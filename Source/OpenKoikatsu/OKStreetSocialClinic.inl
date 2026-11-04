// The gynaecology clinic, the cosmetic clinic and the hair salon (user 2026-11-03; ok-rules clinic.rs). Each treatment is
// for the girl with him: he offers it at the counter, she says yes or no in her own words (a choice, as a gift), and
// only then does he pay and is it done. What she had done is kept in the save's ext (her hexp for the hymen,
// ext.appearance for her face and hair). Her face and hair are a copy of her card made by the Rust restyle
// (ok-extract appearance.rs): the one-on-one opens her from it at once, the street crowd from the next start of the game.
#include "KKRustExtract.h"
#include "Misc/SecureHash.h"

namespace OKStreetClinic {
// The rules' treatment for a catalogue item of the clinics and the salon.
inline const TCHAR* KindOf(const FString& ItemId){
 return ItemId==TEXT("gyn_hymen_repair")?TEXT("hymen_restore"):ItemId==TEXT("beauty_face_swap")?TEXT("face_swap"):ItemId==TEXT("beauty_face_restore")?TEXT("face_restore"):ItemId==TEXT("salon_dye")?TEXT("hair_dye"):nullptr;
}
inline FString Dir(){return FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir())/TEXT("StreetSocial/Appearance");} // full: the crowd resolves relative paths against the project
}

TSharedPtr<FJsonObject> AOKStreetSocialScene::ClinicRequest(int32 Her,const FString& ItemId,const FString& From,const FString& Color){
 auto& S=*State;const TCHAR* Kind=OKStreetClinic::KindOf(ItemId);if(!Kind||!S.Manifest.Characters.IsValidIndex(Her))return nullptr;
 const FString Girl=OKStreetStableId(S.Manifest.Characters[Her]);
 auto Request=OKRulesHeroineRequest(S,TEXT("clinic_treat"),Girl);OKRulesPutExt(S,Request);
 Request->SetStringField(TEXT("kind"),Kind);Request->SetStringField(TEXT("girl"),Girl);Request->SetStringField(TEXT("girl_name"),S.Manifest.Characters[Her].Name);
 Request->SetNumberField(TEXT("day"),S.Store.CalendarDay);Request->SetStringField(TEXT("place"),S.ShopPlace);
 if(!From.IsEmpty()){Request->SetStringField(TEXT("from"),From);
  for(const auto& C:S.Manifest.Characters)if(OKStreetStableId(C)==From)Request->SetStringField(TEXT("from_name"),C.Name);}
 if(!Color.IsEmpty())Request->SetStringField(TEXT("color"),Color);
 return OKRulesEval(S,Request);
}

void AOKStreetSocialScene::OfferClinic(int32 Her,const FString& ItemId,const FString& From,const FString& Color){
 auto& S=*State;const auto* Item=S.Catalog.Find(ItemId);if(!Item||Her==INDEX_NONE)return;
 // Asked first with nothing changed: what cannot be done (she is still a virgin, that is her face already) is said now.
 const TSharedPtr<FJsonObject> Try=ClinicRequest(Her,ItemId,From,Color);if(!Try)return;
 if(!Try->GetBoolField(TEXT("ok"))){S.FreeTalkNotice=Try->GetStringField(TEXT("fact"));RefreshUI();return;}
 FString What=Item->Name;
 if(!From.IsEmpty())for(const auto& C:S.Manifest.Characters)if(OKStreetStableId(C)==From)What=OKMsg(TEXT("ui.clinic.face_of"),{{TEXT("name"),C.Name}});
 if(!Color.IsEmpty())if(const TSharedPtr<FJsonObject> Chart=OKRulesEval(S,OKRulesRequest(TEXT("hair_colors")))){const TArray<TSharedPtr<FJsonValue>>* Colors=nullptr;
  if(Chart->TryGetArrayField(TEXT("colors"),Colors))for(const auto& V:*Colors)if(V->AsObject()->GetStringField(TEXT("id"))==Color)What=OKMsg(TEXT("ui.clinic.dye_to"),{{TEXT("color"),V->AsObject()->GetStringField(TEXT("name"))}});}
 const FString Label=OKMsg(TEXT("ui.clinic.offer_label"),{{TEXT("what"),What},{TEXT("price"),Money(Item->PriceOf(Item->DefaultSize()))}});
 if(S.Choices.ContainsByPredicate([&](const FOKStreetPendingChoice& C){return C.Kind==TEXT("clinic")&&C.Heroine==Her;})){S.FreeTalkNotice=OKT(TEXT("ui.clinic.already_asked"));RefreshUI();return;}
 TWeakObjectPtr<AOKStreetSocialScene> Weak(this);
 // Her own answer decides (no lean: whether she wants her body or face changed is hers to say).
 OpenChoice(Her,TEXT("clinic"),Label,{TEXT("accept"),TEXT("decline")},FString(),0.f,25,[Weak,Her,ItemId,From,Color](const FString& Option){if(Weak.IsValid())Weak->FinishClinic(Her,ItemId,Option,From,Color);});
 S.FreeTalkNotice=OKMsg(TEXT("ui.clinic.asked_her"),{{TEXT("what"),What}});
 RefreshUI();
}

