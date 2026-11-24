#include "KKLocalMods.h"
#include "KKZipManifest.h"
#include "KKModIndex.h"
#include "HAL/FileManager.h"
#include "Misc/Paths.h"

// Which zipmods a card needs and where they are. Two sources: the packages beside the card (its own folder) and, when
// the card sits inside a game installation, that game's mods/.
//
// The game's mods/ is read through the installed index (FKKModIndex, read from the base library's own
// mods_guids.txt: no manifest of the tree is opened and nothing is cached) and only for the GUIDs this card names. Building it here, per selection, read every package in
// mods/ — 7,296 of them, 111 GiB, on the game thread — so dropping a card from the game's own UserData/chara/female
// froze the reader for minutes with nothing on screen (the user, 2026-11-24). Without an index (tests, other callers)
// it still scans, which is what the fixtures exercise.
void FKKLocalModIndex::BuildForCard(const FString& CardPath, const TArray<FKKResolveInfo>& Needed, const FKKModIndex* Installed)
{
	ByGuid.Reset(); Diagnostics.Reset(); GameRoot.Reset(); ZipmodPaths.Reset(); SkippedGameMods.Reset();
	FString FullCard=FPaths::ConvertRelativePathToFull(CardPath); FPaths::NormalizeFilename(FullCard); FPaths::CollapseRelativeDirectories(FullCard);
	const FString Directory=FPaths::GetPath(FullCard);
	for(FString Candidate=Directory; !Candidate.IsEmpty();){
		if(IFileManager::Get().DirectoryExists(*(Candidate/TEXT("abdata")))
			&& IFileManager::Get().DirectoryExists(*(Candidate/TEXT("UserData")))
			&& (IFileManager::Get().FileExists(*(Candidate/TEXT("KoikatsuSunshine.exe")))
				|| IFileManager::Get().FileExists(*(Candidate/TEXT("Koikatu.exe"))))){GameRoot=Candidate;break;}
		const FString Parent=FPaths::GetPath(Candidate);if(Parent==Candidate)break;Candidate=Parent;
	}
	// The packages beside the card: read whole, there are a handful of them.
	TArray<FString> Names;
	IFileManager::Get().FindFiles(Names, *(Directory / TEXT("*.zipmod")), true, false);
	Names.Sort();
	TArray<FString> ValidPaths;
	for(const FString& Name:Names)
	{
		const FString Path=Directory/Name;
		TArray<FKKLocalMod> Mods; FString Error;
		if(!KKZip::ReadManifests(Path,Mods,Error)){Diagnostics.Add(Path+TEXT(": ")+Error);continue;}
		ValidPaths.Add(Path);
		for(const FKKLocalMod& Mod:Mods)
		{
			TArray<FKKLocalMod>& Entries=ByGuid.FindOrAdd(Mod.Guid);
			if(!Entries.ContainsByPredicate([&](const FKKLocalMod& Existing){return Existing.Path==Mod.Path||KKZip::SameContents(Existing.Path,Mod.Path);}))Entries.Add(Mod);
		}
	}
	if(!GameRoot.IsEmpty())AddGameMods(Needed,Installed,ValidPaths);
	ValidPaths.Sort();
	ZipmodPaths=MoveTemp(ValidPaths);
}

