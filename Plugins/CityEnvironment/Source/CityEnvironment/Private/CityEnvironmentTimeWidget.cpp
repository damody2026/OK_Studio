#include "CityEnvironmentTimeWidget.h"
#include "Engine/GameInstance.h"

#include "CityEnvironmentCelestial.h"
#include "CityEnvironmentController.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/Slider.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Styling/CoreStyle.h"

namespace
{
	struct FCityTimeCopy
	{
		const TCHAR* Title;
		const TCHAR* Pause;
		const TCHAR* Resume;
		const TCHAR* Speed;
		const TCHAR* Date;
		const TCHAR* Hour;
		const TCHAR* Hint;
	};

	const FCityTimeCopy& CopyFor(ECityLanguage Language)
	{
		static const FCityTimeCopy Traditional = {
			TEXT("時間"), TEXT("暫停"), TEXT("繼續"), TEXT("速度"), TEXT("日期"), TEXT("時刻"), TEXT("F8 顯示或隱藏")
		};
		static const FCityTimeCopy Simplified = {
			TEXT("时间"), TEXT("暂停"), TEXT("继续"), TEXT("速度"), TEXT("日期"), TEXT("时刻"), TEXT("F8 显示或隐藏")
		};
		static const FCityTimeCopy English = {
			TEXT("Time"), TEXT("Pause"), TEXT("Resume"), TEXT("Speed"), TEXT("Date"), TEXT("Hour"), TEXT("F8 show or hide")
		};
		switch (Language)
		{
		case ECityLanguage::SimplifiedChinese:
			return Simplified;
		case ECityLanguage::English:
			return English;
		default:
			return Traditional;
		}
	}

	UTextBlock* MakeText(UWidgetTree* Tree, const FName& Name, int32 Size)
	{
		UTextBlock* Text = Tree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), Name);
		if (Text)
		{
			Text->SetFont(FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), Size));
			Text->SetColorAndOpacity(FSlateColor(FLinearColor::White));
		}
		return Text;
	}
}

void UCityEnvironmentTimeWidget::SetController(ACityEnvironmentController* InController)
{
	Controller = InController;
	SyncFromController();
}

TSharedRef<SWidget> UCityEnvironmentTimeWidget::RebuildWidget()
{
	if (WidgetTree && !bTreeBuilt)
	{
		BuildTree();
	}
	return Super::RebuildWidget();
}

void UCityEnvironmentTimeWidget::NativeConstruct()
{
	Super::NativeConstruct();
	if (!bTreeBuilt)
	{
		BuildTree();
	}
	BindLanguage();
	RefreshTexts();
	SyncFromController();
}

void UCityEnvironmentTimeWidget::NativeDestruct()
{
	if (bLanguageBound)
	{
		if (UWorld* World = GetWorld())
		{
			if (UGameInstance* Instance = World->GetGameInstance())
			{
				if (UCityLanguageSubsystem* Language = Instance->GetSubsystem<UCityLanguageSubsystem>())
				{
					Language->OnLanguageChanged.RemoveDynamic(this, &UCityEnvironmentTimeWidget::HandleLanguageChanged);
				}
			}
		}
		bLanguageBound = false;
	}
	Super::NativeDestruct();
}

