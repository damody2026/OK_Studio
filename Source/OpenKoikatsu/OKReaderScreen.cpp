#include "OKReaderScreen.h"
#include "OKCharacterController.h"
#include "OKCardListView.h"
#include "KKShapeRows.h"
#include "OKShapeSlider.h"
#include "Components/VerticalBox.h"
#include "KKPreviewActor.h"
#include "Components/PoseableMeshComponent.h"
#include "Core/Components/DreamWidget.h"
#include "Core/DreamUIBehaviour.h"
#include "Core/DreamWidgetTree.h"
#include "Core/Components/DreamText.h"
#include "Core/Components/DreamImage.h"
#include "Core/Components/DreamCanvas.h"
#include "Core/Components/DreamPanelLayouts.h"
#include "Core/Components/DreamPanelSlot.h"
#include "Core/DreamScreenUISubsystem.h"
#include "DreamUIBPLibrary.h"
#include "Controls/DreamButton.h"
#include "Controls/DreamSlider.h"
#include "Controls/DreamToggle.h"
#include "Controls/DreamDropdown.h"
#include "Controls/DreamTextInput.h"
#include "Controls/DreamScrollBox.h"
#include "Event/DreamEventSystem.h"
#include "Components/Button.h"
#include "Components/Slider.h"
#include "Components/CheckBox.h"
#include "Components/ComboBoxString.h"
#include "Components/EditableTextBox.h"
#include "Components/SpinBox.h"
#include "Components/TextBlock.h"
#include "Components/Image.h"
#include "Components/PanelWidget.h"
#include "Components/HorizontalBox.h"
#include "Components/WrapBox.h"
#include "Components/SizeBox.h"
#include "Components/ListView.h"
#include "Components/ContentWidget.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Engine/Texture.h"
#include "Engine/GameViewportClient.h"
#include "Engine/Engine.h"
#include "GameFramework/PlayerController.h"
#include "Framework/Application/SlateApplication.h"

namespace
{
const TCHAR* GScreenPath=TEXT("/Game/UI/Reader/WBP_ReaderScreen.WBP_ReaderScreen_C");
TWeakObjectPtr<UOKReaderScreen> GScreen;

UDreamText* TextOf(UDreamWidget* W){return W?Cast<UDreamText>(W->GetVisual()):nullptr;}

// The text a UMG control shows: its own (a text block) or the first text inside it (a button's label).
FString TextIn(UWidget* W)
{
	if(!W)return FString();
	if(auto* T=Cast<UTextBlock>(W))return T->GetText().ToString();
	if(auto* C=Cast<UContentWidget>(W))return TextIn(C->GetContent());
	if(auto* P=Cast<UPanelWidget>(W))for(int32 I=0;I<P->GetChildrenCount();++I){FString S=TextIn(P->GetChildAt(I));if(!S.IsEmpty())return S;}
	if(auto* U=Cast<UUserWidget>(W))return TextIn(U->GetRootWidget());
	return FString();
}
bool IsUmgShown(UWidget* W)
{
	if(!W)return false;const ESlateVisibility V=W->GetVisibility();
	return V!=ESlateVisibility::Collapsed&&V!=ESlateVisibility::Hidden;
}
// The UMG children a mirror shows: a panel's, or a user widget's root.
TArray<UWidget*> ChildrenOf(UWidget* W)
{
	TArray<UWidget*> Out;
	if(auto* P=Cast<UPanelWidget>(W))for(int32 I=0;I<P->GetChildrenCount();++I)Out.Add(P->GetChildAt(I));
	else if(auto* U=Cast<UUserWidget>(W)){if(U->GetRootWidget())Out.Add(U->GetRootWidget());}
	return Out;
}
float TextWidth(const FString& S,float PerChar){float W=0;for(TCHAR C:S)W+=C<128?PerChar*.55f:PerChar;return W;}
}

// ------------------------------------------------------------------------------------------------- UOKDreamControl

void UOKDreamControl::NativeOnInitialized()
{
	Super::NativeOnInitialized();
	if(Button)Button->OnClicked.AddDynamic(this,&UOKDreamControl::HandleClicked);
	if(Header)Header->OnClicked.AddDynamic(this,&UOKDreamControl::HandleHeader);
	if(Slider)Slider->OnValueChanged.AddDynamic(this,&UOKDreamControl::HandleSlider);
	if(Toggle)Toggle->OnToggleChanged.AddDynamic(this,&UOKDreamControl::HandleToggle);
	if(Choice)Choice->OnSelectionChanged.AddDynamic(this,&UOKDreamControl::HandleChoice);
	if(Input)Input->OnTextCommitted.AddDynamic(this,&UOKDreamControl::HandleInputCommitted);
}

void UOKDreamControl::SetText(const FString& Text)
{
	if(Text==ShownText)return;ShownText=Text;
	if(auto* T=TextOf(Title?Title.Get():Label.Get()))T->SetText(FText::FromString(Text));
}

void UOKDreamControl::SetOpen(bool bNewOpen)
{
	bOpen=bNewOpen;if(Body)Body->SetShown(bOpen);
}

