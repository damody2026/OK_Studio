// Copyright 2026-Present TypeDreamMoon. All Rights Reserved.

#include "DreamUIRender/DreamUIBaseShaders.h"

#include "Engine/Texture.h"
#include "RenderingThread.h"
#include "TextureResource.h"
#include "RHITextureReference.h"
#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include <d3d12.h>
#include "Windows/HideWindowsPlatformTypes.h"
#endif

#include "HAL/IConsoleManager.h"
#include "Misc/CoreDelegates.h"
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

	/**
	 * Flags only: never a virtual call or a resource read on a pointer that may already be gone. The slot now carries
	 * a weak pointer, so "stale" has a third shape besides garbage and unreachable: a weak that WAS set and no longer
	 * resolves, which is the collected texture this diagnostic was written to catch (`collected=1`, and no name to
	 * print, because the object is gone).
	 */
	static void CheckNotStale(const TWeakObjectPtr<const UTexture>& InWeak, const TCHAR* InSlot)
	{
		if (CVarLogStaleTextures.GetValueOnRenderThread() == 0 || InWeak.IsExplicitlyNull())
		{
			return;
		}
		const UTexture* InTexture = InWeak.Get();
		const bool bCollected = InTexture == nullptr;
		const bool bGarbage = !bCollected && !IsValid(InTexture);
		const bool bUnreachable = !bCollected && InTexture->IsUnreachable();
		if (!bCollected && !bGarbage && !bUnreachable)
		{
			return;
		}
		const int32 Hits = StaleHits.Increment();
		if (Hits <= 20 || (Hits % 100) == 0)
		{
			UE_LOG(LogTemp, Warning, TEXT("DreamGUI stale texture at resolve: slot=%s name=%s collected=%d garbage=%d unreachable=%d frame=%u hits=%d")
				, InSlot, bCollected ? TEXT("<collected>") : *InTexture->GetFName().ToString()
				, bCollected ? 1 : 0, bGarbage ? 1 : 0, bUnreachable ? 1 : 0, GFrameNumberRenderThread, Hits);
		}
	}

	// DIAGNOSTIC (log only, default off), for the GPU page fault of 2026-11-19. What a slot actually stores is an
	// FRHITextureReference -- an indirection -- and what the shader samples is whatever that indirection points at
	// RIGHT NOW. So the question this answers is: at the moment a built-in draw is resolved, which RHI texture is each
	// slot pointing at, and does a slot ever end up pointing at the texture the page-fault report names?
	//
	// Worth recording before the first run, because it corrects the mechanism this cell was asked for: the
	// indirection does NOT merely borrow its target. FRHITextureReference holds it as TRefCountPtr<FRHITexture>
	// (RHITextureReference.h:53), so while a slot points at a texture, that texture's RHI object is kept alive by
	// refcount. The measured chain says the allocation WAS released, so one of these must be true, and the log tells
	// which: (a) the reference was pointed somewhere else (a default texture) before the release, leaving nothing
	// stale -- then no slot ever names the faulting texture; or (b) a slot still names it, and then the release
	// happened despite a live refcount, which would be the find.
	//
	// Printed only when a slot's value changes, plus a heartbeat, so the arrival evidence is visible on a clean trip
	// too -- a cell whose instrument only speaks when something breaks cannot be read in the outcome we expect.
	static TAutoConsoleVariable<int32> CVarLogTextureSlots(
		TEXT("DreamGUI.LogTextureSlots"), 0,
		TEXT("Log each built-in draw slot's texture reference and the RHI texture it currently points at (log only, off by default)."),
		ECVF_RenderThreadSafe);

	static constexpr int32 NumLoggedSlots = 9;

	/** Render thread only (ResolveTextures_RenderThread checks IsInRenderingThread), so plain statics are fine. */
	static void LogSlot(int32 InIndex, const TCHAR* InSlot, const TWeakObjectPtr<const UTexture>& InWeak, const FTextureReferenceRHIRef& InReference)
	{
		if (CVarLogTextureSlots.GetValueOnRenderThread() == 0)
		{
			return;
		}
		// Resolved here, on the render thread, like everything else this function reads; a collected texture prints
		// as <collected> instead of a name, which is the case the page-fault hunt cares about.
		const UTexture* InTexture = InWeak.Get();
		static const void* LastReference[NumLoggedSlots] = {};
		static const void* LastReferenced[NumLoggedSlots] = {};
		static uint32 LastHeartbeatFrame = 0;
		FRHITextureReference* Reference = InReference.GetReference();
		FRHITexture* Referenced = Reference != nullptr ? Reference->GetReferencedTexture() : nullptr;
		const bool bChanged = LastReference[InIndex] != Reference || LastReferenced[InIndex] != Referenced;
		// One heartbeat per 600 frames across all slots: enough to prove the instrument is alive without flooding.
		const bool bHeartbeat = GFrameNumberRenderThread - LastHeartbeatFrame >= 600;
		if (!bChanged && !bHeartbeat)
		{
			return;
		}
		if (bHeartbeat)
		{
			LastHeartbeatFrame = GFrameNumberRenderThread;
		}
		LastReference[InIndex] = Reference;
		LastReferenced[InIndex] = Referenced;
		UE_LOG(LogTemp, Display, TEXT("DreamUI slot %s: %s src=%s ref=%p referenced=%p referenced_name=%s frame=%u")
			, InSlot
			, bChanged ? TEXT("changed") : TEXT("heartbeat")
			, InTexture != nullptr ? *InTexture->GetFName().ToString() : (InWeak.IsExplicitlyNull() ? TEXT("null") : TEXT("<collected>"))
			, Reference, Referenced
			, Referenced != nullptr ? *Referenced->GetName().ToString() : TEXT("none")
			, GFrameNumberRenderThread);
	}
	// DIAGNOSTIC (log only, default off), the one thing the nine slots structurally cannot show (exclusions 26 and 27):
	// what each draw ACTUALLY hands the GPU. The slots are resolved through FTextureReferenceRHIRef, which is reference
	// counted, so that instrument can only ever see live bindings; what is bound is the REFERENCE OBJECT, and the GPU
	// samples whatever it points at when the command list runs. So this records that one hop, per draw.
	//
	// Nothing is logged per draw: a frame carries hundreds of them and printing would change the timing this fault
	// depends on. Raw values go into a fixed ring; the referenced texture's name is taken as an FName while the object
	// is still alive (FRHIResource::GetName already returns FName, so no string work), which is also what lets the dump
	// print a name for a texture that is gone by then. The ring is dumped when the process hits an error, and on demand
	// through DreamGUI.DumpBoundTextures, so a clean trip can prove the instrument is alive before a faulting one runs.
	static TAutoConsoleVariable<int32> CVarLogBoundTextures(
		TEXT("DreamGUI.LogBoundTextures"), 0,
		TEXT("Record what every built-in draw binds into a ring buffer, dumped on an error or by DreamGUI.DumpBoundTextures (log only, off by default)."),
		ECVF_RenderThreadSafe);

	static constexpr int32 BoundFieldCount = 11;
	static const TCHAR* const BoundFieldNames[BoundFieldCount] = {
		TEXT("MainTex"), TEXT("FontTex"), TEXT("WidgetDataTex"), TEXT("ClipDataTex"), TEXT("RectBlockDataTex"),
		TEXT("PaintDataTex"), TEXT("MaskTex0"), TEXT("MaskTex1"), TEXT("SceneDepthTex"), TEXT("BackdropTex"),
		TEXT("RenderLayerWidgetData") };

	struct FBoundEntry
	{
		uint32 Frame = 0;
		uint32 Draw = 0;
		/** What was handed to the shader parameter: usually the texture reference OBJECT, not the texture itself. */
		const void* Bound[BoundFieldCount] = {};
		/** What that reference pointed at here; the same pointer when the bound value is not a reference. */
		const void* Referenced[BoundFieldCount] = {};
		/** Read while it is still alive, so the dump never reads freed memory. Matches the page fault dump's names. */
		FName ReferencedName[BoundFieldCount];
		/**
		 * The GPU virtual address of the texture's resource, read at bind time.
		 * MEASURED, not assumed (2026-11-20): matching the faulting texture by NAME came back negative, and a name is
		 * not what the page fault report identifies anything by -- an ADDRESS is. With the address here the question
		 * becomes "is the faulting address inside something this draw actually bound", which the report can answer.
		 * No size: asking the RHI for a texture's byte size is a device call, and this runs on every field of every
		 * draw. The fault report prints the dead allocation's own address RANGE, so the comparison is range-to-address.
		 */
		uint64 ReferencedVA[BoundFieldCount] = {};
	};

	/**
	 * How many draws the ring holds, read at startup (ECVF_ReadOnly) so a window that turns out too short can be
	 * reopened wider without another build. An entry is a few hundred bytes, so even 131072 draws is tens of MB, and
	 * at the ~30 draws per frame this scene runs that is roughly 4300 frames -- the longest gap measured between a
	 * texture's memory being returned and the fault that reads it is 4116 frames.
	 * The dump prints the frame of every entry, so the window in FRAMES is always measured, never estimated.
	 */
	static TAutoConsoleVariable<int32> CVarBoundRingSize(
		TEXT("DreamGUI.BoundRingSize"), 16384,
		TEXT("How many draws the bound-texture ring holds (read at startup)."),
		ECVF_ReadOnly);

	static int32 BoundRingSize = 0;
	static TArray<FBoundEntry> BoundRing;
	static int32 BoundRingNext = 0;
	static uint32 BoundDrawCounter = 0;
	static FThreadSafeCounter BoundDumpCount;

	static void RecordOne(FBoundEntry& OutEntry, int32 InIndex, FRHITexture* InBound)
	{
		OutEntry.Bound[InIndex] = InBound;
		FRHITexture* Referenced = InBound;
		if (InBound != nullptr)
		{
			if (FRHITextureReference* AsReference = InBound->GetTextureReference())
			{
				Referenced = AsReference->GetReferencedTexture();
			}
		}
		OutEntry.Referenced[InIndex] = Referenced;
		OutEntry.ReferencedName[InIndex] = Referenced != nullptr ? Referenced->GetName() : NAME_None;
		OutEntry.ReferencedVA[InIndex] = 0;
#if PLATFORM_WINDOWS
		if (Referenced != nullptr)
		{
			// GetNativeResource() is the ID3D12Resource on this RHI, and the address is a vtable call, so this needs
			// the header and no library. Null means "no resource", which the dump prints as 0.
			if (ID3D12Resource* Native = static_cast<ID3D12Resource*>(Referenced->GetNativeResource()))
			{
				OutEntry.ReferencedVA[InIndex] = static_cast<uint64>(Native->GetGPUVirtualAddress());
			}
		}
#endif
	}

	static void DumpBoundRing(const TCHAR* InWhy)
	{
		// Dumping twice costs nothing but a duplicate block; missing the dump costs a whole trip, so every trigger that
		// might fire is hooked and the reader of the log de-duplicates by the "DreamUI bound ring" header.
		const int32 Ordinal = BoundDumpCount.Increment();
		int32 Printed = 0;
		if (BoundRing.Num() == 0)
		{
			UE_LOG(LogTemp, Display, TEXT("DreamUI bound ring (%s) #%d: empty, nothing was recorded"), InWhy, Ordinal);
			return;
		}
		// At a large ring size printing every field of every draw would be millions of lines. Two passes instead:
		// every entry that bound a card-class texture (Texture2D_<n>, which is what the page fault dump names), and
		// then the last few hundred draws in full, so the moment of the fault is always there whatever it bound.
		const int32 TailEntries = 512;
		UE_LOG(LogTemp, Display, TEXT("DreamUI bound ring (%s) #%d: slots=%d next=%d draws=%u")
			, InWhy, Ordinal, BoundRingSize, BoundRingNext, BoundDrawCounter);
		for (int32 Step = 0; Step < BoundRingSize; ++Step)
		{
			// Oldest first, so the last line printed is the last draw recorded.
			const FBoundEntry& Entry = BoundRing[(BoundRingNext + Step) % BoundRingSize];
			if (Entry.Draw == 0)
			{
				continue;
			}
			const bool bTail = (Step >= BoundRingSize - TailEntries);
			for (int32 Field = 0; Field < BoundFieldCount; ++Field)
			{
				if (Entry.Bound[Field] == nullptr)
				{
					continue;
				}
				if (!bTail && !Entry.ReferencedName[Field].ToString().StartsWith(TEXT("Texture2D_")))
				{
					continue;
				}
				++Printed;
				UE_LOG(LogTemp, Display, TEXT("DreamUI bound: frame=%u draw=%u %s bound=%p referenced=%p va=0x%llX name=%s")
					, Entry.Frame, Entry.Draw, BoundFieldNames[Field], Entry.Bound[Field], Entry.Referenced[Field]
					, Entry.ReferencedVA[Field]
					, *Entry.ReferencedName[Field].ToString());
			}
		}
		UE_LOG(LogTemp, Display, TEXT("DreamUI bound ring end (%s) #%d: lines=%d"), InWhy, Ordinal, Printed);
	}

	static FAutoConsoleCommand GDumpBoundTextures(
		TEXT("DreamGUI.DumpBoundTextures"),
		TEXT("Dump the ring of textures the built-in draws bound (DreamGUI.LogBoundTextures must be on)."),
		FConsoleCommandDelegate::CreateStatic([]() { DumpBoundRing(TEXT("on demand")); }));

	/**
	 * Which trigger actually fires on a GPU page fault is not something to assume: the D3D12 path ends in the crash
	 * context and then forces an exit, so all three are hooked and whichever runs first wins. If a faulting trip comes
	 * back with no ring dump at all, that is an instrument failure, not a negative result (ERROR_LOG #11).
	 */
	/**
	 * MEASURED, not assumed (2026-11-20): on a GPU page fault NONE of the three delegates ran -- the log ends on the
	 * last line of the RHI's own crash report and the process is gone, so the ring was never dumped and the trip only
	 * showed that the trigger was wrong (ERROR_LOG #11: an instrument that cannot report is not a negative result).
	 * What does happen on that path is the report itself being written to the log, so the ring now rides on that: an
	 * output device watches the stream and dumps inline, on the same thread, while the process is still alive.
	 */
	class FBoundRingCrashWatcher : public FOutputDevice
	{
	public:
		virtual void Serialize(const TCHAR* InText, ELogVerbosity::Type InVerbosity, const FName& InCategory) override
		{
			if (bDumping || InText == nullptr)
			{
				return;
			}
			if (FCString::Strifind(InText, TEXT("PageFault")) == nullptr && FCString::Strifind(InText, TEXT("MMU Fault")) == nullptr)
			{
				return;
			}
			bDumping = true;
			DumpBoundRing(TEXT("gpu fault report"));
			// Once is enough: the report prints many lines and the ring does not change after the fault.
		}
		virtual bool CanBeUsedOnAnyThread() const override { return true; }
		virtual bool CanBeUsedOnMultipleThreads() const override { return true; }
	private:
		bool bDumping = false;
	};
	static FBoundRingCrashWatcher GBoundRingCrashWatcher;

	static void EnsureBoundDumpHooks()
	{
		static bool bHooked = false;
		if (bHooked)
		{
			return;
		}
		bHooked = true;
		if (GLog != nullptr)
		{
			GLog->AddOutputDevice(&GBoundRingCrashWatcher);
		}
		FCoreDelegates::OnHandleSystemError.AddStatic([]() { DumpBoundRing(TEXT("system error")); });
		FCoreDelegates::OnShutdownAfterError.AddStatic([]() { DumpBoundRing(TEXT("shutdown after error")); });
		FCoreDelegates::OnEnginePreExit.AddStatic([]() { DumpBoundRing(TEXT("engine pre exit")); });
	}
}


