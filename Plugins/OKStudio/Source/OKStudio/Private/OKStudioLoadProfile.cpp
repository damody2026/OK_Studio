// Measures what opening a scene costs, from the file to a scene that is completely built and can be worked on:
// OKStudio.ProfileSceneLoad [repeats] [exit]. The scenes come from the file named by OK_SCENE_PROFILE_LIST (one path a
// line, # comments), each loaded `repeats` times in a row (the first is this process's cold open of it, the rest hot),
// and the rows go to Saved/Reports/scene-load/<OK_SCENE_PROFILE_TAG or the time>.json.
//
// Stages (milliseconds): load_call (FOKSceneCard::Open plus releasing the last scene, one blocking call), build (the
// frames after it until nothing is pending: characters, items, the map), and ready = the two together. The scene
// actor's own LoadStats say where the build time went (character open on the worker, Build() by kind, the map).
#include "OKStudioGame.h"

#include "OKSceneActor.h"
#include "OKSceneDocument.h"
#include "KKPreviewActor.h"
#include "Components/SkinnedMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Containers/Ticker.h"
#include "Dom/JsonObject.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/DateTime.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "UnrealClient.h"
#include "ShaderCompiler.h"

namespace
{
	struct FSceneLoadProfile
	{
		TArray<FString> Scenes;
		int32 Repeats = 3;
		bool bExit = false;
		FString Out;

		int32 Scene = 0, Pass = 0;
		bool bLoading = false;
		double Start = 0., LoadCallMs = 0.;
		int32 Frames = 0, ShotWait = 0, ShotExtra = 0;
		FString ShotPath;
		double PeakUsedGb = 0.;
		TArray<TSharedPtr<FJsonValue>> Rows;

		/** OK_SCENE_PROFILE_DUMP=1: what the built scene is, so two runs can be compared object by object. Opening a
		 *  card is not bit-for-bit repeatable (Docs/ERROR_LOG.md I-014), so this is the object list, the world
		 *  transforms, the parts and components of each preview, and the errors: what an optimisation must not change. */
		static void Dump(const UOKStudioGame& Game, const FString& Path)
		{
			const AOKSceneActor* Actor = Game.SceneActor;
			if (!Actor || !Game.Document) return;
			TArray<TSharedPtr<FJsonValue>> Objects;
			for (const FOKSceneObject& O : Game.Document->Objects)
			{
				const FTransform World = Game.Document->WorldTransform(O.Id) * Actor->GetActorTransform();
				auto J = MakeShared<FJsonObject>();
				J->SetNumberField(TEXT("id"), O.Id);
				J->SetNumberField(TEXT("kind"), int32(O.Kind));
				J->SetStringField(TEXT("name"), O.Name);
				J->SetStringField(TEXT("world"), World.ToString());
				if (const FString* Error = Actor->Errors.Find(O.Id)) J->SetStringField(TEXT("error"), *Error);
				if (const AKKPreviewActor* Preview = Actor->PreviewOf(O.Id))
				{
					J->SetNumberField(TEXT("parts"), Preview->Session.PartCount());
					int32 Skinned = 0, Static = 0, Hidden = 0;
					TInlineComponentArray<UPrimitiveComponent*> Primitives(Preview);
					for (const UPrimitiveComponent* C : Primitives)
					{
						if (!C->IsVisible()) { ++Hidden; continue; }
						if (C->IsA<USkinnedMeshComponent>()) ++Skinned; else if (C->IsA<UStaticMeshComponent>()) ++Static;
					}
					J->SetNumberField(TEXT("skinned"), Skinned);
					J->SetNumberField(TEXT("static"), Static);
					J->SetNumberField(TEXT("hidden"), Hidden);
					J->SetStringField(TEXT("preview_world"), Preview->GetActorTransform().ToString());
				}
				Objects.Add(MakeShared<FJsonValueObject>(J));
			}
			auto Root = MakeShared<FJsonObject>();
			Root->SetNumberField(TEXT("map"), Game.Document->Map);
			Root->SetNumberField(TEXT("map_parts"), Actor->MapPartCount());
			Root->SetStringField(TEXT("map_error"), Actor->MapError);
			Root->SetArrayField(TEXT("objects"), Objects);
			FString Json;
			FJsonSerializer::Serialize(Root, TJsonWriterFactory<>::Create(&Json));
			IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path), true);
			FFileHelper::SaveStringToFile(Json, *Path, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
			UE_LOG(LogTemp, Display, TEXT("OK studio scene load: dump %s"), *Path);
		}

