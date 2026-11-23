// The reader screen's mod pages (OK mod framework plan §6.13 D1, Docs/OK_MOD_HOOKS.md §4): each mod's reader.ui page is
// made here as DreamGUI controls (DUI/Reader/Controls/*.dui), bound straight to the mod's values -- shown from
// reader.values (OKReaderMods::Value), changed through reader.control (OKReaderMods::Set), the same road reader_call
// get/set takes. No UMG control stands behind them, so nothing is mirrored.
//
// Items: bool (toggle), choice (dropdown), radio, text (multiline, placeholder), number (a number box), slider, color
// ("#RRGGBB"), list (options to pick from, or a read-only list of lines), progress, label, image (a PNG in the mod's
// folder), button (a mod command), dui (the mod's own .dui panel, "widget": <name>; plan §6.13 D2). Containers: group (a title that folds, with "fold": true), row, tabs, scroll; a page
// and a group take "layout" (column, row, tabs, scroll). "style" names a text style of the theme (Theme.dui's preset):
// Title, Lead, Body, Caption, Overline, AccentText, GoodText, BadText, WarnText.

#include "OKReaderScreen.h"
#include "OKReaderMods.h"
#include "OKCharacterController.h"
#include "OKReaderText.h"
#include "OKModContent.h"
#include "OKModKeys.h"
#include "OKModDreamPanel.h"
#include "DreamUIBPLibrary.h"
#include "Core/DreamWidgetTree.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"
#include "Engine/Texture2D.h"
#include "ImageUtils.h"
#include "Misc/Paths.h"
#include "Core/Components/DreamWidget.h"
#include "Core/Components/DreamText.h"
#include "Core/Components/DreamImage.h"
#include "Core/Components/DreamRectBlock.h"
#include "Core/Components/DreamPanelSlot.h"
#include "Controls/DreamButton.h"
#include "Controls/DreamSlider.h"
#include "Controls/DreamToggle.h"
#include "Controls/DreamDropdown.h"
#include "Controls/DreamTextInput.h"
#include "Controls/DreamScrollBox.h"
#include "Controls/DreamSpinBox.h"
#include "Controls/DreamProgressBar.h"
#include "Controls/DreamRadioButton.h"
#include "Controls/DreamTabView.h"
#include "Controls/DreamListView.h"

static UDreamText* ModTextOf(UDreamWidget* W){return W?Cast<UDreamText>(W->GetVisual()):nullptr;}

namespace
{
using FItem=TSharedPtr<FJsonObject>;

FString Str(const FItem& I,const TCHAR* Field){FString S;I->TryGetStringField(Field,S);return S;}
double Num(const FItem& I,const TCHAR* Field,double Default){double N=Default;I->TryGetNumberField(Field,N);return N;}

// The apply-on-load switches are the reader's own setting, not a mod value (OKReaderMods::ApplyOnLoad).
TSharedPtr<FJsonValue> ValueOf(const FString& Key)
{
	if(OKReaderMods::IsApplyKey(Key))return MakeShared<FJsonValueBoolean>(OKReaderMods::ApplyOnLoad(Key.Mid(17)));
	return OKReaderMods::Value(Key);
}
bool SetValueOf(UOKCharacterController* G,const FString& Key,const TSharedPtr<FJsonValue>& V,FString& Error)
{
	if(OKReaderMods::IsApplyKey(Key)){OKReaderMods::SetApplyOnLoad(Key.Mid(17),V->AsBool());return true;}
	return OKReaderMods::Set(G,Key,V,Error);
}
FString AsText(const TSharedPtr<FJsonValue>& V)
{
	if(!V.IsValid()||V->Type==EJson::Null)return FString();
	if(V->Type==EJson::String)return V->AsString();
	if(V->Type==EJson::Number){const double N=V->AsNumber();return N==FMath::RoundToDouble(N)?FString::Printf(TEXT("%lld"),(long long)N):FString::SanitizeFloat(N);}
	if(V->Type==EJson::Boolean)return V->AsBool()?TEXT("true"):TEXT("false");
	return FString();
}
// An item's options: their values and the texts shown.
void OptionsOf(const FItem& I,TArray<FString>& Values,TArray<FString>& Labels)
{
	const TArray<TSharedPtr<FJsonValue>>* Options=nullptr;
	if(!I->TryGetArrayField(TEXT("options"),Options))return;
	for(const TSharedPtr<FJsonValue>& O:*Options)
	{
		if(!O.IsValid())continue;
		if(O->Type==EJson::String){Values.Add(O->AsString());Labels.Add(O->AsString());continue;}
		if(O->Type!=EJson::Object)continue;
		const FItem OO=O->AsObject();FString V=AsText(OO->TryGetField(TEXT("value")));
		FString L=OKReaderMods::ItemText(OO,TEXT("label"));if(L.IsEmpty())L=V;
		Values.Add(V);Labels.Add(L);
	}
}
// "#RRGGBB" (or RRGGBB, #RGB-less forms refused), normalised; false when it is not one.
bool ParseColor(const FString& In,FString& Out,FColor& Color)
{
	FString S=In.TrimStartAndEnd();if(S.StartsWith(TEXT("#")))S.RightChopInline(1);
	if(S.Len()!=6&&S.Len()!=8)return false;
	for(TCHAR C:S)if(!FChar::IsHexDigit(C))return false;
	Color=FColor::FromHex(S);Out=TEXT("#")+S.ToUpper();return true;
}
// The theme's text styles (Plugins/DreamGUI/DUI/Presets/Default.dui, the preset Theme.dui uses): colour and size.
bool TextStyle(const FString& Name,FColor& Color,float& Size)
{
	struct FStyle{const TCHAR* Name;uint32 Rgb;float Size;};
	static const FStyle Styles[]={
		{TEXT("Heading"),0xE7E9EE,44},{TEXT("Title"),0xE7E9EE,30},{TEXT("Lead"),0xE7E9EE,24},{TEXT("Body"),0xA7AEBB,20},
		{TEXT("Caption"),0x878E9C,16},{TEXT("Overline"),0x878E9C,16},{TEXT("Figure"),0xE7E9EE,30},{TEXT("AccentText"),0x7EA6D0,20},
		{TEXT("GoodText"),0x7DB392,20},{TEXT("BadText"),0xD07C74,20},{TEXT("WarnText"),0xD6B06A,20}};
	for(const FStyle& S:Styles)if(Name==S.Name){Color=FColor((S.Rgb>>16)&255,(S.Rgb>>8)&255,S.Rgb&255);Size=S.Size;return true;}
	return false;
}
void FixHeight(UDreamWidget* W,float Height)
{
	if(UDreamPanelSlot* Slot=W?W->GetPanelSlot():nullptr){Slot->SetMinDesiredSize(FVector2D(0,Height));Slot->SetMaxDesiredSize(FVector2D(0,Height));}
}
void Fill(UDreamWidget* W){if(UDreamPanelSlot* Slot=W?W->GetPanelSlot():nullptr)Slot->SetSizeRule(EDreamPanelSizeRule::Fill);}
}

