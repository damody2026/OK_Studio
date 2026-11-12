#include "SOKStudioTimelineCurve.h"
#include "OKStudioStyle.h"
#include "Rendering/DrawElements.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Input/SSpinBox.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SWrapBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"

void SOKStudioCurveCanvas::Construct(const FArguments& Args)
{
	Game = Args._Game;
	GetKeyframe = Args._GetKeyframe;
	OnCurveEdited = Args._OnCurveEdited;
	LockTangentsPtr = Args._LockTangentsPtr;
	SelectedPointPtr = Args._SelectedPointPtr;
}

void SOKStudioCurveCanvas::EnsureDefaultCurve(TArray<FOKSceneTimelineCurvePt>& Curve)
{
	if (Curve.Num() >= 2) return;
	Curve.Reset();
	Curve.Add({ 0.f, 0.f, 1.f, 1.f });
	Curve.Add({ 1.f, 1.f, 1.f, 1.f });
}

FVector2D SOKStudioCurveCanvas::CurveToLocal(const FGeometry& G, float T, float V) const
{
	const FVector2D S = G.GetLocalSize();
	const float W = FMath::Max(20.f, float(S.X) - PadLeft - PadRight);
	const float H = FMath::Max(20.f, float(S.Y) - PadTop - PadBottom);
	const float NormY = (V - MinValRange) / (MaxValRange - MinValRange);
	return FVector2D(PadLeft + T * W, PadTop + (1.f - NormY) * H);
}

void SOKStudioCurveCanvas::LocalToCurve(const FGeometry& G, const FVector2D& Local, float& OutT, float& OutV) const
{
	const FVector2D S = G.GetLocalSize();
	const float W = FMath::Max(20.f, float(S.X) - PadLeft - PadRight);
	const float H = FMath::Max(20.f, float(S.Y) - PadTop - PadBottom);
	OutT = FMath::Clamp((float(Local.X) - PadLeft) / W, 0.f, 1.f);
	const float NormY = 1.f - (float(Local.Y) - PadTop) / H;
	OutV = FMath::Clamp(MinValRange + NormY * (MaxValRange - MinValRange), -0.5f, 1.5f);
}

FVector2D SOKStudioCurveCanvas::TangentHandleLocal(const FGeometry& G, const FOKSceneTimelineCurvePt& Pt, bool bOut) const
{
	const FVector2D P0 = CurveToLocal(G, Pt.Time, Pt.Value);
	const FVector2D S = G.GetLocalSize();
	const float W = FMath::Max(20.f, float(S.X) - PadLeft - PadRight);
	const float H = FMath::Max(20.f, float(S.Y) - PadTop - PadBottom);
	const float Slope = bOut ? Pt.OutTangent : Pt.InTangent;
	const float DirSign = bOut ? 1.f : -1.f;
	// Screen-space direction corresponding to (dt = DirSign, dv = Slope * DirSign)
	FVector2D Dir(DirSign * W, -Slope * DirSign * (H / (MaxValRange - MinValRange)));
	const float Len = Dir.Size();
	if (Len > 1e-4f) Dir /= Len;
	else Dir = FVector2D(DirSign, 0.f);
	return P0 + Dir * TangentHandleLenPx;
}

