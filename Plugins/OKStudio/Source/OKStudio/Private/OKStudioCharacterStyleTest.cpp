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
	TestTrue(TEXT("chibi: bigger head, smaller breasts"), Body[1] > CardBody[1] && Body[4] < CardBody[4]);
	TestTrue(TEXT("chibi: wider face, bigger eyes"), Face[0] > CardFace[0] && Face[34] > CardFace[34]);
	TestEqual(TEXT("chibi: at most half the breasts go"), Body[4], CardBody[4] * 0.5f);
	TestTrue(TEXT("chibi: a wide jaw only widens a little, the chin's tip rounds"), Face[9] <= CardFace[9] + OKStudioStyleTuning().ChibiJaw + 1.e-4f && Face[11] < CardFace[11] && Face[13] > CardFace[13]);

	TArray<float> Half = CardBody, HalfFace = CardFace;
	OKStudioStyleSliders(0.5f, Half, HalfFace);
	TestTrue(TEXT("the slider moves between the card and the style"), FMath::IsNearlyEqual(Half[1], (CardBody[1] + Body[1]) * 0.5f, 1.e-4f));

	TArray<float> Real = CardBody, RealFace = CardFace;
	OKStudioStyleSliders(-1.f, Real, RealFace);
	TestTrue(TEXT("realistic: smaller head, bigger breasts, smaller eyes"), Real[1] < CardBody[1] && Real[4] > CardBody[4] && RealFace[34] < CardFace[34]);

	TArray<float> Tall = CardBody, TallFace = CardFace;
	Tall[0] = 1.f;
	OKStudioStyleSliders(-1.f, Tall, TallFace);
	TestTrue(TEXT("a tall card needs less of a head change for its heads"), Tall[1] > Real[1]);

	// The narrower the card's jaw, the less the realistic end takes it towards its own.
	TArray<float> NarrowBody = CardBody, NarrowFace = CardFace, WideBody = CardBody, WideFace = CardFace;
	NarrowFace[9] = 0.f;
	NarrowFace[16] = -0.4f;
	WideFace[9] = 0.3f;
	WideFace[16] = 0.25f;
	OKStudioStyleSliders(-1.f, NarrowBody, NarrowFace);
	OKStudioStyleSliders(-1.f, WideBody, WideFace);
	TestTrue(TEXT("realistic: a narrow jaw moves less than a wide one"), CardFace[0] - NarrowFace[0] < CardFace[0] - WideFace[0]);
	TestEqual(TEXT("the height slider stays the card's"), Real[0], CardBody[0]);
	TestTrue(TEXT("a style scales the character"), OKStudioStyleScale(1.f, CardBody, Body) < 1.f && OKStudioStyleScale(-1.f, CardBody, Real) > 1.f && OKStudioStyleScale(0.f, CardBody, CardBody) == 1.f);
	TestTrue(TEXT("no style, no bones"), OKStudioStyleBones(0.f, 1.f) == TEXT("[]") && OKStudioStyleBones(1.f, 0.8f).Contains(TEXT("cf_j_index02_L")) && OKStudioStyleBones(-1.f, 2.f).Contains(TEXT("cf_s_thigh01_L")));

	TArray<float> Short, ShortFace;
	OKStudioStyleSliders(1.f, Short, ShortFace);
	TestTrue(TEXT("no sliders stay none"), Short.IsEmpty() && ShortFace.IsEmpty());

	TestTrue(TEXT("a key not holding a style leaves the character's"), FOKSceneKey().Style < -1.f);
	return true;
}
#endif