void UOKReaderScreen::AddModCategory()
{
	UOKCharacterController* G=Controller.Get();
	if(!G||!OKReaderMods::Active())return;
	FCategory Mods;Mods.Name=TEXT("Mods");Mods.Tab=3;
	auto AddPage=[&](const FString& Name,const FItem& Spec)
	{
		FGroup Out;Out.Name=Name;
		// Built when the page opens (and again each time): the page is a group with no title of its own.
		Out.Build=[this,Name,Spec](UDreamWidget* Page)
		{
			auto Group=MakeShared<FJsonObject>(*Spec);Group->SetStringField(TEXT("kind"),TEXT("group"));
			Group->RemoveField(TEXT("label"));Group->RemoveField(TEXT("label_id"));
			BuildModItem(Page,Group,TEXT("Mods›")+Name,false);
		};
		Mods.Groups.Add(MoveTemp(Out));
	};
	// "Apply on load" first: one switch per mod that reads card data (MakerLoadToggle's counterpart).
	{
		TArray<TSharedPtr<FJsonValue>> Switches;
		for(const auto& M:OKReaderMods::CardMods())
		{
			auto S=MakeShared<FJsonObject>();S->SetStringField(TEXT("kind"),TEXT("bool"));S->SetStringField(TEXT("key"),TEXT("reader.mod_apply.")+M.Key);
			S->SetStringField(TEXT("label"),M.Value.IsEmpty()?M.Key:M.Value);Switches.Add(MakeShared<FJsonValueObject>(S));
		}
		if(Switches.Num()){auto Page=MakeShared<FJsonObject>();Page->SetArrayField(TEXT("items"),Switches);AddPage(OKReaderT(TEXT("reader.mods.apply_on_load")),Page);}
	}
	// Mod hotkeys (FOKModKeys, Docs/OK_MOD_HOOKS.md §9): one row per key, its button waits for the new chord.
	{
		TArray<TSharedPtr<FJsonValue>> Keys;
		for(const FOKModKeys::FHotkey& K:FOKModKeys::List())
		{
			auto S=MakeShared<FJsonObject>();S->SetStringField(TEXT("kind"),TEXT("hotkey"));S->SetStringField(TEXT("mod"),K.Mod);S->SetStringField(TEXT("name"),K.Name);
			S->SetStringField(TEXT("label_id"),K.DescriptionId);S->SetStringField(TEXT("label"),K.Mod+TEXT(" ")+K.Name);Keys.Add(MakeShared<FJsonValueObject>(S));
		}
		if(Keys.Num()){auto Page=MakeShared<FJsonObject>();Page->SetArrayField(TEXT("items"),Keys);AddPage(OKReaderT(TEXT("reader.mods.hotkeys")),Page);}
	}
	for(const OKReaderMods::FPage& Page:OKReaderMods::Pages())
	{
		FItem Spec=Page.Spec;
		if(!Spec.IsValid()){Spec=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Items;for(const FItem& I:Page.Items)Items.Add(MakeShared<FJsonValueObject>(I));Spec->SetArrayField(TEXT("items"),Items);}
		AddPage(Page.Name.IsEmpty()?Page.Mod:Page.Name,Spec);
	}
	if(Mods.Groups.Num())Categories.Add(MoveTemp(Mods));
}

