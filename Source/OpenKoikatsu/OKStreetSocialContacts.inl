// Included after scene state/UI definitions. All reservations belong to this scene.
#include "OKStreetSocialPrivateEnv.h"
bool AOKStreetSocialScene::ContactReady(int32 Character) const {
 if(!State||!State->Agents.IsValidIndex(Character-1)||!State->Manifest.Characters.IsValidIndex(Character))return false;
 if(State->OnaniGirl==Character)return false; // touching herself on the street: nobody calls her or brings her over (OKStreetSocialOnani.inl)
 FOKRuntimeCharacterStatus M,N;return OKGetCrowdRuntimeCharacterStatus(const_cast<AOKStreetSocialScene*>(this),0,M)&&OKGetCrowdRuntimeCharacterStatus(const_cast<AOKStreetSocialScene*>(this),Character,N)&&M.Visible&&N.Visible&&N.ActionsReady&&M.Error.IsEmpty()&&N.Error.IsEmpty();
}
bool AOKStreetSocialScene::ContactLover(int32 Character) const {return State&&State->Manifest.Characters.IsValidIndex(Character)&&OKStreetViewRelation(State->Store,OKStreetStableId(State->Manifest.Characters[Character]),State->Manifest.TalkBudget).Stage==TEXT("lover");}
bool AOKStreetSocialScene::ContactIdle() const {if(!State)return false;const auto& S=*State;return S.PrivateGirl==INDEX_NONE&&S.Pair.Partner==INDEX_NONE&&S.Facility==INDEX_NONE&&S.Companion==INDEX_NONE&&!OKStreetConversationBusy(S.Node!=INDEX_NONE,S.CollectedActive,S.RelationshipPending,S.TouchActive);}
// Only sitting and talking with this girl in the way of a contact: nothing else going on (a photo being taken, a meal).
bool AOKStreetSocialScene::SeatedWith(int32 Girl) const {if(!State)return false;const auto& S=*State;return S.Pair.Partner==Girl&&S.Pair.Conversation()&&!S.Pair.CapturePending&&S.PrivateGirl==INDEX_NONE&&S.Facility==INDEX_NONE&&S.Companion==INDEX_NONE&&!OKStreetConversationBusy(S.Node!=INDEX_NONE,S.CollectedActive,S.RelationshipPending,S.TouchActive);}
// The city's long way: the road graph between, the fine grid out of the building he is in and into the one he is going to
// (the graph has no points indoors).
TArray<FVector> AOKStreetSocialScene::CityRoute(const FVector& From,const FVector& To) const{
 // Into a building and out of one: by its door. The graph's point nearest a spot indoors was the pavement behind the
 // wall (三月七 at the cafeteria's table: east of its east wall), the grid from there found no way in in its 4 ms, and the
 // walk ended against that wall, "the way is blocked" (R6-173). The door is on the graph, so the roads lead to it.
 auto Indoor=[](const FVector& At)->const FOKStreetPlace*{for(const auto& P:OKStreetPlaces())if(!P.Outdoor&&!P.Rooms.IsEmpty()&&OKStreetInsidePlace(P,At))return &P;return nullptr;};
 // A room in a building (the dentist in the civic centre): its door is indoors too, in the corridor, and the roads
 // ended on the pavement 24 m away behind the wall (places_check, 11-09). The way in and out is the building's door.
 auto Outer=[](const FOKStreetPlace* P)->const FOKStreetPlace*{
  for(int32 Guard=0;P&&Guard<4;++Guard){const FOKStreetPlace* Around=nullptr;
   for(const auto& Q:OKStreetPlaces())if(&Q!=P&&!Q.Outdoor&&!Q.Rooms.IsEmpty()&&FMath::Abs(Q.Door.Z-P->Door.Z)<150.f&&FVector::Dist2D(Q.Door,P->Door)>50.f&&OKStreetInsidePlace(Q,P->Door)&&!OKStreetInsidePlace(*P,Q.Door)){Around=&Q;break;}
   if(!Around)break;P=Around;}
  return P;};
 const FOKStreetPlace* Into=Outer(Indoor(To));const FOKStreetPlace* OutOf=Outer(Indoor(From));
 // Both in one building on one floor (47 m apart on the EE building's 4F, 優香 at her class): the floor's own way, not the
 // street's roads down on the ground, which led him into the 4F's wall till "the way is blocked" (R6-177).
 if(Into&&Into==OutOf&&FMath::Abs(From.Z-To.Z)<150.f){TArray<FVector> Here=GridRoute(From,To);return Here.Num()>=2?Here:TArray<FVector>{From,To};}
 if(Into&&Into!=OutOf&&FVector::Dist2D(Into->Door,To)>50.f){
  const FVector Door=Into->Door;TArray<FVector> Route=CityRoute(From,Door);if(Route.IsEmpty())Route={From};
  // On her floor, in from the door; upstairs the navigation plans the lift from the door (PlanNavLift).
  if(FMath::Abs(Door.Z-To.Z)<150.f){TArray<FVector> In=GridRoute(Door,To);
   if(In.Num()>=2){In.RemoveAt(0);Route.Append(In);}
   else{const FVector Inside=PlaceInsideSpot(*Into);if(!Inside.Equals(Door,1.f))Route.Add(Inside);Route.Add(To);}}
  return Route;}
 if(OutOf&&OutOf!=Into&&FVector::Dist2D(OutOf->Door,From)>50.f&&FMath::Abs(OutOf->Door.Z-From.Z)<150.f){
  const FVector Door=OutOf->Door;TArray<FVector> Route=GridRoute(From,Door);
  if(Route.Num()<2){Route={From};const FVector Inside=PlaceInsideSpot(*OutOf);if(!Inside.Equals(Door,1.f))Route.Add(Inside);Route.Add(Door);}
  TArray<FVector> Rest=CityRoute(Door,To);if(!Rest.IsEmpty())Rest.RemoveAt(0);Route.Append(Rest);
  return Route;}
 TArray<FVector> Route=OKStreetCityRoute(From,To);if(Route.Num()<3)return Route;
 if(!OKStreetCityClear(GetWorld(),From,Route[1],18.f)){TArray<FVector> Out=GridRoute(From,Route[1]);if(Out.Num()>=2){Route.RemoveAt(0,2);Out.Append(Route);Route=MoveTemp(Out);}}
 const int32 Last=Route.Num()-1;
 if(Last>=1&&!OKStreetCityClear(GetWorld(),Route[Last-1],To,18.f)){TArray<FVector> In=GridRoute(Route[Last-1],To);if(In.Num()>=2){Route.RemoveAt(Last-1,2);Route.Append(In);}}
 return Route;
}
TArray<FVector> AOKStreetSocialScene::ContactRoute(const FVector& From,const FVector& To) const {
 if(OKStreetCityMode()&&(OKStreetCityFar(From,To)||FMath::Abs(From.Z-To.Z)>=150.f))return CityRoute(From,To);
 if(FMath::Abs(From.Z-To.Z)<150.f){auto Grid=GridRoute(From,To);if(Grid.Num()>=2)return Grid;}
 TArray<FOKStreetPointData> Shared;OKStreetWaypoints(Shared);TArray<FVector> Points;for(const auto& P:Shared)Points.Add(P.Position);
 return OKStreetContactRoute(From,To,Points,[&](const FVector& A,const FVector& B){
  const int32 Steps=FMath::Max(1,FMath::CeilToInt(FVector::Dist2D(A,B)/25));for(int32 I=0;I<=Steps;++I)if(OKStreetBlockedPoint(FMath::Lerp(A,B,float(I)/Steps),30))return false;
  FHitResult Hit;FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetContactRoute),false,this);const bool Blocked=GetWorld()->SweepSingleByChannel(Hit,A+FVector(0,0,85),B+FVector(0,0,85),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(30,78),Query);if(Blocked&&State->SelfTest)UE_LOG(LogTemp,Verbose,TEXT("Contact route obstructed actor=%s from=%s to=%s"),*GetNameSafe(Hit.GetActor()),*A.ToString(),*B.ToString());return !Blocked;
 });
}
void AOKStreetSocialScene::SelectContact(int32 Character){if(!State||!State->Agents.IsValidIndex(Character-1))return;State->ContactSelection=Character;RefreshUI(OKStreetUi::Right|OKStreetUi::Debug);}
void AOKStreetSocialScene::NavigateGirl(int32 Character){
 // Not ContactReady: it asks for her being drawn, and across the city she is not, so the button did nothing. Her place is enough.
 if(!State||!State->Agents.IsValidIndex(Character-1)||State->OnaniGirl==Character||State->PrivateGirl!=INDEX_NONE)return;auto& S=*State;
 // Talking or in an activity he cannot walk off: say so (as the map does) instead of accepting a route he never walks.
 if(S.Target!=INDEX_NONE||S.Pair.Partner!=INDEX_NONE||S.OutingGirl!=INDEX_NONE||S.Facility!=INDEX_NONE){S.Message=OKT(TEXT("ui.contacts.end_activity_before_nav"));S.ContactsNotice=S.Message;return;}
 // She is on another floor: the navigation takes the elevator (PlanNavLift, in StepNavigation).
 S.NavAround.Reset();S.NavRide=FOKStreetLiftRide();S.NavGirl=Character;S.NavPointActive=false;S.NavAt=0;S.NavStep=1;S.NavReplans=0;S.NavBlockedAt=FVector(1e9);S.NavProgressAt=SceneTime();S.NavPath=ContactRoute(S.Male,S.Agents[Character-1].Position);S.ContactsNotice=OKT(TEXT("ui.contacts.auto_travel_to_her_hint"));}
