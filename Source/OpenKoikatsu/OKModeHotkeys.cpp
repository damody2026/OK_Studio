// Mod hotkeys in OK Studio and the one-on-one (Docs/OK_MOD_E_WAVE5.md; how to wire a mode: Docs/OK_MOD_F_WAVE4.md §5).
//
// Studio: a reply is one of the studio's effects (status, data, ops, run, …) applied as the bridge applies a key of the
// mod's panel: one undo step of its own (OKStudioModBridge::ApplyHotkeyReply).
// One-on-one: {"pair": {"her", "his"}} sets the H scene's gauges (as the other pair hooks' replies do); a text, "notice"
// or "status" shows in the H panel's hint line, or as a screen note outside the H scene.
#include "OKModeHotkeys.h"
#include "OKModKeys.h"
#include "OKCharacterController.h"
#include "OKHScene.h"
#include "Components/TextBlock.h"
#include "Dom/JsonObject.h"

namespace OKStudioModBridge
{
	void ApplyHotkeyReply(const FString& Mod, const TSharedPtr<FJsonObject>& Reply);
}

namespace OKModeHotkeys
{
	void StudioStart()
	{
		FOKModKeys::Listen(TEXT("studio"), [](const FString& Mod, const TSharedPtr<FJsonObject>& Reply)
		{
			// The bridge checks that the studio is still up (its state, not a captured pointer).
			OKStudioModBridge::ApplyHotkeyReply(Mod, Reply);
		});
	}

	void StudioStop() { FOKModKeys::Stop(TEXT("studio")); }

	void PairStart(UOKCharacterController* Controller)
	{
		FOKModKeys::Listen(TEXT("pair"), [Weak = TWeakObjectPtr<UOKCharacterController>(Controller)](const FString& Mod, const TSharedPtr<FJsonObject>& Reply)
		{
			UOKCharacterController* C = Weak.Get();
			if (!C || !Reply.IsValid()) { UE_LOG(LogTemp, Display, TEXT("[%s] pair hotkey reply not shown: no scene"), *Mod); return; }
			UOKHScenePanel* Panel = C->HPanel.Get();
			const TSharedPtr<FJsonObject>* Json = nullptr;
			const TSharedPtr<FJsonObject>* Gauges = nullptr;
			if (Panel && Reply->TryGetObjectField(TEXT("json"), Json) && Json && Json->IsValid() && (*Json)->TryGetObjectField(TEXT("pair"), Gauges) && Gauges && Gauges->IsValid())
			{
				double HerValue = -1.0, HisValue = -1.0;
				(*Gauges)->TryGetNumberField(TEXT("her"), HerValue);
				(*Gauges)->TryGetNumberField(TEXT("his"), HisValue);
				Panel->SetGauges(float(HerValue), float(HisValue));
			}
			const FString Shown = FOKModKeys::ShownText(Reply);
			if (Shown.IsEmpty()) return;
			UE_LOG(LogTemp, Display, TEXT("[%s] pair hotkey reply shown %s: %s"), *Mod, Panel ? TEXT("in the H panel's hint") : TEXT("as a screen note"), *Shown);
			if (Panel) Panel->ShowHint(FString::Printf(TEXT("[%s] %s"), *Mod, *Shown));
			else C->ScreenNote(42, 4.f, FColor::Cyan, FString::Printf(TEXT("[%s] %s"), *Mod, *Shown));
		});
	}

	void PairStop() { FOKModKeys::Stop(TEXT("pair")); }
}

void UOKHScenePanel::ShowHint(const FString& Text)
{
	if (Hint) Hint->SetText(FText::FromString(Text));
}
