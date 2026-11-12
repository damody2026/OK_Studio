#include "SOKStudioVngePanels.h"
#include "OKStudioStyle.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Engine/Texture2D.h"
#include "Engine/World.h"
#include "Fonts/FontMeasure.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/PlayerController.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "Misc/Paths.h"
#include "Rendering/DrawElements.h"
#include "Widgets/Images/SImage.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Input/SSpinBox.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SSpacer.h"
#include "Widgets/Layout/SWrapBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SOverlay.h"
#include "Widgets/Text/STextBlock.h"

namespace
{
	const TCHAR* PoseCategoryLabel(const FString& Cat)
	{
		if (Cat.Equals(TEXT("ffaces"), ESearchCase::IgnoreCase)) return TEXT("女表情 ffaces");
		if (Cat.Equals(TEXT("fposes"), ESearchCase::IgnoreCase)) return TEXT("女姿势 fposes");
		if (Cat.Equals(TEXT("fstatus"), ESearchCase::IgnoreCase)) return TEXT("女状态 fstatus");
		if (Cat.Equals(TEXT("lhand"), ESearchCase::IgnoreCase)) return TEXT("左手 lhand");
		if (Cat.Equals(TEXT("rhand"), ESearchCase::IgnoreCase)) return TEXT("右手 rhand");
		if (Cat.Equals(TEXT("mfaces"), ESearchCase::IgnoreCase)) return TEXT("男表情 mfaces");
		if (Cat.Equals(TEXT("mposes"), ESearchCase::IgnoreCase)) return TEXT("男姿势 mposes");
		if (Cat.Equals(TEXT("mstatus"), ESearchCase::IgnoreCase)) return TEXT("男状态 mstatus");
		if (Cat.Equals(TEXT("vnacharpose"), ESearchCase::IgnoreCase)) return TEXT("演员姿 vnacharpose");
		if (Cat.Equals(TEXT("vnachar"), ESearchCase::IgnoreCase)) return TEXT("演员全态 vnachar");
		if (Cat.Equals(TEXT("propfk"), ESearchCase::IgnoreCase)) return TEXT("道具FK propfk");
		if (Cat.Equals(TEXT("propvnanime"), ESearchCase::IgnoreCase)) return TEXT("道具动画 propvnanime");
		if (Cat.Equals(TEXT("xxpelib"), ESearchCase::IgnoreCase)) return TEXT("骨骼扩展 xxpelib");
		if (Cat.Equals(TEXT("posef"), ESearchCase::IgnoreCase)) return TEXT("女姿 posef");
		if (Cat.Equals(TEXT("posem"), ESearchCase::IgnoreCase)) return TEXT("男姿 posem");
		if (Cat.Equals(TEXT("face"), ESearchCase::IgnoreCase)) return TEXT("表情 face");
		if (Cat.Equals(TEXT("cam"), ESearchCase::IgnoreCase)) return TEXT("镜头 cam");
		return *Cat;
	}

	TSharedRef<SWidget> SectionBanner(const FString& Title)
	{
		using namespace OKStudioStyle;
		return SNew(SBorder).BorderImage(Brush(FLinearColor(0.11f, 0.23f, 0.40f, 0.95f))).Padding(FMargin(6.f, 3.f))
			[Label(FText::FromString(Title), 10.5f, FLinearColor(0.92f, 0.97f, 1.f))];
	}

	TSharedRef<SWidget> VngeSpin(TFunction<float()> Get, TFunction<void(float)> Set, float MinV, float MaxV, float DeltaV)
	{
		using namespace OKStudioStyle;
		return SNew(SSpinBox<float>).Style(&SpinStyle()).Font(Font(9.5f)).ClearKeyboardFocusOnCommit(true)
			.MinValue(MinV).MaxValue(MaxV).Delta(DeltaV).MaxFractionalDigits(3)
			.Value_Lambda(MoveTemp(Get))
			.OnValueChanged_Lambda([Set, MinV, MaxV](float V) { Set(FMath::Clamp(V, MinV, MaxV)); });
	}

	TSharedRef<SWidget> VngeCheck(const FString& Name, TFunction<bool()> Get, TFunction<void(bool)> Set)
	{
		using namespace OKStudioStyle;
		return SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(SCheckBox).Style(&CheckStyle())
				.IsChecked_Lambda([Get] { return Get() ? ECheckBoxState::Checked : ECheckBoxState::Unchecked; })
				.OnCheckStateChanged_Lambda([Set](ECheckBoxState S) { Set(S == ECheckBoxState::Checked); })
			]
			+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center).Padding(4.f, 0.f, 0.f, 0.f)
			[
				SNew(SButton).ButtonStyle(&FlatButton()).ContentPadding(FMargin(0.f))
				.OnClicked_Lambda([Get, Set] { Set(!Get()); return FReply::Handled(); })
				[SNew(STextBlock).Text(FText::FromString(Name)).Font(Font(9.5f)).ColorAndOpacity(Text()).AutoWrapText(true)]
			];
	}

	TSharedRef<SWidget> VngeRow(const FString& Name, const TSharedRef<SWidget>& Control, float NameRatio = 0.34f)
	{
		using namespace OKStudioStyle;
		return SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(NameRatio).VAlign(VAlign_Center)[Label(FText::FromString(Name), 9.5f, TextSoft())]
			+ SHorizontalBox::Slot().FillWidth(1.f - NameRatio)[SNew(SBox).HeightOverride(19.f)[Control]];
	}
}

// --- SOKStudioVngeOverlay ---

void SOKStudioVngeOverlay::Construct(const FArguments& Args)
{
	using namespace OKStudioStyle;
	Game = Args._Game;
	IsUiHidden = Args._IsUiHidden;
	OnScriptUpdated = Args._OnScriptUpdated;
	SetVisibility(EVisibility::SelfHitTestInvisible);

	ChildSlot
	[
		SNew(SVerticalBox).Visibility(EVisibility::SelfHitTestInvisible)
		+ SVerticalBox::Slot().FillHeight(1.f)[SNew(SSpacer).Visibility(EVisibility::SelfHitTestInvisible)]
		+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center).Padding(0.f, 0.f, 0.f, 68.f)
		[
			SNew(SBox).WidthOverride(680.f)
			.Visibility_Lambda([this]
			{
				if (!Game.IsValid()) return EVisibility::Collapsed;
				const FOKStudioVngeRuntime* V = Game->GetVnge();
				if (!V || !V->bShowDialogueOverlay) return EVisibility::Collapsed;
				const bool bAny = !V->ActiveWhoSay.IsEmpty() || !V->ActiveWhatSay.IsEmpty() || !V->ActiveChoices.IsEmpty();
				return bAny ? EVisibility::Visible : EVisibility::Collapsed;
			})
			[
				SNew(SBorder).BorderImage(Brush(FLinearColor(0.04f, 0.08f, 0.16f, 0.90f))).Padding(FMargin(14.f, 10.f))
				[
					SNew(SVerticalBox)
					+ SVerticalBox::Slot().AutoHeight()
					[
						SNew(SHorizontalBox)
						+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
						[
							SNew(STextBlock).Font(Font(13.f)).ColorAndOpacity(FLinearColor(1.f, 0.88f, 0.38f, 1.f))
							.Text_Lambda([this]
							{
								const FOKStudioVngeRuntime* V = Game.IsValid() ? Game->GetVnge() : nullptr;
								return FText::FromString(V && !V->ActiveWhoSay.IsEmpty() ? V->ActiveWhoSay : FString(TEXT("旁白")));
							})
						]
						+ SHorizontalBox::Slot().AutoWidth().Padding(4.f, 0.f)
						[
							Button(FText::FromString(TEXT("下一步 ▶")), [this]
							{
								if (!Game.IsValid()) return;
								Game->Vnge().StepScriptNext();
								RebuildChoicesIfNeeded();
								if (OnScriptUpdated) OnScriptUpdated();
							}, 68.f, 20.f, false, 9.5f)
						]
						+ SHorizontalBox::Slot().AutoWidth()
						[
							Button(FText::FromString(TEXT("关闭 ×")), [this]
							{
								if (!Game.IsValid()) return;
								Game->Vnge().ClearDialogue();
								RebuildChoicesIfNeeded();
								if (OnScriptUpdated) OnScriptUpdated();
							}, 50.f, 20.f, false, 9.5f, Input())
						]
					]
					+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f, 0.f, 4.f)
					[
						SNew(STextBlock).Font(Font(12.f)).ColorAndOpacity(FLinearColor::White).AutoWrapText(true)
						.Text_Lambda([this]
						{
							const_cast<SOKStudioVngeOverlay*>(this)->RebuildChoicesIfNeeded();
							const FOKStudioVngeRuntime* V = Game.IsValid() ? Game->GetVnge() : nullptr;
							return FText::FromString(V ? V->ActiveWhatSay : FString());
						})
					]
					+ SVerticalBox::Slot().AutoHeight()
					[
						SAssignNew(ChoicesBox, SVerticalBox)
					]
				]
			]
		]
	];
}

void SOKStudioVngeOverlay::RebuildChoicesIfNeeded()
{
	using namespace OKStudioStyle;
	if (!ChoicesBox.IsValid() || !Game.IsValid()) return;
	const FOKStudioVngeRuntime* V = Game->GetVnge();
	FString Sig;
	if (V)
	{
		for (const TPair<FString, FString>& C : V->ActiveChoices) Sig += C.Key + TEXT("->") + C.Value + TEXT("|");
	}
	if (Sig == LastChoicesSignature) return;
	LastChoicesSignature = Sig;
	ChoicesBox->ClearChildren();
	if (!V) return;
	for (const TPair<FString, FString>& Choice : V->ActiveChoices)
	{
		const FString TargetBlock = Choice.Value;
		ChoicesBox->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			Button(FText::FromString(TEXT("◆ ") + Choice.Key), [this, TargetBlock]
			{
				if (!Game.IsValid()) return;
				if (Game->Vnge().JumpScriptBlock(TargetBlock)) Game->Vnge().StepScriptNext();
				RebuildChoicesIfNeeded();
				if (OnScriptUpdated) OnScriptUpdated();
			}, 0.f, 22.f, false, 10.5f)
		];
	}
}

