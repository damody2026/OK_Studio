#include "CityImmersionWalker.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "InputCoreTypes.h"
#include "Camera/PlayerCameraManager.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Components/PlanarReflectionComponent.h"
#include "Engine/PlanarReflection.h"
#include "EngineUtils.h"
#include "HAL/IConsoleManager.h"

void ACityImmersionWalker::CityImmersionCapturePose(float X, float Y, float Z, float Pitch, float Yaw)
{
    if (!FParse::Param(FCommandLine::Get(), TEXT("CityImmersionCapture"))) return;
    if (auto* PC = Cast<APlayerController>(GetController()))
    {
        // Fixed documentation pose only. Normal movement and soak never use it.
        GetCharacterMovement()->StopMovementImmediately();
        GetCharacterMovement()->SetMovementMode(MOVE_Flying);
        SetActorEnableCollision(false);
        SetActorRotation(FRotator(0, Yaw, 0), ETeleportType::TeleportPhysics);
        SetActorLocation(FVector(X, Y, Z - 77.), false, nullptr, ETeleportType::TeleportPhysics);
        if (PC->PlayerCameraManager)
        {
            PC->PlayerCameraManager->ViewPitchMin = -90.f;
            PC->PlayerCameraManager->ViewPitchMax = 90.f;
        }
        PC->SetControlRotation(FRotator(Pitch, Yaw, 0));
        UE_LOG(LogTemp, Log, TEXT("CITY_IMMERSION_CAPTURE_POSE %.6f %.6f %.6f %.6f %.6f"), X, Y, Z, Pitch, Yaw);
    }
}

void ACityImmersionWalker::CityImmersionViewPoint(const FString& ViewId)
{
    if (!FParse::Param(FCommandLine::Get(), TEXT("CityImmersionCapture"))) return;
    if (auto* PC = Cast<APlayerController>(GetController()))
    {
        FVector Eye; FRotator Rotation; PC->GetPlayerViewPoint(Eye, Rotation);
        const float Fov = PC->PlayerCameraManager ? PC->PlayerCameraManager->GetFOVAngle() : -1.f;
        UE_LOG(LogTemp, Log, TEXT("CITY_IMMERSION_CAPTURE %s eye=%.6f,%.6f,%.6f rot=%.6f,%.6f,%.6f fov=%.4f"), *ViewId, Eye.X, Eye.Y, Eye.Z, Rotation.Pitch, Rotation.Yaw, Rotation.Roll, Fov);
        int32 ActiveMirrors = 0, ActiveCapturePercent = 0;
        float ActivePrefilter = 0.f;
        for (auto& Weak : LocalMirrors) if (auto* Reflection = Weak.Get()) if (Reflection->IsVisible())
        {
            ActiveCapturePercent = ActiveMirrors ? FMath::Min(ActiveCapturePercent, Reflection->ScreenPercentage) : Reflection->ScreenPercentage;
            ActivePrefilter = FMath::Max(ActivePrefilter, Reflection->PrefilterRoughness);
            ++ActiveMirrors;
        }
        UE_LOG(LogTemp, Log, TEXT("CITY_IMMERSION_MIRRORS %s configured=%d active=%d capture_percent=%d prefilter=%.3f"), *ViewId, LocalMirrors.Num(), ActiveMirrors, ActiveCapturePercent, ActivePrefilter);
        const auto* Clip = IConsoleManager::Get().FindConsoleVariable(TEXT("r.AllowGlobalClipPlane"));
        const auto* Method = IConsoleManager::Get().FindConsoleVariable(TEXT("r.ReflectionMethod"));
        UE_LOG(LogTemp, Log, TEXT("CITY_IMMERSION_RENDERER clip=%d reflections=%d"), Clip ? Clip->GetInt() : -1, Method ? Method->GetInt() : -1);
    }
}

ACityImmersionWalker::ACityImmersionWalker()
{
    PrimaryActorTick.bCanEverTick = true;
    GetCapsuleComponent()->InitCapsuleSize(35.f, 88.f);
    auto* Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("WalkingCamera"));
    Camera->SetupAttachment(GetCapsuleComponent());
    Camera->SetRelativeLocation(FVector(0, 0, 77));
    Camera->bUsePawnControlRotation = true;
    bUseControllerRotationYaw = true;
    bUseControllerRotationPitch = false;
    bUseControllerRotationRoll = false;
    auto* Movement = GetCharacterMovement();
    Movement->MaxWalkSpeed = 180.f;
    Movement->MaxFlySpeed = 600.f;
    Movement->MaxAcceleration = 2048.f;
    Movement->BrakingDecelerationWalking = 2048.f;
    Movement->BrakingDecelerationFlying = 2048.f;
    Movement->MaxStepHeight = 22.f;
    Movement->SetWalkableFloorAngle(45.f);
    Movement->bUseFlatBaseForFloorChecks = true;
    Movement->JumpZVelocity = 350.f;
}

