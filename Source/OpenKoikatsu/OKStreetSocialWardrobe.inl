// Her clothes (user 2026-11-04; ok-rules wardrobe.rs): the clothes shops' stock is the original game's clothes (catalog.json
// category "clothes", each with the card parts it sets). With her beside him he has her try a piece on (she changes and
// he sees her in it, nothing paid, nothing kept) or buys it for her (she says yes or no in her own words, as at the
// clinics), and she keeps what he bought and changes between it and her own clothes. What she wears is written into the
// same copy of her card as her face and hair (RestyledCard): the one-on-one shows it at once, the street crowd from the
// next start of the game.

namespace OKStreetWardrobe {
// What the rules keep of a piece: all they need, so they do not read the catalogue.
inline TSharedRef<FJsonObject> Piece(const FOKStreetCatalogItem& Item){
 auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("item"),Item.Id);P->SetStringField(TEXT("name"),Item.Name);
 TArray<TSharedPtr<FJsonValue>> Parts;
 for(int32 I=0;I+1<Item.ClothesParts.Num();I+=2)Parts.Add(MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(Item.ClothesParts[I]),MakeShared<FJsonValueNumber>(Item.ClothesParts[I+1])}));
 P->SetArrayField(TEXT("parts"),Parts);P->SetNumberField(TEXT("outfit"),Item.ClothesOutfit);P->SetStringField(TEXT("color"),Item.ClothesColor);
 return P;
}
}

// What she has now, and with Trying a piece over it (wardrobe_of).
TSharedPtr<FJsonObject> AOKStreetSocialScene::WardrobeOf(int32 Her,const FOKStreetCatalogItem* Trying){
 auto& S=*State;if(!S.Manifest.Characters.IsValidIndex(Her))return nullptr;
 auto Request=OKRulesRequest(TEXT("wardrobe_of"));OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),OKStreetStableId(S.Manifest.Characters[Her]));
 if(Trying)Request->SetObjectField(TEXT("trying"),OKStreetWardrobe::Piece(*Trying));
 return OKRulesEval(S,Request);
}

void AOKStreetSocialScene::OfferClothes(int32 Her,const FString& ItemId){
 auto& S=*State;const auto* Item=S.Catalog.Find(ItemId);if(!Item||Her==INDEX_NONE)return;
 if(S.Choices.ContainsByPredicate([&](const FOKStreetPendingChoice& C){return C.Kind==TEXT("clothes")&&C.Heroine==Her;})){S.FreeTalkNotice=OKT(TEXT("ui.clothes.already_asked"));RefreshUI();return;}
 const FString Label=OKMsg(TEXT("ui.clothes.offer_label"),{{TEXT("item"),Item->Name},{TEXT("price"),Money(Item->PriceOf(Item->DefaultSize()))}});
 TWeakObjectPtr<AOKStreetSocialScene> Weak(this);
 OpenChoice(Her,TEXT("clothes"),Label,{TEXT("accept"),TEXT("decline")},FString(),0.f,25,[Weak,Her,ItemId](const FString& Option){if(Weak.IsValid())Weak->FinishClothes(Her,ItemId,Option);});
 S.FreeTalkNotice=OKMsg(TEXT("ui.clothes.asked_her"),{{TEXT("item"),Item->Name}});
 RefreshUI();
}

