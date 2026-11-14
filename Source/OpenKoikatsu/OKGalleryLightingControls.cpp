#include "OKCharacterController.h"
#include "OKMotionComboBox.h"
#include "OKHGShading.h"
#include "KKPreviewActor.h"
#include "Blueprint/WidgetTree.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/Slider.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Styling/CoreStyle.h"

// 光影風格 in the card reader's right panel: the shown character's shadow ramp (the game's graphics-setting ramps and
// mods', live through _RampG), the camera key light's direction, its brightness and the ambient. Plain UMG controls held
// by the controller, so reader_call controls / control_set and ui_widgets / ui_set read and change them like a person.
// Kept in GameUserSettings (OpenKoikatsu.ReaderLighting) between runs.
namespace
{
	constexpr const TCHAR* LightingSection = TEXT("OpenKoikatsu.ReaderLighting");
	constexpr const TCHAR* CardRampLabel = TEXT("角色卡原本的陰影");

	struct FLightingPreset { const TCHAR* Name; const TCHAR* Ramp; float Yaw, Pitch, Intensity, Ambient; };
	// Ramp keys from Content/KKPreview/Ramps/ramps.json; "" keeps each material's card ramp.
	const FLightingPreset LightingPresets[] = {
		{ TEXT("原作預設"), TEXT(""), 0.f, 40.f, 1.f, 1.f },
		{ TEXT("柔和卡通"), TEXT("kk_0"), 0.f, 40.f, 0.95f, 1.6f },
		{ TEXT("強對比卡通"), TEXT("kk_1"), 35.f, 30.f, 1.15f, 0.5f },
		{ TEXT("側光"), TEXT(""), 90.f, 20.f, 1.f, 0.8f },
		{ TEXT("逆光"), TEXT(""), 180.f, 25.f, 1.f, 1.3f },
		{ TEXT("無陰影（平光）"), TEXT("kk_6"), 0.f, 40.f, 1.f, 1.f },
	};
	constexpr const TCHAR* CustomPresetName = TEXT("自訂");

	/** zh-TW names of the ramps (the street's ui.toml, [ui.settings] ramp_<key>); the game's own name otherwise. */
	TMap<FString, FString> RampNames()
	{
		TMap<FString, FString> Names;
		TArray<FString> Lines;
		FFileHelper::LoadFileToStringArray(Lines, *(FPaths::ProjectContentDir() / TEXT("IndependentResources/StreetSocialData/Localization/zh-TW/ui.toml")));
		for (const FString& Line : Lines)
		{
			FString Key, Value;
			if (!Line.StartsWith(TEXT("ramp_")) || !Line.Split(TEXT("="), &Key, &Value)) continue;
			Value.TrimStartAndEndInline();
			Names.Add(Key.TrimStartAndEnd().Mid(5), Value.TrimQuotes());
		}
		return Names;
	}

	FString FormatLighting(const UOKCharacterController* G, const USlider* S)
	{
		const float V = S->GetValue();
		if (S == G->LightingYawSlider || S == G->LightingPitchSlider) return FString::Printf(TEXT("%.0f°"), V);
		return FString::Printf(TEXT("%.2f"), V);
	}
}

