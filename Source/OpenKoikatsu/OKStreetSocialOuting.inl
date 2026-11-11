// Street places (OKStreetSocialPlaces.h) and going to an activity together ("一起走過去").
bool OKStreetFixedBlock(const FOKStreetPlanBlock* B); // OKStreetSocialLife.inl
namespace{const TCHAR* OKPhoneDoingWord(const FString& Kind);} // OKStreetSocialPhoneInbox.inl
//
// An activity tied to a place starts with an outing: the player walks the planned route on autopilot and
// she follows with the shared-walk follow (StepCompanion). Free talk keeps working on the way
// (FreeTalkPartner includes OutingGirl). At the door the activity starts with the normal BeginPair /
// BeginPhoto / BeginFacility / BeginCompanion. Activities without a place start where the pair stands.
// When an activity ends both stay where they are, and talk resumes quietly if free talk was open.

// How long before a place opens they may walk to its door and wait there (the same hour a promise may meet there).
static constexpr int32 OKStreetDoorWaitMinutes=60;

// A place model component made static once its sections are in: the same triangles and materials built into a
// UStaticMesh at runtime (sections sharing a material become one), drawn by a static mesh component under it. A
// procedural mesh is drawn on the dynamic path, its sections gathered again every frame for every pass (base, depth,
// four shadow cascades): 39 models, 1.9 million triangles, the largest share of the render thread's frame. The
// procedural component stays, empty, as the node the layers hang from. Returns the component that draws (or the
// procedural one when the build fails). Each material slot gets UV density data: texture streaming asks for it, and left
// uninitialised it raised an ensure whose stack walk held the first frame 12 s.
static UPrimitiveComponent* OKStreetFreezePlaceMesh(AActor* Actor,UProceduralMeshComponent* Procedural,int32& Built){
 if(!Actor||!Procedural||Procedural->GetNumSections()==0)return Procedural;
 FMeshDescription Description=BuildMeshDescription(Procedural);
 TArray<FStaticMaterial> Materials;
 for(int32 I=0;I<Procedural->GetNumSections();++I){UMaterialInterface* M=Procedural->GetMaterial(I);if(!M)M=UMaterial::GetDefaultMaterial(MD_Surface);
  if(!Materials.ContainsByPredicate([M](const FStaticMaterial& S){return S.MaterialInterface==M;})){FStaticMaterial Slot(M,M->GetFName());Slot.UVChannelData=FMeshUVChannelInfo(1.f);Materials.Add(Slot);}}
 UStaticMesh* Mesh=NewObject<UStaticMesh>(Actor);
 Mesh->SetStaticMaterials(Materials);
 UStaticMesh::FBuildMeshDescriptionsParams Params;Params.bFastBuild=true;Params.bBuildSimpleCollision=false;Params.bAllowCpuAccess=false;Params.bMarkPackageDirty=false;
 if(!Mesh->BuildFromMeshDescriptions({&Description},Params)){UE_LOG(LogTemp,Warning,TEXT("Street places: %s stays procedural (static build failed)"),*Procedural->GetName());return Procedural;}
 auto* Static=NewObject<UStaticMeshComponent>(Actor,*(Procedural->GetName()+TEXT("Static")));
 Static->SetMobility(EComponentMobility::Movable);Static->SetCollisionEnabled(ECollisionEnabled::NoCollision);
 Static->SetLightingChannels(Procedural->LightingChannels.bChannel0,Procedural->LightingChannels.bChannel1,Procedural->LightingChannels.bChannel2);
 Static->SetStaticMesh(Mesh);
 for(int32 I=0;I<Materials.Num();++I)Static->SetMaterial(I,Materials[I].MaterialInterface);
 Static->SetupAttachment(Procedural);Static->RegisterComponent();
 Static->SetVisibility(Procedural->IsVisible());
 Procedural->ClearAllMeshSections();
 ++Built;
 return Static;
}

void AOKStreetSocialScene::SpawnStreetPlaces(){
 auto& S=*State;
 // The city's buildings and ground are in its map; only the elevators are the game's.
 if(OKStreetCityMode()){OKStreetRuntimeBlocks().Reset();SpawnElevators();return;}
 UStaticMesh* Meshes[]={LoadObject<UStaticMesh>(nullptr,TEXT("/Game/Scenes/StreetSocial/Meshes/StreetCube.StreetCube")),LoadObject<UStaticMesh>(nullptr,TEXT("/Game/Scenes/StreetSocial/Meshes/StreetSphere.StreetSphere")),LoadObject<UStaticMesh>(nullptr,TEXT("/Game/Scenes/StreetSocial/Meshes/StreetCylinder.StreetCylinder"))};
 if(!Meshes[0]){UE_LOG(LogTemp,Warning,TEXT("Street places: shared street meshes are missing"));return;}
 auto Spawn=[&](const FOKStreetPlacePart& Part){
  UStaticMesh* Mesh=Meshes[(int32)Part.Mesh]?Meshes[(int32)Part.Mesh]:Meshes[0];
  auto* Actor=GetWorld()->SpawnActor<AStaticMeshActor>(Part.Center,FRotator::ZeroRotator);if(!Actor)return;
  Actor->SetOwner(this);Actor->SetActorScale3D(Part.Size/100.f);auto* C=Actor->GetStaticMeshComponent();C->SetMobility(EComponentMobility::Movable);C->SetStaticMesh(Mesh);
  const int32 Index=(int32)Part.Material;const FString Path=FString::Printf(TEXT("/Game/Scenes/StreetSocial/Materials/StreetMaterial%02d.StreetMaterial%02d"),Index,Index);
  if(auto* Material=LoadObject<UMaterialInterface>(nullptr,*Path))C->SetMaterial(0,Material);
  C->SetCollisionEnabled(Part.Solid?ECollisionEnabled::QueryAndPhysics:ECollisionEnabled::NoCollision);
  S.PlaceActors.Add(Actor);
 };
 for(const auto& Ground:OKStreetPlaceGround())Spawn(Ground);
 int32 Parts=0,Models=0,Triangles=0,Frozen=0;
 // Model colours: the engine's BasicShapeMaterial tinted per section; without it, the nearest street material.
 UMaterialInterface* Tintable=LoadObject<UMaterialInterface>(nullptr,TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
 TMap<uint32,UMaterialInterface*> Tints;
 auto StreetMaterial=[](int32 Index){return LoadObject<UMaterialInterface>(nullptr,*FString::Printf(TEXT("/Game/Scenes/StreetSocial/Materials/StreetMaterial%02d.StreetMaterial%02d"),Index,Index));};
 // Solid footprints join the analytic obstacle test, so NPC route walking and the player check avoid them too.
 OKStreetRuntimeBlocks().Reset();
 for(int32 PlaceIndex=0;PlaceIndex<OKStreetPlaces().Num();++PlaceIndex){
  const auto& Place=OKStreetPlaces()[PlaceIndex];
  for(const auto& Part:Place.Parts){
   Spawn(Part);++Parts;
   if(Part.Hidden&&!S.PlaceActors.IsEmpty()&&S.PlaceActors.Last().IsValid())S.PlaceActors.Last()->SetActorHiddenInGame(true);
   if(Part.Solid)OKStreetRuntimeBlocks().Add(FBox(Part.Center-Part.Size*.5f,Part.Center+Part.Size*.5f));
  }
  if(!Place.Model)continue;
  auto* Actor=GetWorld()->SpawnActor<AActor>(AActor::StaticClass(),FTransform(FRotator(0,Place.Yaw,0),Place.Origin));if(!Actor)continue;
  Actor->SetOwner(this);
  auto* Mesh=NewObject<UProceduralMeshComponent>(Actor,TEXT("PlaceModel"));
  Mesh->SetMobility(EComponentMobility::Movable);Mesh->SetLightingChannels(true,true,false);Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);Mesh->bUseAsyncCooking=false;
  Actor->SetRootComponent(Mesh);Mesh->RegisterComponent();Actor->SetActorTransform(FTransform(FRotator(0,Place.Yaw,0),Place.Origin));
  const TArray<FLinearColor> NoColors;
  auto& PlaceLayers=S.PlaceRoofs.AddDefaulted_GetRef();PlaceLayers.Place=PlaceIndex;
  auto Layer=[&](const TCHAR* Name)->UProceduralMeshComponent*{auto* C=NewObject<UProceduralMeshComponent>(Actor,Name);C->SetMobility(EComponentMobility::Movable);C->SetCollisionEnabled(ECollisionEnabled::NoCollision);C->SetLightingChannels(true,true,false);C->SetupAttachment(Mesh);C->RegisterComponent();return C;};
  for(int32 I=0;I<Place.Model->Sections.Num();++I){
   const auto& Sec=Place.Model->Sections[I];
   // Ceiling, roof and rooftop props live on their own component, hidden while the player is in the room;
   // each floor of a multi-storey place too, hidden while he is on a floor below it.
   UProceduralMeshComponent* Target=Mesh;
   if(Sec.Roof&&!Place.Rooms.IsEmpty()){if(!PlaceLayers.Roof.IsValid())PlaceLayers.Roof=Layer(TEXT("PlaceRoof"));Target=Cast<UProceduralMeshComponent>(PlaceLayers.Roof.Get());}
   else if(Sec.Level>0&&!Place.Rooms.IsEmpty()){auto& Level=PlaceLayers.Levels.FindOrAdd(Sec.Level);if(!Level.IsValid())Level=Layer(*FString::Printf(TEXT("PlaceLevel%d"),Sec.Level));Target=Cast<UProceduralMeshComponent>(Level.Get());}
   // Without tangents every vertex gets +X, which is parallel to the normal of an X-facing wall: the shading
   // basis collapses and the wall renders black. Any direction across the normal will do (no normal maps).
   TArray<FProcMeshTangent> Tangents;Tangents.SetNum(Sec.Normals.Num());
   for(int32 V=0;V<Sec.Normals.Num();++V){const FVector N=Sec.Normals[V];const FVector Across=FMath::Abs(N.Z)<.9f?FVector::CrossProduct(FVector::UpVector,N):FVector::CrossProduct(FVector::ForwardVector,N);Tangents[V]=FProcMeshTangent(Across.GetSafeNormal(),false);}
   const int32 SectionIndex=Target->GetNumSections();
   Target->CreateMeshSection_LinearColor(SectionIndex,Sec.Positions,Sec.Indices,Sec.Normals,Sec.UV,NoColors,Tangents,false);
   Triangles+=Sec.Indices.Num()/3;
   UMaterialInterface* Material=nullptr;
   if(Tintable&&!Sec.UseStreetMaterial){
    const uint32 Key=GetTypeHash(Sec.Color.ToFColor(false));
    if(auto* Found=Tints.Find(Key))Material=*Found;
    else{auto* Tint=UMaterialInstanceDynamic::Create(Tintable,this);Tint->SetVectorParameterValue(TEXT("Color"),Sec.Color);Tints.Add(Key,Tint);Material=Tint;}
   }
   if(!Material)Material=StreetMaterial(Sec.StreetMaterial);
   if(Material)Target->SetMaterial(SectionIndex,Material);
  }
  // Every component of the model made static (the layers keep their own visibility switch: the roof, each floor).
  if(PlaceLayers.Roof.IsValid())PlaceLayers.Roof=OKStreetFreezePlaceMesh(Actor,Cast<UProceduralMeshComponent>(PlaceLayers.Roof.Get()),Frozen);
  for(auto& Level:PlaceLayers.Levels)if(Level.Value.IsValid())Level.Value=OKStreetFreezePlaceMesh(Actor,Cast<UProceduralMeshComponent>(Level.Value.Get()),Frozen);
  OKStreetFreezePlaceMesh(Actor,Mesh,Frozen);
  S.PlaceActors.Add(Actor);++Models;
 }
 // The street materials add a fixed share of their colour as ambient; the tinted model material has none and no
 // distance fields for GI, so shadowed walls would go black. Four low shadowless lights on lighting channel 1
 // (models only), one per axis since the models stand at quarter turns, stand in for that ambient (the street
 // materials' 0.22 x colour is about a quarter of full sun), scaled with the sun.
 if(Models>0){
  for(const float Yaw:{0.f,90.f,180.f,270.f}){
   auto* Fill=GetWorld()->SpawnActor<ADirectionalLight>(FVector::ZeroVector,FRotator(-12,Yaw,0));if(!Fill)continue;
   auto* L=Fill->GetLightComponent();L->SetMobility(EComponentMobility::Movable);L->SetCastShadows(false);L->SetLightingChannels(FParse::Param(FCommandLine::Get(),TEXT("StreetSocialFillAllChannels")),true,false);L->MarkRenderStateDirty();
   if(auto* D=Cast<UDirectionalLightComponent>(L)){D->SetAtmosphereSunLight(false);}
   L->SetIntensity(S.ClockDrivesSun&&S.Sun.IsValid()?FMath::Max(S.Sun->GetLightComponent()->Intensity*OKStreetPlaceFillShare,OKStreetPlaceFillNight):2.5f*OKStreetPlaceFillShare);
   Fill->SetOwner(this);S.PlaceActors.Add(Fill);S.PlaceFills.Add(Fill);
   UE_LOG(LogTemp,Display,TEXT("Street place fill light yaw=%.0f intensity=%.2f channels=%d%d%d"),Yaw,L->Intensity,L->LightingChannels.bChannel0,L->LightingChannels.bChannel1,L->LightingChannels.bChannel2);
  }
 }
 UE_LOG(LogTemp,Display,TEXT("Street places: %d places, %d parts, %d models (%d triangles, %d static meshes), tint material %s"),OKStreetPlaces().Num(),Parts,Models,Triangles,Frozen,Tintable?TEXT("found"):TEXT("missing"));
 SpawnElevators();
}

