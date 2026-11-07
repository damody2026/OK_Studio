#include "CityEnvironmentCelestial.h"
#include "CityEnvironmentLog.h"
#include "Misc/Timespan.h"
#include "astronomy.h"

namespace
{
	static constexpr int64 TicksPerSecond = ETimespan::TicksPerSecond;

	FString EscapeJson(const FString& Text)
	{
		FString Out;
		Out.Reserve(Text.Len() + 8);
		for (const TCHAR Character : Text)
		{
			switch (Character)
			{
			case TEXT('\\'): Out += TEXT("\\\\"); break;
			case TEXT('"'): Out += TEXT("\\\""); break;
			case TEXT('\n'): Out += TEXT("\\n"); break;
			case TEXT('\r'): Out += TEXT("\\r"); break;
			case TEXT('\t'): Out += TEXT("\\t"); break;
			default: Out.AppendChar(Character); break;
			}
		}
		return Out;
	}

	FString Num(double Value, int32 Decimals)
	{
		if (!FMath::IsFinite(Value))
		{
			return TEXT("null");
		}
		const bool bNegative = Value < 0.0;
		double Scale = 1.0;
		for (int32 Index = 0; Index < Decimals; ++Index)
		{
			Scale *= 10.0;
		}
		const double Absolute = FMath::Abs(Value);
		const int64 Scaled = FMath::RoundToInt64(Absolute * Scale + 1e-9);
		const int64 Denom = FMath::RoundToInt64(Scale);
		const int64 Whole = Denom > 0 ? Scaled / Denom : Scaled;
		const int64 Fraction = Denom > 0 ? Scaled % Denom : 0;
		FString Digits = FString::Printf(TEXT("%lld"), Fraction);
		while (Digits.Len() < Decimals)
		{
			Digits = TEXT("0") + Digits;
		}
		if (Decimals <= 0)
		{
			return FString::Printf(TEXT("%s%lld"), bNegative ? TEXT("-") : TEXT(""), Whole);
		}
		return FString::Printf(TEXT("%s%lld.%s"), bNegative ? TEXT("-") : TEXT(""), Whole, *Digits);
	}

	FString Vec(const FVector& Value)
	{
		return FString::Printf(TEXT("[%s,%s,%s]"), *Num(Value.X, 6), *Num(Value.Y, 6), *Num(Value.Z, 6));
	}

	bool FiniteTime(const astro_time_t& Time)
	{
		return FMath::IsFinite(Time.ut) && FMath::IsFinite(Time.tt);
	}

	bool MakeAstroTime(const FDateTime& Utc, astro_time_t& Out)
	{
		const int32 Year = Utc.GetYear();
		const int32 Month = Utc.GetMonth();
		const int32 Day = Utc.GetDay();
		const int32 Hour = Utc.GetHour();
		const int32 Minute = Utc.GetMinute();
		const int32 Second = Utc.GetSecond();
		const int32 Millisecond = Utc.GetMillisecond();
		if (!FDateTime::Validate(Year, Month, Day, Hour, Minute, Second, Millisecond))
		{
			return false;
		}
		Out = Astronomy_MakeTime(Year, Month, Day, Hour, Minute, static_cast<double>(Second) + static_cast<double>(Millisecond) / 1000.0);
		return FiniteTime(Out);
	}

	bool FromAstroTime(const astro_time_t& Time, FDateTime& OutUtc)
	{
		if (!FiniteTime(Time))
		{
			return false;
		}
		const astro_utc_t Utc = Astronomy_UtcFromTime(Time);
		if (Utc.year < 1 || Utc.month < 1 || Utc.day < 1)
		{
			return false;
		}
		const int32 WholeSecond = FMath::Clamp(static_cast<int32>(Utc.second), 0, 59);
		const int32 Millisecond = FMath::Clamp(static_cast<int32>((Utc.second - WholeSecond) * 1000.0), 0, 999);
		if (!FDateTime::Validate(Utc.year, Utc.month, Utc.day, Utc.hour, Utc.minute, WholeSecond, Millisecond))
		{
			return false;
		}
		OutUtc = FDateTime(Utc.year, Utc.month, Utc.day, Utc.hour, Utc.minute, WholeSecond, Millisecond);
		return true;
	}

	astro_observer_t MakeObserver(const FCityEnvironmentGeo& Geo)
	{
		return Astronomy_MakeObserver(Geo.Latitude, Geo.Longitude, 0.0);
	}

	bool BodySky(astro_body_t Body, astro_time_t Time, const astro_observer_t& Observer, double NorthYaw, astro_refraction_t Refraction, FCityBodySky& Out)
	{
		Out = FCityBodySky();
		const astro_equatorial_t Equator = Astronomy_Equator(Body, &Time, Observer, EQUATOR_OF_DATE, ABERRATION);
		if (Equator.status != ASTRO_SUCCESS)
		{
			return false;
		}
		const astro_horizon_t Horizon = Astronomy_Horizon(&Time, Observer, Equator.ra, Equator.dec, Refraction);
		if (!FMath::IsFinite(Horizon.azimuth) || !FMath::IsFinite(Horizon.altitude))
		{
			return false;
		}
		Out.bValid = true;
		Out.AzimuthDegrees = Horizon.azimuth;
		Out.AltitudeDegrees = Horizon.altitude;
		Out.Direction = FCityEnvironmentCelestial::HorizonToWorld(Horizon.azimuth, Horizon.altitude, NorthYaw);
		return true;
	}

	FString RiseJson(const FCityRiseSet& RiseSet)
	{
		const FString Rise = RiseSet.bRise ? FString::Printf(TEXT("\"%s\""), *FCityEnvironmentCelestial::ToIso8601(RiseSet.RiseUtc)) : TEXT("null");
		const FString Set = RiseSet.bSet ? FString::Printf(TEXT("\"%s\""), *FCityEnvironmentCelestial::ToIso8601(RiseSet.SetUtc)) : TEXT("null");
		return FString::Printf(TEXT("{\"riseUtc\":%s,\"setUtc\":%s,\"dayLengthHours\":%s}"), *Rise, *Set, RiseSet.bRise && RiseSet.bSet ? *Num(RiseSet.DayLengthHours, 4) : TEXT("null"));
	}

	bool NearlyEqual(double A, double B, double Tolerance)
	{
		return FMath::IsFinite(A) && FMath::IsFinite(B) && FMath::Abs(A - B) <= Tolerance;
	}

