// OpenKoikatsu patch (2026-11-19), not upstream DreamGUI.
#include "DreamUIRender/DreamUIDeferredRelease.h"
#include "RenderingThread.h"
#include "Misc/ScopeLock.h"
#include "HAL/IConsoleManager.h"

namespace DreamUIDeferredReleaseLocal
{
	// One scale per kind (see the header): a cvar, so a measurement does not need its own build, and read on the
	// render thread, which is the only thread that ticks the queue.
	static TAutoConsoleVariable<int32> CVarFramesTexture(
		TEXT("DreamGUI.DeferredRelease.Frames.Texture"), 3,
		TEXT("Render frames a texture handed to FDreamUIDeferredRelease waits before it is released."),
		ECVF_RenderThreadSafe);
	static TAutoConsoleVariable<int32> CVarFramesBuffer(
		TEXT("DreamGUI.DeferredRelease.Frames.Buffer"), 3,
		TEXT("Render frames a buffer handed to FDreamUIDeferredRelease waits before it is released."),
		ECVF_RenderThreadSafe);
	static TAutoConsoleVariable<int32> CVarFramesPooled(
		TEXT("DreamGUI.DeferredRelease.Frames.Pooled"), 3,
		TEXT("Render frames a pooled render target waits before it goes back to GRenderTargetPool for reuse."),
		ECVF_RenderThreadSafe);
	static TAutoConsoleVariable<int32> CVarFramesFunc(
		TEXT("DreamGUI.DeferredRelease.Frames.Func"), 3,
		TEXT("Render frames a release function handed to FDreamUIDeferredRelease::Later waits before it runs."),
		ECVF_RenderThreadSafe);
	struct FEntry
	{
		uint32 Frame = 0;
		FTextureRHIRef Texture;
		FBufferRHIRef Buffer;
		TRefCountPtr<IPooledRenderTarget> Pooled;
		TUniqueFunction<void()> Release;
	};
	// Handed over on the render thread or its graph setup tasks, hence the lock. Never destroyed: what still waits at
	// exit is left, not released after the RHI.
	/** Diagnostic (log only, default off), for the GPU page fault of 2026-11-19: the only way to answer whether a
	 *  texture the GPU faulted on was released by THIS queue. Until now this queue logged nothing per entry -- no
	 *  name, no address, no frame -- so "is it ours?" was unanswerable. Render thread. */
	static TAutoConsoleVariable<int32> CVarLogEntries(
		TEXT("DreamGUI.DeferredRelease.LogEntries"), 0,
		TEXT("Log every resource this queue lets go of, as it lets go (diagnostic, off by default)."),
		ECVF_RenderThreadSafe);
	static FCriticalSection Lock;
	static TArray<FEntry>& Entries()
	{
		static TArray<FEntry>* Instance = new TArray<FEntry>();
		return *Instance;
	}
	/** Printed once, the first time the queue ticks: today's two "the knob was never connected" mistakes both came
	 *  from having no such line. Render thread. */
	static void LogScalesOnce()
	{
		static bool bLogged = false;
		if (bLogged)
		{
			return;
		}
		bLogged = true;
		UE_LOG(LogTemp, Log, TEXT("DreamGUI deferred release frames in effect: texture=%d buffer=%d pooled=%d func=%d")
			, CVarFramesTexture.GetValueOnRenderThread(), CVarFramesBuffer.GetValueOnRenderThread()
			, CVarFramesPooled.GetValueOnRenderThread(), CVarFramesFunc.GetValueOnRenderThread());
	}

	/** The scale of this entry's kind. Render thread. */
	static uint32 FramesFor(const FEntry& InEntry)
	{
		const TAutoConsoleVariable<int32>& Variable =
			  InEntry.Release           ? CVarFramesFunc
			: InEntry.Pooled.IsValid()  ? CVarFramesPooled
			: InEntry.Buffer.IsValid()  ? CVarFramesBuffer
			:                             CVarFramesTexture;
		return static_cast<uint32>(FMath::Max(0, Variable.GetValueOnRenderThread()));
	}
	static void Add(FEntry&& InEntry)
	{
		InEntry.Frame = GFrameNumberRenderThread;
		FScopeLock Scope(&Lock);
		Entries().Add(MoveTemp(InEntry));
	}
}

