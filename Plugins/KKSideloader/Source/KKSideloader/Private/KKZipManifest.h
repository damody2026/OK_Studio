#pragma once

#include "CoreMinimal.h"
#include "KKLocalMods.h"

// Reading a zipmod's identity without reading the zipmod.
//
// A zipmod is a ZIP whose manifest.xml names its GUID, name and version; a Sideloader modpack package is hundreds of
// megabytes of assets around that one small entry. Both indexes used to read the whole file to find it
// (FFileHelper::LoadFileToArray in KKModIndex), which for a 7,296-package / 111 GiB mods/ folder meant reading 111 GiB
// to learn 7,296 GUIDs — minutes on the game thread (the user, 2026-11-24: dropping a card from the game's own
// UserData/chara/female froze the reader). These read the ZIP end record, the central directory and the manifest's own
// bytes: ~65 KiB of seeks per package, 466 MiB for that same folder.
namespace KKZip
{
	// Every manifest.xml in the package (a zipmod may declare more than one). False with Error set for a file that is
	// not a usable zipmod; the error text is shown to the user.
	bool ReadManifests(const FString& Path, TArray<FKKLocalMod>& Mods, FString& Error);

	// Byte-for-byte, in 64 KiB blocks. Two packages with the same GUID are the same mod only if their bytes match.
	bool SameContents(const FString& A, const FString& B);

	// Sideloader.cs's order: numeric runs compared as numbers, "1.10" after "1.9", a leading v/r ignored.
	// Negative when A is older, 0 when equal.
	int32 CompareVersions(const FString& A, const FString& B);

	// Which of several packages declaring one GUID Sideloader would load: version descending, then the longer file
	// name; if any candidate has no version, the newest file wins. Candidates must not be empty.
	int32 PickInstalled(const TArray<FKKLocalMod>& Candidates, TFunctionRef<int64(const FKKLocalMod&)> ModifiedTicks);
}
