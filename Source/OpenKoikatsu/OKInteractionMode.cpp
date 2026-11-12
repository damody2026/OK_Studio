#include "OKInteractionMode.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "OKCharacterController.h"
#include "OKInteractionScene.h"
#include "OKHScene.h"
#include "OKStreetSocialText.h"
#include "OKStreetRules.h"
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
#include "KKAnimationCatalog.h"
#include "Serialization/JsonSerializer.h"
#include "UnrealClient.h"
#include "Engine/GameViewportClient.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Input/SButton.h"
#include "OKReaderTalk.h"

extern TAutoConsoleVariable<int32> CVarHRefineBelly; // OKHScene.cpp
namespace {
struct FInteractionRoleLoad {FOkSession Session;FKKCharacterFile Card;FString Error,Pairs,Opened;bool Ok=false;};
}
// One set of clothes she can put on (bReady) or has taken off. The session is only what that set puts on her (wardrobe.rs).
struct FOKWardrobeItem {FOKWardrobeWant Want;FOkSession Session;FString Error,Opened;bool bOpened=false,bReady=false;};
AOKInteractionMode::AOKInteractionMode(){PrimaryActorTick.bCanEverTick=true;}
AOKInteractionMode* AOKInteractionMode::Enter(UOKCharacterController* Input,const FTransform* InPlace){
    if(!Input||!Input->GetWorld()||!Input->GetOwningPlayer()||Input->Selected.Sex!=1)return nullptr;
    for(TActorIterator<AOKInteractionMode> It(Input->GetWorld());It;++It)if(!It->Finished)return It->Controller==Input?*It:nullptr;
    auto* Mode=Input->GetWorld()->SpawnActor<AOKInteractionMode>();if(!Mode)return nullptr;
    Mode->Controller=Input;Mode->Started=FPlatformTime::Seconds();if(InPlace){Mode->bInPlace=true;Mode->InPlaceAt=*InPlace;Input->bInteractionInPlace=true;
        // In the world itself the sun's shadows reach no further than 40% of their distance while they are at it: gathering
        // the university city's casters took 0.9 ms of the render thread in the department store, the two of them and what
        // stands around them shadowed the same (2026-11-12). Given back on leaving (Exit).
        if(IConsoleVariable* V=IConsoleManager::Get().FindConsoleVariable(TEXT("r.Shadow.DistanceScale"));V&&V->GetFloat()>.4f){Mode->PreviousShadowDistance=V->GetFloat();V->Set(.4f,ECVF_SetByConsole);}}Mode->PreviousView=Input->GetOwningPlayer()->GetViewTarget();Mode->PreviousMouse=Input->GetOwningPlayer()->bShowMouseCursor;
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
// What the street's rules (ok-rules hexp.rs h_experience) answer for a lover who has done everything: every pose, kiss,
// touch and raw allowed, nothing used up today.
static TSharedPtr<FJsonObject> ReaderExperience(const UOKCharacterController* Source){
    auto X=MakeShared<FJsonObject>();
    auto Areas=MakeShared<FJsonObject>(),TouchOk=MakeShared<FJsonObject>(),UsedTo=MakeShared<FJsonObject>();
    for(const TCHAR* K:{TEXT("kiss"),TEXT("chest"),TEXT("crotch"),TEXT("anal"),TEXT("butt"),TEXT("nipple"),TEXT("oral")})Areas->SetNumberField(K,100.);
    for(const TCHAR* K:{TEXT("head"),TEXT("hand"),TEXT("thigh"),TEXT("calf"),TEXT("foot"),TEXT("lips")}){
        if(FCString::Strcmp(K,TEXT("lips"))!=0)Areas->SetNumberField(K,100.);
        auto Ok=MakeShared<FJsonObject>();Ok->SetBoolField(TEXT("touch"),true);Ok->SetBoolField(TEXT("kiss"),true);TouchOk->SetObjectField(K,Ok);}
    UsedTo->SetBoolField(TEXT("crotch"),true);UsedTo->SetBoolField(TEXT("anal"),true);
    X->SetObjectField(TEXT("areas"),Areas);X->SetObjectField(TEXT("touch_ok"),TouchOk);X->SetObjectField(TEXT("used_to"),UsedTo);
    X->SetNumberField(TEXT("level"),3);X->SetStringField(TEXT("level_name"),OKT(TEXT("hexp.level_lewd")));
    for(const TCHAR* K:{TEXT("raw_ok"),TEXT("kiss_ok"),TEXT("used"),TEXT("kissed"),TEXT("addicted")})X->SetBoolField(K,true);
    for(const TCHAR* K:{TEXT("virgin"),TEXT("anal_virgin"),TEXT("hymen_restored"),TEXT("resentful"),TEXT("anal_refused_today"),TEXT("had_enough")})X->SetBoolField(K,false);
    X->SetNumberField(TEXT("anal_chance"),1.);X->SetNumberField(TEXT("service_rounds"),6);X->SetNumberField(TEXT("climax_limit"),10);X->SetNumberField(TEXT("climax_wanted"),10);
    X->SetNumberField(TEXT("today_orgasms"),0);X->SetNumberField(TEXT("today_service"),0);X->SetNumberField(TEXT("chastity"),0.);
    X->SetNumberField(TEXT("her_condoms"),10);X->SetNumberField(TEXT("his_condoms"),10);
    X->SetNumberField(TEXT("sex_desire"),100.);X->SetNumberField(TEXT("favor"),100.);X->SetNumberField(TEXT("energy"),100.);X->SetNumberField(TEXT("satiety"),100.);
    X->SetNumberField(TEXT("personality"),Source->Selected.Personality);X->SetNumberField(TEXT("bust"),Source->Selected.Body.ShapeValueBody.IsValidIndex(4)?Source->Selected.Body.ShapeValueBody[4]:.5f);
    X->SetArrayField(TEXT("poses_played"),{});
    // The folder's other girls: the lesbian and 3P poses' second (OKHScene LoadSecond), as willing and as experienced.
    TArray<TSharedPtr<FJsonValue>> Others;
    for(int32 I=0;I<Source->Entries.Num();++I){const FKKCardListEntry& E=Source->Entries[I];
        if(E.Sex!=1||E.Path==Source->PreviewCardPath||!FPaths::FileExists(E.Path))continue;
        auto O=MakeShared<FJsonObject>();const FString Full=(E.LastName+TEXT(" ")+E.FirstName).TrimStartAndEnd();
        O->SetStringField(TEXT("name"),!Full.IsEmpty()?Full:!E.Nickname.IsEmpty()?E.Nickname:FPaths::GetBaseFilename(E.Path));
        O->SetStringField(TEXT("card"),E.Path);O->SetNumberField(TEXT("girl"),I+1);O->SetStringField(TEXT("id"),E.Path);
        O->SetBoolField(TEXT("willing"),true);O->SetNumberField(TEXT("level"),2);Others.Add(MakeShared<FJsonValueObject>(O));
        if(Others.Num()>=12)break;}
    X->SetArrayField(TEXT("others"),Others);
    return X;
}
AOKInteractionMode* AOKInteractionMode::EnterReader(UOKCharacterController* Source){
    if(!Source||Source->InteractionWidget||Source->bLoadInFlight||Source->Selected.Sex!=1)return nullptr;
    if(!IsValid(Source->PreviewActor)||!Source->PreviewActor->Session.IsOpen()){
        Source->bEnterInteractionAfterLoad=true;Source->OnLoad3D();return nullptr;
    }
    Source->ApplyPendingEditorMods();if(Source->bEditorModsDirty)return nullptr;
    auto* Shared=CreateWidget<UOKCharacterController>(Source->GetOwningPlayer());if(!Shared)return nullptr;
    Shared->bInteractionOnly=true;Shared->bIndependentCards=Source->bIndependentCards;Shared->Selected=Source->Selected;
    // Only her card, as the street's (EnterCards): the wardrobe and outfit change take Entries[0] as the card she came from
    // (the whole folder here put the first card's rig on her: "the donor's rig differs from hers").
    {const FKKCardListEntry* Hers=Source->Entries.FindByPredicate([Source](const FKKCardListEntry& E){return E.Path==Source->PreviewCardPath;});
     if(!Hers&&Source->Entries.IsValidIndex(Source->SelectedIndex))Hers=&Source->Entries[Source->SelectedIndex];
     if(Hers)Shared->Entries={*Hers};else{auto& E=Shared->Entries.AddDefaulted_GetRef();E.Path=Source->PreviewCardPath;E.FileName=FPaths::GetCleanFilename(E.Path);}Shared->SelectedIndex=0;}
   Shared->OutfitIndex=Source->OutfitIndex;
    Shared->PreviewOutfitIndex=Source->PreviewOutfitIndex;Shared->PreviewCardPath=Source->PreviewCardPath;Shared->CurrentCardDirectory=Source->CurrentCardDirectory;Shared->bModelLayout=true;
    FMemory::Memcpy(Shared->ClothesStates,Source->ClothesStates,9);FMemory::Memcpy(Shared->LoadedClothesStates,Source->LoadedClothesStates,9);
    Shared->InitializeInteractionControls();
    auto* Mode=Enter(Shared);if(!Mode)return nullptr;Mode->OwnController=true;
    Mode->LoadingFemale=Mode->GetWorld()->SpawnActor<AKKPreviewActor>();
    if(!Mode->LoadingFemale||!Source->PreviewActor->Session.CloneForInteraction(Mode->LoadingFemale->Session)){Mode->Fail(TEXT("無法複製目前角色的完整高模資源"));return nullptr;}
    FMemory::Memcpy(Mode->LoadingFemale->DisplayClothesStates,Source->PreviewActor->DisplayClothesStates,9);
    Mode->LoadingFemale->Session.WardrobePrepare();Mode->bClonedFemale=true;
    Mode->LoadingFemale->bPreserveSourceWorld=true;Mode->LoadingFemale->SetActorLocation(FVector::ZeroVector);Mode->LoadingFemale->SetActorHiddenInGame(true);Shared->bLoadInFlight=true;
    FString Error;if(!Mode->LoadingFemale->BeginSessionLoad(Error)){Mode->Fail(Error);return nullptr;}
    if(Source->PartnerMalePaths.IsValidIndex(Source->SelectedPartnerMale))Mode->MalePath=Source->PartnerMalePaths[Source->SelectedPartnerMale];
    else if(!Shared->PartnerMalePaths.IsEmpty())Mode->MalePath=Shared->PartnerMalePaths[0];
    // The same one-on-one as the street's (user 2026-11-09: the card reader's scene and UI as StreetSocial's): its H panel,
    // her as his lover who has done it all (no street relation here to gate anything), the folder's other girls for 3P.
    {auto Name=[](const FString& Last,const FString& First,const FString& Nick,const FString& Path){
         const FString Full=(Last+TEXT(" ")+First).TrimStartAndEnd();return !Full.IsEmpty()?Full:!Nick.IsEmpty()?Nick:FPaths::GetBaseFilename(Path);};
     const FString Her=Name(Source->Selected.LastName,Source->Selected.FirstName,Source->Selected.Nickname,Source->PreviewCardPath);
     FString Him=FPaths::GetBaseFilename(Mode->MalePath);
     for(const FKKCardListEntry& E:Source->Entries)if(E.Path==Mode->MalePath){Him=Name(E.LastName,E.FirstName,E.Nickname,E.Path);break;}
     // The H panel's words come from the rules' text tables (OKT); only the street opens them. A copy of the DLL, so a
     // rules build elsewhere is not blocked by this process holding it (as the street sandboxes do).
     if(!OKStreetActiveRules()||!OKStreetActiveRules()->IsOpen()){
         static TUniquePtr<FOKStreetRules> ReaderRules;
         const FString Built=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("Tools/ok-rules/target/release/ok_rules.dll"));
         const FString Copy=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("CardReader/rules")/FString::Printf(TEXT("ok_rules_%u.dll"),FPlatformProcess::GetCurrentProcessId()));
         if(FPaths::FileExists(Built)&&IFileManager::Get().Copy(*Copy,*Built)==COPY_OK)FPlatformMisc::SetEnvironmentVar(TEXT("OK_RULES_DLL"),*Copy);
         ReaderRules=MakeUnique<FOKStreetRules>();FString RulesError;
         if(ReaderRules->Open(RulesError))OKStreetSetActiveRules(ReaderRules.Get());
         else{UE_LOG(LogTemp,Warning,TEXT("Card reader one-on-one: rules not open, the H panel shows its text ids: %s"),*RulesError);ReaderRules.Reset();}}
     // Her talk first: the names the panel shows are the street's (her name table, his name from the settings), as she says them.
     Mode->ReaderTalk=MakeShared<FOKReaderTalk>(Source->PreviewCardPath,Her,Him,Source->Selected.Personality);
     Mode->BeginHScene(Mode->ReaderTalk->HerName(),TEXT("lover"),ReaderExperience(Source),Mode->ReaderTalk->HisName());}
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
        Job->Ok=Job->Ok&&Job->Session.Open(Root,Source,Outfit,Job->Error,FOkSession::AllClothesStates);
        const double T2=FPlatformTime::Seconds();double T3=T2,T35=T2,T4=T2;
        // Her materials first, every texture in parallel (the precache below then finds them prepared): one at a time,
        // March 7th's took 10 s here (Encore 1 s), the player looking at the loading screen.
        if(Job->Ok&&!*Token){Job->Session.WardrobePrepare();Job->Session.ApplyBodyPhysics(Job->Card.Body.BustSoftness,Job->Card.Body.BustWeight);if(CVarHRefineBelly.GetValueOnAnyThread())Job->Session.RefineBelly();
         // The shaped baselines her entry's static frame would make first (168 ms in that frame, 2026-11-12).
         Job->Session.PrepareShapedBaselines();T3=FPlatformTime::Seconds();
         FString MaterialError;if(!Job->Session.PrepareRuntimeMaterials(MaterialError,true))UE_LOG(LogTemp,Warning,TEXT("Interaction female materials: %s"),*MaterialError);T35=FPlatformTime::Seconds();
         AKKPreviewActor::PrecacheSessionTextures(Job->Session,true);T4=FPlatformTime::Seconds();
         // The touch reactions' shared data, parsed here rather than in the frame her scene comes up.
         FString BodyError;if(!FOKBodyInteraction::WarmShared(BodyError)){UE_LOG(LogTemp,Warning,TEXT("Interaction body data: %s"),*BodyError);}
         // And her reaction solver, which her entry made in its frame (89 ms, 2026-11-12).
         else if(!FOKBodyInteraction::PrepareAhead(Job->Session,BodyError)){UE_LOG(LogTemp,Warning,TEXT("Interaction body reaction: %s"),*BodyError);}
         // Her ahegao's eye set (OKHScene.cpp), read in her scene's first frame before (72 ms).
         {extern void OKHScenePrepareFace();OKHScenePrepareFace();}
         // Her pair list too, as the card reader's own load does (RefreshPairs read it from the session on the game thread).
         Job->Pairs=Job->Session.NativeAnimationPairs();}
        UE_LOG(LogTemp,Display,TEXT("Interaction female load %s: card %.0f ms, session %.0f ms, body physics %.0f ms, materials %.0f ms, textures %.0f ms"),*FPaths::GetCleanFilename(Path),(T1-T0)*1000.,(T2-T1)*1000.,(T3-T2)*1000.,(T35-T3)*1000.,(T4-T35)*1000.);
        AsyncTask(ENamedThreads::GameThread,[Weak,Job,Token,Path,Outfit](){
            if(*Token||!Weak.IsValid())return;auto* Mode=Weak.Get();auto* C=Mode->Controller.Get();
            if(!Job->Ok){Mode->Fail(Job->Error.IsEmpty()?TEXT("女角高模載入失敗"):Job->Error);return;}
            C->Selected=MoveTemp(Job->Card);C->Entries.Reset();auto& E=C->Entries.AddDefaulted_GetRef();E.Path=Path;E.FileName=FPaths::GetCleanFilename(Path);C->SelectedIndex=0;C->OutfitIndex=Outfit;C->PreviewOutfitIndex=Outfit;C->PreviewCardPath=Path;C->bModelLayout=true;
            if(!Job->Pairs.IsEmpty()){C->PendingLoadPairJson=MoveTemp(Job->Pairs);C->PendingLoadPairGeneration=C->LoadGeneration;}
            Mode->LoadingFemale=Mode->GetWorld()->SpawnActor<AKKPreviewActor>();if(!Mode->LoadingFemale){Mode->Fail(TEXT("無法建立高模角色"));return;}Mode->LoadingFemale->bPreserveSourceWorld=true;if(Mode->bInPlace)Mode->LoadingFemale->SetActorTransform(FTransform(Mode->InPlaceAt.GetRotation(),Mode->InPlaceAt.GetLocation()));else Mode->LoadingFemale->SetActorLocation(FVector::ZeroVector);Mode->LoadingFemale->SetActorHiddenInGame(true);Mode->LoadingFemale->Session=MoveTemp(Job->Session);Mode->LoadingFemale->PrepareWornBodyMasks();if(Mode->Controller)Mode->Controller->PrepareEditorModsJson();UKKAnimationCatalog::PreloadDefaultCatalog();
            FString Error;if(!Mode->LoadingFemale->BeginSessionLoad(Error)){Mode->Fail(Error);return;}
        });
    });
}
bool AOKInteractionMode::ChangeOutfit(int32 Outfit,const FString& Coordinate,bool bWithAccessories){
    if(Outfit<0||(Controller&&Controller->Selected.Outfits.Num()>0&&Outfit>=Controller->Selected.Outfits.Num()))return false;
    if(!Coordinate.IsEmpty()&&!FPaths::FileExists(Coordinate))return false;
    return StartSwap(Outfit,Coordinate,bWithAccessories);
}
FString AOKInteractionMode::OpenedRoot() const{
    return UKKCardWorkspace::PortableSourcePath(OpenedFemaleCard()).IsEmpty()&&UKKGameRoot::Get()?UKKGameRoot::Get()->Root:FString();
}
FString AOKInteractionMode::OpenedFemaleCard() const{return !OpenedCard.IsEmpty()?OpenedCard:Controller&&Controller->Entries.IsValidIndex(0)?Controller->Entries[0].Path:FString();}
bool AOKInteractionMode::ClothesTransition(int32 Kind,uint8 Out[9],FString& Why) const{
    if(!Controller)return false;
    return FOkSession::ClothingTransition(OpenedRoot(),OpenedFemaleCard(),Controller->OutfitIndex,Controller->ClothesStates,Kind,Out,Why);
}
// What she wears next, opened and cut down off the game thread (wardrobe.rs). An item back from her (she took it off) only
// needs its materials again.
static void OKOpenWardrobeItem(FOKWardrobeItem& Item,const FString& GameRoot,const TSharedPtr<FThreadSafeBool,ESPMode::ThreadSafe>& Token,bool bNow){
    const FOKWardrobeWant& Want=Item.Want;const double T0=FPlatformTime::Seconds();double T1=T0,T2=T0;
    if(!Item.Session.IsOpen()){
        FString Path=Want.Card;
        if(!Want.Coordinate.IsEmpty()){
            // Her card with the coordinate card written into this outfit, made once per card, coordinate and outfit.
            const FString Dir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("StreetSocial/HOutfits"));IFileManager::Get().MakeDirectory(*Dir,true);
            const FString Clothes=Dir/(FPaths::GetBaseFilename(Want.Coordinate)+TEXT(".okclothes"));
            // _w2: made again since a coordinate's plugin data saved under another outfit index is worn (okclothes.rs).
            const FString Worn=Dir/FString::Printf(TEXT("%s__%s_%d%s_w2.png"),*FPaths::GetBaseFilename(Want.Card),*FPaths::GetBaseFilename(Want.Coordinate),Want.Outfit,Want.bAccessories?TEXT("_acc"):TEXT(""));
            const FDateTime Made=IFileManager::Get().GetTimeStamp(*Worn);
            if(Made==FDateTime::MinValue()||Made<IFileManager::Get().GetTimeStamp(*Want.Card)||Made<IFileManager::Get().GetTimeStamp(*Want.Coordinate)){
                // Worn on her card as the game's card (its OK chunks, ok*, dropped) and opened from the game: an OK card
                // wearing new clothes would be made again (oklib::remake_ok_card, a minute, and only with every zipmod
                // its outfits name installed), too long to wait for in the scene.
                FString Summary;TArray<uint8> Bytes,Plain;const FString PlainCard=Dir/(FPaths::GetBaseFilename(Want.Card)+TEXT("__game.png"));
                bool Stripped=FFileHelper::LoadFileToArray(Bytes,*Want.Card)&&Bytes.Num()>8&&FMemory::Memcmp(Bytes.GetData(),"\x89PNG\r\n\x1a\n",8)==0;
                if(Stripped){Plain.Append(Bytes.GetData(),8);int64 Pos=8;Stripped=false;
                    while(Pos+12<=Bytes.Num()){const uint32 Len=(uint32(Bytes[Pos])<<24)|(uint32(Bytes[Pos+1])<<16)|(uint32(Bytes[Pos+2])<<8)|uint32(Bytes[Pos+3]);const int64 End=Pos+12+int64(Len);
                        if(End>Bytes.Num())break;const uint8* Type=&Bytes[Pos+4];
                        if(FMemory::Memcmp(Type,"IEND",4)==0){Plain.Append(&Bytes[Pos],Bytes.Num()-Pos);Stripped=true;break;}
                        if(!(Type[0]=='o'&&Type[1]=='k'))Plain.Append(&Bytes[Pos],End-Pos);Pos=End;}}
                if(!Stripped||!FFileHelper::SaveArrayToFile(Plain,*PlainCard))Item.Error=TEXT("無法讀取她的角色卡：")+Want.Card;
                else if(!FOkSession::ClothesImport(Want.Coordinate,Clothes,Summary)){Item.Error=TEXT("服裝卡讀取失敗：")+Summary;}
                else if(!(Want.bAccessories?FOkSession::ClothesWear(PlainCard,Clothes,Want.Outfit,Worn,Summary):FOkSession::ClothesWearClothesOnly(PlainCard,Clothes,Want.Outfit,Worn,Summary))){Item.Error=TEXT("穿上服裝卡失敗：")+Summary;}
                UE_LOG(LogTemp,Display,TEXT("H scene outfit: coordinate %s worn as outfit %d -> %s: %s"),*FPaths::GetCleanFilename(Want.Coordinate),Want.Outfit,*Worn,*Summary);
            }
            if(!Item.Error.IsEmpty())return;
            Path=Worn;
        }
        T1=FPlatformTime::Seconds();
        const FString Portable=UKKCardWorkspace::PortableSourcePath(Path);
        if(Portable.IsEmpty()&&GameRoot.IsEmpty()){Item.Error=TEXT("沒有設定遊戲目錄，不能開啟服裝卡的衣服");return;}
        if(!Item.Session.Open(Portable.IsEmpty()?GameRoot:FString(),Portable.IsEmpty()?Path:Portable,Want.Outfit,Item.Error,FOkSession::AllClothesStates))return;
        Item.Session.WardrobeStrip();Item.Opened=Path;T2=FPlatformTime::Seconds();
    }
    if(*Token)return;
    FString MaterialError;if(!Item.Session.PrepareRuntimeMaterials(MaterialError,bNow))UE_LOG(LogTemp,Warning,TEXT("Wardrobe materials: %s"),*MaterialError);
    AKKPreviewActor::PrecacheSessionTextures(Item.Session,true,bNow);
    UE_LOG(LogTemp,Display,TEXT("Wardrobe opened %s%s: wear %.0f ms, session %.0f ms, materials and textures %.0f ms"),*Want.Key(),bNow?TEXT(" (asked for)"):TEXT(""),(T1-T0)*1000.,(T2-T1)*1000.,(FPlatformTime::Seconds()-T2)*1000.);
    Item.bOpened=true;
}
FString FOKWardrobeWant::Key() const{return FString::Printf(TEXT("%s|%s|%d|%d"),*Card,*Coordinate,bAccessories,Outfit);}
FOKWardrobeWant AOKInteractionMode::WornWant() const{
    FOKWardrobeWant Want;Want.Card=OpenedFemaleCard();Want.Outfit=Controller->OutfitIndex;return Want;
}
// A change of clothes never replaces her model (user 2026-11-07: "any model change once one-on-one has begun is a serious
// bug"): the parts are traded on the model she has, the pair and her pose going on. What she has not worn yet is opened
// in the background; until it is there she keeps what she has on.
bool AOKInteractionMode::StartSwap(int32 Outfit,const FString& Coordinate,bool bWithAccessories){
    if(!Ready||Finished||IsChangingOutfit()||!Controller||!IsValid(Controller->PreviewActor)||!Controller->Entries.IsValidIndex(0))return false;
    FOKWardrobeWant Want;Want.Card=Controller->Entries[0].Path;Want.Coordinate=Coordinate;Want.bAccessories=!Coordinate.IsEmpty()&&bWithAccessories;Want.Outfit=Outfit;
    OutfitChanging=true;OutfitError.Reset();SwapOutfit=Outfit;SwapCoordinate=Coordinate;
    SwapKey=Want.Key();SwapWas=WornWant();
    if(!Wardrobe.Contains(SwapKey)){auto Item=MakeShared<FOKWardrobeItem,ESPMode::ThreadSafe>();Item->Want=Want;Wardrobe.Add(SwapKey,Item);}
    UE_LOG(LogTemp,Display,TEXT("H scene outfit change: %s"),*SwapKey);
    return true;
}
void AOKInteractionMode::PlanWardrobe(){
    // Each of her outfits once: its garment states are all in it.
    WardrobeQueue.Reset();const int32 Count=FMath::Clamp(Controller->Selected.Outfits.Num(),1,8);
    for(int32 Other=0;Other<Count;++Other){FOKWardrobeWant Want;Want.Card=Controller->Entries[0].Path;Want.Outfit=Other;WardrobeQueue.Add(Want);}
}
void AOKInteractionMode::PumpWardrobe(){
    if(bWardrobeBusy)return;
    TSharedPtr<FOKWardrobeItem,ESPMode::ThreadSafe> Next;bool bNow=false;
    if(OutfitChanging){const auto* Asked=Wardrobe.Find(SwapKey);if(Asked&&!(*Asked)->bReady&&(*Asked)->Error.IsEmpty()){Next=*Asked;bNow=true;}}
    else while(!Next&&!WardrobeQueue.IsEmpty()){
        const FOKWardrobeWant Want=WardrobeQueue[0];WardrobeQueue.RemoveAt(0);const FString Key=Want.Key();if(Key==WornWant().Key())continue;
        if(const auto* Found=Wardrobe.Find(Key)){if(!(*Found)->bReady&&(*Found)->Error.IsEmpty())Next=*Found;continue;}
        Next=MakeShared<FOKWardrobeItem,ESPMode::ThreadSafe>();Next->Want=Want;Wardrobe.Add(Key,Next);
    }
    if(!Next)return;
    bWardrobeBusy=true;const FString GameRoot=UKKGameRoot::Get()?UKKGameRoot::Get()->Root:FString();const auto Token=Cancelled;TWeakObjectPtr<AOKInteractionMode> Weak(this);
    Async(EAsyncExecution::Thread,[Weak,Next,Token,GameRoot,bNow](){
        if(!*Token)OKOpenWardrobeItem(*Next,GameRoot,Token,bNow);
        AsyncTask(ENamedThreads::GameThread,[Weak,Next](){
            if(Next->bOpened)Next->bReady=true;else if(Next->Error.IsEmpty())Next->Error=TEXT("新服裝載入失敗");
            if(auto* Mode=Weak.Get())Mode->bWardrobeBusy=false;});
    });
}
void AOKInteractionMode::TickOutfitSwap(){
    if(!bWardrobePlanned){bWardrobePlanned=true;PlanWardrobe();
        // Her clothing rules for each outfit worked out off the game thread (ok-extract keeps them): a pose's undoing of her
        // clothes asks for them, and the first ask cost 0.8 s a piece in the frame (3.9 s for the side position, 2026-11-12).
        {const FString Root=OpenedRoot(),Card=OpenedFemaleCard();const int32 Count=FMath::Clamp(Controller->Selected.Outfits.Num(),1,8),Worn=Controller->OutfitIndex;
         Async(EAsyncExecution::Thread,[Root,Card,Count,Worn](){const double T0=FPlatformTime::Seconds();
             for(int32 I=-1;I<Count;++I){const int32 Outfit=I<0?Worn:I;if(I>=0&&Outfit==Worn)continue;uint8 Zero[9]={},Out[9];FString Why;FOkSession::ClothingTransition(Root,Card,Outfit,Zero,0,Out,Why);}
             UE_LOG(LogTemp,Display,TEXT("H scene clothing rules prepared for %d outfits in %.0f ms"),Count,(FPlatformTime::Seconds()-T0)*1000.);});}
        // Brought over from the card reader, she has only the state she was opened in: her clothes again, with them all.
        if(bClonedFemale)StartSwap(Controller->OutfitIndex,FString(),false);}
    if(OutfitChanging){
        auto* Girl=Controller->PreviewActor.Get();const auto Item=Wardrobe.FindRef(SwapKey);FString Why;
        auto Failed=[&](const FString& What){OutfitChanging=false;OutfitError=What;Wardrobe.Remove(SwapKey);UE_LOG(LogTemp,Warning,TEXT("H scene outfit change failed: %s"),*What);if(Controller->HPanel)Controller->HPanel->OutfitChanged(false);};
        if(!IsValid(Girl)||!Item){Failed(TEXT("新服裝載入失敗"));}
        else if(!Item->Error.IsEmpty()){Failed(Item->Error);}
        else if(Item->bReady){
            if(!Girl->IsWardrobeStaging()&&!Girl->BeginWardrobeStage(Item->Session,Why)){Failed(Why);return;}
            const int32 Staged=Girl->ContinueWardrobeStage(Why,.004);
            if(Staged<0){Failed(Why);return;}
            if(Staged>0){
                // A frame being solved shows first: the trade below is between frames.
                if(Controller->HPanel)Controller->HPanel->ForgetClothCover();
                if(Controller->PairedPlayback)Controller->PairedPlayback->SyncAsync();
                if(!Girl->CommitWardrobeStage(Why)){Failed(Why);return;}
                // The item now holds what she took off.
                const FString Opened=Item->Opened;const FString WasKey=SwapWas.Key();
                Item->Want=SwapWas;Item->Opened=OpenedFemaleCard();Item->bReady=false;Item->bOpened=false;
                Wardrobe.Remove(SwapKey);if(WasKey!=SwapKey)Wardrobe.Add(WasKey,Item); // the same key: what came from the card reader, only its opened state
                Controller->OutfitIndex=SwapOutfit;Controller->PreviewOutfitIndex=SwapOutfit;WornCoordinate=SwapCoordinate;OpenedCard=Opened;
                // The pieces he had taken off stay off (the original keeps fileStatus.clothesState over a coordinate change).
                Girl->bAllClothesStates=true;FMemory::Memzero(Girl->DisplayClothesStates,9);Girl->SetClothingPartsHidden(Controller->ClothesStates);
                Girl->bBodyReactionPoseDirty=true; // paused, she still shows them
                OutfitChanging=false;
                WardrobeQueue.Add(SwapWas); // what she took off gets its materials back
                UE_LOG(LogTemp,Display,TEXT("H scene outfit changed: outfit %d%s%s, %d parts"),SwapOutfit,SwapCoordinate.IsEmpty()?TEXT(""):TEXT(" coordinate "),*FPaths::GetCleanFilename(SwapCoordinate),Girl->Session.PartCount());
                if(Controller->HPanel)Controller->HPanel->OutfitChanged(true);
            }
        }
    }
    PumpWardrobe();
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
        // {"limb_ik":{"feet":b,"hands":b,"feet_to_hers":b,"floor_near":cm,"hand_spread":cm,"hand_far":cm,"reread":b}}: their limbs' IK
        // while he is in her (the answer's limb_ik has them; a hand setting reads his hands again).
        const TSharedPtr<FJsonObject>* LimbIk=nullptr;if(Body->TryGetObjectField(TEXT("limb_ik"),LimbIk))Panel->SetLimbIk(*LimbIk);
        // {"tongue":{"up":cm,"pitch":deg,"length":x}}: her tongue out (ok.HScene.TongueUp / TonguePitch / TongueLength).
        const TSharedPtr<FJsonObject>* TongueSet=nullptr;if(Body->TryGetObjectField(TEXT("tongue"),TongueSet))Panel->SetTongue(*TongueSet);
        // {"mirror":{"on":b,"yaw":deg,"distance":cm}}: the 200 x 200 cm mirror round them (ok.HScene.Mirror / MirrorYaw / MirrorDistance).
        const TSharedPtr<FJsonObject>* MirrorSet=nullptr;if(Body->TryGetObjectField(TEXT("mirror"),MirrorSet))Panel->SetMirror(*MirrorSet,0);
        // {"mirror2":{...}}: the second mirror, the same way (ok.HScene.Mirror2 / Mirror2Yaw / Mirror2Distance).
        if(Body->TryGetObjectField(TEXT("mirror2"),MirrorSet))Panel->SetMirror(*MirrorSet,1);
        // {"puddles":{"on":b,"count":n,"size":cm,"shine":0..1}}: the puddles on the floor (ok.HScene.Puddles / PuddleCount / PuddleSize / PuddleShine).
        if(Body->TryGetObjectField(TEXT("puddles"),MirrorSet))Panel->SetPuddles(*MirrorSet);
        // {"skin_lit":true|false}: their skin lit by the scene or the original's toon (ok.HScene.SkinLit).
        bool SkinLit=false;if(Body->TryGetBoolField(TEXT("skin_lit"),SkinLit))if(auto* Var=IConsoleManager::Get().FindConsoleVariable(TEXT("ok.HScene.SkinLit")))Var->Set(SkinLit?1:0,ECVF_SetByConsole);
        // {"orbit":[yaw,pitch,distance]}: the camera round her hips, turned from where she faces (pose checks from the side and the front).
        const TArray<TSharedPtr<FJsonValue>>* Orbit=nullptr;if(Body->TryGetArrayField(TEXT("orbit"),Orbit)&&Orbit->Num()==3&&IsValid(Controller->PreviewActor)){auto* Girl=Controller->PreviewActor.Get();
            // "orbit_bone": round another of her bones (cf_J_FaceBase for her face) instead of her hips.
            FString OrbitBone=TEXT("j_hips");Body->TryGetStringField(TEXT("orbit_bone"),OrbitBone);
            FVector Hips=Girl->GetActorLocation();if(Girl->BodySkel){int32 Bone=Girl->BodySkel->GetBoneIndex(*OrbitBone);if(Bone==INDEX_NONE)Bone=Girl->BodySkel->GetBoneIndex(*(TEXT("cf_")+OrbitBone));if(Bone==INDEX_NONE)Bone=Girl->BodySkel->GetBoneIndex(TEXT("j_hips"));if(Bone!=INDEX_NONE)Hips=Girl->BodySkel->GetBoneTransform(Bone).GetLocation();}
            Girl->OrbitFocus=Hips;Girl->OrbitYaw=float((*Orbit)[0]->AsNumber())+Girl->GetActorRotation().Yaw;Girl->OrbitPitch=float((*Orbit)[1]->AsNumber());Girl->OrbitDistance=float((*Orbit)[2]->AsNumber());Girl->ApplyOrbitCamera();}
#if !UE_BUILD_SHIPPING
        // {"spray":true|false}: the player's water gun (A + left button) at what the camera looks at; game.log says what landed.
        bool Spray=false;if(Body->TryGetBoolField(TEXT("spray"),Spray))if(auto* PC=Cast<AOpenKoikatsuPlayerController>(Controller->GetOwningPlayer())){
            // "spray_at":[x,y,z] aims that far (cm, world) from the orbit focus, e.g. at the floor beside her.
            FVector Off=FVector::ZeroVector;const TArray<TSharedPtr<FJsonValue>>* At=nullptr;if(Body->TryGetArrayField(TEXT("spray_at"),At)&&At->Num()==3)Off=FVector((*At)[0]->AsNumber(),(*At)[1]->AsNumber(),(*At)[2]->AsNumber());
            if(Spray&&Controller->PreviewActor)PC->ScriptedPaintAim=Controller->PreviewActor->OrbitFocus+Off;else PC->ScriptedPaintAim.Reset();
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
    // {"save_masks":"<folder>"}: her body's mask for each state of her top (on, half, off) as PNG files there.
    FString MaskDir;if(View.IsValid()&&Body.IsValid()&&Body->TryGetStringField(TEXT("save_masks"),MaskDir)&&!MaskDir.IsEmpty()&&IsValid(Controller->PreviewActor)){
        TArray<TSharedPtr<FJsonValue>> L;for(int32 TopState:{0,1,3}){TArray<uint8> Png;
            if(Controller->PreviewActor->Session.WardrobeBodyMask(TopState,Png)&&FFileHelper::SaveArrayToFile(Png,*(MaskDir/FString::Printf(TEXT("body_mask_top%d.png"),TopState))))L.Add(MakeShared<FJsonValueNumber>(TopState));}
        View->SetArrayField(TEXT("saved_masks"),L);}
    // {"parts":true}: every mesh component on her (role, class, shown), to see what draws.
    bool PartsDump=false;if(View.IsValid()&&Body.IsValid()&&Body->TryGetBoolField(TEXT("parts"),PartsDump)&&PartsDump&&IsValid(Controller->PreviewActor)){
        TArray<TSharedPtr<FJsonValue>> L;TInlineComponentArray<UMeshComponent*> Components;Controller->PreviewActor->GetComponents(Components);
        for(UMeshComponent* C:Components){int32 Index=INDEX_NONE;for(const FName& Tag:C->ComponentTags)if(Tag.ToString().StartsWith(TEXT("KKSessionPart_")))Index=FCString::Atoi(*Tag.ToString().Mid(14));
            FString PartRole;OkMeshView V{};if(Index!=INDEX_NONE&&Controller->PreviewActor->Session.PartAt(Index,V)&&V.role)PartRole=UTF8_TO_TCHAR(V.role);
            // Each slot's material: its name, d for a dynamic instance, st when it has the iris tiling (_MainTex_ST), rows when gaze rows.
            FString Mats;for(int32 S=0;S<C->GetNumMaterials();++S)if(UMaterialInterface* M=C->GetMaterial(S)){FLinearColor P;
                Mats+=FString::Printf(TEXT(" %s%s%s%s"),*(M->GetName()+(Cast<UMaterialInstance>(M)&&Cast<UMaterialInstance>(M)->Parent?TEXT("<")+Cast<UMaterialInstance>(M)->Parent->GetName():FString())),M->IsA<UMaterialInstanceDynamic>()?TEXT(":d"):TEXT(""),M->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("_MainTex_ST")),P)?TEXT(":st"):TEXT(""),M->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("KKEyeUV0Row0")),P)?TEXT(":rows"):TEXT(""));
                // Its main texture and colour (a piece drawn black: user 2026-11-09, her half-off top).
                UTexture* Tex=nullptr;if(M->GetTextureParameterValue(FHashedMaterialParameterInfo(TEXT("_MainTex")),Tex)&&Tex)Mats+=FString::Printf(TEXT("[tex=%s %dx%d]"),*Tex->GetName(),int32(Tex->GetSurfaceWidth()),int32(Tex->GetSurfaceHeight()));
                if(M->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("_Color")),P))Mats+=FString::Printf(TEXT("[col=%.2f,%.2f,%.2f]"),P.R,P.G,P.B);}
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
float OKHVoiceRms(const FKKSpeechPcm& Pcm);float OKHCryRms(); // OKHScene.cpp
bool AOKInteractionMode::HSceneSpeak(const FString& Path){
    if(!CVarHTtsLines.GetValueOnGameThread())return false;
    if(!Controller||!IsValid(Controller->PreviewActor))return false;auto* Her=Controller->PreviewActor.Get();
    if(Controller->HPanel&&Controller->HPanel->LineIsStale())return false; // said to what happened before (UOKHScenePanel::ShowLine)
    // As loud as her cries (OKHCryRms): the TTS came out much quieter (user 2026-11-09). Its samples scaled up, the
    // loudest kept below full scale.
    Her->StopHBreath();FString Why;bool Ok=false;
    {TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe> Pcm;
     if(KKSpeech::DecodeOgg(Path,Pcm,Why)&&Pcm){const float Rms=OKHVoiceRms(*Pcm);int32 Peak=1;for(const int16 S:Pcm->Samples)Peak=FMath::Max(Peak,FMath::Abs(int32(S)));
        const float Gain=Rms>0.f?FMath::Clamp(FMath::Min(OKHCryRms()/Rms,32000.f/Peak*1.5f),1.f,8.f):1.f;
        if(Gain>1.01f){auto Loud=MakeShared<FKKSpeechPcm,ESPMode::ThreadSafe>(*Pcm);for(int16& S:Loud->Samples){const float V=S*Gain;S=int16(FMath::Clamp(V>29000.f?29000.f+(V-29000.f)*.15f:V<-29000.f?-29000.f+(V+29000.f)*.15f:V,-32767.f,32767.f));}Pcm=Loud;}
        UE_LOG(LogTemp,Display,TEXT("H scene: her line loudness %.3f -> x%.2f (her cries %.3f)"),Rms,Gain,OKHCryRms());
        Ok=Her->PlaySpeechPcm(Pcm,1.f,Why);}}
    if(!Ok)UE_LOG(LogTemp,Warning,TEXT("H scene: her line did not play: %s"),*Why);
    if(Ok)UE_LOG(LogTemp,Display,TEXT("H scene: her line spoken on her (%s)"),*FPaths::GetCleanFilename(Path));
    if(Ok&&Controller->HPanel)Controller->HPanel->SpokeLine();
    return Ok;
}
void AOKInteractionMode::HSceneReplyPending(bool bPending){if(Controller&&Controller->HPanel)Controller->HPanel->SetReplyPending(bPending);}
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
    if(ReaderTalk&&Ready)ReaderTalk->Tick(*this);
    if(auto* PC=Controller->GetOwningPlayer())if(PC->WasInputKeyJustPressed(EKeys::Escape)){Exit(!Ready);return;}
    // Space pauses or resumes the two of them (user, 2026-11-02: to take pictures), not while typing to her.
    if(auto* PC=Controller->GetOwningPlayer())if(Controller->HPanel&&Controller->PairedPlayback&&PC->WasInputKeyJustPressed(EKeys::SpaceBar)){
        const TSharedPtr<SWidget> Focus=FSlateApplication::IsInitialized()?FSlateApplication::Get().GetKeyboardFocusedWidget():nullptr;
        if(!Focus||!Focus->GetType().ToString().Contains(TEXT("EditableText")))SetHPaused(!Controller->PairedPlayback->IsPaused());}
    if(FPlatformTime::Seconds()-Started>180&&!Ready&&(!Activated||ReturnLabel==TEXT("返回多人街區"))){Fail(TEXT("一對一互動準備逾時"));return;}
    if(LoadingFemale){TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_HerLoaded);FString Why;
        if(!LoadingFemale->ContinueSessionLoad(Why)){Fail(Why);return;}
        // Her irises without highlights read back and painted while she loads (her H panel may ask for them at once).
        LoadingFemale->PrepareEyeDull();
        if(!LoadingFemale->IsSessionLoadComplete())return;
        bool FullOff=true;for(uint8 State:Controller->ClothesStates)FullOff&=State==3;
        {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_HerClothes);LoadingFemale->bAllClothesStates=!bClonedFemale;LoadingFemale->SetClothingPartsHidden(Controller->ClothesStates);
        if(FullOff)LoadingFemale->SetClothingHidden(true);}
        {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_HerMaterials);if(!LoadingFemale->BeginProgressiveMaterials())return;}
        Controller->PreviewActor=LoadingFemale;LoadingFemale=nullptr;Controller->PreviewActor->SetActorTickEnabled(false);Controller->bLoadInFlight=false;
        // Only when they differ from what she was opened with (as ActivateInteraction): the same again was 220 ms of the frame.
        {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_HerShapes);auto* Her=Controller->PreviewActor.Get();
         if(Her->bShapeDirty||Her->Session.ShapeBody()!=Controller->Selected.Body.ShapeValueBody||Her->Session.ShapeFace()!=Controller->Selected.Face.ShapeValueFace)Her->ApplyShapes(Controller->Selected.Face.ShapeValueFace,Controller->Selected.Body.ShapeValueBody);}
        {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_HerView);Controller->PreviewActor->SetupStudioView(true);Controller->PreviewActor->SetActorHiddenInGame(false);}
        {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_RefreshPairs);Controller->RefreshPairs();}
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
        // The one-on-one in place as well: right where she stood, facing as she did (he follows her, RefreshPairs). At the
        // origin it was in the sea off the university city (Jeanne Alter in the bookstore, 2026-11-12); the street's origin
        // being its square had hidden it.
        else if(bInPlace){auto* Her=Controller->PreviewActor.Get();const FVector Feet=InPlaceAt.GetLocation();const FVector Foot=Her->GetActorLocation();
            Her->SetActorLocationAndRotation(Feet+FVector(0.,0.,Foot.Z),FRotator(0.,InPlaceAt.Rotator().Yaw,0.));
            Her->OrbitFocus=FVector(Feet.X,Feet.Y,Feet.Z+Her->OrbitFocus.Z);Her->OrbitYaw=InPlaceAt.Rotator().Yaw;Her->ApplyOrbitCamera();
            UE_LOG(LogTemp,Display,TEXT("One-on-one: in place at %s yaw %.0f"),*Feet.ToCompactString(),InPlaceAt.Rotator().Yaw);}
    }
    {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_PreviewPreparation);if(!OwnController)Controller->TickPreviewPreparation();}
    if(!Activated){
        if(Controller->bLoadInFlight)return;
        {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_Activate);Controller->InteractionReturnLabel=ReturnLabel;Controller->ActivateInteraction();}
        if(!Controller->InteractionWidget)return;
        Activated=true;OriginalPosition=Controller->PreviewActor->GetActorLocation();
        if(bFitting){Controller->InteractionWidget->SetVisibility(ESlateVisibility::Collapsed);if(auto* PC=Cast<AOpenKoikatsuPlayerController>(Controller->GetOwningPlayer()))PC->SetPaintPreviewActive(false);}
        else if(!MalePath.IsEmpty()){TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_LoadPartner);Controller->LoadPartnerFromPath(MalePath);}
    }
    {TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_PairPhysics);UpdatePairPhysics();}
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
    if(Ready){TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_OutfitSwap);TickOutfitSwap();}
