#include "SOKStudioTimeline.h"
#include "OKSceneActor.h"
#include "OKStudioCatalog.h"
#include "OKStudioStyle.h"
#include "Fonts/FontMeasure.h"
#include "Framework/Application/SlateApplication.h"
#include "Rendering/DrawElements.h"

void SOKStudioTimeline::Construct(const FArguments& Args)
{
	Game = Args._Game;
	OnEaseMenu = Args._OnEaseMenu;
	OnStatus = Args._OnStatus;
}

TArray<SOKStudioTimeline::FRowInfo> SOKStudioTimeline::RowInfos() const
{
	TArray<FRowInfo> Rows;
	if (!Game.IsValid()) return Rows;
	const UOKSceneDocument* Doc = Game->Document;
	static const TCHAR* Subs[] = { TEXT("變換"), TEXT("FK"), TEXT("狀態"), TEXT("數值"), TEXT("動作"), TEXT("語音") };
	auto AddRows = [&](int32 Track)
	{
		const FOKSceneObject* O = Doc->Find(Track);
		FRowInfo R;
		R.Track = Track;
		R.Label = Track == UOKSceneDocument::SceneTrackId ? FString(TEXT("場景（畫面）")) : (O ? O->Name : FString::Printf(TEXT("#%d"), Track));
		Rows.Add(R);
		if (!Open.Contains(Track) || Track == UOKSceneDocument::SceneTrackId) return;
		for (int32 S = 0; S < 6; ++S)
		{
			if ((S == 1 || S == 2 || S == 4 || S == 5) && (!O || O->Kind != EOKSceneObjectKind::Character)) continue;
			if (S == 3 && (!O || (O->Kind != EOKSceneObjectKind::Light && O->Kind != EOKSceneObjectKind::Camera && O->Kind != EOKSceneObjectKind::Effect))) continue;
			FRowInfo Sub;
			Sub.Track = Track;
			Sub.Sub = S;
			Sub.Label = FString(TEXT("    ")) + Subs[S];
			Rows.Add(Sub);
		}
	};
	for (const FOKSceneTrack& T : Doc->Tracks) AddRows(T.ObjectId);
	// A character with voices but no keys has no track.
	for (const FOKSceneObject& O : Doc->Objects)
		if (!O.Character.VoiceClips.IsEmpty() && !Doc->TrackOf(O.Id)) AddRows(O.Id);
	return Rows;
}

bool SOKStudioTimeline::SubHasKey(int32 Sub, const FOKSceneKey& K, const FOKSceneObject* O) const
{
	switch (Sub)
	{
	case 1: return K.Fk.Num() > 0;
	case 2: return K.bCharacterState || K.AnimTime >= 0.f;
	case 3: return O && (O->Kind == EOKSceneObjectKind::Light || O->Kind == EOKSceneObjectKind::Camera || O->Kind == EOKSceneObjectKind::Effect);
	case 4: return K.AnimNo >= 0;
	default: return true;
	}
}

float SOKStudioTimeline::TimeToX(const FGeometry& G, float Time) const
{
	const float Width = FMath::Max(10.f, float(G.GetLocalSize().X) - LabelWidth - 6.f);
	const float Duration = Game.IsValid() ? FMath::Max(Game->Document->Duration, 0.1f) : 10.f;
	return LabelWidth + 3.f + (Time - Scroll) / Duration * Width * Zoom;
}

float SOKStudioTimeline::XToTime(const FGeometry& G, float X) const
{
	const float Width = FMath::Max(10.f, float(G.GetLocalSize().X) - LabelWidth - 6.f);
	const float Duration = Game.IsValid() ? FMath::Max(Game->Document->Duration, 0.1f) : 10.f;
	return FMath::Clamp(Scroll + (X - LabelWidth - 3.f) / (Width * Zoom) * Duration, 0.f, Duration);
}

