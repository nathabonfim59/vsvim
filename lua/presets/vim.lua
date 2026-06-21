-- presets/vim.lua
--
-- The "vim" keybinding preset: plain Vim defaults, no leader-based overrides.
--
-- It registers NO custom keymaps, users who want the stock Vim experience
-- (and to use fff.nvim via :FindFiles / :LiveGrep commands rather than
-- <leader> prefixes) pick this preset. A preset is just a module with an
-- apply() function; this one is intentionally a no-op for keymaps.
--
-- We do expose a couple of user commands so the fuzzy finder is still
-- reachable without leader keys (call :FindFiles / :LiveGrep / :GrepWord).

local M = {}

function M.apply()
	-- No keymaps: leave Vim's defaults untouched.
	--
	-- Provide commands instead so fff.nvim stays usable.
	vim.api.nvim_create_user_command("FindFiles", function()
		require("fff").find_files()
	end, { desc = "vsvim: fuzzy find files" })

	vim.api.nvim_create_user_command("LiveGrep", function()
		require("fff").live_grep()
	end, { desc = "vsvim: live grep" })

	vim.api.nvim_create_user_command("GrepWord", function()
		require("fff").live_grep({ query = vim.fn.expand("<cword>") })
	end, { desc = "vsvim: grep word under cursor" })

	-- mini.pick-based pickers (see lua/pickers.lua). Exposed as commands so
	-- the vim preset stays free of leader/Ctrl+ keymap overrides.
	vim.api.nvim_create_user_command("PickFiles", function()
		require("pickers").files()
	end, { desc = "vsvim: quick open (buffers + fff files)" })
	vim.api.nvim_create_user_command("CommandPalette", function()
		require("pickers").command_palette()
	end, { desc = "vsvim: command palette (commands + keymaps)" })
	vim.api.nvim_create_user_command("PickBuffers", function()
		require("pickers").buffers()
	end, { desc = "vsvim: buffer picker" })

	-- Buffer/tab management commands (VS Code-style tabline in lua/tabline.lua).
	vim.api.nvim_create_user_command("BufferClose", function()
		local cur = vim.api.nvim_get_current_buf()
		local prev = nil
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if b ~= cur and vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b) then
				prev = b
			end
		end
		if prev then
			vim.api.nvim_set_current_buf(prev)
		end
		vim.api.nvim_buf_delete(cur, { force = false })
	end, { desc = "vsvim: close the current editor tab" })
end

return M
