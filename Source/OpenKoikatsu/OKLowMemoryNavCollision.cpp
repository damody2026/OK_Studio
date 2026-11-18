// Low-memory PC (OKRuntimeLowMemory): the navigation collision of every streamed-in static mesh is let go once it has
// loaded (Docs/STREET_CITY_STREAMING_LOWSPEC_20261114.md §12).
//
// PREREQUISITE: this project builds no navigation mesh and never queries navigation data (no NavigationSystem,
// RecastNavMesh or AI MoveTo anywhere in Source/ or Plugins/; the street walks on its own grid, GridRoute and
// NavCellTest are physics queries). Anything that starts using the engine's navigation must turn this off
// (ok.TrimNavCollision 0), or navigation meshes built at run time lose every static mesh's collision.
//
// Each UStaticMesh carries a UNavCollision: the cooked bulk plus the vertex / index arrays decoded from it in PostLoad.
// It was 1.1 GB of the 11.3 GB commit at the peak of a low-memory walk across the city and grew with every cell
// streamed in (LLM tag NavigationCollision, 0.6 -> 1.1 GB). Dropping it from the cook (bHasNavigationData off) needs a
// full cook; this frees it at run time instead. The physics collision (UBodySetup, Chaos trimeshes) is separate data
// and is not touched.
//
// No scan of all objects: a UObject-creation listener notes each new UNavCollision (any thread, under a lock), and the
// game thread frees the noted ones once a second, keeping those still loading for the next pass.
//   ok.TrimNavCollision  -1 (default): on in low-memory mode, off otherwise; 1 on; 0 off.
#include "CoreMinimal.h"
#include "Containers/Ticker.h"
#include "HAL/IConsoleManager.h"
#include "HAL/PlatformTime.h"
#include "Misc/CoreDelegates.h"
#include "Misc/ScopeLock.h"
#include "NavCollision.h"
#include "UObject/UObjectArray.h"
#include "KKRuntimeMaterial.h"

namespace {
int32 GTrimNavCollision = -1;
FAutoConsoleVariableRef CVarTrimNavCollision(TEXT("ok.TrimNavCollision"), GTrimNavCollision,
	TEXT("Free the navigation collision of loaded static meshes (this game builds no navigation mesh). -1: in low-memory mode; 1: on; 0: off."));

bool Enabled() { return GTrimNavCollision < 0 ? OKRuntimeLowMemory() : GTrimNavCollision > 0; }

int64 Release(FNavCollisionConvex& C) {
	const int64 Bytes = int64(C.VertexBuffer.GetAllocatedSize()) + int64(C.IndexBuffer.GetAllocatedSize());
	C.VertexBuffer.Empty(); C.IndexBuffer.Empty();
	return Bytes;
}

class FTrimmer final : public FUObjectArray::FUObjectCreateListener {
public:
	void Start() {
		GUObjectArray.AddUObjectCreateListener(this);
		Ticker = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateRaw(this, &FTrimmer::Tick), 1.f);
	}
	virtual void NotifyUObjectCreated(const UObjectBase* Object, int32 Index) override {
		// Called as each object is allocated, from whichever thread loads it; the class is already set.
		if (!Object->GetClass()->IsChildOf(UNavCollision::StaticClass()) || !Enabled()) return;
		FScopeLock Lock(&Guard);
		Noted.Add(FWeakObjectPtr(static_cast<const UObject*>(Object)));
	}
	virtual void OnUObjectArrayShutdown() override {
		GUObjectArray.RemoveUObjectCreateListener(this);
		FTSTicker::GetCoreTicker().RemoveTicker(Ticker);
	}

private:
	bool Tick(float) {
		QUICK_SCOPE_CYCLE_COUNTER(STAT_OK_TrimNavCollision);
		const double Start = FPlatformTime::Seconds();
		TArray<FWeakObjectPtr> Batch;
		{ FScopeLock Lock(&Guard); Swap(Batch, Noted); }
		if (Batch.IsEmpty()) return true;
		TArray<FWeakObjectPtr> Later;
		int32 Freed = 0;
		for (const FWeakObjectPtr& Weak : Batch) {
			UNavCollision* Nav = Cast<UNavCollision>(Weak.Get());
			if (!Nav || Nav->HasAnyFlags(RF_ClassDefaultObject)) continue;
			// Still loading (async, or awaiting PostLoad): its Setup decodes the cooked data after us; next pass.
			if (Nav->HasAnyFlags(RF_NeedLoad | RF_NeedPostLoad) || Nav->HasAnyInternalFlags(EInternalObjectFlags::Async)) { Later.Add(Weak); continue; }
			int64 Bytes = Release(Nav->GetMutableTriMeshCollision()) + Release(Nav->GetMutableConvexCollision());
			TArray<FName> Formats;
			Nav->CookedFormatData.GetContainedFormats(Formats);
			for (const FName& F : Formats) Bytes += Nav->CookedFormatData.GetFormat(F).GetBulkDataSize();
			if (!Formats.IsEmpty()) Nav->CookedFormatData.FlushData();
			if (Bytes > 0) { TrimmedBytes += Bytes; ++TrimmedMeshes; ++Freed; }
		}
		if (!Later.IsEmpty()) { FScopeLock Lock(&Guard); Noted.Append(MoveTemp(Later)); }
		const double Ms = (FPlatformTime::Seconds() - Start) * 1000.;
		MaxPassMs = FMath::Max(MaxPassMs, Ms);
		if (Freed && (TrimmedBytes - LoggedBytes >= (64ll << 20) || LoggedBytes == 0)) {
			LoggedBytes = TrimmedBytes;
			UE_LOG(LogTemp, Display, TEXT("Low-memory mode: navigation collision freed for %d meshes, %.0f MB so far (this pass %d meshes %.2f ms, longest pass %.2f ms; ok.TrimNavCollision)"),
				TrimmedMeshes, double(TrimmedBytes) / (1 << 20), Freed, Ms, MaxPassMs);
		}
		return true;
	}

	FCriticalSection Guard;
	TArray<FWeakObjectPtr> Noted;
	FTSTicker::FDelegateHandle Ticker;
	int64 TrimmedBytes = 0, LoggedBytes = 0;
	int32 TrimmedMeshes = 0;
	double MaxPassMs = 0;
};
FTrimmer GTrimmer;
}

void OKStartNavCollisionTrim() {
	FCoreDelegates::GetOnPostEngineInit().AddLambda([]() { GTrimmer.Start(); });
}
