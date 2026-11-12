#include "SOKStudioTimeline.h"
#include "SOKStudioTimelineCurve.h"
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
	OnInterpMenu = Args._OnInterpMenu;
	OnOpenCurve = Args._OnOpenCurve;
	OnSelectInterpKey = Args._OnSelectInterpKey;
	OnStatus = Args._OnStatus;
}

FString SOKStudioTimeline::GroupKeyForInterp(const UOKSceneDocument* Doc, const FOKSceneTimelineTrack& Tr)
{
	if (!Tr.GroupPath.IsEmpty()) return Tr.GroupPath;
	if (Tr.ObjectId >= 0)
	{
		if (const FOKSceneObject* O = Doc ? Doc->Find(Tr.ObjectId) : nullptr)
		{
			return FString::Printf(TEXT("#%d %s"), O->Id, *O->Name);
		}
		return FString::Printf(TEXT("对象 #%d"), Tr.ObjectId);
	}
	if (!Tr.Owner.IsEmpty() && !Tr.Owner.Equals(TEXT("Timeline"), ESearchCase::IgnoreCase))
	{
		return FString::Printf(TEXT("全局 · %s"), *Tr.Owner);
	}
	return TEXT("全局与镜头 (Timeline)");
}

TArray<SOKStudioTimeline::FRowInfo> SOKStudioTimeline::RowInfos() const
{
	TArray<FRowInfo> Rows;
	if (!Game.IsValid() || !Game->Document) return Rows;
	const UOKSceneDocument* Doc = Game->Document;
	static const TCHAR* Subs[] = { TEXT("变换"), TEXT("FK"), TEXT("状态"), TEXT("数值"), TEXT("动作"), TEXT("语音") };
	auto AddRows = [&](int32 Track)
	{
		const FOKSceneObject* O = Doc->Find(Track);
		FRowInfo R;
		R.Kind = ERowKind::SceneTrack;
		R.Track = Track;
		R.Label = Track == UOKSceneDocument::SceneTrackId ? FString(TEXT("场景（画面）")) : (O ? O->Name : FString::Printf(TEXT("#%d"), Track));
		Rows.Add(R);
		if (!Open.Contains(Track) || Track == UOKSceneDocument::SceneTrackId) return;
		for (int32 S = 0; S < 6; ++S)
		{
			if ((S == 1 || S == 2 || S == 4 || S == 5) && (!O || O->Kind != EOKSceneObjectKind::Character)) continue;
			if (S == 3 && (!O || (O->Kind != EOKSceneObjectKind::Light && O->Kind != EOKSceneObjectKind::Camera && O->Kind != EOKSceneObjectKind::Effect))) continue;
			FRowInfo Sub;
			Sub.Kind = ERowKind::SceneTrack;
			Sub.Track = Track;
			Sub.Sub = S;
			Sub.Label = FString(TEXT("    ")) + Subs[S];
			Rows.Add(Sub);
		}
	};
	for (const FOKSceneTrack& T : Doc->Tracks) AddRows(T.ObjectId);
	for (const FOKSceneObject& O : Doc->Objects)
		if (!O.Character.VoiceClips.IsEmpty() && !Doc->TrackOf(O.Id)) AddRows(O.Id);

	// Append grouped Timeline.dll continuous interpolable tracks
	if (!Doc->TimelineTracks.IsEmpty())
	{
		TArray<FString> GroupOrder;
		TMap<FString, TArray<int32>> Grouped;
		for (int32 I = 0; I < Doc->TimelineTracks.Num(); ++I)
		{
			const FString GK = GroupKeyForInterp(Doc, Doc->TimelineTracks[I]);
			if (!Grouped.Contains(GK)) GroupOrder.Add(GK);
			Grouped.FindOrAdd(GK).Add(I);
		}

		for (const FString& GK : GroupOrder)
		{
			const TArray<int32>& Indices = Grouped[GK];
			FRowInfo Header;
			Header.Kind = ERowKind::InterpGroup;
			Header.GroupKey = GK;
			Header.Label = FString::Printf(TEXT("%s (%d)"), *GK, Indices.Num());
			Rows.Add(Header);

			if (ClosedInterpGroups.Contains(GK)) continue;
			for (int32 Idx : Indices)
			{
				const FOKSceneTimelineTrack& Tr = Doc->TimelineTracks[Idx];
				FRowInfo TRow;
				TRow.Kind = ERowKind::InterpTrack;
				TRow.InterpIndex = Idx;
				TRow.Track = Tr.ObjectId;
				TRow.Label = Doc->DescribeTimelineTrack(Tr);
				Rows.Add(TRow);
			}
		}
	}

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
	auto DrawBox = [&](float X, float Y, float W, float H, const FLinearColor& C, int32 L)
	{
		FSlateDrawElement::MakeBox(Out, L, G.ToPaintGeometry(FVector2f(W, H), FSlateLayoutTransform(FVector2f(X, Y))), Brush(C), ESlateDrawEffect::None, C);
	};
	auto DrawText = [&](float X, float Y, const FString& S, const FLinearColor& C, float Px, int32 L, float MaxW = 400.f)
	{
		FSlateDrawElement::MakeText(Out, L, G.ToPaintGeometry(FVector2f(MaxW, 20.f), FSlateLayoutTransform(FVector2f(X, Y))), S, Font(Px), ESlateDrawEffect::None, C);
	};
	DrawBox(0.f, 0.f, float(Size.X), float(Size.Y), ListArea(), Layer);
	if (!Game.IsValid() || !Game->Document) return Layer + 1;
	const UOKSceneDocument* Doc = Game->Document;
	const float Duration = FMath::Max(Doc->Duration, 0.1f);

	// Loop range
	if (Game->LoopEnd > Game->LoopStart)
	{
		const float X0 = TimeToX(G, Game->LoopStart), X1 = TimeToX(G, Game->LoopEnd);
		DrawBox(X0, 0.f, FMath::Max(1.f, X1 - X0), float(Size.Y), FLinearColor(0.35f, 0.6f, 1.f, 0.12f), Layer + 1);
	}

	// Ruler & subdivision grid
	DrawBox(0.f, 0.f, float(Size.X), RulerHeight, Panel(), Layer + 1);
	const float PixelsPerSecond = TimeToX(G, 1.f) - TimeToX(G, 0.f);
	const float BlockLen = FMath::Max(Doc->TimelineBlockLength, 0.1f);
	const int32 Divs = FMath::Clamp(Doc->TimelineDivisions, 1, 120);
	const float SubStepSec = BlockLen / float(Divs);
	if (Divs > 1 && PixelsPerSecond * SubStepSec >= 6.f)
	{
		const int32 MaxSteps = FMath::Min(2000, FMath::CeilToInt(Duration / SubStepSec));
		for (int32 Step = 1; Step <= MaxSteps; ++Step)
		{
			if (Step % Divs == 0) continue;
			const float X = TimeToX(G, Step * SubStepSec);
			if (X < LabelWidth || X > Size.X) continue;
			const TArray<FVector2f> SubLine = { FVector2f(X, RulerHeight), FVector2f(X, float(Size.Y)) };
			if (DrawableLine(SubLine))
				FSlateDrawElement::MakeLines(Out, Layer + 1, G.ToPaintGeometry(), SubLine, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.04f));
		}
	}

	const int32 Every = PixelsPerSecond > 40.f ? 1 : (PixelsPerSecond > 12.f ? 5 : 10);
	for (int32 S = 0; S <= FMath::CeilToInt(Duration); S += Every)
	{
		const float X = TimeToX(G, float(S));
		if (X < LabelWidth || X > Size.X) continue;
		const TArray<FVector2f> SecLine = { FVector2f(X, RulerHeight - 6.f), FVector2f(X, float(Size.Y)) };
		if (DrawableLine(SecLine))
			FSlateDrawElement::MakeLines(Out, Layer + 2, G.ToPaintGeometry(), SecLine, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.13f));
		if (X < Size.X - 14.f) DrawText(X + 2.f, 1.f, FString::Printf(TEXT("%d"), S), TextHint(), 9.f, Layer + 2);
	}

	// Rows
	const TArray<FRowInfo> Rows = RowInfos();
	for (int32 I = RowScroll; I < Rows.Num(); ++I)
	{
		const float Y = RulerHeight + (I - RowScroll) * RowHeight;
		if (Y > Size.Y) break;
		const FRowInfo& R = Rows[I];

		if (R.Kind == ERowKind::InterpGroup)
		{
			DrawBox(0.f, Y, float(Size.X), RowHeight, FLinearColor(0.10f, 0.22f, 0.38f, 0.65f), Layer + 1);
			const bool bClosed = ClosedInterpGroups.Contains(R.GroupKey);
			DrawText(3.f, Y + 1.f, FString::Printf(TEXT("%s %s"), bClosed ? TEXT("▶") : TEXT("▼"), *R.Label), FLinearColor(0.85f, 0.94f, 1.f), 9.5f, Layer + 2, LabelWidth - 6.f);
			const TArray<FVector2f> Sep = { FVector2f(0.f, Y + RowHeight), FVector2f(float(Size.X), Y + RowHeight) };
			if (DrawableLine(Sep))
				FSlateDrawElement::MakeLines(Out, Layer + 1, G.ToPaintGeometry(), Sep, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.08f));
			continue;
		}

		if (R.Kind == ERowKind::InterpTrack)
		{
			if (!Doc->TimelineTracks.IsValidIndex(R.InterpIndex)) continue;
			const FOKSceneTimelineTrack& Tr = Doc->TimelineTracks[R.InterpIndex];
			const bool bFocused = (FocusedInterpTrack == R.InterpIndex);
			if (bFocused) DrawBox(0.f, Y, LabelWidth, RowHeight, FLinearColor(RowFill().R, RowFill().G, RowFill().B, 0.72f), Layer + 1);
			else if (Tr.ObjectId >= 0 && Game->IsSelected(Tr.ObjectId)) DrawBox(0.f, Y, LabelWidth, RowHeight, FLinearColor(RowFill().R, RowFill().G, RowFill().B, 0.35f), Layer + 1);

			// Track color badge (x = 2..5)
			DrawBox(2.f, Y + 2.f, 3.f, RowHeight - 4.f, Tr.Color, Layer + 2);
			// Enable checkbox (x = 8..18)
			DrawBox(8.f, Y + 3.f, 10.f, 10.f, Tr.bEnabled ? On() : Input(), Layer + 2);
			if (Tr.bEnabled) DrawText(9.5f, Y + 1.f, TEXT("✓"), FLinearColor::White, 8.5f, Layer + 3, 12.f);

			const FString CleanLbl = R.Label.Len() > 16 ? R.Label.Left(15) + TEXT("…") : R.Label;
			DrawText(21.f, Y + 1.f, CleanLbl, Tr.bEnabled ? OKStudioStyle::Text() : TextHint(), 9.5f, Layer + 2, LabelWidth - 23.f);

			const TArray<FVector2f> Sep = { FVector2f(0.f, Y + RowHeight), FVector2f(float(Size.X), Y + RowHeight) };
			if (DrawableLine(Sep))
				FSlateDrawElement::MakeLines(Out, Layer + 1, G.ToPaintGeometry(), Sep, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.06f));

			for (const FOKSceneTimelineKeyframe& K : Tr.Keyframes)
			{
				const float X = TimeToX(G, K.Time);
				if (X < LabelWidth || X > Size.X) continue;
				const bool bSel = Selected.Contains(FKeyRef::MakeInterp(R.InterpIndex, K.Time));
				bool bCustomCurve = K.Curve.Num() > 2;
				if (!bCustomCurve && K.Curve.Num() == 2)
				{
					bCustomCurve = FMath::Abs(K.Curve[0].OutTangent - 1.f) > 0.05f || FMath::Abs(K.Curve[1].InTangent - 1.f) > 0.05f;
				}
				const FLinearColor KC = bSel ? FLinearColor::Yellow
					: (!Tr.bEnabled ? FLinearColor(0.5f, 0.5f, 0.5f, 0.7f)
					: (bCustomCurve ? FLinearColor(0.45f, 0.95f, 0.65f, 1.f) : FLinearColor(0.5f, 0.85f, 1.f, 1.f)));
				const float H = 4.5f, CY = Y + RowHeight * 0.5f;
				const TArray<FVector2f> Diamond = { FVector2f(X, CY - H), FVector2f(X + H, CY), FVector2f(X, CY + H), FVector2f(X - H, CY), FVector2f(X, CY - H) };
				if (DrawableLine(Diamond))
					FSlateDrawElement::MakeLines(Out, Layer + 3, G.ToPaintGeometry(), Diamond, ESlateDrawEffect::None, KC, true, 1.8f);
			}
			continue;
		}

		// SceneTrack row
		const bool bSelectedObject = Game->IsSelected(R.Track);
		if (bSelectedObject) DrawBox(0.f, Y, LabelWidth, RowHeight, FLinearColor(RowFill().R, RowFill().G, RowFill().B, 0.6f), Layer + 1);
		const FString Arrow = R.Sub < 0 && R.Track != UOKSceneDocument::SceneTrackId ? (Open.Contains(R.Track) ? TEXT("▼ ") : TEXT("▶ ")) : TEXT("  ");
		DrawText(3.f, Y + 1.f, Arrow + R.Label, R.Sub < 0 ? OKStudioStyle::Text() : TextSoft(), 10.f, Layer + 2, LabelWidth - 5.f);
		const TArray<FVector2f> Sep = { FVector2f(0.f, Y + RowHeight), FVector2f(float(Size.X), Y + RowHeight) };
		if (DrawableLine(Sep))
			FSlateDrawElement::MakeLines(Out, Layer + 1, G.ToPaintGeometry(), Sep, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.06f));

		const FOKSceneTrack* T = Doc->TrackOf(R.Track);
		const FOKSceneObject* O = Doc->Find(R.Track);
		if (O && (R.Sub < 0 || R.Sub == 5))
		{
			for (int32 V = 0; V < O->Character.VoiceClips.Num(); ++V)
			{
				const FOKSceneVoiceClip& Voice = O->Character.VoiceClips[V];
				const bool bPicked = R.Track == VoiceTrack && V == VoiceIndex;
				const float Start = Voice.Start + (bPicked && Drag == EDrag::Voice ? XToTime(G, float(DragNow.X)) - DragTimeFrom : 0.f);
				const float X0 = FMath::Max(TimeToX(G, Start), LabelWidth), X1 = FMath::Min(TimeToX(G, Start + Game->VoiceClipSeconds(Voice)), float(Size.X));
				if (X1 <= X0) continue;
				const FLinearColor C = bPicked ? FLinearColor(1.f, .85f, .3f, .9f) : FLinearColor(.3f, .55f, 1.f, .75f);
				if (R.Sub < 0) { DrawBox(X0, Y + RowHeight - 3.f, X1 - X0, 2.f, C, Layer + 2); continue; }
				DrawBox(X0, Y + 2.f, X1 - X0, RowHeight - 4.f, C, Layer + 2);
				if (X1 - X0 >= 14.f) DrawText(X0 + 2.f, Y + 1.f, Game->VoiceClipName(Voice).Left(FMath::Max(int32((X1 - X0) / 7.f), 1)), FLinearColor::White, 9.f, Layer + 3);
			}
		}
		if (!T) continue;
		for (const FOKSceneKey& K : T->Keys)
		{
			if (R.Sub >= 0 && !SubHasKey(R.Sub, K, O)) continue;
			const float X = TimeToX(G, K.Time);
			if (X < LabelWidth || X > Size.X) continue;
			if (K.AnimBlend > 0.f && R.Sub == 4) DrawBox(X, Y + 3.f, FMath::Min(TimeToX(G, K.Time + K.AnimBlend), float(Size.X)) - X, RowHeight - 6.f, FLinearColor(.45f, .9f, .5f, .35f), Layer + 2);
			const bool bSel = Selected.Contains(FKeyRef{ R.Track, K.Time, -1 });
			const FLinearColor C = bSel ? FLinearColor::Yellow : (K.Ease == EOKSceneEase::Step ? FLinearColor(1.f, .55f, .2f) : FLinearColor(.75f, .85f, 1.f));
			const float H = R.Sub < 0 ? 5.f : 3.5f, CY = Y + RowHeight * 0.5f;
			const TArray<FVector2f> Diamond = { FVector2f(X, CY - H), FVector2f(X + H, CY), FVector2f(X, CY + H), FVector2f(X - H, CY), FVector2f(X, CY - H) };
			if (DrawableLine(Diamond))
				FSlateDrawElement::MakeLines(Out, Layer + 3, G.ToPaintGeometry(), Diamond, ESlateDrawEffect::None, C, true, 2.f);

			const FOKSceneKey* NextKey = T->Keys.FindByPredicate([&K](const FOKSceneKey& N) { return N.Time > K.Time; });
			const float Room = (NextKey ? FMath::Min(TimeToX(G, NextKey->Time) - H, float(Size.X)) : float(Size.X)) - (X + H + 2.f);
			if (R.Track == UOKSceneDocument::SceneTrackId && K.Camera >= -1)
			{
				const FOKSceneObject* Cam = Doc->Find(K.Camera);
				const FString Name = K.Camera < 0 ? FString(TEXT("自由")) : (Cam ? Cam->Name : FString(TEXT("（已删）")));
				if (Room >= 12.f) DrawText(X + H + 2.f, Y + 1.f, Name.Left(FMath::Max(int32(Room / 6.f), 1)), TextHint(), 9.f, Layer + 3);
			}
			if (K.AnimNo >= 0 && (R.Sub < 0 || R.Sub == 4) && Room >= 12.f)
			{
				const FOKSceneKey* Before = nullptr;
				for (const FOKSceneKey& P : T->Keys) if (P.Time < K.Time && P.AnimNo >= 0) Before = &P;
				const FOKStudioAnim* Anim = FOKStudioCatalog::Get().FindAnim(K.AnimKind, K.AnimGroup, K.AnimCategory, K.AnimNo);
				if (Anim && (!Before || !Before->SameMotion(K)))
					DrawText(X + H + 2.f, Y + 1.f, FOKStudioCatalog::ZhName(Anim->Name).Left(FMath::Max(int32(Room / 6.f), 1)), FLinearColor(.55f, .95f, .6f), 9.f, Layer + 3);
			}
		}
	}

	const TArray<FVector2f> BorderLine = { FVector2f(LabelWidth, 0.f), FVector2f(LabelWidth, float(Size.Y)) };
	if (DrawableLine(BorderLine))
		FSlateDrawElement::MakeLines(Out, Layer + 2, G.ToPaintGeometry(), BorderLine, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.2f));

	// Play head
	const float PX = TimeToX(G, Game->TimelineTime);
	if (Size.Y > 0.f)
	{
		const TArray<FVector2f> PlayLine = { FVector2f(PX, 0.f), FVector2f(PX, float(Size.Y)) };
		if (DrawableLine(PlayLine))
			FSlateDrawElement::MakeLines(Out, Layer + 4, G.ToPaintGeometry(), PlayLine, ESlateDrawEffect::None, FLinearColor(1.f, .3f, .3f), true, 1.5f);
	}

	if (Drag == EDrag::Box)
	{
		const FVector2D A(FMath::Min(DragFrom.X, DragNow.X), FMath::Min(DragFrom.Y, DragNow.Y)), B(FMath::Max(DragFrom.X, DragNow.X), FMath::Max(DragFrom.Y, DragNow.Y));
		DrawBox(float(A.X), float(A.Y), float(B.X - A.X), float(B.Y - A.Y), FLinearColor(1.f, 1.f, 1.f, 0.12f), Layer + 5);
	}
	if (Rows.IsEmpty())
		DrawText(LabelWidth + 8.f, RulerHeight + 6.f, TEXT("选对象按 K 打帧，或点击「+ 添加插值轨」制作连续曲线动画"), TextHint(), 10.f, Layer + 2, 460.f);
	return Layer + 6;
}

