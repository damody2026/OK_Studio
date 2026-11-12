// ---- The roster menu (the button under the minimap): which heroines live in this world, and this save's own settings
// and memories for each of them.
//
// Cards: the heroine folder (Content/CharacterCards/StreetHeroines). Cards dragged onto the game window are copied into
// it; an original KKS card there (dragged or copied in by hand) is made into an OK card (ok-extract --oklib card, about a
// minute), the original kept in KKS/ beside it. Tools/street_roster.lua does the file work on a worker.
// The roster is the save's (roster.json in the live game folder, copied with every slot): applying it saves the game,
// and the map starts again; at the start the selection gets the save's heroines (ApplyRosterToManifest).
// Settings are the save's too, never her card's: her name and persona text (heroine-settings.json, ApplyHeroineSettings),
// her profile and her memories (the mind's heroines/ and memory/ files, written through ok-mind's set_profile and
// set_memories). Her conversation context can be dropped so she starts afresh with them.
#include "Async/Async.h"
#include "Input/DragAndDrop.h"
#include "Widgets/Input/SMultiLineEditableTextBox.h"

// The checkout the game runs from: up from the executable to the folder that holds Tools/street_roster.lua (a packaged
// stage lives under Saved/StreetSocial/Build/<tag>.stage).
static FString OKStreetRepoRoot(){
 static FString Root;if(!Root.IsEmpty())return Root;
 for(FString Dir=FPaths::ConvertRelativePathToFull(FPlatformProcess::BaseDir());!Dir.IsEmpty();){
  FPaths::NormalizeDirectoryName(Dir);
  if(FPaths::FileExists(Dir/TEXT("Tools/street_roster.lua"))){Root=Dir;break;}
  const FString Up=FPaths::GetPath(Dir);if(Up.IsEmpty()||Up==Dir)break;Dir=Up;}
 if(Root.IsEmpty())Root=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());
 return Root;
}

static FString OKStreetRosterDir(){return OKStreetRepoRoot()/TEXT("Content/CharacterCards/StreetHeroines");}

static FString OKStreetRosterKey(const FString& Path){FString P=FPaths::ConvertRelativePathToFull(Path);FPaths::NormalizeFilename(P);return P.ToLower();}

// Tools/street_roster.lua with these arguments, waiting for it (call it off the game thread when it may convert a card).
static bool OKStreetRosterLua(const TArray<FString>& Args,FString& Log){
 const FString Root=OKStreetRepoRoot();
 FString Params=FString::Printf(TEXT("\"%s\""),*(Root/TEXT("Tools/street_roster.lua")));
 for(const FString& A:Args)Params+=FString::Printf(TEXT(" \"%s\""),*A.Replace(TEXT("\""),TEXT("")));
 int32 Code=-1;FString Out,Err;
 const bool Ran=FPlatformProcess::ExecProcess(*(Root/TEXT("Tools/lua/lua.exe")),*Params,&Code,&Out,&Err,*Root);
 Log=(Out+Err).TrimStartAndEnd();
 if(!Ran||Code!=0)UE_LOG(LogTemp,Warning,TEXT("Street roster: street_roster.lua %s failed (%d): %s"),Args.Num()?*Args[0]:TEXT(""),Code,*Log.Right(800));
 return Ran&&Code==0;
}

static TSharedPtr<FJsonObject> OKStreetRosterReadJson(const FString& Path){
 FString Body;TSharedPtr<FJsonObject> Root;
 if(!FFileHelper::LoadFileToString(Body,*Path)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Body),Root))return nullptr;
 return Root;
}