int32 SOKStudioTimeline::OnPaint(const FPaintArgs&, const FGeometry& G, const FSlateRect&, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle&, bool) const
{
	using namespace OKStudioStyle;
	const FVector2D Size = G.GetLocalSize();
	auto Box = [&](float X, float Y, float W, float H, const FLinearColor& C, int32 L)
	{
		FSlateDrawElement::MakeBox(Out, L, G.ToPaintGeometry(FVector2f(W, H), FSlateLayoutTransform(FVector2f(X, Y))), Brush(C), ESlateDrawEffect::None, C);
	};
	auto Text = [&](float X, float Y, const FString& S, const FLinearColor& C, float Px, int32 L)
	{
		FSlateDrawElement::MakeText(Out, L, G.ToPaintGeometry(FVector2f(400.f, 20.f), FSlateLayoutTransform(FVector2f(X, Y))), S, Font(Px), ESlateDrawEffect::None, C);
	};
	Box(0.f, 0.f, Size.X, Size.Y, ListArea(), Layer);
	if (!Game.IsValid()) return Layer + 1;
	const UOKSceneDocument* Doc = Game->Document;
	const float Duration = FMath::Max(Doc->Duration, 0.1f);
	// Loop range.
	if (Game->LoopEnd > Game->LoopStart)
	{
		const float X0 = TimeToX(G, Game->LoopStart), X1 = TimeToX(G, Game->LoopEnd);
		Box(X0, 0.f, FMath::Max(1.f, X1 - X0), Size.Y, FLinearColor(0.35f, 0.6f, 1.f, 0.12f), Layer + 1);
	}
	// Ruler: a tick every second (every 5 when crowded), labels.
	Box(0.f, 0.f, Size.X, RulerHeight, Panel(), Layer + 1);
	const float PixelsPerSecond = TimeToX(G, 1.f) - TimeToX(G, 0.f);
	const int32 Every = PixelsPerSecond > 40.f ? 1 : (PixelsPerSecond > 12.f ? 5 : 10);
	for (int32 S = 0; S <= FMath::CeilToInt(Duration); S += Every)
	{
		const float X = TimeToX(G, float(S));
		if (X < LabelWidth || X > Size.X) continue;
		FSlateDrawElement::MakeLines(Out, Layer + 2, G.ToPaintGeometry(), { FVector2f(X, RulerHeight - 6.f), FVector2f(X, Size.Y) }, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.12f));
		if (X < Size.X - 14.f) Text(X + 2.f, 1.f, FString::Printf(TEXT("%d"), S), TextHint(), 9.f, Layer + 2);
	}
	// Rows.
	const TArray<FRowInfo> Rows = RowInfos();
	for (int32 I = RowScroll; I < Rows.Num(); ++I)
	{
		const float Y = RulerHeight + (I - RowScroll) * RowHeight;
		if (Y > Size.Y) break;
		const FRowInfo& R = Rows[I];
		const bool bSelectedObject = Game->IsSelected(R.Track);
		if (bSelectedObject) Box(0.f, Y, LabelWidth, RowHeight, FLinearColor(RowFill().R, RowFill().G, RowFill().B, 0.6f), Layer + 1);
		const FString Arrow = R.Sub < 0 && R.Track != UOKSceneDocument::SceneTrackId ? (Open.Contains(R.Track) ? TEXT("▼ ") : TEXT("▶ ")) : TEXT("  ");
		Text(3.f, Y + 1.f, Arrow + R.Label, R.Sub < 0 ? OKStudioStyle::Text() : TextSoft(), 10.f, Layer + 2);
		FSlateDrawElement::MakeLines(Out, Layer + 1, G.ToPaintGeometry(), { FVector2f(0.f, Y + RowHeight), FVector2f(Size.X, Y + RowHeight) }, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.06f));
		const FOKSceneTrack* T = Doc->TrackOf(R.Track);
		const FOKSceneObject* O = Doc->Find(R.Track);
		// Voice clips (U233): bars of their length, thin on the character's own row.
		if (O && (R.Sub < 0 || R.Sub == 5))
			for (int32 V = 0; V < O->Character.VoiceClips.Num(); ++V)
			{
				const FOKSceneVoiceClip& Voice = O->Character.VoiceClips[V];
				const bool bPicked = R.Track == VoiceTrack && V == VoiceIndex;
				const float Start = Voice.Start + (bPicked && Drag == EDrag::Voice ? XToTime(G, DragNow.X) - DragTimeFrom : 0.f);
				const float X0 = FMath::Max(TimeToX(G, Start), LabelWidth), X1 = FMath::Min(TimeToX(G, Start + Game->VoiceClipSeconds(Voice)), float(Size.X));
				if (X1 <= X0) continue;
				const FLinearColor C = bPicked ? FLinearColor(1.f, .85f, .3f, .9f) : FLinearColor(.3f, .55f, 1.f, .75f);
				if (R.Sub < 0) { Box(X0, Y + RowHeight - 3.f, X1 - X0, 2.f, C, Layer + 2); continue; }
				Box(X0, Y + 2.f, X1 - X0, RowHeight - 4.f, C, Layer + 2);
				if (X1 - X0 >= 14.f) Text(X0 + 2.f, Y + 1.f, Game->VoiceClipName(Voice).Left(FMath::Max(int32((X1 - X0) / 7.f), 1)), FLinearColor::White, 9.f, Layer + 3);
			}
		if (!T) continue;
		for (const FOKSceneKey& K : T->Keys)
		{
			if (R.Sub >= 0 && !SubHasKey(R.Sub, K, O)) continue;
			const float X = TimeToX(G, K.Time);
			if (X < LabelWidth || X > Size.X) continue;
			// A motion that fades in (U236): the fade's length after its key.
			if (K.AnimBlend > 0.f && R.Sub == 4) Box(X, Y + 3.f, FMath::Min(TimeToX(G, K.Time + K.AnimBlend), float(Size.X)) - X, RowHeight - 6.f, FLinearColor(.45f, .9f, .5f, .35f), Layer + 2);
			const bool bSel = Selected.Contains(FKeyRef{ R.Track, K.Time });
			const FLinearColor C = bSel ? FLinearColor::Yellow : (K.Ease == EOKSceneEase::Step ? FLinearColor(1.f, .55f, .2f) : FLinearColor(.75f, .85f, 1.f));
			const float H = R.Sub < 0 ? 5.f : 3.5f, CY = Y + RowHeight * 0.5f;
			FSlateDrawElement::MakeLines(Out, Layer + 3, G.ToPaintGeometry(), { FVector2f(X, CY - H), FVector2f(X + H, CY), FVector2f(X, CY + H), FVector2f(X - H, CY), FVector2f(X, CY - H) }, ESlateDrawEffect::None, C, true, 2.f);
			// Only as many characters as fit before the next key (about 6 px each at this size).
			const FOKSceneKey* NextKey = T->Keys.FindByPredicate([&K](const FOKSceneKey& N) { return N.Time > K.Time; });
			const float Room = (NextKey ? FMath::Min(TimeToX(G, NextKey->Time) - H, Size.X) : Size.X) - (X + H + 2.f);
			// Scene keys name the view they cut to.
			if (R.Track == UOKSceneDocument::SceneTrackId && K.Camera >= -1)
			{
				const FOKSceneObject* Cam = Doc->Find(K.Camera);
				const FString Name = K.Camera < 0 ? FString(TEXT("自由")) : (Cam ? Cam->Name : FString(TEXT("（已刪）")));
				if (Room >= 12.f) Text(X + H + 2.f, Y + 1.f, Name.Left(FMath::Max(int32(Room / 6.f), 1)), TextHint(), 9.f, Layer + 3);
			}
			// A character's keys name the motion where it changes (U230), in its own colour.
			if (K.AnimNo >= 0 && (R.Sub < 0 || R.Sub == 4) && Room >= 12.f)
			{
				const FOKSceneKey* Before = nullptr;
				for (const FOKSceneKey& P : T->Keys) if (P.Time < K.Time && P.AnimNo >= 0) Before = &P;
				const FOKStudioAnim* Anim = FOKStudioCatalog::Get().FindAnim(K.AnimKind, K.AnimGroup, K.AnimCategory, K.AnimNo);
				if (Anim && (!Before || !Before->SameMotion(K)))
					Text(X + H + 2.f, Y + 1.f, FOKStudioCatalog::ZhName(Anim->Name).Left(FMath::Max(int32(Room / 6.f), 1)), FLinearColor(.55f, .95f, .6f), 9.f, Layer + 3);
			}
		}
	}
	FSlateDrawElement::MakeLines(Out, Layer + 2, G.ToPaintGeometry(), { FVector2f(LabelWidth, 0.f), FVector2f(LabelWidth, Size.Y) }, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.2f));
	// Play head.
	const float PX = TimeToX(G, Game->TimelineTime);
	if (Size.Y > 0.f) FSlateDrawElement::MakeLines(Out, Layer + 4, G.ToPaintGeometry(), { FVector2f(PX, 0.f), FVector2f(PX, Size.Y) }, ESlateDrawEffect::None, FLinearColor(1.f, .3f, .3f), true, 1.5f);
	if (Drag == EDrag::Box)
	{
		const FVector2D A(FMath::Min(DragFrom.X, DragNow.X), FMath::Min(DragFrom.Y, DragNow.Y)), B(FMath::Max(DragFrom.X, DragNow.X), FMath::Max(DragFrom.Y, DragNow.Y));
		Box(A.X, A.Y, B.X - A.X, B.Y - A.Y, FLinearColor(1.f, 1.f, 1.f, 0.12f), Layer + 5);
	}
	if (Rows.IsEmpty()) Text(LabelWidth + 8.f, RulerHeight + 6.f, TEXT("做一段動作：選物件打 key（K）→ 點上方尺規換時間 → 移動 → 再打 key → 播放"), TextHint(), 10.f, Layer + 2);
	return Layer + 6;
}

