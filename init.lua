-- Minimal Neovim configuration

-- Set <space> as the leader key (must be set before plugin/loading logic)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Options
require("options")

-- Plugins
require("plugins")

-- Keybinding presets. vsvim ships two ("vsvim" leader-based maps, or plain
-- "vim" defaults). On first run the user is prompted to choose; the choice
-- is persisted to stdpath("config")/keybindings.json (~/.config/vsvim) so it
-- never touches ~/.config/nvim. See lua/presets/.
require("presets").setup()


-- NOTE: the `tui` plugin auto-loads from plugin/tui.lua (see :help load-plugins)
-- and registers the :Tui command + <leader>gg (lazygit) keymap.
