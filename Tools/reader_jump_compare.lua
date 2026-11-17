-- Two reader_jump_check runs of the same cards, view by view: "something that should be there is gone".
--
--   Tools\lua\lua.exe Tools\reader_jump_compare.lua --a REPORT[,REPORT..] --a-images DIR[,DIR..]
--       --b REPORT[,REPORT..] --b-images DIR[,DIR..] --out DIR [--top N] [--block N] [--steps light|all] [--mcp EXE]
--
-- Pairs the still views of both runs (LIGHT lit/flat: the card loaded, before any motion) by card, step and view index,
-- and runs ok-game-mcp image_diff on each: the luma difference in block x
-- block tiles, the worst tile and where it is. A vanished pupil, eye or part is a small tile changing a lot while the
-- whole image barely moves; whole-image checks (black, white, no character) pass it (2026-11-18: with the highlight taken
-- off on a low-memory PC the iris was uploaded empty, the eye went white, and the eye audit said pass).
-- Writes DIR/compare.txt (worst tile first: key, tile, corner, pixels changed by more than 80, whole-image mean, files)
-- and, for the top N (default 40), DIR/NN_<card>_<step>_<view>.png: a | b, 240x240 around that tile, 2x, tile outlined.
-- Look at the crops: a moved hair strand and a missing pupil can score alike; the number only orders them.
-- Each report lists its images by file name; --a-images / --b-images are the folders they were copied to (--images of
-- reader_jump_check), one per report, in the same order.

local args = {}
do
  local i = 1
  while arg[i] do
    local k = arg[i]
    if k:sub(1, 2) ~= "--" or not arg[i + 1] then error("unexpected argument " .. k) end
    args[k:sub(3)] = arg[i + 1]; i = i + 2
  end
end
for _, k in ipairs({ "a", "a-images", "b", "b-images", "out" }) do
  if not args[k] then io.stderr:write("--" .. k .. " is required (see the top of Tools/reader_jump_compare.lua)\n"); os.exit(1) end
end
local mcp = (args.mcp or "Tools/ok-game-mcp/target/release/ok-game-mcp.exe"):gsub("/", "\\") -- (cmd: backslashes)
local top, block = tonumber(args.top or "40"), tonumber(args.block or "24")
-- --steps all also pairs O<n> a. Those are taken while the jump plays and land on another frame each run (11-18: the
-- worst 40 pairs of a low-memory run against 11-16 were all a different pose, tile 200+), so by default only LIGHT.
local all_steps = args.steps == "all"
local out = args.out:gsub("\\", "/")
os.execute(('mkdir "%s" 2>nul'):format(out:gsub("/", "\\")))

local function split(s) local t = {}; for x in s:gmatch("[^,]+") do t[#t + 1] = x:gsub("\\", "/") end return t end

-- key "<card> <step> <view><n>" -> image path, for the standing views
local function views(reports, dirs)
  local r, d, m = split(reports), split(dirs), {}
  assert(#r == #d, "one image folder per report")
  for i = 1, #r do
    for line in io.lines(r[i]) do
      local card, step, rest = line:match("^(%S+) (%S+) (.*)$")
      if card and (step == "LIGHT" or all_steps and step:match("^O%d$")) then
        for key, list in rest:gmatch("(%a+)=([^%s]+)") do
          if key == "lit" or key == "flat" or key == "a" then
            local k = 0
            for name in list:gmatch("[^,]+") do
              if name:match("%.png$") then k = k + 1; m[("%s %s %s%d"):format(card, step, key, k)] = d[i] .. "/" .. name end
            end
          end
        end
      end
    end
  end
  return m
end

local function exists(p) local f = io.open(p, "rb"); if f then f:close() end return f ~= nil end
local function diff(a, b, crop)
  local json = ('{"a":"%s","b":"%s","block":%d%s}'):format(a, b, block, crop and (',"crop":"' .. crop .. '"') or "")
  -- (the whole line in quotes once more: cmd /c drops the first and last quote of a line that starts with one)
  local p = io.popen(('""%s" call image_diff "%s" 2>&1"'):format(mcp, json:gsub('"', '\\"')))
  local t = p:read("a"); p:close()
  local tile = tonumber(t:match('"tile"%s*:%s*([%d.]+)'))
  if not tile then return nil, (t:gsub("%s+", " ")) end
  return { tile = tile, x = tonumber(t:match('"x"%s*:%s*(%d+)')), y = tonumber(t:match('"y"%s*:%s*(%d+)')),
    changed = tonumber(t:match('"changed_px"%s*:%s*(%d+)')), mean = tonumber(t:match('"mean"%s*:%s*([%d.]+)')) }
end

local A, B = views(args.a, args["a-images"]), views(args.b, args["b-images"])
local keys = {}
for k in pairs(B) do if A[k] then keys[#keys + 1] = k end end
table.sort(keys)
local rows, missing, failed = {}, 0, {}
for i, k in ipairs(keys) do
  if exists(A[k]) and exists(B[k]) then
    local r, err = diff(A[k], B[k])
    if r then r.key = k; rows[#rows + 1] = r else failed[#failed + 1] = k .. ": " .. err end
  else missing = missing + 1 end
  if i % 100 == 0 then io.write(("%d/%d\n"):format(i, #keys)); io.flush() end
end
table.sort(rows, function(x, y) return x.tile > y.tile end)
local f = assert(io.open(out .. "/compare.txt", "wb"))
local function say(s) f:write(s, "\n"); print(s) end
say(("pairs %d (views only one side has are not paired; files missing %d, diff failed %d)"):format(#rows, missing, #failed))
for _, l in ipairs(failed) do say("FAILED " .. l) end
for i, r in ipairs(rows) do
  local line = ("%-26s tile %6.1f at (%d,%d)  >80px %7d  mean %5.2f  a=%s b=%s"):format(r.key, r.tile, r.x, r.y, r.changed,
    r.mean, A[r.key]:match("[^/]+$"), B[r.key]:match("[^/]+$"))
  if i <= top then
    local crop = ("%s/%02d_%s.png"):format(out, i, r.key:gsub(" ", "_"))
    diff(A[r.key], B[r.key], crop)
    line = line .. "  crop=" .. crop:match("[^/]+$")
  end
  f:write(line, "\n"); if i <= 15 then print(line) end
end
f:close()
