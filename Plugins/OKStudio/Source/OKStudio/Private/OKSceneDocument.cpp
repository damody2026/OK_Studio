#include "OKSceneDocument.h"
#include "Engine/Scene.h"
#include "OKStudioCatalog.h"
#include "OKStudioPost.h"
#include "OKStudioBloom.h"
#include "ok_extract.h"
#include "Dom/JsonObject.h"
#include "JsonObjectConverter.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

int32 UOKSceneDocument::AddObject(EOKSceneObjectKind Kind, const FString& Name, int32 Parent)
{
	if (Parent >= 0 && !Find(Parent)) Parent = -1;
	FOKSceneObject& Object = Objects.AddDefaulted_GetRef();
	Object.Id = NextId++;
	Object.Parent = Parent;
	Object.Kind = Kind;
	Object.Name = Name.IsEmpty() ? FString::Printf(TEXT("%s %d"), *StaticEnum<EOKSceneObjectKind>()->GetNameStringByValue(int64(Kind)), Object.Id) : Name;
	const int32 Id = Object.Id;
	NotifyChanged();
	return Id;
}

bool UOKSceneDocument::RemoveObject(int32 Id)
{
	if (!Find(Id)) return false;
	TArray<int32> Doomed = { Id };
	for (int32 I = 0; I < Doomed.Num(); ++I) Doomed.Append(Children(Doomed[I]));
	Objects.RemoveAll([&](const FOKSceneObject& O) { return Doomed.Contains(O.Id); });
	if (Doomed.Contains(ActiveCamera)) ActiveCamera = -1;
	NotifyChanged();
	return true;
}

bool UOKSceneDocument::Reparent(int32 Id, int32 NewParent)
{
	FOKSceneObject* Object = Find(Id);
	if (!Object || (NewParent >= 0 && !Find(NewParent))) return false;
	for (int32 P = NewParent; P >= 0; P = Find(P) ? Find(P)->Parent : -1) if (P == Id) return false;
	const FTransform World = WorldTransform(Id);
	const FTransform ParentWorld = ChildFrame(NewParent);
	Object = Find(Id);
	Object->Parent = NewParent;
	Object->AttachBone.Reset();
	Object->Transform = World.GetRelativeTransform(ParentWorld);
	// World scale is the object's own (WorldTransform): moving it under another parent keeps its size.
	Object->Transform.SetScale3D(World.GetScale3D());
	NotifyChanged();
	return true;
}

int32 UOKSceneDocument::Duplicate(int32 Id)
{
	if (!Find(Id)) return -1;
	TMap<int32, int32> IdMap;
	TArray<int32> Order = { Id };
	for (int32 I = 0; I < Order.Num(); ++I) Order.Append(Children(Order[I]));
	for (int32 Old : Order)
	{
		FOKSceneObject Copy = *Find(Old);
		Copy.Id = NextId++;
		Copy.Parent = Old == Id ? Copy.Parent : IdMap.FindChecked(Copy.Parent);
		if (Old == Id) Copy.Name += TEXT(" copy");
		IdMap.Add(Old, Copy.Id);
		Objects.Add(Copy);
	}
	// The copies keep their timeline keys, as a copy and paste does.
	for (int32 T = 0, Count = Tracks.Num(); T < Count; ++T)
		if (const int32* To = IdMap.Find(Tracks[T].ObjectId)) { FOKSceneTrack Track = Tracks[T]; Track.ObjectId = *To; Tracks.Add(MoveTemp(Track)); }
	for (int32 T = 0, Count = TimelineTracks.Num(); T < Count; ++T)
		if (const int32* To = IdMap.Find(TimelineTracks[T].ObjectId)) { FOKSceneTimelineTrack Tl = TimelineTracks[T]; Tl.ObjectId = *To; TimelineTracks.Add(MoveTemp(Tl)); }
	for (int32 CIdx = 0, Count = Constraints.Num(); CIdx < Count; ++CIdx)
	{
		const FOKSceneConstraint& Con = Constraints[CIdx];
		const int32* NewChild = IdMap.Find(Con.ChildId);
		const int32* NewParent = Con.ParentId == -2 ? nullptr : IdMap.Find(Con.ParentId);
		if (NewChild && (Con.ParentId == -2 || NewParent))
		{
			FOKSceneConstraint Copy = Con;
			Copy.ChildId = *NewChild;
			if (NewParent) Copy.ParentId = *NewParent;
			Constraints.Add(MoveTemp(Copy));
		}
	}
	NotifyChanged();
	return IdMap[Id];
}

FOKSceneObject* UOKSceneDocument::Find(int32 Id)
{
	if (FindScopes > 0) return const_cast<FOKSceneObject*>(FindIndexed(Id));
	return Objects.FindByPredicate([Id](const FOKSceneObject& O) { return O.Id == Id; });
}

const FOKSceneObject* UOKSceneDocument::Find(int32 Id) const
{
	if (FindScopes > 0) return FindIndexed(Id);
	return Objects.FindByPredicate([Id](const FOKSceneObject& O) { return O.Id == Id; });
}

const FOKSceneObject* UOKSceneDocument::FindIndexed(int32 Id) const
{
	// The index is built when a scope starts and belongs to that array: a resized or moved array (an object added or
	// removed inside the scope) or an entry whose object no longer carries its id is indexed again. An id absent from a
	// fresh index is absent (a root's parent, -1, is looked up for every object).
	auto Rebuild = [this]
	{
		FindIndex.Reset();
		FindIndex.Reserve(Objects.Num());
		for (int32 I = 0; I < Objects.Num(); ++I) FindIndex.Add(Objects[I].Id, I);
		FindIndexData = Objects.GetData();
		FindIndexNum = Objects.Num();
	};
	if (FindIndexData != Objects.GetData() || FindIndexNum != Objects.Num()) Rebuild();
	const int32* At = FindIndex.Find(Id);
	if (At && (!Objects.IsValidIndex(*At) || Objects[*At].Id != Id)) { Rebuild(); At = FindIndex.Find(Id); }
	return At && Objects.IsValidIndex(*At) && Objects[*At].Id == Id ? &Objects[*At] : nullptr;
}

UOKSceneDocument::FFindScope::FFindScope(const UOKSceneDocument* InDocument) : Document(InDocument)
{
	// OK_STUDIO_FIND_INDEX=0 (diagnostic): scan as before, to measure what the index saves.
	static const bool bOff = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_STUDIO_FIND_INDEX")) == TEXT("0");
	if (!Document || bOff) { Document = nullptr; return; }
	if (Document->FindScopes++ == 0) Document->FindIndexNum = -1;
}

UOKSceneDocument::FFindScope::~FFindScope()
{
	if (Document) --Document->FindScopes;
}

TArray<int32> UOKSceneDocument::Children(int32 Parent) const
{
	TArray<int32> Out;
	for (const FOKSceneObject& O : Objects) if (O.Parent == Parent) Out.Add(O.Id);
	return Out;
}

FTransform UOKSceneDocument::WorldTransform(int32 Id) const
{
	// The chain from the scene root down (bounded: a corrupt file with a parent cycle must not hang).
	TArray<const FOKSceneObject*, TInlineAllocator<16>> Chain;
	for (int32 Steps = 0, Cur = Id; Cur >= 0 && Steps < UOKSceneDocument::MaxDepth; ++Steps)
	{
		const FOKSceneObject* O = Find(Cur);
		if (!O) break;
		Chain.Add(O);
		Cur = O->Parent;
	}
	FTransform World = FTransform::Identity;
	for (int32 K = Chain.Num() - 1; K >= 0; --K)
	{
		const FOKSceneObject* O = Chain[K];
		const FOKSceneObject* P = Chain.IsValidIndex(K + 1) ? Chain[K + 1] : nullptr;
		FTransform Frame = World;
		if (P && P->Kind == EOKSceneObjectKind::Item) Frame = FOKStudioCatalog::Get().AnimatedItemChildPoint(P->Item.Group, P->Item.Category, P->Item.No, P->Item.AnimePattern, P->Item.AnimeTime, ItemAnimationSeconds, P->Item.AnimeSpeed) * Frame;
		FTransform Bone;
		if (P && P->Kind == EOKSceneObjectKind::Character && !O->AttachBone.IsEmpty() && BoneFrame && BoneFrame(P->Id, O->AttachBone, Bone)) Frame = Bone * Frame;
		World = O->Transform * Frame;
		// Studio's GuideObject keeps every object's world scale at its own (localScale = localScale / lossyScale *
		// changeAmount.scale each frame): a parent's scale moves its children (their positions scale with it) but does
		// not size them. A child under a 57x stretched cylinder keeps its own size.
		World.SetScale3D(O->Transform.GetScale3D());
	}
	return World;
}

FTransform UOKSceneDocument::ChildFrame(int32 Parent) const
{
	const FOKSceneObject* P = Find(Parent);
	if (!P) return FTransform::Identity;
	const FTransform World = WorldTransform(Parent);
	return P->Kind == EOKSceneObjectKind::Item ? FOKStudioCatalog::Get().AnimatedItemChildPoint(P->Item.Group, P->Item.Category, P->Item.No, P->Item.AnimePattern, P->Item.AnimeTime, ItemAnimationSeconds, P->Item.AnimeSpeed) * World : World;
}

FTransform UOKSceneDocument::ParentFrame(int32 Id) const
{
	const FOKSceneObject* O = Find(Id);
	if (!O) return FTransform::Identity;
	const FTransform Frame = ChildFrame(O->Parent);
	const FOKSceneObject* P = Find(O->Parent);
	FTransform Bone;
	if (P && P->Kind == EOKSceneObjectKind::Character && !O->AttachBone.IsEmpty() && BoneFrame && BoneFrame(P->Id, O->AttachBone, Bone)) return Bone * Frame;
	return Frame;
}

bool UOKSceneDocument::IsShown(int32 Id) const
{
	for (int32 Steps = 0, Cur = Id; Cur >= 0 && Steps < UOKSceneDocument::MaxDepth; ++Steps)
	{
		const FOKSceneObject* O = Find(Cur);
		if (!O) break;
		if (!O->bVisible) return false;
		Cur = O->Parent;
	}
	return true;
}

FString UOKSceneDocument::ToJson() const
{
	TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
	Root->SetStringField(TEXT("format"), TEXT("okscene"));
	const bool bMotionKeys = Tracks.ContainsByPredicate([](const FOKSceneTrack& T) { return T.Keys.ContainsByPredicate([](const FOKSceneKey& K) { return K.AnimNo >= 0; }); });
	const bool bFades = Tracks.ContainsByPredicate([](const FOKSceneTrack& T) { return T.Keys.ContainsByPredicate([](const FOKSceneKey& K) { return K.AnimBlend > 0.f; }); });
	const bool bClips = Objects.ContainsByPredicate([](const FOKSceneObject& O) { return !O.Character.VoiceClips.IsEmpty(); });
	const bool bOrbits = Tracks.ContainsByPredicate([](const FOKSceneTrack& T) { return T.bOrbitPath; });
	Root->SetNumberField(TEXT("version"), bFades || bClips || bOrbits ? 3 : bMotionKeys ? 2 : 1);
	Root->SetNumberField(TEXT("active_camera"), ActiveCamera);
	Root->SetNumberField(TEXT("next_id"), NextId);
	Root->SetNumberField(TEXT("map"), Map);
	if (!MapTransform.Equals(FTransform::Identity)) Root->SetStringField(TEXT("map_transform"), MapTransform.ToString());
	Root->SetNumberField(TEXT("duration"), Duration);
	if (Playhead > 0.f) Root->SetNumberField(TEXT("playhead"), Playhead);
	if (!SoundFile.IsEmpty()) Root->SetStringField(TEXT("sound_file"), SoundFile);
	if (!FMath::IsNearlyZero(SoundDelay)) Root->SetNumberField(TEXT("sound_delay"), SoundDelay);
	if (TSharedPtr<FJsonObject> PostJson = FJsonObjectConverter::UStructToJsonObject(Post)) Root->SetObjectField(TEXT("post"), PostJson);
	if (TSharedPtr<FJsonObject> SoundJson = FJsonObjectConverter::UStructToJsonObject(Sound)) Root->SetObjectField(TEXT("sound"), SoundJson);
	TArray<TSharedPtr<FJsonValue>> TrackJson;
	for (const FOKSceneTrack& T : Tracks) if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(T)) TrackJson.Add(MakeShared<FJsonValueObject>(J));
	Root->SetArrayField(TEXT("tracks"), TrackJson);
	if (!Constraints.IsEmpty())
	{
		TArray<TSharedPtr<FJsonValue>> ConJson;
		for (const FOKSceneConstraint& C : Constraints) if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(C)) ConJson.Add(MakeShared<FJsonValueObject>(J));
		Root->SetArrayField(TEXT("constraints"), ConJson);
	}
	if (!TimelineTracks.IsEmpty())
	{
		TArray<TSharedPtr<FJsonValue>> TlJson;
		for (const FOKSceneTimelineTrack& T : TimelineTracks) if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(T)) TlJson.Add(MakeShared<FJsonValueObject>(J));
		Root->SetArrayField(TEXT("timeline_tracks"), TlJson);
	}
	if (bLoopTimeline) Root->SetBoolField(TEXT("loop_timeline"), true);
	if (!FMath::IsNearlyEqual(TimelineSpeed, 1.f, 1e-4f)) Root->SetNumberField(TEXT("timeline_speed"), TimelineSpeed);
	if (TimelineDivisions != 10) Root->SetNumberField(TEXT("timeline_divisions"), TimelineDivisions);
	if (!FMath::IsNearlyEqual(TimelineBlockLength, 1.f, 1e-4f)) Root->SetNumberField(TEXT("timeline_block_length"), TimelineBlockLength);
	if (!Vnge.IsEmpty())
		if (TSharedPtr<FJsonObject> VngeJson = FJsonObjectConverter::UStructToJsonObject(Vnge)) Root->SetObjectField(TEXT("vnge"), VngeJson);
	if (StudioCameraId >= 0)
	{
		Root->SetNumberField(TEXT("studio_camera_id"), StudioCameraId);
		Root->SetStringField(TEXT("studio_camera_orbit_target"), StudioCameraOrbitTarget.ToString());
		Root->SetStringField(TEXT("studio_camera_orbit_rot"), StudioCameraOrbitRot.ToString());
		Root->SetStringField(TEXT("studio_camera_orbit_dist"), StudioCameraOrbitDist.ToString());
	}
	if (CharaLightId >= 0) Root->SetNumberField(TEXT("chara_light_id"), CharaLightId);
	if (bLinkCharaLightToCamera)
	{
		Root->SetBoolField(TEXT("link_chara_light"), true);
		Root->SetStringField(TEXT("linked_light_base"), LinkedLightBase.ToString());
		Root->SetStringField(TEXT("linked_camera_base"), LinkedCameraBase.ToString());
	}
	if (SavedView.bSet) if (TSharedPtr<FJsonObject> View = FJsonObjectConverter::UStructToJsonObject(SavedView)) Root->SetObjectField(TEXT("view"), View);
	if (Bookmarks.ContainsByPredicate([](const FOKSceneBookmark& B) { return B.bSet; }))
	{
		TArray<TSharedPtr<FJsonValue>> MarkJson;
		for (const FOKSceneBookmark& B : Bookmarks) if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(B)) MarkJson.Add(MakeShared<FJsonValueObject>(J));
		Root->SetArrayField(TEXT("bookmarks"), MarkJson);
	}
	TArray<TSharedPtr<FJsonValue>> Items;
	for (const FOKSceneObject& O : Objects)
	{
		TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(O);
		if (!J) continue;
		// Only the payload of the object's kind is written.
		if (O.Kind != EOKSceneObjectKind::Character) J->RemoveField(TEXT("character"));
		if (O.Kind != EOKSceneObjectKind::Item) J->RemoveField(TEXT("item"));
		if (O.Kind != EOKSceneObjectKind::Light) J->RemoveField(TEXT("light"));
		if (O.Kind != EOKSceneObjectKind::Camera) J->RemoveField(TEXT("camera"));
		if (O.Kind != EOKSceneObjectKind::Effect) J->RemoveField(TEXT("effect"));
		if (O.LiveMaterialEdits.IsEmpty()) J->RemoveField(TEXT("liveMaterialEdits"));
		Items.Add(MakeShared<FJsonValueObject>(J));
	}
	Root->SetArrayField(TEXT("objects"), Items);
	FString Out;
	const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Out);
	FJsonSerializer::Serialize(Root, Writer);
	return Out;
}

