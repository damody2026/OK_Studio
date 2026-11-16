#include "OKShapeSlider.h"
#include "OKGalleryWidget.h"
#include "Components/TextBlock.h"
#include "Components/EditableTextBox.h"
#include "Blueprint/WidgetTree.h"
#include "Components/SizeBox.h"
#include "Styling/CoreStyle.h"
#include "Containers/Ticker.h"
#include "Framework/Application/SlateApplication.h"
#include "Widgets/SWindow.h"
#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include <msctf.h>
#include "Windows/HideWindowsPlatformTypes.h"
#endif

namespace
{
	// The Slate widgets of every value field, to recognise one when it takes the keyboard.
	TArray<TWeakPtr<SWidget>> GValueFieldWidgets;

	// A value field holds a number: the input method stays off while it has the keyboard. Slate turns the IME on for any
	// text field it focuses, and with 注音 (Bopomofo) the main keyboard's "." is ㄡ: it started a composition that took the
	// next keys too, and "1.5" ended as "1" (2026-11-16). Off is what the game viewport has anyway; the next text field to
	// take the keyboard turns it on again for itself.
	void DisableInputMethod(const TSharedRef<SWidget>& Focused)
	{
#if PLATFORM_WINDOWS
		const TSharedPtr<SWindow> Window = FSlateApplication::Get().FindWidgetWindow(Focused);
		if (!Window || !Window->GetNativeWindow()) return;
		const HWND Hwnd = static_cast<HWND>(Window->GetNativeWindow()->GetOSWindowHandle());
		// IMM: no input context for the window (imm32 is loaded by the engine; looked up so nothing new is linked).
		if (HMODULE Imm = ::GetModuleHandleW(L"imm32.dll"))
		{
			using FAssociate = BOOL(WINAPI*)(HWND, void*, DWORD);
			if (const FAssociate Associate = reinterpret_cast<FAssociate>(::GetProcAddress(Imm, "ImmAssociateContextEx"))) Associate(Hwnd, nullptr, 0);
		}
		// TSF: focus a document manager with no context in it, as the engine does for a viewport.
		static const CLSID ThreadMgrClass = { 0x529a9e6b, 0x6587, 0x4f23, { 0xab, 0x9e, 0x9c, 0x7d, 0x68, 0x3e, 0x3c, 0x50 } };
		ITfThreadMgr* Manager = nullptr;
		if (SUCCEEDED(::CoCreateInstance(ThreadMgrClass, nullptr, CLSCTX_INPROC_SERVER, __uuidof(ITfThreadMgr), reinterpret_cast<void**>(&Manager))) && Manager)
		{
			static ITfDocumentMgr* Empty = nullptr;
			if (!Empty) Manager->CreateDocumentMgr(&Empty);
			if (Empty)
			{
				ITfDocumentMgr* Previous = nullptr;
				Manager->AssociateFocus(Hwnd, Empty, &Previous);
				if (Previous) Previous->Release();
				Manager->SetFocus(Empty);
			}
			Manager->Release();
		}
#endif
	}

	bool IsValueField(TSharedPtr<SWidget> Widget)
	{
		for (int32 Depth = 0; Depth < 8 && Widget; ++Depth, Widget = Widget->GetParentWidget())
			for (const TWeakPtr<SWidget>& Field : GValueFieldWidgets)
				if (Field.Pin() == Widget) return true;
		return false;
	}

	void HookFocus()
	{
		static bool bHooked = false;
		if (bHooked || !FSlateApplication::IsInitialized()) return;
		bHooked = true;
		FSlateApplication::Get().OnFocusChanging().AddLambda([](const FFocusEvent&, const FWeakWidgetPath&, const TSharedPtr<SWidget>&, const FWidgetPath&, const TSharedPtr<SWidget>& Focused)
		{
			if (!Focused || !IsValueField(Focused)) return;
			// Next frame: after Slate's own focus handling, which is what turns the IME on.
			TWeakPtr<SWidget> Weak = Focused;
			FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak](float)
			{
				if (const TSharedPtr<SWidget> Widget = Weak.Pin(); Widget && Widget->HasKeyboardFocus()) DisableInputMethod(Widget.ToSharedRef());
				return false;
			}));
		});
	}
}

TSharedRef<SWidget> UOKValueField::RebuildWidget()
{
	TSharedRef<SWidget> Widget = Super::RebuildWidget();
	GValueFieldWidgets.RemoveAll([](const TWeakPtr<SWidget>& W) { return !W.IsValid(); });
	GValueFieldWidgets.Add(Widget);
	HookFocus();
	return Widget;
}

