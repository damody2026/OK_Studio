#include "CityEnvironmentController.h"

#include "CityEnvironmentClockSubsystem.h"
#include "CityEnvironmentLog.h"
#include "CityEnvironmentSaveGame.h"
#include "CityEnvironmentTimeWidget.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/InputComponent.h"
#include "Components/LightComponent.h"
#include "Components/LocalLightComponent.h"
#include "Components/PostProcessComponent.h"
#include "Components/PrimitiveComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/GameInstance.h"
#include "Engine/Texture2D.h"
#include "Engine/TextureCube.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerController.h"
#include "InputCoreTypes.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialParameterCollection.h"
#include "Materials/MaterialParameterCollectionInstance.h"
#include "Misc/App.h"
#include "TextureResource.h"
#include "UObject/ObjectSaveContext.h"

namespace
{
	enum class ECityLightKind : uint8
	{
		Sun = 1,
		Fill = 2,
		Sky = 3,
		Moon = 4,
		Bounce = 5,
		Local = 6
	};

	enum class ECityLampGroup : uint8
	{
		Path = 0,
		Feature = 1,
		Market = 2,
		Sport = 3,
		Camp = 4
	};

	enum class ECityMeshRole : uint8
	{
		Disc = 0,
		Halo = 1,
		NightSky = 2
	};

	const TCHAR* CollectionPath = TEXT("/Game/UniversityCity/EnvironmentV1/MPC_CityEnvironment.MPC_CityEnvironment");
	const TCHAR* SpherePath = TEXT("/Engine/BasicShapes/Sphere.Sphere");

	bool EqualsOrPrefixed(const FString& Name, const TCHAR* BindingRole)
	{
		if (Name.Equals(BindingRole, ESearchCase::IgnoreCase))
		{
			return true;
		}
		return Name.StartsWith(FString(BindingRole) + TEXT("_"), ESearchCase::IgnoreCase);
	}

	bool AnyName(const TArray<FString, TInlineAllocator<4>>& Names, TFunctionRef<bool(const FString&)> Test)
	{
		for (const FString& Name : Names)
		{
			if (Test(Name))
			{
				return true;
			}
		}
		return false;
	}

	bool HasTag(const TArray<FString, TInlineAllocator<8>>& ActorTags, const TCHAR* Tag)
	{
		for (const FString& Item : ActorTags)
		{
			if (Item.Equals(Tag, ESearchCase::IgnoreCase))
			{
				return true;
			}
		}
		return false;
	}

	bool IsIndoorTag(const TArray<FString, TInlineAllocator<8>>& ActorTags)
	{
		return HasTag(ActorTags, TEXT("Indoor")) || HasTag(ActorTags, TEXT("EnvIndoor")) || HasTag(ActorTags, TEXT("EnvGroup=Indoor"));
	}

	bool ParseGroup(const TArray<FString, TInlineAllocator<8>>& ActorTags, ECityLampGroup& OutGroup)
	{
		for (const FString& Tag : ActorTags)
		{
			if (!Tag.StartsWith(TEXT("EnvGroup="), ESearchCase::IgnoreCase))
			{
				continue;
			}
			const FString Value = Tag.Mid(9);
			if (Value.Equals(TEXT("Path"), ESearchCase::IgnoreCase)) { OutGroup = ECityLampGroup::Path; return true; }
			if (Value.Equals(TEXT("Feature"), ESearchCase::IgnoreCase)) { OutGroup = ECityLampGroup::Feature; return true; }
			if (Value.Equals(TEXT("Market"), ESearchCase::IgnoreCase)) { OutGroup = ECityLampGroup::Market; return true; }
			if (Value.Equals(TEXT("Sport"), ESearchCase::IgnoreCase)) { OutGroup = ECityLampGroup::Sport; return true; }
			if (Value.Equals(TEXT("Camp"), ESearchCase::IgnoreCase)) { OutGroup = ECityLampGroup::Camp; return true; }
		}
		return false;
	}

	bool ParseLumens(const TArray<FString, TInlineAllocator<8>>& ActorTags, float& OutLumens)
	{
		for (const FString& Tag : ActorTags)
		{
			if (!Tag.StartsWith(TEXT("EnvLumens="), ESearchCase::IgnoreCase))
			{
				continue;
			}
			const double Value = FCString::Atod(*Tag.Mid(10));
			if (FMath::IsFinite(Value) && Value >= 0.0)
			{
				OutLumens = static_cast<float>(Value);
				return true;
			}
		}
		return false;
	}

	void CollectNames(const AActor* Actor, const UActorComponent* Component, TArray<FString, TInlineAllocator<4>>& Out)
	{
		if (Actor)
		{
			Out.Add(Actor->GetName());
			Out.Add(Actor->GetActorNameOrLabel());
			// Editor labels are stripped from cooked actors. Persist semantic roles
			// as tags so the same registry works in Editor, PIE and Shipping.
			for (const FName Tag : Actor->Tags)
			{
				const FString Value = Tag.ToString();
				if (Value.StartsWith(TEXT("EnvRole="))) Out.Add(Value.Mid(8));
			}
		}
		if (Component)
		{
			Out.Add(Component->GetName());
		}
	}

	void CollectTags(const AActor* Actor, const UActorComponent* Component, TArray<FString, TInlineAllocator<8>>& Out)
	{
		if (Actor)
		{
			for (const FName& Tag : Actor->Tags)
			{
				Out.Add(Tag.ToString());
			}
		}
		if (Component)
		{
			for (const FName& Tag : Component->ComponentTags)
			{
				Out.Add(Tag.ToString());
			}
		}
	}

	bool HasScalar(const UMaterialInterface* Material, const TCHAR* Name)
	{
		if (!Material)
		{
			return false;
		}
		float Unused = 0.0f;
		return Material->GetScalarParameterValue(FHashedMaterialParameterInfo(FName(Name)), Unused);
	}

	FVector SlerpDirection(const FVector& From, const FVector& To, float Alpha)
	{
		const FVector A = From.GetSafeNormal();
		const FVector B = To.GetSafeNormal();
		const double Dot = FMath::Clamp(static_cast<double>(FVector::DotProduct(A, B)), -1.0, 1.0);
		const double Omega = FMath::Acos(Dot);
		if (Omega < 1.0e-4)
		{
			return B;
		}
		const double SinOmega = FMath::Sin(Omega);
		const float T = FMath::Clamp(Alpha, 0.0f, 1.0f);
		const double W0 = FMath::Sin((1.0 - T) * Omega) / SinOmega;
		const double W1 = FMath::Sin(static_cast<double>(T) * Omega) / SinOmega;
		return (A * W0 + B * W1).GetSafeNormal();
	}

	FVector BrightLimb(const FVector& SunDirection, const FVector& MoonDirection)
	{
		const double Dot = FMath::Clamp(static_cast<double>(FVector::DotProduct(SunDirection, MoonDirection)), -1.0, 1.0);
		FVector Bright = SunDirection - MoonDirection * static_cast<float>(Dot);
		if (!Bright.Normalize())
		{
			return SunDirection.GetSafeNormal();
		}
		return Bright;
	}

	void AimLight(ULightComponentBase* Light, const FVector& TowardBody)
	{
		if (!Light)
		{
			return;
		}
		const FVector Rays = (-TowardBody).GetSafeNormal();
		if (Rays.IsNearlyZero())
		{
			return;
		}
		Light->SetMobility(EComponentMobility::Movable);
		// The visual celestial spheres continue to interpolate every frame.
		// Shadow emitters need not invalidate VSM caches for imperceptible
		// fractions of a degree, especially under a broad moon penumbra.
		const auto Directional = Cast<UDirectionalLightComponent>(Light);
		const double Tolerance = Directional && Directional->LightSourceAngle >= 5.f ? 0.05 : 0.015;
		if (FVector::DotProduct(Light->GetForwardVector(), Rays) > FMath::Cos(FMath::DegreesToRadians(Tolerance))) return;
		Light->SetWorldRotation(FRotationMatrix::MakeFromX(Rays).Rotator());
	}

	void WriteIntensity(ULightComponentBase* Base, float Intensity)
	{
		if (!Base || !FMath::IsFinite(Intensity))
		{
			return;
		}
		if (USkyLightComponent* Sky = Cast<USkyLightComponent>(Base))
		{
			Sky->SetIntensity(FMath::Max(0.0f, Intensity));
			return;
		}
		if (ULightComponent* Light = Cast<ULightComponent>(Base))
		{
			Light->SetIntensity(FMath::Max(0.0f, Intensity));
		}
	}

	double ScheduleFor(ECityLampGroup Group, const FCityEnvironmentSample& Sample)
	{
		switch (Group)
		{
		case ECityLampGroup::Feature: return Sample.FeatureSchedule;
		case ECityLampGroup::Market: return Sample.MarketSchedule;
		case ECityLampGroup::Sport: return Sample.SportSchedule;
		case ECityLampGroup::Camp: return Sample.CampSchedule;
		default: return Sample.PathSchedule;
		}
	}
}

ACityEnvironmentController::ACityEnvironmentController()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;
	PrimaryActorTick.bTickEvenWhenPaused = true;
	bBlockInput = false;
	LocalDateTime = FDateTime(2026, 10, 22, 12, 0, 0);
	Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	SetRootComponent(Root);
	Exposure = CreateDefaultSubobject<UPostProcessComponent>(TEXT("CityEnvironmentExposure"));
	if (Exposure)
	{
		Exposure->SetupAttachment(Root);
		Exposure->bUnbound = true;
		Exposure->Priority = 100.0f;
		Exposure->BlendWeight = 0.0f;
		Exposure->bEnabled = false;
	}
}

bool ACityEnvironmentController::ShouldTickIfViewportsOnly() const
{
	return true;
}

