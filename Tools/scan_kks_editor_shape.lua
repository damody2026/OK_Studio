-- Reads the original character editor's body/face sections out of the decompiled source and prints, for every slider,
-- which shape index it drives. The pairing is mechanical: each ChaCustom/Cvs*.cs declares its sliders in order
-- (`private Slider sld<Name>`) and an `arrIndex` table of the same length; the Nth slider writes
-- `SetShapeFaceValue(arrIndex[N], v)` (or SetShapeBodyValue). So slider name ↔ shape index comes straight out of
-- those two lists, with no guessing. Sections whose sliders are not shape values (colour, texture, paint) have no
-- `arrIndex` and are reported as such instead of being silently skipped.
--
--   Tools\lua\lua.exe Tools\scan_kks_editor_shape.lua [-Source DIR] [-Section NAME] [-Markdown]
--
-- -Source defaults to D:/XKoikatuSunshine/kks_decomp (the local path; the one written in AGENTS.md/README is only an
-- example and is not guaranteed to exist on any machine).
local ok = require "ok"
local path = require "ok.path"

local USAGE = [[
Tools\lua\lua.exe Tools\scan_kks_editor_shape.lua [-Source DIR] [-Section NAME] [-Markdown]
]]
local VALUES = { source = true, section = true }
local SWITCHES = { markdown = true, help = true }
local o = {}
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    local name = a:match("^%-%-?([%a%-]+)$")
    if not name then error(("unexpected argument %q\n%s"):format(a, USAGE)) end
    name = name:lower():gsub("%-", "")
    if VALUES[name] then i = i + 1; o[name] = arg[i] or error(("-%s needs a value"):format(name))
    elseif SWITCHES[name] then o[name] = true
    else error(("unknown option %q\n%s"):format(a, USAGE)) end
    i = i + 1
  end
end
if o.help then print(USAGE) return end

local source = path.norm(o.source or "D:/XKoikatuSunshine/kks_decomp")
local dir = source .. "/Assembly-CSharp/ChaCustom"
if not path.is_dir(dir) then
  error(("no decompiled editor source at %s\nGive -Source <kks_decomp folder>."):format(dir))
end

-- 顔 then 体, in the order the original's menus show them (CustomChangeFaceMenu / CustomChangeBodyMenu).
local SECTIONS = {
  { page = "顔", name = "顔全体", file = "CvsFaceAll" },
  { page = "顔", name = "耳", file = "CvsEar" },
  { page = "顔", name = "あご", file = "CvsChin" },
  { page = "顔", name = "頬", file = "CvsCheek" },
  { page = "顔", name = "眉", file = "CvsEyebrow" },
  { page = "顔", name = "目①", file = "CvsEye01" },
  { page = "顔", name = "目②", file = "CvsEye02" },
  { page = "顔", name = "鼻", file = "CvsNose" },
  { page = "顔", name = "口", file = "CvsMouth" },
  { page = "顔", name = "ほくろ", file = "CvsMole" },
  { page = "顔", name = "メイク", file = "CvsMakeup" },
  { page = "顔", name = "顔型全体", file = "CvsFaceShapeAll" },
  { page = "体", name = "体全体", file = "CvsBodyAll" },
  { page = "体", name = "胸", file = "CvsBreast" },
  { page = "体", name = "上半身", file = "CvsBodyUpper" },
  { page = "体", name = "下半身", file = "CvsBodyLower" },
  { page = "体", name = "腕", file = "CvsArm" },
  { page = "体", name = "脚", file = "CvsLeg" },
  { page = "体", name = "爪", file = "CvsNail" },
  { page = "体", name = "下毛", file = "CvsUnderhair" },
  { page = "体", name = "日焼け", file = "CvsSunburn" },
  { page = "体", name = "ボディペイント", file = "CvsBodyPaint" },
  { page = "体", name = "体型全体", file = "CvsBodyShapeAll" },
}

local function read(file)
  local p = dir .. "/" .. file .. ".cs"
  if not path.is_file(p) then return nil end
  return path.read_text(p)
end