void AOKStreetSocialScene::FinishClothes(int32 Her,const FString& ItemId,const FString& Option){
 auto& S=*State;const auto* Item=S.Catalog.Find(ItemId);if(!Item||!S.Manifest.Characters.IsValidIndex(Her))return;
 if(Option!=TEXT("accept")){UE_LOG(LogTemp,Display,TEXT("Street clothes: actor %d declined %s"),Her,*ItemId);S.FreeTalkNotice=OKT(TEXT("ui.clothes.she_declined"));RefreshUI();return;}
 const FString Girl=OKStreetStableId(S.Manifest.Characters[Her]);
 auto Request=OKRulesHeroineRequest(S,TEXT("clothes_buy"),Girl);OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),Girl);
 Request->SetNumberField(TEXT("day"),S.Store.CalendarDay);Request->SetStringField(TEXT("place"),S.ShopPlace);Request->SetObjectField(TEXT("piece"),OKStreetWardrobe::Piece(*Item));
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer)return;
 if(!Answer->GetBoolField(TEXT("ok"))){S.FreeTalkNotice=Answer->GetStringField(TEXT("fact"));RefreshUI();return;}
 const int32 Price=Item->PriceOf(Item->DefaultSize());auto Candidate=S.Store;
 const FString Why=OKT(TEXT("ui.bank.buy_label"))+Item->Name;
 if(Candidate.PlayerCash>=Price)OKCash(Candidate,-Price,TEXT("shopping"),Why);
 else if(!PayByCard(Candidate,Price,S.ShopPlace,Why)){S.FreeTalkNotice=OKT(TEXT("ui.economy.not_enough_money"));RefreshUI();return;}
 OKRulesTakeExt(Candidate,*Answer);ApplyRulesEffects(Candidate,*Answer);
 if(!CommitStore(MoveTemp(Candidate)))return;
 FlushRulesEffects();
 S.TellHer.Add(OKMsg(TEXT("ui.scene.game_fact_note"),{{TEXT("fact"),Answer->GetStringField(TEXT("fact"))}}));
 UE_LOG(LogTemp,Display,TEXT("Street clothes: actor %d got %s, paid %d"),Her,*ItemId,Price);
 S.FreeTalkNotice=OKMsg(TEXT("ui.clothes.done_line"),{{TEXT("name"),S.Manifest.Characters[Her].Name},{TEXT("item_name"),Item->Name},{TEXT("price"),Price}})+DressedCard(Her);
 RefreshUI();
}

// Her card as she is dressed now for the one-on-one; the words for the notice.
FString AOKStreetSocialScene::DressedCard(int32 Her){
 auto& S=*State;FString Error;const FString Card=RestyledCard(Her,Error);
 if(Card.IsEmpty()){UE_LOG(LogTemp,Warning,TEXT("Street clothes: actor %d card not dressed: %s"),Her,*Error);return FString();}
 if(S.HighCards.IsValidIndex(Her))S.HighCards[Her]=Card;
 return OKT(TEXT("ui.clothes.street_next_start"));
}

// She changes into a piece and he sees her in it: her high model alone right where she stands, from a copy of her card with
// the piece on (AOKInteractionMode::bFitting: no partner, no pose, no panel). Leaving it she is back in what she wore.
void AOKStreetSocialScene::TryClothes(int32 Her,const FString& ItemId){
 auto& S=*State;const auto* Item=S.Catalog.Find(ItemId);if(!Item||Her==INDEX_NONE)return;
 FString Error;const FString Card=RestyledCard(Her,Error,Item);
 if(Card.IsEmpty()){UE_LOG(LogTemp,Warning,TEXT("Street clothes: try on %s failed: %s"),*ItemId,*Error);S.FreeTalkNotice=OKT(TEXT("ui.clothes.try_failed"));RefreshUI();return;}
 if(SeatedWith(Her))FinishPhoto(false);
 BeginPrivate(Her,Card,Item->ClothesOutfit);
 if(S.PrivateGirl!=Her){S.FreeTalkNotice=OKT(TEXT("ui.clothes.not_now"));RefreshUI();return;}
 UE_LOG(LogTemp,Display,TEXT("Street clothes: actor %d tries on %s (%s)"),Her,*ItemId,*Card);
}

// She puts on one of hers or takes it off (ItemId empty: all her own clothes again).
void AOKStreetSocialScene::ChangeClothes(int32 Her,const FString& ItemId,bool On){
 auto& S=*State;if(!S.Manifest.Characters.IsValidIndex(Her))return;
 auto Request=OKRulesRequest(TEXT("clothes_change"));OKRulesPutExt(S,Request);Request->SetStringField(TEXT("girl"),OKStreetStableId(S.Manifest.Characters[Her]));
 Request->SetStringField(TEXT("item"),ItemId);Request->SetBoolField(TEXT("on"),On);
 const TSharedPtr<FJsonObject> Answer=OKRulesEval(S,Request);if(!Answer)return;
 if(!Answer->GetBoolField(TEXT("ok"))){S.FreeTalkNotice=Answer->GetStringField(TEXT("fact"));RefreshUI();return;}
 auto Candidate=S.Store;OKRulesTakeExt(Candidate,*Answer);if(!CommitStore(MoveTemp(Candidate)))return;
 S.FreeTalkNotice=OKMsg(TEXT("ui.clothes.changed"),{{TEXT("name"),S.Manifest.Characters[Her].Name}})+DressedCard(Her);
 RefreshUI();
}