// Development: -StreetSocialPlaceTour=<dir> stands at every place's door (and inside walk-in places) once the
// street is ready, saves a screenshot of each (<dir>/<id>.png, <id>_inside.png), then runs a few activities with
// girl 1 (<dir>/<activity>.png) and quits.
void AOKStreetSocialScene::TickPlaceTour(double Now){
 auto& S=*State;if(S.PlaceTourDir.IsEmpty()||!S.AllReady)return;
 const auto& Places=OKStreetPlaces();
 struct FStep {int32 Place;bool Inside;const TCHAR* Activity;int32 Floor=0;};
 static TArray<FStep> Steps;
 if(Steps.IsEmpty()){
  for(int32 I=0;I<Places.Num();++I){
   Steps.Add({I,false,nullptr});
   const auto Lifts=OKStreetPlaceLifts(Places[I]);
   if(!Lifts.IsEmpty()){for(int32 F=1;F<=Lifts.Num();++F)Steps.Add({I,true,nullptr,F});}
   else if(!Places[I].Rooms.IsEmpty())Steps.Add({I,true,nullptr});
  }
  // Every activity that happens at a place anchor (the ones a place model lays out).
  for(const auto& A:OKStreetActivities())if(A.Anchor&&*A.Anchor&&A.Kind!=EOKStreetActivityKind::Facility)Steps.Add({INDEX_NONE,false,A.Id});
  if(FParse::Param(FCommandLine::Get(),TEXT("StreetSocialPlaceTourActivities"))){Steps.RemoveAll([](const FStep& X){return !X.Activity;});}
  FString Only;if(FParse::Value(FCommandLine::Get(),TEXT("StreetSocialPlaceTourOnly="),Only,false)){TArray<FString> Ids;Only.ParseIntoArray(Ids,TEXT(","));Steps.RemoveAll([&Ids](const FStep& X){return !X.Activity||!Ids.Contains(X.Activity);});}
 }
 if(S.PlaceTourIndex<0){S.PlaceTourIndex=0;S.PlaceTourAt=Now;S.PlaceTourShot=false;IFileManager::Get().MakeDirectory(*S.PlaceTourDir,true);}
 if(!Steps.IsValidIndex(S.PlaceTourIndex)){if(Now-S.PlaceTourAt>2)FPlatformMisc::RequestExitWithStatus(false,0);return;}
 const FStep& Step=Steps[S.PlaceTourIndex];
 auto Next=[&](){++S.PlaceTourIndex;S.PlaceTourShot=false;S.PlaceTourAt=Now;};
 if(Step.Activity){
  if(!S.PlaceTourShot){
   if(S.Pair.Partner!=INDEX_NONE)FinishPhoto();
   if(S.RestroomGirl!=INDEX_NONE)EndRestroom(false);
   if(S.SleepPhase!=0){S.SleepPhase=2;S.SleepAt=-1e9;TickSleep();} // wake from the previous step's night
   if(S.SoloGirl!=INDEX_NONE)EndSolo();
   FString Error;if(!StartOutingActivity(1,Step.Activity,Error)){UE_LOG(LogTemp,Warning,TEXT("Street place tour: %s failed: %s"),Step.Activity,*Error);Next();return;}
   S.PlaceTourShot=true;S.PlaceTourAt=Now;return;
  }
  if(((S.Pair.Partner!=INDEX_NONE&&S.Pair.Phase==1)||S.RestroomGirl!=INDEX_NONE||S.SleepPhase==2||S.SoloPhase==2)&&Now-S.PlaceTourAt>4){
   if(S.SoloPhase!=2||S.Pitch>-15){S.Pitch=S.SleepPhase==2?-60:-22;S.Distance=S.SleepPhase==2?420:480;}
   FScreenshotRequest::RequestScreenshot(S.PlaceTourDir/FString(Step.Activity)+TEXT(".png"),false,false);
   UE_LOG(LogTemp,Display,TEXT("Street place tour: activity %s at %s yaw=%.0f"),Step.Activity,*S.Male.ToCompactString(),S.Pair.Yaw);
   // Restroom check: step into the women's room; TickRestroom must put the player back outside.
   if(const FOKStreetActivity* Act=OKStreetFindActivity(Step.Activity);Act&&Act->Kind==EOKStreetActivityKind::Restroom)if(const FOKStreetPlace* Rest=OKStreetFindPlace(Act->Place))if(const auto* Women=OKStreetPlaceAnchor(*Rest,TEXT("women")))S.Male=Women->Position;
   Next();return; // the next step ends this pair: the screenshot is taken at the end of this frame
  }
  if(Now-S.PlaceTourAt>40){UE_LOG(LogTemp,Warning,TEXT("Street place tour: %s never started"),Step.Activity);Next();}
  return;
 }
 const auto& P=Places[Step.Place];
 const FVector Center=P.Model?P.Origin:P.Door;FVector Out=(P.Door-Center).GetSafeNormal2D();if(Out.IsNearlyZero())Out=FVector(1,0,0);
 if(Step.Inside){
  // Stand in the room (the roof hides) and look down into it from the door side.
  const auto Lifts=OKStreetPlaceLifts(P);
  const int32 RoomIndex=Step.Floor>0?P.RoomLevels.IndexOfByKey(Step.Floor):INDEX_NONE;
  S.Male=P.Rooms.IsValidIndex(RoomIndex)&&Lifts.IsValidIndex(Step.Floor-1)?FVector(P.Rooms[RoomIndex].GetCenter().X,P.Rooms[RoomIndex].GetCenter().Y,Lifts[Step.Floor-1]->Position.Z):P.Anchors.IsEmpty()?P.Rooms[0].GetCenter()*FVector(1,1,0):P.Anchors[0].Position;
  S.Yaw=(-Out).Rotation().Yaw+20;S.Pitch=-50;S.Distance=Step.Floor>0?1400:900;
 }
 else{S.Male=P.Door+Out*100;S.Yaw=(Center-S.Male).Rotation().Yaw+28;S.Pitch=-18;S.Distance=2000;}
 S.MouseUI=true;
 if(!S.PlaceTourShot&&Now-S.PlaceTourAt>3){
  const FString Shot=Step.Floor>0?FString::Printf(TEXT("%s_F%d.png"),P.Id,Step.Floor):FString(P.Id)+(Step.Inside?TEXT("_inside.png"):TEXT(".png"));
  FScreenshotRequest::RequestScreenshot(S.PlaceTourDir/Shot,false,false);S.PlaceTourShot=true;S.PlaceTourAt=Now;
  if(Step.Floor>0)UE_LOG(LogTemp,Display,TEXT("Street place tour: %s floor %d -> player floor %d"),P.Id,Step.Floor,OKStreetPlaceFloor(P,S.Male));
  // Walkable from the plaza? (the same planner an outing uses)
  if(!Step.Inside){const TArray<FVector> Route=PlaceRoute(FVector(0,500,0),P.Door);
   UE_LOG(LogTemp,Display,TEXT("Street place tour: %s door=%s rooms=%d anchors=%d route_points=%d"),P.Id,*P.Door.ToCompactString(),P.Rooms.Num(),P.Anchors.Num(),Route.Num());}
 }
 else if(S.PlaceTourShot&&Now-S.PlaceTourAt>1.5)Next();
}

// She comes back out of the women's room after a while; the player cannot walk into it.
void AOKStreetSocialScene::TickRestroom(){
 auto& S=*State;const double Now=SceneTime();
 if(S.RestroomGirl!=INDEX_NONE&&Now>=S.RestroomUntil)EndRestroom(true);
 for(const auto& Place:OKStreetPlaces()){
  const FOKStreetModelAnchor* Women=OKStreetPlaceAnchor(Place,TEXT("women"));
  const FOKStreetModelAnchor* Wait=OKStreetPlaceAnchor(Place,TEXT("wait"));
  if(!Women||!Wait)continue;
  for(const FBox& Room:Place.Rooms){
   const bool WomenRoom=Women->Position.X>=Room.Min.X&&Women->Position.X<=Room.Max.X&&Women->Position.Y>=Room.Min.Y&&Women->Position.Y<=Room.Max.Y;
   if(WomenRoom&&S.Male.X>=Room.Min.X&&S.Male.X<=Room.Max.X&&S.Male.Y>=Room.Min.Y&&S.Male.Y<=Room.Max.Y){
    S.Male=Wait->Position;
    if(Now-S.RestroomBlockedAt>3){S.RestroomBlockedAt=Now;S.Message=OKT(TEXT("ui.outing.ladies_room_no_men"));RefreshUI();UE_LOG(LogTemp,Display,TEXT("Street restroom: kept the player out of the women's room at %s"),Place.Id);}
   }
  }
 }
}

void AOKStreetSocialScene::EndRestroom(bool Returned){
 auto& S=*State;const int32 Girl=S.RestroomGirl;if(Girl==INDEX_NONE)return;S.RestroomGirl=INDEX_NONE;
 MindRemember(Girl,TEXT("restroom"),OKMsg(TEXT("ui.memory.restroom"),{{TEXT("place"),([&](const FString& Id){const FOKStreetPlace* P=OKStreetFindPlace(Id);return P?FString(P->Name):Id.IsEmpty()?FString(OKT(TEXT("ui.etiquette.street_location"))):Id;})(S.RestroomPlace)}}),S.RestroomPlace,0.05f);
 const FOKStreetPlace* Place=OKStreetFindPlace(S.RestroomPlace);
 const FOKStreetModelAnchor* Wait=Place?OKStreetPlaceAnchor(*Place,TEXT("wait")):nullptr;
 if(S.Agents.IsValidIndex(Girl-1)){
  auto& Agent=S.Agents[Girl-1];
  // Back out beside the player if he waited nearby, else at the door.
  const FVector Door=Wait?Wait->Position:Agent.Position;
  Agent.Position=FVector::Dist2D(S.Male,Door)<800?S.Male+FVector(0,120,0):Door;Agent.Held=false;Agent.Mode=EOKStreetMove::Walking;Agent.Stuck=0;
 }
 if(Returned){S.Message=OKMsg(TEXT("ui.outing.she_out_of_ladies_room"), {{TEXT("girl_name"), *S.Manifest.Characters[Girl].Name}});RefreshUI();ResumeTalkQuiet(Girl);}
 UE_LOG(LogTemp,Display,TEXT("Street restroom: actor=%d came out"),Girl);
}

// Elevator: the player (and the girl with him, if she is close) to the place's stop on that floor.
// The panel's floor buttons are the car's buttons: they work while he stands in that place's car.
void AOKStreetSocialScene::RideElevator(int32 PlaceIndex,int32 Floor){
 if(!State)return;const int32 Index=ElevatorOfPlace(PlaceIndex);if(Index==INDEX_NONE)return;
 if(!InElevatorCar(Index,State->Male)){State->Message=OKT(TEXT("ui.outing.enter_elevator_before_floor"));RefreshUI();return;}
 PressElevator(Index,Floor-1);
}
int32 AOKStreetSocialScene::ElevatorOfPlace(int32 PlaceIndex) const{
 if(!State)return INDEX_NONE;for(int32 I=0;I<State->Elevators.Num();++I)if(State->Elevators[I].Place==PlaceIndex)return I;
 // A place sharing another's shaft (SpawnElevators makes one car a shaft): that car.
 if(!OKStreetPlaces().IsValidIndex(PlaceIndex))return INDEX_NONE;
 const auto Lifts=OKStreetPlaceLifts(OKStreetPlaces()[PlaceIndex]);if(Lifts.Num()<2)return INDEX_NONE;
 const FVector Centre=Lifts[0]->Position-FRotator(0,Lifts[0]->Yaw,0).Vector()*160.f;
 for(int32 I=0;I<State->Elevators.Num();++I)if(FVector::Dist2D(State->Elevators[I].Centre,Centre)<10.f)return I;
 return INDEX_NONE;
}

bool AOKStreetSocialScene::NextDay(){
 auto& S=*State;
 // A day already begun before the clock was put back over it (the hour buttons): only its date comes back, it is not
 // begun twice (allowance, pay, the daily drift once a day; R3-225).
 if(S.DayRewound==S.Store.CalendarDay+1){++S.Store.CalendarDay;S.DayRewound=-1;UE_LOG(LogTemp,Display,TEXT("Street day: back to day %d (already begun)"),S.Store.CalendarDay);return true;}
 S.DayRewound=-1;
 MindEndOfDay();
 auto Candidate=S.Store;++Candidate.TopicDay;++Candidate.CalendarDay;
 Candidate.CalendarMinute=FMath::Clamp(FMath::FloorToInt32(OKStreetClockHours(S.ClockStartHours,FPlatformTime::Seconds()-S.ClockStartWall)*60.0),0,24*60-1);
 // The heroines' day (day.rs day_people): counters, the daily drift, a night's rest, favor and feelings made one, friends
 // after days of talking, a faded lover breaking up, his allowance and her income, bills, debts and paying him back.
 {auto Request=OKRulesRequest(TEXT("day_people"));Request->SetNumberField(TEXT("day"),Candidate.CalendarDay);Request->SetNumberField(TEXT("talk_budget"),S.Manifest.TalkBudget);Request->SetNumberField(TEXT("seed"),FMath::Rand());
  TArray<TSharedPtr<FJsonValue>> Heroines;auto Profiles=MakeShared<FJsonObject>();
  for(const auto& R:Candidate.Relations){auto H=MakeShared<FJsonObject>();H->SetObjectField(TEXT("relation"),OKRulesRelationJson(R));
   const int32 Girl=CharacterOf(R.Id);H->SetBoolField(TEXT("present"),Girl!=INDEX_NONE);
   if(Girl!=INDEX_NONE){H->SetStringField(TEXT("name"),S.Manifest.Characters[Girl].Name);H->SetNumberField(TEXT("favor_limit"),OKRulesFavorLimit(S,R,R.Stage));
    TSet<int64> Days;for(const auto& E:HistoryOf(R.Id))if(E.Kind==TEXT("talk")||E.Kind==TEXT("topic")||E.Kind==TEXT("touch")||OKStreetHistoryIsPhone(E.Kind))Days.Add(E.Minute/1440);H->SetNumberField(TEXT("talk_days"),Days.Num());}
   if(const TSharedPtr<FJsonObject> P=S.MindProfiles.FindRef(R.Id))Profiles->SetObjectField(R.Id,P.ToSharedRef());
   Heroines.Add(MakeShared<FJsonValueObject>(H));}
  Request->SetArrayField(TEXT("heroines"),Heroines);Request->SetObjectField(TEXT("profiles"),Profiles);
  const TSharedPtr<FJsonObject> Day=OKRulesEval(S,Request);if(!Day.IsValid())return false;
  ApplyRulesEffects(Candidate,*Day);
  for(auto& R:Candidate.Rumors)R.Heat*=float(Day->GetNumberField(TEXT("rumor_heat_factor")));}
 BankDaily(Candidate);
 // Bonds between heroines drift back a little each day (social.rs bond_heat_daily).
 {auto Request=OKRulesRequest(TEXT("bond_heat_daily"));TArray<TSharedPtr<FJsonValue>> Rows;
  for(const auto& Bond:Candidate.BondHeat)Rows.Add(MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueString>(Bond.Key),MakeShared<FJsonValueNumber>(Bond.Value)}));
  Request->SetArrayField(TEXT("bond_heat"),Rows);
  if(const TSharedPtr<FJsonObject> Out=OKRulesEval(S,Request))for(const auto& V:Out->GetArrayField(TEXT("bond_heat"))){const auto& P=V->AsArray();if(P.Num()==2)Candidate.BondHeat.Add(P[0]->AsString(),float(P[1]->AsNumber()));}}
 TickVentures(Candidate);
 CompanyDaily(Candidate); // buildings, morale, applicants (OKStreetSocialCompany.inl)
 S.Store=MoveTemp(Candidate);
 if(!S.SelfTest&&!S.Manifest.SavePath.IsEmpty())OKStreetAtomicSaveStoreAsync(S.Manifest.SavePath,S.Store);
 FlushRulesEffects();return true;
}

// Sleep: the player lies down on a bed (the facility sleeping clip) and the girl with him on the next bed, if any;
// after a short night the street clock jumps to 7:00 the next morning and the day advances.
bool AOKStreetSocialScene::StartSleep(const FOKStreetModelAnchor& Bed,const FOKStreetPlace* Place,int32 Girl,bool bNap){
 auto& S=*State;
 if(S.SleepPhase!=0)return false;
 // A nap (lying down together, a lap pillow) is the same pose for a little while; the clock does not jump.
 S.SleepNap=bNap;
 // Plan §13.3.2: sleeping through an appointment is not allowed; wake 30 minutes before is the limit.
 // Up at 07:00, or half an hour before a meeting that morning (SkipWakeMinute).
 {if(const FOKStreetAppointment* Next=bNap?nullptr:AppointmentBefore(SkipWakeMinute()-1)){S.Message=OKT(TEXT("ui.outing.promise_pending_no_sleep"))+Next->Label;RefreshUI();return false;}}
 if(S.Pair.Partner!=INDEX_NONE)FinishPhoto();
 if(S.Facility!=INDEX_NONE||S.PrivateGirl!=INDEX_NONE){S.Message=OKT(TEXT("ui.outing.cannot_sleep_now"));RefreshUI();return false;}
 {FString Why;if(Place&&FCString::Strcmp(Place->Id,TEXT("boys_dorm"))==0&&DormLocked(&Why)){S.Message=Why;RefreshUI();return false;}}
 StopAmbientActivity();EndTalk();if(S.Companion!=INDEX_NONE)FinishCompanion();
 // Sleeping over is an invitation like any other (plan §12.5): she joins only if she would accept it now.
 if(Girl>0&&S.Manifest.Characters.IsValidIndex(Girl)&&!bNap){FString Why;RollInviteStance(Girl);if(!InviteAllowed(Girl,TEXT("sleep_together"),Why)){S.FreeTalkNotice=OKT(TEXT("ui.outing.she_refuses_sleep_label"))+Why;Girl=INDEX_NONE;}}
 const bool Paired=Girl>0&&S.Agents.IsValidIndex(Girl-1);
 const TCHAR* Clip=Paired?TEXT("venue_soine_male.okanim"):TEXT("facility_sleep.okanim");FString Error;
 S.SleepPaired=Paired;
 S.SleepBed=Bed.Position;S.SleepYaw=Bed.Yaw;S.SleepPlace=Place?Place->Name:OKT(TEXT("ui.outing.here_label"));S.SleepGirl=INDEX_NONE;
 S.Male=Bed.Position;S.Rotations[0]=FRotator(0,Bed.Yaw,0);
 if(!OKPrewarmCrowdRuntimeAction(this,0,Clip,Error)){S.Message=OKT(TEXT("ui.outing.sleep_action_not_ready"))+Error;RefreshUI();return false;}
 // With her: the original side-by-side sleeping pair (soine), both from the same spot on the one bed.
 if(Paired){
  auto& Agent=S.Agents[Girl-1];Agent.Position=Bed.Position;Agent.Held=true;S.Rotations[Girl]=FRotator(0,Bed.Yaw,0);
  if(OKPrewarmCrowdRuntimeAction(this,Girl,TEXT("venue_soine_female.okanim"),Error)){S.SleepGirl=Girl;S.SleepGirlBed=Bed.Position;S.SleepGirlYaw=Bed.Yaw;}
  // The soine pair's root is not at the middle of the bodies: move both so they lie on the mattress.
  FVector Shift(OKStreetSoineShiftX,OKStreetSoineShiftY,0);FParse::Value(FCommandLine::Get(),TEXT("StreetSocialSoineShiftX="),Shift.X);FParse::Value(FCommandLine::Get(),TEXT("StreetSocialSoineShiftY="),Shift.Y);
  const FVector Moved=Bed.Position+FRotator(0,Bed.Yaw,0).RotateVector(Shift);S.SleepBed=Moved;S.Male=Moved;Agent.Position=Moved;S.SleepGirlBed=Moved;
 }
 float CamYaw=0;FParse::Value(FCommandLine::Get(),TEXT("StreetSocialSleepCamYaw="),CamYaw);S.SleepPhase=1;S.SleepAt=SceneTime();S.Yaw=Bed.Yaw+CamYaw;S.Pitch=-40;S.Distance=420;S.MouseUI=true;
 S.Message=bNap?OKMsg(TEXT("ui.outing.lying_down_with_her"), {{TEXT("sleep_place"), *S.SleepPlace}}):OKMsg(TEXT("ui.outing.lying_down_prepare_sleep"), {{TEXT("sleep_place"), *S.SleepPlace}});RefreshUI();
 if(S.SleepGirl!=INDEX_NONE)HeroineNote(S.SleepGirl,bNap?TEXT("nap_together"):TEXT("sleep_together"),OKMsg(TEXT("ui.outing.sleep_together_at"), {{TEXT("sleep_place"), *S.SleepPlace}}),Place?FString(Place->Id):FString(),-1.f,S.SleepPlace);
 if(S.SleepGirl!=INDEX_NONE&&!bNap)AddSecondSleeper(S.SleepGirl,Place,Bed.Name);
 UE_LOG(LogTemp,Display,TEXT("Street sleep: at %s (%s) with girl %d"),*S.SleepPlace,*Bed.Name,S.SleepGirl);
 return true;
}

