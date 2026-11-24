#include "KKModIndex.h"
#include "KKZipManifest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

namespace
{
	bool PathInModpack(const FString& Path, const FString& ModsDir)
	{
		FString Rel = Path;
		if (FPaths::MakePathRelativeTo(Rel, *ModsDir))
		{
			return Rel.Contains(TEXT("Sideloader Modpack"));
		}
		return Path.Contains(TEXT("Sideloader Modpack"));
	}

	FString FullLower(const FString& Path)
	{
		FString Full = FPaths::ConvertRelativePathToFull(Path);
		FPaths::NormalizeFilename(Full);
		return Full.ToLower();
	}

	// Which package Sideloader would load for a GUID several of them declare. Both building and loading the cache end
	// here, so a cache answers what a build would.
	void ComputeWinners(const TArray<FKKZipmodFile>& Files, const FString& ModsDir, TMap<FString, FKKZipmod>& Out)
	{
		Out.Reset();
		TMap<FString, TArray<FKKLocalMod>> Candidates;
		TMap<FString, int64> Ticks;
		for (const FKKZipmodFile& File : Files)
		{
			Ticks.Add(File.Path, File.ModifiedTicks);
			for (const FKKZipmod& Mod : File.Mods)
			{
				if (Mod.Guid.IsEmpty())
				{
					continue;
				}
				FKKLocalMod Local;
				Local.Guid = Mod.Guid;
				Local.Name = Mod.Name;
				Local.Version = Mod.Version;
				Local.Path = Mod.Path;
				Candidates.FindOrAdd(Mod.Guid).Add(MoveTemp(Local));
			}
		}
		for (const TPair<FString, TArray<FKKLocalMod>>& Group : Candidates)
		{
			if (Group.Value.IsEmpty())
			{
				continue;
			}
			const int32 Pick = KKZip::PickInstalled(Group.Value, [&Ticks](const FKKLocalMod& Mod)
			{
				const int64* Found = Ticks.Find(Mod.Path);
				return Found ? *Found : 0;
			});
			const FKKLocalMod& Chosen = Group.Value[Pick];
			FKKZipmod Mod;
			Mod.Guid = Chosen.Guid;
			Mod.Name = Chosen.Name;
			Mod.Version = Chosen.Version;
			Mod.Path = Chosen.Path;
			Mod.bInSideloaderModpack = PathInModpack(Chosen.Path, ModsDir);
			Out.Add(Group.Key, MoveTemp(Mod));
		}
	}
}

bool ReadZipmodGuid(const FString& ZipPath, FString& OutGuid, FString& OutName)
{
	TArray<FKKLocalMod> Mods;
	FString Error;
	if (!KKZip::ReadManifests(ZipPath, Mods, Error) || Mods.IsEmpty())
	{
		return false;
	}
	OutGuid = Mods[0].Guid;
	OutName = Mods[0].Name;
	return !OutGuid.IsEmpty();
}

bool FKKModIndex::Build(const FString& InModsDir, FString& OutError, TFunction<void(int32, int32)> OnProgress)
{
	// What the cache already knows, when it is about this same folder: reused for every package whose size and
	// modification time still match, so a repeat build reads no manifest at all.
	TMap<FString, FKKZipmodFile> Known;
	if (ModsDir == InModsDir)
	{
		for (FKKZipmodFile& File : Files)
		{
			Known.Add(FullLower(File.Path), MoveTemp(File));
		}
	}
	ModsDir = InModsDir;
	GuidToMod.Reset();
	Unreadable.Reset();
	TArray<FString> Paths;
	IFileManager::Get().FindFilesRecursive(Paths, *InModsDir, TEXT("*.zipmod"), true, false);
	Paths.Sort();
	TArray<FKKZipmodFile> Fresh;
	Fresh.Reserve(Paths.Num());
	for (int32 I = 0; I < Paths.Num(); ++I)
	{
		FString Full = FPaths::ConvertRelativePathToFull(Paths[I]);
		FPaths::NormalizeFilename(Full);
		const FFileStatData Stat = IFileManager::Get().GetStatData(*Full);
		FKKZipmodFile Entry;
		Entry.Path = Full;
		Entry.Size = Stat.bIsValid ? Stat.FileSize : 0;
		Entry.ModifiedTicks = Stat.bIsValid ? Stat.ModificationTime.GetTicks() : 0;
		const FKKZipmodFile* Cached = Known.Find(Full.ToLower());
		if (Cached && Cached->Size == Entry.Size && Cached->ModifiedTicks == Entry.ModifiedTicks)
		{
			Entry.Error = Cached->Error;
			Entry.Mods = Cached->Mods;
		}
		else
		{
			TArray<FKKLocalMod> Mods;
			if (!KKZip::ReadManifests(Full, Mods, Entry.Error))
			{
				Entry.Mods.Reset();
			}
			else
			{
				for (const FKKLocalMod& Mod : Mods)
				{
					FKKZipmod Zip;
					Zip.Guid = Mod.Guid;
					Zip.Name = Mod.Name;
					Zip.Version = Mod.Version;
					Zip.Path = Full;
					Zip.bInSideloaderModpack = PathInModpack(Full, InModsDir);
					Entry.Mods.Add(MoveTemp(Zip));
				}
			}
		}
		if (!Entry.Error.IsEmpty())
		{
			Unreadable.Add(Entry.Path, Entry.Error);
		}
		Fresh.Add(MoveTemp(Entry));
		if (OnProgress && ((I & 127) == 0 || I + 1 == Paths.Num()))
		{
			OnProgress(I + 1, Paths.Num());
		}
	}
	Files = MoveTemp(Fresh);
	ComputeWinners(Files, InModsDir, GuidToMod);
	if (GuidToMod.Num() == 0 && Paths.Num() > 0)
	{
		OutError = TEXT("scanned zipmods but found no GUIDs");
		LastError = OutError;
		return false;
	}
	return true;
}

