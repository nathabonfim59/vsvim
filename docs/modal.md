# Modal dialog module

Source: [`lua/modal.lua`](../lua/modal.lua)

A small reusable modal-dialog module with optional clickable buttons,
backdrop, focus guard, and a non-focus mode. Used by
[`diff_gutter`](git-and-hunks.md) (hunk preview) and
[`sidebar`](sidebar.md) (close confirmation), and by the vsvim preset's
unsaved-changes-on-close modal.

## Features

- **Multiple positions**: `"center"` (default), `"cursor"`, `"bottom"`,
  or a custom `{ row = N, col = N }` table.
- **Optional button bar** at the top or bottom, left / right / center
  aligned, with Tab / Shift-Tab navigation, Enter to activate, and mouse
  click support.
- **Optional backdrop** (dimming overlay) behind the modal.
- **Custom keymaps** mapped to action strings.
- **Focus guard** — prevents other code (e.g. `mini.files`' focus-loss
  timer) from stealing focus while the modal is open.
- **Non-focus mode** — open the float without stealing focus from the
  current buffer, so no `BufLeave` / `WinLeave` fires on it. This avoids
  autowrite and other leave-triggered side effects when the caller's
  buffer has unsaved changes.
- **`on_open` / `on_close` callbacks** for caller-specific setup and
  cleanup.
- **Auto-close** on `WinLeave` / `BufLeave` (focus mode) or when the
  original buffer / window is left (non-focus mode).

## API

```lua
local modal = require("modal")

local ctx = modal.open({
  title       = " Title ",          -- string or { { text, hl } } table
  lines       = { "line 1", "line 2" },
  position    = "center",           -- "center" | "cursor" | "bottom" | {row, col}
  width       = 60,                 -- auto-calculated if omitted
  max_width   = 80,
  max_height  = 20,
  min_width   = 20,
  border      = "rounded",
  filetype    = "diff",             -- optional
  win_options = { cursorline = false },  -- window-local opts
  backdrop    = true,
  backdrop_hl = "NormalFloat",
  noautocmd   = true,               -- pass noautocmd=true to nvim_open_win
  focus       = true,               -- steal focus (default true)
  focus_guard = false,              -- prevent focus from leaving the modal
  buttons = {
    position    = "bottom",         -- "top" | "bottom"
    align       = "right",          -- "left" | "right" | "center"
    padding     = 2,                -- blank lines between bar and content
    spacing     = "  ",             -- spacing between buttons
    selected_hl = "PmenuSel",       -- keyboard-selected button highlight
    items = {
      { label = " Save ",    hl = "DiffAdd",    action = "save",    default = true },
      { label = " Discard ", hl = "DiffDelete", action = "discard" },
      { label = " Cancel ",  hl = "PmenuSbar",  action = "cancel"  },
    },
  },
  keymaps = {
    ["y"]     = "save",
    ["n"]     = "discard",
    ["q"]     = "cancel",
    ["<Esc>"] = "cancel",
  },
  on_action = function(action)      -- called (scheduled) after close
    if action == "save" then ... end
  end,
  on_open   = function(ctx) ... end,
  on_close  = function() ... end,
})

ctx.close()       -- close programmatically
ctx.run_action(a) -- close + dispatch on_action(a)
```

## Button bar

When `buttons` is provided, a button bar is rendered either above or
below the content. Each button has a `label`, a highlight group (`hl`),
and an `action` string. The first item with `default = true` is
preselected for keyboard navigation.

Built-in keymaps when buttons are present:

| Key        | Action                              |
| ---------- | ----------------------------------- |
| `<Tab>`    | Next button                         |
| `<S-Tab>`  | Previous button                     |
| `<CR>`     | Activate selected button            |
| `<LeftMouse>` | Click a button to activate it    |

Mouse clicks dispatch by column position; non-button clicks fall through
to normal cursor positioning (focus mode) or to the original window
(non-focus mode).

Button highlights are reapplied on every selection change. The
keyboard-selected button gets `selected_hl` (default `PmenuSel`); the
others keep their own `hl`.

## Non-focus mode

Set `focus = false` to open the float without entering it. The current
buffer keeps focus, no `BufLeave` / `WinLeave` fires on it, and keymaps
are set on the current buffer instead of the modal buffer. This is what
the vsvim preset uses for the unsaved-changes-on-close modal, so
autowrite and other leave-triggered autocmds can't silently save or
close the buffer before the user decides.

In non-focus mode the modal also auto-closes when the original window is
closed (`WinClosed`).

## Focus guard

Set `focus_guard = true` to prevent other code from pulling focus away
while the modal is open. This temporarily wraps `vim.api.nvim_set_current_win`
so external calls that try to move focus elsewhere are ignored. The
wrapper is restored before close so close-time focus changes work.

The sidebar's close-confirmation modal uses this so `mini.files`'
focus-loss timer can't reopen a second modal in the gap between closing
the first one and running the chosen action.