bool SOKStudioTimeline::HitKey(const FGeometry& G, const FVector2D& Local, FKeyRef& Out) const
{
	if (!Game.IsValid() || Local.Y < RulerHeight || Local.X < LabelWidth) return false;
	const TArray<FRowInfo> Rows = RowInfos();
	const int32 Row = RowScroll + int32((Local.Y - RulerHeight) / RowHeight);
	if (!Rows.IsValidIndex(Row)) return false;
	const FOKSceneTrack* T = Game->Document->TrackOf(Rows[Row].Track);
	const FOKSceneObject* O = Game->Document->Find(Rows[Row].Track);
	if (!T) return false;
	float Best = 6.f;
	bool bHit = false;
	for (const FOKSceneKey& K : T->Keys)
	{
		if (Rows[Row].Sub >= 0 && !SubHasKey(Rows[Row].Sub, K, O)) continue;
		const float D = FMath::Abs(TimeToX(G, K.Time) - float(Local.X));
		if (D < Best) { Best = D; Out = { Rows[Row].Track, K.Time }; bHit = true; }
	}
	return bHit;
}

bool SOKStudioTimeline::HitVoice(const FGeometry& G, const FVector2D& Local, int32& OutTrack, int32& OutIndex) const
{
	if (!Game.IsValid() || Local.Y < RulerHeight || Local.X < LabelWidth) return false;
	const TArray<FRowInfo> Rows = RowInfos();
	const int32 Row = RowScroll + int32((Local.Y - RulerHeight) / RowHeight);
	if (!Rows.IsValidIndex(Row) || (Rows[Row].Sub >= 0 && Rows[Row].Sub != 5)) return false;
	const FOKSceneObject* O = Game->Document->Find(Rows[Row].Track);
	if (!O) return false;
	// The last laid on top.
	for (int32 V = O->Character.VoiceClips.Num() - 1; V >= 0; --V)
	{
		const FOKSceneVoiceClip& Voice = O->Character.VoiceClips[V];
		if (Local.X >= TimeToX(G, Voice.Start) - 2.f && Local.X <= TimeToX(G, Voice.Start + Game->VoiceClipSeconds(Voice)) + 2.f) { OutTrack = O->Id; OutIndex = V; return true; }
	}
	return false;
}