bool SOKStudioTimeline::HitKey(const FGeometry& G, const FVector2D& Local, FKeyRef& Out) const
{
	if (!Game.IsValid() || !Game->Document || Local.Y < RulerHeight || Local.X < LabelWidth) return false;
	const TArray<FRowInfo> Rows = RowInfos();
	const int32 Row = RowScroll + int32((Local.Y - RulerHeight) / RowHeight);
	if (!Rows.IsValidIndex(Row)) return false;

	if (Rows[Row].Kind == ERowKind::InterpTrack)
	{
		const int32 Idx = Rows[Row].InterpIndex;
		if (!Game->Document->TimelineTracks.IsValidIndex(Idx)) return false;
		const FOKSceneTimelineTrack& Tr = Game->Document->TimelineTracks[Idx];
		float Best = 6.5f;
		bool bHit = false;
		for (const FOKSceneTimelineKeyframe& K : Tr.Keyframes)
		{
			const float D = FMath::Abs(TimeToX(G, K.Time) - float(Local.X));
			if (D < Best) { Best = D; Out = FKeyRef::MakeInterp(Idx, K.Time); bHit = true; }
		}
		return bHit;
	}

	if (Rows[Row].Kind != ERowKind::SceneTrack) return false;
	const FOKSceneTrack* T = Game->Document->TrackOf(Rows[Row].Track);
	const FOKSceneObject* O = Game->Document->Find(Rows[Row].Track);
	if (!T) return false;
	float Best = 6.f;
	bool bHit = false;
	for (const FOKSceneKey& K : T->Keys)
	{
		if (Rows[Row].Sub >= 0 && !SubHasKey(Rows[Row].Sub, K, O)) continue;
		const float D = FMath::Abs(TimeToX(G, K.Time) - float(Local.X));
		if (D < Best) { Best = D; Out = { Rows[Row].Track, K.Time, -1 }; bHit = true; }
	}
	return bHit;
}

