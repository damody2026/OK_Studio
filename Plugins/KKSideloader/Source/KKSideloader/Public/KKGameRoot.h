#pragma once

#include "CoreMinimal.h"
#include "KKGameRoot.generated.h"

UCLASS(config = Game, defaultconfig)
class KKSIDELOADER_API UKKGameRoot : public UObject
{
	GENERATED_BODY()

public:
	UKKGameRoot();

	UPROPERTY(config, EditAnywhere, Category = "OpenKoikatsu")
	FString Root;

	// Local library: models of third-party mods (character and Studio mods) converted on this machine, kept apart from
	// the shared base library (OK_LOCAL_LIBRARY; empty: Content/IndependentResources/local_v1 when present).
	UPROPERTY(config, EditAnywhere, Category = "OpenKoikatsu")
	FString LocalLibrary;

	UFUNCTION(BlueprintCallable, Category = "OpenKoikatsu")
	static UKKGameRoot* Get();

	// True with -NoGameRoot (a package: no original game on this machine; Root is then empty unless the user set one).
	static bool NoGame();

	// The user's own choice (the reader's 設定 › 遊戲目錄 page), kept in GameUserSettings.ini [OKGameRoot] -- writable in a
	// package, whose DefaultGame.ini is read-only cooked content. Get() takes it over DefaultGame.ini, and over
	// -NoGameRoot too: that flag only keeps the build machine's path out, it does not stop the user from naming theirs.
	// Callers read Root at the moment they need it, so a change counts from the next card open.
	static void SetUserRoot(const FString& Path);
	static void SetUserLocalLibrary(const FString& Path);
	// Forget the user's choice: back to DefaultGame.ini (or nothing, with -NoGameRoot).
	static void ClearUserRoot();
	static void ClearUserLocalLibrary();
	static bool HasUserRoot();
	static bool HasUserLocalLibrary();
	// What Root and LocalLibrary are without the user's choice.
	static FString DefaultRoot();
	static FString DefaultLocalLibrary();
	// LocalLibrary as an absolute folder (relative to the project), or empty; also published as OK_LOCAL_LIBRARY by
	// SetUserLocalLibrary, which the Rust side reads at each open.
	static FString ResolvedLocalLibrary();

	UFUNCTION(BlueprintCallable, Category = "OpenKoikatsu")
	FString Abdata() const;

	UFUNCTION(BlueprintCallable, Category = "OpenKoikatsu")
	FString Mods() const;

	UFUNCTION(BlueprintCallable, Category = "OpenKoikatsu")
	FString CharaFemale() const;

	UFUNCTION(BlueprintCallable, Category = "OpenKoikatsu")
	FString Coordinate() const;
};
