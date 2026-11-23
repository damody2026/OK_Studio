// Before the gallery header, which reaches the controller header, whose inline `NoteAction` builds JSON and so needs
// the type complete; this file sends composite editor operations (`ops`) the same way.
#include "Dom/JsonObject.h"
#include "OKGalleryWidget.h"
#include "Misc/ConfigCacheIni.h"
#include "OKComboBox.h"
#include "OKPropertyInput.h"
#include "OKReaderText.h"
#include "OKAppearanceCardJob.h"
#include "KKCardReader.h"
#include "KKCardWriter.h"
#include "KKGameRoot.h"
#include "KKPreviewActor.h"
#include "Blueprint/WidgetTree.h"
#include "Components/VerticalBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/Button.h"
#include "Components/Border.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "OKReaderMods.h"

void UOKPropertyInput::Changed(float V){if(!Owner||Generation!=Owner->PropertyGeneration)return;if(bBoolean)Owner->SetEditorProperty(Key,MakeShared<FJsonValueBoolean>(V>=.5f));else Owner->SetEditorProperty(Key,MakeShared<FJsonValueNumber>(V));}
void UOKPropertyParent::Committed(const FText& V,ETextCommit::Type Type){if(Owner&&Generation==Owner->PropertyGeneration&&Type!=ETextCommit::OnCleared)Owner->SetEditorProperty(Key,MakeShared<FJsonValueString>(V.ToString()));}
void UOKPropertyReset::Reset(){if(Owner)Owner->ResetEditorProperty(Key);}
void UOKPropertyToggle::Changed(bool bNewChecked){if(Owner&&Generation==Owner->PropertyGeneration)Owner->SetEditorProperty(Key,MakeShared<FJsonValueBoolean>(bNewChecked));}
void UOKPropertyParentChoice::Selected(FString Option,ESelectInfo::Type SelectionType){if(SelectionType==ESelectInfo::Direct)return;int32 I=FindOptionIndex(Option);if(Input&&Keys.IsValidIndex(I)){Input->SetText(FText::FromString(Keys[I]));Input->Committed(Input->GetText(),ETextCommit::OnEnter);}}
void UOKPropertyChoice::Selected(FString Option,ESelectInfo::Type SelectionType){if(SelectionType==ESelectInfo::Direct||!Owner||Generation!=Owner->PropertyGeneration)return;const int32 I=FindOptionIndex(Option);if(Values.IsValidIndex(I))Owner->SetEditorProperty(Key,MakeShared<FJsonValueString>(Values[I]));}
namespace {
UButton* PropertyButton(UWidgetTree* Tree,UHorizontalBox* Row,const TCHAR* Label){auto* B=Tree->ConstructWidget<UButton>();auto* T=Tree->ConstructWidget<UTextBlock>();T->SetText(FText::FromString(Label));T->SetFont(FCoreStyle::GetDefaultFontStyle("Regular",16));B->SetContent(T);Row->AddChildToHorizontalBox(B)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));return B;}
}
void UOKCharacterController::BuildPropertyControls(UVerticalBox* Parent){
 auto* Nav=WidgetTree->ConstructWidget<UHorizontalBox>();PropertyButton(WidgetTree,Nav,TEXT("顏色／飾品詳細編輯"))->OnClicked.AddDynamic(this,&UOKCharacterController::OnOpenProperties);Parent->AddChild(Nav);
 PropertyPanel=WidgetTree->ConstructWidget<UVerticalBox>();PropertyPanel->SetVisibility(ESlateVisibility::Collapsed);Parent->AddChild(PropertyPanel);
 auto* Actions=WidgetTree->ConstructWidget<UHorizontalBox>();PropertyButton(WidgetTree,Actions,TEXT("套用並更新角色"))->OnClicked.AddDynamic(this,&UOKCharacterController::OnApplyProperties);PropertyButton(WidgetTree,Actions,TEXT("撤銷尚未套用"))->OnClicked.AddDynamic(this,&UOKCharacterController::OnResetProperties);PropertyPanel->AddChild(Actions);
 PropertySearch=WidgetTree->ConstructWidget<UEditableTextBox>();PropertySearch->SetHintText(FText::FromString(TEXT("搜尋顏色、瞳孔、眼線、頭髮、飾品、變形、骨架或物理")));PropertySearch->OnTextChanged.AddDynamic(this,&UOKCharacterController::OnPropertySearch);PropertyPanel->AddChild(PropertySearch);
 auto* Pages=WidgetTree->ConstructWidget<UHorizontalBox>();PropertyButton(WidgetTree,Pages,TEXT("上一頁"))->OnClicked.AddDynamic(this,&UOKCharacterController::OnPropertyPrev);PropertyPageText=WidgetTree->ConstructWidget<UTextBlock>();Pages->AddChild(PropertyPageText);PropertyButton(WidgetTree,Pages,TEXT("下一頁"))->OnClicked.AddDynamic(this,&UOKCharacterController::OnPropertyNext);PropertyPanel->AddChild(Pages);
 PropertyStatus=WidgetTree->ConstructWidget<UTextBlock>();PropertyStatus->SetAutoWrapText(true);PropertyPanel->AddChild(PropertyStatus);
 PropertyColorTarget=WidgetTree->ConstructWidget<UOKComboBoxString>();PropertyColorTarget->OnSelectionChanged.AddDynamic(this,&UOKCharacterController::OnPropertyColorTarget);PropertyPanel->AddChild(PropertyColorTarget);
 auto* ColorRow=WidgetTree->ConstructWidget<UHorizontalBox>();PropertyColorHex=WidgetTree->ConstructWidget<UEditableTextBox>();PropertyColorHex->SetHintText(FText::FromString(TEXT("色碼 #RRGGBB 或 #RRGGBBAA，按 Enter 套用")));PropertyColorHex->OnTextCommitted.AddDynamic(this,&UOKCharacterController::OnPropertyColorHex);ColorRow->AddChildToHorizontalBox(PropertyColorHex)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));auto* SwatchSize=WidgetTree->ConstructWidget<USizeBox>();SwatchSize->SetWidthOverride(42);SwatchSize->SetHeightOverride(28);PropertyColorSwatch=WidgetTree->ConstructWidget<UBorder>();SwatchSize->SetContent(PropertyColorSwatch);ColorRow->AddChild(SwatchSize);PropertyPanel->AddChild(ColorRow);
 auto* Height=WidgetTree->ConstructWidget<USizeBox>();Height->SetHeightOverride(420);PropertyPanel->AddChild(Height);auto* Scroll=WidgetTree->ConstructWidget<UScrollBox>();Height->SetContent(Scroll);PropertyRows=WidgetTree->ConstructWidget<UVerticalBox>();Scroll->AddChild(PropertyRows);
}
void UOKCharacterController::OnOpenProperties(){
 if(MaterializeAppearance([](UOKCharacterController* G){G->OnOpenProperties();}))return;
 if(bPropertyBusy||bAppearanceBusy||bLoadInFlight||!Entries.IsValidIndex(SelectedIndex))return;
 if(PropertyPanel->GetVisibility()!=ESlateVisibility::Collapsed&&!EditorProperties.IsEmpty()){++PropertyGeneration;PropertyPanel->SetVisibility(ESlateVisibility::Collapsed);return;}
 if(!EditorProperties.IsEmpty()&&PropertySource==Entries[SelectedIndex].Path&&PropertyOutfit==OutfitIndex){PropertyPanel->SetVisibility(ESlateVisibility::Visible);RebuildPropertyControls();return;}
 PropertyPanel->SetVisibility(ESlateVisibility::Visible);++PropertyGeneration;PendingProperties.Reset();EditorProperties.Reset();PropertyRows->ClearChildren();PropertySource=Entries[SelectedIndex].Path;PropertyOutfit=OutfitIndex;
 const FString Folder=AppearanceWorkFolder(Entries[SelectedIndex].Path),Input=Folder/(FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT(".properties.png"));IFileManager::Get().MakeDirectory(*Folder,true);
 auto CardJob=MakeShared<FOKAppearanceCardJob,ESPMode::ThreadSafe>(Selected);
 if(auto* Root=UKKGameRoot::Get())AppearanceRoot=Root->Root;
 auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("action"),TEXT("properties"));R->SetStringField(TEXT("card"),Input);R->SetNumberField(TEXT("outfit"),OutfitIndex);bPropertyBusy=true;PropertyStatus->SetText(FText::FromString(TEXT("讀取目前角色的可編輯設定…")));const int32 Selection=SelectedIndex,Generation=LoadGeneration,Outfit=OutfitIndex;
 RunAppearanceRequest(R,[Selection,Generation,Outfit](UOKCharacterController* G,TSharedPtr<FJsonObject> Data,const FString& Error){G->bPropertyBusy=false;if(Selection!=G->SelectedIndex||Generation!=G->LoadGeneration||Outfit!=G->OutfitIndex)return;if(!Data){G->PropertyStatus->SetText(FText::FromString(TEXT("設定讀取失敗：")+Error));return;}for(auto V:Data->GetArrayField(TEXT("properties")))G->EditorProperties.Add(V->AsObject());G->EditorPropertyParents.Reset();for(auto V:Data->GetArrayField(TEXT("parents")))G->EditorPropertyParents.Add(V->AsObject());
  // Sections ok-extract does not know: named, never silently dropped (see EditorUnknownPluginSections).
  G->EditorUnknownPluginSections.Reset();const TArray<TSharedPtr<FJsonValue>>* Unknown=nullptr;
  G->bEditorUnknownPluginSectionsReported=Data->TryGetArrayField(TEXT("unknown_plugin_sections"),Unknown);
  G->EditorUnknownPluginSectionsCard=G->Entries.IsValidIndex(G->SelectedIndex)?G->Entries[G->SelectedIndex].Path:FString();G->EditorUnknownPluginSectionsOutfit=G->OutfitIndex;
  if(Unknown)for(auto V:*Unknown){const FString S=V->AsString();if(!S.IsEmpty())G->EditorUnknownPluginSections.Add(S);}
  G->RebuildPropertyControls();
  if(!G->EditorUnknownPluginSections.IsEmpty())G->PropertyStatus->SetText(FText::FromString(FString::Printf(
   TEXT("這張卡有 %d 個尚未支援的外掛區段，內容不會顯示也不會被改到：%s"),
   G->EditorUnknownPluginSections.Num(),*FString::Join(G->EditorUnknownPluginSections,TEXT("、")))));},CardJob);
}
void UOKCharacterController::OnPropertySearch(const FText& Value){PropertyPage=0;RebuildPropertyControls();}
void UOKCharacterController::OnPropertyPrev(){PropertyPage=FMath::Max(0,PropertyPage-1);RebuildPropertyControls();}
void UOKCharacterController::OnPropertyNext(){PropertyPage=FMath::Min(FMath::Max(0,(PropertyMatches-1)/64),PropertyPage+1);RebuildPropertyControls();}
void UOKCharacterController::SetEditorProperty(const FString& Key,TSharedPtr<FJsonValue> Value){if(bPropertyBusy)return;
 auto Equal=[](const TSharedPtr<FJsonValue>& A,const TSharedPtr<FJsonValue>& B){if(!A.IsValid()||!B.IsValid()||A->Type!=B->Type)return false;if(A->Type==EJson::Number)return FMath::Abs(A->AsNumber()-B->AsNumber())<1.e-7;if(A->Type==EJson::Boolean)return A->AsBool()==B->AsBool();if(A->Type==EJson::String)return A->AsString()==B->AsString();return false;};
 TSharedPtr<FJsonValue> BaseValue;for(auto P:EditorProperties)if(P->GetStringField(TEXT("key"))==Key){BaseValue=P->Values[TEXT("value")];break;}
 // reader.property_change only for a value that changed: the page writes every row's value back when it is built.
 {const TSharedPtr<FJsonValue>* Was=PendingProperties.Find(Key);if(!Equal(Was?*Was:BaseValue,Value))OKReaderMods::PropertyChanged(this,Key);}
 const bool Same=Equal(BaseValue,Value);if(Same)PendingProperties.Remove(Key);else PendingProperties.Add(Key,Value);RefreshPropertyColor();PropertyStatus->SetText(FText::FromString(FString::Printf(TEXT("已修改 %d 項；按「套用並更新角色」產生可保存的外觀。"),PendingProperties.Num())));}