float UOKReaderScreen::BuildModItems(UDreamWidget* Into,const TArray<TSharedPtr<FJsonValue>>& Items,const FString& Where,bool bRow)
{
	float Height=0;int32 Count=0;
	for(const TSharedPtr<FJsonValue>& V:Items)
	{
		if(!V.IsValid()||V->Type!=EJson::Object){PagesErrors.Add(Where+TEXT("：項目不是物件，略過"));continue;}
		const float H=BuildModItem(Into,V->AsObject(),Where,bRow);
		Height=bRow?FMath::Max(Height,H):Height+H;++Count;
	}
	if(!bRow&&Count>1)Height+=8.f*(Count-1);
	return Height;
}

UDreamWidget* UOKReaderScreen::ModRow(UDreamWidget* Into,const FItem& Item,bool bRow)
{
	const FString Label=OKReaderMods::ItemText(Item,TEXT("label"));
	if(Label.IsEmpty())return Into;
	UDreamWidget* Row=MakePanel(Into,true,8.f);
	if(UOKDreamControl* Caption=MakeControl(TEXT("Label"),Row))
	{
		Caption->FixedText=Label;Caption->SetText(Label);
		Caption->SetWidth(bRow?FMath::Max(48.f,FMath::Min(160.f,Label.Len()*18.f)):CaptionWidth());
		if(UDreamText* T=ModTextOf(Caption->Label)){T->SetAutoWrapText(false);T->SetOverflowType(EDreamUITextOverflowType::Ellipsis);}
	}
	if(bRow)Fill(Row);
	return Row;
}