void AOKStreetSocialScene::TickSleep(){
 auto& S=*State;if(S.SleepPhase==0)return;
 const double Now=SceneTime();const TCHAR* Clip=S.SleepPaired?TEXT("venue_soine_male.okanim"):TEXT("facility_sleep.okanim");const TCHAR* GirlClip=TEXT("venue_soine_female.okanim");
 S.Male=S.SleepBed;S.Rotations[0]=FRotator(0,S.SleepYaw,0);
 if(S.SleepGirl!=INDEX_NONE&&S.Agents.IsValidIndex(S.SleepGirl-1)){S.Agents[S.SleepGirl-1].Position=S.SleepGirlBed;S.Rotations[S.SleepGirl]=FRotator(0,S.SleepGirlYaw,0);}
 if(S.SleepPhase==1){
  FOKRuntimeActionStreamStatus A,B;
  const bool MaleReady=OKGetCrowdRuntimeActionStatus(this,0,A)&&A.Ready&&!A.Pending&&!A.Preparing&&A.ClipId==Clip;
  const bool GirlReady=S.SleepGirl==INDEX_NONE||(OKGetCrowdRuntimeActionStatus(this,S.SleepGirl,B)&&B.Ready&&!B.Pending&&!B.Preparing&&B.ClipId==GirlClip);
  if(MaleReady&&GirlReady){
   FString Error;OKPlayCrowdRuntimeAction(this,0,Clip,Error);if(S.SleepGirl!=INDEX_NONE)OKPlayCrowdRuntimeAction(this,S.SleepGirl,GirlClip,Error);
   if(S.SleepGirl2!=INDEX_NONE)OKPlayCrowdRuntimeAction(this,S.SleepGirl2,TEXT("facility_sleep.okanim"),Error);
   S.SleepPhase=2;S.SleepAt=Now;S.Message=TEXT("Zzz…");RefreshUI();
  }
  else if(Now-S.SleepAt>40)AbortSleep(OKT(TEXT("ui.outing.cannot_sleep_timeout"))); // everyone back as they were (Life.inl)
  return;
 }
 if(Now-S.SleepAt<(S.SleepNap?30.0:7.0)&&!(S.SleepNap&&S.SleepWake))return;
 S.SleepWake=false;
 if(S.SleepNap){
  // Up again where they lay down, the same day.
  FString Error;ResumeBehavior(0,Error);
  S.Male=S.SleepBed+FRotator(0,S.SleepYaw,0).RotateVector(FVector(110,0,0));S.Male.Z=OKStreetFloorZ(S.SleepBed);
  const int32 Girl=S.SleepGirl;S.SleepGirl=INDEX_NONE;S.SleepPhase=0;S.SleepNap=false;
  if(Girl!=INDEX_NONE&&S.Agents.IsValidIndex(Girl-1)){ResumeBehavior(Girl,Error);S.Agents[Girl-1].Position=S.Male+FRotator(0,S.SleepYaw,0).RotateVector(FVector(40,120,0));ResumeTalkQuiet(Girl);}
  S.Message=OKT(TEXT("ui.outing.rested_then_got_up"));RefreshUI();
  return;
 }
 // Morning: up at 7:00 the next day, standing beside the bed.
 FString Error;ResumeBehavior(0,Error);
 const FVector Side=FRotator(0,S.SleepYaw,0).RotateVector(FVector(110,0,0));
 S.Male=S.SleepBed+Side;S.Male.Z=OKStreetFloorZ(S.SleepBed);
 {const double Wake=double(SkipWakeMinute()%1440)/60.0;S.ClockStartHours=Wake;S.ClockStartWall=FPlatformTime::Seconds();S.NextSunUpdate=0;S.ClockDrivesSun=S.Sun.IsValid();S.CalendarLastHours=Wake;}
 NextDay();
 if(S.SleepGirl2!=INDEX_NONE&&S.Agents.IsValidIndex(S.SleepGirl2-1)){ResumeBehavior(S.SleepGirl2,Error);auto& Second=S.Agents[S.SleepGirl2-1];Second.Held=false;Second.Position=S.Male+FRotator(0,S.SleepYaw,0).RotateVector(FVector(-60,160,0));}
 S.SleepGirl2=INDEX_NONE;
 const int32 Girl=S.SleepGirl;S.SleepGirl=INDEX_NONE;S.SleepPhase=0;
 if(Girl!=INDEX_NONE&&S.Agents.IsValidIndex(Girl-1)){
  ResumeBehavior(Girl,Error);
  auto& Agent=S.Agents[Girl-1];Agent.Position=S.Male+FRotator(0,S.SleepYaw,0).RotateVector(FVector(40,120,0));
  ResumeTalkQuiet(Girl);
 }
 {const int64 Woke=OKStreetMindNow(S)%1440;S.Message=OKMsg(TEXT("ui.outing.slept_until_morning"),{{TEXT("hour"),int32(Woke/60)},{TEXT("minute"),int32(Woke%60)}});}RefreshUI(); // the hour it really is (earlier for an early date)
 UE_LOG(LogTemp,Display,TEXT("Street sleep: woke up the next morning"));
}

void AOKStreetSocialScene::TickSolo(){
 auto& S=*State;if(S.SoloGirl==INDEX_NONE)return;const int32 Girl=S.SoloGirl;
 if(!S.Agents.IsValidIndex(Girl-1)){EndSolo();return;}
 const FRotator Facing(0,S.SoloYaw,0);
 // Still getting ready: where he ends up after being set down (pushed out of a vending machine by 151 cm) is the spot.
 if(S.SoloPhase==1)S.SoloSpot=S.Male;
 // Where she was put beside him at the start (behind his side, settled off the omikuji stand): kept, not put back level
 // with him 110 cm aside, which stood her inside the shrine's stands and the haunted house (activity audit 11-11).
 S.Agents[Girl-1].Position=S.SoloSpot+(S.SoloHerOffset.IsNearlyZero()?Facing.RotateVector(FVector(0,110,0)):S.SoloHerOffset);S.Rotations[Girl]=Facing;
 // He walks away: done (with his own clip playing, any step away ends it).
 // Walking off, not the nudge he gets when he is set down on the spot (a 60 cm push-out ended the stretch 0.12 s in).
 if(FVector::Dist2D(S.Male,S.SoloSpot)>(S.SoloMale.IsEmpty()?320.f:150.f)){UE_LOG(LogTemp,Display,TEXT("Street solo: %s ends, he is %.0f from the spot (%s, spot %s, phase %d, %.2f s in)"),*S.SoloWhat,FVector::Dist2D(S.Male,S.SoloSpot),*S.Male.ToCompactString(),*S.SoloSpot.ToCompactString(),S.SoloPhase,SceneTime()-S.SoloAt);EndSolo();return;}
 // Its time is up (game minutes): done by itself.
 if(S.SoloPhase==2&&OKStreetMindNow(S)-S.SoloStartMinute>=S.SoloMinutes){UE_LOG(LogTemp,Display,TEXT("Street solo: %s done after %d min"),*S.SoloWhat,S.SoloMinutes);EndSolo();return;}
 if(S.SoloPhase==1){
  FOKRuntimeActionStreamStatus A,B;
  const bool GirlReady=OKGetCrowdRuntimeActionStatus(this,Girl,A)&&A.Ready&&!A.Pending&&!A.Preparing&&A.ClipId==S.SoloFemale;
  const bool MaleReady=S.SoloMale.IsEmpty()||(OKGetCrowdRuntimeActionStatus(this,0,B)&&B.Ready&&!B.Pending&&!B.Preparing&&B.ClipId==S.SoloMale);
  if(GirlReady&&MaleReady){FString Error;OKPlayCrowdRuntimeAction(this,Girl,S.SoloFemale,Error);if(!S.SoloMale.IsEmpty())OKPlayCrowdRuntimeAction(this,0,S.SoloMale,Error);S.SoloPhase=2;}
  else if(SceneTime()-S.SoloAt>40){UE_LOG(LogTemp,Warning,TEXT("Street solo: clip never got ready"));EndSolo();}
 }
}

void AOKStreetSocialScene::EndSolo(){
 auto& S=*State;const int32 Girl=S.SoloGirl;if(Girl==INDEX_NONE)return;S.SoloGirl=INDEX_NONE;S.SoloPhase=0;
 // Ended before its time (he spoke to her, another activity took over): settled for the minutes it lasted, not its
 // whole length. Watching the fish two minutes and then sitting on the bench put the clock 18 minutes on (R3-112).
 if(S.ActGirl==Girl&&OKStreetMindNow(S)-S.SoloStartMinute<S.SoloMinutes)S.ActCutShort=true;
 FString Error;ResumeBehavior(Girl,Error);if(!S.SoloMale.IsEmpty())ResumeBehavior(0,Error);
 if(S.Agents.IsValidIndex(Girl-1)){auto& Agent=S.Agents[Girl-1];Agent.Held=false;Agent.Mode=EOKStreetMove::Walking;Agent.Stuck=0;}
 S.Message=OKMsg(TEXT("ui.outing.solo_activity_ended"), {{TEXT("solo_activity"), *S.SoloWhat}});RefreshUI();ResumeTalkQuiet(Girl);
}


void AOKStreetSocialScene::DestroyStreetPlaces(){
 if(!State)return;State->PlaceRoofs.Reset();
 for(auto& Actor:State->PlaceActors)if(Actor.IsValid())Actor->Destroy();
 State->PlaceActors.Reset();
 DestroyElevators();
 OKStreetRuntimeBlocks().Reset();
 State->NavGrid.Reset();State->NavGround.Reset();
}

// Like ContactRoute, over the shared waypoints plus the place corridor and doors.
TArray<FVector> AOKStreetSocialScene::PlaceRoute(const FVector& From,const FVector& To) const{QUICK_SCOPE_CYCLE_COUNTER(STAT_Street_PlaceRoute);
 if(FMath::Abs(From.Z-To.Z)<150.f&&!OKStreetCityFar(From,To)){auto Grid=GridRoute(From,To);if(Grid.Num()>=2)return Grid;}
 return PlaceRouteWaypoints(From,To);
}
TArray<FVector> AOKStreetSocialScene::PlaceRouteWaypoints(const FVector& From,const FVector& To) const{QUICK_SCOPE_CYCLE_COUNTER(STAT_Street_PlaceRouteWaypoints);
 if(OKStreetCityMode())return CityRoute(From,To);
 TArray<FOKStreetPointData> Shared;OKStreetWaypoints(Shared);TArray<FVector> Points;for(const auto& P:Shared)Points.Add(P.Position);
 Points.Append(OKStreetPlaceRoutePoints());
 return OKStreetContactRoute(From,To,Points,[&](const FVector& A,const FVector& B){
  const int32 Steps=FMath::Max(1,FMath::CeilToInt(FVector::Dist2D(A,B)/25));
  for(int32 I=0;I<=Steps;++I)if(OKStreetBlockedPoint(FMath::Lerp(A,B,float(I)/Steps),30))return false;
  FHitResult Hit;FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetPlaceRoute),false,this);
  return !GetWorld()->SweepSingleByChannel(Hit,A+FVector(0,0,85),B+FVector(0,0,85),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(30,78),Query);
 });
}

// Places within `Radius` of the player, nearest first.
TArray<const FOKStreetPlace*> AOKStreetSocialScene::NearbyPlaces(float Radius) const{
 TArray<const FOKStreetPlace*> Out;
 for(const auto& P:OKStreetPlaces())if(FVector::Dist2D(State->Male,P.Door)<=Radius)Out.Add(&P);
 Out.Sort([this](const FOKStreetPlace& A,const FOKStreetPlace& B){return FVector::Dist2D(State->Male,A.Door)<FVector::Dist2D(State->Male,B.Door);});
 return Out;
}

// Where a walk to a building ends: through its door and a few steps into its ground-floor room (a shop's counter side),
// or the door when it has no rooms.
FVector AOKStreetSocialScene::PlaceInsideSpot(const FOKStreetPlace& Place) const{
 // Open air: its spot nearest the door that counts as this place. 1.8 m from the door towards its box's middle was the
 // shrine's in the park (the park's box holds the shrine), the BBQ area's in the playground, the fishing spot's over the
 // pond and the jet-ski's in the water (places_check 11-09).
 if(Place.Outdoor){const FOKStreetModelAnchor* Near=nullptr;double NearD=FMath::Square(2500.0);
  for(const auto& A:Place.Anchors){if(A.Name.StartsWith(TEXT("lift"))||A.Name.StartsWith(TEXT("stair"))||A.Name.StartsWith(TEXT("gate"))||FMath::Abs(A.Position.Z-Place.Door.Z)>150.f)continue;
   const double D=FVector::DistSquared2D(A.Position,Place.Door);if(D<NearD&&PlaceHere(A.Position)==Place.Id){NearD=D;Near=&A;}}
  if(Near)return Near->Position;}
 const FBox* Ground=nullptr;float Best=1e12f;
 for(int32 R=0;R<Place.Rooms.Num();++R)if(!Place.RoomLevels.IsValidIndex(R)||Place.RoomLevels[R]<=1){const float D=Place.Rooms[R].ComputeSquaredDistanceToPoint(FVector(Place.Door.X,Place.Door.Y,Place.Rooms[R].GetCenter().Z));if(D<Best){Best=D;Ground=&Place.Rooms[R];}}
 if(!Ground)return Place.Door;
 FVector In=Ground->GetClosestPointTo(FVector(Place.Door.X,Place.Door.Y,Ground->GetCenter().Z));
 FVector ToCenter=Ground->GetCenter()-In;ToCenter.Z=0;const float Room=ToCenter.Size();
 if(Room>1.f)In+=ToCenter/Room*FMath::Min(180.f,Room*.5f);
 In.Z=Place.Door.Z;
 return OKStreetInsidePlace(Place,In)?In:Place.Door;
}

