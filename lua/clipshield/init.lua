local mask = require("clipshield.mask")
local watchlist = require("clipshield.watchlist")

local M = {}

M.config = {
	-- Where the Watchlist lives. One JSON object per line.
	watchlist = vim.fs.joinpath(vim.fn.stdpath("data"), "clipshield", "watchlist.jsonl"),
	-- Entries with no replacement of their own get this word plus a number:
	-- REDACTED1, REDACTED2, ...
	placeholder = "REDACTED",
	-- Refuse to add anything shorter than this; short entries match everywhere.
	min_length = 8,
	-- Default mappings. Set to false to bind everything yourself.
	keymaps = true,
	prefix = "<leader>s",
	-- How long the copied-text popup stays open (ms). Set to 0 to disable.
	popup_duration = 3000,
	-- Maximum number of lines shown in the popup (excess is truncated).
	popup_max_lines = 8,
}

--- Set while performing a Raw Yank, so the TextYankPost handler stands aside.
local skipping = false

--- Active popup window & buffer id, so a new yank replaces the old one.
local popup_win_id = nil
local popup_buf_id = nil
local popup_close_timer = nil

--- Safely close the current popup (if any).
local function close_popup()
	if popup_close_timer then
		pcall(vim.fn.timer_stop, popup_close_timer)
		popup_close_timer = nil
	end
	if popup_win_id and vim.api.nvim_win_is_valid(popup_win_id) then
		pcall(vim.api.nvim_win_close, popup_win_id, true)
	end
	if popup_buf_id and vim.api.nvim_buf_is_valid(popup_buf_id) then
		pcall(vim.api.nvim_buf_delete, popup_buf_id, { force = true })
	end
	popup_win_id = nil
	popup_buf_id = nil
end

--- Show a floating popup with the masked clipboard contents, then auto-close.
local function show_popup(masked_text, secret_count)
	close_popup()

	local duration = M.config.popup_duration
	if duration <= 0 then
		return
	end

	local header = ("Clipshield: %d secret(s) masked"):format(secret_count)
	local all_lines = vim.split(masked_text, "\n", { plain = true })
	local total_lines = #all_lines

	-- Take at most popup_max_lines.
	local display_lines = {}
	local max_lines = M.config.popup_max_lines
	for i = 1, math.min(total_lines, max_lines) do
		display_lines[i] = all_lines[i]
	end
	if total_lines > max_lines then
		display_lines[#display_lines + 1] = ("... (%d more lines)"):format(total_lines - max_lines)
	end

	-- Truncate very long single lines for display.
	local max_width = 60
	for i, line in ipairs(display_lines) do
		if vim.api.nvim_strwidth(line) > max_width then
			display_lines[i] = vim.fn.strcharpart(line, 0, max_width - 1) .. "…"
		end
	end

	local buf = vim.api.nvim_create_buf(false, true)
	popup_buf_id = buf

	-- Build content: header + separator + blank line + masked text.
	local sep_len = vim.api.nvim_strwidth(header)
	local sep = string.rep("─", sep_len)
	local content = { header, sep, "" }
	for _, line in ipairs(display_lines) do
		content[#content + 1] = line
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

	-- Highlight the header line.
	vim.api.nvim_buf_add_highlight(buf, 0, "WarningMsg", 0, 0, -1)
	-- Highlight the separator.
	vim.api.nvim_buf_add_highlight(buf, 0, "LineNr", 1, 0, -1)

	-- Compute window size from content.
	local width = 0
	for _, line in ipairs(content) do
		local w = vim.api.nvim_strwidth(line)
		if w > width then
			width = w
		end
	end
	local height = #content

	local win_opts = {
		relative = "cursor",
		row = 1,
		col = 0,
		width = math.max(width + 2, 20),
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		noautocmd = true,
	}

	local win = vim.api.nvim_open_win(buf, false, win_opts)
	popup_win_id = win

	-- Slight transparency so it feels like a notification, not a buffer.
	vim.api.nvim_win_set_option(win, "winblend", 15)

	-- Auto-close after `duration` ms.
	popup_close_timer = vim.fn.timer_start(duration, function()
		vim.schedule(close_popup)
	end)
end

--- Which clipboard registers this yank landed in, if any. The unnamed register
--- is deliberately not among them: in-buffer editing must keep working on the
--- true value.
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

local function on_yank()
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

	show_popup(masked, count)
end

--- Run a yank without masking it.
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

--- The selection, or nil if it cannot go into the Watchlist.
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

--- Add the selection, asking what it should read as when copied.
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

--- Add the selection with the numbered default placeholder, asking nothing.
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

--- Mappings already installed, so that a later setup() can take them back.
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
	map("x", p .. "y", ":<C-u>lua require('clipshield').yank_raw_selection()<CR>", "yank selection unmasked")
	map("n", p .. "l", M.open, "open Watchlist")
	map("n", p .. "d", M.delete, "remove from Watchlist")
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	apply_keymaps()
end

--- Called once from plugin/clipshield.lua. The plugin works without setup().
function M.bootstrap()
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = vim.api.nvim_create_augroup("clipshield", { clear = true }),
		callback = on_yank,
		desc = "clipshield: mask Secrets on their way to the clipboard",
	})
	apply_keymaps()
end

return M
