#include "KKPreviewDebug.h"
#include "KKPreviewActor.h"
#include "Components/PrimitiveComponent.h"
#include "ProceduralMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "Materials/Material.h"
#include "HAL/IConsoleManager.h"
#include "UObject/UObjectIterator.h"
#include "Misc/OutputDevice.h"

namespace
{
const TCHAR* PartTagPrefix = TEXT("OKPart=");
// Set on what these controls hid, so showing again never shows what the actor itself hid.
const FName DebugHiddenTag(TEXT("OKDebugHidden"));

void ApplyAll(IConsoleVariable*);

TAutoConsoleVariable<FString> CVarHideParts(TEXT("ok.Debug.HideParts"), TEXT(""),
	TEXT("Comma-separated source renderer names whose drawn parts are hidden (exact match; empty shows them all)."),
	FConsoleVariableDelegate::CreateStatic(&ApplyAll), ECVF_Default);
TAutoConsoleVariable<int32> CVarOutline(TEXT("ok.Debug.Outline"), 1,
	TEXT("0 hides every character outline shell (component shells and procedural outline sections); 1 shows them."),
	FConsoleVariableDelegate::CreateStatic(&ApplyAll), ECVF_Default);

FString PartName(const UPrimitiveComponent* Component)
{
	for (const FName& Tag : Component->ComponentTags)
	{
		const FString Text = Tag.ToString();
		if (Text.StartsWith(PartTagPrefix)) return Text.Mid(FCString::Strlen(PartTagPrefix));
	}
	return FString();
}

TSet<FString> HiddenNames()
{
	TArray<FString> Names;
	CVarHideParts.GetValueOnGameThread().ParseIntoArray(Names, TEXT(","));
	TSet<FString> Out;
	for (FString& Name : Names) Out.Add(Name.TrimStartAndEnd());
	return Out;
}

bool IsOutlineMaterial(const UMaterialInterface* Material)
{
	if (!Material) return false;
	if (Material->GetName().Contains(TEXT("Outline"))) return true;
	const UMaterial* Base = Material->GetMaterial();
	return Base && Base->GetName().Contains(TEXT("Outline"));
}

void Apply(UPrimitiveComponent* Component, const TSet<FString>& Hidden, bool bOutline)
{
	const FString Name = PartName(Component);
	if (Name.IsEmpty()) return;
	const bool bShell = Component->ComponentHasTag(TEXT("KKPreviewOutline"));
	const bool bHide = Hidden.Contains(Name) || (bShell && !bOutline);
	if (bHide && !Component->bHiddenInGame)
	{
		Component->SetHiddenInGame(true);
		Component->ComponentTags.AddUnique(DebugHiddenTag);
	}
	else if (!bHide && Component->ComponentHasTag(DebugHiddenTag))
	{
		Component->SetHiddenInGame(false);
		Component->ComponentTags.Remove(DebugHiddenTag);
	}
	// A procedural part draws its outline as extra sections of its own mesh.
	if (UProceduralMeshComponent* Mesh = Cast<UProceduralMeshComponent>(Component))
		for (int32 Section = 1; Section < Mesh->GetNumSections(); ++Section)
			if (IsOutlineMaterial(Mesh->GetMaterial(Section)))
				Mesh->SetMeshSectionVisible(Section, bOutline);
}

void ApplyAll(IConsoleVariable*)
{
	const TSet<FString> Hidden = HiddenNames();
	const bool bOutline = CVarOutline.GetValueOnGameThread() != 0;
	for (TObjectIterator<AKKPreviewActor> It; It; ++It)
	{
		if (It->HasAnyFlags(RF_ClassDefaultObject) || !It->GetWorld()) continue;
		TInlineComponentArray<UPrimitiveComponent*> Components(*It);
		for (UPrimitiveComponent* Component : Components) Apply(Component, Hidden, bOutline);
	}
}

FAutoConsoleCommandWithWorldArgsAndOutputDevice DumpPartsCommand(TEXT("ok.Debug.DumpParts"),
	TEXT("Lists every character part (OKPart= tag): its name, component, visibility, and each material slot with its blend mode."),
	FConsoleCommandWithWorldArgsAndOutputDeviceDelegate::CreateLambda([](const TArray<FString>&, UWorld* World, FOutputDevice& Ar)
	{
		int32 Count = 0;
		for (TObjectIterator<AKKPreviewActor> It; It; ++It)
		{
			if (It->HasAnyFlags(RF_ClassDefaultObject) || (World && It->GetWorld() != World)) continue;
			TInlineComponentArray<UPrimitiveComponent*> Components(*It);
			for (UPrimitiveComponent* Component : Components)
			{
				const FString Name = PartName(Component);
				if (Name.IsEmpty()) continue;
				FString Slots;
				for (int32 Slot = 0; Slot < Component->GetNumMaterials(); ++Slot)
				{
					const UMaterialInterface* Material = Component->GetMaterial(Slot);
					const UMaterial* Base = Material ? Material->GetMaterial() : nullptr;
					Slots += FString::Printf(TEXT(" [%d %s base=%s blend=%d twosided=%d]"), Slot, Material ? *Material->GetName() : TEXT("none"),
						Base ? *Base->GetName() : TEXT("none"), Material ? int32(Material->GetBlendMode()) : -1, Material ? int32(Material->IsTwoSided()) : -1);
				}
				Ar.Logf(TEXT("OK part %s actor=%s component=%s class=%s visible=%d hidden_in_game=%d debug_hidden=%d outline_shell=%d%s"), *Name,
					*It->GetName(), *Component->GetName(), *Component->GetClass()->GetName(), int32(Component->IsVisible()), int32(Component->bHiddenInGame),
					int32(Component->ComponentHasTag(DebugHiddenTag)), int32(Component->ComponentHasTag(TEXT("KKPreviewOutline"))), *Slots);
				++Count;
			}
		}
		Ar.Logf(TEXT("OK parts listed=%d"), Count);
	}));
}

