-- presets/init.lua
--
-- Orchestrates the keybinding-preset system.
--
-- vsvim ships two presets (see presets/config.lua's PRESETS table):
--   - "vsvim"  leader-based keymaps (<leader>sf, <leader>sg, ...)
--   - "vim"    plain Vim defaults, no leader overrides
--
-- The chosen preset is persisted in vsvim's OWN config directory
-- (stdpath("config")/keybindings.json, i.e. ~/.config/vsvim/keybindings.json
-- because NVIM_APPNAME=vsvim), never in ~/.config/nvim.
--
-- On first run the user is prompted via vim.ui.select() to pick a preset.
-- The apply step happens after plugins.lua has run so presets can rely on
-- fff.nvim being available.

local M = {}

local config = require("presets.config")

-- Apply the named preset's keymaps. Errors if the preset module is missing.
function M.apply(name)
	local mod = require("presets." .. name)
	if type(mod.apply) ~= "function" then
		error(("presets: preset '%s' has no apply() function"):format(name))
	end
	mod.apply()
	M._applied = name
end

-- Resolve which preset to use and apply it.
--
-- Resolution order:
--   1. Saved choice in keybindings.json (presets/config.read)
--   2. If none saved: prompt the user (async), apply the vsvim preset in the
--      meantime so the editor is usable, and persist the choice on selection.
function M.setup()
	local saved = config.read()

	if saved and config.is_known(saved) then
		-- Existing user: apply immediately.
		M.apply(saved)
		return
	end

	-- First run: apply the default so keymaps work right away, then prompt.
	-- The prompt is async (vim.ui.select); once the user picks, we re-apply.
	M.apply("vsvim")
	config.prompt(function(name)
		-- Only re-apply if the choice differs from what's already live.
		if name ~= M._applied then
			-- Clear leader-based maps from the vsvim preset before applying vim,
			-- so a switch to "vim" doesn't leave stale <leader> mappings around.
			-- (Simplest correct approach: delete our known maps.)
			if M._applied == "vsvim" then
				for _, lhs in ipairs({
					"<leader>sf",
					"<leader>sg",
					"<leader>sw",
					"<C-p>",
					"<C-S-p>",
					"<C-S-f>",
					"<C-Tab>",
					"<C-S-Tab>",
				}) do
					pcall(vim.keymap.del, "n", lhs)
				end
			end
			M.apply(name)
		end
	end)
end

return M
