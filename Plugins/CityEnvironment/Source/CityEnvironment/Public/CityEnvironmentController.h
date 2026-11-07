#pragma once

#include "CoreMinimal.h"
#include "CityEnvironmentCelestial.h"
#include "GameFramework/Actor.h"
#include "CityEnvironmentController.generated.h"

class UCityEnvironmentTimeWidget;
class ULightComponentBase;
class UMaterialInstanceDynamic;
class UMaterialInterface;
class UMaterialParameterCollection;
class UPostProcessComponent;
class UPrimitiveComponent;
class USceneComponent;
class USkyAtmosphereComponent;
class USkyLightComponent;
class UTexture2D;
class UTextureCube;
class APlayerController;

/**
 * One environment writer per world. The civil clock itself lives on the
 * game instance. This actor samples lighting at 10 Hz and interpolates
 * sun and moon directions every frame.
 */
UCLASS(Blueprintable, ClassGroup=(City))
class CITYENVIRONMENT_API ACityEnvironmentController : public AActor
{
	GENERATED_BODY()

public:
	ACityEnvironmentController();

	virtual void OnConstruction(const FTransform& Transform) override;
	virtual void PostLoad() override;
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void Tick(float DeltaSeconds) override;
	virtual bool ShouldTickIfViewportsOnly() const override;
	virtual void PreSave(FObjectPreSaveContext SaveContext) override;

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void InitializeBindings();

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void RefreshBindings();

	/** Detach transient preview resources before the native editor saves. */
	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void PrepareForSave();

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void DeactivateAndRestore();

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void ApplyEnvironment();

	/** Deterministic lighting origin for offline captures; never saved in maps. */
	UFUNCTION(BlueprintCallable, Category="City|Environment")
	void SetLightingViewOverride(FVector Location, bool bEnabled);

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void SetHour(double Hour);

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void SetDateTime(FDateTime InLocalDateTime);

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void SetTimeScale(double InTimeScale);

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void SetPaused(bool bInPaused);

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void SaveClock();

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	void LoadClock();

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	FString GetStateJson();

	UFUNCTION(CallInEditor, BlueprintCallable, Category="City|Environment")
	FString RunClockSelfTests();

	UFUNCTION(BlueprintCallable, Category="City|Environment")
	void ToggleTimeControls();

	FDateTime GetLocalDateTime() const { return LocalDateTime; }
	double GetTimeScale() const { return TimeScale; }
	bool IsClockPaused() const { return Paused; }
	bool ShouldShowTimeControls() const { return ShowTimeControls; }