void SOKStudioTimeline::Scrub(float Time)
{
	if (!Game.IsValid()) return;
	Game->SetTimelineTime(Time);
	// The characters' animations follow the play head too (a still frame of the moment).
	if (Game->SceneActor)
		for (const FOKSceneObject& O : Game->Document->Objects)
			if (O.Kind == EOKSceneObjectKind::Character) Game->SceneActor->SetAnimationTime(O.Id, Game->TimelineTime);
}

FReply SOKStudioTimeline::OnMouseButtonDown(const FGeometry& G, const FPointerEvent& E)
{
	if (!Game.IsValid()) return FReply::Unhandled();
	const FVector2D Local = G.AbsoluteToLocal(E.GetScreenSpacePosition());
	DragFrom = DragNow = Local;
	FKeyRef Key;
	const bool bKey = HitKey(G, Local, Key);
	if (E.GetEffectingButton() == EKeys::RightMouseButton)
	{
		if (bKey && !Selected.Contains(Key)) Selected = { Key };
		// The menu keeps the focus (taking it back to the timeline would dismiss the menu at once).
		if (bKey && OnEaseMenu) { OnEaseMenu(E.GetScreenSpacePosition()); return FReply::Handled(); }
		return FReply::Handled().SetUserFocus(SharedThis(this), EFocusCause::Mouse);
	}
	if (E.GetEffectingButton() != EKeys::LeftMouseButton) return FReply::Unhandled();
	if (Local.Y < RulerHeight && Local.X >= LabelWidth)
	{
		Drag = EDrag::Scrub;
		Game->bTimelinePlaying = false;
		Scrub(Snap(XToTime(G, Local.X)));
	}
	else if (Local.X < LabelWidth && Local.Y >= RulerHeight)
	{
		// Label: open / close the track, select its object.
		const TArray<FRowInfo> Rows = RowInfos();
		const int32 Row = RowScroll + int32((Local.Y - RulerHeight) / RowHeight);
		if (Rows.IsValidIndex(Row) && Rows[Row].Sub < 0)
		{
			const int32 Track = Rows[Row].Track;
			if (Local.X < 14.f) { if (Open.Contains(Track)) Open.Remove(Track); else Open.Add(Track); }
			else if (Game->Document->Find(Track)) { if (E.IsShiftDown() || E.IsControlDown()) Game->ToggleSelect(Track); else Game->Select(Track); }
		}
	}
	else if (bKey)
	{
		VoiceTrack = -1;
		if (E.IsShiftDown() || E.IsControlDown()) { if (Selected.Contains(Key)) Selected.Remove(Key); else Selected.Add(Key); }
		else if (!Selected.Contains(Key)) Selected = { Key };
		Drag = EDrag::Keys;
		DragTimeFrom = XToTime(G, Local.X);
	}
	else if (HitVoice(G, Local, VoiceTrack, VoiceIndex))
	{
		Selected.Reset();
		Drag = EDrag::Voice;
		DragTimeFrom = XToTime(G, Local.X);
	}
	else
	{
		VoiceTrack = -1;
		if (!E.IsShiftDown() && !E.IsControlDown()) Selected.Reset();
		Drag = EDrag::Box;
	}
	return FReply::Handled().CaptureMouse(SharedThis(this)).SetUserFocus(SharedThis(this), EFocusCause::Mouse);
}