static bool OKStreetRosterWriteJson(const FString& Path,const TSharedRef<FJsonObject>& Root){
 FString Body;FJsonSerializer::Serialize(Root,TJsonWriterFactory<>::Create(&Body));
 return FFileHelper::SaveStringToFile(Body,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}

// Files dragged in from Explorer, while a drag is over the window.
class SOKStreetRosterDrop:public SCompoundWidget{
public:
 SLATE_BEGIN_ARGS(SOKStreetRosterDrop){}SLATE_ARGUMENT(FString,Label)SLATE_END_ARGS()
 TFunction<void(const TArray<FString>&)> OnFiles;
 void Construct(const FArguments& Args){
  ChildSlot[SNew(SBorder).BorderImage(FCoreStyle::Get().GetBrush("WhiteBrush")).BorderBackgroundColor(FLinearColor(0,0,0,.5f)).HAlign(HAlign_Center).VAlign(VAlign_Center)
   [SNew(STextBlock).Font(FCoreStyle::GetDefaultFontStyle("Bold",28)).ColorAndOpacity(FLinearColor::White).Text(FText::FromString(Args._Label))]];
 }
 static bool Dragging(){
  if(!FSlateApplication::IsInitialized()||!FSlateApplication::Get().IsDragDropping())return false;
  const TSharedPtr<FDragDropOperation> Op=FSlateApplication::Get().GetDragDroppingContent();return Op.IsValid()&&Op->IsOfType<FExternalDragOperation>();
 }
 static TArray<FString> Files(const FDragDropEvent& Event){
  const TSharedPtr<FExternalDragOperation> Op=Event.GetOperationAs<FExternalDragOperation>();
  return Op.IsValid()&&Op->HasFiles()?Op->GetFiles():TArray<FString>();
 }
 virtual FReply OnDragOver(const FGeometry&,const FDragDropEvent& Event) override{return Files(Event).Num()?FReply::Handled():FReply::Unhandled();}
 virtual FReply OnDrop(const FGeometry&,const FDragDropEvent& Event) override{
  const TArray<FString> F=Files(Event);if(F.Num()&&OnFiles)OnFiles(F);return F.Num()?FReply::Handled():FReply::Unhandled();
 }
};

TSharedRef<SWidget> AOKStreetSocialScene::RosterDropZone(){
 TSharedRef<SOKStreetRosterDrop> Zone=SNew(SOKStreetRosterDrop).Label(OKT(TEXT("ui.roster.drop_here")));
 Zone->SetVisibility(TAttribute<EVisibility>::CreateLambda([](){return SOKStreetRosterDrop::Dragging()?EVisibility::Visible:EVisibility::Collapsed;}));
 Zone->OnFiles=[Weak=TWeakObjectPtr<AOKStreetSocialScene>(this)](const TArray<FString>& Files){
  if(!Weak.IsValid())return;TArray<FString> Cards;for(const FString& F:Files)if(F.EndsWith(TEXT(".png"),ESearchCase::IgnoreCase))Cards.Add(F);
  if(!Weak->State->RosterOpen)Weak->OpenRoster();
  if(Cards.IsEmpty()){Weak->State->RosterNotice=OKT(TEXT("ui.roster.drop_not_png"));Weak->RosterRebuild();return;}
  Weak->RosterRun(TEXT("import"),Cards);};
 return Zone;
}

FString AOKStreetSocialScene::RosterLiveDir() const{return FPaths::GetPath(State->Manifest.SavePath);}

// At the start: the selection with the save's heroines in place of the launcher's (their cast made by the launcher's own
// prepare step), when the save has a roster that differs. False when nothing changed.
bool AOKStreetSocialScene::ApplyRosterToManifest(const FString& ManifestPath,FString& Json){
 auto& S=*State;if(S.Manifest.SavePath.IsEmpty())return false;
 const TSharedPtr<FJsonObject> Roster=OKStreetRosterReadJson(RosterLiveDir()/TEXT("roster.json"));
 const TArray<TSharedPtr<FJsonValue>>* Want=nullptr;if(!Roster||!Roster->TryGetArrayField(TEXT("cards"),Want))return false;
 TArray<FString> Cards;TSet<FString> Seen;
 for(const auto& V:*Want){const FString P=V->AsString();if(P.IsEmpty()||!FPaths::FileExists(P)){UE_LOG(LogTemp,Warning,TEXT("Street roster: %s is gone, left out"),*P);continue;}
  if(!Seen.Contains(OKStreetRosterKey(P))&&Cards.Num()<OKStreetFemaleCount){Seen.Add(OKStreetRosterKey(P));Cards.Add(P);}}
 TSharedPtr<FJsonObject> Root;const TArray<TSharedPtr<FJsonValue>>* Now=nullptr;
 if(Cards.IsEmpty()||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Root)||!Root||!Root->TryGetArrayField(TEXT("cards"),Now)||Now->Num()<1)return false;
 bool Same=Now->Num()==Cards.Num()+1;for(int32 I=0;Same&&I<Cards.Num();++I)Same=OKStreetRosterKey((*Now)[I+1]->AsString())==OKStreetRosterKey(Cards[I]);
 if(Same)return false;
 const FString Dir=FPaths::GetPath(ManifestPath),CardsFile=Dir/TEXT("roster.cards.json"),CastFile=Dir/TEXT("roster.cast.json");
 {auto List=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> A;for(const FString& C:Cards)A.Add(MakeShared<FJsonValueString>(C));List->SetArrayField(TEXT("cards"),A);
  if(!OKStreetRosterWriteJson(CardsFile,List))return false;}
 FString Log;
 if(!OKStreetRosterLua({TEXT("cast"),TEXT("--male"),(*Now)[0]->AsString(),TEXT("--cards"),CardsFile,TEXT("--output"),CastFile},Log))return false;
 const TSharedPtr<FJsonObject> Cast=OKStreetRosterReadJson(CastFile);if(!Cast)return false;
 for(const TCHAR* Key:{TEXT("cards"),TEXT("outfits"),TEXT("characters")}){const TSharedPtr<FJsonValue> V=Cast->TryGetField(Key);if(!V)return false;Root->SetField(Key,V);}
 FString Body;FJsonSerializer::Serialize(Root.ToSharedRef(),TJsonWriterFactory<>::Create(&Body));
 if(!FFileHelper::SaveStringToFile(Body,*ManifestPath,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)){UE_LOG(LogTemp,Warning,TEXT("Street roster: cannot write %s"),*ManifestPath);return false;}
 Json=Body;UE_LOG(LogTemp,Display,TEXT("Street roster: the world has the save's %d heroines"),Cards.Num());
 return true;
}

