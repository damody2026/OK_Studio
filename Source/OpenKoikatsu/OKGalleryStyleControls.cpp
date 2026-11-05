#include "OKGalleryWidget.h"
#include "OKShapeSlider.h"
#include "OKStudioCharacterStyle.h"
#include "KKPreviewActor.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Button.h"
#include "Components/ComboBoxString.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Styling/CoreStyle.h"
#include "Dom/JsonObject.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

// The Studio's character style in the card reader: the shown character only, the card keeps its values.
namespace
{
	using T = FOKStudioStyleTuning;
	struct FStyleControl { const TCHAR* Key; const TCHAR* Label; float Min; float Max; float T::* Field; };
	const FStyleControl StyleControls[] = {
		{ TEXT("style"), TEXT("風格（-1 寫實、1 Q 版）"), -1.f, 1.f, nullptr },
		{ TEXT("heads"), TEXT("頭身"), 7.f, 15.f, &T::Heads },
		{ TEXT("head_size"), TEXT("頭大小"), 0.8f, 1.5f, &T::HeadSize },
		{ TEXT("shoulders"), TEXT("肩寬"), 0.7f, 2.f, &T::Shoulders },
		{ TEXT("upper"), TEXT("上半身寬"), 0.7f, 2.f, &T::Upper },
		{ TEXT("waist"), TEXT("腰寬"), 0.6f, 2.f, &T::Waist },
		{ TEXT("hips"), TEXT("臀寬"), 0.7f, 2.2f, &T::Hips },
		{ TEXT("upper_arm"), TEXT("大手臂粗"), 0.7f, 2.5f, &T::UpperArm },
		{ TEXT("forearm"), TEXT("小手臂粗"), 0.7f, 2.5f, &T::Forearm },
		{ TEXT("thigh"), TEXT("大腿粗"), 0.7f, 2.5f, &T::Thigh },
		{ TEXT("calf"), TEXT("小腿粗"), 0.7f, 2.5f, &T::Calf },
		{ TEXT("arm_growth"), TEXT("手臂長度"), 0.f, 1.2f, &T::ArmGrowth },
		{ TEXT("leg_length"), TEXT("腿長"), 0.7f, 1.3f, &T::LegLength },
		{ TEXT("bust"), TEXT("胸部大小"), 0.6f, 2.f, &T::Bust },
		{ TEXT("breast"), TEXT("胸部滑桿目標"), 0.f, 1.5f, &T::Breast },
		{ TEXT("hem"), TEXT("衣服下擺寬"), 0.6f, 1.5f, &T::Hem },
		{ TEXT("real_jaw"), TEXT("寫實下巴變化"), 0.f, 1.f, &T::RealJaw },
		{ TEXT("real_face"), TEXT("寫實五官變化"), 0.f, 1.f, &T::RealFace },
		{ TEXT("real_chin"), TEXT("寫實下巴尖圓度"), 0.f, 1.f, &T::RealChin },
		{ TEXT("chibi_chin"), TEXT("Q 版下巴尖圓度"), 0.f, 1.f, &T::ChibiChin },
		{ TEXT("chibi_jaw"), TEXT("Q 版下巴加寬上限"), 0.f, 0.6f, &T::ChibiJaw },
	};
	/** The sliders' numbers, kept between runs and readable from outside. */
	FString TuningFile()
	{
		return FPaths::ProjectSavedDir() / TEXT("OKStyleTuning.json");
	}

	void LoadTuning()
	{
		FString Text;
		TSharedPtr<FJsonObject> Json;
		if (!FFileHelper::LoadFileToString(Text, *TuningFile()) || !FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Json) || !Json) return;
		for (const FStyleControl& C : StyleControls)
		{
			double V;
			if (C.Field && Json->TryGetNumberField(C.Key, V)) OKStudioStyleTuning().*C.Field = float(V);
		}
	}

	void SaveTuning()
	{
		FString Text = TEXT("{\n");
		for (const FStyleControl& C : StyleControls)
			if (C.Field) Text += FString::Printf(TEXT("%s  \"%s\": %.2f"), Text.Len() > 2 ? TEXT(",\n") : TEXT(""), C.Key, OKStudioStyleTuning().*C.Field);
		FFileHelper::SaveStringToFile(Text + TEXT("\n}\n"), *TuningFile(), FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
	}

	const FStyleControl* FindControl(const FString& Key)
	{
		for (const FStyleControl& C : StyleControls) if (Key == C.Key) return &C;
		return nullptr;
	}
}

