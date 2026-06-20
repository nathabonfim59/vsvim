-- General Neovim options

local options = {
	-- Show a single status line across the bottom of the screen for all
	-- windows/splits, instead of one per window. See :help 'laststatus'
	laststatus = 3,

	-- Indent with 4 columns. See :help 'tabstop', :help 'shiftwidth',
	-- :help 'softtabstop'. Note: 'expandtab' is NOT set, so real tab
	-- characters are preserved.
	tabstop = 4,
	shiftwidth = 4,
	softtabstop = 4,

	-- Show absolute line numbers in the gutter like VS Code. See :help 'number'
	number = true,

	-- Highlight the current line like VS Code. The 'CursorLine' and
	-- 'CursorLineNr' highlight groups come from the vscode.nvim colorscheme.
	-- See :help 'cursorline'
	cursorline = true,

	-- Show invisible characters (tabs, trailing whitespace, etc.) so real
	-- tabs are visible. See :help 'list', :help 'listchars'
	list = true,

	-- Yank/delete/paste to the system clipboard. See :help 'clipboard',
	-- :help clipboard-unnamed, :help clipboard-unnamedplus
	clipboard = "unnamed,unnamedplus",
}

for key, value in pairs(options) do
	vim.opt[key] = value
end
