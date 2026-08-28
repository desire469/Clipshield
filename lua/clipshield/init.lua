local mask = require("clipshield.mask")
local watchlist = require("clipshield.watchlist")

local M = {}

M.config = {
	watchlist = vim.fs.joinpath(vim.fn.stdpath("data"), "clipshield", "watchlist.jsonl"),
	placeholder = "REDACTED",
	min_length = 8,
	keymaps = true,
	prefix = "<leader>s",
	-- How long the notification stays (ms). 0 = use Neovim default timeout.
	notify_timeout = 3000,
	-- Max characters of masked text shown in the notification.
	notify_max_length = 200,
}

local skipping = false

local function clipboard_targets(regname)
	if regname == "+" or regname == "*" then
		return { [regname] = true }
	end
	if regname ~= "" then
		return {}
	end

	local targets = {}
	for _, flag in ipairs(vim.split(vim.o.clipboard, ",", { trimempty = true })) do
		if flag == "unnamedplus" then
			targets["+"] = true
		elseif flag == "unnamed" then
			targets["*"] = true
		end
	end
	return targets
end

local function notify_masked(masked_text, secret_count)
	local display = masked_text
	local max_len = M.config.notify_max_length
	if #display > max_len then
		display = display:sub(1, max_len) .. "..."
	end

	-- Collapse newlines for a single-line notification.
	display = display:gsub("\n", " ")

	vim.notify(
		("Clipshield: %d secret(s) masked\n%s"):format(secret_count, display),
		vim.log.levels.WARN,
		{ title = "Clipshield", timeout = M.config.notify_timeout }
	)
end

local function on_yank()
	vim.notify("DEBUG: on_yank fired")
	if skipping then
		return
	end

	local event = vim.v.event
	local targets = clipboard_targets(event.regname)
	if next(targets) == nil then
		return
	end

	local entries, err = watchlist.read()
	if err then
		vim.notify("clipshield: " .. err, vim.log.levels.ERROR)
	end
	if #entries == 0 then
		return
	end

	local text = table.concat(event.regcontents, "\n")
	local masked, count = mask.apply(text, entries, M.config.placeholder)
	if count == 0 then
		return
	end

	local lines = vim.split(masked, "\n", { plain = true })
	local regtype = event.regtype
	if regtype:sub(1, 1) == "\22" then
		regtype = "v"
	end

	for register in pairs(targets) do
		vim.fn.setreg(register, lines, regtype)
	end

	notify_masked(masked, count)
end

local function without_masking(command)
	skipping = true
	local ok, err = pcall(vim.cmd, command)
	skipping = false
	if not ok then
		vim.notify("clipshield: " .. tostring(err), vim.log.levels.ERROR)
	end
end

function M.yank_raw_selection()
	without_masking('normal! gv"+y')
end

function M.yank_raw_range(line1, line2)
	without_masking(("%d,%dyank +"):format(line1, line2))
end

local function selected_value()
	local lines = vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
	local value = vim.trim(table.concat(lines, "\n"))

	if #value < M.config.min_length then
		vim.notify(
			("clipshield: refusing to add %d characters — anything under %d matches far too much"):format(
				#value,
				M.config.min_length
			),
			vim.log.levels.WARN
		)
		return nil
	end

	for _, entry in ipairs(watchlist.read()) do
		if entry.value == value then
			return nil
		end
	end

	return value
end

function M.add_selection()
	local value = selected_value()
	if not value then
		return
	end

	vim.ui.input({ prompt = "Replace with: " }, function(replacement)
		if replacement == nil then
			return
		end
		watchlist.add(value, vim.trim(replacement))
	end)
end

function M.add_selection_default()
	local value = selected_value()
	if not value then
		return
	end
	watchlist.add(value, "")
end

function M.open()
	local file = watchlist.path()
	vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
	vim.cmd.edit(vim.fn.fnameescape(file))
end

function M.delete()
	local entries = watchlist.read()
	if #entries == 0 then
		vim.notify("clipshield: the Watchlist is empty", vim.log.levels.INFO)
		return
	end

	vim.ui.select(entries, {
		prompt = "Remove from Watchlist:",
		format_item = watchlist.describe,
	}, function(choice)
		if choice then
			watchlist.remove(choice.value)
		end
	end)
end

local applied = {}

local function apply_keymaps()
	for _, map in ipairs(applied) do
		pcall(vim.keymap.del, map[1], map[2])
	end
	applied = {}

	if not M.config.keymaps then
		return
	end
	local p = M.config.prefix

	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "clipshield: " .. desc })
		applied[#applied + 1] = { mode, lhs }
	end

	map(
		"x",
		p .. "a",
		":<C-u>lua require('clipshield').add_selection_default()<CR>",
		"add selection to Watchlist with the default placeholder"
	)
	map("x", p .. "y", ":<C-u>lua require('clipshield').yank_raw_selection()<CR>", "yank unmasked")
	map("n", p .. "l", M.open, "open Watchlist")
	map("n", p .. "d", M.delete, "remove from Watchlist")
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	apply_keymaps()
end

function M.bootstrap()
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = vim.api.nvim_create_augroup("clipshield", { clear = true }),
		callback = on_yank,
		desc = "clipshield: mask Secrets on their way to the clipboard",
	})
	apply_keymaps()
end

return M
