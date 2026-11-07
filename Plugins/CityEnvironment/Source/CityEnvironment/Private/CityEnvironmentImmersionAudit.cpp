// Opt-in cooked-world physics and walking soak validation. Normal play is inert.
#include "CityEnvironmentImmersionAudit.h"
#include "CityEnvironmentController.h"
#include "CityImmersionWalker.h"
#include "CityImmersionInputAudit.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "CollisionShape.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Containers/Ticker.h"
#include "Dom/JsonObject.h"
#include "Engine/Engine.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerController.h"
#include "HAL/PlatformMemory.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UnrealClient.h"

namespace
{
 FTSTicker::FDelegateHandle ImmersionTickerHandle;
 FString ImmersionAuditOutputPath, PlanPath;
 TSharedPtr<FJsonObject> Plan, Report;
 TWeakObjectPtr<ACityEnvironmentController> ImmersionClockController;
 TWeakObjectPtr<ACameraActor> Camera;
 TArray<TSharedPtr<FJsonValue>> Samples, Images;
 TArray<TSharedPtr<FJsonValue>> CompletedRouteRecords;
 int32 ImmersionPawnGlazingChecks=0;
 TArray<TSharedPtr<FJsonValue>> ImmersionFrameHitches;
 int64 ImmersionFrameCount=0,ImmersionSlowFrames=0,ImmersionUncapturedSlowFrames=0;
 double ImmersionMaxFrameGap=0,ImmersionMaxUncapturedGap=0,ImmersionLastImageAt=-1.e12;
 TArray<TWeakObjectPtr<UInstancedStaticMeshComponent>> StemComponents;
 TMap<FString,TWeakObjectPtr<UStaticMeshComponent>> FixtureComponents;
 int32 RayIndex=0, FloorIndex=0, SweepIndex=0, StemGroup=0, StemIndex=0, StemChecks=0;
 int32 StemRenderLinksChecked=0;
 int32 FixtureChecks=0;
 int32 WalkRoute=0, WalkSegment=0, CompletedRoutes=0, StepAssists=0;
 double Started=0, ReadyAt=0, SoakStarted=0, SoakSeconds=0;
 double NextSample=0, NextImage=0, LastWalk=0, WalkDistance=0;
 FVector PreviousBody=FVector::ZeroVector;
 bool PreviousBodyValid=false;
 TWeakObjectPtr<ACityImmersionWalker> Walker;
 bool CharacterRouteStarted=false;
 double CharacterLastProgress=0,CharacterBestDistance=1.e30;

