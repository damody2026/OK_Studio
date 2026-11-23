// Mod hotkeys in every mode (OKModKeys.h, Docs/OK_MOD_HOOKS.md §5; host side Tools/ok-mod/host/src/keys.rs).
#include "OKModKeys.h"
#include "OKModHost.h"
#include "Framework/Application/IInputProcessor.h"
#include "Framework/Application/SlateApplication.h"
#include "HAL/IConsoleManager.h"
#include "InputCoreTypes.h"
#include "Misc/CoreDelegates.h"

namespace
{
struct FCapture
{
	FString Mod, Name;
	TFunction<void(const FString&, bool)> Done;
};

TMap<FString, FOKModKeys::FOnReply> GListeners;
// The bound chords (normalized as the host does) of the hotkeys the host lists, asked again every second.
TSet<FString> GBound;
double GAskedAt = -1e9;
TOptional<FCapture> GCapture;

// The same comparable form as keys.rs normalize: modifiers (either side) in a fixed order, then the key, lower case.
FString Normalize(const FString& Chord)
{
	bool Mods[4] = {false, false, false, false};
	FString Key;
	TArray<FString> Parts;
	Chord.ParseIntoArray(Parts, TEXT("+"));
	for (FString P : Parts)
	{
		P = P.TrimStartAndEnd().ToLower();
		if (P.IsEmpty()) continue;
		if (P == TEXT("control") || P == TEXT("ctrl") || P == TEXT("leftcontrol") || P == TEXT("rightcontrol")) Mods[0] = true;
		else if (P == TEXT("alt") || P == TEXT("leftalt") || P == TEXT("rightalt")) Mods[1] = true;
		else if (P == TEXT("shift") || P == TEXT("leftshift") || P == TEXT("rightshift")) Mods[2] = true;
		else if (P == TEXT("command") || P == TEXT("cmd") || P == TEXT("leftcommand") || P == TEXT("rightcommand")) Mods[3] = true;
		else if (Key.IsEmpty()) Key = P;
		else return FString();
	}
	if (Key.IsEmpty()) return FString();
	static const TCHAR* Names[] = {TEXT("control"), TEXT("alt"), TEXT("shift"), TEXT("command")};
	FString Out;
	for (int32 I = 0; I < 4; ++I) if (Mods[I]) Out += FString(Names[I]) + TEXT("+");
	return Out + Key;
}

// The chord of a key press in Unreal key names ("Control+Shift+K"); empty for a modifier alone.
FString ChordOf(const FKeyEvent& Event)
{
	const FKey Key = Event.GetKey();
	if (!Key.IsValid() || Key.IsModifierKey() || Key.IsMouseButton()) return FString();
	FString Out;
	if (Event.IsControlDown()) Out += TEXT("Control+");
	if (Event.IsAltDown()) Out += TEXT("Alt+");
	if (Event.IsShiftDown()) Out += TEXT("Shift+");
	if (Event.IsCommandDown()) Out += TEXT("Command+");
	return Out + Key.GetFName().ToString();
}

TSharedRef<FJsonObject> Op(const TCHAR* Name)
{
	TSharedRef<FJsonObject> R = MakeShared<FJsonObject>();
	R->SetStringField(TEXT("op"), Name);
	return R;
}

void Refresh()
{
	GAskedAt = FPlatformTime::Seconds();
	GBound.Reset();
	for (const FOKModKeys::FHotkey& K : FOKModKeys::List())
	{
		const FString N = Normalize(K.Chord);
		if (!N.IsEmpty()) GBound.Add(N);
	}
}

// A text field has the keyboard: typing must not fire mods. Slate's editable texts, and anything else that says so.
bool Typing(FSlateApplication& App)
{
	const TSharedPtr<SWidget> Focused = App.GetKeyboardFocusedWidget();
	if (!Focused.IsValid()) return false;
	const FString Type = Focused->GetType().ToString();
	return Type.Contains(TEXT("EditableText")) || Type.Contains(TEXT("TextBox")) || Type.Contains(TEXT("TextInput"));
}

void Send(const FString& Chord, const FString& Mode)
{
	TSharedRef<FJsonObject> R = Op(TEXT("key"));
	R->SetStringField(TEXT("chord"), Chord);
	R->SetStringField(TEXT("mode"), Mode);
	FString Error;
	const TSharedPtr<FJsonObject> Answer = FOKModHost::Get().DispatchJson(R, Error);
	if (!Answer.IsValid()) { UE_LOG(LogOKMod, Warning, TEXT("hotkey %s: %s"), *Chord, *Error); return; }
	const TArray<TSharedPtr<FJsonValue>>* Replies = nullptr;
	if (!Answer->TryGetArrayField(TEXT("replies"), Replies)) return;
	const FOKModKeys::FOnReply* Handler = GListeners.Find(Mode);
	for (const TSharedPtr<FJsonValue>& V : *Replies)
	{
		const TSharedPtr<FJsonObject> O = V->AsObject();
		if (!O.IsValid()) continue;
		const FString Mod = O->GetStringField(TEXT("mod"));
		bool bOk = false;
		O->TryGetBoolField(TEXT("ok"), bOk);
		if (!bOk) { UE_LOG(LogOKMod, Warning, TEXT("[%s] hotkey %s: %s"), *Mod, *Chord, *O->GetStringField(TEXT("error"))); continue; }
		UE_LOG(LogOKMod, Display, TEXT("[%s] hotkey %s in %s%s%s"), *Mod, *Chord, *Mode, FOKModKeys::ShownText(O).IsEmpty() ? TEXT("") : TEXT(": "), *FOKModKeys::ShownText(O));
		if (Handler && *Handler) (*Handler)(Mod, O);
	}
}

class FProcessor : public IInputProcessor
{
public:
	virtual void Tick(const float, FSlateApplication&, TSharedRef<ICursor>) override
	{
		FOKModHost& Host = FOKModHost::Get();
		if (Host.IsOpen() && GListeners.Contains(Host.CurrentMode()) && FPlatformTime::Seconds() - GAskedAt > 1.0) Refresh();
	}