// The save's names and persona texts for its heroines (heroine-settings.json), over what their cards say.
void AOKStreetSocialScene::ApplyHeroineSettings(){
 auto& S=*State;const TSharedPtr<FJsonObject> All=OKStreetRosterReadJson(RosterLiveDir()/TEXT("heroine-settings.json"));
 OKStreetFreeTalkClearPersonaOverrides();
 for(int32 I=1;I<S.Manifest.Characters.Num();++I){auto& C=S.Manifest.Characters[I];const FString Id=OKStreetStableId(C);
  const FString Base=S.RosterBaseNames.FindOrAdd(Id,C.Name);
  const TSharedPtr<FJsonObject>* Mine=nullptr;FString Name,Persona;
  if(All&&All->TryGetObjectField(Id,Mine)&&Mine&&Mine->IsValid()){(*Mine)->TryGetStringField(TEXT("name"),Name);(*Mine)->TryGetStringField(TEXT("persona"),Persona);}
  Name=Name.TrimStartAndEnd();C.Name=Name.IsEmpty()?Base:Name;
  if(C.Name!=Base||!Persona.IsEmpty())OKStreetFreeTalkSetPersonaOverride(C.Name,Base,Persona);}
}

void AOKStreetSocialScene::OpenRoster(){
 auto& S=*State;if(S.RosterOpen)return;
 S.RosterOpen=true;S.RosterEdit=INDEX_NONE;S.RosterNotice.Reset();
 S.RosterPausedClock=!S.ClockPaused;if(!S.ClockPaused){S.ClockStartHours=OKStreetClockHours(S.ClockStartHours,FPlatformTime::Seconds()-S.ClockStartWall);S.ClockStartWall=FPlatformTime::Seconds();S.ClockPaused=true;}
 // The world as it is: its cards before any clinic restyle.
 S.RosterWorld.Reset();const TArray<FString>& Cards=S.BaseCards.Num()?S.BaseCards:S.HighCards;for(int32 I=1;I<Cards.Num();++I)S.RosterWorld.Add(Cards[I]);
 S.RosterPicked=S.RosterWorld;
 S.MouseUI=true;ApplyMouseMode(true);
 RosterRun(TEXT("scan"),{});
}

void AOKStreetSocialScene::CloseRoster(){
 auto& S=*State;if(!S.RosterOpen)return;
 S.RosterOpen=false;S.RosterEdit=INDEX_NONE;if(S.UiRosterHolder)S.UiRosterHolder->SetContent(SNullWidget::NullWidget);
 if(S.RosterPausedClock){S.ClockPaused=false;S.ClockStartWall=FPlatformTime::Seconds();}S.RosterPausedClock=false;RefreshUI();
}

