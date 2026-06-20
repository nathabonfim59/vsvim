-- Plugin management via vim.pack (Neovim 0.12+ built-in)
-- See: :help vim.pack

-- Install fff.nvim (fuzzy finder): https://github.com/dmtrKovalenko/fff.nvim
vim.pack.add({
	{
		src = "https://github.com/dmtrKovalenko/fff.nvim",
	},
})

-- fff.nvim ships a prebuilt binary; build it on install.
-- Triggered via the standard `PackChanged` event emitted by vim.pack.
vim.api.nvim_create_autocmd("PackChanged", {
	group = vim.api.nvim_create_augroup("fff-install", { clear = true }),
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if name == "fff.nvim" and kind == "install" then
			if not ev.data.active then
				vim.cmd.packadd("fff.nvim")
			end
			require("fff.download").download_or_build_binary()
		end
	end,
})

-- fff.nvim configuration (read before the plugin loads)
vim.g.fff = {
	lazy_sync = true,
	debug = { enabled = true, show_scores = true },
}

-- NOTE: keymaps are registered by the keybinding-preset system
-- (lua/presets/), not here. See init.lua -> require("presets").setup().
