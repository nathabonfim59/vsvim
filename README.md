# vsvim

<img width="1402" height="888" alt="image" src="https://github.com/user-attachments/assets/9f04f77b-34db-48f6-b463-9637274e78ce" />

VS Code, but in Neovim — with as few plugins as possible.

A minimal Neovim distribution that aims for a familiar VS Code editing
experience without piling on plugin managers, language servers, or UI
frameworks. Just sensible defaults, the built-in `vim.pack` for plugin
management, and a handful of small Lua modules that recreate the VS Code
chrome (sidebar, tab bar, status bar, clickable git gutter) on top of
[`mini.nvim`](https://github.com/nvim-mini/mini.nvim).

## Features

### Editor chrome
- **Sidebar filepicker** (`<C-b>`) — a docked-left `mini.files` explorer with
  synthetic `..` entries, single-click open, left padding, and a centered
  Save / Discard / Cancel modal when there are pending filesystem changes.
- **Editor tab bar** — one tab per listed buffer, colored filetype icons,
  VS Code-style dirty indicator (filled dot when modified, `×` when clean),
  click-to-switch, theme-derived highlights.
- **Status bar** — the solid blue strip at the bottom: git branch + diff
  summary on the left, diagnostics / `Ln, Col` / indent / EOL / encoding /
  language on the right. The sidebar icon, branch, and diff summary are all
  **clickable** (toggle sidebar, open lazygit, open full-file diff).
- **VS Code Dark+ colorscheme** via
  [`vscode.nvim`](https://github.com/Mofiqul/vscode.nvim); all chrome
  highlights are derived from the live theme, no hardcoded hex fallbacks.

### Git / hunks
- **Gutter diff indicators** (`mini.diff`) — VS Code-style add / change /
  delete bars in the sign column, colored from the theme's git palette.
- **Clickable gutter** — left-click a hunk sign to preview it in a floating
  window (with Discard / Close buttons); right-click to discard the hunk
  directly.
- **Full-file diff view** — click the statusline diff summary (or call
  `:lua require("diff_gutter").open_file_diff(0)`) to open a HEAD-vs-working
  split with `diff` enabled, VS Code's "Open Changes" layout. Press `q` to
  leave diff mode.
- **lazygit** — `<leader>gg` (or click the branch indicator) opens lazygit
  full-screen in a floating terminal.

### Editing
- **VS Code keybindings** as a preset — Ctrl+C/X/V, Ctrl+Z/Y, Ctrl+S,
  Ctrl+Shift+K (delete line), Alt+Up/Down (move line), Shift+Alt+Up/Down
  (duplicate), Ctrl+Enter / Ctrl+Shift+Enter (insert line below/above),
  Ctrl+F / F3 / Ctrl+H (find/replace), Ctrl+/ and Shift+Alt+A (line/block
  comments), Ctrl+B (sidebar), Ctrl+\` (terminal), Shift+Alt+F (LSP
  format), and many more. See
  [docs/navigation.md](docs/navigation.md) for the full table.
- **Smart Tab / Enter / Backspace** via `mini.keymap` — Tab accepts
  completion then indents, Enter accepts completion then honors auto-pairs,
  Backspace unwraps auto-pairs.
- **Auto-pairs, comments, completion** from `mini.nvim`.
- **`fff.nvim`** fuzzy finder — `<leader>sf` (files), `<leader>sg` (grep),
  `<leader>sw` (word under cursor).

### Buffer / tab management
- **`<C-w>` closes the current editor tab** (VS Code style). If the buffer
  has unsaved changes, a Save / Discard / Cancel modal is shown instead of
  erroring out.
- `<leader>bn` / `<leader>bp` cycle editor tabs; `<leader>bd` is an alias
  for close.

### Isolation
- vsvim runs in its **own Neovim scope** (`$NVIM_APPNAME=vsvim`), so all of
  its config, data, cache, and state live under `~/.config/vsvim`,
  `~/.local/share/vsvim`, etc. — it never touches your regular
  `~/.config/nvim`.

## Requirements

- [Neovim](https://neovim.io) 0.12+ (uses the built-in `vim.pack`)
- `curl` and `git` (for `vim.pack` to fetch plugins)
- `lazygit` (optional — only for the `<leader>gg` keymap and the
  statusline branch click)

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

- **vsvim** — VS Code-style editing shortcuts plus leader-based picker
  keymaps (`<leader>sf`, `<leader>sg`, `<leader>sw`). The default.
- **vim** — plain Vim defaults, no leader overrides. fff.nvim stays
  reachable via `:FindFiles`, `:LiveGrep`, and `:GrepWord`.

Re-pick at any time by deleting `~/.config/vsvim/keybindings.json` (or
editing it to `"preset": "vim"` / `"vsvim"`). See
[docs/presets.md](docs/presets.md).

## Structure

```
install.sh             # Installs the `vsvim` launcher + wires the config scope
vsvim                  # Launcher: sets NVIM_APPNAME=vsvim, execs nvim
init.lua               # Entry point: sets leader, loads options + plugins + presets
lua/options.lua        # General options
lua/plugins.lua        # vim.pack plugin spec + setup for every mini.* module
lua/presets/           # Keybinding preset system (vsvim vs vim) + persistence
lua/keymaps/vscode.lua # VS Code text-editing shortcuts (used by the vsvim preset)
lua/sidebar.lua        # VS Code-style sidebar filepicker (mini.files)
lua/tabline.lua        # VS Code-style editor tab bar (mini.tabline)
lua/statusline.lua     # VS Code-style status bar (mini.statusline)
lua/diff_gutter.lua    # Clickable git diff gutter + hunk preview + file diff
lua/modal.lua          # Reusable modal dialog module (buttons, backdrop, focus guard)
lua/tui/init.lua       # Full-screen floating terminal helper (lazygit, etc.)
plugin/tui.lua         # Auto-sourced: registers :Tui command + <leader>gg keymap
```

Logic lives under `lua/` (loaded on demand) and auto-sourced entry points
live under `plugin/` (see `:help load-plugins`).

## Documentation

Per-module docs live in [`docs/`](docs/):

- [docs/navigation.md](docs/navigation.md) — VS Code-style editing
  keybindings (the `keymaps/vscode.lua` preset).
- [docs/sidebar.md](docs/sidebar.md) — the sidebar filepicker.
- [docs/tabline.md](docs/tabline.md) — the editor tab bar.
- [docs/statusline.md](docs/statusline.md) — the bottom status bar.
- [docs/git-and-hunks.md](docs/git-and-hunks.md) — the diff gutter, hunk
  preview, and full-file diff view.
- [docs/modal.md](docs/modal.md) — the reusable modal dialog module.
- [docs/tui.md](docs/tui.md) — the floating terminal helper.
- [docs/presets.md](docs/presets.md) — the keybinding-preset system.
- [docs/plugins.md](docs/plugins.md) — `vim.pack` plugin spec and the
  `mini.nvim` modules vsvim uses.
- [docs/options.md](docs/options.md) — the default Neovim options.

## Keymaps (vsvim preset)

A quick reference; the **vim** preset leaves Vim's defaults untouched and
exposes `:FindFiles` / `:LiveGrep` / `:GrepWord` instead. See
[docs/navigation.md](docs/navigation.md) for the full editing-shortcut
table.

| Key          | Action                              |
| ------------ | ----------------------------------- |
| `<C-b>`      | Toggle sidebar filepicker           |
| `<C-w>`      | Close current editor tab            |
| `<leader>sf` | Search [F]iles                      |
| `<leader>sg` | Search [G]rep                       |
| `<leader>sw` | Search [W]ord under cursor          |
| `<leader>gg` | Open lazygit (floating terminal)    |
| `<leader>bn` | Next editor tab                     |
| `<leader>bp` | Previous editor tab                 |
| `<leader>bd` | Close current editor tab            |

## License

MIT
