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
#include "Framework/Application/SlateApplication.h"
#include "Widgets/SWindow.h"
#include "ImageUtils.h"
#include "Misc/FileHelper.h"
#include "Dom/JsonObject.h"

namespace
{
	/** The step before the build that holds the game thread (see BeginStage). Depth: Begin / End pairs nest (opening a
	 *  KStudio scene file imports it inside), the outermost names the scene. */
	struct FLoadStage
	{
		int32 Depth = 0;
		FString Scene, Text, Step;
		/** The scene the last steps were for: the build after them shows it (an imported KStudio scene has no file of
		 *  its own until it is saved, so the studio's File is empty then). */
		FString LastScene;
		int32 Done = 0, Total = 0;
		double LastPaint = 0.;
		/** Window paints forced so far in this process (each one is two ForceRedrawWindow calls). */
		int32 Paints = 0;
	};
	FLoadStage& Stage() { static FLoadStage S; return S; }

	/** Paints the game window now: the caller holds the game thread, so Slate would not otherwise. Twice, because the
	 *  window has two buffers and either may be the one shown while the frame is held (as SOKStudioPanel::PaintStatus). */
	void PaintNow(bool bForce)
	{
		FLoadStage& S = Stage();
		const double Now = FPlatformTime::Seconds();
		// OK_STUDIO_STAGE_PAINT=0: never paint here (the steps are still recorded and reported, studio_state "loading"
		// included); for A/B of what these paints cost a load.
		static const bool bPaint = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_STUDIO_STAGE_PAINT")) != TEXT("0");
		if (!bPaint) return;
		if (!bForce && Now - S.LastPaint < 0.2) return;
		if (!IsInGameThread() || !FSlateApplication::IsInitialized() || !UOKStudioGame::Get() || !GEngine || !GEngine->GameViewport) return;
		const TSharedPtr<SWindow> Window = GEngine->GameViewport->GetWindow();
		if (!Window.IsValid()) return;
		S.LastPaint = Now;
		++S.Paints;
		FSlateApplication::Get().ForceRedrawWindow(Window.ToSharedRef());
		FSlateApplication::Get().ForceRedrawWindow(Window.ToSharedRef());
		// OK_STUDIO_STAGE_SHOT=<folder>: a picture of the window at each new step, for checking what the user sees while
		// the game thread is held (no frame runs then, so the profile's frame-based screenshots cannot take one).
		static const FString ShotDir = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_STUDIO_STAGE_SHOT"));
		if (bForce && !ShotDir.IsEmpty())
		{
			static int32 Shot = 0;
			TArray<FColor> Pixels;
			FIntVector Size;
			if (FSlateApplication::Get().TakeScreenshot(Window.ToSharedRef(), Pixels, Size) && Size.X > 0 && Size.Y > 0)
			{
				for (FColor& C : Pixels) C.A = 255;
				TArray64<uint8> Png;
				FImageUtils::PNGCompressImageArray(Size.X, Size.Y, TArrayView64<const FColor>(Pixels.GetData(), Pixels.Num()), Png);
				FFileHelper::SaveArrayToFile(Png, *(ShotDir / FString::Printf(TEXT("stage_%02d.png"), ++Shot)));
			}
		}
	}
}

void SOKStudioLoadOverlay::BeginStage(const FString& SceneName)
{
	FLoadStage& S = Stage();
	if (S.Depth++ == 0) { S.Scene = SceneName; S.Step = TEXT("load.waiting"); S.Text = OKStudioT(TEXT("load.waiting")); S.Done = S.Total = 0; PaintNow(true); }
}

void SOKStudioLoadOverlay::SetStage(const TCHAR* Step, const FString& Text, int32 Done, int32 Total)
{
	FLoadStage& S = Stage();
	if (S.Depth <= 0) return;
	const bool bNewStep = S.Step != Step;
	S.Step = Step;
	S.Text = Text;
	S.Done = Done;
	S.Total = Total;
	PaintNow(bNewStep);
}