void ACityEnvironmentController::PreSave(FObjectPreSaveContext SaveContext)
{
	const bool bResumePreview = IsActorTickEnabled();
	if (GetWorld() && !GetWorld()->IsGameWorld())
	{
		PrepareForSave();
		if (bResumePreview && !SaveContext.IsCooking())
		{
			TWeakObjectPtr<ACityEnvironmentController> WeakThis(this);
			FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([WeakThis](float)
			{
				if (!WeakThis.IsValid()) return false;
				if (GIsSavingPackage) return true;
				WeakThis->InitializeBindings();
				return false;
			}));
		}
	}
	Super::PreSave(SaveContext);
}

void ACityEnvironmentController::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	if (!HasAnyFlags(RF_ClassDefaultObject))
	{
		EnsureInitialClock();
	}
}

void ACityEnvironmentController::PostLoad()
{
	Super::PostLoad();
#if WITH_EDITOR
	// Persisted maps intentionally contain no transient preview MIDs/metering
	// texture. Recreate the preview after an interactive editor finishes load.
	if (!IsTemplate() && !FApp::IsUnattended() && !IsRunningCommandlet())
	{
		const TWeakObjectPtr<ACityEnvironmentController> Weak(this);
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak](float)
		{
			if (Weak.IsValid() && Weak->GetWorld() && Weak->GetWorld()->WorldType == EWorldType::Editor) Weak->InitializeBindings();
			return false;
		}), .1f);
	}
#endif
}

void ACityEnvironmentController::BeginPlay()
{
	Super::BeginPlay();
	SetActorTickEnabled(true);
	EnsureInitialClock();
	InitializeBindings();
	UCityEnvironmentClockSubsystem* PlaybackClock = ResolveClock();
	const bool bNewClock = bAuthority && (PlaybackClock ? PlaybackClock->ConsumeInitialPlayback() : true);
	if (bNewClock && bPlaybackOnBeginPlay)
	{
		SetPaused(false);
	}
	if (bAuthority)
	{
		EnsureWidget();
		BindTimeKey();
	}
}

void ACityEnvironmentController::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	ReleaseWidget();
	ReleaseInput();
	UWorld* World = GetWorld();
	const bool bExplicitRemoval = EndPlayReason == EEndPlayReason::Destroyed && World && !World->bIsTearingDown;
	if (bExplicitRemoval && bAuthority && bDidMutate)
	{
		RestoreOwnedState();
		TArray<ACityEnvironmentController*, TInlineAllocator<4>> Others;
		for (TActorIterator<ACityEnvironmentController> It(World); It; ++It)
		{
			if (*It != this && IsValid(*It) && !It->IsActorBeingDestroyed())
			{
				Others.Add(*It);
			}
		}
		for (ACityEnvironmentController* Other : Others)
		{
			if (Other)
			{
				Other->InitializeBindings();
			}
		}
	}
	if (MeterMask)
	{
		MeterMask->RemoveFromRoot();
	}
	Super::EndPlay(EndPlayReason);
}

void ACityEnvironmentController::Tick(float DeltaSeconds)
{
	(void)DeltaSeconds;
	if (!bBindingsReady)
	{
		InitializeBindings();
	}
	else
	{
		MirrorClock();
		AdvanceEditorClock();
		SampleAndApply(false);
	}
	if (bAuthority)
	{
		BindTimeKey();
		if (ShowTimeControls)
		{
			EnsureWidget();
		}
		if (TimeWidget)
		{
			TimeWidget->SyncFromController();
		}
		UpdateTimeInputMode();
	}
}

void ACityEnvironmentController::InitializeBindings()
{
	SetActorTickEnabled(true);
	EnsureInitialClock();
	ClaimAuthority();
	if (bAuthority)
	{
		RefreshRegistry();
	}
	bBindingsReady = true;
	bSeek = true;
	SampleAndApply(true);
}

void ACityEnvironmentController::RefreshBindings()
{
	bBindingsReady = false;
	InitializeBindings();
}

void ACityEnvironmentController::PrepareForSave()
{
	// A map must retain asset references, never preview-only dynamic instances
	// or a transient metering texture. BeginPlay rebuilds these in the game.
	SetActorTickEnabled(false);
	for (const FManagedSign& Sign : Signs)
	{
		if (UPrimitiveComponent* Component = Sign.Component.Get())
			if (UMaterialInterface* Original = Sign.Original.Get())
				Component->SetMaterial(Sign.MaterialIndex, Original);
	}
	for (const FManagedMesh& Mesh : Meshes)
	{
		if (UPrimitiveComponent* Component = Mesh.Component.Get())
			for (int32 Index = 0; Index < Mesh.OriginalMaterials.Num(); ++Index)
				if (UMaterialInterface* Original = Mesh.OriginalMaterials[Index].Get())
					Component->SetMaterial(Index, Original);
	}
	if (Exposure)
	{
		Exposure->Settings.AutoExposureMeterMask = nullptr;
		Exposure->Settings.bOverride_AutoExposureMeterMask = false;
	}
}

void ACityEnvironmentController::DeactivateAndRestore()
{
	SetActorTickEnabled(false);
	RestoreOwnedState();
	bAuthority = false;
	bBindingsReady = false;
	if (Exposure) Exposure->bEnabled = false;
}

void ACityEnvironmentController::ApplyEnvironment()
{
	if (!bBindingsReady)
	{
		InitializeBindings();
		return;
	}
	bSeek = true;
	SkyAccumulator = static_cast<float>(FMath::Max(0.1, SkyRecaptureSeconds));
	SampleAndApply(true);
}

void ACityEnvironmentController::SetHour(double Hour)
{
	LocalDateTime = FCityEnvironmentCelestial::SetHourOnDate(LocalDateTime, Hour);
	if (UCityEnvironmentClockSubsystem* Clock = ResolveClock())
	{
		Clock->SetLocalDateTime(LocalDateTime);
	}
	NoteMirrored();
	bSeek = true;
	ApplyEnvironment();
}

void ACityEnvironmentController::SetDateTime(FDateTime InLocalDateTime)
{
	LocalDateTime = InLocalDateTime;
	if (UCityEnvironmentClockSubsystem* Clock = ResolveClock())
	{
		Clock->SetLocalDateTime(LocalDateTime);
	}
	NoteMirrored();
	bSeek = true;
	ApplyEnvironment();
}

void ACityEnvironmentController::SetTimeScale(double InTimeScale)
{
	TimeScale = FMath::IsFinite(InTimeScale) ? InTimeScale : 1.0;
	if (UCityEnvironmentClockSubsystem* Clock = ResolveClock())
	{
		Clock->SetTimeScale(TimeScale);
	}
	NoteMirrored();
	if (TimeWidget)
	{
		TimeWidget->SyncFromController();
	}
}

void ACityEnvironmentController::SetPaused(bool bInPaused)
{
	Paused = bInPaused;
	if (UCityEnvironmentClockSubsystem* Clock = ResolveClock())
	{
		Clock->SetPaused(Paused);
	}
	NoteMirrored();
	if (TimeWidget)
	{
		TimeWidget->SyncFromController();
	}
}

void ACityEnvironmentController::SaveClock()
{
	EnsureInitialClock();
	if (UCityEnvironmentClockSubsystem* Clock = ResolveClock())
	{
		Clock->SetLocalDateTime(LocalDateTime);
		Clock->SetTimeScale(TimeScale);
		Clock->SetMinutesPerDay(MinutesPerDay);
		Clock->SetPaused(Paused);
		Clock->SaveClock(MakeGeo());
		return;
	}
	UCityEnvironmentSaveGame::SaveSlot(LocalDateTime, MakeGeo(), MinutesPerDay, TimeScale, Paused);
}

void ACityEnvironmentController::LoadClock()
{
	FCityEnvironmentGeo Geo = MakeGeo();
	if (UCityEnvironmentClockSubsystem* Clock = ResolveClock())
	{
		if (!Clock->LoadClock(&Geo))
		{
			return;
		}
		LocalDateTime = Clock->GetLocalDateTime();
		TimeScale = Clock->GetTimeScale();
		MinutesPerDay = Clock->GetMinutesPerDay();
		Paused = Clock->IsPaused();
	}
	else
	{
		double LoadedMinutes = MinutesPerDay;
		double LoadedScale = TimeScale;
		bool bLoadedPaused = Paused;
		FDateTime Loaded;
		if (!UCityEnvironmentSaveGame::LoadSlot(Loaded, Geo, LoadedMinutes, LoadedScale, bLoadedPaused))
		{
			return;
		}
		LocalDateTime = Loaded;
		MinutesPerDay = LoadedMinutes;
		TimeScale = LoadedScale;
		Paused = bLoadedPaused;
	}
	Latitude = Geo.Latitude;
	Longitude = Geo.Longitude;
	UTCOffsetHours = Geo.UtcOffsetHours;
	NorthYawDegrees = Geo.NorthYawDegrees;
	bClockReady = true;
	NoteMirrored();
	bSeek = true;
	ApplyEnvironment();
}

FString ACityEnvironmentController::GetStateJson()
{
	const FCityEnvironmentGeo Geo = MakeGeo();
	const FCityEnvironmentSample Sample = FCityEnvironmentCelestial::Evaluate(LocalDateTime, Geo, true);
	return FCityEnvironmentCelestial::BuildStateJson(Sample, Geo, Paused, TimeScale, MinutesPerDay);
}

FString ACityEnvironmentController::RunClockSelfTests()
{
	return FCityEnvironmentCelestial::RunSelfTests();
}

void ACityEnvironmentController::ToggleTimeControls()
{
	ShowTimeControls = !ShowTimeControls;
	if (ShowTimeControls)
	{
		EnsureWidget();
	}
	if (TimeWidget)
	{
		TimeWidget->SetControlsVisible(ShowTimeControls);
	}
	UpdateTimeInputMode();
}

UCityEnvironmentClockSubsystem* ACityEnvironmentController::ResolveClock() const
{
	const UWorld* World = GetWorld();
	const UGameInstance* Instance = World ? World->GetGameInstance() : nullptr;
	return Instance ? Instance->GetSubsystem<UCityEnvironmentClockSubsystem>() : nullptr;
}