int32 SOKStudioCurveCanvas::OnPaint(const FPaintArgs&, const FGeometry& G, const FSlateRect&, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle&, bool) const
{
	using namespace OKStudioStyle;
	const FVector2D Size = G.GetLocalSize();
	auto DrawBox = [&](float X, float Y, float W, float H, const FLinearColor& C, int32 L)
	{
		FSlateDrawElement::MakeBox(Out, L, G.ToPaintGeometry(FVector2f(W, H), FSlateLayoutTransform(FVector2f(X, Y))), Brush(C), ESlateDrawEffect::None, C);
	};
	auto DrawText = [&](float X, float Y, const FString& S, const FLinearColor& C, float Px, int32 L)
	{
		FSlateDrawElement::MakeText(Out, L, G.ToPaintGeometry(FVector2f(120.f, 16.f), FSlateLayoutTransform(FVector2f(X, Y))), S, Font(Px), ESlateDrawEffect::None, C);
	};

	DrawBox(0.f, 0.f, float(Size.X), float(Size.Y), ListArea(), Layer);

	// Unit [0, 1] x [0, 1] inner highlight box
	const FVector2D TopLeft01 = CurveToLocal(G, 0.f, 1.f);
	const FVector2D BotRight01 = CurveToLocal(G, 1.f, 0.f);
	DrawBox(float(TopLeft01.X), float(TopLeft01.Y), FMath::Max(1.f, float(BotRight01.X - TopLeft01.X)), FMath::Max(1.f, float(BotRight01.Y - TopLeft01.Y)), FLinearColor(0.14f, 0.24f, 0.38f, 0.45f), Layer + 1);

	// Grid lines
	for (int32 I = 0; I <= 4; ++I)
	{
		const float U = I * 0.25f;
		const FVector2D VX0 = CurveToLocal(G, U, MinValRange);
		const FVector2D VX1 = CurveToLocal(G, U, MaxValRange);
		const TArray<FVector2f> VLine = { FVector2f(VX0), FVector2f(VX1) };
		if (DrawableLine(VLine))
		{
			const float Alpha = (I == 0 || I == 4) ? 0.30f : 0.10f;
			FSlateDrawElement::MakeLines(Out, Layer + 2, G.ToPaintGeometry(), VLine, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, Alpha));
		}
		DrawText(float(VX0.X) - 8.f, float(Size.Y) - 15.f, FString::Printf(TEXT("%.2g"), U), TextHint(), 8.5f, Layer + 2);

		const FVector2D HY0 = CurveToLocal(G, 0.f, U);
		const FVector2D HY1 = CurveToLocal(G, 1.f, U);
		const TArray<FVector2f> HLine = { FVector2f(HY0), FVector2f(HY1) };
		if (DrawableLine(HLine))
		{
			const float Alpha = (I == 0 || I == 4) ? 0.30f : 0.10f;
			FSlateDrawElement::MakeLines(Out, Layer + 2, G.ToPaintGeometry(), HLine, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, Alpha));
		}
		DrawText(2.f, float(HY0.Y) - 6.f, FString::Printf(TEXT("%.2g"), U), TextHint(), 8.5f, Layer + 2);
	}

	// Diagonal reference line (linear)
	{
		const TArray<FVector2f> Diag = { FVector2f(CurveToLocal(G, 0.f, 0.f)), FVector2f(CurveToLocal(G, 1.f, 1.f)) };
		if (DrawableLine(Diag))
		{
			FSlateDrawElement::MakeLines(Out, Layer + 2, G.ToPaintGeometry(), Diag, ESlateDrawEffect::None, FLinearColor(1.f, 1.f, 1.f, 0.12f));
		}
	}

	const FOKSceneTimelineKeyframe* Kf = GetKeyframe ? GetKeyframe() : nullptr;
	if (!Kf)
	{
		DrawText(PadLeft + 12.f, float(Size.Y) * 0.45f, TEXT("请在时间轴选中插值轨或关键帧"), TextHint(), 10.f, Layer + 3);
		return Layer + 4;
	}

	TArray<FOKSceneTimelineCurvePt> Pts = Kf->Curve;
	EnsureDefaultCurve(Pts);

	// Sample cubic-Hermite curve
	TArray<FVector2f> Sampled;
	constexpr int32 Steps = 80;
	Sampled.Reserve(Steps + 1);
	for (int32 S = 0; S <= Steps; ++S)
	{
		const float U = float(S) / float(Steps);
		const float V = UOKSceneDocument::EvaluateTimelineCurve01(Pts, U);
		Sampled.Add(FVector2f(CurveToLocal(G, U, FMath::Clamp(V, MinValRange, MaxValRange))));
	}
	if (DrawableLine(Sampled))
	{
		FSlateDrawElement::MakeLines(Out, Layer + 3, G.ToPaintGeometry(), Sampled, ESlateDrawEffect::None, FLinearColor(0.35f, 0.92f, 0.55f, 1.f), true, 2.0f);
	}

	// Draw tangent handles for selected control point
	const int32 SelIdx = FMath::Clamp(SelectedPoint(), 0, Pts.Num() - 1);
	if (Pts.IsValidIndex(SelIdx))
	{
		const FOKSceneTimelineCurvePt& SP = Pts[SelIdx];
		const FVector2D Center = CurveToLocal(G, SP.Time, SP.Value);
		if (SelIdx > 0)
		{
			const FVector2D HIn = TangentHandleLocal(G, SP, false);
			const TArray<FVector2f> LIn = { FVector2f(Center), FVector2f(HIn) };
			if (DrawableLine(LIn))
			{
				FSlateDrawElement::MakeLines(Out, Layer + 4, G.ToPaintGeometry(), LIn, ESlateDrawEffect::None, FLinearColor(0.35f, 0.85f, 1.f, 0.9f), true, 1.4f);
			}
			DrawBox(float(HIn.X) - 3.5f, float(HIn.Y) - 3.5f, 7.f, 7.f, FLinearColor(0.35f, 0.85f, 1.f, 1.f), Layer + 5);
		}
		if (SelIdx + 1 < Pts.Num())
		{
			const FVector2D HOut = TangentHandleLocal(G, SP, true);
			const TArray<FVector2f> LOut = { FVector2f(Center), FVector2f(HOut) };
			if (DrawableLine(LOut))
			{
				FSlateDrawElement::MakeLines(Out, Layer + 4, G.ToPaintGeometry(), LOut, ESlateDrawEffect::None, FLinearColor(1.f, 0.65f, 0.25f, 0.9f), true, 1.4f);
			}
			DrawBox(float(HOut.X) - 3.5f, float(HOut.Y) - 3.5f, 7.f, 7.f, FLinearColor(1.f, 0.65f, 0.25f, 1.f), Layer + 5);
		}
	}

	// Draw control points
	for (int32 I = 0; I < Pts.Num(); ++I)
	{
		const FVector2D P = CurveToLocal(G, Pts[I].Time, Pts[I].Value);
		const bool bSel = (I == SelIdx);
		const float R = bSel ? 5.f : 4.f;
		const FLinearColor Col = bSel ? FLinearColor::Yellow : FLinearColor::White;
		DrawBox(float(P.X) - R, float(P.Y) - R, R * 2.f, R * 2.f, Col, Layer + 6);
	}

	return Layer + 7;
}

