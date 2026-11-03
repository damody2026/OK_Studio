#include "OKStudioImportSettings.h"
#include "OKStudioGameInternal.h"
#include "OKStudioSky.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioClearColorSettingsTest, "OpenKoikatsu.Studio.ClearColorSettings", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKStudioClearColorSettingsTest::RunTest(const FString&)
{
    TestTrue(TEXT("source default is black without an installation"), OKStudioClearColorFromSettings(TEXT("")).Equals(FLinearColor::Black));
    const FString Xml = TEXT("<System><H><BackColor>1,0,0,1</BackColor></H><Est><BackColor>0.2, 0.3, 0.4, 0.1</BackColor></Est></System>");
    TestTrue(TEXT("Studio uses Est settings, preserving display RGB and ignoring camera alpha"), OKStudioClearColorFromSettings(Xml).Equals(FLinearColor(.2f,.3f,.4f,1.f)));
    for (const FString Invalid : { TEXT("<System><Est/></System>"), TEXT("<System><Est><BackColor>1,2,3</BackColor></Est></System>"), TEXT("<System><Est><BackColor>1,bad,0,1</BackColor></Est></System>") })
        TestTrue(TEXT("missing or invalid colour retains source black default"), OKStudioClearColorFromSettings(Invalid).Equals(FLinearColor::Black));
    FLinearColor A=FLinearColor::Red,B=FLinearColor::Green,C=FLinearColor::Blue;
    TArray<FLinearColor> Higher;
    TestTrue(TEXT("empty native scene never inherits Maker probe"), OKStudioMapAmbient(-1,A,B,C,&Higher)
        && A.Equals(FLinearColor(0,0,0,0)) && B.Equals(A) && C.Equals(A) && Higher.Num()==4
        && Higher[0].Equals(A) && Higher[1].Equals(A) && Higher[2].Equals(A) && Higher[3].Equals(FLinearColor(0,0,0,1)));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioFocusSelectionFrustumTest, "OpenKoikatsu.Studio.FocusSelectionFrustumEnvelope", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKStudioFocusSelectionFrustumTest::RunTest(const FString&)
{
    // Standing character AABB (~50x36x168 cm): 8-corner envelope must fit all vertices tightly without bounding-sphere over-retreat.
    const FBox CharaBox(FVector(-25.f, -18.f, 0.f), FVector(25.f, 18.f, 168.f));
    for (const float Aspect : { 16.f / 9.f, 21.f / 9.f, 9.f / 16.f })
    {
        for (const float HFov : { 28.f, 40.f, 70.f })
        {
            for (const FRotator Rot : { FRotator(-8.f, -90.f, 0.f), FRotator(0.f, 0.f, 0.f), FRotator(-25.f, 45.f, 0.f) })
            {
                const float Dist = OKStudioGameInternal::ComputeFocusSelectionDistance(CharaBox, Rot, HFov, Aspect);
                TestTrue(TEXT("distance is finite and within valid bounds"), FMath::IsFinite(Dist) && Dist >= 20.f && Dist <= 5000.f);
                const FRotationMatrix Basis(FRotator(Rot.Pitch, Rot.Yaw, 0.f));
                const FVector Forward = Basis.GetUnitAxis(EAxis::X);
                const FVector Right = Basis.GetUnitAxis(EAxis::Y);
                const FVector Up = Basis.GetUnitAxis(EAxis::Z);
                const FVector CamPos = CharaBox.GetCenter() - Forward * Dist;
                const float TanH = FMath::Tan(FMath::DegreesToRadians(HFov * 0.5f));
                const float TanV = TanH / Aspect;
                FVector Corners[8];
                CharaBox.GetVertices(Corners);
                float MaxUsage = 0.f;
                for (const FVector& C : Corners)
                {
                    const FVector Rel = C - CamPos;
                    const double Z = FVector::DotProduct(Rel, Forward);
                    TestTrue(TEXT("every corner lies in front of camera"), Z > 0.5);
                    const float NormX = float(FMath::Abs(FVector::DotProduct(Rel, Right)) / (Z * TanH));
                    const float NormY = float(FMath::Abs(FVector::DotProduct(Rel, Up)) / (Z * TanV));
                    TestTrue(TEXT("every corner fits horizontally and vertically"), NormX <= 1.0f && NormY <= 1.0f);
                    MaxUsage = FMath::Max3(MaxUsage, NormX, NormY);
                }
                TestTrue(TEXT("envelope tightly frames the limiting axis (>88% NDC utilization)"), MaxUsage > 0.88f);
            }
        }
    }
    const float Dist16x9 = OKStudioGameInternal::ComputeFocusSelectionDistance(CharaBox, FRotator(-8.f, -90.f, 0.f), 40.f, 16.f / 9.f);
    TestTrue(TEXT("16:9 standing character distance avoids excessive sphere retreat (< 480 cm)"), Dist16x9 < 480.f);
    // Degenerate / invalid inputs fall back safely without NaN.
    TestEqual(TEXT("invalid box falls back to 380 cm"), OKStudioGameInternal::ComputeFocusSelectionDistance(FBox(ForceInit), FRotator::ZeroRotator, 40.f, 16.f / 9.f), 380.f);
    const float ZeroAspectDist = OKStudioGameInternal::ComputeFocusSelectionDistance(CharaBox, FRotator(-8.f, -90.f, 0.f), 0.f, 0.f);
    TestTrue(TEXT("zero FOV/aspect falls back to 40 deg 16:9"), FMath::IsNearlyEqual(ZeroAspectDist, Dist16x9, 1e-3f));
    return true;
}
#endif

