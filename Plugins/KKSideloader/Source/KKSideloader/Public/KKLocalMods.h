#pragma once

#include "CoreMinimal.h"
#include "KKCardTypes.h"

enum class EKKLocalModStatus : uint8 { Found, Missing, Conflict };

struct KKSIDELOADER_API FKKLocalMod
{
	FString Guid;
	FString Name;
	FString Version;
	FString Path;
};

struct KKSIDELOADER_API FKKLocalModRequirement
{
	FString Guid;
	EKKLocalModStatus Status = EKKLocalModStatus::Missing;
	TArray<FKKLocalMod> Candidates;
};

class FKKModIndex;

// Discovers manifests only; Found never implies that 3D conversion is supported.
class KKSIDELOADER_API FKKLocalModIndex
{
public:
	/** The packages beside the card, plus — when the card sits inside a game installation — that game's mods/.
	 *  With `Installed` (the index built once for that mods/ folder) only the GUIDs in `Needed` are looked up there;
	 *  without it, every package in mods/ is read, which on a real installation is thousands of files and belongs on a
	 *  worker, never on the game thread. */
	void BuildForCard(const FString& CardPath, const TArray<FKKResolveInfo>& Needed = {}, const FKKModIndex* Installed = nullptr);
	TArray<FKKLocalModRequirement> Resolve(const TArray<FKKResolveInfo>& References) const;
	bool CopyFound(const TArray<FKKResolveInfo>& References, const FString& Directory, FString& Error) const;
	TMap<FString, TArray<FKKLocalMod>> ByGuid;
	TArray<FString> Diagnostics;
	// Empty for cards outside a recognized game installation.
	FString GameRoot;
	TArray<FString> ZipmodPaths;
	TArray<FString> SkippedGameMods;

private:
	void AddGameMods(const TArray<FKKResolveInfo>& Needed, const FKKModIndex* Installed, TArray<FString>& ValidPaths);
};
