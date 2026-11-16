#include "OKStudioFbx.h"
#include "OKSceneDocument.h"
#include "ProceduralMeshComponent.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Engine/Texture2D.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Misc/Base64.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/ScopeLock.h"
#include "UObject/StrongObjectPtr.h"
#if WITH_EDITOR
#include "Materials/Material.h"
#include "Materials/MaterialExpressionMultiply.h"
#include "Materials/MaterialExpressionScalarParameter.h"
#include "Materials/MaterialExpressionTextureSampleParameter2D.h"
#include "Materials/MaterialExpressionVectorParameter.h"
#endif

// ufbx (single-file FBX / OBJ reader, MIT), the copy the engine's Interchange FBX parser compiles the same way.
// C4756 (overflow in constant arithmetic): newer Windows SDKs define INFINITY as 1e+300 cast to float; the game target's
// shared precompiled header has math.h in before _UCRT_LEGACY_INFINITY (Build.cs) can take effect.
THIRD_PARTY_INCLUDES_START
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4756)
#endif
#include "ufbx.c"
#ifdef _MSC_VER
#pragma warning(pop)
#endif
THIRD_PARTY_INCLUDES_END

namespace
{
	FString Utf8(const ufbx_string& S) { return S.length ? FString(FUTF8ToTCHAR(S.data, int32(S.length))) : FString(); }

	/** The bytes of a material map's image: embedded in the file, else the file it names (as written, beside the model,
	 *  or by its bare name beside the model, which is where a moved model usually has its textures). */
	bool TextureBytes(const ufbx_texture* T, const FString& ModelDir, TArray<uint8>& Out, FString& OutName)
	{
		if (!T) return false;
		// A layered or procedural texture: its first file texture.
		if (T->type != UFBX_TEXTURE_FILE && T->file_textures.count > 0) T = T->file_textures.data[0];
		if (T->content.size > 0)
		{
			Out.Append(static_cast<const uint8*>(T->content.data), int32(T->content.size));
			OutName = FPaths::GetCleanFilename(Utf8(T->filename));
			return true;
		}
		TArray<FString> Candidates;
		for (const ufbx_string* S : { &T->absolute_filename, &T->filename, &T->relative_filename })
		{
			const FString P = Utf8(*S).Replace(TEXT("\\"), TEXT("/"));
			if (P.IsEmpty()) continue;
			Candidates.Add(FPaths::IsRelative(P) ? ModelDir / P : P);
			Candidates.Add(ModelDir / FPaths::GetCleanFilename(P));
			Candidates.Add(ModelDir / TEXT("textures") / FPaths::GetCleanFilename(P));
		}
		for (const FString& C : Candidates)
			if (FPaths::FileExists(C) && FFileHelper::LoadFileToArray(Out, *C)) { OutName = FPaths::GetCleanFilename(C); return true; }
		return false;
	}

	FLinearColor MapColor(const ufbx_material_map& M, const FLinearColor& Default)
	{
		if (!M.has_value) return Default;
		return FLinearColor(float(M.value_vec4.x), float(M.value_vec4.y), float(M.value_vec4.z), M.value_components >= 4 ? float(M.value_vec4.w) : 1.f);
	}

