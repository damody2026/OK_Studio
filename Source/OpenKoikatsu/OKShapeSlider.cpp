#include "OKShapeSlider.h"
#include "OKGalleryWidget.h"
#include "Components/TextBlock.h"
#include "Components/EditableTextBox.h"
#include "Blueprint/WidgetTree.h"
#include "Components/SizeBox.h"
#include "Styling/CoreStyle.h"

void UOKShapeSlider::OnResetClicked()
{
	if(Owner&&!StyleParameter.IsEmpty()){Owner->OnStyleReset(this);return;}
	if(Owner&&!BodyParameter.IsEmpty()){Owner->OnBodyPhysicsChanged(BodyParameter,.5f);Owner->SyncBoneSliders();return;}
	if(Owner&&!PregnancyParameter.IsEmpty()){Owner->OnPregnancyChanged(PregnancyParameter,0.f);Owner->SyncBoneSliders();return;}
	if(Owner&&!ModBone.IsEmpty()){Owner->OnBoneChanged(this,ModAxis>=4?0.f:1.f);return;}
	if (Owner && AnimationParameter.IsEmpty()) Owner->ResetShape(bBody, Index);
}

bool UOKShapeSlider::ShowsPercent() const
{
	return StyleParameter.IsEmpty() && AnimationParameter.IsEmpty() && PregnancyParameter.IsEmpty() && ModAxis < 7;
}

UWidget* UOKShapeSlider::MakeValueField(UWidgetTree* Tree, int32 FontSize, float MinWidth)
{
	UEditableTextBox* Box = Tree->ConstructWidget<UEditableTextBox>(UEditableTextBox::StaticClass());
	FEditableTextBoxStyle Style = Box->GetWidgetStyle();
	Style.SetFont(FCoreStyle::GetDefaultFontStyle("Regular", FontSize));
	Style.SetPadding(FMargin(2.f, 0.f));
	Style.SetForegroundColor(FSlateColor(FLinearColor::White));
	Style.SetFocusedForegroundColor(FSlateColor(FLinearColor::White));
	Style.SetBackgroundColor(FSlateColor(FLinearColor(0.f, 0.f, 0.f, 0.35f)));
	Box->SetWidgetStyle(Style);
	Box->SetJustification(ETextJustify::Center);
	Box->SetSelectAllTextWhenFocused(true);
	Box->SetRevertTextOnEscape(true);
	Box->SetClearKeyboardFocusOnCommit(true);
	Box->OnTextCommitted.AddDynamic(this, &UOKShapeSlider::OnValueCommitted);
	ValueLabel = Box;
	USizeBox* Size = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
	Size->SetMinDesiredWidth(MinWidth);
	Size->SetContent(Box);
	return Size;
}

void UOKShapeSlider::RefreshValueLabel(bool bForce)
{
	if (!ValueLabel) return;
	// Slider syncs (card reload, MCP, another control) must not overwrite what the user is typing.
	if (!bForce && ValueLabel->HasKeyboardFocus()) return;
	if (!StyleParameter.IsEmpty())
	{
		ValueLabel->SetText(FText::FromString(FString::Printf(TEXT("%.2f"),GetValue())));
	}
	else
	{
		ValueLabel->SetText(ShowsPercent()?FText::AsNumber(FMath::RoundToInt(GetValue()*100.f)):FText::AsNumber(GetValue()));
	}
}

void UOKShapeSlider::OnValueCommitted(const FText& Text, ETextCommit::Type Method)
{
	// Esc (OnCleared) reverts; non-numbers revert; out-of-range numbers clamp to the slider's range.
	if (Method == ETextCommit::OnCleared) { RefreshValueLabel(true); return; }
	FString Input = Text.ToString().TrimStartAndEnd();
	Input.ReplaceInline(TEXT(","), TEXT(""));
	double Number = 0.;
	if (Input.IsEmpty() || !LexTryParseString(Number, *Input) || !FMath::IsFinite(Number)) { RefreshValueLabel(true); return; }
	const float Typed = FMath::Clamp(float(ShowsPercent() ? Number / 100. : Number), GetMinValue(), GetMaxValue());
	SetValue(Typed);
	// SetValue does not broadcast OnValueChanged: apply as a drag would, then show the clamped value.
	OnSliderMoved(GetValue());
	RefreshValueLabel(true);
}

void UOKShapeSlider::OnSliderMoved(float NewValue)
{
	RefreshValueLabel();
	if (Owner)
	{
		if(!StyleParameter.IsEmpty()) Owner->OnStyleChanged(StyleParameter,NewValue);
		else if(!BodyParameter.IsEmpty()) Owner->OnBodyPhysicsChanged(BodyParameter,NewValue);
		else if(!PregnancyParameter.IsEmpty()) Owner->OnPregnancyChanged(PregnancyParameter,NewValue);
		else if(!ModBone.IsEmpty()) Owner->OnBoneChanged(this,NewValue);
		else if(AnimationParameter.IsEmpty()) Owner->OnShapeChanged(bBody,Index,NewValue);
		else Owner->OnGameAnimationParameter(AnimationParameter,NewValue);
	}
}

void UOKShapeSlider::OnModSideChanged(FString SelectedSide,ESelectInfo::Type Type){if(Owner)Owner->SyncBoneSliders();}