void UOKCharacterController::OnResetProperties(){if(bPropertyBusy)return;PendingProperties.Reset();RebuildPropertyControls();}
void UOKCharacterController::ResetEditorProperty(const FString& Key){if(bPropertyBusy)return;PendingProperties.Remove(Key);RebuildPropertyControls();}
void UOKCharacterController::OnPropertyColorTarget(FString Option,ESelectInfo::Type SelectionType){PropertyColorKey=PropertyColorLabels.FindRef(Option);RefreshPropertyColor();}
void UOKCharacterController::RefreshPropertyColor(){
 auto* Keys=PropertyColorGroups.Find(PropertyColorKey);if(!Keys||Keys->Num()!=4)return;uint8 Channels[4]={0,0,0,255};
 for(int32 I=0;I<4;++I){double Value=I==3?1.:0.;if(auto* V=PendingProperties.Find((*Keys)[I]))Value=(*V)->AsNumber();else for(auto P:EditorProperties)if(P->GetStringField(TEXT("key"))==(*Keys)[I]){Value=P->GetNumberField(TEXT("value"));break;}Channels[I]=FMath::RoundToInt(FMath::Clamp(Value,0.,1.)*255.);}
 const FColor C(Channels[0],Channels[1],Channels[2],Channels[3]);PropertyColorHex->SetText(FText::FromString(TEXT("#")+C.ToHex()));PropertyColorSwatch->SetBrushColor(FLinearColor::FromSRGBColor(C));
}
void UOKCharacterController::OnPropertyColorHex(const FText& Text,ETextCommit::Type CommitType){
 if(CommitType!=ETextCommit::OnEnter||bPropertyBusy)return;FString Hex=Text.ToString().TrimStartAndEnd();Hex.RemoveFromStart(TEXT("#"));if(Hex.Len()!=6&&Hex.Len()!=8){PropertyStatus->SetText(FText::FromString(TEXT("色碼請輸入六位 RGB 或八位 RGBA 十六進位值。")));return;}for(TCHAR C:Hex)if(!FChar::IsHexDigit(C)){PropertyStatus->SetText(FText::FromString(TEXT("色碼只能包含 0–9 與 A–F。")));return;}
 auto* Keys=PropertyColorGroups.Find(PropertyColorKey);if(!Keys||Keys->Num()!=4)return;const TArray<FString> Copy=*Keys;const FColor C=FColor::FromHex(Hex);const uint8 Values[4]={C.R,C.G,C.B,C.A};for(int32 I=0;I<(Hex.Len()==8?4:3);++I)SetEditorProperty(Copy[I],MakeShared<FJsonValueNumber>(Values[I]/255.));RebuildPropertyControls();
}
void UOKCharacterController::RebuildPropertyControls(){
 if(!PropertyRows||bPropertyBusy)return;++PropertyGeneration;PropertyRows->ClearChildren();const FString Search=PropertySearch->GetText().ToString();int32 Count=0;PropertyMatches=0;for(auto P:EditorProperties)if(PropertyInScope(P)&&(Search.IsEmpty()||P->GetStringField(TEXT("label")).Contains(Search)||P->GetStringField(TEXT("key")).Contains(Search)))++PropertyMatches;PropertyPage=FMath::Clamp(PropertyPage,0,FMath::Max(0,(PropertyMatches-1)/64));
 const FString PreviousColor=PropertyColorKey;PropertyColorGroups.Reset();PropertyColorLabels.Reset();PropertyColorTarget->ClearOptions();PropertyColorKey=PreviousColor;TMap<FString,FString> GroupLabels;
 for(auto P:EditorProperties)if(PropertyInScope(P)&&P->GetStringField(TEXT("kind"))==TEXT("color")){const FString Key=P->GetStringField(TEXT("key"));int32 Dot;if(!Key.FindLastChar(TEXT('.'),Dot))continue;const FString Component=Key.Mid(Dot+1);int32 Index=INDEX_NONE;if(Component.Len()==1&&Component[0]>=TEXT('0')&&Component[0]<=TEXT('3'))Index=Component[0]-TEXT('0');else for(int32 I=0;I<4;++I)if(Component==TArray<FString>{TEXT("r"),TEXT("g"),TEXT("b"),TEXT("a")}[I])Index=I;if(Index==INDEX_NONE)continue;const FString Prefix=Key.Left(Dot);auto& Keys=PropertyColorGroups.FindOrAdd(Prefix);Keys.SetNum(4);Keys[Index]=Key;FString L=P->GetStringField(TEXT("label"));int32 Slash;if(L.FindLastChar(TEXT('／'),Slash))L=L.Left(Slash);GroupLabels.Add(Prefix,L);}
 TArray<FString> ColorKeys;PropertyColorGroups.GetKeys(ColorKeys);ColorKeys.Sort();FString CurrentOption;for(const FString& Key:ColorKeys){const auto& Keys=PropertyColorGroups[Key];if(Keys.Num()!=4||Keys.Contains(FString()))continue;const FString L=GroupLabels[Key];PropertyColorLabels.Add(L,Key);PropertyColorTarget->AddOption(L);if(Key==PropertyColorKey)CurrentOption=L;}if(CurrentOption.IsEmpty()&&PropertyColorTarget->GetOptionCount()>0)CurrentOption=PropertyColorTarget->GetOptionAtIndex(0);PropertyColorTarget->SetSelectedOption(CurrentOption);OnPropertyColorTarget(CurrentOption,ESelectInfo::Direct);
 // A plugin's rows (plugins.<id>.*, ok-extract plugins.rs) under a heading: its section's title (group_id, a text id of
 // the reader's language) and how many rows it has here, an ICU message (reader.properties.plugin_group_rows).
 TMap<FString,int32> GroupRows;for(auto P:EditorProperties){FString GroupId;if(PropertyInScope(P)&&P->TryGetStringField(TEXT("group_id"),GroupId)&&!GroupId.IsEmpty())++GroupRows.FindOrAdd(GroupId);}
 FString ShownGroup;
 for(auto P:EditorProperties){const FString Key=P->GetStringField(TEXT("key")),Label=P->GetStringField(TEXT("label")),Kind=P->GetStringField(TEXT("kind"));if(!PropertyInScope(P))continue;if(!Search.IsEmpty()&&!Label.Contains(Search)&&!Key.Contains(Search))continue;const int32 Match=Count++;if(Match<PropertyPage*64||Match>=(PropertyPage+1)*64)continue;
  if(FString GroupId;P->TryGetStringField(TEXT("group_id"),GroupId)&&!GroupId.IsEmpty()&&GroupId!=ShownGroup){
   ShownGroup=GroupId;auto Args=MakeShared<FJsonObject>();Args->SetStringField(TEXT("group"),OKReaderT(GroupId));Args->SetNumberField(TEXT("count"),GroupRows.FindRef(GroupId));
   FString Heading=OKReaderMsg(TEXT("reader.properties.plugin_group_rows"),Args);if(Heading==TEXT("reader.properties.plugin_group_rows"))Heading=OKReaderT(GroupId);
   auto* Header=WidgetTree->ConstructWidget<UTextBlock>();Header->SetText(FText::FromString(Heading));Header->SetToolTipText(FText::FromString(GroupId));Header->SetFont(FCoreStyle::GetDefaultFontStyle("Bold",15));PropertyRows->AddChild(Header);}
  auto* Row=WidgetTree->ConstructWidget<UHorizontalBox>();auto* Text=WidgetTree->ConstructWidget<UTextBlock>();Text->SetText(FText::FromString(Label));Text->SetAutoWrapText(true);Text->SetToolTipText(FText::FromString(Key));Text->SetFont(FCoreStyle::GetDefaultFontStyle("Regular",14));Row->AddChildToHorizontalBox(Text)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
  auto V=PendingProperties.Contains(Key)?PendingProperties[Key]:P->Values[TEXT("value")];
  auto* Width=WidgetTree->ConstructWidget<USizeBox>();Width->SetWidthOverride(130);Row->AddChild(Width);
  if(Kind==TEXT("bool")){auto* Toggle=WidgetTree->ConstructWidget<UOKPropertyToggle>();Toggle->Owner=this;Toggle->Key=Key;Toggle->Generation=PropertyGeneration;Toggle->SetIsChecked(V->AsBool());Toggle->OnCheckStateChanged.AddDynamic(Toggle,&UOKPropertyToggle::Changed);Width->SetContent(Toggle);}
  else if(Kind==TEXT("choice")){auto* Choice=WidgetTree->ConstructWidget<UOKPropertyChoice>();Choice->Owner=this;Choice->Key=Key;Choice->Generation=PropertyGeneration;const TArray<TSharedPtr<FJsonValue>>* Options=nullptr;if(P->TryGetArrayField(TEXT("options"),Options))for(auto O:*Options){const auto Option=O->AsObject();const FString Value=Option->GetStringField(TEXT("value")),L=Option->GetStringField(TEXT("label"));Choice->Values.Add(Value);Choice->AddOption(L);if(Value==V->AsString())Choice->SetSelectedOption(L);}Choice->OnSelectionChanged.AddDynamic(Choice,&UOKPropertyChoice::Selected);Width->SetWidthOverride(220);Width->SetContent(Choice);}
  else if(Kind==TEXT("parent")){auto* Col=WidgetTree->ConstructWidget<UVerticalBox>();Width->SetContent(Col);auto* Input=WidgetTree->ConstructWidget<UOKPropertyParent>();Input->Owner=this;Input->Key=Key;Input->Generation=PropertyGeneration;Input->SetText(FText::FromString(V->AsString()));Input->SetToolTipText(FText::FromString(TEXT("亦可輸入模組的骨架名稱；空白使用素材預設綁定。")));Input->OnTextCommitted.AddDynamic(Input,&UOKPropertyParent::Committed);Col->AddChild(Input);auto* Choice=WidgetTree->ConstructWidget<UOKPropertyParentChoice>();Choice->Input=Input;for(auto ParentOption:EditorPropertyParents){const FString K=ParentOption->GetStringField(TEXT("key")),L=ParentOption->GetStringField(TEXT("label"));Choice->Keys.Add(K);Choice->AddOption(L);if(K==V->AsString())Choice->SetSelectedOption(L);}Choice->OnSelectionChanged.AddDynamic(Choice,&UOKPropertyParentChoice::Selected);Col->AddChild(Choice);}
  else{auto* Input=WidgetTree->ConstructWidget<UOKPropertyInput>();Input->Owner=this;Input->Key=Key;Input->Generation=PropertyGeneration;Input->bBoolean=Kind==TEXT("bool");Input->SetMinValue(Kind==TEXT("color")||Input->bBoolean?0.f:-1000000.f);Input->SetMaxValue(Kind==TEXT("color")||Input->bBoolean?1.f:1000000.f);Input->SetDelta(Input->bBoolean?1.f:.01f);Input->SetValue(Input->bBoolean?(V->AsBool()?1.f:0.f):V->AsNumber());Input->OnValueChanged.AddDynamic(Input,&UOKPropertyInput::Changed);Width->SetContent(Input);}
  auto* Reset=WidgetTree->ConstructWidget<UOKPropertyReset>();Reset->Owner=this;Reset->Key=Key;auto* ResetText=WidgetTree->ConstructWidget<UTextBlock>();ResetText->SetText(FText::FromString(TEXT("撤銷")));Reset->SetContent(ResetText);Reset->SetToolTipText(FText::FromString(TEXT("還原此欄位尚未套用的修改")));Reset->OnClicked.AddDynamic(Reset,&UOKPropertyReset::Reset);Row->AddChild(Reset);PropertyRows->AddChild(Row);
 }
 PropertyPageText->SetText(FText::FromString(FString::Printf(TEXT("%d／%d 頁"),PropertyPage+1,FMath::Max(1,(PropertyMatches+63)/64))));
 PropertyStatus->SetText(FText::FromString(FString::Printf(TEXT("符合 %d／%d 項；顏色可輸入色碼或調整 0–1 色彩通道。飾品變形組依原作為兩組位置、旋轉角度與縮放。"),Count,EditorProperties.Num())));
}
void UOKCharacterController::OnApplyProperties(){
 if(bPropertyBusy||bAppearanceBusy||bLoadInFlight||bAnimationPreparing||PendingProperties.IsEmpty()||!Entries.IsValidIndex(SelectedIndex))return;
 if(PropertySource!=Entries[SelectedIndex].Path||PropertyOutfit!=OutfitIndex){PropertyStatus->SetText(FText::FromString(TEXT("角色或服裝已切換，請關閉並重新開啟詳細編輯後再修改。")));return;}
 const FString Folder=AppearanceWorkFolder(Entries[SelectedIndex].Path),Id=FGuid::NewGuid().ToString(EGuidFormats::Digits),Input=Folder/(Id+TEXT(".input.png")),Output=Folder/(Id+TEXT(".png"));
 auto CardJob=MakeShared<FOKAppearanceCardJob,ESPMode::ThreadSafe>(Selected);
 TArray<TSharedPtr<FJsonValue>> Edits;for(auto& E:PendingProperties){auto V=MakeShared<FJsonObject>();V->SetStringField(TEXT("key"),E.Key);V->SetField(TEXT("value"),E.Value);Edits.Add(MakeShared<FJsonValueObject>(V));}
 auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("action"),TEXT("properties_apply"));R->SetStringField(TEXT("card"),Input);R->SetStringField(TEXT("output"),Output);R->SetStringField(TEXT("resources"),FPaths::ProjectContentDir()/TEXT("IndependentResources/v1"));R->SetNumberField(TEXT("outfit"),OutfitIndex);R->SetArrayField(TEXT("edits"),Edits);
 // A staged hair main colour carries the original's whole action with it (every slot, the gradient, the outline and
 // the gloss, as the four settings say). The staged rows go along and win over the action's own fields, so the colour
 // the person is looking at is the colour that lands; the rest of what the original writes comes from the action.
 LoadHairColourSettings();
 const TArray<TSharedPtr<FJsonValue>> HairOps=HairColourOpsForStagedEdits();
 if(!HairOps.IsEmpty())R->SetArrayField(TEXT("ops"),HairOps);
 bPropertyBusy=true;bAppearanceBusy=true;PropertyPanel->SetIsEnabled(false);if(ShapePanel)ShapePanel->SetIsEnabled(false);PropertyStatus->SetText(FText::FromString(TEXT("正在產生外觀與可保存資源…")));const int32 Selection=SelectedIndex,Generation=LoadGeneration,Outfit=OutfitIndex;const bool bActionApplied=!HairOps.IsEmpty();
 RunAppearanceRequest(R,[Selection,Generation,Outfit,Output,CardJob,bActionApplied](UOKCharacterController* G,TSharedPtr<FJsonObject> Data,const FString& Failure){G->bPropertyBusy=false;G->bAppearanceBusy=false;G->PropertyPanel->SetIsEnabled(true);if(G->ShapePanel)G->ShapePanel->SetIsEnabled(true);if(Selection!=G->SelectedIndex||Generation!=G->LoadGeneration||Outfit!=G->OutfitIndex)return;
  if(!Data){G->PropertyStatus->SetText(FText::FromString(TEXT("外觀更新失敗，保留目前角色與修改：")+Failure));return;}
  if(bActionApplied)G->EditorProperties.Reset();	// the action wrote fields no staged row asked for: read them back rather than show stale ones
  else for(auto P:G->EditorProperties)if(auto* V=G->PendingProperties.Find(P->GetStringField(TEXT("key"))))P->SetField(TEXT("value"),*V);
  G->PendingProperties.Reset();G->Selected=MoveTemp(CardJob->Card);G->SetWorkingCardPath(Output);G->PropertySource=Output;G->bIndependentCards=true;G->PreviewResourceSignature.Empty();G->OnLoad3D();G->PropertyStatus->SetText(FText::FromString(TEXT("已套用並保存外觀，可繼續編輯或另存角色卡。")));
 },CardJob);
}
namespace { constexpr const TCHAR* HairColourSection=TEXT("OpenKoikatsu.HairEditor"); }

