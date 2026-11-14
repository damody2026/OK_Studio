#include "OpenKoikatsu.h"
#include "OKGameControl.h"
#include "Modules/ModuleManager.h"
#include "NiagaraModule.h"
#include "HAL/IConsoleManager.h"
#include "Misc/CoreDelegates.h"
#include "WorldPartition/WorldPartitionSubsystem.h"
#include "KKRuntimeMaterial.h"
#include "Engine/Engine.h"
#include "Engine/World.h"

void OKHSceneInstallPrecacheAhead(); // OKHScene.h

class FOpenKoikatsuModule final : public FDefaultGameModuleImpl {
public:
    virtual void StartupModule() override {
        FDefaultGameModuleImpl::StartupModule();
        // Gameplay-owned effects need Niagara's template and world lifecycle
        // registrations before any World is created, including minimal runtime stages.
        FModuleManager::LoadModuleChecked<INiagaraModule>(TEXT("Niagara"));
        OKGameControl::Start();
        // Every mode (street, card reader, studio): shaders never compile in a frame that waits for them. A draw whose PSO
        // is still compiling (precached late, a cold driver cache) is left out of that frame instead of the frame waiting,
        // 100-200 ms each at the one-on-one's start (user 2026-11-12: a one-off event must not hold up frame generation).
        // Command line and console still override. And the H scene's _Bias twins precached as a high model loads.
        FCoreDelegates::GetOnPostEngineInit().AddLambda([]() {
            if (auto* V = IConsoleManager::Get().FindConsoleVariable(TEXT("r.SkipDrawOnPSOPrecaching"))) V->Set(1, ECVF_SetByProjectSetting);
            OKHSceneInstallPrecacheAhead();
        });
        // Streamed map (UniversityCityWP): -StreetCityLoadingRange=N (cm), or 128 m on a low-memory PC (OKRuntimeLowMemory),
        // in place of the map's 256 m. Set as each partitioned game world starts: the engine forgets the override whenever a
        // world goes (a save loaded reopens the map), so a console command at launch only held until then
        // (Docs/STREET_CITY_STREAMING_LOWSPEC_20261114.md).
        UWorldPartitionSubsystem::OnWorldPartitionSubsystemInitialized.AddLambda([](UWorldPartitionSubsystem*, UWorld* World) {
            if (!World || !World->IsGameWorld() || !GEngine) return;
            int32 Range = OKRuntimeLowMemory() ? 12800 : 0;
            FParse::Value(FCommandLine::Get(), TEXT("StreetCityLoadingRange="), Range);
            if (Range <= 0) return;
            GEngine->Exec(World, *FString::Printf(TEXT("wp.Runtime.OverrideRuntimeSpatialHashLoadingRange -grid=0 -range=%d"), Range));
            UE_LOG(LogTemp, Display, TEXT("Streamed map loading range %d cm"), Range);
        });
    }
};
// Primary module of this project (OK_Demo had its own primary module and used IMPLEMENT_GAME_MODULE here).
IMPLEMENT_PRIMARY_GAME_MODULE(FOpenKoikatsuModule, OpenKoikatsu, "OpenKoikatsu");
