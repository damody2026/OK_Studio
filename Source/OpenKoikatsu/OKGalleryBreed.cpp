// Breeding (配種): a child card from two parent cards (ok-extract breed.rs), opened at once and then pictured as she
// looks. Docs/OK_BREEDING.md.
#include "OKGalleryWidget.h"
#include "OKBusyProgress.h"
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
#include "Misc/SecureHash.h"
#include "HAL/PlatformProcess.h"

FString OKHairDeckExe(); // OKGalleryHairDeck.cpp
// HairDeck's square crop of a face picture (OKCardPreviewCapture::BeginHairReference: 768x1024, the face centre in the
// middle): the face centre 0.48 of the way down, as in HairDeck's reference images.
static const TCHAR* BreedFaceBox=TEXT("0,143,768,911");

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
	TWeakObjectPtr<UOKCharacterController> Weak(this);
	// Her hair is HairDeck's, drawn from both parents' faces mixed 40-60% (the share from the seed): their face pictures
	// first (each opened and pictured once, kept while the card is unchanged).
	auto Breed=[Weak,Mother,Father,Seed,Output,Done]()
	{
	UOKCharacterController* Self=Weak.Get();
	if(!Self)return;
	Self->BreedStatus=FString::Printf(TEXT("配種中（種子 %llu）：%s × %s …（OK 卡要重新封裝，約半分鐘）"),Seed,*Self->BreedParentName(Mother),*Self->BreedParentName(Father));
	const FString MotherFace=BreedFaceCurrent(Mother)?BreedFacePath(Mother):FString(),FatherFace=BreedFaceCurrent(Father)?BreedFacePath(Father):FString();
	const FString HairExe=OKHairDeckExe();
	const auto Busy=MakeShared<OKBusy::FScope,ESPMode::ThreadSafe>(TEXT("配種"));
	Async(EAsyncExecution::Thread,[Weak,Mother,Father,Seed,Output,Done,MotherFace,FatherFace,HairExe,Busy]()
	{
		FString Summary;
		const bool Ok=FOkSession::Breed(Mother,Father,Seed,Output,Summary);
		if(Ok&&!MotherFace.IsEmpty()&&!FatherFace.IsEmpty()&&!HairExe.IsEmpty())
		{
			// The father's share 40-60%, from the seed (the same child each time for the same seed).
			const double Share=.4+.2*double((Seed*0x9E3779B97F4A7C15ull)>>40)/double(1ull<<24);
			const FString HairDir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("OKBreed/hair")/FPaths::GetBaseFilename(Output));
			const FString Args=FString::Printf(TEXT("generate --image \"%s\" --box %s --mix \"%s\" --mix-box %s --mix-weight %.3f --seed %llu --out \"%s\""),*MotherFace,BreedFaceBox,*FatherFace,BreedFaceBox,Share,Seed%1000000ull,*HairDir);
			int32 Code=-1;FString StdOut,StdErr;
			FPlatformProcess::ExecProcess(*HairExe,*Args,&Code,&StdOut,&StdErr);
			const FString Cards=HairDir/FString::Printf(TEXT("cards_seed%llu.json"),Seed%1000000ull);
			FString HairSummary;
			const FString Opts=FString::Printf(TEXT("{\"mix\":{\"mother\":\"%s\",\"father\":\"%s\",\"father_share\":%.3f}}"),
				*FPaths::GetCleanFilename(Mother).ReplaceCharWithEscapedChar(),*FPaths::GetCleanFilename(Father).ReplaceCharWithEscapedChar(),Share);
			if(Code!=0||!FPaths::FileExists(Cards))Summary+=FString::Printf(TEXT("; HairDeck hair not made (%d): %s"),Code,*StdErr.TrimStartAndEnd().Right(300));
			else if(!FOkSession::CardHairDeck(Output,Cards,Opts,Output,HairSummary))Summary+=TEXT("; HairDeck hair not kept: ")+HairSummary;
			else Summary+=FString::Printf(TEXT("; HairDeck hair mixed from both (father %.0f%%): %s"),Share*100.0,*HairSummary);
		}
		else if(Ok)Summary+=FString::Printf(TEXT("; no HairDeck mix (faces %s/%s, ok-hairdeck %s)"),MotherFace.IsEmpty()?TEXT("-"):TEXT("ok"),FatherFace.IsEmpty()?TEXT("-"):TEXT("ok"),HairExe.IsEmpty()?TEXT("missing"):TEXT("ok"));
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
	};
	BreedStatus=FString::Printf(TEXT("拍父母的臉（孩子的頭髮由兩人的頭髮混合生成）：%s × %s …"),*BreedParentName(Mother),*BreedParentName(Father));
	EnsureBreedFace(Mother,[Weak,Father,Breed](bool)
	{
		if(UOKCharacterController* Self=Weak.Get())Self->EnsureBreedFace(Father,[Breed](bool){Breed();});
	});
}

