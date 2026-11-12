#if OK_RUNTIME_SHARED_MATERIAL_TOOL
// The puddles on the floor of the one-on-one (user 2026-11-12: water on the ground with screen space reflections): a Default
// Lit, masked, nearly smooth surface, so the engine's screen space reflections (r.ReflectionMethod 2, the project's default)
// show the two of them in it. Its outline is the PuddleMask texture's red channel (made at runtime, UOKHScenePanel::
// TickPuddles; clipped at a half), PuddleColor / PuddleRoughness / PuddleSpecular tune the water.
//
//   UnrealEditor-Cmd RuntimeMaterialBake.uproject -run=GpuPoseAudit -PreparePuddleMaterial -AssetRoot=<Content>
//     -MaterialPath=/Game/IndependentResources/RuntimeMaterials/<root>/M_OKPuddleLit -Output=<report.json>
#include "Materials/Material.h"
#include "Materials/MaterialExpressionCustom.h"
#include "Materials/MaterialExpressionTextureObjectParameter.h"
#include "Materials/MaterialExpressionScalarParameter.h"
#include "Materials/MaterialExpressionVectorParameter.h"
#include "Materials/MaterialExpressionTextureCoordinate.h"
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
 // The puddle's outline, its red channel (white where the water is, smooth toward its edge).
 auto* Tex=NewObject<UMaterialExpressionTextureObjectParameter>(Mat);Tex->ParameterName=TEXT("PuddleMask");
 Tex->Texture=LoadObject<UTexture2D>(nullptr,TEXT("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture"));Tex->SamplerType=SAMPLERTYPE_LinearColor;Register(Tex);
 auto* UV=NewObject<UMaterialExpressionTextureCoordinate>(Mat);Register(UV);
 auto* Mask=NewObject<UMaterialExpressionCustom>(Mat);Mask->OutputType=CMOT_Float1;Mask->Description=TEXT("OK puddle mask");Mask->Inputs.Reset();
 {auto& I=Mask->Inputs.AddDefaulted_GetRef();I.InputName=TEXT("UV");I.Input.Expression=UV;}
 {auto& I=Mask->Inputs.AddDefaulted_GetRef();I.InputName=TEXT("Tex");I.Input.Expression=Tex;}
 Mask->Code=TEXT("return Texture2DSample(Tex,TexSampler,UV).r;");Register(Mask);
 auto* Color=NewObject<UMaterialExpressionVectorParameter>(Mat);Color->ParameterName=TEXT("PuddleColor");Color->DefaultValue=FLinearColor(.012f,.014f,.018f,1.f);Register(Color);
 auto* Ed=Mat->GetEditorOnlyData();
 Ed->BaseColor.Expression=Color;Ed->OpacityMask.Expression=Mask;
 Ed->Specular.Expression=Scalar(TEXT("PuddleSpecular"),.5f);Ed->Roughness.Expression=Scalar(TEXT("PuddleRoughness"),.03f);Ed->Metallic.Expression=Scalar(TEXT("PuddleMetallic"),0.f);
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
