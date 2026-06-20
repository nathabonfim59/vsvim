# vsvim

VS Code, but in Neovim — with as few plugins as possible.

A minimal Neovim config that aims for a familiar editor experience without
piling on plugin managers, language servers, or UI frameworks. Just sensible
defaults and the bare essentials, built on Neovim's built-in `vim.pack`.

## Requirements

- [Neovim](https://neovim.io) 0.12+ (uses the built-in `vim.pack` for plugin management)

## What's in it

- Sensible defaults via `lua/options.lua`
- Plugin management with [`vim.pack`](https://neovim.io/doc/user/vim.pack.html) (no external plugin manager)
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim) — fuzzy finder (the one plugin)
- A small `tui` plugin providing a `:Tui` command and a `<leader>gg` lazygit keymap

## Structure

```
init.lua              # Entry point: sets leader, loads options + plugins
lua/options.lua       # General options
lua/plugins.lua       # vim.pack plugin spec + config/keymaps
lua/tui/init.lua      # TUI helper logic (lazygit)
plugin/tui.lua        # Auto-sourced: registers :Tui command + keymap
```

Logic lives under `lua/` (loaded on demand) and auto-sourced entry points
live under `plugin/` (see `:help load-plugins`).

## Keymaps

| Key          | Action                |
| ------------ | --------------------- |
| `<leader>sf` | Search [F]iles        |
| `<leader>sg` | Search [G]rep         |
| `<leader>sw` | Search [W]ord         |
| `<leader>gg` | Open lazygit (TUI)    |

## License

MIT
