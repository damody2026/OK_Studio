// Her pregnancy on the street (Tools/ok-rules src/pregnancy.rs preg_day; Docs/H_SCENE_ADDITIONS_PLAN.md 8). Asked
// each new day before her plans (the day she gives birth she stays home, heavy she rests more; plan.rs), with her
// memory the first time she knows and of a birth. Knowing it she does not drink, run or bathe in hot springs (the
// rules refuse those), sick in weeks 6 to 14 a few times a day, heavy from 28 she walks slower; her mind is told each
// turn (ui.mind.pregnancy_status) and so speaks of it.

static int64 OKStreetMindNow(const FOKStreetSceneState& S); // OKStreetSocialMind.inl
static const FJsonObject* OKStreetPreg(const FOKStreetSceneState& S,int32 Girl){return Girl>0&&Girl<OKStreetCastCount&&S.PregView[Girl].IsValid()?S.PregView[Girl].Get():nullptr;}
static bool OKStreetPregFlag(const FOKStreetSceneState& S,int32 Girl,const TCHAR* Key){const FJsonObject* P=OKStreetPreg(S,Girl);bool B=false;return P&&P->TryGetBoolField(Key,B)&&B;}
static int32 OKStreetPregNumber(const FOKStreetSceneState& S,int32 Girl,const TCHAR* Key){const FJsonObject* P=OKStreetPreg(S,Girl);double V=0;return P&&P->TryGetNumberField(Key,V)?int32(V):0;}

// What her body tells her (for her mind): sick before she knows why, pregnant (sick, heavy), lately given birth.
static FString OKStreetPregnancyStatus(const FOKStreetSceneState& S,int32 Girl){
 if(!OKStreetPreg(S,Girl))return FString();
 const bool Pregnant=OKStreetPregFlag(S,Girl,TEXT("pregnant")),Knows=OKStreetPregFlag(S,Girl,TEXT("knows")),Sick=OKStreetPregFlag(S,Girl,TEXT("sick"));
 const int32 After=OKStreetPregNumber(S,Girl,TEXT("days_since_birth"));
 const TCHAR* State=Pregnant?(Knows?TEXT("knows"):Sick?TEXT("unknown_sick"):TEXT("none")):After>=0&&After<180?TEXT("postpartum"):TEXT("none");
 if(!FCString::Strcmp(State,TEXT("none")))return FString();
 return OKMsg(TEXT("ui.mind.pregnancy_status"),{{TEXT("state"),State},{TEXT("week"),OKStreetPregNumber(S,Girl,TEXT("week"))},{TEXT("sick"),Sick?TEXT("yes"):TEXT("no")},
  {TEXT("heavy"),OKStreetPregFlag(S,Girl,TEXT("heavy"))?TEXT("yes"):TEXT("no")},{TEXT("days"),After}});
}

void AOKStreetSocialScene::PregnancyDay(){
 auto& S=*State;const int32 Cast=FMath::Min(S.Manifest.Characters.Num(),OKStreetCastCount);
 for(int32 Girl=1;Girl<Cast;++Girl){
  const FString Id=OKStreetStableId(S.Manifest.Characters[Girl]);
  auto Request=OKRulesRequest(TEXT("preg_day"));OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),Id);
  Request->SetStringField(TEXT("place"),S.Agents.IsValidIndex(Girl-1)?PlaceHere(S.Agents[Girl-1].Position):FString());
  const TSharedPtr<FJsonObject> A=OKRulesEval(S,Request);if(!A.IsValid())continue;
  const TSharedPtr<FJsonObject>* V=nullptr;S.PregView[Girl]=A->TryGetObjectField(TEXT("pregnancy"),V)?*V:nullptr;
  bool Learned=false,Born=false;A->TryGetBoolField(TEXT("learned"),Learned);A->TryGetBoolField(TEXT("born"),Born);
  if(Learned||Born){auto Candidate=S.Store;OKRulesTakeExt(Candidate,*A);ApplyRulesEffects(Candidate,*A);if(CommitStore(MoveTemp(Candidate)))FlushRulesEffects();}
  // Her sick spells today: the first after she is up, the next hours apart (TickPregnancy).
  S.PregSickDone[Girl]=0;S.PregSickAt[Girl]=480+FMath::RandRange(0,150);
  if(OKStreetPregFlag(S,Girl,TEXT("pregnant"))||Born||OKStreetPregNumber(S,Girl,TEXT("days_since_birth"))>=0)
   UE_LOG(LogTemp,Display,TEXT("Street pregnancy: actor=%d week %d knows %d sick %d heavy %d, learned %d born %d"),Girl,OKStreetPregNumber(S,Girl,TEXT("week")),
    OKStreetPregFlag(S,Girl,TEXT("knows")),OKStreetPregFlag(S,Girl,TEXT("sick")),OKStreetPregFlag(S,Girl,TEXT("heavy")),Learned,Born);
 }
}

// Sick (weeks 6 to 14): her sick_times spells a day between 08:00 and 22:00, awake and out of the room with him; she
// covers her mouth, and the next time she talks she knows it just came over her.
void AOKStreetSocialScene::TickPregnancy(){
 auto& S=*State;const int32 Cast=FMath::Min(S.Manifest.Characters.Num(),OKStreetCastCount);const int32 Of=int32(OKStreetMindNow(S)%1440);
 for(int32 Girl=1;Girl<Cast;++Girl){
  if(!OKStreetPregFlag(S,Girl,TEXT("sick"))||S.PregSickDone[Girl]>=OKStreetPregNumber(S,Girl,TEXT("sick_times"))||Of<S.PregSickAt[Girl]||Of>=1320)continue;
  if(S.PrivateGirl==Girl||!S.Agents.IsValidIndex(Girl-1)||S.SleepGirl==Girl||S.SleepGirl2==Girl)continue;
  const FOKStreetPlanBlock* B=LifeBlock(Girl,Of);if(B&&B->Kind==TEXT("sleep"))continue;
  ++S.PregSickDone[Girl];S.PregSickAt[Girl]=Of+180+FMath::RandRange(0,120);
  PlayGesture(Girl,TEXT("hide_face"),TEXT("低落"),2.5f);
  const FString Id=OKStreetStableId(S.Manifest.Characters[Girl]);FString& Recent=S.MindRecent.FindOrAdd(Id);
  Recent+=OKT(TEXT("ui.mind.pregnancy_sick_now"));
  UE_LOG(LogTemp,Display,TEXT("Street pregnancy: actor=%d sick (%d of %d today)"),Girl,S.PregSickDone[Girl],OKStreetPregNumber(S,Girl,TEXT("sick_times")));
 }
}
