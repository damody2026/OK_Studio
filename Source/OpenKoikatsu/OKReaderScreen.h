#pragma once
#include "CoreMinimal.h"
#include "Core/DreamTextUserWidget.h"
#include "HAL/ThreadSafeBool.h"
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
	// A drawer's fold sign (▼ open, ▶ folded).
	UPROPERTY() TObjectPtr<UDreamWidget> Arrow;

	// The UMG control this one shows (null for a control of the screen's own).
	TWeakObjectPtr<UWidget> Source;
	// Pressed when there is no UMG source (the screen's own buttons).
	TFunction<void()> OnPressed;
	// Text shown instead of the source's own (a drawer's title, a tab).
	FString FixedText;
	// A drop-down: only the options matching this show (a search field above it sets it).
	FString Filter;
	// Hidden and shown with this control (its search field), and only for a list of at least SearchMinOptions entries.
	TWeakObjectPtr<UDreamWidget> Companion;
	static constexpr int32 SearchMinOptions=30;

	void SetText(const FString& Text);
	void SetOpen(bool bOpen);
	bool IsOpen() const { return bOpen; }
	// Copy the UMG control's state into this one. Cheap when nothing changed.
	void Sync();
	// A click on it, as the pointer would (ok.ReaderScreen press): false when it is not a shown, enabled button.
	bool Press();
	const FString& GetShownText() const { return ShownText; }

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
	bool bCaptionFitted=false;
	FString ShownText;
	TArray<FString> ShownOptions;
	// Shown option -> the UMG option index; the filter and option count it was made for.
	TArray<int32> OptionMap;
	FString ShownFilter;
	int32 ShownSourceCount=-1;
	TWeakObjectPtr<class UTexture> ShownTexture;
};

// A row or column holding mirrored children, kept in step with the UMG panel it shows.
struct FOKDreamMirrorPanel
{
	TWeakObjectPtr<UPanelWidget> Source;
	TWeakObjectPtr<UDreamWidget> Target;
	int32 Children=-1;
	// Which UMG children it was mirrored from: a list rebuilt with as many new widgets (a page of the picture picker, of the
	// detailed editor) is mirrored again too.
	TArray<TWeakObjectPtr<UWidget>> Kids;
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
	UPROPERTY() TObjectPtr<UDreamWidget> Notice;
	UPROPERTY() TObjectPtr<UDreamWidget> NoticeText;

