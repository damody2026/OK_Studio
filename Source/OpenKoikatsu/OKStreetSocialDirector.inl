// Included by OKStreetSocialScene.cpp: plan §6.6 initiative (heroines acting on their own) and §14 the open-world
// Director (helping him discover hidden troubles, holidays, weather, exam weeks, birthdays). Rules only.

// Weather and holidays are rules (Tools/ok-rules src/plan.rs raining_at / holiday_on).
bool AOKStreetSocialScene::RainingAt(int32 Day,int32 Minute) const{
 auto Request=OKRulesRequest(TEXT("weather"));Request->SetNumberField(TEXT("day"),Day);Request->SetNumberField(TEXT("minute"),Minute);
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(*State,Request);return Answer&&Answer->GetBoolField(TEXT("raining"));
}

FString AOKStreetSocialScene::HolidayOn(int32 Day) const{
 auto Request=OKRulesRequest(TEXT("holiday"));Request->SetNumberField(TEXT("day"),Day);
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(*State,Request);return Answer?Answer->GetStringField(TEXT("holiday")):FString();
}

bool AOKStreetSocialScene::BirthdayOf(int32 I,int32 Day) const{
 const FString B=OKStreetProfileString(ProfileOf(I),nullptr,TEXT("birthday"));TArray<FString> P;B.ParseIntoArray(P,TEXT("-"));
 if(P.Num()!=3)return false;const FDateTime D=OKStreetCalendarDateTime(Day,12.0);
 return D.GetMonth()==FCString::Atoi(*P[1])&&D.GetDay()==FCString::Atoi(*P[2]);
}