bool UOKSceneDocument::FromJson(const FString& Json, FString& OutError)
{
    ItemAnimationSeconds = 0.f;
	TSharedPtr<FJsonObject> Root;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json), Root) || !Root) { OutError = TEXT("not JSON"); return false; }
	if (Root->GetStringField(TEXT("format")) != TEXT("okscene")) { OutError = TEXT("not an .okscene file"); return false; }
	const int32 Version = int32(Root->GetNumberField(TEXT("version")));
	if (Version < 1 || Version > FormatVersion) { OutError = FString::Printf(TEXT("unsupported .okscene version %d"), Version); return false; }
	TArray<FOKSceneObject> Loaded;
	const TArray<TSharedPtr<FJsonValue>>* Items = nullptr;
	if (Root->TryGetArrayField(TEXT("objects"), Items))
	{
		for (const TSharedPtr<FJsonValue>& V : *Items)
		{
			FOKSceneObject O;
			if (!V->AsObject() || !FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &O)) { OutError = TEXT("bad scene object"); return false; }
			Loaded.Add(O);
		}
	}
	TSet<int32> Ids;
	int32 MaxId = 0;
	for (const FOKSceneObject& O : Loaded)
	{
		if (O.Id <= 0 || Ids.Contains(O.Id)) { OutError = FString::Printf(TEXT("duplicate or invalid object id %d"), O.Id); return false; }
		Ids.Add(O.Id);
		MaxId = FMath::Max(MaxId, O.Id);
	}
	for (FOKSceneObject& O : Loaded) if (O.Parent >= 0 && !Ids.Contains(O.Parent)) O.Parent = -1;
	// An imported particle item takes the library's best effect for it now (the library may have gained one since).
	for (FOKSceneObject& O : Loaded)
		if (O.Kind == EOKSceneObjectKind::Effect && !O.Effect.Source.IsEmpty())
			if (const FOKStudioEffect* Best = FOKStudioCatalog::Get().EffectForParticleText(O.Effect.Source); Best && Best->Id != O.Effect.Effect)
			{
				UE_LOG(LogTemp, Display, TEXT("OK scene: effect %d (%s) now %s"), O.Id, *O.Effect.Source, *Best->Id);
				O.Effect.Effect = Best->Id;
			}
	Objects = MoveTemp(Loaded);
	ActiveCamera = Root->HasField(TEXT("active_camera")) ? int32(Root->GetNumberField(TEXT("active_camera"))) : -1;
	Map = Root->HasField(TEXT("map")) ? int32(Root->GetNumberField(TEXT("map"))) : -1;
	MapTransform = FTransform::Identity;
	FString MapTransformText;
	if (Root->TryGetStringField(TEXT("map_transform"), MapTransformText)) MapTransform.InitFromString(MapTransformText);
	Duration = Root->HasField(TEXT("duration")) ? float(Root->GetNumberField(TEXT("duration"))) : 10.f;
	Playhead = Root->HasField(TEXT("playhead")) ? float(Root->GetNumberField(TEXT("playhead"))) : 0.f;
	SoundFile = Root->HasField(TEXT("sound_file")) ? Root->GetStringField(TEXT("sound_file")) : FString();
	SoundDelay = Root->HasField(TEXT("sound_delay")) ? float(Root->GetNumberField(TEXT("sound_delay"))) : 0.f;
	Post = FOKScenePost();
	const TSharedPtr<FJsonObject>* PostJson = nullptr;
	if (Root->TryGetObjectField(TEXT("post"), PostJson)) FJsonObjectConverter::JsonObjectToUStruct(PostJson->ToSharedRef(), &Post);
	Sound = FOKSceneSound();
	const TSharedPtr<FJsonObject>* SoundJson = nullptr;
	if (Root->TryGetObjectField(TEXT("sound"), SoundJson)) FJsonObjectConverter::JsonObjectToUStruct(SoundJson->ToSharedRef(), &Sound);
	Tracks.Reset();
	const TArray<TSharedPtr<FJsonValue>>* TrackJson = nullptr;
	if (Root->TryGetArrayField(TEXT("tracks"), TrackJson))
		for (const TSharedPtr<FJsonValue>& V : *TrackJson)
		{
			FOKSceneTrack T;
			if (V->AsObject() && FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &T) && (Ids.Contains(T.ObjectId) || T.ObjectId == SceneTrackId)) Tracks.Add(MoveTemp(T));
		}
	Bookmarks.Reset();
	SavedView = FOKSceneBookmark();
	Constraints.Reset();
	const TArray<TSharedPtr<FJsonValue>>* ConJson = nullptr;
	if (Root->TryGetArrayField(TEXT("constraints"), ConJson))
		for (const TSharedPtr<FJsonValue>& V : *ConJson)
		{
			FOKSceneConstraint C;
			if (V->AsObject() && FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &C)
				&& (C.ParentId == -2 || Ids.Contains(C.ParentId)) && Ids.Contains(C.ChildId))
				Constraints.Add(MoveTemp(C));
		}
	TimelineTracks.Reset();
	const TArray<TSharedPtr<FJsonValue>>* TlJson = nullptr;
	if (Root->TryGetArrayField(TEXT("timeline_tracks"), TlJson))
		for (const TSharedPtr<FJsonValue>& V : *TlJson)
		{
			FOKSceneTimelineTrack T;
			if (V->AsObject() && FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &T)
				&& (T.ObjectId < 0 || Ids.Contains(T.ObjectId)))
				TimelineTracks.Add(MoveTemp(T));
		}
	bLoopTimeline = false;
	Root->TryGetBoolField(TEXT("loop_timeline"), bLoopTimeline);
	TimelineSpeed = Root->HasField(TEXT("timeline_speed")) ? FMath::Max(0.01f, float(Root->GetNumberField(TEXT("timeline_speed")))) : 1.f;
	TimelineDivisions = Root->HasField(TEXT("timeline_divisions")) ? FMath::Max(1, int32(Root->GetNumberField(TEXT("timeline_divisions")))) : 10;
	TimelineBlockLength = Root->HasField(TEXT("timeline_block_length")) ? FMath::Max(0.01f, float(Root->GetNumberField(TEXT("timeline_block_length")))) : 1.f;
	LastTimelineScale = 1.f;
	Vnge = FOKSceneVngeData();
	const TSharedPtr<FJsonObject>* VngeJson = nullptr;
	if (Root->TryGetObjectField(TEXT("vnge"), VngeJson) && VngeJson && VngeJson->IsValid())
		FJsonObjectConverter::JsonObjectToUStruct(VngeJson->ToSharedRef(), &Vnge);
	StudioCameraId = Root->HasField(TEXT("studio_camera_id")) ? int32(Root->GetNumberField(TEXT("studio_camera_id"))) : -1;
	StudioCameraOrbitTarget = FVector::ZeroVector;
	StudioCameraOrbitRot = FVector::ZeroVector;
	StudioCameraOrbitDist = FVector::ZeroVector;
	FString OrbitStr;
	if (Root->TryGetStringField(TEXT("studio_camera_orbit_target"), OrbitStr)) StudioCameraOrbitTarget.InitFromString(OrbitStr);
	if (Root->TryGetStringField(TEXT("studio_camera_orbit_rot"), OrbitStr)) StudioCameraOrbitRot.InitFromString(OrbitStr);
	if (Root->TryGetStringField(TEXT("studio_camera_orbit_dist"), OrbitStr)) StudioCameraOrbitDist.InitFromString(OrbitStr);
	CharaLightId = Root->HasField(TEXT("chara_light_id")) ? int32(Root->GetNumberField(TEXT("chara_light_id"))) : -1;
	bLinkCharaLightToCamera = false;
	Root->TryGetBoolField(TEXT("link_chara_light"), bLinkCharaLightToCamera);
	LinkedLightBase = FVector2D::ZeroVector;
	LinkedCameraBase = FVector2D::ZeroVector;
	if (Root->TryGetStringField(TEXT("linked_light_base"), OrbitStr)) LinkedLightBase.InitFromString(OrbitStr);
	if (Root->TryGetStringField(TEXT("linked_camera_base"), OrbitStr)) LinkedCameraBase.InitFromString(OrbitStr);
	const TSharedPtr<FJsonObject>* ViewJson = nullptr;
	if (Root->TryGetObjectField(TEXT("view"), ViewJson)) FJsonObjectConverter::JsonObjectToUStruct(ViewJson->ToSharedRef(), &SavedView);
	const TArray<TSharedPtr<FJsonValue>>* MarkJson = nullptr;
	if (Root->TryGetArrayField(TEXT("bookmarks"), MarkJson))
		for (const TSharedPtr<FJsonValue>& V : *MarkJson)
		{
			FOKSceneBookmark B;
			if (V->AsObject()) FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &B);
			if (Bookmarks.Num() < 10) Bookmarks.Add(B);
		}
	NextId = FMath::Max(MaxId + 1, Root->HasField(TEXT("next_id")) ? int32(Root->GetNumberField(TEXT("next_id"))) : 1);
	NotifyChanged();
	return true;
}

bool UOKSceneDocument::ReplaceFile(const FString& Temp, const FString& Path, FString& OutError)
{
	if (IFileManager::Get().Move(*Path, *Temp, true, true, false, true)) return true;
	IFileManager::Get().Delete(*Temp, false, true, true);
	OutError = TEXT("cannot replace ") + Path;
	return false;
}

bool UOKSceneDocument::SaveToFile(const FString& Path, FString& OutError) const
{
	// The old file stays whole until the new one is written in full.
	const FString Temp = Path + TEXT(".saving");
	if (!FFileHelper::SaveStringToFile(ToJson(), *Temp, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)) { IFileManager::Get().Delete(*Temp, false, true, true); OutError = TEXT("cannot write ") + Path; return false; }
	return ReplaceFile(Temp, Path, OutError);
}

namespace
{
	/** Objects of a fragment or scene added to a document under new ids (parents inside the set follow; the set's top
	 *  objects go under Parent). Tracks of the objects come along. */
	TArray<int32> AddObjectsRemapped(UOKSceneDocument& Doc, TArray<FOKSceneObject>&& In, const TArray<FOKSceneTrack>& InTracks, int32 Parent, const TSharedPtr<FJsonObject>& ExtraRoot = nullptr)
	{
		TMap<int32, int32> IdMap;
		for (FOKSceneObject& O : In) IdMap.Add(O.Id, Doc.NextId++);
		TArray<int32> Tops;
		for (FOKSceneObject& O : In)
		{
			const bool bTop = !IdMap.Contains(O.Parent);
			O.Id = IdMap[O.Id];
			O.Parent = bTop ? (Doc.Find(Parent) ? Parent : -1) : IdMap[O.Parent];
			if (bTop) { Tops.Add(O.Id); if (O.Parent < 0 || (Doc.Find(O.Parent) && Doc.Find(O.Parent)->Kind != EOKSceneObjectKind::Character)) O.AttachBone.Reset(); }
			Doc.Objects.Add(MoveTemp(O));
		}
		for (const FOKSceneTrack& T : InTracks)
			if (const int32* To = IdMap.Find(T.ObjectId)) { FOKSceneTrack Copy = T; Copy.ObjectId = *To; Doc.Tracks.Add(MoveTemp(Copy)); }
		if (ExtraRoot)
		{
			const TArray<TSharedPtr<FJsonValue>>* TlJson = nullptr;
			if (ExtraRoot->TryGetArrayField(TEXT("timeline_tracks"), TlJson))
				for (const TSharedPtr<FJsonValue>& V : *TlJson)
				{
					FOKSceneTimelineTrack Tr;
					if (!V->AsObject() || !FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &Tr)) continue;
					if (Tr.ObjectId >= 0)
					{
						const int32* To = IdMap.Find(Tr.ObjectId);
						if (!To) continue;
						Tr.ObjectId = *To;
					}
					Doc.TimelineTracks.Add(MoveTemp(Tr));
				}
			const TArray<TSharedPtr<FJsonValue>>* ConJson = nullptr;
			if (ExtraRoot->TryGetArrayField(TEXT("constraints"), ConJson))
				for (const TSharedPtr<FJsonValue>& V : *ConJson)
				{
					FOKSceneConstraint Con;
					if (!V->AsObject() || !FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &Con)) continue;
					const int32* NewChild = IdMap.Find(Con.ChildId);
					const int32* NewParent = Con.ParentId == -2 ? nullptr : IdMap.Find(Con.ParentId);
					if (!NewChild || (Con.ParentId != -2 && !NewParent)) continue;
					Con.ChildId = *NewChild;
					if (NewParent) Con.ParentId = *NewParent;
					Doc.Constraints.Add(MoveTemp(Con));
				}
			const TSharedPtr<FJsonObject>* VngeJson = nullptr;
			if (ExtraRoot->TryGetObjectField(TEXT("vnge"), VngeJson) && VngeJson && VngeJson->IsValid())
			{
				FOKSceneVngeData MergedVnge;
				if (FJsonObjectConverter::JsonObjectToUStruct(VngeJson->ToSharedRef(), &MergedVnge))
				{
					MergedVnge.RemapObjectIds(IdMap);
					Doc.Vnge.Registry.Actors.Append(MergedVnge.Registry.Actors);
					Doc.Vnge.Registry.Props.Append(MergedVnge.Registry.Props);
					Doc.Vnge.Clips.Append(MergedVnge.Clips);
					Doc.Vnge.Texts.Append(MergedVnge.Texts);
					Doc.Vnge.Sounds.Append(MergedVnge.Sounds);
					Doc.Vnge.Physics.Rules.Append(MergedVnge.Physics.Rules);
				}
			}
		}
		return Tops;
	}

	bool ParseObjects(const TSharedPtr<FJsonObject>& Root, TArray<FOKSceneObject>& Out, TArray<FOKSceneTrack>& OutTracks, FString& OutError)
	{
		const TArray<TSharedPtr<FJsonValue>>* Items = nullptr;
		if (!Root || !Root->TryGetArrayField(TEXT("objects"), Items)) { OutError = TEXT("no objects"); return false; }
		TSet<int32> Ids;
		for (const TSharedPtr<FJsonValue>& V : *Items)
		{
			FOKSceneObject O;
			if (!V->AsObject() || !FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &O) || Ids.Contains(O.Id)) { OutError = TEXT("bad scene object"); return false; }
			Ids.Add(O.Id);
			Out.Add(MoveTemp(O));
		}
		const TArray<TSharedPtr<FJsonValue>>* TrackJson = nullptr;
		if (Root->TryGetArrayField(TEXT("tracks"), TrackJson))
			for (const TSharedPtr<FJsonValue>& V : *TrackJson)
			{
				FOKSceneTrack T;
				if (V->AsObject() && FJsonObjectConverter::JsonObjectToUStruct(V->AsObject().ToSharedRef(), &T) && Ids.Contains(T.ObjectId)) OutTracks.Add(MoveTemp(T));
			}
		return true;
	}
}

FString UOKSceneDocument::ExportFragment(const TArray<int32>& Ids) const
{
	// Every chosen object with its subtree, once, in document order (parents before children as the document has them).
	TSet<int32> Wanted;
	TArray<int32> Queue = Ids;
	for (int32 I = 0; I < Queue.Num(); ++I) if (Find(Queue[I]) && !Wanted.Contains(Queue[I])) { Wanted.Add(Queue[I]); Queue.Append(Children(Queue[I])); }
	TArray<TSharedPtr<FJsonValue>> Items, TrackJson;
	for (const FOKSceneObject& O : Objects)
		if (Wanted.Contains(O.Id))
			if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(O)) Items.Add(MakeShared<FJsonValueObject>(J));
	for (const FOKSceneTrack& T : Tracks)
		if (Wanted.Contains(T.ObjectId))
			if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(T)) TrackJson.Add(MakeShared<FJsonValueObject>(J));
	TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
	Root->SetStringField(TEXT("format"), TEXT("okscene-fragment"));
	Root->SetNumberField(TEXT("version"), FormatVersion);
	Root->SetArrayField(TEXT("objects"), Items);
	Root->SetArrayField(TEXT("tracks"), TrackJson);
	if (!Constraints.IsEmpty())
	{
		TArray<TSharedPtr<FJsonValue>> ConJson;
		for (const FOKSceneConstraint& C : Constraints) if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(C)) ConJson.Add(MakeShared<FJsonValueObject>(J));
		Root->SetArrayField(TEXT("constraints"), ConJson);
	}
	if (!TimelineTracks.IsEmpty())
	{
		TArray<TSharedPtr<FJsonValue>> TlJson;
		for (const FOKSceneTimelineTrack& T : TimelineTracks) if (TSharedPtr<FJsonObject> J = FJsonObjectConverter::UStructToJsonObject(T)) TlJson.Add(MakeShared<FJsonValueObject>(J));
		Root->SetArrayField(TEXT("timeline_tracks"), TlJson);
	}
	if (bLoopTimeline) Root->SetBoolField(TEXT("loop_timeline"), true);
	if (!FMath::IsNearlyEqual(TimelineSpeed, 1.f, 1e-4f)) Root->SetNumberField(TEXT("timeline_speed"), TimelineSpeed);
	if (TimelineDivisions != 10) Root->SetNumberField(TEXT("timeline_divisions"), TimelineDivisions);
	if (!FMath::IsNearlyEqual(TimelineBlockLength, 1.f, 1e-4f)) Root->SetNumberField(TEXT("timeline_block_length"), TimelineBlockLength);
	if (!Vnge.IsEmpty())
		if (TSharedPtr<FJsonObject> VngeJson = FJsonObjectConverter::UStructToJsonObject(Vnge)) Root->SetObjectField(TEXT("vnge"), VngeJson);
	if (StudioCameraId >= 0)
	{
		Root->SetNumberField(TEXT("studio_camera_id"), StudioCameraId);
		Root->SetStringField(TEXT("studio_camera_orbit_target"), StudioCameraOrbitTarget.ToString());
		Root->SetStringField(TEXT("studio_camera_orbit_rot"), StudioCameraOrbitRot.ToString());
		Root->SetStringField(TEXT("studio_camera_orbit_dist"), StudioCameraOrbitDist.ToString());
	}
	if (CharaLightId >= 0) Root->SetNumberField(TEXT("chara_light_id"), CharaLightId);
	if (bLinkCharaLightToCamera)
	{
		Root->SetBoolField(TEXT("link_chara_light"), true);
		Root->SetStringField(TEXT("linked_light_base"), LinkedLightBase.ToString());
		Root->SetStringField(TEXT("linked_camera_base"), LinkedCameraBase.ToString());
	}
	FString Out;
	FJsonSerializer::Serialize(Root, TJsonWriterFactory<>::Create(&Out));
	return Out;
}

TArray<int32> UOKSceneDocument::PasteFragment(const FString& Json, int32 Parent, FString& OutError)
{
	TSharedPtr<FJsonObject> Root;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json), Root) || !Root || Root->GetStringField(TEXT("format")) != TEXT("okscene-fragment")) { OutError = TEXT("not an OK Studio clipboard fragment"); return {}; }
	TArray<FOKSceneObject> In;
	TArray<FOKSceneTrack> InTracks;
	if (!ParseObjects(Root, In, InTracks, OutError)) return {};
	TArray<int32> Tops = AddObjectsRemapped(*this, MoveTemp(In), InTracks, Parent, Root);
	NotifyChanged();
	return Tops;
}

TArray<int32> UOKSceneDocument::Merge(const FString& SceneJson, FString& OutError)
{
	TSharedPtr<FJsonObject> Root;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(SceneJson), Root) || !Root || Root->GetStringField(TEXT("format")) != TEXT("okscene")) { OutError = TEXT("not an .okscene"); return {}; }
	TArray<FOKSceneObject> In;
	TArray<FOKSceneTrack> InTracks;
	if (!ParseObjects(Root, In, InTracks, OutError)) return {};
	TSet<int32> Ids;
	for (const FOKSceneObject& O : In) Ids.Add(O.Id);
	for (FOKSceneObject& O : In) if (!Ids.Contains(O.Parent)) O.Parent = -1;
	TArray<int32> Tops = AddObjectsRemapped(*this, MoveTemp(In), InTracks, -1, Root);
	if (Root->HasField(TEXT("duration"))) Duration = FMath::Max(Duration, float(Root->GetNumberField(TEXT("duration"))));
	NotifyChanged();
	return Tops;
}

bool UOKSceneDocument::LoadFromFile(const FString& Path, FString& OutError)
{
	FString Json;
	if (!FFileHelper::LoadFileToString(Json, *Path)) { OutError = TEXT("cannot read ") + Path; return false; }
	return FromJson(Json, OutError);
}

namespace
{
	/** The keyed value of an object: a light's intensity or a camera's field of view. */
	float KeyValue(const FOKSceneObject& O)
	{
		return O.Kind == EOKSceneObjectKind::Light ? O.Light.Intensity : O.Kind == EOKSceneObjectKind::Camera ? O.Camera.Fov : O.Kind == EOKSceneObjectKind::Effect ? O.Effect.Intensity : 0.f;
	}
	void SetKeyValue(FOKSceneObject& O, float V)
	{
		if (O.Kind == EOKSceneObjectKind::Light) O.Light.Intensity = V;
		else if (O.Kind == EOKSceneObjectKind::Camera) O.Camera.Fov = V;
		else if (O.Kind == EOKSceneObjectKind::Effect) O.Effect.Intensity = V;
	}
	constexpr float KeyTolerance = 1.f / 60.f;
}

const FOKSceneTrack* UOKSceneDocument::TrackOf(int32 Id) const
{
	return Tracks.FindByPredicate([Id](const FOKSceneTrack& T) { return T.ObjectId == Id; });
}

int32 UOKSceneDocument::MoveKey(int32 Id, int32 Index, float NewTime)
{
	FOKSceneTrack* T = Tracks.FindByPredicate([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; });
	if (!T || !T->Keys.IsValidIndex(Index)) return INDEX_NONE;
	FOKSceneKey K = T->Keys[Index];
	T->Keys.RemoveAt(Index);
	K.Time = FMath::Max(NewTime, 0.f);
	T->Keys.RemoveAll([&K](const FOKSceneKey& X) { return FMath::Abs(X.Time - K.Time) < KeyTolerance; });
	T->Keys.Add(K);
	T->Keys.Sort([](const FOKSceneKey& A, const FOKSceneKey& B) { return A.Time < B.Time; });
	Duration = FMath::Max(Duration, K.Time);
	NotifyChanged();
	return T->Keys.IndexOfByPredicate([&K](const FOKSceneKey& X) { return X.Time == K.Time; });
}

namespace
{
	FString KeyedText(const FTransform& T, float Value, bool bCharacter, const TArray<FOKSceneFkBone>& Fk, int32 Eyebrow, int32 Eyes, int32 Mouth, float MouthOpen,
		int32 HandLeft, int32 HandRight, const TArray<uint8>& Clothes, float Style, float FaceStyle, float AnimTime)
	{
		const FVector L = T.GetLocation(), S = T.GetScale3D();
		const FRotator R = T.Rotator();
		FString Text = FString::Printf(TEXT("%.2f %.2f %.2f %.2f %.2f %.2f %.3f %.3f %.3f %.3f"), L.X, L.Y, L.Z, R.Pitch, R.Yaw, R.Roll, S.X, S.Y, S.Z, Value);
		if (!bCharacter) return Text;
		Text += FString::Printf(TEXT(" %d %d %d %.3f %d %d %.3f %.3f %.3f"), Eyebrow, Eyes, Mouth, MouthOpen, HandLeft, HandRight, Style, FaceStyle, AnimTime);
		for (uint8 C : Clothes) Text += FString::Printf(TEXT(" c%d"), C);
		for (const FOKSceneFkBone& B : Fk) Text += FString::Printf(TEXT(" %s %.2f %.2f %.2f"), *B.Bone, B.Euler.X, B.Euler.Y, B.Euler.Z);
		return Text;
	}
}

FString UOKSceneDocument::KeyedState(const FOKSceneObject& O, bool bMotion)
{
	const FOKSceneCharacter& C = O.Character;
	FString Text = KeyedText(O.Transform, KeyValue(O), O.Kind == EOKSceneObjectKind::Character, C.Fk, C.EyebrowPattern, C.EyesPattern, C.MouthPattern, C.MouthOpen,
		C.HandLeft, C.HandRight, C.ClothesStates, C.Style, C.ShownFaceStyle(), C.Speed == 0.f ? C.Time : -1.f);
	if (bMotion && C.StudioAnimeNo >= 0) Text += FString::Printf(TEXT(" m%d/%d/%d/%d %.3f"), C.StudioAnimeKind, C.StudioAnimeGroup, C.StudioAnimeCategory, C.StudioAnimeNo, C.Speed);
	if (O.Kind == EOKSceneObjectKind::Character) Text += FString::Printf(TEXT(" l%d %d %.1f %.1f %.1f"), int32(C.EyesLook), int32(C.NeckLook), C.LookPoint.X, C.LookPoint.Y, C.LookPoint.Z);
	return Text;
}

