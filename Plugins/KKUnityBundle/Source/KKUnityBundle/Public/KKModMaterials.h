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
	/** Hands the game's mod host to the ok-extract this module links (its texture hooks, material.post_texture), or
	 *  clears it with nulls. Must be this module's copy: in a modular build every module that links ok_extract.lib has
	 *  its own, and only this one opens cards. */
	KKUNITYBUNDLE_API void SetExtractDispatch(const char* (*Dispatch)(const char* RequestJson), void (*Free)(const char* Text));
	/** Hands the mod host's per-frame function (okm_frame) to this module's ok-extract (ok_set_mod_frame), or clears it
	 *  with null. Called from ok-extract's worker threads once per character per frame. */
	KKUNITYBUNDLE_API void SetExtractFrame(uint32 (*Frame)(void* FrameView));
	/** A resolver asked before the family table (OKModding sets it while a mod subscribes to material.resolve_shader);
	 *  null to clear. Game thread. */
	KKUNITYBUNDLE_API void SetResolver(TFunction<TSharedPtr<FKKModMaterial>(const FString& ShaderName, const FString& Part)> Resolver);
	/** The mod material for this Unity shader on this part: the resolver's answer, else the shader's family. */
	KKUNITYBUNDLE_API TSharedPtr<FKKModMaterial> Resolve(const FString& ShaderName, const FString& Part);

	/**
	 * The instance a part draws with: the material's own parameter values, then (bCopySourceValues) the card's values
	 * for parameters of the same name (colours sRGB to linear), then the part's texture in MainTexture.
	 */
	KKUNITYBUNDLE_API UMaterialInstanceDynamic* MakeInstance(const FKKModMaterial& Material, UObject* Outer, UTexture* PartTexture,
		TFunctionRef<bool(const FString& Property, FLinearColor& Out)> SourceValue);
}
