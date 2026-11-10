// Getting about town by bus or taxi (R6-203). The city is a kilometre across and two people walk it at 2.75 m a game
// minute: the dorm to the convenience store was four hours on foot. The rules (ok-rules transit.rs) quote the bus
// (between its fixed stops, at the doors of the places it names) and the taxi (to the door) for a long walk; she hears
// them with the walk's minutes and may say "let's take the bus" (take_bus / take_taxi), he has them as buttons. A ride
// is his fare paid, the minutes gone by, and the two of them set down where it stops; the walk goes on from there.

// The quote for a walk of WalkCm from where he is to Drop (the place's door); her words about it ("" when no ride is
// worth it). Kept for the buttons and the ride until the walk ends.
FString AOKStreetSocialScene::QuoteTransit(int32 Girl,float WalkCm,const FVector& Drop){
 auto& S=*State;S.TransitQuote.Reset();S.TransitFor=INDEX_NONE;
 if(!OKStreetCityMode())return FString();
 static TArray<FString> StopIds;
 if(StopIds.IsEmpty())if(const TSharedPtr<FJsonObject> Out=OKRulesEval(S,OKRulesRequest(TEXT("transit_stops")))){
  const TArray<TSharedPtr<FJsonValue>>* A=nullptr;if(Out->TryGetArrayField(TEXT("stops"),A))for(const auto& V:*A)StopIds.Add(V->AsString());}
 auto Point=[](const FVector& P){TArray<TSharedPtr<FJsonValue>> A;A.Add(MakeShared<FJsonValueNumber>(P.X/100.0));A.Add(MakeShared<FJsonValueNumber>(P.Y/100.0));return A;};
 TSharedRef<FJsonObject> Ask=OKRulesRequest(TEXT("transit_quote"));
 Ask->SetNumberField(TEXT("walk_m"),WalkCm/100.0);Ask->SetArrayField(TEXT("from"),Point(S.Male));Ask->SetArrayField(TEXT("to"),Point(Drop));
 TArray<TSharedPtr<FJsonValue>> Stops;
 for(const FString& Id:StopIds)if(const FOKStreetPlace* P=OKStreetFindPlace(Id)){TSharedRef<FJsonObject> O=MakeShared<FJsonObject>();
  O->SetStringField(TEXT("id"),Id);O->SetNumberField(TEXT("x"),P->Door.X/100.0);O->SetNumberField(TEXT("y"),P->Door.Y/100.0);Stops.Add(MakeShared<FJsonValueObject>(O));}
 Ask->SetArrayField(TEXT("stops"),Stops);Ask->SetNumberField(TEXT("people"),2);Ask->SetNumberField(TEXT("cash"),double(S.Store.PlayerCash));
 const TSharedPtr<FJsonObject> Out=OKRulesEval(S,Ask);if(!Out)return FString();
 auto StopName=[](const FString& Id){const FOKStreetPlace* P=OKStreetFindPlace(Id);return P?FString(P->Name):Id;};
 FString Options;
 for(const TCHAR* Mode:{TEXT("bus"),TEXT("taxi")}){
  const TSharedPtr<FJsonObject>* Offer=nullptr;if(!Out->TryGetObjectField(Mode,Offer)||!Offer||!Offer->IsValid())continue;
  const FString Line=OKMsg(*(FString(TEXT("ui.transit."))+Mode+TEXT("_option")),{{TEXT("minutes"),int64((*Offer)->GetNumberField(TEXT("minutes")))},{TEXT("fare"),int64((*Offer)->GetNumberField(TEXT("fare")))},
   {TEXT("board"),StopName((*Offer)->GetStringField(TEXT("board")))},{TEXT("alight"),StopName((*Offer)->GetStringField(TEXT("alight")))}});
  Options+=(Options.IsEmpty()?FString():FString(OKT(TEXT("ui.transit.option_separator"))))+Line;
 }
 if(Options.IsEmpty())return FString();
 S.TransitQuote=Out;S.TransitFor=Girl;S.TransitDrop=Drop;
 UE_LOG(LogTemp,Display,TEXT("Street transit: actor=%d walk %.0f m; %s (suggest %s)"),Girl,WalkCm/100.f,*Options,*Out->GetStringField(TEXT("suggest")));
 return OKMsg(TEXT("ui.transit.tell_her"),{{TEXT("options"),Options}});
}