void AOKStreetSocialScene::NavigatePoint(const FVector& Spot,const FString& Name){
 if(!State)return;auto& S=*State;
 FVector Goal=Spot;if(OKStreetCityMode()&&Goal.Z==0.f)Goal.Z=S.Male.Z; // a spot on the big map has no height
 if(S.Target!=INDEX_NONE||S.PrivateGirl!=INDEX_NONE||S.Pair.Partner!=INDEX_NONE||S.OutingGirl!=INDEX_NONE||S.Facility!=INDEX_NONE){S.Message=OKT(TEXT("ui.contacts.end_activity_before_map_nav"));return;}
 // On his floor the street grid is searched a slice a frame (TickNavSearch, 3 ms each): a long route held the frame
 // 6-8 ms. Another floor: the place graph (doors and corridors), at once.
 S.NavSearch.Reset();
 if(OKStreetCityMode()&&OKStreetCityFar(S.Male,Goal)){NavigatePointAlong(Goal,Name,CityRoute(S.Male,Goal));return;}
 if(FMath::Abs(S.Male.Z-Goal.Z)<150.f){S.NavSearch=MakeShared<FOKStreetGridSearch>();S.NavSearch->From=S.Male;S.NavSearch->To=Goal;S.NavSearchGoal=Goal;S.NavSearchName=Name;return;}
 NavigatePointAlong(Goal,Name,PlaceRouteWaypoints(S.Male,Goal));
}
void AOKStreetSocialScene::TickNavSearch(){
 if(!State||!State->NavSearch)return;auto& S=*State;
 if(!GridSearchStep(*S.NavSearch,FPlatformTime::Seconds()+0.003))return;
 TArray<FVector> Path=MoveTemp(S.NavSearch->Route);const FVector From=S.NavSearch->From;S.NavSearch.Reset();
 if(Path.Num()<2)Path=PlaceRouteWaypoints(From,S.NavSearchGoal); // as PlaceRoute: no grid way, the place graph
 NavigatePointAlong(S.NavSearchGoal,S.NavSearchName,MoveTemp(Path));
}
// The rest of NavigatePoint, once the route is known (computed once, then walked in order).
void AOKStreetSocialScene::NavigatePointAlong(const FVector& Goal,const FString& Name,TArray<FVector>&& Path){
 auto& S=*State;
 // A place's door: on through it into its ground floor. Stopped at the door he was outside it, and its buttons (the
 // menu, applying for a job) were not there.
 FVector Target=Goal;for(const auto& P:OKStreetPlaces())if(!P.Rooms.IsEmpty()&&FVector::Dist2D(P.Door,Goal)<5.f&&FMath::Abs(P.Door.Z-Goal.Z)<100.f){Target=PlaceInsideSpot(P);if(!Target.Equals(Goal,1.f)&&!Path.IsEmpty())Path.Add(Target);break;}
 UE_LOG(LogTemp,Display,TEXT("Street navigation: goal=%s name=%s points=%d"),*Goal.ToCompactString(),*Name,Path.Num());
 // On another floor (he upstairs, or the spot upstairs): the navigation takes an elevator (PlanNavLift); no street
 // route is needed from upstairs.
 const bool Floors=NavNeedsLift(Goal);
 if(Path.IsEmpty()&&!Floors){S.Message=OKT(TEXT("ui.contacts.unreachable_try_elsewhere"));return;}
 if(Path.IsEmpty())Path={S.Male};
 S.NavAround.Reset();S.NavRide=FOKStreetLiftRide();S.NavGirl=INDEX_NONE;S.NavPointActive=true;S.NavPoint=Floors?Target:FVector(Target.X,Target.Y,S.Male.Z);S.NavPointName=Name;S.NavPath=MoveTemp(Path);S.NavStep=1;S.NavReplans=0;S.NavBlockedAt=FVector(1e9);S.NavAt=SceneTime();S.NavProgressAt=S.NavAt;
 S.Message=OKT(TEXT("ui.contacts.auto_travel_button"))+(Name.IsEmpty()?FString(OKT(TEXT("ui.contacts.map_selected_spot"))):Name)+OKT(TEXT("ui.contacts.wasd_cancel_nav_suffix"));
 if(S.BigMapOpen)ToggleBigMap(); // navigation, its notice and the message are bound to state: no rebuild
}
void AOKStreetSocialScene::StopNavigation(const FString& Notice){
 if(!State)return;auto& S=*State;S.NavSearch.Reset();S.NavAround.Reset();S.NavGirl=INDEX_NONE;S.NavPointActive=false;S.NavPath.Reset();S.NavRide=FOKStreetLiftRide();S.ContactsNotice.Reset();
 if(!Notice.IsEmpty())S.Message=Notice;
}
void AOKStreetSocialScene::ToggleBigMap(){
 if(!State)return;auto& S=*State;
 if(!S.BigMapOpen){S.BigMapOpen=true;S.BigMapSavedMouse=S.MouseUI;S.MouseUI=true;}
 else{S.BigMapOpen=false;S.MouseUI=S.BigMapSavedMouse;}
 ApplyMouseMode(true);
}
// Walkable-street grid: a cell is free when a body standing there keeps the same clearance walking needs (30 cm from
// street obstacles and place blocks, no overlap with world collision). Cells are tested when A* first reaches them.
static constexpr float OKStreetNavCell=40.f;
bool AOKStreetSocialScene::NavCellFree(const FIntPoint& Cell,float Z) const{
 auto& Grid=State->NavGrid.FindOrAdd(FMath::RoundToInt(Z/100.f));
 if(const bool* Known=Grid.Find(Cell))return *Known;
 QUICK_SCOPE_CYCLE_COUNTER(STAT_Street_NavCellTest);
 const FVector P(Cell.X*OKStreetNavCell,Cell.Y*OKStreetNavCell,Z);
 bool Free=OKStreetObstacleGap(P,30.f)>30.f;
 // The city's ground is not flat: a cell needs ground near this height, and the body is tested above a step's height.
 float GroundZ=Z;if(Free&&OKStreetCityMode())Free=OKStreetGroundZ(GetWorld(),P,GroundZ,this);
 // Upstairs the floor is flat, and ground 1.2 m down is the floor below: the department store's 4F atrium has no rail on
 // most of its edge, the trace hit the 3F escalator 1-2 m under it, and the route to the optician led him into the void
 // (2460 -> 2303, "she is on another floor"). The street keeps its slopes.
 if(Free&&OKStreetCityMode()&&GroundZ<Z-60.f&&OKStreetUpstairs(P))Free=false;
 if(Free&&OKStreetCityMode())State->NavGround.FindOrAdd(FMath::RoundToInt(Z/100.f)).Add(Cell,GroundZ);
 if(Free){FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetNavCell),false,this);Free=!GetWorld()->OverlapAnyTestByChannel(FVector(P.X,P.Y,GroundZ)+FVector(0,0,OKStreetBodyLift()),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(40,OKStreetBodyHalf()),Query);} // wider than his 28: a cell beside an awning or a sign is not a way
 Grid.Add(Cell,Free);return Free;
}
TArray<FVector> AOKStreetSocialScene::GridRoute(const FVector& From,const FVector& To) const{
 // In the city a walled-in search ran through 60000 cells in one frame (300 ms). 4 ms, then no route: the caller falls back to
 // its other way, and the cells tested stay known, so the next try gets further.
 // Upstairs 25 ms: the floors are small and walled, and every caller falls back to a straight line, which from the optician
 // on the department store's 4F went through the shop's wall to the lift ("the way is blocked") or across the atrium.
 // Inside a building on its ground floor too: from the department store's lift to its door, 4 ms was never enough among
 // the shops, the straight line ran into a shop wall, and he and Raiden circled the 1F for three hours (R6-183).
 const double Budget=!OKStreetCityMode()?TNumericLimits<double>::Max():OKStreetUpstairs(From)||!PlaceHere(From).IsEmpty()?.025:.004;
 FOKStreetGridSearch G;G.From=From;G.To=To;GridSearchStep(G,FPlatformTime::Seconds()+Budget);return MoveTemp(G.Route);
}
bool AOKStreetSocialScene::GridSearchStep(FOKStreetGridSearch& G,double Deadline) const{
 if(G.Phase==2)return true;
 const float Z=G.From.Z;const FVector From=G.From,To=G.To;
 auto ToCell=[](const FVector& P){return FIntPoint(FMath::RoundToInt(P.X/OKStreetNavCell),FMath::RoundToInt(P.Y/OKStreetNavCell));};
 auto Centre=[Z](const FIntPoint& C){return FVector(C.X*OKStreetNavCell,C.Y*OKStreetNavCell,Z);};
 if(G.Phase==0){
  G.Z=Z;G.Start=ToCell(From);G.Goal=ToCell(To);G.Phase=2;
  // A goal on a counter, a door frame or a bench: the nearest free cell around it.
  if(!NavCellFree(G.Goal,Z)){
   bool Found=false;
   for(int32 R=1;R<=6&&!Found;++R)for(int32 DX=-R;DX<=R&&!Found;++DX)for(int32 DY=-R;DY<=R;++DY){
    if(FMath::Max(FMath::Abs(DX),FMath::Abs(DY))!=R)continue;const FIntPoint C=G.Goal+FIntPoint(DX,DY);if(NavCellFree(C,Z)){G.Goal=C;Found=true;break;}}
   if(!Found)return true;
  }
  if(G.Start==G.Goal){G.Route={From,To};return true;}
  G.Lo=FIntPoint(FMath::Min(G.Start.X,G.Goal.X)-60,FMath::Min(G.Start.Y,G.Goal.Y)-60);G.Hi=FIntPoint(FMath::Max(G.Start.X,G.Goal.X)+60,FMath::Max(G.Start.Y,G.Goal.Y)+60);
  G.W=G.Hi.X-G.Lo.X+1;const int32 Cells=G.W*(G.Hi.Y-G.Lo.Y+1);
  {QUICK_SCOPE_CYCLE_COUNTER(STAT_Street_GridAlloc);G.Cost.Init(TNumericLimits<float>::Max(),Cells);G.Came.SetNumUninitialized(Cells);G.Cell.SetNumZeroed(Cells);}
  G.Phase=1;
 }
 const FIntPoint Start=G.Start,Goal=G.Goal,Lo=G.Lo,Hi=G.Hi;
 // Near the start, cells too close to a wall are allowed (dearly), so standing by one never traps him.
 // A cell he was stopped walking into (a thin wall between two free cell centres) is not passable, even next to the start.
 const TSet<FIntPoint>* Learned=State->NavLearned.Find(FMath::RoundToInt(Z/100.f));
 const TMap<FIntPoint,float>* Grounds=OKStreetCityMode()?State->NavGround.Find(FMath::RoundToInt(Z/100.f)):nullptr;
 const int32 W=G.W;
 auto Index=[&](const FIntPoint& C){return (C.X-Lo.X)+(C.Y-Lo.Y)*W;};
 auto Known=[&](const FIntPoint& C)->uint8{
  if(C.X<Lo.X||C.Y<Lo.Y||C.X>Hi.X||C.Y>Hi.Y)return 1|(NavCellFree(C,Z)?2:0)|(Learned&&Learned->Contains(C)?4:0);
  uint8& K=G.Cell[Index(C)];if(!K)K=1|(NavCellFree(C,Z)?2:0)|(Learned&&Learned->Contains(C)?4:0);return K;};
 auto Passable=[&](const FIntPoint& C){const uint8 K=Known(C);if(K&4)return false;return (K&2)||FMath::Max(FMath::Abs(C.X-Start.X),FMath::Abs(C.Y-Start.Y))<=1;};
 auto Heuristic=[&](const FIntPoint& C){const float DX=FMath::Abs(C.X-Goal.X),DY=FMath::Abs(C.Y-Goal.Y);return DX+DY+(UE_SQRT_2-2.f)*FMath::Min(DX,DY);};
 auto& Came=G.Came;auto& Cost=G.Cost;auto& Open=G.Open;
 auto Less=[](const TPair<float,FIntPoint>& A,const TPair<float,FIntPoint>& B){return A.Key<B.Key;};
 static const FIntPoint Steps[]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
 auto Release=[&G](){G.Cost.Empty();G.Came.Empty();G.Cell.Empty();G.Open.Empty();G.Path.Empty();};
 if(G.Phase==1){
 if(G.Expanded==0&&Open.IsEmpty()&&Cost[Index(Start)]!=0.f){Cost[Index(Start)]=0.f;Open.HeapPush({Heuristic(Start),Start},Less);}
 bool Reached=false;
 while(!Open.IsEmpty()&&G.Expanded<60000){
  // Out of time: the search goes on from here next slice (the open list, costs and links are kept).
  if((G.Expanded&31)==0&&FPlatformTime::Seconds()>Deadline)return false;
  TPair<float,FIntPoint> Top;Open.HeapPop(Top,Less);const FIntPoint C=Top.Value;const float Here=Cost[Index(C)];
  if(Top.Key>Here+Heuristic(C)+.01f)continue; // stale entry
  if(C==Goal){Reached=true;break;}
  ++G.Expanded;
  for(const FIntPoint& D:Steps){
   const FIntPoint N=C+D;if(N.X<Lo.X||N.Y<Lo.Y||N.X>Hi.X||N.Y>Hi.Y||!Passable(N))continue;
   // The city's ground under the next cell no higher or lower than a step: the cell test finds ground on top of a bench or
   // the playground's exercise machines (56 cm up), his walk cannot step up there, and every way round crossed the
   // machine again; he stood against it for half an hour on the way to the playground.
   if(Grounds&&FMath::Abs(Grounds->FindRef(N,Z)-Grounds->FindRef(C,Z))>40.f)continue;
   if(D.X!=0&&D.Y!=0&&(!Passable(FIntPoint(C.X+D.X,C.Y))||!Passable(FIntPoint(C.X,C.Y+D.Y))))continue; // no cutting corners
   const float Step=(D.X!=0&&D.Y!=0?UE_SQRT_2:1.f)*(Known(N)&2?1.f:8.f);
   const int32 NI=Index(N);const float New=Here+Step;
   if(New<Cost[NI]){Cost[NI]=New;Came[NI]=Index(C);Open.HeapPush({New+Heuristic(N),N},Less);}
  }
 }
 if(!Reached){G.Phase=2;UE_LOG(LogTemp,Display,TEXT("Street grid route: none from %s to %s (%d cells)"),*From.ToCompactString(),*To.ToCompactString(),G.Expanded);Release();return true;}
 TArray<FIntPoint>& Cells=G.Path;Cells={Goal};while(Cells.Last()!=Start){const int32 P=Came[Index(Cells.Last())];Cells.Add(FIntPoint(Lo.X+P%W,Lo.Y+P/W));}
 Algo::Reverse(Cells);
 // The pull still asks what is known of the cells (Cell), not the costs or links.
 G.Cost.Empty();G.Came.Empty();G.Open.Empty();G.Route={From};G.PullI=0;G.PullJ=-1;G.Phase=3;
 }
 // Pull the string: keep only the corners a straight walk cannot cut.
 // A straight line between two cell centres can still clip the corner of something between the cell centres: the body-sized
 // sweep along it must also be clear, or the walk stops at that corner ("the way is blocked") in the open street.
 FCollisionQueryParams SweepQuery(SCENE_QUERY_STAT(StreetGridClear),false,this);
 auto Clear=[&](const FVector& A,const FVector& B){
  const int32 N=FMath::Max(1,FMath::CeilToInt(FVector::Dist2D(A,B)/(OKStreetNavCell*.5f)));
  for(int32 I=1;I<N;++I)if(!Passable(ToCell(FMath::Lerp(A,B,float(I)/N))))return false;
  FHitResult Hit;
  // Starting against a wall counts as clear only when the line leads away from it (as StreetStep backs out of one).
  if(GetWorld()->SweepSingleByChannel(Hit,FVector(A.X,A.Y,Z)+FVector(0,0,OKStreetBodyLift()),FVector(B.X,B.Y,Z)+FVector(0,0,OKStreetBodyLift()),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(30,OKStreetBodyHalf()),SweepQuery)&&(!Hit.bStartPenetrating||FVector::DotProduct((B-A).GetSafeNormal2D(),Hit.Normal)<=0.f))return false;
  return true;};
 QUICK_SCOPE_CYCLE_COUNTER(STAT_Street_GridPull);
 // A slice at a time too: out of time between two tries, it goes on from the same corner and cell next slice.
 const TArray<FIntPoint>& Cells=G.Path;TArray<FVector>& Route=G.Route;
 while(G.PullI<Cells.Num()-1){const int32 I=G.PullI;if(G.PullJ<0)G.PullJ=Cells.Num()-1;
  while(G.PullJ>I+1&&!Clear(I==0?From:Centre(Cells[I]),Centre(Cells[G.PullJ]))){--G.PullJ;if(FPlatformTime::Seconds()>Deadline)return false;}
  Route.Add(Centre(Cells[G.PullJ]));G.PullI=G.PullJ;G.PullJ=-1;}
 if(Goal==ToCell(To)&&Clear(Route.Last(),To))Route.Last()=To;
 G.Phase=2;Release();return true;
}
// How near his feet may come to a heroine's (her body and his, side by side).
static constexpr float OKStreetHeroineBody=60.f; // sitting, her knees reach forward of her feet
FVector AOKStreetSocialScene::StreetStep(const FVector& From,const FVector& Direction,float Distance) const{
 constexpr float Clearance=30.f;
 FVector D=Direction;D.Z=0;if(Distance<=0||!D.Normalize())return From;
 const float Here=OKStreetObstacleGap(From,Clearance+10.f); // compared only below the clearance (and 3 cm more)
 FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetStep),false,this);
 auto Free=[&](const FVector& To){
  // Into an obstacle's clearance is blocked, but backing out of one he is already too close to never is. Along a wall at
  // the clearance's edge (30 here, 29 a step on) he may slide: a few centimetres closer, never under 25 (the capsule
  // sweep below still stops him at the wall itself).
  const float There=OKStreetObstacleGap(To,Clearance+10.f);if(There<=Clearance&&(There<Clearance-5.f||There<Here-3.f))return false;
  // A heroine is in his way like anything else: walking into one sitting on a chair pushed her off it, left sitting on
  // the air (R3-221). Into her body is blocked; away from her (already that close) never is.
  // His steps only: a heroine walked with this (to a party seat, to an invitation) is not stopped by the others.
  // The one walking with him (a companion, an outing, a pair activity) walks at his side and never blocks him: she
  // stopped him on the way to the park lawn every step (R3-223).
  if(FVector::Dist2D(From,State->Male)<1.f)for(const auto& A:State->Agents){if(FMath::Abs(A.Position.Z-To.Z)>100.f)continue;
   if(A.Slot==State->Companion||A.Slot==State->OutingGirl||A.Slot==State->Pair.Partner)continue;const float Near=float(FVector::Dist2D(To,A.Position));
   if(Near<OKStreetHeroineBody&&Near<float(FVector::Dist2D(From,A.Position)))return false;}
  FHitResult Hit;
  if(GetWorld()->SweepSingleByChannel(Hit,From+FVector(0,0,OKStreetBodyLift()),To+FVector(0,0,OKStreetBodyLift()),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(28,OKStreetBodyHalf()),Query))
   if(!Hit.bStartPenetrating||FVector::DotProduct((To-From).GetSafeNormal2D(),Hit.Normal)<=0.f)return false;
  return true;};
 // Straight on, else slide along the obstacle: either axis, then 45 degrees either way (corners, posts, trees).
 const FVector Tries[]={D,FVector(FMath::Sign(D.X),0,0),FVector(0,FMath::Sign(D.Y),0),D.RotateAngleAxis(45,FVector::UpVector),D.RotateAngleAxis(-45,FVector::UpVector)};
 for(const FVector& T:Tries){if(T.IsNearlyZero()||FVector::DotProduct(T,D)<.3f)continue;FVector To=From+T*Distance;
  // The city's ground: he goes up and down with it, and where there is none he does not go. A lift's car and doorway are no ground of the
  // map's and its shaft has no floor above the first: from the second floor up nobody could step out of the car.
  if(OKStreetCityMode()){bool Lift=false;for(int32 I=0;I<State->Elevators.Num()&&!Lift;++I)Lift=InElevatorCar(I,From)||InElevatorCar(I,To)||ElevatorLanding(I,From)!=INDEX_NONE;
   float GroundZ=From.Z;bool Ground=OKStreetGroundZ(GetWorld(),To,GroundZ,this);
   // Already in the air (no ground in reach under where he stands, put there by a step past at another height): he comes
   // down to the ground below instead of standing there for good (R6-180). Not off a ledge he stands on: that has ground.
   if(!Ground&&!Lift){float HereZ=From.Z;if(!OKStreetGroundZ(GetWorld(),From,HereZ,this)){FHitResult Down;FCollisionQueryParams Q(SCENE_QUERY_STAT(StreetFall),false,this);
    if(GetWorld()->LineTraceSingleByChannel(Down,To+FVector(0,0,70),To-FVector(0,0,600),ECC_WorldStatic,Q)){GroundZ=float(Down.ImpactPoint.Z);Ground=true;}}}
   if(!Ground&&!Lift)continue;
   // Up a stair or a kerb, never onto the furniture: the sweep's body starts 45 cm up, so a bench passed under it and
   // the ground trace (70 cm up) put him on its seat, from there on the cafeteria table, where no grid way starts
   // (R6-190). A step is at most 21 cm long; a stair's riser is under 25. Only from ground he stands on: put somewhere
   // below the ground (a door's height, a step past) he still comes up onto it.
   if(Ground&&!Lift&&GroundZ-From.Z>35.f){float HereZ=From.Z;if(OKStreetGroundZ(GetWorld(),From,HereZ,this)&&FMath::Abs(HereZ-From.Z)<10.f)continue;}
   To.Z=Lift&&(!Ground||FMath::Abs(GroundZ-From.Z)>60.f)?From.Z:GroundZ;}
  if(Free(To))return To;}
 return From;
}
// Where to walk to speak to her: where she is, or, when she sits among furniture (a sofa, a bench by a table), the
// free spot within talking range nearest him.
FVector AOKStreetSocialScene::NavApproachSpot(const FVector& Her) const{
 if(!OKStreetBlockedPoint(Her,30))return Her;
 const FVector Male=State->Male;FVector Best=Her;float BestDistance=TNumericLimits<float>::Max();
 // On her side of the walls: reading by a shelf in the bookstore, the free spot nearest him was the pavement outside its
 // wall, and the navigation said "beside her" there.
 const FString HerPlace=PlaceHere(Her);
 for(const float R:{120.f,160.f,200.f})for(int32 A=0;A<18;++A){
  const float Angle=A*20.f*PI/180.f;const FVector P=Her+FVector(FMath::Cos(Angle),FMath::Sin(Angle),0)*R;
  if(OKStreetBlockedPoint(P,30)||PlaceHere(P)!=HerPlace)continue;const float D=FVector::Dist2D(P,Male);if(D<BestDistance){BestDistance=D;Best=P;}}
 return Best;
}

