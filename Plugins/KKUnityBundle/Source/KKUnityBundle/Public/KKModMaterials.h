#pragma once
// Materials that OK mods bring for character parts (Docs/OK_MOD_FRAMEWORK_PLAN.md section 6.11), kept here so the
// material dispatch in KKPreviewActor can use them without knowing about the mod host (Plugins/OKModding fills it):
//   - shader families: a mod's material draws every part whose Unity shader has this name;
//   - per-part overrides: a mod's material on one part of one character (MaterialEditor's shader swap).
// A material is either a mod's cooked asset (B layer, from its pak) or a core parent with parameters (A layer).
#include "CoreMinimal.h"
#include "UObject/StrongObjectPtr.h"

class UMaterialInterface;
class UMaterialInstanceDynamic;
class UTexture;

struct FKKModMaterial
{
	/** <mod id>/<name> */
	FString Id;
	TStrongObjectPtr<UMaterialInterface> Material;
	/** The parameter that gets the part's own texture (empty: none). */
	FName MainTexture;
	/** The card's material values go to parameters of the same name. */
	bool bCopySourceValues = true;
	TMap<FName, float> Scalars;
	TMap<FName, FLinearColor> Vectors;
	TArray<TPair<FName, TStrongObjectPtr<UTexture>>> Textures;
};

namespace KKModMaterials
{
	/** Replaces the family table: lower-case Unity shader name -> material. Game thread. */
	KKUNITYBUNDLE_API void SetFamilies(TMap<FString, TSharedPtr<FKKModMaterial>> ByShader);
	KKUNITYBUNDLE_API TSharedPtr<FKKModMaterial> FindFamily(const FString& ShaderName);
	KKUNITYBUNDLE_API int32 FamilyCount();

	/**
	 * The instance a part draws with: the material's own parameter values, then (bCopySourceValues) the card's values
	 * for parameters of the same name (colours sRGB to linear), then the part's texture in MainTexture.
	 */
	KKUNITYBUNDLE_API UMaterialInstanceDynamic* MakeInstance(const FKKModMaterial& Material, UObject* Outer, UTexture* PartTexture,
		TFunctionRef<bool(const FString& Property, FLinearColor& Out)> SourceValue);
}
