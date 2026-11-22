#include "OKReaderPageItems.h"

#include "Blueprint/WidgetTree.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Dom/JsonObject.h"
#include "OKCharacterController.h"
#include "OKCharacterMCPRegistry.h"
#include "OKReaderMods.h"
#include "OKReaderText.h"
#include "Styling/CoreStyle.h"

namespace
{
using FRows=TArray<TSharedPtr<FJsonValue>>;

struct FItem
{
	TWeakObjectPtr<UWidget> Control;
	TWeakObjectPtr<UTextBlock> Caption;
	TWeakObjectPtr<UVerticalBox> Box;
	FString Kind,Key,Action,Label,LabelId;
};
TArray<FItem> GItems;
TArray<TWeakObjectPtr<UVerticalBox>> GBoxes;
float GSinceRefresh=0.f;

const TCHAR* LanguageKey=TEXT("reader.lang");

// The colour components of a colour key: key.r／.g／.b／.a, else key.0–.3 (ok-extract's two spellings).
TArray<FString> ColorKeys(const FString& Key,const TMap<FString,TSharedPtr<FJsonObject>>& Rows)
{
	static const TCHAR* Names[]={TEXT("r"),TEXT("g"),TEXT("b"),TEXT("a")};
	TArray<FString> Out;
	for(int32 I=0;I<4;++I)
	{
		const FString Named=Key+TEXT(".")+Names[I],Numbered=Key+FString::Printf(TEXT(".%d"),I);
		Out.Add(Rows.Contains(Named)?Named:Rows.Contains(Numbered)?Numbered:FString());
	}
	return Out;
}

TMap<FString,TSharedPtr<FJsonObject>> RegistryRows(UOKCharacterController* G)
{
	TMap<FString,TSharedPtr<FJsonObject>> Rows;
	for(const TSharedPtr<FJsonValue>& V:OKCharacterMCPRegistry::Parameters(G))
		if(const TSharedPtr<FJsonObject> P=V.IsValid()?V->AsObject():nullptr){FString K;if(P->TryGetStringField(TEXT("key"),K))Rows.Add(K,P);}
	return Rows;
}

bool Write(UOKCharacterController* G,const FRows& Edits)
{
	FString Error;
	if(OKCharacterMCPRegistry::SetParameters(G,Edits,Error))return true;
	UE_LOG(LogTemp,Warning,TEXT("ok.ReaderScreen page item: %s"),*Error);
	return false;
}
TSharedPtr<FJsonValue> Edit(const FString& Key,const TSharedPtr<FJsonValue>& Value)
{
	auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("key"),Key);O->SetField(TEXT("value"),Value);
	return MakeShared<FJsonValueObject>(O);
}

FString Caption(const FItem& I){return I.LabelId.IsEmpty()?I.Label:OKReaderT(I.LabelId);}

template<class T> T* Make(UOKCharacterController* G,const FString& Hint)
{
	FString Name=TEXT("PageItem_")+Hint;
	for(TCHAR& C:Name)if(!FChar::IsAlnum(C)&&C!=TEXT('_'))C=TEXT('_');
	return G->WidgetTree->ConstructWidget<T>(T::StaticClass(),MakeUniqueObjectName(G->WidgetTree,T::StaticClass(),FName(*Name)));
}

bool Shown(const FItem& I){return I.Box.IsValid()&&I.Box->GetVisibility()!=ESlateVisibility::Collapsed&&I.Control.IsValid();}
}

bool OKReaderPageItems::IsItemKind(const FString& Kind)
{
	return Kind==TEXT("bool")||Kind==TEXT("toggle")||Kind==TEXT("choice")||Kind==TEXT("dropdown")||Kind==TEXT("color")||Kind==TEXT("text")||Kind==TEXT("button");
}

bool OKReaderPageItems::IsKnownAction(const FString& Action)
{
	static const TSet<FString> Known={TEXT("add_accessory_slot"),TEXT("apply_properties"),TEXT("reset_properties"),TEXT("tpose"),TEXT("walk"),
		TEXT("pause"),TEXT("replay"),TEXT("blink"),TEXT("reset_left_hand"),TEXT("reset_right_hand"),TEXT("speak")};
	// mod.<id>.<command>: a mod's button (its reader_ui page), run through the mod host.
	return Known.Contains(Action)||Action.StartsWith(TEXT("mod."));
}

