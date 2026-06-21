# Options

Source: [`lua/options.lua`](../lua/options.lua)

A small set of general Neovim options that bring the editing experience
closer to VS Code. Set in `init.lua` before plugins load.

| Option        | Value      | Why                                              |
| ------------- | ---------- | ------------------------------------------------ |
| `laststatus`  | `3`        | One global status line across the bottom for the whole tabpage (VS Code's single status bar). See `:help 'laststatus'` |
| `tabstop`     | `4`        | Indent with 4 columns. `expandtab` is **not** set, so real tab characters are preserved. See `:help 'tabstop'`, `:help 'shiftwidth'`, `:help 'softtabstop'` |
| `shiftwidth`  | `4`        | (see above)                                      |
| `softtabstop` | `4`        | (see above)                                      |
| `number`      | `true`     | Show absolute line numbers in the gutter like VS Code. See `:help 'number'` |
| `cursorline`  | `true`     | Highlight the current line like VS Code. The `CursorLine` / `CursorLineNr` highlights come from `vscode.nvim`. See `:help 'cursorline'` |
| `signcolumn`  | `"yes"`    | Always show the sign column so git gutter indicators don't shift the text when they appear / disappear. See `:help 'signcolumn'` |
| `mouse`       | `"a"`      | Enable mouse everywhere so gutter signs and tabline tabs can be clicked. See `:help 'mouse'` |
| `list`        | `true`     | Show invisible characters (tabs, trailing whitespace, etc.) so real tabs are visible. See `:help 'list'`, `:help 'listchars'` |
| `clipboard`   | `"unnamed,unnamedplus"` | Yank / delete / paste to the system clipboard. See `:help 'clipboard'`, `:help clipboard-unnamed`, `:help clipboard-unnamedplus` |

## Notes

- `expandtab` is deliberately **not** set, so files that use real tabs
  keep them. The statusline's indent section reflects this, it shows
  `Tab Size: 4` instead of `Spaces: 4` when `expandtab` is off.
- `laststatus = 3` is also re-asserted by
  [`lua/statusline.lua`](../lua/statusline.lua) at setup time, since VS
  Code always shows the status bar even with a single window.
- The leader key is set to `<space>` in `init.lua` (before plugins
  load), per `:help <Leader>`. The `vim` preset doesn't define any
  leader maps, but the leader is still set so user maps can use it.
