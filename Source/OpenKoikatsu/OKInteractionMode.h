#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "OKBodyInteraction.h"
#include "OKBodyGesture.h"
#include "OKInteractionMode.generated.h"

class UOKCharacterController;
class AKKPreviewActor;
class APlayerController;
class FJsonObject;

// One in-world lifetime for both entry points. No browser, process or IPC ownership.
UCLASS()
class OPENKOIKATSU_API AOKInteractionMode : public AActor {
    GENERATED_BODY()
public:
    AOKInteractionMode();
    // InPlace: where she stands in the world the scene is in (the street's one-on-one, user 2026-11-01: right there,
    // no change of scene): nothing of the world is hidden, she is set down there and the scene's showcase floor, wall
    // and light stay away. Null: the showcase room as before.
    static AOKInteractionMode* Enter(UOKCharacterController* Controller,const FTransform* InPlace=nullptr);
    static AOKInteractionMode* EnterReader(UOKCharacterController* Source);
    static AOKInteractionMode* EnterCards(APlayerController* Player,const FString& Female,const FString& Male,int32 FemaleOutfit=0,const FTransform* InPlace=nullptr); // FemaleOutfit: the outfit she wears (the street's)
    virtual void Tick(float Delta) override;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
    void Exit(bool Cancelled=false);
    // The street's fitting (OKStreetSocialWardrobe.inl): she alone, standing, to be looked at: no partner, no pose, no panel.
    bool bFitting=false;
    FBox FittingRoom=FBox(ForceInit); // the room she tries clothes on in: the city's walls have no collision, the camera stays inside this
    // The street's one-on-one: the H scene panel for her (name, relation stage, ok-rules h_experience answer).
    void BeginHScene(const FString& Name,const FString& Stage,const TSharedPtr<FJsonObject>& Experience,const FString& Player);
    // The control channel's /hscene: {kind} presses a panel button, {pose} picks a pose by name, {speed} sets it; answers the panel's view.
    TSharedPtr<FJsonObject> HSceneControl(const TSharedPtr<FJsonObject>& Body,FString& Error);
    void SetHPaused(bool bPaused); // the two of them stopped where they are (space key, control channel)
    // Talk in the H scene through the street (UOKHScenePanel::Say): his next line and what she is in the middle of;
    // her line to show; her spoken line on her high model.
    bool HSceneTakeLine(FString& Text,FString& Context,bool& System);
    bool HSceneHear(const FString& Text,FString& Context);
    void HSceneShowLine(const FString& Text);
    FString HSceneJudgeFacts() const;
    bool HSceneApplyTalk(const TSharedPtr<FJsonObject>& Verdict);
    bool HSceneSpeak(const FString& Path);
    bool HSceneSpeaking() const;
    bool HSceneHasReaction() const;
    // Her outfit changed in the H scene (the original's HSprite.OnClickCoordinateChange → ChangeCoordinateTypeAndReload):
    // her card's outfit Outfit (KKS coordinate 0..6), or with Coordinate a game coordinate card (UserData/coordinate) worn
    // as that outfit, as Studio loads one (a copy of her card is written under Saved/StreetSocial/HOutfits; hers stays as
    // it was). She opens in the background, is swapped in when ready, and the pose starts again. False: one is already
    // changing, or the scene is not ready.
    // bWithAccessories: the coordinate card's accessories too (else only its clothes: her accessories, hair made of them
    // among them, stay, as the maker loads one with accessories unticked).
    bool ChangeOutfit(int32 Outfit,const FString& Coordinate=FString(),bool bWithAccessories=false);
    // The card she was opened from and its root, for what reads it again.
    void OpenedSource(FString& Root,FString& Card) const{Root=OpenedRoot();Card=OpenedFemaleCard();}
    bool IsChangingOutfit() const {return OutfitChanging||SwappingFemale!=nullptr;}
    // A garment's next state as the original cycles it (on, half off where it has one, off), from the card she is opened
    // from; ChangeClothesStates opens her again in states a garment's half off needs (visibility alone cannot show it).
    bool ClothesTransition(int32 Kind,uint8 Out[9],FString& Why) const;
    bool ChangeClothesStates(const uint8 States[9]);
    bool bSwapClothesOnly=false; // the change in progress (or last) only opened her clothes in other states
    FString OutfitError;     // the last change's failure (empty when it worked)
    FString WornCoordinate;  // the coordinate card she wears now (empty: her card's own outfit)
    bool IsReady() const {return Ready;}
    bool IsFinished() const {return Finished;}
    FString Error;
    FString ReturnLabel=TEXT("返回人物編輯器");
    FString ReportPath;
    double AutoReturnSeconds=0;
    TFunction<void(TSharedRef<FJsonObject>)> Returned;
    UPROPERTY() TObjectPtr<UOKCharacterController> Controller;
private:
    void LoadFemale(const FString& Path,int32 Outfit=0);
#if !UE_BUILD_SHIPPING
    bool TickFeatureAudit();
    int32 FeatureAuditStage=0,FeatureAuditPair=INDEX_NONE;
    double FeatureAuditAt=0.;
#endif
    void Fail(const FString& Why);
    UPROPERTY() TObjectPtr<AKKPreviewActor> LoadingFemale;
    UPROPERTY() TObjectPtr<AKKPreviewActor> SwappingFemale; // her in the new outfit, built hidden (ChangeOutfit)
    bool OutfitChanging=false;int32 SwapOutfit=0;FString SwapCoordinate,SwapOpened,OpenedCard;uint8 SwapStates[9]{};
    bool StartSwap(int32 Outfit,const FString& Coordinate,bool bWithAccessories,const uint8* States);
    FString OpenedFemaleCard() const;FString OpenedRoot() const; // the card she is opened from now (a coordinate worn: that copy)
    void TickOutfitSwap();
    UPROPERTY() TObjectPtr<AActor> PreviousView;
    FString MalePath;
    TSharedPtr<FThreadSafeBool,ESPMode::ThreadSafe> Cancelled;
    double Started=0,ReadyAt=0;
    bool OwnController=false,Activated=false,Ready=false,Finished=false,Exiting=false,bInPlace=false;FTransform InPlaceAt;
    bool PreviousPaint=false,PreviousMouse=false,PreviousTouch=false;
    FOKBodyInteraction PreviousBodyInteraction;
    FOKBodyGesture PreviousBodyGesture;
    struct FSourceAudioState {TWeakObjectPtr<class UAudioComponent> Audio;bool Paused=false;};
    TArray<FSourceAudioState> SourceAudio;
    FVector OriginalPosition=FVector::ZeroVector;
    TSharedPtr<FJsonObject> Evidence;
    struct FSourceActorState {TWeakObjectPtr<AActor> Actor;bool Hidden=false,Collision=false,Tick=false;};
    TArray<FSourceActorState> SourceActors;
    TSharedPtr<class SWidget> PreparingOverlay;
    // The two characters of this one-to-one scene use PhysX secondary dynamics for its whole duration (solo motions
    // too, not only paired playback); released on Exit. A replaced partner is added when it appears.
    TArray<TWeakObjectPtr<class AKKPreviewActor>> PairPhysicsActors;
    void UpdatePairPhysics();
};
