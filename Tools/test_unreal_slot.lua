-- Tools\lua\lua.exe Tools\test_unreal_slot.lua
-- Two claims arriving together, one of them exclusive (--need-gb 60), must not both get a slot (2026-11-18 05:52:
-- c-lowspec's [need 60] claim took slot1 and f-yvonne-low took slot2 a second later). Runs in a scratch slot folder
-- with the machine probes faked (OK_UNREAL_SLOTS_FAKE), and a pause between the checks and the write that would let
-- both claims through without the lock.
local ok = require "ok"
local P, proc = ok.path, ok.proc

local T = ok.test.suite("UnrealSlotTests")
local script = P.join(ok.root, "Tools/unreal_slot.lua")

local function scratch()
  local dir = P.join(ok.root, "Saved/Tests/UnrealSlot", os.date("%Y%m%d%H%M%S") .. "-" .. math.random(100000, 999999))
  P.mkdir(dir, true)
  return dir
end

local function start(root, agent, need_gb)
  local args = { ok.lua_exe, script, "claim", agent, "test", "--need-gb", tostring(need_gb) }
  local saved = { os.getenv("OK_UNREAL_SLOTS"), os.getenv("OK_UNREAL_SLOTS_FAKE") }
  local fs = require "okfs"
  fs.setenv("OK_UNREAL_SLOTS", root); fs.setenv("OK_UNREAL_SLOTS_FAKE", "free=200 pause=1.5")
  local p = proc.popen(args, { stderr = "stdout", hide = true })
  fs.setenv("OK_UNREAL_SLOTS", saved[1]); fs.setenv("OK_UNREAL_SLOTS_FAKE", saved[2])
  return p
end

local function finish(p)
  local out = p:read("a") or ""
  local code = p:wait(60)
  return code, out
end

local function holders(root)
  local list = {}
  for i = 1, 2 do
    local f = P.join(root, "slot" .. i, "owner.txt")
    local who = P.is_file(f) and (P.read_text(f):match("^%s*(%S+)")) or nil
    if who then list[#list + 1] = who end
  end
  return list
end

local function race(t, first, second)
  local root = scratch()
  local a = start(root, first[1], first[2])
  local b = start(root, second[1], second[2])
  local ca, oa = finish(a)
  local cb, ob = finish(b)
  local won = (ca == 0 and 1 or 0) + (cb == 0 and 1 or 0)
  t:eq(won, 1, "exactly one claim succeeds (" .. first[1] .. ": " .. tostring(ca) .. " " .. oa .. " / " .. second[1] .. ": " .. tostring(cb) .. " " .. ob .. ")")
  t:eq(#holders(root), 1, "one slot held")
  t:falsy(P.exists(P.join(root, "claim.lock")), "lock released")
  P.rmtree(root)
end

T:case("test_exclusive_then_normal_only_one_wins", function(t)
  race(t, { "t-exclusive", 60 }, { "t-normal", 35 })
end)

T:case("test_normal_then_exclusive_only_one_wins", function(t)
  race(t, { "t-normal", 35 }, { "t-exclusive", 60 })
end)

T:case("test_two_normal_both_win", function(t)
  local root = scratch()
  local a = start(root, "t-one", 35)
  local b = start(root, "t-two", 35)
  local ca = finish(a)
  local cb = finish(b)
  t:eq(ca, 0); t:eq(cb, 0)
  t:eq(#holders(root), 2)
  P.rmtree(root)
end)

T:run()
