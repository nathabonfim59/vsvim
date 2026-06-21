# Navigation & editing keybindings

Source: [`lua/keymaps/vscode.lua`](../lua/keymaps/vscode.lua)

The **vsvim** preset applies a complete set of VS Code text-editing
shortcuts on top of Vim defaults. The design goal is a "no modes"
workflow: every common editing operation is reachable from insert mode
without manually switching to normal mode.

These mappings are registered by `require("keymaps.vscode").apply()`,
which is called from [`lua/presets/vsvim.lua`](../lua/presets/vsvim.lua)
after `mini.pairs` / `mini.comment` / `mini.completion` are set up. The
**vim** preset does not apply any of them.

## Cursor movement

| Key              | Modes        | Action                                       |
| ---------------- | ------------ | -------------------------------------------- |
| `<Home>`         | n i v        | Toggle first-non-blank / column 0            |
| `<End>`          | n            | End of line (`$`)                            |
| `<C-Home>`       | n i v        | Top of file                                  |
| `<C-End>`        | n i v        | Bottom of file                               |
| `<C-Left>`       | n v / i      | Previous word (`b` / `<C-o>b`)               |
| `<C-Right>`      | n v / i      | Next word (`w` / `<C-o>w`)                   |
| `<C-g>`          | n i          | Go to line (prompts for line number)         |

## Selection

| Key              | Action                          |
| ---------------- | -------------------------------- |
| `<S-Left>`       | Select char left                 |
| `<S-Right>`      | Select char right                |
| `<S-Up>`         | Select line up                   |
| `<S-Down>`       | Select line down                 |
| `<S-Home>`       | Select to first non-blank        |
| `<S-End>`        | Select to end of line            |
| `<C-S-Left>`     | Select word left                 |
| `<C-S-Right>`    | Select word right                |
| `<C-S-Home>`     | Select to top of file            |
| `<C-S-End>`      | Select to bottom of file         |
| `<C-a>`          | Select all                       |

Each shift-arrow mapping has three variants (normal / insert / visual) so
selection works no matter which mode you're in. In insert mode it uses
`<C-o>v` to enter visual mode persistently.

## Clipboard

`options.lua` sets `clipboard=unnamed,unnamedplus`, so the default
registers always sync with the OS clipboard. The Ctrl keys map on top:

| Key        | Modes   | Action                              |
| ---------- | ------- | ----------------------------------- |
| `<C-c>`    | v n i   | Copy selection / current line       |
| `<C-x>`    | v n i   | Cut selection / current line        |
| `<C-v>`    | v n i   | Paste (visual: replace selection)   |

## Undo / redo

| Key          | Modes   | Action       |
| ------------ | ------- | ------------ |
| `<C-z>`      | n v i   | Undo         |
| `<C-y>`      | n v i   | Redo         |
| `<C-S-z>`    | n v i   | Redo         |

## Delete

| Key            | Modes   | Action                       |
| -------------- | ------- | ---------------------------- |
| `<C-BS>`       | i n     | Delete word to the left      |
| `<C-Del>`      | i n     | Delete word to the right     |
| `<C-S-k>`      | n i v   | Delete current line          |

## Line operations

| Key              | Modes   | Action                              |
| ---------------- | ------- | ----------------------------------- |
| `<A-Up>`         | n i v   | Move line / selection up            |
| `<A-Down>`       | n i v   | Move line / selection down          |
| `<S-A-Up>`       | n i v   | Duplicate line / selection up       |
| `<S-A-Down>`     | n i v   | Duplicate line / selection down     |
| `<C-CR>`         | n i     | Insert line below                   |
| `<C-S-CR>`       | n i     | Insert line above                   |
| `<C-S-\>`        | n v i   | Jump to matching bracket            |

## Indentation & smart keys (mini.keymap)

| Key      | Action                                                            |
| -------- | ----------------------------------------------------------------- |
| `<Tab>`  | Accept completion → expand snippet → increase indent → `<Tab>`    |
| `<S-Tab>`| Previous completion → decrease indent → `<S-Tab>`                 |
| `<CR>`   | Accept completion → `mini.pairs` CR → `<CR>`                      |
| `<BS>`   | `mini.pairs` BS (unwrap pairs) → `<BS>`                           |

In normal / visual mode, `<Tab>` / `<S-Tab>` indent / dedent lines
(`>>` / `<<` / `>gv` / `<gv`).

`mini.completion` shows the popup with nothing selected initially; the
custom Tab step selects the first candidate (`<C-n>`) and immediately
confirms it (`<C-y>`), so a single Tab press accepts — matching VS Code.

## Comments (mini.comment)

| Key          | Modes   | Action              |
| ------------ | ------- | ------------------- |
| `<C-/>`      | n i v   | Toggle line comment |
| `<S-A-a>`    | n i v   | Toggle block comment |

## Find / replace

| Key          | Modes   | Action                                       |
| ------------ | ------- | -------------------------------------------- |
| `<C-f>`      | n i     | Open incremental search                      |
| `<F3>`       | n v i   | Next match                                   |
| `<S-F3>`     | n v i   | Previous match                               |
| `<C-h>`      | n i     | Substitute (pre-fills `:%s/`)                |
| `<C-d>`      | n i v   | Jump to next occurrence of word / selection  |
| `<C-S-l>`    | n i     | Highlight all occurrences of word            |

## Format

| Key          | Modes   | Action                                       |
| ------------ | ------- | -------------------------------------------- |
| `<S-A-f>`    | n i v   | LSP format document (or selection in visual) |

## Misc

| Key          | Modes   | Action                                       |
| ------------ | ------- | -------------------------------------------- |
| `<A-z>`      | n i     | Toggle word wrap                             |
| `<C-b>`      | n i     | Toggle sidebar filepicker                    |
| `<C-`>`      | n i     | Toggle terminal (`:Tui`)                     |
| `<C-S-[>`    | n v i   | Fold                                         |
| `<C-S-]>`    | n v i   | Unfold                                       |

## Buffer / tab management (vsvim preset)

These come from [`lua/presets/vsvim.lua`](../lua/presets/vsvim.lua), not
from `keymaps/vscode.lua`, but are listed here for completeness.

| Key          | Action                                       |
| ------------ | -------------------------------------------- |
| `<C-w>`      | Close current editor tab (Save/Discard/Cancel modal if unsaved) |
| `<leader>bd` | Close current editor tab (alias)             |
| `<leader>bn` | Next editor tab                              |
| `<leader>bp` | Previous editor tab                          |

`<C-w>` shadows Vim's window-command prefix in normal mode. Window
management is rarely needed in the single-window vsvim workflow; insert
mode is left untouched so `<C-w>` (delete word) still works there.

## Fuzzy finder (vsvim preset)

| Key          | Action                              |
| ------------ | ----------------------------------- |
| `<leader>sf` | Search [F]iles (fff.nvim)           |
| `<leader>sg` | Search [G]rep (fff.nvim live grep)  |
| `<leader>sw` | Search [W]ord under cursor          |
| `<leader>gg` | Open lazygit (floating terminal)    |

In the **vim** preset these are exposed as `:FindFiles`, `:LiveGrep`,
`:GrepWord`, and `:Tui lazygit` instead.
