// Breeding (配種): a child card from two parent cards (ok-extract breed.rs), opened at once and then pictured as she
// looks. Docs/OK_BREEDING.md.
#include "OKGalleryWidget.h"
#include "KKPreviewActor.h"
#include "KKCardWorkspace.h"
#include "KKRustExtract.h"
#include "OKCardPreviewCapture.h"
#include "Async/Async.h"
#include "Containers/Ticker.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "Misc/DateTime.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

FString UOKCharacterController::BreedParentName(const FString& Path) const
{
	if(Path.IsEmpty())return TEXT("（未選）");
	const FKKCardListEntry* E=Entries.FindByPredicate([&](const FKKCardListEntry& X){return FPaths::IsSamePath(X.Path,Path);});
	const FString Name=E?(E->LastName+TEXT(" ")+E->FirstName).TrimStartAndEnd():FString();
	return Name.IsEmpty()?FPaths::GetBaseFilename(Path):Name;
}

bool UOKCharacterController::SetBreedParent(bool bFather,const FString& PathIn)
{
	const FString Path=!PathIn.IsEmpty()?PathIn:(Entries.IsValidIndex(SelectedIndex)?Entries[SelectedIndex].Path:FString());
	if(Path.IsEmpty()||!IFileManager::Get().FileExists(*Path)){BreedStatus=TEXT("請先在卡片牆點一張卡，再按「設為母親」或「設為父親」。");return false;}
	(bFather?BreedFather:BreedMother)=Path;
	BreedStatus=FString::Printf(TEXT("%s設為 %s。"),bFather?TEXT("父親"):TEXT("母親"),*BreedParentName(Path));
	return true;
}

void UOKCharacterController::BreedChild(uint64 SeedIn,TFunction<void(bool,const FString&)> Done)
{
	if(!Done)Done=[](bool,const FString&){};
	auto Fail=[this,&Done](const FString& Why){BreedStatus=Why;Done(false,Why);};
	if(BreedMother.IsEmpty()||BreedFather.IsEmpty()){Fail(TEXT("要先設好母親與父親。"));return;}
	if(FPaths::IsSamePath(BreedMother,BreedFather)){Fail(TEXT("母親和父親是同一張卡，請選兩張不同的卡。"));return;}
	if(bBreeding){Fail(TEXT("上一次配種還在進行。"));return;}
	if(bLoadInFlight){Fail(TEXT("卡片載入中，請稍候再配種。"));return;}
	// A new child each time: nine digits (short enough to read off and give back to MCP's "seed") from the clock and the
	// cycle counter, scrambled (the clock alone is coarse: every seed ended in 00001).
	const uint64 Seed=SeedIn?SeedIn:((uint64(FDateTime::UtcNow().GetTicks())^(uint64(FPlatformTime::Cycles64())<<7))*0x9E3779B97F4A7C15ull>>24)%1000000000ull+1;
	const FString Mother=BreedMother,Father=BreedFather;
	// The player's own cards (UserData, kept), not Saved (disposable).
	const FString Output=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("UserData/okbreed")/FString::Printf(TEXT("%s×%s_%llu.png"),
		*FPaths::GetBaseFilename(Mother).Left(40),*FPaths::GetBaseFilename(Father).Left(40),Seed));
	IFileManager::Get().MakeDirectory(*FPaths::GetPath(Output),true);
	bBreeding=true;
	BreedStatus=FString::Printf(TEXT("配種中（種子 %llu）：%s × %s …（OK 卡要重新封裝，約半分鐘）"),Seed,*BreedParentName(Mother),*BreedParentName(Father));
	TWeakObjectPtr<UOKCharacterController> Weak(this);
	Async(EAsyncExecution::Thread,[Weak,Mother,Father,Seed,Output,Done]()
	{
		FString Summary;
		const bool Ok=FOkSession::Breed(Mother,Father,Seed,Output,Summary);
		AsyncTask(ENamedThreads::GameThread,[Weak,Seed,Output,Ok,Summary,Done]()
		{
			UE_LOG(LogTemp,Display,TEXT("OK breed seed %llu -> %s: %s"),Seed,*Output,*Summary);
			UOKCharacterController* Self=Weak.Get();
			if(!Self)return;
			if(!Ok){Self->bBreeding=false;Self->BreedStatus=TEXT("配種失敗：")+Summary;Done(false,Summary);return;}
			// Opened at once, as a worn outfit card is.
			Self->bIndependentCards=!UKKCardWorkspace::PortableSourcePath(Output).IsEmpty();
			int32 Index=Self->Entries.IndexOfByPredicate([&](const FKKCardListEntry& E){return FPaths::IsSamePath(E.Path,Output);});
			if(Index==INDEX_NONE){FKKCardListEntry E;E.Path=Output;E.FileName=FPaths::GetCleanFilename(Output);Index=Self->Entries.Add(E);}
			Self->SelectIndex(Index);
			if(Self->SelectedIndex!=Index){Self->bBreeding=false;Self->BreedStatus=TEXT("孩子的卡讀不出來：")+Output;Done(false,Self->BreedStatus);return;}
			Self->OutfitIndex=0;Self->RefreshOutfitList();Self->OnLoad3D();
			Self->BreedStatus=FString::Printf(TEXT("生出 %s（種子 %llu），拍照中…"),*Self->BreedParentName(Output),Seed);
			// Pictured once she shows (and a moment more for her textures): her own picture instead of the base parent's.
			const double Until=FPlatformTime::Seconds()+180.0;
			TSharedRef<double> ShownAt=MakeShared<double>(0.0);
			FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak,Output,Until,ShownAt,Done](float)->bool
			{
				UOKCharacterController* Self=Weak.Get();
				if(!Self)return false;
				const bool bShown=IsValid(Self->PreviewActor)&&FPaths::IsSamePath(Self->PreviewCardPath,Output)&&!Self->bLoadInFlight;
				const double Now=FPlatformTime::Seconds();
				if(!bShown)
				{
					*ShownAt=0.0;
					if(Now<Until)return true;
					Self->bBreeding=false;Self->BreedStatus=TEXT("孩子已存好，但沒有顯示出來，卡片圖沒換：")+Output;Done(true,Output);
					return false;
				}
				if(*ShownAt==0.0){*ShownAt=Now;return true;}
				if(Now-*ShownAt<1.5)return true;
				Self->PictureBredChild(Output,Done);
				return false;
			}),0.25f);
		});
	});
}

