-- Compiles the card reader's DreamGUI screens (DUI/Reader/*.dui, listed in DUI/Reader/widgets.json) into their widget
-- Blueprints under Content/UI/Reader with DreamGUI's DreamUICompileWidgets commandlet. Run it after editing a .dui
-- outside the editor; the editor itself recompiles a loaded .dui when its file is saved.
--
--   Tools\lua\lua.exe Tools\build_reader_ui.lua [--engine DIR] [--only WBP_A,WBP_B]
--
-- Needs the editor target built (Build.bat OpenKoikatsuEditor). Fails on any compile error; the log is
-- Saved/DreamGUI/compile-widgets.log.
local ok = require "ok"
local path, proc = ok.path, ok.proc

local function win(p) return (path.norm(p):gsub("/", "\\")) end

local p = ok.args.parser("Compile the card reader's .dui screens")
p:opt("--engine", { default = ok.engine_root() })
p:opt("--only", { default = "" })
local a = p:parse(arg)

local manifest = path.join(ok.root, "DUI/Reader/widgets.json")
local log = path.join(ok.root, "Saved/DreamGUI/compile-widgets.log")
path.mkdir(path.join(ok.root, "Saved/DreamGUI"))
local editor = path.join(path.norm(a.engine), "Engine/Binaries/Win64/UnrealEditor-Cmd.exe")
if not path.is_file(editor) then error("No editor at " .. win(editor), 0) end

local args = { win(editor), win(path.join(ok.root, "OpenKoikatsu.uproject")), "-run=DreamUICompileWidgets",
  "-Manifest=" .. win(manifest), "-unattended", "-nosplash", "-nosound", "-NullRHI", "-abslog=" .. win(log) }
if a.only ~= "" then args[#args + 1] = "-Only=" .. a.only end
local r = proc.run(args, { stdout_file = path.join(ok.root, "Saved/DreamGUI/compile-widgets.stdout.txt"), merge = true })
local text = path.exists(log) and path.read_text(log) or ""
local errors = 0
for line in text:gmatch("[^\r\n]+") do
  if line:find("DUI%d%d%d%d") or line:find("Error:") then print(line) end
  if line:find("Error:") then errors = errors + 1 end
end
if not r.ok or errors > 0 then error(("Widget compile failed (exit %s, %d errors): %s"):format(tostring(r.code), errors, win(log)), 0) end
print("compiled: " .. win(manifest))
