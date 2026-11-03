// Included by OKStreetSocialScene.cpp: bookmarks and the time after an H scene (Docs/H_SCENE_ADDITIONS_PLAN.md 12, 13).
// A bookmark is filed by the rules (bookmarks.rs: when, where, her state, the last 50 lines, her memory of it); here the
// thumbnail is taken, the lines gathered and the phone page drawn. After the scene they stay together and talk; the
// result is shown once he leaves.

// Where the thumbnails are: beside the save, in Bookmarks/ (the save keeps only the file name).
static FString OKStreetBookmarkDir(const FOKStreetSceneState& S){
 return (S.Manifest.SavePath.IsEmpty()?FPaths::ProjectSavedDir()/TEXT("StreetSocial"):FPaths::GetPath(S.Manifest.SavePath))/TEXT("Bookmarks");
}

void AOKStreetSocialScene::Bookmark(int32 Girl){
 auto& S=*State;if(Girl<=0||!S.Manifest.Characters.IsValidIndex(Girl))return;
 const FString Id=OKStreetStableId(S.Manifest.Characters[Girl]);
 // The view as it is, without the panels; the record names the file now, the picture lands a frame later.
 FString Thumb;
 if(!FScreenshotRequest::IsScreenshotRequested()){const FString Dir=OKStreetBookmarkDir(S);IFileManager::Get().MakeDirectory(*Dir,true);
  Thumb=TEXT("Mark-")+FDateTime::UtcNow().ToString(TEXT("%Y%m%d-%H%M%S"))+TEXT("-")+FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT(".png");
  FScreenshotRequest::RequestScreenshot(Dir/Thumb,false,false);}
 // The last 50 lines between them, both sides (face to face and on the phone).
 TArray<TSharedPtr<FJsonValue>> Lines;const auto& List=HistoryOf(Id);
 for(int32 K=List.Num()-1;K>=0&&Lines.Num()<50;--K){const auto& E=List[K];if((E.Who!=TEXT("him")&&E.Who!=TEXT("her"))||E.Kind==TEXT("photo")||E.Text.IsEmpty())continue;
  auto L=MakeShared<FJsonObject>();L->SetStringField(TEXT("who"),E.Who);L->SetStringField(TEXT("text"),E.Text);Lines.Insert(MakeShared<FJsonValueObject>(L),0);}
 const FString PlaceId=PlaceHere(S.Male);const auto* Where=PlaceId.IsEmpty()?nullptr:OKStreetFindPlace(PlaceId);
 auto Request=OKRulesHeroineRequest(S,TEXT("bookmark_add"),Id);OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),Id);
 Request->SetNumberField(TEXT("day"),S.Store.CalendarDay);Request->SetNumberField(TEXT("minute"),double(OKStreetMindNow(S)%1440));
 Request->SetStringField(TEXT("place"),Where?FString(Where->Name):FString());Request->SetArrayField(TEXT("lines"),Lines);Request->SetStringField(TEXT("thumb"),Thumb);
 const TSharedPtr<FJsonObject> Out=OKRulesEval(S,Request);if(!Out.IsValid())return;
 auto Candidate=S.Store;OKRulesTakeExt(Candidate,*Out);if(!CommitStore(MoveTemp(Candidate)))return;
 MindObserve(Girl,TEXT("bookmark"),Out->GetStringField(TEXT("memory")),PlaceId,0.7f);
 S.FreeTalkNotice=S.ContactsNotice=OKMsg(TEXT("ui.bookmarks.saved"),{{TEXT("title"),Out->GetStringField(TEXT("title"))}});RefreshUI();
 UE_LOG(LogTemp,Display,TEXT("Street bookmark: actor=%d #%d %s, %d lines, thumb %s"),Girl,int32(Out->GetNumberField(TEXT("id"))),*Out->GetStringField(TEXT("title")),Lines.Num(),*Thumb);
}

// For her words: the last five, and the lines of the one he asks about (bookmarks_facts).
FString AOKStreetSocialScene::BookmarkFacts(int32 Character,const FString& Said) const{
 const auto& S=*State;if(Character<=0||!S.Manifest.Characters.IsValidIndex(Character))return FString();
 auto Request=OKRulesRequest(TEXT("bookmarks_facts"));OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),OKStreetStableId(S.Manifest.Characters[Character]));Request->SetStringField(TEXT("said"),Said);
 const TSharedPtr<FJsonObject> Out=OKRulesEval(S,Request);return Out.IsValid()?Out->GetStringField(TEXT("text")):FString();
}

