#include "KKRuntimeMaterial.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"

// A halving mip step covers whole source texels with weight one, so it does not need the general area box's four
// double divisions and eight min/max per output pixel (2026-11-25: that box was the biggest piece of a card
// reader's texture preparation). The fast path must produce the general box's own bytes -- not nearly, exactly --
// for every size, including the odd and 1xN steps it must decline to take, and for both colour spaces.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKRuntimeMipsMatchTheReferenceResize,
    "OpenKoikatsu.RuntimeMaterial.MipsMatchTheReferenceResize",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FOKRuntimeMipsMatchTheReferenceResize::RunTest(const FString&)
{
    uint32 Seed = 0x9e3779b9u;
    auto Next = [&Seed](uint32 N) { Seed ^= Seed << 13; Seed ^= Seed >> 17; Seed ^= Seed << 5; return Seed % N; };
    int32 Compared = 0;
    for (const FIntPoint Size : { FIntPoint(64, 64), FIntPoint(128, 32), FIntPoint(37, 11), FIntPoint(1, 9),
                                  FIntPoint(16, 1), FIntPoint(5, 5), FIntPoint(2, 2), FIntPoint(1, 1) })
    {
        for (const bool SRGB : { true, false })
        {
            for (const bool EncodedMips : { false, true })
            {
                TArray<uint8> Pixels;
                Pixels.SetNumUninitialized(Size.X * Size.Y * 4);
                for (uint8& Byte : Pixels) Byte = uint8(Next(256));
                FKKRuntimeTextureSettings Settings;
                Settings.SRGB = SRGB;
                Settings.EncodedMips = EncodedMips;
                TArray<FKKRuntimeTextureMip> Fast, Reference;
                FString Error;
                OKForceSlowRuntimeMips(false);
                const bool FastOk = OKBuildRuntimeTextureMips(Pixels, Size.X, Size.Y, Settings, Fast, Error);
                OKForceSlowRuntimeMips(true);
                const bool ReferenceOk = OKBuildRuntimeTextureMips(Pixels, Size.X, Size.Y, Settings, Reference, Error);
                OKResetSlowRuntimeMipsOverride();
                const FString What = FString::Printf(TEXT("%dx%d srgb=%d encoded=%d"), Size.X, Size.Y, int32(SRGB), int32(EncodedMips));
                TestTrue(*FString::Printf(TEXT("fast path builds %s"), *What), FastOk);
                TestTrue(*FString::Printf(TEXT("reference builds %s"), *What), ReferenceOk);
                TestEqual(*FString::Printf(TEXT("mip count %s"), *What), Fast.Num(), Reference.Num());
                for (int32 Level = 0; Level < FMath::Min(Fast.Num(), Reference.Num()); ++Level)
                {
                    TestEqual(*FString::Printf(TEXT("mip %d width %s"), Level, *What), Fast[Level].Width, Reference[Level].Width);
                    TestEqual(*FString::Printf(TEXT("mip %d height %s"), Level, *What), Fast[Level].Height, Reference[Level].Height);
                    const bool Same = Fast[Level].BGRA.Num() == Reference[Level].BGRA.Num()
                        && FMemory::Memcmp(Fast[Level].BGRA.GetData(), Reference[Level].BGRA.GetData(), Fast[Level].BGRA.Num()) == 0;
                    TestTrue(*FString::Printf(TEXT("mip %d bytes identical %s"), Level, *What), Same);
                    ++Compared;
                }
            }
        }
    }
    TestTrue(TEXT("mip levels were compared"), Compared > 50);
    return true;
}

#endif
