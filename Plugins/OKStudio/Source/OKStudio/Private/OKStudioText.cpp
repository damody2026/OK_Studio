#include "OKStudioText.h"

#include "Dom/JsonValue.h"
#include "Internationalization/Culture.h"
#include "Internationalization/Internationalization.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
	// The Chinese every table is read over, so the studio has words before (or without) the files.
	const TCHAR* const BuiltinZh[][2] = {
		{TEXT("load.title"), TEXT("載入場景")},
		{TEXT("load.progress"), TEXT("已建 {built, number} / 共 {total, number} 個物件")},
		{TEXT("load.percent"), TEXT("{percent, number}%")},
		{TEXT("load.waiting"), TEXT("準備中…")},
	};

	struct FTable
	{
		FString Lang;
		TMap<FString, FString> Words;
	};

	FString PickLanguage()
	{
		FString Lang = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_STUDIO_LANG")).TrimStartAndEnd();
		if (!Lang.IsEmpty()) return Lang;
		const FString Culture = FInternationalization::Get().GetCurrentLanguage()->GetName().ToLower();
		if (Culture.StartsWith(TEXT("ja"))) return TEXT("ja");
		if (Culture.StartsWith(TEXT("en"))) return TEXT("en");
		return TEXT("zh");
	}

	/** One studio.toml over Words: `id = "text"` lines, # comments and [sections] skipped, the text a JSON string. */
	void ReadTable(const FString& File, TMap<FString, FString>& Words)
	{
		FString Text;
		if (!FFileHelper::LoadFileToString(Text, *File)) return;
		TArray<FString> Lines;
		Text.ParseIntoArrayLines(Lines, false);
		for (int32 N = 0; N < Lines.Num(); ++N)
		{
			const FString Line = Lines[N].TrimStartAndEnd();
			if (Line.IsEmpty() || Line.StartsWith(TEXT("#")) || Line.StartsWith(TEXT("["))) continue;
			FString Key, Value;
			if (!Line.Split(TEXT("="), &Key, &Value))
			{
				UE_LOG(LogTemp, Warning, TEXT("OK studio text: %s:%d: expected id = \"text\""), *File, N + 1);
				continue;
			}
			Key = Key.TrimStartAndEnd().TrimQuotes();
			TArray<TSharedPtr<FJsonValue>> Parsed;
			const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(TEXT("[") + Value.TrimStartAndEnd() + TEXT("]"));
			FString Word;
			if (!FJsonSerializer::Deserialize(Reader, Parsed) || Parsed.Num() != 1 || !Parsed[0]->TryGetString(Word))
			{
				UE_LOG(LogTemp, Warning, TEXT("OK studio text: %s:%d: the text is not a quoted string"), *File, N + 1);
				continue;
			}
			Words.Add(Key, Word);
		}
	}

	const FTable& Table()
	{
		static FTable T = []
		{
			FTable Out;
			Out.Lang = PickLanguage();
			for (const auto& W : BuiltinZh) Out.Words.Add(W[0], W[1]);
			const FString Dir = FPaths::ProjectContentDir() / TEXT("IndependentResources/Studio/Localization");
			FString Base, Rest;
			if (!Out.Lang.Split(TEXT("-"), &Base, &Rest) && !Out.Lang.Split(TEXT("_"), &Base, &Rest)) Base = Out.Lang;
			ReadTable(Dir / Base / TEXT("studio.toml"), Out.Words);
			if (Base != Out.Lang) ReadTable(Dir / Out.Lang / TEXT("studio.toml"), Out.Words);
			return Out;
		}();
		return T;
	}

	/** ICU's default integer: digits grouped by three with a comma (zh, ja and en all group that way). */
	FString GroupDigits(int64 V)
	{
		const bool bNegative = V < 0;
		FString Digits = FString::Printf(TEXT("%lld"), bNegative ? -V : V);
		for (int32 I = Digits.Len() - 3; I > 0; I -= 3) Digits.InsertAt(I, TEXT(','));
		return bNegative ? TEXT("-") + Digits : Digits;
	}
}

FString OKStudioFormat(const FString& Pattern, std::initializer_list<FOKStudioArg> Args)
{
	FString Out;
	Out.Reserve(Pattern.Len() + 16);
	for (int32 I = 0; I < Pattern.Len(); ++I)
	{
		const TCHAR C = Pattern[I];
		if (C == TEXT('\''))
		{
			// ICU quoting: '' is one apostrophe, '{...}' is literal text.
			if (I + 1 < Pattern.Len() && Pattern[I + 1] == TEXT('\'')) { Out.AppendChar(TEXT('\'')); ++I; continue; }
			if (I + 1 < Pattern.Len() && (Pattern[I + 1] == TEXT('{') || Pattern[I + 1] == TEXT('}')))
			{
				const int32 End = Pattern.Find(TEXT("'"), ESearchCase::CaseSensitive, ESearchDir::FromStart, I + 1);
				if (End != INDEX_NONE) { Out += Pattern.Mid(I + 1, End - I - 1); I = End; continue; }
			}
			Out.AppendChar(C);
			continue;
		}
		if (C != TEXT('{')) { Out.AppendChar(C); continue; }
		const int32 End = Pattern.Find(TEXT("}"), ESearchCase::CaseSensitive, ESearchDir::FromStart, I + 1);
		if (End == INDEX_NONE) { Out += Pattern.Mid(I); break; }
		TArray<FString> Parts;
		Pattern.Mid(I + 1, End - I - 1).ParseIntoArray(Parts, TEXT(","), false);
		const FString Name = Parts.Num() ? Parts[0].TrimStartAndEnd() : FString();
		const FString Type = Parts.Num() > 1 ? Parts[1].TrimStartAndEnd() : FString();
		const FOKStudioArg* Arg = nullptr;
		for (const FOKStudioArg& A : Args) if (Name == A.Name) { Arg = &A; break; }
		if (!Arg || (!Type.IsEmpty() && Type != TEXT("number"))) { Out += Pattern.Mid(I, End - I + 1); I = End; continue; }
		Out += Arg->bNumber ? (Type == TEXT("number") ? GroupDigits(Arg->Number) : FString::Printf(TEXT("%lld"), Arg->Number)) : Arg->Text;
		I = End;
	}
	return Out;
}

FString OKStudioLanguage() { return Table().Lang; }

FString OKStudioT(const TCHAR* Id)
{
	if (const FString* W = Table().Words.Find(Id)) return *W;
	return Id;
}

FString OKStudioMsg(const TCHAR* Id, std::initializer_list<FOKStudioArg> Args)
{
	return OKStudioFormat(OKStudioT(Id), Args);
}