// The folder scanned (and its KKS cards converted), after copying in the files dropped: on a worker, the list back here.
void AOKStreetSocialScene::RosterRun(const FString& Command,const TArray<FString>& Files){
 auto& S=*State;if(S.RosterBusy){S.RosterNotice=OKT(TEXT("ui.roster.busy"));RosterRebuild();return;}
 S.RosterBusy=true;S.RosterNotice=OKT(Command==TEXT("import")?TEXT("ui.roster.importing"):TEXT("ui.roster.scanning"));RosterRebuild();
 const FString Dir=OKStreetRosterDir(),Out=RosterLiveDir()/TEXT("roster.scan.json");
 TArray<FString> Args={Command,TEXT("--dir"),Dir,TEXT("--output"),Out};Args.Append(Files);
 Async(EAsyncExecution::Thread,[Weak=TWeakObjectPtr<AOKStreetSocialScene>(this),Args,Out](){
  FString Log;const bool Ok=OKStreetRosterLua(Args,Log);const TSharedPtr<FJsonObject> Scan=Ok?OKStreetRosterReadJson(Out):nullptr;
  AsyncTask(ENamedThreads::GameThread,[Weak,Ok,Log,Scan](){
   if(!Weak.IsValid()||!Weak->State)return;auto& L=*Weak->State;L.RosterBusy=false;
   if(!Scan){L.RosterNotice=OKMsg(TEXT("ui.roster.failed"),{{TEXT("log"),Log.Right(300)}});Weak->RosterRebuild();return;}
   L.RosterCards.Reset();const TArray<TSharedPtr<FJsonValue>>* Cards=nullptr;
   if(Scan->TryGetArrayField(TEXT("cards"),Cards))for(const auto& V:*Cards)if(V->AsObject())L.RosterCards.Add(V->AsObject());
   int32 Converted=0;TArray<FString> Problems;const TArray<TSharedPtr<FJsonValue>>* Entries=nullptr;
   if(Scan->TryGetArrayField(TEXT("log"),Entries))for(const auto& V:*Entries){const auto E=V->AsObject();if(!E)continue;bool C=false;FString Err;
    if(E->TryGetBoolField(TEXT("converted"),C)&&C)++Converted;
    if(E->TryGetStringField(TEXT("error"),Err))Problems.Add(FPaths::GetCleanFilename(E->GetStringField(TEXT("card")))+TEXT(": ")+Err.Left(160));}
   L.RosterNotice=OKMsg(TEXT("ui.roster.scanned"),{{TEXT("count"),L.RosterCards.Num()},{TEXT("converted"),Converted}});
   if(Problems.Num())L.RosterNotice+=TEXT("\n")+FString::Join(Problems,TEXT("\n"));
   Weak->RosterRebuild();});});
}

// Who is picked becomes the save's roster; the game is saved and the map starts again with them.
void AOKStreetSocialScene::RosterApply(){
 auto& S=*State;if(S.RosterPicked.IsEmpty()||S.Manifest.SavePath.IsEmpty())return;
 auto Root=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> A;for(const FString& C:S.RosterPicked)A.Add(MakeShared<FJsonValueString>(C));Root->SetArrayField(TEXT("cards"),A);
 if(!OKStreetRosterWriteJson(RosterLiveDir()/TEXT("roster.json"),Root)){S.RosterNotice=OKT(TEXT("ui.roster.write_failed"));RosterRebuild();return;}
 UE_LOG(LogTemp,Display,TEXT("Street roster: %d heroines picked; the world starts again with them"),S.RosterPicked.Num());
 S.RosterNotice=OKT(TEXT("ui.saves.restarting"));RosterRebuild();
 SaveToSlot(TEXT("auto"));RestartWithSave(TEXT("load"),TEXT("auto"));
}

// Her settings or her memories into the editor, as the save has them now.
void AOKStreetSocialScene::RosterEditHer(int32 Her,const FString& Tab){
 auto& S=*State;if(!S.Manifest.Characters.IsValidIndex(Her)||Her<1)return;
 S.RosterEdit=Her;S.RosterTab=Tab;S.RosterNotice.Reset();
 const auto& C=S.Manifest.Characters[Her];const FString Id=OKStreetStableId(C);
 auto Query=[&](const TCHAR* Kind,FString& Out)->TSharedPtr<FJsonObject>{
  if(!S.Mind){S.RosterNotice=OKT(TEXT("ui.roster.no_mind"));return nullptr;}
  auto Q=MakeShared<FJsonObject>();Q->SetStringField(TEXT("kind"),Kind);Q->SetStringField(TEXT("heroine"),Id);FString Error;
  if(!S.Mind->Query(OKStreetMindJson(Q),Out,Error)){S.RosterNotice=Error;return nullptr;}
  TSharedPtr<FJsonObject> R;FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Out),R);return R;};
 FString Out;
 if(Tab==TEXT("settings")){
  S.RosterName=C.Name;FOKFreeTalkPersona Persona;FString Error;OKStreetFreeTalkLoadPersona(C.Name,Persona,Error);S.RosterPersona=S.RosterPersonaLoaded=Persona.Profile;
  S.RosterProfile.Reset();const TSharedPtr<FJsonObject> R=Query(TEXT("profile"),Out);const TSharedPtr<FJsonObject>* P=nullptr;
  if(R&&R->TryGetObjectField(TEXT("profile"),P)&&P&&P->IsValid())FJsonSerializer::Serialize(P->ToSharedRef(),TJsonWriterFactory<>::Create(&S.RosterProfile));
 }else{
  TArray<FString> Lines;const TSharedPtr<FJsonObject> R=Query(TEXT("memories"),Out);const TArray<TSharedPtr<FJsonValue>>* M=nullptr;
  if(R&&R->TryGetArrayField(TEXT("memories"),M))for(const auto& V:*M){const auto Rec=V->AsObject();if(!Rec)continue;
   const FDateTime When=OKStreetCalendarEpoch()+FTimespan::FromMinutes(Rec->GetNumberField(TEXT("t")));
   Lines.Add(FString::Printf(TEXT("[%s %.2f %d/%d %02d:%02d] %s"),*Rec->GetStringField(TEXT("id")),Rec->GetNumberField(TEXT("importance")),When.GetMonth(),When.GetDay(),When.GetHour(),When.GetMinute(),*Rec->GetStringField(TEXT("summary")).Replace(TEXT("\n"),TEXT(" "))));}
  S.RosterMemory=FString::Join(Lines,TEXT("\n"));
 }
 RosterRebuild();
}

