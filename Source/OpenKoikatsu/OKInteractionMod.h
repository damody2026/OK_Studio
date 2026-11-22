// What happens in the one-on-one (AOKInteractionMode) and its H scene (UOKHScenePanel), for what listens from outside:
// the mod host (Docs/OK_MOD_FRAMEWORK_PLAN.md §14.3 pair-counter, subtitles; work item 13), tests. The scene's own code
// only calls the Fire functions below, one line each where it happens; with no one subscribed they return at once.
// Game thread only. A subscriber reads; it never changes the scene from inside the callback.
#pragma once

#include "CoreMinimal.h"

class AOKInteractionMode;
class UOKCharacterController;

enum class EOKPairModEvent : uint8
{
	/** The one-on-one is opened (AOKInteractionMode::Enter): nothing loaded yet. */
	Enter,
	/** Both of them are loaded and playing (the "ready" of its evidence). */
	Ready,
	/** It ends (AOKInteractionMode::Exit): bCancelled, Seconds since Ready. */
	Exit,
	/** The H scene notes something that happened (UOKHScenePanel::Note): Text as shown, bReact whether she reacts. */
	Note,
	/** One of them comes (UOKHScenePanel::Finish): Text is the kind (e.g. "org_in", "same_out"). */
	Finish,
	/** Her voice plays: Source "hvoice" (the original's H line, Row of its table, Text its clip name) or "tts" (her spoken
	 *  line), Path the sound file. */
	Voice,
	/** Her line is shown as text (the H scene's talk, UOKHScenePanel::ShowLine through the street): Text. */
	Line,
};

struct FOKPairModEvent
{
	EOKPairModEvent Kind = EOKPairModEvent::Note;
	/** Her card (the one-on-one's female; empty when not known yet). */
	FString Card;
	FString Text;
	FString Path;
	FString Source;
	int32 Row = -1;
	bool bReact = false;
	bool bCancelled = false;
	/** The street's fitting room (she alone, trying clothes on), not a one-on-one with him. */
	bool bFitting = false;
	double Seconds = 0.0;
};

/** Event name for logs and the mod host: "enter", "ready", "exit", "note", "finish", "voice", "line". */
OPENKOIKATSU_API const TCHAR* OKPairModEventName(EOKPairModEvent Kind);

class OPENKOIKATSU_API FOKInteractionModEvents
{
public:
	static FOKInteractionModEvents& Get();

	/** Owner: who subscribes (a mod id, a test name); RemoveOwner drops all of its subscriptions. Returns an id for Unsubscribe. */
	int32 Subscribe(const FString& Owner, TFunction<void(const FOKPairModEvent&)> Callback);
	bool Unsubscribe(int32 Id);
	void RemoveOwner(const FString& Owner);
	bool HasSubscribers() const { return !Subscribers.IsEmpty(); }
	/** Sends to every subscriber in the order they subscribed. One subscribing or leaving meanwhile takes effect next time. */
	void Broadcast(const FOKPairModEvent& Event) const;

	// The scene's one-line calls.
	static void FireEnter(const AOKInteractionMode* Mode);
	static void FireReady(const AOKInteractionMode* Mode);
	static void FireExit(const AOKInteractionMode* Mode, bool bCancelled, double Seconds);
	static void FireNote(const UOKCharacterController* Gallery, const FString& Text, bool bReact);
	static void FireFinish(const UOKCharacterController* Gallery, const TCHAR* Kind);
	static void FireVoice(const UOKCharacterController* Gallery, const TCHAR* Source, const FString& Path, const FString& Name, int32 Row);
	static void FireLine(const UOKCharacterController* Gallery, const FString& Text);

private:
	struct FSubscriber { int32 Id = 0; FString Owner; TFunction<void(const FOKPairModEvent&)> Callback; };
	TArray<FSubscriber> Subscribers;
	int32 NextId = 1;
};