int32 SOKStudioVngeOverlay::OnPaint(const FPaintArgs& Args, const FGeometry& G, const FSlateRect& Culling, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const
{
	using namespace OKStudioStyle;
	int32 NextLayer = SCompoundWidget::OnPaint(Args, G, Culling, Out, Layer, Style, bParentEnabled);
	if (!Game.IsValid() || !Game->Document) return NextLayer;
	const FOKStudioVngeRuntime* V = Game->GetVnge();
	if (!V || !V->bShowTextOverlay || Game->Document->Vnge.Texts.IsEmpty()) return NextLayer;

	const FVector2D LocalSize = G.GetLocalSize();
	if (LocalSize.X < 10.f || LocalSize.Y < 10.f) return NextLayer;

	UWorld* World = Game->GetTickableGameObjectWorld();
	APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
	FVector2D ViewportPixels = LocalSize;
	if (GEngine && GEngine->GameViewport) GEngine->GameViewport->GetViewportSize(ViewportPixels);
	if (ViewportPixels.X < 1.f || ViewportPixels.Y < 1.f) ViewportPixels = LocalSize;

	const TSharedRef<FSlateFontMeasure> FontMeasure = FSlateApplication::Get().GetRenderer()->GetFontMeasureService();

	for (const FOKVngeTextEntry& Entry : Game->Document->Vnge.Texts)
	{
		if (!Entry.bVisible || Entry.Text.IsEmpty()) continue;
		if (Entry.bParentHide && Entry.ObjectId >= 0 && !Game->Document->IsShown(Entry.ObjectId)) continue;

		const FSlateFontInfo TextFont = Font(FMath::Clamp(Entry.Size, 8.f, 160.f));
		const FVector2D Measured = FontMeasure->Measure(Entry.Text, TextFont);
		FVector2D DrawAt = LocalSize * 0.5;

		if (Entry.bIs3D)
		{
			if (!PC) continue;
			FVector WorldPos;
			if (Entry.ObjectId >= 0 && Game->Document->Find(Entry.ObjectId))
			{
				WorldPos = Game->Document->WorldTransform(Entry.ObjectId).GetLocation()
					+ FVector(Entry.Position.Z * 100.f, Entry.Position.X * 100.f, Entry.Position.Y * 100.f);
			}
			else
			{
				WorldPos = FVector(Entry.Position.Z * 100.f, Entry.Position.X * 100.f, Entry.Position.Y * 100.f);
			}
			FVector2D ScreenPx = FVector2D::ZeroVector;
			if (!PC->ProjectWorldLocationToScreen(WorldPos, ScreenPx, true)) continue;
			DrawAt = FVector2D(ScreenPx.X / ViewportPixels.X * LocalSize.X, ScreenPx.Y / ViewportPixels.Y * LocalSize.Y);
			DrawAt -= Measured * 0.5;
		}
		else
		{
			const int32 Col = FMath::Clamp(Entry.Anchor, 0, 8) % 3;
			const int32 Row = FMath::Clamp(Entry.Anchor, 0, 8) / 3;
			const double BaseX = Col == 0 ? 24.0 : (Col == 1 ? LocalSize.X * 0.5 : LocalSize.X - 24.0);
			const double BaseY = Row == 0 ? 24.0 : (Row == 1 ? LocalSize.Y * 0.5 : LocalSize.Y - 24.0);

			// Entry.Position X/Y can be normalized (-1..1) or canvas pixel offsets
			double OffX = Entry.Position.X;
			double OffY = -Entry.Position.Y;
			if (FMath::Abs(Entry.Position.X) <= 1.5f && FMath::Abs(Entry.Position.Y) <= 1.5f && (FMath::Abs(Entry.Position.X) > 0.001f || FMath::Abs(Entry.Position.Y) > 0.001f))
			{
				OffX = Entry.Position.X * LocalSize.X * 0.5;
				OffY = -Entry.Position.Y * LocalSize.Y * 0.5;
			}
			DrawAt = FVector2D(BaseX + OffX, BaseY + OffY);
			if (Col == 1 || Entry.Alignment == 1) DrawAt.X -= Measured.X * 0.5;
			else if (Col == 2 || Entry.Alignment == 2) DrawAt.X -= Measured.X;
			if (Row == 1) DrawAt.Y -= Measured.Y * 0.5;
			else if (Row == 2) DrawAt.Y -= Measured.Y;
		}

		if (Entry.BgColor.A > 0.01f)
		{
			FSlateDrawElement::MakeBox(
				Out, NextLayer,
				G.ToPaintGeometry(FVector2f(float(Measured.X) + 12.f, float(Measured.Y) + 6.f), FSlateLayoutTransform(FVector2f(float(DrawAt.X) - 6.f, float(DrawAt.Y) - 3.f))),
				Brush(Entry.BgColor), ESlateDrawEffect::None, Entry.BgColor);
		}

		const float Spread = FMath::Clamp(Entry.OutlineSpread, 0.f, 6.f);
		if (Spread > 0.05f && Entry.OutlineColor.A > 0.01f)
		{
			const FVector2f Offsets[4] = { { -Spread, 0.f }, { Spread, 0.f }, { 0.f, -Spread }, { 0.f, Spread } };
			for (const FVector2f& Off : Offsets)
			{
				FSlateDrawElement::MakeText(
					Out, NextLayer + 1,
					G.ToPaintGeometry(FVector2f(float(Measured.X) + 8.f, float(Measured.Y) + 4.f), FSlateLayoutTransform(FVector2f(float(DrawAt.X) + Off.X, float(DrawAt.Y) + Off.Y))),
					Entry.Text, TextFont, ESlateDrawEffect::None, Entry.OutlineColor);
			}
		}

		FSlateDrawElement::MakeText(
			Out, NextLayer + 2,
			G.ToPaintGeometry(FVector2f(float(Measured.X) + 8.f, float(Measured.Y) + 4.f), FSlateLayoutTransform(FVector2f(float(DrawAt.X), float(DrawAt.Y)))),
			Entry.Text, TextFont, ESlateDrawEffect::None, Entry.Color);
	}

	return NextLayer + 3;
}

// --- FOKStudioVngeUi ---

void FOKStudioVngeUi::RefreshAllOpenVngeWindows()
{
	static const TCHAR* Ids[] = {
		TEXT("vnge_hub"), TEXT("vnge_sss"), TEXT("vnge_poselib"), TEXT("vnge_anime"),
		TEXT("vnge_text"), TEXT("vnge_sound"), TEXT("vnge_physics"), TEXT("vnge_utils"), TEXT("vnge_script")
	};
	for (const TCHAR* Id : Ids) DeferWin(Id);
}

const FSlateBrush* FOKStudioVngeUi::BrushForPreset(const FString& FullPath)
{
	if (const TSharedPtr<FSlateBrush>* Found = ThumbBrushes.Find(FullPath)) return Found->Get();
	if (!Game.IsValid()) return nullptr;
	UTexture2D* Tex = Game->Vnge().GetPresetThumbnail(FullPath);
	if (!Tex) return nullptr;
	TSharedPtr<FSlateBrush> B = MakeShared<FSlateBrush>();
	B->SetResourceObject(Tex);
	B->ImageSize = FVector2D(52.f, 52.f);
	ThumbBrushes.Add(FullPath, B);
	return B.Get();
}

int32 FOKStudioVngeUi::TargetCharacterId() const
{
	if (!Game.IsValid() || !Game->Document) return -1;
	if (const FOKSceneObject* Sel = Game->Document->Find(Game->SelectedId); Sel && Sel->Kind == EOKSceneObjectKind::Character)
		return Sel->Id;
	for (const FOKSceneObject& O : Game->Document->Objects)
		if (O.Kind == EOKSceneObjectKind::Character) return O.Id;
	return -1;
}

// 1. VNGE Hub
TSharedRef<SWidget> FOKStudioVngeUi::BuildHub()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid() || !Game->Document) return Body;
	const FOKSceneVngeData& V = Game->Document->Vnge;

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 4.f)[SectionBanner(TEXT("当前场景 VNGE 数据概览"))];
	Body->AddSlot().AutoHeight().Padding(2.f, 2.f, 2.f, 6.f)
	[
		SNew(SBorder).BorderImage(Brush(ListArea())).Padding(6.f)
		[
			SNew(STextBlock).Font(Font(10.f)).ColorAndOpacity(Text()).AutoWrapText(true)
			.Text_Lambda([this]
			{
				if (!Game.IsValid() || !Game->Document) return FText::GetEmpty();
				const FOKSceneVngeData& D = Game->Document->Vnge;
				return FText::FromString(FString::Printf(
					TEXT("SSS 幕状态：%d 幕　｜　镜头机位：%d 个　｜　微状态：%d 项\n")
					TEXT("注册演员：%d 名 / 道具：%d 件　｜　VNAnime 剪辑：%d 段\n")
					TEXT("字幕/3D文字：%d 条　｜　场景音源：%d 个　｜　物理规则：%d 条　｜　VNSS 剧本：%d 块"),
					D.Sss.States.Num(), D.Sss.Cameras.Num(), D.Sss.Ministates.Num(),
					D.Registry.Actors.Num(), D.Registry.Props.Num(), D.Clips.Num(),
					D.Texts.Num(), D.Sounds.Num(), D.Physics.Rules.Num(), D.Script.Blocks.Num()));
			})
		]
	];

	// Quick transport for SSS & VNSS
	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 4.f)[SectionBanner(TEXT("快捷导演操作"))];
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("自动注册演员/道具")), [this]
			{
				if (!Game.IsValid()) return;
				const int32 N = Game->Vnge().AutoRegisterSceneTags();
				MarkChanged();
				Status(FString::Printf(TEXT("已自动注册 %d 个场景演员与道具标签"), N));
				RefreshAllOpenVngeWindows();
			}, 0.f, 22.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().FillWidth(0.8f).Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("◀ 上一幕")), [this]
			{
				if (!Game.IsValid() || Game->Document->Vnge.Sss.States.IsEmpty()) return;
				const int32 Cur = Game->Document->Vnge.Sss.ActiveStateIndex;
				const int32 Prev = FMath::Clamp(Cur <= 0 ? 0 : Cur - 1, 0, Game->Document->Vnge.Sss.States.Num() - 1);
				if (Game->Vnge().ApplySssState(Prev, true)) Status(FString::Printf(TEXT("已切换到第 %d 幕"), Prev + 1));
				RefreshAllOpenVngeWindows();
			}, 0.f, 22.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().FillWidth(0.8f).Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("下一幕 ▶")), [this]
			{
				if (!Game.IsValid() || Game->Document->Vnge.Sss.States.IsEmpty()) return;
				const int32 Cur = Game->Document->Vnge.Sss.ActiveStateIndex;
				const int32 Next = FMath::Clamp(Cur + 1, 0, Game->Document->Vnge.Sss.States.Num() - 1);
				if (Game->Vnge().ApplySssState(Next, true)) Status(FString::Printf(TEXT("已切换到第 %d 幕"), Next + 1));
				RefreshAllOpenVngeWindows();
			}, 0.f, 22.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().FillWidth(0.9f)
		[
			Button(FText::FromString(TEXT("剧本下一步 ▶")), [this]
			{
				if (!Game.IsValid()) return;
				if (!Game->Vnge().StepScriptNext()) Status(TEXT("当前无更多剧本行"));
				RefreshAllOpenVngeWindows();
			}, 0.f, 22.f, false, 9.5f)
		]
	];

	Body->AddSlot().AutoHeight().Padding(0.f, 6.f, 0.f, 4.f)[SectionBanner(TEXT("打开 VNGE 专项功能面板"))];

	struct FEntry { const TCHAR* WinId; FString Title; };
	const TArray<FEntry> Modules = {
		{ TEXT("vnge_sss"), FString::Printf(TEXT("1. 幕状态与镜头 (SSS) [%d幕/%d镜]"), V.Sss.States.Num(), V.Sss.Cameras.Num()) },
		{ TEXT("vnge_poselib"), TEXT("2. 姿势与表情预设库 (PoseLib 13分类)") },
		{ TEXT("vnge_anime"), FString::Printf(TEXT("3. 关键帧剪辑 (VNAnime / KFA) [%d段]"), V.Clips.Num()) },
		{ TEXT("vnge_text"), FString::Printf(TEXT("4. 字幕与 3D 空间文字 (VNText) [%d条]"), V.Texts.Num()) },
		{ TEXT("vnge_sound"), FString::Printf(TEXT("5. 场景音效与口型驱动 (VNSound) [%d个]"), V.Sounds.Num()) },
		{ TEXT("vnge_physics"), FString::Printf(TEXT("6. 物理与接触距离触发 (VNPhysics) [%d条]"), V.Physics.Rules.Num()) },
		{ TEXT("vnge_utils"), TEXT("7. 场景工具与角色状态复制粘贴") },
		{ TEXT("vnge_script"), FString::Printf(TEXT("8. 视觉小说剧本导演 (VNSS) [%d块]"), V.Script.Blocks.Num()) },
	};

	TSharedRef<SVerticalBox> Grid = SNew(SVerticalBox);
	for (int32 I = 0; I < Modules.Num(); I += 2)
	{
		TSharedRef<SHorizontalBox> Row = SNew(SHorizontalBox);
		for (int32 J = 0; J < 2 && I + J < Modules.Num(); ++J)
		{
			const FString WId = Modules[I + J].WinId;
			Row->AddSlot().FillWidth(1.f).Padding(J == 0 ? FMargin(0.f, 0.f, 3.f, 0.f) : FMargin(0.f))
			[
				Button(FText::FromString(Modules[I + J].Title), [this, WId] { if (OnOpenWindow) OnOpenWindow(WId); }, 0.f, 28.f, false, 9.8f)
			];
		}
		Grid->AddSlot().AutoHeight().Padding(0.f, 2.f)[Row];
	}
	Body->AddSlot().AutoHeight()[Grid];

	Body->AddSlot().AutoHeight().Padding(0.f, 6.f, 0.f, 0.f)
	[
		Button(FText::FromString(TEXT("■ 停止所有播放中的 VNAnime 剪辑与场景音效")), [this]
		{
			if (!Game.IsValid()) return;
			Game->Vnge().StopAllClips();
			Game->Vnge().StopAllSounds();
			Status(TEXT("已停止所有 VNGE 剪辑与音效"));
			RefreshAllOpenVngeWindows();
		}, 0.f, 22.f, false, 9.5f, Input())
	];

	return SNew(SScrollBox).ScrollBarThickness(FVector2D(4.f, 4.f)) + SScrollBox::Slot().Padding(4.f)[Body];
}

