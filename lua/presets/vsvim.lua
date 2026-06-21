-- presets/vsvim.lua
--
-- The "vsvim" keybinding preset: leader-based keymaps on top of Vim defaults.
-- This is the default set of mappings vsvim ships with (<leader>sf, etc.).
--
-- A preset is a plain module that exposes a single `apply()` function which
-- registers whatever keymaps it wants. It is called by presets.init after the
-- user's choice has been resolved.

local M = {}

local modal = require("modal")

-- Button highlight groups for the unsaved-changes modal. Linked lazily so
-- they pick up the active colorscheme. Mirrors the sidebar's conventions:
--   Save    → DiffAdd    (green, positive action)
--   Discard → DiffDelete (red, destructive action)
--   Cancel  → PmenuSbar  (gray, neutral dismissal)
local function ensure_close_modal_hl()
	vim.api.nvim_set_hl(0, "VsvimCloseSaveBtn", { default = true, link = "DiffAdd" })
	vim.api.nvim_set_hl(0, "VsvimCloseDiscardBtn", { default = true, link = "DiffDelete" })
	vim.api.nvim_set_hl(0, "VsvimCloseCancelBtn", { default = true, link = "PmenuSbar" })
end

-- Switch the current window to the previous listed buffer (excluding `cur`)
-- and delete `cur`. Called after the save/discard decision has been made.
local function switch_and_delete(cur, force)
	local prev = nil
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if b ~= cur and vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b) then
			prev = b -- last one wins -> closest listed buffer
		end
	end
	if prev then
		vim.api.nvim_set_current_buf(prev)
	end
	pcall(vim.api.nvim_buf_delete, cur, { force = force })
end