// The 【今天】 line: date events, weather now, her birthday (and tomorrow's, so she can hint).
namespace{const TCHAR* OKPhoneDoingWord(const FString& Kind);} // OKStreetSocialPhoneInbox.inl
// Her day ahead for the judge, each with its place id: "come along with me first" names no place, and Raiden's errand
// was skipped (he agreed to walk with her, they went straight to the dessert she had said would come after it).
FString AOKStreetSocialScene::JudgePlanLine(int32 Character) const{
 const auto& S=*State;const auto* Plan=S.Plans.Find(Character);if(!Plan)return FString();
 const int32 Minute=int32(OKStreetMindNow(S)%1440);TArray<FString> Next;
 for(const auto& B:*Plan)if(B.End>Minute&&Next.Num()<3&&B.Kind!=TEXT("sleep")&&!B.Place.IsEmpty()){const FOKStreetPlace* P=OKStreetFindPlace(B.Place);
  const int32 Said=(FMath::Max(B.Start,Minute)+7)/15*15;
  Next.Add(FString::Printf(TEXT("%02d:%02d "),Said/60%24,Said%60)+OKMsg(TEXT("ui.director.plan_block"),{{TEXT("doing"),OKPhoneDoingWord(B.Kind)},{TEXT("place"),P?FString(P->Name):B.Place}})+TEXT(" (go:")+B.Place+TEXT(")"));}
 return Next.IsEmpty()?FString():OKMsg(TEXT("ui.scene.judge_her_plan"),{{TEXT("plan"),FString::Join(Next,OKT(TEXT("ui.economy.semicolon_mark")))}});
}
FString AOKStreetSocialScene::TodayText(int32 Character) const{
 const auto& S=*State;const int64 Now=OKStreetMindNow(S);const int32 Day=S.Store.CalendarDay;TArray<FString> Parts;
 const FString Holiday=HolidayOn(Day);if(!Holiday.IsEmpty())Parts.Add(Holiday);
 // Places shut all day today (the library on Mondays): she said she was off to the library on a Monday (R3-206).
 {const int32 Weekday=int32(StreetNow().GetDayOfWeek());TArray<FString> Shut;
  for(const auto& Pair:S.Catalog.Places)if(Pair.Value.ClosedWeekdays.Contains(Weekday)){const FOKStreetPlace* P=OKStreetFindPlace(Pair.Key);Shut.Add(P?FString(P->Name):Pair.Key);}
  if(Shut.Num()){Shut.Sort();Parts.Add(OKMsg(TEXT("ui.director.closed_today_line"),{{TEXT("places"),FString::Join(Shut,OKT(TEXT("ui.bank.list_separator")))}}));}}
 Parts.Add(RainingAt(Day,int32(Now%1440))?OKT(TEXT("ui.director.raining_now")):OKT(TEXT("ui.director.not_raining")));
 if(S.Manifest.Characters.IsValidIndex(Character)&&Character>0)if(const FString* Inv=S.HerInvestText.Find(OKStreetStableId(S.Manifest.Characters[Character])))Parts.Add(*Inv);
 {const FString Mine=AcademicText(Character);if(!Mine.IsEmpty())Parts.Add(OKT(TEXT("ui.director.you_are_label"))+Mine);
  // A girl who has only just met him does not know what he studies (unless he says so in the talk, which she then hears).
  const bool Stranger=S.Manifest.Characters.IsValidIndex(Character)&&Character>0&&OKStreetViewRelation(S.Store,OKStreetStableId(S.Manifest.Characters[Character]),S.Manifest.TalkBudget).Stage==TEXT("stranger");
  if(Stranger)Parts.Add(OKT(TEXT("ui.director.his_major_unknown")));
  else Parts.Add(OKMsg(TEXT("ui.director.he_is_intelligence_line"), {{TEXT("academic_title"), *AcademicText(0)}, {TEXT("intelligence"), S.Store.PlayerAcademic.Intelligence}}));}
 // School is out (summer, until the term starts): no classes for anyone. She once answered "I have class at noon".
 {EOKStreetTermPhase Phase;FOKStreetTerm Next;FOKStreetTerm Term=OKRulesTermAt(S,StreetNow(),Phase,nullptr,nullptr,&Next);
  if(Phase==EOKStreetTermPhase::Break)Parts.Add(OKMsg(TEXT("ui.director.school_break_line"),{{TEXT("start"),(Next.Key.IsEmpty()?Term:Next).Start.ToString(TEXT("%m/%d"))}}));
  // An exam week has no classes and one sitting, its Friday 17:00 (academics.rs): she once had "management, one paper
  // this morning" on the Wednesday (R3-213).
  else if(Phase==EOKStreetTermPhase::Midterm||Phase==EOKStreetTermPhase::Final){const FDateTime Week=Phase==EOKStreetTermPhase::Midterm?Term.Midterm:Term.Final;
   Parts.Add(OKMsg(TEXT("ui.director.exam_week_line"),{{TEXT("exam"),Phase==EOKStreetTermPhase::Midterm?OKT(TEXT("ui.director.midterm_word")):OKT(TEXT("ui.director.final_word"))},{TEXT("date"),(Week+FTimespan::FromDays(4)).ToString(TEXT("%m/%d"))}}));}}
 // Where she lives (her profile): at the door of her own dorm Jeanne said she did not live there and had come to see a
 // friend; only "resting at home at the girls' dorm" in her plan said so.
 if(Character>0&&S.Manifest.Characters.IsValidIndex(Character)){const FString Home=OKStreetProfileString(S.MindProfiles.FindRef(OKStreetStableId(S.Manifest.Characters[Character])),nullptr,TEXT("home_place_id"));
  if(const FOKStreetPlace* P=Home.IsEmpty()?nullptr:OKStreetFindPlace(Home)){Parts.Add(OKMsg(TEXT("ui.director.your_home_line"),{{TEXT("place"),FString(P->Name)}}));
   // And how far it is to campus on her own feet (the day plans' 2.75 m a game minute, the way 1.3 times the straight
   // line): Jeanne told him the girls' dorm was five minutes from school, and stood by it when he said the map showed it
   // much further (R6-236). Told only the walk, she said 270 minutes as if she walked it to class: the bus too.
   if(const FOKStreetPlace* Gate=OKStreetFindPlace(TEXT("campus_gate"));Gate&&Gate!=P){
    const float WalkCm=FVector::Dist2D(P->Door,Gate->Door)*1.3f;
    const int32 Minutes=FMath::Max(5,FMath::RoundToInt(WalkCm/100.f/2.75f/5.f)*5);
    FString Line=OKMsg(TEXT("ui.director.home_walk_line"),{{TEXT("home"),FString(P->Name)},{TEXT("place"),FString(Gate->Name)},{TEXT("minutes"),Minutes}});
    const TSharedPtr<FJsonObject>* Bus=nullptr;
    if(const TSharedPtr<FJsonObject> Quote=OKStreetCityMode()?OKStreetTransitQuote(S,P->Door,Gate->Door,WalkCm,1,-1):nullptr;Quote&&Quote->TryGetObjectField(TEXT("bus"),Bus)&&Bus&&Bus->IsValid())
     Line+=OKMsg(TEXT("ui.director.home_bus_line"),{{TEXT("minutes"),int64((*Bus)->GetNumberField(TEXT("minutes")))}});
    Parts.Add(Line);}}}
 // Where he lives: Yuuka, at the girls' dorm, took "I just moved in, do you live here too?" as him living on her floor.
 if(const FOKStreetPlace* P=OKStreetFindPlace(TEXT("boys_dorm")))Parts.Add(OKMsg(TEXT("ui.director.his_home_line"),{{TEXT("place"),FString(P->Name)}}));
 // What her own day still holds (the plan she follows): what she says she has to do comes from here.
 if(const auto* Plan=S.Plans.Find(Character)){TArray<FString> Next;const int32 Minute=int32(Now%1440);
  // Back-to-back blocks of the same thing at the same place are one: the staggered walk to class (12:49 "class" at T1,
  // then the 13:30 class) made Jeanne say her class began at 12:45 (R6-157). Two classes in a row there start with the
  // later one, the class itself; a meal or a stay just runs on.
  TArray<FOKStreetPlanBlock> Shown;
  for(const auto& B:*Plan)if(B.End>Minute&&B.Kind!=TEXT("sleep")){
   if(Shown.Num()&&Shown.Last().Kind==B.Kind&&Shown.Last().Place==B.Place&&Shown.Last().End>=B.Start-1){if(B.Kind==TEXT("class")||B.Kind==TEXT("work"))Shown.Last()=B;else Shown.Last().End=B.End;}
   else Shown.Add(B);}
  // Four of the day's blocks, and past them still what she is bound to (a class, a shift, a promise): Jeanne's 17:00
  // shift at the bookstore was the fifth and she said she had no work tonight (R6-160).
  for(const auto& B:Shown)if(Next.Num()<4||(Next.Num()<8&&(B.Kind==TEXT("class")||B.Kind==TEXT("work")||B.Kind==TEXT("promise")))){const FOKStreetPlace* P=OKStreetFindPlace(B.Place);
   // On the hour or the quarter as people say it ("快十点"), not the staggered 09:44 she once repeated word for word.
   const int32 Said=(B.Start+7)/15*15;
   const FString Block=OKMsg(TEXT("ui.director.plan_block"),{{TEXT("doing"),OKPhoneDoingWord(B.Kind)},{TEXT("place"),P?FString(P->Name):B.Place}});
   // The block she is in already is now, not at its start: at 10:30 刻晴 said she would go to the library "at 10:15" (R4-2).
   if(B.Start<=Minute){const int32 Until=(B.End+7)/15*15;Next.Add(OKMsg(TEXT("ui.director.plan_now"),{{TEXT("end"),FString::Printf(TEXT("%02d:%02d"),Until/60%24,Until%60)},{TEXT("block"),Block}}));}
   else Next.Add(FString::Printf(TEXT("%02d:%02d %s"),Said/60%24,Said%60,*Block));}
  if(Next.Num())Parts.Add(OKMsg(TEXT("ui.director.your_plan_line"),{{TEXT("plan"),FString::Join(Next,OKT(TEXT("ui.bank.list_separator")))}}));
  // And what her day already held: 安可, back from an afternoon at the library, said she had not been there yet, and
  // Jeanne said she had no class that morning after one (R6-163). The last four, merged the same way.
  TArray<FOKStreetPlanBlock> Done;
  for(const auto& B:*Plan)if(B.End<=Minute&&B.Kind!=TEXT("sleep")){
   if(Done.Num()&&Done.Last().Kind==B.Kind&&Done.Last().Place==B.Place&&Done.Last().End>=B.Start-1){if(B.Kind==TEXT("class")||B.Kind==TEXT("work"))Done.Last().Start=FMath::Max(Done.Last().Start,B.Start);Done.Last().End=B.End;}
   else Done.Add(B);}
  // Before those four, still what she was bound to (a class, a shift, a promise): 爱丽丝 worked the drink shop 10:00-15:10
  // and, four leisure blocks later, told him at dinner she had no work today (R6-172).
  TArray<int32> Keep;for(int32 K=0;K<Done.Num();++K){const FString& Kind=Done[K].Kind;if(K>=Done.Num()-4||Kind==TEXT("class")||Kind==TEXT("work")||Kind==TEXT("promise"))Keep.Add(K);}
  while(Keep.Num()>8)Keep.RemoveAt(0);
  TArray<FString> Earlier;for(const int32 K:Keep){const auto& B=Done[K];const FOKStreetPlace* P=OKStreetFindPlace(B.Place);const int32 Said=(B.Start+7)/15*15;
   Earlier.Add(FString::Printf(TEXT("%02d:%02d %s"),Said/60%24,Said%60,*OKMsg(TEXT("ui.director.plan_block"),{{TEXT("doing"),OKPhoneDoingWord(B.Kind)},{TEXT("place"),P?FString(P->Name):B.Place}})));}
  if(Earlier.Num())Parts.Add(OKMsg(TEXT("ui.director.your_day_so_far_line"),{{TEXT("done"),FString::Join(Earlier,OKT(TEXT("ui.bank.list_separator")))}}));}
 if(BirthdayOf(Character,Day))Parts.Add(OKT(TEXT("ui.director.today_is_birthday")));else if(BirthdayOf(Character,Day+1))Parts.Add(OKT(TEXT("ui.director.tomorrow_birthday_hint")));
 return FString::Join(Parts,OKT(TEXT("ui.bank.list_separator")));
}