void UOKDreamControl::Sync()
{
	UWidget* S=Source.Get();
	if(!S){if(!FixedText.IsEmpty())SetText(FixedText);return;}
	SetShown(IsUmgShown(S));
	if(!GetShown())return;
	TGuardValue<bool> Guard(bPushing,true);
	if(auto* Drawer=Cast<UOKDrawerButton>(S))
	{
		SetText(FixedText.IsEmpty()?Drawer->Title:FixedText);
		if(Drawer->bOpen!=bOpen)SetOpen(Drawer->bOpen);
		return;
	}
	if(Button){SetText(FixedText.IsEmpty()?TextIn(S):FixedText);Button->SetIsEnabled(S->GetIsEnabled());}
	else if(Label&&!Toggle){SetText(TextIn(S));}
	if(auto* U=Cast<USlider>(S))if(Slider)
	{
		if(Slider->GetMinValue()!=U->GetMinValue())Slider->SetMinValue(U->GetMinValue());
		if(Slider->GetMaxValue()!=U->GetMaxValue())Slider->SetMaxValue(U->GetMaxValue());
		if(!FMath::IsNearlyEqual(Slider->GetValue(),U->GetValue(),1e-4f))Slider->SetValue(U->GetValue());
		Slider->SetIsEnabled(U->GetIsEnabled());
	}
	if(auto* U=Cast<UCheckBox>(S))if(Toggle)
	{
		SetText(TextIn(U));
		if(Toggle->GetIsOn()!=U->IsChecked())Toggle->SetIsOn(U->IsChecked());
		Toggle->SetIsEnabled(U->GetIsEnabled());
	}
	if(auto* U=Cast<UComboBoxString>(S))if(Choice)
	{
		bool Same=ShownOptions.Num()==U->GetOptionCount();
		for(int32 I=0;Same&&I<ShownOptions.Num();++I)Same=ShownOptions[I]==U->GetOptionAtIndex(I);
		if(!Same)
		{
			ShownOptions.Reset();TArray<FText> Options;
			for(int32 I=0;I<U->GetOptionCount();++I){ShownOptions.Add(U->GetOptionAtIndex(I));Options.Add(FText::FromString(ShownOptions.Last()));}
			Choice->SetOptions(Options);
		}
		const int32 Index=U->GetSelectedIndex();if(Choice->GetSelectedIndex()!=Index)Choice->SetSelectedIndex(Index);
		Choice->SetIsEnabled(U->GetIsEnabled());
	}
	if(Input)
	{
		FString Value;
		if(auto* U=Cast<UEditableTextBox>(S))Value=U->GetText().ToString();
		else if(auto* N=Cast<USpinBox>(S))Value=FString::SanitizeFloat(N->GetValue(),0);
		// Only what the controller changed: text typed here and not yet committed stays.
		if(Value!=ShownText){ShownText=Value;Input->SetText(Value);}
		Input->SetIsEnabled(S->GetIsEnabled());
	}
	if(auto* U=Cast<UImage>(S))if(Picture)
	{
		UTexture* Texture=Cast<UTexture>(U->GetBrush().GetResourceObject());
		if(Texture!=ShownTexture.Get())
		{
			ShownTexture=Texture;
			if(auto* Image=Cast<UDreamImage>(Picture->GetVisual())){FDreamUIImageBrush Brush=Image->GetBrush();Brush.SetResourceObject(Texture);Image->SetBrush(Brush);}
		}
	}
}

void UOKDreamControl::HandleClicked()
{
	if(bPushing)return;
	if(auto* B=Cast<UButton>(Source.Get())){if(B->GetIsEnabled())B->OnClicked.Broadcast();}
	else if(OnPressed)OnPressed();
	if(auto* G=Source.IsValid()?Source->GetTypedOuter<UOKCharacterController>():nullptr)G->ApplyPendingEditorMods();
}
void UOKDreamControl::HandleHeader()
{
	if(auto* Drawer=Cast<UOKDrawerButton>(Source.Get())){Drawer->SetOpen(!Drawer->bOpen,true);SetOpen(Drawer->bOpen);}
	else SetOpen(!bOpen);
}
// The same steps as ui_set (OKGameControl SetValue): what a person's change on the UMG control would fire.
void UOKDreamControl::HandleSlider(float Value)
{
	if(bPushing)return;
	if(auto* U=Cast<USlider>(Source.Get())){U->SetValue(Value);U->OnValueChanged.Broadcast(Value);}
	if(auto* G=Source.IsValid()?Source->GetTypedOuter<UOKCharacterController>():nullptr)G->ApplyPendingEditorMods();
}
void UOKDreamControl::HandleToggle(bool bOn)
{
	if(bPushing)return;
	if(auto* U=Cast<UCheckBox>(Source.Get())){U->SetIsChecked(bOn);U->OnCheckStateChanged.Broadcast(bOn);}
	if(auto* G=Source.IsValid()?Source->GetTypedOuter<UOKCharacterController>():nullptr)G->ApplyPendingEditorMods();
}
void UOKDreamControl::HandleChoice(int32 Index)
{
	if(bPushing)return;
	if(auto* U=Cast<UComboBoxString>(Source.Get()))if(Index>=0&&Index<U->GetOptionCount())
	{
		const FString Option=U->GetOptionAtIndex(Index);
		auto Changed=U->OnSelectionChanged;U->OnSelectionChanged.Clear();U->SetSelectedOption(Option);U->OnSelectionChanged=Changed;
		U->OnSelectionChanged.Broadcast(Option,ESelectInfo::OnMouseClick);
	}
	if(auto* G=Source.IsValid()?Source->GetTypedOuter<UOKCharacterController>():nullptr)G->ApplyPendingEditorMods();
}
void UOKDreamControl::HandleInputCommitted(const FString& Text)
{
	if(bPushing)return;
	if(auto* U=Cast<UEditableTextBox>(Source.Get()))
	{
		auto Changed=U->OnTextChanged;U->OnTextChanged.Clear();U->SetText(FText::FromString(Text));U->OnTextChanged=Changed;
		U->OnTextChanged.Broadcast(U->GetText());U->OnTextCommitted.Broadcast(U->GetText(),ETextCommit::OnEnter);
	}
	else if(auto* N=Cast<USpinBox>(Source.Get()))
	{
		if(!Text.IsNumeric())return;const float V=FCString::Atof(*Text);
		N->SetValue(V);N->OnValueChanged.Broadcast(N->GetValue());N->OnValueCommitted.Broadcast(N->GetValue(),ETextCommit::OnEnter);
	}
	ShownText.Reset();
	if(auto* G=Source.IsValid()?Source->GetTypedOuter<UOKCharacterController>():nullptr)G->ApplyPendingEditorMods();
}

// ------------------------------------------------------------------------------------------------- UOKReaderScreen