// 2. VNGE SSS
TSharedRef<SWidget> FOKStudioVngeUi::BuildSss()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid() || !Game->Document) return Body;
	FOKVngeSssData& Sss = Game->Document->Vnge.Sss;

	static const TCHAR* TabNames[] = { TEXT("幕状态"), TEXT("镜头机位"), TEXT("演员/道具标签"), TEXT("微状态与SSSB") };
	TSharedRef<SHorizontalBox> Tabs = SNew(SHorizontalBox);
	for (int32 T = 0; T < 4; ++T)
	{
		Tabs->AddSlot().FillWidth(1.f).Padding(0.f, 0.f, T < 3 ? 2.f : 0.f, 0.f)
		[
			Button(FText::FromString(TabNames[T]), [this, T] { SssTab = T; DeferWin(TEXT("vnge_sss")); }, 0.f, 20.f, SssTab == T, 9.5f)
		];
	}
	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 4.f)[Tabs];

	if (SssTab == 0)
	{
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
			[
				VngeCheck(TEXT("切幕时平滑运镜"), [this] { return bSssSmoothCam; }, [this](bool B) { bSssSmoothCam = B; })
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(4.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("运镜(秒)")), 9.5f)]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				SNew(SBox).WidthOverride(52.f).HeightOverride(18.f)
				[
					VngeSpin(
						[this] { return Game.IsValid() ? Game->Document->Vnge.Sss.CameraTransitionSeconds : 0.5f; },
						[this](float V) { if (Game.IsValid()) { Game->Document->Vnge.Sss.CameraTransitionSeconds = V; MarkChanged(); } }, 0.f, 10.f, 0.05f)
				]
			]
		];

		TSharedRef<SVerticalBox> ListBox = SNew(SVerticalBox);
		for (int32 I = 0; I < Sss.States.Num(); ++I)
		{
			const FOKVngeSceneState& St = Sss.States[I];
			const FString Title = FString::Printf(TEXT("#%d [%s] %s%s（角色%d/道具%d）"),
				I + 1, St.Id.IsEmpty() ? TEXT("幕") : *St.Id,
				St.WhoSay.IsEmpty() ? TEXT("") : *(St.WhoSay + TEXT("：")),
				*St.WhatSay.Left(24), St.Actors.Num(), St.Props.Num());
			ListBox->AddSlot().AutoHeight().Padding(0.f, 1.f)
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().FillWidth(1.f)
				[
					Button(FText::FromString(Title), [this, I]
					{
						if (Game.IsValid() && Game->Vnge().ApplySssState(I, bSssSmoothCam))
						{
							Status(FString::Printf(TEXT("已应用 SSS 第 %d 幕"), I + 1));
							DeferWin(TEXT("vnge_sss"));
						}
					}, 0.f, 21.f, Sss.ActiveStateIndex == I, 9.5f)
				]
				+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 0.f, 0.f)
				[
					Button(FText::FromString(TEXT("删")), [this, I]
					{
						if (Game.IsValid() && Game->Vnge().DeleteSssState(I))
						{
							MarkChanged();
							Status(TEXT("已删除幕状态"));
							DeferWin(TEXT("vnge_sss"));
						}
					}, 28.f, 21.f, false, 9.f, Input())
				]
			];
		}
		if (Sss.States.IsEmpty())
		{
			ListBox->AddSlot().AutoHeight().Padding(4.f)[Label(FText::FromString(TEXT("暂无 SSS 幕状态，可在下方将当前场景姿态与机位捕获为新幕。")), 9.5f, TextHint())];
		}
		Body->AddSlot().FillHeight(1.f).Padding(0.f, 3.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[ListBox]]];

		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)[SectionBanner(TEXT("捕获当前场景为新幕"))];
		Body->AddSlot().AutoHeight().Padding(0.f, 1.f)[VngeRow(TEXT("幕代号 ID"), SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("可留空自动编号"))).Text_Lambda([this] { return FText::FromString(NewStateId); }).OnTextChanged_Lambda([this](const FText& T) { NewStateId = T.ToString(); }))];
		Body->AddSlot().AutoHeight().Padding(0.f, 1.f)[VngeRow(TEXT("说话人"), SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("可选：台词角色名"))).Text_Lambda([this] { return FText::FromString(NewWhoSay); }).OnTextChanged_Lambda([this](const FText& T) { NewWhoSay = T.ToString(); }))];
		Body->AddSlot().AutoHeight().Padding(0.f, 1.f)[VngeRow(TEXT("台词内容"), SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("可选：切到此幕显示的台词"))).Text_Lambda([this] { return FText::FromString(NewWhatSay); }).OnTextChanged_Lambda([this](const FText& T) { NewWhatSay = T.ToString(); }))];
		Body->AddSlot().AutoHeight().Padding(0.f, 3.f, 0.f, 0.f)
		[
			Button(FText::FromString(TEXT("+ 捕获当前角色/道具/镜头为新幕")), [this]
			{
				if (!Game.IsValid()) return;
				const int32 Idx = Game->Vnge().CaptureCurrentSssState(NewStateId, NewWhoSay, NewWhatSay);
				if (Idx >= 0)
				{
					MarkChanged();
					Status(FString::Printf(TEXT("已捕获保存为第 %d 幕"), Idx + 1));
					DeferWin(TEXT("vnge_sss"));
					DeferWin(TEXT("vnge_hub"));
				}
			}, 0.f, 23.f, false, 10.f, On())
		];
	}
	else if (SssTab == 1)
	{
		TSharedRef<SVerticalBox> ListBox = SNew(SVerticalBox);
		for (int32 I = 0; I < Sss.Cameras.Num(); ++I)
		{
			const FOKVngeCameraSlot& Cam = Sss.Cameras[I];
			const FString Title = FString::Printf(TEXT("机位 #%d (FOV %.1f°) %s %s"),
				Cam.Slot, Cam.Fov, *Cam.WhoSay, *Cam.WhatSay.Left(20));
			ListBox->AddSlot().AutoHeight().Padding(0.f, 1.f)
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().FillWidth(1.f)
				[
					Button(FText::FromString(Title), [this, I]
					{
						if (Game.IsValid() && Game->Vnge().ApplySssCamera(I, bSssSmoothCam ? -1.f : 0.f))
						{
							Status(FString::Printf(TEXT("已切换到 SSS 机位 #%d"), I + 1));
							DeferWin(TEXT("vnge_sss"));
						}
					}, 0.f, 21.f, Sss.ActiveCameraSlot == I, 9.5f)
				]
				+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 0.f, 0.f)
				[
					Button(FText::FromString(TEXT("删")), [this, I]
					{
						if (Game.IsValid() && Game->Vnge().DeleteSssCamera(I))
						{
							MarkChanged();
							DeferWin(TEXT("vnge_sss"));
						}
					}, 28.f, 21.f, false, 9.f, Input())
				]
			];
		}
		if (Sss.Cameras.IsEmpty())
		{
			ListBox->AddSlot().AutoHeight().Padding(4.f)[Label(FText::FromString(TEXT("暂无保存的 SSS 镜头机位。")), 9.5f, TextHint())];
		}
		Body->AddSlot().FillHeight(1.f).Padding(0.f, 3.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[ListBox]]];
		Body->AddSlot().AutoHeight().Padding(0.f, 3.f, 0.f, 0.f)
		[
			Button(FText::FromString(TEXT("+ 捕获当前自由视角为新机位")), [this]
			{
				if (!Game.IsValid()) return;
				const int32 Idx = Game->Vnge().CaptureCurrentSssCamera(NewWhoSay, NewWhatSay);
				if (Idx >= 0)
				{
					MarkChanged();
					Status(FString::Printf(TEXT("已保存 SSS 镜头机位 #%d"), Idx + 1));
					DeferWin(TEXT("vnge_sss"));
					DeferWin(TEXT("vnge_hub"));
				}
			}, 0.f, 23.f, false, 10.f, On())
		];
	}
	else if (SssTab == 2)
	{
		FOKVngeRegistry& Reg = Game->Document->Vnge.Registry;
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			Button(FText::FromString(TEXT("自动扫描并注册全场角色与顶层道具")), [this]
			{
				if (!Game.IsValid()) return;
				const int32 N = Game->Vnge().AutoRegisterSceneTags();
				MarkChanged();
				Status(FString::Printf(TEXT("已注册 %d 个标签"), N));
				DeferWin(TEXT("vnge_sss"));
			}, 0.f, 22.f, false, 9.5f)
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				SNew(SBox).HeightOverride(20.f)
				[
					SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("为当前选中对象设置代号（如 f1 / desk）")))
					.Text_Lambda([this] { return FText::FromString(NewTagAlias); })
					.OnTextChanged_Lambda([this](const FText& T) { NewTagAlias = T.ToString(); })
				]
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(TEXT("设为演员")), [this]
				{
					if (!Game.IsValid() || Game->SelectedId < 0) { Status(TEXT("请先在大纲选择对象")); return; }
					if (Game->Vnge().SetObjectTag(Game->SelectedId, NewTagAlias, false))
					{
						MarkChanged();
						DeferWin(TEXT("vnge_sss"));
					}
				}, 58.f, 20.f, false, 9.5f)
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				Button(FText::FromString(TEXT("设为道具")), [this]
				{
					if (!Game.IsValid() || Game->SelectedId < 0) { Status(TEXT("请先在大纲选择对象")); return; }
					if (Game->Vnge().SetObjectTag(Game->SelectedId, NewTagAlias, true))
					{
						MarkChanged();
						DeferWin(TEXT("vnge_sss"));
					}
				}, 58.f, 20.f, false, 9.5f)
			]
		];

		TSharedRef<SVerticalBox> TagList = SNew(SVerticalBox);
		auto AppendTags = [&](const TArray<FOKVngeActorTag>& Arr, bool bProp)
		{
			for (const FOKVngeActorTag& Tag : Arr)
			{
				const FOKSceneObject* Obj = Game->Document->Find(Tag.ObjectId);
				const FString AliasCopy = Tag.Alias;
				const int32 ObjId = Tag.ObjectId;
				TagList->AddSlot().AutoHeight().Padding(0.f, 1.f)
				[
					SNew(SHorizontalBox)
					+ SHorizontalBox::Slot().FillWidth(1.f)
					[
						Button(FText::FromString(FString::Printf(TEXT("[%s] %s → #%d %s"),
							bProp ? TEXT("道具") : TEXT("演员"), *Tag.Alias, ObjId, Obj ? *Obj->Name : TEXT("（未绑定）"))),
							[this, ObjId] { if (Game.IsValid() && ObjId >= 0) Game->Select(ObjId); }, 0.f, 20.f, false, 9.5f)
					]
					+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 0.f, 0.f)
					[
						Button(FText::FromString(TEXT("移除")), [this, AliasCopy, bProp]
						{
							if (Game.IsValid() && Game->Vnge().RemoveObjectTag(AliasCopy, bProp))
							{
								MarkChanged();
								DeferWin(TEXT("vnge_sss"));
							}
						}, 38.f, 20.f, false, 9.f, Input())
					]
				];
			}
		};
		AppendTags(Reg.Actors, false);
		AppendTags(Reg.Props, true);
		Body->AddSlot().FillHeight(1.f).Padding(0.f, 3.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[TagList]]];
	}
	else
	{
		TSharedRef<SVerticalBox> MiniBox = SNew(SVerticalBox);
		for (int32 I = 0; I < Sss.Ministates.Num(); ++I)
		{
			const FOKVngeMinistate& M = Sss.Ministates[I];
			MiniBox->AddSlot().AutoHeight().Padding(0.f, 1.f)
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
				[
					Label(FText::FromString(FString::Printf(TEXT("[%s] %s"), *M.Group, *M.Name)), 9.5f)
				]
				+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)
				[
					Button(FText::FromString(TEXT("套用原对象")), [this, I]
					{
						if (Game.IsValid() && Game->Vnge().ApplyMinistate(I, -1)) Status(TEXT("已应用微状态"));
					}, 66.f, 19.f, false, 9.f)
				]
				+ SHorizontalBox::Slot().AutoWidth()
				[
					Button(FText::FromString(TEXT("套用选中")), [this, I]
					{
						if (Game.IsValid() && Game->Vnge().ApplyMinistate(I, Game->SelectedId)) Status(TEXT("已将微状态应用到选中对象"));
					}, 58.f, 19.f, false, 9.f)
				]
			];
		}
		if (Sss.Ministates.IsEmpty()) MiniBox->AddSlot().AutoHeight().Padding(3.f)[Label(FText::FromString(TEXT("当前场景不含 Ministates 微状态条目。")), 9.5f, TextHint())];
		if (!Sss.SssbJson.IsEmpty())
		{
			MiniBox->AddSlot().AutoHeight().Padding(0.f, 6.f, 0.f, 2.f)[SectionBanner(FString::Printf(TEXT("SSSB 节点图数据（%d 字节）"), Sss.SssbJson.Len()))];
			MiniBox->AddSlot().AutoHeight()[SNew(STextBlock).Font(Font(8.5f)).ColorAndOpacity(TextSoft()).AutoWrapText(true).Text(FText::FromString(Sss.SssbJson.Left(800)))];
		}
		if (!Sss.SssAdvJson.IsEmpty())
		{
			MiniBox->AddSlot().AutoHeight().Padding(0.f, 6.f, 0.f, 2.f)[SectionBanner(FString::Printf(TEXT("SSSAdv 扩展数据（%d 字节）"), Sss.SssAdvJson.Len()))];
			MiniBox->AddSlot().AutoHeight()[SNew(STextBlock).Font(Font(8.5f)).ColorAndOpacity(TextSoft()).AutoWrapText(true).Text(FText::FromString(Sss.SssAdvJson.Left(800)))];
		}
		Body->AddSlot().FillHeight(1.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(4.f)[SNew(SScrollBox) + SScrollBox::Slot()[MiniBox]]];
	}

	return Body;
}

