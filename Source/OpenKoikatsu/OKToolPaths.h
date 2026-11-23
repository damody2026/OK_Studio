// Built tools (Tools/<Name>) and the video import's weights, found the same way in a development checkout and in a
// package: a package's Tools/ sits above its stage (Saved/StreetSocial/Build/<stage>/Windows/OpenKoikatsu), so the
// project directory alone does not reach it (Tools/package_studio_release.lua).
#pragma once

#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
#include "HAL/PlatformMisc.h"
#include "HAL/PlatformProcess.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

// The project directory, the game executable's folder and up to eight of its parents, the launch directory.
inline TArray<FString> OKToolRoots()
{
	TArray<FString> Roots;
	Roots.Add(FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()));
	FString Walk=FPaths::ConvertRelativePathToFull(FPlatformProcess::BaseDir());
	for(int32 Up=0;Up<9&&!Walk.IsEmpty();++Up)
	{
		FPaths::NormalizeDirectoryName(Walk);
		Roots.AddUnique(Walk);
		FString Parent=FPaths::GetPath(Walk);
		if(Parent==Walk)break;
		Walk=MoveTemp(Parent);
	}
	Roots.AddUnique(FPaths::ConvertRelativePathToFull(FPaths::LaunchDir()));
	return Roots;
}

// Tools/<Name>/target/release/<Name>.exe, Tools/<Name>/<Name>.exe or <Name>/<Name>.exe under any of OKToolRoots.
// Tried, when given, gets every path looked at.
inline FString OKFindTool(const FString& Name,TArray<FString>* Tried=nullptr)
{
	const FString Exe=Name+TEXT(".exe");
	for(const FString& Root:OKToolRoots())
		for(const FString& Rel:{FString(TEXT("Tools"))/Name/TEXT("target/release")/Exe,FString(TEXT("Tools"))/Name/Exe,Name/Exe})
		{
			const FString Candidate=FPaths::ConvertRelativePathToFull(Root/Rel);
			if(Tried)Tried->AddUnique(Candidate);
			if(FPaths::FileExists(Candidate))return Candidate;
		}
	return FString();
}

// The video import's checkpoints (SMPL-X body models and GVHMR) as ok-video looks for them (Tools/ok-video/src/main.rs):
// OK_GVHMR_MODELS, the project's local-instance.json "gvhmr_models", a GVHMR/checkpoints folder up from ok-video.exe,
// then <project>/ref/GVHMR/inputs/checkpoints. Empty when none has body_models and gvhmr. They are not redistributable:
// a package never carries them, the player brings their own (Docs/VIDEO_WEIGHTS.md).
inline FString OKVideoWeights(const FString& VideoExe,TArray<FString>* Tried=nullptr)
{
	TArray<FString> Candidates;
	FString Named=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_GVHMR_MODELS"));
	if(Named.IsEmpty())
	{
		FString Text;
		if(FFileHelper::LoadFileToString(Text,*(FPaths::ProjectDir()/TEXT("local-instance.json"))))
		{
			TSharedPtr<FJsonObject> Json;
			if(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Json)&&Json.IsValid())Json->TryGetStringField(TEXT("gvhmr_models"),Named);
		}
	}
	if(!Named.IsEmpty())Candidates.Add(Named);
	else
	{
		FString Walk=VideoExe.IsEmpty()?FString():FPaths::GetPath(FPaths::ConvertRelativePathToFull(VideoExe));
		for(int32 Up=0;Up<6&&!Walk.IsEmpty();++Up)
		{
			Candidates.AddUnique(Walk/TEXT("GVHMR/checkpoints"));
			FString Parent=FPaths::GetPath(Walk);
			if(Parent==Walk)break;
			Walk=MoveTemp(Parent);
		}
		Candidates.AddUnique(FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("ref/GVHMR/inputs/checkpoints")));
	}
	for(const FString& Dir:Candidates)
	{
		if(Tried)Tried->AddUnique(Dir);
		if(FPaths::DirectoryExists(Dir/TEXT("body_models"))&&FPaths::DirectoryExists(Dir/TEXT("gvhmr")))return Dir;
	}
	return FString();
}