FCityEnvironmentGeo ACityEnvironmentController::MakeGeo() const
{
	FCityEnvironmentGeo Geo;
	Geo.Latitude = Latitude;
	Geo.Longitude = Longitude;
	Geo.UtcOffsetHours = UTCOffsetHours;
	Geo.NorthYawDegrees = NorthYawDegrees;
	Geo.Sanitize();
	return Geo;
}

void ACityEnvironmentController::NoteMirrored()
{
	LastMirroredDate = LocalDateTime;
	LastMirroredScale = TimeScale;
	LastMirroredMinutes = MinutesPerDay;
	bLastMirroredPaused = Paused;
}

void ACityEnvironmentController::EnsureInitialClock()
{
	UCityEnvironmentClockSubsystem* Clock = ResolveClock();
	if (Clock)
	{
		if (Clock->IsAwaitingSeed())
		{
			Clock->SeedFullMoon(MakeGeo());
		}
		if (!bClockReady && Clock->HasClock())
		{
			FCityEnvironmentGeo SavedGeo;
			FDateTime SavedTime;
			double SavedMinutes = MinutesPerDay, SavedScale = TimeScale;
			bool bSavedPaused = Paused;
			if (UCityEnvironmentSaveGame::LoadSlot(SavedTime, SavedGeo, SavedMinutes, SavedScale, bSavedPaused))
			{
				Latitude = SavedGeo.Latitude; Longitude = SavedGeo.Longitude;
				UTCOffsetHours = SavedGeo.UtcOffsetHours; NorthYawDegrees = SavedGeo.NorthYawDegrees;
			}
			LocalDateTime = Clock->GetLocalDateTime();
			TimeScale = Clock->GetTimeScale();
			MinutesPerDay = Clock->GetMinutesPerDay();
			Paused = Clock->IsPaused();
			NoteMirrored();
			bClockReady = true;
		}
		return;
	}
	if (bClockReady)
	{
		return;
	}
	FCityEnvironmentGeo LoadedGeo;
	double LoadedMinutes = MinutesPerDay;
	double LoadedScale = TimeScale;
	bool bLoadedPaused = Paused;
	FDateTime Loaded;
	if (UCityEnvironmentSaveGame::LoadSlot(Loaded, LoadedGeo, LoadedMinutes, LoadedScale, bLoadedPaused))
	{
		Latitude = LoadedGeo.Latitude; Longitude = LoadedGeo.Longitude;
		UTCOffsetHours = LoadedGeo.UtcOffsetHours; NorthYawDegrees = LoadedGeo.NorthYawDegrees;
		LocalDateTime = Loaded;
		MinutesPerDay = LoadedMinutes;
		TimeScale = LoadedScale;
		Paused = bLoadedPaused;
	}
	else
	{
		const FCityEnvironmentGeo Site = MakeGeo();
		const FDateTime After(
			static_cast<int32>(FCityEnvironmentCelestial::FullMoonAnchorYear),
			FCityEnvironmentCelestial::FullMoonAnchorMonth,
			FCityEnvironmentCelestial::FullMoonAnchorDay);
		FDateTime Full;
		if (FCityEnvironmentCelestial::NextFullMoonLocal(Site, After, Full) && Full > After)
		{
			LocalDateTime = Full.GetDate() + FTimespan(21,0,0);
		}
		Paused = true;
		UCityEnvironmentSaveGame::SaveSlot(LocalDateTime, Site, MinutesPerDay, TimeScale, true);
		UE_LOG(LogCityEnvironment, Log, TEXT("Initial civil time %s"), *FCityEnvironmentCelestial::ToIso8601(LocalDateTime));
	}
	NoteMirrored();
	bClockReady = true;
}

void ACityEnvironmentController::MirrorClock()
{
	UCityEnvironmentClockSubsystem* Clock = ResolveClock();
	if (!Clock || !Clock->HasClock())
	{
		return;
	}
	if (LocalDateTime != LastMirroredDate)
	{
		Clock->SetLocalDateTime(LocalDateTime);
		bSeek = true;
	}
	else
	{
		LocalDateTime = Clock->GetLocalDateTime();
	}
	if (TimeScale != LastMirroredScale)
	{
		Clock->SetTimeScale(TimeScale);
	}
	else
	{
		TimeScale = Clock->GetTimeScale();
	}
	if (MinutesPerDay != LastMirroredMinutes)
	{
		Clock->SetMinutesPerDay(MinutesPerDay);
	}
	else
	{
		MinutesPerDay = Clock->GetMinutesPerDay();
	}
	if (Paused != bLastMirroredPaused)
	{
		Clock->SetPaused(Paused);
	}
	else
	{
		Paused = Clock->IsPaused();
	}
	NoteMirrored();
}

void ACityEnvironmentController::AdvanceEditorClock()
{
	if (ResolveClock() || !bAuthority || Paused)
	{
		return;
	}
	const double RealDelta = static_cast<double>(FApp::GetDeltaTime());
	if (!FMath::IsFinite(RealDelta) || RealDelta <= 0.0)
	{
		return;
	}
	LocalDateTime = FCityEnvironmentCelestial::AdvanceRealTime(LocalDateTime, RealDelta, MinutesPerDay, TimeScale);
	NoteMirrored();
}

void ACityEnvironmentController::ClaimAuthority()
{
	UWorld* World = GetWorld();
	if (!World)
	{
		bAuthority = true;
		return;
	}
	ACityEnvironmentController* Best = nullptr;
	uint32 BestId = MAX_uint32;
	for (TActorIterator<ACityEnvironmentController> It(World); It; ++It)
	{
		if (!IsValid(*It) || It->IsActorBeingDestroyed())
		{
			continue;
		}
		if (It->GetUniqueID() < BestId)
		{
			Best = *It;
			BestId = It->GetUniqueID();
		}
	}
	for (TActorIterator<ACityEnvironmentController> It(World); It; ++It)
	{
		if (IsValid(*It) && !It->IsActorBeingDestroyed())
		{
			It->SetAuthority(Best == *It);
		}
	}
}

void ACityEnvironmentController::SetAuthority(bool bInAuthority)
{
	bAuthority = bInAuthority;
	if (Exposure)
	{
		Exposure->bEnabled = bAuthority;
		Exposure->BlendWeight = bAuthority ? 1.0f : 0.0f;
		Exposure->bUnbound = true;
		Exposure->Priority = 100.0f;
	}
	if (!bAuthority)
	{
		ReleaseWidget();
		ReleaseInput();
	}
}

