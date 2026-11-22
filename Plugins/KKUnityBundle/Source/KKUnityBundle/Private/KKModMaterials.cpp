#include "KKModMaterials.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"

namespace
{
TMap<FString, TSharedPtr<FKKModMaterial>>& Families()
{
	static TMap<FString, TSharedPtr<FKKModMaterial>> Table;
	return Table;
}
float Linear(float C) { return C <= .04045f ? C / 12.92f : FMath::Pow((C + .055f) / 1.055f, 2.4f); }
}

void KKModMaterials::SetFamilies(TMap<FString, TSharedPtr<FKKModMaterial>> ByShader)
{
	check(IsInGameThread());
	Families() = MoveTemp(ByShader);
}

TSharedPtr<FKKModMaterial> KKModMaterials::FindFamily(const FString& ShaderName)
{
	if (Families().IsEmpty() || ShaderName.IsEmpty()) return nullptr;
	const TSharedPtr<FKKModMaterial>* Found = Families().Find(ShaderName.ToLower());
	return Found ? *Found : nullptr;
}

int32 KKModMaterials::FamilyCount() { return Families().Num(); }

UMaterialInstanceDynamic* KKModMaterials::MakeInstance(const FKKModMaterial& M, UObject* Outer, UTexture* PartTexture,
	TFunctionRef<bool(const FString& Property, FLinearColor& Out)> SourceValue)
{
	if (!M.Material.IsValid()) return nullptr;
	UMaterialInstanceDynamic* Dynamic = UMaterialInstanceDynamic::Create(M.Material.Get(), Outer);
	if (!Dynamic) return nullptr;
	for (const TPair<FName, float>& P : M.Scalars) Dynamic->SetScalarParameterValue(P.Key, P.Value);
	for (const TPair<FName, FLinearColor>& P : M.Vectors) Dynamic->SetVectorParameterValue(P.Key, P.Value);
	for (const TPair<FName, TStrongObjectPtr<UTexture>>& P : M.Textures) if (P.Value.IsValid()) Dynamic->SetTextureParameterValue(P.Key, P.Value.Get());
	if (M.bCopySourceValues)
	{
		TArray<FMaterialParameterInfo> Infos;
		TArray<FGuid> Ids;
		M.Material->GetAllScalarParameterInfo(Infos, Ids);
		for (const FMaterialParameterInfo& Info : Infos)
		{
			FLinearColor V;
			if (SourceValue(Info.Name.ToString(), V)) Dynamic->SetScalarParameterValue(Info.Name, V.R);
		}
		Infos.Reset();
		Ids.Reset();
		M.Material->GetAllVectorParameterInfo(Infos, Ids);
		for (const FMaterialParameterInfo& Info : Infos)
		{
			FLinearColor V;
			if (SourceValue(Info.Name.ToString(), V)) Dynamic->SetVectorParameterValue(Info.Name, FLinearColor(Linear(V.R), Linear(V.G), Linear(V.B), V.A));
		}
	}
	if (PartTexture && !M.MainTexture.IsNone()) Dynamic->SetTextureParameterValue(M.MainTexture, PartTexture);
	return Dynamic;
}