bool SOKStudioTimeline::HitVoice(const FGeometry& G, const FVector2D& Local, int32& OutTrack, int32& OutIndex) const
{
	if (!Game.IsValid() || !Game->Document || Local.Y < RulerHeight || Local.X < LabelWidth) return false;
	const TArray<FRowInfo> Rows = RowInfos();
	const int32 Row = RowScroll + int32((Local.Y - RulerHeight) / RowHeight);
	if (!Rows.IsValidIndex(Row) || Rows[Row].Kind != ERowKind::SceneTrack || (Rows[Row].Sub >= 0 && Rows[Row].Sub != 5)) return false;
	const FOKSceneObject* O = Game->Document->Find(Rows[Row].Track);
	if (!O) return false;
	for (int32 V = O->Character.VoiceClips.Num() - 1; V >= 0; --V)
	{
		const FOKSceneVoiceClip& Voice = O->Character.VoiceClips[V];
		if (Local.X >= TimeToX(G, Voice.Start) - 2.f && Local.X <= TimeToX(G, Voice.Start + Game->VoiceClipSeconds(Voice)) + 2.f)
		{
			OutTrack = O->Id;
			OutIndex = V;
			return true;
		}
	}
	return false;
}

void SOKStudioTimeline::Scrub(float Time)
{
	if (!Game.IsValid()) return;
	Game->SetTimelineTime(Time);
	if (Game->SceneActor)
		for (const FOKSceneObject& O : Game->Document->Objects)
			if (O.Kind == EOKSceneObjectKind::Character) Game->SceneActor->SetAnimationTime(O.Id, Game->TimelineTime);
}