// What the rules need to say whether an activity can be done now: her, the weather, the bags, what they did today.
TSharedRef<FJsonObject> AOKStreetSocialScene::ActivityContext(int32 Girl,const TCHAR* Rule) const{
 const auto& S=*State;auto R=OKRulesRequest(Rule);
 if(S.Manifest.Characters.IsValidIndex(Girl)){auto G=MakeShared<FJsonObject>();G->SetStringField(TEXT("id"),OKStreetStableId(S.Manifest.Characters[Girl]));
  TArray<TSharedPtr<FJsonValue>> Names{MakeShared<FJsonValueString>(S.Manifest.Characters[Girl].Name)};G->SetArrayField(TEXT("names"),Names);R->SetObjectField(TEXT("girl"),G);
  // Her profile: an activity may be hers only when it names a field of it (help_her_work: occupation.side_task).
  if(const TSharedPtr<FJsonObject> Profile=S.MindProfiles.FindRef(OKStreetStableId(S.Manifest.Characters[Girl])))R->SetObjectField(TEXT("profile"),Profile);}
 const int64 Now=OKStreetMindNow(S);R->SetBoolField(TEXT("raining"),RainingAt(S.Store.CalendarDay,int32(Now%1440)));R->SetNumberField(TEXT("day"),S.Store.CalendarDay); // festival-only activities (events.toml)
 TArray<TSharedPtr<FJsonValue>> His;for(const FString& I:S.Store.Inventory)His.Add(MakeShared<FJsonValueString>(I));
 // What they ordered here counts too, made or still being made: 三月七 ordered the fish food and paid for it, and the
 // feeding that started before it came had him buy another bag (R4-16).
 TArray<TSharedPtr<FJsonValue>> Hers;
 for(const FOKStreetDish& D:S.Table)if(D.Percent>0.f){if(!D.ForHer)His.Add(MakeShared<FJsonValueString>(D.ItemId));else if(D.Her==INDEX_NONE||D.Her==Girl)Hers.Add(MakeShared<FJsonValueString>(D.ItemId));}
 // And what is in the basket waiting for who pays: 惠惠 said she would buy the fish food, the feeding started while the
 // checkout was still open, and he bought a second bag.
 for(const FOKStreetCartLine& L:S.Cart){if(!L.ForHer)His.Add(MakeShared<FJsonValueString>(L.ItemId));else if(L.Girl==INDEX_NONE||L.Girl==Girl)Hers.Add(MakeShared<FJsonValueString>(L.ItemId));}
 R->SetArrayField(TEXT("his_items"),His);R->SetArrayField(TEXT("her_items"),Hers);
 OKRulesPutExt(S,R); // what she bought for herself (activities.rs reads her things from it)
 TArray<TSharedPtr<FJsonValue>> Done;if(S.ActivitiesDoneDay==Now/1440)if(const auto* D=S.ActivitiesDone.Find(Girl))for(const FString& I:*D)Done.Add(MakeShared<FJsonValueString>(I));R->SetArrayField(TEXT("done_today"),Done);
 auto Names=MakeShared<FJsonObject>();for(const auto& P:OKStreetPlaces())Names->SetStringField(P.Id,P.Name);R->SetObjectField(TEXT("place_names"),Names);
 return R;
}

bool AOKStreetSocialScene::ActivityCheck(int32 Girl,const FString& ActivityId,FString& Why,bool bConsume,bool bAtEnd){
 auto& S=*State;auto Request=ActivityContext(Girl,TEXT("activity_check"));Request->SetStringField(TEXT("id"),ActivityId);Request->SetBoolField(TEXT("at_end"),bAtEnd);
 Request->SetStringField(TEXT("here"),PlaceHere(S.Male));Request->SetNumberField(TEXT("player_cash"),double(S.Store.PlayerCash));
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer.IsValid())return true;
 if(!Answer->GetBoolField(TEXT("ok"))){Why=Answer->GetStringField(TEXT("why"));UE_LOG(LogTemp,Display,TEXT("Street activity check: %s refused (%s: %s)"),*ActivityId,*Answer->GetStringField(TEXT("reason")),*Why);return false;}
 // What it needs and is sold right here he bought on the spot (activities.rs check: buy, effects).
 const TArray<TSharedPtr<FJsonValue>>* Buy=nullptr;
 if(!bAtEnd&&Answer->TryGetArrayField(TEXT("buy"),Buy)&&Buy->Num()){auto Candidate=S.Store;
  for(const auto& V:*Buy){Candidate.Inventory.Add(V->AsObject()->GetStringField(TEXT("item")));UE_LOG(LogTemp,Display,TEXT("Street activity check: %s, bought %s here"),*ActivityId,*V->AsObject()->GetStringField(TEXT("name")));}
  ApplyRulesEffects(Candidate,*Answer);if(CommitStore(MoveTemp(Candidate)))FlushRulesEffects();}
 if(bConsume){const TArray<TSharedPtr<FJsonValue>>* Consume=nullptr;
  if(Answer->TryGetArrayField(TEXT("consume"),Consume)&&Consume->Num()){auto Candidate=S.Store;
   for(const auto& V:*Consume){const auto O=V->AsObject();const FString Item=O->GetStringField(TEXT("item"));const bool FromHis=O->GetStringField(TEXT("from"))==TEXT("his");
    // From his bag, else the one they ordered here (ActivityContext lists both): used up, it leaves the table.
    if(!(FromHis&&Candidate.Inventory.RemoveSingle(Item)>0)){const int32 K=S.Table.IndexOfByPredicate([&](const FOKStreetDish& D){return D.ItemId==Item&&D.ForHer!=FromHis&&D.Percent>0.f;});if(K!=INDEX_NONE)S.Table.RemoveAt(K);}
    UE_LOG(LogTemp,Display,TEXT("Street activity check: %s uses %s (%s)"),*ActivityId,*O->GetStringField(TEXT("item")),*O->GetStringField(TEXT("from")));}
   if(Answer->HasField(TEXT("ext")))OKRulesTakeExt(Candidate,*Answer); // hers used up, out of her things
   CommitStore(MoveTemp(Candidate));}}
 return true;
}

// For her words (the scene line): what of this place's activities, or those done where they stand, cannot be done now
// and why ("寫生（下雨了）"), so she does not offer it; she says it in her own way if he asks for it.
FString AOKStreetSocialScene::ActivityBlockedLine(int32 Character) const{
 const auto& S=*State;auto Request=ActivityContext(Character,TEXT("activity_blocked"));Request->SetStringField(TEXT("place"),PlaceHere(S.Male));
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer.IsValid())return FString();
 TArray<FString> Parts;for(const auto& V:Answer->GetArrayField(TEXT("blocked"))){const auto O=V->AsObject();Parts.Add(OKMsg(TEXT("ui.mind.blocked_activity_entry"),{{TEXT("name"),O->GetStringField(TEXT("name"))},{TEXT("why"),O->GetStringField(TEXT("why"))}}));}
 FString Line=Parts.IsEmpty()?FString():OKT(TEXT("ui.mind.blocked_activities_label"))+FString::Join(Parts,OKT(TEXT("ui.bank.list_separator")));
 // And what this place offers now, by id: in the park the standing practice is the park's (park_exercise), not the
 // playground's stretching both of them had picked (activities.rs activities_here).
 Request->SetStringField(TEXT("rule"),TEXT("activities_here"));
 if(const TSharedPtr<FJsonObject> Here=OKRulesEval(S,Request)){TArray<FString> Ids;for(const auto& V:Here->GetArrayField(TEXT("here"))){const auto O=V->AsObject();Ids.Add(OKMsg(TEXT("ui.mind.here_activity_entry"),{{TEXT("id"),O->GetStringField(TEXT("id"))},{TEXT("name"),O->GetStringField(TEXT("name"))}}));}
  if(!Ids.IsEmpty())Line=OKT(TEXT("ui.mind.here_activities_label"))+FString::Join(Ids,OKT(TEXT("ui.bank.list_separator")))+Line;}
 return Line;
}

bool AOKStreetSocialScene::BeginOuting(int32 Girl,const FString& ActivityId,FString& Error){
 if(!State)return false;auto& S=*State;
 // Already on the way there with her ("eat" said on the way to the cafeteria meal they set off for): the walk goes on,
 // not cancelled and started over.
 if(S.OutingGirl==Girl&&S.OutingActivity==ActivityId){UE_LOG(LogTemp,Display,TEXT("Street outing: already on the way to %s with actor %d"),*ActivityId,Girl);return true;}
 const FOKStreetActivity* Activity=OKStreetFindActivity(ActivityId);
 // Out of reach now (raining for the sketching, no fish food, someone else's thing, done today): not set off at all.
 if(Activity&&!ActivityCheck(Girl,ActivityId,Error,false))return false;
 // The model sometimes answers a bare place id ("petshop") instead of "go:petshop": treat it as going there.
 const FOKStreetPlace* Place=ActivityId.StartsWith(TEXT("go:"))?OKStreetFindPlace(ActivityId.Mid(3)):Activity?OKStreetFindPlace(Activity->Place):OKStreetFindPlace(ActivityId);
 const bool Leave=ActivityId==TEXT("leave");
 const bool Stroll=ActivityId==TEXT("stroll")||ActivityId==TEXT("walk"); // a walk with no destination: a loop nearby
 if(!Activity&&!Place&&!Leave&&!Stroll){Error=OKT(TEXT("ui.outing.no_such_activity_place"));return false;}
 // On his shift he works: not off somewhere with her, and not sat down at a table of his own shop with her (the barista
 // sat with Raiden for her latte). She is served; they talk at the counter.
 if(S.ShiftAppointment&&!Leave){Error=OKT(TEXT("ui.jobs.on_shift_no_outing"));UE_LOG(LogTemp,Display,TEXT("Street outing: %s not started, he is on shift"),*ActivityId);return false;}
 // Closed when they get there and still a quarter of an hour after (it opens at 11:00, they set off at 10:39 with twenty
 // minutes to walk: open by then), or open then but closing within a quarter of an hour (Raiden and he set off for
 // dinner at 21:39, walked in at 21:59 and the restaurant closed on their dishes). The walk at the outing's pace
 // (OKStreetOutingWalkMPerMin, the way 1.3 times the straight line).
 if(Place&&!Leave){FString Why;int32 Days=0;if(Blacklisted(Place->Id,&Days)){Error=OKMsg(TEXT("ui.outing.blacklisted_days_left"), {{TEXT("days"), Days}});return false;}
  const float WalkMinutes=OKStreetInsidePlace(*Place,S.Male)?0.f:FVector::Dist2D(S.Male,Place->Door)/100.f*1.3f/OKStreetOutingWalkMPerMin;
  const FDateTime Arrive=StreetNow()+FTimespan::FromMinutes(WalkMinutes);
  const bool ClosedThen=PlaceClosedAt(Place->Id,Arrive,Why);FString After;const bool ClosedAfter=PlaceClosedAt(Place->Id,Arrive+FTimespan::FromMinutes(15),After);
  // Only walking to it (go:, nothing to do there yet) to wait at its door: an hour before it opens is as good a place to
  // be as the meeting point a promise may name there (R3-253c). Jeanne Alter and he were told "closed" at 10:19 for the
  // department store opening at 11 they had met in front of (R5-8).
  FString Later;const bool DoorWait=ActivityId.StartsWith(TEXT("go:"))&&ClosedThen&&!Place->Rooms.IsEmpty()&&!PlaceClosedAt(Place->Id,Arrive+FTimespan::FromMinutes(OKStreetDoorWaitMinutes),Later);
  if(DoorWait){UE_LOG(LogTemp,Display,TEXT("Street outing: %s not open on arrival but within the hour; they go and wait at its door"),*ActivityId);}
  else if(ClosedThen&&ClosedAfter){Error=Why;return false;}
  if(!ClosedThen&&ClosedAfter){
   Error=OKMsg(TEXT("ui.outing.closes_before_arrival"),{{TEXT("place"),Place->Name},{TEXT("minutes"),FMath::CeilToInt(WalkMinutes)},{TEXT("why"),After}});
   UE_LOG(LogTemp,Display,TEXT("Street outing: %s not started, %s closes before they could be there and stay (walk %.0f min)"),*ActivityId,Place->Id,WalkMinutes);return false;}}
 if(!S.Manifest.Characters.IsValidIndex(Girl)||!S.Agents.IsValidIndex(Girl-1)){Error=OKT(TEXT("ui.outing.cannot_find_her"));return false;}
 // What they ordered here is still being made: not off somewhere else before it comes (leaving clears the table).
 // Sitting down here to wait for it is not leaving (cafe_seat in the cafe where the latte is being made).
 const bool StaysHere=Place&&OKStreetInsidePlace(*Place,S.Male);
 // Only his own dishes and hers: another girl's latte she ordered and pays for herself kept him from going to the
 // shrine with Jeanne (R3-124).
 if(!Leave&&!StaysHere&&S.Table.ContainsByPredicate([Girl](const FOKStreetDish& D){return !D.Served&&(!D.ForHer||D.Her==INDEX_NONE||D.Her==Girl);})){Error=OKT(TEXT("ui.outing.wait_for_order"));UE_LOG(LogTemp,Display,TEXT("Street outing: waits, the order is still being made"));return false;}
 // Free talk can end the activity she is in ("leave"), or go somewhere else, which ends it first.
 // Either way both stay where the activity ended (a room returns them to its door).
 // Ended here by their own words, so it lasted the minutes that went by: leaving the moon viewing three minutes in put
 // the clock on to its full hour and past her dorm's curfew (R3-117). A meal or a drink keeps its own reckoning (the
 // menu bill at the end).
 if(S.ActGirl==Girl&&!(S.Pair.Partner==Girl&&(S.Pair.Meal||S.Pair.Drink)))S.ActCutShort=true;
 if(S.Facility!=INDEX_NONE&&S.FacilityCharacter==Girl)FinishFacility();
 if(S.Pair.Partner==Girl)FinishPhoto();
 if(S.RestroomGirl==Girl)EndRestroom(false);
 if(S.SoloGirl==Girl){UE_LOG(LogTemp,Display,TEXT("Street solo: %s ends, a new outing (%s) begins"),*S.SoloWhat,*ActivityId);EndSolo();}
 if(Leave){
  // Her "let's go" answered the table eaten clean, asked before the walk they agreed on began that same moment: it is
  // that walk, not a stop to it (R3-250: the walk to her class ended 2 s in, on the department store's 9F).
  if(S.OutingGirl==Girl&&S.OutingBegunAt>S.FreeTalkSentAt){UE_LOG(LogTemp,Display,TEXT("Street free talk: actor=%d's leave was asked before %s began; the outing goes on"),Girl,*S.OutingActivity);return true;}
  if(S.OutingGirl==Girl)CancelOuting(FString());
  if(S.Companion==Girl)FinishCompanion();
  if(S.Pair.Partner==Girl){Error=OKT(TEXT("ui.outing.wait_activity_wrapup"));return false;}
  S.Message=OKT(TEXT("ui.outing.activity_ended_stay"));ResumeTalkQuiet(Girl);RefreshUI();
  UE_LOG(LogTemp,Display,TEXT("Street free talk: actor=%d left the activity"),Girl);
  return true;
 }
 if(S.Pair.Partner!=INDEX_NONE||S.Facility!=INDEX_NONE||S.PrivateGirl!=INDEX_NONE){Error=OKT(TEXT("ui.outing.other_activity_ongoing"));return false;}
 if(OKStreetConversationBusy(S.Node!=INDEX_NONE,S.CollectedActive,S.RelationshipPending,S.TouchActive)){Error=OKT(TEXT("ui.outing.wait_she_finish_speaking"));return false;}
 // The one he is talking with is beside him as far as their talk goes: 惠惠, 4.9 m off in their open talk, agreed to
 // lunch and was told she was not with him; she asked where he had walked off to (R6-154).
 if(FVector::Dist2D(S.Male,S.Agents[Girl-1].Position)>(FreeTalkPartner()==Girl?800.f:400.f)){Error=OKT(TEXT("ui.outing.she_not_beside_you"));return false;}
 // He walks with her now: where the navigation was taking him is over (met on the way to the park, it resumed after
 // the walk to the sports ground and pulled him off her stretching spot 3 s in).
 if(S.NavGirl!=INDEX_NONE||S.NavPointActive){UE_LOG(LogTemp,Display,TEXT("Street outing: navigation to %s ends, he goes with actor=%d"),*S.NavPointName,Girl);StopNavigation(FString());}
 if(S.OutingGirl!=INDEX_NONE)CancelOuting(FString());
 if(S.Companion!=INDEX_NONE)FinishCompanion();
 if(Stroll){BeginStroll(Girl,Error);return Error.IsEmpty();}
 // Activities with an anchor happen inside the place: the route goes on from the door to that spot.
 const FOKStreetModelAnchor* Spot=Place&&Activity?OKStreetPlaceAnchor(*Place,Activity->Anchor):nullptr;
 // A spot in another building than its place (the old school's music room is on the cafeteria's 3F): the walk goes
 // through the building it is in, its door and its lift. Up the school's own lift it ended on the 3F 100 m off, two
 // minutes of walking into walls (activity audit 11-09).
 if(Spot&&Place&&!OKStreetInsidePlace(*Place,Spot->Position))for(const auto& Q:OKStreetPlaces())if(&Q!=Place&&!Q.Rooms.IsEmpty()&&OKStreetInsidePlace(Q,Spot->Position)){
  UE_LOG(LogTemp,Display,TEXT("Street outing: %s's spot is in %s, not %s: the walk goes through it"),*ActivityId,Q.Id,Place->Id);Place=&Q;break;}
 // Already there: at the activity's spot, or for a building inside it (at its door is still outside the shop: the route
 // below goes in), for a place without rooms at its door.
 const bool There=!Place||(Spot?FVector::Dist2D(S.Male,Spot->Position)<80&&FMath::Abs(S.Male.Z-Spot->Position.Z)<150.f:Place->Rooms.IsEmpty()?FVector::Dist2D(S.Male,Place->Door)<200:OKStreetInsidePlace(*Place,S.Male));
 if(There)return StartOutingActivity(Girl,ActivityId,Error);
 // Upstairs in a building with an elevator and going elsewhere: to the car on this floor and down to the street
 // first (StepLiftRide), then the way there from the ground floor. A route straight from upstairs runs into walls.
 if(OKStreetUpstairs(S.Male)&&!(Spot&&OKStreetInsidePlace(*Place,S.Male)))for(int32 PlaceIx=0;PlaceIx<OKStreetPlaces().Num();++PlaceIx){
  const auto& Here=OKStreetPlaces()[PlaceIx];if(!OKStreetInsidePlace(Here,S.Male))continue;
  const auto Lifts=OKStreetPlaceLifts(Here);const int32 Elevator=ElevatorOfPlace(PlaceIx);if(Lifts.IsEmpty()||Elevator==INDEX_NONE)continue;
  int32 Floor=0;for(int32 F=0;F<Lifts.Num();++F)if(FMath::Abs(Lifts[F]->Position.Z-S.Male.Z)<FMath::Abs(Lifts[Floor]->Position.Z-S.Male.Z))Floor=F;
  TArray<FVector> Down=GridRoute(S.Male,Lifts[Floor]->Position);if(Down.Num()<2)Down={S.Male,Lifts[Floor]->Position};
  S.LiftRide=FOKStreetLiftRide();S.LiftRide.Elevator=Elevator;S.LiftRide.Floor=0;S.LiftRide.Descend=true;S.LiftRide.Spot=Spot?Spot->Position:PlaceInsideSpot(*Place);
  StopAmbientActivity();EndTalk();
  S.OutingGirl=Girl;S.OutingActivity=ActivityId;S.OutingPlace=Place->Name;S.OutingRoute=MoveTemp(Down);S.OutingStep=1;S.OutingProgressAt=S.OutingBegunAt=SceneTime();
  S.TransitQuote.Reset();S.TransitFor=INDEX_NONE; // the walk and its bus or taxi are told once down on the street (StepLiftRide)
  S.Companion=Girl;S.Agents[Girl-1].Held=true;S.CompanionTrail.Reset();S.CompanionTrail.Add(S.Male);S.CompanionLastMale=S.Male;S.CompanionBlockedAt=0;S.CompanionTravel=0;S.CompanionWalk=0;
  S.Message=OKMsg(TEXT("ui.outing.walk_to_place_by_elevator"), {{TEXT("girl_name"), *S.Manifest.Characters[Girl].Name}, {TEXT("place_name"), Place->Name}});
  UE_LOG(LogTemp,Display,TEXT("Street outing: actor=%d activity=%s starts upstairs in %s: down by the elevator first"),Girl,*ActivityId,Here.Name);
  RefreshUI();return true;
 }
 const FVector SpotAt=Spot?Spot->Position:FVector::ZeroVector;TArray<FVector> Route;
 if(!PlanOutingRoute(Place,Spot?&SpotAt:nullptr,Route,Error))return false;
 StopAmbientActivity();EndTalk();
 S.OutingGirl=Girl;S.OutingActivity=ActivityId;S.OutingPlace=Place->Name;S.OutingRoute=Route;S.OutingStep=1;S.OutingProgressAt=S.OutingBegunAt=SceneTime();
 S.TransitQuote.Reset();S.TransitFor=INDEX_NONE;
 // Same follow as the shared walk: she trails the player's breadcrumbs.
 S.Companion=Girl;S.Agents[Girl-1].Held=true;S.CompanionTrail.Reset();S.CompanionTrail.Add(S.Male);S.CompanionLastMale=S.Male;S.CompanionBlockedAt=0;S.CompanionTravel=0;S.CompanionWalk=0;
 S.Message=OKMsg(TEXT("ui.outing.walk_to_place_together"), {{TEXT("girl_name"), *S.Manifest.Characters[Girl].Name}, {TEXT("place_name"), Place->Name}});
 UE_LOG(LogTemp,Display,TEXT("Street outing: actor=%d activity=%s route_points=%d"),Girl,*ActivityId,Route.Num());
 TellOutingWalk(Girl,*Place,Route);
 RefreshUI();
 return true;
}

