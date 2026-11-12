#pragma once
#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "Components/Button.h"
#include "Components/Slider.h"
#include "Dom/JsonObject.h"
#include "Commandlets/Commandlet.h"
#include "OKArousalDrops.h"
#include "OKTears.h"
#include "KKRustExtract.h"
#include "OKHScene.generated.h"

// The street one-on-one as the original H scene (HSceneProc / HSprite, D:\KoikatuSunshine\H_scene.md): a menu of the
// authored poses by mode (service by hand, mouth, breasts; intercourse), each pose's state flow (Idle → Insert →
// InsertIdle → WLoop/SLoop → OLoop → finish → after), both gauges, speed, condom, the finish choices, her clothes; what
// happened is counted for her experience (Tools/ok-rules/src/hexp.rs). Replaces the card reader's test panel when the
// street opens the scene (UOKCharacterController::bHScene).
class UOKCharacterController;
class AKKPreviewActor;
class UOKHScenePanel;
class UTextBlock;
class UVerticalBox;
class UWrapBox;
class UProgressBar;
class USlider;
class UScrollBox;
struct FOKCoordLoad;

// One mirror of the H scene (UOKHScenePanel::TickMirror): its actor, the quad its picture is drawn on, the capture, and two
// pictures (user 2026-11-09: the mirror halved the frame rate) taken every other frame into the one not shown, then shown
// (Front), at twice the mirror's size on the screen for its edges (Size).
USTRUCT()
struct FOKHMirror {
    GENERATED_BODY()
    UPROPERTY() TObjectPtr<AActor> Actor;
    UPROPERTY() TObjectPtr<class UProceduralMeshComponent> Quad;
    UPROPERTY() TObjectPtr<class USceneCaptureComponent2D> Capture;
    UPROPERTY() TObjectPtr<class UTextureRenderTarget2D> Targets[2];
    UPROPERTY() TObjectPtr<class UMaterialInstanceDynamic> Shown;
    int32 Front=0,Size=0;uint64 TakenAt=0;
};

UCLASS()
class OPENKOIKATSU_API UOKHSceneButton : public UButton {
    GENERATED_BODY()
public:
    int32 Kind=INDEX_NONE;
    UPROPERTY() TObjectPtr<UOKHScenePanel> Owner;
    UFUNCTION() void HandleClick();
};

// A row of the settings panel on the left: a console variable (UOKHScenePanel, HSettings).
UCLASS()
class OPENKOIKATSU_API UOKHSettingSlider : public USlider {
    GENERATED_BODY()
public:
    int32 Row=INDEX_NONE;
    UPROPERTY() TObjectPtr<UTextBlock> Shown;
    UPROPERTY() TObjectPtr<UOKHScenePanel> Owner;
    // An on/off row (0..1 in steps of 1) is a button instead (user 2026-11-09): off white with black words, on black with
    // white words; the slider stays, hidden, holding the value.
    UPROPERTY() TObjectPtr<class UButton> Toggle;UPROPERTY() TObjectPtr<UTextBlock> ToggleText;
    void Show();
    UFUNCTION() void HandleValue(float NewValue);
    UFUNCTION() void HandleDone();
    UFUNCTION() void HandleToggle();
};

// Where his penis root goes (user, 2026-11-02): a point in a circle, dragged; its edge is the farthest that way
// (UOKHScenePanel::RootPad). Up her back, down her belly, left and right hers.
UCLASS()
class OPENKOIKATSU_API UOKHRootPad : public UUserWidget {
    GENERATED_BODY()
public:
    UPROPERTY() TObjectPtr<UOKHScenePanel> Owner;
    FVector2D Value=FVector2D::ZeroVector;
    virtual TSharedRef<SWidget> RebuildWidget() override;
    virtual int32 NativePaint(const FPaintArgs& Args,const FGeometry& Geometry,const FSlateRect& Culling,FSlateWindowElementList& Out,int32 Layer,const FWidgetStyle& Style,bool bParentEnabled) const override;
    virtual FReply NativeOnMouseButtonDown(const FGeometry& Geometry,const FPointerEvent& Event) override;
    virtual FReply NativeOnMouseMove(const FGeometry& Geometry,const FPointerEvent& Event) override;
    virtual FReply NativeOnMouseButtonUp(const FGeometry& Geometry,const FPointerEvent& Event) override;
private:
    bool bDragging=false;
    void Drag(const FGeometry& Geometry,const FPointerEvent& Event);
};

// One authored pose (Content/IndependentResources/StreetSocialData/h_poses.json, from ok-hposes) on the pair list.
struct FOKHPose {
    int32 Pair=INDEX_NONE;      // index in the controller's NativePairs
    int32 Mode=0;               // 1 service, 2 intercourse (AnimationInfo_XX)
    bool bThree=false;int32 SecondUpper=0,SecondLower=0;FString SecondSource,SecondMotion;int32 SecondLayer=0; // 3P (AnimationInfo_06, _07): plays as its mode, with the second heroine
    int32 KindHoushi=0;         // service: 0 hand, 1 mouth, 2 breasts
    int32 SysTaii=0;            // sysTaii: 0 hand or breasts only, 1 licking, 2 him in her mouth (咥え)
    bool Anal=false;
    bool FemaleLead=false;      // isFemaleInitiative: her lines are the voice table's rows 38 on (HSonyu num2)
    int32 IsExperience=0;       // 1: needs her used to it (慣れ)
    int32 StateRestriction=0;
    int32 UpperCloth=0,LowerCloth=0; // numFemaleUpper/LowerCloth: her top / bottom at least this undone for it (SetAllClothState)
    FString Name,Raw;          // shown (OKMotionLabelDisplay) and authored
    int32 Prop=0;              // what the private room adds for it: 0 none (floor), 1 seat, 2 table, 3 wall
};

