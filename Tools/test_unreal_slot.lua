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

T:case("test_claim_refused_while_exclusive_held", function(t)
  local root = scratch()
  local code = finish(start(root, "t-exclusive", 60))
  t:eq(code, 0)
  local c2, out = finish(start(root, "t-normal", 35))
  t:eq(c2, 2, "queued, not given slot2: " .. out)
  t:contains(out, "holds the whole machine")
  local c3 = finish(start(root, "t-other-exclusive", 60))
  t:eq(c3, 2)
  t:eq(holders(root), { "t-exclusive" })
  P.rmtree(root)
end)

-- A queue entry / owner line written directly, as another agent's claim would leave them.
local function put(root, rel, text)
  P.mkdir(P.parent(P.join(root, rel)), true)
  P.write_text(P.join(root, rel), text)
end
local function stamp(min_ago) return os.date("%Y-%m-%d %H:%M:%S", os.time() - min_ago * 60) end
local function run(root, ...)
  local args = { ok.lua_exe, script, ... }
  local fs = require "okfs"
  local saved = { os.getenv("OK_UNREAL_SLOTS"), os.getenv("OK_UNREAL_SLOTS_FAKE") }
  fs.setenv("OK_UNREAL_SLOTS", root); fs.setenv("OK_UNREAL_SLOTS_FAKE", "free=200")
  local p = proc.popen(args, { stderr = "stdout", hide = true })
  fs.setenv("OK_UNREAL_SLOTS", saved[1]); fs.setenv("OK_UNREAL_SLOTS_FAKE", saved[2])
  return finish(p)
end
-- c-lowspec-t ranks as c-lowspec (-9), above the t-* agents (9).
local function exclusive_waiting(root) put(root, "queue/c-lowspec-t.txt", "c-lowspec-t test " .. stamp(0) .. "\nneed 60\n") end

T:case("test_queued_exclusive_lends_free_slot_until_holder_is_back", function(t)
  local root = scratch()
  exclusive_waiting(root)
  put(root, "slot1/owner.txt", "t-holder test " .. stamp(5) .. "\n")
  local code, out = run(root, "claim", "t-borrow", "test")
  t:eq(code, 0, out)
  t:contains(out, "lent")
  local line = P.read_text(P.join(root, "slot2", "owner.txt"))
  local back = tonumber(line:match("%[until=(%d+)%]"))
  t:truthy(back, line)
  t:less_eq(math.abs(back - (os.time() + 15 * 60)), 5, "lent until the holder's 20 min are up")
  t:eq((run(root, "yield", "t-borrow")), 0, "keeps the slot before its time")
  put(root, "slot2/owner.txt", (line:gsub("%[until=%d+%]", "[until=" .. (os.time() - 1) .. "]")))
  local yc, yout = run(root, "yield", "t-borrow")
  t:eq(yc, 3, yout)
  t:eq((run(root, "yield", "t-holder")), 3, "an ordinary holder still yields to the exclusive waiter")
  P.rmtree(root)
end)

T:case("test_queued_exclusive_takes_empty_machine", function(t)
  local root = scratch()
  exclusive_waiting(root)
  local code, out = run(root, "claim", "t-normal", "test")
  t:eq(code, 2, out)
  t:contains(out, "free machine next")
  local c2 = run(root, "claim", "c-lowspec-t", "test", "--need-gb", "60")
  t:eq(c2, 0)
  P.rmtree(root)
end)

T:case("test_no_lend_when_holder_nearly_done", function(t)
  local root = scratch()
  exclusive_waiting(root)
  put(root, "slot1/owner.txt", "t-holder test " .. stamp(17) .. "\n")
  local code, out = run(root, "claim", "t-borrow", "test")
  t:eq(code, 2, out)
  t:contains(out, "too short to lend")
  P.rmtree(root)
end)

T:case("test_queued_ordinary_higher_still_blocks", function(t)
  local root = scratch()
  put(root, "queue/c-lowspec-t.txt", "c-lowspec-t test " .. stamp(0) .. "\n")
  put(root, "slot1/owner.txt", "t-holder test " .. stamp(5) .. "\n")
  local code, out = run(root, "claim", "t-borrow", "test")
  t:eq(code, 2, out)
  t:contains(out, "has higher priority")
  P.rmtree(root)
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