UOKReaderScreen* UOKReaderScreen::Open(UOKCharacterController* Controller)
{
	if(!Controller)return nullptr;
	UClass* Class=LoadClass<UOKReaderScreen>(nullptr,GScreenPath);
	if(!Class){UE_LOG(LogTemp,Warning,TEXT("Reader screen %s missing: the reader keeps its UMG controls"),GScreenPath);return nullptr;}
	// Design pixels on a 1080-high screen, whatever the window.
	if(auto* Screens=UDreamScreenUISubsystem::Get(Controller->GetWorld()))if(UDreamCanvas* Canvas=Screens->GetScreenCanvas(Controller->GetOwningPlayer()))
	{
		Canvas->SetScaleMode(EDreamCanvasScaleMode::ScaleWithScreenSize);Canvas->SetReferenceResolution(FVector2D(1920,1080));Canvas->SetMatchFromWidthToHeight(1.f);
	}
	auto* Screen=Cast<UOKReaderScreen>(UDreamUIBPLibrary::AddWidgetOfClassToViewport(Controller,Class,10));
	if(!Screen)return nullptr;
	Screen->Controller=Controller;GScreen=Screen;
	if(auto* Screens=UDreamScreenUISubsystem::Get(Controller->GetWorld()))if(UDreamCanvas* Canvas=Screens->GetScreenCanvas(Controller->GetOwningPlayer()))
	{
		Canvas->SetScaleMode(EDreamCanvasScaleMode::ScaleWithScreenSize);Canvas->SetReferenceResolution(FVector2D(1920,1080));Canvas->SetMatchFromWidthToHeight(1.f);
	}
	return Screen;
}

void UOKReaderScreen::NativeOnInitialized()
{
	Super::NativeOnInitialized();
	if(BackToLauncher)BackToLauncher->OnClicked.AddDynamic(this,&UOKReaderScreen::HandleBackToLauncher);
	if(Tab0)Tab0->OnClicked.AddDynamic(this,&UOKReaderScreen::HandleTab0);
	if(Tab1)Tab1->OnClicked.AddDynamic(this,&UOKReaderScreen::HandleTab1);
	if(Tab2)Tab2->OnClicked.AddDynamic(this,&UOKReaderScreen::HandleTab2);
	if(Tab3)Tab3->OnClicked.AddDynamic(this,&UOKReaderScreen::HandleTab3);
}

void UOKReaderScreen::HandleBackToLauncher()
{
	// No separate launcher program: the card wall is where a card is picked and opened.
	if(auto* G=Controller.Get())if(G->bModelLayout)G->OnBackToGallery();
	ShowTab(1);
}
void UOKReaderScreen::HandleTab0(){ShowTab(0);}
void UOKReaderScreen::HandleTab1(){ShowTab(1);}
void UOKReaderScreen::HandleTab2(){ShowTab(2);}
void UOKReaderScreen::HandleTab3(){ShowTab(3);}

UOKDreamControl* UOKReaderScreen::MakeControl(const TCHAR* Kind,UDreamWidget* Into)
{
	UClass* Class=LoadClass<UOKDreamControl>(nullptr,*FString::Printf(TEXT("/Game/UI/Reader/Controls/WBP_OK%s.WBP_OK%s_C"),Kind,Kind));
	if(!Class){UE_LOG(LogTemp,Warning,TEXT("Reader control WBP_OK%s missing"),Kind);return nullptr;}
	auto* C=Cast<UOKDreamControl>(UDreamUIBPLibrary::CreateDreamWidgetOfClass(this,Class));
	if(!C)return nullptr;
	// The .dui gives its root the control's natural size: the control takes that size and its root fills it, so a panel that
	// stretches the control stretches what is drawn.
	float Height=0;
	if(UDreamWidget* Root=C->GetWidgetTree()?C->GetWidgetTree()->GetRootWidget():nullptr)
	{
		const FVector2D Natural=Root->GetSizeDelta();C->SetSizeDelta(Natural);Height=Natural.Y;
		Root->SetAnchorMin(FVector2D(0,0));Root->SetAnchorMax(FVector2D(1,1));Root->SetAnchoredPosition(FVector2D::ZeroVector);Root->SetSizeDelta(FVector2D::ZeroVector);
	}
	if(Into)AddToHost(Into,C,false);
	// Its height is the designed one: a slider measures itself 100 high and stretched every row to that.
	if(Height>0)if(UDreamPanelSlot* Slot=C->GetPanelSlot()){Slot->SetMinDesiredSize(FVector2D(0,Height));Slot->SetMaxDesiredSize(FVector2D(0,Height));}
	Controls.Add(C);return C;
}

UOKDreamControl* UOKReaderScreen::MakeOwnButton(UDreamWidget* Into,const FString& Text,TFunction<void()> Press)
{
	UOKDreamControl* C=MakeControl(TEXT("Button"),Into);if(!C)return nullptr;
	C->FixedText=Text;C->OnPressed=MoveTemp(Press);C->SetText(Text);
	C->SetWidth(FMath::Max(64.f,TextWidth(Text,20.f)+36.f));
	return C;
}

UDreamWidget* UOKReaderScreen::MakePanel(UDreamWidget* Into,bool bHorizontal,float Spacing)
{
	UDreamWidget* W=UDreamUIBPLibrary::ConstructWidget(this,bHorizontal?TEXT("Row"):TEXT("Column"),nullptr);
	if(!W)return nullptr;
	// A panel is a widget with a layout container (CreateNewLayoutContainer, not AddComponent: a container is no behaviour).
	if(bHorizontal){if(auto* L=W->CreateNewLayoutContainer<UDreamLayoutContainerHorizontalBox>())L->SetSpacing(Spacing);}
	else if(auto* L=W->CreateNewLayoutContainer<UDreamLayoutContainerVerticalBox>())L->SetSpacing(Spacing);
	// No size of its own: a panel left at the default 100 x 100 kept rows 100 high whatever they held.
	W->SetSizeDelta(FVector2D::ZeroVector);
	if(Into)AddToHost(Into,W,false);
	return W;
}

void UOKReaderScreen::AddToHost(UDreamWidget* Host,UDreamWidget* Child,bool bFill)
{
	if(!Host||!Child)return;
	if(auto* Scroll=Cast<UDreamScrollBox>(Host)){Scroll->AddContent(Child);return;}
	if(UDreamPanelSlot* Slot=Host->AddChild(Child))
	{
		Slot->SetHorizontalAlignment(EDreamPanelHorizontalAlignment::Fill);
		Slot->SetVerticalAlignment(EDreamPanelVerticalAlignment::Center);
		if(bFill)Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
	}
}

