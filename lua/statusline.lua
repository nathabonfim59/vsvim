-- lua/statusline.lua
--
-- VS Code-style statusline built on `mini.statusline`.
--
-- Pure logic / reusable API (no side-effects). Wired up in `lua/plugins.lua`
-- via `require("statusline").setup()` after `mini.statusline` is added with
-- `vim.pack`. See AGENTS.md for the lua/ vs plugin/ split rationale.
--
-- Design goals (mimic VS Code's status bar, the solid blue strip at the
-- very bottom of the window):
--   - One solid bar spanning the full width, not segmented "bubbles".
--     VS Code's status bar has no separators between sections; everything
--     sits on the same blue background separated only by spacing.
--   - Left side: git branch (icon resolved from MiniIcons) + dirty/sync indicator.
--   - Right side: errors/warnings counts (icons resolved from diagnostic signs),
--     cursor position "Ln %l, Col %c", indentation (Spaces:N / Tabs), encoding,
--     EOL mode, and the language mode (filetype).
--   - White-on-blue text. The exact blue is VS Code's status-bar blue, which
--     the vscode.nvim palette exposes as `vscDarkBlue` (#223E55 in dark,
--     #007ACC in light, the latter being *literally* VS Code's value).
--   - Inactive windows get a dimmed variant, mirroring VS Code's unfocused
--     status bar.
--
-- Highlighting is derived from the active colorscheme rather than hard-coded:
-- `set_highlights()` resolves colors from the live groups that vscode.nvim
-- populates (StatusLine / StatusLineNC / vsc*), falling back to the standard
-- StatusLine groups when the theme does not provide VS Code-specific values.

local M = {}

-- Resolve a highlight definition, following links so we read the real colors.
-- Returns the table from `nvim_get_hl` (possibly empty), never nil.
local function resolve(group)
	return vim.api.nvim_get_hl(0, { name = group, link = false }) or {}
end

-- Icon glyphs used in the bar. Resolved at setup() time from live sources
-- (MiniIcons and vim.diagnostic.config().signs.text) so they track the user's
-- icon/font configuration. No hardcoded fallbacks: if a source is unavailable,
-- the corresponding section omits the glyph.
M.GLYPHS = {}

-- Sections ----------------------------------------------------------------
--
-- Each returns a string suitable for one statusline segment (no surrounding
-- spaces, `combine_groups` pads them). Return "" to omit. We reuse
-- mini.statusline's built-in sections where they already do the right thing
-- (truncation, icon resolution, etc.) and only override the VS Code-specific
-- bits (position format, indentation, EOL).

-- Sidebar filepicker icon. Click to toggle the mini.files explorer
-- (VS Code's Ctrl+B sidebar).
function M.section_sidebar()
	local icon = M.GLYPHS.sidebar
	if not icon or icon == "" then return "" end
	return "%@VsvimStatuslineSidebarClick@" .. icon .. "%X"
end

-- Git branch (plus the mini.git/gitsigns dirty summary if present).
-- Empty when not in a repo, exactly like VS Code which hides the branch
-- indicator outside a workspace.
function M.section_git()
	local MiniStatusline = _G.MiniStatusline
	if not MiniStatusline then return "" end
	-- Forward to mini.statusline so it honours truncation + the configured
	-- icon, then swap in VS Code's branch glyph when available.
	local icon = M.GLYPHS.branch
	if icon and icon ~= "" then
		icon = icon .. " "
	else
		icon = nil
	end
	local s = MiniStatusline.section_git({ trunc_width = 80, icon = icon })
	if s == "" then
		return s
	end
	-- Click the branch indicator to open lazygit in a floating TUI.
	return "%@VsvimStatuslineGitClick@" .. s .. "%X"
end

-- Diff summary from mini.diff/gitsigns. VS Code folds this into the branch
-- indicator; we keep it separate (mini.statusline convention) so it just
-- reads as extra detail next to the branch. Clicking it opens a full-file
-- diff view (HEAD vs working buffer) via `diff_gutter.open_file_diff()`.
function M.section_diff()
	local MiniStatusline = _G.MiniStatusline
	if not MiniStatusline then return "" end
	local s = MiniStatusline.section_diff({ trunc_width = 100 })
	if s == "" then
		return s
	end
	return "%@VsvimStatuslineDiffClick@" .. s .. "%X"
end

-- Errors / warnings with glyphs resolved from `vim.diagnostic.config().signs.text`.
-- mini.statusline's default uses single letters (E/W); we rebuild the counts
-- with the configured sign icons so the bar matches VS Code's right-hand
-- problem tally.
function M.section_diagnostics()
	local MiniStatusline = _G.MiniStatusline
	if not MiniStatusline then return "" end
	if MiniStatusline.is_truncated(100) then return "" end

	-- `vim.diagnostic.count(0)` returns nil until diagnostics exist.
	local counts = vim.diagnostic.count(0)
	if not counts then return "" end
	local sev = vim.diagnostic.severity
	local errs = counts[sev.ERROR] or 0
	local warns = counts[sev.WARN] or 0
	if errs == 0 and warns == 0 then return "" end

	local err_icon = M.GLYPHS.error or ""
	local warn_icon = M.GLYPHS.warn or ""
	return string.format("%s %d  %s %d", err_icon, errs, warn_icon, warns)
end

-- Cursor position in VS Code's exact format: `Ln 12, Col 34`.
function M.section_position()
	return "Ln %l, Col %c"
end

-- Indentation: `Spaces: 4` or `Tab Size: 4` (VS Code's exact wording).
function M.section_indent()
	local expand = vim.bo.expandtab
	local width = vim.bo.shiftwidth ~= 0 and vim.bo.shiftwidth or vim.bo.tabstop
	if expand then
		return "Spaces: " .. width
	end
	return "Tab Size: " .. width
end

-- End-of-line style: LF / CRLF / CR, VS Code surfaces this clickable item.
function M.section_eol()
	local ff = vim.bo.fileformat
	if ff == "unix" then return "LF"
	elseif ff == "dos" then return "CRLF"
	elseif ff == "mac" then return "CR"
	end
	return ff
end

-- Encoding (utf-8 etc.). Hidden unless it's something unusual, like VS Code.
function M.section_encoding()
	local enc = (vim.bo.fileencoding ~= "" and vim.bo.fileencoding) or vim.o.encoding
	-- VS Code only shows the encoding widget when it isn't UTF-8.
	if enc == "utf-8" or enc == "" then return "" end
	return enc:upper()
end

-- Language mode (filetype). VS Code shows the language identifier on the
-- far right; blank buffers show "Plain Text".
function M.section_language()
	local ft = vim.bo.filetype
	if ft == "" then return "Plain Text" end
	local ok, MiniIcons = pcall(require, "mini.icons")
	if ok then
		local icon = MiniIcons.get("filetype", ft)
		if icon and icon ~= "" then return icon .. " " .. ft end
	end
	return ft
end

-- Compose the active statusline.
--
-- Layout (mirrors VS Code), left → right with `%=` splitting halves:
--
--   [git] [diff]      %=     [diagnostics] [position] [indent] [eol] [encoding] [language]
--
-- Everything sits on one flat blue background (no per-section highlighting),
-- which is what makes it read as VS Code's status bar rather than a typical
-- bubble-style Neovim statusline.
function M.content_active()
	local MiniStatusline = _G.MiniStatusline
	local combine = MiniStatusline.combine_groups

	local sidebar = M.section_sidebar()
	local git = M.section_git()
	local diff = M.section_diff()
	local diagnostics = M.section_diagnostics()
	local position = M.section_position()
	local indent = M.section_indent()
	local eol = M.section_eol()
	local encoding = M.section_encoding()
	local language = M.section_language()

	-- A single highlight group wraps the whole bar (VsvimStatusline), so all
	-- sections share VS Code's flat blue background and white foreground.
	return combine({
		{ hl = "VsvimStatusline", strings = { sidebar, git, diff } },
		"%=",
		{ hl = "VsvimStatusline", strings = { diagnostics, position, indent, eol, encoding, language } },
	})
end

-- Inactive windows: dimmed blue with just the filename, like VS Code's
-- unfocused editor status bar.
function M.content_inactive()
	return "%#VsvimStatuslineInactive#%f%="
end

-- VS Code-flavoured highlight groups.
--
-- We define our own `VsvimStatusline` / `VsvimStatuslineInactive` (rather
-- than reusing mini.statusline's MiniStatusline* groups) because VS Code's
-- bar is a *single* flat color, mini.statusline's groups are designed for
-- per-section tinting, which we deliberately don't want here.
--
-- One wrinkle vs. the tabline: VS Code's status bar is a solid *blue*
-- All colors are pulled directly from the live vscode.nvim palette via
-- `require("vscode.colors").get_colors()` so they adapt to dark/light mode
-- and any `color_overrides` the user has configured.
function M.set_highlights()
	local hl = vim.api.nvim_set_hl

	-- Honour an explicit VsvimStatusBar override first (escape hatch).
	local custom = resolve("VsvimStatusBar")
	if custom.bg and custom.fg then
		hl(0, "VsvimStatusline", { default = true, bg = custom.bg, fg = custom.fg })
		hl(0, "VsvimStatuslineInactive", { default = true, bg = custom.bg, fg = custom.fg })
		return
	end

	-- Pull colors from the live theme. Prefer vscode.nvim's palette when
	-- available; otherwise derive from the standard StatusLine groups so there
	-- are no hardcoded hex fallbacks.
	local ok, vsc_colors = pcall(require, "vscode.colors")
	local c = ok and vsc_colors.get_colors() or {}

	local function vsc_hex(name)
		local val = c[name]
		if type(val) == "string" and val:match("^#%x%x%x%x%x%x$") then
			return tonumber(val:sub(2), 16)
		end
		return nil
	end

	-- Active bar: vscSelection is the selection-highlight blue; vscFront is the
	-- editor foreground. Fall back to the colorscheme's StatusLine group.
	local status = resolve("StatusLine")
	local bar_bg = vsc_hex("vscSelection") or status.bg
	local bar_fg = vsc_hex("vscFront") or status.fg

	-- Inactive bar: derive from StatusLineNC when vscode.nvim is absent.
	local status_nc = resolve("StatusLineNC")
	local inactive_bg = vsc_hex("vscLeftDark") or status_nc.bg or bar_bg
	local inactive_fg = vsc_hex("vscLeftLight") or status_nc.fg or bar_fg

	if bar_bg and bar_fg then
		hl(0, "VsvimStatusline", { bg = bar_bg, fg = bar_fg })
	end
	if inactive_bg and inactive_fg then
		hl(0, "VsvimStatuslineInactive", { bg = inactive_bg, fg = inactive_fg })
	end
end

-- Toggle the sidebar filepicker from the statusline icon click region.
local function sidebar_click_handler()
	local ok, sidebar = pcall(require, "sidebar")
	if ok then
		sidebar.toggle()
	else
		vim.notify("statusline: 'sidebar' module not found", vim.log.levels.ERROR)
	end
end

-- Open lazygit from the statusline git branch click region.
local function git_click_handler()
	local ok, tui = pcall(require, "tui")
	if ok then
		-- Open lazygit focused on the branches panel.
		tui.open({ "lazygit", "branch" }, { title = "lazygit" })
	else
		vim.notify("statusline: 'tui' module not found", vim.log.levels.ERROR)
	end
end

-- Open a full-file diff view (HEAD vs working buffer) from the statusline
-- diff-summary click region. Delegates to diff_gutter.open_file_diff().
local function diff_click_handler()
	local ok, diff_gutter = pcall(require, "diff_gutter")
	if ok then
		diff_gutter.open_file_diff(0)
	else
		vim.notify("statusline: 'diff_gutter' module not found", vim.log.levels.ERROR)
	end
end

-- Apply VS Code-style statusline.
-- `opts` is forwarded to `mini.statusline.setup()` (merged with our defaults).
function M.setup(opts)
	local has_mini, mini_statusline = pcall(require, "mini.statusline")
	if not has_mini then
		vim.notify("statusline: 'mini.statusline' not found (run :PackUpdate)", vim.log.levels.ERROR)
		return
	end

	-- Clicking the sidebar icon toggles the filepicker.
	_G.vsvim_statusline_sidebar_click = sidebar_click_handler
	-- Clicking the git branch indicator opens lazygit (if the tui module is available).
	_G.vsvim_statusline_git_click = git_click_handler
	-- Clicking the diff summary opens a full-file diff view (HEAD vs working buffer).
	_G.vsvim_statusline_diff_click = diff_click_handler
	vim.cmd([[
		function! VsvimStatuslineSidebarClick(...) abort
			call v:lua.vsvim_statusline_sidebar_click()
		endfunction
		function! VsvimStatuslineGitClick(...) abort
			call v:lua.vsvim_statusline_git_click()
		endfunction
		function! VsvimStatuslineDiffClick(...) abort
			call v:lua.vsvim_statusline_diff_click()
		endfunction
	]])

	-- Branch: MiniIcons.get("filetype", "git") gives the theme-consistent git glyph.
	-- Sidebar: a folder icon from the "directory" category.
	local ok_icons, MiniIcons = pcall(require, "mini.icons")
	if ok_icons then
		M.GLYPHS.branch = MiniIcons.get("filetype", "git")
		M.GLYPHS.sidebar = MiniIcons.get("directory", "folder")
	end

	-- Diagnostic signs: read from Neovim's own sign config (set by colorscheme /
	-- user config via vim.diagnostic.config). This is the canonical source,
	-- mini.icons has no error/warn entries in its lsp category.
	local sev = vim.diagnostic.severity
	local dsigns = (vim.diagnostic.config() or {}).signs
	if type(dsigns) == "table" and type(dsigns.text) == "table" then
		M.GLYPHS.error = dsigns.text[sev.ERROR]
		M.GLYPHS.warn  = dsigns.text[sev.WARN]
	end

	mini_statusline.setup(vim.tbl_deep_extend("force", {
		content = {
			active = M.content_active,
			inactive = M.content_inactive,
		},
		use_icons = true,
	}, opts or {}))

	-- VS Code always shows the status bar, even with a single window.
	-- `laststatus = 3` gives one global bar for the whole tabpage.
	vim.o.laststatus = 3

	-- Re-apply our highlights after any colorscheme switch so they survive
	-- `:colorscheme` reloads (mini.statusline resets defaults on ColorScheme).
	local group = vim.api.nvim_create_augroup("vsvim-statusline-hl", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = M.set_highlights,
	})
	M.set_highlights()
end

return M