	/** The game owns the sun, the sky light and the exposure and feeds SetHour: this keeps the lamps, the signs and the sky dome. */
	void UseGameClock();

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	FDateTime LocalDateTime;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	double Latitude = 23.5;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	double Longitude = 121.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	double UTCOffsetHours = 8.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	double NorthYawDegrees = 0.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="0.001"))
	double MinutesPerDay = 60.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	bool Paused = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	bool ShowTimeControls = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	double TimeScale = 1.0;

	/** Editor preview stays paused. BeginPlay clears Paused when this is set. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	bool bPlaybackOnBeginPlay = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="0.1", ClampMax="40.0"))
	double MoonAngularDiameterDegrees = 5.5;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="1.01", ClampMax="3.0"))
	double HaloAngularScale = 1.6;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="100000.0"))
	double MoonDiscDistance = 8000000.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="0.0"))
	double LocalLightDrawDistance = 12000.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="0"))
	int32 MaxSignificantLocalLights = 48;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="0"))
	int32 MaxShadowedLocalLights = 8;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	bool bLocalLightShadows = false;

	/** Artistic moon diameter also controls the physical penumbra width. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="0.5", ClampMax="12.0"))
	double MoonShadowSourceAngle = 9.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment", meta=(ClampMin="0.1"))
	double SkyRecaptureSeconds = 2.0;

	/** Persistent references ensure the ambient maps are included in cooking. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	TObjectPtr<UTextureCube> DayAmbientCubemap;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="City|Environment")
	TObjectPtr<UTextureCube> NightAmbientCubemap;

protected:
	UPROPERTY(VisibleAnywhere, Category="City|Environment")
	TObjectPtr<USceneComponent> Root;

	UPROPERTY(VisibleAnywhere, Category="City|Environment")
	TObjectPtr<UPostProcessComponent> Exposure;

	UPROPERTY(Transient)
	TObjectPtr<UCityEnvironmentTimeWidget> TimeWidget;

	UPROPERTY(Transient)
	TObjectPtr<UTexture2D> MeterMask;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialParameterCollection> ParameterCollection;

private:
	bool bGameClock = false;
	FVector LightingViewOverride = FVector::ZeroVector;
	bool bLightingViewOverride = false;
	void UpdateTimeInputMode();
	void RestoreTimeInputMode();
	TWeakObjectPtr<APlayerController> TimeInputOwner;
	bool bTimeInputOwned = false;
	bool bPreviousMouseCursor = false;
	struct FManagedLight
	{
		TWeakObjectPtr<ULightComponentBase> Component;
		uint8 Kind = 0;
		uint8 Group = 0;
		bool bOverrideLumens = false;
		bool bDirectional = false;
		bool bSky = false;
		bool bLocal = false;
		float TargetLumens = 0.0f;
		float OriginalIntensity = 0.0f;
		FColor OriginalColor = FColor::White;
		float OriginalTemperature = 6500.0f;
		bool bOriginalUseTemperature = false;
		bool bOriginalCastShadows = false;
		float OriginalMaxDrawDistance = 0.0f;
		float OriginalFadeRange = 0.0f;
		uint8 OriginalUnits = 0;
		bool bHasUnits = false;
		int32 OriginalAtmosphereIndex = 0;
		FLinearColor OriginalDiskScale = FLinearColor::White;
		float OriginalSourceAngle = 0.5357f;
		float OriginalSourceSoftAngle = 0.0f;
		int32 OriginalForwardPriority = 0;
		bool bHasAtmosphereDisk = false;
		bool bOriginalRealTimeCapture = false;
		bool bHasRealTimeCapture = false;
		uint8 OriginalMobility = 0;
		bool bOriginalVisible = true;
	};

	struct FManagedSign
	{
		TWeakObjectPtr<UPrimitiveComponent> Component;
		int32 MaterialIndex = 0;
		TWeakObjectPtr<UMaterialInterface> Original;
		TWeakObjectPtr<UMaterialInstanceDynamic> Dynamic;
	};

	struct FManagedAtmosphere
	{
		TWeakObjectPtr<USkyAtmosphereComponent> Component;
		float OriginalAngle = 0.0f;
	};

	struct FManagedMesh
	{
		TWeakObjectPtr<AActor> Actor;
		TWeakObjectPtr<UPrimitiveComponent> Component;
		uint8 BindingRole = 0;
		bool bDriver = false;
		FTransform OriginalRelative = FTransform::Identity;
		uint8 OriginalCollision = 0;
		bool bOriginalCastShadow = false;
		uint8 OriginalMobility = 0;
		bool bOriginalVisible = true;
		bool bOriginalActorCollision = true;
		TArray<TWeakObjectPtr<UMaterialInterface>> OriginalMaterials;
		bool bCreatedComponent = false;
	};

	class UCityEnvironmentClockSubsystem* ResolveClock() const;
	FCityEnvironmentGeo MakeGeo() const;
	void EnsureInitialClock();
	void MirrorClock();
	void AdvanceEditorClock();
	void ClaimAuthority();
	void SetAuthority(bool bInAuthority);
	void RefreshRegistry();
	void RestoreOwnedState();
	void ReleaseWidget();
	void EnsureWidget();
	void BindTimeKey();
	void ReleaseInput();
	FVector ResolveCamera() const;
	void SampleAndApply(bool bForceSample);
	void ApplyDirections(float Alpha);
	void ApplyScalars(const FCityEnvironmentSample& Sample);
	void ApplyMoonAndSky(const FCityEnvironmentSample& Sample, const FVector& SunDirection, const FVector& MoonDirection);
	void ApplyCollection(const FCityEnvironmentSample& Sample, const FVector& SunDirection, const FVector& MoonDirection, bool bScalars);
	void EnsureMeterMask();
	void NoteMirrored();

	TArray<FManagedLight> Lights;
	TArray<FManagedSign> Signs;
	TArray<FManagedAtmosphere> Atmospheres;
	TArray<FManagedMesh> Meshes;
	bool bSunBound = false;
	bool bMoonBound = false;
	bool bFillBound = false;
	bool bSkyBound = false;
	bool bBounceBound = false;
	bool bAuthority = true;
	bool bBindingsReady = false;
	bool bClockReady = false;
	bool bSeek = true;
	bool bHasSample = false;
	bool bKeyBound = false;
	bool bLoggedMissingCollection = false;
	bool bLoggedMissingSphere = false;
	bool bLoggedBindings = false;
	bool bDidMutate = false;
	float SampleAccumulator = 0.0f;
	float SkyAccumulator = 1000.0f;
	FCityEnvironmentSample CurrentSample;
	FVector PreviousSunDirection = FVector::UpVector;
	FVector CurrentSunDirection = FVector::UpVector;
	FVector PreviousMoonDirection = FVector::UpVector;
	FVector CurrentMoonDirection = FVector::UpVector;
	FVector DisplaySunDirection = FVector::UpVector;
	FVector DisplayMoonDirection = FVector::UpVector;
	FDateTime LastMirroredDate;
	double LastMirroredScale = 1.0;
	double LastMirroredMinutes = 60.0;
	bool bLastMirroredPaused = true;
};
