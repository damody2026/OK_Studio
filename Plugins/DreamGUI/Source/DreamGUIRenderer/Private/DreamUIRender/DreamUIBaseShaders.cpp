// Copyright 2026-Present TypeDreamMoon. All Rights Reserved.

#include "DreamUIRender/DreamUIBaseShaders.h"

#include "Engine/Texture.h"
#include "RenderingThread.h"
#include "TextureResource.h"

FDreamUIBuiltInTextures FDreamUIBuiltInDrawParams::GetTexturesForRenderCommand() const
{
	// The weak pointers are copied, not resolved: the command that reads them resolves them on the render thread, where
	// a texture already collected comes back null and its draw binds a fallback.
	FDreamUIBuiltInTextures Textures;
	Textures.Main = MainTexture;
	Textures.Font = FontTexture;
	Textures.WidgetData = WidgetDataTexture;
	Textures.ClipData = ClipDataTexture;
	Textures.RenderLayerTable = RenderLayerTable;
	Textures.RectBlockData = RectBlockData;
	Textures.PaintData = PaintData;
	Textures.MaskTexture0 = MaskTexture0;
	Textures.MaskTexture1 = MaskTexture1;
	return Textures;
}

void FDreamUIBuiltInDrawParams::ResolveTextures_RenderThread(const FDreamUIBuiltInTextures& InTextures)
{
	check(IsInRenderingThread());
	// A texture's reference is made and released on the render thread, and its resource is the render thread's view
	// of it: both are read here, where they are coherent, and never on the game thread.
	auto Reference = [](const TWeakObjectPtr<const UTexture>& InWeak) -> FTextureReferenceRHIRef
	{
		const UTexture* InTexture = InWeak.Get();
		return InTexture != nullptr ? InTexture->TextureReference.TextureReferenceRHI : FTextureReferenceRHIRef();
	};
	auto Sampler = [](const TWeakObjectPtr<const UTexture>& InWeak) -> FSamplerStateRHIRef
	{
		const UTexture* InTexture = InWeak.Get();
		const FTextureResource* Resource = InTexture != nullptr ? InTexture->GetResource() : nullptr;
		return Resource != nullptr ? Resource->SamplerStateRHI : FSamplerStateRHIRef();
	};
	MainTextureRHI = Reference(InTextures.Main);
	MainSamplerRHI = Sampler(InTextures.Main);
	FontTextureRHI = Reference(InTextures.Font);
	FontSamplerRHI = Sampler(InTextures.Font);
	WidgetDataTextureRHI = Reference(InTextures.WidgetData);
	ClipDataTextureRHI = Reference(InTextures.ClipData);
	RenderLayerTableRHI = Reference(InTextures.RenderLayerTable);
	RectBlockDataRHI = Reference(InTextures.RectBlockData);
	PaintDataRHI = Reference(InTextures.PaintData);
	MaskTexture0RHI = Reference(InTextures.MaskTexture0);
	MaskSampler0RHI = Sampler(InTextures.MaskTexture0);
	MaskTexture1RHI = Reference(InTextures.MaskTexture1);
	MaskSampler1RHI = Sampler(InTextures.MaskTexture1);
}

IMPLEMENT_GLOBAL_SHADER(FDreamUIBaseVS, "/Plugin/DreamGUI/Private/DreamUIBase.usf", "MainVS", SF_Vertex);
IMPLEMENT_GLOBAL_SHADER(FDreamUIBasePS, "/Plugin/DreamGUI/Private/DreamUIBase.usf", "MainPS", SF_Pixel);