		/** True when the scene is completely built: no object or map waiting for a later frame. */
		static bool Ready(const UOKStudioGame& Game)
		{
			const AOKSceneActor* Actor = Game.SceneActor;
			return Actor && !Actor->HasPendingBuilds() && Actor->PreparingMap() < 0;
		}

		void Finish()
		{
			FString Json;
			FJsonSerializer::Serialize(Rows, TJsonWriterFactory<>::Create(&Json));
			IFileManager::Get().MakeDirectory(*FPaths::GetPath(Out), true);
			FFileHelper::SaveStringToFile(Json, *Out, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
			UE_LOG(LogTemp, Display, TEXT("OK studio scene load: RESULT %d rows into %s"), Rows.Num(), *Out);
		}

		/** One tick of the run; false when every scene is measured. */
		bool Tick(UOKStudioGame& Game)
		{
			// OK_SCENE_PROFILE_SHOT=1: a few frames after the scene is up, a picture of it beside the rows, so two runs
			// can be looked at as well as compared number by number.
			if (ShotWait > 0)
			{
				// Still settling; the shader compiler is given its time too, then the picture, then a few frames for it
				// to be written before the next scene replaces what is on screen.
				if (--ShotWait > 0 || (GShaderCompilingManager && GShaderCompilingManager->IsCompiling() && ++ShotExtra < 600)) { if (ShotWait <= 0) ShotWait = 1; return true; }
				if (!ShotPath.IsEmpty()) { FScreenshotRequest::RequestScreenshot(ShotPath, false, false); ShotPath.Reset(); ShotWait = 5; }
				return true;
			}
			if (bLoading)
			{
				++Frames;
				// A bigger per-frame budget builds more at once: the memory the renderer has not freed yet is the risk.
				PeakUsedGb = FMath::Max(PeakUsedGb, FPlatformMemory::GetStats().UsedPhysical / double(1 << 30));
				if (!Ready(Game)) return true;
				const double ReadyMs = (FPlatformTime::Seconds() - Start) * 1000.;
				const AOKSceneActor::FLoadStats& S = Game.SceneActor->LoadStats;
				auto Row = MakeShared<FJsonObject>();
				Row->SetStringField(TEXT("scene"), FPaths::GetCleanFilename(Scenes[Scene]));
				Row->SetNumberField(TEXT("pass"), Pass); // 0 is this process's first open of the scene
				Row->SetNumberField(TEXT("ready_ms"), ReadyMs);
				Row->SetNumberField(TEXT("load_call_ms"), LoadCallMs);
				Row->SetNumberField(TEXT("build_ms"), ReadyMs - LoadCallMs);
				Row->SetNumberField(TEXT("build_frames"), Frames);
				Row->SetNumberField(TEXT("peak_used_gb"), PeakUsedGb);
				Row->SetNumberField(TEXT("character_open_ms"), S.CharacterOpenMs);
				Row->SetNumberField(TEXT("character_continue_ms"), S.CharacterContinueMs);
				Row->SetNumberField(TEXT("character_build_ms"), S.CharacterBuildMs);
				Row->SetNumberField(TEXT("item_build_ms"), S.ItemBuildMs);
				Row->SetNumberField(TEXT("item_model_ms"), S.ItemModelMs);
				Row->SetNumberField(TEXT("item_open_ms"), S.ItemOpenMs);
				Row->SetNumberField(TEXT("item_open_worker_ms"), S.ItemOpenWorkerMs);
				Row->SetNumberField(TEXT("item_spawn_ms"), S.ItemSpawnMs);
				Row->SetNumberField(TEXT("item_node_world_ms"), S.ItemNodeWorldMs);
				Row->SetNumberField(TEXT("item_cameras_ms"), S.ItemCamerasMs);
				Row->SetNumberField(TEXT("other_build_ms"), S.OtherBuildMs);
				Row->SetNumberField(TEXT("map_continue_ms"), S.MapContinueMs);
				Row->SetNumberField(TEXT("sync_ms"), S.SyncMs);
				Row->SetNumberField(TEXT("wire_ms"), S.WireMs);
				Row->SetNumberField(TEXT("sync_same_ms"), S.SyncSameMs);
				Row->SetNumberField(TEXT("sync_world_ms"), S.SyncWorldMs);
				Row->SetNumberField(TEXT("sync_place_ms"), S.SyncPlaceMs);
				Row->SetNumberField(TEXT("placement_writes"), S.PlacementWrites);
				Row->SetNumberField(TEXT("placement_skips"), S.PlacementSkips);
				Row->SetNumberField(TEXT("characters"), S.Characters);
				Row->SetNumberField(TEXT("items"), S.Items);
				Row->SetNumberField(TEXT("others"), S.Others);
				Row->SetNumberField(TEXT("syncs"), S.Syncs);
				Row->SetNumberField(TEXT("starved_syncs"), S.StarvedSyncs);
				Row->SetNumberField(TEXT("objects"), Game.Document ? Game.Document->Objects.Num() : 0);
				Rows.Add(MakeShared<FJsonValueObject>(Row));
				UE_LOG(LogTemp, Display, TEXT("OK studio scene load: %s pass=%d ready=%.0f ms (open+release=%.0f build=%.0f over %d frames) chars=%d (open=%.0f continue=%.0f build=%.0f) items=%d (build=%.0f: model=%.0f open=%.0f worker_open=%.0f spawn=%.0f node=%.0f cameras=%.0f) map=%.0f starved=%d/%d"),
					*FPaths::GetCleanFilename(Scenes[Scene]), Pass, ReadyMs, LoadCallMs, ReadyMs - LoadCallMs, Frames,
					S.Characters, S.CharacterOpenMs, S.CharacterContinueMs, S.CharacterBuildMs, S.Items, S.ItemBuildMs,
					S.ItemModelMs, S.ItemOpenMs, S.ItemOpenWorkerMs, S.ItemSpawnMs, S.ItemNodeWorldMs, S.ItemCamerasMs, S.MapContinueMs, S.StarvedSyncs, S.Syncs);
				UE_LOG(LogTemp, Display, TEXT("OK studio scene load: %s pass=%d sync=%.0f ms of %.0f (wire=%.0f, outside Sync %.0f); walk: same=%.0f world=%.0f place=%.0f (moved %d, left alone %d)"),
					*FPaths::GetCleanFilename(Scenes[Scene]), Pass, S.SyncMs, ReadyMs, S.WireMs, ReadyMs - LoadCallMs - S.SyncMs,
					S.SyncSameMs, S.SyncWorldMs, S.SyncPlaceMs, S.PlacementWrites, S.PlacementSkips);
				UE_LOG(LogTemp, Display, TEXT("OK studio scene load: %s pass=%d peak memory %.1f GB"), *FPaths::GetCleanFilename(Scenes[Scene]), Pass, PeakUsedGb);
				if (FPlatformMisc::GetEnvironmentVariable(TEXT("OK_SCENE_PROFILE_SHOT")) == TEXT("1"))
				{
					// Not the frame the build ends on: the runtime materials are still being made then, and a picture of
					// that compares how far they got, not the scene. OK_SCENE_PROFILE_SHOT_FRAMES sets the wait.
					const int32 Wait = FCString::Atoi(*FPlatformMisc::GetEnvironmentVariable(TEXT("OK_SCENE_PROFILE_SHOT_FRAMES")));
					ShotWait = Wait > 1 ? Wait : 240;
					ShotPath = FPaths::GetPath(Out) / FPaths::GetBaseFilename(Out) + FString::Printf(TEXT("_%s_pass%d.png"), *FPaths::GetBaseFilename(Scenes[Scene]), Pass);
				}
				if (FPlatformMisc::GetEnvironmentVariable(TEXT("OK_SCENE_PROFILE_DUMP")) == TEXT("1"))
					Dump(Game, FPaths::GetPath(Out) / FPaths::GetBaseFilename(Out) + FString::Printf(TEXT("_%s_pass%d.json"), *FPaths::GetBaseFilename(Scenes[Scene]), Pass));
				bLoading = false;
				if (++Pass >= Repeats) { Pass = 0; ++Scene; }
				if (ShotWait > 0) return true; // the picture is written over the next frames, before the next scene replaces it
			}
			if (Scene >= Scenes.Num()) { Finish(); return false; }
			// The stats belong to this load alone; the clock starts with the blocking call a click makes.
			if (Game.SceneActor) Game.SceneActor->LoadStats = AOKSceneActor::FLoadStats();
			FString Error;
			Frames = 0;
			PeakUsedGb = 0.;
			ShotExtra = 0;
			ShotPath.Reset();
			Start = FPlatformTime::Seconds();
			const bool bOpened = Game.Load(Scenes[Scene], Error);
			LoadCallMs = (FPlatformTime::Seconds() - Start) * 1000.;
			if (!bOpened)
			{
				UE_LOG(LogTemp, Warning, TEXT("OK studio scene load: %s not opened: %s"), *Scenes[Scene], *Error);
				Pass = 0;
				++Scene;
				return true;
			}
			bLoading = true;
			return true;
		}
	};

