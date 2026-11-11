#include "OKStreetBacks.h"

#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "Components/StaticMeshComponent.h"
#include "ProfilingDebugging/CpuProfilerTrace.h"

static TAutoConsoleVariable<int32> CVarStreetHideBacks(TEXT("ok.Street.HideBacks"),1,TEXT("1: a street shape the camera is inside, or a floor it is under, is not drawn; 0: all drawn"));

namespace{
 struct FBacks{TWeakObjectPtr<UWorld> World;double FoundAt=-1.;TArray<TWeakObjectPtr<UStaticMeshComponent>> Shapes;TSet<TWeakObjectPtr<UStaticMeshComponent>> Hidden;FVector Eye=FVector::ZeroVector;bool bLooked=false,bOn=true;};
 FBacks GBacks;
 // The street's own shapes and the engine's basic ones (the room's walls and floor are those too); not the people.
 bool IsStreetShape(const UStaticMeshComponent* C){
  const UStaticMesh* Mesh=C?C->GetStaticMesh():nullptr;if(!Mesh)return false;
  const FString Path=Mesh->GetPathName();return Path.StartsWith(TEXT("/Game/Scenes/StreetSocial/"))||Path.StartsWith(TEXT("/Engine/BasicShapes/"));
 }
}

void OKHideStreetBacks(UWorld* World,const FVector& Eye){
 FBacks& B=GBacks;const bool bOn=CVarStreetHideBacks.GetValueOnGameThread()!=0;
 if(B.World!=World){for(auto& C:B.Hidden)if(C.IsValid())C->SetVisibility(true);B=FBacks();B.World=World;}
 if(!World)return;
 // Shapes come and go (shops, the room's walls): looked up again every two seconds.
 const double Now=World->GetTimeSeconds();
 TRACE_CPUPROFILER_EVENT_SCOPE(Street_HideBacks);
 if(B.FoundAt<0.||Now-B.FoundAt>2.){B.FoundAt=Now;B.Shapes.Reset();B.bLooked=false;
  for(TActorIterator<AStaticMeshActor> It(World);It;++It)if(UStaticMeshComponent* C=It->GetStaticMeshComponent();IsStreetShape(C))B.Shapes.Add(C);}
 // The same eye over the same shapes hides the same ones: a still camera (the one-on-one's, mostly) costs nothing. Every
 // frame it took 0.4 ms of the game thread in the university city (2026-11-12).
 else if(B.bLooked&&B.bOn==bOn&&FVector::DistSquared(B.Eye,Eye)<1.)return;
 B.bLooked=true;B.bOn=bOn;B.Eye=Eye;
 TSet<TWeakObjectPtr<UStaticMeshComponent>> Hide;
 if(bOn)for(const auto& Weak:B.Shapes){UStaticMeshComponent* C=Weak.Get();if(!C||!C->GetStaticMesh())continue;
  // In the shape's own space: inside its box (2 cm in from its faces), or lower than a floor's top (a slab far wider
  // than it is thick) under it. The ground (such a slab with its top under half a metre) wherever: under the next
  // slab along, its underside hid the view as well. Roofs and awnings only right under them, not from the street.
  const FBox Local=C->GetStaticMesh()->GetBoundingBox();const FVector P=C->GetComponentTransform().InverseTransformPosition(Eye);
  const FVector Size=Local.GetSize()*C->GetComponentScale().GetAbs();const float Margin=2.f;
  const FVector In=FVector(Margin)/C->GetComponentScale().GetAbs().ComponentMax(FVector(KINDA_SMALL_NUMBER));
  const bool bFloor=Size.Z*4.f<FMath::Min(Size.X,Size.Y);
  const bool bInXY=P.X>Local.Min.X+In.X&&P.X<Local.Max.X-In.X&&P.Y>Local.Min.Y+In.Y&&P.Y<Local.Max.Y-In.Y;
  const bool bGround=bFloor&&C->Bounds.Origin.Z+C->Bounds.BoxExtent.Z<50.;
  if(P.Z<Local.Max.Z-In.Z&&(bGround||bInXY&&(bFloor||P.Z>Local.Min.Z+In.Z)))Hide.Add(Weak);}
 for(auto& C:B.Hidden)if(!Hide.Contains(C)&&C.IsValid())C->SetVisibility(true);
 for(auto& C:Hide)if(!B.Hidden.Contains(C)&&C.IsValid())C->SetVisibility(false);
 B.Hidden=MoveTemp(Hide);
}