FReply SOKStudioCurveCanvas::OnMouseButtonDown(const FGeometry& G, const FPointerEvent& E)
{
	FOKSceneTimelineKeyframe* Kf = GetKeyframe ? GetKeyframe() : nullptr;
	if (!Kf) return FReply::Unhandled();
	EnsureDefaultCurve(Kf->Curve);

	const FVector2D Local = G.AbsoluteToLocal(E.GetScreenSpacePosition());
	const int32 SelIdx = FMath::Clamp(SelectedPoint(), 0, Kf->Curve.Num() - 1);

	if (E.GetEffectingButton() == EKeys::RightMouseButton)
	{
		for (int32 I = 1; I + 1 < Kf->Curve.Num(); ++I)
		{
			if (FVector2D::Distance(Local, CurveToLocal(G, Kf->Curve[I].Time, Kf->Curve[I].Value)) <= 8.f)
			{
				Kf->Curve.RemoveAt(I);
				SetSelectedPoint(FMath::Clamp(I - 1, 0, Kf->Curve.Num() - 1));
				if (OnCurveEdited) OnCurveEdited();
				return FReply::Handled();
			}
		}
		return FReply::Handled();
	}

	if (E.GetEffectingButton() != EKeys::LeftMouseButton) return FReply::Unhandled();

	// Check tangent handles of selected point first
	if (Kf->Curve.IsValidIndex(SelIdx))
	{
		if (SelIdx > 0 && FVector2D::Distance(Local, TangentHandleLocal(G, Kf->Curve[SelIdx], false)) <= 8.f)
		{
			DragMode = EDragMode::InTangent;
			if (Game.IsValid()) Game->bUserDragging = true;
			return FReply::Handled().CaptureMouse(SharedThis(this));
		}
		if (SelIdx + 1 < Kf->Curve.Num() && FVector2D::Distance(Local, TangentHandleLocal(G, Kf->Curve[SelIdx], true)) <= 8.f)
		{
			DragMode = EDragMode::OutTangent;
			if (Game.IsValid()) Game->bUserDragging = true;
			return FReply::Handled().CaptureMouse(SharedThis(this));
		}
	}

	// Check control points
	for (int32 I = 0; I < Kf->Curve.Num(); ++I)
	{
		if (FVector2D::Distance(Local, CurveToLocal(G, Kf->Curve[I].Time, Kf->Curve[I].Value)) <= 8.f)
		{
			SetSelectedPoint(I);
			DragMode = EDragMode::Point;
			if (Game.IsValid()) Game->bUserDragging = true;
			if (OnCurveEdited) OnCurveEdited();
			return FReply::Handled().CaptureMouse(SharedThis(this));
		}
	}

	return FReply::Handled();
}