void ACityEnvironmentController::RefreshRegistry()
{
	UWorld* World = GetWorld();
	if (!World)
	{
		return;
	}
	UCityEnvironmentClockSubsystem* Clock = ResolveClock();
	TArray<FManagedLight> PreviousLights = MoveTemp(Lights);
	TArray<FManagedSign> PreviousSigns = MoveTemp(Signs);
	TArray<FManagedAtmosphere> PreviousAtmospheres = MoveTemp(Atmospheres);
	TArray<FManagedMesh> PreviousMeshes = MoveTemp(Meshes);
	Lights.Reset();
	Signs.Reset();
	Atmospheres.Reset();
	Meshes.Reset();
	bSunBound = false;
	bMoonBound = false;
	bFillBound = false;
	bSkyBound = false;
	bBounceBound = false;

	auto FindLight = [&PreviousLights](const ULightComponentBase* Component) -> const FManagedLight*
	{
		for (const FManagedLight& Item : PreviousLights)
		{
			if (Item.Component.Get() == Component)
			{
				return &Item;
			}
		}
		return nullptr;
	};
	auto RememberLight = [&](ULightComponentBase* Light, ECityLightKind Kind, ECityLampGroup Group, bool bOverride, float Lumens)
	{
		if (!Light)
		{
			return;
		}
		FManagedLight Managed;
		Managed.Component = Light;
		Managed.Kind = static_cast<uint8>(Kind);
		Managed.Group = static_cast<uint8>(Group);
		Managed.bOverrideLumens = bOverride;
		Managed.TargetLumens = Lumens;
		Managed.bDirectional = Cast<UDirectionalLightComponent>(Light) != nullptr;
		Managed.bSky = Cast<USkyLightComponent>(Light) != nullptr;
		Managed.bLocal = Cast<ULocalLightComponent>(Light) != nullptr;
		if (const FManagedLight* Previous = FindLight(Light))
		{
			Managed.OriginalIntensity = Previous->OriginalIntensity;
			Managed.OriginalColor = Previous->OriginalColor;
			Managed.OriginalTemperature = Previous->OriginalTemperature;
			Managed.bOriginalUseTemperature = Previous->bOriginalUseTemperature;
			Managed.bOriginalCastShadows = Previous->bOriginalCastShadows;
			Managed.OriginalMaxDrawDistance = Previous->OriginalMaxDrawDistance;
			Managed.OriginalFadeRange = Previous->OriginalFadeRange;
			Managed.OriginalUnits = Previous->OriginalUnits;
			Managed.bHasUnits = Previous->bHasUnits;
			Managed.OriginalAtmosphereIndex = Previous->OriginalAtmosphereIndex;
			Managed.OriginalDiskScale = Previous->OriginalDiskScale;
			Managed.OriginalSourceAngle = Previous->OriginalSourceAngle;
			Managed.OriginalSourceSoftAngle = Previous->OriginalSourceSoftAngle;
			Managed.OriginalForwardPriority = Previous->OriginalForwardPriority;
			Managed.bHasAtmosphereDisk = Previous->bHasAtmosphereDisk;
			Managed.bOriginalRealTimeCapture = Previous->bOriginalRealTimeCapture;
			Managed.bHasRealTimeCapture = Previous->bHasRealTimeCapture;
			Managed.OriginalMobility = Previous->OriginalMobility;
			Managed.bOriginalVisible = Previous->bOriginalVisible;
		}
		else
		{
			FCityLightBaseline Baseline;
			Baseline.Component = Light;
			Baseline.Intensity = Light->Intensity;
			Baseline.Color = Light->LightColor;
			Baseline.bCastShadows = Light->CastShadows != 0;
			Baseline.Mobility = static_cast<uint8>(Light->Mobility.GetValue());
			Baseline.bVisible = Light->GetVisibleFlag();
			if (const ULightComponent* AsLight = Cast<ULightComponent>(Light))
			{
				Baseline.Temperature = AsLight->Temperature;
				Baseline.bUseTemperature = AsLight->bUseTemperature != 0;
				Baseline.MaxDrawDistance = AsLight->MaxDrawDistance;
				Baseline.MaxDistanceFadeRange = AsLight->MaxDistanceFadeRange;
			}
			if (const ULocalLightComponent* Local = Cast<ULocalLightComponent>(Light))
			{
				Baseline.bHasUnits = true;
				Baseline.Units = static_cast<uint8>(Local->IntensityUnits);
			}
			if (const UDirectionalLightComponent* Directional = Cast<UDirectionalLightComponent>(Light))
			{
				Baseline.bHasAtmosphereDisk = true;
				Baseline.AtmosphereSunLightIndex = Directional->AtmosphereSunLightIndex;
				Baseline.AtmosphereSunDiskColorScale = Directional->GetAtmosphereSunDiskColorScale();
				Baseline.SourceAngle = Directional->LightSourceAngle;
				Baseline.SourceSoftAngle = Directional->LightSourceSoftAngle;
				Baseline.ForwardPriority = Directional->ForwardShadingPriority;
			}
			if (const USkyLightComponent* Sky = Cast<USkyLightComponent>(Light))
			{
				Baseline.bHasRealTimeCapture = true;
				Baseline.bRealTimeCapture = Sky->bRealTimeCapture;
			}
			if (Clock)
			{
				Clock->AdoptLightBaseline(Baseline);
			}
			Managed.OriginalIntensity = Baseline.Intensity;
			Managed.OriginalColor = Baseline.Color;
			Managed.OriginalTemperature = Baseline.Temperature;
			Managed.bOriginalUseTemperature = Baseline.bUseTemperature;
			Managed.bOriginalCastShadows = Baseline.bCastShadows;
			Managed.OriginalMaxDrawDistance = Baseline.MaxDrawDistance;
			Managed.OriginalFadeRange = Baseline.MaxDistanceFadeRange;
			Managed.OriginalUnits = Baseline.Units;
			Managed.bHasUnits = Baseline.bHasUnits;
			Managed.OriginalAtmosphereIndex = Baseline.AtmosphereSunLightIndex;
			Managed.OriginalDiskScale = Baseline.AtmosphereSunDiskColorScale;
			Managed.OriginalSourceAngle = Baseline.SourceAngle;
			Managed.OriginalSourceSoftAngle = Baseline.SourceSoftAngle;
			Managed.OriginalForwardPriority = Baseline.ForwardPriority;
			Managed.bHasAtmosphereDisk = Baseline.bHasAtmosphereDisk;
			Managed.bOriginalRealTimeCapture = Baseline.bRealTimeCapture;
			Managed.bHasRealTimeCapture = Baseline.bHasRealTimeCapture;
			Managed.OriginalMobility = Baseline.Mobility;
			Managed.bOriginalVisible = Baseline.bVisible;
		}
		switch (Kind)
		{
		case ECityLightKind::Sun: bSunBound = true; break;
		case ECityLightKind::Moon: bMoonBound = true; break;
		case ECityLightKind::Fill: bFillBound = true; break;
		case ECityLightKind::Sky: bSkyBound = true; break;
		case ECityLightKind::Bounce: bBounceBound = true; break;
		default: break;
		}
		Lights.Add(Managed);
	};

	for (TActorIterator<AActor> It(World); It; ++It)
	{
		AActor* Actor = *It;
		if (!IsValid(Actor) || Actor == this)
		{
			continue;
		}
		TInlineComponentArray<ULightComponentBase*> Components(Actor);
		for (ULightComponentBase* Light : Components)
		{
			if (!Light)
			{
				continue;
			}
			TArray<FString, TInlineAllocator<4>> Names;
			TArray<FString, TInlineAllocator<8>> ActorTags;
			CollectNames(Actor, Light, Names);
			CollectTags(Actor, Light, ActorTags);
			auto Named = [&Names](const TCHAR* BindingRole)
			{
				return AnyName(Names, [BindingRole](const FString& Name) { return EqualsOrPrefixed(Name, BindingRole); });
			};
			auto TakeNamed = [&](bool& bBound, const TCHAR* BindingRole, ECityLightKind Kind) -> bool
			{
				if (!Named(BindingRole))
				{
					return false;
				}
				if (bBound)
				{
					UE_LOG(LogCityEnvironment, Warning, TEXT("Duplicate %s skipped: actor %s component %s"), BindingRole, *Actor->GetActorNameOrLabel(), *Light->GetName());
				}
				else
				{
					RememberLight(Light, Kind, ECityLampGroup::Path, false, 0.0f);
				}
				return true;
			};
			if (TakeNamed(bSunBound, TEXT("CitySun"), ECityLightKind::Sun)
				|| TakeNamed(bFillBound, TEXT("CityStreetFill"), ECityLightKind::Fill)
				|| TakeNamed(bSkyBound, TEXT("CitySkyLight"), ECityLightKind::Sky)
				|| TakeNamed(bMoonBound, TEXT("ResortMoonlight"), ECityLightKind::Moon)
				|| TakeNamed(bBounceBound, TEXT("ResortMoonBounce"), ECityLightKind::Bounce))
			{
				continue;
			}
			if (IsIndoorTag(ActorTags))
			{
				continue;
			}
			ECityLampGroup Group = ECityLampGroup::Path;
			const bool bGrouped = ParseGroup(ActorTags, Group);
			float Lumens = 0.0f;
			const bool bLumens = ParseLumens(ActorTags, Lumens);
			const bool bBollard = AnyName(Names, [](const FString& Name) { return Name.Contains(TEXT("BollardLight"), ESearchCase::IgnoreCase); });
			const bool bLantern = AnyName(Names, [](const FString& Name)
			{
				return Name.Contains(TEXT("ResortLantern"), ESearchCase::IgnoreCase) && Name.Contains(TEXT("_Light"), ESearchCase::IgnoreCase);
			});
			const bool bDestination = AnyName(Names, [](const FString& Name) { return EqualsOrPrefixed(Name, TEXT("DestinationLight")); });
			const bool bPlaceLabel = AnyName(Names, [](const FString& Name)
			{
				return Name.Contains(TEXT("Destination"), ESearchCase::IgnoreCase) || Name.Contains(TEXT("Activity"), ESearchCase::IgnoreCase);
			});
			const bool bOutdoorWord = HasTag(ActorTags, TEXT("Outdoor")) || HasTag(ActorTags, TEXT("EnvOutdoor"));
			bool bLocal = false;
			if (bGrouped)
			{
				bLocal = true;
			}
			else if (bBollard || bLantern)
			{
				bLocal = true;
				Group = ECityLampGroup::Path;
			}
			else if (bDestination)
			{
				bLocal = true;
				Group = ECityLampGroup::Feature;
			}
			else if (bPlaceLabel && bOutdoorWord)
			{
				bLocal = true;
				Group = ECityLampGroup::Feature;
			}
			if (!bLocal)
			{
				continue;
			}
			bool bOverride = bLumens || bBollard || bLantern;
			if (!bLumens && bBollard)
			{
				Lumens = static_cast<float>(FCityEnvironmentCelestial::BollardLumens);
			}
			else if (!bLumens && bLantern)
			{
				Lumens = static_cast<float>(FCityEnvironmentCelestial::LanternLumens);
			}
			RememberLight(Light, ECityLightKind::Local, Group, bOverride, Lumens);
		}

		TInlineComponentArray<UPrimitiveComponent*> Primitives(Actor);
		for (UPrimitiveComponent* Primitive : Primitives)
		{
			if (!Primitive)
			{
				continue;
			}
			const int32 MaterialCount = Primitive->GetNumMaterials();
			for (int32 Index = 0; Index < MaterialCount; ++Index)
			{
				UMaterialInterface* Material = Primitive->GetMaterial(Index);
				if (!HasScalar(Material, TEXT("SignNightStrength")))
				{
					continue;
				}
				FManagedSign Sign;
				Sign.Component = Primitive;
				Sign.MaterialIndex = Index;
				const FManagedSign* Previous = nullptr;
				for (const FManagedSign& Item : PreviousSigns)
				{
					if (Item.Component.Get() == Primitive && Item.MaterialIndex == Index)
					{
						Previous = &Item;
						break;
					}
				}
				if (Previous)
				{
					Sign.Original = Previous->Original;
					Sign.Dynamic = Previous->Dynamic;
				}
				else
				{
					FCitySignBaseline Baseline;
					Baseline.Component = Primitive;
					Baseline.MaterialIndex = Index;
					Baseline.Original = Material;
					if (Clock)
					{
						Clock->AdoptSignBaseline(Baseline);
					}
					Sign.Original = Baseline.Original;
				}
				UMaterialInterface* Parent = Sign.Original.Get();
				UMaterialInstanceDynamic* Dynamic = Cast<UMaterialInstanceDynamic>(Primitive->GetMaterial(Index));
				if (!Dynamic || (Parent && Dynamic->Parent != Parent))
				{
					UMaterialInterface* Source = Parent ? Parent : Material;
					Dynamic = Source ? UMaterialInstanceDynamic::Create(Source, Primitive) : nullptr;
					if (Dynamic)
					{
						Primitive->SetMaterial(Index, Dynamic);
					}
				}
				Sign.Dynamic = Dynamic;
				Signs.Add(Sign);
			}
		}
	}

	for (TActorIterator<AActor> It(World); It; ++It)
	{
		AActor* Actor = *It;
		if (!IsValid(Actor))
		{
			continue;
		}
		TInlineComponentArray<USkyAtmosphereComponent*> SkyAtmospheres(Actor);
		for (USkyAtmosphereComponent* Atmosphere : SkyAtmospheres)
		{
			if (!Atmosphere)
			{
				continue;
			}
			FManagedAtmosphere Managed;
			Managed.Component = Atmosphere;
			const FManagedAtmosphere* Previous = nullptr;
			for (const FManagedAtmosphere& Item : PreviousAtmospheres)
			{
				if (Item.Component.Get() == Atmosphere)
				{
					Previous = &Item;
					break;
				}
			}
			if (Previous)
			{
				Managed.OriginalAngle = Previous->OriginalAngle;
			}
			else
			{
				FCityAtmosphereBaseline Baseline;
				Baseline.Component = Atmosphere;
				Baseline.TransmittanceMinLightElevationAngle = Atmosphere->TransmittanceMinLightElevationAngle;
				if (Clock)
				{
					Clock->AdoptAtmosphereBaseline(Baseline);
				}
				Managed.OriginalAngle = Baseline.TransmittanceMinLightElevationAngle;
			}
			Atmospheres.Add(Managed);
		}
	}

	// NewObject uniquifies an explicit name, so created meshes are tracked by pointer.
	TSet<UPrimitiveComponent*> CreatedComponents;
	auto BindMeshActor = [&](const TCHAR* RoleName, ECityMeshRole BindingRole)
	{
		bool bBoundRole = false;
		for (TActorIterator<AActor> It(World); It; ++It)
		{
			AActor* Actor = *It;
			if (!IsValid(Actor))
			{
				continue;
			}
			TArray<FString, TInlineAllocator<4>> Names;
			CollectNames(Actor, nullptr, Names);
			if (!AnyName(Names, [RoleName](const FString& Name) { return EqualsOrPrefixed(Name, RoleName); }))
			{
				continue;
			}
			if (bBoundRole)
			{
				UE_LOG(LogCityEnvironment, Warning, TEXT("Duplicate %s skipped: actor %s"), RoleName, *Actor->GetActorNameOrLabel());
				continue;
			}
			TInlineComponentArray<UPrimitiveComponent*> Primitives(Actor);
			if (Primitives.Num() == 0)
			{
				UStaticMesh* Sphere = LoadObject<UStaticMesh>(nullptr, SpherePath);
				if (!Sphere)
				{
					if (!bLoggedMissingSphere)
					{
						bLoggedMissingSphere = true;
						UE_LOG(LogCityEnvironment, Warning, TEXT("Engine sphere mesh is unavailable; moon geometry was not created"));
					}
				}
				else
				{
					const FName SphereName = MakeUniqueObjectName(Actor, UStaticMeshComponent::StaticClass(), TEXT("CityEnvironmentSphere"));
					UStaticMeshComponent* Created = NewObject<UStaticMeshComponent>(Actor, SphereName);
					if (Created)
					{
						Created->SetStaticMesh(Sphere);
						if (USceneComponent* ActorRoot = Actor->GetRootComponent())
						{
							Created->SetupAttachment(ActorRoot);
						}
						else
						{
							Actor->SetRootComponent(Created);
						}
						Created->RegisterComponent();
						Actor->AddInstanceComponent(Created);
						CreatedComponents.Add(Created);
						Primitives.Add(Created);
					}
				}
			}
			bool bChoseDriver = false;
			for (UPrimitiveComponent* Primitive : Primitives)
			{
				if (!Primitive)
				{
					continue;
				}
				FManagedMesh Managed;
				Managed.Actor = Actor;
				Managed.Component = Primitive;
				Managed.BindingRole = static_cast<uint8>(BindingRole);
				Managed.bDriver = !bChoseDriver && Cast<UStaticMeshComponent>(Primitive) != nullptr;
				if (Managed.bDriver)
				{
					bChoseDriver = true;
				}
				const FManagedMesh* Previous = nullptr;
				for (const FManagedMesh& Item : PreviousMeshes)
				{
					if (Item.Component.Get() == Primitive)
					{
						Previous = &Item;
						break;
					}
				}
				if (Previous)
				{
					Managed.OriginalRelative = Previous->OriginalRelative;
					Managed.OriginalCollision = Previous->OriginalCollision;
					Managed.bOriginalCastShadow = Previous->bOriginalCastShadow;
					Managed.OriginalMobility = Previous->OriginalMobility;
					Managed.bOriginalVisible = Previous->bOriginalVisible;
					Managed.bOriginalActorCollision = Previous->bOriginalActorCollision;
					Managed.OriginalMaterials = Previous->OriginalMaterials;
					Managed.bCreatedComponent = Previous->bCreatedComponent;
				}
				else
				{
					FCityMeshBaseline Baseline;
					Baseline.Component = Primitive;
					Baseline.RelativeTransform = Primitive->GetRelativeTransform();
					Baseline.Collision = static_cast<uint8>(Primitive->GetCollisionEnabled());
					Baseline.bCastShadow = Primitive->CastShadow;
					Baseline.Mobility = static_cast<uint8>(Primitive->Mobility.GetValue());
					Baseline.bVisible = Primitive->GetVisibleFlag();
					const int32 MaterialCount = Primitive->GetNumMaterials();
					Baseline.Materials.Reserve(MaterialCount);
					for (int32 Index = 0; Index < MaterialCount; ++Index)
					{
						Baseline.Materials.Add(Primitive->GetMaterial(Index));
					}
					if (Clock)
					{
						Clock->AdoptMeshBaseline(Baseline);
					}
					Managed.OriginalRelative = Baseline.RelativeTransform;
					Managed.OriginalCollision = Baseline.Collision;
					Managed.bOriginalCastShadow = Baseline.bCastShadow;
					Managed.OriginalMobility = Baseline.Mobility;
					Managed.bOriginalVisible = Baseline.bVisible;
					Managed.bOriginalActorCollision = Actor->GetActorEnableCollision();
					Managed.OriginalMaterials = Baseline.Materials;
					Managed.bCreatedComponent = CreatedComponents.Contains(Primitive);
				}
				Primitive->SetMobility(EComponentMobility::Movable);
				Primitive->SetCollisionEnabled(ECollisionEnabled::NoCollision);
				Primitive->SetCastShadow(false);
				Meshes.Add(Managed);
			}
			if (!bChoseDriver && Primitives.Num() > 0 && Meshes.Num() > 0)
			{
				Meshes.Last().bDriver = true;
			}
			Actor->SetActorEnableCollision(false);
			bBoundRole = true;
		}
	};
	BindMeshActor(TEXT("ResortMoonDisc"), ECityMeshRole::Disc);
	BindMeshActor(TEXT("ResortMoonHalo"), ECityMeshRole::Halo);
	BindMeshActor(TEXT("ResortNightSky"), ECityMeshRole::NightSky);

	if (!bLoggedBindings)
	{
		bLoggedBindings = true;
		int32 LocalCount = 0;
		for (const FManagedLight& Light : Lights)
		{
			LocalCount += Light.Kind == static_cast<uint8>(ECityLightKind::Local) ? 1 : 0;
		}
		UE_LOG(LogCityEnvironment, Log, TEXT("Environment bindings sun=%d moon=%d fill=%d sky=%d bounce=%d locals=%d signs=%d atmospheres=%d meshes=%d"),
			bSunBound ? 1 : 0, bMoonBound ? 1 : 0, bFillBound ? 1 : 0, bSkyBound ? 1 : 0, bBounceBound ? 1 : 0,
			LocalCount, Signs.Num(), Atmospheres.Num(), Meshes.Num());
	}
}

