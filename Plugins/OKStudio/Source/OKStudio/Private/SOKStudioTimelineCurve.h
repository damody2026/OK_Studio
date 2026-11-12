#pragma once

// OK Studio Timeline Cubic-Hermite Curve Editor window (Timeline.dll [0, 1] curveKeyframe editor + keyframe value inspector).
#include "CoreMinimal.h"
#include "OKStudioGame.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/SLeafWidget.h"

class SOKStudioCurveCanvas : public SLeafWidget
{
public:
	SLATE_BEGIN_ARGS(SOKStudioCurveCanvas) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UOKStudioGame>, Game)
		SLATE_ARGUMENT(TFunction<FOKSceneTimelineKeyframe*()>, GetKeyframe)
		SLATE_ARGUMENT(TFunction<void()>, OnCurveEdited)
		SLATE_ARGUMENT(bool*, LockTangentsPtr)
		SLATE_ARGUMENT(int32*, SelectedPointPtr)
	SLATE_END_ARGS()

	void Construct(const FArguments& Args);
	virtual FVector2D ComputeDesiredSize(float) const override { return FVector2D(360.f, 210.f); }
	virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& Geometry, const FSlateRect& Culling, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const override;
	virtual FReply OnMouseButtonDown(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnMouseButtonDoubleClick(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnMouseMove(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnMouseButtonUp(const FGeometry& Geometry, const FPointerEvent& Event) override;

	static void EnsureDefaultCurve(TArray<FOKSceneTimelineCurvePt>& Curve);

private:
	enum class EDragMode : uint8 { None, Point, InTangent, OutTangent };

	TWeakObjectPtr<UOKStudioGame> Game;
	TFunction<FOKSceneTimelineKeyframe*()> GetKeyframe;
	TFunction<void()> OnCurveEdited;
	bool* LockTangentsPtr = nullptr;
	int32* SelectedPointPtr = nullptr;
	EDragMode DragMode = EDragMode::None;

	static constexpr float PadLeft = 32.f;
	static constexpr float PadRight = 14.f;
	static constexpr float PadTop = 14.f;
	static constexpr float PadBottom = 20.f;
	static constexpr float MinValRange = -0.25f;
	static constexpr float MaxValRange = 1.25f;
	static constexpr float TangentHandleLenPx = 38.f;

	FVector2D CurveToLocal(const FGeometry& G, float T, float V) const;
	void LocalToCurve(const FGeometry& G, const FVector2D& Local, float& OutT, float& OutV) const;
	FVector2D TangentHandleLocal(const FGeometry& G, const FOKSceneTimelineCurvePt& Pt, bool bOut) const;
	int32 SelectedPoint() const { return SelectedPointPtr ? *SelectedPointPtr : 0; }
	void SetSelectedPoint(int32 Idx) { if (SelectedPointPtr) *SelectedPointPtr = Idx; }
};

class SOKStudioTimelineCurve : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SOKStudioTimelineCurve) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UOKStudioGame>, Game)
		SLATE_ARGUMENT(TFunction<bool(int32&, float&)>, GetActiveKey)
		SLATE_ARGUMENT(TFunction<void(int32, float)>, SetActiveKey)
		SLATE_ARGUMENT(TFunction<void(const FString&)>, OnStatus)
	SLATE_END_ARGS()

	void Construct(const FArguments& Args);
	void RefreshContent();

	static void ApplyPresetToCurve(TArray<FOKSceneTimelineCurvePt>& Curve, int32 PresetIndex);

private:
	TWeakObjectPtr<UOKStudioGame> Game;
	TFunction<bool(int32&, float&)> GetActiveKey;
	TFunction<void(int32, float)> SetActiveKey;
	TFunction<void(const FString&)> OnStatus;

	TSharedPtr<SBox> ContentHost;
	int32 SelectedCurvePoint = 0;
	bool bLockTangents = true;
	TArray<FOKSceneTimelineCurvePt> CopiedCurve;

	FOKSceneTimelineTrack* ResolveTrack(int32& OutTrackIdx) const;
	FOKSceneTimelineKeyframe* ResolveKeyframe(int32& OutTrackIdx, int32& OutKeyIdx) const;
	void NotifyCurveEdited();
};
