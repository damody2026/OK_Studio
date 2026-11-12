#pragma once

// OK Studio timeline: time ruler with subdivision grid, play head and loop range; displays both OK Studio object tracks
// (Doc->Tracks) and KK/KKS Timeline.dll continuous cubic-Hermite interpolable tracks (Doc->TimelineTracks) with grouping,
// enable toggles, track color badges, box-selection, drag-move, copy/paste, delete, curve presets, and double-click to
// open the Hermite curve editor.
#include "CoreMinimal.h"
#include "OKStudioGame.h"
#include "Widgets/SLeafWidget.h"

class SOKStudioTimeline : public SLeafWidget
{
public:
	SLATE_BEGIN_ARGS(SOKStudioTimeline) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UOKStudioGame>, Game)
		SLATE_ARGUMENT(TFunction<void(const FVector2D&)>, OnEaseMenu)
		SLATE_ARGUMENT(TFunction<void(int32, float, const FVector2D&)>, OnInterpMenu)
		SLATE_ARGUMENT(TFunction<void(int32, float)>, OnOpenCurve)
		SLATE_ARGUMENT(TFunction<void(int32, float)>, OnSelectInterpKey)
		SLATE_ARGUMENT(TFunction<void(const FString&)>, OnStatus)
	SLATE_END_ARGS()

	/** A key by its track's object (or -10000 - InterpTrack for TimelineTracks) and its time. */
	struct FKeyRef
	{
		int32 Track = 0;
		float Time = 0.f;
		int32 InterpTrack = -1;

		static FKeyRef MakeInterp(int32 Idx, float T)
		{
			FKeyRef R;
			R.Track = -10000 - Idx;
			R.Time = T;
			R.InterpTrack = Idx;
			return R;
		}
		bool IsInterp() const { return InterpTrack >= 0; }
		bool operator==(const FKeyRef& O) const
		{
			return Track == O.Track && InterpTrack == O.InterpTrack && FMath::Abs(Time - O.Time) < 1e-4f;
		}
	};

	void Construct(const FArguments& Args);
	virtual FVector2D ComputeDesiredSize(float) const override { return FVector2D(580.f, 180.f); }
	virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& Geometry, const FSlateRect& Culling, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const override;
	virtual FReply OnMouseButtonDown(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnMouseButtonDoubleClick(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnMouseMove(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnMouseButtonUp(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnMouseWheel(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply OnKeyDown(const FGeometry& Geometry, const FKeyEvent& Event) override;
	virtual bool SupportsKeyboardFocus() const override { return true; }

	TArray<FKeyRef> Selected;
	float SnapFps = 30.f;
	TSet<int32> Open;
	TSet<FString> ClosedInterpGroups;
	int32 FocusedInterpTrack = -1;
	int32 VoiceTrack = -1, VoiceIndex = -1;

	void DeleteSelected();
	void CopySelected();
	void PasteAtPlayhead();
	void SetEase(EOKSceneEase Ease);
	void SetCurvePresetOnSelected(int32 PresetIndex);
	void Scrub(float Time);
	float Snap(float Time) const { return SnapFps > 0.f ? FMath::RoundToFloat(Time * SnapFps) / SnapFps : Time; }
	void KeySelection();
	void KeyInterpolable();

private:
	TWeakObjectPtr<UOKStudioGame> Game;
	TFunction<void(const FVector2D&)> OnEaseMenu;
	TFunction<void(int32, float, const FVector2D&)> OnInterpMenu;
	TFunction<void(int32, float)> OnOpenCurve;
	TFunction<void(int32, float)> OnSelectInterpKey;
	TFunction<void(const FString&)> OnStatus;

	enum class ERowKind : uint8 { SceneTrack, InterpGroup, InterpTrack };
	struct FRowInfo
	{
		ERowKind Kind = ERowKind::SceneTrack;
		int32 Track = 0;
		int32 Sub = -1;
		int32 InterpIndex = -1;
		FString GroupKey;
		FString Label;
	};
	TArray<FRowInfo> RowInfos() const;
	static FString GroupKeyForInterp(const UOKSceneDocument* Doc, const FOKSceneTimelineTrack& Tr);

	/** Clipboard for Doc->Tracks and Doc->TimelineTracks. */
	TArray<TPair<int32, FOKSceneKey>> Clip;
	TArray<TPair<int32, FOKSceneTimelineKeyframe>> InterpClip;

	enum class EDrag : uint8 { None, Scrub, Keys, Box, Voice } Drag = EDrag::None;
	FVector2D DragFrom = FVector2D::ZeroVector, DragNow = FVector2D::ZeroVector;
	float DragTimeFrom = 0.f;
	float Zoom = 1.f, Scroll = 0.f;
	int32 RowScroll = 0;
	static constexpr float LabelWidth = 160.f, RulerHeight = 16.f, RowHeight = 16.f;

	float TimeToX(const FGeometry& G, float Time) const;
	float XToTime(const FGeometry& G, float X) const;
	bool HitKey(const FGeometry& G, const FVector2D& Local, FKeyRef& Out) const;
	bool HitVoice(const FGeometry& G, const FVector2D& Local, int32& OutTrack, int32& OutIndex) const;
	bool SubHasKey(int32 Sub, const FOKSceneKey& K, const FOKSceneObject* O) const;
};