// Plan §6.6: three times a day each heroine weighs acting first; the strongest reason wins (social.rs initiative).
// Acting means walking over (or messaging when far) with what she wants on her mind; the words come later.
void AOKStreetSocialScene::TickInitiative(){
 auto& S=*State;if(S.SelfTest||!S.Mind)return;
 const int64 Now=OKStreetMindNow(S);const int32 Minute=int32(Now%1440);
 // Only near a slot change is there anything to weigh (07:00, 12:00, 18:00).
 const int32 Slot=Minute/60>=18?3:Minute/60>=12?2:Minute/60>=7?1:0;if(Slot==0||S.Store.CalendarDay*4+Slot==S.InitiativeSlot)return;
 auto Request=OKRulesRequest(TEXT("initiative"));Request->SetNumberField(TEXT("minute"),Minute);Request->SetNumberField(TEXT("day"),S.Store.CalendarDay);Request->SetNumberField(TEXT("last_slot"),S.InitiativeSlot);
 Request->SetNumberField(TEXT("player_cash"),double(S.Store.PlayerCash)); // she does not come to borrow from a man with nothing
 Request->SetBoolField(TEXT("rain"),RainingAt(S.Store.CalendarDay,Minute)&&PlaceHere(S.Male).IsEmpty());Request->SetStringField(TEXT("holiday"),HolidayOn(S.Store.CalendarDay));
 auto Names=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Rows;
 for(int32 I=1;I<S.Manifest.Characters.Num();++I){
  // With him in the private room she is not weighing the street (her "hungry, ask him to eat" came in mid-H).
  if(S.PrivateGirl==I&&S.PrivateMode.IsValid())continue;
  const FString Id=OKStreetStableId(S.Manifest.Characters[I]);Names->SetStringField(Id,S.Manifest.Characters[I].Name);
  auto H=MakeShared<FJsonObject>();H->SetNumberField(TEXT("actor"),I);H->SetStringField(TEXT("id"),Id);H->SetObjectField(TEXT("relation"),OKRulesRelationJson(OKStreetViewRelation(S.Store,Id,S.Manifest.TalkBudget)));
  if(const auto P=ProfileOf(I))H->SetObjectField(TEXT("profile"),P.ToSharedRef());
  H->SetBoolField(TEXT("busy"),BusyWithPlayer(I));H->SetBoolField(TEXT("near"),S.Agents.IsValidIndex(I-1)&&FVector::Dist2D(S.Agents[I-1].Position,S.Male)<3000);H->SetBoolField(TEXT("birthday_tomorrow"),BirthdayOf(I,S.Store.CalendarDay+1));
  Rows.Add(MakeShared<FJsonValueObject>(H));
 }
 Request->SetObjectField(TEXT("names"),Names);Request->SetArrayField(TEXT("heroines"),Rows);
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer)return;
 S.InitiativeSlot=int32(Answer->GetNumberField(TEXT("slot")));
 double Actor=0;if(!Answer->TryGetNumberField(TEXT("actor"),Actor))return;
 const int32 BestI=int32(Actor);const FString Why=Answer->GetStringField(TEXT("why"));
 ApplyRulesEffects(S.Store,*Answer);S.InitiativeReason.Add(BestI,Why);
 if(S.ApproachNext.IsValidIndex(BestI))S.ApproachNext[BestI]=FPlatformTime::Seconds();
 ++S.InitiativesToday;
 UE_LOG(LogTemp,Display,TEXT("Street initiative: actor=%d score=%.0f %s"),BestI,Answer->GetNumberField(TEXT("score")),*Why);
}