void AOKStreetSocialScene::FinishClinic(int32 Her,const FString& ItemId,const FString& Option,const FString& From,const FString& Color){
 auto& S=*State;const auto* Item=S.Catalog.Find(ItemId);if(!Item||!S.Manifest.Characters.IsValidIndex(Her))return;
 if(Option!=TEXT("accept")){UE_LOG(LogTemp,Display,TEXT("Street clinic: actor %d declined %s"),Her,*ItemId);S.FreeTalkNotice=OKT(TEXT("ui.clinic.she_declined"));RefreshUI();return;}
 const TSharedPtr<FJsonObject> Answer=ClinicRequest(Her,ItemId,From,Color);if(!Answer)return;
 if(!Answer->GetBoolField(TEXT("ok"))){S.FreeTalkNotice=Answer->GetStringField(TEXT("fact"));RefreshUI();return;}
 const int32 Price=Item->PriceOf(Item->DefaultSize());auto Candidate=S.Store;
 const FString Why=OKT(TEXT("ui.bank.buy_label"))+Item->Name;
 if(Candidate.PlayerCash>=Price)OKCash(Candidate,-Price,TEXT("shopping"),Why);
 else if(!PayByCard(Candidate,Price,S.ShopPlace,Why)){S.FreeTalkNotice=OKT(TEXT("ui.economy.not_enough_money"));RefreshUI();return;}
 OKRulesTakeExt(Candidate,*Answer);ApplyRulesEffects(Candidate,*Answer);
 if(!CommitStore(MoveTemp(Candidate)))return;
 FlushRulesEffects();
 S.TellHer.Add(OKMsg(TEXT("ui.scene.game_fact_note"),{{TEXT("fact"),Answer->GetStringField(TEXT("fact"))}}));
 UE_LOG(LogTemp,Display,TEXT("Street clinic: actor %d had %s (from=%s color=%s), paid %d"),Her,*ItemId,*From,*Color,Price);
 FString Notice=OKMsg(TEXT("ui.clinic.done_line"),{{TEXT("name"),S.Manifest.Characters[Her].Name},{TEXT("item_name"),Item->Name},{TEXT("price"),Price}});
 // Her face and hair: a new copy of her card for the one-on-one now; the street shows it from the next start.
 if(ItemId!=TEXT("gyn_hymen_repair")){FString Error;const FString Card=RestyledCard(Her,Error);
  if(Card.IsEmpty()){UE_LOG(LogTemp,Warning,TEXT("Street clinic: actor %d card not restyled: %s"),Her,*Error);}
  else{if(S.HighCards.IsValidIndex(Her))S.HighCards[Her]=Card;Notice+=OKT(TEXT("ui.clinic.street_next_start"));}}
 S.FreeTalkNotice=Notice;
 RefreshUI();
}