 FVector Vec(const TSharedPtr<FJsonObject>& Row, const TCHAR* Key)
 {
  const auto& A=Row->GetArrayField(Key);
  return FVector(A[0]->AsNumber(),A[1]->AsNumber(),A[2]->AsNumber());
 }
 TArray<TSharedPtr<FJsonValue>> Coordinates(const FVector& V)
 {
  return {MakeShared<FJsonValueNumber>(V.X),MakeShared<FJsonValueNumber>(V.Y),MakeShared<FJsonValueNumber>(V.Z)};
 }
 void Save(const TCHAR* Status)
 {
  Report->SetStringField(TEXT("status"),Status);
  Report->SetNumberField(TEXT("elapsed_real_seconds"),FPlatformTime::Seconds()-Started);
  Report->SetNumberField(TEXT("rays_checked"),RayIndex);
  Report->SetNumberField(TEXT("pawn_simple_glazing_checks"),ImmersionPawnGlazingChecks);
  Report->SetNumberField(TEXT("floor_probes_checked"),FloorIndex);
  Report->SetNumberField(TEXT("capsule_sweeps_checked"),SweepIndex);
  Report->SetNumberField(TEXT("stem_proxies_checked"),StemChecks);
  Report->SetNumberField(TEXT("visible_stem_links_checked"),StemRenderLinksChecked);
  Report->SetNumberField(TEXT("solid_fixtures_checked"),FixtureChecks);
  Report->SetArrayField(TEXT("soak_samples"),Samples);
  Report->SetArrayField(TEXT("soak_images"),Images);
  Report->SetNumberField(TEXT("completed_walk_routes"),CompletedRoutes);
  Report->SetArrayField(TEXT("completed_route_records"),CompletedRouteRecords);
  Report->SetNumberField(TEXT("walking_frames"),double(ImmersionFrameCount));
  Report->SetNumberField(TEXT("frames_over_100ms"),double(ImmersionSlowFrames));
  Report->SetNumberField(TEXT("uncaptured_frames_over_100ms"),double(ImmersionUncapturedSlowFrames));
  Report->SetNumberField(TEXT("max_frame_gap_ms"),ImmersionMaxFrameGap*1000.);
  Report->SetNumberField(TEXT("max_uncaptured_frame_gap_ms"),ImmersionMaxUncapturedGap*1000.);
  Report->SetArrayField(TEXT("first_frame_hitches"),ImmersionFrameHitches);
  Report->SetStringField(TEXT("frame_timing_scope"),TEXT("Real core-ticker gaps while walking; screenshot request and following1s classified separately. Includes audit query/readback cost; not a standalone GPU benchmark."));
  FString Text;
  FJsonSerializer::Serialize(Report.ToSharedRef(),TJsonWriterFactory<>::Create(&Text));
  IFileManager::Get().MakeDirectory(*FPaths::GetPath(ImmersionAuditOutputPath),true);
  FFileHelper::SaveStringToFile(Text,*ImmersionAuditOutputPath);
 }
 bool Finish(const FString& Error=FString(),const TSharedPtr<FJsonObject>& Detail=nullptr)
 {
  if(!Error.IsEmpty())Report->SetStringField(TEXT("error"),Error);
  if(Detail)Report->SetObjectField(TEXT("error_detail"),Detail);
  Report->SetNumberField(TEXT("completed_walk_routes"),CompletedRoutes);
  Report->SetNumberField(TEXT("walking_step_assists"),StepAssists);
  Report->SetNumberField(TEXT("soak_real_seconds"),SoakStarted>0?FPlatformTime::Seconds()-SoakStarted:0);
  Save(Error.IsEmpty()?TEXT("passed"):TEXT("failed"));
  FPlatformMisc::RequestExit(false);
  return false;
 }
 TSharedPtr<FJsonObject> HitDetail(const TSharedPtr<FJsonObject>& Row,const FHitResult& Hit,bool Blocked)
 {
  auto D=MakeShared<FJsonObject>();D->SetObjectField(TEXT("query"),Row);
  D->SetBoolField(TEXT("blocked"),Blocked);
  D->SetStringField(TEXT("actor"),Hit.GetActor()?Hit.GetActor()->GetPathName():TEXT(""));
  D->SetStringField(TEXT("component"),Hit.GetComponent()?Hit.GetComponent()->GetPathName():TEXT(""));
  D->SetArrayField(TEXT("point_cm"),Coordinates(Hit.ImpactPoint));return D;
 }
 bool ResolveStems(UWorld* World)
 {
  for(auto V:Plan->GetArrayField(TEXT("stem_groups")))
  {
   auto Row=V->AsObject();TArray<UInstancedStaticMeshComponent*> Found;
   for(TActorIterator<AActor> It(World);It;++It)
   {
    if(It->GetName()!=Row->GetStringField(TEXT("owner_object_name")))continue;
    TInlineComponentArray<UInstancedStaticMeshComponent*> Cs;It->GetComponents(Cs);
    for(auto C:Cs)if(C->GetName()==Row->GetStringField(TEXT("component_name")))Found.Add(C);
   }
   if(Found.Num()!=1)return false;
   auto C=Found[0];auto Mesh=C->GetStaticMesh();
   if(!Mesh||Mesh->GetPathName()!=Row->GetStringField(TEXT("mesh"))||C->GetInstanceCount()!=Row->GetIntegerField(TEXT("instance_count"))||C->IsVisible()||!C->bHiddenInGame||C->bCastHiddenShadow||bool(C->CastShadow)!=Row->GetBoolField(TEXT("expected_cast_shadow"))||C->GetCollisionProfileName()!=FName(TEXT("BlockAll"))||C->GetCollisionResponseToChannel(ECC_Pawn)!=ECR_Block||C->GetCollisionResponseToChannel(ECC_Visibility)!=ECR_Block)return false;
   StemComponents.Add(C);
  }
  return true;
 }
 bool ResolveStemRenderLinks(UWorld* World)
 {
  TMap<FString,UStaticMeshComponent*> Components;
  for(TActorIterator<AActor> It(World);It;++It)
  {
   TInlineComponentArray<UStaticMeshComponent*> Cs;It->GetComponents(Cs);
   for(auto C:Cs){const FString Key=It->GetName()+TEXT("::")+C->GetName();Components.Add(Key,C);FixtureComponents.Add(Key,C);}
  }
  const auto& Links=Plan->GetArrayField(TEXT("stem_render_links"));
  TSet<FString> UsedTrees,UsedProxies;
  for(auto V:Links)
  {
   auto R=V->AsObject();const FString Key=R->GetStringField(TEXT("tree_owner_object_name"))+TEXT("::")+R->GetStringField(TEXT("tree_component_name"));
   auto Ptr=Components.Find(Key);if(!Ptr)return false;auto Tree=*Ptr;
   if(!Tree||!Tree->GetStaticMesh()||Tree->GetStaticMesh()->GetPathName()!=R->GetStringField(TEXT("tree_mesh"))||!Tree->IsVisible()||Tree->bHiddenInGame||Tree->GetOwner()->IsHidden())return false;
   const int32 Instance=R->GetIntegerField(TEXT("tree_instance"));FTransform TreeTransform=Tree->GetComponentTransform();
   if(Instance>=0)
   {
    auto ISM=Cast<UInstancedStaticMeshComponent>(Tree);
    if(!ISM||Instance>=ISM->GetInstanceCount()||!ISM->GetInstanceTransform(Instance,TreeTransform,true))return false;
   }
   else if(Cast<UInstancedStaticMeshComponent>(Tree))return false;
   const int32 Group=R->GetIntegerField(TEXT("proxy_group")),ProxyIndex=R->GetIntegerField(TEXT("proxy_instance"));
   if(!StemComponents.IsValidIndex(Group)||!StemComponents[Group].IsValid())return false;
   FTransform ProxyTransform;auto Proxy=StemComponents[Group].Get();
   if(ProxyIndex<0||ProxyIndex>=Proxy->GetInstanceCount()||!Proxy->GetInstanceTransform(ProxyIndex,ProxyTransform,true))return false;
   const FVector TreeRoot=TreeTransform.GetTranslation(),ProxyBase=ProxyTransform.TransformPosition(Vec(R,TEXT("proxy_base_local_cm"))),Expected=Vec(R,TEXT("expected_root_cm"));
   if(FVector::Distance(TreeRoot,Expected)>1.||FVector::DistXY(TreeRoot,ProxyBase)>1.||FMath::Abs(TreeRoot.Z-ProxyBase.Z)>5.)return false;
   const FString TreeKey=Key+TEXT("/")+FString::FromInt(Instance),ProxyKey=FString::FromInt(Group)+TEXT("/")+FString::FromInt(ProxyIndex);
   if(UsedTrees.Contains(TreeKey)||UsedProxies.Contains(ProxyKey))return false;
   UsedTrees.Add(TreeKey);UsedProxies.Add(ProxyKey);++StemRenderLinksChecked;
  }
  int32 ExpectedCount=0;for(auto C:StemComponents)ExpectedCount+=C->GetInstanceCount();
  return StemRenderLinksChecked==ExpectedCount&&Links.Num()==ExpectedCount;
 }
 bool CharacterWalk(UWorld* World,double Now)
 {
  auto Pawn=Walker.Get();if(!Pawn)return false;
  auto PC=Cast<APlayerController>(Pawn->GetController());if(!PC)return false;
  const auto& Routes=Plan->GetArrayField(TEXT("walk_routes"));
  auto Route=Routes[WalkRoute]->AsObject();const auto& Points=Route->GetArrayField(TEXT("points"));
  auto Point=[&](int32 I){const auto& A=Points[I]->AsArray();return FVector(A[0]->AsNumber(),A[1]->AsNumber(),A.Num()>2?A[2]->AsNumber():0);};
  FCollisionQueryParams Q(SCENE_QUERY_STAT(ImmersionCharacterWalk),true,Pawn);
  auto GroundAt=[&](const FVector& XY,FHitResult& Hit){const double Top=XY.Z>0?XY.Z+35:1380,Bottom=XY.Z>0?XY.Z-80:1100;return World->LineTraceSingleByChannel(Hit,FVector(XY.X,XY.Y,Top),FVector(XY.X,XY.Y,Bottom),ECC_Visibility,Q);};
  if(!CharacterRouteStarted)
  {
   FHitResult Ground;if(!GroundAt(Point(0),Ground))return false;
   Pawn->GetCharacterMovement()->StopMovementImmediately();
   Pawn->SetActorLocation(FVector(Point(0).X,Point(0).Y,Ground.ImpactPoint.Z+90),false,nullptr,ETeleportType::TeleportPhysics);
   Pawn->GetCharacterMovement()->SetMovementMode(MOVE_Falling);
   CharacterRouteStarted=true;CharacterLastProgress=Now;CharacterBestDistance=1.e30;return true;
  }
  const FVector Location=Pawn->GetActorLocation(),Target=Point(WalkSegment+1);
  FHitResult Ground;const bool Supported=GroundAt(FVector(Location.X,Location.Y,Location.Z-88),Ground);
  // At a tread edge the capsule already rests on the next tread while its
  // centre ray still sees the lower landing. Use the actual movement floor
  // contact; retain the finite centre probe for the initial falling settle.
  const auto* Movement = Pawn->GetCharacterMovement();
  const auto& Contact = Movement->CurrentFloor;
  const bool CapsuleSupported = Movement->IsMovingOnGround() && Contact.IsWalkableFloor() && Contact.FloorDist >= -2.f && Contact.FloorDist <= 5.f;
  if(!CapsuleSupported && (!Supported||Location.Z-Ground.ImpactPoint.Z<86||Location.Z-Ground.ImpactPoint.Z>120))
  {
   Report->SetArrayField(TEXT("unsupported_character_cm"),Coordinates(Location));Report->SetBoolField(TEXT("character_ground_hit"),Supported);
   if(Supported)Report->SetArrayField(TEXT("character_ground_cm"),Coordinates(Ground.ImpactPoint));
   Report->SetNumberField(TEXT("stalled_route"),WalkRoute);Report->SetNumberField(TEXT("stalled_segment"),WalkSegment);return false;
  }
  const double Distance=FVector::Dist2D(Location,Target);
  if(Distance<18&&(Target.Z<=0||FMath::Abs(Location.Z-90-Target.Z)<35))
  {
   if(++WalkSegment>=Points.Num()-1)
   {
    if(CompletedRouteRecords.Num()<256){auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("route"),Route->GetStringField(TEXT("id")));R->SetArrayField(TEXT("final_character_cm"),Coordinates(Location));R->SetArrayField(TEXT("final_target_cm"),Coordinates(Target));R->SetNumberField(TEXT("elapsed_seconds"),Now-SoakStarted);CompletedRouteRecords.Add(MakeShared<FJsonValueObject>(R));}
    WalkSegment=0;WalkRoute=(WalkRoute+1)%Routes.Num();++CompletedRoutes;CharacterRouteStarted=false;
   }
   CharacterBestDistance=1.e30;CharacterLastProgress=Now;return true;
  }
  if(Distance<CharacterBestDistance-5){CharacterBestDistance=Distance;CharacterLastProgress=Now;}
  if(Now-CharacterLastProgress>15)
  {
   Report->SetArrayField(TEXT("stalled_character_cm"),Coordinates(Location));
   Report->SetArrayField(TEXT("stalled_target_cm"),Coordinates(Target));
   Report->SetNumberField(TEXT("stalled_route"),WalkRoute);Report->SetNumberField(TEXT("stalled_segment"),WalkSegment);return false;
  }
  FVector Direction=Target-Location;Direction.Z=0;Direction.Normalize();
  PC->SetControlRotation(FRotator(-2,Direction.Rotation().Yaw,0));
  Pawn->AddMovementInput(Direction,1.f);
  return true;
 }
 bool Walk(UWorld* World,double Now)
 {
  const auto& Routes=Plan->GetArrayField(TEXT("walk_routes"));
  if(Routes.IsEmpty())return true;
  auto Route=Routes[WalkRoute]->AsObject();const auto& Points=Route->GetArrayField(TEXT("points"));
  const double Gap=FMath::Max(0.,Now-LastWalk);const bool CaptureWindow=Now-ImmersionLastImageAt<1.;++ImmersionFrameCount;ImmersionMaxFrameGap=FMath::Max(ImmersionMaxFrameGap,Gap);if(!CaptureWindow)ImmersionMaxUncapturedGap=FMath::Max(ImmersionMaxUncapturedGap,Gap);
  if(Gap>.1){++ImmersionSlowFrames;if(!CaptureWindow)++ImmersionUncapturedSlowFrames;if(ImmersionFrameHitches.Num()<40){auto H=MakeShared<FJsonObject>();H->SetNumberField(TEXT("elapsed_seconds"),Now-SoakStarted);H->SetNumberField(TEXT("gap_ms"),Gap*1000.);H->SetNumberField(TEXT("route"),WalkRoute);H->SetNumberField(TEXT("segment"),WalkSegment);H->SetBoolField(TEXT("capture_window"),CaptureWindow);ImmersionFrameHitches.Add(MakeShared<FJsonValueObject>(H));}}
  double Remaining=FMath::Clamp(Gap,0.,.5)*140.;LastWalk=Now;
  if(Walker.IsValid())return CharacterWalk(World,Now);
  while(Remaining>0)
  {
   auto Point=[&](int32 I){const auto& A=Points[I]->AsArray();return FVector(A[0]->AsNumber(),A[1]->AsNumber(),0);};
   const FVector A=Point(WalkSegment),B=Point(WalkSegment+1);const double Length=FVector::Distance(A,B);
   if(Length<.01||WalkDistance+Remaining>=Length)
   {
    Remaining=FMath::Max(0.,Remaining-FMath::Max(0.,Length-WalkDistance));WalkDistance=0;
    if(++WalkSegment>=Points.Num()-1){WalkSegment=0;WalkRoute=(WalkRoute+1)%Routes.Num();++CompletedRoutes;PreviousBodyValid=false;break;}
    continue;
   }
   WalkDistance+=Remaining;Remaining=0;const FVector XY=FMath::Lerp(A,B,float(WalkDistance/Length));
   FCollisionQueryParams Q(SCENE_QUERY_STAT(ImmersionWalk),true);if(Camera.IsValid())Q.AddIgnoredActor(Camera.Get());
   FHitResult Ground;if(!World->LineTraceSingleByChannel(Ground,XY+FVector(0,0,1380),XY+FVector(0,0,1100),ECC_Visibility,Q))return false;
   const FVector Body(XY.X,XY.Y,Ground.ImpactPoint.Z+98);FHitResult Hit;
   if(PreviousBodyValid&&World->SweepSingleByChannel(Hit,PreviousBody,Body,FQuat::Identity,ECC_Visibility,FCollisionShape::MakeCapsule(35,88),Q))
   {
    FHitResult Raised;
    if(Hit.ImpactPoint.Z>Ground.ImpactPoint.Z+20||World->SweepSingleByChannel(Raised,PreviousBody+FVector(0,0,20),Body+FVector(0,0,20),FQuat::Identity,ECC_Visibility,FCollisionShape::MakeCapsule(35,88),Q))return false;
    ++StepAssists;
   }
   PreviousBody=Body;PreviousBodyValid=true;
   if(Camera.IsValid())
   {
    const FVector Eye(XY.X,XY.Y,Ground.ImpactPoint.Z+165);Camera->SetActorLocation(Eye);
    FVector Direction=B-A;Direction.Z=-.03*Direction.Size2D();Camera->SetActorRotation(Direction.Rotation());
   }
  }
  return true;
 }
 bool Tick(float)
 {
  const double Now=FPlatformTime::Seconds();
  if(!ImmersionClockController.IsValid())
  {
   if(Now-Started>600)return Finish(TEXT("game_world_start_timeout"));
   if(!GEngine)return true;
   for(const FWorldContext& Context:GEngine->GetWorldContexts())
   {
    UWorld* W=Context.World();if(!W||!W->IsGameWorld()||!W->HasBegunPlay())continue;
    for(TActorIterator<ACityEnvironmentController> It(W);It;++It){ImmersionClockController=*It;break;}
   }
   if(!ImmersionClockController.IsValid())return true;
   auto C=ImmersionClockController.Get();C->SetPaused(true);ReadyAt=Now+2;
   Report->SetStringField(TEXT("world_type"),C->GetWorld()->WorldType==EWorldType::PIE?TEXT("PIE"):TEXT("Game"));
   if(!ResolveStems(C->GetWorld()))return Finish(TEXT("cooked_stem_component_contract_mismatch"));
   if(!ResolveStemRenderLinks(C->GetWorld()))return Finish(TEXT("cooked_visible_tree_proxy_alignment_mismatch"));
   Save(TEXT("running"));return true;
  }
  if(Now<ReadyAt)return true;
  if(Now-Started>SoakSeconds+900)return Finish(TEXT("immersion_audit_timeout"));
  auto C=ImmersionClockController.Get();UWorld* World=C->GetWorld();
  if(Plan->HasTypedField<EJson::Object>(TEXT("player_start"))&&!Report->HasField(TEXT("player_start_passed")))
  {
   auto PC=World->GetFirstPlayerController();auto Pawn=PC?Cast<ACityImmersionWalker>(PC->GetPawn()):nullptr;
   const auto Expected=Plan->GetObjectField(TEXT("player_start"));
   if(!Pawn||!World->GetAuthGameMode()||World->GetAuthGameMode()->GetClass()!=ACityImmersionGameMode::StaticClass())return Finish(TEXT("normal_gameplay_walker_missing"));
   const auto Capsule=Pawn->GetCapsuleComponent();
   if(FMath::Abs(Capsule->GetUnscaledCapsuleRadius()-35)>0.01||FMath::Abs(Capsule->GetUnscaledCapsuleHalfHeight()-88)>0.01||FVector::Dist2D(Pawn->GetActorLocation(),Vec(Expected,TEXT("location")))>5||!Pawn->GetCharacterMovement()->IsMovingOnGround())return Finish(TEXT("normal_gameplay_spawn_contract_mismatch"));
   Walker=Pawn;Pawn->SetAuditControlled(true);Pawn->GetCharacterMovement()->MaxWalkSpeed=140;
   Report->SetBoolField(TEXT("player_start_passed"),true);
   Report->SetArrayField(TEXT("actual_player_start_cm"),Coordinates(Pawn->GetActorLocation()));
   Report->SetStringField(TEXT("walking_scope"),TEXT("Actual ACharacter movement and blocking capsule within each route; teleport only between route starts. Automated movement input, not an OS keyboard test."));
  }
  if(Walker.IsValid()&&!Report->HasField(TEXT("normal_input_smoke_passed")))
  {
   const auto Input=PollCityImmersionInputAudit(Walker.Get(),C,Report,Now);
   if(Input==ECityImmersionInputAudit::Failed)return Finish(TEXT("normal_player_input_smoke_failed"));
   if(Input==ECityImmersionInputAudit::Pending)return true;
  }
  FCollisionQueryParams Query(SCENE_QUERY_STAT(ImmersionCookedAudit),true);
  const auto& Rays=Plan->GetArrayField(TEXT("rays"));
  for(int32 N=0;N<256&&RayIndex<Rays.Num();++N)
  {
   auto R=Rays[RayIndex]->AsObject();FHitResult H;const bool Blocked=World->LineTraceSingleByChannel(H,Vec(R,TEXT("start")),Vec(R,TEXT("end")),ECC_Visibility,Query);
   if(Blocked!=R->GetBoolField(TEXT("expected_hit")))return Finish(TEXT("cooked_interior_ray_mismatch"),HitDetail(R,H,Blocked));
   if(Blocked&&R->HasField(TEXT("expected_point"))&&FVector::Distance(H.ImpactPoint,Vec(R,TEXT("expected_point")))>1)return Finish(TEXT("cooked_interior_hit_position_mismatch"),HitDetail(R,H,Blocked));
   if(R->HasField(TEXT("pawn_simple_query"))&&R->GetBoolField(TEXT("pawn_simple_query")))
   {
    FCollisionQueryParams PlayerQuery(SCENE_QUERY_STAT(ImmersionPawnWindowAudit),false);
    if(Walker.IsValid())PlayerQuery.AddIgnoredActor(Walker.Get());
    FHitResult PlayerHit;const bool PlayerBlocked=World->LineTraceSingleByChannel(PlayerHit,Vec(R,TEXT("start")),Vec(R,TEXT("end")),ECC_Pawn,PlayerQuery);
    if(!PlayerBlocked||FVector::Distance(PlayerHit.ImpactPoint,Vec(R,TEXT("expected_point")))>1)return Finish(TEXT("cooked_window_pawn_collision_mismatch"),HitDetail(R,PlayerHit,PlayerBlocked));
    ++ImmersionPawnGlazingChecks;
   }
   ++RayIndex;
  }
  if(RayIndex<Rays.Num())return true;
  const auto& Floors=Plan->GetArrayField(TEXT("floors"));
  for(int32 N=0;N<256&&FloorIndex<Floors.Num();++N)
  {
   auto R=Floors[FloorIndex]->AsObject();FHitResult H;const bool Blocked=World->LineTraceSingleByChannel(H,Vec(R,TEXT("start")),Vec(R,TEXT("end")),ECC_Visibility,Query);
   if(!Blocked||H.ImpactPoint.Z<R->GetNumberField(TEXT("min_z"))||H.ImpactPoint.Z>R->GetNumberField(TEXT("max_z")))return Finish(TEXT("cooked_floor_support_mismatch"),HitDetail(R,H,Blocked));
   ++FloorIndex;
  }
  if(FloorIndex<Floors.Num())return true;
  const auto& Sweeps=Plan->GetArrayField(TEXT("sweeps"));
  for(int32 N=0;N<64&&SweepIndex<Sweeps.Num();++N)
  {
   auto R=Sweeps[SweepIndex]->AsObject();FHitResult H;const bool Blocked=World->SweepSingleByChannel(H,Vec(R,TEXT("start")),Vec(R,TEXT("end")),FQuat::Identity,ECC_Visibility,FCollisionShape::MakeCapsule(35,88),Query);
   if(Blocked)return Finish(TEXT("cooked_player_capsule_obstruction"),HitDetail(R,H,Blocked));++SweepIndex;
  }
  if(SweepIndex<Sweeps.Num())return true;
  const auto& Groups=Plan->GetArrayField(TEXT("stem_groups"));
  for(int32 N=0;N<128&&StemGroup<Groups.Num();++N)
  {
   auto Group=Groups[StemGroup]->AsObject();const auto& Targets=Group->GetArrayField(TEXT("targets"));
   if(StemIndex>=Targets.Num()){++StemGroup;StemIndex=0;--N;continue;}
   auto R=Targets[StemIndex]->AsObject();const FVector P=Vec(R,TEXT("center"));const double Radius=R->GetNumberField(TEXT("ray_radius"));bool Good=false;FCollisionQueryParams Simple(SCENE_QUERY_STAT(ImmersionStemAudit),false);
   for(const FVector& Offset:{FVector(Radius,0,0),FVector(0,Radius,0),FVector(-Radius,0,0),FVector(0,-Radius,0)})
   {
    FHitResult H;if(World->LineTraceSingleByChannel(H,P+Offset,P,ECC_Visibility,Simple)&&H.GetComponent()==StemComponents[StemGroup].Get()){Good=true;break;}
   }
   if(!Good)return Finish(TEXT("cooked_stem_physics_missing"),R);++StemIndex;++StemChecks;
  }
  if(StemGroup<Groups.Num())return true;
  const auto& Fixtures=Plan->GetArrayField(TEXT("fixture_positive_rays"));
  for(int32 N=0;N<64&&FixtureChecks<Fixtures.Num();++N)
  {
   auto R=Fixtures[FixtureChecks]->AsObject();const FString Key=R->GetStringField(TEXT("owner_object_name"))+TEXT("::")+R->GetStringField(TEXT("component_name"));
   auto Found=FixtureComponents.Find(Key);if(!Found||!Found->IsValid())return Finish(TEXT("cooked_fixture_component_missing"),R);auto MeshComponent=Found->Get();
   if(!MeshComponent->GetStaticMesh()||MeshComponent->GetStaticMesh()->GetPathName()!=R->GetStringField(TEXT("mesh"))||!MeshComponent->IsVisible()||MeshComponent->bHiddenInGame||MeshComponent->GetOwner()->IsHidden()||MeshComponent->GetCollisionProfileName()!=FName(TEXT("BlockAll"))||MeshComponent->GetCollisionResponseToChannel(ECC_Pawn)!=ECR_Block)return Finish(TEXT("cooked_fixture_contract_mismatch"),R);
   FCollisionQueryParams Simple(SCENE_QUERY_STAT(ImmersionFixtureAudit),false);FHitResult Hit;const bool Blocked=World->LineTraceSingleByChannel(Hit,Vec(R,TEXT("start")),Vec(R,TEXT("end")),ECC_Visibility,Simple);const int32 Instance=R->GetIntegerField(TEXT("instance"));
   if(!Blocked||Hit.GetComponent()!=MeshComponent||(Instance>=0&&Hit.Item!=Instance))return Finish(TEXT("cooked_visible_fixture_physics_missing"),HitDetail(R,Hit,Blocked));++FixtureChecks;
  }
  if(FixtureChecks<Fixtures.Num())return true;
  if(SoakSeconds<=0){Report->SetBoolField(TEXT("cooked_physics_passed"),true);return Finish();}
  if(SoakStarted<=0)
  {
   Report->SetBoolField(TEXT("cooked_physics_passed"),true);SoakStarted=Now;LastWalk=Now;
   C->SetDateTime(FDateTime(2026,10,26));C->SetTimeScale(24);C->SetPaused(false);
   if(Walker.IsValid()){if(auto PC=World->GetFirstPlayerController())PC->SetViewTarget(Walker.Get());}
   else{auto A=World->SpawnActor<ACameraActor>();Camera=A;A->GetCameraComponent()->SetFieldOfView(75);if(auto PC=World->GetFirstPlayerController())PC->SetViewTarget(A);}
   Save(TEXT("running"));return true;
  }
  if(!Walk(World,Now))return Finish(TEXT("native_soak_walk_obstructed"));
  const double Elapsed=Now-SoakStarted;
  if(Elapsed>=NextSample)
  {
   auto S=MakeShared<FJsonObject>();S->SetNumberField(TEXT("elapsed_seconds"),Elapsed);S->SetNumberField(TEXT("process_working_set_mb"),double(FPlatformMemory::GetStats().UsedPhysical)/(1024.*1024.));S->SetNumberField(TEXT("route"),WalkRoute);S->SetNumberField(TEXT("segment"),WalkSegment);
   TSharedPtr<FJsonObject> Clock;FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(C->GetStateJson()),Clock);if(Clock)S->SetObjectField(TEXT("clock"),Clock);
   Samples.Add(MakeShared<FJsonValueObject>(S));NextSample+=60;Save(TEXT("running"));
  }
  if(Elapsed>=NextImage&&Elapsed+2<SoakSeconds)
  {
   const FString Folder=FPaths::GetPath(ImmersionAuditOutputPath)/FPaths::GetBaseFilename(ImmersionAuditOutputPath);IFileManager::Get().MakeDirectory(*Folder,true);const FString Path=Folder/FString::Printf(TEXT("walk-%04d.png"),Images.Num());FScreenshotRequest::RequestScreenshot(Path,false,false);ImmersionLastImageAt=Now;auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("path"),Path);Row->SetNumberField(TEXT("request_elapsed_seconds"),Elapsed);Images.Add(MakeShared<FJsonValueObject>(Row));NextImage+=30;
  }
  if(Elapsed>=SoakSeconds)return Finish();return true;
 }
}
void StartCityEnvironmentImmersionAudit()
{
 if(!FParse::Value(FCommandLine::Get(),TEXT("CityImmersionAudit="),ImmersionAuditOutputPath)||ImmersionAuditOutputPath.IsEmpty())return;
 Started=FPlatformTime::Seconds();Report=MakeShared<FJsonObject>();
 FString Text;FParse::Value(FCommandLine::Get(),TEXT("CityImmersionPlan="),PlanPath);
 if(!FFileHelper::LoadFileToString(Text,*PlanPath)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Plan)){Finish(TEXT("missing_or_invalid_immersion_plan"));return;}
 for(const TCHAR* Key:{TEXT("rays"),TEXT("floors"),TEXT("sweeps"),TEXT("stem_groups"),TEXT("stem_render_links"),TEXT("fixture_positive_rays"),TEXT("walk_routes")})if(!Plan->HasTypedField<EJson::Array>(Key)){Finish(TEXT("invalid_immersion_plan_schema"));return;}
 FParse::Value(FCommandLine::Get(),TEXT("CityImmersionSoakSeconds="),SoakSeconds);SoakSeconds=FMath::Clamp(SoakSeconds,0.,7200.);
 Report->SetStringField(TEXT("supplied_plan_map_sha256"),Plan->GetStringField(TEXT("map_sha256")));Report->SetStringField(TEXT("plan_path"),PlanPath);Report->SetNumberField(TEXT("requested_soak_seconds"),SoakSeconds);Report->SetStringField(TEXT("scope"),TEXT("Opt-in actual Game-world interior rays, ground support, player capsules,visible fixtures and tree/proxy linkage. Optional1.4m/s route soak with24x clock; real CharacterMovement when player_start contract supplied,otherwise legacy camera/capsule replay. Launcher distinguishes uncooked source from immutable cooked package."));
 ImmersionTickerHandle=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&Tick));
}
void StopCityEnvironmentImmersionAudit()
{
 if(ImmersionTickerHandle.IsValid()){FTSTicker::GetCoreTicker().RemoveTicker(ImmersionTickerHandle);ImmersionTickerHandle.Reset();}
}