void UCityEnvironmentTimeWidget::BuildTree()
{
	if (!WidgetTree || bTreeBuilt)
	{
		return;
	}
	UCanvasPanel* Canvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("TimeCanvas"));
	UBorder* Panel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("TimePanel"));
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("TimeColumn"));
	TitleText = MakeText(WidgetTree, TEXT("TimeTitle"), 18);
	DateText = MakeText(WidgetTree, TEXT("TimeDate"), 14);
	HourText = MakeText(WidgetTree, TEXT("TimeHour"), 14);
	HourSlider = WidgetTree->ConstructWidget<USlider>(USlider::StaticClass(), TEXT("HourSlider"));
	PauseButton = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass(), TEXT("PauseButton"));
	PauseLabel = MakeText(WidgetTree, TEXT("PauseLabel"), 14);
	DateInput = WidgetTree->ConstructWidget<UEditableTextBox>(UEditableTextBox::StaticClass(), TEXT("DateInput"));
	FEditableTextBoxStyle DateStyle=DateInput->GetWidgetStyle();DateStyle.SetFont(FCoreStyle::GetDefaultFontStyle(TEXT("Regular"),13));DateInput->SetWidgetStyle(DateStyle);DateInput->SetForegroundColor(FLinearColor(.06f,.08f,.12f,1.f));
	DateInput->SetHintText(FText::FromString(TEXT("YYYY-MM-DDTHH:MM:SS")));
	DateInput->OnTextCommitted.AddDynamic(this, &UCityEnvironmentTimeWidget::HandleDateCommitted);
	SaveButton = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass(), TEXT("SaveClock"));
	LoadButton = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass(), TEXT("LoadClock"));
	SaveLabel = MakeText(WidgetTree, TEXT("SaveClockLabel"), 14);
	LoadLabel = MakeText(WidgetTree, TEXT("LoadClockLabel"), 14);
	SaveButton->SetContent(SaveLabel);
	LoadButton->SetContent(LoadLabel);
	SaveButton->OnClicked.AddDynamic(this, &UCityEnvironmentTimeWidget::HandleSaveClicked);
	LoadButton->OnClicked.AddDynamic(this, &UCityEnvironmentTimeWidget::HandleLoadClicked);
	UHorizontalBox* StorageRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ClockStorage"));
	StorageRow->AddChildToHorizontalBox(SaveButton)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	StorageRow->AddChildToHorizontalBox(LoadButton)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	SpeedText = MakeText(WidgetTree, TEXT("TimeSpeed"), 14);
	SpeedSlider = WidgetTree->ConstructWidget<USlider>(USlider::StaticClass(), TEXT("SpeedSlider"));
	HintText = MakeText(WidgetTree, TEXT("TimeHint"), 12);
	if (!Canvas || !Panel || !Column || !HourSlider || !SpeedSlider || !PauseButton)
	{
		return;
	}
	Canvas->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	Panel->SetBrushColor(FLinearColor(0.02f, 0.03f, 0.05f, 0.84f));
	Panel->SetPadding(FMargin(12.0f));
	Panel->SetVisibility(ESlateVisibility::Visible);
	HourSlider->SetMinValue(0.0f);
	HourSlider->SetMaxValue(24.0f);
	SpeedSlider->SetMinValue(0.0f);
	SpeedSlider->SetMaxValue(24.0f);
	PauseButton->SetBackgroundColor(FLinearColor(0.15f, 0.17f, 0.22f, 0.95f));
	if (PauseLabel)
	{
		PauseButton->SetContent(PauseLabel);
	}
	auto AddRow = [Column](UWidget* Child)
	{
		if (!Child)
		{
			return;
		}
		if (UVerticalBoxSlot* LayoutSlot = Column->AddChildToVerticalBox(Child))
		{
			LayoutSlot->SetPadding(FMargin(0.0f, 3.0f));
			LayoutSlot->SetHorizontalAlignment(HAlign_Fill);
		}
	};
	AddRow(TitleText);
	AddRow(DateText);
	AddRow(DateInput);
	AddRow(HourText);
	AddRow(HourSlider);
	AddRow(PauseButton);
	AddRow(SpeedText);
	AddRow(SpeedSlider);
	AddRow(StorageRow);
	AddRow(HintText);
	Panel->SetContent(Column);
	if (UCanvasPanelSlot* LayoutSlot = Canvas->AddChildToCanvas(Panel))
	{
		LayoutSlot->SetAnchors(FAnchors(0.0f, 0.0f));
		LayoutSlot->SetAlignment(FVector2D(0.0f, 0.0f));
		LayoutSlot->SetPosition(FVector2D(24.0f, 24.0f));
		LayoutSlot->SetAutoSize(false);
		LayoutSlot->SetSize(FVector2D(340.0f, 338.0f));
	}
	WidgetTree->RootWidget = Canvas;
	HourSlider->OnValueChanged.AddDynamic(this, &UCityEnvironmentTimeWidget::HandleHourChanged);
	SpeedSlider->OnValueChanged.AddDynamic(this, &UCityEnvironmentTimeWidget::HandleSpeedChanged);
	PauseButton->OnClicked.AddDynamic(this, &UCityEnvironmentTimeWidget::HandlePauseClicked);
	bTreeBuilt = true;
	SetVisibility(ESlateVisibility::SelfHitTestInvisible);
}

