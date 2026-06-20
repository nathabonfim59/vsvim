-- Minimal Neovim configuration

-- Set <space> as the leader key (must be set before plugin/loading logic)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Options
require("options")

-- Plugins
require("plugins")

-- NOTE: the `tui` plugin auto-loads from plugin/tui.lua (see :help load-plugins)
-- and registers the :Tui command + <leader>gg (lazygit) keymap.
