# Editor tab bar

Source: [`lua/tabline.lua`](../lua/tabline.lua)

A VS Code-style editor tab bar built on
[`mini.tabline`](https://github.com/nvim-mini/mini.nvim/blob/main/doc/mini-tabline.txt).
One tab per listed buffer, colored filetype icon, VS Code-style dirty
indicator, click-to-switch.

## Features

- **One tab per listed buffer**: `mini.tabline`'s default behaviour,
  kept as-is.
- **Colored filetype icon** resolved per-buffer via
    [`mini.icons`](https://github.com/nvim-mini/mini.nvim/blob/main/doc/mini-icons.txt)
    (with a graceful fallback to `nvim-web-devicons`, then nothing).
- **VS Code-style dirty indicator**:
  - `●` (red) while the buffer has unsaved changes,
  - `×` (grey) once it is clean.
  The glyphs are resolved from `mini.icons` custom filetype entries
  (`vsvim-modified` / `vsvim-close`), registered in
  [`lua/plugins.lua`](../lua/plugins.lua), so users can override them
  through the standard `mini.icons` config.
- **Click-to-switch**: provided by `mini.tabline`'s
  `%N@MiniTablineSwitchBuffer@` wrapper; clicking a tab switches to that
  buffer, just like clicking a VS Code tab.
- **Active tab highlight**: the active tab gets a distinct, brighter
  background and bold filename so it reads as "selected".

## Layout

Each tab is formatted as:

```
 <icon> <name>     <indicator>
```

The indicator is the modified dot when the buffer is dirty, the close
glyph when it is clean. The wide gap before the indicator mirrors VS
Code's tab spacing.

## Highlights

Highlights are derived from the active colorscheme rather than
hard-coded. `set_highlights()` pulls VS Code's exact tab palette from the
live `TabLineSel` / `TabLine` / `TabLineFill` groups that `vscode.nvim`
populates (`vscTabCurrent` / `vscTabOther` / `vscTabOutside`), and tints
the modified indicator from the theme's git / diagnostic colors
(`GitSignsChange` / `DiagnosticWarn`), the same approach `barbar.nvim`
uses for its `Buffer*` groups.

The highlights are re-applied on every `ColorScheme` event so they
survive colorscheme reloads (and adapt to light / dark mode). No
hardcoded hex fallbacks are used.

The groups defined:

| Group                          | Meaning                          |
| ------------------------------ | -------------------------------- |
| `MiniTablineCurrent`           | Active tab                       |
| `MiniTablineVisible`           | Open in another window           |
| `MiniTablineHidden`            | Inactive / hidden tab            |
| `MiniTablineModifiedCurrent`   | Active tab, modified             |
| `MiniTablineModifiedVisible`   | Visible tab, modified            |
| `MiniTablineModifiedHidden`    | Hidden tab, modified             |
| `MiniTablineFill`              | Empty area around the tabs       |
| `MiniTablineTabpagesection`    | `Tab N/M` section (multi-tabpage)|
| `MiniTablineTrunc`             | Truncation arrows (`‹` / `›`)    |

## API

```lua
require("tabline").setup(opts)   -- configure mini.tabline + wire highlights
require("tabline").format(buf_id, label)  -- per-tab label formatter
require("tabline").get_icon(buf_id)       -- colored filetype icon
require("tabline").set_highlights()       -- re-apply VS Code highlights
```

`setup(opts)` merges `opts` into the `mini.tabline` config. It also sets
up `mini.icons` (if available and not already set up) and mocks
`nvim-web-devicons` so other plugins looking for devicons get answers.
