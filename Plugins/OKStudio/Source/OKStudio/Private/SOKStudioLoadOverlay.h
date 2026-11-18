#pragma once

// What a loading scene shows while its objects build. With ok.Studio.LoadSkipDraw on (the default) the world area is
// cleared every frame until the last object is built (UGameViewportClient::Draw clears the canvas when
// bDisableWorldRendering is set), so without this the screen is black for a minute or more and looks hung. Slate draws
// on top regardless, and the default Slate font has CJK glyphs, unlike the engine's small debug font.
//
// The overlay sits in the game viewport above the studio panel and collapses itself when the scene actor has nothing
// left to build; it never takes input. Words come from the studio text tables (OKStudioText.h, studio.toml "load.*").
//
// ok.Studio.LoadSkipDraw defaults to 1 only because this overlay exists: it is the only progress a loading scene shows
// (AOKStudioGameMode::StartPlay turns the engine's on-screen messages off, so AddOnScreenDebugMessage never draws in
// the studio). Before removing it, disabling it or changing when it shows (HasPendingBuilds()), tell whoever owns
// LoadSkipDraw (OKSceneActor.cpp) so its default goes back to 0 in the same change; otherwise a big scene is black for
// a minute or more.
#include "CoreMinimal.h"
#include "Widgets/SCompoundWidget.h"
#include "UObject/WeakObjectPtrTemplates.h"

class UOKStudioGame;

class SOKStudioLoadOverlay : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SOKStudioLoadOverlay) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UOKStudioGame>, Game)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);

	/** Objects built and in all for the scene being loaded; false when nothing is loading. */
	static bool Progress(const UOKStudioGame* Game, int32& OutBuilt, int32& OutTotal);

private:
	TWeakObjectPtr<UOKStudioGame> Game;
	EVisibility Shown() const;
	FText SceneName() const;
	FText ProgressText() const;
	FText PercentText() const;
	TOptional<float> Fraction() const;
	float Scale() const;
};