FReply SOKStudioTimeline::OnMouseButtonDown(const FGeometry& G, const FPointerEvent& E)
{
	if (!Game.IsValid() || !Game->Document) return FReply::Unhandled();
	const FVector2D Local = G.AbsoluteToLocal(E.GetScreenSpacePosition());
	DragFrom = DragNow = Local;
	FKeyRef Key;
	const bool bKey = HitKey(G, Local, Key);

	const TArray<FRowInfo> Rows = RowInfos();
	const int32 Row = Local.Y >= RulerHeight ? (RowScroll + int32((Local.Y - RulerHeight) / RowHeight)) : -1;

	if (E.GetEffectingButton() == EKeys::RightMouseButton)
	{
		if (bKey)
		{
			if (!Selected.Contains(Key)) Selected = { Key };
			if (Key.IsInterp())
			{
				FocusedInterpTrack = Key.InterpTrack;
				if (OnSelectInterpKey) OnSelectInterpKey(Key.InterpTrack, Key.Time);
				if (OnInterpMenu) { OnInterpMenu(Key.InterpTrack, Key.Time, E.GetScreenSpacePosition()); return FReply::Handled(); }
			}
			if (OnEaseMenu) { OnEaseMenu(E.GetScreenSpacePosition()); return FReply::Handled(); }
		}
		else if (Rows.IsValidIndex(Row) && Rows[Row].Kind == ERowKind::InterpTrack)
		{
			FocusedInterpTrack = Rows[Row].InterpIndex;
			if (OnSelectInterpKey) OnSelectInterpKey(FocusedInterpTrack, Game->TimelineTime);
			if (OnInterpMenu) { OnInterpMenu(FocusedInterpTrack, -1.f, E.GetScreenSpacePosition()); return FReply::Handled(); }
		}
		return FReply::Handled().SetUserFocus(SharedThis(this), EFocusCause::Mouse);
	}

	if (E.GetEffectingButton() != EKeys::LeftMouseButton) return FReply::Unhandled();

	if (Local.Y < RulerHeight && Local.X >= LabelWidth)
	{
		Drag = EDrag::Scrub;
		Game->bTimelinePlaying = false;
		Scrub(Snap(XToTime(G, float(Local.X))));
	}
	else if (Local.X < LabelWidth && Rows.IsValidIndex(Row))
	{
		const FRowInfo& RI = Rows[Row];
		if (RI.Kind == ERowKind::InterpGroup)
		{
			if (ClosedInterpGroups.Contains(RI.GroupKey)) ClosedInterpGroups.Remove(RI.GroupKey);
			else ClosedInterpGroups.Add(RI.GroupKey);
		}
		else if (RI.Kind == ERowKind::InterpTrack && Game->Document->TimelineTracks.IsValidIndex(RI.InterpIndex))
		{
			FOKSceneTimelineTrack& Tr = Game->Document->TimelineTracks[RI.InterpIndex];
			if (Local.X >= 6.f && Local.X <= 19.f)
			{
				Tr.bEnabled = !Tr.bEnabled;
				Game->Document->NotifyChanged();
				Game->SetTimelineTime(Game->TimelineTime);
				if (OnStatus) OnStatus(FString::Printf(TEXT("%s 插值轨：%s"), Tr.bEnabled ? TEXT("已启用") : TEXT("已禁用"), *Game->Document->DescribeTimelineTrack(Tr)));
			}
			else
			{
				FocusedInterpTrack = RI.InterpIndex;
				if (Tr.ObjectId >= 0 && Game->Document->Find(Tr.ObjectId)) Game->Select(Tr.ObjectId);
				const float FirstT = Tr.Keyframes.Num() ? Tr.Keyframes[0].Time : Game->TimelineTime;
				if (OnSelectInterpKey) OnSelectInterpKey(RI.InterpIndex, FirstT);
			}
		}
		else if (RI.Kind == ERowKind::SceneTrack && RI.Sub < 0)
		{
			const int32 Track = RI.Track;
			if (Local.X < 14.f) { if (Open.Contains(Track)) Open.Remove(Track); else Open.Add(Track); }
			else if (Game->Document->Find(Track))
			{
				FocusedInterpTrack = -1;
				if (E.IsShiftDown() || E.IsControlDown()) Game->ToggleSelect(Track);
				else Game->Select(Track);
			}
		}
	}
	else if (bKey)
	{
		VoiceTrack = -1;
		if (Key.IsInterp())
		{
			FocusedInterpTrack = Key.InterpTrack;
			if (OnSelectInterpKey) OnSelectInterpKey(Key.InterpTrack, Key.Time);
		}
		if (E.IsShiftDown() || E.IsControlDown()) { if (Selected.Contains(Key)) Selected.Remove(Key); else Selected.Add(Key); }
		else if (!Selected.Contains(Key)) Selected = { Key };
		Drag = EDrag::Keys;
		DragTimeFrom = XToTime(G, float(Local.X));
	}
	else if (HitVoice(G, Local, VoiceTrack, VoiceIndex))
	{
		Selected.Reset();
		Drag = EDrag::Voice;
		DragTimeFrom = XToTime(G, float(Local.X));
	}
	else
	{
		VoiceTrack = -1;
		if (!E.IsShiftDown() && !E.IsControlDown()) Selected.Reset();
		Drag = EDrag::Box;
	}
	return FReply::Handled().CaptureMouse(SharedThis(this)).SetUserFocus(SharedThis(this), EFocusCause::Mouse);
}