// Walks the gold route at running pace. Arrival, a blocked path or her becoming unavailable ends it.
float AOKStreetSocialScene::StepNavigation(float Dt){
 auto& S=*State;
 if((S.NavGirl==INDEX_NONE&&!S.NavPointActive)||S.SelfTest||S.Target!=INDEX_NONE||S.Pair.Partner!=INDEX_NONE||S.OutingGirl!=INDEX_NONE||S.PrivateGirl!=INDEX_NONE||S.Facility!=INDEX_NONE)return 0;
 if(S.NavGirl!=INDEX_NONE&&!S.Agents.IsValidIndex(S.NavGirl-1)){StopNavigation(FString());return 0;}
 const FVector Her=S.NavPointActive?S.NavPoint:S.Agents[S.NavGirl-1].Position;
 const FVector Goal=S.NavPointActive?S.NavPoint:NavApproachSpot(Her);
 // He is walking himself: the autopilot waits, then goes on from where he is.
 if(SceneTime()-S.ManualMoveAt<3.0){S.NavAround.Reset();return 0;}
 // The way around what stopped him, searched a slice a frame while he stands there.
 if(S.NavAround){
  if(!GridSearchStep(*S.NavAround,FPlatformTime::Seconds()+.003))return 0;
  TArray<FVector> Around=MoveTemp(S.NavAround->Route);const FVector To=S.NavAround->To;S.NavAround.Reset();S.NavProgressAt=SceneTime();
  if(Around.Num()>=2){if(S.NavPath.IsValidIndex(S.NavStep)&&To==S.NavPath[S.NavStep])S.NavPath.RemoveAt(0,S.NavStep+1);else S.NavPath.Reset();
   Around.Append(S.NavPath);S.NavPath=MoveTemp(Around);S.NavStep=1;}
  else if(S.NavRide.Elevator==INDEX_NONE){auto Path=S.NavPointActive?PlaceRoute(S.Male,Goal):ContactRoute(S.Male,Goal);if(Path.Num()>=2){S.NavPath=MoveTemp(Path);S.NavStep=1;}}
  return 0;}
 // On another floor: to an elevator first, then the ride (the route there is the plan's).
 // The shop's stairs first: from a shop's 2F to the department store's lift he walked into the shop's wall.
 if(S.NavRide.Elevator==INDEX_NONE&&NavNeedsLift(Goal)&&!NavByShopStairs(Goal)&&!PlanNavLift(Goal)){StopNavigation(OKT(TEXT("ui.contacts.other_floor_no_path")));return 0;}
 if(S.NavRide.Elevator!=INDEX_NONE&&S.NavStep>=S.NavPath.Num()){
  float Rate=0;const int32 Done=AdvanceLiftRide(S.NavRide,Dt,Rate);
  if(Done==2){StopNavigation(OKT(TEXT("ui.contacts.path_blocked_stop")));return 0;}
  if(Done==1){const bool Down=S.NavRide.Descend;S.NavRide=FOKStreetLiftRide();
   // Off the car: on this floor the grid; down on the street the place graph. Still another floor away: plan again.
   const FVector Now=S.NavPointActive?S.NavPoint:S.Agents[S.NavGirl-1].Position;
   const bool More=NavNeedsLift(Now);
   // Up on her floor: the grid searched a slice a frame till it is done (NavAround). GridRoute gives the city 4 ms, and
   // with no route in that time the straight line led across the department store's 4F atrium into the void.
   const bool Search=!More&&!Down&&OKStreetCityMode();
   TArray<FVector> Rest=More||Search?TArray<FVector>{S.Male}:Down?(S.NavPointActive?PlaceRoute(S.Male,Now):ContactRoute(S.Male,Now)):GridRoute(S.Male,Now);
   if(Search){S.NavAround=MakeShared<FOKStreetGridSearch>();S.NavAround->From=S.Male;S.NavAround->To=Now;}
   else if(Rest.Num()<2&&!More)Rest={S.Male,Now};
   if(S.NavPointActive&&!More)S.NavPoint.Z=S.Male.Z; // still another floor away: the goal keeps its height
   S.NavPath=MoveTemp(Rest);S.NavStep=1;S.NavReplans=0;S.NavProgressAt=SceneTime();}
  return Rate;
 }
 if(S.ManualReplan){S.ManualReplan=false;auto Path=S.NavPointActive?PlaceRoute(S.Male,Goal):ContactRoute(S.Male,Goal);if(Path.Num()>=2){S.NavPath=MoveTemp(Path);S.NavStep=1;S.NavReplans=0;S.NavProgressAt=SceneTime();}S.Message=OKT(TEXT("ui.contacts.resume_auto_travel"));RefreshUI();}
 // Close to her counts only on her side of the walls: in the same place (both in the bookstore, both outside), not
 // 1.2 m away through the shop's wall, where E cannot reach her.
 if((FVector::Dist2D(S.Male,Goal)<=(S.NavPointActive?80.f:40.f)||(!S.NavPointActive&&FVector::Dist2D(S.Male,Her)<=180.f&&PlaceHere(S.Male)==PlaceHere(Her)))&&FMath::Abs(S.Male.Z-Goal.Z)<150.f){
  // Walked up to her: if she was on her way somewhere she notices him, stops and turns to him for a moment, so he can
  // speak to her instead of chasing her down the street.
  if(!S.NavPointActive&&S.Agents.IsValidIndex(S.NavGirl-1)){const int32 G=S.NavGirl;S.CommutePausedUntil.Add(G,SceneTime()+10.0);
   if(S.Commutes.Contains(G))S.Rotations[G]=FRotator(0,(S.Male-S.Agents[G-1].Position).Rotation().Yaw,0);}
  // And he looks at her: E picks the girl in view, and beside Megumin in the dorm lounge it was Yuuka in front of him.
  if(!S.NavPointActive&&S.Agents.IsValidIndex(S.NavGirl-1)){const int32 G=S.NavGirl;S.Yaw=(S.Agents[G-1].Position-S.Male).Rotation().Yaw;S.Candidate=G;S.CandidateExplicit=true;}
  StopNavigation(S.NavPointActive?OKT(TEXT("ui.contacts.arrived_label"))+(S.NavPointName.IsEmpty()?FString(OKT(TEXT("ui.contacts.destination_label"))):S.NavPointName)+OKT(TEXT("ui.contacts.full_stop")):OKT(TEXT("ui.contacts.arrived_short"))+OKStreetScriptedName(S.Manifest.Characters[S.NavGirl].Name)+OKT(TEXT("ui.contacts.beside_her_talk_hint")));return 0;}
 while(S.NavStep<S.NavPath.Num()&&FVector::Dist2D(S.Male,S.NavPath[S.NavStep])<=30)++S.NavStep;
 FVector Next=S.NavPath.IsValidIndex(S.NavStep)?S.NavPath[S.NavStep]:Goal;
 // Chasing her: close by and nothing in between, straight at where she is now (the route, drawn every 0.75 s, lags a
 // girl who is walking).
 if(!S.NavPointActive&&FMath::Abs(Goal.Z-S.Male.Z)<150.f&&FVector::Dist2D(S.Male,Goal)<900.f){
  bool Clear=true;const int32 Steps=FMath::Max(1,FMath::CeilToInt(FVector::Dist2D(S.Male,Goal)/40.f));
  for(int32 I=1;I<Steps&&Clear;++I)if(OKStreetBlockedPoint(FMath::Lerp(S.Male,Goal,float(I)/Steps),30))Clear=false;
  if(Clear)Next=Goal;
 }
 FVector Delta=Next-S.Male;Delta.Z=0;const float Distance=Delta.Size();if(Distance<1)return 0;
 const float Step=FMath::Min(Distance,OKStreetMaleRunSpeed*FMath::Min(Dt,.05f));
 const double Now=SceneTime();
 const FVector Moved=StreetStep(S.Male,Delta/Distance,Step);
 if(Moved==S.Male){
  // On his way to a lift and stopped at its landing: he is there, standing there calls the car.
  if(S.NavRide.Elevator!=INDEX_NONE&&ElevatorLanding(S.NavRide.Elevator,S.Male)!=INDEX_NONE){S.NavStep=S.NavPath.Num();return 0;}
  // Blocked: find a new way from where he stands before giving up.
  if(Now-S.NavProgressAt>1.0){
   if(S.NavReplans>=(OKStreetCityMode()?30:6)){StopNavigation(OKT(TEXT("ui.contacts.path_blocked_stop")));return 0;} // each try learns a blocked cell, so a few more find the way round
   ++S.NavReplans;S.NavProgressAt=Now;S.NavBlockedAt=S.Male;
   if(OKStreetCityMode())OKStreetCityBlocked(S.NavPath.IsValidIndex(S.NavStep-1)?S.NavPath[S.NavStep-1]:S.Male,Next); // the road graph learns it too
   // Stopped by something solid the grid did not see: the cell ahead is known blocked from now on.
   {const FVector Ahead=S.Male+Delta/Distance*OKStreetNavCell;const FIntPoint Cell(FMath::RoundToInt(Ahead.X/OKStreetNavCell),FMath::RoundToInt(Ahead.Y/OKStreetNavCell));
    const FIntPoint Here(FMath::RoundToInt(S.Male.X/OKStreetNavCell),FMath::RoundToInt(S.Male.Y/OKStreetNavCell));
    if(Cell!=Here){S.NavLearned.FindOrAdd(FMath::RoundToInt(S.Male.Z/100.f)).Add(Cell);UE_LOG(LogTemp,Display,TEXT("Street navigation: cell (%d,%d) learned blocked"),Cell.X,Cell.Y);}}
   // Wedged (three stops in a row where he stands): out to the nearest free cell he can reach in a straight line, up to
   // four cells away, and the way again from there.
   if(S.NavReplans==3){
    const float Z=S.Male.Z;const FIntPoint Here(FMath::RoundToInt(S.Male.X/OKStreetNavCell),FMath::RoundToInt(S.Male.Y/OKStreetNavCell));
    const TSet<FIntPoint>* Known=S.NavLearned.Find(FMath::RoundToInt(Z/100.f));FCollisionQueryParams Q(SCENE_QUERY_STAT(StreetNavUnstick),false,this);bool Out=false;
    for(int32 R=1;R<=4&&!Out;++R)for(int32 DX=-R;DX<=R&&!Out;++DX)for(int32 DY=-R;DY<=R&&!Out;++DY){
     if(FMath::Max(FMath::Abs(DX),FMath::Abs(DY))!=R)continue;const FIntPoint C=Here+FIntPoint(DX,DY);if((Known&&Known->Contains(C))||!NavCellFree(C,Z))continue;
     const FVector P(C.X*OKStreetNavCell,C.Y*OKStreetNavCell,Z);FHitResult H;
     if(GetWorld()->SweepSingleByChannel(H,S.Male+FVector(0,0,85),P+FVector(0,0,85),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(28,78),Q)&&!H.bStartPenetrating)continue;
     // Where he lands is clear of furniture: risen from a table his body overlaps it, the sweep above starts inside it
     // and reports nothing, and he was put under the ramen shop's table, then on it (R6-197).
     if(GetWorld()->OverlapAnyTestByChannel(P+FVector(0,0,85),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(28,78),Q))continue;
     UE_LOG(LogTemp,Display,TEXT("Street navigation: wedged at %s, out to %s"),*S.Male.ToCompactString(),*P.ToCompactString());S.Male=P;Out=true;}
    // Shut in (between a facade and its inner wall): out at the nearest door on the street (doors are where walking
    // starts), and the way again from there.
    if(!Out){const FOKStreetPlace* Near=nullptr;for(const auto& P:OKStreetPlaces())if(FMath::Abs(P.Door.Z-Z)<150.f&&(!Near||FVector::Dist2D(P.Door,S.Male)<FVector::Dist2D(Near->Door,S.Male)))Near=&P;
     if(Near&&FVector::Dist2D(Near->Door,S.Male)<2000.f){UE_LOG(LogTemp,Warning,TEXT("Street navigation: shut in at %s, out at the door of %s"),*S.Male.ToCompactString(),Near->Id);S.Male=FVector(Near->Door.X,Near->Door.Y,Z);Out=true;}}
    // Upstairs no door is on his floor: the lift's landing on it is where walking starts there. Stepped off the car on the
    // EE building's 4F into a pocket beside the shaft, he stood shut in, saved there, and loaded back into it (R6-178).
    if(!Out){const FVector* Landing=nullptr;for(const auto& E:S.Elevators)for(int32 F=0;F<E.Landing.Num();++F)if(FMath::Abs(E.StopZ[F]-Z)<100.f&&FVector::Dist2D(E.Landing[F],S.Male)<2000.f&&(!Landing||FVector::Dist2D(E.Landing[F],S.Male)<FVector::Dist2D(*Landing,S.Male)))Landing=&E.Landing[F];
     if(Landing){UE_LOG(LogTemp,Warning,TEXT("Street navigation: shut in at %s, out at the lift landing %s"),*S.Male.ToCompactString(),*Landing->ToCompactString());S.Male=*Landing;Out=true;}}
    // On the way to a lift: the way again is to its landing (the route's end). The street route from there left the ride
    // behind: loaded at the ramen shop on the department store's 9F, he walked the 9F wall toward the ground for an hour
    // (R6-188).
    if(Out){auto Path=S.NavRide.Elevator!=INDEX_NONE&&!S.NavPath.IsEmpty()?GridRoute(S.Male,S.NavPath.Last()):S.NavPointActive?PlaceRoute(S.Male,Goal):ContactRoute(S.Male,Goal);
     if(S.NavRide.Elevator!=INDEX_NONE&&Path.Num()<2&&!S.NavPath.IsEmpty())Path={S.Male,S.NavPath.Last()};
     if(Path.Num()>=2){S.NavPath=MoveTemp(Path);S.NavStep=1;}return 0;}
   }
   // First around what is in the way, to the next point only (the grid keeps the body's clearance; the same route again
   // would run into the same wall); the whole way again only when that finds nothing.
   if(S.NavReplans==1){S.NavAround=MakeShared<FOKStreetGridSearch>();S.NavAround->From=S.Male;S.NavAround->To=Next;}
   else if(S.NavRide.Elevator==INDEX_NONE){auto Path=S.NavPointActive?PlaceRoute(S.Male,Goal):ContactRoute(S.Male,Goal);
    if(Path.Num()>=2){S.NavPath=MoveTemp(Path);S.NavStep=1;}}
   {
    // What is in the way: the clearance gap on his side, and the first thing a body-sized sweep toward the next point hits.
    FString Hit=TEXT("none");FCollisionQueryParams Q(SCENE_QUERY_STAT(StreetNavWhy),false,this);FHitResult H;const FVector Dir=Delta/Distance;
    if(GetWorld()->SweepSingleByChannel(H,S.Male+FVector(0,0,OKStreetBodyLift()),S.Male+Dir*Step+FVector(0,0,OKStreetBodyLift()),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(28,OKStreetBodyHalf()),Q))Hit=FString::Printf(TEXT("%s/%s at %s pen=%d"),*GetNameSafe(H.GetActor()),*GetNameSafe(H.GetComponent()),*H.ImpactPoint.ToCompactString(),H.bStartPenetrating?1:0);
    UE_LOG(LogTemp,Display,TEXT("Street navigation: blocked why: next=%s gap_here=%.0f gap_ahead=%.0f sweep=%s"),*Next.ToCompactString(),OKStreetObstacleGap(S.Male),OKStreetObstacleGap(S.Male+Dir*Step),*Hit);
   }
   UE_LOG(LogTemp,Display,TEXT("Street navigation: blocked at %s, replanned %d (points=%d)"),*S.Male.ToCompactString(),S.NavReplans,S.NavPath.Num());
  }
  return 0;
 }
 S.Rotations[0]=OKStreetFacingMovement(Moved-S.Male,S.Rotations[0]);S.Male=Moved;S.NavProgressAt=Now;
 // Past what stopped him: the tries start again. Not merely near the next point: after a way round the next point is a
 // cell away, the count went back to 0 every time, and he never got to the wedged step or gave up.
 if(FVector::Dist2D(S.Male,S.NavPath.IsValidIndex(S.NavStep)?S.NavPath[S.NavStep]:Goal)<60&&FVector::Dist2D(S.Male,S.NavBlockedAt)>200.f)S.NavReplans=0;
 return OKStreetMaleRunSpeed/OKStreetWalkSpeed;
}
void AOKStreetSocialScene::BeginPrivate(int32 Character,const FString& TryCard,int32 TryOutfit){
 if(!ContactReady(Character)||!ContactIdle()||!State->HighCards.IsValidIndex(Character)||State->HighCards.IsEmpty())return;
 auto& S=*State;StopAmbientActivity();EndTalk();GalgameHideForPrivate();
 OKStreetPrivateEnvSave(); // its high models change the extraction environment the crowd reads (OKStreetSocialPrivateEnv.cpp)
 // Right where she stands, facing as she does (user, 2026-11-01: into the one-on-one on the street itself, no change of
 // scene): her high model takes her place, his is set by the pair; the street goes on around them.
 const FOKStreetAgentSim* Her=S.Agents.FindByPredicate([Character](const FOKStreetAgentSim& A){return A.Slot==Character;});
 const FTransform There(FRotator(0.,S.RenderedRotations.IsValidIndex(Character)?S.RenderedRotations[Character].Yaw:0.,0.),Her?Her->Position:S.Male);
 const bool TryOn=!TryCard.IsEmpty();const int32 Worn=S.HighOutfits.IsValidIndex(Character)?S.HighOutfits[Character]:0;
 auto* Mode=AOKInteractionMode::EnterCards(GetWorld()->GetFirstPlayerController(),TryOn?TryCard:S.HighCards[Character],S.HighCards[0],TryOn&&TryOutfit>=0?TryOutfit:Worn,&There);
 if(!Mode){OKStreetPrivateEnvRestore();S.ContactsNotice=OKT(TEXT("ui.contacts.interaction_load_failed"));RefreshUI();return;}
 // Her experience (hexp.rs) gates the poses, raw insertion and anal in the H panel.
 S.PrivateTryOn=TryOn;Mode->bFitting=TryOn;
 // Her street model stands right where the high one now does: 安可 tried the dress on inside her own cheongsam.
 if(TryOn){FString Hidden;OKSetCrowdRuntimeCharacterMotion(this,Character,FTransform(There.GetRotation(),There.GetLocation()-FVector(0.,0.,100000.)),0.f,Hidden);}
 if(TryOn){const FVector At=There.GetLocation();for(const auto& P:OKStreetPlaces())for(const FBox& Room:P.Rooms)if(At.X>=Room.Min.X&&At.X<=Room.Max.X&&At.Y>=Room.Min.Y&&At.Y<=Room.Max.Y&&At.Z>=Room.Min.Z-60.f&&At.Z<Room.Max.Z-60.f)Mode->FittingRoom=Room;}
 if(!TryOn){const FString Id=OKStreetStableId(S.Manifest.Characters[Character]);auto Ask=OKRulesHeroineRequest(S,TEXT("h_experience"),Id);Ask->SetStringField(TEXT("girl"),Id);Ask->SetNumberField(TEXT("day"),S.Store.CalendarDay);OKRulesPutExt(S,Ask);
  // With her desire and bust: past 100 she runs and her nipples leak in the room too (OKHScene drips).
  TSharedPtr<FJsonObject> Experience=OKRulesEval(S,Ask);if(Experience.IsValid()){Experience->SetNumberField(TEXT("sex_desire"),OKStreetViewRelation(S.Store,Id,S.Manifest.TalkBudget).SexDesire);Experience->SetNumberField(TEXT("favor"),OKStreetViewRelation(S.Store,Id,S.Manifest.TalkBudget).Favor);Experience->SetNumberField(TEXT("bust"),OKStreetHerCard(S,Character).Bust);
   // Her eyes in the room: who she is and how worn out (OKHScene TickEyeDull).
   {const auto R=OKStreetViewRelation(S.Store,Id,S.Manifest.TalkBudget);Experience->SetNumberField(TEXT("energy"),R.Energy);Experience->SetNumberField(TEXT("satiety"),R.Satiety);Experience->SetNumberField(TEXT("personality"),S.Manifest.Characters[Character].PersonalityId);}
   // His condoms (the H panel puts one on only when he or she has one; hers are hexp's her_condoms).
   Experience->SetNumberField(TEXT("his_condoms"),S.Store.Inventory.FilterByPredicate([](const FString& I){return I==TEXT("cv_condom");}).Num());
   // Taken from touching herself on the street: she wants it, raw and all (OKStreetSocialOnani.inl).
   // Taken after her no (PrivateConsent): she says how could he, and stays unwilling though her body likes it (OKHScene).
   if(S.PrivateForcedGirl==Character)Experience->SetBoolField(TEXT("forced"),true);
   if(S.OnaniPrivate==Character){Experience->SetBoolField(TEXT("street_onani"),true);Experience->SetBoolField(TEXT("raw_ok"),true);Experience->SetBoolField(TEXT("kiss_ok"),true);Experience->SetBoolField(TEXT("resentful"),false);}}
  // The other heroines, for the lesbian and 3P poses (OKHScene LoadSecond).
  if(Experience.IsValid()){TArray<TSharedPtr<FJsonValue>> Others;for(int32 I=1;I<S.Manifest.Characters.Num();++I){const FString Card=OKStreetCardFor(S,I);if(I==Character||Card.IsEmpty())continue;
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("name"),S.Manifest.Characters[I].Name);O->SetStringField(TEXT("card"),Card);O->SetNumberField(TEXT("girl"),I);{const FString OtherId=OKStreetStableId(S.Manifest.Characters[I]);O->SetStringField(TEXT("id"),OtherId);const FString Stage=OKStreetViewRelation(S.Store,OtherId,S.Manifest.TalkBudget).Stage;O->SetBoolField(TEXT("willing"),Stage!=TEXT("stranger"));auto AskHer=OKRulesHeroineRequest(S,TEXT("h_experience"),OtherId);AskHer->SetStringField(TEXT("girl"),OtherId);AskHer->SetNumberField(TEXT("day"),S.Store.CalendarDay);OKRulesPutExt(S,AskHer);double Level=Stage==TEXT("lover")?2:Stage==TEXT("friend")?1:0;
    if(const TSharedPtr<FJsonObject> Had=OKRulesEval(S,AskHer)){O->SetObjectField(TEXT("experience"),Had);Had->TryGetNumberField(TEXT("level"),Level);}O->SetNumberField(TEXT("level"),Level);}Others.Add(MakeShared<FJsonValueObject>(O));}
   Experience->SetArrayField(TEXT("others"),Others);}
  S.PrivateForcedGirl=INDEX_NONE;
  Mode->BeginHScene(S.Manifest.Characters[Character].Name,OKStreetViewRelation(S.Store,Id,S.Manifest.TalkBudget).Stage,Experience,S.Manifest.Characters[0].Name);}
 S.PrivateShownLine=S.FreeTalkCaptionHer; // what was on screen before is not shown in the scene
 // The street clock runs about 24 times real time: an hour in the room would be a whole night gone (she said the sun was
 // up after one scene). It stands still while they are in there and moves on by the real time spent when they leave.
 if(!S.ClockPaused){const double Wall=FPlatformTime::Seconds();S.ClockStartHours=OKStreetClockHours(S.ClockStartHours,Wall-S.ClockStartWall);S.ClockStartWall=Wall;S.ClockPaused=true;S.PrivateClockFrozen=true;}
 // The last scene's result still open (or still waiting for the time after it to end) does not stay over this one.
 EndAfter(false);
 if(S.HResultPanel.IsValid()){if(GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(S.HResultPanel.ToSharedRef());S.HResultPanel.Reset();}
 S.PrivateGirl=Character;S.HighPrivateAt=FPlatformTime::Seconds();S.HighPrivateSeenReady=false;S.HighPrivateResult.Reset();S.PrivateMouse=S.MouseUI;S.PrivateMode=Mode;
 const FString Directory=FPaths::GetPath(S.Manifest.SocialReport)/TEXT("HighInteraction")/FGuid::NewGuid().ToString(EGuidFormats::Digits);IFileManager::Get().MakeDirectory(*Directory,true);
 S.HighPrivateReport=Directory/TEXT("result.json");Mode->ReportPath=S.HighPrivateReport;
 Mode->AutoReturnSeconds=S.SelfTest?2:0;
 TWeakObjectPtr<AOKStreetSocialScene> Weak(this);
 Mode->Returned=[Weak](TSharedRef<FJsonObject> Result){if(Weak.IsValid()&&Weak->State){Weak->State->HighPrivateResult=Result;Weak->State->HighPrivateSeenReady=Result->HasField(TEXT("partner_ready"))&&Result->GetBoolField(TEXT("partner_ready"));Weak->FinishPrivate();if(Weak->State->SelfTest&&!Weak->State->Reported)Weak->RunContactsProbe(Weak->SceneTime());}};
 S.PrivateInPlace=true;S.MouseToggleRequested=false;S.ContactsNotice=OKT(TEXT("ui.contacts.loading_one_on_one"));RefreshUI();
 // What the street figures hold would stay hanging in the air: their ticks stop with the street's (TickPrivate).
 {auto Hide=[&S](AActor* A){if(A&&!A->IsHidden()){A->SetActorHiddenInGame(true);S.PrivateHiddenProps.Add(A);}};
  for(auto& Held:S.ReadingProps)for(auto& P:Held.Value)Hide(P.Get());for(auto& P:S.MealHandProps)Hide(P.Key.Get());for(auto& P:S.FacilityHandProps)Hide(P.Key.Get());
  for(auto& P:S.PairProps)Hide(P.Get());for(auto& P:S.AmbientProps)Hide(P.Get());Hide(S.Umbrella.Get());}
 if(S.Overlay)S.Overlay->SetVisibility(EVisibility::Collapsed);
 // A leave button of the street's own, top right over the scene: back to the street at any time (its panel's return is
 // at the top of a long scrolled list, and the control channel cannot reach it).
 if(GEngine&&GEngine->GameViewport){
  S.PrivateLeave=SNew(SBox).HAlign(HAlign_Right).VAlign(VAlign_Top).Padding(FMargin(0,16,24,0))
   [SNew(SHorizontalBox)+SHorizontalBox::Slot().AutoWidth().Padding(0,0,8,0)[TryOn?SNullWidget::NullWidget:BookmarkButton(Character)] // this moment kept (OKStreetSocialBookmarks.inl)
    +SHorizontalBox::Slot().AutoWidth()[SNew(SButton).ButtonStyle(OKStreetGlassButton()).ContentPadding(FMargin(18,8))
    .Text(FText::FromString(OKT(TryOn?TEXT("ui.clothes.try_done"):TEXT("ui.contacts.leave_one_on_one"))))
    .OnClicked_Lambda([Weak=TWeakObjectPtr<AOKStreetSocialScene>(this)](){if(Weak.IsValid())Weak->FinishPrivate();return FReply::Handled();})]];
  GEngine->GameViewport->AddViewportWidgetContent(S.PrivateLeave.ToSharedRef(),20);}
}
// The original's result after an H scene (HSceneResult): her level then and now, each place's development before and
// after (what grew in green), and this time's firsts; on the street until he closes it or another one-on-one ends.
// The result screen closed: the other heroines in the scene next, one after the other.
void AOKStreetSocialScene::CloseHResult(){
 if(!State||!State->HResultPanel.IsValid()||!GEngine||!GEngine->GameViewport)return;auto& S=*State;
 GEngine->GameViewport->RemoveViewportWidgetContent(S.HResultPanel.ToSharedRef());S.HResultPanel.Reset();
 if(S.HResultNext.Num()){const auto One=S.HResultNext[0];S.HResultNext.RemoveAt(0);ShowHResult(One.Key,*One.Value);}
}
void AOKStreetSocialScene::ShowHResult(int32 Girl,const FJsonObject& Answer){
 auto& S=*State;const TSharedPtr<FJsonObject>* Result=nullptr;
 if(S.HResultPanel.IsValid()){if(GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(S.HResultPanel.ToSharedRef());S.HResultPanel.Reset();}
 if(!Answer.TryGetObjectField(TEXT("result"),Result)||!(*Result)->GetBoolField(TEXT("played"))||!GEngine||!GEngine->GameViewport)return;
 TSharedRef<SVerticalBox> Rows=SNew(SVerticalBox);
 auto Line=[&](const FString& Text,const FLinearColor& Color,int32 Size){Rows->AddSlot().AutoHeight().Padding(FMargin(0,2))[SNew(STextBlock).Text(FText::FromString(Text)).ColorAndOpacity(FSlateColor(Color)).Font(FCoreStyle::GetDefaultFontStyle("Regular",Size))];};
 Line(OKMsg(TEXT("ui.hresult.title"),{{TEXT("name"),SpokenName(Girl)}}),FLinearColor::White,18);
 const FString Was=(*Result)->GetStringField(TEXT("level_before_name")),Now=Answer.GetStringField(TEXT("level_name"));
 Line(Was==Now?OKMsg(TEXT("ui.hresult.level"),{{TEXT("level"),Now}}):OKMsg(TEXT("ui.hresult.level_up"),{{TEXT("before"),Was},{TEXT("after"),Now}}),Was==Now?FLinearColor(.85f,.85f,.9f):FLinearColor(1.f,.75f,.3f),15);
 const TArray<TSharedPtr<FJsonValue>>* Areas=nullptr;
 if((*Result)->TryGetArrayField(TEXT("areas"),Areas))for(const auto& V:*Areas){const auto O=V->AsObject();if(!O)continue;
  const int32 B=int32(O->GetNumberField(TEXT("before"))),A=int32(O->GetNumberField(TEXT("after")));
  Line(OKMsg(A>B?TEXT("ui.hresult.area_up"):TEXT("ui.hresult.area"),{{TEXT("name"),O->GetStringField(TEXT("name"))},{TEXT("before"),B},{TEXT("after"),A},{TEXT("n"),A-B}}),A>B?FLinearColor(.55f,1.f,.6f):FLinearColor(.8f,.8f,.85f),14);}
 const TArray<TSharedPtr<FJsonValue>>* Firsts=nullptr;
 if((*Result)->TryGetArrayField(TEXT("firsts"),Firsts))for(const auto& V:*Firsts)Line(OKMsg(TEXT("ui.hresult.first"),{{TEXT("text"),V->AsString()}}),FLinearColor(1.f,.6f,.75f),14);
 // Her pregnancy (pregnancy.rs): conceived this time, or how far along.
 const TSharedPtr<FJsonObject>* Preg=nullptr;bool bConceived=false;(*Result)->TryGetBoolField(TEXT("conceived"),bConceived);
 if((*Result)->TryGetObjectField(TEXT("pregnancy"),Preg)&&(*Preg)->GetBoolField(TEXT("pregnant")))
  Line(bConceived?OKT(TEXT("ui.hresult.conceived")):OKMsg(TEXT("ui.hresult.pregnant"),{{TEXT("week"),int32((*Preg)->GetNumberField(TEXT("week")))}}),FLinearColor(1.f,.55f,.85f),14);
 // What was done (H_SCENE_ADDITIONS_PLAN 14): how long, her climaxes, where he came, her spray and milk, the poses.
 const TSharedPtr<FJsonObject>* H=nullptr;
 if(S.HighPrivateResult.IsValid()&&S.HighPrivateResult->TryGetObjectField(TEXT("h"),H)&&(*H)->HasField(TEXT("counts"))){
  const auto C=(*H)->GetObjectField(TEXT("counts"));auto N=[&](const TCHAR* K){double V=0;C->TryGetNumberField(K,V);return int32(V);};
  const int32 Seconds=int32(S.HighPrivateResult->HasField(TEXT("seconds"))?S.HighPrivateResult->GetNumberField(TEXT("seconds")):0.);
  const FLinearColor Grey(.8f,.8f,.88f);
  Line(OKMsg(TEXT("ui.hresult.stats_time"),{{TEXT("minutes"),FMath::Max(1,Seconds/60)},{TEXT("orgasms"),N(TEXT("her_orgasms"))}}),Grey,14);
  Line(OKMsg(TEXT("ui.hresult.stats_his"),{{TEXT("n"),N(TEXT("his_finishes"))},{TEXT("raw"),N(TEXT("his_inside_raw"))},{TEXT("condom"),N(TEXT("his_condom"))},{TEXT("outside"),N(TEXT("his_outside"))},{TEXT("mouth"),N(TEXT("his_mouth"))},{TEXT("swallowed"),N(TEXT("swallowed"))}}),Grey,14);
  Line(OKMsg(TEXT("ui.hresult.stats_her"),{{TEXT("drips"),N(TEXT("her_drip_times"))},{TEXT("milk"),N(TEXT("her_milk_times"))}}),Grey,14);
  const TArray<TSharedPtr<FJsonValue>>* Played=nullptr;TArray<FString> Names;
  if((*H)->TryGetArrayField(TEXT("poses"),Played))for(const auto& V:*Played)Names.AddUnique(V->AsString());
  if(Names.Num())Line(OKMsg(TEXT("ui.hresult.stats_poses"),{{TEXT("poses"),FString::Join(Names,OKT(TEXT("ui.memory.list_separator")))}}),Grey,14);}
 // Her totals so far (hexp: the times they had sex, her climaxes and where).
 const TSharedPtr<FJsonObject>* Totals=nullptr;
 if((*Result)->TryGetObjectField(TEXT("totals"),Totals)){static const TCHAR* Keys[]={TEXT("kiss"),TEXT("chest"),TEXT("nipple"),TEXT("butt"),TEXT("crotch"),TEXT("anal"),TEXT("head"),TEXT("hand"),TEXT("thigh"),TEXT("calf"),TEXT("foot")};
  const TSharedPtr<FJsonObject>* By=nullptr;(*Totals)->TryGetObjectField(TEXT("climaxes"),By);TArray<FString> Where;
  for(const TCHAR* K:Keys){double V=0;if(By)(*By)->TryGetNumberField(K,V);if(V>0)Where.Add(OKMsg(TEXT("ui.hscene.history_place"),{{TEXT("place"),OKT(*(FString(TEXT("ui.hscene.part_"))+(FCString::Strcmp(K,TEXT("kiss"))==0?TEXT("lips"):K)))},{TEXT("n"),int32(V)}}));}
  auto T=[&](const TCHAR* K){double V=0;(*Totals)->TryGetNumberField(K,V);return int32(V);};
  Line(OKMsg(TEXT("ui.hresult.stats_total"),{{TEXT("sex"),T(TEXT("sex_count"))},{TEXT("vaginal"),T(TEXT("vaginal_count"))},{TEXT("anal"),T(TEXT("anal_count"))},{TEXT("orgasms"),T(TEXT("orgasms"))}}),FLinearColor(.95f,.85f,.6f),14);
  if(Where.Num())Line(OKMsg(TEXT("ui.hresult.stats_where"),{{TEXT("where"),FString::Join(Where,OKT(TEXT("ui.memory.list_separator")))}}),FLinearColor(.95f,.85f,.6f),14);}
 Rows->AddSlot().AutoHeight().HAlign(HAlign_Right).Padding(FMargin(0,10,0,0))
  [SNew(SButton).ButtonStyle(OKStreetGlassButton()).ContentPadding(FMargin(18,6)).Text(FText::FromString(OKT(TEXT("ui.hresult.close"))))
   .OnClicked_Lambda([Weak=TWeakObjectPtr<AOKStreetSocialScene>(this)](){if(Weak.IsValid())Weak->CloseHResult();return FReply::Handled();})];
 TSharedRef<SBorder> Panel=SNew(SBorder).BorderImage(FCoreStyle::Get().GetBrush("WhiteBrush")).BorderBackgroundColor(FLinearColor(.05f,.04f,.08f,.88f)).Padding(FMargin(28,20));
 Panel->SetContent(Rows);
 S.HResultPanel=SNew(SBox).HAlign(HAlign_Center).VAlign(VAlign_Center)[Panel];
 GEngine->GameViewport->AddViewportWidgetContent(S.HResultPanel.ToSharedRef(),25);
 UE_LOG(LogTemp,Display,TEXT("Street private: result shown (%s -> %s, %d places)"),*Was,*Now,Areas?Areas->Num():0);
}
void AOKStreetSocialScene::FinishPrivate(){
 if(!State||State->PrivateGirl==INDEX_NONE)return;auto& S=*State;
 auto Mode=S.PrivateMode;const int32 Girl=S.PrivateGirl;S.PrivateMode.Reset();S.PrivateGirl=INDEX_NONE;S.OnaniPrivate=INDEX_NONE;
 // Left from the street's own leave button (or the control channel): the scene still hands back what happened, or her
 // memory and experience of it were lost (only the scene's own return kept them).
 if(Mode.IsValid()&&!Mode->IsFinished()){TWeakObjectPtr<AOKStreetSocialScene> Weak(this);Mode->Returned=[Weak](TSharedRef<FJsonObject> Result){if(Weak.IsValid()&&Weak->State)Weak->State->HighPrivateResult=Result;};Mode->Exit(false);}
 OKStreetPrivateEnvRestore();
 if(S.PrivateClockFrozen&&S.ClockPaused){const double Wall=FPlatformTime::Seconds();S.ClockStartHours=FMath::Fmod(S.ClockStartHours+FMath::Max(0.,Wall-S.HighPrivateAt)/3600.,24.);S.ClockStartWall=Wall;S.ClockPaused=false;RefreshUI();}S.PrivateClockFrozen=false; // (someone ran the clock meanwhile: it already moved)
 S.PrivatePausedSeconds+=FMath::Max(0.,FPlatformTime::Seconds()-S.HighPrivateAt);S.LastWall=0;
 OKSuspendCrowdRuntimeScene(this,false);S.PrivateInPlace=false;S.MouseUI=S.PrivateMouse;S.MouseToggleRequested=false;
 for(const auto& P:S.PrivateHiddenProps)if(AActor* A=P.Get())A->SetActorHiddenInGame(false);S.PrivateHiddenProps.Reset();
 if(auto* PC=GetWorld()->GetFirstPlayerController())PC->SetViewTarget(S.Camera.Get());
 if(S.Overlay)S.Overlay->SetVisibility(EVisibility::Visible);
 if(S.PrivateLeave.IsValid()){if(GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(S.PrivateLeave.ToSharedRef());S.PrivateLeave.Reset();}
 // Her memory of the session: when it started (the memory's own time), how long, and every thing they did, in order.
 if(S.HighPrivateResult.IsValid()&&!S.PrivateTryOn&&S.Manifest.Characters.IsValidIndex(Girl)){
  const TArray<TSharedPtr<FJsonValue>>* Acts=nullptr;TArray<FString> Done;
  if(S.HighPrivateResult->TryGetArrayField(TEXT("actions"),Acts))for(const auto& V:*Acts){const auto O=V->AsObject();if(!O)continue;
   const int32 Sec=int32(O->GetNumberField(TEXT("seconds")));FString Label=O->GetStringField(TEXT("label"));
   if(O->GetStringField(TEXT("kind"))==TEXT("said"))Label=OKMsg(TEXT("ui.memory.private_he_said"),{{TEXT("text"),Label}}); // his words, not a thing they did
   Done.Add(OKMsg(TEXT("ui.memory.private_action"),{{TEXT("label"),Label},{TEXT("minute"),Sec/60},{TEXT("second"),Sec%60}}));}
  const int32 Seconds=int32(S.HighPrivateResult->HasField(TEXT("seconds"))?S.HighPrivateResult->GetNumberField(TEXT("seconds")):0.);
  const FString Text=OKMsg(TEXT("ui.memory.private_session"),{{TEXT("minutes"),FMath::Max(1,Seconds/60)},{TEXT("count"),Done.Num()},{TEXT("actions"),FString::Join(Done,OKT(TEXT("ui.memory.list_separator")))}});
  MindObserve(Girl,TEXT("private"),Text,PlaceHere(S.Male),Done.IsEmpty()?0.5f:0.75f);
  // What it leaves on her: the experience, firsts and the relation (hexp.rs h_session_end), whichever way the scene opened.
  const TSharedPtr<FJsonObject>* H=nullptr;
  // The others in it (lesbian, 3P) remember it and keep their climaxes and poses; these counts have no touch or insertion
  // of hers, so her firsts stay as they were.
  if(S.HighPrivateResult->TryGetObjectField(TEXT("h"),H)){const TArray<TSharedPtr<FJsonValue>>* Joined=nullptr;
   if((*H)->TryGetArrayField(TEXT("second"),Joined))for(const auto& Row:*Joined){const auto R=Row->AsObject();if(!R)continue;
    const int32 Other=int32(R->GetNumberField(TEXT("girl")));const FString OtherId=R->GetStringField(TEXT("id"));const TSharedPtr<FJsonObject>* Hers=nullptr;if(Other<=0||OtherId.IsEmpty()||!R->TryGetObjectField(TEXT("counts"),Hers))continue;
    // As the first heroine below: what is on her, then the same h_session_end on her own counts.
    if(Other<OKStreetCastCount){const TArray<TSharedPtr<FJsonValue>>* On=nullptr;if((*Hers)->TryGetArrayField(TEXT("siru"),On))for(int32 A=0;A<On->Num()&&A<5;++A)if((*On)[A]->AsNumber()>0)S.SemenOn[Other]|=1<<A;double Drips=0,Milk=0;(*Hers)->TryGetNumberField(TEXT("her_drips"),Drips);(*Hers)->TryGetNumberField(TEXT("her_milk"),Milk);S.ArousalWetCrotch[Other]+=int32(Drips);S.ArousalWetMilk[Other]+=int32(Milk);}
    auto Request=OKRulesHeroineRequest(S,TEXT("h_session_end"),OtherId);Request->SetStringField(TEXT("girl"),OtherId);Request->SetNumberField(TEXT("day"),S.Store.CalendarDay);Request->SetStringField(TEXT("place"),PlaceHere(S.Male));Request->SetNumberField(TEXT("minute"),double(OKStreetMindNow(S)));Request->SetObjectField(TEXT("counts"),*Hers);{const TArray<TSharedPtr<FJsonValue>>* Names=nullptr;if(R->TryGetArrayField(TEXT("poses"),Names))Request->SetArrayField(TEXT("poses"),*Names);}OKRulesPutExt(S,Request);
    if(const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request)){auto Candidate=S.Store;OKRulesTakeExt(Candidate,*Answer);ApplyRulesEffects(Candidate,*Answer);if(CommitStore(MoveTemp(Candidate)))FlushRulesEffects();OKStreetApplyHerExtras(S,OtherId);S.HResultNext.Add(TPair<int32,TSharedPtr<FJsonObject>>(Other,Answer));
     UE_LOG(LogTemp,Display,TEXT("Street private: %s was in it too, %d climaxes, level %s"),*R->GetStringField(TEXT("name")),int32((*Hers)->GetNumberField(TEXT("her_orgasms"))),*Answer->GetStringField(TEXT("level_name")));}}}
  if(S.HighPrivateResult->TryGetObjectField(TEXT("h"),H)&&(*H)->HasField(TEXT("counts"))){
   // She comes out of the room as wet as she ran in it (until she sleeps or bathes).
   if(Girl>0&&Girl<OKStreetCastCount){const auto C=(*H)->GetObjectField(TEXT("counts"));double Drips=0,Milk=0;C->TryGetNumberField(TEXT("her_drips"),Drips);C->TryGetNumberField(TEXT("her_milk"),Milk);
    S.ArousalWetCrotch[Girl]+=int32(Drips);S.ArousalWetMilk[Girl]+=int32(Milk);
    const TArray<TSharedPtr<FJsonValue>>* On=nullptr;if(C->TryGetArrayField(TEXT("siru"),On))for(int32 A=0;A<On->Num()&&A<5;++A)if((*On)[A]->AsNumber()>0)S.SemenOn[Girl]|=1<<A;}
   const FString Id=OKStreetStableId(S.Manifest.Characters[Girl]);auto Request=OKRulesHeroineRequest(S,TEXT("h_session_end"),Id);
   Request->SetStringField(TEXT("girl"),Id);Request->SetNumberField(TEXT("day"),S.Store.CalendarDay);Request->SetStringField(TEXT("place"),PlaceHere(S.Male));Request->SetNumberField(TEXT("minute"),double(OKStreetMindNow(S)));Request->SetObjectField(TEXT("counts"),(*H)->GetObjectField(TEXT("counts")));{const TArray<TSharedPtr<FJsonValue>>* Poses=nullptr;if((*H)->TryGetArrayField(TEXT("poses"),Poses))Request->SetArrayField(TEXT("poses"),*Poses);}OKRulesPutExt(S,Request);
   if(const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request)){auto Candidate=S.Store;OKRulesTakeExt(Candidate,*Answer);ApplyRulesEffects(Candidate,*Answer);if(CommitStore(MoveTemp(Candidate)))FlushRulesEffects();OKStreetApplyHerExtras(S,Id);
    UE_LOG(LogTemp,Display,TEXT("Street private: experience %d -> %d (%s)"),int32(Answer->GetNumberField(TEXT("level_before"))),int32(Answer->GetNumberField(TEXT("level_after"))),*Answer->GetStringField(TEXT("level_name")));
    // With her beside him they stay a while first and talk (the time after); the result waits for "leave".
    const TSharedPtr<FJsonObject>* Played=nullptr;
    if(S.Agents.IsValidIndex(Girl-1)&&FVector::Dist2D(S.Agents[Girl-1].Position,S.Male)<400.f&&Answer->TryGetObjectField(TEXT("result"),Played)&&(*Played)->GetBoolField(TEXT("played")))BeginAfter(Girl,Answer);
    else ShowHResult(Girl,*Answer);}
  }
 }
 S.PrivateTryOn=false;
 // Back on the street with her beside him: they go on talking (the scene started from their talk, which it ended).
 // Without this she went straight back to her schedule and walked off from the lunch he had just paid for. Opened from
 // the contacts with her elsewhere, there is nobody beside him to go on with.
 if(S.Agents.IsValidIndex(Girl-1)&&FVector::Dist2D(S.Agents[Girl-1].Position,S.Male)<400.f){S.FreeTalkOpen=true;ResumeTalkQuiet(Girl);
  UE_LOG(LogTemp,Display,TEXT("Street private: back with actor=%d, talk resumed=%d"),Girl,S.Target==Girl?1:0);}
 S.ContactsNotice=OKT(TEXT("ui.contacts.exited_one_on_one"));ApplyMouseMode(S.ViewportFocused);RefreshUI();
}
bool AOKStreetSocialScene::TickPrivate(double Now){
 auto& S=*State;if(S.PrivateGirl==INDEX_NONE)return false;
 // Tick stops at this function for the whole one-on-one, so the street's own motion never runs: every street figure goes
 // out of sight from here, and Tick puts them back after it (he and she are the high models meanwhile).
 {FString Hidden;OKSetCrowdRuntimeCharacterMotion(this,0,FTransform(S.Rotations[0],S.Male+OKStreetOffstage),0.f,Hidden);
  for(const auto& Agent:S.Agents)OKSetCrowdRuntimeCharacterMotion(this,Agent.Slot,FTransform(S.RenderedRotations[Agent.Slot],Agent.Position+OKStreetOffstage),0.f,Hidden);}
 // Esc leaves it like the leave button (the scene's own Esc check sees only real keys, not the control channel's).
 if(S.PrivateMode.IsValid()&&OKKeyPressed(GetWorld()->GetFirstPlayerController(),EKeys::Escape)){FinishPrivate();return true;}
 if(S.PrivateMode.IsValid()){
  // Talk while it happens: his line from the H panel goes to her as free talk (she is the partner while the scene is
  // open, FreeTalkPartner), with what she is in the middle of; her answer is shown on the panel.
  FString Line,Context;bool System=false;
  // Her reaction to a touch is out of date once he does something new (a kiss while she still talks about her chest):
  // the line she is saying ends, the rest is dropped and the new happening is sent now, as the original's voice follows
  // each action. His words and her answers to them are never cut.
  if(S.PrivateReplyIsReaction&&!S.FreeTalkBusy&&S.FreeTalkDraft.IsEmpty()&&HerReplyUnspoken()&&S.PrivateMode->HSceneHasReaction()){
   UE_LOG(LogTemp,Display,TEXT("H scene: %d unsaid lines of her last reaction dropped for a newer happening"),S.FreeTalkSpeechLines.Num()-S.FreeTalkSpeechPlayed);
   S.FreeTalkSpeechPlayed=S.FreeTalkSpeechLines.Num();}
  if(!S.FreeTalkBusy&&S.FreeTalkDraft.IsEmpty()&&!HerReplyUnspoken()&&S.PrivateMode->HSceneTakeLine(Line,Context,System)){S.PrivateTalkContext=Context;S.FreeTalkDraft=Line;S.SystemNote=System;S.PrivateReplyIsReaction=System;SendFreeTalk();}
  if(S.FreeTalkCaptionHer!=S.PrivateShownLine){S.PrivateShownLine=S.FreeTalkCaptionHer;S.PrivateMode->HSceneShowLine(S.FreeTalkCaptionHer);}
  S.PrivateMode->HSceneReplyPending(HerReplyUnspoken());
  return true;
 }
 FinishPrivate();if(S.SelfTest){S.Errors.Add(TEXT("Shared interaction mode disappeared without returning"));WriteReport(false);}return true;
}
void AOKStreetSocialScene::TickContacts(float Dt,double Now){
 auto& S=*State;
 if(S.PrivateGirl!=INDEX_NONE&&!ContactReady(S.PrivateGirl)){FinishPrivate();return;}
 TickAfter();
 // Her route is redrawn as she moves; not while the navigation is on its way to (or in) an elevator, or with her upstairs.
 // Across the city the route is drawn again every 5 s, not 0.75: each new one started him off from its first point, and he paced
 // back and forth on the street. She may not be drawn from there (ContactReady): only gone from the street ends it.
 if(S.NavGirl!=INDEX_NONE&&S.Agents.IsValidIndex(S.NavGirl-1)&&Now-S.NavAt>(OKStreetCityMode()&&OKStreetCityFar(S.Male,S.Agents[S.NavGirl-1].Position)?5.:.75)&&S.NavRide.Elevator==INDEX_NONE&&!NavNeedsLift(S.Agents[S.NavGirl-1].Position)){if(S.OnaniGirl==S.NavGirl){S.NavGirl=INDEX_NONE;S.NavPath.Reset();S.ContactsNotice=OKT(TEXT("ui.contacts.nav_target_unavailable"));RefreshUI();}else{S.NavAt=Now;S.NavPath=ContactRoute(S.Male,NavApproachSpot(S.Agents[S.NavGirl-1].Position));S.NavStep=1;}}
}
void AOKStreetSocialScene::RunContactsProbe(double Now){
 auto& S=*State;if(S.ContactsChecked){if(S.ContactsOnlyTest)WriteReport(S.Errors.IsEmpty());return;}
 auto Fail=[&](const TCHAR* Why){S.Errors.Add(Why);FinishPrivate();EndTalk();S.Store=S.ContactsProbeStore;S.Agents=S.ContactsProbeAgents;S.Rotations=S.ContactsProbeRotations;S.Male=S.ContactsProbeMale;WriteReport(false);};
 if(Now-S.ReadyAt>1800){Fail(TEXT("Contacts runtime probe timeout"));return;}
 if(S.ContactsProbePhase==0){
  // Visible geometry can precede asynchronous action admission.
  for(int32 I=1;I<S.Manifest.Characters.Num();++I)if(!ContactReady(I))return;
  S.ContactsProbeStore=S.Store;S.ContactsProbeAgents=S.Agents;S.ContactsProbeRotations=S.Rotations;S.ContactsProbeMale=S.Male;S.ContactsProbeAt=Now;S.ContactsOpen=true;S.ContactsSnapshot.Yaw=S.Yaw;S.ContactsSnapshot.Pitch=S.Pitch;S.ContactsSnapshot.Distance=S.Distance;S.ContactsSnapshot.Greetings=S.Greetings;
  auto Clear=[](const FVector& A,const FVector& B){for(int32 I=0;I<=100;++I){const FVector P=FMath::Lerp(A,B,I/100.f);if(P.X>40&&P.X<60&&FMath::Abs(P.Y)<20)return false;}return true;};
  const auto Detour=OKStreetContactRoute(FVector(0,0,0),FVector(100,0,0),{FVector(0,50,0),FVector(100,50,0)},Clear);
  if(Detour.Num()<3||!OKStreetContactRoute(FVector(0,0,0),FVector(100,0,0),{},Clear).IsEmpty()){Fail(TEXT("Navigation graph failed obstacle/unreachable check"));return;}
  for(const bool Intro:{false,true}){auto C=MakeShared<FJsonObject>();C->SetNumberField(TEXT("id"),0);C->SetStringField(TEXT("street_support"),TEXT("supported"));if(Intro){C->SetStringField(TEXT("context"),TEXT("introduction"));C->SetStringField(TEXT("rule"),TEXT("fallback_shuffle_pool"));}TArray<FString> Terms;int32 Id;FString Filter,Support,Error;if(!OKStreetAppendConditionObject(C,Terms,Id,Filter,Support,Error)||!Terms.Contains(Intro?TEXT("speak=always"):TEXT("speak=never"))){Fail(TEXT("Lover introduction fallback confused with Speak condition zero"));return;}}
  for(auto& A:S.Agents)A.Held=true;
   for(int32 I=1;I<S.Manifest.Characters.Num();++I){NavigateGirl(I);if(S.NavGirl!=I||S.NavPath.Num()<2){Fail(TEXT("Roster girl navigation path missing"));return;}++S.ContactsRoutes;const int32 R=OKStreetRelationIndex(S.Store,OKStreetStableId(S.Manifest.Characters[I]),S.Manifest.TalkBudget,true);S.Store.Relations[R].Stage=TEXT("lover");}
  SelectContact(5);RebuildUI(); // RefreshUI only marks the panel dirty; count what is actually built
  if(S.ContactSelection!=5||S.ContactRows!=5||S.ContactActions!=2||S.Target!=INDEX_NONE){Fail(TEXT("Roster must use one shared two-action panel without changing conversation"));return;}S.ContactsUI=true;
  S.ContactsProbePhase=3;return;
 }
 if(S.PrivateAnyCase<15){
  const int32 Character=S.PrivateAnyCase/3+1,Stage=S.PrivateAnyCase%3;const TCHAR* Stages[]={TEXT("stranger"),TEXT("friend"),TEXT("lover")};
  if(S.PrivateAnyPhase==0){
   // Each heroine's profile arrives once, asynchronously, and initializes saved fields (wallet, stranger cap). Take
   // the "before" save after all of them, or a profile landing during the high scene reads as a changed street state.
   int32 Missing=0;for(int32 G=1;G<S.Manifest.Characters.Num();++G)if(!S.MindProfiles.Contains(OKStreetStableId(S.Manifest.Characters[G])))++Missing;
   if(Missing>0){
    const double Now=FPlatformTime::Seconds();if(S.PrivateAnyProfileWait<=0)S.PrivateAnyProfileWait=Now;
    if(Now-S.PrivateAnyProfileWait<120)return;
    UE_LOG(LogTemp,Warning,TEXT("Private-scene test: %d heroine profiles still missing after 120 s; testing without them"),Missing);
   }
   S.PrivateAnyProfileWait=0;
   EndTalk();const int32 R=OKStreetRelationIndex(S.Store,OKStreetStableId(S.Manifest.Characters[Character]),S.Manifest.TalkBudget,true);S.Store.Relations[R].Stage=Stages[Stage];S.Store.Relations[R].Favor=0;S.Store.Relations[R].TalksRemaining=5;S.PrivateAnySave=OKStreetWriteSave(S.Store);
   S.HighPrivateAgents=S.Agents;S.HighPrivateRotations=S.Rotations;S.HighPrivateMale=S.Male;
   BeginPrivate(Character);if(S.PrivateGirl!=Character){Fail(TEXT("Any-relationship high-model scene admission failed"));return;}S.PrivateAnyPhase=1;return;
  }
  if(S.PrivateGirl!=INDEX_NONE)return;
  if(!S.HighPrivateResult||!S.HighPrivateResult->GetBoolField(TEXT("same_process"))||int32(S.HighPrivateResult->GetNumberField(TEXT("process_id")))!=int32(FPlatformProcess::GetCurrentProcessId())||S.HighPrivateResult->GetStringField(TEXT("state"))!=TEXT("returned")||!S.HighPrivateResult->GetBoolField(TEXT("partner_ready"))||S.HighPrivateResult->GetStringField(TEXT("scene_class"))!=TEXT("/Script/OpenKoikatsu.OKInteractionScene")||OKStreetWriteSave(S.Store)!=S.PrivateAnySave||S.Male!=S.HighPrivateMale||S.Rotations!=S.HighPrivateRotations){UE_LOG(LogTemp,Error,TEXT("Shared return mismatch result=%d save=%d male=%d rotations=%d"),S.HighPrivateResult.IsValid(),OKStreetWriteSave(S.Store)==S.PrivateAnySave,S.Male==S.HighPrivateMale,S.Rotations==S.HighPrivateRotations);
   // Both saves beside the report, so a changed field can be found.
   if(OKStreetWriteSave(S.Store)!=S.PrivateAnySave){const FString Dir=FPaths::GetPath(S.Manifest.SocialReport);FFileHelper::SaveStringToFile(S.PrivateAnySave,*(Dir/TEXT("shared-return.before.json")));FFileHelper::SaveStringToFile(OKStreetWriteSave(S.Store),*(Dir/TEXT("shared-return.after.json")));}
   Fail(TEXT("High-model private return did not preserve original street state"));return;}
  for(int32 I=0;I<S.Agents.Num();++I)if(S.Agents[I].Position!=S.HighPrivateAgents[I].Position||S.Agents[I].Held!=S.HighPrivateAgents[I].Held){Fail(TEXT("A crowd agent moved while high scene was active"));return;}
  auto E=MakeShared<FJsonObject>();E->SetNumberField(TEXT("slot"),Character);E->SetNumberField(TEXT("stage"),Stage);E->SetStringField(TEXT("report"),S.HighPrivateReport);E->SetObjectField(TEXT("high_model"),S.HighPrivateResult);S.PrivateAnyEvidence.Add(MakeShared<FJsonValueObject>(E));
  if(Stage==2)++S.ContactsPrivate;
  ++S.PrivateAnyCase;S.PrivateAnyPhase=0;return;
 }
 S.Store=S.ContactsProbeStore;S.Agents=S.ContactsProbeAgents;S.Rotations=S.ContactsProbeRotations;S.Male=S.ContactsProbeMale;S.NavGirl=INDEX_NONE;S.NavPath.Reset();S.Yaw=S.ContactsSnapshot.Yaw;S.Pitch=S.ContactsSnapshot.Pitch;S.Distance=S.ContactsSnapshot.Distance;S.Greetings=S.ContactsSnapshot.Greetings;S.ContactsNotice.Reset();S.ContactsChecked=true;S.ContactsOpen=false;S.ContactSelection=INDEX_NONE;RefreshUI();
}