bool UOKSceneDocument::HasMotionKeys(int32 Id) const
{
	const FOKSceneTrack* T = Tracks.FindByPredicate([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; });
	return T && T->Keys.ContainsByPredicate([](const FOKSceneKey& K) { return K.AnimNo >= 0; });
}

bool UOKSceneDocument::MotionFadeAt(int32 Id, float Time, FOKSceneMotionFade& Out) const
{
	Out = FOKSceneMotionFade();
	const FOKSceneTrack* T = Tracks.FindByPredicate([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; });
	if (!T) return false;
	// The first key of the run of one motion that Index is in.
	auto RunStart = [T](int32 Index)
	{
		int32 Start = Index;
		for (int32 I = Index - 1; I >= 0; --I)
		{
			if (T->Keys[I].AnimNo < 0) continue;
			if (!T->Keys[I].SameMotion(T->Keys[Index])) break;
			Start = I;
		}
		return Start;
	};
	int32 First = INDEX_NONE, Last = INDEX_NONE;
	for (int32 I = 0; I < T->Keys.Num(); ++I)
	{
		if (T->Keys[I].AnimNo < 0) continue;
		if (First == INDEX_NONE) First = I;
		if (T->Keys[I].Time <= Time) Last = I;
	}
	if (Last == INDEX_NONE) return false;
	const int32 Start = RunStart(Last);
	const FOKSceneKey& K = T->Keys[Start];
	if (K.AnimBlend <= 0.f || K.AnimSpeed <= 0.f || K.AnimTime >= 0.f || Time >= K.Time + K.AnimBlend) return false;
	int32 Before = INDEX_NONE;
	for (int32 I = Start - 1; I >= 0 && Before == INDEX_NONE; --I) if (T->Keys[I].AnimNo >= 0) Before = I;
	if (Before == INDEX_NONE) return false;
	const FOKSceneKey& P = T->Keys[Before];
	const int32 PStart = RunStart(Before);
	// Where the old motion's clock stood at the key (ApplyMotionKeys' clock), or the frame it was held on.
	const float Clock = PStart == First ? T->Keys[PStart].AnimStart : -T->Keys[PStart].Time * P.AnimSpeed;
	Out.Kind = P.AnimKind; Out.Group = P.AnimGroup; Out.Category = P.AnimCategory; Out.No = P.AnimNo;
	Out.FromTime = P.AnimTime >= 0.f ? P.AnimTime : Clock + K.Time * P.AnimSpeed;
	Out.Duration = K.AnimBlend * K.AnimSpeed;
	return true;
}

FString UOKSceneDocument::KeyedState(const FOKSceneObject& O, const FOKSceneKey& K)
{
	FString Text = KeyedText(K.Transform, K.Value, O.Kind == EOKSceneObjectKind::Character, K.Fk, K.EyebrowPattern, K.EyesPattern, K.MouthPattern, K.MouthOpen,
		K.HandLeft, K.HandRight, K.ClothesStates, K.Style, K.ShownFaceStyle(), K.AnimTime);
	if (K.AnimNo >= 0) Text += FString::Printf(TEXT(" m%d/%d/%d/%d %.3f"), K.AnimKind, K.AnimGroup, K.AnimCategory, K.AnimNo, K.AnimSpeed);
	// A key from before U266 says nothing about the look: whatever it is now is as keyed.
	if (O.Kind == EOKSceneObjectKind::Character)
	{
		const FOKSceneCharacter& C = O.Character;
		const bool bKeyed = K.LookEyes >= 0;
		const FVector P = bKeyed ? K.LookPoint : C.LookPoint;
		Text += FString::Printf(TEXT(" l%d %d %.1f %.1f %.1f"), bKeyed ? K.LookEyes : int32(C.EyesLook), bKeyed ? K.LookNeck : int32(C.NeckLook), P.X, P.Y, P.Z);
	}
	return Text;
}

void UOKSceneDocument::SetKey(int32 Id, float Time)
{
	if (Id == SceneTrackId)
	{
		FOKSceneTrack* T = Tracks.FindByPredicate([](const FOKSceneTrack& X) { return X.ObjectId == SceneTrackId; });
		if (!T) { T = &Tracks.AddDefaulted_GetRef(); T->ObjectId = SceneTrackId; }
		const FOKSceneKey* Old = T->Keys.FindByPredicate([Time](const FOKSceneKey& K) { return FMath::Abs(K.Time - Time) < KeyTolerance; });
		FOKSceneKey K;
		K.Ease = Old ? Old->Ease : EOKSceneEase::Linear;
		T->Keys.RemoveAll([Time](const FOKSceneKey& X) { return FMath::Abs(X.Time - Time) < KeyTolerance; });
		K.Time = FMath::Max(Time, 0.f);
		K.Exposure = Post.Exposure;
		K.FocalDistance = Post.FocalDistance;
		K.Camera = ActiveCamera;
		T->Keys.Add(K);
		T->Keys.Sort([](const FOKSceneKey& A, const FOKSceneKey& B) { return A.Time < B.Time; });
		Duration = FMath::Max(Duration, K.Time);
		NotifyChanged();
		return;
	}
	const FOKSceneObject* O = Find(Id);
	if (!O) return;
	FOKSceneTrack* T = Tracks.FindByPredicate([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; });
	if (!T) { T = &Tracks.AddDefaulted_GetRef(); T->ObjectId = Id; }
	// Re-keying keeps the key's curve.
	const FOKSceneKey* Old = T->Keys.FindByPredicate([Time](const FOKSceneKey& K) { return FMath::Abs(K.Time - Time) < KeyTolerance; });
	const EOKSceneEase Ease = Old ? Old->Ease : EOKSceneEase::Linear;
	const float Blend = Old ? Old->AnimBlend : 0.f;
	T->Keys.RemoveAll([Time](const FOKSceneKey& K) { return FMath::Abs(K.Time - Time) < KeyTolerance; });
	FOKSceneKey K;
	K.Time = FMath::Max(Time, 0.f);
	K.Ease = Ease;
	K.AnimBlend = Blend;
	K.Transform = O->Transform;
	K.Value = KeyValue(*O);
	if (O->Kind == EOKSceneObjectKind::Character)
	{
		const FOKSceneCharacter& C = O->Character;
		K.Fk = C.Fk;
		K.bCharacterState = true;
		K.EyebrowPattern = C.EyebrowPattern; K.EyesPattern = C.EyesPattern; K.MouthPattern = C.MouthPattern; K.MouthOpen = C.MouthOpen;
		K.HandLeft = C.HandLeft; K.HandRight = C.HandRight; K.ClothesStates = C.ClothesStates; K.Style = C.Style; K.FaceStyle = C.FaceStyle;
		K.LookEyes = int32(C.EyesLook); K.LookNeck = int32(C.NeckLook); K.LookPoint = C.LookPoint;
		// A stopped animation keys its frame (the timeline then scrubs it); a playing one runs on its own.
		K.AnimTime = C.Speed == 0.f ? C.Time : -1.f;
		// The motion too (U230): one person talking, then the other, needs it to change on the timeline. A motion that is
		// not a Studio one (a video motion, an .okanim) stays as it is.
		if (C.StudioAnimeNo >= 0)
		{
			K.AnimKind = C.StudioAnimeKind; K.AnimGroup = C.StudioAnimeGroup; K.AnimCategory = C.StudioAnimeCategory; K.AnimNo = C.StudioAnimeNo;
			K.AnimSpeed = C.Speed; K.AnimStart = C.Time;
		}
	}
	if (O->Kind == EOKSceneObjectKind::Light) K.Color = O->Light.Color;
	T->Keys.Add(K);
	T->Keys.Sort([](const FOKSceneKey& A, const FOKSceneKey& B) { return A.Time < B.Time; });
	Duration = FMath::Max(Duration, K.Time);
	NotifyChanged();
}

bool UOKSceneDocument::SetBoneKey(int32 Id, float Time, const FString& Bone)
{
	const FOKSceneObject* O = Find(Id);
	if (!O || O->Kind != EOKSceneObjectKind::Character || Bone.IsEmpty()) return false;
	// The bone's value now: its FK, or nothing to key.
	const FOKSceneFkBone* Now = O->Character.Fk.FindByPredicate([&](const FOKSceneFkBone& B) { return B.Bone == Bone; });
	if (!Now) return false;
	const FOKSceneFkBone Value = *Now;
	FOKSceneKey* K = KeyAt(Id, Time);
	if (!K)
	{
		FOKSceneTrack* T = TrackOf(Id);
		if (!T) { T = &Tracks.AddDefaulted_GetRef(); T->ObjectId = Id; }
		// The rest of the new key is what the track gives at Time, so only this bone changes.
		FOKSceneKey& New = T->Keys.AddDefaulted_GetRef();
		New.Time = FMath::Max(Time, 0.f);
		New.Transform = O->Transform;
		New.Value = KeyValue(*O);
		New.AnimTime = O->Character.Speed == 0.f ? O->Character.Time : -1.f;
		T->Keys.Sort([](const FOKSceneKey& A, const FOKSceneKey& B) { return A.Time < B.Time; });
		Duration = FMath::Max(Duration, Time);
		K = KeyAt(Id, Time);
	}
	if (FOKSceneFkBone* B = K->Fk.FindByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == Bone; })) *B = Value;
	else K->Fk.Add(Value);
	NotifyChanged();
	return true;
}

bool UOKSceneDocument::RemoveBoneKey(int32 Id, float Time, const FString& Bone)
{
	FOKSceneKey* K = KeyAt(Id, Time);
	if (!K || !K->Fk.RemoveAll([&](const FOKSceneFkBone& B) { return B.Bone == Bone; })) return false;
	NotifyChanged();
	return true;
}

bool UOKSceneDocument::ClearTrack(int32 Id)
{
	if (!Tracks.RemoveAll([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; })) return false;
	NotifyChanged();
	return true;
}

FOKSceneKey* UOKSceneDocument::KeyAt(int32 Id, float Time)
{
	FOKSceneTrack* T = Tracks.FindByPredicate([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; });
	return T ? T->Keys.FindByPredicate([Time](const FOKSceneKey& K) { return FMath::Abs(K.Time - Time) < KeyTolerance; }) : nullptr;
}

float UOKSceneDocument::EaseAlpha(EOKSceneEase Ease, float U)
{
	U = FMath::Clamp(U, 0.f, 1.f);
	switch (Ease)
	{
	case EOKSceneEase::EaseInOut: return U < 0.5f ? 2.f * U * U : 1.f - 2.f * (1.f - U) * (1.f - U);
	case EOKSceneEase::EaseIn: return U * U;
	case EOKSceneEase::EaseOut: return 1.f - (1.f - U) * (1.f - U);
	case EOKSceneEase::Step: return 0.f;
	default: return U;
	}
}

bool UOKSceneDocument::RemoveKey(int32 Id, float Time)
{
	FOKSceneTrack* T = Tracks.FindByPredicate([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; });
	if (!T || !T->Keys.RemoveAll([Time](const FOKSceneKey& K) { return FMath::Abs(K.Time - Time) < KeyTolerance; })) return false;
	if (T->Keys.IsEmpty()) Tracks.RemoveAll([Id](const FOKSceneTrack& X) { return X.ObjectId == Id; });
	NotifyChanged();
	return true;
}

namespace
{
	/** A key's face, hands and clothes onto a character (the mouth opening given separately, it blends). */
	void ApplyCharacterKey(FOKSceneCharacter& C, const FOKSceneKey& K, float MouthOpen, float Style, float FaceStyle)
	{
		if (!K.bCharacterState) return;
		if (Style >= -1.f) { C.Style = Style; C.FaceStyle = FaceStyle; }
		C.EyebrowPattern = K.EyebrowPattern; C.EyesPattern = K.EyesPattern; C.MouthPattern = K.MouthPattern; C.MouthOpen = MouthOpen;
		C.HandLeft = K.HandLeft; C.HandRight = K.HandRight;
		if (K.LookEyes >= 0) { C.EyesLook = EOKSceneLook(K.LookEyes); C.NeckLook = EOKSceneLook(K.LookNeck); C.LookPoint = K.LookPoint; }
		// Clothes only change when they differ (a change rebuilds the character).
		if (K.ClothesStates.Num() == C.ClothesStates.Num() && K.ClothesStates != C.ClothesStates) C.ClothesStates = K.ClothesStates;
	}

	/** Where the views of two camera keys meet: the middle of the closest points of their rays, both in front of the
	 *  cameras. False for views that run side by side or apart. */
	bool OrbitPoint(const FTransform& A, const FTransform& B, FVector& Out)
	{
		const FVector DA = A.GetRotation().GetAxisX(), DB = B.GetRotation().GetAxisX(), W = A.GetLocation() - B.GetLocation();
		const double Dot = DA | DB, Den = 1. - Dot * Dot;
		if (Den < 1e-3) return false;
		const double D = DA | W, E = DB | W;
		const double S = (Dot * E - D) / Den, T = (E - Dot * D) / Den;
		if (S <= 1. || T <= 1.) return false;
		Out = (A.GetLocation() + DA * S + B.GetLocation() + DB * T) * 0.5;
		return true;
	}

	/** A camera at U between two keys, swung round where they look: the distance and the turn go evenly, and the keys'
	 *  own aim off that point fades from one to the other, so it lands on each key exactly. */
	bool OrbitBetween(const FTransform& A, const FTransform& B, float U, FTransform& Out)
	{
		FVector Focus;
		if (!OrbitPoint(A, B, Focus)) return false;
		const FVector VA = A.GetLocation() - Focus, VB = B.GetLocation() - Focus;
		const double LA = VA.Size(), LB = VB.Size();
		if (LA < 1. || LB < 1.) return false;
		const FVector Dir = FQuat::Slerp(FQuat::Identity, FQuat::FindBetweenVectors(VA, VB), U).RotateVector(VA / LA);
		if (FMath::Abs(Dir.Z) > 0.999 || FMath::Abs(VA.Z / LA) > 0.999 || FMath::Abs(VB.Z / LB) > 0.999) return false;
		auto Look = [](const FVector& From) { return FRotationMatrix::MakeFromXZ(-From, FVector::UpVector).ToQuat(); };
		const FQuat OffA = Look(VA / LA).Inverse() * A.GetRotation(), OffB = Look(VB / LB).Inverse() * B.GetRotation();
		Out.SetLocation(Focus + Dir * FMath::Lerp(LA, LB, double(U)));
		Out.SetRotation(Look(Dir) * FQuat::Slerp(OffA, OffB, U));
		return true;
	}

	/** The motion a character track gives at Time: the last key at or before it that holds one (before the first, the
	 *  first). It starts over at the first key of its run; the track's first motion starts where it was keyed. */
	void ApplyMotionKeys(FOKSceneCharacter& C, const FOKSceneTrack& T, float Time)
	{
		int32 First = INDEX_NONE, Last = INDEX_NONE;
		for (int32 I = 0; I < T.Keys.Num(); ++I)
		{
			if (T.Keys[I].AnimNo < 0) continue;
			if (First == INDEX_NONE) First = I;
			if (T.Keys[I].Time <= Time || Last == INDEX_NONE) Last = I;
		}
		if (Last == INDEX_NONE) return;
		const FOKSceneKey& K = T.Keys[Last];
		int32 Start = Last;
		for (int32 I = Last - 1; I >= 0; --I)
		{
			if (T.Keys[I].AnimNo < 0) continue;
			if (!T.Keys[I].SameMotion(K)) break;
			Start = I;
		}
		C.StudioAnimeKind = K.AnimKind; C.StudioAnimeGroup = K.AnimGroup; C.StudioAnimeCategory = K.AnimCategory; C.StudioAnimeNo = K.AnimNo;
		C.Speed = K.AnimSpeed;
		// The clock is Time + the timeline's time * Speed: this puts the motion's start at its key.
		C.Time = Start == First ? T.Keys[Start].AnimStart : -T.Keys[Start].Time * K.AnimSpeed;
	}

	/** A character track's FK at Time. */
	TArray<FOKSceneFkBone> SampleTrackFk(const FOKSceneTrack& T, float Time)
	{
		// Every FK bone is its own track (HS2Studio6 bone keys): it turns between the nearest keys around Time that
		// hold it, so a bone keyed at fewer keys still moves smoothly; before its first / after its last key it holds.
		TArray<FString> Names;
		for (const FOKSceneKey& K : T.Keys) for (const FOKSceneFkBone& Bone : K.Fk) Names.AddUnique(Bone.Bone);
		TArray<FOKSceneFkBone> Fk;
		for (const FString& Name : Names)
		{
			const FOKSceneFkBone* From = nullptr; const FOKSceneFkBone* To = nullptr;
			const FOKSceneKey* KeyFrom = nullptr; const FOKSceneKey* KeyTo = nullptr;
			for (const FOKSceneKey& K : T.Keys)
			{
				const FOKSceneFkBone* Bone = K.Fk.FindByPredicate([&](const FOKSceneFkBone& X2) { return X2.Bone == Name; });
				if (!Bone) continue;
				if (K.Time <= Time) { From = Bone; KeyFrom = &K; }
				else if (!To) { To = Bone; KeyTo = &K; }
			}
			if (!From) { Fk.Add(*To); continue; }
			FOKSceneFkBone Out = *From;
			if (To)
			{
				const float W = UOKSceneDocument::EaseAlpha(KeyFrom->Ease, (Time - KeyFrom->Time) / FMath::Max(KeyTo->Time - KeyFrom->Time, 1e-4f));
				const float Ea[3] = { float(From->Euler.X), float(From->Euler.Y), float(From->Euler.Z) };
				const float Eb[3] = { float(To->Euler.X), float(To->Euler.Y), float(To->Euler.Z) };
				float E[3] = {};
				if (ok_unity_euler_slerp(Ea, Eb, W, E) == 0) Out.Euler = FVector(E[0], E[1], E[2]);
			}
			Fk.Add(Out);
		}
		return Fk;
	}
}

namespace
{
	FTransform DocUnityToUe(const FVector& Position, const FVector& EulerDegrees, const FVector& Scale)
	{
		const FQuat Qx(FVector(1, 0, 0), FMath::DegreesToRadians(EulerDegrees.X));
		const FQuat Qy(FVector(0, 1, 0), FMath::DegreesToRadians(EulerDegrees.Y));
		const FQuat Qz(FVector(0, 0, 1), FMath::DegreesToRadians(EulerDegrees.Z));
		const FQuat U = Qy * Qx * Qz;
		return FTransform(FQuat(-U.X, U.Z, U.Y, U.W).GetNormalized(), FVector(-Position.X, Position.Z, Position.Y) * 100.0, FVector(Scale.X, Scale.Z, Scale.Y));
	}