FReply SOKStudioTimeline::OnMouseButtonDoubleClick(const FGeometry& G, const FPointerEvent& E)
{
	if (!Game.IsValid() || !Game->Document || E.GetEffectingButton() != EKeys::LeftMouseButton) return FReply::Unhandled();
	const FVector2D Local = G.AbsoluteToLocal(E.GetScreenSpacePosition());
	FKeyRef Key;
	if (HitKey(G, Local, Key) && Key.IsInterp())
	{
		FocusedInterpTrack = Key.InterpTrack;
		if (OnSelectInterpKey) OnSelectInterpKey(Key.InterpTrack, Key.Time);
		if (OnOpenCurve) OnOpenCurve(Key.InterpTrack, Key.Time);
		return FReply::Handled();
	}
	if (Local.X < LabelWidth && Local.Y >= RulerHeight)
	{
		const TArray<FRowInfo> Rows = RowInfos();
		const int32 Row = RowScroll + int32((Local.Y - RulerHeight) / RowHeight);
		if (Rows.IsValidIndex(Row) && Rows[Row].Kind == ERowKind::InterpTrack && Local.X > 20.f)
		{
			FocusedInterpTrack = Rows[Row].InterpIndex;
			const FOKSceneTimelineTrack& Tr = Game->Document->TimelineTracks[FocusedInterpTrack];
			const float T = Tr.Keyframes.Num() ? Tr.Keyframes[0].Time : Game->TimelineTime;
			if (OnOpenCurve) OnOpenCurve(FocusedInterpTrack, T);
			return FReply::Handled();
		}
	}
	return FReply::Unhandled();
}