	bool SameSample(const FCityEnvironmentSample& A, const FCityEnvironmentSample& B, FString& Detail)
	{
		if (A.bValid != B.bValid || A.LocalDateTime != B.LocalDateTime)
		{
			Detail = TEXT("identity mismatch");
			return false;
		}
		if (!NearlyEqual(A.Sun.AzimuthDegrees, B.Sun.AzimuthDegrees, 1e-6) || !NearlyEqual(A.Sun.AltitudeDegrees, B.Sun.AltitudeDegrees, 1e-6) || !NearlyEqual(A.SunLux, B.SunLux, 1e-6))
		{
			Detail = TEXT("sun mismatch");
			return false;
		}
		if (!NearlyEqual(A.Moon.AzimuthDegrees, B.Moon.AzimuthDegrees, 1e-6) || !NearlyEqual(A.Moon.AltitudeDegrees, B.Moon.AltitudeDegrees, 1e-6) || !NearlyEqual(A.MoonLux, B.MoonLux, 1e-6) || !NearlyEqual(A.MoonIlluminatedFraction, B.MoonIlluminatedFraction, 1e-6))
		{
			Detail = TEXT("moon mismatch");
			return false;
		}
		if (!NearlyEqual(A.NightWeight, B.NightWeight, 1e-8) || !NearlyEqual(A.EvMin, B.EvMin, 1e-8) || !NearlyEqual(A.PathSchedule, B.PathSchedule, 1e-8) || !NearlyEqual(A.MarketSchedule, B.MarketSchedule, 1e-8))
		{
			Detail = TEXT("weight mismatch");
			return false;
		}
		return true;
	}
}

bool FCityEnvironmentGeo::IsFinite() const
{
	return FMath::IsFinite(Latitude) && FMath::IsFinite(Longitude) && FMath::IsFinite(UtcOffsetHours) && FMath::IsFinite(NorthYawDegrees);
}

void FCityEnvironmentGeo::Sanitize()
{
	if (!FMath::IsFinite(Latitude)) Latitude = 23.5;
	if (!FMath::IsFinite(Longitude)) Longitude = 121.0;
	if (!FMath::IsFinite(UtcOffsetHours)) UtcOffsetHours = 8.0;
	if (!FMath::IsFinite(NorthYawDegrees)) NorthYawDegrees = 0.0;
	Latitude = FMath::Clamp(Latitude, -90.0, 90.0);
	UtcOffsetHours = FMath::Clamp(UtcOffsetHours, -18.0, 18.0);
}

double FCityEnvironmentCelestial::SmoothStep(double Edge0, double Edge1, double Value)
{
	if (!FMath::IsFinite(Value) || !FMath::IsFinite(Edge0) || !FMath::IsFinite(Edge1) || FMath::IsNearlyEqual(Edge0, Edge1))
	{
		return Value >= Edge1 ? 1.0 : 0.0;
	}
	const double Alpha = FMath::Clamp((Value - Edge0) / (Edge1 - Edge0), 0.0, 1.0);
	return Alpha * Alpha * (3.0 - 2.0 * Alpha);
}

double FCityEnvironmentCelestial::WrapHour(double Hour)
{
	if (!FMath::IsFinite(Hour))
	{
		return 0.0;
	}
	double Wrapped = FMath::Fmod(Hour, 24.0);
	if (Wrapped < 0.0)
	{
		Wrapped += 24.0;
	}
	if (Wrapped >= 24.0)
	{
		Wrapped = 0.0;
	}
	return Wrapped;
}

double FCityEnvironmentCelestial::HourOfDay(const FDateTime& Local)
{
	return static_cast<double>(Local.GetHour())
		+ static_cast<double>(Local.GetMinute()) / 60.0
		+ (static_cast<double>(Local.GetSecond()) + static_cast<double>(Local.GetMillisecond()) / 1000.0) / 3600.0;
}

FString FCityEnvironmentCelestial::ToIso8601(const FDateTime& Value)
{
	return FString::Printf(TEXT("%04d-%02d-%02dT%02d:%02d:%02d.%03d"),
		Value.GetYear(), Value.GetMonth(), Value.GetDay(),
		Value.GetHour(), Value.GetMinute(), Value.GetSecond(), Value.GetMillisecond());
}

FDateTime FCityEnvironmentCelestial::ToUtc(const FDateTime& Local, double UtcOffsetHours)
{
	if (!FMath::IsFinite(UtcOffsetHours))
	{
		UtcOffsetHours = 8.0;
	}
	return Local - FTimespan::FromSeconds(UtcOffsetHours * 3600.0);
}

FDateTime FCityEnvironmentCelestial::ToLocal(const FDateTime& Utc, double UtcOffsetHours)
{
	if (!FMath::IsFinite(UtcOffsetHours))
	{
		UtcOffsetHours = 8.0;
	}
	return Utc + FTimespan::FromSeconds(UtcOffsetHours * 3600.0);
}

FDateTime FCityEnvironmentCelestial::AddGameSeconds(const FDateTime& Local, double GameSeconds)
{
	if (!FMath::IsFinite(GameSeconds) || GameSeconds == 0.0)
	{
		return Local;
	}
	const double Ticks = GameSeconds * static_cast<double>(TicksPerSecond);
	const int64 Delta = FMath::RoundToInt64(Ticks);
	return Local + FTimespan(Delta);
}

FDateTime FCityEnvironmentCelestial::AdvanceRealTime(const FDateTime& Local, double RealSeconds, double MinutesPerDay, double TimeScale)
{
	if (!FMath::IsFinite(RealSeconds) || !FMath::IsFinite(MinutesPerDay) || !FMath::IsFinite(TimeScale) || MinutesPerDay <= 0.001)
	{
		return Local;
	}
	const double GameSecondsPerRealSecond = (86400.0 / (MinutesPerDay * 60.0)) * TimeScale;
	return AddGameSeconds(Local, RealSeconds * GameSecondsPerRealSecond);
}

FDateTime FCityEnvironmentCelestial::SetHourOnDate(const FDateTime& Local, double Hour)
{
	if (!FMath::IsFinite(Hour))
	{
		return Local;
	}
	return AddGameSeconds(Local.GetDate(), Hour * 3600.0);
}

