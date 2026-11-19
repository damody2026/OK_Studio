-- Machine-wide Unreal slots shared by every agent and checkout (C:, E:, F:): at most two Unreal processes at once.
-- slotN\owner.txt names who holds a slot (first word = agent), queue\<agent>.txt says who is waiting.
--
--   Tools\lua\lua.exe Tools\unreal_slot.lua claim <agent> "<what for>" [--wait] [--need-gb N] [--lane <name>]
--                                                                      take a free slot, else stay queued (exit 2)
--   Tools\lua\lua.exe Tools\unreal_slot.lua release <agent>                       give back the agent's slots and queue entry
--   Tools\lua\lua.exe Tools\unreal_slot.lua yield <agent>                         exit 3 when someone of higher priority waits
--   Tools\lua\lua.exe Tools\unreal_slot.lua status
--
-- claim only succeeds when no agent of higher priority is queued, a slot is free, fewer than two Unreal processes of
-- slot holders run (those started since the earliest current claim; an older one, e.g. the user's own game, does not
-- count here), fewer than three run in all, and enough commit is free (default 35 GB, --need-gb N, plus 25 GB left
-- over); --need-gb 60 or more also needs every other slot free and keeps the others closed while held. Checks and the
-- write run under a machine-wide lock (ROOT\claim.lock) so two claims never both pass. It re-reads owner.txt after writing (another agent may have written the same slot) and leaves the queue in the
-- same step, so a stale queue file never makes a lower-priority agent wait for someone who already runs.
-- A queue entry stops counting once its claim --wait process has ended (pid + start time in the entry) or it was not
-- refreshed for 15 minutes (claim --wait refreshes it every poll; a one-shot claim on every call). Ranks match the
-- longest listed name that is the agent or a "-" prefix of it (f-yvonne-q1 ranks as f-yvonne).
local ok = require "ok"
local path, proc = ok.path, ok.proc

