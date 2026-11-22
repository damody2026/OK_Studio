#include "OKGalleryWidget.h"
#include "KKPreviewActor.h"
#include "HAL/IConsoleManager.h"
#include "Engine/Engine.h"
#include "UObject/UObjectIterator.h"
#include "KKRustExtract.h"
#include "HAL/FileManager.h"
#include "Misc/Paths.h"

// HairDeck hair on the reader's character: a generated cards_seed<s>.json (chains_seed<s>.json beside it) replaces her
// hair in the open session, then her meshes are rebuilt like an editor geometry change.
bool UOKCharacterController::ApplyHairDeckHair(const FString& CardsJson,const FString& OptsJson,FString& OutReport)
{
	if(!PreviewActor){OutReport=TEXT("沒有載入的角色");return false;}
	// Every session this character loads from now on (clothing variants, reopened outfits) gets it too.
	const FString OldCards=PreviewActor->HairDeckCards,OldOpts=PreviewActor->HairDeckOpts;
	PreviewActor->HairDeckCards=CardsJson;PreviewActor->HairDeckOpts=OptsJson;
	if(!PreviewActor->ApplyHairDeckToSession(&OutReport)){PreviewActor->HairDeckCards=OldCards;PreviewActor->HairDeckOpts=OldOpts;return false;}
	const float Phase=PreviewActor->AnimPhase;const int32 Mode=PreviewActor->PoseMode;
	FString Error;
	// A full rebuild: the hair slot gets a new material and texture, which RefreshEditorGeometry (geometry only) keeps.
	if(!PreviewActor->LoadSession(Error)){OutReport=Error;return false;}
	PreviewActor->AnimPhase=Phase;PreviewActor->PoseMode=Mode;
	PreviewActor->ApplyShapes(Selected.Face.ShapeValueFace,Selected.Body.ShapeValueBody);
	return true;
}

// The HairDeck hair she wears kept in her card (okHk): every open of the card puts it on (reader, street, OK Studio),
// and bred children inherit it with the hairstyle. Written to the card itself unless Out names another file.
bool UOKCharacterController::SaveHairDeckToCard(const FString& OutIn,bool bRemove,FString& OutReport)
{
	if(!PreviewActor||PreviewCardPath.IsEmpty()){OutReport=TEXT("沒有載入的角色");return false;}
	if(!bRemove&&PreviewActor->HairDeckCards.IsEmpty()){OutReport=TEXT("她身上沒有 HairDeck 頭髮（先用 ok.ReaderHairDeck 換上）");return false;}
	const FString Card=PreviewCardPath;
	const FString Out=OutIn.IsEmpty()?Card:FPaths::ConvertRelativePathToFull(OutIn);
	if(Out!=Card)IFileManager::Get().MakeDirectory(*FPaths::GetPath(Out),true);
	FString Summary;
	if(!FOkSession::CardHairDeck(Card,bRemove?FString():PreviewActor->HairDeckCards,PreviewActor->HairDeckOpts,Out,Summary)){OutReport=Summary;return false;}
	// The card itself now carries it (or not): her later opens follow the card, not the reader's choice.
	if(Out==Card){PreviewActor->HairDeckCards.Reset();PreviewActor->HairDeckOpts.Reset();}
	OutReport=FString::Printf(TEXT("%s -> %s"),*Summary,*Out);
	return true;
}

static FAutoConsoleCommand ReaderHairDeckSaveCmd(TEXT("ok.ReaderHairDeckSave"),
	TEXT("ok.ReaderHairDeckSave [out card | -]: keep the HairDeck hair the reader character wears in her card (the card itself, or out); - takes it out of the card"),
	FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
	{
		const FString Arg=Args.IsEmpty()?FString():Args[0].TrimQuotes();
		const bool bRemove=Arg==TEXT("-");
		for(TObjectIterator<UOKCharacterController> It;It;++It)
		{
			if(!It->HasPreviewCharacter())continue;
			FString Report;const bool bOk=It->SaveHairDeckToCard(bRemove?FString():Arg,bRemove,Report);
			UE_LOG(LogTemp,Display,TEXT("OK HairDeck save %s: %s"),bOk?TEXT("ok"):TEXT("failed"),*Report);
			It->ScreenNote(2,8.f,bOk?FColor::Cyan:FColor::Orange,bOk?(bRemove?TEXT("卡片不再帶 HairDeck 頭髮（重新載入後換回原本頭髮）"):TEXT("HairDeck 頭髮已存進卡片")):Report);
			return;
		}
	}));

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
			It->ScreenNote(2,8.f,bOk?FColor::Cyan:FColor::Orange,bOk?TEXT("已換上 HairDeck 頭髮"):Report);
			return;
		}
	}));
