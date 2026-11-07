// Opt-in native validation. It is inert unless -CityEnvironmentAudit=<file> is supplied.
// Runs against the actual Game/PIE world and clock ticker, including cooked builds.
#include "CityEnvironmentRuntimeAudit.h"
#include "CityEnvironmentController.h"
#include "CityEnvironmentCelestial.h"
#include "CityEnvironmentTimeWidget.h"
#include "CityLanguage.h"
#include "Components/Button.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInterface.h"
#include "Components/Slider.h"
#include "Components/TextBlock.h"
#include "Components/EditableTextBox.h"
#include "UObject/UObjectIterator.h"
#include "RenderTimer.h"
#include "UnrealClient.h"
#include "CollisionShape.h"
#include "CityEnvironmentLog.h"
#include "Containers/Ticker.h"
#include "Dom/JsonObject.h"
#include "DynamicRHI.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerController.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "HAL/PlatformMisc.h"
#include "HAL/IConsoleManager.h"
#include "HAL/PlatformTime.h"
#include "Misc/App.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Modules/ModuleManager.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

namespace
{
 FTSTicker::FDelegateHandle AuditHandle;
 FString AuditOutput;
 TWeakObjectPtr<ACityEnvironmentController> AuditController;
 TWeakObjectPtr<ACameraActor> AuditCamera;
 TSharedPtr<FJsonObject> AuditReport;
 TArray<TSharedPtr<FJsonValue>> AuditSamples;
 FDateTime AuditCycleStart;
 double AuditStarted = 0, AuditPhaseStart = 0;
 int32 AuditPhase = -1, AuditLastHour = -1;
 bool AuditFailed = false;
 bool AuditScreenshotRequested = false;
 bool AuditPerformanceRequested = false;
 int32 AuditWarmFrames = 0;
 TArray<TSharedPtr<FJsonValue>> AuditProfilePairs;
 TSharedPtr<FJsonObject> AuditEnabledMetrics;
 bool AuditMotionRequested=false;
 int32 AuditMotionClip=0,AuditMotionFrame=0;
 double AuditMotionStart=0;
 FVector AuditPreviousEye;
 TArray<TSharedPtr<FJsonValue>> AuditMotionRows;