// Her name and persona into the save's settings, her profile into the mind's file of this save; at once in this game.
void AOKStreetSocialScene::RosterSaveSettings(){
 auto& S=*State;const int32 Her=S.RosterEdit;if(!S.Manifest.Characters.IsValidIndex(Her)||Her<1)return;
 const FString Id=OKStreetStableId(S.Manifest.Characters[Her]);
 if(!S.RosterProfile.TrimStartAndEnd().IsEmpty()){
  TSharedPtr<FJsonObject> Profile;if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(S.RosterProfile),Profile)||!Profile){S.RosterNotice=OKT(TEXT("ui.roster.profile_bad_json"));RosterRebuild();return;}
  if(S.Mind){auto Q=MakeShared<FJsonObject>();Q->SetStringField(TEXT("kind"),TEXT("set_profile"));Q->SetStringField(TEXT("heroine"),Id);Q->SetObjectField(TEXT("profile"),Profile);
   FString Out,Error;if(!S.Mind->Query(OKStreetMindJson(Q),Out,Error)){S.RosterNotice=OKMsg(TEXT("ui.roster.save_failed"),{{TEXT("error"),Error}});RosterRebuild();return;}
   TSharedPtr<FJsonObject> R;const TSharedPtr<FJsonObject>* Saved=nullptr;
   if(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Out),R)&&R&&R->TryGetObjectField(TEXT("profile"),Saved)&&Saved&&Saved->IsValid()){S.MindProfiles.Add(Id,*Saved);OKStreetApplyHerExtras(S,Id);}}}
 const FString Path=RosterLiveDir()/TEXT("heroine-settings.json");
 TSharedPtr<FJsonObject> All=OKStreetRosterReadJson(Path);if(!All)All=MakeShared<FJsonObject>();
 TSharedPtr<FJsonObject> Mine=MakeShared<FJsonObject>();{const TSharedPtr<FJsonObject>* Old=nullptr;if(All->TryGetObjectField(Id,Old)&&Old&&Old->IsValid())Mine=*Old;}
 const FString Base=S.RosterBaseNames.FindRef(Id),Name=S.RosterName.TrimStartAndEnd();
 if(Name.IsEmpty()||Name==Base)Mine->RemoveField(TEXT("name"));else Mine->SetStringField(TEXT("name"),Name);
 if(S.RosterPersona!=S.RosterPersonaLoaded){if(S.RosterPersona.TrimStartAndEnd().IsEmpty())Mine->RemoveField(TEXT("persona"));else Mine->SetStringField(TEXT("persona"),S.RosterPersona);}
 if(Mine->Values.IsEmpty())All->RemoveField(Id);else All->SetObjectField(Id,Mine);
 if(!OKStreetRosterWriteJson(Path,All.ToSharedRef())){S.RosterNotice=OKT(TEXT("ui.roster.write_failed"));RosterRebuild();return;}
 ApplyHeroineSettings();S.RosterPersonaLoaded=S.RosterPersona;
 UE_LOG(LogTemp,Display,TEXT("Street roster: settings of %s saved in this save"),*Id);
 S.RosterNotice=OKT(TEXT("ui.roster.settings_saved"));RefreshUI();RosterRebuild();
}

