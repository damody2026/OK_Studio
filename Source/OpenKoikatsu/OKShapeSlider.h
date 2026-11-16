#pragma once

#include "CoreMinimal.h"
#include "Components/Slider.h"
#include "Components/ComboBoxString.h"
#include "Components/EditableTextBox.h"
#include "OKShapeSlider.generated.h"

class UOKCharacterController;
class UTextBlock;
class UComboBoxString;
class UButton;

// The number after a slider, typed into like a text box: Enter or leaving it applies, Esc reverts, a non-number reverts,
// an out-of-range number clamps to the slider's range. Applying sets the slider and broadcasts its OnValueChanged, so
// the change goes through the same handler as a drag. Used by every slider row with a value (shape, bone, lighting...).
UCLASS()
class OPENKOIKATSU_API UOKValueField : public UEditableTextBox
{
	GENERATED_BODY()

public:
	// Builds a styled field for Slider, wrapped in a size box at least MinWidth wide; Out (optional) gets the field.
	static UWidget* Make(class UWidgetTree* Tree, USlider* Slider, int32 FontSize, float MinWidth, UOKValueField** Out = nullptr);

	TWeakObjectPtr<USlider> Slider;
	// Slider value -> shown text (default: the number as is).
	TFunction<FString(float)> Format;
	// Typed number -> slider value before clamping (default: the number as is; shape rows divide by 100).
	TFunction<double(double)> FromTyped;

	// Shows the slider's value; unless bForce, leaves the field alone while the user is typing in it.
	void Refresh(bool bForce = false);

	UFUNCTION()
	void OnValueCommitted(const FText& Entered, ETextCommit::Type Method);

	// Only digits, sign, decimal point, grouping and the shown unit are taken; any other edit (a letter, a pasted word) is
	// undone at once, so the field never holds anything but a number.
	UFUNCTION()
	void OnValueEdited(const FText& Edited);

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	FString LastValid;
};

UCLASS()
class OPENKOIKATSU_API UOKShapeSlider : public USlider
{
	GENERATED_BODY()

public:
	int32 Index = INDEX_NONE;
	bool bBody = false;
	FString AnimationParameter;
 FString ModBone, ModRight, ModCategory, PregnancyParameter, BodyParameter, StyleParameter;
 int32 ModAxis=-1;
 bool ModCoordinateSpecific=false;
 UPROPERTY() TObjectPtr<UComboBoxString> ModSide;
 UPROPERTY() TObjectPtr<UWidget> ModRow;
 UPROPERTY() TObjectPtr<UButton> ModReset;
 UFUNCTION() void OnModSideChanged(FString SelectedSide, ESelectInfo::Type Type);

	UPROPERTY()
	TObjectPtr<UOKCharacterController> Owner;

	// The number after the slider; it can be typed into (UOKValueField).
	UPROPERTY()
	TObjectPtr<UOKValueField> ValueLabel;

	// Builds ValueLabel and returns it, wrapped to MinWidth, for the caller's layout.
	UWidget* MakeValueField(class UWidgetTree* Tree, int32 FontSize, float MinWidth = 40.f);

	// bForce also rewrites the field while the user is typing into it.
	void RefreshValueLabel(bool bForce = false);

	// The field shows the slider value x100 rounded (card shape rows) rather than the raw value.
	bool ShowsPercent() const;
	FString FormatValue(float Shown) const;

	UFUNCTION()
	void OnSliderMoved(float NewValue);

	UFUNCTION()
	void OnResetClicked();
};
