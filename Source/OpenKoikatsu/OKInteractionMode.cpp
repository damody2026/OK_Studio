#include "OKInteractionMode.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "OKCharacterController.h"
#include "OKInteractionScene.h"
#include "OKHScene.h"
#include "Framework/Application/SlateApplication.h"
#include "KKPreviewActor.h"
#include "ok_extract.h"
#include "Components/PoseableMeshComponent.h"
#include "KKPairedPlayback.h"
#include "KKCardReader.h"
#include "KKCardWorkspace.h"
#include "KKGameRoot.h"
#include "OpenKoikatsuPlayerController.h"
#include "OKPaintSprayer.h"
#include "Async/Async.h"
#include "Camera/CameraActor.h"
#include "Engine/World.h"
#include "Components/AudioComponent.h"
#include "EngineUtils.h"
#include "HAL/PlatformProcess.h"
#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "Dom/JsonObject.h"
#include "Misc/Paths.h"
#include "Components/ComboBoxString.h"
#include "ProceduralMeshComponent.h"
#include "Misc/FileHelper.h"
#include "Serialization/JsonSerializer.h"
#include "UnrealClient.h"
#include "Engine/GameViewportClient.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Input/SButton.h"

namespace {
struct FInteractionRoleLoad {FOkSession Session;FKKCharacterFile Card;FString Error,Pairs,Opened;bool Ok=false;};
}
AOKInteractionMode::AOKInteractionMode(){PrimaryActorTick.bCanEverTick=true;}
AOKInteractionMode* AOKInteractionMode::Enter(UOKCharacterController* Input,const FTransform* InPlace){
    if(!Input||!Input->GetWorld()||!Input->GetOwningPlayer()||Input->Selected.Sex!=1)return nullptr;
    for(TActorIterator<AOKInteractionMode> It(Input->GetWorld());It;++It)if(!It->Finished)return It->Controller==Input?*It:nullptr;
    auto* Mode=Input->GetWorld()->SpawnActor<AOKInteractionMode>();if(!Mode)return nullptr;
    Mode->Controller=Input;Mode->Started=FPlatformTime::Seconds();if(InPlace){Mode->bInPlace=true;Mode->InPlaceAt=*InPlace;Input->bInteractionInPlace=true;}Mode->PreviousView=Input->GetOwningPlayer()->GetViewTarget();Mode->PreviousMouse=Input->GetOwningPlayer()->bShowMouseCursor;
    if(auto* PC=Cast<AOpenKoikatsuPlayerController>(Input->GetOwningPlayer())){
        Mode->PreviousPaint=PC->IsPaintPreviewActive();Mode->PreviousTouch=PC->bBodyTouchEnabled;
        // Detach the source context before stage activation can cancel it.
        Mode->PreviousBodyInteraction=MoveTemp(PC->BodyInteraction);PC->BodyInteraction=FOKBodyInteraction();
        Mode->PreviousBodyGesture=MoveTemp(PC->BodyGesture);PC->BodyGesture=FOKBodyGesture();PC->bBodyTouchEnabled=false;
    }
    Mode->Cancelled=MakeShared<FThreadSafeBool,ESPMode::ThreadSafe>(false);
    for(TActorIterator<AActor> It(Input->GetWorld());It;++It){
        AActor* A=*It;if(A==Mode)continue;
        Mode->SourceActors.Add({A,A->IsHidden(),A->GetActorEnableCollision(),A->IsActorTickEnabled()});
        if(Cast<AKKPreviewActor>(A)||Cast<AKKPairedPlayback>(A))A->SetActorTickEnabled(false);
        if(InPlace)continue; // the world goes on around them: its sounds, its sights
        TInlineComponentArray<UAudioComponent*> Audio;A->GetComponents(Audio);for(auto* Component:Audio)if(Component->IsPlaying()){Mode->SourceAudio.Add({Component,Component->bIsPaused!=0});Component->SetPaused(true);}
        if(A!=Input->PreviewActor&&A!=Input->PartnerActor){A->SetActorHiddenInGame(true);A->SetActorEnableCollision(false);}
    }
    if(GEngine&&GEngine->GameViewport){
        TWeakObjectPtr<AOKInteractionMode> Weak(Mode);
        Mode->PreparingOverlay=SNew(SBorder).HAlign(HAlign_Center).VAlign(VAlign_Center).BorderBackgroundColor(FLinearColor(.015f,.025f,.04f,.92f))[
            SNew(SVerticalBox)+SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).Text(FText::FromString(TEXT("正在準備高模…")))]
            +SVerticalBox::Slot().AutoHeight().Padding(0,20)[SNew(SButton).Text(FText::FromString(TEXT("取消並返回"))).OnClicked_Lambda([Weak](){if(Weak.IsValid())Weak->Exit(true);return FReply::Handled();})]];
        GEngine->GameViewport->AddViewportWidgetContent(Mode->PreparingOverlay.ToSharedRef(),120);
    }
    Input->InteractionReturned=[Weak=TWeakObjectPtr<AOKInteractionMode>(Mode)](){if(Weak.IsValid())Weak->Exit();};
    return Mode;
}
AOKInteractionMode* AOKInteractionMode::EnterReader(UOKCharacterController* Source){
    if(!Source||Source->InteractionWidget||Source->bLoadInFlight||Source->Selected.Sex!=1)return nullptr;
    if(!IsValid(Source->PreviewActor)||!Source->PreviewActor->Session.IsOpen()){
        Source->bEnterInteractionAfterLoad=true;Source->OnLoad3D();return nullptr;
    }
    Source->ApplyPendingEditorMods();if(Source->bEditorModsDirty)return nullptr;
    auto* Shared=CreateWidget<UOKCharacterController>(Source->GetOwningPlayer());if(!Shared)return nullptr;
    Shared->bInteractionOnly=true;Shared->bIndependentCards=Source->bIndependentCards;Shared->Selected=Source->Selected;
    Shared->Entries=Source->Entries;Shared->SelectedIndex=Source->SelectedIndex;Shared->OutfitIndex=Source->OutfitIndex;
    Shared->PreviewOutfitIndex=Source->PreviewOutfitIndex;Shared->PreviewCardPath=Source->PreviewCardPath;Shared->CurrentCardDirectory=Source->CurrentCardDirectory;Shared->bModelLayout=true;
    FMemory::Memcpy(Shared->ClothesStates,Source->ClothesStates,9);FMemory::Memcpy(Shared->LoadedClothesStates,Source->LoadedClothesStates,9);
    Shared->InitializeInteractionControls();
    auto* Mode=Enter(Shared);if(!Mode)return nullptr;Mode->OwnController=true;
    Mode->LoadingFemale=Mode->GetWorld()->SpawnActor<AKKPreviewActor>();
    if(!Mode->LoadingFemale||!Source->PreviewActor->Session.CloneForInteraction(Mode->LoadingFemale->Session)){Mode->Fail(TEXT("無法複製目前角色的完整高模資源"));return nullptr;}
    FMemory::Memcpy(Mode->LoadingFemale->DisplayClothesStates,Source->PreviewActor->DisplayClothesStates,9);
    Mode->LoadingFemale->bPreserveSourceWorld=true;Mode->LoadingFemale->SetActorLocation(FVector::ZeroVector);Mode->LoadingFemale->SetActorHiddenInGame(true);Shared->bLoadInFlight=true;
    FString Error;if(!Mode->LoadingFemale->BeginSessionLoad(Error)){Mode->Fail(Error);return nullptr;}
    if(Source->PartnerMalePaths.IsValidIndex(Source->SelectedPartnerMale))Mode->MalePath=Source->PartnerMalePaths[Source->SelectedPartnerMale];
    else if(!Shared->PartnerMalePaths.IsEmpty())Mode->MalePath=Shared->PartnerMalePaths[0];
    const auto SourceVisibility=Source->GetVisibility();Source->SetVisibility(ESlateVisibility::Collapsed);
    Mode->Returned=[Weak=TWeakObjectPtr<UOKCharacterController>(Source),SourceVisibility](TSharedRef<FJsonObject>){if(Weak.IsValid()){Weak->SetVisibility(SourceVisibility);Weak->ApplyClickInputMode();}};
    return Mode;
}
AOKInteractionMode* AOKInteractionMode::EnterCards(APlayerController* Player,const FString& Female,const FString& Male,int32 FemaleOutfit,const FTransform* InPlace){
    if(!Player||!FPaths::FileExists(Female)||!FPaths::FileExists(Male))return nullptr;
    auto* Shared=CreateWidget<UOKCharacterController>(Player);Shared->bInteractionOnly=true;Shared->bIndependentCards=!UKKCardWorkspace::PortableSourcePath(Female).IsEmpty();Shared->Selected.Sex=1;Shared->InitializeInteractionControls();
    auto* Mode=Enter(Shared,InPlace);if(!Mode)return nullptr;
    Mode->OwnController=true;Mode->MalePath=Male;Mode->ReturnLabel=TEXT("返回多人街區");Mode->LoadFemale(Female,FemaleOutfit);return Mode;
}
void AOKInteractionMode::LoadFemale(const FString& Path,int32 Outfit){
    Controller->bLoadInFlight=true;
    const FString Portable=UKKCardWorkspace::PortableSourcePath(Path);
    const FString Root=Portable.IsEmpty()&&UKKGameRoot::Get()?UKKGameRoot::Get()->Root:FString();
    const FString Source=Portable.IsEmpty()?Path:Portable;
    auto Job=MakeShared<FInteractionRoleLoad,ESPMode::ThreadSafe>();const auto Token=Cancelled;TWeakObjectPtr<AOKInteractionMode> Weak(this);
    FOkSession::InitBindings();
    Async(EAsyncExecution::Thread,[Weak,Job,Token,Path,Root,Source,Outfit](){
        if(*Token)return;
        // Each step timed: March 7th's high model took 14 s here (Encore 1.6 s) with nothing in the log.
        const double T0=FPlatformTime::Seconds();
        Job->Ok=UKKCardReader::LoadFromFile(Path,Job->Card,Job->Error);
        if(Job->Ok&&Job->Card.Sex!=1){Job->Ok=false;Job->Error=TEXT("這張卡是男性角色，不能當女角：")+FPaths::GetCleanFilename(Path);}
        const double T1=FPlatformTime::Seconds();
        Job->Ok=Job->Ok&&Job->Session.Open(Root,Source,Outfit,Job->Error);
        const double T2=FPlatformTime::Seconds();double T3=T2,T35=T2,T4=T2;
        // Her materials first, every texture in parallel (the precache below then finds them prepared): one at a time,
        // March 7th's took 10 s here (Encore 1 s), the player looking at the loading screen.
        if(Job->Ok&&!*Token){Job->Session.ApplyBodyPhysics(Job->Card.Body.BustSoftness,Job->Card.Body.BustWeight);T3=FPlatformTime::Seconds();
         FString MaterialError;if(!Job->Session.PrepareRuntimeMaterials(MaterialError,true))UE_LOG(LogTemp,Warning,TEXT("Interaction female materials: %s"),*MaterialError);T35=FPlatformTime::Seconds();
         AKKPreviewActor::PrecacheSessionTextures(Job->Session,true);T4=FPlatformTime::Seconds();
         // The touch reactions' shared data, parsed here rather than in the frame her scene comes up.
         FString BodyError;if(!FOKBodyInteraction::WarmShared(BodyError))UE_LOG(LogTemp,Warning,TEXT("Interaction body data: %s"),*BodyError);
         // Her pair list too, as the card reader's own load does (RefreshPairs read it from the session on the game thread).
         Job->Pairs=Job->Session.NativeAnimationPairs();}
        UE_LOG(LogTemp,Display,TEXT("Interaction female load %s: card %.0f ms, session %.0f ms, body physics %.0f ms, materials %.0f ms, textures %.0f ms"),*FPaths::GetCleanFilename(Path),(T1-T0)*1000.,(T2-T1)*1000.,(T3-T2)*1000.,(T35-T3)*1000.,(T4-T35)*1000.);
        AsyncTask(ENamedThreads::GameThread,[Weak,Job,Token,Path,Outfit](){
            if(*Token||!Weak.IsValid())return;auto* Mode=Weak.Get();auto* C=Mode->Controller.Get();
            if(!Job->Ok){Mode->Fail(Job->Error.IsEmpty()?TEXT("女角高模載入失敗"):Job->Error);return;}
            C->Selected=MoveTemp(Job->Card);C->Entries.Reset();auto& E=C->Entries.AddDefaulted_GetRef();E.Path=Path;E.FileName=FPaths::GetCleanFilename(Path);C->SelectedIndex=0;C->OutfitIndex=Outfit;C->PreviewOutfitIndex=Outfit;C->PreviewCardPath=Path;C->bModelLayout=true;
            if(!Job->Pairs.IsEmpty()){C->PendingLoadPairJson=MoveTemp(Job->Pairs);C->PendingLoadPairGeneration=C->LoadGeneration;}
            Mode->LoadingFemale=Mode->GetWorld()->SpawnActor<AKKPreviewActor>();if(!Mode->LoadingFemale){Mode->Fail(TEXT("無法建立高模角色"));return;}Mode->LoadingFemale->bPreserveSourceWorld=true;if(Mode->bInPlace)Mode->LoadingFemale->SetActorTransform(FTransform(Mode->InPlaceAt.GetRotation(),Mode->InPlaceAt.GetLocation()));else Mode->LoadingFemale->SetActorLocation(FVector::ZeroVector);Mode->LoadingFemale->SetActorHiddenInGame(true);Mode->LoadingFemale->Session=MoveTemp(Job->Session);
            FString Error;if(!Mode->LoadingFemale->BeginSessionLoad(Error)){Mode->Fail(Error);return;}
        });
    });
}
bool AOKInteractionMode::ChangeOutfit(int32 Outfit,const FString& Coordinate,bool bWithAccessories){
    if(Outfit<0||(Controller&&Controller->Selected.Outfits.Num()>0&&Outfit>=Controller->Selected.Outfits.Num()))return false;
    if(!Coordinate.IsEmpty()&&!FPaths::FileExists(Coordinate))return false;
    return StartSwap(Outfit,Coordinate,bWithAccessories,nullptr);
}
FString AOKInteractionMode::OpenedRoot() const{
    return UKKCardWorkspace::PortableSourcePath(OpenedFemaleCard()).IsEmpty()&&UKKGameRoot::Get()?UKKGameRoot::Get()->Root:FString();
}
FString AOKInteractionMode::OpenedFemaleCard() const{return !OpenedCard.IsEmpty()?OpenedCard:Controller&&Controller->Entries.IsValidIndex(0)?Controller->Entries[0].Path:FString();}
bool AOKInteractionMode::ClothesTransition(int32 Kind,uint8 Out[9],FString& Why) const{
    if(!Controller)return false;
    return FOkSession::ClothingTransition(OpenedRoot(),OpenedFemaleCard(),Controller->OutfitIndex,Controller->ClothesStates,Kind,Out,Why);
}
bool AOKInteractionMode::ChangeClothesStates(const uint8 States[9]){return Controller&&StartSwap(Controller->OutfitIndex,FString(),false,States);}
bool AOKInteractionMode::StartSwap(int32 Outfit,const FString& Coordinate,bool bWithAccessories,const uint8* States){
    if(!Ready||Finished||IsChangingOutfit()||!Controller||!IsValid(Controller->PreviewActor)||!Controller->Entries.IsValidIndex(0))return false;
    // States: the same clothes opened again in these states (half off is another part of the garment, chosen as she opens).
    OutfitChanging=true;OutfitError.Reset();SwapOutfit=Outfit;bSwapClothesOnly=States!=nullptr;SwapCoordinate=States?WornCoordinate:Coordinate;
    TArray<uint8> Opening;Opening.SetNumZeroed(9);if(States)for(int32 K=0;K<9;++K)Opening[K]=States[K];FMemory::Memcpy(SwapStates,Opening.GetData(),9);
    const FString Card=States?OpenedFemaleCard():Controller->Entries[0].Path;const FVector2D Physics(Controller->Selected.Body.BustSoftness,Controller->Selected.Body.BustWeight);
    const FString GameRoot=UKKGameRoot::Get()?UKKGameRoot::Get()->Root:FString();
    auto Job=MakeShared<FInteractionRoleLoad,ESPMode::ThreadSafe>();const auto Token=Cancelled;TWeakObjectPtr<AOKInteractionMode> Weak(this);
    UE_LOG(LogTemp,Display,TEXT("H scene outfit change: outfit %d%s%s"),Outfit,Coordinate.IsEmpty()?TEXT(""):TEXT(" coordinate "),*Coordinate);
    Async(EAsyncExecution::Thread,[Weak,Job,Token,Card,Coordinate,Outfit,Physics,GameRoot,bWithAccessories,Opening](){
        if(*Token)return;const double T0=FPlatformTime::Seconds();
        FString Path=Card;
        if(!Coordinate.IsEmpty()){
            // Her card with the coordinate card written into this outfit, made once per card, coordinate and outfit.
            const FString Dir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("StreetSocial/HOutfits"));IFileManager::Get().MakeDirectory(*Dir,true);
            const FString Clothes=Dir/(FPaths::GetBaseFilename(Coordinate)+TEXT(".okclothes"));
            const FString Worn=Dir/FString::Printf(TEXT("%s__%s_%d%s.png"),*FPaths::GetBaseFilename(Card),*FPaths::GetBaseFilename(Coordinate),Outfit,bWithAccessories?TEXT("_acc"):TEXT(""));
            const FDateTime Made=IFileManager::Get().GetTimeStamp(*Worn);
            if(Made==FDateTime::MinValue()||Made<IFileManager::Get().GetTimeStamp(*Card)||Made<IFileManager::Get().GetTimeStamp(*Coordinate)){
                // Worn on her card as the game's card (its OK chunks, ok*, dropped) and opened from the game: an OK card
                // wearing new clothes would be made again (oklib::remake_ok_card, a minute, and only with every zipmod
                // its outfits name installed), too long to wait for in the scene.
                FString Summary;TArray<uint8> Bytes,Plain;const FString PlainCard=Dir/(FPaths::GetBaseFilename(Card)+TEXT("__game.png"));
                bool Stripped=FFileHelper::LoadFileToArray(Bytes,*Card)&&Bytes.Num()>8&&FMemory::Memcmp(Bytes.GetData(),"\x89PNG\r\n\x1a\n",8)==0;
                if(Stripped){Plain.Append(Bytes.GetData(),8);int64 Pos=8;Stripped=false;
                    while(Pos+12<=Bytes.Num()){const uint32 Len=(uint32(Bytes[Pos])<<24)|(uint32(Bytes[Pos+1])<<16)|(uint32(Bytes[Pos+2])<<8)|uint32(Bytes[Pos+3]);const int64 End=Pos+12+int64(Len);
                        if(End>Bytes.Num())break;const uint8* Type=&Bytes[Pos+4];
                        if(FMemory::Memcmp(Type,"IEND",4)==0){Plain.Append(&Bytes[Pos],Bytes.Num()-Pos);Stripped=true;break;}
                        if(!(Type[0]=='o'&&Type[1]=='k'))Plain.Append(&Bytes[Pos],End-Pos);Pos=End;}}
                if(!Stripped||!FFileHelper::SaveArrayToFile(Plain,*PlainCard))Job->Error=TEXT("無法讀取她的角色卡：")+Card;
                else if(!FOkSession::ClothesImport(Coordinate,Clothes,Summary)){Job->Error=TEXT("服裝卡讀取失敗：")+Summary;}
                else if(!(bWithAccessories?FOkSession::ClothesWear(PlainCard,Clothes,Outfit,Worn,Summary):FOkSession::ClothesWearClothesOnly(PlainCard,Clothes,Outfit,Worn,Summary))){Job->Error=TEXT("穿上服裝卡失敗：")+Summary;}
                UE_LOG(LogTemp,Display,TEXT("H scene outfit: coordinate %s worn as outfit %d -> %s: %s"),*FPaths::GetCleanFilename(Coordinate),Outfit,*Worn,*Summary);
            }
            if(!Job->Error.IsEmpty()){AsyncTask(ENamedThreads::GameThread,[Weak,Job](){if(auto* Mode=Weak.Get()){Mode->OutfitChanging=false;Mode->OutfitError=Job->Error;if(Mode->Controller&&Mode->Controller->HPanel)Mode->Controller->HPanel->OutfitChanged(false);}});return;}
            Path=Worn;
        }
        const double T1=FPlatformTime::Seconds();
        const FString Portable=UKKCardWorkspace::PortableSourcePath(Path);
        if(Portable.IsEmpty()&&GameRoot.IsEmpty())Job->Error=TEXT("沒有設定遊戲目錄，不能開啟服裝卡的衣服");
        else Job->Ok=Job->Session.Open(Portable.IsEmpty()?GameRoot:FString(),Portable.IsEmpty()?Path:Portable,Outfit,Job->Error,Opening.GetData());
        Job->Opened=Path;
        const double T2=FPlatformTime::Seconds();
        if(Job->Ok&&!*Token){Job->Session.ApplyBodyPhysics(Physics.X,Physics.Y);
            FString MaterialError;if(!Job->Session.PrepareRuntimeMaterials(MaterialError,true))UE_LOG(LogTemp,Warning,TEXT("H scene outfit materials: %s"),*MaterialError);
            AKKPreviewActor::PrecacheSessionTextures(Job->Session,true);}
        UE_LOG(LogTemp,Display,TEXT("H scene outfit open: wear %.0f ms, session %.0f ms, materials and textures %.0f ms"),(T1-T0)*1000.,(T2-T1)*1000.,(FPlatformTime::Seconds()-T2)*1000.);
        AsyncTask(ENamedThreads::GameThread,[Weak,Job,Token](){
            if(*Token||!Weak.IsValid())return;auto* Mode=Weak.Get();auto* C=Mode->Controller.Get();
            auto Failed=[&](const FString& Why){Mode->OutfitChanging=false;Mode->OutfitError=Why;UE_LOG(LogTemp,Warning,TEXT("H scene outfit change failed: %s"),*Why);if(C&&C->HPanel)C->HPanel->OutfitChanged(false);};
            if(!C||!IsValid(C->PreviewActor)){Mode->OutfitChanging=false;return;}
            if(!Job->Ok){Failed(Job->Error.IsEmpty()?TEXT("新服裝載入失敗"):Job->Error);return;}
            auto* Actor=Mode->GetWorld()->SpawnActor<AKKPreviewActor>(C->PreviewActor->GetActorLocation(),C->PreviewActor->GetActorRotation());if(!Actor){Failed(TEXT("無法建立角色"));return;}
            Actor->bPreserveSourceWorld=true;Actor->SetActorHiddenInGame(true);Actor->SetActorTickEnabled(false);Actor->Session=MoveTemp(Job->Session);
            FString Error;if(!Actor->BeginSessionLoad(Error)){Actor->Destroy();Failed(Error);return;}
            Mode->SwappingFemale=Actor;Mode->SwapOpened=Job->Opened;Mode->OutfitChanging=false;
        });
    });
    return true;
}
void OKRetireActor(AActor* Actor); // OKGalleryWidget.cpp
void AOKInteractionMode::TickOutfitSwap(){
    AKKPreviewActor* New=SwappingFemale;if(!New)return;
    auto* Old=Controller->PreviewActor.Get();FString Why;
    if(!IsValid(Old)||!New->ContinueSessionLoad(Why)){SwappingFemale=nullptr;New->Destroy();OutfitError=Why.IsEmpty()?TEXT("新服裝載入失敗"):Why;if(Controller->HPanel)Controller->HPanel->OutfitChanged(false);return;}
    if(!New->IsSessionLoadComplete()||!New->BeginProgressiveMaterials())return;
    SwappingFemale=nullptr;
    // The pair player holds views into her old session: it stops here and starts again on her new one in the state it was
    // in (the card reader's reload of the same card), so she goes on where she was.
    Controller->KeepPartnerForReload();
    Controller->CancelPairPreparation();
    if(Controller->PairedPlayback){Controller->PairedPlayback->Stop();Controller->PairedPlayback->Destroy();Controller->PairedPlayback=nullptr;}
    Old->StopSpeech();Old->StopHBreath();
    New->SetActorTransform(Old->GetActorTransform());New->bPairOriginSet=Old->bPairOriginSet;New->PairOrigin=Old->PairOrigin;
    New->ApplyShapes(Controller->Selected.Face.ShapeValueFace,Controller->Selected.Body.ShapeValueBody);
    New->SpeechLines=Old->SpeechLines;New->SpeechPitch=Old->SpeechPitch;New->bSpeechDrivesMouth=Old->bSpeechDrivesMouth;
    // The view stays where the player had it.
    if(New->StudioCam&&New->StudioCam!=Old->StudioCam)New->StudioCam->Destroy();
    New->StudioCam=Old->StudioCam;Old->StudioCam=nullptr;
    New->OrbitFocus=Old->OrbitFocus;New->OrbitYaw=Old->OrbitYaw;New->OrbitPitch=Old->OrbitPitch;New->OrbitDistance=Old->OrbitDistance;
    // The pieces he had taken off stay off (the original keeps fileStatus.clothesState over a coordinate change).
    FMemory::Memcpy(New->DisplayClothesStates,SwapStates,9);New->SetClothingPartsHidden(Controller->ClothesStates);
    if(PairPhysicsActors.Remove(Old))Old->RemovePairPhysics();
    Controller->PreviewActor=New;Controller->OutfitIndex=SwapOutfit;Controller->PreviewOutfitIndex=SwapOutfit;WornCoordinate=SwapCoordinate;OpenedCard=SwapOpened;
    New->SetActorHiddenInGame(false);New->SetActorTickEnabled(true);
    if(IsValid(Controller->PartnerActor))Controller->PartnerActor->SetActorTickEnabled(true);
    OKRetireActor(Old);
    UpdatePairPhysics();
    Controller->RestorePairAfterReload();
    UE_LOG(LogTemp,Display,TEXT("H scene outfit changed: outfit %d%s%s, %d parts"),SwapOutfit,SwapCoordinate.IsEmpty()?TEXT(""):TEXT(" coordinate "),*FPaths::GetCleanFilename(SwapCoordinate),New->Session.PartCount());
    if(Controller->HPanel)Controller->HPanel->OutfitChanged(true);
}
void AOKInteractionMode::BeginHScene(const FString& Name,const FString& Stage,const TSharedPtr<FJsonObject>& Experience,const FString& Player){
    if(!Controller)return;Controller->bHScene=true;Controller->HPlayerName=Player;Controller->HHeroineName=Name;Controller->HHeroineStage=Stage;Controller->HExperience=Experience;Controller->HResult.Reset();
}
TSharedPtr<FJsonObject> AOKInteractionMode::HSceneControl(const TSharedPtr<FJsonObject>& Body,FString& Why){
    UOKHScenePanel* Panel=Controller?Controller->HPanel.Get():nullptr;if(!Panel){Why=TEXT("no H panel (scene not ready)");return nullptr;}
    double Kind=0,Speed=-1;FString Pose;
    if(Body.IsValid()){
        if(Body->TryGetNumberField(TEXT("speed"),Speed)&&Speed>=0)Panel->SetSpeed(float(Speed));
        bool Pause=false;if(Body->TryGetBoolField(TEXT("pause"),Pause))SetHPaused(Pause); // {"pause":true}: as the space key
        if(Body->TryGetStringField(TEXT("pose"),Pose)&&!Pose.IsEmpty()&&!Panel->SelectPoseNamed(Pose)){Why=TEXT("no pose named ")+Pose;return nullptr;}
        if(Body->TryGetNumberField(TEXT("kind"),Kind)&&Kind>0)Panel->Click(int32(Kind));
        FString Say;if(Body->TryGetStringField(TEXT("say"),Say)&&!Say.IsEmpty())Panel->Say(Say);
        // {"outfit":N}: her card's outfit N (0..6); {"coordinate":"file name or path"}: a game coordinate card worn as the
        // outfit she has on. Both load in the background (outfit_changing in the answer until she is swapped in).
        double OutfitN=-1;FString Coordinate,OutfitWhy;
        if(Body->TryGetNumberField(TEXT("outfit"),OutfitN)&&OutfitN>=0&&!Panel->WearOutfit(int32(OutfitN),FString(),OutfitWhy)){Why=OutfitWhy;return nullptr;}
        bool WithAccessories=false;if(Body->TryGetBoolField(TEXT("accessories"),WithAccessories))Panel->bCoordinateAccessories=WithAccessories; // {"accessories":true}: its accessories too
        if(Body->TryGetStringField(TEXT("coordinate"),Coordinate)&&!Coordinate.IsEmpty()&&!Panel->WearOutfit(Controller->OutfitIndex,Coordinate,OutfitWhy)){Why=OutfitWhy;return nullptr;}
        // {"height":{"her":0..1,"him":0..1}}: their height slider (ChaFile shapeBody[0]) for testing the pair at other sizes.
        double BlushValue;if(Body->TryGetNumberField(TEXT("blush"),BlushValue))Panel->BlushTest=float(BlushValue);
        // {"orbit":[yaw,pitch,distance]}: the camera round her hips, turned from where she faces (pose checks from the side and the front).
        const TArray<TSharedPtr<FJsonValue>>* Orbit=nullptr;if(Body->TryGetArrayField(TEXT("orbit"),Orbit)&&Orbit->Num()==3&&IsValid(Controller->PreviewActor)){auto* Girl=Controller->PreviewActor.Get();
            FVector Hips=Girl->GetActorLocation();if(Girl->BodySkel){const int32 Bone=Girl->BodySkel->GetBoneIndex(TEXT("j_hips"));if(Bone!=INDEX_NONE)Hips=Girl->BodySkel->GetBoneTransform(Bone).GetLocation();}
            Girl->OrbitFocus=Hips;Girl->OrbitYaw=float((*Orbit)[0]->AsNumber())+Girl->GetActorRotation().Yaw;Girl->OrbitPitch=float((*Orbit)[1]->AsNumber());Girl->OrbitDistance=float((*Orbit)[2]->AsNumber());Girl->ApplyOrbitCamera();}
#if !UE_BUILD_SHIPPING
        // {"spray":true|false}: the player's water gun (A + left button) at what the camera looks at; game.log says what landed.
        bool Spray=false;if(Body->TryGetBoolField(TEXT("spray"),Spray))if(auto* PC=Cast<AOpenKoikatsuPlayerController>(Controller->GetOwningPlayer())){
            if(Spray&&Controller->PreviewActor)PC->ScriptedPaintAim=Controller->PreviewActor->OrbitFocus;else PC->ScriptedPaintAim.Reset();
            PC->bScriptedPaintFire=Spray;
            UE_LOG(LogTemp,Display,TEXT("H control spray %d: preview=%d hits=%d deposited=%.3f"),Spray,PC->IsPaintPreviewActive(),PC->PaintSprayer?PC->PaintSprayer->HitCount:-1,PC->PaintSprayer?PC->PaintSprayer->Deposited:-1.);}
#endif
        // {"siru":[face,ftop,fbot,btop,bbot]}: set the liquid levels (0..2) directly, to look at how they draw.
        const TArray<TSharedPtr<FJsonValue>>* SiruLevels=nullptr;if(Body->TryGetArrayField(TEXT("siru"),SiruLevels)&&SiruLevels->Num()==5){int32 L[5];for(int32 A=0;A<5;++A)L[A]=int32((*SiruLevels)[A]->AsNumber());Panel->SetSiruTest(L);}
        // {"leave":true}: the scene ends as the leave button ends it.
        bool Leave=false;if(Body->TryGetBoolField(TEXT("leave"),Leave)&&Leave){Exit();Why=TEXT("left");return nullptr;}
        // {"dev_set":{"oral":55,...}}: as the left panel's sliders, kept with her when the scene ends.
        const TSharedPtr<FJsonObject>* Sets=nullptr;if(Body->TryGetObjectField(TEXT("dev_set"),Sets))for(const auto& D:(*Sets)->Values)Panel->SetDev(*D.Key,float(D.Value->AsNumber()));
        // {"dev":{"oral":100,...}}: her development there, for testing (0..100; -1 back to hers).
        const TSharedPtr<FJsonObject>* Devs=nullptr;if(Body->TryGetObjectField(TEXT("dev"),Devs))for(const auto& D:(*Devs)->Values){const double V=D.Value->AsNumber();if(V<0.)Panel->DevTest.Remove(FString(D.Key));else Panel->DevTest.Add(FString(D.Key),float(V));}
        bool Green=false;if(Body->TryGetBoolField(TEXT("penis_green"),Green))Panel->SetPenisGreen(Green);
        // {"preg":{"belly":0.8,"body":0.5}}: her pregnant belly and changed areolae held there for testing (-1 hers).
        const TSharedPtr<FJsonObject>* Preg=nullptr;if(Body->TryGetObjectField(TEXT("preg"),Preg)){double V=0;
            if((*Preg)->TryGetNumberField(TEXT("belly"),V))Panel->PregBellyTest=float(V);if((*Preg)->TryGetNumberField(TEXT("body"),V))Panel->PregBodyTest=float(V);Panel->PregCheckAt=0.;}
        // {"her_pose":{"ankle":20,"thigh_l":30,"thigh_r":0,"hand_l":3,"hand_r":-1}}: her pose as the panel sets it (degrees;
        // a hand pattern, -1 as the motion). Fields left out stay as they are.
        const TSharedPtr<FJsonObject>* HerPose=nullptr;if(Body->TryGetObjectField(TEXT("her_pose"),HerPose)){double V;float F[3];int32 H[2];const float* FP[3]={};const int32* HP[2]={};
            static const TCHAR* FK[3]={TEXT("ankle"),TEXT("thigh_l"),TEXT("thigh_r")};for(int32 I=0;I<3;++I)if((*HerPose)->TryGetNumberField(FK[I],V)){F[I]=float(V);FP[I]=&F[I];}
            static const TCHAR* HK[2]={TEXT("hand_l"),TEXT("hand_r")};for(int32 I=0;I<2;++I)if((*HerPose)->TryGetNumberField(HK[I],V)){H[I]=int32(V);HP[I]=&H[I];}
            Panel->SetHerPose(FP[0],FP[1],FP[2],HP[0],HP[1]);}
        // {"penis":{"length":1.2,"scale":1.1,"root":[x,y]}}: his penis set as the panel's sliders and pad do.
        const TSharedPtr<FJsonObject>* Penis=nullptr;if(Body->TryGetObjectField(TEXT("penis"),Penis)){double L=-1,S=-1;(*Penis)->TryGetNumberField(TEXT("length"),L);(*Penis)->TryGetNumberField(TEXT("scale"),S);
            if(L>0||S>0)Panel->SetPenis(L>0?float(L):1.f,S>0?float(S):1.f,5.f);
            const TArray<TSharedPtr<FJsonValue>>* Root=nullptr;if((*Penis)->TryGetArrayField(TEXT("root"),Root)&&Root->Num()==2)Panel->SetRootPad(FVector2D((*Root)[0]->AsNumber(),(*Root)[1]->AsNumber()),3.f);}
        double FaceCam=0;const TSharedPtr<FJsonObject>* FaceView=nullptr;if(Body->TryGetNumberField(TEXT("face_cam"),FaceCam))Panel->LookAtFace(float(FaceCam));
        else if(Body->TryGetObjectField(TEXT("face_cam"),FaceView)){double Dist=40,Turn=0;(*FaceView)->TryGetNumberField(TEXT("distance"),Dist);(*FaceView)->TryGetNumberField(TEXT("turn"),Turn);Panel->LookAtFace(float(Dist),float(Turn));} // {"face_cam":{"distance":40,"turn":90}}: from her side
        double CrotchCam=0;const TSharedPtr<FJsonObject>* CrotchView=nullptr;if(Body->TryGetNumberField(TEXT("crotch_cam"),CrotchCam))Panel->LookAtCrotch(float(CrotchCam));
        else if(Body->TryGetObjectField(TEXT("crotch_cam"),CrotchView)){double Dist=60,Pitch=15,Turn=0;(*CrotchView)->TryGetNumberField(TEXT("distance"),Dist);(*CrotchView)->TryGetNumberField(TEXT("pitch"),Pitch);(*CrotchView)->TryGetNumberField(TEXT("turn"),Turn);bool Front=false;(*CrotchView)->TryGetBoolField(TEXT("front"),Front);Panel->LookAtCrotch(float(Dist),float(Pitch),float(Turn),Front);}
        const TSharedPtr<FJsonObject>* Heights=nullptr;if(Body->TryGetObjectField(TEXT("height"),Heights)){
            // The pair player holds views into both sessions: reshaping under it crashed the game. Stop it first; the next pose
            // chosen makes the pair again at the new sizes.
            Controller->CancelPairPreparation();
            if(Controller->PairedPlayback){Controller->PairedPlayback->Stop();Controller->PairedPlayback->Destroy();Controller->PairedPlayback=nullptr;}
            for(AKKPreviewActor* A:{Controller->PreviewActor.Get(),Controller->PartnerActor.Get()})if(IsValid(A))A->SetActorTickEnabled(true);
            auto Set=[](AKKPreviewActor* A,double V){if(!IsValid(A)||A->ShapeBody.IsEmpty())return;A->ShapeBody[0]=float(V);A->ApplyShapes(A->ShapeFace,A->ShapeBody);};
            double V;if((*Heights)->TryGetNumberField(TEXT("her"),V))Set(Controller->PreviewActor,V);if((*Heights)->TryGetNumberField(TEXT("him"),V))Set(Controller->PartnerActor,V);}
    }
    TSharedPtr<FJsonObject> View=Panel->Describe();
    View->SetNumberField(TEXT("outfit"),Controller->OutfitIndex);View->SetStringField(TEXT("coordinate"),WornCoordinate);
    View->SetBoolField(TEXT("outfit_changing"),IsChangingOutfit());View->SetStringField(TEXT("outfit_error"),OutfitError);
    // {"faces":true}: her eye (1) and brow (2) pattern labels, for choosing expressions.
    bool Faces=false;if(View.IsValid()&&Body.IsValid()&&Body->TryGetBoolField(TEXT("faces"),Faces)&&Faces&&IsValid(Controller->PreviewActor))
        for(int32 Control=1;Control<=2;++Control){TArray<TSharedPtr<FJsonValue>> L;for(int32 P=0;P<Controller->PreviewActor->GetFacePatternCount(Control);++P)L.Add(MakeShared<FJsonValueString>(Controller->PreviewActor->GetFacePatternLabel(Control,P)));View->SetArrayField(Control==1?TEXT("eyes"):TEXT("brows"),L);}
    if(Faces&&View.IsValid()&&IsValid(Controller->PreviewActor)){TArray<TSharedPtr<FJsonValue>> L;for(int32 P=0;P<Controller->PreviewActor->GetMouthPatternCount();++P)L.Add(MakeShared<FJsonValueString>(Controller->PreviewActor->GetMouthPatternLabel(P)));View->SetArrayField(TEXT("mouths"),L);}
    // {"parts":true}: every mesh component on her (role, class, shown), to see what draws.
    bool PartsDump=false;if(View.IsValid()&&Body.IsValid()&&Body->TryGetBoolField(TEXT("parts"),PartsDump)&&PartsDump&&IsValid(Controller->PreviewActor)){
        TArray<TSharedPtr<FJsonValue>> L;TInlineComponentArray<UMeshComponent*> Components;Controller->PreviewActor->GetComponents(Components);
        for(UMeshComponent* C:Components){int32 Index=INDEX_NONE;for(const FName& Tag:C->ComponentTags)if(Tag.ToString().StartsWith(TEXT("KKSessionPart_")))Index=FCString::Atoi(*Tag.ToString().Mid(14));
            FString PartRole;OkMeshView V{};if(Index!=INDEX_NONE&&Controller->PreviewActor->Session.PartAt(Index,V)&&V.role)PartRole=UTF8_TO_TCHAR(V.role);
            // Each slot's material: its name, d for a dynamic instance, st when it has the iris tiling (_MainTex_ST), rows when gaze rows.
            FString Mats;for(int32 S=0;S<C->GetNumMaterials();++S)if(UMaterialInterface* M=C->GetMaterial(S)){FLinearColor P;
                Mats+=FString::Printf(TEXT(" %s%s%s%s"),*M->GetName(),M->IsA<UMaterialInstanceDynamic>()?TEXT(":d"):TEXT(""),M->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("_MainTex_ST")),P)?TEXT(":st"):TEXT(""),M->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("KKEyeUV0Row0")),P)?TEXT(":rows"):TEXT(""));}
            L.Add(MakeShared<FJsonValueString>(FString::Printf(TEXT("%d %s %s %s vis=%d hig=%d main=%d parent=%s mats=%s"),Index,*PartRole,*C->GetClass()->GetName(),*C->GetName(),C->IsVisible(),C->bHiddenInGame,C->bRenderInMainPass,C->GetAttachParent()?*C->GetAttachParent()->GetName():TEXT("-"),*Mats)));}
        View->SetArrayField(TEXT("parts"),L);}
    // {"his_parts":true}: the same for him, with each part's renderer name (the penis is o_dankon / cm_o_dan00).
    bool HisDump=false;if(View.IsValid()&&Body.IsValid()&&Body->TryGetBoolField(TEXT("his_parts"),HisDump)&&HisDump&&IsValid(Controller->PartnerActor)){
        TArray<TSharedPtr<FJsonValue>> L;TInlineComponentArray<UMeshComponent*> Components;Controller->PartnerActor->GetComponents(Components);
        for(UMeshComponent* C:Components){int32 Index=INDEX_NONE;for(const FName& Tag:C->ComponentTags)if(Tag.ToString().StartsWith(TEXT("KKSessionPart_")))Index=FCString::Atoi(*Tag.ToString().Mid(14));
            FString PartRole,PartName;OkMeshView V{};if(Index!=INDEX_NONE&&Controller->PartnerActor->Session.PartAt(Index,V)){if(V.role)PartRole=UTF8_TO_TCHAR(V.role);if(V.name)PartName=UTF8_TO_TCHAR(V.name);}
            const UMaterialInterface* M=C->GetNumMaterials()>0?C->GetMaterial(0):nullptr;
            L.Add(MakeShared<FJsonValueString>(FString::Printf(TEXT("%d %s %s vis=%d mat=%s"),Index,*PartRole,*PartName,C->IsVisible(),M?*M->GetName():TEXT("-"))));}
        View->SetArrayField(TEXT("his_parts"),L);}
    // {"bones":true}: where their hips, hands, feet and heads are (world cm), for placing props under a pose.
    bool BonesDump=false;if(View.IsValid()&&Body.IsValid()&&Body->TryGetBoolField(TEXT("bones"),BonesDump)&&BonesDump){
        auto Dump=[&](AKKPreviewActor* A,const TCHAR* Field,const TCHAR* P){if(!IsValid(A)||!A->BodySkel)return;auto O=MakeShared<FJsonObject>();
            for(const TCHAR* B:{TEXT("j_hips"),TEXT("j_hand_L"),TEXT("j_hand_R"),TEXT("j_foot_L"),TEXT("j_foot_R"),TEXT("j_head"),TEXT("j_spine02")}){const FName Name(FString(P)+B);
                if(A->BodySkel->GetBoneIndex(Name)==INDEX_NONE)continue;const FVector L=A->BodySkel->GetBoneLocation(Name);O->SetStringField(B,FString::Printf(TEXT("%.0f %.0f %.0f"),L.X,L.Y,L.Z));}
            // Her soft parts (bust and hip dynamics, ok.Physics.*): where each sits in the frame of the bone it hangs from (mm):
            // the hips in her waist's, the bust in her upper spine's, so the clip's own motion of her body drops out.
            auto Soft=[&](const TCHAR* Frame,std::initializer_list<const TCHAR*> Bones){const int32 W=A->BodySkel->GetBoneIndex(FName(FString(P)+Frame));if(W==INDEX_NONE)return;
                const FTransform WT=A->BodySkel->GetBoneTransform(W);
                for(const TCHAR* B:Bones){const int32 I=A->BodySkel->GetBoneIndex(FName(FString(P)+B));if(I==INDEX_NONE)continue;
                    const FVector L=WT.InverseTransformPosition(A->BodySkel->GetBoneTransform(I).GetLocation())*10.;O->SetStringField(B,FString::Printf(TEXT("%.1f %.1f %.1f"),L.X,L.Y,L.Z));}};
            Soft(TEXT("j_waist02"),{TEXT("d_siri_L"),TEXT("d_siri_R"),TEXT("j_siri_L"),TEXT("j_siri_R")});
            Soft(TEXT("j_spine03"),{TEXT("j_bust03_L"),TEXT("j_bust03_R"),TEXT("d_bust03_L"),TEXT("d_bnip01_L")});
            O->SetStringField(TEXT("actor"),A->GetActorLocation().ToCompactString());View->SetObjectField(Field,O);};
        Dump(Controller->PreviewActor,TEXT("her_bones"),TEXT("cf_"));Dump(Controller->PartnerActor,TEXT("his_bones"),TEXT("cm_"));}
    return View;
}
bool AOKInteractionMode::HSceneTakeLine(FString& Text,FString& Context,bool& System){return Controller&&Controller->HPanel&&Controller->HPanel->TakeLine(Text,Context,System);}
bool AOKInteractionMode::HSceneHear(const FString& Text,FString& Context){return Controller&&Controller->HPanel&&Controller->HPanel->Hear(Text,Context);}
void AOKInteractionMode::HSceneShowLine(const FString& Text){if(Controller&&Controller->HPanel)Controller->HPanel->ShowLine(Text);}
FString AOKInteractionMode::HSceneJudgeFacts() const{return Controller&&Controller->HPanel?Controller->HPanel->JudgeFacts():FString();}
bool AOKInteractionMode::HSceneApplyTalk(const TSharedPtr<FJsonObject>& Verdict){return Controller&&Controller->HPanel&&Controller->HPanel->ApplyTalk(Verdict);}
extern TAutoConsoleVariable<int32> CVarHTtsLines; // OKHScene.cpp
bool AOKInteractionMode::HSceneSpeak(const FString& Path){
    if(!CVarHTtsLines.GetValueOnGameThread())return false;
    if(!Controller||!IsValid(Controller->PreviewActor))return false;auto* Her=Controller->PreviewActor.Get();
    if(Controller->HPanel&&Controller->HPanel->LineIsStale())return false; // said to what happened before (UOKHScenePanel::ShowLine)
    Her->StopHBreath();FString Why;const bool Ok=Her->PlaySpeechFile(Path,1.f,Why);
    if(!Ok)UE_LOG(LogTemp,Warning,TEXT("H scene: her line did not play: %s"),*Why);
    if(Ok)UE_LOG(LogTemp,Display,TEXT("H scene: her line spoken on her (%s)"),*FPaths::GetCleanFilename(Path));
    if(Ok&&Controller->HPanel)Controller->HPanel->SpokeLine();
    return Ok;
}
bool AOKInteractionMode::HSceneHasReaction() const{return Controller&&Controller->HPanel&&Controller->HPanel->HasReaction();}
bool AOKInteractionMode::HSceneSpeaking() const{return Controller&&IsValid(Controller->PreviewActor)&&Controller->PreviewActor->IsSpeaking()&&!Controller->PreviewActor->bHBreath;}
void AOKInteractionMode::Fail(const FString& Why){Error=Why;UE_LOG(LogTemp,Error,TEXT("Shared interaction mode: %s"),*Why);Exit(true);}
void AOKInteractionMode::SetHPaused(bool bPaused){
    if(!Controller||!Controller->PairedPlayback)return;
    Controller->PairedPlayback->SetPaused(bPaused);if(Controller->PreviewActor)Controller->PreviewActor->SetSpeechPaused(bPaused);if(Controller->PartnerActor)Controller->PartnerActor->SetSpeechPaused(bPaused);
    UE_LOG(LogTemp,Display,TEXT("H scene: %s"),bPaused?TEXT("paused"):TEXT("resumed"));
}
void AOKInteractionMode::Tick(float Delta){
    Super::Tick(Delta);if(Finished||!Controller)return;
    if(auto* PC=Controller->GetOwningPlayer())if(PC->WasInputKeyJustPressed(EKeys::Escape)){Exit(!Ready);return;}
    // Space pauses or resumes the two of them (user, 2026-11-02: to take pictures), not while typing to her.
    if(auto* PC=Controller->GetOwningPlayer())if(Controller->HPanel&&Controller->PairedPlayback&&PC->WasInputKeyJustPressed(EKeys::SpaceBar)){
        const TSharedPtr<SWidget> Focus=FSlateApplication::IsInitialized()?FSlateApplication::Get().GetKeyboardFocusedWidget():nullptr;
        if(!Focus||!Focus->GetType().ToString().Contains(TEXT("EditableText")))SetHPaused(!Controller->PairedPlayback->IsPaused());}
    if(FPlatformTime::Seconds()-Started>180&&!Ready&&(!Activated||ReturnLabel==TEXT("返回多人街區"))){Fail(TEXT("一對一互動準備逾時"));return;}
    if(LoadingFemale){FString Why;
        if(!LoadingFemale->ContinueSessionLoad(Why)){Fail(Why);return;}
        if(!LoadingFemale->IsSessionLoadComplete())return;
        bool FullOff=true;for(uint8 State:Controller->ClothesStates)FullOff&=State==3;
        if(FullOff)LoadingFemale->SetClothingHidden(true);
        if(!LoadingFemale->BeginProgressiveMaterials())return;
        Controller->PreviewActor=LoadingFemale;LoadingFemale=nullptr;Controller->PreviewActor->SetActorTickEnabled(false);Controller->bLoadInFlight=false;
        Controller->PreviewActor->ApplyShapes(Controller->Selected.Face.ShapeValueFace,Controller->Selected.Body.ShapeValueBody);
        Controller->PreviewActor->SetupStudioView(true);Controller->PreviewActor->SetActorHiddenInGame(false);Controller->RefreshPairs();
        // SetupStudioView stands her at the world's origin, which on the street is a square outdoors: she tried the shop's
        // dress on in the open. A fitting stays where she was, in the shop, and the camera takes the side with the most room.
        if(bFitting&&bInPlace){auto* Her=Controller->PreviewActor.Get();const FVector Feet=InPlaceAt.GetLocation();const FVector Chest=Feet+FVector(0.,0.,100.);
            FCollisionQueryParams Query(SCENE_QUERY_STAT(OKFittingCamera),false,Her);float Yaw=0.f,Room=0.f;
            for(int32 Side=0;Side<12;++Side){const float Angle=Side*30.f;const FVector Way(FMath::Sin(FMath::DegreesToRadians(Angle)),FMath::Cos(FMath::DegreesToRadians(Angle)),0.);
                FHitResult Hit;float Clear=GetWorld()->LineTraceSingleByChannel(Hit,Chest,Chest+Way*450.,ECC_WorldStatic,Query)?Hit.Distance:450.f;
                if(FittingRoom.IsValid){if(Way.X>.01)Clear=FMath::Min<float>(Clear,(FittingRoom.Max.X-Chest.X)/Way.X);else if(Way.X<-.01)Clear=FMath::Min<float>(Clear,(FittingRoom.Min.X-Chest.X)/Way.X);
                    if(Way.Y>.01)Clear=FMath::Min<float>(Clear,(FittingRoom.Max.Y-Chest.Y)/Way.Y);else if(Way.Y<-.01)Clear=FMath::Min<float>(Clear,(FittingRoom.Min.Y-Chest.Y)/Way.Y);}
                if(FittingRoom.IsValid){const FVector Middle=(FittingRoom.GetCenter()-Chest).GetSafeNormal2D();Clear*=1.f+float(FVector::DotProduct(Way,Middle));} // the wall behind her is not in the box: toward the room's middle
                if(Clear>Room){Room=Clear;Yaw=Angle;}}
            const float Distance=FMath::Clamp(Room-30.f,150.f,420.f);
            const FVector Foot=Her->GetActorLocation();Her->SetActorLocationAndRotation(Feet+FVector(0.,0.,Foot.Z),FRotator(0.,-Yaw,0.));
            Her->OrbitFocus=FVector(Feet.X,Feet.Y,Feet.Z+Her->OrbitFocus.Z);Her->OrbitYaw=Yaw;Her->OrbitPitch=0.f;Her->OrbitDistance=Distance;Her->ApplyOrbitCamera();
            UE_LOG(LogTemp,Display,TEXT("Fitting: in place at %s, camera yaw %.0f at %.0f cm"),*Feet.ToCompactString(),Yaw,Distance);}
    }
    if(!OwnController)Controller->TickPreviewPreparation();
    if(!Activated){
        if(Controller->bLoadInFlight)return;
        Controller->InteractionReturnLabel=ReturnLabel;Controller->ActivateInteraction();
        if(!Controller->InteractionWidget)return;
        Activated=true;OriginalPosition=Controller->PreviewActor->GetActorLocation();
        if(bFitting){Controller->InteractionWidget->SetVisibility(ESlateVisibility::Collapsed);if(auto* PC=Cast<AOpenKoikatsuPlayerController>(Controller->GetOwningPlayer()))PC->SetPaintPreviewActive(false);}
        else if(!MalePath.IsEmpty())Controller->LoadPartnerFromPath(MalePath);
    }
    UpdatePairPhysics();
    if(bFitting&&!Ready&&IsValid(Controller->PreviewActor)&&Controller->PreviewActor->PreparePlaybackMaterials(false)){
        auto* Her=Controller->PreviewActor.Get();
        if(!Her->SetGameSceneMode(3,false)||!Her->SetGameAnimation(TEXT("states:studio@5B2273747564696F2F616E696D652F30302E756E6974793364222C227461636869222C22222C22225D|tachi / [Studio layer 0] Base Layer.f_tachi_00_00")))UE_LOG(LogTemp,Warning,TEXT("Fitting: the standing clip did not play"));
        if(PreparingOverlay&&GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(PreparingOverlay.ToSharedRef());PreparingOverlay.Reset();
        Ready=true;ReadyAt=FPlatformTime::Seconds();Evidence=MakeShared<FJsonObject>();Evidence->SetStringField(TEXT("state"),TEXT("ready"));
    }
    const bool Both=IsValid(Controller->PreviewActor)&&IsValid(Controller->PartnerActor)&&Controller->PartnerActor->Session.IsOpen();
    if(!Ready&&Both&&Controller->PairedPlayback&&Controller->PairedPlayback->GetElapsed()>0&&Controller->PreviewActor->AreInteractionStreamsReady()&&Controller->PartnerActor->AreInteractionStreamsReady()){
        if(PreparingOverlay&&GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(PreparingOverlay.ToSharedRef());PreparingOverlay.Reset();
        Ready=true;ReadyAt=FPlatformTime::Seconds();Evidence=MakeShared<FJsonObject>();Evidence->SetStringField(TEXT("state"),TEXT("ready"));Evidence->SetBoolField(TEXT("partner_ready"),true);Evidence->SetBoolField(TEXT("same_process"),true);Evidence->SetNumberField(TEXT("process_id"),FPlatformProcess::GetCurrentProcessId());Evidence->SetStringField(TEXT("scene_class"),Controller->InteractionScene->GetClass()->GetPathName());Evidence->SetNumberField(TEXT("source_parts"),Controller->PreviewActor->Session.PartCount());Evidence->SetBoolField(TEXT("source_geometry"),true);
        UE_LOG(LogTemp,Display,TEXT("Shared interaction ready pid=%u female_parts=%d male_parts=%d"),FPlatformProcess::GetCurrentProcessId(),Controller->PreviewActor->Session.PartCount(),Controller->PartnerActor->Session.PartCount());
        Evidence->SetStringField(TEXT("card"),Controller->PreviewCardPath);Evidence->SetStringField(TEXT("partner"),MalePath);
        Evidence->SetStringField(TEXT("widget_class"),Controller->InteractionWidget->GetClass()->GetPathName());
        int64 Vertices=0;int32 Components=0;for(const auto& Part:Controller->PreviewActor->Parts){Vertices+=Part.BaseVertices.Num();if(IsValid(Part.Comp))++Components;}
        Evidence->SetNumberField(TEXT("render_vertices"),Vertices);Evidence->SetNumberField(TEXT("render_components"),Components);
        Evidence->SetNumberField(TEXT("playback_start_seconds"),Controller->PairedPlayback->GetElapsed());
        if(!ReportPath.IsEmpty())FScreenshotRequest::RequestScreenshot(FPaths::GetPath(ReportPath)/TEXT("high-interaction.png"),true,false);
    }
    if(Ready)TickOutfitSwap();
#if !UE_BUILD_SHIPPING
    if(Ready&&!TickFeatureAudit())return;
#endif
    if(Ready&&AutoReturnSeconds>0&&FPlatformTime::Seconds()-ReadyAt>=AutoReturnSeconds)Exit();
}
void AOKInteractionMode::UpdatePairPhysics(){
    for(AKKPreviewActor* Actor:{Controller->PreviewActor.Get(),Controller->PartnerActor.Get()})
        if(IsValid(Actor)&&!PairPhysicsActors.Contains(Actor)){Actor->AddPairPhysics();PairPhysicsActors.Add(Actor);}
}
void AOKInteractionMode::Exit(bool WasCancelled){
    if(Exiting||Finished)return;Exiting=true;if(Cancelled)*Cancelled=true;
    for(const TWeakObjectPtr<AKKPreviewActor>& Actor:PairPhysicsActors)if(Actor.IsValid())Actor->RemovePairPhysics();PairPhysicsActors.Reset();
    if(PreparingOverlay&&GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(PreparingOverlay.ToSharedRef());PreparingOverlay.Reset();
    if(!Evidence)Evidence=MakeShared<FJsonObject>();Evidence->SetStringField(TEXT("state"),!WasCancelled&&Activated?TEXT("returned"):TEXT("cancelled"));Evidence->SetStringField(TEXT("error"),Error);Evidence->SetBoolField(TEXT("same_process"),true);Evidence->SetNumberField(TEXT("process_id"),FPlatformProcess::GetCurrentProcessId());
    if(Controller){Evidence->SetArrayField(TEXT("actions"),Controller->ActionLog);Evidence->SetNumberField(TEXT("seconds"),Ready?FMath::RoundToDouble(FPlatformTime::Seconds()-ReadyAt):0.);Controller->ActionLog.Reset();Controller->ActionLogStart=0;
    if(Controller->PairedPlayback)Evidence->SetNumberField(TEXT("playback_end_seconds"),Controller->PairedPlayback->GetElapsed());Controller->InteractionReturned=nullptr;Controller->OnExitInteraction();if(Controller->HResult.IsValid())Evidence->SetObjectField(TEXT("h"),Controller->HResult);++Controller->LoadGeneration;++Controller->PartnerLoadGeneration;Controller->CancelPairCatalogue();Controller->CancelPairPreparation();
        if(OwnController){Controller->OnStopPair();if(Controller->PreviewActor)Controller->PreviewActor->Destroy();Controller->PreviewActor=nullptr;}
        if(auto* PC=Controller->GetOwningPlayer()){if(PreviousView)PC->SetViewTarget(PreviousView);PC->bShowMouseCursor=PreviousMouse;if(auto* O=Cast<AOpenKoikatsuPlayerController>(PC)){O->SetBodyTouchEnabled(false);O->BodyInteraction=MoveTemp(PreviousBodyInteraction);O->BodyGesture=MoveTemp(PreviousBodyGesture);O->bBodyTouchEnabled=PreviousTouch;O->SetPaintPreviewActive(PreviousPaint);}}
    }
    if(LoadingFemale){LoadingFemale->Destroy();LoadingFemale=nullptr;}
    if(SwappingFemale){SwappingFemale->Destroy();SwappingFemale=nullptr;}
    for(const auto& State:SourceActors)if(auto* Actor=State.Actor.Get()){Actor->SetActorHiddenInGame(State.Hidden);Actor->SetActorEnableCollision(State.Collision);Actor->SetActorTickEnabled(State.Tick);}
    for(const auto& State:SourceAudio)if(auto* Audio=State.Audio.Get())Audio->SetPaused(State.Paused);SourceAudio.Reset();
    SourceActors.Reset();
    if(!ReportPath.IsEmpty()){FString Json;FJsonSerializer::Serialize(Evidence.ToSharedRef(),TJsonWriterFactory<>::Create(&Json));FFileHelper::SaveStringToFile(Json,*ReportPath,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);}
    Finished=true;if(Returned)Returned(Evidence.ToSharedRef());Destroy();
}
void AOKInteractionMode::EndPlay(const EEndPlayReason::Type Reason){if(!Finished)Exit(true);Super::EndPlay(Reason);}