void ACityEnvironmentController::RestoreOwnedState()
{
	UCityEnvironmentClockSubsystem* Clock = ResolveClock();
	for (const FManagedLight& Item : Lights)
	{
		ULightComponentBase* Light = Item.Component.Get();
		if (!Light)
		{
			continue;
		}
		Light->SetMobility(EComponentMobility::Movable);
		WriteIntensity(Light, Item.OriginalIntensity);
		Light->SetVisibility(Item.bOriginalVisible);
		Light->SetCastShadows(Item.bOriginalCastShadows);
		if (ULightComponent* AsLight = Cast<ULightComponent>(Light))
		{
			AsLight->SetLightFColor(Item.OriginalColor);
			AsLight->SetUseTemperature(Item.bOriginalUseTemperature);
			AsLight->SetTemperature(Item.OriginalTemperature);
			AsLight->SetMaxDistanceFadeRange(Item.OriginalFadeRange);
			AsLight->SetMaxDrawDistance(Item.OriginalMaxDrawDistance);
		}
		else
		{
			Light->LightColor = Item.OriginalColor;
			Light->MarkRenderStateDirty();
		}
		if (ULocalLightComponent* Local = Cast<ULocalLightComponent>(Light))
		{
			if (Item.bHasUnits)
			{
				Local->SetIntensityUnits(static_cast<ELightUnits>(Item.OriginalUnits));
			}
		}
		if (UDirectionalLightComponent* Directional = Cast<UDirectionalLightComponent>(Light))
		{
			if (Item.bHasAtmosphereDisk)
			{
				Directional->SetAtmosphereSunLightIndex(Item.OriginalAtmosphereIndex);
				Directional->SetAtmosphereSunDiskColorScale(Item.OriginalDiskScale);
				Directional->SetLightSourceAngle(Item.OriginalSourceAngle);
				Directional->SetLightSourceSoftAngle(Item.OriginalSourceSoftAngle);
				Directional->SetForwardShadingPriority(Item.OriginalForwardPriority);
			}
		}
		if (USkyLightComponent* Sky = Cast<USkyLightComponent>(Light))
		{
			if (Item.bHasRealTimeCapture)
			{
				Sky->SetRealTimeCapture(Item.bOriginalRealTimeCapture);
			}
		}
		Light->SetMobility(static_cast<EComponentMobility::Type>(Item.OriginalMobility));
		if (Clock)
		{
			Clock->DropLightBaseline(Light);
		}
	}
	for (const FManagedSign& Sign : Signs)
	{
		if (UPrimitiveComponent* Primitive = Sign.Component.Get())
		{
			if (UMaterialInterface* Original = Sign.Original.Get())
			{
				Primitive->SetMaterial(Sign.MaterialIndex, Original);
			}
			if (Clock)
			{
				Clock->DropSignBaseline(Primitive, Sign.MaterialIndex);
			}
		}
	}
	for (const FManagedAtmosphere& Item : Atmospheres)
	{
		if (USkyAtmosphereComponent* Atmosphere = Item.Component.Get())
		{
			Atmosphere->SetTransmittanceMinLightElevationAngle(Item.OriginalAngle);
			if (Clock)
			{
				Clock->DropAtmosphereBaseline(Atmosphere);
			}
		}
	}
	for (FManagedMesh& Mesh : Meshes)
	{
		UPrimitiveComponent* Primitive = Mesh.Component.Get();
		AActor* Actor = Mesh.Actor.Get();
		if (Mesh.bCreatedComponent && Primitive)
		{
			Primitive->DestroyComponent();
			if (Clock)
			{
				Clock->DropMeshBaseline(Primitive);
			}
			continue;
		}
		if (!Primitive)
		{
			continue;
		}
		Primitive->SetMobility(EComponentMobility::Movable);
		Primitive->SetRelativeTransform(Mesh.OriginalRelative);
		Primitive->SetCollisionEnabled(static_cast<ECollisionEnabled::Type>(Mesh.OriginalCollision));
		Primitive->SetCastShadow(Mesh.bOriginalCastShadow);
		Primitive->SetVisibility(Mesh.bOriginalVisible);
		for (int32 Index = 0; Index < Mesh.OriginalMaterials.Num(); ++Index)
		{
			if (UMaterialInterface* Material = Mesh.OriginalMaterials[Index].Get())
			{
				Primitive->SetMaterial(Index, Material);
			}
		}
		Primitive->SetMobility(static_cast<EComponentMobility::Type>(Mesh.OriginalMobility));
		if (Actor)
		{
			Actor->SetActorEnableCollision(Mesh.bOriginalActorCollision);
		}
		if (Clock)
		{
			Clock->DropMeshBaseline(Primitive);
		}
	}
	Lights.Reset();
	Signs.Reset();
	Atmospheres.Reset();
	Meshes.Reset();
	bDidMutate = false;
}