// Where the reader's other display settings live (GConfig, GGameUserSettingsIni under Saved/): one place for the
// reader's settings, not a file of our own. Saved/ is discardable -- clearing it returns these to the original's
// defaults, which are all four on.
void UOKCharacterController::LoadHairColourSettings()
{
 for(const TPair<const TCHAR*,bool*> Pair:{TPair<const TCHAR*,bool*>(TEXT("HairSameSetting"),&bHairSameSetting),
   {TEXT("HairAutoSetting"),&bHairAutoSetting},{TEXT("HairOutlineSetting"),&bHairOutlineSetting},{TEXT("HairGlossSetting"),&bHairGlossSetting}})
  GConfig->GetBool(HairColourSection,Pair.Key,*Pair.Value,GGameUserSettingsIni);
}

void UOKCharacterController::SetHairColourSetting(const FString& Name,bool Value)
{
 bool* Target=Name==TEXT("same")?&bHairSameSetting:Name==TEXT("auto")?&bHairAutoSetting:Name==TEXT("outline")?&bHairOutlineSetting:Name==TEXT("gloss")?&bHairGlossSetting:nullptr;
 if(!Target||*Target==Value)return;
 *Target=Value;
 const FString Key=FString(TEXT("Hair"))+(Name==TEXT("same")?TEXT("Same"):Name==TEXT("auto")?TEXT("Auto"):Name==TEXT("outline")?TEXT("Outline"):TEXT("Gloss"))+TEXT("Setting");
 GConfig->SetBool(HairColourSection,*Key,Value,GGameUserSettingsIni);
 GConfig->Flush(false,GGameUserSettingsIni);
}

