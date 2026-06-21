-- lua/modal.lua
--
-- Reusable modal dialog module with optional clickable buttons.
--
-- Pure logic / reusable API (no side-effects). Used by diff_gutter.lua and
-- sidebar.lua. See AGENTS.md for the lua/ vs plugin/ split.
--
-- Supports:
--   - Multiple positions: "center", "cursor", "bottom", or custom {row, col}
--   - Optional clickable button bar (top or bottom, left/right/center aligned)
--     with Tab/Shift-Tab navigation, Enter to activate, mouse click support
--   - Optional backdrop (dimming overlay)
--   - Custom keymaps mapped to action strings
--   - Focus guard (prevents other code from stealing focus while open)
--   - Non-focus mode: open the float without stealing focus from the
--     current buffer, so no BufLeave/WinLeave fires on it (avoids
--     autowrite and other leave-triggered side effects)
--   - on_open/on_close callbacks for caller-specific setup/cleanup
--   - Auto-close on WinLeave/BufLeave

local M = {}

-- Unique counter for augroup names so multiple modals don't clobber each
-- other's autocmds.
local modal_seq = 0

-- Close a window and delete its buffer if still valid.
local function close_win(win_id, buf_id)
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
	end
	if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
		vim.api.nvim_buf_delete(buf_id, { force = true })
	end
end

