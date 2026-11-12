// Installed KKUSS outline programs. Regenerate with Tools/generate_runtime_kkuss.lua.
// KKUSS; original DXBC e22eae25acc2dfec5115f166952e11a2062b1e35a8414753d214a7edc72c49f0
static const int32 GKKUSSOutlineCBSize[]={18,2};
static const FOKAdditionalUniform GKKUSSOutlineUniforms[]={
{TEXT("_LightColor0"),0,32,4,0,0},
{TEXT("_BaseColor"),0,48,4,0,0},
{TEXT("_Unlit_Intensity"),0,64,1,0,0},
{TEXT("_Is_LightColor_Outline"),0,72,1,0,0},
{TEXT("_MainTex_ST"),0,96,4,0,0},
{TEXT("_Is_BlendBaseColor"),0,160,1,0,0},
{TEXT("_OutlineTex_ST"),0,176,4,0,0},
{TEXT("_Is_OutlineTex"),0,192,1,0,0},
{TEXT("_Cutoff"),0,228,1,0,0},
{TEXT("_alpha_a"),0,232,1,0,0},
{TEXT("_alpha_b"),0,236,1,0,0},
{TEXT("_LineColorG"),0,272,4,0,0},
{TEXT("unity_AmbientSky"),1,16,4,0,0},
};
static const TArray<FOKAdditionalTexture> GKKUSSOutlineTextures={
{TEXT("_AlphaMask"),0,2,2},
{TEXT("_MainTex"),1,0,2},
{TEXT("_OutlineTex"),2,1,2},
{TEXT("_Outline_Sampler"),3,3,2},
{TEXT("_BakedNormal"),4,4,2},
{TEXT("_DetailMask"),5,5,2},
};
static const FOKAdditionalProperty GKKUSSOutlineProperties[]={
{TEXT("_MainTex"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("white")},
{TEXT("_NormalMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_overcolor1"),0,false,FLinearColor(1.0f,1.0f,1.0f,0.0f),TEXT("")},
{TEXT("_overtex1"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_overcolor2"),0,false,FLinearColor(1.0f,1.0f,1.0f,0.0f),TEXT("")},
{TEXT("_overtex2"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_overcolor3"),0,false,FLinearColor(1.0f,1.0f,1.0f,0.0f),TEXT("")},
{TEXT("_overtex3"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_NormalMap"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("bump")},
{TEXT("_NormalMapDetail"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("bump")},
{TEXT("_DetailMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_LineMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_AlphaMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("white")},
{TEXT("_SpecularColor"),0,false,FLinearColor(1.0f,1.0f,1.0f,0.0f),TEXT("")},
{TEXT("_DetailNormalMapScale"),3,false,FLinearColor(0.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_SpecularPower"),3,false,FLinearColor(0.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_SpecularPowerNail"),3,false,FLinearColor(0.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_ShadowExtend"),3,false,FLinearColor(0.0f,0.0f,2.0f,0.0f),TEXT("")},
{TEXT("_rimpower"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_rimV"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_nipsize"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_alpha_a"),2,false,FLinearColor(1.0f,0.0f,0.0f,0.0f),TEXT("")},
{TEXT("_alpha_b"),2,false,FLinearColor(1.0f,0.0f,0.0f,0.0f),TEXT("")},
{TEXT("_outline"),2,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("")},
{TEXT("_notusetexspecular"),3,false,FLinearColor(1.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_nip"),2,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("")},
{TEXT("_ColorMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_Color"),0,false,FLinearColor(0.33574831485748291f,0.99264711141586304f,0.69364511966705322f,1.0f),TEXT("")},
{TEXT("_Color2"),0,false,FLinearColor(0.11724189668893814f,0.0f,1.0f,1.0f),TEXT("")},
{TEXT("_Color3"),0,false,FLinearColor(0.5f,0.5f,0.5f,1.0f),TEXT("")},
{TEXT("_liquidmask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_Texture2"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_Texture3"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("bump")},
{TEXT("_LiquidTiling"),1,false,FLinearColor(0.0f,0.0f,2.0f,2.0f),TEXT("")},
{TEXT("_liquidftop"),3,false,FLinearColor(0.0f,0.0f,2.0f,0.0f),TEXT("")},
{TEXT("_liquidfbot"),3,false,FLinearColor(0.0f,0.0f,2.0f,0.0f),TEXT("")},
{TEXT("_liquidbtop"),3,false,FLinearColor(0.0f,0.0f,2.0f,0.0f),TEXT("")},
{TEXT("_liquidbbot"),3,false,FLinearColor(0.0f,0.0f,2.0f,0.0f),TEXT("")},
{TEXT("_liquidface"),3,false,FLinearColor(0.0f,0.0f,2.0f,0.0f),TEXT("")},
{TEXT("_Cutoff"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_nip_specular"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_tex1mask"),2,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("")},
{TEXT("_Occlusion"),3,false,FLinearColor(1.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Glossiness"),3,false,FLinearColor(0.34999999403953552f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Metallic"),3,false,FLinearColor(0.20000000298023224f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Emission"),3,false,FLinearColor(0.10000000149011612f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Addcolor"),0,false,FLinearColor(1.0f,0.97000002861022949f,0.94999998807907104f,1.0f),TEXT("")},
{TEXT("_DetailMaskScale"),3,false,FLinearColor(0.30000001192092896f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_ShadowPower"),3,false,FLinearColor(0.85000002384185791f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_cutoff"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
};
static const TCHAR* GKKUSSOutlineProgram=
TEXT(R"OKSHADER(
precise float4 o0=0.0;
precise float4 r0=0.0;
precise float4 r1=0.0;
precise float4 r2=0.0;
precise float4 r3=0.0;
r0.xyzw=(Texture0.Sample(Sampler2,float2((v1.xy).x,lerp((v1.xy).y,1.0-(v1.xy).y,UVFlip)))).xyzw;
r1.xyzw=(Texture1.Sample(Sampler0,float2((v1.xy).x,lerp((v1.xy).y,1.0-(v1.xy).y,UVFlip)))).xyzw;
r0.zw=(-cb0[14].zw+float2(asfloat(0x3f800000u),asfloat(0x3f800000u)));
r0.xy=max(r0.xy,r0.zw);
r0.x=min(r0.x,r0.y);
r0.x=min(r1.w,r0.x);
r0.x=(r0.x+-cb0[14].y);
r0.x=(r0.x+asfloat(0xba83126fu));
r0.x=asfloat((r0.x<asfloat(0x00000000u))?0xffffffffu:0u);
if(asuint(r0.x)!=0u) clip(-1.0);
r0.xyz=mad(cb0[17].xyz,cb0[17].www,cb0[17].www);
r1.xyz=float3(asfloat((asfloat(0x3d4ccccdu)<cb1[1].x)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb1[1].y)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb1[1].z)?0xffffffffu:0u));
r2.xyz=(cb0[4].xxx*cb1[1].xyz);
r0.w=(cb0[4].x*asfloat(0x3d4ccccdu));
r1.xyz=float3((asuint(r1.x)!=0u?r2.x:r0.w),(asuint(r1.y)!=0u?r2.y:r0.w),(asuint(r1.z)!=0u?r2.z:r0.w));
r2.xyz=float3(asfloat((asfloat(0x3d4ccccdu)<cb0[2].x)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb0[2].y)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb0[2].z)?0xffffffffu:0u));
r1.xyz=float3((asuint(r2.x)!=0u?cb0[2].x:r1.x),(asuint(r2.y)!=0u?cb0[2].y:r1.y),(asuint(r2.z)!=0u?cb0[2].z:r1.z));
r0.w=dot(r1.xyz,float3(asfloat(0x3e991687u),asfloat(0x3f1645a2u),asfloat(0x3de978d5u)));
r1.w=asfloat((r0.w<asfloat(0x3f800000u))?0xffffffffu:0u);
r2.xyz=(r1.xyz/r0.www);
r1.xyz=float3((asuint(r1.w)!=0u?r1.x:r2.x),(asuint(r1.w)!=0u?r1.y:r2.y),(asuint(r1.w)!=0u?r1.z:r2.z));
r1.xyz=(r1.xyz+float3(asfloat(0xbf800000u),asfloat(0xbf800000u),asfloat(0xbf800000u)));
r1.xyz=mad(cb0[4].zzz,r1.xyz,float3(asfloat(0x3f800000u),asfloat(0x3f800000u),asfloat(0x3f800000u)));
r2.xy=mad(v1.xy,cb0[6].xy,cb0[6].zw);
r2.xyzw=(Texture1.Sample(Sampler0,float2((r2.xy).x,lerp((r2.xy).y,1.0-(r2.xy).y,UVFlip)))).xyzw;
r2.xyz=(r2.xyz*cb0[3].xyz);
r3.xyz=(r0.xyz*r1.xyz);
r2.xyz=(r2.xyz*r2.xyz);
r2.xyz=(r0.xyz*r2.xyz);
r2.xyz=mad(r2.xyz,r1.xyz,-r3.xyz);
r2.xyz=mad(cb0[10].xxx,r2.xyz,r3.xyz);
r3.xy=mad(v1.xy,cb0[11].xy,cb0[11].zw);
r3.xyzw=(Texture2.Sample(Sampler1,float2((r3.xy).x,lerp((r3.xy).y,1.0-(r3.xy).y,UVFlip)))).xyzw;
r0.xyz=(r0.xyz*r3.xyz);
r0.xyz=mad(r0.xyz,r1.xyz,-r2.xyz);
o0.xyz=mad(cb0[12].xxx,r0.xyz,r2.xyz);
o0.w=asfloat(0x3f800000u);
return o0;
)OKSHADER")
;
static const int32 GKKUSSOutlineVertexCBSize[]={17,5,7,21};
static const FOKAdditionalUniform GKKUSSOutlineVertexUniforms[]={
{TEXT("_Farthest_Distance"),0,116,1,0,0},
{TEXT("_Nearest_Distance"),0,120,1,0,0},
{TEXT("_Outline_Sampler_ST"),0,128,4,0,0},
{TEXT("_Offset_Z"),0,164,1,0,0},
{TEXT("_BakedNormal_ST"),0,208,4,0,0},
{TEXT("_Is_BakedNormal"),0,224,1,0,0},
{TEXT("_DetailMask_ST"),0,240,4,0,0},
{TEXT("_linewidthG"),0,256,1,0,0},
{TEXT("_WorldSpaceCameraPos"),1,64,3,0,0},
{TEXT("unity_ObjectToWorld"),2,0,4,0,4},
{TEXT("unity_WorldToObject"),2,64,4,0,4},
{TEXT("unity_MatrixVP"),3,272,4,0,4},
};
static const TArray<FOKAdditionalTexture> GKKUSSOutlineVertexTextures={
{TEXT("_Outline_Sampler"),0,0,2},
{TEXT("_BakedNormal"),1,1,2},
{TEXT("_DetailMask"),2,2,2},
};
static const TCHAR* GKKUSSOutlineVertexProgram=
TEXT(R"OKSHADER(
float4 v0=OKPosition;
float4 v1=OKNormal;
float4 v2=OKTangent;
float4 v3=OKUV0;
precise float4 o0=0.0;
precise float4 o1=0.0;
precise float4 o2=0.0;
precise float4 o3=0.0;
precise float4 o4=0.0;
precise float4 r0=0.0;
precise float4 r1=0.0;
precise float4 r2=0.0;
precise float4 r3=0.0;
precise float4 r4=0.0;
r0.xyz=(-cb1[4].xyz+v0.xyz);
r0.x=dot(r0.xyz,r0.xyz);
r0.x=sqrt(r0.x);
r0.x=(r0.x+-cb0[7].y);
r0.y=(-cb0[7].y+cb0[7].z);
r0.x=(abs(r0.y)>1e-12?saturate(r0.x/r0.y):(r0.x>0.0?1.0:0.0));
r0.y=mad(r0.x,asfloat(0xc0000000u),asfloat(0x40400000u));
r0.x=(r0.x*r0.x);
r0.x=(r0.x*r0.y);
r0.yz=mad(v3.xy,cb0[15].xy,cb0[15].zw);
r1.xyzw=(Texture2.SampleGrad(Sampler2,float2((r0.yz).x,lerp((r0.yz).y,1.0-(r0.yz).y,UVFlip)),float2((float2(asfloat(0x00000000u),asfloat(0x00000000u))).x,lerp((float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,-(float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,UVFlip)),float2((float2(asfloat(0x00000000u),asfloat(0x00000000u))).x,lerp((float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,-(float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,UVFlip)))).xyzw;
r0.y=(-r1.z+asfloat(0x3f800000u));
r0.z=(cb0[16].x*asfloat(0x40400000u));
r0.y=(r0.y*r0.z);
r0.y=(r0.y*asfloat(0x3a83126fu));
r0.x=(r0.x*r0.y);
r0.yz=mad(v3.xy,cb0[8].xy,cb0[8].zw);
r1.xyzw=(Texture0.SampleLevel(Sampler0,float2((r0.yz).x,lerp((r0.yz).y,1.0-(r0.yz).y,UVFlip)),asfloat(0x00000000u))).xyzw;
r0.x=(r0.x*r1.x);
r1.x=dot(v1.xyz,cb2[4].xyz);
r1.y=dot(v1.xyz,cb2[5].xyz);
r1.z=dot(v1.xyz,cb2[6].xyz);
r0.y=dot(r1.xyz,r1.xyz);
r0.y=rsqrt(r0.y);
r0.yzw=(r0.yyy*r1.xyz);
r1.xyz=(v2.yyy*cb2[1].xyz);
r1.xyz=mad(cb2[0].xyz,v2.xxx,r1.xyz);
r1.xyz=mad(cb2[2].xyz,v2.zzz,r1.xyz);
r1.w=dot(r1.xyz,r1.xyz);
r1.w=rsqrt(r1.w);
r1.xyz=(r1.www*r1.xyz);
r2.xyz=(r0.wyz*r1.yzx);
r2.xyz=mad(r0.zwy,r1.zxy,-r2.xyz);
r2.xyz=(r2.xyz*v2.www);
r1.w=dot(r2.xyz,r2.xyz);
r1.w=rsqrt(r1.w);
r2.xyz=(r1.www*r2.xyz);
r3.xy=mad(v3.xy,cb0[13].xy,cb0[13].zw);
r3.xyzw=(Texture1.SampleLevel(Sampler1,float2((r3.xy).x,lerp((r3.xy).y,1.0-(r3.xy).y,UVFlip)),asfloat(0x00000000u))).xyzw;
r3.xyz=mad(r3.xyz,float3(asfloat(0x40000000u),asfloat(0x40000000u),asfloat(0x40000000u)),float3(asfloat(0xbf800000u),asfloat(0xbf800000u),asfloat(0xbf800000u)));
r4.xyz=(r2.xyz*r3.yyy);
o4.xyz=r2.xyz;
r2.xyz=mad(r3.xxx,r1.xyz,r4.xyz);
o3.xyz=r1.xyz;
r1.xyz=mad(r3.zzz,r0.yzw,r2.xyz);
o2.xyz=r0.yzw;
r0.y=dot(r1.xyz,r1.xyz);
r0.y=rsqrt(r0.y);
r0.yzw=(r0.yyy*r1.xyz);
r0.yzw=mad(r0.yzw,r0.xxx,v0.xyz);
r1.xyz=mad(v1.xyz,r0.xxx,v0.xyz);
r0.xyz=(r0.yzw+-r1.xyz);
r0.xyz=mad(cb0[14].xxx,r0.xyz,r1.xyz);
r1.xyzw=(r0.yyyy*cb2[1].xyzw);
r1.xyzw=mad(cb2[0].xyzw,r0.xxxx,r1.xyzw);
r0.xyzw=mad(cb2[2].xyzw,r0.zzzz,r1.xyzw);
r0.xyzw=(r0.xyzw+cb2[3].xyzw);
r1.xyzw=(r0.yyyy*cb3[18].xyzw);
r1.xyzw=mad(cb3[17].xyzw,r0.xxxx,r1.xyzw);
r1.xyzw=mad(cb3[19].xyzw,r0.zzzz,r1.xyzw);
r0.xyzw=mad(cb3[20].xyzw,r0.wwww,r1.xyzw);
o0.xyzw=float4(r0.xyz+normalize(v0.xyz-cb1[4].xyz)*(-cb0[10].y*0.0005),r0.w);
o1.xy=v3.xy;
)OKSHADER")
;
// KKUSShair; original DXBC e22eae25acc2dfec5115f166952e11a2062b1e35a8414753d214a7edc72c49f0
static const int32 GKKUSSHairOutlineCBSize[]={18,2};
static const FOKAdditionalUniform GKKUSSHairOutlineUniforms[]={
{TEXT("_LightColor0"),0,32,4,0,0},
{TEXT("_BaseColor"),0,48,4,0,0},
{TEXT("_Unlit_Intensity"),0,64,1,0,0},
{TEXT("_Is_LightColor_Outline"),0,72,1,0,0},
{TEXT("_MainTex_ST"),0,96,4,0,0},
{TEXT("_Is_BlendBaseColor"),0,160,1,0,0},
{TEXT("_OutlineTex_ST"),0,176,4,0,0},
{TEXT("_Is_OutlineTex"),0,192,1,0,0},
{TEXT("_Cutoff"),0,228,1,0,0},
{TEXT("_alpha_a"),0,232,1,0,0},
{TEXT("_alpha_b"),0,236,1,0,0},
{TEXT("_LineColorG"),0,272,4,0,0},
{TEXT("unity_AmbientSky"),1,16,4,0,0},
};
static const TArray<FOKAdditionalTexture> GKKUSSHairOutlineTextures={
{TEXT("_AlphaMask"),0,2,2},
{TEXT("_MainTex"),1,0,2},
{TEXT("_OutlineTex"),2,1,2},
{TEXT("_Outline_Sampler"),3,3,2},
{TEXT("_BakedNormal"),4,4,2},
{TEXT("_DetailMask"),5,5,2},
};
static const FOKAdditionalProperty GKKUSSHairOutlineProperties[]={
{TEXT("_AnotherRamp"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("white")},
{TEXT("_MainTex"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("white")},
{TEXT("_NormalMap"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("bump")},
{TEXT("_AlphaMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("white")},
{TEXT("_DetailMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_HairGloss"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_ShadowColor"),0,false,FLinearColor(0.62800002098083496f,0.62800002098083496f,0.62800002098083496f,1.0f),TEXT("")},
{TEXT("_SpeclarHeight"),3,false,FLinearColor(1.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_rimpower"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_rimVa"),3,false,FLinearColor(0.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_ShadowExtenda"),3,false,FLinearColor(0.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_ColorMask"),4,false,FLinearColor(0.0f,0.0f,0.0f,0.0f),TEXT("black")},
{TEXT("_Color"),0,false,FLinearColor(1.0f,1.0f,1.0f,1.0f),TEXT("")},
{TEXT("_Color2"),0,false,FLinearColor(0.78431367874145508f,0.78431367874145508f,0.78431367874145508f,1.0f),TEXT("")},
{TEXT("_Color3"),0,false,FLinearColor(0.5f,0.5f,0.5f,1.0f),TEXT("")},
{TEXT("_LineColor"),0,false,FLinearColor(0.5f,0.5f,0.5f,1.0f),TEXT("")},
{TEXT("_Cutoff"),3,false,FLinearColor(0.5f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Occlusion"),3,false,FLinearColor(1.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_SpecularPower"),3,false,FLinearColor(0.10000000149011612f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Metallic"),3,false,FLinearColor(0.05000000074505806f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Emission"),3,false,FLinearColor(0.0f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_Addcolor"),0,false,FLinearColor(1.2000000476837158f,1.2000000476837158f,1.2000000476837158f,1.0f),TEXT("")},
{TEXT("_DetailMaskScale"),3,false,FLinearColor(0.30000001192092896f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_ShadowPower"),3,false,FLinearColor(0.85000002384185791f,0.0f,1.0f,0.0f),TEXT("")},
{TEXT("_alpha_a"),2,false,FLinearColor(1.0f,0.0f,0.0f,0.0f),TEXT("")},
{TEXT("_alpha_b"),2,false,FLinearColor(1.0f,0.0f,0.0f,0.0f),TEXT("")},
{TEXT("_alpha"),3,false,FLinearColor(0.40000000596046448f,0.0f,1.0f,0.0f),TEXT("")},
};
static const TCHAR* GKKUSSHairOutlineProgram=
TEXT(R"OKSHADER(
precise float4 o0=0.0;
precise float4 r0=0.0;
precise float4 r1=0.0;
precise float4 r2=0.0;
precise float4 r3=0.0;
r0.xyzw=(Texture0.Sample(Sampler2,float2((v1.xy).x,lerp((v1.xy).y,1.0-(v1.xy).y,UVFlip)))).xyzw;
r1.xyzw=(Texture1.Sample(Sampler0,float2((v1.xy).x,lerp((v1.xy).y,1.0-(v1.xy).y,UVFlip)))).xyzw;
r0.zw=(-cb0[14].zw+float2(asfloat(0x3f800000u),asfloat(0x3f800000u)));
r0.xy=max(r0.xy,r0.zw);
r0.x=min(r0.x,r0.y);
r0.x=min(r1.w,r0.x);
r0.x=(r0.x+-cb0[14].y);
r0.x=(r0.x+asfloat(0xba83126fu));
r0.x=asfloat((r0.x<asfloat(0x00000000u))?0xffffffffu:0u);
if(asuint(r0.x)!=0u) clip(-1.0);
r0.xyz=mad(cb0[17].xyz,cb0[17].www,cb0[17].www);
r1.xyz=float3(asfloat((asfloat(0x3d4ccccdu)<cb1[1].x)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb1[1].y)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb1[1].z)?0xffffffffu:0u));
r2.xyz=(cb0[4].xxx*cb1[1].xyz);
r0.w=(cb0[4].x*asfloat(0x3d4ccccdu));
r1.xyz=float3((asuint(r1.x)!=0u?r2.x:r0.w),(asuint(r1.y)!=0u?r2.y:r0.w),(asuint(r1.z)!=0u?r2.z:r0.w));
r2.xyz=float3(asfloat((asfloat(0x3d4ccccdu)<cb0[2].x)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb0[2].y)?0xffffffffu:0u),asfloat((asfloat(0x3d4ccccdu)<cb0[2].z)?0xffffffffu:0u));
r1.xyz=float3((asuint(r2.x)!=0u?cb0[2].x:r1.x),(asuint(r2.y)!=0u?cb0[2].y:r1.y),(asuint(r2.z)!=0u?cb0[2].z:r1.z));
r0.w=dot(r1.xyz,float3(asfloat(0x3e991687u),asfloat(0x3f1645a2u),asfloat(0x3de978d5u)));
r1.w=asfloat((r0.w<asfloat(0x3f800000u))?0xffffffffu:0u);
r2.xyz=(r1.xyz/r0.www);
r1.xyz=float3((asuint(r1.w)!=0u?r1.x:r2.x),(asuint(r1.w)!=0u?r1.y:r2.y),(asuint(r1.w)!=0u?r1.z:r2.z));
r1.xyz=(r1.xyz+float3(asfloat(0xbf800000u),asfloat(0xbf800000u),asfloat(0xbf800000u)));
r1.xyz=mad(cb0[4].zzz,r1.xyz,float3(asfloat(0x3f800000u),asfloat(0x3f800000u),asfloat(0x3f800000u)));
r2.xy=mad(v1.xy,cb0[6].xy,cb0[6].zw);
r2.xyzw=(Texture1.Sample(Sampler0,float2((r2.xy).x,lerp((r2.xy).y,1.0-(r2.xy).y,UVFlip)))).xyzw;
r2.xyz=(r2.xyz*cb0[3].xyz);
r3.xyz=(r0.xyz*r1.xyz);
r2.xyz=(r2.xyz*r2.xyz);
r2.xyz=(r0.xyz*r2.xyz);
r2.xyz=mad(r2.xyz,r1.xyz,-r3.xyz);
r2.xyz=mad(cb0[10].xxx,r2.xyz,r3.xyz);
r3.xy=mad(v1.xy,cb0[11].xy,cb0[11].zw);
r3.xyzw=(Texture2.Sample(Sampler1,float2((r3.xy).x,lerp((r3.xy).y,1.0-(r3.xy).y,UVFlip)))).xyzw;
r0.xyz=(r0.xyz*r3.xyz);
r0.xyz=mad(r0.xyz,r1.xyz,-r2.xyz);
o0.xyz=mad(cb0[12].xxx,r0.xyz,r2.xyz);
o0.w=asfloat(0x3f800000u);
return o0;
)OKSHADER")
;
static const int32 GKKUSSHairOutlineVertexCBSize[]={17,5,7,21};
static const FOKAdditionalUniform GKKUSSHairOutlineVertexUniforms[]={
{TEXT("_Farthest_Distance"),0,116,1,0,0},
{TEXT("_Nearest_Distance"),0,120,1,0,0},
{TEXT("_Outline_Sampler_ST"),0,128,4,0,0},
{TEXT("_Offset_Z"),0,164,1,0,0},
{TEXT("_BakedNormal_ST"),0,208,4,0,0},
{TEXT("_Is_BakedNormal"),0,224,1,0,0},
{TEXT("_DetailMask_ST"),0,240,4,0,0},
{TEXT("_linewidthG"),0,256,1,0,0},
{TEXT("_WorldSpaceCameraPos"),1,64,3,0,0},
{TEXT("unity_ObjectToWorld"),2,0,4,0,4},
{TEXT("unity_WorldToObject"),2,64,4,0,4},
{TEXT("unity_MatrixVP"),3,272,4,0,4},
};
static const TArray<FOKAdditionalTexture> GKKUSSHairOutlineVertexTextures={
{TEXT("_Outline_Sampler"),0,0,2},
{TEXT("_BakedNormal"),1,1,2},
{TEXT("_DetailMask"),2,2,2},
};
static const TCHAR* GKKUSSHairOutlineVertexProgram=
TEXT(R"OKSHADER(
float4 v0=OKPosition;
float4 v1=OKNormal;
float4 v2=OKTangent;
float4 v3=OKUV0;
precise float4 o0=0.0;
precise float4 o1=0.0;
precise float4 o2=0.0;
precise float4 o3=0.0;
precise float4 o4=0.0;
precise float4 r0=0.0;
precise float4 r1=0.0;
precise float4 r2=0.0;
precise float4 r3=0.0;
precise float4 r4=0.0;
r0.xyz=(-cb1[4].xyz+v0.xyz);
r0.x=dot(r0.xyz,r0.xyz);
r0.x=sqrt(r0.x);
r0.x=(r0.x+-cb0[7].y);
r0.y=(-cb0[7].y+cb0[7].z);
r0.x=(abs(r0.y)>1e-12?saturate(r0.x/r0.y):(r0.x>0.0?1.0:0.0));
r0.y=mad(r0.x,asfloat(0xc0000000u),asfloat(0x40400000u));
r0.x=(r0.x*r0.x);
r0.x=(r0.x*r0.y);
r0.yz=mad(v3.xy,cb0[15].xy,cb0[15].zw);
r1.xyzw=(Texture2.SampleGrad(Sampler2,float2((r0.yz).x,lerp((r0.yz).y,1.0-(r0.yz).y,UVFlip)),float2((float2(asfloat(0x00000000u),asfloat(0x00000000u))).x,lerp((float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,-(float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,UVFlip)),float2((float2(asfloat(0x00000000u),asfloat(0x00000000u))).x,lerp((float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,-(float2(asfloat(0x00000000u),asfloat(0x00000000u))).y,UVFlip)))).xyzw;
r0.y=(-r1.z+asfloat(0x3f800000u));
r0.z=(cb0[16].x*asfloat(0x40400000u));
r0.y=(r0.y*r0.z);
r0.y=(r0.y*asfloat(0x3a83126fu));
r0.x=(r0.x*r0.y);
r0.yz=mad(v3.xy,cb0[8].xy,cb0[8].zw);
r1.xyzw=(Texture0.SampleLevel(Sampler0,float2((r0.yz).x,lerp((r0.yz).y,1.0-(r0.yz).y,UVFlip)),asfloat(0x00000000u))).xyzw;
r0.x=(r0.x*r1.x);
r1.x=dot(v1.xyz,cb2[4].xyz);
r1.y=dot(v1.xyz,cb2[5].xyz);
r1.z=dot(v1.xyz,cb2[6].xyz);
r0.y=dot(r1.xyz,r1.xyz);
r0.y=rsqrt(r0.y);
r0.yzw=(r0.yyy*r1.xyz);
r1.xyz=(v2.yyy*cb2[1].xyz);
r1.xyz=mad(cb2[0].xyz,v2.xxx,r1.xyz);
r1.xyz=mad(cb2[2].xyz,v2.zzz,r1.xyz);
r1.w=dot(r1.xyz,r1.xyz);
r1.w=rsqrt(r1.w);
r1.xyz=(r1.www*r1.xyz);
r2.xyz=(r0.wyz*r1.yzx);
r2.xyz=mad(r0.zwy,r1.zxy,-r2.xyz);
r2.xyz=(r2.xyz*v2.www);
r1.w=dot(r2.xyz,r2.xyz);
r1.w=rsqrt(r1.w);
r2.xyz=(r1.www*r2.xyz);
r3.xy=mad(v3.xy,cb0[13].xy,cb0[13].zw);
r3.xyzw=(Texture1.SampleLevel(Sampler1,float2((r3.xy).x,lerp((r3.xy).y,1.0-(r3.xy).y,UVFlip)),asfloat(0x00000000u))).xyzw;
r3.xyz=mad(r3.xyz,float3(asfloat(0x40000000u),asfloat(0x40000000u),asfloat(0x40000000u)),float3(asfloat(0xbf800000u),asfloat(0xbf800000u),asfloat(0xbf800000u)));
r4.xyz=(r2.xyz*r3.yyy);
o4.xyz=r2.xyz;
r2.xyz=mad(r3.xxx,r1.xyz,r4.xyz);
o3.xyz=r1.xyz;
r1.xyz=mad(r3.zzz,r0.yzw,r2.xyz);
o2.xyz=r0.yzw;
r0.y=dot(r1.xyz,r1.xyz);
r0.y=rsqrt(r0.y);
r0.yzw=(r0.yyy*r1.xyz);
r0.yzw=mad(r0.yzw,r0.xxx,v0.xyz);
r1.xyz=mad(v1.xyz,r0.xxx,v0.xyz);
r0.xyz=(r0.yzw+-r1.xyz);
r0.xyz=mad(cb0[14].xxx,r0.xyz,r1.xyz);
r1.xyzw=(r0.yyyy*cb2[1].xyzw);
r1.xyzw=mad(cb2[0].xyzw,r0.xxxx,r1.xyzw);
r0.xyzw=mad(cb2[2].xyzw,r0.zzzz,r1.xyzw);
r0.xyzw=(r0.xyzw+cb2[3].xyzw);
r1.xyzw=(r0.yyyy*cb3[18].xyzw);
r1.xyzw=mad(cb3[17].xyzw,r0.xxxx,r1.xyzw);
r1.xyzw=mad(cb3[19].xyzw,r0.zzzz,r1.xyzw);
r0.xyzw=mad(cb3[20].xyzw,r0.wwww,r1.xyzw);
o0.xyzw=float4(r0.xyz+normalize(v0.xyz-cb1[4].xyz)*(-cb0[10].y*0.0005),r0.w);
o1.xy=v3.xy;
)OKSHADER")
;
