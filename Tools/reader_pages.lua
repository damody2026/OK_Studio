-- Offline check of the card reader's page definition (Config/ReaderEditor/pages.json,
-- Docs/READER_DATA_DRIVEN_PAGES_DESIGN.md), before anything is built.
--
--   Tools\lua\lua.exe Tools\reader_pages.lua [--old <pages.json>] [--new <pages.json>]
--
-- With --new: what the new file changes against the old one (default: the checked-in one), page by page:
-- pages added, removed or moved, and for each page in both whether what it shows stays the same. A page
-- that swaps a shape group for the keys of that group ("items") shows the same rows, so its audit must
-- not move; anything else that changes is listed. Every item key is checked against the registry keys
-- that can be known without the game (shape.*, bone.*, the two bust physics); keys that only exist at
-- run time (pregnancy.*, style.*, a card's properties) are listed for the in-game audit to settle.
-- Exit 1 when a page's content changed or a key is unknown, so a typo is found before the build.
local M = {}

local ROOT = (arg and arg[0] or ""):gsub("[\\/]Tools[\\/][^\\/]*$", "")
if ROOT == "" or ROOT == (arg and arg[0]) then ROOT = "." end

local function read(file)
  local f = assert(io.open(file, "rb"), "cannot read " .. file)
  local s = f:read("a"); f:close(); return s
end

local function json_decode(text)
  local ok_mod, ok = pcall(require, "ok")
  if ok_mod then return ok.json.decode((text:gsub("^\239\187\191", ""))) end
  return require("json").decode((text:gsub("^\239\187\191", "")))
end

-- The shape groups as KKShapeRows splits them (display order, a group ends at bSep): {face = {{keys}...}, body = ...}.
function M.shape_groups(source)
  local groups, cur = { face = {}, body = {} }, { face = {}, body = {} }
  for _, idx, body, sep in source:gmatch('{TEXT%("([^"]*)"%),%s*(%d+),%s*(%a+),%s*(%a+)}') do
    local kind = body == "true" and "body" or "face"
    table.insert(cur[kind], ("shape.%s.%s"):format(kind, idx))
    if sep == "true" then table.insert(groups[kind], cur[kind]); cur[kind] = {} end
  end
  for _, kind in ipairs({ "face", "body" }) do
    if #cur[kind] > 0 then table.insert(groups[kind], cur[kind]) end
  end
  return groups
end

local AXES = { [-1] = "scale.uniform", [0] = "scale.x", "scale.y", "scale.z", "length", "position.x", "position.y",
  "position.z", "rotation.x", "rotation.y", "rotation.z" }

-- The registry keys known without the game (OKCharacterMCPRegistry::Parameters): a set.
function M.static_keys(shape_source, bone_source)
  local keys = {}
  for i = 0, 51 do keys["shape.face." .. i] = true end
  for i = 0, 43 do keys["shape.body." .. i] = true end
  for bone, right, axis in bone_source:gmatch('{TEXT%("[^"]*"%),%s*TEXT%("[^"]*"%),%s*TEXT%("([^"]*)"%),%s*TEXT%("([^"]*)"%),%s*(%-?%d+)') do
    local a = AXES[tonumber(axis)]
    if a then
      if bone ~= "" then keys["bone." .. bone .. "." .. a] = true end
      if right ~= "" then keys["bone." .. right .. "." .. a] = true end
    end
  end
  keys["physics.bustSoftness"], keys["physics.bustWeight"] = true, true
  return keys
end

-- Keys whose existence only the running game knows.
function M.runtime_only(key)
  return key:match("^pregnancy%.") or key:match("^style%.") or not (key:match("^shape%.") or key:match("^bone%.") or key:match("^physics%."))
end

local function source_token(spec, groups)
  if spec.shape then
    local g = groups[spec.shape] and groups[spec.shape][(spec.group or -1) + 1]
    if not g then return { "missing shape group " .. tostring(spec.shape) .. " " .. tostring(spec.group) } end
    local out = {}
    for _, k in ipairs(g) do out[#out + 1] = "key " .. k end
    return out
  end
  for _, field in ipairs({ "rows", "widget", "named", "drawer" }) do
    if spec[field] then return { field .. " " .. tostring(spec[field]) } end
  end
  return { "unknown source" }
end

-- What a page shows, in order: shape groups expanded to their keys, then the items' keys. A page that swaps
-- {"shape": "face", "group": 0} for the six items of that group gives the same list.
function M.page_rows(sub, groups)
  local rows = {}
  for _, spec in ipairs(sub.sources or {}) do
    for _, t in ipairs(source_token(spec, groups)) do rows[#rows + 1] = t end
  end
  for _, item in ipairs(sub.items or {}) do rows[#rows + 1] = "key " .. tostring(item.key) end
  return rows
end

-- Everything else on a page (what it does when entered, its own buttons...), as one comparable string.
local function page_rest(sub)
  local parts = {}
  for _, k in ipairs({ "pickers", "bone_category", "enter", "signature", "shown_only", "builder", "own_buttons", "needs" }) do
    local v = sub[k]
    if v ~= nil then
      local ok_mod, ok = pcall(require, "ok")
      local enc = ok_mod and ok.json.encode or require("json").encode
      parts[#parts + 1] = k .. "=" .. enc(v)
    end
  end
  return table.concat(parts, ";")
end

local function index(doc)
  local list, by = {}, {}
  for ci, c in ipairs(doc.categories or {}) do
    for si, s in ipairs(c.subs or {}) do
      local path = c.name .. "›" .. s.name
      list[#list + 1] = path
      by[path] = { sub = s, tab = c.tab or 0, pos = #list }
    end
  end
  return list, by
end

-- The differences between two definitions and the keys no registry has: {lines}, {unknown}, {runtime}.
function M.compare(old, new, groups, keys)
  local lines, unknown, runtime = {}, {}, {}
  local old_list, old_by = index(old)
  local new_list, new_by = index(new)
  for _, p in ipairs(old_list) do if not new_by[p] then lines[#lines + 1] = "removed  " .. p end end
  local kept_old, kept_new = {}, {}
  for _, p in ipairs(old_list) do if new_by[p] then kept_old[#kept_old + 1] = p end end
  for _, p in ipairs(new_list) do
    if not old_by[p] then lines[#lines + 1] = "added    " .. p
    else kept_new[#kept_new + 1] = p end
  end
  for i, p in ipairs(kept_new) do
    if kept_old[i] ~= p then lines[#lines + 1] = "moved    " .. p end
  end
  for _, p in ipairs(kept_new) do
    local a, b = old_by[p], new_by[p]
    local ra, rb = M.page_rows(a.sub, groups), M.page_rows(b.sub, groups)
    local same = #ra == #rb
    for i = 1, math.max(#ra, #rb) do if ra[i] ~= rb[i] then same = false end end
    if not same then
      lines[#lines + 1] = "changed  " .. p .. "  shows: " .. table.concat(ra, ", ") .. "  ->  " .. table.concat(rb, ", ")
    end
    if page_rest(a.sub) ~= page_rest(b.sub) or a.tab ~= b.tab then lines[#lines + 1] = "changed  " .. p .. "  (behaviour or tab)" end
  end
  for _, p in ipairs(new_list) do
    for _, item in ipairs(new_by[p].sub.items or {}) do
      local k = tostring(item.key)
      if keys[k] then
      elseif M.runtime_only(k) then runtime[#runtime + 1] = p .. "  " .. k
      else unknown[#unknown + 1] = p .. "  " .. k end
    end
  end
  return lines, unknown, runtime
end

function M.main(argv)
  local old_file, new_file = ROOT .. "/Config/ReaderEditor/pages.json", nil
  local i = 1
  while i <= #argv do
    if argv[i] == "--old" then old_file = argv[i + 1]; i = i + 2
    elseif argv[i] == "--new" then new_file = argv[i + 1]; i = i + 2
    else error("unknown argument " .. argv[i] .. " (--old <file> --new <file>)", 0) end
  end
  local groups = M.shape_groups(read(ROOT .. "/Plugins/KKCard/Source/KKCard/Private/KKShapeRows.cpp"))
  local keys = M.static_keys("", read(ROOT .. "/Source/OpenKoikatsu/OKBoneControls.h"))
  local old = json_decode(read(old_file))
  local new = new_file and json_decode(read(new_file)) or old
  local lines, unknown, runtime = M.compare(old, new, groups, keys)
  local _, by = index(new)
  local pages = 0; for _ in pairs(by) do pages = pages + 1 end
  print(("pages: %d in %s"):format(pages, new_file or old_file))
  for _, l in ipairs(lines) do print(l) end
  for _, u in ipairs(unknown) do print("unknown key  " .. u) end
  for _, r in ipairs(runtime) do print("run-time key (the in-game audit decides)  " .. r) end
  local bad = #lines + #unknown
  print(bad == 0 and "same pages, every key known: the in-game audit should not move" or ("%d difference(s)"):format(bad))
  return bad == 0 and 0 or 1
end

if arg and arg[0] and (arg[0]:match("[\\/]reader_pages%.lua$") or arg[0]:match("^reader_pages%.lua$")) then os.exit(M.main(arg)) end
return M