FVector FCityEnvironmentCelestial::HorizonToWorld(double AzimuthDegrees, double AltitudeDegrees, double NorthYawDegrees)
{
	if (!FMath::IsFinite(AzimuthDegrees) || !FMath::IsFinite(AltitudeDegrees) || !FMath::IsFinite(NorthYawDegrees))
	{
		return FVector::UpVector;
	}
	const double Azimuth = FMath::DegreesToRadians(AzimuthDegrees);
	const double Altitude = FMath::DegreesToRadians(AltitudeDegrees);
	const double CosAltitude = FMath::Cos(Altitude);
	const double North = CosAltitude * FMath::Cos(Azimuth);
	const double East = CosAltitude * FMath::Sin(Azimuth);
	const double Up = FMath::Sin(Altitude);
	const double Yaw = FMath::DegreesToRadians(NorthYawDegrees);
	const double CosYaw = FMath::Cos(Yaw);
	const double SinYaw = FMath::Sin(Yaw);
	FVector World(
		static_cast<float>(North * CosYaw - East * SinYaw),
		static_cast<float>(North * SinYaw + East * CosYaw),
		static_cast<float>(Up));
	if (!World.Normalize())
	{
		World = FVector::UpVector;
	}
	return World;
}

double FCityEnvironmentCelestial::DeepNightAmount(double Hour)
{
	Hour = WrapHour(Hour);
	if (Hour >= 23.0)
	{
		return SmoothStep(23.0, 23.5, Hour);
	}
	if (Hour < 4.0)
	{
		return 1.0;
	}
	if (Hour < 6.0)
	{
		return 1.0 - SmoothStep(4.0, 6.0, Hour);
	}
	return 0.0;
}

double FCityEnvironmentCelestial::MarketClosedAmount(double Hour)
{
	Hour = WrapHour(Hour);
	if (Hour >= 23.0)
	{
		return SmoothStep(23.0, 23.5, Hour);
	}
	if (Hour >= 18.0)
	{
		return 0.0;
	}
	if (Hour >= 16.0)
	{
		return 1.0 - SmoothStep(16.0, 18.0, Hour);
	}
	return 1.0;
}

double FCityEnvironmentCelestial::PathScheduleAt(double Hour)
{
	return FMath::Lerp(1.0, PathDeep, DeepNightAmount(Hour));
}

double FCityEnvironmentCelestial::FeatureScheduleAt(double Hour)
{
	return FMath::Lerp(1.0, FeatureDeep, DeepNightAmount(Hour));
}

double FCityEnvironmentCelestial::CampScheduleAt(double Hour)
{
	return FMath::Lerp(1.0, CampDeep, DeepNightAmount(Hour));
}

double FCityEnvironmentCelestial::MarketScheduleAt(double Hour)
{
	return 1.0 - MarketClosedAmount(Hour);
}

double FCityEnvironmentCelestial::SportScheduleAt(double Hour)
{
	return MarketScheduleAt(Hour);
}

bool FCityEnvironmentCelestial::NextFullMoonLocal(const FCityEnvironmentGeo& InGeo, const FDateTime& AfterLocal, FDateTime& OutLocal)
{
	FCityEnvironmentGeo Geo = InGeo;
	Geo.Sanitize();
	astro_time_t Start;
	if (!MakeAstroTime(ToUtc(AfterLocal, Geo.UtcOffsetHours), Start))
	{
		return false;
	}
	const astro_search_result_t Found = Astronomy_SearchMoonPhase(180.0, Start, 40.0);
	if (Found.status != ASTRO_SUCCESS)
	{
		return false;
	}
	FDateTime Utc;
	if (!FromAstroTime(Found.time, Utc))
	{
		return false;
	}
	OutLocal = ToLocal(Utc, Geo.UtcOffsetHours);
	return OutLocal > AfterLocal || OutLocal == AfterLocal;
}

bool FCityEnvironmentCelestial::ComputeRiseSet(ECityCelestialBody Body, const FCityEnvironmentGeo& InGeo, const FDateTime& LocalMidnight, FCityRiseSet& Out)
{
	Out = FCityRiseSet();
	FCityEnvironmentGeo Geo = InGeo;
	Geo.Sanitize();
	astro_time_t Start;
	if (!MakeAstroTime(ToUtc(LocalMidnight.GetDate(), Geo.UtcOffsetHours), Start))
	{
		return false;
	}
	const astro_body_t AstroBody = Body == ECityCelestialBody::Sun ? BODY_SUN : BODY_MOON;
	const astro_observer_t Observer = MakeObserver(Geo);
	const astro_search_result_t Rise = Astronomy_SearchRiseSetEx(AstroBody, Observer, DIRECTION_RISE, Start, 1.2, 0.0);
	const astro_search_result_t Set = Astronomy_SearchRiseSetEx(AstroBody, Observer, DIRECTION_SET, Start, 1.2, 0.0);
	if (Rise.status == ASTRO_SUCCESS && FromAstroTime(Rise.time, Out.RiseUtc))
	{
		Out.bRise = true;
	}
	if (Set.status == ASTRO_SUCCESS && FromAstroTime(Set.time, Out.SetUtc))
	{
		Out.bSet = true;
	}
	if (Out.bRise && Out.bSet)
	{
		double Hours = (Out.SetUtc - Out.RiseUtc).GetTotalHours();
		if (Hours < 0.0)
		{
			Hours += 24.0;
		}
		Out.DayLengthHours = Hours;
	}
	return Out.bRise && Out.bSet;
}

