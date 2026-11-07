#pragma once

#include "CoreMinimal.h"
#include "CityEnvironmentCelestial.h"
#include "Containers/Ticker.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "UObject/ObjectKey.h"
#include "CityEnvironmentClockSubsystem.generated.h"

class ULightComponentBase;
class UPrimitiveComponent;
class UMaterialInterface;
class USkyAtmosphereComponent;

/** First-seen authored values. Later refreshes must not treat a live edit as the original. */
struct FCityLightBaseline
{
	TWeakObjectPtr<ULightComponentBase> Component;
	float Intensity = 0.0f;
	FColor Color = FColor::White;
	float Temperature = 6500.0f;
	bool bUseTemperature = false;
	bool bCastShadows = false;
	float MaxDrawDistance = 0.0f;
	float MaxDistanceFadeRange = 0.0f;
	uint8 Units = 0;
	bool bHasUnits = false;
	int32 AtmosphereSunLightIndex = 0;
	FLinearColor AtmosphereSunDiskColorScale = FLinearColor::White;
	bool bHasAtmosphereDisk = false;
	float SourceAngle = 0.5357f;
	float SourceSoftAngle = 0.0f;
	int32 ForwardPriority = 0;
	bool bRealTimeCapture = false;
	bool bHasRealTimeCapture = false;
	uint8 Mobility = 0;
	bool bVisible = true;
};

struct FCitySignBaseline
{
	TWeakObjectPtr<UPrimitiveComponent> Component;
	int32 MaterialIndex = 0;
	TWeakObjectPtr<UMaterialInterface> Original;
};

struct FCityAtmosphereBaseline
{
	TWeakObjectPtr<USkyAtmosphereComponent> Component;
	float TransmittanceMinLightElevationAngle = 0.0f;
};

struct FCityMeshBaseline
{
	TWeakObjectPtr<UPrimitiveComponent> Component;
	FTransform RelativeTransform = FTransform::Identity;
	uint8 Collision = 0;
	bool bCastShadow = false;
	uint8 Mobility = 0;
	bool bVisible = true;
	TArray<TWeakObjectPtr<UMaterialInterface>> Materials;
};

/**
 * One civil clock for the game instance. It keeps running across level travel.
 * Advance uses FApp::GetDeltaTime once per frame, never world DeltaSeconds.
 */
UCLASS()
class CITYENVIRONMENT_API UCityEnvironmentClockSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

	bool HasClock() const { return bHasClock; }
	bool IsAwaitingSeed() const { return bAwaitingSeed; }
	FDateTime GetLocalDateTime() const { return LocalDateTime; }
	double GetTimeScale() const { return TimeScale; }
	double GetMinutesPerDay() const { return MinutesPerDay; }
	bool IsPaused() const { return bPaused; }

	void SetLocalDateTime(const FDateTime& Value);
	void SetTimeScale(double Value);
	void SetMinutesPerDay(double Value);
	void SetPaused(bool bInPaused);
	void SeedFullMoon(const FCityEnvironmentGeo& Geo);
	bool SaveClock(const FCityEnvironmentGeo& Geo);
	bool LoadClock(FCityEnvironmentGeo* OutGeo);
	/** Auto-play only a brand-new clock; preserve saved pause state on reload/travel. */
	bool ConsumeInitialPlayback();

	/** Copies the stored original into InOut when this component was captured before. */
	bool AdoptLightBaseline(FCityLightBaseline& InOut);
	void DropLightBaseline(const ULightComponentBase* Light);
	bool AdoptSignBaseline(FCitySignBaseline& InOut);
	void DropSignBaseline(const UPrimitiveComponent* Component, int32 MaterialIndex);
	bool AdoptAtmosphereBaseline(FCityAtmosphereBaseline& InOut);
	void DropAtmosphereBaseline(const USkyAtmosphereComponent* Component);
	bool AdoptMeshBaseline(FCityMeshBaseline& InOut);
	void DropMeshBaseline(const UPrimitiveComponent* Component);

private:
	bool bLoadedPersistentClock = false;
	bool bInitialPlaybackConsumed = false;
	bool TickClock(float DeltaSeconds);
	void PruneBaselines();

	FDateTime LocalDateTime;
	double TimeScale = 1.0;
	double MinutesPerDay = 60.0;
	bool bPaused = true;
	bool bHasClock = false;
	bool bAwaitingSeed = true;
	FTSTicker::FDelegateHandle TickerHandle;
	TMap<FObjectKey, FCityLightBaseline> LightBaselines;
	TArray<FCitySignBaseline> SignBaselines;
	TArray<FCityAtmosphereBaseline> AtmosphereBaselines;
	TArray<FCityMeshBaseline> MeshBaselines;
};
