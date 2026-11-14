// Memory and machine lines in game.log, so a crash on a tester's PC can be read from the log alone
// (Docs/STREET_CITY_STREAMING_LOWSPEC_20261114.md):
//   OKMachine  once the RHI is up: CPU, RAM, commit limit, GPU, driver, VRAM, low-memory mode, stage, patch
//   OKMem      every 30 s (-OKMemLogSeconds=N, 0 = off): this process's commit and working set, the system's free commit,
//              this process's VRAM use against the driver's budget (DXGI), loaded streaming levels, installed characters
//   warnings   VRAM over the driver budget, under 2 GB of free system commit
//   an OKMem line at Error when an allocation fails (the engine's out-of-memory delegate), flushed before the engine dies
// The log is flushed after each line: a process killed by the OS or the driver keeps what it wrote.
#include "CoreMinimal.h"
#include <atomic>
#include "Containers/Ticker.h"
#include "HAL/PlatformMemory.h"
#include "HAL/PlatformMisc.h"
#include "Misc/CommandLine.h"
#include "Misc/CoreDelegates.h"
#include "Misc/OutputDeviceRedirector.h"
#include "Misc/Parse.h"
#include "RHI.h"
#include "RHIGlobals.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/LevelStreaming.h"
#include "KKRuntimeMaterial.h"
#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include <dxgi1_4.h>
#include "Windows/HideWindowsPlatformTypes.h"
#endif

// Characters installed in the runtime scene (OKCrowdRuntimeScene.cpp keeps it current).
std::atomic<int32> GOKRuntimeCharactersInstalled{0};

namespace {
#if PLATFORM_WINDOWS
// The adapter the game renders on (the one with the most dedicated memory), loaded at run time: no link dependency.
IDXGIAdapter3* Adapter() {
	static IDXGIAdapter3* Cached = nullptr; static bool Tried = false;
	if (Tried) return Cached; Tried = true;
	HMODULE Dxgi = ::LoadLibraryW(L"dxgi.dll"); if (!Dxgi) return nullptr;
	using FCreate = HRESULT(WINAPI*)(REFIID, void**);
	auto Create = reinterpret_cast<FCreate>(::GetProcAddress(Dxgi, "CreateDXGIFactory1")); if (!Create) return nullptr;
	IDXGIFactory1* Factory = nullptr; if (FAILED(Create(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&Factory))) || !Factory) return nullptr;
	SIZE_T Best = 0; IDXGIAdapter1* A = nullptr;
	for (UINT I = 0; Factory->EnumAdapters1(I, &A) != DXGI_ERROR_NOT_FOUND; ++I) {
		DXGI_ADAPTER_DESC1 D; A->GetDesc1(&D);
		IDXGIAdapter3* A3 = nullptr;
		if (!(D.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) && D.DedicatedVideoMemory > Best && SUCCEEDED(A->QueryInterface(__uuidof(IDXGIAdapter3), reinterpret_cast<void**>(&A3)))) {
			if (Cached) Cached->Release(); Cached = A3; Best = D.DedicatedVideoMemory;
		}
		A->Release();
	}
	Factory->Release();
	return Cached;
}
#endif

double Gb(uint64 Bytes) { return double(Bytes) / (1024.0 * 1024.0 * 1024.0); }

struct FSample { uint64 Commit = 0, PeakCommit = 0, WorkingSet = 0, FreeCommit = 0, CommitLimit = 0, Vram = 0, VramBudget = 0, Dedicated = 0; };

FSample Sample() {
	FSample S;
	const FPlatformMemoryStats M = FPlatformMemory::GetStats();
	S.Commit = M.UsedVirtual; S.PeakCommit = M.PeakUsedVirtual; S.WorkingSet = M.UsedPhysical;
#if PLATFORM_WINDOWS
	MEMORYSTATUSEX Status; Status.dwLength = sizeof(Status);
	if (::GlobalMemoryStatusEx(&Status)) { S.FreeCommit = Status.ullAvailPageFile; S.CommitLimit = Status.ullTotalPageFile; }
	if (IDXGIAdapter3* A = Adapter()) {
		DXGI_QUERY_VIDEO_MEMORY_INFO Info;
		if (SUCCEEDED(A->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &Info))) { S.Vram = Info.CurrentUsage; S.VramBudget = Info.Budget; }
		DXGI_ADAPTER_DESC D; if (SUCCEEDED(A->GetDesc(&D))) S.Dedicated = D.DedicatedVideoMemory;
	}
