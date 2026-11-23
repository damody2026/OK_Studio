#pragma once
// Mod hotkeys in every mode (Docs/OK_MOD_HOOKS.md §5): a mod declares a hotkey config entry (Registrar::hotkey); the
// host lists them ({"op":"hotkeys"}) and this watches the keyboard for the chords bound to them, sending
// {"op":"key","chord","mode"} when one is pressed -- the mod gets the hook key.<id>.<name>. One Slate input
// pre-processor for the whole game: a mode takes mod hotkeys once it calls Listen (one line in each mode's start-up),
// so a screen that never asked for them (the crowd room) is left alone.
//
// Keys are not taken while a text field has the keyboard (typing a name must not fire a mod), while a key repeats, or
// while a mouse button is held. A matched chord is consumed: the player bound it to the mod.
//
// Rebinding: Capture(Mod, Name) waits for the next chord and stores it as the mod's config value (config_set) --
// the reader's Mods › 熱鍵 page and the console command OKMod.Bind <mod> <name> [chord] use it; OKMod.Keys lists them.
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"

class OKMODDING_API FOKModKeys
{
public:
	/** One reply of the host ({"mod","ok","text"|"json"|"error"}) to a hotkey; Mod is the mod's id. */
	using FOnReply = TFunction<void(const FString& Mod, const TSharedPtr<FJsonObject>& Reply)>;

	/**
	 * The mode Mode ("reader", "studio", "pair", "street") takes mod hotkeys from now on; OnReply gets each mod's reply
	 * (null: text replies only go to the log). Calling again for the same mode replaces the handler. Game thread.
	 */
	static void Listen(const FString& Mode, FOnReply OnReply = nullptr);
	/** The mode stops taking them (its handler would point at a screen that is gone). */
	static void Stop(const FString& Mode);

	struct FHotkey
	{
		FString Mod, Name, Chord, Default, DescriptionId;
	};
	/** The hotkeys of the mods loaded now (bound or not), from the host. */
	static TArray<FHotkey> List();
	/** Stores Chord (Unreal key names joined by '+'; empty unbinds) as the mod's binding. */
	static bool Bind(const FString& Mod, const FString& Name, const FString& Chord, FString& Error);
	/**
	 * The next chord pressed becomes the binding of Name of Mod (Escape cancels, Backspace unbinds); Done gets the new
	 * chord, or nothing with bCancelled. The chord is not sent to any mod.
	 */
	static void Capture(const FString& Mod, const FString& Name, TFunction<void(const FString& Chord, bool bCancelled)> Done);
	static bool IsCapturing();

	/** Text of a reply worth showing the player: "text", or the JSON's "notice" / "status"; empty otherwise. */
	static FString ShownText(const TSharedPtr<FJsonObject>& Reply);
	/** The chord's text for the player ("Ctrl+K"); "—" for none. */
	static FString Display(const FString& Chord);
};
