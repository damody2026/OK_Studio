#include "KKGameRoot.h"
#include "Misc/Paths.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"

UKKGameRoot::UKKGameRoot()
{
	Root = TEXT("C:/portable/KoikatuSunshine");
}

UKKGameRoot* UKKGameRoot::Get()
{
	UKKGameRoot* Game = GetMutableDefault<UKKGameRoot>();
	// -NoGameRoot: a package runs on its own base library and has no original game. The cooked Config still names
	// the build machine's game (DefaultGame.ini Root=D:/KoikatuSunshine), and the reader then listed and held open that
	// machine's UserData folders (2026-11-17, the Studio package). Tools/street_stage.lua packaged_launch passes it.
	if (NoGame()) Game->Root.Reset();
	return Game;
}

bool UKKGameRoot::NoGame()
{
	static const bool bNoGame = FParse::Param(FCommandLine::Get(), TEXT("NoGameRoot"));
	return bNoGame;
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