FCityEnvironmentSample FCityEnvironmentCelestial::Evaluate(const FDateTime& Local, const FCityEnvironmentGeo& InGeo, bool bIncludeRiseSet)
{
	FCityEnvironmentSample Sample;
	Sample.LocalDateTime = Local;
	FCityEnvironmentGeo Geo = InGeo;
	Geo.Sanitize();
	Sample.UtcDateTime = ToUtc(Local, Geo.UtcOffsetHours);
	Sample.Hour24 = HourOfDay(Local);
	astro_time_t Time;
	if (!MakeAstroTime(Sample.UtcDateTime, Time))
	{
		return Sample;
	}
	const astro_observer_t Observer = MakeObserver(Geo);
	if (!BodySky(BODY_SUN, Time, Observer, Geo.NorthYawDegrees, REFRACTION_NORMAL, Sample.Sun))
	{
		return Sample;
	}
	if (!BodySky(BODY_MOON, Time, Observer, Geo.NorthYawDegrees, REFRACTION_NORMAL, Sample.Moon))
	{
		return Sample;
	}
	const astro_angle_result_t Phase = Astronomy_MoonPhase(Time);
	const astro_illum_t Illumination = Astronomy_Illumination(BODY_MOON, Time);
	if (Phase.status != ASTRO_SUCCESS || Illumination.status != ASTRO_SUCCESS)
	{
		return Sample;
	}
	Sample.MoonPhaseAngleDegrees = Phase.angle;
	Sample.MoonIlluminatedFraction = FMath::Clamp(Illumination.phase_fraction, 0.0, 1.0);
	const double Dot = FMath::Clamp(static_cast<double>(FVector::DotProduct(Sample.Sun.Direction, Sample.Moon.Direction)), -1.0, 1.0);
	Sample.SunMoonSeparationDegrees = FMath::RadiansToDegrees(FMath::Acos(Dot));
	FVector Bright = Sample.Sun.Direction - Sample.Moon.Direction * static_cast<float>(Dot);
	if (!Bright.Normalize())
	{
		Bright = Sample.Sun.Direction;
	}
	Sample.MoonBrightDirection = Bright;

	const double SunAltitude = Sample.Sun.AltitudeDegrees;
	const double MoonAltitude = Sample.Moon.AltitudeDegrees;
	Sample.NightWeight = 1.0 - SmoothStep(-8.0, 3.0, SunAltitude);
	Sample.DayWeight = 1.0 - Sample.NightWeight;
	const double SunAbove = SmoothStep(0.0, 40.0, SunAltitude);
	Sample.SunLux = SunAltitude <= 0.0 ? 0.0 : SunNoonLux * SunAbove;
	const double MoonAbove = SmoothStep(0.0, 3.0, MoonAltitude);
	Sample.MoonLux = MoonAltitude <= 0.0 ? 0.0 : MoonArtLux * Sample.MoonIlluminatedFraction * MoonAbove * Sample.NightWeight;
	Sample.BounceLux = NightBounceLux * Sample.NightWeight;
	Sample.StreetFillScale = Sample.DayWeight * (Sample.SunLux / SunNoonLux);
	// Unit-radiance authored ambient maps follow the visible sky's log radiance
	// curve. This supplies twilight diffuse light when direct sun has set,
	// instead of retaining a daytime EV range over an almost unlit world.
	Sample.SkyLightIntensity = FMath::Lerp(DaySkyIntensity, NightSkyIntensity, Sample.NightWeight) * FMath::Pow(6500.0, Sample.DayWeight);
	const double Warm = 1.0 - SmoothStep(0.0, 18.0, FMath::Max(0.0, SunAltitude));
	Sample.SunTemperatureKelvin = FMath::Lerp(5800.0, 2500.0, Warm);
	// Bounded night adaptation retains the dark sky instead of metering the
	// entire moonlit street back to the same middle grey as daytime.
	Sample.EvMin = FMath::Lerp(10.0, -1.0, Sample.NightWeight);
	Sample.EvMax = FMath::Lerp(15.0, 3.0, Sample.NightWeight);
	Sample.PathSchedule = PathScheduleAt(Sample.Hour24);
	Sample.FeatureSchedule = FeatureScheduleAt(Sample.Hour24);
	Sample.CampSchedule = CampScheduleAt(Sample.Hour24);
	Sample.MarketSchedule = MarketScheduleAt(Sample.Hour24);
	Sample.SportSchedule = SportScheduleAt(Sample.Hour24);
	Sample.SignGlowWeight = Sample.NightWeight * FMath::Lerp(1.0, SignClosed, MarketClosedAmount(Sample.Hour24));
	Sample.LampGlowWeight = Sample.NightWeight * Sample.PathSchedule;
	const double DiscAbove = SmoothStep(-0.25, 1.5, MoonAltitude);
	Sample.MoonDiscVisibility = DiscAbove * (1.0 - SmoothStep(0.0, 10.0, SunAltitude));
	Sample.bValid = true;
	if (bIncludeRiseSet)
	{
		ComputeRiseSet(ECityCelestialBody::Sun, Geo, Local, Sample.SunRiseSet);
		ComputeRiseSet(ECityCelestialBody::Moon, Geo, Local, Sample.MoonRiseSet);
	}
	return Sample;
}

