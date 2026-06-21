-- pickers.lua
--
-- mini.pick-based pickers that recreate the VS Code "Quick Open" family of
-- shortcuts, with fff.nvim reused as the file/grep backend wherever it does
-- the job better (rust-indexed frecency file search, live grep).
--
-- Pure logic + setup(). Keymaps are wired up by the preset system
-- (lua/presets/), not here, so the "vim" preset can expose the same features
-- as :commands without leader-based keymaps.
--
-- Pickers exposed:
--   M.files()            - Ctrl+P:  open buffers first, then fff-indexed files
--   M.command_palette()  - Ctrl+Shift+P: Ex commands + keymaps in one picker
--   M.grep()             - Ctrl+Shift+F: fff.nvim live grep
--   M.buffers()          - Ctrl+Tab: mini.pick buffer picker

local M = {}

-- Run once at startup (called from lua/plugins.lua alongside the other
-- mini.nvim module setups). mini.extra provides the commands/keymaps sources
-- we reuse for the command palette.
function M.setup()
	require("mini.pick").setup({
		window = { config = { border = "rounded" } },
	})
	require("mini.extra").setup()
end

-- Collect listed, loaded buffers as mini.pick items, MRU-ordered with the
-- current buffer first (matching VS Code's Quick Open). Items carry `bufnr`
-- so default_choose switches to the buffer and default_preview shows content.
local function buffer_items_mru()
	local cur = vim.api.nvim_get_current_buf()
	local infos = vim.fn.getbufinfo({ buflisted = 1 })
	-- current buffer first, then by lastused descending
	table.sort(infos, function(a, b)
		if a.bufnr == cur then return true end
		if b.bufnr == cur then return false end
		return a.lastused > b.lastused
	end)
	local items = {}
	for _, info in ipairs(infos) do
		if vim.api.nvim_buf_is_loaded(info.bufnr) and info.name ~= "" then
			table.insert(items, {
				bufnr = info.bufnr,
				path = info.name,
				text = vim.fn.fnamemodify(info.name, ":~:."),
			})
		end
	end
	return items
end

-- Case-insensitive substring check on a path.
local function path_matches(path, query)
	if query == "" then return true end
	return path:lower():find(query:lower(), 1, true) ~= nil
end

-- Build the combined item list for a given query: buffers whose path matches
-- the query (MRU, current first), then fff file-search results (deduped
-- against open buffers). With an empty query only buffers are shown, matching
-- VS Code's "Ctrl+P shows open editors first" behavior.
local function build_file_items(query)
	local buffers = buffer_items_mru()
	local items = {}
	-- Track all open buffer paths so fff results don't duplicate them.
	local seen = {}
	local buf_by_path = {}
	for _, buf in ipairs(buffers) do
		seen[buf.path] = true
		buf_by_path[buf.path] = buf
	end

	-- Matching buffers first (MRU, current first).
	for _, buf in ipairs(buffers) do
		if path_matches(buf.text, query) or path_matches(buf.path, query) then
			table.insert(items, buf)
		end
	end

	-- fff file results, deduped. If a result matches an open buffer that
	-- didn't pass the substring filter, use the buffer item so default_choose
	-- switches to it instead of :edit'ing a new copy.
	if query ~= "" then
		local ok, fff = pcall(require, "fff")
		if ok and fff.file_search then
			local base = require("fff.conf").get().base_path
			local res = fff.file_search(query, { max_results = 200, wait_for_index_ms = 0 }) or {}
			for _, f in ipairs(res.items or {}) do
				local rel = f.relative_path
				if rel then
					local abs = base .. "/" .. rel
					if not seen[abs] then
						seen[abs] = true
						-- Use the buffer item if this file is already open.
						table.insert(items, buf_by_path[abs] or { path = abs, text = rel })
					end
				end
			end
		end
	end

	return items
end

-- Ctrl+P / VS Code "Quick Open": open buffers (including the current one)
-- pinned at the top in MRU order, then fff-indexed files appended as you
-- type. Uses mini.pick's dynamic `match` + `set_picker_items` pattern (same
-- as MiniPick.builtin.grep_live): items are rebuilt on every query change,
-- pre-filtered so do_match=false is safe.
function M.files()
	local pick = require("mini.pick")

	local match = function(_, _, query)
		local items = build_file_items(table.concat(query))
		pick.set_picker_items(items, { do_match = false })
	end

	pick.start({
		source = {
			name = "Files",
			items = {},
			match = match,
			show = pick.default_show,
			preview = pick.default_preview,
			choose = pick.default_choose,
		},
	})
end

-- Ctrl+Shift+P / VS Code "Command Palette": merge Ex commands and active
-- keymaps into one picker. Choosing a command feeds `:Cmd` (with a trailing
-- space if it takes args); choosing a keymap replays its lhs.
function M.command_palette()
	local pick = require("mini.pick")

	local commands = vim.tbl_deep_extend("force", vim.api.nvim_get_commands({}), vim.api.nvim_buf_get_commands(0, {}))
	local items = {}

	for _, name in ipairs(vim.fn.getcompletion("", "command")) do
		local data = commands[name] or {}
		table.insert(items, {
			text = string.format("> %s", name),
			_kind = "command",
			_name = name,
			_nargs = data.nargs,
		})
	end

	local max_lhs = 0
	local keymap_rows = {}
	for _, m in ipairs({ "n", "x", "i", "c", "t" }) do
		for _, ma in ipairs(vim.api.nvim_get_keymap(m)) do
			local lhs = vim.fn.keytrans(ma.lhsraw or ma.lhs)
			max_lhs = math.max(vim.fn.strchars(lhs), max_lhs)
			local desc = ma.desc ~= nil and vim.inspect(ma.desc) or ma.rhs
			table.insert(keymap_rows, { mode = m, lhs = lhs, lhs_raw = ma.lhs, desc = desc })
		end
	end
	for _, r in ipairs(keymap_rows) do
		local pad = string.rep(" ", max_lhs - vim.fn.strchars(r.lhs))
		table.insert(items, {
			text = string.format("#  %s  %s%s │ %s", r.mode, r.lhs, pad, r.desc or ""),
			_kind = "keymap",
			_lhs = r.lhs_raw,
			_mode = r.mode,
		})
	end

	pick.start({
		source = {
			name = "Command Palette",
			items = items,
			preview = function(buf_id, item)
				if item._kind == "command" then
					local data = commands[item._name] or {}
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.split(vim.inspect(data), "\n"))
				else
					local ma = vim.fn.maparg(item._lhs, item._mode, false, true)
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.split(vim.inspect(ma), "\n"))
				end
			end,
			choose = function(item)
				if item._kind == "command" then
					local keys = string.format(":%s%s", item._name, item._nargs == "0" and "\r" or " ")
					vim.schedule(function() vim.fn.feedkeys(keys) end)
				else
					local keys = vim.api.nvim_replace_termcodes(item._lhs, true, true, true)
					if item._mode == "x" then keys = "gv" .. keys end
					vim.schedule(function() vim.api.nvim_input(keys) end)
				end
			end,
		},
	})
end

-- Ctrl+Shift+F / VS Code "Find in Files": delegates to fff.nvim's live grep,
-- which uses its rust indexer for fast content search.
function M.grep()
	require("fff").live_grep()
end

-- Ctrl+Tab / VS Code "Open Editors": mini.pick's built-in buffer picker.
function M.buffers()
	require("mini.pick").builtin.buffers({ include_current = true })
end

return M
