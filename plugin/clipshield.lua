if vim.g.loaded_clipshield then return end
vim.g.loaded_clipshield = true

local clipshield = require("clipshield")
clipshield.bootstrap()

vim.api.nvim_create_user_command("YankRaw", function(opts)
  clipshield.yank_raw_range(opts.line1, opts.line2)
end, { range = true, desc = "Yank to the clipboard without masking Secrets" })

vim.api.nvim_create_user_command("ClipshieldAdd", function()
  clipshield.add_selection()
end, { range = true, desc = "Add the selection to the Watchlist, choosing what it reads as" })

vim.api.nvim_create_user_command("ClipshieldAddDefault", function()
  clipshield.add_selection_default()
end, { range = true, desc = "Add the selection to the Watchlist with the default placeholder" })

vim.api.nvim_create_user_command("ClipshieldAddNamed", function()
  clipshield.add_selection_named()
end, { range = true, desc = "Add the selection to the Watchlist under a name, choosing what it reads as" })

vim.api.nvim_create_user_command("ClipshieldSetReplacement", function()
  clipshield.set_replacement()
end, { desc = "Set or change the replacement of a Watchlist entry" })

vim.api.nvim_create_user_command("ClipshieldList", function()
  clipshield.open()
end, { desc = "Open the Watchlist" })

vim.api.nvim_create_user_command("ClipshieldDelete", function()
  clipshield.delete()
end, { desc = "Remove an entry from the Watchlist" })
