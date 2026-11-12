#pragma once
#include "CoreMinimal.h"
#include "Tasks/Task.h"
#include "GameFramework/Actor.h"
#include "KKPairedPlayback.generated.h"
class AKKPreviewActor;

// A single coordinator owns both sessions' elapsed time. The roles cannot
// also advance from their own Actor Tick while this coordinator is active.
// Pair poses shown since start (ShowFrame): how often the pair really moves, apart from how often the game draws
// (ok.Anim.PairNoWait keeps the pose while the next is solved).
extern KKUNITYBUNDLE_API uint64 GKKPairFramesShown;

UCLASS()
class KKUNITYBUNDLE_API AKKPairedPlayback : public AActor
{
	GENERATED_BODY()
public:
	AKKPairedPlayback();
	bool Start(AKKPreviewActor* Female,AKKPreviewActor* Male,const FString& FemaleKey,const FString& MaleKey,
		const FString& State,const FString& FemaleMotion,const FString& MaleMotion,FString& Error);
	bool Restart(FString& Error);
	void Stop();
	// Start into another state of the pose already playing (the same two, the same motions): no settle (Restart).
	bool bSamePoseRestart=false;
	void SetPaused(bool Paused) {bPaused=Paused;}
	bool IsPaused() const {return bPaused;}
	// A worker is writing both sessions now (ok.Anim.AsyncPair): read neither until it is done.
	bool IsSolving() const {return bSolvePending&&!PendingSolve.IsCompleted();}
	// Each tick, once the frame solved in the background is on screen and before the next solve is launched: the one moment
	// a game-thread reader is sure both sessions are idle and match what is shown (between ticks a solve nearly always runs).
	FSimpleMulticastDelegate OnSessionsIdle;
	bool SetSpeed(float Value);
	float GetSpeed() const {return Speed;}
	bool bMeasureAdvance=false;
	uint64 AdvanceSamples=0;
	double AdvanceTotalMs=0.,AdvanceMaximumMs=0.;
	void ResetAdvanceMetrics(){AdvanceSamples=0;AdvanceTotalMs=AdvanceMaximumMs=0.;}
	float GetElapsed() const {return float(Elapsed);}
    const FString& GetState() const {return StateName;}
    const FString& GetFemaleClip() const {return FemaleClip;}
    const FString& GetMaleClip() const {return MaleClip;}
    const FString& GetFemaleMotion() const {return FemaleIK;}
    const FString& GetMaleMotion() const {return MaleIK;}
	bool Advance(float Delta,FString& Error);
	/** The second heroine of a 3P pose: solved and shown with the pair. Null takes her out; do that before destroying her. */
	void SetThird(AKKPreviewActor* Actor,const FString& Motion,bool bSwapped);
	AKKPreviewActor* GetThird() const {return ThirdActor.Get();}
	/** Whether this state plays through its converted OK group (ok.Anim.UseOK and Saved/OKAnim/Pairs has it). */
	bool IsUsingOK() const {return OkPlayer.IsValid();}
	/** Waits for the frame being solved in the background (ok.Anim.AsyncPair) and shows it: call before touching the
	 *  characters' sessions from outside the playback. */
	void SyncAsync(bool bDeferStreams=false);
	/** The CPU accessory streams ShowFrame left for after the next solve was launched (ok.Anim.PairSplitDisplay). */
	void FinishDeferredStreams();
	/** Walk cycle for OK pair playback (set by the OK animation module). */
	static const TArray<uint8>* WalkCycle;
	FString OkReport;
	virtual void Tick(float DeltaSeconds) override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	UPROPERTY() TObjectPtr<AKKPreviewActor> FemaleActor;
	UPROPERTY() TObjectPtr<AKKPreviewActor> MaleActor;
	UPROPERTY() TObjectPtr<AKKPreviewActor> ThirdActor;
	FString ThirdMotion;bool bThirdSwapped=false;
private:
	TSharedPtr<class FOkAnimPlayer> OkPlayer;
	FString FemaleClip,MaleClip,StateName,FemaleIK,MaleIK;
	double Elapsed=0.;float Speed=1.f;
	float VaginaRangeMin=0.f,VaginaRangeMax=0.f;
	bool bPaused=false,bActive=false,bVaginaRange=false;
	bool OldFemaleTick=false,OldMaleTick=false;
	// Both characters use PhysX secondary dynamics while the pair plays (AKKPreviewActor::AddPairPhysics).
	bool bPairPhysics=false;
	// ok.Anim.AsyncPair: the OK solve of the next frame runs on a worker while the game thread goes on; its result is
	// shown at the start of the next tick (one frame of latency).
	UE::Tasks::FTask PendingSolve;
	bool bSolvePending=false,bSolveOk=true;
	// The pending solve is the native GPU pair frame (no OK group for this state), not the OK player's: no face curves.
	bool bPendingNative=false;
	double PendingNext=0.;float PendingDelta=0.;
	// ok.Anim.PairNoWait: ticks that kept the pose while the next frame was solved, and the time they passed on.
	float SkippedDelta=0.f;int32 SkippedTicks=0;
	bool PendingReactions[2]={false,false};
	FString PendingReport;
	bool ShowFrame(float Delta,const bool Reactions[2],FString& Error,bool bDeferStreams=false);
};
