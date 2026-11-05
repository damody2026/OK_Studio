#include "OKStudioCharacterStyle.h"
#include "OKSceneDocument.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioCharacterStyleTest, "OpenKoikatsu.Studio.CharacterStyle", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKStudioCharacterStyleTest::RunTest(const FString&)
{
	TArray<float> CardBody, CardFace;
	CardBody.Init(0.5f, 44);
	CardFace.Init(0.5f, 52);
	TArray<float> Body = CardBody, Face = CardFace;
	OKStudioStyleSliders(0.f, Body, Face);
	TestTrue(TEXT("style 0 is the card"), Body == CardBody && Face == CardFace);

	OKStudioStyleSliders(1.f, Body, Face);
	TestTrue(TEXT("chibi: shorter, bigger head, smaller breasts"), Body[0] < CardBody[0] && Body[1] > CardBody[1] && Body[4] < CardBody[4]);
	TestTrue(TEXT("chibi: wider face, bigger eyes"), Face[0] > CardFace[0] && Face[34] > CardFace[34]);

	TArray<float> Half = CardBody, HalfFace = CardFace;
	OKStudioStyleSliders(0.5f, Half, HalfFace);
	TestTrue(TEXT("the slider moves between the card and the style"), FMath::IsNearlyEqual(Half[0], (CardBody[0] + Body[0]) * 0.5f, 1.e-4f));

	TArray<float> Real = CardBody, RealFace = CardFace;
	OKStudioStyleSliders(-1.f, Real, RealFace);
	TestTrue(TEXT("realistic: taller, smaller head, bigger breasts, smaller eyes"), Real[0] > CardBody[0] && Real[1] < CardBody[1] && Real[4] > CardBody[4] && RealFace[34] < CardFace[34]);

	TArray<float> Short, ShortFace;
	OKStudioStyleSliders(1.f, Short, ShortFace);
	TestTrue(TEXT("no sliders stay none"), Short.IsEmpty() && ShortFace.IsEmpty());

	TestTrue(TEXT("a key not holding a style leaves the character's"), FOKSceneKey().Style < -1.f);
	return true;
}
#endif
