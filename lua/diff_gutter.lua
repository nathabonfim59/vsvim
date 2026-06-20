-- lua/diff_gutter.lua
--
-- Clickable VS Code-style git diff gutter.
--
-- Pure logic / reusable API (no side-effects). Wired up in `lua/plugins.lua`
-- after `mini.diff` is loaded. See AGENTS.md for the lua/ vs plugin/ split.
--
-- Behavior:
--   - Left-click a sign in the sign column to open a floating hunk preview.
--   - Inside the float press `d` to discard the hunk, `q` or `<Esc>` to close.
--   - The float has two clickable buttons at the bottom of its content area:
--     "Discard" (red) and "Close" (gray). Left-click either to act.
--   - Right-click a sign to discard the hunk directly (no preview).
--
-- This is built on `mini.diff`'s hunk data (`MiniDiff.get_buf_data()`), so the
-- indicators, preview contents, and reset logic all stay consistent with the
-- Git source mini.diff already maintains.

local M = {}

-- Close a floating preview window and delete its scratch buffer.
local function close_float(win_id, buf_id)
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
	end
	if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
		vim.api.nvim_buf_delete(buf_id, { force = true })
	end
end

-- Find the mini.diff hunk covering the given 1-indexed buffer line.
local function hunk_at_line(buf_data, line)
	for _, h in ipairs(buf_data.hunks or {}) do
		if h.type == "delete" then
			if h.buf_start == line then
				return h
			end
		elseif h.buf_start <= line and line <= h.buf_start + h.buf_count - 1 then
			return h
		end
	end
	return nil
end

-- Build a unified-diff-style preview for a hunk.
local function make_preview(buf_id, hunk)
	local buf_data = MiniDiff.get_buf_data(buf_id)
	local ref_text = buf_data and buf_data.ref_text or ""
	local ref_lines = vim.split(ref_text, "\n")

	local buf_lines = vim.api.nvim_buf_get_lines(buf_id, hunk.buf_start - 1, hunk.buf_start + hunk.buf_count - 1, false)

	local lines = {}
	table.insert(
		lines,
		string.format("@@ -%d,%d +%d,%d @@", hunk.ref_start, hunk.ref_count, hunk.buf_start, hunk.buf_count)
	)
	for i = hunk.ref_start, hunk.ref_start + hunk.ref_count - 1 do
		table.insert(lines, "-" .. (ref_lines[i] or ""))
	end
	for _, l in ipairs(buf_lines) do
		table.insert(lines, "+" .. l)
	end
	return lines
end

-- Reset a single hunk to the reference text (i.e. discard the change).
local function reset_hunk(buf_id, hunk)
	local buf_data = MiniDiff.get_buf_data(buf_id)
	local ref_text = buf_data and buf_data.ref_text
	if not ref_text then
		return
	end

	local ref_lines = vim.split(ref_text, "\n")
	local new_lines = {}
	for i = hunk.ref_start, hunk.ref_start + hunk.ref_count - 1 do
		table.insert(new_lines, ref_lines[i] or "")
	end

	if hunk.type == "add" then
		-- Remove added lines.
		vim.api.nvim_buf_set_lines(buf_id, hunk.buf_start - 1, hunk.buf_start + hunk.buf_count - 1, false, {})
	else
		-- Replace changed/deleted lines with their reference state.
		vim.api.nvim_buf_set_lines(buf_id, hunk.buf_start - 1, hunk.buf_start + hunk.buf_count - 1, false, new_lines)
	end
end

