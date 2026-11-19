// Copyright 2026-Present TypeDreamMoon. All Rights Reserved.

#include "DreamUIRender/DreamUIBaseShaders.h"

#include "Engine/Texture.h"
#include "RenderingThread.h"
#include "TextureResource.h"

#include "HAL/IConsoleManager.h"
#include "HAL/ThreadSafeCounter.h"
#include "UObject/UObjectBaseUtility.h"

namespace DreamUIBaseShadersLocal
{
	// DIAGNOSTIC (log only, default off), to settle one question: does a built-in draw ever resolve a texture whose
	// UObject has already been let go? The game thread names these textures weakly and resolves them to raw pointers
	// for the render command that carries them (GetTexturesForRenderCommand), and the render thread dereferences those
	// raw pointers here. If one of them is garbage by then, the FRHITextureReference read out of it is not a stale
	// pointer but a freshly fabricated one, which is the only shape that explains a faulting address in no heap
	// without any pool having moved anything.
	//
	// Prediction registered before the first run: NO hits. UTexture's IsReadyForFinishDestroy waits on its resource
	// release fence, so the object is not purged until the render thread has passed the commands enqueued before it.
	// A hit would therefore be a real find, and none leaves the per-kind frame scales as the primary evidence.
	static TAutoConsoleVariable<int32> CVarLogStaleTextures(
		TEXT("DreamGUI.LogStaleTextures"), 0,
		TEXT("Log when a built-in draw resolves a texture whose UObject is already garbage or unreachable (log only, never fatal)."),
		ECVF_RenderThreadSafe);

	static FThreadSafeCounter StaleHits;

	/** Flags only: never a virtual call or a resource read on a pointer that may already be gone. */
	static void CheckNotStale(const UTexture* InTexture, const TCHAR* InSlot)
	{
		if (InTexture == nullptr || CVarLogStaleTextures.GetValueOnRenderThread() == 0)
		{
			return;
		}
		const bool bGarbage = !IsValid(InTexture);
		const bool bUnreachable = InTexture->IsUnreachable();
		if (!bGarbage && !bUnreachable)
		{
			return;
		}
		const int32 Hits = StaleHits.Increment();
		if (Hits <= 20 || (Hits % 100) == 0)
		{
			UE_LOG(LogTemp, Warning, TEXT("DreamGUI stale texture at resolve: slot=%s name=%s garbage=%d unreachable=%d frame=%u hits=%d")
				, InSlot, *InTexture->GetFName().ToString(), bGarbage ? 1 : 0, bUnreachable ? 1 : 0, GFrameNumberRenderThread, Hits);
		}
	}
}


FDreamUIBuiltInTextures FDreamUIBuiltInDrawParams::GetTexturesForRenderCommand() const
{
	// Called where the game thread's objects hold still -- the game thread itself, or the end-of-frame update that
	// builds a proxy -- which is what resolving a weak pointer asks for.
	FDreamUIBuiltInTextures Textures;
	Textures.Main = MainTexture.Get();
	Textures.Font = FontTexture.Get();
	Textures.WidgetData = WidgetDataTexture.Get();
	Textures.ClipData = ClipDataTexture.Get();
	Textures.RenderLayerTable = RenderLayerTable.Get();
	Textures.RectBlockData = RectBlockData.Get();
	Textures.PaintData = PaintData.Get();
	Textures.MaskTexture0 = MaskTexture0.Get();
	Textures.MaskTexture1 = MaskTexture1.Get();
	return Textures;
}

void FDreamUIBuiltInDrawParams::ResolveTextures_RenderThread(const FDreamUIBuiltInTextures& InTextures)
{
	check(IsInRenderingThread());
	using namespace DreamUIBaseShadersLocal;
	CheckNotStale(InTextures.Main, TEXT("Main"));
	CheckNotStale(InTextures.Font, TEXT("Font"));
	CheckNotStale(InTextures.WidgetData, TEXT("WidgetData"));
	CheckNotStale(InTextures.ClipData, TEXT("ClipData"));
	CheckNotStale(InTextures.RenderLayerTable, TEXT("RenderLayerTable"));
	CheckNotStale(InTextures.RectBlockData, TEXT("RectBlockData"));
	CheckNotStale(InTextures.PaintData, TEXT("PaintData"));
	CheckNotStale(InTextures.MaskTexture0, TEXT("MaskTexture0"));
	CheckNotStale(InTextures.MaskTexture1, TEXT("MaskTexture1"));
	// A texture's reference is made and released on the render thread, and its resource is the render thread's view
	// of it: both are read here, where they are coherent, and never on the game thread.
	auto Reference = [](const UTexture* InTexture) -> FTextureReferenceRHIRef
	{
		return InTexture != nullptr ? InTexture->TextureReference.TextureReferenceRHI : FTextureReferenceRHIRef();
	};
	auto Sampler = [](const UTexture* InTexture) -> FSamplerStateRHIRef
	{
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
