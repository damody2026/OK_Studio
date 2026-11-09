#pragma once

#include "CoreMinimal.h"

/**
 * Civil time and topocentric sun/moon evaluation.
 *
 * Refraction convention (every altitude this module reports, unless a test
 * explicitly compares the airless value):
 *   EQUATOR_OF_DATE + ABERRATION, observer topocentric (not geocentric),
 *   then Astronomy_Horizon with REFRACTION_NORMAL.
 * REFRACTION_NORMAL is Astronomy Engine's Meeus standard-atmosphere model at
 * sea level. It increases apparent altitude; azimuth is not refracted.
 * Rise/set uses Astronomy_SearchRiseSetEx with the library horizon
 * (refraction plus the body's apparent radius) and metersAboveGround = 0.
 * Runtime never uses REFRACTION_JPLHOR. JSON field "refraction" repeats this.
 *
 * Horizon azimuth: 0 = north, 90 = east, altitude degrees above the horizon.
 * UE world: +X north, +Y east, +Z up, then yawed by NorthYawDegrees
 * (positive yaw rotates north from +X toward +Y). Direction vectors point
 * from the observer toward the body. A directional light's forward axis is
 * the opposite vector (rays travel away from the body).
 *
 * The clock advances only through AddGameSeconds / AdvanceRealTime. Callers
 * pass one real-time delta. World TimeDilation is not an input.
 */
struct CITYENVIRONMENT_API FCityEnvironmentGeo
{
	double Latitude = 23.5;
	double Longitude = 121.0;
	double UtcOffsetHours = 8.0;
	double NorthYawDegrees = 0.0;

	bool IsFinite() const;
	void Sanitize();
};

struct CITYENVIRONMENT_API FCityBodySky
{
	bool bValid = false;
	double AzimuthDegrees = 0.0;
	double AltitudeDegrees = 0.0;
	FVector Direction = FVector::UpVector;
};

struct CITYENVIRONMENT_API FCityRiseSet
{
	bool bRise = false;
	bool bSet = false;
	FDateTime RiseUtc;
	FDateTime SetUtc;
	double DayLengthHours = 0.0;
};

struct CITYENVIRONMENT_API FCityEnvironmentSample
{
	bool bValid = false;
	FDateTime LocalDateTime;
	FDateTime UtcDateTime;
	double Hour24 = 0.0;
	FCityBodySky Sun;
	FCityBodySky Moon;
	double MoonPhaseAngleDegrees = 0.0;
	double MoonIlluminatedFraction = 0.0;
	FVector MoonBrightDirection = FVector::ForwardVector;
	double SunMoonSeparationDegrees = 0.0;
	double NightWeight = 0.0;
	double DayWeight = 1.0;
	double SignGlowWeight = 0.0;
	double LampGlowWeight = 0.0;
	double SunLux = 0.0;
	double MoonLux = 0.0;
	double BounceLux = 0.0;
	double StreetFillScale = 0.0;
	double SkyLightIntensity = 2.5;
	double SunTemperatureKelvin = 5800.0;
	double EvMin = 10.0;
	double EvMax = 15.0;
	double PathSchedule = 1.0;
	double FeatureSchedule = 1.0;
	double MarketSchedule = 1.0;
	double SportSchedule = 1.0;
	double CampSchedule = 1.0;
	double MoonDiscVisibility = 0.0;
	FCityRiseSet SunRiseSet;
	FCityRiseSet MoonRiseSet;
};

enum class ECityCelestialBody : uint8
{
	Sun,
	Moon
};

class CITYENVIRONMENT_API FCityEnvironmentCelestial
{
public:
	static constexpr double FullMoonAnchorYear = 2026;
	static constexpr int32 FullMoonAnchorMonth = 10;
	static constexpr int32 FullMoonAnchorDay = 22;
	static constexpr double SunNoonLux = 80000.0;
	static constexpr double MoonArtLux = 4.0;
	static constexpr double NightBounceLux = 2.4;
	static constexpr double DaySkyIntensity = 2.5;
	static constexpr double NightSkyIntensity = 2.1;
	static constexpr double PathDeep = 0.7;
	static constexpr double FeatureDeep = 0.45;
	static constexpr double CampDeep = 0.4;
	static constexpr double SignClosed = 0.35;
	static constexpr double LanternLumens = 1200.0;
	static constexpr double BollardLumens = 140.0;

	static double SmoothStep(double Edge0, double Edge1, double Value);
	static double WrapHour(double Hour);
	static double HourOfDay(const FDateTime& Local);
	static FString ToIso8601(const FDateTime& Value);
	static FDateTime ToUtc(const FDateTime& Local, double UtcOffsetHours);
	static FDateTime ToLocal(const FDateTime& Utc, double UtcOffsetHours);
	static FDateTime AddGameSeconds(const FDateTime& Local, double GameSeconds);
	static FDateTime AdvanceRealTime(const FDateTime& Local, double RealSeconds, double MinutesPerDay, double TimeScale);
	static FDateTime SetHourOnDate(const FDateTime& Local, double Hour);
	static FVector HorizonToWorld(double AzimuthDegrees, double AltitudeDegrees, double NorthYawDegrees);

	static double DeepNightAmount(double Hour);
	static double MarketClosedAmount(double Hour);
	static double PathScheduleAt(double Hour);
	static double FeatureScheduleAt(double Hour);
	static double CampScheduleAt(double Hour);
	static double MarketScheduleAt(double Hour);
	static double SportScheduleAt(double Hour);

	static bool NextFullMoonLocal(const FCityEnvironmentGeo& Geo, const FDateTime& AfterLocal, FDateTime& OutLocal);
	static FCityEnvironmentSample Evaluate(const FDateTime& Local, const FCityEnvironmentGeo& Geo, bool bIncludeRiseSet);
	static bool ComputeRiseSet(ECityCelestialBody Body, const FCityEnvironmentGeo& Geo, const FDateTime& LocalMidnight, FCityRiseSet& Out);
	static FString BuildStateJson(const FCityEnvironmentSample& Sample, const FCityEnvironmentGeo& Geo, bool bPaused, double TimeScale, double MinutesPerDay);
	static FString RunSelfTests();

	static bool TestMidnight(FString& Detail);
	static bool TestLeapDay(FString& Detail);
	static bool TestSeek(FString& Detail);
	static bool TestNormalTime(FString& Detail);
	static bool TestMoonPhase(FString& Detail);
	static bool TestSeasons(FString& Detail);
	static bool TestBelowHorizon(FString& Detail);
	static bool TestSchedules(FString& Detail);
	static bool TestRefraction(FString& Detail);
	static bool TestFrame(FString& Detail);
};
