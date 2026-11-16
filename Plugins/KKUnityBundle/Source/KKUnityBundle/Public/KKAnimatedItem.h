// A library prefab with an Animator of its own (the H caress hands, fingers, tongue, toys), drawn by its own preview
// actor and hung on a bone of a character the way Unity's SetParent(bone, worldPositionStays: false) keeps the prefab
// root's local transform under it (HandCtrl.SetItem).
#pragma once

#include "CoreMinimal.h"
#include "KKRustExtract.h"
#include "UObject/WeakObjectPtrTemplates.h"

class AKKPreviewActor;
class UWorld;

class KKUNITYBUNDLE_API FKKAnimatedItem
{
public:
	FKKAnimatedItem() = default;
	~FKKAnimatedItem() { Destroy(); }
	FKKAnimatedItem(const FKKAnimatedItem&) = delete;
	FKKAnimatedItem& operator=(const FKKAnimatedItem&) = delete;

	/** Opens the library model's prefab and spawns the actor that draws it (hidden until it is posed). AnimRoot: the
	 *  animation root its controller's states are read from (the base library's `paired`). */
	bool Spawn(UWorld* World, const FString& Library, const FString& Model, const FString& Prefab, const FString& AnimRoot, FString& OutError);
	void Destroy();
	bool IsSpawned() const { return Actor.IsValid() && Item.IsOpen(); }
	AKKPreviewActor* GetActor() const { return Actor.Get(); }
	const FString& PrefabName() const { return Prefab; }

	/** Hangs it on Bone of Owner's session skeleton (any transform of it, an H collider bone too); None takes it off. */
	void Attach(AKKPreviewActor* Owner, const FString& Bone);
	/** Plays State (a key of the animation root) from its start; Seconds of it are advanced by Tick. */
	void Play(const FString& State);
	const FString& CurrentState() const { return State; }
	/** Shown or not; hidden it is neither posed nor placed. */
	void SetVisible(bool bVisible);
	bool IsVisible() const { return bShown; }
	/** Advances its clock by Delta * Speed, poses it with the controller's float parameters and places it on its bone. */
	bool Tick(float Delta, float Speed, const TMap<FString, float>& Values);

private:
	bool Place();
	TWeakObjectPtr<AKKPreviewActor> Actor;
	TWeakObjectPtr<AKKPreviewActor> Owner;
	FOkSkinnedItem Item;
	FString Prefab, AnimRoot, Bone, State;
	float Seconds = 0.f;
	bool bShown = false;
	bool bPoseLogged = false;
};
