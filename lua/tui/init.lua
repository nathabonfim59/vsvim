-- tui.nvim: open any TUI program full-screen in a floating terminal window.
--
-- Module structure (see :help lua-module-load, :help load-plugins):
--   lua/tui/init.lua   -> the module returned by `require("tui")`
--   plugin/tui.lua     -> auto-sourced at startup; registers commands/keymaps
--
-- A "fullscreen" floating window is achieved by sizing the float to the whole
-- editor (relative="editor", width/height = columns/lines). See :help api-floatwin.
-- The program runs in a |:terminal| buffer inside the float, and the buffer is
-- wiped when the job exits (TermClose). See :help TermClose, :help terminal-start.

local M = {}
M.__index = M

-- Default configuration. Override via setup().
M.defaults = {
	-- Float window appearance.
	border = "rounded",
	-- Vertical/horizontal padding (in cells) from the editor edges.
	-- 0 = truly fullscreen; a small value looks nicer with a border.
	padding = 0,
	-- Highlight group for the float background (nil = NormalFloat).
	hl = nil,
	-- Enter Terminal-mode automatically when the float opens.
	start_insert = true,
	-- Close the float when its buffer loses focus.
	close_on_bufleave = true,
}

-- Merge user config into defaults.
function M.setup(opts)
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
	return M
end

-- Build the window config for a fullscreen float.
-- See :help nvim_open_win() / :help api-floatwin.
function M._win_config()
	local cfg = M.config or M.defaults
	local pad = cfg.padding or 0
	local width = math.max(1, vim.o.columns - pad * 2)
	local height = math.max(1, vim.o.lines - pad * 2)
	return {
		relative = "editor",
		anchor = "NW",
		row = pad,
		col = pad,
		width = width,
		height = height,
		border = cfg.border,
		style = "minimal",
		-- Prefer NormalFloat / a custom hl if provided via winhighlight.
		title = " tui ",
		title_pos = "center",
	}
end

-- Create (or reuse) a fullscreen float running `cmd` in a terminal.
--
-- cmd:   table of args, e.g. { "lazygit" } or { "nvim", "." }
--        (a string is split via |vim.split()| on whitespace)
-- opts:  optional per-call overrides merged into the module config:
--        { title = "...", border = "...", padding = N, start_insert = bool }
--
-- Returns the window id, or nil if the program is not installed.
function M.open(cmd, opts)
	if type(cmd) == "string" then
		cmd = vim.split(cmd, "%s+")
	end
	assert(type(cmd) == "table" and #cmd > 0, "tui.open: cmd must be a non-empty table or string")

	-- Only launch if the binary is on $PATH (see :help executable()).
	if vim.fn.executable(cmd[1]) ~= 1 then
		vim.notify(("tui: %q is not installed or not executable."):format(cmd[1]), vim.log.levels.WARN)
		return nil
	end

	-- Apply per-call overrides on top of the module config.
	local cfg = vim.tbl_deep_extend("force", M.config or M.defaults, opts or {})

	-- Reuse an existing float for the same command, if any.
	for _, state in pairs(M._floats or {}) do
		if state and vim.deep_equal(state.cmd, cmd) and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_set_current_win(state.win)
			return state.win
		end
	end

	-- Scratch buffer for the terminal (see :help nvim_create_buf()).
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "tui"

	local win_cfg = M._win_config()
	if cfg.title then
		win_cfg.title = " " .. cfg.title .. " "
	end

	local win = vim.api.nvim_open_win(buf, true, win_cfg)
	if cfg.hl then
		vim.wo[win].winhighlight = "Normal:" .. cfg.hl .. ",FloatBorder:" .. cfg.hl
	end

	-- Attach a |:terminal| job to the buffer. The modern replacement for the
	-- deprecated termopen() is jobstart() with `{ term = v:true }`, which binds
	-- the PTY to the current buffer. See :help jobstart().
	-- We switch to the float window first so the job lands in our buffer.
	vim.api.nvim_win_call(win, function()
		vim.fn.jobstart(cmd, { term = true })
	end)

	-- Track state so we can reuse / clean up.
	M._floats = M._floats or {}
	M._floats[win] = { win = win, buf = buf, cmd = cmd }

	-- Wipe the buffer (and thus close the float) when the job exits.
	-- See :help TermClose.
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = buf,
		once = true,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
			M._floats[win] = nil
		end,
	})

	-- Optionally close the float when leaving its buffer.
	if cfg.close_on_bufleave then
		vim.api.nvim_create_autocmd("BufLeave", {
			buffer = buf,
			once = true,
			nested = true,
			callback = function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
				M._floats[win] = nil
			end,
		})
	end

	if cfg.start_insert then
		vim.cmd.startinsert()
	end

	return win
end

-- Close every open tui float.
function M.close_all()
	for win, state in pairs(M._floats or {}) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		M._floats[win] = nil
	end
end

-- Keep the floats sized to the editor when the terminal is resized.
-- See :help VimResized.
vim.api.nvim_create_autocmd("VimResized", {
	group = vim.api.nvim_create_augroup("tui-resize", { clear = true }),
	callback = function()
		for win, state in pairs(M._floats or {}) do
			if state and vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_set_config(win, M._win_config())
			end
		end
	end,
})

return M