// Whether a part's vertex normals still agree with its triangles' own facing as it moves: the outline shell is pushed out
// along the vertex normals and drawn on the faces turned away, so where the two disagree the shell comes out in front.
static FAutoConsoleCommandWithWorldArgsAndOutputDevice GOKNormalCheckCommand(TEXT("ok.Debug.NormalCheck"),
	TEXT("ok.Debug.NormalCheck <part>: for each character's part of that name, how many triangles' vertex normals point against the triangle's own facing (now)."),
	FConsoleCommandWithWorldArgsAndOutputDeviceDelegate::CreateLambda([](const TArray<FString>& Args, UWorld* World, FOutputDevice& Ar)
	{
		const FString Wanted = FString::Join(Args, TEXT(" "));
		for (TObjectIterator<AKKPreviewActor> It; It; ++It)
		{
			if (It->HasAnyFlags(RF_ClassDefaultObject) || (World && It->GetWorld() != World)) continue;
			for (const FKKLoadedPart& Part : It->Parts)
			{
				if (!Part.Comp || PartName(Part.Comp) != Wanted) continue;
				const TArray<FVector>& V = Part.BaseVertices;
				const TArray<FVector>& N = Part.BaseNormals;
				// The part's own convention (UE's handedness flips the sign) is the majority; the rest are the odd ones.
				TArray<double> Means;
				TArray<FVector> Centres;
				for (int32 T = 0; T + 2 < Part.Triangles.Num(); T += 3)
				{
					const int32 A = Part.Triangles[T], B = Part.Triangles[T + 1], C = Part.Triangles[T + 2];
					if (!V.IsValidIndex(A) || !V.IsValidIndex(B) || !V.IsValidIndex(C) || !N.IsValidIndex(A) || !N.IsValidIndex(B) || !N.IsValidIndex(C)) continue;
					const FVector Face = FVector::CrossProduct(V[B] - V[A], V[C] - V[A]).GetSafeNormal();
					if (Face.IsNearlyZero()) continue;
					Means.Add(((Face | N[A].GetSafeNormal()) + (Face | N[B].GetSafeNormal()) + (Face | N[C].GetSafeNormal())) / 3.0);
					Centres.Add(Part.Comp->GetComponentTransform().TransformPosition((V[A] + V[B] + V[C]) / 3.0));
				}
				int32 Negative = 0;
				for (double Mean : Means) Negative += Mean < 0.0 ? 1 : 0;
				const bool MajorityNegative = Negative * 2 >= Means.Num();
				FBox All(ForceInit), Odd(ForceInit);
				int32 OddCount = 0;
				for (int32 I = 0; I < Means.Num(); ++I)
				{
					All += Centres[I];
					if ((Means[I] < 0.0) != MajorityNegative) { Odd += Centres[I]; ++OddCount; }
				}
				Ar.Logf(TEXT("OK normal check %s actor=%s component=%s tris=%d odd=%d all=[%s .. %s] odd=[%s .. %s] private_gpu=%d"), *Wanted,
					*It->GetName(), *Part.Comp->GetName(), Means.Num(), OddCount, *All.Min.ToCompactString(), *All.Max.ToCompactString(),
					Odd.IsValid ? *Odd.Min.ToCompactString() : TEXT("-"), Odd.IsValid ? *Odd.Max.ToCompactString() : TEXT("-"), Part.PrivateGpuDisplay ? 1 : 0);
			}
		}
	}));

void OKTagPreviewPart(UPrimitiveComponent* Component, const FString& Name)
{
	if (!Component || Name.IsEmpty()) return;
	// A pooled component drawing another part now: only its current part's name.
	Component->ComponentTags.RemoveAll([](const FName& Tag) { return Tag.ToString().StartsWith(PartTagPrefix); });
	Component->ComponentTags.Add(FName(*(FString(PartTagPrefix) + Name)));
	Apply(Component, HiddenNames(), CVarOutline.GetValueOnGameThread() != 0);
}
