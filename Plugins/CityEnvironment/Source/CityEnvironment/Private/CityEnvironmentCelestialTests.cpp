#include "CityEnvironmentCelestial.h"
#include "CityEnvironmentSaveGame.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
	FCityEnvironmentCelestialTest,
	"CityEnvironment.Celestial",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::EngineFilter)

bool FCityEnvironmentCelestialTest::RunTest(const FString& Parameters)
{
	(void)Parameters;
	const bool bSlotBefore = UGameplayStatics::DoesSaveGameExist(UCityEnvironmentSaveGame::SlotName(), 0);
	const FString Json = FCityEnvironmentCelestial::RunSelfTests();
	const bool bSlotAfter = UGameplayStatics::DoesSaveGameExist(UCityEnvironmentSaveGame::SlotName(), 0);

	TestTrue(TEXT("self-test json passed"), Json.StartsWith(TEXT("{\"passed\":true,")));
	TestTrue(TEXT("failed count is zero"), Json.Contains(TEXT("\"failed\":0")));
	TestFalse(TEXT("no failing case"), Json.Contains(TEXT("\"passed\":false")));
	TestTrue(TEXT("save slot unchanged"), bSlotBefore == bSlotAfter);

	const TCHAR* Required[] = {
		TEXT("\"name\":\"midnight\""),
		TEXT("\"name\":\"leapday\""),
		TEXT("\"name\":\"seek\""),
		TEXT("\"name\":\"normalTime\""),
		TEXT("\"name\":\"moonPhase\""),
		TEXT("\"name\":\"seasons\"")
	};
	for (const TCHAR* Name : Required)
	{
		TestTrue(FString::Printf(TEXT("contains %s"), Name), Json.Contains(Name));
	}
	if (!Json.StartsWith(TEXT("{\"passed\":true,")))
	{
		AddError(Json);
	}
	return true;
}

#endif
