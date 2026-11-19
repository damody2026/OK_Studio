-- 产生一张「一眼看得出贴错」的检查贴图，给读卡器「材質貼圖 › 指派」的拍照用。
--
-- 为什么不随便拿一张图：随便指派一张图拍出来只是一张花脸，证明不了写回对不对。这张图要同时能验四件事：
--   棋盘格        → 缩放与平铺（UV scale 错了，格子大小就不对）
--   四角不同颜色  → 旋转与镜像（左上红、右上绿、左下蓝、右下黄，换位置就是转了或翻了）
--   中央一个「F」 → 两个轴都不对称，所以水平翻、垂直翻、转 90° 都看得出来（UV 检查的老办法）
--   外框一圈      → 边界与 wrap（格子被切一半、或外框消失，就是取样超出 0..1）
--
-- 用法（输出进版控，自制内容，不是原作素材）：
--   Tools\lua\lua.exe Tools\make_uv_check_texture.lua [输出.png] [边长]
-- 预设 Tools\testdata\uv_check_512.png，512×512。
local image = require "ok.image"

local out = arg[1] or "Tools/testdata/uv_check_512.png"
local size = tonumber(arg[2] or "512")
assert(size >= 128 and size % 64 == 0, "边长要是 64 的倍数且至少 128")

local CELL = size // 8          -- 8×8 格
local CORNER = size // 8        -- 四角色块
local BORDER = math.max(2, size // 128)

-- 刻意选高对比且互不相近的颜色：拍出来缩小、或经过卡片的色彩处理之后仍分得开。
local DARK, LIGHT = { 32, 32, 32 }, { 232, 232, 232 }
local CORNERS = {
  tl = { 220, 30, 30 },   -- 左上 红
  tr = { 30, 190, 60 },   -- 右上 绿
  bl = { 40, 90, 230 },   -- 左下 蓝
  br = { 240, 210, 40 },  -- 右下 黄
}
local BORDER_RGB = { 0, 200, 210 }   -- 青
local GLYPH = { 230, 40, 210 }       -- 洋红

local img = image.new(size, size, "RGB", DARK)
local function fill(x0, y0, x1, y1, rgb)
  for y = math.max(0, y0), math.min(size - 1, y1) do
    for x = math.max(0, x0), math.min(size - 1, x1) do img:set(x, y, rgb[1], rgb[2], rgb[3]) end
  end
end

-- 棋盘格
for cy = 0, 7 do
  for cx = 0, 7 do
    if (cx + cy) % 2 == 0 then fill(cx * CELL, cy * CELL, (cx + 1) * CELL - 1, (cy + 1) * CELL - 1, LIGHT) end
  end
end

-- 四角：各一块，颜色都不同，所以哪一角跑到哪里都看得出来
fill(0, 0, CORNER - 1, CORNER - 1, CORNERS.tl)
fill(size - CORNER, 0, size - 1, CORNER - 1, CORNERS.tr)
fill(0, size - CORNER, CORNER - 1, size - 1, CORNERS.bl)
fill(size - CORNER, size - CORNER, size - 1, size - 1, CORNERS.br)

-- 中央的「F」：三个矩形。两个轴都不对称 —— 水平翻会变成镜像 F，垂直翻会让两横跑到下面，
-- 转 90° 会让竖笔变横。所以一张图就分得出「贴反了」的三种情形。
-- 座标全部取整：`img:set` 要整数，给它小数会什么都不画**而且不报错**（第一版的中横就这样整条不见，
-- 图印出来像个「Γ」—— 正是这张图要抓的那种「看起来差不多，其实错了」）。
do
  local w, h = size * 3 // 10, size * 46 // 100         -- 字的外框
  local x0, y0 = (size - w) // 2, (size - h) // 2
  local stroke = math.max(4, size // 32)
  fill(x0, y0, x0 + stroke - 1, y0 + h - 1, GLYPH)                       -- 竖笔
  fill(x0, y0, x0 + w - 1, y0 + stroke - 1, GLYPH)                       -- 上横
  local mid = y0 + h * 46 // 100
  fill(x0, mid, x0 + w * 72 // 100, mid + stroke - 1, GLYPH)             -- 中横（比上横短）
end

-- 外框一圈：取样超出 0..1 时第一个不见的就是它
fill(0, 0, size - 1, BORDER - 1, BORDER_RGB)
fill(0, size - BORDER, size - 1, size - 1, BORDER_RGB)
fill(0, 0, BORDER - 1, size - 1, BORDER_RGB)
fill(size - BORDER, 0, size - 1, size - 1, BORDER_RGB)

local dir = out:match("^(.*)[/\\][^/\\]+$")
if dir then require("ok.path").mkdir(dir) end
img:save(out)
print(("wrote %s (%dx%d, cell %d, corner %d, border %d)"):format(out, size, size, CELL, CORNER, BORDER))