#if !UE_BUILD_SHIPPING
    if(Ready){TRACE_CPUPROFILER_EVENT_SCOPE(OK_IM_FeatureAudit);if(!TickFeatureAudit())return;}
#endif
    if(Ready&&AutoReturnSeconds>0&&FPlatformTime::Seconds()-ReadyAt>=AutoReturnSeconds)Exit();
}
void AOKInteractionMode::UpdatePairPhysics(){
    for(AKKPreviewActor* Actor:{Controller->PreviewActor.Get(),Controller->PartnerActor.Get()})
        if(IsValid(Actor)&&!PairPhysicsActors.Contains(Actor)){Actor->AddPairPhysics();PairPhysicsActors.Add(Actor);}
}
void AOKInteractionMode::Exit(bool WasCancelled){
    if(Exiting||Finished)return;Exiting=true;if(Cancelled)*Cancelled=true;
    if(ReaderTalk){ReaderTalk->End();ReaderTalk.Reset();}
    if(PreviousShadowDistance>=0.f){if(IConsoleVariable* V=IConsoleManager::Get().FindConsoleVariable(TEXT("r.Shadow.DistanceScale")))V->Set(PreviousShadowDistance,ECVF_SetByConsole);PreviousShadowDistance=-1.f;}
    for(const TWeakObjectPtr<AKKPreviewActor>& Actor:PairPhysicsActors)if(Actor.IsValid())Actor->RemovePairPhysics();PairPhysicsActors.Reset();
    if(PreparingOverlay&&GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(PreparingOverlay.ToSharedRef());PreparingOverlay.Reset();
    if(!Evidence)Evidence=MakeShared<FJsonObject>();Evidence->SetStringField(TEXT("state"),!WasCancelled&&Activated?TEXT("returned"):TEXT("cancelled"));Evidence->SetStringField(TEXT("error"),Error);Evidence->SetBoolField(TEXT("same_process"),true);Evidence->SetNumberField(TEXT("process_id"),FPlatformProcess::GetCurrentProcessId());
    if(Controller){Evidence->SetArrayField(TEXT("actions"),Controller->ActionLog);Evidence->SetNumberField(TEXT("seconds"),Ready?FMath::RoundToDouble(FPlatformTime::Seconds()-ReadyAt):0.);Controller->ActionLog.Reset();Controller->ActionLogStart=0;
    if(Controller->PairedPlayback)Evidence->SetNumberField(TEXT("playback_end_seconds"),Controller->PairedPlayback->GetElapsed());Controller->InteractionReturned=nullptr;Controller->OnExitInteraction();if(Controller->HResult.IsValid())Evidence->SetObjectField(TEXT("h"),Controller->HResult);++Controller->LoadGeneration;++Controller->PartnerLoadGeneration;Controller->CancelPairCatalogue();Controller->CancelPairPreparation();
        if(OwnController){Controller->OnStopPair();if(Controller->PreviewActor)Controller->PreviewActor->Destroy();Controller->PreviewActor=nullptr;}
        if(auto* PC=Controller->GetOwningPlayer()){if(PreviousView)PC->SetViewTarget(PreviousView);PC->bShowMouseCursor=PreviousMouse;if(auto* O=Cast<AOpenKoikatsuPlayerController>(PC)){O->SetBodyTouchEnabled(false);O->BodyInteraction=MoveTemp(PreviousBodyInteraction);O->BodyGesture=MoveTemp(PreviousBodyGesture);O->bBodyTouchEnabled=PreviousTouch;O->SetPaintPreviewActive(PreviousPaint);}}
    }
    if(LoadingFemale){LoadingFemale->Destroy();LoadingFemale=nullptr;}
    if(Controller&&IsValid(Controller->PreviewActor))Controller->PreviewActor->CancelWardrobeStage();
    WardrobeQueue.Reset();Wardrobe.Reset();OutfitChanging=false;
    for(const auto& State:SourceActors)if(auto* Actor=State.Actor.Get()){Actor->SetActorHiddenInGame(State.Hidden);Actor->SetActorEnableCollision(State.Collision);Actor->SetActorTickEnabled(State.Tick);}
    for(const auto& State:SourceAudio)if(auto* Audio=State.Audio.Get())Audio->SetPaused(State.Paused);SourceAudio.Reset();
    SourceActors.Reset();
    if(!ReportPath.IsEmpty()){FString Json;FJsonSerializer::Serialize(Evidence.ToSharedRef(),TJsonWriterFactory<>::Create(&Json));FFileHelper::SaveStringToFile(Json,*ReportPath,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);}
    Finished=true;if(Returned)Returned(Evidence.ToSharedRef());Destroy();
}
void AOKInteractionMode::EndPlay(const EEndPlayReason::Type Reason){if(!Finished)Exit(true);Super::EndPlay(Reason);}
