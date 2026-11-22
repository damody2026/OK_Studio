// OK mod framework work item 3 (Docs/OK_MOD_S3_材質可行性.md): proves in the packaged game that a mod's cooked material
// pak (Tools/modkit_cook.lua) loads from Mods/<id>/content/ — not Content/Paks — and draws with its own shader library.
// Development only; work items 6/9 (Plugins/OKModding, the material mod) take the mount/OpenLibrary/load order over.
//
//   ok.ModMaterialProbe Mod=<id> [Pak=<file>] [Library=<name>] [Assets=<obj path>+<obj path>] [NoLibrary=1]
//                       [Shot=<png>] [Quit=1]
// Pak defaults to <project>/Mods/<id>/content/<id>.pak, Library to OKModCook_<id> (the cook host's project name).
// Order (§6.11): mount the pak at a low order -> register the package root /<id>/ -> OpenLibrary -> load the materials.
// NoLibrary=1 skips OpenLibrary (the negative control: the material then has no shaders and falls back).
// Each asset goes on a plane 2.5 m in front of the camera; log lines start with OKMODPROBE.
#if !UE_BUILD_SHIPPING
#include "CoreMinimal.h"
#include "HAL/IConsoleManager.h"
#include "HAL/PlatformFileManager.h"
#include "Misc/CoreDelegates.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Containers/Ticker.h"
#include "ShaderCodeLibrary.h"
#include "Materials/MaterialInterface.h"
#include "Materials/Material.h"
#include "MaterialShared.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/PlayerController.h"
#include "UnrealClient.h"
#include "RHIGlobals.h"

DEFINE_LOG_CATEGORY_STATIC(LogOKModProbe, Log, All);