-- Close the current editor tab (like VS Code's Ctrl+W). `:bd`-style:
-- wipe the buffer but keep the window, jumping to the previous listed
-- buffer so the editor doesn't leave an empty window behind.
-- If the buffer has unsaved changes, a Save / Discard / Cancel modal is
-- shown instead of erroring out.
local function close_current_buffer()
	local cur = vim.api.nvim_get_current_buf()

	-- Unmodified buffer: close immediately.
	if not vim.bo[cur].modified then
		switch_and_delete(cur, false)
		return
	end

	-- Modified buffer: ask the user what to do.
	ensure_close_modal_hl()
	local name = vim.api.nvim_buf_get_name(cur)
	if name == "" then
		name = "[No Name]"
	else
		name = vim.fn.fnamemodify(name, ":~:.")
	end

	-- Open the modal with focus=false so the current buffer keeps focus.
	-- This prevents BufLeave/WinLeave from firing on the original buffer,
	-- which would trigger autowrite or other leave-triggered autocmds that
	-- could silently save or close the buffer before the user decides.
	modal.open({
		title = { { " Unsaved Changes ", "WarningMsg" } },
		lines = {
			name .. " has unsaved changes.",
			"Do you want to save before closing?",
		},
		position = "center",
		width = math.min(60, math.max(40, #name + 30)),
		max_height = 12,
		border = "rounded",
		backdrop = true,
		noautocmd = true,
		focus = false,
		buttons = {
			position = "bottom",
			align = "right",
			padding = 2,
			items = {
				{ label = " Save ", hl = "VsvimCloseSaveBtn", action = "save", default = true },
				{ label = " Discard ", hl = "VsvimCloseDiscardBtn", action = "discard" },
				{ label = " Cancel ", hl = "VsvimCloseCancelBtn", action = "cancel" },
			},
		},
		keymaps = {
			["y"] = "save",
			["n"] = "discard",
			["q"] = "cancel",
			["<Esc>"] = "cancel",
			["<C-c>"] = "cancel",
		},
		on_action = function(action)
			if action == "save" then
				local ok, err = pcall(vim.api.nvim_buf_call, cur, function()
					vim.cmd("write")
				end)
				if not ok then
					vim.notify("Close: " .. tostring(err), vim.log.levels.ERROR)
					return
				end
				switch_and_delete(cur, false)
			elseif action == "discard" then
				switch_and_delete(cur, true)
			end
			-- "cancel" is a no-op, buffer stays open, nothing is written.
		end,
	})
end

-- "No modes" workflow: land in insert mode whenever an editable buffer is
-- shown, so the editor is always ready to type (matching VS Code). Only
-- normal file buffers (buftype == "" and modifiable) are affected; floats,
-- terminals, quickfix, help, mini.files/pick/starter buffers, etc. keep
-- their own mode handling.
local function is_editable(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.bo[buf].buftype ~= "" then
		return false
	end
	return vim.bo[buf].modifiable
end

local function start_insert()
	if is_editable(0) and vim.fn.mode() == "n" then
		vim.cmd("startinsert")
	end
end

function M.apply()
	-- VSCode text-editing shortcuts (no-modes experience).
	-- Must run after plugins.lua so mini.pairs / mini.comment are set up.
	require("keymaps.vscode").apply()

	-- Start in insert mode on editable buffers. BufEnter covers buffer
	-- switches; VimEnter catches the initial buffer on startup paths where
	-- BufEnter has already fired before apply() runs.
	local group = vim.api.nvim_create_augroup("vsvim-start-insert", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = start_insert,
	})
	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		once = true,
		callback = start_insert,
	})
	-- fff.nvim (fuzzy finder) keymaps. fff.nvim is required by plugins.lua,
	-- so it is available by the time presets run.
	vim.keymap.set("n", "<leader>sf", function()
		require("fff").find_files()
	end, { desc = "[S]earch [F]iles" })
	vim.keymap.set("n", "<leader>sg", function()
		require("fff").live_grep()
	end, { desc = "[S]earch [G]rep" })
	vim.keymap.set("n", "<leader>sw", function()
		require("fff").live_grep({ query = vim.fn.expand("<cword>") })
	end, { desc = "[S]earch [W]ord" })

	-- VS Code "Quick Open" family (mini.pick, with fff as file/grep backend).
	-- See lua/pickers.lua. Ctrl+P lists open buffers first then fff-indexed
	-- files, Ctrl+Shift+P is the command palette (commands + keymaps),
	-- Ctrl+Shift+F is find-in-files (fff live grep), Ctrl+Tab opens the
	-- buffer picker.
	local pickers = require("pickers")
	vim.keymap.set("n", "<C-p>", pickers.files, { desc = "Quick Open (buffers + files)" })
	vim.keymap.set("n", "<C-S-p>", pickers.command_palette, { desc = "Command palette (commands + keymaps)" })
	vim.keymap.set("n", "<C-S-f>", pickers.grep, { desc = "Find in files (fff live grep)" })
	vim.keymap.set("n", "<C-Tab>", pickers.buffers, { desc = "Open editors (buffer picker)" })
	vim.keymap.set("n", "<C-S-Tab>", pickers.buffers, { desc = "Open editors (buffer picker)" })

	-- Tab/buffer management (VS Code-style tabline lives in lua/tabline.lua).
	-- Ctrl+W closes the current editor tab, matching VS Code's shortcut.
	-- This shadows Vim's <C-w> window-command prefix in normal mode; window
	-- management is rarely needed in the single-window vsvim workflow. Insert
	-- mode is left untouched so <C-w> (delete word) still works there.
	vim.keymap.set("n", "<C-w>", close_current_buffer, { desc = "Close tab (VS Code Ctrl+W)", nowait = true })
	vim.keymap.set("n", "<leader>bd", close_current_buffer, { desc = "[B]uffer [D]elete (close tab)" })

	-- Cycle editor tabs like VS Code's Ctrl+Tab / Ctrl+Shift+Tab.
	vim.keymap.set("n", "<leader>bn", "<Cmd>bnext<CR>", { desc = "[B]uffer [N]ext tab" })
	vim.keymap.set("n", "<leader>bp", "<Cmd>bprevious<CR>", { desc = "[B]uffer [P]revious tab" })
end

return M
