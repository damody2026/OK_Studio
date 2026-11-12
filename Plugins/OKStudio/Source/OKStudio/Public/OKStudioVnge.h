#pragma once

#include "CoreMinimal.h"
#include "UObject/ObjectMacros.h"
#include "UObject/StrongObjectPtr.h"
#include "OKStudioVnge.generated.h"

class UOKSceneDocument;
class UOKStudioGame;
class FJsonObject;
class UAudioComponent;
class UTexture2D;

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeActorTag
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Alias;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 ObjectId = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Sex = 1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString ColorHex;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Title;

	bool operator==(const FOKVngeActorTag& O) const = default;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeRegistry
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeActorTag> Actors;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeActorTag> Props;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString ActorSettingsJson;

	int32 ResolveObjectId(const FString& Alias, const UOKSceneDocument* Doc = nullptr) const;
	bool IsEmpty() const { return Actors.IsEmpty() && Props.IsEmpty() && ActorSettingsJson.IsEmpty(); }
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeFkEntry
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Bone;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Euler = FVector::ZeroVector;

	bool operator==(const FOKVngeFkEntry& O) const = default;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeIkEntry
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Effector = 0;

	/** Unity local-space metres (converted on apply). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Pos = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Euler = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bUseRotation = false;

	bool operator==(const FOKVngeIkEntry& O) const = default;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeCameraSlot
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Slot = 0;

	/** Unity orbit target (metres). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Pos = FVector::ZeroVector;

	/** Unity orbit distance vector (metres, typically (0, 0, -dist)). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Distance = FVector(0.f, 0.f, -2.f);

	/** Unity camera Euler angles (degrees). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Rotate = FVector::ZeroVector;

	/** Vertical FOV (degrees). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Fov = 23.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString WhoSay;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString WhatSay;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString AddParam;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeObjectPatch
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Alias;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 ObjectId = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bIsProp = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Visible = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasPos = false;

	/** Unity local-space position (metres). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Pos = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasRot = false;

	/** Unity local-space Euler angles (degrees). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Rot = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasScale = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Scale = FVector::OneVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 AnimGroup = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 AnimCategory = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 AnimNo = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float AnimSpeed = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float AnimTime = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeFkEntry> Fk;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeIkEntry> Ik;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 EyebrowPtn = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 EyesPtn = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float EyesOpen = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 MouthPtn = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float MouthOpen = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 HandLeft = -2;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 HandRight = -2;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 EyesLook = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 NeckLook = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Outfit = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<uint8> ClothesStates;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<uint8> AccessoriesShown;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 TearsLv = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Blush = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float NipStand = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<uint8> Fluids;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float LightIntensity = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 LightEnable = -1;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeSceneState
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Id;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString WhoSay;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString WhatSay;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString AddParam;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 LinkedCameraSlot = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeObjectPatch> Actors;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeObjectPatch> Props;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeMinistate
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Name;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Group;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString PayloadJson;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeSssData
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Version;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeCameraSlot> Cameras;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeSceneState> States;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeMinistate> Ministates;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString SssAdvJson;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString SssbJson;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 ActiveStateIndex = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 ActiveCameraSlot = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float CameraTransitionSeconds = 0.5f;

	bool IsEmpty() const
	{
		return Cameras.IsEmpty() && States.IsEmpty() && Ministates.IsEmpty() && SssAdvJson.IsEmpty() && SssbJson.IsEmpty();
	}
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeTrackKey
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Time = 0.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Ease = TEXT("Linear");

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Visible = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasPos = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Pos = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasRot = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Rot = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasScale = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Scale = FVector::OneVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasCam = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector CamPos = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector CamDst = FVector(0.f, 0.f, -2.f);

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector CamRot = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bHasValue = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Value = 0.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeFkEntry> Fk;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeIkEntry> Ik;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 EyebrowPtn = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 EyesPtn = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 MouthPtn = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float EyesOpen = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float MouthOpen = -1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 HandLeft = -2;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 HandRight = -2;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 AnimGroup = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 AnimCategory = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 AnimNo = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float AnimSpeed = -1.f;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeTrack
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString TargetAlias;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString TargetType;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 ObjectId = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeTrackKey> Keys;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeClip
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Name;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Version = 2;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float FrameLength = 60.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float FrameRate = 30.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Duration = 2.f;

	/** 0: play once, 1: loop, 2: ping-pong. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 LoopMode = 1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Speed = 1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bAutorun = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Priority = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeTrack> Tracks;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeTextEntry
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Id;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 ObjectId = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Text;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FLinearColor Color = FLinearColor::White;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FLinearColor BgColor = FLinearColor(0.f, 0.f, 0.f, 0.f);

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FLinearColor OutlineColor = FLinearColor(0.f, 0.f, 0.f, 0.85f);

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float OutlineSpread = 1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bVisible = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bInFront = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Font;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Size = 24.f;

	/** Unity TextAnchor 0..8 (4 = MiddleCenter). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Anchor = 4;

	/** 0 Left, 1 Center, 2 Right. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 Alignment = 1;

	/** Screen normalized/pixel offset (when bBindCam / !bIs3D) or Unity world position (metres) when bIs3D. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Position = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Rotation = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FVector Scale = FVector::OneVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bIs3D = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bBindCam = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bParentHide = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bWordWrap = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 WordWrapLen = 0;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeSoundSource
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Id;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Group;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Path;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString ExtractedPath;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Volume = 1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float Pitch = 1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bLoop = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bAutoPlay = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bIs3D = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 BindObjectId = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString BindActorAlias;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float MinDist = 1.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float MaxDist = 25.f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bLipSync = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString RawJson;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngePhysicsRule
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Name;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bEnabled = true;

	/** -2: active camera; > 0: scene object id. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 SourceObjectId = -2;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString SourceAlias;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	int32 TargetObjectId = -1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString TargetAlias;

	/** Trigger distance in metres. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	float TriggerDistance = 0.35f;

	/** "play_clip", "apply_state", "play_sound", "toggle_visible". */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString ActionKind = TEXT("play_clip");

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString ActionParam;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngePhysicsData
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Version;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	bool bEnabled = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngePhysicsRule> Rules;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString CollidersJson;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString RigidBodiesJson;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString TriggersJson;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString ActionsJson;

	bool IsEmpty() const
	{
		return Rules.IsEmpty() && CollidersJson.IsEmpty() && RigidBodiesJson.IsEmpty() && TriggersJson.IsEmpty() && ActionsJson.IsEmpty();
	}
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeScriptBlock
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Name;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FString> Lines;
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKVngeScriptData
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString Version;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeScriptBlock> Blocks;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FString RawJson;

	bool IsEmpty() const { return Blocks.IsEmpty() && RawJson.IsEmpty(); }
};