void UOKCharacterController::BuildStyleControls()
{
	// Second in the list: the bone categories run long.
	TArray<FString> Categories;
	for (int32 I = 0; I < BoneCategoryCombo->GetOptionCount(); ++I) Categories.Add(BoneCategoryCombo->GetOptionAtIndex(I));
	Categories.Insert(TEXT("角色風格"), FMath::Min(1, Categories.Num()));
	const FString Shown = BoneCategoryCombo->GetSelectedOption();
	BoneCategoryCombo->ClearOptions();
	for (const FString& Category : Categories) BoneCategoryCombo->AddOption(Category);
	BoneCategoryCombo->SetSelectedOption(Shown);
	LoadTuning();
	StyleBox = WidgetTree->ConstructWidget<UVerticalBox>();
	for (const FStyleControl& Def : StyleControls)
	{
		auto Row = WidgetTree->ConstructWidget<UHorizontalBox>();
		auto Box = WidgetTree->ConstructWidget<USizeBox>();
		Box->SetWidthOverride(128.f);
		Box->SetMinDesiredHeight(44.f);
		auto Label = WidgetTree->ConstructWidget<UTextBlock>();
		Label->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 16));
		Label->SetAutoWrapText(true);
		Label->SetWrapTextAt(128.f);
		Label->SetText(FText::FromString(Def.Label));
		Box->SetContent(Label);
		Row->AddChild(Box);
		auto Slider = WidgetTree->ConstructWidget<UOKShapeSlider>();
		Slider->Owner = this;
		Slider->StyleParameter = Def.Key;
		Slider->ModAxis = 7;	// the label shows the value as it is
		Slider->ModRow = Row;
		Slider->SetMinValue(Def.Min);
		Slider->SetMaxValue(Def.Max);
		Slider->SetStepSize(0.01f);
		Slider->SetValue(Def.Field ? OKStudioStyleTuning().*Def.Field : 0.f);
		Slider->SetSliderBarColor(FLinearColor(.95f, .7f, .35f));
		Slider->OnValueChanged.AddDynamic(Slider, &UOKShapeSlider::OnSliderMoved);
		auto RowSlot = Row->AddChildToHorizontalBox(Slider);
		RowSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		RowSlot->SetVerticalAlignment(VAlign_Center);
		auto ValueBox = WidgetTree->ConstructWidget<USizeBox>();
		ValueBox->SetWidthOverride(56.f);
		Slider->ValueLabel = WidgetTree->ConstructWidget<UTextBlock>();
		Slider->ValueLabel->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 16));
		ValueBox->SetContent(Slider->ValueLabel);
		Row->AddChild(ValueBox);
		auto Reset = WidgetTree->ConstructWidget<UButton>();
		auto Text = WidgetTree->ConstructWidget<UTextBlock>();
		Text->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 14));
		Text->SetAutoWrapText(false);
		Text->SetText(FText::FromString(TEXT("重置")));
		Reset->SetContent(Text);
		Reset->OnClicked.AddDynamic(Slider, &UOKShapeSlider::OnResetClicked);
		Row->AddChild(Reset);
		StyleBox->AddChild(Row);
		StyleSliders.Add(Slider);
		Slider->RefreshValueLabel();
	}
	ShapeBox->AddChild(StyleBox);
	StyleBox->SetVisibility(ESlateVisibility::Collapsed);
	float Start = 0.f;
	if (FParse::Value(FCommandLine::Get(), TEXT("-CharacterStyle="), Start))
	{
		StyleSliders[0]->SetValue(Start);
		CharacterStyle = Start;
	}
}

void UOKCharacterController::OnStyleChanged(const FString& Parameter, float Value)
{
	const FStyleControl* Def = FindControl(Parameter);
	if (!Def || !FMath::IsFinite(Value)) return;
	Value = FMath::RoundToFloat(Value * 100.f) / 100.f;
	if (Def->Field)
	{
		OKStudioStyleTuning().*Def->Field = Value;
		++OKStudioStyleTuning().Revision;
		SaveTuning();
	}
	else CharacterStyle = Value;
	ApplyCharacterStyle();
}

float UOKCharacterController::StyleDefault(const FString& Parameter) const
{
	const FStyleControl* Def = FindControl(Parameter);
	return Def && Def->Field ? FOKStudioStyleTuning().*Def->Field : 0.f;
}

void UOKCharacterController::OnStyleReset(UOKShapeSlider* Slider)
{
	const FStyleControl* Def = Slider ? FindControl(Slider->StyleParameter) : nullptr;
	if (Def) Slider->SetValue(Def->Field ? FOKStudioStyleTuning().*Def->Field : 0.f);
	if (Slider) Slider->OnSliderMoved(Slider->GetValue());
}

void UOKCharacterController::ApplyCharacterStyle()
{
	if (!IsValid(PreviewActor) || !bModelLayout) return;
	if (StyledActor != PreviewActor)
	{
		StyledActorLocation = PreviewActor->GetActorLocation();
		StyledScale = 1.f;
	}
	StyledActor = PreviewActor;
	TArray<float> Body = Selected.Body.ShapeValueBody, Face = Selected.Face.ShapeValueFace;
	OKStudioStyleSliders(CharacterStyle, Body, Face);
	const float Scale = OKStudioStyleScale(CharacterStyle, Selected.Body.ShapeValueBody, Body);
	PreviewActor->Session.SetStyleBones(OKStudioStyleBones(CharacterStyle, Scale));
	PreviewActor->SetActorScale3D(FVector(Scale));
	const float Height = Selected.Body.ShapeValueBody.IsValidIndex(0) ? Selected.Body.ShapeValueBody[0] : 0.5f;
	PreviewActor->SetActorLocation(StyledActorLocation + FVector(0.f, 0.f, OKStudioStyleLift(CharacterStyle, Scale, Height)));
	PreviewActor->MarkShapeDirty(Face, Body);
	// The view keeps the character's framing as it grows.
	const float Growth = Scale / StyledScale;
	StyledScale = Scale;
	PreviewActor->OrbitFocus = StyledActorLocation + (PreviewActor->OrbitFocus - StyledActorLocation) * Growth;
	PreviewActor->OrbitDistance *= Growth;
	PreviewActor->ApplyOrbitCamera();
}

static FAutoConsoleCommand GalleryStyleCmd(TEXT("ok.GalleryStyle"), TEXT("ok.GalleryStyle <key> <value>: a slider of the card reader's 角色風格 (keys: style, heads, hips, ...)"),
	FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
	{
		if (Args.Num() < 2) return;
		for (TObjectIterator<UOKCharacterController> It; It; ++It)
			for (UOKShapeSlider* Slider : It->StyleSliders)
				if (Slider && Slider->StyleParameter == Args[0]) Slider->SetValue(FCString::Atof(*Args[1])), Slider->OnSliderMoved(Slider->GetValue());
	}));