bool FKKModIndex::LoadCache(const FString& CachePath)
{
	FString JsonStr;
	if (!FFileHelper::LoadFileToString(JsonStr, *CachePath))
	{
		return false;
	}
	TSharedPtr<FJsonObject> Root;
	const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(JsonStr);
	if (!FJsonSerializer::Deserialize(Reader, Root) || !Root.IsValid())
	{
		return false;
	}
	// Only the format that remembers each package's size and modification time can be updated instead of rebuilt; the
	// older one (GUID to path alone) is treated as absent, and rebuilding it now costs a manifest read per package.
	const TArray<TSharedPtr<FJsonValue>>* FileList = nullptr;
	if (!Root->TryGetArrayField(TEXT("files"), FileList) || !FileList)
	{
		return false;
	}
	ModsDir = Root->GetStringField(TEXT("mods_dir"));
	Files.Reset();
	GuidToMod.Reset();
	Unreadable.Reset();
	for (const TSharedPtr<FJsonValue>& Value : *FileList)
	{
		const TSharedPtr<FJsonObject>* Object = nullptr;
		if (!Value.IsValid() || !Value->TryGetObject(Object) || !Object)
		{
			continue;
		}
		FKKZipmodFile File;
		File.Path = (*Object)->GetStringField(TEXT("path"));
		if (File.Path.IsEmpty())
		{
			continue;
		}
		(*Object)->TryGetNumberField(TEXT("size"), File.Size);
		// A tick count (100 ns since year 1) is past what a JSON number keeps exactly, so it is written as text.
		FString TicksText;
		if ((*Object)->TryGetStringField(TEXT("ticks"), TicksText))
		{
			File.ModifiedTicks = FCString::Atoi64(*TicksText);
		}
		(*Object)->TryGetStringField(TEXT("error"), File.Error);
		const TArray<TSharedPtr<FJsonValue>>* ModList = nullptr;
		if ((*Object)->TryGetArrayField(TEXT("mods"), ModList) && ModList)
		{
			for (const TSharedPtr<FJsonValue>& ModValue : *ModList)
			{
				const TSharedPtr<FJsonObject>* ModObject = nullptr;
				if (!ModValue.IsValid() || !ModValue->TryGetObject(ModObject) || !ModObject)
				{
					continue;
				}
				FKKZipmod Mod;
				Mod.Path = File.Path;
				Mod.Guid = (*ModObject)->GetStringField(TEXT("guid"));
				(*ModObject)->TryGetStringField(TEXT("name"), Mod.Name);
				(*ModObject)->TryGetStringField(TEXT("version"), Mod.Version);
				Mod.bInSideloaderModpack = PathInModpack(File.Path, ModsDir);
				if (!Mod.Guid.IsEmpty())
				{
					File.Mods.Add(MoveTemp(Mod));
				}
			}
		}
		if (!File.Error.IsEmpty())
		{
			Unreadable.Add(File.Path, File.Error);
		}
		Files.Add(MoveTemp(File));
	}
	ComputeWinners(Files, ModsDir, GuidToMod);
	return !Files.IsEmpty();
}

