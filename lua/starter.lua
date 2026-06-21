-- lua/starter.lua
--
-- VS Code-style start screen built on `mini.starter`.
--
-- Pure logic / reusable API (no side-effects). Wired up in `lua/plugins.lua`
-- via `require("starter").setup()` after `mini.starter` is available.
-- See AGENTS.md for the lua/ vs plugin/ split rationale.
--
-- Layout (vertically centered, horizontally centered):
--   - Header: a VSVIM ASCII banner plus a one-line tagline.
--   - Sections: "Recent files" (10) and "Builtin actions".
--   - Footer: empty (mini.starter's default hints are verbose, omitted).
--
-- The banner combines two figlet fonts (see BANNER below). It is stored as a
-- single multi-line string (mini.starter accepts `\n` in `header`).

local M = {}

-- vsVIM banner. "vs" (lowercase) uses the "ANSI Shadow" figlet font (filled
-- blocks with drop shadow), "VIM" (uppercase) uses the "Standard" figlet
-- font, so the bold lowercase prefix contrasts with the lighter VIM.
-- Joined side by side with two spaces.
-- Generated with: figlet -f "ANSI Shadow" vs ; figlet -f "Standard" VIM.
local BANNER = [[
██╗   ██╗███████╗   __     _____ __  __
██║   ██║██╔════╝   \ \   / /_ _|  \/  |
██║   ██║███████╗    \ \ / / | || |\/| |
╚██╗ ██╔╝╚════██║     \ V /  | || |  | |
 ╚████╔╝ ███████║      \_/  |___|_|  |_|
  ╚═══╝  ╚══════╝
]]

-- One-line tagline shown beneath the banner.
local TAGLINE = "VS Code-ish, but in Neovim"

-- Build the header string: banner, blank line, tagline.
local function build_header()
	return BANNER .. "\n" .. TAGLINE
end

function M.setup(opts)
	local has_mini, starter = pcall(require, "mini.starter")
	if not has_mini then
		vim.notify("starter: 'mini.starter' not found (run :PackUpdate)", vim.log.levels.ERROR)
		return
	end

	local config = vim.tbl_deep_extend("force", {
		evaluate_single = false,
		items = {
			starter.sections.recent_files(10, false),
			starter.sections.builtin_actions(),
		},
		header = build_header(),
		footer = "",
		content_hooks = {
			starter.gen_hook.adding_bullet(),
			starter.gen_hook.aligning("center", "center"),
		},
	}, opts or {})

	starter.setup(config)
end

return M
