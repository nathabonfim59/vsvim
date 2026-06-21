-- lua/tabline.lua
--
-- VS Code-style tabline built on `mini.tabline`.
--
-- Pure logic / reusable API (no side-effects). Wired up in `lua/plugins.lua`
-- via `require("tabline").setup()` after `mini.tabline` is added with
-- `vim.pack`. See AGENTS.md for the lua/ vs plugin/ split rationale.
--
-- Design goals (mimic VS Code's editor tab bar):
--   - One row of "editor tabs", one per listed buffer.
--   - Colored filetype icon + bare filename (mini.icons).
--   - Dirty indicator: VS Code shows a filled dot while the file has unsaved
--     changes and a cross once it is clean. We mirror that exactly.
--   - The whole tab is clickable to switch buffers (provided by
--     mini.tabline's `%N@MiniTablineSwitchBuffer@` wrapper), just like
--     clicking a VS Code tab.
--   - The active tab gets a distinct, brighter highlight so it reads as
--     "selected", same as VS Code's active tab.
--
-- Highlighting is derived from the active colorscheme rather than hard-coded:
-- `set_highlights()` pulls VS Code's exact tab palette from the live
-- `TabLineSel` / `TabLine` / `TabLineFill` groups that vscode.nvim populates
-- (vscTabCurrent / vscTabOther / vscTabOutside), and tints the dirty indicator
-- from the theme's git/diagnostic colors, the same approach barbar.nvim uses
-- for its `Buffer*` groups. No hardcoded hex fallbacks are used.

local M = {}

-- Glyphs. Populated at setup() time from MiniIcons custom filetype entries
-- ("vsvim-modified" / "vsvim-close"), so users can override them through the
-- standard `mini.icons` config. The defaults are registered in lua/plugins.lua.
M.GLYPHS = {}

-- Resolve a highlight definition, following links so we read the real colors.
-- Returns the table from `nvim_get_hl` (possibly empty), never nil.
local function resolve(group)
	return vim.api.nvim_get_hl(0, { name = group, link = false }) or {}
end

-- Format a single tab's label.
--
-- `mini.tabline` calls this with `(buf_id, label)` where `label` is the
-- already-deduplicated filename. The returned string is placed inside the
-- tab's clickable region, so it must be plain text (no |'tabline'| items).
--
-- Layout (mirrors VS Code):  ` <icon> <name>      <indicator> `
-- The indicator is the vsvim-modified icon when modified, vsvim-close when clean.
function M.format(buf_id, label)
	local MiniTabline = _G.MiniTabline
	local icon = ""
	if MiniTabline and MiniTabline.config.show_icons then
		local ok, resolved = pcall(M.get_icon, buf_id)
		if ok and resolved and resolved ~= "" then
			icon = resolved .. " "
		end
	end

	local indicator = vim.bo[buf_id].modified and M.GLYPHS.modified or M.GLYPHS.close
	indicator = indicator or ""
	return string.format(" %s%s     %s ", icon, label, indicator)
end

-- Resolve a colored filetype icon for `buf_id` via mini.icons (with a
-- graceful fallback to nvim-web-devicons, then nothing). Mirrors
-- `mini.tabline`'s own resolution order but per-buffer so the format
-- function stays self-contained.
function M.get_icon(buf_id)
	local name = vim.api.nvim_buf_get_name(buf_id)
	if name == "" then return "" end

	if _G.MiniIcons then
		local icon = (_G.MiniIcons.get("file", name))
		return icon or ""
	end

	local ok, devicons = pcall(require, "nvim-web-devicons")
	if ok then
		return (devicons.get_icon(vim.fn.fnamemodify(name, ":t"), nil, { default = true })) or ""
	end
	return ""
end

-- VS Code-flavored highlight groups.
--
-- mini.tabline defines: MiniTablineCurrent / Visible / Hidden (+ Modified*
-- variants), MiniTablineFill, MiniTablineTabpagesection, MiniTablineTrunc.
--
-- Rather than hard-coding greys (which drift away from the active
-- colorscheme), we pull the live colors from the vscode.nvim theme. The
-- theme already maps VS Code's exact tab palette onto the standard groups:
--
--   TabLineSel  -> vscTabCurrent  (active tab background)
--   TabLine     -> vscTabOther    (inactive tab background)
--   TabLineFill -> vscTabOutside  (the empty area around the tabs)
--
-- Deriving from those groups means our tabs always match the editor chrome,
-- adapt to light/dark backgrounds automatically, and survive colorscheme
-- reloads. The `●` modified indicator is tinted with the theme's git/dirty
-- colors (GitSignsChange / DiagnosticWarn) the same way barbar.nvim does it.
function M.set_highlights()
	local hl = vim.api.nvim_set_hl

	-- All colors are resolved from highlight groups defined by the active
	-- colorscheme (vscode.nvim populates these from its `vsc*` palette), so the
	-- tabline tracks the theme automatically. No hardcoded hex fallbacks.
	local function fg(names)
		for _, name in ipairs(names) do
			local c = resolve(name).fg
			if c ~= nil then return c end
		end
		return nil
	end
	local function bg(names)
		for _, name in ipairs(names) do
			local c = resolve(name).bg
			if c ~= nil then return c end
		end
		return nil
	end

	-- Active tab: background and full-bright foreground from the theme's
	-- standard tab groups.
	local sel_bg = bg({ "TabLineSel" })
	local sel_fg = fg({ "TabLineSel", "TabLine" })

	-- Inactive (hidden) tab background and foreground from the theme's tab
	-- groups. Reuse CursorLineNr/BufferVisible/NonText as progressively dimmer
	-- foreground sources.
	local other_bg = bg({ "TabLine" })
	local other_fg = fg({ "CursorLineNr", "BufferVisible", "NonText" })

	-- Empty area around the tabs.
	local fill_bg = bg({ "TabLineFill" })
	local fill_fg = fg({ "TabLineFill" })

	-- Dirty/modified tint from the theme's git/diagnostic colors so it
	-- matches inlined diffs.
	local dirty_fg = fg({ "GitSignsChange", "DiagnosticWarn" })

	-- Helper to skip a highlight when a required color is missing.
	local function set_if(name, opts)
		if opts.bg or opts.fg or opts.sp then
			hl(0, name, vim.tbl_extend("force", { default = true }, opts))
		end
	end

	-- Active tab: solid background matching the editor, bold filename so it
	-- reads as "selected" like VS Code's active editor tab.
	set_if("MiniTablineCurrent", { bg = sel_bg, fg = sel_fg, bold = true })
	-- Visible (open in another window): same family, not bold.
	set_if("MiniTablineVisible", { bg = sel_bg, fg = sel_fg })
	-- Hidden: muted background, greyed-out text.
	set_if("MiniTablineHidden", { bg = other_bg, fg = other_fg })

	-- Modified variants reuse the tab backgrounds but warm foreground so the
	-- modified indicator reads as "unsaved" (mirrors barbar's `*Mod` groups).
	set_if("MiniTablineModifiedCurrent", { bg = sel_bg, fg = dirty_fg, bold = true })
	set_if("MiniTablineModifiedVisible", { bg = sel_bg, fg = dirty_fg })
	set_if("MiniTablineModifiedHidden", { bg = other_bg, fg = dirty_fg })

	-- The empty area to the right of the last tab blends with the tab row.
	set_if("MiniTablineFill", { bg = fill_bg })
	-- The `Tab N/M` section shown when there are multiple tabpages.
	set_if("MiniTablineTabpagesection", { bg = sel_bg, fg = sel_fg, bold = true })
	-- Truncation arrows (`‹`/`›`) when tabs overflow.
	set_if("MiniTablineTrunc", { fg = fill_fg })
end

-- Apply VS Code-style tabline.
-- `opts` is forwarded to `mini.tabline.setup()` (merged with our defaults).
function M.setup(opts)
	local has_mini, mini_tabline = pcall(require, "mini.tabline")
	if not has_mini then
		vim.notify("tabline: 'mini.tabline' not found (run :PackUpdate)", vim.log.levels.ERROR)
		return
	end

	-- mini.icons gives colored filetype icons like VS Code. Set it up so
	-- `get_icon` can use it; no-op if the module isn't present.
	local has_icons, mini_icons = pcall(require, "mini.icons")
	if has_icons and not _G.MiniIcons then
		mini_icons.setup()
		-- Provide the devicons API too, in case other plugins look for it.
		pcall(mini_icons.mock_nvim_web_devicons)
	end

	-- Resolve tab-state indicators from MiniIcons custom filetype entries.
	-- These are registered in lua/plugins.lua, but users can override them by
	-- configuring mini.icons before vsvim loads.
	if _G.MiniIcons then
		M.GLYPHS.modified = _G.MiniIcons.get("filetype", "vsvim-modified")
		M.GLYPHS.close = _G.MiniIcons.get("filetype", "vsvim-close")
	end

	mini_tabline.setup(vim.tbl_deep_extend("force", {
		show_icons = true,
		format = M.format,
		-- VS Code has no tabpage concept; keep it subtle on the left.
		tabpage_section = "left",
	}, opts or {}))

	-- Re-apply our highlights after any colorscheme switch so they survive
	-- `:colorscheme` reloads (mini.tabline resets defaults on ColorScheme).
	local group = vim.api.nvim_create_augroup("vsvim-tabline-hl", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = M.set_highlights,
	})
	M.set_highlights()
end

return M