	FVector DocComputeLinkedCharaLightEuler(const FVector2D& PreLig, const FVector2D& PreCam, const FVector2D& CamEuler)
	{
		auto Wrap180 = [](double Deg) -> double
		{
			if (Deg < -180.0 || Deg > 180.0)
				Deg = Deg <= 0.0 ? FMath::Fmod(Deg - 180.0, 360.0) + 180.0 : FMath::Fmod(Deg + 180.0, 360.0) - 180.0;
			return Deg;
		};
		auto Wrap90 = [](double Deg) -> double
		{
			if (Deg < -90.0 || Deg > 90.0)
				Deg = Deg <= 0.0 ? FMath::Fmod(Deg - 90.0, 180.0) + 90.0 : FMath::Fmod(Deg + 90.0, 180.0) - 90.0;
			return Deg;
		};
		auto Fix360 = [](double Deg) -> double
		{
			Deg = FMath::Fmod(Deg, 360.0);
			return Deg < 0.0 ? Deg + 360.0 : Deg;
		};
		const double Dx = CamEuler.X - PreCam.X;
		const double Dy = CamEuler.Y - PreCam.Y;
		if (FMath::IsNearlyZero(Dx, 1e-6) && FMath::IsNearlyZero(Dy, 1e-6))
			return FVector(PreLig.X, PreLig.Y, 0.0);
		const double Alpha = Wrap180(PreLig.Y + 180.0 - PreCam.Y);
		const double Beta = Wrap90(40.0 - PreLig.X);
		int32 Situ = 0;
		if (FMath::IsNearlyZero(Alpha, 1e-4)) Situ = 1;
		else if (FMath::IsNearlyEqual(FMath::Abs(Alpha), 180.0, 1e-4)) Situ = 2;
		else if (FMath::IsNearlyEqual(FMath::Abs(Beta), 90.0, 1e-4)) Situ = 3;
		if (Situ != 0)
		{
			double OffX = Dx, OffY = Dy;
			if (Situ == 2) OffX = -Dx;
			else if (Situ == 3)
			{
				if (Alpha > 90.0) { OffX = -Dx; OffY = Dy + 180.0 - Alpha; }
				else if (Alpha < -90.0) { OffX = -Dx; OffY = Dy - 180.0 - Alpha; }
				else { OffX = Dx; OffY = Dy - Alpha; }
			}
			return FVector(Fix360(PreLig.X - OffX), Fix360(PreLig.Y + OffY), 0.0);
		}
		const double AlphaR = FMath::DegreesToRadians(Alpha);
		const double BetaR = FMath::DegreesToRadians(Beta);
		const double SinAlphaCosBeta = FMath::Sin(AlphaR) * FMath::Cos(BetaR);
		double CosR = FMath::Sqrt(FMath::Max(0.0, 1.0 - SinAlphaCosBeta * SinAlphaCosBeta));
		if (Alpha < -90.0 || Alpha > 90.0) CosR = -CosR;
		const double SinAgls = FMath::IsNearlyZero(CosR, 1e-12) ? 0.0 : FMath::Clamp(FMath::Sin(BetaR) / CosR, -1.0, 1.0);
		const double NextAgls = FMath::Asin(SinAgls) + FMath::DegreesToRadians(Dx);
		const double NewBetaR = FMath::Asin(FMath::Clamp(FMath::Sin(NextAgls) * CosR, -1.0, 1.0));
		const double CosNewBeta = FMath::Cos(NewBetaR);
		const double CosNewAlpha = FMath::IsNearlyZero(CosNewBeta, 1e-12) ? 1.0 : FMath::Clamp(FMath::Cos(NextAgls) * CosR / CosNewBeta, -1.0, 1.0);
		double NewAlphaR = FMath::Acos(CosNewAlpha);
		if (Alpha < 0.0) NewAlphaR = -NewAlphaR;
		const double DeltaBeta = FMath::RadiansToDegrees(NewBetaR) - Beta;
		const double DeltaYaw = Dy + FMath::RadiansToDegrees(NewAlphaR) - Alpha;
		return FVector(Fix360(PreLig.X - DeltaBeta), Fix360(PreLig.Y + DeltaYaw), 0.0);
	}

	float EvalTimelineCurve(const TArray<FOKSceneTimelineCurvePt>& Curve, float U)
	{
		U = FMath::Clamp(U, 0.f, 1.f);
		if (Curve.Num() < 2) return U;
		if (U <= Curve[0].Time) return Curve[0].Value;
		if (U >= Curve.Last().Time) return Curve.Last().Value;
		for (int32 I = 0; I + 1 < Curve.Num(); ++I)
		{
			const FOKSceneTimelineCurvePt& P0 = Curve[I];
			const FOKSceneTimelineCurvePt& P1 = Curve[I + 1];
			if (U <= P1.Time)
			{
				const float Dt = P1.Time - P0.Time;
				if (Dt <= 1e-6f || !FMath::IsFinite(P0.OutTangent) || !FMath::IsFinite(P1.InTangent)) return P0.Value;
				const float S = (U - P0.Time) / Dt;
				const float S2 = S * S, S3 = S2 * S;
				const float M0 = P0.OutTangent * Dt, M1 = P1.InTangent * Dt;
				return (2.f * S3 - 3.f * S2 + 1.f) * P0.Value
					+ (S3 - 2.f * S2 + S) * M0
					+ (-2.f * S3 + 3.f * S2) * P1.Value
					+ (S3 - S2) * M1;
			}
		}
		return Curve.Last().Value;
	}

	FVector SampleUnityQuatSlerpEuler(const TArray<float>& Va, const TArray<float>* Vb, float Factor)
	{
		if (Va.Num() < 4) return FVector::ZeroVector;
		float Q[4] = { Va[0], Va[1], Va[2], Va[3] };
		if (Vb && Vb->Num() >= 4)
		{
			float Qb[4] = { (*Vb)[0], (*Vb)[1], (*Vb)[2], (*Vb)[3] };
			float Dot = Q[0] * Qb[0] + Q[1] * Qb[1] + Q[2] * Qb[2] + Q[3] * Qb[3];
			if (Dot < 0.f) { for (int32 K = 0; K < 4; ++K) Qb[K] = -Qb[K]; Dot = -Dot; }
			if (Dot > 0.9995f)
			{
				float Norm = 0.f;
				for (int32 K = 0; K < 4; ++K) { Q[K] = Q[K] + (Qb[K] - Q[K]) * Factor; Norm += Q[K] * Q[K]; }
				Norm = FMath::Sqrt(FMath::Max(Norm, 1e-12f));
				for (int32 K = 0; K < 4; ++K) Q[K] /= Norm;
			}
			else
			{
				const float Theta = FMath::Acos(FMath::Clamp(Dot, -1.f, 1.f));
				const float SinTh = FMath::Sin(Theta);
				const float Sa = FMath::Sin((1.f - Factor) * Theta) / SinTh;
				const float Sb = FMath::Sin(Factor * Theta) / SinTh;
				for (int32 K = 0; K < 4; ++K) Q[K] = Q[K] * Sa + Qb[K] * Sb;
			}
		}
		float OutEuler[3] = { 0.f, 0.f, 0.f };
		ok_unity_quat_to_euler(Q, OutEuler);
		return FVector(OutEuler[0], OutEuler[1], OutEuler[2]);
	}

	void UpsertBoneOverride(TArray<FOKSceneBoneTrs>& Arr, const FString& Bone, const FVector* Pos, const FVector* Euler, const FVector* Scale)
	{
		FOKSceneBoneTrs* Entry = Arr.FindByPredicate([&](const FOKSceneBoneTrs& B) { return B.Bone == Bone; });
		if (!Entry) { Entry = &Arr.AddDefaulted_GetRef(); Entry->Bone = Bone; }
		if (Pos) { Entry->bHasPos = true; Entry->Pos = *Pos; }
		if (Euler) { Entry->bHasRot = true; Entry->Euler = *Euler; }
		if (Scale) { Entry->bHasScale = true; Entry->Scale = *Scale; }
	}

	void UpsertMorphOverride(TArray<FOKSceneMorphOverride>& Arr, const FString& Renderer, int32 Index, const FString& Name, float Weight)
	{
		FOKSceneMorphOverride* Entry = Arr.FindByPredicate([&](const FOKSceneMorphOverride& M) { return M.Renderer == Renderer && M.Index == Index; });
		if (!Entry) { Entry = &Arr.AddDefaulted_GetRef(); Entry->Renderer = Renderer; Entry->Index = Index; }
		if (!Name.IsEmpty()) Entry->Name = Name;
		Entry->Weight = FMath::Clamp(Weight, 0.f, 100.f);
	}
}

namespace
{
	void UpsertLiveMaterialEdit(TArray<FOKSceneMaterialEdit>& Arr, const FString& Material, const FString& Property, EOKSceneMaterialEditKind Kind, const FLinearColor& Val)
	{
		if (Property.IsEmpty()) return;
		FOKSceneMaterialEdit* Entry = Arr.FindByPredicate([&](const FOKSceneMaterialEdit& E) { return E.Material == Material && E.Property == Property && E.Kind == Kind; });
		if (!Entry)
		{
			Entry = &Arr.AddDefaulted_GetRef();
			Entry->Material = Material;
			Entry->Property = Property;
			Entry->Kind = Kind;
		}
		Entry->Value = Val;
	}

	FString DocLeafNodeName(const FString& Path)
	{
		FString Trimmed = Path;
		Trimmed.TrimStartAndEndInline();
		int32 Slash = INDEX_NONE;
		if (Trimmed.FindLastChar(TEXT('/'), Slash)) Trimmed = Trimmed.Mid(Slash + 1);
		if (Trimmed.EndsWith(TEXT("(work)"))) Trimmed.LeftChopInline(6);
		Trimmed.TrimStartAndEndInline();
		return Trimmed;
	}
}

float UOKSceneDocument::EvaluateTimelineCurve01(const TArray<FOKSceneTimelineCurvePt>& Curve, float RawU)
{
	return EvalTimelineCurve(Curve, RawU);
}