// Dragging the main hair colour is not one field in the original: with the four settings on it writes every slot's
// base, gradient start and end, outline and gloss (parity doc §7.1). The rows the person dragged stay as they are --
// they are what is on screen -- and this adds the action those rows imply, so one apply writes the whole thing.
// Only `baseColor`: a person editing the gradient or the outline directly means that one field, as the original does.
TArray<TSharedPtr<FJsonValue>> UOKCharacterController::HairColourOpsForStagedEdits() const
{
 TArray<TSharedPtr<FJsonValue>> Ops;
 TSet<int32> Slots;
 for(const TPair<FString,TSharedPtr<FJsonValue>>& Edit:PendingProperties)
 {
  int32 SlotIndex=INDEX_NONE;
  // `hair.parts.<N>.baseColor.<channel>`: the channel is which of RGBA, so any of them means this slot's main colour.
  if(!Edit.Key.StartsWith(TEXT("hair.parts."))||!Edit.Key.Contains(TEXT(".baseColor.")))continue;
  const FString Rest=Edit.Key.RightChop(11);FString Number,Tail;
  if(!Rest.Split(TEXT("."),&Number,&Tail)||!Number.IsNumeric())continue;
  SlotIndex=FCString::Atoi(*Number);
  if(SlotIndex>=0)Slots.Add(SlotIndex);
 }
 for(int32 SlotIndex:Slots)
 {
  // The colour sent is the one the rows will hold after this apply: the staged channels, and for a channel not
  // dragged the value the row shows now. Reading only the staged ones would send a colour nobody chose.
  double Channels[3]={0,0,0};bool Known[3]={false,false,false};
  for(int32 Channel=0;Channel<3;++Channel)
  {
   const FString Key=FString::Printf(TEXT("hair.parts.%d.baseColor.%d"),SlotIndex,Channel);
   if(const TSharedPtr<FJsonValue>* Staged=PendingProperties.Find(Key)){Channels[Channel]=(*Staged)->AsNumber();Known[Channel]=true;continue;}
   for(const TSharedPtr<FJsonObject>& Row:EditorProperties)if(Row->GetStringField(TEXT("key"))==Key){Channels[Channel]=Row->GetNumberField(TEXT("value"));Known[Channel]=true;break;}
  }
  if(!Known[0]||!Known[1]||!Known[2])continue;	// an incomplete colour is not an action; the staged rows still apply
  auto Op=MakeShared<FJsonObject>();Op->SetStringField(TEXT("op"),TEXT("hair_base_color"));
  TArray<TSharedPtr<FJsonValue>> Rgba;for(double V:Channels)Rgba.Add(MakeShared<FJsonValueNumber>(FMath::Clamp(V,0.,1.)));
  Op->SetArrayField(TEXT("rgba"),Rgba);Op->SetNumberField(TEXT("slot"),SlotIndex);
  Op->SetBoolField(TEXT("same"),bHairSameSetting);Op->SetBoolField(TEXT("auto"),bHairAutoSetting);
  Op->SetBoolField(TEXT("outline"),bHairOutlineSetting);Op->SetBoolField(TEXT("gloss"),bHairGlossSetting);
  Ops.Add(MakeShared<FJsonValueObject>(Op));
 }
 return Ops;
}

