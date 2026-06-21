# vsvim

<img width="1402" height="888" alt="image" src="https://github.com/user-attachments/assets/9f04f77b-34db-48f6-b463-9637274e78ce" />

VS Code-ish, but in Neovim.

A lightweight Neovim distribution that recreates part of the VS Code
experience: the sidebar, tab bar, status bar, and clickable git gutter. Built
on [`mini.nvim`](https://github.com/nvim-mini/mini.nvim) with the built-in
`vim.pack` for plugin management. No plugin managers, language servers, or UI
frameworks, just sensible defaults.

## Features

**Editor chrome**

- **Sidebar filepicker** (`<C-b>`): docked-left `mini.files` explorer with
  single-click open and a Save / Discard / Cancel modal for pending changes.
- **Tab bar**: one tab per buffer, filetype icons, VS Code-style dirty dot,
  click-to-switch.
- **Status bar**: git branch + diff on the left, diagnostics / position /
  indent / encoding / language on the right. Branch, diff, and sidebar icon
  are clickable.
- **Dark+ colorscheme** via
  [`vscode.nvim`](https://github.com/Mofiqul/vscode.nvim); all chrome
  highlights derive from the live theme.

**Git**

- Theme-colored gutter diff signs (`mini.diff`): click to preview a hunk,
  right-click to discard.
- Full-file diff view (HEAD vs working) via statusline click or
  `:lua require("diff_gutter").open_file_diff(0)`; `q` to leave.
- `<leader>gg` (or click the branch) opens `lazygit` in a floating terminal.

**Editing**

- **VS Code keybindings** as a preset: Ctrl+C/X/V/Z/Y, Ctrl+S, line
  move/duplicate, comment toggle, find/replace, and more. Full table in
  [docs/navigation.md](docs/navigation.md).
- Smart Tab / Enter / Backspace, auto-pairs, comments, completion (`mini.*`).
- **Quick Open** (`mini.pick` + `fff.nvim`): `<C-p>` files, `<C-S-p>` command
  palette, `<C-S-f>` find in files, `<C-Tab>` buffers.

**Buffers**

- `<C-w>` closes the current tab (with a Save / Discard / Cancel modal on
  unsaved changes). `<leader>bn` / `<leader>bp` cycle tabs.

**Isolation**

- Runs in its own scope (`$NVIM_APPNAME=vsvim`): config, data, and state live
  under `~/.config/vsvim`, never touching `~/.config/nvim`.

## Requirements

- [Neovim](https://neovim.io) 0.12+, `curl`, `git`
- `lazygit` (optional, for `<leader>gg` and the statusline branch click)

## Install

```sh
git clone <this-repo> vsvim
cd vsvim
./install.sh
```

Symlinks a `vsvim` launcher into `~/.local/bin` (or `/usr/local/bin` as root),
so repo edits take effect immediately. Flags: `--copy` (frozen install),
`--uninstall`, `--help`. Then run `vsvim` instead of `nvim`.

### One-liner (from latest release)

No git needed. Downloads the latest release tarball, extracts it, and runs
the bundled `install.sh --copy`:

```sh
tmp=$(mktemp -d) && curl -fsSL https://github.com/nathabonfim59/vsvim/releases/latest/download/vsvim-latest.tar.gz | tar -xz -C "$tmp" && sh "$tmp"/vsvim-*/install.sh --copy && rm -rf "$tmp"
```

## Version and updates

```sh
vsvim --version     # print the installed version
vsvim update        # check for and install a newer release
```

`vsvim update` behaves according to install mode:

- **Symlink install** (default): runs `git pull --ff-only` in the repo and
  refreshes the install links. No download, no version comparison.
- **`--copy` install**: queries the latest GitHub release, compares the
  remote version against the one baked into the launcher, and if newer
  downloads the `vsvim-X.Y.Z.tar.gz` tarball, verifies its SHA256, and
  reinstalls into the same prefix/bindir/configdir recorded at install time.

Releases are cut by pushing a `vX.Y.Z` tag, which triggers
[`.github/workflows/release.yml`](.github/workflows/release.yml) to build the
tarball (with the version baked into `VERSION`) and publish a GitHub Release.

## Keybindings

On first launch vsvim asks for a preset, saved to
`~/.config/vsvim/keybindings.json`:

- **vsvim** (default): VS Code shortcuts plus leader-based pickers.
- **vim**: plain Vim defaults. fff.nvim stays reachable via `:FindFiles`,
  `:LiveGrep`, `:GrepWord`.

Re-pick by deleting (or editing) that file. See
[docs/presets.md](docs/presets.md).

**vsvim preset reference** (vim preset leaves defaults untouched):

| Key          | Action                           |
| ------------ | -------------------------------- |
| `<C-b>`      | Toggle sidebar filepicker        |
| `<C-p>`      | Quick open files                 |
| `<C-S-p>`    | Command palette                  |
| `<C-S-f>`    | Find in files                    |
| `<C-Tab>`    | Buffer picker                    |
| `<C-w>`      | Close current tab                |
| `<leader>sf` | Search [F]iles                   |
| `<leader>sg` | Search [G]rep                    |
| `<leader>sw` | Search [W]ord under cursor       |
| `<leader>gg` | Open lazygit (floating terminal) |
| `<leader>bn` | Next editor tab                  |
| `<leader>bp` | Previous editor tab              |
| `<leader>bd` | Close current editor tab         |

## Documentation

Per-module docs in [`docs/`](docs/):

[editing keybindings](docs/navigation.md) · [sidebar](docs/sidebar.md) ·
[tabline](docs/tabline.md) · [statusline](docs/statusline.md) ·
[git & hunks](docs/git-and-hunks.md) · [modal](docs/modal.md) ·
[tui](docs/tui.md) · [presets](docs/presets.md) ·
[plugins](docs/plugins.md) · [options](docs/options.md)

## License

MIT
