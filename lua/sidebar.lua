-- lua/sidebar.lua
--
-- VS Code-style sidebar filepicker built on `mini.files`.
--
-- Pure logic / reusable API (no side-effects). Wired up in `lua/plugins.lua`
-- via `require("sidebar").setup()` after `mini.files` is available.
-- See AGENTS.md for the lua/ vs plugin/ split rationale.

local M = {}

-- Compute the height of a full-height sidebar window.
local function sidebar_height()
	local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
	local has_statusline = vim.o.laststatus > 0
	return vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
end

-- Style a mini.files window so it looks like a docked left sidebar.
-- mini.files always uses floating windows; this pins the float to the left
-- edge with no border and full editor height.
local function style_sidebar_window(win_id)
	if not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local ok, MiniFiles = pcall(require, "mini.files")
	if not ok then
		return
	end

	local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
	local width = MiniFiles.config.windows.width_focus

	vim.api.nvim_win_set_config(win_id, {
		relative = "editor",
		anchor = "NW",
		row = has_tabline and 1 or 0,
		col = 0,
		width = width,
		height = sidebar_height(),
		border = "none",
	})
end

-- Return the directory path currently shown in a mini.files buffer.
local function get_buffer_dir(buf_id, MiniFiles)
	-- Try the first real entry's parent.
	local ok, entry = pcall(MiniFiles.get_fs_entry, buf_id, 1)
	if ok and entry and entry.path then
		return vim.fn.fnamemodify(entry.path, ":h")
	end

	-- Fall back to the explorer state window list.
	local state = MiniFiles.get_explorer_state()
	if not state then
		return nil
	end
	for _, win in ipairs(state.windows) do
		if vim.api.nvim_win_get_buf(win.win_id) == buf_id then
			return win.path
		end
	end
	return nil
end

-- Insert a synthetic ".." entry at the top of a directory buffer so users can
-- navigate up without reaching for the `h` key.
local function add_parent_entry(buf_id, MiniFiles)
	local dir_path = get_buffer_dir(buf_id, MiniFiles)
	if not dir_path then
		return
	end

	local parent = vim.fn.fnamemodify(dir_path, ":h")
	if parent == dir_path then
		return
	end

	-- Avoid adding a second ".." if the buffer was already modified.
	local first_line = vim.api.nvim_buf_get_lines(buf_id, 0, 1, false)[1] or ""
	if first_line:match("^/%d+/%.%.$") then
		return
	end

	-- Insert at the top without replacing existing lines, so mini.files' highlight
	-- extmarks are preserved and simply shift down by one row.
	vim.api.nvim_buf_set_lines(buf_id, 0, 0, false, { "/0/.." })

	-- Color the synthetic ".." entry like a directory.
	local ns = vim.api.nvim_create_namespace("vsvim-sidebar")
	vim.api.nvim_buf_add_highlight(buf_id, ns, "MiniFilesDirectory", 0, 0, -1)

	-- Keep the cursor on the same real entry it was on before the insertion.
	local win_id = vim.fn.bufwinid(buf_id)
	if win_id ~= -1 then
		local cursor = vim.api.nvim_win_get_cursor(win_id)
		cursor[1] = cursor[1] + 1
		pcall(vim.api.nvim_win_set_cursor, win_id, cursor)
	end
end

-- Add a small amount of left padding to every entry so the sidebar content does
-- not sit flush against the window edge, matching VS Code's explorer spacing.
local padding_ns = vim.api.nvim_create_namespace("vsvim-sidebar-padding")
local function add_left_padding(buf_id)
	vim.api.nvim_buf_clear_namespace(buf_id, padding_ns, 0, -1)

	local line_count = vim.api.nvim_buf_line_count(buf_id)
	for i = 1, line_count do
		local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1] or ""
		if #line > 0 then
			vim.api.nvim_buf_set_extmark(buf_id, padding_ns, i - 1, 0, {
				virt_text = { { " ", "Normal" } },
				virt_text_pos = "inline",
				right_gravity = false,
			})
		end
	end
end