void FKKLocalModIndex::AddGameMods(const TArray<FKKResolveInfo>& Needed, const FKKModIndex* Installed, TArray<FString>& ValidPaths)
{
	const FString Mods=GameRoot/TEXT("mods");
	auto Attach=[&](const FKKLocalMod& Chosen)
	{
		ValidPaths.AddUnique(Chosen.Path);
		TArray<FKKLocalMod>& Entries=ByGuid.FindOrAdd(Chosen.Guid);
		if(!Entries.ContainsByPredicate([&](const FKKLocalMod& Existing){return FPaths::IsSamePath(Existing.Path,Chosen.Path)||KKZip::SameContents(Existing.Path,Chosen.Path);}))Entries.Add(Chosen);
	};
	if(Installed)
	{
		// Only this card's own GUIDs, from the index built once for this mods/ folder.
		if(!Installed->CoversModsDir(Mods))
		{
			SkippedGameMods.Add(Mods+TEXT(": 基礎庫沒有這個 mods 的索引（ok-extract --oklib shared-ignore），這張卡要的 zipmod 先當成缺少"));
			return;
		}
		TSet<FString> Asked;
		for(const FKKResolveInfo& Ref:Needed)
		{
			if(Ref.ModID.IsEmpty()||Asked.Contains(Ref.ModID))continue;
			Asked.Add(Ref.ModID);
			if(const FKKZipmod* Found=Installed->Find(Ref.ModID))
			{
				FKKLocalMod Mod; Mod.Guid=Found->Guid; Mod.Name=Found->Name; Mod.Version=Found->Version; Mod.Path=Found->Path;
				Attach(Mod);
			}
		}
		for(const TPair<FString,FString>& Bad:Installed->Unreadable)SkippedGameMods.Add(Bad.Key+TEXT(": ")+Bad.Value);
		return;
	}
	// No index: every package in mods/, as before.
	TArray<FString> Packages;IFileManager::Get().FindFilesRecursive(Packages,*Mods,TEXT("*.zipmod"),true,false);
	Packages.Sort();
	TSet<FString> Beside;
	for(const FString& Path:ValidPaths)Beside.Add(FPaths::ConvertRelativePathToFull(Path).ToLower());
	TMap<FString,TArray<FKKLocalMod>> GameMods;
	for(const FString& Path:Packages)
	{
		FString Full=FPaths::ConvertRelativePathToFull(Path);FPaths::NormalizeFilename(Full);
		if(Beside.Contains(Full.ToLower()))continue;
		TArray<FKKLocalMod> Declared; FString Error;
		if(!KKZip::ReadManifests(Full,Declared,Error)){SkippedGameMods.Add(Full+TEXT(": ")+Error);continue;}
		for(const FKKLocalMod& Mod:Declared)GameMods.FindOrAdd(Mod.Guid).Add(Mod);
	}
	for(TPair<FString,TArray<FKKLocalMod>>& Group:GameMods)
	{
		if(Group.Value.IsEmpty())continue;
		const int32 Pick=KKZip::PickInstalled(Group.Value,[](const FKKLocalMod& M){return IFileManager::Get().GetTimeStamp(*M.Path).GetTicks();});
		Attach(Group.Value[Pick]);
	}
}
TArray<FKKLocalModRequirement> FKKLocalModIndex::Resolve(const TArray<FKKResolveInfo>& References) const
{
	TArray<FKKLocalModRequirement> Result; TSet<FString> Seen;
	for (const FKKResolveInfo& Ref : References)
	{
		if (Ref.ModID.IsEmpty() || Seen.Contains(Ref.ModID)) continue;
		Seen.Add(Ref.ModID); FKKLocalModRequirement Item; Item.Guid = Ref.ModID;
		if (const TArray<FKKLocalMod>* Entries = ByGuid.Find(Ref.ModID))
		{
			Item.Candidates = *Entries;
			Item.Status = Entries->Num() == 1 ? EKKLocalModStatus::Found : EKKLocalModStatus::Conflict;
		}
		Result.Add(MoveTemp(Item));
	}
	return Result;
}

bool FKKLocalModIndex::CopyFound(const TArray<FKKResolveInfo>& References, const FString& Directory, FString& Error) const
{
	TSet<FString> Copied;
	for (const FKKLocalModRequirement& Item : Resolve(References))
	{
		if (Item.Status != EKKLocalModStatus::Found) continue;
		const FString Source = Item.Candidates[0].Path;
		if (Copied.Contains(Source)) continue;
		Copied.Add(Source);
		FString Destination = Directory / FPaths::GetCleanFilename(Source);
		if (FPaths::IsSamePath(Source, Destination)) continue;
		if (IFileManager::Get().FileExists(*Destination))
		{
			if (KKZip::SameContents(Source, Destination)) continue;
			Error = FString::Printf(TEXT("輸出目錄已有不同的 %s，未覆寫。請使用其他目錄。"), *FPaths::GetCleanFilename(Source)); return false;
		}
		if (IFileManager::Get().Copy(*Destination, *Source, false) != COPY_OK)
		{ Error = FString::Printf(TEXT("無法複製 zipmod：%s"), *Source); return false; }
	}
	return true;
}