// A walk with no destination: five or so straight legs round where they stand, back to the start. Every point, and
// the ground between points, keeps at least 50 cm from any obstacle; indoors-out is avoided unless they are indoors.
void AOKStreetSocialScene::BeginStroll(int32 Girl,FString& Error,bool bRun){
 auto& S=*State;Error.Reset();
 constexpr float StrollClearance=50.f;
 auto Clear=[&](const FVector& From,const FVector& To){
  const bool FromTight=OKStreetBlockedPoint(From,StrollClearance); // where he stands may already be close to something
  const float Length=float(FVector::Dist2D(From,To));const int32 Steps=FMath::Max(2,int32(Length/60.f));
  for(int32 K=0;K<=Steps;++K){const FVector P=From+(To-From)*(float(K)/float(Steps));if(FromTight&&FVector::Dist2D(P,From)<120.f)continue;if(OKStreetBlockedPoint(P,StrollClearance))return false;}
  return true;
 };
 // A run (jogging in the park): longer legs that stay inside the place they run in.
 const FString Here=PlaceHere(S.Male);
 // A room under 15 m across (a restaurant, a cafe) is no place for a walk: out of its door and round outside, back to
 // the door (R6-36: her "quiet path" after lunch was 14 points among the restaurant tables, over in 22 s). A floor to
 // walk round (the department store's) keeps its loop inside.
 const FOKStreetPlace* In=Here.IsEmpty()||bRun?nullptr:OKStreetFindPlace(Here);bool Small=false;
 if(In&&!In->Door.IsNearlyZero())for(const FBox& R:In->Rooms)if(S.Male.X>=R.Min.X&&S.Male.X<=R.Max.X&&S.Male.Y>=R.Min.Y&&S.Male.Y<=R.Max.Y&&S.Male.Z>=R.Min.Z-60.f&&S.Male.Z<R.Max.Z)
  Small=FMath::Min(R.Max.X-R.Min.X,R.Max.Y-R.Min.Y)<1500.f;
 TArray<FVector> Route;
 if(Small){Route=PlaceRoute(S.Male,In->Door);if(Route.Num()<2)Route=GridRoute(S.Male,In->Door);if(Route.Num()<2)Route={S.Male,In->Door};
  UE_LOG(LogTemp,Display,TEXT("Street stroll: %s is a small room; the walk goes out of its door (%d points) and round outside"),In->Name,Route.Num());}
 else Route.Add(S.Male);
 const int32 Out=Route.Num();FVector At=Route.Last();const FVector Home=At;const bool Indoors=!Here.IsEmpty()&&!bRun&&!Small;
 // Indoors the legs are short: more of them, so a walk round the floor is not over in a minute or two.
 for(int32 Leg=0;Leg<(Indoors?12:5);++Leg){
  bool Found=false;
  for(int32 Try=0;Try<(Indoors?40:16)&&!Found;++Try){
   // Indoors the rooms are small: shorter legs, more tries.
   FVector P=At+FRotator(0,S.Random.FRandRange(0.f,360.f),0).RotateVector(FVector(Indoors?S.Random.FRandRange(150.f,600.f):bRun?S.Random.FRandRange(400.f,900.f):S.Random.FRandRange(500.f,1400.f),0,0));P.Z=At.Z;
   if(bRun?PlaceHere(P)!=Here:(!Indoors&&!PlaceHere(P).IsEmpty()))continue;
   if(!Clear(At,P))continue;
   Route.Add(P);At=P;Found=true;
  }
  if(!Found)break;
 }
 if(Route.Num()-Out>=2&&Clear(At,Home))Route.Add(Home);
 if(Route.Num()-Out<2){Error=OKT(TEXT("ui.outing.no_walk_route_nearby"));UE_LOG(LogTemp,Display,TEXT("Street stroll: no route found around (%.0f,%.0f)"),S.Male.X,S.Male.Y);return;}
 StopAmbientActivity();EndTalk();
 S.OutingGirl=Girl;S.OutingActivity=TEXT("stroll");S.OutingPlace=OKT(TEXT("ui.outing.nearby_label"));S.OutingRoute=Route;S.OutingStep=1;S.OutingProgressAt=S.OutingBegunAt=SceneTime();S.OutingRun=bRun;
 S.Companion=Girl;S.Agents[Girl-1].Held=true;S.CompanionTrail.Reset();S.CompanionTrail.Add(S.Male);S.CompanionLastMale=S.Male;S.CompanionBlockedAt=0;S.CompanionTravel=0;S.CompanionWalk=0;
 S.Message=OKMsg(TEXT("ui.outing.stroll_nearby_together"), {{TEXT("girl_name"), *S.Manifest.Characters[Girl].Name}});
 UE_LOG(LogTemp,Display,TEXT("Street stroll: actor=%d route_points=%d"),Girl,Route.Num());
 RefreshUI();
}

void AOKStreetSocialScene::CancelOuting(const FString& Message){
 if(!State||State->OutingGirl==INDEX_NONE)return;auto& S=*State;
 const int32 Girl=S.OutingGirl;
 MindRemember(Girl,TEXT("outing"),OKMsg(TEXT("ui.memory.outing_cancelled"),{{TEXT("place"),([&](const FString& Id){const FOKStreetPlace* P=OKStreetFindPlace(Id);return P?FString(P->Name):Id.IsEmpty()?FString(OKT(TEXT("ui.etiquette.street_location"))):Id;})(S.OutingPlace)},{TEXT("activity"),OKStreetActivityName(S.OutingActivity)},{TEXT("why"),Message}}),S.OutingPlace,0.25f);
 UE_LOG(LogTemp,Display,TEXT("Street outing: cancelled at %s (%s)"),*S.Male.ToCompactString(),*Message);
 S.OutingGirl=INDEX_NONE;S.TransitQuote.Reset();S.TransitFor=INDEX_NONE;S.OutingRoute.Reset();S.OutingActivity.Reset();S.OutingPlace.Reset();S.LiftRide=FOKStreetLiftRide();S.OutingWaitDoor=false;S.OutingRun=false;S.StrollActivity.Reset();S.PhotoWalkAlbum.Reset();
 if(S.Companion==Girl)FinishCompanion();
 if(!Message.IsEmpty()){S.Message=Message;ResumeTalkQuiet(Girl);}
 RefreshUI();
}

