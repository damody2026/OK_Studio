#pragma once
#include "CoreMinimal.h"

class AActor;
class USceneComponent;
class UProceduralMeshComponent;
class UStaticMeshComponent;
class UMaterialInstanceDynamic;

// Her tears (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md P2; user 2026-11-02: not the original's tear meshes, Unreal's own):
// a bead running down her cheek over her skin as she is posed (FOkSession::FaceTearPath), stopping and going on, and
// behind it a wet streak with a bright line along it (it blooms, the way light shines off water) that dries away.
// Each tear hangs on her head bone, so it moves with her head.
struct FOKTears{
	// Way: world cm points down her face and her skin's normal at each, now; Attach / Bone: her head bone.
	void Add(AActor* Owner,USceneComponent* Attach,FName Bone,const TArray<FVector>& WorldPoints,const TArray<FVector>& WorldNormals);
	// Eye: the camera, for the bead's highlight.
	void Tick(float Dt,const FVector& Eye);
	void Reset();
	int32 Num() const{return Tears.Num();}
private:
	struct FTear{
		TWeakObjectPtr<UProceduralMeshComponent> Streak,Shine;
		TWeakObjectPtr<UStaticMeshComponent> Bead,Glint;
		TWeakObjectPtr<UMaterialInstanceDynamic> Wet,Gleam,Drop,Spark;
		TArray<FVector> P,N; // the way, in the head bone's space
		float Front=0.f,Age=0.f,Pause=0.f,Speed=0.f,Ended=-1.f;
	};
	UMaterialInstanceDynamic* Tinted(AActor* Owner,const FLinearColor& Tint) const;
	void Draw(FTear& T,float Alpha,float ShineAlpha);
	TArray<FTear> Tears;
};
