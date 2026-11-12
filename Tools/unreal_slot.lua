-- Machine-wide Unreal slots shared by every agent and checkout (C:, E:, F:): at most two Unreal processes at once.
-- slotN\owner.txt names who holds a slot (first word = agent), queue\<agent>.txt says who is waiting.
--
--   Tools\lua\lua.exe Tools\unreal_slot.lua claim <agent> "<what for>" [--wait] [--need-gb N]   take a free slot, else stay queued (exit 2)
--   Tools\lua\lua.exe Tools\unreal_slot.lua release <agent>                       give back the agent's slots and queue entry
--   Tools\lua\lua.exe Tools\unreal_slot.lua yield <agent>                         exit 3 when someone of higher priority waits
--   Tools\lua\lua.exe Tools\unreal_slot.lua status
--
-- claim only succeeds when no agent of higher priority is queued, a slot is free, fewer than two Unreal processes
-- run and enough commit is free (default 35 GB, --need-gb N); --need-gb 60 or more also needs every other slot free and keeps the others closed while held. It re-reads owner.txt after writing (another agent may have written the same slot) and leaves the queue in the
-- same step, so a stale queue file never makes a lower-priority agent wait for someone who already runs.
local ok = require "ok"
local path, proc = ok.path, ok.proc

local ROOT = os.getenv("OK_UNREAL_SLOTS") or "C:/portable/OpenKoikatsu/Saved/UnrealSlots"
local SLOTS = 2
-- claim also waits until this much commit is free; pass --need-gb 105 before opening the editor on UniversityCityWP.
local DEFAULT_NEED_GB = 35
-- A claim needing this much or more (the WP editor) takes the whole machine: it waits until no other slot is held, and
-- while it holds its slot nobody else gets one (2026-11-10: a game claimed beside the 56 GB editor, free commit fell to 7 GB).
local EXCLUSIVE_GB = 60
-- Lower runs first; agents not listed rank after these.
local PRIORITY = { ["f-cover"] = -3, ["e-120fps"] = -2, ["c-street-city"] = -1, ["c-conquest"] = 0, FStyle = 1, ["e-galgame"] = 2, ["e-fork"] = 2, ["e-fork-2"] = 2, F = 3, ["e-okcard"] = 4 }

local function rank(agent) return PRIORITY[agent] or 9 end
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
local function unreal_count()
  local out = proc.output({ "powershell", "-NoProfile", "-Command",
    "Get-CimInstance Win32_Process | ?{$_.Name -match '^(UnrealEditor(-Cmd)?|OpenKoikatsu|StreetSocialCity(-Cmd)?)\\.exe$'} | %{$_.ExecutablePath}" }) or ""
  local n = 0
  for line in out:gmatch("[^\r\n]+") do
    if not line:lower():match("\\windows\\[^\\]+%.exe$") then n = n + 1 end
  end
  return n
end

-- Free commit (RAM + page file) in GB. An editor with the university city WP map commits about 97 GB and the game
-- about 27 GB, so two of them can exhaust the machine even under the process cap (2026-11-08 05:17).
local function free_commit_gb()
  local out = proc.output({ "powershell", "-NoProfile", "-Command",
    "[int]((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory/1MB)" }) or ""
  return tonumber(out:match("%d+")) or 0
end

local function queued()
  local list = {}
  local dir = path.join(ROOT, "queue")
  if path.is_dir(dir) then
    for _, n in ipairs(path.list(dir)) do
      local agent = n:match("^(.-)%.txt$")
      if agent then list[#list + 1] = agent end
    end
  end
  return list
end

local function waiting_above(agent)
  for _, other in ipairs(queued()) do
    if other ~= agent and rank(other) < rank(agent) then return other end
  end
end

local function enqueue(agent, note)
  path.mkdir(path.join(ROOT, "queue"), true)
  if not path.is_file(queue_file(agent)) then path.write_text(queue_file(agent), agent .. " " .. note .. " " .. now() .. "\n") end
end

-- One attempt: the slot index taken (or already held), or nil and why not.
local function try_claim(agent, note, need_gb)
  for i = 1, SLOTS do if owner(i) == agent then return i end end
  local blocker = waiting_above(agent)
  if blocker then return nil, blocker .. " has higher priority and is waiting" end
  for i = 1, SLOTS do
    local who, text = owner(i)
    if who and who ~= agent then
      local held = tonumber((text or ""):match("%[need (%d+)%]")) or 0
      if held >= EXCLUSIVE_GB then return nil, who .. " holds the whole machine (" .. held .. " GB)" end
      if need_gb >= EXCLUSIVE_GB then return nil, who .. " holds slot" .. i .. "; " .. need_gb .. " GB needs every slot free" end
    end
  end
  if unreal_count() >= SLOTS then return nil, SLOTS .. " Unreal processes already run" end
  local free = free_commit_gb()
  if free < need_gb then return nil, "only " .. free .. " GB commit free, need " .. need_gb end
  for i = 1, SLOTS do
    if not owner(i) then
      path.mkdir(path.parent(owner_file(i)), true)
      path.write_text(owner_file(i), agent .. " " .. note .. " " .. now() .. (need_gb >= EXCLUSIVE_GB and (" [need " .. need_gb .. "]") or "") .. "\n")
      if owner(i) == agent then return i end
    end
  end
  return nil, "no free slot"
end

local function claim(agent, note, wait, need_gb)
  enqueue(agent, note)
  while true do
    local i, why = try_claim(agent, note, need_gb)
    if i then
      -- the queue entry may already be gone (another session cleaned the queue); the slot is ours either way
      pcall(path.remove, queue_file(agent))
      io.write("slot", i, "\n")
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

local function status()
  for i = 1, SLOTS do
    local who, text = owner(i)
    io.write("slot", i, ": ", who and (text:gsub("%s+$", "")) or "(free)", "\n")
  end
  io.write("queue: ", table.concat(queued(), ", "), "\n")
  io.write("unreal processes: ", unreal_count(), "\n")
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
    else rest[#rest + 1] = arg[i] end
    i = i + 1
  end
  local note = table.concat(rest, " ")
  if agent and not agent:match("^[%w%-_]+$") then error("agent name: letters, digits, - or _", 0) end
  if cmd == "claim" and agent then os.exit(claim(agent, note, wait, need_gb))
  elseif cmd == "release" and agent then os.exit(release(agent))
  elseif cmd == "yield" and agent then
    local other = waiting_above(agent)
    if other then io.write("yield to ", other, "\n"); os.exit(3) end
    io.write("keep\n"); os.exit(0)
  elseif cmd == "status" or not cmd then os.exit(status())
  else error("usage: unreal_slot.lua claim|release|yield <agent> [note] [--wait] | status", 0) end
end

ok.main(main)
