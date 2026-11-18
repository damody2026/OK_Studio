// A library prefab with an Animator of its own (the H caress hands, fingers, tongue, toys), drawn by its own preview
// actor and hung on a bone of a character the way Unity's SetParent(bone, worldPositionStays: false) keeps the prefab
// root's local transform under it (HandCtrl.SetItem).
#pragma once

#include "CoreMinimal.h"
#include "KKRustExtract.h"
#include "UObject/WeakObjectPtrTemplates.h"

class AKKPreviewActor;
class UWorld;

/** What FKKAnimatedItem::Spawn opens before it touches the world (the session that draws the prefab and the posed item):
 *  native work only, so it can be done on a worker ahead of time (FKKAnimatedItem::Open) and spawned later. */
struct KKUNITYBUNDLE_API FKKAnimatedItemSource
{
	FOkSession Session;
	FOkSkinnedItem Item;
	FString Error;
	bool bOpen = false;
};

class KKUNITYBUNDLE_API FKKAnimatedItem
{
public:
	FKKAnimatedItem() = default;
	~FKKAnimatedItem() { Destroy(); }
	FKKAnimatedItem(const FKKAnimatedItem&) = delete;
	FKKAnimatedItem& operator=(const FKKAnimatedItem&) = delete;

	/** Opens the library model's prefab and spawns the actor that draws it (hidden until it is posed). AnimRoot: the
	 *  animation root its controller's states are read from (the base library's `paired`). Colors: its item colours
	 *  (sRGB _Color.._Color4; alpha < 0 keeps the model's), as HandCtrl gives the caressing hand his skin colour. */
	bool Spawn(UWorld* World, const FString& Library, const FString& Model, const FString& Prefab, const FString& AnimRoot, FString& OutError, const TArray<FLinearColor>& Colors = TArray<FLinearColor>());
	/** The native half of Spawn (any thread): opens the prefab's session and item. */
	static void Open(FKKAnimatedItemSource& Source, const FString& Library, const FString& Model, const FString& Prefab);
	/** The game-thread half of Spawn: spawns the actor from an opened Source (its session and item are taken). */
	bool Spawn(UWorld* World, FKKAnimatedItemSource& Source, const FString& Prefab, const FString& AnimRoot, FString& OutError, const TArray<FLinearColor>& Colors = TArray<FLinearColor>());
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
