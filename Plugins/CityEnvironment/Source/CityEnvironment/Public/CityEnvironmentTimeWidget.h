#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "CityLanguage.h"
#include "CityEnvironmentTimeWidget.generated.h"

class ACityEnvironmentController;
class UBorder;
class UButton;
class UEditableTextBox;
class USlider;
class UTextBlock;
class UVerticalBox;

/**
 * Native time controls. The root does not take hits, so an empty screen
 * does not steal camera clicks. Collapsed while hidden.
 */
UCLASS()
class CITYENVIRONMENT_API UCityEnvironmentTimeWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	void SetController(ACityEnvironmentController* InController);
	void SyncFromController();

	UFUNCTION(BlueprintCallable, Category="City|Environment")
	void SetHour(double Hour);

	UFUNCTION(BlueprintCallable, Category="City|Environment")
	void SetPaused(bool bPaused);

	UFUNCTION(BlueprintCallable, Category="City|Environment")
	void SetTimeScale(double Scale);

	UFUNCTION(BlueprintCallable, Category="City|Environment")
	void SetControlsVisible(bool bVisible);

	UFUNCTION(BlueprintCallable, Category="City|Environment")
	void ApplyLanguage(ECityLanguage Language);

	UFUNCTION(BlueprintCallable, Category="City|Environment")
	FString GetDateText() const;

	virtual TSharedRef<SWidget> RebuildWidget() override;

protected:
	virtual void NativeConstruct() override;
	virtual void NativeDestruct() override;

private:
	void BuildTree();
	void BindLanguage();
	void RefreshTexts();
	ECityLanguage ResolveLanguage() const;

	UFUNCTION()
	void HandleHourChanged(float Value);

	UFUNCTION()
	void HandleSpeedChanged(float Value);

	UFUNCTION()
	void HandlePauseClicked();

	UFUNCTION()
	void HandleDateCommitted(const FText& Text, ETextCommit::Type Method);
	UFUNCTION()
	void HandleSaveClicked();
	UFUNCTION()
	void HandleLoadClicked();

	UFUNCTION()
	void HandleLanguageChanged(ECityLanguage Language);

	TWeakObjectPtr<ACityEnvironmentController> Controller;
	TObjectPtr<UTextBlock> TitleText;
	TObjectPtr<UTextBlock> DateText;
	TObjectPtr<UTextBlock> HourText;
	TObjectPtr<UTextBlock> SpeedText;
	TObjectPtr<UTextBlock> HintText;
	TObjectPtr<USlider> HourSlider;
	TObjectPtr<USlider> SpeedSlider;
	TObjectPtr<UButton> PauseButton;
	TObjectPtr<UTextBlock> PauseLabel;
	UPROPERTY(Transient)
	TObjectPtr<UEditableTextBox> DateInput;
	UPROPERTY(Transient)
	TObjectPtr<UButton> SaveButton;
	UPROPERTY(Transient)
	TObjectPtr<UButton> LoadButton;
	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> SaveLabel;
	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> LoadLabel;
	ECityLanguage ShownLanguage = ECityLanguage::TraditionalChinese;
	bool bApplyingUi = false;
	bool bLanguageBound = false;
	bool bTreeBuilt = false;
	bool bUiSnapshot = false;
	FDateTime LastUiTime;
	double LastUiScale = 0;
	bool bLastUiPaused = false;
	bool bLastUiVisible = false;
	ECityLanguage LastUiLanguage = ECityLanguage::TraditionalChinese;
};
