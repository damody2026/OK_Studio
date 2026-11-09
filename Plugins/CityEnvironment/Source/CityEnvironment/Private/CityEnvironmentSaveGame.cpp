#include "CityEnvironmentSaveGame.h"

#include "CityEnvironmentCelestial.h"
#include "CityEnvironmentLog.h"
#include "Kismet/GameplayStatics.h"

const TCHAR* UCityEnvironmentSaveGame::SlotName()
{
	return TEXT("CityEnvironmentV1");
}

bool UCityEnvironmentSaveGame::SaveSlot(const FDateTime& InLocalDateTime, const FCityEnvironmentGeo& Geo, double InMinutesPerDay, double InTimeScale, bool bInPaused)
{
	UCityEnvironmentSaveGame* Image = Cast<UCityEnvironmentSaveGame>(UGameplayStatics::CreateSaveGameObject(UCityEnvironmentSaveGame::StaticClass()));
	if (!Image)
	{
		UE_LOG(LogCityEnvironment, Warning, TEXT("Could not create save object for slot %s"), SlotName());
		return false;
	}
	FCityEnvironmentGeo Site = Geo;
	Site.Sanitize();
	Image->LocalDateTime = InLocalDateTime;
	Image->Latitude = Site.Latitude;
	Image->Longitude = Site.Longitude;
	Image->UtcOffsetHours = Site.UtcOffsetHours;
	Image->NorthYawDegrees = Site.NorthYawDegrees;
	Image->MinutesPerDay = FMath::IsFinite(InMinutesPerDay) && InMinutesPerDay > 0.001 ? InMinutesPerDay : 60.0;
	Image->TimeScale = FMath::IsFinite(InTimeScale) ? InTimeScale : 1.0;
	Image->bPaused = bInPaused;
	Image->bHasClock = true;
	if (!UGameplayStatics::SaveGameToSlot(Image, SlotName(), 0))
	{
		UE_LOG(LogCityEnvironment, Warning, TEXT("SaveGameToSlot failed for %s"), SlotName());
		return false;
	}
	return true;
}

bool UCityEnvironmentSaveGame::LoadSlot(FDateTime& OutLocalDateTime, FCityEnvironmentGeo& OutGeo, double& OutMinutesPerDay, double& OutTimeScale, bool& bOutPaused)
{
	if (!UGameplayStatics::DoesSaveGameExist(SlotName(), 0))
	{
		return false;
	}
	USaveGame* Loaded = UGameplayStatics::LoadGameFromSlot(SlotName(), 0);
	const UCityEnvironmentSaveGame* Image = Cast<UCityEnvironmentSaveGame>(Loaded);
	if (!Image || !Image->bHasClock)
	{
		UE_LOG(LogCityEnvironment, Warning, TEXT("Slot %s exists but is not a city environment clock"), SlotName());
		return false;
	}
	OutLocalDateTime = Image->LocalDateTime;
	OutGeo.Latitude = Image->Latitude;
	OutGeo.Longitude = Image->Longitude;
	OutGeo.UtcOffsetHours = Image->UtcOffsetHours;
	OutGeo.NorthYawDegrees = Image->NorthYawDegrees;
	OutGeo.Sanitize();
	OutMinutesPerDay = FMath::IsFinite(Image->MinutesPerDay) && Image->MinutesPerDay > 0.001 ? Image->MinutesPerDay : 60.0;
	OutTimeScale = FMath::IsFinite(Image->TimeScale) ? Image->TimeScale : 1.0;
	bOutPaused = Image->bPaused;
	return true;
}