// Her memories as edited: "[id importance ...] text" keeps that memory with the new text and importance, a line without
// the bracket is a new memory, a memory whose line is gone is forgotten.
void AOKStreetSocialScene::RosterSaveMemory(){
 auto& S=*State;const int32 Her=S.RosterEdit;if(!S.Manifest.Characters.IsValidIndex(Her)||Her<1||!S.Mind)return;
 TArray<FString> Lines;S.RosterMemory.ParseIntoArrayLines(Lines);TArray<TSharedPtr<FJsonValue>> Records;
 for(FString Line:Lines){Line.TrimStartAndEndInline();if(Line.IsEmpty())continue;
  auto R=MakeShared<FJsonObject>();double Importance=.5;FString Id,Text=Line;int32 Close=INDEX_NONE;
  if(Line.StartsWith(TEXT("["))&&Line.FindChar(TEXT(']'),Close)){TArray<FString> Head;Line.Mid(1,Close-1).ParseIntoArrayWS(Head);Text=Line.Mid(Close+1).TrimStartAndEnd();
   if(Head.Num()>0)Id=Head[0];if(Head.Num()>1&&FCString::IsNumeric(*Head[1]))Importance=FCString::Atod(*Head[1]);}
  R->SetStringField(TEXT("id"),Id);R->SetStringField(TEXT("summary"),Text);R->SetNumberField(TEXT("importance"),Importance);Records.Add(MakeShared<FJsonValueObject>(R));}
 auto Q=MakeShared<FJsonObject>();Q->SetStringField(TEXT("kind"),TEXT("set_memories"));Q->SetStringField(TEXT("heroine"),OKStreetStableId(S.Manifest.Characters[Her]));
 Q->SetArrayField(TEXT("memories"),Records);Q->SetNumberField(TEXT("now"),double(OKStreetMindNow(S)));
 FString Out,Error;if(!S.Mind->Query(OKStreetMindJson(Q),Out,Error)){S.RosterNotice=OKMsg(TEXT("ui.roster.save_failed"),{{TEXT("error"),Error}});RosterRebuild();return;}
 FString SaveError;S.Mind->Save(SaveError);
 UE_LOG(LogTemp,Display,TEXT("Street roster: memories of heroine %d saved (%s)"),Her,*Out);
 RosterEditHer(Her,TEXT("memory"));S.RosterNotice=OKT(TEXT("ui.roster.memory_saved"));RosterRebuild();
}

// Her conversation context dropped: her next words start from her persona, profile and memories as they are now.
void AOKStreetSocialScene::RosterForgetContext(){
 auto& S=*State;const int32 Her=S.RosterEdit;if(!S.Manifest.Characters.IsValidIndex(Her)||Her<1||!S.Mind)return;
 auto Q=MakeShared<FJsonObject>();Q->SetStringField(TEXT("kind"),TEXT("forget_context"));Q->SetStringField(TEXT("heroine"),OKStreetStableId(S.Manifest.Characters[Her]));
 FString Out,Error;S.RosterNotice=S.Mind->Query(OKStreetMindJson(Q),Out,Error)?OKT(TEXT("ui.roster.context_forgotten")):OKMsg(TEXT("ui.roster.save_failed"),{{TEXT("error"),Error}});
 RosterRebuild();
}

// Only roster actions rebuild the panel (not RefreshUI), so what is being typed is not thrown away by other updates.
void AOKStreetSocialScene::RosterRebuild(){
 auto& S=*State;if(!S.UiRosterHolder)return;
 S.UiRosterHolder->SetContent(S.RosterOpen?BuildRosterPanel():SNullWidget::NullWidget);
}