FReply SOKStudioTimeline::OnMouseMove(const FGeometry& G, const FPointerEvent& E)
{
	if (!HasMouseCapture() || !Game.IsValid()) return FReply::Unhandled();
	DragNow = G.AbsoluteToLocal(E.GetScreenSpacePosition());
	if (Drag == EDrag::Scrub) Scrub(Snap(XToTime(G, float(DragNow.X))));
	if (Drag == EDrag::Keys && OnStatus) OnStatus(FString::Printf(TEXT("移动 %d 个关键帧 %+.3f 秒"), Selected.Num(), Snap(XToTime(G, float(DragNow.X)) - DragTimeFrom)));
	return FReply::Handled();
}

FReply SOKStudioTimeline::OnMouseButtonUp(const FGeometry& G, const FPointerEvent& E)
{
	if (!HasMouseCapture()) return FReply::Unhandled();
	if (Game.IsValid() && Game->Document)
	{
		if (Drag == EDrag::Keys)
		{
			const float Shift = Snap(XToTime(G, float(DragNow.X)) - DragTimeFrom);
			if (FMath::Abs(Shift) > 1e-4f)
			{
				TArray<FKeyRef> Order = Selected;
				Order.Sort([Shift](const FKeyRef& A, const FKeyRef& B) { return Shift > 0.f ? A.Time > B.Time : A.Time < B.Time; });
				TArray<FKeyRef> Moved;
				bool bMovedInterp = false;
				for (const FKeyRef& K : Order)
				{
					if (K.IsInterp())
					{
						if (!Game->Document->TimelineTracks.IsValidIndex(K.InterpTrack)) continue;
						FOKSceneTimelineTrack& Tr = Game->Document->TimelineTracks[K.InterpTrack];
						const int32 Index = Tr.Keyframes.IndexOfByPredicate([&K](const FOKSceneTimelineKeyframe& X) { return FMath::Abs(X.Time - K.Time) < 1e-4f; });
						if (Index == INDEX_NONE) continue;
						const float To = FMath::Max(0.f, Snap(K.Time + Shift));
						FOKSceneTimelineKeyframe Copy = Tr.Keyframes[Index];
						Copy.Time = To;
						Tr.Keyframes.RemoveAt(Index);
						Tr.Keyframes.RemoveAll([To](const FOKSceneTimelineKeyframe& X) { return FMath::Abs(X.Time - To) < 1e-4f; });
						Tr.Keyframes.Add(MoveTemp(Copy));
						Tr.Keyframes.Sort([](const FOKSceneTimelineKeyframe& A, const FOKSceneTimelineKeyframe& B) { return A.Time < B.Time; });
						Game->Document->Duration = FMath::Max(Game->Document->Duration, To);
						Moved.Add(FKeyRef::MakeInterp(K.InterpTrack, To));
						bMovedInterp = true;
						continue;
					}
					FOKSceneTrack* T = Game->Document->TrackOf(K.Track);
					const int32 Index = T ? T->Keys.IndexOfByPredicate([&K](const FOKSceneKey& X) { return FMath::Abs(X.Time - K.Time) < 1e-4f; }) : INDEX_NONE;
					if (Index == INDEX_NONE) continue;
					const float To = FMath::Max(0.f, Snap(K.Time + Shift));
					Game->Document->MoveKey(K.Track, Index, To);
					Moved.Add({ K.Track, To, -1 });
				}
				Selected = Moved;
				if (bMovedInterp)
				{
					Game->Document->NotifyChanged();
					Game->SetTimelineTime(Game->TimelineTime);
				}
			}
		}
		else if (Drag == EDrag::Voice)
		{
			FOKSceneObject* O = Game->Document->Find(VoiceTrack);
			const float Shift = XToTime(G, float(DragNow.X)) - DragTimeFrom;
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
				if (Rows[I].Kind == ERowKind::InterpTrack && Game->Document->TimelineTracks.IsValidIndex(Rows[I].InterpIndex))
				{
					const FOKSceneTimelineTrack& Tr = Game->Document->TimelineTracks[Rows[I].InterpIndex];
					for (const FOKSceneTimelineKeyframe& K : Tr.Keyframes)
					{
						const float X = TimeToX(G, K.Time);
						if (X >= A.X && X <= B.X) Selected.AddUnique(FKeyRef::MakeInterp(Rows[I].InterpIndex, K.Time));
					}
					continue;
				}
				if (Rows[I].Kind != ERowKind::SceneTrack) continue;
				const FOKSceneTrack* T = Game->Document->TrackOf(Rows[I].Track);
				const FOKSceneObject* O = Game->Document->Find(Rows[I].Track);
				if (T)
				{
					for (const FOKSceneKey& K : T->Keys)
					{
						const float X = TimeToX(G, K.Time);
						if (X >= A.X && X <= B.X && (Rows[I].Sub < 0 || SubHasKey(Rows[I].Sub, K, O)))
							Selected.AddUnique({ Rows[I].Track, K.Time, -1 });
					}
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
		const FVector2D Local = G.AbsoluteToLocal(E.GetScreenSpacePosition());
		const float At = XToTime(G, float(Local.X));
		Zoom = FMath::Clamp(Zoom * (E.GetWheelDelta() > 0.f ? 1.25f : 0.8f), 1.f, 40.f);
		Scroll = FMath::Max(0.f, Scroll + At - XToTime(G, float(Local.X)));
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
	if (!Game.IsValid() || !Game->Document) return;
	if (FOKSceneObject* O = VoiceTrack >= 0 ? Game->Document->Find(VoiceTrack) : nullptr; O && O->Character.VoiceClips.IsValidIndex(VoiceIndex))
	{
		O->Character.VoiceClips.RemoveAt(VoiceIndex);
		VoiceTrack = -1;
		Game->Document->NotifyChanged();
		if (OnStatus) OnStatus(TEXT("已删除语音片段"));
		return;
	}
	bool bRemovedInterp = false;
	for (const FKeyRef& K : Selected)
	{
		if (K.IsInterp())
		{
			if (Game->Document->TimelineTracks.IsValidIndex(K.InterpTrack))
			{
				Game->Document->TimelineTracks[K.InterpTrack].Keyframes.RemoveAll([&K](const FOKSceneTimelineKeyframe& X) { return FMath::Abs(X.Time - K.Time) < 1e-3f; });
				bRemovedInterp = true;
			}
		}
		else
		{
			Game->Document->RemoveKey(K.Track, K.Time);
		}
	}
	if (bRemovedInterp)
	{
		Game->Document->NotifyChanged();
		Game->SetTimelineTime(Game->TimelineTime);
	}
	if (OnStatus) OnStatus(FString::Printf(TEXT("已删除 %d 个关键帧"), Selected.Num()));
	Selected.Reset();
}

void SOKStudioTimeline::CopySelected()
{
	if (!Game.IsValid() || !Game->Document || Selected.IsEmpty()) return;
	Clip.Reset();
	InterpClip.Reset();
	float First = TNumericLimits<float>::Max();
	for (const FKeyRef& K : Selected) First = FMath::Min(First, K.Time);
	for (const FKeyRef& K : Selected)
	{
		if (K.IsInterp())
		{
			if (!Game->Document->TimelineTracks.IsValidIndex(K.InterpTrack)) continue;
			const FOKSceneTimelineTrack& Tr = Game->Document->TimelineTracks[K.InterpTrack];
			if (const FOKSceneTimelineKeyframe* Found = Tr.Keyframes.FindByPredicate([&K](const FOKSceneTimelineKeyframe& X) { return FMath::Abs(X.Time - K.Time) < 1e-3f; }))
			{
				FOKSceneTimelineKeyframe Copy = *Found;
				Copy.Time -= First;
				InterpClip.Add({ K.InterpTrack, MoveTemp(Copy) });
			}
		}
		else if (const FOKSceneKey* Key = Game->Document->KeyAt(K.Track, K.Time))
		{
			FOKSceneKey Copy = *Key;
			Copy.Time -= First;
			Clip.Add({ K.Track, MoveTemp(Copy) });
		}
	}
	if (OnStatus) OnStatus(FString::Printf(TEXT("已复制 %d 个关键帧"), Clip.Num() + InterpClip.Num()));
}

void SOKStudioTimeline::PasteAtPlayhead()
{
	if (!Game.IsValid() || !Game->Document || (Clip.IsEmpty() && InterpClip.IsEmpty())) return;
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
		Selected.Add({ C.Key, K.Time, -1 });
	}
	for (const TPair<int32, FOKSceneTimelineKeyframe>& C : InterpClip)
	{
		if (!Doc->TimelineTracks.IsValidIndex(C.Key)) continue;
		FOKSceneTimelineTrack& Tr = Doc->TimelineTracks[C.Key];
		FOKSceneTimelineKeyframe K = C.Value;
		K.Time = Snap(Game->TimelineTime + K.Time);
		Tr.Keyframes.RemoveAll([&K](const FOKSceneTimelineKeyframe& X) { return FMath::Abs(X.Time - K.Time) < 1.f / 60.f; });
		Tr.Keyframes.Add(K);
		Tr.Keyframes.Sort([](const FOKSceneTimelineKeyframe& A, const FOKSceneTimelineKeyframe& B) { return A.Time < B.Time; });
		Doc->Duration = FMath::Max(Doc->Duration, K.Time);
		Selected.Add(FKeyRef::MakeInterp(C.Key, K.Time));
	}
	Doc->NotifyChanged();
	Game->SetTimelineTime(Game->TimelineTime);
	if (OnStatus) OnStatus(FString::Printf(TEXT("已粘贴 %d 个关键帧到 %.2f 秒"), Clip.Num() + InterpClip.Num(), Game->TimelineTime));
}

void SOKStudioTimeline::SetEase(EOKSceneEase Ease)
{
	if (!Game.IsValid() || !Game->Document) return;
	// Map EOKSceneEase to Hermite preset index as well: Linear->0, EaseInOut->1, EaseIn->3, EaseOut->2, Step->4
	const int32 PresetMap[] = { 0, 1, 3, 2, 4 };
	const int32 Preset = PresetMap[FMath::Clamp(int32(Ease), 0, 4)];
	for (const FKeyRef& K : Selected)
	{
		if (K.IsInterp())
		{
			if (Game->Document->TimelineTracks.IsValidIndex(K.InterpTrack))
			{
				for (FOKSceneTimelineKeyframe& X : Game->Document->TimelineTracks[K.InterpTrack].Keyframes)
				{
					if (FMath::Abs(X.Time - K.Time) < 1e-3f) SOKStudioTimelineCurve::ApplyPresetToCurve(X.Curve, Preset);
				}
			}
		}
		else if (FOKSceneKey* Key = Game->Document->KeyAt(K.Track, K.Time))
		{
			Key->Ease = Ease;
		}
	}
	Game->Document->NotifyChanged();
	Game->SetTimelineTime(Game->TimelineTime);
}

void SOKStudioTimeline::SetCurvePresetOnSelected(int32 PresetIndex)
{
	if (!Game.IsValid() || !Game->Document) return;
	int32 Count = 0;
	for (const FKeyRef& K : Selected)
	{
		if (!K.IsInterp() || !Game->Document->TimelineTracks.IsValidIndex(K.InterpTrack)) continue;
		for (FOKSceneTimelineKeyframe& X : Game->Document->TimelineTracks[K.InterpTrack].Keyframes)
		{
			if (FMath::Abs(X.Time - K.Time) < 1e-3f)
			{
				SOKStudioTimelineCurve::ApplyPresetToCurve(X.Curve, PresetIndex);
				++Count;
			}
		}
	}
	if (Count > 0)
	{
		Game->Document->NotifyChanged();
		Game->SetTimelineTime(Game->TimelineTime);
	}
}

void SOKStudioTimeline::KeyInterpolable()
{
	if (!Game.IsValid() || !Game->Document) return;
	UOKSceneDocument* Doc = Game->Document;
	const float Time = Snap(Game->TimelineTime);
	if (Doc->TimelineTracks.IsValidIndex(FocusedInterpTrack))
	{
		const int32 KI = Doc->SetTimelineTrackKey(FocusedInterpTrack, Time);
		if (KI >= 0)
		{
			Selected = { FKeyRef::MakeInterp(FocusedInterpTrack, Time) };
			if (OnSelectInterpKey) OnSelectInterpKey(FocusedInterpTrack, Time);
			if (OnStatus) OnStatus(FString::Printf(TEXT("已在 %.2f 秒为插值轨「%s」打帧"), Time, *Doc->DescribeTimelineTrack(Doc->TimelineTracks[FocusedInterpTrack])));
			return;
		}
	}

	int32 Keyed = 0;
	for (int32 I = 0; I < Doc->TimelineTracks.Num(); ++I)
	{
		const FOKSceneTimelineTrack& Tr = Doc->TimelineTracks[I];
		if (!Tr.bEnabled) continue;
		if (Tr.ObjectId >= 0 && Game->IsSelected(Tr.ObjectId))
		{
			if (Doc->SetTimelineTrackKey(I, Time) >= 0) ++Keyed;
		}
	}
	if (Keyed > 0)
	{
		if (OnStatus) OnStatus(FString::Printf(TEXT("已在 %.2f 秒为选中对象的 %d 条插值轨打帧"), Time, Keyed));
	}
	else if (OnStatus)
	{
		OnStatus(TEXT("请先在时间轴左侧点击一条插值轨，或点击「+ 添加插值轨」"));
	}
}

void SOKStudioTimeline::KeySelection()
{
	if (!Game.IsValid() || !Game->Document) return;
	const float Time = Snap(Game->TimelineTime);
	if (Game->Selection.IsEmpty())
	{
		if (Game->Document->TimelineTracks.IsValidIndex(FocusedInterpTrack))
		{
			KeyInterpolable();
			return;
		}
		if (OnStatus) OnStatus(TEXT("请先选对象或插值轨再打帧"));
		return;
	}
	bool bCameraAside = false;
	for (int32 Id : Game->Selection)
	{
		Game->Document->SetKey(Id, Time);
		const FOKSceneObject* O = Game->Document->Find(Id);
		bCameraAside |= O && O->Kind == EOKSceneObjectKind::Camera && Game->Document->ActiveCamera != Id;
	}
	if (Game->Document->TimelineTracks.IsValidIndex(FocusedInterpTrack))
	{
		const int32 ObjId = Game->Document->TimelineTracks[FocusedInterpTrack].ObjectId;
		if (ObjId < 0 || Game->IsSelected(ObjId)) Game->Document->SetTimelineTrackKey(FocusedInterpTrack, Time);
	}
	if (OnStatus) OnStatus(FString::Printf(TEXT("已在 %.2f 秒为 %d 个对象打帧%s"), Time, Game->Selection.Num(), bCameraAside ? TEXT("（相机使用的是其自身变换；需用当前视角请点「视角打帧」）") : TEXT("")));
}
