-- The command-line face of clipshield, for callers outside Neovim:
-- compositor keybinds (Hyprland), shell one-liners, scripts. Neovim is the
-- engine; bin/clipshield is the steering wheel.
--
--   printf '%s' "$text" | cli.lua add [-n NAME] [-r REPLACEMENT]
--   printf '%s' "$text" | cli.lua copy
--
-- `add` prints a status line to stdout. `copy` writes the Masked text to
-- stdout exactly as received (bin/clipshield pipes it into wl-copy) and the
-- status to stderr. Errors always go to stderr.
-- Exit codes: 0 done · 1 refused (too short, duplicate) · 2 no usable input.
--
-- The Watchlist is the same file the editor uses. One exception: a user
-- setup() that moves it is not loaded headless — point the CLI at it with
-- CLIPSHIELD_WATCHLIST=/path/to/watchlist.jsonl.

local function die(code, message)
	io.stderr:write(("clipshield: %s\n"):format(message))
	os.exit(code, true)
end

-- nvim -l does not pass trailing arguments as Lua varargs; they sit in
-- v:argv after the "-l <script>" pair.
local function script_args()
	local argv = vim.v.argv
	for i = 1, #argv - 1 do
		if argv[i] == "-l" then
			return vim.list_slice(argv, i + 2)
		end
	end
	return {}
end

local function parse(args)
	local cmd = args[1]
	if cmd ~= "add" and cmd ~= "copy" then
		die(64, "usage: cli add [-n NAME] [-r REPLACEMENT] | cli copy")
	end

	local name, replacement, i = "", "", 2
	while i <= #args do
		local flag = args[i]
		if cmd == "add" and flag == "-n" then
			name, i = args[i + 1] or die(64, "-n needs a name"), i + 2
		elseif cmd == "add" and flag == "-r" then
			replacement, i = args[i + 1] or die(64, "-r needs a replacement"), i + 2
		else
			die(64, "unknown argument: " .. tostring(flag))
		end
	end
	return cmd, name, replacement
end

local cmd, name, replacement = parse(script_args())

local clipshield = require("clipshield")
local override = os.getenv("CLIPSHIELD_WATCHLIST")
if override and override ~= "" then
	clipshield.config.watchlist = override
end
local watchlist = require("clipshield.watchlist")

local text = io.read("*a") or ""

if cmd == "add" then
	local value = vim.trim(text)
	if value == "" then
		die(2, "nothing to add — the selection is empty")
	end
	if #value < clipshield.config.min_length then
		die(
			1,
			("refusing to add %d characters — anything under %d matches far too much"):format(
				#value,
				clipshield.config.min_length
			)
		)
	end

	-- A broken line in the file must not be silently dropped by the rewrite
	-- that adding performs; refuse and say so instead.
	local entries, err = watchlist.read()
	if err then
		die(1, err)
	end
	for _, entry in ipairs(entries) do
		if entry.value == value then
			die(1, ("%s… is already on the Watchlist"):format(value:sub(1, 12)))
		end
	end

	watchlist.add(value, replacement, name)

	local shown = #value > 12 and (value:sub(1, 12) .. "…") or value
	local reads = replacement ~= "" and ("'" .. replacement .. "'") or "the numbered placeholder"
	io.write(("added %s — reads as %s\n"):format(shown, reads))
	os.exit(0, true)
end

-- copy
if text == "" then
	die(2, "nothing to copy — the selection is empty")
end

local entries, err = watchlist.read()
if err then
	-- Loud but not fatal: mask with the entries that do parse. Refusing to
	-- copy at all is the one thing worse than copying with a partial list.
	io.stderr:write("clipshield: " .. err .. "\n")
end

local masked, count = require("clipshield.mask").apply(text, entries, clipshield.config.placeholder)
io.write(masked)
if count > 0 then
	io.stderr:write(("clipshield: %d secret(s) masked\n"):format(count))
end
os.exit(0, true)