FString FCityEnvironmentCelestial::BuildStateJson(const FCityEnvironmentSample& Sample, const FCityEnvironmentGeo& Geo, bool bPaused, double TimeScale, double MinutesPerDay)
{
	FString Json;
	Json.Reserve(2048);
	Json += TEXT("{\"valid\":");
	Json += Sample.bValid ? TEXT("true") : TEXT("false");
	Json += TEXT(",\"localDateTime\":\"");
	Json += ToIso8601(Sample.LocalDateTime);
	Json += TEXT("\",\"utcDateTime\":\"");
	Json += ToIso8601(Sample.UtcDateTime);
	Json += TEXT("\",\"hour24\":");
	Json += Num(Sample.Hour24, 6);
	Json += TEXT(",\"paused\":");
	Json += bPaused ? TEXT("true") : TEXT("false");
	Json += TEXT(",\"timeScale\":");
	Json += Num(TimeScale, 6);
	Json += TEXT(",\"minutesPerDay\":");
	Json += Num(MinutesPerDay, 4);
	Json += TEXT(",\"latitude\":");
	Json += Num(Geo.Latitude, 6);
	Json += TEXT(",\"longitude\":");
	Json += Num(Geo.Longitude, 6);
	Json += TEXT(",\"utcOffsetHours\":");
	Json += Num(Geo.UtcOffsetHours, 4);
	Json += TEXT(",\"northYawDegrees\":");
	Json += Num(Geo.NorthYawDegrees, 4);
	Json += TEXT(",\"refraction\":\"REFRACTION_NORMAL\",\"equator\":\"EQUATOR_OF_DATE\",\"aberration\":\"ABERRATION\"");
	Json += TEXT(",\"frame\":\"topocentric apparent horizon; azimuth 0=north 90=east; UE +X north +Y east +Z up yawed by northYawDegrees\"");
	Json += TEXT(",\"nightWeight\":");
	Json += Num(Sample.NightWeight, 6);
	Json += TEXT(",\"dayWeight\":");
	Json += Num(Sample.DayWeight, 6);
	Json += TEXT(",\"signGlowWeight\":");
	Json += Num(Sample.SignGlowWeight, 6);
	Json += TEXT(",\"lampGlowWeight\":");
	Json += Num(Sample.LampGlowWeight, 6);
	Json += TEXT(",\"streetFillScale\":");
	Json += Num(Sample.StreetFillScale, 6);
	Json += TEXT(",\"skyLight\":");
	Json += Num(Sample.SkyLightIntensity, 6);
	Json += TEXT(",\"evMin\":");
	Json += Num(Sample.EvMin, 4);
	Json += TEXT(",\"evMax\":");
	Json += Num(Sample.EvMax, 4);
	Json += TEXT(",\"groups\":{\"path\":");
	Json += Num(Sample.PathSchedule, 6);
	Json += TEXT(",\"feature\":");
	Json += Num(Sample.FeatureSchedule, 6);
	Json += TEXT(",\"market\":");
	Json += Num(Sample.MarketSchedule, 6);
	Json += TEXT(",\"sport\":");
	Json += Num(Sample.SportSchedule, 6);
	Json += TEXT(",\"camp\":");
	Json += Num(Sample.CampSchedule, 6);
	Json += TEXT("},\"sun\":{\"azimuth\":");
	Json += Num(Sample.Sun.AzimuthDegrees, 6);
	Json += TEXT(",\"altitude\":");
	Json += Num(Sample.Sun.AltitudeDegrees, 6);
	Json += TEXT(",\"direction\":");
	Json += Vec(Sample.Sun.Direction);
	Json += TEXT(",\"lux\":");
	Json += Num(Sample.SunLux, 4);
	Json += TEXT(",\"temperature\":");
	Json += Num(Sample.SunTemperatureKelvin, 2);
	Json += TEXT(",\"riseSet\":");
	Json += RiseJson(Sample.SunRiseSet);
	Json += TEXT("},\"moon\":{\"azimuth\":");
	Json += Num(Sample.Moon.AzimuthDegrees, 6);
	Json += TEXT(",\"altitude\":");
	Json += Num(Sample.Moon.AltitudeDegrees, 6);
	Json += TEXT(",\"direction\":");
	Json += Vec(Sample.Moon.Direction);
	Json += TEXT(",\"phaseAngle\":");
	Json += Num(Sample.MoonPhaseAngleDegrees, 6);
	Json += TEXT(",\"illuminatedFraction\":");
	Json += Num(Sample.MoonIlluminatedFraction, 6);
	Json += TEXT(",\"brightDirection\":");
	Json += Vec(Sample.MoonBrightDirection);
	Json += TEXT(",\"lux\":");
	Json += Num(Sample.MoonLux, 6);
	Json += TEXT(",\"discVisibility\":");
	Json += Num(Sample.MoonDiscVisibility, 6);
	Json += TEXT(",\"separationFromSun\":");
	Json += Num(Sample.SunMoonSeparationDegrees, 6);
	Json += TEXT(",\"riseSet\":");
	Json += RiseJson(Sample.MoonRiseSet);
	Json += TEXT("}}");
	return Json;
}

bool FCityEnvironmentCelestial::TestMidnight(FString& Detail)
{
	const FDateTime Start(2026, 10, 22, 23, 59, 59);
	const FDateTime Next = AddGameSeconds(Start, 1.0);
	const FDateTime Expected(2026, 10, 23, 0, 0, 0);
	if (Next != Expected)
	{
		Detail = FString::Printf(TEXT("got %s"), *ToIso8601(Next));
		return false;
	}
	const FDateTime ByScale = AdvanceRealTime(FDateTime(2026, 10, 22, 23, 0, 0), 150.0, 60.0, 1.0);
	if (ByScale != FDateTime(2026, 10, 23, 0, 0, 0))
	{
		Detail = FString::Printf(TEXT("scaled midnight %s"), *ToIso8601(ByScale));
		return false;
	}
	const FDateTime Hour24 = SetHourOnDate(FDateTime(2026, 10, 22, 15, 30, 0), 24.0);
	if (Hour24 != FDateTime(2026, 10, 23, 0, 0, 0))
	{
		Detail = FString::Printf(TEXT("hour 24 %s"), *ToIso8601(Hour24));
		return false;
	}
	const FDateTime Hour26 = SetHourOnDate(FDateTime(2026, 10, 22, 1, 0, 0), 26.5);
	if (Hour26 != FDateTime(2026, 10, 23, 2, 30, 0))
	{
		Detail = FString::Printf(TEXT("hour 26.5 %s"), *ToIso8601(Hour26));
		return false;
	}
	const FDateTime Negative = SetHourOnDate(FDateTime(2026, 10, 22, 12, 0, 0), -1.0);
	if (Negative != FDateTime(2026, 10, 21, 23, 0, 0))
	{
		Detail = FString::Printf(TEXT("hour -1 %s"), *ToIso8601(Negative));
		return false;
	}
	Detail = ToIso8601(Next);
	return true;
}

bool FCityEnvironmentCelestial::TestLeapDay(FString& Detail)
{
	const FDateTime LeapStart(2028, 2, 28, 23, 59, 59);
	const FDateTime LeapNext = AddGameSeconds(LeapStart, 1.0);
	if (LeapNext != FDateTime(2028, 2, 29, 0, 0, 0))
	{
		Detail = FString::Printf(TEXT("into leap day %s"), *ToIso8601(LeapNext));
		return false;
	}
	const FDateTime LeapOut = AddGameSeconds(FDateTime(2028, 2, 29, 23, 59, 59), 1.0);
	if (LeapOut != FDateTime(2028, 3, 1, 0, 0, 0))
	{
		Detail = FString::Printf(TEXT("out of leap day %s"), *ToIso8601(LeapOut));
		return false;
	}
	const FDateTime Common = AddGameSeconds(FDateTime(2027, 2, 28, 23, 59, 59), 1.0);
	if (Common != FDateTime(2027, 3, 1, 0, 0, 0))
	{
		Detail = FString::Printf(TEXT("common year %s"), *ToIso8601(Common));
		return false;
	}
	const FDateTime HourWrap = SetHourOnDate(FDateTime(2028, 2, 28, 8, 0, 0), 24.0);
	if (HourWrap != FDateTime(2028, 2, 29, 0, 0, 0))
	{
		Detail = FString::Printf(TEXT("leap hour 24 %s"), *ToIso8601(HourWrap));
		return false;
	}
	const FDateTime Rewind = AddGameSeconds(FDateTime(2028, 3, 1, 0, 0, 0), -1.0);
	if (Rewind != FDateTime(2028, 2, 29, 23, 59, 59))
	{
		Detail = FString::Printf(TEXT("rewind leap %s"), *ToIso8601(Rewind));
		return false;
	}
	Detail = ToIso8601(LeapNext);
	return true;
}

