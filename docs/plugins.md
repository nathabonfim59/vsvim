# Plugins

Source: [`lua/plugins.lua`](../lua/plugins.lua)

vsvim uses Neovim 0.12's built-in [`vim.pack`](https://neovim.io/doc/user/vim.pack.html)
for plugin management, no external plugin manager. Plugins are added
with `vim.pack.add({ ... })` and live under vsvim's own data directory
(`~/.local/share/vsvim`) thanks to `$NVIM_APPNAME=vsvim`.

## Plugin list

| Plugin                                                       | Purpose                                              |
| ------------------------------------------------------------ | ---------------------------------------------------- |
| [`mini.nvim`](https://github.com/nvim-mini/mini.nvim)        | Library: tabline, statusline, files, diff, git, icons, pairs, comment, completion, keymap, pick, extra |
| [`fff.nvim`](https://github.com/dmtrKovalenko/fff.nvim)      | Fuzzy finder (`<leader>sf` / `<leader>sg` / `<leader>sw`), file/grep backend for the Quick Open pickers |
| [`vscode.nvim`](https://github.com/Mofiqul/vscode.nvim)      | VS Code Dark+ / Light+ colorscheme                   |

`mini.nvim` loads lazily per module, so adding the whole repo doesn't
start anything until a module's `setup()` runs.

## mini.nvim modules used

| Module        | Setup location     | Used by                              |
| ------------- | ------------------ | ------------------------------------ |
| `mini.icons`  | `plugins.lua`      | tabline, statusline (filetype / directory / git glyphs) |
| `mini.git`    | `plugins.lua`      | statusline `section_git` (`vim.b.minigit_summary_string`) |
| `mini.diff`   | `plugins.lua`      | [diff gutter](git-and-hunks.md)      |
| `mini.pairs`  | `plugins.lua`      | auto-close brackets / quotes         |
| `mini.comment`| `plugins.lua`      | `gc` / `gcc` / `gb` comment operators (Ctrl+/ and Shift+Alt+A) |
| `mini.completion` | `plugins.lua`  | completion popup for `mini.keymap`'s smart-Tab / Enter |
| `mini.pick`   | `plugins.lua`      | Quick Open / command palette / buffer picker ([navigation.md](navigation.md)) |
| `mini.extra`  | `plugins.lua`      | commands/keymaps sources for the command palette |
| `mini.keymap` | `keymaps/vscode.lua` | smart Tab / S-Tab / CR / BS multisteps |
| `mini.files`  | `sidebar.lua`      | [sidebar filepicker](sidebar.md)     |
| `mini.tabline`| `tabline.lua`      | [editor tab bar](tabline.md)         |
| `mini.statusline` | `statusline.lua`| [status bar](statusline.md)          |
| `mini.starter`| `starter.lua`      | start screen (ASCII banner, recent files, builtin actions) |

## Colorscheme

`vscode.nvim` is applied on startup:

```lua
vim.o.background = "dark"
pcall(vim.cmd.colorscheme, "vscode")
```

`background` is set before the colorscheme loads so `vscode.nvim` picks
its Dark+ variant. `pcall` swallows the not-yet-installed error on a
fresh checkout; `vim.pack` installs `vscode.nvim` on first launch and
the colorscheme activates automatically on the next startup.

All chrome highlights (tabline, statusline, diff gutter, modals) are
derived from the live theme rather than hardcoded, and re-applied on
every `ColorScheme` event so they survive colorscheme reloads.

## Custom mini.icons entries

Two custom filetype entries are registered so the tabline's modified /
close indicators can be overridden through the standard `mini.icons`
config:

```lua
require("mini.icons").setup({
  filetype = {
    ["vsvim-modified"] = { glyph = "●", hl = "MiniIconsRed" },
    ["vsvim-close"]    = { glyph = "×", hl = "MiniIconsGrey" },
  },
})
```

## fff.nvim binary

`fff.nvim` ships a prebuilt binary that is built on install. The
`PackChanged` autocmd triggers `require("fff.download").download_or_build_binary()`
when `fff.nvim` is installed:

```lua
vim.api.nvim_create_autocmd("PackChanged", {
  group = vim.api.nvim_create_augroup("fff-install", { clear = true }),
  callback = function(ev)
    if ev.data.spec.name == "fff.nvim" and ev.data.kind == "install" then
      if not ev.data.active then vim.cmd.packadd("fff.nvim") end
      require("fff.download").download_or_build_binary()
    end
  end,
})
```

`fff.nvim` is also preconfigured via `vim.g.fff` before it loads:

```lua
vim.g.fff = {
  lazy_sync = true,
  debug = { enabled = true, show_scores = true },
}
```

## Updating plugins

Use the built-in `vim.pack` commands:

```vim
:PackUpdate       " install / update plugins
:PackStatus       " show plugin status
:PackClean        " remove unused plugins
```

See `:help vim.pack` for the full reference.