FReply SOKStudioTimeline::OnMouseMove(const FGeometry& G, const FPointerEvent& E)
{
	if (!HasMouseCapture() || !Game.IsValid()) return FReply::Unhandled();
	DragNow = G.AbsoluteToLocal(E.GetScreenSpacePosition());
	if (Drag == EDrag::Scrub) Scrub(Snap(XToTime(G, DragNow.X)));
	if (Drag == EDrag::Keys && OnStatus) OnStatus(FString::Printf(TEXT("移動 %d 個 key %+.3f 秒"), Selected.Num(), Snap(XToTime(G, DragNow.X) - DragTimeFrom)));
	return FReply::Handled();
}

FReply SOKStudioTimeline::OnMouseButtonUp(const FGeometry& G, const FPointerEvent& E)
{
	if (!HasMouseCapture()) return FReply::Unhandled();
	if (Game.IsValid())
	{
		if (Drag == EDrag::Keys)
		{
			const float Shift = Snap(XToTime(G, DragNow.X) - DragTimeFrom);
			if (FMath::Abs(Shift) > 1e-4f)
			{
				// Later keys first when moving right (a moved key never lands on one still to move), earlier first when left.
				TArray<FKeyRef> Order = Selected;
				Order.Sort([Shift](const FKeyRef& A, const FKeyRef& B) { return Shift > 0.f ? A.Time > B.Time : A.Time < B.Time; });
				TArray<FKeyRef> Moved;
				for (const FKeyRef& K : Order)
				{
					FOKSceneTrack* T = Game->Document->TrackOf(K.Track);
					const int32 Index = T ? T->Keys.IndexOfByPredicate([&K](const FOKSceneKey& X) { return FMath::Abs(X.Time - K.Time) < 1e-4f; }) : INDEX_NONE;
					if (Index == INDEX_NONE) continue;
					const float To = FMath::Max(0.f, Snap(K.Time + Shift));
					Game->Document->MoveKey(K.Track, Index, To);
					Moved.Add({ K.Track, To });
				}
				Selected = Moved;
			}
		}
		else if (Drag == EDrag::Voice)
		{
			FOKSceneObject* O = Game->Document->Find(VoiceTrack);
			const float Shift = XToTime(G, DragNow.X) - DragTimeFrom;
			if (O && O->Character.VoiceClips.IsValidIndex(VoiceIndex) && FMath::Abs(Shift) > 1e-4f)
			{
				FOKSceneVoiceClip& Voice = O->Character.VoiceClips[VoiceIndex];
				Voice.Start = FMath::Max(0.f, Snap(Voice.Start + Shift));
				Game->Document->Duration = FMath::Max(Game->Document->Duration, Voice.Start + Game->VoiceClipSeconds(Voice));
				Game->Document->NotifyChanged();
			}
		}
		else if (Drag == EDrag::Box)
		{
			const FVector2D A(FMath::Min(DragFrom.X, DragNow.X), FMath::Min(DragFrom.Y, DragNow.Y)), B(FMath::Max(DragFrom.X, DragNow.X), FMath::Max(DragFrom.Y, DragNow.Y));
			const TArray<FRowInfo> Rows = RowInfos();
			for (int32 I = RowScroll; I < Rows.Num(); ++I)
			{
				const float Y = RulerHeight + (I - RowScroll) * RowHeight + RowHeight * 0.5f;
				if (Y < A.Y || Y > B.Y) continue;
				const FOKSceneTrack* T = Game->Document->TrackOf(Rows[I].Track);
				const FOKSceneObject* O = Game->Document->Find(Rows[I].Track);
				if (T) for (const FOKSceneKey& K : T->Keys)
				{
					const float X = TimeToX(G, K.Time);
					if (X >= A.X && X <= B.X && (Rows[I].Sub < 0 || SubHasKey(Rows[I].Sub, K, O))) Selected.AddUnique({ Rows[I].Track, K.Time });
				}
			}
		}
	}
	Drag = EDrag::None;
	return FReply::Handled().ReleaseMouseCapture();
}

