#include "OKStudioMod.h"
#include "OKSceneDocument.h"
#include "Dom/JsonObject.h"

DEFINE_LOG_CATEGORY_STATIC(LogOKStudioMod, Log, All);

FOKStudioModRegistry& FOKStudioModRegistry::Get()
{
	static FOKStudioModRegistry Registry;
	return Registry;
}

namespace
{
	bool NameChar(TCHAR C) { return FChar::IsAlnum(C) || C == TEXT('_') || C == TEXT('-'); }
}

bool FOKStudioModRegistry::IsValidOwner(const FString& Owner)
{
	if (Owner.IsEmpty() || Owner.Len() > 128 || Owner.StartsWith(TEXT(".")) || Owner.EndsWith(TEXT(".")) || Owner.Contains(TEXT(".."))) return false;
	for (TCHAR C : Owner) if (!NameChar(C) && C != TEXT('.')) return false;
	return true;
}

bool FOKStudioModRegistry::IsValidName(const FString& Name)
{
	if (Name.IsEmpty() || Name.Len() > 64) return false;
	for (TCHAR C : Name) if (!NameChar(C)) return false;
	return true;
}

bool FOKStudioModRegistry::Check(const FString& Owner, const FString& Name, const TCHAR* What, bool bTaken) const
{
	if (!IsValidOwner(Owner)) { UE_LOG(LogOKStudioMod, Warning, TEXT("OK studio mod: %s \"%s\" refused: bad mod id \"%s\""), What, *Name, *Owner); return false; }
	if (!IsValidName(Name)) { UE_LOG(LogOKStudioMod, Warning, TEXT("OK studio mod: %s of %s refused: bad name \"%s\""), What, *Owner, *Name); return false; }
	if (bTaken) { UE_LOG(LogOKStudioMod, Warning, TEXT("OK studio mod: %s %s.%s refused: already registered"), What, *Owner, *Name); return false; }
	return true;
}

bool FOKStudioModRegistry::AddCommand(FOKStudioModCommand Command)
{
	const bool bTaken = CommandList.ContainsByPredicate([&](const FOKStudioModCommand& C) { return C.Owner == Command.Owner && C.Name == Command.Name; });
	if (!Check(Command.Owner, Command.Name, TEXT("command"), bTaken) || !Command.Run) return false;
	if (Command.Label.IsEmpty()) Command.Label = Command.Id();
	CommandList.Add(MoveTemp(Command));
	++GenerationCounter;
	return true;
}

bool FOKStudioModRegistry::AddToolbarButton(FOKStudioModToolbarButton Button)
{
	const bool bTaken = ToolbarList.ContainsByPredicate([&](const FOKStudioModToolbarButton& B) { return B.Owner == Button.Owner && B.Id == Button.Id; });
	if (!Check(Button.Owner, Button.Id, TEXT("toolbar button"), bTaken) || Button.Command.IsEmpty()) return false;
	ToolbarList.Add(MoveTemp(Button));
	++GenerationCounter;
	return true;
}

bool FOKStudioModRegistry::AddMenuItem(FOKStudioModMenuItem Item)
{
	const bool bTaken = MenuList.ContainsByPredicate([&](const FOKStudioModMenuItem& M) { return M.Owner == Item.Owner && M.Id == Item.Id; });
	if (!Check(Item.Owner, Item.Id, TEXT("menu item"), bTaken) || Item.Command.IsEmpty()) return false;
	MenuList.Add(MoveTemp(Item));
	++GenerationCounter;
	return true;
}

