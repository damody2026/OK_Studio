#pragma once
#include "CoreMinimal.h"
#include "Materials/MaterialInstanceDynamic.h"

// A lit stand-in (a <name>_Lit instance shown in place of the character's own instance) kept in step with the original.
// Whatever sets the shown material writes to the stand-in while it is shown: her clothes' _alpha_a / _alpha_b, the body
// mask, overrides (user 2026-11-09: her half-off top black, lit and unlit). Each sync first gives the original every value
// written to the stand-in since the last sync (what differs from what the sync left there), then copies the original's
// values over. The original thus holds everything, and is right when it is shown again.
struct FKKLitSnapshot {
    TArray<FScalarParameterValue> Scalars;TArray<FVectorParameterValue> Vectors;TArray<FTextureParameterValue> Textures;
};

inline void KKSyncLitInstance(UMaterialInstanceDynamic* Lit,UMaterialInstanceDynamic* Original,FKKLitSnapshot& Last){
    if(!Lit||!Original)return;
    for(const FScalarParameterValue& V:Lit->ScalarParameterValues){
        const FScalarParameterValue* Was=Last.Scalars.FindByPredicate([&](const FScalarParameterValue& X){return X.ParameterInfo==V.ParameterInfo;});
        if(!Was||Was->ParameterValue!=V.ParameterValue)Original->SetScalarParameterValueByInfo(V.ParameterInfo,V.ParameterValue);
    }
    for(const FVectorParameterValue& V:Lit->VectorParameterValues){
        const FVectorParameterValue* Was=Last.Vectors.FindByPredicate([&](const FVectorParameterValue& X){return X.ParameterInfo==V.ParameterInfo;});
        if(!Was||Was->ParameterValue!=V.ParameterValue)Original->SetVectorParameterValueByInfo(V.ParameterInfo,V.ParameterValue);
    }
    for(const FTextureParameterValue& V:Lit->TextureParameterValues){
        const FTextureParameterValue* Was=Last.Textures.FindByPredicate([&](const FTextureParameterValue& X){return X.ParameterInfo==V.ParameterInfo;});
        if(!Was||Was->ParameterValue!=V.ParameterValue)Original->SetTextureParameterValueByInfo(V.ParameterInfo,V.ParameterValue);
    }
    Lit->CopyParameterOverrides(Original);
    Last.Scalars=Lit->ScalarParameterValues;Last.Vectors=Lit->VectorParameterValues;Last.Textures=Lit->TextureParameterValues;
}