FReply SOKStudioTimeline::OnMouseWheel(const FGeometry& G, const FPointerEvent& E)
{
	if (E.IsControlDown())
	{
		// Zoom about the mouse.
		const FVector2D Local = G.AbsoluteToLocal(E.GetScreenSpacePosition());
		const float At = XToTime(G, Local.X);
		Zoom = FMath::Clamp(Zoom * (E.GetWheelDelta() > 0.f ? 1.25f : 0.8f), 1.f, 40.f);
		Scroll = FMath::Max(0.f, Scroll + At - XToTime(G, Local.X));
	}
	else if (E.IsShiftDown()) Scroll = FMath::Max(0.f, Scroll - E.GetWheelDelta() * (Game.IsValid() ? Game->Document->Duration : 10.f) * 0.05f / Zoom);
	else RowScroll = FMath::Clamp(RowScroll - int32(E.GetWheelDelta()), 0, FMath::Max(0, RowInfos().Num() - 1));
	return FReply::Handled();
}

FReply SOKStudioTimeline::OnKeyDown(const FGeometry&, const FKeyEvent& E)
{
	if (E.GetKey() == EKeys::Delete) { DeleteSelected(); return FReply::Handled(); }
	if (E.IsControlDown() && E.GetKey() == EKeys::C) { CopySelected(); return FReply::Handled(); }
	if (E.IsControlDown() && E.GetKey() == EKeys::V) { PasteAtPlayhead(); return FReply::Handled(); }
	return FReply::Unhandled();
}

