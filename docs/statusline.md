# Status bar

Source: [`lua/statusline.lua`](../lua/statusline.lua)

The solid blue strip at the bottom of the editor, built on
[`mini.statusline`](https://github.com/nvim-mini/mini.nvim/blob/main/doc/mini-statusline.txt).
Mirrors VS Code's status bar layout: git branch + diff summary on the
left, diagnostics / position / indent / EOL / encoding / language on the
right, all on one flat blue background.

`options.lua` sets `laststatus = 3` so there is a single global bar for
the whole tabpage, exactly like VS Code.

## Layout

```
[sidebar-icon] [git branch] [diff summary]   %=   [diagnostics] [Ln, Col] [indent] [eol] [encoding] [language]
```

`%=` splits the bar into left and right halves. Everything sits on a
single flat blue background (`VsvimStatusline`), which is what makes it
read as VS Code's status bar rather than a typical bubble-style Neovim
statusline.

Inactive windows get a dimmed variant (`VsvimStatuslineInactive`) showing
just the filename, like VS Code's unfocused editor status bar.

## Sections

| Section        | Source                          | Notes                                              |
| -------------- | ------------------------------- | -------------------------------------------------- |
| sidebar icon   | `M.section_sidebar`             | Click to toggle the filepicker                     |
| git branch     | `mini.statusline.section_git`   | Branch glyph from `mini.icons`; click opens lazygit|
| diff summary   | `mini.statusline.section_diff`  | Click opens a full-file diff view                  |
| diagnostics    | `M.section_diagnostics`         | Error / warning counts with sign icons             |
| position       | `M.section_position`            | `Ln %l, Col %c` (VS Code's exact format)           |
| indent         | `M.section_indent`              | `Spaces: N` or `Tab Size: N`                       |
| EOL            | `M.section_eol`                 | `LF` / `CRLF` / `CR`                               |
| encoding       | `M.section_encoding`            | Hidden unless it isn't UTF-8 (VS Code behaviour)   |
| language       | `M.section_language`            | Filetype with `mini.icons` glyph; "Plain Text" if blank |

## Clickable regions

Three sections are wired to click handlers via statusline `%@...@` items:

| Region        | Click action                                       |
| ------------- | -------------------------------------------------- |
| sidebar icon  | `require("sidebar").toggle()`                      |
| git branch    | `require("tui").open({ "lazygit", "branch" })`     |
| diff summary  | `require("diff_gutter").open_file_diff(0)`         |

The handlers are exposed as `_G.vsvim_statusline_sidebar_click` /
`_G.vsvim_statusline_git_click` / `_G.vsvim_statusline_diff_click` and
wrapped in Vimscript functions (`VsvimStatuslineSidebarClick`, etc.) so
the `%@` items have something to call.

## Highlights

VS Code's status bar is a *single* flat color, so we define our own
`VsvimStatusline` / `VsvimStatuslineInactive` groups rather than reusing
`mini.statusline`'s `MiniStatusline*` groups (which are designed for
per-section tinting).

Colors are pulled directly from the live `vscode.nvim` palette via
`require("vscode.colors").get_colors()` so they adapt to dark / light
mode and any `color_overrides` the user has configured:

- Active bar: `vscSelection` background, `vscFront` foreground (falls
  back to the colorscheme's `StatusLine` group).
- Inactive bar: `vscLeftDark` background, `vscLeftLight` foreground
  (falls back to `StatusLineNC`).

An explicit `VsvimStatusBar` highlight group is honoured first as an
escape hatch for users who want to override the bar color directly.

Highlights are re-applied on every `ColorScheme` event so they survive
colorscheme reloads. No hardcoded hex fallbacks are used.

## API

```lua
require("statusline").setup(opts)        -- configure mini.statusline + wire click handlers
require("statusline").content_active()   -- active window statusline string
require("statusline").content_inactive() -- inactive window statusline string
require("statusline").set_highlights()   -- re-apply VS Code highlights
```

Each `section_*` function is also part of the public API and returns the
string for that segment (empty string to omit).
