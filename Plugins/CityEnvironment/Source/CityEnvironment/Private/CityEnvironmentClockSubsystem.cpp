#include "CityEnvironmentClockSubsystem.h"
#include "Components/LightComponentBase.h"

#include "CityEnvironmentLog.h"
#include "CityEnvironmentSaveGame.h"
#include "Misc/App.h"

void UCityEnvironmentClockSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	FCityEnvironmentGeo Geo;
	double LoadedMinutes = 60.0;
	double LoadedScale = 1.0;
	bool bLoadedPaused = true;
	FDateTime LoadedTime;
	if (UCityEnvironmentSaveGame::LoadSlot(LoadedTime, Geo, LoadedMinutes, LoadedScale, bLoadedPaused))
	{
		LocalDateTime = LoadedTime;
		bLoadedPersistentClock = true;
		MinutesPerDay = LoadedMinutes;
		TimeScale = LoadedScale;
		bPaused = bLoadedPaused;
		bHasClock = true;
		bAwaitingSeed = false;
	}
	else
	{
		LocalDateTime = FDateTime(
			static_cast<int32>(FCityEnvironmentCelestial::FullMoonAnchorYear),
			FCityEnvironmentCelestial::FullMoonAnchorMonth,
			FCityEnvironmentCelestial::FullMoonAnchorDay,
			12, 0, 0);
		bPaused = true;
		bHasClock = false;
		bAwaitingSeed = true;
	}
	TickerHandle = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateUObject(this, &UCityEnvironmentClockSubsystem::TickClock));
}

void UCityEnvironmentClockSubsystem::Deinitialize()
{
	if (TickerHandle.IsValid())
	{
		FTSTicker::GetCoreTicker().RemoveTicker(TickerHandle);
		TickerHandle.Reset();
	}
	Super::Deinitialize();
}

void UCityEnvironmentClockSubsystem::SetLocalDateTime(const FDateTime& Value)
{
	LocalDateTime = Value;
	bHasClock = true;
	bAwaitingSeed = false;
}

void UCityEnvironmentClockSubsystem::SetTimeScale(double Value)
{
	TimeScale = FMath::IsFinite(Value) ? Value : 1.0;
}

void UCityEnvironmentClockSubsystem::SetMinutesPerDay(double Value)
{
	MinutesPerDay = FMath::IsFinite(Value) && Value > 0.001 ? Value : 60.0;
}

void UCityEnvironmentClockSubsystem::SetPaused(bool bInPaused)
{
	bPaused = bInPaused;
}

void UCityEnvironmentClockSubsystem::SeedFullMoon(const FCityEnvironmentGeo& Geo)
{
	if (!bAwaitingSeed)
	{
		return;
	}
	FCityEnvironmentGeo Site = Geo;
	Site.Sanitize();
	const FDateTime After(
		static_cast<int32>(FCityEnvironmentCelestial::FullMoonAnchorYear),
		FCityEnvironmentCelestial::FullMoonAnchorMonth,
		FCityEnvironmentCelestial::FullMoonAnchorDay);
	FDateTime Full;
	if (FCityEnvironmentCelestial::NextFullMoonLocal(Site, After, Full) && Full > After)
	{
		// Use the full-moon date for a romantic evening on first launch.
		// The exact astronomical full-moon instant remains in the ephemeris.
		LocalDateTime = Full.GetDate() + FTimespan(21,0,0);
	}
	else
	{
		UE_LOG(LogCityEnvironment, Warning, TEXT("Full moon search after 2026-10-22 failed; keeping %s"), *FCityEnvironmentCelestial::ToIso8601(LocalDateTime));
	}
	bAwaitingSeed = false;
	bHasClock = true;
	bPaused = true;
	SaveClock(Site);
	UE_LOG(LogCityEnvironment, Log, TEXT("Initial civil time %s (next full moon after 2026-10-22)"), *FCityEnvironmentCelestial::ToIso8601(LocalDateTime));
}

bool UCityEnvironmentClockSubsystem::SaveClock(const FCityEnvironmentGeo& Geo)
{
	return UCityEnvironmentSaveGame::SaveSlot(LocalDateTime, Geo, MinutesPerDay, TimeScale, bPaused);
}

bool UCityEnvironmentClockSubsystem::LoadClock(FCityEnvironmentGeo* OutGeo)
{
	FCityEnvironmentGeo Geo;
	double LoadedMinutes = MinutesPerDay;
	double LoadedScale = TimeScale;
	bool bLoadedPaused = bPaused;
	FDateTime LoadedTime;
	if (!UCityEnvironmentSaveGame::LoadSlot(LoadedTime, Geo, LoadedMinutes, LoadedScale, bLoadedPaused))
	{
		return false;
	}
	LocalDateTime = LoadedTime;
	MinutesPerDay = LoadedMinutes;
	TimeScale = LoadedScale;
	bPaused = bLoadedPaused;
	bHasClock = true;
	bAwaitingSeed = false;
	if (OutGeo)
	{
		*OutGeo = Geo;
	}
	return true;
}