-- Open a floating window previewing the hunk under the cursor/click.
local function open_hunk_preview(buf_id, hunk)
	local lines = make_preview(buf_id, hunk)

	-- Button bar at the top of the float content, padded with blank lines
	-- below. "Discard" (red) and "Close" (gray) are right-aligned.
	local width = math.min(80, math.max(40, vim.o.columns - 10))
	local discard_btn = " Discard "
	local close_btn = " Close "
	local spacing = "  "
	local buttons_text = discard_btn .. spacing .. close_btn
	local pad = math.max(0, width - #buttons_text)
	local button_line = string.rep(" ", pad) .. buttons_text

	-- Layout: [buttons] [blank] [blank] [diff]
	local button_line_nr = 1 -- 1-based line number of the button row
	table.insert(lines, 1, "") -- padding below buttons
	table.insert(lines, 1, "") -- padding below buttons
	table.insert(lines, 1, button_line)

	local pbuf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = pbuf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = pbuf })
	vim.api.nvim_set_option_value("filetype", "diff", { buf = pbuf })

	-- Button geometry (0-based byte columns for extmarks).
	local ns = vim.api.nvim_create_namespace("vsvim_diff_gutter")
	local discard_col0 = pad
	local close_col0 = pad + #discard_btn + #spacing

	-- Selection state: "close" is preselected. Tab cycles between the two;
	-- Enter activates the selected button. The selected button gets
	-- `DiffGutterBtnSel` (→ PmenuSel, blue) instead of its normal color.
	local selected = "close"
	local buttons = { "discard", "close" }

	local function update_button_hl()
		vim.api.nvim_buf_clear_namespace(pbuf, ns, 0, -1)
		local d_hl = selected == "discard" and "DiffGutterBtnSel" or "DiffGutterDiscardBtn"
		local c_hl = selected == "close" and "DiffGutterBtnSel" or "DiffGutterCloseBtn"
		vim.api.nvim_buf_set_extmark(pbuf, ns, button_line_nr - 1, discard_col0, {
			end_col = discard_col0 + #discard_btn,
			hl_group = d_hl,
		})
		vim.api.nvim_buf_set_extmark(pbuf, ns, button_line_nr - 1, close_col0, {
			end_col = close_col0 + #close_btn,
			hl_group = c_hl,
		})
	end

	local height = math.min(20, math.max(3, #lines))
	local win = vim.api.nvim_open_win(pbuf, true, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		anchor = "NW",
		style = "minimal",
		border = "rounded",
		title = " Hunk preview ",
		title_pos = "center",
	})

	local function close()
		close_float(win, pbuf)
	end

	local function discard()
		reset_hunk(buf_id, hunk)
		close()
	end

	-- Activate the currently selected button.
	local function activate()
		if selected == "discard" then
			discard()
		else
			close()
		end
	end

	-- Cycle selection to the next button (Tab) or previous (Shift-Tab).
	local function cycle(dir)
		local idx = 1
		for i, b in ipairs(buttons) do
			if b == selected then
				idx = i
				break
			end
		end
		idx = idx + dir
		if idx < 1 then
			idx = #buttons
		elseif idx > #buttons then
			idx = 1
		end
		selected = buttons[idx]
		update_button_hl()
	end

	-- Apply initial highlight (Close preselected).
	update_button_hl()

	local opts = { buffer = pbuf, silent = true, nowait = true }
	vim.keymap.set("n", "q", close, opts)
	vim.keymap.set("n", "<Esc>", close, opts)
	vim.keymap.set("n", "d", discard, vim.tbl_extend("force", opts, { desc = "Discard hunk" }))
	vim.keymap.set("n", "<Tab>", function()
		cycle(1)
	end, vim.tbl_extend("force", opts, { desc = "Next button" }))
	vim.keymap.set("n", "<S-Tab>", function()
		cycle(-1)
	end, vim.tbl_extend("force", opts, { desc = "Previous button" }))
	vim.keymap.set("n", "<CR>", activate, vim.tbl_extend("force", opts, { desc = "Activate button" }))

	-- Clickable buttons: intercept <LeftMouse> on the button line and dispatch
	-- by column position. Non-button clicks fall through to cursor positioning
	-- so normal mouse behavior (selection, scrolling target) is preserved.
	vim.keymap.set("n", "<LeftMouse>", function()
		local pos = vim.fn.getmousepos()
		if pos.line == button_line_nr then
			local col = pos.column -- 1-based byte column
			if col > discard_col0 and col <= discard_col0 + #discard_btn then
				discard()
				return
			elseif col > close_col0 and col <= close_col0 + #close_btn then
				close()
				return
			end
		end
		vim.api.nvim_win_set_cursor(win, { pos.line, math.max(0, pos.column - 1) })
	end, { buffer = pbuf, silent = true })

	-- Close automatically if the user leaves the float.
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = pbuf,
		once = true,
		callback = close,
	})
end

-- Handler for clicks in the sign column.
local function click_handler(_minwid, _clicks, button, _modifiers)
	local pos = vim.fn.getmousepos()
	if not pos or pos.winid == 0 then
		return
	end

	local ok, MiniDiff = pcall(require, "mini.diff")
	if not ok then
		return
	end

	local buf_id = vim.api.nvim_win_get_buf(pos.winid)
	local buf_data = MiniDiff.get_buf_data(buf_id)
	if not buf_data or not buf_data.hunks or #buf_data.hunks == 0 then
		return
	end

	local hunk = hunk_at_line(buf_data, pos.line)
	if not hunk then
		return
	end

	if button == "l" then
		open_hunk_preview(buf_id, hunk)
	elseif button == "r" then
		reset_hunk(buf_id, hunk)
	end
end

-- Apply the clickable diff gutter.
function M.setup()
	local ok = pcall(require, "mini.diff")
	if not ok then
		vim.notify("diff_gutter: 'mini.diff' not found (run :PackUpdate)", vim.log.levels.ERROR)
		return
	end

	-- Highlights for the float's bottom button bar. All link to existing
	-- groups so they pick up the active colorscheme automatically:
	--   DiffGutterDiscardBtn → DiffDelete  (red bg, destructive action)
	--   DiffGutterCloseBtn   → PmenuSbar   (gray bg, neutral dismissal)
	--   DiffGutterBtnSel     → PmenuSel    (blue bg, keyboard-selected button)
	-- `default = true` lets a colorscheme override them; re-applied on
	-- colorscheme changes because loading a scheme clears existing groups.
	local function define_hl()
		vim.api.nvim_set_hl(0, "DiffGutterDiscardBtn", { default = true, link = "DiffDelete" })
		vim.api.nvim_set_hl(0, "DiffGutterCloseBtn", { default = true, link = "PmenuSbar" })
		vim.api.nvim_set_hl(0, "DiffGutterBtnSel", { default = true, link = "PmenuSel" })
	end
	define_hl()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = define_hl })

	-- Expose Lua handler and create Vimscript wrapper so the 'statuscolumn'
	-- %@ item has a function it can call.
	_G.vsvim_diff_gutter_click = click_handler
	vim.cmd([[
		function! VsvimDiffGutterClick(minwid, clicks, button, modifiers) abort
			call v:lua.vsvim_diff_gutter_click(a:minwid, a:clicks, a:button, a:modifiers)
		endfunction
	]])

	-- Signs first, then line number, then a small gap. Clicks on the sign area
	-- open the hunk preview; clicks on the line number fall through normally.
	vim.opt.statuscolumn = '%@VsvimDiffGutterClick@%s%X%l '
end

return M