USTRUCT(BlueprintType)
struct OKSTUDIO_API FOKSceneVngeData
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FOKVngeRegistry Registry;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FOKVngeSssData Sss;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeClip> Clips;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeTextEntry> Texts;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	TArray<FOKVngeSoundSource> Sounds;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FOKVngePhysicsData Physics;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "VNGE")
	FOKVngeScriptData Script;

	bool IsEmpty() const
	{
		return Registry.IsEmpty() && Sss.IsEmpty() && Clips.IsEmpty() && Texts.IsEmpty()
			&& Sounds.IsEmpty() && Physics.IsEmpty() && Script.IsEmpty();
	}

	void RemapObjectIds(const TMap<int32, int32>& IdMap);
};

struct OKSTUDIO_API FOKVngeCopyMask
{
	bool bFace = true;
	bool bPose = true;
	bool bHands = true;
	bool bLook = true;
	bool bClothes = true;
	bool bKeepAccessories = false;
	bool bState = true;
	bool bStyle = true;
	bool bLocalTransform = false;
	bool bWorldTransform = false;
};

struct OKSTUDIO_API FOKVngePosePresetItem
{
	FString Name;
	FString Category;
	FString FullPath;
	bool bIsPng = false;
};

/**
 * Runtime controller for all VNGE Studio subsystems (SSS, PoseLib, VNAnime/KFA, VNText, VNSound, VNPhysics,
 * Scene Utils & Status Copy, and VNSceneScript). Owned and ticked by UOKStudioGame.
 */
