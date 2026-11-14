-- The player's settings file: Saved/StreetSocial/player.json (a sandbox has its own). One file holds what belongs to
-- the player rather than to a game (Docs/API_KEYS.md):
--   locale, render_style, appearance_base         (as before, read by the game)
--   voice    {voice_mode: builtin|tts|cloud|off, tts_age, male_tone, tts_base_size, player_name, ...}
--   asr      {mode: local|cloud, device, endpoint}
--   deepseek {api_key, endpoint, model}           free talk and the heroines' mind; no key: built-in choices only
--   aliyun   {api_key, base_url, tts_model, asr_model}   cloud voices and voice input; no key: no cloud
-- The older files (voice-settings.json, asr-settings.json, deepseek.json, %LOCALAPPDATA%\OpenKoikatsu\api-keys.json)
-- are read once into it.
--
--   local settings = require "street_player_settings"
--   local file, notes = settings.migrate(dir)     -- dir/player.json, made or completed from the older files
--   settings.template()                            -- a new player's file: no keys
local ok = require "ok"
local json, path = ok.json, ok.path

local M = {}

M.DEEPSEEK_ENDPOINT = "https://api.deepseek.com/chat/completions"
M.DEEPSEEK_MODEL = "deepseek-v4-flash"
M.ALIYUN_BASE_URL = "https://dashscope.aliyuncs.com"
M.ALIYUN_TTS_MODEL = "qwen-audio-3.1-tts-flash"
M.ALIYUN_ASR_MODEL = "qwen3-asr-flash"

local function read(p)
  if not path.is_file(p) then return nil end
  local okj, v = pcall(function() return json.decode((path.read_text(p):gsub("^\239\187\191", ""))) end)
  return okj and json.is_object(v) and v or nil
end

local function str(v) return type(v) == "string" and v or "" end

-- The two key sections, with every field present (an empty key: that service is off).
local function complete(player)
  local d = json.is_object(player.deepseek) and player.deepseek or json.object()
  if d.api_key == nil then d.api_key = "" end
  if d.endpoint == nil then d.endpoint = M.DEEPSEEK_ENDPOINT end
  if d.model == nil then d.model = M.DEEPSEEK_MODEL end
  player.deepseek = d
  local a = json.is_object(player.aliyun) and player.aliyun or json.object()
  if a.api_key == nil then a.api_key = "" end
  if a.base_url == nil then a.base_url = M.ALIYUN_BASE_URL end
  if a.tts_model == nil then a.tts_model = M.ALIYUN_TTS_MODEL end
  if a.asr_model == nil then a.asr_model = M.ALIYUN_ASR_MODEL end
  player.aliyun = a
  return player
end

-- A new player's file: built-in voices, local voice input, no keys.
function M.template()
  local p = json.object()
  p.voice = json.object({ { "voice_mode", "builtin" } })
  p.asr = json.object({ { "mode", "local" } })
  return complete(p)
end

function M.encode(player)
  return json.encode(player, { indent = 2, ensure_ascii = false }) .. "\n"
end

-- dir/player.json made from, or completed with, the older settings files. Files in dir that were read are renamed
-- *.migrated (nothing reads them any more); the shared copies under %LOCALAPPDATA%\OpenKoikatsu are left for the
-- other checkouts, except api-keys.json (only this version wrote it), which goes once its keys are in.
-- opts.shared = false (a package): the shared copies under %LOCALAPPDATA%\OpenKoikatsu are not read, so no key comes in.
function M.migrate(dir, opts)
  local file = path.join(dir, "player.json")
  local player = read(file) or json.object()
  local notes, used = {}, {}
  local shared = not (opts and opts.shared == false)
  local user = shared and os.getenv("LOCALAPPDATA") and path.join(os.getenv("LOCALAPPDATA"), "OpenKoikatsu") or nil

  local vs = read(path.join(dir, "voice-settings.json"))
  if vs then
    if not json.is_object(player.voice) then player.voice = vs; notes[#notes + 1] = "voice settings" end
    used[#used + 1] = path.join(dir, "voice-settings.json")
  end
  if not json.is_object(player.voice) then player.voice = json.object({ { "voice_mode", "builtin" } }) end

  local as = read(path.join(dir, "asr-settings.json"))
  if as then
    if not json.is_object(player.asr) then
      local a = json.object({ { "mode", "local" } })
      if str(as.device) ~= "" then a.device = as.device end
      if str(as.endpoint) ~= "" then a.endpoint = as.endpoint end
      player.asr = a; notes[#notes + 1] = "microphone"
    end
    used[#used + 1] = path.join(dir, "asr-settings.json")
  end
  if not json.is_object(player.asr) then player.asr = json.object({ { "mode", "local" } }) end

  -- DeepSeek: this folder's deepseek.json, else the user's shared copy.
  local have_deepseek = json.is_object(player.deepseek) and str(player.deepseek.api_key) ~= ""
  for _, p in ipairs({ path.join(dir, "deepseek.json"), user and path.join(user, "deepseek.json") or "" }) do
    local d = p ~= "" and read(p)
    if d then
      if not have_deepseek and str(d.api_key) ~= "" then
        player.deepseek = json.object({ { "api_key", d.api_key }, { "endpoint", str(d.endpoint) ~= "" and d.endpoint or M.DEEPSEEK_ENDPOINT },
          { "model", str(d.model) ~= "" and d.model or M.DEEPSEEK_MODEL } })
        have_deepseek = true; notes[#notes + 1] = "DeepSeek key"
      end
      if p == path.join(dir, "deepseek.json") then used[#used + 1] = p end
    end
  end

  -- The short-lived %LOCALAPPDATA%\OpenKoikatsu\api-keys.json.
  local keys_file = user and path.join(user, "api-keys.json")
  local keys = keys_file and read(keys_file)
  if keys then
    for _, name in ipairs({ "deepseek", "aliyun" }) do
      local from = keys[name]
      local have = json.is_object(player[name]) and str(player[name].api_key) ~= ""
      if json.is_object(from) and str(from.api_key) ~= "" and not have then player[name] = from; notes[#notes + 1] = name .. " key" end
    end
  end

  complete(player)
  path.mkdir(dir, true)
  path.write_text(file, M.encode(player), { newline = "\n" })
  for _, p in ipairs(used) do pcall(os.rename, p, p .. ".migrated") end
  if keys then pcall(os.remove, keys_file) end
  return file, notes
end

-- The settings as the launcher needs them (never fails: an unreadable file is a new player's).
function M.read(file)
  return complete(read(file) or M.template())
end

return M