FString UOKCharacterController::BreedFacePath(const FString& Card)
{
	const FTCHARToUTF8 Utf8(*FPaths::ConvertRelativePathToFull(Card).ToLower());
	FMD5 Md5;Md5.Update(reinterpret_cast<const uint8*>(Utf8.Get()),Utf8.Length());
	uint8 Digest[16];Md5.Final(Digest);
	const FString Key=BytesToHex(Digest,16);
	return FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("OKBreed/faces")/(Key+TEXT(".png")));
}

bool UOKCharacterController::BreedFaceCurrent(const FString& Card)
{
	const FDateTime Face=IFileManager::Get().GetTimeStamp(*BreedFacePath(Card)),Of=IFileManager::Get().GetTimeStamp(*Card);
	return Face!=FDateTime::MinValue()&&Of!=FDateTime::MinValue()&&Face>=Of;
}

void UOKCharacterController::EnsureBreedFace(const FString& Card,TFunction<void(bool)> Next)
{
	if(BreedFaceCurrent(Card)){Next(true);return;}
	TWeakObjectPtr<UOKCharacterController> Weak(this);
	auto Capture=[Weak,Card,Next]()
	{
		UOKCharacterController* Self=Weak.Get();
		if(!Self||!IsValid(Self->PreviewActor)){Next(false);return;}
		OKCardPreviewCapture::BeginHairReference(Self->PreviewActor,[Card,Next](TArray<TArray<uint8>> Views,FString Error)
		{
			const FString Face=BreedFacePath(Card);
			IFileManager::Get().MakeDirectory(*FPaths::GetPath(Face),true);
			const bool bOk=Error.IsEmpty()&&Views.Num()>0&&Views[0].Num()>0&&FFileHelper::SaveArrayToFile(Views[0],*Face);
			UE_LOG(LogTemp,Display,TEXT("OK breed face %s -> %s: %s"),*Card,*Face,bOk?TEXT("ok"):*Error);
			Next(bOk);
		});
	};
	if(IsValid(PreviewActor)&&FPaths::IsSamePath(PreviewCardPath,Card)&&!bLoadInFlight){Capture();return;}
	bIndependentCards=!UKKCardWorkspace::PortableSourcePath(Card).IsEmpty();
	int32 Index=Entries.IndexOfByPredicate([&](const FKKCardListEntry& E){return FPaths::IsSamePath(E.Path,Card);});
	if(Index==INDEX_NONE){FKKCardListEntry E;E.Path=Card;E.FileName=FPaths::GetCleanFilename(Card);Index=Entries.Add(E);}
	SelectIndex(Index);
	if(SelectedIndex!=Index){Next(false);return;}
	OutfitIndex=0;RefreshOutfitList();OnLoad3D();
	const double Until=FPlatformTime::Seconds()+180.0;
	TSharedRef<double> ShownAt=MakeShared<double>(0.0);
	FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak,Card,Until,ShownAt,Capture,Next](float)->bool
	{
		UOKCharacterController* Self=Weak.Get();
		if(!Self){Next(false);return false;}
		const double Now=FPlatformTime::Seconds();
		if(!(IsValid(Self->PreviewActor)&&FPaths::IsSamePath(Self->PreviewCardPath,Card)&&!Self->bLoadInFlight))
		{*ShownAt=0.0;if(Now<Until)return true;Next(false);return false;}
		if(*ShownAt==0.0){*ShownAt=Now;return true;}
		if(Now-*ShownAt<1.5)return true;
		Capture();
		return false;
	}),0.25f);
}