// 3. VNGE PoseLib
TSharedRef<SWidget> FOKStudioVngeUi::BuildPoseLib()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid()) return Body;

	const FString RootDir = FOKStudioVngeRuntime::ResolvePoseLibRoot();
	const TArray<FString> Cats = FOKStudioVngeRuntime::GetPoseLibCategories(RootDir);
	if (!Cats.Contains(PoseCategory) && !Cats.IsEmpty()) PoseCategory = Cats[0];

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			SNew(STextBlock).Font(Font(9.f)).ColorAndOpacity(TextHint()).OverflowPolicy(ETextOverflowPolicy::Ellipsis)
			.Text(FText::FromString(TEXT("目录：") + RootDir))
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)
		[
			Button(FText::FromString(TEXT("开文件夹")), [RootDir]
			{
				IFileManager::Get().MakeDirectory(*RootDir, true);
				FPlatformProcess::ExploreFolder(*RootDir);
			}, 54.f, 18.f, false, 9.f)
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("刷新")), [this] { ResetTransientCaches(); DeferWin(TEXT("vnge_poselib")); }, 38.f, 18.f, false, 9.f)
		]
	];

	TSharedRef<SWrapBox> CatBar = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(2.f, 2.f));
	for (const FString& C : Cats)
	{
		CatBar->AddSlot()
		[
			Button(FText::FromString(PoseCategoryLabel(C)), [this, C] { PoseCategory = C; PosePage = 0; DeferWin(TEXT("vnge_poselib")); }, 68.f, 18.f, PoseCategory == C, 9.f)
		];
	}
	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 4.f)[CatBar];

	const TArray<FOKVngePosePresetItem> Items = Game->Vnge().ScanPosePresets(PoseCategory, PoseSearch);
	constexpr int32 PerPage = 24;
	const int32 TotalPages = FMath::Max(1, (Items.Num() + PerPage - 1) / PerPage);
	PosePage = FMath::Clamp(PosePage, 0, TotalPages - 1);

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 4.f, 0.f)
		[
			SNew(SBox).HeightOverride(19.f)
			[
				SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("输入关键词回车筛选预设…")))
				.Text_Lambda([this] { return FText::FromString(PoseSearch); })
				.OnTextCommitted_Lambda([this](const FText& T, ETextCommit::Type) { PoseSearch = T.ToString(); PosePage = 0; DeferWin(TEXT("vnge_poselib")); })
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("◀")), [this] { PosePage = FMath::Max(0, PosePage - 1); DeferWin(TEXT("vnge_poselib")); }, 24.f, 19.f, false, 9.f)
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(2.f, 0.f)
		[
			Label(FText::FromString(FString::Printf(TEXT("%d/%d 页（共 %d 项）"), PosePage + 1, TotalPages, Items.Num())), 9.f, TextSoft())
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 0.f, 0.f)
		[
			Button(FText::FromString(TEXT("▶")), [this, TotalPages] { PosePage = FMath::Min(TotalPages - 1, PosePage + 1); DeferWin(TEXT("vnge_poselib")); }, 24.f, 19.f, false, 9.f)
		]
	];

	TSharedRef<SVerticalBox> ListBox = SNew(SVerticalBox);
	const int32 StartIdx = PosePage * PerPage;
	const int32 EndIdx = FMath::Min(Items.Num(), StartIdx + PerPage);
	for (int32 I = StartIdx; I < EndIdx; ++I)
	{
		const FOKVngePosePresetItem& Item = Items[I];
		const FString FullPath = Item.FullPath;
		const FString DisplayName = Item.Name;
		const FSlateBrush* Thumb = Item.bIsPng ? BrushForPreset(FullPath) : nullptr;

		TSharedRef<SHorizontalBox> Row = SNew(SHorizontalBox);
		if (Thumb)
		{
			Row->AddSlot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 4.f, 0.f)
			[
				SNew(SBox).WidthOverride(44.f).HeightOverride(44.f)[SNew(SImage).Image(Thumb)]
			];
		}
		Row->AddSlot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			Button(FText::FromString(FString::Printf(TEXT("[%s] %s"), Item.bIsPng ? TEXT("PNG") : TEXT("TXT"), *DisplayName)), [this, FullPath, DisplayName]
			{
				if (!Game.IsValid()) return;
				FString Err;
				if (Game->Vnge().ApplyPosePreset(FullPath, TargetCharacterId(), Err))
				{
					MarkChanged();
					Status(TEXT("已套用 VNGE 预设：") + DisplayName);
				}
				else Status(TEXT("套用预设失败：") + Err);
			}, 0.f, Thumb ? 44.f : 22.f, false, 9.5f)
		];
		ListBox->AddSlot().AutoHeight().Padding(0.f, 1.f)[Row];
	}
	if (Items.IsEmpty())
	{
		ListBox->AddSlot().AutoHeight().Padding(8.f)[Label(FText::FromString(TEXT("该分类下暂无预设文件。")), 9.5f, TextHint())];
	}
	Body->AddSlot().FillHeight(1.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[ListBox]]];

	// Save bar
	Body->AddSlot().AutoHeight().Padding(0.f, 4.f, 0.f, 0.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 3.f, 0.f)
		[
			SNew(SBox).HeightOverride(20.f)
			[
				SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("输入预设名称以保存到当前分类…")))
				.Text_Lambda([this] { return FText::FromString(NewPresetName); })
				.OnTextChanged_Lambda([this](const FText& T) { NewPresetName = T.ToString(); })
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("存截图.png")), [this]
			{
				if (!Game.IsValid()) return;
				FString Saved, Err;
				if (Game->Vnge().SavePosePreset(PoseCategory, NewPresetName, TargetCharacterId(), true, Saved, Err))
				{
					Status(TEXT("已保存带截图预设：") + FPaths::GetCleanFilename(Saved));
					DeferWin(TEXT("vnge_poselib"));
				}
				else Status(TEXT("保存失败：") + Err);
			}, 68.f, 20.f, false, 9.5f, On())
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("存纯文本.txt")), [this]
			{
				if (!Game.IsValid()) return;
				FString Saved, Err;
				if (Game->Vnge().SavePosePreset(PoseCategory, NewPresetName, TargetCharacterId(), false, Saved, Err))
				{
					Status(TEXT("已保存预设：") + FPaths::GetCleanFilename(Saved));
					DeferWin(TEXT("vnge_poselib"));
				}
				else Status(TEXT("保存失败：") + Err);
			}, 72.f, 20.f, false, 9.5f)
		]
	];

	return Body;
}

// 4. VNGE Anime (KFA)
TSharedRef<SWidget> FOKStudioVngeUi::BuildAnime()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid() || !Game->Document) return Body;
	TArray<FOKVngeClip>& Clips = Game->Document->Vnge.Clips;
	SelectedClip = Clips.IsEmpty() ? -1 : FMath::Clamp(SelectedClip, 0, Clips.Num() - 1);

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 3.f, 0.f)
		[
			SNew(SBox).HeightOverride(20.f)
			[
				SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("新剪辑名称")))
				.Text_Lambda([this] { return FText::FromString(NewClipName); })
				.OnTextChanged_Lambda([this](const FText& T) { NewClipName = T.ToString(); })
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("+ 新建剪辑")), [this]
			{
				if (!Game.IsValid()) return;
				SelectedClip = Game->Vnge().CreateClip(NewClipName, NewClipDuration, 30.f);
				MarkChanged();
				DeferWin(TEXT("vnge_anime"));
				DeferWin(TEXT("vnge_hub"));
			}, 68.f, 20.f, false, 9.5f, On())
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("■ 全部停止")), [this] { if (Game.IsValid()) Game->Vnge().StopAllClips(); DeferWin(TEXT("vnge_anime")); }, 64.f, 20.f, false, 9.5f, Input())
		]
	];

	TSharedRef<SVerticalBox> ClipList = SNew(SVerticalBox);
	for (int32 I = 0; I < Clips.Num(); ++I)
	{
		const FOKVngeClip& C = Clips[I];
		ClipList->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				Button(TAttribute<FText>::CreateLambda([this, I]
				{
					if (!Game.IsValid() || !Game->Document->Vnge.Clips.IsValidIndex(I)) return FText::GetEmpty();
					const FOKVngeClip& X = Game->Document->Vnge.Clips[I];
					const FOKStudioVngeRuntime::FClipPlayState* PS = Game->GetVnge() ? Game->GetVnge()->GetClipPlayState(I) : nullptr;
					return FText::FromString(FString::Printf(TEXT("#%d %s（%d轨 / %.2fs）%s"),
						I + 1, *X.Name, X.Tracks.Num(), X.Duration,
						PS && PS->bPlaying ? *FString::Printf(TEXT(" [播放 %.2fs]"), PS->Time) : TEXT("")));
				}), [this, I] { SelectedClip = I; DeferWin(TEXT("vnge_anime")); }, 0.f, 20.f, SelectedClip == I, 9.5f)
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 1.f, 0.f)
			[
				Button(FText::FromString(TEXT("▶")), [this, I] { if (Game.IsValid()) Game->Vnge().PlayClip(I, false); }, 24.f, 20.f, false, 9.f)
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 1.f, 0.f)
			[
				Button(FText::FromString(TEXT("⏸")), [this, I] { if (Game.IsValid()) Game->Vnge().PauseClip(I); }, 24.f, 20.f, false, 9.f)
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				Button(FText::FromString(TEXT("■")), [this, I] { if (Game.IsValid()) Game->Vnge().StopClip(I); }, 24.f, 20.f, false, 9.f, Input())
			]
		];
	}
	if (Clips.IsEmpty())
	{
		ClipList->AddSlot().AutoHeight().Padding(6.f)[Label(FText::FromString(TEXT("当前场景暂无 VNAnime (KFA) 关键帧剪辑。")), 9.5f, TextHint())];
	}
	Body->AddSlot().AutoHeight().MaxHeight(140.f).Padding(0.f, 2.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[ClipList]]];

	if (Clips.IsValidIndex(SelectedClip))
	{
		const int32 CI = SelectedClip;
		Body->AddSlot().AutoHeight().Padding(0.f, 4.f, 0.f, 2.f)[SectionBanner(FString::Printf(TEXT("剪辑编辑：#%d %s"), CI + 1, *Clips[CI].Name))];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SBox).HeightOverride(20.f)
			[
				SNew(SSlider)
				.Value_Lambda([this, CI]
				{
					if (!Game.IsValid() || !Game->Document->Vnge.Clips.IsValidIndex(CI)) return 0.f;
					const float Dur = FMath::Max(Game->Document->Vnge.Clips[CI].Duration, 0.01f);
					const FOKStudioVngeRuntime::FClipPlayState* PS = Game->GetVnge() ? Game->GetVnge()->GetClipPlayState(CI) : nullptr;
					return PS ? FMath::Clamp(PS->Time / Dur, 0.f, 1.f) : 0.f;
				})
				.OnValueChanged_Lambda([this, CI](float U)
				{
					if (!Game.IsValid() || !Game->Document->Vnge.Clips.IsValidIndex(CI)) return;
					Game->Vnge().ScrubClip(CI, U * FMath::Max(Game->Document->Vnge.Clips[CI].Duration, 0.01f));
				})
			]
		];

		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)[Label(FText::FromString(TEXT("时长(s)")), 9.5f)]
			+ SHorizontalBox::Slot().AutoWidth().Padding(3.f, 0.f)[SNew(SBox).WidthOverride(52.f).HeightOverride(18.f)[VngeSpin([this, CI] { return Game.IsValid() && Game->Document->Vnge.Clips.IsValidIndex(CI) ? Game->Document->Vnge.Clips[CI].Duration : 2.f; }, [this, CI](float V) { if (Game.IsValid() && Game->Document->Vnge.Clips.IsValidIndex(CI)) { Game->Document->Vnge.Clips[CI].Duration = V; MarkChanged(); } }, 0.1f, 600.f, 0.1f)]]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(4.f, 0.f, 0.f, 0.f)[Label(FText::FromString(TEXT("倍速")), 9.5f)]
			+ SHorizontalBox::Slot().AutoWidth().Padding(3.f, 0.f)[SNew(SBox).WidthOverride(48.f).HeightOverride(18.f)[VngeSpin([this, CI] { return Game.IsValid() && Game->Document->Vnge.Clips.IsValidIndex(CI) ? Game->Document->Vnge.Clips[CI].Speed : 1.f; }, [this, CI](float V) { if (Game.IsValid() && Game->Document->Vnge.Clips.IsValidIndex(CI)) { Game->Document->Vnge.Clips[CI].Speed = V; MarkChanged(); } }, 0.05f, 8.f, 0.05f)]]
			+ SHorizontalBox::Slot().FillWidth(1.f).Padding(6.f, 0.f, 0.f, 0.f)
			[
				VngeCheck(TEXT("开场自动播放"), [this, CI] { return Game.IsValid() && Game->Document->Vnge.Clips.IsValidIndex(CI) && Game->Document->Vnge.Clips[CI].bAutorun; }, [this, CI](bool B) { if (Game.IsValid() && Game->Document->Vnge.Clips.IsValidIndex(CI)) { Game->Document->Vnge.Clips[CI].bAutorun = B; MarkChanged(); } })
			]
		];

		static const TCHAR* LoopNames[] = { TEXT("单次"), TEXT("循环"), TEXT("往返") };
		TSharedRef<SHorizontalBox> LoopRow = SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 4.f, 0.f)[Label(FText::FromString(TEXT("循环模式：")), 9.5f)];
		for (int32 L = 0; L < 3; ++L)
		{
			LoopRow->AddSlot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(LoopNames[L]), [this, CI, L]
				{
					if (Game.IsValid() && Game->Document->Vnge.Clips.IsValidIndex(CI))
					{
						Game->Document->Vnge.Clips[CI].LoopMode = L;
						MarkChanged();
						DeferWin(TEXT("vnge_anime"));
					}
				}, 0.f, 19.f, Clips[CI].LoopMode == L, 9.5f)
			];
		}
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)[LoopRow];

		Body->AddSlot().AutoHeight().Padding(0.f, 3.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(TEXT("◆ 录选中对象帧")), [this, CI]
				{
					if (!Game.IsValid() || Game->SelectedId < 0) { Status(TEXT("请先选择场景对象")); return; }
					const FOKStudioVngeRuntime::FClipPlayState* PS = Game->GetVnge() ? Game->GetVnge()->GetClipPlayState(CI) : nullptr;
					const float T = PS ? PS->Time : 0.f;
					if (Game->Vnge().RecordKeyToClip(CI, Game->SelectedId, T))
					{
						MarkChanged();
						Status(FString::Printf(TEXT("已在 %.2fs 录制对象关键帧"), T));
						DeferWin(TEXT("vnge_anime"));
					}
				}, 0.f, 21.f, false, 9.5f, On())
			]
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				Button(FText::FromString(TEXT("◆ 录当前镜头帧")), [this, CI]
				{
					if (!Game.IsValid()) return;
					const FOKStudioVngeRuntime::FClipPlayState* PS = Game->GetVnge() ? Game->GetVnge()->GetClipPlayState(CI) : nullptr;
					const float T = PS ? PS->Time : 0.f;
					if (Game->Vnge().RecordCameraKeyToClip(CI, T))
					{
						MarkChanged();
						Status(FString::Printf(TEXT("已在 %.2fs 录制镜头关键帧"), T));
						DeferWin(TEXT("vnge_anime"));
					}
				}, 0.f, 21.f, false, 9.5f)
			]
		];

		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.2f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(TEXT("★ 烤入主时间轴（追加）")), [this, CI]
				{
					if (!Game.IsValid()) return;
					if (Game->Vnge().BakeClipToTimeline(CI, false))
					{
						MarkChanged();
						if (OnOpenWindow) OnOpenWindow(TEXT("timeline"));
						Status(TEXT("已将剪辑关键帧烤入主时间轴"));
					}
				}, 0.f, 21.f, false, 9.5f)
			]
			+ SHorizontalBox::Slot().FillWidth(1.2f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(TEXT("烤入主时间轴（覆盖）")), [this, CI]
				{
					if (!Game.IsValid()) return;
					if (Game->Vnge().BakeClipToTimeline(CI, true))
					{
						MarkChanged();
						if (OnOpenWindow) OnOpenWindow(TEXT("timeline"));
						Status(TEXT("已覆盖烤入主时间轴"));
					}
				}, 0.f, 21.f, false, 9.5f)
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				Button(FText::FromString(TEXT("删除剪辑")), [this, CI]
				{
					if (Game.IsValid() && Game->Vnge().DeleteClip(CI))
					{
						MarkChanged();
						DeferWin(TEXT("vnge_anime"));
						DeferWin(TEXT("vnge_hub"));
					}
				}, 58.f, 21.f, false, 9.f, Input())
			]
		];

		TSharedRef<SVerticalBox> TrList = SNew(SVerticalBox);
		for (const FOKVngeTrack& Tr : Clips[CI].Tracks)
		{
			TrList->AddSlot().AutoHeight().Padding(2.f, 1.f)
			[
				Label(FText::FromString(FString::Printf(TEXT("• [%s] %s (#%d) — %d 个关键帧"), *Tr.TargetType, *Tr.TargetAlias, Tr.ObjectId, Tr.Keys.Num())), 9.f, TextSoft())
			];
		}
		Body->AddSlot().FillHeight(1.f).Padding(0.f, 3.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[TrList]]];
	}

	return Body;
}

