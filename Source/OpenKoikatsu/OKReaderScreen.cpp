#include "OKReaderScreen.h"
#include "UObject/UObjectIterator.h"
#include "Engine/Texture.h"
#include "RHIStats.h"
#include "DynamicRHI.h"
bool OKReaderPicturesShown();	// ok.ReaderPictures (below)
#include "DreamUIRender/DreamUIShaderGate.h"
#include "OKCharacterController.h"
#include "OKCardListView.h"
#include "OKMotionComboBox.h"
#include "KKShapeRows.h"
#include "OKShapeSlider.h"
#include "OKAppearanceButton.h"
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
#include "Core/Components/DreamLayout.h"
#include "Core/DreamScreenUISubsystem.h"
#include "DreamUIBPLibrary.h"
#include "Controls/DreamButton.h"
#include "Controls/DreamSlider.h"
#include "Controls/DreamToggle.h"
#include "Controls/DreamDropdown.h"
#include "Controls/DreamTextInput.h"
#include "Controls/DreamScrollBox.h"
#include "Event/DreamEventSystem.h"
#include "Event/DreamPointerEventData.h"
#include "Event/DreamUIInputTypes.h"
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
#include "KKGameRoot.h"
#include "IImageWrapper.h"
#include "IImageWrapperModule.h"
#include "HAL/PlatformFileManager.h"
#include "HAL/FileManager.h"
#include "Async/Async.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"
#include "Tasks/Task.h"
#include "Engine/Texture2D.h"
#if PLATFORM_WINDOWS
// The folder picker. winnls.h's surrogate macros broke DreamUITextData.h in a unity file after this one (ERROR_LOG
// 2026-11-18): they are put back as they were around the system headers.
#pragma push_macro("HIGH_SURROGATE_START")
#pragma push_macro("HIGH_SURROGATE_END")
#pragma push_macro("LOW_SURROGATE_START")
#pragma push_macro("LOW_SURROGATE_END")
#include "Windows/AllowWindowsPlatformTypes.h"
#include <shobjidl.h>
#include "Windows/HideWindowsPlatformTypes.h"
#pragma pop_macro("LOW_SURROGATE_END")
#pragma pop_macro("LOW_SURROGATE_START")
#pragma pop_macro("HIGH_SURROGATE_END")
#pragma pop_macro("HIGH_SURROGATE_START")
#endif

namespace
{
const TCHAR* GScreenPath=TEXT("/Game/UI/Reader/WBP_ReaderScreen.WBP_ReaderScreen_C");
TWeakObjectPtr<UOKReaderScreen> GScreen;

// Who moved the reader's camera last (ok.ReaderScreen look): the player controller says so when the mouse turns, pans or
// zooms it (OKNoteCameraChange); a change nobody announced came from elsewhere (a view button, the MCP, a load).
namespace OKReaderCameraWatch
{
	FString NotedWho;uint64 NotedFrame=0;
	FString LastWho;double LastAt=0;FString LastButtons;
	bool bHave=false;float Yaw=0,Pitch=0,Distance=0;FVector Focus=FVector::ZeroVector;
	FString PressedButtons()
	{
		if(!FSlateApplication::IsInitialized())return TEXT("-");
		FString Out;for(const FKey& K:FSlateApplication::Get().GetPressedMouseButtons()){if(!Out.IsEmpty())Out+=TEXT("+");Out+=K.ToString();}
		return Out.IsEmpty()?TEXT("none"):Out;
	}
}

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
void OKNoteCameraChange(const FString& Who){OKReaderCameraWatch::NotedWho=Who;OKReaderCameraWatch::NotedFrame=GFrameCounter;}

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
	if(auto* T=TextOf(Arrow))T->SetText(FText::FromString(bOpen?TEXT("▼"):TEXT("▶")));
}

