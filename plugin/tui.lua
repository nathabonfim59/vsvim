-- plugin/tui.lua
-- Auto-sourced at startup (see :help load-plugins). Wires up the `tui` module:
-- a user command and a default keymap for opening TUI programs full-screen.

local tui = require("tui")

-- Sensible defaults. Customize via tui.setup({...}) before this runs, or edit here.
tui.setup({
	padding = 1, -- small gap so the border is visible
	border = "rounded",
})

-- :Tui <prog> [args...]   -> open a TUI full-screen
-- :Tui lazygit
-- :Tui btop
-- :Tui nvim .
vim.api.nvim_create_user_command("Tui", function(opts)
	local args = opts.fargs
	if #args == 0 then
		vim.notify("tui: usage :Tui <program> [args...]", vim.log.levels.WARN)
		return
	end
	tui.open(args, { title = table.concat(args, " ") })
end, {
	desc = "Open a TUI program full-screen in a floating terminal",
	nargs = "+",
	complete = "shellcmd",
})

-- Default keymap: <leader>gg opens LazyGit full-screen (same shortcut as before).
-- Set `vim.g.tui_no_default_keymaps = true` to disable.
if not vim.g.tui_no_default_keymaps then
	vim.keymap.set("n", "<leader>gg", function()
		tui.open({ "lazygit" }, { title = "lazygit" })
	end, { desc = "[G]it - Open Lazy[g]it (tui)" })
end