// Deliberately beside OnApplyProperties rather than folded into it: that function is being edited by other sessions
// this week, and the two differ in what they know afterwards. An `edits` apply knows every new value (it sent them,
// so it patches the rows in place); an `ops` apply does not -- the expansion happens in Rust and can touch fields no
// row asked for -- so it drops the rows and lets the panel read them back from the card it just wrote.
FString UOKCharacterController::ApplyPropertyOps(const TArray<TSharedPtr<FJsonValue>>& Ops){
 if(Ops.IsEmpty())return TEXT("No operation given");
 if(bPropertyBusy||bAppearanceBusy||bLoadInFlight||bAnimationPreparing)return TEXT("Busy; retry when the current work finishes");
 if(!Entries.IsValidIndex(SelectedIndex))return TEXT("No character loaded");
 if(!PendingProperties.IsEmpty())return TEXT("Apply or discard the staged property edits first");
 if(PropertySource!=Entries[SelectedIndex].Path||PropertyOutfit!=OutfitIndex)return TEXT("Character or outfit changed; reopen the detailed editor");
 const FString Folder=AppearanceWorkFolder(Entries[SelectedIndex].Path),Id=FGuid::NewGuid().ToString(EGuidFormats::Digits),Input=Folder/(Id+TEXT(".input.png")),Output=Folder/(Id+TEXT(".png"));
 auto CardJob=MakeShared<FOKAppearanceCardJob,ESPMode::ThreadSafe>(Selected);
 auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("action"),TEXT("properties_apply"));R->SetStringField(TEXT("card"),Input);R->SetStringField(TEXT("output"),Output);R->SetStringField(TEXT("resources"),FPaths::ProjectContentDir()/TEXT("IndependentResources/v1"));R->SetNumberField(TEXT("outfit"),OutfitIndex);R->SetArrayField(TEXT("ops"),Ops);
 bPropertyBusy=true;bAppearanceBusy=true;if(PropertyPanel)PropertyPanel->SetIsEnabled(false);if(ShapePanel)ShapePanel->SetIsEnabled(false);
 if(PropertyStatus)PropertyStatus->SetText(FText::FromString(TEXT("正在套用這個動作並產生外觀…")));
 const int32 Selection=SelectedIndex,Generation=LoadGeneration,Outfit=OutfitIndex;
 RunAppearanceRequest(R,[Selection,Generation,Outfit,Output,CardJob,Ops](UOKCharacterController* G,TSharedPtr<FJsonObject> Data,const FString& Failure){
  G->bPropertyBusy=false;G->bAppearanceBusy=false;if(G->PropertyPanel)G->PropertyPanel->SetIsEnabled(true);if(G->ShapePanel)G->ShapePanel->SetIsEnabled(true);
  if(Selection!=G->SelectedIndex||Generation!=G->LoadGeneration||Outfit!=G->OutfitIndex)return;
  if(!Data){if(G->PropertyStatus)G->PropertyStatus->SetText(FText::FromString(TEXT("這個動作沒有套用，角色保持原樣：")+Failure));return;}
  OKReaderMods::AccessoriesMoved(G,Ops);	// reader.accessory_copy／accessory_transfer (other ops are ignored there)
  // The rows are stale in a way we cannot repair from here, so they are re-read rather than guessed.
  G->EditorProperties.Reset();G->Selected=MoveTemp(CardJob->Card);G->SetWorkingCardPath(Output);G->PropertySource=Output;G->bIndependentCards=true;G->PreviewResourceSignature.Empty();G->OnLoad3D();
  if(G->PropertyStatus)G->PropertyStatus->SetText(FText::FromString(TEXT("已套用這個動作並保存外觀。")));
 },CardJob);
 return FString();
}
bool UOKCharacterController::PropertyInScope(const TSharedPtr<FJsonObject>& P) const{
 if(PropertyScope.IsEmpty())return true;
 const FString Key=P->GetStringField(TEXT("key")),Label=P->GetStringField(TEXT("label"));
 for(const FString& Token:PropertyScope)if(Key.Contains(Token,ESearchCase::IgnoreCase)||Label.Contains(Token))return true;
 return false;
}
void UOKCharacterController::SetPropertyScope(const TArray<FString>& Tokens){
 if(PropertyScope!=Tokens){PropertyScope=Tokens;PropertyPage=0;}
 if(bPropertyBusy)return;	// the rows being read are built with this scope
 // Loaded for this card and outfit: only the rows change. Otherwise opened (OnOpenProperties folds an open panel away).
 if(PropertyPanel&&PropertyPanel->GetVisibility()!=ESlateVisibility::Collapsed&&!EditorProperties.IsEmpty()&&Entries.IsValidIndex(SelectedIndex)&&PropertySource==Entries[SelectedIndex].Path&&PropertyOutfit==OutfitIndex)RebuildPropertyControls();
 else{if(PropertyPanel&&PropertyPanel->GetVisibility()!=ESlateVisibility::Collapsed)PropertyPanel->SetVisibility(ESlateVisibility::Collapsed);OnOpenProperties();}
}

