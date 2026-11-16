#pragma once

#include "CoreMinimal.h"
#include "Components/Slider.h"
#include "Components/ComboBoxString.h"
#include "OKShapeSlider.generated.h"

class UOKCharacterController;
class UTextBlock;
class UEditableTextBox;
class UComboBoxString;
class UButton;

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

	// The number after the slider; it can be typed into (Enter or leaving it applies, Esc reverts).
	UPROPERTY()
	TObjectPtr<UEditableTextBox> ValueLabel;

	// Builds ValueLabel (styled, bound to OnValueCommitted) and returns it, wrapped to MinWidth, for the caller's layout.
	UWidget* MakeValueField(class UWidgetTree* Tree, int32 FontSize, float MinWidth = 40.f);

	// bForce also rewrites the field while the user is typing into it.
	void RefreshValueLabel(bool bForce = false);

	// The field shows the slider value x100 rounded (card shape rows) rather than the raw value.
	bool ShowsPercent() const;

	UFUNCTION()
	void OnValueCommitted(const FText& Text, ETextCommit::Type Method);

	UFUNCTION()
	void OnSliderMoved(float NewValue);

	UFUNCTION()
	void OnResetClicked();
};
