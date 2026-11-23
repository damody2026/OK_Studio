-- Packs every example mod of Tools/ok-mod into .okmod packages (Docs/OK_MOD_S12_FINISH.md, Docs/OK_MOD_F_WAVE5.md):
-- the release DLL (Tools/ok-mod/target/release), mod.toml, locale/ and materials/ from the example, and the files
-- ModKit makes that are not versioned (content/*.pak, ui/*.dui) from --content-from/<example>/ when the example has
-- none. The pak's content_build must match the game the packages are installed into (Tools/modkit_cook.lua).
--
--   Tools\lua\lua.exe Tools\pack_mod_examples.lua --out <folder> [--content-from Mods] [--build]
--     --build   cargo build --release -j 8 --workspace in Tools/ok-mod first
-- Prints one line per example (id, version, package or the error); exit 1 when one failed.
local ok = require "ok"
local path, proc = ok.path, ok.proc

local function main()
  local p = ok.args.parser("Pack every Tools/ok-mod example into .okmod packages")
  p:opt("--out", { required = true })
  p:opt("--content-from", { default = "Mods" })
  p:flag("--build")
  local a = p:parse(arg)
  local root = ok.root
  local okmod = path.join(root, "Tools/ok-mod")
  if a.build then
    proc.run({ "cargo", "build", "--release", "-j", "8", "--workspace" }, { cwd = okmod, check = true, env = { RAYON_NUM_THREADS = "8" } })
  end
  local tool = path.join(okmod, "target/release/ok-mod-pack.exe")
  if not path.exists(tool) then error("no " .. tool .. " (run with --build)", 0) end
  local out = path.abs(path.join(root, a.out))
  local work = path.join(out, "src")
  if path.is_dir(work) then path.rmtree(work) end
  path.mkdir(work)
  local extra = path.abs(path.join(root, a.content_from))
  local failed = 0
  for _, dir in ipairs(path.iterdir(path.join(okmod, "examples"))) do
    local manifest = path.join(dir, "mod.toml")
    if path.is_file(manifest) then
      local name = path.name(dir)
      local text = path.read_text(manifest)
      local dll = text:match('\ndll%s*=%s*"([^"]+)"')
      local folder = path.join(work, name)
      path.mkdir(folder)
      path.copy(manifest, path.join(folder, "mod.toml"))
      for _, sub in ipairs({ "locale", "materials", "assets", "content", "ui" }) do
        local from = path.join(dir, sub)
        -- An empty folder in the example (content/ is kept for ModKit) counts as none.
        if not path.is_dir(from) or #path.iterdir(from) == 0 then from = path.join(extra, name, sub) end
        if path.is_dir(from) then path.copytree(from, path.join(folder, sub)) end
      end
      local args = { tool, "pack", folder, "--dll", path.join(okmod, "target/release", dll or ""), "--json" }
      local r = proc.run(args, { capture = true, cwd = out })
      if r.ok then
        local j = ok.json.decode(r.stdout)
        local moved = path.abs(path.join(out, j.package))
        io.write(("%s %s -> %s%s\n"):format(j.id, j.version, moved, (#(j.warnings or {}) > 0) and (" (warnings: " .. table.concat(j.warnings, "; ") .. ")") or ""))
      else
        failed = failed + 1
        io.write(("%s: FAILED %s\n"):format(name, ((r.stderr or "") .. (r.stdout or "")):gsub("%s+$", "")))
      end
    end
  end
  if failed > 0 then os.exit(1) end
end

ok.main(main)