void DreamUIRecordBoundTextures(const FDreamUIBasePS::FParameters& InPS, FRHITexture* InRenderLayerWidgetData)
{
	using namespace DreamUIBaseShadersLocal;
	if (CVarLogBoundTextures.GetValueOnRenderThread() == 0)
	{
		return;
	}
	EnsureBoundDumpHooks();
	if (BoundRing.Num() == 0)
	{
		BoundRingSize = FMath::Clamp(CVarBoundRingSize.GetValueOnRenderThread(), 256, 1 << 21);
		BoundRing.SetNum(BoundRingSize);
		UE_LOG(LogTemp, Display, TEXT("DreamUI bound ring allocated: slots=%d"), BoundRingSize);
	}
	FBoundEntry& Entry = BoundRing[BoundRingNext];
	BoundRingNext = (BoundRingNext + 1) % BoundRingSize;
	Entry = FBoundEntry();
	Entry.Frame = GFrameNumberRenderThread;
	Entry.Draw = ++BoundDrawCounter;
	RecordOne(Entry, 0, InPS.DreamUI_MainTex);
	RecordOne(Entry, 1, InPS.DreamUI_FontTex);
	RecordOne(Entry, 2, InPS.DreamUI_WidgetDataTex);
	RecordOne(Entry, 3, InPS.DreamUI_ClipDataTex);
	RecordOne(Entry, 4, InPS.DreamUI_RectBlockDataTex);
	RecordOne(Entry, 5, InPS.DreamUI_PaintDataTex);
	RecordOne(Entry, 6, InPS.DreamUI_MaskTex0);
	RecordOne(Entry, 7, InPS.DreamUI_MaskTex1);
	RecordOne(Entry, 8, InPS.DreamUI_SceneDepthTex);
	RecordOne(Entry, 9, InPS.DreamUI_BackdropTex);
	RecordOne(Entry, 10, InRenderLayerWidgetData);
}


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
	// Diagnostic, once every slot is resolved: which RHI texture is each slot pointing at right now?
	LogSlot(0, TEXT("Main"), InTextures.Main, MainTextureRHI);
	LogSlot(1, TEXT("Font"), InTextures.Font, FontTextureRHI);
	LogSlot(2, TEXT("WidgetData"), InTextures.WidgetData, WidgetDataTextureRHI);
	LogSlot(3, TEXT("ClipData"), InTextures.ClipData, ClipDataTextureRHI);
	LogSlot(4, TEXT("RenderLayerTable"), InTextures.RenderLayerTable, RenderLayerTableRHI);
	LogSlot(5, TEXT("RectBlockData"), InTextures.RectBlockData, RectBlockDataRHI);
	LogSlot(6, TEXT("PaintData"), InTextures.PaintData, PaintDataRHI);
	LogSlot(7, TEXT("MaskTexture0"), InTextures.MaskTexture0, MaskTexture0RHI);
	LogSlot(8, TEXT("MaskTexture1"), InTextures.MaskTexture1, MaskTexture1RHI);
}

IMPLEMENT_GLOBAL_SHADER(FDreamUIBaseVS, "/Plugin/DreamGUI/Private/DreamUIBase.usf", "MainVS", SF_Vertex);
IMPLEMENT_GLOBAL_SHADER(FDreamUIBasePS, "/Plugin/DreamGUI/Private/DreamUIBase.usf", "MainPS", SF_Pixel);