void ACityEnvironmentController::ReleaseWidget()
{
	if (TimeWidget)
	{
		TimeWidget->RemoveFromParent();
		TimeWidget = nullptr;
	}
}

void ACityEnvironmentController::EnsureWidget()
{
	if (!bAuthority || !ShowTimeControls || TimeWidget)
	{
		return;
	}
	UWorld* World = GetWorld();
	if (!World || !World->IsGameWorld())
	{
		return;
	}
	TimeWidget = CreateWidget<UCityEnvironmentTimeWidget>(World, UCityEnvironmentTimeWidget::StaticClass());
	if (!TimeWidget)
	{
		return;
	}
	TimeWidget->SetController(this);
	TimeWidget->AddToViewport(40);
	TimeWidget->SetControlsVisible(true);
	UpdateTimeInputMode();
}

void ACityEnvironmentController::UpdateTimeInputMode()
{
	if(!ShowTimeControls){RestoreTimeInputMode();return;}
	if(bTimeInputOwned||!TimeWidget||!GetWorld()||!GetWorld()->IsGameWorld())return;
	if(APlayerController* PC=GetWorld()->GetFirstPlayerController())
	{
		TimeInputOwner=PC;bPreviousMouseCursor=PC->bShowMouseCursor;bTimeInputOwned=true;PC->bShowMouseCursor=true;
		FInputModeGameAndUI Mode;Mode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);Mode.SetHideCursorDuringCapture(false);PC->SetInputMode(Mode);
	}
}

void ACityEnvironmentController::RestoreTimeInputMode()
{
	if(bTimeInputOwned&&TimeInputOwner.IsValid())
	{
		APlayerController* PC=TimeInputOwner.Get();PC->bShowMouseCursor=bPreviousMouseCursor;
		if(!bPreviousMouseCursor){FInputModeGameOnly Mode;Mode.SetConsumeCaptureMouseDown(false);PC->SetInputMode(Mode);}
	}
	bTimeInputOwned=false;TimeInputOwner.Reset();
}

void ACityEnvironmentController::BindTimeKey()
{
	if (bKeyBound || !bAuthority)
	{
		return;
	}
	UWorld* World = GetWorld();
	APlayerController* Controller = World ? World->GetFirstPlayerController() : nullptr;
	if (!Controller)
	{
		return;
	}
	EnableInput(Controller);
	if (!InputComponent)
	{
		return;
	}
	InputComponent->BindKey(EKeys::F8, IE_Pressed, this, &ACityEnvironmentController::ToggleTimeControls);
	bKeyBound = true;
}

void ACityEnvironmentController::ReleaseInput()
{
	RestoreTimeInputMode();
	if (!bKeyBound)
	{
		return;
	}
	if (UWorld* World = GetWorld())
	{
		if (APlayerController* Controller = World->GetFirstPlayerController())
		{
			DisableInput(Controller);
		}
	}
	bKeyBound = false;
}

FVector ACityEnvironmentController::ResolveCamera() const
{
	if (bLightingViewOverride)
	{
		return LightingViewOverride;
	}
	if (const UWorld* World = GetWorld())
	{
		if (World->IsGameWorld())
		{
			if (const APlayerController* Player = World->GetFirstPlayerController())
			{
				FVector Location; FRotator Rotation;
				Player->GetPlayerViewPoint(Location, Rotation);
				return Location;
			}
		}
		const TArray<FVector>& Views = World->ViewLocationsRenderedLastFrame;
		if (Views.Num() > 0)
		{
			// A mean can lie in another district when reflection/offline views
			// coexist. Use a real view; captures supply their explicit override.
			return Views.Last();
		}
	}
	return GetActorLocation();
}

void ACityEnvironmentController::SetLightingViewOverride(FVector Location, bool bEnabled)
{
	LightingViewOverride = Location;
	bLightingViewOverride = bEnabled && !Location.ContainsNaN();
	ApplyEnvironment();
}

void ACityEnvironmentController::SampleAndApply(bool bForceSample)
{
	const float RealDelta = FMath::Max(0.0f, FApp::GetDeltaTime());
	SampleAccumulator += RealDelta;
	SkyAccumulator += RealDelta;
	const bool bDue = bForceSample || bSeek || !bHasSample || SampleAccumulator >= 0.1f;
	if (bDue)
	{
		const FCityEnvironmentSample Sample = FCityEnvironmentCelestial::Evaluate(LocalDateTime, MakeGeo(), false);
		if (Sample.bValid)
		{
			const bool bSnap = bForceSample || bSeek || !bHasSample || SampleAccumulator >= 0.2f;
			if (bSnap)
			{
				PreviousSunDirection = CurrentSunDirection = Sample.Sun.Direction;
				PreviousMoonDirection = CurrentMoonDirection = Sample.Moon.Direction;
				SampleAccumulator = 0.0f;
				SkyAccumulator = FMath::Max(SkyAccumulator, static_cast<float>(SkyRecaptureSeconds));
			}
			else
			{
				PreviousSunDirection = CurrentSunDirection;
				PreviousMoonDirection = CurrentMoonDirection;
				CurrentSunDirection = Sample.Sun.Direction;
				CurrentMoonDirection = Sample.Moon.Direction;
				SampleAccumulator = FMath::Fmod(SampleAccumulator, 0.1f);
			}
			CurrentSample = Sample;
			bHasSample = true;
		}
		bSeek = false;
	}
	if (!bAuthority || !bHasSample)
	{
		return;
	}
	const float Alpha = (SampleAccumulator <= 0.0f) ? 1.0f : FMath::Clamp(SampleAccumulator / 0.1f, 0.0f, 1.0f);
	ApplyDirections(Alpha);
	if (bDue && CurrentSample.bValid)
	{
		ApplyScalars(CurrentSample);
	}
}

void ACityEnvironmentController::ApplyDirections(float Alpha)
{
	DisplaySunDirection = SlerpDirection(PreviousSunDirection, CurrentSunDirection, Alpha);
	DisplayMoonDirection = SlerpDirection(PreviousMoonDirection, CurrentMoonDirection, Alpha);
	if (!bAuthority)
	{
		return;
	}
	for (const FManagedLight& Item : Lights)
	{
		ULightComponentBase* Light = Item.Component.Get();
		if (!Light || !Item.bDirectional)
		{
			continue;
		}
		if (Item.Kind == static_cast<uint8>(ECityLightKind::Sun))
		{
			AimLight(Light, DisplaySunDirection);
		}
		else if (Item.Kind == static_cast<uint8>(ECityLightKind::Moon))
		{
			AimLight(Light, DisplayMoonDirection);
		}
	}
	ApplyMoonAndSky(CurrentSample, DisplaySunDirection, DisplayMoonDirection);
	ApplyCollection(CurrentSample, DisplaySunDirection, DisplayMoonDirection, false);
}