FReply SOKStudioCurveCanvas::OnMouseButtonDoubleClick(const FGeometry& G, const FPointerEvent& E)
{
	if (E.GetEffectingButton() != EKeys::LeftMouseButton) return FReply::Unhandled();
	FOKSceneTimelineKeyframe* Kf = GetKeyframe ? GetKeyframe() : nullptr;
	if (!Kf) return FReply::Unhandled();
	EnsureDefaultCurve(Kf->Curve);

	float T = 0.5f, V = 0.5f;
	LocalToCurve(G, G.AbsoluteToLocal(E.GetScreenSpacePosition()), T, V);
	T = FMath::Clamp(T, 0.02f, 0.98f);
	for (const FOKSceneTimelineCurvePt& Existing : Kf->Curve)
	{
		if (FMath::Abs(Existing.Time - T) < 0.015f) return FReply::Handled();
	}

	FOKSceneTimelineCurvePt NewPt;
	NewPt.Time = T;
	NewPt.Value = V;
	const float Eps = 0.01f;
	const float V0 = UOKSceneDocument::EvaluateTimelineCurve01(Kf->Curve, FMath::Max(0.f, T - Eps));
	const float V1 = UOKSceneDocument::EvaluateTimelineCurve01(Kf->Curve, FMath::Min(1.f, T + Eps));
	NewPt.InTangent = NewPt.OutTangent = FMath::Clamp((V1 - V0) / (2.f * Eps), -8.f, 8.f);

	int32 InsertIdx = Kf->Curve.Num() - 1;
	for (int32 I = 0; I < Kf->Curve.Num(); ++I)
	{
		if (Kf->Curve[I].Time > T) { InsertIdx = I; break; }
	}
	Kf->Curve.Insert(NewPt, InsertIdx);
	SetSelectedPoint(InsertIdx);
	if (OnCurveEdited) OnCurveEdited();
	return FReply::Handled();
}

FReply SOKStudioCurveCanvas::OnMouseMove(const FGeometry& G, const FPointerEvent& E)
{
	if (!HasMouseCapture() || DragMode == EDragMode::None) return FReply::Unhandled();
	FOKSceneTimelineKeyframe* Kf = GetKeyframe ? GetKeyframe() : nullptr;
	if (!Kf || Kf->Curve.Num() < 2) return FReply::Handled();

	const int32 SelIdx = FMath::Clamp(SelectedPoint(), 0, Kf->Curve.Num() - 1);
	FOKSceneTimelineCurvePt& Pt = Kf->Curve[SelIdx];
	float T = 0.f, V = 0.f;
	LocalToCurve(G, G.AbsoluteToLocal(E.GetScreenSpacePosition()), T, V);

	if (DragMode == EDragMode::Point)
	{
		if (SelIdx == 0) Pt.Time = 0.f;
		else if (SelIdx == Kf->Curve.Num() - 1) Pt.Time = 1.f;
		else
		{
			const float MinT = Kf->Curve[SelIdx - 1].Time + 0.01f;
			const float MaxT = Kf->Curve[SelIdx + 1].Time - 0.01f;
			Pt.Time = FMath::Clamp(T, MinT, MaxT);
		}
		Pt.Value = FMath::Clamp(V, -0.25f, 1.25f);
	}
	else if (DragMode == EDragMode::InTangent || DragMode == EDragMode::OutTangent)
	{
		const bool bOut = (DragMode == EDragMode::OutTangent);
		float Dt = bOut ? FMath::Max(T - Pt.Time, 0.005f) : FMath::Min(T - Pt.Time, -0.005f);
		const float Dv = V - Pt.Value;
		const float Slope = FMath::Clamp(Dv / Dt, -12.f, 12.f);
		if (bOut)
		{
			Pt.OutTangent = Slope;
			if (LockTangentsPtr && *LockTangentsPtr) Pt.InTangent = Slope;
		}
		else
		{
			Pt.InTangent = Slope;
			if (LockTangentsPtr && *LockTangentsPtr) Pt.OutTangent = Slope;
		}
	}

	if (Game.IsValid())
	{
		Game->Document->NotifyChanged();
		Game->SetTimelineTime(Game->TimelineTime);
	}
	return FReply::Handled();
}

FReply SOKStudioCurveCanvas::OnMouseButtonUp(const FGeometry&, const FPointerEvent&)
{
	if (!HasMouseCapture()) return FReply::Unhandled();
	DragMode = EDragMode::None;
	if (Game.IsValid()) Game->bUserDragging = false;
	if (OnCurveEdited) OnCurveEdited();
	return FReply::Handled().ReleaseMouseCapture();
}

// --- SOKStudioTimelineCurve ---

void SOKStudioTimelineCurve::Construct(const FArguments& Args)
{
	Game = Args._Game;
	GetActiveKey = Args._GetActiveKey;
	SetActiveKey = Args._SetActiveKey;
	OnStatus = Args._OnStatus;

	ChildSlot
	[
		SAssignNew(ContentHost, SBox)
	];
	RefreshContent();
}