// Player autopilot along the outing route; returns the walk-animation speed ratio (0 when standing).
float AOKStreetSocialScene::StepOuting(float Dt){
 auto& S=*State;
 if(S.OutingGirl==INDEX_NONE)return 0;
 // He leads or they walk abreast and he is walking himself: the route waits; 3 s idle it goes on from where he is
 // (a walk to a place is planned again from here; a stroll keeps its points).
 if(S.FollowMode!=1&&SceneTime()-S.ManualMoveAt<3.0){S.OutingProgressAt=SceneTime();return 0;}
 if(S.ManualReplan&&S.FollowMode!=1){S.ManualReplan=false;S.FollowLeadInit=false;
  if(S.OutingActivity!=TEXT("stroll")&&S.OutingStep<S.OutingRoute.Num()){auto Path=PlaceRoute(S.Male,S.OutingRoute.Last());if(Path.Num()>=2){S.OutingRoute=MoveTemp(Path);S.OutingStep=1;}}
  S.Message=OKT(TEXT("ui.outing.continue_heading_on"));RefreshUI();}
 if(S.FollowMode!=0&&S.Companion==S.OutingGirl)return StepOutingLed(Dt);
 // The follow gave up (too far, blocked for long): stop going there.
 if(S.Companion!=S.OutingGirl){CancelOuting(OKT(TEXT("ui.outing.she_didnt_follow")));return 0;}
 const double Now=SceneTime();
 // Not open yet when they reach its door (they set off at 10:51 for an 11:00 opening): they wait outside the door, still
 // talking, and go in once it opens; they used to walk in and sit down at a table in the dark shop.
 {const FOKStreetActivity* Act=OKStreetFindActivity(S.OutingActivity);
  const FOKStreetPlace* Dest=S.OutingActivity.StartsWith(TEXT("go:"))?OKStreetFindPlace(S.OutingActivity.Mid(3)):Act&&Act->Place?OKStreetFindPlace(Act->Place):nullptr;
  FString Why;
  if(Dest&&!Dest->Rooms.IsEmpty()&&!OKStreetInsidePlace(*Dest,S.Male)&&FVector::Dist2D(S.Male,Dest->Door)<150.f&&PlaceClosedNow(Dest->Id,Why)){
   // Setting off allowed an opening a quarter of an hour after the estimated walk, and the walk was quicker than that
   // estimate (at the cafe at 07:36 for 08:00: called off at its door, R3-217).
   // Setting off allowed it, so they wait as long as going there does (R5-8): the walk is often quicker than its
   // estimate, and lunch at the restaurant opening at 11 was called off at its door at 10:20 on half an hour (R5-22).
   if(PlaceClosedAt(Dest->Id,StreetNow()+FTimespan::FromMinutes(OKStreetDoorWaitMinutes),Why)){S.OutingWaitDoor=false;CancelOuting(OKMsg(TEXT("ui.outing.closed_at_door"),{{TEXT("place"),Dest->Name},{TEXT("why"),*Why}}));return 0;}
   S.OutingProgressAt=Now;
   if(!S.OutingWaitDoor){S.OutingWaitDoor=true;S.Message=OKMsg(TEXT("ui.outing.wait_at_door_until_open"),{{TEXT("place"),Dest->Name}});RefreshUI();
    UE_LOG(LogTemp,Display,TEXT("Street outing: %s not open yet; they wait at its door (%s)"),Dest->Id,*Why);}
   return 0;}
  if(S.OutingWaitDoor){S.OutingWaitDoor=false;if(Dest){S.Message=OKMsg(TEXT("ui.outing.opened_go_in"),{{TEXT("place"),Dest->Name}});RefreshUI();UE_LOG(LogTemp,Display,TEXT("Street outing: %s opened; they go in"),Dest->Id);}}}
 if(S.LiftRide.Elevator!=INDEX_NONE&&S.OutingStep>=S.OutingRoute.Num())return StepLiftRide(Dt);
 const float Gap=FVector::Dist2D(S.Male,S.Agents[S.OutingGirl-1].Position);
 if(S.OutingStep>=S.OutingRoute.Num()){if(Gap<=220)ArriveOuting();return 0;}
 if(Gap>350){S.OutingProgressAt=Now;return 0;} // wait for her to catch up
 FVector Delta=S.OutingRoute[S.OutingStep]-S.Male;Delta.Z=0;
 const float Distance=Delta.Size();
 if(Distance<20){++S.OutingStep;
  // A photo walk stops at every second point, three times, for his photo of her.
  if(!S.PhotoWalkAlbum.IsEmpty()&&S.OutingStep%2==0&&S.PhotoWalkStops<3&&S.OutingStep<S.OutingRoute.Num()){S.PhotoWalkPauseUntil=Now+3.0;PhotoWalkStop(S.OutingGirl);}
  return 0;}
 if(Now<S.PhotoWalkPauseUntil){S.OutingProgressAt=Now;return 0;}
 const float Pace=S.OutingRun?OKStreetMaleRunSpeed*.7f:OKStreetMaleWalkSpeed; // jogging: a run he can keep up
 const FVector Candidate=StreetStep(S.Male,Delta/Distance,FMath::Min(Distance,Pace*FMath::Min(Dt,.05f)));
 if(Candidate==S.Male){
  // His own way is blocked: plan the route again from where he stands, every 4 s, until it opens. Esc ends it.
  if(Now-S.OutingProgressAt>4){
   // Round the obstacle to the next point and on along the rest of the route: planned straight to the last point, a
   // stroll's loop (it ends near where it began) collapsed into two points and the walk was over in seconds.
   S.OutingProgressAt=Now;
   // Upstairs the way is on this floor: planned again on the street's routes from the EE building's 2F, the next point was
   // its door on the ground floor and he was stepped down to it through the floor (activity audit 11-09).
   const bool Upstairs=OKStreetUpstairs(S.Male);
   TArray<FVector> Again=Upstairs?GridRoute(S.Male,S.OutingRoute[S.OutingStep]):PlaceRoute(S.Male,S.OutingRoute[S.OutingStep]);
   if(Again.Num()>=2)for(int32 K=S.OutingStep+1;K<S.OutingRoute.Num();++K)Again.Add(S.OutingRoute[K]);
   else if(!Upstairs)Again=PlaceRoute(S.Male,S.OutingRoute.Last()); // the next point itself is out of reach: straight on to the end
   // Inside a building (just down from the elevator) the street routes do not reach him: out by its door first.
   if(Again.Num()<2&&!Upstairs)if(const FOKStreetPlace* In=OKStreetFindPlace(PlaceHere(S.Male));In&&!In->Door.IsNearlyZero()){
    TArray<FVector> Out=PlaceRoute(In->Door,S.OutingRoute.Last());
    // Already tried the straight way to the door and a wall is in it: they step out of the door (a hallway the
    // street map does not know).
    if(Out.Num()>=2&&S.OutingRoute.IsValidIndex(1)&&S.OutingRoute[1].Equals(In->Door,1.f)){
     UE_LOG(LogTemp,Display,TEXT("Street outing: no way out of %s from (%.0f,%.0f); they step out of its door"),In->Name,S.Male.X,S.Male.Y);
     S.Male=FVector(In->Door.X,In->Door.Y,S.Male.Z);S.Agents[S.OutingGirl-1].Position=S.Male+FVector(0,80,0);Again=MoveTemp(Out);}
    else if(Out.Num()>=2){Again={S.Male};Again.Append(Out);}}
   UE_LOG(LogTemp,Display,TEXT("Street outing: blocked at (%.0f,%.0f), route planned again (%d points)"),S.Male.X,S.Male.Y,Again.Num());
   // The same route again ran into the same thing every 4 s for minutes (a stroll stuck by the restaurant tables;
   // R3-234). Held up in the same spot a second time: round it on the grid (cells tested with his body's clearance);
   // a fifth: he squeezes past to the next point, as the navigation does when wedged.
   if(FVector::Dist2D(S.Male,S.OutingStuckPos)<30.f)++S.OutingStuckCount;else{S.OutingStuckCount=1;S.OutingStuckPos=S.Male;}
   // Held up within reach of the last point (the seat at the table): he takes it now. At the cafeteria he stood 60 cm (at the
   // department store 1.55 m) from his chair for 16 s while the route was planned round the table again and again.
   // At the boat pond the dock is over the water's edge: blocked 1.5 m short, the route planned again went the long way
   // round the pond and back, two minutes (activity audit 11-09); the rowing boat is 8 m off the bank. The activity puts them
   // on its spot anyway: within 10 m of an activity's last point he takes it.
   const bool AtLast=S.OutingStep==S.OutingRoute.Num()-1&&FVector::Dist2D(S.Male,S.OutingRoute[S.OutingStep])<(OKStreetFindActivity(S.OutingActivity)?1000.f:200.f);
   // Upstairs with no way found on the floor twice (the cafeteria's 3F to its music room, the EE building's 2F): the next
   // point is on this floor, he steps past rather than standing there until she gives up.
   if((S.OutingStuckCount>=5||AtLast||(Upstairs&&Again.Num()<2&&S.OutingStuckCount>=2))&&S.OutingRoute.IsValidIndex(S.OutingStep)){
    const FVector Next=S.OutingRoute[S.OutingStep];UE_LOG(LogTemp,Display,TEXT("Street outing: wedged at (%.0f,%.0f); he steps past to the next point %s"),S.Male.X,S.Male.Y,*Next.ToCompactString());
    // At the point's height in the city (its ground): kept at his, a step past onto a lower road left him 2.5 m up in the
    // air, where no step finds ground under him, and every point after that was a wedge (R6-180).
    FVector To(Next.X,Next.Y,OKStreetCityMode()?Next.Z:S.Male.Z);
    // Not into the furniture: the meal's last point is the table itself, he was put in the fast food table and stood
    // up inside it, shut in between it and the wall (R6-199). The nearest clear spot, his side first.
    {FCollisionQueryParams Q(SCENE_QUERY_STAT(StreetStepPast),false,this);
     auto Clear=[&](const FVector& P){return !GetWorld()->OverlapAnyTestByChannel(P+FVector(0,0,85),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(28,78),Q);};
     if(!Clear(To)){bool Found=false;FVector Best=To;double BestD=1e18;
      for(int32 R=1;R<=4&&!Found;++R)for(int32 DX=-R;DX<=R;++DX)for(int32 DY=-R;DY<=R;++DY){if(FMath::Max(FMath::Abs(DX),FMath::Abs(DY))!=R)continue;
       const FVector P=To+FVector(DX*OKStreetNavCell,DY*OKStreetNavCell,0);if(!Clear(P))continue;const double D=FVector::Dist2D(P,S.Male);if(D<BestD){BestD=D;Best=P;Found=true;}}
      if(Found){UE_LOG(LogTemp,Display,TEXT("Street outing: %s is in the furniture, he stands at %s"),*To.ToCompactString(),*Best.ToCompactString());To=Best;}}}
    S.Male=To;++S.OutingStep;S.OutingStuckCount=0;return 0;}
   // Back at the same spot after a planned-again route is a loop already: on the way to the ramen shop each new street
   // route led him off and round to the same block by the department store, three loops, an hour of the clock (R6-187).
   if(S.OutingStuckCount>=2&&S.OutingRoute.IsValidIndex(S.OutingStep)){TArray<FVector> Around=GridRoute(S.Male,S.OutingRoute[S.OutingStep]);
    if(Around.Num()>=2){for(int32 K=S.OutingStep+1;K<S.OutingRoute.Num();++K)Around.Add(S.OutingRoute[K]);Again=MoveTemp(Around);UE_LOG(LogTemp,Display,TEXT("Street outing: round it on the grid (%d points)"),Again.Num());}}
   if(Again.Num()>=2){S.OutingRoute=Again;S.OutingStep=1;}
  }
  return 0;
 }
 S.Rotations[0]=OKStreetFacingMovement(Candidate-S.Male,S.Rotations[0]);S.Male=Candidate;S.OutingProgressAt=Now;
 return Pace/OKStreetWalkSpeed;
}

void AOKStreetSocialScene::ArriveOuting(){
 auto& S=*State;
 const int32 Girl=S.OutingGirl;const FString Activity=S.OutingActivity;const FString Place=S.OutingPlace;
 S.OutingGirl=INDEX_NONE;S.TransitQuote.Reset();S.TransitFor=INDEX_NONE;S.OutingRoute.Reset();S.OutingActivity.Reset();S.OutingPlace.Reset();S.LiftRide=FOKStreetLiftRide();S.OutingWaitDoor=false;
 S.LastActivity=Activity;S.LastActivityGirl=Girl;S.LastActivityAt=SceneTime(); // for its aftermath when it ends (Life.inl)
 // Where the two of them just got to, for a meeting there later today that this walk already was (R5-13).
 if(Girl!=INDEX_NONE){const FOKStreetActivity* A=OKStreetFindActivity(Activity);S.ArrivedWith=Girl;S.ArrivedMinute=OKStreetMindNow(S);
  S.ArrivedPlace=Activity.StartsWith(TEXT("go:"))?Activity.Mid(3):A&&A->Place?FString(A->Place):Place;}
 if(Girl!=INDEX_NONE)MindRemember(Girl,TEXT("outing"),OKMsg(TEXT("ui.memory.outing_arrived"),{{TEXT("place"),([&](const FString& Id){const FOKStreetPlace* P=OKStreetFindPlace(Id);return P?FString(P->Name):Id.IsEmpty()?FString(OKT(TEXT("ui.etiquette.street_location"))):Id;})(Place)},{TEXT("activity"),OKStreetActivityName(Activity)}}),Place,0.3f);
 if(S.Companion==Girl){
  if(S.Agents.IsValidIndex(Girl-1)){auto& Agent=S.Agents[Girl-1];Agent.Held=false;Agent.Mode=EOKStreetMove::Walking;Agent.Stuck=0;}
  FString Error;ResumeBehavior(Girl,Error);S.Companion=INDEX_NONE;S.CompanionTrail.Reset();S.CompanionBlockedAt=0;S.CompanionWalk=0;
 }
 FString Error;
 if(Activity==TEXT("stroll")){
  // A run around the park (an activity of the table, not a plain stroll): its end is an activity's end (time, needs).
  const FString Run=S.StrollActivity;S.StrollActivity.Reset();S.OutingRun=false;S.PhotoWalkAlbum.Reset();
  if(!Run.IsEmpty()&&Girl!=INDEX_NONE)ActivityAftermath(Run,Girl,S.StrollStartMinute);
  S.Message=OKT(TEXT("ui.outing.stroll_ended"));ResumeTalkQuiet(Girl);RefreshUI();return;}
 if(Activity.StartsWith(TEXT("go:"))){
  // Walked home by him: she stays in for the rest of this block. 安可, full and walked back to the dorm at 20:37, set off
  // at once for her 18:16-21:00 meal at the department store she had just come from (R6-102). A class, shift, promise
  // or the night still takes her (the schedule's own check).
  if(Girl!=INDEX_NONE&&S.Manifest.Characters.IsValidIndex(Girl)&&Activity.Mid(3)==OKStreetProfileString(S.MindProfiles.FindRef(OKStreetStableId(S.Manifest.Characters[Girl])),nullptr,TEXT("home_place_id"))){
   const int64 Now=OKStreetMindNow(S);const int32 Minute=int32(Now%1440);
   // The meeting with him she is coming home from counts as over too: 安可's 19:00 date block ran to 21:44, and walked home
   // after it at 20:41 she went straight back out.
   if(const FOKStreetPlanBlock* B=BlockNow(Girl,Minute);B&&B->End>Minute&&(!OKStreetFixedBlock(B)||B->Kind==TEXT("promise"))){S.HomeAfterWalk.Add(Girl,FIntPoint(int32(Now),int32(Now-Minute+B->End)));
    UE_LOG(LogTemp,Display,TEXT("Street outing: actor %d walked home; stays in until %02d:%02d"),Girl,B->End/60%24,B->End%60);}}
  S.Message=OKMsg(TEXT("ui.outing.arrived_at_place"), {{TEXT("place"), *Place}});ResumeTalkQuiet(Girl);RefreshUI();return;}
 // Gone in to play cards: they sit down to the game, not to the place's own activity.
 if(!S.BluffOnArrival.IsEmpty()&&S.BluffOnArrival==Activity){S.BluffOnArrival.Reset();FString Why;
  if(BluffCanStart(&Why)){S.Message=OKMsg(TEXT("ui.outing.arrived_start_bluff_game"), {{TEXT("place"), *Place}});StartBluff();}
  else{S.BluffDealBy=SceneTime()+20.0;S.Message=OKMsg(TEXT("ui.outing.arrived_deal_after_seated"), {{TEXT("place"), *Place}});ResumeTalkQuiet(Girl);RefreshUI();} // the others still walking in (TickBluff)
  return;}
 // At a meal upstairs in a building they were already in (the food court on 9F): no menu prompt came, as they had
 // walked in on 1F, and the ramen 惠惠 asked for on the way was never ordered; she said "the ramen is here" over his
 // bowl alone (R6-62). Arriving at it is walking into the place to eat: the prompt comes once (TickShopArrival).
 if(Girl!=INDEX_NONE){const FOKStreetActivity* A=OKStreetFindActivity(Activity);const FString At=A&&A->Place?FString(A->Place):Place;
  if(!At.IsEmpty()&&S.ShopPromptedPlace!=At&&ItemsHere(At).ContainsByPredicate([](const FOKStreetCatalogItem* I){return I&&I->Consumable;})){
   S.ShopArrivalPlace.Reset();S.ShopSeenPlace=At;S.ShopEnteredWith=true;UE_LOG(LogTemp,Display,TEXT("Street outing: arrived to eat at %s; the menu prompt is due"),*At);}}
 if(!StartOutingActivity(Girl,Activity,Error)){S.Message=OKMsg(TEXT("ui.outing.arrived_but_error"), {{TEXT("place"), *Place}, {TEXT("error"), *Error}});ResumeTalkQuiet(Girl);RefreshUI();}
}

// Where to sit down for cards agreed on outdoors (bluff.rs card_table_place): an activity with a spot inside an open
// place (a table first), the place he named or the nearest; "" when there is none (or they are indoors already).
FString AOKStreetSocialScene::CardTableOuting(const FString& Said){
 auto& S=*State;FString Why;if(BluffCanStart(&Why))return FString();
 TMap<FString,FString> SeatOf;TArray<TSharedPtr<FJsonValue>> Places;
 for(const auto& P:OKStreetPlaces()){
  const FOKStreetActivity* Best=nullptr;
  for(const auto& A:OKStreetActivities()){if(!A.Place||!A.Anchor||FCString::Strcmp(P.Id,A.Place)!=0)continue;const FOKStreetModelAnchor* Spot=OKStreetPlaceAnchor(P,A.Anchor);
   if(A.Kind==EOKStreetActivityKind::Facility||A.Kind==EOKStreetActivityKind::Sleep||A.Kind==EOKStreetActivityKind::Restroom)continue; // a room of their own, not a table
   if(!Spot||!OKStreetInsidePlace(P,Spot->Position))continue;if(!Best||(A.Kind==EOKStreetActivityKind::Pair&&Best->Kind!=EOKStreetActivityKind::Pair))Best=&A;}
  FString Closed;auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("id"),P.Id);O->SetStringField(TEXT("name"),P.Name);O->SetNumberField(TEXT("dist"),FVector::Dist2D(P.Door,S.Male));
  O->SetBoolField(TEXT("open"),!PlaceClosedNow(P.Id,Closed));O->SetBoolField(TEXT("seat"),Best!=nullptr);Places.Add(MakeShared<FJsonValueObject>(O));
  if(Best)SeatOf.Add(P.Id,Best->Id);
 }
 auto Request=OKRulesRequest(TEXT("card_table_place"));Request->SetStringField(TEXT("said"),Said);Request->SetBoolField(TEXT("indoors"),false);Request->SetArrayField(TEXT("places"),Places);
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer.IsValid())return FString();
 const FString* Seat=SeatOf.Find(Answer->GetStringField(TEXT("place")));return Seat?*Seat:FString();
}

