# Keybinding presets

Sources:
- [`lua/presets/init.lua`](../lua/presets/init.lua) — orchestrator
- [`lua/presets/config.lua`](../lua/presets/config.lua) — preset table + persistence
- [`lua/presets/vsvim.lua`](../lua/presets/vsvim.lua) — the vsvim preset
- [`lua/presets/vim.lua`](../lua/presets/vim.lua) — the vim preset
- [`lua/keymaps/vscode.lua`](../lua/keymaps/vscode.lua) — VS Code editing shortcuts (used by vsvim)

vsvim ships two keybinding presets. On first launch the user is prompted
to pick one; the choice is persisted to
`~/.config/vsvim/keybindings.json` and re-applied on every launch.

## Presets

| Name    | Description                                                        |
| ------- | ------------------------------------------------------------------ |
| `vsvim` | VS Code-style editing shortcuts + leader-based picker keymaps. The default. |
| `vim`   | Plain Vim defaults, no leader-based overrides. fff.nvim reachable via `:FindFiles` / `:LiveGrep` / `:GrepWord`. |

A preset is just a Lua module under `lua/presets/` that exposes a single
`apply()` function registering whatever keymaps / commands it wants. The
orchestrator (`presets/init.lua`) resolves which preset to use and calls
its `apply()`.

## Resolution order

1. Saved choice in `keybindings.json` (read by `presets/config.read`).
2. If none saved: apply the default (`vsvim`) so keymaps work right
   away, then prompt the user asynchronously. Once the user picks, the
   choice is persisted and the new preset is applied (stale leader maps
   from the previous preset are deleted first).

In headless mode (no interactive UI) the prompt is skipped and the
default preset is used without persisting anything.

## Switching presets

Re-pick at any time by deleting `~/.config/vsvim/keybindings.json` (or
editing it to `"preset": "vim"` / `"vsvim"`):

```sh
rm ~/.config/vsvim/keybindings.json   # prompt again on next launch
# or
echo '{"preset":"vim"}' > ~/.config/vsvim/keybindings.json
```

## The vsvim preset

`presets/vsvim.lua`'s `apply()` does three things:

1. Calls `require("keymaps.vscode").apply()` to register the full set of
   VS Code text-editing shortcuts (see
   [navigation.md](navigation.md) for the table). This must run after
   `plugins.lua` so `mini.pairs` / `mini.comment` are available.
2. Registers the fff.nvim fuzzy-finder keymaps:
   - `<leader>sf` — search files
   - `<leader>sg` — live grep
   - `<leader>sw` — grep word under cursor
3. Registers buffer / tab management:
   - `<C-w>` — close current editor tab (VS Code style), with a
     Save / Discard / Cancel modal if the buffer has unsaved changes
   - `<leader>bd` — alias for close
   - `<leader>bn` / `<leader>bp` — next / previous editor tab

`<C-w>` shadows Vim's window-command prefix in normal mode (it uses
`nowait = true`); insert mode is left untouched so `<C-w>` (delete word)
still works there.

### Unsaved-changes modal

The close-current-buffer logic shows a centered modal (built on the
reusable [`modal`](modal.md) module) when the buffer is modified:

- **Save** (green, `DiffAdd`) — write the buffer, then close.
- **Discard** (red, `DiffDelete`) — close without writing.
- **Cancel** (gray, `PmenuSbar`) — keep the buffer open.

Keyboard shortcuts: `y` (save), `n` (discard), `q` / `<Esc>` / `<C-c>`
(cancel). The modal opens with `focus = false` so the current buffer
keeps focus and `BufLeave` / `WinLeave` don't fire — this prevents
autowrite or other leave-triggered autocmds from silently saving or
closing the buffer before the user decides.

## The vim preset

`presets/vim.lua`'s `apply()` registers **no keymaps** — it leaves
Vim's defaults untouched. It does expose a few user commands so the
fuzzy finder and tab management stay reachable without leader keys:

| Command        | Action                              |
| -------------- | ----------------------------------- |
| `:FindFiles`   | fff.nvim fuzzy find files           |
| `:LiveGrep`    | fff.nvim live grep                  |
| `:GrepWord`    | fff.nvim grep word under cursor     |
| `:BufferClose` | Close the current editor tab        |

## Adding a preset

1. Create `lua/presets/<name>.lua` with an `apply()` function.
2. Add it to `PRESETS` in [`lua/presets/config.lua`](../lua/presets/config.lua):

```lua
M.PRESETS = {
  { name = "vsvim", desc = "..." },
  { name = "vim",   desc = "..." },
  { name = "my",    desc = "my — my custom keymaps" },
}
```

It will then appear in the first-run prompt and be selectable by editing
`keybindings.json`.
