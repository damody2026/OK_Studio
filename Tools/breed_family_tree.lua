-- 配種家族樹：讀配出來的卡（okDn 血緣紀錄）自動排出世代，畫成一張圖（ffmpeg 合成）。
-- 祖先卡不用列：從孩子的紀錄找到父母的卡（路徑），一路找到原卡。每張卡標名字與檔案大小；
-- 依賴父母的子卡（okDn depends）標「依賴父母」，原卡與匯出的完整卡標「完整卡」。Docs/OK_BREEDING.md。
-- Usage: Tools\lua\lua.exe Tools\breed_family_tree.lua --out <圖.png> [--title <標題>] [--subtitle <副標>] [--list <清單檔>] <卡或資料夾>...
package.path = 'Tools/lua/?.lua;' .. package.path
local json = require 'ok.json'
local lfs = require 'lfs'
-- (okfs: UTF-8 file names; io.open takes the system code page and cannot open 刻晴×雷電.png)
local fs = require 'okfs'

-- (Windows hands lua.exe its arguments in the system code page, not UTF-8: Chinese titles are best left to the defaults)
local args, inputs = { title = '配種大家族', subtitle = '子卡只存父母沒有的資源，開卡時才讀父母的卡　　藍框：依賴父母　金框：完整卡' }, {}
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == '--out' or a == '--title' or a == '--subtitle' then args[a:sub(3)] = arg[i + 1]; i = i + 2
    elseif a == '--list' then
      -- a UTF-8 file, one card a line (card names such as 刻晴×雷電 do not survive the command line)
      for line in io.lines(arg[i + 1]) do line = line:gsub('^\239\187\191', ''):gsub('%s+$', ''); if line ~= '' then inputs[#inputs + 1] = line end end
      i = i + 2
    else inputs[#inputs + 1] = a; i = i + 1 end
  end
end
assert(args.out and #inputs > 0, 'usage: breed_family_tree.lua --out <png> [--title t] [--subtitle s] <card or folder>...')

local function read(p) local f = fs.open(p, 'rb'); if not f then return nil end; local s = f:read('a'); f:close(); return s end
local function write(p, s) local f = assert(fs.open(p, 'wb')); f:write(s); f:close() end
local function slash(p) return (p:gsub('\\', '/')) end

-- The PNG chunks before IEND: { kind = data }, and the picture alone (no ok* chunks, nothing after IEND).
local function card(path)
  local s = read(path)
  if not s or s:sub(1, 8) ~= '\137PNG\r\n\26\n' then return nil end
  local chunks, picture, pos = {}, { s:sub(1, 8) }, 9
  while pos + 12 <= #s + 1 do
    local len = string.unpack('>I4', s, pos)
    local kind = s:sub(pos + 4, pos + 7)
    if kind:sub(1, 2) ~= 'ok' then picture[#picture + 1] = s:sub(pos, pos + 11 + len) end
    if kind == 'IEND' then break end
    chunks[kind] = s:sub(pos + 8, pos + 7 + len)
    pos = pos + 12 + len
  end
  return { chunks = chunks, picture = table.concat(picture), size = #s }
end

local files = {}
for _, input in ipairs(inputs) do
  if lfs.attributes(input, 'mode') == 'directory' then
    for name in lfs.dir(input) do if name:lower():match('%.png$') then files[#files + 1] = input .. '/' .. name end end
  else files[#files + 1] = input end
end
table.sort(files)

local nodes, order = {}, {}
local function node(id) if not nodes[id] then nodes[id] = { id = id }; order[#order + 1] = id end; return nodes[id] end
local function fill(n, path, c)
  n.path, n.size, n.picture = path, c.size, c.picture
end
local pending = {}
for _, path in ipairs(files) do
  local c = card(path)
  local dn = c and c.chunks.okDn and json.decode(c.chunks.okDn)
  if dn and dn.format == 'ok-breed' then
    local id = c.chunks.okId or path
    local n = node(id)
    fill(n, path, c)
    n.dna, n.name, n.generation = dn, dn.name or '', dn.generation or 1
    n.depends = type(dn.depends) == 'table' and (dn.depends.mother == true or dn.depends.father == true)
    n.mother, n.father = dn.mother.id, dn.father.id
    for _, p in ipairs({ dn.mother, dn.father }) do pending[#pending + 1] = p end
  end
end
-- Ancestors not listed: their cards by the path the child recorded.
for _, p in ipairs(pending) do
  local n = node(p.id)
  n.name = (n.name and n.name ~= '') and n.name or p.name
  n.generation = n.generation or p.generation or 0
  if not n.picture then
    local c = p.path and card(p.path)
    if c then fill(n, p.path, c) end
  end
end
local count = 0
for _, id in ipairs(order) do if nodes[id].picture then count = count + 1 end end
assert(count > 0, 'no bred cards found')

-- Rows by generation; the first row in the order the children name them, later rows under their parents.
local rows, maxgen = {}, 0
for _, id in ipairs(order) do
  local n = nodes[id]
  if n.picture then rows[n.generation] = rows[n.generation] or {}; table.insert(rows[n.generation], n); maxgen = math.max(maxgen, n.generation) end
end
local TW, TH, GAP, LABEL, ROWGAP, LEFT, TOP = 170, 238, 34, 62, 92, 150, 150
local width = 0
for g = 0, maxgen do width = math.max(width, #(rows[g] or {}) * (TW + GAP) - GAP) end
width = width + LEFT + 60
local function place(g)
  local row = rows[g] or {}
  if g > 0 then
    for i, n in ipairs(row) do
      local m, f = nodes[n.mother], nodes[n.father]
      n.key = ((m and m.cx or 0) + (f and f.cx or 0)) / 2 + i * 1e-3
    end
    table.sort(row, function(a, b) return a.key < b.key end)
  end
  local w = #row * (TW + GAP) - GAP
  local x0 = LEFT + math.floor((width - LEFT - 60 - w) / 2)
  for i, n in ipairs(row) do
    n.x, n.y = x0 + (i - 1) * (TW + GAP), TOP + g * (TH + LABEL + ROWGAP)
    n.cx = n.x + TW // 2
  end
end
for g = 0, maxgen do place(g) end
local height = TOP + (maxgen + 1) * (TH + LABEL + ROWGAP) - ROWGAP + 40

-- ffmpeg filter graph.
local work = args.out .. '.parts'
lfs.mkdir(work)
local function esc(p) return "'" .. slash(p):gsub(':', '\\:') .. "'" end
local FONT, BOLD = esc('C:/Windows/Fonts/msjh.ttc'), esc('C:/Windows/Fonts/msjhbd.ttc')
local texts = 0
local function text(s, x, y, size, color, bold, center)
  texts = texts + 1
  local file = string.format('%s/t%d.txt', work, texts)
  write(file, s)
  return string.format("drawtext=fontfile=%s:textfile=%s:fontsize=%d:fontcolor=%s:x=%s:y=%d", bold and BOLD or FONT, esc(lfs.currentdir() .. '/' .. file),
    size, color, center and string.format('%d-text_w/2', x) or tostring(x), y)
end
local function box(x, y, w, h, color) return string.format('drawbox=x=%d:y=%d:w=%d:h=%d:color=%s:t=fill', x, y, w, h, color) end

local inputs_args, ops, overlays = {}, {}, {}
local placed = {}
for g = 0, maxgen do for _, n in ipairs(rows[g] or {}) do placed[#placed + 1] = n end end
for i, n in ipairs(placed) do
  local file = string.format('%s/p%d.png', work, i)
  write(file, n.picture)
  inputs_args[#inputs_args + 1] = string.format('-i "%s"', file)
end
local palette = { '0xf2a7c3', '0x8fd3f4', '0xf6d58e', '0xa9e5a0', '0xc6a8f0', '0xf3a98a', '0x9ce0d8', '0xe8c0a0' }
-- Connectors: a bar under each couple, a line from its middle to each child.
local couples, couple_order = {}, {}
for _, n in ipairs(placed) do
  if n.mother and n.father and nodes[n.mother].cx and nodes[n.father].cx then
    local k = n.mother .. '|' .. n.father
    if not couples[k] then couples[k] = { m = nodes[n.mother], f = nodes[n.father], kids = {} }; couple_order[#couple_order + 1] = k end
    table.insert(couples[k].kids, n)
  end
end
local lanes = {}
for ci, k in ipairs(couple_order) do
  local c = couples[k]
  local color = palette[(ci - 1) % #palette + 1]
  local bottom = math.max(c.m.y, c.f.y) + TH + LABEL
  local lane = (lanes[bottom] or 0); lanes[bottom] = lane + 1
  local bar = bottom + 10 + lane * 9
  local x1, x2 = math.min(c.m.cx, c.f.cx), math.max(c.m.cx, c.f.cx)
  ops[#ops + 1] = box(c.m.cx - 2, math.min(c.m.y + TH + LABEL, bar), 4, math.abs(bar - (c.m.y + TH + LABEL)) + 4, color)
  ops[#ops + 1] = box(c.f.cx - 2, math.min(c.f.y + TH + LABEL, bar), 4, math.abs(bar - (c.f.y + TH + LABEL)) + 4, color)
  ops[#ops + 1] = box(x1, bar, x2 - x1 + 4, 4, color)
  local mid = (x1 + x2) // 2
  for _, kid in ipairs(c.kids) do
    local bus = kid.y - 18 - lane * 7
    ops[#ops + 1] = box(mid, bar, 4, bus - bar + 4, color)
    ops[#ops + 1] = box(math.min(mid, kid.cx), bus, math.abs(kid.cx - mid) + 4, 4, color)
    ops[#ops + 1] = box(kid.cx, bus, 4, kid.y - bus, color)
  end
end
local function mb(bytes) return string.format('%.1f MB', bytes / 1048576) end
for _, n in ipairs(placed) do
  ops[#ops + 1] = box(n.x - 3, n.y - 3, TW + 6, TH + 6, n.depends and '0x8fd3f4' or '0xf6d58e')
  ops[#ops + 1] = text(n.name ~= '' and n.name or '?', n.cx, n.y + TH + 8, 20, 'white', true, true)
  ops[#ops + 1] = text(mb(n.size) .. (n.depends and '・依賴父母' or '・完整卡'), n.cx, n.y + TH + 36, 15, n.depends and '0x8fd3f4' or '0xf6d58e', false, true)
end
for g = 0, maxgen do
  if rows[g] then ops[#ops + 1] = text(g == 0 and '原卡' or string.format('第 %d 代', g), 30, TOP + g * (TH + LABEL + ROWGAP) + TH // 2 - 14, 26, '0xd0d4e8', true, false) end
end
ops[#ops + 1] = text(args.title, width // 2, 36, 44, 'white', true, true)
if args.subtitle ~= '' then ops[#ops + 1] = text(args.subtitle, width // 2, 96, 20, '0xb8bcd0', false, true) end

local graph = { string.format('color=c=0x1b1d2a:s=%dx%d,format=rgb24[bg0]', width, height) }
local last = 'bg0'
for i, n in ipairs(placed) do
  graph[#graph + 1] = string.format('[%d:v]scale=%d:%d:force_original_aspect_ratio=increase,crop=%d:%d,format=rgb24[p%d]', i - 1, TW, TH, TW, TH, i)
end
local chain = {}
for _, op in ipairs(ops) do if op:find('^drawbox') then chain[#chain + 1] = op end end
graph[#graph + 1] = string.format('[%s]%s[lines]', last, table.concat(chain, ','))
last = 'lines'
for i, n in ipairs(placed) do
  graph[#graph + 1] = string.format('[%s][p%d]overlay=x=%d:y=%d[o%d]', last, i, n.x, n.y, i)
  last = 'o' .. i
end
local labels = {}
for _, op in ipairs(ops) do if op:find('^drawtext') then labels[#labels + 1] = op end end
graph[#graph + 1] = string.format('[%s]%s[out]', last, table.concat(labels, ','))
local script = work .. '/graph.txt'
write(script, table.concat(graph, ';\n'))
local ffmpeg = 'Tools/ffmpeg/ffmpeg.exe'
local cmd = string.format('"%s" -y -loglevel error %s -/filter_complex "%s" -map "[out]" -frames:v 1 "%s"', ffmpeg, table.concat(inputs_args, ' '), script, args.out)
local ok = os.execute('"' .. cmd .. '"')
for name in lfs.dir(work) do if name ~= '.' and name ~= '..' then os.remove(work .. '/' .. name) end end
lfs.rmdir(work)
assert(ok, 'ffmpeg failed')
print(string.format('family tree: %d cards, %d generations -> %s', #placed, maxgen + 1, args.out))