void UOKSceneDocument::EvaluateTimeline(float Time)
{
	bool bAny = false;
	// The keys around Time and the eased fraction between them (B null: hold A).
	auto Around = [Time](const FOKSceneTrack& T, const FOKSceneKey*& A, const FOKSceneKey*& B, float& U)
	{
		const int32 Next = T.Keys.IndexOfByPredicate([Time](const FOKSceneKey& K) { return K.Time > Time; });
		if (Next == INDEX_NONE) { A = &T.Keys.Last(); B = nullptr; U = 0.f; return; }
		if (Next == 0) { A = &T.Keys[0]; B = nullptr; U = 0.f; return; }
		A = &T.Keys[Next - 1]; B = &T.Keys[Next];
		U = EaseAlpha(A->Ease, (Time - A->Time) / FMath::Max(B->Time - A->Time, 1e-4f));
	};
	for (const FOKSceneTrack& T : Tracks)
	{
		if (T.ObjectId != SceneTrackId || T.Keys.IsEmpty()) continue;
		const FOKSceneKey* A = nullptr; const FOKSceneKey* B = nullptr; float U = 0.f;
		Around(T, A, B, U);
		Post.Exposure = B ? FMath::Lerp(A->Exposure, B->Exposure, U) : A->Exposure;
		Post.FocalDistance = B ? FMath::Lerp(A->FocalDistance, B->FocalDistance, U) : A->FocalDistance;
		// The view cuts to the last key's camera at or before Time (before the first key: the first key's).
		const FOKSceneKey* Cut = nullptr;
		for (const FOKSceneKey& K : T.Keys)
			if (K.Camera >= -1 && (K.Camera == -1 || Find(K.Camera)) && (!Cut || K.Time <= Time)) Cut = &K;
		if (Cut) ActiveCamera = Cut->Camera;
		bAny = true;
	}
	for (const FOKSceneTrack& T : Tracks)
	{
		FOKSceneObject* O = Find(T.ObjectId);
		if (!O || T.Keys.IsEmpty()) continue;
		{
			// Light colour and a character's scrubbed animation time (keys that set them).
			const FOKSceneKey* A = nullptr; const FOKSceneKey* B = nullptr; float U = 0.f;
			Around(T, A, B, U);
			if (O->Kind == EOKSceneObjectKind::Light && A->Color.A >= 0.f) O->Light.Color = B && B->Color.A >= 0.f ? FMath::Lerp(A->Color, B->Color, U) : A->Color;
			if (O->Kind == EOKSceneObjectKind::Character) ApplyMotionKeys(O->Character, T, Time);
			if (O->Kind == EOKSceneObjectKind::Character && A->AnimTime >= 0.f)
			{
				O->Character.Speed = 0.f;
				// Times of two motions have nothing to blend.
				const bool bBlend = B && B->AnimTime >= 0.f && (A->AnimNo < 0 || B->AnimNo < 0 || A->SameMotion(*B));
				O->Character.Time = bBlend ? FMath::Lerp(A->AnimTime, B->AnimTime, U) : A->AnimTime;
			}
		}
		int32 Next = T.Keys.IndexOfByPredicate([Time](const FOKSceneKey& K) { return K.Time > Time; });
		FTransform X;
		float V;
		const bool bCharacter = O->Kind == EOKSceneObjectKind::Character;
		if (Next == INDEX_NONE) { const FOKSceneKey& K = T.Keys.Last(); X = K.Transform; V = K.Value; if (bCharacter) { O->Character.Fk = SampleTrackFk(T, Time); ApplyCharacterKey(O->Character, K, K.MouthOpen, K.Style, K.FaceStyle); } }
		else if (Next == 0) { const FOKSceneKey& K = T.Keys[0]; X = K.Transform; V = K.Value; if (bCharacter) { O->Character.Fk = SampleTrackFk(T, Time); ApplyCharacterKey(O->Character, K, K.MouthOpen, K.Style, K.FaceStyle); } }
		else
		{
			const FOKSceneKey& A = T.Keys[Next - 1];
			const FOKSceneKey& B = T.Keys[Next];
			const float U = EaseAlpha(A.Ease, (Time - A.Time) / FMath::Max(B.Time - A.Time, 1e-4f));
			if (T.bSmoothPath)
			{
				// Catmull-Rom through the keys (the ends repeat their key), so the path has no corners at keys.
				const FVector P0 = T.Keys[FMath::Max(Next - 2, 0)].Transform.GetLocation(), P1 = A.Transform.GetLocation(), P2 = B.Transform.GetLocation();
				const FVector P3 = T.Keys[FMath::Min(Next + 1, T.Keys.Num() - 1)].Transform.GetLocation();
				const float U2 = U * U, U3 = U2 * U;
				X.SetLocation(0.5f * (2.f * P1 + (P2 - P0) * U + (2.f * P0 - 5.f * P1 + 4.f * P2 - P3) * U2 + (3.f * P1 - P0 - 3.f * P2 + P3) * U3));
			}
			else X.SetLocation(FMath::Lerp(A.Transform.GetLocation(), B.Transform.GetLocation(), U));
			X.SetRotation(FQuat::Slerp(A.Transform.GetRotation(), B.Transform.GetRotation(), U));
			X.SetScale3D(FMath::Lerp(A.Transform.GetScale3D(), B.Transform.GetScale3D(), U));
			if (T.bOrbitPath && O->Kind == EOKSceneObjectKind::Camera) OrbitBetween(A.Transform, B.Transform, U, X);
			V = FMath::Lerp(A.Value, B.Value, U);
			if (bCharacter)
			{
				O->Character.Fk = SampleTrackFk(T, Time);
				// Patterns hold the earlier key's; the mouth opening blends when both keys set it.
				const float Mouth = A.MouthOpen >= 0.f && B.MouthOpen >= 0.f ? FMath::Lerp(A.MouthOpen, B.MouthOpen, U) : A.MouthOpen;
				const bool bStyles = A.Style >= -1.f && B.Style >= -1.f;
				ApplyCharacterKey(O->Character, A, Mouth, bStyles ? FMath::Lerp(A.Style, B.Style, U) : A.Style, bStyles ? FMath::Lerp(A.ShownFaceStyle(), B.ShownFaceStyle(), U) : A.FaceStyle);
				// A look point moves from key to key: two points, the head turns between them.
				if (A.LookEyes >= 0 && B.LookEyes >= 0 && A.LookNeck == B.LookNeck && A.LookEyes == B.LookEyes) O->Character.LookPoint = FMath::Lerp(A.LookPoint, B.LookPoint, U);
			}
		}
		O->Transform = X;
		SetKeyValue(*O, V);
		bAny = true;
	}
	if (!TimelineTracks.IsEmpty())
	{
		LastTimelineScale = 1.f;
		const float EvalTime = (bLoopTimeline && Duration > 1e-4f && Time >= 0.f) ? FMath::Fmod(Time, Duration) : Time;
		FVector OrbitPos = StudioCameraOrbitTarget;
		FVector OrbitRot = StudioCameraOrbitRot;
		FVector OrbitDist = StudioCameraOrbitDist;
		bool bOrbitTouched = false;
		bool bDirectCamPos = false, bDirectCamRot = false, bCamFov = false;
		FVector DirectCamPos = FVector::ZeroVector, DirectCamRotEuler = FVector::ZeroVector;
		float CamVertFov = 23.f;
		TMap<TPair<int32, FString>, FVector> GuideEulerAccum;
		TMap<TPair<int32, FString>, FVector> BoneEulerAccum;

		for (const FOKSceneTimelineTrack& Tr : TimelineTracks)
		{
			if (!Tr.bEnabled || Tr.Keyframes.IsEmpty()) continue;
			const int32 Next = Tr.Keyframes.IndexOfByPredicate([EvalTime](const FOKSceneTimelineKeyframe& K) { return K.Time > EvalTime; });
			const FOKSceneTimelineKeyframe* K0 = nullptr;
			const FOKSceneTimelineKeyframe* K1 = nullptr;
			float Factor = 0.f;
			if (Next == INDEX_NONE) { K0 = &Tr.Keyframes.Last(); }
			else if (Next == 0) { K0 = &Tr.Keyframes[0]; }
			else
			{
				K0 = &Tr.Keyframes[Next - 1];
				K1 = &Tr.Keyframes[Next];
				const float RawU = (EvalTime - K0->Time) / FMath::Max(K1->Time - K0->Time, 1e-5f);
				Factor = EvalTimelineCurve(K0->Curve, RawU);
			}
			if (K0->Values.IsEmpty()) continue;
			auto Sample1 = [&]() -> float
			{
				return K1 && K1->Values.Num() >= 1 ? FMath::Lerp(K0->Values[0], K1->Values[0], Factor) : K0->Values[0];
			};
			auto SampleAngleDeg = [&]() -> float
			{
				if (!K1 || K1->Values.Num() < 1) return K0->Values[0];
				const float Delta = FMath::FindDeltaAngleDegrees(K0->Values[0], K1->Values[0]);
				float Out = FMath::Fmod(K0->Values[0] + Delta * Factor, 360.f);
				if (Out < 0.f) Out += 360.f;
				return Out;
			};
			auto Sample3 = [&]() -> FVector
			{
				if (K0->Values.Num() < 3) return FVector::ZeroVector;
				const FVector A(K0->Values[0], K0->Values[1], K0->Values[2]);
				if (!K1 || K1->Values.Num() < 3) return A;
				return FMath::Lerp(A, FVector(K1->Values[0], K1->Values[1], K1->Values[2]), Factor);
			};
			auto SampleColor = [&]() -> FLinearColor
			{
				if (K0->Values.Num() < 4) return FLinearColor::White;
				const FLinearColor A(K0->Values[0], K0->Values[1], K0->Values[2], K0->Values[3]);
				if (!K1 || K1->Values.Num() < 4) return A;
				return FMath::Lerp(A, FLinearColor(K1->Values[0], K1->Values[1], K1->Values[2], K1->Values[3]), Factor);
			};

			if (Tr.Owner == TEXT("Timeline") && Tr.ObjectId < 0)
			{
				if (Tr.InterpolableId == TEXT("cameraOPos")) { OrbitPos = Sample3(); bOrbitTouched = true; bAny = true; }
				else if (Tr.InterpolableId == TEXT("cameraORot")) { OrbitRot = SampleUnityQuatSlerpEuler(K0->Values, K1 ? &K1->Values : nullptr, Factor); bOrbitTouched = true; bAny = true; }
				else if (Tr.InterpolableId == TEXT("cameraOZoom")) { OrbitDist.Z = Sample1(); bOrbitTouched = true; bAny = true; }
				else if (Tr.InterpolableId == TEXT("cameraPos")) { DirectCamPos = Sample3(); bDirectCamPos = true; bAny = true; }
				else if (Tr.InterpolableId == TEXT("cameraRot")) { DirectCamRotEuler = SampleUnityQuatSlerpEuler(K0->Values, K1 ? &K1->Values : nullptr, Factor); bDirectCamRot = true; bAny = true; }
				else if (Tr.InterpolableId == TEXT("cameraFOV")) { CamVertFov = Sample1(); bCamFov = true; bAny = true; }
				else if (Tr.InterpolableId == TEXT("timeScale")) { LastTimelineScale = FMath::Max(0.01f, Sample1()); bAny = true; }
				else if (Tr.InterpolableId == TEXT("cameraData") && K0->Values.Num() >= 10)
				{
					auto LerpIdx = [&](int32 Idx) -> float
					{
						return K1 && K1->Values.IsValidIndex(Idx) ? FMath::Lerp(K0->Values[Idx], K1->Values[Idx], Factor) : K0->Values[Idx];
					};
					auto LerpDegIdx = [&](int32 Idx) -> float
					{
						if (!K1 || !K1->Values.IsValidIndex(Idx)) return K0->Values[Idx];
						const float D = FMath::FindDeltaAngleDegrees(K0->Values[Idx], K1->Values[Idx]);
						float Out = FMath::Fmod(K0->Values[Idx] + D * Factor, 360.f);
						return Out < 0.f ? Out + 360.f : Out;
					};
					OrbitPos = FVector(LerpIdx(0), LerpIdx(1), LerpIdx(2));
					OrbitRot = FVector(LerpDegIdx(3), LerpDegIdx(4), LerpDegIdx(5));
					OrbitDist = FVector(LerpIdx(6), LerpIdx(7), LerpIdx(8));
					CamVertFov = LerpIdx(9);
					bOrbitTouched = true;
					bCamFov = true;
					bAny = true;
				}
				continue;
			}
			if (Tr.Owner == TEXT("NodesConstraints") && Tr.InterpolableId != TEXT("constraintEnabled"))
			{
				if (Tr.InterpolableId == TEXT("constraintPos"))
				{
					const float W = FMath::Clamp(Sample1(), 0.f, 1.f);
					for (FOKSceneConstraint& Con : Constraints)
						if (Con.LoadId == Tr.ParamInt) { Con.PosFactor = W; Con.bPosition = W > 1e-4f; bAny = true; }
				}
				else if (Tr.InterpolableId == TEXT("constraintRos") || Tr.InterpolableId == TEXT("constraintRot"))
				{
					const float W = FMath::Clamp(Sample1(), 0.f, 1.f);
					for (FOKSceneConstraint& Con : Constraints)
						if (Con.LoadId == Tr.ParamInt) { Con.RotFactor = W; Con.bRotation = W > 1e-4f; bAny = true; }
				}
				continue;
			}
			if (Tr.Owner == TEXT("NodesConstraints") && Tr.InterpolableId == TEXT("constraintEnabled"))
			{
				const bool bOn = K0->Values[0] > 0.5f;
				for (FOKSceneConstraint& Con : Constraints)
					if (Con.LoadId == Tr.ParamInt && Con.bEnabled != bOn) { Con.bEnabled = bOn; bAny = true; }
				continue;
			}

			FOKSceneObject* O = Find(Tr.ObjectId);
			if (!O) continue;
			bAny = true;

			if (Tr.Owner == TEXT("Timeline"))
			{
				if (Tr.InterpolableId == TEXT("objectEnabled") || Tr.InterpolableId == TEXT("lightOnOff"))
				{
					O->bVisible = K0->Values[0] > 0.5f;
				}
				else if (Tr.InterpolableId == TEXT("guideObjectPos"))
				{
					const FVector P = Sample3();
					if (Tr.TargetPath.IsEmpty()) O->Transform.SetLocation(FVector(-P.X, P.Z, P.Y) * 100.0);
					else if (Tr.TargetIkEffector >= 0 && O->Kind == EOKSceneObjectKind::Character)
					{
						FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Tr.TargetIkEffector; });
						if (!Ik) { Ik = &O->Character.Ik.AddDefaulted_GetRef(); Ik->Effector = Tr.TargetIkEffector; Ik->bUseRotation = (Tr.TargetIkEffector >= 5 && Tr.TargetIkEffector <= 8); }
						Ik->Position = FVector(-P.X, P.Z, P.Y) * 100.0;
					}
					else if (!Tr.TargetBone.IsEmpty())
					{
						if (O->Kind == EOKSceneObjectKind::Character) UpsertBoneOverride(O->Character.BoneOverrides, Tr.TargetBone, &P, nullptr, nullptr);
						else if (O->Kind == EOKSceneObjectKind::Item) UpsertBoneOverride(O->Item.BoneOverrides, Tr.TargetBone, &P, nullptr, nullptr);
					}
				}
				else if (Tr.InterpolableId == TEXT("guideObjectRot"))
				{
					const FVector Euler = SampleUnityQuatSlerpEuler(K0->Values, K1 ? &K1->Values : nullptr, Factor);
					if (Tr.TargetPath.IsEmpty())
					{
						FQuat Q = DocUnityToUe(FVector::ZeroVector, Euler, FVector::OneVector).GetRotation();
						if (O->Kind == EOKSceneObjectKind::Camera || O->Kind == EOKSceneObjectKind::Light)
							Q = Q * FQuat(FVector::UpVector, UE_HALF_PI);
						O->Transform.SetRotation(Q);
					}
					else if (Tr.TargetIkEffector >= 0 && O->Kind == EOKSceneObjectKind::Character)
					{
						FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Tr.TargetIkEffector; });
						if (!Ik) { Ik = &O->Character.Ik.AddDefaulted_GetRef(); Ik->Effector = Tr.TargetIkEffector; }
						Ik->Euler = Euler;
						Ik->bUseRotation = (Tr.TargetIkEffector >= 5 && Tr.TargetIkEffector <= 8);
					}
					else if (!Tr.TargetBone.IsEmpty())
					{
						if (O->Kind == EOKSceneObjectKind::Character)
						{
							FOKSceneFkBone* Fk = O->Character.Fk.FindByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == Tr.TargetBone; });
							if (!Fk) { Fk = &O->Character.Fk.AddDefaulted_GetRef(); Fk->Bone = Tr.TargetBone; }
							Fk->Euler = Euler;
						}
						else if (O->Kind == EOKSceneObjectKind::Item)
						{
							FOKSceneFkBone* Fk = O->Item.Fk.FindByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == Tr.TargetBone; });
							if (!Fk) { Fk = &O->Item.Fk.AddDefaulted_GetRef(); Fk->Bone = Tr.TargetBone; }
							Fk->Euler = Euler;
						}
					}
				}
				else if (Tr.InterpolableId == TEXT("guideObjectScale"))
				{
					const FVector S = Sample3();
					if (Tr.TargetPath.IsEmpty()) O->Transform.SetScale3D(FVector(S.X, S.Z, S.Y));
					else if (!Tr.TargetBone.IsEmpty())
					{
						if (O->Kind == EOKSceneObjectKind::Character) UpsertBoneOverride(O->Character.BoneOverrides, Tr.TargetBone, nullptr, nullptr, &S);
						else if (O->Kind == EOKSceneObjectKind::Item) UpsertBoneOverride(O->Item.BoneOverrides, Tr.TargetBone, nullptr, nullptr, &S);
					}
				}
				else if (O->Kind == EOKSceneObjectKind::Light)
				{
					if (Tr.InterpolableId == TEXT("lightColor")) O->Light.Color = SampleColor();
					else if (Tr.InterpolableId == TEXT("lightStrength")) O->Light.Intensity = FMath::Max(0.f, Sample1()) * (O->Light.Type == EOKSceneLightType::Directional ? 4.f : 800.f);
					else if (Tr.InterpolableId == TEXT("lightRange")) O->Light.Range = FMath::Max(1.f, Sample1() * 100.f);
					else if (Tr.InterpolableId == TEXT("lightSpotAngle")) O->Light.SpotAngle = FMath::Clamp(Sample1(), 1.f, 80.f);
					else if (Tr.InterpolableId == TEXT("lightShadows")) O->Light.bShadows = K0->Values[0] > 0.5f;
				}
				else if (O->Kind == EOKSceneObjectKind::Character)
				{
					if (Tr.InterpolableId == TEXT("objectAnimationSpeed")) O->Character.Speed = FMath::Max(0.f, Sample1());
					else if (Tr.InterpolableId == TEXT("charAnimationTime")) { O->Character.Speed = 0.f; O->Character.Time = FMath::Max(0.f, Sample1()); }
					else if (Tr.InterpolableId == TEXT("charAnimationPattern"))
					{
						FOKSceneAnimFloat* Af = O->Character.AnimFloats.FindByPredicate([](const FOKSceneAnimFloat& F) { return F.Name == TEXT("pattern"); });
						if (!Af) { Af = &O->Character.AnimFloats.AddDefaulted_GetRef(); Af->Name = TEXT("pattern"); }
						Af->Value = FMath::Clamp(Sample1(), 0.f, 1.f);
					}
					else if (Tr.InterpolableId == TEXT("characterEyes")) O->Character.EyesPattern = FMath::RoundToInt(K0->Values[0]);
					else if (Tr.InterpolableId == TEXT("characterEyesOpen")) O->Character.EyesOpen = FMath::Clamp(Sample1(), 0.f, 1.f);
					else if (Tr.InterpolableId == TEXT("characterEyebrows")) O->Character.EyebrowPattern = FMath::RoundToInt(K0->Values[0]);
					else if (Tr.InterpolableId == TEXT("characterMouth")) O->Character.MouthPattern = FMath::RoundToInt(K0->Values[0]);
					else if (Tr.InterpolableId == TEXT("characterMouthOpen")) O->Character.MouthOpen = FMath::Clamp(Sample1(), 0.f, 1.f);
					else if (Tr.InterpolableId == TEXT("characterLeftHand")) { const int32 N = FMath::RoundToInt(K0->Values[0]); O->Character.HandLeft = N <= 0 ? -1 : FMath::Min(N, 23); }
					else if (Tr.InterpolableId == TEXT("characterRightHand")) { const int32 N = FMath::RoundToInt(K0->Values[0]); O->Character.HandRight = N <= 0 ? -1 : FMath::Min(N, 23); }
					else if (Tr.InterpolableId == TEXT("blush")) O->Character.Blush = FMath::Clamp(Sample1(), 0.f, 1.f);
					else if (Tr.InterpolableId == TEXT("tears")) O->Character.TearsLevel = FMath::Clamp(FMath::RoundToInt(K0->Values[0]), 0, 3);
					else if (Tr.InterpolableId == TEXT("femaleNipples")) O->Character.NipStand = FMath::Clamp(Sample1(), 0.f, 1.f);
					else if (Tr.InterpolableId == TEXT("characterEyebrowsOpen")) O->Character.EyebrowsOpen = FMath::Clamp(Sample1(), 0.f, 1.f);
					else if (Tr.InterpolableId == TEXT("characterNeck"))
					{
						const int32 Mode = FMath::Clamp(FMath::RoundToInt(K0->Values[0]), 0, 4);
						O->Character.NeckLook = Mode == 0 ? EOKSceneLook::Animation : Mode == 1 ? EOKSceneLook::Camera : Mode == 2 ? EOKSceneLook::Away : Mode == 3 ? EOKSceneLook::Fixed : EOKSceneLook::Point;
					}
					else if (Tr.InterpolableId == TEXT("charAnimation") && K0->Values.Num() >= 3)
					{
						const int32 Grp = FMath::RoundToInt(K0->Values[0]);
						const int32 Cat = FMath::RoundToInt(K0->Values[1]);
						const int32 No = FMath::RoundToInt(K0->Values[2]);
						const int32 Kind = FOKStudioCatalog::Get().FindAnim(0, Grp, Cat, No) ? 0 : (FOKStudioCatalog::Get().FindAnim(1, Grp, Cat, No) ? 1 : O->Character.StudioAnimeKind);
						O->Character.StudioAnimeKind = Kind;
						O->Character.StudioAnimeGroup = Grp;
						O->Character.StudioAnimeCategory = Cat;
						O->Character.StudioAnimeNo = No;
					}
					else if (Tr.InterpolableId == TEXT("juice") && Tr.ParamInt >= 0 && Tr.ParamInt < 5)
					{
						if (O->Character.Fluids.Num() < 5) O->Character.Fluids.Init(0, 5);
						O->Character.Fluids[Tr.ParamInt] = uint8(FMath::Clamp(FMath::RoundToInt(K0->Values[0]), 0, 2));
					}
					else if (Tr.InterpolableId == TEXT("charClothes") && O->Character.ClothesStates.IsValidIndex(Tr.ParamInt))
					{
						const uint8 St = uint8(FMath::Clamp(FMath::RoundToInt(K0->Values[0]), 0, 3));
						O->Character.ClothesStates[Tr.ParamInt] = St;
						if (Tr.ParamInt == 7 && O->Character.ClothesStates.IsValidIndex(8)) O->Character.ClothesStates[8] = St;
					}
				}
				else if (O->Kind == EOKSceneObjectKind::Item)
				{
					if (Tr.InterpolableId == TEXT("objectAnimationSpeed")) O->Item.AnimeSpeed = FMath::Max(0.f, Sample1());
					else if (Tr.InterpolableId == TEXT("itemAnimationTime")) { O->Item.AnimeSpeed = 0.f; O->Item.AnimeTime = FMath::Max(0.f, Sample1()); }
					else if (Tr.InterpolableId == TEXT("itemAlpha")) O->Item.Alpha = FMath::Clamp(Sample1(), 0.f, 1.f);
					else if (Tr.InterpolableId == TEXT("itemShadowColor")) O->Item.ShadowColor = SampleColor();
					else if (Tr.InterpolableId == TEXT("itemEmissionColor")) O->Item.EmissionColor = SampleColor();
					else if (Tr.InterpolableId == TEXT("itemEmissionPower")) O->Item.EmissionPower = Sample1();
					else if (Tr.InterpolableId == TEXT("itemLightCancel")) O->Item.LightCancel = Sample1();
					else if (Tr.InterpolableId == TEXT("itemLineWidth")) O->Item.LineWidth = FMath::Max(0.f, Sample1());
					else if (Tr.InterpolableId == TEXT("itemLineColor")) O->Item.LineColor = SampleColor();
					else if (Tr.InterpolableId == TEXT("itemPanelColor"))
					{
						if (O->Item.Colors.IsEmpty()) O->Item.Colors.Add(FLinearColor::White);
						O->Item.Colors[0] = SampleColor();
					}
					else if (Tr.InterpolableId.StartsWith(TEXT("itemPattern")) || Tr.InterpolableId.StartsWith(TEXT("itemPanelPattern")))
					{
						const bool bPanel = Tr.InterpolableId.StartsWith(TEXT("itemPanelPattern"));
						const int32 Slot = bPanel ? 0 : (Tr.InterpolableId[Tr.InterpolableId.Len() - 1] - TEXT('1'));
						if (Slot >= 0 && Slot < 3)
						{
							while (O->Item.Patterns.Num() <= Slot) O->Item.Patterns.AddDefaulted();
							FOKSceneItemPattern& Pat = O->Item.Patterns[Slot];
							const FString Core = bPanel ? Tr.InterpolableId.Mid(16) : Tr.InterpolableId.Mid(11, Tr.InterpolableId.Len() - 12);
							if (Core == TEXT("Color")) Pat.Color = SampleColor();
							else if (Core == TEXT("Clamp")) Pat.bClamp = K0->Values[0] > 0.5f;
							else if (Core == TEXT("UOffset")) Pat.Uv.X = Sample1();
							else if (Core == TEXT("VOffset")) Pat.Uv.Y = Sample1();
							else if (Core == TEXT("UTiling")) Pat.Uv.Z = Sample1();
							else if (Core == TEXT("VTiling")) Pat.Uv.W = Sample1();
							else if (Core == TEXT("Rot")) Pat.Rotation = Sample1();
						}
					}
					else if (Tr.InterpolableId.StartsWith(TEXT("itemColor")) && Tr.InterpolableId.Len() == 10)
					{
						const int32 Slot = Tr.InterpolableId[9] - TEXT('1');
						if (Slot >= 0 && Slot < 4)
						{
							while (O->Item.Colors.Num() <= Slot) O->Item.Colors.Add(FLinearColor(1.f, 1.f, 1.f, -1.f));
							O->Item.Colors[Slot] = SampleColor();
						}
					}
				}
			}
			else if (Tr.Owner == TEXT("KKPE"))
			{
				TArray<FOKSceneBoneTrs>* Bones = O->Kind == EOKSceneObjectKind::Character ? &O->Character.BoneOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.BoneOverrides : nullptr);
				TArray<FOKSceneMorphOverride>* Morphs = O->Kind == EOKSceneObjectKind::Character ? &O->Character.MorphOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.MorphOverrides : nullptr);
				if (Bones && !Tr.TargetBone.IsEmpty())
				{
					if (Tr.InterpolableId == TEXT("bonePos")) { const FVector P = Sample3(); UpsertBoneOverride(*Bones, Tr.TargetBone, &P, nullptr, nullptr); }
					else if (Tr.InterpolableId == TEXT("boneRot")) { const FVector E = SampleUnityQuatSlerpEuler(K0->Values, K1 ? &K1->Values : nullptr, Factor); UpsertBoneOverride(*Bones, Tr.TargetBone, nullptr, &E, nullptr); }
					else if (Tr.InterpolableId == TEXT("boneScale")) { const FVector S = Sample3(); UpsertBoneOverride(*Bones, Tr.TargetBone, nullptr, nullptr, &S); }
				}
				if (O->Kind == EOKSceneObjectKind::Character)
				{
					if (Tr.InterpolableId == TEXT("fbbikWeight"))
					{
						O->Character.IkWeight = FMath::Clamp(Sample1(), 0.f, 1.f);
					}
					else if (Tr.TargetIkEffector >= 0 && Tr.InterpolableId.StartsWith(TEXT("fbbik")))
					{
						FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Tr.TargetIkEffector; });
						if (!Ik) { Ik = &O->Character.Ik.AddDefaulted_GetRef(); Ik->Effector = Tr.TargetIkEffector; }
						const float W = FMath::Clamp(Sample1(), 0.f, 1.f);
						if (Tr.InterpolableId.StartsWith(TEXT("fbbikEffectorRotationWeight")))
						{
							Ik->RotationWeight = W;
							Ik->bUseRotation = W > 1e-4f;
						}
						else
						{
							Ik->Weight = W;
						}
					}
				}
				if (Morphs && !Tr.TargetPath.IsEmpty())
				{
					if (Tr.InterpolableId == TEXT("lastBlendShape") && Tr.ParamInt >= 0)
					{
						UpsertMorphOverride(*Morphs, Tr.TargetPath, Tr.ParamInt, FString(), Sample1());
					}
					else if (Tr.InterpolableId == TEXT("groupBlendShape") || Tr.InterpolableId == TEXT("groupBlendShapeLink"))
					{
						for (int32 M = 0; M < K0->Values.Num(); ++M)
						{
							const float W = K1 && K1->Values.IsValidIndex(M) ? FMath::Lerp(K0->Values[M], K1->Values[M], Factor) : K0->Values[M];
							const FString Nm = K0->Names.IsValidIndex(M) ? K0->Names[M] : FString();
							UpsertMorphOverride(*Morphs, Tr.TargetPath, M, Nm, W);
						}
					}
				}
			}
			else if (Tr.Owner == TEXT("RendererEditor"))
			{
				const FString Prop = !Tr.ParamStr.IsEmpty() ? Tr.ParamStr : Tr.InterpolableId;
				if (Tr.InterpolableId == TEXT("targetEnabled"))
				{
					const FString Rend = DocLeafNodeName(Tr.TargetPath);
					if (!Rend.IsEmpty()) UpsertLiveMaterialEdit(O->LiveMaterialEdits, Rend, TEXT("Enabled"), EOKSceneMaterialEditKind::Renderer, FLinearColor(K0->Values[0] > 0.5f ? 1.f : 0.f, 0.f, 0.f, 0.f));
				}
				else if (Tr.InterpolableId.StartsWith(TEXT("Float_")))
				{
					UpsertLiveMaterialEdit(O->LiveMaterialEdits, FString(), Prop, EOKSceneMaterialEditKind::Float, FLinearColor(Sample1(), 0.f, 0.f, 0.f));
				}
				else if (Tr.InterpolableId.StartsWith(TEXT("Color_")))
				{
					UpsertLiveMaterialEdit(O->LiveMaterialEdits, FString(), Prop, EOKSceneMaterialEditKind::Color, SampleColor());
				}
				else if (Tr.InterpolableId.StartsWith(TEXT("Vector_")))
				{
					UpsertLiveMaterialEdit(O->LiveMaterialEdits, FString(), Prop, EOKSceneMaterialEditKind::Vector, SampleColor());
				}
				else if ((Tr.InterpolableId.StartsWith(TEXT("TextureScale_")) || Tr.InterpolableId.StartsWith(TEXT("TextureOffset_"))) && K0->Values.Num() >= 2)
				{
					const float Vx = K1 && K1->Values.Num() >= 2 ? FMath::Lerp(K0->Values[0], K1->Values[0], Factor) : K0->Values[0];
					const float Vy = K1 && K1->Values.Num() >= 2 ? FMath::Lerp(K0->Values[1], K1->Values[1], Factor) : K0->Values[1];
					FOKSceneMaterialEdit* Existing = O->LiveMaterialEdits.FindByPredicate([&](const FOKSceneMaterialEdit& E) { return E.Material.IsEmpty() && E.Property == Prop && E.Kind == EOKSceneMaterialEditKind::TextureST; });
					FLinearColor St = Existing ? Existing->Value : FLinearColor(1.f, 1.f, 0.f, 0.f);
					if (Tr.InterpolableId.StartsWith(TEXT("TextureScale_"))) { St.R = Vx; St.G = Vy; }
					else { St.B = Vx; St.A = Vy; }
					UpsertLiveMaterialEdit(O->LiveMaterialEdits, FString(), Prop, EOKSceneMaterialEditKind::TextureST, St);
				}
			}
			else if (Tr.Owner == TEXT("MaterialEditor"))
			{
				TArray<FString> Parts;
				Tr.ParamStr.ParseIntoArray(Parts, TEXT("|"), false);
				const FString Mat = Parts.IsValidIndex(0) ? Parts[0] : FString();
				const FString Prop = Parts.IsValidIndex(1) ? Parts[1] : FString();
				if (!Prop.IsEmpty())
				{
					if (Tr.InterpolableId == TEXT("floatProperty"))
						UpsertLiveMaterialEdit(O->LiveMaterialEdits, Mat, Prop, EOKSceneMaterialEditKind::Float, FLinearColor(Sample1(), 0.f, 0.f, 0.f));
					else if (Tr.InterpolableId == TEXT("colorProperty"))
						UpsertLiveMaterialEdit(O->LiveMaterialEdits, Mat, Prop, EOKSceneMaterialEditKind::Color, SampleColor());
					else if ((Tr.InterpolableId == TEXT("textureScaleProperty") || Tr.InterpolableId == TEXT("textureOffsetProperty")) && K0->Values.Num() >= 2)
					{
						const float Vx = K1 && K1->Values.Num() >= 2 ? FMath::Lerp(K0->Values[0], K1->Values[0], Factor) : K0->Values[0];
						const float Vy = K1 && K1->Values.Num() >= 2 ? FMath::Lerp(K0->Values[1], K1->Values[1], Factor) : K0->Values[1];
						FOKSceneMaterialEdit* Existing = O->LiveMaterialEdits.FindByPredicate([&](const FOKSceneMaterialEdit& E) { return E.Material == Mat && E.Property == Prop && E.Kind == EOKSceneMaterialEditKind::TextureST; });
						FLinearColor St = Existing ? Existing->Value : FLinearColor(1.f, 1.f, 0.f, 0.f);
						if (Tr.InterpolableId == TEXT("textureScaleProperty")) { St.R = Vx; St.G = Vy; }
						else { St.B = Vx; St.A = Vy; }
						UpsertLiveMaterialEdit(O->LiveMaterialEdits, Mat, Prop, EOKSceneMaterialEditKind::TextureST, St);
					}
				}
			}
			else if (Tr.Owner == TEXT("PregnancyPlus") && O->Kind == EOKSceneObjectKind::Character)
			{
				const float Inflation = FMath::Clamp(Sample1(), -10.f, 40.f);
				const float ScaleFactor = FMath::Max(0.5f, 1.f + Inflation * 0.022f);
				const FVector BellyScale(ScaleFactor, 1.f + Inflation * 0.008f, ScaleFactor);
				UpsertBoneOverride(O->Character.BoneOverrides, TEXT("cf_s_waist01"), nullptr, nullptr, &BellyScale);
			}
			else if (Tr.Owner == TEXT("ShalltyUtils"))
			{
				auto AxisOf = [](const FString& Id, const TCHAR* Prefix) -> int32
				{
					if (Id == FString::Printf(TEXT("%sXPos"), Prefix) || Id == FString::Printf(TEXT("%sXRot"), Prefix) || Id == FString::Printf(TEXT("%sXScale"), Prefix)) return 0;
					if (Id == FString::Printf(TEXT("%sYPos"), Prefix) || Id == FString::Printf(TEXT("%sYRot"), Prefix) || Id == FString::Printf(TEXT("%sYScale"), Prefix)) return 1;
					if (Id == FString::Printf(TEXT("%sZPos"), Prefix) || Id == FString::Printf(TEXT("%sZRot"), Prefix) || Id == FString::Printf(TEXT("%sZScale"), Prefix)) return 2;
					return -1;
				};
				const int32 GuideAxis = AxisOf(Tr.InterpolableId, TEXT("guideObject"));
				const int32 BoneAxis = AxisOf(Tr.InterpolableId, TEXT("bone"));
				if (GuideAxis >= 0 && Tr.InterpolableId.EndsWith(TEXT("Pos")))
				{
					const float Val = Sample1();
					if (Tr.TargetPath.IsEmpty())
					{
						FVector LocUe = O->Transform.GetLocation();
						if (GuideAxis == 0) LocUe.X = -Val * 100.0;
						else if (GuideAxis == 1) LocUe.Z = Val * 100.0;
						else LocUe.Y = Val * 100.0;
						O->Transform.SetLocation(LocUe);
					}
					else if (Tr.TargetIkEffector >= 0 && O->Kind == EOKSceneObjectKind::Character)
					{
						FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Tr.TargetIkEffector; });
						if (!Ik) { Ik = &O->Character.Ik.AddDefaulted_GetRef(); Ik->Effector = Tr.TargetIkEffector; Ik->bUseRotation = (Tr.TargetIkEffector >= 5 && Tr.TargetIkEffector <= 8); }
						if (GuideAxis == 0) Ik->Position.X = -Val * 100.0;
						else if (GuideAxis == 1) Ik->Position.Z = Val * 100.0;
						else Ik->Position.Y = Val * 100.0;
					}
					else if (!Tr.TargetBone.IsEmpty())
					{
						TArray<FOKSceneBoneTrs>* Bones = O->Kind == EOKSceneObjectKind::Character ? &O->Character.BoneOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.BoneOverrides : nullptr);
						if (Bones)
						{
							FOKSceneBoneTrs* Entry = Bones->FindByPredicate([&](const FOKSceneBoneTrs& B) { return B.Bone == Tr.TargetBone; });
							FVector P = (Entry && Entry->bHasPos) ? Entry->Pos : FVector::ZeroVector;
							P[GuideAxis] = Val;
							UpsertBoneOverride(*Bones, Tr.TargetBone, &P, nullptr, nullptr);
						}
					}
				}
				else if (GuideAxis >= 0 && Tr.InterpolableId.EndsWith(TEXT("Rot")))
				{
					const float Deg = SampleAngleDeg();
					const TPair<int32, FString> Key(Tr.ObjectId, Tr.TargetPath);
					if (Tr.TargetPath.IsEmpty())
					{
						FVector* Cached = GuideEulerAccum.Find(Key);
						if (!Cached)
						{
							FQuat Q = O->Transform.GetRotation();
							if (O->Kind == EOKSceneObjectKind::Camera || O->Kind == EOKSceneObjectKind::Light)
								Q = Q * FQuat(FVector::UpVector, -UE_HALF_PI);
							Q.Normalize();
							const float Uq[4] = { float(-Q.X), float(Q.Z), float(Q.Y), float(Q.W) };
							float InitEuler[3] = { 0.f, 0.f, 0.f };
							ok_unity_quat_to_euler(Uq, InitEuler);
							Cached = &GuideEulerAccum.Add(Key, FVector(InitEuler[0], InitEuler[1], InitEuler[2]));
						}
						(*Cached)[GuideAxis] = Deg;
						FQuat QOut = DocUnityToUe(FVector::ZeroVector, *Cached, FVector::OneVector).GetRotation();
						if (O->Kind == EOKSceneObjectKind::Camera || O->Kind == EOKSceneObjectKind::Light)
							QOut = QOut * FQuat(FVector::UpVector, UE_HALF_PI);
						O->Transform.SetRotation(QOut);
					}
					else if (Tr.TargetIkEffector >= 0 && O->Kind == EOKSceneObjectKind::Character)
					{
						FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Tr.TargetIkEffector; });
						if (!Ik) { Ik = &O->Character.Ik.AddDefaulted_GetRef(); Ik->Effector = Tr.TargetIkEffector; }
						Ik->Euler[GuideAxis] = Deg;
						Ik->bUseRotation = (Tr.TargetIkEffector >= 5 && Tr.TargetIkEffector <= 8);
					}
					else if (!Tr.TargetBone.IsEmpty())
					{
						TArray<FOKSceneFkBone>* FkArr = O->Kind == EOKSceneObjectKind::Character ? &O->Character.Fk : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.Fk : nullptr);
						if (FkArr)
						{
							FOKSceneFkBone* Fk = FkArr->FindByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == Tr.TargetBone; });
							if (!Fk) { Fk = &FkArr->AddDefaulted_GetRef(); Fk->Bone = Tr.TargetBone; }
							Fk->Euler[GuideAxis] = Deg;
						}
					}
				}
				else if (GuideAxis >= 0 && Tr.InterpolableId.EndsWith(TEXT("Scale")))
				{
					const float Val = Sample1();
					if (Tr.TargetPath.IsEmpty())
					{
						FVector ScaleUe = O->Transform.GetScale3D();
						if (GuideAxis == 0) ScaleUe.X = Val;
						else if (GuideAxis == 1) ScaleUe.Z = Val;
						else ScaleUe.Y = Val;
						O->Transform.SetScale3D(ScaleUe);
					}
					else if (!Tr.TargetBone.IsEmpty())
					{
						TArray<FOKSceneBoneTrs>* Bones = O->Kind == EOKSceneObjectKind::Character ? &O->Character.BoneOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.BoneOverrides : nullptr);
						if (Bones)
						{
							FOKSceneBoneTrs* Entry = Bones->FindByPredicate([&](const FOKSceneBoneTrs& B) { return B.Bone == Tr.TargetBone; });
							FVector S = (Entry && Entry->bHasScale) ? Entry->Scale : FVector::OneVector;
							S[GuideAxis] = Val;
							UpsertBoneOverride(*Bones, Tr.TargetBone, nullptr, nullptr, &S);
						}
					}
				}
				else if (BoneAxis >= 0 && !Tr.TargetBone.IsEmpty())
				{
					TArray<FOKSceneBoneTrs>* Bones = O->Kind == EOKSceneObjectKind::Character ? &O->Character.BoneOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.BoneOverrides : nullptr);
					if (Bones)
					{
						FOKSceneBoneTrs* Entry = Bones->FindByPredicate([&](const FOKSceneBoneTrs& B) { return B.Bone == Tr.TargetBone; });
						if (Tr.InterpolableId.EndsWith(TEXT("Pos")))
						{
							FVector P = (Entry && Entry->bHasPos) ? Entry->Pos : FVector::ZeroVector;
							P[BoneAxis] = Sample1();
							UpsertBoneOverride(*Bones, Tr.TargetBone, &P, nullptr, nullptr);
						}
						else if (Tr.InterpolableId.EndsWith(TEXT("Rot")))
						{
							const TPair<int32, FString> Key(Tr.ObjectId, Tr.TargetBone);
							FVector* Cached = BoneEulerAccum.Find(Key);
							if (!Cached)
							{
								const FVector InitE = (Entry && Entry->bHasRot) ? Entry->Euler : FVector::ZeroVector;
								Cached = &BoneEulerAccum.Add(Key, InitE);
							}
							(*Cached)[BoneAxis] = SampleAngleDeg();
							UpsertBoneOverride(*Bones, Tr.TargetBone, nullptr, Cached, nullptr);
						}
						else if (Tr.InterpolableId.EndsWith(TEXT("Scale")))
						{
							FVector S = (Entry && Entry->bHasScale) ? Entry->Scale : FVector::OneVector;
							S[BoneAxis] = Sample1();
							UpsertBoneOverride(*Bones, Tr.TargetBone, nullptr, nullptr, &S);
						}
					}
				}
			}
		}

		if (bOrbitTouched || bDirectCamPos || bDirectCamRot || bCamFov)
		{
			const int32 CamId = StudioCameraId >= 0 ? StudioCameraId : ActiveCamera;
			if (FOKSceneObject* CamObj = Find(CamId); CamObj && CamObj->Kind == EOKSceneObjectKind::Camera)
			{
				const FQuat CamTurn(FVector::UpVector, UE_HALF_PI);
				const FQuat LightChild = DocUnityToUe(FVector::ZeroVector, FVector(40.f, 180.f, 0.f), FVector::OneVector).GetRotation();
				FVector EffectiveCamRot = OrbitRot;
				bool bHasCamEuler = false;
				if (bOrbitTouched)
				{
					StudioCameraOrbitTarget = OrbitPos;
					StudioCameraOrbitRot = OrbitRot;
					StudioCameraOrbitDist = OrbitDist;
					const FTransform Base = DocUnityToUe(OrbitPos, OrbitRot, FVector::OneVector);
					CamObj->Transform.SetRotation(Base.GetRotation() * CamTurn);
					CamObj->Transform.SetLocation(Base.GetLocation() + Base.GetRotation().RotateVector(FVector(-OrbitDist.X, OrbitDist.Z, OrbitDist.Y) * 100.0));
					bHasCamEuler = true;
				}
				if (bDirectCamPos) CamObj->Transform.SetLocation(FVector(-DirectCamPos.X, DirectCamPos.Z, DirectCamPos.Y) * 100.0);
				if (bDirectCamRot)
				{
					const FQuat BaseRot = DocUnityToUe(FVector::ZeroVector, DirectCamRotEuler, FVector::OneVector).GetRotation();
					CamObj->Transform.SetRotation(BaseRot * CamTurn);
					EffectiveCamRot = DirectCamRotEuler;
					bHasCamEuler = true;
				}
				if (bCamFov)
				{
					const double VertRad = FMath::DegreesToRadians(FMath::Clamp(double(CamVertFov), 1.0, 170.0));
					CamObj->Camera.Fov = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(VertRad * 0.5) * 16.0 / 9.0)));
				}
				if (bHasCamEuler && bLinkCharaLightToCamera && CharaLightId >= 0)
				{
					if (FOKSceneObject* LightObj = Find(CharaLightId); LightObj && LightObj->Kind == EOKSceneObjectKind::Light)
					{
						const FVector LightEuler = DocComputeLinkedCharaLightEuler(LinkedLightBase, LinkedCameraBase, FVector2D(EffectiveCamRot.X, EffectiveCamRot.Y));
						const FQuat LightShine = DocUnityToUe(FVector::ZeroVector, LightEuler, FVector::OneVector).GetRotation() * LightChild * CamTurn;
						LightObj->Transform.SetRotation(LightShine);
					}
				}
			}
		}
	}
	if (bAny) NotifyChanged();
}