// 5. VNGE Text
TSharedRef<SWidget> FOKStudioVngeUi::BuildText()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid() || !Game->Document) return Body;
	TArray<FOKVngeTextEntry>& Texts = Game->Document->Vnge.Texts;
	SelectedText = Texts.IsEmpty() ? -1 : FMath::Clamp(SelectedText, 0, Texts.Num() - 1);

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			VngeCheck(TEXT("视口显示字幕与空间文字"), [this] { return Game.IsValid() && Game->GetVnge() && Game->GetVnge()->bShowTextOverlay; }, [this](bool B) { if (Game.IsValid()) Game->Vnge().bShowTextOverlay = B; })
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)
		[
			Button(FText::FromString(TEXT("+ 2D 字幕")), [this]
			{
				if (!Game.IsValid()) return;
				SelectedText = Game->Vnge().AddTextEntry(TEXT("新屏幕字幕"), false);
				MarkChanged();
				DeferWin(TEXT("vnge_text"));
				DeferWin(TEXT("vnge_hub"));
			}, 64.f, 20.f, false, 9.5f, On())
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("+ 3D 文字")), [this]
			{
				if (!Game.IsValid()) return;
				SelectedText = Game->Vnge().AddTextEntry(TEXT("3D 空间文字"), true);
				MarkChanged();
				DeferWin(TEXT("vnge_text"));
				DeferWin(TEXT("vnge_hub"));
			}, 64.f, 20.f, false, 9.5f)
		]
	];

	TSharedRef<SVerticalBox> ListBox = SNew(SVerticalBox);
	for (int32 I = 0; I < Texts.Num(); ++I)
	{
		const FOKVngeTextEntry& T = Texts[I];
		ListBox->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 3.f, 0.f)
			[
				SNew(SCheckBox).Style(&CheckStyle())
				.IsChecked_Lambda([this, I] { return Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(I) && Game->Document->Vnge.Texts[I].bVisible ? ECheckBoxState::Checked : ECheckBoxState::Unchecked; })
				.OnCheckStateChanged_Lambda([this, I](ECheckBoxState S) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(I)) { Game->Document->Vnge.Texts[I].bVisible = (S == ECheckBoxState::Checked); MarkChanged(); } })
			]
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				Button(FText::FromString(FString::Printf(TEXT("[%s] %s"), T.bIs3D ? TEXT("3D") : TEXT("2D"), *T.Text.Replace(TEXT("\n"), TEXT(" ")).Left(28))),
					[this, I] { SelectedText = I; DeferWin(TEXT("vnge_text")); }, 0.f, 20.f, SelectedText == I, 9.5f)
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 0.f, 0.f)
			[
				Button(FText::FromString(TEXT("删")), [this, I]
				{
					if (Game.IsValid() && Game->Vnge().RemoveTextEntry(I))
					{
						MarkChanged();
						DeferWin(TEXT("vnge_text"));
						DeferWin(TEXT("vnge_hub"));
					}
				}, 28.f, 20.f, false, 9.f, Input())
			]
		];
	}
	if (Texts.IsEmpty()) ListBox->AddSlot().AutoHeight().Padding(6.f)[Label(FText::FromString(TEXT("当前场景暂无 VNText 或 Studio 文字节点。")), 9.5f, TextHint())];
	Body->AddSlot().AutoHeight().MaxHeight(130.f).Padding(0.f, 2.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[ListBox]]];

	if (Texts.IsValidIndex(SelectedText))
	{
		const int32 TI = SelectedText;
		Body->AddSlot().AutoHeight().Padding(0.f, 4.f, 0.f, 2.f)[SectionBanner(FString::Printf(TEXT("编辑文字条目 #%d"), TI + 1))];
		Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			VngeRow(TEXT("文本内容"), SNew(SEditableTextBox).Style(&TextBoxStyle())
				.Text_Lambda([this, TI] { return FText::FromString(Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI) ? Game->Document->Vnge.Texts[TI].Text : FString()); })
				.OnTextChanged_Lambda([this, TI](const FText& V) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI)) { Game->Document->Vnge.Texts[TI].Text = V.ToString(); MarkChanged(); } }), 0.25f)
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				VngeCheck(TEXT("3D 空间投影"), [this, TI] { return Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI) && Game->Document->Vnge.Texts[TI].bIs3D; },
					[this, TI](bool B) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI)) { Game->Document->Vnge.Texts[TI].bIs3D = B; MarkChanged(); DeferWin(TEXT("vnge_text")); } })
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(4.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("字号")), 9.5f)]
			+ SHorizontalBox::Slot().AutoWidth()[SNew(SBox).WidthOverride(48.f).HeightOverride(18.f)[VngeSpin([this, TI] { return Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI) ? Game->Document->Vnge.Texts[TI].Size : 24.f; }, [this, TI](float V) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI)) { Game->Document->Vnge.Texts[TI].Size = V; MarkChanged(); } }, 8.f, 160.f, 1.f)]]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(4.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("描边")), 9.5f)]
			+ SHorizontalBox::Slot().AutoWidth()[SNew(SBox).WidthOverride(44.f).HeightOverride(18.f)[VngeSpin([this, TI] { return Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI) ? Game->Document->Vnge.Texts[TI].OutlineSpread : 1.f; }, [this, TI](float V) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI)) { Game->Document->Vnge.Texts[TI].OutlineSpread = V; MarkChanged(); } }, 0.f, 6.f, 0.2f)]]
		];

		// Position X / Y / Z
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)[Label(FText::FromString(Texts[TI].bIs3D ? TEXT("3D坐标(m)") : TEXT("偏移(px)")), 9.5f, TextSoft())]
			+ SHorizontalBox::Slot().AutoWidth().Padding(3.f, 0.f)[SNew(SBox).WidthOverride(56.f).HeightOverride(18.f)[VngeSpin([this, TI] { return Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI) ? float(Game->Document->Vnge.Texts[TI].Position.X) : 0.f; }, [this, TI](float V) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI)) { Game->Document->Vnge.Texts[TI].Position.X = V; MarkChanged(); } }, -2000.f, 2000.f, Texts[TI].bIs3D ? 0.05f : 2.f)]]
			+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)[SNew(SBox).WidthOverride(56.f).HeightOverride(18.f)[VngeSpin([this, TI] { return Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI) ? float(Game->Document->Vnge.Texts[TI].Position.Y) : 0.f; }, [this, TI](float V) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI)) { Game->Document->Vnge.Texts[TI].Position.Y = V; MarkChanged(); } }, -2000.f, 2000.f, Texts[TI].bIs3D ? 0.05f : 2.f)]]
			+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)[SNew(SBox).WidthOverride(56.f).HeightOverride(18.f)[VngeSpin([this, TI] { return Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI) ? float(Game->Document->Vnge.Texts[TI].Position.Z) : 0.f; }, [this, TI](float V) { if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI)) { Game->Document->Vnge.Texts[TI].Position.Z = V; MarkChanged(); } }, -2000.f, 2000.f, 0.05f)]]
			+ SHorizontalBox::Slot().FillWidth(1.f).Padding(3.f, 0.f, 0.f, 0.f)
			[
				Button(FText::FromString(TEXT("移至选中处")), [this, TI]
				{
					if (!Game.IsValid() || !Game->Document->Vnge.Texts.IsValidIndex(TI)) return;
					const FVector UeLoc = Game->SelectedId >= 0 ? Game->Document->WorldTransform(Game->SelectedId).GetLocation() : Game->Focus;
					Game->Document->Vnge.Texts[TI].bIs3D = true;
					Game->Document->Vnge.Texts[TI].ObjectId = -1;
					Game->Document->Vnge.Texts[TI].Position = FVector(UeLoc.Y * 0.01f, (UeLoc.Z + 35.f) * 0.01f, UeLoc.X * 0.01f);
					MarkChanged();
					DeferWin(TEXT("vnge_text"));
				}, 0.f, 18.f, false, 9.f)
			]
		];

		if (!Texts[TI].bIs3D)
		{
			static const TCHAR* AnchorNames[] = { TEXT("左上"), TEXT("上中"), TEXT("右上"), TEXT("左中"), TEXT("正中"), TEXT("右中"), TEXT("左下"), TEXT("下中"), TEXT("右下") };
			TSharedRef<SWrapBox> Anchors = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(2.f, 2.f));
			for (int32 A = 0; A < 9; ++A)
			{
				Anchors->AddSlot()
				[
					Button(FText::FromString(AnchorNames[A]), [this, TI, A]
					{
						if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI))
						{
							Game->Document->Vnge.Texts[TI].Anchor = A;
							MarkChanged();
							DeferWin(TEXT("vnge_text"));
						}
					}, 40.f, 18.f, Texts[TI].Anchor == A, 9.f)
				];
			}
			Body->AddSlot().AutoHeight().Padding(0.f, 2.f)[Anchors];
		}

		// Quick color presets
		struct FColPreset { const TCHAR* Name; FLinearColor Col; };
		static const FColPreset Cols[] = {
			{ TEXT("纯白"), FLinearColor::White },
			{ TEXT("暖黄"), FLinearColor(1.f, 0.92f, 0.35f, 1.f) },
			{ TEXT("樱粉"), FLinearColor(1.f, 0.65f, 0.82f, 1.f) },
			{ TEXT("天青"), FLinearColor(0.45f, 0.92f, 1.f, 1.f) },
			{ TEXT("鲜红"), FLinearColor(1.f, 0.32f, 0.32f, 1.f) },
		};
		TSharedRef<SHorizontalBox> ColRow = SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 4.f, 0.f)[Label(FText::FromString(TEXT("字色：")), 9.5f)];
		for (const FColPreset& CP : Cols)
		{
			const FLinearColor CVal = CP.Col;
			ColRow->AddSlot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(CP.Name), [this, TI, CVal]
				{
					if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI))
					{
						Game->Document->Vnge.Texts[TI].Color = CVal;
						MarkChanged();
					}
				}, 40.f, 18.f, false, 9.f)
			];
		}
		ColRow->AddSlot().AutoWidth().Padding(4.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("半透黑底")), [this, TI]
			{
				if (Game.IsValid() && Game->Document->Vnge.Texts.IsValidIndex(TI))
				{
					FLinearColor& Bg = Game->Document->Vnge.Texts[TI].BgColor;
					Bg = Bg.A > 0.1f ? FLinearColor(0.f, 0.f, 0.f, 0.f) : FLinearColor(0.f, 0.f, 0.f, 0.65f);
					MarkChanged();
				}
			}, 56.f, 18.f, false, 9.f)
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)[ColRow];
	}

	return Body;
}

