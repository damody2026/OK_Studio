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

// Same names and values in the same order (what a sync leaves in both instances).
template<typename T> bool KKLitSame(const TArray<T>& A,const TArray<T>& B){
    if(A.Num()!=B.Num())return false;
    for(int32 I=0;I<A.Num();++I)if(!(A[I].ParameterInfo==B[I].ParameterInfo)||A[I].ParameterValue!=B[I].ParameterValue)return false;
    return true;
}
// Only the values that moved in Original since the last sync set on Lit, the lists unchanged otherwise. False when the
// lists differ in shape (a parameter added or removed): then the whole copy below.
template<typename T,typename SetFn> bool KKLitApplyMoved(const TArray<T>& Now,const TArray<T>& Was,SetFn&& Set){
    if(Now.Num()!=Was.Num())return false;
    for(int32 I=0;I<Now.Num();++I)if(!(Now[I].ParameterInfo==Was[I].ParameterInfo))return false;
    for(int32 I=0;I<Now.Num();++I)if(Now[I].ParameterValue!=Was[I].ParameterValue)Set(Now[I]);
    return true;
}

inline void KKSyncLitInstance(UMaterialInstanceDynamic* Lit,UMaterialInstanceDynamic* Original,FKKLitSnapshot& Last){
    if(!Lit||!Original)return;
    // Every frame for every lit instance of both of them: the whole copy re-sent each instance to the render thread, 0.33 ms
    // of the H scene's game thread (2026-11-10). Nothing written to either since the last sync: nothing to do. Only her own
    // instance moved (her blush, her clothes' alpha): those values alone.
    const bool bLitSame=KKLitSame(Lit->ScalarParameterValues,Last.Scalars)&&KKLitSame(Lit->VectorParameterValues,Last.Vectors)&&KKLitSame(Lit->TextureParameterValues,Last.Textures);
    if(bLitSame){
        if(KKLitSame(Original->ScalarParameterValues,Last.Scalars)&&KKLitSame(Original->VectorParameterValues,Last.Vectors)&&KKLitSame(Original->TextureParameterValues,Last.Textures))return;
        if(KKLitApplyMoved(Original->ScalarParameterValues,Last.Scalars,[&](const FScalarParameterValue& V){Lit->SetScalarParameterValueByInfo(V.ParameterInfo,V.ParameterValue);})
            &&KKLitApplyMoved(Original->VectorParameterValues,Last.Vectors,[&](const FVectorParameterValue& V){Lit->SetVectorParameterValueByInfo(V.ParameterInfo,V.ParameterValue);})
            &&KKLitApplyMoved(Original->TextureParameterValues,Last.Textures,[&](const FTextureParameterValue& V){Lit->SetTextureParameterValueByInfo(V.ParameterInfo,V.ParameterValue);})){
            Last.Scalars=Original->ScalarParameterValues;Last.Vectors=Original->VectorParameterValues;Last.Textures=Original->TextureParameterValues;
            if(KKLitSame(Lit->ScalarParameterValues,Last.Scalars)&&KKLitSame(Lit->VectorParameterValues,Last.Vectors)&&KKLitSame(Lit->TextureParameterValues,Last.Textures))return;
        }
    }
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
