#pragma once

// U277: outside models (FBX) in a scene. The file is read with ufbx (the engine's copy, MIT) into static mesh sections,
// one per material, in Unreal space (cm, Z up, left-handed); OKSceneActor shows them on a procedural mesh.
#include "CoreMinimal.h"

struct FOKFbxSection
{
	/** The material's name (unique in the model; "材質 N" when the file has none). */
	FString Material;
	TArray<FVector> Positions;
	TArray<FVector> Normals;
	TArray<FVector2D> Uvs;
	TArray<FColor> Colors;
	TArray<int32> Triangles;
	/** The file's material: base colour, metallic, roughness, emission and the base colour texture (bytes of an image
	 *  file, embedded or read from beside the model; empty: none). */
	FLinearColor BaseColor = FLinearColor::White;
	float Metallic = 0.f;
	float Roughness = 0.6f;
	FLinearColor Emission = FLinearColor::Black;
	TArray<uint8> BaseTexture;
	FString BaseTextureName;
};

struct FOKFbxModel
{
	TArray<FOKFbxSection> Sections;
	FBox Bounds = FBox(ForceInit);
	int32 Meshes = 0;
};

class AActor;
class USceneComponent;
class UProceduralMeshComponent;
struct FOKSceneMaterialEdit;

namespace OKStudioFbx
{
	/** Whether a path is a model file the studio reads (.fbx; .obj too, which ufbx reads as well). */
	bool IsModelFile(const FString& Path);
	/** Reads a model; false with the reason in OutError. Cached by path and file time. */
	TSharedPtr<const FOKFbxModel> Load(const FString& Path, FString& OutError);
	/** A procedural mesh of the model under Parent (one section per material), registered; null with OutError. */
	UProceduralMeshComponent* Spawn(AActor* Owner, USceneComponent* Parent, const FString& Path, FString& OutError);
	/** Puts the model's materials on the mesh with the edits over them (by material name, empty = every material):
	 *  _Color, _Metallic, _Glossiness, _EmissionColor (colour / float), _MainTex (texture: base64 PNG, alpha < 0 clears),
	 *  _TwoSided (float), and the Renderer edit Enabled shows or hides a material's section. */
	void ApplyEdits(UProceduralMeshComponent* Mesh, const FString& Path, const TArray<FOKSceneMaterialEdit>& Edits);
	/** The value a material property has before edits (for the material editor): colour in Out, float in Out.R. */
	bool SourceValue(const FOKFbxSection& Section, const FString& Property, FLinearColor& Out);
}
