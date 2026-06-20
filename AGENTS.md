# AGENTS.md

Write commit messages in conventional commits format (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, optional scope).

## Plugin structure (per `:help lua-module-load` + `:help load-plugins`)

Keep logic and auto-sourced entry points separate:

- `lua/<plugin>/init.lua` — the module returned by `require("<plugin>")`. Pure logic/functions, no side-effects. Loaded on demand.
- `plugin/<plugin>.lua` — auto-sourced at startup (`:runtime! plugin/**/*.{vim,lua}`). Put `setup()` calls, user commands, and default keymaps here.

Don't mix the two: `lua/` is not auto-sourced, and `plugin/` should not hold the reusable API.