UCLASS()
class OPENKOIKATSU_API UOKHScenePanel : public UUserWidget {
    GENERATED_BODY()
public:
    void PoseFailed(const FString& Why); // the pair player would not start it
    UPROPERTY() TObjectPtr<UOKCharacterController> Gallery;
    virtual TSharedRef<SWidget> RebuildWidget() override;
    virtual void NativeTick(const FGeometry& Geometry,float Delta) override;
    void TickScene(float Delta);float DeferredDelta=0.f;int32 DeferredTicks=0; // NativeTick: put off to the pair's idle point
    bool bTickingBeside=false,bIdleTickOwed=false; // ok.HScene.TickBeside: TickScene runs beside the solve; its session parts at the idle point (TickAtIdle)
    void TickAtIdle();
    double DevLineAt=0.; // DevLine is formatted at most 4 times a second
    bool bFastPaths=false;void FastPaths(bool bOn); // ok.HScene.FastPaths: Slate global invalidation and indexed accessory streams while the scene is up
    void Click(int32 Kind);
    // What happened, for h_session_end (counts) and her memory (poses, events).
    TSharedRef<FJsonObject> Result() const;
    // The control channel's view (/hscene): pose, state, gauges, the buttons now offered (kind and label), the list.
    TSharedRef<FJsonObject> Describe() const;
    bool SelectPoseNamed(const FString& Name);
    void SetLimbIk(const TSharedPtr<FJsonObject>& Settings);TSharedPtr<FJsonObject> LimbIkJson() const;
    void SetTongue(const TSharedPtr<FJsonObject>& Settings);TSharedPtr<FJsonObject> TongueJson() const;
    void SetMirror(const TSharedPtr<FJsonObject>& Settings,int32 Index=0);TSharedPtr<FJsonObject> MirrorJson(int32 Index=0) const;
    void SetSpeed(float Value);
    // Talk while it happens (the street's free talk, OKStreetSocialContacts.inl). What he says goes out at once, or,
    // while she cannot answer (moving faster than 2x), is held and goes out at her climax; her answer shows here and is
    // spoken on her (the street plays it, then her breathing comes back).
    void Say(const FString& Text);
    bool TakeLine(FString& Text,FString& Context,bool& System);
    // His words from elsewhere (the microphone): false when she cannot answer now (held for her climax).
    bool Hear(const FString& Text,FString& Context);
    void ShowLine(const FString& Text);
    void SpokeLine(){bTalkSpoken=true;}
    void SetReplyPending(bool bPending){bReplyPending=bPending;}
    UFUNCTION() void OnInputCommitted(const FText& Text,ETextCommit::Type Commit);
    // His penis set live (user, 2026-11-02): length (times along his dan bones) and size (his penis root scale), and
    // where its root goes: Pad in the unit circle, its edge RootReach cm off the way into her toward that side, the
    // entrance staying the pivot, so he presses the other way. Up her back, down her belly.
    void SetPenis(float Length,float Scale,float Most=2.f);void SetRootPad(const FVector2D& Pad,float Most=1.f);
    // Her outfit (the clothes tab, /hscene {"outfit":N} or {"coordinate":"file"}): her card's outfit 0..6, or a game
    // coordinate card (UserData/coordinate, by file name or path) worn as the outfit she has on (AOKInteractionMode::
    // ChangeOutfit). OutfitChanged: it is on her (or failed); the pose starts again on her new self.
    bool WearOutfit(int32 Outfit,const FString& Coordinate,FString& Why);
    void OutfitChanged(bool bOk);
    void ForgetClothCover();
    UFUNCTION() void OnPenisLength(float Value);
    UFUNCTION() void OnPenisScale(float Value);
    // Her pose set by him (user, 2026-11-02), on top of whatever plays: her ankles bent (degrees, both), each thigh opened
    // (degrees, left and right apart) and each hand's shape (-1 as the motion has it, else the game's hand pattern).
    // Held every frame through the pair's animation (her FK with '+' names, ApplyHerFk; her session's hand shapes).
    void SetHerPose(const float* Ankle,const float* ThighL,const float* ThighR,const int32* HandL,const int32* HandR);
    UFUNCTION() void OnAnkle(float Value);
    UFUNCTION() void OnTongueLength(float Value);
    UFUNCTION() void OnThighL(float Value);
    UFUNCTION() void OnThighR(float Value);
    UFUNCTION() void OnHandL(FString Option,ESelectInfo::Type How);
    UFUNCTION() void OnHandR(FString Option,ESelectInfo::Type How);