class OKSTUDIO_API FOKStudioVngeRuntime
{
public:
	explicit FOKStudioVngeRuntime(UOKStudioGame* InGame);
	~FOKStudioVngeRuntime();

	static void ImportFromSceneJson(const TSharedPtr<FJsonObject>& VngeJson, const TMap<int32, int32>& KeyToId, UOKSceneDocument& Doc, TArray<FString>& OutNotes);

	void OnSceneOpened();
	void Tick(float DeltaTime);

	// --- Registry / Tracking ---
	int32 AutoRegisterSceneTags();
	bool SetObjectTag(int32 ObjectId, const FString& Alias, bool bIsProp);
	bool RemoveObjectTag(const FString& Alias, bool bIsProp);

	// --- SSS (Scene Save State & Camera Transition & Ministates) ---
	bool ApplySssState(int32 StateIndex, bool bSmoothCamera = true);
	bool ApplySssCamera(int32 CameraSlotIndex, float TransitionSeconds = -1.f);
	int32 CaptureCurrentSssState(const FString& CustomId, const FString& WhoSay, const FString& WhatSay);
	int32 CaptureCurrentSssCamera(const FString& WhoSay, const FString& WhatSay);
	bool DeleteSssState(int32 StateIndex);
	bool DeleteSssCamera(int32 CameraSlotIndex);
	bool ApplyMinistate(int32 MinistateIndex, int32 OverrideTargetId = -1);

	// --- VNAnime (KFA Multi-Clip Player, Recorder & Timeline Baker) ---
	struct FClipPlayState
	{
		bool bPlaying = false;
		float Time = 0.f;
		int32 PingPongDir = 1;
	};
	bool PlayClip(int32 ClipIndex, bool bResetTime = false);
	void PauseClip(int32 ClipIndex);
	void StopClip(int32 ClipIndex);
	void StopAllClips();
	bool ScrubClip(int32 ClipIndex, float TimeSeconds);
	const FClipPlayState* GetClipPlayState(int32 ClipIndex) const;
	int32 CreateClip(const FString& Name, float Duration = 4.f, float FrameRate = 30.f);
	bool DeleteClip(int32 ClipIndex);
	bool RecordKeyToClip(int32 ClipIndex, int32 ObjectId, float TimeSeconds);
	bool RecordCameraKeyToClip(int32 ClipIndex, float TimeSeconds);
	bool BakeClipToTimeline(int32 ClipIndex, bool bReplaceExisting = false);
	static void BakeClipToDocumentTimeline(const FOKVngeClip& Clip, UOKSceneDocument& Doc, bool bReplaceExisting);

	// --- PoseLib (Console/Lib/sss 13-category .png / .txt preset library) ---
	static FString ResolvePoseLibRoot();
	static TArray<FString> GetPoseLibCategories(const FString& RootDir = FString());
	TArray<FOKVngePosePresetItem> ScanPosePresets(const FString& Category, const FString& SearchFilter = FString());
	UTexture2D* GetPresetThumbnail(const FString& FilePath);
	bool ApplyPosePreset(const FString& FilePath, int32 TargetCharaId, FString& OutError);
	bool SavePosePreset(const FString& Category, const FString& PresetName, int32 SourceCharaId, bool bSaveAsPng, FString& OutSavedPath, FString& OutError);

	// --- VNText (2D & 3D Viewport Text) ---
	bool bShowTextOverlay = true;
	int32 AddTextEntry(const FString& InitialText, bool bIs3D = false);
	bool RemoveTextEntry(int32 Index);

	// --- VNSound (Embedded / External Sound + 3D Follow + Character LipSync) ---
	bool PlaySoundSource(int32 SourceIndex, FString& OutError);
	void StopSoundSource(int32 SourceIndex);
	void StopAllSounds();
	bool IsSoundPlaying(int32 SourceIndex) const;
	int32 AddSoundSource(const FString& FilePath, int32 BindCharaId = -1);
	bool RemoveSoundSource(int32 SourceIndex);

