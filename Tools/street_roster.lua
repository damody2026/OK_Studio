-- The street's heroine folder, for the in-game roster menu (Source/OpenKoikatsu/OKStreetSocialRoster.inl).
--
--   street_roster.lua scan --dir <folder> --output <json>
--       Every card in the folder: OK cards as they are; an original KKS card is turned into an OK card first
--       (ok-extract --oklib card, with the game of Config/DefaultGame.ini when it is there), the original kept in KKS/.
--   street_roster.lua import --dir <folder> --output <json> <file>...
--       Copies the files (cards dropped on the game window) into the folder, then scans it.
--   street_roster.lua cast --male <png> --cards <json {"cards":[...]}> --output <json>
--       The selection's cast for those heroines ({"cards","outfits","characters"}), as the launcher's
--       prepare_street_social_selection.lua makes it.
local ok = require "ok"
local json, path, util = ok.json, ok.path, ok.util
package.path = path.join(ok.root, "Tools/?.lua;") .. package.path
local prepare = require "prepare_street_social_selection"

local function win(p) return (path.norm(p):gsub("/+", "/"):gsub("/", "\\")) end
local function read_json(p) return json.decode(path.read_text(p)) end
local function write_json(p, v) path.write_text(p, json.encode(v, { ensure_ascii = false, indent = 2 })) end

-- The PNG chunks of a file (kind -> true), or nil when it is not a PNG.
local function chunks(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local data = f:read("a"); f:close()
  if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
  local kinds, at = {}, 9
  while at + 8 <= #data do
    local len = string.unpack(">I4", data, at)
    local kind = data:sub(at + 4, at + 7)
    kinds[kind] = true
    at = at + 12 + len
    if kind == "IEND" then break end
  end
  return kinds, data:find("KoiKatuChara", at, true) ~= nil
end

-- An OK card carries its resources (okLc) and look (okLb); an original card only the game's trailing data.
local function kind_of(p)
  local kinds, chara = chunks(p)
  if not kinds then return nil end
  if kinds.okLc or kinds.okLb then return "ok" end
  if chara then return "kks" end
  return nil
end

local function game_root()
  local ini = path.join(ok.root, "Config/DefaultGame.ini")
  if path.exists(ini) then
    local root = path.read_text(ini):match("%[/Script/KKSideloader%.KKGameRoot%][^%[]-\nRoot=([^\r\n]+)")
    if root and path.is_dir(root) then return root end
  end
  return "X:/NoGame"
end

-- An original card made into an OK card in place: the original goes to KKS/ beside it.
local function convert(p, log)
  local exe = path.join(ok.root, "Tools/ok-extract/target/release/ok-extract.exe")
  if not path.exists(exe) then log[#log + 1] = { card = win(p), error = "ok-extract.exe missing" }; return false end
  local keep = path.join(path.parent(p), "KKS")
  path.mkdir(keep, true)
  local original = path.join(keep, path.name(p))
  local n = 1
  while path.exists(original) do original = path.join(keep, ("%s-%d.png"):format(path.stem(p), n)); n = n + 1 end
  assert(os.rename(p, original))
  local cmd = ('""%s" "%s" --oklib card "%s" "%s" "%s" 2>&1"'):format(win(exe), game_root(),
    win(path.join(ok.root, "Content/IndependentResources/base_v1")), win(original), win(p))
  local pipe = io.popen(cmd); local out = pipe and pipe:read("a") or ""; if pipe then pipe:close() end
  if not path.exists(p) or kind_of(p) ~= "ok" then
    if path.exists(p) then os.remove(p) end
    os.rename(original, p)
    log[#log + 1] = { card = win(p), error = "conversion failed: " .. (out:sub(-400)) }
    return false
  end
  log[#log + 1] = { card = win(p), converted = true, original = win(original) }
  return true
end

local function scan(dir)
  local overrides = path.join(ok.root, "Content/IndependentResources/StreetSocialData/name_overrides.json")
  local names = path.exists(overrides) and (read_json(overrides).names or {}) or {}
  path.mkdir(dir, true)
  local log, cards = {}, {}
  for _, name in ipairs(path.list(dir)) do
    local p = path.join(dir, name)
    if path.is_file(p) and name:lower():match("%.png$") then
      local kind = kind_of(p)
      if kind == "kks" and convert(p, log) then kind = "ok" end
      if kind == "ok" then
        local ok_c, c = pcall(prepare.character, p)
        if ok_c and names[c.id] then c.name = names[c.id] end
        if ok_c and c.sex == 1 then
          cards[#cards + 1] = json.object({ { "path", win(p) }, { "id", c.id }, { "name", c.name } })
        elseif ok_c then
          log[#log + 1] = { card = win(p), error = "not a female card" }
        else
          log[#log + 1] = { card = win(p), error = tostring(c) }
        end
      end
    end
  end
  table.sort(cards, function(a, b) return a.path:lower() < b.path:lower() end)
  return json.object({ { "dir", win(dir) }, { "cards", cards }, { "log", log } })
end

local function main(argv)
  local command = table.remove(argv, 1)
  local parser = ok.args.parser()
  parser:opt("--dir", { default = "" })
  parser:opt("--output", { required = true })
  parser:opt("--male", { default = "" })
  parser:opt("--cards", { default = "" })
  parser:arg("files", { nargs = "*" })
  local args = parser:parse(argv)
  if command == "scan" or command == "import" then
    local dir = path.abs(args.dir)
    path.mkdir(dir, true)
    for _, f in ipairs(args.files or {}) do
      if path.is_file(f) and f:lower():match("%.png$") then
        local to = path.join(dir, path.name(f))
        if path.abs(f):lower() ~= to:lower() then
          local n = 1
          while path.exists(to) do to = path.join(dir, ("%s-%d.png"):format(path.stem(f), n)); n = n + 1 end
          path.write_bytes(to, path.read_bytes(f))
        end
      end
    end
    write_json(args.output, scan(dir))
  elseif command == "cast" then
    local list = read_json(args.cards)
    local _, _, everyone = prepare.cast(path.abs(args.male), list.cards or list)
    write_json(args.output, json.object({
      { "cards", util.map(everyone, function(c) return c.path end) },
      { "outfits", util.map(everyone, function(c) return c.outfit end) },
      { "characters", everyone },
    }))
  else
    error("usage: street_roster.lua scan|import|cast ...", 0)
  end
end

ok.main(function() main(arg) end)
