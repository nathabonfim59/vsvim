# Floating terminal (TUI)

Sources:
- [`lua/tui/init.lua`](../lua/tui/init.lua) — the module returned by `require("tui")`
- [`plugin/tui.lua`](../plugin/tui.lua) — auto-sourced; registers `:Tui` + `<leader>gg`

Open any TUI program full-screen in a floating terminal window. Used to
provide the `<leader>gg` lazygit keymap and the statusline's
click-branch-to-open-lazygit feature.

## Module structure

Per `:help lua-module-load` and `:help load-plugins`:

- `lua/tui/init.lua` — the module returned by `require("tui")`. Pure
  logic / reusable API, no side-effects.
- `plugin/tui.lua` — auto-sourced at startup. Calls `tui.setup()` with
  defaults, registers the `:Tui` user command, and maps `<leader>gg` to
  open lazygit.

## Usage

```vim
:Tui lazygit
:Tui btop
:Tui nvim .
```

```lua
require("tui").open({ "lazygit" }, { title = "lazygit" })
require("tui").open("lazygit status", { padding = 2 })  -- string is split on whitespace
require("tui").close_all()
```

## Keymap

| Key          | Action                              |
| ------------ | ----------------------------------- |
| `<leader>gg` | Open lazygit full-screen            |

Set `vim.g.tui_no_default_keymaps = true` before startup to disable the
default keymap. The statusline's git-branch click region also opens
lazygit (focused on the branches panel) via this module.

## Configuration

`setup(opts)` merges `opts` into the defaults:

```lua
require("tui").setup({
  border           = "rounded",
  padding          = 1,           -- cells from the editor edges (0 = truly fullscreen)
  hl               = nil,         -- highlight group for the float bg (nil = NormalFloat)
  start_insert     = true,        -- enter Terminal-mode automatically
  close_on_bufleave = true,       -- close the float when its buffer loses focus
})
```

Per-call overrides can be passed to `open()`:

```lua
require("tui").open({ "btop" }, { title = "btop", padding = 0 })
```

## Behaviour

- **Reuse** — if a float for the same command is already open, it is
  focused instead of opening a new one.
- **Resize** — floats are resized to the editor on `VimResized`.
- **Cleanup** — the float is closed when the terminal job exits
  (`TermClose`) and (optionally) when its buffer loses focus
  (`BufLeave`). The scratch buffer is wiped on close.
- **Binary check** — `open()` refuses to launch a program that isn't on
  `$PATH` and notifies the user instead.

## How it works

A scratch buffer is created with `buftype` left default and `filetype =
"tui"`, a floating window is opened over the whole editor
(`relative = "editor"`, `width = columns - pad*2`, `height = lines -
pad*2`), and a `:terminal` job is attached with `jobstart(cmd, { term =
true })` from inside the float window so the PTY binds to our buffer.