void UCityEnvironmentTimeWidget::BindLanguage()
{
	if (bLanguageBound)
	{
		return;
	}
	if (UWorld* World = GetWorld())
	{
		if (UGameInstance* Instance = World->GetGameInstance())
		{
			if (UCityLanguageSubsystem* Language = Instance->GetSubsystem<UCityLanguageSubsystem>())
			{
				Language->OnLanguageChanged.AddDynamic(this, &UCityEnvironmentTimeWidget::HandleLanguageChanged);
				ShownLanguage = Language->GetLanguage();
				bLanguageBound = true;
			}
		}
	}
}

ECityLanguage UCityEnvironmentTimeWidget::ResolveLanguage() const
{
	if (const UWorld* World = GetWorld())
	{
		if (const UGameInstance* Instance = World->GetGameInstance())
		{
			if (const UCityLanguageSubsystem* Language = Instance->GetSubsystem<UCityLanguageSubsystem>())
			{
				return Language->GetLanguage();
			}
		}
	}
	return ShownLanguage;
}

void UCityEnvironmentTimeWidget::ApplyLanguage(ECityLanguage Language)
{
	ShownLanguage = Language;
	RefreshTexts();
}

void UCityEnvironmentTimeWidget::RefreshTexts()
{
	const FCityTimeCopy& Copy = CopyFor(ResolveLanguage());
	const ECityLanguage Language = ResolveLanguage();
	if (SaveLabel) SaveLabel->SetText(FText::FromString(Language == ECityLanguage::English ? TEXT("Save time") : Language == ECityLanguage::SimplifiedChinese ? TEXT("保存时间") : TEXT("儲存時間")));
	if (LoadLabel) LoadLabel->SetText(FText::FromString(Language == ECityLanguage::English ? TEXT("Load time") : Language == ECityLanguage::SimplifiedChinese ? TEXT("读取时间") : TEXT("讀取時間")));
	if (TitleText)
	{
		TitleText->SetText(FText::FromString(Copy.Title));
	}
	if (HintText)
	{
		HintText->SetText(FText::FromString(Copy.Hint));
	}
	if (PauseLabel)
	{
		const bool bPaused = !Controller.IsValid() || Controller->IsClockPaused();
		PauseLabel->SetText(FText::FromString(bPaused ? Copy.Resume : Copy.Pause));
	}
	if (DateText)
	{
		DateText->SetText(FText::FromString(FString::Printf(TEXT("%s  %s"), Copy.Date, *GetDateText())));
	}
	if (HourText && Controller.IsValid())
	{
		const double Hour = FCityEnvironmentCelestial::HourOfDay(Controller->GetLocalDateTime());
		const int32 Whole = FMath::Clamp(FMath::FloorToInt(Hour), 0, 23);
		const int32 Minute = FMath::Clamp(FMath::FloorToInt((Hour - Whole) * 60.0), 0, 59);
		HourText->SetText(FText::FromString(FString::Printf(TEXT("%s  %02d:%02d"), Copy.Hour, Whole, Minute)));
	}
	if (SpeedText && Controller.IsValid())
	{
		SpeedText->SetText(FText::FromString(FString::Printf(TEXT("%s  %.2f"), Copy.Speed, Controller->GetTimeScale())));
	}
}