local ROOT = os.getenv("OK_UNREAL_SLOTS") or "C:/portable/OpenKoikatsu/Saved/UnrealSlots"
-- Slot arbitration runs only from the C checkout's copy: E:/F: carry their own copies of this script, and an older copy
-- does not take the claim lock or know the lending rules (2026-11-18: E/F claims stayed blocked by rules they lacked).
local ARBITER = "C:/portable/OpenKoikatsu/Tools/unreal_slot.lua"
local SELF = path.abs(arg[0] or "")
-- The lane (-OKLane / ok-game-mcp's `lane`) the holder launches its Unreal under, recorded as " [lane=<name>]" on the
-- owner line by `claim --lane`. ok-game-mcp's launch guard compares the caller's lane with it, so the agent that holds
-- the slot can start its own game while everyone else is refused: without it the guard could only infer exclusivity
-- from "one agent holds two slots" and so refused the measurer itself (2026-11-19).
local LANE
if not os.getenv("OK_UNREAL_SLOTS") and SELF:lower() ~= ARBITER:lower() then
  io.stderr:write("warning: slots are arbitrated by " .. ARBITER .. "; this copy (" .. SELF .. ") may be out of date. Run:\n"
    .. "  C:\\portable\\OpenKoikatsu\\Tools\\lua\\lua.exe C:\\portable\\OpenKoikatsu\\Tools\\unreal_slot.lua " .. table.concat(arg, " ") .. "\n")
end
local SLOTS = 2
-- claim also waits until this much commit is free; pass --need-gb 105 before opening the editor on UniversityCityWP.
local DEFAULT_NEED_GB = 35
-- A claim needing this much or more (the WP editor) takes the whole machine: it waits until no other slot is held, and
-- while it holds its slot nobody else gets one (2026-11-10: a game claimed beside the 56 GB editor, free commit fell to 7 GB).
local EXCLUSIVE_GB = 60
-- Unreal processes on the whole machine: the two slots plus one game the user runs themselves (the user's rule).
local MAX_UNREAL = SLOTS + 1
-- A new slot also leaves this much commit free beyond its --need-gb (2026-11-16: free commit fell to 11 GB);
-- exclusive claims (>= EXCLUSIVE_GB) run alone and check --need-gb only.
local RESERVE_GB = 25
-- f-sceneload ranks first since 2026-11-18: the user named 開場景卡片優化 the top-priority line, and at rank 9 it sat behind four agents.
-- Lower runs first; agents not listed rank after these.
local PRIORITY = { ["f-sceneload"] = -20, ["e-cardload"] = -25, ["f-yvonne"] = -11, ["c-lowspec"] = -9, ["e-120fps"] = -5, ["e-120fps-quiet"] = -5, ["f-cover"] = -3, ["c-street-city"] = -1, ["c-conquest"] = 0, FStyle = 1, ["e-galgame"] = 2, ["e-fork"] = 2, ["e-fork-2"] = -24, F = 3, ["e-okcard"] = 4 }

-- Agent names carry suffixes (f-yvonne-q1, e-fork-2): the longest listed name that equals the agent or is a "-"
-- prefix of it gives the rank, so f-yvonne-q1 ranks as f-yvonne (2026-11-16: exact lookup left it at 9, behind e-120fps).
local function rank(agent)
  local best, len = nil, -1
  for name, r in pairs(PRIORITY) do
    if (agent == name or agent:sub(1, #name + 1) == name .. "-") and #name > len then best, len = r, #name end
  end
  return best or 9
end
-- A queue entry counts only while its waiter lives: claim --wait writes its process (pid + start time) and refreshes the
-- timestamp on every poll; an entry whose process is gone, or not refreshed for this long, no longer blocks anyone
-- (2026-11-16: a dead e-120fps entry kept both slots empty for half an hour with five agents waiting).
local QUEUE_STALE_MIN = 15
-- A test run holds a slot for at most this long: past it, whoever is queued gets the machine (2026-11-15, the user's rule).
local MAX_HOLD_MIN = 20
local function owner_file(i) return path.join(ROOT, "slot" .. i, "owner.txt") end
local function queue_file(agent) return path.join(ROOT, "queue", agent .. ".txt") end
local function now() return os.date("%Y-%m-%d %H:%M:%S") end

local function owner(i)
  local f = owner_file(i)
  if not path.is_file(f) then return nil end
  local text = path.read_text(f) or ""
  return text:match("^%s*(%S+)"), text
end

-- Unreal processes on the machine (editor, commandlet, packaged game, city build); the launcher stub at a stage root
-- (…\Windows\OpenKoikatsu.exe) only starts the real one and is not counted.
-- Returns the start times ("yyyyMMddHHmmss") of those processes.
local function unreal_starts()
  local out = proc.output({ "powershell", "-NoProfile", "-Command",
    "Get-CimInstance Win32_Process | ?{$_.Name -match '^(UnrealEditor(-Cmd)?|OpenKoikatsu|StreetSocialCity(-Cmd)?)\\.exe$'} | " ..
    "%{ $_.CreationDate.ToString('yyyyMMddHHmmss') + ' ' + $_.ExecutablePath }" }) or ""
  local list = {}
  for start, exe in out:gmatch("(%d+) ([^\r\n]+)") do
    if not exe:lower():match("\\windows\\[^\\]+%.exe$") then list[#list + 1] = start end
  end
  return list
end

-- Unreal (and Unreal Insights) processes whose CPU time moves over two seconds: "pid exe (+N ms CPU)". Whether a
-- process is alive is judged by its CPU time, not by HasExited, tasklist or memory (2026-11-18: an UnrealEditor-Cmd whose
-- slot was released kept one core busy through an exclusive measurement; an Insights analysis did the same to the next).
local function busy_unreal()
  local out = proc.output({ "powershell", "-NoProfile", "-Command",
    "$f = { Get-CimInstance Win32_Process | ?{$_.Name -match '^(UnrealEditor(-Cmd)?|OpenKoikatsu|StreetSocialCity(-Cmd)?|UnrealInsights)\\.exe$'} }; " ..
    "$a = @{}; & $f | %{ $a[$_.ProcessId] = $_.KernelModeTime + $_.UserModeTime }; Start-Sleep -Seconds 2; " ..
    "& $f | %{ $d = ($_.KernelModeTime + $_.UserModeTime) - $a[$_.ProcessId]; " ..
    "if ($a.ContainsKey($_.ProcessId) -and $d -gt 0 -and -not ($_.ExecutablePath -match '\\\\Windows\\\\[^\\\\]+\\.exe$')) { '' + $_.ProcessId + ' ' + [int]($d / 10000) + ' ' + $_.ExecutablePath } }" },
    { check = false }) or ""
  local list = {}
  for pid, ms, exe in out:gmatch("(%d+) (%d+) ([^\r\n]+)") do list[#list + 1] = pid .. " " .. exe .. " (+" .. ms .. " ms CPU in 2 s)" end
  return list
end

-- Free commit (RAM + page file) in GB. An editor with the university city WP map commits about 97 GB and the game
-- about 27 GB, so two of them can exhaust the machine even under the process cap (2026-11-08 05:17).
local function free_commit_gb()
  local out = proc.output({ "powershell", "-NoProfile", "-Command",
    "[int]((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory/1MB)" }) or ""
  return tonumber(out:match("%d+")) or 0
end

-- Minutes since a "YYYY-MM-DD HH:MM:SS" stamp found in text (the last one on its first line), or nil.
local function age_min(text)
  local line = (text or ""):match("^[^\n]*") or ""
  -- owner lines may end in " [need N]" / " [until=T]" after the stamp
  repeat local n; line, n = line:gsub("%s*%b[]%s*$", "") until n == 0
  local y, mo, d, h, mi, se = line:match("(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)%s*$")
  if not y then return nil end
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                      hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) })
  return math.floor(os.difftime(os.time(), t) / 60)
end

-- Processes on the machine as { [pid] = start "yyyyMMddHHmmss" } (one query per check).
local function processes()
  local out = proc.output({ "powershell", "-NoProfile", "-Command",
    "Get-CimInstance Win32_Process | %{ '' + $_.ProcessId + ' ' + $_.CreationDate.ToString('yyyyMMddHHmmss') }" }, { check = false }) or ""
  local list = {}
  for pid, start in out:gmatch("(%d+) (%d+)") do list[tonumber(pid)] = start end
  return list
end

-- This Lua process (the parent of the PowerShell it starts): "pid start".
local function self_process()
  local out = proc.output({ "powershell", "-NoProfile", "-Command",
    "$me = Get-CimInstance Win32_Process -Filter \"ProcessId=$PID\"; " ..
    "$p = Get-CimInstance Win32_Process -Filter \"ProcessId=$($me.ParentProcessId)\"; " ..
    "'' + $p.ProcessId + ' ' + $p.CreationDate.ToString('yyyyMMddHHmmss')" }, { check = false }) or ""
  return out:match("(%d+ %d+)")
end

-- Why a queue entry no longer counts, or nil while it does: its waiter's process is gone (an entry from claim --wait
-- names it), or the entry was not refreshed for QUEUE_STALE_MIN minutes (no timestamp at all counts as stale).
local function queue_dead(text, procs)
  local pid, start = (text or ""):match("\npid (%d+) (%d+)")
  if pid then
    procs = procs or processes()
    if procs[tonumber(pid)] ~= start then return "process " .. pid .. " ended" end
  end
  local age = age_min(text)
  if not age then return "no timestamp" end
  if age >= QUEUE_STALE_MIN then return "not refreshed for " .. age .. " min" end
end

-- Agents queued and still waiting, in file order. Entries of ended processes are removed (nobody will come back for
-- them); entries that only aged out are skipped but kept, so status can show them.
local function queued(all)
  local list = {}
  local dir = path.join(ROOT, "queue")
  if not path.is_dir(dir) then return list end
  local procs
  for _, n in ipairs(path.list(dir)) do
    local agent = n:match("^(.-)%.txt$")
    if agent then
      local okr, text = pcall(path.read_text, queue_file(agent))
      text = okr and text or ""
      if not procs and text:match("\npid %d+") then procs = processes() end
      local dead = queue_dead(text, procs)
      if dead and dead:match("^process") then pcall(path.remove, queue_file(agent)) end
      if all then list[#list + 1] = dead and (agent .. " (stale: " .. dead .. ")") or agent
      elseif not dead then list[#list + 1] = agent end
    end
  end
  return list
end

-- Minutes the slot has been held, from the timestamp claim wrote at the end of owner.txt.
local function held_min(i)
  local _, text = owner(i)
  if not text then return nil end
  return age_min(text)
end

-- The longest any of this agent's slots has been held.
local function held_min_agent(agent)
  local held
  for i = 1, SLOTS do
    if owner(i) == agent then
      local m = held_min(i)
      if m and (not held or m > held) then held = m end
    end
  end
  return held
end

-- Unreal processes split into { held = started since the earliest current slot claim (a slot holder's instance),
-- other = started before every current claim (the user's own game, or one left over from a released slot) }.
-- Slot holders launch after they claim, so a process older than every claim cannot be theirs (2026-11-16: the
-- user's game counted against the two slots and kept slot2 empty all evening with 70 GB free).
local function unreal_counts()
  local first
  for i = 1, SLOTS do
    local who, text = owner(i)
    if who then
      local y, mo, d, h, mi, se = (text:match("^[^\n]*") or ""):match(".*(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
      -- a held slot without a readable claim time: treat every process as possibly its own
      local stamp = y and (y .. mo .. d .. h .. mi .. se) or "0"
      if not first or stamp < first then first = stamp end
    end
  end
  local held, other = 0, 0
  for _, start in ipairs(unreal_starts()) do
    if first and start >= first then held = held + 1 else other = other + 1 end
  end
  return held, other
end

-- GB a queued agent asked for ("need N" line of its queue entry; entries without one are ordinary claims).
local function queued_need(agent)
  local okr, text = pcall(path.read_text, queue_file(agent))
  return okr and tonumber((text or ""):match("\nneed (%d+)")) or 0
end

-- Waiting too long lifts an agent above everyone who has not: its rank drops by STARVE_BOOST, more than the whole
-- spread of PRIORITY, so higher-ranked agents taking turns can no longer keep it out (2026-11-18: c-lowspec waited
-- 40 min twice while f-sceneload, e-cardload and f-yvonne alternated). Agents lifted at the same time keep their
-- order between themselves.
local STARVE_MIN = 20
local STARVE_BOOST = 40
local function queued_since(agent)
  local okr, text = pcall(path.read_text, queue_file(agent))
  return okr and tonumber((text or ""):match("\nsince (%d+)")) or nil
end
local function erank(agent)
  local since = queued_since(agent)
  if since and os.time() - since >= STARVE_MIN * 60 then return rank(agent) - STARVE_BOOST end
  return rank(agent)
end
-- The higher-priority agents still waiting, as { {agent, need_gb}... }.
local function waiting_above_all(agent)
  local list = {}
  for _, other in ipairs(queued()) do
    if other ~= agent and erank(other) < erank(agent) then list[#list + 1] = { other, queued_need(other) } end
  end
  return list
end

local function waiting_above(agent)
  local first = waiting_above_all(agent)[1]
  return first and first[1]
end

-- os.time() of the last "YYYY-MM-DD HH:MM:SS" stamp on a line, or nil.
local function stamp_time(line)
  local y, mo, d, h, mi, se = (line or ""):match(".*(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
  if not y then return nil end
  return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) })
end

-- When the slots other agents hold must be back: claim time + MAX_HOLD_MIN, or the [until=] of a lent slot; the latest
-- of them (an exclusive waiter starts only when all are back), or nil when nobody else holds a slot.
local function holders_back(agent)
  local latest
  for i = 1, SLOTS do
    local who, text = owner(i)
    if who and who ~= agent then
      local line = text:match("^[^\n]*") or ""
      local t = tonumber(line:match("%[until=(%d+)%]")) or ((stamp_time(line) or os.time()) + MAX_HOLD_MIN * 60)
      if not latest or t > latest then latest = t end
    end
  end
  return latest
end

-- A lent slot shorter than this is not worth starting Unreal for.
local MIN_LEND_MIN = 5

-- Writes (or refreshes) the agent's queue entry. With `me` ("pid start", claim --wait) the entry lives as long as
-- that process; without it (a one-shot claim that the agent repeats) it lives QUEUE_STALE_MIN minutes per call.
-- An exclusive claim records its need ("need N"): while it waits, a free slot can still be lent (see try_claim_locked).
local function enqueue(agent, note, me, need_gb)
  path.mkdir(path.join(ROOT, "queue"), true)
  -- "since <epoch>" survives every refresh: the first line's stamp is rewritten on each poll, so only this can say
  -- how long an agent has really been queued. starved() uses it to lift an agent that others keep preempting
  -- (2026-11-18: c-lowspec waited 40 min twice while higher-ranked agents took turns).
  local okr, old = pcall(path.read_text, queue_file(agent))
  local since = okr and (old or ""):match("\nsince (%d+)") or nil
  path.write_text(queue_file(agent), agent .. " " .. note .. " " .. now() .. "\n" .. (me and ("pid " .. me .. "\n") or "")
    .. ((need_gb or 0) >= EXCLUSIVE_GB and ("need " .. need_gb .. "\n") or "")
    .. ("since " .. (since or os.time()) .. "\n"))
end

-- Test hook, honoured only with OK_UNREAL_SLOTS set (a scratch slot folder): OK_UNREAL_SLOTS_FAKE="free=<GB> pause=<s>"
-- skips the machine probes (no Unreal processes, that much commit free) and sleeps before writing owner.txt, so a test
-- can line two claims up inside the check-then-write window.
local FAKE = os.getenv("OK_UNREAL_SLOTS") and os.getenv("OK_UNREAL_SLOTS_FAKE") or nil
if FAKE then
  local free, pause = tonumber(FAKE:match("free=(%d+)")) or 200, tonumber(FAKE:match("pause=([%d.]+)")) or 0
  local busy = FAKE:match("busy=(%d+)")
  unreal_starts = function() return {} end
  free_commit_gb = function() return free end
  busy_unreal = function() return busy and { busy .. " X:/Fake/UnrealEditor-Cmd.exe (+500 ms CPU in 2 s)" } or {} end
  FAKE = { pause = pause }
end

-- Every claim checks and writes under one machine-wide lock (a folder: mkdir either creates it or fails), so two claims
-- cannot both pass the checks and then both write (2026-11-18 05:52: c-lowspec's [need 60] claim took slot1 and
-- f-yvonne-low took slot2 one second later). A lock older than LOCK_STALE_S is from a claim that died and is broken.
local LOCK_STALE_S = 120
local function with_lock(fn)
  local lfs = require "lfs"
  local dir = path.join(ROOT, "claim.lock")
  path.mkdir(ROOT, true)
  local deadline = os.time() + LOCK_STALE_S + 30
  while not lfs.mkdir(dir) do
    local m = lfs.attributes(dir, "modification")
    if m and os.difftime(os.time(), m) > LOCK_STALE_S then lfs.rmdir(dir)
    elseif os.time() > deadline then return nil, "claim lock " .. dir .. " stays taken"
    else ok.time.sleep(0.2) end
  end
  local res = table.pack(pcall(fn))
  lfs.rmdir(dir)
  if not res[1] then error(res[2], 0) end
  return table.unpack(res, 2, res.n)
end

-- Another holder conflicts with this claim: one of the two takes the whole machine.
local function exclusive_conflict(agent, need_gb, skip)
  for i = 1, SLOTS do
    local who, text = owner(i)
    if i ~= skip and who and who ~= agent then
      local held = tonumber((text or ""):match("%[need (%d+)%]")) or 0
      if held >= EXCLUSIVE_GB then return who .. " holds the whole machine (" .. held .. " GB)" end
      if need_gb >= EXCLUSIVE_GB then return who .. " holds slot" .. i .. "; " .. need_gb .. " GB needs every slot free" end
    end
  end
end

-- One attempt: the slot index taken (or already held), or nil and why not.
local function try_claim_locked(agent, note, need_gb)
  for i = 1, SLOTS do if owner(i) == agent then return i end end
  -- A higher-priority waiter blocks this claim. An exclusive waiter only blocks it when lending would delay it: it
  -- starts once every held slot is back, so a free slot is lent until the latest of those returns ([until=], enforced
  -- by yield); with no slot held it gets the machine next (2026-11-18: a queued [need 60] kept slot2 empty for 14 min).
  local lend_until
  for _, w in ipairs(waiting_above_all(agent)) do
    if w[2] < EXCLUSIVE_GB or need_gb >= EXCLUSIVE_GB then return nil, w[1] .. " has higher priority and is waiting" end
    local back = holders_back(agent)
    if not back then return nil, w[1] .. " (exclusive) has higher priority and gets the free machine next" end
    if back - os.time() < MIN_LEND_MIN * 60 then
      return nil, w[1] .. " (exclusive) is waiting; the held slots are back in " .. math.max(0, math.floor((back - os.time()) / 60)) .. " min, too short to lend"
    end
    lend_until = back
  end
  local conflict = exclusive_conflict(agent, need_gb)
  if conflict then return nil, conflict end
  local held, other = unreal_counts()
  if held >= SLOTS then return nil, held .. " Unreal processes of slot holders already run" end
  if held + other >= MAX_UNREAL then
    return nil, (held + other) .. " Unreal processes run (" .. other .. " not a slot holder's); the machine allows " .. MAX_UNREAL
  end
  local free = free_commit_gb()
  if free < need_gb then return nil, "only " .. free .. " GB commit free, need " .. need_gb end
  if need_gb < EXCLUSIVE_GB and free - need_gb < RESERVE_GB then
    return nil, "only " .. free .. " GB commit free, need " .. need_gb .. " + " .. RESERVE_GB .. " left over"
  end
  -- An exclusive claim is for measuring on a quiet machine: nobody else's Unreal or Insights may still be running,
  -- even one whose slot was released (no slot holders can exist here, so every busy one is a leftover or the user's).
  if need_gb >= EXCLUSIVE_GB then
    local busy = busy_unreal()
    if #busy > 0 then return nil, "the machine is not quiet; still running: " .. table.concat(busy, "; ") end
  end
  if FAKE and FAKE.pause > 0 then ok.time.sleep(FAKE.pause) end
  for i = 1, SLOTS do
    if not owner(i) then
      path.mkdir(path.parent(owner_file(i)), true)
      path.write_text(owner_file(i), agent .. " " .. note .. " " .. now() .. (need_gb >= EXCLUSIVE_GB and (" [need " .. need_gb .. "]") or "")
        .. (lend_until and (" [until=" .. lend_until .. "]") or "") .. (LANE and (" [lane=" .. LANE .. "]") or "") .. "\n")
      if owner(i) == agent then
        -- A claim made by an older copy of this script (another checkout) does not take the lock: if one landed
        -- meanwhile and the two conflict, give the slot back and try again later.
        local late = exclusive_conflict(agent, need_gb, i)
        if not late then return i end
        path.write_text(owner_file(i), "")
        return nil, late
      end
    end
  end
  return nil, "no free slot"
end

local function try_claim(agent, note, need_gb)
  return with_lock(function() return try_claim_locked(agent, note, need_gb) end)
end

local function claim(agent, note, wait, need_gb)
  local me = wait and self_process() or nil
  while true do
    enqueue(agent, note, me, need_gb)
    local i, why = try_claim(agent, note, need_gb)
    if i then
      -- the queue entry may already be gone (another session cleaned the queue); the slot is ours either way
      pcall(path.remove, queue_file(agent))
      local _, text = owner(i)
      local lent = tonumber((text or ""):match("%[until=(%d+)%]"))
      io.write("slot", i, lent and (" (lent: an exclusive claim waits; give it back by " .. os.date("%H:%M", lent) .. ", yield says when)") or "", "\n")
      return 0
    end
    if not wait then io.write("queued: ", why, "\n"); return 2 end
    proc.run({ "cmd", "/c", "ping", "-n", "21", "127.0.0.1" }, { capture = true })
  end
end

local function release(agent)
  local n = 0
  for i = 1, SLOTS do
    if owner(i) == agent then path.write_text(owner_file(i), ""); n = n + 1 end
  end
  if path.is_file(queue_file(agent)) then path.remove(queue_file(agent)) end
  io.write("released ", n, " slot(s)\n")
  return 0
end

-- Builds take no slot, so they used to run straight through someone else's exclusive measurement (2026-11-18 20:25:
-- three trees compiling while c-lowspec was walking a quiet route). Call this before starting ANY build or cook:
-- exit 0 = go ahead, exit 3 = an exclusive measurement holds the machine, wait and ask again.
local function may_build()
  for i = 1, SLOTS do
    local who, text = owner(i)
    local need = who and tonumber((text or ""):match("%[need (%d+)%]"))
    if need and need >= EXCLUSIVE_GB then
      io.write("wait: ", who, " holds slot", i, " exclusively (need ", need, " GB); a build would spoil its measurement\n")
      return 3
    end
  end
  io.write("go\n")
  return 0
end

local function status()
  for i = 1, SLOTS do
    local who, text = owner(i)
    local held = who and held_min(i)
    local tail = ""
    if held then
      tail = held >= MAX_HOLD_MIN and (" [held " .. held .. " min, over the " .. MAX_HOLD_MIN .. " min cap]")
                                   or (" [held " .. held .. " min]")
    end
    print(("slot" .. i .. ": " .. (who and (text:gsub("%s+$", "") .. tail) or "(free)")))
  end
  io.write("queue: ", table.concat(queued(true), ", "), "\n")
  local held, other = unreal_counts()
  io.write("unreal processes: ", held + other, " (slot holders ", held, ", others ", other, ")\n")
  local busy = busy_unreal()
  io.write("using CPU (Unreal / Insights): ", #busy > 0 and table.concat(busy, "; ") or "none", "\n")
  io.write("free commit: ", free_commit_gb(), " GB\n")
  return 0
end

local function main()
  local cmd, agent = arg[1], arg[2]
  local rest, wait, need_gb = {}, false, DEFAULT_NEED_GB
  local i = 3
  while i <= #arg do
    if arg[i] == "--wait" then wait = true
    elseif arg[i] == "--need-gb" then i = i + 1; need_gb = tonumber(arg[i]) or error("--need-gb <GB>", 0)
    elseif arg[i] == "--lane" then i = i + 1
      LANE = (arg[i] or ""):match("^[%w%-_]+$") or error("--lane <name>: letters, digits, - or _", 0)
    else rest[#rest + 1] = arg[i] end
    i = i + 1
  end
  local note = table.concat(rest, " ")
  if agent and not agent:match("^[%w%-_]+$") then error("agent name: letters, digits, - or _", 0) end
  if cmd == "claim" and agent then os.exit(claim(agent, note, wait, need_gb))
  elseif cmd == "release" and agent then os.exit(release(agent))
  elseif cmd == "yield" and agent then
    -- A lent slot goes back at its [until=] even if the exclusive waiter is not yet first in line.
    for i = 1, SLOTS do
      local who, text = owner(i)
      local lent = who == agent and tonumber((text or ""):match("%[until=(%d+)%]"))
      if lent and os.time() >= lent then print("release (slot" .. i .. " was lent until " .. os.date("%H:%M", lent) .. ")"); os.exit(3) end
    end
    -- Exclusive waiters lend free slots (try_claim_locked); a holder yields to them only once its lent time is up.
    local other
    for _, w in ipairs(waiting_above_all(agent)) do
      local mine
      for i = 1, SLOTS do if owner(i) == agent then local _, t = owner(i); mine = mine or (t or ""):match("%[until=%d+%]") end end
      if w[2] < EXCLUSIVE_GB or not mine then other = w[1]; break end
    end
    if other then io.write("yield to ", other, "\n"); os.exit(3) end
    -- No slot is held for more than 20 minutes (2026-11-15, the user's rule): past the cap, give it back,
    -- to whoever is queued if anyone is, otherwise just release and re-claim if more time is needed.
    local held = held_min_agent(agent)
    if held and held >= MAX_HOLD_MIN then
      local first = queued()[1]
      if first and first ~= agent then
        print("yield to " .. first .. " (held " .. held .. " min, cap " .. MAX_HOLD_MIN .. ")")
      else
        print("release (held " .. held .. " min, cap " .. MAX_HOLD_MIN .. ", nobody waiting)")
      end
      os.exit(3)
    end
    io.write("keep\n"); os.exit(0)
  elseif cmd == "may-build" then os.exit(may_build())
  elseif cmd == "status" or not cmd then os.exit(status())
  else error("usage: unreal_slot.lua claim|release|yield <agent> [note] [--wait] | status | may-build", 0) end
end

ok.main(main)