	TSharedPtr<const FOKFbxModel> Read(const FString& Path, FString& OutError)
	{
		ufbx_load_opts Opts = {};
		// As the engine's Interchange FBX parser: Unreal's axes (left-handed, Z up), centimetres, mirrored on Y, winding
		// reversed (ufbx keeps a mirrored mesh's winding; Unreal's front faces are the other way). Without the reversal a
		// cube showed its inside (2026-11-16, Saved/Tests/StudioU277b).
		Opts.target_axes = ufbx_axes_left_handed_z_up;
		Opts.handedness_conversion_axis = UFBX_MIRROR_AXIS_Y;
		Opts.space_conversion = UFBX_SPACE_CONVERSION_ADJUST_TRANSFORMS;
		Opts.target_unit_meters = 0.01;
		Opts.reverse_winding = true;
		// OBJ has no units or axes: taken as metres, Y up (what Blender and Maya export by default); a 60 cm box came in
		// at 0.6 cm before (2026-11-16).
		Opts.obj_unit_meters = 1.0;
		Opts.obj_axes = ufbx_axes_right_handed_y_up;
		Opts.generate_missing_normals = true;
		Opts.load_external_files = false;
		ufbx_error Error = {};
		const FTCHARToUTF8 File(*Path);
		ufbx_scene* Scene = ufbx_load_file_len(File.Get(), size_t(File.Length()), &Opts, &Error);
		if (!Scene)
		{
			OutError = FString::Printf(TEXT("cannot read %s: %s"), *Path, *Utf8(Error.description));
			return nullptr;
		}
		const FString Dir = FPaths::GetPath(Path);
		TSharedPtr<FOKFbxModel> Model = MakeShared<FOKFbxModel>();
		TMap<const ufbx_material*, int32> SectionOf;
		TArray<uint32> Tri;
		for (size_t N = 0; N < Scene->nodes.count; ++N)
		{
			const ufbx_node* Node = Scene->nodes.data[N];
			const ufbx_mesh* Mesh = Node ? Node->mesh : nullptr;
			if (!Mesh || !Node->visible || Mesh->num_faces == 0) continue;
			++Model->Meshes;
			const ufbx_matrix ToWorld = Node->geometry_to_world;
			const ufbx_matrix NormalMatrix = ufbx_matrix_for_normals(&ToWorld);
			Tri.SetNumUninitialized(int32(FMath::Max<size_t>(Mesh->max_face_triangles, 1) * 3));
			// One part per material (a mesh with none is one part); the node's materials override the mesh's.
			const size_t Parts = FMath::Max<size_t>(Mesh->material_parts.count, 1);
			for (size_t P = 0; P < Parts; ++P)
			{
				const ufbx_mesh_part* Part = Mesh->material_parts.count ? &Mesh->material_parts.data[P] : nullptr;
				const uint32 MatIndex = Part ? Part->index : 0;
				const ufbx_material* Mat = MatIndex < Node->materials.count ? Node->materials.data[MatIndex] : MatIndex < Mesh->materials.count ? Mesh->materials.data[MatIndex] : nullptr;
				int32* Found = SectionOf.Find(Mat);
				if (!Found)
				{
					FOKFbxSection& S = Model->Sections.AddDefaulted_GetRef();
					S.Material = Mat ? Utf8(Mat->name) : FString();
					if (S.Material.IsEmpty()) S.Material = FString::Printf(TEXT("材質 %d"), Model->Sections.Num());
					// Unique names: the material editor keys its edits by them.
					for (int32 K = 0; K + 1 < Model->Sections.Num(); ++K)
						if (Model->Sections[K].Material == S.Material) { S.Material += FString::Printf(TEXT(" (%d)"), Model->Sections.Num()); break; }
					if (Mat)
					{
						const bool bPbr = Mat->pbr.base_color.has_value || Mat->pbr.base_color.texture;
						const FLinearColor Base = bPbr ? MapColor(Mat->pbr.base_color, FLinearColor::White) : MapColor(Mat->fbx.diffuse_color, FLinearColor::White);
						const float Factor = Mat->pbr.base_factor.has_value ? float(Mat->pbr.base_factor.value_real) : 1.f;
						S.BaseColor = FLinearColor(Base.R * Factor, Base.G * Factor, Base.B * Factor, Base.A);
						if (Mat->pbr.metalness.has_value) S.Metallic = FMath::Clamp(float(Mat->pbr.metalness.value_real), 0.f, 1.f);
						if (Mat->pbr.roughness.has_value) S.Roughness = FMath::Clamp(float(Mat->pbr.roughness.value_real), 0.f, 1.f);
						const FLinearColor Emit = MapColor(Mat->pbr.emission_color, FLinearColor::Black);
						const float EmitFactor = Mat->pbr.emission_factor.has_value ? float(Mat->pbr.emission_factor.value_real) : 1.f;
						S.Emission = FLinearColor(Emit.R * EmitFactor, Emit.G * EmitFactor, Emit.B * EmitFactor, 1.f);
						const ufbx_texture* Tex = Mat->pbr.base_color.texture ? Mat->pbr.base_color.texture : Mat->fbx.diffuse_color.texture;
						// A texture multiplies a white base: FBX exporters often leave the diffuse colour grey or black beside it.
						if (TextureBytes(Tex, Dir, S.BaseTexture, S.BaseTextureName) && S.BaseColor.GetLuminance() < 0.05f) S.BaseColor = FLinearColor::White;
					}
					Found = &SectionOf.Add(Mat, Model->Sections.Num() - 1);
				}
				FOKFbxSection& S = Model->Sections[*Found];
				const size_t Faces = Part ? Part->face_indices.count : Mesh->faces.count;
				for (size_t F = 0; F < Faces; ++F)
				{
					const ufbx_face Face = Mesh->faces.data[Part ? Part->face_indices.data[F] : F];
					const uint32 Count = ufbx_triangulate_face(Tri.GetData(), size_t(Tri.Num()), Mesh, Face);
					for (uint32 I = 0; I < Count * 3; ++I)
					{
						const uint32 Index = Tri[int32(I)];
						const ufbx_vec3 Pos = ufbx_transform_position(&ToWorld, ufbx_get_vertex_vec3(&Mesh->vertex_position, Index));
						S.Positions.Add(FVector(Pos.x, Pos.y, Pos.z));
						Model->Bounds += S.Positions.Last();
						if (Mesh->vertex_normal.exists)
						{
							const ufbx_vec3 Nrm = ufbx_transform_direction(&NormalMatrix, ufbx_get_vertex_vec3(&Mesh->vertex_normal, Index));
							S.Normals.Add(FVector(Nrm.x, Nrm.y, Nrm.z).GetSafeNormal());
						}
						else S.Normals.Add(FVector::UpVector);
						if (Mesh->vertex_uv.exists)
						{
							const ufbx_vec2 Uv = ufbx_get_vertex_vec2(&Mesh->vertex_uv, Index);
							// FBX UVs start at the bottom; Unreal's at the top.
							S.Uvs.Add(FVector2D(Uv.x, 1.0 - Uv.y));
						}
						else S.Uvs.Add(FVector2D::ZeroVector);
						if (Mesh->vertex_color.exists)
						{
							const ufbx_vec4 C = ufbx_get_vertex_vec4(&Mesh->vertex_color, Index);
							S.Colors.Add(FLinearColor(float(C.x), float(C.y), float(C.z), float(C.w)).ToFColor(false));
						}
						else S.Colors.Add(FColor::White);
						S.Triangles.Add(S.Positions.Num() - 1);
					}
				}
			}
		}
		ufbx_free_scene(Scene);
		Model->Sections.RemoveAll([](const FOKFbxSection& S) { return S.Triangles.IsEmpty(); });
		if (Model->Sections.IsEmpty()) { OutError = TEXT("no mesh in ") + Path; return nullptr; }
		return Model;
	}
}

