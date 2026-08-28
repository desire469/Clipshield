-- The Watchlist: one JSON object per line, machine-global, hand-editable.
--
--   {"value":"sk-proj-Ab3xK9...","replacement":"my-api-key"}
--   {"value":"ghp_7fQ2m..."}
--
-- An entry without a replacement gets the numbered default placeholder.
--
-- Blank lines and lines starting with # are ignored, so the file can carry
-- comments even though JSON cannot.

local M = {}

--- Last successfully read Watchlist. Used when the file cannot be read at all,
--- so a broken file downgrades to stale protection rather than to none.
local cache = {}

local function path()
  return require("clipshield").config.watchlist
end

--- @return table entries, string|nil error
function M.read()
  local file = path()
  if vim.fn.filereadable(file) == 0 then
    -- No file yet is the normal state before the first Secret is added.
    return {}, nil
  end

  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then
    return cache, ("cannot read %s — masking with the last known Watchlist"):format(file)
  end

  local entries, broken = {}, {}
  for n, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      local decoded_ok, entry = pcall(vim.json.decode, trimmed)
      if decoded_ok and type(entry) == "table" and type(entry.value) == "string" and #entry.value > 0 then
        entries[#entries + 1] = {
          value = entry.value,
          replacement = type(entry.replacement) == "string" and entry.replacement or "",
          -- Entries written before replacements existed. Shown in the menu so
          -- the list stays readable, never substituted into copied text.
          label = type(entry.label) == "string" and entry.label or "",
        }
      else
        broken[#broken + 1] = n
      end
    end
  end

  cache = entries

  if #broken > 0 then
    return entries, ("%s: line(s) %s are not valid entries and are being ignored")
      :format(file, table.concat(broken, ", "))
  end
  return entries, nil
end

local function serialise(entry)
  local out = { value = entry.value }
  if entry.replacement and entry.replacement ~= "" then
    out.replacement = entry.replacement
  end
  if entry.label and entry.label ~= "" then
    out.label = entry.label
  end
  return vim.json.encode(out)
end

function M.write(entries)
  local file = path()
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")

  local lines = {}
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = serialise(entry)
  end
  vim.fn.writefile(lines, file)
  cache = entries
end

--- @return boolean added -- false when the value is already known
function M.add(value, replacement)
  local entries = M.read()
  for _, entry in ipairs(entries) do
    if entry.value == value then return false end
  end
  entries[#entries + 1] = { value = value, replacement = replacement or "" }
  M.write(entries)
  return true
end

--- How an entry should read in a menu: what it turns into, or failing that
--- enough of the value to recognise it by.
function M.describe(entry)
  if entry.replacement ~= "" then return "→ " .. entry.replacement end
  if entry.label ~= "" then return entry.label end
  return #entry.value > 12 and (entry.value:sub(1, 12) .. "…") or entry.value
end

function M.remove(value)
  local entries, kept = M.read(), {}
  for _, entry in ipairs(entries) do
    if entry.value ~= value then kept[#kept + 1] = entry end
  end
  M.write(kept)
end

M.path = path

return M
