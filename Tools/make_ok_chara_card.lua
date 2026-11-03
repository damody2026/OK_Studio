-- New OK character card from an authored character (Charakuru-style workflow), see Docs/OK_CHARA_CARD.md.
--
-- Every step reads and updates the project file <project>/project.okchara and writes a review sheet
-- under <project>/review; the person checks it before running the next step.
--
--   Tools\lua\lua.exe Tools\make_ok_chara_card.lua assemble <project> [--head-scale 0.48]
--       [--head-neck "0,-0.058,0.30"] [--body-neck "0,0,0.985"]
--     selected head + body GLB (Blender coordinates, metres of the normalised Tripo models) -> assembled/<name>_assembled.glb
--   Tools\lua\lua.exe Tools\make_ok_chara_card.lua fbx2glb <project> <rigged.fbx>
--     the Tripo-rigged FBX (GLB exports from Tripo carry no skin weights) -> assembled/<name>_rigged_w.glb
--   Tools\lua\lua.exe Tools\make_ok_chara_card.lua build <project> [--base <OK card>]
--     ok-chara build + pose test + review sheets -> out/<name>.png
--
-- Blender comes from OK_BLENDER or the default install; ok-chara from OK_CHARA (default: the release build).
local ok = require "ok"
local json = ok.json
local path, proc = ok.path, ok.proc

local root = path.parent(path.parent(path.abs(arg[0])))
local function step(name) io.write("[", os.date("%H:%M:%S"), "] ", name, "\n"); io.flush() end

local function blender()
  local b = os.getenv("OK_BLENDER") or "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
  if not path.is_file(b) then error("Blender not found: " .. b .. " (set OK_BLENDER)", 0) end
  return b
end
local function ok_chara()
  local candidates = { os.getenv("OK_CHARA") or "", path.join(root, "Tools/ok-extract/target/release/ok-chara.exe"), "E:/cargo-target/ok-chara/release/ok-chara.exe" }
  for _, c in ipairs(candidates) do if c ~= "" and path.is_file(c) then return c end end
  error("ok-chara.exe not found: cargo build --release --bin ok-chara (or set OK_CHARA)", 0)
end
-- Blender runs Python only; the program text stays in this script (no .py files in the project).
local function run_blender(code, vars)
  local header = {}
  for k, v in pairs(vars) do header[#header + 1] = ("%s=%s"):format(k, json.encode(v)) end
  local prog = table.concat(header, "\n") .. "\n" .. code
  local res = proc.run({ blender(), "-b", "--factory-startup", "--python-expr", prog }, { capture = true, merge = true })
  local out = res.stdout or ""
  if not res.ok or out:find("Traceback", 1, true) then error("Blender failed:\n" .. out:sub(-3000), 0) end
  return out
end

local function load_project(dir)
  local file = path.join(dir, "project.okchara")
  local p = json.decode(path.read_text(file))
  return p, file
end
local function save_project(p, file) path.write_text(file, json.encode(p, { indent = 2, ensure_ascii = false }), { atomic = true }) end

-- Orthographic review renders (front / side / back) of GLB or OBJ files, tiled into one sheet.
local RENDER = [[
import bpy, math, mathutils as M
def load(f):
    if f.lower().endswith('.obj'): bpy.ops.wm.obj_import(filepath=f)
    else: bpy.ops.import_scene.gltf(filepath=f)
bpy.ops.wm.read_factory_settings(use_empty=True)
for f in FILES: load(f)
sc=bpy.context.scene; sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='FLAT' if TEXTURED else 'STUDIO'
sc.display.shading.color_type='TEXTURE' if TEXTURED else 'OBJECT'
sc.render.resolution_x=sc.render.resolution_y=768; sc.world=bpy.data.worlds.new('w')
objs=[o for o in sc.objects if o.type=='MESH']
for o in objs:
    if not TEXTURED: o.color=(0.9,0.85,0.5,1) if 'head' in o.name else ((1,0.35,0.35,1) if o.name.startswith('base_body') else (0.6,0.8,1,1))
pts=[o.matrix_world@M.Vector(c) for o in objs for c in o.bound_box]
mn=M.Vector([min(p[i] for p in pts) for i in range(3)]); mx=M.Vector([max(p[i] for p in pts) for i in range(3)])
ctr=(mn+mx)/2; size=max(mx-mn)
cam=bpy.data.cameras.new('c'); cam.type='ORTHO'; cam.ortho_scale=size*1.1
co=bpy.data.objects.new('c',cam); sc.collection.objects.link(co); sc.camera=co
for v,d,rz in (('front',(0,-1,0),0),('side',(1,0,0),90),('back',(0,1,0),180)):
    co.location=ctr+M.Vector(d)*size*3; co.rotation_euler=(math.radians(90),0,math.radians(rz))
    sc.render.filepath=OUT+'_'+v+'.png'; bpy.ops.render.render(write_still=True)
]]
local function review(files, out, textured)
  run_blender(RENDER, { FILES = files, OUT = out, TEXTURED = textured and "True" or "False" })
  local ff = path.join(root, "Tools/ffmpeg/ffmpeg.exe")
  local sheet = out .. ".jpg"
  proc.run({ ff, "-loglevel", "error", "-y", "-i", out .. "_front.png", "-i", out .. "_side.png", "-i", out .. "_back.png",
    "-filter_complex", "hstack=3", "-q:v", "3", sheet }, { check = true })
  for _, v in ipairs({ "front", "side", "back" }) do path.remove(out .. "_" .. v .. ".png", true) end
  return sheet
end

local ASSEMBLE = [[
import bpy, mathutils as M
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=BODY)
body=[o for o in bpy.context.scene.objects if o.type=='MESH'][0]; body.name='body'
bpy.ops.import_scene.gltf(filepath=HEAD)
head=[o for o in bpy.context.scene.objects if o.type=='MESH' and o!=body][0]; head.name='head'
s=SCALE
head.scale=(s,s,s); head.location=M.Vector(BODY_NECK)-s*M.Vector(HEAD_NECK)
for o in list(bpy.context.scene.objects):
    if o.type=='EMPTY':
        for c in o.children: c.parent=None
for o in list(bpy.context.scene.objects):
    if o.type=='EMPTY': bpy.data.objects.remove(o)
bpy.ops.object.select_all(action='SELECT'); bpy.context.view_layer.objects.active=body
bpy.ops.object.transform_apply(location=True,rotation=False,scale=True)
bpy.ops.export_scene.gltf(filepath=OUT,export_format='GLB')
]]
local FBX2GLB = [[
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX)
bpy.ops.export_scene.gltf(filepath=OUT,export_format='GLB',export_skins=True,export_animations=False,export_image_format='JPEG')
from collections import Counter
for o in bpy.context.scene.objects:
    if o.type=='MESH':
        multi=sum(1 for v in o.data.vertices if len([g for g in v.groups if g.weight>0.01])>1)
        print('WEIGHTS',o.name,len(o.data.vertices),multi)
]]

