#include "SOKStudioLoadOverlay.h"

#include "OKSceneActor.h"
#include "OKSceneDocument.h"
#include "OKStudioGame.h"
#include "OKStudioStyle.h"
#include "OKStudioText.h"
#include "OKStudioSettings.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Misc/Paths.h"
#include "Widgets/Images/SThrobber.h"
#include "Widgets/Layout/SDPIScaler.h"
#include "Widgets/Notifications/SProgressBar.h"

bool SOKStudioLoadOverlay::Progress(const UOKStudioGame* InGame, int32& OutBuilt, int32& OutTotal)
{
	OutBuilt = OutTotal = 0;
	const AOKSceneActor* Actor = InGame ? InGame->SceneActor.Get() : nullptr;
	if (!Actor || !Actor->Document || !Actor->HasPendingBuilds()) return false;
	// The same count the actor's own progress line used: objects built so far against every object of the scene.
	OutBuilt = Actor->LoadStats.Characters + Actor->LoadStats.Items + Actor->LoadStats.Others;
	OutTotal = Actor->Document->Objects.Num();
	OutBuilt = FMath::Clamp(OutBuilt, 0, OutTotal);
	return true;
}

void SOKStudioLoadOverlay::Construct(const FArguments& InArgs)
{
	Game = InArgs._Game;
	using namespace OKStudioStyle;
	ChildSlot
	[
		SNew(SBox)
		.Visibility(this, &SOKStudioLoadOverlay::Shown)
		.HAlign(HAlign_Center)
		.VAlign(VAlign_Center)
		.Padding(16.f)
		[
			SNew(SDPIScaler)
			.DPIScale(this, &SOKStudioLoadOverlay::Scale)
			[
				SNew(SBox)
				.MinDesiredWidth(360.f)
				.MaxDesiredWidth(520.f)
				[
					SNew(SBorder)
					.BorderImage(Brush(Panel()))
					.Padding(FMargin(20.f, 16.f))
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight()
						[
							SNew(SHorizontalBox)
							+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 12.f, 0.f)
							[
								SNew(SCircularThrobber).Radius(11.f).NumPieces(8).Period(0.9f)
							]
							+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
							[
								Label(FText::FromString(OKStudioT(TEXT("load.title"))), 16.f)
							]
							+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
							[
								Label(TAttribute<FText>::CreateSP(this, &SOKStudioLoadOverlay::PercentText), 14.f, TextSoft())
							]
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 8.f, 0.f, 0.f)
						[
							SNew(STextBlock).Text(this, &SOKStudioLoadOverlay::SceneName).Font(Font(12.f)).ColorAndOpacity(TextSoft())
							.AutoWrapText(true)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 12.f, 0.f, 0.f)
						[
							SNew(SBox).HeightOverride(8.f)
							[
								SNew(SProgressBar).Percent(this, &SOKStudioLoadOverlay::Fraction).FillColorAndOpacity(On())
								.BackgroundImage(Brush(ListArea()))
							]
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 8.f, 0.f, 0.f)
						[
							Label(TAttribute<FText>::CreateSP(this, &SOKStudioLoadOverlay::ProgressText), 11.f, TextHint())
						]
					]
				]
			]
		]
	];
}

EVisibility SOKStudioLoadOverlay::Shown() const
{
	int32 Built, Total;
	return Progress(Game.Get(), Built, Total) ? EVisibility::HitTestInvisible : EVisibility::Collapsed;
}

FText SOKStudioLoadOverlay::SceneName() const
{
	const UOKStudioGame* G = Game.Get();
	return FText::FromString(G && !G->File.IsEmpty() ? FPaths::GetBaseFilename(G->File) : FString());
}

FText SOKStudioLoadOverlay::ProgressText() const
{
	int32 Built, Total;
	if (!Progress(Game.Get(), Built, Total)) return FText::GetEmpty();
	if (Built == 0) return FText::FromString(OKStudioT(TEXT("load.waiting")));
	return FText::FromString(OKStudioMsg(TEXT("load.progress"), {{TEXT("built"), Built}, {TEXT("total"), Total}}));
}

FText SOKStudioLoadOverlay::PercentText() const
{
	int32 Built, Total;
	if (!Progress(Game.Get(), Built, Total) || Total <= 0) return FText::GetEmpty();
	return FText::FromString(OKStudioMsg(TEXT("load.percent"), {{TEXT("percent"), int32(100.0 * Built / Total)}}));
}

TOptional<float> SOKStudioLoadOverlay::Fraction() const
{
	int32 Built, Total;
	if (!Progress(Game.Get(), Built, Total) || Total <= 0) return 0.f;
	return float(Built) / float(Total);
}

float SOKStudioLoadOverlay::Scale() const
{
	// The panel's rule (SOKStudioPanel::UiDpiScale): the studio canvas (1600x900 reference, CanvasScaler match 0.5) on
	// the window's pixels, divided by the scale Slate already applies, times the UI scale setting; so the box keeps its
	// share of the window at 1920x1080 and in a small window alike.
	const FGeometry& G = GetTickSpaceGeometry();
	const float Pixel = G.Scale > 0.f ? G.Scale : 1.f;
	FVector2D Size = FVector2D(G.GetLocalSize()) * Pixel;
	if ((Size.X <= 0. || Size.Y <= 0.) && GEngine && GEngine->GameViewport) GEngine->GameViewport->GetViewportSize(Size);
	return OKStudioStyle::CanvasScale(Size) / Pixel * FMath::Clamp(FOKStudioSettings::Get().UiScale, 0.5f, 2.f);
}