void UOKCharacterController::BuildLightingControls(UVerticalBox* Parent)
{
	auto Text = [&](const FString& S, int32 Size)
	{
		UTextBlock* T = WidgetTree->ConstructWidget<UTextBlock>();
		T->SetText(FText::FromString(S));
		T->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", Size));
		T->SetColorAndOpacity(FSlateColor(FLinearColor::White));
		return T;
	};
	auto Labeled = [&](const TCHAR* Label, UWidget* Control, UTextBlock* Value)
	{
		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>();
		USizeBox* Box = WidgetTree->ConstructWidget<USizeBox>();
		Box->SetWidthOverride(96.f);
		Box->SetMinDesiredHeight(36.f);
		UTextBlock* T = Text(Label, 15);
		T->SetAutoWrapText(true);
		Box->SetContent(T);
		Row->AddChild(Box);
		UHorizontalBoxSlot* S = Row->AddChildToHorizontalBox(Control);
		S->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		S->SetVerticalAlignment(VAlign_Center);
		if (Value)
		{
			USizeBox* ValueBox = WidgetTree->ConstructWidget<USizeBox>();
			ValueBox->SetWidthOverride(52.f);
			ValueBox->SetContent(Value);
			Row->AddChildToHorizontalBox(ValueBox)->SetVerticalAlignment(VAlign_Center);
		}
		Control->SetToolTipText(FText::FromString(Label));
		Parent->AddChildToVerticalBox(Row)->SetPadding(FMargin(0.f, 1.f));
	};
	auto Slider = [&](const TCHAR* Label, const TCHAR* Name, float Min, float Max, float Step, float Value)
	{
		USlider* S = WidgetTree->ConstructWidget<USlider>(USlider::StaticClass(), Name);
		S->SetMinValue(Min);
		S->SetMaxValue(Max);
		S->SetStepSize(Step);
		S->SetValue(Value);
		S->SetSliderBarColor(FLinearColor(.95f, .8f, .45f));
		S->OnValueChanged.AddDynamic(this, &UOKCharacterController::OnLightingSlider);
		UTextBlock* V = Text(FString(), 14);
		Labeled(Label, S, V);
		LightingValueLabels.Add({ S, V });
		return S;
	};
	Parent->AddChildToVerticalBox(Text(TEXT("光影風格"), 17))->SetPadding(FMargin(0.f, 0.f, 0.f, 4.f));

	auto Float = [&](const TCHAR* Key, float Default)
	{
		float V = Default;
		if (GConfig) GConfig->GetFloat(LightingSection, Key, V, GGameUserSettingsIni);
		return FMath::IsFinite(V) ? V : Default;
	};
	FString Preset = LightingPresets[0].Name, Ramp;
	if (GConfig)
	{
		GConfig->GetString(LightingSection, TEXT("Preset"), Preset, GGameUserSettingsIni);
		GConfig->GetString(LightingSection, TEXT("Ramp"), Ramp, GGameUserSettingsIni);
	}

	LightingPresetCombo = WidgetTree->ConstructWidget<UOKMotionComboBox>(UOKMotionComboBox::StaticClass(), TEXT("LightingPresetCombo"));
	for (const FLightingPreset& P : LightingPresets) LightingPresetCombo->AddOption(P.Name);
	LightingPresetCombo->AddOption(CustomPresetName);
	LightingPresetCombo->SetSelectedOption(LightingPresetCombo->FindOptionIndex(Preset) >= 0 ? Preset : FString(CustomPresetName));
	LightingPresetCombo->OnSelectionChanged.AddDynamic(this, &UOKCharacterController::OnLightingPreset);
	Labeled(TEXT("光影預設"), LightingPresetCombo, nullptr);

	LightingRampCombo = WidgetTree->ConstructWidget<UOKMotionComboBox>(UOKMotionComboBox::StaticClass(), TEXT("LightingRampCombo"));
	LightingRampKeys.Reset();
	LightingRampCombo->AddOption(CardRampLabel);
	LightingRampKeys.Add(FString());
	const TMap<FString, FString> Names = RampNames();
	for (const FOKRenderRamp& R : OKRenderRamps())
	{
		FString Label = Names.FindRef(R.Key);
		if (Label.IsEmpty()) Label = R.Name.IsEmpty() ? R.Key : R.Name;
		while (LightingRampCombo->FindOptionIndex(Label) >= 0) Label += TEXT(" ");	// options are matched by text
		LightingRampCombo->AddOption(Label);
		LightingRampKeys.Add(R.Key);
	}
	const int32 RampIndex = FMath::Max(0, LightingRampKeys.IndexOfByKey(Ramp));
	LightingRampCombo->SetSelectedIndex(RampIndex);
	LightingRampCombo->OnSelectionChanged.AddDynamic(this, &UOKCharacterController::OnLightingRamp);
	Labeled(TEXT("陰影風格"), LightingRampCombo, nullptr);

	LightingYawSlider = Slider(TEXT("主光水平角（0 鏡頭方向、正值往右）"), TEXT("LightingYaw"), -180.f, 180.f, 1.f, Float(TEXT("Yaw"), 0.f));
	LightingPitchSlider = Slider(TEXT("主光仰角"), TEXT("LightingPitch"), -30.f, 89.f, 1.f, Float(TEXT("Pitch"), 40.f));
	LightingIntensitySlider = Slider(TEXT("主光亮度"), TEXT("LightingIntensity"), 0.f, 2.f, 0.01f, Float(TEXT("Intensity"), 1.f));
	LightingAmbientSlider = Slider(TEXT("環境光"), TEXT("LightingAmbient"), 0.f, 4.f, 0.01f, Float(TEXT("Ambient"), 1.f));
	for (const auto& L : LightingValueLabels) L.Value->SetText(FText::FromString(FormatLighting(this, L.Key)));
	Parent->AddChildToVerticalBox(WidgetTree->ConstructWidget<USizeBox>())->SetPadding(FMargin(0.f, 0.f, 0.f, 10.f));
}

