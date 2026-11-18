// Copyright 2019-Present LexLiu. All Rights Reserved.

#include "DreamUIRender/DreamUIShaders.h"
#include "GlobalRenderResources.h"
#include "PipelineStateCache.h"
#include "Materials/Material.h"
#include "ShaderParameterUtils.h"
#include "PrimitiveUniformShaderParameters.h"
#include "MeshBatch.h"
#include "MaterialDomain.h"
#include "Materials/MaterialRenderProxy.h"
#include "SceneView.h"

IMPLEMENT_MATERIAL_SHADER_TYPE(, FDreamUIScreenRenderVS, TEXT("/Plugin/DreamGUI/Private/DreamUIShader.usf"), TEXT("MainVS"), SF_Vertex);
IMPLEMENT_MATERIAL_SHADER_TYPE(, FDreamUIScreenRenderPS, TEXT("/Plugin/DreamGUI/Private/DreamUIShader.usf"), TEXT("MainPS"), SF_Pixel);
IMPLEMENT_MATERIAL_SHADER_TYPE(, FDreamUIWorldRenderPS, TEXT("/Plugin/DreamGUI/Private/DreamUIShader.usf"), TEXT("MainPS"), SF_Pixel);
IMPLEMENT_MATERIAL_SHADER_TYPE(, FDreamUIWorldRenderDepthFadePS, TEXT("/Plugin/DreamGUI/Private/DreamUIShader.usf"), TEXT("MainPS"), SF_Pixel);

IMPLEMENT_GLOBAL_SHADER_PARAMETER_STRUCT(FDreamUIWorldRenderDepthTexUB, "DreamUIWorldRenderDepthTexUB");

namespace DreamUIShadersLocal
{
	/**
	 * Whether DreamGUI can draw with this material: a UI material, or an unlit surface one (a custom element material, a
	 * converted particle material) -- and not one made for a skinned or deforming mesh. A character's unlit toon material
	 * is unlit too, and every one of them used to carry the four DreamGUI shaders it is never drawn with; a cook that did not
	 * have the plugin (a separately cooked material patch) left them out, and the game, which has it, called each of those
	 * materials incomplete ("missing FMaterialShader (FDreamUIWorldRenderDepthFadePS, 0)") on load.
	 */
	static bool IsDreamUIMaterial(const FMaterialShaderPermutationParameters& Parameters)
	{
		const auto& Material = Parameters.MaterialParameters;
		if (Material.MaterialDomain == MD_UI)
		{
			return true;
		}
		if (Material.MaterialDomain != MD_Surface || Material.ShadingModels.CountShadingModels() != 1 || Material.ShadingModels.GetFirstShadingModel() != EMaterialShadingModel::MSM_Unlit)
		{
			return false;
		}
		return !(Material.bIsUsedWithSkeletalMesh || Material.bIsUsedWithMorphTargets || Material.bIsUsedWithInstancedSkinnedMesh
			|| Material.bIsUsedWithAPEXCloth || Material.bIsUsedWithGeometryCache || Material.bIsUsedWithMeshDeformer);
	}
}

