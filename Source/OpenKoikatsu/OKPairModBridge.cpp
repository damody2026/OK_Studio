// The one-on-one's events (OKInteractionMod.h) to the mod host as hooks (work item 13 of Docs/OK_MOD_FRAMEWORK_PLAN.md):
// pair.enter, pair.ready, pair.exit, pair.note, pair.finish, pair.voice, pair.line, sent as {"op":"hook","hook",
// "payload"} to every mod subscribed to the name (Event::Hook of ok-mod-api). The payload is the event as JSON:
// {"pair": 1, "event", "card", "text", "path", "source", "row", "react", "cancelled", "fitting", "seconds"}.
//
// Skeleton: the mods' replies are only kept for OK.PairModTrace; what a reply may do in the one-on-one (a subtitle, a
// counter shown on screen) is decided with the examples (pair-counter, subtitles) once Event::Hook is in E.
#include "OKInteractionMod.h"
#include "OKModHost.h"
#include "Containers/Ticker.h"
#include "Dom/JsonObject.h"
#include "HAL/IConsoleManager.h"
#include "Misc/App.h"
#include "Misc/DelayedAutoRegister.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

DEFINE_LOG_CATEGORY_STATIC(LogOKPairMods, Log, All);

namespace OKPairModBridge
{
	struct FState
	{
		int32 Subscription = 0;
		/** A stand-in for the host's dispatch (ok.PairModBridgeSelfTest). */
		TFunction<TSharedPtr<FJsonObject>(const TSharedRef<FJsonObject>&)> FakeDispatch;
		TArray<FString> Trace;
	};

	FState& State()
	{
		static FState S;
		return S;
	}