void SOKStudioTimelineCurve::ApplyPresetToCurve(TArray<FOKSceneTimelineCurvePt>& Curve, int32 PresetIndex)
{
	Curve.Reset();
	switch (PresetIndex)
	{
	case 0: // 线性
		Curve.Add({ 0.f, 0.f, 1.f, 1.f });
		Curve.Add({ 1.f, 1.f, 1.f, 1.f });
		break;
	case 1: // 平滑缓入缓出
		Curve.Add({ 0.f, 0.f, 0.f, 0.f });
		Curve.Add({ 1.f, 1.f, 0.f, 0.f });
		break;
	case 2: // 快入慢出 (EaseOut)
		Curve.Add({ 0.f, 0.f, 2.2f, 2.2f });
		Curve.Add({ 1.f, 1.f, 0.f, 0.f });
		break;
	case 3: // 慢入快出 (EaseIn)
		Curve.Add({ 0.f, 0.f, 0.f, 0.f });
		Curve.Add({ 1.f, 1.f, 2.2f, 2.2f });
		break;
	case 4: // 阶跃常值 (Step)
		Curve.Add({ 0.f, 0.f, 0.f, 0.f });
		Curve.Add({ 0.999f, 0.f, 0.f, 0.f });
		Curve.Add({ 1.f, 1.f, 0.f, 0.f });
		break;
	case 5: // 回弹过冲
		Curve.Add({ 0.f, 0.f, 0.f, 1.6f });
		Curve.Add({ 0.68f, 1.12f, 0.4f, -0.4f });
		Curve.Add({ 1.f, 1.f, -0.35f, 0.f });
		break;
	default:
		Curve.Add({ 0.f, 0.f, 1.f, 1.f });
		Curve.Add({ 1.f, 1.f, 1.f, 1.f });
		break;
	}
}

FOKSceneTimelineTrack* SOKStudioTimelineCurve::ResolveTrack(int32& OutTrackIdx) const
{
	OutTrackIdx = -1;
	if (!Game.IsValid() || !Game->Document || Game->Document->TimelineTracks.IsEmpty()) return nullptr;
	int32 WantedIdx = -1;
	float WantedTime = 0.f;
	if (GetActiveKey) GetActiveKey(WantedIdx, WantedTime);
	if (!Game->Document->TimelineTracks.IsValidIndex(WantedIdx)) WantedIdx = 0;
	OutTrackIdx = WantedIdx;
	return &Game->Document->TimelineTracks[WantedIdx];
}

FOKSceneTimelineKeyframe* SOKStudioTimelineCurve::ResolveKeyframe(int32& OutTrackIdx, int32& OutKeyIdx) const
{
	OutKeyIdx = -1;
	FOKSceneTimelineTrack* Tr = ResolveTrack(OutTrackIdx);
	if (!Tr || Tr->Keyframes.IsEmpty()) return nullptr;
	int32 DummyIdx = -1;
	float WantedTime = Game.IsValid() ? Game->TimelineTime : 0.f;
	if (GetActiveKey) GetActiveKey(DummyIdx, WantedTime);

	int32 BestIdx = 0;
	float BestDist = FMath::Abs(Tr->Keyframes[0].Time - WantedTime);
	for (int32 I = 1; I < Tr->Keyframes.Num(); ++I)
	{
		const float D = FMath::Abs(Tr->Keyframes[I].Time - WantedTime);
		if (D < BestDist) { BestDist = D; BestIdx = I; }
	}
	OutKeyIdx = BestIdx;
	return &Tr->Keyframes[BestIdx];
}

void SOKStudioTimelineCurve::NotifyCurveEdited()
{
	if (Game.IsValid())
	{
		Game->Document->NotifyChanged();
		Game->SetTimelineTime(Game->TimelineTime);
	}
}