bool FOKStudioModRegistry::AddControl(FOKStudioModControl Control)
{
	const bool bTaken = ControlList.ContainsByPredicate([&](const FOKStudioModControl& C) { return C.Owner == Control.Owner && C.Id == Control.Id; });
	if (!Check(Control.Owner, Control.Id, TEXT("control"), bTaken)) return false;
	const bool bButton = Control.Kind == EOKStudioModControlKind::Button;
	if (bButton ? Control.Command.IsEmpty() : !(Control.Get && Control.Set))
	{
		UE_LOG(LogOKStudioMod, Warning, TEXT("OK studio mod: control %s.%s refused: %s"), *Control.Owner, *Control.Id, bButton ? TEXT("a button needs a command") : TEXT("needs Get and Set"));
		return false;
	}
	if (Control.Kind == EOKStudioModControlKind::Dropdown && Control.Options.IsEmpty()) { UE_LOG(LogOKStudioMod, Warning, TEXT("OK studio mod: dropdown %s.%s refused: no options"), *Control.Owner, *Control.Id); return false; }
	if (Control.Label.IsEmpty()) Control.Label = Control.Id;
	ControlList.Add(MoveTemp(Control));
	++GenerationCounter;
	return true;
}

bool FOKStudioModRegistry::AddInterpolable(FOKStudioModInterpolable Interpolable)
{
	const bool bTaken = InterpolableList.ContainsByPredicate([&](const FOKStudioModInterpolable& I) { return I.Owner == Interpolable.Owner && I.Id == Interpolable.Id; });
	if (!Check(Interpolable.Owner, Interpolable.Id, TEXT("interpolable"), bTaken) || !Interpolable.Sample || !Interpolable.Apply) return false;
	if (Interpolable.Label.IsEmpty()) Interpolable.Label = Interpolable.Id;
	InterpolableList.Add(MoveTemp(Interpolable));
	++GenerationCounter;
	return true;
}

void FOKStudioModRegistry::RemoveOwner(const FString& Owner)
{
	const int32 Removed = CommandList.RemoveAll([&](const FOKStudioModCommand& C) { return C.Owner == Owner; })
		+ ToolbarList.RemoveAll([&](const FOKStudioModToolbarButton& B) { return B.Owner == Owner; })
		+ MenuList.RemoveAll([&](const FOKStudioModMenuItem& M) { return M.Owner == Owner; })
		+ ControlList.RemoveAll([&](const FOKStudioModControl& C) { return C.Owner == Owner; })
		+ InterpolableList.RemoveAll([&](const FOKStudioModInterpolable& I) { return I.Owner == Owner; });
	if (Removed) ++GenerationCounter;
}

const FOKStudioModCommand* FOKStudioModRegistry::FindCommand(const FString& FullId) const
{
	return CommandList.FindByPredicate([&](const FOKStudioModCommand& C) { return C.Id() == FullId; });
}

bool FOKStudioModRegistry::IsModTrack(const FOKSceneTimelineTrack& Track)
{
	return Track.Owner.StartsWith(TEXT("mod."));
}

const FOKStudioModInterpolable* FOKStudioModRegistry::FindInterpolable(const FOKSceneTimelineTrack& Track) const
{
	if (!IsModTrack(Track)) return nullptr;
	const FString Owner = Track.Owner.Mid(4);
	return InterpolableList.FindByPredicate([&](const FOKStudioModInterpolable& I) { return I.Owner == Owner && I.Id == Track.InterpolableId; });
}

bool FOKStudioModRegistry::SampleTimeline(const UOKSceneDocument& Document, const FOKSceneTimelineTrack& Track, TArray<float>& OutValues) const
{
	OutValues.Reset();
	const FOKStudioModInterpolable* I = FindInterpolable(Track);
	if (!I || !I->Sample(Document, Track.ObjectId, OutValues) || OutValues.IsEmpty()) { OutValues = { 0.f }; return false; }
	return true;
}

bool FOKStudioModRegistry::EvaluateTimeline(UOKSceneDocument& Document, const FOKSceneTimelineTrack& Track, const FOKSceneTimelineKeyframe* K0, const FOKSceneTimelineKeyframe* K1, float Factor) const
{
	// A track of a mod that is not loaded keeps its keys and does nothing.
	const FOKStudioModInterpolable* I = FindInterpolable(Track);
	if (!I || !K0 || K0->Values.IsEmpty()) return false;
	TArray<float> Values = K0->Values;
	if (K1 && K1->Values.Num() == Values.Num())
		for (int32 V = 0; V < Values.Num(); ++V) Values[V] = FMath::Lerp(K0->Values[V], K1->Values[V], Factor);
	I->Apply(Document, Track.ObjectId, Values);
	return true;
}

