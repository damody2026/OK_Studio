-- The city's uncompressed textures to BC, streamed, with mips (11-14: 1,221 textures under ResortArchitectureV1 alone,
-- 2.5 GB, all resident from the start; the game must fit an 8 GB RTX 4060). Edits the source project
-- (StreetSocialCity/Content), then Tools/migrate_street_city_content.lua copies them to Content.
--   Tools\lua\lua.exe Tools\street_city_texture_compress.lua [--dry]     (--dry: report only, nothing saved)
--   Tools\lua\lua.exe Tools\street_city_texture_compress.lua --stretch <its report>   (second pass, see below)
-- Needs an Unreal slot (a commandlet without the map, about 10 GB): claim it first.
-- Which textures: every Texture2D under /Game/UniversityCity except Localization (UI, 180 MB, left alone) that is
--   uncompressed (a setting that stores raw pixels: UserInterface2D, VectorDisplacementmap, HDR/float), has no mips or is
--   in the UI group. A compressed texture that only has NeverStream is counted in the report and left alone. What changes, keeping the material sampler type (Color/LinearColor by sRGB; Normal
--   for normal maps; Grayscale stays as it is, it is 1 byte a pixel and BC4 would need another sampler type):
--   CompressionNone off; UserInterface2D/VectorDisplacementmap -> Default (BC1/BC3); HDR/float -> HDRCompressed (BC6H);
--   NeverStream off; NoMipmaps -> FromTextureGroup; the UI texture group -> World (UI textures never stream).
-- Report: output/street-social-city-production/textures-v1/compress-<stamp>.json, with counts and the estimated GPU
-- size before/after (w*h*bytes a pixel, mips 4/3; BC1/BC3 by the source alpha) and the package bytes on disk.
package.path = 'Tools/lua/?.lua;' .. package.path
local ok = require('ok')
local lfs = require('lfs')
local engine = 'E:/PhysX/UE5.8'
local project = 'E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject/StreetSocialCity.uproject'
local dir = 'output/street-social-city-production/textures-v1/'
lfs.mkdir('output/street-social-city-production'); lfs.mkdir(dir)
local dry, stretch_from = false, nil
-- --stretch <report.json>: the second pass, the textures of that report with a side not a power of two get
--   PowerOfTwoMode StretchToPowerOfTwo (then they compress to BC, get mips and stream); nothing else changes
local ai = 1
while arg[ai] do
  if arg[ai] == '--dry' then dry = true; ai = ai + 1
  elseif arg[ai] == '--stretch' then
    local rf = assert(io.open(arg[ai + 1], 'rb')); local rr = require('ok.json').decode(rf:read('*a')); rf:close()
    local list = {}; for _, x in ipairs(rr.rows) do if not x.pow2 and not x.stretched then list[#list + 1] = x.path end end
    stretch_from = 'output/street-social-city-production/textures-v1/stretch-list.json'
    local wf = assert(io.open(stretch_from, 'wb')); wf:write(require('ok.json').encode(list)); wf:close()
    print('textures to stretch', #list); ai = ai + 2
  else error('unknown argument ' .. arg[ai], 0) end
end
local stamp = os.date('%Y%m%d-%H%M%S')
local root = lfs.currentdir():gsub('\\', '/') .. '/'
local report = root .. dir .. 'compress-' .. stamp .. (dry and '-dry' or '') .. '.json'
local py = root .. dir .. 'compress-run.py'
local f = assert(io.open(py, 'wb'))
f:write(([==[
import unreal, json, os
DRY = %s
OUT = r'%s'
CONTENT = r'%s'
STRETCH_FROM = %s
T =unreal.TextureCompressionSettings
RAW = {T.TC_EDITOR_ICON: T.TC_DEFAULT, T.TC_VECTOR_DISPLACEMENTMAP: T.TC_DEFAULT,
       T.TC_HDR: T.TC_HDR_COMPRESSED, T.TC_HALF_FLOAT: T.TC_HDR_COMPRESSED, T.TC_SINGLE_FLOAT: T.TC_HDR_COMPRESSED, T.TC_HDR_F32: T.TC_HDR_COMPRESSED}
WIDE = {T.TC_HDR: 8, T.TC_HALF_FLOAT: 8, T.TC_SINGLE_FLOAT: 16, T.TC_HDR_F32: 16}
reg = unreal.AssetRegistryHelpers.get_asset_registry()
flt = unreal.ARFilter(package_paths=['/Game/UniversityCity'], recursive_paths=True, class_paths=[unreal.TopLevelAssetPath('/Script/Engine', 'Texture2D')])
rows = []; seen = 0; never_only = 0
STRETCH = set(json.load(open(STRETCH_FROM))) if STRETCH_FROM else set()
def disk(pkg):
    p = CONTENT + pkg[len('/Game/'):] + '.uasset'
    return os.path.getsize(p) if os.path.exists(p) else 0
for ad in reg.get_assets(flt):
    pkg = str(ad.package_name)
    if pkg.startswith('/Game/UniversityCity/Localization/'): continue
    if STRETCH and pkg not in STRETCH: continue
    seen += 1
    if seen %% 500 == 0: unreal.SystemLibrary.collect_garbage()
    t = unreal.load_asset(pkg)
    if not isinstance(t, unreal.Texture2D): continue
    # CompressionNone is a plain UPROPERTY() Python cannot read; no city texture sets it (its name is in no package, 11-15)
    cs = t.get_editor_property('compression_settings'); none = False
    ns = t.get_editor_property('never_stream'); mg = t.get_editor_property('mip_gen_settings'); grp = t.get_editor_property('lod_group')
    raw = cs in RAW
    nomip = mg == unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS
    if pkg in STRETCH:
        # a side not a power of two: no mips and no streaming; one not a multiple of 4: no BC either (2048x209 stays RGBA).
        # Stretched to the next power of two the UVs still cover the whole image (padding would shift them).
        w, h = t.blueprint_get_size_x(), t.blueprint_get_size_y()
        row = dict(path=pkg, w=w, h=h, stretched=True, mode_before=str(t.get_editor_property('power_of_two_mode')))
        if not DRY:
            t.set_editor_property('power_of_two_mode', unreal.TexturePowerOfTwoSetting.STRETCH_TO_POWER_OF_TWO)
            unreal.EditorAssetLibrary.save_loaded_asset(t, False)
        p2 = lambda v: 1 << (v - 1).bit_length()
        alpha = not t.get_editor_property('compression_no_alpha')
        row.update(pow2=True, bc_ok=True, gpu_before=int(w * h * (4 if w %% 4 or h %% 4 else (1 if alpha else 0.5))), gpu_after=int(p2(w) * p2(h) * (1 if alpha else 0.5) * 4 / 3))
        rows.append(row); continue
    if STRETCH: continue
    if ns: never_only += 1
    # a compressed texture that only never streams is counted, not changed (it would resave most of the city's textures)
    if not (raw or nomip or grp == unreal.TextureGroup.TEXTUREGROUP_UI): continue
    never_only -= 1 if ns else 0
    w, h = t.blueprint_get_size_x(), t.blueprint_get_size_y()
    alpha = not t.get_editor_property('compression_no_alpha')
    bpp0 = (WIDE.get(cs, 4) if raw else (1 if alpha else 0.5))
    row = dict(path=pkg, w=w, h=h, setting=str(cs), none=none, never_stream=ns, mips=str(mg), group=str(grp), disk_before=disk(pkg),
               gpu_before=int(w * h * bpp0 * (1 if nomip else 4 / 3)))
    if cs == T.TC_GRAYSCALE or cs == T.TC_DISPLACEMENTMAP or cs == T.TC_ALPHA: row['kept_setting'] = True
    if not DRY:
        if none: t.set_editor_property('compression_none', False)
        if cs in RAW: t.set_editor_property('compression_settings', RAW[cs])
        if ns: t.set_editor_property('never_stream', False)
        if nomip: t.set_editor_property('mip_gen_settings', unreal.TextureMipGenSettings.TMGS_FROM_TEXTURE_GROUP)
        if grp == unreal.TextureGroup.TEXTUREGROUP_UI: t.set_editor_property('lod_group', unreal.TextureGroup.TEXTUREGROUP_WORLD)
        unreal.EditorAssetLibrary.save_loaded_asset(t, False)
        row['disk_after'] = disk(pkg)
    cs2 = RAW.get(cs, cs) if raw else cs
    bpp1 = (1 if cs2 == T.TC_HDR_COMPRESSED else (1 if alpha else 0.5)) if cs not in (T.TC_GRAYSCALE, T.TC_DISPLACEMENTMAP) else 1
    pow2 = (w & (w - 1)) == 0 and (h & (h - 1)) == 0
    row['pow2'] = pow2; row['bc_ok'] = w %% 4 == 0 and h %% 4 == 0
    row['gpu_after'] = int(w * h * (bpp1 if row['bc_ok'] else 4) * (4 / 3 if pow2 else 1))
    rows.append(row)
    if len(rows) %% 50 == 0:
        unreal.SystemLibrary.collect_garbage(); unreal.log('texture compress: %%d done' %% len(rows))
s = lambda k: sum(r.get(k, 0) for r in rows)
folders = {}
for r in rows:
    k = r['path'].split('/')[3]; d = folders.setdefault(k, [0, 0, 0]); d[0] += 1; d[1] += r['gpu_before']; d[2] += r['gpu_after']
json.dump(dict(dry=DRY, textures_seen=seen, changed=len(rows), never_stream_only_unchanged=never_only, gpu_before=s('gpu_before'), gpu_after=s('gpu_after'),
               disk_before=s('disk_before'), disk_after=s('disk_after'), not_pow2=sum(1 for r in rows if not r['pow2']),
               not_bc=sum(1 for r in rows if not r['bc_ok']), kept_setting=sum(1 for r in rows if r.get('kept_setting')),
               folders=folders, rows=rows), open(OUT, 'w'), indent=1)
unreal.log('texture compress: report ' + OUT)
]==]):format(dry and 'True' or 'False', report, root .. 'StreetSocialCity/Content/', stretch_from and ("r'" .. root .. stretch_from .. "'") or 'None'))
f:close()
local log = root .. dir .. 'compress-' .. stamp .. '.log'
local code = ok.proc.run({ engine .. '/Engine/Binaries/Win64/UnrealEditor-Cmd.exe', project, '-run=pythonscript', '-script=' .. py,
  '-unattended', '-nosplash', '-nop4', '-SCCProvider=None', '-abslog=' .. log }, { hide = true }).code
print('exit', code, log)
local r = io.open(report, 'rb')
if not r then print('no report'); os.exit(1) end
local s = r:read('*a'); r:close()
local j = require('ok.json').decode(s)
local G = 2 ^ 30
print(('compressed but NeverStream, left as they are: %d'):format(j.never_stream_only_unchanged or 0))
print(('textures %d seen, %d changed; GPU %.2f -> %.2f GB (estimate); disk %.2f -> %.2f GB; not power of two %d, not BC-sized %d, grayscale kept %d')
  :format(j.textures_seen, j.changed, j.gpu_before / G, j.gpu_after / G, j.disk_before / G, (j.disk_after or 0) / G, j.not_pow2, j.not_bc, j.kept_setting))
for k, v in pairs(j.folders) do print(('  %-24s %5d  %.2f -> %.2f GB'):format(k, v[1], v[2] / G, v[3] / G)) end
print('report', report)
os.exit(code == 0 and 0 or 1)
