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
--   - Dirty indicator: VS Code shows a `●` while the file has unsaved
--     changes and a `×` once it is clean. We mirror that exactly.
--   - The whole tab is clickable to switch buffers (provided by
--     mini.tabline's `%N@MiniTablineSwitchBuffer@` wrapper) — just like
--     clicking a VS Code tab.
--   - The active tab gets a distinct, brighter highlight so it reads as
--     "selected", same as VS Code's active tab.

local M = {}

-- Glyphs. Kept as module-level constants so they're easy to tweak.
M.GLYPHS = {
	modified = "●", -- shown when `vim.bo[buf].modified` (VS Code shows a filled dot)
	close = "×", -- shown when clean (VS Code's close affordance)
}

-- Format a single tab's label.
--
-- `mini.tabline` calls this with `(buf_id, label)` where `label` is the
-- already-deduplicated filename. The returned string is placed inside the
-- tab's clickable region, so it must be plain text (no |'tabline'| items).
--
-- Layout (mirrors VS Code):  ` <icon> <name>      <indicator> `
-- The indicator is `●` when modified, `×` when clean.
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
-- We override the defaults so the active tab "pops" like VS Code's:
--   - Active tab: brighter background + bold filename.
--   - Inactive tabs: muted.
--   - The fill (empty right area) blends with the tab row.
-- These link to standard groups so they adapt to any colorscheme; users can
-- override after setup with |nvim_set_hl()|.
function M.set_highlights()
	local hl = vim.api.nvim_set_hl
	-- Active tab: solid, slightly brighter than the editor background, bold.
	hl(0, "MiniTablineCurrent", { default = true, ctermbg = 235, ctermfg = 231, bg = "#2b2d33", fg = "#e8eaed", bold = true })
	-- Visible (shown in another window): same family, not bold.
	hl(0, "MiniTablineVisible", { default = true, ctermbg = 234, ctermfg = 250, bg = "#222428", fg = "#c8cbd0" })
	-- Hidden: dimmed.
	hl(0, "MiniTablineHidden", { default = true, ctermbg = 234, ctermfg = 240, bg = "#222428", fg = "#6b7079" })

	-- Modified variants reuse the same backgrounds but warm foreground so the
	-- `●` reads as "unsaved". VS Code tints the whole tab; we tint the text.
	hl(0, "MiniTablineModifiedCurrent", { default = true, ctermbg = 235, ctermfg = 222, bg = "#2b2d33", fg = "#e5c07b", bold = true })
	hl(0, "MiniTablineModifiedVisible", { default = true, ctermbg = 234, ctermfg = 180, bg = "#222428", fg = "#c9b27a" })
	hl(0, "MiniTablineModifiedHidden", { default = true, ctermbg = 234, ctermfg = 95, bg = "#222428", fg = "#8a7a5a" })

	-- The empty area to the right of the last tab.
	hl(0, "MiniTablineFill", { default = true, ctermbg = 234, bg = "#1b1c20" })
	-- The `Tab N/M` section shown when there are multiple tabpages.
	hl(0, "MiniTablineTabpagesection", { default = true, ctermbg = 238, ctermfg = 231, bg = "#3a3d44", fg = "#e8eaed", bold = true })
	-- Truncation arrows (`‹`/`›`) when tabs overflow.
	hl(0, "MiniTablineTrunc", { default = true, ctermfg = 245, fg = "#8b909a" })
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
