#include "OKTears.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "GameFramework/Actor.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "ProceduralMeshComponent.h"
#include "KKAffineProceduralMeshComponent.h"

namespace{
 constexpr int32 MaxTears=8;
 constexpr float StepCm=.4f;            // FaceTearPath's step (the panel asks for 4 mm)
 constexpr float StreakCm=.24f,ShineCm=.06f;
 constexpr float WetFor=2.5f,DryFor=4.f; // after the bead is gone: still wet, then drying away
 const FLinearColor WetTint(.82f,.9f,1.f,.32f),ShineTint(3.5f,3.5f,3.8f,.55f),DropTint(.85f,.92f,1.f,.5f),SparkTint(5.f,5.f,5.f,1.f);
 UStaticMesh* Sphere(){return LoadObject<UStaticMesh>(nullptr,TEXT("/Engine/BasicShapes/Sphere.Sphere"));}
}

UMaterialInstanceDynamic* FOKTears::Tinted(AActor* Owner,const FLinearColor& Tint) const{
 UMaterialInterface* Parent=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewTranslucent.M_PreviewTranslucent"));
 if(!Parent||!Owner)return nullptr;
 auto* M=UMaterialInstanceDynamic::Create(Parent,Owner);M->SetVectorParameterValue(TEXT("PreviewTint"),Tint);return M;
}

void FOKTears::Add(AActor* Owner,USceneComponent* Attach,FName Bone,const TArray<FVector>& WorldPoints,const TArray<FVector>& WorldNormals){
 if(!Owner||!Attach||WorldPoints.Num()<3||WorldPoints.Num()!=WorldNormals.Num())return;
 while(Tears.Num()>=MaxTears){FTear& Old=Tears[0];for(auto* C:{(USceneComponent*)Old.Streak.Get(),(USceneComponent*)Old.Shine.Get(),(USceneComponent*)Old.Bead.Get(),(USceneComponent*)Old.Glint.Get()})if(C)C->DestroyComponent();Tears.RemoveAt(0);}
 const FTransform Socket=Attach->GetSocketTransform(Bone);
 FTear& T=Tears.AddDefaulted_GetRef();
 for(int32 I=0;I<WorldPoints.Num();++I){T.P.Add(Socket.InverseTransformPosition(WorldPoints[I]));T.N.Add(Socket.InverseTransformVectorNoScale(WorldNormals[I]).GetSafeNormal());}
 T.Speed=FMath::FRandRange(1.6f,3.f);
 auto Hang=[&](USceneComponent* C){C->RegisterComponent();C->AttachToComponent(Attach,FAttachmentTransformRules::SnapToTargetIncludingScale,Bone);};
 for(int32 Layer=0;Layer<2;++Layer){
  auto* M=NewObject<UKKAffineProceduralMeshComponent>(Owner);/* PSOs precached; stock procedural meshes collect none */M->SetCastShadow(false);M->SetCollisionEnabled(ECollisionEnabled::NoCollision);M->bUseAsyncCooking=false;
  M->SetTranslucentSortPriority(1+Layer);Hang(M);
  UMaterialInstanceDynamic* Mat=Tinted(Owner,Layer?ShineTint:WetTint);(Layer?T.Shine:T.Streak)=M;(Layer?T.Gleam:T.Wet)=Mat;
 }
 if(UStaticMesh* Mesh=Sphere())for(int32 Layer=0;Layer<2;++Layer){
  auto* C=NewObject<UStaticMeshComponent>(Owner);C->SetStaticMesh(Mesh);C->SetCastShadow(false);C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
  C->SetMobility(EComponentMobility::Movable);C->SetTranslucentSortPriority(3+Layer);Hang(C);
  UMaterialInstanceDynamic* Mat=Tinted(Owner,Layer?SparkTint:DropTint);C->SetMaterial(0,Mat);(Layer?T.Glint:T.Bead)=C;(Layer?T.Spark:T.Drop)=Mat;
 }
}

