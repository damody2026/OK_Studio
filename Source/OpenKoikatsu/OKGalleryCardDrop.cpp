#include "OKGalleryWidget.h"
#include "KKCardWorkspace.h"
#include "KKPreviewActor.h"
#include "Framework/Application/IInputProcessor.h"
#include "Framework/Application/SlateApplication.h"
#include "Input/DragAndDrop.h"
#include "Async/Async.h"
#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "Misc/Paths.h"
#include "Engine/Engine.h"
#include "UObject/UObjectIterator.h"

// Card files dragged in from Explorer (left or right button: both arrive as the window's OLE drop) anywhere on the card
// reader's window load like the card wall's 加载3D: an original KKS card or an OK card. UMG gives external drops to no
// UUserWidget (SObjectWidget routes only its own FUMGDragDropOp), and over the 3D view nothing under the cursor takes
// them, so the reader watches the drag itself: Slate turns the system drag into mouse moves and the drop into a mouse up,
// and an input preprocessor sees both first.
namespace
{
	TArray<FString> DraggedFiles()
	{
		if (!FSlateApplication::IsInitialized()) return {};
		const TSharedPtr<FDragDropOperation> Op = FSlateApplication::Get().GetDragDroppingContent();
		if (!Op.IsValid() || !Op->IsOfType<FExternalDragOperation>()) return {};
		const FExternalDragOperation& External = static_cast<const FExternalDragOperation&>(*Op);
		return External.HasFiles() ? External.GetFiles() : TArray<FString>();
	}

	bool HasCardFile(const TArray<FString>& Files)
	{
		for (const FString& F : Files) if (FPaths::GetExtension(F).Equals(TEXT("png"), ESearchCase::IgnoreCase)) return true;
		return false;
	}
}

class FOKCardDropProcessor : public IInputProcessor
{
public:
	explicit FOKCardDropProcessor(UOKCharacterController* InOwner) : Owner(InOwner) {}
	virtual void Tick(const float, FSlateApplication&, TSharedRef<ICursor>) override {}
	virtual const TCHAR* GetDebugName() const override { return TEXT("OKCardDrop"); }
	// Handled moves are what makes Slate answer the system's drag-over with "copy" (otherwise the cursor shows "no" and
	// the system never drops). Only while card files are dragged and the reader can take them.
	virtual bool HandleMouseMoveEvent(FSlateApplication&, const FPointerEvent&) override
	{
		UOKCharacterController* G = Owner.Get();
		return G && G->CanAcceptDroppedCard() && HasCardFile(DraggedFiles());
	}
	virtual bool HandleMouseButtonUpEvent(FSlateApplication& App, const FPointerEvent&) override
	{
		UOKCharacterController* G = Owner.Get();
		const TArray<FString> Files = DraggedFiles();
		if (!G || !G->CanAcceptDroppedCard() || !HasCardFile(Files)) return false;
		App.CancelDragDrop();
		// Loaded on the next frame, out of the system's drop call.
		TWeakObjectPtr<UOKCharacterController> Weak(G);
		AsyncTask(ENamedThreads::GameThread, [Weak, Files]()
		{
			if (UOKCharacterController* C = Weak.Get())
				for (const FString& F : Files)
					if (FPaths::GetExtension(F).Equals(TEXT("png"), ESearchCase::IgnoreCase)) { C->OpenDroppedCard(F); break; }
		});
		return true;
	}
	TWeakObjectPtr<UOKCharacterController> Owner;
};

bool UOKCharacterController::CanAcceptDroppedCard() const
{
	return !bOkStudioOpen && !bInteractionOnly && !InteractionWidget && !InteractionScene && !bEnterInteractionAfterLoad
		&& GetVisibility() != ESlateVisibility::Collapsed;
}

bool UOKCharacterController::OpenDroppedCard(const FString& Raw)
{
	const FString Path = FPaths::ConvertRelativePathToFull(Raw);
	auto Say = [](const FString& Text, const FColor& Color)
	{
		if (GEngine) GEngine->AddOnScreenDebugMessage(1, 6.f, Color, Text);
		UE_LOG(LogTemp, Display, TEXT("OK reader drop: %s"), *Text);
	};
	if (!FPaths::GetExtension(Path).Equals(TEXT("png"), ESearchCase::IgnoreCase) || !IFileManager::Get().FileExists(*Path))
	{
		Say(TEXT("拖進來的不是角色卡 PNG：") + Path, FColor::Yellow);
		return false;
	}
	if (!CanAcceptDroppedCard())
	{
		Say(TEXT("目前的畫面不能載入角色卡"), FColor::Yellow);
		return false;
	}
	if (bLoadInFlight || PreparingPreview || bPropertyBusy || bAppearanceBusy || bAnimationPreparing || bPortableSaveInFlight || bApngCaptureInFlight)
	{
		Say(TEXT("正在處理上一個動作，請稍候再拖入"), FColor::Yellow);
		return false;
	}
	if (!PendingProperties.IsEmpty())
	{
		Say(TEXT("還有尚未套用的修改，先套用或重置再拖入"), FColor::Yellow);
		return false;
	}
	// Same as the MCP's load: an OK card (or one with an okpreview beside it) opens in the APNG source mode, an original
	// card in the KKS one; a card from another folder joins the list.
	bIndependentCards = !UKKCardWorkspace::PortableSourcePath(Path).IsEmpty();
	int32 Index = Entries.IndexOfByPredicate([&](const FKKCardListEntry& E) { return FPaths::IsSamePath(E.Path, Path); });
	if (Index == INDEX_NONE)
	{
		FKKCardListEntry E;
		E.Path = Path;
		E.FileName = FPaths::GetCleanFilename(Path);
		Index = Entries.Add(E);
	}
	SelectIndex(Index);
	if (SelectedIndex != Index)
	{
		Say(TEXT("讀不到這張角色卡：") + Path, FColor::Orange);
		return false;
	}
	Say(TEXT("載入拖入的角色卡：") + FPaths::GetCleanFilename(Path), FColor::Cyan);
	OnLoad3D();
	return true;
}

void UOKCharacterController::StartCardDrop()
{
	if (CardDropProcessor.IsValid() || !FSlateApplication::IsInitialized()) return;
	CardDropProcessor = MakeShared<FOKCardDropProcessor>(this);
	FSlateApplication::Get().RegisterInputPreProcessor(CardDropProcessor);
}

void UOKCharacterController::StopCardDrop()
{
	if (CardDropProcessor.IsValid() && FSlateApplication::IsInitialized()) FSlateApplication::Get().UnregisterInputPreProcessor(CardDropProcessor);
	CardDropProcessor.Reset();
}

// What dropping that file on the reader does (the drag itself comes from the system): for tests and ui_exec.
static FAutoConsoleCommand ReaderDropCmd(TEXT("ok.ReaderDrop"), TEXT("ok.ReaderDrop <card.png>: load it as if dragged onto the card reader"),
	FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
	{
		const FString Path = FString::Join(Args, TEXT(" ")).TrimQuotes();
		for (TObjectIterator<UOKCharacterController> It; It; ++It)
			if (It->CanAcceptDroppedCard()) { It->OpenDroppedCard(Path); return; }
	}));