// A city spot is often the thing itself (the drink shop's counter, the snack bar's table, the bookshop's shelf, a vending
// machine): stood exactly there he was inside it, and the camera between their heads with him, the view one white counter
// (activity audit 11-09). A seat, a bench, a bed or a pool is meant to be sat or lain in: those keep the spot.
bool AOKStreetSocialScene::ActivitySettles(const TCHAR* Anchor) const{
 if(!OKStreetCityMode()||!Anchor)return false;const FString Name=Anchor;
 for(const TCHAR* In:{TEXT("seat"),TEXT("bench"),TEXT("sofa"),TEXT("booth"),TEXT("bed"),TEXT("bleacher"),TEXT("chair"),TEXT("pool"),TEXT("swim"),TEXT("bath"),TEXT("lounge"),TEXT("boat")})if(Name.Contains(In))return false;
 return true;
}
// The nearest open floor round At (a body's room from the hips up, ground at its height), on the near side of what it faces
// (Yaw) first; At stays when it is open already or nothing is within 4 m (the park's fountain is wider than 2 m).
void AOKStreetSocialScene::SettleOnFloor(FVector& At,float Yaw,const TCHAR* Why) const{
 FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetActivitySpot),false,this);
 // (and clear of the street's own props: the lodge's vending machine has no collision, and she stood in it to her chin)
 auto Clear=[&](FVector& P){float G=P.Z;if(OKStreetBlockedPoint(P,15.f)||!OKStreetGroundZ(GetWorld(),P,G,this)||G>P.Z+30.f||G<P.Z-60.f)return false;
  if(GetWorld()->OverlapAnyTestByChannel(FVector(P.X,P.Y,G+110.f),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(20.f,65.f),Query))return false;P.Z=G;return true;};
 FVector Here=At;if(Clear(Here)){At=Here;return;}
 const FVector Facing=FRotator(0,Yaw,0).Vector();FVector Best=At;float BestScore=TNumericLimits<float>::Max();
 for(float R=25.f;R<=400.f;R+=25.f){for(int32 K=0;K<24;++K){const FVector Dir(FMath::Cos(2*PI*K/24.f),FMath::Sin(2*PI*K/24.f),0);FVector C=At+Dir*R;if(!Clear(C))continue;
   const float Score=R+((Dir|Facing)>.3f?60.f:0.f);if(Score<BestScore){BestScore=Score;Best=C;}}if(BestScore<R+25.f)break;}
 if(BestScore<TNumericLimits<float>::Max()){UE_LOG(LogTemp,Display,TEXT("Street activity: %s spot inside something, %s -> %s"),Why,*At.ToCompactString(),*Best.ToCompactString());At=Best;}
}

// The way to an outing's place from where he is (not upstairs in another building: BeginOuting takes him down first):
// inside it over the grid or by its elevator, out in the open to the spot, else to the door (of the building it is
// upstairs in, and up by its elevator: S.LiftRide). Also after the ride down from upstairs: the street route straight at
// a spot upstairs in another building ended under it, and the taxi set them down on the civic centre's 3F at the
// aquarium, past its lift (R6-234).
bool AOKStreetSocialScene::PlanOutingRoute(const FOKStreetPlace* Place,const FVector* Spot,TArray<FVector>& Route,FString& Error){
 auto& S=*State;Route.Reset();
 // Already inside: walk over on this floor; the spot on another floor (the food court on 9F from the ground floor) is
 // up (or down) by the elevator: to its landing here, the ride (StepLiftRide), then on to the spot. Walking straight at
 // it "arrived" under it and the activity put them on 9F without the ride.
 const TArray<const FOKStreetModelAnchor*> InLifts=Spot&&OKStreetInsidePlace(*Place,S.Male)?OKStreetPlaceLifts(*Place):TArray<const FOKStreetModelAnchor*>();
 const int32 InElevator=InLifts.IsEmpty()?INDEX_NONE:ElevatorOfPlace(OKStreetPlaces().IndexOfByPredicate([Place](const FOKStreetPlace& P){return &P==Place;}));
 if(Spot&&InElevator!=INDEX_NONE&&FMath::Abs(S.Male.Z-(*Spot).Z)>=150.f){
  auto FloorAt=[&](float Z){int32 Best=0;for(int32 F=0;F<InLifts.Num();++F)if(FMath::Abs(InLifts[F]->Position.Z-Z)<FMath::Abs(InLifts[Best]->Position.Z-Z))Best=F;return Best;};
  const int32 From=FloorAt(S.Male.Z),To=FloorAt((*Spot).Z);
  Route=GridRoute(S.Male,InLifts[From]->Position);if(Route.Num()<2)Route={S.Male,InLifts[From]->Position};
  S.LiftRide=FOKStreetLiftRide();S.LiftRide.Elevator=InElevator;S.LiftRide.Floor=To;S.LiftRide.Spot=(*Spot);
  UE_LOG(LogTemp,Display,TEXT("Street outing: the spot is on another floor of %s: by the elevator (%d -> %d)"),Place->Name,From,To);
 }
 // Already inside, same floor: over on the grid, to the spot or the nearest cell beside it in sight of it (a carousel's
 // spot is in the ride); straight over only when the grid finds nothing. Straight from the amusement park's gate to the
 // carousel he ran into the rides 14 m short and went round for two minutes (activity audit 11-11).
 else if(Spot&&OKStreetInsidePlace(*Place,S.Male)){Route=GridRoute(S.Male,(*Spot),150.f);if(Route.Num()<2)Route={S.Male,(*Spot)};}
 // Open air: no door to go through, the way leads to the spot itself. By the "door" the walk to the Christmas tree went
 // round by the campus gate to the far side of the fence and back (its door had been put on the campus side; activity
 // audit 11-09).
 else if(Spot&&Place->Outdoor&&!OKStreetUpstairs((*Spot))){Route=PlaceRoute(S.Male,(*Spot));if(Route.Num()<2){Error=OKMsg(TEXT("ui.outing.no_route_to_place"), {{TEXT("place_name"), Place->Name}});return false;}}
 else{
  // Upstairs, by an elevator: the place's own, or the building's it is in. "Let's go to the ramen shop" (no activity
  // spot) walked to the department store's ground floor under its 9F door and "arrived" there; 贞德·Alter's ramen was
  // "not sold here" (R6-187).
  const FVector Target=Spot?(*Spot):PlaceInsideSpot(*Place);
  const FOKStreetPlace* LiftPlace=nullptr;
  if(OKStreetUpstairs(Target)){
   if(!OKStreetPlaceLifts(*Place).IsEmpty())LiftPlace=Place;
   else for(const auto& Q:OKStreetPlaces())if(&Q!=Place&&!Q.Rooms.IsEmpty()&&!OKStreetPlaceLifts(Q).IsEmpty()&&!OKStreetUpstairs(Q.Door)&&OKStreetInsidePlace(Q,Target)){LiftPlace=&Q;break;}}
  const FVector Door=LiftPlace?LiftPlace->Door:Place->Door;
  Route=FVector::Dist2D(S.Male,Door)<200?TArray<FVector>{S.Male,Door}:PlaceRoute(S.Male,Door);
  if(Route.Num()<2){Error=OKMsg(TEXT("ui.outing.no_route_to_place"), {{TEXT("place_name"), Place->Name}});return false;}
  if(LiftPlace){
   const auto Lifts=OKStreetPlaceLifts(*LiftPlace);
   // Indoors the grid finds the way round desks and shelves from the door to the elevator.
   TArray<FVector> In=GridRoute(Route.Last(),Lifts[0]->Position);if(In.Num()>=2){In.RemoveAt(0);Route.Append(In);}
   else{if(const auto* Hall=OKStreetPlaceAnchor(*LiftPlace,TEXT("hall")))Route.Add(Hall->Position);Route.Add(Lifts[0]->Position);}
   // then ride up in the car (StepLiftRide)
   int32 Floor=0;for(int32 F=0;F<Lifts.Num();++F)if(FMath::Abs(Lifts[F]->Position.Z-Target.Z)<FMath::Abs(Lifts[Floor]->Position.Z-Target.Z))Floor=F;
   S.LiftRide=FOKStreetLiftRide();S.LiftRide.Elevator=ElevatorOfPlace(OKStreetPlaces().IndexOfByPredicate([LiftPlace](const FOKStreetPlace& P){return &P==LiftPlace;}));S.LiftRide.Floor=Floor;S.LiftRide.Spot=Target;
   if(LiftPlace!=Place)UE_LOG(LogTemp,Display,TEXT("Street outing: %s is upstairs in %s: by its elevator to floor %d"),Place->Id,LiftPlace->Id,Floor);
  }
  else if(Spot){TArray<FVector> In=GridRoute(Route.Last(),(*Spot));if(In.Num()>=2){In.RemoveAt(0);Route.Append(In);}else Route.Add((*Spot));}
  // Going to a building (no spot of an activity): through the door and a few steps in, so they are in the shop, not outside it.
  else{const FVector In=PlaceInsideSpot(*Place);
   if(In!=Place->Door){TArray<FVector> Steps=GridRoute(Route.Last(),In);if(Steps.Num()>=2){Steps.RemoveAt(0);Route.Append(Steps);}}}
 }
 return true;
}

// How long the walk is, and what of her day it runs into: she knows it, the model decides (go on, or say she has to go).
// 贞德 said "I have class at 13:30" at 12:47 and set off with him for the park: 69 minutes on foot, there at 13:56, and
// she remembered the class only when he asked (R6-188b). The walk at the outing's pace (OKStreetOutingWalkMPerMin, R6-235).
// Also after a ride down from upstairs (StepLiftRide): from the ramen shop on the department store's 9F to the cafe was two
// hours on foot in the rain, and she was never told, nor offered the bus or a taxi (R6-230).
void AOKStreetSocialScene::TellOutingWalk(int32 Girl,const FOKStreetPlace& Place,const TArray<FVector>& Route){
 auto& S=*State;
 float Length=0;for(int32 K=1;K<Route.Num();++K)Length+=float(FVector::Dist2D(Route[K-1],Route[K]));
 const int32 Minutes=FMath::CeilToInt(Length/100.f/OKStreetOutingWalkMPerMin);
 // Already at the place (in it, or at its door): the walk is a few steps inside, not a trip. Told "12 minutes to the
 // boys' dorm" at its door for the lounge 28 m in, she found it too far and called it off (activity audit 11-11).
 const bool AtPlace=OKStreetInsidePlace(Place,S.Male)||FVector::Dist2D(S.Male,Place.Door)<500.f;
 if(Minutes<10||AtPlace)return;
 const int64 NowMin=OKStreetMindNow(S);const int32 Day=int32(NowMin%1440);const int32 Arrive=Day+Minutes;
 FString Note=OKMsg(TEXT("ui.outing.walk_minutes_tell_her"),{{TEXT("place"),Place.Name},{TEXT("minutes"),Minutes},{TEXT("arrive"),FString::Printf(TEXT("%02d:%02d"),Arrive/60%24,Arrive%60)}});
 if(const auto* Plan=S.Plans.Find(Girl))for(const auto& B:*Plan)if((B.Kind==TEXT("class")||B.Kind==TEXT("work"))&&B.Start>Day&&B.Start<Arrive+30){
  const FOKStreetPlace* At=OKStreetFindPlace(B.Place);
  Note+=OKMsg(TEXT("ui.outing.walk_runs_into_plan"),{{TEXT("at"),FString::Printf(TEXT("%02d:%02d"),B.Start/60%24,B.Start%60)},{TEXT("doing"),OKPhoneDoingWord(B.Kind)},{TEXT("place"),At?FString(At->Name):B.Place}});
  UE_LOG(LogTemp,Display,TEXT("Street outing: the %d-minute walk runs into actor=%d's %s at %02d:%02d"),Minutes,Girl,*B.Kind,B.Start/60,B.Start%60);break;}
 // The bus and the taxi for it (R6-203): she hears them with the minutes, he sees them as buttons.
 // Set down at the street door: for a place upstairs (the aquarium on the civic centre's 3F) the door of the building it
 // is in, whose lift takes them up. Its own door upstairs had the taxi leave them on the 3F (R6-234).
 FVector Drop=Place.Door;
 if(OKStreetUpstairs(Drop))for(const auto& Q:OKStreetPlaces())if(&Q!=&Place&&!Q.Rooms.IsEmpty()&&!OKStreetUpstairs(Q.Door)&&OKStreetInsidePlace(Q,Place.Door)){Drop=Q.Door;break;}
 Note+=QuoteTransit(Girl,Length,Drop);
 S.TellHer.Add(Note);
}