// The streak and its bright line from where the tear started to the bead: a ribbon across her skin at each point.
void FOKTears::Draw(FTear& T,float Alpha,float ShineAlpha){
 const int32 Last=FMath::Min(T.P.Num()-1,FMath::FloorToInt(T.Front));const float Frac=T.Front-Last;
 TArray<FVector> At,Up;for(int32 I=0;I<=Last;++I){At.Add(T.P[I]);Up.Add(T.N[I]);}
 if(Last+1<T.P.Num()&&Frac>0.f){At.Add(FMath::Lerp(T.P[Last],T.P[Last+1],Frac));Up.Add(FMath::Lerp(T.N[Last],T.N[Last+1],Frac).GetSafeNormal());}
 for(int32 Layer=0;Layer<2;++Layer){
  UProceduralMeshComponent* M=(Layer?T.Shine:T.Streak).Get();if(!M)continue;
  if(At.Num()<2){M->ClearAllMeshSections();continue;}
  TArray<FVector> V,Nrm;TArray<int32> Tri;TArray<FVector2D> UV;TArray<FLinearColor> Col;TArray<FProcMeshTangent> Tan;
  const float Width=Layer?ShineCm:StreakCm;
  for(int32 I=0;I<At.Num();++I){
   const FVector Along=(At[FMath::Min(I+1,At.Num()-1)]-At[FMath::Max(I-1,0)]).GetSafeNormal();
   const FVector Side=FVector::CrossProduct(Up[I],Along).GetSafeNormal();
   // Thinner toward where it started (it has run off there), widest just behind the bead.
   const float W=Width*.5f*FMath::Lerp(.55f,1.f,float(I)/FMath::Max(1,At.Num()-1));
   const FVector C=At[I]+Up[I]*(Layer?.035f:.015f);
   V.Add(C-Side*W);V.Add(C+Side*W);Nrm.Add(Up[I]);Nrm.Add(Up[I]);UV.Add(FVector2D(0,I));UV.Add(FVector2D(1,I));
   Col.Add(FLinearColor::White);Col.Add(FLinearColor::White);Tan.Add(FProcMeshTangent(Along,false));Tan.Add(FProcMeshTangent(Along,false));
   if(I>0){const int32 A=2*I-2,B=2*I-1,Cc=2*I,D=2*I+1;Tri.Append({A,Cc,B,B,Cc,D,A,B,Cc,B,D,Cc});} // both faces
  }
  M->CreateMeshSection_LinearColor(0,V,Tri,Nrm,UV,Col,Tan,false);
  UMaterialInstanceDynamic* Mat=(Layer?T.Gleam:T.Wet).Get();if(Mat){FLinearColor Tint=Layer?ShineTint:WetTint;Tint.A*=Layer?ShineAlpha:Alpha;Mat->SetVectorParameterValue(TEXT("PreviewTint"),Tint);M->SetMaterial(0,Mat);}
 }
}

void FOKTears::Tick(float Dt,const FVector& Eye){
 for(int32 Index=Tears.Num()-1;Index>=0;--Index){FTear& T=Tears[Index];T.Age+=Dt;
  // It runs a little, holds, runs on (a real tear stops where her skin is dry).
  if(T.Ended<0.f){
   if(T.Pause>0.f)T.Pause-=Dt;
   else{const int32 Was=FMath::FloorToInt(T.Front);T.Front+=T.Speed*Dt/StepCm;
    if(FMath::FloorToInt(T.Front)!=Was&&FMath::FRand()<.12f)T.Pause=FMath::FRandRange(.2f,.7f);}
   if(T.Front>=T.P.Num()-1){T.Front=float(T.P.Num()-1);T.Ended=T.Age;}
  }
  const float Since=T.Ended<0.f?0.f:T.Age-T.Ended;
  const float Alpha=FMath::Clamp(1.f-(Since-WetFor)/DryFor,0.f,1.f);
  const float BeadAlpha=T.Ended<0.f?1.f:FMath::Clamp(1.f-Since/.6f,0.f,1.f);
  Draw(T,Alpha,Alpha*Alpha);
  // The bead at the front, swelling as it runs; its highlight toward the camera.
  const int32 Last=FMath::Min(T.P.Num()-1,FMath::FloorToInt(T.Front));const int32 Next=FMath::Min(T.P.Num()-1,Last+1);const float Frac=T.Front-Last;
  const FVector At=FMath::Lerp(T.P[Last],T.P[Next],Frac),Up=FMath::Lerp(T.N[Last],T.N[Next],Frac).GetSafeNormal();
  const float Size=.0032f*FMath::Lerp(.8f,1.15f,FMath::Clamp(T.Front/FMath::Max(1,T.P.Num()-1),0.f,1.f))*BeadAlpha;
  if(auto* B=T.Bead.Get()){B->SetRelativeLocation(At+Up*.11f);B->SetRelativeScale3D(FVector(Size,Size,Size*.8f));B->SetVisibility(BeadAlpha>0.f);}
  if(auto* G=T.Glint.Get();G&&T.Bead.IsValid()){const FVector W=T.Bead->GetComponentLocation();const FVector Toward=((Eye-W).GetSafeNormal()+FVector(0,0,.6f)).GetSafeNormal();
   G->SetWorldLocation(W+Toward*Size*50.f*.55f);G->SetWorldScale3D(FVector(Size*.3f));G->SetVisibility(BeadAlpha>0.f);}
  if(Alpha<=0.f){for(auto* C:{(USceneComponent*)T.Streak.Get(),(USceneComponent*)T.Shine.Get(),(USceneComponent*)T.Bead.Get(),(USceneComponent*)T.Glint.Get()})if(C)C->DestroyComponent();Tears.RemoveAtSwap(Index);}
 }
}

void FOKTears::Reset(){
 for(FTear& T:Tears)for(auto* C:{(USceneComponent*)T.Streak.Get(),(USceneComponent*)T.Shine.Get(),(USceneComponent*)T.Bead.Get(),(USceneComponent*)T.Glint.Get()})if(C)C->DestroyComponent();
 Tears.Reset();
}