void UOKCharacterController::SyncLightingWidgets()
{
	for (const auto& L : LightingValueLabels) if (L.Key && L.Value) L.Value->SetText(FText::FromString(FormatLighting(this, L.Key)));
	if (!GConfig || !LightingPresetCombo) return;
	GConfig->SetString(LightingSection, TEXT("Preset"), *LightingPresetCombo->GetSelectedOption(), GGameUserSettingsIni);
	const int32 Ramp = LightingRampCombo ? LightingRampCombo->GetSelectedIndex() : 0;
	GConfig->SetString(LightingSection, TEXT("Ramp"), *(LightingRampKeys.IsValidIndex(Ramp) ? LightingRampKeys[Ramp] : FString()), GGameUserSettingsIni);
	GConfig->SetFloat(LightingSection, TEXT("Yaw"), LightingYawSlider->GetValue(), GGameUserSettingsIni);
	GConfig->SetFloat(LightingSection, TEXT("Pitch"), LightingPitchSlider->GetValue(), GGameUserSettingsIni);
	GConfig->SetFloat(LightingSection, TEXT("Intensity"), LightingIntensitySlider->GetValue(), GGameUserSettingsIni);
	GConfig->SetFloat(LightingSection, TEXT("Ambient"), LightingAmbientSlider->GetValue(), GGameUserSettingsIni);
	GConfig->Flush(false, GGameUserSettingsIni);
}

void UOKCharacterController::OnLightingPreset(FString Value, ESelectInfo::Type Type)
{
	for (const FLightingPreset& P : LightingPresets)
	{
		if (Value != P.Name) continue;
		// Set the controls quietly (their own callbacks would call the look custom), then apply once.
		TGuardValue<bool> Guard(bApplyingLightingPreset, true);
		LightingRampCombo->SetSelectedIndex(FMath::Max(0, LightingRampKeys.IndexOfByKey(FString(P.Ramp))));
		LightingYawSlider->SetValue(P.Yaw);
		LightingPitchSlider->SetValue(P.Pitch);
		LightingIntensitySlider->SetValue(P.Intensity);
		LightingAmbientSlider->SetValue(P.Ambient);
		break;
	}
	ApplyLighting(true);
	SyncLightingWidgets();
}

