// Included by OKStreetSocialScene.cpp: the control channel, always open (OKControl: 127.0.0.1 only, port
// -StreetSocialControlPort, else port_base + 10). It lets a developer or a test driver play the game from outside: read the full state, type to the heroine, press the buttons on screen by their label, press keys
// (walking is real walking: the keys go through OKKeyDown/OKKeyPressed like a real keyboard), look around, start the
// built-in navigation and take screenshots. Requests are answered on the game thread between ticks.
// -StreetSocialControl (the launcher's -Control) adds what a driver wants and a player does not (OKVirtualInput().Driven).

static bool GControlStarted=false,GControlRestoreMouse=false;
static double GControlRestoreMouseAt=0;
static int32 GControlShots=0;

// /camera: a fixed camera on one actor's bone (for like-for-like looks against the card reader's capture camera). Yaw and
// pitch are relative to the actor's facing (yaw 0 = in front of her, 90 = her left side); ortho_width > 0 is orthographic.
struct FOKControlCamera {bool Active=false;int32 Actor=1;FName Bone=TEXT("cf_j_head");double Yaw=90,Pitch=0,Distance=80,Fov=30,Ortho=0,SavedFov=90;};
static FOKControlCamera GControlCamera;
static bool OKApplyControlCamera(AActor* Owner,ACameraActor* Camera,const TSharedPtr<FJsonObject>& Report=nullptr){
 const auto& C=GControlCamera;FOKRuntimeCharacterStatus Status;FTransform Bone;
 if(!Camera||!OKGetCrowdRuntimeCharacterStatus(Owner,C.Actor,Status)||!OKGetCrowdRuntimeBoneTransform(Owner,C.Actor,C.Bone,Bone)||Bone.ContainsNaN())return false;
 const FVector Direction=Status.Transform.GetRotation().RotateVector(FRotator(C.Pitch,C.Yaw,0).Vector());
 const FVector Location=Bone.GetLocation()+Direction*C.Distance;Camera->SetActorLocationAndRotation(Location,(-Direction).Rotation());
 if(auto* Lens=Camera->GetCameraComponent()){Lens->SetConstraintAspectRatio(false);Lens->SetFieldOfView(C.Fov);Lens->SetProjectionMode(C.Ortho>0?ECameraProjectionMode::Orthographic:ECameraProjectionMode::Perspective);if(C.Ortho>0)Lens->SetOrthoWidth(C.Ortho);}
 if(Report.IsValid()){
  Report->SetStringField(TEXT("actor_rotation"),Status.Transform.Rotator().ToString());Report->SetStringField(TEXT("camera_location"),Location.ToString());
  // Head-related bone worlds (location, rotation, scale) to compare with the card reader / native session.
  auto Bones=MakeShared<FJsonObject>();
  for(const TCHAR* Name:{TEXT("cf_j_neck"),TEXT("cf_j_head"),TEXT("cf_s_head"),TEXT("p_cf_head_bone"),TEXT("cf_J_N_FaceRoot"),TEXT("cf_J_FaceRoot"),TEXT("cf_J_FaceBase"),TEXT("cf_J_FaceUp_ty"),TEXT("cf_J_FaceUp_tz"),TEXT("cf_J_FaceLow_s")}){
   FTransform T;if(!OKGetCrowdRuntimeBoneTransform(Owner,C.Actor,Name,T))continue;auto B=MakeShared<FJsonObject>();
   B->SetStringField(TEXT("location"),T.GetLocation().ToString());B->SetStringField(TEXT("rotation"),T.Rotator().ToString());B->SetStringField(TEXT("scale"),T.GetScale3D().ToString());
   B->SetStringField(TEXT("local_to_head"),Bone.InverseTransformPosition(T.GetLocation()).ToString());Bones->SetObjectField(Name,B);}
  Report->SetObjectField(TEXT("bones"),Bones);}
 return true;
}

// The map ending (quit, or started again for a load or a new game): the routes point at this scene, so they go with it
// and the next scene binds its own.
static void OKControlStop(){
 OKControl::Unbind(TEXT("street"));GControlStarted=false;
}

static void OKControlReply(const FHttpResultCallback& Done,const TSharedRef<FJsonObject>& Body,int32 Code=200){
 FString Text;auto Writer=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text);FJsonSerializer::Serialize(Body,Writer);
 auto Response=FHttpServerResponse::Create(Text,TEXT("application/json; charset=utf-8"));Response->Code=static_cast<EHttpServerResponseCodes>(Code);Done(MoveTemp(Response));
}
extern ENGINE_API float GAverageFPS; // UnrealEngine.cpp, not in a public header (the /fps readout)
static TSharedRef<FJsonObject> OKControlResult(bool Ok,const FString& Error=FString()){auto O=MakeShared<FJsonObject>();O->SetBoolField(TEXT("ok"),Ok);if(!Error.IsEmpty())O->SetStringField(TEXT("error"),Error);return O;}
static TSharedRef<FJsonObject> OKControlBody(const FHttpServerRequest& Req){
 const FUTF8ToTCHAR Utf8(reinterpret_cast<const ANSICHAR*>(Req.Body.GetData()),Req.Body.Num());
 const FString Text(Utf8.Length(),Utf8.Get());
 TSharedPtr<FJsonObject> Root;
 if(Text.IsEmpty()||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Root)||!Root.IsValid())Root=MakeShared<FJsonObject>();
 return Root.ToSharedRef();
}

