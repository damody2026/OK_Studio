#include "OKGalleryWidget.h"
#include "ProfilingDebugging/CpuProfilerTrace.h"
#include "KKPreviewActor.h"
#include "KKSkeletalBuilder.h"
#include "KKCardWorkspace.h"
#include "KKGameRoot.h"
#include "KKAnimationCatalog.h"
#include "Async/Async.h"
#include "Engine/World.h"
#include "Camera/CameraActor.h"
#include "Components/TextBlock.h"
#include "Components/SizeBox.h"
#include "Components/EditableTextBox.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformFileManager.h"
#include "GenericPlatform/GenericPlatformFile.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "HAL/PlatformProcess.h"
#include "Misc/ScopeExit.h"
#include "Widgets/SWindow.h"
#include "KKRustExtract.h"
#include "OKCardPreviewCapture.h"
#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include <commdlg.h>
#include "Windows/HideWindowsPlatformTypes.h"
#include "OKReaderMods.h"
#endif
void OKBackgroundWorkerPriority(); // OKGalleryWidget.cpp
void OKRetireActor(AActor* Actor); // OKGalleryWidget.cpp: hidden now, destroyed over the next frames

struct FOKClothingWarmJob {
 FOkSession Session;FString Key,Error,Mods;FVector2D Physics;bool Ok=false;TWeakObjectPtr<AKKPreviewActor> Actor;
 // Garment states this session was opened with. A cached actor must report
 // them, or a later "wear all" compares against all-zero and skips its reload.
 uint8 States[9]{};
};
namespace {
FString StatesKey(const uint8* States){return FString::Printf(TEXT("%u,%u,%u,%u,%u,%u,%u,%u,%u"),States[0],States[1],States[2],States[3],States[4],States[5],States[6],States[7],States[8]);}
}
void UOKCharacterController::ResetClothingPreviews(const FString& Context){
 TRACE_CPUPROFILER_EVENT_SCOPE(KK_GalleryResetClothing);
 ++ClothingWarmGeneration;ClothingWarmQueue.Reset();bClothingRulesPending=false;
 if(ClothingWarmReady)if(auto* Actor=ClothingWarmReady->Actor.Get())OKRetireActor(Actor);
 ClothingWarmReady.Reset();
 // Obsolete workers retain the gate until completion, bounding background
 // loads even when cards change faster than resources can be prepared.
 for(auto& Entry:ClothingPreviews)if(IsValid(Entry.Value)&&Entry.Value!=PreviewActor&&Entry.Value!=StalePreview)OKRetireActor(Entry.Value);
 ClothingPreviews.Reset();ClothingPreviewOrder.Reset();ClothingPreviewMods.Reset();ClothingPreviewContext=Context;
}
void UOKCharacterController::CacheClothingPreview(AKKPreviewActor* Actor,const FString& Key){
 TRACE_CPUPROFILER_EVENT_SCOPE(KK_GalleryCacheClothing);
 TRACE_CPUPROFILER_EVENT_SCOPE(KK_GalleryCacheBody);if(IsValid(Actor))Actor->SetClothingHidden(false);
 if(!IsValid(Actor)||ClothingPreviewContext.IsEmpty()||!Key.StartsWith(ClothingPreviewContext+TEXT("|clothes="))){if(IsValid(Actor))OKRetireActor(Actor);return;}
 // Never retire the shown character or the one kept while the next loads (a failed load puts it back).
 auto Retirable=[this](AKKPreviewActor* A){return IsValid(A)&&A!=PreviewActor&&A!=StalePreview&&A!=PreparingPreview;};
 if(auto* Existing=ClothingPreviews.Find(Key))if(Retirable(*Existing)&&*Existing!=Actor)OKRetireActor(*Existing);
 {TRACE_CPUPROFILER_EVENT_SCOPE(KK_GalleryHideClothing);Actor->StopSpeech();Actor->SuspendDisplayTicks(true);Actor->SetActorTickEnabled(false);Actor->SetActorHiddenInGame(true);Actor->SetActorEnableCollision(false);}
 ClothingPreviews.Add(Key,Actor);ClothingPreviewMods.Add(Key,EditorModsJson());ClothingPreviewOrder.Remove(Key);ClothingPreviewOrder.Add(Key);
 // At most three inactive native sessions and GPU displays, regardless of
 // the number of garment combinations. Oldest inactive state is evicted.
 while(ClothingPreviewOrder.Num()>3){TRACE_CPUPROFILER_EVENT_SCOPE(KK_GalleryEvictClothing);const FString Old=ClothingPreviewOrder[0];ClothingPreviewOrder.RemoveAt(0);if(auto* Entry=ClothingPreviews.Find(Old))if(Retirable(*Entry))OKRetireActor(*Entry);ClothingPreviews.Remove(Old);ClothingPreviewMods.Remove(Old);}
}
bool UOKCharacterController::TryClothingPreview(const FString& Key){
 TRACE_CPUPROFILER_EVENT_SCOPE(KK_GalleryTryClothing);
 auto* Found=ClothingPreviews.Find(Key);if(!Found||!IsValid(*Found)||!(*Found)->bPlaybackMaterialsReady||!IsValid(PreviewActor))return false;
 const bool Profile=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_LOAD_PROFILE"))==TEXT("1");double ProfileAt=FPlatformTime::Seconds();
 auto ProfileStep=[&](const TCHAR* Step){if(Profile){const double Now=FPlatformTime::Seconds();UE_LOG(LogTemp,Display,TEXT("OK clothing prepared switch step=%s ms=%.3f"),Step,(Now-ProfileAt)*1000.);ProfileAt=Now;}};
 AKKPreviewActor* Next=*Found;AKKPreviewActor* Previous=PreviewActor;
 const bool ModsChanged=bEditorModsDirty||ClothingPreviewMods.FindRef(Key)!=EditorModsJson();ClothingPreviewMods.Remove(Key);
 ClothingPreviews.Remove(Key);ClothingPreviewOrder.Remove(Key);
 const bool Playing=Previous->IsActorTickEnabled();const float Time=Previous->AnimPhase;
 Next->SpeechLines=Previous->SpeechLines;Next->SpeechPitch=Previous->SpeechPitch;Next->bSpeechDrivesMouth=Previous->bSpeechDrivesMouth;
 const int32 Mode=Previous->PoseMode;
 Next->SetActorTransform(Previous->GetActorTransform());
 if(Next->StudioCam&&Next->StudioCam!=Previous->StudioCam)Next->StudioCam->Destroy();
 Next->StudioCam=Previous->StudioCam;Previous->StudioCam=nullptr;
 Next->OrbitFocus=Previous->OrbitFocus;Next->OrbitYaw=Previous->OrbitYaw;Next->OrbitPitch=Previous->OrbitPitch;Next->OrbitDistance=Previous->OrbitDistance;
 CacheClothingPreview(Previous,PreviewResourceSignature);
 PreviewActor=Next;PreviewResourceSignature=Key;FMemory::Memcpy(LoadedClothesStates,ClothesStates,sizeof(ClothesStates));
 // The cache key is these exact states; the display must report them too.
 FMemory::Memcpy(Next->DisplayClothesStates,ClothesStates,sizeof(ClothesStates));
 Next->SuspendDisplayTicks(false);Next->SetActorHiddenInGame(false);Next->SetActorEnableCollision(false);
 ProfileStep(TEXT("display_swap"));
 FString Error;
 if(Next->bShapeDirty)Next->ApplyPoseFrame(0.f);
 Next->SetGameSceneMode(SelectedGameSceneMode);
 if(Mode==2&&!SelectedGameClip.IsEmpty()){
  if(SelectedStudioRow.IsNone())Next->SetGameAnimation(SelectedGameClip,false);
  else Next->SetStudioAnimation(AnimationCatalog,SelectedStudioRow,Error,SavedStudioOptions.X,SavedStudioOptions.Y,SavedStudioOptions.Z);
 }else if(Next->PoseMode!=Mode)Next->SetPoseMode(Mode);
 ProfileStep(TEXT("animation"));
 for(int32 I=0;I<Previous->Session.AnimationFloatCount();++I){FString Name;float Value,Min,Max;if(Previous->Session.AnimationFloatAt(I,Name,Value,Min,Max))Next->Session.SetAnimationFloat(Name,Value);}
 ProfileStep(TEXT("animation_parameters"));
 SetModelLayout(true);
 if(ModsChanged){bEditorModsDirty=true;ApplyPendingEditorMods();}
 ProfileStep(TEXT("modifiers"));
 Next->Session.ApplyBodyPhysics(Selected.Body.BustSoftness,Selected.Body.BustWeight);
 if(Next->bShapeDirty||Next->Session.ShapeBody()!=Selected.Body.ShapeValueBody||Next->Session.ShapeFace()!=Selected.Face.ShapeValueFace)Next->MarkShapeDirty(Selected.Face.ShapeValueFace,Selected.Body.ShapeValueBody);
 Next->AnimationPlaybackSpeed=Previous->AnimationPlaybackSpeed;Next->AnimPhase=Time;Next->FaceClock=Previous->FaceClock;
 ProfileStep(TEXT("shape_physics"));
 Next->BeginFaceDisplayUpdate();Next->SetMouthPattern(SelectedMouthPattern,false);Next->SetMouthOpen(SelectedMouthOpen);RefreshFaceControls();Next->EndFaceDisplayUpdate();
 ProfileStep(TEXT("face"));
 RefreshHandControls();Next->FollowHeadLookCamera(Previous->bHeadLookFollowCamera);Next->ApplyPoseFrame(0.f);Next->SetActorTickEnabled(Playing);
 ProfileStep(TEXT("hands_pose"));
 ApplyPenisVisible();SetModelLayout(true);
 ProfileStep(TEXT("layout"));
 if(InspectorText)InspectorText->SetText(FText::FromString(Error.IsEmpty()?TEXT("已切換服裝狀態"):Error));
 bLastClothingSwitchCached=true;UE_LOG(LogTemp,Display,TEXT("OK clothing preview cache hit %s"),*Key);return true;
}
static bool ClothingWarmDisabled(){
  return FPlatformMisc::GetEnvironmentVariable(TEXT("OK_NO_CLOTHING_WARM"))==TEXT("1");
 }
