# Sidebar filepicker

Source: [`lua/sidebar.lua`](../lua/sidebar.lua)

A VS Code-style sidebar explorer built on
[`mini.files`](https://github.com/nvim-mini/mini.nvim/blob/main/doc/mini-files.txt).
Toggle it with `<C-b>` (vsvim preset) or click the folder icon in the
statusline.

`mini.files` always uses floating windows; this module pins the float to
the left edge of the editor with a single border and full editor height so
it reads as a docked sidebar rather than a centered popup.

## Features

- **Docked-left layout** — full editor height, single border, 32-column
  width, pinned below the tabline and above the statusline.
- **Synthetic `..` entry** at the top of every directory listing, so you
  can navigate up by pressing `l` / `Enter` / clicking on it (instead of
  reaching for `h`). The entry is registered in `mini.files`' private
  path index so it isn't treated as a pending filesystem create.
- **Single-click open** — clicking an entry expands a directory or opens
  a file, matching VS Code's explorer. (`mini.files` defaults to
  double-click.)
- **Left padding** on every line so content isn't flush against the
  window edge.
- **Centered confirmation modal** when closing with pending filesystem
  changes (deletions, renames, moves). VS Code's explorer prompts before
  discarding; vsvim shows a Save / Discard / Cancel modal built on the
  reusable [`modal`](modal.md) module instead of `mini.files`' built-in
  command-line `confirm()` dialog.
- **Buffer cleanup** — when a file is deleted / moved to trash from the
  sidebar, any open buffer for that file is closed. When a file is
  renamed or moved, open buffers are renamed to follow it (a fallback for
  `mini.files`' own rename logic).

## Keymaps (inside the sidebar)

| Key        | Action                                       |
| ---------- | -------------------------------------------- |
| `l` / `<CR>` | Open / expand entry (or go to parent on `..`) |
| `h`        | Go to parent directory                       |
| `L`        | Open + preview                               |
| `H`        | Go to parent + close current                 |
| `q`        | Close sidebar (with confirmation if pending) |
| `<C-b>`    | Toggle sidebar                               |
| `=`        | Synchronize (apply pending changes)          |
| `<` / `>`  | Trim left / right                            |
| `'` / `m`  | Mark goto / set                              |
| `<BS>`     | Reset                                        |
| `@`        | Reveal cwd                                   |
| `g?`       | Show help                                    |

Single-click on an entry also opens / expands it.

## API

The module is a plain Lua table returned by `require("sidebar")`:

```lua
require("sidebar").setup(opts)   -- configure mini.files + wire autocmds
require("sidebar").toggle()      -- open if closed, close if open
require("sidebar").open(path?)   -- open at `path` (defaults to cwd)
require("sidebar").close()       -- close if open
```

`setup(opts)` merges `opts` into the `mini.files` config (windows,
mappings, ...) and patches `MiniFiles.close()` so every close path goes
through the centered confirmation popup. It is idempotent — calling it
more than once will not re-patch `MiniFiles.close()`.

## Confirmation modal

When you close the sidebar with pending filesystem changes, a centered
modal is shown listing the changes with three buttons:

- **Save** (green, `DiffAdd`) — apply the changes and close.
- **Discard** (red, `DiffDelete`) — drop the changes and close.
- **Cancel** (gray, `PmenuSbar`) — keep the sidebar open.

Keyboard shortcuts: `y` (save), `n` (discard), `q` / `<Esc>` / `<C-c>`
(cancel). The modal opens with a focus guard so `mini.files`' focus-loss
timer can't pull focus away while it's open.

The pending-changes summary is probed by temporarily overriding
`vim.fn.confirm` to capture the message `mini.files` would have shown,
then restoring it. Nothing is applied during the probe.
