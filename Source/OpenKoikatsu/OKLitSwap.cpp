#include "OKLitSwap.h"
#include "GameFramework/Actor.h"
#include "Components/MeshComponent.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "HAL/IConsoleManager.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "KKAffineProceduralMeshComponent.h"
#include "KKLitSync.h"

namespace {
struct FOKLitSet {
	TMap<TWeakObjectPtr<UMaterialInstanceDynamic>,TWeakObjectPtr<UMaterialInstanceDynamic>> LitOf,OriginalOf;
	TMap<TWeakObjectPtr<UMaterialInstanceDynamic>,FKKLitSnapshot> Snapshots;
};
TMap<TWeakObjectPtr<AActor>,FOKLitSet> GLit;
TSet<FString> GMissing;
TMap<FString,TWeakObjectPtr<UMaterialInterface>> GParents;
}

const FString& OKLitMaterialRootPath(){
	static const FString Root=[]{FString Manifest,Json,Found;TSharedPtr<FJsonObject> Object;
		if(FParse::Value(FCommandLine::Get(),TEXT("StreetSocialManifest="),Manifest)&&FFileHelper::LoadFileToString(Json,*Manifest)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Object)&&Object)Object->TryGetStringField(TEXT("lit_material_root"),Found);
		return Found.IsEmpty()?FString(TEXT("/Game/IndependentResources/RuntimeMaterials/StreetLit03")):Found;}();
	return Root;
}

int32 OKSetActorLit(AActor* Owner,bool bOn,const FString& LitRoot){
	if(!IsValid(Owner))return 0;
	TInlineComponentArray<UMeshComponent*> Meshes(Owner);
	if(!bOn){
		if(FOKLitSet* Set=GLit.Find(Owner)){
			for(UMeshComponent* Mesh:Meshes)for(int32 Slot=0;Slot<Mesh->GetNumMaterials();++Slot)
				if(auto* M=Cast<UMaterialInstanceDynamic>(Mesh->GetMaterial(Slot)))if(const auto* Original=Set->OriginalOf.Find(M))if(Original->IsValid())Mesh->SetMaterial(Slot,Original->Get());
			GLit.Remove(Owner);}
		return 0;
	}
	FOKLitSet& Set=GLit.FindOrAdd(Owner);
	TSet<UMaterialInstanceDynamic*> Shown;
	static IConsoleVariable* Affine=IConsoleManager::Get().FindConsoleVariable(TEXT("ok.Lit.Affine"));const bool bAffine=!Affine||Affine->GetInt()!=0;
	for(UMeshComponent* Mesh:Meshes){
		if(!Mesh->bRenderInMainPass||(!bAffine&&Mesh->IsA<UKKAffineProceduralMeshComponent>()))continue;
		for(int32 Slot=0;Slot<Mesh->GetNumMaterials();++Slot){
			auto* M=Cast<UMaterialInstanceDynamic>(Mesh->GetMaterial(Slot));if(!M)continue;
			UMaterialInstanceDynamic* Lit=Set.OriginalOf.Contains(M)?M:nullptr;
			if(!Lit)if(const auto* Found=Set.LitOf.Find(M))Lit=Found->Get();
			if(!Lit){
				UMaterialInterface* Parent=M->Parent;if(!Parent||Parent->GetPathName().Contains(TEXT("/StreetHG"))||Parent->GetName().EndsWith(TEXT("_Wrap")))continue;
				FString Base=Parent->GetName();Base.RemoveFromEnd(TEXT("_Flat"));
				const FString Path=LitRoot/(Base+TEXT("_Lit"));if(GMissing.Contains(Path))continue;
				UMaterialInterface* LitParent=nullptr;
				if(const auto* Known=GParents.Find(Path))LitParent=Known->Get();
				if(!LitParent){LitParent=FPackageName::DoesPackageExist(Path)?LoadObject<UMaterialInterface>(nullptr,*(Path+TEXT(".")+Base+TEXT("_Lit"))):nullptr;
					if(!LitParent){GMissing.Add(Path);continue;}GParents.Add(Path,LitParent);}
				Lit=UMaterialInstanceDynamic::Create(LitParent,Owner);
				Set.LitOf.Add(M,Lit);Set.OriginalOf.Add(Lit,M);
			}
			if(Mesh->GetMaterial(Slot)!=Lit)Mesh->SetMaterial(Slot,Lit);
			Shown.Add(Lit);
		}
	}
	for(UMaterialInstanceDynamic* Lit:Shown)if(const auto* Original=Set.OriginalOf.Find(Lit))if(Original->IsValid())KKSyncLitInstance(Lit,Original->Get(),Set.Snapshots.FindOrAdd(Lit));
	return Shown.Num();
}