void UOKCharacterController::OnLightingRamp(FString Value, ESelectInfo::Type Type)
{
	if (bApplyingLightingPreset) return;
	// Only a person's (or MCP's) pick makes the look custom.
	if (LightingPresetCombo && LightingPresetCombo->GetSelectedOption() != CustomPresetName)
	{
		auto Changed = LightingPresetCombo->OnSelectionChanged;
		LightingPresetCombo->OnSelectionChanged.Clear();
		LightingPresetCombo->SetSelectedOption(CustomPresetName);
		LightingPresetCombo->OnSelectionChanged = Changed;
	}
	ApplyLighting(true);
	SyncLightingWidgets();
}

void UOKCharacterController::OnLightingSlider(float Value)
{
	if (bApplyingLightingPreset) return;
	if (LightingPresetCombo && LightingPresetCombo->GetSelectedOption() != CustomPresetName)
	{
		// A slider moved off its preset's value makes the look custom.
		for (const FLightingPreset& P : LightingPresets)
			if (LightingPresetCombo->GetSelectedOption() == P.Name &&
				(!FMath::IsNearlyEqual(LightingYawSlider->GetValue(), P.Yaw, .5f) || !FMath::IsNearlyEqual(LightingPitchSlider->GetValue(), P.Pitch, .5f) ||
				 !FMath::IsNearlyEqual(LightingIntensitySlider->GetValue(), P.Intensity, .005f) || !FMath::IsNearlyEqual(LightingAmbientSlider->GetValue(), P.Ambient, .005f)))
			{
				auto Changed = LightingPresetCombo->OnSelectionChanged;
				LightingPresetCombo->OnSelectionChanged.Clear();
				LightingPresetCombo->SetSelectedOption(CustomPresetName);
				LightingPresetCombo->OnSelectionChanged = Changed;
			}
	}
	ApplyLighting(true);
	SyncLightingWidgets();
}

void UOKCharacterController::ApplyLighting(bool bForce)
{
	if (!IsValid(PreviewActor) || !LightingRampCombo) return;
	const bool bNewActor = LitActor != PreviewActor;
	const double Now = FPlatformTime::Seconds();
	// Materials of the same character are rebuilt by outfit changes and progressive loads: catch up a few times a second.
	if (!bForce && !bNewActor && Now - LightingAppliedAt < .25) return;
	LightingAppliedAt = Now;
	AKKPreviewActor* A = PreviewActor;
	A->KeyLightYaw = LightingYawSlider->GetValue();
	A->KeyLightPitch = LightingPitchSlider->GetValue();
	A->KeyLightIntensity = LightingIntensitySlider->GetValue();
	A->AmbientScale = LightingAmbientSlider->GetValue();
	const int32 RampIndex = LightingRampCombo->GetSelectedIndex();
	const FString Key = LightingRampKeys.IsValidIndex(RampIndex) ? LightingRampKeys[RampIndex] : FString();
	UTexture2D* Ramp = nullptr;
	if (!Key.IsEmpty())
	{
		FString Error;
		Ramp = OKLoadRenderRamp(Key, Error);
		if (!Ramp) UE_LOG(LogTemp, Warning, TEXT("OK reader lighting: ramp %s: %s"), *Key, *Error);
	}
	// The card's own ramp needs no write until a ramp was chosen on this character (SetDisplayRamp gives every
	// material it touches its own instance; ProductCardRamps remembers the card ramps it replaced).
	if (Ramp || A->ProductCardRamps.Num() > 0) A->SetDisplayRamp(Ramp);
	A->ApplyLightingScales();
	A->UpdateCameraKeyLight();
	if (bNewActor || bForce)
		UE_LOG(LogTemp, Display, TEXT("OK reader lighting preset=%s ramp=%s yaw=%.0f pitch=%.0f light=%.2f ambient=%.2f"),
			*LightingPresetCombo->GetSelectedOption(), Key.IsEmpty() ? TEXT("card") : *Key, A->KeyLightYaw, A->KeyLightPitch, A->KeyLightIntensity, A->AmbientScale);
	LitActor = PreviewActor;
}
