-- Reads the rows OKStudio.ProfileSceneLoad writes (Saved/Reports/scene-load/<tag>.json) and prints the asked-for
-- fields, one line a row.
--
-- The point of this script is the one thing a grep of the json cannot do: a field that is NOT in the row prints
-- MISSING, never a blank or a 0. "The field was not written" and "the field was written as 0" mean opposite things
-- (ERROR_LOG 7g: missing data read as a result), and a pipeline that silently turns the first into the second is how
-- a measurement that never happened ends up in a table as a number.
--
--   Tools\lua\lua.exe Tools\scene_load_report.lua <report.json> [field ...]
--
-- With no field names it prints the default set for the scene-load questions.

local ok = require("ok")
local json = ok.json
local path = ok.path

local DEFAULT = { "scene", "pass", "ready_ms", "load_call_ms", "build_ms", "build_frames",
                  "sync_ms", "sync_world_ms", "item_open_worker_ms" }

local function main()
  local args = arg
  local file = args[1] or error("usage: scene_load_report.lua <report.json> [field ...]", 0)
  if not path.is_file(file) then error("no such report: " .. file, 0) end
  local fields = {}
  for i = 2, #args do fields[#fields + 1] = args[i] end
  if #fields == 0 then fields = DEFAULT end

  local text = assert(io.open(file, "rb")):read("a")
  local doc = json.decode(text)
  local rows = doc.rows or doc
  if type(rows) ~= "table" or #rows == 0 then error("no rows in " .. file, 0) end

  io.write(table.concat(fields, "\t"), "\n")
  for _, row in ipairs(rows) do
    local out = {}
    for _, f in ipairs(fields) do
      local v = row[f]
      -- MISSING, not "" and not 0: the row simply does not carry this field.
      if v == nil then
        out[#out + 1] = "MISSING"
      elseif type(v) == "number" then
        out[#out + 1] = string.format("%.1f", v)
      else
        out[#out + 1] = tostring(v)
      end
    end
    io.write(table.concat(out, "\t"), "\n")
  end
  io.write(("# %d row(s) from %s\n"):format(#rows, file))
end

ok.main(main)
