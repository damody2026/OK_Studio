#pragma once

#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"

class UOKCharacterController;

// The card reader's side of the OK mod Character API and reader UI API (Docs/OK_MOD_HOOKS.md, plan §6.2–§6.4).
// Everything goes to the mod host as JSON (FOKModHost, Tools/ok-mod/host/src/card.rs); nothing here runs mod code
// directly, and with mods off (-NoMods, no host) every call does nothing.
//
// - A card opened: the mods subscribed to character_load get their okMx section (or none); the reader says which mods
//   the card uses that are not here. Another outfit of the same card: outfit_change.
// - A card saved: character_save, the host writes the sections into the saved file (other mods' kept byte for byte).
// - Mod controls: reader_ui pages (a "Mods" category on the reader screen), their values as registry rows
//   (`mod.<id>.<key>`, OKCharacterMCPRegistry), so reader_call get/set and the page controls (OKReaderPageItems) both
//   reach them; a change goes to the mod (reader_set), and what it asks back (registry edits, a notice) is done.
// - "Apply this mod's data when a card loads" (MakerLoadToggle): keys `reader.mod_apply.<id>`, kept in
//   Saved/CardReader/mod_apply.json.
// - A reply may name the outfits ({"outfit_names":{"0":"制服"}}): the outfit list shows "服裝 1：制服".
// - A voice line spoken: speech_start; a mod may answer with a subtitle the reader shows.
namespace OKReaderMods
{
	bool Active();
	// A preview finished loading this card and outfit (character_load or outfit_change).
	void Loaded(UOKCharacterController* G,const FString& Card,int32 Outfit);
	// A card was written to Path (the reader's save): the mods' sections into it.
	void Saved(UOKCharacterController* G,const FString& Path);
	// A voice line started; Text is what she says (as the reader lists it).
	void Speech(UOKCharacterController* G,const FString& Text);

	// The registry rows of every mod control (kind, label, value, options; category "mods").
	TArray<TSharedPtr<FJsonValue>> Rows(UOKCharacterController* G);
	bool IsModKey(const FString& Key);
	// A mod control's value now (reader.values, asked again after a card loads and after each change); null when none.
	TSharedPtr<FJsonValue> Value(const FString& Key);
	// An item's text field, from the reader's text table when it gives "<field>_id" (label, text, name).
	FString ItemText(const TSharedPtr<FJsonObject>& Item,const TCHAR* Field);
	// One mod control changed (registry write). False with Error when the mod refused.
	bool Set(UOKCharacterController* G,const FString& Key,const TSharedPtr<FJsonValue>& Value,FString& Error);

	// The reader screen's "Mods" pages: name and items (pages.json item objects, keys already mod.<id>.*).
	// Spec: the whole page object (its layout and style; Docs/OK_MOD_HOOKS.md §4).
	struct FPage {FString Mod,Name;TArray<TSharedPtr<FJsonObject>> Items;TSharedPtr<FJsonObject> Spec;};
	TArray<FPage> Pages();
	// Mods that take card data on load (character_load subscribers): id and name.
	TArray<TPair<FString,FString>> CardMods();

	// reader.mod_apply.<id>
	bool IsApplyKey(const FString& Key);
	bool ApplyOnLoad(const FString& Mod);
	void SetApplyOnLoad(const FString& Mod,bool bOn);

	// A name a mod gave this outfit of this card ({"outfit_names": {"<index>": name}} in a reply), or empty.
	FString OutfitName(const FString& Card,int32 Outfit);

	// A button's mod command (`mod.<id>.<name>`): run, its text shown as a notice.
	bool RunCommand(UOKCharacterController* G,const FString& Command,FString& Error);

	// A mod's .dui panel raised an event (plan §6.13 D2): hook ui.<mod>.<event> to that mod alone, payload
	// {"event","value"}; its reply is followed like any hook's.
	bool Emit(UOKCharacterController* G,const FString& Mod,const FString& Event,const FString& Value,FString& Error);
}