// 6. VNGE Sound
TSharedRef<SWidget> FOKStudioVngeUi::BuildSound()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid() || !Game->Document) return Body;
	TArray<FOKVngeSoundSource>& Sounds = Game->Document->Vnge.Sounds;
	SelectedSound = Sounds.IsEmpty() ? -1 : FMath::Clamp(SelectedSound, 0, Sounds.Num() - 1);

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 3.f, 0.f)
		[
			SNew(SBox).HeightOverride(20.f)
			[
				SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("输入外部 .ogg / .wav 文件路径…")))
				.Text_Lambda([this] { return FText::FromString(NewSoundPath); })
				.OnTextChanged_Lambda([this](const FText& T) { NewSoundPath = T.ToString(); })
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("+ 添加音源")), [this]
			{
				if (!Game.IsValid()) return;
				const FString Clean = NewSoundPath.TrimStartAndEnd().TrimQuotes();
				if (Clean.IsEmpty()) { Status(TEXT("请先填写音频文件路径")); return; }
				SelectedSound = Game->Vnge().AddSoundSource(Clean, TargetCharacterId());
				MarkChanged();
				Status(TEXT("已添加场景音源：") + FPaths::GetCleanFilename(Clean));
				DeferWin(TEXT("vnge_sound"));
				DeferWin(TEXT("vnge_hub"));
			}, 68.f, 20.f, false, 9.5f, On())
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("■ 全部停止")), [this] { if (Game.IsValid()) Game->Vnge().StopAllSounds(); DeferWin(TEXT("vnge_sound")); }, 64.f, 20.f, false, 9.5f, Input())
		]
	];

	TSharedRef<SVerticalBox> ListBox = SNew(SVerticalBox);
	for (int32 I = 0; I < Sounds.Num(); ++I)
	{
		const FOKVngeSoundSource& S = Sounds[I];
		const FString LabelStr = FString::Printf(TEXT("[%s] %s"), !S.ExtractedPath.IsEmpty() ? TEXT("内嵌") : TEXT("外部"),
			S.Id.IsEmpty() ? *FPaths::GetCleanFilename(S.Path) : *S.Id);
		ListBox->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				Button(TAttribute<FText>::CreateLambda([this, I, LabelStr]
				{
					const bool bPlaying = Game.IsValid() && Game->GetVnge() && Game->GetVnge()->IsSoundPlaying(I);
					return FText::FromString(LabelStr + (bPlaying ? TEXT(" [播放中]") : TEXT("")));
				}), [this, I] { SelectedSound = I; DeferWin(TEXT("vnge_sound")); }, 0.f, 20.f, SelectedSound == I, 9.5f)
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 1.f, 0.f)
			[
				Button(FText::FromString(TEXT("▶ 试听")), [this, I]
				{
					if (!Game.IsValid()) return;
					FString Err;
					if (!Game->Vnge().PlaySoundSource(I, Err)) Status(TEXT("播放失败：") + Err);
					else Status(TEXT("正在播放音源"));
				}, 46.f, 20.f, false, 9.f)
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 1.f, 0.f)
			[
				Button(FText::FromString(TEXT("■")), [this, I] { if (Game.IsValid()) Game->Vnge().StopSoundSource(I); }, 24.f, 20.f, false, 9.f, Input())
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				Button(FText::FromString(TEXT("删")), [this, I]
				{
					if (Game.IsValid() && Game->Vnge().RemoveSoundSource(I))
					{
						MarkChanged();
						DeferWin(TEXT("vnge_sound"));
						DeferWin(TEXT("vnge_hub"));
					}
				}, 26.f, 20.f, false, 9.f, Input())
			]
		];
	}
	if (Sounds.IsEmpty()) ListBox->AddSlot().AutoHeight().Padding(6.f)[Label(FText::FromString(TEXT("当前场景暂无 VNSound 音源。")), 9.5f, TextHint())];
	Body->AddSlot().AutoHeight().MaxHeight(150.f).Padding(0.f, 2.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[ListBox]]];

	if (Sounds.IsValidIndex(SelectedSound))
	{
		const int32 SI = SelectedSound;
		Body->AddSlot().AutoHeight().Padding(0.f, 4.f, 0.f, 2.f)[SectionBanner(FString::Printf(TEXT("音源设置 #%d"), SI + 1))];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)[Label(FText::FromString(TEXT("音量")), 9.5f)]
			+ SHorizontalBox::Slot().AutoWidth().Padding(3.f, 0.f)[SNew(SBox).WidthOverride(52.f).HeightOverride(18.f)[VngeSpin([this, SI] { return Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI) ? Game->Document->Vnge.Sounds[SI].Volume : 1.f; }, [this, SI](float V) { if (Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI)) { Game->Document->Vnge.Sounds[SI].Volume = V; MarkChanged(); } }, 0.f, 2.f, 0.05f)]]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(6.f, 0.f, 0.f, 0.f)[Label(FText::FromString(TEXT("音调")), 9.5f)]
			+ SHorizontalBox::Slot().AutoWidth().Padding(3.f, 0.f)[SNew(SBox).WidthOverride(52.f).HeightOverride(18.f)[VngeSpin([this, SI] { return Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI) ? Game->Document->Vnge.Sounds[SI].Pitch : 1.f; }, [this, SI](float V) { if (Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI)) { Game->Document->Vnge.Sounds[SI].Pitch = V; MarkChanged(); } }, 0.2f, 3.f, 0.05f)]]
			+ SHorizontalBox::Slot().FillWidth(1.f).Padding(6.f, 0.f, 0.f, 0.f)
			[
				VngeCheck(TEXT("循环播放"), [this, SI] { return Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI) && Game->Document->Vnge.Sounds[SI].bLoop; }, [this, SI](bool B) { if (Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI)) { Game->Document->Vnge.Sounds[SI].bLoop = B; MarkChanged(); } })
			]
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f)[VngeCheck(TEXT("开场自动播放"), [this, SI] { return Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI) && Game->Document->Vnge.Sounds[SI].bAutoPlay; }, [this, SI](bool B) { if (Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI)) { Game->Document->Vnge.Sounds[SI].bAutoPlay = B; MarkChanged(); } })]
			+ SHorizontalBox::Slot().FillWidth(1.f)[VngeCheck(TEXT("3D 空间距离衰减"), [this, SI] { return Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI) && Game->Document->Vnge.Sounds[SI].bIs3D; }, [this, SI](bool B) { if (Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI)) { Game->Document->Vnge.Sounds[SI].bIs3D = B; MarkChanged(); } })]
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			VngeCheck(TEXT("播放时驱动绑定角色张嘴口型 (LipSync)"),
				[this, SI] { return Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI) && Game->Document->Vnge.Sounds[SI].bLipSync; },
				[this, SI](bool B) { if (Game.IsValid() && Game->Document->Vnge.Sounds.IsValidIndex(SI)) { Game->Document->Vnge.Sounds[SI].bLipSync = B; MarkChanged(); } })
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 3.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
			[
				Label(TAttribute<FText>::CreateLambda([this, SI]
				{
					if (!Game.IsValid() || !Game->Document->Vnge.Sounds.IsValidIndex(SI)) return FText::GetEmpty();
					const int32 BId = Game->Document->Vnge.Sounds[SI].BindObjectId;
					const FOKSceneObject* O = Game->Document->Find(BId);
					return FText::FromString(O ? FString::Printf(TEXT("绑定对象：#%d %s"), BId, *O->Name) : FString(TEXT("绑定对象：（未绑定）")));
				}), 9.5f, TextSoft())
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)
			[
				Button(FText::FromString(TEXT("绑定当前选中")), [this, SI]
				{
					if (!Game.IsValid() || Game->SelectedId < 0 || !Game->Document->Vnge.Sounds.IsValidIndex(SI)) return;
					Game->Document->Vnge.Sounds[SI].BindObjectId = Game->SelectedId;
					MarkChanged();
				}, 78.f, 19.f, false, 9.f)
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				Button(FText::FromString(TEXT("解绑")), [this, SI]
				{
					if (!Game.IsValid() || !Game->Document->Vnge.Sounds.IsValidIndex(SI)) return;
					Game->Document->Vnge.Sounds[SI].BindObjectId = -1;
					Game->Document->Vnge.Sounds[SI].BindActorAlias.Reset();
					MarkChanged();
				}, 40.f, 19.f, false, 9.f, Input())
			]
		];
	}

	return Body;
}

