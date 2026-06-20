-- keymaps/vscode.lua
--
-- Complete VSCode text-editing shortcut emulation for Neovim.
-- Designed for a "no modes" workflow: all common editing operations are
-- reachable from insert mode without manually switching to normal mode.
--
-- Call M.apply() once during startup (see presets/vsvim.lua).

local M = {}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function map(modes, lhs, rhs, opts)
	vim.keymap.set(modes, lhs, rhs, vim.tbl_extend("force", { noremap = true, silent = true }, opts or {}))
end

-- Run a normal-mode command string and stay in whatever mode results.
local function n(cmd)
	vim.cmd("normal! " .. cmd)
end

-- ── M.apply ──────────────────────────────────────────────────────────────────

function M.apply()

	-- ── NAVIGATION ───────────────────────────────────────────────────────────

	-- Home: toggle between first non-blank and column 0 (VSCode behaviour)
	local function smart_home()
		local col = vim.fn.col(".")
		local indent = vim.fn.indent(vim.fn.line(".")) + 1
		n(col ~= indent and "^" or "0")
	end
	map({ "n", "i", "v" }, "<Home>", smart_home)

	-- End: $  (insert mode already handles <End> natively; remap normal)
	map("n", "<End>", "$")

	-- Ctrl+Home / Ctrl+End: file boundaries
	map({ "n", "i", "v" }, "<C-Home>", function() n("gg0") end)
	map({ "n", "i", "v" }, "<C-End>",  function() n("G$") end)

	-- Ctrl+Left / Ctrl+Right: word navigation
	map({ "n", "v" }, "<C-Left>",  "b")
	map({ "n", "v" }, "<C-Right>", "w")
	map("i", "<C-Left>",  "<C-o>b")
	map("i", "<C-Right>", "<C-o>w")

	-- ── SELECTION ────────────────────────────────────────────────────────────
	-- Strategy:
	--   • normal  → enter charwise visual and extend
	--   • insert  → <C-o>v  (enters visual persistently) then extend
	--   • visual  → extend the existing selection

	-- Helpers to DRY up the three-mode table
	local sel = {
		-- { normal-rhs, insert-rhs, visual-rhs }
		["<S-Left>"]    = { "v<Left>",  "<C-o>v<Left>",  "<Left>"  },
		["<S-Right>"]   = { "v<Right>", "<C-o>v<Right>", "<Right>" },
		["<S-Up>"]      = { "v<Up>",    "<C-o>v<Up>",    "<Up>"    },
		["<S-Down>"]    = { "v<Down>",  "<C-o>v<Down>",  "<Down>"  },
		["<S-Home>"]    = { "v^",       "<C-o>v^",       "^"       },
		["<S-End>"]     = { "v$",       "<C-o>v$",       "$"       },
		["<C-S-Left>"]  = { "vb",       "<C-o>vb",       "b"       },
		["<C-S-Right>"] = { "ve",       "<C-o>ve",       "e"       },
		["<C-S-Home>"]  = { "vgg0",     "<C-o>vgg0",     "gg0"     },
		["<C-S-End>"]   = { "vG$",      "<C-o>vG$",      "G$"      },
	}
	for lhs, rhs in pairs(sel) do
		map("n", lhs, rhs[1])
		map("i", lhs, rhs[2])
		map("v", lhs, rhs[3])
	end

	-- Ctrl+A: select all
	map({ "n", "i" }, "<C-a>", function() n("ggVG") end)
	map("v", "<C-a>", function() n("ggVG") end)

	-- ── CLIPBOARD ────────────────────────────────────────────────────────────
	-- options.lua already sets clipboard=unnamed,unnamedplus, so the default
	-- registers always sync with the OS clipboard. We just need the Ctrl keys.

	-- Ctrl+C: copy selection (visual) or current line (normal / insert)
	map("v", "<C-c>", "yi")           -- yank selection, drop back to insert
	map("n", "<C-c>", "yy")           -- yank line
	map("i", "<C-c>", "<C-o>yy")      -- yank line from insert

	-- Ctrl+X: cut selection or current line
	map("v", "<C-x>", "di")           -- delete selection, drop to insert
	map("n", "<C-x>", "dd")           -- cut line
	map("i", "<C-x>", "<C-o>dd")      -- cut line from insert

	-- Ctrl+V: paste
	-- In visual: delete selection to blackhole (preserve clipboard) then paste
	map("v", "<C-v>", '"_dpa')        -- blackhole-delete, paste, append-mode
	map("n", "<C-v>", "p")
	map("i", "<C-v>", "<C-r>*")       -- insert from * (OS clipboard)

	-- ── UNDO / REDO ──────────────────────────────────────────────────────────
	map({ "n", "v" }, "<C-z>",   "u")
	map("i",          "<C-z>",   "<C-o>u")
	map({ "n", "v" }, "<C-y>",   "<C-r>")
	map("i",          "<C-y>",   "<C-o><C-r>")
	map({ "n", "v" }, "<C-S-z>", "<C-r>")
	map("i",          "<C-S-z>", "<C-o><C-r>")

	-- ── DELETE ───────────────────────────────────────────────────────────────
	-- Ctrl+Backspace: delete word to the left
	map("i", "<C-BS>", "<C-w>")
	map("n", "<C-BS>", "db")
	-- Ctrl+Delete: delete word to the right
	map("i", "<C-Del>", "<C-o>de")
	map("n", "<C-Del>", "de")

	-- ── LINE OPERATIONS ──────────────────────────────────────────────────────
	-- Ctrl+Shift+K: delete current line
	map("n", "<C-S-k>", "dd")
	map("i", "<C-S-k>", "<C-o>dd")
	map("v", "<C-S-k>", "d<Esc>i")

	-- Alt+Up / Alt+Down: move line or selection up / down
	map("n", "<A-Up>",   ":m .-2<CR>==")
	map("i", "<A-Up>",   "<Esc>:m .-2<CR>==gi")
	map("v", "<A-Up>",   ":m '<-2<CR>gv=gv")
	map("n", "<A-Down>", ":m .+1<CR>==")
	map("i", "<A-Down>", "<Esc>:m .+1<CR>==gi")
	map("v", "<A-Down>", ":m '>+1<CR>gv=gv")

	-- Shift+Alt+Up / Shift+Alt+Down: duplicate line or selection
	map("n", "<S-A-Up>",   ":t .-1<CR>==")
	map("i", "<S-A-Up>",   "<Esc>:t .-1<CR>==gi")
	map("n", "<S-A-Down>", ":t .<CR>==")
	map("i", "<S-A-Down>", "<Esc>:t .<CR>==gi")
	map("v", "<S-A-Up>", function()
		local s, e = vim.fn.line("'<"), vim.fn.line("'>")
		vim.cmd(s .. "," .. e .. "t " .. (s - 1))
		vim.cmd("normal! gv")
	end)
	map("v", "<S-A-Down>", function()
		local s, e = vim.fn.line("'<"), vim.fn.line("'>")
		vim.cmd(s .. "," .. e .. "t " .. e)
		vim.cmd("normal! " .. (e + 1) .. "GV" .. (e + e - s + 1) .. "G")
	end)

	-- Ctrl+Enter: insert line below (without breaking current line)
	map("n", "<C-CR>",   "o<Esc>")
	map("i", "<C-CR>",   "<Esc>o")

	-- Ctrl+Shift+Enter: insert line above
	map("n", "<C-S-CR>", "O<Esc>")
	map("i", "<C-S-CR>", "<Esc>O")

	-- Ctrl+Shift+\: jump to matching bracket
	map({ "n", "v" }, "<C-S-\\>", "%")
	map("i",          "<C-S-\\>", "<C-o>%")

	-- ── INDENTATION & SMART KEYS (via mini.keymap) ──────────────────────────
	-- Tab  → accept completion  → expand snippet  → increase indent  → <Tab>
	-- S-Tab → prev completion  → decrease indent  → <S-Tab>
	-- CR   → accept completion  → mini.pairs CR   → <CR>
	-- BS   → mini.pairs BS      → <BS>
	local mk = require("mini.keymap")
	-- pmenu_accept requires an item to already be selected; mini.completion
	-- shows the popup with nothing selected initially. The custom step selects
	-- the first candidate (<C-n>) and immediately confirms it (<C-y>) so a
	-- single Tab press accepts, matching VSCode behaviour.
	mk.map_multistep("i", "<Tab>", {
		"pmenu_accept",
		{
			condition = function() return vim.fn.pumvisible() == 1 end,
			action    = function() return "<C-n><C-y>" end,
		},
		"increase_indent",
	})
	mk.map_multistep("i", "<S-Tab>", {
		"pmenu_prev",
		"decrease_indent",
	})
	mk.map_multistep("i", "<CR>", {
		"pmenu_accept",
		"minipairs_cr",
	})
	mk.map_multistep("i", "<BS>", {
		"minipairs_bs",
	})

	-- Normal / visual indentation (mini.keymap only handles insert)
	map("n", "<Tab>",   ">>")
	map("n", "<S-Tab>", "<<")
	map("v", "<Tab>",   ">gv")
	map("v", "<S-Tab>", "<gv")

	-- ── COMMENTS ─────────────────────────────────────────────────────────────
	-- Requires mini.comment (set up in plugins.lua). gc / gcc are its operators.
	map("n", "<C-/>",   "gcc", { noremap = false })
	map("i", "<C-/>",   "<C-o>gcc", { noremap = false })
	map("v", "<C-/>",   "gc",  { noremap = false })
	-- Shift+Alt+A: block comment
	map("n", "<S-A-a>", "gbc", { noremap = false })
	map("i", "<S-A-a>", "<C-o>gbc", { noremap = false })
	map("v", "<S-A-a>", "gb",  { noremap = false })

	-- ── FIND / REPLACE ───────────────────────────────────────────────────────
	-- Ctrl+F: open incremental search
	map("n", "<C-f>", "/")
	map("i", "<C-f>", "<C-o>/")

	-- F3 / Shift+F3: next / previous match
	map({ "n", "v" }, "<F3>",   "n")
	map("i",          "<F3>",   "<C-o>n")
	map({ "n", "v" }, "<S-F3>", "N")
	map("i",          "<S-F3>", "<C-o>N")

	-- Ctrl+H: substitute (pre-fills :%s/ in the command line)
	map({ "n", "i" }, "<C-h>", ":%s/", { noremap = true, silent = false })

	-- Ctrl+D: jump to next occurrence of word under cursor
	map("n", "<C-d>", "*")
	map("i", "<C-d>", "<C-o>*")
	map("v", "<C-d>", function()
		-- search for the visual selection
		local s = vim.fn.getpos("'<")
		local e = vim.fn.getpos("'>")
		local lines = vim.api.nvim_buf_get_text(0, s[2] - 1, s[3] - 1, e[2] - 1, e[3], {})
		local word = table.concat(lines, "\n")
		if word ~= "" then
			vim.fn.setreg("/", vim.fn.escape(word, "/\\"))
			vim.cmd("normal! n")
		end
	end)

	-- Ctrl+Shift+L: highlight all occurrences of word under cursor
	map({ "n", "i" }, "<C-S-l>", function()
		local word = vim.fn.expand("<cword>")
		if word == "" then return end
		vim.fn.setreg("/", "\\<" .. vim.fn.escape(word, "\\") .. "\\>")
		vim.opt.hlsearch = true
	end)

	-- ── FORMAT ───────────────────────────────────────────────────────────────
	-- Shift+Alt+F: LSP format document / selection
	map({ "n", "i" }, "<S-A-f>", function()
		vim.lsp.buf.format({ async = true })
	end)
	map("v", "<S-A-f>", function()
		vim.lsp.buf.format({
			async = true,
			range = {
				["start"] = vim.api.nvim_buf_get_mark(0, "<"),
				["end"]   = vim.api.nvim_buf_get_mark(0, ">"),
			},
		})
	end)

	-- ── MISC ─────────────────────────────────────────────────────────────────
	-- Alt+Z: toggle word wrap
	map({ "n", "i" }, "<A-z>", function()
		vim.wo.wrap = not vim.wo.wrap
		vim.notify("Word wrap: " .. (vim.wo.wrap and "on" or "off"))
	end)

	-- Ctrl+G: go to line (like VSCode's Ctrl+G)
	map({ "n", "i" }, "<C-g>", function()
		vim.ui.input({ prompt = "Go to line: " }, function(input)
			local line = tonumber(input)
			if line then n(line .. "G") end
		end)
	end)

	-- Ctrl+`: toggle terminal (delegates to the Tui command from plugin/tui.lua)
	map({ "n", "i" }, "<C-`>", function()
		pcall(vim.cmd, "Tui")
	end)

	-- Ctrl+Shift+[ / ]: fold / unfold
	map({ "n", "v" }, "<C-S-[>", "zc")
	map("i",          "<C-S-[>", "<C-o>zc")
	map({ "n", "v" }, "<C-S-]>", "zo")
	map("i",          "<C-S-]>", "<C-o>zo")

	-- Escape in insert: VSCode-feel — clear any in-flight selection/completion
	-- but stay at the cursor. We leave the default <Esc> (exit to normal) in
	-- place; the important thing is that all the shortcuts above mean the user
	-- rarely needs to reach for Esc to do editing work.
end

return M
