// OpenKoikatsu patch (2026-11-19), not upstream DreamGUI.
#include "DreamUIRender/DreamUIDeferredRelease.h"
#include "RenderingThread.h"
#include "Misc/ScopeLock.h"

namespace DreamUIDeferredReleaseLocal
{
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
	static FCriticalSection Lock;
	static TArray<FEntry>& Entries()
	{
		static TArray<FEntry>* Instance = new TArray<FEntry>();
		return *Instance;
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
	FScopeLock Scope(&DreamUIDeferredReleaseLocal::Lock);
	TArray<DreamUIDeferredReleaseLocal::FEntry>& List = DreamUIDeferredReleaseLocal::Entries();
	const uint32 Now = GFrameNumberRenderThread;
	// Taken out first: a release may hand something else over (a proxy's delete releasing its resources).
	TArray<DreamUIDeferredReleaseLocal::FEntry> Due;
	for (int32 Index = 0; Index < List.Num();)
	{
		if (Now - List[Index].Frame >= DelayFrames)
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
	for (DreamUIDeferredReleaseLocal::FEntry& Entry : Due)
	{
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
