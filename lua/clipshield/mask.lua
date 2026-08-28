-- Substitution of Secrets for Placeholders.
--
-- Pure: text in, text out. No editor state, no I/O. Everything that can go
-- subtly wrong in this plugin goes wrong in here, so it lives on its own.

local M = {}

--- Every occurrence of every entry, as {s, e, entry} spans over `text`.
local function occurrences(text, entries)
  local found = {}
  for _, entry in ipairs(entries) do
    if #entry.value > 0 then
      local init = 1
      while true do
        local s, e = string.find(text, entry.value, init, true)
        if not s then break end
        found[#found + 1] = { s = s, e = e, entry = entry }
        init = s + 1
      end
    end
  end
  return found
end

--- Longest span wins. A shorter entry that is a substring of a longer one must
--- never claim its half first, or the remainder of a real key ends up in the
--- clipboard in the clear.
local function claim(found)
  table.sort(found, function(a, b)
    local la, lb = a.e - a.s, b.e - b.s
    if la ~= lb then return la > lb end
    return a.s < b.s
  end)

  local kept = {}
  for _, span in ipairs(found) do
    local overlaps = false
    for _, taken in ipairs(kept) do
      if span.s <= taken.e and taken.s <= span.e then
        overlaps = true
        break
      end
    end
    if not overlaps then kept[#kept + 1] = span end
  end

  table.sort(kept, function(a, b) return a.s < b.s end)
  return kept
end

--- Replace every Match in `text` with its Placeholder.
---
--- An entry carrying its own replacement is substituted for it verbatim: the
--- user chose that text and wants to read exactly it. Everything else falls
--- back to the numbered default, where a number is the only thing that keeps
--- two different Secrets apart. Numbering runs from the start of `text`, so
--- the first such Secret a reader meets is always number one, and the same
--- Secret twice keeps the same number.
---@return string masked, integer count
function M.apply(text, entries, default)
  default = default or "REDACTED"

  local kept = claim(occurrences(text, entries))
  if #kept == 0 then return text, 0 end

  local numbers, last_number = {}, 0
  local out, pos = {}, 1

  for _, span in ipairs(kept) do
    local entry = span.entry
    local replacement = entry.replacement
    if replacement == nil or replacement == "" then
      if not numbers[entry.value] then
        last_number = last_number + 1
        numbers[entry.value] = last_number
      end
      replacement = default .. numbers[entry.value]
    end
    out[#out + 1] = text:sub(pos, span.s - 1)
    out[#out + 1] = replacement
    pos = span.e + 1
  end
  out[#out + 1] = text:sub(pos)

  return table.concat(out), #kept
end

return M