FString UOKSceneDocument::DescribeTimelineTrack(const FOKSceneTimelineTrack& Track) const
{
	const FOKSceneObject* Obj = Track.ObjectId >= 0 ? Find(Track.ObjectId) : nullptr;
	const FString TargetLabel = Obj ? Obj->Name : (Track.ObjectId < 0 ? TEXT("全局/镜头") : FString::Printf(TEXT("#%d"), Track.ObjectId));
	if (!Track.Alias.IsEmpty())
	{
		return FString::Printf(TEXT("[%s] %s"), *TargetLabel, *Track.Alias);
	}
	FString PropLabel = Track.InterpolableId;
	if (Track.Owner == TEXT("Timeline"))
	{
		if (Track.InterpolableId == TEXT("cameraOPos")) PropLabel = TEXT("镜头环绕焦点");
		else if (Track.InterpolableId == TEXT("cameraORot")) PropLabel = TEXT("镜头环绕旋转");
		else if (Track.InterpolableId == TEXT("cameraOZoom")) PropLabel = TEXT("镜头环绕推拉");
		else if (Track.InterpolableId == TEXT("cameraPos")) PropLabel = TEXT("镜头坐标");
		else if (Track.InterpolableId == TEXT("cameraRot")) PropLabel = TEXT("镜头旋转");
		else if (Track.InterpolableId == TEXT("cameraFOV")) PropLabel = TEXT("镜头视场角 FOV");
		else if (Track.InterpolableId == TEXT("cameraData")) PropLabel = TEXT("镜头全参数");
		else if (Track.InterpolableId == TEXT("timeScale")) PropLabel = TEXT("时间轴倍速");
		else if (Track.InterpolableId == TEXT("guideObjectPos")) PropLabel = Track.TargetPath.IsEmpty() ? TEXT("位置") : FString::Printf(TEXT("节点位置 (%s)"), *DocLeafNodeName(Track.TargetPath));
		else if (Track.InterpolableId == TEXT("guideObjectRot")) PropLabel = Track.TargetPath.IsEmpty() ? TEXT("旋转") : FString::Printf(TEXT("节点旋转 (%s)"), *DocLeafNodeName(Track.TargetPath));
		else if (Track.InterpolableId == TEXT("guideObjectScale")) PropLabel = Track.TargetPath.IsEmpty() ? TEXT("缩放") : FString::Printf(TEXT("节点缩放 (%s)"), *DocLeafNodeName(Track.TargetPath));
		else if (Track.InterpolableId == TEXT("objectEnabled")) PropLabel = TEXT("显隐开关");
		else if (Track.InterpolableId == TEXT("objectAnimationSpeed")) PropLabel = TEXT("动作速度");
		else if (Track.InterpolableId == TEXT("charAnimation")) PropLabel = TEXT("角色动作切换");
		else if (Track.InterpolableId == TEXT("charAnimationTime")) PropLabel = TEXT("角色动作时间");
		else if (Track.InterpolableId == TEXT("charAnimationPattern")) PropLabel = TEXT("动作混合 Pattern");
		else if (Track.InterpolableId == TEXT("characterEyes")) PropLabel = TEXT("眼型");
		else if (Track.InterpolableId == TEXT("characterEyesOpen")) PropLabel = TEXT("眨眼开合");
		else if (Track.InterpolableId == TEXT("characterEyebrows")) PropLabel = TEXT("眉型");
		else if (Track.InterpolableId == TEXT("characterEyebrowsOpen")) PropLabel = TEXT("眉毛高度");
		else if (Track.InterpolableId == TEXT("characterMouth")) PropLabel = TEXT("嘴型");
		else if (Track.InterpolableId == TEXT("characterMouthOpen")) PropLabel = TEXT("嘴巴开合");
		else if (Track.InterpolableId == TEXT("characterNeck")) PropLabel = TEXT("颈部朝向模式");
		else if (Track.InterpolableId == TEXT("characterLeftHand")) PropLabel = TEXT("左手手势");
		else if (Track.InterpolableId == TEXT("characterRightHand")) PropLabel = TEXT("右手手势");
		else if (Track.InterpolableId == TEXT("blush")) PropLabel = TEXT("脸红");
		else if (Track.InterpolableId == TEXT("tears")) PropLabel = TEXT("眼泪等级");
		else if (Track.InterpolableId == TEXT("femaleNipples")) PropLabel = TEXT("胸部激凸");
		else if (Track.InterpolableId == TEXT("charClothes")) PropLabel = FString::Printf(TEXT("服装状态 #%d"), Track.ParamInt + 1);
		else if (Track.InterpolableId == TEXT("juice")) PropLabel = FString::Printf(TEXT("液体等级 #%d"), Track.ParamInt + 1);
		else if (Track.InterpolableId == TEXT("lightOnOff")) PropLabel = TEXT("灯光开关");
		else if (Track.InterpolableId == TEXT("lightColor")) PropLabel = TEXT("灯光颜色");
		else if (Track.InterpolableId == TEXT("lightStrength")) PropLabel = TEXT("灯光强度");
		else if (Track.InterpolableId == TEXT("lightRange")) PropLabel = TEXT("灯光范围");
		else if (Track.InterpolableId == TEXT("lightSpotAngle")) PropLabel = TEXT("聚光角度");
		else if (Track.InterpolableId == TEXT("lightShadows")) PropLabel = TEXT("灯光阴影");
		else if (Track.InterpolableId == TEXT("itemAlpha")) PropLabel = TEXT("道具透明度");
		else if (Track.InterpolableId == TEXT("itemEmissionColor")) PropLabel = TEXT("自发光颜色");
		else if (Track.InterpolableId == TEXT("itemEmissionPower")) PropLabel = TEXT("自发光强度");
		else if (Track.InterpolableId == TEXT("itemShadowColor")) PropLabel = TEXT("阴影颜色");
		else if (Track.InterpolableId == TEXT("itemLightCancel")) PropLabel = TEXT("受光抵消");
		else if (Track.InterpolableId == TEXT("itemLineWidth")) PropLabel = TEXT("描边粗细");
		else if (Track.InterpolableId == TEXT("itemLineColor")) PropLabel = TEXT("描边颜色");
	}
	else if (Track.Owner == TEXT("KKPE"))
	{
		if (Track.InterpolableId == TEXT("bonePos")) PropLabel = FString::Printf(TEXT("KKPE 骨骼位移 (%s)"), *Track.TargetBone);
		else if (Track.InterpolableId == TEXT("boneRot")) PropLabel = FString::Printf(TEXT("KKPE 骨骼旋转 (%s)"), *Track.TargetBone);
		else if (Track.InterpolableId == TEXT("boneScale")) PropLabel = FString::Printf(TEXT("KKPE 骨骼缩放 (%s)"), *Track.TargetBone);
		else if (Track.InterpolableId == TEXT("lastBlendShape")) PropLabel = FString::Printf(TEXT("BlendShape #%d (%s)"), Track.ParamInt, *DocLeafNodeName(Track.TargetPath));
		else if (Track.InterpolableId.StartsWith(TEXT("groupBlendShape"))) PropLabel = FString::Printf(TEXT("BlendShape 组 (%s)"), *DocLeafNodeName(Track.TargetPath));
		else if (Track.InterpolableId == TEXT("fbbikWeight")) PropLabel = TEXT("IK 整体权重");
		else if (Track.InterpolableId.StartsWith(TEXT("fbbik"))) PropLabel = FString::Printf(TEXT("IK 权重 (%s)"), *Track.InterpolableId.Mid(5));
		else PropLabel = FString::Printf(TEXT("KKPE · %s"), *Track.InterpolableId);
	}
	else if (Track.Owner == TEXT("NodesConstraints"))
	{
		PropLabel = FString::Printf(TEXT("约束 #%d · %s"), Track.ParamInt, *Track.InterpolableId);
	}
	else if (Track.Owner == TEXT("MaterialEditor") || Track.Owner == TEXT("RendererEditor"))
	{
		PropLabel = FString::Printf(TEXT("材质 · %s (%s)"), *Track.InterpolableId, *Track.ParamStr);
	}
	else
	{
		PropLabel = FString::Printf(TEXT("%s::%s"), *Track.Owner, *Track.InterpolableId);
	}
	return FString::Printf(TEXT("[%s] %s"), *TargetLabel, *PropLabel);
}

