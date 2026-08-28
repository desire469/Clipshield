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

--- Active popup window & buffer ids, so a new yank reuses or replaces the old one.
local popup_win_id = nil
local popup_buf_id = nil
local popup_timer = nil

--- Show a floating popup with the masked clipboard contents, then auto-close.
local function show_popup(masked_text, secret_count)
	-- Dismiss any previous popup first.
	if popup_timer then
		pcall(vim.loop.timer_stop, popup_timer)
		popup_timer = nil
	end
	if popup_win_id and vim.api.nvim_win_is_valid(popup_win_id) then
		pcall(vim.api.nvim_win_close, popup_win_id, true)
	end
	if popup_buf_id and vim.api.nvim_buf_is_valid(popup_buf_id) then
		pcall(vim.api.nvim_buf_delete, popup_buf_id, { force = true })
	end

	local duration = M.config.popup_duration
	if duration <= 0 then
		return
	end

	local header = ("Clipshield: %d secret(s) masked"):format(secret_count)
	local display_lines = vim.split(masked_text, "\n", { plain = true })

	-- Truncate if too many lines.
	local max_lines = M.config.popup_max_lines
	if #display_lines > max_lines then
		display_lines = vim.list_slice(display_lines, 1, max_lines)
		table.insert(
			display_lines,
			("... (%d more lines)"):format(#vim.split(masked_text, "\n", { plain = true }) - max_lines)
		)
	end

	-- Truncate very long single lines for display.
	local max_width = 60
	for i, line in ipairs(display_lines) do
		if vim.api.nvim_strwidth(line) > max_width then
			display_lines[i] = vim.fn.strpart(line, 0, max_width - 1) .. "…"
		end
	end

	local buf = vim.api.nvim_create_buf(false, true)
	popup_buf_id = buf

	local content = { header, "─" .. string.rep("─", #header - 1), "" }
	vim.list_extend(content, display_lines)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

	-- Highlight the header line.
	vim.api.nvim_buf_add_highlight(buf, 0, "WarningMsg", 0, 0, -1)
	-- Highlight the separator.
	vim.api.nvim_buf_add_highlight(buf, 0, "LineNr", 1, 0, -1)

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

	-- Set window highlight.
	vim.api.nvim_win_set_option(win, "winblend", 15)

	popup_timer = vim.loop.new_timer()
	popup_timer:start(duration, 0, function()
		vim.schedule(function()
			if popup_win_id and vim.api.nvim_win_is_valid(popup_win_id) then
				pcall(vim.api.nvim_win_close, popup_win_id, true)
			end
			if popup_buf_id and vim.api.nvim_buf_is_valid(popup_buf_id) then
				pcall(vim.api.nvim_buf_delete, popup_buf_id, { force = true })
			end
			popup_win_id = nil
			popup_buf_id = nil
			popup_timer = nil
		end)
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
		-- The one thing worth breaking the silence for: a Watchlist that cannot be
		-- read means the user believes they are protected while they are not.
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
	-- A blockwise register carries its own width, which no longer describes the
	-- masked text. Charwise is the only honest thing to fall back to.
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
		-- Already known: nothing to do, and no reason to ask anything.
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
--- Any prompt here would be read as "what should this turn into?", which is
--- the other mapping's job.
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
--- plugin/ runs before setup(), so keymaps = false must be able to undo them.
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