local function vec(s) local t = {}; for x in s:gmatch("[^,]+") do t[#t + 1] = tonumber(x) end; assert(#t == 3, "expected x,y,z"); return t end

local function main()
  local cmd, dir = arg[1], arg[2]
  if not cmd or not dir then
    io.stderr:write("usage: make_ok_chara_card.lua assemble|fbx2glb|build <project> ...\n"); os.exit(2)
  end
  dir = path.abs(dir)
  local p, file = load_project(dir)
  local name = p.name
  path.mkdir(path.join(dir, "assembled"), true); path.mkdir(path.join(dir, "review"), true); path.mkdir(path.join(dir, "out"), true)
  if cmd == "assemble" then
    local a = ok.args.parser("assemble"); a:arg("command"); a:arg("project")
    a:opt("--head-scale", { default = "0.48" }); a:opt("--head-neck", { default = "0,-0.058,0.30" }); a:opt("--body-neck", { default = "0,0,0.985" })
    local o = a:parse(arg)
    local head, body = path.join(dir, p.textured.head), path.join(dir, p.textured.body)
    local out = path.join(dir, "assembled", name .. "_assembled.glb")
    step("assemble " .. out)
    run_blender(ASSEMBLE, { HEAD = head, BODY = body, OUT = out, SCALE = tonumber(o.head_scale), HEAD_NECK = vec(o.head_neck), BODY_NECK = vec(o.body_neck) })
    p.assembled = { file = "assembled/" .. name .. "_assembled.glb", head_scale = tonumber(o.head_scale), head_neck = vec(o.head_neck), body_neck = vec(o.body_neck) }
    p.stage = "rig"
    save_project(p, file)
    print(review({ out }, path.join(dir, "review", "assembled"), true))
  elseif cmd == "fbx2glb" then
    local fbx = path.abs(assert(arg[3], "missing rigged FBX"))
    local out = path.join(dir, "assembled", name .. "_rigged_w.glb")
    step("convert " .. fbx)
    local log = run_blender(FBX2GLB, { FBX = fbx, OUT = out })
    for line in log:gmatch("WEIGHTS[^\n]*") do print(line) end
    p.rigged = "assembled/" .. name .. "_rigged_w.glb"; p.stage = "build"
    save_project(p, file)
  elseif cmd == "build" then
    local a = ok.args.parser("build"); a:arg("command"); a:arg("project")
    a:opt("--base", { default = p.base_card or path.join(root, "Content/CharacterCards/StreetHeroines/megumin.png") })
    local o = a:parse(arg)
    local lib = path.join(root, "Content/IndependentResources/base_v1")
    local out = path.join(dir, "out", name .. ".png")
    local fitted, posed = path.join(dir, "review", "fitted.obj"), path.join(dir, "review", "posed.obj")
    step("ok-chara build " .. out)
    local res = proc.run({ ok_chara(), "build", lib, o.base, path.join(dir, p.rigged), path.join(dir, p.options or "fit/options.json"), out, fitted }, { capture = true })
    if not res.ok then error("ok-chara build failed:\n" .. (res.stderr or "") .. (res.stdout or ""), 0) end
    print(res.stdout)
    step("pose test")
    proc.run({ ok_chara(), "pose-test", lib, out, posed }, { check = true, capture = true })
    print(review({ fitted }, path.join(dir, "review", "fit"), false))
    print(review({ posed }, path.join(dir, "review", "posed"), false))
    p.base_card = o.base; p.card = "out/" .. name .. ".png"; p.stage = "verify"
    p.build_report = json.decode(res.stdout)
    save_project(p, file)
  else
    error("unknown command " .. cmd, 0)
  end
end
main()
