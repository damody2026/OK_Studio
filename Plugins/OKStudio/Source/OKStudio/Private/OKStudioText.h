#pragma once

// OK Studio's words in the player's language, from text tables:
// Content/IndependentResources/Studio/Localization/<lang>/studio.toml, one `id = "ICU message"` per line (the same form
// as the story player's story.toml, Tools/ok-story tuning.rs Words). The language comes from OK_STUDIO_LANG, else the
// Unreal culture: zh* -> zh, ja* -> ja, en* -> en, anything else zh. A table for "zh" and then one for the full name
// (for example "zh-CN") are read over the built-in Chinese; an id no table has shows as itself.
//
//   OKStudioT(TEXT("load.title"))                                   a message without arguments
//   OKStudioMsg(TEXT("load.progress"), {{TEXT("built"), 3}, ...})   with named arguments
//
// The formatter takes the simple arguments of ICU MessageFormat: {name} and {name, number} (integers group by the
// language's rule, as ICU's default number). plural / select are not read here; a table that uses them shows the
// pattern as it is, so keep this module's messages to simple arguments.
#include "CoreMinimal.h"
#include <initializer_list>

struct FOKStudioArg
{
	const TCHAR* Name;
	FString Text;
	bool bNumber = false;
	int64 Number = 0;
	FOKStudioArg(const TCHAR* InName, const FString& V) : Name(InName), Text(V) {}
	FOKStudioArg(const TCHAR* InName, const TCHAR* V) : Name(InName), Text(V ? V : TEXT("")) {}
	FOKStudioArg(const TCHAR* InName, int32 V) : Name(InName), bNumber(true), Number(V) {}
	FOKStudioArg(const TCHAR* InName, int64 V) : Name(InName), bNumber(true), Number(V) {}
};

/** The message, or the id when no table has it. */
FString OKStudioT(const TCHAR* Id);
/** The message with its arguments put in. */
FString OKStudioMsg(const TCHAR* Id, std::initializer_list<FOKStudioArg> Args);
/** The language the tables are read for ("zh", "en", "ja" or a full name such as "zh-CN"). */
FString OKStudioLanguage();
/** Formats an ICU pattern (simple arguments only) without a table, for tests. */
FString OKStudioFormat(const FString& Pattern, std::initializer_list<FOKStudioArg> Args);