bool FCityEnvironmentCelestial::TestSeek(FString& Detail)
{
	FCityEnvironmentGeo Geo;
	const FDateTime Day(2026, 11, 5);
	const FDateTime Noon = SetHourOnDate(Day, 12.0);
	const FDateTime Night = SetHourOnDate(Day, 2.0);
	const FDateTime Dusk = SetHourOnDate(Day, 18.5);
	const FCityEnvironmentSample FirstNight = Evaluate(Night, Geo, false);
	const FCityEnvironmentSample NoonSample = Evaluate(Noon, Geo, false);
	const FCityEnvironmentSample DuskSample = Evaluate(Dusk, Geo, false);
	const FCityEnvironmentSample SecondNight = Evaluate(Night, Geo, false);
	if (!FirstNight.bValid || !NoonSample.bValid || !DuskSample.bValid || !SecondNight.bValid)
	{
		Detail = TEXT("evaluate failed");
		return false;
	}
	if (!SameSample(FirstNight, SecondNight, Detail))
	{
		return false;
	}
	if (FMath::Abs(NoonSample.Sun.AltitudeDegrees - Night.GetHour()) < 1.0 && NoonSample.Sun.AltitudeDegrees < 20.0)
	{
		Detail = TEXT("noon sun unexpectedly low");
		return false;
	}
	if (!(NoonSample.Sun.AltitudeDegrees > Night.GetHour() && NoonSample.SunLux > FirstNight.SunLux))
	{
		Detail = FString::Printf(TEXT("noon alt %s night alt %s"), *Num(NoonSample.Sun.AltitudeDegrees, 3), *Num(FirstNight.Sun.AltitudeDegrees, 3));
		return false;
	}
	if (FVector::DotProduct(NoonSample.Sun.Direction, DuskSample.Sun.Direction) > 0.995f)
	{
		Detail = TEXT("seek did not move the sun");
		return false;
	}
	const FCityEnvironmentSample Repeated = Evaluate(Night, Geo, false);
	return SameSample(FirstNight, Repeated, Detail);
}

bool FCityEnvironmentCelestial::TestNormalTime(FString& Detail)
{
	const FDateTime Start(2026, 6, 21, 8, 15, 0);
	const FDateTime OneDay = AdvanceRealTime(Start, 3600.0, 60.0, 1.0);
	if (OneDay != FDateTime(2026, 6, 22, 8, 15, 0))
	{
		Detail = FString::Printf(TEXT("60 real minutes %s"), *ToIso8601(OneDay));
		return false;
	}
	const FDateTime Fast = AdvanceRealTime(Start, 150.0, 60.0, 24.0);
	if (Fast != OneDay)
	{
		Detail = FString::Printf(TEXT("24x %s"), *ToIso8601(Fast));
		return false;
	}
	const FDateTime Half = AdvanceRealTime(Start, 900.0, 30.0, 1.0);
	if (Half != FDateTime(2026, 6, 21, 20, 15, 0) || AdvanceRealTime(Start, 1800.0, 30.0, 1.0) != OneDay)
	{
		Detail = FString::Printf(TEXT("30 min/day %s"), *ToIso8601(Half));
		return false;
	}
	if (AdvanceRealTime(Start, 3600.0, 60.0, 0.0) != Start)
	{
		Detail = TEXT("zero scale moved");
		return false;
	}
	if (AdvanceRealTime(Start, 120.0, 60.0, -1.0) != AddGameSeconds(Start, -120.0 * 24.0))
	{
		Detail = TEXT("reverse scale mismatch");
		return false;
	}
	Detail = ToIso8601(OneDay);
	return true;
}

bool FCityEnvironmentCelestial::TestMoonPhase(FString& Detail)
{
	FCityEnvironmentGeo Geo;
	const FDateTime After(2026, 10, 22);
	FDateTime FullLocal;
	if (!NextFullMoonLocal(Geo, After, FullLocal))
	{
		Detail = TEXT("full moon search failed");
		return false;
	}
	if (FullLocal <= After)
	{
		Detail = ToIso8601(FullLocal);
		return false;
	}
	const FCityEnvironmentSample Full = Evaluate(FullLocal, Geo, false);
	if (!Full.bValid || FMath::Abs(Full.MoonPhaseAngleDegrees - 180.0) > 0.05 || Full.MoonIlluminatedFraction < 0.99)
	{
		Detail = FString::Printf(TEXT("full %s phase %s illum %s"), *ToIso8601(FullLocal), *Num(Full.MoonPhaseAngleDegrees, 4), *Num(Full.MoonIlluminatedFraction, 4));
		return false;
	}
	if (FVector::DotProduct(Full.Sun.Direction, Full.Moon.Direction) > -0.8f)
	{
		Detail = TEXT("full moon is not opposite the sun");
		return false;
	}
	astro_time_t Start;
	if (!MakeAstroTime(ToUtc(After, Geo.UtcOffsetHours), Start))
	{
		Detail = TEXT("bad start");
		return false;
	}
	const astro_search_result_t Quarter = Astronomy_SearchMoonPhase(90.0, Start, 40.0);
	const astro_search_result_t NewMoon = Astronomy_SearchMoonPhase(0.0, Start, 40.0);
	FDateTime QuarterUtc;
	FDateTime NewUtc;
	if (Quarter.status != ASTRO_SUCCESS || NewMoon.status != ASTRO_SUCCESS || !FromAstroTime(Quarter.time, QuarterUtc) || !FromAstroTime(NewMoon.time, NewUtc))
	{
		Detail = TEXT("quarter search failed");
		return false;
	}
	const FCityEnvironmentSample First = Evaluate(ToLocal(QuarterUtc, Geo.UtcOffsetHours), Geo, false);
	const FCityEnvironmentSample Dark = Evaluate(ToLocal(NewUtc, Geo.UtcOffsetHours), Geo, false);
	if (!First.bValid || !Dark.bValid || First.MoonIlluminatedFraction < 0.45 || First.MoonIlluminatedFraction > 0.55 || Dark.MoonIlluminatedFraction > 0.02)
	{
		Detail = FString::Printf(TEXT("quarter illum %s new %s"), *Num(First.MoonIlluminatedFraction, 4), *Num(Dark.MoonIlluminatedFraction, 4));
		return false;
	}
	if (FMath::Abs(First.SunMoonSeparationDegrees - 90.0) > 20.0)
	{
		Detail = FString::Printf(TEXT("quarter separation %s"), *Num(First.SunMoonSeparationDegrees, 3));
		return false;
	}
	const FCityEnvironmentSample Later = Evaluate(AddGameSeconds(FullLocal, 6.0 * 3600.0), Geo, false);
	if (!Later.bValid || FMath::Abs(Later.Moon.AzimuthDegrees - Full.Moon.AzimuthDegrees) < 1.0)
	{
		Detail = TEXT("moon azimuth did not move");
		return false;
	}
	Detail = ToIso8601(FullLocal);
	return true;
}

