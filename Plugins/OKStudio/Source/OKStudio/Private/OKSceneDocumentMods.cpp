// The scene's mod data: the "mods" field of .okscene (FormatVersion 4; Docs/OK_MOD_FRAMEWORK_PLAN.md §6.2, §6.5).
//   "mods": { "<mod id>": { "version": <int>, "data": "<base64>" }, ... }
// The data lives in the document, so saving, scene cards, undo / redo (whole-document JSON snapshots) and the unsaved
// mark cover it with nothing from the mod. An entry of a mod this build does not have is written back as it was read.
#include "OKSceneDocument.h"
#include "Dom/JsonObject.h"
#include "Misc/Base64.h"

bool UOKSceneDocument::GetModData(const FString& Mod, TArray<uint8>& OutBytes, int32* OutVersion) const
{
	OutBytes.Reset();
	const FOKSceneModData* Entry = Mods.Find(Mod);
	if (!Entry) return false;
	if (OutVersion) *OutVersion = Entry->Version;
	return Entry->Data.IsEmpty() || FBase64::Decode(Entry->Data, OutBytes);
}

void UOKSceneDocument::SetModData(const FString& Mod, int32 Version, TConstArrayView<uint8> Bytes)
{
	FOKSceneModData& Entry = Mods.FindOrAdd(Mod);
	Entry.Version = Version;
	Entry.Data = Bytes.IsEmpty() ? FString() : FBase64::Encode(Bytes.GetData(), uint32(Bytes.Num()));
	// The same keys in the same order whatever order they were set in: undo compares documents as text.
	Mods.KeySort(TLess<FString>());
}

bool UOKSceneDocument::RemoveModData(const FString& Mod)
{
	return Mods.Remove(Mod) > 0;
}

void UOKSceneDocument::WriteMods(FJsonObject& Root) const
{
	if (Mods.IsEmpty()) return;
	TArray<FString> Ids;
	Mods.GetKeys(Ids);
	Ids.Sort();
	TSharedRef<FJsonObject> Out = MakeShared<FJsonObject>();
	for (const FString& Id : Ids)
	{
		const FOKSceneModData& Entry = Mods[Id];
		TSharedRef<FJsonObject> J = MakeShared<FJsonObject>();
		J->SetNumberField(TEXT("version"), Entry.Version);
		J->SetStringField(TEXT("data"), Entry.Data);
		Out->SetObjectField(Id, J);
	}
	Root.SetObjectField(TEXT("mods"), Out);
}

void UOKSceneDocument::ReadMods(const FJsonObject& Root)
{
	Mods.Reset();
	const TSharedPtr<FJsonObject>* In = nullptr;
	if (!Root.TryGetObjectField(TEXT("mods"), In) || !In || !In->IsValid()) return;
	for (const TPair<FString, TSharedPtr<FJsonValue>>& Pair : (*In)->Values)
	{
		const TSharedPtr<FJsonObject>* J = nullptr;
		FOKSceneModData Entry;
		double Version = 0.0;
		// A broken entry is dropped and the scene still opens: one mod's data must not cost the whole scene.
		if (Pair.Key.IsEmpty() || !Pair.Value.IsValid() || !Pair.Value->TryGetObject(J) || !J || !(*J)->TryGetNumberField(TEXT("version"), Version) || !(*J)->TryGetStringField(TEXT("data"), Entry.Data))
		{
			UE_LOG(LogTemp, Warning, TEXT("OK scene: mod data \"%s\" is not {version, data}; dropped"), *Pair.Key);
			continue;
		}
		Entry.Version = int32(Version);
		Mods.Add(Pair.Key, MoveTemp(Entry));
	}
	Mods.KeySort(TLess<FString>());
}
