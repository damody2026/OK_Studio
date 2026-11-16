#include "KKAnimatedItem.h"

#include "Camera/CameraComponent.h"
#include "Components/PrimitiveComponent.h"
#include "Materials/MaterialInterface.h"
#include "Engine/World.h"
#include "KKPreviewActor.h"
#include "KKExactSkinning.h"
#include "Components/PoseableMeshComponent.h"
#include "ok_extract.h"

bool FKKAnimatedItem::Spawn(UWorld* World, const FString& Library, const FString& Model, const FString& InPrefab, const FString& InAnimRoot, FString& OutError)
{
	Destroy();
	if (!World) { OutError = TEXT("no world"); return false; }
	FOkSession Session;
	if (!Session.OpenOkModel(Library, Model, InPrefab, false, OutError)) return false;
	if (!Item.Open(Library, Model, InPrefab, OutError)) return false;
	FActorSpawnParameters Params;
	Params.ObjectFlags = RF_Transient;
	AKKPreviewActor* A = World->SpawnActor<AKKPreviewActor>(FVector::ZeroVector, FRotator::ZeroRotator, Params);
	if (!A) { Item.Close(); OutError = TEXT("item actor not spawned"); return false; }
	// Posed here, not by the actor's own clock (it has no animation of its own).
	A->SetActorTickEnabled(false);
	A->bSceneDrivenPose = true;
	// Drawn as an item (the game's own item program, toon shadow and _ShadowColor), as OK Studio draws its items.
	A->bStudioItemShading = true;
	A->CharacterDisplayShadowsOverride = false;
	A->Session = MoveTemp(Session);
	if (!A->LoadSession(OutError)) { A->Destroy(); Item.Close(); return false; }
	TArray<UPrimitiveComponent*> Prims;
	A->GetComponents(Prims);
	for (UPrimitiveComponent* P : Prims)
	{
		const UMaterialInterface* M = P->GetNumMaterials() > 0 ? P->GetMaterial(0) : nullptr;
		UE_LOG(LogTemp, Display, TEXT("Animated item %s: %s %s material %s%s"), *InPrefab, *P->GetClass()->GetName(), *P->GetName(), M ? *M->GetName() : TEXT("-"), P->IsVisible() ? TEXT("") : TEXT(" (hidden)"));
	}
	// The preview actor's own camera is not part of the scene.
	TArray<UCameraComponent*> Cameras;
	A->GetComponents(Cameras);
	for (UCameraComponent* Cam : Cameras) Cam->DestroyComponent();
	A->SetActorHiddenInGame(true);
	Actor = A;
	Prefab = InPrefab;
	AnimRoot = InAnimRoot;
	bShown = false;
	return true;
}

void FKKAnimatedItem::Destroy()
{
	if (AKKPreviewActor* A = Actor.Get()) A->Destroy();
	Actor.Reset();
	Owner.Reset();
	Item.Close();
	State.Reset();
	Bone.Reset();
	bShown = false;
}

void FKKAnimatedItem::Attach(AKKPreviewActor* InOwner, const FString& InBone)
{
	Owner = InOwner;
	Bone = InBone;
}

void FKKAnimatedItem::Play(const FString& InState)
{
	if (InState != State) { State = InState; Seconds = 0.f; bPoseLogged = false; }
}

void FKKAnimatedItem::SetVisible(bool bVisible)
{
	bShown = bVisible;
	if (AKKPreviewActor* A = Actor.Get()) A->SetActorHiddenInGame(!bVisible);
}

bool FKKAnimatedItem::Place()
{
	AKKPreviewActor* A = Actor.Get();
	AKKPreviewActor* O = Owner.Get();
	float M[16];
	if (!A || !O || Bone.IsEmpty() || !O->Session.BoneWorldMatrix(Bone, M)) return false;
	// The bone's Unity matrix (her session's space) in Unreal's axes, as her parts are drawn: under her body mesh, which
	// carries the offset the H scene's alignment gives her parts (UOKHScenePanel::MoveParts), else under her actor.
	const USceneComponent* Frame = O->BodySkel ? static_cast<const USceneComponent*>(O->BodySkel) : O->GetRootComponent();
	A->SetActorTransform(FTransform(OKSkinPaletteToUnreal(M)) * (Frame ? Frame->GetComponentTransform() : O->GetActorTransform()));
	return true;
}

bool FKKAnimatedItem::Tick(float Delta, float Speed, const TMap<FString, float>& Values)
{
	AKKPreviewActor* A = Actor.Get();
	if (!A || !bShown || State.IsEmpty() || !Item.IsOpen()) return false;
	Seconds += FMath::Max(0.f, Delta * Speed);
	const int32 Written = Item.PoseSession(A->Session, AnimRoot, State, Seconds, Values);
	if (Written <= 0) { if (!bPoseLogged) { bPoseLogged = true; UE_LOG(LogTemp, Warning, TEXT("Animated item %s: %s wrote no parts"), *Prefab, *State); } return false; }
	A->RefreshRuntimeAccessories();
	const bool bPlaced = Place();
	if (!bPoseLogged)
	{
		bPoseLogged = true;
		const FBox Box = A->GetComponentsBoundingBox(true);
		AKKPreviewActor* O = Owner.Get();
		// Where the posed vertices should be (their centre through the placement) against where they are drawn.
		OkMeshView View;
		FMemory::Memzero(View);
		if (A->Session.PartAt(0, View) && View.positions && View.n_verts > 0)
		{
			FVector Sum = FVector::ZeroVector;
			for (int32 V = 0; V < View.n_verts; ++V) Sum += FVector(View.positions[V * 3], View.positions[V * 3 + 1], View.positions[V * 3 + 2]);
			const FVector Want = A->GetActorTransform().TransformPosition(AKKPreviewActor::UnityToActorLocal(Sum / View.n_verts));
			UE_LOG(LogTemp, Display, TEXT("Animated item %s: vertex centre should be %s, drawn bounds centre %s"), *Prefab, *Want.ToString(), *Box.GetCenter().ToString());
		}
		UE_LOG(LogTemp, Display, TEXT("Animated item %s: %s wrote %d parts, %s on %s at %s (bounds %s, owner at %s)"), *Prefab, *State, Written,
			bPlaced ? TEXT("placed") : TEXT("NOT placed"), *Bone, *A->GetActorLocation().ToString(), *Box.ToString(), O ? *O->GetActorLocation().ToString() : TEXT("-"));
	}
	return bPlaced;
}
