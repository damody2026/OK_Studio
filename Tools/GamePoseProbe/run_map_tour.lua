-- Sky and sea of original Studio maps at each time of day, for the comparison with OK Studio (OK_PROBE_MAP_TOUR).
-- Build Tools/GamePoseProbe/build.lua first. Uses a temporary installed probe; the pictures stay in Saved/Tests/<tag>.
--   Tools\lua\lua.exe Tools\GamePoseProbe\run_map_tour.lua --tag MapTour01 --stops 56:0,56:1,56:2,56:3 [--height 30]
local ok = require "ok"
local fs = require "okfs"
local path = ok.path
local parser = ok.args.parser("Native Studio map sky and sea tour")
parser:opt("--stops", { required = true })
parser:opt("--tag", { required = true })
parser:opt("--height", { default = "30" })
parser:opt("--timeout", { default = "1200" })
parser:flag("--lights-only")
local a = parser:parse(arg)
assert(a.tag:match("^[%w_%-]+$"), "Invalid tag")
assert(a.stops:match("^[%d:,]+$"), "Stops are map:sun,map:sun")
local game = ok.game_root()
local output = path.join(ok.root, "Saved/Tests", a.tag)
assert(not path.exists(output), "Use a fresh tag")
local installed = path.join(game, "BepInEx/plugins/OpenKoikatsu.GamePoseProbe.dll")
assert(not path.exists(installed), "Probe already installed; retain its owner's plugin")
for _, process in ipairs(ok.kit.call({ "proc-list", "CharaStudio.exe" }) or {}) do
    error("Existing Studio process must retain its plugins: " .. tostring(process.pid))
end
path.mkdir(output)
path.copy(path.join(ok.root, "Tools/GamePoseProbe/OpenKoikatsu.GamePoseProbe.dll"), installed)
local owned
local success, err = xpcall(function()
    local prefix = path.join(output, "Tour")
    fs.setenv("OK_PROBE_MAP_TOUR", a.stops)
    fs.setenv("OK_PROBE_TOUR_HEIGHT", a.height)
    fs.setenv("OK_GAME_POSE_OUTPUT", prefix)
    fs.setenv("OK_PROBE_TOUR_LIGHTS_ONLY", a.lights_only and "1" or "")
    owned = ok.proc.popen({ path.join(game, "CharaStudio.exe"), "-windowed", "-screen-width", "1280", "-screen-height", "720" },
        { hide = true, stdout = "NUL", stderr = "NUL" })
    local deadline = ok.time.time() + tonumber(a.timeout)
    while not path.exists(prefix) do
        assert(not owned:poll(), "Native exited before the tour finished")
        assert(ok.time.time() < deadline, "Native map tour timeout")
        ok.time.sleep(1)
    end
    if owned:wait(15) == nil then owned:kill(); owned:wait() end
    owned = nil
    print("Native map tour complete: " .. output)
end, debug.traceback)
if owned and not owned:poll() then owned:kill(); owned:wait() end
if path.exists(installed) then path.rename(installed, path.join(output, "probe.last-run.dll")) end
if not success then error(err) end