bool OKReaderPageItems::RunAction(UOKCharacterController* G,const FString& Action,FString& Error)
{
	if(!G){Error=TEXT("no reader");return false;}
	if(Action==TEXT("add_accessory_slot"))G->OnAddAccessorySlot();
	else if(Action==TEXT("apply_properties"))G->OnApplyProperties();
	else if(Action==TEXT("reset_properties"))G->OnResetProperties();
	else if(Action==TEXT("tpose"))G->OnPoseTpose();
	else if(Action==TEXT("walk"))G->OnPoseWalk();
	else if(Action==TEXT("pause"))G->OnPausePlayback();
	else if(Action==TEXT("replay"))G->OnReplayPlayback();
	else if(Action==TEXT("blink"))G->OnForceBlink();
	else if(Action==TEXT("reset_left_hand"))G->OnResetLeftHand();
	else if(Action==TEXT("reset_right_hand"))G->OnResetRightHand();
	else if(Action==TEXT("speak"))G->OnSpeak();
	else if(Action.StartsWith(TEXT("mod.")))return OKReaderMods::RunCommand(G,Action,Error);
	else{Error=TEXT("unknown action ")+Action;return false;}
	return true;
}

UWidget* OKReaderPageItems::Build(UOKCharacterController* G,UVerticalBox*& Box,const TSharedPtr<FJsonObject>& Spec,FString& Error)
{
	if(!G||!G->WidgetTree||!G->ShapeBox||!Spec.IsValid()){Error=TEXT("讀卡器還沒準備好");return nullptr;}
	FItem I;
	Spec->TryGetStringField(TEXT("kind"),I.Kind);Spec->TryGetStringField(TEXT("key"),I.Key);Spec->TryGetStringField(TEXT("action"),I.Action);
	Spec->TryGetStringField(TEXT("label"),I.Label);Spec->TryGetStringField(TEXT("label_id"),I.LabelId);
	if(I.Kind==TEXT("toggle"))I.Kind=TEXT("bool");
	if(I.Kind==TEXT("dropdown"))I.Kind=TEXT("choice");
	if(!IsItemKind(I.Kind)){Error=TEXT("不認得的 kind ")+I.Kind;return nullptr;}
	if(I.Kind==TEXT("button"))
	{
		if(I.Action.IsEmpty()){Error=TEXT("button 要有 action");return nullptr;}
		if(!IsKnownAction(I.Action)){Error=TEXT("不認得的 action ")+I.Action;return nullptr;}
		if(I.Label.IsEmpty()&&I.LabelId.IsEmpty()){Error=TEXT("button 要有 label 或 label_id");return nullptr;}
	}
	else
	{
		if(I.Key.IsEmpty()){Error=I.Kind+TEXT(" 要有 key");return nullptr;}
		if(I.Key==LanguageKey&&I.Kind!=TEXT("choice")){Error=TEXT("reader.lang 只能是 choice");return nullptr;}
		if(I.Label.IsEmpty()&&I.LabelId.IsEmpty())I.Label=I.Key;
	}
	if(!Box)
	{
		Box=Make<UVerticalBox>(G,TEXT("Box"));
		G->ShapeBox->AddChild(Box);
		Box->SetVisibility(ESlateVisibility::Collapsed);
		GBoxes.Add(Box);
	}
	I.Box=Box;
	auto* Row=Make<UHorizontalBox>(G,I.Key.IsEmpty()?I.Action:I.Key);
	if(I.Kind==TEXT("button"))
	{
		auto* B=Make<UOKPageItemButton>(G,I.Action);B->Owner=G;B->Action=I.Action;
		auto* T=Make<UTextBlock>(G,I.Action+TEXT("_Text"));T->SetText(FText::FromString(Caption(I)));T->SetFont(FCoreStyle::GetDefaultFontStyle("Regular",14));
		B->SetContent(T);B->OnClicked.AddDynamic(B,&UOKPageItemButton::Clicked);
		Row->AddChildToHorizontalBox(B);
		I.Caption=T;I.Control=B;
	}
	else
	{
		auto* T=Make<UTextBlock>(G,I.Key+TEXT("_Caption"));T->SetText(FText::FromString(Caption(I)));T->SetAutoWrapText(true);
		T->SetToolTipText(FText::FromString(I.Key));T->SetFont(FCoreStyle::GetDefaultFontStyle("Regular",14));
		Row->AddChildToHorizontalBox(T)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		auto* Width=Make<USizeBox>(G,I.Key+TEXT("_Width"));Width->SetWidthOverride(170);Row->AddChild(Width);
		UWidget* Control=nullptr;
		if(I.Kind==TEXT("bool")){auto* C=Make<UOKPageItemToggle>(G,I.Key);C->Owner=G;C->Key=I.Key;C->OnCheckStateChanged.AddDynamic(C,&UOKPageItemToggle::Changed);Control=C;}
		else if(I.Kind==TEXT("choice")){auto* C=Make<UOKPageItemChoice>(G,I.Key);C->Owner=G;C->Key=I.Key;C->OnSelectionChanged.AddDynamic(C,&UOKPageItemChoice::Selected);Control=C;}
		else{auto* C=Make<UOKPageItemText>(G,I.Key);C->Owner=G;C->Key=I.Key;C->bColor=I.Kind==TEXT("color");
			if(C->bColor)C->SetHintText(FText::FromString(TEXT("#RRGGBBAA")));C->OnTextCommitted.AddDynamic(C,&UOKPageItemText::Committed);Control=C;}
		Width->SetContent(Control);
		I.Caption=T;I.Control=Control;
		// Disabled until the key has a value (Refresh).
		Control->SetIsEnabled(false);
	}
	Box->AddChild(Row);
	GItems.Add(I);
	return Row;
}