bool OKStudioFbx::IsModelFile(const FString& Path)
{
	const FString Ext = FPaths::GetExtension(Path).ToLower();
	return Ext == TEXT("fbx") || Ext == TEXT("obj");
}

TSharedPtr<const FOKFbxModel> OKStudioFbx::Load(const FString& Path, FString& OutError)
{
	struct FEntry { FDateTime Time; TSharedPtr<const FOKFbxModel> Model; };
	static FCriticalSection Lock;
	static TMap<FString, FEntry> Cache;
	const FString Full = FPaths::ConvertRelativePathToFull(Path);
	if (!FPaths::FileExists(Full)) { OutError = TEXT("model file missing: ") + Full; return nullptr; }
	const FDateTime Time = IFileManager::Get().GetTimeStamp(*Full);
	{
		FScopeLock Guard(&Lock);
		if (const FEntry* E = Cache.Find(Full); E && E->Time == Time) return E->Model;
	}
	TSharedPtr<const FOKFbxModel> Model = Read(Full, OutError);
	if (Model)
	{
		FScopeLock Guard(&Lock);
		Cache.Add(Full, { Time, Model });
		UE_LOG(LogTemp, Display, TEXT("OK studio: model %s: %d meshes, %d materials, bounds %s"), *Full, Model->Meshes, Model->Sections.Num(), *Model->Bounds.ToString());
	}
	return Model;
}

