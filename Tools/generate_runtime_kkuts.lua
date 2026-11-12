-- Generate common KKUTS shader recipes and outlines from installed [nHaruka] KKUTS zipmod DXBC; never card data.
local ok = require "ok"
local cg = require "shader_program_codegen"
local json, path, util = ok.json, ok.path, ok.util

local ROOT = ok.root
local DEST = ROOT .. "/Plugins/KKRuntimePose/Source/KKRuntimePose/Private/SharedShaders"
local SAVED = ROOT .. "/Saved/ShaderDxbc/KKUTS"

local SPECS = {
  { member = "abdata/chara/kkuts.unity3d", shader = "KKUTS", recipe = "KKUTS", pass = 2, blob = 12, outline = true },
  { member = "abdata/chara/kkutsitem.unity3d", shader = "KKUTSitem", recipe = "KKUTSItem", pass = 2, blob = 12, outline = true },
  { member = "abdata/chara/kkutsalpha.unity3d", shader = "KKUTSalpha", recipe = "KKUTSAlpha", pass = 2, blob = 10, outline = false },
  { member = "abdata/chara/kkutshair.unity3d", shader = "KKUTShair", recipe = "KKUTSHair", pass = 2, blob = 12, outline = true },
  { member = "abdata/chara/kkutseye.unity3d", shader = "KKUTSeye", recipe = "KKUTSEye", pass = 1, blob = 8, outline = false },
  { member = "abdata/chara/kkutseyew.unity3d", shader = "KKUTSeyew", recipe = "KKUTSEyeWhite", pass = 1, blob = 8, outline = false },
}

local VERTEX_BUILTINS = { _WorldSpaceCameraPos = true, unity_ObjectToWorld = true, unity_WorldToObject = true, unity_MatrixVP = true }
local SEMANTICS = { POSITION0 = "OKPosition", NORMAL0 = "OKNormal", TANGENT0 = "OKTangent", TEXCOORD0 = "OKUV0",
  TEXCOORD1 = "OKUV1", TEXCOORD2 = "OKUV2", TEXCOORD3 = "OKUV3", COLOR0 = "OKColor" }

