---
name: neovim-help
description: Look up Neovim (Nvim) help docs from the LOCAL runtime on disk (no network). Use whenever the task involves Nvim APIs, options, Lua stdlib, vim.pack, autocmds, lsp, lspconfig, filetype, plugin development, or any `:help <topic>` reference. Authoritative for the user's installed Nvim version.
---

# Neovim Help (Local Docs)

Look up Nvim documentation from the local runtime on disk. This matches the
user's **installed** Nvim version and requires no network.

## Runtime location

The help files live under `$VIMRUNTIME/doc/`:

- Typical path: `/usr/share/nvim/runtime/doc/`
- Resolve dynamically (works on any install/Nix/macOS): print
  `vim.env.VIMRUNTIME` via a headless nvim, or fall back to
  `/usr/share/nvim/runtime`.

```bash
VRT="$(nvim --headless +'lua io.write(vim.env.VIMRUNTIME)' +qa 2>/dev/null)"
VRT="${VRT:-/usr/share/nvim/runtime}"
echo "$VRT/doc"
```

## Key concept: topics ≠ filenames

A `:help foo` topic maps to a file via *tags*, not filenames. The tag
`|vim.pack|` lives inside `runtime/doc/pack.txt`, **not** `vim.pack.txt`.
Always resolve the topic to its file first, then read the section.

Resolve a topic to a file+line via the tag index:

```bash
# Files containing the tag (top hit is usually the definition):
grep -rl '\*vim\.pack\*' "$VRT/doc" | head

# All occurrences with line numbers:
grep -n '\*vim\.pack\*' "$VRT/doc/pack.txt"
```

Tag convention: topics are wrapped in `*asterisks*` in the source, e.g.
`*vim.pack*`, `*vim.pack.add()*`, `*'clipboard'*`, `*autocmd*`. Escape dots.

## Common doc files

| Want                              | File                          |
|-----------------------------------|-------------------------------|
| `:help vim.pack`, plugin mgmt     | `pack.txt`                    |
| Options (`vim.opt`, `'foo'`)      | `options.txt`                 |
| Lua stdlib, `vim.fn`, `vim.api`   | `lua.txt`, `builtin.txt`      |
| `vim.api.nvim_*`                  | `api.txt`                     |
| Autocmds / events (`PackChanged`) | `autocmd.txt`                 |
| LSP, `vim.lsp`, `vim.diagnostic`  | `lsp.txt`, `diagnostic.txt`   |
| LSP server config                 | `lspconfig.txt` (if present)  |
| Filetypes / `vim.filetype`        | `filetype.txt`                |
| Diagnostics, highlights           | `diagnostic.txt`, `syntax.txt`|
| News / changelog                  | `news.txt`                    |
| Treesitter                        | `treesitter.txt`              |
| Standard built-in plugins         | `pack.txt` (`*standard-plugin*`) |
| Quick UI / floating windows       | `api.txt`, `vim.fn` in `builtin.txt` |

## Reading a section

```bash
# Open the file around a tag (shows surrounding context):
sed -n "$((LINE-5)),$((LINE+60))p" "$VRT/doc/pack.txt"
```

Prefer `read` with `offset`/`limit` over `sed` when possible.

## Interactive fallback (queries the real help system)

Use this to confirm a topic exists or get exact rendered output:

```bash
nvim --headless \
  +'lua io.write(vim.api.nvim_cmd({cmd="help",args={"vim.pack.add()"}},{output=true}))' \
  +qa
```

If output is empty, the topic may not exist in this Nvim version — verify with:

```bash
nvim --headless +'lua print(vim.fn.exists(":help"))' +qa
```

## Cross-references in docs

Follow `|foo|` links by grepping the tag in the same `doc/` dir. Section
headers look like `==...== Title    *tag*`; grep for the tag to jump.

## When NOT to use this skill

- The task is about the user's plugin source code (read the repo instead).
- The user explicitly asks for the *latest/master* doc — then fetch from
  `https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/<file>.txt`
  and say so, noting it may differ from the installed version.

## Gotchas

- The rendered web URL `neovim.io/doc/user/<file>#<tag>` 404s for some files;
  don't rely on it.
- `lua-stdlib` types are *not* on the global `vim.` namespace; see `lua.txt`.
- Help is plain text — strip nothing special, but `|tags|` and `*tags*` are
  markup, not literal text.