namespace
{
	/** The lit material models draw with: BaseMap (sRGB) x Color as base colour, Metallic, Roughness, Emissive. Built in
	 *  code once (the studio runs on the editor binary); a build without the editor falls back to the engine's basic
	 *  shape material (its Color parameter only). */
	UMaterialInterface* ModelMaterial(bool bTwoSided)
	{
		static TStrongObjectPtr<UMaterialInterface> Cached[2];
		TStrongObjectPtr<UMaterialInterface>& Slot = Cached[bTwoSided ? 1 : 0];
		if (Slot) return Slot.Get();
#if WITH_EDITOR
		UMaterial* Mat = NewObject<UMaterial>(GetTransientPackage(), NAME_None, RF_Transient);
		UMaterialEditorOnlyData* Ed = Mat ? Mat->GetEditorOnlyData() : nullptr;
		if (Ed)
		{
			Mat->TwoSided = bTwoSided;
			auto Register = [Mat](UMaterialExpression* E) { E->Material = Mat; Mat->GetExpressionCollection().AddExpression(E); };
			auto* Tex = NewObject<UMaterialExpressionTextureSampleParameter2D>(Mat); Tex->ParameterName = TEXT("BaseMap"); Tex->SamplerType = SAMPLERTYPE_Color;
			Tex->Texture = LoadObject<UTexture2D>(nullptr, TEXT("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")); Register(Tex);
			auto* Color = NewObject<UMaterialExpressionVectorParameter>(Mat); Color->ParameterName = TEXT("Color"); Color->DefaultValue = FLinearColor::White; Register(Color);
			auto* Mul = NewObject<UMaterialExpressionMultiply>(Mat); Mul->A.Expression = Tex; Mul->A.OutputIndex = 0; Mul->B.Expression = Color; Mul->B.OutputIndex = 0; Register(Mul);
			auto* Metal = NewObject<UMaterialExpressionScalarParameter>(Mat); Metal->ParameterName = TEXT("Metallic"); Metal->DefaultValue = 0.f; Register(Metal);
			auto* Rough = NewObject<UMaterialExpressionScalarParameter>(Mat); Rough->ParameterName = TEXT("Roughness"); Rough->DefaultValue = 0.6f; Register(Rough);
			auto* Emit = NewObject<UMaterialExpressionVectorParameter>(Mat); Emit->ParameterName = TEXT("Emissive"); Emit->DefaultValue = FLinearColor::Black; Register(Emit);
			Ed->BaseColor.Expression = Mul;
			Ed->Metallic.Expression = Metal;
			Ed->Roughness.Expression = Rough;
			Ed->EmissiveColor.Expression = Emit;
			Mat->PreEditChange(nullptr);
			Mat->PostEditChange();
			Slot.Reset(Mat);
			return Mat;
		}
#endif
		Slot.Reset(LoadObject<UMaterialInterface>(nullptr, TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial")));
		return Slot.Get();
	}

	UTexture2D* ImageTexture(const TArray<uint8>& Bytes)
	{
		if (Bytes.IsEmpty()) return nullptr;
		UTexture2D* T = FImageUtils::ImportBufferAsTexture2D(Bytes);
		if (T) T->SRGB = true;
		return T;
	}

	struct FResolved
	{
		FLinearColor Color = FLinearColor::White, Emission = FLinearColor::Black;
		float Metallic = 0.f, Roughness = 0.6f;
		bool bTwoSided = false, bShown = true;
		/** Texture: 0 the file's, 1 an edit's (Bytes), 2 cleared. */
		int32 TextureFrom = 0;
		TArray<uint8> Bytes;
	};

	FResolved Resolve(const FOKFbxSection& S, const TArray<FOKSceneMaterialEdit>& Edits)
	{
		FResolved R;
		R.Color = S.BaseColor; R.Emission = S.Emission; R.Metallic = S.Metallic; R.Roughness = S.Roughness;
		for (const FOKSceneMaterialEdit& E : Edits)
		{
			if (!E.Material.IsEmpty() && E.Material != S.Material) continue;
			const FString P = E.Property.StartsWith(TEXT("_")) ? E.Property : TEXT("_") + E.Property;
			if (E.Kind == EOKSceneMaterialEditKind::Renderer) { if (P == TEXT("_Enabled")) R.bShown = E.Value.R > 0.5f; continue; }
			if (P == TEXT("_Color")) R.Color = E.Value;
			else if (P == TEXT("_Metallic")) R.Metallic = E.Value.R;
			else if (P == TEXT("_Glossiness")) R.Roughness = 1.f - E.Value.R;
			else if (P == TEXT("_EmissionColor")) R.Emission = E.Value;
			else if (P == TEXT("_TwoSided")) R.bTwoSided = E.Value.R > 0.5f;
			else if (P == TEXT("_MainTex") && E.Kind == EOKSceneMaterialEditKind::Texture)
			{
				if (E.Value.A < 0.f) R.TextureFrom = 2;
				else { R.Bytes.Reset(); if (FBase64::Decode(E.Text, R.Bytes)) R.TextureFrom = 1; }
			}
		}
		return R;
	}
}

bool OKStudioFbx::SourceValue(const FOKFbxSection& Section, const FString& Property, FLinearColor& Out)
{
	if (Property == TEXT("_Color")) Out = Section.BaseColor;
	else if (Property == TEXT("_EmissionColor")) Out = Section.Emission;
	else if (Property == TEXT("_Metallic")) Out = FLinearColor(Section.Metallic, 0.f, 0.f, 0.f);
	else if (Property == TEXT("_Glossiness")) Out = FLinearColor(1.f - Section.Roughness, 0.f, 0.f, 0.f);
	else if (Property == TEXT("_TwoSided")) Out = FLinearColor(0.f, 0.f, 0.f, 0.f);
	else return false;
	return true;
}

UProceduralMeshComponent* OKStudioFbx::Spawn(AActor* Owner, USceneComponent* Parent, const FString& Path, FString& OutError)
{
	const TSharedPtr<const FOKFbxModel> Model = Load(Path, OutError);
	if (!Model || !Owner) return nullptr;
	UProceduralMeshComponent* Mesh = NewObject<UProceduralMeshComponent>(Owner);
	Mesh->bUseAsyncCooking = true;
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	for (int32 I = 0; I < Model->Sections.Num(); ++I)
	{
		const FOKFbxSection& S = Model->Sections[I];
		Mesh->CreateMeshSection(I, S.Positions, S.Triangles, S.Normals, S.Uvs, S.Colors, TArray<FProcMeshTangent>(), false);
	}
	if (Parent) Mesh->SetupAttachment(Parent);
	Mesh->RegisterComponent();
	ApplyEdits(Mesh, Path, {});
	return Mesh;
}

void OKStudioFbx::ApplyEdits(UProceduralMeshComponent* Mesh, const FString& Path, const TArray<FOKSceneMaterialEdit>& Edits)
{
	FString Error;
	const TSharedPtr<const FOKFbxModel> Model = Mesh ? Load(Path, Error) : nullptr;
	if (!Model) return;
	for (int32 I = 0; I < Model->Sections.Num() && I < Mesh->GetNumSections(); ++I)
	{
		const FOKFbxSection& S = Model->Sections[I];
		const FResolved R = Resolve(S, Edits);
		UMaterialInstanceDynamic* Mid = UMaterialInstanceDynamic::Create(ModelMaterial(R.bTwoSided), Mesh);
		if (!Mid) continue;
		Mid->SetVectorParameterValue(TEXT("Color"), R.Color);
		Mid->SetScalarParameterValue(TEXT("Metallic"), FMath::Clamp(R.Metallic, 0.f, 1.f));
		Mid->SetScalarParameterValue(TEXT("Roughness"), FMath::Clamp(R.Roughness, 0.f, 1.f));
		Mid->SetVectorParameterValue(TEXT("Emissive"), R.Emission);
		if (UTexture2D* Tex = R.TextureFrom == 1 ? ImageTexture(R.Bytes) : R.TextureFrom == 0 ? ImageTexture(S.BaseTexture) : nullptr)
			Mid->SetTextureParameterValue(TEXT("BaseMap"), Tex);
		Mesh->SetMaterial(I, Mid);
		Mesh->SetMeshSectionVisible(I, R.bShown);
	}
}
