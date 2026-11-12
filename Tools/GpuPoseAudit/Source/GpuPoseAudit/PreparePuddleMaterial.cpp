#if OK_RUNTIME_SHARED_MATERIAL_TOOL
// The puddles on the floor of the one-on-one (user 2026-11-12: water on the ground with screen space reflections). An
// opaque, masked, nearly smooth Default Lit surface, so the engine's screen space reflections (r.ReflectionMethod 2, the
// project's default) show the two of them in it at full quality.
//
// What shows where nothing on screen is reflected (user 2026-11-12, "why so black"): the floor under it, darker. The game
// photographs the floor from above (UOKHScenePanel::TickPuddles, scene colour, the floor only) into PuddleFloor, and the
// surface glows with it (Emissive = that colour x PuddleDarken, found by world position through PuddleFloorRect: centre x,
// centre y, 1 / width of the photo), so it reads as wet floor; the reflection is added on top (Metallic PuddleMetallic,
// its reflectance PuddleColor, so no diffuse light of its own). The two earlier tries: a surface of its own with nothing
// behind the reflection (black wherever it missed), a deferred decal (the street floor takes none).
//
// The outline is the PuddleMask texture's red channel (made at runtime; clipped at a half).
//
//   UnrealEditor-Cmd RuntimeMaterialBake.uproject -run=GpuPoseAudit -PreparePuddleMaterial -AssetRoot=<Content>
//     -MaterialPath=/Game/IndependentResources/RuntimeMaterials/<root>/M_OKPuddleMirror -Output=<report.json>
#include "Materials/Material.h"
#include "Materials/MaterialExpressionCustom.h"
#include "Materials/MaterialExpressionTextureObjectParameter.h"
#include "Materials/MaterialExpressionScalarParameter.h"
#include "Materials/MaterialExpressionVectorParameter.h"
#include "Materials/MaterialExpressionTextureCoordinate.h"
#include "Materials/MaterialExpressionWorldPosition.h"
#include "Engine/Texture2D.h"
#include "UObject/SavePackage.h"
#include "UObject/StrongObjectPtr.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Json.h"
#include "MaterialShared.h"