-- Open/expand the entry under cursor, treating the synthetic ".." entry as
-- "go to parent directory".
local function go_in_or_up(MiniFiles)
	local line = vim.fn.getline(".")
	if line:match("^/%d+/%.%.$") then
		MiniFiles.go_out()
	else
		MiniFiles.go_in()
	end
end

-- Toggle the sidebar filepicker.
-- Closes it if open, otherwise opens a fresh explorer at the current working
-- directory. This matches VS Code's Ctrl+B "toggle side bar" behaviour.
function M.toggle()
	local ok, MiniFiles = pcall(require, "mini.files")
	if not ok then
		vim.notify("sidebar: 'mini.files' not found (run :PackUpdate)", vim.log.levels.ERROR)
		return
	end

	-- `MiniFiles.close()` returns:
	--   - `true`  -> closed successfully
	--   - `false` -> user cancelled (pending edits)
	--   - `nil`   -> nothing was open
	local closed = MiniFiles.close()
	if closed == nil then
		MiniFiles.open(vim.fn.getcwd(), false)
	end
end

-- Open the sidebar at the given path (defaults to cwd).
function M.open(path)
	local ok, MiniFiles = pcall(require, "mini.files")
	if not ok then
		vim.notify("sidebar: 'mini.files' not found (run :PackUpdate)", vim.log.levels.ERROR)
		return
	end
	MiniFiles.open(path or vim.fn.getcwd(), false)
end

-- Close the sidebar if open.
function M.close()
	local ok, MiniFiles = pcall(require, "mini.files")
	if not ok then
		return
	end
	MiniFiles.close()
end

-- Apply VS Code-style sidebar configuration to `mini.files`.
function M.setup(opts)
	local has_mini, mini_files = pcall(require, "mini.files")
	if not has_mini then
		vim.notify("sidebar: 'mini.files' not found (run :PackUpdate)", vim.log.levels.ERROR)
		return
	end

	mini_files.setup(vim.tbl_deep_extend("force", {
		-- Show a single focused directory column for a sidebar feel.
		windows = {
			max_number = 1,
			preview = false,
			width_focus = 32,
			width_nofocus = 32,
			width_preview = 25,
		},
		mappings = {
			close = "q",
			go_in = "l",
			go_in_plus = "L",
			go_out = "h",
			go_out_plus = "H",
			mark_goto = "'",
			mark_set = "m",
			reset = "<BS>",
			reveal_cwd = "@",
			show_help = "g?",
			synchronize = "=",
			trim_left = "<",
			trim_right = ">",
		},
	}, opts or {}))

	local group = vim.api.nvim_create_augroup("vsvim-sidebar", { clear = true })

	-- Allow toggling the sidebar from inside mini.files buffers too.
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MiniFilesBufferCreate",
		callback = function(args)
			local buf_id = args.data.buf_id

			vim.keymap.set("n", "<C-b>", function()
				M.toggle()
			end, { buffer = buf_id, desc = "Toggle sidebar filepicker", silent = true })

			-- `l` opens/expands; on the synthetic ".." entry it goes up instead.
			vim.keymap.set("n", "l", function()
				go_in_or_up(mini_files)
			end, { buffer = buf_id, desc = "Open/expand or go to parent", silent = true })

			-- Single-click to expand folders / open files, like VS Code's explorer.
			vim.keymap.set("n", "<LeftRelease>", function()
				local pos = vim.fn.getmousepos()
				if pos.winid == 0 or pos.line == 0 then
					return
				end
				vim.api.nvim_set_current_win(pos.winid)
				vim.api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
				go_in_or_up(mini_files)
			end, { buffer = buf_id, desc = "Open/expand entry under mouse", silent = true })
		end,
	})

	-- Add a synthetic ".." entry at the top of each directory listing and keep
	-- a small left padding on every line.
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MiniFilesBufferUpdate",
		callback = function(args)
			add_parent_entry(args.data.buf_id, mini_files)
			add_left_padding(args.data.buf_id)
		end,
	})

	-- Pin every mini.files window to the left edge as a docked sidebar.
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MiniFilesWindowUpdate",
		callback = function(args)
			style_sidebar_window(args.data.win_id)
		end,
	})
end

return M