// One UMG widget, and everything under it, as DreamGUI controls under Parent. bInRow: Parent lays out across.
void UOKReaderScreen::Mirror(UWidget* Source,UDreamWidget* Into,bool bInRow)
{
	if(!Source||!Into)return;
	if(Source->IsA<UOKDrawerButton>())return;	// the right panel's drawers show these
	if(Source->IsA<UListView>())return;	// the card list has a page of its own
	auto Place=[&](UOKDreamControl* C,float RowWidth,bool bFill)
	{
		if(!C)return;C->Source=Source;C->Sync();
		if(bInRow){if(RowWidth>0)C->SetWidth(RowWidth);if(bFill)if(auto* Slot=C->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);}
	};
	if(Source->IsA<UButton>()){UOKDreamControl* C=MakeControl(TEXT("Button"),Into);const FString T=TextIn(Source);Place(C,FMath::Max(56.f,TextWidth(T,20.f)+36.f),false);return;}
	if(Source->IsA<USlider>()){Place(MakeControl(TEXT("Slider"),Into),0,true);return;}
	if(Source->IsA<UCheckBox>()){Place(MakeControl(TEXT("Toggle"),Into),FMath::Max(80.f,TextWidth(TextIn(Source),18.f)+56.f),false);return;}
	if(Source->IsA<UComboBoxString>()){Place(MakeControl(TEXT("Choice"),Into),0,true);return;}
	if(Source->IsA<UEditableTextBox>()||Source->IsA<USpinBox>()){Place(MakeControl(TEXT("Input"),Into),bInRow?84.f:0.f,false);return;}
	if(Source->IsA<UTextBlock>()){Place(MakeControl(TEXT("Label"),Into),FMath::Min(200.f,TextWidth(TextIn(Source),18.f)+12.f),false);return;}
	if(Source->IsA<UImage>()){Place(MakeControl(TEXT("Image"),Into),0,false);return;}
	// A size box in a row only gives its child a width: keep the width, drop the box.
	if(auto* Size=Cast<USizeBox>(Source);Size&&bInRow&&Size->GetChildrenCount()==1)
	{
		const int32 Before=Into->GetChildren().Num();Mirror(Size->GetChildAt(0),Into,true);
		if(Into->GetChildren().Num()>Before&&Size->GetWidthOverride()>0)Into->GetChildren().Last()->SetWidth(Size->GetWidthOverride());
		return;
	}
	if(Source->IsA<UPanelWidget>()||Source->IsA<UUserWidget>())
	{
		const bool bHorizontal=Source->IsA<UHorizontalBox>()||Source->IsA<UWrapBox>();
		UDreamWidget* Target=MakePanel(Into,bHorizontal,bHorizontal?6.f:6.f);
		if(!Target)return;
		if(bInRow)if(auto* Slot=Target->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
		FOKDreamMirrorPanel Panel;Panel.Source=Cast<UPanelWidget>(Source);Panel.Target=Target;Panel.bHorizontal=bHorizontal;
		const TArray<UWidget*> Kids=ChildrenOf(Source);Panel.Children=Kids.Num();
		Target->SetShown(IsUmgShown(Source));
		for(UWidget* Child:Kids)Mirror(Child,Target,bHorizontal);
		if(Panel.Source.IsValid())Panels.Add(Panel);
	}
}

void UOKReaderScreen::MirrorChildren(UPanelWidget* Source,UDreamWidget* Target,bool bHorizontal)
{
	if(!Source||!Target)return;
	for(UDreamWidget* Child:TArray<UDreamWidget*>(Target->GetChildren()))if(Child)Child->DestroyWidget();
	for(int32 I=0;I<Source->GetChildrenCount();++I)Mirror(Source->GetChildAt(I),Target,bHorizontal);
}

void UOKReaderScreen::BuildCategories()
{
	UOKCharacterController* G=Controller.Get();if(!G)return;
	Categories.Reset();
	// Body and face sliders, grouped as the separators in KKShapeRows group them.
	auto ShapeGroups=[&](bool bBody,const TArray<FString>& Names)
	{
		TArray<FGroup> Groups;FGroup Current;int32 Next=0;
		const TConstArrayView<FKKShapeRow> Rows=KKShapeRows();
		for(int32 I=0;I<Rows.Num()&&I<G->ShapeSliders.Num();++I)
		{
			if(Rows[I].bBody!=bBody)continue;
			if(UWidget* Row=G->ShapeSliders[I]?G->ShapeSliders[I]->GetParent():nullptr)Current.Sources.Add(Row);
			if(Rows[I].bSep){Current.Name=Names.IsValidIndex(Next)?Names[Next]:FString::Printf(TEXT("%d"),Next+1);++Next;Groups.Add(MoveTemp(Current));Current=FGroup();}
		}
		if(Current.Sources.Num()){Current.Name=Names.IsValidIndex(Next)?Names[Next]:FString::Printf(TEXT("%d"),Next+1);Groups.Add(MoveTemp(Current));}
		return Groups;
	};
	auto Group=[](const FString& Name,const TArray<UWidget*>& Sources){FGroup Out;Out.Name=Name;for(UWidget* W:Sources)if(W)Out.Sources.Add(W);return Out;};
	auto Named=[G](const TCHAR* Name){return G->WidgetTree?G->WidgetTree->FindWidget(FName(Name)):nullptr;};
	// A UMG drawer body shows (and so mirrors) only while its drawer is open; the appearance panel only once opened.
	auto OpenDrawer=[](UOKDrawerButton* D){return TFunction<void()>([Weak=TWeakObjectPtr<UOKDrawerButton>(D)](){if(Weak.IsValid()&&!Weak->bOpen)Weak->SetOpen(true,false);});};
	TFunction<void()> OpenAppearance=[Weak=TWeakObjectPtr<UOKCharacterController>(G)](){if(Weak.IsValid()&&Weak->AppearancePanel&&Weak->AppearancePanel->GetVisibility()==ESlateVisibility::Collapsed)Weak->OnOpenAppearance();};

	FCategory Face;Face.Name=TEXT("臉");Face.Groups=ShapeGroups(false,{TEXT("臉型"),TEXT("下巴"),TEXT("臉頰"),TEXT("眉毛"),TEXT("眼睛"),TEXT("鼻子"),TEXT("嘴巴"),TEXT("耳朵")});
	Categories.Add(MoveTemp(Face));

	FCategory Body;Body.Name=TEXT("身子");Body.Groups=ShapeGroups(true,{TEXT("全身"),TEXT("胸部"),TEXT("軀幹"),TEXT("腰臀"),TEXT("手臂"),TEXT("腿部")});
	{
		// The bone controls follow the last slider row in the same column.
		FGroup Bones;Bones.Name=TEXT("骨骼");
		if(G->ShapeBox&&G->ShapeSliders.Num())
		{
			const int32 Last=G->ShapeBox->GetChildIndex(G->ShapeSliders.Last()?G->ShapeSliders.Last()->GetParent():nullptr);
			for(int32 I=Last+1;Last>=0&&I<G->ShapeBox->GetChildrenCount();++I)if(!G->ShapeSeparators.Contains(G->ShapeBox->GetChildAt(I)))Bones.Sources.Add(G->ShapeBox->GetChildAt(I));
		}
		if(Bones.Sources.Num())Body.Groups.Add(MoveTemp(Bones));
		if(G->PregnancyBox)Body.Groups.Add(Group(TEXT("懷孕"),{G->PregnancyBox.Get()}));
	}
	Categories.Add(MoveTemp(Body));

	FCategory Clothes;Clothes.Name=TEXT("衣服");
	for(UOKDrawerButton* D:G->MotionDrawers)if(D&&D->Key==TEXT("Clothes")){Clothes.Groups.Add(Group(TEXT("穿著狀態"),{D->Body.Get()}));Clothes.Groups.Last().OnEnter=OpenDrawer(D);}
	Clothes.Groups.Add(Group(TEXT("服裝"),{G->OutfitCombo?static_cast<UWidget*>(G->OutfitCombo->GetParent()):nullptr,G->OutfitNav.Get()}));
	Clothes.Groups.Add(Group(TEXT("外觀選擇"),{G->AppearancePanel.Get()}));Clothes.Groups.Last().OnEnter=OpenAppearance;
	for(FGroup& Each:Clothes.Groups)Each.Sources.RemoveAll([](const TWeakObjectPtr<UWidget>& W){return !W.IsValid();});
	Categories.Add(MoveTemp(Clothes));

	FCategory Accessory;Accessory.Name=TEXT("配件");
	Accessory.Groups.Add(Group(TEXT("外觀選擇"),{G->AppearancePanel.Get()}));Accessory.Groups.Last().OnEnter=OpenAppearance;
	Accessory.Groups.Add(Group(TEXT("屬性"),{G->PropertyPanel.Get()}));
	Categories.Add(MoveTemp(Accessory));

	FCategory Info;Info.Name=TEXT("角色資訊");
	Info.Groups.Add(Group(TEXT("角色"),{G->InspectCol.Get()}));
	Categories.Add(MoveTemp(Info));

	FCategory Cards;Cards.Name=TEXT("人物卡總欄");Cards.Tab=1;
	Cards.Groups.Add(Group(TEXT("人物卡"),{G->CardCol.Get()}));
	Categories.Add(MoveTemp(Cards));

	FCategory ClothesCards;ClothesCards.Name=TEXT("衣服卡總欄");ClothesCards.Tab=2;
	ClothesCards.Groups.Add(Group(TEXT("服裝卡"),{static_cast<UWidget*>(Named(TEXT("OkClothesRow")))}));
	Categories.Add(MoveTemp(ClothesCards));

	FCategory Settings;Settings.Name=TEXT("設定／介面");Settings.Tab=3;
	for(UOKDrawerButton* D:G->MotionDrawers)if(D&&D->Key==TEXT("Lighting")){Settings.Groups.Add(Group(TEXT("光影"),{D->Body.Get()}));Settings.Groups.Last().OnEnter=OpenDrawer(D);}
	if(G->StyleBox)Settings.Groups.Add(Group(TEXT("角色風格"),{G->StyleBox.Get()}));
	Settings.Groups.Add(Group(TEXT("物理"),{G->PhysicsBackendCombo?static_cast<UWidget*>(G->PhysicsBackendCombo->GetParent()):nullptr}));
	Settings.Groups.Add(Group(TEXT("介面"),{G->EditorWidthInput?static_cast<UWidget*>(G->EditorWidthInput->GetParent()):nullptr,G->EditorFontInput?static_cast<UWidget*>(G->EditorFontInput->GetParent()):nullptr}));
	for(FGroup& Each:Settings.Groups)Each.Sources.RemoveAll([](const TWeakObjectPtr<UWidget>& W){return !W.IsValid();});
	Settings.Groups.RemoveAll([](const FGroup& Each){return Each.Sources.IsEmpty();});
	Categories.Add(MoveTemp(Settings));
}

void UOKReaderScreen::BuildDrawers()
{
	UOKCharacterController* G=Controller.Get();if(!G||!RightScroll)return;
	// The editor's own buttons, as listed in the 2026-11-18 sketch, first.
	if(UOKDreamControl* Main=MakeControl(TEXT("Drawer"),RightScroll))
	{
		Main->FixedText=TEXT("人物編輯");Main->SetText(Main->FixedText);Main->Body=MakePanel(RightScroll,false,6.f);Main->SetOpen(true);Drawers.Add(Main);
		UDreamWidget* Grid=MakePanel(Main->Body,false,6.f);
		auto Row=[&](std::initializer_list<const TCHAR*> Names)
		{
			UDreamWidget* R=MakePanel(Grid,true,6.f);
			for(const TCHAR* Name:Names)if(UWidget* W=G->WidgetTree->FindWidget(FName(Name)))
			{
				const int32 Before=R->GetChildren().Num();Mirror(W,R,true);
				if(R->GetChildren().Num()>Before)if(auto* Slot=R->GetChildren().Last()->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
			}
		};
		Row({TEXT("ResetAllShapes"),TEXT("ShapeLoad3D"),TEXT("BackGallery")});
		Row({TEXT("EditorInteraction"),TEXT("EditorStudio"),TEXT("EditorStudioTimeline")});
		Row({TEXT("ModelApngSave"),TEXT("EditorSaveKks"),TEXT("EditorHands")});
		if(G->OutfitCombo)Mirror(G->OutfitCombo.Get(),Grid,false);
	}
	for(UOKDrawerButton* D:G->MotionDrawers)
	{
		if(!D||D->Key==TEXT("Clothes")||D->Key==TEXT("Lighting"))continue;	// those are left-panel categories
		UOKDreamControl* Drawer=MakeControl(TEXT("Drawer"),RightScroll);if(!Drawer)continue;
		Drawer->Body=MakePanel(RightScroll,false,6.f);
		Drawer->Source=D;Drawer->SetOpen(D->bOpen);Drawers.Add(Drawer);
		if(D->Body)Mirror(D->Body,Drawer->Body,false);
		Drawer->Sync();
	}
}

void UOKReaderScreen::BuildCameraBar()
{
	if(!CameraBarHost)return;
	auto View=[this](float Yaw,float Pitch,float Distance,int32 Focus)
	{
		UOKCharacterController* G=Controller.Get();AKKPreviewActor* A=G?G->PreviewActor.Get():nullptr;if(!A)return;
		A->FrameCurrentPose();
		const FVector Base=A->OrbitFocus;const float Full=A->OrbitDistance;
		// Focus: 0 whole body, 1 upper body, 2 face, 3 legs.
		if(Focus>0&&A->BodySkel)
		{
			const FName Bone=Focus==2?FName(TEXT("cf_j_head")):Focus==1?FName(TEXT("cf_j_spine03")):FName(TEXT("cf_j_leg01_L"));
			const FVector At=A->BodySkel->GetBoneLocation(Bone,EBoneSpaces::WorldSpace);
			if(!At.ContainsNaN()&&!At.IsNearlyZero())A->OrbitFocus=FVector(Base.X,Base.Y,At.Z+(Focus==2?6.f:0.f));
		}
		A->OrbitYaw+=Yaw;A->OrbitPitch=Pitch;A->OrbitDistance=Full*Distance;A->ApplyOrbitCamera();
	};
	MakeOwnButton(CameraBarHost,TEXT("全身"),[View](){View(0,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("上半身"),[View](){View(0,0,.55f,1);});
	MakeOwnButton(CameraBarHost,TEXT("臉部"),[View](){View(0,0,.22f,2);});
	MakeOwnButton(CameraBarHost,TEXT("腿部"),[View](){View(0,0,.6f,3);});
	MakeOwnButton(CameraBarHost,TEXT("正面"),[View](){View(0,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("左側"),[View](){View(-90,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("右側"),[View](){View(90,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("背面"),[View](){View(180,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("俯視"),[View](){View(0,-35,1,0);});
}

void UOKReaderScreen::BuildPluginTools()
{
	UOKCharacterController* G=Controller.Get();if(!G||!PluginHost)return;
	if(G->FpsText)Mirror(G->FpsText,PluginHost,true);
	if(UWidget* Fps=G->WidgetTree->FindWidget(TEXT("ReaderFps")))if(Fps!=G->FpsText)Mirror(Fps,PluginHost,true);
}

void UOKReaderScreen::ClearPage()
{
	for(UDreamWidget* W:PageWidgets)if(IsValid(W))W->DestroyWidget();
	PageWidgets.Reset();
	for(UOKDreamControl* B:SubButtons)if(IsValid(B))B->DestroyWidget();
	SubButtons.Reset();
	Controls.RemoveAll([](const TObjectPtr<UOKDreamControl>& C){return !IsValid(C);});
	Panels.RemoveAll([](const FOKDreamMirrorPanel& P){return !P.Target.IsValid()||!IsValid(P.Target.Get());});
}

void UOKReaderScreen::ShowTab(int32 Index)
{
	Tab=FMath::Clamp(Index,0,3);
	UDreamButton* Tabs[]={Tab0,Tab1,Tab2,Tab3};
	for(int32 I=0;I<4;++I)if(Tabs[I])Tabs[I]->SetRenderOpacity(I==Tab?1.f:.62f);
	// The rail lists the edit categories; the other three tabs are one page each.
	for(UOKDreamControl* B:RailButtons)if(IsValid(B))B->DestroyWidget();
	RailButtons.Reset();
	int32 First=INDEX_NONE;
	for(int32 I=0;I<Categories.Num();++I)
	{
		if(First==INDEX_NONE&&Categories[I].Tab==Tab)First=I;
		if(Tab!=0)continue;
		UOKDreamControl* B=MakeOwnButton(RailHost,Categories[I].Name,[this,I](){ShowCategory(I);});
		if(B){B->SetWidth(104);if(auto* Slot=B->GetPanelSlot())Slot->SetHorizontalAlignment(EDreamPanelHorizontalAlignment::Fill);RailButtons.Add(B);}
	}
	if(RailHost)RailHost->SetShown(Tab==0);
	if(First!=INDEX_NONE)ShowCategory(First);
}

void UOKReaderScreen::ShowCategory(int32 Index,int32 SubIndex)
{
	if(!Categories.IsValidIndex(Index))return;
	ClearPage();
	Category=Index;const FCategory& C=Categories[Index];
	if(C.Tab!=Tab){Tab=C.Tab;UDreamButton* Tabs[]={Tab0,Tab1,Tab2,Tab3};for(int32 I=0;I<4;++I)if(Tabs[I])Tabs[I]->SetRenderOpacity(I==Tab?1.f:.62f);if(RailHost)RailHost->SetShown(Tab==0);}
	for(int32 I=0;I<RailButtons.Num();++I)if(RailButtons[I])RailButtons[I]->SetRenderOpacity(I==Index?1.f:.7f);
	if(auto* T=TextOf(CategoryTitle))T->SetText(FText::FromString(C.Name));
	if(C.OnEnter)C.OnEnter();
	Sub=FMath::Clamp(SubIndex,0,FMath::Max(0,C.Groups.Num()-1));
	// The second-level menu: one button per group; the page shows the chosen group.
	if(C.Groups.Num()>1)for(int32 I=0;I<C.Groups.Num();++I)
	{
		UOKDreamControl* B=MakeOwnButton(SubMenuHost,C.Groups[I].Name,[this,Index,I](){ShowCategory(Index,I);});
		if(B){B->SetRenderOpacity(I==Sub?1.f:.65f);SubButtons.Add(B);Controls.Remove(B);}
	}
	if(SubMenuHost)SubMenuHost->SetShown(C.Groups.Num()>1);
	if(LeftScroll&&C.Groups.IsValidIndex(Sub))
	{
		if(C.Groups[Sub].OnEnter)C.Groups[Sub].OnEnter();
		UDreamWidget* Page=MakePanel(nullptr,false,8.f);
		if(Page){LeftScroll->AddContent(Page);PageWidgets.Add(Page);}
		for(const TWeakObjectPtr<UWidget>& Source:C.Groups[Sub].Sources)if(Source.IsValid()&&Page)Mirror(Source.Get(),Page,false);
		// The card list: a page of buttons, as the UMG list view shows them.
		if(Tab==1&&Page)if(UOKCharacterController* G=Controller.Get())
		{
			UDreamWidget* List=MakePanel(Page,false,4.f);
			ShownEntries=G->Entries.Num();
			for(int32 I=0;I<G->Entries.Num()&&I<400;++I)
			{
				const auto& E=G->Entries[I];
				const FString Text=FString::Printf(TEXT("%s %s  %s"),*E.LastName,*E.FirstName,*E.FileName);
				TWeakObjectPtr<UOKCharacterController> Weak(G);
				if(UOKDreamControl* B=MakeOwnButton(List,Text,[Weak,I](){if(Weak.IsValid())Weak->SelectIndex(I);}))B->SetWidth(0);
			}
		}
		LeftScroll->ScrollToStart();
	}
}

void UOKReaderScreen::SetLeftWidth(float Width)
{
	LeftWidth=FMath::Clamp(Width,360.f,1000.f);Layout();
}

void UOKReaderScreen::Layout()
{
	if(LeftPanel)LeftPanel->SetWidth(LeftWidth);
	if(RightPanel)RightPanel->SetWidth(RightWidth);
	// The camera bar spans the 3D view between the two panels, 16 px clear of each.
	if(CameraBar){CameraBar->SetSizeDelta(FVector2D(-(LeftWidth+RightWidth+32.f),56.f));CameraBar->SetHorizontalAnchoredPosition((LeftWidth-RightWidth)*.5f);}
	if(NamePlate)NamePlate->SetHorizontalAnchoredPosition(-(RightWidth+16.f));
}

// The left panel's right edge is a handle: press near it and drag.
void UOKReaderScreen::TickResize()
{
	APlayerController* PC=GetOwningPlayer();if(!PC)PC=Controller.IsValid()?Controller->GetOwningPlayer():nullptr;
	if(!PC||!GEngine||!GEngine->GameViewport||!GEngine->GameViewport->Viewport)return;
	float X=0,Y=0;if(!PC->GetMousePosition(X,Y))return;
	const FIntPoint Size=GEngine->GameViewport->Viewport->GetSizeXY();if(Size.Y<=0)return;
	const float Scale=Size.Y/1080.f;const bool Down=PC->IsInputKeyDown(EKeys::LeftMouseButton);
	const float Edge=LeftWidth*Scale;
	if(!bResizing&&Down&&PC->WasInputKeyJustPressed(EKeys::LeftMouseButton)&&FMath::Abs(X-Edge)<=8.f*Scale){bResizing=true;ResizeStartX=X;ResizeStartWidth=LeftWidth;}
	if(bResizing){if(!Down)bResizing=false;else SetLeftWidth(ResizeStartWidth+(X-ResizeStartX)/Scale);}
}

void UOKReaderScreen::SyncAll()
{
	// Panels whose UMG children came or went (a list the controller rebuilt) are mirrored again.
	Panels.RemoveAll([](const FOKDreamMirrorPanel& P){return !P.Source.IsValid()||!P.Target.IsValid()||!IsValid(P.Target.Get());});
	const int32 Count=Panels.Num();	// mirroring again appends the new panels after these
	for(int32 I=0;I<Count;++I)
	{
		UPanelWidget* S=Panels[I].Source.Get();UDreamWidget* T=Panels[I].Target.Get();
		if(!S||!T||!IsValid(T))continue;
		T->SetShown(IsUmgShown(S));
		if(S->GetChildrenCount()!=Panels[I].Children){Panels[I].Children=S->GetChildrenCount();const bool bHorizontal=Panels[I].bHorizontal;MirrorChildren(S,T,bHorizontal);}
	}
	Controls.RemoveAll([](const TObjectPtr<UOKDreamControl>& C){return !IsValid(C);});
	for(int32 I=0;I<Controls.Num();++I)Controls[I]->Sync();
	for(UOKDreamControl* D:Drawers)if(IsValid(D))D->Sync();
	if(UOKCharacterController* G=Controller.Get())
	{
		// The card wall until a card is open, the editor once one is; a new card folder lists again.
		if(G->bModelLayout!=bShownModelLayout){bShownModelLayout=G->bModelLayout;ShowTab(bShownModelLayout?0:1);}
		else if(Tab==1&&G->Entries.Num()!=ShownEntries)ShowCategory(Category,Sub);
	}
	if(UOKCharacterController* G=Controller.Get())if(auto* T=TextOf(CardName))
	{
		FString Name;
		if(G->Entries.IsValidIndex(G->SelectedIndex)){const auto& E=G->Entries[G->SelectedIndex];Name=(E.LastName+TEXT(" ")+E.FirstName).TrimStartAndEnd();if(Name.IsEmpty())Name=E.FileName;}
		if(T->GetText().ToString()!=Name)T->SetText(FText::FromString(Name));
		if(NamePlate)NamePlate->SetShown(!Name.IsEmpty());
		if(CameraBar)CameraBar->SetShown(G->bModelLayout);
	}
}

void UOKReaderScreen::Tick(float DeltaSeconds)
{
	if(!bBuilt&&Controller.IsValid())
	{
		bBuilt=true;
		BuildCategories();BuildDrawers();BuildCameraBar();BuildPluginTools();Layout();
		bShownModelLayout=Controller->bModelLayout;ShowTab(bShownModelLayout?0:1);
	}
	if(!bBuilt)return;
	TickResize();
	SyncAll();
}

FString UOKReaderScreen::CurrentTab() const
{
	static const TCHAR* Names[]={TEXT("編輯"),TEXT("人物卡"),TEXT("衣服卡"),TEXT("設定")};return Names[FMath::Clamp(Tab,0,3)];
}
FString UOKReaderScreen::CurrentCategory() const{return Categories.IsValidIndex(Category)?Categories[Category].Name:FString();}
bool UOKReaderScreen::SelectCategory(const FString& Name)
{
	for(int32 I=0;I<Categories.Num();++I)if(Categories[I].Name==Name){if(Categories[I].Tab!=Tab)ShowTab(Categories[I].Tab);ShowCategory(I);return true;}
	return false;
}
bool UOKReaderScreen::SelectSub(const FString& Name)
{
	if(!Categories.IsValidIndex(Category))return false;
	const auto& Groups=Categories[Category].Groups;for(int32 I=0;I<Groups.Num();++I)if(Groups[I].Name==Name){ShowCategory(Category,I);return true;}
	return false;
}

// For the player controller: whether the pointer is over this screen's panels rather than the 3D view.
bool OKReaderScreenUnderCursor()
{
	UOKReaderScreen* S=GScreen.Get();if(!S||!GEngine||!GEngine->GameViewport||!GEngine->GameViewport->Viewport)return false;
	if(auto* Events=UDreamEventSystem::GetDreamEventSystemInstance(S,0))if(Events->IsPointerOverUIByPointerID(0))return true;
	APlayerController* PC=S->GetOwningPlayer();float X=0,Y=0;if(!PC||!PC->GetMousePosition(X,Y))return false;
	const FIntPoint Size=GEngine->GameViewport->Viewport->GetSizeXY();if(Size.Y<=0)return false;
	const float Scale=Size.Y/1080.f;
	return X<=(S->GetLeftWidth()+10.f)*Scale||X>=Size.X-440.f*Scale||Y<=80.f*Scale;
}

// For the game MCP (ui_exec) and tests: the screen's own navigation, which has no UMG control to set.
//   ok.ReaderScreen tab <0-3> | category <name> | sub <name> | width <px> | state
static FAutoConsoleCommand GReaderScreenCommand(TEXT("ok.ReaderScreen"),
	TEXT("ok.ReaderScreen tab <0-3> | category <name> | sub <name> | width <px> | state: the card reader's DreamGUI screen"),
	FConsoleCommandWithWorldArgsAndOutputDeviceDelegate::CreateLambda([](const TArray<FString>& Args,UWorld*,FOutputDevice& Out)
	{
		UOKReaderScreen* S=GScreen.Get();
		if(!S){Out.Log(TEXT("no reader screen"));return;}
		const FString Verb=Args.Num()>0?Args[0]:TEXT("state");
		const FString Value=Args.Num()>1?FString::Join(TArrayView<const FString>(Args).RightChop(1),TEXT(" ")):FString();
		bool Done=true;
		if(Verb==TEXT("tab")){Done=Value.IsNumeric();if(Done)S->ShowTabPublic(FCString::Atoi(*Value));}
		else if(Verb==TEXT("category"))Done=S->SelectCategory(Value);
		else if(Verb==TEXT("sub"))Done=S->SelectSub(Value);
		else if(Verb==TEXT("width")){Done=Value.IsNumeric();if(Done)S->SetLeftWidth(FCString::Atof(*Value));}
		else if(Verb==TEXT("dump"))
		{
			// The DreamGUI tree as laid out: name, class, visual, position, size, shown, layout container.
			TFunction<void(UDreamWidget*,int32)> Walk=[&](UDreamWidget* W,int32 Depth)
			{
				if(!W||Depth>14)return;
				FString Layout;for(UDreamUIBehaviour* C:W->GetAllComponents())if(C&&C->GetClass()->GetName().Contains(TEXT("Layout")))Layout=C->GetClass()->GetName();
				const FVector2D P=W->GetAnchoredPosition(),Z=W->GetSizeDelta();
				Out.Logf(TEXT("%s%s [%s%s%s] pos=(%.0f,%.0f) size=(%.0f,%.0f)%s"),*FString::ChrN(Depth*2,TEXT(' ')),*W->GetDisplayName(),*W->GetClass()->GetName(),W->GetVisual()?TEXT(" "):TEXT(""),W->GetVisual()?*W->GetVisual()->GetClass()->GetName():TEXT(""),P.X,P.Y,Z.X,Z.Y,W->GetShown()?*(Layout.IsEmpty()?FString():TEXT(" ")+Layout):TEXT(" HIDDEN"));
				if(!W->GetShown())return;
				if(auto* U=Cast<UDreamUserWidget>(W))if(U->GetWidgetTree()&&U->GetWidgetTree()->GetRootWidget()&&!U->GetChildren().Contains(U->GetWidgetTree()->GetRootWidget()))Walk(U->GetWidgetTree()->GetRootWidget(),Depth+1);
				for(UDreamWidget* C:W->GetChildren())Walk(C,Depth+1);
			};
			Walk(S,0);
		}
		Out.Logf(TEXT("%s tab=%s category=%s left_width=%.0f"),Done?TEXT("ok"):TEXT("failed"),*S->CurrentTab(),*S->CurrentCategory(),S->GetLeftWidth());
	}));
