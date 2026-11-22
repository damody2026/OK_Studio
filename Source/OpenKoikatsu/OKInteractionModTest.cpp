// Tests of the one-on-one's event points (OKInteractionMod.h; OK_MOD_FRAMEWORK_PLAN work item 13, its first part).
//  - OpenKoikatsu.Interaction.ModEvents (automation): subscribing, the events' fields, leaving, an owner removed.
//  - ok.PairModEvents [on|off] (console, any mode): a C++ subscriber that writes every event to the log and to
//    Saved/OKInteraction/pair_mod_events.txt, to check a real one-on-one (enter, ready, notes, finish, voice, exit).
#include "OKInteractionMod.h"
#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKInteractionModEventsTest, "OpenKoikatsu.Interaction.ModEvents", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKInteractionModEventsTest::RunTest(const FString&)
{
	FOKInteractionModEvents& Events = FOKInteractionModEvents::Get();
	const FString Owner = TEXT("test.pairmod");
	Events.RemoveOwner(Owner);
	const bool bHadOthers = Events.HasSubscribers();
	TArray<FOKPairModEvent> Got;
	const int32 Id = Events.Subscribe(Owner, [&Got](const FOKPairModEvent& E) { Got.Add(E); });
	TestTrue(TEXT("subscribed"), Id > 0 && Events.HasSubscribers());
	TestEqual(TEXT("an empty callback is refused"), Events.Subscribe(Owner, nullptr), 0);

	// What the scene sends, in a one-on-one's order (no scene here: no mode or controller, so no card).
	FOKInteractionModEvents::FireEnter(nullptr);
	FOKInteractionModEvents::FireReady(nullptr);
	FOKInteractionModEvents::FireNote(nullptr, TEXT("初吻"), true);
	FOKInteractionModEvents::FireLine(nullptr, TEXT("她說的話"));
	FOKInteractionModEvents::FireVoice(nullptr, TEXT("hvoice"), TEXT("C:/h/voice.ogg"), TEXT("h_ko_00_300"), 301);
	FOKInteractionModEvents::FireFinish(nullptr, TEXT("org_in"));
	FOKInteractionModEvents::FireExit(nullptr, false, 12.5);
	const TArray<EOKPairModEvent> Order = { EOKPairModEvent::Enter, EOKPairModEvent::Ready, EOKPairModEvent::Note, EOKPairModEvent::Line, EOKPairModEvent::Voice, EOKPairModEvent::Finish, EOKPairModEvent::Exit };
	TestEqual(TEXT("every event arrives once"), Got.Num(), Order.Num());
	for (int32 I = 0; I < FMath::Min(Got.Num(), Order.Num()); ++I) TestTrue(FString::Printf(TEXT("event %d is %s"), I, OKPairModEventName(Order[I])), Got[I].Kind == Order[I]);
	if (Got.Num() == Order.Num())
	{
		TestTrue(TEXT("note text and react"), Got[2].Text == TEXT("初吻") && Got[2].bReact);
		TestEqual(TEXT("line text"), Got[3].Text, FString(TEXT("她說的話")));
		TestTrue(TEXT("voice fields"), Got[4].Source == TEXT("hvoice") && Got[4].Path == TEXT("C:/h/voice.ogg") && Got[4].Text == TEXT("h_ko_00_300") && Got[4].Row == 301);
		TestEqual(TEXT("finish kind"), Got[5].Text, FString(TEXT("org_in")));
		TestTrue(TEXT("exit not cancelled, seconds"), !Got[6].bCancelled && Got[6].Seconds == 12.5);
		TestTrue(TEXT("no card without a scene"), Got[0].Card.IsEmpty() && Got[2].Card.IsEmpty());
	}

	// A subscriber that leaves while being told: the others still hear this event, it hears no more.
	TArray<FString> Order2;
	int32 Leaver = 0;
	Leaver = Events.Subscribe(Owner, [&Order2, &Leaver, &Events](const FOKPairModEvent&) { Order2.Add(TEXT("leaver")); Events.Unsubscribe(Leaver); });
	Events.Subscribe(Owner, [&Order2](const FOKPairModEvent&) { Order2.Add(TEXT("after")); });
	Got.Reset();
	FOKInteractionModEvents::FireNote(nullptr, TEXT("a"), false);
	FOKInteractionModEvents::FireNote(nullptr, TEXT("b"), false);
	TestEqual(TEXT("leaving inside a callback: the rest still told, in order"), FString::Join(Order2, TEXT(",")), FString(TEXT("leaver,after,after")));
	TestEqual(TEXT("first subscriber heard both"), Got.Num(), 2);

	TestTrue(TEXT("unsubscribe"), Events.Unsubscribe(Id));
	TestFalse(TEXT("unsubscribe twice"), Events.Unsubscribe(Id));
	Events.RemoveOwner(Owner);
	Got.Reset();
	FOKInteractionModEvents::FireNote(nullptr, TEXT("c"), false);
	TestTrue(TEXT("removed owner hears nothing"), Got.IsEmpty() && Order2.Num() == 3);
	TestEqual(TEXT("no subscribers left (as before)"), Events.HasSubscribers(), bHadOthers);
	return true;
}
#endif

