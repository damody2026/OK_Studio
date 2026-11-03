// A heroine whose desire is full (200, OKStreetSexDesireMax; user 2026-11-03) touches herself where she stands on the
// street for a game hour: the original's standing masturbation (kht_f_02, HMasturbation's states WLoop, MLoop, SLoop,
// OLoop, Orgasm, Orgasm_A, Orgasm_B) round and round, her crotch spraying hard as she comes. Spoken to meanwhile, she
// goes straight into the one-on-one with him whoever he is to her (BeginTalk, BeginPrivate: street_onani).
struct FOKStreetOnaniStep {const TCHAR* Clip;float Seconds;bool Squirt;};
// Seconds of each (0: the clip once through); with the change between two (about 1.8 s, her stand blended through)
// about forty-five a round: three or four climaxes in her hour (two and a half real minutes).
static const FOKStreetOnaniStep OKStreetOnaniSteps[]={
 {TEXT("street_onani_wloop.okanim"),6.f,false},{TEXT("street_onani_mloop1.okanim"),6.f,false},{TEXT("street_onani_sloop.okanim"),6.f,false},
 {TEXT("street_onani_oloop.okanim"),4.f,false},{TEXT("street_onani_orgasm.okanim"),0.f,true},{TEXT("street_onani_orgasm_a.okanim"),6.f,true},
 {TEXT("street_onani_orgasm_b.okanim"),6.f,false}};
static constexpr int64 OKStreetOnaniMinutes=60;

void AOKStreetSocialScene::StopOnani(bool bSettle){
 if(!State||State->OnaniGirl==INDEX_NONE)return;auto& S=*State;const int32 Girl=S.OnaniGirl;
 S.OnaniGirl=INDEX_NONE;S.OnaniPlaying=false;
 FString Error;ResumeBehavior(Girl,Error);
 if(S.Agents.IsValidIndex(Girl-1)){
  const FVector Position=S.Agents[Girl-1].Position;S.Agents[Girl-1]=S.OnaniSaved;
  auto& Agent=S.Agents[Girl-1];Agent.Position=Position;Agent.Held=false;Agent.Dwell=0;Agent.DwellPoint=INDEX_NONE;Agent.Stuck=0;Agent.Mode=EOKStreetMove::Walking;
 }
 // Her hour done: each climax satisfied ten points of her desire, as one with him does (hexp.rs session_end), so she does
 // not start again at once. Taken into the room by him instead, the room's own end settles it.
 if(bSettle&&S.OnaniClimaxes>0){
  const int32 Field=OKHeroineStats().IndexOfByPredicate([](const FOKHeroineStat& Stat){return FCString::Strcmp(Stat.Id,TEXT("sex_desire"))==0;});
  const float Desire=OKStreetViewRelation(S.Store,OKStreetStableId(S.Manifest.Characters[Girl]),S.Manifest.TalkBudget).SexDesire;
  if(Field!=INDEX_NONE)SetCharacterStat(Girl,Field,FMath::Max(0.f,Desire-10.f*S.OnaniClimaxes));
 }
 S.OnaniCooldown.Add(Girl,SceneTime()+120.0);
 UE_LOG(LogTemp,Display,TEXT("Street onani: actor %d stops after %d climaxes (%s)"),Girl,S.OnaniClimaxes,bSettle?TEXT("her hour is up"):TEXT("interrupted"));
}

