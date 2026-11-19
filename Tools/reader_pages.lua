-- Offline check of the card reader's page definition (Config/ReaderEditor/pages.json,
-- Docs/READER_DATA_DRIVEN_PAGES_DESIGN.md), before anything is built.
--
--   Tools\lua\lua.exe Tools\reader_pages.lua [--old <pages.json>] [--new <pages.json>]
--
-- With --new: what the new file changes against the old one (default: the checked-in one), page by page:
-- pages added, removed or moved, and for each page in both whether what it shows stays the same. A page
-- that swaps a shape group for the keys of that group ("items") shows the same rows, so its audit must
-- not move; anything else that changes is listed, a changed order included. Every item key is checked against the registry keys
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
  -- The bust rows are the rows of the two bust physics keys (OKReaderScreen BustRows, in BoneSliders order).
  if spec.rows == "bust" then return { "key physics.bustSoftness", "key physics.bustWeight" } end
  for _, field in ipairs({ "rows", "widget", "named", "drawer" }) do
    if spec[field] then return { field .. " " .. tostring(spec[field]) } end
  end
  return { "unknown source" }
end

-- What a page shows, in order. A page lists its rows either as "sources" (step 1) or as "items" (step 2), one
-- ordered list whose entries are a registry key ({"key": ...}) or any source ({"rows": "bust"}, {"widget": ...},
-- {"shape": ...}): the list's order is the page's order, nothing is put first. Shape groups expand to their keys
-- and the bust rows to the two bust physics keys, so {"shape": "face", "group": 0} and the six keys of that group
-- give the same list. The second result is why the page is not valid (nil when it is).
function M.page_rows(sub, groups)
  local rows, err = {}, nil
  if sub.sources and sub.items then err = "has both sources and items (one ordered list: items)" end
  for _, spec in ipairs(sub.items or sub.sources or {}) do
    if spec.key ~= nil then rows[#rows + 1] = "key " .. tostring(spec.key)
    else
      for _, t in ipairs(source_token(spec, groups)) do
        rows[#rows + 1] = t
        if t == "unknown source" or t:match("^missing ") then err = err or ("bad entry: " .. t) end
      end
    end
  end
  return rows, err
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
    if not old_by[p] then
      lines[#lines + 1] = "added    " .. p
      local _, err = M.page_rows(new_by[p].sub, groups)
      if err then lines[#lines + 1] = "invalid  " .. p .. "  " .. err end
    else kept_new[#kept_new + 1] = p end
  end
  for i, p in ipairs(kept_new) do
    if kept_old[i] ~= p then lines[#lines + 1] = "moved    " .. p end
  end
  for _, p in ipairs(kept_new) do
    local a, b = old_by[p], new_by[p]
    local ra = M.page_rows(a.sub, groups)
    local rb, err = M.page_rows(b.sub, groups)
    if err then lines[#lines + 1] = "invalid  " .. p .. "  " .. err end
    local same = #ra == #rb
    for i = 1, math.max(#ra, #rb) do if ra[i] ~= rb[i] then same = false end end
    if not same then
      lines[#lines + 1] = "changed  " .. p .. "  shows: " .. table.concat(ra, ", ") .. "  ->  " .. table.concat(rb, ", ")
    end
    if page_rest(a.sub) ~= page_rest(b.sub) or a.tab ~= b.tab then lines[#lines + 1] = "changed  " .. p .. "  (behaviour or tab)" end
  end
  for _, p in ipairs(new_list) do
    for _, item in ipairs(new_by[p].sub.items or {}) do
      local k = item.key ~= nil and tostring(item.key) or nil
      if k == nil or keys[k] then
      elseif M.runtime_only(k) then runtime[#runtime + 1] = p .. "  " .. k
      else unknown[#unknown + 1] = p .. "  " .. k end
    end
  end
  return lines, unknown, runtime
end

-- What each of the audit's four columns says (OKReaderScreen `audit`, its registry line), written once here so the
-- C++ side and the tests read the same rule (Docs/READER_DATA_DRIVEN_PAGES_DESIGN.md, 稽核四欄):
--   s.card        a card is selected (what reader_call state's unknown_plugin_sections_status calls one)
--   s.ui, s.range counts over the registry as it is now; without a card the card's own properties are not in it
--   s.data        page keys the registry lacks; s.unjudged: of the page keys, those only a card has (not counted
--                 without a card, as their absence says nothing then)
--   s.kkex        reader_call state's unknown_plugin_sections_status (bad2861df: "no_card", "not_read",
--                 "unsupported"; "read" is given as the list itself), or the older names below:
--                 "busy" (the card's properties are being read), "unread" (not read for this card and outfit yet),
--                 "absent" (read, but the producer gave no unknown_plugin_sections: this build lacks the support),
--                 or the list of section keys (empty list: none unknown)
-- A missing answer is never written as 0: 0 means "counted and none".
-- Sections ok-extract leaves out of PLUGIN_SECTIONS on purpose (F tree plugins.rs, cb5459b1d), so they always come
-- back in unknown_plugin_sections; they are not "this build lacks support" and are not counted as unknown:
-- ABMX is edited through bone.*, the sideloader resolve list is rewritten as a whole by appearance, and
-- OpenKoikatsu.AppearanceSource is our own provenance block. Matched case-insensitively, like the producer.
M.DELIBERATELY_ABSENT = {
  ["kkabmplugin.abmdata"] = true, ["kkabmx.core"] = true,
  ["com.bepis.sideloader.universalautoresolver"] = true, ["openkoikatsu.appearancesource"] = true,
}

function M.audit_cells(s)
  local cells = {}
  if s.card then
    cells.ui = tostring(s.ui)
    cells.data = tostring(s.data)
    cells.range = tostring(s.range)
    if s.kkex == "no_card" then cells.kkex = "沒有卡"
    elseif s.kkex == "busy" then cells.kkex = "讀取中"
    elseif s.kkex == "unread" or s.kkex == "not_read" or s.kkex == nil then cells.kkex = "未讀（這張卡的屬性還沒讀）"
    elseif s.kkex == "absent" or s.kkex == "unsupported" then cells.kkex = "缺支援（這個 build 的產生端沒有 unknown_plugin_sections）"
    else
      local unknown, kept_out = {}, {}
      for _, key in ipairs(s.kkex) do
        if M.DELIBERATELY_ABSENT[key:lower()] then kept_out[#kept_out + 1] = key else unknown[#unknown + 1] = key end
      end
      cells.kkex = tostring(#unknown) .. (#unknown > 0 and ("：" .. table.concat(unknown, "、")) or "")
      if #kept_out > 0 then cells.kkex = cells.kkex .. "；刻意不收 " .. #kept_out .. "（" .. table.concat(kept_out, "、") .. "）" end
    end
  else
    cells.ui = s.ui .. "（沒有卡：卡的屬性鍵未計）"
    cells.data = s.data .. ("（沒有卡：只有卡才有的鍵 %d 個未判）"):format(s.unjudged or 0)
    cells.range = s.range .. "（沒有卡：卡的屬性鍵未計）"
    cells.kkex = "沒有卡"
  end
  return cells
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