TArray<FOKStudioModRegistry::FMenuInterpolable> FOKStudioModRegistry::InterpolableMenu(const UOKSceneDocument& Document, int32 SelectedId) const
{
	TArray<FMenuInterpolable> Out;
	const FOKSceneObject* Selected = Document.Find(SelectedId);
	for (const FOKStudioModInterpolable& I : InterpolableList)
	{
		if (I.bPerObject && (!Selected || (!I.Kinds.IsEmpty() && !I.Kinds.Contains(int32(Selected->Kind))))) continue;
		const FString Where = I.bPerObject ? FString::Printf(TEXT("#%d"), Selected->Id) : FString(TEXT("場景"));
		Out.Add({ FString::Printf(TEXT("Mod %s：%s（%s）"), *I.Owner, *I.Label, *Where), TimelineOwner(I.Owner), I.Id, I.bPerObject ? Selected->Id : -1 });
	}
	return Out;
}

namespace
{
	TSharedRef<FJsonObject> MapJson(const TMap<int32, int32>& IdMap)
	{
		TSharedRef<FJsonObject> Map = MakeShared<FJsonObject>();
		for (const TPair<int32, int32>& P : IdMap) Map->SetNumberField(FString::FromInt(P.Key), P.Value);
		return Map;
	}
	TArray<TSharedPtr<FJsonValue>> IdsJson(const TArray<int32>& Ids)
	{
		TArray<TSharedPtr<FJsonValue>> Out;
		for (int32 Id : Ids) Out.Add(MakeShared<FJsonValueNumber>(Id));
		return Out;
	}
}

void FOKStudioModRegistry::NotifySceneLoad(const TCHAR* Kind, const TMap<int32, int32>* IdMap, const TSharedPtr<FJsonObject>& ImportedRoot)
{
	if (!SceneEventSink) return;
	TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
	Args->SetStringField(TEXT("kind"), Kind);
	if (IdMap) Args->SetObjectField(TEXT("map"), MapJson(*IdMap));
	const TSharedPtr<FJsonObject>* Mods = nullptr;
	if (ImportedRoot && ImportedRoot->TryGetObjectField(TEXT("mods"), Mods) && Mods) Args->SetObjectField(TEXT("imported_mods"), *Mods);
	SceneEventSink(TEXT("scene_load"), Args);
}

void FOKStudioModRegistry::NotifySceneSave()
{
	if (SceneEventSink) SceneEventSink(TEXT("scene_save"), MakeShared<FJsonObject>());
}

void FOKStudioModRegistry::NotifyObjectsCopied(const TMap<int32, int32>& IdMap)
{
	if (!SceneEventSink || IdMap.IsEmpty()) return;
	TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
	Args->SetObjectField(TEXT("map"), MapJson(IdMap));
	SceneEventSink(TEXT("objects_copied"), Args);
}

void FOKStudioModRegistry::NotifyObjectsDeleted(const TArray<int32>& Ids)
{
	if (!SceneEventSink || Ids.IsEmpty()) return;
	TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
	Args->SetArrayField(TEXT("ids"), IdsJson(Ids));
	SceneEventSink(TEXT("objects_deleted"), Args);
}

void FOKStudioModRegistry::NotifySelected(const TArray<int32>& Ids, int32 Primary)
{
	if (!SceneEventSink) return;
	TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
	Args->SetArrayField(TEXT("ids"), IdsJson(Ids));
	Args->SetNumberField(TEXT("primary"), Primary);
	SceneEventSink(TEXT("objects_selected"), Args);
}
