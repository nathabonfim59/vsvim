-- Plugin management via vim.pack (Neovim 0.12+ built-in)
-- See: :help vim.pack

-- Install plugins:
--   - mini.nvim: provides `mini.tabline` (the VS Code-style tab bar, see
--     lua/tabline.lua), `mini.statusline` (the VS Code-style bottom bar,
--     see lua/statusline.lua) and `mini.icons` (colored filetype icons).
--     The library loads lazily per module, so adding the whole repo does
--     not start anything until a module's setup() runs.
--     https://github.com/nvim-mini/mini.nvim
--   - fff.nvim (fuzzy finder): https://github.com/dmtrKovalenko/fff.nvim
--   - vscode.nvim (colorscheme): VS Code Dark+/Light+ theme.
--     https://github.com/Mofiqul/vscode.nvim
vim.pack.add({
	{ src = "https://github.com/nvim-mini/mini.nvim" },
	{
		src = "https://github.com/dmtrKovalenko/fff.nvim",
	},
	{ src = "https://github.com/Mofiqul/vscode.nvim" },
})

-- Default to dark mode and apply the vscode.nvim colorscheme on startup.
-- `background` must be set before the colorscheme loads so vscode.nvim picks
-- up its Dark+ variant. `pcall` swallows the not-yet-installed error on a
-- fresh checkout; vim.pack installs vscode.nvim on first launch and the
-- colorscheme activates automatically on the next startup.
vim.o.background = "dark"
pcall(vim.cmd.colorscheme, "vscode")

-- mini.icons: colored filetype icons used by mini.tabline and mini.statusline.
-- Also registers custom "filetype" entries for the tabline's modified/close
-- indicators so they can be overridden through the standard MiniIcons config.
require("mini.icons").setup({
	filetype = {
		["vsvim-modified"] = { glyph = "●", hl = "MiniIconsRed" },
		["vsvim-close"] = { glyph = "×", hl = "MiniIconsGrey" },
	},
})

-- mini.git: provides git branch/status info consumed by mini.statusline's
-- section_git() via `vim.b.minigit_summary_string`.
require("mini.git").setup()

-- mini.diff: VS Code-style gutter diff indicators (add/change/delete bars).
-- Uses mini.diff's built-in Git source, so indicators update as you edit and
-- stage/reset hunks with the `gh` / `gH` operators and `[h` / `]h` navigation.
require("mini.diff").setup({
	view = {
		-- Show indicators in the sign column rather than colored line numbers.
		style = "sign",
		-- VS Code uses a thin colored bar in the gutter; deletion is shown as a
		-- small underscore on the line after the removed block.
		signs = { add = "▎", change = "▎", delete = "▁" },
	},
})

-- Color the diff gutter indicators with vscode.nvim's git palette.
-- mini.diff sets its highlight groups as defaults on ColorScheme, so we re-apply
-- our overrides after every colorscheme reload.
local function set_diff_highlights()
	local ok, vsc = pcall(require, "vscode.colors")
	if not ok then
		return
	end
	local c = vsc.get_colors()
	local hl = vim.api.nvim_set_hl
	hl(0, "MiniDiffSignAdd", { fg = c.vscGitAdded, bg = "NONE", default = false })
	hl(0, "MiniDiffSignChange", { fg = c.vscGitModified, bg = "NONE", default = false })
	hl(0, "MiniDiffSignDelete", { fg = c.vscGitDeleted, bg = "NONE", default = false })
end

local diff_hl_group = vim.api.nvim_create_augroup("vsvim-diff-hl", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
	group = diff_hl_group,
	callback = set_diff_highlights,
})
set_diff_highlights()

-- mini.pairs: auto-close brackets, quotes, etc. — VSCode's default behaviour.
-- mini.keymap's "minipairs_cr" / "minipairs_bs" steps depend on this.
require("mini.pairs").setup()

-- mini.comment: gc / gcc operators for line and block comments.
-- Ctrl+/ and Shift+Alt+A in the vscode keymap preset delegate here.
require("mini.comment").setup()

-- mini.completion: lightweight built-in completion used by mini.keymap's
-- "pmenu_accept" / "pmenu_prev" smart-Tab steps.
require("mini.completion").setup()

-- mini.files: VS Code-style sidebar filepicker. Toggle with Ctrl+B or click
-- the folder icon in the statusline. Pure logic in lua/sidebar.lua.
require("sidebar").setup()

-- VS Code-style tabline (listed buffers as tabs, colored icons, modified
-- dot / close glyph, click-to-switch). Pure logic in lua/tabline.lua.
require("tabline").setup()

-- VS Code-style statusline (the solid blue bottom bar: git branch on the
-- left, diagnostics + position + indent + encoding + language on the
-- right). Pure logic in lua/statusline.lua; built on `mini.statusline`.
require("statusline").setup()

-- fff.nvim ships a prebuilt binary; build it on install.
-- Triggered via the standard `PackChanged` event emitted by vim.pack.
vim.api.nvim_create_autocmd("PackChanged", {
	group = vim.api.nvim_create_augroup("fff-install", { clear = true }),
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if name == "fff.nvim" and kind == "install" then
			if not ev.data.active then
				vim.cmd.packadd("fff.nvim")
			end
			require("fff.download").download_or_build_binary()
		end
	end,
})

-- fff.nvim configuration (read before the plugin loads)
vim.g.fff = {
	lazy_sync = true,
	debug = { enabled = true, show_scores = true },
}

-- NOTE: keymaps are registered by the keybinding-preset system
-- (lua/presets/), not here. See init.lua -> require("presets").setup().
