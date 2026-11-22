#include "OKReaderText.h"

#include "HAL/FileManager.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "OKStreetRules.h"
#include "OKStreetSocialText.h"

namespace
{
FString LanguageFile(){return FPaths::ProjectSavedDir()/TEXT("CardReader/language.txt");}
int32 GLanguageGeneration=0;
bool GLanguageRead=false;

void ReadLanguage()
{
	if(GLanguageRead)return;
	GLanguageRead=true;
	FString Lang;
	if(!FParse::Value(FCommandLine::Get(),TEXT("ReaderLang="),Lang))FFileHelper::LoadFileToString(Lang,*LanguageFile());
	Lang.TrimStartAndEndInline();
	for(const auto& L:OKReaderLanguages())if(L.Key==Lang){OKStreetUseCppLanguage(Lang);return;}
}

// The rules the words come from: the ones already open in this process (the street, the one-on-one), else the reader's
// own copy of the DLL, so a rules build elsewhere is not blocked by this process holding it.
bool RulesReady()
{
	ReadLanguage();
	if(FOKStreetRules* Active=OKStreetActiveRules();Active&&Active->IsOpen())return true;
	static TUniquePtr<FOKStreetRules> ReaderRules;static bool bTried=false;
	if(bTried)return false;
	bTried=true;
	const FString Built=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("Tools/ok-rules/target/release/ok_rules.dll"));
	const FString Copy=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("CardReader/rules")/FString::Printf(TEXT("ok_rules_%u.dll"),FPlatformProcess::GetCurrentProcessId()));
	if(FPlatformMisc::GetEnvironmentVariable(TEXT("OK_RULES_DLL")).IsEmpty()&&FPaths::FileExists(Built)&&IFileManager::Get().Copy(*Copy,*Built)==COPY_OK)
		FPlatformMisc::SetEnvironmentVar(TEXT("OK_RULES_DLL"),*Copy);
	ReaderRules=MakeUnique<FOKStreetRules>();FString Error;
	if(!ReaderRules->Open(Error)){UE_LOG(LogTemp,Warning,TEXT("Card reader text: rules not open, the reader shows text ids: %s"),*Error);ReaderRules.Reset();return false;}
	OKStreetSetActiveRules(ReaderRules.Get());
	return true;
}
}

const TArray<TPair<FString,FString>>& OKReaderLanguages()
{
	static const TArray<TPair<FString,FString>> Languages={{TEXT("zh-TW"),TEXT("繁體中文")},{TEXT("zh-CN"),TEXT("简体中文")},{TEXT("en"),TEXT("English")}};
	return Languages;
}

FString OKReaderLanguage(){ReadLanguage();return OKStreetCppText().Lang;}

bool OKReaderSetLanguage(const FString& Lang)
{
	ReadLanguage();
	bool bKnown=false;for(const auto& L:OKReaderLanguages())bKnown|=L.Key==Lang;
	if(!bKnown)return false;
	if(OKStreetCppText().Lang==Lang)return true;
	OKStreetUseCppLanguage(Lang);++GLanguageGeneration;
	FFileHelper::SaveStringToFile(Lang,*LanguageFile());
	return true;
}

int32 OKReaderLanguageGeneration(){return GLanguageGeneration;}

FString OKReaderT(const FString& Id)
{
	if(Id.IsEmpty()||!RulesReady())return Id;
	return FString(OKT(*Id));
}

FString OKReaderMsg(const FString& Id,const TSharedPtr<FJsonObject>& Args)
{
	FString Out;
	if(Id.IsEmpty()||!RulesReady()||!OKStreetRulesText(*Id,Args,Out))return Id;
	return Out;
}