bool AOKStreetSocialScene::StartOutingActivity(int32 Girl,const FString& ActivityId,FString& Error){
 auto& S=*State;
 // What she ordered on the way here goes to the counter now that they are in the shop (the rest stays for later).
 if(TArray<FOKStreetCartLine>* Carried=S.CarriedOrders.Find(Girl)){const FString Shop=ShopPlaceHere();int32 Added=0;
  for(int32 K=Carried->Num()-1;K>=0;--K)if(const auto* Item=S.Catalog.Find((*Carried)[K].ItemId);Item&&Item->Place==Shop){S.ShopPlace=Shop;S.Cart.Add((*Carried)[K]);Carried->RemoveAt(K);++Added;}
  if(Carried->IsEmpty())S.CarriedOrders.Remove(Girl);
  if(Added>0){UE_LOG(LogTemp,Display,TEXT("Street order carried: %d lines ordered at %s on arrival"),Added,*Shop);PlaceChatOrder(Girl,S.CarriedOrderSaid.FindRef(Girl));}}
 const FOKStreetActivity* A=OKStreetFindActivity(ActivityId);
 if(!A){ResumeTalkQuiet(Girl);return true;}
 // Still possible now they are here (it may have started raining on the way); what it uses up goes when it ends.
 if(!ActivityCheck(Girl,ActivityId,Error,false))return false;
 // Closed when they arrive (the walk took them past closing time): no meal, no drink.
 if(A->Place&&*A->Place){FString Why;if(PlaceClosedNow(A->Place,Why)&&PlaceClosedAt(A->Place,StreetNow()+FTimespan::FromMinutes(15),Why)){Error=Why;return false;}}
 // Solo: at the place's spot she does its action (shopping, watching the fish, the sky, stretching) beside him;
 // with a male curve too (praying) he does it as well. Ends when he walks off.
 if(A->Kind==EOKStreetActivityKind::Solo){
  const FOKStreetPlace* Place=OKStreetFindPlace(A->Place);
  const FOKStreetModelAnchor* Spot=Place?OKStreetPlaceAnchor(*Place,A->Anchor):nullptr;
  if(!Spot||!A->FemaleClip){Error=OKT(TEXT("ui.outing.cannot_do_here"));return false;}
  StopAmbientActivity();EndTalk();if(S.Companion==Girl)FinishCompanion();
  const FRotator Facing(0,Spot->Yaw+A->Turn,0);FString Ignore;
  S.Male=Spot->Position;S.Rotations[0]=Facing;if(ActivitySettles(A->Anchor))SettleOnFloor(S.Male,Facing.Yaw,A->Id);
  // In the city she stands a little behind his side: what he faces (a vending machine 1.2 m wide, a shelf) is in front, and
  // level with him she was inside it; a prop without collision is not seen by the settle.
  auto& Agent=S.Agents[Girl-1];Agent.Position=S.Male+Facing.RotateVector(FVector(OKStreetCityMode()?-60.f:0.f,110,0));if(ActivitySettles(A->Anchor))SettleOnFloor(Agent.Position,Facing.Yaw,A->Id);Agent.Held=true;S.Rotations[Girl]=Facing;
  if(!OKPrewarmCrowdRuntimeAction(this,Girl,A->FemaleClip,Ignore)){Error=OKT(TEXT("ui.outing.action_not_ready_label"))+Ignore;Agent.Held=false;return false;}
  // He does the same thing beside her unless the activity names his own action.
  const TCHAR* MaleClip=A->MaleClip?A->MaleClip:A->FemaleClip;
  const bool MaleOk=OKPrewarmCrowdRuntimeAction(this,0,MaleClip,Ignore);if(!MaleOk)UE_LOG(LogTemp,Warning,TEXT("Street solo: male clip %s: %s"),MaleClip,*Ignore);
  if(A->Effect&&*A->Effect)StartEffect(A->Effect,Girl); // her spell, far off over the field
  S.SoloGirl=Girl;S.SoloPhase=1;S.SoloSpot=S.Male;S.SoloHerOffset=Agent.Position-S.Male;S.SoloYaw=Facing.Yaw;S.SoloFemale=A->FemaleClip;S.SoloMale=MaleOk?MaleClip:TEXT("");S.SoloWhat=A->Name;S.SoloId=A->Id;S.SoloAt=SceneTime();
  // It takes its time (game minutes, the rules' table) and then ends by itself: praying is over, the fish watched.
  S.SoloStartMinute=OKStreetMindNow(S);{auto Request=OKRulesRequest(TEXT("activity_minutes"));Request->SetStringField(TEXT("id"),A->Id);Request->SetStringField(TEXT("kind"),TEXT("solo"));Request->SetNumberField(TEXT("code"),A->Code);
   const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);S.SoloMinutes=Answer.IsValid()?int32(Answer->GetNumberField(TEXT("minutes"))):20;}
  // In front of a machine the camera looks over their shoulders at it; elsewhere it shows their faces.
  const bool Machine=FCString::Strcmp(A->Anchor,TEXT("vending"))==0;
  S.Yaw=Facing.Yaw+(Machine?35:150);S.Pitch=Machine?-18:-12;S.Distance=360;
  S.Message=OKMsg(TEXT("ui.outing.speaker_line_walkaway"), {{TEXT("girl_name"), *S.Manifest.Characters[Girl].Name}, {TEXT("speaker_name"), A->Name}});RefreshUI();
  UE_LOG(LogTemp,Display,TEXT("Street solo: actor=%d %s clip=%s male=%s"),Girl,A->Id,A->FemaleClip,A->MaleClip?A->MaleClip:TEXT("-"));
  return true;
 }
 // Sleep: the outing ends at the bed; lie down (she takes the next bed if there is one).
 if(A->Kind==EOKStreetActivityKind::Sleep){
  const FOKStreetPlace* Place=OKStreetFindPlace(A->Place);
  const FOKStreetModelAnchor* Bed=Place?OKStreetPlaceAnchor(*Place,A->Anchor):nullptr;
  if(!Bed){Error=OKT(TEXT("ui.outing.no_bed_here"));return false;}
  return StartSleep(*Bed,Place,Girl);
 }
 // Restroom: they walk to the door (the 'wait' spot); she goes into the women's room and comes back out.
 if(A->Kind==EOKStreetActivityKind::Restroom){
  const FOKStreetPlace* Place=OKStreetFindPlace(A->Place);
  const FOKStreetModelAnchor* Women=Place?OKStreetPlaceAnchor(*Place,TEXT("women")):nullptr;
  if(!Women){Error=OKT(TEXT("ui.outing.no_restroom_here"));return false;}
  StopAmbientActivity();EndTalk();if(S.Companion==Girl)FinishCompanion();
  if(const FOKStreetModelAnchor* Wait=OKStreetPlaceAnchor(*Place,TEXT("wait")))S.Male=Wait->Position; // outings end here already
  auto& Agent=S.Agents[Girl-1];Agent.Position=Women->Position;Agent.Held=true;
  S.RestroomGirl=Girl;S.RestroomUntil=SceneTime()+FMath::FRandRange(12.f,18.f);S.RestroomPlace=Place->Id;
  S.Message=OKMsg(TEXT("ui.outing.she_in_ladies_room"), {{TEXT("girl_name"), *S.Manifest.Characters[Girl].Name}});RefreshUI();
  UE_LOG(LogTemp,Display,TEXT("Street restroom: actor=%d went into %s"),Girl,Place->Id);
  return true;
 }
 // At the place's anchor: stand exactly there and lay the pair out its way (tables, shelves, the bath).
 if(A->Kind==EOKStreetActivityKind::Pair||A->Kind==EOKStreetActivityKind::Photo){
  const FOKStreetPlace* Place=OKStreetFindPlace(A->Place);
  if(const FOKStreetModelAnchor* Spot=Place?OKStreetPlaceAnchor(*Place,A->Anchor):nullptr){
   S.Male=Spot->Position;S.NextPairYaw=Spot->Yaw;S.NextPairFemaleClip=A->FemaleClip?A->FemaleClip:TEXT("");S.NextPairMaleClip=A->MaleClip?A->MaleClip:TEXT("");
   S.Agents[Girl-1].Position=S.Male+FRotator(0,Spot->Yaw,0).RotateVector(FVector(0,110,0));
   // A city spot is often the thing itself (the drink shop's counter, the snack bar's table, the bookshop's shelf): stood
   // exactly there he was inside it, and the camera between their heads with him, the view one white counter (activity
   // audit 11-09). Each of the two goes to the nearest open floor round where they were put, on the near side of what
   // they face first. A seat, a bench, a bed or a pool is meant to be sat or lain in: those keep the spot.
   if(ActivitySettles(A->Anchor)){SettleOnFloor(S.Male,Spot->Yaw,A->Id);FVector& Her=S.Agents[Girl-1].Position;Her=S.Male+FRotator(0,Spot->Yaw,0).RotateVector(FVector(0,110,0));SettleOnFloor(Her,Spot->Yaw,A->Id);}
  }
 }
 // Which activity this is, also when it starts where they already stand (no walk, no ArriveOuting): without it reading
 // side by side in the bookshop read as "sitting and talking", and his quiet reading drew silence nudges until she left.
 S.LastActivity=ActivityId;S.LastActivityGirl=Girl;S.LastActivityAt=SceneTime();
 switch(A->Kind){
  case EOKStreetActivityKind::Pair:BeginPair(Girl,A->Code);break;
  case EOKStreetActivityKind::Photo:BeginPhoto(Girl);break;
  case EOKStreetActivityKind::Facility:BeginFacility(A->Code,Girl);break;
  // code 1: a run around the place they are in (jogging in the park), the rules' table says so.
  // code 2: a photo walk (a stroll with stops where he photographs her, one album).
  case EOKStreetActivityKind::Walk:if(A->Code==1||A->Code==2){BeginStroll(Girl,Error,A->Code==1);if(!Error.IsEmpty())return false;S.StrollActivity=A->Id;S.StrollStartMinute=OKStreetMindNow(S);
   S.PhotoWalkStops=0;S.PhotoWalkPauseUntil=0;S.PhotoWalkAlbum=A->Code==2?FString::Printf(TEXT("walk:%lld"),OKStreetMindNow(S)):FString();
   // Told as what it is: the run with 贞德 they had agreed on read "taking a walk nearby" (R6-148).
   S.Message=OKMsg(TEXT("ui.outing.activity_route_together"),{{TEXT("girl_name"),*S.Manifest.Characters[Girl].Name},{TEXT("activity"),OKStreetActivityName(A->Id)}});RefreshUI();return true;}BeginCompanion(Girl);break;
 }
 const bool Started=S.Pair.Partner==Girl||S.Facility!=INDEX_NONE||S.Companion==Girl;
 if(!Started)Error=S.Message.IsEmpty()?OKMsg(TEXT("ui.outing.cannot_do_action_now"), {{TEXT("action_name"), A->Name}}):S.Message;
 return Started;
}

// Back to talking with her without the scripted greeting line (after an activity or an outing).
void AOKStreetSocialScene::ResumeTalkQuiet(int32 Girl){
 auto& S=*State;
 if(!S.FreeTalkOpen||S.Target==Girl||!S.Manifest.Characters.IsValidIndex(Girl)){UE_LOG(LogTemp,Display,TEXT("Street talk: no talk to resume with actor %d (open=%d target=%d)"),Girl,S.FreeTalkOpen?1:0,S.Target);return;}
 S.QuietTalk=true;
 if(!BeginTalk(Girl)){S.QuietTalk=false;UE_LOG(LogTemp,Display,TEXT("Street talk: could not resume the talk with actor %d (companion=%d facility=%d pair=%d)"),Girl,S.Companion,S.Facility,S.Pair.Partner);}
 S.FreeTalkOpen=true;
}

// What the pair is doing right now, for the model, and what is on their table.
FString AOKStreetSocialScene::FreeTalkDoing() const{
 if(!State)return FString();const auto& S=*State;
 // What is on the table and how far along, whatever they sit at: told only "eating together", 胡桃 said "the noodles
 // are here" three times before they came; 安可 at a café seat was told only "sitting and chatting".
 FString Table;
 if(!S.Table.IsEmpty()){
  TArray<FString> Dishes;
  for(const auto& D:S.Table){
   const FString Whose=OKT(D.ForHer&&(D.Her==INDEX_NONE||D.Her==FreeTalkPartner())?TEXT("ui.outing.table_yours"):D.ForHer?TEXT("ui.outing.table_others"):TEXT("ui.outing.table_his"));
   Dishes.Add(OKMsg(!D.Served?TEXT("ui.outing.table_dish_pending"):D.Percent>=99.f?TEXT("ui.outing.table_dish_untouched"):TEXT("ui.outing.table_dish_left"),{{TEXT("whose"),Whose},{TEXT("item"),D.Name},{TEXT("percent"),FMath::RoundToInt(D.Percent)}}));
  }
  Table=OKMsg(TEXT("ui.outing.table_now"),{{TEXT("dishes"),FString::Join(Dishes,OKT(TEXT("ui.outing.table_sep")))}});
 }
 return FreeTalkActivity()+Table;
}

FString AOKStreetSocialScene::FreeTalkActivity() const{
 if(State){const int32 Lift=ElevatorWithMale();if(Lift!=INDEX_NONE){const auto& E=State->Elevators[Lift];return OKMsg(TEXT("ui.outing.in_elevator_at_place"), {{TEXT("place_name"), OKStreetPlaces()[E.Place].Name}, {TEXT("floor_label"), E.Phase==4?OKT(TEXT("ui.outing.elevator_moving_label")):*E.Labels[E.Floor]}});}}
 const auto& S=*State;
 if(S.OutingGirl!=INDEX_NONE){
  const FOKStreetActivity* A=OKStreetFindActivity(S.OutingActivity);
  // How far is still left: told only "walking to the dorm", 胡桃 said "here's the door, see you tomorrow" with most of
  // the walk ahead (R6-26).
  float Left=0.f;if(S.OutingRoute.IsValidIndex(S.OutingStep)){Left=FVector::Dist2D(S.Male,S.OutingRoute[S.OutingStep]);
   for(int32 K=S.OutingStep+1;K<S.OutingRoute.Num();++K)Left+=FVector::Dist2D(S.OutingRoute[K-1],S.OutingRoute[K]);}
  const FString Way=Left>=500.f?OKMsg(TEXT("ui.outing.walking_left"),{{TEXT("meters"),FMath::RoundToInt(Left/100.f)}}):FString();
  // A run or a photo walk is the activity itself, under way: told "walking somewhere nearby", "after the run, breakfast"
  // set off for the cafeteria five minutes into the run with 贞德 (R6-149).
  if(!S.StrollActivity.IsEmpty())return OKMsg(TEXT("ui.outing.doing_route_activity_now"),{{TEXT("activity_name"),OKStreetActivityName(S.StrollActivity)}});
  return (A?OKMsg(TEXT("ui.outing.walking_prepare_activity"), {{TEXT("outing_place"), *S.OutingPlace}, {TEXT("activity_name"), A->Name}}):OKMsg(TEXT("ui.outing.walking_with_player_to"), {{TEXT("outing_place"), *S.OutingPlace}}))+Way;
 }
 if(S.Pair.Partner!=INDEX_NONE){
  const auto& P=S.Pair;
  return P.Bath?OKT(TEXT("ui.outing.onsen_together_now")):P.Meal?OKT(TEXT("ui.outing.eating_together_now")):P.Drink?OKT(TEXT("ui.outing.drinking_together_now")):P.Seated?OKT(TEXT("ui.outing.sitting_chatting_now")):P.PhoneUse?OKT(TEXT("ui.outing.phone_together_now")):P.Splash?OKT(TEXT("ui.outing.splash_game_now")):P.Watermelon?OKT(TEXT("ui.outing.playing_watermelon_now")):OKT(TEXT("ui.outing.group_photo_now"));
 }
 if(S.Facility!=INDEX_NONE)return S.Facility==0?OKT(TEXT("ui.outing.dining_private_room_now")):S.Facility==1?OKT(TEXT("ui.outing.resting_room_now")):OKT(TEXT("ui.outing.oil_treatment_room_now"));
 if(S.Companion!=INDEX_NONE)return OKT(TEXT("ui.outing.follow_player_no_destination"));
 if(S.RestroomGirl!=INDEX_NONE)return OKT(TEXT("ui.outing.in_ladies_room_talk_hint"));
 if(S.SoloGirl!=INDEX_NONE)return OKMsg(TEXT("ui.outing.with_player_doing"), {{TEXT("solo_activity"), *S.SoloWhat}});
 if(S.SleepPhase!=0)return OKMsg(TEXT("ui.outing.in_bed_preparing_sleep"), {{TEXT("sleep_place"), *S.SleepPlace}});
 for(const auto& Place:OKStreetPlaces())if(const int32 Floor=OKStreetPlaceFloor(Place,S.Male)){
  const auto Lifts=OKStreetPlaceLifts(Place);
  if(Lifts.IsValidIndex(Floor-1))return OKMsg(TEXT("ui.outing.standing_chat_on_floor"), {{TEXT("place_name"), Place.Name}, {TEXT("lift_label"), *OKStreetLiftLabel(*Lifts[Floor-1])}});
  return OKMsg(TEXT("ui.outing.standing_chat_inside"), {{TEXT("place_name"), Place.Name}});
 }
 return OKT(TEXT("ui.outing.standing_chat_label"));
}

// Nearby places for the model: name, distance and compass direction from the player.
FString AOKStreetSocialScene::FreeTalkNearby() const{
 TArray<FString> Items;
 // A place not open now says so, with its hours ("not open yet, 7-19"): she knows the cafeteria opens at seven, not
 // eleven, and that it opens in five minutes.
 for(const FOKStreetPlace* P:NearbyPlaces(4000)){FString Why;const bool Closed=PlaceClosedNow(P->Id,Why);
  Items.Add(OKMsg(Closed?TEXT("ui.outing.person_compass_distance_closed"):TEXT("ui.outing.person_compass_distance"), {{TEXT("name"), P->Name}, {TEXT("compass"), *OKStreetCompass(State->Male,P->Door)}, {TEXT("distance_m"), FVector::Dist2D(State->Male,P->Door)/100.f}, {TEXT("why"), Why}}));}
 // The ones farther off that are closed now, too: at 08:42 安可 proposed the bookstore "since the department store is
 // not open yet", and the bookstore opened at ten; neither was near enough to be listed with its hours.
 TArray<FString> FarClosed;const auto Near=NearbyPlaces(4000);
 for(const auto& P:OKStreetPlaces())if(!Near.Contains(&P)){FString Why;if(PlaceClosedNow(P.Id,Why))FarClosed.Add(FString(P.Name)+OKMsg(TEXT("ui.outing.far_closed_why"),{{TEXT("why"),Why}}));}
 FString Out=Items.IsEmpty()?OKT(TEXT("ui.outing.no_special_place_nearby")):FString::Join(Items,OKT(TEXT("ui.bank.list_separator")));
 if(!FarClosed.IsEmpty())Out+=OKMsg(TEXT("ui.outing.far_closed_places"),{{TEXT("places"),FString::Join(FarClosed,OKT(TEXT("ui.bank.list_separator")))}});
 // And that the rest are open: with nothing said of the library, 安可 dropped her own 14:00 library plan because "it
 // is closed today" while 优香 and she were both in it within the hour.
 Out+=OKT(TEXT("ui.outing.others_open_now"));
 return Out;
}

// Panel buttons for place activities go through the same outing as free talk, and the same yes or no: she is asked
// (the invitation rules) unless she already agreed in conversation.
void AOKStreetSocialScene::StartActivityFromPanel(int32 Girl,const FString& ActivityId,bool bAgreed){
 FString Error;
 if(!bAgreed&&!PanelConsent(Girl,ActivityId))return; // the same yes or no as everywhere (Life.inl)
 if(!BeginOuting(Girl,ActivityId,Error)){State->Message=Error;RefreshUI();}
}
