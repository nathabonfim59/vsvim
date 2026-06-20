# vsvim

VS Code, but in Neovim — with as few plugins as possible.

A minimal Neovim config that aims for a familiar editor experience without
piling on plugin managers, language servers, or UI frameworks. Just sensible
defaults and the bare essentials, built on Neovim's built-in `vim.pack`.

## Requirements

- [Neovim](https://neovim.io) 0.12+ (uses the built-in `vim.pack` for plugin management)
- `curl` and `git` (for `vim.pack` to fetch plugins)

## Installing

vsvim installs a `vsvim` launcher onto your `$PATH` and wires up its own
isolated Neovim scope via `$NVIM_APPNAME=vsvim`. This means vsvim keeps
**all** of its config, data, and state under the `vsvim` sub-directories
(e.g. `~/.config/vsvim`) and never touches your regular `~/.config/nvim`.

```sh
git clone <this-repo> vsvim
cd vsvim
./install.sh
```

By default the launcher is symlinked into:

- `~/.local/bin/vsvim` when run as a normal user
- `/usr/local/bin/vsvim` when run as root

so live edits to the cloned repo take effect immediately. Pass `--copy` for
a frozen, self-contained install, or `--uninstall` to remove everything.
Run `./install.sh --help` for the full option list.

Then just run `vsvim` instead of `nvim`.

## Keybinding presets

On first launch vsvim asks which keybindings you want; the choice is saved
to `~/.config/vsvim/keybindings.json` and re-applied on every launch:

- **vsvim** — leader-based keymaps (the defaults below).
- **vim** — plain Vim defaults, no leader overrides. fff.nvim stays
  reachable via `:FindFiles`, `:LiveGrep`, and `:GrepWord`.

Re-pick at any time by deleting `~/.config/vsvim/keybindings.json` (or
editing it to `"preset": "vim"` / `"vsvim"`).

## What's in it

- Sensible defaults via `lua/options.lua`
- Plugin management with [`vim.pack`](https://neovim.io/doc/user/vim.pack.html) (no external plugin manager)
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim) — fuzzy finder (the one plugin)
- A small `tui` plugin providing a `:Tui` command and a `<leader>gg` lazygit keymap
- A keybinding-preset system (`lua/presets/`) — pick vsvim or plain Vim maps

## Structure

```
install.sh           # Installs the `vsvim` launcher + wires the config scope
vsvim                # Launcher: sets NVIM_APPNAME=vsvim, execs nvim
init.lua             # Entry point: sets leader, loads options + plugins + presets
lua/options.lua      # General options
lua/plugins.lua      # vim.pack plugin spec + config
lua/presets/         # Keybinding presets (vsvim vs vim) + persistence
lua/tui/init.lua     # TUI helper logic (lazygit)
plugin/tui.lua       # Auto-sourced: registers :Tui command + keymap
```

Logic lives under `lua/` (loaded on demand) and auto-sourced entry points
live under `plugin/` (see `:help load-plugins`).

## Keymaps

Shown for the **vsvim** preset (the **vim** preset leaves Vim's defaults
untouched and exposes `:FindFiles` / `:LiveGrep` / `:GrepWord` instead):

| Key          | Action                |
| ------------ | --------------------- |
| `<leader>sf` | Search [F]iles        |
| `<leader>sg` | Search [G]rep         |
| `<leader>sw` | Search [W]ord         |
| `<leader>gg` | Open lazygit (TUI)    |

## License

MIT
