-- Sign faces for the shops that changed trade: the name board and the blade still show the old shop's name,
-- so Tools/street_city_lover_spots_payload.lua puts these pictures on them.
-- Writes output/street-social-city-production/shop-refits-v1/converted-signs/<id>-H.jpg (2048 x 512), <id>-V.jpg (512 x 2048) for the blade
-- and <id>-B.jpg (2048 x 180) for the RomanceName_<id> name board over the shop front.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_signs.lua
local out = 'output/street-social-city-production/shop-refits-v1/converted-signs'
-- id, name on the sign, background, text colour
local SIGNS = {
  { 'S41', '速食店', '0xB3261E', '0xFFE9A8' }, { 'S48', 'KTV', '0x26123F', '0xFF7AD9' }, { 'S52', '居酒屋', '0x2B1A12', '0xF4D9A0' },
  { 'S58', '泳裝店', '0x0E6E99', '0xFFFFFF' }, { 'S59', '美甲店', '0xF3C9D6', '0x7A2448' }, { 'S67', '貓咪咖啡', '0x6B4A32', '0xFFF1DC' },
  { 'S69', '可麗餅', '0xFBE3B5', '0x8A3B12' }, { 'S70', '迴轉壽司', '0x12324F', '0xFFFFFF' }, { 'S72', '超市', '0x1D7A46', '0xFFFFFF' },
  { 'S73', '漫畫網咖', '0x20242B', '0x7FE3FF' }, { 'S76', '浴衣租借', '0x31406E', '0xF5E8CF' }, { 'S79', '保齡球', '0x8E1B2C', '0xFFFFFF' },
  { 'S82', '醫美診所', '0xF4F6F7', '0x2A6F7F' }, { 'S88', '燒肉店', '0x1C1512', '0xFF9A3D' }, { 'S96', 'LIVE HOUSE', '0x101014', '0xFFD24A' },
  { 'S13', '區公所', '0x24466B', '0xFFFFFF' }, { 'S66', '派出所', '0x16335C', '0xFFFFFF' }, { 'S22', '租屋仲介', '0x1F6E5B', '0xFFFFFF' },
  { 'S50', '占卜屋', '0x2A1B4D', '0xE9D08A' }, { 'S75', '婚紗禮服', '0xFAF3EC', '0xA2743F' }, { 'S91', '親子館', '0xFFD77A', '0x2D5E8C' },
  { 'S55', '手作教室', '0xC9794A', '0xFFF6E6' }, { 'S87', '早餐店', '0xF2B632', '0x5A2C0E' },
}
local FONT = "C\\:/Windows/Fonts/msjhbd.ttc"
local FF = 'Tools\\ffmpeg\\ffmpeg.exe'
os.execute('if not exist "' .. out:gsub('/', '\\') .. '" mkdir "' .. out:gsub('/', '\\') .. '"')
local function chars(s) local t = {}; for c in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do t[#t + 1] = c end; return t end
local function run(bg, size, filters, file)
  local script = file .. '.txt'
  local f = assert(io.open(script, 'wb')); f:write(table.concat(filters, ',')); f:close()
  assert(os.execute(FF .. ' -y -loglevel error -f lavfi -i color=c=' .. bg .. ':s=' .. size .. ':d=1 -/vf "' .. script .. '" -frames:v 1 -q:v 2 "' .. file .. '"'))
  os.remove(script)
end
local function esc(c) return (c:gsub('\\', '\\\\'):gsub("'", "\\'")) end
for _, s in ipairs(SIGNS) do
  local id, name, bg, fg = s[1], s[2], s[3], s[4]
  local h = { ("drawbox=x=24:y=24:w=2000:h=464:color=%s@0.8:t=8"):format(fg) }
  local size = math.min(300, math.floor(1800 / math.max(#chars(name), 1)))
  h[#h + 1] = ("drawtext=fontfile='%s':text='%s':fontsize=%d:fontcolor=%s:x=(w-text_w)/2:y=(h-text_h)/2"):format(FONT, esc(name), size, fg)
  run(bg, '2048x512', h, out .. '/' .. id .. '-H.jpg')
  local bs = math.min(136, math.floor(1700 / math.max(#chars(name), 1)))
  run(bg, '2048x180', { ("drawtext=fontfile='%s':text='%s':fontsize=%d:fontcolor=%s:x=(w-text_w)/2:y=(h-text_h)/2"):format(FONT, esc(table.concat(chars(name), #name == #chars(name) and '' or '  ')), bs, fg) }, out .. '/' .. id .. '-B.jpg')
  local v = { ("drawbox=x=24:y=24:w=464:h=2000:color=%s@0.8:t=8"):format(fg) }
  local cs = chars(name)
  if #name == #cs and #cs > 4 then
    -- latin names turn on their side
    run(bg, '2048x512', h, out .. '/' .. id .. '-V.tmp.jpg')
    assert(os.execute(FF .. ' -y -loglevel error -i "' .. out .. '/' .. id .. '-V.tmp.jpg" -vf transpose=1 -q:v 2 "' .. out .. '/' .. id .. '-V.jpg"'))
    os.remove(out .. '/' .. id .. '-V.tmp.jpg')
  else
    local cell = math.min(420, math.floor(1800 / #cs)); local y0 = (2048 - cell * #cs) // 2
    for i, c in ipairs(cs) do
      v[#v + 1] = ("drawtext=fontfile='%s':text='%s':fontsize=%d:fontcolor=%s:x=(w-text_w)/2:y=%d"):format(FONT, esc(c), math.floor(cell * .86), fg, y0 + (i - 1) * cell + cell // 14)
    end
    run(bg, '512x2048', v, out .. '/' .. id .. '-V.jpg')
  end
end
print('wrote', #SIGNS, out)