bool FCityEnvironmentCelestial::TestSeasons(FString& Detail)
{
	FCityEnvironmentGeo Geo;
	const astro_seasons_t Seasons = Astronomy_Seasons(2026);
	if (Seasons.status != ASTRO_SUCCESS)
	{
		Detail = TEXT("seasons failed");
		return false;
	}
	FDateTime MarchUtc;
	FDateTime JuneUtc;
	FDateTime DecemberUtc;
	if (!FromAstroTime(Seasons.mar_equinox, MarchUtc) || !FromAstroTime(Seasons.jun_solstice, JuneUtc) || !FromAstroTime(Seasons.dec_solstice, DecemberUtc))
	{
		Detail = TEXT("season dates failed");
		return false;
	}
	FCityRiseSet March;
	FCityRiseSet June;
	FCityRiseSet December;
	if (!ComputeRiseSet(ECityCelestialBody::Sun, Geo, ToLocal(MarchUtc, Geo.UtcOffsetHours), March)
		|| !ComputeRiseSet(ECityCelestialBody::Sun, Geo, ToLocal(JuneUtc, Geo.UtcOffsetHours), June)
		|| !ComputeRiseSet(ECityCelestialBody::Sun, Geo, ToLocal(DecemberUtc, Geo.UtcOffsetHours), December))
	{
		Detail = TEXT("rise/set failed");
		return false;
	}
	if (March.DayLengthHours < 11.5 || March.DayLengthHours > 12.5)
	{
		Detail = FString::Printf(TEXT("equinox day %s"), *Num(March.DayLengthHours, 3));
		return false;
	}
	if (!(June.DayLengthHours > March.DayLengthHours + 0.4 && March.DayLengthHours > December.DayLengthHours + 0.4))
	{
		Detail = FString::Printf(TEXT("june %s march %s december %s"), *Num(June.DayLengthHours, 3), *Num(March.DayLengthHours, 3), *Num(December.DayLengthHours, 3));
		return false;
	}
	const FCityEnvironmentSample JuneNoon = Evaluate(SetHourOnDate(ToLocal(JuneUtc, Geo.UtcOffsetHours), 12.0), Geo, false);
	const FCityEnvironmentSample DecemberNoon = Evaluate(SetHourOnDate(ToLocal(DecemberUtc, Geo.UtcOffsetHours), 12.0), Geo, false);
	if (!JuneNoon.bValid || !DecemberNoon.bValid || !(JuneNoon.Sun.AltitudeDegrees > DecemberNoon.Sun.AltitudeDegrees + 10.0))
	{
		Detail = TEXT("noon altitude did not change with season");
		return false;
	}
	Detail = FString::Printf(TEXT("june %s h december %s h"), *Num(June.DayLengthHours, 2), *Num(December.DayLengthHours, 2));
	return true;
}

bool FCityEnvironmentCelestial::TestBelowHorizon(FString& Detail)
{
	FCityEnvironmentGeo Geo;
	const FCityEnvironmentSample Midnight = Evaluate(FDateTime(2026, 11, 24, 0, 30, 0), Geo, false);
	const FCityEnvironmentSample Noon = Evaluate(FDateTime(2026, 11, 24, 12, 0, 0), Geo, false);
	if (!Midnight.bValid || !Noon.bValid)
	{
		Detail = TEXT("evaluate failed");
		return false;
	}
	if (Midnight.Sun.AltitudeDegrees >= 0.0 || Midnight.SunLux != 0.0 || Midnight.NightWeight < 0.999 || Midnight.BounceLux < 2.39 || Midnight.SkyLightIntensity > NightSkyIntensity + 0.01)
	{
		Detail = FString::Printf(TEXT("midnight alt %s lux %s night %s"), *Num(Midnight.Sun.AltitudeDegrees, 3), *Num(Midnight.SunLux, 3), *Num(Midnight.NightWeight, 3));
		return false;
	}
	if (Midnight.Moon.AltitudeDegrees <= 0.0 && Midnight.MoonLux != 0.0)
	{
		Detail = TEXT("moon lux leaked below the horizon");
		return false;
	}
	if (Noon.Sun.AltitudeDegrees <= 40.0 || Noon.SunLux < 70000.0 || Noon.NightWeight > 0.001 || Noon.BounceLux > 0.01 || Noon.StreetFillScale < 0.8 || Noon.SkyLightIntensity < 2.49)
	{
		Detail = FString::Printf(TEXT("noon alt %s lux %s"), *Num(Noon.Sun.AltitudeDegrees, 3), *Num(Noon.SunLux, 1));
		return false;
	}
	if (Noon.Moon.AltitudeDegrees <= 0.0 && Noon.MoonLux != 0.0)
	{
		Detail = TEXT("noon moon lux below horizon");
		return false;
	}
	Detail = FString::Printf(TEXT("midnight lux 0 noon %s"), *Num(Noon.SunLux, 0));
	return true;
}