// 7. VNGE Physics
TSharedRef<SWidget> FOKStudioVngeUi::BuildPhysics()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid() || !Game->Document) return Body;
	FOKVngePhysicsData& Phys = Game->Document->Vnge.Physics;
	SelectedRule = Phys.Rules.IsEmpty() ? -1 : FMath::Clamp(SelectedRule, 0, Phys.Rules.Num() - 1);

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			VngeCheck(TEXT("启用距离 / 接触触发评估"), [this] { return Game.IsValid() && Game->Document->Vnge.Physics.bEnabled; }, [this](bool B) { if (Game.IsValid()) { Game->Document->Vnge.Physics.bEnabled = B; MarkChanged(); } })
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("+ 新增接触触发规则")), [this]
			{
				if (!Game.IsValid()) return;
				SelectedRule = Game->Vnge().AddPhysicsRule(-2, Game->SelectedId, 0.45f, TEXT("play_clip"), TEXT("0"));
				MarkChanged();
				DeferWin(TEXT("vnge_physics"));
				DeferWin(TEXT("vnge_hub"));
			}, 110.f, 20.f, false, 9.5f, On())
		]
	];

	TSharedRef<SVerticalBox> ListBox = SNew(SVerticalBox);
	for (int32 I = 0; I < Phys.Rules.Num(); ++I)
	{
		const FOKVngePhysicsRule& R = Phys.Rules[I];
		ListBox->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 3.f, 0.f)
			[
				SNew(SCheckBox).Style(&CheckStyle())
				.IsChecked_Lambda([this, I] { return Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(I) && Game->Document->Vnge.Physics.Rules[I].bEnabled ? ECheckBoxState::Checked : ECheckBoxState::Unchecked; })
				.OnCheckStateChanged_Lambda([this, I](ECheckBoxState S) { if (Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(I)) { Game->Document->Vnge.Physics.Rules[I].bEnabled = (S == ECheckBoxState::Checked); MarkChanged(); } })
			]
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				Button(FText::FromString(FString::Printf(TEXT("%s (≤%.2fm → %s:%s)"), *R.Name, R.TriggerDistance, *R.ActionKind, *R.ActionParam)),
					[this, I] { SelectedRule = I; DeferWin(TEXT("vnge_physics")); }, 0.f, 20.f, SelectedRule == I, 9.5f)
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f, 1.f, 0.f)
			[
				Button(FText::FromString(TEXT("触发")), [this, I]
				{
					if (Game.IsValid() && Game->Vnge().TriggerPhysicsRuleNow(I)) Status(TEXT("已执行物理规则触发动作"));
				}, 36.f, 20.f, false, 9.f)
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				Button(FText::FromString(TEXT("删")), [this, I]
				{
					if (Game.IsValid() && Game->Vnge().RemovePhysicsRule(I))
					{
						MarkChanged();
						DeferWin(TEXT("vnge_physics"));
						DeferWin(TEXT("vnge_hub"));
					}
				}, 26.f, 20.f, false, 9.f, Input())
			]
		];
	}
	if (Phys.Rules.IsEmpty()) ListBox->AddSlot().AutoHeight().Padding(6.f)[Label(FText::FromString(TEXT("暂无距离/接触触发规则。")), 9.5f, TextHint())];
	Body->AddSlot().AutoHeight().MaxHeight(130.f).Padding(0.f, 2.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[ListBox]]];

	if (Phys.Rules.IsValidIndex(SelectedRule))
	{
		const int32 RI = SelectedRule;
		Body->AddSlot().AutoHeight().Padding(0.f, 4.f, 0.f, 2.f)[SectionBanner(FString::Printf(TEXT("编辑触发规则 #%d"), RI + 1))];
		Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			VngeRow(TEXT("规则名称"), SNew(SEditableTextBox).Style(&TextBoxStyle())
				.Text_Lambda([this, RI] { return FText::FromString(Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI) ? Game->Document->Vnge.Physics.Rules[RI].Name : FString()); })
				.OnTextChanged_Lambda([this, RI](const FText& T) { if (Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI)) { Game->Document->Vnge.Physics.Rules[RI].Name = T.ToString(); MarkChanged(); } }))
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			VngeRow(TEXT("触发距离(米)"), VngeSpin(
				[this, RI] { return Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI) ? Game->Document->Vnge.Physics.Rules[RI].TriggerDistance : 0.35f; },
				[this, RI](float V) { if (Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI)) { Game->Document->Vnge.Physics.Rules[RI].TriggerDistance = V; MarkChanged(); } }, 0.02f, 50.f, 0.02f))
		];
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(TEXT("源设为镜头")), [this, RI] { if (Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI)) { Game->Document->Vnge.Physics.Rules[RI].SourceObjectId = -2; MarkChanged(); DeferWin(TEXT("vnge_physics")); } }, 0.f, 19.f, Phys.Rules[RI].SourceObjectId == -2, 9.f)
			]
			+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(TEXT("源设为选中对象")), [this, RI] { if (Game.IsValid() && Game->SelectedId >= 0 && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI)) { Game->Document->Vnge.Physics.Rules[RI].SourceObjectId = Game->SelectedId; MarkChanged(); DeferWin(TEXT("vnge_physics")); } }, 0.f, 19.f, false, 9.f)
			]
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				Button(FText::FromString(TEXT("目标设为选中对象")), [this, RI] { if (Game.IsValid() && Game->SelectedId >= 0 && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI)) { Game->Document->Vnge.Physics.Rules[RI].TargetObjectId = Game->SelectedId; MarkChanged(); DeferWin(TEXT("vnge_physics")); } }, 0.f, 19.f, false, 9.f)
			]
		];

		struct FActKind { const TCHAR* Id; const TCHAR* Label; };
		static const FActKind Acts[] = {
			{ TEXT("play_clip"), TEXT("播剪辑") },
			{ TEXT("apply_state"), TEXT("切SSS幕") },
			{ TEXT("play_sound"), TEXT("播音源") },
			{ TEXT("toggle_visible"), TEXT("切换显隐") },
		};
		TSharedRef<SHorizontalBox> ActRow = SNew(SHorizontalBox);
		for (const FActKind& AK : Acts)
		{
			const FString KindStr = AK.Id;
			ActRow->AddSlot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
			[
				Button(FText::FromString(AK.Label), [this, RI, KindStr]
				{
					if (Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI))
					{
						Game->Document->Vnge.Physics.Rules[RI].ActionKind = KindStr;
						MarkChanged();
						DeferWin(TEXT("vnge_physics"));
					}
				}, 0.f, 19.f, Phys.Rules[RI].ActionKind == KindStr, 9.f)
			];
		}
		Body->AddSlot().AutoHeight().Padding(0.f, 2.f)[ActRow];
		Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
		[
			VngeRow(TEXT("动作参数(索引/名)"), SNew(SEditableTextBox).Style(&TextBoxStyle())
				.Text_Lambda([this, RI] { return FText::FromString(Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI) ? Game->Document->Vnge.Physics.Rules[RI].ActionParam : FString()); })
				.OnTextChanged_Lambda([this, RI](const FText& T) { if (Game.IsValid() && Game->Document->Vnge.Physics.Rules.IsValidIndex(RI)) { Game->Document->Vnge.Physics.Rules[RI].ActionParam = T.ToString(); MarkChanged(); } }))
		];
	}

	const bool bHasRaw = !Phys.CollidersJson.IsEmpty() || !Phys.RigidBodiesJson.IsEmpty() || !Phys.TriggersJson.IsEmpty() || !Phys.ActionsJson.IsEmpty();
	if (bHasRaw)
	{
		Body->AddSlot().AutoHeight().Padding(0.f, 4.f, 0.f, 2.f)
		[
			Button(FText::FromString(bShowRawPhysicsJson ? TEXT("▼ 收起场景导入的原始碰撞体 / 刚体 / 触发器数据") : TEXT("▶ 查看场景导入的原始碰撞体 / 刚体 / 触发器数据")),
				[this] { bShowRawPhysicsJson = !bShowRawPhysicsJson; DeferWin(TEXT("vnge_physics")); }, 0.f, 19.f, false, 9.f, Input())
		];
		if (bShowRawPhysicsJson)
		{
			const FString Summary = FString::Printf(TEXT("Colliders: %s\nRigidBodies: %s\nTriggers: %s\nActions: %s"),
				*Phys.CollidersJson.Left(300), *Phys.RigidBodiesJson.Left(300), *Phys.TriggersJson.Left(300), *Phys.ActionsJson.Left(300));
			Body->AddSlot().FillHeight(1.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(4.f)[SNew(SScrollBox) + SScrollBox::Slot()[SNew(STextBlock).Font(Font(8.5f)).ColorAndOpacity(TextSoft()).AutoWrapText(true).Text(FText::FromString(Summary))]]];
		}
	}

	return Body;
}