	virtual bool HandleKeyDownEvent(FSlateApplication& App, const FKeyEvent& Event) override
	{
		if (GCapture.IsSet())
		{
			const FKey Key = Event.GetKey();
			if (Key.IsModifierKey()) return true;	// wait for the key itself
			FCapture C = MoveTemp(GCapture.GetValue());
			GCapture.Reset();
			if (Key == EKeys::Escape) { if (C.Done) C.Done(FString(), true); return true; }
			const FString Chord = Key == EKeys::BackSpace ? FString() : ChordOf(Event);
			FString Error;
			if (!FOKModKeys::Bind(C.Mod, C.Name, Chord, Error)) { UE_LOG(LogOKMod, Warning, TEXT("bind %s %s: %s"), *C.Mod, *C.Name, *Error); if (C.Done) C.Done(FString(), true); return true; }
			if (C.Done) C.Done(Chord, false);
			return true;
		}
		if (Event.IsRepeat()) return false;
		FOKModHost& Host = FOKModHost::Get();
		const FString Mode = Host.CurrentMode();
		if (!Host.IsOpen() || !GListeners.Contains(Mode) || GBound.IsEmpty()) return false;
		const FString Chord = ChordOf(Event);
		if (Chord.IsEmpty() || !GBound.Contains(Normalize(Chord))) return false;
		if (Typing(App) || App.GetPressedMouseButtons().Num()) return false;
		Send(Chord, Mode);
		return true;
	}

	virtual const TCHAR* GetDebugName() const override { return TEXT("OKModKeys"); }
};

TSharedPtr<FProcessor> GProcessor;

void Install()
{
	if (GProcessor.IsValid() || !FSlateApplication::IsInitialized()) return;
	GProcessor = MakeShared<FProcessor>();
	FSlateApplication::Get().RegisterInputPreProcessor(GProcessor);
	FCoreDelegates::OnEnginePreExit.AddLambda([]
	{
		if (GProcessor.IsValid() && FSlateApplication::IsInitialized()) FSlateApplication::Get().UnregisterInputPreProcessor(GProcessor);
		GProcessor.Reset();
		GListeners.Reset();
		GCapture.Reset();
	});
}

FAutoConsoleCommand GKeysCommand(TEXT("OKMod.Keys"), TEXT("Lists the mod hotkeys: mod, name, chord (OKModKeys.h)."),
	FConsoleCommandWithOutputDeviceDelegate::CreateLambda([](FOutputDevice& Out)
	{
		const TArray<FOKModKeys::FHotkey> Keys = FOKModKeys::List();
		if (Keys.IsEmpty()) Out.Log(TEXT("no mod hotkeys"));
		for (const FOKModKeys::FHotkey& K : Keys)
			Out.Logf(TEXT("%s %s = %s (default %s)"), *K.Mod, *K.Name, K.Chord.IsEmpty() ? TEXT("(none)") : *K.Chord, *K.Default);
	}));

FAutoConsoleCommand GBindCommand(TEXT("OKMod.Bind"),
	TEXT("OKMod.Bind <mod> <name> [chord]: binds a mod hotkey (Unreal key names joined by +, \"-\" unbinds); without a chord the next key pressed."),
	FConsoleCommandWithArgsAndOutputDeviceDelegate::CreateLambda([](const TArray<FString>& Args, FOutputDevice& Out)
	{
		if (Args.Num() < 2) { Out.Log(TEXT("OKMod.Bind <mod> <name> [chord]")); return; }
		if (Args.Num() == 2)
		{
			FOKModKeys::Capture(Args[0], Args[1], [Mod = Args[0], Name = Args[1]](const FString& Chord, bool bCancelled)
			{
				UE_LOG(LogOKMod, Display, TEXT("%s %s: %s"), *Mod, *Name, bCancelled ? TEXT("not changed") : (Chord.IsEmpty() ? TEXT("unbound") : *Chord));
			});
			Out.Log(TEXT("press the key (Escape cancels, Backspace unbinds)"));
			return;
		}
		const FString Chord = Args[2] == TEXT("-") ? FString() : Args[2];
		FString Error;
		Out.Log(FOKModKeys::Bind(Args[0], Args[1], Chord, Error) ? FString::Printf(TEXT("%s %s = %s"), *Args[0], *Args[1], Chord.IsEmpty() ? TEXT("(none)") : *Chord) : TEXT("error: ") + Error);
	}));
}