// 材質貼圖（MaterialEditor 的 TextureDictionary／MaterialTexturePropertyList）。和 EditorProperties 分开，因为
// 一张 PNG 不是属性值：ok-extract 那边也是另外两个动作（Docs/READER_UI_APPEARANCE_API.md §11）。
// 一列的身分是 5 个栏位（object／coordinate／slot／material／property），不是列号 —— 清单的顺序是每张卡自己的事，
// 所以界面拿到什么就送回什么，从不自己记「第几列」。
void UOKCharacterController::LoadTextureRows(){
 if(bTextureBusy||bPropertyBusy||bAppearanceBusy||bLoadInFlight||!Entries.IsValidIndex(SelectedIndex))return;
 const FString Card=Entries[SelectedIndex].Path;
 if(TextureSource==Card&&TextureOutfit==OutfitIndex)return;	// 已经是这张卡这套服装的，别重读
 const FString Folder=AppearanceWorkFolder(Card),Input=Folder/(FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT(".textures.png"));
 IFileManager::Get().MakeDirectory(*Folder,true);
 auto CardJob=MakeShared<FOKAppearanceCardJob,ESPMode::ThreadSafe>(Selected);
 if(auto* Root=UKKGameRoot::Get())AppearanceRoot=Root->Root;
 auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("action"),TEXT("textures"));R->SetStringField(TEXT("card"),Input);R->SetNumberField(TEXT("outfit"),OutfitIndex);
 bTextureBusy=true;EditorTextures.Reset();TextureSource=Card;TextureOutfit=OutfitIndex;TextureNote=TEXT("讀取這張卡的材質貼圖…");++TextureGeneration;
 const int32 Selection=SelectedIndex,Generation=LoadGeneration,Outfit=OutfitIndex;
 RunAppearanceRequest(R,[Selection,Generation,Outfit](UOKCharacterController* G,TSharedPtr<FJsonObject> Data,const FString& Error){
  G->bTextureBusy=false;++G->TextureGeneration;
  if(Selection!=G->SelectedIndex||Generation!=G->LoadGeneration||Outfit!=G->OutfitIndex)return;
  if(!Data){G->TextureSource.Empty();G->TextureOutfit=INDEX_NONE;G->TextureNote=TEXT("貼圖清單讀取失敗：")+Error;return;}
  for(auto V:Data->GetArrayField(TEXT("textures")))G->EditorTextures.Add(V->AsObject());
  G->TextureNote=G->EditorTextures.IsEmpty()?TEXT("這張卡（這套服裝）沒有任何材質貼圖覆寫。")
   :FString::Printf(TEXT("%d 筆材質貼圖覆寫。"),G->EditorTextures.Num());
 },CardJob);
}
// 一批修改一次送出，和 ApplyPropertyOps 同一个理由：卡片不会停在半套用的状态，开卡也只发生一次。
FString UOKCharacterController::ApplyTextureChanges(const TArray<TSharedPtr<FJsonValue>>& Changes){
 if(Changes.IsEmpty())return TEXT("No texture change given");
 if(bTextureBusy||bPropertyBusy||bAppearanceBusy||bLoadInFlight||bAnimationPreparing)return TEXT("Busy; retry when the current work finishes");
 if(!Entries.IsValidIndex(SelectedIndex))return TEXT("No character loaded");
 if(!PendingProperties.IsEmpty())return TEXT("Apply or discard the staged property edits first");
 const FString Folder=AppearanceWorkFolder(Entries[SelectedIndex].Path),Id=FGuid::NewGuid().ToString(EGuidFormats::Digits),
  Input=Folder/(Id+TEXT(".input.png")),Output=Folder/(Id+TEXT(".png"));
 auto CardJob=MakeShared<FOKAppearanceCardJob,ESPMode::ThreadSafe>(Selected);
 auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("action"),TEXT("textures_apply"));R->SetStringField(TEXT("card"),Input);
 R->SetStringField(TEXT("output"),Output);R->SetStringField(TEXT("resources"),FPaths::ProjectContentDir()/TEXT("IndependentResources/v1"));
 R->SetNumberField(TEXT("outfit"),OutfitIndex);R->SetArrayField(TEXT("changes"),Changes);
 bTextureBusy=true;bAppearanceBusy=true;if(PropertyPanel)PropertyPanel->SetIsEnabled(false);
 TextureNote=TEXT("正在寫入貼圖並產生外觀…");++TextureGeneration;
 const int32 Selection=SelectedIndex,Generation=LoadGeneration,Outfit=OutfitIndex;
 RunAppearanceRequest(R,[Selection,Generation,Outfit,Output,CardJob](UOKCharacterController* G,TSharedPtr<FJsonObject> Data,const FString& Failure){
  G->bTextureBusy=false;G->bAppearanceBusy=false;++G->TextureGeneration;if(G->PropertyPanel)G->PropertyPanel->SetIsEnabled(true);
  if(Selection!=G->SelectedIndex||Generation!=G->LoadGeneration||Outfit!=G->OutfitIndex)return;
  if(!Data){G->TextureNote=TEXT("貼圖沒有寫入，角色保持原樣：")+Failure;return;}
  // 清单与属性都已经不是这张卡的了（purge 会丢掉没人引用的字典项），重读而不是猜。
  G->EditorTextures.Reset();G->TextureSource.Empty();G->TextureOutfit=INDEX_NONE;G->EditorProperties.Reset();
  G->Selected=MoveTemp(CardJob->Card);G->SetWorkingCardPath(Output);G->PropertySource=Output;G->bIndependentCards=true;
  G->PreviewResourceSignature.Empty();G->OnLoad3D();
  G->TextureNote=TEXT("已寫入貼圖並保存外觀。");
 },CardJob);
 return FString();
}
