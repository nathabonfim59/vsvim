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
	local pbuf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = pbuf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = pbuf })
	vim.api.nvim_set_option_value("filetype", "diff", { buf = pbuf })

	local width = math.min(80, math.max(40, vim.o.columns - 10))
	local height = math.min(20, math.max(3, #lines + 2))
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

	local opts = { buffer = pbuf, silent = true, nowait = true }
	vim.keymap.set("n", "q", close, opts)
	vim.keymap.set("n", "<Esc>", close, opts)
	vim.keymap.set("n", "d", function()
		reset_hunk(buf_id, hunk)
		close()
	end, vim.tbl_extend("force", opts, { desc = "Discard hunk" }))

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
