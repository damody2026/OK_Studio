#pragma once
#include "CoreMinimal.h"
#include "Core/DreamTextUserWidget.h"
#include "OKReaderScreen.generated.h"

class UOKCharacterController;
class UDreamButton;
class UDreamSlider;
class UDreamToggle;
class UDreamDropdown;
class UDreamTextInput;
class UDreamScrollBox;
class UWidget;
class UPanelWidget;

// The card reader's DreamGUI screen (DUI/Reader/ReaderScreen.dui) and its controls (DUI/Reader/Controls/*.dui).
//
// The character controller (UOKCharacterController) keeps its UMG widgets as the model: every handler, the save
// paths and the game MCP (ui_*, reader_call) read and write those. They are no longer drawn -- the controller's
// UMG root is see-through and lets the pointer through -- and this screen shows a DreamGUI control for each one:
// a value set here is set on the UMG control and its event fired, exactly what ui_set does; what the controller
// changes on its side shows here on the next frame.

// One mirrored control. The .dui file decides which of the parts below exist; the rest stay null.
UCLASS()
class OPENKOIKATSU_API UOKDreamControl : public UDreamTextUserWidget
{
	GENERATED_BODY()
public:
	UPROPERTY() TObjectPtr<UDreamWidget> Label;
	UPROPERTY() TObjectPtr<UDreamButton> Button;
	UPROPERTY() TObjectPtr<UDreamSlider> Slider;
	UPROPERTY() TObjectPtr<UDreamToggle> Toggle;
	UPROPERTY() TObjectPtr<UDreamDropdown> Choice;
	UPROPERTY() TObjectPtr<UDreamTextInput> Input;
	UPROPERTY() TObjectPtr<UDreamWidget> Picture;
	// A drawer: the header button, its title and the body that folds away.
	UPROPERTY() TObjectPtr<UDreamButton> Header;
	UPROPERTY() TObjectPtr<UDreamWidget> Title;
	UPROPERTY() TObjectPtr<UDreamWidget> Body;

	// The UMG control this one shows (null for a control of the screen's own).
	TWeakObjectPtr<UWidget> Source;
	// Pressed when there is no UMG source (the screen's own buttons).
	TFunction<void()> OnPressed;
	// Text shown instead of the source's own (a drawer's title, a tab).
	FString FixedText;

	void SetText(const FString& Text);
	void SetOpen(bool bOpen);
	bool IsOpen() const { return bOpen; }
	// Copy the UMG control's state into this one. Cheap when nothing changed.
	void Sync();

protected:
	virtual void NativeOnInitialized() override;
	UFUNCTION() void HandleClicked();
	UFUNCTION() void HandleHeader();
	UFUNCTION() void HandleSlider(float Value);
	UFUNCTION() void HandleToggle(bool bOn);
	UFUNCTION() void HandleChoice(int32 Index);
	UFUNCTION() void HandleInputCommitted(const FString& Text);

private:
	bool bPushing=false;
	bool bOpen=true;
	FString ShownText;
	TArray<FString> ShownOptions;
	TWeakObjectPtr<class UTexture> ShownTexture;
};

// A row or column holding mirrored children, kept in step with the UMG panel it shows.
struct FOKDreamMirrorPanel
{
	TWeakObjectPtr<UPanelWidget> Source;
	TWeakObjectPtr<UDreamWidget> Target;
	int32 Children=-1;
	bool bHorizontal=false;
};