void SOKStudioTimelineCurve::RefreshContent()
{
	using namespace OKStudioStyle;
	if (!ContentHost.IsValid()) return;

	int32 TrackIdx = -1, KeyIdx = -1;
	FOKSceneTimelineTrack* Tr = ResolveTrack(TrackIdx);
	FOKSceneTimelineKeyframe* Kf = ResolveKeyframe(TrackIdx, KeyIdx);

	TSharedRef<SVerticalBox> Root = SNew(SVerticalBox);

	if (!Tr)
	{
		Root->AddSlot().FillHeight(1.f).VAlign(VAlign_Center).HAlign(HAlign_Center).Padding(12.f)
		[
			SNew(STextBlock).Font(Font(10.5f)).ColorAndOpacity(TextHint()).AutoWrapText(true)
			.Text(FText::FromString(TEXT("当前场景暂无 Timeline 属性插值轨。\n可在时间轴窗口点击「+ 添加插值轨」创建轨道，或导入含 Timeline 的场景 / XML。")))
		];
		ContentHost->SetContent(Root);
		return;
	}

	if (Kf) SOKStudioCurveCanvas::EnsureDefaultCurve(Kf->Curve);

	// 1. Track & Keyframe selector bar
	Root->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("◀ 轨")), [this]
			{
				int32 TI = 0, KI = 0;
				if (!ResolveTrack(TI) || !Game.IsValid()) return;
				const int32 N = Game->Document->TimelineTracks.Num();
				const int32 Next = (TI - 1 + N) % N;
				const float T = Game->Document->TimelineTracks[Next].Keyframes.Num() ? Game->Document->TimelineTracks[Next].Keyframes[0].Time : 0.f;
				if (SetActiveKey) SetActiveKey(Next, T);
				SelectedCurvePoint = 0;
				RefreshContent();
			}, 38.f, 19.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center).Padding(4.f, 0.f)
		[
			SNew(STextBlock).Font(Font(10.f)).ColorAndOpacity(FLinearColor(0.85f, 0.95f, 1.f)).OverflowPolicy(ETextOverflowPolicy::Ellipsis)
			.Text_Lambda([this]
			{
				int32 TI = -1, KI = -1;
				const FOKSceneTimelineTrack* T = ResolveTrack(TI);
				const FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI);
				if (!T || !Game.IsValid()) return FText::FromString(TEXT("未选择插值轨"));
				const FString Desc = Game->Document->DescribeTimelineTrack(*T);
				if (!K) return FText::FromString(FString::Printf(TEXT("[%d/%d] %s（无关键帧）"), TI + 1, Game->Document->TimelineTracks.Num(), *Desc));
				return FText::FromString(FString::Printf(TEXT("[%d/%d] %s · 帧 %d/%d @ %.3fs"), TI + 1, Game->Document->TimelineTracks.Num(), *Desc, KI + 1, T->Keyframes.Num(), K->Time));
			})
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)
		[
			Button(FText::FromString(TEXT("轨 ▶")), [this]
			{
				int32 TI = 0;
				if (!ResolveTrack(TI) || !Game.IsValid()) return;
				const int32 N = Game->Document->TimelineTracks.Num();
				const int32 Next = (TI + 1) % N;
				const float T = Game->Document->TimelineTracks[Next].Keyframes.Num() ? Game->Document->TimelineTracks[Next].Keyframes[0].Time : 0.f;
				if (SetActiveKey) SetActiveKey(Next, T);
				SelectedCurvePoint = 0;
				RefreshContent();
			}, 38.f, 19.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)
		[
			Button(FText::FromString(TEXT("◀ 上帧")), [this]
			{
				int32 TI = -1, KI = -1;
				const FOKSceneTimelineTrack* T = ResolveTrack(TI);
				ResolveKeyframe(TI, KI);
				if (!T || T->Keyframes.IsEmpty()) return;
				const int32 Prev = FMath::Max(0, KI - 1);
				if (SetActiveKey) SetActiveKey(TI, T->Keyframes[Prev].Time);
				if (Game.IsValid()) Game->SetTimelineTime(T->Keyframes[Prev].Time);
				SelectedCurvePoint = 0;
				RefreshContent();
			}, 44.f, 19.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("下帧 ▶")), [this]
			{
				int32 TI = -1, KI = -1;
				const FOKSceneTimelineTrack* T = ResolveTrack(TI);
				ResolveKeyframe(TI, KI);
				if (!T || T->Keyframes.IsEmpty()) return;
				const int32 Next = FMath::Min(T->Keyframes.Num() - 1, KI + 1);
				if (SetActiveKey) SetActiveKey(TI, T->Keyframes[Next].Time);
				if (Game.IsValid()) Game->SetTimelineTime(T->Keyframes[Next].Time);
				SelectedCurvePoint = 0;
				RefreshContent();
			}, 44.f, 19.f, false, 9.5f)
		]
	];

	// 2. Presets & Copy/Paste row
	static const TCHAR* PresetLabels[] = { TEXT("线性"), TEXT("平滑缓入缓出"), TEXT("快入慢出"), TEXT("慢入快出"), TEXT("阶跃常值"), TEXT("回弹过冲") };
	TSharedRef<SWrapBox> PresetRow = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(2.f, 2.f));
	for (int32 P = 0; P < 6; ++P)
	{
		PresetRow->AddSlot()
		[
			Button(FText::FromString(PresetLabels[P]), [this, P]
			{
				int32 TI = -1, KI = -1;
				if (FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI))
				{
					ApplyPresetToCurve(K->Curve, P);
					SelectedCurvePoint = 0;
					NotifyCurveEdited();
					if (OnStatus) OnStatus(FString::Printf(TEXT("已套用曲线预设：%s"), PresetLabels[P]));
				}
			}, P == 1 ? 74.f : 52.f, 18.f, false, 9.5f)
		];
	}
	PresetRow->AddSlot()
	[
		Button(FText::FromString(TEXT("复制曲线")), [this]
		{
			int32 TI = -1, KI = -1;
			if (FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI))
			{
				SOKStudioCurveCanvas::EnsureDefaultCurve(K->Curve);
				CopiedCurve = K->Curve;
				if (OnStatus) OnStatus(TEXT("已复制当前关键帧 Hermite 曲线"));
			}
		}, 54.f, 18.f, false, 9.5f)
	];
	PresetRow->AddSlot()
	[
		Button(FText::FromString(TEXT("粘贴曲线")), [this]
		{
			int32 TI = -1, KI = -1;
			FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI);
			if (!K || CopiedCurve.Num() < 2) return;
			K->Curve = CopiedCurve;
			SelectedCurvePoint = 0;
			NotifyCurveEdited();
			if (OnStatus) OnStatus(TEXT("已粘贴 Hermite 曲线"));
		}, 54.f, 18.f, false, 9.5f)
	];
	PresetRow->AddSlot()
	[
		Button(FText::FromString(TEXT("套用全轨")), [this]
		{
			int32 TI = -1, KI = -1;
			FOKSceneTimelineTrack* T = ResolveTrack(TI);
			FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI);
			if (!T || !K) return;
			SOKStudioCurveCanvas::EnsureDefaultCurve(K->Curve);
			const TArray<FOKSceneTimelineCurvePt> Src = K->Curve;
			for (FOKSceneTimelineKeyframe& Other : T->Keyframes) Other.Curve = Src;
			NotifyCurveEdited();
			if (OnStatus) OnStatus(FString::Printf(TEXT("已将曲线套用到本轨全部 %d 个关键帧"), T->Keyframes.Num()));
		}, 54.f, 18.f, false, 9.5f)
	];
	Root->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)[PresetRow];

	// 3. Interactive Canvas
	Root->AddSlot().FillHeight(1.f).Padding(0.f, 2.f)
	[
		SNew(SOKStudioCurveCanvas)
		.Game(Game)
		.LockTangentsPtr(&bLockTangents)
		.SelectedPointPtr(&SelectedCurvePoint)
		.GetKeyframe([this]() -> FOKSceneTimelineKeyframe*
		{
			int32 TI = -1, KI = -1;
			return ResolveKeyframe(TI, KI);
		})
		.OnCurveEdited([this] { NotifyCurveEdited(); })
	];

	// 4. Control point & Tangents numeric bar
	auto MakeSpin = [this](TFunction<float()> Get, TFunction<void(float)> Set, float MinV, float MaxV, float DeltaV) -> TSharedRef<SWidget>
	{
		return SNew(SSpinBox<float>).Style(&SpinStyle()).Font(Font(9.5f)).ClearKeyboardFocusOnCommit(true)
			.MinValue(MinV).MaxValue(MaxV).Delta(DeltaV).MaxFractionalDigits(3)
			.Value_Lambda(MoveTemp(Get))
			.OnValueChanged_Lambda([this, Set](float V) { Set(V); NotifyCurveEdited(); });
	};

	Root->AddSlot().AutoHeight().Padding(0.f, 2.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SCheckBox).Style(&CheckStyle())
			.IsChecked_Lambda([this] { return bLockTangents ? ECheckBoxState::Checked : ECheckBoxState::Unchecked; })
			.OnCheckStateChanged_Lambda([this](ECheckBoxState S) { bLockTangents = (S == ECheckBoxState::Checked); })
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(3.f, 0.f, 6.f, 0.f)
		[
			Label(FText::FromString(TEXT("对称切线")), 9.5f)
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("点t")), 9.5f, TextSoft())]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 4.f, 0.f)
		[
			SNew(SBox).WidthOverride(48.f).HeightOverride(18.f)
			[
				MakeSpin(
					[this] { int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI); return K && K->Curve.IsValidIndex(SelectedCurvePoint) ? K->Curve[SelectedCurvePoint].Time : 0.f; },
					[this](float V)
					{
						int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI);
						if (!K || !K->Curve.IsValidIndex(SelectedCurvePoint)) return;
						if (SelectedCurvePoint == 0 || SelectedCurvePoint == K->Curve.Num() - 1) return;
						K->Curve[SelectedCurvePoint].Time = FMath::Clamp(V, K->Curve[SelectedCurvePoint - 1].Time + 0.01f, K->Curve[SelectedCurvePoint + 1].Time - 0.01f);
					}, 0.f, 1.f, 0.01f)
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("值v")), 9.5f, TextSoft())]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 4.f, 0.f)
		[
			SNew(SBox).WidthOverride(48.f).HeightOverride(18.f)
			[
				MakeSpin(
					[this] { int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI); return K && K->Curve.IsValidIndex(SelectedCurvePoint) ? K->Curve[SelectedCurvePoint].Value : 0.f; },
					[this](float V) { int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI); if (K && K->Curve.IsValidIndex(SelectedCurvePoint)) K->Curve[SelectedCurvePoint].Value = V; }, -0.5f, 1.5f, 0.01f)
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("入斜率")), 9.5f, FLinearColor(0.35f, 0.85f, 1.f))]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 4.f, 0.f)
		[
			SNew(SBox).WidthOverride(50.f).HeightOverride(18.f)
			[
				MakeSpin(
					[this] { int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI); return K && K->Curve.IsValidIndex(SelectedCurvePoint) ? K->Curve[SelectedCurvePoint].InTangent : 1.f; },
					[this](float V)
					{
						int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI);
						if (!K || !K->Curve.IsValidIndex(SelectedCurvePoint)) return;
						K->Curve[SelectedCurvePoint].InTangent = V;
						if (bLockTangents) K->Curve[SelectedCurvePoint].OutTangent = V;
					}, -12.f, 12.f, 0.05f)
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("出斜率")), 9.5f, FLinearColor(1.f, 0.65f, 0.25f))]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			SNew(SBox).WidthOverride(50.f).HeightOverride(18.f)
			[
				MakeSpin(
					[this] { int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI); return K && K->Curve.IsValidIndex(SelectedCurvePoint) ? K->Curve[SelectedCurvePoint].OutTangent : 1.f; },
					[this](float V)
					{
						int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI);
						if (!K || !K->Curve.IsValidIndex(SelectedCurvePoint)) return;
						K->Curve[SelectedCurvePoint].OutTangent = V;
						if (bLockTangents) K->Curve[SelectedCurvePoint].InTangent = V;
					}, -12.f, 12.f, 0.05f)
			]
		]
	];

	// 5. Keyframe values fine-tuning row
	if (Kf && !Kf->Values.IsEmpty())
	{
		TSharedRef<SWrapBox> ValRow = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(3.f, 2.f));
		static const TCHAR* CompNames[] = { TEXT("V0/X"), TEXT("V1/Y"), TEXT("V2/Z"), TEXT("V3/W"), TEXT("V4"), TEXT("V5") };
		const int32 ShowNum = FMath::Min(Kf->Values.Num(), 6);
		for (int32 C = 0; C < ShowNum; ++C)
		{
			ValRow->AddSlot()
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 2.f, 0.f)
				[
					Label(FText::FromString(CompNames[C]), 9.f, TextSoft())
				]
				+ SHorizontalBox::Slot().AutoWidth()
				[
					SNew(SBox).WidthOverride(58.f).HeightOverride(18.f)
					[
						MakeSpin(
							[this, C] { int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI); return K && K->Values.IsValidIndex(C) ? K->Values[C] : 0.f; },
							[this, C](float V) { int32 TI, KI; FOKSceneTimelineKeyframe* K = ResolveKeyframe(TI, KI); if (K && K->Values.IsValidIndex(C)) K->Values[C] = V; }, -10000.f, 10000.f, 0.02f)
					]
				]
			];
		}
		Root->AddSlot().AutoHeight().Padding(0.f, 2.f, 0.f, 0.f)[ValRow];
	}

	Root->AddSlot().AutoHeight().Padding(0.f, 2.f, 0.f, 0.f)
	[
		Label(FText::FromString(TEXT("提示：左键拖动控制点与切线手柄；双击空白添加控制点；右键删除中间控制点。")), 8.5f, TextHint())
	];

	ContentHost->SetContent(Root);
}
