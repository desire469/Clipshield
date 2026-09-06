-- Terminal UI of the Watchlist manager: the wofi window's twin for the
-- terminal. `clipshield tui` launches it standalone (a --clean nvim in its
-- own floating window, lazygit-style); :ClipshieldTUI opens the same window
-- inside a running editor. CLIPSHIELD_WATCHLIST overrides the file, as in
-- the rest of the CLI.
--
--   e / <Enter>  edit what the entry reads as (prefilled; empty — numbered)
--   r            back to the numbered default
--   d            delete the entry under the cursor
--   q / <Esc>    close

local M = {}

local state = { buf = nil, win = nil, standalone = false }

local function watchlist()
	return require("clipshield.watchlist")
end

local function apply_env()
	local cs = require("clipshield")
	local override = os.getenv("CLIPSHIELD_WATCHLIST")
	if override and override ~= "" then
		cs.config.watchlist = override
	end
end

local function menu_name(entry)
	return entry.label ~= "" and entry.label
		or (#entry.value > 12 and (entry.value:sub(1, 12) .. "…") or entry.value)
end

--- Buffer line == entry number: rows map one to one, so the cursor row IS
--- the index. The legend lives in the winbar, not in the buffer.
local function render()
	local entries = watchlist().read()
	local lines = {}
	for n, entry in ipairs(entries) do
		local name = menu_name(entry)
		lines[n] = entry.replacement ~= "" and ("%d  %s → %s"):format(n, name, entry.replacement)
			or ("%d  %s  ·  numbered"):format(n, name)
	end
	if #lines == 0 then
		lines = { "The Watchlist is empty" }
	end
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false

	-- Fit the window to the content.
	local width = 24
	for _, l in ipairs(lines) do
		width = math.max(width, #l)
	end
	vim.api.nvim_win_set_width(state.win, math.min(width + 4, math.max(30, vim.o.columns - 6)))
	vim.api.nvim_win_set_height(state.win, math.min(#lines, 20))
end

local function feedback(text)
	vim.api.nvim_echo({ { "clipshield: ", "WarningMsg" }, { text } }, false, {})
end

--- Entry under the cursor, or nil with a nudge.
local function current_entry()
	local entries = watchlist().read()
	local row = vim.api.nvim_win_get_cursor(state.win)[1]
	local entry = entries[row]
	if not entry then
		feedback("put the cursor on an entry")
		return nil
	end
	return entry
end

local function edit_entry()
	local entry = current_entry()
	if not entry then
		return
	end
	local name = menu_name(entry)
	vim.ui.input({
		prompt = ("What should ‘%s’ read as when copied? "):format(name),
		default = entry.replacement,
	}, function(answer)
		if answer == nil then
			return -- Esc — back to the list, nothing saved
		end
		local repl = vim.trim(answer)
		watchlist().update(entry.value, repl)
		feedback(("%s now reads as %s"):format(name, repl ~= "" and ("'" .. repl .. "'") or "the numbered default"))
		render()
	end)
end

local function reset_entry()
	local entry = current_entry()
	if not entry then
		return
	end
	watchlist().update(entry.value, "")
	feedback(("%s now reads as the numbered default"):format(menu_name(entry)))
	render()
end

local function delete_entry()
	local entry = current_entry()
	if not entry then
		return
	end
	watchlist().remove(entry.value)
	feedback(("removed %s"):format(menu_name(entry)))
	render()
end

local function close()
	if state.standalone then
		vim.cmd("qa!")
		return
	end
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, false)
	end
	state.win = nil
	if vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
	state.buf = nil
end

function M.run()
	apply_env()

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].modifiable = false

	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		row = math.floor(vim.o.lines / 4),
		col = math.floor(vim.o.columns / 4),
		width = 40,
		height = 8,
		style = "minimal",
		border = "rounded",
	})
	state.standalone = os.getenv("CLIPSHIELD_STANDALONE") == "1"
	vim.wo[state.win].winbar = " clipshield  ·  e: edit  ·  r: default  ·  d: delete  ·  q: quit"

	render()

	local opts = { buffer = state.buf, nowait = true, silent = true }
	vim.keymap.set("n", "e", edit_entry, opts)
	vim.keymap.set("n", "<CR>", edit_entry, opts)
	vim.keymap.set("n", "r", reset_entry, opts)
	vim.keymap.set("n", "d", delete_entry, opts)
	vim.keymap.set("n", "q", close, opts)
	vim.keymap.set("n", "<Esc>", close, opts)
end

return M