void FDreamUIDeferredRelease::Hold(FTextureRHIRef InTexture)
{
	if (!InTexture.IsValid())return;
	DreamUIDeferredReleaseLocal::FEntry Entry;
	Entry.Texture = MoveTemp(InTexture);
	DreamUIDeferredReleaseLocal::Add(MoveTemp(Entry));
}

void FDreamUIDeferredRelease::Hold(FBufferRHIRef InBuffer)
{
	if (!InBuffer.IsValid())return;
	DreamUIDeferredReleaseLocal::FEntry Entry;
	Entry.Buffer = MoveTemp(InBuffer);
	DreamUIDeferredReleaseLocal::Add(MoveTemp(Entry));
}

void FDreamUIDeferredRelease::Hold(TRefCountPtr<IPooledRenderTarget> InPooled)
{
	if (!InPooled.IsValid())return;
	DreamUIDeferredReleaseLocal::FEntry Entry;
	Entry.Pooled = MoveTemp(InPooled);
	DreamUIDeferredReleaseLocal::Add(MoveTemp(Entry));
}

void FDreamUIDeferredRelease::Later(TUniqueFunction<void()> InRelease)
{
	if (!InRelease)return;
	DreamUIDeferredReleaseLocal::FEntry Entry;
	Entry.Release = MoveTemp(InRelease);
	DreamUIDeferredReleaseLocal::Add(MoveTemp(Entry));
}

void FDreamUIDeferredRelease::Tick_RenderThread()
{
	check(IsInRenderingThread());
	DreamUIDeferredReleaseLocal::LogScalesOnce();
	FScopeLock Scope(&DreamUIDeferredReleaseLocal::Lock);
	TArray<DreamUIDeferredReleaseLocal::FEntry>& List = DreamUIDeferredReleaseLocal::Entries();
	const uint32 Now = GFrameNumberRenderThread;
	// Taken out first: a release may hand something else over (a proxy's delete releasing its resources).
	TArray<DreamUIDeferredReleaseLocal::FEntry> Due;
	for (int32 Index = 0; Index < List.Num();)
	{
		if (Now - List[Index].Frame >= DreamUIDeferredReleaseLocal::FramesFor(List[Index]))
		{
			Due.Add(MoveTemp(List[Index]));
			List.RemoveAt(Index, EAllowShrinking::No);
		}
		else
		{
			++Index;
		}
	}
	Scope.Unlock();
	const bool bLog = DreamUIDeferredReleaseLocal::CVarLogEntries.GetValueOnRenderThread() != 0;
	for (DreamUIDeferredReleaseLocal::FEntry& Entry : Due)
	{
		if (bLog)
		{
			// The texture's RHI name is the same key the D3D12 page-fault report prints.
			const FRHITexture* Texture = Entry.Texture.GetReference();
			const FIntVector Size = Texture ? Texture->GetSizeXYZ() : FIntVector::ZeroValue;
			UE_LOG(LogTemp, Display, TEXT("DreamGUI deferred release lets go: kind=%s name=%s %dx%d held=%u frames now=%u"),
				Entry.Release ? TEXT("func") : Entry.Pooled.IsValid() ? TEXT("pooled") : Entry.Buffer.IsValid() ? TEXT("buffer") : TEXT("texture"),
				Texture ? *Texture->GetName().ToString() : TEXT("-"),
				Size.X, Size.Y, Now - Entry.Frame, Now);
		}
		if (Entry.Release)
		{
			Entry.Release();
		}
	}
}

int32 FDreamUIDeferredRelease::Num()
{
	FScopeLock Scope(&DreamUIDeferredReleaseLocal::Lock);
	return DreamUIDeferredReleaseLocal::Entries().Num();
}

static FAutoConsoleCommand GDreamUILogDeferredRelease(
	TEXT("DreamGUI.LogDeferredRelease"),
	TEXT("Log how many GPU resources DreamGUI holds back before releasing them (FDreamUIDeferredRelease)."),
	FConsoleCommandDelegate::CreateLambda([]()
	{
		ENQUEUE_RENDER_COMMAND(FDreamUILogDeferredRelease)([](FRHICommandListImmediate&)
		{
			UE_LOG(LogTemp, Log, TEXT("DreamGUI deferred release: %d waiting"), FDreamUIDeferredRelease::Num());
		});
	}));