// The phone's bookmarks page for her thread: newest first with the thumbnail; one opened shows its lines.
TSharedRef<SWidget> AOKStreetSocialScene::BuildBookmarks(int32 Girl){
 auto& S=*State;TWeakObjectPtr<AOKStreetSocialScene> Weak(this);
 auto Request=OKRulesRequest(TEXT("bookmarks_view"));OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),OKStreetStableId(S.Manifest.Characters[Girl]));
 auto Rows=SNew(SVerticalBox);int32 Shown=0;const FString Dir=OKStreetBookmarkDir(S);
 if(const TSharedPtr<FJsonObject> Out=OKRulesEval(S,Request))for(const auto& V:Out->GetArrayField(TEXT("bookmarks"))){const auto O=V->AsObject();if(!O)continue;++Shown;
  const int32 Mark=int32(O->GetNumberField(TEXT("id")));const bool Open=S.BookmarkOpen==Mark;const FString Thumb=O->GetStringField(TEXT("thumb"));
  auto Body=SNew(SVerticalBox);
  Body->AddSlot().AutoHeight()[OKFinButton(Weak,O->GetStringField(TEXT("title")),[Weak,Mark,Open](){Weak->State->BookmarkOpen=Open?INDEX_NONE:Mark;Weak->RefreshUI();},true,Open?FLinearColor(1,.85f,.3f):FLinearColor::White)];
  Body->AddSlot().AutoHeight().Padding(0,2)[OKFinText(O->GetStringField(TEXT("state")),FLinearColor(.75f,.75f,.82f),9,false,true)];
  Body->AddSlot().AutoHeight().Padding(0,2)[OKFinText(O->GetStringField(TEXT("summary")),OKStreetSpeakerColor(Girl),11,false,true)];
  if(Open)for(const auto& L:O->GetArrayField(TEXT("lines"))){const auto Line=L->AsObject();if(!Line)continue;const bool Him=Line->GetStringField(TEXT("who"))==TEXT("him");
   Body->AddSlot().AutoHeight().Padding(Him?FMargin(60,2,0,2):FMargin(0,2,60,2))[OKFinText((Him?OKStreetScriptedName(S.Manifest.Characters[0].Name):OKStreetScriptedName(S.Manifest.Characters[Girl].Name))+OKT(TEXT("ui.economy.colon_mark"))+Line->GetStringField(TEXT("text")),Him?OKStreetPlayerLineColor():OKStreetSpeakerColor(Girl),11,false,true)];}
  Rows->AddSlot().AutoHeight().Padding(4)[SNew(SBorder).BorderImage(OKFinSolid()).BorderBackgroundColor(FLinearColor(.22f,.2f,.28f)).Padding(6)[SNew(SHorizontalBox)
   +SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Top).Padding(0,0,8,0)[SNew(SBox).WidthOverride(160).HeightOverride(90)[Thumb.IsEmpty()?SNullWidget::NullWidget:StaticCastSharedRef<SWidget>(SNew(SImage).Image(OKStreetPhotoBrush(Dir/Thumb)))]]
   +SHorizontalBox::Slot().FillWidth(1)[Body]]];}
 if(Shown==0)Rows->AddSlot().AutoHeight().Padding(6)[OKFinText(OKT(TEXT("ui.bookmarks.empty")),FLinearColor(.7f,.7f,.7f),11)];
 return Rows;
}

// Glass buttons over the scene, top right: the bookmark beside the scene's leave (in the H scene) or the after-time's.
TSharedRef<SWidget> AOKStreetSocialScene::BookmarkButton(int32 Girl){
 return SNew(SButton).ButtonStyle(OKStreetGlassButton()).ContentPadding(FMargin(18,8)).Text(FText::FromString(OKT(TEXT("ui.bookmarks.button"))))
  .OnClicked_Lambda([Weak=TWeakObjectPtr<AOKStreetSocialScene>(this),Girl](){if(Weak.IsValid())Weak->Bookmark(Girl);return FReply::Handled();});
}

// After the scene: they stay where they are and talk (her words know it is just after); "leave" shows the result.
void AOKStreetSocialScene::BeginAfter(int32 Girl,const TSharedPtr<FJsonObject>& Answer){
 auto& S=*State;EndAfter(false);if(!GEngine||!GEngine->GameViewport)return;
 S.AfterGirl=Girl;S.AfterAnswer=Answer;
 // Top middle: the street's panel is back on the right (its hour buttons sit where the scene's leave was).
 S.AfterBar=SNew(SBox).HAlign(HAlign_Center).VAlign(VAlign_Top).Padding(FMargin(0,16,0,0))
  [SNew(SHorizontalBox)
   +SHorizontalBox::Slot().AutoWidth().Padding(0,0,8,0)[BookmarkButton(Girl)]
   +SHorizontalBox::Slot().AutoWidth()[SNew(SButton).ButtonStyle(OKStreetGlassButton()).ContentPadding(FMargin(18,8)).Text(FText::FromString(OKT(TEXT("ui.bookmarks.leave_after"))))
    .OnClicked_Lambda([Weak=TWeakObjectPtr<AOKStreetSocialScene>(this)](){if(Weak.IsValid())Weak->EndAfter(true);return FReply::Handled();})]];
 GEngine->GameViewport->AddViewportWidgetContent(S.AfterBar.ToSharedRef(),20);
 UE_LOG(LogTemp,Display,TEXT("Street private: after-time with actor=%d"),Girl);
}

void AOKStreetSocialScene::EndAfter(bool bShowResult){
 if(!State||State->AfterGirl==INDEX_NONE)return;auto& S=*State;
 const int32 Girl=S.AfterGirl;const TSharedPtr<FJsonObject> Answer=S.AfterAnswer;S.AfterGirl=INDEX_NONE;S.AfterAnswer.Reset();
 if(S.AfterBar.IsValid()){if(GEngine&&GEngine->GameViewport)GEngine->GameViewport->RemoveViewportWidgetContent(S.AfterBar.ToSharedRef());S.AfterBar.Reset();}
 UE_LOG(LogTemp,Display,TEXT("Street private: after-time with actor=%d ended (result %d)"),Girl,bShowResult&&Answer.IsValid()?1:0);
 if(bShowResult&&Answer.IsValid())ShowHResult(Girl,*Answer);
}

// The after-time ends by itself when the talk with her does (she walked off, he turned to someone else).
void AOKStreetSocialScene::TickAfter(){
 auto& S=*State;if(S.AfterGirl==INDEX_NONE)return;
 if(!S.Agents.IsValidIndex(S.AfterGirl-1)||FVector::Dist2D(S.Agents[S.AfterGirl-1].Position,S.Male)>600.f||(S.Target!=INDEX_NONE&&S.Target!=S.AfterGirl))EndAfter(true);
}