void SOKStudioTimeline::DeleteSelected()
{
	if (!Game.IsValid()) return;
	if (FOKSceneObject* O = VoiceTrack >= 0 ? Game->Document->Find(VoiceTrack) : nullptr; O && O->Character.VoiceClips.IsValidIndex(VoiceIndex))
	{
		O->Character.VoiceClips.RemoveAt(VoiceIndex);
		VoiceTrack = -1;
		Game->Document->NotifyChanged();
		if (OnStatus) OnStatus(TEXT("刪除語音片段"));
		return;
	}
	for (const FKeyRef& K : Selected) Game->Document->RemoveKey(K.Track, K.Time);
	if (OnStatus) OnStatus(FString::Printf(TEXT("刪除 %d 個 key"), Selected.Num()));
	Selected.Reset();
}

void SOKStudioTimeline::CopySelected()
{
	if (!Game.IsValid() || Selected.IsEmpty()) return;
	Clip.Reset();
	float First = TNumericLimits<float>::Max();
	for (const FKeyRef& K : Selected) First = FMath::Min(First, K.Time);
	for (const FKeyRef& K : Selected)
		if (const FOKSceneKey* Key = Game->Document->KeyAt(K.Track, K.Time)) { FOKSceneKey Copy = *Key; Copy.Time -= First; Clip.Add({ K.Track, Copy }); }
	if (OnStatus) OnStatus(FString::Printf(TEXT("複製 %d 個 key"), Clip.Num()));
}

void SOKStudioTimeline::PasteAtPlayhead()
{
	if (!Game.IsValid() || Clip.IsEmpty()) return;
	UOKSceneDocument* Doc = Game->Document;
	Selected.Reset();
	for (const TPair<int32, FOKSceneKey>& C : Clip)
	{
		FOKSceneTrack* T = Doc->TrackOf(C.Key);
		if (!T && (Doc->Find(C.Key) || C.Key == UOKSceneDocument::SceneTrackId)) { T = &Doc->Tracks.AddDefaulted_GetRef(); T->ObjectId = C.Key; }
		if (!T) continue;
		FOKSceneKey K = C.Value;
		K.Time = Snap(Game->TimelineTime + K.Time);
		T->Keys.RemoveAll([&K](const FOKSceneKey& X) { return FMath::Abs(X.Time - K.Time) < 1.f / 60.f; });
		T->Keys.Add(K);
		T->Keys.Sort([](const FOKSceneKey& A, const FOKSceneKey& B) { return A.Time < B.Time; });
		Doc->Duration = FMath::Max(Doc->Duration, K.Time);
		Selected.Add({ C.Key, K.Time });
	}
	Doc->NotifyChanged();
	if (OnStatus) OnStatus(FString::Printf(TEXT("貼上 %d 個 key 到 %.2f 秒"), Clip.Num(), Game->TimelineTime));
}

void SOKStudioTimeline::SetEase(EOKSceneEase Ease)
{
	if (!Game.IsValid()) return;
	for (const FKeyRef& K : Selected) if (FOKSceneKey* Key = Game->Document->KeyAt(K.Track, K.Time)) Key->Ease = Ease;
	Game->Document->NotifyChanged();
}

void SOKStudioTimeline::KeySelection()
{
	if (!Game.IsValid()) return;
	// U191: with nothing selected it reported "0 objects keyed", which read like a failure with no reason.
	if (Game->Selection.IsEmpty()) { if (OnStatus) OnStatus(TEXT("先選物件再打 key")); return; }
	const float Time = Snap(Game->TimelineTime);
	for (int32 Id : Game->Selection) Game->Document->SetKey(Id, Time);
	if (OnStatus) OnStatus(FString::Printf(TEXT("在 %.2f 秒為 %d 個物件打 key"), Time, Game->Selection.Num()));
}