local function vertex_inputs(shader, asm)
  local out, inside = {}, false
  for line in asm:gmatch("[^\r\n]+") do
    if line:find("^// Input signature:") then inside = true
    elseif line:find("^// Output signature:") then break
    elseif inside then
      local name, index, register = line:match("^// (%u+)%s+(%d+)%s+%a+%s+(%d+)%s")
      if name then
        local value = SEMANTICS[name .. index]
        if not value then error(shader .. ": outline vertex input " .. name .. index .. " unsupported", 0) end
        out[#out + 1] = "float4 v" .. register .. "=" .. value .. ";"
      end
    end
  end
  if #out == 0 then error(shader .. ": outline vertex program has no input signature", 0) end
  return table.concat(out, "\n") .. "\n"
end

local function vertex_outputs(asm)
  local out, seen = {}, {}
  for register in asm:gmatch("dcl_output[%w_]* o(%d+)") do
    local n = tonumber(register)
    if not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  return out
end

local function replace_exact_once(text, target, replacement, label)
  local a, b = text:find(target, 1, true)
  if not a then error(label .. ": expected pattern not found:\n" .. target, 0) end
  if text:find(target, b + 1, true) then error(label .. ": expected pattern matched more than once", 0) end
  return text:sub(1, a - 1) .. replacement .. text:sub(b + 1)
end

local function find_kkuts_zipmod()
  for i = 1, #arg do
    if arg[i] == "--zipmod" and arg[i + 1] then return path.abs(arg[i + 1]) end
  end
  local game = ok.game_root(true)
  local mods = game .. "/mods"
  if path.is_dir(mods) then
    for _, f in ipairs(path.rglob(mods, "*KKUTS*.zipmod")) do
      return f
    end
  end
  error("KKUTS zipmod not found under " .. mods .. "; pass --zipmod <path>", 0)
end

local function native_blob(raw, index, stride)
  local sp = cg.sub_program_at(raw, index, stride)
  return cg.dxbc_in(sp.m_ProgramCode, "index"), sp
end

local function dump_dxbc(file, blob)
  path.write_bytes(file, blob)
  local asm = cg.dumpbin(file)
  path.write_text(path.with_suffix(file, ".asm.txt"), asm)
  return asm
end

local function main()
  local zipmod = find_kkuts_zipmod()
  path.mkdir(SAVED)
  local tmp_dir = path.temp("_kkuts_bundles")
  local outline_lines = { "// Installed KKUTS outline programs. Regenerate with Tools/generate_runtime_kkuts.lua." }
  local records = json.array({})

  local ok_run, err = pcall(function()
    for _, spec in ipairs(SPECS) do
      local bundle_path = tmp_dir .. "/" .. path.name(spec.member)
      ok.kit.call({ "zip-member", zipmod, spec.member, bundle_path })
      local tree = cg.shader_tree(bundle_path, spec.shader)
      local parsed = tree.m_ParsedForm
      local raw = cg.platform_raw(tree, 4)
      local stride = 8 -- KK Unity 5.6 ShaderProgram entry stride

      -- ForwardBase fragment program
      local pass_ = parsed.m_SubShaders[1].m_Passes[spec.pass]
      local names = cg.names(pass_.m_NameIndices)
      local program
      for _, p in ipairs(pass_.progFragment.m_SubPrograms) do
        if p.m_GpuProgramType == 17 and p.m_BlobIndex == spec.blob then program = p; break end
      end
      assert(program, spec.shader .. ": ForwardBase fragment subprogram blob " .. spec.blob .. " not found")
      local kws = cg.keyword_names(names, program.m_KeywordIndices)
      local has_dir = false
      for _, kw in ipairs(kws) do if kw == "DIRECTIONAL" then has_dir = true; break end end
      assert(has_dir, spec.shader .. ": ForwardBase subprogram missing DIRECTIONAL keyword")

      local blob = native_blob(raw, spec.blob, stride)
      local folder = SAVED .. "/" .. spec.shader
      path.mkdir(folder)
      local asm = dump_dxbc(folder .. "/forward_ps.dxbc", blob)
      local sizes = cg.cb_sizes(asm)
      assert(#sizes == #program.m_ConstantBuffers, spec.shader .. ": CB count mismatch")

      local bind_lines = {
        "// Generated by Tools/generate_runtime_kkuts.lua; Installed " .. spec.shader .. ": pass " .. spec.pass .. ", blob " .. spec.blob,
        "static const int32 G" .. spec.recipe .. "CBSize[]={" .. table.concat(sizes, ",") .. "};",
        "static const FOKAdditionalUniform G" .. spec.recipe .. "Uniforms[]={",
      }
      for cb, c in ipairs(program.m_ConstantBuffers) do
        for _, u in ipairs(cg.concat(c.m_VectorParams, c.m_MatrixParams)) do
          assert(u.m_Index // 16 < sizes[cb], spec.shader .. ": uniform offset out of CB bounds")
          bind_lines[#bind_lines + 1] = cg.uniform_line(names, cb - 1, u)
        end
      end
      bind_lines[#bind_lines + 1] = "};"
      bind_lines[#bind_lines + 1] = "static const FOKAdditionalTexture G" .. spec.recipe .. "Textures[]={"
      for _, t in ipairs(program.m_TextureParams) do
        if t.m_SamplerIndex >= 0 then
          assert(cg.uses_sampler(asm, t.m_Index, t.m_SamplerIndex), spec.shader .. ": texture sampler mismatch t" .. t.m_Index)
        end
        bind_lines[#bind_lines + 1] = cg.texture_line(names[t.m_NameIndex], t.m_Index, t.m_SamplerIndex, t.m_Dim)
      end
      bind_lines[#bind_lines + 1] = "};"
      bind_lines[#bind_lines + 1] = "static const FOKAdditionalProperty G" .. spec.recipe .. "Properties[]={"
      for _, prop in ipairs(parsed.m_PropInfo.m_Props) do
        bind_lines[#bind_lines + 1] = cg.property_line(prop)
      end
      bind_lines[#bind_lines + 1] = "};"
      path.write_text(DEST .. "/" .. spec.recipe .. "Bindings.inl", table.concat(bind_lines, "\n") .. "\n")

      local sha = cg.sha256(blob)
      local prog_body = "\n" .. cg.translate(cg.precise_lines(blob, asm)) .. "\n"
      local prog_lines = {
        "// Exact installed pixel DXBC SHA256 " .. sha,
        "static const TCHAR* G" .. spec.recipe .. "Program=",
      }
      cg.text_chunks(prog_body, prog_lines)
      prog_lines[#prog_lines + 1] = ";"
      path.write_text(DEST .. "/" .. spec.recipe .. "Program.inl", table.concat(prog_lines, "\n") .. "\n")

      -- Outline pass (Pass 1) for KKUTS, KKUTSItem, KKUTSHair
      if spec.outline then
        local opass = parsed.m_SubShaders[1].m_Passes[1]
        local onames = cg.names(opass.m_NameIndices)
        assert(opass.m_State.culling.val == 1, spec.shader .. ": expected front-cull outline pass")
        local ops, ovs
        for _, x in ipairs(opass.progFragment.m_SubPrograms) do if x.m_GpuProgramType == 17 then ops = x; break end end
        for _, x in ipairs(opass.progVertex.m_SubPrograms) do if x.m_GpuProgramType == 15 then ovs = x; break end end
        assert(ops and ovs, spec.shader .. ": outline VS/PS subprogram missing")

        local label = spec.recipe .. "Outline"
        local oblob = native_blob(raw, ops.m_BlobIndex, stride)
        local ovblob = native_blob(raw, ovs.m_BlobIndex, stride)
        local oasm = dump_dxbc(folder .. "/outline_ps.dxbc", oblob)
        local ovasm = dump_dxbc(folder .. "/outline_vs.dxbc", ovblob)
        local osizes = cg.cb_sizes(oasm)
        assert(#osizes == #ops.m_ConstantBuffers, spec.shader .. ": outline PS CB count mismatch")

        outline_lines[#outline_lines + 1] = "// " .. spec.shader .. "; original DXBC " .. cg.sha256(oblob)
        outline_lines[#outline_lines + 1] = "static const int32 G" .. label .. "CBSize[]={" .. table.concat(osizes, ",") .. "};"
        outline_lines[#outline_lines + 1] = "static const FOKAdditionalUniform G" .. label .. "Uniforms[]={"
        for cb, c in ipairs(ops.m_ConstantBuffers) do
          for _, u in ipairs(cg.concat(c.m_VectorParams, c.m_MatrixParams)) do
            outline_lines[#outline_lines + 1] = cg.uniform_line(onames, cb - 1, u)
          end
        end
        outline_lines[#outline_lines + 1] = "};"
        outline_lines[#outline_lines + 1] = "static const TArray<FOKAdditionalTexture> G" .. label .. "Textures={"
        local texture_params = cg.concat(ops.m_TextureParams)
        for _, vt in ipairs(ovs.m_TextureParams) do
          local dup = false
          for _, t in ipairs(texture_params) do if onames[t.m_NameIndex] == onames[vt.m_NameIndex] then dup = true; break end end
          if not dup then
            local new = util.deepcopy(vt)
            local top = -1
            for _, t in ipairs(texture_params) do if t.m_Index > top then top = t.m_Index end end
            new.m_Index = top + 1
            new.m_SamplerIndex = new.m_Index
            texture_params[#texture_params + 1] = new
          end
        end
        for _, t in ipairs(texture_params) do
          outline_lines[#outline_lines + 1] = cg.texture_line(onames[t.m_NameIndex], t.m_Index, t.m_SamplerIndex, t.m_Dim)
        end
        outline_lines[#outline_lines + 1] = "};"
        outline_lines[#outline_lines + 1] = "static const FOKAdditionalProperty G" .. label .. "Properties[]={"
        for _, prop in ipairs(parsed.m_PropInfo.m_Props) do
          outline_lines[#outline_lines + 1] = cg.property_line(prop)
        end
        outline_lines[#outline_lines + 1] = "};"
        outline_lines[#outline_lines + 1] = "static const TCHAR* G" .. label .. "Program="
        cg.text_chunks("\n" .. cg.translate(cg.precise_lines(oblob, oasm)) .. "\n", outline_lines)
        outline_lines[#outline_lines + 1] = ";"

        local ovsizes = cg.cb_sizes(ovasm)
        assert(#ovsizes == #ovs.m_ConstantBuffers, spec.shader .. ": outline VS CB count mismatch")
        outline_lines[#outline_lines + 1] = "static const int32 G" .. label .. "VertexCBSize[]={" .. table.concat(ovsizes, ",") .. "};"
        outline_lines[#outline_lines + 1] = "static const FOKAdditionalUniform G" .. label .. "VertexUniforms[]={"
        for cb, c in ipairs(ovs.m_ConstantBuffers) do
          for _, u in ipairs(cg.concat(c.m_VectorParams, c.m_MatrixParams)) do
            local uname = onames[u.m_NameIndex]
            if (uname:find("^unity_") or uname:find("^_WorldSpace") or uname:find("^_Projection") or uname:find("^_Screen") or uname:find("^_Time"))
              and not VERTEX_BUILTINS[uname] then
              error(spec.shader .. ": outline vertex program uses unsupported engine value " .. uname, 0)
            end
            outline_lines[#outline_lines + 1] = cg.uniform_line(onames, cb - 1, u)
          end
        end
        outline_lines[#outline_lines + 1] = "};"
        outline_lines[#outline_lines + 1] = "static const TArray<FOKAdditionalTexture> G" .. label .. "VertexTextures={"
        for _, t in ipairs(ovs.m_TextureParams) do
          outline_lines[#outline_lines + 1] = cg.texture_line(onames[t.m_NameIndex], t.m_Index, t.m_SamplerIndex, t.m_Dim)
        end
        outline_lines[#outline_lines + 1] = "};"

        -- Shared outline parent runs VS in Unity world space (identity unity_ObjectToWorld & unity_MatrixVP):
        -- 1) Measure camera distance from vertex world position v0.xyz rather than object origin cb2[3].xyz (0,0,0).
        -- 2) Apply _Offset_Z along world view ray rather than multiplying camera world position into clip Z.
        local vp_translated = cg.translate(cg.precise_lines(ovblob, ovasm), vertex_outputs(ovasm), "")
        vp_translated = replace_exact_once(
          vp_translated,
          "r0.xyz=(-cb1[4].xyz+cb2[3].xyz);",
          "r0.xyz=(-cb1[4].xyz+v0.xyz);",
          spec.shader .. " outline VS camera distance"
        )
        vp_translated = replace_exact_once(
          vp_translated,
          table.concat({
            "r1.x=(cb1[4].y*cb3[18].z);",
            "r1.x=mad(cb3[17].z,cb1[4].x,r1.x);",
            "r1.x=mad(cb3[19].z,cb1[4].z,r1.x);",
            "r1.x=(r1.x+cb3[20].z);",
            "r1.x=(r1.x*cb0[10].y);",
            "o0.z=mad(r1.x,asfloat(0xbc23d70au),r0.z);",
            "o0.xyw=r0.xyw;",
          }, "\n"),
          "o0.xyzw=float4(r0.xyz+normalize(v0.xyz-cb1[4].xyz)*(-cb0[10].y*0.0005),r0.w);",
          spec.shader .. " outline VS _Offset_Z"
        )

        outline_lines[#outline_lines + 1] = "static const TCHAR* G" .. label .. "VertexProgram="
        cg.text_chunks("\n" .. vertex_inputs(spec.shader, ovasm) .. vp_translated .. "\n", outline_lines)
        outline_lines[#outline_lines + 1] = ";"
      end

      records[#records + 1] = json.object({
        { "shader", spec.shader },
        { "recipe", spec.recipe },
        { "forward_blob", spec.blob },
        { "forward_sha256", sha },
        { "outline", spec.outline },
      })
    end
  end)
  path.rmtree(tmp_dir)
  if not ok_run then error(err, 0) end

  path.write_text(DEST .. "/KKUTSOutlinePrograms.inl", table.concat(outline_lines, "\n") .. "\n")
  path.write_text(SAVED .. "/sources.json", json.encode(records, { indent = 2 }))
  print(json.encode(json.object({ { "zipmod", zipmod }, { "recipes", #records } }), { indent = 2 }))
end

ok.main(main)