 bool ValidateSurfaceRendering(UWorld* World,const TCHAR* Argument,const TCHAR* ReportKey,FName OwnershipTag)
 {
  FString Path;if(!FParse::Value(FCommandLine::Get(),Argument,Path))return true;
  FString Text;TSharedPtr<FJsonObject> Ledger;
  if(!FFileHelper::LoadFileToString(Text,*Path)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Ledger)||Ledger->GetStringField(TEXT("status"))!=TEXT("passed"))return false;
  const auto& Changes=Ledger->GetArrayField(TEXT("changes"));const auto& Replacements=Ledger->GetArrayField(TEXT("replacements"));TSet<FString> OriginalMeshes,ReplacementMeshes;TSet<int32> FoundOriginal;TSet<FString> FoundReplacement;int32 Instances=0;
  for(auto V:Changes)OriginalMeshes.Add(V->AsObject()->GetStringField(TEXT("original_mesh")));
  for(auto V:Replacements)ReplacementMeshes.Add(V->AsObject()->GetStringField(TEXT("mesh")));
  for(TActorIterator<AActor> It(World);It;++It){TInlineComponentArray<UStaticMeshComponent*> Components;It->GetComponents(Components);for(auto C:Components){auto Mesh=C->GetStaticMesh();if(!Mesh)continue;const FString MeshPath=Mesh->GetPathName();
   if(OriginalMeshes.Contains(MeshPath)){
    auto Instanced=Cast<UInstancedStaticMeshComponent>(C);if(!Instanced||!Instanced->GetInstanceCount())continue;
    if(C->IsVisible()||!C->bHiddenInGame||C->bCastHiddenShadow)return false;
    bool Matched=false;const FMatrix Matrix=C->GetComponentTransform().ToMatrixWithScale();
    for(int32 Index=0;Index<Changes.Num();++Index){if(FoundOriginal.Contains(Index))continue;auto Row=Changes[Index]->AsObject();if(Row->GetStringField(TEXT("original_mesh"))!=MeshPath||Row->GetIntegerField(TEXT("instance_count"))!=Instanced->GetInstanceCount())continue;const auto& Expected=Row->GetArrayField(TEXT("component_matrix"));if(Expected.Num()!=16)return false;bool Same=true;for(int32 R=0;R<4;++R)for(int32 K=0;K<4;++K)Same&=FMath::Abs(Matrix.M[R][K]-Expected[R*4+K]->AsNumber())<.001;if(!Same)continue;
     auto Original=Row->GetObjectField(TEXT("original"))->GetObjectField(TEXT("row"));if(C->GetCollisionProfileName().ToString()!=Original->GetStringField(TEXT("collision")))return false;const auto& Materials=Row->GetArrayField(TEXT("effective_materials"));if(C->GetNumMaterials()!=Materials.Num())return false;for(int32 K=0;K<Materials.Num();++K)if(!C->GetMaterial(K)||C->GetMaterial(K)->GetPathName()!=Materials[K]->AsString())return false;FoundOriginal.Add(Index);Instances+=Instanced->GetInstanceCount();Matched=true;break;
    }if(!Matched)return false;
   }
   if(ReplacementMeshes.Contains(MeshPath)){
    if(!It->ActorHasTag(OwnershipTag)||!C->IsVisible()||C->bHiddenInGame||C->GetCollisionEnabled()!=ECollisionEnabled::NoCollision||!C->GetComponentTransform().Equals(FTransform::Identity,.001)||FoundReplacement.Contains(MeshPath))return false;FoundReplacement.Add(MeshPath);
   }
  }}
  auto Result=MakeShared<FJsonObject>();const bool Good=FoundOriginal.Num()==Changes.Num()&&FoundReplacement.Num()==Replacements.Num();Result->SetBoolField(TEXT("passed"),Good);Result->SetNumberField(TEXT("original_components"),FoundOriginal.Num());Result->SetNumberField(TEXT("original_instances"),Instances);Result->SetNumberField(TEXT("replacement_chunks"),FoundReplacement.Num());Result->SetStringField(TEXT("scope"),TEXT("Actual runtime world: original instance counts, component matrices, materials and collision profiles preserved; original rendering/hidden shadows disabled; replacement ownership, identity transforms, visibility and NoCollision verified"));AuditReport->SetObjectField(ReportKey,Result);return Good;
 }
 void SetupMotionClip(ACityEnvironmentController* C,double Now)
 {
  const int32 Hours[]={12,17,2};const int32 Minutes[]={0,30,0};C->SetPaused(true);C->SetDateTime(FDateTime(2026,10,26,Hours[AuditMotionClip],Minutes[AuditMotionClip]));AuditMotionFrame=0;AuditMotionStart=Now+5;AuditPreviousEye=FVector(45900,39000,1380);if(AuditCamera.IsValid()){AuditCamera->SetActorLocation(AuditPreviousEye);AuditCamera->SetActorRotation((FVector(48600,42000,1800)-AuditPreviousEye).Rotation());}
 }
 TArray<double> AuditFrameMs, AuditGpuMs, AuditGameMs, AuditRenderMs;

 TSharedPtr<FJsonObject> State(ACityEnvironmentController* C)
 {
  TSharedPtr<FJsonObject> R;
  if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(C->GetStateJson()), R)) AuditFailed = true;
  return R;
 }
 void Save(bool Complete=false)
 {
  AuditReport->SetStringField(TEXT("status"), AuditFailed ? TEXT("failed") : Complete ? TEXT("passed") : TEXT("running"));
  AuditReport->SetArrayField(TEXT("samples"), AuditSamples);
  AuditReport->SetNumberField(TEXT("elapsed_real_seconds"), FPlatformTime::Seconds() - AuditStarted);
  FString Text; FJsonSerializer::Serialize(AuditReport.ToSharedRef(), TJsonWriterFactory<>::Create(&Text));
  IFileManager::Get().MakeDirectory(*FPaths::GetPath(AuditOutput), true);
  if (!FFileHelper::SaveStringToFile(Text, *AuditOutput)) UE_LOG(LogCityEnvironment, Error, TEXT("Audit receipt save failed: %s"), *AuditOutput);
 }
 bool Finish(const FString& Error = FString())
 {
  if (!Error.IsEmpty()) { AuditFailed = true; AuditReport->SetStringField(TEXT("error"), Error); }
  if (AuditController.IsValid()) { AuditController->SetPaused(true); AuditController->SetTimeScale(1); }
  const bool ExternalExit=FParse::Param(FCommandLine::Get(),TEXT("CityEnvironmentAuditExternalExit"));
  AuditReport->SetBoolField(TEXT("external_exit_deferred"),ExternalExit);
  Save(true); UE_LOG(LogCityEnvironment, Display, TEXT("Native environment audit %s: %s"), AuditFailed ? TEXT("failed") : TEXT("passed"), *AuditOutput);
  // The PIE harness must end Play while editor subsystems and viewports still
  // exist. Direct process exit tears them down before EndPlayMap can use them.
  if(!ExternalExit)FPlatformMisc::RequestExitWithStatus(false, AuditFailed ? 1 : 0); return false;
 }
 void BeginPhase(int32 Value)
 {
  AuditPhase = Value; AuditPhaseStart = FPlatformTime::Seconds(); AuditFrameMs.Reset(); AuditGpuMs.Reset(); AuditGameMs.Reset(); AuditRenderMs.Reset();
 }
 TSharedPtr<FJsonObject> Metrics()
 {
  auto M = MakeShared<FJsonObject>(); AuditFrameMs.Sort(); AuditGpuMs.Sort(); AuditGameMs.Sort(); AuditRenderMs.Sort();
  M->SetNumberField(TEXT("frames"), AuditFrameMs.Num());
  if (AuditFrameMs.Num()) { M->SetNumberField(TEXT("frame_median_ms"), AuditFrameMs[AuditFrameMs.Num()/2]); M->SetNumberField(TEXT("frame_p95_ms"), AuditFrameMs[FMath::Min(AuditFrameMs.Num()-1,int32(AuditFrameMs.Num()*.95))]); }
  if (AuditGpuMs.Num()) { M->SetNumberField(TEXT("gpu_median_ms"), AuditGpuMs[AuditGpuMs.Num()/2]); M->SetNumberField(TEXT("gpu_p95_ms"), AuditGpuMs[FMath::Min(AuditGpuMs.Num()-1,int32(AuditGpuMs.Num()*.95))]); }
  if(AuditGameMs.Num()) M->SetNumberField(TEXT("game_thread_median_ms"),AuditGameMs[AuditGameMs.Num()/2]);
  if(AuditRenderMs.Num()) M->SetNumberField(TEXT("render_thread_median_ms"),AuditRenderMs[AuditRenderMs.Num()/2]);
  M->SetBoolField(TEXT("gpu_timer_available"), AuditGpuMs.Num() > 0); return M;
 }
 bool Tick(float)
 {
  const double Now = FPlatformTime::Seconds();
  if (!AuditController.IsValid())
  {
   if (!GEngine) return true;
   for (const FWorldContext& Context : GEngine->GetWorldContexts())
   {
    UWorld* World = Context.World(); if (!World || !World->IsGameWorld() || !World->HasBegunPlay()) continue;
    for (TActorIterator<ACityEnvironmentController> It(World); It; ++It) { AuditController = *It; break; }
   }
   if (!AuditController.IsValid()) return true;
   AuditStarted = Now; BeginPhase(0); AuditReport = MakeShared<FJsonObject>();
   AuditReport->SetStringField(TEXT("world_type"), AuditController->GetWorld()->WorldType == EWorldType::PIE ? TEXT("PIE") : TEXT("Game"));
   AuditReport->SetBoolField(TEXT("python_module_loaded"), FModuleManager::Get().IsModuleLoaded(TEXT("PythonScriptPlugin")));
   AuditReport->SetStringField(TEXT("cpu"), FPlatformMisc::GetCPUBrand()); AuditReport->SetStringField(TEXT("gpu"), FPlatformMisc::GetPrimaryGPUBrand());
   AuditReport->SetStringField(TEXT("build"), FApp::GetBuildConfiguration() == EBuildConfiguration::Shipping ? TEXT("Shipping") : TEXT("Development"));
   if(auto Pool=IConsoleManager::Get().FindConsoleVariable(TEXT("r.Streaming.PoolSize")))AuditReport->SetNumberField(TEXT("texture_pool_mb"),Pool->GetInt());
   auto C = AuditController.Get(); AuditReport->SetObjectField(TEXT("startup_state_before_audit"),State(C)); C->SetPaused(true); C->ShowTimeControls = true;
   UWorld* World = C->GetWorld();if(!ValidateSurfaceRendering(World,TEXT("CityEnvironmentStreetLedger="),TEXT("street_render_validation"),TEXT("CityDepthStreetV1"))||!ValidateSurfaceRendering(World,TEXT("CityEnvironmentTactileLedger="),TEXT("tactile_render_validation"),TEXT("CityDepthTactileV1")))return Finish(TEXT("street_runtime_render_or_preservation_mismatch")); ACameraActor* View = World->SpawnActor<ACameraActor>(); AuditCamera = View;
   View->SetActorLocation(FVector(45546.45,41890.81,1700.2)); View->SetActorRotation((FVector(45900,43800,1800)-View->GetActorLocation()).Rotation()); View->GetCameraComponent()->SetFieldOfView(60);
   if (auto PC = World->GetFirstPlayerController()) PC->SetViewTarget(View);
   C->SetDateTime(FDateTime(2026,10,26,21)); C->SetPaused(true);
   AuditReport->SetObjectField(TEXT("initial"), State(C));
   return true;
  }
  auto C = AuditController.Get();
  if (Now - AuditStarted > 720) return Finish(TEXT("runtime_timeout"));
  if(AuditPhase==0)++AuditWarmFrames;
  if (AuditPhase == 0 && Now - AuditPhaseStart > 30 && AuditWarmFrames >= 600)
  {
   const bool PauseGood=C->GetLocalDateTime()==FDateTime(2026,10,26,21);
   AuditReport->SetBoolField(TEXT("pause_ticker_passed"),PauseGood);
   if(!PauseGood)return Finish(TEXT("paused_clock_advanced"));
   UCityEnvironmentTimeWidget* Widget=nullptr;
   for(TObjectIterator<UCityEnvironmentTimeWidget> It;It;++It)if(It->GetWorld()==C->GetWorld()&&It->IsInViewport()){Widget=*It;break;}
   if(!Widget)return Finish(TEXT("time_widget_missing"));
   auto PauseButton=Cast<UButton>(Widget->GetWidgetFromName(TEXT("PauseButton")));
   auto HourSlider=Cast<USlider>(Widget->GetWidgetFromName(TEXT("HourSlider")));
   auto SpeedSlider=Cast<USlider>(Widget->GetWidgetFromName(TEXT("SpeedSlider")));
   auto DateInput=Cast<UEditableTextBox>(Widget->GetWidgetFromName(TEXT("DateInput")));
   auto SaveButton=Cast<UButton>(Widget->GetWidgetFromName(TEXT("SaveClock")));
   auto LoadButton=Cast<UButton>(Widget->GetWidgetFromName(TEXT("LoadClock")));
   auto Title=Cast<UTextBlock>(Widget->GetWidgetFromName(TEXT("TimeTitle")));
   if(!PauseButton||!HourSlider||!SpeedSlider||!DateInput||!SaveButton||!LoadButton||!Title)return Finish(TEXT("time_widget_controls_missing"));
   C->ToggleTimeControls(); const bool Hidden=!C->ShouldShowTimeControls(); C->ToggleTimeControls();
   PauseButton->OnClicked.Broadcast();const bool Resumed=!C->IsClockPaused();PauseButton->OnClicked.Broadcast();
   DateInput->OnTextCommitted.Broadcast(FText::FromString(TEXT("2028-02-29T23:58:59")),ETextCommit::OnEnter);
   const bool DateGood=C->GetLocalDateTime()==FDateTime(2028,2,29,23,58,59);
   HourSlider->OnValueChanged.Broadcast(24);const bool MidnightGood=C->GetLocalDateTime()==FDateTime(2028,3,1);
   SpeedSlider->OnValueChanged.Broadcast(2);SaveButton->OnClicked.Broadcast();C->SetDateTime(FDateTime(2027,1,1));LoadButton->OnClicked.Broadcast();
   const bool StorageGood=C->GetLocalDateTime()==FDateTime(2028,3,1)&&C->GetTimeScale()==2;
   auto Language=C->GetGameInstance()->GetSubsystem<UCityLanguageSubsystem>();
   if(!Language)return Finish(TEXT("language_subsystem_missing"));
   const ECityLanguage PreviousLanguage=Language->GetLanguage();bool LanguagesGood=true;
   const TCHAR* Expected[]={TEXT("時間"),TEXT("时间"),TEXT("Time")};
   for(int32 L=0;L<3;++L){Language->SetLanguage(ECityLanguage(L),false);LanguagesGood&=Title->GetText().ToString()==Expected[L];}
   Language->SetLanguage(PreviousLanguage,false);
   const bool PointerGood=C->GetWorld()->GetFirstPlayerController()&&C->GetWorld()->GetFirstPlayerController()->bShowMouseCursor;
   AuditReport->SetBoolField(TEXT("time_panel_mouse_cursor_passed"),PointerGood);
   const bool UiGood=Hidden&&Resumed&&C->IsClockPaused()&&DateGood&&MidnightGood&&StorageGood&&LanguagesGood&&PointerGood;
   AuditReport->SetBoolField(TEXT("native_ui_delegates_passed"),UiGood);AuditReport->SetBoolField(TEXT("three_languages_passed"),LanguagesGood);
   if(!UiGood)return Finish(TEXT("native_ui_control_mismatch"));
   // Test actual persistence, leap date, geography, reverse seek and pause.
   C->Latitude=25; C->NorthYawDegrees=35; C->SetDateTime(FDateTime(2028,2,29,23,58,59)); C->SetTimeScale(2); C->SetPaused(true); C->SaveClock();
   C->Latitude=10; C->NorthYawDegrees=0; C->SetDateTime(FDateTime(2027,1,1)); C->SetTimeScale(1); C->LoadClock();
   auto S=State(C); const bool Good=C->GetLocalDateTime()==FDateTime(2028,2,29,23,58,59)&&C->Latitude==25&&C->NorthYawDegrees==35&&C->GetTimeScale()==2&&C->IsClockPaused();
   AuditReport->SetBoolField(TEXT("save_load_passed"),Good); AuditReport->SetObjectField(TEXT("loaded"),S); if(!Good)return Finish(TEXT("save_load_mismatch"));
   C->Latitude=23.5; C->NorthYawDegrees=0; C->SetDateTime(FDateTime(2026,10,26,21)); C->SetTimeScale(1); C->SetPaused(true); BeginPhase(AuditPerformanceRequested?1:10); return true;
  }
  if(AuditPhase==10)
  {
   if(!AuditScreenshotRequested&&Now-AuditPhaseStart>2){AuditScreenshotRequested=true;const FString Image=FPaths::ChangeExtension(AuditOutput,TEXT("png"));FScreenshotRequest::RequestScreenshot(Image,true,false);AuditReport->SetStringField(TEXT("native_ui_screenshot"),Image);}
   if(Now-AuditPhaseStart>4){C->SetDateTime(FDateTime(2026,10,26));C->SetTimeScale(24);C->SetPaused(false);AuditCycleStart=C->GetLocalDateTime();BeginPhase(3);}
   return true;
  }
  if(AuditPhase==4)
  {
   if(Now<AuditMotionStart)return true;
   const double Elapsed=Now-AuditMotionStart;
   if(Elapsed>=6)
   {
    if(++AuditMotionClip>=3){AuditReport->SetArrayField(TEXT("native_motion_frames"),AuditMotionRows);C->SetDateTime(FDateTime(2026,10,26,21));C->SetTimeScale(1);C->SaveClock();return Finish();}
    SetupMotionClip(C,Now);return true;
   }
   const FVector Eye=FMath::Lerp(FVector(45900,39000,1380),FVector(45900,43500,1380),float(Elapsed/6));
   FHitResult Hit;FCollisionQueryParams Query(SCENE_QUERY_STAT(CityMotionClearance),true);Query.AddIgnoredActor(C);if(AuditCamera.IsValid())Query.AddIgnoredActor(AuditCamera.Get());
   if(C->GetWorld()->SweepSingleByChannel(Hit,AuditPreviousEye,Eye,FQuat::Identity,ECC_Visibility,FCollisionShape::MakeSphere(20),Query))return Finish(TEXT("native_motion_camera_obstructed: ")+(Hit.GetActor()?Hit.GetActor()->GetPathName():TEXT("unknown")));
   AuditPreviousEye=Eye;AuditCamera->SetActorLocation(Eye);AuditCamera->SetActorRotation((FVector(48600,42000,1800)-Eye).Rotation());
   if(Elapsed>=AuditMotionFrame*.1)
   {
    const FString Folder=FPaths::GetPath(AuditOutput)/FPaths::GetBaseFilename(AuditOutput);IFileManager::Get().MakeDirectory(*Folder,true);const FString Image=Folder/FString::Printf(TEXT("motion-%d-%03d.png"),AuditMotionClip,AuditMotionFrame++);FScreenshotRequest::RequestScreenshot(Image,false,false);auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("image"),Image);Row->SetNumberField(TEXT("clip"),AuditMotionClip);Row->SetNumberField(TEXT("elapsed_seconds"),Elapsed);Row->SetObjectField(TEXT("clock"),State(C));Row->SetNumberField(TEXT("x"),Eye.X);Row->SetNumberField(TEXT("y"),Eye.Y);Row->SetNumberField(TEXT("z"),Eye.Z);AuditMotionRows.Add(MakeShared<FJsonValueObject>(Row));
   }
   return true;
  }
  if (AuditPhase == 1 || AuditPhase == 2)
  {
   if(AuditPhase==1&&!AuditScreenshotRequested&&Now-AuditPhaseStart>5)
   {
    AuditScreenshotRequested=true;const FString Image=FPaths::ChangeExtension(AuditOutput,TEXT("png"));FScreenshotRequest::RequestScreenshot(Image,true,false);AuditReport->SetStringField(TEXT("native_ui_screenshot"),Image);
   }
   if (Now-AuditPhaseStart>10) { AuditFrameMs.Add(FApp::GetDeltaTime()*1000.); AuditGameMs.Add(FPlatformTime::ToMilliseconds(GGameThreadTime)); AuditRenderMs.Add(FPlatformTime::ToMilliseconds(GRenderThreadTime)); double G=FPlatformTime::ToMilliseconds(RHIGetGPUFrameCycles()); if(G>0&&FMath::IsFinite(G))AuditGpuMs.Add(G); }
   if (Now-AuditPhaseStart>30 && AuditFrameMs.Num()>=120)
   {
    auto Measured=Metrics();AuditReport->SetObjectField(AuditPhase==1?TEXT("profile_enabled"):TEXT("profile_disabled"),Measured);
    if(AuditPhase==1){AuditEnabledMetrics=Measured;C->DeactivateAndRestore();BeginPhase(2);return true;}
    auto Pair=MakeShared<FJsonObject>();Pair->SetObjectField(TEXT("enabled"),AuditEnabledMetrics);Pair->SetObjectField(TEXT("disabled"),Measured);AuditProfilePairs.Add(MakeShared<FJsonValueObject>(Pair));
    if(AuditProfilePairs.Num()<3){C->InitializeBindings();C->SetDateTime(FDateTime(2026,10,26,21));C->SetPaused(true);BeginPhase(1);return true;}
    TArray<double> GpuDeltas,FrameRatios;bool TimersGood=true;
    for(auto P:AuditProfilePairs){auto A=P->AsObject()->GetObjectField(TEXT("enabled"));auto B=P->AsObject()->GetObjectField(TEXT("disabled"));TimersGood&=A->GetBoolField(TEXT("gpu_timer_available"))&&B->GetBoolField(TEXT("gpu_timer_available"))&&A->GetNumberField(TEXT("frames"))>=120&&B->GetNumberField(TEXT("frames"))>=120;if(TimersGood)GpuDeltas.Add(A->GetNumberField(TEXT("gpu_median_ms"))-B->GetNumberField(TEXT("gpu_median_ms")));FrameRatios.Add(A->GetNumberField(TEXT("frame_median_ms"))/B->GetNumberField(TEXT("frame_median_ms"))-1.);}
    GpuDeltas.Sort();FrameRatios.Sort();auto Perf=MakeShared<FJsonObject>();Perf->SetArrayField(TEXT("pairs"),AuditProfilePairs);Perf->SetStringField(TEXT("baseline"),TEXT("Authored light state restored, same geometry and renderer configuration; renderer-migration cost excluded"));Perf->SetNumberField(TEXT("frame_increase_median"),FrameRatios[1]);if(GpuDeltas.Num()==3)Perf->SetNumberField(TEXT("gpu_delta_median_ms"),GpuDeltas[1]);Perf->SetBoolField(TEXT("target_passed"),TimersGood&&GpuDeltas.Num()==3&&GpuDeltas[1]<=2.&&FrameRatios[1]<=.15);AuditReport->SetObjectField(TEXT("performance"),Perf);
    C->InitializeBindings(); C->SetDateTime(FDateTime(2026,10,26)); C->SetTimeScale(24); C->SetPaused(false); AuditCycleStart=C->GetLocalDateTime(); BeginPhase(3); return true;
   }
  }
  if(AuditPhase==3)
  {
   const int32 Hour=int32((C->GetLocalDateTime()-AuditCycleStart).GetTotalHours());
   if(Hour!=AuditLastHour){AuditLastHour=Hour;AuditSamples.Add(MakeShared<FJsonValueObject>(State(C)));Save();}
   if(Hour>=24)
   {
    const double Real=Now-AuditPhaseStart;
    AuditReport->SetNumberField(TEXT("day_real_seconds_at_24x"),Real); AuditReport->SetBoolField(TEXT("full_day_ticker_passed"),FMath::Abs(Real-150.)<5&&AuditSamples.Num()>=24);
    if(FMath::Abs(Real-150.)>=5||AuditSamples.Num()<24)return Finish(TEXT("real_clock_rate_mismatch"));
    C->SetPaused(true); C->SetDateTime(FDateTime(2026,11,9,2)); AuditReport->SetObjectField(TEXT("moonless"),State(C));
    if(AuditMotionRequested){BeginPhase(4);SetupMotionClip(C,Now);return true;}
    C->SetDateTime(FDateTime(2026,10,26,21)); C->SetTimeScale(1); C->SaveClock(); return Finish();
   }
  }
  return true;
 }
}
void StartCityEnvironmentRuntimeAudit()
{
 AuditPerformanceRequested=FParse::Param(FCommandLine::Get(),TEXT("CityEnvironmentProfile"));
 AuditMotionRequested=FParse::Param(FCommandLine::Get(),TEXT("CityEnvironmentMotion"));
 if(FParse::Value(FCommandLine::Get(),TEXT("CityEnvironmentAudit="),AuditOutput)&&!AuditOutput.IsEmpty())
  AuditHandle=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&Tick));
}
void StopCityEnvironmentRuntimeAudit()
{
 if(AuditHandle.IsValid()){FTSTicker::GetCoreTicker().RemoveTicker(AuditHandle);AuditHandle.Reset();}
}
