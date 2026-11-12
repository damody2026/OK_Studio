#pragma once
#include "CoreMinimal.h"

class AActor;

// Characters lit by the scene instead of their own toon (user 2026-11-09: the street's lit / unlit switch). Every material
// instance on Owner's components whose parent has a <name>_Lit sibling under LitRoot (Tools/prepare_runtime_shared_material.lua
// --lit-only; a face's <name>_Flat goes by its family) is swapped for an instance of that one, its values copied from the
// original on every call (whatever sets the original each frame still does). Parts not drawn in the main pass stay as
// they are, and so do the affine parts (hair, clothes, accessories) while ok.Lit.Affine is 0. false gives every original
// back. Returns how many instances are lit now.
int32 OKSetActorLit(AActor* Owner,bool bOn,const FString& LitRoot);

// The lit parents' root: the manifest's lit_material_root (Launch/materials.json lit_root), else the current one.
const FString& OKLitMaterialRootPath();
