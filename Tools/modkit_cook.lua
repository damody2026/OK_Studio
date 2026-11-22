-- ModKit cook (OK mod framework work item 3, Docs/OK_MOD_S3_材質可行性.md): cooks ONE content-only mod plugin
-- (Plugins/<id>, no C++ modules) into its own legacy pak plus its own shader library, and checks a mod pak.
--
--   Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> [--plugin-dir DIR] [--engine DIR] [--out DIR]
--       cook Plugins/<id>/Content in a per-mod cook host, pak it, verify it; the last stdout line is the pak
--       and prints the content_build line for the mod.toml (the game build the pak was cooked for)
--   Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> --content-build   only print that value
--   Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> --prepare-only      lay out the cook host, print its .uproject
--   Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> --python <file.py>  run an editor Python script in the cook host
--       (authoring without the GUI; the script saves into the plugin through the host's junction)
--   Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> --verify <pak>      only check a pak (exit 1 when rejected)
--
-- The cook host (Saved/ModKit/<id>/Host/OKModCook_<id>.uproject) is a content-only project:
--   * Plugins/<id>            junction to the mod plugin (the only project plugin it enables);
--   * Shaders/OKMod/<id>      junction to the plugin's Shaders/, so a Custom node includes
--                             "/Project/OKMod/<id>/<file>.usf" (the engine maps <project>/Shaders to /Project; a
--                             content-only plugin has no module to map /Plugin/<id> itself);
--   * Config/                 the game's DefaultEngine.ini (same renderer settings, so the same shader permutations)
--                             plus a legacy-pak DefaultGame.ini and the CrowdCookSM6 custom config (DX12 SM6 only).
-- Its project name gives the shader library its name: ShaderArchive-OKModCook_<id>-PCD3D_SM6.ushaderbytecode, which
-- never collides with the game's or another mod's library.
--
-- Pak layout (what the host mounts, Docs/OK_MOD_FRAMEWORK_PLAN.md §6.11):
--   mount point  ../../../OpenKoikatsu/Mods/<id>/Content/
--   <rel>.uasset/.uexp/.ubulk   the plugin's cooked content; package root /<id>/ (the plugin's mount root)
--   ShaderArchive-OKModCook_<id>-PCD3D_SM6.ushaderbytecode   the shader library (FShaderCodeLibrary::OpenLibrary)
--
-- verify (moves to the Rust ok-mod-pack later, work item 12): every entry under the mount point above, only cooked
-- package files and this mod's shader library, and every export of every package of an allowed class (§6.11 white list).
--
-- .dui panels (§6.13 D2): every Plugins/<id>/DUI/<Name>.dui becomes /<id>/UI/WBP_<Name> (parent UOKModDreamPanel,
-- plugin OKModDream), compiled by DreamGUI's DreamUICompileWidgets in the cook host -- always from the .dui, never kept:
--   1. lint: the class line is /<id>/UI/WBP_<Name>; `use` only "Theme.dui" (the reader theme) or "Plugin.DreamGUI:...";
--      no `new`, view models, props, globals or two-way bindings (the panel reaches the game only through `Mod`);
--   2. compile, check with OKModDreamCheck (only compiler-made functions, calls on the list, references inside the
--      mod, DreamGUI or the engine) and take each widget's fingerprint; delete, compile again, same fingerprints;
--   3. cook; the pak's panel packages are checked again by the game when it mounts the pak (OKModContent).
-- The mod folder ships each .dui as ui/<Name>.dui next to content/ (the game refuses a panel without it); the run
-- leaves them in <out>/ui/. A pak with panels only has no shader library.
-- Artifacts go under Saved/ModKit/<id>/ (not versioned).
local ok = require "ok"
local json, path, proc, util = ok.json, ok.path, ok.proc, ok.util
local lfs = require "lfs"

local function win(p) return (path.norm(p):gsub("/", "\\")) end
local function step(name) io.write("[", os.date("%H:%M:%S"), "] ", name, "\n"); io.flush() end
local function editor_cmd(engine) return win(path.join(engine, "Engine/Binaries/Win64/UnrealEditor-Cmd.exe")) end

