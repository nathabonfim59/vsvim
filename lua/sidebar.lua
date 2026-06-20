-- lua/sidebar.lua
--
-- VS Code-style sidebar filepicker built on `mini.files`.
--
-- Pure logic / reusable API (no side-effects). Wired up in `lua/plugins.lua`
-- via `require("sidebar").setup()` after `mini.files` is available.
-- See AGENTS.md for the lua/ vs plugin/ split rationale.

local M = {}

-- Stored original `MiniFiles.close()` so we can wrap it with our custom
-- confirmation popup without touching the plugin source.
local orig_mini_files_close = nil

-- Compute the height of a full-height sidebar window.
local function sidebar_height()
	local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
	local has_statusline = vim.o.laststatus > 0
	return vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
end

-- Style a mini.files window so it looks like a docked left sidebar.
-- mini.files always uses floating windows; this pins the float to the left
-- edge with a single border and full editor height.
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

	-- Account for the top and bottom border rows so the float fits between the
	-- tabline (if any) and the status/command line.
	local height = math.max(1, sidebar_height() - 2)

	vim.api.nvim_win_set_config(win_id, {
		relative = "editor",
		anchor = "NW",
		row = has_tabline and 1 or 0,
		col = 0,
		width = width,
		height = height,
		border = "single",
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

-- Access `mini.files`' private helper table `H`. This is needed so we can
-- register synthetic ".." entries in its path index, which prevents them from
-- being treated as pending file-system changes.
local function get_mini_files_helpers()
	local ok, MiniFiles = pcall(require, "mini.files")
	if not ok then
		return nil
	end
	for _, fn in pairs(MiniFiles) do
		if type(fn) == "function" then
			for i = 1, debug.getinfo(fn, "u").nups do
				local name, val = debug.getupvalue(fn, i)
				if name == "H" then
					return val
				end
			end
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
	if first_line:match("^/%d+/*%.%.$") then
		return
	end

	-- Register a synthetic path for the parent directory so mini.files treats the
	-- ".." entry as already in sync (path_from == path_to) instead of a create.
	local synthetic_path = dir_path .. "/.."
	local path_id = 0
	local H = get_mini_files_helpers()
	if H and H.path_index then
		path_id = H.path_index[synthetic_path]
		if path_id == nil then
			path_id = #H.path_index + 1
			H.path_index[path_id] = synthetic_path
			H.path_index[synthetic_path] = path_id
		end
	end

	-- Insert at the top without replacing existing lines, so mini.files' highlight
	-- extmarks are preserved and simply shift down by one row. The double slash
	-- keeps `mini.files`' line parsing happy (it expects an icon separator).
	vim.api.nvim_buf_set_lines(buf_id, 0, 0, false, { "/" .. path_id .. "//.." })

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
	if line:match("^/%d+/*%.%.$") then
		MiniFiles.go_out()
	else
		MiniFiles.go_in()
	end
end

-- Run `fn` while `vim.fn.confirm` is overridden to always return `result`.
-- Restores the original function afterwards. Used to drive `mini.files'
-- built-in confirmation prompts programmatically.
local function with_confirm_result(result, fn)
	local orig_confirm = vim.fn.confirm
	vim.fn.confirm = function()
		return result
	end
	local ok, res = pcall(fn)
	vim.fn.confirm = orig_confirm
	if not ok then
		error(res)
	end
	return res
end

-- Probe `mini.files` for pending file system changes without applying them.
-- Returns the human-readable change summary (the message `mini.files` would
-- show in its own confirm dialog), or `nil` if there is nothing pending.
local function get_pending_changes(MiniFiles)
	local captured = nil
	local orig_confirm = vim.fn.confirm
	vim.fn.confirm = function(msg)
		captured = msg
		return 3 -- Cancel
	end
	pcall(MiniFiles.synchronize)
	vim.fn.confirm = orig_confirm
	return captured
end

-- Highlight group for the modal backdrop. Linked lazily so it plays nicely
-- with any colorscheme already loaded.
local function ensure_modal_highlights()
	if vim.fn.hlID("VsvimSidebarBackdrop") == 0 then
		vim.api.nvim_set_hl(0, "VsvimSidebarBackdrop", { link = "NormalFloat", default = true })
	end
	if vim.fn.hlID("VsvimSidebarModalTitle") == 0 then
		vim.api.nvim_set_hl(0, "VsvimSidebarModalTitle", { link = "FloatTitle", default = true })
	end
end

-- Show a centered, focused modal describing pending changes and ask whether to
-- apply them, discard them, or cancel the close operation.
--
-- This is implemented as a "proper" modal: it steals focus on open, closes
-- itself before running the chosen action, and cleans up its autocmds and
-- backdrop automatically.
local function show_confirm_modal(change_lines, on_apply, on_discard)
	ensure_modal_highlights()

	local MiniFiles = require("mini.files")

	local lines = {
		"Pending file system changes",
		"",
	}
	vim.list_extend(lines, change_lines)
	vim.list_extend(lines, {
		"",
		" [y/Enter] Apply changes and close",
		" [n]       Discard changes and close",
		" [q/Esc]   Cancel and keep filepicker open",
	})

	local width = math.min(70, math.max(45, vim.o.columns - 12))
	local height = math.min(#lines + 2, vim.o.lines - 6)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Backdrop: full-screen non-focusable float behind the modal. It visually
	-- dims the rest of the UI and prevents accidental interaction with the
	-- filepicker while the modal is open.
	local backdrop_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[backdrop_buf].buftype = "nofile"
	vim.bo[backdrop_buf].bufhidden = "wipe"
	vim.bo[backdrop_buf].swapfile = false
	vim.bo[backdrop_buf].modifiable = false

	local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
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
		vim.wo[backdrop_win].winhighlight = "Normal:VsvimSidebarBackdrop"
		vim.wo[backdrop_win].winblend = 0
	end

	-- Modal content buffer.
	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
	vim.bo[buf_id].buftype = "nofile"
	vim.bo[buf_id].bufhidden = "wipe"
	vim.bo[buf_id].swapfile = false
	vim.bo[buf_id].modifiable = false
	vim.bo[buf_id].filetype = "vsvim-sidebar-confirm"

	-- Modal window. `enter = true` focuses it; `noautocmd = true` keeps
	-- `mini.files` autocommands from interfering during creation.
	local win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = { { " Confirm Changes ", "VsvimSidebarModalTitle" } },
		title_pos = "center",
		zindex = 150,
		noautocmd = true,
	})

	vim.wo[win_id].cursorline = true
	vim.wo[win_id].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"

	-- Place cursor on the first actionable line ("Apply").
	local action_line = 1
	for i, line in ipairs(lines) do
		if line:match("^ %[yY%]") or line:match("^ %[[yY]%/") then
			action_line = i
			break
		end
	end
	pcall(vim.api.nvim_win_set_cursor, win_id, { action_line, 0 })

	-- Force focus now and again after the current event loop tick. This handles
	-- cases where the modal is opened from a keymap or autocommand that would
	-- otherwise steal focus back.
	local function steal_focus()
		if vim.api.nvim_win_is_valid(win_id) then
			vim.api.nvim_set_current_win(win_id)
		end
	end
	steal_focus()
	vim.schedule(steal_focus)

	-- Temporarily override `nvim_set_current_win` so nothing can pull focus away
	-- from the modal while it is open. This is needed because `mini.files` runs
	-- a focus-loss timer that calls `MiniFiles.close()` and then restores focus
	-- to the previously focused window; without this guard the modal would be
	-- dismissed immediately (e.g. when clicking outside the filetree).
	local orig_set_current_win = vim.api.nvim_set_current_win
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

	-- Stop `mini.files`' focus-loss timer while the modal is open. Otherwise the
	-- timer would keep calling `MiniFiles.close()` every second (the modal buffer
	-- is not `minifiles`), and it could reopen a second modal in the gap between
	-- closing this one and running the chosen action.
	local H = get_mini_files_helpers()
	local focus_timer = H and H.timers and H.timers.focus
	if focus_timer and type(focus_timer.stop) == "function" then
		pcall(focus_timer.stop, focus_timer)
	end

	-- Cleanup state.
	local closed = false
	local augroup = vim.api.nvim_create_augroup("vsvim-sidebar-confirm", { clear = true })

	local function close_windows()
		if closed then
			return
		end
		closed = true
		vim.api.nvim_set_current_win = orig_set_current_win
		pcall(vim.api.nvim_del_augroup_by_id, augroup)
		if vim.api.nvim_win_is_valid(win_id) then
			pcall(vim.api.nvim_win_close, win_id, true)
		end
		if backdrop_win ~= 0 and vim.api.nvim_win_is_valid(backdrop_win) then
			pcall(vim.api.nvim_win_close, backdrop_win, true)
		end
		-- Resume focus-loss tracking if the filepicker is still open (e.g. the
		-- user cancelled the modal). If an action closed the filepicker, this is
		-- a no-op because `explorer_track_lost_focus` only starts the timer.
		if H and H.explorer_track_lost_focus and MiniFiles.get_explorer_state() then
			pcall(H.explorer_track_lost_focus)
		end
		vim.cmd("redraw")
	end

	-- Close the modal automatically if the user somehow leaves it (e.g. mouse
	-- click outside, `<C-w>w`, or another plugin switching windows).
	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
		group = augroup,
		buffer = buf_id,
		once = true,
		callback = close_windows,
	})

	-- Helper that closes the modal immediately and runs the chosen action in the
	-- next tick, after Neovim has finished processing the keymap.
	local function run_action(action)
		close_windows()
		vim.schedule(function()
			local ok, err = pcall(action)
			if not ok then
				vim.notify("sidebar: " .. tostring(err), vim.log.levels.ERROR)
			end
		end)
	end

	local opts = { buffer = buf_id, silent = true, nowait = true, noremap = true }

	vim.keymap.set("n", "y", function()
		run_action(on_apply)
	end, vim.tbl_extend("force", opts, { desc = "Apply changes and close filepicker" }))

	vim.keymap.set("n", "<CR>", function()
		run_action(on_apply)
	end, vim.tbl_extend("force", opts, { desc = "Apply changes and close filepicker" }))

	vim.keymap.set("n", "n", function()
		run_action(on_discard)
	end, vim.tbl_extend("force", opts, { desc = "Discard changes and close filepicker" }))

	vim.keymap.set("n", "q", close_windows, vim.tbl_extend("force", opts, { desc = "Cancel and keep filepicker open" }))
	vim.keymap.set("n", "<Esc>", close_windows, vim.tbl_extend("force", opts, { desc = "Cancel and keep filepicker open" }))
	vim.keymap.set("n", "<C-c>", close_windows, vim.tbl_extend("force", opts, { desc = "Cancel and keep filepicker open" }))
end

-- Close the sidebar, but show a centered confirmation modal if there are
-- pending file system changes (deletions, renames, moves, etc.).
local function close_with_confirmation(MiniFiles)
	local changes_msg = get_pending_changes(MiniFiles)

	if changes_msg == nil then
		if orig_mini_files_close ~= nil then
			pcall(orig_mini_files_close)
		end
		return
	end

	local change_lines = vim.split(changes_msg, "\n", { plain = true })

	local function apply_and_close()
		with_confirm_result(1, function()
			MiniFiles.synchronize()
		end)
		if orig_mini_files_close ~= nil then
			pcall(orig_mini_files_close)
		end
	end

	local function discard_and_close()
		with_confirm_result(1, function()
			if orig_mini_files_close ~= nil then
				pcall(orig_mini_files_close)
			end
		end)
	end

	show_confirm_modal(change_lines, apply_and_close, discard_and_close)
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

	-- If nothing is open, start a new explorer.
	local state = MiniFiles.get_explorer_state()
	if state == nil then
		MiniFiles.open(vim.fn.getcwd(), false)
		return
	end

	-- Close via the patched `MiniFiles.close()`, which shows our centered
	-- confirmation popup when there are pending changes.
	MiniFiles.close()
end

-- Normalize a path by stripping trailing slashes so file and directory
-- comparisons behave consistently.
local function normalize_path(path)
	return (path:gsub("/+$", ""))
end

-- Close all normal (`buftype = ""`) buffers associated with `path`.
-- `path` may be a file or a directory; in the latter case every buffer under
-- it is closed too. This mirrors VS Code's behaviour when a file is deleted or
-- moved to trash from the explorer.
local function close_deleted_buffers(path)
	local target = normalize_path(path)
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].buftype == "" then
			local name = normalize_path(vim.api.nvim_buf_get_name(buf_id))
			if name == target or vim.startswith(name, target .. "/") then
				pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
			end
		end
	end
end

-- Rename all normal buffers whose path starts with `from` so they point to the
-- corresponding location under `to`. This acts as a fallback for `mini.files`'
-- own buffer renaming, ensuring open files stay in sync after rename/move.
local function rename_matching_buffers(from, to)
	local from_prefix = normalize_path(from)
	local to_prefix = normalize_path(to)
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].buftype == "" then
			local name = normalize_path(vim.api.nvim_buf_get_name(buf_id))
			if name == from_prefix then
				pcall(vim.api.nvim_buf_set_name, buf_id, to_prefix)
			elseif vim.startswith(name, from_prefix .. "/") then
				local suffix = name:sub(#from_prefix + 2)
				pcall(vim.api.nvim_buf_set_name, buf_id, to_prefix .. "/" .. suffix)
			end
		end
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

	-- Patch `MiniFiles.close()` so every close path (the `q` mapping, `<C-b>`,
	-- and any internal call) goes through our centered confirmation popup
	-- instead of the command-line confirm dialog. Guard against re-patching if
	-- `setup()` is called more than once.
	if orig_mini_files_close == nil then
		orig_mini_files_close = mini_files.close
		mini_files.close = function()
			close_with_confirmation(mini_files)
		end
	end

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

			-- `q` closes the filepicker. `MiniFiles.close()` is patched below to
			-- show our centered confirmation popup when there are pending changes.
			vim.keymap.set("n", "q", function()
				mini_files.close()
			end, { buffer = buf_id, desc = "Close sidebar filepicker", silent = true })

			-- `l` opens/expands; on the synthetic ".." entry it goes up instead.
			vim.keymap.set("n", "l", function()
				go_in_or_up(mini_files)
			end, { buffer = buf_id, desc = "Open/expand or go to parent", silent = true })

			-- `Enter` also opens/expands, matching VS Code's explorer behaviour.
			vim.keymap.set("n", "<CR>", function()
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

	-- Close normal buffers whose files were deleted from the filepicker.
	-- `mini.files` already renames buffers on move/rename, but it leaves stale
	-- buffers behind after delete (including trash moves).
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MiniFilesActionDelete",
		callback = function(args)
			close_deleted_buffers(args.data.from)
		end,
	})

	-- Fallback buffer rename for move/rename actions. `mini.files` performs its
	-- own rename, but this ensures the buffer list stays consistent even if a
	-- built-in edge case is missed.
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MiniFilesActionRename",
		callback = function(args)
			rename_matching_buffers(args.data.from, args.data.to)
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MiniFilesActionMove",
		callback = function(args)
			rename_matching_buffers(args.data.from, args.data.to)
		end,
	})
end

return M