namespace
{
	int32 PairModLogId = 0;

	FString PairModEventText(const FOKPairModEvent& E)
	{
		FString S = FString::Printf(TEXT("%s %s"), *FDateTime::Now().ToString(TEXT("%H:%M:%S")), OKPairModEventName(E.Kind));
		if (!E.Card.IsEmpty()) S += TEXT(" card=") + FPaths::GetCleanFilename(E.Card);
		if (!E.Text.IsEmpty()) S += TEXT(" text=") + E.Text;
		if (!E.Source.IsEmpty()) S += TEXT(" source=") + E.Source;
		if (!E.Path.IsEmpty()) S += TEXT(" path=") + FPaths::GetCleanFilename(E.Path);
		if (E.Row >= 0) S += FString::Printf(TEXT(" row=%d"), E.Row);
		if (E.Kind == EOKPairModEvent::Note) S += E.bReact ? TEXT(" react") : TEXT(" quiet");
		if (E.Kind == EOKPairModEvent::Exit) S += FString::Printf(TEXT(" cancelled=%d seconds=%.1f"), E.bCancelled ? 1 : 0, E.Seconds);
		if (E.bFitting) S += TEXT(" fitting");
		return S;
	}

	FAutoConsoleCommand PairModEventsCommand(TEXT("ok.PairModEvents"),
		TEXT("ok.PairModEvents [on|off]: log the one-on-one's mod events (OKInteractionMod.h) to the log and Saved/OKInteraction/pair_mod_events.txt."),
		FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
		{
			const bool bOn = Args.IsEmpty() || Args[0] != TEXT("off");
			FOKInteractionModEvents::Get().RemoveOwner(TEXT("test.pairmodlog"));
			PairModLogId = 0;
			const FString File = FPaths::ProjectSavedDir() / TEXT("OKInteraction/pair_mod_events.txt");
			if (!bOn) { UE_LOG(LogTemp, Display, TEXT("Pair mod events: off")); return; }
			FFileHelper::SaveStringToFile(FString(), *File, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
			PairModLogId = FOKInteractionModEvents::Get().Subscribe(TEXT("test.pairmodlog"), [File](const FOKPairModEvent& E)
			{
				const FString Line = PairModEventText(E);
				UE_LOG(LogTemp, Display, TEXT("Pair mod event: %s"), *Line);
				FFileHelper::SaveStringToFile(Line + TEXT("\n"), *File, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM, &IFileManager::Get(), FILEWRITE_Append);
			});
			UE_LOG(LogTemp, Display, TEXT("Pair mod events: on (%s)"), *File);
		}));
}