FString UCityEnvironmentTimeWidget::GetDateText() const
{
	if (!Controller.IsValid())
	{
		return FString();
	}
	return FCityEnvironmentCelestial::ToIso8601(Controller->GetLocalDateTime());
}

void UCityEnvironmentTimeWidget::SyncFromController()
{
	if (!Controller.IsValid() || !bTreeBuilt)
	{
		return;
	}
	const FDateTime Now=Controller->GetLocalDateTime();const double Scale=Controller->GetTimeScale();const bool IsPaused=Controller->IsClockPaused();const bool bUiVisible=Controller->ShouldShowTimeControls();const ECityLanguage Language=ResolveLanguage();
	if(bUiSnapshot&&LastUiTime==Now&&LastUiScale==Scale&&bLastUiPaused==IsPaused&&bLastUiVisible==bUiVisible&&LastUiLanguage==Language)return;
	bUiSnapshot=true;LastUiTime=Now;LastUiScale=Scale;bLastUiPaused=IsPaused;bLastUiVisible=bUiVisible;LastUiLanguage=Language;
	bApplyingUi = true;
	if (HourSlider)
	{
		const float Hour = static_cast<float>(FCityEnvironmentCelestial::HourOfDay(Controller->GetLocalDateTime()));
		HourSlider->SetValue(FMath::Clamp(Hour, 0.0f, 24.0f));
	}
	if (SpeedSlider)
	{
		SpeedSlider->SetValue(FMath::Clamp(static_cast<float>(Controller->GetTimeScale()), 0.0f, 24.0f));
	}
	bApplyingUi = false;
	RefreshTexts();
	SetControlsVisible(Controller->ShouldShowTimeControls());
}

void UCityEnvironmentTimeWidget::SetHour(double Hour)
{
	if (Controller.IsValid())
	{
		Controller->SetHour(Hour);
	}
}

void UCityEnvironmentTimeWidget::SetPaused(bool bPaused)
{
	if (Controller.IsValid())
	{
		Controller->SetPaused(bPaused);
	}
}

void UCityEnvironmentTimeWidget::SetTimeScale(double Scale)
{
	if (Controller.IsValid())
	{
		Controller->SetTimeScale(Scale);
	}
}

void UCityEnvironmentTimeWidget::SetControlsVisible(bool bVisible)
{
	SetVisibility(bVisible ? ESlateVisibility::SelfHitTestInvisible : ESlateVisibility::Collapsed);
}

void UCityEnvironmentTimeWidget::HandleHourChanged(float Value)
{
	if (bApplyingUi || !Controller.IsValid())
	{
		return;
	}
	Controller->SetHour(static_cast<double>(Value));
}

void UCityEnvironmentTimeWidget::HandleSpeedChanged(float Value)
{
	if (bApplyingUi || !Controller.IsValid())
	{
		return;
	}
	Controller->SetTimeScale(static_cast<double>(Value));
}

void UCityEnvironmentTimeWidget::HandlePauseClicked()
{
	if (!Controller.IsValid())
	{
		return;
	}
	Controller->SetPaused(!Controller->IsClockPaused());
}

void UCityEnvironmentTimeWidget::HandleLanguageChanged(ECityLanguage Language)
{
	ApplyLanguage(Language);
}

void UCityEnvironmentTimeWidget::HandleDateCommitted(const FText& Text, ETextCommit::Type Method)
{
	if (!Controller.IsValid() || Method == ETextCommit::OnCleared) return;
	FDateTime Value;
	if (FDateTime::ParseIso8601(*Text.ToString(), Value))
	{
		Controller->SetDateTime(Value);
		DateInput->SetError(FText::GetEmpty());
	}
	else if (!Text.IsEmpty()) DateInput->SetError(FText::FromString(TEXT("YYYY-MM-DDTHH:MM:SS")));
}

void UCityEnvironmentTimeWidget::HandleSaveClicked()
{
	if (Controller.IsValid()) Controller->SaveClock();
}

void UCityEnvironmentTimeWidget::HandleLoadClicked()
{
	if (Controller.IsValid()) Controller->LoadClock();
}