// The ride: "bus" or "taxi" from the quote of the walk they are on. He pays both fares; the clock moves on by the ride
// (not past the day's end); they are set down at the stop by where they go (bus) or at its door (taxi), and walk on.
bool AOKStreetSocialScene::TakeTransit(const FString& Mode,bool HerIdea){
 auto& S=*State;const int32 Girl=S.OutingGirl;
 if(Girl==INDEX_NONE||S.TransitFor!=Girl||!S.TransitQuote.IsValid()||!S.Agents.IsValidIndex(Girl-1)){UE_LOG(LogTemp,Display,TEXT("Street transit: no %s offered now"),*Mode);return false;}
 const TSharedPtr<FJsonObject>* Offer=nullptr;
 if(!S.TransitQuote->TryGetObjectField(Mode,Offer)||!Offer||!Offer->IsValid()){UE_LOG(LogTemp,Display,TEXT("Street transit: %s not offered for this walk"),*Mode);
  if(HerIdea)S.TellHer.Add(OKT(*(FString(TEXT("ui.transit.no_"))+Mode+TEXT("_note"))));return false;}
 const bool Bus=Mode==TEXT("bus");
 const int64 Fare=int64((*Offer)->GetNumberField(TEXT("fare")));const int32 Minutes=int32((*Offer)->GetNumberField(TEXT("minutes")));
 if(!SpendCash(Fare,OKT(Bus?TEXT("ui.transit.why_bus"):TEXT("ui.transit.why_taxi")))){
  UE_LOG(LogTemp,Display,TEXT("Street transit: %s fare %lld, he cannot pay"),*Mode,Fare);
  S.TellHer.Add(OKMsg(TEXT("ui.transit.cannot_pay_note"),{{TEXT("fare"),Fare}}));RefreshUI();return false;}
 // The rest of the walk from the place's door (or the stop near it).
 int32 Door=FMath::Clamp(S.OutingStep,0,S.OutingRoute.Num()-1);
 for(int32 K=Door;K<S.OutingRoute.Num();++K)if(FVector::Dist2D(S.OutingRoute[K],S.TransitDrop)<FVector::Dist2D(S.OutingRoute[Door],S.TransitDrop))Door=K;
 FString Where;
 if(Bus){
  const FString Alight=(*Offer)->GetStringField(TEXT("alight"));const FOKStreetPlace* Stop=OKStreetFindPlace(Alight);
  const FVector At=Stop?Stop->Door:S.OutingRoute[Door];Where=Stop?FString(Stop->Name):S.OutingPlace;
  TArray<FVector> Rest=PlaceRoute(At,S.OutingRoute[Door]);if(Rest.Num()<2)Rest={At,S.OutingRoute[Door]};
  for(int32 K=Door+1;K<S.OutingRoute.Num();++K)Rest.Add(S.OutingRoute[K]);
  S.OutingRoute=MoveTemp(Rest);S.OutingStep=1;S.Male=At;
 }else{S.Male=S.OutingRoute[Door];S.OutingStep=FMath::Min(Door+1,S.OutingRoute.Num()-1);Where=S.OutingPlace;}
 // She gets out with him.
 {FVector Side=FVector::CrossProduct(FVector::UpVector,FRotator(0,S.Yaw,0).Vector());Side.Z=0;Side=Side.GetSafeNormal()*80.f;FVector Her=S.Male+Side;
  for(int32 Turn=0;Turn<8&&OKStreetBlockedPoint(Her,28.f);++Turn)Her=S.Male+Side.RotateAngleAxis(45.f*(Turn+1),FVector::UpVector);
  Her.Z=S.Male.Z;S.Agents[Girl-1].Position=Her;}
 S.CompanionTrail.Reset();S.CompanionTrail.Add(S.Male);S.CompanionLastMale=S.Male;S.CompanionBlockedAt=0;S.OutingProgressAt=SceneTime();
 StopNavigation(FString());S.ManualReplan=false;
 // The ride's minutes, not past the day's end (as an activity's time goes by, OKStreetSocialLife.inl).
 {const double Hours=S.ClockPaused?S.ClockStartHours:OKStreetClockHours(S.ClockStartHours,FPlatformTime::Seconds()-S.ClockStartWall);
  const double Add=FMath::Min(Minutes/60.0,FMath::Max(0.0,23.75-Hours));if(Add>0){S.ClockStartHours+=Add;S.NextSunUpdate=0;}}
 const FString How=OKT(Bus?TEXT("ui.transit.by_bus"):TEXT("ui.transit.by_taxi"));
 S.Message=OKMsg(TEXT("ui.transit.rode"),{{TEXT("how"),How},{TEXT("place"),Where},{TEXT("minutes"),Minutes},{TEXT("fare"),Fare}});
 S.TellHer.Add(OKMsg(TEXT("ui.transit.rode_note"),{{TEXT("how"),How},{TEXT("place"),Where},{TEXT("minutes"),Minutes},{TEXT("fare"),Fare}}));
 MindRemember(Girl,TEXT("outing"),OKMsg(TEXT("ui.transit.memory_rode"),{{TEXT("how"),How},{TEXT("place"),S.OutingPlace}}),S.OutingPlace,0.2f);
 UE_LOG(LogTemp,Display,TEXT("Street transit: actor=%d rode by %s (%s) to %s: %d min, fare %lld, set down at %s, %d route points left"),Girl,*Mode,HerIdea?TEXT("her idea"):TEXT("his"),*Where,Minutes,Fare,*S.Male.ToCompactString(),S.OutingRoute.Num()-S.OutingStep);
 S.TransitQuote.Reset();S.TransitFor=INDEX_NONE;
 RefreshUI();return true;
}