FDreamUIScreenRenderVS::FDreamUIScreenRenderVS(const FMaterialShaderType::CompiledShaderInitializerType& Initializer)
	: FMaterialShader(Initializer)
{
	RenderLayerTableParameter.Bind(Initializer.ParameterMap, TEXT("DreamUI_RenderLayerTable"));
	RenderLayerWidgetDataParameter.Bind(Initializer.ParameterMap, TEXT("DreamUI_RenderLayerWidgetData"));
}
bool FDreamUIScreenRenderVS::ShouldCompilePermutation(const FMaterialShaderPermutationParameters& Parameters)
{
	return DreamUIShadersLocal::IsDreamUIMaterial(Parameters);
}
void FDreamUIScreenRenderVS::ModifyCompilationEnvironment(const FMaterialShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
{
	FMaterialShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
	//OutEnvironment.SetDefine(TEXT("NUM_CUSTOMIZED_UVS"), Material->GetNumCustomizedUVs());
	OutEnvironment.SetDefine(TEXT("HAS_PRIMITIVE_UNIFORM_BUFFER"), true);
	OutEnvironment.SetDefine(TEXT("VF_SUPPORTS_PRIMITIVE_SCENE_DATA"), false);
	OutEnvironment.SetDefine(TEXT("NEEDS_WORLD_POSITION_EXCLUDING_SHADER_OFFSETS"), true);
}
void FDreamUIScreenRenderVS::SetMaterialShaderParameters(FRHICommandList& RHICmdList, const FSceneView& View, const FMaterialRenderProxy* MaterialRenderProxy, const FMaterial* Material, const TUniformBuffer<FPrimitiveUniformShaderParameters>* PrimitiveUniformBuffer, FRHITexture* InRenderLayerTable, FRHITexture* InRenderLayerWidgetData)
{
	FRHIBatchedShaderParameters& BatchedParameters = RHICmdList.GetScratchShaderParameters();
	SetUniformBufferParameter(BatchedParameters, GetUniformBufferParameter<FPrimitiveUniformShaderParameters>(), *PrimitiveUniformBuffer);
	SetViewParameters(BatchedParameters, View, View.ViewUniformBuffer);
	// Black when there is none: a record read from it names row 0, no layer.
	SetTextureParameter(BatchedParameters, RenderLayerTableParameter, InRenderLayerTable != nullptr ? InRenderLayerTable : GBlackTexture->TextureRHI.GetReference());
	SetTextureParameter(BatchedParameters, RenderLayerWidgetDataParameter, InRenderLayerWidgetData != nullptr ? InRenderLayerWidgetData : GBlackTexture->TextureRHI.GetReference());
	RHICmdList.SetBatchedShaderParameters(RHICmdList.GetBoundVertexShader(), BatchedParameters);
	FMaterialShader::SetParameters(RHICmdList, RHICmdList.GetBoundVertexShader(), MaterialRenderProxy, *Material, View);
}



FDreamUIScreenRenderPS::FDreamUIScreenRenderPS(const FMaterialShaderType::CompiledShaderInitializerType& Initializer)
	:FMaterialShader(Initializer)
{
	DreamUIGammaValuesParameter.Bind(Initializer.ParameterMap, TEXT("_DreamUIGammaValues"));
}
bool FDreamUIScreenRenderPS::ShouldCompilePermutation(const FMaterialShaderPermutationParameters& Parameters)
{
	return DreamUIShadersLocal::IsDreamUIMaterial(Parameters);
}
void FDreamUIScreenRenderPS::ModifyCompilationEnvironment(const FMaterialShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
{
	FMaterialShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
	//OutEnvironment.SetDefine(TEXT("NUM_CUSTOMIZED_UVS"), Material->GetNumCustomizedUVs());
	OutEnvironment.SetDefine(TEXT("HAS_PRIMITIVE_UNIFORM_BUFFER"), true);
	OutEnvironment.SetDefine(TEXT("VF_SUPPORTS_PRIMITIVE_SCENE_DATA"), false);
	OutEnvironment.SetDefine(TEXT("NEEDS_WORLD_POSITION_EXCLUDING_SHADER_OFFSETS"), true);
}
void FDreamUIScreenRenderPS::SetMaterialShaderParameters(FRHICommandList& RHICmdList, const FSceneView& View, const FMaterialRenderProxy* MaterialRenderProxy, const FMaterial* Material, const TUniformBuffer<FPrimitiveUniformShaderParameters>* PrimitiveUniformBuffer)
{
	FRHIBatchedShaderParameters& BatchedParameters = RHICmdList.GetScratchShaderParameters();
	SetUniformBufferParameter(BatchedParameters, GetUniformBufferParameter<FPrimitiveUniformShaderParameters>(), *PrimitiveUniformBuffer);
	SetViewParameters(BatchedParameters, View, View.ViewUniformBuffer);
	RHICmdList.SetBatchedShaderParameters(RHICmdList.GetBoundPixelShader(), BatchedParameters);
	FMaterialShader::SetParameters(RHICmdList, RHICmdList.GetBoundPixelShader(), MaterialRenderProxy, *Material, View);
}
void FDreamUIScreenRenderPS::SetGammaValue(FRHICommandList& RHICmdList, float value)
{
	FRHIBatchedShaderParameters& BatchedParameters = RHICmdList.GetScratchShaderParameters();
	FVector4f GammaValues(2.2f / value, 1.0f / value, 0.0f, 0.0f);
	SetShaderValue(BatchedParameters, DreamUIGammaValuesParameter, GammaValues);
	RHICmdList.SetBatchedShaderParameters(RHICmdList.GetBoundPixelShader(), BatchedParameters);
}


FDreamUIWorldRenderPS::FDreamUIWorldRenderPS(const FMaterialShaderType::CompiledShaderInitializerType& Initializer)
	:FDreamUIScreenRenderPS(Initializer)
{
	SceneDepthTextureScaleOffsetParameter.Bind(Initializer.ParameterMap, TEXT("_SceneDepthTextureScaleOffset"));
	SceneDepthBlendParameter.Bind(Initializer.ParameterMap, TEXT("_SceneDepthBlend"));
}
void FDreamUIWorldRenderPS::ModifyCompilationEnvironment(const FMaterialShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
{
	OutEnvironment.SetDefine(TEXT("LEXUI_BLEND_DEPTH"), true);
	FDreamUIScreenRenderPS::ModifyCompilationEnvironment(Parameters, OutEnvironment);
}
void FDreamUIWorldRenderPS::SetDepthBlendParameter(FRHICommandList& RHICmdList, float DepthBlend, const FVector4f& DepthTextureScaleOffset, FRHITexture* DepthTexture, FRHISamplerState* DepthTextureSampler)
{
	FDreamUIWorldRenderDepthTexUB UB;
	UB._SceneDepthTex = DepthTexture;
	UB._SceneDepthTexSampler = DepthTextureSampler;
	TUniformBufferRef<FDreamUIWorldRenderDepthTexUB> UniformBuffer = TUniformBufferRef<FDreamUIWorldRenderDepthTexUB>::CreateUniformBufferImmediate(UB, UniformBuffer_SingleFrame);
	FRHIBatchedShaderParameters& BatchedParameters = RHICmdList.GetScratchShaderParameters();
	SetUniformBufferParameter(BatchedParameters, GetUniformBufferParameter<FDreamUIWorldRenderDepthTexUB>(), UniformBuffer);
	SetShaderValue(BatchedParameters, SceneDepthBlendParameter, DepthBlend);
	SetShaderValue(BatchedParameters, SceneDepthTextureScaleOffsetParameter, DepthTextureScaleOffset);
	RHICmdList.SetBatchedShaderParameters(RHICmdList.GetBoundPixelShader(), BatchedParameters);
}

void FDreamUIWorldRenderPS::SetDepthBlendParameter(FRHICommandList& RHICmdList, float DepthBlend, const FVector4f& DepthTextureScaleOffset, FRHITexture* DepthTexture, TUniformBufferRef<FDreamUIWorldRenderDepthTexUB>& InOutDepthTextureBuffer)
{
	if (!InOutDepthTextureBuffer.IsValid())
	{
		FDreamUIWorldRenderDepthTexUB UB;
		UB._SceneDepthTex = DepthTexture;
		UB._SceneDepthTexSampler = TStaticSamplerState<SF_Bilinear, AM_Clamp, AM_Clamp, AM_Clamp>::GetRHI();
		InOutDepthTextureBuffer = TUniformBufferRef<FDreamUIWorldRenderDepthTexUB>::CreateUniformBufferImmediate(UB, UniformBuffer_SingleFrame);
	}
	FRHIBatchedShaderParameters& BatchedParameters = RHICmdList.GetScratchShaderParameters();
	SetUniformBufferParameter(BatchedParameters, GetUniformBufferParameter<FDreamUIWorldRenderDepthTexUB>(), InOutDepthTextureBuffer);
	SetShaderValue(BatchedParameters, SceneDepthBlendParameter, DepthBlend);
	SetShaderValue(BatchedParameters, SceneDepthTextureScaleOffsetParameter, DepthTextureScaleOffset);
	RHICmdList.SetBatchedShaderParameters(RHICmdList.GetBoundPixelShader(), BatchedParameters);
}


FDreamUIWorldRenderDepthFadePS::FDreamUIWorldRenderDepthFadePS(const FMaterialShaderType::CompiledShaderInitializerType& Initializer)
	:FDreamUIWorldRenderPS(Initializer)
{
	SceneDepthFadeParameter.Bind(Initializer.ParameterMap, TEXT("_SceneDepthFade"));
}
void FDreamUIWorldRenderDepthFadePS::ModifyCompilationEnvironment(const FMaterialShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
{
	OutEnvironment.SetDefine(TEXT("LEXUI_DEPTH_FADE"), true);
	FDreamUIWorldRenderPS::ModifyCompilationEnvironment(Parameters, OutEnvironment);
}
void FDreamUIWorldRenderDepthFadePS::SetDepthFadeParameter(FRHICommandList& RHICmdList, int DepthFade)
{
	FRHIBatchedShaderParameters& BatchedParameters = RHICmdList.GetScratchShaderParameters();
	SetShaderValue(BatchedParameters, SceneDepthFadeParameter, DepthFade);
	RHICmdList.SetBatchedShaderParameters(RHICmdList.GetBoundPixelShader(), BatchedParameters);
}
