#include "OKInteractionMod.h"
#include "OKInteractionMode.h"
#include "OKCharacterController.h"

const TCHAR* OKPairModEventName(EOKPairModEvent Kind)
{
	switch (Kind)
	{
	case EOKPairModEvent::Enter: return TEXT("enter");
	case EOKPairModEvent::Ready: return TEXT("ready");
	case EOKPairModEvent::Exit: return TEXT("exit");
	case EOKPairModEvent::Note: return TEXT("note");
	case EOKPairModEvent::Finish: return TEXT("finish");
	case EOKPairModEvent::Voice: return TEXT("voice");
	case EOKPairModEvent::Line: return TEXT("line");
	}
	return TEXT("unknown");
}

FOKInteractionModEvents& FOKInteractionModEvents::Get()
{
	static FOKInteractionModEvents Events;
	return Events;
}

int32 FOKInteractionModEvents::Subscribe(const FString& Owner, TFunction<void(const FOKPairModEvent&)> Callback)
{
	if (!Callback) return 0;
	const int32 Id = NextId++;
	Subscribers.Add({ Id, Owner, MoveTemp(Callback) });
	return Id;
}

bool FOKInteractionModEvents::Unsubscribe(int32 Id)
{
	return Subscribers.RemoveAll([Id](const FSubscriber& S) { return S.Id == Id; }) > 0;
}

void FOKInteractionModEvents::RemoveOwner(const FString& Owner)
{
	Subscribers.RemoveAll([&Owner](const FSubscriber& S) { return S.Owner == Owner; });
}

void FOKInteractionModEvents::Broadcast(const FOKPairModEvent& Event) const
{
	if (Subscribers.IsEmpty()) return;
	// A copy: a callback may subscribe or leave.
	const TArray<FSubscriber> Now = Subscribers;
	for (const FSubscriber& S : Now) S.Callback(Event);
}

namespace
{
	FString ModeCard(const AOKInteractionMode* Mode)
	{
		FString Root, Card;
		if (Mode) Mode->OpenedSource(Root, Card);
		return Card;
	}
	FString GalleryCard(const UOKCharacterController* Gallery) { return Gallery ? Gallery->PreviewCardPath : FString(); }
}

void FOKInteractionModEvents::FireEnter(const AOKInteractionMode* Mode)
{
	if (!Get().HasSubscribers()) return;
	FOKPairModEvent E;
	E.Kind = EOKPairModEvent::Enter;
	E.Card = ModeCard(Mode);
	E.bFitting = Mode && Mode->bFitting;
	Get().Broadcast(E);
}

void FOKInteractionModEvents::FireReady(const AOKInteractionMode* Mode)
{
	if (!Get().HasSubscribers()) return;
	FOKPairModEvent E;
	E.Kind = EOKPairModEvent::Ready;
	E.Card = ModeCard(Mode);
	E.bFitting = Mode && Mode->bFitting;
	Get().Broadcast(E);
}

void FOKInteractionModEvents::FireExit(const AOKInteractionMode* Mode, bool bCancelled, double Seconds)
{
	if (!Get().HasSubscribers()) return;
	FOKPairModEvent E;
	E.Kind = EOKPairModEvent::Exit;
	E.Card = ModeCard(Mode);
	E.bFitting = Mode && Mode->bFitting;
	E.bCancelled = bCancelled;
	E.Seconds = Seconds;
	Get().Broadcast(E);
}

void FOKInteractionModEvents::FireNote(const UOKCharacterController* Gallery, const FString& Text, bool bReact)
{
	if (!Get().HasSubscribers()) return;
	FOKPairModEvent E;
	E.Kind = EOKPairModEvent::Note;
	E.Card = GalleryCard(Gallery);
	E.Text = Text;
	E.bReact = bReact;
	Get().Broadcast(E);
}

void FOKInteractionModEvents::FireFinish(const UOKCharacterController* Gallery, const TCHAR* Kind)
{
	if (!Get().HasSubscribers()) return;
	FOKPairModEvent E;
	E.Kind = EOKPairModEvent::Finish;
	E.Card = GalleryCard(Gallery);
	E.Text = Kind ? Kind : TEXT("");
	Get().Broadcast(E);
}

void FOKInteractionModEvents::FireVoice(const UOKCharacterController* Gallery, const TCHAR* Source, const FString& Path, const FString& Name, int32 Row)
{
	if (!Get().HasSubscribers()) return;
	FOKPairModEvent E;
	E.Kind = EOKPairModEvent::Voice;
	E.Card = GalleryCard(Gallery);
	E.Source = Source ? Source : TEXT("");
	E.Path = Path;
	E.Text = Name;
	E.Row = Row;
	Get().Broadcast(E);
}

void FOKInteractionModEvents::FireLine(const UOKCharacterController* Gallery, const FString& Text)
{
	if (!Get().HasSubscribers()) return;
	FOKPairModEvent E;
	E.Kind = EOKPairModEvent::Line;
	E.Card = GalleryCard(Gallery);
	E.Text = Text;
	Get().Broadcast(E);
}
