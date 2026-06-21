-- presets/config.lua
--
-- Loads and persists the user's chosen keybinding preset to vsvim's OWN
-- config directory (e.g. ~/.config/vsvim/keybindings.json), never to
-- ~/.config/nvim. Isolation is achieved via $NVIM_APPNAME=vsvim (see the
-- `vsvim` binary and :help $NVIM_APPNAME), so stdpath("config") already
-- points at the vsvim scope.
--
-- On first run (no saved choice), the user is prompted with vim.ui.select()
-- to pick a preset; the choice is then persisted.

local M = {}

-- All available presets, in display order. Each value is the module name
-- under lua/presets/ that defines that preset's keymaps (see presets.init).
M.PRESETS = {
	{ name = "vsvim", desc = "vsvim: leader-based keymaps (<leader>sf, <leader>sg, ...)" },
	{ name = "vim", desc = "vim: plain Vim defaults, no leader-based overrides" },
}

-- File used to remember the choice. Lives under stdpath("config"), which is
-- the vsvim scope because NVIM_APPNAME=vsvim.
function M.path()
	return vim.fn.stdpath("config") .. "/keybindings.json"
end

-- Read the saved preset name, or nil if none chosen yet / unreadable.
function M.read()
	local p = M.path()
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local body = f:read("*a")
	f:close()
	if not body or body == "" then
		return nil
	end
	local ok, data = pcall(vim.fn.json_decode, body)
	if not ok or type(data) ~= "table" then
		return nil
	end
	return data.preset
end

-- Persist the chosen preset name. Creates the config dir if needed.
function M.write(preset)
	local dir = vim.fn.stdpath("config")
	vim.fn.mkdir(dir, "p")
	local body = vim.fn.json_encode({ preset = preset })
	local f, err = io.open(M.path(), "w")
	if not f then
		vim.notify(("vsvim: could not save keybinding choice (%s)"):format(err), vim.log.levels.WARN)
		return false
	end
	f:write(body)
	f:close()
	return true
end

-- Validate that a preset name is known to us.
function M.is_known(name)
	for _, p in ipairs(M.PRESETS) do
		if p.name == name then
			return true
		end
	end
	return false
end

-- True when there is an interactive UI attached (i.e. not headless). The
-- default vim.ui.select() blocks forever with no TTY, so we must skip the
-- prompt and fall back to the default preset in that case.
local function interactive()
	return #vim.api.nvim_list_uis() > 0
end

-- Prompt the user (async) to choose a preset, persist the result, then call
-- `on_choice(name)`. Used on first run. When there is no interactive UI
-- (headless mode), no prompt is shown and `on_choice` is called with the
-- default preset name without persisting anything.
function M.prompt(on_choice)
	if not interactive() then
		on_choice(M.PRESETS[1].name)
		return
	end

	local items = {}
	for _, p in ipairs(M.PRESETS) do
		items[#items + 1] = { name = p.name, desc = p.desc }
	end

	vim.ui.select(items, {
		prompt = "vsvim: choose your keybindings",
		format_item = function(item)
			return item.desc
		end,
	}, function(choice)
		if not choice then
			-- User cancelled: default to the vsvim preset but don't save,
			-- so they get prompted again next time.
			vim.notify("vsvim: no selection, using default 'vsvim' keybindings", vim.log.levels.INFO)
			on_choice("vsvim")
			return
		end
		M.write(choice.name)
		vim.notify(("vsvim: keybindings set to '%s' (saved to %s)"):format(choice.name, M.path()), vim.log.levels.INFO)
		on_choice(choice.name)
	end)
end

return M
