#include "OKGalleryWidget.h"
#include "KKPreviewActor.h"
#include "HAL/IConsoleManager.h"
#include "Engine/Engine.h"
#include "UObject/UObjectIterator.h"

// HairDeck hair on the reader's character: a generated cards_seed<s>.json (chains_seed<s>.json beside it) replaces her
// hair in the open session, then her meshes are rebuilt like an editor geometry change.
bool UOKCharacterController::ApplyHairDeckHair(const FString& CardsJson,const FString& OptsJson,FString& OutReport)
{
	if(!PreviewActor){OutReport=TEXT("沒有載入的角色");return false;}
	if(!PreviewActor->Session.ApplyHairDeck(CardsJson,OptsJson,OutReport))return false;
	const float Phase=PreviewActor->AnimPhase;const int32 Mode=PreviewActor->PoseMode;
	FString Error;
	if(!PreviewActor->RefreshEditorGeometry()&&!PreviewActor->LoadSession(Error)){OutReport=Error;return false;}
	PreviewActor->AnimPhase=Phase;PreviewActor->PoseMode=Mode;
	PreviewActor->ApplyShapes(Selected.Face.ShapeValueFace,Selected.Body.ShapeValueBody);
	return true;
}

static FAutoConsoleCommand ReaderHairDeckCmd(TEXT("ok.ReaderHairDeck"),
	TEXT("ok.ReaderHairDeck <cards_seed0.json> [opts json]: replace the reader character's hair with a HairDeck result"),
	FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
	{
		if(Args.IsEmpty())return;
		const FString Cards=Args[0].TrimQuotes();
		const FString Opts=Args.Num()>1?FString::Join(TArrayView<const FString>(Args).RightChop(1),TEXT(" ")):FString();
		for(TObjectIterator<UOKCharacterController> It;It;++It)
		{
			if(!It->HasPreviewCharacter())continue;
			FString Report;const bool bOk=It->ApplyHairDeckHair(Cards,Opts,Report);
			UE_LOG(LogTemp,Display,TEXT("OK HairDeck %s: %s"),bOk?TEXT("ok"):TEXT("failed"),*Report);
			if(GEngine)GEngine->AddOnScreenDebugMessage(2,8.f,bOk?FColor::Cyan:FColor::Orange,bOk?TEXT("已換上 HairDeck 頭髮"):Report);
			return;
		}
	}));
