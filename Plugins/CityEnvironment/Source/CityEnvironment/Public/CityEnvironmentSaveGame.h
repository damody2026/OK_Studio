#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "CityEnvironmentSaveGame.generated.h"

struct FCityEnvironmentGeo;

/** Disk image of the civil clock. The slot name is CityEnvironmentV1. */
UCLASS()
class CITYENVIRONMENT_API UCityEnvironmentSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	static const TCHAR* SlotName();

	UPROPERTY()
	FDateTime LocalDateTime;

	UPROPERTY()
	double Latitude = 23.5;

	UPROPERTY()
	double Longitude = 121.0;

	UPROPERTY()
	double UtcOffsetHours = 8.0;

	UPROPERTY()
	double NorthYawDegrees = 0.0;

	UPROPERTY()
	double MinutesPerDay = 60.0;

	UPROPERTY()
	double TimeScale = 1.0;

	UPROPERTY()
	bool bPaused = true;

	UPROPERTY()
	bool bHasClock = false;

	static bool SaveSlot(const FDateTime& LocalDateTime, const FCityEnvironmentGeo& Geo, double MinutesPerDay, double TimeScale, bool bPaused);
	static bool LoadSlot(FDateTime& OutLocalDateTime, FCityEnvironmentGeo& OutGeo, double& OutMinutesPerDay, double& OutTimeScale, bool& bOutPaused);
};