	// Show this screen for the controller, whose UMG tree must already be built.
	static UOKReaderScreen* Open(UOKCharacterController* Controller);
	// Every frame from the controller's tick.
	void Tick(float DeltaSeconds);
	// The screen's own state, for the game MCP's reader state.
	FString CurrentTab() const;
	FString CurrentCategory() const;
	bool SelectCategory(const FString& Name);
	bool SelectSub(const FString& Name);
	// Press the shown control with this text (the Index-th of several; exact text first, then containing it).
	bool PressControl(const FString& Text,int32 Index);
	void ScrollLeftPage(float Progress);
	void ShowTabPublic(int32 Index){ShowTab(Index);}
	void SetLeftWidth(float Width);
	// 設定 › 遊戲目錄 from outside the page (ok.ReaderScreen gameroot/library): saved as the page saves it, and the page,
	// when shown, shows it and what is found there. bForget: back to the default.
	void ApplyFolderSetting(bool bLibrary,const FString& Folder,bool bForget);
	// A report from the controller (UOKCharacterController::ScreenNote), shown under the camera bar for Seconds; a report
	// with the same key replaces the one shown. The engine's own on-screen messages would draw over the left panel.
	void ShowNotice(int32 Key,float Seconds,const FColor& Color,const FString& Text);
	// The reports shown now, one per line (for the game MCP and tests).
	FString NoticeState() const;
	// The card list's pictures held now, of how many tiles ("12/101"; "-" with no card list shown).
	FString ThumbState() const;
	float GetLeftWidth() const { return LeftWidth; }
	class UOKCharacterController* GetController() const;
	// The 3D view between the two panels in viewport pixels (the screen canvas is 1080 design pixels high): what the HUD
	// draws there (the height ruler) stays clear of the panels. False before the screen is laid out.
	bool ViewSpan(const FVector2D& ViewportSize,float& OutLeft,float& OutRight,float& OutTop) const;

protected:
	virtual void NativeOnInitialized() override;
	UFUNCTION() void HandleBackToLauncher();
	UFUNCTION() void HandleTab0();
	UFUNCTION() void HandleTab1();
	UFUNCTION() void HandleTab2();
	UFUNCTION() void HandleTab3();

private:
	// Sources: UMG widgets mirrored onto the page; Build: a page of the screen's own (no UMG counterpart).
	// bShownOnly: only the sources shown now are mirrored (the bone rows: hundreds, most folded away by the category);
	// Signature: the page is built again when it changes (the bone category and the X／Y／Z switch).
	struct FGroup {FString Name;TArray<TWeakObjectPtr<UWidget>> Sources;TFunction<void()> OnEnter;TFunction<void(UDreamWidget*)> Build;bool bShownOnly=false;TFunction<FString()> Signature;};
	FString ShownSignature;
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
	UPROPERTY() TArray<TObjectPtr<UDreamWidget>> RailSpacers;
	UPROPERTY() TArray<TObjectPtr<UOKDreamControl>> SubButtons;
	UPROPERTY() TArray<TObjectPtr<UOKDreamControl>> Drawers;
	UPROPERTY() TArray<TObjectPtr<UDreamWidget>> PageWidgets;
	// The card list's buttons, their texts, and the card they last marked as the current one.
	UPROPERTY() TArray<TObjectPtr<UOKDreamControl>> CardButtons;
	TArray<FString> CardTexts;
	int32 ShownCardSelection=INDEX_NONE;
	// How many cards were marked as not opening when the list was last marked.
	int32 ShownUnopenable=0;
	struct FNote{FString Text;FColor Color;double Until=0;uint64 Order=0;};
	TMap<int32,FNote> Notes;
	uint64 NoteOrder=0;
	// The text the notice shows, and whether it is shown (as laid out until the first frame hides it).
	FString ShownNotice;bool bNoticeShown=true;
	void TickNotice();
	// The card list's pictures, one per tile (null until it scrolls into view; dropped again far out of it), and which
	// tiles have a decode on the way. ThumbGeneration discards a decode finishing after the list was rebuilt.
	UPROPERTY() TArray<TObjectPtr<class UTexture2D>> CardThumbs;
	TArray<FString> CardPaths;
	TArray<bool> CardThumbLoading;
	int32 ThumbsInFlight=0;
	int32 ThumbGeneration=0;
	// Raised when the list is rebuilt: decodes still on workers stop and never report back (a destroyed screen is caught by
	// the weak pointer the report holds).
	TSharedRef<FThreadSafeBool> ThumbCancel=MakeShared<FThreadSafeBool>(false);
	// Every picture texture the list ever made, kept for the screen's life and reused (FreeThumbs: the ones no tile shows):
	// none is collected while DreamGUI may still draw it.
	UPROPERTY() TArray<TObjectPtr<class UTexture2D>> ThumbPool;
	TArray<class UTexture2D*> FreeThumbs;
	void GiveBackThumb(class UTexture2D* Texture);
	class UTexture2D* PutThumb(int32 Width,int32 Height,const TArray<uint8>& Bgra);
	// The 遊戲目錄 page's fields and what they report (the folder count runs on a worker).
	TWeakObjectPtr<UOKDreamControl> RootInput,RootStatus,LibraryInput,LibraryStatus;
	int32 RootCheckGeneration=0;
	// Whether the hidden UMG layer held the keyboard focus last frame (it is logged when it starts to).
	bool bUmgHadFocus=false;
	TArray<FOKDreamMirrorPanel> Panels;
	// The page's part of the picture picker and of the detailed editor (target prefixes, property tokens), asked for again
	// while the controller is busy (reading the catalog it opens neither): see SyncAll.
	TOptional<TArray<FString>> WantedTargets,WantedProperties;

	void BuildCategories();
	void BuildDrawers();
	void BuildCameraBar();
	void BuildPluginTools();
	void ShowTab(int32 Index);
	void ShowCategory(int32 Index,int32 SubIndex=0);
	void ClearPage();
	void MarkCurrentCard();
	void TickThumbnails();
	void BuildGameRootPage(UDreamWidget* Page);
	void CheckGameRoot(const FString& Root);
	void CheckLocalLibrary(const FString& Library);
	static FString PickFolder(const FString& Title,const FString& Start);
	void Layout();
	void TickResize();
	void SyncAll();
	void ApplyWantedScopes();

	UOKDreamControl* MakeControl(const TCHAR* Kind,UDreamWidget* Into);
	UOKDreamControl* MakeOwnButton(UDreamWidget* Into,const FString& Text,TFunction<void()> Press);
	UDreamWidget* MakePanel(UDreamWidget* Into,bool bHorizontal,float Spacing);
	void Mirror(UWidget* Source,UDreamWidget* Into,bool bInRow);
	bool InPropertyPanel(UWidget* W) const;
	static bool IsRowCaption(UWidget* W);
	float CaptionWidth() const;
	// The left page's measured height when the scroll box last took its extent (it measures only when content is added,
	// and a page is added empty and filled after).
	float ShownPageHeight=-1.f;
	int32 PageMeasureFrame=0;
	void MirrorChildren(UPanelWidget* Source,UDreamWidget* Target,bool bHorizontal);
	void AddToHost(UDreamWidget* Host,UDreamWidget* Child,bool bFill);
};