// The open-world Director (plan §14): no crises are handed out; it only makes sure he can find out about one
// (social.rs director).
void AOKStreetSocialScene::TickDirector(){
 auto& S=*State;if(S.SelfTest||!S.Mind||S.DirectorDay==S.Store.CalendarDay)return;S.DirectorDay=S.Store.CalendarDay;
 auto Request=OKRulesRequest(TEXT("director"));Request->SetNumberField(TEXT("day"),S.Store.CalendarDay);
 TArray<TSharedPtr<FJsonValue>> Rows;for(int32 I=1;I<S.Manifest.Characters.Num();++I){auto H=MakeShared<FJsonObject>();H->SetStringField(TEXT("id"),OKStreetStableId(S.Manifest.Characters[I]));H->SetStringField(TEXT("name"),S.Manifest.Characters[I].Name);if(const auto P=ProfileOf(I))H->SetObjectField(TEXT("profile"),P.ToSharedRef());Rows.Add(MakeShared<FJsonValueObject>(H));}
 Request->SetArrayField(TEXT("heroines"),Rows);
 TArray<TSharedPtr<FJsonValue>> Known;for(const auto& R:S.Store.Rumors){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("about"),R.About);O->SetStringField(TEXT("kind"),R.Kind);Known.Add(MakeShared<FJsonValueObject>(O));}
 Request->SetArrayField(TEXT("rumors"),Known);
 TArray<TSharedPtr<FJsonValue>> Bonds;for(const auto& Bond:S.Store.BondHeat)Bonds.Add(MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueString>(Bond.Key),MakeShared<FJsonValueNumber>(Bond.Value)}));
 Request->SetArrayField(TEXT("bond_heat"),Bonds);
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer||Answer->GetArrayField(TEXT("rumors")).IsEmpty())return;
 auto Candidate=S.Store;
 for(const auto& V:Answer->GetArrayField(TEXT("rumors"))){FOKStreetRumor R;OKRulesReadRumor(*V->AsObject(),R);R.Id=Candidate.NextRumor++;Candidate.Rumors.Add(R);UE_LOG(LogTemp,Display,TEXT("Street director: %s's hidden need can now be heard about"),*R.About);}
 CommitStore(MoveTemp(Candidate));
}

// End of day birthday check (plan §11.3): forgetting costs "being seen" (social.rs birthday_end).
void AOKStreetSocialScene::CheckBirthdays(){
 auto& S=*State;
 for(int32 I=1;I<S.Manifest.Characters.Num();++I){
  if(!BirthdayOf(I,S.Store.CalendarDay))continue;
  const FString Id=OKStreetStableId(S.Manifest.Characters[I]);
  auto Request=OKRulesRelationRequest(TEXT("birthday_end"),OKStreetViewRelation(S.Store,Id,S.Manifest.TalkBudget),ProfileOf(I));Request->SetBoolField(TEXT("together"),S.InteractedToday.Contains(I));
  const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer)continue;
  auto Candidate=S.Store;ApplyRulesEffects(Candidate,*Answer);CommitStore(MoveTemp(Candidate));
 }
}