void UOKCharacterController::ExportBredChild(const FString& PathIn,TFunction<void(bool,const FString&)> Done)
{
	if(!Done)Done=[](bool,const FString&){};
	const FString Card=!PathIn.IsEmpty()?PathIn:(Entries.IsValidIndex(SelectedIndex)?Entries[SelectedIndex].Path:FString());
	if(Card.IsEmpty()){BreedStatus=TEXT("請先在卡片牆點一張配出來的卡，再按「匯出完整卡」。");Done(false,BreedStatus);return;}
	if(bBreeding){BreedStatus=TEXT("上一次配種還在進行。");Done(false,BreedStatus);return;}
	const FString Output=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("UserData/okbreed/export")/FPaths::GetCleanFilename(Card));
	IFileManager::Get().MakeDirectory(*FPaths::GetPath(Output),true);
	bBreeding=true;
	BreedStatus=FString::Printf(TEXT("匯出完整卡：%s …（合併父母的資源並逐套服裝檢查，約半分鐘）"),*BreedParentName(Card));
	TWeakObjectPtr<UOKCharacterController> Weak(this);
	const auto Busy=MakeShared<OKBusy::FScope,ESPMode::ThreadSafe>(TEXT("匯出完整卡"));
	Async(EAsyncExecution::Thread,[Weak,Card,Output,Done,Busy]()
	{
		FString Summary;
		const bool Ok=FOkSession::BreedExport(Card,Output,Summary);
		AsyncTask(ENamedThreads::GameThread,[Weak,Output,Ok,Summary,Done,Busy]()
		{
			UE_LOG(LogTemp,Display,TEXT("OK breed export -> %s: %s"),*Output,*Summary);
			UOKCharacterController* Self=Weak.Get();
			if(!Self)return;
			Self->bBreeding=false;
			Self->BreedStatus=Ok?FString::Printf(TEXT("已匯出完整卡（不需要父母卡就能開）：\n%s"),*Output):TEXT("匯出失敗：")+Summary;
			Done(Ok,Ok?Output:Summary);
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
	OKCardPreviewCapture::Begin(PreviewActor,[Weak,Picture,Output,Finish](TArray<TArray<uint8>> Views,FString Error)
	{
		if(!Error.IsEmpty()||Views.Num()<2||Views[1].Num()==0||!FFileHelper::SaveArrayToFile(Views[1],*Picture)){Finish(false,Error.IsEmpty()?TEXT("拍照失敗"):Error);return;}
		// The card rewritten (tens of MB) off the game thread.
		const auto Busy=MakeShared<OKBusy::FScope,ESPMode::ThreadSafe>(TEXT("寫回孩子的卡面"));
		Async(EAsyncExecution::Thread,[Weak,Picture,Output,Finish,Busy]()
		{
			FString Summary;
			const bool Ok=FOkSession::BreedPicture(Output,Picture,Output,Summary);
			AsyncTask(ENamedThreads::GameThread,[Weak,Output,Ok,Summary,Finish,Busy]()
			{
				UE_LOG(LogTemp,Display,TEXT("OK breed picture: %s"),*Summary);
				// Her face too (her own children's hair), after the card is rewritten so it is newer than the card.
				UOKCharacterController* Self=Weak.Get();
				if(!Self){Finish(Ok,Summary);return;}
				Self->EnsureBreedFace(Output,[Ok,Summary,Finish](bool){Finish(Ok,Summary);});
			});
		});
	});
}