bool FKKModIndex::SaveCache(const FString& CachePath) const
{
	TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
	Root->SetStringField(TEXT("mods_dir"), ModsDir);
	TArray<TSharedPtr<FJsonValue>> FileList;
	FileList.Reserve(Files.Num());
	for (const FKKZipmodFile& File : Files)
	{
		TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
		Object->SetStringField(TEXT("path"), File.Path);
		Object->SetNumberField(TEXT("size"), double(File.Size));
		Object->SetStringField(TEXT("ticks"), FString::Printf(TEXT("%lld"), File.ModifiedTicks));
		if (!File.Error.IsEmpty())
		{
			Object->SetStringField(TEXT("error"), File.Error);
		}
		TArray<TSharedPtr<FJsonValue>> ModList;
		for (const FKKZipmod& Mod : File.Mods)
		{
			TSharedRef<FJsonObject> ModObject = MakeShared<FJsonObject>();
			ModObject->SetStringField(TEXT("guid"), Mod.Guid);
			if (!Mod.Name.IsEmpty())
			{
				ModObject->SetStringField(TEXT("name"), Mod.Name);
			}
			if (!Mod.Version.IsEmpty())
			{
				ModObject->SetStringField(TEXT("version"), Mod.Version);
			}
			ModList.Add(MakeShared<FJsonValueObject>(ModObject));
		}
		Object->SetArrayField(TEXT("mods"), ModList);
		FileList.Add(MakeShared<FJsonValueObject>(Object));
	}
	Root->SetArrayField(TEXT("files"), FileList);
	FString JsonStr;
	const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&JsonStr);
	FJsonSerializer::Serialize(Root, Writer);
	return FFileHelper::SaveStringToFile(JsonStr, *CachePath);
}

FString FKKModIndex::DefaultLibraryDir()
{
	const FString Configured = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_BASE_LIBRARY"));
	if (!Configured.IsEmpty()) return Configured;
	return FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir() / TEXT("IndependentResources/base_v1"));
}

bool FKKModIndex::LoadGuidRows(const FString& Rows, const FString& InModsDir, FString& OutError)
{
	GuidToMod.Reset();
	Files.Reset();
	Unreadable.Reset();
	ModsDir = InModsDir;
	if (Rows.IsEmpty())
	{
		OutError = TEXT("the base library carries no mods index: run `ok-extract <game> --oklib mods-index <library>`");
		LastError = OutError;
		return false;
	}
	TArray<FString> Lines;
	Rows.ParseIntoArrayLines(Lines);
	for (const FString& Line : Lines)
	{
		if (Line.IsEmpty() || Line.StartsWith(TEXT("#"))) continue;
		TArray<FString> Cols;
		Line.ParseIntoArray(Cols, TEXT("\t"), false);
		if (Cols.Num() < 3) continue;
		// Every archive declaring the GUID is listed, in the tree's walk order; the first is the one the index's
		// own lookup prefers, so a later line does not replace it.
		if (GuidToMod.Contains(Cols[0])) continue;
		FKKZipmod Mod;
		Mod.Guid = Cols[0];
		Mod.Version = Cols[1];
		Mod.Path = ModsDir / Cols[2];
		Mod.Name = FPaths::GetBaseFilename(Cols[2]);
		Mod.bInSideloaderModpack = PathInModpack(Mod.Path, ModsDir);
		GuidToMod.Add(Mod.Guid, Mod);
	}
	LastError.Reset();
	return GuidToMod.Num() > 0;
}

bool FKKModIndex::CoversModsDir(const FString& Mods) const
{
	return !ModsDir.IsEmpty() && !Mods.IsEmpty() && FPaths::IsSamePath(ModsDir, Mods);
}

const FKKZipmod* FKKModIndex::Find(const FString& Guid) const
{
	return GuidToMod.Find(Guid);
}

TArray<FKKResolveInfo> FKKModIndex::Missing(const TArray<FKKResolveInfo>& Resolves) const
{
	TArray<FKKResolveInfo> Out;
	TSet<FString> Seen;
	for (const FKKResolveInfo& Info : Resolves)
	{
		if (Info.ModID.IsEmpty() || Seen.Contains(Info.ModID))
		{
			continue;
		}
		Seen.Add(Info.ModID);
		if (!GuidToMod.Contains(Info.ModID))
		{
			Out.Add(Info);
		}
	}
	return Out;
}
