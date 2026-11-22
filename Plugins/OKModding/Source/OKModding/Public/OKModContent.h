#pragma once
// What enabled mods bring besides code (Docs/OK_MOD_FRAMEWORK_PLAN.md section 6.11):
//   - B layer: their cooked material pak (Mods/<id>/content/<root>.pak), mounted with its own shader library, every
//     asset checked against the class whitelist and the game's content build before anything uses it;
//   - A layer: core parents (Content/IndependentResources/PreviewMaterials) with the mod's parameters and PNG textures;
//   - shader families: Unity shader names a mod material draws (KKModMaterials, used by the card reader's parts);
//   - per-part overrides at run time (mod.material.apply).
// Cooked content cannot load in the editor: there a B-layer material uses its A-layer fallback (`parent`).
#include "CoreMinimal.h"
#include "KKModMaterials.h"

namespace OKModContent
{
	/** Reads the host's {"op":"content"}, mounts what is new, rebuilds the material and family tables. Game thread. */
	OKMODDING_API void Refresh();
	/** "<ini [OKModding] ContentBuild>@<engine major.minor.patch-changelist>": what a mod's content_build must equal. */
	OKMODDING_API FString ContentBuild();
	/** A mod material by "<mod id>/<name>". */
	OKMODDING_API TSharedPtr<FKKModMaterial> Find(const FString& Id);
	OKMODDING_API TArray<FString> MaterialIds();
	/**
	 * A mod's .dui panel (plan §6.13 D2): the class of /<content root>/UI/WBP_<Name>, a UOKModDreamPanel, checked to be
	 * only what the DreamGUI compiler made from the mod's ui/<Name>.dui. Null (logged once) when the mod's content is not
	 * loaded or the panel was refused. Game thread.
	 */
	OKMODDING_API UClass* Widget(const FString& ModId, const FString& Name);

	/**
	 * The card reader's per-part material overrides (mod.material.apply) kept in the card: the core's okMx section
	 * "ok.materials", {"overrides":[{"part","material":"<mod>/<name>","fallback":{A-layer: parent, scalars, vectors}}]}.
	 * CardLoaded reads it and applies each override to the characters shown, using the card's fallback (a core parent
	 * with the saved parameters) when that mod material is not here (mod not installed or disabled); CardSaved writes the
	 * overrides of the character shown into the saved card. Game thread.
	 */
	OKMODDING_API void CardLoaded(const FString& Card);
	OKMODDING_API void CardSaved(const FString& Card);
}
