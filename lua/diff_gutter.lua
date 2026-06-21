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
--   - The float has two clickable buttons at the top, right-aligned:
--     "Discard" (red) and "Close" (gray, preselected). Tab cycles between
--     them, Enter activates, mouse click works too.
--   - Right-click a sign to discard the hunk directly (no preview).
--
-- This is built on `mini.diff`'s hunk data (`MiniDiff.get_buf_data()`), so the
-- indicators, preview contents, and reset logic all stay consistent with the
-- Git source mini.diff already maintains.

local modal = require("modal")

local M = {}

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

-- Open a full-file diff view: HEAD (mini.diff's ref_text) on the left, the
-- working buffer on the right, both with 'diff' enabled, VS Code's "Open
-- Changes" layout. Press `q` in either window (or just close the left one)
-- to leave diff mode and restore the working buffer.
function M.open_file_diff(buf_id)
	buf_id = buf_id or 0
	if buf_id == 0 then
		buf_id = vim.api.nvim_get_current_buf()
	end

	local ok, MiniDiff = pcall(require, "mini.diff")
	if not ok then
		vim.notify("diff_gutter: 'mini.diff' not found", vim.log.levels.ERROR)
		return
	end

	local buf_data = MiniDiff.get_buf_data(buf_id)
	if not buf_data or type(buf_data.ref_text) ~= "string" then
		vim.notify("diff_gutter: no reference text for this buffer", vim.log.levels.WARN)
		return
	end

	-- Find a window currently showing the working buffer; fall back to the
	-- current window. We'll split it to the left and put the ref buffer there.
	local work_win = nil
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(w) == buf_id then
			work_win = w
			break
		end
	end
	work_win = work_win or vim.api.nvim_get_current_win()

	-- Build a scratch buffer holding the reference (HEAD) text.
	local ref_lines = vim.split(buf_data.ref_text, "\n")
	-- nvim_buf_set_lines drops a trailing empty element produced by the
	-- trailing newline mini.diff appends; that's fine, it just means the
	-- ref buffer has the same line count as the file at HEAD.
	local ref_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(ref_buf, 0, -1, false, ref_lines)
	vim.bo[ref_buf].buftype = "nofile"
	vim.bo[ref_buf].bufhidden = "wipe"
	vim.bo[ref_buf].swapfile = false
	vim.bo[ref_buf].modifiable = false
	vim.bo[ref_buf].readonly = true
	vim.bo[ref_buf].filetype = "diff"

	-- Title the ref buffer like VS Code's "HEAD • <file>" tab.
	local name = vim.api.nvim_buf_get_name(buf_id)
	local short = (name ~= "" and vim.fn.fnamemodify(name, ":t")) or "buffer"
	vim.api.nvim_buf_set_name(ref_buf, "HEAD • " .. short)

	-- Open the ref buffer in a left split off the working window.
	local ref_win = vim.api.nvim_open_win(ref_buf, false, {
		split = "left",
		win = work_win,
	})
	if ref_win == 0 then
		vim.notify("diff_gutter: could not open diff split", vim.log.levels.ERROR)
		pcall(vim.api.nvim_buf_delete, ref_buf, { force = true })
		return
	end

	-- Enable diff mode on both windows. `diffopt` defaults already include
	-- `closeoff`, so closing either window turns diff off in the other, but
	-- we also force it off on the working window when the ref window closes,
	-- to be safe across nvim versions.
	vim.wo[ref_win].diff = true
	vim.wo[work_win].diff = true

	-- `q` in either window closes the ref window, which (via the autocmd
	-- below) restores the working buffer to non-diff mode.
	local function close_diff()
		if vim.api.nvim_win_is_valid(ref_win) then
			vim.api.nvim_win_close(ref_win, true)
		end
	end

	vim.keymap.set("n", "q", close_diff, { buffer = ref_buf, silent = true, nowait = true })
	vim.keymap.set("n", "q", close_diff, { buffer = buf_id, silent = true, nowait = true })

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(ref_win),
		once = true,
		callback = function()
			if vim.api.nvim_win_is_valid(work_win) then
				vim.wo[work_win].diff = false
			end
			-- Remove the buffer-local `q` we added to the working buffer.
			pcall(vim.keymap.del, "n", "q", { buffer = buf_id })
		end,
	})

	-- Jump to the working window so the cursor stays on the editable side.
	pcall(vim.api.nvim_set_current_win, work_win)
	vim.cmd("diffupdate")
end

-- Open a floating window previewing the hunk under the cursor/click.
local function open_hunk_preview(buf_id, hunk)
	modal.open({
		title = " Hunk preview ",
		lines = make_preview(buf_id, hunk),
		position = "cursor",
		filetype = "diff",
		min_width = 40,
		buttons = {
			position = "top",
			align = "right",
			items = {
				{ label = " Discard ", hl = "DiffGutterDiscardBtn", action = "discard" },
				{ label = " Close ", hl = "DiffGutterCloseBtn", action = "close", default = true },
			},
		},
		keymaps = {
			["d"] = "discard",
			["q"] = "close",
			["<Esc>"] = "close",
		},
		on_action = function(action)
			if action == "discard" then
				reset_hunk(buf_id, hunk)
			end
		end,
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

	-- Highlights for the float's button bar. All link to existing groups so
	-- they pick up the active colorscheme automatically:
	--   DiffGutterDiscardBtn → DiffDelete  (red bg, destructive action)
	--   DiffGutterCloseBtn   → PmenuSbar   (gray bg, neutral dismissal)
	-- `default = true` lets a colorscheme override them; re-applied on
	-- colorscheme changes because loading a scheme clears existing groups.
	local function define_hl()
		vim.api.nvim_set_hl(0, "DiffGutterDiscardBtn", { default = true, link = "DiffDelete" })
		vim.api.nvim_set_hl(0, "DiffGutterCloseBtn", { default = true, link = "PmenuSbar" })
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