void AOKStreetSocialScene::TickOnani(double Now){
 auto& S=*State;
 if(S.OnaniGirl==INDEX_NONE){
  if(!S.AllReady||S.SelfTest||Now<S.OnaniCheckAt)return;S.OnaniCheckAt=Now+2.0;
  const int32 Minute=int32(OKStreetMindNow(S)%1440);
  // The nearest of those at full desire who are out and about (not with him, not sitting at her post, not asleep).
  int32 Best=INDEX_NONE;float BestD=MAX_flt;
  for(const auto& Agent:S.Agents){const int32 I=Agent.Slot;
   if(!S.Manifest.Characters.IsValidIndex(I)||!OKStreetIsFemaleTarget(I,S.Manifest.Characters[I])||(Agent.Held&&!S.ScheduleHeld.Contains(I))||BusyWithPlayer(I)||InLifePose(I)||S.AmbientActor==I||S.Commutes.Contains(I)||S.NpcLifts.Contains(I)||S.OnaniCooldown.FindRef(I)>Now)continue;
   if(OKStreetViewRelation(S.Store,OKStreetStableId(S.Manifest.Characters[I]),S.Manifest.TalkBudget).SexDesire<OKStreetSexDesireMax)continue;
   const FOKStreetPlanBlock* B=LifeBlock(I,Minute);if(B&&(B->Kind==TEXT("sleep")||B->Kind==TEXT("bath")))continue;
   FOKRuntimeCharacterStatus Status;if(!OKGetCrowdRuntimeCharacterStatus(this,I,Status)||!Status.Visible||!Status.ActionsReady||!Status.Error.IsEmpty())continue;
   const float D=FVector::Dist2D(Agent.Position,S.Male);if(D<BestD){BestD=D;Best=I;}
  }
  if(Best==INDEX_NONE)return;
  auto& Agent=S.Agents[Best-1];S.OnaniSaved=Agent;Agent.Held=true;
  S.OnaniGirl=Best;S.OnaniStep=0;S.OnaniPlaying=false;S.OnaniRequested=Now;S.OnaniAskedAt=0;S.OnaniClimaxes=0;S.OnaniStartMinute=OKStreetMindNow(S);
  UE_LOG(LogTemp,Display,TEXT("Street onani: actor %d at full desire touches herself (%.0f cm from him)"),Best,BestD);
  return;
 }
 const int32 Girl=S.OnaniGirl;
 // He took her somewhere or into something (the room has its own end): this ends here.
 if(!S.Agents.IsValidIndex(Girl-1)||S.Target==Girl||S.Companion==Girl||S.PrivateGirl==Girl||S.Pair.Partner==Girl||S.OutingGirl==Girl||S.SoloGirl==Girl){StopOnani(false);return;}
 if(OKStreetMindNow(S)-S.OnaniStartMinute>=OKStreetOnaniMinutes){StopOnani(true);return;}
 const FOKStreetOnaniStep& Step=OKStreetOnaniSteps[S.OnaniStep];
 FOKRuntimeActionStreamStatus A;if(!OKGetCrowdRuntimeActionStatus(this,Girl,A)){StopOnani(false);return;}
 // ClipId names the clip being prepared when there is one: hers shows when it plays with nothing pending.
 const bool Shows=A.Playing&&A.ClipId==Step.Clip&&!A.Pending&&!A.Preparing;
 // Waiting for this step's clip to start. She has one action slot: the clip she shows is let go (a short blend through
 // her stand, as her song's moves do, OKStreetSocialSong.inl SongStage) and this one starts once the slot is free;
 // something else still prepared for her is dropped for it. Asked again each half second until then. (Not prepared
 // behind the one she shows: with her slot taken that request waited out its 60 s and held the change up as long.)
 if(!S.OnaniPlaying){
  if(!Shows&&Now-S.OnaniAskedAt>=.5&&!(A.ClipId==Step.Clip&&(A.Pending||A.Preparing))){S.OnaniAskedAt=Now;FString Error;
   if(A.Playing&&A.ClipId!=Step.Clip)OKReleaseCrowdRuntimeAction(this,Girl,Error);
   if(!OKPlayCrowdRuntimeAction(this,Girl,Step.Clip,Error)){FString Ignore;OKCancelCrowdRuntimeAction(this,Girl,Ignore);
    if(!OKPlayCrowdRuntimeAction(this,Girl,Step.Clip,Error))UE_LOG(LogTemp,Verbose,TEXT("Street onani: %s not yet: %s"),Step.Clip,*Error);}}
  if(Shows){S.OnaniPlaying=true;S.OnaniStepAt=Now;S.OnaniStepSeconds=Step.Seconds>0?Step.Seconds:FMath::Max(.5f,A.DurationSeconds-.15f);
   UE_LOG(LogTemp,Display,TEXT("Street onani: actor %d %s, %.1f s after asking, for %.1f s"),Girl,Step.Clip,Now-S.OnaniRequested,S.OnaniStepSeconds);
   if(S.OnaniStep==4){++S.OnaniClimaxes;UE_LOG(LogTemp,Display,TEXT("Street onani: actor %d comes (%d)"),Girl,S.OnaniClimaxes);}}
  else if(Now-S.OnaniRequested>OKCrowdRuntimeActionPrepareSeconds){UE_LOG(LogTemp,Warning,TEXT("Street onani: %s never started"),Step.Clip);StopOnani(false);}
  return;
 }
 // Coming: her crotch sprays hard, shot out ahead of her (from her hips through her crotch), a drop every 30 ms.
 if(Step.Squirt&&Now>=S.OnaniSquirtAt){S.OnaniSquirtAt=Now+.03;FVector Kokan,Hips;
  if(OKGetCrowdRuntimeBonePosition(this,Girl,TEXT("cf_J_Kokan"),Kokan)&&OKGetCrowdRuntimeBonePosition(this,Girl,TEXT("cf_j_hips"),Hips)){
   const FVector V=((Kokan-Hips).GetSafeNormal()+FMath::VRand()*.3f).GetSafeNormal()*220.f*FMath::FRandRange(.7f,1.2f);
   if(S.ArousalDrops.Squirt(this,Girl,Kokan,V,S.Agents[Girl-1].Position.Z+.3f,OKArousal::Clear))++S.ArousalWetCrotch[Girl];}}
 if(Now-S.OnaniStepAt<S.OnaniStepSeconds)return;
 S.OnaniStep=(S.OnaniStep+1)%UE_ARRAY_COUNT(OKStreetOnaniSteps);S.OnaniPlaying=false;S.OnaniRequested=Now;S.OnaniAskedAt=0;
}