TSharedRef<SWidget> AOKStreetSocialScene::BuildRosterPanel(){
 auto& S=*State;auto Weak=TWeakObjectPtr<AOKStreetSocialScene>(this);
 const FLinearColor Soft(.85f,.88f,.92f),Dim(.68f,.72f,.78f),Note(.65f,.85f,1.f);
 auto Button=[Weak](const FString& Text,TFunction<void(AOKStreetSocialScene&)> Do,bool Enabled=true){return SNew(SButton).ButtonStyle(OKStreetGlassButton()).IsEnabled(Enabled).HAlign(HAlign_Center)
  .Text(FText::FromString(Text)).OnClicked_Lambda([Weak,Do](){if(Weak.IsValid())Do(*Weak);return FReply::Handled();});};
 auto Label=[](const FString& Text,FLinearColor Color,int32 Size=14){return SNew(STextBlock).Text(FText::FromString(Text)).ColorAndOpacity(Color).AutoWrapText(true).Font(FCoreStyle::GetDefaultFontStyle("Regular",Size));};
 auto Picked=[&S](const FString& Path){return S.RosterPicked.ContainsByPredicate([&](const FString& P){return OKStreetRosterKey(P)==OKStreetRosterKey(Path);});};
 TSet<FString> World;for(const FString& P:S.RosterWorld)World.Add(OKStreetRosterKey(P));
 bool Changed=S.RosterPicked.Num()!=S.RosterWorld.Num();for(const FString& P:S.RosterPicked)Changed|=!World.Contains(OKStreetRosterKey(P));

 auto Left=SNew(SVerticalBox);
 Left->AddSlot().AutoHeight().Padding(4)[SNew(SHorizontalBox)
  +SHorizontalBox::Slot().FillWidth(1).VAlign(VAlign_Center)[SNew(STextBlock).Font(FCoreStyle::GetDefaultFontStyle("Bold",22)).ColorAndOpacity(FLinearColor::White).Text(FText::FromString(OKT(TEXT("ui.roster.title"))))]
  +SHorizontalBox::Slot().AutoWidth()[Button(OKT(TEXT("ui.scene.close_button")),[](AOKStreetSocialScene& A){A.CloseRoster();})]];
 Left->AddSlot().AutoHeight().Padding(4,2)[Label(OKMsg(TEXT("ui.roster.how"),{{TEXT("dir"),OKStreetRosterDir()}}),Dim,12)];
 if(!S.RosterNotice.IsEmpty())Left->AddSlot().AutoHeight().Padding(4,4)[Label(S.RosterNotice,Note,13)];
 Left->AddSlot().AutoHeight().Padding(2)[SNew(SHorizontalBox)
  +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.rescan")),[](AOKStreetSocialScene& A){A.RosterRun(TEXT("scan"),{});},!S.RosterBusy)]
  +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.open_folder")),[](AOKStreetSocialScene&){IFileManager::Get().MakeDirectory(*OKStreetRosterDir(),true);FPlatformProcess::ExploreFolder(*OKStreetRosterDir());})]
  +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKMsg(TEXT("ui.roster.apply"),{{TEXT("count"),S.RosterPicked.Num()},{TEXT("max"),OKStreetFemaleCount}}),[](AOKStreetSocialScene& A){A.RosterApply();},Changed&&S.RosterPicked.Num()>0&&!S.RosterBusy)]];
 // Every card in the folder, and the world's own heroines even when their card is somewhere else.
 TArray<TPair<FString,FString>> Rows;TSet<FString> Listed;
 for(const auto& C:S.RosterCards){const FString P=C->GetStringField(TEXT("path"));Rows.Add({P,C->GetStringField(TEXT("name"))});Listed.Add(OKStreetRosterKey(P));}
 for(int32 I=0;I<S.RosterWorld.Num();++I)if(!Listed.Contains(OKStreetRosterKey(S.RosterWorld[I]))&&S.Manifest.Characters.IsValidIndex(I+1))Rows.Insert({S.RosterWorld[I],S.Manifest.Characters[I+1].Name},0);
 auto List=SNew(SVerticalBox);
 for(const auto& Row:Rows){const FString Path=Row.Key;
  const int32 Her=S.RosterWorld.IndexOfByPredicate([&](const FString& P){return OKStreetRosterKey(P)==OKStreetRosterKey(Path);})+1; // 0: not in this world
  const FString Name=Her>0&&S.Manifest.Characters.IsValidIndex(Her)?S.Manifest.Characters[Her].Name:Row.Value;
  auto Line=SNew(SHorizontalBox);
  Line->AddSlot().FillWidth(1).VAlign(VAlign_Center).Padding(2)[SNew(SCheckBox).IsChecked(Picked(Path)?ECheckBoxState::Checked:ECheckBoxState::Unchecked)
   .OnCheckStateChanged_Lambda([Weak,Path](ECheckBoxState Value){if(!Weak.IsValid())return;auto& L=*Weak->State;
    L.RosterPicked.RemoveAll([&](const FString& P){return OKStreetRosterKey(P)==OKStreetRosterKey(Path);});
    if(Value==ECheckBoxState::Checked){if(L.RosterPicked.Num()>=OKStreetFemaleCount)L.RosterNotice=OKMsg(TEXT("ui.roster.too_many"),{{TEXT("max"),OKStreetFemaleCount}});else L.RosterPicked.Add(Path);}
    Weak->RosterRebuild();})
   [SNew(SVerticalBox)+SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).ColorAndOpacity(FLinearColor::White).Text(FText::FromString(Her>0?OKMsg(TEXT("ui.roster.in_world"),{{TEXT("name"),Name}}):Name))]
    +SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).ColorAndOpacity(Dim).Font(FCoreStyle::GetDefaultFontStyle("Regular",10)).Text(FText::FromString(FPaths::GetCleanFilename(Path)))]]];
  if(Her>0){
   Line->AddSlot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.settings")),[Her](AOKStreetSocialScene& A){A.RosterEditHer(Her,TEXT("settings"));})];
   Line->AddSlot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.memory")),[Her](AOKStreetSocialScene& A){A.RosterEditHer(Her,TEXT("memory"));})];}
  Line->AddSlot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.voice_wav")),[Her,Path](AOKStreetSocialScene& A){A.PickVoiceWav(Her,Path);},!S.RosterBusy)];
  List->AddSlot().AutoHeight().Padding(2)[Line];}
 if(Rows.IsEmpty())List->AddSlot().AutoHeight().Padding(4)[Label(OKT(TEXT("ui.roster.empty")),Dim)];
 Left->AddSlot().FillHeight(1).Padding(2,6)[SNew(SScrollBox)+SScrollBox::Slot()[List]];

 // The heroine being edited: the save's settings for her, or her memories.
 TSharedRef<SWidget> Right=SNullWidget::NullWidget;
 if(S.Manifest.Characters.IsValidIndex(S.RosterEdit)&&S.RosterEdit>0){
  const FString Name=S.Manifest.Characters[S.RosterEdit].Name;auto Box=SNew(SVerticalBox);
  Box->AddSlot().AutoHeight().Padding(4)[SNew(STextBlock).Font(FCoreStyle::GetDefaultFontStyle("Bold",18)).ColorAndOpacity(FLinearColor::White)
   .Text(FText::FromString(OKMsg(S.RosterTab==TEXT("memory")?TEXT("ui.roster.memory_of"):TEXT("ui.roster.settings_of"),{{TEXT("name"),Name}})))];
  Box->AddSlot().AutoHeight().Padding(4,0,4,4)[Label(OKT(S.RosterTab==TEXT("memory")?TEXT("ui.roster.memory_how"):TEXT("ui.roster.settings_how")),Dim,12)];
  auto Multi=[Weak](FString FOKStreetSceneState::* Field,const FString& Text){return SNew(SMultiLineEditableTextBox).Text(FText::FromString(Text)).AutoWrapText(true)
   .OnTextChanged_Lambda([Weak,Field](const FText& T){if(Weak.IsValid())(*Weak->State).*Field=T.ToString();});};
  if(S.RosterTab==TEXT("memory")){
   Box->AddSlot().FillHeight(1).Padding(4)[SNew(SScrollBox)+SScrollBox::Slot()[Multi(&FOKStreetSceneState::RosterMemory,S.RosterMemory)]];
   Box->AddSlot().AutoHeight().Padding(4)[SNew(SHorizontalBox)
    +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.save_reload")),[](AOKStreetSocialScene& A){A.RosterSaveMemory();})]
    +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.reload")),[](AOKStreetSocialScene& A){A.RosterEditHer(A.State->RosterEdit,TEXT("memory"));})]
    +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.forget_context")),[](AOKStreetSocialScene& A){A.RosterForgetContext();})]];
  }else{
   Box->AddSlot().AutoHeight().Padding(4,4,4,0)[Label(OKT(TEXT("ui.roster.name")),Soft,13)];
   Box->AddSlot().AutoHeight().Padding(4)[SNew(SEditableTextBox).Text(FText::FromString(S.RosterName)).OnTextChanged_Lambda([Weak](const FText& T){if(Weak.IsValid())Weak->State->RosterName=T.ToString();})];
   Box->AddSlot().AutoHeight().Padding(4,4,4,0)[Label(OKT(TEXT("ui.roster.persona")),Soft,13)];
   Box->AddSlot().AutoHeight().Padding(4)[SNew(SBox).MaxDesiredHeight(180)[SNew(SScrollBox)+SScrollBox::Slot()[Multi(&FOKStreetSceneState::RosterPersona,S.RosterPersona)]]];
   Box->AddSlot().AutoHeight().Padding(4,4,4,0)[Label(OKT(TEXT("ui.roster.profile")),Soft,13)];
   Box->AddSlot().FillHeight(1).Padding(4)[SNew(SScrollBox)+SScrollBox::Slot()[Multi(&FOKStreetSceneState::RosterProfile,S.RosterProfile)]];
   Box->AddSlot().AutoHeight().Padding(4)[SNew(SHorizontalBox)
    +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.save_reload")),[](AOKStreetSocialScene& A){A.RosterSaveSettings();})]
    +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.reload")),[](AOKStreetSocialScene& A){A.RosterEditHer(A.State->RosterEdit,TEXT("settings"));})]
    +SHorizontalBox::Slot().AutoWidth().Padding(2)[Button(OKT(TEXT("ui.roster.forget_context")),[](AOKStreetSocialScene& A){A.RosterForgetContext();})]];
  }
  Right=SNew(SBox).WidthOverride(640)[Box];
 }
 return SNew(SOverlay)
  +SOverlay::Slot()[SNew(SBorder).BorderImage(FCoreStyle::Get().GetBrush("WhiteBrush")).BorderBackgroundColor(FLinearColor(0,0,0,.45f))]
  +SOverlay::Slot().HAlign(HAlign_Center).VAlign(VAlign_Fill).Padding(24,40)[SNew(SBox)[SNew(SBorder).BorderImage(OKStreetGlassPanel()).Padding(16)[SNew(SHorizontalBox)
   +SHorizontalBox::Slot().AutoWidth()[SNew(SBox).WidthOverride(520)[Left]]
   +SHorizontalBox::Slot().AutoWidth().Padding(12,0,0,0)[Right]]]];
}