bool UCityEnvironmentClockSubsystem::ConsumeInitialPlayback()
{
	const bool bNewClock = !bLoadedPersistentClock && !bInitialPlaybackConsumed;
	bInitialPlaybackConsumed = true;
	return bNewClock;
}

bool UCityEnvironmentClockSubsystem::TickClock(float DeltaSeconds)
{
	(void)DeltaSeconds;
	if (bPaused || bAwaitingSeed || !bHasClock)
	{
		return true;
	}
	const double RealDelta = static_cast<double>(FApp::GetDeltaTime());
	if (!FMath::IsFinite(RealDelta) || RealDelta <= 0.0)
	{
		return true;
	}
	LocalDateTime = FCityEnvironmentCelestial::AdvanceRealTime(LocalDateTime, RealDelta, MinutesPerDay, TimeScale);
	return true;
}

void UCityEnvironmentClockSubsystem::PruneBaselines()
{
	for (auto It = LightBaselines.CreateIterator(); It; ++It)
	{
		if (!It.Value().Component.IsValid())
		{
			It.RemoveCurrent();
		}
	}
	SignBaselines.RemoveAll([](const FCitySignBaseline& Item) { return !Item.Component.IsValid(); });
	AtmosphereBaselines.RemoveAll([](const FCityAtmosphereBaseline& Item) { return !Item.Component.IsValid(); });
	MeshBaselines.RemoveAll([](const FCityMeshBaseline& Item) { return !Item.Component.IsValid(); });
}

bool UCityEnvironmentClockSubsystem::AdoptLightBaseline(FCityLightBaseline& InOut)
{
	if (!InOut.Component.IsValid())
	{
		return false;
	}
	PruneBaselines();
	const FObjectKey Key(InOut.Component.Get());
	if (const FCityLightBaseline* Found = LightBaselines.Find(Key))
	{
		InOut = *Found;
		return true;
	}
	LightBaselines.Add(Key, InOut);
	return false;
}

void UCityEnvironmentClockSubsystem::DropLightBaseline(const ULightComponentBase* Light)
{
	if (Light)
	{
		LightBaselines.Remove(FObjectKey(Light));
	}
}

bool UCityEnvironmentClockSubsystem::AdoptSignBaseline(FCitySignBaseline& InOut)
{
	if (!InOut.Component.IsValid())
	{
		return false;
	}
	for (const FCitySignBaseline& Item : SignBaselines)
	{
		if (Item.Component.Get() == InOut.Component.Get() && Item.MaterialIndex == InOut.MaterialIndex)
		{
			InOut.Original = Item.Original;
			return true;
		}
	}
	SignBaselines.Add(InOut);
	return false;
}

void UCityEnvironmentClockSubsystem::DropSignBaseline(const UPrimitiveComponent* Component, int32 MaterialIndex)
{
	SignBaselines.RemoveAll([Component, MaterialIndex](const FCitySignBaseline& Item)
	{
		return Item.Component.Get() == Component && Item.MaterialIndex == MaterialIndex;
	});
}

bool UCityEnvironmentClockSubsystem::AdoptAtmosphereBaseline(FCityAtmosphereBaseline& InOut)
{
	if (!InOut.Component.IsValid())
	{
		return false;
	}
	for (const FCityAtmosphereBaseline& Item : AtmosphereBaselines)
	{
		if (Item.Component.Get() == InOut.Component.Get())
		{
			InOut.TransmittanceMinLightElevationAngle = Item.TransmittanceMinLightElevationAngle;
			return true;
		}
	}
	AtmosphereBaselines.Add(InOut);
	return false;
}

void UCityEnvironmentClockSubsystem::DropAtmosphereBaseline(const USkyAtmosphereComponent* Component)
{
	AtmosphereBaselines.RemoveAll([Component](const FCityAtmosphereBaseline& Item)
	{
		return Item.Component.Get() == Component;
	});
}

bool UCityEnvironmentClockSubsystem::AdoptMeshBaseline(FCityMeshBaseline& InOut)
{
	if (!InOut.Component.IsValid())
	{
		return false;
	}
	for (const FCityMeshBaseline& Item : MeshBaselines)
	{
		if (Item.Component.Get() == InOut.Component.Get())
		{
			InOut = Item;
			return true;
		}
	}
	MeshBaselines.Add(InOut);
	return false;
}

void UCityEnvironmentClockSubsystem::DropMeshBaseline(const UPrimitiveComponent* Component)
{
	MeshBaselines.RemoveAll([Component](const FCityMeshBaseline& Item)
	{
		return Item.Component.Get() == Component;
	});
}
