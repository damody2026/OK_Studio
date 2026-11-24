#pragma once

#include "CoreMinimal.h"
#include "KKCardTypes.h"

struct KKSIDELOADER_API FKKZipmod
{
	FString Guid;
	FString Path;
	FString Name;
	FString Version;
	bool bInSideloaderModpack = false;
};

/** One package as the cache remembers it, with what makes the entry stale. */
struct KKSIDELOADER_API FKKZipmodFile
{
	FString Path;
	int64 Size = 0;
	int64 ModifiedTicks = 0;
	/** Why its manifest could not be read; empty when it was read. */
	FString Error;
	TArray<FKKZipmod> Mods;
};

/** Which GUID lives in which package of one mods/ folder.
 *
 *  Built from the packages' manifests only (KKZip::ReadManifests), never from their contents, and kept in a cache that
 *  survives restarts: a second build reads the manifest of a package the cache does not already have at that size and
 *  modification time. On a real installation (7,296 packages, 111 GiB) a full build reads ~466 MiB and a repeat build
 *  almost nothing; it still belongs on a worker thread, with a progress bar (Docs/READER_BUSY_PROGRESS.md). */
class KKSIDELOADER_API FKKModIndex
{
public:
	/** OnProgress, when bound, is called with (packages done, packages in all) every so often; it must be safe to call
	 *  from the thread Build runs on. */
	bool Build(const FString& ModsDir, FString& OutError, TFunction<void(int32, int32)> OnProgress = nullptr);
	/** The same map read from the base library's own index (`<library>/mods_guids.txt`, written by
	 *  `ok-extract <game> --oklib shared-ignore <library>`): which archive of `ModsDir` declares each GUID, without
	 *  opening a single package and without a cache. This is how the reader builds it -- reading the installation's
	 *  7,296 manifests at every start is a whole-tree read, and keeping the result in Saved/mod_index.json is a
	 *  cache; an open may do neither (2026-11-24). Err when the library has no index yet. */
	bool LoadLibraryGuids(const FString& LibraryDir, const FString& ModsDir, FString& OutError);
	/** OK_BASE_LIBRARY, else Content/IndependentResources/base_v1. */
	static FString DefaultLibraryDir();
	bool LoadCache(const FString& CachePath);
	bool SaveCache(const FString& CachePath) const;
	const FKKZipmod* Find(const FString& Guid) const;
	TArray<FKKResolveInfo> Missing(const TArray<FKKResolveInfo>& Resolves) const;
	int32 Num() const { return GuidToMod.Num(); }
	/** Whether this index was built for that mods/ folder, so that "not here" is an answer about it. */
	bool CoversModsDir(const FString& Mods) const;

	TMap<FString, FKKZipmod> GuidToMod;
	TArray<FKKZipmodFile> Files;
	/** Package path to why its manifest could not be read. */
	TMap<FString, FString> Unreadable;
	FString ModsDir;
	FString LastError;
};

bool KKSIDELOADER_API ReadZipmodGuid(const FString& ZipPath, FString& OutGuid, FString& OutName);
