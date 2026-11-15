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

void OKTagPreviewPart(UPrimitiveComponent* Component, const FString& Name)
{
	if (!Component || Name.IsEmpty()) return;
	// A pooled component drawing another part now: only its current part's name.
	Component->ComponentTags.RemoveAll([](const FName& Tag) { return Tag.ToString().StartsWith(PartTagPrefix); });
	Component->ComponentTags.Add(FName(*(FString(PartTagPrefix) + Name)));
	Apply(Component, HiddenNames(), CVarOutline.GetValueOnGameThread() != 0);
}