	FAutoConsoleCommand ProfileSceneLoadCommand(TEXT("OKStudio.ProfileSceneLoad"),
		TEXT("OKStudio.ProfileSceneLoad [repeats] [exit]: how long each scene of OK_SCENE_PROFILE_LIST takes from the file to a built scene (Saved/Reports/scene-load; OK_SCENE_PROFILE_TAG names the file)."),
		FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
		{
			const FString ListFile = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_SCENE_PROFILE_LIST"));
			TArray<FString> Lines;
			if (ListFile.IsEmpty() || !FFileHelper::LoadFileToStringArray(Lines, *ListFile))
			{
				UE_LOG(LogTemp, Error, TEXT("OKStudio.ProfileSceneLoad: OK_SCENE_PROFILE_LIST must name a readable list of scenes (%s)"), *ListFile);
				return;
			}
			TSharedRef<FSceneLoadProfile> Run = MakeShared<FSceneLoadProfile>();
			for (const FString& Line : Lines)
			{
				const FString Path = Line.TrimStartAndEnd();
				if (!Path.IsEmpty() && !Path.StartsWith(TEXT("#"))) Run->Scenes.Add(Path);
			}
			if (Run->Scenes.IsEmpty()) { UE_LOG(LogTemp, Error, TEXT("OKStudio.ProfileSceneLoad: %s lists no scene"), *ListFile); return; }
			Run->Repeats = Args.Num() > 0 && Args[0].IsNumeric() ? FMath::Clamp(FCString::Atoi(*Args[0]), 1, 20) : 3;
			Run->bExit = Args.Contains(TEXT("exit"));
			FString Tag = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_SCENE_PROFILE_TAG"));
			if (Tag.IsEmpty()) Tag = FDateTime::Now().ToString(TEXT("%Y%m%d_%H%M%S"));
			Run->Out = FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir() / TEXT("Reports/scene-load") / (Tag + TEXT(".json")));
			UE_LOG(LogTemp, Display, TEXT("OK studio scene load: %d scenes x %d passes -> %s"), Run->Scenes.Num(), Run->Repeats, *Run->Out);
			// The studio game mode (SceneEditor.cmd) runs its own studio; a few frames first so it is up.
			TSharedRef<int32> Frames = MakeShared<int32>(0);
			FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Run, Frames](float)
			{
				if (++*Frames < 30) return true;
				UOKStudioGame* Game = UOKStudioGame::Get();
				if (!Game)
				{
					UWorld* World = GEngine && GEngine->GameViewport ? GEngine->GameViewport->GetWorld() : nullptr;
					FString Error;
					Game = UOKStudioGame::Start(World, FString(), Error);
					if (!Game)
					{
						UE_LOG(LogTemp, Error, TEXT("OK studio scene load: %s"), *Error);
						if (Run->bExit) FPlatformMisc::RequestExit(false);
						return false;
					}
				}
				if (Run->Tick(*Game)) return true;
				if (Run->bExit) { Game->ReleaseSceneResources(); FPlatformMisc::RequestExit(false); }
				return false;
			}), 0.f);
		}));
}