void AOKStreetSocialScene::StartControlServer(){
 int32 Port=0;FParse::Value(FCommandLine::Get(),TEXT("StreetSocialControlPort="),Port);
 OKVirtualInput().Active=true;OKVirtualInput().Driven|=FParse::Param(FCommandLine::Get(),TEXT("StreetSocialControl"));
 Port=OKControl::Listen(TEXT("street"),10,Port);
 if(!Port){UE_LOG(LogTemp,Warning,TEXT("Street control: no port"));return;}

 // The whole picture of the game for whoever is playing from outside.
 auto Build=[this]()->TSharedRef<FJsonObject>{
  auto& S=*State;auto O=MakeShared<FJsonObject>();const double Wall=FPlatformTime::Seconds();
  const double Hours=OKStreetClockHours(S.ClockStartHours,Wall-S.ClockStartWall);
  {auto T=MakeShared<FJsonObject>();T->SetNumberField(TEXT("hours"),Hours);T->SetStringField(TEXT("clock"),FString::Printf(TEXT("%02d:%02d"),int32(Hours),int32((Hours-int32(Hours))*60)));T->SetBoolField(TEXT("paused"),S.ClockPaused);
   T->SetNumberField(TEXT("game_day"),S.Store.CalendarDay);T->SetStringField(TEXT("date"),OKStreetCalendarDateTime(S.Store.CalendarDay,Hours).ToString(TEXT("%Y-%m-%d")));O->SetObjectField(TEXT("time"),T);} // the date shown (before 04:00 the game day before's next date)
  {auto P=MakeShared<FJsonObject>();P->SetNumberField(TEXT("x"),S.Male.X);P->SetNumberField(TEXT("y"),S.Male.Y);P->SetNumberField(TEXT("z"),S.Male.Z);P->SetNumberField(TEXT("yaw"),S.Rotations.IsValidIndex(0)?S.Rotations[0].Yaw:0.0);
   P->SetStringField(TEXT("place"),PlaceHere(S.Male));P->SetNumberField(TEXT("gap"),OKStreetObstacleGap(S.Male));P->SetNumberField(TEXT("node"),S.Node);P->SetBoolField(TEXT("relationship_pending"),S.RelationshipPending);P->SetBoolField(TEXT("collected_active"),S.CollectedActive);P->SetBoolField(TEXT("cursor_mode"),S.MouseUI);P->SetNumberField(TEXT("camera_yaw"),S.Yaw);P->SetNumberField(TEXT("camera_pitch"),S.Pitch);
   P->SetNumberField(TEXT("cash"),double(S.Store.PlayerCash));P->SetNumberField(TEXT("bank"),double(S.Store.PlayerBank));O->SetObjectField(TEXT("player"),P);}
  O->SetStringField(TEXT("message"),S.Message);O->SetStringField(TEXT("notice"),S.FreeTalkNotice);O->SetBoolField(TEXT("all_ready"),S.AllReady); // every character loaded (the "all ready" hint in any language)
  O->SetNumberField(TEXT("target"),S.Target);O->SetNumberField(TEXT("partner"),FreeTalkPartner());O->SetNumberField(TEXT("ring"),S.RingGirl); // ring: who is calling him now (-1: nobody)
  {TArray<TSharedPtr<FJsonValue>> Party;for(const int32 G:S.Party)Party.Add(MakeShared<FJsonValueNumber>(G));O->SetArrayField(TEXT("party"),Party);O->SetBoolField(TEXT("bluff"),S.Bluff.Active);}
  {TArray<TSharedPtr<FJsonValue>> Appts;for(const auto& A:S.Store.Appointments){if(A.Status!=TEXT("pending"))continue;auto R=MakeShared<FJsonObject>();
    R->SetNumberField(TEXT("id"),A.Id);R->SetStringField(TEXT("kind"),A.Kind);R->SetStringField(TEXT("label"),A.Label);R->SetNumberField(TEXT("start"),double(A.Start));Appts.Add(MakeShared<FJsonValueObject>(R));}
   O->SetArrayField(TEXT("appointments"),Appts);}
  // The elevator near him (diagnostics): its floor, doors, the side it opens to and whether he is in the car; and his
  // gap to the nearest known obstacle.
  {O->SetNumberField(TEXT("obstacle_gap"),OKStreetObstacleGap(S.Male));
   {TArray<TSharedPtr<FJsonValue>> Near;for(const FBox& Bx:OKStreetRuntimeBlocks()){const FVector C=Bx.GetCenter();if(FVector::Dist2D(C,S.Male)<300.f)Near.Add(MakeShared<FJsonValueString>(Bx.Min.ToCompactString()+TEXT(" .. ")+Bx.Max.ToCompactString()));}
    O->SetArrayField(TEXT("blocks_near"),Near);}
   for(int32 I=0;I<S.Elevators.Num();++I){const auto& E=S.Elevators[I];if(FVector::Dist2D(E.Centre,S.Male)>1500.f)continue;
    auto L=MakeShared<FJsonObject>();L->SetStringField(TEXT("place"),OKStreetPlaces()[E.Place].Id);L->SetNumberField(TEXT("floor"),E.Floor);L->SetNumberField(TEXT("target"),E.Target);L->SetNumberField(TEXT("phase"),E.Phase);
    L->SetNumberField(TEXT("car_z"),E.CarZ);L->SetBoolField(TEXT("he_in_car"),InElevatorCar(I,S.Male));L->SetNumberField(TEXT("landing_here"),ElevatorLanding(I,S.Male));
    L->SetStringField(TEXT("centre"),E.Centre.ToCompactString());if(E.Out.IsValidIndex(E.Floor))L->SetStringField(TEXT("out"),E.Out[E.Floor].ToCompactString());if(E.Landing.IsValidIndex(E.Floor))L->SetStringField(TEXT("landing"),E.Landing[E.Floor].ToCompactString());
    O->SetObjectField(TEXT("elevator"),L);break;}}
  {auto A=MakeShared<FJsonObject>();A->SetNumberField(TEXT("partner"),S.Pair.Partner);A->SetNumberField(TEXT("phase"),S.Pair.Phase);A->SetBoolField(TEXT("meal"),S.Pair.Meal);A->SetBoolField(TEXT("seated"),S.Pair.Seated);A->SetBoolField(TEXT("drink"),S.Pair.Drink);O->SetObjectField(TEXT("pair"),A);}
  {auto A=MakeShared<FJsonObject>();A->SetNumberField(TEXT("companion"),S.Companion);A->SetNumberField(TEXT("outing_girl"),S.OutingGirl);A->SetStringField(TEXT("outing_activity"),S.OutingActivity);A->SetStringField(TEXT("outing_place"),S.OutingPlace);
   A->SetNumberField(TEXT("outing_step"),S.OutingStep);A->SetNumberField(TEXT("outing_points"),S.OutingRoute.Num());A->SetNumberField(TEXT("nav_girl"),S.NavGirl);A->SetBoolField(TEXT("nav_point"),S.NavPointActive);A->SetStringField(TEXT("nav_name"),S.NavPointName);
   A->SetNumberField(TEXT("facility"),S.Facility);A->SetNumberField(TEXT("private_girl"),S.PrivateGirl);O->SetObjectField(TEXT("activity"),A);}
  {auto F=MakeShared<FJsonObject>();F->SetBoolField(TEXT("open"),S.FreeTalkOpen);F->SetBoolField(TEXT("live"),S.FreeTalkLive);F->SetBoolField(TEXT("live_ready"),S.FreeTalkLiveReady);F->SetBoolField(TEXT("busy"),S.FreeTalkBusy);
   F->SetStringField(TEXT("heard"),S.FreeTalkHeard);F->SetNumberField(TEXT("mic_level"),S.FreeTalkMicLevel);F->SetBoolField(TEXT("mic_speaking"),S.FreeTalkLiveSpeaking);F->SetStringField(TEXT("draft"),S.FreeTalkDraft);
   F->SetStringField(TEXT("caption_player"),S.FreeTalkCaptionPlayer);F->SetStringField(TEXT("caption_her"),S.FreeTalkCaptionHer);F->SetBoolField(TEXT("farewell_pending"),S.FarewellPending);F->SetNumberField(TEXT("queued_events"),S.TellHer.Num());O->SetObjectField(TEXT("free_talk"),F);}
  {TArray<TSharedPtr<FJsonValue>> Rows;for(const auto& L:S.Cart){auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("item"),L.ItemId);if(const auto* I=S.Catalog.Find(L.ItemId))R->SetStringField(TEXT("name"),I->Name);R->SetBoolField(TEXT("for_her"),L.ForHer);Rows.Add(MakeShared<FJsonValueObject>(R));}O->SetArrayField(TEXT("cart"),Rows);}
  {TArray<TSharedPtr<FJsonValue>> Rows;for(const auto& D:S.Table){auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("name"),D.Name);R->SetBoolField(TEXT("for_her"),D.ForHer);R->SetBoolField(TEXT("served"),D.Served);R->SetNumberField(TEXT("percent"),D.Percent);Rows.Add(MakeShared<FJsonValueObject>(R));}O->SetArrayField(TEXT("table"),Rows);}
  O->SetNumberField(TEXT("pending_serves"),S.Serves.Num());O->SetStringField(TEXT("shop"),ShopPlaceHere());
  {FString Why;O->SetBoolField(TEXT("shop_closed"),!ShopPlaceHere().IsEmpty()&&PlaceClosedNow(ShopPlaceHere(),Why));}
  {TArray<TSharedPtr<FJsonValue>> Rows;
   for(int32 I=1;I<S.Manifest.Characters.Num();++I)if(S.Agents.IsValidIndex(I-1)){
    const auto& A=S.Agents[I-1];auto G=MakeShared<FJsonObject>();
    G->SetNumberField(TEXT("slot"),I);G->SetStringField(TEXT("name"),S.Manifest.Characters[I].Name);
    G->SetNumberField(TEXT("x"),A.Position.X);G->SetNumberField(TEXT("y"),A.Position.Y);G->SetNumberField(TEXT("z"),A.Position.Z);G->SetNumberField(TEXT("dist"),FVector::Dist2D(A.Position,S.Male));
    G->SetNumberField(TEXT("yaw_target"),S.Rotations.IsValidIndex(I)?S.Rotations[I].Yaw:0.0);G->SetNumberField(TEXT("yaw_body"),S.RenderedRotations.IsValidIndex(I)?S.RenderedRotations[I].Yaw:0.0);
    G->SetBoolField(TEXT("held"),A.Held);G->SetNumberField(TEXT("mode"),int32(A.Mode));G->SetStringField(TEXT("place"),PlaceHere(A.Position));
    G->SetBoolField(TEXT("target"),S.Target==I);G->SetBoolField(TEXT("companion"),S.Companion==I);G->SetBoolField(TEXT("outing"),S.OutingGirl==I);G->SetBoolField(TEXT("pair"),S.Pair.Partner==I);
    G->SetBoolField(TEXT("life_pose"),InLifePose(I));G->SetBoolField(TEXT("commute"),S.Commutes.Contains(I));G->SetBoolField(TEXT("scheduled"),S.ScheduleHeld.Contains(I));G->SetBoolField(TEXT("promised_treat"),HerTreatPromised(I));G->SetBoolField(TEXT("lover_pose"),S.LoverPose.Girl==I);G->SetBoolField(TEXT("lover_react"),S.LoverReact.Girl==I);
    FOKRuntimeActionStreamStatus Act;const bool HasAct=OKGetCrowdRuntimeActionStatus(this,I,Act);G->SetStringField(TEXT("clip"),HasAct?Act.ClipId:FString());G->SetBoolField(TEXT("playing"),HasAct&&Act.Playing);G->SetBoolField(TEXT("speaking"),OKCrowdRuntimeSpeechActive(this,I));
    const FOKStreetRelation R=OKStreetViewRelation(S.Store,OKStreetStableId(S.Manifest.Characters[I]),S.Manifest.TalkBudget);
    G->SetNumberField(TEXT("gap"),OKStreetObstacleGap(A.Position));G->SetStringField(TEXT("stage"),R.Stage);G->SetNumberField(TEXT("favor"),R.Favor);G->SetNumberField(TEXT("cash"),double(R.Cash));G->SetNumberField(TEXT("owes_player"),double(R.OwesPlayer));G->SetNumberField(TEXT("satiety"),R.Satiety);G->SetNumberField(TEXT("energy"),R.Energy);
    G->SetStringField(TEXT("orientation"),OrientationOf(I));
    {auto Bonds=MakeShared<FJsonObject>();for(int32 J=1;J<S.Manifest.Characters.Num();++J)if(J!=I){auto B=MakeShared<FJsonObject>();B->SetNumberField(TEXT("favor"),BondOf(I,J));B->SetStringField(TEXT("stage"),BondStageOf(I,J));Bonds->SetObjectField(S.Manifest.Characters[J].Name,B);}G->SetObjectField(TEXT("toward"),Bonds);}
    Rows.Add(MakeShared<FJsonValueObject>(G));}
   O->SetArrayField(TEXT("girls"),Rows);}
  return O;
 };

 auto Bind=[&](const TCHAR* Path,EHttpServerRequestVerbs Verb,TFunction<void(const FHttpServerRequest&,const FHttpResultCallback&)> Fn){
  OKControl::Bind(TEXT("street"),Path,Verb,MoveTemp(Fn));
 };

 Bind(TEXT("/health"),EHttpServerRequestVerbs::VERB_GET,[](const FHttpServerRequest&,const FHttpResultCallback& Done){OKControlReply(Done,OKControlResult(true));});
 Bind(TEXT("/state"),EHttpServerRequestVerbs::VERB_GET,[Build](const FHttpServerRequest&,const FHttpResultCallback& Done){OKControlReply(Done,Build());});

 // He says something to her: the same path as typing it, or as the recogniser handing over what it heard.
 Bind(TEXT("/say"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;FString Said;OKControlBody(Req)->TryGetStringField(TEXT("text"),Said);const FString Text=Said.TrimStartAndEnd();
  if(Text.IsEmpty()){OKControlReply(Done,OKControlResult(false,TEXT("empty text")));return;}
  if(FreeTalkPartner()==INDEX_NONE){OKControlReply(Done,OKControlResult(false,TEXT("nobody to talk to")));return;}
  if(S.FreeTalkBusy){OKControlReply(Done,OKControlResult(false,TEXT("busy: she is still answering")));return;}
  if(SongIsSinging()&&S.Song.Girl==FreeTalkPartner()){OKControlReply(Done,OKControlResult(false,TEXT("busy: she is singing")));return;}
  S.SystemNote=false;S.FreeTalkHeard=Text;S.FreeTalkDraft=Text;SendFreeTalk();
  OKControlReply(Done,OKControlResult(true));
 });

 // Types into the phone's message box of the open thread and presses send (the thread is chosen with the phone's buttons).
 Bind(TEXT("/phone"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;FString Said;OKControlBody(Req)->TryGetStringField(TEXT("text"),Said);
  if(S.App!=TEXT("phone")){OKControlReply(Done,OKControlResult(false,TEXT("the phone is not open")));return;}
  if(Said.TrimStartAndEnd().IsEmpty()){OKControlReply(Done,OKControlResult(false,TEXT("empty text")));return;}
  if(S.FreeTalkBusy){OKControlReply(Done,OKControlResult(false,TEXT("busy: she is still answering")));return;}
  S.PhoneDraft=Said;PhoneSend();OKControlReply(Done,OKControlResult(true));
 });

 // Types into a text box of the panels, as keys would: {box: n} (the n-th box on screen) or {hint: "..."} (part of its
 // hint text), {text}, {enter: true} to press Enter after. Without text: the boxes on screen (index, hint, text).
 Bind(TEXT("/type"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);FString Text,Hint,Label;double Box=-1;bool Enter=false;
  const bool HasText=B->TryGetStringField(TEXT("text"),Text);B->TryGetStringField(TEXT("hint"),Hint);B->TryGetStringField(TEXT("label"),Label);B->TryGetNumberField(TEXT("box"),Box);B->TryGetBoolField(TEXT("enter"),Enter);
  // Each box with the text shown just before it (its label: 价格, 股数…), which stays put when boxes come and go.
  TArray<TSharedRef<SEditableTextBox>> Boxes;TArray<FString> Labels;FString LastText;
  TFunction<void(const TSharedRef<SWidget>&)> Walk=[&](const TSharedRef<SWidget>& W){
   if(W->GetType()==FName(TEXT("SEditableTextBox"))){if(!W->GetCachedGeometry().GetLocalSize().IsNearlyZero()){Boxes.Add(StaticCastSharedRef<SEditableTextBox>(W));Labels.Add(LastText);}return;}
   if(W->GetType()==FName(TEXT("STextBlock")))LastText=StaticCastSharedRef<STextBlock>(W)->GetText().ToString();
   if(FChildren* C=W->GetChildren())for(int32 I=0;I<C->Num();++I)Walk(C->GetChildAt(I));};
  if(S.Overlay.IsValid())Walk(S.Overlay.ToSharedRef());
  auto O=OKControlResult(true);
  if(!HasText){TArray<TSharedPtr<FJsonValue>> Rows;for(int32 I=0;I<Boxes.Num();++I){auto R=MakeShared<FJsonObject>();R->SetNumberField(TEXT("box"),I);R->SetStringField(TEXT("hint"),Boxes[I]->GetHintText().ToString());R->SetStringField(TEXT("label"),Labels[I]);R->SetStringField(TEXT("text"),Boxes[I]->GetText().ToString());Rows.Add(MakeShared<FJsonValueObject>(R));}
   O->SetArrayField(TEXT("boxes"),Rows);OKControlReply(Done,O);return;}
  int32 Pick=INDEX_NONE;
  if(!Hint.IsEmpty()){for(int32 I=0;I<Boxes.Num();++I)if(Boxes[I]->GetHintText().ToString().Contains(Hint)){Pick=I;break;}}
  else if(!Label.IsEmpty()){for(int32 I=0;I<Boxes.Num();++I)if(Labels[I].Contains(Label)){Pick=I;break;}}
  else if(Boxes.IsValidIndex(int32(Box)))Pick=int32(Box);
  if(Pick==INDEX_NONE){OKControlReply(Done,OKControlResult(false,TEXT("no such text box")));return;}
  auto& App=FSlateApplication::Get();App.SetKeyboardFocus(Boxes[Pick],EFocusCause::SetDirectly);Boxes[Pick]->SelectAllText();
  for(const TCHAR C:Text)App.ProcessKeyCharEvent(FCharacterEvent(C,FModifierKeysState(),0,false));
  if(Enter){const FKeyEvent K(EKeys::Enter,FModifierKeysState(),0,false,0,0);App.ProcessKeyDownEvent(K);App.ProcessKeyUpEvent(K);}
  O->SetStringField(TEXT("text"),Boxes[Pick]->GetText().ToString());OKControlReply(Done,O);
 });

 // Her face, set directly (tuning the look without waiting for the model): {girl, blush, sweat, gaze_x, gaze_y,
 // highlight, tears, expr, fade_scale (dev: stretch the look's easing), peek (only read)}. Answers what the runtime did,
 // the look drawn now and the shape cross-fade counters.
 // The frame rate now, as the engine averages it (no FPS-chart folder per measurement): fps and ms per thread.
 // The H result screen's close button; says whether one was open.
 Bind(TEXT("/hresult_close"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest&,const FHttpResultCallback& Done){
  const bool Open=State&&State->HResultPanel.IsValid();CloseHResult();auto O=OKControlResult(Open,Open?FString():TEXT("no result screen"));O->SetBoolField(TEXT("more"),State&&State->HResultPanel.IsValid());OKControlReply(Done,O);});
 Bind(TEXT("/fps"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest&,const FHttpResultCallback& Done){
  auto O=OKControlResult(true,FString());O->SetNumberField(TEXT("fps"),GAverageFPS);O->SetNumberField(TEXT("frame_ms"),GAverageFPS>0.f?1000.f/GAverageFPS:0.f);
  O->SetNumberField(TEXT("game_ms"),FPlatformTime::ToMilliseconds(GGameThreadTime));O->SetNumberField(TEXT("render_ms"),FPlatformTime::ToMilliseconds(GRenderThreadTime));
  O->SetNumberField(TEXT("gpu_ms"),FPlatformTime::ToMilliseconds(RHIGetGPUFrameCycles()));
  O->SetNumberField(TEXT("pair_frames"),double(GKKPairFramesShown));O->SetNumberField(TEXT("seconds"),FPlatformTime::Seconds()); // pair poses shown so far, for their rate
  OKControlReply(Done,O);});
 Bind(TEXT("/play"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);double Girl=-1,Seconds=4;B->TryGetNumberField(TEXT("girl"),Girl);B->TryGetNumberField(TEXT("seconds"),Seconds);
  if(!S.Manifest.Characters.IsValidIndex(int32(Girl))||Girl<1){OKControlReply(Done,OKControlResult(false,FString::Printf(TEXT("girl: 1..%d"),S.Manifest.Characters.Num()-1)));return;}
  FString Clip,Gesture,Emotion;B->TryGetStringField(TEXT("clip"),Clip);B->TryGetStringField(TEXT("gesture"),Gesture);B->TryGetStringField(TEXT("emotion"),Emotion);
  if(!Clip.IsEmpty())StartLoverReaction(int32(Girl),Clip,float(Seconds));else PlayGesture(int32(Girl),Gesture,Emotion,float(Seconds));
  OKControlReply(Done,OKControlResult(true,FString()));});
 Bind(TEXT("/face"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);double Girl=-1,V=0;B->TryGetNumberField(TEXT("girl"),Girl);
  if(!S.Manifest.Characters.IsValidIndex(int32(Girl))||Girl<1){OKControlReply(Done,OKControlResult(false,FString::Printf(TEXT("girl: 1..%d"),S.Manifest.Characters.Num()-1)));return;}
  FString Expr,Error;bool Peek=false;B->TryGetBoolField(TEXT("peek"),Peek);
  if(!Peek&&B->TryGetStringField(TEXT("expr"),Expr))if(const auto* E=S.Expressions.Find(S.Manifest.Characters[int32(Girl)].PersonalityId,Expr))OKSetCrowdRuntimeFaceExpression(this,int32(Girl),E->Face,E->Blink,Error);
  // {"mouth": pattern, "mouth_open": 0..1}: one source mouth alone, for seeing how far each pattern opens.
  if(!Peek&&B->TryGetNumberField(TEXT("mouth"),V)){FKKRuntimeFaceState F;F.MouthPattern=int32(V);F.MouthBlend=true;double Open=0;B->TryGetNumberField(TEXT("mouth_open"),Open);F.MouthOpening=float(Open);OKSetCrowdRuntimeFaceExpression(this,int32(Girl),F,true,Error);}
  FOKRuntimeFaceLook Look;if(B->TryGetNumberField(TEXT("blush"),V))Look.Blush=float(V);if(B->TryGetNumberField(TEXT("sweat"),V))Look.Sweat=float(V);
  if(B->TryGetNumberField(TEXT("gaze_x"),V))Look.Gaze.X=V;if(B->TryGetNumberField(TEXT("gaze_y"),V))Look.Gaze.Y=V;if(B->TryGetNumberField(TEXT("highlight"),V))Look.Highlight=int32(V);if(B->TryGetNumberField(TEXT("tears"),V))Look.Tears=int32(V);if(B->TryGetNumberField(TEXT("fade_scale"),V))Look.FadeScale=float(V);
  // {"eyes_follow": -1 as ok.EyeFollow, 0 ahead, 1 him, 2 the camera}: where her eyes go while she looks at someone.
  if(!Peek&&B->TryGetNumberField(TEXT("eyes_follow"),V))OKSetCrowdRuntimeEyeFollow(this,int32(Girl),int32(V));
  const bool Ok=Peek||OKSetCrowdRuntimeFaceLook(this,int32(Girl),Look,Error);auto O=OKControlResult(Ok,Error);
  // What her face shows this frame, easing toward the goal ({"peek": true} only reads it).
  {FOKRuntimeFaceLookNow N;if(OKGetCrowdRuntimeFaceLook(this,int32(Girl),N)){auto J=MakeShared<FJsonObject>();J->SetNumberField(TEXT("blush"),N.Blush);J->SetNumberField(TEXT("sweat"),N.Sweat);J->SetNumberField(TEXT("pupil"),N.Pupil);J->SetNumberField(TEXT("dull"),N.Dull);J->SetNumberField(TEXT("gaze_x"),N.Gaze.X);J->SetNumberField(TEXT("gaze_y"),N.Gaze.Y);J->SetNumberField(TEXT("follow_x"),N.Follow.X);J->SetNumberField(TEXT("follow_y"),N.Follow.Y);J->SetNumberField(TEXT("tears"),N.Tears);J->SetNumberField(TEXT("tear_shown"),N.TearShown);J->SetNumberField(TEXT("highlight"),N.Highlight);J->SetBoolField(TEXT("fading"),N.Fading);O->SetObjectField(TEXT("look_now"),J);}}
  // The shape cross-fades so far (mouth / eyes / brows, 0.15 s each as the source): started, frames drawn mid-way, done.
  {FOKRuntimeFaceStatus F;if(OKGetCrowdRuntimeFaceStatus(this,int32(Girl),F)){O->SetNumberField(TEXT("fades_started"),double(F.Started));O->SetNumberField(TEXT("fade_frames"),double(F.Intermediate));O->SetNumberField(TEXT("fades_completed"),double(F.Completed));}}
  // {"catch": candelas}: the catch light the lit tears shine with.
  if(B->TryGetNumberField(TEXT("catch"),V)&&S.CatchLight.IsValid())S.CatchLight->SetIntensity(float(V));
  // {"set": {"kind": 4, "name": "_Color", "value": [1,0,0,1]}}: a raw parameter on one kind of her materials.
  const TSharedPtr<FJsonObject>* Set=nullptr;if(B->TryGetObjectField(TEXT("set"),Set)){double Kind=0;FString Name;(*Set)->TryGetNumberField(TEXT("kind"),Kind);(*Set)->TryGetStringField(TEXT("name"),Name);
   const TArray<TSharedPtr<FJsonValue>>* Values=nullptr;FLinearColor C(0,0,0,0);bool Vector=false;double X=0;
   if((*Set)->TryGetArrayField(TEXT("value"),Values)){Vector=true;for(int32 K=0;K<4&&K<Values->Num();++K)(&C.R)[K]=float((*Values)[K]->AsNumber());}else if((*Set)->TryGetNumberField(TEXT("value"),X))C.R=float(X);
   O->SetNumberField(TEXT("set_materials"),OKSetCrowdRuntimeLookParameter(this,int32(Girl),int32(Kind),Name,C,Vector));}
  OKControlReply(Done,O);
 });

 Bind(TEXT("/buttons"),EHttpServerRequestVerbs::VERB_GET,[this](const FHttpServerRequest&,const FHttpResultCallback& Done){
  auto& S=*State;auto O=OKControlResult(true);TArray<TSharedPtr<FJsonValue>> Rows,Clipped;
  if(S.Overlay.IsValid()){TArray<TPair<FString,TSharedPtr<SWidget>>> Buttons;OKProbeCollect(S.Overlay.ToSharedRef(),nullptr,Buttons);
   // A row scrolled out of its list is listed too, its index in "clipped" (the menu has more than nine dishes).
   for(const auto& B:Buttons){if(B.Key.IsEmpty()||!B.Value->IsEnabled())continue;const bool Out=OKProbeScrolledOut(B.Value);
    if(!Out&&B.Value->GetCachedGeometry().GetLocalSize().IsNearlyZero())continue;if(Out)Clipped.Add(MakeShared<FJsonValueNumber>(Rows.Num()));Rows.Add(MakeShared<FJsonValueString>(B.Key));}}
  O->SetArrayField(TEXT("buttons"),Rows);O->SetArrayField(TEXT("clipped"),Clipped);OKControlReply(Done,O);
 });

 // Press the button with this label (as the mouse would). The "@" development shortcuts (summon, teleport) are refused.
 Bind(TEXT("/click"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;FString Label;auto ClickBody=OKControlBody(Req);ClickBody->TryGetStringField(TEXT("label"),Label);double Nth=0;ClickBody->TryGetNumberField(TEXT("index"),Nth);
  if(Label.IsEmpty()||Label.StartsWith(TEXT("@"))){OKControlReply(Done,OKControlResult(false,TEXT("a plain button label is required")));return;}
  if(!S.MouseUI){GControlRestoreMouse=true;S.MouseUI=true;ApplyMouseMode(true);}
  GControlRestoreMouseAt=FPlatformTime::Seconds()+0.5;
  // Slate drops synthetic mouse input while the game window is not the foreground window.
  if(GEngine&&GEngine->GameViewport){if(TSharedPtr<SWindow> Win=GEngine->GameViewport->GetWindow())Win->BringToFront(true);FSlateApplication::Get().SetAllUserFocusToGameViewport();}
  FString Why;const bool Ok=ProbePress(Label,Why,int32(Nth));OKControlReply(Done,OKControlResult(Ok,Why));
 });

 // {x, y}: a left click at these viewport pixels, for what has no label to press by (a dropdown and its list).
 Bind(TEXT("/mouse"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);double X=0,Y=0;B->TryGetNumberField(TEXT("x"),X);B->TryGetNumberField(TEXT("y"),Y);
  UGameViewportClient* Client=GEngine?GEngine->GameViewport.Get():nullptr;const TSharedPtr<SViewport> Widget=Client?Client->GetGameViewportWidget():nullptr;
  if(!Widget){OKControlReply(Done,OKControlResult(false,TEXT("no viewport")));return;}
  if(!S.MouseUI){GControlRestoreMouse=true;S.MouseUI=true;ApplyMouseMode(true);}
  GControlRestoreMouseAt=FPlatformTime::Seconds()+5.0;
  if(TSharedPtr<SWindow> Win=Client->GetWindow())Win->BringToFront(true);
  FVector2D Size;Client->GetViewportSize(Size);const FGeometry Geo=Widget->GetCachedGeometry();const FVector2D P=Geo.LocalToAbsolute(FVector2D(X,Y)*Geo.GetLocalSize()/Size);
  FSlateApplication& App=FSlateApplication::Get();TSet<FKey> Pressed;Pressed.Add(EKeys::LeftMouseButton);
  // "phase": down | move | up drags over several frames as a held button does (a click when absent).
  FString Phase;B->TryGetStringField(TEXT("phase"),Phase);static FVector2D Last=FVector2D::ZeroVector;
  const FVector2D From=Phase==TEXT("move")||Phase==TEXT("up")?Last:P;Last=P;App.SetCursorPos(P);
  const TSet<FKey>& Held=Phase==TEXT("move")?Pressed:TSet<FKey>();
  App.ProcessMouseMoveEvent(FPointerEvent(App.CursorPointerIndex,P,From,Held,FKey(),0,FModifierKeysState()));
  if(Phase.IsEmpty()||Phase==TEXT("down"))App.ProcessMouseButtonDownEvent(nullptr,FPointerEvent(App.CursorPointerIndex,P,P,Pressed,EKeys::LeftMouseButton,0,FModifierKeysState()));
  if(Phase.IsEmpty()||Phase==TEXT("up"))App.ProcessMouseButtonUpEvent(FPointerEvent(App.CursorPointerIndex,P,P,TSet<FKey>(),EKeys::LeftMouseButton,0,FModifierKeysState()));
  if(!Phase.IsEmpty()&&Phase!=TEXT("up"))GControlRestoreMouseAt=FPlatformTime::Seconds()+30.0;
  OKControlReply(Done,OKControlResult(true));
 });

 // Cursor mode on/off (what Ctrl or the middle mouse button toggles): off lets WASD and E work again.
 // Development money for testing what needs it (a company, a bankruptcy): through the books like any cash, so the
 // journal stays reconciled; a negative amount takes money away.
 // {girl, ovulate?}: her pregnancy as it stands; ovulate true makes any finish inside take, false puts her back on her cycle.
 Bind(TEXT("/pregnancy"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);double Girl=0;B->TryGetNumberField(TEXT("girl"),Girl);const int32 Index=int32(Girl);
  if(Index<1||Index>=OKStreetCastCount||!S.Manifest.Characters.IsValidIndex(Index)){OKControlReply(Done,OKControlResult(false,TEXT("girl")));return;}
  auto Request=OKRulesRequest(TEXT("preg_ovulate"));OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),OKStreetStableId(S.Manifest.Characters[Index]));
  bool On=false;const bool Set=B->TryGetBoolField(TEXT("ovulate"),On);if(Set)Request->SetBoolField(TEXT("on"),On);
  const TSharedPtr<FJsonObject> A=OKRulesEval(S,Request);const TSharedPtr<FJsonObject>* View=nullptr;
  if(!A.IsValid()||!A->TryGetObjectField(TEXT("pregnancy"),View)){OKControlReply(Done,OKControlResult(false,TEXT("rules")));return;}
  bool Ok=true;if(Set){auto Candidate=S.Store;OKRulesTakeExt(Candidate,*A);Ok=CommitStore(MoveTemp(Candidate));if(Ok)S.PregView[Index]=*View;}
  auto O=OKControlResult(Ok);O->SetStringField(TEXT("name"),S.Manifest.Characters[Index].Name);O->SetObjectField(TEXT("pregnancy"),*View);OKControlReply(Done,O);
 });
 Bind(TEXT("/money"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;double Amount=0;OKControlBody(Req)->TryGetNumberField(TEXT("amount"),Amount);
  auto Candidate=S.Store;OKCash(Candidate,int64(Amount),TEXT("adjust"),OKT(TEXT("ui.control.test_add_money_control")));const bool Ok=CommitStore(MoveTemp(Candidate));
  auto O=OKControlResult(Ok);O->SetNumberField(TEXT("cash"),double(S.Store.PlayerCash));RefreshUI();OKControlReply(Done,O);
 });

 // A heroine's stat as the 女主數值 panel sets it: {"girl": N, "field": "sex_desire", "value": 160} (field: an
 // OKHeroineStats id). Answers the value it holds now.
 Bind(TEXT("/stat"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const auto Body=OKControlBody(Req);double Girl=0,Value=0;FString Field;
  Body->TryGetNumberField(TEXT("girl"),Girl);const bool Set=Body->TryGetNumberField(TEXT("value"),Value);Body->TryGetStringField(TEXT("field"),Field); // without a value: only read
  const int32 F=OKHeroineStats().IndexOfByPredicate([&](const FOKHeroineStat& X){return Field==X.Id;});
  const bool Ok=F!=INDEX_NONE&&S.Manifest.Characters.IsValidIndex(int32(Girl));if(Ok&&Set)SetCharacterStat(int32(Girl),F,float(Value));
  auto O=OKControlResult(Ok);
  if(Ok)O->SetNumberField(TEXT("value"),OKHeroineStats()[F].Get(OKStreetViewRelation(S.Store,OKStreetStableId(S.Manifest.Characters[int32(Girl)]),S.Manifest.TalkBudget)));
  OKControlReply(Done,O);
 });

 // The room microphone while a test drives the talk: off, what it hears (someone else in the room) is dropped.
 Bind(TEXT("/mic"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;bool Ignore=true;OKControlBody(Req)->TryGetBoolField(TEXT("ignore"),Ignore);S.ControlMicIgnored=Ignore;
  auto O=OKControlResult(true);O->SetBoolField(TEXT("ignore"),Ignore);OKControlReply(Done,O);
 });

 // The card table (吹牛): do = start | play (cards, claim: rank 0..12 when leading) | pass | pick (cards: his selection) |
 // call | stop | (nothing: just read).
 // Answers the table as he sees it: his cards, everyone's count, whose turn, the window, the log.
 Bind(TEXT("/bluff"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto& B=S.Bluff;const auto Body=OKControlBody(Req);FString Do;Body->TryGetStringField(TEXT("do"),Do);
  TArray<int32> Cards;const TArray<TSharedPtr<FJsonValue>>* A=nullptr;if(Body->TryGetArrayField(TEXT("cards"),A))for(const auto& V:*A)Cards.Add(int32(V->AsNumber()));
  double ClaimField=-1;Body->TryGetNumberField(TEXT("claim"),ClaimField);
  if(Do==TEXT("start"))StartBluff();
  else if(Do==TEXT("play"))BluffPlay(0,Cards,ClaimField>=0?int32(ClaimField):B.Rank>=0?B.Rank:B.ClaimRank);
  else if(Do==TEXT("pass"))BluffPass();
  else if(Do==TEXT("pick")){B.Selected.Reset();for(const int32 C:Cards)BluffToggle(C);}
  else if(Do==TEXT("call"))BluffChallenge(0);
  else if(Do==TEXT("stop"))EndBluff(OKT(TEXT("ui.control.game_stopped_by_you")),INDEX_NONE);
  auto O=OKControlResult(true);O->SetBoolField(TEXT("active"),B.Active);O->SetBoolField(TEXT("intro"),B.Intro);O->SetBoolField(TEXT("window"),B.Window);
  O->SetNumberField(TEXT("turn"),B.Turn);O->SetStringField(TEXT("rank"),B.Rank>=0?OKBluffRankName(B.Rank):FString(TEXT("lead")));O->SetBoolField(TEXT("open"),B.Open);O->SetNumberField(TEXT("pile"),B.PileCount);O->SetNumberField(TEXT("last_seat"),B.LastSeat);
  TArray<TSharedPtr<FJsonValue>> Mine,Names,Counts,Log;
  if(B.Hands.IsValidIndex(0))for(const int32 C:B.Hands[0])Mine.Add(MakeShared<FJsonValueString>(FString::Printf(TEXT("%d:%s"),C,*OKBluffCardName(C))));
  for(int32 K=0;K<B.Seats.Num();++K){Names.Add(MakeShared<FJsonValueString>(BluffSeatName(K)));Counts.Add(MakeShared<FJsonValueNumber>(B.Hands.IsValidIndex(K)?B.Hands[K].Num():0));}
  for(int32 I=FMath::Max(0,B.Log.Num()-8);I<B.Log.Num();++I)Log.Add(MakeShared<FJsonValueString>(B.Log[I]));
  O->SetArrayField(TEXT("hand"),Mine);O->SetArrayField(TEXT("seats"),Names);O->SetArrayField(TEXT("counts"),Counts);O->SetArrayField(TEXT("log"),Log);
  O->SetStringField(TEXT("notice"),S.FreeTalkNotice);OKControlReply(Done,O);
 });

 // Development: put heroines (slots) around him, held where they are (her schedule and commute stopped), to test what
 // needs several of them together (a group talk, the card table) without walking them in from across town.
 Bind(TEXT("/summon"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;TArray<int32> Slots;const auto Body=OKControlBody(Req);const TArray<TSharedPtr<FJsonValue>>* A=nullptr;if(Body->TryGetArrayField(TEXT("slots"),A)) /* the body kept alive: A points into it */for(const auto& V:*A)Slots.Add(int32(V->AsNumber()));
  int32 K=0;for(const int32 G:Slots){if(!S.Agents.IsValidIndex(G-1))continue;
   const float Angle=FMath::DegreesToRadians(S.Rotations[0].Yaw+60.f+35.f*K++);
   S.Agents[G-1].Position=S.Male+FVector(FMath::Cos(Angle),FMath::Sin(Angle),0)*170.f;S.Commutes.Remove(G);S.LiftWalks.Remove(G);S.Agents[G-1].Held=true;S.ScheduleHeld.Add(G);
   UE_LOG(LogTemp,Display,TEXT("Street control: summoned actor %d next to him"),G);}
  RefreshUI();OKControlReply(Done,OKControlResult(true));
 });

 // The language (lang: zh-TW | zh-CN | en; its region follows unless follow_region is false) and the save's region
 // (region: TW | CN | US; the save's money is converted by the rules). Answers what is in use.
 Bind(TEXT("/locale"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const auto Body=OKControlBody(Req);FString Lang,Region;
  const bool HasRegion=Body->TryGetStringField(TEXT("region"),Region);bool Follow=true;Body->TryGetBoolField(TEXT("follow_region"),Follow);
  if(HasRegion)ChangeRegion(Region);
  if(Body->TryGetStringField(TEXT("lang"),Lang)&&(Lang==TEXT("zh-TW")||Lang==TEXT("zh-CN")||Lang==TEXT("en")))SetLanguage(Lang,Follow&&!HasRegion);
  auto O=OKControlResult(true);O->SetStringField(TEXT("lang"),S.Lang);O->SetStringField(TEXT("region"),S.Store.Region);O->SetStringField(TEXT("money_sample"),Money(Local(TEXT("price"),30)));O->SetNumberField(TEXT("cash"),double(S.Store.PlayerCash));
  OKControlReply(Done,O);
 });

 // The characters' look: style = koikatsu | ramp:<key> (the game's shadow ramps, live) | hg (saves "auto" and reloads
 // the map on it). Answers the one in use and every style there is.
 Bind(TEXT("/render"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  const auto Body=OKControlBody(Req);FString Style;if(Body->TryGetStringField(TEXT("style"),Style))SetRenderStyle(Style);
  bool bLit;if(Body->TryGetBoolField(TEXT("lit"),bLit))SetLit(bLit);
  auto O=OKControlResult(true);O->SetBoolField(TEXT("lit"),State->Lit);O->SetStringField(TEXT("style"),RenderStyle());O->SetStringField(TEXT("label"),RenderStyleLabel(RenderStyle()));O->SetBoolField(TEXT("restarting"),State->SaveRestarting);
  TArray<TSharedPtr<FJsonValue>> Styles;Styles.Add(MakeShared<FJsonValueString>(TEXT("koikatsu")));for(const auto& R:OKRenderRamps())Styles.Add(MakeShared<FJsonValueString>(TEXT("ramp:")+R.Key));Styles.Add(MakeShared<FJsonValueString>(TEXT("hg")));O->SetArrayField(TEXT("styles"),Styles);
  OKControlReply(Done,O);
 });

 // Save slots and the start menu: op = open | start | close | save | load | new (slot: auto, 1..8). Answers the slots.
 // The galgame presenter, for regression tests (Tools/galgame_regression.lua): whether a scene runs and with whom, its
 // lines and the one the wheel scrolled back to, the rollback points, the line on screen, whether a portrait was
 // captured, and the presenter's own state (shot "pov" for first person, camera, portrait shown, typed characters).
 Bind(TEXT("/galgame"),EHttpServerRequestVerbs::VERB_GET,[this](const FHttpServerRequest&,const FHttpResultCallback& Done){
  auto O=OKControlResult(true);
  if(Galgame.IsValid()){
   const auto& G=*Galgame;O->SetBoolField(TEXT("active"),G.bActive);O->SetNumberField(TEXT("partner"),G.Partner);
   O->SetNumberField(TEXT("lines"),G.Lines.Num());O->SetNumberField(TEXT("view_line"),G.ViewLine);O->SetNumberField(TEXT("checkpoints"),G.Checkpoints.Num());
   O->SetStringField(TEXT("on_screen"),G.OnScreen);O->SetBoolField(TEXT("portrait_captured"),G.Portrait.Material()!=nullptr);
   TSharedPtr<FJsonObject> Story;if(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(G.Live.State()),Story)&&Story.IsValid())O->SetObjectField(TEXT("story"),Story);
  }else O->SetBoolField(TEXT("active"),false);
  OKControlReply(Done,O);});
 // Every place, checked for walking (development): its door tied to the road graph's connected part, the way in from the
 // door to its inside spot, and from there to each activity's anchor on that floor, by a full grid search (no time limit,
 // unlike a walk's). {"only": "id,id"} for some. Each place: {id, door_links, door_on_roads, in, anchors:[{activity,
 // anchor, ok, why}], problems:[...]}; the reply also counts the places with problems.
 Bind(TEXT("/places_check"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  const auto Body=OKControlBody(Req);FString OnlyText;Body->TryGetStringField(TEXT("only"),OnlyText);TArray<FString> Only;OnlyText.ParseIntoArray(Only,TEXT(","));
  const double Began=FPlatformTime::Seconds();const FOKStreetCityData& City=OKStreetCity();
  auto Walk=[this](const FVector& From,const FVector& To,int32& Points)->bool{
   if(FMath::Abs(From.Z-To.Z)>=150.f){Points=-1;return true;} // another floor: by the lift, not this check
   if(FVector::Dist2D(From,To)<30.f){Points=1;return true;}
   FOKStreetGridSearch G;G.From=From;G.To=To;GridSearchStep(G,TNumericLimits<double>::Max());Points=G.Route.Num();return G.Route.Num()>=2;};
  TArray<TSharedPtr<FJsonValue>> Rows;int32 Bad=0;
  for(const auto& P:OKStreetPlaces()){
   if(Only.Num()&&!Only.Contains(P.Id))continue;
   auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("id"),P.Id);TArray<TSharedPtr<FJsonValue>> Problems;
   auto Problem=[&Problems](const FString& Text){Problems.Add(MakeShared<FJsonValueString>(Text));};
   // The door on the graph: the point tied to it (OKStreetCityCheckRoads), its links, and whether it is in the kept part.
   int32 DoorNode=INDEX_NONE;for(int32 N=City.Nodes.Num()-1;N>=0;--N)if(FVector::DistSquared2D(City.Nodes[N],P.Door)<1.0){DoorNode=N;break;}
   const int32 Links=City.Links.IsValidIndex(DoorNode)?City.Links[DoorNode].Num():0;
   const bool OnRoads=DoorNode!=INDEX_NONE&&Links>0&&(City.Kept.IsEmpty()||City.Kept[DoorNode]==City.KeptPart);
   Row->SetNumberField(TEXT("door_links"),Links);Row->SetBoolField(TEXT("door_on_roads"),OnRoads);
   // The way a walk takes from the roads (a point of the kept part) to the door, each leg walkable: clear for his body, or
   // a grid way between its ends.
   {const int32 HubNode=City.Kept.IndexOfByKey(City.KeptPart);
    if(City.Nodes.IsValidIndex(HubNode)&&!OKStreetUpstairs(P.Door)){const TArray<FVector> Route=CityRoute(City.Nodes[HubNode],P.Door);Row->SetNumberField(TEXT("route_points"),Route.Num());
     if(Route.Num()<2||!Route.Last().Equals(P.Door,50.f))Problem(TEXT("no road route to the door"));
     for(int32 I=1;I<Route.Num();++I){int32 Points=0;if(OKStreetCityClear(GetWorld(),Route[I-1],Route[I],18.f)||Walk(Route[I-1],Route[I],Points))continue;
      Problem(FString::Printf(TEXT("road leg %d/%d blocked: %s -> %s (%.0f m)"),I,Route.Num()-1,*Route[I-1].ToCompactString(),*Route[I].ToCompactString(),FVector::Dist2D(Route[I-1],Route[I])/100.f));break;}}}
   float Ground=P.Door.Z;if(!OKStreetGroundZ(GetWorld(),P.Door,Ground,this))Problem(TEXT("no ground at the door"));
   else if(FMath::IsNearlyEqual(Ground,P.Door.Z+70.f,1.f))Problem(TEXT("door point inside something solid"));else if(FMath::Abs(Ground-P.Door.Z)>60.f)Problem(FString::Printf(TEXT("door %.0f cm off the ground"),Ground-P.Door.Z));
   // In from the door.
   FVector Inside=P.Door;
   if(!P.Rooms.IsEmpty()){Inside=PlaceInsideSpot(P);int32 Points=0;const bool In=Walk(P.Door,Inside,Points);Row->SetNumberField(TEXT("in_points"),Points);
    if(!In)Problem(TEXT("no way from the door to the inside spot"));
    if(PlaceHere(Inside)!=P.Id)Problem(FString::Printf(TEXT("inside spot counts as %s"),*PlaceHere(Inside)));}
   // To each activity's anchor.
   TArray<TSharedPtr<FJsonValue>> Anchors;
   for(const auto& A:OKStreetActivities()){if(!A.Place||FCString::Strcmp(A.Place,P.Id)!=0||!A.Anchor||!*A.Anchor)continue;
    auto Item=MakeShared<FJsonObject>();Item->SetStringField(TEXT("activity"),A.Id);Item->SetStringField(TEXT("anchor"),A.Anchor);
    const FOKStreetModelAnchor* Spot=OKStreetPlaceAnchor(P,A.Anchor);FString Why;
    if(!Spot)Why=TEXT("no such anchor");
    else{int32 Points=0;const bool Ok=Walk(Inside,Spot->Position,Points)||Walk(P.Door,Spot->Position,Points);
     if(Points==-1)Why=TEXT("another floor");else if(!Ok)Why=TEXT("no way to it");
     float G=Spot->Position.Z;if(Why.IsEmpty()&&!OKStreetGroundZ(GetWorld(),Spot->Position,G,this))Why=TEXT("no ground under it");}
    Item->SetBoolField(TEXT("ok"),Why.IsEmpty()||Why==TEXT("another floor"));Item->SetStringField(TEXT("why"),Why);
    if(!Why.IsEmpty()&&Why!=TEXT("another floor"))Problem(FString::Printf(TEXT("%s (%s): %s"),A.Id,A.Anchor,*Why));
    Anchors.Add(MakeShared<FJsonValueObject>(Item));}
   Row->SetArrayField(TEXT("anchors"),Anchors);Row->SetArrayField(TEXT("problems"),Problems);if(Problems.Num())++Bad;
   Rows.Add(MakeShared<FJsonValueObject>(Row));
  }
  auto O=OKControlResult(true);O->SetNumberField(TEXT("places"),Rows.Num());O->SetNumberField(TEXT("with_problems"),Bad);
  O->SetNumberField(TEXT("ms"),(FPlatformTime::Seconds()-Began)*1000.0);O->SetArrayField(TEXT("rows"),Rows);OKControlReply(Done,O);
 });
 // Every activity, tried for real (development, Tools/street_activity_audit.lua): {"op":"start", girl, id} ends what
 // is going on, puts him at the place's door and her beside him (held), and starts the outing to it as an agreed
 // invitation does (no asking); {"op":"status"} tells what runs now (walking there, pair, solo, facility, restroom,
 // sleep, stroll) and where the two stand against the activity's anchor and the ground; {"op":"end"} ends it all.
 Bind(TEXT("/activity_try"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const auto B=OKControlBody(Req);FString Op=TEXT("status"),Id;B->TryGetStringField(TEXT("op"),Op);B->TryGetStringField(TEXT("id"),Id);double GirlNum=0;B->TryGetNumberField(TEXT("girl"),GirlNum);
  auto EndAll=[this,&S](){if(S.OutingGirl!=INDEX_NONE)CancelOuting(FString());if(S.Pair.Partner!=INDEX_NONE)FinishPhoto();if(S.SoloGirl!=INDEX_NONE)EndSolo();if(S.Facility!=INDEX_NONE)FinishFacility();
   if(S.RestroomGirl!=INDEX_NONE)EndRestroom(false);if(S.SleepPhase!=0)AbortSleep(FString());if(S.Companion!=INDEX_NONE)FinishCompanion();S.StrollActivity.Reset();EndTalk();};
  if(Op==TEXT("end")){EndAll();OKControlReply(Done,OKControlResult(true));return;}
  if(Op==TEXT("start")){
   const FOKStreetActivity* A=OKStreetFindActivity(Id);const int32 Girl=int32(GirlNum);
   if(!A||!S.Agents.IsValidIndex(Girl-1)){OKControlReply(Done,OKControlResult(false,TEXT("girl and a known activity id required")));return;}
   const FOKStreetPlace* P=A->Place&&*A->Place?OKStreetFindPlace(A->Place):nullptr;
   EndAll();StopNavigation(FString());
   if(P){S.Male=P->Door;float G=S.Male.Z;if(OKStreetGroundZ(GetWorld(),S.Male,G,this))S.Male.Z=G;}
   auto& Her=S.Agents[Girl-1];Her.Position=S.Male+FRotator(0,S.Rotations[0].Yaw+90.f,0).RotateVector(FVector(120,0,0));S.Commutes.Remove(Girl);S.LiftWalks.Remove(Girl);Her.Held=true;S.ScheduleHeld.Add(Girl);
   FString Error;const bool Ok=BeginOuting(Girl,Id,Error);
   auto O=OKControlResult(Ok,Error);O->SetStringField(TEXT("place"),P?P->Id:TEXT(""));O->SetNumberField(TEXT("kind"),int32(A->Kind));O->SetStringField(TEXT("anchor"),A->Anchor?A->Anchor:TEXT(""));
   OKControlReply(Done,O);return;}
  // status
  auto O=OKControlResult(true);
  FString Running=TEXT("none");int32 Girl=INDEX_NONE;
  if(S.OutingGirl!=INDEX_NONE&&S.OutingActivity==TEXT("stroll")){Running=TEXT("stroll");Girl=S.OutingGirl;}
  else if(S.OutingGirl!=INDEX_NONE){Running=TEXT("walking");Girl=S.OutingGirl;O->SetNumberField(TEXT("route_step"),S.OutingStep);O->SetNumberField(TEXT("route_points"),S.OutingRoute.Num());O->SetStringField(TEXT("activity"),S.OutingActivity);}
  else if(S.Pair.Partner!=INDEX_NONE){Running=TEXT("pair");Girl=S.Pair.Partner;O->SetNumberField(TEXT("pair_phase"),S.Pair.Phase);O->SetStringField(TEXT("female_clip"),S.Pair.FemaleClip);O->SetStringField(TEXT("male_clip"),S.Pair.MaleClip);}
  else if(S.SoloGirl!=INDEX_NONE){Running=TEXT("solo");Girl=S.SoloGirl;}
  else if(S.Facility!=INDEX_NONE){Running=TEXT("facility");Girl=S.FacilityCharacter;}
  else if(S.RestroomGirl!=INDEX_NONE){Running=TEXT("restroom");Girl=S.RestroomGirl;}
  else if(S.SleepPhase!=0){Running=TEXT("sleep");Girl=S.SleepGirl;}
  else if(!S.StrollActivity.IsEmpty()&&S.Companion!=INDEX_NONE){Running=TEXT("stroll");Girl=S.Companion;}
  O->SetStringField(TEXT("running"),Running);O->SetStringField(TEXT("message"),S.Message);O->SetStringField(TEXT("last_activity"),S.LastActivity);O->SetStringField(TEXT("here"),PlaceHere(S.Male));
  auto Where=[this](const FVector& At,TSharedRef<FJsonObject> Into,const TCHAR* Name){auto W=MakeShared<FJsonObject>();W->SetNumberField(TEXT("x"),At.X);W->SetNumberField(TEXT("y"),At.Y);W->SetNumberField(TEXT("z"),At.Z);
   float G=At.Z;const bool HasGround=OKStreetGroundZ(GetWorld(),At,G,this);W->SetBoolField(TEXT("ground"),HasGround);if(HasGround)W->SetNumberField(TEXT("above_ground"),At.Z-G);
   W->SetBoolField(TEXT("in_obstacle"),OKStreetBlockedPoint(At,0.f));
   // The map's own meshes (a shelf, a wall): a thin body from chest to head where he stands. From the knees up it was the
   // table's edge at every meal (a seated pair is at the table on purpose).
   FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetActivityTry),false,this);
   W->SetBoolField(TEXT("in_mesh"),GetWorld()->OverlapAnyTestByChannel(FVector(At.X,At.Y,(HasGround?G:At.Z)+140.f),FQuat::Identity,ECC_WorldStatic,FCollisionShape::MakeCapsule(12.f,30.f),Query));
   Into->SetObjectField(Name,W);};
  Where(S.Male,O,TEXT("male"));if(S.Agents.IsValidIndex(Girl-1)){Where(S.Agents[Girl-1].Position,O,TEXT("female"));O->SetNumberField(TEXT("girl"),Girl);O->SetNumberField(TEXT("apart"),FVector::Dist(S.Male,S.Agents[Girl-1].Position));}
  const FOKStreetActivity* A=OKStreetFindActivity(Id.IsEmpty()?S.LastActivity:Id);const FOKStreetPlace* P=A&&A->Place?OKStreetFindPlace(A->Place):nullptr;
  if(const FOKStreetModelAnchor* Spot=P&&A->Anchor?OKStreetPlaceAnchor(*P,A->Anchor):nullptr){Where(Spot->Position,O,TEXT("anchor"));O->SetNumberField(TEXT("male_from_anchor"),FVector::Dist2D(S.Male,Spot->Position));O->SetNumberField(TEXT("male_dz_anchor"),S.Male.Z-Spot->Position.Z);}
  OKControlReply(Done,O);
 });
 // The roster menu (OKStreetSocialRoster.inl), as a person uses it: {} or {"op":"state"} reads it; open | close | scan;
 // import {files}; pick {path, on}; apply; edit {her, tab: settings|memory}; set {field: name|persona|profile|memory,
 // value}; save (the tab being edited); forget (her conversation context).
 Bind(TEXT("/roster"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const auto Body=OKControlBody(Req);FString Op,Path,Field,Value,Tab;Body->TryGetStringField(TEXT("op"),Op);
  Body->TryGetStringField(TEXT("path"),Path);Body->TryGetStringField(TEXT("field"),Field);Body->TryGetStringField(TEXT("value"),Value);Body->TryGetStringField(TEXT("tab"),Tab);
  bool On=true;Body->TryGetBoolField(TEXT("on"),On);double Her=0;Body->TryGetNumberField(TEXT("her"),Her);
  FString Error;
  if(Op==TEXT("open"))OpenRoster();else if(Op==TEXT("close"))CloseRoster();
  else if(Op==TEXT("scan")||Op==TEXT("import")){TArray<FString> Files;const TArray<TSharedPtr<FJsonValue>>* A=nullptr;if(Body->TryGetArrayField(TEXT("files"),A))for(const auto& V:*A)Files.Add(V->AsString());
   if(!S.RosterOpen)OpenRoster();if(Op==TEXT("import")||Files.Num())RosterRun(TEXT("import"),Files);else if(!S.RosterBusy)RosterRun(TEXT("scan"),{});}
  else if(Op==TEXT("pick")){S.RosterPicked.RemoveAll([&](const FString& P){return OKStreetRosterKey(P)==OKStreetRosterKey(Path);});
   if(On){if(S.RosterPicked.Num()>=OKStreetFemaleCount)Error=TEXT("at most ten heroines");else if(!FPaths::FileExists(Path))Error=TEXT("no such card");else S.RosterPicked.Add(Path);}RosterRebuild();}
  else if(Op==TEXT("edit"))RosterEditHer(int32(Her),Tab.IsEmpty()?TEXT("settings"):Tab);
  else if(Op==TEXT("set")){if(Field==TEXT("name"))S.RosterName=Value;else if(Field==TEXT("persona"))S.RosterPersona=Value;else if(Field==TEXT("profile"))S.RosterProfile=Value;else if(Field==TEXT("memory"))S.RosterMemory=Value;else Error=TEXT("field must be name|persona|profile|memory");RosterRebuild();}
  else if(Op==TEXT("save")){if(S.RosterEdit<1)Error=TEXT("nobody is being edited");else if(S.RosterTab==TEXT("memory"))RosterSaveMemory();else RosterSaveSettings();}
  else if(Op==TEXT("forget"))RosterForgetContext();
  else if(!Op.IsEmpty()&&Op!=TEXT("state")&&Op!=TEXT("apply"))Error=TEXT("op must be state|open|close|scan|import|pick|apply|edit|set|save|forget");
  auto O=OKControlResult(Error.IsEmpty(),Error);O->SetBoolField(TEXT("open"),S.RosterOpen);O->SetBoolField(TEXT("busy"),S.RosterBusy);O->SetStringField(TEXT("notice"),S.RosterNotice);
  O->SetStringField(TEXT("dir"),OKStreetRosterDir());
  TArray<TSharedPtr<FJsonValue>> Cards;for(const auto& C:S.RosterCards)Cards.Add(MakeShared<FJsonValueObject>(C));O->SetArrayField(TEXT("cards"),Cards);
  auto Strings=[](const TArray<FString>& L){TArray<TSharedPtr<FJsonValue>> A;for(const FString& X:L)A.Add(MakeShared<FJsonValueString>(X));return A;};
  O->SetArrayField(TEXT("picked"),Strings(S.RosterPicked));O->SetArrayField(TEXT("world"),Strings(S.RosterWorld));
  TArray<FString> Names;for(int32 I=1;I<S.Manifest.Characters.Num();++I)Names.Add(S.Manifest.Characters[I].Name);O->SetArrayField(TEXT("heroines"),Strings(Names)); // her = index + 1
  O->SetNumberField(TEXT("editing"),S.RosterEdit);O->SetStringField(TEXT("tab"),S.RosterTab);
  if(S.RosterEdit>0){O->SetStringField(TEXT("name"),S.RosterName);O->SetStringField(TEXT("persona"),S.RosterPersona);O->SetStringField(TEXT("profile"),S.RosterProfile);O->SetStringField(TEXT("memory"),S.RosterMemory);}
  OKControlReply(Done,O);
  if(Op==TEXT("apply")&&Error.IsEmpty())RosterApply(); // last: the map starts again
 });
 Bind(TEXT("/saves"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const auto Body=OKControlBody(Req);FString Op,Slot;Body->TryGetStringField(TEXT("op"),Op);Body->TryGetStringField(TEXT("slot"),Slot);
  if(int32 N=0;Slot.IsEmpty()&&Body->TryGetNumberField(TEXT("slot"),N))Slot=FString::FromInt(N);
  // A request it cannot carry out says so: {"action":"save","slot":8} answered ok with the last notice ("saved to slot 8")
  // and saved nothing, so three saves of a round were lost without a word.
  const bool Known=Op.IsEmpty()&&Body->Values.Num()==0||Op==TEXT("list")||Op==TEXT("open")||Op==TEXT("start")||Op==TEXT("close")||Op==TEXT("new")||(Op==TEXT("save")||Op==TEXT("load"))&&!Slot.IsEmpty();
  if(!Known){OKControlReply(Done,OKControlResult(false,TEXT("op must be list|open|start|close|new, or save|load with a slot")));return;}
  if(Op==TEXT("open"))OpenSaveMenu(TEXT("game"));else if(Op==TEXT("start"))OpenSaveMenu(TEXT("start"));else if(Op==TEXT("close"))CloseSaveMenu();
  else if(Op==TEXT("save")&&!Slot.IsEmpty()){bool Background=false;Body->TryGetBoolField(TEXT("background"),Background);SaveToSlot(Slot,Background);}
  auto O=OKControlResult(true);O->SetStringField(TEXT("menu"),S.SaveMenu);O->SetStringField(TEXT("notice"),S.SaveNotice);
  auto Slots=MakeShared<FJsonObject>();Slots->SetStringField(TEXT("auto"),SaveSlotSummary(TEXT("auto")));for(int32 I=1;I<=OKStreetSaveSlotCount;++I)Slots->SetStringField(FString::FromInt(I),SaveSlotSummary(FString::FromInt(I)));
  O->SetObjectField(TEXT("slots"),Slots);OKControlReply(Done,O);
  // Last: the map starts again, and this scene (and these routes) end.
  if(Op==TEXT("load")&&!Slot.IsEmpty())RestartWithSave(TEXT("load"),Slot);else if(Op==TEXT("new"))RestartWithSave(TEXT("new"),FString());
 });

 // The street clock paused or running (the panel's pause button): {"paused": true|false}.
 Bind(TEXT("/clock"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;bool Paused=S.ClockPaused;const auto ClockBody=OKControlBody(Req);ClockBody->TryGetBoolField(TEXT("paused"),Paused);
  // "hours": set the time of day, like the panel's clock buttons (tests start where the heroines are about, not at dinner).
  double Hours=-1;if(ClockBody->TryGetNumberField(TEXT("hours"),Hours)&&Hours>=0){S.ClockStartHours=FMath::Fmod(Hours+48.0,24.0);S.ClockStartWall=FPlatformTime::Seconds();S.NextSunUpdate=0;S.CalendarLastHours=-1;S.ClockDrivesSun=S.Sun.IsValid();}
  // "sky_gain": the sky dome's brightness, a number or [r, g, b], in place of OKStreetSkyLuminanceAt (tuning it); -1 clears.
  {double G=0;const TArray<TSharedPtr<FJsonValue>>* Rgb=nullptr;
   if(ClockBody->TryGetArrayField(TEXT("sky_gain"),Rgb)&&Rgb->Num()>=3)S.SkyGainOverride=FLinearColor(float((*Rgb)[0]->AsNumber()),float((*Rgb)[1]->AsNumber()),float((*Rgb)[2]->AsNumber()));
   else if(ClockBody->TryGetNumberField(TEXT("sky_gain"),G))S.SkyGainOverride=FLinearColor(float(G),float(G),float(G));
   if(ClockBody->HasField(TEXT("sky_gain")))S.NextSunUpdate=0;}
  if(Paused!=S.ClockPaused){const double Wall=FPlatformTime::Seconds();if(Paused)S.ClockStartHours=OKStreetClockHours(S.ClockStartHours,Wall-S.ClockStartWall);S.ClockStartWall=Wall;S.ClockPaused=Paused;RefreshUI();}
  auto O=OKControlResult(true);O->SetBoolField(TEXT("paused"),S.ClockPaused);OKControlReply(Done,O);
 });

 Bind(TEXT("/cursor"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;bool On=false;OKControlBody(Req)->TryGetBoolField(TEXT("on"),On);
  S.MouseUI=On;ApplyMouseMode(true);RefreshUI();OKControlReply(Done,OKControlResult(true));
 });

 // What the shop he stands in sells now: id, name, prices, whether it is food or drink.
 Bind(TEXT("/menu"),EHttpServerRequestVerbs::VERB_GET,[this](const FHttpServerRequest&,const FHttpResultCallback& Done){
  auto& S=*State;auto O=OKControlResult(true);const FString Place=ShopPlaceHere();O->SetStringField(TEXT("place"),Place);FString Why;O->SetBoolField(TEXT("closed"),!Place.IsEmpty()&&PlaceClosedNow(Place,Why));
  TArray<TSharedPtr<FJsonValue>> Rows;
  if(!Place.IsEmpty())for(const auto* I:ItemsHere(Place)){
   auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("id"),I->Id);R->SetStringField(TEXT("name"),I->Name);R->SetBoolField(TEXT("consumable"),I->Consumable);
   TArray<FString> Prices;for(const auto& P:I->Price)Prices.Add(P.Key.IsEmpty()?FString::FromInt(P.Value):P.Key+FString::FromInt(P.Value));R->SetStringField(TEXT("price"),FString::Join(Prices,TEXT("/")));
   Rows.Add(MakeShared<FJsonValueObject>(R));}
  O->SetArrayField(TEXT("items"),Rows);OKControlReply(Done,O);
 });

 Bind(TEXT("/key"),EHttpServerRequestVerbs::VERB_POST,[](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto B=OKControlBody(Req);FString Name;B->TryGetStringField(TEXT("key"),Name);double Seconds=0;B->TryGetNumberField(TEXT("seconds"),Seconds);
  const FKey Key(*Name);if(!Key.IsValid()){OKControlReply(Done,OKControlResult(false,TEXT("unknown key name (E, W, Escape, LeftShift, One, ...)")));return;}
  auto& V=OKVirtualInput();V.Driven=true;V.Pending.Add(Key);if(Seconds>0)V.DownUntil.Add(Key,FPlatformTime::Seconds()+Seconds);
  OKControlReply(Done,OKControlResult(true));
 });

 Bind(TEXT("/look"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);double Yaw=0,Pitch=0;
  if(B->TryGetNumberField(TEXT("yaw"),Yaw))S.Yaw=Yaw;if(B->TryGetNumberField(TEXT("pitch"),Pitch))S.Pitch=FMath::Clamp(Pitch,-50.0,15.0);
  OKControlReply(Done,OKControlResult(true));
 });

 // The built-in autopilot: to a heroine ("girl": 1..10) or to a place's door ("place": id). The player walks at normal speed.
 // {"x":..,"y":..,"z":..}: put him there at once (a test at a spot no walk reaches soon, like a mirror on an upper floor).
 Bind(TEXT("/warp"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto B=OKControlBody(Req);double X=0,Y=0,Z=0;
  // {girl}: a metre in front of her, facing her; {place}: its door. Tests go there at once instead of walking (user 2026-11-12).
  double Girl=0;FString Place;
  if(B->TryGetNumberField(TEXT("girl"),Girl)){auto& S=*State;const int32 G=int32(Girl);const FOKStreetAgentSim* Her=S.Agents.FindByPredicate([G](const FOKStreetAgentSim& A){return A.Slot==G;});
   if(!Her){OKControlReply(Done,OKControlResult(false,TEXT("no such girl")));return;}
   const float Yaw=S.RenderedRotations.IsValidIndex(G)?S.RenderedRotations[G].Yaw:0.f;const FVector Ahead=FRotator(0.f,Yaw,0.f).Vector();
   StopNavigation(FString());S.Male=Her->Position+Ahead*100.;if(S.Rotations.IsValidIndex(0))S.Rotations[0].Yaw=Yaw+180.f;
   auto O=OKControlResult(true);O->SetNumberField(TEXT("x"),S.Male.X);O->SetNumberField(TEXT("y"),S.Male.Y);O->SetNumberField(TEXT("z"),S.Male.Z);OKControlReply(Done,O);return;}
  if(B->TryGetStringField(TEXT("place"),Place)&&!Place.IsEmpty()){const FOKStreetPlace* P=OKStreetFindPlace(Place);
   if(!P){OKControlReply(Done,OKControlResult(false,TEXT("no such place")));return;}
   StopNavigation(FString());State->Male=P->Door;OKControlReply(Done,OKControlResult(true));return;}
  if(!B->TryGetNumberField(TEXT("x"),X)||!B->TryGetNumberField(TEXT("y"),Y)||!B->TryGetNumberField(TEXT("z"),Z)){OKControlReply(Done,OKControlResult(false,TEXT("x, y and z are required")));return;}
  StopNavigation(FString());State->Male=FVector(X,Y,Z);OKControlReply(Done,OKControlResult(true));
 });
 Bind(TEXT("/navigate"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto B=OKControlBody(Req);bool Stop=false;B->TryGetBoolField(TEXT("stop"),Stop);double Girl=0;FString Place;
  if(Stop){StopNavigation(FString());OKControlReply(Done,OKControlResult(true));return;}
  if(B->TryGetNumberField(TEXT("girl"),Girl)){NavigateGirl(int32(Girl));OKControlReply(Done,OKControlResult(true));return;}
  // {"place": id, "floor": N}: that floor's elevator landing in the place (navigation across floors).
  double Floor=-1;if(B->TryGetStringField(TEXT("place"),Place)&&B->TryGetNumberField(TEXT("floor"),Floor)){const FOKStreetPlace* P=OKStreetFindPlace(Place);const auto Lifts=P?OKStreetPlaceLifts(*P):TArray<const FOKStreetModelAnchor*>();
   if(!Lifts.IsValidIndex(int32(Floor))){OKControlReply(Done,OKControlResult(false,TEXT("no such floor")));return;}
   NavigatePoint(Lifts[int32(Floor)]->Position+FVector(0,0,0),P->Name);OKControlReply(Done,OKControlResult(true));return;}
  if(B->TryGetStringField(TEXT("place"),Place)){const FOKStreetPlace* P=OKStreetFindPlace(Place);if(!P){OKControlReply(Done,OKControlResult(false,TEXT("unknown place id")));return;}NavigatePoint(P->Door,P->Name);OKControlReply(Done,OKControlResult(true));return;}
  OKControlReply(Done,OKControlResult(false,TEXT("girl, place or stop is required")));
 });

 // The game rules (ok_rules.dll): {"action":"status"} (default), {"action":"reload"} (swap in a newer cargo build, else
 // re-read the tuning files) or {"action":"eval","request":{"kind":...}} (ask the rules directly, nothing is applied).
 // The heroine mind (ok-mind): status, or reload (a new build, or the settings file read again) while it is idle.
 Bind(TEXT("/mind"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const TSharedRef<FJsonObject> Body=OKControlBody(Req);FString Action=TEXT("status");Body->TryGetStringField(TEXT("action"),Action);
  if(!S.Mind){OKControlReply(Done,OKControlResult(false,TEXT("mind not open")));return;}
  FString Out,Error;TSharedRef<FJsonObject> O=OKControlResult(true);
  if(Action==TEXT("reload")){WaitFinQuery();const bool Ok=S.Mind->Reload(Out,Error);O=OKControlResult(Ok,Error);O->SetStringField(TEXT("result"),Out);
   UE_LOG(LogTemp,Display,TEXT("StreetSocial mind reload: %s%s"),Ok?*Out:TEXT("failed: "),Ok?TEXT(""):*Error);}
  if(S.Mind->Query(TEXT("{\"kind\":\"status\"}"),Out,Error)){TSharedPtr<FJsonObject> Status;if(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Out),Status)&&Status.IsValid())O->SetObjectField(TEXT("status"),Status);}
  O->SetStringField(TEXT("dll"),S.Mind->DllPath());
  OKControlReply(Done,O);
 });
 // Her song (OKStreetSocialSong.inl): {"action": state|prepare|play|accept|later|decline|skip|cancel|enable|disable, "girl": N}.
 Bind(TEXT("/song"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  const TSharedRef<FJsonObject> Body=OKControlBody(Req);FString Action=TEXT("state");Body->TryGetStringField(TEXT("action"),Action);int32 Girl=0;Body->TryGetNumberField(TEXT("girl"),Girl);
  // Testing her milestone songs: set_relation {girl, stage?, favor?, lines?} sets her stage / favor and the lines since
  // her last song (then the song rules see it on their next check).
  if(Action==TEXT("set_relation")){auto& S=*State;const auto* R=OKSongRelation(S,Girl);
   if(!R){OKControlReply(Done,OKControlResult(false,TEXT("he has not met her")));return;}
   auto* W=const_cast<FOKStreetRelation*>(R);FString Stage;double Favor=0;int32 Lines=0;
   // (Her stage before this one is what the song event saw, so making her his lover here counts as becoming one now.)
   if(Body->TryGetStringField(TEXT("stage"),Stage)){if(!S.Song.Loaded)SongLoad();auto& Seen=S.Song.Progress.FindOrAdd(W->Id);if(Seen.Stage.IsEmpty())Seen.Stage=W->Stage;W->Stage=Stage;}if(Body->TryGetNumberField(TEXT("favor"),Favor))W->Favor=float(Favor);
   if(Body->TryGetNumberField(TEXT("lines"),Lines)){if(!S.Song.Loaded)SongLoad();S.Song.Progress.FindOrAdd(W->Id).Lines=Lines;SongSave();}
   S.Song.NextCheck=0;RefreshUI();Action=TEXT("state");}
  OKControlReply(Done,SongControl(Action,Girl));
 });
 // {girl:1..10, id}: would she go? The check every invitation asks (nothing is bought or used up here).
 Bind(TEXT("/activity"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const auto B=OKControlBody(Req);double Girl=-1;FString Id;B->TryGetNumberField(TEXT("girl"),Girl);B->TryGetStringField(TEXT("id"),Id);
  if(Girl<1||!S.Manifest.Characters.IsValidIndex(int32(Girl))||Id.IsEmpty()){OKControlReply(Done,OKControlResult(false,TEXT("girl and id required")));return;}
  auto Request=ActivityContext(int32(Girl),TEXT("activity_check"));Request->SetStringField(TEXT("id"),Id);Request->SetStringField(TEXT("here"),PlaceHere(S.Male));Request->SetNumberField(TEXT("player_cash"),double(S.Store.PlayerCash));
  const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);auto O=OKControlResult(Answer.IsValid());if(Answer.IsValid())O->SetObjectField(TEXT("answer"),Answer);OKControlReply(Done,O);});

 Bind(TEXT("/rules"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const TSharedRef<FJsonObject> Body=OKControlBody(Req);FString Action=TEXT("status");Body->TryGetStringField(TEXT("action"),Action);
  if(!S.Rules){OKControlReply(Done,OKControlResult(false,TEXT("rules not open")));return;}
  FString Error;TSharedRef<FJsonObject> O=OKControlResult(true);
  if(Action==TEXT("reload")){FString Out;const bool Ok=S.Rules->Reload(Out,Error);O=OKControlResult(Ok,Error);O->SetStringField(TEXT("result"),Out);if(Ok){LoadUiTexts();RefreshUI();}}
  else if(Action==TEXT("eval")){const TSharedPtr<FJsonObject>* Request=nullptr;
   if(!Body->TryGetObjectField(TEXT("request"),Request)||!Request->IsValid()){OKControlReply(Done,OKControlResult(false,TEXT("request object required")));return;}
   const TSharedPtr<FJsonObject> Answer=S.Rules->Eval(Request->ToSharedRef(),Error);O=OKControlResult(Answer.IsValid(),Error);if(Answer.IsValid())O->SetObjectField(TEXT("answer"),Answer);}
  else{auto Request=MakeShared<FJsonObject>();Request->SetStringField(TEXT("rule"),TEXT("status"));const TSharedPtr<FJsonObject> Answer=S.Rules->Eval(Request,Error);
   O=OKControlResult(Answer.IsValid(),Error);if(Answer.IsValid())O->SetObjectField(TEXT("status"),Answer);}
  O->SetStringField(TEXT("dll"),S.Rules->DllPath());O->SetNumberField(TEXT("generation"),S.Rules->Generation());
  OKControlReply(Done,O);
 });

 // {actor:1..10, bone, yaw, pitch, distance, fov, ortho_width} pins the camera (see GControlCamera); {off:true} releases it.
 // /inspect {girl:1..10, yaw, pitch, distance}: that heroine alone in the inspection room, the camera round her (yaw 0 in
 // front of her, 90 her left side); {off:true} sends her back to her day (OKStreetSocialInspect.inl).
 Bind(TEXT("/inspect"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);bool Off=false;B->TryGetBoolField(TEXT("off"),Off);
  if(Off){EndInspect();OKControlReply(Done,OKControlResult(true));return;}
  double Girl=S.InspectSlot!=INDEX_NONE?S.InspectSlot:1;B->TryGetNumberField(TEXT("girl"),Girl);FString Error;
  if(int32(Girl)!=S.InspectSlot&&!BeginInspect(int32(Girl),Error)){OKControlReply(Done,OKControlResult(false,Error));return;}
  double V=0;if(B->TryGetNumberField(TEXT("yaw"),V))S.InspectYaw=float(V);if(B->TryGetNumberField(TEXT("pitch"),V))S.InspectPitch=float(V);if(B->TryGetNumberField(TEXT("distance"),V))S.InspectDistance=float(V);
  auto O=OKControlResult(true);O->SetNumberField(TEXT("girl"),S.InspectSlot);O->SetNumberField(TEXT("yaw"),S.InspectYaw);O->SetNumberField(TEXT("pitch"),S.InspectPitch);O->SetNumberField(TEXT("distance"),S.InspectDistance);
  OKControlReply(Done,O);
 });
 // The one-on-one scene: {girl} enters it with her (as the 進入場景 button, without the talk), {off:true} leaves it (as
 // its leave button, and after it the time after's "leave the room"); {} tells whether one is open and with whom.
 Bind(TEXT("/private"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);bool Off=false;B->TryGetBoolField(TEXT("off"),Off);double Girl=0;B->TryGetNumberField(TEXT("girl"),Girl);
  if(Off){if(S.PrivateGirl!=INDEX_NONE)FinishPrivate();else EndAfter(true);}
  else if(Girl>0&&S.PrivateGirl==INDEX_NONE){if(S.InspectSlot!=INDEX_NONE)EndInspect();BeginPrivate(int32(Girl));
   if(S.PrivateGirl!=int32(Girl)){OKControlReply(Done,OKControlResult(false,TEXT("could not open (not ready, not idle, or no high model for her)")));return;}}
  auto O=OKControlResult(true);O->SetNumberField(TEXT("girl"),S.PrivateGirl);OKControlReply(Done,O);
 });
 // The one-on-one's H panel (OKHScene.h): {} its view; {kind} presses a button by kind, {pose} picks a pose, {speed}.
 Bind(TEXT("/hscene"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;if(!S.PrivateMode.IsValid()){OKControlReply(Done,OKControlResult(false,TEXT("no one-on-one open")));return;}
  FString Why;const TSharedPtr<FJsonObject> View=S.PrivateMode->HSceneControl(OKControlBody(Req),Why);
  if(!View){OKControlReply(Done,OKControlResult(false,Why));return;}
  auto O=OKControlResult(true);O->SetObjectField(TEXT("h"),View);OKControlReply(Done,O);
 });
 // {girl, why, kind?}: she writes him now, from that reason (kind "initiative" when none: her own message).
 Bind(TEXT("/text"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);double Girl=0;B->TryGetNumberField(TEXT("girl"),Girl);FString Why,Kind=TEXT("initiative");B->TryGetStringField(TEXT("why"),Why);B->TryGetStringField(TEXT("kind"),Kind);
  if(!S.Manifest.Characters.IsValidIndex(int32(Girl))||Girl<1||Why.IsEmpty()){OKControlReply(Done,OKControlResult(false,TEXT("girl and why")));return;}
  QueueHerText(int32(Girl),Why,Kind,0.0);OKControlReply(Done,OKControlResult(true));
 });
 // {girl}: the heroine he is talking with says her wish to be close now (what her own wish does by chance), and the
 // choice opens for him to answer.
 Bind(TEXT("/wish"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);double Girl=0;B->TryGetNumberField(TEXT("girl"),Girl);
  if(int32(Girl)<1||S.Target!=int32(Girl)){OKControlReply(Done,OKControlResult(false,TEXT("talk with her first")));return;}
  AskIntimacyWish(int32(Girl));OKControlReply(Done,OKControlResult(true));
 });

 Bind(TEXT("/camera"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;auto B=OKControlBody(Req);auto& C=GControlCamera;bool Off=false;B->TryGetBoolField(TEXT("off"),Off);
  ACameraActor* Camera=S.Camera.Get();UCameraComponent* Lens=Camera?Camera->GetCameraComponent():nullptr;
  if(Off){if(C.Active&&Lens){Lens->SetProjectionMode(ECameraProjectionMode::Perspective);Lens->SetFieldOfView(C.SavedFov);}C.Active=false;OKControlReply(Done,OKControlResult(true));return;}
  if(!Lens){OKControlReply(Done,OKControlResult(false,TEXT("no street camera")));return;}
  if(!C.Active)C.SavedFov=Lens->FieldOfView;
  double Actor=C.Actor;B->TryGetNumberField(TEXT("actor"),Actor);C.Actor=int32(Actor);FString Bone;if(B->TryGetStringField(TEXT("bone"),Bone))C.Bone=FName(*Bone);
  B->TryGetNumberField(TEXT("yaw"),C.Yaw);B->TryGetNumberField(TEXT("pitch"),C.Pitch);B->TryGetNumberField(TEXT("distance"),C.Distance);B->TryGetNumberField(TEXT("fov"),C.Fov);B->TryGetNumberField(TEXT("ortho_width"),C.Ortho);
  C.Active=true;auto O=OKControlResult(true);
  if(!OKApplyControlCamera(this,Camera,O)){C.Active=false;OKControlReply(Done,OKControlResult(false,TEXT("actor or bone unavailable")));return;}
  O->SetNumberField(TEXT("fov"),Lens->FieldOfView);O->SetNumberField(TEXT("ortho_width"),C.Ortho);OKControlReply(Done,O);
 });

 // {command: "stat unit"} runs an engine console command on the game thread and returns what it printed (profiling:
 // "stat dumphitches", "Trace.File <path> cpu,gpu,frame", "Trace.Stop"). Viewport commands (stat, HighResShot) go
 // through the game viewport, the rest through the engine. Development only: the channel itself needs -StreetSocialControl.
 Bind(TEXT("/exec"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  FString Command;OKControlBody(Req)->TryGetStringField(TEXT("command"),Command);Command.TrimStartAndEndInline();
  if(Command.IsEmpty()){OKControlReply(Done,OKControlResult(false,TEXT("command is required")));return;}
  FStringOutputDevice Out;Out.SetAutoEmitLineTerminator(true);bool Handled=false;
  if(GEngine&&GEngine->GameViewport&&GetWorld())Handled=GEngine->GameViewport->Exec(GetWorld(),*Command,Out);
  if(!Handled&&GEngine)Handled=GEngine->Exec(GetWorld(),*Command,Out);
  UE_LOG(LogTemp,Display,TEXT("Street control exec: %s (%s)"),*Command,Handled?TEXT("handled"):TEXT("not handled"));
  auto O=OKControlResult(Handled,Handled?FString():TEXT("not a known command"));O->SetStringField(TEXT("output"),Out);OKControlReply(Done,O);
 });

 // {scale: 3}: the engine's high-resolution shot at that multiple of the window (no UI), for close looks at a face.
 Bind(TEXT("/screenshot"),EHttpServerRequestVerbs::VERB_POST,[this](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  auto& S=*State;const FString Dir=FPaths::GetPath(S.Manifest.SocialReport)/TEXT("control_shots");IFileManager::Get().MakeDirectory(*Dir,true);
  double Scale=1;OKControlBody(Req)->TryGetNumberField(TEXT("scale"),Scale);Scale=FMath::Clamp(Scale,1.0,4.0);
  const FString File=Dir/FString::Printf(TEXT("shot.%04d.png"),++GControlShots);
  // HighResShot is the game viewport's command (GEngine->Exec does not route it there).
  if(Scale>1.01&&GEngine&&GEngine->GameViewport&&GetWorld()){GEngine->GameViewport->Exec(GetWorld(),*FString::Printf(TEXT("HighResShot %.2f filename=\"%s\""),Scale,*File),*GLog);}
  else FScreenshotRequest::RequestScreenshot(File,true,false);
  auto O=OKControlResult(true);O->SetStringField(TEXT("path"),File);OKControlReply(Done,O);
 });

 UE_LOG(LogTemp,Display,TEXT("Street control: listening on http://127.0.0.1:%d (state, say, buttons, click, key, look, navigate, rules, screenshot)"),Port);
}

// Every tick: start the channel once, turn the keys asked for since the last tick into
// "just pressed" for this one, and give the cursor back to the game a moment after a button was pressed through it.
void AOKStreetSocialScene::TickControl(){
 if(!GControlStarted){GControlStarted=true;StartControlServer();}
 auto& V=OKVirtualInput();if(!V.Active)return;
 V.Pressed=MoveTemp(V.Pending);V.Pending.Reset();
 if(GControlRestoreMouse&&FPlatformTime::Seconds()>=GControlRestoreMouseAt){GControlRestoreMouse=false;State->MouseUI=false;ApplyMouseMode(true);RefreshUI();}
}