	// --- VNPhysics (Distance / Contact Triggers & Rules) ---
	bool TriggerPhysicsRuleNow(int32 RuleIndex);
	int32 AddPhysicsRule(int32 SourceId, int32 TargetId, float DistanceM, const FString& ActionKind, const FString& ActionParam);
	bool RemovePhysicsRule(int32 RuleIndex);

	// --- Scene Utils & Status Copy ---
	int32 StepMoveSelected(const FVector& DeltaCm, bool bLocalSpace = false);
	int32 StepRotateSelected(const FRotator& DeltaDeg, bool bLocalSpace = true);
	int32 StepScaleSelected(const FVector& ScaleMultiplier);
	int32 BatchReplaceCharacterCards(const FString& NewCardPath, bool bSelectedOnly, bool bKeepOutfitAndClothes);
	int32 SetAllCharactersBlink(int32 BlinkMode);
	int32 SyncHCharacters(int32 ReferenceCharaId, bool bSyncTransform, bool bSyncMotionAndTime);
	int32 BatchItemFk(bool bSelectedOnly, bool bResetToZero);
	bool CopyCharacterStatus(int32 SourceCharaId);
	bool HasCopiedStatus() const { return bHasClipboardStatus; }
	FString CopiedStatusSourceName() const { return ClipboardSourceName; }
	int32 PasteCharacterStatus(const TArray<int32>& TargetIds, const FOKVngeCopyMask& Mask);

	// --- VNSS (VNSceneScript Stepper & Dialogue Overlay) ---
	bool bShowDialogueOverlay = true;
	FString ActiveWhoSay;
	FString ActiveWhatSay;
	TArray<TPair<FString, FString>> ActiveChoices; // (Label, TargetBlock)
	int32 ActiveScriptBlock = 0;
	int32 ActiveScriptLine = -1;
	bool StepScriptNext();
	bool JumpScriptBlock(const FString& BlockName);
	void ResetScript();
	void ClearDialogue();

private:
	UOKStudioGame* Game = nullptr;

	// Camera smooth interpolation state
	bool bCamTransitionActive = false;
	float CamTransElapsed = 0.f;
	float CamTransDuration = 0.5f;
	FVector CamStartTarget = FVector::ZeroVector, CamEndTarget = FVector::ZeroVector;
	FVector CamStartRot = FVector::ZeroVector, CamEndRot = FVector::ZeroVector;
	FVector CamStartDist = FVector::ZeroVector, CamEndDist = FVector::ZeroVector;
	float CamStartFov = 23.f, CamEndFov = 23.f;

	// Concurrent KFA clip playback
	TMap<int32, FClipPlayState> ClipStates;
	void EvaluateClipAt(const FOKVngeClip& Clip, float TimeSec);
	void ApplyObjectPatch(const FOKVngeObjectPatch& Patch, bool bAllowMotionChange = true);
	void ApplyOrbitCameraUnity(const FVector& TargetM, const FVector& DistM, const FVector& RotDeg, float VertFovDeg);

	// Sound runtime handles
	struct FActiveSound
	{
		TWeakObjectPtr<UAudioComponent> AudioComp;
		TStrongObjectPtr<UObject> SoundWave;
		int32 LipSyncObjectId = -1;
		double StartRealTime = 0.0;
		float DurationSec = 0.f;
		bool bLoop = false;
	};
	TMap<int32, FActiveSound> ActiveSounds;

	// Physics edge-trigger tracking
	TSet<int32> InsideTriggerRules;

	// PoseLib thumbnail cache
	TMap<FString, TStrongObjectPtr<UTexture2D>> PresetThumbnails;

	// Character status clipboard
	bool bHasClipboardStatus = false;
	FString ClipboardSourceName;
	int32 ClipboardSourceId = -1;
	FTransform ClipboardLocalTransform = FTransform::Identity;
	FTransform ClipboardWorldTransform = FTransform::Identity;
	TSharedPtr<FJsonObject> ClipboardCharJson;

	void ExecuteScriptLine(const FString& Line);
};