// Her card as she looks now (ext.appearance, ext.wardrobe): her own card, or a copy with someone's face shape, her dyed
// hair and/or the clothes she has on (with Trying, that piece too), made once for each look and kept in
// Saved/StreetSocial/Appearance. Empty (with Error) when it could not be made.
FString AOKStreetSocialScene::RestyledCard(int32 Her,FString& Error,const FOKStreetCatalogItem* Trying){
 auto& S=*State;if(!S.BaseCards.IsValidIndex(Her)||!S.Manifest.Characters.IsValidIndex(Her)){Error=TEXT("no card");return FString();}
 const FString Own=S.BaseCards[Her],Girl=OKStreetStableId(S.Manifest.Characters[Her]);
 auto Request=OKRulesRequest(TEXT("appearance_of"));OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),Girl);
 const TSharedPtr<FJsonObject> Look=OKRulesEval(S,Request);if(!Look){Error=TEXT("appearance_of failed");return FString();}
 const FString FaceFrom=Look->GetStringField(TEXT("face_from")),Hair=Look->GetStringField(TEXT("hair_rgb"));
 TArray<TSharedPtr<FJsonValue>> Dress;if(const TSharedPtr<FJsonObject> Has=WardrobeOf(Her,Trying)){const TArray<TSharedPtr<FJsonValue>>* List=nullptr;if(Has->TryGetArrayField(TEXT("dress"),List))Dress=*List;}
 if(FaceFrom.IsEmpty()&&Hair.IsEmpty()&&Dress.IsEmpty())return Own;
 const int32 Outfit=S.HighOutfits.IsValidIndex(Her)?S.HighOutfits[Her]:0;FString DressKey;{auto W=TJsonWriterFactory<>::Create(&DressKey);FJsonSerializer::Serialize(Dress,W);}
 FString Donor;
 if(!FaceFrom.IsEmpty())for(int32 I=0;I<S.Manifest.Characters.Num();++I)if(OKStreetStableId(S.Manifest.Characters[I])==FaceFrom&&S.BaseCards.IsValidIndex(I))Donor=S.BaseCards[I];
 if(!FaceFrom.IsEmpty()&&Donor.IsEmpty()){Error=TEXT("whose face she has is not in this street: ")+FaceFrom;return FString();}
 // One file for each look of hers: the same look again reuses it (and the crowd's disk cache keyed by the card).
 const FString Key=FMD5::HashAnsiString(*FString::Printf(TEXT("%s|%s|%s|%d|%s"),*Own,*Donor,*Hair,Outfit,*DressKey)).Left(12);
 const FString Out=OKStreetClinic::Dir()/FString::Printf(TEXT("%s-%s.png"),*Girl.Right(16),*Key);
 if(IFileManager::Get().FileExists(*Out))return Out;
 auto Json=MakeShared<FJsonObject>();Json->SetStringField(TEXT("action"),TEXT("restyle"));Json->SetStringField(TEXT("card"),Own);Json->SetStringField(TEXT("output"),Out);
 Json->SetStringField(TEXT("donor"),Donor);Json->SetStringField(TEXT("hair_rgb"),Hair);Json->SetArrayField(TEXT("dress"),Dress);Json->SetNumberField(TEXT("outfit"),Outfit);
 FString Body;{auto W=TJsonWriterFactory<>::Create(&Body);FJsonSerializer::Serialize(Json,W);}
 const FString RequestPath=OKStreetClinic::Dir()/TEXT("restyle.request.json"),Report=OKStreetClinic::Dir()/TEXT("restyle.report.json");
 IFileManager::Get().MakeDirectory(*OKStreetClinic::Dir(),true);
 if(!FFileHelper::SaveStringToFile(Body,*RequestPath,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)){Error=TEXT("cannot write the restyle request");return FString();}
 if(!FOkSession::AppearanceRequest(FString(),RequestPath,Report,Error)||!IFileManager::Get().FileExists(*Out))return FString();
 UE_LOG(LogTemp,Display,TEXT("Street clinic: %s restyled to %s (face of %s, hair %s)"),*Girl,*Out,*FaceFrom,*Hair);
 return Out;
}

