#include "OKStudioText.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioTextFormatTest, "OpenKoikatsu.Studio.TextFormat", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKStudioTextFormatTest::RunTest(const FString&)
{
	TestEqual(TEXT("simple and number arguments"),
		OKStudioFormat(TEXT("已建 {built, number} / 共 {total, number} 個物件"), {{TEXT("built"), 1170}, {TEXT("total"), 1234567}}),
		FString(TEXT("已建 1,170 / 共 1,234,567 個物件")));
	TestEqual(TEXT("a plain argument is not grouped"), OKStudioFormat(TEXT("{n}"), {{TEXT("n"), 12345}}), FString(TEXT("12345")));
	TestEqual(TEXT("text argument"), OKStudioFormat(TEXT("「{name}」"), {{TEXT("name"), TEXT("SD42 full")}}), FString(TEXT("「SD42 full」")));
	TestEqual(TEXT("an unknown argument stays as written"), OKStudioFormat(TEXT("{x} {y}"), {{TEXT("x"), 1}}), FString(TEXT("1 {y}")));
	TestEqual(TEXT("plural is not read here and stays"), OKStudioFormat(TEXT("{n, plural, one {#} other {#}}"), {{TEXT("n"), 2}}),
		FString(TEXT("{n, plural, one {#} other {#}}")));
	TestEqual(TEXT("ICU quoting"), OKStudioFormat(TEXT("it''s '{n}' {n}"), {{TEXT("n"), 3}}), FString(TEXT("it's {n} 3")));
	TestEqual(TEXT("built-in words exist"), OKStudioT(TEXT("load.title")).IsEmpty() || OKStudioT(TEXT("load.title")) == TEXT("load.title"), false);
	TestEqual(TEXT("unknown id shows as itself"), OKStudioT(TEXT("no.such.id")), FString(TEXT("no.such.id")));
	return true;
}
#endif
