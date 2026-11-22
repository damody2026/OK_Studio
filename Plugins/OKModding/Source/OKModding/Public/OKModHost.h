#pragma once
// The OK mod host in this process (Docs/OK_MOD_FRAMEWORK_PLAN.md §3, §8): ok_mod_host.dll (Tools/ok-mod/host), loaded
// with LoadLibrary like ok_rules.dll, which finds the Rust mods in Mods/, loads them and passes them events. Mods never
// touch Unreal objects; everything goes through JSON requests (include/ok_mod_host.h).
//
// The host opens when the first game mode starts (EnterMode), because which mods load depends on the mode (mod.toml
// "targets"). -NoMods, or Shift held while the game starts, keeps the DLL unloaded: the game runs as without mods.
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
#include "Misc/ScopeRWLock.h"

OKMODDING_API DECLARE_LOG_CATEGORY_EXTERN(LogOKMod, Log, All);

class OKMODDING_API FOKModHost
{
public:
	static FOKModHost& Get();

	/** Reads -NoMods / Shift once, at module start-up. */
	void Startup();
	/** Mods off for this run (-NoMods or Shift at start-up). */
	bool IsTurnedOff() const { return bTurnedOff; }
	bool IsOpen() const { return Handle != nullptr; }

	/**
	 * A game mode starts: reader, studio, pair or street. The first call opens the host for that mode; a later mode
	 * loads its own mods too (the street hands over to the 1-on-1 scene in the same process). Game thread.
	 */
	void EnterMode(const FString& Mode);
	void ExitMode(const FString& Mode);
	/** The mode entered last and not left, or empty. */
	const FString& CurrentMode() const { return Current; }

	/** One okm_dispatch request (JSON text in, JSON text out); false with Error when the host is closed or refuses. */
	bool Dispatch(const FString& Request, FString& Answer, FString& Error);
	TSharedPtr<FJsonObject> DispatchJson(const TSharedRef<FJsonObject>& Request, FString& Error);
	/** {"op":"list"}, or null when the host is not open. */
	TSharedPtr<FJsonObject> List();

	/** Shuts the mods down (engine exit). */
	void Close();

	/** Mods/ in the stage root (folder with stage.json above the executable), else the checkout; -ModsDir= / OK_MODS_DIR. */
	static FString ModsDir();
	/** <root>/UserData/config/mods next to that Mods/; OK_MODS_CONFIG_DIR. */
	static FString ConfigDir();
	/** Where ok_mod_host.dll is looked for: OK_MOD_HOST_DLL, next to the executable, the checkout's cargo build. */
	static TArray<FString> DllCandidates();

	/**
	 * For ok-extract inside this process (ok_set_mod_dispatch, Docs/OK_MOD_HOOK_INVENTORY.md §5.2): one request, the
	 * answer as a UTF-8 string the caller releases with RustFree, null when the host is closed. Any thread.
	 */
	static const char* RustDispatch(const char* RequestUtf8);
	static void RustFree(const char* Text);

	struct FApi;

private:
	bool Open(const FString& Mode);
	void RegisterCommands();
	FApi* Api = nullptr;
	void* Handle = nullptr;
	bool bStarted = false;
	bool bTurnedOff = false;
	bool bOpenFailed = false;
	FString Current;
	TSet<FString> Registered;
	FRWLock Lock;
};