-- The sliders arrIndex is indexed by. **Declaration order is not it**: every section builds an explicit
-- `sliders = new Slider[N] { sldA, sldB, ... }` and that array is what pairs with arrIndex. CvsBodyShapeAll declares
-- 47 sliders but puts only 44 in the array (bustSoftness/bustWeight/areolaSize are not shape values and are written
-- separately), and its array order differs from the declaration order — pairing by declaration order gave wrong
-- indices for most of the body (caught before publishing, 2026-11-19). Declaration order is only a fallback, and the
-- output says which of the two was used.
local function sliders(text)
  local block = text:match("sliders%s*=%s*new%s+Slider%[%d*%]%s*(%b{})")
  if block then
    local names = {}
    for name in block:gmatch("sld([%w_]+)") do names[#names + 1] = name end
    return names, "array"
  end
  local names = {}
  for name in text:gmatch("private%s+Slider%s+sld([%w_]+)%s*;") do names[#names + 1] = name end
  return names, "declaration order (no explicit array)"
end

-- `private readonly int[] arrIndex = new int[N] { 24, 25, ... };` — also the multi-line form.
local function indices(text)
  local block = text:match("arrIndex%s*=%s*new%s+int%[%d*%]%s*(%b{})")
  if not block then return nil end
  local list = {}
  for n in block:gmatch("(%-?%d+)") do list[#list + 1] = tonumber(n) end
  return list
end

local function kind(text)
  if text:find("SetShapeFaceValue", 1, true) then return "shape.face" end
  if text:find("SetShapeBodyValue", 1, true) then return "shape.body" end
  return nil
end

local rows, notes = {}, {}
for _, s in ipairs(SECTIONS) do
  if not o.section or o.section:lower() == s.file:lower() then
    local text = read(s.file)
    if not text then
      notes[#notes + 1] = ("%s／%s：找不到 %s.cs"):format(s.page, s.name, s.file)
    else
      local sld, how = sliders(text)
      local idx, key = indices(text), kind(text)
      if not idx or not key then
        -- Not a shape section (colour, texture, paint, pattern): say so with what it does declare, so the gap list
        -- can pick it up as its own kind of item instead of it vanishing from the table.
        notes[#notes + 1] = ("%s／%s（%s）：沒有 arrIndex／不是體型值，滑桿 %d 個、開關 %d 個、下拉 %d 個")
          :format(s.page, s.name, s.file, #sld,
            select(2, text:gsub("private%s+Toggle%s+tgl", "")),
            select(2, text:gsub("private%s+TMP_Dropdown", "")))
      else
        do
          local declared = {}
          for name in text:gmatch("private%s+Slider%s+sld([%w_]+)%s*;") do declared[#declared + 1] = name end
          local paired = {}
          for _, n in ipairs(sld) do paired[n] = true end
          local left = {}
          for _, n in ipairs(declared) do if not paired[n] then left[#left + 1] = "sld" .. n end end
          if #left > 0 then
            notes[#notes + 1] = ("%s／%s（%s）：這幾個滑桿**不是體型值**，另有去處：%s")
              :format(s.page, s.name, s.file, table.concat(left, "、"))
          end
        end
        if #sld ~= #idx then
          notes[#notes + 1] = ("%s／%s（%s）：滑桿 %d 個但 arrIndex %d 項，**對不上，要人工核**")
            :format(s.page, s.name, s.file, #sld, #idx)
        end
        for i = 1, math.min(#sld, #idx) do
          rows[#rows + 1] = { page = s.page, section = s.name, file = s.file, order = i, how = how,
                              slider = sld[i], key = ("%s.%d"):format(key, idx[i]) }
        end
      end
    end
  end
end

if o.markdown then
  print("| 分頁 | 分類 | # | 原作滑桿 | 資料鍵 |")
  print("|---|---|---:|---|---|")
  for _, r in ipairs(rows) do
    print(("| %s | %s | %d | `sld%s` | `%s` |"):format(r.page, r.section, r.order, r.slider, r.key))
  end
else
  for _, r in ipairs(rows) do
    print(("%s\t%s\t%d\tsld%s\t%s"):format(r.page, r.section, r.order, r.slider, r.key))
  end
end
if #notes > 0 then
  print("")
  print("-- 需要另外處理的分類（不是體型值，或數量對不上）：")
  for _, n in ipairs(notes) do print("-- " .. n) end
end
print(("-- 合計 %d 個體型滑桿"):format(#rows))