-- Build the button bar line text and compute each button's byte column range.
-- Returns (button_line_text, positions) where positions[i] = { col0, end_col }
-- (0-based byte columns for extmarks).
local function build_button_bar(items, width, align, spacing)
	local parts = {}
	for _, item in ipairs(items) do
		table.insert(parts, item.label)
	end
	local buttons_text = table.concat(parts, spacing)

	local pad
	if align == "right" then
		pad = math.max(0, width - #buttons_text)
	elseif align == "center" then
		pad = math.max(0, math.floor((width - #buttons_text) / 2))
	else -- left
		pad = 0
	end

	local button_line = string.rep(" ", pad) .. buttons_text

	local positions = {}
	local col = pad
	for i, item in ipairs(items) do
		positions[i] = { col0 = col, end_col = col + #item.label }
		col = col + #item.label + #spacing
	end

	return button_line, positions
end

--- Open a modal window.
--- @param opts table Modal configuration.
---   title         string|table  Window title (string or { {text, hl} } table).
---   lines         string[]      Content lines (the modal body).
---   position      string|table  "center" (default), "cursor", "bottom", or {row, col}.
---   width         number        Fixed width (auto-calculated if omitted).
---   max_width     number        Maximum width (default 80).
---   max_height    number        Maximum height (default 20).
---   min_width     number        Minimum width (default 20).
---   border        string        Border style (default "rounded").
---   filetype      string        Buffer filetype (optional).
---   win_options   table         Window-local options to apply.
---   backdrop      boolean       Show a dimming backdrop (default false).
---   backdrop_hl   string        Backdrop highlight group (default "NormalFloat").
---   editable      boolean       Allow editing the modal body (default false).
---                 When false (the default) the modal buffer is made fully
---                 non-editable: 'modifiable' off (:help 'modifiable', E21)
---                 blocks text changes, 'readonly' on (:help 'readonly')
---                 blocks accidental writes, and buftype="nofile"
---                 (:help 'buftype') detaches it from disk. Set to true for
---                 input-style modals where the user types into the buffer.
---   noautocmd     boolean       Pass noautocmd=true to nvim_open_win (default false).
---   focus         boolean       Steal focus to the modal window (default true).
---                 When false, the float opens without entering it, the
---                 current buffer keeps focus, no BufLeave/WinLeave fires,
---                 and keymaps are set on the current buffer instead of the
---                 modal buffer. Useful when the caller's buffer has unsaved
---                 changes and autowrite or other leave-triggered autocmds
---                 must not fire.
---   focus_guard   boolean       Prevent focus from leaving the modal (default false).
---   buttons       table         Button bar config (optional). See below.
---   keymaps       table         { [key] = action_string } mappings (optional).
---   on_action     function      Called (scheduled) after close with the action string.
---   on_open       function      Called after the window is created. Receives ctx.
---   on_close      function      Called before windows are closed. Receives ctx.
---
---   buttons = {
---     position    = "top"|"bottom"  (default "bottom")
---     align       = "left"|"right"|"center"  (default "right")
---     padding     = number  blank lines between button bar and content (default 2)
---     spacing     = string  spacing between buttons (default "  ")
---     selected_hl = string  highlight for the keyboard-selected button (default "PmenuSel")
---     items = {
---       { label = " Discard ", hl = "DiffGutterDiscardBtn", action = "discard" },
---       { label = " Close ", hl = "DiffGutterCloseBtn", action = "close", default = true },
---     },
---   }
---
--- @return table ctx  { win, buf, backdrop_win, close, run_action }
function M.open(opts)
	opts = opts or {}
	local lines = vim.list_extend({}, opts.lines or {})
	local focus = opts.focus ~= false -- default true
	local editable = opts.editable == true -- default false

	-- In non-focus mode, keymaps are set on the current buffer (saved here)
	-- instead of the modal buffer, so the float never steals focus.
	local orig_buf = focus and nil or vim.api.nvim_get_current_buf()
	local orig_win = focus and nil or vim.api.nvim_get_current_win()

	-- Compute width from content if not explicitly given.
	local max_width = opts.max_width or 80
	local min_width = opts.min_width or 20
	local width = opts.width
	if not width then
		width = math.min(max_width, math.max(min_width, vim.o.columns - 10))
		for _, line in ipairs(lines) do
			width = math.max(width, math.min(max_width, #line + 2))
		end
	end

	-- --- Set up button bar ---
	local buttons_config = opts.buttons
	local button_positions = nil
	local button_line_nr = nil
	local selected = nil
	local ns = nil

	if buttons_config and buttons_config.items and #buttons_config.items > 0 then
		ns = vim.api.nvim_create_namespace("vsvim-modal")
		local btn_pos = buttons_config.position or "bottom"
		local btn_padding = buttons_config.padding or 2
		local btn_align = buttons_config.align or "right"
		local btn_spacing = buttons_config.spacing or "  "
		local button_line_text, positions =
			build_button_bar(buttons_config.items, width, btn_align, btn_spacing)
		button_positions = positions

		-- Find default-selected button (first one with default = true).
		for i, item in ipairs(buttons_config.items) do
			if item.default then
				selected = i
				break
			end
		end
		if not selected then
			selected = 1
		end

		if btn_pos == "top" then
			-- Layout: [button_line] [padding...] [content]
			button_line_nr = 1
			for _ = 1, btn_padding do
				table.insert(lines, 1, "")
			end
			table.insert(lines, 1, button_line_text)
		else
			-- Layout: [content] [padding...] [button_line]
			button_line_nr = #lines + btn_padding + 1
			for _ = 1, btn_padding do
				table.insert(lines, "")
			end
			table.insert(lines, button_line_text)
		end
	end

	local max_height = opts.max_height or 20
	local height = math.min(max_height, math.max(3, #lines))

	-- --- Compute window position ---
	local relative = "editor"
	local row, col
	if opts.position == "cursor" then
		relative = "cursor"
		row = 1
		col = 0
	elseif opts.position == "center" or opts.position == nil then
		row = math.floor((vim.o.lines - height) / 2)
		col = math.floor((vim.o.columns - width) / 2)
	elseif opts.position == "bottom" then
		local has_tabline = vim.o.showtabline == 2
			or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
		local has_statusline = vim.o.laststatus > 0
		local avail = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
		row = math.max(0, avail - height - 1)
		col = math.floor((vim.o.columns - width) / 2)
	elseif type(opts.position) == "table" then
		row = opts.position.row or 0
		col = opts.position.col or 0
	else
		row = math.floor((vim.o.lines - height) / 2)
		col = math.floor((vim.o.columns - width) / 2)
	end

	-- --- Create backdrop (optional) ---
	local backdrop_win, backdrop_buf
	if opts.backdrop then
		backdrop_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[backdrop_buf].buftype = "nofile"
		vim.bo[backdrop_buf].bufhidden = "wipe"
		vim.bo[backdrop_buf].swapfile = false
		-- Fully non-editable: 'modifiable' off blocks text changes
		-- (:help 'modifiable', E21), 'readonly' on blocks accidental
		-- writes (:help 'readonly'). Combined with buftype="nofile"
		-- (:help 'buftype') the buffer can't be written or altered.
		vim.bo[backdrop_buf].modifiable = false
		vim.bo[backdrop_buf].readonly = true

		backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
			relative = "editor",
			row = 0,
			col = 0,
			width = vim.o.columns,
			height = vim.o.lines,
			style = "minimal",
			focusable = false,
			zindex = 100,
			noautocmd = true,
		})
		if backdrop_win ~= 0 then
			vim.wo[backdrop_win].winhighlight = "Normal:" .. (opts.backdrop_hl or "NormalFloat")
			vim.wo[backdrop_win].winblend = 0
		end
	end

	-- --- Create modal buffer ---
	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
	vim.bo[buf_id].buftype = "nofile"
	vim.bo[buf_id].bufhidden = "wipe"
	vim.bo[buf_id].swapfile = false
	-- Fully non-editable by default: 'modifiable' off blocks text changes
	-- (:help 'modifiable', E21), 'readonly' on blocks accidental writes
	-- (:help 'readonly'). Combined with buftype="nofile" (:help 'buftype')
	-- the buffer can't be written or altered. Callers that need an
	-- input-style modal pass opts.editable = true.
	if not editable then
		vim.bo[buf_id].modifiable = false
		vim.bo[buf_id].readonly = true
	end
	if opts.filetype then
		vim.bo[buf_id].filetype = opts.filetype
	end

	-- --- Create modal window ---
	local win_config = {
		relative = relative,
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = opts.border or "rounded",
		zindex = 150,
	}
	if opts.noautocmd then
		win_config.noautocmd = true
	end
	if opts.title then
		win_config.title = opts.title
		win_config.title_pos = "center"
	end

	local win_id = vim.api.nvim_open_win(buf_id, focus, win_config)

	-- Apply caller-specified window-local options.
	if opts.win_options then
		for k, v in pairs(opts.win_options) do
			vim.wo[win_id][k] = v
		end
	end

	-- --- Button highlights ---
	local function update_button_hl()
		if not ns or not button_positions then
			return
		end
		vim.api.nvim_buf_clear_namespace(buf_id, ns, 0, -1)
		local selected_hl = buttons_config.selected_hl or "PmenuSel"
		for i, pos in ipairs(button_positions) do
			local hl = (i == selected) and selected_hl or buttons_config.items[i].hl
			if hl then
				vim.api.nvim_buf_set_extmark(buf_id, ns, button_line_nr - 1, pos.col0, {
					end_col = pos.end_col,
					hl_group = hl,
				})
			end
		end
	end

	if buttons_config then
		update_button_hl()
	end

	-- --- State and cleanup ---
	modal_seq = modal_seq + 1
	local augroup_name = "vsvim-modal-" .. modal_seq
	local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
	local closed = false
	local orig_set_current_win = nil
	local set_keys = {} -- keys set on orig_buf (non-focus mode) for cleanup

	local ctx = {
		win = win_id,
		buf = buf_id,
		backdrop_win = backdrop_win,
	}

	local function close()
		if closed then
			return
		end
		closed = true

		-- Restore focus guard before closing so close-time focus changes work.
		if orig_set_current_win then
			vim.api.nvim_set_current_win = orig_set_current_win
			orig_set_current_win = nil
		end

		-- In non-focus mode, clean up keymaps set on the original buffer.
		-- (In focus mode, keymaps are on the modal buffer which gets deleted.)
		if not focus and orig_buf and vim.api.nvim_buf_is_valid(orig_buf) then
			for _, key in ipairs(set_keys) do
				pcall(vim.keymap.del, "n", key, { buffer = orig_buf })
			end
		end

		pcall(vim.api.nvim_del_augroup_by_id, augroup)
		if opts.on_close then
			pcall(opts.on_close, ctx)
		end
		close_win(win_id, buf_id)
		if backdrop_win and backdrop_win ~= 0 then
			close_win(backdrop_win, backdrop_buf)
		end
		vim.cmd("redraw")
	end

	local function run_action(action)
		close()
		if action and opts.on_action then
			vim.schedule(function()
				local ok, err = pcall(opts.on_action, action)
				if not ok then
					vim.notify("modal: " .. tostring(err), vim.log.levels.ERROR)
				end
			end)
		end
	end

	ctx.close = close
	ctx.run_action = run_action

	-- --- Keymaps ---
	-- In non-focus mode, keymaps are set on the original buffer (which keeps
	-- focus) instead of the modal buffer. In focus mode, they're set on the
	-- modal buffer as before.
	local km_target = focus and buf_id or orig_buf
	local km_opts = { buffer = km_target, silent = true, nowait = true, noremap = true }

	-- Helper: set a buffer-local keymap and track it for cleanup (non-focus).
	local function set_key(key, fn, o)
		vim.keymap.set("n", key, fn, o)
		if not focus then
			table.insert(set_keys, key)
		end
	end

	-- Button navigation keymaps (only when buttons are present).
	if buttons_config then
		local function cycle(dir)
			selected = selected + dir
			if selected < 1 then
				selected = #buttons_config.items
			elseif selected > #buttons_config.items then
				selected = 1
			end
			update_button_hl()
		end

		set_key("<Tab>", function()
			cycle(1)
		end, vim.tbl_extend("force", km_opts, { desc = "Next button" }))
		set_key("<S-Tab>", function()
			cycle(-1)
		end, vim.tbl_extend("force", km_opts, { desc = "Previous button" }))
		set_key("<CR>", function()
			run_action(buttons_config.items[selected].action)
		end, vim.tbl_extend("force", km_opts, { desc = "Activate button" }))

		-- hjkl navigation: h/k move to the previous button, l/j to the next.
		-- Only active when buttons are present (a button is always selected).
		set_key("h", function()
			cycle(-1)
		end, vim.tbl_extend("force", km_opts, { desc = "Previous button" }))
		set_key("l", function()
			cycle(1)
		end, vim.tbl_extend("force", km_opts, { desc = "Next button" }))
		set_key("k", function()
			cycle(-1)
		end, vim.tbl_extend("force", km_opts, { desc = "Previous button" }))
		set_key("j", function()
			cycle(1)
		end, vim.tbl_extend("force", km_opts, { desc = "Next button" }))

		-- Mouse click on buttons: dispatch by column position. Non-button
		-- clicks fall through to normal cursor positioning.
		set_key("<LeftMouse>", function()
			local pos = vim.fn.getmousepos()
			if pos.winid == win_id and pos.line == button_line_nr then
				local col_click = pos.column
				for i, p in ipairs(button_positions) do
					if col_click > p.col0 and col_click <= p.end_col then
						run_action(buttons_config.items[i].action)
						return
					end
				end
			end
			-- In focus mode, move cursor in the modal window.
			-- In non-focus mode, let the click fall through to the original window.
			if focus and pos.winid == win_id then
				vim.api.nvim_win_set_cursor(win_id, { pos.line, math.max(0, pos.column - 1) })
			end
		end, { buffer = km_target, silent = true })
	end

	-- User-defined keymaps (each maps to an action string).
	if opts.keymaps then
		for key, action in pairs(opts.keymaps) do
			set_key(key, function()
				run_action(action)
			end, km_opts)
		end
	end

	-- Auto-close:
	--   Focus mode: close when the modal buffer is left (WinLeave/BufLeave).
	--   Non-focus mode: close when the original buffer is left (the float is
	--   not focused, so its BufLeave never fires, we watch the original buf).
	if focus then
		vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
			group = augroup,
			buffer = buf_id,
			once = true,
			callback = close,
		})
	else
		vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
			group = augroup,
			buffer = orig_buf,
			once = true,
			callback = close,
		})
		-- Also close if the original window is closed.
		vim.api.nvim_create_autocmd("WinClosed", {
			group = augroup,
			pattern = tostring(orig_win),
			once = true,
			callback = close,
		})
	end

	-- --- Focus guard (optional) ---
	-- Steals focus on open and prevents other code (e.g. mini.files' focus-loss
	-- timer) from pulling focus away while the modal is open.
	if opts.focus_guard then
		local function steal_focus()
			if vim.api.nvim_win_is_valid(win_id) then
				pcall(vim.api.nvim_set_current_win, win_id)
			end
		end
		steal_focus()
		vim.schedule(steal_focus)

		orig_set_current_win = vim.api.nvim_set_current_win
		vim.api.nvim_set_current_win = function(win)
			if not vim.api.nvim_win_is_valid(win_id) then
				vim.api.nvim_set_current_win = orig_set_current_win
				return orig_set_current_win(win)
			end
			if win == win_id then
				return orig_set_current_win(win)
			end
			-- Ignore external attempts to move focus away from the modal.
		end
	end

	-- --- on_open callback ---
	if opts.on_open then
		pcall(opts.on_open, ctx)
	end

	return ctx
end

return M