void ACityImmersionWalker::PossessedBy(AController* NewController)
{
    Super::PossessedBy(NewController);
    if (auto* PC = Cast<APlayerController>(NewController))
    {
        PC->bShowMouseCursor = false;
        PC->SetInputMode(FInputModeGameOnly());
    }
}

void ACityImmersionWalker::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    auto* PC = Cast<APlayerController>(GetController());
    if (!PC || !PC->IsLocalController()) return;
    if (!bMirrorsCached)
    {
        for (TActorIterator<APlanarReflection> It(GetWorld()); It; ++It)
            if (It->ActorHasTag(TEXT("ImmersionLargeMirror")))
                if (auto* Reflection = It->FindComponentByClass<UPlanarReflectionComponent>())
                {
                    // Clear indoor mirrors; the nearby two-mirror limit bounds cost.
                    Reflection->ScreenPercentage = 75;
                    Reflection->PrefilterRoughness = 0.f;
                    Reflection->MarkRenderStateDirty();
                    LocalMirrors.Add(Reflection);
                }
        bMirrorsCached = true;
    }
    MirrorRefreshSeconds -= DeltaSeconds;
    if (MirrorRefreshSeconds <= 0.f)
    {
        MirrorRefreshSeconds = .2f;
        FVector Eye; FRotator View; PC->GetPlayerViewPoint(Eye, View);
        TArray<TPair<float, UPlanarReflectionComponent*>> Nearby;
        for (auto& Weak : LocalMirrors) if (auto* Reflection = Weak.Get())
        {
            const FVector Offset = Eye - Reflection->GetComponentLocation();
            const bool bSameFloor = FMath::Abs(Offset.Z) < 300.f;
            const bool bInFront = FVector::DotProduct(Offset, Reflection->GetUpVector()) > 2.f;
            if (bSameFloor && bInFront && Offset.SizeSquared() < FMath::Square(2200.f)) Nearby.Emplace(Offset.SizeSquared(), Reflection);
        }
        Nearby.Sort([](const auto& A, const auto& B) { return A.Key < B.Key; });
        for (auto& Weak : LocalMirrors) if (auto* Reflection = Weak.Get())
        {
            const bool bActive = (Nearby.Num() > 0 && Nearby[0].Value == Reflection) || (Nearby.Num() > 1 && Nearby[1].Value == Reflection);
            if (Reflection->IsVisible() != bActive) Reflection->SetVisibility(bActive);
        }
    }
    if (bAuditControlled) return;
    auto* Movement = GetCharacterMovement();
    if (PC->bShowMouseCursor || PC->IsMoveInputIgnored())
    {
        Movement->StopMovementImmediately();
        return;
    }
    if (PC->WasInputKeyJustPressed(EKeys::F7))
    {
        bTourFlight = !bTourFlight;
        Movement->StopMovementImmediately();
        Movement->SetMovementMode(bTourFlight ? MOVE_Flying : MOVE_Falling);
    }
    const bool bFast = PC->IsInputKeyDown(EKeys::LeftShift) || PC->IsInputKeyDown(EKeys::RightShift);
    Movement->MaxWalkSpeed = bFast ? 380.f : 180.f;
    Movement->MaxFlySpeed = bFast ? 1200.f : 600.f;
    float X = 0.f, Y = 0.f;
    PC->GetInputMouseDelta(X, Y);
    AddControllerYawInput(X * .08f);
    AddControllerPitchInput(-Y * .08f);
    const FRotator Heading(0, PC->GetControlRotation().Yaw, 0);
    const float Forward = float(PC->IsInputKeyDown(EKeys::W) || PC->IsInputKeyDown(EKeys::Up)) - float(PC->IsInputKeyDown(EKeys::S) || PC->IsInputKeyDown(EKeys::Down));
    const float Right = float(PC->IsInputKeyDown(EKeys::D) || PC->IsInputKeyDown(EKeys::Right)) - float(PC->IsInputKeyDown(EKeys::A) || PC->IsInputKeyDown(EKeys::Left));
    FVector Direction = Heading.Vector() * Forward + FRotationMatrix(Heading).GetUnitAxis(EAxis::Y) * Right;
    if (bTourFlight)
    {
        Direction.Z = float(PC->IsInputKeyDown(EKeys::E) || PC->IsInputKeyDown(EKeys::SpaceBar)) - float(PC->IsInputKeyDown(EKeys::Q) || PC->IsInputKeyDown(EKeys::LeftControl));
    }
    else
    {
        if (PC->WasInputKeyJustPressed(EKeys::SpaceBar)) Jump();
        if (!PC->IsInputKeyDown(EKeys::SpaceBar)) StopJumping();
    }
    AddMovementInput(Direction.GetClampedToMaxSize(1.f));
}

ACityImmersionGameMode::ACityImmersionGameMode()
{
    DefaultPawnClass = ACityImmersionWalker::StaticClass();
    PlayerControllerClass = APlayerController::StaticClass();
}
