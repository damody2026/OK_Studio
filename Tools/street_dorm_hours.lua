-- Read-only: how long each heroine is awake and out of his reach at home (ext.day_plan in the saves), 07:00-23:00.
-- A run is consecutive awake blocks at her home (girls_dorm unless her profile says otherwise) that are not a meal (the
-- lounge downstairs, where he can sit with her); sleep ends a run. Prints every heroine-day with its longest run and
-- total, and the blocks of any run over the limit.
--
--   Tools\lua\lua.exe Tools\street_dorm_hours.lua [--limit 180] <save dir or relationships.json> ...
--   e.g. Tools\lua\lua.exe Tools\street_dorm_hours.lua Saved/StreetSocial/Sandbox/play1/Saves
local ok = require "ok"
local json, path = ok.json, ok.path

local function main()
  local limit, files = 180, {}
  local i = 1
  while i <= #arg do
    if arg[i] == "--limit" then limit = tonumber(arg[i + 1]); i = i + 2
    else
      local p = arg[i]
      if path.is_dir(p) and not path.is_file(path.join(p, "relationships.json")) then
        for _, d in ipairs(path.list(p)) do -- a Saves folder: every slot in it
          local f = path.join(p, d, "relationships.json")
          if path.is_file(f) then files[#files + 1] = f end
        end
      else
        if path.is_dir(p) then p = path.join(p, "relationships.json") end
        if path.is_file(p) then files[#files + 1] = p end
      end
      i = i + 1
    end
  end
  if #files == 0 then error("no relationships.json given", 0) end
  local seen, over, worst = {}, 0, 0
  for _, file in ipairs(files) do
    local save = json.decode(path.read_text(file))
    local ext = save.ext
    if type(ext) == "string" then ext = json.decode(ext) end
    local plan = ext and ext.day_plan
    if plan and plan.actors then
      for actor, blocks in pairs(plan.actors) do
        local key = actor .. "|" .. tostring(plan.day)
        if not seen[key] then
          seen[key] = true
          table.sort(blocks, function(a, b) return a.start < b.start end)
          local run, runStart, best, total, runBlocks, bestBlocks = 0, nil, 0, 0, {}, {}
          local function close()
            if run > best then best, bestBlocks = run, runBlocks end
            run, runStart, runBlocks = 0, nil, {}
          end
          for _, b in ipairs(blocks) do
            local s, e = math.max(b.start, 420), math.min(b["end"], 1380)
            local away = b.place == "girls_dorm" and b.kind ~= "sleep" and b.kind ~= "meal"
            if e > s and away then
              if runStart and s > runStart + run then close() end -- a gap: not consecutive
              runStart = runStart or s
              run = run + (e - s); total = total + (e - s)
              runBlocks[#runBlocks + 1] = b
            elseif e > s then close() end
          end
          close()
          worst = math.max(worst, best)
          local flag = best > limit and "  OVER" or ""
          if best > limit then over = over + 1 end
          print(("day %3s %s  longest %5.1f h  total %4.1f h%s  (%s)"):format(tostring(plan.day), actor:sub(1, 14), best / 60, total / 60, flag, path.name(path.parent(file))))
          if best > limit then
            for _, b in ipairs(bestBlocks) do
              print(("      %02d:%02d-%02d:%02d %s %s source=%s job=%s"):format(b.start // 60, b.start % 60, b["end"] // 60, b["end"] % 60, b.kind, b.place, b.source or "", b.job_id or ""))
            end
          end
        end
      end
    end
  end
  print(("%d heroine-days, %d over %d min, longest %.1f h"):format((function() local n = 0 for _ in pairs(seen) do n = n + 1 end return n end)(), over, limit, worst / 60))
  return over == 0 and 0 or 1
end

os.exit(main())
