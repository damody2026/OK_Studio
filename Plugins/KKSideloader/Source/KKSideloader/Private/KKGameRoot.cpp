#include "KKGameRoot.h"
#include "Misc/Paths.h"
#include "Misc/CommandLine.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/Parse.h"

namespace KKGameRootLocal
{
	constexpr const TCHAR* UserSection = TEXT("OKGameRoot");
	// DefaultGame.ini's values, taken before Get() first writes the user's choice over the config properties.
	FString ConfigRoot, ConfigLocalLibrary;
	bool bConfigTaken = false;
	void TakeConfig(UKKGameRoot* Game)
	{
		if (bConfigTaken) return;
		bConfigTaken = true;
		ConfigRoot = Game->Root;
		ConfigLocalLibrary = Game->LocalLibrary;
	}
	bool ReadUser(const TCHAR* Key, FString& Out)
	{
		return GConfig && GConfig->GetString(UserSection, Key, Out, GGameUserSettingsIni);
	}
	void WriteUser(const TCHAR* Key, const FString* Value)
	{
		if (!GConfig) return;
		if (Value) GConfig->SetString(UserSection, Key, **Value, GGameUserSettingsIni);
		else GConfig->RemoveKey(UserSection, Key, GGameUserSettingsIni);
		GConfig->Flush(false, GGameUserSettingsIni);
	}
	void PublishLocalLibrary()
	{
		FPlatformMisc::SetEnvironmentVar(TEXT("OK_LOCAL_LIBRARY"), *UKKGameRoot::ResolvedLocalLibrary());
	}
}

UKKGameRoot::UKKGameRoot()
{
	// No built-in path. Everyone keeps the game somewhere else, so a path baked in here is one machine's and wrong for
	// every other one: it points the reader at a folder that is not there, and the cards then quietly open without
	// their zipmods (the user, 2026-11-24: 「我這是萬人遊戲，你怎麼能假設大家路徑一樣」). Empty until the user says
	// where it is (設定 › 遊戲目錄), or a card opened from inside an installation says so itself.
	Root.Empty();
}

UKKGameRoot* UKKGameRoot::Get()
{
	using namespace KKGameRootLocal;
	UKKGameRoot* Game = GetMutableDefault<UKKGameRoot>();
	TakeConfig(Game);
	// -NoGameRoot: a package runs on its own base library and has no original game. The cooked Config still names
	// the build machine's game (DefaultGame.ini Root=D:/KoikatuSunshine), and the reader then listed and held open that
	// machine's UserData folders (2026-11-17, the Studio package). Tools/street_stage.lua packaged_launch passes it.
	// The user's own folder (SetUserRoot) is theirs and stands either way.
	FString User;
	Game->Root = ReadUser(TEXT("Root"), User) ? User : DefaultRoot();
	Game->LocalLibrary = ReadUser(TEXT("LocalLibrary"), User) ? User : ConfigLocalLibrary;
	return Game;
}

bool UKKGameRoot::NoGame()
{
	static const bool bNoGame = FParse::Param(FCommandLine::Get(), TEXT("NoGameRoot"));
	return bNoGame;
}

FString UKKGameRoot::DefaultRoot()
{
	KKGameRootLocal::TakeConfig(GetMutableDefault<UKKGameRoot>());
	return NoGame() ? FString() : KKGameRootLocal::ConfigRoot;
}

FString UKKGameRoot::DefaultLocalLibrary()
{
	KKGameRootLocal::TakeConfig(GetMutableDefault<UKKGameRoot>());
	return KKGameRootLocal::ConfigLocalLibrary;
}

void UKKGameRoot::SetUserRoot(const FString& Path)
{
	const FString Value = Path.TrimStartAndEnd();
	KKGameRootLocal::WriteUser(TEXT("Root"), &Value);
	Get();
}

void UKKGameRoot::SetUserLocalLibrary(const FString& Path)
{
	const FString Value = Path.TrimStartAndEnd();
	KKGameRootLocal::WriteUser(TEXT("LocalLibrary"), &Value);
	Get();
	KKGameRootLocal::PublishLocalLibrary();
}

void UKKGameRoot::ClearUserRoot()
{
	KKGameRootLocal::WriteUser(TEXT("Root"), nullptr);
	Get();
}

void UKKGameRoot::ClearUserLocalLibrary()
{
	KKGameRootLocal::WriteUser(TEXT("LocalLibrary"), nullptr);
	Get();
	KKGameRootLocal::PublishLocalLibrary();
}

bool UKKGameRoot::HasUserRoot()
{
	FString Unused;
	return KKGameRootLocal::ReadUser(TEXT("Root"), Unused);
}

bool UKKGameRoot::HasUserLocalLibrary()
{
	FString Unused;
	return KKGameRootLocal::ReadUser(TEXT("LocalLibrary"), Unused);
}

FString UKKGameRoot::ResolvedLocalLibrary()
{
	FString Library = Get()->LocalLibrary;
	if (Library.IsEmpty()) return Library;
	if (FPaths::IsRelative(Library)) Library = FPaths::ProjectDir() / Library;
	return FPaths::ConvertRelativePathToFull(Library);
}

FString UKKGameRoot::Abdata() const
{
	return FPaths::Combine(Root, TEXT("abdata"));
}

FString UKKGameRoot::Mods() const
{
	return FPaths::Combine(Root, TEXT("mods"));
}

FString UKKGameRoot::CharaFemale() const
{
	return FPaths::Combine(Root, TEXT("UserData"), TEXT("chara"), TEXT("female"));
}

FString UKKGameRoot::Coordinate() const
{
	return FPaths::Combine(Root, TEXT("UserData"), TEXT("coordinate"));
}

FKKGameRootChoice KKChooseGameRoot(const FString& Configured, const FString& CardsOwnInstall)
{
	auto HasMods=[](const FString& Folder){return !Folder.IsEmpty()&&FPaths::DirectoryExists(FPaths::Combine(Folder,TEXT("mods")));};
	FKKGameRootChoice Choice;
	Choice.Root=Configured;
	Choice.bConfiguredMissing=!Configured.IsEmpty()&&!HasMods(Configured);
	if(HasMods(CardsOwnInstall)&&!FPaths::IsSamePath(CardsOwnInstall,Configured))
	{
		Choice.Root=CardsOwnInstall;
		Choice.bFromCard=true;
	}
	return Choice;
}