// The buttons under a piece on the shop's menu.
void AOKStreetSocialScene::AddClothesRows(const TSharedRef<SVerticalBox>& List,const FOKStreetCatalogItem& Item,int32 Her){
 const FLinearColor Ink(.24f,.14f,.07f);TWeakObjectPtr<AOKStreetSocialScene> Weak(this);const FString Id=Item.Id;
 if(Her==INDEX_NONE){List->AddSlot().AutoHeight().Padding(12,0,0,4)[SNew(STextBlock).Font(FCoreStyle::GetDefaultFontStyle("Italic",13)).ColorAndOpacity(Ink.CopyWithNewOpacity(.7f)).Text(FText::FromString(OKT(TEXT("ui.clothes.needs_her"))))];return;}
 auto Button=[&Weak](const FString& Text,TFunction<void()> Do){return SNew(SButton).ButtonStyle(OKStreetGlassButton()).ContentPadding(FMargin(8,2)).Text(FText::FromString(Text)).OnClicked_Lambda([Weak,Do](){if(Weak.IsValid())Do();return FReply::Handled();});};
 auto Wrap=SNew(SWrapBox).UseAllottedSize(true);
 Wrap->AddSlot().Padding(2)[Button(OKT(TEXT("ui.clothes.try_on")),[Weak,Her,Id](){Weak->TryClothes(Her,Id);})];
 bool Owned=false;
 if(const TSharedPtr<FJsonObject> Has=WardrobeOf(Her)){const TArray<TSharedPtr<FJsonValue>>* Pieces=nullptr;
  if(Has->TryGetArrayField(TEXT("owned"),Pieces))for(const auto& V:*Pieces)Owned|=V->AsObject()->GetStringField(TEXT("item"))==Id;}
 if(Owned)Wrap->AddSlot().Padding(6,4)[SNew(STextBlock).ColorAndOpacity(Ink).Text(FText::FromString(OKT(TEXT("ui.clothes.owned"))))];
 else Wrap->AddSlot().Padding(2)[Button(OKT(TEXT("ui.clothes.buy_for_her")),[Weak,Her,Id](){Weak->OfferClothes(Her,Id);})];
 List->AddSlot().AutoHeight().Padding(12,0,0,4)[Wrap];
}

// What she already has, at the top of a shop that sells clothes: put it on, take it off, or back to her own.
void AOKStreetSocialScene::AddWardrobeRows(const TSharedRef<SVerticalBox>& List,int32 Her){
 const TSharedPtr<FJsonObject> Has=Her==INDEX_NONE?nullptr:WardrobeOf(Her);const TArray<TSharedPtr<FJsonValue>>* Pieces=nullptr;
 if(!Has||!Has->TryGetArrayField(TEXT("owned"),Pieces)||Pieces->IsEmpty())return;
 const FLinearColor Ink(.24f,.14f,.07f),Accent(.55f,.13f,.08f);TWeakObjectPtr<AOKStreetSocialScene> Weak(this);
 auto Button=[&Weak](const FString& Text,TFunction<void()> Do){return SNew(SButton).ButtonStyle(OKStreetGlassButton()).ContentPadding(FMargin(8,2)).Text(FText::FromString(Text)).OnClicked_Lambda([Weak,Do](){if(Weak.IsValid())Do();return FReply::Handled();});};
 List->AddSlot().AutoHeight().Padding(0,2,0,4)[SNew(STextBlock).Font(FCoreStyle::GetDefaultFontStyle("Bold",17)).ColorAndOpacity(Accent).Text(FText::FromString(OKT(TEXT("ui.clothes.wardrobe_title"))))];
 for(const auto& V:*Pieces){const auto P=V->AsObject();const FString Id=P->GetStringField(TEXT("item"));const bool Worn=P->GetBoolField(TEXT("worn"));
  auto Row=SNew(SHorizontalBox);Row->AddSlot().FillWidth(1).VAlign(VAlign_Center)[SNew(STextBlock).Font(FCoreStyle::GetDefaultFontStyle("Regular",15)).ColorAndOpacity(Ink).Text(FText::FromString(P->GetStringField(TEXT("name"))))];
  Row->AddSlot().AutoWidth().Padding(2,0)[Button(OKT(Worn?TEXT("ui.clothes.take_off"):TEXT("ui.clothes.wear")),[Weak,Her,Id,Worn](){Weak->ChangeClothes(Her,Id,!Worn);})];
  List->AddSlot().AutoHeight().Padding(0,2)[Row];}
 List->AddSlot().AutoHeight().Padding(0,4,0,8)[Button(OKT(TEXT("ui.clothes.all_own")),[Weak,Her](){Weak->ChangeClothes(Her,FString(),true);})];
}
