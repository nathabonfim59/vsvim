-- presets/vsvim.lua
--
-- The "vsvim" keybinding preset: leader-based keymaps on top of Vim defaults.
-- This is the default set of mappings vsvim ships with (<leader>sf, etc.).
--
-- A preset is a plain module that exposes a single `apply()` function which
-- registers whatever keymaps it wants. It is called by presets.init after the
-- user's choice has been resolved.

local M = {}

function M.apply()
	-- VSCode text-editing shortcuts (no-modes experience).
	-- Must run after plugins.lua so mini.pairs / mini.comment are set up.
	require("keymaps.vscode").apply()
	-- fff.nvim (fuzzy finder) keymaps. fff.nvim is required by plugins.lua,
	-- so it is available by the time presets run.
	vim.keymap.set("n", "<leader>sf", function()
		require("fff").find_files()
	end, { desc = "[S]earch [F]iles" })
	vim.keymap.set("n", "<leader>sg", function()
		require("fff").live_grep()
	end, { desc = "[S]earch [G]rep" })
	vim.keymap.set("n", "<leader>sw", function()
		require("fff").live_grep({ query = vim.fn.expand("<cword>") })
	end, { desc = "[S]earch [W]ord" })

	-- Tab/buffer management (VS Code-style tabline lives in lua/tabline.lua).
	-- Close the current editor tab (like VS Code's Ctrl+W). `:bd`-style:
	-- wipe the buffer but keep the window, jumping to the previous listed
	-- buffer so the editor doesn't leave an empty window behind.
	vim.keymap.set("n", "<leader>bd", function()
		local cur = vim.api.nvim_get_current_buf()
		-- Pick the previous listed buffer that isn't the current one.
		local prev = nil
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if b ~= cur and vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b) then
				prev = b -- last one wins -> closest listed buffer
			end
		end
		if prev then
			vim.api.nvim_set_current_buf(prev)
		end
		vim.api.nvim_buf_delete(cur, { force = false })
	end, { desc = "[B]uffer [D]elete (close tab)" })

	-- Cycle editor tabs like VS Code's Ctrl+Tab / Ctrl+Shift+Tab.
	vim.keymap.set("n", "<leader>bn", "<Cmd>bnext<CR>", { desc = "[B]uffer [N]ext tab" })
	vim.keymap.set("n", "<leader>bp", "<Cmd>bprevious<CR>", { desc = "[B]uffer [P]revious tab" })
end

return M
