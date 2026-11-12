#pragma once

// OK Studio VNGE Workspace UI: viewport subtitle/3D-text & VNSS dialogue overlay + 9 Simplified Chinese floating panels.
#include "CoreMinimal.h"
#include "OKStudioGame.h"
#include "OKStudioVnge.h"
#include "Styling/SlateBrush.h"
#include "Widgets/SCompoundWidget.h"

class SVerticalBox;

class SOKStudioVngeOverlay : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SOKStudioVngeOverlay) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UOKStudioGame>, Game)
		SLATE_ARGUMENT(TFunction<bool()>, IsUiHidden)
		SLATE_ARGUMENT(TFunction<void()>, OnScriptUpdated)
	SLATE_END_ARGS()

	void Construct(const FArguments& Args);
	virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& Geometry, const FSlateRect& Culling, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const override;

private:
	TWeakObjectPtr<UOKStudioGame> Game;
	TFunction<bool()> IsUiHidden;
	TFunction<void()> OnScriptUpdated;
	TSharedPtr<SVerticalBox> ChoicesBox;
	FString LastChoicesSignature;
	void RebuildChoicesIfNeeded();
};

class FOKStudioVngeUi : public TSharedFromThis<FOKStudioVngeUi>
{
public:
	TWeakObjectPtr<UOKStudioGame> Game;
	TFunction<void(const FString&)> OnStatus;
	TFunction<void(const FString&)> OnOpenWindow;
	TFunction<void(const FString&)> OnRefreshWindow;
	TFunction<void()> OnSceneChanged;
	TFunction<FString()> GetCardBrowserPreview;

	void RefreshAllOpenVngeWindows();
	void ResetTransientCaches() { ThumbBrushes.Reset(); }

	TSharedRef<SWidget> BuildHub();
	TSharedRef<SWidget> BuildSss();
	TSharedRef<SWidget> BuildPoseLib();
	TSharedRef<SWidget> BuildAnime();
	TSharedRef<SWidget> BuildText();
	TSharedRef<SWidget> BuildSound();
	TSharedRef<SWidget> BuildPhysics();
	TSharedRef<SWidget> BuildUtils();
	TSharedRef<SWidget> BuildScript();

	// Shared state accessible for commands
	int32 SssTab = 0; // 0: States, 1: Cameras, 2: Tracking, 3: Ministates/SSSB
	bool bSssSmoothCam = true;
	FString NewStateId, NewWhoSay, NewWhatSay, NewTagAlias;

	FString PoseCategory = TEXT("posef");
	FString PoseSearch;
	FString NewPresetName;
	int32 PosePage = 0;

	int32 SelectedClip = 0;
	FString NewClipName = TEXT("新动作剪辑");
	float NewClipDuration = 4.f;

	int32 SelectedText = 0;

	int32 SelectedSound = 0;
	FString NewSoundPath;

	int32 SelectedRule = 0;
	bool bShowRawPhysicsJson = false;

	float StepMoveCm = 5.f;
	float StepRotDeg = 10.f;
	bool bStepLocal = true;
	FString BatchCardPath;
	bool bBatchKeepClothes = true;
	FOKVngeCopyMask CopyMask;

	int32 SelectedScriptBlock = 0;
	FString NewScriptBlockName = TEXT("main");
	FString NewScriptLine;

private:
	TMap<FString, TSharedPtr<FSlateBrush>> ThumbBrushes;
	const FSlateBrush* BrushForPreset(const FString& FullPath);
	int32 TargetCharacterId() const;
	void Status(const FString& Msg) const { if (OnStatus) OnStatus(Msg); }
	void MarkChanged() const { if (OnSceneChanged) OnSceneChanged(); }
	void DeferWin(const FString& Id) const { if (OnRefreshWindow) OnRefreshWindow(Id); }
};