    enum EKind : int32 {
        TabHand=10,TabMouth=11,TabBreast=12,TabSonyu=20,TabClothes=30,TabAibu=40,TabSolo=41,TabPeep=42,TabGirls=43,Tab3P=44,
        AibuBase=500,
        TouchChest=2101,TouchCrotch=2102,TouchAnal=2103,TouchButt=2104,TouchNipple=2105,Kiss=2106,Release=2107,
        TouchHead=2130,TouchHand=2131,TouchThigh=2132,TouchCalf=2133,TouchFoot=2134,TouchLips=2135,LickToggle=2136, // H_SCENE_ADDITIONS_PLAN 3
        Afterglow=2137, // H_SCENE_ADDITIONS_PLAN 12
        SettingsToggle=2300,SettingsReset=2301, // the settings panel on the left
        HeadCameraToggle=2302,EyesCameraToggle=2303, // her head, her eyes on the camera
        PanelHideToggle=2304, // the panel on the right away and back (user 2026-11-09)
        LeaveToggle=2305, // back to the card reader (its one-on-one only; the street has its own leave button)
        PoseBase=1000,
        Faster=2001,Slower=2002,Toggle=2003,Inside=2004,Outside=2005,Drink=2006,Vomit=2007,Again=2008,Insert=2009,InsertAnal=2010,Pull=2011,Condom=2012,Stop=2014,Continue=2015,ToggleMale=2016,LockHer=2017,LockHis=2018,MaleBottom=2019,PenisXRayToggle=2020,PhysicsNext=2021,GrayRoomToggle=2022,PenisPanelToggle=2023,PenisReset=2024,FluidClear=2025,FeetPinToggle=2026,HandsPinToggle=2027,SkinLitToggle=2028,
        SecondChange=3690,SecondClothes=3691,SecondBase=3700, // the second heroine (lesbian, 3P)
        ClothesBase=3000,RoomBase=3200,OutfitBase=3300,CoordinateToggle=3310,CoordinateAccessories=3311,CoordinateBase=3400,
    };
private:
    // Caress (AnimationInfo_00): her own animation, him hidden (HAibu); each state is prepared up front.
    struct FAibuPose {FString Name,Source;int32 Layer=0,Id=-1,Prop=0,Info=0,Ctrl=0,SecondLayer=0,UpperCloth=0,LowerCloth=0,SecondUpper=0,SecondLower=0;FString SecondSource;}; // Info: HFlag.EMode, 0 caress, 3 masturbation, 4 peeping, 5 lesbian
    TArray<FAibuPose> AibuPoses;
    TMap<FString,FString> SoloKeys;      // state -> clip key of the active caress pose
    FString SoloState;double SoloStarted=0.;
    int32 SoloInfo=0;void TickSolo(float Delta); // she plays by herself (HMasturbation, HPeeping)
    // The second heroine of the lesbian and 3P poses: her own actor at her place, on her clock, playing the pose's second role.
    UPROPERTY() TObjectPtr<class AKKPreviewActor> Second;
    TArray<float> SecondFace,SecondBody;TMap<FString,FString> SecondKeys;FString SecondState,SecondName;
    int32 SecondGeneration=0;bool bSecondLoading=false,bSecondReady=false,bSecondBare=false;
    // Her part of the scene: the original has one gauge for both (flags.gaugeFemale), so she climaxes when the first does.
    // Who he is in: the original's 3P pose id % 2 picks the heroine (H3PSonyu num), so an odd pose (入れ替え) is the second's.
    // There the scene's counters are hers: FHLedger holds whichever heroine's are not in use, swapped by SyncSwap.
    struct FHLedger {bool bService=false,bRaw=false,bRawPressed=false,bCrotch=false,bAnal=false;int32 ServiceFinishes=0,CrotchClimaxes=0,AnalClimaxes=0,HisFinishes=0,HisInside=0,HisOutside=0,HisMouth=0,Swallowed=0,HisInsideRaw=0,HisCondom=0,HisInsideVaginaRaw=0,Siru[5]={0,0,0,0,0};float CrotchDeepest=0.f,AnalDeepest=0.f;};
    // A group pose as one heroine had it: hexp.rs group_role turns the seconds into her development there.
public:
    struct FGroupRow {FString Category,Role;int32 Id=0;float Seconds=0.f;int32 Climaxes=0;};
private:
    struct FSecondRun {int32 Girl=0;FString Id,Name;int32 Orgasms=0,Drips=0,Milk=0;TArray<FString> Poses;FHLedger Ledger;TArray<FGroupRow> Rows;TSharedPtr<FJsonObject> Experience;};
    TArray<FGroupRow> MainRows;bool bSwapped=false,bGirlsPlayed=false;
    void SyncSwap(bool bWant);bool SecondReceives() const;bool GroupPose(FString& Category,int32& Id) const;static FGroupRow& GroupRow(TArray<FGroupRow>& Rows,const FString& Category,int32 Id,const FString& Role);void TickGroup(float Delta);
    const TSharedPtr<FJsonObject>& Exp() const; // what the heroine he is with now has been through (Gallery->HExperience, or the second's)
    TArray<FSecondRun> SecondRuns;int32 SecondRun=INDEX_NONE,SecondPersonality=0,SecondLevel=0;float SecondVoiceRate=.5f;double SecondCameUntil=0.;FString SecondBreathKey,SecondFaceKey,SecondClothKey;uint8 SecondPieces[9]={};double SecondSquirtAt=0.,SecondMilkAt=0.,SecondDripAt=0.;void ApplySecondClothes();float SecondDev(const TCHAR* Area) const;
    void SecondReact();void SecondBreath(const FString& State);bool SecondHere() const;
    void LoadSecond(int32 Index);void DropSecond();void TickSecond(float Delta);void PlaySecond(const FString& State);void PrepareSecond(const FString& Source,int32 Layer);
    int32 ActiveAibu=INDEX_NONE,PendingAibu=INDEX_NONE,AibuGeneration=0,TouchArea=INDEX_NONE;
    int32 AreaClimaxes[11]={};          // her climaxes from his touch or kiss there (AreaSeconds order; hexp climaxes)
    float AreaSeconds[11]={};           // kiss, chest, crotch, anal, butt, nipples (hAreaExps order); head, hand, thigh, calf, foot
    // Touching or kissing (bLickMode) the rest of her (H_SCENE_ADDITIONS_PLAN 3): her lips touched (bLipsTouch, area 0
    // without the kiss), and the flinch of the touched part as the original's HitReaction.
    bool bLickMode=false,bLipsTouch=false,bAfterglow=false; // afterglow: done, lying with him, talking (12)
    void TouchBody(int32 Area);void Flinch(int32 Area);bool BodyTouching() const;
    void TickAhegao();bool bAhegaoPose=false; // her double peace (TickAhegao)
    // Her tongue out raised (TickTongue; ok.HScene.TongueUp / TonguePitch, {"tongue":{...}} on /hscene): its parts as they
    // were made (less the alignment's offset), the girl they are hers, and whether her mouth pattern has it out.
    void TickTongue();
    // Two 200 x 200 cm mirrors beside them (user 2026-11-09, the second 2026-11-12; TickMirror, ok.HScene.Mirror / MirrorYaw /
    // MirrorDistance and Mirror2 / Mirror2Yaw / Mirror2Distance, {"mirror":{...}} and {"mirror2":{...}} on /hscene): each a
    // capture from the camera's reflection through it, drawn on its quad (FOKHMirror).
    UPROPERTY() FOKHMirror Mirrors[2];int32 MirrorTurn=0;
    void TickMirror();void TickOneMirror(int32 Index,bool& bTaken);void RemoveMirror();void RemoveMirror(int32 Index);
    // Puddles on the floor round them (user 2026-11-12; TickPuddles, ok.HScene.Puddles / PuddleCount / PuddleSize,
    // {"puddles":{...}} on /hscene): nearly smooth lit water (M_OKPuddleLit) in which screen space reflections show them.
    UPROPERTY() TObjectPtr<AActor> Puddles;UPROPERTY() TArray<TObjectPtr<class UTexture2D>> PuddleMasks;
    UPROPERTY() TArray<TObjectPtr<UMaterialInstanceDynamic>> PuddleShown;float PuddleShineShown=-1.f;
    int32 PuddlesMade=0;float PuddlesSize=0.f;int32 PreviousSsrQuality=-1,PreviousReflectionMethod=-1;
    void TickPuddles();void RemovePuddles();
public:
    void SetPuddles(const TSharedPtr<FJsonObject>& Settings);TSharedPtr<FJsonObject> PuddlesJson() const;
private:
    // Their skin lit by the scene or the original's toon (ok.HScene.SkinLit, SkinLitToggle; user 2026-11-09).
    void TickSkinLit(bool bEnd);bool bSkinLitShown=false;
    void TickClothBias(bool bEnd);bool bClothBiasShown=false;
    // While lit: a key and a fill light on lighting channel 1 only (the pair, not the street), from the panel's light rows.
    TWeakObjectPtr<class UPointLightComponent> SkinKey,SkinFill;
    // Taken after her no (experience "forced"): her first words and her talk context (Context).
    bool Forced() const;bool bForcedSaid=false;double ForcedSayAt=0.;
    // She talks by herself every ok.HScene.ChatEvery seconds she can (user 2026-11-09), his words go on as before.
    void TickChatter();double QuietSince=0.;
    TMap<TWeakObjectPtr<class USceneComponent>,FTransform> TongueRest;TWeakObjectPtr<class AKKPreviewActor> TongueGirl;int32 TongueOutPattern=-2,TongueOutChecked=-1;bool bTongueRaised=false;
    void TickCameraLight(bool bEnd);bool bCameraLit=false; // their key light from the camera
    TMap<TWeakObjectPtr<class UMaterialInstanceDynamic>,FLinearColor> CameraLightWas;FVector CameraLightShown=FVector::ZeroVector;
    // The panel's light rows: their shadow ramp and the colour of the light, each material's own given back when they go.
    void TickLightChoice(bool bEnd);
    // Her outfits with something missing (outfit_gaps.rs, read in the background): marked on their buttons; a severe one
    // says so at the first press and is worn at the second.
    struct FOutfitGap{int32 Count=0;bool bSevere=false;};
    TMap<int32,FOutfitGap> OutfitGaps;FString OutfitGapCard;int32 OutfitWarned=INDEX_NONE;void ReadOutfitGaps();
    TMap<TWeakObjectPtr<class UMaterialInstanceDynamic>,TWeakObjectPtr<class UTexture>> RampWas;TMap<TWeakObjectPtr<class UMaterialInstanceDynamic>,FLinearColor> LightColorWas;
    FString RampShown;int32 TintShown=0;TArray<FString> LightRampKeys;
    UPROPERTY() TObjectPtr<class UComboBoxString> LightCombos[3];
    UFUNCTION() void OnLightStyle(FString Option,ESelectInfo::Type How);
    UFUNCTION() void OnLightFrom(FString Option,ESelectInfo::Type How);
    UFUNCTION() void OnLightTint(FString Option,ESelectInfo::Type How);
    TWeakObjectPtr<AKKPreviewActor> AheGazeFor;float AheGazeSet=0.f;int32 AheMouthSet=INDEX_NONE;bool bAheManualWas=false;double AheTongueUntil=0.; // her tongue out after a climax (CountHerOrgasm, UpdateFace) // her rolled-up gaze given (TickAhegao)
    bool bAheEyeLook=false,bAheEyeFollow=false;int32 AheEyePattern=1;FVector AheEyeTarget=FVector::ZeroVector; // her look, given back after it
    double FlinchUntil=0.,FlinchNext=0.;FString FlinchBone;FVector FlinchTurn=FVector::ZeroVector;
    bool bAibuLoaded=false;
    void LoadAibuPoses();
    void SelectAibu(int32 Index);
    void PlaySolo(const FString& State);
    void Touch(int32 Area);
    float AreaExperience(int32 Area) const;
    bool NeverHad(int32 Area) const;
    // Her development there, 0..1 (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md): chest, nipple, crotch, anal or oral, as she
    // came in plus ten points for each climax there this scene (crotch, anal) or each time he came in her mouth (oral).
    float Dev(const TCHAR* Area) const;
    // Her bust grows with her excitement as her chest is developed (up to half again at 100%), eased.
    // and, sucking him, her face (her mouth's development): cheeks drawn in, mouth and chin pulled long, eyes rolled up,
    // tears. Both through her live shape (her card's values changed, MarkShapeDirty).
    void SwellBust(float Delta);float BustSwell=1.f,BustSwellSet=1.f,OralSuck=0.f,OralSuckSet=0.f,OralPull=0.f,OralPullSet=0.f,OralGazeSet=0.f;double NippleUntil=0,TearAt=0;bool bSucking=false;
    void LoadPoses();
    void BuildList();
    void BuildActions();
    void SelectPose(int32 PoseIndex);
    void PoseClothes(int32 Upper,int32 Lower);
    // His penis drawn through her (ApplyMaleLook) only in a pose where he is in her: as it was last applied.
    bool XRayInHer() const;bool bXRayInHer=false;
    bool FinishInMouth() const;
    bool bOpeningChecked=false; // the scene moved from its opening pose to the first caress, once (NativeTick)
    void Want(const FString& State);
    void Chain(const TArray<FString>& States);
    bool Has(const FString& State) const;
    FString P(const FString& State) const {return bAnalPlay?TEXT("A_")+State:State;}
    void Finish(const TCHAR* Kind);
    void Note(const FString& Text,bool bReact=true);
    bool Hooked() const; // hooked on it (ok-rules hexp addicted): past her limit she begs for more
    // The original's H sounds (HSeCtrl, the base library's h/se.json): a pose's state plays each of its sounds as its
    // normalized time passes the sound's key (entering her, the thrusts, pulling out).
    void TickSounds();void PlaySe(const FString& Clip);FString SoundState;float SoundTime=0.f;
    UPROPERTY() TArray<TObjectPtr<USoundBase>> SoundsPlaying;
    // One of her lines from the intercourse voice table (HSonyu playVoices - 300), in her experience bank.
    bool PlayHVoice(int32 Row);
    void ApplySpeed();float BellyPullback=0.f;bool bPullbackLogged=false;float SkinFacing=0.f;bool bBellySide=false;int32 BulgeRefused=0;float WrapMs=0.f,WrapSolveMs=0.f,SwellMs=0.f;bool bWrapShown=false,bWrapLineShown=false;int32 WrapVerts=0; /* her skin moved over him (ReadBulge) */FVector BellyFront=FVector::ZeroVector;float TipInside=-1.f; // cm his glans is past her entrance along himself (-1 none)
    FString Current() const;
    int32 Level() const;
    // She has come as many times as she will this scene (climax_limit): she wants it to stop, the panel offers no more
    // touching, moving or entering her.
    bool HadEnough() const;
    void CountHerOrgasm();FString History() const;