void FOKModKeys::Listen(const FString& Mode, FOnReply OnReply)
{
	GListeners.Add(Mode, MoveTemp(OnReply));
	GAskedAt = -1e9;
	Install();
}

void FOKModKeys::Stop(const FString& Mode)
{
	GListeners.Remove(Mode);
}

TArray<FOKModKeys::FHotkey> FOKModKeys::List()
{
	TArray<FHotkey> Out;
	if (!FOKModHost::Get().IsOpen()) return Out;
	FString Error;
	const TSharedPtr<FJsonObject> Answer = FOKModHost::Get().DispatchJson(Op(TEXT("hotkeys")), Error);
	const TArray<TSharedPtr<FJsonValue>>* Keys = nullptr;
	if (!Answer.IsValid() || !Answer->TryGetArrayField(TEXT("keys"), Keys)) return Out;
	for (const TSharedPtr<FJsonValue>& V : *Keys)
	{
		const TSharedPtr<FJsonObject> O = V->AsObject();
		if (!O.IsValid()) continue;
		FHotkey K;
		O->TryGetStringField(TEXT("mod"), K.Mod);
		O->TryGetStringField(TEXT("name"), K.Name);
		O->TryGetStringField(TEXT("chord"), K.Chord);
		O->TryGetStringField(TEXT("default"), K.Default);
		O->TryGetStringField(TEXT("description_id"), K.DescriptionId);
		Out.Add(MoveTemp(K));
	}
	return Out;
}

bool FOKModKeys::Bind(const FString& Mod, const FString& Name, const FString& Chord, FString& Error)
{
	TSharedRef<FJsonObject> R = Op(TEXT("config_set"));
	R->SetStringField(TEXT("mod"), Mod);
	R->SetStringField(TEXT("key"), Name);
	R->SetStringField(TEXT("value"), Chord);
	const TSharedPtr<FJsonObject> Answer = FOKModHost::Get().DispatchJson(R, Error);
	if (!Answer.IsValid()) return false;
	bool bOk = false;
	Answer->TryGetBoolField(TEXT("ok"), bOk);
	if (!bOk) { Error = Answer->GetStringField(TEXT("error")); return false; }
	GAskedAt = -1e9;
	UE_LOG(LogOKMod, Display, TEXT("[%s] hotkey %s bound to %s"), *Mod, *Name, Chord.IsEmpty() ? TEXT("(none)") : *Chord);
	return true;
}

void FOKModKeys::Capture(const FString& Mod, const FString& Name, TFunction<void(const FString&, bool)> Done)
{
	Install();
	if (GCapture.IsSet() && GCapture->Done) GCapture->Done(FString(), true);
	GCapture = FCapture{Mod, Name, MoveTemp(Done)};
}

bool FOKModKeys::IsCapturing() { return GCapture.IsSet(); }

FString FOKModKeys::ShownText(const TSharedPtr<FJsonObject>& Reply)
{
	if (!Reply.IsValid()) return FString();
	FString Text;
	if (Reply->TryGetStringField(TEXT("text"), Text)) return Text;
	const TSharedPtr<FJsonObject>* Json = nullptr;
	if (Reply->TryGetObjectField(TEXT("json"), Json) && Json->IsValid())
		if ((*Json)->TryGetStringField(TEXT("notice"), Text) || (*Json)->TryGetStringField(TEXT("status"), Text)) return Text;
	return FString();
}

FString FOKModKeys::Display(const FString& Chord)
{
	if (Chord.IsEmpty()) return TEXT("—");
	TArray<FString> Parts, Out;
	Chord.ParseIntoArray(Parts, TEXT("+"));
	for (FString P : Parts)
	{
		P.TrimStartAndEndInline();
		const FString L = P.ToLower();
		if (L.EndsWith(TEXT("control")) || L == TEXT("ctrl")) Out.Add(TEXT("Ctrl"));
		else if (L.EndsWith(TEXT("alt"))) Out.Add(TEXT("Alt"));
		else if (L.EndsWith(TEXT("shift"))) Out.Add(TEXT("Shift"));
		else if (L.EndsWith(TEXT("command")) || L == TEXT("cmd")) Out.Add(TEXT("Cmd"));
		else { const FKey Key{FName(*P)}; Out.Add(Key.IsValid() ? Key.GetDisplayName().ToString() : P); }
	}
	return FString::Join(Out, TEXT("+"));
}
