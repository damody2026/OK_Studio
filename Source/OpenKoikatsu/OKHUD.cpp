#include "OKHUD.h"
#include "OKGalleryWidget.h"
#include "KKPreviewActor.h"
#include "Blueprint/UserWidget.h"
#include "Camera/PlayerCameraManager.h"
#include "Components/SizeBox.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "UnrealClient.h"

void AOKHUD::BeginPlay()
{
	Super::BeginPlay();
	FString Manifest;
	if(FParse::Value(FCommandLine::Get(),TEXT("StreetSocialManifest="),Manifest)||FParse::Value(FCommandLine::Get(),TEXT("CrowdRuntimeScene="),Manifest))return;
	APlayerController* PC = GetOwningPlayerController();
	if (!PC)
	{
		return;
	}
	Gallery = CreateWidget<UOKGalleryWidget>(PC, UOKGalleryWidget::StaticClass());
	if (Gallery)
	{
		Gallery->AddToViewport(100);
	}
}

void AOKHUD::SetGalleryVisible(bool bVisible)
{
	if (Gallery)
	{
		Gallery->SetVisibility(bVisible ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	}
	bShowHUD = bVisible;
}

void AOKHUD::DrawHUD()
{
	Super::DrawHUD();
	// The card reader's camera follows a character's style, so a ruler beside the character shows the height: real centimetres
	// from the ground in the character's plane, drawn here to stay out of the card captures.
	APlayerController* PC = GetOwningPlayerController();
	// A screenshot without the UI is the character alone: the character MCP's images are measured.
	if (FScreenshotRequest::IsScreenshotRequested() && !FScreenshotRequest::ShouldShowUI()) return;
	if (!Canvas || !Gallery || !PC || !PC->PlayerCameraManager || !Gallery->bModelLayout || Gallery->bOkStudioOpen || Gallery->InteractionWidget || Gallery->InteractionScene) return;
	const AKKPreviewActor* Actor = Gallery->PreviewActor;
	if (!IsValid(Actor) || !Actor->Session.IsOpen()) return;
	const FVector Ground = Gallery->StyledActor == Actor ? Gallery->StyledActorLocation : Actor->GetActorLocation();
	const FVector Side = FRotationMatrix(FRotator(0.f, PC->PlayerCameraManager->GetCameraRotation().Yaw, 0.f)).GetUnitAxis(EAxis::Y);
	const FVector Foot = Ground + Side * (72.f * Actor->GetActorScale3D().Z);
	// Slate draws over the HUD: the ruler stays left of the right panel, its marks and numbers going left from there.
	float Right = Canvas->ClipX;
	const FGeometry& Root = Gallery->GetCachedGeometry();
	if (Gallery->MotionPanel && Gallery->MotionPanel->IsVisible() && Root.GetLocalSize().X > 0.f)
		Right *= Root.AbsoluteToLocal(Gallery->MotionPanel->GetCachedGeometry().GetAbsolutePosition()).X / Root.GetLocalSize().X;
	const FLinearColor Colour(1.f, .93f, .6f);
	UFont* Font = GEngine->GetMediumFont();
	const float X = FMath::Min(Canvas->Project(Foot).X, Right - 12.f);
	float LastY = 0.f;
	for (int32 Height = 0; Height <= 300; Height += 10)
	{
		const FVector At = Canvas->Project(Foot + FVector(0.f, 0.f, Height));
		if (At.Z <= 0.f) return;	// behind the camera
		const bool bMajor = Height % 50 == 0;
		DrawLine(X - (bMajor ? 18.f : 9.f), At.Y, X, At.Y, Colour, bMajor ? 2.f : 1.f);
		if (bMajor) DrawText(FString::Printf(TEXT("%d cm"), Height), Colour, X - 76.f, At.Y - 9.f, Font);
		if (Height > 0) DrawLine(X, LastY, X, At.Y, Colour, 2.f);
		LastY = At.Y;
	}
}