UCLASS()
class OPENKOIKATSU_API UOKReaderScreen : public UDreamTextUserWidget
{
	GENERATED_BODY()
public:
	UPROPERTY() TObjectPtr<UDreamWidget> LeftPanel;
	UPROPERTY() TObjectPtr<UDreamWidget> CameraBar;
	UPROPERTY() TObjectPtr<UDreamWidget> NamePlate;
	UPROPERTY() TObjectPtr<UDreamWidget> RightPanel;
	UPROPERTY() TObjectPtr<UDreamButton> BackToLauncher;
	UPROPERTY() TObjectPtr<UDreamButton> Tab0;
	UPROPERTY() TObjectPtr<UDreamButton> Tab1;
	UPROPERTY() TObjectPtr<UDreamButton> Tab2;
	UPROPERTY() TObjectPtr<UDreamButton> Tab3;
	UPROPERTY() TObjectPtr<UDreamWidget> RailHost;
	UPROPERTY() TObjectPtr<UDreamWidget> SubMenuHost;
	UPROPERTY() TObjectPtr<UDreamWidget> CategoryTitle;
	UPROPERTY() TObjectPtr<UDreamScrollBox> LeftScroll;
	UPROPERTY() TObjectPtr<UDreamWidget> LeftResizeHandle;
	UPROPERTY() TObjectPtr<UDreamWidget> CameraBarHost;
	UPROPERTY() TObjectPtr<UDreamWidget> CardName;
	UPROPERTY() TObjectPtr<UDreamScrollBox> RightScroll;
	UPROPERTY() TObjectPtr<UDreamWidget> PluginHost;

	// Show this screen for the controller, whose UMG tree must already be built.
	static UOKReaderScreen* Open(UOKCharacterController* Controller);
	// Every frame from the controller's tick.
	void Tick(float DeltaSeconds);
	// The screen's own state, for the game MCP's reader state.
	FString CurrentTab() const;
	FString CurrentCategory() const;
	bool SelectCategory(const FString& Name);
	bool SelectSub(const FString& Name);
	void ShowTabPublic(int32 Index){ShowTab(Index);}
	void SetLeftWidth(float Width);
	float GetLeftWidth() const { return LeftWidth; }

protected:
	virtual void NativeOnInitialized() override;
	UFUNCTION() void HandleBackToLauncher();
	UFUNCTION() void HandleTab0();
	UFUNCTION() void HandleTab1();
	UFUNCTION() void HandleTab2();
	UFUNCTION() void HandleTab3();

private:
	struct FGroup {FString Name;TArray<TWeakObjectPtr<UWidget>> Sources;TFunction<void()> OnEnter;};
	struct FCategory {FString Name;int32 Tab=0;TArray<FGroup> Groups;TFunction<void()> OnEnter;};

	TWeakObjectPtr<UOKCharacterController> Controller;
	TArray<FCategory> Categories;
	int32 Tab=0;
	int32 Category=0;
	int32 Sub=0;
	float LeftWidth=560.f;
	float RightWidth=440.f;
	// The camera bar's buttons at their natural widths, plus its padding: the 3D view between the panels keeps this much.
	float CameraBarWidth=0.f;
	bool bBuilt=false;
	bool bShownModelLayout=false;
	int32 ShownEntries=-1;
	bool bResizing=false,bResizeMouseWasDown=false;
	float ResizeStartX=0.f,ResizeStartWidth=0.f;

	UPROPERTY() TArray<TObjectPtr<UOKDreamControl>> Controls;
	UPROPERTY() TArray<TObjectPtr<UOKDreamControl>> RailButtons;
	UPROPERTY() TArray<TObjectPtr<UOKDreamControl>> SubButtons;
	UPROPERTY() TArray<TObjectPtr<UOKDreamControl>> Drawers;
	UPROPERTY() TArray<TObjectPtr<UDreamWidget>> PageWidgets;
	TArray<FOKDreamMirrorPanel> Panels;

	void BuildCategories();
	void BuildDrawers();
	void BuildCameraBar();
	void BuildPluginTools();
	void ShowTab(int32 Index);
	void ShowCategory(int32 Index,int32 SubIndex=0);
	void ClearPage();
	void Layout();
	void TickResize();
	void SyncAll();

	UOKDreamControl* MakeControl(const TCHAR* Kind,UDreamWidget* Into);
	UOKDreamControl* MakeOwnButton(UDreamWidget* Into,const FString& Text,TFunction<void()> Press);
	UDreamWidget* MakePanel(UDreamWidget* Into,bool bHorizontal,float Spacing);
	void Mirror(UWidget* Source,UDreamWidget* Into,bool bInRow);
	void MirrorChildren(UPanelWidget* Source,UDreamWidget* Target,bool bHorizontal);
	void AddToHost(UDreamWidget* Host,UDreamWidget* Child,bool bFill);
};