void UOKDreamControl::Sync()
{
	UWidget* S=Source.Get();
	if(!S){if(!FixedText.IsEmpty())SetText(FixedText);return;}
	SetShown(IsUmgShown(S));
	// The search field only for a list long enough to need one (the lighting presets are OKMotionComboBoxes of a few
	// entries, and showed "搜尋動作" over them), and while it holds a filter.
	if(Companion.IsValid())
	{
		const UComboBoxString* Combo=Cast<UComboBoxString>(S);
		const bool bWant=GetShown()&&(!Combo||Combo->GetOptionCount()>=SearchMinOptions||!Filter.IsEmpty());
		if(Companion->GetShown()!=bWant)Companion->SetShown(bWant);
	}
	if(!GetShown())return;
	TGuardValue<bool> Guard(bPushing,true);
	if(auto* Drawer=Cast<UOKDrawerButton>(S))
	{
		SetText(FixedText.IsEmpty()?Drawer->Title:FixedText);
		if(Drawer->bOpen!=bOpen)SetOpen(Drawer->bOpen);
		return;
	}
	// A picture-picker tile: its thumbnail over its caption, the item the card has marked.
	if(auto* A=Cast<UOKAppearanceButton>(S))
	{
		SetText((A->bChosen?TEXT("▶ "):TEXT(""))+TextIn(A->Caption));
		if(Button)Button->SetIsEnabled(A->GetIsEnabled());
		UTexture* Texture=A->Thumbnail&&OKReaderPicturesShown()?Cast<UTexture>(A->Thumbnail->GetBrush().GetResourceObject()):nullptr;
		if(Picture&&Texture!=ShownTexture.Get())
		{
			ShownTexture=Texture;
			if(auto* Image=Cast<UDreamImage>(Picture->GetVisual())){FDreamUIImageBrush Brush=Image->GetBrush();Brush.SetResourceObject(Texture);Image->SetBrush(Brush);}
			Picture->SetShown(Texture!=nullptr);
		}
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
		// The chosen option on one line, cut with "..." (a long one wrapped to three lines over the next row).
		if(!bCaptionFitted&&Choice->CaptionNode)if(UDreamText* T=TextOf(Choice->CaptionNode)){T->SetAutoWrapText(false);T->SetOverflowType(EDreamUITextOverflowType::Ellipsis);bCaptionFitted=true;}
		// The options the filter keeps (all without one), each mapped to its UMG index. Built again when the filter, the
		// option count or (unfiltered) any option changed.
		const int32 Count=U->GetOptionCount();
		bool Same=ShownSourceCount==Count&&ShownFilter==Filter;
		for(int32 I=0;Same&&Filter.IsEmpty()&&I<ShownOptions.Num();++I)Same=ShownOptions[I]==U->GetOptionAtIndex(I);
		if(!Same)
		{
			ShownSourceCount=Count;ShownFilter=Filter;ShownOptions.Reset();OptionMap.Reset();
			if(Filter.IsEmpty())for(int32 I=0;I<Count;++I){ShownOptions.Add(U->GetOptionAtIndex(I));OptionMap.Add(I);}
			// The motion list searches its labels as its own popup does (names, ids, the display label; words ANDed).
			else if(auto* M=Cast<UOKMotionComboBox>(U))
			{
				M->SetSearchText(FText::FromString(Filter));
				for(const FString& O:M->GetFilteredOptions()){const int32 I=U->FindOptionIndex(O);if(I>=0){ShownOptions.Add(O);OptionMap.Add(I);}}
			}
			else for(int32 I=0;I<Count;++I)if(U->GetOptionAtIndex(I).Contains(Filter)){ShownOptions.Add(U->GetOptionAtIndex(I));OptionMap.Add(I);}
			TArray<FText> Options;for(const FString& O:ShownOptions)Options.Add(FText::FromString(O));
			Choice->SetOptions(Options);
		}
		const int32 Index=OptionMap.IndexOfByKey(U->GetSelectedIndex());if(Choice->GetSelectedIndex()!=Index)Choice->SetSelectedIndex(Index);
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
		UTexture* Texture=OKReaderPicturesShown()?Cast<UTexture>(U->GetBrush().GetResourceObject()):nullptr;
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
// ok.ReaderPictures 0: no picture tile or mirrored image draws its texture (a comparison run for the open GPU page
// fault, Docs/CARD_READER_DREAMGUI.md): the tiles and their captions stay, the pictures do not.
static TAutoConsoleVariable<int32> CVarReaderPictures(TEXT("ok.ReaderPictures"),1,TEXT("Pictures in the reader's DreamGUI screen (picker tiles, mirrored images, card list): 1 drawn (default), 0 none (for comparison runs)."));
bool OKReaderPicturesShown(){return CVarReaderPictures.GetValueOnGameThread()!=0;}

bool UOKDreamControl::Press()
{
	if(!GetShown())return false;
	if(Header){HandleHeader();return true;}
	if(auto* U=Cast<UCheckBox>(Source.Get()))
	{
		if(!Toggle||!U->GetIsEnabled())return false;
		HandleToggle(!U->IsChecked());return true;
	}
	if(!Button||!Button->GetIsEnabled())return false;
	HandleClicked();return true;
}
bool UOKDreamControl::SetValue(const FString& Value,FString* OutNote)
{
	auto Fail=[OutNote](const FString& Why){if(OutNote)*OutNote=Why;return false;};
	if(!GetShown())return Fail(TEXT("not shown"));
	UWidget* S=Source.Get();
	if(!S||!S->GetIsEnabled())return Fail(TEXT("no enabled control behind it"));
	if(auto* U=Cast<USlider>(S))
	{
		if(!Value.IsNumeric())return Fail(TEXT("a slider takes a number"));
		const float V=FCString::Atof(*Value);
		if(V<U->GetMinValue()-1e-4f||V>U->GetMaxValue()+1e-4f)return Fail(FString::Printf(TEXT("out of range %g..%g"),U->GetMinValue(),U->GetMaxValue()));
		HandleSlider(V);return true;
	}
	if(Cast<UCheckBox>(S))
	{
		const FString L=Value.ToLower();
		const bool bOn=L==TEXT("1")||L==TEXT("on")||L==TEXT("true");
		if(!bOn&&L!=TEXT("0")&&L!=TEXT("off")&&L!=TEXT("false"))return Fail(TEXT("a toggle takes on/off/1/0"));
		HandleToggle(bOn);return true;
	}
	if(auto* U=Cast<UComboBoxString>(S))
	{
		int32 Index=U->FindOptionIndex(Value);
		if(Index==INDEX_NONE&&Value.IsNumeric())Index=FCString::Atoi(*Value);
		if(Index<0||Index>=U->GetOptionCount())return Fail(TEXT("no option ")+Value);
		const int32 ShownIndex=OptionMap.IsEmpty()?Index:OptionMap.IndexOfByKey(Index);
		if(ShownIndex==INDEX_NONE)return Fail(TEXT("option hidden by the filter: ")+Value);
		HandleChoice(ShownIndex);return true;
	}
	if(Cast<UEditableTextBox>(S)){HandleInputCommitted(Value);return true;}
	return Fail(TEXT("it takes no value"));
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
	if(OptionMap.IsValidIndex(Index))Index=OptionMap[Index];
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
	// A stage on a base cooked before DreamGUI has none of its global shaders (startup no longer requires them,
	// DreamUIShaderGate.h): drawing the screen there would fail on the GPU, so the reader says what to rebuild and
	// keeps its UMG controls instead of stopping.
	{
		FString Why;
		if(!DreamGUIGlobalShadersReady(&Why))
		{
			UE_LOG(LogTemp,Error,TEXT("ok.ReaderScreen: %s"),*Why);
			if(GEngine)GEngine->AddOnScreenDebugMessage(-1,600.f,FColor::Red,Why);
			return nullptr;
		}
	}
	UClass* Class=LoadClass<UOKReaderScreen>(nullptr,GScreenPath);
	if(!Class){UE_LOG(LogTemp,Warning,TEXT("Reader screen %s missing: the reader keeps its UMG controls"),GScreenPath);return nullptr;}
	// D3D12 moves textures to compact its texture pool (after a collection frees many, a card switch); with the reader's
	// DreamGUI screen up, a draw then sampled a moved texture's old place: a GPU page fault ("DefragFree: 1" on the
	// released texture in the D3D12 tracking log). 2026-11-19: eight rounds of card loads + source switches + obj gc with
	// the defrag off, none crashed; with it on, every run crashed in round 1-3. Which draw keeps the stale binding is not
	// found yet: the defrag stays off while the reader screen runs (the other modes keep it).
	if(IConsoleVariable* Defrag=IConsoleManager::Get().FindConsoleVariable(TEXT("d3d12.VRAMTexturePoolDefrag")))
	{
		if(Defrag->GetInt()!=0){Defrag->Set(0,ECVF_SetByCode);UE_LOG(LogTemp,Display,TEXT("ok.ReaderScreen: d3d12.VRAMTexturePoolDefrag 0 (texture pool defrag off while the DreamGUI reader runs)"));}
	}
	// Design pixels on a 1080-high screen, whatever the window.
	if(auto* Screens=UDreamScreenUISubsystem::Get(Controller->GetWorld()))if(UDreamCanvas* Canvas=Screens->GetScreenCanvas(Controller->GetOwningPlayer()))
	{
		Canvas->SetScaleMode(EDreamCanvasScaleMode::ScaleWithScreenSize);Canvas->SetReferenceResolution(FVector2D(1920,1080));Canvas->SetMatchFromWidthToHeight(1.f);
	}
	auto* Screen=Cast<UOKReaderScreen>(UDreamUIBPLibrary::AddWidgetOfClassToViewport(Controller,Class,10));
	if(!Screen)return nullptr;
	Screen->Controller=Controller;GScreen=Screen;
	// The picker's 前往 設定 › 遊戲目錄 (shown when there is no game folder): the page switch waits for the next frame, as
	// the switch destroys the very button whose click asked for it.
	Controller->OnWantGameRootSettings=[Weak=TWeakObjectPtr<UOKReaderScreen>(Screen)]()
	{
		AsyncTask(ENamedThreads::GameThread,[Weak]()
		{
			UOKReaderScreen* Self=Weak.Get();if(!IsValid(Self))return;
			for(int32 I=0;I<Self->Categories.Num();++I)if(Self->Categories[I].Name==TEXT("設定／介面"))
			{
				const int32 Sub=Self->Categories[I].Groups.IndexOfByPredicate([](const FGroup& Each){return Each.Name==TEXT("遊戲目錄");});
				Self->ShowCategory(I,FMath::Max(0,Sub));return;
			}
		});
	};
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

// Whether a UMG widget sits in the property editor (配件／屬性).
bool UOKReaderScreen::InPropertyPanel(UWidget* W) const
{
	const UOKCharacterController* G=Controller.Get();
	UWidget* Panel=G?G->PropertyPanel.Get():nullptr;
	for(UWidget* At=W;At&&Panel;At=At->GetParent())if(At==Panel)return true;
	return false;
}

// A row's caption: the first child of a row of several, a text followed by a value control (a slider, drop-down, field
// or tick box, maybe in a size box).
bool UOKReaderScreen::IsRowCaption(UWidget* W)
{
	UWidget* Cell=W;UPanelWidget* Row=W?W->GetParent():nullptr;
	if(Row&&Row->IsA<USizeBox>()&&Row->GetChildrenCount()==1){Cell=Row;Row=Row->GetParent();}
	if(!Row||!Row->IsA<UHorizontalBox>()||Row->GetChildIndex(Cell)!=0||Row->GetChildrenCount()<2)return false;
	UWidget* Next=Row->GetChildAt(1);
	if(auto* Size=Cast<USizeBox>(Next);Size&&Size->GetChildrenCount()==1)Next=Size->GetChildAt(0);
	return Next&&(Next->IsA<USlider>()||Next->IsA<UComboBoxString>()||Next->IsA<UEditableTextBox>()||Next->IsA<USpinBox>()||Next->IsA<UCheckBox>());
}

// The name column's width: one rule for every page, a share of the page between the rail and the panel's edge.
float UOKReaderScreen::CaptionWidth() const
{
	return FMath::RoundToFloat(FMath::Clamp((LeftWidth-204.f)*0.32f,110.f,240.f));
}

// One UMG widget, and everything under it, as DreamGUI controls under Parent. bInRow: Parent lays out across.
// A row of three or more buttons and nothing else (匯出這套服裝 / 穿上 OK 服裝 / 轉換服裝) at their natural widths ran past
// the column's right edge: such a row shares the width equally, each label on one line, shrunk when long.
static void FitButtonRow(UDreamWidget* Target)
{
	const TArray<UDreamWidget*> Row(Target->GetChildren());
	int32 Buttons=0;
	for(UDreamWidget* Child:Row){const UOKDreamControl* C=Cast<UOKDreamControl>(Child);if(!C||!C->Button)return;if(C->GetShown())++Buttons;}
	if(Buttons<3)return;
	for(UDreamWidget* Child:Row)
	{
		Child->SetWidth(0);
		if(auto* Slot=Child->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
		if(UDreamText* T=TextOf(Cast<UOKDreamControl>(Child)->Label)){T->SetAutoWrapText(false);T->SetOverflowType(EDreamUITextOverflowType::HorizontalOverflow);T->SetBestFit(true);T->SetBestFitMinSize(12.f);}
	}
}

void UOKReaderScreen::Mirror(UWidget* Source,UDreamWidget* Into,bool bInRow)
{
	if(!Source||!Into)return;
	if(Source->IsA<UOKDrawerButton>())return;	// the right panel's drawers show these
	// The picker's 關閉 would fold the picker away out of the page it is part of.
	if(UOKCharacterController* Owner=Controller.Get())if(Source==Owner->AppearanceCloseButton)return;
	if(Source->IsA<UListView>())return;	// the card list has a page of its own
	auto Place=[&](UOKDreamControl* C,float RowWidth,bool bFill)
	{
		if(!C)return;C->Source=Source;C->Sync();
		if(bInRow){if(RowWidth>0)C->SetWidth(RowWidth);if(bFill)if(auto* Slot=C->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);}
	};
	// The picture picker's items: a tile with the item's thumbnail (the button's own label is only its caption).
	// Every tile the same size (a long caption such as 類型 1806 · 模組 widened its tile, so rows held two or three).
	if(Source->IsA<UOKAppearanceButton>()){if(UOKDreamControl* C=MakeControl(TEXT("PickTile"),Into)){C->Source=Source;if(C->Picture)C->Picture->SetShown(false);if(UDreamPanelSlot* Slot=C->GetPanelSlot()){Slot->SetMinDesiredSize(FVector2D(112,150));Slot->SetMaxDesiredSize(FVector2D(112,150));}C->Sync();}return;}
	if(Source->IsA<UButton>()){UOKDreamControl* C=MakeControl(TEXT("Button"),Into);const FString T=TextIn(Source);Place(C,FMath::Max(56.f,TextWidth(T,20.f)+36.f),false);return;}
	if(Source->IsA<USlider>()){Place(MakeControl(TEXT("Slider"),Into),0,true);return;}
	if(Source->IsA<UCheckBox>()){Place(MakeControl(TEXT("Toggle"),Into),FMath::Max(80.f,TextWidth(TextIn(Source),18.f)+56.f),false);return;}
	// The motion lists run to tens of thousands of entries: a search field above the drop-down narrows it, as the UMG
	// popup's own search box did.
	if(Source->IsA<UOKMotionComboBox>())
	{
		UDreamWidget* Box=MakePanel(Into,false,4.f);if(!Box)return;
		if(bInRow)if(auto* Slot=Box->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
		UOKDreamControl* Search=MakeControl(TEXT("Input"),Box);
		UOKDreamControl* C=MakeControl(TEXT("Choice"),Box);if(!C)return;
		C->Source=Source;C->Companion=Search;
		if(Search&&Search->Input)
		{
			Search->Input->SetPlaceholder(FText::FromString(TEXT("搜尋動作（名稱或編號，空格隔開多個詞）")));
			// Not kept across a rebuild of its panel: measured 2026-11-18 (ui_type while playing motions, switching outfit,
			// drawers, tabs and cards) and no panel holding it was mirrored again; SyncAll logs it if one ever is.
			Search->Input->GetOnTextChangedEvent().AddWeakLambda(C,[C](const FString& Text){C->Filter=Text.TrimStartAndEnd();C->Sync();});
		}
		C->Sync();return;
	}
	// The property editor's rows (caption, value, 撤銷): the caption a fixed column on one line, the value filling the rest,
	// so the rows line up whatever their caption's length (2026-11-18: captions of every length pushed the values about,
	// a "0" field shrank to its digit and long choices wrapped over the next row).
	const bool bPropertyRow=bInRow&&InPropertyPanel(Source);
	if(Source->IsA<UComboBoxString>()){Place(MakeControl(TEXT("Choice"),Into),0,true);return;}
	if(Source->IsA<UEditableTextBox>()||Source->IsA<USpinBox>()){UOKDreamControl* C=MakeControl(TEXT("Input"),Into);Place(C,bPropertyRow?0.f:bInRow?84.f:0.f,bPropertyRow);
		// The UMG field's hint (搜尋名稱、編號或模組來源 ...) as the placeholder: an empty box said nothing.
		if(auto* E=Cast<UEditableTextBox>(Source))if(C&&C->Input&&!E->GetHintText().IsEmpty())C->Input->SetPlaceholder(E->GetHintText());
		return;}
	if(Source->IsA<UTextBlock>())
	{
		UOKDreamControl* C=MakeControl(TEXT("Label"),Into);
		const bool bCaption=bInRow&&IsRowCaption(Source);
		Place(C,bCaption?CaptionWidth():FMath::Min(200.f,TextWidth(TextIn(Source),18.f)+12.f),false);
		if(!C)return;
		// A caption is the row's name column: the same width on every page (臉, 身子, 屬性, 光影 ...), so the values
		// start at one x whichever page is shown. A longer name wraps (and the row grows) rather than lose its end --
		// "物理／頭髮（後髮）" and "（前髮）" differ only there.
		UDreamPanelSlot* Slot=C->GetPanelSlot();
		if(bCaption&&Slot)
		{
			const float Width=CaptionWidth();
			Slot->SetMinDesiredSize(FVector2D(Width,Slot->MinDesiredSize.Y));Slot->SetMaxDesiredSize(FVector2D(Width,0));
			if(UDreamText* T=TextOf(C->Label))T->SetAutoWrapText(true);
		}
		// Down a column a long text wraps: the line grows with it instead of keeping the designed 30 and drawing over the
		// row under it.
		else if(!bInRow&&Slot)Slot->SetMaxDesiredSize(FVector2D::ZeroVector);
		return;
	}
	if(Source->IsA<UImage>()){Place(MakeControl(TEXT("Image"),Into),0,false);return;}
	// A size box in a row only gives its child a width: keep the width, drop the box.
	if(auto* Size=Cast<USizeBox>(Source);Size&&bInRow&&Size->GetChildrenCount()==1)
	{
		const int32 Before=Into->GetChildren().Num();Mirror(Size->GetChildAt(0),Into,true);
		// (Not a caption's: the name column has its own width.)
		if(Into->GetChildren().Num()>Before&&Size->GetWidthOverride()>0&&!IsRowCaption(Size->GetChildAt(0)))Into->GetChildren().Last()->SetWidth(Size->GetWidthOverride());
		return;
	}
	if(Source->IsA<UPanelWidget>()||Source->IsA<UUserWidget>())
	{
		// The picture picker's grid wraps its tiles into rows as wide as the page (one row of 32 ran off the panel).
		UOKCharacterController* G=Controller.Get();
		const bool bWrap=G&&Source==G->AppearanceGrid;
		const bool bHorizontal=!bWrap&&(Source->IsA<UHorizontalBox>()||Source->IsA<UWrapBox>());
		UDreamWidget* Target=nullptr;
		if(bWrap)
		{
			Target=UDreamUIBPLibrary::ConstructWidget(this,TEXT("PickGrid"),nullptr);
			if(Target)
			{
				if(auto* Wrap=Target->CreateNewLayoutContainer<UDreamLayoutContainerWrapBox>())Wrap->SetSpacing(FVector2D(6,6));
				Target->SetSizeDelta(FVector2D::ZeroVector);AddToHost(Into,Target,false);
			}
		}
		else Target=MakePanel(Into,bHorizontal,bHorizontal?6.f:6.f);
		if(!Target)return;
		if(bInRow)if(auto* Slot=Target->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
		FOKDreamMirrorPanel Panel;Panel.Source=Cast<UPanelWidget>(Source);Panel.Target=Target;Panel.bHorizontal=bHorizontal;
		const TArray<UWidget*> Kids=ChildrenOf(Source);Panel.Children=Kids.Num();for(UWidget* K:Kids)Panel.Kids.Add(K);
		Target->SetShown(IsUmgShown(Source));
		for(UWidget* Child:Kids)Mirror(Child,Target,bHorizontal);
		if(bHorizontal)FitButtonRow(Target);
		if(Panel.Source.IsValid())Panels.Add(Panel);
	}
}

void UOKReaderScreen::MirrorChildren(UPanelWidget* Source,UDreamWidget* Target,bool bHorizontal)
{
	if(!Source||!Target)return;
	for(UDreamWidget* Child:TArray<UDreamWidget*>(Target->GetChildren()))if(Child)Child->DestroyWidget();
	for(int32 I=0;I<Source->GetChildrenCount();++I)Mirror(Source->GetChildAt(I),Target,bHorizontal);
	if(bHorizontal)FitButtonRow(Target);
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

	// A page's part of the picture picker (target-key prefixes) and of the detailed editor (tokens in a property's key or
	// label), both under the page's own sliders: 眉毛 lists the eyebrow kinds and colours, not every target of the card.
	// Asked for again by SyncAll while the controller is busy: reading the catalog, it opens neither panel.
	auto Pickers=[this,G](FGroup& Into,const TArray<FString>& Targets,const TArray<FString>& Properties)
	{
		if(!Targets.IsEmpty()&&G->AppearancePanel)Into.Sources.Add(G->AppearancePanel.Get());
		if(!Properties.IsEmpty()&&G->PropertyPanel)Into.Sources.Add(G->PropertyPanel.Get());
		// Without a character in 3D the picker and the detailed editor have nothing to read (both work on the loaded card):
		// the page says so, and is built again once a character is in (the signature changes).
		TFunction<void(UDreamWidget*)> BeforeBuild=MoveTemp(Into.Build);
		Into.Build=[this,BeforeBuild](UDreamWidget* Page)
		{
			if(BeforeBuild)BeforeBuild(Page);
			UOKCharacterController* C=Controller.Get();
			if(C&&!C->bModelLayout)if(UOKDreamControl* L=MakeControl(TEXT("Label"),Page))
			{
				const FString Say=TEXT("要先在「人物卡總欄」選一張卡並按「載入3D」，這裡才有外觀選擇與詳細編輯。");
				L->FixedText=Say;L->SetText(Say);
				if(UDreamPanelSlot* Slot=L->GetPanelSlot())Slot->SetMaxDesiredSize(FVector2D::ZeroVector);
			}
		};
		TFunction<FString()> BeforeSignature=MoveTemp(Into.Signature);
		Into.Signature=[this,BeforeSignature]()
		{
			const UOKCharacterController* C=Controller.Get();
			return (C&&C->bModelLayout?TEXT("3d|"):TEXT("none|"))+(BeforeSignature?BeforeSignature():FString());
		};
		TFunction<void()> Before=MoveTemp(Into.OnEnter);
		Into.OnEnter=[this,Targets,Properties,Before]()
		{
			if(Before)Before();
			if(!Targets.IsEmpty())WantedTargets=Targets;
			if(!Properties.IsEmpty())WantedProperties=Properties;
			ApplyWantedScopes();
		};
	};
	// The bone category drop-down decides which rows of the shared slider column show: anything but 原遊戲參數 folds the
	// face and body sliders away (they are the same UMG rows the 臉 and 身子 pages mirror). Each page sets the one it needs.
	auto BoneCategory=[G](const FString& Want)
	{
		return TFunction<void()>([Weak=TWeakObjectPtr<UOKCharacterController>(G),Want]()
		{
			if(Weak.IsValid()&&Weak->BoneCategoryCombo&&Weak->BoneCategoryCombo->GetSelectedOption()!=Want)Weak->BoneCategoryCombo->SetSelectedOption(Want);
		});
	};
	// 胸部柔軟度／胸部重量 (shown under 原遊戲參數) go with the breast sliders; the bone rows are what follows the last
	// slider row in the same column (the category drop-down, the X／Y／Z switch, then the rows of the chosen category).
	TArray<UWidget*> BustRows;
	for(UOKShapeSlider* S:G->BoneSliders)if(S&&!S->BodyParameter.IsEmpty()&&S->ModRow)BustRows.Add(S->ModRow);
	TArray<UWidget*> BoneRows;
	if(G->ShapeBox&&G->ShapeSliders.Num())
	{
		const int32 Last=G->ShapeBox->GetChildIndex(G->ShapeSliders.Last()?G->ShapeSliders.Last()->GetParent():nullptr);
		for(int32 I=Last+1;Last>=0&&I<G->ShapeBox->GetChildrenCount();++I)
		{
			UWidget* W=G->ShapeBox->GetChildAt(I);
			if(!G->ShapeSeparators.Contains(W)&&!BustRows.Contains(W)&&W!=G->PregnancyBox&&W!=G->StyleBox&&W!=G->BoneCategoryCombo&&W!=G->BoneAxesCheck)BoneRows.Add(W);
		}
	}
	FCategory Face;Face.Name=TEXT("臉");Face.Groups=ShapeGroups(false,{TEXT("臉型"),TEXT("下巴"),TEXT("臉頰"),TEXT("眉毛"),TEXT("眼睛"),TEXT("鼻子"),TEXT("嘴巴"),TEXT("耳朵")});
	for(FGroup& Each:Face.Groups)
	{
		Each.OnEnter=BoneCategory(TEXT("原遊戲參數"));
		if(Each.Name==TEXT("眉毛"))Pickers(Each,{TEXT("eyebrow")},{TEXT("eyebrow")});
		else if(Each.Name==TEXT("眼睛"))Pickers(Each,{TEXT("pupil"),TEXT("gradation"),TEXT("eye_white"),TEXT("eye_hi_"),TEXT("eyeline_"),TEXT("eyeshadow")},{TEXT("pupil"),TEXT("grad"),TEXT("white"),TEXT("hlUp"),TEXT("hlDown"),TEXT("eyeline"),TEXT("eyeshadow")});
		else if(Each.Name==TEXT("臉頰"))Pickers(Each,{TEXT("cheek"),TEXT("mole")},{TEXT("cheek"),TEXT("mole")});
		else if(Each.Name==TEXT("鼻子"))Pickers(Each,{TEXT("nose")},{});
		else if(Each.Name==TEXT("嘴巴"))Pickers(Each,{TEXT("lip")},{TEXT("lip")});
	}
	// The pupil overlay textures (Material Editor overrides on the eye materials): read with eye_overlays when the page
	// opens, a tile per candidate under each slot that is drawn, and 無 to clear; a pick writes a new work card.
	{
		FGroup Overlays;Overlays.Name=TEXT("瞳孔覆蓋貼圖");Overlays.OnEnter=BoneCategory(TEXT("原遊戲參數"));
		Overlays.Signature=[G](){return FString::Printf(TEXT("%d|%d|%d|%d|%s"),G->bModelLayout?1:0,G->bLoadInFlight?1:0,G->EyeOverlayGeneration,G->bEyeOverlayBusy?1:0,*G->EyeOverlayStatus);};
		Overlays.Build=[this,G](UDreamWidget* Page){BuildEyeOverlayPage(Page);};
		int32 After=Face.Groups.IndexOfByPredicate([](const FGroup& Each){return Each.Name==TEXT("眼睛");});
		Face.Groups.Insert(MoveTemp(Overlays),After==INDEX_NONE?Face.Groups.Num():After+1);
	}
	// 眼部縮放2: the ABMX eye bones (cf_J_Eye_tz, cf_J_Eye_rz_L/R, cf_J_Eye_tx_L/R …, category FaceEyes2) as the original
	// game's eye page has them: the bone rows of 骨骼調整：眼球 with the X／Y／Z switch, without the category drop-down.
	if(BoneRows.Num())
	{
		FGroup EyeBones;EyeBones.Name=TEXT("眼部縮放2");EyeBones.bShownOnly=true;
		EyeBones.OnEnter=BoneCategory(TEXT("骨骼調整：眼球"));
		EyeBones.Signature=[Weak=TWeakObjectPtr<UOKCharacterController>(G)]()
		{
			if(!Weak.IsValid()||!Weak->BoneCategoryCombo)return FString();
			return Weak->BoneCategoryCombo->GetSelectedOption()+(Weak->BoneAxesCheck&&Weak->BoneAxesCheck->IsChecked()?TEXT("|axes"):TEXT(""));
		};
		if(G->BoneAxesCheck)EyeBones.Sources.Add(G->BoneAxesCheck.Get());
		for(UWidget* W:BoneRows)EyeBones.Sources.Add(W);
		int32 After=Face.Groups.IndexOfByPredicate([](const FGroup& Each){return Each.Name==TEXT("瞳孔覆蓋貼圖");});
		Face.Groups.Insert(MoveTemp(EyeBones),After==INDEX_NONE?Face.Groups.Num():After+1);
	}
	// The face's skin: head shape, skin detail and face paint (not on 臉型, the page a card opens on: entering a picker
	// page reads the card's catalog).
	{
		FGroup Skin;Skin.Name=TEXT("頭型與膚質");Skin.OnEnter=BoneCategory(TEXT("原遊戲參數"));
		Pickers(Skin,{TEXT("head"),TEXT("face_detail"),TEXT("facepaint")},{TEXT("detail"),TEXT("paint"),TEXT("skin")});
		Face.Groups.Add(MoveTemp(Skin));
	}
	Categories.Add(MoveTemp(Face));

	// Hair: its models (後髮, 前髮, 側髮, 附加頭髮, 光澤) and its colours and settings.
	{
		FCategory Hair;Hair.Name=TEXT("頭髮");
		FGroup Styles;Styles.Name=TEXT("髮型");Pickers(Styles,{TEXT("hair0"),TEXT("hair1"),TEXT("hair2"),TEXT("hair3"),TEXT("hair_gloss")},{});Hair.Groups.Add(MoveTemp(Styles));
		FGroup Colours;Colours.Name=TEXT("髮色與設定");Pickers(Colours,{},{TEXT("hair"),TEXT("髮")});Hair.Groups.Add(MoveTemp(Colours));
		Categories.Add(MoveTemp(Hair));
	}

	FCategory Body;Body.Name=TEXT("身子");Body.Groups=ShapeGroups(true,{TEXT("全身"),TEXT("胸部"),TEXT("軀幹"),TEXT("腰臀"),TEXT("手臂"),TEXT("腿部")});
	{
		for(FGroup& Each:Body.Groups)
		{
			Each.OnEnter=BoneCategory(TEXT("原遊戲參數"));
			if(Each.Name==TEXT("胸部"))for(UWidget* W:BustRows)Each.Sources.Add(W);
		}
		// The bone controls follow the last slider row in the same column: the category drop-down and the X／Y／Z switch
		// first. Only the rows the category shows are mirrored, the page built again when the category or the switch
		// changes: every bone row at once (骨骼調整：全部) held the frame 1.8 s (2026-11-18), so it opens on the first
		// bone category.
		FGroup Bones;Bones.Name=TEXT("骨骼");Bones.bShownOnly=true;
		Bones.Signature=[Weak=TWeakObjectPtr<UOKCharacterController>(G)]()
		{
			if(!Weak.IsValid()||!Weak->BoneCategoryCombo)return FString();
			return Weak->BoneCategoryCombo->GetSelectedOption()+(Weak->BoneAxesCheck&&Weak->BoneAxesCheck->IsChecked()?TEXT("|axes"):TEXT(""));
		};
		if(G->BoneCategoryCombo)Bones.Sources.Add(G->BoneCategoryCombo.Get());
		if(G->BoneAxesCheck)Bones.Sources.Add(G->BoneAxesCheck.Get());
		for(UWidget* W:BoneRows)Bones.Sources.Add(W);
		Bones.OnEnter=[Weak=TWeakObjectPtr<UOKCharacterController>(G)]()
		{
			if(!Weak.IsValid()||!Weak->BoneCategoryCombo)return;
			const FString Now=Weak->BoneCategoryCombo->GetSelectedOption();
			auto NotBones=[](const FString& O){return O==TEXT("原遊戲參數")||O==TEXT("骨骼調整：全部")||O==TEXT("角色風格")||O==TEXT("腹部形變");};
			if(!NotBones(Now))return;
			for(int32 I=0;I<Weak->BoneCategoryCombo->GetOptionCount();++I)
				if(!NotBones(Weak->BoneCategoryCombo->GetOptionAtIndex(I))){Weak->BoneCategoryCombo->SetSelectedIndex(I);return;}
		};
		if(Bones.Sources.Num())Body.Groups.Add(MoveTemp(Bones));
		if(G->PregnancyBox){Body.Groups.Add(Group(TEXT("懷孕"),{G->PregnancyBox.Get()}));Body.Groups.Last().OnEnter=BoneCategory(TEXT("腹部形變"));}
		// The body's skin: detail, tan lines, nipples, underhair, body paint.
		FGroup Skin;Skin.Name=TEXT("皮膚");
		Pickers(Skin,{TEXT("body_detail"),TEXT("sunburn"),TEXT("nipple"),TEXT("underhair"),TEXT("bodypaint")},{TEXT("body."),TEXT("sunburn"),TEXT("nip"),TEXT("underhair")});
		Body.Groups.Add(MoveTemp(Skin));
	}
	Categories.Add(MoveTemp(Body));

	FCategory Clothes;Clothes.Name=TEXT("衣服");
	for(UOKDrawerButton* D:G->MotionDrawers)if(D&&D->Key==TEXT("Clothes")){Clothes.Groups.Add(Group(TEXT("穿著狀態"),{D->Body.Get()}));Clothes.Groups.Last().OnEnter=OpenDrawer(D);}
	Clothes.Groups.Add(Group(TEXT("服裝"),{G->OutfitCombo?static_cast<UWidget*>(G->OutfitCombo->GetParent()):nullptr,G->OutfitNav.Get()}));
	{FGroup Pick;Pick.Name=TEXT("外觀選擇");Pickers(Pick,{TEXT("clothes"),TEXT("pattern"),TEXT("emblem"),TEXT("sub")},{});Clothes.Groups.Add(MoveTemp(Pick));}
	{FGroup Colours;Colours.Name=TEXT("顏色與設定");Pickers(Colours,{},{TEXT("clothes")});Clothes.Groups.Add(MoveTemp(Colours));}
	for(FGroup& Each:Clothes.Groups)Each.Sources.RemoveAll([](const TWeakObjectPtr<UWidget>& W){return !W.IsValid();});
	Categories.Add(MoveTemp(Clothes));

	// Accessories: the slot first (配件欄 1 … 額外配件欄 N), then that slot's category and model; a new slot; the slots'
	// colours, offsets and bones; and the detailed editor whole (全部屬性).
	FCategory Accessory;Accessory.Name=TEXT("配件");
	{
		FGroup Slots;Slots.Name=TEXT("飾品");
		if(G->AppearancePanel)Slots.Sources.Add(G->AppearancePanel.Get());
		Slots.OnEnter=[this,Weak=TWeakObjectPtr<UOKCharacterController>(G)](){if(!Weak.IsValid())return;WantedTargets=TArray<FString>{Weak->AccessorySlotScope()};ApplyWantedScopes();};
		Slots.Build=[this](UDreamWidget* Page)
		{
			TWeakObjectPtr<UOKCharacterController> Weak(Controller);
			MakeOwnButton(Page,TEXT("新增飾品欄位"),[Weak](){if(Weak.IsValid())Weak->OnAddAccessorySlot();});
		};
		Accessory.Groups.Add(MoveTemp(Slots));
	}
	{FGroup Settings;Settings.Name=TEXT("飾品顏色與位置");Pickers(Settings,{},{TEXT("accessory"),TEXT("飾品")});Accessory.Groups.Add(MoveTemp(Settings));}
	// The property editor reads the card when opened; the empty token list is "all" here, so its scope is cleared by hand.
	{
		FGroup All=Group(TEXT("全部屬性"),{G->PropertyPanel.Get()});
		All.OnEnter=[this](){WantedProperties=TArray<FString>();ApplyWantedScopes();};
		Accessory.Groups.Add(MoveTemp(All));
	}
	Categories.Add(MoveTemp(Accessory));

	FCategory Info;Info.Name=TEXT("角色資訊");
	Info.Groups.Add(Group(TEXT("角色"),{G->InspectCol.Get()}));
	// The card wall's info column, collapsed once a card is open (SetModelLayout); the UMG layer is see-through and never
	// hit-tested, so showing it again only gives this page its mirror.
	Info.Groups.Last().OnEnter=[Weak=TWeakObjectPtr<UOKCharacterController>(G)](){if(Weak.IsValid()&&Weak->InspectCol)Weak->InspectCol->SetVisibility(ESlateVisibility::SelfHitTestInvisible);};
	Categories.Add(MoveTemp(Info));

	FCategory Cards;Cards.Name=TEXT("人物卡總欄");Cards.Tab=1;
	Cards.Groups.Add(Group(TEXT("人物卡"),{G->CardCol.Get()}));
	Categories.Add(MoveTemp(Cards));

	FCategory ClothesCards;ClothesCards.Name=TEXT("衣服卡總欄");ClothesCards.Tab=2;
	ClothesCards.Groups.Add(Group(TEXT("服裝卡"),{static_cast<UWidget*>(Named(TEXT("OkClothesRow")))}));
	Categories.Add(MoveTemp(ClothesCards));

	FCategory Settings;Settings.Name=TEXT("設定／介面");Settings.Tab=3;
	// The game folder (where zipmods are looked for) and the local library: a page of the screen's own, first.
	{FGroup Folders;Folders.Name=TEXT("遊戲目錄");Folders.Build=[this](UDreamWidget* Page){BuildGameRootPage(Page);};Settings.Groups.Add(MoveTemp(Folders));}
	for(UOKDrawerButton* D:G->MotionDrawers)if(D&&D->Key==TEXT("Lighting")){Settings.Groups.Add(Group(TEXT("光影"),{D->Body.Get()}));Settings.Groups.Last().OnEnter=OpenDrawer(D);}
	// The style box shows only under the bone category 角色風格 (OKGalleryBoneControls): this page selects it.
	if(G->StyleBox){Settings.Groups.Add(Group(TEXT("角色風格"),{G->StyleBox.Get()}));Settings.Groups.Last().OnEnter=BoneCategory(TEXT("角色風格"));}
	// The physics controls sit loose in the animation column, each after its caption: those pairs, not the whole column.
	{
		TArray<UWidget*> Physics;
		for(UWidget* W:{static_cast<UWidget*>(G->PhysicsBackendCombo.Get()),static_cast<UWidget*>(G->PhysicsSoftnessSlider.Get()),static_cast<UWidget*>(G->PhysicsWeightSlider.Get()),static_cast<UWidget*>(G->PhysicsTailSlider.Get())})
		{
			if(!W)continue;
			if(UPanelWidget* P=W->GetParent()){const int32 I=P->GetChildIndex(W);if(I>0&&Cast<UTextBlock>(P->GetChildAt(I-1)))Physics.Add(P->GetChildAt(I-1));}
			Physics.Add(W);
		}
		Settings.Groups.Add(Group(TEXT("物理"),Physics));
	}
	// No 介面 page: the UMG panel width and font size (EditorWidthInput, EditorFontInput) only resize the hidden UMG layer.
	for(FGroup& Each:Settings.Groups)Each.Sources.RemoveAll([](const TWeakObjectPtr<UWidget>& W){return !W.IsValid();});
	Settings.Groups.RemoveAll([](const FGroup& Each){return Each.Sources.IsEmpty()&&!Each.Build;});
	Categories.Add(MoveTemp(Settings));
}

void UOKReaderScreen::BuildDrawers()
{
	UOKCharacterController* G=Controller.Get();if(!G||!RightScroll)return;
	// The sketch (2026-11-18, again 11-18 noon): the titled drawers on top, folded, then the editor's own button block.
	for(UOKDrawerButton* D:G->MotionDrawers)
	{
		if(!D||D->Key==TEXT("Clothes")||D->Key==TEXT("Lighting"))continue;	// those are left-panel categories
		UOKDreamControl* Drawer=MakeControl(TEXT("Drawer"),RightScroll);if(!Drawer)continue;
		Drawer->Body=MakePanel(RightScroll,false,6.f);
		// Folded to their titles at first, as drawn; the UMG drawer folds with it (its layer is not seen).
		if(D->bOpen)D->SetOpen(false,false);
		Drawer->Source=D;Drawer->SetOpen(false);Drawers.Add(Drawer);
		if(D->Body)Mirror(D->Body,Drawer->Body,false);
		Drawer->Sync();
	}
	// The editor's own buttons, below the drawers (the user: "this belongs here").
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
				if(R->GetChildren().Num()<=Before)continue;
				// Equal thirds, one line each: a long label (重設到預設值, 進入1對1互動場景) shrinks to fit instead of
				// wrapping and making its row taller than the others.
				UDreamWidget* B=R->GetChildren().Last();B->SetWidth(0);
				if(auto* Slot=B->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
				if(auto* Control=Cast<UOKDreamControl>(B))if(UDreamText* T=TextOf(Control->Label))
				{
					T->SetAutoWrapText(false);T->SetOverflowType(EDreamUITextOverflowType::HorizontalOverflow);
					T->SetBestFit(true);T->SetBestFitMinSize(12.f);
				}
			}
		};
		Row({TEXT("ResetAllShapes"),TEXT("ShapeLoad3D"),TEXT("BackGallery")});
		Row({TEXT("EditorInteraction"),TEXT("EditorStudio"),TEXT("EditorStudioTimeline")});
		Row({TEXT("ModelApngSave"),TEXT("EditorSaveKks"),TEXT("EditorHands")});
		if(G->OutfitCombo)Mirror(G->OutfitCombo.Get(),Grid,false);
	}
}

void UOKReaderScreen::BuildCameraBar()
{
	if(!CameraBarHost)return;
	auto View=[this](float Yaw,float Pitch,float Distance,int32 Focus)
	{
		UOKCharacterController* G=Controller.Get();AKKPreviewActor* A=G?G->PreviewActor.Get():nullptr;if(!A)return;
		A->FrameCurrentPoseRealtime();	// no CPU-skinned readback (a package crashed in CacheVertices)
		const FVector Base=A->OrbitFocus;const float Full=A->OrbitDistance;
		// Focus: 0 whole body, 1 upper body, 2 face, 3 legs.
		if(Focus>0&&A->BodySkel)
		{
			const FName Bone=Focus==2?FName(TEXT("cf_j_head")):Focus==1?FName(TEXT("cf_j_spine03")):FName(TEXT("cf_j_leg01_L"));
			const FVector At=A->BodySkel->GetBoneLocation(Bone,EBoneSpaces::WorldSpace);
			if(!At.ContainsNaN()&&!At.IsNearlyZero())A->OrbitFocus=FVector(Base.X,Base.Y,At.Z+(Focus==2?6.f:0.f));
		}
		// OrbitYaw is the camera's bearing around her (0 = in front): set, not added, so 背面 twice stays behind her; NAN
		// (the framing buttons) keeps the side the camera is on.
		if(!FMath::IsNaN(Yaw)){A->OrbitYaw=Yaw;}A->OrbitPitch=Pitch;A->OrbitDistance=Full*Distance;A->ApplyOrbitCamera();
	};
	MakeOwnButton(CameraBarHost,TEXT("全身"),[View](){View(NAN,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("半身"),[View](){View(NAN,0,.55f,1);});
	MakeOwnButton(CameraBarHost,TEXT("臉部"),[View](){View(NAN,0,.22f,2);});
	MakeOwnButton(CameraBarHost,TEXT("腿部"),[View](){View(NAN,0,.6f,3);});
	MakeOwnButton(CameraBarHost,TEXT("正面"),[View](){View(0,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("左側"),[View](){View(-90,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("右側"),[View](){View(90,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("背面"),[View](){View(180,0,1,0);});
	MakeOwnButton(CameraBarHost,TEXT("俯視"),[View](){View(NAN,35,1,0);});
	// The bar is as wide as the 3D view between the panels: the buttons share what is over their own width, and
	// SetLeftWidth keeps the left panel from squeezing the view below that (they would run under the right panel).
	// Two characters each, on one line: at the narrowest view each keeps 64 design pixels (two 20 px glyphs and the
	// button's 12 px padding each side); the label never wraps (a squeezed one went vertical).
	CameraBarWidth=20.f;
	for(UDreamWidget* B:CameraBarHost->GetChildren())if(B)
	{
		B->SetWidth(40.f);CameraBarWidth+=64.f+6.f;
		if(UDreamPanelSlot* Slot=B->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);
		if(auto* Control=Cast<UOKDreamControl>(B))if(UDreamText* T=TextOf(Control->Label)){T->SetAutoWrapText(false);T->SetOverflowType(EDreamUITextOverflowType::HorizontalOverflow);}
	}
}

void UOKReaderScreen::BuildPluginTools()
{
	UOKCharacterController* G=Controller.Get();if(!G||!PluginHost)return;
	if(G->FpsText)Mirror(G->FpsText,PluginHost,true);
	if(UWidget* Fps=G->WidgetTree->FindWidget(TEXT("ReaderFps")))if(Fps!=G->FpsText)Mirror(Fps,PluginHost,true);
}

void UOKReaderScreen::ClearPage()
{
	// The card tiles let go of their pictures before the tiles and the textures go: no brush is left pointing at a
	// texture the next collection frees, whenever DreamGUI actually releases the destroyed tiles.
	for(UOKDreamControl* Tile:CardButtons)if(IsValid(Tile)&&Tile->Picture)
		if(auto* Image=Cast<UDreamImage>(Tile->Picture->GetVisual())){FDreamUIImageBrush Brush=Image->GetBrush();Brush.SetResourceObject(nullptr);Image->SetBrush(Brush);}
	for(UDreamWidget* W:PageWidgets)if(IsValid(W))W->DestroyWidget();
	PageWidgets.Reset();
	ShownPageHeight=-1.f;
	for(UOKDreamControl* B:SubButtons)if(IsValid(B))B->DestroyWidget();
	SubButtons.Reset();
	CardButtons.Reset();CardTexts.Reset();ShownCardSelection=INDEX_NONE;
	for(UTexture2D* T:CardThumbs)GiveBackThumb(T);
	CardThumbs.Reset();CardPaths.Reset();CardThumbLoading.Reset();ThumbsInFlight=0;++ThumbGeneration;
	*ThumbCancel=true;ThumbCancel=MakeShared<FThreadSafeBool>(false);
	WantedTargets.Reset();WantedProperties.Reset();
	RootInput.Reset();RootStatus.Reset();LibraryInput.Reset();LibraryStatus.Reset();++RootCheckGeneration;
	Controls.RemoveAll([](const TObjectPtr<UOKDreamControl>& C){return !IsValid(C);});
	Panels.RemoveAll([](const FOKDreamMirrorPanel& P){return !P.Target.IsValid()||!IsValid(P.Target.Get());});
}

// The card list marks the card the reader has (the one whose name is at the bottom right): a sign before its name, the
// others dimmed a little.
void UOKReaderScreen::MarkCurrentCard()
{
	UOKCharacterController* G=Controller.Get();if(!G||CardButtons.IsEmpty())return;
	const int32 Current=G->SelectedIndex;const int32 Unopenable=G->UnopenableCards.Num();
	if(Current==ShownCardSelection&&Unopenable==ShownUnopenable)return;
	ShownCardSelection=Current;ShownUnopenable=Unopenable;
	// A card that could not be read or opened stays in the list, marked (pressing it again tries again).
	for(int32 I=0;I<CardButtons.Num();++I)if(UOKDreamControl* B=CardButtons[I];IsValid(B)&&CardTexts.IsValidIndex(I))
	{
		const bool bBad=CardPaths.IsValidIndex(I)&&G->UnopenableCards.Contains(CardPaths[I]);
		// U+00A0 after the mark: the line breaks inside a long name rather than leave the mark alone on its own line.
		B->FixedText=(I==Current?TEXT("▶ "):TEXT(""))+FString(bBad?TEXT("開不了："):TEXT(""))+CardTexts[I];B->SetText(B->FixedText);
		B->SetRenderOpacity(I==Current||bBad?1.f:.72f);
	}
}

void UOKReaderScreen::ShowNotice(int32 Key,float Seconds,const FColor& Color,const FString& Text)
{
	UE_LOG(LogTemp,Display,TEXT("ok.ReaderScreen notice: %s"),*Text.Replace(TEXT("\n"),TEXT(" | ")));
	if(Text.IsEmpty()){Notes.Remove(Key);return;}
	FNote& N=Notes.FindOrAdd(Key);N.Text=Text.TrimEnd();N.Color=Color;N.Until=FPlatformTime::Seconds()+FMath::Max(Seconds,.5f);N.Order=++NoteOrder;
}

FString UOKReaderScreen::NoticeState() const
{
	TArray<const FNote*> Due;for(const auto& P:Notes)Due.Add(&P.Value);
	Due.Sort([](const FNote& A,const FNote& B){return A.Order<B.Order;});
	FString Out;for(const FNote* N:Due){if(!Out.IsEmpty())Out+=TEXT("\n");Out+=N->Text;}
	return Out;
}

// The notice under the camera bar: the reports still due, oldest first, coloured after the latest, as tall as its lines.
void UOKReaderScreen::TickNotice()
{
	const double Now=FPlatformTime::Seconds();
	for(auto It=Notes.CreateIterator();It;++It)if(It->Value.Until<=Now)It.RemoveCurrent();
	const FString Text=NoticeState();
	if(!Notice)return;
	if(Text.IsEmpty()){ShownNotice.Reset();if(bNoticeShown){bNoticeShown=false;Notice->SetShown(false);}return;}
	if(Text==ShownNotice&&bNoticeShown)return;
	ShownNotice=Text;bNoticeShown=true;
	const FNote* Latest=nullptr;for(const auto& P:Notes)if(!Latest||P.Value.Order>Latest->Order)Latest=&P.Value;
	if(UDreamText* T=TextOf(NoticeText))
	{
		T->SetText(FText::FromString(Text));
		if(Latest)T->SetColor(Latest->Color.WithAlpha(255));
		const float Width=FMath::Max(120.f,Notice->GetWidth()-28.f);
		const float Height=T->GetPreferredSizeWithin(FDreamMeasureSpec::Exactly(Width),FDreamMeasureSpec::Undefined()).Y;
		Notice->SetHeight(FMath::Max(44.f,Height+12.f));
	}
	Notice->SetShown(true);
}

namespace OKReaderThumbs
{
	// The card's own picture: a card file is a PNG (an OK card an APNG) whose default image is the card face. Only the
	// image chunks are read -- an OK card carries its resources in chunks of tens of megabytes after them -- and the
	// picture is scaled to the tile on this worker, so the game thread only makes a small texture.
	struct FThumb {int32 Width=0,Height=0;TArray<uint8> Bgra;};
	// Wrappers is looked up on the game thread before the task starts (module loading is not for workers); Cancelled is
	// the list's own flag, raised when the list is rebuilt, so a stale decode stops before the expensive part.
	FThumb Decode(IImageWrapperModule* Wrappers,const FString& Path,int32 MaxWidth,int32 MaxHeight,const TSharedRef<FThreadSafeBool>& Cancelled)
	{
		FThumb Out;
		if(!Wrappers||*Cancelled)return Out;
		TUniquePtr<IFileHandle> File(FPlatformFileManager::Get().GetPlatformFile().OpenRead(*Path));
		if(!File)return Out;
		static const uint8 Signature[8]={137,80,78,71,13,10,26,10};
		TArray<uint8> Png;Png.Append(Signature,8);
		uint8 Head[8];
		if(!File->Read(Head,8)||FMemory::Memcmp(Head,Signature,8)!=0)return Out;
		bool bSawData=false;
		while(File->Read(Head,8))
		{
			const uint32 Length=(uint32(Head[0])<<24)|(uint32(Head[1])<<16)|(uint32(Head[2])<<8)|uint32(Head[3]);
			const FAnsiString Type=FAnsiString::ConstructFromPtrSize(reinterpret_cast<const ANSICHAR*>(Head+4),4);
			const bool bKeep=Type==ANSITEXTVIEW("IHDR")||Type==ANSITEXTVIEW("PLTE")||Type==ANSITEXTVIEW("tRNS")||Type==ANSITEXTVIEW("IDAT");
			if(Type==ANSITEXTVIEW("IEND")||(bSawData&&Type!=ANSITEXTVIEW("IDAT")))break;	// the default image's data is one run
			if(bKeep)
			{
				if(Length>64u*1024*1024)return Out;
				const int32 At=Png.Num();Png.AddUninitialized(8+Length+4);FMemory::Memcpy(Png.GetData()+At,Head,8);
				if(!File->Read(Png.GetData()+At+8,Length+4))return Out;
				bSawData|=Type==ANSITEXTVIEW("IDAT");
			}
			else if(!File->Seek(File->Tell()+int64(Length)+4))return Out;
		}
		if(!bSawData||*Cancelled)return Out;
		// The size from IHDR (the first chunk kept) before any pixel is decoded: a card face is a few hundred pixels, so a
		// picture larger than 2048x2048 is not a card face and is not decoded at all.
		if(Png.Num()<8+8+13||FMemory::Memcmp(Png.GetData()+12,"IHDR",4)!=0)return Out;
		auto Be32=[&](int32 At){const uint8* P=Png.GetData()+At;return int64((uint32(P[0])<<24)|(uint32(P[1])<<16)|(uint32(P[2])<<8)|uint32(P[3]));};
		const int64 HeadWidth=Be32(16),HeadHeight=Be32(20);
		if(HeadWidth<=0||HeadHeight<=0||HeadWidth>2048||HeadHeight>2048)return Out;
		static const uint8 End[12]={0,0,0,0,'I','E','N','D',0xAE,0x42,0x60,0x82};Png.Append(End,12);
		TSharedPtr<IImageWrapper> Wrapper=Wrappers->CreateImageWrapper(EImageFormat::PNG);
		TArray<uint8> Raw;
		if(!Wrapper||!Wrapper->SetCompressed(Png.GetData(),Png.Num())||!Wrapper->GetRaw(ERGBFormat::BGRA,8,Raw))return Out;
		const int32 W=Wrapper->GetWidth(),H=Wrapper->GetHeight();
		if(W<=0||H<=0||W!=HeadWidth||H!=HeadHeight||Raw.Num()<int64(W)*H*4||*Cancelled)return Out;
		// Always the tile's picture size (the pool's textures are all that size): a card face has the tile's shape, any
		// other picture is stretched to it.
		Out.Width=MaxWidth;Out.Height=MaxHeight;
		Out.Bgra.SetNumUninitialized(Out.Width*Out.Height*4);
		// A box filter over the source pixels each output pixel covers (nearest when the source is smaller).
		for(int32 Y=0;Y<Out.Height;++Y)for(int32 X=0;X<Out.Width;++X)
		{
			const int32 X0=X*W/Out.Width,X1=FMath::Max(X0+1,(X+1)*W/Out.Width),Y0=Y*H/Out.Height,Y1=FMath::Max(Y0+1,(Y+1)*H/Out.Height);
			uint32 Sum[4]={0,0,0,0};
			for(int32 SY=Y0;SY<Y1;++SY)for(int32 SX=X0;SX<X1;++SX){const uint8* P=Raw.GetData()+(SY*W+SX)*4;for(int32 C=0;C<4;++C)Sum[C]+=P[C];}
			const uint32 Count=uint32((X1-X0)*(Y1-Y0));uint8* O=Out.Bgra.GetData()+(Y*Out.Width+X)*4;
			for(int32 C=0;C<4;++C)O[C]=uint8(Sum[C]/Count);
		}
		return Out;
	}
	constexpr int32 TileWidth=288,TileHeight=402;
	// A new pool texture holding Thumb.
	UTexture2D* MakeTexture(const FThumb& Thumb)
	{
		if(Thumb.Width!=TileWidth||Thumb.Height!=TileHeight||Thumb.Bgra.Num()!=Thumb.Width*Thumb.Height*4)return nullptr;
		UTexture2D* Texture=UTexture2D::CreateTransient(Thumb.Width,Thumb.Height,PF_B8G8R8A8);
		if(!Texture)return nullptr;
		Texture->SRGB=true;
		void* Data=Texture->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE);
		FMemory::Memcpy(Data,Thumb.Bgra.GetData(),Thumb.Bgra.Num());
		Texture->GetPlatformData()->Mips[0].BulkData.Unlock();
		Texture->UpdateResource();
		return Texture;
	}
	// A pool texture given a new picture: the pixels go to the render thread with their own copy.
	bool Refill(UTexture2D* Texture,const FThumb& Thumb)
	{
		if(!IsValid(Texture)||!Texture->GetResource()||Thumb.Width!=Texture->GetSizeX()||Thumb.Height!=Texture->GetSizeY()||Thumb.Bgra.Num()!=Thumb.Width*Thumb.Height*4)return false;
		uint8* Copy=static_cast<uint8*>(FMemory::Malloc(Thumb.Bgra.Num()));FMemory::Memcpy(Copy,Thumb.Bgra.GetData(),Thumb.Bgra.Num());
		FUpdateTextureRegion2D* Region=new FUpdateTextureRegion2D(0,0,0,0,Thumb.Width,Thumb.Height);
		Texture->UpdateTextureRegions(0,1,Region,Thumb.Width*4,4,Copy,[](uint8* Data,const FUpdateTextureRegion2D* Regions){FMemory::Free(Data);delete Regions;});
		return true;
	}
	void Show(UOKDreamControl* Tile,UTexture2D* Texture)
	{
		if(!IsValid(Tile)||!Tile->Picture)return;
		if(!OKReaderPicturesShown())Texture=nullptr;
		if(auto* Image=Cast<UDreamImage>(Tile->Picture->GetVisual())){FDreamUIImageBrush Brush=Image->GetBrush();Brush.SetResourceObject(Texture);Image->SetBrush(Brush);}
		Tile->Picture->SetShown(Texture!=nullptr);
	}
}

// The card list's pictures: decoded on workers for the tiles in or near the scrolled view (a few at a time), dropped
// again for tiles far out of it, so a folder of hundreds of cards never holds all their pictures.
// The pictures live in a pool owned by the screen (ThumbPool, a UPROPERTY) for as long as the screen lives: a tile that
// lets go of its picture gives the texture back to the pool, the next tile gets it refilled. No picture texture is
// ever collected while the reader runs, so no DreamGUI draw data built before a brush change can outlive its texture
// (2026-11-19: switching the card source and scrolling fast ended in a GPU page fault after about a minute).
static TAutoConsoleVariable<int32> CVarReaderThumbs(TEXT("ok.ReaderThumbs"),1,TEXT("Card list pictures in the reader's DreamGUI screen: 1 decode them (default), 0 none (for comparison runs)."));

void UOKReaderScreen::ListResources(FOutputDevice& Out) const
{
	auto MiB=[](int64 Bytes){return double(Bytes)/(1024.0*1024.0);};
	auto Size=[](const UTexture* T)->int64{return T&&T->GetResource()?int64(T->CalcTextureMemorySizeEnum(TMC_ResidentMips)):0;};
	FString Line=FString::Printf(TEXT("screen thumbPool=%d free=%d cardThumbs=%d controls=%d pageWidgets=%d cards=%d"),ThumbPool.Num(),FreeThumbs.Num(),CardThumbs.Num(),Controls.Num(),PageWidgets.Num(),CardButtons.Num());
	if(const UOKCharacterController* G=Controller.Get())
	{
		int64 Bytes=0;for(const auto& Pair:G->AppearanceThumbCache)Bytes+=Size(Pair.Value);
		Line+=FString::Printf(TEXT(" | controller appearanceCache=%d (%.1f MiB) appearanceTextures=%d"),G->AppearanceThumbCache.Num(),MiB(Bytes),G->AppearanceTextures.Num());
	}
	int32 Widgets=0,Mirrors=0;
	for(TObjectIterator<UDreamWidget> It;It;++It)if(IsValid(*It)){++Widgets;if(It->IsA<UOKDreamControl>())++Mirrors;}
	Line+=FString::Printf(TEXT(" | live dreamWidgets=%d mirrorControls=%d"),Widgets,Mirrors);
	// Textures by class, the transient ones (made at run time) apart.
	TMap<FString,TPair<int32,int64>> ByKind;
	for(TObjectIterator<UTexture> It;It;++It)
	{
		const UTexture* T=*It;if(!IsValid(T)||T->HasAnyFlags(RF_ClassDefaultObject))continue;
		const bool bTransient=T->GetOutermost()==GetTransientPackage();
		TPair<int32,int64>& Slot=ByKind.FindOrAdd(T->GetClass()->GetName()+(bTransient?TEXT("(transient)"):TEXT("")));
		++Slot.Key;Slot.Value+=Size(T);
	}
	ByKind.ValueSort([](const TPair<int32,int64>& A,const TPair<int32,int64>& B){return A.Value>B.Value;});
	Line+=TEXT(" | textures");
	for(const auto& Pair:ByKind)Line+=FString::Printf(TEXT(" %s=%d/%.1fMiB"),*Pair.Key,Pair.Value.Key,MiB(Pair.Value.Value));
	FTextureMemoryStats Stats;RHIGetTextureMemoryStats(Stats);
	Line+=FString::Printf(TEXT(" | rhi streaming=%.1fMiB nonStreaming=%.1fMiB dedicated=%.0fMiB"),MiB(Stats.StreamingMemorySize),MiB(Stats.NonStreamingMemorySize),MiB(Stats.DedicatedVideoMemory));
	Out.Log(Line);
	UE_LOG(LogTemp,Display,TEXT("OK reader resources %s"),*Line);
}

void UOKReaderScreen::GiveBackThumb(UTexture2D* Texture)
{
	if(Texture&&ThumbPool.Contains(Texture)&&!FreeThumbs.Contains(Texture))FreeThumbs.Add(Texture);
}

UTexture2D* UOKReaderScreen::PutThumb(int32 Width,int32 Height,const TArray<uint8>& Bgra)
{
	OKReaderThumbs::FThumb Thumb;Thumb.Width=Width;Thumb.Height=Height;Thumb.Bgra=Bgra;
	while(FreeThumbs.Num())
	{
		UTexture2D* Texture=FreeThumbs.Pop();
		if(OKReaderThumbs::Refill(Texture,Thumb))return Texture;
	}
	UTexture2D* Texture=OKReaderThumbs::MakeTexture(Thumb);
	if(Texture)ThumbPool.Add(Texture);
	return Texture;
}

void UOKReaderScreen::TickThumbnails()
{
	if(CardButtons.IsEmpty()||!LeftScroll)return;
	if(CVarReaderThumbs.GetValueOnGameThread()==0)return;
	const float Scale=FMath::Max(.01f,float(LeftScroll->GetWorldScale().Z>0?LeftScroll->GetWorldScale().Z:LeftScroll->GetWorldScale().Y));
	const FVector Center=LeftScroll->GetWorldLocation();
	const float View=LeftScroll->GetHeight();
	// Distances along the panel, in its units: the box's location is a point of its own rect (its pivot), so "near"
	// reaches a view's height past both edges whichever point that is.
	const float Near=(View*2.f+260.f)*Scale,Far=(View*4.f+260.f)*Scale;
	TArray<int32> Wanted;
	for(int32 I=0;I<CardButtons.Num();++I)
	{
		UOKDreamControl* Tile=CardButtons[I];if(!IsValid(Tile))continue;
		const float Distance=FVector::Dist(Tile->GetWorldLocation(),Center);
		if(Distance>Far&&CardThumbs.IsValidIndex(I)&&CardThumbs[I]){OKReaderThumbs::Show(Tile,nullptr);GiveBackThumb(CardThumbs[I]);CardThumbs[I]=nullptr;}
		else if(Distance<=Near&&CardThumbs.IsValidIndex(I)&&!CardThumbs[I]&&!CardThumbLoading[I])Wanted.Add(I);
	}
	Wanted.Sort([&](int32 A,int32 B){return FVector::DistSquared(CardButtons[A]->GetWorldLocation(),Center)<FVector::DistSquared(CardButtons[B]->GetWorldLocation(),Center);});
	for(int32 I:Wanted)
	{
		if(ThumbsInFlight>=3)break;
		if(!CardPaths.IsValidIndex(I)||!CardThumbLoading.IsValidIndex(I))continue;
		// Everything the worker touches is its own: a copy of the path, the module pointer (modules stay loaded until
		// exit) and a shared cancel flag. The screen is reached only from the game thread, through a weak pointer, and
		// only for the same list (generation) -- a rebuilt list raised the flag and bumped the generation.
		IImageWrapperModule* Wrappers=FModuleManager::LoadModulePtr<IImageWrapperModule>(TEXT("ImageWrapper"));
		if(!Wrappers)return;
		CardThumbLoading[I]=true;++ThumbsInFlight;
		const FString Path=CardPaths[I];const int32 Generation=ThumbGeneration;
		TSharedRef<FThreadSafeBool> Cancelled=ThumbCancel;
		TWeakObjectPtr<UOKReaderScreen> Weak(this);
		UE::Tasks::Launch(TEXT("OKReaderThumb"),[Weak,Wrappers,Path,I,Generation,Cancelled]()
		{
			OKReaderThumbs::FThumb Thumb=OKReaderThumbs::Decode(Wrappers,Path,OKReaderThumbs::TileWidth,OKReaderThumbs::TileHeight,Cancelled);
			if(*Cancelled)return;
			AsyncTask(ENamedThreads::GameThread,[Weak,I,Generation,Cancelled,Thumb=MoveTemp(Thumb)]()
			{
				UOKReaderScreen* Self=Weak.Get();
				if(*Cancelled||!IsValid(Self)||Self->ThumbGeneration!=Generation)return;
				Self->ThumbsInFlight=FMath::Max(0,Self->ThumbsInFlight-1);
				if(!Self->CardThumbs.IsValidIndex(I)||!Self->CardThumbLoading.IsValidIndex(I)||!Self->CardButtons.IsValidIndex(I))return;
				UTexture2D* Texture=Self->PutThumb(Thumb.Width,Thumb.Height,Thumb.Bgra);
				if(!Texture)return;	// unreadable: stays marked loading, so it is not asked for again
				Self->CardThumbLoading[I]=false;
				Self->CardThumbs[I]=Texture;OKReaderThumbs::Show(Self->CardButtons[I],Texture);
			});
		});
	}
}

// A folder through the system's own folder picker (Windows: IFileOpenDialog with FOS_PICKFOLDERS). Empty when cancelled.
FString UOKReaderScreen::PickFolder(const FString& Title,const FString& Start)
{
	FString Result;
#if PLATFORM_WINDOWS
	const HRESULT Init=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED|COINIT_DISABLE_OLE1DDE);
	IFileOpenDialog* Dialog=nullptr;
	if(SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&Dialog))))
	{
		DWORD Options=0;Dialog->GetOptions(&Options);Dialog->SetOptions(Options|FOS_PICKFOLDERS|FOS_FORCEFILESYSTEM|FOS_PATHMUSTEXIST);
		Dialog->SetTitle(*Title);
		if(!Start.IsEmpty()&&FPaths::DirectoryExists(Start))
		{
			IShellItem* Folder=nullptr;const FString Native=FPaths::ConvertRelativePathToFull(Start).Replace(TEXT("/"),TEXT("\\"));
			if(SUCCEEDED(SHCreateItemFromParsingName(*Native,nullptr,IID_PPV_ARGS(&Folder)))){Dialog->SetFolder(Folder);Folder->Release();}
		}
		const HWND Owner=GEngine&&GEngine->GameViewport&&GEngine->GameViewport->GetWindow().IsValid()&&GEngine->GameViewport->GetWindow()->GetNativeWindow().IsValid()
			?static_cast<HWND>(GEngine->GameViewport->GetWindow()->GetNativeWindow()->GetOSWindowHandle()):nullptr;
		if(SUCCEEDED(Dialog->Show(Owner)))
		{
			IShellItem* Item=nullptr;
			if(SUCCEEDED(Dialog->GetResult(&Item)))
			{
				PWSTR Chosen=nullptr;
				if(SUCCEEDED(Item->GetDisplayName(SIGDN_FILESYSPATH,&Chosen))){Result=FString(Chosen).Replace(TEXT("\\"),TEXT("/"));CoTaskMemFree(Chosen);}
				Item->Release();
			}
		}
		Dialog->Release();
	}
	if(SUCCEEDED(Init))CoUninitialize();
#endif
	return Result;
}

// 設定 › 遊戲目錄: where the original game is (its mods/ is where zipmods are looked for) and the local library, each a
// field, a folder button and what is found there, said as soon as it is typed. Kept as the user's own setting
// (UKKGameRoot::SetUserRoot: GameUserSettings.ini, writable in a package), read again at each card open.
void UOKReaderScreen::BuildEyeOverlayPage(UDreamWidget* Page)
{
	UOKCharacterController* G=Controller.Get();if(!G||!Page)return;
	auto Text=[this](UDreamWidget* Into,const FString& Value)
	{
		UOKDreamControl* C=MakeControl(TEXT("Label"),Into);
		if(C){C->FixedText=Value;C->SetText(Value);if(UDreamPanelSlot* Slot=C->GetPanelSlot())Slot->SetMaxDesiredSize(FVector2D::ZeroVector);}
		return C;
	};
	if(!G->bModelLayout){Text(Page,TEXT("要先在「人物卡總欄」選一張卡並按「載入3D」，這一頁才讀得到它的瞳孔覆蓋貼圖。"));return;}
	if(G->bLoadInFlight){Text(Page,TEXT("等角色載入完成後讀取瞳孔覆蓋貼圖…"));return;}
	const FString Card=G->Entries.IsValidIndex(G->SelectedIndex)?G->Entries[G->SelectedIndex].Path:FString();
	// Read once per card (and again after a pick); a failed read waits for 重新讀取 instead of retrying on every rebuild.
	if(!G->bEyeOverlayBusy&&G->EyeOverlayStatus.IsEmpty()&&(!G->EyeOverlayData.IsValid()||G->EyeOverlayCard!=Card))
	{
		G->EyeOverlayData.Reset();
		AsyncTask(ENamedThreads::GameThread,[Weak=TWeakObjectPtr<UOKCharacterController>(G)](){if(Weak.IsValid())Weak->RequestEyeOverlays();});
		Text(Page,TEXT("正在讀取這張卡的瞳孔覆蓋貼圖…"));
		return;
	}
	if(!G->EyeOverlayStatus.IsEmpty())Text(Page,G->EyeOverlayStatus);
	{
		UDreamWidget* Row=MakePanel(Page,true,6.f);
		TWeakObjectPtr<UOKCharacterController> Weak(G);
		MakeOwnButton(Row,TEXT("重新讀取"),[Weak](){if(Weak.IsValid()&&!Weak->bEyeOverlayBusy){Weak->EyeOverlayStatus.Reset();Weak->EyeOverlayData.Reset();Weak->RequestEyeOverlays();}});
	}
	const TSharedPtr<FJsonObject> Data=G->EyeOverlayData;
	if(!Data.IsValid()||G->bEyeOverlayBusy)return;
	const TArray<TSharedPtr<FJsonValue>>* Slots=nullptr;const TArray<TSharedPtr<FJsonValue>>* Candidates=nullptr;
	Data->TryGetArrayField(TEXT("slots"),Slots);Data->TryGetArrayField(TEXT("candidates"),Candidates);
	if(!Slots||Slots->IsEmpty()){Text(Page,TEXT("這張卡的眼睛材質沒有可設定覆蓋貼圖的槽位。"));return;}
	int32 Unused=0,Other=0;
	if(Candidates)for(const TSharedPtr<FJsonValue>& V:*Candidates){bool bEye=false;if(V->AsObject())V->AsObject()->TryGetBoolField(TEXT("eye"),bEye);if(!bEye)++Other;}
	for(const TSharedPtr<FJsonValue>& SlotValue:*Slots)
	{
		const TSharedPtr<FJsonObject> Slot=SlotValue->AsObject();if(!Slot)continue;
		bool bApplies=true;Slot->TryGetBoolField(TEXT("applies"),bApplies);
		if(!bApplies){++Unused;continue;}
		FString Label,Material,Property,Current;Slot->TryGetStringField(TEXT("label"),Label);Slot->TryGetStringField(TEXT("material"),Material);Slot->TryGetStringField(TEXT("property"),Property);Slot->TryGetStringField(TEXT("candidate"),Current);
		bool bPresent=false;Slot->TryGetBoolField(TEXT("present"),bPresent);
		Text(Page,FString::Printf(TEXT("%s（%s › %s）"),*Label,*Material,*Property));
		UDreamWidget* Grid=UDreamUIBPLibrary::ConstructWidget(this,TEXT("Grid"),nullptr);
		if(!Grid)continue;
		if(auto* Wrap=Grid->CreateNewLayoutContainer<UDreamLayoutContainerWrapBox>())Wrap->SetSpacing(FVector2D(6,6));
		Grid->SetSizeDelta(FVector2D::ZeroVector);AddToHost(Page,Grid,false);
		if(UOKDreamControl* Anchor=Text(Grid,FString::Printf(TEXT("%s（%s › %s）"),*Label,*Material,*Property)))Anchor->SetShown(false);	// names the row for ControlPath
		TWeakObjectPtr<UOKCharacterController> Weak(G);
		auto Tile=[this,Grid](const FString& Caption,UTexture2D* Picture,TFunction<void()> Press)
		{
			UOKDreamControl* B=MakeControl(TEXT("PickTile"),Grid);if(!B)return;
			B->FixedText=Caption;B->SetText(Caption);B->OnPressed=MoveTemp(Press);
			if(UDreamPanelSlot* S=B->GetPanelSlot()){S->SetMinDesiredSize(FVector2D(112,150));S->SetMaxDesiredSize(FVector2D(112,150));}
			OKReaderThumbs::Show(B,Picture);
		};
		Tile(bPresent?TEXT("無"):TEXT("▸ 無"),nullptr,[Weak,Material,Property](){if(Weak.IsValid())Weak->SetEyeOverlay(Material,Property,FString());});
		if(Candidates)for(const TSharedPtr<FJsonValue>& V:*Candidates)
		{
			const TSharedPtr<FJsonObject> C=V->AsObject();if(!C)continue;
			bool bEye=false;C->TryGetBoolField(TEXT("eye"),bEye);if(!bEye)continue;
			FString Id,Name,Png;C->TryGetStringField(TEXT("id"),Id);C->TryGetStringField(TEXT("name"),Name);C->TryGetStringField(TEXT("png"),Png);
			const FString Caption=(Id==Current&&bPresent?TEXT("▸ "):TEXT(""))+(Name.IsEmpty()?Id:Name);
			Tile(Caption,G->EyeOverlayThumb(Png),[Weak,Material,Property,Id](){if(Weak.IsValid())Weak->SetEyeOverlay(Material,Property,Id);});
		}
	}
	if(Unused)Text(Page,FString::Printf(TEXT("另有 %d 個槽位這條開卡路徑不畫（瞳孔材質上的高光貼圖走「眼睛」頁的高光種類），不列出。"),Unused));
	if(Other)Text(Page,FString::Printf(TEXT("這張卡另有 %d 張用在衣服或配件上的貼圖，不列在這裡。"),Other));
}

void UOKReaderScreen::BuildGameRootPage(UDreamWidget* Page)
{
	auto Text=[this](UDreamWidget* Into,const FString& Value)
	{
		UOKDreamControl* C=MakeControl(TEXT("Label"),Into);
		if(C){C->FixedText=Value;C->SetText(Value);if(UDreamPanelSlot* Slot=C->GetPanelSlot())Slot->SetMaxDesiredSize(FVector2D::ZeroVector);}
		return C;
	};
	auto Field=[this,Text](UDreamWidget* Into,const FString& Caption,const FString& Value,const FString& Hint,
		TFunction<void(const FString&)> Changed,TFunction<void(const FString&)> Save,TFunction<FString()> Pick,TFunction<FString()> Reset)
	{
		Text(Into,Caption);
		// The path on a line of its own (a folder path is long), the buttons under it.
		UOKDreamControl* Input=MakeControl(TEXT("Input"),Into);
		UDreamWidget* Row=MakePanel(Into,true,6.f);
		if(Input)
		{
			if(Input->Input)
			{
				Input->Input->SetText(Value);Input->Input->SetPlaceholder(FText::FromString(Hint));
				Input->Input->GetOnTextChangedEvent().AddWeakLambda(this,[Changed](const FString& Typed){Changed(Typed.TrimStartAndEnd());});
				Input->Input->GetOnTextCommittedEvent().AddWeakLambda(this,[Save](const FString& Typed){Save(Typed.TrimStartAndEnd());});
			}
		}
		TWeakObjectPtr<UOKDreamControl> WeakInput(Input);
		MakeOwnButton(Row,TEXT("選資料夾…"),[WeakInput,Pick,Save,Changed]()
		{
			// Logged: the system dialog is out of the game MCP's reach, so its outcome is read here.
			const FString Chosen=Pick();UE_LOG(LogTemp,Display,TEXT("ok.ReaderScreen: folder dialog %s%s"),Chosen.IsEmpty()?TEXT("cancelled"):TEXT("picked "),*Chosen);if(Chosen.IsEmpty())return;
			if(WeakInput.IsValid()&&WeakInput->Input)WeakInput->Input->SetText(Chosen);
			Save(Chosen);Changed(Chosen);
		});
		MakeOwnButton(Row,TEXT("還原預設"),[WeakInput,Reset,Changed]()
		{
			const FString Default=Reset();
			if(WeakInput.IsValid()&&WeakInput->Input)WeakInput->Input->SetText(Default);
			Changed(Default);
		});
		return Input;
	};
	UKKGameRoot* Game=UKKGameRoot::Get();
	const FString Root=Game?Game->Root:FString();
	RootInput=Field(Page,TEXT("遊戲目錄（原作 Koikatsu Sunshine 的資料夾：開卡時從它的 mods/ 找 zipmod）"),Root,TEXT("例如 D:/KoikatuSunshine"),
		[this](const FString& Typed){CheckGameRoot(Typed);},
		[](const FString& Typed){UKKGameRoot::SetUserRoot(Typed);},
		[this](){return PickFolder(TEXT("選擇遊戲目錄"),UKKGameRoot::Get()->Root);},
		[](){UKKGameRoot::ClearUserRoot();return UKKGameRoot::Get()->Root;});
	RootStatus=Text(Page,FString());
	const FString Library=Game?Game->LocalLibrary:FString();
	LibraryInput=Field(Page,TEXT("本機模型庫（LocalLibrary：在這台電腦轉出的第三方 mod 模型；空白就用基礎庫旁的 local_v1）"),Library,TEXT("空白：基礎庫旁的 local_v1"),
		[this](const FString& Typed){CheckLocalLibrary(Typed);},
		[](const FString& Typed){UKKGameRoot::SetUserLocalLibrary(Typed);},
		[this](){return PickFolder(TEXT("選擇本機模型庫"),UKKGameRoot::ResolvedLocalLibrary());},
		[](){UKKGameRoot::ClearUserLocalLibrary();return UKKGameRoot::Get()->LocalLibrary;});
	LibraryStatus=Text(Page,FString());
	Text(Page,TEXT("按 Enter 或選資料夾就存下（下次開程式還在），下一次開卡就用新的路徑，不必重開程式。卡片清單若列的是遊戲的卡片資料夾，到「人物卡總欄」按「使用遊戲卡片目錄」重新列出。"));
	CheckGameRoot(Root);CheckLocalLibrary(Library);
}

// What is in the folder typed so far: counted on a worker (a mods/ folder holds thousands of zipmods), the newest answer
// shown.
void UOKReaderScreen::CheckGameRoot(const FString& Root)
{
	const int32 Generation=++RootCheckGeneration;
	auto Say=[this](const FString& Value){if(UOKDreamControl* C=RootStatus.Get()){C->FixedText=Value;C->SetText(Value);}};
	if(Root.IsEmpty()){Say(UKKGameRoot::NoGame()?TEXT("未設定：這個包沒有原作遊戲，只用卡片旁邊的 zipmod 與基礎庫。"):TEXT("未設定：只用卡片旁邊的 zipmod 與基礎庫。"));return;}
	Say(TEXT("檢查中…"));
	TWeakObjectPtr<UOKReaderScreen> Weak(this);
	UE::Tasks::Launch(TEXT("OKReaderGameRoot"),[Weak,Root,Generation]()
	{
		FString Message;
		const FString Mods=Root/TEXT("mods");
		if(!FPaths::DirectoryExists(Root))Message=TEXT("✗ 找不到這個資料夾。");
		else if(!FPaths::DirectoryExists(Mods))Message=TEXT("✗ 這個路徑底下沒有 mods/ 資料夾，找不到 zipmod。");
		else
		{
			TArray<FString> Found;IFileManager::Get().FindFilesRecursive(Found,*Mods,TEXT("*.zipmod"),true,false);
			Message=FString::Printf(TEXT("✓ 找到 mods/，%d 個 zipmod。"),Found.Num());
			if(!FPaths::DirectoryExists(Root/TEXT("abdata")))Message+=TEXT("（沒有 abdata/：不像原作遊戲的資料夾）");
		}
		AsyncTask(ENamedThreads::GameThread,[Weak,Generation,Message]()
		{
			UOKReaderScreen* Self=Weak.Get();if(!Self||Self->RootCheckGeneration!=Generation)return;
			if(UOKDreamControl* C=Self->RootStatus.Get()){C->FixedText=Message;C->SetText(Message);}
		});
	});
}

FString UOKReaderScreen::ThumbState() const
{
	if(CardThumbs.IsEmpty())return TEXT("-");
	int32 Held=0;for(const TObjectPtr<UTexture2D>& T:CardThumbs)if(T)++Held;
	return FString::Printf(TEXT("%d/%d"),Held,CardThumbs.Num());
}

void UOKReaderScreen::ApplyFolderSetting(bool bLibrary,const FString& Folder,bool bForget)
{
	if(bLibrary){if(bForget)UKKGameRoot::ClearUserLocalLibrary();else UKKGameRoot::SetUserLocalLibrary(Folder);}
	else{if(bForget)UKKGameRoot::ClearUserRoot();else UKKGameRoot::SetUserRoot(Folder);}
	UKKGameRoot* Game=UKKGameRoot::Get();
	const FString Now=bLibrary?Game->LocalLibrary:Game->Root;
	if(UOKDreamControl* Field=(bLibrary?LibraryInput:RootInput).Get())if(Field->Input)Field->Input->SetText(Now);
	if(bLibrary){if(LibraryStatus.IsValid())CheckLocalLibrary(Now);}
	else if(RootStatus.IsValid())CheckGameRoot(Now);
}

void UOKReaderScreen::CheckLocalLibrary(const FString& Library)
{
	FString Message;
	if(Library.IsEmpty())Message=TEXT("未設定：用基礎庫旁的 local_v1（有的話）。");
	else
	{
		const FString Full=FPaths::IsRelative(Library)?FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/Library):Library;
		Message=FPaths::DirectoryExists(Full)?FString::Printf(TEXT("✓ 找到資料夾 %s"),*Full):TEXT("✗ 找不到這個資料夾。");
	}
	if(UOKDreamControl* C=LibraryStatus.Get()){C->FixedText=Message;C->SetText(Message);}
}

// The current tab takes the .dui's TabOn look (Tab0's), the rest TabOff (Tab1's); before this only Tab0 ever had the
// raised face, so 編輯 looked chosen on every tab. Both looks come from the same .dui for every reader screen: taken
// once, before any tab changed. Also used when a page of another tab is opened directly (前往 設定 › 遊戲目錄).
static TOptional<FDreamButtonStyle> GTabOnStyle,GTabOffStyle;
static void PaintTabs(UDreamButton* const (&Tabs)[4],int32 Current)
{
	if(!GTabOnStyle.IsSet()&&Tabs[0]&&Tabs[1]){GTabOnStyle=Tabs[0]->GetStyle();GTabOffStyle=Tabs[1]->GetStyle();}
	for(int32 I=0;I<4;++I)if(Tabs[I])
	{
		if(GTabOnStyle.IsSet())Tabs[I]->SetStyle(I==Current?GTabOnStyle.GetValue():GTabOffStyle.GetValue());
		Tabs[I]->SetRenderOpacity(I==Current?1.f:.62f);
	}
}

void UOKReaderScreen::ShowTab(int32 Index)
{
	Tab=FMath::Clamp(Index,0,3);
	UDreamButton* Tabs[]={Tab0,Tab1,Tab2,Tab3};
	TOptional<FDreamButtonStyle>& TabOnStyle=GTabOnStyle;TOptional<FDreamButtonStyle>& TabOffStyle=GTabOffStyle;
	if(!TabOnStyle.IsSet()&&Tab0&&Tab1){TabOnStyle=Tab0->GetStyle();TabOffStyle=Tab1->GetStyle();}
	for(int32 I=0;I<4;++I)if(Tabs[I])
	{
		if(TabOnStyle.IsSet())Tabs[I]->SetStyle(I==Tab?TabOnStyle.GetValue():TabOffStyle.GetValue());
		Tabs[I]->SetRenderOpacity(I==Tab?1.f:.62f);
	}
	// The rail lists every category on every tab (the sketch keeps it on the left throughout); 設定 sits alone at its foot.
	for(UOKDreamControl* B:RailButtons)if(IsValid(B))B->DestroyWidget();
	for(UDreamWidget* Gap:RailSpacers)if(IsValid(Gap))Gap->DestroyWidget();
	RailSpacers.Reset();
	RailButtons.Reset();
	int32 First=INDEX_NONE;
	for(int32 I=0;I<Categories.Num();++I)
	{
		if(First==INDEX_NONE&&Categories[I].Tab==Tab)First=I;
		if(RailHost&&Categories[I].Name==TEXT("設定／介面"))if(UDreamWidget* Gap=MakePanel(RailHost,false,0.f)){RailSpacers.Add(Gap);if(auto* Slot=Gap->GetPanelSlot())Slot->SetSizeRule(EDreamPanelSizeRule::Fill);}
		UOKDreamControl* B=MakeOwnButton(RailHost,Categories[I].Name,[this,I](){ShowCategory(I);});
		if(B){B->SetWidth(104);if(auto* Slot=B->GetPanelSlot())Slot->SetHorizontalAlignment(EDreamPanelHorizontalAlignment::Fill);RailButtons.Add(B);}
	}
	if(First!=INDEX_NONE)ShowCategory(First);
}

void UOKReaderScreen::ShowCategory(int32 Index,int32 SubIndex)
{
	if(!Categories.IsValidIndex(Index))return;
	ClearPage();
	Category=Index;const FCategory& C=Categories[Index];
	if(C.Tab!=Tab){Tab=C.Tab;UDreamButton* Tabs[4]={Tab0,Tab1,Tab2,Tab3};PaintTabs(Tabs,Tab);}
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
		for(const TWeakObjectPtr<UWidget>& Source:C.Groups[Sub].Sources)if(Source.IsValid()&&Page&&(!C.Groups[Sub].bShownOnly||IsUmgShown(Source.Get())))Mirror(Source.Get(),Page,false);
		ShownSignature=C.Groups[Sub].Signature?C.Groups[Sub].Signature():FString();
		if(C.Groups[Sub].Build&&Page)C.Groups[Sub].Build(Page);
		// The card list: a grid of the cards' pictures with their names under them, as a file browser shows pictures (the
		// pictures load as their tiles scroll into view, TickThumbnails).
		if(Tab==1&&Page)if(UOKCharacterController* G=Controller.Get())
		{
			UDreamWidget* List=UDreamUIBPLibrary::ConstructWidget(this,TEXT("CardGrid"),nullptr);
			if(List)
			{
				if(auto* Wrap=List->CreateNewLayoutContainer<UDreamLayoutContainerWrapBox>())Wrap->SetSpacing(FVector2D(8,8));
				List->SetSizeDelta(FVector2D::ZeroVector);AddToHost(Page,List,false);
			}
			ShownEntries=G->Entries.Num();
			for(int32 I=0;I<G->Entries.Num()&&I<400&&List;++I)
			{
				const auto& E=G->Entries[I];
				const FString Name=FString::Printf(TEXT("%s %s"),*E.LastName,*E.FirstName).TrimStartAndEnd();
				const FString Text=Name.IsEmpty()?FPaths::GetBaseFilename(E.FileName):Name;
				TWeakObjectPtr<UOKCharacterController> Weak(G);
				UOKDreamControl* B=MakeControl(TEXT("CardTile"),List);
				if(B)
				{
					B->FixedText=Text;B->OnPressed=[Weak,I](){if(Weak.IsValid())Weak->SelectIndex(I);};B->SetText(Text);
					if(UDreamPanelSlot* Slot=B->GetPanelSlot()){Slot->SetHorizontalAlignment(EDreamPanelHorizontalAlignment::Left);Slot->SetMinDesiredSize(FVector2D(156,252));Slot->SetMaxDesiredSize(FVector2D(156,252));}
					if(B->Picture)B->Picture->SetShown(false);
				}
				CardButtons.Add(B);CardTexts.Add(Text);CardPaths.Add(E.Path);CardThumbs.Add(nullptr);CardThumbLoading.Add(false);
			}
			ShownCardSelection=INDEX_NONE;MarkCurrentCard();
		}
		LeftScroll->ScrollToStart();
	}
}

UOKCharacterController* UOKReaderScreen::GetController() const{return Controller.Get();}

// The page's picker and editor, opened with its scope once the controller can: a page entered while the catalog is read
// (or a card loads) would otherwise stay without them. Asked once it shows (or a request for it is on its way).
void UOKReaderScreen::ApplyWantedScopes()
{
	UOKCharacterController* G=Controller.Get();
	if(!G||!G->bModelLayout||G->bAppearanceBusy||G->bPropertyBusy||G->bLoadInFlight)return;
	auto IsOpen=[](UWidget* W){return W&&W->GetVisibility()!=ESlateVisibility::Collapsed;};
	if(WantedTargets.IsSet())
	{
		G->SetAppearanceScope(WantedTargets.GetValue());
		if(IsOpen(G->AppearancePanel)||G->bAppearanceBusy)WantedTargets.Reset();
	}
	if(WantedProperties.IsSet()&&!G->bAppearanceBusy)
	{
		G->SetPropertyScope(WantedProperties.GetValue());
		if(IsOpen(G->PropertyPanel)||G->bPropertyBusy)WantedProperties.Reset();
	}
}

void UOKReaderScreen::ScrollLeftPage(float Progress){if(LeftScroll)LeftScroll->SetScrollProgress(FMath::Clamp(Progress,0.f,1.f));}

namespace OKReaderPaths
{
	// A drawer title without the fold arrow it shows.
	static FString Title(const UOKDreamControl* D)
	{
		FString T=D->FixedText.IsEmpty()?D->GetShownText():D->FixedText;
		T.TrimStartAndEndInline();
		while(T.Len()&&FCString::Strchr(TEXT("▸▾►▼▶▲"),T[T.Len()-1]))T.LeftChopInline(1);
		return T.TrimEnd();
	}
	// The kind of control (WBP_OKSlider_C: "Slider").
	static FString Kind(const UOKDreamControl* C)
	{
		FString K=C->GetClass()->GetName();K.RemoveFromStart(TEXT("WBP_OK"));K.RemoveFromEnd(TEXT("_C"));return K;
	}
	// What a control is called: the text it shows, unless that is empty or a value (a number, which changes), then its kind.
	static FString Name(const UOKDreamControl* C)
	{
		const FString T=C->GetShownText().TrimStartAndEnd();
		if(T.IsEmpty())return Kind(C);
		bool bValue=true;
		for(TCHAR Ch:T)if(!(FChar::IsDigit(Ch)||Ch==TEXT('.')||Ch==TEXT('-')||Ch==TEXT('+')||Ch==TEXT('%')||Ch==TEXT(' ')||Ch==TEXT(','))){bValue=false;break;}
		return bValue?Kind(C):T;
	}
	// The label of the row a control sits in: the first Label among its siblings (not itself), in a horizontal row only
	// (a column's labels title the controls under them, not one row).
	static FString RowLabel(const UOKDreamControl* C)
	{
		const UDreamWidget* P=C->GetParent();if(!P||!(Cast<UDreamLayoutContainerHorizontalBox>(P->GetLayoutContainer())||Cast<UDreamLayoutContainerWrapBox>(P->GetLayoutContainer())))return FString();
		for(const UDreamWidget* W:P->GetChildren())
			if(const UOKDreamControl* L=Cast<UOKDreamControl>(W);L&&L!=C&&Kind(L)==TEXT("Label"))
			{
				const FString N=Name(L);
				if(N!=TEXT("Label"))return N;
			}
		return FString();
	}
}

FString UOKReaderScreen::ControlPath(const UOKDreamControl* C) const
{
	if(!C)return FString();
	const FString Caption=OKReaderPaths::Name(C);
	auto Has=[C](const TArray<TObjectPtr<UOKDreamControl>>& List){for(const UOKDreamControl* X:List)if(X==C)return true;return false;};
	if(Has(CardButtons))return TEXT("卡片›")+Caption;
	if(Has(RailButtons))return TEXT("分類›")+Caption;
	if(Has(SubButtons))return CurrentCategory()+TEXT("›")+Caption;
	if(Has(Drawers))return TEXT("抽屜›")+OKReaderPaths::Title(C);
	FString Leaf=Caption;
	if(OKReaderPaths::Kind(C)!=TEXT("Label")){const FString Row=OKReaderPaths::RowLabel(C);if(!Row.IsEmpty()&&Row!=Caption)Leaf=Row+TEXT("›")+Caption;}
	for(const UDreamWidget* P=C->GetParent();P;P=P->GetParent())
	{
		for(const UOKDreamControl* D:Drawers)if(IsValid(D)&&D->Body==P)return OKReaderPaths::Title(D)+TEXT("›")+Leaf;
		if(P==CameraBarHost)return TEXT("鏡頭›")+Leaf;
		if(P==LeftScroll)
		{
			FString Where=CurrentCategory();
			if(Categories.IsValidIndex(Category)&&Categories[Category].Groups.IsValidIndex(Sub))Where+=TEXT("›")+Categories[Category].Groups[Sub].Name;
			return Where+TEXT("›")+Leaf;
		}
	}
	return Leaf;
}

// Every shown control and its path; a path two controls would share gets " #2", " #3" ... in screen order.
static void OKReaderAllControls(const UOKReaderScreen* S,TArray<UOKDreamControl*>& All,TArray<FString>& Paths,
	const TArray<TObjectPtr<UOKDreamControl>>& Controls,const TArray<TObjectPtr<UOKDreamControl>>& SubButtons,const TArray<TObjectPtr<UOKDreamControl>>& RailButtons,
	const TArray<TObjectPtr<UOKDreamControl>>& Drawers,const TArray<TObjectPtr<UOKDreamControl>>& CardButtons)
{
	for(UOKDreamControl* C:Controls)if(IsValid(C))All.Add(C);
	for(UOKDreamControl* C:SubButtons)if(IsValid(C))All.AddUnique(C);
	for(UOKDreamControl* C:RailButtons)if(IsValid(C))All.AddUnique(C);
	for(UOKDreamControl* C:Drawers)if(IsValid(C))All.AddUnique(C);
	for(UOKDreamControl* C:CardButtons)if(IsValid(C))All.AddUnique(C);	// the card list's tiles (by the name they show)
	All.RemoveAll([](const UOKDreamControl* C){return !C->GetShown();});
	TMap<FString,int32> Seen;
	for(const UOKDreamControl* C:All)
	{
		const FString P=S->ControlPath(C);
		const int32 N=++Seen.FindOrAdd(P);
		Paths.Add(N>1?FString::Printf(TEXT("%s #%d"),*P,N):P);
	}
}

bool UOKReaderScreen::PressControl(const FString& Text,int32 Index,FString* OutNote,const FString* SetTo)
{
	TArray<UOKDreamControl*> All;TArray<FString> Paths;
	OKReaderAllControls(this,All,Paths,Controls,SubButtons,RailButtons,Drawers,CardButtons);
	// A path names one control; a text may name several. Exact first, then containing it.
	const bool bPath=Text.Contains(TEXT("›"));
	TArray<int32> Found;
	for(int32 Pass=0;Pass<2&&Found.IsEmpty();++Pass)
		for(int32 I=0;I<All.Num();++I)
		{
			const FString Name=bPath?Paths[I]:All[I]->GetShownText().TrimStartAndEnd();
			if(Pass==0?Name==Text:Name.Contains(Text))Found.Add(I);
		}
	auto List=[&Paths](const TArray<int32>& Of){FString L;for(int32 I=0;I<Of.Num();++I)L+=FString::Printf(TEXT("\n  #%d %s"),I,*Paths[Of[I]]);return L;};
	if(Found.IsEmpty()){if(OutNote)*OutNote=TEXT("no shown control named ")+Text;return false;}
	int32 Pick=0;
	if(Index>=0)
	{
		if(!Found.IsValidIndex(Index)){if(OutNote)*OutNote=FString::Printf(TEXT("only %d control(s) named %s:"),Found.Num(),*Text)+List(Found);return false;}
		Pick=Index;
	}
	else if(Found.Num()>1){if(OutNote)*OutNote=FString::Printf(TEXT("ambiguous: %d controls named %s; give the path or #N:"),Found.Num(),*Text)+List(Found);return false;}
	if(OutNote)
	{
		*OutNote=(SetTo?FString::Printf(TEXT("set %s = "),*Paths[Found[Pick]])+*SetTo:TEXT("pressed ")+Paths[Found[Pick]]);
		// A short name matched exactly while other controls contain it: say which, so a caller meaning one of them notices.
		if(!bPath)
		{
			TArray<int32> Also;
			for(int32 I=0;I<All.Num();++I)if(!Found.Contains(I)&&All[I]->GetShownText().Contains(Text))Also.Add(I);
			if(Also.Num())*OutNote+=TEXT("\n(also containing it, by path:")+List(Also)+TEXT(")");
		}
	}
	if(SetTo)
	{
		FString Why;
		if(All[Found[Pick]]->SetValue(*SetTo,&Why))return true;
		if(OutNote)*OutNote+=TEXT(" failed: ")+Why;
		return false;
	}
	return All[Found[Pick]]->Press();
}

void UOKReaderScreen::ListControls(FOutputDevice& Out,const FString& Filter) const
{
	TArray<UOKDreamControl*> All;TArray<FString> Paths;
	OKReaderAllControls(this,All,Paths,Controls,SubButtons,RailButtons,Drawers,CardButtons);
	for(const FString& P:Paths)if(Filter.IsEmpty()||P.Contains(Filter))Out.Log(P);
}

bool UOKReaderScreen::ViewSpan(const FVector2D& ViewportSize,float& OutLeft,float& OutRight,float& OutTop) const
{
	if(!bBuilt||ViewportSize.X<=0.f||ViewportSize.Y<=0.f)return false;
	// The screen canvas scales with the viewport height (Open: 1920x1080 reference, matched on height).
	const float Scale=ViewportSize.Y/1080.f;
	OutLeft=LeftWidth*Scale;OutRight=ViewportSize.X-RightWidth*Scale;
	// Below the camera bar (12 from the top, 56 high) and a gap.
	OutTop=(12.f+56.f+8.f)*Scale;
	// And below the notice while it shows.
	if(Notice&&bNoticeShown&&!ShownNotice.IsEmpty())OutTop+=(Notice->GetHeight()+8.f)*Scale;
	return OutRight>OutLeft;
}

void UOKReaderScreen::SetLeftWidth(float Width)
{
	// No wider than leaves the camera bar its room (the screen is 1080 design pixels high, as wide as its aspect makes it).
	float Max=1000.f;
	if(GEngine&&GEngine->GameViewport&&GEngine->GameViewport->Viewport){const FIntPoint Size=GEngine->GameViewport->Viewport->GetSizeXY();if(Size.Y>0)Max=FMath::Min(Max,Size.X*1080.f/Size.Y-RightWidth-32.f-CameraBarWidth);}
	// 540: narrower cuts the slider rows (their label, value and reset button keep their widths).
	LeftWidth=FMath::Clamp(Width,540.f,FMath::Max(540.f,Max));Layout();
}

void UOKReaderScreen::Layout()
{
	if(LeftPanel)LeftPanel->SetWidth(LeftWidth);
	if(RightPanel)RightPanel->SetWidth(RightWidth);
	// The camera bar spans the 3D view between the two panels, 16 px clear of each.
	if(CameraBar){CameraBar->SetSizeDelta(FVector2D(-(LeftWidth+RightWidth+32.f),56.f));CameraBar->SetHorizontalAnchoredPosition((LeftWidth-RightWidth)*.5f);}
	if(NamePlate)NamePlate->SetHorizontalAnchoredPosition(-(RightWidth+16.f));
	// The notice spans the 3D view as the camera bar does; its height follows its lines (TickNotice).
	if(Notice){Notice->SetSizeDelta(FVector2D(-(LeftWidth+RightWidth+32.f),Notice->GetSizeDelta().Y));Notice->SetHorizontalAnchoredPosition((LeftWidth-RightWidth)*.5f);ShownNotice.Reset();}
}

// The left panel's right edge is a handle: press near it and drag.
void UOKReaderScreen::TickResize()
{
	// The mouse as DreamGUI sees it (the same pointer its hit test uses): its Slate input source consumes presses over its
	// widgets (the handle is one), so the player controller's input never sees them.
	if(!GEngine||!GEngine->GameViewport||!GEngine->GameViewport->Viewport)return;
	const FIntPoint Size=GEngine->GameViewport->Viewport->GetSizeXY();if(Size.Y<=0)return;
	UDreamEventSystem* Events=UDreamEventSystem::GetDreamEventSystemInstance(this,0);
	const UDreamPointerEventData* Pointer=Events?Events->GetPointerEventData(DreamUIPointerIds::Mouse,false):nullptr;
	if(!Pointer){bResizing=false;bResizeMouseWasDown=false;return;}
	const float X=Pointer->PointerPosition.X;
	const float Scale=Size.Y/1080.f;const bool Down=Pointer->bNowIsTriggerPressed;
	const bool bJustPressed=Down&&!bResizeMouseWasDown;bResizeMouseWasDown=Down;
	const float Edge=LeftWidth*Scale;
	if(bJustPressed)UE_LOG(LogTemp,Verbose,TEXT("ok.ReaderScreen: press at x=%.1f, panel edge %.1f"),X,Edge);
	// The handle is 8 design pixels inside the edge; a little either side of it still grabs.
	if(!bResizing&&bJustPressed&&X>=Edge-12.f*Scale&&X<=Edge+6.f*Scale){bResizing=true;ResizeStartX=X;ResizeStartWidth=LeftWidth;}
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
		bool bSame=S->GetChildrenCount()==Panels[I].Children&&Panels[I].Kids.Num()==Panels[I].Children;
		for(int32 K=0;bSame&&K<Panels[I].Kids.Num();++K)bSame=Panels[I].Kids[K].Get()==S->GetChildAt(K);
		if(!bSame)
		{
			// Logged only: a rebuild drops whatever was typed into a field under it (the motion search). Not seen in the
			// 2026-11-18 measurement; this line says when it happens, before anything is built for it.
			UE_LOG(LogTemp,Log,TEXT("ok.ReaderScreen: %s children %d -> %d, mirrored again"),*S->GetName(),Panels[I].Children,S->GetChildrenCount());
			Panels[I].Children=S->GetChildrenCount();Panels[I].Kids.Reset();for(int32 K=0;K<S->GetChildrenCount();++K)Panels[I].Kids.Add(S->GetChildAt(K));const bool bHorizontal=Panels[I].bHorizontal;
			MirrorChildren(S,T,bHorizontal);
		}
	}
	// A page built from what showed then (the bone rows of one category) is built again when that changes.
	if(Categories.IsValidIndex(Category)&&Categories[Category].Groups.IsValidIndex(Sub))
	{
		const FGroup& Current=Categories[Category].Groups[Sub];
		if(Current.Signature&&Current.Signature()!=ShownSignature)ShowCategory(Category,Sub);
	}
	ApplyWantedScopes();
	Controls.RemoveAll([](const TObjectPtr<UOKDreamControl>& C){return !IsValid(C);});
	for(int32 I=0;I<Controls.Num();++I)Controls[I]->Sync();
	for(UOKDreamControl* D:Drawers)if(IsValid(D))D->Sync();
	if(UOKCharacterController* G=Controller.Get())
	{
		// The card wall until a card is open, the editor once one is; a new card folder lists again.
		if(G->bModelLayout!=bShownModelLayout){bShownModelLayout=G->bModelLayout;ShowTab(bShownModelLayout?0:1);}
		else if(Tab==1&&G->Entries.Num()!=ShownEntries)ShowCategory(Category,Sub);
		MarkCurrentCard();
	}
	TickNotice();
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
	// Logged only, once per entry: DreamGUI takes keys only while the game viewport has Slate's keyboard focus
	// (FDreamUISlateInputSource::IsKeyForThisWorld), so focus inside the hidden UMG layer would leave its fields deaf.
	// Measured 2026-11-18 with ui_focus (clicks, typing, motions, cards): never happened; nothing is done about it here.
	if(FSlateApplication::IsInitialized())if(UOKCharacterController* G=Controller.Get())
	{
		const bool bUmgFocus=G->HasAnyUserFocus()||G->HasFocusedDescendants();
		if(bUmgFocus&&!bUmgHadFocus)UE_LOG(LogTemp,Log,TEXT("ok.ReaderScreen: keyboard focus is in the hidden UMG layer (DreamGUI fields get no keys until the viewport has it)"));
		bUmgHadFocus=bUmgFocus;
	}
	TickResize();
	SyncAll();
	TickThumbnails();
	// The camera watch (ok.ReaderScreen look): a changed orbit is put down to the mouse when the player controller noted
	// a drag or wheel this frame or the last, else to something else; with the mouse buttons Slate holds as pressed then.
	if(UOKCharacterController* G=Controller.Get())if(const AKKPreviewActor* A=G->PreviewActor.Get())
	{
		using namespace OKReaderCameraWatch;
		const bool bMoved=bHave&&(!FMath::IsNearlyEqual(Yaw,A->OrbitYaw,.01f)||!FMath::IsNearlyEqual(Pitch,A->OrbitPitch,.01f)
			||!FMath::IsNearlyEqual(Distance,A->OrbitDistance,.05f)||!Focus.Equals(A->OrbitFocus,.05f));
		if(bMoved)
		{
			LastWho=NotedFrame+1>=GFrameCounter&&!NotedWho.IsEmpty()?NotedWho:TEXT("not the mouse (a view button, the MCP, a load or a pose change)");
			LastAt=FPlatformTime::Seconds();LastButtons=PressedButtons();
		}
		bHave=true;Yaw=A->OrbitYaw;Pitch=A->OrbitPitch;Distance=A->OrbitDistance;Focus=A->OrbitFocus;
	}
	// The left scroll box takes its content's extent only when content is added (UDreamScrollBox::AddContent), and a page
	// is added empty and then filled, rebuilt when a UMG list changes, its rows shown and hidden: measured 2026-11-18, the
	// 屬性 page ran below the panel with no bar and the wheel did nothing. Re-take it whenever the page's height moved.
	if(LeftScroll&&PageWidgets.Num()&&++PageMeasureFrame>=6)
	{
		PageMeasureFrame=0;
		const UDreamWidget* Page=PageWidgets.Last();
		const UDreamLayoutContainer* Layout=Page?Page->GetLayoutContainer():nullptr;
		const float Height=Layout?Layout->GetLayoutPreferredSize().Y:-1.f;
		if(!FMath::IsNearlyEqual(Height,ShownPageHeight,0.5f)){ShownPageHeight=Height;LeftScroll->RefreshContentExtent();}
	}
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
	TEXT("ok.ReaderScreen tab <0-3> | category <name> | sub <name> | width <px> | press <path|text> [#N] | set <path|text> [#N] = <value> | controls [filter] | card <N> | scroll <0-1> | look | gameroot [folder|default] | library [folder|default] | state: the card reader's DreamGUI screen"),
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
		// "press <text> [#N]": the shown control with that text (the N-th of several, from 0) is clicked as the pointer would.
		else if(Verb==TEXT("press"))
		{
			FString Text=Value;int32 Index=-1;int32 Hash=INDEX_NONE;
			if(!Text.Contains(TEXT("›"))&&Text.FindLastChar(TEXT('#'),Hash)&&Text.Mid(Hash+1).IsNumeric()){Index=FCString::Atoi(*Text.Mid(Hash+1));Text=Text.Left(Hash).TrimEnd();}
			FString Note;
			Done=!Text.IsEmpty()&&S->PressControl(Text,Index,&Note);
			if(!Note.IsEmpty())Out.Log(Note);
		}
		// "set <path|text> [#N] = <value>": a slider, toggle, drop-down or input set as a person would (the same matching as press).
		else if(Verb==TEXT("set"))
		{
			int32 Eq=INDEX_NONE;
			Done=Value.FindChar(TEXT('='),Eq);
			if(Done)
			{
				FString Text=Value.Left(Eq).TrimStartAndEnd();const FString To=Value.Mid(Eq+1).TrimStartAndEnd();int32 Index=-1;int32 Hash=INDEX_NONE;
				if(!Text.Contains(TEXT("›"))&&Text.FindLastChar(TEXT('#'),Hash)&&Text.Mid(Hash+1).IsNumeric()){Index=FCString::Atoi(*Text.Mid(Hash+1));Text=Text.Left(Hash).TrimEnd();}
				FString Note;
				Done=!Text.IsEmpty()&&S->PressControl(Text,Index,&Note,&To);
				if(!Note.IsEmpty())Out.Log(Note);
			}
		}
		// "controls [filter]": every shown control's path (what press takes), flagging paths two controls share.
		else if(Verb==TEXT("controls"))S->ListControls(Out,Value);
		// "resources": counts and sizes that must not grow without bound over a long session (thumbnail pools and caches,
		// mirrored controls, live textures by kind, the RHI's texture memory).
		else if(Verb==TEXT("resources"))S->ListResources(Out);
		// "card <N>": the card list's N-th tile (from 0) clicked as the pointer would; prints its file.
		else if(Verb==TEXT("card"))
		{
			const int32 I=Value.IsNumeric()?FCString::Atoi(*Value):-1;
			Done=S->PressCard(I);
			if(Done)Out.Logf(TEXT("card=%d file=%s"),I,*S->CardFile(I));
		}
		// "scroll <0..1>": the left page to that point of its length (screenshots of a long page).
		else if(Verb==TEXT("scroll")){Done=Value.IsNumeric();if(Done)S->ScrollLeftPage(FCString::Atof(*Value));}
		else if(Verb==TEXT("width")){Done=Value.IsNumeric();if(Done)S->SetLeftWidth(FCString::Atof(*Value));}
		// 設定 › 遊戲目錄: "gameroot <folder>" / "library <folder>" save as the page does ("default" forgets the user's choice);
		// either with no folder reports what is set and found.
		// "look": what follows the cursor and who moved the camera last, so "the view moves without a button held" is told
		// apart in one line: eyes on the cursor (eye_mode 1), the head following the camera, or the camera itself.
		else if(Verb==TEXT("look"))
		{
			using namespace OKReaderCameraWatch;
			UOKCharacterController* G=S->GetController();const AKKPreviewActor* A=G?G->PreviewActor.Get():nullptr;
			if(!A){Out.Log(TEXT("look: no character"));return;}
			static const TCHAR* EyeModes[]={TEXT("front"),TEXT("cursor"),TEXT("camera")};
			Out.Logf(TEXT("look eye_mode=%d(%s) eye_tracking=%d eye_follows_camera=%d gaze=%.3f,%.3f,%.3f head_follows_camera=%d buttons=%s"),
				G->EyeMode,EyeModes[FMath::Clamp(G->EyeMode,0,2)],A->bEyeLookTracking?1:0,A->bEyeLookFollowCamera?1:0,
				A->EyeGaze[0],A->EyeGaze[1],A->EyeGaze[2],A->bHeadLookFollowCamera?1:0,*PressedButtons());
			Out.Logf(TEXT("camera yaw=%.2f pitch=%.2f distance=%.1f focus=%s last_change=%s %s"),A->OrbitYaw,A->OrbitPitch,A->OrbitDistance,*A->OrbitFocus.ToCompactString(),
				LastWho.IsEmpty()?TEXT("none"):*LastWho,LastWho.IsEmpty()?TEXT(""):*FString::Printf(TEXT("%.1f s ago, buttons then=%s"),FPlatformTime::Seconds()-LastAt,*LastButtons));
			return;
		}
		else if(Verb==TEXT("gameroot")||Verb==TEXT("library"))
		{
			const bool bLibrary=Verb==TEXT("library");
			if(!Value.IsEmpty())S->ApplyFolderSetting(bLibrary,Value==TEXT("default")?FString():Value,Value==TEXT("default"));
			UKKGameRoot* Game=UKKGameRoot::Get();
			Out.Logf(TEXT("%s=%s user=%s"),*Verb,bLibrary?*Game->LocalLibrary:*Game->Root,(bLibrary?UKKGameRoot::HasUserLocalLibrary():UKKGameRoot::HasUserRoot())?TEXT("yes"):TEXT("no"));
			if(!bLibrary){const FString Mods=Game->Root/TEXT("mods");TArray<FString> Found;if(!Game->Root.IsEmpty()&&FPaths::DirectoryExists(Mods))IFileManager::Get().FindFilesRecursive(Found,*Mods,TEXT("*.zipmod"),true,false);Out.Logf(TEXT("mods=%s zipmods=%d"),FPaths::DirectoryExists(Mods)?TEXT("yes"):TEXT("no"),Found.Num());}
		}
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
		Out.Logf(TEXT("%s tab=%s category=%s left_width=%.0f thumbs=%s notice=%s"),Done?TEXT("ok"):TEXT("failed"),*S->CurrentTab(),*S->CurrentCategory(),S->GetLeftWidth(),*S->ThumbState(),*S->NoticeState().Replace(TEXT("\n"),TEXT(" | ")));
	}));