void ACityEnvironmentController::ApplyScalars(const FCityEnvironmentSample& Sample)
{
	if (!bAuthority || !Sample.bValid)
	{
		return;
	}
	EnsureMeterMask();
	const FVector Camera = ResolveCamera();
	struct FRank
	{
		int32 Index = INDEX_NONE;
		double DistanceSquared = 0.0;
	};
	TArray<FRank> Ranks;
	const double Draw = LocalLightDrawDistance;
	const double DrawSquared = Draw > 0.0 ? Draw * Draw : TNumericLimits<double>::Max();
	for (int32 Index = 0; Index < Lights.Num(); ++Index)
	{
		const FManagedLight& Item = Lights[Index];
		if (!Item.bLocal || !Item.Component.IsValid())
		{
			continue;
		}
		FRank Rank;
		Rank.Index = Index;
		Rank.DistanceSquared = FVector::DistSquared(Item.Component->GetComponentLocation(), Camera);
		Ranks.Add(Rank);
	}
	Ranks.Sort([](const FRank& A, const FRank& B) { return A.DistanceSquared < B.DistanceSquared; });
	TArray<int32> Significant;
	TArray<int32> Shadowed;
	for (const FRank& Rank : Ranks)
	{
		if (Rank.DistanceSquared > DrawSquared || Significant.Num() >= MaxSignificantLocalLights)
		{
			continue;
		}
		Significant.Add(Rank.Index);
		if (bLocalLightShadows && Shadowed.Num() < MaxShadowedLocalLights)
		{
			Shadowed.Add(Rank.Index);
		}
	}

	for (int32 Index = 0; Index < Lights.Num(); ++Index)
	{
		const FManagedLight& Item = Lights[Index];
		ULightComponentBase* Light = Item.Component.Get();
		if (!Light)
		{
			continue;
		}
		Light->SetMobility(EComponentMobility::Movable);
		const ECityLightKind Kind = static_cast<ECityLightKind>(Item.Kind);
		float Intensity = Item.OriginalIntensity;
		if (Kind == ECityLightKind::Sun)
		{
			Intensity = static_cast<float>(Sample.SunLux);
			if (ULightComponent* AsLight = Cast<ULightComponent>(Light))
			{
				AsLight->SetUseTemperature(true);
				AsLight->SetTemperature(static_cast<float>(Sample.SunTemperatureKelvin));
			}
			if (UDirectionalLightComponent* Directional = Cast<UDirectionalLightComponent>(Light))
			{
				Directional->SetAtmosphereSunLightIndex(0);
				Directional->SetForwardShadingPriority(Sample.NightWeight > .5 ? 3 : 4);
			}
		}
		else if (Kind == ECityLightKind::Fill)
		{
			Intensity = Item.OriginalIntensity * static_cast<float>(Sample.StreetFillScale);
			if(auto Directional=Cast<UDirectionalLightComponent>(Light))Directional->SetForwardShadingPriority(0);
		}
		else if (Kind == ECityLightKind::Sky)
		{
			Intensity = static_cast<float>(Sample.SkyLightIntensity);
			if (USkyLightComponent* Sky = Cast<USkyLightComponent>(Light))
			{
				Sky->SetRealTimeCapture(false);
				if (DayAmbientCubemap && NightAmbientCubemap && Sky->SourceType == SLS_SpecifiedCubemap)
				{
					// Convolve each asset once, then blend SH/specular data. The
					// visible night sky can stay dark while shaded faces stay readable.
					Sky->SetCubemapBlend(DayAmbientCubemap, NightAmbientCubemap, float(Sample.NightWeight));
				}
				if (Sky->SourceType == SLS_CapturedScene && SkyAccumulator >= static_cast<float>(FMath::Max(0.1, SkyRecaptureSeconds)))
				{
					Sky->RecaptureSky();
					SkyAccumulator = 0.0f;
				}
			}
		}
		else if (Kind == ECityLightKind::Moon)
		{
			Intensity = static_cast<float>(Sample.MoonLux);
			if (UDirectionalLightComponent* Directional = Cast<UDirectionalLightComponent>(Light))
			{
				Directional->SetAtmosphereSunLightIndex(1);
				Directional->SetForwardShadingPriority(Sample.NightWeight > .5 ? 4 : 3);
				Directional->SetAtmosphereSunDiskColorScale(FLinearColor::Black);
				// VSM SMRT uses the angular emitter size to spread the penumbra
				// with distance from the occluder. Keep contact detail without
				// a hard moon-shadow outline across the pavement.
				Directional->SetLightSourceAngle(float(MoonShadowSourceAngle));
				Directional->SetLightSourceSoftAngle(2.0f);
			}
		}
		else if (Kind == ECityLightKind::Bounce)
		{
			Intensity = static_cast<float>(Sample.BounceLux);
			if(auto Directional=Cast<UDirectionalLightComponent>(Light))Directional->SetForwardShadingPriority(1);
		}
		else if (Kind == ECityLightKind::Local)
		{
			const double Factor = ScheduleFor(static_cast<ECityLampGroup>(Item.Group), Sample) * Sample.NightWeight;
			Intensity = Item.bOverrideLumens ? Item.TargetLumens * static_cast<float>(Factor) : Item.OriginalIntensity * static_cast<float>(Factor);
			const bool bKeep = Significant.Contains(Index);
			const bool bShadow = Shadowed.Contains(Index);
			if (!bKeep)
			{
				Intensity = 0.0f;
			}
			if (ULocalLightComponent* Local = Cast<ULocalLightComponent>(Light))
			{
				if (Item.bOverrideLumens)
				{
					Local->SetIntensityUnits(ELightUnits::Lumens);
				}
			}
			if (ULightComponent* AsLight = Cast<ULightComponent>(Light))
			{
				const float Distance = static_cast<float>(FMath::Max(0.0, LocalLightDrawDistance));
				AsLight->SetMaxDistanceFadeRange(Distance > 0.0f ? Distance * 0.1f : Item.OriginalFadeRange);
				AsLight->SetMaxDrawDistance(Distance);
			}
			Light->SetCastShadows(bShadow);
		}
		WriteIntensity(Light, Intensity);
	}

	for (const FManagedSign& Sign : Signs)
	{
		if (UMaterialInstanceDynamic* Dynamic = Sign.Dynamic.Get())
		{
			Dynamic->SetScalarParameterValue(TEXT("SignNightStrength"), static_cast<float>(Sample.SignGlowWeight));
		}
	}
	for (const FManagedAtmosphere& Item : Atmospheres)
	{
		if (USkyAtmosphereComponent* Atmosphere = Item.Component.Get())
		{
			Atmosphere->SetTransmittanceMinLightElevationAngle(0.0f);
		}
	}
	if (Exposure)
	{
		Exposure->bEnabled = true;
		Exposure->bUnbound = true;
		Exposure->Priority = 100.0f;
		Exposure->BlendWeight = 1.0f;
		FPostProcessSettings& Settings = Exposure->Settings;
		Settings.bOverride_AutoExposureMethod = true;
		Settings.AutoExposureMethod = AEM_Histogram;
		Settings.bOverride_AutoExposureMinBrightness = true;
		Settings.bOverride_AutoExposureMaxBrightness = true;
		Settings.AutoExposureMinBrightness = static_cast<float>(Sample.EvMin);
		Settings.AutoExposureMaxBrightness = static_cast<float>(Sample.EvMax);
		Settings.bOverride_HistogramLogMin = true;
		Settings.bOverride_HistogramLogMax = true;
		Settings.HistogramLogMin = static_cast<float>(Sample.EvMin);
		Settings.HistogramLogMax = static_cast<float>(Sample.EvMax);
		Settings.bOverride_AutoExposureSpeedUp = true;
		Settings.bOverride_AutoExposureSpeedDown = true;
		Settings.AutoExposureSpeedUp = 3.0f;
		Settings.AutoExposureSpeedDown = 3.0f;
		Settings.bOverride_AutoExposureLowPercent = true;
		Settings.bOverride_AutoExposureHighPercent = true;
		Settings.AutoExposureLowPercent = 10.0f;
		Settings.AutoExposureHighPercent = 90.0f;
		Settings.bOverride_LocalExposureMethod = true;
		Settings.LocalExposureMethod = ELocalExposureMethod::Bilateral;
		Settings.bOverride_LocalExposureHighlightContrastScale = true;
		Settings.bOverride_LocalExposureShadowContrastScale = true;
		Settings.LocalExposureHighlightContrastScale = 0.85f;
		Settings.LocalExposureShadowContrastScale = 0.9f;
		Settings.bOverride_LocalExposureDetailStrength = true;
		Settings.LocalExposureDetailStrength = 1.0f;
		Settings.bOverride_LocalExposureBlurredLuminanceBlend = true;
		Settings.LocalExposureBlurredLuminanceBlend = 0.5f;
		if (MeterMask)
		{
			Settings.bOverride_AutoExposureMeterMask = true;
			Settings.AutoExposureMeterMask = MeterMask;
		}
	}
	ApplyCollection(Sample, DisplaySunDirection, DisplayMoonDirection, true);
	bDidMutate = true;
}

