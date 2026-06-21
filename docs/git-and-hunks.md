# Git gutter & hunks

Sources:
- [`lua/diff_gutter.lua`](../lua/diff_gutter.lua): clickable gutter, hunk preview, file diff
- [`lua/plugins.lua`](../lua/plugins.lua): `mini.diff` / `mini.git` setup and diff highlights

VS Code-style git integration: gutter diff indicators, a clickable gutter
that previews / discards hunks, and a full-file "Open Changes" diff view.

## Gutter indicators

`mini.diff` is configured in `lua/plugins.lua` to show indicators in the
sign column (rather than colored line numbers) using VS Code's glyphs:

- `▎` for add and change (a thin colored bar),
- `▁` for delete (a small underscore on the line *after* the removed
  block).

The indicators are colored from `vscode.nvim`'s git palette:

| Group                | Color source       |
| -------------------- | ------------------ |
| `MiniDiffSignAdd`    | `vscGitAdded`      |
| `MiniDiffSignChange` | `vscGitModified`   |
| `MiniDiffSignDelete` | `vscGitDeleted`    |

These overrides are re-applied on every `ColorScheme` event so they
survive colorscheme reloads.

`mini.git` is also set up so the statusline's `section_git` can show the
branch + dirty summary via `vim.b.minigit_summary_string`.

## Clickable gutter

`diff_gutter.setup()` wires a click handler into the sign column via
`statuscolumn`:

```vim
%@VsvimDiffGutterClick@%s%X%l
```

Signs come first, then the line number, then a small gap. Clicks on the
sign area dispatch to the handler; clicks on the line number fall through
normally.

| Click          | Action                                                       |
| -------------- | ------------------------------------------------------------ |
| Left-click     | Open a floating hunk preview (with Discard / Close buttons)  |
| Right-click    | Discard the hunk directly (no preview)                       |

The handler resolves the hunk covering the clicked line via
`MiniDiff.get_buf_data(buf_id).hunks` and operates on that hunk.

## Hunk preview

The preview is a floating window showing a unified-diff-style rendering
of the hunk:

```
@@ -<ref_start>,<ref_count> +<buf_start>,<buf_count> @@
-<removed line>
+<added line>
...
```

It is built on the reusable [`modal`](modal.md) module and has a
top-right button bar with two buttons:

- **Discard** (red, `DiffDelete`): reset the hunk to its reference text.
- **Close** (gray, `PmenuSbar`, preselected): close the preview.

Keyboard shortcuts: `d` (discard), `q` / `<Esc>` (close). Tab cycles the
buttons, Enter activates, mouse click works too.

The preview opens at the cursor position (`position = "cursor"`).

## Full-file diff view

`diff_gutter.open_file_diff(buf_id)` opens VS Code's "Open Changes"
layout: HEAD (`mini.diff`'s `ref_text`) on the left, the working buffer
on the right, both with `'diff'` enabled.

- The reference buffer is a scratch `nofile` buffer named
  `HEAD • <filename>`, wiped when its window closes.
- `diffopt` defaults include `closeoff`, so closing either window turns
  diff off in the other. An additional `WinClosed` autocmd forces diff
  off on the working window to be safe across nvim versions.
- `q` in either window closes the reference window (and thus leaves diff
  mode). The buffer-local `q` mapping on the working buffer is cleaned
  up when the reference window closes.
- The cursor stays on the working (editable) side.

Reach it by:

- clicking the diff summary in the [statusline](statusline.md),
- `:lua require("diff_gutter").open_file_diff(0)`,
- calling it from your own keymap.

## Hunk navigation (mini.diff)

`mini.diff`'s built-in hunk operators are available regardless of the
clickable gutter:

| Key      | Mode    | Action                              |
| -------- | ------- | ----------------------------------- |
| `gh`     | normal  | Hunk operator (apply / reset / ...) |
| `gH`     | visual  | Hunk operator over a selection      |
| `[h`     | normal  | Previous hunk                       |
| `]h`     | normal  | Next hunk                           |

See `:help mini.diff` for the full reference.

## API

```lua
require("diff_gutter").setup()                 -- wire click handler + highlights
require("diff_gutter").open_file_diff(buf_id?) -- open HEAD-vs-working diff split
```

`open_file_diff(0)` (or with no argument) operates on the current buffer.