void OKReaderPageItems::ShowOnly(UVerticalBox* Box)
{
	for(const TWeakObjectPtr<UVerticalBox>& B:GBoxes)if(B.IsValid())B->SetVisibility(B.Get()==Box?ESlateVisibility::Visible:ESlateVisibility::Collapsed);
	GSinceRefresh=1.f;	// the page shows its values at once
}

void OKReaderPageItems::Refresh(UOKCharacterController* G,float DeltaSeconds)
{
	GSinceRefresh+=DeltaSeconds;
	if(!G||GSinceRefresh<.25f)return;
	GSinceRefresh=0.f;
	bool bAny=false,bRegistry=false;
	for(const FItem& I:GItems)if(Shown(I)){bAny=true;bRegistry|=I.Kind!=TEXT("button")&&I.Key!=LanguageKey;}
	if(!bAny)return;
	const TMap<FString,TSharedPtr<FJsonObject>> Rows=bRegistry?RegistryRows(G):TMap<FString,TSharedPtr<FJsonObject>>();
	for(const FItem& I:GItems)
	{
		if(!Shown(I)||I.Kind==TEXT("button"))continue;
		UWidget* W=I.Control.Get();
		if(I.Key==LanguageKey)
		{
			auto* C=Cast<UOKPageItemChoice>(W);if(!C)continue;
			C->bQuiet=true;
			if(C->GetOptionCount()!=OKReaderLanguages().Num()){C->ClearOptions();C->Values.Reset();for(const auto& L:OKReaderLanguages()){C->AddOption(L.Value);C->Values.Add(L.Value,L.Key);}}
			for(const auto& L:OKReaderLanguages())if(L.Key==OKReaderLanguage()&&C->GetSelectedOption()!=L.Value)C->SetSelectedOption(L.Value);
			C->bQuiet=false;C->SetIsEnabled(true);
			continue;
		}
		if(I.Kind==TEXT("color"))
		{
			auto* T=Cast<UOKPageItemText>(W);if(!T)continue;
			const TArray<FString> Keys=ColorKeys(I.Key,Rows);
			const bool bHave=!Keys[0].IsEmpty()&&!Keys[1].IsEmpty()&&!Keys[2].IsEmpty();
			T->SetIsEnabled(bHave);
			if(!bHave||T->HasKeyboardFocus())continue;
			uint8 C[4]={0,0,0,255};
			for(int32 K=0;K<4;++K)if(!Keys[K].IsEmpty()){double V=0;if(Rows[Keys[K]]->TryGetNumberField(TEXT("value"),V))C[K]=uint8(FMath::RoundToInt(FMath::Clamp(V,0.,1.)*255.));}
			const FString Hex=TEXT("#")+FColor(C[0],C[1],C[2],C[3]).ToHex();
			if(T->GetText().ToString()!=Hex)T->SetText(FText::FromString(Hex));
			continue;
		}
		const TSharedPtr<FJsonObject>* Row=Rows.Find(I.Key);
		bool bSupported=true;if(Row)(*Row)->TryGetBoolField(TEXT("supported"),bSupported);
		W->SetIsEnabled(Row&&bSupported);
		if(!Row)continue;
		const TSharedPtr<FJsonValue> Value=(*Row)->TryGetField(TEXT("value"));
		if(auto* B=Cast<UOKPageItemToggle>(W)){bool bOn=false;if(Value.IsValid()&&Value->TryGetBool(bOn)&&B->IsChecked()!=bOn)B->SetIsChecked(bOn);}
		else if(auto* C=Cast<UOKPageItemChoice>(W))
		{
			// The options: {value, label} (card properties) or plain strings (choices).
			TArray<TPair<FString,FString>> Options;
			const TArray<TSharedPtr<FJsonValue>>* List=nullptr;
			if((*Row)->TryGetArrayField(TEXT("options"),List))for(const auto& O:*List){const TSharedPtr<FJsonObject> Ob=O->AsObject();if(Ob.IsValid())Options.Emplace(Ob->GetStringField(TEXT("label")),Ob->GetStringField(TEXT("value")));}
			else if((*Row)->TryGetArrayField(TEXT("choices"),List))for(const auto& O:*List)Options.Emplace(O->AsString(),O->AsString());
			C->bQuiet=true;
			if(C->GetOptionCount()!=Options.Num()){C->ClearOptions();C->Values.Reset();for(const auto& O:Options){C->AddOption(O.Key);C->Values.Add(O.Key,O.Value);}}
			FString Now;if(Value.IsValid())Value->TryGetString(Now);
			for(const auto& O:Options)if(O.Value==Now&&C->GetSelectedOption()!=O.Key)C->SetSelectedOption(O.Key);
			C->bQuiet=false;
		}
		else if(auto* T=Cast<UOKPageItemText>(W)){FString Now;if(Value.IsValid()&&Value->TryGetString(Now)&&!T->HasKeyboardFocus()&&T->GetText().ToString()!=Now)T->SetText(FText::FromString(Now));}
	}
}