bool FCityEnvironmentCelestial::TestSchedules(FString& Detail)
{
	if (!NearlyEqual(PathScheduleAt(2.0), 0.7, 1e-9) || !NearlyEqual(PathScheduleAt(12.0), 1.0, 1e-9) || !NearlyEqual(PathScheduleAt(21.0), 1.0, 1e-9))
	{
		Detail = TEXT("path anchors");
		return false;
	}
	if (!NearlyEqual(FeatureScheduleAt(2.0), 0.45, 1e-9) || !NearlyEqual(CampScheduleAt(2.0), 0.4, 1e-9))
	{
		Detail = TEXT("feature/camp anchors");
		return false;
	}
	if (!NearlyEqual(MarketScheduleAt(2.0), 0.0, 1e-9) || !NearlyEqual(MarketScheduleAt(21.0), 1.0, 1e-9) || !NearlyEqual(SportScheduleAt(2.0), 0.0, 1e-9) || !NearlyEqual(SportScheduleAt(21.0), 1.0, 1e-9))
	{
		Detail = TEXT("market/sport anchors");
		return false;
	}
	if (FMath::Abs(PathScheduleAt(23.99) - PathScheduleAt(0.01)) > 0.02)
	{
		Detail = TEXT("midnight path step");
		return false;
	}
	double PreviousPath = PathScheduleAt(22.0);
	double PreviousFeature = FeatureScheduleAt(22.0);
	double PreviousMarket = MarketScheduleAt(22.0);
	double PreviousSport = SportScheduleAt(22.0);
	double PreviousCamp = CampScheduleAt(22.0);
	for (int32 Minute = 1; Minute <= (8 * 60 + 30); ++Minute)
	{
		const double Hour = 22.0 + static_cast<double>(Minute) / 60.0;
		const double Path = PathScheduleAt(Hour);
		const double Feature = FeatureScheduleAt(Hour);
		const double Market = MarketScheduleAt(Hour);
		const double Sport = SportScheduleAt(Hour);
		const double Camp = CampScheduleAt(Hour);
		if (FMath::Abs(Path - PreviousPath) > 0.06 || FMath::Abs(Feature - PreviousFeature) > 0.06 || FMath::Abs(Market - PreviousMarket) > 0.06 || FMath::Abs(Sport - PreviousSport) > 0.06 || FMath::Abs(Camp - PreviousCamp) > 0.06)
		{
			Detail = FString::Printf(TEXT("step at %s"), *Num(WrapHour(Hour), 3));
			return false;
		}
		PreviousPath = Path;
		PreviousFeature = Feature;
		PreviousMarket = Market;
		PreviousSport = Sport;
		PreviousCamp = Camp;
	}
	if (!(PathScheduleAt(2.0) > MarketScheduleAt(2.0) + 0.5))
	{
		Detail = TEXT("path was closed with the market");
		return false;
	}
	Detail = TEXT("continuous");
	return true;
}

bool FCityEnvironmentCelestial::TestRefraction(FString& Detail)
{
	FCityEnvironmentGeo Geo;
	Geo.Sanitize();
	bool bFound = false;
	double Geometric = 0.0;
	double Apparent = 0.0;
	for (int32 Hour = 0; Hour < 24 && !bFound; ++Hour)
	{
		const FDateTime Local(2026, 3, 20, Hour, 20, 0);
		astro_time_t Time;
		if (!MakeAstroTime(ToUtc(Local, Geo.UtcOffsetHours), Time))
		{
			continue;
		}
		const astro_observer_t Observer = MakeObserver(Geo);
		FCityBodySky Airless;
		FCityBodySky Normal;
		if (!BodySky(BODY_SUN, Time, Observer, 0.0, REFRACTION_NONE, Airless) || !BodySky(BODY_SUN, Time, Observer, 0.0, REFRACTION_NORMAL, Normal))
		{
			continue;
		}
		if (Airless.AltitudeDegrees > 2.0 && Airless.AltitudeDegrees < 20.0)
		{
			bFound = true;
			Geometric = Airless.AltitudeDegrees;
			Apparent = Normal.AltitudeDegrees;
		}
	}
	if (!bFound)
	{
		Detail = TEXT("no low-sun sample");
		return false;
	}
	if (!(Apparent > Geometric))
	{
		Detail = FString::Printf(TEXT("apparent %s geometric %s"), *Num(Apparent, 4), *Num(Geometric, 4));
		return false;
	}
	Detail = FString::Printf(TEXT("apparent-geometric %s deg"), *Num(Apparent - Geometric, 4));
	return true;
}

bool FCityEnvironmentCelestial::TestFrame(FString& Detail)
{
	const FVector North = HorizonToWorld(0.0, 0.0, 0.0);
	const FVector East = HorizonToWorld(90.0, 0.0, 0.0);
	const FVector Up = HorizonToWorld(0.0, 90.0, 0.0);
	const FVector YawedNorth = HorizonToWorld(0.0, 0.0, 90.0);
	const FVector YawedEast = HorizonToWorld(90.0, 0.0, 90.0);
	if (!North.Equals(FVector::ForwardVector, 1e-4f) || !East.Equals(FVector::RightVector, 1e-4f) || !Up.Equals(FVector::UpVector, 1e-4f))
	{
		Detail = TEXT("identity frame");
		return false;
	}
	if (!YawedNorth.Equals(FVector::RightVector, 1e-4f) || !YawedEast.Equals(-FVector::ForwardVector, 1e-4f))
	{
		Detail = TEXT("yaw frame");
		return false;
	}
	Detail = TEXT("+X north +Y east +Z up");
	return true;
}

FString FCityEnvironmentCelestial::RunSelfTests()
{
	struct FCase
	{
		const TCHAR* Name;
		bool (*Run)(FString&);
	};
	const FCase Cases[] = {
		{TEXT("midnight"), &FCityEnvironmentCelestial::TestMidnight},
		{TEXT("leapday"), &FCityEnvironmentCelestial::TestLeapDay},
		{TEXT("seek"), &FCityEnvironmentCelestial::TestSeek},
		{TEXT("normalTime"), &FCityEnvironmentCelestial::TestNormalTime},
		{TEXT("moonPhase"), &FCityEnvironmentCelestial::TestMoonPhase},
		{TEXT("seasons"), &FCityEnvironmentCelestial::TestSeasons},
		{TEXT("belowHorizon"), &FCityEnvironmentCelestial::TestBelowHorizon},
		{TEXT("schedules"), &FCityEnvironmentCelestial::TestSchedules},
		{TEXT("refraction"), &FCityEnvironmentCelestial::TestRefraction},
		{TEXT("frame"), &FCityEnvironmentCelestial::TestFrame}
	};
	int32 Failed = 0;
	FString Results;
	for (const FCase& Case : Cases)
	{
		FString Detail;
		bool bPassed = false;
		bPassed = Case.Run(Detail);
		if (!bPassed)
		{
			++Failed;
			UE_LOG(LogCityEnvironment, Warning, TEXT("Clock self-test %s failed: %s"), Case.Name, *Detail);
		}
		if (!Results.IsEmpty())
		{
			Results += TEXT(",");
		}
		Results += FString::Printf(TEXT("{\"name\":\"%s\",\"passed\":%s,\"detail\":\"%s\"}"), Case.Name, bPassed ? TEXT("true") : TEXT("false"), *EscapeJson(Detail));
	}
	const bool bAll = Failed == 0;
	return FString::Printf(TEXT("{\"passed\":%s,\"failed\":%d,\"results\":[%s]}"), bAll ? TEXT("true") : TEXT("false"), Failed, *Results);
}