void ACityEnvironmentController::ApplyMoonAndSky(const FCityEnvironmentSample& Sample, const FVector& SunDirection, const FVector& MoonDirection)
{
	(void)SunDirection;
	if (!Sample.bValid)
	{
		return;
	}
	const FVector Camera = ResolveCamera();
	const FVector Direction = MoonDirection.GetSafeNormal();
	const double Diameter = FMath::Clamp(MoonAngularDiameterDegrees, 0.1, 40.0);
	const double HaloScale = FMath::Clamp(HaloAngularScale, 1.01, 3.0);
	const double DiscDistance = FMath::Max(100000.0, MoonDiscDistance);
	const double Alpha = FMath::DegreesToRadians(Diameter * 0.5);
	const double Beta = FMath::DegreesToRadians(Diameter * HaloScale * 0.5);
	const double DiscRadius = DiscDistance * FMath::Tan(Alpha);
	const double Gap = FMath::Max(25000.0, DiscRadius * 0.02);
	const double TanBeta = FMath::Tan(Beta);
	double HaloDistance = DiscDistance + DiscRadius + Gap + 100000.0;
	if (TanBeta < 0.9)
	{
		HaloDistance = (DiscDistance + DiscRadius + Gap) / (1.0 - TanBeta);
	}
	double HaloRadius = HaloDistance * TanBeta;
	const double NearLimit = DiscDistance + DiscRadius + Gap;
	if (HaloDistance - HaloRadius < NearLimit)
	{
		HaloRadius = FMath::Max(1.0, HaloDistance - NearLimit);
	}
	const double HaloFar = HaloDistance + HaloRadius;
	// Below the horizon, or fully faded, the disc and halo are hidden. A partial daytime fade stays visible.
	const bool bMoonUp = Sample.Moon.AltitudeDegrees > 0.0 && Sample.MoonDiscVisibility > 0.001;
	const float DiscFade = static_cast<float>(Sample.MoonDiscVisibility);
	// The installed material blends the entire day/night sky continuously.
	// Hiding its opaque shell at a threshold would expose a different sky.
	const bool bSkyOn = true;

	for (const FManagedMesh& Mesh : Meshes)
	{
		UPrimitiveComponent* Primitive = Mesh.Component.Get();
		if (!Primitive)
		{
			continue;
		}
		Primitive->SetMobility(EComponentMobility::Movable);
		Primitive->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Primitive->SetCastShadow(false);
		const ECityMeshRole BindingRole = static_cast<ECityMeshRole>(Mesh.BindingRole);
		const bool bShow = BindingRole == ECityMeshRole::NightSky ? bSkyOn : bMoonUp;
		Primitive->SetVisibility(bShow, true);
		float Fade = BindingRole == ECityMeshRole::NightSky ? static_cast<float>(Sample.NightWeight) : DiscFade;
		Primitive->SetCustomPrimitiveDataFloat(0, Fade);
		if (UMeshComponent* AsMesh = Cast<UMeshComponent>(Primitive))
		{
			const TCHAR* Candidates[] = {
				BindingRole == ECityMeshRole::NightSky ? TEXT("NightWeight") : TEXT("MoonDiscVisibility"),
				TEXT("Opacity"),
				BindingRole == ECityMeshRole::NightSky ? TEXT("StarOpacity") : TEXT("Fade")
			};
			for (const TCHAR* Name : Candidates)
			{
				if (!HasScalar(AsMesh->GetMaterial(0), Name) && !HasScalar(Mesh.OriginalMaterials.Num() > 0 ? Mesh.OriginalMaterials[0].Get() : nullptr, Name))
				{
					continue;
				}
				UMaterialInstanceDynamic* Dynamic = Cast<UMaterialInstanceDynamic>(AsMesh->GetMaterial(0));
				if (!Dynamic)
				{
					UMaterialInterface* Parent = Mesh.OriginalMaterials.Num() > 0 ? Mesh.OriginalMaterials[0].Get() : AsMesh->GetMaterial(0);
					if (Parent && HasScalar(Parent, Name))
					{
						Dynamic = UMaterialInstanceDynamic::Create(Parent, AsMesh);
						if (Dynamic)
						{
							AsMesh->SetMaterial(0, Dynamic);
						}
					}
				}
				if (Dynamic && HasScalar(Dynamic, Name))
				{
					Dynamic->SetScalarParameterValue(Name, Fade);
				}
			}
		}
		if (!Mesh.bDriver)
		{
			continue;
		}
		UStaticMeshComponent* StaticMesh = Cast<UStaticMeshComponent>(Primitive);
		const UStaticMesh* Asset = StaticMesh ? StaticMesh->GetStaticMesh() : nullptr;
		const double LocalRadius = Asset && Asset->GetBounds().SphereRadius > 1.0 ? Asset->GetBounds().SphereRadius : 50.0;
		const FVector Origin = Asset ? FVector(Asset->GetBounds().Origin) : FVector::ZeroVector;
		double Distance = DiscDistance;
		double Radius = DiscRadius;
		if (BindingRole == ECityMeshRole::Halo)
		{
			Distance = HaloDistance;
			Radius = HaloRadius;
		}
		else if (BindingRole == ECityMeshRole::NightSky)
		{
			const double OriginalRadius = LocalRadius * static_cast<double>(Mesh.OriginalRelative.GetScale3D().GetAbsMax());
			Radius = FMath::Max(OriginalRadius, HaloFar + Gap);
			Distance = 0.0;
		}
		const double Scale = Radius / LocalRadius;
		const FVector Target = BindingRole == ECityMeshRole::NightSky ? Camera : Camera + Direction * Distance;
		Primitive->SetWorldScale3D(FVector(Scale));
		if (BindingRole != ECityMeshRole::NightSky)
		{
			Primitive->SetWorldRotation(FRotator::ZeroRotator);
		}
		Primitive->SetWorldLocation(Target - Origin * Scale);
	}
}

void ACityEnvironmentController::ApplyCollection(const FCityEnvironmentSample& Sample, const FVector& SunDirection, const FVector& MoonDirection, bool bScalars)
{
	UWorld* World = GetWorld();
	if (!World || !Sample.bValid)
	{
		return;
	}
	if (!ParameterCollection)
	{
		ParameterCollection = LoadObject<UMaterialParameterCollection>(nullptr, CollectionPath);
		if (!ParameterCollection)
		{
			if (!bLoggedMissingCollection)
			{
				bLoggedMissingCollection = true;
				UE_LOG(LogCityEnvironment, Warning, TEXT("Missing %s. The primary agent creates this collection; materials will not receive weights until it exists."), CollectionPath);
			}
			return;
		}
	}
	UMaterialParameterCollectionInstance* Instance = World->GetParameterCollectionInstance(ParameterCollection);
	if (!Instance)
	{
		return;
	}
	const FLinearColor SunColor(SunDirection.X, SunDirection.Y, SunDirection.Z, 0.0f);
	const FLinearColor MoonColor(MoonDirection.X, MoonDirection.Y, MoonDirection.Z, 0.0f);
	const FVector Bright = BrightLimb(SunDirection, MoonDirection);
	Instance->SetVectorParameterValue(TEXT("SunDirection"), SunColor);
	Instance->SetVectorParameterValue(TEXT("MoonDirection"), MoonColor);
	Instance->SetVectorParameterValue(TEXT("MoonBrightDirection"), FLinearColor(Bright.X, Bright.Y, Bright.Z, 0.0f));
	if (!bScalars)
	{
		return;
	}
	const float Night = static_cast<float>(Sample.NightWeight);
	const FLinearColor DayTop(0.18f, 0.42f, 0.85f, 1.0f);
	const FLinearColor DayHorizon(0.62f, 0.78f, 0.92f, 1.0f);
	// Visible sky is independent of the ambient cubemap: keep the approved
	// street lighting while giving the sky a substantially darker night blue.
	const FLinearColor NightTop(0.0008f, 0.0015f, 0.005f, 1.0f);
	const FLinearColor NightHorizon(0.004f, 0.006f, 0.014f, 1.0f);
	Instance->SetScalarParameterValue(TEXT("NightWeight"), Night);
	Instance->SetScalarParameterValue(TEXT("DayWeight"), static_cast<float>(Sample.DayWeight));
	Instance->SetScalarParameterValue(TEXT("SignGlowWeight"), static_cast<float>(Sample.SignGlowWeight));
	Instance->SetScalarParameterValue(TEXT("LampGlowWeight"), static_cast<float>(Sample.LampGlowWeight));
	Instance->SetScalarParameterValue(TEXT("SportGlowWeight"), static_cast<float>(Sample.NightWeight * Sample.SportSchedule));
	Instance->SetScalarParameterValue(TEXT("MoonPhase"), static_cast<float>(Sample.MoonPhaseAngleDegrees / 360.0));
	Instance->SetScalarParameterValue(TEXT("MoonIllumination"), static_cast<float>(Sample.MoonIlluminatedFraction));
	Instance->SetVectorParameterValue(TEXT("SkyTop"), FMath::Lerp(DayTop, NightTop, Night));
	Instance->SetVectorParameterValue(TEXT("SkyHorizon"), FMath::Lerp(DayHorizon, NightHorizon, Night));
}

void ACityEnvironmentController::EnsureMeterMask()
{
	if (MeterMask)
	{
		return;
	}
	MeterMask = UTexture2D::CreateTransient(64, 64, PF_B8G8R8A8, TEXT("CityEnvironmentMeterMask"));
	if (!MeterMask)
	{
		return;
	}
	MeterMask->SRGB = false;
	MeterMask->Filter = TF_Bilinear;
	MeterMask->AddressX = TA_Clamp;
	MeterMask->AddressY = TA_Clamp;
	MeterMask->NeverStream = true;
#if WITH_EDITORONLY_DATA
	MeterMask->MipGenSettings = TMGS_NoMipmaps;
#endif
	FTexturePlatformData* Platform = MeterMask->GetPlatformData();
	if (!Platform || Platform->Mips.Num() == 0)
	{
		MeterMask = nullptr;
		return;
	}
	FTexture2DMipMap& Mip = Platform->Mips[0];
	void* Locked = Mip.BulkData.Lock(LOCK_READ_WRITE);
	if (!Locked)
	{
		MeterMask = nullptr;
		return;
	}
	FColor* Pixels = static_cast<FColor*>(Locked);
	const int32 Width = Mip.SizeX;
	const int32 Height = Mip.SizeY;
	const float Sigma = 0.28f;
	for (int32 Y = 0; Y < Height; ++Y)
	{
		for (int32 X = 0; X < Width; ++X)
		{
			const float U = (static_cast<float>(X) + 0.5f) / static_cast<float>(Width) - 0.5f;
			const float V = (static_cast<float>(Y) + 0.5f) / static_cast<float>(Height) - 0.5f;
			const float Weight = FMath::Exp(-(U * U + V * V) / (2.0f * Sigma * Sigma));
			const uint8 Byte = static_cast<uint8>(FMath::Clamp(FMath::RoundToInt(Weight * 255.0f), 0, 255));
			Pixels[Y * Width + X] = FColor(Byte, Byte, Byte, 255);
		}
	}
	Mip.BulkData.Unlock();
	MeterMask->UpdateResource();
	MeterMask->AddToRoot();
}