float UOKReaderScreen::BuildModItem(UDreamWidget* Into,const FItem& Item,const FString& Where,bool bRow)
{
	UOKCharacterController* G=Controller.Get();
	if(!G||!Into||!Item.IsValid())return 0;
	FString Kind=Str(Item,TEXT("kind"));if(Kind==TEXT("toggle"))Kind=TEXT("bool");if(Kind==TEXT("dropdown"))Kind=TEXT("choice");
	const FString Key=Str(Item,TEXT("key"));
	const FString Label=OKReaderMods::ItemText(Item,TEXT("label"));
	const FString Here=Where+TEXT("›")+(Label.IsEmpty()?(Key.IsEmpty()?Kind:Key):Label);
	TWeakObjectPtr<UOKCharacterController> WeakG(G);
	auto Bad=[&](const FString& Why){PagesErrors.Add(Here+TEXT("：")+Why);return 0.f;};
	// A value control's Push: the typed value made the mod's JSON value, then reader.control.
	auto PushJson=[WeakG,Key](const TSharedPtr<FJsonValue>& V,FString& Why){return SetValueOf(WeakG.Get(),Key,V,Why);};
	auto NeedKey=[&](){if(Key.IsEmpty()){Bad(TEXT("沒有 key"));return false;}return true;};

	// ---------------------------------------------------------------------------------------------- containers
	const TArray<TSharedPtr<FJsonValue>>* Kids=nullptr;
	if(Kind==TEXT("group")||Kind==TEXT("row")||Kind==TEXT("tabs")||Kind==TEXT("scroll"))
	{
		static const TArray<TSharedPtr<FJsonValue>> None;
		const TArray<TSharedPtr<FJsonValue>>& Items=Item->TryGetArrayField(TEXT("items"),Kids)?*Kids:None;
		FString Layout=Str(Item,TEXT("layout"));
		if(Kind!=TEXT("group"))Layout=Kind;
		if(Layout.IsEmpty())Layout=TEXT("column");
		float Height=0;UDreamWidget* Host=Into;
		// A titled group: a header that folds the rest away ("fold": true), or a caption line over it.
		if(Kind==TEXT("group")&&!Label.IsEmpty())
		{
			UDreamWidget* Box=MakePanel(Into,false,8.f);
			const bool bFold=Item->HasTypedField<EJson::Boolean>(TEXT("fold"))&&Item->GetBoolField(TEXT("fold"));
			UOKDreamControl* Head=MakeControl(bFold?TEXT("Drawer"):TEXT("Label"),Box);
			if(Head){Head->FixedText=Label;Head->SetText(Label);Height+=Head->GetSizeDelta().Y+8.f;}
			if(!bFold)if(UDreamText* T=Head?ModTextOf(Head->Label):nullptr){FColor C;float S;if(TextStyle(TEXT("Lead"),C,S)){T->SetColor(C);T->SetFontSize(S);}}
			Host=MakePanel(Box,false,8.f);
			if(bFold&&Head){Head->Body=Host;Head->SetOpen(!(Item->HasTypedField<EJson::Boolean>(TEXT("folded"))&&Item->GetBoolField(TEXT("folded"))));}
		}
		if(Layout==TEXT("row"))
		{
			UDreamWidget* Row=MakePanel(Host,true,8.f);
			return Height+BuildModItems(Row,Items,Here,true);
		}
		if(Layout==TEXT("scroll"))
		{
			UOKDreamControl* C=MakeControl(TEXT("Scroll"),Host);if(!C||!C->Scroll)return Bad(TEXT("捲動區 WBP_OKScroll 不在"));
			const float Box=FMath::Clamp((float)Num(Item,TEXT("height"),240),60.f,1200.f);
			FixHeight(C,Box);
			UDreamWidget* Inside=MakePanel(nullptr,false,8.f);C->Scroll->AddContent(Inside);
			BuildModItems(Inside,Items,Here,false);
			return Height+Box;
		}
		if(Layout==TEXT("tabs"))
		{
			UOKDreamControl* C=MakeControl(TEXT("Tabs"),Host);if(!C||!C->Tabs)return Bad(TEXT("分頁 WBP_OKTabs 不在"));
			TArray<FText> Labels;float Tallest=0;
			for(const TSharedPtr<FJsonValue>& V:Items)
			{
				if(!V.IsValid()||V->Type!=EJson::Object){Bad(TEXT("分頁不是物件，略過"));continue;}
				const FItem TabSpec=V->AsObject();
				FString Name=OKReaderMods::ItemText(TabSpec,TEXT("label"));if(Name.IsEmpty())Name=OKReaderMods::ItemText(TabSpec,TEXT("name"));
				if(Name.IsEmpty())Name=FString::Printf(TEXT("%d"),Labels.Num()+1);
				UDreamWidget* Page=MakePanel(nullptr,false,8.f);C->Tabs->AddPage(Page);Labels.Add(FText::FromString(Name));
				// Each tab is its child's content: a group's items (its title is the tab), or the one item itself.
				const TArray<TSharedPtr<FJsonValue>>* TabItems=nullptr;
				if(Str(TabSpec,TEXT("kind"))==TEXT("group")&&TabSpec->TryGetArrayField(TEXT("items"),TabItems))
				{
					auto Inner=MakeShared<FJsonObject>(*TabSpec);Inner->RemoveField(TEXT("label"));Inner->RemoveField(TEXT("label_id"));
					Tallest=FMath::Max(Tallest,BuildModItem(Page,Inner,Here+TEXT("›")+Name,false));
				}
				else Tallest=FMath::Max(Tallest,BuildModItem(Page,TabSpec,Here,false));
			}
			C->Tabs->SetTabLabels(Labels);
			// As tall as its tallest page under the strip: the page column does not grow the tab view by itself.
			const float Box=FMath::Max((float)Num(Item,TEXT("height"),0),Tallest+64.f);
			FixHeight(C,Box);
			return Height+Box;
		}
		return Height+BuildModItems(Host,Items,Here,false);
	}

	// ---------------------------------------------------------------------------------------------- shown only
	if(Kind==TEXT("label"))
	{
		UOKDreamControl* C=MakeControl(TEXT("Label"),Into);if(!C)return 0;
		const FString Fixed=OKReaderMods::ItemText(Item,TEXT("text"));
		if(UDreamText* T=ModTextOf(C->Label)){FColor Color;float Size;const FString Style=Str(Item,TEXT("style"));
			if(TextStyle(Style,Color,Size)){T->SetColor(Color);T->SetFontSize(Size);}else if(!Style.IsEmpty())Bad(TEXT("沒有這個文字樣式 ")+Style);}
		if(bRow)Fill(C);
		// A long text wraps: its height follows (the label's designed 30 is one line).
		if(UDreamPanelSlot* Slot=C->GetPanelSlot())Slot->SetMaxDesiredSize(FVector2D::ZeroVector);
		if(Key.IsEmpty()){C->FixedText=Fixed;C->SetText(Fixed);}
		else C->Pull=[Key,Fixed](UOKDreamControl& Self){const FString V=AsText(ValueOf(Key));Self.SetText(Fixed.IsEmpty()?V:Fixed+V);};
		if(!Key.IsEmpty())C->PullNow();
		const float Line=26.f,Width=FMath::Max(120.f,LeftWidth-80.f);
		return FMath::Max(30.f,Line*FMath::CeilToFloat(FMath::Max(1,Fixed.Len()+8)*18.f/Width));
	}
	if(Kind==TEXT("progress"))
	{
		UDreamWidget* Row=ModRow(Into,Item,bRow);
		UOKDreamControl* C=MakeControl(TEXT("Progress"),Row);if(!C||!C->Progress)return Bad(TEXT("進度條 WBP_OKProgress 不在"));
		Fill(C);
		const double Lo=Num(Item,TEXT("min"),0),Hi=Num(Item,TEXT("max"),1);
		const double Fixed=Num(Item,TEXT("value"),0);
		C->Pull=[Key,Lo,Hi,Fixed](UOKDreamControl& Self)
		{
			const TSharedPtr<FJsonValue> V=Key.IsEmpty()?nullptr:ValueOf(Key);
			const double N=V.IsValid()&&V->Type==EJson::Number?V->AsNumber():Fixed;
			const float P=Hi>Lo?float(FMath::Clamp((N-Lo)/(Hi-Lo),0.0,1.0)):0.f;
			if(!FMath::IsNearlyEqual(Self.Progress->GetPercent(),P,1e-4f))Self.Progress->SetPercent(P);
		};
		C->PullNow();
		return 36;
	}
	if(Kind==TEXT("image"))
	{
		const FString File=Str(Item,TEXT("image"));
		if(File.IsEmpty())return Bad(TEXT("圖片不在 mod 的資料夾裡（或檔案不存在）"));
		UTexture2D* Texture=nullptr;
		if(TObjectPtr<UTexture2D>* Known=ModPictures.Find(File))Texture=*Known;
		else{Texture=FImageUtils::ImportFileAsTexture2D(File);if(Texture)ModPictures.Add(File,Texture);}
		if(!Texture)return Bad(TEXT("讀不了圖片 ")+FPaths::GetCleanFilename(File));
		UOKDreamControl* C=MakeControl(TEXT("Image"),Into);if(!C||!C->Picture)return 0;
		if(auto* Image=Cast<UDreamImage>(C->Picture->GetVisual())){FDreamUIImageBrush Brush=Image->GetBrush();Brush.SetResourceObject(Texture);Image->SetBrush(Brush);}
		// Its own size, or the width and height the mod asks for, kept to the column.
		float W=(float)Num(Item,TEXT("width"),Texture->GetSizeX()),H=(float)Num(Item,TEXT("height"),0);
		W=FMath::Clamp(W,8.f,FMath::Max(64.f,LeftWidth-80.f));
		if(H<=0)H=W*Texture->GetSizeY()/FMath::Max(1,Texture->GetSizeX());
		H=FMath::Clamp(H,8.f,1200.f);
		// Both sides fixed: a width alone was taken as a minimum and the column squeezed the picture narrow.
		C->SetWidth(W);if(UDreamPanelSlot* Slot=C->GetPanelSlot()){Slot->SetMinDesiredSize(FVector2D(W,H));Slot->SetMaxDesiredSize(FVector2D(W,H));}
		if(UDreamPanelSlot* Slot=C->GetPanelSlot())Slot->SetHorizontalAlignment(EDreamPanelHorizontalAlignment::Left);
		return H;
	}
	// A mod's own .dui panel, cooked into its pak (OKModContent::Widget checks it); it reaches only this mod's values
	// (Mod.Text/Number/Flag) and this mod's ui.<id>.* hooks (Mod.Emit).
	if(Kind==TEXT("dui"))
	{
		const FString Mod=Str(Item,TEXT("mod")),Widget=Str(Item,TEXT("widget"));
		if(Mod.IsEmpty()||Widget.IsEmpty())return Bad(TEXT("dui 需要 widget"));
		UClass* Class=OKModContent::Widget(Mod,Widget);
		if(!Class)return Bad(TEXT("面板 ")+Widget+TEXT(" 不能用（mod 的內容沒載入或沒通過檢查，見 log）"));
		auto* Panel=Cast<UOKModDreamPanel>(UDreamUIBPLibrary::CreateDreamWidgetOfClass(this,Class));
		if(!Panel)return Bad(TEXT("面板 ")+Widget+TEXT(" 建立失敗"));
		UOKModDreamBridge* Bridge=NewObject<UOKModDreamBridge>(Panel);
		Bridge->ModId=Mod;
		Bridge->OnRead=[Mod](const FString& K){return AsText(OKReaderMods::Value(TEXT("mod.")+Mod+TEXT(".")+K));};
		Bridge->OnEmit=[WeakG,Mod](const FString& Event,const FString& Value)
		{
			FString Error;
			if(!OKReaderMods::Emit(WeakG.Get(),Mod,Event,Value,Error))UE_LOG(LogTemp,Warning,TEXT("ok.ReaderScreen: ui.%s.%s: %s"),*Mod,*Event,*Error);
		};
		Panel->Mod=Bridge;
		// Its designed size (the .dui root's), the height the mod asks for winning; the root fills it.
		FVector2D Natural(LeftWidth-80.f,200.f);
		if(UDreamWidget* Root=Panel->GetWidgetTree()?Panel->GetWidgetTree()->GetRootWidget():nullptr)
		{
			if(Root->GetSizeDelta().Y>0)Natural=Root->GetSizeDelta();
			Root->SetAnchorMin(FVector2D(0,0));Root->SetAnchorMax(FVector2D(1,1));Root->SetAnchoredPosition(FVector2D::ZeroVector);Root->SetSizeDelta(FVector2D::ZeroVector);
		}
		const float H=FMath::Clamp((float)Num(Item,TEXT("height"),Natural.Y),20.f,1200.f);
		Panel->SetSizeDelta(FVector2D(Natural.X,H));
		AddToHost(Into,Panel,false);
		if(UDreamPanelSlot* Slot=Panel->GetPanelSlot()){Slot->SetMinDesiredSize(FVector2D(0,H));Slot->SetMaxDesiredSize(FVector2D(0,H));}
		if(bRow)Fill(Panel);
		return H;
	}
	if(Kind==TEXT("hotkey"))
	{
		// The key shown on a button; pressing it waits for the next chord (Escape keeps the old one, Backspace unbinds).
		const FString Mod=Str(Item,TEXT("mod")),Name=Str(Item,TEXT("name"));
		if(Mod.IsEmpty()||Name.IsEmpty())return Bad(TEXT("熱鍵沒有 mod／name"));
		UDreamWidget* Row=ModRow(Into,Item,bRow);
		auto Shown=[Mod,Name]()
		{
			for(const FOKModKeys::FHotkey& K:FOKModKeys::List())if(K.Mod==Mod&&K.Name==Name)return FOKModKeys::Display(K.Chord);
			return FString(TEXT("—"));
		};
		TSharedRef<TWeakObjectPtr<UOKDreamControl>> Self=MakeShared<TWeakObjectPtr<UOKDreamControl>>();
		UOKDreamControl* C=MakeOwnButton(Row,Shown(),[Mod,Name,Self,Shown]()
		{
			if(UOKDreamControl* B=Self->Get()){B->FixedText=OKReaderT(TEXT("reader.mods.press_key"));B->SetText(B->FixedText);}
			FOKModKeys::Capture(Mod,Name,[Self,Shown](const FString&,bool){if(UOKDreamControl* B=Self->Get()){B->FixedText=Shown();B->SetText(B->FixedText);}});
		});
		*Self=C;
		if(C)Fill(C);
		return C?C->GetSizeDelta().Y:0;
	}
	if(Kind==TEXT("button"))
	{
		const FString Action=Str(Item,TEXT("action"));
		if(Action.IsEmpty())return Bad(TEXT("按鈕沒有 action"));
		UOKDreamControl* C=MakeOwnButton(Into,Label.IsEmpty()?Action:Label,[WeakG,Action]()
		{
			FString Error;
			if(!OKReaderMods::RunCommand(WeakG.Get(),Action,Error))UE_LOG(LogTemp,Warning,TEXT("ok.ReaderScreen: %s: %s"),*Action,*Error);
		});
		if(C&&bRow)Fill(C);
		return C?C->GetSizeDelta().Y:0;
	}

	// ---------------------------------------------------------------------------------------------- values
	if(Kind==TEXT("bool"))
	{
		if(!NeedKey())return 0;
		UOKDreamControl* C=MakeControl(TEXT("Toggle"),Into);if(!C||!C->Toggle)return 0;
		C->Pull=[Key,Label](UOKDreamControl& Self)
		{
			Self.SetText(Label);
			const TSharedPtr<FJsonValue> V=ValueOf(Key);const bool bOn=V.IsValid()&&V->Type==EJson::Boolean&&V->AsBool();
			if(Self.Toggle->GetIsOn()!=bOn)Self.Toggle->SetIsOn(bOn);
		};
		C->Push=[PushJson](const FString& V,FString& Why){return PushJson(MakeShared<FJsonValueBoolean>(V==TEXT("1")),Why);};
		C->PullNow();
		if(bRow)Fill(C);
		return C->GetSizeDelta().Y;
	}
	if(Kind==TEXT("choice")||Kind==TEXT("radio")||Kind==TEXT("list"))
	{
		if(!NeedKey())return 0;
		TArray<FString> Values,Labels;OptionsOf(Item,Values,Labels);
		if(Kind==TEXT("radio"))
		{
			if(Values.IsEmpty())return Bad(TEXT("單選沒有 options"));
			UDreamWidget* Row=ModRow(Into,Item,bRow);
			UDreamWidget* Group=MakePanel(Row,Item->HasTypedField<EJson::String>(TEXT("layout"))&&Str(Item,TEXT("layout"))==TEXT("column")?false:true,12.f);
			if(Row!=Into)Fill(Group);
			for(int32 I=0;I<Values.Num();++I)
			{
				UOKDreamControl* C=MakeControl(TEXT("Radio"),Group);if(!C||!C->Radio)continue;
				const FString Value=Values[I],Text=Labels[I];
				C->FixedText=Text;C->SetText(Text);C->SetWidth(FMath::Max(64.f,Text.Len()*18.f+44.f));
				C->Pull=[Key,Value](UOKDreamControl& Self){const bool bOn=AsText(ValueOf(Key))==Value;if(Self.Radio->GetIsOn()!=bOn)Self.Radio->SetIsOn(bOn);};
				C->Push=[PushJson,Value](const FString& V,FString& Why){return V==TEXT("1")?PushJson(MakeShared<FJsonValueString>(Value),Why):true;};
				C->PullNow();
			}
			return 36;
		}
		if(Kind==TEXT("choice"))
		{
			if(Values.IsEmpty())return Bad(TEXT("選單沒有 options"));
			UDreamWidget* Row=ModRow(Into,Item,bRow);
			UOKDreamControl* C=MakeControl(TEXT("Choice"),Row);if(!C||!C->Choice)return 0;
			Fill(C);
			TArray<FText> Texts;for(const FString& L:Labels)Texts.Add(FText::FromString(L));
			C->Choice->SetOptions(Texts);C->BoundOptions=Labels;
			C->Pull=[Key,Values](UOKDreamControl& Self){const int32 I=Values.IndexOfByKey(AsText(ValueOf(Key)));if(Self.Choice->GetSelectedIndex()!=I)Self.Choice->SetSelectedIndex(I);};
			C->Push=[PushJson,Values](const FString& V,FString& Why)
			{
				const int32 I=FCString::Atoi(*V);if(!Values.IsValidIndex(I)){Why=TEXT("no option ")+V;return false;}
				return PushJson(MakeShared<FJsonValueString>(Values[I]),Why);
			};
			C->PullNow();
			return C->GetSizeDelta().Y;
		}
		// A list: options to pick from, or (none) the lines the value holds, read only.
		if(!Label.IsEmpty())if(UOKDreamControl* Caption=MakeControl(TEXT("Label"),Into)){Caption->FixedText=Label;Caption->SetText(Label);}
		UOKDreamControl* C=MakeControl(TEXT("List"),Into);if(!C||!C->List)return 0;
		const float Box=FMath::Clamp((float)Num(Item,TEXT("height"),180),60.f,1200.f);
		FixHeight(C,Box);
		const bool bPick=!Values.IsEmpty();
		if(bPick)
		{
			TArray<FText> Texts;for(const FString& L:Labels)Texts.Add(FText::FromString(L));
			C->List->SetItems(Texts);C->BoundOptions=Labels;
			C->Push=[PushJson,Values](const FString& V,FString& Why)
			{
				const int32 I=FCString::Atoi(*V);if(!Values.IsValidIndex(I)){Why=TEXT("no option ")+V;return false;}
				return PushJson(MakeShared<FJsonValueString>(Values[I]),Why);
			};
		}
		C->Pull=[Key,Values,bPick](UOKDreamControl& Self)
		{
			const TSharedPtr<FJsonValue> V=ValueOf(Key);
			if(bPick){const int32 I=Values.IndexOfByKey(AsText(V));if(Self.List->GetSelectedIndex()!=I)Self.List->SetSelectedIndexWithoutNotify(I);return;}
			TArray<FString> Lines;
			if(V.IsValid()&&V->Type==EJson::Array)for(const TSharedPtr<FJsonValue>& L:V->AsArray())Lines.Add(AsText(L));
			if(Lines!=Self.BoundOptions)
			{
				Self.BoundOptions=Lines;TArray<FText> Texts;for(const FString& L:Lines)Texts.Add(FText::FromString(L));
				Self.List->SetItems(Texts);
			}
		};
		C->PullNow();
		return Box+(Label.IsEmpty()?0.f:38.f);
	}
	if(Kind==TEXT("text"))
	{
		if(!NeedKey())return 0;
		const bool bMulti=Item->HasTypedField<EJson::Boolean>(TEXT("multiline"))&&Item->GetBoolField(TEXT("multiline"));
		// A multi-line field gets its own line under the caption; one line sits beside it.
		UDreamWidget* Row=bMulti?Into:ModRow(Into,Item,bRow);
		if(bMulti&&!Label.IsEmpty())if(UOKDreamControl* Caption=MakeControl(TEXT("Label"),Into)){Caption->FixedText=Label;Caption->SetText(Label);}
		UOKDreamControl* C=MakeControl(TEXT("Input"),Row);if(!C||!C->Input)return 0;
		Fill(C);
		float Box=C->GetSizeDelta().Y;
		if(bMulti){C->Input->SetMultiLine(true);Box=FMath::Clamp((float)Num(Item,TEXT("height"),120),60.f,800.f);FixHeight(C,Box);}
		const FString Hint=OKReaderMods::ItemText(Item,TEXT("placeholder"));if(!Hint.IsEmpty())C->Input->SetPlaceholder(FText::FromString(Hint));
		if(Item->HasTypedField<EJson::Number>(TEXT("max_length")))C->Input->SetMaxLength(Item->GetIntegerField(TEXT("max_length")));
		// Only what the mod changed is shown: text typed and not yet committed stays.
		TSharedRef<FString> Last=MakeShared<FString>(TEXT("\x1"));
		C->Pull=[Key,Last](UOKDreamControl& Self){const FString V=AsText(ValueOf(Key));if(V!=*Last){*Last=V;Self.Input->SetText(V);}};
		C->Push=[PushJson](const FString& V,FString& Why){return PushJson(MakeShared<FJsonValueString>(V),Why);};
		C->PullNow();
		return Box+(bMulti&&!Label.IsEmpty()?38.f:0.f);
	}
	if(Kind==TEXT("color"))
	{
		if(!NeedKey())return 0;
		UDreamWidget* Row=ModRow(Into,Item,bRow);
		UOKDreamControl* C=MakeControl(TEXT("Color"),Row);if(!C||!C->Input)return 0;
		Fill(C);C->Input->SetPlaceholder(FText::FromString(TEXT("#RRGGBB")));
		TSharedRef<FString> Last=MakeShared<FString>(TEXT("\x1"));
		C->Pull=[Key,Last](UOKDreamControl& Self)
		{
			const FString V=AsText(ValueOf(Key));if(V==*Last)return;*Last=V;
			Self.Input->SetText(V);FString Norm;FColor Color;
			// The swatch is the colour itself: its body, not a tint over the card face (which multiplied it to near black).
			if(auto* Rect=Self.Swatch?Cast<UDreamRectBlock>(Self.Swatch->GetVisual()):nullptr){Rect->SetEnableBodyGradient(false);Rect->SetBodyColor(ParseColor(V,Norm,Color)?Color:FColor(0,0,0,0));}
		};
		C->Push=[PushJson](const FString& V,FString& Why)
		{
			FString Norm;FColor Color;if(!ParseColor(V,Norm,Color)){Why=TEXT("a colour is #RRGGBB");return false;}
			return PushJson(MakeShared<FJsonValueString>(Norm),Why);
		};
		C->PullNow();
		return C->GetSizeDelta().Y;
	}
	if(Kind.IsEmpty()||Kind==TEXT("number")||Kind==TEXT("slider"))
	{
		if(!NeedKey())return 0;
		const double Lo=Num(Item,TEXT("min"),0),Hi=FMath::Max(Lo,Num(Item,TEXT("max"),Kind==TEXT("slider")?1:100)),Step=Num(Item,TEXT("step"),0);
		const bool bWhole=Step>=1&&Step==FMath::RoundToDouble(Step);
		UDreamWidget* Row=ModRow(Into,Item,bRow);
		auto Push=[PushJson,bWhole](const FString& V,FString& Why){const double N=FCString::Atod(*V);return PushJson(MakeShared<FJsonValueNumber>(bWhole?FMath::RoundToDouble(N):N),Why);};
		TSharedRef<double> Last=MakeShared<double>(TNumericLimits<double>::Max());
		if(Kind==TEXT("slider"))
		{
			UOKDreamControl* C=MakeControl(TEXT("Slider"),Row);if(!C||!C->Slider)return 0;
			Fill(C);C->Slider->SetMinValue(float(Lo));C->Slider->SetMaxValue(float(Hi));
			if(Step>0){C->Slider->SetStepSize(float(Step));C->Slider->SetMouseUsesStep(true);}
			C->Slider->SetWholeNumbers(bWhole&&Step==1);
			// The value beside it.
			UOKDreamControl* ValueLabel=Row!=Into?MakeControl(TEXT("Label"),Row):nullptr;
			if(ValueLabel)ValueLabel->SetWidth(64.f);
			TWeakObjectPtr<UOKDreamControl> WeakShown(ValueLabel);
			C->Pull=[Key,Last,WeakShown](UOKDreamControl& Self)
			{
				const TSharedPtr<FJsonValue> V=ValueOf(Key);const double N=V.IsValid()&&V->Type==EJson::Number?V->AsNumber():0;
				if(N==*Last)return;*Last=N;Self.Slider->SetValue(float(N));
				if(UOKDreamControl* S=WeakShown.Get())S->SetText(AsText(MakeShared<FJsonValueNumber>(FMath::RoundToDouble(N*1000)/1000)));
			};
			C->Push=Push;C->PullNow();
			return C->GetSizeDelta().Y;
		}
		UOKDreamControl* C=MakeControl(TEXT("Spin"),Row);if(!C||!C->Spin)return 0;
		Fill(C);C->Spin->SetMinValue(float(Lo));C->Spin->SetMaxValue(float(Hi));C->Spin->SetMinSliderValue(float(Lo));C->Spin->SetMaxSliderValue(float(Hi));
		if(Step>0)C->Spin->SetStepSize(float(Step));
		C->Pull=[Key,Last](UOKDreamControl& Self)
		{
			const TSharedPtr<FJsonValue> V=ValueOf(Key);const double N=V.IsValid()&&V->Type==EJson::Number?V->AsNumber():0;
			if(N==*Last)return;*Last=N;Self.Spin->SetValue(float(N));
		};
		C->Push=Push;C->PullNow();
		return C->GetSizeDelta().Y;
	}
	return Bad(TEXT("不認得的種類 ")+Kind);
}