void UOKCharacterController::SuspendClothingWarmForCapture(){
 if(!bClothingWarmHeld)UE_LOG(LogTemp,Display,TEXT("OK clothing warm held for product capture"));
 bClothingWarmHeld=true;
 ++ClothingWarmGeneration;ClothingWarmQueue.Reset();bClothingRulesPending=false;
 if(ClothingWarmReady)if(auto* Actor=ClothingWarmReady->Actor.Get())OKRetireActor(Actor);
 ClothingWarmReady.Reset();
}
void UOKCharacterController::WarmClothingPreviews(){
 if(bClothingWarmHeld||ClothingWarmDisabled())return;
 if(!IsValid(PreviewActor)||ClothingPreviewContext.IsEmpty()||!Entries.IsValidIndex(SelectedIndex))return;
 // Rule discovery reads and validates the source card/catalogue. Queue it
 // behind the same single-worker gate as native preview preparation.
 bClothingRulesPending=true;
}

void UOKCharacterController::TickClothingPreviews(){
 TRACE_CPUPROFILER_EVENT_SCOPE(KK_GalleryClothingTick);
 if(bClothingWarmHeld||ClothingWarmDisabled())return;
 if(IsValid(PreviewActor)&&(PreviewActor->bProductSweep||PreviewActor->bProductLightLatched))return;
 // Hidden outfit actors allocate textures and compile materials as well as
 // opening native sessions. Give the active editor exclusive preparation
 // priority while the user browses appearance choices; retain queued jobs
 // and resume them when that panel closes.
 if(bLoadInFlight||bAppearanceBusy||bAppearanceThumbBusy||bPropertyBusy||
    (AppearancePanel&&AppearancePanel->IsVisible())||bAnimationPreparing||PendingAnimationKind>=0||!bModelLayout||InteractionWidget||InteractionScene||PairedPlayback||!IsValid(PreviewActor)||!Entries.IsValidIndex(SelectedIndex))return;
 if(Selected.DeferredPreview)return; // OnCloseAppearance persists before resuming background source reads.
 if(PreviewActor->bClothingHidden)return;
 // With OK_PRELOAD_NEIGHBOR the next card in the list is prepared first (OKGalleryNeighbor.cpp).
 if(!ClothingWarmReady&&NeighborPreloadPending())return;
 for(auto& Entry:ClothingPreviews)if(IsValid(Entry.Value)&&!Entry.Value->bPlaybackMaterialsReady)Entry.Value->PreparePlaybackMaterials(false);
 if(ClothingWarmReady){
  auto Job=ClothingWarmReady;
  if(!Job->Ok||Job->Key==PreviewResourceSignature||ClothingPreviews.Contains(Job->Key)){
   if(auto* Actor=Job->Actor.Get())Actor->Destroy();
   if(!Job->Ok)UE_LOG(LogTemp,Warning,TEXT("OK clothing warm load: %s"),*Job->Error);
   ClothingWarmReady.Reset();return;
  }
  FString Error;bool Ok=false;
  auto* Actor=Job->Actor.Get();
  if(!Actor){
   Actor=GetWorld()->SpawnActor<AKKPreviewActor>(PreviewActor->GetActorLocation(),PreviewActor->GetActorRotation());
   if(Actor){Job->Actor=Actor;Actor->SetActorHiddenInGame(true);Actor->SetActorTickEnabled(false);
    FMemory::Memcpy(Actor->DisplayClothesStates,Job->States,sizeof(Job->States));
    Actor->Session=MoveTemp(Job->Session);Actor->UseGalleryPhysics();if(Job->Physics!=FVector2D(Selected.Body.BustSoftness,Selected.Body.BustWeight))Actor->Session.ApplyBodyPhysics(Selected.Body.BustSoftness,Selected.Body.BustWeight);const FString Mods=EditorModsJson();if(Mods!=Job->Mods)Actor->Session.ApplyEditorMods(Mods,OutfitIndex);
    Ok=Actor->BeginSessionLoad(Error);
   }
  }else Ok=Actor->ContinueSessionLoad(Error);
  if(Actor)Actor->SuspendDisplayTicks(true);
  if(!Ok){if(Actor)Actor->Destroy();ClothingWarmReady.Reset();UE_LOG(LogTemp,Warning,TEXT("OK clothing warm display: %s"),*Error);}
  else if(Actor->IsSessionLoadComplete()){
   CacheClothingPreview(Actor,Job->Key);ClothingWarmReady.Reset();UE_LOG(LogTemp,Display,TEXT("OK clothing preview prepared incrementally %s"),*Job->Key);
  }
  return;
 }
 if(bClothingRulesPending&&!bClothingWarmInFlight){
  bClothingRulesPending=false;bClothingWarmInFlight=true;
  const UKKGameRoot* Root=bIndependentCards?nullptr:UKKGameRoot::Get();
  const FString Game=Root?Root->Root:FString(),Card=Entries[SelectedIndex].Path,Context=ClothingPreviewContext;
  const int32 Generation=ClothingWarmGeneration,Outfit=OutfitIndex;
  TWeakObjectPtr<UOKCharacterController> Weak(this);
  Async(EAsyncExecution::Thread,[Weak,Game,Card,Context,Generation,Outfit](){
   OKBackgroundWorkerPriority();
   TArray<FString> Keys;FString Errors;
   for(int32 Action:{100,101,103}){
    uint8 Base[9]{},State[9]{};FString Error;
    if(Action==103)FMemory::Memset(Base,3,sizeof(Base));
    if(FOkSession::ClothingTransition(Game,Card,Outfit,Base,Action==103?101:Action,State,Error))Keys.AddUnique(Context+TEXT("|clothes=")+StatesKey(State));
    else Errors+=Error+TEXT("\n");
   }
   AsyncTask(ENamedThreads::GameThread,[Weak,Context,Generation,Keys=MoveTemp(Keys),Errors=MoveTemp(Errors)](){
    if(auto* G=Weak.Get()){
     G->bClothingWarmInFlight=false;
     if(Generation!=G->ClothingWarmGeneration||Context!=G->ClothingPreviewContext)return;
     for(const FString& Key:Keys)if(Key!=G->PreviewResourceSignature&&!G->ClothingPreviews.Contains(Key))G->ClothingWarmQueue.AddUnique(Key);
     if(!Errors.IsEmpty())UE_LOG(LogTemp,Warning,TEXT("OK clothing warm rules: %s"),*Errors);
    }
   });
  });
  return;
 }
 if(bClothingWarmInFlight||ClothingWarmQueue.IsEmpty())return;
 const FString Key=ClothingWarmQueue[0];ClothingWarmQueue.RemoveAt(0);
 if(Key==PreviewResourceSignature||ClothingPreviews.Contains(Key))return;
 TArray<FString> Values;Key.Mid(Key.Find(TEXT("|clothes="))+9).ParseIntoArray(Values,TEXT(","));if(Values.Num()!=9)return;
 TArray<uint8> States;for(const FString& Value:Values)States.Add(uint8(FCString::Atoi(*Value)));
 UKKGameRoot* Root=bIndependentCards?nullptr:UKKGameRoot::Get();const FString Game=Root?Root->Root:FString();
 const FString Card=bIndependentCards?UKKCardWorkspace::LoadableSourcePath(Entries[SelectedIndex].Path):Entries[SelectedIndex].Path;
 const int32 Generation=ClothingWarmGeneration,Outfit=OutfitIndex;bClothingWarmInFlight=true;
 auto Job=MakeShared<FOKClothingWarmJob,ESPMode::ThreadSafe>();Job->Key=Key;for(int32 I=0;I<9;++I)Job->States[I]=States[I];Job->Mods=EditorModsJson();Job->Physics=FVector2D(Selected.Body.BustSoftness,Selected.Body.BustWeight);TWeakObjectPtr<UOKCharacterController> Weak(this);
 const bool PrepareSkeleton=OKLiveGpuSkinRequested();
 Async(EAsyncExecution::Thread,[Weak,Generation,Game,Card,Outfit,States,Job,PrepareSkeleton](){
  OKBackgroundWorkerPriority();
  const double Begin=FPlatformTime::Seconds();UE_LOG(LogTemp,Display,TEXT("OK clothing warm begin %s"),*Job->Key);
  // With the launcher's warm processes (OK_WARM_PRIORITY), an OK card's variant that is not in the open cache is
  // requested from them and waited for here. Building it in this process would hold the process-wide card pack
  // mount for seconds, and the next card the user opens would wait behind it.
  const FString WarmFile=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_WARM_PRIORITY"));
  if(!WarmFile.IsEmpty()&&FOkSession::CacheReady(Card,Outfit,States.GetData())==0){
   FString Line=FPaths::ConvertRelativePathToFull(Card)+FString::Printf(TEXT("\t%d\t"),Outfit);
   for(int32 I=0;I<States.Num();++I){if(I)Line+=TEXT(",");Line.AppendInt(States[I]);}
   FFileHelper::SaveStringToFile(Line+TEXT("\n"),*WarmFile,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,&IFileManager::Get(),FILEWRITE_Append);
   int32 Ready=0; // once a second: the check hashes the card file
   while(Ready==0&&FPlatformTime::Seconds()-Begin<45.){FPlatformProcess::Sleep(1.f);Ready=FOkSession::CacheReady(Card,Outfit,States.GetData());}
   if(Ready==0){
    UE_LOG(LogTemp,Display,TEXT("OK clothing warm left to the warm processes %s"),*Job->Key);
    AsyncTask(ENamedThreads::GameThread,[Weak](){if(auto* G=Weak.Get())G->bClothingWarmInFlight=false;});
    return;
   }
  }
  // Speculative: gives way to the card the user opens next (the open fails and the variant is simply not ready).
  FOkSession::SetThreadBackground(true);
  Job->Ok=Job->Session.Open(Game,Card,Outfit,Job->Error,States.GetData());const double Opened=FPlatformTime::Seconds();
  FOkSession::SetThreadBackground(false);
  if(Job->Ok){Job->Session.ApplyBodyPhysics(Job->Physics.X,Job->Physics.Y);Job->Session.ApplyEditorMods(Job->Mods,Outfit);AKKPreviewActor::PrecacheSessionTextures(Job->Session,PrepareSkeleton,true);}
  UE_LOG(LogTemp,Display,TEXT("OK clothing warm worker ok=%d open_ms=%.3f texture_ms=%.3f"),Job->Ok,(Opened-Begin)*1000.,(FPlatformTime::Seconds()-Opened)*1000.);
  AsyncTask(ENamedThreads::GameThread,[Weak,Generation,Job](){if(auto* G=Weak.Get()){G->bClothingWarmInFlight=false;if(Generation==G->ClothingWarmGeneration)G->ClothingWarmReady=Job;}});
 });
}