	FString Condensed(const TSharedRef<FJsonObject>& Object)
	{
		FString Out;
		FJsonSerializer::Serialize(Object, TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out));
		return Out;
	}

	TSharedRef<FJsonObject> Payload(const FOKPairModEvent& E)
	{
		TSharedRef<FJsonObject> P = MakeShared<FJsonObject>();
		P->SetNumberField(TEXT("pair"), 1);
		P->SetStringField(TEXT("event"), OKPairModEventName(E.Kind));
		P->SetStringField(TEXT("card"), E.Card);
		if (!E.Text.IsEmpty()) P->SetStringField(TEXT("text"), E.Text);
		if (!E.Path.IsEmpty()) P->SetStringField(TEXT("path"), E.Path);
		if (!E.Source.IsEmpty()) P->SetStringField(TEXT("source"), E.Source);
		if (E.Row >= 0) P->SetNumberField(TEXT("row"), E.Row);
		if (E.Kind == EOKPairModEvent::Note) P->SetBoolField(TEXT("react"), E.bReact);
		if (E.Kind == EOKPairModEvent::Exit) { P->SetBoolField(TEXT("cancelled"), E.bCancelled); P->SetNumberField(TEXT("seconds"), E.Seconds); }
		P->SetBoolField(TEXT("fitting"), E.bFitting);
		return P;
	}

	void Send(const FOKPairModEvent& E)
	{
		FState& S = State();
		TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
		const FString Hook = FString(TEXT("pair.")) + OKPairModEventName(E.Kind);
		Request->SetStringField(TEXT("op"), TEXT("hook"));
		Request->SetStringField(TEXT("hook"), Hook);
		Request->SetObjectField(TEXT("payload"), Payload(E));
		FString Error;
		const TSharedPtr<FJsonObject> Answer = S.FakeDispatch ? S.FakeDispatch(Request) : FOKModHost::Get().DispatchJson(Request, Error);
		const FString Line = FString::Printf(TEXT("%s %s -> %s"), *Hook, *Condensed(Request).Left(300), Answer.IsValid() ? *Condensed(Answer.ToSharedRef()).Left(300) : *Error);
		S.Trace.Add(Line);
		if (S.Trace.Num() > 200) S.Trace.RemoveAt(0, S.Trace.Num() - 200);
		bool bOk = false;
		if (!Answer.IsValid() || !Answer->TryGetBoolField(TEXT("ok"), bOk) || !bOk) UE_LOG(LogOKPairMods, Verbose, TEXT("%s"), *Line);
	}

	/** Subscribed to the one-on-one's events while the host is open (or a fake stands in). */
	bool Tick(float)
	{
		FState& S = State();
		const bool bWant = S.FakeDispatch || FOKModHost::Get().IsOpen();
		if (bWant && !S.Subscription) S.Subscription = FOKInteractionModEvents::Get().Subscribe(TEXT("mod-host"), [](const FOKPairModEvent& E) { Send(E); });
		else if (!bWant && S.Subscription) { FOKInteractionModEvents::Get().Unsubscribe(S.Subscription); S.Subscription = 0; }
		return true;
	}

	FDelayedAutoRegisterHelper Start(EDelayedRegisterRunPhase::EndOfEngineInit, []
	{
		if (!FApp::IsGame() || IsRunningCommandlet()) return;
		FTSTicker::GetCoreTicker().AddTicker(TEXT("OKPairMods"), 0.5f, [](float Delta) { return Tick(Delta); });
	});

	FAutoConsoleCommand TraceCommand(TEXT("ok.PairModTrace"), TEXT("Logs the last one-on-one hooks sent to the mods and their answers."),
		FConsoleCommandDelegate::CreateLambda([]
		{
			UE_LOG(LogOKPairMods, Display, TEXT("pair hooks: %s"), State().Subscription ? TEXT("subscribed") : TEXT("not subscribed (host closed)"));
			for (const FString& Line : State().Trace) UE_LOG(LogOKPairMods, Display, TEXT("%s"), *Line);
		}));

	/** Every event kind through a fake host: the hook names and payload fields (Saved/OKInteraction/pair_mod_bridge_selftest.txt). */
	FAutoConsoleCommand SelfTest(TEXT("ok.PairModBridgeSelfTest"), TEXT("Sends each one-on-one event through the pair hook bridge to a fake host."),
		FConsoleCommandDelegate::CreateLambda([]
		{
			FState& S = State();
			TArray<TSharedRef<FJsonObject>> Seen;
			S.FakeDispatch = [&Seen](const TSharedRef<FJsonObject>& Request)
			{
				Seen.Add(Request);
				TSharedRef<FJsonObject> Out = MakeShared<FJsonObject>();
				Out->SetBoolField(TEXT("ok"), true);
				Out->SetArrayField(TEXT("replies"), {});
				return TSharedPtr<FJsonObject>(Out);
			};
			Tick(0.f);
			const int32 Kinds = int32(EOKPairModEvent::Line) + 1;
			for (int32 K = 0; K < Kinds; ++K)
			{
				FOKPairModEvent E;
				E.Kind = EOKPairModEvent(K);
				E.Card = TEXT("selftest.png");
				E.Text = TEXT("text");
				E.Source = E.Kind == EOKPairModEvent::Voice ? TEXT("hvoice") : TEXT("");
				E.Path = E.Kind == EOKPairModEvent::Voice ? TEXT("voice.ogg") : TEXT("");
				E.Row = E.Kind == EOKPairModEvent::Voice ? 3 : -1;
				E.bCancelled = true;
				E.Seconds = 12.5;
				FOKInteractionModEvents::Get().Broadcast(E);
			}
			S.FakeDispatch = nullptr;
			Tick(0.f);
			TArray<FString> Lines;
			int32 Failed = 0;
			auto Check = [&](bool bOk, const FString& What) { Lines.Add(FString::Printf(TEXT("%s %s"), bOk ? TEXT("PASS") : TEXT("FAIL"), *What)); Failed += !bOk; };
			Check(Seen.Num() == Kinds, FString::Printf(TEXT("%d hooks sent for %d kinds"), Seen.Num(), Kinds));
			for (int32 K = 0; K < Seen.Num() && K < Kinds; ++K)
			{
				const FString Want = FString(TEXT("pair.")) + OKPairModEventName(EOKPairModEvent(K));
				FString Op, Hook;
				Seen[K]->TryGetStringField(TEXT("op"), Op);
				Seen[K]->TryGetStringField(TEXT("hook"), Hook);
				const TSharedPtr<FJsonObject>* PayloadObject = nullptr;
				Seen[K]->TryGetObjectField(TEXT("payload"), PayloadObject);
				const TSharedPtr<FJsonObject> P = PayloadObject ? *PayloadObject : nullptr;
				const FString PayloadText = P.IsValid() ? Condensed(P.ToSharedRef()) : FString(TEXT("<no payload object>"));
				Check(Op == TEXT("hook") && Hook == Want, FString::Printf(TEXT("%s (%s)"), *Want, *PayloadText));
				FString Card;
				Check(P.IsValid() && P->TryGetStringField(TEXT("card"), Card) && Card == TEXT("selftest.png"), Want + TEXT(" payload carries the card"));
				if (EOKPairModEvent(K) == EOKPairModEvent::Voice)
				{
					double Row = -1;
					FString Path;
					Check(P.IsValid() && P->TryGetNumberField(TEXT("row"), Row) && Row == 3 && P->TryGetStringField(TEXT("path"), Path) && Path == TEXT("voice.ogg"), TEXT("pair.voice carries row and path"));
				}
				if (EOKPairModEvent(K) == EOKPairModEvent::Exit)
				{
					bool bCancelled = false;
					Check(P.IsValid() && P->TryGetBoolField(TEXT("cancelled"), bCancelled) && bCancelled, TEXT("pair.exit carries cancelled"));
				}
			}
			Lines.Insert(FString::Printf(TEXT("ok.PairModBridgeSelfTest: %d failed of %d"), Failed, Lines.Num()), 0);
			const FString Out = FPaths::ProjectSavedDir() / TEXT("OKInteraction/pair_mod_bridge_selftest.txt");
			FFileHelper::SaveStringToFile(FString::Join(Lines, TEXT("\n")) + TEXT("\n"), *Out, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
			for (const FString& L : Lines) UE_LOG(LogOKPairMods, Display, TEXT("PairModBridgeSelfTest %s"), *L);
		}));
}