// 8. VNGE Scene Utils & Status Copy
TSharedRef<SWidget> FOKStudioVngeUi::BuildUtils()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid()) return Body;

	// Section 1: Step Transform
	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)[SectionBanner(TEXT("一、选中对象精确步进变换 (Scene Utils)"))];
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f)[VngeCheck(TEXT("按局部坐标轴步进"), [this] { return bStepLocal; }, [this](bool B) { bStepLocal = B; })]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(4.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("位移cm")), 9.f)]
		+ SHorizontalBox::Slot().AutoWidth()[SNew(SBox).WidthOverride(46.f).HeightOverride(18.f)[VngeSpin([this] { return StepMoveCm; }, [this](float V) { StepMoveCm = V; }, 0.1f, 500.f, 0.5f)]]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(4.f, 0.f, 2.f, 0.f)[Label(FText::FromString(TEXT("旋转°")), 9.f)]
		+ SHorizontalBox::Slot().AutoWidth()[SNew(SBox).WidthOverride(46.f).HeightOverride(18.f)[VngeSpin([this] { return StepRotDeg; }, [this](float V) { StepRotDeg = V; }, 0.5f, 180.f, 1.f)]]
	];
	Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("-X")), [this] { if (Game.IsValid()) { Game->Vnge().StepMoveSelected(FVector(-StepMoveCm, 0, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("+X")), [this] { if (Game.IsValid()) { Game->Vnge().StepMoveSelected(FVector(StepMoveCm, 0, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("-Y")), [this] { if (Game.IsValid()) { Game->Vnge().StepMoveSelected(FVector(0, -StepMoveCm, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("+Y")), [this] { if (Game.IsValid()) { Game->Vnge().StepMoveSelected(FVector(0, StepMoveCm, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("-Z")), [this] { if (Game.IsValid()) { Game->Vnge().StepMoveSelected(FVector(0, 0, -StepMoveCm), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("+Z")), [this] { if (Game.IsValid()) { Game->Vnge().StepMoveSelected(FVector(0, 0, StepMoveCm), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
	];
	Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("俯仰-")), [this] { if (Game.IsValid()) { Game->Vnge().StepRotateSelected(FRotator(-StepRotDeg, 0, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("俯仰+")), [this] { if (Game.IsValid()) { Game->Vnge().StepRotateSelected(FRotator(StepRotDeg, 0, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("偏航-")), [this] { if (Game.IsValid()) { Game->Vnge().StepRotateSelected(FRotator(0, -StepRotDeg, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("偏航+")), [this] { if (Game.IsValid()) { Game->Vnge().StepRotateSelected(FRotator(0, StepRotDeg, 0), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("翻滚-")), [this] { if (Game.IsValid()) { Game->Vnge().StepRotateSelected(FRotator(0, 0, -StepRotDeg), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("翻滚+")), [this] { if (Game.IsValid()) { Game->Vnge().StepRotateSelected(FRotator(0, 0, StepRotDeg), bStepLocal); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
	];
	Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("缩放 0.9x")), [this] { if (Game.IsValid()) { Game->Vnge().StepScaleSelected(FVector(0.9f)); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("缩放 0.98x")), [this] { if (Game.IsValid()) { Game->Vnge().StepScaleSelected(FVector(0.98f)); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("缩放 1.02x")), [this] { if (Game.IsValid()) { Game->Vnge().StepScaleSelected(FVector(1.02f)); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(1.f, 0.f)[Button(FText::FromString(TEXT("缩放 1.1x")), [this] { if (Game.IsValid()) { Game->Vnge().StepScaleSelected(FVector(1.1f)); MarkChanged(); } }, 0.f, 19.f, false, 9.f)]
	];

	// Section 2: Batch Tools
	Body->AddSlot().AutoHeight().Padding(0.f, 6.f, 0.f, 3.f)[SectionBanner(TEXT("二、全场眨眼、Sync-H 对齐、批量换卡与道具 FK"))];
	Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)[Button(FText::FromString(TEXT("全场开启眨眼")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().SetAllCharactersBlink(1); MarkChanged(); Status(FString::Printf(TEXT("已开启 %d 名角色自然眨眼"), N)); } }, 0.f, 20.f, false, 9.5f)]
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)[Button(FText::FromString(TEXT("全场锁定睁眼")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().SetAllCharactersBlink(0); MarkChanged(); Status(FString::Printf(TEXT("已锁定 %d 名角色不眨眼"), N)); } }, 0.f, 20.f, false, 9.5f)]
		+ SHorizontalBox::Slot().FillWidth(1.f)[Button(FText::FromString(TEXT("全场闭眼")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().SetAllCharactersBlink(2); MarkChanged(); Status(FString::Printf(TEXT("已设 %d 名角色闭眼"), N)); } }, 0.f, 20.f, false, 9.5f)]
	];
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)[Button(FText::FromString(TEXT("Sync-H 同步动作进度")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().SyncHCharacters(TargetCharacterId(), false, true); MarkChanged(); Status(FString::Printf(TEXT("已向基准角色同步 %d 名角色动作进度"), N)); } }, 0.f, 20.f, false, 9.5f)]
		+ SHorizontalBox::Slot().FillWidth(1.f)[Button(FText::FromString(TEXT("Sync-H 位姿+动作对齐")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().SyncHCharacters(TargetCharacterId(), true, true); MarkChanged(); Status(FString::Printf(TEXT("已对齐 %d 名角色位姿与动作"), N)); } }, 0.f, 20.f, false, 9.5f)]
	];
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)[Button(FText::FromString(TEXT("选中道具清零 FK")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().BatchItemFk(true, true); MarkChanged(); Status(FString::Printf(TEXT("已重置 %d 件选中道具 FK"), N)); } }, 0.f, 20.f, false, 9.5f)]
		+ SHorizontalBox::Slot().FillWidth(1.f)[Button(FText::FromString(TEXT("全场道具清零 FK")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().BatchItemFk(false, true); MarkChanged(); Status(FString::Printf(TEXT("已重置全场 %d 件道具 FK"), N)); } }, 0.f, 20.f, false, 9.5f)]
	];

	// Batch Replace Card
	Body->AddSlot().AutoHeight().Padding(0.f, 3.f, 0.f, 1.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
		[
			SNew(SBox).HeightOverride(19.f)
			[
				SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("替换用角色卡 .png 路径…")))
				.Text_Lambda([this] { return FText::FromString(BatchCardPath); })
				.OnTextChanged_Lambda([this](const FText& T) { BatchCardPath = T.ToString(); })
			]
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("取卡库当前卡")), [this]
			{
				if (GetCardBrowserPreview)
				{
					const FString P = GetCardBrowserPreview();
					if (!P.IsEmpty()) { BatchCardPath = P; Status(TEXT("已填入角色卡浏览器所选卡片")); }
					else Status(TEXT("请先在「角色卡」窗口点选一张卡"));
				}
			}, 78.f, 19.f, false, 9.f)
		]
	];
	Body->AddSlot().AutoHeight().Padding(0.f, 1.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.1f).VAlign(VAlign_Center)[VngeCheck(TEXT("换卡保留当前服装状态"), [this] { return bBatchKeepClothes; }, [this](bool B) { bBatchKeepClothes = B; })]
		+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)[Button(FText::FromString(TEXT("换选中角色")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().BatchReplaceCharacterCards(BatchCardPath, true, bBatchKeepClothes); MarkChanged(); Status(FString::Printf(TEXT("已替换 %d 名选中角色"), N)); } }, 70.f, 19.f, false, 9.f)]
		+ SHorizontalBox::Slot().AutoWidth()[Button(FText::FromString(TEXT("换全场角色")), [this] { if (Game.IsValid()) { const int32 N = Game->Vnge().BatchReplaceCharacterCards(BatchCardPath, false, bBatchKeepClothes); MarkChanged(); Status(FString::Printf(TEXT("已替换 %d 名角色"), N)); } }, 70.f, 19.f, false, 9.f)]
	];

	// Section 3: Status Copy
	Body->AddSlot().AutoHeight().Padding(0.f, 6.f, 0.f, 3.f)[SectionBanner(TEXT("三、角色状态分类复制与批量粘贴 (Status Copy)"))];
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 4.f, 0.f)
		[
			Button(FText::FromString(TEXT("复制选中角色状态")), [this]
			{
				if (!Game.IsValid()) return;
				const int32 SrcId = TargetCharacterId();
				if (Game->Vnge().CopyCharacterStatus(SrcId))
				{
					Status(TEXT("已复制角色状态：") + Game->Vnge().CopiedStatusSourceName());
					DeferWin(TEXT("vnge_utils"));
				}
				else Status(TEXT("请先选择一个角色"));
			}, 108.f, 21.f, false, 9.5f, On())
		]
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			Label(TAttribute<FText>::CreateLambda([this]
			{
				const FOKStudioVngeRuntime* V = Game.IsValid() ? Game->GetVnge() : nullptr;
				return FText::FromString(V && V->HasCopiedStatus() ? TEXT("剪贴板：") + V->CopiedStatusSourceName() : FString(TEXT("剪贴板：（未复制）")));
			}), 9.5f, TextSoft())
		]
	];

	TSharedRef<SWrapBox> Checks = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(6.f, 2.f));
	auto AddMaskCheck = [&](const TCHAR* Name, bool* Ptr)
	{
		Checks->AddSlot()[SNew(SBox).WidthOverride(128.f)[VngeCheck(Name, [Ptr] { return *Ptr; }, [Ptr](bool B) { *Ptr = B; })]];
	};
	AddMaskCheck(TEXT("表情与眉眼嘴"), &CopyMask.bFace);
	AddMaskCheck(TEXT("FK/IK 姿势与动作"), &CopyMask.bPose);
	AddMaskCheck(TEXT("左右手势"), &CopyMask.bHands);
	AddMaskCheck(TEXT("视线与颈部"), &CopyMask.bLook);
	AddMaskCheck(TEXT("服装穿脱状态"), &CopyMask.bClothes);
	AddMaskCheck(TEXT("保留原配饰开关"), &CopyMask.bKeepAccessories);
	AddMaskCheck(TEXT("脸红/泪水/体液"), &CopyMask.bState);
	AddMaskCheck(TEXT("身形滑杆与风格"), &CopyMask.bStyle);
	AddMaskCheck(TEXT("局部变换"), &CopyMask.bLocalTransform);
	AddMaskCheck(TEXT("世界变换"), &CopyMask.bWorldTransform);
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f)[Checks];

	Body->AddSlot().AutoHeight().Padding(0.f, 3.f, 0.f, 0.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 3.f, 0.f)
		[
			Button(FText::FromString(TEXT("粘贴到选中的所有角色")), [this]
			{
				if (!Game.IsValid()) return;
				const int32 N = Game->Vnge().PasteCharacterStatus(Game->Selection, CopyMask);
				MarkChanged();
				Status(FString::Printf(TEXT("已将状态粘贴到 %d 名选中角色"), N));
			}, 0.f, 22.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().FillWidth(1.f)
		[
			Button(FText::FromString(TEXT("粘贴到全场所有角色")), [this]
			{
				if (!Game.IsValid() || !Game->Document) return;
				TArray<int32> AllChars;
				for (const FOKSceneObject& O : Game->Document->Objects) if (O.Kind == EOKSceneObjectKind::Character) AllChars.Add(O.Id);
				const int32 N = Game->Vnge().PasteCharacterStatus(AllChars, CopyMask);
				MarkChanged();
				Status(FString::Printf(TEXT("已将状态粘贴到全场 %d 名角色"), N));
			}, 0.f, 22.f, false, 9.5f)
		]
	];

	return SNew(SScrollBox).ScrollBarThickness(FVector2D(4.f, 4.f)) + SScrollBox::Slot().Padding(3.f)[Body];
}

// 9. VNGE Script (VNSS)
TSharedRef<SWidget> FOKStudioVngeUi::BuildScript()
{
	using namespace OKStudioStyle;
	TSharedRef<SVerticalBox> Body = SNew(SVerticalBox);
	if (!Game.IsValid() || !Game->Document) return Body;
	FOKVngeScriptData& Scr = Game->Document->Vnge.Script;
	SelectedScriptBlock = Scr.Blocks.IsEmpty() ? -1 : FMath::Clamp(SelectedScriptBlock, 0, Scr.Blocks.Num() - 1);

	Body->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 3.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			VngeCheck(TEXT("视口显示对话字幕框"), [this] { return Game.IsValid() && Game->GetVnge() && Game->GetVnge()->bShowDialogueOverlay; }, [this](bool B) { if (Game.IsValid()) Game->Vnge().bShowDialogueOverlay = B; })
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(2.f, 0.f)
		[
			Button(FText::FromString(TEXT("▶ 下一步")), [this]
			{
				if (!Game.IsValid()) return;
				if (Game->Vnge().StepScriptNext()) SelectedScriptBlock = Game->Vnge().ActiveScriptBlock;
				else Status(TEXT("已到达段落末尾"));
				DeferWin(TEXT("vnge_script"));
			}, 62.f, 20.f, false, 9.5f, On())
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("↺ 重置")), [this]
			{
				if (!Game.IsValid()) return;
				Game->Vnge().ResetScript();
				SelectedScriptBlock = 0;
				DeferWin(TEXT("vnge_script"));
			}, 48.f, 20.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("清空对话")), [this] { if (Game.IsValid()) Game->Vnge().ClearDialogue(); }, 56.f, 20.f, false, 9.5f, Input())
		]
	];

	// Block tabs
	TSharedRef<SWrapBox> BlockRow = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(2.f, 2.f));
	for (int32 B = 0; B < Scr.Blocks.Num(); ++B)
	{
		BlockRow->AddSlot()
		[
			Button(FText::FromString(FString::Printf(TEXT("%s (%d)"), *Scr.Blocks[B].Name, Scr.Blocks[B].Lines.Num())), [this, B]
			{
				SelectedScriptBlock = B;
				if (Game.IsValid() && Game->Document->Vnge.Script.Blocks.IsValidIndex(B))
					Game->Vnge().JumpScriptBlock(Game->Document->Vnge.Script.Blocks[B].Name);
				DeferWin(TEXT("vnge_script"));
			}, 76.f, 19.f, SelectedScriptBlock == B, 9.f)
		];
	}
	BlockRow->AddSlot()
	[
		Button(FText::FromString(TEXT("+ 新段落")), [this]
		{
			if (!Game.IsValid()) return;
			FOKVngeScriptBlock& NB = Game->Document->Vnge.Script.Blocks.AddDefaulted_GetRef();
			NB.Name = FString::Printf(TEXT("block_%d"), Game->Document->Vnge.Script.Blocks.Num());
			SelectedScriptBlock = Game->Document->Vnge.Script.Blocks.Num() - 1;
			MarkChanged();
			DeferWin(TEXT("vnge_script"));
			DeferWin(TEXT("vnge_hub"));
		}, 58.f, 19.f, false, 9.f)
	];
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f)[BlockRow];

	TSharedRef<SVerticalBox> LineList = SNew(SVerticalBox);
	if (Scr.Blocks.IsValidIndex(SelectedScriptBlock))
	{
		const FOKVngeScriptBlock& Blk = Scr.Blocks[SelectedScriptBlock];
		const int32 ActiveB = Game->GetVnge() ? Game->GetVnge()->ActiveScriptBlock : -1;
		const int32 ActiveL = Game->GetVnge() ? Game->GetVnge()->ActiveScriptLine : -1;
		for (int32 L = 0; L < Blk.Lines.Num(); ++L)
		{
			const bool bCur = (ActiveB == SelectedScriptBlock && ActiveL == L);
			const int32 BIdx = SelectedScriptBlock;
			LineList->AddSlot().AutoHeight().Padding(0.f, 1.f)
			[
				Button(FText::FromString(FString::Printf(TEXT("%02d  %s"), L + 1, *Blk.Lines[L])), [this, BIdx, L]
				{
					if (!Game.IsValid() || !Game->Document->Vnge.Script.Blocks.IsValidIndex(BIdx)) return;
					Game->Vnge().ActiveScriptBlock = BIdx;
					Game->Vnge().ActiveScriptLine = L - 1;
					Game->Vnge().StepScriptNext();
					DeferWin(TEXT("vnge_script"));
				}, 0.f, 20.f, bCur, 9.5f)
			];
		}
		if (Blk.Lines.IsEmpty())
		{
			LineList->AddSlot().AutoHeight().Padding(6.f)[Label(FText::FromString(TEXT("该段落暂无指令行，可在下方输入「角色名:台词」或「state:0」追加。")), 9.5f, TextHint())];
		}
	}
	else
	{
		LineList->AddSlot().AutoHeight().Padding(6.f)[Label(FText::FromString(TEXT("当前场景暂无 VNSS 剧本，点击「+ 新段落」可创建。")), 9.5f, TextHint())];
	}
	Body->AddSlot().FillHeight(1.f).Padding(0.f, 3.f)[SNew(SBorder).BorderImage(Brush(ListArea())).Padding(3.f)[SNew(SScrollBox) + SScrollBox::Slot()[LineList]]];

	// Composer
	Body->AddSlot().AutoHeight().Padding(0.f, 2.f, 0.f, 0.f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 2.f, 0.f)
		[
			SNew(SBox).HeightOverride(20.f)
			[
				SNew(SEditableTextBox).Style(&TextBoxStyle()).HintText(FText::FromString(TEXT("如：女主:你好！ 或 state:0 / cam:0 / clip:0")))
				.Text_Lambda([this] { return FText::FromString(NewScriptLine); })
				.OnTextChanged_Lambda([this](const FText& T) { NewScriptLine = T.ToString(); })
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 2.f, 0.f)
		[
			Button(FText::FromString(TEXT("追加行")), [this]
			{
				if (!Game.IsValid() || NewScriptLine.TrimStartAndEnd().IsEmpty()) return;
				if (Game->Document->Vnge.Script.Blocks.IsEmpty())
				{
					FOKVngeScriptBlock& NB = Game->Document->Vnge.Script.Blocks.AddDefaulted_GetRef();
					NB.Name = TEXT("main");
					SelectedScriptBlock = 0;
				}
				if (Game->Document->Vnge.Script.Blocks.IsValidIndex(SelectedScriptBlock))
				{
					Game->Document->Vnge.Script.Blocks[SelectedScriptBlock].Lines.Add(NewScriptLine.TrimStartAndEnd());
					NewScriptLine.Reset();
					MarkChanged();
					DeferWin(TEXT("vnge_script"));
				}
			}, 50.f, 20.f, false, 9.5f)
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			Button(FText::FromString(TEXT("删末行")), [this]
			{
				if (!Game.IsValid() || !Game->Document->Vnge.Script.Blocks.IsValidIndex(SelectedScriptBlock)) return;
				TArray<FString>& Lines = Game->Document->Vnge.Script.Blocks[SelectedScriptBlock].Lines;
				if (!Lines.IsEmpty()) { Lines.Pop(); MarkChanged(); DeferWin(TEXT("vnge_script")); }
			}, 48.f, 20.f, false, 9.f, Input())
		]
	];

	return Body;
}