-- §6.11: the only classes a mod pak may carry (no Blueprint: code in a mod is a Rust DLL).
local ALLOWED_CLASSES = {
  Material = true, MaterialInstanceConstant = true, MaterialFunction = true, MaterialParameterCollection = true,
  Texture2D = true, TextureCube = true, Texture2DArray = true, VolumeTexture = true, SubsurfaceProfile = true,
}
-- Sub-objects a cooked white-listed asset carries along (none seen yet; add only with evidence from a cooked sample).
local ALLOWED_SUBOBJECT_CLASSES = {}
local PACKAGE_EXTENSIONS = { [".uasset"] = true, [".uexp"] = true, [".ubulk"] = true, [".uptnl"] = true }

local function host_name(id) return "OKModCook_" .. id end
local function mount_point(id) return "../../../OpenKoikatsu/Mods/" .. id .. "/Content/" end

-- Files below dir, recursive, not following links.
local function files_below(dir, out)
  out = out or {}
  if not path.is_dir(dir) then return out end
  for _, n in ipairs(path.list(dir)) do
    local full = path.join(dir, n)
    local attr = lfs.symlinkattributes(full)
    if attr and attr.mode == "directory" then files_below(full, out) elseif attr and attr.mode == "file" then out[#out + 1] = full end
  end
  return out
end

-- Plugins/<id>/DUI/*.dui (the mod's panels).
local function dui_files(plugin_dir)
  local out = {}
  local dir = path.join(plugin_dir, "DUI")
  if not path.is_dir(dir) then return out end
  for _, n in ipairs(path.list(dir)) do
    if n:lower():match("%.dui$") then
      if not n:match("^[A-Za-z0-9_]+%.dui$") then error("a panel's file name is A-Z a-z 0-9 _ only: " .. n, 0) end
      out[#out + 1] = path.join(dir, n)
    end
  end
  table.sort(out)
  return out
end

-- What a mod's .dui may say (the game's check covers the compiled result; this stops the obvious early, with a line).
local function lint_dui(id, file)
  local problems = {}
  local name = path.stem(file)
  local want = "/" .. id .. "/UI/WBP_" .. name
  local n, class = 0, nil
  local text = path.read_text(file)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local code = line:gsub("\r$", ""):gsub("//.*$", "")
    local function bad(why) problems[#problems + 1] = ("%d: %s"):format(n, why) end
    local c = code:match("^%s*class%s+(%S+)")
    if c then class = c end
    local u = code:match("^%s*use%s+(.+)$")
    if u then
      local target = u:match('^"([^"]*)"')
      if not target then bad("use names a file, not a class: " .. util.strip(u))
      elseif target ~= "Theme.dui" and not target:match("^Plugin%.DreamGUI:") then bad("use only \"Theme.dui\" or \"Plugin.DreamGUI:...\": " .. target) end
    end
    if code:find("<->", 1, true) then bad("two-way binding (<->): a panel only reads the mod's values (Mod.Text) and raises its events (Mod.Emit)") end
    for _, word in ipairs({ "new", "viewmodels", "props", "global", "globals" }) do
      if code:find("%f[%w_]" .. word .. "%f[^%w_]") then bad("`" .. word .. "` is not allowed in a mod panel") end
    end
  end
  if class ~= want then problems[#problems + 1] = ("the class line must be `class %s` (it is %s)"):format(want, tostring(class)) end
  return problems
end

local function junction(link, target)
  path.mkdir(path.parent(link))
  if not path.exists(link) then proc.run({ "mklink", "/J", win(link), win(target) }, { quiet = true, check = true }) end
  local attr = lfs.symlinkattributes(link)
  local linked = attr and attr.mode == "link" and attr.target and path.abs((attr.target:gsub("^\\\\%?\\", "")))
  if not linked or linked:lower() ~= path.abs(target):lower() then error("Unexpected junction: " .. win(link), 0) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- cook host
-- ---------------------------------------------------------------------------------------------------------------
local function prepare_host(id, plugin_dir)
  local root = ok.root
  local descriptor = path.join(plugin_dir, id .. ".uplugin")
  if not path.is_file(descriptor) then error("No plugin descriptor " .. win(descriptor), 0) end
  local plugin = json.decode((path.read_text(descriptor):gsub("^\239\187\191", "")))
  if plugin.Modules and #plugin.Modules > 0 then error("A mod plugin is content only (no Modules): " .. win(descriptor), 0) end
  if not util.truthy(plugin.CanContainContent) then error("CanContainContent must be true: " .. win(descriptor), 0) end
  local host = path.join(root, "Saved/ModKit/" .. id .. "/Host")
  path.mkdir(host)
  junction(path.join(host, "Plugins/" .. id), plugin_dir)
  if path.is_dir(path.join(plugin_dir, "Shaders")) then junction(path.join(host, "Shaders/OKMod/" .. id), path.join(plugin_dir, "Shaders")) end
  local config = path.join(host, "Config")
  path.mkdir(path.join(config, "Custom/CrowdCookSM6"))
  path.copy(path.join(root, "Config/DefaultEngine.ini"), path.join(config, "DefaultEngine.ini"))
  -- The game module and its plugins are not in the host: point their classes back at the engine (else a load error fails the run).
  path.append_text(path.join(config, "DefaultEngine.ini"), "\r\n[/Script/Engine.Engine]\r\nGameViewportClientClassName=/Script/Engine.GameViewportClient\r\n"
    .. "[/Script/EngineSettings.GameMapsSettings]\r\nGlobalDefaultGameMode=/Script/Engine.GameModeBase\r\n", { newline = "" })
  path.copy(path.join(root, "Config/Custom/CrowdCookSM6/DefaultEngine.ini"), path.join(config, "Custom/CrowdCookSM6/DefaultEngine.ini"))
  path.write_text(path.join(config, "DefaultGame.ini"), table.concat({
    "[/Script/EngineSettings.GeneralProjectSettings]",
    "ProjectName=" .. host_name(id),
    "[/Script/UnrealEd.ProjectPackagingSettings]",
    "bShareMaterialShaderCode=True",
    "bSharedMaterialNativeLibraries=True",
    "bUseIoStore=False",
    "bUseZenStore=False",
    "bUsePakFile=True",
    "" }, "\r\n"))
  local plugins = {
    json.object({ { "Name", id }, { "Enabled", true } }),
    json.object({ { "Name", "PythonScriptPlugin" }, { "Enabled", true } }),
    json.object({ { "Name", "EditorScriptingUtilities" }, { "Enabled", true } }),
  }
  -- .dui panels: DreamGUI compiles them, OKModDream is their parent class and their check (both the game's builds).
  local duis = dui_files(plugin_dir)
  if #duis > 0 then
    for _, name in ipairs({ "DreamGUI", "OKModDream" }) do
      junction(path.join(host, "Plugins/" .. name), path.join(root, "Plugins/" .. name))
      plugins[#plugins + 1] = json.object({ { "Name", name }, { "Enabled", true } })
    end
    path.mkdir(path.join(host, "DUI"))
    path.copy(path.join(root, "DUI/Theme.dui"), path.join(host, "DUI/Theme.dui"))
  end
  local project = json.object({
    { "FileVersion", 3 }, { "EngineAssociation", "" }, { "Category", "OKMod cook host" },
    { "Description", "Generated by Tools/modkit_cook.lua for mod " .. id .. "; do not edit." },
    { "Plugins", plugins },
  })
  local project_path = path.join(host, host_name(id) .. ".uproject")
  path.write_text(project_path, json.encode(project, { indent = 4 }) .. "\n")
  return { host = host, project = project_path, duis = duis }
end

-- ---------------------------------------------------------------------------------------------------------------
-- .dui panels (§6.13 D2)
-- ---------------------------------------------------------------------------------------------------------------
local function compile_duis(engine, id, host, work, round)
  local plugin = path.join(host.host, "Plugins/" .. id)
  local ui = path.join(plugin, "Content/UI")
  -- Always from the .dui: what an earlier compile left (or an author saved by hand) is deleted first.
  for _, f in ipairs(files_below(ui)) do if path.name(f):match("^WBP_.*%.uasset$") then path.remove(f) end end
  local entries = {}
  for _, d in ipairs(host.duis) do
    local name = path.stem(d)
    local copy = path.join(host.host, "DUI/" .. name .. ".dui")
    path.copy(d, copy)
    entries[#entries + 1] = json.object({ { "asset", "/" .. id .. "/UI/WBP_" .. name }, { "parent", "/Script/OKModDream.OKModDreamPanel" },
      { "source", name .. ".dui" } })
  end
  local manifest = path.join(work, "widgets.json")
  path.write_text(manifest, json.encode(json.object({ { "widgets", entries } }), { indent = 2 }) .. "\n")
  step("dui compile " .. round)
  local log = path.join(work, "dui-compile-" .. round .. ".log")
  local line = '"' .. editor_cmd(engine) .. '" "' .. win(host.project) .. '" -run=DreamUICompileWidgets -Manifest="' .. win(manifest)
    .. '" -unattended -nosound -NoSplash -NullRHI -abslog="' .. win(log) .. '"'
  local r = proc.run(line, { shell = false, hide = true, quiet = true, timeout = 20 * 60 })
  local errors = {}
  for _, l in ipairs(path.exists(log) and path.read_lines(log) or {}) do
    if l:find("DUI%d%d%d%d") or l:find("Error:", 1, true) then errors[#errors + 1] = l end
  end
  if not r.ok or #errors > 0 then error(".dui compile failed (" .. win(log) .. "):\n" .. table.concat(errors, "\n"), 0) end
  step("dui check " .. round)
  local out = path.join(work, "dui-fingerprints-" .. round .. ".txt")
  local clog = path.join(work, "dui-check-" .. round .. ".log")
  line = '"' .. editor_cmd(engine) .. '" "' .. win(host.project) .. '" -run=OKModDreamCheck -Root=' .. id .. ' -Out="' .. win(out)
    .. '" -unattended -nosound -NoSplash -NullRHI -abslog="' .. win(clog) .. '"'
  r = proc.run(line, { shell = false, hide = true, quiet = true, timeout = 20 * 60 })
  local problems = {}
  for _, l in ipairs(path.exists(clog) and path.read_lines(clog) or {}) do
    if l:find("OKModDreamCheck:", 1, true) and l:find("Error", 1, true) then problems[#problems + 1] = l end
  end
  if not r.ok or #problems > 0 or not path.is_file(out) then
    error("the .dui panels fail the mod check (" .. win(clog) .. "):\n" .. table.concat(problems, "\n"), 0)
  end
  local text = path.read_text(out)
  local count = select(2, text:gsub("\n", ""))
  if count ~= #host.duis then error(("the check saw %d panel(s), the plugin has %d .dui (%s)"):format(count, #host.duis, win(clog)), 0) end
  return text
end

local function build_duis(engine, id, host, work)
  if #host.duis == 0 then return end
  for _, d in ipairs(host.duis) do
    local problems = lint_dui(id, d)
    if #problems > 0 then error(win(d) .. ":\n  " .. table.concat(problems, "\n  "), 0) end
  end
  local first = compile_duis(engine, id, host, work, 1)
  local second = compile_duis(engine, id, host, work, 2)
  if first ~= second then
    error("compiling the same .dui twice gave different widgets:\n" .. first .. "---\n" .. second, 0)
  end
  path.mkdir(path.join(work, "ui"))
  for _, d in ipairs(host.duis) do path.copy(d, path.join(work, "ui/" .. path.name(d))) end
  io.write(first)
end


-- ---------------------------------------------------------------------------------------------------------------
-- pak check
-- ---------------------------------------------------------------------------------------------------------------
-- Reads an FString at pos; returns the string (UTF-16 reduced to ASCII-ish) and the next position.
local function read_fstring(s, pos)
  local n; n, pos = string.unpack("<i4", s, pos)
  if n == 0 then return "", pos end
  if n > 0 then
    if n > 4096 then error("bad string length") end
    return s:sub(pos, pos + n - 2), pos + n
  end
  n = -n
  if n > 4096 then error("bad string length") end
  local chars = {}
  for i = 0, n - 2 do
    local c = string.unpack("<I2", s, pos + i * 2)
    chars[#chars + 1] = c < 128 and string.char(c) or "?"
  end
  return table.concat(chars), pos + n * 2
end

-- Parses a cooked (unversioned, UE 5.8) package header (.uasset): returns {package=, names=, imports=, exports=}.
-- Layout from Engine/Source/Runtime/CoreUObject/Private/UObject/PackageFileSummary.cpp and ObjectResource.cpp.
local function parse_package(bytes)
  local pos = 1
  local tag; tag, pos = string.unpack("<I4", bytes, pos)
  if tag ~= 0x9E2A83C1 then error("not a package (tag)") end
  local legacy; legacy, pos = string.unpack("<i4", bytes, pos)
  if legacy ~= -9 then error("unsupported LegacyFileVersion " .. legacy) end
  local ue3, ue4, ue5, lic; ue3, ue4, ue5, lic, pos = string.unpack("<i4i4i4i4", bytes, pos)
  -- UE 5.8 cooks versioned headers (ue4 522, ue5 1018 here); unversioned ones (all 0) mean the same current layout.
  if (ue4 ~= 0 and ue4 < 522) or (ue5 ~= 0 and ue5 < 1018) then error(("package versions %d/%d older than this engine's"):format(ue4, ue5)) end
  pos = pos + 20 + 4 -- SavedHash (FIoHash), TotalHeaderSize
  local custom; custom, pos = string.unpack("<i4", bytes, pos)
  pos = pos + custom * 20
  local package; package, pos = read_fstring(bytes, pos)
  local flags; flags, pos = string.unpack("<I4", bytes, pos)
  if flags & 0x80000000 == 0 or flags & 0x200 == 0 then error("not a cooked package (PKG_Cooked / PKG_FilterEditorOnly missing)") end
  local name_count, name_offset; name_count, name_offset, pos = string.unpack("<i4i4", bytes, pos)
  pos = pos + 8 -- SoftObjectPathsCount, Offset (no LocalizationId: filtered)
  pos = pos + 8 -- GatherableTextDataCount, Offset
  local export_count, export_offset, import_count, import_offset
  export_count, export_offset, import_count, import_offset, pos = string.unpack("<i4i4i4i4", bytes, pos)
  -- The export map ends where the (empty) Verse cell export map starts: 96 bytes an entry with unversioned properties,
  -- 112 with ScriptSerializationStart/EndOffset (UE 5.8 cooks versioned, so 112).
  local cell_export_offset = select(2, string.unpack("<i4i4", bytes, pos))
  local stride = export_count > 0 and (cell_export_offset - export_offset) // export_count or 112
  if stride ~= 96 and stride ~= 112 then error("unexpected export map entry size " .. stride) end
  local names, p = {}, name_offset + 1
  for i = 0, name_count - 1 do
    local n; n, p = read_fstring(bytes, p)
    names[i] = n
    p = p + 4 -- NonCasePreservingHash, CasePreservingHash
  end
  local function fname(at)
    local index, number = string.unpack("<i4i4", bytes, at)
    local n = names[index]
    if not n then error("name index out of range") end
    return number > 0 and (n .. "_" .. (number - 1)) or n
  end
  local imports = {}
  p = import_offset + 1
  for i = 1, import_count do
    imports[i] = { class_package = fname(p), class = fname(p + 8), outer = string.unpack("<i4", bytes, p + 16), name = fname(p + 20) }
    p = p + 40 -- ClassPackage, ClassName, OuterIndex, ObjectName, PackageName, bImportOptional
  end
  local exports = {}
  p = export_offset + 1
  for i = 1, export_count do
    local class, super, template, outer = string.unpack("<i4i4i4i4", bytes, p)
    exports[i] = { class_index = class, outer = outer, name = fname(p + 16) }
    p = p + stride -- ObjectResource.cpp operator<<(FObjectExport)
  end
  local function resolve(index)
    if index < 0 then local imp = imports[-index]; return imp and imp.name or "?", imp
    elseif index > 0 then local exp = exports[index]; return exp and exp.name or "?", nil end
    return "None", nil
  end
  for _, e in ipairs(exports) do
    local name, imp = resolve(e.class_index)
    e.class = name
    -- A class defined in this package (ClassIndex > 0, e.g. a Blueprint's generated class) or not a /Script/ class.
    e.native = imp ~= nil and imp.class == "Class"
    if e.native and imp.outer < 0 then local outer = imports[-imp.outer]; e.class_package = outer and outer.name end
  end
  return { package = package, names = names, imports = imports, exports = exports }
end

-- Lists a pak with UnrealPak: returns mount point, entries (paths relative to the mount point), the raw listing.
local function list_pak(engine, pak)
  local r = proc.run({ win(path.join(engine, "Engine/Binaries/Win64/UnrealPak.exe")), win(pak), "-List" }, { capture = true, merge = true })
  local out = r.stdout or ""
  if not r.ok then error("UnrealPak -List failed:\n" .. out, 0) end
  local mount = out:match('[Mm]ount point "([^"\r\n]*)"') or out:match('[Mm]ount point ([^\r\n]+)')
  local entries = {}
  for name in out:gmatch('Display: "([^"]+)" offset:') do entries[#entries + 1] = name end
  return mount and util.strip(mount) or nil, entries, out
end

-- Returns problems (empty = accepted) and a report table.
local function verify_pak(engine, id, pak, work)
  local problems, report = {}, { pak = win(pak), mod = id, packages = {} }
  local function bad(msg) problems[#problems + 1] = msg end
  local mount, entries, listing = list_pak(engine, pak)
  path.write_text(path.join(work, "verify.list.txt"), listing)
  report.mount_point, report.entries = mount, entries
  local want = mount_point(id)
  if not mount then bad("no mount point in the listing") end
  -- Entries in the listing are relative to the mount point; their full path is mount .. entry.
  local library = "ShaderArchive-" .. host_name(id) .. "-"
  local packages = {}
  for _, e in ipairs(entries) do
    local full = (mount or "") .. e
    local norm = full:gsub("\\", "/")
    if norm:find("%.%./", #"../../../" + 1) or norm:find("/%./") then bad("path escapes with ./ or ../: " .. full) end
    if norm:sub(1, #want):lower() ~= want:lower() then
      bad("outside the mod root " .. want .. ": " .. full)
    else
      local rel = norm:sub(#want + 1)
      local ext = path.suffix(rel):lower()
      if not rel:find("/") and rel:sub(1, #library) == library and (ext == ".ushaderbytecode") then
        report.shader_library = rel
      elseif PACKAGE_EXTENSIONS[ext] then
        if ext == ".uasset" then packages[#packages + 1] = { rel = rel, entry = e } end
      elseif ext == ".umap" then
        bad("maps are not allowed: " .. full)
      else
        bad("file type not allowed: " .. full)
      end
    end
  end
  local needs_library = false
  -- Package classes: extract and read each .uasset header.
  local extract = path.join(work, "verify.extract")
  if path.is_dir(extract) then path.rmtree(extract) end
  path.mkdir(extract)
  local x = proc.run({ win(path.join(engine, "Engine/Binaries/Win64/UnrealPak.exe")), win(pak), "-Extract", win(extract) },
    { stdout_file = path.join(work, "verify.extract.log"), merge = true })
  if not x.ok then bad("UnrealPak -Extract failed: " .. win(path.join(work, "verify.extract.log"))) end
  for _, pkg in ipairs(packages) do
    local file = path.join(extract, pkg.entry)
    local okp, parsed = pcall(function() return parse_package(path.read_bytes(file)) end)
    if not okp then
      bad("cannot read package " .. pkg.rel .. ": " .. tostring(parsed))
    else
      local expected = "/" .. id .. "/" .. path.with_suffix(pkg.rel, "")
      local info = { file = pkg.rel, package = parsed.package, exports = {} }
      if parsed.package:lower() ~= expected:lower() then bad(pkg.rel .. " names itself " .. parsed.package .. ", expected " .. expected) end
      local asset = path.stem(pkg.rel)
      -- A .dui panel (§6.13 D2): UI/WBP_<Name> with a generated widget class, from DUI/<Name>.dui. Its exports are the
      -- DreamGUI compiler's (checked by OKModDreamCheck before the cook and by the game when it mounts the pak).
      local panel = false
      for _, e in ipairs(parsed.exports) do
        if e.class == "DreamWidgetGeneratedClass" and e.outer == 0 then panel = true end
      end
      if panel then
        local name = pkg.rel:match("^UI/WBP_([A-Za-z0-9_]+)%.uasset$")
        if not name then bad(pkg.rel .. ": a panel must be UI/WBP_<Name>") end
        info.class = "DreamWidgetGeneratedClass"
        info.panel = name
      else
        needs_library = true
      end
      for _, e in ipairs(panel and {} or parsed.exports) do
        info.exports[#info.exports + 1] = { name = e.name, class = e.class, native = e.native, class_package = e.class_package }
        local top = e.outer == 0
        if not e.native or e.class_package ~= "/Script/Engine" then
          bad(("%s: export %s has class %s (%s), not an engine class"):format(pkg.rel, e.name, e.class, e.class_package or "defined in the package"))
        elseif top and e.name == asset then
          if not ALLOWED_CLASSES[e.class] then bad(("%s: asset class %s is not allowed"):format(pkg.rel, e.class)) end
          info.class = e.class
        elseif not ALLOWED_CLASSES[e.class] and not ALLOWED_SUBOBJECT_CLASSES[e.class] then
          bad(("%s: export %s has class %s, not allowed"):format(pkg.rel, e.name, e.class))
        end
      end
      if not info.class then bad(pkg.rel .. ": no top-level asset named " .. asset) end
      report.packages[#report.packages + 1] = info
    end
  end
  if needs_library and not report.shader_library then bad("no shader library " .. library .. "<format>.ushaderbytecode at the mod root") end
  report.accepted = #problems == 0
  report.problems = problems
  path.write_text(path.join(work, "verify.json"), json.encode(report, { indent = 2 }) .. "\n")
  return problems, report
end

-- ---------------------------------------------------------------------------------------------------------------
-- cook + pak
-- ---------------------------------------------------------------------------------------------------------------
-- What the game's OKModContent::ContentBuild() returns for this engine: "<Config/DefaultGame.ini [OKModding]
-- ContentBuild>@<major>.<minor>.<patch>-<Changelist>" (Engine/Build/Build.version, FEngineVersion::Current()). A mod's mod.toml content_build must equal it, else
-- the game does not mount its pak (the shaders would not match the game's).
local function content_build(engine)
  local build = "0"
  local ini = path.exists(path.join(ok.root, "Config/DefaultGame.ini")) and path.read_bytes(path.join(ok.root, "Config/DefaultGame.ini")) or ""
  local section = ini:match("%[OKModding%]([^%[]*)")
  if section then build = section:match("\nContentBuild=([^\r\n]+)") or build end
  local v = json.decode(path.read_bytes(path.join(engine, "Engine/Build/Build.version")))
  return string.format("%s@%d.%d.%d-%d", build, v.MajorVersion, v.MinorVersion, v.PatchVersion, v.Changelist)
end

local function cook(engine, id, host, work)
  step("cook " .. id)
  local cooked = path.join(work, "cook")
  if path.is_dir(cooked) then path.rmtree(cooked) end
  local log = path.join(work, "cook.log")
  local args = { '"' .. win(host.project) .. '"', "-run=Cook", "-TargetPlatform=Windows", "-MAP=/Engine/Maps/Entry", "-NoDefaultMaps",
    "-NoGameAlwaysCook", "-SkipZenStore", "-CustomConfig=CrowdCookSM6", "-unattended", "-nosound", "-NoSplash", "-corelimit=8",
    '-COOKDIR="' .. win(path.join(host.host, "Plugins/" .. id .. "/Content")) .. '"',
    '-OutputDir="' .. win(cooked) .. '"', '-abslog="' .. win(log) .. '"' }
  local line = '"' .. editor_cmd(engine) .. '" ' .. table.concat(args, " ")
  local r = proc.run(line, { shell = false, hide = true, quiet = true, timeout = 30 * 60 })
  if r.error == "timeout" then error("cook timeout: " .. win(log), 0) end
  if not r.ok then error("cook failed: " .. win(log), 0) end
  local name = host_name(id)
  local content = path.join(cooked, name .. "/Plugins/" .. id .. "/Content")
  local files = files_below(content)
  if #files == 0 then error("cook produced nothing under " .. win(content), 0) end
  local libraries = {}
  for _, f in ipairs(files_below(path.join(cooked, name .. "/Content"))) do
    if path.fnmatch(path.name(f), "ShaderArchive-" .. name .. "-*.ushaderbytecode") then libraries[#libraries + 1] = f end
  end
  -- A library cooked per plugin, should the engine ever put it next to the plugin content instead.
  for _, f in ipairs(files) do
    if path.fnmatch(path.name(f), "ShaderArchive-*.ushaderbytecode") then error("unexpected plugin shader library " .. win(f), 0) end
  end
  -- No library when nothing has shaders (a mod with .dui panels only); verify_pak requires one when materials are there.
  if #libraries == 0 then io.write("(no shader library: nothing in the plugin has shaders)\n") end
  -- A material that does not compile still "cooks" (Success, warnings only) without a shader map and draws the default
  -- material in the game; e.g. a Custom node whose #include is missing (Docs/OK_MOD_S3_材質可行性.md).
  local failed = {}
  for _, l in ipairs(path.read_lines(log)) do
    if l:find("Failed to compile Material", 1, true) or l:find("valid ShaderMap", 1, true)
      or (l:find("Expression include file path", 1, true) and l:find("invalid", 1, true)) then failed[#failed + 1] = l end
  end
  if #failed > 0 then error("material compile failed in the cook (" .. win(log) .. "):\n" .. table.concat(failed, "\n"), 0) end
  return content, files, libraries
end

local function make_pak(engine, id, content, files, libraries, work)
  step("pak " .. id)
  local lines, root = {}, mount_point(id)
  for _, f in ipairs(files) do lines[#lines + 1] = '"' .. win(f) .. '" "' .. root .. f:sub(#content + 2) .. '"' end
  for _, f in ipairs(libraries) do lines[#lines + 1] = '"' .. win(f) .. '" "' .. root .. path.name(f) .. '"' end
  local response = path.join(work, "pak.response.txt")
  path.write_text(response, table.concat(lines, "\n") .. "\n", { bom = true })
  local pak = path.join(work, "pak/" .. id .. ".pak")
  path.mkdir(path.parent(pak))
  if path.exists(pak) then path.remove(pak) end
  local r = proc.run({ win(path.join(engine, "Engine/Binaries/Win64/UnrealPak.exe")), win(pak), "-Create=" .. win(response) },
    { stdout_file = path.join(work, "pak.log"), merge = true })
  if not r.ok or not path.is_file(pak) then error("UnrealPak failed: " .. win(path.join(work, "pak.log")), 0) end
  return pak
end

local function main()
  local p = ok.args.parser("ModKit: cook one content-only mod plugin into its own pak and shader library")
  p:opt("--mod", { required = true })
  p:opt("--plugin-dir", { default = "" })
  p:opt("--engine", { default = ok.engine_root() })
  p:opt("--out", { default = "" })
  p:opt("--verify", { default = "" })
  p:opt("--python", { default = "" })
  p:flag("--prepare-only")
  p:flag("--content-build")
  local a = p:parse(arg)
  if not a.mod:match("^[A-Za-z][A-Za-z0-9_]*$") then error("--mod must match ^[A-Za-z][A-Za-z0-9_]*$ (it names the plugin and its package root)", 0) end
  local engine = path.norm(a.engine)
  local id = a.mod
  local plugin_dir = a.plugin_dir ~= "" and path.abs(a.plugin_dir) or path.join(ok.root, "Plugins/" .. id)
  local work = a.out ~= "" and path.abs(a.out) or path.join(ok.root, "Saved/ModKit/" .. id .. "/Cook-" .. os.date("%Y%m%d%H%M%S"))
  if a.content_build then io.write(content_build(engine), "\n"); return end
  path.mkdir(work)

  if a.verify ~= "" then
    local problems, report = verify_pak(engine, id, path.abs(a.verify), work)
    for _, pkg in ipairs(report.packages) do io.write("  ", pkg.file, "  ", tostring(pkg.class), "\n") end
    if #problems > 0 then
      io.write("REJECTED ", win(a.verify), "\n")
      for _, m in ipairs(problems) do io.write("  - ", m, "\n") end
      io.write(win(path.join(work, "verify.json")), "\n")
      os.exit(1)
    end
    io.write("ACCEPTED ", win(a.verify), "\n", win(path.join(work, "verify.json")), "\n")
    return
  end

  local host = prepare_host(id, plugin_dir)
  if a.prepare_only then io.write(win(host.project), "\n"); return end
  if a.python ~= "" then
    step("python " .. a.python)
    local log = path.join(work, "python.log")
    local line = '"' .. editor_cmd(engine) .. '" "' .. win(host.project) .. '" -run=pythonscript -script="' .. win(path.abs(a.python))
      .. '" -unattended -nosound -NoSplash -abslog="' .. win(log) .. '"'
    local r = proc.run(line, { shell = false, hide = true, quiet = true, timeout = 20 * 60 })
    if not r.ok then error("python script failed: " .. win(log), 0) end
    io.write(win(log), "\n")
    return
  end
  build_duis(engine, id, host, work)
  local content, files, libraries = cook(engine, id, host, work)
  local pak = make_pak(engine, id, content, files, libraries, work)
  step("verify")
  local problems = verify_pak(engine, id, pak, work)
  if #problems > 0 then
    for _, m in ipairs(problems) do io.write("  - ", m, "\n") end
    error("the cooked pak fails the mod check: " .. win(path.join(work, "verify.json")), 0)
  end
  step("done")
  local stamp = content_build(engine)
  path.write_text(path.join(work, "content_build.txt"), stamp .. "\n")
  io.write('content_build = "', stamp, '"   (put this in the mod.toml)\n')
  if #host.duis > 0 then io.write("panels: copy ", win(path.join(work, "ui")), " into the mod folder as ui/\n") end
  io.write(win(pak), "\n")
end

ok.main(main)