void OKReaderPageItems::Relabel()
{
	for(const FItem& I:GItems)if(I.Caption.IsValid())I.Caption->SetText(FText::FromString(Caption(I)));
}

void OKReaderPageItems::List(FOutputDevice& Out)
{
	for(const FItem& I:GItems)Out.Logf(TEXT("%-6s %-40s %s%s"),*I.Kind,I.Key.IsEmpty()?*I.Action:*I.Key,I.Control.IsValid()?*I.Control->GetName():TEXT("(gone)"),Shown(I)?TEXT(""):TEXT(" [not shown]"));
	Out.Logf(TEXT("%d page items"),GItems.Num());
}

void OKReaderPageItems::Reset()
{
	for(const TWeakObjectPtr<UVerticalBox>& B:GBoxes)if(B.IsValid())B->RemoveFromParent();
	GBoxes.Reset();GItems.Reset();
}

void UOKPageItemToggle::Changed(bool bNewChecked)
{
	if(UOKCharacterController* G=Owner.Get())Write(G,{Edit(Key,MakeShared<FJsonValueBoolean>(bNewChecked))});
}

void UOKPageItemChoice::Selected(FString Option,ESelectInfo::Type SelectionType)
{
	UOKCharacterController* G=Owner.Get();const FString* Value=Values.Find(Option);
	if(bQuiet||!G||!Value)return;
	if(Key==LanguageKey)
	{
		if(OKReaderSetLanguage(*Value)){OKReaderPageItems::Relabel();G->RebuildPropertyControls();}
		return;
	}
	Write(G,{Edit(Key,MakeShared<FJsonValueString>(*Value))});
}

void UOKPageItemText::Committed(const FText& Typed,ETextCommit::Type CommitType)
{
	UOKCharacterController* G=Owner.Get();
	if(!G||(CommitType!=ETextCommit::OnEnter&&CommitType!=ETextCommit::OnUserMovedFocus))return;
	if(!bColor){Write(G,{Edit(Key,MakeShared<FJsonValueString>(Typed.ToString()))});return;}
	FString Hex=Typed.ToString().TrimStartAndEnd();Hex.RemoveFromStart(TEXT("#"));
	bool bHex=Hex.Len()==6||Hex.Len()==8;for(TCHAR C:Hex)bHex&=FChar::IsHexDigit(C);
	if(!bHex){UE_LOG(LogTemp,Warning,TEXT("ok.ReaderScreen page item %s: %s is not #RRGGBB or #RRGGBBAA"),*Key,*Typed.ToString());return;}
	const FColor C=FColor::FromHex(Hex);const uint8 Channels[4]={C.R,C.G,C.B,C.A};
	const TArray<FString> Keys=ColorKeys(Key,RegistryRows(G));
	FRows Edits;
	for(int32 I=0;I<(Hex.Len()==8?4:3);++I)if(!Keys[I].IsEmpty())Edits.Add(Edit(Keys[I],MakeShared<FJsonValueNumber>(Channels[I]/255.)));
	if(Edits.Num())Write(G,Edits);
}

void UOKPageItemButton::Clicked()
{
	FString Error;
	if(!OKReaderPageItems::RunAction(Owner.Get(),Action,Error))UE_LOG(LogTemp,Warning,TEXT("ok.ReaderScreen page item: %s"),*Error);
}