// At the start, before the crowd loads: each girl with a changed face or hair is loaded from her restyled card (the
// selection's cards list, written again next to it). Returns the selection the crowd should read.
FString AOKStreetSocialScene::ApplyAppearanceToSelection(const FString& ManifestPath,const FString& Json){
 auto& S=*State;S.BaseCards=S.HighCards;
 TSharedPtr<FJsonObject> Root;if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Root)||!Root)return ManifestPath;
 const TArray<TSharedPtr<FJsonValue>>* Cards=nullptr;if(!Root->TryGetArrayField(TEXT("cards"),Cards))return ManifestPath;
 TArray<TSharedPtr<FJsonValue>> Now=*Cards;bool Changed=false;
 for(int32 I=1;I<Now.Num()&&I<S.HighCards.Num();++I){FString Error;const FString Card=RestyledCard(I,Error);
  if(Card.IsEmpty()){UE_LOG(LogTemp,Warning,TEXT("Street clinic: actor %d keeps her own card: %s"),I,*Error);continue;}
  if(Card==S.BaseCards[I])continue;
  Now[I]=MakeShared<FJsonValueString>(Card);S.HighCards[I]=Card;Changed=true;}
 if(!Changed)return ManifestPath;
 Root->SetArrayField(TEXT("cards"),Now);FString Body;{auto W=TJsonWriterFactory<>::Create(&Body);FJsonSerializer::Serialize(Root.ToSharedRef(),W);}
 const FString Out=FPaths::GetPath(ManifestPath)/(FPaths::GetBaseFilename(ManifestPath)+TEXT(".appearance.json"));
 if(!FFileHelper::SaveStringToFile(Body,*Out,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)){UE_LOG(LogTemp,Warning,TEXT("Street clinic: cannot write %s"),*Out);return ManifestPath;}
 UE_LOG(LogTemp,Display,TEXT("Street clinic: the crowd loads the restyled cards from %s"),*Out);
 return Out;
}

// The clinic and salon rows of the menu: the treatment for her, whose face, which colour.
void AOKStreetSocialScene::AddClinicRows(const TSharedRef<SVerticalBox>& List,const FOKStreetCatalogItem& Item,int32 Her){
 auto& S=*State;TWeakObjectPtr<AOKStreetSocialScene> Weak(this);const FString Id=Item.Id;
 const FLinearColor Ink(.24f,.14f,.07f);
 auto Button=[&Weak](const FString& Text,TFunction<void()> Do){return SNew(SButton).ButtonStyle(OKStreetGlassButton()).ContentPadding(FMargin(8,2)).Text(FText::FromString(Text)).OnClicked_Lambda([Weak,Do](){if(Weak.IsValid())Do();return FReply::Handled();});};
 if(Her==INDEX_NONE){List->AddSlot().AutoHeight().Padding(12,0,0,4)[SNew(STextBlock).Font(FCoreStyle::GetDefaultFontStyle("Italic",13)).ColorAndOpacity(Ink.CopyWithNewOpacity(.7f)).Text(FText::FromString(OKT(TEXT("ui.clinic.needs_her"))))];return;}
 auto Wrap=SNew(SWrapBox).UseAllottedSize(true);
 auto Add=[&](const FString& Text,TFunction<void()> Do){Wrap->AddSlot().Padding(2)[Button(Text,MoveTemp(Do))];};
 if(Id==TEXT("beauty_face_swap")){
  // Whose face: the other heroines of this street (his own is not on offer).
  for(int32 I=1;I<S.Manifest.Characters.Num();++I)if(I!=Her&&OKStreetIsFemaleTarget(I,S.Manifest.Characters[I])){const FString From=OKStreetStableId(S.Manifest.Characters[I]);
   Add(OKMsg(TEXT("ui.clinic.face_of"),{{TEXT("name"),S.Manifest.Characters[I].Name}}),[Weak,Her,Id,From](){Weak->OfferClinic(Her,Id,From,FString());});}
 }else if(Id==TEXT("salon_dye")){
  if(const TSharedPtr<FJsonObject> Chart=OKRulesEval(S,OKRulesRequest(TEXT("hair_colors")))){const TArray<TSharedPtr<FJsonValue>>* Colors=nullptr;
   if(Chart->TryGetArrayField(TEXT("colors"),Colors))for(const auto& V:*Colors){const FString Color=V->AsObject()->GetStringField(TEXT("id"));
    Add(V->AsObject()->GetStringField(TEXT("name")),[Weak,Her,Id,Color](){Weak->OfferClinic(Her,Id,FString(),Color);});}}
 }else Add(OKMsg(TEXT("ui.clinic.do_for_her"),{{TEXT("name"),S.Manifest.Characters[Her].Name}}),[Weak,Her,Id](){Weak->OfferClinic(Her,Id,FString(),FString());});
 List->AddSlot().AutoHeight().Padding(12,0,0,4)[Wrap];
}