    UPROPERTY() TObjectPtr<UTextBlock> Title;
    UPROPERTY() TObjectPtr<UTextBlock> Status;
    UPROPERTY() TObjectPtr<UTextBlock> DevLine; // her five developments now, with what this scene added
    UPROPERTY() TObjectPtr<UTextBlock> Hint;
    UPROPERTY() TObjectPtr<UProgressBar> HerGauge;
    UPROPERTY() TObjectPtr<UProgressBar> HisGauge;
    UPROPERTY() TObjectPtr<USlider> Speed;
    UPROPERTY() TObjectPtr<class UBorder> SpeedCover; // over 70% of the speed bar while she is touched where she never was
    UPROPERTY() TObjectPtr<UVerticalBox> PenisBox;
    // Half size: the inner box twice the panel high (NativeTick, from the panel as laid out), drawn at half.
    UPROPERTY() TObjectPtr<class USizeBox> HalfInner;UPROPERTY() TObjectPtr<class USizeBox> PanelWidth;
    UPROPERTY() TObjectPtr<USlider> LengthSlider;
    UPROPERTY() TObjectPtr<USlider> TongueSlider;UPROPERTY() TObjectPtr<USlider> AnkleSlider;UPROPERTY() TObjectPtr<USlider> ThighSliders[2];UPROPERTY() TObjectPtr<class UComboBoxString> HandCombos[2];
    float AnkleTurn=0.f,ThighOpen[2]={0.f,0.f};int32 HandPattern[2]={-1,-1},HandShown[2]={-1,-1},HandOptions=-1;TWeakObjectPtr<class AKKPreviewActor> HandGirl,EyesCameraGirl;void TickEyesCamera();FVector4f HerPoseShown=FVector4f(0.f,0.f,0.f,0.f);
    // Her FK this frame: her trembling (Tremble) and the pose he set, together (her session holds one FK list).
    void ApplyHerFk(class AKKPreviewActor* Girl,TArray<FString>& Names,TArray<FVector>& Turns);void TickHands();
    double PaizuriMilkAt=0;
    UPROPERTY() TObjectPtr<USlider> ScaleSlider;
    UPROPERTY() TObjectPtr<UTextBlock> PenisLabel;
    UPROPERTY() TObjectPtr<UOKHRootPad> RootPadWidget;
    float PenisLength=1.f,PenisScale=1.f,PenisSetLength=1.f,PenisSetScale=1.f;FVector2D RootPad=FVector2D::ZeroVector;FVector2D RootPadNow=FVector2D::ZeroVector;float RootPadScale=1.f;bool bPenisPanel=false;bool bPanelHidden=false;
    UPROPERTY() TObjectPtr<class UTextBlock> PanelHideText;
    UPROPERTY() TObjectPtr<class UButton> LeaveButton; // the card reader's one-on-one only (LeaveToggle)
    bool bLeaveChecked=false;
    // Twice the 8 cm it was (user, 2026-11-02: the pad's edge reaches where (0,2) did).
    static constexpr float RootReach=16.f;
    void ShowPenis();
    UPROPERTY() TObjectPtr<class USizeBox> SettingsBox;UPROPERTY() TArray<TObjectPtr<UOKHSettingSlider>> SettingSliders;bool bSettingsOpen=false;
    TMap<FString,float> DevSet; // her development as set on the panel (Result)
    UPROPERTY() TObjectPtr<class USizeBox> CoordSides[2];UPROPERTY() TObjectPtr<UWrapBox> CoordWraps[2];
    UPROPERTY() TArray<TObjectPtr<UOKHSceneButton>> CoordButtons;UPROPERTY() TArray<TObjectPtr<class UImage>> CoordImages;UPROPERTY() TArray<TObjectPtr<class UTexture2D>> CoordTextures;TSharedPtr<FOKCoordLoad> CoordLoad;double CoordShown=0.;
    UPROPERTY() TObjectPtr<UTextBlock> CoordAccessories;void ShowCoordinates();void ShowAccessories();void MarkCoordinate();void TickCoordinates();
    bool bHeadCamera=false;TWeakObjectPtr<AKKPreviewActor> HeadCameraGirl;bool HEyesOnCamera() const;
    TArray<FVector> AheHandAt;float AheHeadRise=0.f; // where her double peace puts her hands (HoldFeet gives them); her head above her shoulders as it began
    UPROPERTY() TObjectPtr<UWrapBox> Actions;
    UPROPERTY() TObjectPtr<UWrapBox> Tabs;
    UPROPERTY() TObjectPtr<UScrollBox> List;
    UPROPERTY() TObjectPtr<class UEditableTextBox> Input;
    UPROPERTY() TObjectPtr<UTextBlock> Caption;
    struct FHLine {FString Text,Note;bool System=false;};
    TArray<FHLine> Outbox;
    TArray<FString> Held;
    bool bTalkSpoken=false,bReplyPending=false,bChatOpen=true;FString OutfitLoadingText;
    // 0.5x to 4x while moving; past 2x she has no breath to answer.
    float PlaybackSpeed() const {return .5f+3.5f*SpeedValue;}
    bool CannotAnswer() const;
    void ReleaseHeld(const TCHAR* NoteKey=TEXT("ui.hscene.held_note"));
    // Her eyes and brows follow the moment (state, her gauge, how used to it she is), as the original's H face lists do.
    void UpdateFace();
    // Her cheeks flush with her excitement (the face's blush overlay, ChangeHohoAkaRate's _overcolor2 alpha = lerp(0, .2, rate)):
    // it rises with her gauge and fades slowly after, so she is still flushed after she comes. Her card's own blush is the floor.
    void UpdateBlush(float Delta);void RestoreBlush();
    // Semen on her (ChaControl siruLv: face, front top, front bottom, back top, back bottom; 0..2), written to her materials'
    // _liquid* as the original does every frame; where it lands follows the finish and which side of her he is on. It is
    // cleared when the scene ends, as the original cleans her up after H.
    int32 Siru[5]={0,0,0,0,0};void AddSiru(int32 Area);void ApplySiru();int32 SiruSide() const;
    // Her materials that draw the liquid: component, parent, the liquid textures bound (diagnostic in /hscene).
    TArray<FString> LiquidReport() const;float SiruRefresh=0.f;
    TWeakObjectPtr<class AKKPreviewActor> BlushFor;float Blush=-1.f,BlushShown=-1.f;bool bBlushLogged=false;
public:
    void BareChest();bool bAhegaoShown=false;int32 AhegaoMouth=INDEX_NONE;
    // What runs out of her in the room (her desire past 100, OKArousalDrops.h): the drops, her next one at her crotch and
    // at a nipple, which nipple, and how many came (into the result: she leaves the room as wet).
    void TickDrips(float Delta);float HerDesire() const;FOKArousalDrops Drips;FOKTears Tears;uint8 TearsWanted=0;void SpawnTears(class AKKPreviewActor* Girl);void AimIntoMouth(class AKKPreviewActor* Girl,class AKKPreviewActor* Him);void HideInMouth(class AKKPreviewActor* Girl,class AKKPreviewActor* Him);
    TWeakObjectPtr<class AKKPreviewActor> MouthClipHim;int32 MouthClipPart=INDEX_NONE;int32 MouthClipVerts=0;bool bMouthAimed=false;FVector MouthAim=FVector::ZeroVector;float MouthTurned=0.f;FVector MouthDbg=FVector::ZeroVector;double DripAt=0,MilkAt=0,NippleSprayAt=0,SquirtAt=0,ClimaxUntil=0,ClimaxLoopFor=0;bool bTrembling=false,bVaginaLogged=false;void Tremble(double Now);bool StreetOnani() const;int32 MilkTurn=0,HerDrips=0,HerMilk=0;int32 HerDripTimes=0,HerMilkTimes=0;double DripBoutAt=-100.,MilkBoutAt=-100.; // drops, and the times she ran (a pause of 3 s starts another; the result shows these)
    void ClearLine();
    void TickEyeDull(float Delta);float EyeDullScale=0.f;bool bEyeDullHidden=false; // her pupils and highlight (a yandere, or worn out)
    void TickEyeLook(AKKPreviewActor* Girl,float Delta);void RestoreEyeLook();TWeakObjectPtr<AKKPreviewActor> EyeLookActor;float EyeLookWait=0.f; // the panel's pupil shape and colour, her eyelids
    struct FHStyled{TWeakObjectPtr<class AKKPreviewActor> Actor;float Shown=0.f;FVector Base=FVector::ZeroVector;TArray<float> CardFace,CardBody,Face,Body;};
    FHStyled Styled[2];float StyleWait=0.f;bool bStyleOpen=false; // her, him
    void TickStyle(float Delta);void ApplyStyle(FHStyled& S,float Style);void RestoreStyle();const TArray<float>& HerFace() const;const TArray<float>& HerBody() const;
    FVector2f PupilStretchShown=FVector2f(1.f,1.f);FVector3f IrisHsvShown=FVector3f(0.f,1.f,1.f);FOKIrisMarks PupilMarksShown;float EyeFrameShown=0.f;
    float PupilShakeClock=0.f;FVector2f PupilShakeFrom=FVector2f::ZeroVector,PupilShakeTo=FVector2f::ZeroVector,PupilShakeNow=FVector2f::ZeroVector; // her pupils' tremble
    void TickDeepFace(float Delta);void EndDeepFace(class AKKPreviewActor* Girl);float DeepFace=0.f,DeepGazeSet=0.f;bool bDeepFace=false,bDeepManualWas=false,bAheDepth=false; // her eyes and tongue with how deep he is (TickDeepFace)
    // Her line asked for before a climax, a finish or a new pose comes back after it ("don't stop" once he had come):
    // it is not shown or spoken. LineEpoch moves at those; SentEpoch is the epoch her last line was asked in.
    int32 LineEpoch=0,SentEpoch=0;bool bStaleLine=false;
    // When he or she last came (Finish) and who (0 he, 1 she, 2 both): the words for the state until the after pose.
    double JustCameAt=0.;int32 JustCame=0;
    bool LineIsStale() const {return bStaleLine;}
    // A newer happening waits for her reaction (React): what she is still saying reacts to an older one.
    bool HasReaction() const {return Outbox.ContainsByPredicate([](const FHLine& L){return L.System;});}
    FString JudgeFacts() const; // for the H talk judge: the pose, what is happening, the poses she could be asked into
    bool ApplyTalk(const TSharedPtr<FJsonObject>& Verdict); // its verdict done as the buttons would; true: the scene ends
    void LookAtFace(float Distance,float Turn=0.f); // Turn: degrees round her from in front of her face (90: her side)
    void LookAtCrotch(float Distance,float Pitch=15.f,float Turn=0.f,bool bFront=false); // /hscene {"crotch_cam":cm} or {distance, pitch, turn}: where they join, from beside her body // /hscene {"face_cam":cm}: the camera in front of her face, to see what is on it
    void SetSiruTest(const int32 (&Levels)[5]); // /hscene {"siru":[...]}: set her liquid levels directly
    TMap<FString,float> DevTest; // /hscene {"dev":{...}}: her development, for testing (Dev)
    float DevOf(const TCHAR* Area) const;void SetDev(const TCHAR* Area,float Value); // the left panel's rows
    // Her pregnancy (ok-rules pregnancy.rs, in her experience): belly and changed areolae shown in the scene.
    // /hscene {"preg":{"belly":0..1,"body":0..1}} holds them for testing (-1 back to hers).
    float PregBellyTest=-1.f,PregBodyTest=-1.f;
    void ApplyPregnancy(double Now);double PregCheckAt=0.;float PregBellyShown=0.f;TWeakObjectPtr<class AKKPreviewActor> PregActor;int32 PregOutfit=-1;
    float PregBelly() const;float PregNipples() const;float PregBust() const;bool PregLocks(const FOKHPose& Pose) const;
    // /hscene {"penis_green":true}: his penis flat pure green, depth-tested, so any of it out of her skin shows (testing).
    void SetPenisGreen(bool bOn);bool bPenisGreen=false;UPROPERTY() TArray<TObjectPtr<UMaterialInterface>> GreenKept;TArray<TWeakObjectPtr<UMeshComponent>> GreenComps;
    float BlushTest=-1.f; // /hscene {"blush":v}: hold her blush at v (0..1) to compare shots; -1 follows her
private:
    UPROPERTY() TArray<TObjectPtr<class UMaterialInstanceDynamic>> BlushMats; TArray<float> BlushBase;
    FString FaceKey;
    // A new pose frames her from the side of the line between them, turned to her front (his back no longer fills the
    // view); he can be hidden as in the original. The player's own orbit stays until the next pose.
    void FrameCamera();
    // A wall between the camera and them is hidden for the shot (after the camera moves and after props are placed).
    void HideWallsInTheWay();
    FString FramedKey;double FrameAt=0;bool bMaleHidden=false;
    // How he is drawn (the original's male display): 0 as he is, 1 one see-through colour (her and the penis seen through
    // him), 2 hidden. His bottom comes off for the scene (the penis shows) unless the player puts it back on.
    // See-through by default: where his penis is in her shows (the original's silhouette).
    // The street hidden behind a plain grey room around them (user, 2026-11-01): the world's actors hidden (lights,
    // cameras and the two of them kept), six grey slabs round her.
    void SetGrayRoom(bool bOn);void HideWorld();double GrayCheckAt=0.;bool bGrayRoom=false;UPROPERTY() TArray<TObjectPtr<AActor>> GrayRoom;TArray<TWeakObjectPtr<AActor>> GrayHidden;
    int32 MaleView=1;bool bMaleBottomOff=true;bool bPenisXRay=false; /* off by default: user 2026-11-11 */TWeakObjectPtr<class AKKPreviewActor> MaleLookFor;
    UPROPERTY() TObjectPtr<class UMaterialInstanceDynamic> MaleGhost;
    UPROPERTY() TObjectPtr<class UMaterialInstanceDynamic> PenisXRay; // over her while he is see-through (M_PreviewXRay)
    UPROPERTY() TArray<TObjectPtr<class UMeshComponent>> MaleGhostComps;
    UPROPERTY() TArray<TObjectPtr<class UMaterialInterface>> MaleGhostMats; // their own materials, slot by slot, to put back
    UPROPERTY() TArray<TObjectPtr<class UMeshComponent>> MaleGhostOutlines; // his outline shells, hidden while see-through
    void ApplyMaleLook();
    // The pair's clips are made for standard bodies: with her (or him) taller or shorter the penis misses her or goes
    // through her (the original too). While he is in her, he is moved so the line of his penis passes through her entrance
    // and the entrance stays along its length; the thrust along it is the clip's. His actor stays on her origin (the pair
    // player requires one origin): the offset is on the parts under his root.
    void AlignHim(float Delta);
    // Where his glans comes out of her skin (a thin girl, a clip made for a thicker one), her skin swells there instead of
    // letting it come through: of the belly.bulge morphs made on her body (ok-extract belly_bulge.rs, a grid over her pubic
    // mound, groins, belly and back), the one that moves that skin most, out by how far he is past it. Her session tells
    // (BellyBulgePast). Tip null: he is not in her, all ease off.
    void BulgeBelly(class AKKPreviewActor* Girl,const FVector* Tip,float Off,float Delta);
    // His glans and how far it is out of her skin, read from both sessions when the pair playback says they are idle
    // (AKKPairedPlayback::OnSessionsIdle); without a playback, AlignHim and BulgeBelly read them themselves.
    float AimTilt=35.f;void ReadPairSessions();void ReadBulge(class AKKPreviewActor* Girl,const FVector& Tip,const FVector* Root=nullptr);float AimRelax=0.f;float SkinOutMost=-100.f;float SkinUnderMost=-100.f;float SkinWorst=-100.f;float SkinRest=0.f;float SkinWorstAlong=0.f;FVector SkinNormal=FVector::ZeroVector;FVector RootDodge=FVector::ZeroVector;float DepthCap=1.f;int32 LiftedPose=INDEX_NONE;bool bLifted=false;
    TWeakObjectPtr<class AKKPairedPlayback> ReadingPlayback;FDelegateHandle ReadingHandle;
    TMap<FName,float> Bulge;int32 BulgePart=INDEX_NONE;FName BulgeOpen;float OpenEased=0.f;FName BulgeTarget;float BulgePast=0.f,BulgeMoves=0.f;bool bBulgeLogged=false;TWeakObjectPtr<class AKKPreviewActor> BulgedHer;
    // Her clothes kept over her skin (CoverClothes): her skin's wrap moves this frame, the garments moved, the time it took.
    void CoverClothes(class AKKPreviewActor* Girl);TArray<uint32> WrapIdxShown;TArray<FVector3f> WrapDShown,WrapNShown;TWeakObjectPtr<class AKKPreviewActor> ClothGirl;TSet<int32> ClothShown;TMap<int32,double> ClothCpuUntil;int32 ClothVerts=0;float ClothMs=0.f;
    // His penis out through her back folded under her skin (ReadBulge, penis.clip): his part with that morph, whether it is moved now.
    TWeakObjectPtr<class AKKPreviewActor> ClipHim;int32 ClipPart=INDEX_NONE;bool bClipShown=false;int32 ClipVerts=0;float BackExitCm=-1.f;float ClipLastTip=-1.f,ClipLeadCm=0.f;bool bAlignByGlans=false;double AlignNoLineLog=0.;TArray<int32> ClothParts,ClothCpu;TArray<uint32> ClothIdx;TArray<FVector3f> ClothD;bool bClothPiped=false,bClothTaken=false,bWrapTipKnown=false;FVector WrapLastTip=FVector::ZeroVector;
    // The game's coordinate cards (UserData/coordinate and its folders), listed in the clothes tab when opened.
    bool bCoordinateList=false;TArray<FString> CoordinateCards;void FindCoordinateCards();
public:
    // A coordinate card worn with its accessories too (else only its clothes: hers, hair made of accessories among them, stay).
    bool bCoordinateAccessories=false;
private:
    class AOKInteractionMode* Interaction() const;
    // The girl whose shoes were taken off on coming into her room (NativeTick): once each, she may put them back on.
    TWeakObjectPtr<class AKKPreviewActor> ShoesOffFor;
    // His glans from his penis root, from his session (the end of his penis mesh; J_dan109 draws in as he goes in): kept
    // between reads.
    FVector GlansFromRoot=FVector::ZeroVector;bool bGlans=false;
    FVector HimOffset=FVector::ZeroVector,HimApplied=FVector::ZeroVector;FString AlignedKey;bool bAlignLogged=false;TWeakObjectPtr<class AKKPreviewActor> AlignedHim;
    // The taller one bends the knees instead of sinking through the floor or floating over it: he is lowered with his feet
    // held where they were (Studio IK foot targets); when he would have to rise, she is lowered the same way.
    FVector HerOffset=FVector::ZeroVector,HerApplied=FVector::ZeroVector;TWeakObjectPtr<class AKKPreviewActor> AlignedHer;
    int32 FeetWait=0,HandsWait=0;bool bFeetRead=false,bHisStands=false,bHerStands=false,bHisIk=false,bHerIk=false;FVector HisFeet[2],HerFeet[2],HisHeld[2],HerHeld[2];
    // Her hands on his penis while she sucks him (GripHim): IK effectors (5, 6) and where, her skeleton space; what was set.
    TArray<int32> HandEff;TArray<FVector> HandAt,HandHeld;void GripHim(class AKKPreviewActor* Girl,class AKKPreviewActor* Him,const FVector& Lips,const FVector& Root,const FVector& Axis);
    // IK targets of HoldFeet while the pair plays: sent when both sessions are idle (ReadPairSessions) instead of waiting
    // for the solve (SyncPair) each time they move. Each actor's latest set replaces the one before.
    struct FPendingIk{TWeakObjectPtr<class AKKPreviewActor> Who;TArray<int32> Eff;TArray<FVector> At;uint64 Frame=0;};TArray<FPendingIk> PendingIk;
    void SendPendingIk(bool bWait);void DropPendingIk(class AKKPreviewActor* A);
    void MoveParts(class AKKPreviewActor* A,const FVector& Want,FVector& Applied);void HoldFeet(class AKKPreviewActor* A,bool bStands,const FVector& Offset,const FVector (&Feet)[2],FVector (&Kept)[2],bool& bIk,bool bPin=false,const FVector* PinHands=nullptr,FVector* KeptHands=nullptr,int32* KeptSet=nullptr);
    bool bPinFeet=true; // FeetPinToggle: while he is in her their soles stay where the clip put them (IK)
    // HandsPinToggle: while he is in her their hands stay where the clip put them (IK), his on her waist going with it.
    bool bPinHands=true,bHandsRead=false;FVector HisHands[2],HerHands[2],HisHandsKept[2],HerHandsKept[2],HisHandLocal[2];FName HisHandOn[2];int32 HisIkSet=0,HerIkSet=0;FVector HimOffsetWas=FVector::ZeroVector,HerOffsetWas=FVector::ZeroVector;
    FVector HandOnSum[2][3],HandOnSq[2][3],HandOnLast[2][3];int32 HandOnN[2][3]={}; // his hands on each of her waist bones over the read (ReadHands)
    bool bHandsReading=false;void ReadHands(class AKKPreviewActor* Girl,class AKKPreviewActor* Him);
    // Their limbs' IK, set from the control channel too ({"limb_ik":{...}} on /hscene; LimbIkJson in the answer):
    // a hand of his holds her waist bone it keeps within HandSpreadMax cm of, no farther than HandFarMax cm off it;
    // bFeetToHers puts his soles as high as hers while both are within FeetFloorNear cm of the floor.
    float HandSpreadMax=2.5f,HandFarMax=35.f,FeetFloorNear=25.f;bool bFeetToHers=true;
    void FeetToHers(class AKKPreviewActor* Girl,class AKKPreviewActor* Him,FVector (&Out)[2]) const;
    // The pair solves its next frame in the background (ok.Anim.AsyncPair): wait for it before touching either session.
    void SyncPair();
    void RestoreAlign();
    float AlignFoot=0.f,AlignPushed=0.f,AlignDeep=0.f;
    float FeetMin[2]={0,0},FeetMax[2]={0,0},FeetShown[4]={0,0,0,0}; // his and her lower ankle over the floor, range in the last two seconds // his lower ankle above her floor (cm), for /hscene
    float AlignOff=-1.f,AlignAt=0.f,AlignLen=0.f,AlignTip=-1.f; // the last measure while he is in her (cm off the penis line, % of its length), for /hscene
    float ThrustApplied=0.f,ThrustLow=1.f,ThrustHigh=0.f; // his push along his penis now, the clip's shallowest / deepest lately
    float DeepAlong=1e9f; // the deepest point of his thrusts lately (entrance distance from the root along the penis), easing back
    float AtMin=0.f,AtMax=0.f,AtShownMin=0.f,AtShownMax=0.f,AtWindow=0.f; // depth range over the last two seconds, for /hscene
    TSet<int32> Offered; // the action kinds BuildActions shows now
    // The original's poses on a chair, a desk or at a wall need that thing: the room puts a plain one where the pose
    // has her (or him) lean, sit or lie, measured from their bones once the pose stands (PlaceProps).
    UPROPERTY() TArray<TObjectPtr<class AStaticMeshActor>> Props;bool bPropsTable=false; // a table she leans on goes down with her
    FString PropKey;double PropAt=0;
    // A new pose or place jumps them, the props and the camera at once: the screen goes black at the change and fades in
    // once the new pose plays (the pair restarted, at most three seconds), as the original fades its position changes.
    bool bCovered=false,bEntered=false;double CoverAt=0;float CoverElapsed=0;TWeakObjectPtr<class AKKPairedPlayback> CoverPlayback;FString CoverClip,LastPoseKey;bool bPlaceOnly=false;
    // What the pair played on the previous tick: a cached pose is committed in the click itself, before this tick sees it.
    TWeakObjectPtr<class AKKPairedPlayback> SeenPlayback;FString SeenClip;float SeenElapsed=0;
    bool NewPosePlays(double Now) const;void Cover(bool bOn,double Now);
    void PlaceProps(int32 Kind);
    // Where they are (the original's map choice): 0 the floor, 1 a bed under them in the floor poses.
    int32 Room=0;
    void ClearProps();
    virtual void NativeDestruct() override;
    // The original's gauge locks: a locked gauge stops short of climax (his below the finish choices in a service, so
    // nothing happens by itself); he still finishes with the buttons.
    bool bLockHer=false,bLockHis=false;
    // A moment she reacts to in her own words (her character, how she feels now): sent as a game note, the latest only.
    void React(const FString& Event,const FString& Extra=FString());
    void CaressBreath();
    FString Context() const;
    FString StateWords(const FString& Base) const;
    bool bRawAsked=false,bRawPressed=false;
    // Condoms (user 2026-11-03): none on unless one of them has one. Put on this scene, his and hers; the one on is not yet
    // in her (Fresh: taken off, it goes back), is hers, or he has finished in it (Spent: off once he pulls out).
    int32 CondomsHis=0,CondomsHer=0;bool bCondomFresh=false,bCondomHers=false,bCondomSpent=false;
    // Past 100 favor she puts it on him with her mouth (user 2026-11-04): a blowjob picked at random plays a few seconds, then
    // back to the pose he was in, condom on. From: that pose, INDEX_NONE when she is not at it; At: when she has it on.
    int32 CondomMouthFrom=INDEX_NONE,CondomMouthPose=INDEX_NONE;double CondomMouthAt=0.;bool bCondomMouthBack=false;bool StartCondomMouth();void PutCondomOn();
    double GripUntil[2]={0.,0.}; // a hand on him (GripHim) closes round him until then, as the panel has not set one
    int32 CondomsLeft(bool bHers) const;void DropSpentCondom();
    // Out of condoms (user 2026-11-03): he says so, and her answer (her character, how much she wants it, her libido) is
    // read by the H judge like his question when she is pregnant (lets_raw): she may say let's do it without.
    bool bNoCondomAsked=false;void AskNoCondoms();
    // Pregnant and she knows (user 2026-11-03): whether he may go without is hers to say by her character. He asks her,
    // the H judge reads her answer (lets_raw): 1 yes, -1 no, 0 not answered.
    int32 RawLet=0;bool bRawAskedPregnant=false;bool PregnantKnows() const;
    int32 HisInside=0,HisOutside=0,HisMouth=0,Swallowed=0;
    int32 HisInsideRaw=0,HisCondom=0,HisInsideVaginaRaw=0; // in her: his finishes inside without a condom, and any with one (discharge); in her vagina without one (pregnancy)
    TArray<FOKHPose> Poses;
    int32 Tab=TabSonyu,ActivePose=INDEX_NONE,PendingPose=INDEX_NONE;
    int32 Mode=-1;              // of the active pose: 0 caress, 1 service, 2 intercourse
    FString Wanted,LastState,ActionsKey;
    TArray<FString> Queue;      // states still to play, in order (a finish, the insertion)
    double StateSeen=0.,LastRequest=0.,OralIdleSince=0.;
    float Her=0.f,His=0.f,SpeedValue=.35f;
    bool bStrong=false,bAnalPlay=false,bCondom=false,bInsertedNow=false,bInsideFinished=false,bAnalRefused=false,bAnalAsked=false,bServiceRefused=false,bSaidEnough=false; // bServiceRefused: she has served him as many times as she will this scene (service_rounds)
    // Counts for her experience.
    bool bPlayed=false,bService=false,bRaw=false,bCrotch=false,bAnal=false;
    int32 ServiceFinishes=0,CrotchClimaxes=0,AnalClimaxes=0,HerOrgasms=0,HisFinishes=0;
    // How deep he went in each (AlignDeep while they move, 0..100): her first time all the way in is a memory (hexp.rs).
    float CrotchDeepest=0.f,AnalDeepest=0.f;
    TArray<FString> PosesPlayed,Events;
    // Her body fluids by the water gun (TickFluids; H_SCENE_ADDITIONS_PLAN 1, 2, 9).
    UPROPERTY() TObjectPtr<class AOKPaintSprayer> Fluid;void TickFluids(float Delta);void Spurt(int32 Pulses);
    double SpurtAt=0.,LeakUntil=0.,LeakFor=1.,MouthSpillUntil=0.,MouthDribbleUntil=0.,DroolAt=0.,DroolOnUntil=0.;int32 SpurtLeft=0,LeakPending=0;bool bLeakAnal=false,bKissTongue=false,DroolTurn=false;
};

// The see-through material for his penis inside her (M_PreviewXRay): the translucent preview parent with the depth
// test off, drawn over her as an overlay. Run once in the editor: -run=OKBuildHXRayMaterial (PreviewMaterials is cooked).
UCLASS()
class OPENKOIKATSU_API UOKBuildHXRayMaterialCommandlet : public UCommandlet {
    GENERATED_BODY()
public:
    virtual int32 Main(const FString& Params) override;
};