bool UOKSceneDocument::SampleCurrentTimelineValue(const FOKSceneTimelineTrack& Track, TArray<float>& OutValues, TArray<FString>* OutNames) const
{
	OutValues.Reset();
	if (OutNames) OutNames->Reset();
	auto PushUnityQuatFromEuler = [&](const FVector& EulerDeg)
	{
		const FQuat Qx(FVector(1, 0, 0), FMath::DegreesToRadians(EulerDeg.X));
		const FQuat Qy(FVector(0, 1, 0), FMath::DegreesToRadians(EulerDeg.Y));
		const FQuat Qz(FVector(0, 0, 1), FMath::DegreesToRadians(EulerDeg.Z));
		const FQuat U = (Qy * Qx * Qz).GetNormalized();
		OutValues = { float(U.X), float(U.Y), float(U.Z), float(U.W) };
	};
	auto PushUnityQuatFromUeQuat = [&](FQuat Q, bool bCamOrLight)
	{
		if (bCamOrLight) Q = Q * FQuat(FVector::UpVector, -UE_HALF_PI);
		Q.Normalize();
		OutValues = { float(-Q.X), float(Q.Z), float(Q.Y), float(Q.W) };
	};

	if (Track.Owner == TEXT("Timeline") && Track.ObjectId < 0)
	{
		const int32 CamId = StudioCameraId >= 0 ? StudioCameraId : ActiveCamera;
		const FOKSceneObject* CamObj = Find(CamId);
		if (Track.InterpolableId == TEXT("timeScale")) { OutValues = { LastTimelineScale }; return true; }
		if (Track.InterpolableId == TEXT("cameraOPos")) { OutValues = { float(StudioCameraOrbitTarget.X), float(StudioCameraOrbitTarget.Y), float(StudioCameraOrbitTarget.Z) }; return true; }
		if (Track.InterpolableId == TEXT("cameraORot")) { PushUnityQuatFromEuler(StudioCameraOrbitRot); return true; }
		if (Track.InterpolableId == TEXT("cameraOZoom")) { OutValues = { float(StudioCameraOrbitDist.Z) }; return true; }
		if (Track.InterpolableId == TEXT("cameraPos"))
		{
			const FVector Loc = CamObj ? CamObj->Transform.GetLocation() / 100.0 : FVector::ZeroVector;
			OutValues = { float(-Loc.X), float(Loc.Z), float(Loc.Y) };
			return true;
		}
		if (Track.InterpolableId == TEXT("cameraRot"))
		{
			PushUnityQuatFromUeQuat(CamObj ? CamObj->Transform.GetRotation() : FQuat::Identity, true);
			return true;
		}
		if (Track.InterpolableId == TEXT("cameraFOV"))
		{
			const double HorzRad = FMath::DegreesToRadians(double(CamObj ? CamObj->Camera.Fov : FreeView.Fov));
			const float VertDeg = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(HorzRad * 0.5) * 9.0 / 16.0)));
			OutValues = { VertDeg };
			return true;
		}
		if (Track.InterpolableId == TEXT("cameraData"))
		{
			const double HorzRad = FMath::DegreesToRadians(double(CamObj ? CamObj->Camera.Fov : FreeView.Fov));
			const float VertDeg = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(HorzRad * 0.5) * 9.0 / 16.0)));
			OutValues = {
				float(StudioCameraOrbitTarget.X), float(StudioCameraOrbitTarget.Y), float(StudioCameraOrbitTarget.Z),
				float(StudioCameraOrbitRot.X), float(StudioCameraOrbitRot.Y), float(StudioCameraOrbitRot.Z),
				float(StudioCameraOrbitDist.X), float(StudioCameraOrbitDist.Y), float(StudioCameraOrbitDist.Z),
				VertDeg
			};
			return true;
		}
		return false;
	}
	if (Track.Owner == TEXT("NodesConstraints"))
	{
		const FOKSceneConstraint* Con = Constraints.FindByPredicate([&](const FOKSceneConstraint& C) { return C.LoadId == Track.ParamInt; });
		if (Track.InterpolableId == TEXT("constraintEnabled")) { OutValues = { (Con && Con->bEnabled) ? 1.f : 0.f }; return true; }
		if (Track.InterpolableId == TEXT("constraintPos")) { OutValues = { Con ? Con->PosFactor : 1.f }; return true; }
		if (Track.InterpolableId == TEXT("constraintRos") || Track.InterpolableId == TEXT("constraintRot")) { OutValues = { Con ? Con->RotFactor : 1.f }; return true; }
		return false;
	}

	const FOKSceneObject* O = Find(Track.ObjectId);
	if (!O) return false;

	if (Track.Owner == TEXT("Timeline"))
	{
		if (Track.InterpolableId == TEXT("objectEnabled") || Track.InterpolableId == TEXT("lightOnOff")) { OutValues = { O->bVisible ? 1.f : 0.f }; return true; }
		if (Track.InterpolableId == TEXT("guideObjectPos"))
		{
			if (Track.TargetPath.IsEmpty())
			{
				const FVector L = O->Transform.GetLocation() / 100.0;
				OutValues = { float(-L.X), float(L.Z), float(L.Y) };
				return true;
			}
			if (Track.TargetIkEffector >= 0 && O->Kind == EOKSceneObjectKind::Character)
			{
				const FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Track.TargetIkEffector; });
				const FVector L = Ik ? Ik->Position / 100.0 : FVector::ZeroVector;
				OutValues = { float(-L.X), float(L.Z), float(L.Y) };
				return true;
			}
			const TArray<FOKSceneBoneTrs>* Bones = O->Kind == EOKSceneObjectKind::Character ? &O->Character.BoneOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.BoneOverrides : nullptr);
			const FOKSceneBoneTrs* B = Bones ? Bones->FindByPredicate([&](const FOKSceneBoneTrs& X) { return X.Bone == Track.TargetBone; }) : nullptr;
			const FVector P = (B && B->bHasPos) ? B->Pos : FVector::ZeroVector;
			OutValues = { float(P.X), float(P.Y), float(P.Z) };
			return true;
		}
		if (Track.InterpolableId == TEXT("guideObjectRot"))
		{
			if (Track.TargetPath.IsEmpty())
			{
				PushUnityQuatFromUeQuat(O->Transform.GetRotation(), O->Kind == EOKSceneObjectKind::Camera || O->Kind == EOKSceneObjectKind::Light);
				return true;
			}
			if (Track.TargetIkEffector >= 0 && O->Kind == EOKSceneObjectKind::Character)
			{
				const FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Track.TargetIkEffector; });
				PushUnityQuatFromEuler(Ik ? Ik->Euler : FVector::ZeroVector);
				return true;
			}
			const TArray<FOKSceneFkBone>* FkArr = O->Kind == EOKSceneObjectKind::Character ? &O->Character.Fk : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.Fk : nullptr);
			const FOKSceneFkBone* Fk = FkArr ? FkArr->FindByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == Track.TargetBone; }) : nullptr;
			PushUnityQuatFromEuler(Fk ? Fk->Euler : FVector::ZeroVector);
			return true;
		}
		if (Track.InterpolableId == TEXT("guideObjectScale"))
		{
			if (Track.TargetPath.IsEmpty())
			{
				const FVector S = O->Transform.GetScale3D();
				OutValues = { float(S.X), float(S.Z), float(S.Y) };
				return true;
			}
			const TArray<FOKSceneBoneTrs>* Bones = O->Kind == EOKSceneObjectKind::Character ? &O->Character.BoneOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.BoneOverrides : nullptr);
			const FOKSceneBoneTrs* B = Bones ? Bones->FindByPredicate([&](const FOKSceneBoneTrs& X) { return X.Bone == Track.TargetBone; }) : nullptr;
			const FVector S = (B && B->bHasScale) ? B->Scale : FVector::OneVector;
			OutValues = { float(S.X), float(S.Y), float(S.Z) };
			return true;
		}
		if (O->Kind == EOKSceneObjectKind::Light)
		{
			if (Track.InterpolableId == TEXT("lightColor")) { OutValues = { O->Light.Color.R, O->Light.Color.G, O->Light.Color.B, O->Light.Color.A }; return true; }
			if (Track.InterpolableId == TEXT("lightStrength")) { OutValues = { O->Light.Intensity / (O->Light.Type == EOKSceneLightType::Directional ? 4.f : 800.f) }; return true; }
			if (Track.InterpolableId == TEXT("lightRange")) { OutValues = { O->Light.Range / 100.f }; return true; }
			if (Track.InterpolableId == TEXT("lightSpotAngle")) { OutValues = { O->Light.SpotAngle }; return true; }
			if (Track.InterpolableId == TEXT("lightShadows")) { OutValues = { O->Light.bShadows ? 1.f : 0.f }; return true; }
		}
		if (O->Kind == EOKSceneObjectKind::Character)
		{
			const FOKSceneCharacter& C = O->Character;
			if (Track.InterpolableId == TEXT("objectAnimationSpeed")) { OutValues = { C.Speed }; return true; }
			if (Track.InterpolableId == TEXT("charAnimationTime")) { OutValues = { C.Time }; return true; }
			if (Track.InterpolableId == TEXT("charAnimation")) { OutValues = { float(FMath::Max(0, C.StudioAnimeGroup)), float(FMath::Max(0, C.StudioAnimeCategory)), float(FMath::Max(0, C.StudioAnimeNo)) }; return true; }
			if (Track.InterpolableId == TEXT("charAnimationPattern"))
			{
				const FOKSceneAnimFloat* Af = C.AnimFloats.FindByPredicate([](const FOKSceneAnimFloat& F) { return F.Name == TEXT("pattern"); });
				OutValues = { Af ? Af->Value : 0.f };
				return true;
			}
			if (Track.InterpolableId == TEXT("characterEyes")) { OutValues = { float(FMath::Max(0, C.EyesPattern)) }; return true; }
			if (Track.InterpolableId == TEXT("characterEyesOpen")) { OutValues = { C.EyesOpen >= 0.f ? C.EyesOpen : 1.f }; return true; }
			if (Track.InterpolableId == TEXT("characterEyebrows")) { OutValues = { float(FMath::Max(0, C.EyebrowPattern)) }; return true; }
			if (Track.InterpolableId == TEXT("characterEyebrowsOpen")) { OutValues = { C.EyebrowsOpen >= 0.f ? C.EyebrowsOpen : 1.f }; return true; }
			if (Track.InterpolableId == TEXT("characterMouth")) { OutValues = { float(FMath::Max(0, C.MouthPattern)) }; return true; }
			if (Track.InterpolableId == TEXT("characterMouthOpen")) { OutValues = { C.MouthOpen >= 0.f ? C.MouthOpen : 0.f }; return true; }
			if (Track.InterpolableId == TEXT("characterNeck"))
			{
				const int32 M = C.NeckLook == EOKSceneLook::Animation ? 0 : C.NeckLook == EOKSceneLook::Camera ? 1 : C.NeckLook == EOKSceneLook::Away ? 2 : C.NeckLook == EOKSceneLook::Fixed ? 3 : 4;
				OutValues = { float(M) };
				return true;
			}
			if (Track.InterpolableId == TEXT("characterLeftHand")) { OutValues = { float(FMath::Max(0, C.HandLeft)) }; return true; }
			if (Track.InterpolableId == TEXT("characterRightHand")) { OutValues = { float(FMath::Max(0, C.HandRight)) }; return true; }
			if (Track.InterpolableId == TEXT("blush")) { OutValues = { FMath::Max(0.f, C.Blush) }; return true; }
			if (Track.InterpolableId == TEXT("tears")) { OutValues = { float(FMath::Max(0, C.TearsLevel)) }; return true; }
			if (Track.InterpolableId == TEXT("femaleNipples")) { OutValues = { FMath::Max(0.f, C.NipStand) }; return true; }
			if (Track.InterpolableId == TEXT("charClothes") && C.ClothesStates.IsValidIndex(Track.ParamInt)) { OutValues = { float(C.ClothesStates[Track.ParamInt]) }; return true; }
			if (Track.InterpolableId == TEXT("juice")) { OutValues = { C.Fluids.IsValidIndex(Track.ParamInt) ? float(C.Fluids[Track.ParamInt]) : 0.f }; return true; }
		}
		if (O->Kind == EOKSceneObjectKind::Item)
		{
			const FOKSceneItem& It = O->Item;
			if (Track.InterpolableId == TEXT("objectAnimationSpeed")) { OutValues = { It.AnimeSpeed }; return true; }
			if (Track.InterpolableId == TEXT("itemAnimationTime")) { OutValues = { It.AnimeTime }; return true; }
			if (Track.InterpolableId == TEXT("itemAlpha")) { OutValues = { It.Alpha }; return true; }
			if (Track.InterpolableId == TEXT("itemShadowColor")) { const FLinearColor C = It.ShadowColor.A >= 0.f ? It.ShadowColor : FLinearColor::Black; OutValues = { C.R, C.G, C.B, 1.f }; return true; }
			if (Track.InterpolableId == TEXT("itemEmissionColor")) { const FLinearColor C = It.EmissionColor.A >= 0.f ? It.EmissionColor : FLinearColor::White; OutValues = { C.R, C.G, C.B, 1.f }; return true; }
			if (Track.InterpolableId == TEXT("itemEmissionPower")) { OutValues = { FMath::Max(0.f, It.EmissionPower) }; return true; }
			if (Track.InterpolableId == TEXT("itemLightCancel")) { OutValues = { FMath::Max(0.f, It.LightCancel) }; return true; }
			if (Track.InterpolableId == TEXT("itemLineWidth")) { OutValues = { It.LineWidth }; return true; }
			if (Track.InterpolableId == TEXT("itemLineColor")) { const FLinearColor C = It.LineColor.A >= 0.f ? It.LineColor : FLinearColor::Black; OutValues = { C.R, C.G, C.B, 1.f }; return true; }
			if (Track.InterpolableId.StartsWith(TEXT("itemColor")) && Track.InterpolableId.Len() == 10)
			{
				const int32 Slot = Track.InterpolableId[9] - TEXT('1');
				const FLinearColor C = It.Colors.IsValidIndex(Slot) && It.Colors[Slot].A >= 0.f ? It.Colors[Slot] : FLinearColor::White;
				OutValues = { C.R, C.G, C.B, C.A };
				return true;
			}
		}
	}
	else if (Track.Owner == TEXT("KKPE"))
	{
		const TArray<FOKSceneBoneTrs>* Bones = O->Kind == EOKSceneObjectKind::Character ? &O->Character.BoneOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.BoneOverrides : nullptr);
		const FOKSceneBoneTrs* B = Bones ? Bones->FindByPredicate([&](const FOKSceneBoneTrs& X) { return X.Bone == Track.TargetBone; }) : nullptr;
		if (Track.InterpolableId == TEXT("bonePos")) { const FVector P = (B && B->bHasPos) ? B->Pos : FVector::ZeroVector; OutValues = { float(P.X), float(P.Y), float(P.Z) }; return true; }
		if (Track.InterpolableId == TEXT("boneRot")) { PushUnityQuatFromEuler((B && B->bHasRot) ? B->Euler : FVector::ZeroVector); return true; }
		if (Track.InterpolableId == TEXT("boneScale")) { const FVector S = (B && B->bHasScale) ? B->Scale : FVector::OneVector; OutValues = { float(S.X), float(S.Y), float(S.Z) }; return true; }
		if (Track.InterpolableId == TEXT("fbbikWeight") && O->Kind == EOKSceneObjectKind::Character) { OutValues = { O->Character.IkWeight }; return true; }
		if (Track.TargetIkEffector >= 0 && O->Kind == EOKSceneObjectKind::Character)
		{
			const FOKSceneIkTarget* Ik = O->Character.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == Track.TargetIkEffector; });
			OutValues = { Ik ? (Track.InterpolableId.StartsWith(TEXT("fbbikEffectorRotationWeight")) ? Ik->RotationWeight : Ik->Weight) : 1.f };
			return true;
		}
		if (Track.InterpolableId == TEXT("lastBlendShape"))
		{
			const TArray<FOKSceneMorphOverride>* Morphs = O->Kind == EOKSceneObjectKind::Character ? &O->Character.MorphOverrides : (O->Kind == EOKSceneObjectKind::Item ? &O->Item.MorphOverrides : nullptr);
			const FOKSceneMorphOverride* M = Morphs ? Morphs->FindByPredicate([&](const FOKSceneMorphOverride& X) { return X.Renderer == Track.TargetPath && X.Index == Track.ParamInt; }) : nullptr;
			OutValues = { M ? M->Weight : 0.f };
			return true;
		}
	}
	OutValues = { 0.f };
	return true;
}

int32 UOKSceneDocument::AddTimelineInterpolableTrack(const FString& Owner, const FString& InterpolableId, int32 ObjectId, const FString& TargetPath, const FString& TargetBone, int32 TargetIkEffector, int32 ParamInt, const FString& ParamStr, const FString& Alias, const FString& GroupPath)
{
	int32 Existing = TimelineTracks.IndexOfByPredicate([&](const FOKSceneTimelineTrack& T)
	{
		return T.Owner == Owner && T.InterpolableId == InterpolableId && T.ObjectId == ObjectId
			&& T.TargetPath == TargetPath && T.TargetBone == TargetBone
			&& T.TargetIkEffector == TargetIkEffector && T.ParamInt == ParamInt && T.ParamStr == ParamStr;
	});
	if (Existing == INDEX_NONE)
	{
		FOKSceneTimelineTrack& NewTr = TimelineTracks.AddDefaulted_GetRef();
		NewTr.bEnabled = true;
		NewTr.Owner = Owner;
		NewTr.InterpolableId = InterpolableId;
		NewTr.ObjectId = ObjectId;
		NewTr.TargetPath = TargetPath;
		NewTr.TargetBone = TargetBone;
		NewTr.TargetIkEffector = TargetIkEffector;
		NewTr.ParamInt = ParamInt;
		NewTr.ParamStr = ParamStr;
		NewTr.Alias = Alias;
		NewTr.GroupPath = GroupPath;
		Existing = TimelineTracks.Num() - 1;
	}
	SetTimelineTrackKey(Existing, Playhead);
	return Existing;
}