// ---------------------------------------------------------------------------------------------- OK clothes (.okclothes)
// One outfit with its plugin data (Material Editor, KCOX, accessory states ...); the shared models stay in the OK base
// library, so the file is about the size of a coordinate card (Docs/OK_BASE_LIBRARY_PLAN.md). Files go to the save folder.
namespace {
bool OKPickFile(const TCHAR* Filter,const TCHAR* Title,FString& Out){
#if PLATFORM_WINDOWS
 TCHAR File[4096]={0};OPENFILENAMEW Dialog{};Dialog.lStructSize=sizeof(Dialog);
 if(GEngine&&GEngine->GameViewport)if(TSharedPtr<SWindow> Window=GEngine->GameViewport->GetWindow())if(Window->GetNativeWindow().IsValid())Dialog.hwndOwner=(HWND)Window->GetNativeWindow()->GetOSWindowHandle();
 Dialog.lpstrFilter=Filter;Dialog.lpstrFile=File;Dialog.nMaxFile=UE_ARRAY_COUNT(File);Dialog.lpstrTitle=Title;
 Dialog.Flags=OFN_FILEMUSTEXIST|OFN_PATHMUSTEXIST|OFN_NOCHANGEDIR;
 if(!GetOpenFileNameW(&Dialog))return false;Out=File;return true;
#else
 return false;
#endif
}
}
// Outfit cards go to the save folder when one is given, else to UserData/okclothes (the player's own data, kept).
static FString OKClothesFolder(const UEditableTextBox* SaveFolder){
 const FString Typed=SaveFolder?SaveFolder->GetText().ToString().TrimStartAndEnd():FString();
 return FPaths::ConvertRelativePathToFull(Typed.IsEmpty()?FPaths::ProjectDir()/TEXT("UserData/okclothes"):Typed);
}
void UOKCharacterController::OnExportOkClothes(){
 auto Report=[this](const FString& Text){if(InspectorText)InspectorText->SetText(FText::FromString(Text));ScreenNote(1,8.f,FColor::Cyan,Text);};
 ExportOkClothesTo(FString(),[Report](bool bOk,const FString& What){Report(bOk?TEXT("已匯出服裝卡：")+What:TEXT("匯出服裝卡失敗：")+What);});
}
void UOKCharacterController::ExportOkClothesTo(const FString& OutIn,TFunction<void(bool,const FString&)> Done){
 if(!Done)Done=[](bool,const FString&){};
 if(!Entries.IsValidIndex(SelectedIndex)){Done(false,TEXT("請先選擇一張角色卡。"));return;}
 const FString Card=Entries[SelectedIndex].Path;const int32 Outfit=OutfitIndex;
 const FString Output=!OutIn.IsEmpty()?OutIn:OKClothesFolder(OutputDirectoryInput)/FString::Printf(TEXT("%s_outfit%d.okclothes"),*FPaths::GetBaseFilename(Card),Outfit);
 IFileManager::Get().MakeDirectory(*FPaths::GetPath(Output),true);
 TWeakObjectPtr<UOKCharacterController> Weak(this);
 auto Export=[Weak,Card,Outfit,Output,Done](const FString& Picture){
  FString Summary;const bool Ok=Picture.IsEmpty()?FOkSession::ClothesExport(Card,Outfit,Output,Summary):FOkSession::ClothesExportPictured(Card,Outfit,Picture,Output,Summary);
  UE_LOG(LogTemp,Display,TEXT("OK clothes export %s outfit %d -> %s: %s"),*Card,Outfit,*Output,*Summary);
  if(Ok&&Weak.IsValid()){++Weak->OkClothesVersion;OKReaderMods::ClothesSaved(Weak.Get(),Output,Card,Outfit);}	// reader.coordinate_save
  Done(Ok,Ok?Output:Summary);
 };
 // Pictured as she wears it now (the front view of the card capture); the card's own picture when she is not shown.
 if(!IsValid(PreviewActor)||!FPaths::IsSamePath(PreviewCardPath,Card)){Export(FString());return;}
 const FString Picture=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("OKClothes/picture.png"));
 OKCardPreviewCapture::Begin(PreviewActor,[Export,Picture](TArray<TArray<uint8>> Views,FString Error){
  const bool bPicture=Error.IsEmpty()&&Views.Num()>1&&Views[1].Num()>0&&FFileHelper::SaveArrayToFile(Views[1],*Picture);
  if(!bPicture)UE_LOG(LogTemp,Warning,TEXT("OK clothes export: no picture (%s), the card's own used"),*Error);
  Export(bPicture?Picture:FString());
 });
}
static void OKWearPicked(UOKCharacterController* Self,bool bClothesOnly,TFunction<void(const FString&)> Report){
 FString Clothes;if(!OKPickFile(TEXT("OK 服裝卡\0*.okclothes\0所有檔案\0*.*\0"),TEXT("選擇要套用的服裝卡"),Clothes))return;
 Report(TEXT("套用服裝卡中…"));
 Self->WearOkClothesFrom(Clothes,bClothesOnly,[Report](bool bOk,const FString& What){Report(bOk?TEXT("已套用服裝卡（工作卡，要保留請另存）：")+What:TEXT("套用服裝卡失敗：")+What);});
}
void UOKCharacterController::OnWearOkClothes(){
 OKWearPicked(this,false,[this](const FString& Text){if(InspectorText)InspectorText->SetText(FText::FromString(Text));ScreenNote(1,8.f,FColor::Cyan,Text);});
}
void UOKCharacterController::OnWearOkClothesOnly(){
 OKWearPicked(this,true,[this](const FString& Text){if(InspectorText)InspectorText->SetText(FText::FromString(Text));ScreenNote(1,8.f,FColor::Cyan,Text);});
}
void UOKCharacterController::WearOkClothesReported(const FString& Clothes,bool bClothesOnly){
 TWeakObjectPtr<UOKCharacterController> Weak(this);
 auto Report=[Weak](const FString& Text){if(UOKCharacterController* Self=Weak.Get()){if(Self->InspectorText)Self->InspectorText->SetText(FText::FromString(Text));Self->ScreenNote(1,8.f,FColor::Cyan,Text);}};
 Report((bClothesOnly?TEXT("只換衣服中…："):TEXT("套用服裝卡中…："))+FPaths::GetBaseFilename(Clothes));
 WearOkClothesFrom(Clothes,bClothesOnly,[Report](bool bOk,const FString& What){Report(bOk?TEXT("已套用服裝卡（工作卡，要保留請另存）：")+What:TEXT("套用服裝卡失敗：")+What);});
}
FString UOKCharacterController::OkClothesFolderPath() const{
 const FString Folder=OKClothesFolder(OutputDirectoryInput);
 IFileManager::Get().MakeDirectory(*Folder,true);
 return Folder;
}
// A game coordinate card (【KoiKatuClothes】) rather than a character card, told without reading the file: the PNG
// chunks are walked by seeking (a character card carries tens of megabytes of resources in its chunks), then the
// marker is read from the bytes right after IEND, where the trailer puts it (okclothes::read_coordinate_file).
static bool OKIsCoordinateCardFile(const FString& Path){
 TUniquePtr<IFileHandle> File(FPlatformFileManager::Get().GetPlatformFile().OpenRead(*Path));
 if(!File)return false;
 static const uint8 Signature[8]={137,80,78,71,13,10,26,10};
 uint8 Head[8];
 if(!File->Read(Head,8)||FMemory::Memcmp(Head,Signature,8)!=0)return false;
 for(int32 Chunks=0;Chunks<4096;++Chunks){
  if(!File->Read(Head,8))return false;
  const uint32 Length=(uint32(Head[0])<<24)|(uint32(Head[1])<<16)|(uint32(Head[2])<<8)|uint32(Head[3]);
  if(FMemory::Memcmp(Head+4,"IEND",4)==0){
   // int32 product, then a .NET string: its length is a varint of one or two bytes, so the name is well inside this.
   uint8 Trailer[64]={};
   if(!File->Seek(File->Tell()+int64(Length)+4))return false;
   const int64 Read=FMath::Min<int64>(sizeof(Trailer),FMath::Max<int64>(0,File->Size()-File->Tell()));
   if(Read<20||!File->Read(Trailer,Read))return false;
   const ANSICHAR* Marker="KoiKatuClothes";const int32 MarkerLength=14;
   for(int64 At=0;At+MarkerLength<=Read;++At)if(FMemory::Memcmp(Trailer+At,Marker,MarkerLength)==0)return true;
   return false;
  }
  if(!File->Seek(File->Tell()+int64(Length)+4))return false;
 }
 return false;
}
TArray<FString> UOKCharacterController::OkClothesFiles() const{
 TArray<FString> Folders{OKClothesFolder(OutputDirectoryInput),FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("UserData/okclothes"))};
 TArray<TPair<FDateTime,FString>> Found;
 for(int32 I=0;I<Folders.Num();++I){
  if(Folders.IndexOfByPredicate([&](const FString& F){return FPaths::IsSamePath(F,Folders[I]);})!=I)continue;
  TArray<FString> Names;IFileManager::Get().FindFiles(Names,*(Folders[I]/TEXT("*.okclothes")),true,false);
  for(const FString& Name:Names){const FString Path=Folders[I]/Name;Found.Emplace(IFileManager::Get().GetTimeStamp(*Path),Path);}
  // The game's own outfit cards as they come: the folder may also hold character cards (the save folder does), so
  // only the ones marked as a coordinate card are listed.
  TArray<FString> Pngs;IFileManager::Get().FindFiles(Pngs,*(Folders[I]/TEXT("*.png")),true,false);
  for(const FString& Name:Pngs){const FString Path=Folders[I]/Name;if(OKIsCoordinateCardFile(Path))Found.Emplace(IFileManager::Get().GetTimeStamp(*Path),Path);}
 }
 Found.Sort([](const auto& A,const auto& B){return A.Key>B.Key;});
 TArray<FString> Out;for(const auto& F:Found)Out.Add(F.Value);
 return Out;
}
// While an outfit card is being worn, say what the native job is doing and how far it is. The two sealing steps are
// child processes that take seconds each; they stream their own progress back (ok-extract progress.rs), so the
// percentage keeps moving inside them instead of sitting at one number.
void UOKCharacterController::TickClothesWearProgress(){
 if(!bWearingOkClothes)return;
 const double Now=FPlatformTime::Seconds();
 if(Now<WearProgressAt)return;
 WearProgressAt=Now+.1;
 FString Label;float Done=0.f;int64 Generation=0;
 if(!FOkSession::JobProgress(Label,Done,Generation))return;
 const FString Text=FString::Printf(TEXT("套用服裝卡 %d%%：%s（%.0f 秒）"),FMath::RoundToInt(Done*100.f),*Label,Now-WearProgressBegan);
 if(InspectorText)InspectorText->SetText(FText::FromString(Text));
 ScreenNote(1,1.f,FColor::Cyan,Text);
}
void UOKCharacterController::WearOkClothesFrom(const FString& Clothes,bool bClothesOnly,TFunction<void(bool,const FString&)> Done){
 if(!Done)Done=[](bool,const FString&){};
 if(!Entries.IsValidIndex(SelectedIndex)){Done(false,TEXT("請先選擇一張角色卡。"));return;}
 if(bWearingOkClothes){Done(false,TEXT("另一次套用還在進行。"));return;}
 if(!IFileManager::Get().FileExists(*Clothes)){Done(false,TEXT("找不到服裝卡：")+Clothes);return;}
 const FString Card=Entries[SelectedIndex].Path;const int32 Outfit=OutfitIndex;
 // A work card: the card shown stays as it was; saving keeps the result (the reader's save).
 const FString Output=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("OKClothes/Worn")/FString::Printf(TEXT("%s+%s.png"),*FPaths::GetBaseFilename(Card).Left(60),*FPaths::GetBaseFilename(Clothes).Left(60)));
 IFileManager::Get().MakeDirectory(*FPaths::GetPath(Output),true);
 bWearingOkClothes=true;WearProgressBegan=FPlatformTime::Seconds();WearProgressAt=0.;
 TWeakObjectPtr<UOKCharacterController> Weak(this);
 // An OK card is sealed again for her new clothes (ok-extract.exe, seconds): off the game thread.
 // The two halves of "點縮圖到她換好衣服" are timed and logged, always: the wear (resealing the card, which is
 // nearly all of it -- Docs/OK_CLOTHES_CARD.md) and the open that follows. OK_PROFILE=1 splits the wear further.
 const double Pressed=FPlatformTime::Seconds();
 Async(EAsyncExecution::Thread,[Weak,Card,Clothes,Outfit,Output,bClothesOnly,Done,Pressed](){
  FString Summary;
  const bool Ok=bClothesOnly?FOkSession::ClothesWearClothesOnly(Card,Clothes,Outfit,Output,Summary):FOkSession::ClothesWear(Card,Clothes,Outfit,Output,Summary);
  const double Worn=FPlatformTime::Seconds();
  AsyncTask(ENamedThreads::GameThread,[Weak,Card,Clothes,Outfit,Output,Ok,Summary,Done,Pressed,Worn](){
   UE_LOG(LogTemp,Display,TEXT("OK clothes wear %s on %s outfit %d -> %s: %s"),*Clothes,*Card,Outfit,*Output,*Summary);
   ON_SCOPE_EXIT{UE_LOG(LogTemp,Display,TEXT("OK clothes wear timing: wear %.2fs + open %.2fs = %.2fs"),Worn-Pressed,FPlatformTime::Seconds()-Worn,FPlatformTime::Seconds()-Pressed);};
   UOKCharacterController* Self=Weak.Get();
   if(!Self){return;}
   Self->bWearingOkClothes=false;
   if(!Ok){Done(false,Summary);return;}
   // The worn card is a work card of the same character; the mods take the outfit card's data (reader.coordinate_load).
   OKReaderMods::WorkingCard(Card,Output);OKReaderMods::ClothesWorn(Self,Clothes,Output,Outfit);
   // Opened at once, in the outfit she now wears.
   Self->bIndependentCards=!UKKCardWorkspace::PortableSourcePath(Output).IsEmpty();
   int32 Index=Self->Entries.IndexOfByPredicate([&](const auto& E){return FPaths::IsSamePath(E.Path,Output);});
   if(Index==INDEX_NONE){FKKCardListEntry E;E.Path=Output;E.FileName=FPaths::GetCleanFilename(Output);Index=Self->Entries.Add(E);}
   else Self->Entries[Index].FileName=FPaths::GetCleanFilename(Output);
   Self->SelectIndex(Index);
   if(Self->SelectedIndex!=Index){Done(false,TEXT("套好的卡讀不出來：")+Output);return;}
   // The wear is done but she is not on screen yet; the open and the display build are the last ~20% of the wait.
   {const FString Note=FString::Printf(TEXT("套用服裝卡 97%%：開卡並建立顯示（%.0f 秒）"),FPlatformTime::Seconds()-Self->WearProgressBegan);
    if(Self->InspectorText)Self->InspectorText->SetText(FText::FromString(Note));Self->ScreenNote(1,8.f,FColor::Cyan,Note);}
   Self->OutfitIndex=FMath::Max(0,Outfit);Self->RefreshOutfitList();Self->OnLoad3D();
   Done(true,Output);
  });
 });
}
void UOKCharacterController::OnImportClothesCard(){
 auto Report=[this](const FString& Text){if(InspectorText)InspectorText->SetText(FText::FromString(Text));ScreenNote(1,8.f,FColor::Cyan,Text);};
 const FString Directory=OutputDirectoryInput?OutputDirectoryInput->GetText().ToString().TrimStartAndEnd():FString();
 if(Directory.IsEmpty()){Report(TEXT("請先在卡片列表填寫另存資料夾。"));return;}
 FString Coordinate;if(!OKPickFile(TEXT("服裝卡\0*.png\0所有檔案\0*.*\0"),TEXT("選擇遊戲的服裝卡"),Coordinate))return;
 const FString Output=FPaths::ConvertRelativePathToFull(Directory)/(FPaths::GetBaseFilename(Coordinate)+TEXT(".okclothes"));
 IFileManager::Get().MakeDirectory(*FPaths::GetPath(Output),true);
 FString Summary;const bool Ok=FOkSession::ClothesImport(Coordinate,Output,Summary);
 UE_LOG(LogTemp,Display,TEXT("OK clothes import %s -> %s: %s"),*Coordinate,*Output,*Summary);
 if(Ok)++OkClothesVersion;
 Report(Ok?TEXT("已轉成 OK 服裝：")+Output:TEXT("轉換服裝卡失敗：")+Summary);
}
