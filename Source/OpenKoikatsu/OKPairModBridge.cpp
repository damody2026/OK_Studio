// The one-on-one's events (OKInteractionMod.h) to the mod host as hooks (work item 13 of Docs/OK_MOD_FRAMEWORK_PLAN.md):
// pair.enter, pair.ready, pair.exit, pair.note, pair.finish, pair.voice, pair.line, sent as {"op":"hook","hook",
// "payload"} to every mod subscribed to the name (Event::Hook of ok-mod-api). The payload is the event as JSON:
// {"pair": 1, "event", "card", "text", "path", "source", "row", "react", "cancelled", "fitting", "seconds"}.
//
// Her card's mod data: pair.enter and pair.exit go to one mod at a time with that mod's own okMx section of the card
// ("section": {"version", "data_b64"}, as reader.character_load hands it). A reply {"version", "data_b64"} (ok-mod-sdk
// hooks::save) writes the mod's section back into the card file, {"remove": true} removes it (FOkSession::
// SetCardModSection: every other section and the card's identity stay). Other replies are kept for ok.PairModTrace.
#include "OKInteractionMod.h"
#include "OKModHost.h"
#include "KKRustExtract.h"
#include "Misc/Base64.h"
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
		/** The mode the host was in before a one-on-one inside another mode's world (reader, street) switched it to "pair". */
		FString ModeBefore;
		bool bEnteredPair = false;
		/** A stand-in for the host's dispatch (ok.PairModBridgeSelfTest). */
		TFunction<TSharedPtr<FJsonObject>(const TSharedRef<FJsonObject>&)> FakeDispatch;
		TArray<FString> Trace;
		/** Per mod, the hooks the host said it did not subscribe to (not asked again while the host stays open). */
		TMap<FString, TSet<FString>> NotSubscribed;
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

	void Note(const FString& Line)
	{
		TArray<FString>& T = State().Trace;
		T.Add(Line);
		if (T.Num() > 200) T.RemoveAt(0, T.Num() - 200);
	}

	TSharedPtr<FJsonObject> Dispatch(const TSharedRef<FJsonObject>& Request, FString& Error)
	{
		FState& S = State();
		return S.FakeDispatch ? S.FakeDispatch(Request) : FOKModHost::Get().DispatchJson(Request, Error);
	}

	/** A mod's reply: write or remove its section of the card. */
	void ApplyReply(const FString& Mod, const FJsonObject& Reply, const FString& Card)
	{
		const TSharedPtr<FJsonObject>* Json = nullptr;
		if (!Reply.TryGetObjectField(TEXT("json"), Json) || !Json || !Json->IsValid() || Card.IsEmpty()) return;
		bool bRemove = false;
		FString Base64;
		int32 Version = 1;
		(*Json)->TryGetBoolField(TEXT("remove"), bRemove);
		const bool bSave = (*Json)->TryGetStringField(TEXT("data_b64"), Base64);
		if (!bRemove && !bSave) return;
		(*Json)->TryGetNumberField(TEXT("version"), Version);
		TArray<uint8> Bytes;
		if (bSave && !FBase64::Decode(Base64, Bytes)) { UE_LOG(LogOKPairMods, Warning, TEXT("%s: data_b64 is not base64"), *Mod); return; }
		FString Error;
		if (!FOkSession::SetCardModSection(Card, Mod, Version, Bytes, bRemove, Error))
		{
			UE_LOG(LogOKPairMods, Warning, TEXT("%s: card data of %s: %s"), *Mod, *Card, *Error);
		}
		else
		{
			UE_LOG(LogOKPairMods, Display, TEXT("%s: %s its card data in %s (%d bytes, version %d)"), *Mod, bRemove ? TEXT("removed") : TEXT("wrote"), *Card, Bytes.Num(), Version);
		}
	}

	/** Sends the request and handles each reply; the mods that did not subscribe are remembered. */
	void SendRequest(const FString& Hook, const TSharedRef<FJsonObject>& Request, const FString& Card)
	{
		FString Error;
		const TSharedPtr<FJsonObject> Answer = Dispatch(Request, Error);
		Note(FString::Printf(TEXT("%s %s -> %s"), *Hook, *Condensed(Request).Left(300), Answer.IsValid() ? *Condensed(Answer.ToSharedRef()).Left(300) : *Error));
		const TArray<TSharedPtr<FJsonValue>>* Replies = nullptr;
		if (!Answer.IsValid() || !Answer->TryGetArrayField(TEXT("replies"), Replies)) return;
		for (const TSharedPtr<FJsonValue>& V : *Replies)
		{
			const TSharedPtr<FJsonObject> R = V->AsObject();
			FString Mod, Why;
			if (!R || !R->TryGetStringField(TEXT("mod"), Mod)) continue;
			if (R->TryGetStringField(TEXT("error"), Why))
			{
				if (Why.Contains(TEXT("did not subscribe"))) State().NotSubscribed.FindOrAdd(Mod).Add(Hook);
				else UE_LOG(LogOKPairMods, Warning, TEXT("%s %s: %s"), *Mod, *Hook, *Why);
				continue;
			}
			ApplyReply(Mod, *R, Card);
		}
	}

	TArray<FString> EnabledMods()
	{
		TArray<FString> Out;
		const TSharedPtr<FJsonObject> List = FOKModHost::Get().List();
		const TArray<TSharedPtr<FJsonValue>>* Mods = nullptr;
		if (!List.IsValid() || !List->TryGetArrayField(TEXT("mods"), Mods)) return Out;
		for (const TSharedPtr<FJsonValue>& V : *Mods)
		{
			const TSharedPtr<FJsonObject> M = V->AsObject();
			FString Id, StateName;
			if (M && M->TryGetStringField(TEXT("id"), Id) && M->TryGetStringField(TEXT("state"), StateName) && StateName == TEXT("enabled")) Out.Add(Id);
		}
		return Out;
	}

	void Send(const FOKPairModEvent& E)
	{
		FState& S = State();
		const FString Hook = FString(TEXT("pair.")) + OKPairModEventName(E.Kind);
		const FString Card = !E.Card.IsEmpty() && FPaths::FileExists(E.Card) ? E.Card : FString();
		auto MakeRequest = [&](const TSharedRef<FJsonObject>& Payload_)
		{
			TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
			Request->SetStringField(TEXT("op"), TEXT("hook"));
			Request->SetStringField(TEXT("hook"), Hook);
			Request->SetObjectField(TEXT("payload"), Payload_);
			return Request;
		};
		// Entering and leaving: each mod with its own section of her card (only its own: one request per mod).
		if (!Card.IsEmpty() && !S.FakeDispatch && (E.Kind == EOKPairModEvent::Enter || E.Kind == EOKPairModEvent::Exit))
		{
			for (const FString& Mod : EnabledMods())
			{
				if (const TSet<FString>* Skip = S.NotSubscribed.Find(Mod); Skip && Skip->Contains(Hook)) continue;
				TSharedRef<FJsonObject> P = Payload(E);
				bool bFound = false;
				int32 Version = 0;
				TArray<uint8> Bytes;
				FString Error;
				if (!FOkSession::CardModSection(Card, Mod, bFound, Version, Bytes, Error)) UE_LOG(LogOKPairMods, Warning, TEXT("%s: card data of %s: %s"), *Mod, *Card, *Error);
				if (bFound)
				{
					TSharedRef<FJsonObject> Section = MakeShared<FJsonObject>();
					Section->SetNumberField(TEXT("version"), Version);
					Section->SetStringField(TEXT("data_b64"), FBase64::Encode(Bytes));
					P->SetObjectField(TEXT("section"), Section);
				}
				TSharedRef<FJsonObject> Request = MakeRequest(P);
				Request->SetArrayField(TEXT("mods"), { MakeShared<FJsonValueString>(Mod) });
				SendRequest(Hook, Request, Card);
			}
			return;
		}
		SendRequest(Hook, MakeRequest(Payload(E)), Card);
	}

	/** One event: a one-on-one opened inside the reader's or the street's world switches the host to "pair" first (its
	 *  mods load and get mode_enter, OKModHost.h) and back after the exit was sent; one in its own world (the pair game
	 *  mode, OKModModes.cpp) is "pair" already. The street's fitting room is not a one-on-one. */
	void OnEvent(const FOKPairModEvent& E)
	{
		FState& S = State();
		FOKModHost& Host = FOKModHost::Get();
		if (E.Kind == EOKPairModEvent::Enter && !E.bFitting && !S.FakeDispatch && Host.IsOpen() && Host.CurrentMode() != TEXT("pair"))
		{
			S.ModeBefore = Host.CurrentMode();
			S.bEnteredPair = true;
			Host.EnterMode(TEXT("pair"));
		}
		Send(E);
		if (E.Kind == EOKPairModEvent::Exit && S.bEnteredPair)
		{
			S.bEnteredPair = false;
			Host.ExitMode(TEXT("pair"));
			if (!S.ModeBefore.IsEmpty()) Host.EnterMode(S.ModeBefore);
		}
	}

	/** Subscribed to the one-on-one's events while the host is open (or a fake stands in). */
	bool Tick(float)
	{
		FState& S = State();
		const bool bWant = S.FakeDispatch || FOKModHost::Get().IsOpen();
		if (!bWant) S.NotSubscribed.Reset();
		if (bWant && !S.Subscription) S.Subscription = FOKInteractionModEvents::Get().Subscribe(TEXT("mod-host"), [](const FOKPairModEvent& E) { OnEvent(E); });
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
