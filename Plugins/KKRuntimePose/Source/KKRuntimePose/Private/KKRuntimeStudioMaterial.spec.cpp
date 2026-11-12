#include "KKRuntimeSharedMaterial.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "KKRuntimeDisplayProfile.h"
#include "Materials/MaterialInstanceDynamic.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioMdkCoverage,
    "OpenKoikatsu.RuntimeMaterial.StudioMdkCoverage",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FOKStudioMdkCoverage::RunTest(const FString&)
{
    for (const TCHAR* Keywords : { TEXT("[\"_NORMALMAP\"]"), TEXT("[\"_NORMALMAP\",\"_ALPHATEST_ON\"]") })
    {
        FKKRuntimeMaterialPart Part;
        Part.SourceMetadataJson = FString::Printf(TEXT("{\"material\":{\"shader\":\"Shader Forge/main_StandardMDK_studio\",\"keywords\":%s}}"), Keywords);
        const auto Recipe = OKRuntimeSharedMaterialRecipe(Part);
        TestEqual(TEXT("body and guard use native MDK"), int32(Recipe), int32(EKKRuntimeMaterialRecipe::ForgeMDK));
        TestEqual(TEXT("MDK writes depth and clips alpha"), int32(OKRuntimeSharedMaterialBlendMode(Recipe)), int32(BLEND_Masked));
    }
    return true;
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioGlassesBlend,
    "OpenKoikatsu.RuntimeMaterial.GlassesBlend",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKStudioGlassesBlend::RunTest(const FString&)
{
    for (int32 I = int32(EKKRuntimeMaterialRecipe::KoikanoGlasses0);
         I <= int32(EKKRuntimeMaterialRecipe::KoikanoGlasses11); ++I)
    {
        const auto Recipe = EKKRuntimeMaterialRecipe(I);
        TestTrue(TEXT("all native glasses variants preserve shader alpha"), OKRuntimeSharedMaterialTranslucent(Recipe));
        TestEqual(TEXT("source SrcAlpha / OneMinusSrcAlpha"), int32(OKRuntimeSharedMaterialBlendMode(Recipe)), int32(BLEND_Translucent));
    }
    return true;
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKVertexAmbientParentCompatibility,
    "OpenKoikatsu.RuntimeMaterial.VertexAmbientParentCompatibility",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKVertexAmbientParentCompatibility::RunTest(const FString&)
{
    FKKRuntimeMaterialPart Part;Part.ShaderKind=1;Part.Blend=TEXT("masked");Part.Unlit=true;
    Part.SourceMetadataJson=TEXT("{\"schema\":1,\"material\":{\"shader\":\"Koikano/hair_main_sun\",\"keywords\":[\"_OLDHAIR_ON\"]}}");
    auto* Legacy=OKLoadRuntimeSharedMaterialParent(TEXT("/Game/IndependentResources/RuntimeMaterials/StreetDisplay26"),EKKRuntimeMaterialRecipe::KoikanoHairSun2);
    auto* Current=OKLoadRuntimeSharedMaterialParent(TEXT("/Game/IndependentResources/RuntimeMaterials/StudioDisplay28"),EKKRuntimeMaterialRecipe::KoikanoHairSun2);
    if(!TestNotNull(TEXT("legacy cooked native hair parent"),Legacy)||!TestNotNull(TEXT("current cooked native hair parent"),Current))return false;
    FKKRuntimeMaterialScene Scene;OKApplyCharacterMakerLighting(Scene);FString Error;
    TestNotNull(*FString::Printf(TEXT("maker binds existing parent without optional vertex ambient: %s"),*Error),OKCreateRuntimeSharedMaterial(Part,{},Legacy,Scene,Error));
    const FLinearColor Probe(.2f,.1f,.3f,.4f);Scene.Uniforms.Add(TEXT("unity_SHBr"),Probe);
    TestNull(TEXT("nonzero vertex ambient requires a capable parent"),OKCreateRuntimeSharedMaterial(Part,{},Legacy,Scene,Error));
    auto* MID=OKCreateRuntimeSharedMaterial(Part,{},Current,Scene,Error);
    if(!TestNotNull(*FString::Printf(TEXT("current parent binds native probe: %s"),*Error),MID))return false;
    FLinearColor Actual;float Alpha=0;
    TestTrue(TEXT("native probe vector and alpha survive binding"),MID->GetVectorParameterValue(FMaterialParameterInfo(TEXT("unity_SHBr")),Actual)
        && MID->GetScalarParameterValue(FMaterialParameterInfo(TEXT("unity_SHBr__A")),Alpha)
        && Actual.Equals(Probe,.000001f) && FMath::Abs(Alpha-Probe.A)<.000001f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKForgeSkinCustomizationBinding,
    "OpenKoikatsu.RuntimeMaterial.ForgeSkinCustomizationBinding",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKForgeSkinCustomizationBinding::RunTest(const FString&)
{
    FKKRuntimeMaterialPart Part;
    Part.ShaderKind = 7;
    Part.Blend = TEXT("masked");
    Part.Unlit = true;
    Part.SourceMetadataJson = TEXT("{\"schema\":1,\"material\":{\"shader\":\"Shader Forge/main_skin\",\"floats\":{\"_rimV\":0.4,\"_rimpower\":0.1},\"colors\":{}}}");
    Part.Values.Add(TEXT("_ShadowExtend"), FVector4f(0.66f, 0.f, 0.f, 0.f));
    Part.Values.Add(TEXT("_SpecularHeight"), FVector4f(0.99f, 0.f, 0.f, 0.f));
    Part.Values.Add(TEXT("_OverColor1"), FVector4f(0.85f, 0.5f, 0.55f, 0.3f));
    auto* Parent = OKLoadRuntimeSharedMaterialParent(TEXT("/Game/IndependentResources/RuntimeMaterials/StudioDisplay30"), EKKRuntimeMaterialRecipe::ForgeSkin);
    if (!TestNotNull(TEXT("StudioDisplay30 ForgeSkin parent"), Parent)) return false;
    FKKRuntimeMaterialScene Scene;
    OKApplyCharacterMakerLighting(Scene);
    FString Error;
    auto* MID = OKCreateRuntimeSharedMaterial(Part, {}, Parent, Scene, Error);
    if (!TestNotNull(*FString::Printf(TEXT("ForgeSkin MID binds card skin properties: %s"), *Error), MID)) return false;
    float ShadowExtend = 0.f, SpecHeight = 0.f, RimV = 0.f, RimPower = 0.f, ShadowStrength = -1.f;
    TestTrue(TEXT("ForgeSkin binds _ShadowExtend"), MID->GetScalarParameterValue(FMaterialParameterInfo(TEXT("_ShadowExtend")), ShadowExtend) && FMath::IsNearlyEqual(ShadowExtend, 0.66f, 1e-4f));
    TestTrue(TEXT("ForgeSkin binds _SpeclarHeight"), MID->GetScalarParameterValue(FMaterialParameterInfo(TEXT("_SpeclarHeight")), SpecHeight) && FMath::IsNearlyEqual(SpecHeight, 0.99f, 1e-4f));
    TestTrue(TEXT("ForgeSkin binds _rimV"), MID->GetScalarParameterValue(FMaterialParameterInfo(TEXT("_rimV")), RimV) && FMath::IsNearlyEqual(RimV, 0.4f, 1e-4f));
    TestTrue(TEXT("ForgeSkin binds _rimpower"), MID->GetScalarParameterValue(FMaterialParameterInfo(TEXT("_rimpower")), RimPower) && FMath::IsNearlyEqual(RimPower, 0.1f, 1e-4f));
    TestTrue(TEXT("StudioDisplay30 defaults __OK_ShadowStrength to 0"), MID->GetScalarParameterValue(FMaterialParameterInfo(TEXT("__OK_ShadowStrength")), ShadowStrength) && FMath::IsNearlyEqual(ShadowStrength, 0.f, 1e-5f));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKKKUTSMaterialCoverage,
    "OpenKoikatsu.RuntimeMaterial.KKUTSCoverage",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKKKUTSMaterialCoverage::RunTest(const FString&)
{
    struct FCase { const TCHAR* Shader; EKKRuntimeMaterialRecipe Recipe; EBlendMode Blend; bool TwoSided; bool HasOutline; };
    const FCase Cases[] = {
        { TEXT("KKUTS"), EKKRuntimeMaterialRecipe::KKUTS, BLEND_Masked, true, true },
        { TEXT("KKUTS_Tess"), EKKRuntimeMaterialRecipe::KKUTS, BLEND_Masked, true, true },
        { TEXT("KKUTSitem"), EKKRuntimeMaterialRecipe::KKUTSItem, BLEND_Masked, true, true },
        { TEXT("KKUTSitem_Tess"), EKKRuntimeMaterialRecipe::KKUTSItem, BLEND_Masked, true, true },
        { TEXT("KKUTSalpha"), EKKRuntimeMaterialRecipe::KKUTSAlpha, BLEND_Translucent, true, false },
        { TEXT("KKUTSalpha_Tess"), EKKRuntimeMaterialRecipe::KKUTSAlpha, BLEND_Translucent, true, false },
        { TEXT("KKUTShair"), EKKRuntimeMaterialRecipe::KKUTSHair, BLEND_Masked, true, true },
        { TEXT("KKUTShair_Tess"), EKKRuntimeMaterialRecipe::KKUTSHair, BLEND_Masked, true, true },
        { TEXT("KKUTSeye"), EKKRuntimeMaterialRecipe::KKUTSEye, BLEND_Translucent, false, false },
        { TEXT("KKUTSeyew"), EKKRuntimeMaterialRecipe::KKUTSEyeWhite, BLEND_Translucent, false, false },
        { TEXT("KKUSS"), EKKRuntimeMaterialRecipe::KKUSS, BLEND_Masked, true, true },
        { TEXT("kKUSS"), EKKRuntimeMaterialRecipe::KKUSS, BLEND_Masked, true, true },
        { TEXT("KKUSSitem"), EKKRuntimeMaterialRecipe::KKUSSItem, BLEND_Masked, true, false },
        { TEXT("KKUSSalpha"), EKKRuntimeMaterialRecipe::KKUSSAlpha, BLEND_AlphaComposite, false, false },
        { TEXT("KKUSShair"), EKKRuntimeMaterialRecipe::KKUSSHair, BLEND_Masked, true, true },
    };
    for (const FCase& C : Cases)
    {
        FKKRuntimeMaterialPart Part;
        Part.SourceMetadataJson = FString::Printf(TEXT("{\"schema\":1,\"material\":{\"shader\":\"%s\",\"floats\":{\"_highcolor_power\":0.42,\"_outlineadjust\":1.5,\"_1st_shademap_st_x\":2.0},\"colors\":{}}}"), C.Shader);
        const auto Recipe = OKRuntimeSharedMaterialRecipe(Part);
        TestEqual(C.Shader, int32(Recipe), int32(C.Recipe));
        TestEqual(C.Shader, int32(OKRuntimeSharedMaterialBlendMode(Recipe)), int32(C.Blend));
        TestEqual(C.Shader, OKRuntimeSharedMaterialTwoSided(Recipe), C.TwoSided);
        TestEqual(C.Shader, OKRuntimeOutlineLayout(Recipe) != nullptr, C.HasOutline);
        {
            FKKRuntimeMaterialScene Scene;
            FKKRuntimeMaterialBinding Binding;
            FString Error;
            TestTrue(*FString::Printf(TEXT("%s forward binding: %s"), C.Shader, *Error), OKPrepareRuntimeSharedMaterialBinding(Part, Scene, Binding, Error, false));
            if (C.Recipe == EKKRuntimeMaterialRecipe::KKUTS)
            {
                TestTrue(TEXT("lowercase ME float binds to _HighColor_Power"), FMath::IsNearlyEqual(Binding.Scalars.FindRef(TEXT("_HighColor_Power")), 0.42f, 1e-4f));
                TestTrue(TEXT("lowercase ME ST axis binds to _1st_ShadeMap_ST"), FMath::IsNearlyEqual(Binding.Vectors.FindRef(TEXT("_1st_ShadeMap_ST")).R, 2.f, 1e-4f));
            }
            if (C.HasOutline)
            {
                FKKRuntimeMaterialBinding OutlineBinding;
                TestTrue(*FString::Printf(TEXT("%s outline binding: %s"), C.Shader, *Error), OKPrepareRuntimeSharedMaterialBinding(Part, Scene, OutlineBinding, Error, true));
                if (C.Recipe == EKKRuntimeMaterialRecipe::KKUTS || C.Recipe == EKKRuntimeMaterialRecipe::KKUTSItem || C.Recipe == EKKRuntimeMaterialRecipe::KKUTSHair)
                {
                    TestTrue(TEXT("lowercase ME _outlineadjust binds to _OutlineAdjust"), FMath::IsNearlyEqual(OutlineBinding.Scalars.FindRef(TEXT("_OutlineAdjust")), 1.5f, 1e-4f));
                }
                else
                {
                    TestTrue(TEXT("KKUSS outline binds _linewidthG"), OutlineBinding.Scalars.Contains(TEXT("_linewidthG")));
                }
            }
            for (const TCHAR* Root : { TEXT("/Game/IndependentResources/RuntimeMaterials/StreetDisplay27"), TEXT("/Game/IndependentResources/RuntimeMaterials/StreetHG06"), TEXT("/Game/IndependentResources/RuntimeMaterials/StudioDisplay31") })
            {
                auto* Parent = OKLoadRuntimeSharedMaterialParent(Root, Recipe, false);
                TestNotNull(*FString::Printf(TEXT("%s/%s forward parent"), Root, C.Shader), Parent);
                if (C.HasOutline)
                {
                    auto* OutlineParent = OKLoadRuntimeSharedMaterialParent(Root, Recipe, true);
                    TestNotNull(*FString::Printf(TEXT("%s/%s outline parent"), Root, C.Shader), OutlineParent);
                }
            }
        }
    }
    return !HasAnyErrors();
}

#endif

