#pragma once

#include "CoreMinimal.h"
#include "Dom/JsonObject.h"

// The card reader's words from the shared text tables (Content/IndependentResources/StreetSocialData/Localization/
// <lang>/*.toml, ICU MessageFormat, formatted by ok-rules as the street's OKT/OKMsg are). The reader opens the rules
// itself when nothing has (a private copy of the DLL, as the one-on-one does), on the first word asked for.
// Without the rules the id itself is shown, so a missing table never hides a control.

// The reader's language: -ReaderLang=<lang>, else what was last chosen (Saved/CardReader/language.txt), else zh-TW.
FString OKReaderLanguage();
// Sets (and keeps) the reader's language; the words asked for afterwards are in it. False: not one of OKReaderLanguages.
bool OKReaderSetLanguage(const FString& Lang);
// The languages the tables have: code and the language's own name.
const TArray<TPair<FString, FString>>& OKReaderLanguages();
// Changes each time the language does (callers rebuild text they cached).
int32 OKReaderLanguageGeneration();

// A message without arguments in the reader's language; Id when the rules or the id are missing.
FString OKReaderT(const FString& Id);
// A message with ICU arguments ({name} / {count, plural, ...}); Id when the rules or the id are missing.
FString OKReaderMsg(const FString& Id, const TSharedPtr<FJsonObject>& Args);
