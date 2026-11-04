#include "OKHScene.h"
#include "Camera/CameraActor.h"
#include "Camera/PlayerCameraManager.h"
#include "Camera/CameraComponent.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Components/ButtonSlot.h"
#include "Components/CheckBox.h"
#include "HAL/IConsoleManager.h"
#include "OKCharacterController.h"
#include "OKInteractionMode.h"
#include "KKGameRoot.h"
#include "HAL/FileManager.h"
#include "OKArousalDrops.h"
#include "Misc/App.h"
#include "OKStreetSocialText.h"
#include "OKMotionLabelZh.h"
#include "KKPreviewActor.h"
#include "KKPairedPlayback.h"
#include "KKRustExtract.h"
#include "ok_extract.h"
#include "KKSpeech.h"
#include "OKSceneActor.h"
#include "Kismet/GameplayStatics.h"
#include "EngineUtils.h"
#include "Engine/Light.h"
#include "Components/LightComponentBase.h"
#include "Engine/SkyLight.h"
#include "Engine/PostProcessVolume.h"
#include "GameFramework/Info.h"
#include "AudioDevice.h"
#include "Engine/StaticMeshActor.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/Material.h"
#include "UObject/SavePackage.h"
#include "UObject/Package.h"
#include "Misc/PackageName.h"
#include "Engine/StaticMesh.h"
#include "Components/StaticMeshComponent.h"
#include "Components/PoseableMeshComponent.h"
#include "Async/Async.h"
#include "Blueprint/WidgetTree.h"
#include "Rendering/DrawElements.h"
#include "Styling/CoreStyle.h"
#include "Components/ScaleBox.h"
#include "Components/SkinnedMeshComponent.h"
#include "Framework/Application/SlateApplication.h"
#include "Components/SizeBox.h"
#include "Components/Border.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/Spacer.h"
#include "Components/ComboBoxString.h"
#include "OKComboBox.h"
#include "OKHGShading.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/ProgressBar.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/Slider.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/WrapBox.h"
#include "Components/EditableTextBox.h"
#include "Components/Image.h"
#include "ImageUtils.h"
#include "KKCardWorkspace.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "OKPaintSprayer.h"
#include "Components/InvalidationBox.h"
#include "ok_extract.h"

void UOKHSceneButton::HandleClick(){if(Owner)Owner->Click(Kind);}

// The authored metadata of every pose, by "AnimationInfo_XX:id" (ok-hposes from the original h/list).
static const TMap<FString,TSharedPtr<FJsonObject>>& HPoseMeta(){
    static TMap<FString,TSharedPtr<FJsonObject>> Meta;static bool Loaded=false;
    if(Loaded)return Meta;Loaded=true;
    FString Json;TArray<TSharedPtr<FJsonValue>> Rows;
    if(FFileHelper::LoadFileToString(Json,*(FPaths::ProjectContentDir()/TEXT("IndependentResources/StreetSocialData/h_poses.json")))&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Rows))
        for(const auto& V:Rows)if(const auto O=V->AsObject())Meta.Add(FString::Printf(TEXT("%s:%d"),*O->GetStringField(TEXT("category")),int32(O->GetNumberField(TEXT("id")))),O);
    UE_LOG(LogTemp,Display,TEXT("H scene: %d authored poses"),Meta.Num());
    return Meta;
}

// A state without the anal prefix: the flow is the same for both.
static FString HBase(const FString& State){return State.StartsWith(TEXT("A_"))?State.Mid(2):State;}
static bool HIsLoop(const FString& Base){return Base==TEXT("WLoop")||Base==TEXT("SLoop");}

int32 UOKHScenePanel::Level() const{return Gallery&&Gallery->HExperience.IsValid()?int32(Gallery->HExperience->GetNumberField(TEXT("level"))):0;}
FString UOKHScenePanel::Current() const{if(Mode==0)return SoloState;return Gallery&&Gallery->PairedPlayback?Gallery->PairedPlayback->GetState():FString();}
bool UOKHScenePanel::Has(const FString& State) const{if(Mode==0)return SoloKeys.Contains(State);return Gallery&&Gallery->PairStateCombo&&Gallery->PairStateCombo->FindOptionIndex(State)>0;}
float UOKHScenePanel::AreaExperience(int32 Area) const{
    static const TCHAR* Keys[]={TEXT("kiss"),TEXT("chest"),TEXT("crotch"),TEXT("anal"),TEXT("butt"),TEXT("nipple"),TEXT("head"),TEXT("hand"),TEXT("thigh"),TEXT("calf"),TEXT("foot")};
    const TSharedPtr<FJsonObject>* Areas=nullptr;double V=0;
    // Her vagina and anus: what she is used to (their development counts only climaxes with him in her).
    if(Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetObjectField(Area==2||Area==3?TEXT("used_to"):TEXT("areas"),Areas)&&Area>=0&&Area<11)(*Areas)->TryGetNumberField(Keys[Area],V);
    return float(V);
}
// Nothing ever done to her there: undeveloped (development counts only climaxes, hexp.rs) and, for her vagina and anus,
// never had him in it either (she is not a virgin there), so a girl who has had sex is not touched there "for the first time".
bool UOKHScenePanel::NeverHad(int32 Area) const{
    if(AreaExperience(Area)>=.05f)return false;
    const TCHAR* Virgin=Area==2?TEXT("virgin"):Area==3?TEXT("anal_virgin"):nullptr;bool V=true;
    if(Virgin&&Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetBoolField(Virgin,V)&&!V)return false;
    return true;
}
// The private room is a bare floor: a pose fits it when the original lets it play on the floor, a bed or standing
// (H point categories 0, 1, 9; 1008, which only マングリ正常位 has, is played on the floor too). Chair, desk, wall,
// pool, fence, net and the rest need their prop and floated there (he sat on air in 椅子対面, she lay in mid-air in 机寝位).
static TAutoConsoleVariable<int32> CVarHAllPoses(TEXT("ok.HScene.AllPoses"),0,TEXT("1: list every authored pose in the private room, props or not (testing prop placement)"));
// The room's prop for a pose: 0 none (it plays on the floor, a bed or standing: categories 0, 1, 9, 1008), 1 a seat (chair
// 2-5, bench 12, prank chair 1003, straddled chair 1200, sofa 1201), 2 a table (desk 6-7, box 1009, table tennis 1301,
// crouch at a desk 1305), 3 a wall (8, bookshelf 1002, fence 1006, net 1300, wall 1302, pressed 1304); -1 none fits
// (pool, banana boat, the rest): left out of the room.
static int32 HPropKind(const FString& Category,int32 Id){
    const TSharedPtr<FJsonObject>* M=HPoseMeta().Find(FString::Printf(TEXT("%s:%d"),*Category,Id));if(!M)return 0;
    const TArray<TSharedPtr<FJsonValue>>* Places=nullptr;if(!(*M)->TryGetArrayField(TEXT("categories"),Places)||Places->IsEmpty())return 0;
    int32 Kind=-1;
    for(const auto& V:*Places){const int32 C=int32(V->AsNumber());
        if(C==0||C==1||C==9||C==1008)return 0;
        const int32 K=(C>=2&&C<=5)||C==12||C==1003||C==1200||C==1201?1:(C==6||C==7||C==1009||C==1301||C==1305)?2:(C==8||C==1002||C==1006||C==1300||C==1302||C==1304)?3:-1;
        if(K>0&&Kind<0)Kind=K;}
    return Kind;
}
// Her spoken lines in H (the original's Japanese voice table rows, her climax words): off (user 2026-11-02: only her cries,
// the breathing bank). 1 brings them back.
TAutoConsoleVariable<int32> CVarHSpokenLines(TEXT("ok.HScene.SpokenLines"),0,TEXT("1: she speaks the original's lines in H (voice table, climax words); 0: only her cries"));
// Her answers by TTS, her cries held while she says them (user 2026-11-04).
TAutoConsoleVariable<int32> CVarHTtsLines(TEXT("ok.HScene.TtsLines"),1,TEXT("1: she says her answers in H by TTS, her cries wait for them; 0: they are only shown"));
static TAutoConsoleVariable<float> CVarHHerRate(TEXT("ok.HScene.HerRate"),1.f,TEXT("Her gauge rises this many times as fast"));
static TAutoConsoleVariable<float> CVarHHisRate(TEXT("ok.HScene.HisRate"),1.f,TEXT("His gauge rises this many times as fast"));
static TAutoConsoleVariable<float> CVarHTongueLength(TEXT("ok.HScene.TongueLength"),1.f,TEXT("How long her tongue comes out, 1 as the card has it"));
static TAutoConsoleVariable<int32> CVarHDrool(TEXT("ok.HScene.Drool"),1,TEXT("1: she drools (kissing, ahegao); 0 not"));
static TAutoConsoleVariable<int32> CVarHFluidTongue(TEXT("ok.HScene.FluidTongue"),0,TEXT("1: what comes out of her coats her tongue too; 0 it does not (her drool turned it white)"));
static TAutoConsoleVariable<float> CVarHPupilSize(TEXT("ok.HScene.PupilSize"),1.f,TEXT("Her pupils, times as large as they would be"));
static TAutoConsoleVariable<int32> CVarHPupilHighlight(TEXT("ok.HScene.PupilHighlight"),1,TEXT("0: no highlight in her eyes whatever her state"));
static TAutoConsoleVariable<float> CVarHPupilShake(TEXT("ok.HScene.PupilShake"),0.f,TEXT("How far her pupils tremble, percent of the iris texture; 0 they hold still"));
static TAutoConsoleVariable<float> CVarHPupilShakeRate(TEXT("ok.HScene.PupilShakeRate"),8.f,TEXT("New places her trembling pupils go to, per second"));
static TAutoConsoleVariable<float> CVarHCondomMouthFavor(TEXT("ok.HScene.CondomMouthFavor"),100.f,TEXT("Past this favor she puts the condom on him with her mouth"));
// What the player can set in the panel on the left (user 2026-11-04): console variables, kept between runs in the user's
// settings folder (the stage changes, so not under Saved). A row with no variable is a heading; 0..1 by 1 is on and off.
struct FHSetting {const TCHAR* Var;const TCHAR* Label;float Low,High,Step,Default;};
static const FHSetting HSettings[]={
    // @: not a console variable, her development in this area (UOKHScenePanel::SetDev); kept with her, not reset here.
    {nullptr,TEXT("ui.hscene.set_dev")},
    {TEXT("@kiss"),TEXT("ui.hscene.set_dev_kiss"),0.f,100.f,1.f,0.f},
    {TEXT("@chest"),TEXT("ui.hscene.set_dev_chest"),0.f,100.f,1.f,0.f},
    {TEXT("@nipple"),TEXT("ui.hscene.set_dev_nipple"),0.f,100.f,1.f,0.f},
    {TEXT("@butt"),TEXT("ui.hscene.set_dev_butt"),0.f,100.f,1.f,0.f},
    {TEXT("@crotch"),TEXT("ui.hscene.set_dev_crotch"),0.f,100.f,1.f,0.f},
    {TEXT("@anal"),TEXT("ui.hscene.set_dev_anal"),0.f,100.f,1.f,0.f},
    {TEXT("@oral"),TEXT("ui.hscene.set_dev_oral"),0.f,100.f,1.f,0.f},
    {TEXT("@head"),TEXT("ui.hscene.set_dev_head"),0.f,100.f,1.f,0.f},
    {TEXT("@hand"),TEXT("ui.hscene.set_dev_hand"),0.f,100.f,1.f,0.f},
    {TEXT("@thigh"),TEXT("ui.hscene.set_dev_thigh"),0.f,100.f,1.f,0.f},
    {TEXT("@calf"),TEXT("ui.hscene.set_dev_calf"),0.f,100.f,1.f,0.f},
    {TEXT("@foot"),TEXT("ui.hscene.set_dev_foot"),0.f,100.f,1.f,0.f},
    {nullptr,TEXT("ui.hscene.set_voice")},
    {TEXT("TtsLines"),TEXT("ui.hscene.set_tts"),0.f,1.f,1.f,1.f},
    {TEXT("SpokenLines"),TEXT("ui.hscene.set_spoken"),0.f,1.f,1.f,0.f},
    {nullptr,TEXT("ui.hscene.set_gauge")},
    {TEXT("HerRate"),TEXT("ui.hscene.set_her_rate"),.2f,5.f,.1f,1.f},
    {TEXT("HisRate"),TEXT("ui.hscene.set_his_rate"),.2f,5.f,.1f,1.f},
    {nullptr,TEXT("ui.hscene.set_ahegao")},
    {TEXT("AhegaoClimaxes"),TEXT("ui.hscene.set_ahe_climaxes"),0.f,10.f,1.f,4.f},
    {TEXT("AhegaoSpeed"),TEXT("ui.hscene.set_ahe_speed"),0.f,1.f,.01f,.66f},
    {TEXT("AhegaoGaze"),TEXT("ui.hscene.set_ahe_gaze"),0.f,2.f,.05f,1.25f},
    {TEXT("AhegaoMouthOpen"),TEXT("ui.hscene.set_ahe_mouth"),0.f,1.f,.05f,.85f},
    {TEXT("AhegaoArms"),TEXT("ui.hscene.set_ahe_arms"),0.f,1.f,1.f,1.f},
    {TEXT("Drool"),TEXT("ui.hscene.set_drool"),0.f,1.f,1.f,1.f},
    {TEXT("TongueLength"),TEXT("ui.hscene.tongue_length"),0.f,2.f,.05f,1.f},
    {nullptr,TEXT("ui.hscene.set_service")},
    {TEXT("CondomMouthFavor"),TEXT("ui.hscene.set_condom_favor"),0.f,500.f,10.f,100.f},
    {TEXT("CondomMouthSeconds"),TEXT("ui.hscene.set_condom_seconds"),2.f,20.f,1.f,6.f},
    {TEXT("SuckGrip"),TEXT("ui.hscene.set_suck_grip"),0.f,1.f,1.f,1.f},
    {nullptr,TEXT("ui.hscene.set_pupil")},
    {TEXT("PupilSize"),TEXT("ui.hscene.set_pupil_size"),.5f,2.f,.05f,1.f},
    {TEXT("PupilHighlight"),TEXT("ui.hscene.set_pupil_highlight"),0.f,1.f,1.f,1.f},
    {TEXT("PupilShake"),TEXT("ui.hscene.set_pupil_shake"),0.f,10.f,.1f,0.f},
    {TEXT("PupilShakeRate"),TEXT("ui.hscene.set_pupil_shake_rate"),1.f,30.f,1.f,8.f},
    {nullptr,TEXT("ui.hscene.set_view")},
    {TEXT("EyesCamera"),TEXT("ui.hscene.set_eyes_camera"),0.f,1.f,1.f,1.f},
    {TEXT("CameraLight"),TEXT("ui.hscene.set_camera_light"),0.f,1.f,1.f,1.f},
    {TEXT("SiruTexture"),TEXT("ui.hscene.set_siru"),0.f,1.f,1.f,0.f},
    {TEXT("Props"),TEXT("ui.hscene.set_props"),0.f,1.f,1.f,0.f},
};
static IConsoleVariable* HSettingVar(const TCHAR* Name){return IConsoleManager::Get().FindConsoleVariable(*(FString(TEXT("ok.HScene."))+Name));}
// A test run keeps its own (-OKSettingsDir, Tools/run_street_social_development.lua): the player's game reads the shared one.
static FString HSettingsFile(){FString Own;if(FParse::Value(FCommandLine::Get(),TEXT("-OKSettingsDir="),Own))return FPaths::Combine(Own,TEXT("HSettings.ini"));
    return FPaths::Combine(FPlatformProcess::UserSettingsDir(),TEXT("OpenKoikatsu"),TEXT("HSettings.ini"));}
static void HSettingSet(const TCHAR* Name,float Value){if(auto* Var=HSettingVar(Name))Var->Set(*FString::Printf(TEXT("%g"),Value),ECVF_SetByConsole);}
// The panel's light rows, kept with the settings.
static const TCHAR* const HLightVars[]={TEXT("LightFrom"),TEXT("LightTint"),TEXT("LightRamp")};
static void HSettingsLoad(){
    TArray<FString> Lines;FFileHelper::LoadFileToStringArray(Lines,*HSettingsFile());
    for(const FString& Line:Lines){FString Name,Value;if(Line.Split(TEXT("="),&Name,&Value)){for(const FHSetting& S:HSettings)if(S.Var&&Name==S.Var)HSettingSet(S.Var,FCString::Atof(*Value));
        for(const TCHAR* Light:HLightVars)if(Name==Light)if(auto* Var=HSettingVar(Light))Var->Set(*Value,ECVF_SetByConsole);}}
}
static void HSettingsSave(){
    FString Out;for(const FHSetting& S:HSettings)if(S.Var)if(auto* Var=HSettingVar(S.Var))Out+=FString::Printf(TEXT("%s=%g\n"),S.Var,Var->GetFloat());
    for(const TCHAR* Light:HLightVars)if(auto* Var=HSettingVar(Light))Out+=FString::Printf(TEXT("%s=%s\n"),Light,*Var->GetString());
    FFileHelper::SaveStringToFile(Out,*HSettingsFile());
}
void UOKHSettingSlider::Show(){
    const FHSetting& S=HSettings[Row];
    if(S.Var[0]==TEXT('@')){const float V=Owner?Owner->DevOf(S.Var+1):0.f;SetValue(V);if(Shown)Shown->SetText(FText::AsNumber(FMath::RoundToInt(V)));return;}
    auto* Var=HSettingVar(S.Var);if(!Var)return;const float V=Var->GetFloat();SetValue(V);
    if(Shown)Shown->SetText(FText::FromString(S.Low==0.f&&S.High==1.f&&S.Step==1.f?OKT(V>.5f?TEXT("ui.hscene.set_on"):TEXT("ui.hscene.set_off")):FString::Printf(TEXT("%g"),V)));
}
void UOKHSettingSlider::HandleValue(float NewValue){const TCHAR* Var=HSettings[Row].Var;if(Var[0]==TEXT('@')){if(Owner)Owner->SetDev(Var+1,NewValue);}else HSettingSet(Var,NewValue);Show();}
void UOKHSettingSlider::HandleDone(){HSettingsSave();}
static bool HFitsRoom(const FString& Category,int32 Id){return CVarHAllPoses.GetValueOnGameThread()||HPropKind(Category,Id)>=0;}
void UOKHScenePanel::LoadAibuPoses(){
    bAibuLoaded=true;AibuPoses.Reset();TArray<TSharedPtr<FJsonValue>> Rows;
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(FOkSession::CommonInteractionPoses()),Rows))return;
    for(const auto& V:Rows){const auto Row=V->AsObject();if(!Row||Row->GetIntegerField(TEXT("participants"))!=1||Row->GetStringField(TEXT("category"))!=TEXT("AnimationInfo_00"))continue;
        if(!HFitsRoom(TEXT("AnimationInfo_00"),Row->GetIntegerField(TEXT("id"))))continue;
        FAibuPose& Pose=AibuPoses.AddDefaulted_GetRef();Pose.Source=Row->GetStringField(TEXT("female_source"));Pose.Layer=Row->GetIntegerField(TEXT("female_layer"));Pose.Id=Row->GetIntegerField(TEXT("id"));Pose.Prop=FMath::Max(0,HPropKind(TEXT("AnimationInfo_00"),Pose.Id));
        const FString Raw=Row->GetStringField(TEXT("name"));Pose.Name=Raw.IsEmpty()?FString::Printf(TEXT("#%d"),Row->GetIntegerField(TEXT("id"))):OKMotionLabelDisplay(Raw);}
    UE_LOG(LogTemp,Display,TEXT("H scene: %d caress poses"),AibuPoses.Num());
}
void UOKHScenePanel::SelectAibu(int32 Index){
    if(!Gallery||!AibuPoses.IsValidIndex(Index)||!Gallery->PreviewActor)return;
    PendingAibu=Index;Queue.Reset();Wanted.Reset();TouchArea=INDEX_NONE;BuildList();
    const int32 Generation=++AibuGeneration;const FAibuPose Pose=AibuPoses[Index];const FString Root=FOkSession::CommonPairRoot();
    TWeakObjectPtr<UOKHScenePanel> Weak(this);
    if(Hint)Hint->SetText(FText::FromString(OKT(TEXT("ui.hscene.loading_caress")))); // a hint, not something they did (not in her memory)
    Async(EAsyncExecution::Thread,[Weak,Generation,Pose,Root](){
        TMap<FString,FString> Keys;const FString Prefix=TEXT(" / [Controller layer 0] Base Layer.");
        FOkSession::BeginAnimationPreparation();
        for(const FString& Label:FOkSession::AnimationSourceNames(Root,Pose.Source)){const int32 At=Label.Find(Prefix);if(At==INDEX_NONE)continue;
            const FString State=Label.Mid(At+Prefix.Len());if(State.Contains(TEXT(".")))continue;
            const FString Key=FOkSession::PairClipForRoot(Root,Pose.Source+TEXT("|")+Label,Pose.Layer);
            if(!Key.IsEmpty()&&FOkSession::PrepareAnimationClip(Root,Key))Keys.Add(State,Key);}
        FOkSession::EndAnimationPreparation();
        AsyncTask(ENamedThreads::GameThread,[Weak,Generation,Keys=MoveTemp(Keys)]() mutable {
            auto* UI=Weak.Get();if(!UI||UI->AibuGeneration!=Generation||!UI->Gallery||!UI->Gallery->PreviewActor)return;
            if(!Keys.Contains(TEXT("Idle"))){UI->PendingAibu=INDEX_NONE;UI->Note(OKT(TEXT("ui.hscene.pose_missing")),false);UI->BuildList();return;}
            UOKCharacterController* G=UI->Gallery;
            // Him out of the picture as in the original caress; his pose stops.
            // Only the pair playback stops: OnStopPair also destroys him, and no pose could be chosen after the caress.
            G->CancelPairPreparation();G->bPairBreathArmed=false;G->PreviewActor->StopHBreath();
            if(G->PairedPlayback){G->PairedPlayback->Stop();G->PairedPlayback->Destroy();G->PairedPlayback=nullptr;}
            if(G->PartnerActor){G->PartnerActor->StopHBreath();G->PartnerActor->SetActorHiddenInGame(true);}
            G->PreviewActor->SetActorTickEnabled(true);G->PreviewActor->SetGameSceneMode(3,false);G->SelectedGameSceneMode=3;
            UI->SoloKeys=MoveTemp(Keys);UI->ActiveAibu=UI->PendingAibu;UI->PendingAibu=INDEX_NONE;UI->ClearLine();UI->ActivePose=INDEX_NONE;UI->Mode=0;UI->SoloState.Reset();
            G->NoteAction(TEXT("pair"),UI->AibuPoses[UI->ActiveAibu].Name);
            UI->PlaySolo(TEXT("Idle"));UI->BuildList();if(UI->Hint)UI->Hint->SetText(FText::FromString(UI->AibuPoses[UI->ActiveAibu].Name)); // loaded: the hint no longer says loading
            if(UI->bAfterglow){UI->Note(OKT(TEXT("ui.hscene.event_afterglow")));if(UI->Hint)UI->Hint->SetText(FText::FromString(OKT(TEXT("ui.hscene.afterglow_hint"))));}
        });
    });
}
void UOKHScenePanel::PlaySolo(const FString& State){
    if(!Gallery||!Gallery->PreviewActor)return;const FString* Key=SoloKeys.Find(State);if(!Key)return;
    if(Gallery->PreviewActor->SetGameAnimation(*Key)){SoloState=State;SoloStarted=FPlatformTime::Seconds();Gallery->SyncGameAnimationSelection(*Key);CaressBreath();}
    else UE_LOG(LogTemp,Warning,TEXT("H scene: caress state %s did not play"),*State);
}
void UOKHScenePanel::Touch(int32 Area){
    const TSharedPtr<FJsonObject> X=Gallery?Gallery->HExperience:nullptr;
    if(Area>=6||(Area==0&&bLipsTouch)){TouchBody(Area);return;}
    if(Area==0){
        // A kiss she has not allowed yet (not his lover, never kissed) is refused (HandCtrl: voice 103).
        if(!(X.IsValid()&&X->GetBoolField(TEXT("kiss_ok")))){Note(OKT(TEXT("ui.hscene.kiss_refused")));Chain({TEXT("Front_Dislikes"),TEXT("Idle")});TouchArea=INDEX_NONE;return;}
        // Her first kiss ever (not this scene's first): she answers it as one, in her own words (TTS; user 2026-11-03:
        // a first-time line by TTS, not the original's first bank).
        const bool bFirst=!(X->HasField(TEXT("kissed"))&&X->GetBoolField(TEXT("kissed")))&&AreaSeconds[0]<=0.f;
        TouchArea=0;Chain({TEXT("K_Touch"),TEXT("K_Loop")});Note(OKT(bFirst?TEXT("ui.hscene.event_first_kiss"):TEXT("ui.hscene.event_kiss")));return;
    }
    // Her anal untouched and him not her lover: she pulls away (anal_dislikes).
    if(Area==3&&NeverHad(3)&&Gallery->HHeroineStage!=TEXT("lover")){Note(OKT(TEXT("ui.hscene.anal_touch_refused")));Chain({TEXT("Back_Dislikes"),TEXT("Idle")});TouchArea=INDEX_NONE;return;}
    static const TCHAR* Prefix[]={TEXT(""),TEXT("M_"),TEXT("A_"),TEXT("S_"),TEXT("S_"),TEXT("M_")};
    static const TCHAR* TouchEvents[]={TEXT(""),TEXT("ui.hscene.event_touch_chest"),TEXT("ui.hscene.event_touch_crotch"),TEXT("ui.hscene.event_touch_anal"),TEXT("ui.hscene.event_touch_butt"),TEXT("ui.hscene.event_touch_nipple")};
    // A place she has never been touched (HVoiceCtrl GetStateSelect gives it her first-time bank): she answers it as her
    // first time there, by TTS.
    static const TCHAR* FirstEvents[]={TEXT(""),TEXT("ui.hscene.event_first_chest"),TEXT("ui.hscene.event_first_crotch"),TEXT("ui.hscene.event_first_anal"),TEXT("ui.hscene.event_first_butt"),TEXT("ui.hscene.event_first_nipple")};
    // Kissed or licked there (bLickMode): the same caress of hers (the original's tongue item), said as his mouth.
    if(TouchArea!=Area){const bool First=NeverHad(Area)&&AreaSeconds[Area]<=0.f;
        if(bLickMode){static const TCHAR* Parts[]={TEXT(""),TEXT("chest"),TEXT("crotch"),TEXT("anal"),TEXT("butt"),TEXT("nipple")};
            Note(OKMsg(First?TEXT("ui.hscene.event_first_body"):TEXT("ui.hscene.event_body"),{{TEXT("how"),TEXT("kiss")},{TEXT("part"),OKT(*(FString(TEXT("ui.hscene.part_"))+Parts[Area]))}}));}
        else Note(OKT(First?FirstEvents[Area]:TouchEvents[Area]));}
    TouchArea=Area;Chain({FString(Prefix[Area])+TEXT("Touch"),FString(Prefix[Area])+TEXT("Idle")});
}
// Her head, hand, thigh, calf, foot (or her lips) touched or kissed: no caress clip of hers in the original, which plays
// its HitReaction there (HandCtrl reac_head / reac_arm / reac_leg): the part flinches, again every few seconds while he
// keeps at it, less the more it is developed. Whether she lets him: hexp.rs touch_ok (her relation, the place developed).
static const TCHAR* HBodyKey(int32 Area){static const TCHAR* K[]={TEXT("head"),TEXT("hand"),TEXT("thigh"),TEXT("calf"),TEXT("foot")};return Area==0?TEXT("lips"):Area>=6&&Area<11?K[Area-6]:TEXT("");}
bool UOKHScenePanel::BodyTouching() const{return TouchArea>=6||(TouchArea==0&&bLipsTouch);}
void UOKHScenePanel::TouchBody(int32 Area){
    const TCHAR* Key=HBodyKey(Area);const TCHAR* How=bLickMode?TEXT("kiss"):TEXT("touch");
    const FString Part=OKT(*(FString(TEXT("ui.hscene.part_"))+Key));
    bool Ok=true;{const TSharedPtr<FJsonObject>* T=nullptr;const TSharedPtr<FJsonObject>* One=nullptr;
     if(Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetObjectField(TEXT("touch_ok"),T)&&(*T)->TryGetObjectField(Key,One))(*One)->TryGetBoolField(How,Ok);}
    if(!Ok){Note(OKMsg(TEXT("ui.hscene.event_body_refused"),{{TEXT("how"),How},{TEXT("part"),Part}}));Chain({TEXT("Front_Dislikes"),TEXT("Idle")});TouchArea=INDEX_NONE;bLipsTouch=false;return;}
    if(TouchArea!=Area||(Area==0)){const bool First=Area!=0&&AreaExperience(Area)<.05f&&AreaSeconds[Area]<=0.f;
        Note(OKMsg(First?TEXT("ui.hscene.event_first_body"):TEXT("ui.hscene.event_body"),{{TEXT("how"),How},{TEXT("part"),Part}}));}
    TouchArea=Area;Flinch(Area);
}
void UOKHScenePanel::Flinch(int32 Area){
    static const TCHAR* Bones[]={TEXT("cf_j_head"),TEXT("cf_j_forearm01_"),TEXT("cf_j_thigh00_"),TEXT("cf_j_leg01_"),TEXT("cf_j_leg03_")};
    static const float Amp[]={7.f,14.f,6.f,9.f,12.f};
    const int32 I=Area==0?0:FMath::Clamp(Area-6,0,4);const FString Side=I==0?FString():FString(FMath::RandBool()?TEXT("L"):TEXT("R"));
    FlinchBone=FString(TEXT("+"))+Bones[I]+Side;
    FlinchTurn=FVector(FMath::FRandRange(-1.f,1.f),FMath::FRandRange(-1.f,1.f),FMath::FRandRange(-1.f,1.f)).GetSafeNormal()*Amp[I]*(Area==0?.6f:1.f)*(1.f-.6f*Dev(Area==0?TEXT("kiss"):HBodyKey(Area)));
    const double Now=FPlatformTime::Seconds();FlinchUntil=Now+.45;FlinchNext=Now+FMath::FRandRange(2.f,3.5f);
}
void UOKHScenePanel::Note(const FString& Text,bool bReact){Events.Add(Text);if(Gallery)Gallery->NoteAction(TEXT("h"),Text);if(bReact)React(Text);if(Hint)Hint->SetText(FText::FromString(Text));UE_LOG(LogTemp,Display,TEXT("H scene: %s"),*Text);}

TSharedRef<SWidget> UOKHScenePanel::RebuildWidget(){
    if(!WidgetTree)WidgetTree=NewObject<UWidgetTree>(this);
    UHorizontalBox* Root=WidgetTree->ConstructWidget<UHorizontalBox>();WidgetTree->RootWidget=Root;
    {HSettingsLoad();SettingSliders.Reset();bCoordinateList=false;CoordButtons.Reset();CoordImages.Reset();CoordTextures.Reset();
     auto Label=[&](const FString& Words,float Size,const FLinearColor& Color){auto* T=WidgetTree->ConstructWidget<UTextBlock>();FSlateFontInfo F=T->GetFont();F.Size=Size;T->SetFont(F);T->SetColorAndOpacity(FSlateColor(Color));T->SetText(FText::FromString(Words));return T;};
     auto Button=[&](int32 Kind,const TCHAR* Key){auto* B=WidgetTree->ConstructWidget<UOKHSceneButton>();B->Kind=Kind;B->Owner=this;B->OnClicked.AddDynamic(B,&UOKHSceneButton::HandleClick);B->SetContent(Label(OKT(Key),10.f,FLinearColor::Black));return B;};
     UVerticalBox* Left=WidgetTree->ConstructWidget<UVerticalBox>();
     if(auto* S=Root->AddChildToHorizontalBox(Left)){S->SetPadding(FMargin(16,72,0,16));S->SetVerticalAlignment(VAlign_Fill);}
     if(auto* S=Left->AddChildToVerticalBox(Button(SettingsToggle,TEXT("ui.hscene.settings"))))S->SetHorizontalAlignment(HAlign_Left);
     SettingsBox=WidgetTree->ConstructWidget<USizeBox>();SettingsBox->SetWidthOverride(260.f);SettingsBox->SetVisibility(ESlateVisibility::Collapsed);
     if(auto* S=Left->AddChildToVerticalBox(SettingsBox)){S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));S->SetPadding(FMargin(0,6,0,0));}
     UBorder* Back=WidgetTree->ConstructWidget<UBorder>();Back->SetBrushColor(FLinearColor(.06f,.02f,.05f,.82f));Back->SetPadding(FMargin(10));SettingsBox->AddChild(Back);
     UScrollBox* Rows=WidgetTree->ConstructWidget<UScrollBox>();Back->AddChild(Rows);
     for(int32 I=0;I<UE_ARRAY_COUNT(HSettings);++I){const FHSetting& H=HSettings[I];
         if(!H.Var){Rows->AddChild(Label(OKT(H.Label),11.f,FLinearColor(1.f,.75f,.85f)));continue;}
         UHorizontalBox* Top=WidgetTree->ConstructWidget<UHorizontalBox>();
         if(auto* S=Top->AddChildToHorizontalBox(Label(OKT(H.Label),9.f,FLinearColor::White)))S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
         auto* Shown=Label(FString(),9.f,FLinearColor(1.f,.9f,.6f));Top->AddChildToHorizontalBox(Shown);Rows->AddChild(Top);
         auto* Slider=WidgetTree->ConstructWidget<UOKHSettingSlider>();Slider->Row=I;Slider->Owner=this;Slider->Shown=Shown;Slider->SetMinValue(H.Low);Slider->SetMaxValue(H.High);Slider->SetStepSize(H.Step);
         Slider->OnValueChanged.AddDynamic(Slider,&UOKHSettingSlider::HandleValue);Slider->OnMouseCaptureEnd.AddDynamic(Slider,&UOKHSettingSlider::HandleDone);Rows->AddChild(Slider);SettingSliders.Add(Slider);}
     Rows->AddChild(Button(SettingsReset,TEXT("ui.hscene.settings_reset")));}
    // Coordinate cards by their pictures, down both sides of her (user 2026-11-04): ShowCoordinates fills them.
    auto CoordSide=[&](int32 Side){
        CoordSides[Side]=WidgetTree->ConstructWidget<USizeBox>();CoordSides[Side]->SetWidthOverride(456.f);CoordSides[Side]->SetVisibility(ESlateVisibility::Collapsed);
        if(auto* S=Root->AddChildToHorizontalBox(CoordSides[Side])){S->SetPadding(FMargin(8,72,8,16));S->SetVerticalAlignment(VAlign_Fill);}
        UBorder* Back=WidgetTree->ConstructWidget<UBorder>();Back->SetBrushColor(FLinearColor(.06f,.02f,.05f,.6f));Back->SetPadding(FMargin(6));CoordSides[Side]->AddChild(Back);
        UVerticalBox* Column=WidgetTree->ConstructWidget<UVerticalBox>();Back->AddChild(Column);
        // The panel on the right is away while they show: closing them and what they change are here.
        if(Side==0){UHorizontalBox* Top=WidgetTree->ConstructWidget<UHorizontalBox>();
            auto Bar=[&](int32 Kind,const TCHAR* Key){auto* B=WidgetTree->ConstructWidget<UOKHSceneButton>();B->Kind=Kind;B->Owner=this;B->OnClicked.AddDynamic(B,&UOKHSceneButton::HandleClick);
                auto* T=WidgetTree->ConstructWidget<UTextBlock>();FSlateFontInfo Font=T->GetFont();Font.Size=10;T->SetFont(Font);T->SetColorAndOpacity(FSlateColor(FLinearColor::Black));T->SetText(FText::FromString(OKT(Key)));B->SetContent(T);
                if(auto* S=Top->AddChildToHorizontalBox(B))S->SetPadding(FMargin(0,0,6,0));return T;};
            Bar(CoordinateToggle,TEXT("ui.hscene.coordinate_close"));CoordAccessories=Bar(CoordinateAccessories,TEXT("ui.hscene.coordinate_clothes_only"));
            Column->AddChildToVerticalBox(Top)->SetPadding(FMargin(0,0,0,6));}
        UScrollBox* Scroll=WidgetTree->ConstructWidget<UScrollBox>();Scroll->SetAlwaysShowScrollbar(true);Scroll->SetScrollbarThickness(FVector2D(14.f,14.f));
        // Up to 500 tiles: painted once and kept (36 ms a frame otherwise), not walked every frame.
        UInvalidationBox* Cached=WidgetTree->ConstructWidget<UInvalidationBox>();Cached->SetContent(Scroll);Column->AddChildToVerticalBox(Cached)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
        CoordWraps[Side]=WidgetTree->ConstructWidget<UWrapBox>();CoordWraps[Side]->SetInnerSlotPadding(FVector2D(6,6));CoordWraps[Side]->SetExplicitWrapSize(true);CoordWraps[Side]->SetWrapSize(424.f);Scroll->AddChild(CoordWraps[Side]);};
    CoordSide(0);
    USizeBox* Space=WidgetTree->ConstructWidget<USizeBox>();Space->SetVisibility(ESlateVisibility::HitTestInvisible);Root->AddChildToHorizontalBox(Space)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
    CoordSide(1);
    USizeBox* Width=WidgetTree->ConstructWidget<USizeBox>();Width->SetWidthOverride(340.f);
    if(auto* S=Root->AddChildToHorizontalBox(Width)){S->SetPadding(FMargin(0,72,16,16));S->SetVerticalAlignment(VAlign_Fill);}
    UBorder* Back=WidgetTree->ConstructWidget<UBorder>();Back->SetBrushColor(FLinearColor(.06f,.02f,.05f,.82f));Back->SetPadding(FMargin(12));
    // Half size (user, 2026-11-02: the panel text was too big): laid out twice as wide, drawn at half.
    UScaleBox* Half=WidgetTree->ConstructWidget<UScaleBox>();Half->SetStretch(EStretch::UserSpecified);Half->SetUserSpecifiedScale(.5f);Half->SetStretchDirection(EStretchDirection::Both);Width->AddChild(Half);
    HalfInner=WidgetTree->ConstructWidget<USizeBox>();HalfInner->SetWidthOverride(680.f);Half->AddChild(HalfInner);HalfInner->AddChild(Back);PanelWidth=Width;
    UVerticalBox* Box=WidgetTree->ConstructWidget<UVerticalBox>();Back->AddChild(Box);
    auto Text=[&](float Size,const FLinearColor& Color){auto* T=WidgetTree->ConstructWidget<UTextBlock>();FSlateFontInfo F=T->GetFont();F.Size=Size;T->SetFont(F);T->SetColorAndOpacity(FSlateColor(Color));T->SetAutoWrapText(true);Box->AddChildToVerticalBox(T)->SetPadding(FMargin(0,2));return T;};
    auto Gauge=[&](const TCHAR* Label,const FLinearColor& Color){
        UHorizontalBox* Row=WidgetTree->ConstructWidget<UHorizontalBox>();
        auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(OKT(Label)));L->SetColorAndOpacity(FSlateColor(FLinearColor::White));
        if(auto* S=Row->AddChildToHorizontalBox(L)){S->SetPadding(FMargin(0,0,8,0));S->SetVerticalAlignment(VAlign_Center);}
        auto* Bar=WidgetTree->ConstructWidget<UProgressBar>();Bar->SetFillColorAndOpacity(Color);Bar->SetPercent(0.f);
        if(auto* S=Row->AddChildToHorizontalBox(Bar)){S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));S->SetVerticalAlignment(VAlign_Center);}
        Box->AddChildToVerticalBox(Row)->SetPadding(FMargin(0,3));return Bar;
    };
    Title=Text(15.f,FLinearColor(1.f,.8f,.9f));
    Status=Text(12.f,FLinearColor::White);
    HerGauge=Gauge(TEXT("ui.hscene.her_gauge"),FLinearColor(1.f,.35f,.6f));
    HisGauge=Gauge(TEXT("ui.hscene.his_gauge"),FLinearColor(.35f,.6f,1.f));
    DevLine=Text(11.f,FLinearColor(1.f,.75f,.85f));
    {
        UHorizontalBox* Row=WidgetTree->ConstructWidget<UHorizontalBox>();
        auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(OKT(TEXT("ui.hscene.speed"))));L->SetColorAndOpacity(FSlateColor(FLinearColor::White));
        if(auto* S=Row->AddChildToHorizontalBox(L)){S->SetPadding(FMargin(0,0,8,0));S->SetVerticalAlignment(VAlign_Center);}
        Speed=WidgetTree->ConstructWidget<USlider>();Speed->SetMinValue(0.f);Speed->SetMaxValue(1.f);Speed->SetValue(SpeedValue);
        // The original's cover over the bar past 70% (HAibu SetSpriteDislikesis70): touched where she never was, faster
        // than that and she pulls away.
        UOverlay* Over=WidgetTree->ConstructWidget<UOverlay>();if(UOverlaySlot* O=Over->AddChildToOverlay(Speed)){O->SetHorizontalAlignment(HAlign_Fill);O->SetVerticalAlignment(VAlign_Center);}
        UHorizontalBox* Marks=WidgetTree->ConstructWidget<UHorizontalBox>();Marks->SetVisibility(ESlateVisibility::HitTestInvisible);
        if(auto* S=Marks->AddChildToHorizontalBox(WidgetTree->ConstructWidget<USpacer>())){FSlateChildSize Z(ESlateSizeRule::Fill);Z.Value=.7f;S->SetSize(Z);}
        SpeedCover=WidgetTree->ConstructWidget<UBorder>();SpeedCover->SetBrushColor(FLinearColor(.85f,.1f,.15f,.45f));SpeedCover->SetVisibility(ESlateVisibility::Hidden);
        if(auto* S=Marks->AddChildToHorizontalBox(SpeedCover)){FSlateChildSize Z(ESlateSizeRule::Fill);Z.Value=.3f;S->SetSize(Z);}
        if(UOverlaySlot* O=Over->AddChildToOverlay(Marks)){O->SetHorizontalAlignment(HAlign_Fill);O->SetVerticalAlignment(VAlign_Fill);}
        if(auto* S=Row->AddChildToHorizontalBox(Over))S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
        Box->AddChildToVerticalBox(Row)->SetPadding(FMargin(0,3));
    }
    {
        PenisBox=WidgetTree->ConstructWidget<UVerticalBox>();PenisBox->SetVisibility(bPenisPanel?ESlateVisibility::Visible:ESlateVisibility::Collapsed);
        auto Row=[&](const TCHAR* Key,float Value,USlider*& Out){UHorizontalBox* R=WidgetTree->ConstructWidget<UHorizontalBox>();
            auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(OKT(Key)));L->SetColorAndOpacity(FSlateColor(FLinearColor::White));
            if(auto* S=R->AddChildToHorizontalBox(L)){S->SetPadding(FMargin(0,0,8,0));S->SetVerticalAlignment(VAlign_Center);}
            Out=WidgetTree->ConstructWidget<USlider>();Out->SetMinValue(.5f);Out->SetMaxValue(2.f);Out->SetStepSize(.05f);Out->SetValue(Value);
            if(auto* S=R->AddChildToHorizontalBox(Out))S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));PenisBox->AddChildToVerticalBox(R)->SetPadding(FMargin(0,2));};
        USlider* LengthS=nullptr;USlider* ScaleS=nullptr;Row(TEXT("ui.hscene.penis_length"),PenisLength,LengthS);Row(TEXT("ui.hscene.penis_scale"),PenisScale,ScaleS);
        LengthSlider=LengthS;ScaleSlider=ScaleS;LengthSlider->OnValueChanged.AddDynamic(this,&UOKHScenePanel::OnPenisLength);ScaleSlider->OnValueChanged.AddDynamic(this,&UOKHScenePanel::OnPenisScale);
        PenisLabel=WidgetTree->ConstructWidget<UTextBlock>();PenisLabel->SetColorAndOpacity(FSlateColor(FLinearColor(1.f,.9f,.6f)));PenisBox->AddChildToVerticalBox(PenisLabel);
        RootPadWidget=CreateWidget<UOKHRootPad>(this,UOKHRootPad::StaticClass());RootPadWidget->Owner=this;RootPadWidget->Value=RootPad;
        if(auto* S=PenisBox->AddChildToVerticalBox(RootPadWidget)){S->SetHorizontalAlignment(HAlign_Center);S->SetPadding(FMargin(0,4));}
        Box->AddChildToVerticalBox(PenisBox)->SetPadding(FMargin(0,3));ShowPenis();
    }
    {   // Her pose (SetHerPose): ankles, each thigh, each hand.
        auto Label=[&](UHorizontalBox* R,const TCHAR* Key){auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(OKT(Key)));L->SetColorAndOpacity(FSlateColor(FLinearColor(1.f,.85f,.9f)));
            if(auto* S=R->AddChildToHorizontalBox(L)){S->SetPadding(FMargin(0,0,8,0));S->SetVerticalAlignment(VAlign_Center);}};
        auto Row=[&](const TCHAR* Key,float Low,float High,float Value)->USlider*{UHorizontalBox* R=WidgetTree->ConstructWidget<UHorizontalBox>();Label(R,Key);
            auto* S_=WidgetTree->ConstructWidget<USlider>();S_->SetMinValue(Low);S_->SetMaxValue(High);S_->SetStepSize(1.f);S_->SetValue(Value);
            if(auto* S=R->AddChildToHorizontalBox(S_))S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));Box->AddChildToVerticalBox(R)->SetPadding(FMargin(0,1));return S_;};
        Text(11.f,FLinearColor(1.f,.75f,.85f))->SetText(FText::FromString(OKT(TEXT("ui.hscene.her_pose"))));
        AnkleSlider=Row(TEXT("ui.hscene.ankle"),-60.f,60.f,AnkleTurn);AnkleSlider->OnValueChanged.AddDynamic(this,&UOKHScenePanel::OnAnkle);
        ThighSliders[0]=Row(TEXT("ui.hscene.thigh_l"),-30.f,60.f,ThighOpen[0]);ThighSliders[0]->OnValueChanged.AddDynamic(this,&UOKHScenePanel::OnThighL);
        ThighSliders[1]=Row(TEXT("ui.hscene.thigh_r"),-30.f,60.f,ThighOpen[1]);ThighSliders[1]->OnValueChanged.AddDynamic(this,&UOKHScenePanel::OnThighR);
        TongueSlider=Row(TEXT("ui.hscene.tongue_length"),0.f,2.f,CVarHTongueLength.GetValueOnGameThread());TongueSlider->SetStepSize(.05f);TongueSlider->OnValueChanged.AddDynamic(this,&UOKHScenePanel::OnTongueLength);
        UHorizontalBox* R=WidgetTree->ConstructWidget<UHorizontalBox>();HandOptions=-1;
        for(int32 Side=0;Side<2;++Side){Label(R,Side?TEXT("ui.hscene.hand_r"):TEXT("ui.hscene.hand_l"));
            HandCombos[Side]=WidgetTree->ConstructWidget<UOKComboBoxString>();HandCombos[Side]->AddOption(OKT(TEXT("ui.hscene.hand_follow")));HandCombos[Side]->SetSelectedIndex(0);
            if(Side)HandCombos[Side]->OnSelectionChanged.AddDynamic(this,&UOKHScenePanel::OnHandR);else HandCombos[Side]->OnSelectionChanged.AddDynamic(this,&UOKHScenePanel::OnHandL);
            if(auto* S=R->AddChildToHorizontalBox(HandCombos[Side])){S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));S->SetPadding(FMargin(0,0,6,0));}}
        Box->AddChildToVerticalBox(R)->SetPadding(FMargin(0,2));
    }
    {   // Light and shadow (user 2026-11-04): their ramp, where the light comes from, its colour. HG is not here: it starts the map again.
        Text(11.f,FLinearColor(1.f,.75f,.85f))->SetText(FText::FromString(OKT(TEXT("ui.hscene.light"))));
        auto Row=[&](int32 I,const TCHAR* Key){UHorizontalBox* R=WidgetTree->ConstructWidget<UHorizontalBox>();
            auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(OKT(Key)));L->SetColorAndOpacity(FSlateColor(FLinearColor(1.f,.85f,.9f)));
            if(auto* S=R->AddChildToHorizontalBox(L)){S->SetPadding(FMargin(0,0,8,0));S->SetVerticalAlignment(VAlign_Center);}
            LightCombos[I]=WidgetTree->ConstructWidget<UOKComboBoxString>();if(auto* S=R->AddChildToHorizontalBox(LightCombos[I]))S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            Box->AddChildToVerticalBox(R)->SetPadding(FMargin(0,2));return LightCombos[I].Get();};
        UComboBoxString* Style=Row(0,TEXT("ui.hscene.light_style"));Style->AddOption(OKT(TEXT("ui.hscene.light_style_card")));LightRampKeys.Reset();
        for(const FOKRenderRamp& Ramp:OKRenderRamps()){const FString Id=TEXT("ui.settings.ramp_")+Ramp.Key;const FString Name=OKT(*Id);Style->AddOption(Name==Id?Ramp.Name:Name);LightRampKeys.Add(Ramp.Key);}
        UComboBoxString* From=Row(1,TEXT("ui.hscene.light_from"));for(const TCHAR* Key:{TEXT("ui.hscene.light_from_camera"),TEXT("ui.hscene.light_from_left"),TEXT("ui.hscene.light_from_right"),TEXT("ui.hscene.light_from_above"),TEXT("ui.hscene.light_from_below"),TEXT("ui.hscene.light_from_behind"),TEXT("ui.hscene.light_from_street")})From->AddOption(OKT(Key));
        UComboBoxString* Tint=Row(2,TEXT("ui.hscene.light_tint"));for(const TCHAR* Key:{TEXT("ui.hscene.light_tint_white"),TEXT("ui.hscene.light_tint_warm"),TEXT("ui.hscene.light_tint_cold"),TEXT("ui.hscene.light_tint_dusk"),TEXT("ui.hscene.light_tint_night")})Tint->AddOption(OKT(Key));
        Style->SetSelectedIndex(0);From->SetSelectedIndex(0);Tint->SetSelectedIndex(0);
        Style->OnSelectionChanged.AddDynamic(this,&UOKHScenePanel::OnLightStyle);From->OnSelectionChanged.AddDynamic(this,&UOKHScenePanel::OnLightFrom);Tint->OnSelectionChanged.AddDynamic(this,&UOKHScenePanel::OnLightTint);
    }
    Actions=WidgetTree->ConstructWidget<UWrapBox>();Actions->SetInnerSlotPadding(FVector2D(6,6));Box->AddChildToVerticalBox(Actions)->SetPadding(FMargin(0,8));
    Hint=Text(12.f,FLinearColor(1.f,.9f,.6f));
    Caption=Text(13.f,FLinearColor(1.f,1.f,1.f));
    Input=WidgetTree->ConstructWidget<UEditableTextBox>();Input->SetHintText(FText::FromString(OKT(TEXT("ui.hscene.say_hint"))));Input->OnTextCommitted.AddDynamic(this,&UOKHScenePanel::OnInputCommitted);
    Box->AddChildToVerticalBox(Input)->SetPadding(FMargin(0,4));
    Tabs=WidgetTree->ConstructWidget<UWrapBox>();Tabs->SetInnerSlotPadding(FVector2D(4,4));Box->AddChildToVerticalBox(Tabs)->SetPadding(FMargin(0,8,0,4));
    List=WidgetTree->ConstructWidget<UScrollBox>();
    if(auto* S=Box->AddChildToVerticalBox(List))S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
    auto Tab_=[this](int32 Kind,const TCHAR* Key){auto* B=WidgetTree->ConstructWidget<UOKHSceneButton>();B->Kind=Kind;B->Owner=this;B->OnClicked.AddDynamic(B,&UOKHSceneButton::HandleClick);auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(OKT(Key)));B->SetContent(L);Tabs->AddChildToWrapBox(B);};
    Tab_(TabAibu,TEXT("ui.hscene.tab_aibu"));Tab_(TabHand,TEXT("ui.hscene.tab_hand"));Tab_(TabMouth,TEXT("ui.hscene.tab_mouth"));Tab_(TabBreast,TEXT("ui.hscene.tab_breast"));Tab_(TabSonyu,TEXT("ui.hscene.tab_sonyu"));Tab_(TabClothes,TEXT("ui.hscene.tab_clothes"));
    SetVisibility(ESlateVisibility::SelfHitTestInvisible);
    return Super::RebuildWidget();
}

void UOKHScenePanel::LoadPoses(){
    Poses.Reset();if(!Gallery)return;
    const auto& Meta=HPoseMeta();
    for(int32 I=0;I<Gallery->NativePairs.Num();++I){
        const auto& Row=Gallery->NativePairs[I];if(!Row)continue;
        const FString Category=Row->GetStringField(TEXT("category"));const int32 Id=int32(Row->GetNumberField(TEXT("id")));
        FOKHPose Pose;Pose.Pair=I;Pose.Mode=Category==TEXT("AnimationInfo_01")?1:Category==TEXT("AnimationInfo_02")?2:0;if(!Pose.Mode||!HFitsRoom(Category,Id))continue;
        Pose.Name=Row->GetStringField(TEXT("name"));
        if(const TSharedPtr<FJsonObject>* M=Meta.Find(FString::Printf(TEXT("%s:%d"),*Category,Id))){
            Pose.KindHoushi=int32((*M)->GetNumberField(TEXT("kind_houshi")));Pose.SysTaii=int32((*M)->GetNumberField(TEXT("sys_taii")));Pose.Anal=(*M)->GetBoolField(TEXT("anal"));
            Pose.FemaleLead=(*M)->HasField(TEXT("female_initiative"))&&(*M)->GetBoolField(TEXT("female_initiative"));
            Pose.IsExperience=int32((*M)->GetNumberField(TEXT("is_experience")));Pose.StateRestriction=int32((*M)->GetNumberField(TEXT("state_restriction")));
            Pose.UpperCloth=int32((*M)->GetNumberField(TEXT("upper_cloth")));Pose.LowerCloth=int32((*M)->GetNumberField(TEXT("lower_cloth")));
            const FString Named=(*M)->GetStringField(TEXT("name"));if(!Named.IsEmpty())Pose.Name=Named;
        }
        Pose.Prop=FMath::Max(0,HPropKind(Category,Id));
        if(Pose.Name.IsEmpty())Pose.Name=FString::Printf(TEXT("#%d"),Id);
        Pose.Raw=Pose.Name;Pose.Name=OKMotionLabelDisplay(Pose.Raw);
        Poses.Add(Pose);
    }
}

static bool OKHServiceSpent(int32 Finishes,const TSharedPtr<FJsonObject>& X);
void UOKHScenePanel::ReadOutfitGaps(){
    const AOKInteractionMode* M=Interaction();if(!M)return;FString Root,Card;M->OpenedSource(Root,Card);if(Card==OutfitGapCard)return;
    OutfitGapCard=Card;OutfitGaps.Reset();OutfitWarned=INDEX_NONE;
    Async(EAsyncExecution::Thread,[Weak=TWeakObjectPtr<UOKHScenePanel>(this),Root,Card]{
        const FString Json=FOkSession::CardOutfitGaps(Root,Card);
        AsyncTask(ENamedThreads::GameThread,[Weak,Card,Json]{UOKHScenePanel* Panel=Weak.Get();if(!Panel||Panel->OutfitGapCard!=Card)return;
            TArray<TSharedPtr<FJsonValue>> Rows;if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Rows)){UE_LOG(LogTemp,Warning,TEXT("H scene outfit gaps: nothing read for %s"),*Card);return;}
            for(const auto& V:Rows){const auto Row=V->AsObject();const TArray<TSharedPtr<FJsonValue>>* Gaps=nullptr;if(!Row||!Row->TryGetArrayField(TEXT("gaps"),Gaps)||Gaps->IsEmpty())continue;
                FOutfitGap& Gap=Panel->OutfitGaps.Add(Row->GetIntegerField(TEXT("outfit")));Gap.Count=Gaps->Num();Gap.bSevere=Row->GetBoolField(TEXT("severe"));}
            UE_LOG(LogTemp,Display,TEXT("H scene outfit gaps: %d of her outfits lack something"),Panel->OutfitGaps.Num());
            if(Panel->OutfitGaps.Num()&&Panel->Tab==TabClothes)Panel->BuildList();});});
}
void UOKHScenePanel::BuildList(){
    if(!List||!WidgetTree)return;List->ClearChildren();
    if(bCoordinateList&&Tab!=TabClothes){bCoordinateList=false;ShowCoordinates();}
    auto Add=[this](int32 Kind,const FString& Label,bool Enabled,bool Current){
        auto* B=WidgetTree->ConstructWidget<UOKHSceneButton>();B->Kind=Kind;B->Owner=this;B->OnClicked.AddDynamic(B,&UOKHSceneButton::HandleClick);B->SetIsEnabled(Enabled);
        if(Current)B->SetBackgroundColor(FLinearColor(1.f,.45f,.7f));
        auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(Label));L->SetAutoWrapText(true);L->SetJustification(ETextJustify::Center);
        // The label fills the button: centred in it, it wrapped at its own last width ("單手／交" on two lines).
        if(auto* S=Cast<UButtonSlot>(B->SetContent(L)))S->SetHorizontalAlignment(HAlign_Fill);List->AddChild(B);
    };
    if(Tab==TabClothes){
        static const TCHAR* Parts[]={TEXT("ui.hscene.cloth_top"),TEXT("ui.hscene.cloth_bottom"),TEXT("ui.hscene.cloth_bra"),TEXT("ui.hscene.cloth_shorts"),TEXT("ui.hscene.cloth_gloves"),TEXT("ui.hscene.cloth_pantyhose"),TEXT("ui.hscene.cloth_socks"),TEXT("ui.hscene.cloth_inner_shoes"),TEXT("ui.hscene.cloth_shoes")};
        static const TCHAR* States[]={TEXT("ui.hscene.cloth_on"),TEXT("ui.hscene.cloth_half"),TEXT("ui.hscene.cloth_half2"),TEXT("ui.hscene.cloth_off")};
        // Each piece she is wearing comes off or goes back on by itself (visibility only: a reload would end the scene).
        static const TCHAR* Views[]={TEXT("ui.hscene.male_view_shown"),TEXT("ui.hscene.male_view_ghost"),TEXT("ui.hscene.male_view_hidden")};
        Add(ClothesBase+100,OKT(TEXT("ui.hscene.cloth_all_on")),true,false);Add(ClothesBase+101,OKT(TEXT("ui.hscene.cloth_all_half")),true,false);Add(ClothesBase+102,OKT(TEXT("ui.hscene.cloth_all_off")),true,false);
        Add(ToggleMale,OKT(Views[FMath::Clamp(MaleView,0,2)]),Mode!=0,MaleView!=0);
        Add(MaleBottom,OKT(bMaleBottomOff?TEXT("ui.hscene.male_bottom_off"):TEXT("ui.hscene.male_bottom_on")),Mode!=0,bMaleBottomOff);
        Add(RoomBase,OKT(TEXT("ui.hscene.room_floor")),true,Room==0);Add(RoomBase+1,OKT(TEXT("ui.hscene.room_bed")),true,Room==1);
        auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;
        for(int32 K=0;K<9;++K)if(Girl&&Girl->HasClothingKind(K)&&Girl->DisplayClothesStates[K]!=3)
            Add(ClothesBase+K,FString::Printf(TEXT("%s：%s"),OKT(Parts[K]),OKT(States[FMath::Clamp<int32>(Gallery->ClothesStates[K],0,3)])),true,Gallery->ClothesStates[K]==3);
        // Her outfits, as the original H scene's coordinate buttons, and the game's coordinate cards worn as the one on.
        const AOKInteractionMode* M=Interaction();const bool Free=M&&M->IsReady()&&!M->IsChangingOutfit();
        const FString Worn=M?M->WornCoordinate:FString();
        ReadOutfitGaps();
        for(int32 O=0;O<FMath::Min(Gallery->Selected.Outfits.Num(),10);++O){const FOutfitGap* Gap=OutfitGaps.Find(O);
            Add(OutfitBase+O,OKMsg(TEXT("ui.hscene.outfit"),{{TEXT("name"),FString(OKT(*FString::Printf(TEXT("ui.hscene.outfit_%d"),FMath::Min(O,7))))}})+(Gap?FString(OKT(TEXT("ui.hscene.outfit_gap_tag"))):FString()),Free,Worn.IsEmpty()&&O==Gallery->OutfitIndex);}
        Add(CoordinateToggle,OKT(bCoordinateList?TEXT("ui.hscene.coordinate_close"):TEXT("ui.hscene.coordinate_open")),true,!Worn.IsEmpty());
        return;
    }
    // Never played with her (hexp.rs poses_played, this scene's too): New (H_SCENE_ADDITIONS_PLAN 5).
    TSet<FString> Played(PosesPlayed);{const TArray<TSharedPtr<FJsonValue>>* Had=nullptr;
     if(Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetArrayField(TEXT("poses_played"),Had))for(const auto& V:*Had)Played.Add(V->AsString());}
    auto Fresh=[&](const FString& Name){return Played.Contains(Name)?FString():OKT(TEXT("ui.hscene.new_mark"));};
    if(Tab==TabAibu){if(!bAibuLoaded)LoadAibuPoses();for(int32 I=0;I<AibuPoses.Num();++I)Add(AibuBase+I,AibuPoses[I].Name+Fresh(AibuPoses[I].Name),true,(I==ActiveAibu&&Mode==0)||I==PendingAibu);return;}
    const bool Used=Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->GetBoolField(TEXT("used"));
    for(int32 I=0;I<Poses.Num();++I){const FOKHPose& Pose=Poses[I];
        const bool Shown=Tab==TabSonyu?Pose.Mode==2:Pose.Mode==1&&Pose.KindHoushi==Tab-TabHand;if(!Shown)continue;
        const bool PregLocked=PregLocks(Pose);const bool Locked=Pose.IsExperience==1&&!Used||PregLocked;
        // Her service rounds used up (she said so): no hand, mouth or breast pose to pick, as she would not start it.
        const bool Spent=Pose.Mode==1&&(bServiceRefused||OKHServiceSpent(ServiceFinishes,Gallery?Gallery->HExperience:nullptr));
        FString Label=Pose.Name;if(Pose.Anal)Label+=OKT(TEXT("ui.hscene.anal_mark"));
        // The room brings a seat, table or wall for it (PlaceProps).
        if(Pose.Prop>=1&&Pose.Prop<=3)Label+=OKT(*FString::Printf(TEXT("ui.hscene.prop_mark_%d"),Pose.Prop));
        if(Locked)Label+=OKT(PregLocked?TEXT("ui.hscene.preg_locked_mark"):TEXT("ui.hscene.locked_mark"));Label+=Fresh(Pose.Name);
        Add(PoseBase+I,Label,!Locked&&!Spent,(Mode!=0&&I==ActivePose)||I==PendingPose);
    }
}

static TAutoConsoleVariable<float> CVarHCondomMouthSeconds(TEXT("ok.HScene.CondomMouthSeconds"),6.f,TEXT("How long she is at it when she puts the condom on him with her mouth."));
void UOKHScenePanel::SelectPose(int32 Index){
    if(!Gallery||!Poses.IsValidIndex(Index)||!Gallery->PairCombo)return;
    int32 Option=Gallery->PairVisibleIndices.Find(Poses[Index].Pair);
    if(Option==INDEX_NONE&&Gallery->PairCategoryCombo){Gallery->PairCategoryCombo->SetSelectedIndex(0);Option=Gallery->PairVisibleIndices.Find(Poses[Index].Pair);}
    if(Option==INDEX_NONE){Note(OKT(TEXT("ui.hscene.pose_missing")),false);return;}
    if(Gallery->PartnerActor)Gallery->PartnerActor->SetActorHiddenInGame(false);
    ++AibuGeneration;PendingAibu=INDEX_NONE;TouchArea=INDEX_NONE;
    DropSpentCondom();PendingPose=Index;Queue.Reset();Wanted.Reset();bAnalPlay=false;bInsideFinished=false;bStrong=false;
    // Already the list's choice (the scene opens with its first pose there, or he picks the one playing): setting it again
    // fires nothing and the pose stayed pending for good, so load it as a new choice.
    if(Gallery->PairCombo->GetSelectedIndex()==Option+1)Gallery->OnPairSelected(Gallery->PairCombo->GetSelectedOption(),ESelectInfo::OnMouseClick);
    else Gallery->PairCombo->SetSelectedIndex(Option+1);
    Gallery->NoteAction(TEXT("pair"),Poses[Index].Name);
    PoseClothes(Poses[Index]);
    BuildList();
}
// As the original starts a pose (HSceneProc SetAllClothState from numFemaleUpper/LowerCloth): her top and bra, or her
// bottom, panties and pantyhose, undone at least that far (1 shifted aside, 3 off), never put back on. Shifted is a piece's
// half state where it has one (ClothesTransition, one press of its button), off where it has none; a half state opens her
// again in it (as the clothes buttons), off only hides it.
void UOKHScenePanel::PoseClothes(const FOKHPose& Pose){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;AOKInteractionMode* M=Interaction();if(!IsValid(Girl)||!M)return;
    uint8* S=Gallery->ClothesStates;uint8 Next[9];FMemory::Memcpy(Next,S,9);
    auto Undo=[&](std::initializer_list<int32> Parts,int32 State){
        if(State<=0)return;
        for(const int32 K:Parts){if(Next[K]>=State)continue;
            uint8 Press[9];FString Why;
            Next[K]=State>=3||!M->ClothesTransition(K,Press,Why)||Press[K]==0?3:Press[K];}
    };
    Undo({0,2},Pose.UpperCloth);Undo({1,3,5},Pose.LowerCloth);
    if(FMemory::Memcmp(Next,S,9)==0)return;
    bool Shown=true;for(int32 K=0;K<9;++K)Shown&=Next[K]==3||Next[K]==Girl->DisplayClothesStates[K];
    if(!Shown&&M->ChangeClothesStates(Next)){FMemory::Memcpy(S,Next,9);Gallery->RefreshClothesStateLabels();return;}
    // Opening her again is busy: off instead, so nothing goes through her clothes.
    for(int32 K=0;K<9;++K)if(Next[K]!=S[K]&&Next[K]!=Girl->DisplayClothesStates[K])Next[K]=3;
    FMemory::Memcpy(S,Next,9);Girl->SetClothingPartsHidden(S);Gallery->RefreshClothesStateLabels();
}

void UOKHScenePanel::Want(const FString& State){
    if(!Has(State)){UE_LOG(LogTemp,Display,TEXT("H scene: pose has no state %s"),*State);return;}
    Wanted=State;LastRequest=0.;
}
void UOKHScenePanel::Chain(const TArray<FString>& States){
    Queue.Reset();for(const FString& S:States)if(Has(S))Queue.Add(S);
    if(!Queue.IsEmpty())Want(Queue[0]);
}

void UOKHScenePanel::ApplySpeed(){
    if(!Gallery||!Gallery->PairedPlayback)return;
    const float Target=HIsLoop(HBase(Current()))?PlaybackSpeed():1.f;
    if(!FMath::IsNearlyEqual(Gallery->PairedPlayback->GetSpeed(),Target,.01f))Gallery->OnPairSpeed(Target/4.f);
}

// A place of hers past 30 (she starts to feel it), 60 (sensitive) or 100 (used to him) with this climax or his coming in
// her mouth (H_DEVELOPMENT_EXPERIENCE_PLAN P3): said with the event, so her reaction to it speaks of it.
static FString OKDevStep(const TCHAR* Area,float Before,float After){
    for(const int32 Step:{100,60,30})if(Before<Step/100.f-1e-4f&&After>=Step/100.f-1e-4f)
        return OKMsg(TEXT("ui.hscene.event_dev_step"),{{TEXT("area"),OKT(*(FString(TEXT("ui.hscene.dev_area_"))+Area))},{TEXT("step"),Step}});
    return FString();
}

// Where his inside finish of a service goes: her mouth for a mouth pose, and for one with him in her mouth (sysTaii 2:
// パイズリ+咥え), as the original's IN_Start leads on to Oral_Idle (she holds it, then swallows or spits) for every pose.
bool UOKHScenePanel::FinishInMouth() const{
    if(!Poses.IsValidIndex(ActivePose))return true;const FOKHPose& P=Poses[ActivePose];
    return P.KindHoushi==1||P.SysTaii==2&&Has(TEXT("Oral_Idle"));
}
bool UOKHScenePanel::PregnantKnows() const{
    const TSharedPtr<FJsonObject>* P=nullptr;bool Pregnant=false,Knows=false;
    if(Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetObjectField(TEXT("pregnancy"),P)){(*P)->TryGetBoolField(TEXT("pregnant"),Pregnant);(*P)->TryGetBoolField(TEXT("knows"),Knows);}
    return Pregnant&&Knows;
}
// His condoms (his bag, the street's his_condoms) or hers (hexp her_condoms) not yet put on this scene.
int32 UOKHScenePanel::CondomsLeft(bool bHers) const{
    double N=0;if(Gallery&&Gallery->HExperience.IsValid())Gallery->HExperience->TryGetNumberField(bHers?TEXT("her_condoms"):TEXT("his_condoms"),N);
    return FMath::Max(0,int32(N)-(bHers?CondomsHer:CondomsHis));
}
void UOKHScenePanel::PutCondomOn(){bCondomHers=CondomsLeft(false)<=0;++(bCondomHers?CondomsHer:CondomsHis);bCondom=bCondomFresh=true;bCondomSpent=false;}
// She takes it in her mouth and rolls it on him, past 100 favor; false when she does not (he puts it on himself).
bool UOKHScenePanel::StartCondomMouth(){
    double Favor=0.;if(!Gallery||!Gallery->HExperience.IsValid()||!Gallery->HExperience->TryGetNumberField(TEXT("favor"),Favor)||Favor<=CVarHCondomMouthFavor.GetValueOnGameThread())return false;
    TArray<int32> Mouth;for(int32 I=0;I<Poses.Num();++I)if(Poses[I].Mode==1&&Poses[I].KindHoushi==1&&!Poses[I].Raw.Contains(TEXT("玉舐め")))Mouth.Add(I); // licking his balls puts nothing on
    if(Mouth.IsEmpty())return false;
    const int32 Found=Mouth[FMath::RandHelper(Mouth.Num())]; // any of them (user 2026-11-04: all kinds of ways)
    const int32 From=ActivePose;SelectPose(Found);if(PendingPose!=Found)return false;
    CondomMouthFrom=From;CondomMouthPose=Found;CondomMouthAt=0.;
    return true;
}
// Out of her once it has been in her (user 2026-11-03: used is used, whether he came or not): the condom comes off and the
// next time needs a new one; with none left he says so (AskNoCondoms).
void UOKHScenePanel::DropSpentCondom(){
    if(bCondom&&!bCondomFresh)bCondomSpent=true;
    if(!bCondomSpent)return;
    bCondom=bCondomSpent=bCondomFresh=false;ActionsKey.Reset();
    if(Mode==2&&CondomsLeft(false)+CondomsLeft(true)<=0)AskNoCondoms();
}
// He tells her there are no condoms (his line, so the H judge reads her answer); once a scene.
void UOKHScenePanel::AskNoCondoms(){
    if(bNoCondomAsked)return;bNoCondomAsked=true;
    Note(OKT(TEXT("ui.hscene.condoms_out")),false);
    if(Gallery)Gallery->NoteAction(TEXT("said"),OKT(TEXT("ui.hscene.ask_no_condoms")));
    Outbox.Add({OKT(TEXT("ui.hscene.ask_no_condoms")),OKT(TEXT("ui.hscene.no_condoms_note"))});
}
void UOKHScenePanel::Finish(const TCHAR* Kind){
    const FString K=Kind;++LineEpoch;
    JustCameAt=FPlatformTime::Seconds();JustCame=K.StartsWith(TEXT("org"))?1:K.StartsWith(TEXT("same"))?2:0;
    if(Mode==1){
        ++ServiceFinishes;++HisFinishes;His=0.f;const float OralBefore=Dev(TEXT("oral"));
        // In her mouth only for a mouth pose: on her chest or in her hand is outside her (not swallowed or spat).
        if(K==TEXT("inside")&&FinishInMouth())++HisMouth;else ++HisOutside;
        if(K==TEXT("inside")){const int32 Kind=FinishInMouth()?1:Poses[ActivePose].KindHoushi;
            // In her mouth: she holds it, then swallows or spits (Oral_Idle). On her chest or in her hand there is nothing to
            // swallow: the finish, then the after state (IN_A, or OUT_A where the pose has none).
            if(Kind==1){Chain({TEXT("IN_Start"),TEXT("IN_Loop"),TEXT("Oral_Idle_IN"),TEXT("Oral_Idle")});OralIdleSince=0.;}
            else Chain({TEXT("IN_Start"),TEXT("IN_Loop"),Has(TEXT("IN_A"))?TEXT("IN_A"):TEXT("OUT_A")});
            if(Kind==2)AddSiru(1); // on her chest
            if(Kind!=1)Spurt(5); // in her hand or between her breasts (in her mouth it stays in it)
            // A foot job (足コキ, a hand service in the original) ends on her feet, not in her hand.
            const bool Feet=Kind==0&&Poses.IsValidIndex(ActivePose)&&Poses[ActivePose].Raw.Contains(TEXT("足コキ"));
            const FString Event=OKT(Kind==1?TEXT("ui.hscene.event_service_inside"):Kind==2?TEXT("ui.hscene.event_service_chest"):Feet?TEXT("ui.hscene.event_service_feet"):TEXT("ui.hscene.event_service_hand"))+OKDevStep(TEXT("oral"),OralBefore,Dev(TEXT("oral")));
            // In her mouth: he picks swallow or spit next, so her line now must not say she already did either.
            if(Kind==1){Note(Event,false);React(Event,OKT(TEXT("ui.hscene.mouth_full_note")));}else Note(Event);}
        else{const bool Mouth=Poses.IsValidIndex(ActivePose)&&FinishInMouth();Chain({TEXT("M_OUT_Start"),TEXT("M_OUT_Loop"),TEXT("OUT_A")});AddSiru(Mouth?0:1);Spurt(5);
            // Out of her mouth it lands on her face (she said "my mouth is full" to a plain "outside").
            Note(OKT(Mouth?TEXT("ui.hscene.event_service_face"):TEXT("ui.hscene.event_service_outside")));}
        return;
    }
    const bool Org=K.StartsWith(TEXT("org")),Same=K.StartsWith(TEXT("same"));
    const TCHAR* DevArea=bAnalPlay?TEXT("anal"):TEXT("crotch");const float DevBefore=Dev(DevArea);
    // Only a climax with him in her opens that place (H_DEVELOPMENT_EXPERIENCE_PLAN: 每在陰道／肛門內高潮一次), not one
    // from his fingers.
    if(Org||Same){if(Mode==2)++(bAnalPlay?AnalClimaxes:CrotchClimaxes);Her=0.f;}
    if(Same||K==TEXT("inside")||K==TEXT("outside")){++HisFinishes;His=0.f;++(K==TEXT("outside")?HisOutside:HisInside);if(Mode==2){if(bCondom){++HisCondom;bCondomSpent=true;}else if(K!=TEXT("outside")){++HisInsideRaw;if(!bAnalPlay)++HisInsideVaginaRaw;}}}
    if(Org||Same){ReleaseHeld();CountHerOrgasm();
        // Her cry as she comes (HSonyu: 325 in the slow loop, 326 in the fast one, from her experience bank; user 2026-11-01:
        // the breathing went on through it). The breathing comes back once she is quiet (bTalkSpoken).
        auto* Girl=Gallery->PreviewActor.Get();const int32 PairIndex=Gallery->PairCombo?Gallery->PairCombo->GetSelectedIndex()-1:-1;
        const int32 AnimId=Gallery->NativePairs.IsValidIndex(PairIndex)?int32(Gallery->NativePairs[PairIndex]->GetNumberField(TEXT("id"))):-1;
        TArray<FKKHBreathCue> Cries;FString Error;
        // User 2026-11-02: no spoken lines in H, only her cries (the breathing goes on through her climax).
        if(CVarHSpokenLines.GetValueOnGameThread()&&IsValid(Girl)&&KKSpeech::CollectHVoice(UOKCharacterController::DefaultVoiceRoot(),Gallery->Selected.Personality,K.EndsWith(TEXT("S"))?26:25,AnimId,Gallery->HBreath,Cries,Error)){
            const FKKHBreathCue& Cry=Cries[FMath::RandHelper(Cries.Num())];Girl->StopHBreath();
            if(Girl->PlaySpeechFile(Cry.Path,FMath::Lerp(.94f,1.06f,Gallery->Selected.VoiceRate),Error)){bTalkSpoken=true;ClimaxUntil=FPlatformTime::Seconds()+4.;UE_LOG(LogTemp,Display,TEXT("H scene: her climax cry %s"),*Cry.Name);}}
        if(!Error.IsEmpty())UE_LOG(LogTemp,Display,TEXT("H scene: no climax cry: %s"),*Error);
        ClimaxUntil=FMath::Max(ClimaxUntil,FPlatformTime::Seconds()+3.);
        // Developed there, she comes twice as long; her developed nipples spray six seconds more (H_DEVELOPMENT_EXPERIENCE_PLAN).
        if(Org||Same){const double Now=FPlatformTime::Seconds();ClimaxUntil=Now+(ClimaxUntil-Now)*(1.f+(Mode==2?Dev(bAnalPlay?TEXT("anal"):TEXT("crotch")):0.f));
            ClimaxLoopFor=ClimaxUntil-Now;}}
    bInsideFinished=Same||K==TEXT("inside");
    if(K==TEXT("outside")){AddSiru(SiruSide()==0?1:3);Spurt(6);} // over the side of her he is on
    else if(Mode==2&&(Same||K==TEXT("inside"))&&!bCondom){++LeakPending;bLeakAnal=bAnalPlay;}
    else if((Same||K==TEXT("inside"))&&!bCondom)AddSiru(bAnalPlay?4:2);
    TArray<FString> States={P(TEXT("OLoop"))};
    if(K==TEXT("outside"))States.Append({P(TEXT("M_OUT_Start")),P(TEXT("M_OUT_Loop")),P(TEXT("OUT_A"))});
    else if(K==TEXT("inside"))States.Append({P(TEXT("M_IN_Start")),P(TEXT("M_IN_Loop")),P(TEXT("IN_A"))});
    else if(K==TEXT("orgW"))States.Append({P(TEXT("WF_IN_Start")),P(TEXT("WF_IN_Loop")),P(TEXT("WS_IN_A"))});
    else if(K==TEXT("sameW"))States.Append({P(TEXT("WS_IN_Start")),P(TEXT("WS_IN_Loop")),P(TEXT("WS_IN_A"))});
    else if(K==TEXT("orgS"))States.Append({P(TEXT("SF_IN_Start")),P(TEXT("SF_IN_Loop")),P(TEXT("SS_IN_A"))});
    else States.Append({P(TEXT("SS_IN_Start")),P(TEXT("SS_IN_Loop")),P(TEXT("SS_IN_A"))});
    Chain(States);
    const FString Event=OKT(Org?TEXT("ui.hscene.event_her_orgasm"):Same?TEXT("ui.hscene.event_together"):K==TEXT("inside")?(bCondom?TEXT("ui.hscene.event_inside_condom"):TEXT("ui.hscene.event_inside")):TEXT("ui.hscene.event_outside"))+OKDevStep(DevArea,DevBefore,Dev(DevArea));
    // In a condom it stays in the condom: her line must not feel it flowing into her.
    if(!Org&&bInsideFinished&&bCondom){Note(Event,false);React(Event,OKT(TEXT("ui.hscene.condom_finish_note")));}else Note(Event);
}

// Her service_rounds for the scene (hexp.rs, with what she already did today) are used up: she will not start another
// hand, mouth or breast round, whether he asks once more or picks a new pose.
static bool OKHServiceSpent(int32 Finishes,const TSharedPtr<FJsonObject>& X){
 return Finishes+(X.IsValid()&&X->HasField(TEXT("today_service"))?int32(X->GetNumberField(TEXT("today_service"))):0)>=FMath::Max(1,X.IsValid()?int32(X->GetNumberField(TEXT("service_rounds"))):2);
}
void UOKHScenePanel::Click(int32 Kind){
    if(Kind==SettingsToggle||Kind==SettingsReset){
        if(Kind==SettingsToggle){bSettingsOpen=!bSettingsOpen;if(SettingsBox)SettingsBox->SetVisibility(bSettingsOpen?ESlateVisibility::Visible:ESlateVisibility::Collapsed);}
        else{for(const FHSetting& S:HSettings)if(S.Var)HSettingSet(S.Var,S.Default);HSettingsSave();}
        for(UOKHSettingSlider* Slider:SettingSliders)if(Slider)Slider->Show();
        return;}
    if(!Gallery)return;
    // Done (H_SCENE_ADDITIONS_PLAN 12): she lies with him (the caress on her back, him out of the picture as in a
    // caress) and they talk; any other action is the scene going on again.
    if(Kind==Afterglow){const int32 Lying=AibuPoses.IndexOfByPredicate([](const FAibuPose& P){return P.Id==1;});
        if(!bAibuLoaded)LoadAibuPoses();const int32 At=Lying!=INDEX_NONE?Lying:AibuPoses.IndexOfByPredicate([](const FAibuPose& P){return P.Id==1;});
        bAfterglow=true;if(At!=INDEX_NONE)SelectAibu(At);else{Note(OKT(TEXT("ui.hscene.event_afterglow")));if(Hint)Hint->SetText(FText::FromString(OKT(TEXT("ui.hscene.afterglow_hint"))));}
        return;}
    if(Kind<TabHand||Kind>TabAibu)bAfterglow=false;
    const FString Base=Mode==0?Current():HBase(Current());
    if(Kind>=TabHand&&Kind<=TabAibu){Tab=Kind;BuildList();return;}
    if(Kind>=PoseBase&&Kind<PoseBase+1000){SelectPose(Kind-PoseBase);return;}
    if(Kind>=AibuBase&&Kind<PoseBase){SelectAibu(Kind-AibuBase);return;}
    if(Kind>=RoomBase&&Kind<=RoomBase+1){Room=Kind-RoomBase;PropKey.Reset();Note(OKT(Room==1?TEXT("ui.hscene.event_room_bed"):TEXT("ui.hscene.event_room_floor")),false);BuildList();return;}
    if(Kind>=TouchChest&&Kind<=Kiss&&Mode==0){static const int32 Areas[]={1,2,3,4,5,0};bLipsTouch=false;Touch(Areas[Kind-TouchChest]);ActionsKey.Reset();return;}
    if(Kind>=TouchHead&&Kind<=TouchFoot&&Mode==0){Touch(6+Kind-TouchHead);ActionsKey.Reset();return;}
    if(Kind==TouchLips&&Mode==0){bLipsTouch=true;Touch(0);ActionsKey.Reset();return;}
    if(Kind==LickToggle&&Mode==0){bLickMode=!bLickMode;ActionsKey.Reset();return;}
    if(Mode==0&&Kind>=Faster&&Kind<=Continue)return; // pair actions while caressing (a stale button or the control channel)
    // An action counts only when the panel offers it now (finishing outside at an empty gauge, inserting during a
    // service): the same rule for a click, a stale button and the control channel.
    if((Kind>=Faster&&Kind<=Continue)||(Kind>=TouchChest&&Kind<=Release)){BuildActions();if(!Offered.Contains(Kind)){UE_LOG(LogTemp,Display,TEXT("H scene: action %d not offered now"),Kind);return;}}
    // Insertion and the condom belong to intercourse poses, anal to the ones that allow it (a stale button or the channel).
    if((Kind==Insert||Kind==InsertAnal||Kind==Condom||Kind==Pull)&&Mode!=2)return;
    if(Kind==InsertAnal&&!(Poses.IsValidIndex(ActivePose)&&Poses[ActivePose].Anal))return;
    if(Kind==LockHer){bLockHer=!bLockHer;ActionsKey.Reset();return;}
    if(Kind==LockHis){bLockHis=!bLockHis;ActionsKey.Reset();return;}
    if((Kind==ToggleMale||Kind==MaleBottom)&&Mode==0)return; // he is not there in a caress
    if(Kind==GrayRoomToggle){SetGrayRoom(!bGrayRoom);ActionsKey.Reset();return;}
    if(Kind==PenisPanelToggle){bPenisPanel=!bPenisPanel;if(PenisBox)PenisBox->SetVisibility(bPenisPanel?ESlateVisibility::Visible:ESlateVisibility::Collapsed);ActionsKey.Reset();return;}
    if(Kind==PenisReset){SetPenis(1.f,1.f);SetRootPad(FVector2D::ZeroVector);return;}
    if(Kind==PhysicsNext){UComboBoxString* Combo=Gallery?Gallery->PhysicsBackendCombo.Get():nullptr;
        if(Combo&&Combo->GetOptionCount()>0){Combo->SetSelectedIndex((Combo->GetSelectedIndex()+1)%Combo->GetOptionCount());
            Gallery->OnPhysicsBackendSelected(Combo->GetSelectedOption(),ESelectInfo::OnMouseClick);
            UE_LOG(LogTemp,Display,TEXT("H scene: physics %s"),*Combo->GetSelectedOption());}
        ActionsKey.Reset();return;}
    if(Kind==PenisXRayToggle){bPenisXRay=!bPenisXRay;ApplyMaleLook();ActionsKey.Reset();return;}
    if(Kind==ToggleMale){MaleView=(MaleView+1)%3;bMaleHidden=MaleView==2;ApplyMaleLook();BuildList();return;}
    if(Kind==MaleBottom){bMaleBottomOff=!bMaleBottomOff;ApplyMaleLook();BuildList();return;}
    if(Kind==Release&&Mode==0){TouchArea=INDEX_NONE;Chain({TEXT("Idle")});ActionsKey.Reset();return;}
    if(Kind==CoordinateToggle){bCoordinateList=!bCoordinateList;if(bCoordinateList){FindCoordinateCards();if(bSettingsOpen)Click(SettingsToggle);}ShowCoordinates();BuildList();return;}
    if(Kind==HeadCameraToggle){bHeadCamera=!bHeadCamera;HeadCameraGirl=nullptr;ActionsKey.Reset();return;}
    if(Kind==EyesCameraToggle){const bool On=!HEyesOnCamera();HSettingSet(TEXT("EyesCamera"),On?1.f:0.f);HSettingsSave();for(UOKHSettingSlider* Slider:SettingSliders)if(Slider)Slider->Show();
        // The ahegao holds her eyes up and gives back what it found: what it gives back changes.
        if(bAhegaoShown){bAheEyeLook=bAheEyeFollow=On;AheEyePattern=1;}
        else{if(Gallery->EyeLookCameraCheck)Gallery->EyeLookCameraCheck->SetIsChecked(On);Gallery->OnEyeLookCamera(On);}
        ActionsKey.Reset();return;}
    if(Kind==CoordinateAccessories){bCoordinateAccessories=!bCoordinateAccessories;ShowAccessories();BuildList();return;}
    if(Kind>=OutfitBase&&Kind<OutfitBase+10){const int32 Outfit=Kind-OutfitBase;const FOutfitGap* Gap=OutfitGaps.Find(Outfit);
        if(Gap&&Gap->bSevere&&OutfitWarned!=Outfit){OutfitWarned=Outfit;if(Hint)Hint->SetText(FText::FromString(OKMsg(TEXT("ui.hscene.outfit_gap_warn"),{{TEXT("count"),Gap->Count}})));return;}
        OutfitWarned=INDEX_NONE;FString Why;if(!WearOutfit(Outfit,FString(),Why)&&Hint)Hint->SetText(FText::FromString(Why));return;}
    if(Kind>=CoordinateBase){FString Why;if(CoordinateCards.IsValidIndex(Kind-CoordinateBase)&&!WearOutfit(Gallery->OutfitIndex,CoordinateCards[Kind-CoordinateBase],Why)&&Hint)Hint->SetText(FText::FromString(Why));return;}
    if(Kind>=ClothesBase){
        auto* Girl=Gallery->PreviewActor.Get();const int32 C=Kind-ClothesBase;if(!IsValid(Girl))return;
        static const TCHAR* Parts[]={TEXT("ui.hscene.cloth_top"),TEXT("ui.hscene.cloth_bottom"),TEXT("ui.hscene.cloth_bra"),TEXT("ui.hscene.cloth_shorts"),TEXT("ui.hscene.cloth_gloves"),TEXT("ui.hscene.cloth_pantyhose"),TEXT("ui.hscene.cloth_socks"),TEXT("ui.hscene.cloth_inner_shoes"),TEXT("ui.hscene.cloth_shoes")};
        uint8* S=Gallery->ClothesStates;FString Event;
        // A piece goes on, half off (where it has a half), off, as the original's buttons (user, 2026-11-02: one press took
        // it all off). Off is visibility; a state she is not opened in (half off, back on from half) opens her again in it.
        uint8 Next[9];FMemory::Memcpy(Next,S,9);AOKInteractionMode* M=Interaction();
        if(C==100){FMemory::Memzero(Next,9);Event=OKT(TEXT("ui.hscene.event_dressed"));}
        else if(C==102){FMemory::Memset(Next,3,9);Event=OKT(TEXT("ui.hscene.event_undressed"));}
        // Each piece's half state, as one press takes it from on; a piece with none stays as it is. The rule goes by her
        // clothes now, so they count as all on while it is asked.
        else if(C==101){uint8 Was[9];FMemory::Memcpy(Was,S,9);FMemory::Memzero(S,9);
            for(int32 K=0;K<9;++K){uint8 Press[9];FString Why;if(M&&Girl->HasClothingKind(K)&&Girl->DisplayClothesStates[K]!=3&&M->ClothesTransition(K,Press,Why)&&Press[K]!=0&&Press[K]!=3)Next[K]=Press[K];}
            FMemory::Memcpy(S,Was,9);Event=OKT(TEXT("ui.hscene.event_half_undressed"));}
        else if(C>=0&&C<9){FString Why;if(!M||!M->ClothesTransition(C,Next,Why)){UE_LOG(LogTemp,Warning,TEXT("H scene: clothes rule: %s"),*Why);Next[C]=S[C]!=3?3:0;}
            Event=OKMsg(Next[C]==3?TEXT("ui.hscene.event_part_off"):Next[C]==0?TEXT("ui.hscene.event_part_on"):TEXT("ui.hscene.event_part_half"),{{TEXT("part"),OKT(Parts[C])}});}
        else return;
        bool Shown=true;for(int32 K=0;K<9;++K)Shown&=Next[K]==3||Next[K]==Girl->DisplayClothesStates[K];
        if(!Shown){if(!M||!M->ChangeClothesStates(Next)){if(Hint)Hint->SetText(FText::FromString(OKT(TEXT("ui.hscene.outfit_busy"))));return;}
            FMemory::Memcpy(S,Next,9);Gallery->RefreshClothesStateLabels();Note(Event);BuildList();return;}
        FMemory::Memcpy(S,Next,9);
        Girl->SetClothingPartsHidden(S);Gallery->RefreshClothesStateLabels();Note(Event);BuildList();return;
    }
    const auto& X=Gallery->HExperience;
    switch(Kind){
    case Faster:
        // From a standstill the button only starts them moving (start, move); faster only once moving.
        if(HIsLoop(Base)){SpeedValue=FMath::Min(1.f,SpeedValue+.15f);if(Speed)Speed->SetValue(SpeedValue);}
        if(Mode==1&&(Base==TEXT("Idle")||Base==TEXT("Stop_Idle")||Base.EndsWith(TEXT("_A"))))Want(TEXT("WLoop"));
        else if(Mode==2&&Base==TEXT("InsertIdle"))Want(P(TEXT("WLoop")));
        break;
    case Slower:
        SpeedValue=FMath::Max(0.f,SpeedValue-.15f);if(Speed)Speed->SetValue(SpeedValue);
        if(Mode==2&&SpeedValue<=0.f&&HIsLoop(Base))Want(P(TEXT("InsertIdle")));
        break;
    case Toggle:if(HIsLoop(Base)){bStrong=Base==TEXT("WLoop");Want(P(bStrong?TEXT("SLoop"):TEXT("WLoop")));}break;
    case Stop:Want(Mode==1?(Has(TEXT("Stop_Idle"))?TEXT("Stop_Idle"):TEXT("Idle")):P(TEXT("InsertIdle")));break;
    case Inside:Finish(Mode==2&&Her>=70.f&&!bLockHer?(bStrong?TEXT("sameS"):TEXT("sameW")):TEXT("inside"));break; // with her gauge locked she does not come with him
    case Outside:Finish(TEXT("outside"));break;
    case Drink:++Swallowed;Chain({TEXT("Drink_IN"),TEXT("Drink"),TEXT("Drink_A")});Note(OKT(TEXT("ui.hscene.event_drink")));break;
    case Vomit:Chain({TEXT("Vomit_IN"),TEXT("Vomit"),TEXT("Vomit_A")});AddSiru(0);MouthSpillUntil=FPlatformTime::Seconds()+4.;Note(OKT(TEXT("ui.hscene.event_vomit")));break; // spat out: on her mouth and chin
    case Again:
        // Once more only while she is willing: past her service_rounds for the scene she says no (and the panel stops offering it).
        if(OKHServiceSpent(ServiceFinishes,X)){bServiceRefused=true;Note(OKT(TEXT("ui.hscene.again_refused")));BuildList();break;}
        Want(TEXT("WLoop"));bStrong=false;break;
    case Condom:
        // Taken off before it was in her: back in the box.
        if(bCondom){if(bCondomFresh)--(bCondomHers?CondomsHer:CondomsHis);bCondom=bCondomFresh=bCondomSpent=false;Note(OKT(TEXT("ui.hscene.condom_off")),false);break;}
        // His first, else one of hers she hands him; with none she says what she makes of it (go and buy some, or not).
        if(CondomsLeft(false)>0||CondomsLeft(true)>0){if(StartCondomMouth())break;PutCondomOn();
            Note(OKT(bCondomHers?TEXT("ui.hscene.condom_hers"):TEXT("ui.hscene.condom_on")),false);break;}
        if(bNoCondomAsked){const FString Event=OKT(TEXT("ui.hscene.condom_none"));Note(Event,false);React(Event,OKT(TEXT("ui.hscene.condom_none_note")));}else AskNoCondoms();break;
    case Insert:
        // Raw only when she lets him (NamaInsertCheck): otherwise she has him put one on (the original's voice 302).
        if(!bCondom&&!bRawPressed&&!(X.IsValid()&&X->GetBoolField(TEXT("raw_ok")))&&RawLet<=0){
            // Pregnant and she knows: he asks her first, and a yes (the H judge) lets him.
            if(PregnantKnows()&&RawLet==0&&!bRawAskedPregnant){bRawAskedPregnant=true;Note(OKT(TEXT("ui.hscene.asked_raw_pregnant")),false);Say(OKT(TEXT("ui.hscene.ask_raw_pregnant")));break;}
            if(RawLet==0&&!bRawAsked){bRawAsked=true;
                if(PregnantKnows())Note(OKT(TEXT("ui.hscene.raw_answer_waiting")),false);
                else if(CondomsLeft(false)+CondomsLeft(true)>0)Note(OKT(TEXT("ui.hscene.wants_condom")));else if(bNoCondomAsked)Note(OKT(TEXT("ui.hscene.wants_condom_none")));else AskNoCondoms();
                break;}
            // Once she has said no he can still have it his way (user 2026-11-04): it costs 1 to 5 favor (hexp, raw_pressed).
            bRawPressed=true;Note(OKT(TEXT("ui.hscene.raw_after_asking")));}
        // Her line as he enters her (HSonyu 307, user 2026-11-01: a virgin, an unused, a used and a lewd girl each say
        // their own): the bank is her experience, the first one until she has had it there (GetStateSelect).
        bCondomFresh=false;bAnalPlay=false;Chain({TEXT("Insert"),TEXT("InsertIdle")});PlayHVoice(7);Note(OKT(bCondom?TEXT("ui.hscene.event_insert"):TEXT("ui.hscene.event_insert_raw")),false);break;
    case InsertAnal:{
        // Asked once a scene: her anal experience is the chance she agrees (isAnalInsertOK), more for a lover or a lewd girl.
        // Already said no today (another scene): still no, not asked again.
        if(!bAnalAsked&&X.IsValid()&&X->HasField(TEXT("anal_refused_today"))&&X->GetBoolField(TEXT("anal_refused_today"))){bAnalAsked=true;bAnalRefused=true;}
        if(!bAnalAsked){bAnalAsked=true;float Chance=X.IsValid()?float(X->GetNumberField(TEXT("anal_chance"))):0.f;if(Level()>=3)Chance=1.f;if(Gallery->HHeroineStage==TEXT("lover"))Chance+=.3f;
            const bool Resentful=X.IsValid()&&X->HasField(TEXT("resentful"))&&X->GetBoolField(TEXT("resentful")); // she resents him: no
            bAnalRefused=Resentful||FMath::FRand()>=FMath::Max(Chance,.1f);}
        if(bAnalRefused){Note(OKT(TEXT("ui.hscene.anal_refused")));break;}
        bCondomFresh=false;bAnalPlay=true;Chain({TEXT("A_Insert"),TEXT("A_InsertIdle")});PlayHVoice(7);Note(OKT(TEXT("ui.hscene.event_insert_anal")),false);break;}
    case Pull:
        if(HBase(Current())==TEXT("InsertIdle"))PlayHVoice(bAnalPlay?6:3); // HSonyu: pulled out while still, 303 / 306
        if(bInsideFinished)Chain({P(TEXT("Pull")),P(TEXT("Drop")),P(TEXT("OUT_A"))});else Chain({P(TEXT("Pull")),P(TEXT("Idle"))});
        if(Queue.IsEmpty())Want(P(TEXT("Idle")));
        bInsideFinished=false;DropSpentCondom();break;
    case Continue:
        // One condom for each time he comes (user 2026-11-03): going on in her after coming in one takes a new one, his
        // first, else hers; with none left he does not go on in the used one.
        if(bCondomSpent){
            // None left and she said do it without: the used one comes off and he goes on in her bare. Past her no he still
            // can, as at Insert.
            const bool bNoneLeft=CondomsLeft(false)+CondomsLeft(true)<=0;
            const bool bRawOk=RawLet>0||bRawPressed||(X.IsValid()&&X->GetBoolField(TEXT("raw_ok")));
            if(bNoneLeft&&(bRawOk||(bNoCondomAsked&&(RawLet<0||bRawAsked)))){if(!bRawOk)bRawPressed=true;bRaw=true;
                bCondom=bCondomSpent=bCondomFresh=false;Note(OKT(bRawOk?TEXT("ui.hscene.condom_off_go_raw"):TEXT("ui.hscene.raw_after_asking")),false);Want(P(TEXT("InsertIdle")));break;}
            if(bNoneLeft){if(bNoCondomAsked){bRawAsked=true;Note(OKT(TEXT("ui.hscene.condom_none_more")));}else AskNoCondoms();break;}
            bCondomHers=CondomsLeft(false)<=0;++(bCondomHers?CondomsHer:CondomsHis);bCondomSpent=bCondomFresh=false;
            Note(OKT(bCondomHers?TEXT("ui.hscene.condom_new_hers"):TEXT("ui.hscene.condom_new")),false);}
        Want(P(TEXT("InsertIdle")));break;
    default:break;
    }
    ActionsKey.Reset();
}

// Breast service is done bare: through her top and bra his penis went in and out of the cloth. Off with them, as she
// would (only those two; a part already off stays as it is).
void UOKHScenePanel::BareChest(){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return;
    uint8* S=Gallery->ClothesStates;bool Changed=false;
    for(const int32 C:{0,2})if(S[C]!=3){S[C]=3;Changed=true;}
    if(!Changed)return;
    Girl->SetClothingPartsHidden(S);Gallery->RefreshClothesStateLabels();Note(OKT(TEXT("ui.hscene.event_chest_bared")),false);
}
// Worn out (her climaxes today reached her limit) she says so and looks tired, but they can go on (user, 2026-11-01:
// past ten a day each climax raises her libido, hexp.rs).
namespace {
struct FOKHSound{FString Anim;float Key=0.f;FString Clip;};
// h/se.json (ok-extract --oklib h-sounds): "AnimationInfo_XX:id" → its pose's one-shot sounds (no pair pose has a loop).
const TMap<FString,TArray<FOKHSound>>& OKHSounds(){
    static TMap<FString,TArray<FOKHSound>> Table;static bool bLoaded=false;if(bLoaded)return Table;bLoaded=true;
    const FString Lib=AOKSceneActor::LibraryDirectory();FString Text;TSharedPtr<FJsonObject> Root;const TSharedPtr<FJsonObject>* Files=nullptr;
    if(!FFileHelper::LoadFileToString(Text,*(Lib/TEXT("h/se.json")))||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Root)||!Root||!Root->TryGetObjectField(TEXT("files"),Files)){
        UE_LOG(LogTemp,Warning,TEXT("H scene: no sound table %s (ok-extract --oklib h-sounds)"),*(Lib/TEXT("h/se.json")));return Table;}
    for(const TSharedPtr<FJsonValue>& V:Root->GetArrayField(TEXT("poses"))){const TSharedPtr<FJsonObject> P=V->AsObject();const TArray<TSharedPtr<FJsonValue>>* Rows=nullptr;
        if(!P||!(*Files)->TryGetArrayField(P->GetStringField(TEXT("file")),Rows))continue;
        TArray<FOKHSound>& Out=Table.Add(FString::Printf(TEXT("AnimationInfo_%02d:%d"),int32(P->GetNumberField(TEXT("m"))),int32(P->GetNumberField(TEXT("id")))));
        for(const TSharedPtr<FJsonValue>& R:*Rows){const TSharedPtr<FJsonObject> O=R->AsObject();if(!O||O->GetBoolField(TEXT("loop")))continue;
            const FString Clip=Lib/TEXT("h/se")/O->GetStringField(TEXT("se"))+TEXT(".ogg");if(!FPaths::FileExists(Clip))continue;
            Out.Add({O->GetStringField(TEXT("anim")),float(O->GetNumberField(TEXT("key"))),Clip});}}
    return Table;
}
}
// HSeCtrl.Proc: the state's normalized time (its fraction) against the last frame's; a new state starts from 0, so a
// key of 0 plays as it begins.
void UOKHScenePanel::TickSounds(){
    AKKPairedPlayback* Playback=Gallery->PairedPlayback.Get();const AKKPreviewActor* Girl=Gallery->PreviewActor.Get();
    if(Mode==0||!Playback||!IsValid(Girl)||!Poses.IsValidIndex(ActivePose)||!Gallery->NativePairs.IsValidIndex(Poses[ActivePose].Pair)){SoundState.Reset();return;}
    const TSharedPtr<FJsonObject>& Row=Gallery->NativePairs[Poses[ActivePose].Pair];
    const TArray<FOKHSound>* Sounds=OKHSounds().Find(FString::Printf(TEXT("%s:%d"),*Row->GetStringField(TEXT("category")),int32(Row->GetNumberField(TEXT("id")))));
    const FString State=Current();const float Now=FMath::Frac(Playback->GetElapsed()/FMath::Max(.05f,Girl->AnimDuration));
    if(State!=SoundState){SoundState=State;SoundTime=0.f;}
    if(Sounds&&!Playback->IsPaused()&&Playback->GetElapsed()>0.f)for(const FOKHSound& S:*Sounds)
        if(S.Anim==State&&(SoundTime>Now?SoundTime<S.Key||Now>S.Key:SoundTime<=S.Key&&S.Key<Now))PlaySe(S.Clip);
    SoundTime=Now;
}
void UOKHScenePanel::PlaySe(const FString& Clip){
    static TMap<FString,TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe>> Decoded;
    TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe>& Pcm=Decoded.FindOrAdd(Clip);FString Error;
    const bool bFirst=!Pcm;
    if(!Pcm&&!KKSpeech::DecodeOgg(Clip,Pcm,Error)){UE_LOG(LogTemp,Warning,TEXT("H scene: sound %s: %s"),*Clip,*Error);return;}
    if(bFirst)UE_LOG(LogTemp,Display,TEXT("H scene: sound %s (%s)"),*FPaths::GetBaseFilename(Clip),*SoundState);
    UWorld* World=GetWorld();if(!World||!World->GetAudioDevice().IsValid())return;
    UKKSpeechWave* Wave=NewObject<UKKSpeechWave>(this);Wave->Init(Pcm,World->GetAudioDevice()->GetSampleRate());
    // Kept referenced while they play (the last few; none of the sounds is longer than a second or two).
    SoundsPlaying.Add(Wave);if(SoundsPlaying.Num()>8)SoundsPlaying.RemoveAt(0);
    UGameplayStatics::PlaySound2D(this,Wave);
}
bool UOKHScenePanel::PlayHVoice(int32 Row){
    if(!CVarHSpokenLines.GetValueOnGameThread())return false; // only her cries (user 2026-11-02): the breathing goes on
    AKKPreviewActor* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||!Poses.IsValidIndex(ActivePose))return false;
    const FOKHPose& Pose=Poses[ActivePose];const int32 AnimId=Gallery->NativePairs.IsValidIndex(Pose.Pair)?int32(Gallery->NativePairs[Pose.Pair]->GetNumberField(TEXT("id"))):-1;
    TArray<FKKHBreathCue> Lines;FString Error;FKKHBreathContext Context=Gallery->HBreath;Context.bAnal=bAnalPlay;Context.bCondom=bCondom; // the panel may have just changed them
    if(KKSpeech::CollectHVoice(UOKCharacterController::DefaultVoiceRoot(),Gallery->Selected.Personality,Row+(Pose.FemaleLead?38:0),AnimId,Context,Lines,Error)){
        const FKKHBreathCue& Line=Lines[FMath::RandHelper(Lines.Num())];Girl->StopHBreath();
        if(Girl->PlaySpeechFile(Line.Path,FMath::Lerp(.94f,1.06f,Gallery->Selected.VoiceRate),Error)){bTalkSpoken=true;
            UE_LOG(LogTemp,Display,TEXT("H scene: her line %d (bank %d) %s"),300+Row,Gallery->HBreath.Experience,*Line.Name);return true;}}
    UE_LOG(LogTemp,Display,TEXT("H scene: no line %d: %s"),300+Row,*Error);return false;
}
static TAutoConsoleVariable<int32> CVarHSuckHide(TEXT("ok.HScene.SuckHide"),1,TEXT("The insides of her mouth hidden while she sucks him (her lower face forward): 1 teeth, 2 canines, 4 tongue"));
// Her mouth and lower face pulled out after him as he draws back (H_DEVELOPMENT_EXPERIENCE_PLAN, user 2026-11-02: the horse
// face did not show): face slider index:amount at the most, times how far out he is and how developed her mouth is.
static TAutoConsoleVariable<FString> CVarHSuckPull(TEXT("ok.HScene.SuckPull"),TEXT("4:3,43:1.5,44:1,45:1,10:2.5,12:2.5,7:1.5,42:-1.5"),TEXT("Her face drawn out after him as he draws back: face slider index:amount, comma separated"));
static TAutoConsoleVariable<float> CVarHSuckHideCm(TEXT("ok.HScene.SuckHideCm"),2.f,TEXT("Sucking: his penis this many cm past her lips not drawn (folded back there); 0 all of him drawn"));
static TAutoConsoleVariable<float> CVarHSuckAim(TEXT("ok.HScene.SuckAim"),0.f,TEXT("Sucking: his penis turned this much (0..1) of the way from the clip's line to straight into her mouth"));
static TAutoConsoleVariable<FString> CVarHSuckOpen(TEXT("ok.HScene.SuckOpen"),TEXT("0.55,1"),TEXT("Sucking: her mouth at least this open, at no development and at full (min,max)"));
static TAutoConsoleVariable<float> CVarHSuckPullTest(TEXT("ok.HScene.SuckPullTest"),-1.f,TEXT("Test: her face drawn out this much (0..1) whatever the stroke; -1 off"));
float UOKHScenePanel::Dev(const TCHAR* Area) const{
    if(const float* T=DevTest.Find(Area))return FMath::Clamp(*T/100.f,0.f,1.f);
    const auto& X=Gallery?Gallery->HExperience:nullptr;const TSharedPtr<FJsonObject>* Areas=nullptr;double V=0;
    if(X.IsValid()&&X->TryGetObjectField(TEXT("areas"),Areas))(*Areas)->TryGetNumberField(Area,V);
    const FString A=Area;V+=A==TEXT("crotch")?10.*CrotchClimaxes:A==TEXT("anal")?10.*AnalClimaxes:A==TEXT("oral")?10.*HisMouth:0.;
    return FMath::Clamp(float(V)/100.f,0.f,1.f);
}
// Her pregnancy as her experience carries it (pregnancy.rs view): the belly by stage, and her areolae larger and
// nipples darker by her births and how far along she is (a pregnancy darkens them on its own).
static TSharedPtr<FJsonObject> OKPregnancyOf(const TSharedPtr<FJsonObject>& X){const TSharedPtr<FJsonObject>* P=nullptr;return X.IsValid()&&X->TryGetObjectField(TEXT("pregnancy"),P)?*P:nullptr;}
float UOKHScenePanel::PregBelly() const{
    if(PregBellyTest>=0.f)return FMath::Clamp(PregBellyTest,0.f,1.f);
    const auto P=OKPregnancyOf(Gallery?Gallery->HExperience:nullptr);double V=0;if(P.IsValid())P->TryGetNumberField(TEXT("belly"),V);return FMath::Clamp(float(V),0.f,1.f);
}
float UOKHScenePanel::PregBust() const{
    if(PregBellyTest>=0.f)return .5f*FMath::Clamp(PregBellyTest,0.f,1.f);
    const auto P=OKPregnancyOf(Gallery?Gallery->HExperience:nullptr);double V=0;if(P.IsValid())P->TryGetNumberField(TEXT("bust"),V);return FMath::Clamp(float(V),0.f,.5f);
}
// Lying on her front or pressed down on her belly: not from her 20th week (pregnancy.rs belly_locked).
static TAutoConsoleVariable<FString> CVarHPregLocked(TEXT("ok.HScene.PregLockedPoses"),TEXT("寝バック,伏せ後背位,押し付けバック,種付けプレス,マングリ正常位"),TEXT("Poses (authored names, comma separated) she will not take from her 20th week of pregnancy"));
bool UOKHScenePanel::PregLocks(const FOKHPose& Pose) const{
    const auto P=OKPregnancyOf(Gallery?Gallery->HExperience:nullptr);bool B=false;if(!(P.IsValid()&&P->TryGetBoolField(TEXT("belly_locked"),B)&&B)&&!(PregBellyTest>=.5f))return false;
    TArray<FString> Names;CVarHPregLocked.GetValueOnGameThread().ParseIntoArray(Names,TEXT(","));return Names.Contains(Pose.Raw)||Names.Contains(Pose.Name);
}
float UOKHScenePanel::PregNipples() const{
    if(PregBodyTest>=0.f)return FMath::Clamp(PregBodyTest,0.f,1.f);
    const auto P=OKPregnancyOf(Gallery?Gallery->HExperience:nullptr);double Body=0,Progress=0;if(P.IsValid()){P->TryGetNumberField(TEXT("body"),Body);P->TryGetNumberField(TEXT("progress"),Progress);}
    return FMath::Clamp(FMath::Max(float(Body),.7f*float(Progress)),0.f,1.f);
}
static TAutoConsoleVariable<FString> CVarHPregNipple(TEXT("ok.HScene.PregNipple"),TEXT("0.85,0.42,0.24,0.2"),TEXT("Her areolae and nipples fully changed by pregnancy: areola size, then nipple colour r,g,b"));
// The PregnancyPlus Standard preset (OKPregnancyPresets.h) the belly takes when her card has no shape of its own.
static const TCHAR* OKPregStandard[][2]={{TEXT("inflationMultiplier"),TEXT("0.25")},{TEXT("inflationStretchX"),TEXT("-0.12")},{TEXT("inflationStretchY"),TEXT("-0.07")},{TEXT("inflationTaperY"),TEXT("-0.005")},{TEXT("inflationTaperZ"),TEXT("-0.003")},{TEXT("inflationRoundness"),TEXT("0.005")},{TEXT("inflationDrop"),TEXT("0.05")}};
void UOKHScenePanel::ApplyPregnancy(double Now){
    AKKPreviewActor* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||Now<PregCheckAt)return;PregCheckAt=Now+1.;
    // Areolae and nipples: every second (an outfit change builds her materials again).
    {TArray<FString> V;CVarHPregNipple.GetValueOnGameThread().ParseIntoArray(V,TEXT(","));const float Size=V.Num()>0?FCString::Atof(*V[0]):.85f;
     const FLinearColor To(V.Num()>3?FCString::Atof(*V[1]):.42f,V.Num()>3?FCString::Atof(*V[2]):.24f,V.Num()>3?FCString::Atof(*V[3]):.2f,1.f);
     const float Amount=PregNipples();if(Amount>0.f||!Girl->NippleBase.IsEmpty())Girl->SetNippleChange(Amount,Size,To);}
    // The belly: her body sculpted again only when it changes (or she was built again).
    const float Belly=PregBelly();
    if(PregActor==Girl&&PregOutfit==Gallery->OutfitIndex&&FMath::IsNearlyEqual(Belly,PregBellyShown,.005f))return;
    if(Belly<=0.f&&PregBellyShown<=0.f&&PregActor==Girl){PregOutfit=Gallery->OutfitIndex;return;}
    TSharedPtr<FJsonObject> Mods;if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Gallery->EditorModsJson()),Mods)||!Mods.IsValid())return;
    const TSharedPtr<FJsonObject>* Own=nullptr;TSharedPtr<FJsonObject> P=Mods->TryGetObjectField(TEXT("pregnancy"),Own)?*Own:MakeShared<FJsonObject>();
    double Card=0;P->TryGetNumberField(TEXT("inflationSize"),Card);bool bShaped=P->HasField(TEXT("inflationMultiplier"));
    if(!bShaped)for(const auto& KV:OKPregStandard)P->SetNumberField(KV[0],FCString::Atof(KV[1]));
    P->SetBoolField(TEXT("GameplayEnabled"),true);P->SetNumberField(TEXT("inflationSize"),FMath::Max(Card,40.*Belly));Mods->SetObjectField(TEXT("pregnancy"),P);
    FString Json;FJsonSerializer::Serialize(Mods.ToSharedRef(),TJsonWriterFactory<>::Create(&Json));bool Geometry=false;
    if(!Girl->Session.ApplyEditorMods(Json,Gallery->OutfitIndex,&Geometry)){UE_LOG(LogTemp,Warning,TEXT("H scene: her pregnant belly %.2f not applied"),Belly);return;}
    if(Geometry){const float Phase=Girl->AnimPhase;const int32 PoseMode=Girl->PoseMode;FString Error;if(!Girl->RefreshEditorGeometry())Girl->LoadSession(Error);Girl->AnimPhase=Phase;Girl->PoseMode=PoseMode;
        Girl->ApplyShapes(Gallery->Selected.Face.ShapeValueFace,Gallery->Selected.Body.ShapeValueBody);}
    UE_LOG(LogTemp,Display,TEXT("H scene: her pregnant belly %.2f (size %.1f, geometry %d)"),Belly,FMath::Max(Card,40.*Belly),Geometry?1:0);
    PregBellyShown=Belly;PregActor=Girl;PregOutfit=Gallery->OutfitIndex;
}
void UOKHScenePanel::SwellBust(float Delta){
    AKKPreviewActor* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||Gallery->Selected.Body.ShapeValueBody.Num()<=4)return;
    // Her pregnancy adds to it, half again at term and going back over six months after (pregnancy.rs bust;
    // H_SCENE_ADDITIONS_PLAN 8), at most twice her own.
    const float Want=FMath::Min(2.f,1.f+PregBust()+.5f*Dev(TEXT("chest"))*FMath::Clamp(Her/100.f,0.f,1.f));
    BustSwell=FMath::FInterpTo(BustSwell,Want,Delta,1.5f);
    // Sucking him (set by AlignHim while he is in her mouth): as strong as her mouth is developed.
    OralSuck=FMath::FInterpTo(OralSuck,bSucking?Dev(TEXT("oral")):0.f,Delta,3.f);
    // Her eyes roll up with it (not over her worn-out ahegao, which has its own).
    {const float Gaze=bAhegaoShown?OralGazeSet:OralSuck>.05f?FMath::Min(1.f,1.2f*OralSuck):0.f; // +1 is up (ok.HScene.AhegaoGaze)
     if(!bAhegaoShown&&FMath::Abs(Gaze-OralGazeSet)>.03f){OralGazeSet=Gaze;Girl->SetEyeGaze(0.f,0.f,Gaze);}}
    const bool BustMoved=FMath::Abs(BustSwell-BustSwellSet)>=.01f||(BustSwellSet!=1.f&&FMath::Abs(BustSwell-1.f)<.01f);
    // Her lips hold him and her mouth and lower face are drawn out along him: six tenths all the while she sucks, the
    // rest as he draws back (AlignDeep against her mouth's 10% to her top, AlignHim). Following the stroke alone, the
    // face (rebuilt a few frames late) was longest with him deepest (2026-11-02).
    {const float Top=FMath::Lerp(30.f,60.f,Dev(TEXT("oral")));const float Out=FMath::Clamp((Top-AlignDeep)/FMath::Max(Top-10.f,1.f),0.f,1.f);
     const float Test=CVarHSuckPullTest.GetValueOnGameThread();OralPull=Test>=0.f?Test*OralSuck:FMath::FInterpTo(OralPull,bSucking?OralSuck*(.6f+.4f*Out):0.f,Delta,12.f);}
    const bool FaceMoved=FMath::Abs(OralSuck-OralSuckSet)>=.02f||(OralSuckSet!=0.f&&OralSuck<.02f)||FMath::Abs(OralPull-OralPullSet)>=.03f||(OralPullSet!=0.f&&OralPull<.03f);
    // Her lower face drawn forward that far brought her teeth out through her upper lip (blue at its corners, oral
    // development 100, 2026-11-02): hidden while it is (her lips are round him there).
    Girl->HiddenMouthInside=OralSuck>=.2f?uint8(CVarHSuckHide.GetValueOnGameThread()):0;
    if(!BustMoved&&!FaceMoved)return;
    BustSwellSet=FMath::Abs(BustSwell-1.f)<.01f?1.f:BustSwell;OralSuckSet=OralSuck<.02f?0.f:OralSuck;OralPullSet=OralPull<.03f?0.f:OralPull;
    TArray<float> Body=Gallery->Selected.Body.ShapeValueBody;Body[4]*=BustSwellSet; // cf_a_bust0x_size (ChaFileBody shapeValueBody[4])
    // The face sliders (ChaFileFace shapeValueFace, cf_customhead). Her mouth and cheeks drawn forward by sucking him (user,
    // 2026-11-01: the "horse face" is the mouth and cheeks pulled out after him, not a longer chin): 4 her lower face
    // forward, 44 / 45 her lips out; 7 lower and 16 upper cheeks narrower (hollowed); 42 her mouth a little wider (with
    // ok.HScene.SuckPull's 42 her lips close round him; wider by 1 her lips were stretched into a band over the inside of her
    // mouth with black gaps at its corners, user 2026-11-02: the lips were wrong).
    TArray<float> Face=Gallery->Selected.Face.ShapeValueFace;const float S=OralSuckSet;
    if(Face.Num()>45){Face[4]+=1.2f*S;Face[44]+=1.f*S;Face[45]+=1.f*S;Face[7]-=1.2f*S;Face[16]-=.8f*S;Face[42]+=.5f*S;}
    if(OralPullSet>0.f){TArray<FString> Pairs;CVarHSuckPull.GetValueOnGameThread().ParseIntoArray(Pairs,TEXT(","));
        for(const FString& P:Pairs){FString I,A;if(P.Split(TEXT(":"),&I,&A)){const int32 At=FCString::Atoi(*I);if(Face.IsValidIndex(At))Face[At]+=FCString::Atof(*A)*OralPullSet;}}}
    // Her mouth open round him, the more the more she is developed (her breaths' mouth alone closed on him). Open all the
    // way her upper lip went up off him and showed the inside of her mouth over him (user, 2026-11-02: the lips were wrong).
    {float Lo=.55f,Hi=1.f;FString A,B;if(CVarHSuckOpen.GetValueOnGameThread().Split(TEXT(","),&A,&B)){Lo=FCString::Atof(*A);Hi=FCString::Atof(*B);}
     if(!bDeepFace)Girl->SetMouthOpenFloor(bSucking?FMath::Lerp(Lo,Hi,OralSuck):0.f);}
    Girl->MarkShapeDirty(Face,Body);
}
static bool HBone(AKKPreviewActor* A,const TCHAR* Name,FVector& Out);
// The session part a component of his draws (KKSessionPart_<n>; KKMorphPart_<n> on the renderer that replaces it once the
// part has morphs, his penis with penis.clip): INDEX_NONE for another tag.
static int32 HTagPart(const FString& T){if(T.StartsWith(TEXT("KKSessionPart_")))return FCString::Atoi(*T.Mid(14));if(T.StartsWith(TEXT("KKMorphPart_")))return FCString::Atoi(*T.Mid(12));return INDEX_NONE;}
void UOKHScenePanel::HideWorld(){
    AKKPreviewActor* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||!GetWorld())return;
    // Asked again every second while the room is grey (UOKHScenePanel::NativeTick): the street shows its people again as
    // they walk and new ones come (user, 2026-11-02: a girl stayed in sight beside them).
    // Anyone with a skinned body is hidden, his own street pawn and the people carrying lights too (user, 2026-11-02).
    const TSet<AActor*> Keep={Girl,Gallery->PartnerActor.Get(),Gallery->PairedPlayback.Get()};
    for(TActorIterator<AActor> It(GetWorld());It;++It){AActor* A=*It;
        if(Keep.Contains(A)||GrayRoom.Contains(A)||Props.Contains(Cast<AStaticMeshActor>(A))||A->IsHidden()||Cast<ALight>(A)||Cast<ASkyLight>(A)||Cast<APostProcessVolume>(A)
            ||Cast<ACameraActor>(A)||Cast<AInfo>(A)||Cast<AController>(A)||Cast<APlayerCameraManager>(A)||!A->FindComponentByClass<USkinnedMeshComponent>()&&(Cast<APawn>(A)||A->FindComponentByClass<ULightComponentBase>()))continue; // the street lights them (its sun sits on a plain actor)
        A->SetActorHiddenInGame(true);GrayHidden.AddUnique(A);}
}
void UOKHScenePanel::SetGrayRoom(bool bOn){
    for(const TWeakObjectPtr<AActor>& A:GrayHidden)if(A.IsValid())A->SetActorHiddenInGame(false);GrayHidden.Reset();
    for(AActor* A:GrayRoom)if(IsValid(A))A->Destroy();GrayRoom.Reset();bGrayRoom=false;
    AKKPreviewActor* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!bOn||!IsValid(Girl)||!GetWorld())return;
    static UStaticMesh* Cube=LoadObject<UStaticMesh>(nullptr,TEXT("/Engine/BasicShapes/Cube.Cube"));if(!Cube)return;
    // Unlit (the street may be at night): flat grey whatever its light.
    UMaterialInterface* Shape=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewOpaque.M_PreviewOpaque"),nullptr,LOAD_NoWarn);
    bGrayRoom=true;
    // What stays: the two of them, lights, cameras, the game's own actors and his own pawn; everyone else on the street
    // (the other girls, user 2026-11-02) is hidden with it.
    HideWorld();
    // Ten metres square, five high, round her feet.
    FVector Hips;const FVector C=HBone(Girl,TEXT("j_hips"),Hips)?FVector(Hips.X,Hips.Y,Girl->GetActorLocation().Z):Girl->GetActorLocation();
    const float W=1000.f,H=500.f,T=4.f;
    auto Slab=[&](const FVector& At,const FVector& Size,const FLinearColor& Tint){
        AStaticMeshActor* A=GetWorld()->SpawnActor<AStaticMeshActor>(At,FRotator::ZeroRotator);if(!A)return;
        A->SetMobility(EComponentMobility::Movable);A->GetStaticMeshComponent()->SetStaticMesh(Cube);A->GetStaticMeshComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        if(Shape)if(auto* M=UMaterialInstanceDynamic::Create(Shape,A)){M->SetVectorParameterValue(TEXT("PreviewTint"),Tint);A->GetStaticMeshComponent()->SetMaterial(0,M);}
        A->GetStaticMeshComponent()->SetCastShadow(false);A->SetActorScale3D(Size/100.f);GrayRoom.Add(A);};
    const FLinearColor Wall(.35f,.35f,.35f,1.f);
    // No floor (user, 2026-11-02: it hid them from below).
    Slab(C+FVector(0,0,H),FVector(W,W,T),Wall);
    Slab(C+FVector(W/2,0,H/2),FVector(T,W,H),Wall);Slab(C-FVector(W/2,0,-H/2),FVector(T,W,H),Wall);
    Slab(C+FVector(0,W/2,H/2),FVector(W,T,H),Wall);Slab(C-FVector(0,W/2,-H/2),FVector(W,T,H),Wall);
    UE_LOG(LogTemp,Display,TEXT("H scene: grey room on (%d of the world hidden)"),GrayHidden.Num());
}
void UOKHScenePanel::SetPenisGreen(bool bOn){
    int32 M=0;for(const TWeakObjectPtr<UMeshComponent>& C:GreenComps){if(!C.IsValid()){continue;}for(int32 I=0;I<C->GetNumMaterials()&&M<GreenKept.Num();++I,++M)C->SetMaterial(I,GreenKept[M]);}
    GreenComps.Reset();GreenKept.Reset();bPenisGreen=bOn;
    AKKPreviewActor* Him=Gallery?Gallery->PartnerActor.Get():nullptr;if(!bOn||!IsValid(Him))return;
    UMaterialInterface* Parent=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewOpaque.M_PreviewOpaque"),nullptr,LOAD_NoWarn);if(!Parent)return;
    UMaterialInstanceDynamic* Green=UMaterialInstanceDynamic::Create(Parent,this);Green->SetVectorParameterValue(TEXT("PreviewTint"),FLinearColor(0.f,1.f,0.f,1.f));
    TInlineComponentArray<UMeshComponent*> All;Him->GetComponents(All);
    for(UMeshComponent* Comp:All)for(const FName& Tag:Comp->ComponentTags){const FString T=Tag.ToString();const int32 PartIdx=HTagPart(T);if(PartIdx==INDEX_NONE)continue;
        OkMeshView V{};if(Him->Session.PartAt(PartIdx,V)&&V.name){const FString N=FString(UTF8_TO_TCHAR(V.name)).ToLower();
            if(N==TEXT("o_dankon")||N==TEXT("cm_o_dan00")){GreenComps.Add(Comp);for(int32 I=0;I<Comp->GetNumMaterials();++I){GreenKept.Add(Comp->GetMaterial(I));Comp->SetMaterial(I,Green);}}}break;} // the see-through overlay (bPenisXRay) stays on it
    UE_LOG(LogTemp,Display,TEXT("H scene: his penis drawn green (%d parts)"),GreenComps.Num());
}
TSharedRef<SWidget> UOKHRootPad::RebuildWidget(){
    if(!WidgetTree)WidgetTree=NewObject<UWidgetTree>(this);
    if(!WidgetTree->RootWidget){USizeBox* Size=WidgetTree->ConstructWidget<USizeBox>();Size->SetWidthOverride(170.f);Size->SetHeightOverride(170.f);WidgetTree->RootWidget=Size;}
    SetVisibility(ESlateVisibility::Visible);return Super::RebuildWidget();
}
int32 UOKHRootPad::NativePaint(const FPaintArgs& Args,const FGeometry& Geometry,const FSlateRect& Culling,FSlateWindowElementList& Out,int32 Layer,const FWidgetStyle& Style,bool bParentEnabled) const{
    const FVector2D Size=Geometry.GetLocalSize();const FVector2D C=Size*.5f;const float R=FMath::Min(Size.X,Size.Y)*.5f-12.f;
    TArray<FVector2D> Ring;for(int32 I=0;I<=48;++I){const float A=2.f*PI*I/48.f;Ring.Add(C+FVector2D(FMath::Cos(A),FMath::Sin(A))*R);}
    FSlateDrawElement::MakeLines(Out,Layer,Geometry.ToPaintGeometry(),Ring,ESlateDrawEffect::None,FLinearColor(1.f,1.f,1.f,.8f),true,2.f);
    FSlateDrawElement::MakeLines(Out,Layer,Geometry.ToPaintGeometry(),{C-FVector2D(R,0),C+FVector2D(R,0)},ESlateDrawEffect::None,FLinearColor(1.f,1.f,1.f,.25f),true,1.f);
    FSlateDrawElement::MakeLines(Out,Layer,Geometry.ToPaintGeometry(),{C-FVector2D(0,R),C+FVector2D(0,R)},ESlateDrawEffect::None,FLinearColor(1.f,1.f,1.f,.25f),true,1.f);
    const FVector2D Dot=C+FVector2D(Value.X,-Value.Y)*R;TArray<FVector2D> Mark;for(int32 I=0;I<=16;++I){const float A=2.f*PI*I/16.f;Mark.Add(Dot+FVector2D(FMath::Cos(A),FMath::Sin(A))*6.f);}
    FSlateDrawElement::MakeLines(Out,Layer+1,Geometry.ToPaintGeometry(),Mark,ESlateDrawEffect::None,FLinearColor(1.f,.4f,.7f),true,4.f);
    const FSlateFontInfo Font=FCoreStyle::GetDefaultFontStyle("Regular",10);
    auto Label=[&](const FString& Text,const FVector2D& At){FSlateDrawElement::MakeText(Out,Layer+1,Geometry.ToPaintGeometry(FVector2f(24.f,16.f),FSlateLayoutTransform(FVector2f(At-FVector2D(8.f,8.f)))),Text,Font,ESlateDrawEffect::None,FLinearColor(1.f,.9f,.6f));};
    Label(OKT(TEXT("ui.hscene.pad_back")),C-FVector2D(0,R+6.f));Label(OKT(TEXT("ui.hscene.pad_belly")),C+FVector2D(0,R+6.f));
    Label(OKT(TEXT("ui.hscene.pad_left")),C-FVector2D(R+6.f,0));Label(OKT(TEXT("ui.hscene.pad_right")),C+FVector2D(R+6.f,0));
    return Super::NativePaint(Args,Geometry,Culling,Out,Layer+1,Style,bParentEnabled);
}
void UOKHRootPad::Drag(const FGeometry& Geometry,const FPointerEvent& Event){
    const FVector2D Size=Geometry.GetLocalSize();const float R=FMath::Min(Size.X,Size.Y)*.5f-12.f;if(R<=1.f)return;
    const FVector2D P=(Geometry.AbsoluteToLocal(Event.GetScreenSpacePosition())-Size*.5f)/R;FVector2D V(P.X,-P.Y);
    if(V.Size()>1.f)V/=V.Size();Value=V;if(Owner)Owner->SetRootPad(V);
}
FReply UOKHRootPad::NativeOnMouseButtonDown(const FGeometry& Geometry,const FPointerEvent& Event){
    if(Event.GetEffectingButton()!=EKeys::LeftMouseButton)return FReply::Unhandled();
    bDragging=true;Drag(Geometry,Event);return FReply::Handled().CaptureMouse(TakeWidget());
}
FReply UOKHRootPad::NativeOnMouseMove(const FGeometry& Geometry,const FPointerEvent& Event){
    if(!bDragging)return FReply::Unhandled();Drag(Geometry,Event);return FReply::Handled();
}
FReply UOKHRootPad::NativeOnMouseButtonUp(const FGeometry& Geometry,const FPointerEvent& Event){
    if(!bDragging)return FReply::Unhandled();bDragging=false;return FReply::Handled().ReleaseMouseCapture();
}
// A slider moved sets its own value only, the other kept as it is (the control channel can set past the sliders' 2;
// the slider showing that as 2 is not a move).
void UOKHScenePanel::OnPenisLength(float Value){if(!FMath::IsNearlyEqual(Value,FMath::Min(PenisLength,2.f)))SetPenis(Value,PenisScale,FMath::Max(2.f,PenisScale));}
void UOKHScenePanel::OnPenisScale(float Value){if(!FMath::IsNearlyEqual(Value,FMath::Min(PenisScale,2.f)))SetPenis(PenisLength,Value,FMath::Max(2.f,PenisLength));}
// Most: past the sliders' 2, for testing (the control channel's penis; user, 2026-11-02: her belly pushed 40 cm out).
void UOKHScenePanel::SetPenis(float Length,float Scale,float Most){
    PenisLength=FMath::Clamp(Length,.5f,Most);PenisScale=FMath::Clamp(Scale,.5f,Most);
    if(LengthSlider&&!FMath::IsNearlyEqual(LengthSlider->GetValue(),FMath::Min(PenisLength,2.f)))LengthSlider->SetValue(FMath::Min(PenisLength,2.f));
    if(ScaleSlider&&!FMath::IsNearlyEqual(ScaleSlider->GetValue(),FMath::Min(PenisScale,2.f)))ScaleSlider->SetValue(FMath::Min(PenisScale,2.f));ShowPenis();
}
// Most: past the pad's edge, for testing (the control channel's penis.root; user, 2026-11-02: her belly pushed 40 cm out).
void UOKHScenePanel::SetRootPad(const FVector2D& Pad,float Most){
    RootPad=Pad.Size()>Most?Pad*(Most/Pad.Size()):Pad;RootPadScale=1.f;if(RootPadWidget)RootPadWidget->Value=RootPad;ShowPenis();
}
void UOKHScenePanel::ShowPenis(){
    if(PenisLabel)PenisLabel->SetText(FText::FromString(FString::Printf(TEXT("%s x%.2f  %s x%.2f  %s %.1f cm"),OKT(TEXT("ui.hscene.penis_length")),PenisLength,OKT(TEXT("ui.hscene.penis_scale")),PenisScale,OKT(TEXT("ui.hscene.penis_root")),RootPad.Size()*RootReach*RootPadScale)));
}
bool UOKHScenePanel::Hooked() const{const auto& X=Gallery?Gallery->HExperience:nullptr;return X.IsValid()&&X->HasField(TEXT("addicted"))&&X->GetBoolField(TEXT("addicted"));}
bool UOKHScenePanel::HadEnough() const{
    const auto& X=Gallery?Gallery->HExperience:nullptr;
    const int32 Today=X.IsValid()&&X->HasField(TEXT("today_orgasms"))?int32(X->GetNumberField(TEXT("today_orgasms"))):0; // earlier scenes today
    return Today+HerOrgasms>=FMath::Max(1,X.IsValid()&&X->HasField(TEXT("climax_limit"))?int32(X->GetNumberField(TEXT("climax_limit"))):4);
}
void UOKHScenePanel::CountHerOrgasm(){
    ++LineEpoch;
    ++HerOrgasms;NippleUntil=FPlatformTime::Seconds()+FMath::Lerp(5.,15.,double(Dev(TEXT("nipple")))); // her milk gushes for 5 s, 15 s when her nipples are developed (user 2026-11-04)
    if(HadEnough()&&!bSaidEnough){bSaidEnough=true;Note(OKT(Hooked()?TEXT("ui.hscene.she_hooked"):TEXT("ui.hscene.she_had_enough")));ActionsKey.Reset();}
}
void UOKHScenePanel::BuildActions(){
    if(!Actions||!WidgetTree)return;
    const FString Cur=Current(),Base=Mode==0?Cur:HBase(Cur);
    const bool Busy=!Queue.IsEmpty()&&!(Queue.Num()==1&&Cur==Queue[0]);
    const FString Key=FString::Printf(TEXT("%d|%s|%d|%d|%d|%d|%d|%d|%d"),Mode,*Cur,Busy,TouchArea,ActiveAibu+100*PendingAibu,His>=70.f,int32(bCondom)+2*int32(bAnalRefused)+4*int32(bLockHer)+8*int32(bLockHis)+16*int32(bServiceRefused)+32*int32(HadEnough())+64*int32(bPenisXRay),ActivePose,PendingPose);
    if(Key==ActionsKey)return;ActionsKey=Key;Actions->ClearChildren();Offered.Reset();
    auto Add=[this](int32 Kind,const TCHAR* Label){Offered.Add(Kind);auto* B=WidgetTree->ConstructWidget<UOKHSceneButton>();B->Kind=Kind;B->Owner=this;B->OnClicked.AddDynamic(B,&UOKHSceneButton::HandleClick);auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(OKT(Label)));B->SetContent(L);Actions->AddChildToWrapBox(B);};
    // The physics solver (user, 2026-11-01: choosable here): the controller's own menu, one click to the next solver.
    auto AddPhysics=[this](){if(!Gallery||!Gallery->PhysicsBackendCombo||Gallery->PhysicsBackendCombo->GetOptionCount()==0)return;Offered.Add(PhysicsNext);
        auto* B=WidgetTree->ConstructWidget<UOKHSceneButton>();B->Kind=PhysicsNext;B->Owner=this;B->OnClicked.AddDynamic(B,&UOKHSceneButton::HandleClick);
        auto* L=WidgetTree->ConstructWidget<UTextBlock>();L->SetText(FText::FromString(Gallery->PhysicsBackendCombo->GetSelectedOption()));B->SetContent(L);Actions->AddChildToWrapBox(B);};
    // In every mode (the caress branch below returns).
    Add(HeadCameraToggle,bHeadCamera?TEXT("ui.hscene.head_camera_on"):TEXT("ui.hscene.head_camera_off"));Add(EyesCameraToggle,HEyesOnCamera()?TEXT("ui.hscene.eyes_camera_on"):TEXT("ui.hscene.eyes_camera_off"));
    if(Mode==0&&ActiveAibu!=INDEX_NONE&&PendingAibu==INDEX_NONE&&!Busy){
        if(!Base.StartsWith(TEXT("Orgasm"))&&!Base.EndsWith(TEXT("Dislikes"))){
            // Touch or kiss (H_SCENE_ADDITIONS_PLAN 3): her mouth (her lips / a kiss), chest, nipples, head, butt, crotch,
            // anus, the back of her hand, thigh, calf, foot.
            {Add(LickToggle,bLickMode?TEXT("ui.hscene.act_mode_kiss"):TEXT("ui.hscene.act_mode_touch"));
             if(bLickMode){Add(Kiss,TEXT("ui.hscene.act_kiss"));Add(TouchChest,TEXT("ui.hscene.act_kiss_chest"));Add(TouchNipple,TEXT("ui.hscene.act_kiss_nipple"));Add(TouchHead,TEXT("ui.hscene.act_kiss_head"));
                 Add(TouchButt,TEXT("ui.hscene.act_kiss_butt"));Add(TouchCrotch,TEXT("ui.hscene.act_kiss_crotch"));Add(TouchAnal,TEXT("ui.hscene.act_kiss_anal"));
                 Add(TouchHand,TEXT("ui.hscene.act_kiss_hand"));Add(TouchThigh,TEXT("ui.hscene.act_kiss_thigh"));Add(TouchCalf,TEXT("ui.hscene.act_kiss_calf"));Add(TouchFoot,TEXT("ui.hscene.act_kiss_foot"));}
             else{Add(TouchLips,TEXT("ui.hscene.act_touch_lips"));Add(TouchChest,TEXT("ui.hscene.act_touch_chest"));Add(TouchNipple,TEXT("ui.hscene.act_touch_nipple"));Add(TouchHead,TEXT("ui.hscene.act_touch_head"));
                 Add(TouchButt,TEXT("ui.hscene.act_touch_butt"));Add(TouchCrotch,TEXT("ui.hscene.act_touch_crotch"));Add(TouchAnal,TEXT("ui.hscene.act_touch_anal"));
                 Add(TouchHand,TEXT("ui.hscene.act_touch_hand"));Add(TouchThigh,TEXT("ui.hscene.act_touch_thigh"));Add(TouchCalf,TEXT("ui.hscene.act_touch_calf"));Add(TouchFoot,TEXT("ui.hscene.act_touch_foot"));}
            }
            if(TouchArea!=INDEX_NONE)Add(Release,TEXT("ui.hscene.act_release"));
            Add(LockHer,bLockHer?TEXT("ui.hscene.act_unlock_her"):TEXT("ui.hscene.act_lock_her"));
            if(bPlayed&&!bAfterglow)Add(Afterglow,TEXT("ui.hscene.act_afterglow"));}
        return;
    }
    if(Mode==0||ActivePose==INDEX_NONE||PendingPose!=INDEX_NONE||Busy||Cur.IsEmpty()||CondomMouthFrom!=INDEX_NONE)return;
    const FOKHPose& Pose=Poses[ActivePose];
    Add(LockHer,bLockHer?TEXT("ui.hscene.act_unlock_her"):TEXT("ui.hscene.act_lock_her"));Add(LockHis,bLockHis?TEXT("ui.hscene.act_unlock_his"):TEXT("ui.hscene.act_lock_his"));
    // A check box always there (user, 2026-11-01): the part of him in her drawn half see-through, on and off at any time.
    Add(PenisXRayToggle,bPenisXRay?TEXT("ui.hscene.xray_on"):TEXT("ui.hscene.xray_off"));AddPhysics();
    Add(GrayRoomToggle,bGrayRoom?TEXT("ui.hscene.gray_room_on"):TEXT("ui.hscene.gray_room_off"));
    if(bPlayed)Add(Afterglow,TEXT("ui.hscene.act_afterglow"));
    Add(PenisPanelToggle,bPenisPanel?TEXT("ui.hscene.penis_panel_on"):TEXT("ui.hscene.penis_panel_off"));
    if(bPenisPanel)Add(PenisReset,TEXT("ui.hscene.penis_reset"));
    if(Mode==1){
        if((Base==TEXT("Idle")||Base==TEXT("Stop_Idle"))&&!bServiceRefused)Add(Faster,TEXT("ui.hscene.act_start"));
        else if(HIsLoop(Base)){Add(Faster,TEXT("ui.hscene.act_faster"));Add(Slower,TEXT("ui.hscene.act_slower"));Add(Toggle,TEXT("ui.hscene.act_toggle"));Add(Stop,TEXT("ui.hscene.act_stop"));}
        else if(Base==TEXT("OLoop")){Add(Inside,FinishInMouth()?TEXT("ui.hscene.act_in_mouth"):Pose.KindHoushi==2?TEXT("ui.hscene.act_on_chest"):Pose.Raw.Contains(TEXT("足コキ"))?TEXT("ui.hscene.act_on_feet"):TEXT("ui.hscene.act_in_hand"));Add(Outside,TEXT("ui.hscene.act_outside"));}
        else if(Base==TEXT("Oral_Idle")){Add(Drink,TEXT("ui.hscene.act_drink"));Add(Vomit,TEXT("ui.hscene.act_vomit"));}
        else if(Base.EndsWith(TEXT("_A"))){if(!bServiceRefused)Add(Again,TEXT("ui.hscene.act_again"));Add(Stop,TEXT("ui.hscene.act_rest"));}
        return;
    }
    const bool Out=Base==TEXT("Idle")||Base==TEXT("OUT_A");
    if(Out){Add(Insert,TEXT("ui.hscene.act_insert"));if(Pose.Anal&&!bAnalRefused)Add(InsertAnal,TEXT("ui.hscene.act_insert_anal"));Add(Condom,bCondom?TEXT("ui.hscene.act_condom_on"):TEXT("ui.hscene.act_condom_off"));}
    else if(Base==TEXT("InsertIdle")){Add(Faster,TEXT("ui.hscene.act_move"));Add(Pull,TEXT("ui.hscene.act_pull"));}
    else if(HIsLoop(Base)){Add(Faster,TEXT("ui.hscene.act_faster"));Add(Slower,TEXT("ui.hscene.act_slower"));Add(Toggle,TEXT("ui.hscene.act_toggle"));Add(Stop,TEXT("ui.hscene.act_stop"));
        if(His>=70.f){Add(Inside,TEXT("ui.hscene.act_inside"));Add(Outside,TEXT("ui.hscene.act_outside"));}}
    else if(Base.EndsWith(TEXT("_A"))){Add(Continue,TEXT("ui.hscene.act_continue"));Add(Pull,TEXT("ui.hscene.act_pull"));}
}

void UOKHScenePanel::NativeTick(const FGeometry& Geometry,float Delta){
    Super::NativeTick(Geometry,Delta);
    if(bGrayRoom&&GetWorld()&&GetWorld()->GetTimeSeconds()>=GrayCheckAt){GrayCheckAt=GetWorld()->GetTimeSeconds()+1.;HideWorld();}
    if(HalfInner&&PanelWidth){const float High=2.f*float(PanelWidth->GetCachedGeometry().GetLocalSize().Y);if(High>10.f&&!FMath::IsNearlyEqual(High,HalfInner->GetHeightOverride(),1.f))HalfInner->SetHeightOverride(High);}
    if(!Gallery)return;
    if(Poses.IsEmpty()&&!Gallery->NativePairs.IsEmpty()){LoadPoses();BuildList();}
    TickDrips(Delta);TickFluids(Delta);TickEyeDull(Delta);TickDeepFace(Delta);TickAhegao();TickCameraLight(false);Tremble(FPlatformTime::Seconds());TickHands();TickEyesCamera();TickCoordinates();TickSounds();SwellBust(Delta);ApplyPregnancy(FPlatformTime::Seconds());
    // Her breathing as the original picks it (HVoiceCtrl): her gauge past 50 and his fast motion (voice.speedMotion,
    // with its own up and down marks) change the cries, her experience the bank. A change starts the matching set
    // (user, 2026-11-01: in her it kept the first, quiet set the caress also uses).
    {FKKHBreathContext& B=Gallery->HBreath;const bool Was50=B.Gauge>=50.f,WasFast=B.bFast;
        B.Gauge=Her;B.bFast=WasFast?SpeedValue>.4f:SpeedValue>.6f;B.Experience=FMath::Clamp(Level(),0,3);
        B.bHadVaginal|=Level()>=1||(Mode==2&&bCrotch);B.bHadAnal|=Mode==2&&bAnal;
        // The voice table conditions (IsPtnConditionsSonyu): where he is, his condom, her first time there while a virgin.
        {const auto& X=Gallery->HExperience;B.bAnal=bAnalPlay;B.bCondom=bCondom;B.bVirginFirst=X.IsValid()&&X->GetBoolField(TEXT("virgin"))&&!bCrotch;B.bAnalVirginFirst=X.IsValid()&&X->GetBoolField(TEXT("anal_virgin"))&&!bAnal;}
        if((B.Gauge>=50.f)!=Was50||B.bFast!=WasFast){if(Mode==0)CaressBreath();else if(Gallery->PairedPlayback)Gallery->StartPairBreath();}}
    // Shoes off, hers and his: the one-on-one room is her own room, and the original's map table (h/list h_map_dependent)
    // has shoes=1 for every 自室 (hotel, inn, training camp) and the shower: HSceneProc.LoadMapDependent sets clothes
    // states 7 and 8 to 3 for everyone there.
    if(AKKPreviewActor* Girl=Gallery->PreviewActor.Get();IsValid(Girl)&&ShoesOffFor!=Girl){ShoesOffFor=Girl;uint8* S=Gallery->ClothesStates;
        if(S[7]!=3||S[8]!=3){S[7]=S[8]=3;Girl->SetClothingPartsHidden(S);Gallery->RefreshClothesStateLabels();}}
    UpdateFace();UpdateBlush(Delta);FrameCamera();
    // The original writes the liquid every frame; her materials are remade when her clothes or pose parts change.
    if(Siru[0]+Siru[1]+Siru[2]+Siru[3]+Siru[4]>0&&(SiruRefresh-=Delta)<=0.f){SiruRefresh=.5f;ApplySiru();}
    {const int32 Kind=Mode==0?(AibuPoses.IsValidIndex(ActiveAibu)?AibuPoses[ActiveAibu].Prop:0):(Poses.IsValidIndex(ActivePose)?Poses[ActivePose].Prop:0);
     const FString Key=FString::Printf(TEXT("%d|%d|%d"),Mode,ActivePose,ActiveAibu);const double T=FPlatformTime::Seconds();
     // A place change (bed, floor) resets the key too: the same pose, only the props change.
     if(Key!=PropKey){PropKey=Key;ClearProps();PropAt=Kind>0||Room!=0?T+.8:0.;bPlaceOnly=Key==LastPoseKey;LastPoseKey=Key;if(bEntered)Cover(true,T);bEntered=true;}
     else{const bool bPlays=NewPosePlays(T);
         // Props are set on the bones of the new pose: not before it has replaced the old one.
         if(PropAt>0&&T>=PropAt&&bPlays){PropAt=0;PlaceProps(Kind);}
         if(bCovered&&bPlays&&T>=CoverAt+.45&&PropAt==0)Cover(false,T);}
     auto* Playback=Gallery->PairedPlayback.Get();SeenPlayback=Playback;
     SeenClip=Playback?Playback->GetFemaleClip()+Playback->GetFemaleMotion():FString();SeenElapsed=Playback?Playback->GetElapsed():0.f;}
    // A pose counts as done once something happened in it (a gauge rose, he entered her, a touch), not when it only opened:
    // a pair opens on a moving state for a few seconds before its Idle.
    {const FString Cur=Current(),Base=Mode==0?Cur:HBase(Cur);
     if(Mode!=0&&Poses.IsValidIndex(ActivePose)&&(Her>3.f||His>3.f||Base.StartsWith(TEXT("Insert")))){PosesPlayed.AddUnique(Poses[ActivePose].Name);
         // The session counts (her experience, h_session_end) only then too: opening a room and leaving is not an H.
         bPlayed=true;if(Mode==1)bService=true;}
     if(Mode==0&&AibuPoses.IsValidIndex(ActiveAibu)&&TouchArea!=INDEX_NONE)PosesPlayed.AddUnique(AibuPoses[ActiveAibu].Name);}
    if(Mode!=0&&Gallery->PartnerActor&&Gallery->PartnerActor->IsHidden()!=bMaleHidden)Gallery->PartnerActor->SetActorHiddenInGame(bMaleHidden);
    // Only once the pair plays: while his parts and materials are still being prepared, hiding his clothes or swapping his
    // materials keeps that preparation from ever finishing (the room timed out).
    const bool PairPlaying=Gallery->PairedPlayback&&Gallery->PairedPlayback->GetElapsed()>0.f;
    if(Mode!=0&&PairPlaying&&Gallery->PartnerActor&&(MaleLookFor!=Gallery->PartnerActor.Get()||bXRayInHer!=XRayInHer()))ApplyMaleLook(); // he was (re)made for the pair, or he went into her / out of her
    AlignHim(Delta); // measures while the pair plays; a new pose or mode puts them back
    const double Now=FPlatformTime::Seconds();
    auto* Playback=Gallery->PairedPlayback.Get();
    // The scene opens on the pair list's first pose (a hand service): the original opens on the first caress that fits the
    // place (HSceneProc LoadAnimationListInfo, lstUseAnimInfo[0] first). Once the room is ready (its loading screen waits
    // for the pair to play), still on that opening pose. Not when he found her touching herself on the street.
    if(!bOpeningChecked){AOKInteractionMode* M=Interaction();
        if(M&&M->IsReady()){bOpeningChecked=true;
            if(Mode==1&&PendingPose==INDEX_NONE&&PendingAibu==INDEX_NONE&&!StreetOnani()){if(!bAibuLoaded)LoadAibuPoses();if(AibuPoses.Num()>0){Tab=TabAibu;SelectAibu(0);}}}}
    // The pose actually playing: the one he picked once it starts, or the one the scene opened with.
    const int32 Playing=Gallery->SelectedPairCatalogueIndex();
    if((Mode!=0||PendingPose!=INDEX_NONE)&&Playback&&!Gallery->bPairPreparing&&Gallery->PairStateCombo&&Gallery->PairStateCombo->GetOptionCount()>1){
        const int32 Found=Poses.IndexOfByPredicate([Playing](const FOKHPose& Pose){return Pose.Pair==Playing;});
        if(Found!=INDEX_NONE&&(Found!=ActivePose||PendingPose==Found)){
            ActivePose=Found;PendingPose=INDEX_NONE;Mode=Poses[Found].Mode;ClearLine();Queue.Reset();Wanted.Reset();bAnalPlay=false;bInsideFinished=false;bStrong=false;
            if(Has(TEXT("Idle")))Want(TEXT("Idle"));
            // At the condom with her mouth; another pose picked meanwhile ends it, nothing used.
            const bool bMouthing=CondomMouthFrom!=INDEX_NONE&&Found==CondomMouthPose;if(!bMouthing)CondomMouthFrom=INDEX_NONE;
            if(bMouthing){Want(TEXT("WLoop"));CondomMouthAt=Now+CVarHCondomMouthSeconds.GetValueOnGameThread();}
            // A new service pose past her rounds: she says no as to "once more" (the panel then offers no start).
            if(Mode==1&&!bMouthing&&!bServiceRefused&&OKHServiceSpent(ServiceFinishes,Gallery->HExperience)){bServiceRefused=true;Note(OKT(TEXT("ui.hscene.again_refused")));}
            if(Mode==1&&Poses[Found].KindHoushi==2)BareChest();
            Tab=Mode==2?TabSonyu:TabHand+Poses[Found].KindHoushi;BuildList();if(Hint)Hint->SetText(FText::FromString(Mode==1&&bServiceRefused?OKT(TEXT("ui.hscene.again_refused")):Poses[Found].Name)); // the new pose (or why she will not start it), not the last one's event
            // Her mouth is full until she has it on: what she says comes back in the pose.
            if(bMouthing)Note(OKT(TEXT("ui.hscene.condom_mouth")),false);
            if(bCondomMouthBack){bCondomMouthBack=false;const FString Event=OKT(TEXT("ui.hscene.condom_mouth_done"));Note(Event,false);React(Event,OKT(TEXT("ui.hscene.condom_mouth_note")));}
        }
    }
    if(CondomMouthFrom!=INDEX_NONE&&PendingPose==INDEX_NONE&&CondomMouthAt>0.&&Now>=CondomMouthAt){
        const int32 Back=CondomMouthFrom;CondomMouthFrom=INDEX_NONE;CondomMouthAt=0.;PutCondomOn();bCondomMouthBack=true;SelectPose(Back);}
    const FString Cur=Current(),Base=Mode==0?Cur:HBase(Cur);
    if(Mode==2&&Base.Contains(TEXT("Loop"))){float& Deepest=Cur.StartsWith(TEXT("A_"))?AnalDeepest:CrotchDeepest;Deepest=FMath::Max(Deepest,AlignDeep);}
    if(Cur!=LastState){
        const FString Before=HBase(LastState);
        LastState=Cur;StateSeen=Now;
        // Inserted once the insertion has played (SetInsertKokan / SetInsertAnal): her first time is then.
        if(Base==TEXT("InsertIdle")&&Before==TEXT("Insert")){
            const bool Virgin=Gallery->HExperience.IsValid()&&Gallery->HExperience->GetBoolField(Cur.StartsWith(TEXT("A_"))?TEXT("anal_virgin"):TEXT("virgin"));
            const bool First=Cur.StartsWith(TEXT("A_"))?!bAnal:!bCrotch;
            if(Cur.StartsWith(TEXT("A_")))bAnal=true;else{bCrotch=true;if(!bCondom)bRaw=true;}
            // What she agreed to goes with it (the reaction keeps only the latest note): she said yes to his asking.
            if(First){FString Event=OKT(Virgin?(Cur.StartsWith(TEXT("A_"))?TEXT("ui.hscene.react_first_anal"):TEXT("ui.hscene.react_virgin")):Cur.StartsWith(TEXT("A_"))?TEXT("ui.hscene.event_insert_anal"):bCondom?TEXT("ui.hscene.event_insert"):TEXT("ui.hscene.event_insert_raw"));
                if(Cur.StartsWith(TEXT("A_")))Event+=OKT(TEXT("ui.hscene.react_agreed_anal"));else if(bRawPressed&&!bCondom)Event+=OKT(TEXT("ui.hscene.react_agreed_raw"));
                else if(!bCondom)Event+=OKT(TEXT("ui.hscene.react_raw_fine")); // raw_ok: she lets him without being asked twice
                React(Event);}
        }
        if(Base==TEXT("Oral_Idle"))OralIdleSince=Now;
    }
    // The queued flow: a one-shot state moves on when it has played once; a finish's own loop after two rounds, and the
    // loop of her climax (WF/WS/SF/SS_IN_Loop, her body shaking in it) for as long as she comes, from when the loop
    // starts (OLoop plays first), as HSonyu holds it while her climax voice plays (user 2026-11-03: the original shaking,
    // not a made-up one).
    if(!Queue.IsEmpty()&&(Playback||Mode==0)){
        if(Cur==Queue[0]){
            if(Queue.Num()==1)Queue.Reset();
            else{
                const float Elapsed=Mode==0?float(Now-SoloStarted):Playback->GetElapsed(),Length=FMath::Max(.2f,Gallery->PreviewActor?Gallery->PreviewActor->AnimDuration:1.f);
                const bool LoopLike=Base.EndsWith(TEXT("_Loop"))||Base==TEXT("OLoop")||Base==TEXT("Oral_Idle_IN");
                const bool HerClimax=Mode==2&&(Base.EndsWith(TEXT("F_IN_Loop"))||Base.EndsWith(TEXT("S_IN_Loop")));
                if(HerClimax?Elapsed>=ClimaxLoopFor&&!(bTalkSpoken&&Gallery->PreviewActor&&Gallery->PreviewActor->IsSpeaking()):Elapsed>=(LoopLike?FMath::Max(Length*2.f,2.5f):Length*.98f)){Queue.RemoveAt(0);Want(Queue[0]);}
            }
        }else if(Wanted!=Queue[0])Want(Queue[0]);
    }
    if(!Wanted.IsEmpty()&&Cur==Wanted)Wanted.Reset();
    if(Mode==0&&!Wanted.IsEmpty()){PlaySolo(Wanted);Wanted.Reset();}
    if(!Wanted.IsEmpty()&&Playback&&!Gallery->bPairPreparing&&Now-LastRequest>.75&&Gallery->PairStateCombo){
        LastRequest=Now;
        if(Gallery->PairStateCombo->GetSelectedOption()!=Wanted)Gallery->PairStateCombo->SetSelectedOption(Wanted);
        else Gallery->OnPairStateSelected(Wanted,ESelectInfo::Direct);
    }
    // Gauges (HFlag gaugeFemale / gaugeMale): they rise with the movement, faster when strong; hers by her experience.
    if(Speed)SpeedValue=Speed->GetValue();
    const float Rate=SpeedValue,Strong=Base==TEXT("SLoop")?1.25f:1.f;
    if(SpeedCover){const bool bCover=Mode==0&&TouchArea!=INDEX_NONE&&TouchArea!=0&&NeverHad(TouchArea);
        const ESlateVisibility Want=bCover?ESlateVisibility::HitTestInvisible:ESlateVisibility::Hidden;if(SpeedCover->GetVisibility()!=Want)SpeedCover->SetVisibility(Want);}
    static const float HerByLevel[]={.55f,.8f,1.f,1.35f};
    // Caress (HAibu): resting on a place she is being touched; her gauge by how used to it she is, and too hard on a
    // place she has never been touched there makes her pull away (JudgeDislikesis70).
    if(Mode==0&&Queue.IsEmpty()&&TouchArea!=INDEX_NONE&&BodyTouching()&&!Base.EndsWith(TEXT("Dislikes"))&&!Base.StartsWith(TEXT("Orgasm"))){
        bPlayed=true;AreaSeconds[TouchArea]+=Delta;if(FPlatformTime::Seconds()>=FlinchNext)Flinch(TouchArea);
        Her+=Delta*(1.f+Dev(TouchArea==0?TEXT("kiss"):HBodyKey(TouchArea)))*CVarHHerRate.GetValueOnGameThread();if(bLockHer)Her=FMath::Min(Her,95.f);
        if(Her>=100.f){Her=0.f;++AreaClimaxes[TouchArea];TouchArea=INDEX_NONE;bLipsTouch=false;ReleaseHeld();Chain({TEXT("Orgasm_Start"),TEXT("Orgasm_Loop"),TEXT("Orgasm_A"),TEXT("Idle")});Note(OKT(TEXT("ui.hscene.event_her_orgasm")));CountHerOrgasm();}
    }
    else if(Mode==0&&Queue.IsEmpty()&&TouchArea!=INDEX_NONE&&(Base.EndsWith(TEXT("_Idle"))||Base==TEXT("K_Loop"))){
        bPlayed=true;AreaSeconds[TouchArea]+=Delta;
        const float Used=FMath::Clamp(AreaExperience(TouchArea)/100.f,0.f,1.f);
        // The original's rate (HandCtrl: FemaleGaugeUp(deltaTime * rateClickGauge), rateClickGauge 2 in the H scene's HFlag,
        // level8): two points a second, fifty seconds to her climax.
        Her+=Delta*2.f*CVarHHerRate.GetValueOnGameThread();if(bLockHer)Her=FMath::Min(Her,95.f);
        if(Rate>=.7f&&Used<=0.f&&TouchArea!=0){Note(OKT(TEXT("ui.hscene.too_hard")));Chain({TouchArea>=3&&TouchArea<=4?TEXT("Back_Dislikes"):TEXT("Front_Dislikes"),TEXT("Idle")});TouchArea=INDEX_NONE;}
        else if(Her>=100.f){Her=0.f;++AreaClimaxes[TouchArea];TouchArea=INDEX_NONE;ReleaseHeld();Chain({TEXT("Orgasm_Start"),TEXT("Orgasm_Loop"),TEXT("Orgasm_A"),TEXT("Idle")});Note(OKT(TEXT("ui.hscene.event_her_orgasm")));CountHerOrgasm();}
    }else if(Queue.IsEmpty()&&HIsLoop(Base)){
        if(Mode==1){His+=Delta*(2.5f+8.f*Rate)*Strong*CVarHHisRate.GetValueOnGameThread();if(bLockHis)His=FMath::Min(His,69.f);Her=FMath::Min(69.f,Her+Delta*.8f);if(His>=70.f&&Wanted.IsEmpty())Want(TEXT("OLoop"));}
        else{const float Both=Delta*(1.5f+6.f*Rate)*Strong*HerByLevel[FMath::Clamp(Level(),0,3)]; // he rises as fast as she does (user 2026-11-04); the panel's rates set them apart
            His+=Both*CVarHHisRate.GetValueOnGameThread();Her+=Both*CVarHHerRate.GetValueOnGameThread();
            if(bLockHer)Her=FMath::Min(Her,95.f);if(bLockHis)His=FMath::Min(His,95.f);
            // Locked, he does not come with her (as she does not come with him locked: the line below).
            // Nor without a condom in her vagina: he rises as fast as she does, so that would be every time and he never chose.
            if(Her>=100.f)Finish(His>=70.f&&!bLockHis&&(bCondom||bAnalPlay)?(Strong>1.f?TEXT("sameS"):TEXT("sameW")):(Strong>1.f?TEXT("orgS"):TEXT("orgW")));
            else if(His>=100.f)Finish(!bCondom?TEXT("outside"):Her>=70.f&&!bLockHer?(Strong>1.f?TEXT("sameS"):TEXT("sameW")):TEXT("inside"));}
    }else if(Queue.IsEmpty()&&Base==TEXT("OLoop")&&Mode==1){His=FMath::Min(bLockHis?95.f:100.f,His+Delta*3.f);if(His>=100.f)Finish(Poses.IsValidIndex(ActivePose)&&FinishInMouth()?TEXT("inside"):TEXT("outside"));}
    else if(Queue.IsEmpty()){Her=FMath::Max(0.f,Her-Delta*3.f);His=FMath::Max(0.f,His-Delta*3.f);}
    Her=FMath::Clamp(Her,0.f,100.f);His=FMath::Clamp(His,0.f,100.f);
    // In her mouth she decides herself if he waits (HHoushi Oral_Idle: drink or spit after a while).
    if(Queue.IsEmpty()&&Base==TEXT("Oral_Idle")&&OralIdleSince>0.&&Now-OralIdleSince>8.){OralIdleSince=0.;static const float DrinkChance[]={.2f,.35f,.6f,.85f};Click(FMath::FRand()<DrinkChance[FMath::Clamp(Level(),0,3)]?Drink:Vomit);} // her own choice: the more used to it, the likelier she swallows
    ApplySpeed();
    // Her spoken answer is over: her breathing goes on (the line stopped it).
    if(bTalkSpoken&&Gallery->PreviewActor&&!Gallery->PreviewActor->IsSpeaking()){bTalkSpoken=false;if(Mode==0)CaressBreath();else if(Gallery->PairedPlayback)Gallery->StartPairBreath();}
    if(HerGauge)HerGauge->SetPercent(Her/100.f);if(HisGauge)HisGauge->SetPercent(His/100.f);
    // Her developments as the scene uses them, each climax there (his finish in her mouth) shown as it adds 10
    // (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md P3); kissing and her caressed places with what this scene's touch adds when it
    // ends (hexp h_session_end: a second of kissing a point, of touch half a point; user 2026-11-03: kiss and butt shown).
    if(DevLine){auto Pct=[this](const TCHAR* A){return int32(FMath::RoundToFloat(Dev(A)*100.f));};
        auto Gain=[](int32 N){return N>0?OKMsg(TEXT("ui.hscene.dev_gain"),{{TEXT("n"),N}}):FString();};
        auto Touch=[&](int32 Area,float PerSecond){const float Was=AreaExperience(Area);return Gain(int32(FMath::Min(100.f,Was+AreaSeconds[Area]*PerSecond))-int32(Was));};
        DevLine->SetText(FText::FromString(OKMsg(TEXT("ui.hscene.dev_line"),{{TEXT("kiss"),Pct(TEXT("kiss"))},{TEXT("kiss_gain"),Touch(0,1.f)},
            {TEXT("chest"),Pct(TEXT("chest"))},{TEXT("chest_gain"),Touch(1,.5f)},{TEXT("nipple"),Pct(TEXT("nipple"))},{TEXT("nipple_gain"),Touch(5,.5f)},
            {TEXT("butt"),Pct(TEXT("butt"))},{TEXT("butt_gain"),Touch(4,.5f)},
            {TEXT("crotch"),Pct(TEXT("crotch"))},{TEXT("crotch_gain"),Gain(10*CrotchClimaxes)},{TEXT("anal"),Pct(TEXT("anal"))},{TEXT("anal_gain"),Gain(10*AnalClimaxes)},
            {TEXT("oral"),Pct(TEXT("oral"))},{TEXT("oral_gain"),Gain(10*HisMouth)},
            // The rest of her (H_SCENE_ADDITIONS_PLAN 3).
            {TEXT("head"),Pct(TEXT("head"))},{TEXT("head_gain"),Touch(6,.5f)},{TEXT("hand"),Pct(TEXT("hand"))},{TEXT("hand_gain"),Touch(7,.5f)},
            {TEXT("thigh"),Pct(TEXT("thigh"))},{TEXT("thigh_gain"),Touch(8,.5f)},{TEXT("calf"),Pct(TEXT("calf"))},{TEXT("calf_gain"),Touch(9,.5f)},
            {TEXT("foot"),Pct(TEXT("foot"))},{TEXT("foot_gain"),Touch(10,.5f)}})));}
    if(Title){FString Name=Gallery->HHeroineName;const FString LevelName=Gallery->HExperience.IsValid()?Gallery->HExperience->GetStringField(TEXT("level_name")):FString();
        Title->SetText(FText::FromString(LevelName.IsEmpty()?Name:FString::Printf(TEXT("%s · %s"),*Name,*LevelName)));}
    if(Status){
        const FString PoseName=Mode==0&&AibuPoses.IsValidIndex(ActiveAibu)?AibuPoses[ActiveAibu].Name:Poses.IsValidIndex(PendingPose)?Poses[PendingPose].Name+OKT(TEXT("ui.hscene.loading")):Poses.IsValidIndex(ActivePose)?Poses[ActivePose].Name:FString(OKT(TEXT("ui.hscene.pick_pose")));
        Status->SetText(FText::FromString(Cur.IsEmpty()?PoseName:FString::Printf(TEXT("%s · %s · ×%.1f%s"),*PoseName,*StateWords(Mode==0?Cur:HBase(Cur)),PlaybackSpeed(),Mode==2?(bCondom?OKT(TEXT("ui.hscene.condom_mark")):TEXT("")):TEXT(""))));
    }
    BuildActions();
}

bool UOKHScenePanel::CannotAnswer() const{
    const FString Cur=Current(),Base=Mode==0?Cur:HBase(Cur);
    const bool Moving=Mode==0?TouchArea!=INDEX_NONE:HIsLoop(Base);
    return Moving&&Queue.IsEmpty()&&PlaybackSpeed()>2.f;
}
void UOKHScenePanel::Say(const FString& Raw){
    const FString Text=Raw.TrimStartAndEnd();if(Text.IsEmpty())return;
    if(Gallery)Gallery->NoteAction(TEXT("said"),Text);
    if(CannotAnswer()){Held.Add(Text);if(Hint)Hint->SetText(FText::FromString(OKT(TEXT("ui.hscene.cannot_answer"))));return;}
    Outbox.Add({Text,FString()});
}
void UOKHScenePanel::ReleaseHeld(){
    if(Held.IsEmpty())return;
    Outbox.Add({FString::Join(Held,TEXT(" ")),OKT(TEXT("ui.hscene.held_note"))});Held.Reset();
}
bool UOKHScenePanel::TakeLine(FString& Text,FString& Out,bool& System){
    if(Outbox.IsEmpty())return false;
    Text=Outbox[0].Text;System=Outbox[0].System;Out=Context();SentEpoch=LineEpoch;if(!Outbox[0].Note.IsEmpty())Out+=TEXT("\n")+Outbox[0].Note;Outbox.RemoveAt(0);
    if(!System&&Caption&&Gallery)Caption->SetText(FText::FromString(Gallery->HPlayerName+TEXT("：")+Text));
    return true;
}
void UOKHScenePanel::React(const FString& Event,const FString& Extra){
    if(Event.IsEmpty()||CannotAnswer())return;
    Outbox.RemoveAll([](const FHLine& L){return L.System;});
    Outbox.Add({OKMsg(TEXT("ui.hscene.react_note"),{{TEXT("event"),Event}}),Extra,true});
}
// Her original breathing for the caress (HVoiceCtrl breath, mode 0): moving while his hands are on her.
void UOKHScenePanel::CaressBreath(){
    if(!Gallery||!Gallery->PreviewActor||Mode!=0||!AibuPoses.IsValidIndex(ActiveAibu)||Gallery->PreviewActor->IsSpeaking()&&!Gallery->PreviewActor->bHBreath)return;
    TArray<FKKHBreathCue> Cues;FString Error;const int32 Personality=Gallery->Selected.Personality;
    FKKHBreathContext Context=Gallery->HBreath;Context.bMoving=TouchArea!=INDEX_NONE;
    if(KKSpeech::CollectHBreath(UOKCharacterController::DefaultVoiceRoot(),Personality,0,SoloState,AibuPoses[ActiveAibu].Id,Context,Cues,Error)&&Cues.Num())
    {const bool Ok=Gallery->PreviewActor->BeginHBreath(Cues,FMath::Lerp(.94f,1.06f,Gallery->Selected.VoiceRate),Error);
        UE_LOG(LogTemp,Display,TEXT("H scene: caress breath %s cues=%d %s"),*SoloState,Cues.Num(),Ok?TEXT("playing"):*Error);}
    else UE_LOG(LogTemp,Display,TEXT("H scene: no caress breath for %s: %s"),*SoloState,*Error);
}
bool UOKHScenePanel::Hear(const FString& Raw,FString& Out){
    const FString Text=Raw.TrimStartAndEnd();if(Text.IsEmpty())return false;
    if(Gallery)Gallery->NoteAction(TEXT("said"),Text);
    if(CannotAnswer()){Held.Add(Text);if(Hint)Hint->SetText(FText::FromString(OKT(TEXT("ui.hscene.cannot_answer"))));return false;}
    Out=Context();SentEpoch=LineEpoch;if(Caption&&Gallery)Caption->SetText(FText::FromString(Gallery->HPlayerName+TEXT("：")+Text));return true;
}
void UOKHScenePanel::ShowLine(const FString& Text){
    bStaleLine=SentEpoch!=LineEpoch;if(bStaleLine){UE_LOG(LogTemp,Display,TEXT("H scene: her line from before the last climax / finish / pose not shown: %s"),*Text.Left(60));return;}
    if(Caption)Caption->SetText(FText::FromString(Text));
}
// What his words in the scene asked for (the street's H judge, ui.scene.h_judge_prompt): the pose and what is going on
// now, and every pose and caress by name.
FString UOKHScenePanel::JudgeFacts() const{
    const FString Cur=Current(),Base=Mode==0?Cur:HBase(Cur);
    const FString PoseName=Mode==0&&AibuPoses.IsValidIndex(ActiveAibu)?AibuPoses[ActiveAibu].Name:Poses.IsValidIndex(ActivePose)?Poses[ActivePose].Name:FString();
    TArray<FString> Names;for(const FOKHPose& P:Poses)Names.AddUnique(P.Name);for(const auto& A:AibuPoses)Names.AddUnique(A.Name);
    return OKMsg(TEXT("ui.hscene.judge_facts"),{{TEXT("pose"),PoseName},{TEXT("state"),Cur.IsEmpty()?FString():StateWords(Base)},{TEXT("poses"),FString::Join(Names,TEXT("、"))}});
}
// His words do what the buttons do, and only what they offer now: "stop" stops (whatever she would like), "pull out",
// "faster" / "slower", where he finishes; another pose only when she agreed in her reply. Ending the scene is the street's.
bool UOKHScenePanel::ApplyTalk(const TSharedPtr<FJsonObject>& V){
    if(!V.IsValid()||!Gallery)return false;
    bool bStop=false,bPull=false,bEnd=false,bAgrees=true;FString Pose,Pace,Where,Why;
    V->TryGetBoolField(TEXT("stop"),bStop);V->TryGetBoolField(TEXT("pull"),bPull);V->TryGetBoolField(TEXT("end"),bEnd);V->TryGetBoolField(TEXT("she_agrees"),bAgrees);
    V->TryGetStringField(TEXT("pose"),Pose);V->TryGetStringField(TEXT("speed"),Pace);V->TryGetStringField(TEXT("finish"),Where);V->TryGetStringField(TEXT("why"),Why);
    // Her answer to going without a condom, taken while she is pregnant and knows (otherwise raw_ok and asking twice decide).
    {FString Let;V->TryGetStringField(TEXT("lets_raw"),Let);
     if((PregnantKnows()||bNoCondomAsked)&&(Let==TEXT("yes")||Let==TEXT("no"))){RawLet=Let==TEXT("yes")?1:-1;if(RawLet>0)Note(OKT(TEXT("ui.hscene.raw_let_pregnant")),false);
      UE_LOG(LogTemp,Display,TEXT("H talk judge: going without a condom: %s"),*Let);}}
    UE_LOG(LogTemp,Display,TEXT("H talk judge: stop=%d pull=%d end=%d pose=\"%s\" agrees=%d speed=\"%s\" finish=\"%s\"; %s"),bStop,bPull,bEnd,*Pose,bAgrees,*Pace,*Where,*Why);
    if(bEnd)return true;
    ActionsKey.Reset();BuildActions();
    if(bStop||bPull){
        if(Mode==0){if(TouchArea!=INDEX_NONE)Click(Release);}
        else{
            const FString Base=HBase(Current());
            if(Offered.Contains(Stop))Click(Stop);
            // Close to his climax nothing is offered but finishing: stopping is still his to do.
            else if(HIsLoop(Base)||Base==TEXT("OLoop")){Queue.Reset();Want(Mode==1?(Has(TEXT("Stop_Idle"))?TEXT("Stop_Idle"):TEXT("Idle")):P(TEXT("InsertIdle")));}
            // Pulling out while moving: stop, then out (the stop's InsertIdle has not played yet, so Pull is not offered).
            if(bPull){ActionsKey.Reset();BuildActions();if(Offered.Contains(Pull))Click(Pull);
                else if(Mode==2&&Has(P(TEXT("Pull")))){Chain({P(TEXT("InsertIdle")),P(TEXT("Pull")),P(TEXT("Idle"))});bInsideFinished=false;}}
        }
        return false;
    }
    if(!Pose.IsEmpty()&&bAgrees){
        const int32 A=AibuPoses.IndexOfByPredicate([&](const auto& X){return X.Name==Pose;});
        if(A!=INDEX_NONE){Tab=TabAibu;SelectAibu(A);}else if(!SelectPoseNamed(Pose)){UE_LOG(LogTemp,Display,TEXT("H talk judge: no pose named %s"),*Pose);}
        return false;
    }
    if(Pace==TEXT("faster")&&Offered.Contains(Faster))Click(Faster);
    else if(Pace==TEXT("slower")&&Offered.Contains(Slower))Click(Slower);
    if(Where==TEXT("inside")&&Offered.Contains(Inside))Click(Inside);
    else if(Where==TEXT("outside")&&Offered.Contains(Outside))Click(Outside);
    return false;
}
// A new pose or caress: what she said to the last one is no longer what is on the screen (her next line replaces nothing stale).
void UOKHScenePanel::ClearLine(){++LineEpoch;if(Caption)Caption->SetText(FText::GetEmpty());}
// Standard face patterns (eye_face.f00_*, mayuge.mayu00_*): eyes 1 closed, 4 smile, 7 setunai, 8 tere, 12 kurusi,
// 13 keno, 24 gyu (squeezed shut); brows 0 default, 1 oko, 2 koma, 11 huan.
// The original's ahegao is the KKS_Ahegao plugin (D:\KoikatuSunshine\BepInEx\config\KKS_Ahegao.cfg, user 2026-11-03): after
// 4 climaxes (caress or insertion; Ahegao Count 4), only while a loop plays (Loop1/2, OLoop, IN_*) faster than 66% (Speed
// Toggle, Minimum Speed 66) and not while kissing; eyes 25, brows 2, mouth 24, and her eyes rolled up 0.25 past her look
// (the street's display materials have no gaze rows: the eye mesh's own coordinates take it, OKUpdateSkeletalMeshUVs).
static TAutoConsoleVariable<float> CVarHAhegaoGaze(TEXT("ok.HScene.AhegaoGaze"),1.25f,TEXT("Ahegao: her gaze, +1 up (-1 down); past it the iris rolls on past its limit (the original's Eye Roll Amount 0.25)"));
static TAutoConsoleVariable<float> CVarHAhegaoSpeed(TEXT("ok.HScene.AhegaoSpeed"),.66f,TEXT("Ahegao after her climaxes: only faster than this (the original's Minimum Speed 66; 0 always)"));
// The original's eyes pattern is a cha_eyeset row (ChaControl.ChangeEyesPtn): its FaceBlendShape eye pattern is the row's
// eyes_ptn (as OK Studio reads it, OKStudioCatalog::EyeSet), from the base library's lists; -1 when they have none.
static int32 HEyeSetBlend(int32 Ptn){
    static TMap<int32,int32> Cache;if(const int32* Hit=Cache.Find(Ptn))return *Hit;
    const FString Configured=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_BASE_LIBRARY"));
    const FTCHARToUTF8 Lib(*(Configured.IsEmpty()?FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()/TEXT("IndependentResources/base_v1")):Configured));
    int32 Blend=-1;const int32 Size=ok_eye_set_json(Lib.Get(),Ptn,nullptr,0);
    if(Size>0){TArray<uint8> Bytes;Bytes.SetNumZeroed(Size+1);ok_eye_set_json(Lib.Get(),Ptn,Bytes.GetData(),Size);
        const FString Json=UTF8_TO_TCHAR(reinterpret_cast<const char*>(Bytes.GetData()));TSharedPtr<FJsonObject> Root;
        if(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Root)&&Root){double V=-1;Root->TryGetNumberField(TEXT("eyes_ptn"),V);Blend=int32(V);}
        UE_LOG(LogTemp,Display,TEXT("H scene: eye set %d: %s"),Ptn,*Json);}
    Cache.Add(Ptn,Blend);return Blend;
}
static TAutoConsoleVariable<FString> CVarHAhegaoFace(TEXT("ok.HScene.AhegaoFace"),TEXT("25,2,43"),TEXT("Ahegao: eye set, brow and mouth patterns (the original's Eye ID 25, Eyebrow ID 2; mouth 43 SexFaces' ahegao, the original's 24 when it lacks)"));
static TAutoConsoleVariable<int32> CVarHAhegaoClimaxes(TEXT("ok.HScene.AhegaoClimaxes"),4,TEXT("Her climaxes in one scene after which she shows the ahegao (0 only when worn out for the day)"));
static TAutoConsoleVariable<int32> CVarHAhegaoTest(TEXT("ok.HScene.AhegaoTest"),0,TEXT("1: the ahegao now (testing)"));
// The double peace of her ahegao: both hands up by her face (Studio FBBIK hand effectors 5 left, 6 right, at her head
// plus out to each side, a little forward and down), fingers in the V (ok.HScene.AhegaoHand, the hand-shape key).
// Given every tick while it shows; let go when it ends, her hands back to the animation (or as set on the panel).
static TAutoConsoleVariable<int32> CVarHAhegaoHand(TEXT("ok.HScene.AhegaoHand"),2,TEXT("Ahegao: the hand-shape key of the V sign (-1 no hand shape)"));
static TAutoConsoleVariable<FString> CVarHAhegaoReach(TEXT("ok.HScene.AhegaoReach"),TEXT("13,9,-1"),TEXT("Ahegao: her hands from her head, cm: out to the side, forward, up"));
static TAutoConsoleVariable<float> CVarHAhegaoMouthOpen(TEXT("ok.HScene.AhegaoMouthOpen"),.85f,TEXT("Ahegao: how far her mouth stays open (her tongue out)"));
static TAutoConsoleVariable<int32> CVarHAhegaoArms(TEXT("ok.HScene.AhegaoArms"),1,TEXT("Ahegao: 1 her hands up by her face (Studio IK), 0 only the V"));
static bool HChestForward(AKKPreviewActor* A,FVector& Out);
// Her tongue out: SexFaces' ahegao mouth (43: smile with TongueOut, installed with the game), else the original's mouth 24 (its
// tongue hardly shows here), else 舌出し (_sita), else 舐める (_name).
static int32 HTongueMouth(AKKPreviewActor* Girl){
    TArray<FString> AF;CVarHAhegaoFace.GetValueOnGameThread().ParseIntoArray(AF,TEXT(","));const int32 Count=Girl->GetMouthPatternCount();
    const int32 Set=AF.IsValidIndex(2)?FCString::Atoi(*AF[2]):43;if(Set>=0&&Set<Count)return Set;if(24<Count)return 24;
    for(const TCHAR* Word:{TEXT("_sita"),TEXT("_name")})for(int32 P=0;P<Count;++P)if(Girl->GetMouthPatternLabel(P).ToLower().Contains(Word))return P;
    return INDEX_NONE;
}
// Where he is in her developed all the way and her desire past 100, or past her fourth climax of the scene (user 2026-11-04):
// her eyes roll up and her tongue comes out with how deep he is (AlignDeep, 20..90), back as he draws out. The ahegao takes
// over from it and goes on following him while he is in her (TickAhegao).
void UOKHScenePanel::EndDeepFace(AKKPreviewActor* Girl){
    if(!bDeepFace)return;bDeepFace=false;DeepFace=DeepGazeSet=0.f;Girl->bManualSpeechPattern=bDeepManualWas;Girl->SetMouthOpenHeld(-1.f);FaceKey.Reset();
    if(bAhegaoShown)return;
    Girl->SetEyeGaze(0.f,0.f,0.f);Girl->SetMouthPattern(0);Girl->SetMouthOpenFloor(0.f);
    if(bAheEyeLook){bAheEyeLook=false;if(bAheEyeFollow)Girl->FollowEyeLookCamera(AheEyePattern);else Girl->SetEyeLookTarget(AheEyeTarget,AheEyePattern,true);}
}
// A yandere's eyes are as on the street, pupils 1.1 times as large and no highlight; once she has climaxed today with her
// stamina or hunger under 50, whoever she is, 1.3 times and no highlight (user 2026-11-04). The pupils ease there.
void UOKHScenePanel::TickEyeDull(float Delta){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return;
    const auto& X=Gallery->HExperience;auto Num=[&X](const TCHAR* Key,double Default){double V=Default;if(X.IsValid())X->TryGetNumberField(Key,V);return V;};
    const bool bSpent=HerOrgasms+int32(Num(TEXT("today_orgasms"),0.))>=1&&(Num(TEXT("energy"),100.)<50.||Num(TEXT("satiety"),100.)<50.);
    const float Want=bSpent?1.3f:int32(Num(TEXT("personality"),0.))==KKPersonalityYandere?1.1f:1.f;
    // The panel on the left: her size on top of that, the highlight off whatever her state, and a tremble that goes to a
    // new place in the iris PupilShakeRate times a second.
    const float Range=CVarHPupilShake.GetValueOnGameThread()/100.f,Rate=CVarHPupilShakeRate.GetValueOnGameThread();
    if(Range>0.f&&Rate>0.f){PupilShakeClock+=Delta*Rate;
        if(PupilShakeClock>=1.f){PupilShakeClock=FMath::Fractional(PupilShakeClock);PupilShakeFrom=PupilShakeTo;PupilShakeTo=FVector2f(FMath::RandPointInCircle(Range));}
        PupilShakeNow=FMath::Lerp(PupilShakeFrom,PupilShakeTo,PupilShakeClock);Girl->SetPupilOffset(PupilShakeNow.X,PupilShakeNow.Y);}
    else if(!PupilShakeNow.IsZero()){PupilShakeNow=PupilShakeFrom=PupilShakeTo=FVector2f::ZeroVector;Girl->SetPupilOffset(0.f,0.f);}
    const bool bHide=Want>1.f||CVarHPupilHighlight.GetValueOnGameThread()==0;const float Sized=Want*CVarHPupilSize.GetValueOnGameThread();
    const float Now=EyeDullScale>0.f?FMath::FInterpConstantTo(EyeDullScale,Sized,Delta,.3f):Sized;
    if(Now==EyeDullScale&&bHide==bEyeDullHidden)return;
    EyeDullScale=Now;bEyeDullHidden=bHide;Girl->SetEyeDull(Now,bHide);
}
void UOKHScenePanel::TickDeepFace(float Delta){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return;
    const FString Base=HBase(Current());
    const bool bInside=Mode==2&&(Base.Contains(TEXT("Loop"))||Base.Contains(TEXT("IN_")));const int32 AheAt=CVarHAhegaoClimaxes.GetValueOnGameThread();
    const bool bWant=bInside&&(bAhegaoShown||(AheAt>0&&HerOrgasms>=AheAt)||(Dev(bAnalPlay?TEXT("anal"):TEXT("crotch"))>=1.f&&HerDesire()>100.f));
    bAheDepth=bAhegaoShown&&bInside;
    const float DeepTop=100.f*FMath::Lerp(bAnalPlay?.4f:.5f,.9f,Dev(bAnalPlay?TEXT("anal"):TEXT("crotch"))); // as deep as he goes at her development
    DeepFace=FMath::FInterpTo(DeepFace,bWant?FMath::Clamp((AlignDeep-20.f)/(DeepTop-20.f),0.f,1.f):0.f,Delta,12.f);
    if(bAhegaoShown||(!bWant&&DeepFace<.02f)){EndDeepFace(Girl);return;}
    const int32 Tongue=HTongueMouth(Girl);
    if(!bDeepFace){bDeepFace=true;bDeepManualWas=Girl->bManualSpeechPattern;DeepGazeSet=0.f;}
    if(Girl->bEyeLookTracking){bAheEyeLook=true;bAheEyeFollow=Girl->bEyeLookFollowCamera;AheEyePattern=Girl->EyeLookPattern;AheEyeTarget=Girl->EyeLookWorldTarget;Girl->StopEyeLookTracking();}
    const float Gaze=CVarHAhegaoGaze.GetValueOnGameThread()*DeepFace;if(FMath::Abs(Gaze-DeepGazeSet)>.03f){SyncPair();if(Girl->SetEyeGaze(0.f,0.f,Gaze))DeepGazeSet=Gaze;}
    // Her breathing lines change her mouth by the original's face list; her tongue stays out (TickAhegao).
    if(Tongue!=INDEX_NONE){Girl->bManualSpeechPattern=true;Girl->SavedMouthPattern=Tongue;if(Girl->MouthPattern!=Tongue)Girl->SetMouthPattern(Tongue);}
    Girl->SetMouthOpenHeld(FMath::Min(1.f,CVarHAhegaoMouthOpen.GetValueOnGameThread()/.85f)*DeepFace);
}
void UOKHScenePanel::TickAhegao(){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||!Girl->Session.IsOpen())return;
    const bool bWant=bAhegaoShown;
    if(!bWant){if(bAhegaoPose){bAhegaoPose=false;SyncPair();Girl->Session.SetStudioIk({},{});bHerIk=false;HandHeld.Reset();AheHandAt.Reset();Girl->SetMouthOpenHeld(-1.f);Girl->SetMouthOpenFloor(0.f);AheGazeFor=nullptr;Girl->bManualSpeechPattern=bAheManualWas;
            if(bAheEyeLook){bAheEyeLook=false;if(bAheEyeFollow)Girl->FollowEyeLookCamera(AheEyePattern);else Girl->SetEyeLookTarget(AheEyeTarget,AheEyePattern,true);}
            SyncPair();for(int32 Side=0;Side<2;++Side){const int32 P=HandPattern[Side];Girl->SetHandShape(Side,P>=0,FMath::Max(0,P),FMath::Max(0,P),0.f);HandShown[Side]=P;}
            Girl->bHeadLookPoseDirty=true;UE_LOG(LogTemp,Display,TEXT("H scene: ahegao over, her hands back"));}
        return;}
    const int32 V=CVarHAhegaoHand.GetValueOnGameThread();
    if(!bAhegaoPose){bAhegaoPose=true;bAheManualWas=Girl->bManualSpeechPattern;
        SyncPair();if(V>=0)for(int32 Side=0;Side<2;++Side){Girl->SetHandShape(Side,true,V,V,0.f);HandShown[Side]=HandPattern[Side];}
        UE_LOG(LogTemp,Display,TEXT("H scene: ahegao, double peace (hand shape %d)"),V);}
    // Her eyes stay rolled up: her look at the camera would set her gaze again every frame; and her mouth open, the
    // tongue pattern is closed lips at mouth-open 0 (def_cl → name_op).
    if(Girl->bEyeLookTracking){bAheEyeLook=true;bAheEyeFollow=Girl->bEyeLookFollowCamera;AheEyePattern=Girl->EyeLookPattern;AheEyeTarget=Girl->EyeLookWorldTarget;Girl->StopEyeLookTracking();}
    // Her gaze up, kept here (the actor holds only -1..1); given again whenever another look (her eye tracking, started
    // again elsewhere) has set her gaze since.
    const float Depth=bAheDepth?DeepFace:1.f; // in her it goes with how deep he is (TickDeepFace), in steps: the gaze is not free to set
    const float Gaze=FMath::RoundToFloat(CVarHAhegaoGaze.GetValueOnGameThread()*Depth*20.f)/20.f;if(AheGazeFor.Get()!=Girl||AheGazeSet!=Gaze||!FMath::IsNearlyEqual(Girl->EyeGaze[2],FMath::Clamp(Gaze,-1.f,1.f),.001f)){SyncPair();if(Girl->SetEyeGaze(0.f,0.f,Gaze)){AheGazeFor=Girl;AheGazeSet=Gaze;}}
    // Held, not a floor, in her: her moans would open it past how deep he is (TickDeepFace).
    if(bAheDepth){Girl->SetMouthOpenFloor(0.f);Girl->SetMouthOpenHeld(FMath::Min(1.f,CVarHAhegaoMouthOpen.GetValueOnGameThread()/.85f)*Depth);}else{Girl->SetMouthOpenHeld(-1.f);Girl->SetMouthOpenFloor(CVarHAhegaoMouthOpen.GetValueOnGameThread());}
    // Her breathing lines change her mouth by the original's face list; her tongue stays out (and comes back after them).
    if(AheMouthSet!=INDEX_NONE){Girl->bManualSpeechPattern=true;Girl->SavedMouthPattern=AheMouthSet;if(Girl->MouthPattern!=AheMouthSet)Girl->SetMouthPattern(AheMouthSet);}
    if(!CVarHAhegaoArms.GetValueOnGameThread()){if(AheHandAt.Num()){AheHandAt.Reset();HoldFeet(Girl,false,FVector::ZeroVector,HerFeet,HerHeld,bHerIk);}return;}
    if(!Girl->bStudioIkReady){FString Error;if(!Girl->Session.PrepareStudioIk(Error)){UE_LOG(LogTemp,Warning,TEXT("H scene: no IK for her double peace: %s"),*Error);CVarHAhegaoArms->Set(0);return;}Girl->bStudioIkReady=true;}
    FVector Head,Hips,L,R,Front;
    if(!HBone(Girl,TEXT("j_head"),Head)||!HBone(Girl,TEXT("j_hips"),Hips)||!HBone(Girl,TEXT("j_shoulder_L"),L)||!HBone(Girl,TEXT("j_shoulder_R"),R))return;
    const FVector Up=(Head-Hips).GetSafeNormal();FVector Side=(L-R);Side-=Up*FVector::DotProduct(Side,Up);Side.Normalize();
    if(!HChestForward(Girl,Front)){Front=FVector::CrossProduct(Up,(R-L).GetSafeNormal());}
    Front-=Up*FVector::DotProduct(Front,Up);Front.Normalize();
    TArray<FString> P;CVarHAhegaoReach.GetValueOnGameThread().ParseIntoArray(P,TEXT(","));const float Out=P.IsValidIndex(0)?FCString::Atof(*P[0]):13.f,Fwd=P.IsValidIndex(1)?FCString::Atof(*P[1]):9.f,Rise=P.IsValidIndex(2)?FCString::Atof(*P[2]):-1.f;
    const FTransform& T=Girl->GetActorTransform();
    const FVector AtL=Head+Side*Out+Front*Fwd+Up*Rise,AtR=Head-Side*Out+Front*Fwd+Up*Rise;
    // Her hands go in the one set of targets HoldFeet gives her (setting any replaces the rest: standing lowered, her held
    // feet and these took turns and her hands went up and down, user 2026-11-04). Eased: her head is moved by the pull of her
    // own hands, read a frame late it would shake them.
    const FVector WantAt[2]={AKKPreviewActor::ActorLocalToUnity(T.InverseTransformPosition(AtL)),AKKPreviewActor::ActorLocalToUnity(T.InverseTransformPosition(AtR))};
    if(AheHandAt.Num()!=2)AheHandAt={WantAt[0],WantAt[1]};
    else{const float Delta=GetWorld()?GetWorld()->GetDeltaSeconds():.016f;for(int32 Hand=0;Hand<2;++Hand)AheHandAt[Hand]=FMath::VInterpTo(AheHandAt[Hand],WantAt[Hand],Delta,10.f);}
    if(Mode==0||!bFeetRead)HoldFeet(Girl,false,FVector::ZeroVector,HerFeet,HerHeld,bHerIk); // otherwise AlignPair's turn
    Girl->bHeadLookPoseDirty=true;
}
// The light comes from the camera at them (user 2026-11-03): in the street their runtime materials light from the
// street's light (her raised hand fell in its dark band); in the H scene from the camera instead.
static TAutoConsoleVariable<int32> CVarHCameraLight(TEXT("ok.HScene.CameraLight"),1,TEXT("1: in the H scene their key light comes from the camera; 0: the street's light"));
// The panel's light rows (user 2026-11-04).
static TAutoConsoleVariable<int32> CVarHLightFrom(TEXT("ok.HScene.LightFrom"),0,TEXT("Their key light, by the camera: 0 from it, 1 left, 2 right, 3 above, 4 below, 5 behind them"));
static TAutoConsoleVariable<int32> CVarHLightTint(TEXT("ok.HScene.LightTint"),0,TEXT("The colour of their light: 0 white, 1 warm, 2 cold, 3 dusk, 4 night"));
static TAutoConsoleVariable<FString> CVarHLightRamp(TEXT("ok.HScene.LightRamp"),TEXT(""),TEXT("Their shadow ramp in the H scene (a key of OKRenderRamps); empty: as they came in"));
constexpr int32 HLightFromStreet=6;
void UOKHScenePanel::TickLightChoice(bool bEnd){
    static const FLinearColor Tints[]={FLinearColor::White,FLinearColor(1.f,.84f,.62f),FLinearColor(.68f,.8f,1.f),FLinearColor(1.f,.58f,.42f),FLinearColor(.3f,.36f,.62f)};
    const FString Ramp=bEnd?FString():CVarHLightRamp.GetValueOnGameThread();const int32 Tint=bEnd?0:FMath::Clamp(CVarHLightTint.GetValueOnGameThread(),0,int32(UE_ARRAY_COUNT(Tints))-1);
    auto Show=[](UComboBoxString* Combo,int32 Index){if(Combo&&Combo->GetSelectedIndex()!=Index)Combo->SetSelectedIndex(Index);};
    Show(LightCombos[0],LightRampKeys.IndexOfByKey(Ramp)+1);Show(LightCombos[1],CVarHCameraLight.GetValueOnGameThread()?FMath::Clamp(CVarHLightFrom.GetValueOnGameThread(),0,HLightFromStreet-1):HLightFromStreet);Show(LightCombos[2],Tint);
    FString Error;UTexture2D* RampTexture=Ramp.IsEmpty()?nullptr:OKLoadRenderRamp(Ramp,Error);
    const bool bRampMoved=Ramp!=RampShown,bTintMoved=Tint!=TintShown;RampShown=Ramp;TintShown=Tint;
    if(bRampMoved&&!RampTexture){for(const auto& Was:RampWas)if(UMaterialInstanceDynamic* M=Was.Key.Get())if(UTexture* Own=Was.Value.Get())M->SetTextureParameterValue(TEXT("_RampG"),Own);RampWas.Reset();}
    if(bTintMoved&&!Tint){for(const auto& Was:LightColorWas)if(UMaterialInstanceDynamic* M=Was.Key.Get())M->SetVectorParameterValue(TEXT("_LightColor0"),Was.Value);LightColorWas.Reset();}
    if(!RampTexture&&!Tint)return;
    // Every tick: a change of clothes brings new materials.
    for(AKKPreviewActor* A:{Gallery?Gallery->PreviewActor.Get():nullptr,Gallery?Gallery->PartnerActor.Get():nullptr})if(IsValid(A)){
        TInlineComponentArray<UMeshComponent*> Meshes(A);
        for(UMeshComponent* Mesh:Meshes)for(int32 MatSlot=0;MatSlot<Mesh->GetNumMaterials();++MatSlot)if(auto* M=Cast<UMaterialInstanceDynamic>(Mesh->GetMaterial(MatSlot))){
            if(RampTexture){const bool bKnown=RampWas.Contains(M);UTexture* Own=nullptr;if(bKnown||M->GetTextureParameterValue(FHashedMaterialParameterInfo(TEXT("_RampG")),Own)){if(!bKnown)RampWas.Add(M,Own);if(bRampMoved||!bKnown)M->SetTextureParameterValue(TEXT("_RampG"),RampTexture);}}
            if(Tint){const bool bKnown=LightColorWas.Contains(M);FLinearColor Own;if(bKnown||M->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("_LightColor0")),Own)){if(!bKnown)LightColorWas.Add(M,Own);if(bTintMoved||!bKnown)M->SetVectorParameterValue(TEXT("_LightColor0"),Tints[Tint]);}}}}
}
void UOKHScenePanel::OnLightStyle(FString,ESelectInfo::Type How){
    if(How==ESelectInfo::Direct||!LightCombos[0])return;const int32 I=LightCombos[0]->GetSelectedIndex()-1;
    if(auto* Var=HSettingVar(TEXT("LightRamp")))Var->Set(LightRampKeys.IsValidIndex(I)?*LightRampKeys[I]:TEXT(""),ECVF_SetByConsole);HSettingsSave();
}
void UOKHScenePanel::OnLightFrom(FString,ESelectInfo::Type How){
    if(How==ESelectInfo::Direct||!LightCombos[1])return;const int32 I=LightCombos[1]->GetSelectedIndex();
    HSettingSet(TEXT("CameraLight"),I==HLightFromStreet?0.f:1.f);if(I!=HLightFromStreet)HSettingSet(TEXT("LightFrom"),I);HSettingsSave();
    for(UOKHSettingSlider* Slider:SettingSliders)if(Slider)Slider->Show();
}
void UOKHScenePanel::OnLightTint(FString,ESelectInfo::Type How){if(How!=ESelectInfo::Direct&&LightCombos[2]){HSettingSet(TEXT("LightTint"),LightCombos[2]->GetSelectedIndex());HSettingsSave();}}
void UOKHScenePanel::TickCameraLight(bool bEnd){
    TickLightChoice(bEnd);
    APlayerCameraManager* Camera=GetOwningPlayer()?GetOwningPlayer()->PlayerCameraManager.Get():nullptr;
    const bool bOn=!bEnd&&Camera&&CVarHCameraLight.GetValueOnGameThread()!=0;
    FVector ToLight=FVector::ZeroVector;
    if(bOn){const FRotationMatrix View(Camera->GetCameraRotation());const FVector Ahead=View.GetUnitAxis(EAxis::X),Right=View.GetUnitAxis(EAxis::Y),Up=View.GetUnitAxis(EAxis::Z);
        switch(CVarHLightFrom.GetValueOnGameThread()){case 1:ToLight=-Ahead-Right;break;case 2:ToLight=-Ahead+Right;break;case 3:ToLight=-Ahead*.5f+Up;break;case 4:ToLight=-Ahead*.5f-Up;break;case 5:ToLight=Ahead+Up*.3f;break;default:ToLight=-Ahead;}
        ToLight=ToLight.GetSafeNormal();}
    // Their runtime materials light by _WorldSpaceLightPos0 (Unity to-light: UE (x,y,z) is Unity (-x,z,y)), the street's
    // light: set from the camera while it moves, each material's own value given back at the end.
    if(bOn){const FLinearColor Unity(-ToLight.X,ToLight.Z,ToLight.Y,0.f);const bool bMoved=!ToLight.Equals(CameraLightShown,1e-4f);CameraLightShown=ToLight;
        for(AKKPreviewActor* A:{Gallery?Gallery->PreviewActor.Get():nullptr,Gallery?Gallery->PartnerActor.Get():nullptr})if(IsValid(A)){
            TInlineComponentArray<UMeshComponent*> Meshes(A);
            for(UMeshComponent* Mesh:Meshes)for(int32 MatSlot=0;MatSlot<Mesh->GetNumMaterials();++MatSlot)if(auto* M=Cast<UMaterialInstanceDynamic>(Mesh->GetMaterial(MatSlot))){
                const bool bKnown=CameraLightWas.Contains(M);if(!bKnown){FLinearColor Was;if(!M->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("_WorldSpaceLightPos0")),Was))continue;CameraLightWas.Add(M,Was);}
                if(bMoved||!bKnown)M->SetVectorParameterValue(TEXT("_WorldSpaceLightPos0"),Unity);}}}
    else if(CameraLightWas.Num()){for(const auto& Was:CameraLightWas)if(UMaterialInstanceDynamic* M=Was.Key.Get())M->SetVectorParameterValue(TEXT("_WorldSpaceLightPos0"),Was.Value);
        CameraLightWas.Reset();CameraLightShown=FVector::ZeroVector;}
    bCameraLit=bOn;
}
void UOKHScenePanel::UpdateFace(){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||Girl->GetFacePatternCount(1)<25||Girl->GetFacePatternCount(2)<12)return;
    const FString Cur=Current(),Base=Mode==0?Cur:HBase(Cur);const int32 L=Level();
    int32 Eye=8,Brow=2;float Open=.85f;
    // Worn out (her climaxes today at her limit) and still going: ahegao (user, 2026-11-01), her eyes half open and rolled
    // up, brows raised, mouth open with her tongue out. The card has no such eye pattern; it is the tere eyes with her
    // gaze up and the mouth pattern whose name has the tongue (name / sita).
    // Or four climaxes in this scene (user 2026-11-03: 高潮 4 次後啊黑顏，雙手比 ya、流口水、翻白眼、吐舌頭; TickAhegao).
    const int32 AheAt=CVarHAhegaoClimaxes.GetValueOnGameThread();
    // After her climaxes as the original: in a loop going fast, caress or insertion, not kissing (she has her normal face
    // between). Worn out for the day it shows whenever she is not refusing (user 2026-11-01).
    const bool bKiss=Mode==0&&(Base==TEXT("K_Loop")||Base==TEXT("K_Touch"));
    const bool bLoop=Mode==2?(HIsLoop(Base)||Base==TEXT("OLoop")||Base.Contains(TEXT("IN_"))):Mode==0&&TouchArea!=INDEX_NONE&&Queue.IsEmpty();
    const bool bAheHold=AheAt>0&&HerOrgasms>=AheAt&&!bKiss&&bLoop&&SpeedValue>=CVarHAhegaoSpeed.GetValueOnGameThread();
    const bool bAhegao=(HadEnough()||bAheHold||CVarHAhegaoTest.GetValueOnGameThread())&&!Cur.Contains(TEXT("Dislikes"));
    TArray<FString> AF;CVarHAhegaoFace.GetValueOnGameThread().ParseIntoArray(AF,TEXT(","));
    auto AheId=[&](int32 I,int32 Def,int32 Count){const int32 V=AF.IsValidIndex(I)?FCString::Atoi(*AF[I]):Def;return V>=0&&V<Count?V:INDEX_NONE;};
    // Her tongue out, given again when it changes.
    const int32 Tongue=bAhegao?HTongueMouth(Girl):INDEX_NONE;
    if(bAhegao!=bAhegaoShown||(bAhegao&&Tongue!=AheMouthSet)){bAhegaoShown=bAhegao;AheMouthSet=Tongue;
        if(bAhegao){if(Tongue!=INDEX_NONE)Girl->SetMouthPattern(Tongue);
            UE_LOG(LogTemp,Display,TEXT("H scene: ahegao (mouth %d %s)"),Tongue,Tongue!=INDEX_NONE?*Girl->GetMouthPatternLabel(Tongue):TEXT("none"));}
        else{Girl->SetEyeGaze(0.f,0.f,0.f);Girl->SetMouthPattern(0);}}
    if(bAhegao){const int32 Set=AF.IsValidIndex(0)?FCString::Atoi(*AF[0]):25;const int32 Blend=HEyeSetBlend(Set);
        const int32 E=Blend>=0&&Blend<Girl->GetFacePatternCount(1)?Blend:INDEX_NONE,B=AheId(1,2,Girl->GetFacePatternCount(2));Eye=E!=INDEX_NONE?E:8;Brow=B!=INDEX_NONE?B:11;Open=E!=INDEX_NONE?1.f:.6f;}
    else if(Cur.Contains(TEXT("Dislikes"))){Eye=13;Brow=1;Open=.9f;}
    else if(bDeepFace){Eye=8;Brow=11;Open=.85f;} // wide enough to see them roll (TickDeepFace)
    // Sucking him (her mouth developed, Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md): her eyes roll up under lids that fall
    // the harder she sucks (her gaze up alone hardly showed, 2026-11-02); in steps, not every frame.
    else if(Mode==1&&OralSuck>.3f){Eye=8;Brow=11;Open=FMath::GridSnap(FMath::Lerp(.85f,.45f,OralSuck),.05f);}
    else if(Mode==0&&(Base==TEXT("K_Loop")||Base==TEXT("K_Touch"))){Eye=1;Brow=2;Open=0.f;}
    else if(Base.StartsWith(TEXT("Orgasm"))||(Mode!=0&&!HIsLoop(Base)&&StateWords(Base)==OKT(TEXT("ui.hscene.state_finishing")))){Eye=24;Brow=2;Open=0.f;}
    else if(StateWords(Base)==OKT(TEXT("ui.hscene.state_after"))){Eye=7;Brow=2;Open=.45f;}
    else if(Base==TEXT("OLoop")||Her>=70.f){Eye=12;Brow=11;Open=.5f;}
    else if(Base==TEXT("SLoop")||Base==TEXT("WLoop")||(Mode==0&&TouchArea!=INDEX_NONE)){Eye=L>=3?8:7;Brow=L<=1?11:2;Open=Base==TEXT("SLoop")?.55f:.7f;}
    else if(Base==TEXT("Insert")||Base==TEXT("InsertIdle")){Eye=L<=1?12:8;Brow=L<=1?11:2;Open=.7f;}
    else if(L>=2){Eye=4;Brow=0;Open=.9f;}
    const FString Key=FString::Printf(TEXT("%d/%d/%.2f"),Eye,Brow,Open);if(Key==FaceKey)return;FaceKey=Key;
    Girl->SetFaceControl(1,Eye,Open,true);Girl->SetFaceControl(2,Brow,1.f,true);
}
void UOKHScenePanel::UpdateBlush(float Delta){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return;
    static const FName Alpha(TEXT("_overcolor2__A")),Color(TEXT("_overcolor2"));
    if(BlushFor!=Girl){RestoreBlush();BlushFor=Girl;Blush=BlushShown=-1.f;
        TInlineComponentArray<UMeshComponent*> Comps;Girl->GetComponents(Comps);
        for(UMeshComponent* Comp:Comps)for(const FName& Tag:Comp->ComponentTags){const FString T=Tag.ToString();if(!T.StartsWith(TEXT("KKSessionPart_")))continue;
            OkMeshView V{};if(!Girl->Session.PartAt(FCString::Atoi(*T.Mid(14)),V)||!V.name||FString(UTF8_TO_TCHAR(V.name)).ToLower()!=TEXT("cf_o_face"))break;
            for(int32 I=0;I<Comp->GetNumMaterials();++I)if(auto* M=Cast<UMaterialInstanceDynamic>(Comp->GetMaterial(I))){float A=0.f;
                if(M->GetScalarParameterValue(FHashedMaterialParameterInfo(Alpha),A)){BlushMats.Add(M);BlushBase.Add(A);}}
            break;}
        if(BlushMats.IsEmpty()&&!bBlushLogged){bBlushLogged=true;UE_LOG(LogTemp,Warning,TEXT("H scene: her face has no live blush parameter (_overcolor2__A); her cheeks stay as her card has them"));}
    }
    if(BlushMats.IsEmpty())return;
    const FString Base=Mode==0?Current():HBase(Current());
    // Her gauge; flushed through the afterglow, and once she has come a little stays for the rest of the scene.
    float Target=Base.StartsWith(TEXT("Orgasm"))?1.f:FMath::Clamp(Her/100.f,0.f,1.f);
    if(Mode!=0&&StateWords(Base)==OKT(TEXT("ui.hscene.state_after")))Target=FMath::Max(Target,.7f);
    if(HerOrgasms>0)Target=FMath::Max(Target,.35f);
    // Up in a few seconds, down over twenty: the flush outlasts the moment.
    Blush=BlushTest>=0.f?BlushTest:Blush<0.f?Target:Target>Blush?FMath::Min(Target,Blush+Delta*.5f):FMath::Max(Target,Blush-Delta*.05f);
    const float Shown=FMath::RoundToFloat(Blush*40.f)/40.f;if(Shown==BlushShown)return;BlushShown=Shown;
    for(int32 I=0;I<BlushMats.Num();++I)if(IsValid(BlushMats[I])){const float A=FMath::Lerp(BlushBase[I],FMath::Max(BlushBase[I],.2f),Shown);
        BlushMats[I]->SetScalarParameterValue(Alpha,A);FLinearColor C;if(BlushMats[I]->GetVectorParameterValue(FHashedMaterialParameterInfo(Color),C)){C.A=A;BlushMats[I]->SetVectorParameterValue(Color,C);}}
}
void UOKHScenePanel::RestoreBlush(){
    for(int32 I=0;I<BlushMats.Num();++I)if(IsValid(BlushMats[I])){BlushMats[I]->SetScalarParameterValue(TEXT("_overcolor2__A"),BlushBase[I]);
        FLinearColor C;if(BlushMats[I]->GetVectorParameterValue(FHashedMaterialParameterInfo(TEXT("_overcolor2")),C)){C.A=BlushBase[I];BlushMats[I]->SetVectorParameterValue(TEXT("_overcolor2"),C);}}
    BlushMats.Reset();BlushBase.Reset();BlushFor=nullptr;
}
bool UOKHScenePanel::NewPosePlays(double Now) const{
    if(Now>CoverAt+3.)return true; // never held black: a pose that does not start shows what there is
    if(Mode==0||bPlaceOnly)return Now>CoverAt+.2;
    auto* Playback=Gallery?Gallery->PairedPlayback.Get():nullptr;if(!Playback)return false;
    // The new pose is committed: another player, its clip or motion changed, or its clock started again. A place change
    // keeps the pose: its props are what changes.
    return Playback!=CoverPlayback.Get()||Playback->GetFemaleClip()+Playback->GetFemaleMotion()!=CoverClip||Playback->GetElapsed()<CoverElapsed-.01f;
}
void UOKHScenePanel::Cover(bool bOn,double Now){
    APlayerCameraManager* Camera=GetOwningPlayer()?GetOwningPlayer()->PlayerCameraManager.Get():nullptr;
    if(bOn){CoverAt=Now;CoverPlayback=SeenPlayback;CoverElapsed=SeenElapsed;CoverClip=SeenClip;}
    else if(bCovered)UE_LOG(LogTemp,Display,TEXT("H scene: new pose shown %.2fs after the change"),Now-CoverAt);
    if(!Camera){bCovered=false;return;}
    bCovered=bOn;
    if(bOn)Camera->StartCameraFade(1.f,1.f,0.f,FLinearColor::Black,false,true); // black this very frame: the jump is never seen
    else Camera->StartCameraFade(1.f,0.f,.35f,FLinearColor::Black,false,false);
}
static bool HBone(AKKPreviewActor* A,const TCHAR* Name,FVector& Out);
float UOKHScenePanel::HerDesire() const{const auto& X=Gallery?Gallery->HExperience:nullptr;double D=0;if(X.IsValid())X->TryGetNumberField(TEXT("sex_desire"),D);return float(D);}
// Her desire for him past 100 (user, 2026-11-01): all through the scene her crotch runs clear and both nipples leak
// milk, more the higher her desire, the nipples more the bigger her bust. They fall to whatever is under her (bed,
// floor; past her and him) and lie there until the room closes.
bool UOKHScenePanel::StreetOnani() const{bool On=false;return Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetBoolField(TEXT("street_onani"),On)&&On;}
void UOKHScenePanel::TickDrips(float Delta){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;
    auto Where=[Girl](int32,FName Bone,FVector& At){return IsValid(Girl)&&HBone(Girl,*Bone.ToString(),At);};
    const float Desire=HerDesire();const double Now=FPlatformTime::Seconds();
    const AActor* Ignore[]={Girl,Gallery?Gallery->PartnerActor.Get():nullptr};
    // Taken from touching herself on the street (her desire at 200, OKStreetSocialOnani.inl; user 2026-11-03): her breasts
    // and crotch run and spray twice as much.
    const float More=StreetOnani()?2.f:1.f;
    // What fell due since the last frame comes out now: at one drop a frame a slow frame caps every rate and her development
    // does not show (at 15 FPS she squirted as much at 100 as at 0).
    auto Due=[Now](double& At,auto Gap,auto Emit){for(int32 N=0;N<4&&Now>=At;++N){At=FMath::Max(At,Now-.1)+Gap();Emit();}};
    auto Drop=[&](const TCHAR* Bone,uint8 Colour){FVector At,L,R;if(!HBone(Girl,Bone,At))return false;
        // Nothing under her: her lowest foot is the floor.
        const float Floor=HBone(Girl,TEXT("j_foot_L"),L)&&HBone(Girl,TEXT("j_foot_R"),R)?FMath::Min(L.Z,R.Z)-3.f:At.Z-80.f;
        return Drips.Spawn(Girl,0,Bone,At,FOKArousalDrops::GroundBelow(Girl,At-FVector(0,0,4.f),Ignore,Floor),Colour);};
    // Between her breasts (the chest service, user 2026-11-02): her nipples run milk as he rubs, whatever her desire,
    // the more the more they are developed: none undeveloped, a drop every 2.4 s at 5, eight a second at 100 (both
    // nipples together), quicker the faster they move.
    const FString Base=HBase(Current());
    const bool bPaizuri=Mode==1&&Poses.IsValidIndex(ActivePose)&&Poses[ActivePose].KindHoushi==2&&Gallery->PairedPlayback&&Gallery->PairedPlayback->GetElapsed()>0.f&&(HIsLoop(Base)||Base==TEXT("OLoop"));
    if(IsValid(Girl)&&bPaizuri&&!bCovered&&Dev(TEXT("nipple"))>=.05f)
        Due(PaizuriMilkAt,[&]{return .12f/Dev(TEXT("nipple"))/FMath::Clamp(.6f+.4f*PlaybackSpeed(),.6f,2.f)/More*FMath::FRandRange(.8f,1.2f);},
            [&]{if(Drop(++MilkTurn%2?TEXT("j_bnip02_L"):TEXT("j_bnip02_R"),OKArousal::White)){++HerMilk;if(Now-MilkBoutAt>3.)++HerMilkTimes;MilkBoutAt=Now;}});
    if(IsValid(Girl)&&Desire>OKArousal::DesireFlush&&!bCovered){
        const auto& X=Gallery->HExperience;double Bust=0;if(X.IsValid())X->TryGetNumberField(TEXT("bust"),Bust);
        // Developed, more of it (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md): her crotch up to twice, her nipples three times.
        Due(DripAt,[&]{return OKArousal::CrotchInterval(Desire)/(1.f+Dev(TEXT("crotch")))/More*FMath::FRandRange(.8f,1.2f);},[&]{if(Drop(TEXT("J_Kokan"),OKArousal::Clear)){++HerDrips;if(Now-DripBoutAt>3.)++HerDripTimes;DripBoutAt=Now;}});
        Due(MilkAt,[&]{return OKArousal::NippleInterval(Desire,float(Bust))*.5f/(1.f+2.f*Dev(TEXT("nipple")))/More*FMath::FRandRange(.8f,1.2f);},[&]{if(Drop(++MilkTurn%2?TEXT("j_bnip02_L"):TEXT("j_bnip02_R"),OKArousal::White)){++HerMilk;if(Now-MilkBoutAt>3.)++HerMilkTimes;MilkBoutAt=Now;}});
    }
    // Sucking him, tears run down her cheeks, the more the more her mouth is developed (H_DEVELOPMENT_EXPERIENCE_PLAN):
    // one eye then the other. Their way down her face is read from her session while it is idle (SpawnTears).
    if(IsValid(Girl)&&OralSuck>.15f&&Now>=TearAt){TearAt=Now+2.2/OralSuck*FMath::FRandRange(.7f,1.3f);TearsWanted|=FMath::RandBool()?1:2;}
    if(TearsWanted&&!IsValid(Gallery->PairedPlayback.Get()))SpawnTears(Girl);
    {FVector Eye=FVector::ZeroVector;if(auto* PC=GetOwningPlayer();PC&&PC->PlayerCameraManager)Eye=PC->PlayerCameraManager->GetCameraLocation();Tears.Tick(Delta,Eye);}
    // As she comes (her cry, ClimaxUntil; user 2026-11-01): her crotch squirts and both nipples spray, shot out from her,
    // whatever her desire. In her anus too it is her vagina that squirts, as much as her crotch is developed (user 2026-11-03).
    // Each has its own clock (user 2026-11-04): her crotch by her crotch, her nipples by her nipples, as much more as her milk.
    if(IsValid(Girl)&&Now<FMath::Max(ClimaxUntil,NippleUntil)){
        FVector Kokan,Hips,Chest,L,R;
        auto Floor=[&](const FVector& At){return HBone(Girl,TEXT("j_foot_L"),L)&&HBone(Girl,TEXT("j_foot_R"),R)?FMath::Min(L.Z,R.Z)-3.f:At.Z-80.f;};
        auto Shoot=[&](const FVector& At,const FVector& Out,float Speed,uint8 Colour){const FVector V=(Out+FMath::VRand()*.3f).GetSafeNormal()*Speed*FMath::FRandRange(.7f,1.2f);
            return Drips.Squirt(Girl,0,At,V,FOKArousalDrops::GroundBelow(Girl,At-FVector(0,0,4.f),Ignore,Floor(At)),Colour);};
        if(Now<ClimaxUntil)Due(SquirtAt,[&]{return .05/(1.f+(Mode==2?Dev(TEXT("crotch")):0.f))/More;},[&]{
            if(HBone(Girl,TEXT("J_Kokan"),Kokan)&&HBone(Girl,TEXT("j_hips"),Hips)&&Shoot(Kokan,(Kokan-Hips).GetSafeNormal(),200.f,OKArousal::Clear)){++HerDrips;if(Now-DripBoutAt>3.)++HerDripTimes;DripBoutAt=Now;}});
        Due(NippleSprayAt,[&]{return .05/(1.f+2.f*Dev(TEXT("nipple")))/More;},[&]{
            if(HBone(Girl,TEXT("j_spine03"),Chest))for(const TCHAR* Nipple:{TEXT("j_bnip02_L"),TEXT("j_bnip02_R")}){FVector At;
                if(HBone(Girl,Nipple,At)&&Shoot(At,(At-Chest).GetSafeNormal(),110.f,OKArousal::White)){++HerMilk;if(Now-MilkBoutAt>3.)++HerMilkTimes;MilkBoutAt=Now;}}});
    }
    Drips.Tick(Delta,Where);
}
// What runs on her body by the water gun (AOKPaintSprayer: it sticks, runs down her and drips to the floor;
// Docs/H_SCENE_ADDITIONS_PLAN.md 1, 2, 9), one stream at a time, the first that has something to say:
//  1. his coming outside her or on her (Spurt: pulses from his glans along him);
//  2. out of her after he came in her without a condom, once he is out of her (more the more times, each less);
//  3. what she spits out of her mouth (Vomit);
//  4. kissing, her saliva from a corner of her mouth, more the more her kissing is developed.
// Her tongue comes out kissing past 40% of it (the mouth pattern with the tongue, as the worn-out face).
static TAutoConsoleVariable<int32> CVarHSiruTexture(TEXT("ok.HScene.SiruTexture"),0,TEXT("1: the original's semen textures on her (_liquid*) as well as the water gun"));
static TAutoConsoleVariable<FString> CVarHFluid(TEXT("ok.HScene.Fluid"),TEXT("520,40,0.35,0.17,40,5,1.5,0.7"),TEXT("Water gun: spurt speed, spurt flow, pulse seconds, gap seconds, leak seconds first time, leak flow, drool flow, drool brush cm"));
void UOKHScenePanel::Spurt(int32 Pulses){SpurtLeft=FMath::Max(SpurtLeft,Pulses);SpurtAt=FMath::Min(SpurtAt,FPlatformTime::Seconds());
    UE_LOG(LogTemp,Display,TEXT("H scene: he spurts %d times (water gun)"),Pulses);}
void UOKHScenePanel::TickFluids(float Delta){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;auto* Him=Gallery?Gallery->PartnerActor.Get():nullptr;if(!IsValid(Girl)||!GetWorld())return;
    TArray<float> F;{TArray<FString> P;CVarHFluid.GetValueOnGameThread().ParseIntoArray(P,TEXT(","));for(const FString& S:P)F.Add(FCString::Atof(*S));}
    while(F.Num()<8)F.Add(1.f);
    const double Now=FPlatformTime::Seconds();const FString Base=HBase(Current());
    if(!IsValid(Fluid)){Fluid=GetWorld()->SpawnActor<AOKPaintSprayer>();if(!IsValid(Fluid))return;Fluid->SetControlsVisible(false);Fluid->bShowGun=false;Fluid->bSkipTongue=!CVarHFluidTongue.GetValueOnGameThread();Fluid->SetActorTickEnabled(true);
        UE_LOG(LogTemp,Display,TEXT("H scene: water gun ready for her fluids"));}
    // Out of her: his semen she held runs out of where he came, starting as he is out of her.
    const bool In=Mode==2&&(Base.StartsWith(TEXT("Insert"))||HIsLoop(Base)||Base==TEXT("OLoop")||Base.Contains(TEXT("_IN"))||Base.EndsWith(TEXT("_Start"))||Base.EndsWith(TEXT("_Loop"))||Base==TEXT("IN_A"));
    if(LeakPending>0&&!In){const double For=F[4]*(1.+.6*(LeakPending-1));LeakUntil=FMath::Max(LeakUntil,Now)+For;LeakFor=For;LeakPending=0;
        UE_LOG(LogTemp,Display,TEXT("H scene: his semen runs out of her %s for %.0f s"),bLeakAnal?TEXT("anus"):TEXT("vagina"),For);}
    FVector O,D;float JetV=0.f,Flow=0.f;FLinearColor Colour(.96f,.96f,.92f,1.f);bool On=false,bThin=false; // thin: saliva, a line down her chin
    FVector Root,Tip;
    if(SpurtLeft>0&&Now>=SpurtAt&&IsValid(Him)&&HBone(Him,TEXT("J_dan100_00"),Root)){
        Tip=Root+(bGlans?GlansFromRoot:FVector(0,0,0));FVector T;if(!bGlans&&HBone(Him,TEXT("J_dan109_00"),T))Tip=T;
        if(Now>=SpurtAt+F[2]){--SpurtLeft;SpurtAt=Now+F[3];}
        else{O=Tip;D=(Tip-Root).GetSafeNormal();if(D.IsNearlyZero())D=FVector(0,0,-1);JetV=F[0];Flow=F[1];On=true;}
    }
    if(!On&&Now<LeakUntil&&!In){FVector Out,Hips;
        if(HBone(Girl,bLeakAnal?TEXT("J_Ana"):TEXT("J_Kokan"),Out)&&HBone(Girl,TEXT("j_hips"),Hips)){
            const float Left=float((LeakUntil-Now)/FMath::Max(1.,LeakFor));
            O=Out;D=((Out-Hips).GetSafeNormal()*.3f+FVector(0,0,-1)).GetSafeNormal();JetV=35.f;Flow=F[5]*FMath::Clamp(Left,.25f,1.f);On=true;}}
    if(!On&&Now<MouthSpillUntil){FVector M;if(HBone(Girl,TEXT("J_MouthCavity"),M)||HBone(Girl,TEXT("J_MouthBase_s"),M)){O=M;D=FVector(0,0,-1);JetV=25.f;Flow=F[5]*1.5f;On=true;}}
    // Kissing: her tongue and saliva.
    const bool bKissing=Mode==0&&(Base==TEXT("K_Loop")||Base==TEXT("K_Touch"));const float DK=Dev(TEXT("kiss"));
    const bool bTongue=bKissing&&DK>=.4f&&!bAhegaoShown;
    if(bTongue!=bKissTongue){bKissTongue=bTongue;
        if(bTongue){if(AhegaoMouth==INDEX_NONE)for(int32 P=0;P<Girl->GetMouthPatternCount();++P){const FString M=Girl->GetMouthPatternLabel(P).ToLower();if(M.Contains(TEXT("_name"))||M.Contains(TEXT("_sita"))){AhegaoMouth=P;break;}}
            if(AhegaoMouth!=INDEX_NONE)Girl->SetMouthPattern(AhegaoMouth);Girl->SetMouthOpenFloor(FMath::Lerp(.2f,.6f,DK));}
        else{if(!bAhegaoShown)Girl->SetMouthPattern(0);Girl->SetMouthOpenFloor(0.f);
            // Drawn apart from a kiss of hers developed past half: a string of saliva between them.
            if(DK>=.5f&&!bKissing)MouthDribbleUntil=Now+.6;}
        UE_LOG(LogTemp,Display,TEXT("H scene: kissing, her tongue %s (kiss %.0f%%)"),bTongue?TEXT("out"):TEXT("back"),DK*100.f);}
    if(!On&&CVarHDrool.GetValueOnGameThread()&&((bKissing&&DK>=.05f)||bAhegaoShown||Now<MouthDribbleUntil)){
        const float DR=bAhegaoShown?FMath::Max(DK,.8f):DK;
        if(Now>=DroolAt){DroolAt=Now+.6/FMath::Max(.05f,DR)*FMath::FRandRange(.8f,1.2f);DroolOnUntil=Now+.15;DroolTurn=!DroolTurn;}
        FVector M;if(Now<DroolOnUntil||Now<MouthDribbleUntil)if(HBone(Girl,DroolTurn?TEXT("J_Mouth_L"):TEXT("J_Mouth_R"),M)){
            // Over her lip and down her chin, the way nose to mouth runs: straight down from the bone it never touched her.
            FVector Cavity,Nose;O=M;D=FVector(0,0,-1);if(HBone(Girl,TEXT("J_MouthCavity"),Cavity)&&HBone(Girl,TEXT("J_Nose_tip"),Nose)){O=M+(M-Cavity).GetSafeNormal()*.6f;D=(M-Nose).GetSafeNormal();}
            JetV=15.f;Flow=F[6]*FMath::Max(.3f,DR);Colour=FLinearColor(.85f,.88f,.92f,.6f);On=bThin=true;}}
    if(On){Fluid->Settings.BrushRadius=bThin?F[7]:2.f;Fluid->Settings.JetSpeed=FMath::Max(10.f,JetV);Fluid->Settings.Flow=Flow;Fluid->Settings.Color=Colour;Fluid->SetSpray(true,O,D);}
    else if(Fluid->IsSpraying())Fluid->StopSpray();
}
// Her body shaking as she comes is her climax loop's own animation (user 2026-11-03: not the shake once made up here on
// top of it); left here, the pose he set on her (ApplyHerFk).
void UOKHScenePanel::Tremble(double Now){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return;
    // Once: what of her could open around him (her body's vagina bones and morphs), for opening her with him.
    if(!bVaginaLogged&&Girl->BodySkel){bVaginaLogged=true;TArray<FString> Found;
        for(int32 I=0;I<Girl->BodySkel->GetNumBones();++I){const FString N=Girl->BodySkel->GetBoneName(I).ToString();if(N.Contains(TEXT("agina"))||N.Contains(TEXT("okan"))||N.Contains(TEXT("Ana")))Found.Add(N);}
        UE_LOG(LogTemp,Display,TEXT("H scene: her vagina bones: %s"),*FString::Join(Found,TEXT(" ")));}
    TArray<FString> Names;TArray<FVector> Turns;
    ApplyHerFk(Girl,Names,Turns);
}
// The pose he set on her, after her trembling (both '+': on top of the animation). Set every frame while there is any,
// so a new self of hers (outfit change) or a new pair keeps it.
void UOKHScenePanel::ApplyHerFk(AKKPreviewActor* Girl,TArray<FString>& Names,TArray<FVector>& Turns){
    {const double Now=FPlatformTime::Seconds();if(Now<FlinchUntil&&!FlinchBone.IsEmpty()){const float T=1.f-float((FlinchUntil-Now)/.45);
        Names.Add(FlinchBone);Turns.Add(FlinchTurn*FMath::Sin(T*PI));Girl->bHeadLookPoseDirty=true;}}
    if(!FMath::IsNearlyZero(AnkleTurn))for(const TCHAR* Bone:{TEXT("+cf_j_leg03_L"),TEXT("+cf_j_leg03_R")}){Names.Add(Bone);Turns.Add(FVector(AnkleTurn,0.f,0.f));}
    // Opening is out to her own side: the left thigh turns one way about its forward axis, the right the other.
    if(!FMath::IsNearlyZero(ThighOpen[0])){Names.Add(TEXT("+cf_j_thigh00_L"));Turns.Add(FVector(0.f,0.f,-ThighOpen[0]));}
    if(!FMath::IsNearlyZero(ThighOpen[1])){Names.Add(TEXT("+cf_j_thigh00_R"));Turns.Add(FVector(0.f,0.f,ThighOpen[1]));}
    // Changed while the pair is paused: the paused pair solves one more frame (it only does for a reason to).
    const FVector4f Set(AnkleTurn,ThighOpen[0],ThighOpen[1],0.f);if(Set!=HerPoseShown){HerPoseShown=Set;Girl->bHeadLookPoseDirty=true;}
    if(!Names.IsEmpty()){Girl->Session.SetFk(Names,Turns);bTrembling=true;}
    else if(bTrembling){Girl->Session.SetFk({},{});bTrembling=false;}
}
// As in the source's H, her eyes are on the camera (user 2026-11-03): set once for each self of hers that is shown, so
// unticking it on the panel (the eye look box) leaves them; the ahegao keeps and gives back what it found.
static TAutoConsoleVariable<int32> CVarHEyesCamera(TEXT("ok.HScene.EyesCamera"),1,TEXT("1: in H her eyes follow the camera from the start (the panel's eye look box can turn it off)"));
bool UOKHScenePanel::HEyesOnCamera() const{return CVarHEyesCamera.GetValueOnGameThread()!=0;}
void UOKHScenePanel::TickEyesCamera(){
    AKKPreviewActor* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;
    // Her head as the button on the right has it (user 2026-11-04), given to whichever self of hers is shown.
    if(IsValid(Girl)&&Girl->StudioCam&&HeadCameraGirl.Get()!=Girl){HeadCameraGirl=Girl;SyncPair();Girl->FollowHeadLookCamera(bHeadCamera);}
    if(!IsValid(Girl)||EyesCameraGirl.Get()==Girl||!CVarHEyesCamera.GetValueOnGameThread()||!Girl->StudioCam)return;
    EyesCameraGirl=Girl;if(bAhegaoShown||Girl->bEyeLookTracking)return;
    const bool On=Girl->FollowEyeLookCamera(Girl->Session.EyeLookPatternCount()>1?1:0);
    if(On&&Gallery->EyeLookCameraCheck)Gallery->EyeLookCameraCheck->SetIsChecked(true);
    UE_LOG(LogTemp,Display,TEXT("H scene: her eyes on the camera %s"),On?TEXT("on"):TEXT("unavailable"));
}
// Her hands as he set them: given again to whichever self of hers is shown (an outfit change makes a new one).
static TAutoConsoleVariable<int32> CVarHSuckGripHand(TEXT("ok.HScene.SuckGripHand"),6,TEXT("The hand pattern of a hand holding him at a blowjob (the fingers closed round him; -1 as the motion)."));
void UOKHScenePanel::TickHands(){
    AKKPreviewActor* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return;
    const int32 Count=Girl->GetHandShapeCount();
    if(Count!=HandOptions)for(int32 Side=0;Side<2;++Side)if(UComboBoxString* C=HandCombos[Side]){
        C->ClearOptions();C->AddOption(OKT(TEXT("ui.hscene.hand_follow")));for(int32 P=0;P<Count;++P)C->AddOption(OKMsg(TEXT("ui.hscene.hand_pattern"),{{TEXT("n"),P}}));
        HandPattern[Side]=FMath::Clamp(HandPattern[Side],-1,Count-1);C->SetSelectedIndex(HandPattern[Side]+1);}
    HandOptions=Count;
    const bool bNew=HandGirl.Get()!=Girl;HandGirl=Girl;
    {const float Tongue=CVarHTongueLength.GetValueOnGameThread();if(!FMath::IsNearlyEqual(Tongue,Girl->TongueLength,.001f)){SyncPair();Girl->SetTongueLength(Tongue);}if(TongueSlider&&!FMath::IsNearlyEqual(TongueSlider->GetValue(),Tongue,.001f))TongueSlider->SetValue(Tongue);}
    const double Now=FPlatformTime::Seconds();
    for(int32 Side=0;Side<2;++Side){const int32 P=HandPattern[Side]<0&&!bAhegaoPose&&Now<GripUntil[Side]?FMath::Min(CVarHSuckGripHand.GetValueOnGameThread(),Count-1):HandPattern[Side];if(bNew?P<0:HandShown[Side]==P)continue;
        SyncPair(); // the pair's worker is on her session: setting a hand under it killed the game without a trace
        if(Girl->SetHandShape(Side,P>=0,FMath::Max(0,P),FMath::Max(0,P),0.f)){HandShown[Side]=P;Girl->bHeadLookPoseDirty=true;}}
}
void UOKHScenePanel::SetHerPose(const float* Ankle,const float* ThighL,const float* ThighR,const int32* HandL,const int32* HandR){
    if(Ankle){AnkleTurn=FMath::Clamp(*Ankle,-60.f,60.f);if(AnkleSlider)AnkleSlider->SetValue(AnkleTurn);}
    if(ThighL){ThighOpen[0]=FMath::Clamp(*ThighL,-30.f,60.f);if(ThighSliders[0])ThighSliders[0]->SetValue(ThighOpen[0]);}
    if(ThighR){ThighOpen[1]=FMath::Clamp(*ThighR,-30.f,60.f);if(ThighSliders[1])ThighSliders[1]->SetValue(ThighOpen[1]);}
    const int32* Hands[2]={HandL,HandR};
    for(int32 Side=0;Side<2;++Side)if(Hands[Side]){HandPattern[Side]=FMath::Max(-1,*Hands[Side]);if(HandOptions>=0)HandPattern[Side]=FMath::Min(HandPattern[Side],HandOptions-1);
        if(HandCombos[Side])HandCombos[Side]->SetSelectedIndex(HandPattern[Side]+1);}
}
void UOKHScenePanel::OnTongueLength(float Value){HSettingSet(TEXT("TongueLength"),Value);HSettingsSave();for(UOKHSettingSlider* Slider:SettingSliders)if(Slider)Slider->Show();}
void UOKHScenePanel::OnAnkle(float Value){AnkleTurn=Value;}
void UOKHScenePanel::OnThighL(float Value){ThighOpen[0]=Value;}
void UOKHScenePanel::OnThighR(float Value){ThighOpen[1]=Value;}
void UOKHScenePanel::OnHandL(FString,ESelectInfo::Type How){if(How!=ESelectInfo::Direct&&HandCombos[0])HandPattern[0]=HandCombos[0]->GetSelectedIndex()-1;}
void UOKHScenePanel::OnHandR(FString,ESelectInfo::Type How){if(How!=ESelectInfo::Direct&&HandCombos[1])HandPattern[1]=HandCombos[1]->GetSelectedIndex()-1;}
void UOKHScenePanel::AddSiru(int32 Area){
    if(Area<0||Area>4)return;Siru[Area]=FMath::Min(2,Siru[Area]+1);if(CVarHSiruTexture.GetValueOnGameThread())ApplySiru();
    UE_LOG(LogTemp,Display,TEXT("H scene: semen on her %d (levels %d %d %d %d %d)"),Area,Siru[0],Siru[1],Siru[2],Siru[3],Siru[4]);
}
void UOKHScenePanel::ApplySiru(){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return;
    static const FName Names[5]={TEXT("_liquidface"),TEXT("_liquidftop"),TEXT("_liquidfbot"),TEXT("_liquidbtop"),TEXT("_liquidbbot")};
    TInlineComponentArray<UMeshComponent*> Comps;Girl->GetComponents(Comps);
    for(UMeshComponent* Comp:Comps)for(int32 I=0;I<Comp->GetNumMaterials();++I)if(auto* M=Cast<UMaterialInstanceDynamic>(Comp->GetMaterial(I)))
        for(int32 A=0;A<5;++A){float Was=0.f;if(M->GetScalarParameterValue(FHashedMaterialParameterInfo(Names[A]),Was)&&Was!=float(Siru[A]))M->SetScalarParameterValue(Names[A],float(Siru[A]));}
}
void UOKHScenePanel::SetSiruTest(const int32 (&Levels)[5]){for(int32 A=0;A<5;++A)Siru[A]=FMath::Clamp(Levels[A],0,2);ApplySiru();}
TArray<FString> UOKHScenePanel::LiquidReport() const{
    TArray<FString> Out;auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl))return Out;
    TInlineComponentArray<UMeshComponent*> Comps;Girl->GetComponents(Comps);
    auto Name=[](UMaterialInstanceDynamic* M,const TCHAR* P){UTexture* T=nullptr;return M->GetTextureParameterValue(FHashedMaterialParameterInfo(P),T)&&T?FString::Printf(TEXT("%s(%dx%d)"),*T->GetName(),int32(T->GetSurfaceWidth()),int32(T->GetSurfaceHeight())):FString(TEXT("-"));};
    // Which of her session's parts carry the liquid textures at all (the renderer can only bind what the open made).
    for(int32 P=0;P<Girl->Session.PartCount();++P){OkMeshView V{};const uint8* Bytes=nullptr;int32 Length=0;
        if(Girl->Session.PartAt(P,V)&&Girl->Session.ShaderTexture(P,"_liquidmask",Bytes,Length))
            Out.Add(FString::Printf(TEXT("session part %d %s/%s liquidmask=%d"),P,UTF8_TO_TCHAR(V.role?V.role:""),UTF8_TO_TCHAR(V.name?V.name:""),Length));}
    for(UMeshComponent* Comp:Comps)for(int32 I=0;I<Comp->GetNumMaterials();++I)if(auto* M=Cast<UMaterialInstanceDynamic>(Comp->GetMaterial(I))){
        float Top=0.f;if(!M->GetScalarParameterValue(FHashedMaterialParameterInfo(TEXT("_liquidftop")),Top))continue;
        Out.Add(FString::Printf(TEXT("%s#%d %s ftop=%g mask=%s tex2=%s tex3=%s"),*Comp->GetName(),I,M->Parent?*M->Parent->GetName():TEXT("?"),Top,*Name(M,TEXT("_liquidmask")),*Name(M,TEXT("_Texture2")),*Name(M,TEXT("_Texture3"))));}
    return Out;
}
int32 UOKHScenePanel::SiruSide() const{
    // 0 when he is on her front (her face turns toward him), 1 when he is behind her.
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;auto* Him=Gallery?Gallery->PartnerActor.Get():nullptr;
    FVector Nose,Head,HerHips,HisHips;
    if(!HBone(Girl,TEXT("J_Nose_tip"),Nose)||!HBone(Girl,TEXT("j_head"),Head)||!HBone(Girl,TEXT("j_hips"),HerHips)||!HBone(Him,TEXT("j_hips"),HisHips))return 0;
    return ((Nose-Head)|(HisHips-HerHips))>=0.?0:1;
}
// A bone of theirs in the world (the male skeleton may name its bones like hers).
static bool HBone(AKKPreviewActor* A,const TCHAR* Name,FVector& Out);
void UOKHScenePanel::LookAtCrotch(float Distance,float Pitch,float Turn,bool bFront){
    // Where his penis is in her: her crotch from beside her body (across the line from her hips to her head), a little above.
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;FVector At,Head,Hips;
    if(!IsValid(Girl)||!Girl->StudioCam||!HBone(Girl,TEXT("J_Kokan"),At)||!HBone(Girl,TEXT("j_head"),Head)||!HBone(Girl,TEXT("j_hips"),Hips))return;
    FVector Body=Head-Hips;Body.Z=0;FVector Side=FVector::CrossProduct(Body.IsNearlyZero()?FVector::ForwardVector:Body.GetSafeNormal(),FVector::UpVector);if(Side.IsNearlyZero())Side=FVector::RightVector;
    Girl->OrbitFocus=At;Girl->OrbitYaw=FMath::RadiansToDegrees(FMath::Atan2(Side.X,Side.Y))+Turn;Girl->OrbitPitch=FMath::Clamp(Pitch,-80.f,85.f);
    // Front (user, 2026-11-01: from the side her thighs hide it): from before her belly, the way her breasts sit from
    // her upper spine (as the penis aim reads her front), up or down as that way goes; Pitch adds to it.
    FVector Chest,BustL,BustR;
    if(bFront&&HBone(Girl,TEXT("j_spine03"),Chest)&&HBone(Girl,TEXT("j_bust01_L"),BustL)&&HBone(Girl,TEXT("j_bust01_R"),BustR)){
        const FVector Up=(Head-Hips).GetSafeNormal();FVector Front=(BustL+BustR)*.5f-Chest;Front-=Up*FVector::DotProduct(Front,Up);Front.Normalize();
        // Belly down (後入, 躺姿後入) there is no front to see from above the floor: low from beside her instead.
        if(Front.Z>-.5f){Girl->OrbitYaw=FMath::RadiansToDegrees(FMath::Atan2(Front.X,Front.Y))+Turn;Girl->OrbitPitch=FMath::Clamp(FMath::RadiansToDegrees(FMath::Asin(Front.Z))+Pitch,5.f,85.f);} // never under the floor
        else Girl->OrbitPitch=5.f;
        // Her front to a sofa back or a wall (沙發騎乘, 靠牆騎乘): the camera stops before it, not inside it.
        const float Y=FMath::DegreesToRadians(Girl->OrbitYaw),P=FMath::DegreesToRadians(Girl->OrbitPitch);const FVector Out(FMath::Sin(Y)*FMath::Cos(P),FMath::Cos(Y)*FMath::Cos(P),FMath::Sin(P)); // ApplyOrbitCamera's offset
        FCollisionQueryParams Params(SCENE_QUERY_STAT(OKHFrontCam),true);Params.AddIgnoredActor(Girl);if(Gallery->PartnerActor)Params.AddIgnoredActor(Gallery->PartnerActor.Get());
        FHitResult Hit;if(GetWorld()&&GetWorld()->LineTraceSingleByChannel(Hit,At,At+Out*Distance,ECC_Visibility,Params)){
            UE_LOG(LogTemp,Display,TEXT("H scene: front camera blocked by %s at %.0f cm"),Hit.GetActor()?*Hit.GetActor()->GetName():TEXT("?"),Hit.Distance);Distance=FMath::Max(15.f,float(Hit.Distance)-5.f);}
        // The props (sofa, wall, table) have no collision (their boxes count the non-colliding parts): in nearer until the camera is out of their boxes (she may sit
        // inside a sofa's box herself).
        auto InProp=[this](const FVector& P){for(AStaticMeshActor* Prop:Props)if(IsValid(Prop)&&Prop->GetComponentsBoundingBox(true).IsInside(P))return true;return false;};
        const float Was=Distance;
        // A prop between, a step away from her (the wall she leans her hands on, 靠牆撐手): before it. One right against her
        // (a wall she is pressed to) is seen through from behind and stays.
        for(AStaticMeshActor* Prop:Props)if(IsValid(Prop)){const FBox Box=Prop->GetComponentsBoundingBox(true);FVector HitAt,Normal;float Time=0.f;
            if(!Box.IsInside(At)&&FMath::LineExtentBoxIntersection(Box,At,At+Out*Distance,FVector::ZeroVector,HitAt,Normal,Time)){const float Far=float(FVector::Dist(At,HitAt));if(Far>=25.f)Distance=FMath::Min(Distance,Far-5.f);}}
        while(Distance>15.f&&InProp(At+Out*Distance))Distance-=5.f;
        if(Distance<Was)UE_LOG(LogTemp,Display,TEXT("H scene: front camera in to %.0f cm, out of the props"),Distance);}
    Girl->OrbitDistance=FMath::Clamp(Distance,15.f,650.f);Girl->ApplyOrbitCamera();
}
void UOKHScenePanel::LookAtFace(float Distance,float Turn){
    // Where her nose points from her head: the camera that way, at her face's height and tilt (down at him, up at the ceiling).
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;FVector Head,Nose;
    if(!IsValid(Girl)||!Girl->StudioCam||!HBone(Girl,TEXT("j_head"),Head)||!HBone(Girl,TEXT("J_Nose_tip"),Nose))return;
    FVector Dir=(Nose-Head).GetSafeNormal();if(Dir.IsNearlyZero())return;
    Girl->OrbitFocus=Nose;Girl->OrbitYaw=FMath::RadiansToDegrees(FMath::Atan2(Dir.X,Dir.Y))+Turn;Girl->OrbitPitch=FMath::Clamp(FMath::RadiansToDegrees(FMath::Asin(Dir.Z)),-70.f,70.f);
    Girl->OrbitDistance=FMath::Clamp(Distance,15.f,650.f);Girl->ApplyOrbitCamera();
}
// Where he enters her: her anus, or her vagina a little below J_Kokan toward her anus (user, 2026-11-01: lower, so her
// labia show above him).
// How far her belly may swell for him (user, 2026-11-02: a swell of 9 cm, then 3, still showed him through her in 騎乘位;
// none: he is drawn back, his root brought in and his penis turned until no part of him is out of her skin).
static constexpr float BellySwellCm=0.f;
// His penis from its middle line to its skin, at size x1 (cm_J_dan shaft of the original male body).
static constexpr float PenisRadiusCm=1.8f;
// How far his root may be moved off her skin past where the pad puts it (AlignHim: RootDodge).
static constexpr float RootDodgeMaxCm=20.f;
static TAutoConsoleVariable<float> CVarHWrapTest(TEXT("ok.HScene.WrapTest"),0.f,TEXT("Test: every wrapped skin moved this many metres up her mesh instead (0 off)"));
static TAutoConsoleVariable<float> CVarHBackClipLead(TEXT("ok.HScene.BackClipLead"),8.f,TEXT("His penis folded under her back this many frames of his glans' way out further in (the morph is drawn after his pose is read)"));
static TAutoConsoleVariable<int32> CVarHBackClip(TEXT("ok.HScene.BackClip"),1,TEXT("1: his penis out through her back folded under her skin there, not drawn (belly_bulge::clip_deltas); 0 drawn"));
static TAutoConsoleVariable<int32> CVarHWrap(TEXT("ok.HScene.Wrap"),1,TEXT("1: her skin moves each frame to wrap his penis in her (belly_bulge::wrap_deltas); 2: her skin material pushes it off his penis (world position offset, the _Wrap parents of wrap_material_root); 3: belly bones added to her body, pushed by his penis (belly_bulge::bone_deltas); 0 off, to compare"));
// The skin parents with the wrap offset (manifest wrap_material_root, Launch/materials.json wrap_root).
static const FString& OKWrapMaterialRoot(){
    static const FString Root=[]{FString Manifest,Json,Found;TSharedPtr<FJsonObject> Object;
        if(FParse::Value(FCommandLine::Get(),TEXT("StreetSocialManifest="),Manifest)&&FFileHelper::LoadFileToString(Json,*Manifest)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Object)&&Object)Object->TryGetStringField(TEXT("wrap_material_root"),Found);
        return Found.IsEmpty()?FString(TEXT("/Game/IndependentResources/RuntimeMaterials/StreetWrap01")):Found;}();
    return Root;
}
static TAutoConsoleVariable<float> CVarHEntranceDown(TEXT("ok.HScene.EntranceDown"),1.5f,TEXT("cm his entry point sits below J_Kokan, toward J_Ana"));
static bool HEntrance(AKKPreviewActor* Girl,bool bAnal,FVector& Out){
    if(bAnal)return HBone(Girl,TEXT("J_Ana"),Out);
    FVector Ana;if(!HBone(Girl,TEXT("J_Kokan"),Out))return false;
    if(HBone(Girl,TEXT("J_Ana"),Ana)&&FVector::Dist(Out,Ana)>1.f)Out+=(Ana-Out).GetSafeNormal()*FMath::Min(CVarHEntranceDown.GetValueOnGameThread(),.5f*float(FVector::Dist(Out,Ana)));
    return true;
}
static bool HBone(AKKPreviewActor* A,const TCHAR* Name,FVector& Out){
    if(!IsValid(A)||!A->BodySkel)return false;
    for(const TCHAR* P:{TEXT("cf_"),TEXT("cm_")}){const FName N(FString(P)+Name);if(A->BodySkel->GetBoneIndex(N)!=INDEX_NONE){Out=A->BodySkel->GetBoneLocation(N);return true;}}
    return false;
}
// Which way her chest faces now, from the shoulders (left to right, crossed with up), while her upper body is upright:
// in a pair pose the actor's rotation is the pose's origin, not her body, and side-by-side poses were shot from behind.
static bool HChestForward(AKKPreviewActor* A,FVector& Out){
    FVector L,R,Head,Hips;
    if(!HBone(A,TEXT("j_shoulder_L"),L)||!HBone(A,TEXT("j_shoulder_R"),R)||!HBone(A,TEXT("j_head"),Head)||!HBone(A,TEXT("j_hips"),Hips))return false;
    const FVector Body=Head-Hips;if(FMath::Abs(float(Body.Z))<Body.Size2D()*1.2f)return false; // lying or on all fours: no upright chest
    // Her face says it best when the face rig is on this skeleton: head to the tip of her nose.
    FVector Nose;const FName NoseBone=A->BodySkel->GetBoneIndex(TEXT("cf_J_Nose_tip"))!=INDEX_NONE?FName(TEXT("cf_J_Nose_tip")):FName(TEXT("cm_J_Nose_tip"));
    if(A->BodySkel->GetBoneIndex(NoseBone)!=INDEX_NONE){Nose=A->BodySkel->GetBoneLocation(NoseBone);Out=Nose-Head;Out.Z=0;
        if(Out.Normalize()){UE_LOG(LogTemp,Verbose,TEXT("H camera: her front from her nose (%.2f,%.2f)"),Out.X,Out.Y);return true;}}
    // The converted skeleton is mirrored (its _L shoulder is on her right in UE): up × (R − L) is her front.
    FVector Right=R-L;Right.Z=0;Out=FVector::CrossProduct(FVector::UpVector,Right);Out.Z=0;
    UE_LOG(LogTemp,Verbose,TEXT("H camera: her front from her shoulders (%.2f,%.2f)"),Out.X,Out.Y);return Out.Normalize();
}
// Where their body is now, from the bones (the component bounds can still be the standing pose's after a sit or a lie).
static FBox HBodyBox(AKKPreviewActor* A){
    FBox Box(ForceInit);FVector P;
    for(const TCHAR* N:{TEXT("j_hips"),TEXT("j_spine02"),TEXT("j_head"),TEXT("j_hand_L"),TEXT("j_hand_R"),TEXT("j_foot_L"),TEXT("j_foot_R"),TEXT("j_leg01_L"),TEXT("j_leg01_R")})if(HBone(A,N,P))Box+=P;
    if(!Box.IsValid)return IsValid(A)?A->GetComponentsBoundingBox(true):Box;
    Box=Box.ExpandBy(15.f);Box.Max.Z+=12.f;return Box; // the flesh around the bones, the top of the head
}
void UOKHScenePanel::FrameCamera(){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||!Girl->StudioCam)return;
    const FString Key=FString::Printf(TEXT("%d|%d|%d"),Mode,ActivePose,ActiveAibu);const double Now=FPlatformTime::Seconds();
    if(Key!=FramedKey){FramedKey=Key;FrameAt=Now+.8;return;} // after the pose has placed them
    if(FrameAt<=0||Now<FrameAt)return;FrameAt=0;
    const FBox HerBox=HBodyBox(Girl);if(!HerBox.IsValid)return;
    FVector Facing=Girl->GetActorRotation().RotateVector(FVector(0,1,0));Facing.Z=0;Facing=Facing.GetSafeNormal();
    FVector Focus=HerBox.GetCenter(),Dir=Facing;float Size=HerBox.GetExtent().Size();
    auto* Him=Gallery->PartnerActor.Get();bool bOverlap=false; // one on top of the other: no side between them to shoot from
    if(Mode!=0&&IsValid(Him)&&!Him->IsHidden()){
        const FBox HisBox=HBodyBox(Him);
        if(HisBox.IsValid){
            FVector Line=HisBox.GetCenter()-HerBox.GetCenter();Line.Z=0;bOverlap=Line.Size()<=25.f;
            // Both of their fronts: the side that sees the two faces (beside him, she faces him and he faces ahead).
            // Face to face they cancel out: then her front alone.
            FVector Chest,HisChest;if(HChestForward(Girl,Chest)){Facing=Chest;
                if(HChestForward(Him,HisChest)&&(Chest+HisChest).Size2D()>.5f)Facing=(Chest+HisChest).GetSafeNormal2D();}
            if(Line.Size()>5.f){Line.Normalize();FVector Side(-Line.Y,Line.X,0);if((Side|Facing)<0)Side=-Side;const FVector Across=Facing-Line*float(Facing|Line); // her front across the line between them, not toward him
                Dir=(Side+.45f*Across-.25f*Line).GetSafeNormal();
                // From the side where his body is least in the way of her face (an arch, a pose seen across his back).
                FVector Face,B;TArray<FVector> HisBody;for(const TCHAR* N:{TEXT("j_head"),TEXT("j_spine02"),TEXT("j_hips")})if(HBone(Him,N,B))HisBody.Add(B);
                if(HBone(Girl,TEXT("j_head"),Face)&&HisBody.Num()){
                    const float Dist=FMath::Clamp(Size*2.5f,120.f,650.f);
                    auto Clear=[&](const FVector& D){const FVector Eye=Focus+D*Dist+FVector(0,0,Dist*.32f);float Near=TNumericLimits<float>::Max();
                        // Only what is between the eye and her face blocks it: his head beside hers (close to her end) does not.
                        const FVector Ray=Face-Eye;for(const FVector& V:HisBody){const float T=float((V-Eye)|Ray)/FMath::Max(1.f,float(Ray.SizeSquared()));
                            if(T>.05f&&T<.85f)Near=FMath::Min(Near,FMath::PointDistToSegment(V,Eye,Face));}return Near;};
                    const FVector Other=(-Side+.45f*Across-.25f*Line).GetSafeNormal();
                    const float Here=Clear(Dir);if(Here<20.f&&Clear(Other)>Here+12.f)Dir=Other;}} // only when this side is blocked
            else Dir=FVector(-Facing.Y,Facing.X,0); // one right against the other (held up, face to face): from beside her, not through him
            Focus=FMath::Lerp(HerBox.GetCenter(),HisBox.GetCenter(),.3f);Size=FMath::Max(Size,(HerBox+HisBox).GetExtent().Size()*.8f);
        }
    }else{Dir=(Facing+.5f*FVector(Facing.Y,-Facing.X,0)).GetSafeNormal();Focus.Z+=HerBox.GetExtent().Z*.15f;} // her body from the bones, a little above its middle so the head is never cut
    // Lying (on her back, on all fours): her body runs along the floor, not the way the actor faces. From beside her body,
    // toward her face, and from higher up, so neither her feet nor her back fill the view. One on top of the other (an
    // arch under him): the same, from beside her body, though it is not flat.
    float Pitch=18.f;
    {FVector Head,Hips;if((Mode==0||bOverlap)&&HBone(Girl,TEXT("j_head"),Head)&&HBone(Girl,TEXT("j_hips"),Hips)){
        FVector Body=Head-Hips;const float Up=FMath::Abs(float(Body.Z));Body.Z=0;
        const bool Flat=Body.Size()>Up*1.2f;
        if((Flat||bOverlap&&Body.Size()>10.f)&&Body.Normalize()){FVector Side(-Body.Y,Body.X,0);if((Side|Facing)<0)Side=-Side;
            if(Flat){Dir=(Side+.35f*Body).GetSafeNormal();Pitch=35.f;}else Dir=Side;}}} // held upright against him: straight from the side
    if(Dir.IsNearlyZero())return;
    float Distance=Size*(Mode==0&&Pitch<30.f?3.1f:2.5f); /* standing alone: head to feet in the shot (2.5 cut both) */ // the bone box is tighter than the mesh bounds
    // Tall shots (a standing pair: 立位 cut both heads at 2.5) need the height in the picture: far enough that the vertical
    // field of view holds their whole height, with a margin.
    {FBox Shot=HerBox;if(auto* Partner=Mode!=0&&Gallery->PartnerActor&&!bMaleHidden?Gallery->PartnerActor.Get():nullptr){const FBox PartnerBox=HBodyBox(Partner);if(PartnerBox.IsValid)Shot+=PartnerBox;}
     const float HFov=Girl->StudioCam&&Girl->StudioCam->GetCameraComponent()?Girl->StudioCam->GetCameraComponent()->FieldOfView:60.f;
     FVector2D View(16.,9.);if(GEngine&&GEngine->GameViewport)GEngine->GameViewport->GetViewportSize(View);
     const float Aspect=View.Y>1.?float(View.X/View.Y):16.f/9.f;
     const float HalfV=FMath::Atan(FMath::Tan(FMath::DegreesToRadians(HFov*.5f))/Aspect);
     const float Upper=float(Shot.Max.Z-Focus.Z),Lower=float(Focus.Z-Shot.Min.Z); // the focus need not be the middle
     Distance=FMath::Max(Distance,FMath::Max(Upper,Lower)*1.15f/FMath::Tan(HalfV));}
    Girl->OrbitFocus=Focus;Girl->OrbitYaw=FMath::RadiansToDegrees(FMath::Atan2(Dir.X,Dir.Y));Girl->OrbitPitch=Pitch;Girl->OrbitDistance=FMath::Clamp(Distance,120.f,650.f);
    Girl->ApplyOrbitCamera();
    UE_LOG(LogTemp,Display,TEXT("H camera: facing (%.2f,%.2f) shot from (%.2f,%.2f) pitch %.0f distance %.0f"),Facing.X,Facing.Y,Dir.X,Dir.Y,Pitch,Girl->OrbitDistance);
    HideWallsInTheWay();
}
bool UOKHScenePanel::XRayInHer() const{return Mode==2||(Mode==1&&Poses.IsValidIndex(ActivePose)&&Poses[ActivePose].KindHoushi==1);}
void UOKHScenePanel::ApplyMaleLook(){
    auto* Him=Gallery?Gallery->PartnerActor.Get():nullptr;if(!IsValid(Him)||Mode==0||Him->IsHidden()||!Gallery->PairedPlayback)return;MaleLookFor=Him;
    // His bottom and briefs (the original takes them off in H): off shows the body under them, the penis with it. His
    // shoes are off in her room as hers are (see NativeTick).
    {uint8 S[9];for(int32 K=0;K<9;++K)S[K]=Him->DisplayClothesStates[K];if(bMaleBottomOff){S[1]=3;S[3]=3;}S[7]=S[8]=3;Him->SetClothingPartsHidden(S);}
    // Put his own materials back first, then (see-through) one colour on every part of him.
    int32 M=0;for(UMeshComponent* Comp:MaleGhostComps){if(!IsValid(Comp)){continue;}for(int32 I=0;I<Comp->GetNumMaterials()&&M<MaleGhostMats.Num();++I,++M)Comp->SetMaterial(I,MaleGhostMats[M]);}
    MaleGhostComps.Reset();MaleGhostMats.Reset();
    for(UMeshComponent* Comp:MaleGhostOutlines)if(IsValid(Comp))Comp->SetVisibility(true);MaleGhostOutlines.Reset();
    // The penis (hidden like the card preview's) shows when his bottom is off.
    Him->SetGenitalVisible(bMaleBottomOff);
    // His balls stay hidden (user, 2026-11-01): o_dan_f / cm_o_dan_f and their outlines.
    {TInlineComponentArray<UPrimitiveComponent*> Prims;Him->GetComponents(Prims);
     for(UPrimitiveComponent* Comp:Prims)for(const FName& Tag:Comp->ComponentTags){const FString T=Tag.ToString();const int32 PartIdx=HTagPart(T);if(PartIdx==INDEX_NONE)continue;
         OkMeshView V{};if(Him->Session.PartAt(PartIdx,V)&&V.name){const FString N=FString(UTF8_TO_TCHAR(V.name)).ToLower();
             if(N==TEXT("o_dan_f")||N==TEXT("cm_o_dan_f")){Comp->SetVisibility(false,true);Comp->SetHiddenInGame(true);}}break;}}
    // Where his penis is inside her: while he is see-through it is drawn once more over everything (depth test off), a
    // faint colour, so the part in her body shows too (whether it runs inside her or comes out through her skin).
    TInlineComponentArray<UMeshComponent*> All;Him->GetComponents(All);
    auto IsGenital=[Him](UMeshComponent* Comp){for(const FName& Tag:Comp->ComponentTags){const FString T=Tag.ToString();const int32 PartIdx=HTagPart(T);if(PartIdx==INDEX_NONE)continue;
        OkMeshView V{};if(Him->Session.PartAt(PartIdx,V)&&V.name){const FString N=FString(UTF8_TO_TCHAR(V.name)).ToLower();return N==TEXT("o_dankon")||N==TEXT("cm_o_dan00");}}return false;};
    // Only where he is in her (intercourse, her mouth): in her hands or between her breasts it would be drawn over them.
    bXRayInHer=XRayInHer();
    UMaterialInterface* XRayParent=bPenisXRay&&bXRayInHer&&MaleView!=2&&bMaleBottomOff?LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewXRay.M_PreviewXRay"),nullptr,LOAD_NoWarn):nullptr;
    if(XRayParent&&!PenisXRay){PenisXRay=UMaterialInstanceDynamic::Create(XRayParent,this);PenisXRay->SetVectorParameterValue(TEXT("PreviewTint"),FLinearColor(1.f,.35f,.75f,.45f));}
    int32 Shown=0;for(UMeshComponent* Comp:All)if(IsGenital(Comp)){Comp->SetOverlayMaterial(XRayParent?PenisXRay.Get():nullptr);Shown+=XRayParent?1:0;}
    if(XRayParent)UE_LOG(LogTemp,Display,TEXT("H scene: penis drawn through her: %d parts%s"),Shown,XRayParent?TEXT(""):TEXT(" (no M_PreviewXRay)"));
    if(bPenisGreen){GreenComps.Reset();GreenKept.Reset();SetPenisGreen(true);}
    if(MaleView!=1)return;
    // Looked up each time, not kept in a static: once the scene that made his ghost material is gone, nothing holds the
    // parent and it is collected; the next scene read the freed one (crash on coming back into the room, R9).
    UMaterialInterface* Parent=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewTranslucent.M_PreviewTranslucent"));
    if(!Parent){UE_LOG(LogTemp,Warning,TEXT("H scene: no see-through material for him"));return;}
    if(!MaleGhost){MaleGhost=UMaterialInstanceDynamic::Create(Parent,this);MaleGhost->SetVectorParameterValue(TEXT("PreviewTint"),FLinearColor(.25f,.45f,1.f,.05f));}
    TInlineComponentArray<UMeshComponent*> Comps;Him->GetComponents(Comps);
    // Everything but the penis and the balls (o_dankon / cm_o_dan00, o_dan_f): those stay as they are, to see where he is in her.
    auto PartName=[Him](UMeshComponent* Comp){for(const FName& Tag:Comp->ComponentTags){const FString T=Tag.ToString();const int32 PartIdx=HTagPart(T);if(PartIdx==INDEX_NONE)continue;
        OkMeshView V{};if(Him->Session.PartAt(PartIdx,V)&&V.name)return FString(UTF8_TO_TCHAR(V.name)).ToLower();}return FString();};
    auto Genital=[&](UMeshComponent* Comp){const FString N=PartName(Comp);return N==TEXT("o_dankon")||N==TEXT("cm_o_dan00")||N==TEXT("o_dan_f")||N==TEXT("cm_o_dan_f");};
    for(UMeshComponent* Comp:Comps){if(!Comp->IsVisible()||Genital(Comp))continue;
        // One layer of colour: his body and face only. Hair cards, clothes, eyes and outline shells stacked on them made the
        // 5% look like half; they are hidden while he is see-through.
        {const UMaterialInterface* First=Comp->GetNumMaterials()>0?Comp->GetMaterial(0):nullptr;const FString N=PartName(Comp);
         if(!(N==TEXT("o_body_a")||N==TEXT("o_body_b")||N==TEXT("cf_o_face"))||(First&&First->GetName().Contains(TEXT("Outline")))){MaleGhostOutlines.Add(Comp);Comp->SetVisibility(false);continue;}}
        MaleGhostComps.Add(Comp);
        for(int32 I=0;I<Comp->GetNumMaterials();++I){MaleGhostMats.Add(Comp->GetMaterial(I));Comp->SetMaterial(I,MaleGhost);}}
    UE_LOG(LogTemp,Display,TEXT("H scene: he is drawn see-through (%d parts)"),MaleGhostComps.Num());
}
void UOKHScenePanel::MoveParts(AKKPreviewActor* A,const FVector& Want,FVector& Applied){
    const FVector Step=Want-Applied;if(!IsValid(A)||Step.IsNearlyZero(.01f))return;Applied=Want;
    if(USceneComponent* Root=A->GetRootComponent()){const FVector Local=Root->GetComponentTransform().InverseTransformVectorNoScale(Step);
        for(USceneComponent* Child:Root->GetAttachChildren())if(IsValid(Child))Child->AddRelativeLocation(Local);}
}
void UOKHScenePanel::SyncPair(){if(Gallery&&Gallery->PairedPlayback)Gallery->PairedPlayback->SyncAsync();}
void UOKHScenePanel::HoldFeet(AKKPreviewActor* A,bool bStands,const FVector& Offset,const FVector (&Feet)[2],FVector (&Kept)[2],bool& bIk){
    if(!IsValid(A)||!A->Session.IsOpen())return;
    // Her hands on him (GripHim) go in the same set: setting one replaces the other.
    const bool bAhe=A==(Gallery?Gallery->PreviewActor.Get():nullptr)&&AheHandAt.Num()==2; // her double peace before her grip on him
    const bool bHands=bAhe||(A==(Gallery?Gallery->PreviewActor.Get():nullptr)&&HandEff.Num());const TArray<int32> Eff5={5,6};const TArray<int32>& HandsEff=bAhe?Eff5:HandEff;const TArray<FVector>& HandsAt=bAhe?AheHandAt:HandAt;
    // Lowered while standing: the feet stay where the clip put them (on the floor), so the knees bend.
    if(bStands&&Offset.Z<-1.f||bHands){
        TArray<int32> Eff;TArray<FVector> At;bool bSame=bIk;
        if(bStands&&Offset.Z<-1.f){
            const FVector Local=A->GetRootComponent()?A->GetRootComponent()->GetComponentTransform().InverseTransformVectorNoScale(Offset):Offset;
            const FVector Shift=AKKPreviewActor::ActorLocalToUnity(Local);
            const FVector L=Feet[0]-Shift,R=Feet[1]-Shift;
            bSame&=FVector::Dist(L,Kept[0])<.002&&FVector::Dist(R,Kept[1])<.002; // within 2 mm: leave the solver alone
            Eff={7,8};At={L,R};Kept[0]=L;Kept[1]=R;}
        if(bHands){bSame&=HandHeld.Num()==HandsAt.Num();for(int32 I=0;bSame&&I<HandsAt.Num();++I)bSame&=FVector::Dist(HandsAt[I],HandHeld[I])<.004;
            Eff.Append(HandsEff);At.Append(HandsAt);}
        if(bSame)return;
        SyncPair();if(A->Session.SetStudioIk(Eff,At)){bIk=true;HandHeld=bHands?HandsAt:TArray<FVector>();}
    }else if(bIk){SyncPair();A->Session.SetStudioIk({},{});bIk=false;HandHeld.Reset();}
}
// Her hands hold him while she sucks him (user, 2026-11-02: her hands missed his penis): he is moved along the line into
// her mouth (AlignHim) and the clip's hands stay where they were. Each hand the clip has near him (within 15 cm of his
// penis) holds what of him is outside her lips (from his root to 2 cm short of her lips): the hand nearer her mouth at 70%
// of it, the other at 35% (one hand: half way), the middle of her palm (wrist to the root of her middle finger) as far
// from his middle as he is thick (3 cm, with his size) on the side the clip has it. Her FBBIK hand effectors (5, 6) are
// her wrists: set where that puts them (her wrist on him put her fingers over her face).
static TAutoConsoleVariable<int32> CVarHSuckGrip(TEXT("ok.HScene.SuckGrip"),1,TEXT("Sucking: her hands put on his penis (her hand IK); 0 the clip's hands"));
void UOKHScenePanel::GripHim(AKKPreviewActor* Girl,AKKPreviewActor* Him,const FVector& Lips,const FVector& Root,const FVector& Axis){
    HandEff.Reset();HandAt.Reset();
    if(!IsValid(Girl)||!Girl->Session.IsOpen()||!CVarHSuckGrip.GetValueOnGameThread())return;
    if(!Girl->bStudioIkReady){FString Error;if(!Girl->Session.PrepareStudioIk(Error))return;Girl->bStudioIkReady=true;}
    const float Outside=float((Lips-Root)|Axis)-2.f;if(Outside<3.f)return;
    const FTransform& T=Girl->GetActorTransform();
    struct FHand{int32 Side;FVector Wrist,Palm,Off;float Along;};TArray<FHand> Hands;
    for(int32 Side=0;Side<2;++Side){FVector Wrist,Finger;if(!HBone(Girl,Side?TEXT("j_hand_R"):TEXT("j_hand_L"),Wrist)||!HBone(Girl,Side?TEXT("j_middle01_R"):TEXT("j_middle01_L"),Finger))continue;
        const FVector Palm=(Wrist+Finger)*.5f;const float Along=float((Palm-Root)|Axis);const FVector Off=Palm-(Root+Axis*Along);
        if(Off.Size()>15.f||Along<-5.f)continue;Hands.Add({Side,Wrist,Palm,Off,Along});}
    Hands.Sort([](const FHand& A,const FHand& B){return A.Along<B.Along;});
    for(int32 I=0;I<Hands.Num();++I){const FHand& H=Hands[I];const float At=Hands.Num()==1?.5f:I?.7f:.35f;
        const FVector Want=Root+Axis*(Outside*At)+H.Off.GetSafeNormal()*(3.f*PenisScale)+(H.Wrist-H.Palm);
        GripUntil[H.Side]=FPlatformTime::Seconds()+2.;HandEff.Add(5+H.Side);HandAt.Add(AKKPreviewActor::ActorLocalToUnity(T.InverseTransformPosition(Want-HerApplied)));}
}
void UOKHScenePanel::RestoreAlign(){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;auto* Him=Gallery?Gallery->PartnerActor.Get():nullptr;
    WrapIdxShown.Reset();WrapDShown.Reset();WrapNShown.Reset();if(AKKPreviewActor* Was=ClothGirl.Get()){for(int32 Part:ClothShown)Was->SetPartWrapDeltas(Part,{},{});TArray<int32> None;Was->Session.SetClothCover(false,{},{},{},None);Was->CpuSkinnedParts.Reset();}ClothGirl=nullptr;ClothCpuUntil.Reset();ClothShown.Reset();ClothVerts=0;
    if(IsValid(Girl)&&(BustSwellSet!=1.f||OralSuckSet!=0.f))Girl->MarkShapeDirty(Gallery->Selected.Face.ShapeValueFace,Gallery->Selected.Body.ShapeValueBody); // her own bust and face again
    if(IsValid(Girl)&&OralGazeSet!=0.f&&!bAhegaoShown)Girl->SetEyeGaze(0.f,0.f,0.f);
    BustSwell=BustSwellSet=1.f;OralSuck=OralSuckSet=OralGazeSet=OralPull=OralPullSet=0.f;bSucking=false;if(IsValid(Girl)){Girl->HiddenMouthInside=0;Girl->SetMouthOpenFloor(0.f);}
    if(AlignedHer==Girl)MoveParts(Girl,FVector::ZeroVector,HerApplied);if(AlignedHim==Him)MoveParts(Him,FVector::ZeroVector,HimApplied);
    if(bHerIk||bHisIk)SyncPair();
    if(bHerIk&&IsValid(Girl)&&Girl->Session.IsOpen())Girl->Session.SetStudioIk({},{});if(bHisIk&&IsValid(Him)&&Him->Session.IsOpen())Him->Session.SetStudioIk({},{});
    bHerIk=bHisIk=false;HimOffset=HerOffset=FVector::ZeroVector;
    if(BulgedHer==Girl&&IsValid(Girl)&&BulgePart!=INDEX_NONE){BulgeBelly(Girl,nullptr,0.f,1e3f);Girl->VaginaOpenOverride=-1.f;}
}
void UOKHScenePanel::BulgeBelly(AKKPreviewActor* Girl,const FVector* Tip,float Off,float Delta){
    if(BulgedHer!=Girl){BulgedHer=Girl;BulgePart=INDEX_NONE;bBulgeLogged=false;Bulge.Reset();BulgeTarget=NAME_None;OpenEased=0.f;
        for(int32 Part=0;IsValid(Girl)&&Part<Girl->Session.PartCount();++Part)
            {const TArray<FName> Morphs=Girl->GetPartMorphNames(Part);if(Morphs.ContainsByPredicate([](const FName& N){return N.ToString().StartsWith(TEXT("belly.bulge."));})){BulgePart=Part;
                // Her body's own opening (SAC bodies: vagina.open), else the one made with the swells.
                // (her own one is driven by the pair playback, DriveVaginaOpening, from VaginaOpenOverride).
                BulgeOpen=Morphs.Contains(FName(TEXT("vagina.open")))?FName(TEXT("vagina.open")):FName(TEXT("kokan.open"));break;}}
        UE_LOG(LogTemp,Display,TEXT("H scene: belly bulge morphs %s"),BulgePart!=INDEX_NONE?*FString::Printf(TEXT("on part %d, opening %s"),BulgePart,*BulgeOpen.ToString()):TEXT("missing (her body has none)"));}
    if(BulgePart==INDEX_NONE)return;
    // Where his tip is against her skin now: read when the pair playback has the sessions idle (ReadPairSessions); with
    // none, here.
    FVector Kokan;
    if(!Tip){BulgeTarget=NAME_None;WrapIdxShown.Reset();WrapDShown.Reset();WrapNShown.Reset();if(bWrapShown&&IsValid(Girl)){Girl->SetPartWrapDeltas(BulgePart,{},{});bWrapShown=false;}
        if(bClipShown&&ClipHim.IsValid()){ClipHim->SetPartWrapDeltas(ClipPart,{},{});bClipShown=false;ClipVerts=0;}if(bWrapLineShown&&IsValid(Girl)){Girl->SetWrapLine(false,FVector::ZeroVector,FVector::ZeroVector,0.f,FString());bWrapLineShown=false;}}
    else if(!IsValid(Gallery?Gallery->PairedPlayback.Get():nullptr))ReadBulge(Girl,*Tip);
    // Once his tip is past her skin (inside, the margin swelled her where he does not show), out by how far and 2.5 cm
    // more (his glans is round, the skin beside the one measured moves less). A swell that hardly moves that skin (the
    // end of its reach) would only bloat her elsewhere.
    TMap<FName,float> Want;
    // Only with his glans 6 cm or more past her entrance along himself (TipInside): nearer it is in her entrance, and drawn
    // out the nearest skin is her bottom or labia, which swelled out after him (user, 2026-11-01).
    // It swells as far as his tip is out of her skin at each moment, no more: it rises and falls with the thrust and never
    // lets him show through. Scaling it by how deep the stroke is (R20c) left her flat while his penis, which hardly moves
    // in these clips, was still out of her skin (user, R20).
    const bool HasKokan=Tip&&HBone(Girl,TEXT("J_Kokan"),Kokan);
    // Her entrance opens around him (user, 2026-11-01: it opens and closes with him; her body's own vagina.open, else belly_bulge.rs OPEN): half open while
    // he is in her, wide as he pushes deep, narrowing as he draws back (AlignDeep, 20..90).
    {const float Open=Tip&&HasKokan?FMath::Lerp(45.f,100.f,FMath::Clamp((AlignDeep-20.f)/70.f,0.f,1.f)):0.f;
     if(BulgeOpen==FName(TEXT("kokan.open"))){if(Open>0.f)Want.Add(BulgeOpen,Open);}
     else if(!BulgeOpen.IsNone()){OpenEased=FMath::FInterpTo(OpenEased,Open,Delta,Open>OpenEased?40.f:20.f);Girl->VaginaOpenOverride=OpenEased<.5f?0.f:OpenEased/100.f;}}
    TArray<FName> Names;Bulge.GetKeys(Names);for(const auto& W:Want)Names.AddUnique(W.Key);
    // Eased to follow the stroke: faster rising (a lag there shows him through her skin), falling as it draws back.
    // All set, then her display rebuilt once (dozens of fine swells at once rebuilt it for each: 100 FPS to 25).
    const double SwellT0=FPlatformTime::Seconds();Girl->BeginFaceDisplayUpdate();ON_SCOPE_EXIT{Girl->EndFaceDisplayUpdate();SwellMs=float((FPlatformTime::Seconds()-SwellT0)*1000.);};
    for(const FName& Name:Names){float& B=Bulge.FindOrAdd(Name);const float Was=B,To=Want.FindRef(Name);
        B=FMath::FInterpTo(B,To,Delta,To>B?40.f:20.f);if(To==0.f&&B<.5f)B=0.f;
        if(FMath::Abs(B-Was)>.05f||(B==0.f&&Was!=0.f)){if(!Girl->SetPartMorphWeight(BulgePart,Name,B))++BulgeRefused;
            if(!bBulgeLogged&&B>1.f){bBulgeLogged=true;UE_LOG(LogTemp,Display,TEXT("H scene: belly bulge %s, his tip %.1f cm out of her skin (%.1f off the way in)"),*Name.ToString(),BulgePast,Off);}}
        if(B==0.f)Bulge.Remove(Name);}
}
void UOKHScenePanel::ReadBulge(AKKPreviewActor* Girl,const FVector& Tip,const FVector* Root){
    FVector Kokan;float M[16];
    if(!HBone(Girl,TEXT("J_Kokan"),Kokan)||!(Girl->Session.BoneWorldMatrix(TEXT("cf_J_Kokan"),M)||Girl->Session.BoneWorldMatrix(TEXT("cf_j_kokan"),M)))return;
    const FTransform& Body=Girl->GetActorTransform();
    // His glans, and every 2.5 cm of him from 4 cm inside her entrance (user, 2026-11-02, 騎乘位: the middle of him came
    // out of her lower belly with his glans still in her): the place that is the most out of her past what her belly
    // swells for (BellySwellCm; none at her back) is the one the swell and the drawing back answer.
    TArray<FVector> Points={Tip};FVector E=FVector::ZeroVector;SkinOutMost=SkinUnderMost=-100.f;SkinNormal=FVector::ZeroVector;SkinRest=0.f;SkinWorstAlong=0.f;
    const float Radius=PenisRadiusCm*PenisScale;
    auto ToUnity=[&](const FVector& At){return FVector(M[3],M[7],M[11])+AKKPreviewActor::ActorLocalToUnity(Body.InverseTransformPosition(At))-AKKPreviewActor::ActorLocalToUnity(Body.InverseTransformPosition(Kokan));};
    // How far into her skin the worst place of him goes (SkinWorst, cm, his skin PenisRadiusCm out from his middle line):
    // in her, any of him out of her (her belly, her back, her bottom); out of her, any of him in her skin (user,
    // 2026-11-02, 桌上躺位 seen from the front: with his root up her back he ran through her bottom on his way in). The way
    // out of her there (SkinNormal; in her, the way back in is the other way) is where his root goes to come off it
    // (AlignHim: RootDodge), whichever side it is. All his points in one reading (FOkSession::SkinCheck).
    SkinWorst=-100.f;
    TArray<FVector> Check;TArray<float> Sign,Along;
    if(Root&&HEntrance(Girl,Current().StartsWith(TEXT("A_")),E)){const FVector Axis=(Tip-*Root).GetSafeNormal();const float AtE=float((E-*Root)|Axis);
        const float To=float((Tip-*Root)|Axis)-2.5f;for(float S=AtE+4.f;S<To;S+=2.5f)Points.Add(*Root+Axis*S);
        // His part out of her, from 3 cm before her entrance (her opening round him is no skin to keep off) to his root.
        for(float S=AtE-3.f;S>0.f;S-=2.f){Check.Add(ToUnity(*Root+Axis*S));Sign.Add(-1.f);Along.Add(S-AtE);}}
    if(TipInside>=6.f)for(const FVector& At:Points){Check.Add(ToUnity(At));Sign.Add(1.f);Along.Add(Root&&!E.IsZero()?float((At-E)|(Tip-*Root).GetSafeNormal()):0.f);}
    // Her front at her belly (user, 2026-11-02): toward it her belly swells round him (BulgeBelly) and he goes on as deep
    // as ever whichever way the pad points him, neither turned off it nor cut short; only her back, bottom and thighs stop
    // him. From her chest (her breasts off her spine, across the line up her body), as the poses lie, stand or arch.
    FVector Front=FVector::ZeroVector;{FVector Chest,BL,BR;if(HBone(Girl,TEXT("j_spine03"),Chest)&&HBone(Girl,TEXT("j_bust01_L"),BL)&&HBone(Girl,TEXT("j_bust01_R"),BR)){
        const FVector Up=(Chest-Kokan).GetSafeNormal();Front=(BL+BR)*.5-Chest;Front=(Front-Up*(Front|Up)).GetSafeNormal();}}
    SkinFacing=-2.f;bBellySide=false;BellyFront=Front;
    TArray<float> Read;
    if(Check.Num()&&Girl->Session.SkinCheck(Check,Read))for(int32 I=0;I<Check.Num();++I){const float* R=&Read[I*5];if(R[0]>1e8f)continue;
        // In her, skin that lies within 9 cm of her entrance at rest is her lips, her perineum and the inside of her
        // opening, never the back he stops at (user, 2026-11-02, 正常位: stopped 6 cm in, his glans nowhere near her back,
        // on skin 3.7 to 4.2 cm from her entrance).
        // Only his glans stops him, and only once its middle is out through her back (user, 2026-11-02: stopped with his
        // glans nowhere near it; the skin folds of her bottom read out of her by his radius alone, their slope turning
        // every frame).
        const bool bTip=Sign[I]>0.f&&(I==0||Sign[I-1]<0.f);
        if(Sign[I]>0.f&&!bTip)continue;
        if(Sign[I]>0.f&&R[4]*100.f<9.f)continue;
        if(Sign[I]>0.f&&!Front.IsZero()){const float Facing=float(Body.TransformVectorNoScale(AKKPreviewActor::UnityToActorLocal(FVector(R[1],R[2],R[3]))).GetSafeNormal()|Front);
            // The whole front half (user, 2026-11-02: of the pad's 360 degrees, the half toward her belly is never stopped).
            if(Facing>0.f){if(R[0]*100.f+Radius>0.f){bBellySide=true;SkinFacing=FMath::Max(SkinFacing,Facing);}continue;}}
        // Her skin round her entrance touches his by right, the soft of her lips, the tops of her thighs and her perineum
        // (skin that is within 5 cm of her entrance at rest; none from 7 cm): in her his penis 6 to 9 cm in lay 0.2 to 2 cm
        // into it at the sides, unseen, and turning him off it took him 10 cm aside and 8 cm out (桌上躺位). Out of her also
        // the whole of his radius 3 cm before her entrance, none from 8 cm.
        const float Off=FMath::Abs(Along[I]),Soft=FMath::Clamp((7.f-R[4]*100.f)/2.f,0.f,1.f);
        const float Touch=Radius*FMath::Max(Soft,Sign[I]>0.f?0.f:FMath::Clamp((8.f-Off)/5.f,0.f,1.f));
        const float Out=R[0]*100.f,Into=Sign[I]>0.f?Out:Radius-Out-Touch;
        if(Sign[I]>0.f)SkinOutMost=FMath::Max(SkinOutMost,Into);else SkinUnderMost=FMath::Max(SkinUnderMost,Into);
        if(Into>SkinWorst){SkinWorst=Into;SkinRest=R[4]*100.f;SkinWorstAlong=Along[I];
            SkinNormal=Body.TransformVectorNoScale(AKKPreviewActor::UnityToActorLocal(FVector(R[1],R[2],R[3]))).GetSafeNormal();}}
    // Her belly wraps all of him in her (user, 2026-11-02: one coarse swell round his glans, pushed past its reach, stood
    // out as a black spike), his radius and half a centimetre more. Morphs made beforehand could not: each one's moves, made at rest, turned with her thighs and hips and opened black
    // wedges (GalV1103a~c). So each frame her skin over him moves by itself, in her posed body, along its own normal to
    // just past him, the skin round it rising with it (belly_bulge::wrap_deltas), drawn as one morph of her renderers.
    {const double WrapT0=FPlatformTime::Seconds();TArray<uint32> Idx;TArray<FVector3f> D,N;
     const int32 WrapMode=CVarHWrap.GetValueOnGameThread();
     // 3: her belly bones (BetterPenetration's way, the bones added to her body here) pushed by him, the skin with them.
     if(!E.IsZero()&&(WrapMode==1||WrapMode==3)&&TipInside>=6.f)Girl->Session.BellyWrapDeltas(ToUnity(E),ToUnity(Tip),Front.IsZero()?FVector::ZeroVector:(ToUnity(Kokan+Front*10.)-ToUnity(Kokan)).GetSafeNormal(),(Radius+.5f)/100.f,Idx,D,&N,WrapMode==3);
     if(const float Test=CVarHWrapTest.GetValueOnGameThread();Test!=0.f)for(FVector3f& V:D)V=FVector3f(0.f,Test,0.f);
     if(D.Num()||bWrapShown){Girl->SetPartWrapDeltas(BulgePart,Idx,D,N);bWrapShown=D.Num()>0;}WrapVerts=D.Num();WrapIdxShown=Idx;WrapDShown=D;WrapNShown=N;
     // ok.HScene.Wrap 2 (the material route, to compare): her skin parents with the wrap offset push her skin off the
     // segment from her entrance to his glans, his radius and half a centimetre (as above) out; nothing while he is in
     // her entrance alone.
     if(WrapMode==2||bWrapLineShown){const bool bLine=WrapMode==2;const bool bIn=!E.IsZero()&&TipInside>=6.f;
      Girl->SetWrapLine(bLine,E,Tip,bIn?Radius+.5f:0.f,OKWrapMaterialRoot());bWrapLineShown=bLine;}
     WrapMs=float((FPlatformTime::Seconds()-WrapT0)*1000.);}
    // His penis out through her back not drawn (user, 2026-11-02: "背部要直接把超出的部分不顯示"; her belly bones lift only
    // her belly): where the line from her entrance to his glans leaves her through skin facing away from her belly
    // (belly_bulge::back_exit), what of him is past it folds back along him to just under her skin there (clip_deltas),
    // drawn as the morph penis.clip of his penis.
    {AKKPreviewActor* Him=Gallery?Gallery->PartnerActor.Get():nullptr;
     if(ClipHim!=Him){if(bClipShown&&ClipHim.IsValid())ClipHim->SetPartWrapDeltas(ClipPart,{},{});ClipHim=Him;ClipPart=INDEX_NONE;bClipShown=false;
         for(int32 Part=0;IsValid(Him)&&Part<Him->Session.PartCount();++Part)if(Him->GetPartMorphNames(Part).Contains(FName(TEXT("penis.clip")))){ClipPart=Part;break;}
         UE_LOG(LogTemp,Display,TEXT("H scene: his penis folds under her back %s"),ClipPart!=INDEX_NONE?*FString::Printf(TEXT("on part %d"),ClipPart):TEXT("never (no penis.clip morph)"));}
     // His glans' way out of her each frame (cm, along him) times BackClipLead: the morph is drawn a frame or two after
     // his pose is read, and a fast thrust (6 cm a frame, 後背位) carried his glans out past a fold made at her skin.
     const float Lead=ClipLastTip>=0.f?FMath::Clamp((TipInside-ClipLastTip)*CVarHBackClipLead.GetValueOnGameThread(),0.f,20.f):0.f;ClipLastTip=TipInside;
     TArray<uint32> Idx;TArray<FVector3f> D;FVector At,N;BackExitCm=-1.f;
     if(IsValid(Him)&&ClipPart!=INDEX_NONE&&CVarHBackClip.GetValueOnGameThread()!=0&&!E.IsZero()&&TipInside>=6.f&&!Front.IsZero()
        &&[&]{const FVector Up=(ToUnity(Kokan+Front*10.)-ToUnity(Kokan)).GetSafeNormal();
            // Where his glans is now, else where the lead carries it (only then: the line drawn on past him found her skin
            // farther on, her upper back, and the place he comes out now was missed).
            return Girl->Session.BackExit(ToUnity(E),ToUnity(Tip),Up,At,N)||(Lead>0.f&&Girl->Session.BackExit(ToUnity(E),ToUnity(Tip+(Tip-E).GetSafeNormal()*Lead),Up,At,N));}()){
         const FVector K(M[3],M[7],M[11]),KL=AKKPreviewActor::ActorLocalToUnity(Body.InverseTransformPosition(Kokan));
         const FVector WAt=Body.TransformPosition(AKKPreviewActor::UnityToActorLocal(At-K+KL));
         const FVector WN=Body.TransformVectorNoScale(AKKPreviewActor::UnityToActorLocal(N)).GetSafeNormal();
         BackExitCm=float((WAt-E).Size());
         // Never folded back past 2 cm in from her entrance (the fold reaches 4 cm and the lead before where he comes out):
         // his shaft out of her stays drawn.
         const float Inset=FMath::Min(Lead,BackExitCm-6.f);ClipLeadCm=Inset;
         // To his skeleton space: his parts are drawn HimApplied off his actor (AlignHim).
         const FTransform& HimT=Him->GetActorTransform();
         auto HisPos=[&](const FVector& W){return AKKPreviewActor::ActorLocalToUnity(HimT.InverseTransformPosition(W-HimApplied));};
         auto HisDir=[&](const FVector& W){return (HisPos(W*100.+WAt)-HisPos(WAt)).GetSafeNormal();};
         Him->Session.PenisClipDeltas(HisPos(WAt),HisDir(WN),HisDir((Tip-E).GetSafeNormal()),Idx,D,FMath::Max(0.f,Inset)/100.f);
         // Moves under a tenth of a millimetre dropped: a set of only those has no morph batches and the engine asserts.
         for(int32 I=D.Num()-1;I>=0;--I)if(D[I].SizeSquared()<1e-8f){D.RemoveAtSwap(I);Idx.RemoveAtSwap(I);}}
     if(IsValid(Him)&&ClipPart!=INDEX_NONE&&(D.Num()||bClipShown)){Him->SetPartWrapDeltas(ClipPart,Idx,D);bClipShown=D.Num()>0;}ClipVerts=D.Num();}
    // His glans alone read out for the panel (bulge_at, belly_out): each reading skins all her swells' skin again, and
    // with the fine grid that for every point of him took the game from 100 FPS to 25.
    bool bAny=false;float Most=0.f;
    for(const FVector& At:TArrayView<const FVector>(Points.GetData(),FMath::Min(1,Points.Num()))){float Past=0.f,Near=0.f,Moves=0.f;FName Target;
        const FVector Here=AKKPreviewActor::ActorLocalToUnity(Body.InverseTransformPosition(At))-AKKPreviewActor::ActorLocalToUnity(Body.InverseTransformPosition(Kokan));
        if(!Girl->Session.BellyBulgePast(FVector(M[3],M[7],M[11])+Here,Past,Near,Target,Moves))continue;
        Past*=100.f;Moves*=100.f;const float Over=Target.ToString().StartsWith(TEXT("belly.bulge.b"))?Past+.5f:Past+1.f-FMath::Clamp(Moves-2.5f,0.f,BellySwellCm);
        if(!bAny||Over>Most){bAny=true;Most=Over;BulgeTarget=Target;BulgePast=Past;BulgeMoves=Moves;}}
    if(!bAny)BulgeTarget=NAME_None;
}
// Her tears' way down her face from under each eye wanted (TearsWanted: 1 left, 2 right), read from her session as she
// is posed (FOkSession::FaceTearPath, every 4 mm, 0.8 mm off her skin), hung on her head bone (FOKTears).
void UOKHScenePanel::SpawnTears(AKKPreviewActor* Girl){
    const uint8 Want=TearsWanted;TearsWanted=0;FVector Kokan,Head;float M[16];
    if(!IsValid(Girl)||!Girl->BodySkel||!HBone(Girl,TEXT("J_Kokan"),Kokan)||!HBone(Girl,TEXT("j_head"),Head)||!(Girl->Session.BoneWorldMatrix(TEXT("cf_J_Kokan"),M)||Girl->Session.BoneWorldMatrix(TEXT("cf_j_kokan"),M)))return;
    const FTransform& Body=Girl->GetActorTransform();const FVector K(M[3],M[7],M[11]),KL=AKKPreviewActor::ActorLocalToUnity(Body.InverseTransformPosition(Kokan));
    auto ToUnity=[&](const FVector& W){return K+AKKPreviewActor::ActorLocalToUnity(Body.InverseTransformPosition(W))-KL;};
    auto ToWorld=[&](const FVector& U){return Body.TransformPosition(AKKPreviewActor::UnityToActorLocal(U-K+KL));};
    const FVector Down=(ToUnity(Kokan-FVector(0,0,100))-ToUnity(Kokan)).GetSafeNormal();
    const FName HeadBone=Girl->BodySkel->GetBoneIndex(TEXT("cf_j_head"))!=INDEX_NONE?FName(TEXT("cf_j_head")):FName(TEXT("cm_j_head"));
    for(int32 Side=0;Side<2;++Side){if(!(Want&(1<<Side)))continue;FVector Eye;if(!HBone(Girl,Side?TEXT("J_Eye02_s_R"):TEXT("J_Eye02_s_L"),Eye))continue;
        // From just under her eye: the nearest skin there is her lower lid.
        TArray<FVector> P,N;if(!Girl->Session.FaceTearPath(ToUnity(Eye-FVector(0,0,1.f)),Down,.004f,.0008f,40,P,N))continue;
        TArray<FVector> WP,WN;for(int32 I=0;I<P.Num();++I){WP.Add(ToWorld(P[I]));WN.Add(Body.TransformVectorNoScale(AKKPreviewActor::UnityToActorLocal(N[I])).GetSafeNormal());}
        Tears.Add(Girl,Girl->BodySkel,HeadBone,WP,WN);
        UE_LOG(LogTemp,Verbose,TEXT("H scene: a tear down her %s cheek, %d points"),Side?TEXT("right"):TEXT("left"),WP.Num());}
}
// In her mouth his penis points straight in through her lips, against the way her face looks: from the middle of her
// head (j_head) to her nose tip, across her face only (not toward either eye). The clips point it at right angles to that
// (up her face from her chin; 90 degrees, measured 2026-11-02), so drawn in to nine tenths it came out through her upper
// lip and nose (user, 2026-11-02). His penis root turned (his FK, belly_bulge::aim_penis); the alignment then puts that
// line through her mouth (AlignHim). ok.HScene.SuckAim: how much of the way from the clip's line to that (0 by default: what
// is past her lips is hidden instead, HideInMouth; turned, he moved far off his pose to reach her). Only while she
// sucks him; his own pose again after.
void UOKHScenePanel::AimIntoMouth(AKKPreviewActor* Girl,AKKPreviewActor* Him){
    if(!IsValid(Him))return;
    FVector Head,Nose,EyeL,EyeR,P0,P1;const float Share=FMath::Clamp(CVarHSuckAim.GetValueOnGameThread(),0.f,1.f);
    if(!bSucking||Share<=0.f||!IsValid(Girl)||!HBone(Girl,TEXT("j_head"),Head)||!HBone(Girl,TEXT("J_Nose_tip"),Nose)||!HBone(Girl,TEXT("J_Eye02_s_L"),EyeL)||!HBone(Girl,TEXT("J_Eye02_s_R"),EyeR)
        ||!HBone(Him,TEXT("J_dan100_00"),P0)||!HBone(Him,TEXT("J_dan109_00"),P1)){if(bMouthAimed){Him->Session.SetFk({},{});bMouthAimed=false;}MouthAim=FVector::ZeroVector;MouthTurned=0.f;return;}
    const FVector Up=((EyeL+EyeR)*.5f-Head).GetSafeNormal(),Across=(EyeL-EyeR).GetSafeNormal();FVector Fwd=Nose-Head;Fwd-=Across*FVector::DotProduct(Fwd,Across);
    // The clip's line as she started sucking (later he is drawn turned).
    const FVector Clip=(P1-P0).GetSafeNormal();MouthAim=MouthAim.IsNearlyZero()?Clip:MouthAim;
    const FVector Want=FMath::Lerp(MouthAim,-Fwd.GetSafeNormal(),Share).GetSafeNormal();
    auto Deg=[](const FVector& A,const FVector& B){return FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(float(A.GetSafeNormal()|B.GetSafeNormal()),-1.f,1.f)));};
    MouthDbg=FVector(Deg(Clip,Want),Deg(Clip,Up),Deg(Fwd,FVector(0,0,-1)));float Turned=0.f;if(Want.IsNearlyZero())return;
    if(Him->Session.AimPenis(AKKPreviewActor::ActorLocalToUnity(Him->GetActorTransform().InverseTransformVector(Want)),Turned)){
        if(!bMouthAimed)UE_LOG(LogTemp,Display,TEXT("H scene: his penis turned %.1f degrees into her mouth"),Turned);bMouthAimed=true;MouthTurned=Turned;}
}
// In her mouth what of him is past two centimetres in is not drawn (user, 2026-11-02: drawn in to nine tenths along the
// clip's line it came out through her upper lip and nose): it folds back along him onto the plane across him there
// (belly_bulge clip_deltas, the morph penis.clip of his penis, as at her back), inside her mouth. Her lips: between the
// corners of her mouth (J_MouthBase_s sits above the opening once her lower face is drawn out, and he showed 1.5 cm over
// her upper lip).
void UOKHScenePanel::HideInMouth(AKKPreviewActor* Girl,AKKPreviewActor* Him){
    if(!IsValid(Him))return;
    if(MouthClipHim!=Him){MouthClipHim=Him;MouthClipPart=INDEX_NONE;MouthClipVerts=0;
        for(int32 Part=0;Part<Him->Session.PartCount();++Part)if(Him->GetPartMorphNames(Part).Contains(FName(TEXT("penis.clip")))){MouthClipPart=Part;break;}}
    if(MouthClipPart==INDEX_NONE)return;
    const float Cm=CVarHSuckHideCm.GetValueOnGameThread();FVector CornerL,CornerR,P0,P1;TArray<uint32> Idx;TArray<FVector3f> D;
    if(bSucking&&Cm>0.f&&IsValid(Girl)&&HBone(Girl,TEXT("J_Mouth_L"),CornerL)&&HBone(Girl,TEXT("J_Mouth_R"),CornerR)&&HBone(Him,TEXT("J_dan100_00"),P0)&&HBone(Him,TEXT("J_dan109_00"),P1)){
        const FVector Lips=(CornerL+CornerR)*.5f;
        // To his skeleton space: his parts are drawn HimApplied off his actor (AlignHim). The plane sits 1 cm (CLIP_IN_M)
        // in from the point given.
        const FVector Axis=(P1-P0).GetSafeNormal();const FTransform& HimT=Him->GetActorTransform();
        auto HisPos=[&](const FVector& W){return AKKPreviewActor::ActorLocalToUnity(HimT.InverseTransformPosition(W-HimApplied));};
        const FVector At=Lips+Axis*(Cm+1.f);const FVector HisAxis=(HisPos(At+Axis*100.)-HisPos(At)).GetSafeNormal();
        Him->Session.PenisClipDeltas(HisPos(At),HisAxis,HisAxis,Idx,D);
        // Moves under a tenth of a millimetre dropped: a set of only those is below the morph buffer's 20 micrometres, has
        // no batches, and the engine asserts (NumTotalBatches > 0, 2026-11-02).
        for(int32 I=D.Num()-1;I>=0;--I)if(D[I].SizeSquared()<1e-8f){D.RemoveAtSwap(I);Idx.RemoveAtSwap(I);}}
    if(D.Num()||MouthClipVerts){Him->SetPartWrapDeltas(MouthClipPart,Idx,D);MouthClipVerts=D.Num();}
}
// Her clothes kept over her skin (user, 2026-11-02: her nipples, her swollen bust and her belly lifted over his penis came
// through her clothes): each frame her breasts and the skin lifted over him push her garments out over them
// (belly_bulge::cover_deltas), drawn as a morph of each garment. ok.HScene.ClothCover 0 leaves her clothes as they are.
static TAutoConsoleVariable<int32> CVarHClothCover(TEXT("ok.HScene.ClothCover"),1,TEXT("1: her clothes are pushed out over her breasts and her belly lifted over his penis (belly_bulge::cover_deltas); 0 off"));
void UOKHScenePanel::CoverClothes(AKKPreviewActor* Girl){
    if(ClothGirl.Get()!=Girl){if(AKKPreviewActor* Was=ClothGirl.Get()){for(int32 Part:ClothShown)Was->SetPartWrapDeltas(Part,{},{});TArray<int32> None;Was->Session.SetClothCover(false,{},{},{},None);Was->CpuSkinnedParts.Reset();}ClothShown.Reset();ClothCpuUntil.Reset();ClothGirl=Girl;}
    if(!IsValid(Girl))return;
    // Her garments with their own rig, as they are skinned on the CPU in her next frame (drawn from those vertices then:
    // the private GPU route skins its own copy of the rest mesh); those on her body skeleton below, as a morph.
    // Kept there two seconds after it last reached her pushing skin: switching a garment between the routes each frame
    // rebuilt its GPU display every time.
    {TArray<int32> Cpu;Girl->Session.SetClothCover(CVarHClothCover.GetValueOnGameThread()!=0,WrapIdxShown,WrapDShown,WrapNShown,Cpu);
     const double Now=FPlatformTime::Seconds();for(int32 Part:Cpu)ClothCpuUntil.Add(Part,Now+2.);
     for(auto It=ClothCpuUntil.CreateIterator();It;++It)if(It.Value()<Now||Cpu.IsEmpty()&&CVarHClothCover.GetValueOnGameThread()==0)It.RemoveCurrent();
     TSet<int32> Keep;ClothCpuUntil.GetKeys(Keep);if(!Keep.Includes(Girl->CpuSkinnedParts)||!Girl->CpuSkinnedParts.Includes(Keep))Girl->CpuSkinnedParts=MoveTemp(Keep);}
    const double T0=FPlatformTime::Seconds();TArray<int32> Parts;TArray<uint32> Idx;TArray<FVector3f> D;
    if(CVarHClothCover.GetValueOnGameThread()!=0)Girl->Session.ClothCoverDeltas(WrapIdxShown,WrapDShown,WrapNShown,Parts,Idx,D);
    TMap<int32,TPair<TArray<uint32>,TArray<FVector3f>>> ByPart;
    // Moves under a tenth of a millimetre dropped: a set of only those has no morph batches and the engine asserts.
    for(int32 I=0;I<Parts.Num();++I)if(D[I].SizeSquared()>=1e-8f){auto& P=ByPart.FindOrAdd(Parts[I]);P.Key.Add(Idx[I]);P.Value.Add(D[I]);}
    for(auto It=ClothShown.CreateIterator();It;++It)if(!ByPart.Contains(*It)){Girl->SetPartWrapDeltas(*It,{},{});It.RemoveCurrent();}
    ClothVerts=0;for(const auto& P:ByPart)if(Girl->SetPartWrapDeltas(P.Key,P.Value.Key,P.Value.Value)){ClothShown.Add(P.Key);ClothVerts+=P.Value.Key.Num();}
    ClothMs=float((FPlatformTime::Seconds()-T0)*1000.);
}
void UOKHScenePanel::ReadPairSessions(){
    // Both sessions are idle and show this frame (AKKPairedPlayback::OnSessionsIdle). Reading them at any other time while
    // the pair plays meant either a crash (the solve was writing them) or values several frames old: a tick almost never
    // finds the background solve finished, and the swell missed his glans coming out.
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;auto* Him=Gallery?Gallery->PartnerActor.Get():nullptr;FVector P0,Glans;
    ON_SCOPE_EXIT{CoverClothes(Girl);};
    if(TearsWanted)SpawnTears(Girl);AimIntoMouth(Girl,Him);HideInMouth(Girl,Him);
    if(IsValid(Him)&&(PenisSetLength!=PenisLength||PenisSetScale!=PenisScale)&&Him->Session.SetPenisSize(PenisLength,PenisScale)){PenisSetLength=PenisLength;PenisSetScale=PenisScale;
        UE_LOG(LogTemp,Display,TEXT("H scene: his penis length x%.2f size x%.2f"),PenisLength,PenisScale);}
    if(!IsValid(Girl)||!IsValid(Him)||AlignedHim!=Him||!HBone(Him,TEXT("J_dan100_00"),P0)||!Him->Session.PenisTip(Glans))return;
    GlansFromRoot=Him->GetActorTransform().TransformPosition(AKKPreviewActor::UnityToActorLocal(Glans))+HimApplied-P0;bGlans=true;
    if(BulgedHer==Girl&&BulgePart!=INDEX_NONE)ReadBulge(Girl,P0+GlansFromRoot,&P0);
    // In her, his penis runs along the way into her (her entrance to her lower spine, J_Ana for the back): the clips point
    // it where the original pins its tip at her entrance (Lookat_dan: cm_J_dan101 looks at k_f_kokan_00, dan109 stuck
    // there), so at the depth he goes here (a fifth to nine tenths of him, user R20) it came out of her belly or went into
    // the floor (躺姿後入, user 2026-11-01). Its root turns (his FK); the alignment then puts that line through her
    // entrance. In every pose his glans heads for the front of her belly with her entrance as the pivot (user, 2026-11-01:
    // what the game needs; the physics can follow later): from her entrance up along her spine, turned 35 degrees toward
    // her front. Her front is the way her breasts sit from her upper spine, across her spine (her crotch moved with her
    // legs, 0.4 to 7.7 cm before her spine, R20l), and a point a set way before her spine aimed only 0 to 17 degrees off
    // it (hips to mid spine is 7 cm). Half the clip's line and half the way to her spine (R20j) still went up her back.
    // Her thighs drawn up before her belly (抬腿朝天, 大張腿, 打樁, 桌球桌, 靠牆背面騎乘, user 2026-11-01) are on that line:
    // seen from the side his glans went into her thigh, not her belly, and the part outside her into the back of it. So
    // the tilt nearest the way to her belly (below; 5-degree steps, 70 down to -40) that keeps him, 3 to 16 cm in and out of her entrance, clear of both thighs
    // (from a third of the way to the knee: at the hip they are by her entrance in any pose; as thick as 0.42 of the way
    // between her hip joints); none clear, the one farthest from them.
    // Outside her (Idle, the insertion itself, after) his penis keeps the clip's angle.
    const FString Cur=Current(),Base=HBase(Cur);
    const bool bInHer=Mode==2&&Base!=TEXT("Idle")&&Base!=TEXT("Insert")&&!Base.Contains(TEXT("OUT"))&&!Base.StartsWith(TEXT("Pull"))&&!Base.StartsWith(TEXT("Drop"));
    if(LiftedPose!=ActivePose||!bInHer){if(bLifted){Him->Session.SetFk({},{});bLifted=false;}LiftedPose=ActivePose;}
    FVector Entrance,Hips,Chest,BustL,BustR;
    if(bInHer&&HEntrance(Girl,Cur.StartsWith(TEXT("A_")),Entrance)&&HBone(Girl,TEXT("j_hips"),Hips)
        &&HBone(Girl,TEXT("j_spine03"),Chest)&&HBone(Girl,TEXT("j_bust01_L"),BustL)&&HBone(Girl,TEXT("j_bust01_R"),BustR)){
        const FVector Up=(Chest-Hips).GetSafeNormal();FVector Front=(BustL+BustR)*.5f-Chest;Front-=Up*FVector::DotProduct(Front,Up);
        FVector ThighL,ThighR,KneeL,KneeR;const bool bThighs=HBone(Girl,TEXT("j_thigh00_L"),ThighL)&&HBone(Girl,TEXT("j_thigh00_R"),ThighR)&&HBone(Girl,TEXT("j_leg01_L"),KneeL)&&HBone(Girl,TEXT("j_leg01_R"),KneeR);
        const float Thick=bThighs?FMath::Clamp(.42f*float(FVector::Dist(ThighL,ThighR)),5.f,10.f):0.f;
        auto Along=[&](float Degrees){const float T=FMath::DegreesToRadians(Degrees);return (Up*FMath::Cos(T)+Front.GetSafeNormal()*FMath::Sin(T)).GetSafeNormal();};
        auto Clear=[&](const FVector& W){if(!bThighs)return 99.f;FVector A,B;float Most=99.f;
            for(const auto& Leg:{TPair<FVector,FVector>(ThighL,KneeL),TPair<FVector,FVector>(ThighR,KneeR)}){
                for(const float Way:{1.f,-1.f}){FMath::SegmentDistToSegmentSafe(Entrance+W*(3.f*Way),Entrance+W*(16.f*Way),FMath::Lerp(Leg.Key,Leg.Value,.3f),Leg.Value,A,B);Most=FMath::Min(Most,float(FVector::Dist(A,B))-Thick);}}
            return Most;};
        // A set 35 degrees off her upper spine went over her belly wherever her pelvis is rolled up (大張腿, 抬腿朝天:
        // her entrance above the line of her body, the line through the thighs over her belly; user 2026-11-01, seen from
        // the side and the front). So straight at her belly: from her entrance to the point half her hip width before her
        // spine at her navel (j_spine02), whatever way her pelvis is turned; 35 degrees only without those bones.
        FVector Navel;float Start=35.f,ToBelly=-99.f;
        if(bThighs&&HBone(Girl,TEXT("j_spine02"),Navel)){const FVector To=(Navel+Front.GetSafeNormal()*(.5f*float(FVector::Dist(ThighL,ThighR)))-Entrance).GetSafeNormal();
            ToBelly=FMath::RadiansToDegrees(FMath::Atan2(float(FVector::DotProduct(To,Front.GetSafeNormal())),float(FVector::DotProduct(To,Up))));Start=FMath::Clamp(ToBelly,-30.f,70.f);}
        float Tilt=Start,BestClear=-99.f,Best=Start;
        for(int32 K=0;K<=30;++K){const float T=Start+5.f*float((K+1)/2)*(K%2?-1.f:1.f);if(T<-40.f)continue;if(T>70.f)continue;const float C=Clear(Along(T));if(C>=1.f){Best=T;BestClear=C;break;}if(C>BestClear){BestClear=C;Best=T;}}
        // Eased there (90 degrees a second, straight on a new pose): her legs move as he thrusts, five-degree steps would jump.
        AimTilt=!bLifted?Best:FMath::FInterpConstantTo(AimTilt,Best,FApp::GetDeltaTime(),360.f);Tilt=AimTilt*(1.f-AimRelax);FVector Want=Along(Tilt);
        // His root moved on the pad (SetRootPad): RootReach cm toward that side at its edge, her entrance still the pivot,
        // so his penis points from there through her entrance. Up the pad is her back, right her right (the converted
        // skeleton is mirrored: her _L thigh is on her right).
        // The pad eased, its radius a second: a jump of the root swung him through her before the dodge caught up.
        RootPadNow=FMath::Vector2DInterpConstantTo(RootPadNow,RootPad,FApp::GetDeltaTime(),1.f);
        if(!RootPadNow.IsNearlyZero()||!RootDodge.IsNearlyZero()){FVector Back=-Front;Back-=Want*FVector::DotProduct(Back,Want);
            FVector Right=bThighs?ThighL-ThighR:FVector::CrossProduct(Want,Back);Right-=Want*FVector::DotProduct(Right,Want);
            const float Reach=bGlans?float(GlansFromRoot.Size()):15.f;
            // As long and big as he is made (user, 2026-11-02: a longer penis turned less for the same pad, and lay under
            // her belly instead of pushing it up): the pad is an angle.
            const FVector Shift=(Back.GetSafeNormal()*RootPadNow.Y+Right.GetSafeNormal()*RootPadNow.X)*RootReach*PenisLength*PenisScale+(RootDodge-Want*FVector::DotProduct(RootDodge,Want));
            Want=(Want*Reach-Shift).GetSafeNormal();}
        if(!bLifted)UE_LOG(LogTemp,Display,TEXT("H scene: %s aim at her belly (breasts %.1f cm before her spine, her lower belly %.0f degrees), tilt %.0f, %.1f cm clear of her thighs"),*Cur,float(Front.Size()),ToBelly,Tilt,BestClear);
        const FVector Dir=AKKPreviewActor::ActorLocalToUnity(Him->GetActorTransform().InverseTransformVector(Want));float Turned=0.f;
        if(Him->Session.AimPenis(Dir,Turned)){if(!bLifted)UE_LOG(LogTemp,Display,TEXT("H scene: %s his penis turned %.1f degrees along the way into her"),*Cur,Turned);bLifted=true;}}
}
void UOKHScenePanel::AlignHim(float Delta){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;auto* Him=Gallery?Gallery->PartnerActor.Get():nullptr;
    if(!IsValid(Girl)||!IsValid(Him))return;
    if(AKKPairedPlayback* Playback=Gallery->PairedPlayback.Get();Playback!=ReadingPlayback.Get()){
        if(AKKPairedPlayback* Was=ReadingPlayback.Get())Was->OnSessionsIdle.Remove(ReadingHandle);
        ReadingPlayback=Playback;ReadingHandle=IsValid(Playback)?Playback->OnSessionsIdle.AddUObject(this,&UOKHScenePanel::ReadPairSessions):FDelegateHandle();}
    if(AlignedHim!=Him){AlignedHim=Him;HimApplied=FVector::ZeroVector;bHisIk=false;bGlans=false;} // a new him has his parts where they were made
    if(AlignedHer!=Girl){AlignedHer=Girl;HerApplied=FVector::ZeroVector;bHerIk=false;}
    const FString Key=FString::Printf(TEXT("%d|%d"),Mode,ActivePose);
    // A new pose places them on one origin again: start from no offset, no held feet.
    if(Key!=AlignedKey){AlignedKey=Key;AimRelax=0.f;RootDodge=FVector::ZeroVector;DepthCap=1.f;BellyPullback=0.f;bPullbackLogged=false;HimOffset=HerOffset=FVector::ZeroVector;bAlignLogged=false;DeepAlong=1e9f;AlignPushed=0.f;ThrustApplied=0.f;ThrustLow=1.f;ThrustHigh=0.f;AtWindow=0.f;AtMin=1e9f;AtMax=-1e9f;
        if(bHisIk||bHerIk)SyncPair();
        if(bHisIk){Him->Session.SetStudioIk({},{});bHisIk=false;}if(bHerIk){Girl->Session.SetStudioIk({},{});bHerIk=false;}
        FeetWait=0;bFeetRead=false;}
    AlignOff=-1.f;AlignTip=-1.f;TipInside=-1.f;bool bBulged=false;
    const FString Cur=Current(),Base=HBase(Cur);
    // Her mouth (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md): while she sucks him (a mouth service pose's loops) he is put on
    // the line into her mouth and taken as deep as her mouth is developed, like her vagina.
    const bool bOral=Mode==1&&Poses.IsValidIndex(ActivePose)&&Poses[ActivePose].KindHoushi==1&&Gallery->PairedPlayback&&Gallery->PairedPlayback->GetElapsed()>0.f&&(HIsLoop(Base)||Base==TEXT("OLoop"));
    bSucking=bOral;
    const bool In=bOral||Mode==2&&Gallery->PairedPlayback&&Gallery->PairedPlayback->GetElapsed()>0.f&&(Base==TEXT("Insert")||Base==TEXT("InsertIdle")||Base.EndsWith(TEXT("Loop"))&&!Base.Contains(TEXT("OUT"))||Base.Contains(TEXT("_IN_"))||Base==TEXT("IN_A"));
    // Where their feet are in the clip (no IK yet), and whether each stands on the floor: read a few frames into the pose.
    if(In&&!bFeetRead&&++FeetWait>3){
        const float Floor=float(Girl->GetActorLocation().Z);SyncPair();
        auto Read=[&](AKKPreviewActor* A,FVector (&Feet)[2],bool& bStands){FString Error;bStands=false;
            if(!A->bStudioIkReady){if(!A->Session.PrepareStudioIk(Error)){UE_LOG(LogTemp,Warning,TEXT("H align: no IK for %s: %s"),*A->GetName(),*Error);return;}A->bStudioIkReady=true;}
            FVector L,R,Hips;if(!A->Session.IkEffectorPosition(7,Feet[0])||!A->Session.IkEffectorPosition(8,Feet[1])||!HBone(A,TEXT("j_foot_L"),L)||!HBone(A,TEXT("j_foot_R"),R)||!HBone(A,TEXT("j_hips"),Hips))return;
            // On a foot (the other may be lifted) with the hips well over it: kneeling, sitting and lying have a foot near the
            // floor too, and lowering those sinks knees and backs into the floor.
            const float Low=float(FMath::Min(L.Z,R.Z));bStands=Low-Floor<18.f&&float(Hips.Z)-Low>60.f;};
        Read(Him,HisFeet,bHisStands);Read(Girl,HerFeet,bHerStands);bFeetRead=true;
        UE_LOG(LogTemp,Display,TEXT("H align: %s he %s, she %s"),*Cur,bHisStands?TEXT("stands"):TEXT("does not stand"),bHerStands?TEXT("stands"):TEXT("does not stand"));
    }
    FVector E,P0,P1;
    if(In&&(bOral?HBone(Girl,TEXT("J_MouthCavity"),E)||HBone(Girl,TEXT("J_MouthBase_s"),E):HEntrance(Girl,Cur.StartsWith(TEXT("A_")),E))&&HBone(Him,TEXT("J_dan100_00"),P0)&&HBone(Him,TEXT("J_dan109_00"),P1)){
        const FVector Axis=(P1-P0).GetSafeNormal();const float Len=float((P1-P0).Size());
        if(Len>2.f){
            const FVector D=E-P0;const float Along=float(D|Axis);const FVector Fix=D-Axis*Along; // onto the line of the penis
            AlignOff=float(Fix.Size());AlignAt=100.f*Along/Len;AlignLen=Len;
            // His glans: the end of his penis mesh, from his session (ReadPairSessions while the pair plays, kept from his
            // root between reads). Not J_dan109: the dan bones draw in as he goes in (17.8 cm at her entrance, 5 to 9 in a
            // loop) while his penis is drawn whole, so that bone is mid-shaft then and everything measured at it came out short.
            {FVector Glans;if(!IsValid(Gallery->PairedPlayback.Get())&&Him->Session.PenisTip(Glans)){
                 GlansFromRoot=Him->GetActorTransform().TransformPosition(AKKPreviewActor::UnityToActorLocal(Glans))+HimApplied-P0;bGlans=true;}}
            const FVector Tip=bGlans?P0+GlansFromRoot:P1;
            // Only a glans well inside her can come through her skin from within (user, 2026-11-01: drawn back, his glans
            // out of her by her bottom was read as through her skin and the swell pulled her bottom out after him).
            TipInside=float((Tip-E)|Axis);
            // How far his tip is off the line into her (her entrance to her lower spine): along it, he runs inside her; well off
            // it, his penis comes out through her belly or her bottom (the angle of the clip, not the place).
            {FVector Spine;if(!bOral&&HBone(Girl,TEXT("j_spine01"),Spine)){const FVector Seg=Spine-E;const float L2=float(Seg.SizeSquared());const float T=L2>1.f?FMath::Clamp(float((Tip-E)|Seg)/L2,0.f,1.f):0.f;AlignTip=float((Tip-(E+Seg*T)).Size());BulgeBelly(Girl,&Tip,AlignTip,Delta);bBulged=true;}}
            {FVector FL,FR;float Foot=1e9f;if(HBone(Him,TEXT("j_foot_L"),FL))Foot=float(FL.Z);if(HBone(Him,TEXT("j_foot_R"),FR))Foot=FMath::Min(Foot,float(FR.Z));AlignFoot=Foot-float(Girl->GetActorLocation().Z);}
            AtMin=FMath::Min(AtMin,AlignAt);AtMax=FMath::Max(AtMax,AlignAt);AtWindow+=Delta;
            {const float Floor=float(Girl->GetActorLocation().Z);AKKPreviewActor* Who[2]={Him,Girl};
             for(int32 W=0;W<2;++W){FVector FL,FR;if(HBone(Who[W],TEXT("j_foot_L"),FL)&&HBone(Who[W],TEXT("j_foot_R"),FR)){const float F=float(FMath::Min(FL.Z,FR.Z))-Floor;FeetMin[W]=FMath::Min(FeetMin[W],F);FeetMax[W]=FMath::Max(FeetMax[W],F);}}}
            if(AtWindow>=2.f){AtShownMin=AtMin;AtShownMax=AtMax;AtWindow=0.f;AtMin=1e9f;AtMax=-1e9f;
                for(int32 W=0;W<2;++W){FeetShown[W*2]=FeetMin[W];FeetShown[W*2+1]=FeetMax[W];FeetMin[W]=1e9f;FeetMax[W]=-1e9f;}}
            // Depth: moving, he draws out until a fifth of him is in her and goes back in to nine tenths, in time with the
            // clip's own thrust (its shallowest and deepest of late; the clips hardly move him, so he stayed all the way in,
            // user R20); still in her (InsertIdle), nine tenths. The insertion itself starts with him outside her: its line is
            // aligned, its depth is the clip's.
            float Thrust=0.f;
            if(Base!=TEXT("Insert")){
                const float Full=bGlans?float(GlansFromRoot.Size()):Len;
                const float Raw=Along+ThrustApplied; // where the clip has him, before this push along his penis
                if(ThrustLow>ThrustHigh){ThrustLow=ThrustHigh=Raw;}
                const float Forget=FMath::Min(1.f,Delta*.5f);
                ThrustLow=Raw<ThrustLow?Raw:ThrustLow+(Raw-ThrustLow)*Forget;ThrustHigh=Raw>ThrustHigh?Raw:ThrustHigh+(Raw-ThrustHigh)*Forget;
                // How deep she takes him is her development there (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md): at most half of
                // him at first (her anus 40%), nine tenths at 100%; he draws out to a fifth.
                // Her mouth: a tenth to 30% at first, to 90% (his root) at 100% (user, 2026-11-02; was 70%).
                // Her crotch 50% to 90%, her anus 40% to 90% (user, 2026-11-02, again after the set 20% to 90% used to find
                // why he would not go in).
                const float Top=bOral?FMath::Lerp(.3f,.6f,Dev(TEXT("oral"))):bAnalPlay?FMath::Lerp(.4f,.9f,Dev(TEXT("anal"))):FMath::Lerp(.5f,.9f,Dev(TEXT("crotch")));
                const float Low=bOral?.1f:.2f;
                float InHer=Top;
                if((HIsLoop(Base)||Base==TEXT("OLoop"))&&ThrustHigh-ThrustLow>.5f)InHer=Low+(Top-Low)*FMath::SmoothStep(0.f,1.f,(ThrustHigh-Raw)/(ThrustHigh-ThrustLow));
                Thrust=Raw-Full*(1.f-InHer);AlignDeep=100.f*InHer;
                // Never through her belly (user, 2026-11-01: in several poses his penis came out of her belly): past
                // what her belly's swell can cover (BulgePast against BulgeMoves less the 2.5 cm round his glans) he is
                // drawn back along himself until it covers him; with room again he goes back in, 3 cm a second.
                // At her back (user, 2026-11-02): he stops there, her back does not swell for him.
                // Any part of him out of her skin anywhere round there (ReadBulge: SkinOutMost), with a centimetre to spare.
                // Measured on his middle line: his skin is PenisRadiusCm (times his size) out from it (user, 2026-11-02, 桌上躺位:
                // his middle 0.7 cm clear of her bottom and his skin in it).
                const float Radius=PenisRadiusCm*PenisScale;
                if(!bOral){const float Over=SkinWorst;
                    // His root stays where the pad puts it, at any angle (user, 2026-11-02: turned off her skin on its own it
                    // went 8 cm to one side): only his depth answers her skin (below), and toward her belly it swells for
                    // him instead (ReadBulge).
                    const float Side=SkinNormal.IsZero()?1.f:float((SkinNormal-(bGlans?GlansFromRoot.GetSafeNormal()*FVector::DotProduct(SkinNormal,GlansFromRoot.GetSafeNormal()):FVector::ZeroVector)).Size());
                    RootDodge=FVector::ZeroVector;
                    // What turning him cannot take he does not go as deep for: her body has no room for all of him there
                    // (地板背面坐位, 掛腳對面坐位: 11 to 15 cm in, skin on every side). How deep he may go (DepthCap, of
                    // him) comes down while the part in her is through her, and goes up 2% a second while not; only the
                    // deepest of each stroke is cut, the stroke stays as played below it (drawing all of him back by a
                    // set amount came too late at each deepest and too early everywhere else). Never out of her for it:
                    // at most back to the shallowest of the stroke.
                    if(Over>0.f&&SkinWorstAlong>0.f)DepthCap=FMath::Min(DepthCap,InHer)-Over*FMath::Max(.5f,1.f-FMath::Min(1.f,Side))*FMath::Min(1.f,Delta*12.f)/FMath::Max(1.f,Full);
                    else DepthCap+=.02f*Delta;
                    DepthCap=FMath::Clamp(DepthCap,Low,1.f);
                    BellyPullback=0.f; // no depth cap for now (user, 2026-11-02); DepthCap is still read out
                    if(BellyPullback>.5f&&!bPullbackLogged){bPullbackLogged=true;UE_LOG(LogTemp,Display,TEXT("H align: %s drawn back %.1f cm so her belly covers him (%.1f cm out, swell %.1f)"),*Cur,BellyPullback,BulgePast,BulgeMoves);}
                    Thrust-=BellyPullback;AlignDeep=100.f*FMath::Max(0.f,InHer-BellyPullback/FMath::Max(1.f,Full));}
                // Her breaths go on as the original plays them, one after another and each heard to its end (user,
                // 2026-11-01: not cut at every stroke), only faster with him at their own pitch (user: sped up they
                // must not go higher): the next one plays the breath just heard against the time between his last two
                // strokes, up to 1.8 times, time-stretched (SpeechTempo). Out of the loops, at their own pace.
                if(HIsLoop(Base)||Base==TEXT("OLoop")){const bool Deep=InHer>Top-.1f;const double Now=FPlatformTime::Seconds();
                    if(Deep&&!bStrokeDeep){const double Period=Now-StrokeCryAt;StrokeCryAt=Now;
                        const UKKSpeechWave* Wave=Girl->SpeechWave.Get();const float Heard=Wave&&Wave->Pcm&&Wave->Pcm->SampleRate>0&&Wave->Pcm->Channels>0?Girl->SpeechTempo*float(Wave->Pcm->Samples.Num())/(Wave->Pcm->SampleRate*Wave->Pcm->Channels):0.f;
                        if(Girl->bHBreath&&Period>.2&&Period<3.&&Heard>0.f)Girl->SpeechTempo=FMath::Clamp(Heard/float(Period),1.f,1.8f);}
                    bStrokeDeep=Deep;}
                else if(Girl->SpeechTempo!=1.f)Girl->SpeechTempo=1.f;
            }
            if(!bAlignLogged){bAlignLogged=true;UE_LOG(LogTemp,Display,TEXT("H align: %s penis %.1f cm, her entrance %.1f cm off its line at %.0f%% of it"),*Cur,Len,AlignOff,AlignAt);}
            // All the way onto her entrance each frame (user, 2026-11-02: riding her, eased a tenth of a second behind, his
            // penis stood off her and came out of her belly while she moved, right only when paused).
            HimOffset+=Fix+Axis*(Thrust-ThrustApplied);AlignPushed=Thrust;ThrustApplied=Thrust;
            // A mismatch past 45 cm is a different pose, not a height; as many times that as his penis is made longer and
            // bigger (user, 2026-11-02: four times as long, he stopped 45 cm short and hardly went in her).
            HimOffset=HimOffset.GetClampedToMaxSize(45.f*FMath::Max(1.f,PenisLength*PenisScale));
            // Both standing: the one who would have to go down bends, and nobody rises off the floor.
            if(bFeetRead&&bHisStands&&bHerStands){const double Net=HimOffset.Z-HerOffset.Z;
                if(Net>0.){HerOffset.Z=-Net;HimOffset.Z=0.;}else{HerOffset.Z=0.;HimOffset.Z=Net;}}
        }
    }
    if(!bBulged)BulgeBelly(Girl,nullptr,0.f,Delta);
    MoveParts(Him,HimOffset,HimApplied);
    {const double Was=HerApplied.Z;MoveParts(Girl,HerOffset,HerApplied);const double Down=HerApplied.Z-Was;
     if(Down!=0.&&bPropsTable)for(AStaticMeshActor* Prop:Props)if(IsValid(Prop))Prop->AddActorWorldOffset(FVector(0.,0.,Down));}
    {FVector L,R,Q0,Q1;if(bSucking&&HBone(Girl,TEXT("J_Mouth_L"),L)&&HBone(Girl,TEXT("J_Mouth_R"),R)&&HBone(Him,TEXT("J_dan100_00"),Q0)&&HBone(Him,TEXT("J_dan109_00"),Q1))
        GripHim(Girl,Him,(L+R)*.5f,Q0,(Q1-Q0).GetSafeNormal());else{HandEff.Reset();HandAt.Reset();}}
    if(bFeetRead){HoldFeet(Him,bHisStands,HimOffset,HisFeet,HisHeld,bHisIk);HoldFeet(Girl,bHerStands,HerOffset,HerFeet,HerHeld,bHerIk);}
}
void UOKHScenePanel::HideWallsInTheWay(){
    auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||!Girl->StudioCam||Props.IsEmpty())return;
    auto* Him=Gallery->PartnerActor.Get();const FVector Focus=Girl->OrbitFocus;
    const FVector Eye=Girl->StudioCam->GetActorLocation();
    // A wall (the only prop taller than a person) between the camera and them is hidden for this shot; seats and beds stay.
    // Lines to her head, her hips and his head, not only to the middle between them (a wall can hide her and miss that).
    TArray<FVector> Seen={Focus};FVector B;if(HBone(Girl,TEXT("j_head"),B))Seen.Add(B);if(HBone(Girl,TEXT("j_hips"),B))Seen.Add(B);
    if(Mode!=0&&IsValid(Him)&&!Him->IsHidden()&&HBone(Him,TEXT("j_head"),B))Seen.Add(B);
    for(AStaticMeshActor* A:Props)if(IsValid(A)){FVector O,E;A->GetActorBounds(false,O,E);bool Blocks=false;
        if(E.Z>90.f)for(const FVector& To:Seen)Blocks|=FMath::LineBoxIntersection(FBox(O-E,O+E),Eye,To,To-Eye);A->SetActorHiddenInGame(Blocks);}
}
void UOKHScenePanel::ClearProps(){for(AStaticMeshActor* A:Props)if(IsValid(A))A->Destroy();Props.Reset();}
void UOKHScenePanel::NativeDestruct(){if(IsValid(Fluid)){Fluid->StopSpray();Fluid->Destroy();Fluid=nullptr;}if(Siru[0]+Siru[1]+Siru[2]+Siru[3]+Siru[4]>0){FMemory::Memzero(Siru);ApplySiru();}if(bCovered)Cover(false,FPlatformTime::Seconds());ClearProps();RestoreBlush();
    if(auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;IsValid(Girl))EndDeepFace(Girl);
    if(bAhegaoShown){bAhegaoShown=false;TickAhegao();if(auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;IsValid(Girl)){Girl->SetEyeGaze(0.f,0.f,0.f);Girl->SetMouthPattern(0);}} // her eyes, mouth and hands back from ahegao
    TickCameraLight(true);
    SetGrayRoom(false);Drips.Reset();Tears.Reset();RestoreAlign();Super::NativeDestruct();}
// Off for now (user, 2026-11-02: the box, table and chair hid the bugs being looked at): ok.HScene.Props 1 sets them again.
static TAutoConsoleVariable<int32> CVarHProps(TEXT("ok.HScene.Props"),0,TEXT("1: a box, table or chair under her for the poses that lean on one; 0: none"));
void UOKHScenePanel::PlaceProps(int32 Kind){
    ClearProps();bPropsTable=false;auto* Girl=Gallery?Gallery->PreviewActor.Get():nullptr;if(!IsValid(Girl)||!Girl->BodySkel||!GetWorld()||!CVarHProps.GetValueOnGameThread())return;
    auto* Him=Mode!=0&&Gallery->PartnerActor&&!bMaleHidden?Gallery->PartnerActor.Get():nullptr;
    auto Bone=HBone;
    TArray<FVector> Hers;FVector HerHips,HisHips,P;
    if(!Bone(Girl,TEXT("j_hips"),HerHips))return;
    for(const TCHAR* N:{TEXT("j_hips"),TEXT("j_spine02"),TEXT("j_head"),TEXT("j_hand_L"),TEXT("j_hand_R"),TEXT("j_foot_L"),TEXT("j_foot_R")})if(Bone(Girl,N,P))Hers.Add(P);
    const bool HasHim=Bone(Him,TEXT("j_hips"),HisHips);
    const float Floor=Girl->GetActorLocation().Z;
    static UStaticMesh* Cube=LoadObject<UStaticMesh>(nullptr,TEXT("/Engine/BasicShapes/Cube.Cube"));if(!Cube)return;
    UMaterialInterface* Shape=LoadObject<UMaterialInterface>(nullptr,TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
    FLinearColor Tint=FLinearColor(.55f,.55f,.55f); // set before a Box for its colour
    auto Box=[&](const FVector& Center,const FVector& Size,const FRotator& Rot){
        auto* A=GetWorld()->SpawnActor<AStaticMeshActor>(Center,Rot);if(!A)return;
        A->SetMobility(EComponentMobility::Movable);A->GetStaticMeshComponent()->SetStaticMesh(Cube);A->GetStaticMeshComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        if(Shape)if(auto* M=UMaterialInstanceDynamic::Create(Shape,A)){M->SetVectorParameterValue(TEXT("Color"),Tint);A->GetStaticMeshComponent()->SetMaterial(0,M);}
        A->SetActorScale3D(Size/100.f);Props.Add(A);};
    FString What;
    if(Kind==1){
        // Under whoever sits: knees off the floor and thighs about level with the hips (kneeling has the knees on the floor).
        // Both sitting (she is on his lap): the lower hips. Neither clearly: the lower hips too.
        auto Sitting=[&](AKKPreviewActor* A,const FVector& Hips){FVector KL,KR;if(!A||!Bone(A,TEXT("j_leg01_L"),KL)||!Bone(A,TEXT("j_leg01_R"),KR))return false;
            const float Knee=float(KL.Z+KR.Z)/2;UE_LOG(LogTemp,Display,TEXT("H scene: seat check knee %.0f above the floor, hips %.0f above the knees"),Knee-Floor,float(Hips.Z)-Knee);
            return Knee>Floor+25.f&&FMath::Abs(float(Hips.Z)-Knee)<25.f;}; // seated: 2–14 cm; bent over standing: 31
        const bool SheSits=Sitting(Girl,HerHips),HisSit=HasHim&&Sitting(Him,HisHips);
        // Nobody sits (she bends over it from behind): the seat is under her hands, nothing through her body.
        FVector HL,HR;
        if(!SheSits&&!HisSit&&Bone(Girl,TEXT("j_hand_L"),HL)&&Bone(Girl,TEXT("j_hand_R"),HR)&&FMath::Min(HL.Z,HR.Z)>Floor+25.f){
            const FVector Hands=(HL+HR)/2;const float Top=float(FMath::Min(HL.Z,HR.Z))-4.f;
            Box(FVector(Hands.X,Hands.Y,(Floor+Top)/2),FVector(48,48,Top-Floor),(Hands-HerHips).GetSafeNormal2D().Rotation());What=TEXT("seat under her hands");
            UE_LOG(LogTemp,Display,TEXT("H scene: %s placed for the pose (%d)"),*What,Props.Num());return;}
        const bool HeSits=HasHim&&(HisSit!=SheSits?HisSit:HisHips.Z<HerHips.Z);const FVector Sit=HeSits?HisHips:HerHips;
        const float Top=FMath::Max(Floor+20.f,Sit.Z-12.f);Box(FVector(Sit.X,Sit.Y,(Floor+Top)/2),FVector(48,48,Top-Floor),FRotator::ZeroRotator);What=TEXT("seat");
        // Leaning back (a sofa, a chair back): a slanted back from the hips along the spine to the head, behind it.
        FVector Head;if(Bone(HeSits?Him:Girl,TEXT("j_head"),Head)){
            const FVector Spine=Head-Sit;FVector Away=HasHim?(HeSits?HerHips-HisHips:HisHips-HerHips):FVector::ZeroVector;Away.Z=0;
            if(Away.Normalize()&&float(Spine|-Away)>20.f){
                const FVector Along=Spine.GetSafeNormal();const FVector Behind=-Away-Along*float(-Away|Along);
                Box((Sit+Head)/2+Behind.GetSafeNormal()*14.f,FVector(Spine.Size()+30.f,52,8),Along.Rotation());What=TEXT("seat with a back");}}
    }else if(Kind==2){
        // Under her body where it rests (hips, back, head, hands above the knees): a table just below the lowest of them.
        TArray<FVector> Rest;for(const FVector& V:Hers)if(V.Z>Floor+40.f)Rest.Add(V);if(Rest.IsEmpty())return;
        float Top=TNumericLimits<float>::Max();for(const FVector& V:Rest)Top=FMath::Min(Top,float(V.Z));Top-=6.f;
        // Laid along her body (hips to head), not square to the world: a square box around a turned body reached into them.
        FVector Head,Along=FVector::ZeroVector;if(Bone(Girl,TEXT("j_head"),Head))Along=Head-HerHips;Along.Z=0;if(!Along.Normalize())Along=FVector::ForwardVector;
        const FVector Across(-Along.Y,Along.X,0.);
        float A0=1e9f,A1=-1e9f,C0=1e9f,C1=-1e9f;
        for(const FVector& V:Rest)if(V.Z<Top+30.f){const float A=float((V-HerHips)|Along),C=float((V-HerHips)|Across);A0=FMath::Min(A0,A);A1=FMath::Max(A1,A);C0=FMath::Min(C0,C);C1=FMath::Max(C1,C);}
        A0-=15.f;A1+=15.f;C0-=18.f;C1+=18.f;
        // Its near edge clear of what stands beside it (his hips, knees and feet; her knees and feet hanging down): she bends
        // over the edge, he stands at it, nobody is inside the table.
        TArray<FVector> Beside;for(const TCHAR* N:{TEXT("j_leg01_L"),TEXT("j_leg01_R"),TEXT("j_foot_L"),TEXT("j_foot_R")})if(Bone(Girl,N,P)&&P.Z<Top+10.f)Beside.Add(P);
        if(HasHim)for(const TCHAR* N:{TEXT("j_hips"),TEXT("j_leg01_L"),TEXT("j_leg01_R"),TEXT("j_foot_L"),TEXT("j_foot_R")})if(Bone(Him,N,P)&&P.Z<Top+25.f)Beside.Add(P);
        const float Middle=(A0+A1)/2;
        for(const FVector& V:Beside){const float A=float((V-HerHips)|Along),C=float((V-HerHips)|Across);if(C>C0-10.f&&C<C1+10.f&&A<Middle)A0=FMath::Max(A0,A+12.f);}
        A1=FMath::Max(A1,A0+45.f);if(C1-C0<55.f){const float M=(C0+C1)/2;C0=M-27.5f;C1=M+27.5f;}
        const FVector Mid=HerHips+Along*((A0+A1)/2)+Across*((C0+C1)/2);
        Box(FVector(Mid.X,Mid.Y,(Floor+Top)/2),FVector(A1-A0,C1-C0,Top-Floor),Along.Rotation());What=TEXT("table");bPropsTable=true;
    }else if(Kind==3){
        // Beyond her on the side away from him (he is behind her: her hands are on it; he faces her: her back is), or the
        // way her hands reach when she is alone.
        FVector Dir=FVector::ZeroVector;FVector L,R;
        if(HasHim)Dir=HerHips-HisHips;
        if(Dir.Size2D()<5.f&&Bone(Girl,TEXT("j_hand_L"),L)&&Bone(Girl,TEXT("j_hand_R"),R))Dir=(L+R)/2-HerHips;
        Dir.Z=0;if(!Dir.Normalize())return;
        // Past both of them (he can be the one against it): never through anyone.
        TArray<FVector> Both=Hers;if(HasHim)for(const TCHAR* N:{TEXT("j_hips"),TEXT("j_spine02"),TEXT("j_head"),TEXT("j_hand_L"),TEXT("j_hand_R"),TEXT("j_foot_L"),TEXT("j_foot_R"),TEXT("j_leg01_L"),TEXT("j_leg01_R")})if(Bone(Him,N,P))Both.Add(P);
        float Far=0;for(const FVector& V:Both)Far=FMath::Max(Far,float((V-HerHips)|Dir));
        const FVector At=HerHips+Dir*(Far+4.f);
        Box(FVector(At.X,At.Y,Floor+110.f),FVector(6,160,220),Dir.Rotation());What=TEXT("wall");
    }else if(Room==1&&HerHips.Z<Floor+60.f){
        // A bed: its mattress top level with the floor under both of them (nobody moves), along her body, with a frame
        // and a headboard past her head. Not under a standing pose.
        // Along the body that lies flattest (him on his back when she rides him), the headboard past that head.
        FVector Along(1,0,0),Lying=HerHips;float Flat=-1.f;
        for(AKKPreviewActor* A:{Girl,HasHim?Him:nullptr}){FVector Hd,Hp;if(!A||!Bone(A,TEXT("j_head"),Hd)||!Bone(A,TEXT("j_hips"),Hp))continue;
            FVector D=Hd-Hp;D.Z=0;if(D.Size()>Flat){Flat=D.Size();Lying=Hp;if(D.Normalize())Along=D;}}
        const FVector Across(-Along.Y,Along.X,0);
        TArray<FVector> All=Hers;if(HasHim){for(const TCHAR* N:{TEXT("j_hips"),TEXT("j_head"),TEXT("j_foot_L"),TEXT("j_foot_R"),TEXT("j_leg01_L"),TEXT("j_leg01_R")})if(Bone(Him,N,P))All.Add(P);}
        float A0=TNumericLimits<float>::Max(),A1=-A0,C0=A0,C1=-A0;
        for(const FVector& V:All){const FVector D=V-Lying;A0=FMath::Min(A0,float(D|Along));A1=FMath::Max(A1,float(D|Along));C0=FMath::Min(C0,float(D|Across));C1=FMath::Max(C1,float(D|Across));}
        A0-=30.f;A1+=25.f;C0-=30.f;C1+=30.f;
        if(A1-A0<200.f){const float Grow=(200.f-(A1-A0))/2;A0-=Grow;A1+=Grow;}
        if(C1-C0<150.f){const float Grow=(150.f-(C1-C0))/2;C0-=Grow;C1+=Grow;}
        const FVector Mid=Lying+Along*((A0+A1)/2)+Across*((C0+C1)/2);const FRotator Rot=Along.Rotation();
        Tint=FLinearColor(.92f,.9f,.86f);Box(FVector(Mid.X,Mid.Y,Floor-18.f),FVector(A1-A0,C1-C0,40.f),Rot); // mattress, top 2 cm above the floor
        Tint=FLinearColor(.32f,.2f,.12f);Box(FVector(Mid.X,Mid.Y,Floor-32.f),FVector(A1-A0+12.f,C1-C0+12.f,30.f),Rot); // frame
        const FVector HeadAt=Lying+Along*(A1+8.f)+Across*((C0+C1)/2);Box(FVector(HeadAt.X,HeadAt.Y,Floor+20.f),FVector(8.f,C1-C0+12.f,80.f),Rot);What=TEXT("bed"); // a low headboard (below the camera)
    }
    UE_LOG(LogTemp,Display,TEXT("H scene: %s placed for the pose (%d)"),*What,Props.Num());
    HideWallsInTheWay(); // the camera may already be framed for this pose
}
// What she has been through with him so far, this time too (hexp orgasms, climaxes, sex_count; user 2026-11-03): she
// can say how many times they have done it and where she came.
FString UOKHScenePanel::History() const{
    const auto& X=Gallery?Gallery->HExperience:nullptr;
    auto Int=[&](const TCHAR* K){double V=0;if(X.IsValid())X->TryGetNumberField(K,V);return int32(V);};
    static const TCHAR* Keys[]={TEXT("kiss"),TEXT("chest"),TEXT("crotch"),TEXT("anal"),TEXT("butt"),TEXT("nipple"),TEXT("head"),TEXT("hand"),TEXT("thigh"),TEXT("calf"),TEXT("foot")};
    const TSharedPtr<FJsonObject>* Before=nullptr;if(X.IsValid())X->TryGetObjectField(TEXT("climaxes"),Before);
    TArray<FString> Where;
    for(int32 I=0;I<11;++I){double V=0;if(Before)(*Before)->TryGetNumberField(Keys[I],V);
        const int32 N=int32(V)+AreaClimaxes[I]+(I==2?CrotchClimaxes:I==3?AnalClimaxes:0);
        if(N>0)Where.Add(OKMsg(TEXT("ui.hscene.history_place"),{{TEXT("place"),OKT(*(FString(TEXT("ui.hscene.part_"))+(I==0?TEXT("lips"):Keys[I])))},{TEXT("n"),N}}));}
    return OKMsg(TEXT("ui.hscene.talk_history"),{{TEXT("sex"),Int(TEXT("sex_count"))+int32(bCrotch||bAnal)},{TEXT("orgasms"),Int(TEXT("orgasms"))+HerOrgasms},
        {TEXT("where"),Where.IsEmpty()?FString():OKMsg(TEXT("ui.hscene.history_where"),{{TEXT("list"),FString::Join(Where,OKT(TEXT("ui.memory.list_separator")))}})}});
}
FString UOKHScenePanel::StateWords(const FString& Base) const{
    if(Mode==0)return OKT(Base==TEXT("K_Loop")||Base==TEXT("K_Touch")?TEXT("ui.hscene.state_kiss"):Base.StartsWith(TEXT("Orgasm"))?TEXT("ui.hscene.state_after"):TouchArea!=INDEX_NONE?TEXT("ui.hscene.state_caress"):TEXT("ui.hscene.state_idle"));
    if(Base==TEXT("Idle")||Base==TEXT("Stop_Idle"))return OKT(TEXT("ui.hscene.state_idle"));
    if(Base==TEXT("Insert")||Base==TEXT("InsertIdle"))return OKT(TEXT("ui.hscene.state_inserted"));
    // His finish or her climax plays out of the loop it started in for a few seconds (OLoop, M_OUT_Start, M_OUT_Loop,
    // then OUT_A): "almost there" then had her beg him not to stop after he had come outside her.
    const bool bAfter=Base.EndsWith(TEXT("_A"))||Base==TEXT("Drop")||Base==TEXT("Pull")||Base.StartsWith(TEXT("Oral"));
    if(!bAfter&&JustCameAt>0.&&FPlatformTime::Seconds()-JustCameAt<10.)
        return OKT(JustCame==1?TEXT("ui.hscene.state_her_came"):JustCame==2?TEXT("ui.hscene.state_both_came"):TEXT("ui.hscene.state_his_came"));
    if(Base==TEXT("WLoop"))return OKT(TEXT("ui.hscene.state_slow"));
    if(Base==TEXT("SLoop"))return OKT(TEXT("ui.hscene.state_fast"));
    if(Base==TEXT("OLoop"))return OKT(TEXT("ui.hscene.state_near"));
    if(Base.StartsWith(TEXT("Oral")))return OKT(TEXT("ui.hscene.state_oral"));
    if(Base.EndsWith(TEXT("_A"))||Base==TEXT("Drop")||Base==TEXT("Pull"))return OKT(TEXT("ui.hscene.state_after"));
    return OKT(TEXT("ui.hscene.state_finishing"));
}
// What she is in the middle of, for her answer (the turn message, not the cached prefix).
FString UOKHScenePanel::Context() const{
    const FString Cur=Current(),Base=Mode==0?Cur:HBase(Cur);
    const FString PoseName=Mode==0&&AibuPoses.IsValidIndex(ActiveAibu)?AibuPoses[ActiveAibu].Name:Poses.IsValidIndex(ActivePose)?Poses[ActivePose].Name:FString();
    // What he has already taken off her: she agreed to this room, so undressing is part of it, not news to protest.
    static const TCHAR* Parts[]={TEXT("ui.hscene.cloth_top"),TEXT("ui.hscene.cloth_bottom"),TEXT("ui.hscene.cloth_bra"),TEXT("ui.hscene.cloth_shorts"),TEXT("ui.hscene.cloth_gloves"),TEXT("ui.hscene.cloth_pantyhose"),TEXT("ui.hscene.cloth_socks"),TEXT("ui.hscene.cloth_inner_shoes"),TEXT("ui.hscene.cloth_shoes")};
    TArray<FString> Bare;if(Gallery&&Gallery->PreviewActor)for(int32 K=0;K<9;++K)if(Gallery->ClothesStates[K]==3&&Gallery->PreviewActor->DisplayClothesStates[K]!=3)Bare.Add(OKT(Parts[K]));
    // How many more she can take today (HadEnough's numbers): her words about having had enough follow the same limit.
    const auto& X=Gallery?Gallery->HExperience:nullptr;
    const int32 Left=FMath::Max(0,FMath::Max(1,X.IsValid()&&X->HasField(TEXT("climax_limit"))?int32(X->GetNumberField(TEXT("climax_limit"))):4)-(X.IsValid()&&X->HasField(TEXT("today_orgasms"))?int32(X->GetNumberField(TEXT("today_orgasms"))):0)-HerOrgasms);
    // How many more times her desire for him wants (ok-rules hexp climax_wanted): a keen girl says she wants more.
    int32 Want=FMath::Max(0,(X.IsValid()&&X->HasField(TEXT("climax_wanted"))?int32(X->GetNumberField(TEXT("climax_wanted"))):0)-(X.IsValid()&&X->HasField(TEXT("today_orgasms"))?int32(X->GetNumberField(TEXT("today_orgasms"))):0)-HerOrgasms);
    // Hooked (ok-rules hexp addicted): each climax makes her want more, never enough, past her limit too.
    const bool bHooked=Hooked();if(bHooked)Want=FMath::Max(Want,1+HerOrgasms);
    return OKMsg(TEXT("ui.hscene.talk_context"),{{TEXT("body"),OKMsg(bHooked?TEXT("ui.hscene.talk_body_hooked"):TEXT("ui.hscene.talk_body"),{{TEXT("left"),Left}})},{TEXT("want"),bHooked?Want:FMath::Min(Want,Left)},{TEXT("bare"),Bare.IsEmpty()?OKT(TEXT("ui.hscene.bare_none")):FString::Join(Bare,TEXT("、"))},{TEXT("pose"),PoseName},{TEXT("state"),StateWords(Base)},{TEXT("speed"),FString::Printf(TEXT("%.1f"),Mode==0||HIsLoop(Base)?PlaybackSpeed():0.f)},
        {TEXT("her"),FMath::RoundToInt(Her)},{TEXT("his"),FMath::RoundToInt(His)},{TEXT("orgasms"),HerOrgasms},{TEXT("finishes"),HisFinishes},{TEXT("condom"),Mode==2&&(bCrotch||bAnal)?(bCondom?TEXT("yes"):TEXT("no")):TEXT("none")}})
        // What runs out of her now (TickDrips): she feels it, so he may say so and she knows.
        +History()
        +OKMsg(TEXT("ui.mind.body_wet_status"),{{TEXT("crotch"),HerDesire()>OKArousal::DesireMilk?TEXT("flooding"):HerDesire()>OKArousal::DesireFlush?TEXT("dripping"):TEXT("none")},{TEXT("discharge"),TEXT("none")},
            {TEXT("milk"),HerDesire()>OKArousal::DesireFlush?TEXT("leaking"):TEXT("none")},{TEXT("any"),HerDesire()>OKArousal::DesireFlush?TEXT("yes"):TEXT("no")}});
}
void UOKHScenePanel::OnInputCommitted(const FText& Text,ETextCommit::Type Commit){
    if(Commit!=ETextCommit::OnEnter)return;Say(Text.ToString());if(Input)Input->SetText(FText::GetEmpty());
}
TSharedRef<FJsonObject> UOKHScenePanel::Describe() const{
    auto O=MakeShared<FJsonObject>();
    O->SetStringField(TEXT("pose"),Mode==0&&AibuPoses.IsValidIndex(ActiveAibu)?AibuPoses[ActiveAibu].Name:Poses.IsValidIndex(ActivePose)?Poses[ActivePose].Name:FString());O->SetStringField(TEXT("pending"),Poses.IsValidIndex(PendingPose)?Poses[PendingPose].Name:FString());
    if(AlignOff>=0.f){auto A=MakeShared<FJsonObject>();A->SetNumberField(TEXT("tip"),AlignTip);A->SetNumberField(TEXT("open"),OpenEased);{float Most=0.f;for(const auto& B:Bulge)Most=FMath::Max(Most,B.Value);A->SetNumberField(TEXT("bulge"),Most);A->SetStringField(TEXT("bulge_at"),BulgeTarget.IsNone()?FString():BulgeTarget.ToString());A->SetNumberField(TEXT("bulge_past"),BulgePast);A->SetNumberField(TEXT("bulge_moves"),BulgeMoves);}A->SetNumberField(TEXT("off"),AlignOff);A->SetNumberField(TEXT("at"),AlignAt);A->SetNumberField(TEXT("len"),AlignLen);A->SetNumberField(TEXT("moved"),HimOffset.Size());A->SetNumberField(TEXT("at_min"),AtShownMin);A->SetNumberField(TEXT("foot"),AlignFoot);A->SetNumberField(TEXT("mz"),HimOffset.Z);A->SetNumberField(TEXT("her_z"),HerOffset.Z);A->SetBoolField(TEXT("his_knees"),bHisIk);A->SetBoolField(TEXT("her_knees"),bHerIk);{TArray<TSharedPtr<FJsonValue>> F;for(float V:FeetShown)F.Add(MakeShared<FJsonValueNumber>(V));A->SetArrayField(TEXT("feet"),F);}A->SetNumberField(TEXT("pushed"),AlignPushed);A->SetNumberField(TEXT("deep"),AlignDeep);A->SetNumberField(TEXT("at_max"),AtShownMax);O->SetObjectField(TEXT("align"),A);}
    O->SetBoolField(TEXT("covered"),bCovered);{TArray<TSharedPtr<FJsonValue>> S;for(int32 V:Siru)S.Add(MakeShared<FJsonValueNumber>(V));O->SetArrayField(TEXT("siru"),S);}
    {TArray<TSharedPtr<FJsonValue>> L;for(const FString& R:LiquidReport())L.Add(MakeShared<FJsonValueString>(R));O->SetArrayField(TEXT("liquid"),L);}
    // Where their heads and feet are on the screen (0..1; -1 behind the camera): both whole in the shot or not.
    {TArray<TSharedPtr<FJsonValue>> Shot;APlayerController* PC=GetOwningPlayer();FVector2D View(1.,1.);if(GEngine&&GEngine->GameViewport)GEngine->GameViewport->GetViewportSize(View);
     for(AKKPreviewActor* A:{Gallery?Gallery->PreviewActor.Get():nullptr,bMaleHidden||!Gallery?nullptr:Gallery->PartnerActor.Get()})if(IsValid(A)&&PC&&View.X>1.)
      for(const TCHAR* N:{TEXT("j_head"),TEXT("j_foot_L"),TEXT("j_foot_R")}){FVector P;FVector2D S(-View.X,-View.Y);
       if(HBone(A,N,P))PC->ProjectWorldLocationToScreen(P+(N[2]==TEXT('h')?FVector(0,0,12):FVector::ZeroVector),S);
       Shot.Add(MakeShared<FJsonValueNumber>(FMath::RoundToFloat(S.X/View.X*100)/100));Shot.Add(MakeShared<FJsonValueNumber>(FMath::RoundToFloat(S.Y/View.Y*100)/100));}
     O->SetArrayField(TEXT("shot"),Shot);}
    O->SetNumberField(TEXT("blush"),BlushMats.IsEmpty()?-1.f:BlushShown);
    O->SetStringField(TEXT("state"),Current());O->SetStringField(TEXT("wanted"),Wanted);O->SetNumberField(TEXT("mode"),Mode);
    TArray<TSharedPtr<FJsonValue>> Q;for(const FString& S:Queue)Q.Add(MakeShared<FJsonValueString>(S));O->SetArrayField(TEXT("queue"),Q);
    O->SetNumberField(TEXT("playback_speed"),PlaybackSpeed());if(Gallery&&Gallery->PreviewActor)O->SetNumberField(TEXT("breath_rate"),Gallery->PreviewActor->SpeechTempo);O->SetBoolField(TEXT("hooked"),Hooked());O->SetNumberField(TEXT("oral_suck"),OralSuckSet);O->SetNumberField(TEXT("oral_pull"),OralPullSet);O->SetNumberField(TEXT("mouth_turned"),bMouthAimed?MouthTurned:0.f);O->SetStringField(TEXT("mouth_dbg"),MouthDbg.ToString());O->SetNumberField(TEXT("mouth_hidden_verts"),MouthClipVerts);O->SetNumberField(TEXT("bust_swell"),BustSwellSet);O->SetNumberField(TEXT("preg_belly"),PregBellyShown);O->SetNumberField(TEXT("preg_nipples"),PregNipples());O->SetNumberField(TEXT("depth_top"),AlignDeep);O->SetNumberField(TEXT("belly_out"),BulgeTarget.IsNone()?-1.f:BulgePast);O->SetNumberField(TEXT("belly_allow"),FMath::Max(0.f,BulgeMoves-2.5f));O->SetNumberField(TEXT("pullback"),BellyPullback);O->SetNumberField(TEXT("tip_inside"),TipInside);O->SetNumberField(TEXT("aim_relax"),AimRelax);O->SetNumberField(TEXT("skin_out"),SkinOutMost);O->SetNumberField(TEXT("skin_under"),SkinUnderMost);O->SetNumberField(TEXT("skin_worst"),SkinWorst);O->SetNumberField(TEXT("skin_rest"),SkinRest);O->SetNumberField(TEXT("skin_along"),SkinWorstAlong);O->SetNumberField(TEXT("root_dodge"),RootDodge.Size());O->SetNumberField(TEXT("depth_cap"),DepthCap);{auto Wr=MakeShared<FJsonObject>();for(const auto& W:Bulge)if(W.Value>1.f)Wr->SetNumberField(W.Key.ToString(),FMath::RoundToFloat(W.Value));O->SetObjectField(TEXT("swells"),Wr);O->SetNumberField(TEXT("swells_refused"),BulgeRefused);O->SetNumberField(TEXT("wrap_ms"),WrapMs);O->SetNumberField(TEXT("wrap_verts"),WrapVerts);O->SetNumberField(TEXT("cloth_verts"),ClothVerts);O->SetNumberField(TEXT("cloth_ms"),ClothMs);O->SetNumberField(TEXT("clip_verts"),ClipVerts);O->SetNumberField(TEXT("back_exit"),BackExitCm);O->SetNumberField(TEXT("clip_lead"),ClipLeadCm);O->SetNumberField(TEXT("swell_ms"),SwellMs);O->SetNumberField(TEXT("swell_part"),BulgePart);}O->SetNumberField(TEXT("skin_facing"),SkinFacing);O->SetBoolField(TEXT("belly_side"),bBellySide);if(Gallery&&Gallery->PreviewActor){const FTransform& HerT=Gallery->PreviewActor->GetActorTransform();auto Vec=[&](const TCHAR* Name,const FVector& V){FVector U=AKKPreviewActor::ActorLocalToUnity(HerT.InverseTransformVectorNoScale(V))*100.;float K[16];if(Gallery->PreviewActor->Session.BoneWorldMatrix(TEXT("cf_j_kokan"),K)||Gallery->PreviewActor->Session.BoneWorldMatrix(TEXT("cf_J_Kokan"),K)){const FVector X(K[0],K[4],K[8]),Y(K[1],K[5],K[9]),Z(K[2],K[6],K[10]);U=FVector(U|X.GetSafeNormal(),U|Y.GetSafeNormal(),U|Z.GetSafeNormal());}TArray<TSharedPtr<FJsonValue>> A;A.Add(MakeShared<FJsonValueNumber>(U.X));A.Add(MakeShared<FJsonValueNumber>(U.Y));A.Add(MakeShared<FJsonValueNumber>(U.Z));O->SetArrayField(Name,A);};Vec(TEXT("dodge_her"),RootDodge);Vec(TEXT("skin_normal_her"),SkinNormal);Vec(TEXT("front_her"),BellyFront);}O->SetNumberField(TEXT("root_scale"),RootPadScale);O->SetBoolField(TEXT("xray"),bPenisXRay);if(Gallery&&Gallery->PairedPlayback)O->SetNumberField(TEXT("pair_rate"),Gallery->PairedPlayback->GetSpeed());O->SetNumberField(TEXT("held"),Held.Num());O->SetStringField(TEXT("caption"),Caption?Caption->GetText().ToString():FString());
    {const TSharedPtr<FJsonObject>* Areas=nullptr;if(Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetObjectField(TEXT("areas"),Areas))O->SetObjectField(TEXT("areas"),*Areas);}
    O->SetNumberField(TEXT("her"),Her);O->SetNumberField(TEXT("his"),His);O->SetNumberField(TEXT("orgasms"),HerOrgasms);O->SetNumberField(TEXT("pupil_shake_x"),PupilShakeNow.X);O->SetNumberField(TEXT("pupil_shake_y"),PupilShakeNow.Y);O->SetBoolField(TEXT("ahegao"),bAhegaoShown);O->SetNumberField(TEXT("deep_face"),DeepFace);
    {auto P=MakeShared<FJsonObject>();P->SetNumberField(TEXT("ankle"),AnkleTurn);P->SetNumberField(TEXT("thigh_l"),ThighOpen[0]);P->SetNumberField(TEXT("thigh_r"),ThighOpen[1]);P->SetNumberField(TEXT("hand_l"),HandPattern[0]);P->SetNumberField(TEXT("hand_r"),HandPattern[1]);P->SetNumberField(TEXT("hand_patterns"),HandOptions);O->SetObjectField(TEXT("her_pose"),P);}
    // Her development as the scene uses it now (her own plus this scene's climaxes), and how long her climax and her
    // nipples' spray have left (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md).
    {auto D=MakeShared<FJsonObject>();for(const TCHAR* A:{TEXT("crotch"),TEXT("anal"),TEXT("oral"),TEXT("chest"),TEXT("nipple")})D->SetNumberField(A,FMath::RoundToFloat(Dev(A)*100.f));O->SetObjectField(TEXT("dev"),D);
     const double Now=FPlatformTime::Seconds();O->SetNumberField(TEXT("climax_left"),FMath::Max(0.,ClimaxUntil-Now));O->SetNumberField(TEXT("nipple_left"),FMath::Max(0.,NippleUntil-Now));}O->SetNumberField(TEXT("speed"),SpeedValue);O->SetBoolField(TEXT("condom"),bCondom);O->SetBoolField(TEXT("anal_play"),bAnalPlay);
    O->SetStringField(TEXT("title"),Title?Title->GetText().ToString():FString());O->SetStringField(TEXT("hint"),Hint?Hint->GetText().ToString():FString());O->SetStringField(TEXT("face"),FaceKey); /* eye/brow/openness now (UpdateFace) */
    if(Gallery&&Gallery->PreviewActor){O->SetBoolField(TEXT("breath"),Gallery->PreviewActor->bHBreath);O->SetBoolField(TEXT("speaking"),Gallery->PreviewActor->IsSpeaking());O->SetNumberField(TEXT("mouth"),Gallery->PreviewActor->EffectiveFaceRate(0));}
    if(Gallery&&Gallery->HExperience.IsValid())O->SetObjectField(TEXT("experience"),Gallery->HExperience); // what she allows (hexp.rs h_experience)
    auto Buttons=[](UPanelWidget* Panel){TArray<TSharedPtr<FJsonValue>> Out;if(Panel)for(int32 I=0;I<Panel->GetChildrenCount();++I)if(auto* B=Cast<UOKHSceneButton>(Panel->GetChildAt(I))){auto R=MakeShared<FJsonObject>();R->SetNumberField(TEXT("kind"),B->Kind);R->SetBoolField(TEXT("enabled"),B->GetIsEnabled());
        if(auto* L=Cast<UTextBlock>(B->GetContent()))R->SetStringField(TEXT("label"),L->GetText().ToString());Out.Add(MakeShared<FJsonValueObject>(R));}return Out;};
    O->SetArrayField(TEXT("actions"),Buttons(Actions));O->SetArrayField(TEXT("list"),Buttons(List));O->SetNumberField(TEXT("tab"),Tab);
    O->SetObjectField(TEXT("result"),Result());
    return O;
}
bool UOKHScenePanel::SelectPoseNamed(const FString& Name){
    const int32 I=Poses.IndexOfByPredicate([&](const FOKHPose& P){return P.Name==Name||P.Raw==Name;});if(I==INDEX_NONE)return false;
    Tab=Poses[I].Mode==2?TabSonyu:TabHand+Poses[I].KindHoushi;SelectPose(I);return true;
}
void UOKHScenePanel::SetSpeed(float Value){SpeedValue=FMath::Clamp(Value,0.f,1.f);if(Speed)Speed->SetValue(SpeedValue);}
TSharedRef<FJsonObject> UOKHScenePanel::Result() const{
    auto Counts=MakeShared<FJsonObject>();
    Counts->SetBoolField(TEXT("anal_refused"),bAnalAsked&&bAnalRefused);Counts->SetBoolField(TEXT("played"),bPlayed);Counts->SetBoolField(TEXT("service"),bService);Counts->SetNumberField(TEXT("service_finishes"),ServiceFinishes);
    auto Part=[](bool Inserted,int32 Climaxes,float Deepest){auto O=MakeShared<FJsonObject>();O->SetBoolField(TEXT("inserted"),Inserted);O->SetNumberField(TEXT("climaxes"),Climaxes);O->SetNumberField(TEXT("deepest"),FMath::RoundToFloat(Deepest));return O;};
    Counts->SetObjectField(TEXT("crotch"),Part(bCrotch,CrotchClimaxes,CrotchDeepest));Counts->SetObjectField(TEXT("anal"),Part(bAnal,AnalClimaxes,AnalDeepest));
    {static const TCHAR* Keys[]={TEXT("kiss"),TEXT("chest"),TEXT("crotch"),TEXT("anal"),TEXT("butt"),TEXT("nipple"),TEXT("head"),TEXT("hand"),TEXT("thigh"),TEXT("calf"),TEXT("foot")};auto Areas=MakeShared<FJsonObject>();
     for(int32 I=0;I<11;++I)Areas->SetNumberField(Keys[I],FMath::RoundToDouble(AreaSeconds[I]));Counts->SetObjectField(TEXT("areas"),Areas);
     auto Came=MakeShared<FJsonObject>();for(int32 I=0;I<11;++I)if(AreaClimaxes[I]>0)Came->SetNumberField(Keys[I],AreaClimaxes[I]);Counts->SetObjectField(TEXT("climax_areas"),Came);Counts->SetNumberField(TEXT("kiss"),FMath::RoundToDouble(AreaSeconds[0]));}
    if(DevSet.Num()){auto Set=MakeShared<FJsonObject>();for(const auto& Area:DevSet)Set->SetNumberField(Area.Key,Area.Value);Counts->SetObjectField(TEXT("dev_set"),Set);}
    Counts->SetBoolField(TEXT("raw"),bRaw);Counts->SetBoolField(TEXT("raw_pressed"),bRawPressed&&bRaw);
    Counts->SetNumberField(TEXT("his_inside"),HisInside);Counts->SetNumberField(TEXT("his_inside_raw"),HisInsideRaw);Counts->SetNumberField(TEXT("his_inside_vagina_raw"),HisInsideVaginaRaw);Counts->SetBoolField(TEXT("street_onani"),StreetOnani());Counts->SetNumberField(TEXT("his_condom"),HisCondom);Counts->SetNumberField(TEXT("condoms_his"),CondomsHis-int32(bCondomFresh&&!bCondomHers));Counts->SetNumberField(TEXT("condoms_her"),CondomsHer-int32(bCondomFresh&&bCondomHers)); // one on but never in her goes back
    Counts->SetNumberField(TEXT("her_drips"),HerDrips);Counts->SetNumberField(TEXT("her_milk"),HerMilk);Counts->SetNumberField(TEXT("her_drip_times"),HerDripTimes);Counts->SetNumberField(TEXT("her_milk_times"),HerMilkTimes);Counts->SetNumberField(TEXT("his_outside"),HisOutside);Counts->SetNumberField(TEXT("his_mouth"),HisMouth);Counts->SetNumberField(TEXT("swallowed"),Swallowed);Counts->SetNumberField(TEXT("her_orgasms"),HerOrgasms);Counts->SetNumberField(TEXT("his_finishes"),HisFinishes);
    auto Out=MakeShared<FJsonObject>();Out->SetObjectField(TEXT("counts"),Counts);
    TArray<TSharedPtr<FJsonValue>> P,E;for(const FString& S:PosesPlayed)P.Add(MakeShared<FJsonValueString>(S));for(const FString& S:Events)E.Add(MakeShared<FJsonValueString>(S));
    Counts->SetArrayField(TEXT("poses"),P); // kept with her: the ones never played are marked New (hexp.rs poses_played)
    // Where his semen is on her (face, front top, front bottom, back top, back bottom; AddSiru): she goes out with it.
    {TArray<TSharedPtr<FJsonValue>> On;for(int32 A=0;A<5;++A)On.Add(MakeShared<FJsonValueNumber>(Siru[A]));Counts->SetArrayField(TEXT("siru"),On);}
    Out->SetArrayField(TEXT("poses"),P);Out->SetArrayField(TEXT("events"),E);
    return Out;
}

int32 UOKBuildHXRayMaterialCommandlet::Main(const FString& Params){
#if WITH_EDITOR
    // A copy of the translucent preview parent (its skeletal / vertex-factory usage comes with it), depth test off.
    UMaterial* Source=LoadObject<UMaterial>(nullptr,TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewTranslucent.M_PreviewTranslucent"));
    if(!Source){UE_LOG(LogTemp,Error,TEXT("OKBuildHXRayMaterial: no M_PreviewTranslucent"));return 1;}
    const FString Path=TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewXRay");
    UPackage* Package=CreatePackage(*Path);Package->FullyLoad();
    UMaterial* XRay=Cast<UMaterial>(StaticDuplicateObject(Source,Package,TEXT("M_PreviewXRay")));
    if(!XRay)return 1;
    XRay->SetFlags(RF_Public|RF_Standalone);XRay->bDisableDepthTest=true;XRay->TwoSided=true;
    XRay->PostEditChange();XRay->MarkPackageDirty();
    FSavePackageArgs Save;Save.TopLevelFlags=RF_Public|RF_Standalone;
    const bool Ok=UPackage::SavePackage(Package,XRay,*FPackageName::LongPackageNameToFilename(Path,FPackageName::GetAssetPackageExtension()),Save);
    UE_LOG(LogTemp,Display,TEXT("OKBuildHXRayMaterial: %s"),Ok?TEXT("saved M_PreviewXRay"):TEXT("save failed"));
    return Ok?0:1;
#else
    return 1;
#endif
}

// ---------------------------------------------------------------------------------------------- her outfit
AOKInteractionMode* UOKHScenePanel::Interaction() const{
    if(!Gallery||!GetWorld())return nullptr;
    for(TActorIterator<AOKInteractionMode> It(GetWorld());It;++It)if(It->Controller==Gallery&&!It->IsFinished())return *It;
    return nullptr;
}
void UOKHScenePanel::FindCoordinateCards(){
    CoordinateCards.Reset();const UKKGameRoot* Root=UKKGameRoot::Get();if(!Root||Root->Root.IsEmpty())return;
    IFileManager::Get().FindFilesRecursive(CoordinateCards,*(Root->Root/TEXT("UserData/coordinate")),TEXT("*.png"),true,false);
    CoordinateCards.Sort();if(CoordinateCards.Num()>500)CoordinateCards.SetNum(500);
}
// Down both sides, every other card on each: the tiles at once, their pictures one a tick (TickCoordinates).
void UOKHScenePanel::ShowCoordinates(){
    const ESlateVisibility Shown=bCoordinateList?ESlateVisibility::Visible:ESlateVisibility::Collapsed;
    for(int32 Side=0;Side<2;++Side){if(CoordSides[Side])CoordSides[Side]->SetVisibility(Shown);if(CoordWraps[Side])CoordWraps[Side]->ClearChildren();}
    if(PanelWidth)PanelWidth->SetVisibility(bCoordinateList?ESlateVisibility::Collapsed:ESlateVisibility::Visible);ShowAccessories(); // room for them (user 2026-11-04)
    CoordButtons.Reset();CoordImages.Reset();CoordTextures.Reset();CoordNext=0;
    if(!bCoordinateList||!WidgetTree||!CoordWraps[0]||!CoordWraps[1])return;
    for(int32 I=0;I<CoordinateCards.Num();++I){
        auto* B=WidgetTree->ConstructWidget<UOKHSceneButton>();B->Kind=CoordinateBase+I;B->Owner=this;B->OnClicked.AddDynamic(B,&UOKHSceneButton::HandleClick);
        UVerticalBox* Tile=WidgetTree->ConstructWidget<UVerticalBox>();
        USizeBox* Size=WidgetTree->ConstructWidget<USizeBox>();Size->SetWidthOverride(104.f);Size->SetHeightOverride(146.f);
        UImage* Picture=WidgetTree->ConstructWidget<UImage>();Picture->SetColorAndOpacity(FLinearColor(.2f,.2f,.2f));Size->AddChild(Picture);Tile->AddChildToVerticalBox(Size);
        USizeBox* Words=WidgetTree->ConstructWidget<USizeBox>();Words->SetWidthOverride(104.f);Words->SetHeightOverride(24.f);Words->SetClipping(EWidgetClipping::ClipToBounds);
        auto* Name=WidgetTree->ConstructWidget<UTextBlock>();FSlateFontInfo Font=Name->GetFont();Font.Size=7;Name->SetFont(Font);Name->SetColorAndOpacity(FSlateColor(FLinearColor::Black));Name->SetAutoWrapText(true);Name->SetText(FText::FromString(FPaths::GetBaseFilename(CoordinateCards[I])));
        Words->AddChild(Name);Tile->AddChildToVerticalBox(Words);B->SetContent(Tile);
        CoordWraps[I%2]->AddChildToWrapBox(B);CoordButtons.Add(B);CoordImages.Add(Picture);}
    MarkCoordinate();
}
void UOKHScenePanel::ShowAccessories(){if(CoordAccessories)CoordAccessories->SetText(FText::FromString(OKT(bCoordinateAccessories?TEXT("ui.hscene.coordinate_with_accessories"):TEXT("ui.hscene.coordinate_clothes_only"))));}
void UOKHScenePanel::MarkCoordinate(){
    const AOKInteractionMode* M=Interaction();const FString Worn=M?M->WornCoordinate:FString();
    for(int32 I=0;I<CoordButtons.Num();++I)CoordButtons[I]->SetBackgroundColor(!Worn.IsEmpty()&&FPaths::IsSamePath(CoordinateCards[I],Worn)?FLinearColor(1.f,.45f,.7f):FLinearColor::White);
}
void UOKHScenePanel::TickCoordinates(){
    if(CoordNext>=CoordImages.Num())return;const int32 I=CoordNext++;
    TArray<uint8> Card;if(!FFileHelper::LoadFileToArray(Card,*CoordinateCards[I]))return;
    if(UTexture2D* Texture=FImageUtils::ImportBufferAsTexture2D(UKKCardWorkspace::PngPreviewBytes(Card))){CoordTextures.Add(Texture);CoordImages[I]->SetColorAndOpacity(FLinearColor::White);CoordImages[I]->SetBrushFromTexture(Texture);}
}
// Her development as the left panel sets it: seen in this scene at once, kept with her when it ends (hexp.rs dev_set).
float UOKHScenePanel::DevOf(const TCHAR* Area) const{
    const TSharedPtr<FJsonObject>* Areas=nullptr;double V=0;
    if(Gallery&&Gallery->HExperience.IsValid()&&Gallery->HExperience->TryGetObjectField(TEXT("areas"),Areas))(*Areas)->TryGetNumberField(Area,V);
    return float(V);
}
void UOKHScenePanel::SetDev(const TCHAR* Area,float Value){
    const TSharedPtr<FJsonObject>* Areas=nullptr;if(!Gallery||!Gallery->HExperience.IsValid()||!Gallery->HExperience->TryGetObjectField(TEXT("areas"),Areas))return;
    (*Areas)->SetNumberField(Area,Value);DevSet.Add(Area,Value);
}
bool UOKHScenePanel::WearOutfit(int32 Outfit,const FString& Coordinate,FString& Why){
    AOKInteractionMode* M=Interaction();if(!M||!M->IsReady()){Why=OKT(TEXT("ui.hscene.outfit_not_ready"));return false;}
    if(M->IsChangingOutfit()){Why=OKT(TEXT("ui.hscene.outfit_busy"));return false;}
    FString Card=Coordinate;
    if(!Card.IsEmpty()&&!FPaths::FileExists(Card)){
        // A file name (with or without .png) among the game's coordinate cards.
        if(CoordinateCards.IsEmpty())FindCoordinateCards();
        const FString Want=FPaths::GetBaseFilename(Card);const FString* Found=CoordinateCards.FindByPredicate([&](const FString& P){return FPaths::GetBaseFilename(P).Equals(Want,ESearchCase::IgnoreCase);});
        if(!Found){Why=OKMsg(TEXT("ui.hscene.coordinate_missing"),{{TEXT("name"),Coordinate}});return false;}
        Card=*Found;
    }
    if(Card.IsEmpty()&&Outfit==Gallery->OutfitIndex&&M->WornCoordinate.IsEmpty()){Why=OKT(TEXT("ui.hscene.outfit_same"));return false;}
    if(!M->ChangeOutfit(Outfit,Card,bCoordinateAccessories)){Why=OKT(TEXT("ui.hscene.outfit_none"));return false;}
    if(Hint)Hint->SetText(FText::FromString(OKT(TEXT("ui.hscene.outfit_loading"))));
    BuildList();return true;
}
void UOKHScenePanel::OutfitChanged(bool bOk){
    AOKInteractionMode* M=Interaction();
    if(!bOk){if(Hint)Hint->SetText(FText::FromString(OKMsg(TEXT("ui.hscene.outfit_failed"),{{TEXT("error"),M?M->OutfitError:FString()}})));BuildList();return;}
    const FString Worn=M?M->WornCoordinate:FString();MarkCoordinate();
    if(!M||!M->bSwapClothesOnly)Note(Worn.IsEmpty()?OKMsg(TEXT("ui.hscene.event_outfit"),{{TEXT("name"),FString(OKT(*FString::Printf(TEXT("ui.hscene.outfit_%d"),FMath::Clamp(Gallery->OutfitIndex,0,7))))}})
        :OKMsg(TEXT("ui.hscene.event_coordinate"),{{TEXT("name"),FPaths::GetBaseFilename(Worn)}}));
    // Her new self starts the pose again where it was chosen: a caress state on her own, or the pair from its start.
    AKKPreviewActor* Girl=Gallery->PreviewActor.Get();
    if(Mode==0&&AibuPoses.IsValidIndex(ActiveAibu)&&IsValid(Girl)){
        if(Gallery->PartnerActor)Gallery->PartnerActor->SetActorHiddenInGame(true);
        Girl->SetGameSceneMode(3,false);PlaySolo(SoloState.IsEmpty()?FString(TEXT("Idle")):SoloState);
    }else if(Poses.IsValidIndex(ActivePose)&&Gallery->PairCombo&&!Gallery->PairedPlayback&&!Gallery->bPairPreparing){
        // The pair goes on in the state it was in (AOKInteractionMode::TickOutfitSwap); when it could not, from the start.
        const int32 Pose=ActivePose;SelectPose(Pose);
        // The same pose is still chosen in the list: its selection does not fire again.
        if(PendingPose==Pose&&Gallery->PairCombo->GetSelectedIndex()>0)Gallery->OnPairSelected(Gallery->PairCombo->GetSelectedOption(),ESelectInfo::OnMouseClick);
    }
    BuildList();
}