bool PreparePuddleMaterial(const FString& AssetRoot,const FString& MaterialPath,const FString& Output){
 if(!MaterialPath.StartsWith(TEXT("/Game/IndependentResources/RuntimeMaterials/"))||!FPackageName::IsValidLongPackageName(MaterialPath))return false;
 FPackageName::RegisterMountPoint(TEXT("/Game/"),FPaths::ConvertRelativePathToFull(AssetRoot)/TEXT(""));
 const FString File=FPackageName::LongPackageNameToFilename(MaterialPath,FPackageName::GetAssetPackageExtension());
 if(IFileManager::Get().FileExists(*File)){UE_LOG(LogTemp,Error,TEXT("Puddle material already exists: %s"),*File);return false;}
 const FString Name=FPackageName::GetShortName(MaterialPath);
 auto* Mat=NewObject<UMaterial>(CreatePackage(*MaterialPath),*Name,RF_Public|RF_Standalone);TStrongObjectPtr<UMaterial> Keep(Mat);
 Mat->MaterialDomain=MD_Surface;Mat->BlendMode=BLEND_Masked;Mat->SetShadingModel(MSM_DefaultLit);Mat->TwoSided=false;Mat->OpacityMaskClipValue=.5f;
 Mat->SetUsageByFlag(MATUSAGE_StaticMesh,true);
 auto Register=[&](UMaterialExpression* E){E->Material=Mat;Mat->GetExpressionCollection().AddExpression(E);return E;};
 auto Scalar=[&](const TCHAR* N,float V){auto* E=NewObject<UMaterialExpressionScalarParameter>(Mat);E->ParameterName=N;E->DefaultValue=V;Register(E);return E;};
 auto Vector=[&](const TCHAR* N,const FLinearColor& V){auto* E=NewObject<UMaterialExpressionVectorParameter>(Mat);E->ParameterName=N;E->DefaultValue=V;Register(E);return E;};
 auto TextureParameter=[&](const TCHAR* N,const TCHAR* Default){auto* E=NewObject<UMaterialExpressionTextureObjectParameter>(Mat);E->ParameterName=N;
  E->Texture=LoadObject<UTexture2D>(nullptr,Default);E->SamplerType=SAMPLERTYPE_LinearColor;Register(E);return E;};
 auto Custom=[&](const TCHAR* What,ECustomMaterialOutputType Type,const TCHAR* Code,std::initializer_list<TPair<const TCHAR*,UMaterialExpression*>> Inputs){
  auto* E=NewObject<UMaterialExpressionCustom>(Mat);E->OutputType=Type;E->Description=What;E->Inputs.Reset();
  for(const auto& In:Inputs){auto& I=E->Inputs.AddDefaulted_GetRef();I.InputName=In.Key;I.Input.Expression=In.Value;}
  E->Code=Code;Register(E);return E;};
 // The puddle's outline, its red channel (white where the water is, smooth toward its edge).
 auto* UV=NewObject<UMaterialExpressionTextureCoordinate>(Mat);Register(UV);
 auto* Mask=Custom(TEXT("OK puddle mask"),CMOT_Float1,TEXT("return Texture2DSample(Tex,TexSampler,UV).r;"),
  {{TEXT("UV"),UV},{TEXT("Tex"),TextureParameter(TEXT("PuddleMask"),TEXT("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture"))}});
 // The floor under it (the photo from above), darker: what shows where nothing is reflected.
 auto* World=NewObject<UMaterialExpressionWorldPosition>(Mat);Register(World);
 auto* Floor=Custom(TEXT("OK puddle floor"),CMOT_Float3,
  TEXT("float2 At=float2((WorldPos.y-Rect.y)*Rect.z+.5,(Rect.x-WorldPos.x)*Rect.z+.5);\nreturn Texture2DSample(Tex,TexSampler,saturate(At)).rgb*Darken;"),
  {{TEXT("WorldPos"),World},{TEXT("Rect"),Vector(TEXT("PuddleFloorRect"),FLinearColor(0.f,0.f,.001f,0.f))},
   {TEXT("Tex"),TextureParameter(TEXT("PuddleFloor"),TEXT("/Engine/EngineResources/Black.Black"))},{TEXT("Darken"),Scalar(TEXT("PuddleDarken"),.6f)}});
 auto* Ed=Mat->GetEditorOnlyData();
 Ed->BaseColor.Expression=Vector(TEXT("PuddleColor"),FLinearColor(.9f,.9f,.92f,1.f));Ed->EmissiveColor.Expression=Floor;Ed->OpacityMask.Expression=Mask;
 Ed->Specular.Expression=Scalar(TEXT("PuddleSpecular"),.5f);Ed->Roughness.Expression=Scalar(TEXT("PuddleRoughness"),.02f);Ed->Metallic.Expression=Scalar(TEXT("PuddleMetallic"),1.f);
 Mat->UpdateCachedExpressionData();Mat->PostEditChange();Mat->CacheShaders(EMaterialShaderPrecompileMode::Synchronous);
 // A graph error would only show at cook time (the game then draws the default material): stop here instead.
 if(auto* Pending=Mat->GetMaterialResource(GMaxRHIShaderPlatform))Pending->FinishCompilation();
 const FMaterialResource* Resource=Mat->GetMaterialResource(GMaxRHIShaderPlatform);
 if(!Resource||!Resource->GetCompileErrors().IsEmpty()||!Resource->GetGameThreadShaderMap()){if(Resource)for(const FString& E:Resource->GetCompileErrors())UE_LOG(LogTemp,Error,TEXT("%s: %s"),*Name,*E);UE_LOG(LogTemp,Error,TEXT("%s did not compile"),*Name);return false;}
 IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);
 FSavePackageArgs Args;Args.TopLevelFlags=RF_Public|RF_Standalone;if(!UPackage::SavePackage(Mat->GetOutermost(),Mat,*File,Args))return false;
 auto Report=MakeShared<FJsonObject>();Report->SetBoolField(TEXT("passed"),true);Report->SetStringField(TEXT("material"),MaterialPath);Report->SetStringField(TEXT("file"),File);
 FString Text;FJsonSerializer::Serialize(Report,TJsonWriterFactory<>::Create(&Text));return FFileHelper::SaveStringToFile(Text,*Output);
}
#endif