#endif
	return S;
}

int32 LoadedLevels() {
	int32 N = 0;
	if (GEngine) for (const FWorldContext& C : GEngine->GetWorldContexts()) {
		UWorld* W = C.World(); if (!W || !W->IsGameWorld()) continue;
		for (ULevelStreaming* L : W->GetStreamingLevels()) if (L && L->IsLevelLoaded()) ++N;
	}
	return N;
}

FString Line(const FSample& S) {
	return FString::Printf(TEXT("OKMem: commit %.2f GB (peak %.2f), working set %.2f GB, system free commit %.1f of %.1f GB, VRAM %.2f GB of budget %.2f GB, streaming levels loaded %d, characters %d"),
		Gb(S.Commit), Gb(S.PeakCommit), Gb(S.WorkingSet), Gb(S.FreeCommit), Gb(S.CommitLimit), Gb(S.Vram), Gb(S.VramBudget), LoadedLevels(), GOKRuntimeCharactersInstalled.load());
}

void LogMachine() {
	const FPlatformMemoryConstants& C = FPlatformMemory::GetConstants();
	const FSample S = Sample();
	FString Stage, Patch;
	FParse::Value(FCommandLine::Get(), TEXT("OKStage="), Stage);
	FParse::Value(FCommandLine::Get(), TEXT("pakdir="), Patch);
	UE_LOG(LogTemp, Display, TEXT("OKMachine: CPU %s (%d cores, %d threads), RAM %.1f GB, commit limit %.1f GB, GPU %s (driver %s, %s), VRAM %.1f GB (budget %.1f GB), low-memory %s, stage %s, patch %s"),
		*FPlatformMisc::GetCPUBrand().TrimStartAndEnd(), FPlatformMisc::NumberOfCores(), FPlatformMisc::NumberOfCoresIncludingHyperthreads(),
		Gb(C.TotalPhysical), Gb(S.CommitLimit), *GRHIAdapterName, *GRHIAdapterUserDriverVersion, GDynamicRHI ? GDynamicRHI->GetName() : TEXT("no RHI"),
		Gb(S.Dedicated), Gb(S.VramBudget), OKRuntimeLowMemory() ? TEXT("on") : TEXT("off"),
		Stage.IsEmpty() ? TEXT("(none)") : *Stage, Patch.IsEmpty() ? TEXT("(none)") : *Patch);
	GLog->Flush();
}
}

void OKStartMemoryDiagnostics() {
	if (GIsEditor && !IsRunningGame()) return;
	float Seconds = 30.f; FParse::Value(FCommandLine::Get(), TEXT("OKMemLogSeconds="), Seconds);
	FCoreDelegates::GetOnPostEngineInit().AddLambda([Seconds]() {
		LogMachine();
		if (Seconds <= 0.f) return;
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([](float) {
			const FSample S = Sample();
			UE_LOG(LogTemp, Display, TEXT("%s"), *Line(S));
			if (S.VramBudget && S.Vram > S.VramBudget) UE_LOG(LogTemp, Warning, TEXT("OKMem: VRAM %.2f GB is over the driver budget %.2f GB (textures may be evicted; the driver can stall or reset)"), Gb(S.Vram), Gb(S.VramBudget));
			if (S.CommitLimit && S.FreeCommit < (2ull << 30)) UE_LOG(LogTemp, Warning, TEXT("OKMem: system free commit %.2f GB: close to out of memory (raise the page file or close other programs)"), Gb(S.FreeCommit));
			GLog->Flush();
			return true;
		}), Seconds);
	});
	// An allocation that failed: the engine logs it and dies; this line says how much was in use when it happened.
	FCoreDelegates::GetOutOfMemoryDelegate().AddLambda([]() {
		UE_LOG(LogTemp, Error, TEXT("Out of memory. %s"), *Line(Sample()));
		GLog->Flush();
	});
}