int32 SOKStudioLoadOverlay::StagePaints() { return Stage().Paints; }

void SOKStudioLoadOverlay::EndStage()
{
	FLoadStage& S = Stage();
	if (S.Depth > 0 && --S.Depth == 0) { S.Text.Reset(); S.LastScene = MoveTemp(S.Scene); S.Scene.Reset(); }
}

TSharedRef<FJsonObject> SOKStudioLoadOverlay::StateJson(const UOKStudioGame* InGame)
{
	TSharedRef<FJsonObject> O = MakeShared<FJsonObject>();
	const FLoadStage& S = Stage();
	int32 Built = 0, Total = 0;
	const bool bBuilding = Progress(InGame, Built, Total);
	O->SetBoolField(TEXT("shown"), S.Depth > 0 || bBuilding);
	if (S.Depth > 0)
	{
		O->SetStringField(TEXT("scene"), S.Scene);
		O->SetStringField(TEXT("step"), S.Step);
		O->SetStringField(TEXT("text"), S.Text);
		O->SetNumberField(TEXT("done"), S.Done);
		O->SetNumberField(TEXT("total"), S.Total);
	}
	else if (bBuilding)
	{
		O->SetStringField(TEXT("scene"), InGame && !InGame->File.IsEmpty() ? FPaths::GetBaseFilename(InGame->File) : S.LastScene);
		O->SetStringField(TEXT("step"), TEXT("build"));
		O->SetStringField(TEXT("text"), Built == 0 ? OKStudioT(TEXT("load.waiting"))
			: OKStudioMsg(TEXT("load.progress"), {{TEXT("built"), Built}, {TEXT("total"), Total}}));
		O->SetNumberField(TEXT("done"), Built);
		O->SetNumberField(TEXT("total"), Total);
	}
	return O;
}

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
	// The box sits over the whole view (ZOrder 30): it never takes the mouse itself, or every click and hover over the
	// panels and the view below it stops here (U279 found G / R / S never saw the view under it).
	SetVisibility(EVisibility::SelfHitTestInvisible);
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
	return Stage().Depth > 0 || Progress(Game.Get(), Built, Total) ? EVisibility::HitTestInvisible : EVisibility::Collapsed;
}

FText SOKStudioLoadOverlay::SceneName() const
{
	if (Stage().Depth > 0) return FText::FromString(Stage().Scene);
	const UOKStudioGame* G = Game.Get();
	return FText::FromString(G && !G->File.IsEmpty() ? FPaths::GetBaseFilename(G->File) : Stage().LastScene);
}

FText SOKStudioLoadOverlay::ProgressText() const
{
	if (Stage().Depth > 0) return FText::FromString(Stage().Text);
	int32 Built, Total;
	if (!Progress(Game.Get(), Built, Total)) return FText::GetEmpty();
	if (Built == 0) return FText::FromString(OKStudioT(TEXT("load.waiting")));
	return FText::FromString(OKStudioMsg(TEXT("load.progress"), {{TEXT("built"), Built}, {TEXT("total"), Total}}));
}

FText SOKStudioLoadOverlay::PercentText() const
{
	// Before the build there is no share of the whole to give: the steps differ too much in length.
	if (Stage().Depth > 0) return FText::GetEmpty();
	int32 Built, Total;
	if (!Progress(Game.Get(), Built, Total) || Total <= 0) return FText::GetEmpty();
	return FText::FromString(OKStudioMsg(TEXT("load.percent"), {{TEXT("percent"), int32(100.0 * Built / Total)}}));
}

TOptional<float> SOKStudioLoadOverlay::Fraction() const
{
	// A step that counts (cards converted, objects read) fills the bar for that step.
	if (Stage().Depth > 0) return Stage().Total > 0 ? float(Stage().Done) / float(Stage().Total) : 0.f;
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