void UOKCharacterController::PictureBredChild(const FString& Output,TFunction<void(bool,const FString&)> Done)
{
	const FString Picture=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("OKBreed/picture.png"));
	IFileManager::Get().MakeDirectory(*FPaths::GetPath(Picture),true);
	TWeakObjectPtr<UOKCharacterController> Weak(this);
	auto Finish=[Weak,Output,Done](bool bPictured,const FString& Note)
	{
		UOKCharacterController* Self=Weak.Get();
		if(!Self)return;
		Self->bBreeding=false;
		if(bPictured)++Self->CardPicturesVersion;
		Self->BreedStatus=FString::Printf(TEXT("生出 %s%s\n%s"),*Self->BreedParentName(Output),bPictured?TEXT("。"):*(TEXT("（卡片圖沒換：")+Note+TEXT("）")),*Output);
		Done(true,Output);
	};
	OKCardPreviewCapture::Begin(PreviewActor,[Picture,Output,Finish](TArray<TArray<uint8>> Views,FString Error)
	{
		if(!Error.IsEmpty()||Views.Num()<2||Views[1].Num()==0||!FFileHelper::SaveArrayToFile(Views[1],*Picture)){Finish(false,Error.IsEmpty()?TEXT("拍照失敗"):Error);return;}
		// The card rewritten (tens of MB) off the game thread.
		Async(EAsyncExecution::Thread,[Picture,Output,Finish]()
		{
			FString Summary;
			const bool Ok=FOkSession::BreedPicture(Output,Picture,Output,Summary);
			AsyncTask(ENamedThreads::GameThread,[Ok,Summary,Finish](){UE_LOG(LogTemp,Display,TEXT("OK breed picture: %s"),*Summary);Finish(Ok,Summary);});
		});
	});
}