int32 UOKSceneDocument::SetTimelineTrackKey(int32 TrackIndex, float Time)
{
	if (!TimelineTracks.IsValidIndex(TrackIndex)) return INDEX_NONE;
	FOKSceneTimelineTrack& Tr = TimelineTracks[TrackIndex];
	TArray<float> Vals;
	TArray<FString> Names;
	if (!SampleCurrentTimelineValue(Tr, Vals, &Names)) Vals = { 0.f };
	const float ClampedTime = FMath::Max(0.f, Time);
	int32 ExistingIdx = Tr.Keyframes.IndexOfByPredicate([ClampedTime](const FOKSceneTimelineKeyframe& K) { return FMath::Abs(K.Time - ClampedTime) < (1.f / 60.f); });
	TArray<FOKSceneTimelineCurvePt> SavedCurve;
	if (ExistingIdx != INDEX_NONE)
	{
		SavedCurve = Tr.Keyframes[ExistingIdx].Curve;
		Tr.Keyframes.RemoveAt(ExistingIdx);
	}
	if (SavedCurve.Num() < 2)
	{
		FOKSceneTimelineCurvePt P0, P1;
		P0.Time = 0.f; P0.Value = 0.f; P0.InTangent = 1.f; P0.OutTangent = 1.f;
		P1.Time = 1.f; P1.Value = 1.f; P1.InTangent = 1.f; P1.OutTangent = 1.f;
		SavedCurve = { P0, P1 };
	}
	FOKSceneTimelineKeyframe Kf;
	Kf.Time = ClampedTime;
	Kf.Values = MoveTemp(Vals);
	Kf.Names = MoveTemp(Names);
	Kf.Curve = MoveTemp(SavedCurve);
	Tr.Keyframes.Add(MoveTemp(Kf));
	Tr.Keyframes.Sort([](const FOKSceneTimelineKeyframe& A, const FOKSceneTimelineKeyframe& B) { return A.Time < B.Time; });
	Duration = FMath::Max(Duration, ClampedTime);
	NotifyChanged();
	return Tr.Keyframes.IndexOfByPredicate([ClampedTime](const FOKSceneTimelineKeyframe& K) { return FMath::IsNearlyEqual(K.Time, ClampedTime, 1e-4f); });
}

bool UOKSceneDocument::ImportTimelineXmlFile(const FString& Path, int32 TargetObjectId, bool bSingleFile, FString& OutError)
{
	const FTCHARToUTF8 Utf8Path(*Path);
	const int32 BindKey = bSingleFile ? TargetObjectId : -1;
	int32 Needed = ok_studio_timeline_read_xml(Utf8Path.Get(), 1, BindKey, nullptr, 0);
	if (Needed <= 0)
	{
		OutError = TEXT("无法解析 Timeline XML 文件：") + Path;
		return false;
	}
	TArray<char> Buf;
	Buf.SetNumZeroed(Needed + 4);
	const int32 Written = ok_studio_timeline_read_xml(Utf8Path.Get(), 1, BindKey, Buf.GetData(), Buf.Num());
	if (Written <= 0)
	{
		OutError = TEXT("读取 Timeline XML 数据失败：") + Path;
		return false;
	}
	const FString JsonStr = UTF8_TO_TCHAR(Buf.GetData());
	TSharedPtr<FJsonObject> TlObj;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(JsonStr), TlObj) || !TlObj)
	{
		OutError = TEXT("Timeline JSON 反序列化失败");
		return false;
	}
	if (!bSingleFile)
	{
		if (TlObj->HasField(TEXT("duration"))) Duration = FMath::Max(0.1f, float(TlObj->GetNumberField(TEXT("duration"))));
		if (TlObj->HasField(TEXT("speed"))) TimelineSpeed = FMath::Max(0.01f, float(TlObj->GetNumberField(TEXT("speed"))));
		if (TlObj->HasField(TEXT("divisions"))) TimelineDivisions = FMath::Max(1, int32(TlObj->GetNumberField(TEXT("divisions"))));
		if (TlObj->HasField(TEXT("block_length"))) TimelineBlockLength = FMath::Max(0.01f, float(TlObj->GetNumberField(TEXT("block_length"))));
		if (TlObj->HasField(TEXT("is_looping"))) bLoopTimeline = TlObj->GetBoolField(TEXT("is_looping"));
	}
	// Map sorted object indices when importing a full-scene XML (dic_key comes in as 0..N-1 when sorted_keys was empty in FFI)
	TArray<int32> SortedObjectIds;
	for (const FOKSceneObject& O : Objects) SortedObjectIds.Add(O.Id);
	SortedObjectIds.Sort();

	const TArray<TSharedPtr<FJsonValue>>* TracksArr = nullptr;
	if (TlObj->TryGetArrayField(TEXT("tracks"), TracksArr))
	{
		for (const TSharedPtr<FJsonValue>& Tv : *TracksArr)
		{
			const TSharedPtr<FJsonObject> To = Tv ? Tv->AsObject() : nullptr;
			if (!To) continue;
			FOKSceneTimelineTrack Tr;
			To->TryGetBoolField(TEXT("enabled"), Tr.bEnabled);
			Tr.Owner = To->GetStringField(TEXT("owner"));
			Tr.InterpolableId = To->GetStringField(TEXT("id"));
			const int32 RawKey = To->HasField(TEXT("dic_key")) ? int32(To->GetNumberField(TEXT("dic_key"))) : -1;
			if (RawKey < 0) Tr.ObjectId = -1;
			else if (bSingleFile) Tr.ObjectId = TargetObjectId;
			else if (SortedObjectIds.IsValidIndex(RawKey)) Tr.ObjectId = SortedObjectIds[RawKey];
			else if (Find(RawKey)) Tr.ObjectId = RawKey;
			else continue;

			To->TryGetStringField(TEXT("alias"), Tr.Alias);
			To->TryGetStringField(TEXT("group_path"), Tr.GroupPath);
			To->TryGetStringField(TEXT("target_path"), Tr.TargetPath);
			To->TryGetStringField(TEXT("target_bone"), Tr.TargetBone);
			To->TryGetStringField(TEXT("param_str"), Tr.ParamStr);
			if (To->HasField(TEXT("target_ik_effector"))) Tr.TargetIkEffector = int32(To->GetNumberField(TEXT("target_ik_effector")));
			if (To->HasField(TEXT("param_int"))) Tr.ParamInt = int32(To->GetNumberField(TEXT("param_int")));
			const TArray<TSharedPtr<FJsonValue>>* ColArr = nullptr;
			if (To->TryGetArrayField(TEXT("color"), ColArr) && ColArr->Num() >= 3)
				Tr.Color = FLinearColor(float((*ColArr)[0]->AsNumber()), float((*ColArr)[1]->AsNumber()), float((*ColArr)[2]->AsNumber()), 1.f);

			const TArray<TSharedPtr<FJsonValue>>* KfsArr = nullptr;
			if (To->TryGetArrayField(TEXT("keyframes"), KfsArr))
			{
				for (const TSharedPtr<FJsonValue>& Kv : *KfsArr)
				{
					const TSharedPtr<FJsonObject> Ko = Kv ? Kv->AsObject() : nullptr;
					if (!Ko) continue;
					FOKSceneTimelineKeyframe Kf;
					Kf.Time = float(Ko->GetNumberField(TEXT("time")));
					Duration = FMath::Max(Duration, Kf.Time);
					const TArray<TSharedPtr<FJsonValue>>* ValArr = nullptr;
					if (Ko->TryGetArrayField(TEXT("values"), ValArr))
						for (const TSharedPtr<FJsonValue>& Vv : *ValArr) Kf.Values.Add(float(Vv->AsNumber()));
					const TArray<TSharedPtr<FJsonValue>>* NameArr = nullptr;
					if (Ko->TryGetArrayField(TEXT("names"), NameArr))
						for (const TSharedPtr<FJsonValue>& Nv : *NameArr) Kf.Names.Add(Nv->AsString());
					const TArray<TSharedPtr<FJsonValue>>* CrvArr = nullptr;
					if (Ko->TryGetArrayField(TEXT("curve"), CrvArr))
						for (const TSharedPtr<FJsonValue>& Cv : *CrvArr)
							if (const TSharedPtr<FJsonObject> Co = Cv ? Cv->AsObject() : nullptr)
							{
								FOKSceneTimelineCurvePt Pt;
								Pt.Time = float(Co->GetNumberField(TEXT("t")));
								Pt.Value = float(Co->GetNumberField(TEXT("v")));
								Pt.InTangent = float(Co->GetNumberField(TEXT("in_t")));
								Pt.OutTangent = float(Co->GetNumberField(TEXT("out_t")));
								Kf.Curve.Add(Pt);
							}
					Tr.Keyframes.Add(MoveTemp(Kf));
				}
			}
			if (!Tr.Keyframes.IsEmpty())
			{
				const int32 Dup = TimelineTracks.IndexOfByPredicate([&](const FOKSceneTimelineTrack& X)
				{
					return X.Owner == Tr.Owner && X.InterpolableId == Tr.InterpolableId && X.ObjectId == Tr.ObjectId
						&& X.TargetPath == Tr.TargetPath && X.ParamInt == Tr.ParamInt && X.ParamStr == Tr.ParamStr;
				});
				if (Dup != INDEX_NONE) TimelineTracks[Dup] = MoveTemp(Tr);
				else TimelineTracks.Add(MoveTemp(Tr));
			}
		}
	}
	EvaluateTimeline(Playhead);
	NotifyChanged();
	return true;
}

bool UOKSceneDocument::ExportTimelineXmlFile(const FString& Path, int32 TargetObjectId, bool bSingleFile, FString& OutError) const
{
	TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
	Root->SetNumberField(TEXT("duration"), FMath::Max(0.1f, Duration));
	Root->SetNumberField(TEXT("speed"), FMath::Max(0.01f, TimelineSpeed));
	Root->SetNumberField(TEXT("divisions"), FMath::Max(1, TimelineDivisions));
	Root->SetNumberField(TEXT("block_length"), FMath::Max(0.01f, TimelineBlockLength));
	Root->SetBoolField(TEXT("is_looping"), bLoopTimeline);
	if (!bSingleFile)
	{
		TArray<int32> SortedIds;
		for (const FOKSceneObject& O : Objects) SortedIds.Add(O.Id);
		SortedIds.Sort();
		TArray<TSharedPtr<FJsonValue>> SortedKeysJson;
		for (int32 Id : SortedIds) SortedKeysJson.Add(MakeShared<FJsonValueNumber>(Id));
		Root->SetArrayField(TEXT("sorted_keys"), SortedKeysJson);
	}

	TArray<TSharedPtr<FJsonValue>> TracksArr;
	for (const FOKSceneTimelineTrack& Tr : TimelineTracks)
	{
		if (bSingleFile && TargetObjectId >= 0 && Tr.ObjectId != TargetObjectId) continue;
		TSharedRef<FJsonObject> To = MakeShared<FJsonObject>();
		To->SetBoolField(TEXT("enabled"), Tr.bEnabled);
		To->SetStringField(TEXT("owner"), Tr.Owner);
		To->SetStringField(TEXT("id"), Tr.InterpolableId);
		To->SetNumberField(TEXT("dic_key"), Tr.ObjectId);
		if (!Tr.Alias.IsEmpty()) To->SetStringField(TEXT("alias"), Tr.Alias);
		if (!Tr.GroupPath.IsEmpty()) To->SetStringField(TEXT("group_path"), Tr.GroupPath);
		if (!Tr.TargetPath.IsEmpty()) To->SetStringField(TEXT("target_path"), Tr.TargetPath);
		if (!Tr.TargetBone.IsEmpty()) To->SetStringField(TEXT("target_bone"), Tr.TargetBone);
		if (Tr.TargetIkEffector >= 0) To->SetNumberField(TEXT("target_ik_effector"), Tr.TargetIkEffector);
		if (Tr.ParamInt >= 0) To->SetNumberField(TEXT("param_int"), Tr.ParamInt);
		if (!Tr.ParamStr.IsEmpty()) To->SetStringField(TEXT("param_str"), Tr.ParamStr);
		To->SetArrayField(TEXT("color"), {
			MakeShared<FJsonValueNumber>(Tr.Color.R),
			MakeShared<FJsonValueNumber>(Tr.Color.G),
			MakeShared<FJsonValueNumber>(Tr.Color.B)
		});
		TArray<TSharedPtr<FJsonValue>> KfsArr;
		for (const FOKSceneTimelineKeyframe& Kf : Tr.Keyframes)
		{
			TSharedRef<FJsonObject> Ko = MakeShared<FJsonObject>();
			Ko->SetNumberField(TEXT("time"), Kf.Time);
			TArray<TSharedPtr<FJsonValue>> ValArr;
			for (float V : Kf.Values) ValArr.Add(MakeShared<FJsonValueNumber>(V));
			Ko->SetArrayField(TEXT("values"), ValArr);
			if (!Kf.Names.IsEmpty())
			{
				TArray<TSharedPtr<FJsonValue>> NmArr;
				for (const FString& Nm : Kf.Names) NmArr.Add(MakeShared<FJsonValueString>(Nm));
				Ko->SetArrayField(TEXT("names"), NmArr);
			}
			if (!Kf.Curve.IsEmpty())
			{
				TArray<TSharedPtr<FJsonValue>> CrvArr;
				for (const FOKSceneTimelineCurvePt& Pt : Kf.Curve)
				{
					TSharedRef<FJsonObject> Co = MakeShared<FJsonObject>();
					Co->SetNumberField(TEXT("t"), Pt.Time);
					Co->SetNumberField(TEXT("v"), Pt.Value);
					Co->SetNumberField(TEXT("in_t"), Pt.InTangent);
					Co->SetNumberField(TEXT("out_t"), Pt.OutTangent);
					CrvArr.Add(MakeShared<FJsonValueObject>(Co));
				}
				Ko->SetArrayField(TEXT("curve"), CrvArr);
			}
			KfsArr.Add(MakeShared<FJsonValueObject>(Ko));
		}
		To->SetArrayField(TEXT("keyframes"), KfsArr);
		TracksArr.Add(MakeShared<FJsonValueObject>(To));
	}
	Root->SetArrayField(TEXT("tracks"), TracksArr);

	FString JsonStr;
	FJsonSerializer::Serialize(Root, TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&JsonStr));
	const FTCHARToUTF8 Utf8Path(*Path);
	const FTCHARToUTF8 Utf8Json(*JsonStr);
	char ErrBuf[512] = {};
	if (ok_studio_timeline_write_xml(Utf8Path.Get(), Utf8Json.Get(), bSingleFile ? 1 : 0, ErrBuf, sizeof(ErrBuf)) != 0)
	{
		OutError = ErrBuf[0] ? FString(UTF8_TO_TCHAR(ErrBuf)) : (TEXT("写入 Timeline XML 失败：") + Path);
		return false;
	}
	return true;
}

TMap<FName, FLinearColor> FOKScenePost::ShaderGlobals() const
{
	TMap<FName, FLinearColor> Out;
	if (AmbientShadowG >= 0.f) Out.Add(TEXT("_ambientshadowG"), FLinearColor(AmbientShadow.R, AmbientShadow.G, AmbientShadow.B, 1.f - FMath::Clamp(AmbientShadowG, 0.f, 1.f)));
	if (LineColorG >= 0.f) Out.Add(TEXT("_LineColorG"), FLinearColor(0.5f, 0.5f, 0.5f, 1.f - FMath::Clamp(LineColorG, 0.f, 1.f)));
	if (LineWidthG >= 0.f) Out.Add(TEXT("_linewidthG"), FLinearColor(LineWidthG, 0.f, 0.f, 0.f));
	if (ShaderType >= 0) Out.Add(TEXT("_KanoVerShift"), FLinearColor(ShaderType == 0 ? 0.f : 1.f, 0.f, 0.f, 0.f));
	return Out;
}

void FOKScenePost::ApplyTo(FPostProcessSettings& S) const
{
	// Studio's shaders write their colour straight to the display (as the card reader shows it): no film curve or
	// gamut expansion, a fixed exposure (the bias below is the only change). The screen filter LUT then sees the
	// colours the game's Amplify Color sees.
	S.bOverride_ToneCurveAmount = true;
	S.ToneCurveAmount = 0.f;
	S.bOverride_MotionBlurAmount = true;
	S.MotionBlurAmount = 0.f;
	S.bOverride_MotionBlurMax = true;
	S.MotionBlurMax = 0.f;
	S.bOverride_ExpandGamut = true;
	S.ExpandGamut = 0.f;
	S.bOverride_BlueCorrection = true;
	S.BlueCorrection = 0.f;
	S.bOverride_AutoExposureMethod = true;
	S.AutoExposureMethod = AEM_Manual;
	S.bOverride_AutoExposureApplyPhysicalCameraExposure = true;
	S.AutoExposureApplyPhysicalCameraExposure = false;
	S.bOverride_AutoExposureMinBrightness = true;
	S.AutoExposureMinBrightness = 1.f;
	S.bOverride_AutoExposureMaxBrightness = true;
	S.AutoExposureMaxBrightness = 1.f;
	// Legacy Gaussian fallback / diagnostic mode only. The installed HDR source does not use a luminance gate
	// or 1/(1-threshold) normalization. OKStudioApplySourceBloom below replaces this approximation with the
	// quarter-resolution, per-channel, nine-tap source chain and disables UE bloom once its parents are ready.
	const float Threshold = BloomThreshold >= 0.f ? FMath::Clamp(BloomThreshold, 0.f, 0.95f) : 0.f;
	const float Spread = 4.f * FMath::Clamp(BloomSize, 0.1f, 8.f);
	const float SigmaOfWidth = 0.00498f * Spread * 9.f / 16.f;
	S.bOverride_BloomMethod = true;
	S.BloomMethod = BM_SOG;
	S.bOverride_BloomIntensity = true;
	S.BloomIntensity = bBloom ? BloomIntensity * 2.f / (1.f - Threshold) : 0.f;
	S.bOverride_BloomThreshold = true;
	S.BloomThreshold = BloomThreshold >= 0.f ? Threshold : -1.f;
	S.bOverride_BloomSizeScale = true;
	S.BloomSizeScale = 1.f;
	S.bOverride_BloomGaussianIntensity = true;
	S.BloomGaussianIntensity = 1.f;
	S.bOverride_Bloom1Tint = S.bOverride_Bloom2Tint = S.bOverride_Bloom3Tint = S.bOverride_Bloom4Tint = S.bOverride_Bloom5Tint = S.bOverride_Bloom6Tint = true;
	S.Bloom1Tint = S.Bloom2Tint = S.Bloom4Tint = S.Bloom5Tint = S.Bloom6Tint = FLinearColor::Black;
	S.Bloom3Tint = FLinearColor(6.f, 6.f, 6.f, 1.f);
	S.bOverride_Bloom3Size = true;
	S.Bloom3Size = SigmaOfWidth * 5.78f * 2.f * 100.f;
	// Always written: a focal distance of 0 turns depth of field off (an unset override let the previous scene's stay).
	S.bOverride_DepthOfFieldFocalDistance = true;
	S.bOverride_DepthOfFieldFstop = true;
	S.DepthOfFieldFocalDistance = bDepthOfField ? FMath::Max(FocalDistance, 1.f) : 0.f;
	S.DepthOfFieldFstop = FMath::Clamp(Aperture, 0.3f, 32.f);
	// The lens opens as wide as the f-stop asks (UE's default limit, f/1.2, clamped wide Studio views' blur away).
	S.bOverride_DepthOfFieldMinFstop = true;
	S.DepthOfFieldMinFstop = 0.3f;
	S.bOverride_VignetteIntensity = true;
	S.VignetteIntensity = bVignette ? VignetteIntensity : 0.f;
	S.bOverride_AutoExposureBias = true;
	S.AutoExposureBias = Exposure;
	UTexture* Lut = ColorFilter >= 0 ? FOKStudioCatalog::Get().FilterLut(ColorFilter) : nullptr;
	S.bOverride_ColorGradingLUT = true;
	const float FilterStrength = Lut ? FMath::Clamp(ColorFilterIntensity, 0.f, 1.f) : 0.f;
	S.ColorGradingLUT = FilterStrength > 0.f ? Lut : OKStudioIdentityGradeLut();
	S.bOverride_ColorGradingIntensity = true;
	S.ColorGradingIntensity = FilterStrength > 0.f ? FilterStrength : 1.f;
	if (OKStudioApplySourceGrade(*this, S))
	{
		// Exposure is applied to linear light inside the source grading pass.
		S.AutoExposureBias = 0.f;
		// A null/zero LUT does not clear a volume's earlier LUT in SceneView:
		// IF_PP rejects null and LerpTo(...,0) leaves the prior blend intact.
		S.ColorGradingLUT = OKStudioIdentityGradeLut();
		S.ColorGradingIntensity = 1.f;
		// The vignette is Studio's own formula inside the grading pass.
		S.VignetteIntensity = 0.f;
	}
	// Fog, ambient occlusion and sun shafts: Studio's own formulas in one post-process material.
	OKStudioApplyScenePostMaterial(*this, S);
	if (OKStudioApplySourceBloom(*this, S)) S.BloomIntensity = 0.f;
}