namespace OKModMaterialProbe
{
static FString Arg(const TArray<FString>& Args, const TCHAR* Key, const FString& Default = FString())
{
	const FString Prefix = FString(Key) + TEXT("=");
	for (const FString& A : Args) if (A.StartsWith(Prefix, ESearchCase::IgnoreCase)) return A.Mid(Prefix.Len());
	return Default;
}

static void Run(const TArray<FString>& Args, UWorld* World)
{
	const FString Mod = Arg(Args, TEXT("Mod"));
	if (Mod.IsEmpty() || !World) { UE_LOG(LogOKModProbe, Error, TEXT("OKMODPROBE usage: ok.ModMaterialProbe Mod=<id> [Pak=] [Library=] [Assets=a+b] [NoLibrary=1] [Shot=] [Quit=1]")); return; }
	const FString Pak = FPaths::ConvertRelativePathToFull(Arg(Args, TEXT("Pak"), FPaths::ProjectDir() / TEXT("Mods") / Mod / TEXT("content") / Mod + TEXT(".pak")));
	const FString Library = Arg(Args, TEXT("Library"), TEXT("OKModCook_") + Mod);
	const bool bNoLibrary = Arg(Args, TEXT("NoLibrary")) == TEXT("1");
	// The pak's mount point (Tools/modkit_cook.lua): ../../../<project>/Mods/<id>/Content/.
	const FString MountDir = FPaths::ProjectDir() / TEXT("Mods") / Mod / TEXT("Content/");
	UE_LOG(LogOKModProbe, Display, TEXT("OKMODPROBE mod=%s pak=%s exists=%d mount=%s library=%s nolibrary=%d"), *Mod, *Pak, FPaths::FileExists(Pak), *MountDir, *Library, bNoLibrary);

	// 1. mount, lowest order: a mod never wins over the game's own paks.
	if (!FCoreDelegates::MountPak.IsBound()) { UE_LOG(LogOKModProbe, Error, TEXT("OKMODPROBE no pak platform file (not a packaged game?)")); return; }
	IPakFile* Mounted = FCoreDelegates::MountPak.Execute(Pak, 0);
	UE_LOG(LogOKModProbe, Display, TEXT("OKMODPROBE mounted=%d"), Mounted != nullptr);
	if (!Mounted) return;
	// 2. the package root (the plugin's mount root in the editor) points at the pak's folder.
	const FString Root = TEXT("/") + Mod + TEXT("/");
	if (!FPackageName::MountPointExists(Root)) FPackageName::RegisterMountPoint(Root, MountDir);
	// 3. the mod's shader library BEFORE any of its materials is serialized (2026-11-17: loaded first, they keep the
	// default material for the whole run).
	bool bOpened = false;
	if (!bNoLibrary) bOpened = FShaderCodeLibrary::OpenLibrary(Library, MountDir);
	UE_LOG(LogOKModProbe, Display, TEXT("OKMODPROBE open library %s in %s -> %d"), *Library, *MountDir, bOpened);

	// 4. load and show.
	TArray<FString> Assets;
	Arg(Args, TEXT("Assets"), FString::Printf(TEXT("/%s/M_OKModSample.M_OKModSample+/%s/MI_OKModSample.MI_OKModSample"), *Mod, *Mod)).ParseIntoArray(Assets, TEXT("+"));
	UStaticMesh* Plane = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Plane.Plane"));
	FVector Eye = FVector::ZeroVector; FRotator View = FRotator::ZeroRotator;
	if (APlayerController* PC = World->GetFirstPlayerController()) PC->GetPlayerViewPoint(Eye, View);
	const FVector Forward = View.Vector(), Right = FRotationMatrix(View).GetUnitAxis(EAxis::Y);
	int32 Index = 0, Drawn = 0;
	for (const FString& Asset : Assets)
	{
		UMaterialInterface* Material = LoadObject<UMaterialInterface>(nullptr, *Asset);
		const FMaterialResource* Resource = Material ? Material->GetMaterialResource(GMaxRHIShaderPlatform) : nullptr;
		const bool bShaderMap = Resource && Resource->GetGameThreadShaderMap() != nullptr;
		const UMaterial* Base = Material ? Material->GetMaterial() : nullptr;
		const bool bDefault = Base && Base->IsDefaultMaterial();
		UE_LOG(LogOKModProbe, Display, TEXT("OKMODPROBE asset=%s loaded=%d class=%s base=%s shadermap=%d default=%d platform=%s"), *Asset, Material != nullptr,
			Material ? *Material->GetClass()->GetName() : TEXT("-"), Base ? *Base->GetPathName() : TEXT("-"), bShaderMap, bDefault,
			*LexToString(GMaxRHIShaderPlatform));
		if (Material && bShaderMap && !bDefault) ++Drawn;
		if (!Plane || !Material) { ++Index; continue; }
		const float Offset = (Index - (Assets.Num() - 1) * .5f) * 220.f;
		const FVector At = Eye + Forward * 300.f + Right * Offset;
		FActorSpawnParameters Params; Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		AStaticMeshActor* Actor = World->SpawnActor<AStaticMeshActor>(At, FRotationMatrix::MakeFromZ(-Forward).Rotator(), Params);
		if (Actor)
		{
			Actor->GetStaticMeshComponent()->SetMobility(EComponentMobility::Movable);
			Actor->GetStaticMeshComponent()->SetStaticMesh(Plane);
			Actor->GetStaticMeshComponent()->SetMaterial(0, Material);
			Actor->SetActorScale3D(FVector(2.f));
		}
		++Index;
	}
	UE_LOG(LogOKModProbe, Display, TEXT("OKMODPROBE result drawn_with_mod_shaders=%d of %d plane=%d"), Drawn, Assets.Num(), Plane != nullptr);

	const FString Shot = Arg(Args, TEXT("Shot"));
	const bool bQuit = Arg(Args, TEXT("Quit")) == TEXT("1");
	if (!Shot.IsEmpty() || bQuit)
	{
		// A few frames for the planes to reach the renderer, then the shot, then the exit.
		const double Start = FPlatformTime::Seconds();
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Shot, bQuit, Start, bShot = false](float) mutable
		{
			const double Age = FPlatformTime::Seconds() - Start;
			if (!bShot && Age > 3.0)
			{
				bShot = true;
				if (!Shot.IsEmpty()) { FScreenshotRequest::RequestScreenshot(Shot, false, false); UE_LOG(LogOKModProbe, Display, TEXT("OKMODPROBE screenshot %s"), *Shot); }
			}
			if (bQuit && Age > 6.0) { UE_LOG(LogOKModProbe, Display, TEXT("OKMODPROBE quit")); FPlatformMisc::RequestExit(false, TEXT("ok.ModMaterialProbe")); return false; }
			return !bQuit || Age <= 6.0;
		}), .25f);
	}
}

static FAutoConsoleCommandWithWorldAndArgs Command(TEXT("ok.ModMaterialProbe"),
	TEXT("Mount a mod material pak from Mods/<id>/content, open its shader library, show its materials (Mod=<id> [Pak=] [Library=] [Assets=a+b] [NoLibrary=1] [Shot=<png>] [Quit=1])"),
	FConsoleCommandWithWorldAndArgsDelegate::CreateLambda([](const TArray<FString>& Args, UWorld* World) { Run(Args, World); }));
}
#endif