void UOKValueField::OnValueEdited(const FText& Edited)
{
	const FString Typed = Edited.ToString();
	for (const TCHAR C : Typed)
	{
		if (!(FChar::IsDigit(C) || C == TEXT('-') || C == TEXT('+') || C == TEXT('.') || C == TEXT(',') || C == TEXT(' ') || C == TEXT('°') || C == TEXT('%')))
		{
			SetText(FText::FromString(LastValid));
			return;
		}
	}
	LastValid = Typed;
}

UWidget* UOKValueField::Make(UWidgetTree* Tree, USlider* Slider, int32 FontSize, float MinWidth, UOKValueField** Out)
{
	UOKValueField* Box = Tree->ConstructWidget<UOKValueField>(UOKValueField::StaticClass());
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
	Box->Slider = Slider;
	Box->OnTextCommitted.AddDynamic(Box, &UOKValueField::OnValueCommitted);
	Box->OnTextChanged.AddDynamic(Box, &UOKValueField::OnValueEdited);
	if (Out) *Out = Box;
	USizeBox* Size = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
	Size->SetMinDesiredWidth(MinWidth);
	Size->SetContent(Box);
	return Size;
}

void UOKValueField::Refresh(bool bForce)
{
	USlider* S = Slider.Get();
	if (!S) return;
	// Slider syncs (card reload, MCP, another control) must not overwrite what the user is typing.
	if (!bForce && HasKeyboardFocus()) return;
	LastValid = Format ? Format(S->GetValue()) : FText::AsNumber(S->GetValue()).ToString();
	SetText(FText::FromString(LastValid));
}

void UOKValueField::OnValueCommitted(const FText& Entered, ETextCommit::Type Method)
{
	USlider* S = Slider.Get();
	if (!S) return;
	// Esc (OnCleared) reverts; non-numbers revert; out-of-range numbers clamp to the slider's range.
	if (Method == ETextCommit::OnCleared) { Refresh(true); return; }
	FString Input = Entered.ToString().TrimStartAndEnd();
	// The shown text may carry grouping or a unit (1,000 / 40°).
	Input.ReplaceInline(TEXT(","), TEXT(""));
	Input.ReplaceInline(TEXT("°"), TEXT(""));
	Input.ReplaceInline(TEXT("%"), TEXT(""));
	Input.TrimStartAndEndInline();
	double Number = 0.;
	if (Input.IsEmpty() || !LexTryParseString(Number, *Input) || !FMath::IsFinite(Number)) { Refresh(true); return; }
	const float Typed = FMath::Clamp(float(FromTyped ? FromTyped(Number) : Number), S->GetMinValue(), S->GetMaxValue());
	S->SetValue(Typed);
	// SetValue does not broadcast: apply through the slider's own handler as a drag would, then show the clamped value.
	S->OnValueChanged.Broadcast(S->GetValue());
	Refresh(true);
}

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

FString UOKShapeSlider::FormatValue(float Shown) const
{
	if (!StyleParameter.IsEmpty()) return FString::Printf(TEXT("%.2f"), Shown);
	return (ShowsPercent() ? FText::AsNumber(FMath::RoundToInt(Shown * 100.f)) : FText::AsNumber(Shown)).ToString();
}

UWidget* UOKShapeSlider::MakeValueField(UWidgetTree* Tree, int32 FontSize, float MinWidth)
{
	UOKValueField* Field = nullptr;
	UWidget* Wrapped = UOKValueField::Make(Tree, this, FontSize, MinWidth, &Field);
	// Asked at use time: the row's kind (style, bone, ...) may be set after the field is built.
	TWeakObjectPtr<UOKShapeSlider> Self(this);
	Field->Format = [Self](float V) { return Self.IsValid() ? Self->FormatValue(V) : FString(); };
	Field->FromTyped = [Self](double N) { return Self.IsValid() && Self->ShowsPercent() ? N / 100. : N; };
	ValueLabel = Field;
	return Wrapped;
}

void UOKShapeSlider::RefreshValueLabel(bool bForce)
{
	if (!ValueLabel) return;
	// A field built elsewhere (tests: NewObject) gets this slider and its format on first use.
	if (!ValueLabel->Slider.IsValid()) ValueLabel->Slider = this;
	if (!ValueLabel->Format)
	{
		TWeakObjectPtr<UOKShapeSlider> Self(this);
		ValueLabel->Format = [Self](float V) { return Self.IsValid() ? Self->FormatValue(V) : FString(); };
	}
	ValueLabel->Refresh(bForce);
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
