#include "Misc/Base64.h"
#include "OKModKeys.h"
// The street's side of the OK mod hooks (Docs/OK_MOD_HOOKS.md §8, OK mod plan §6.6). Everything goes to the mod host as
// JSON hooks named street.*; with mods off (-NoMods, no host, a self-test) nothing here does anything.
//
// - Rules only record (plan §6.6): a mod hears what happened (a new day, a talk begun or ended, an invitation, a call, a
//   gift, a voice line) and may answer with facts for her next turn (street.talk_facts, put in the changing part of the
//   prompt, the 【今天】 line), a notice, or a subtitle. What she says about it is the AI's. A mod never reads what the
//   player typed.
// - A mod's own state lives in the save's ext at ext.mods.<id>: an answer {"state": {...}} replaces it (null removes it),
//   and it is written with the save like every other ext field (the rules copy ext through untouched). After a save is
//   read (a new game, a slot loaded: the scene starts again), street.load hands each mod its state.
// - Namespaced rules: a rule named "<mod id>.<rule>" asked through OKRulesEval goes to that mod (street.rule), not to
//   ok-rules (OKRulesGlue: OKStreetModRule).
// - Her card's mod data (GameCustomFunctionController's per-heroine data, kept with her rather than with one save):
//   street.load hands each mod its own okMx section of every heroine's card ("section" in each heroine, null when none);
//   any answer {"cards": [{"heroine": id, "version", "data_b64"} | {"heroine": id, "remove": true}]} writes or removes
//   that mod's section of her card (FOkSession::SetCardModSection: other mods' sections and her identity stay). Her own
//   card, not the clinic's copy: the copy is made again from it (OKStreetSocialClinic.inl), so write rarely.

namespace
{
bool OKStreetModsOn(const FOKStreetSceneState& S)
{
	if(S.SelfTest||S.RetargetSelfTest)return false;
	const FOKModHost& Host=FOKModHost::Get();
	return Host.IsOpen()&&(Host.CurrentMode()==TEXT("street")||Host.CurrentMode()==TEXT("pair"));
}

TSharedPtr<FJsonObject> OKStreetParseExt(const FString& Ext)
{
	TSharedPtr<FJsonObject> E;
	if(Ext.IsEmpty()||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Ext),E)||!E.IsValid())E=MakeShared<FJsonObject>();
	return E;
}

// The mods subscribed to a hook (the host's list), in its order.
TArray<FString> OKStreetModSubscribers(const TCHAR* Hook)
{
	TArray<FString> Out;
	const TSharedPtr<FJsonObject> L=FOKModHost::Get().List();
	const TArray<TSharedPtr<FJsonValue>>* Mods=nullptr;
	if(!L.IsValid()||!L->TryGetArrayField(TEXT("mods"),Mods))return Out;
	for(const auto& M:*Mods)
	{
		const TSharedPtr<FJsonObject> O=M->AsObject();if(!O.IsValid()||O->GetStringField(TEXT("state"))!=TEXT("enabled"))continue;
		TArray<FString> Subs;O->TryGetStringArrayField(TEXT("subscriptions"),Subs);
		if(Subs.Contains(Hook))Out.Add(O->GetStringField(TEXT("id")));
	}
	return Out;
}

TSharedPtr<FJsonObject> OKStreetModAsk(const FString& Hook,const TSharedRef<FJsonObject>& Payload,const TArray<FString>& Only)
{
	auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("op"),TEXT("hook"));R->SetStringField(TEXT("hook"),Hook);R->SetObjectField(TEXT("payload"),Payload);
	if(Only.Num()){TArray<TSharedPtr<FJsonValue>> Ids;for(const FString& Id:Only)Ids.Add(MakeShared<FJsonValueString>(Id));R->SetArrayField(TEXT("mods"),Ids);}
	FString Error;const TSharedPtr<FJsonObject> Answer=FOKModHost::Get().DispatchJson(R,Error);
	if(!Answer.IsValid())UE_LOG(LogOKMod,Warning,TEXT("street %s: %s"),*Hook,*Error);
	return Answer;
}
}

// "<mod id>.<rule>": the mod's own rule (street.rule), answered like an ok-rules rule. Null when the name is not a mod's.
TSharedPtr<FJsonObject> OKStreetModRule(const TSharedRef<FJsonObject>& Request)
{
	const FString Rule=Request->GetStringField(TEXT("rule"));
	int32 Dot;if(!Rule.FindLastChar(TEXT('.'),Dot)||!FOKModHost::Get().IsOpen())return nullptr;
	const FString Mod=Rule.Left(Dot);
	if(!OKStreetModSubscribers(TEXT("street.rule")).Contains(Mod))return nullptr;
	auto Payload=MakeShared<FJsonObject>();Payload->SetStringField(TEXT("rule"),Rule.Mid(Dot+1));Payload->SetObjectField(TEXT("request"),Request);
	const TSharedPtr<FJsonObject> Answer=OKStreetModAsk(TEXT("street.rule"),Payload,{Mod});
	const TArray<TSharedPtr<FJsonValue>>* Replies=nullptr;
	if(!Answer.IsValid()||!Answer->TryGetArrayField(TEXT("replies"),Replies)||Replies->IsEmpty())return nullptr;
	const TSharedPtr<FJsonObject> Reply=(*Replies)[0]->AsObject();bool bOk=false;
	if(!Reply.IsValid()||!Reply->TryGetBoolField(TEXT("ok"),bOk)||!bOk){UE_LOG(LogOKMod,Warning,TEXT("street rule %s: %s"),*Rule,Reply.IsValid()?*Reply->GetStringField(TEXT("error")):TEXT("no answer"));return nullptr;}
	const TSharedPtr<FJsonObject>* Json=nullptr;
	return Reply->TryGetObjectField(TEXT("json"),Json)?*Json:MakeShared<FJsonObject>();
}

// Her own card (the clinic's copy is made from it), else the card she is shown with.
static FString OKStreetModCard(const FOKStreetSceneState& S,int32 Girl)
{
	if(S.BaseCards.IsValidIndex(Girl)&&!S.BaseCards[Girl].IsEmpty())
	{
		const FString Full=FPaths::ConvertRelativePathToFull(S.BaseCards[Girl]);
		if(IFileManager::Get().FileExists(*Full))return Full;
	}
	return OKStreetCardFor(S,Girl);
}

// A mod's {"cards": [...]}: its section of each named heroine's card written or removed.
static void OKStreetModWriteCards(const FOKStreetSceneState& S,const FString& Mod,const TArray<TSharedPtr<FJsonValue>>& Cards)
{
	for(const TSharedPtr<FJsonValue>& V:Cards)
	{
		const TSharedPtr<FJsonObject> O=V.IsValid()?V->AsObject():nullptr;if(!O.IsValid())continue;
		const FString Her=O->GetStringField(TEXT("heroine"));
		int32 Girl=INDEX_NONE;
		for(int32 I=1;I<S.Manifest.Characters.Num();++I)if(OKStreetStableId(S.Manifest.Characters[I])==Her){Girl=I;break;}
		const FString Card=Girl==INDEX_NONE?FString():OKStreetModCard(S,Girl);
		if(Card.IsEmpty()){UE_LOG(LogOKMod,Warning,TEXT("[%s] cards: no card for heroine %s"),*Mod,*Her);continue;}
		bool bRemove=false;O->TryGetBoolField(TEXT("remove"),bRemove);
		TArray<uint8> Bytes;double Version=1;O->TryGetNumberField(TEXT("version"),Version);
		FString B64;
		if(!bRemove&&(!O->TryGetStringField(TEXT("data_b64"),B64)||!FBase64::Decode(B64,Bytes))){UE_LOG(LogOKMod,Warning,TEXT("[%s] cards: %s has no data_b64"),*Mod,*Her);continue;}
		if(Bytes.Num()>1024*1024){UE_LOG(LogOKMod,Warning,TEXT("[%s] cards: %d bytes for %s, over 1 MiB"),*Mod,Bytes.Num(),*Her);continue;}
		FString Error;
		if(!FOkSession::SetCardModSection(Card,Mod,int32(Version),Bytes,bRemove,Error)){UE_LOG(LogOKMod,Warning,TEXT("[%s] cards: %s: %s"),*Mod,*Card,*Error);}
		else{UE_LOG(LogOKMod,Display,TEXT("[%s] %s its data in %s's card (%d bytes)"),*Mod,bRemove?TEXT("removed"):TEXT("wrote"),*Her,Bytes.Num());}
	}
}

// What every street hook carries: the day, the date, the time, the language.
TSharedRef<FJsonObject> AOKStreetSocialScene::ModsPayload() const
{
	const auto& S=*State;auto P=MakeShared<FJsonObject>();
	const FDateTime D=OKStreetCalendarDateTime(S.Store.CalendarDay,12.0);
	P->SetNumberField(TEXT("day"),S.Store.CalendarDay);P->SetStringField(TEXT("date"),FString::Printf(TEXT("%04d-%02d-%02d"),D.GetYear(),D.GetMonth(),D.GetDay()));
	P->SetNumberField(TEXT("minute"),double(OKStreetMindNow(S)%1440));P->SetStringField(TEXT("lang"),GOKStreetLang);
	return P;
}

// One heroine as the mods see her: her stable id, name and birthday (MM-DD, from her profile).
TSharedRef<FJsonObject> AOKStreetSocialScene::ModsHeroine(int32 Character) const
{
	const auto& S=*State;auto H=MakeShared<FJsonObject>();
	if(!S.Manifest.Characters.IsValidIndex(Character))return H;
	H->SetStringField(TEXT("id"),OKStreetStableId(S.Manifest.Characters[Character]));H->SetStringField(TEXT("name"),S.Manifest.Characters[Character].Name);
	TArray<FString> P;OKStreetProfileString(ProfileOf(Character),nullptr,TEXT("birthday")).ParseIntoArray(P,TEXT("-"));
	if(P.Num()==3)H->SetStringField(TEXT("birthday"),FString::Printf(TEXT("%02d-%02d"),FCString::Atoi(*P[1]),FCString::Atoi(*P[2])));
	return H;
}

// A hook to every subscriber (or the listed mods); what each answers is done here. The answers come back for a caller
// that reads more of them (talk facts).
TSharedPtr<FJsonObject> AOKStreetSocialScene::ModsHook(const TCHAR* Name,const TSharedRef<FJsonObject>& Payload,const TArray<FString>& Only)
{
	if(!State||!OKStreetModsOn(*State))return nullptr;
	auto& S=*State;
	if(!S.ModsLoaded&&FCString::Strcmp(Name,TEXT("street.load"))!=0)ModsEnsureLoaded();
	const TSharedPtr<FJsonObject> Answer=OKStreetModAsk(Name,Payload,Only);
	const TArray<TSharedPtr<FJsonValue>>* Replies=nullptr;
	if(!Answer.IsValid()||!Answer->TryGetArrayField(TEXT("replies"),Replies))return Answer;
	if(Replies->Num()&&FCString::Strcmp(Name,TEXT("street.talk_facts"))!=0)UE_LOG(LogOKMod,Display,TEXT("street hook %s: %d mod(s)"),Name,Replies->Num());
	for(const auto& R:*Replies)
	{
		const TSharedPtr<FJsonObject> O=R->AsObject();if(!O.IsValid())continue;
		const FString Mod=O->GetStringField(TEXT("mod"));bool bOk=false;O->TryGetBoolField(TEXT("ok"),bOk);
		if(!bOk){UE_LOG(LogOKMod,Warning,TEXT("[%s] %s: %s"),*Mod,Name,*O->GetStringField(TEXT("error")));continue;}
		const TSharedPtr<FJsonObject>* Json=nullptr;if(O->TryGetObjectField(TEXT("json"),Json))ModsFollow(Mod,*Json);
	}
	return Answer;
}

// What one mod's answer asks of the street (a hook's or a hotkey's): {"cards": [...]} her card data, {"state": ...}
// its ext.mods.<id> (null removes it), {"notice": text}, {"subtitle": {"text"}}.
void AOKStreetSocialScene::ModsFollow(const FString& Mod,const TSharedPtr<FJsonObject>& Json)
{
	if(!State||!Json.IsValid())return;
	auto& S=*State;
	const TArray<TSharedPtr<FJsonValue>>* Cards=nullptr;
	if(Json->TryGetArrayField(TEXT("cards"),Cards))OKStreetModWriteCards(S,Mod,*Cards);
	if(const TSharedPtr<FJsonValue> State_=Json->TryGetField(TEXT("state")))
	{
		const TSharedPtr<FJsonObject> Ext=OKStreetParseExt(S.Store.Ext);
		const TSharedPtr<FJsonObject>* ModsObj=nullptr;TSharedPtr<FJsonObject> Mods=Ext->TryGetObjectField(TEXT("mods"),ModsObj)?*ModsObj:MakeShared<FJsonObject>();
		if(State_->Type==EJson::Null)Mods->RemoveField(Mod);else Mods->SetField(Mod,State_);
		Ext->SetObjectField(TEXT("mods"),Mods);
		FString Out;auto W=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out);FJsonSerializer::Serialize(Ext.ToSharedRef(),W);S.Store.Ext=Out;
	}
	FString Notice;
	if(Json->TryGetStringField(TEXT("notice"),Notice)&&!Notice.IsEmpty()){S.Message=Notice;UE_LOG(LogOKMod,Display,TEXT("[%s] street notice: %s"),*Mod,*Notice);}
	const TSharedPtr<FJsonObject>* Subtitle=nullptr;FString Line;
	if(Json->TryGetObjectField(TEXT("subtitle"),Subtitle)&&(*Subtitle)->TryGetStringField(TEXT("text"),Line)&&!Line.IsEmpty())
	{
		// The street's own message line (screen debug messages are off in a shipped game); her dialogue box shows the
		// line too, so a subtitle mod matters most where that box is hidden.
		S.Message=Line.Replace(TEXT("\n"),TEXT(" "));Notice=S.Message;
	}
	if(!Notice.IsEmpty())RefreshUI();
}

// The mods' street tables (Mods/<id>/street/*.toml, the host's street_data op; Docs/OK_MOD_C_WAVE6.md), asked once:
// - goods and gifts go into the catalog the shops sell from, after the built-in ones (an item whose shop is not a known
//   place, or whose id is a built-in one, is left out and logged); the rules get the same rows (catalog_extend, in
//   ModsTick once they are up) so prices, gifts and taste work on them too;
// - topics become a block of material at the end of her system prompt's world part: the same every turn (the cached
//   prefix stays whole), used by the AI when they fit, never rules.
// Called after every LoadCatalog (a new region reads the catalog again) and on the first ModsTick.
void AOKStreetSocialScene::ModsMergeStreetData()
{
	if(!State||!OKStreetModsOn(*State))return;
	auto& S=*State;
	if(!S.ModsStreetData.IsValid())
	{
		auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("op"),TEXT("street_data"));
		FString Error;S.ModsStreetData=FOKModHost::Get().DispatchJson(R,Error);
		if(!S.ModsStreetData.IsValid()){UE_LOG(LogOKMod,Warning,TEXT("street data: %s"),*Error);S.ModsStreetData=MakeShared<FJsonObject>();return;}
		const TArray<TSharedPtr<FJsonValue>>* Problems=nullptr;
		if(S.ModsStreetData->TryGetArrayField(TEXT("problems"),Problems))for(const auto& P:*Problems)if(const auto O=P->AsObject())
			UE_LOG(LogOKMod,Warning,TEXT("[%s] street/%s: %s"),*O->GetStringField(TEXT("mod")),*O->GetStringField(TEXT("file")),*O->GetStringField(TEXT("error")));
	}
	int32 Added=0;S.ModsRuleItems.Reset();
	const TArray<TSharedPtr<FJsonValue>>* Items=nullptr;
	if(S.ModsStreetData->TryGetArrayField(TEXT("items"),Items))for(const auto& V:*Items)
	{
		const TSharedPtr<FJsonObject> O=V->AsObject();FOKStreetCatalogItem I;
		if(!OKStreetCatalogItemFrom(O,I))continue;
		const FString Mod=O->GetStringField(TEXT("mod"));
		const FOKStreetCatalogItem* Same=S.Catalog.Find(I.Id);
		if(Same&&!Same->Id.StartsWith(Mod+TEXT(".")))continue;	// a built-in id: not shadowed
		if(!S.Catalog.Places.Contains(I.Place)&&!OKStreetFindPlace(I.Place)){UE_LOG(LogOKMod,Warning,TEXT("[%s] street item %s: no shop \"%s\""),*Mod,*I.Id,*I.Place);continue;}
		// Its name in the street's language when the table gives one ({"names": {"en": ...}}).
		const TSharedPtr<FJsonObject>* Names=nullptr;FString Local;
		if(O->TryGetObjectField(TEXT("names"),Names)&&(*Names)->TryGetStringField(GOKStreetLang,Local)&&!Local.IsEmpty())I.Name=Local;
		S.ModsRuleItems.Add(V);
		if(Same)continue;	// merged before (LoadCatalog again keeps it)
		S.Catalog.Items.Add(MoveTemp(I));++Added;
	}
	// Topics of this language (or of every language), one line each.
	TArray<FString> Lines;
	const TArray<TSharedPtr<FJsonValue>>* Topics=nullptr;
	if(S.ModsStreetData->TryGetArrayField(TEXT("topics"),Topics))for(const auto& V:*Topics)if(const auto O=V->AsObject())
	{
		FString Lang;O->TryGetStringField(TEXT("lang"),Lang);
		// "zh-TW" is zh-TW's only; a bare "en" any English.
		if(!Lang.IsEmpty()&&Lang!=GOKStreetLang&&!(Lang.Len()==2&&GOKStreetLang.StartsWith(Lang)))continue;
		Lines.Add(TEXT("- ")+O->GetStringField(TEXT("text")));
	}
	S.ModsTopics=Lines.Num()?FString(TEXT("\n\n"))+OKT(TEXT("ui.director.mod_topics_header"))+TEXT("\n")+FString::Join(Lines,TEXT("\n")):FString();
	if(Added||Lines.Num())UE_LOG(LogOKMod,Display,TEXT("street data: %d item(s) into the catalog, %d topic line(s) for her prompt"),Added,Lines.Num());
}

// Mod hotkeys (FOKModKeys, Docs/OK_MOD_F_WAVE4.md §5): heard while the street runs, each answer followed like a hook's
// (a plain text answer shown on the message line). Stopped in EndPlay.
void AOKStreetSocialScene::ModsListenKeys()
{
	FOKModKeys::Listen(TEXT("street"),[Weak=TWeakObjectPtr<AOKStreetSocialScene>(this)](const FString& Mod,const TSharedPtr<FJsonObject>& Reply)
	{
		AOKStreetSocialScene* Self=Weak.Get();if(!Self||!Self->State||!Reply.IsValid())return;
		const TSharedPtr<FJsonObject>* Json=nullptr;
		if(Reply->TryGetObjectField(TEXT("json"),Json)){Self->ModsFollow(Mod,*Json);return;}
		const FString Text=FOKModKeys::ShownText(Reply);
		if(!Text.IsEmpty()){Self->State->Message=FString::Printf(TEXT("[%s] %s"),*Mod,*Text);Self->RefreshUI();}
	});
}

// After a save was read (the scene starts with it): street.load, each mod with its own ext.mods.<id> (null: a new game or a
// save from before the mod). Sent once per scene, before any other street hook.
void AOKStreetSocialScene::ModsEnsureLoaded()
{
	if(!State||State->ModsLoaded||!OKStreetModsOn(*State))return;
	auto& S=*State;S.ModsLoaded=true;
	const TSharedPtr<FJsonObject> Ext=OKStreetParseExt(S.Store.Ext);
	const TSharedPtr<FJsonObject>* Mods=nullptr;Ext->TryGetObjectField(TEXT("mods"),Mods);
	TArray<TSharedPtr<FJsonValue>> Heroines;for(int32 I=1;I<S.Manifest.Characters.Num();++I)Heroines.Add(MakeShared<FJsonValueObject>(ModsHeroine(I)));
	for(const FString& Id:OKStreetModSubscribers(TEXT("street.load")))
	{
		// Each heroine with this mod's section of her card.
		TArray<TSharedPtr<FJsonValue>> Own;
		for(int32 I=1;I<S.Manifest.Characters.Num();++I)
		{
			auto H=MakeShared<FJsonObject>(*Heroines[I-1]->AsObject());
			const FString Card=OKStreetModCard(S,I);bool bFound=false;int32 Version=0;TArray<uint8> Bytes;FString Error;
			if(!Card.IsEmpty()&&FOkSession::CardModSection(Card,Id,bFound,Version,Bytes,Error)&&bFound)
			{auto Sec=MakeShared<FJsonObject>();Sec->SetNumberField(TEXT("version"),Version);Sec->SetStringField(TEXT("data_b64"),FBase64::Encode(Bytes));H->SetObjectField(TEXT("section"),Sec);}
			else{H->SetField(TEXT("section"),MakeShared<FJsonValueNull>());if(!Error.IsEmpty())UE_LOG(LogOKMod,Warning,TEXT("[%s] card data of %s: %s"),*Id,*Card,*Error);}
			Own.Add(MakeShared<FJsonValueObject>(H));
		}
		auto P=ModsPayload();P->SetArrayField(TEXT("heroines"),Own);P->SetBoolField(TEXT("new_game"),S.ModsNewGame);
		const TSharedPtr<FJsonValue> Saved=Mods?(*Mods)->TryGetField(Id):nullptr;P->SetField(TEXT("state"),Saved.IsValid()?Saved:MakeShared<FJsonValueNull>());
		ModsHook(TEXT("street.load"),P,{Id});
	}
	UE_LOG(LogOKMod,Display,TEXT("street: mods given their saved state (%d heroines)"),Heroines.Num());
}

// The part of the day (GameAPI PeriodChange): morning 5–11, day 11–17, evening 17–20, night 20–5.
static const TCHAR* OKStreetModPeriod(int32 Minute)
{
	const int32 H=(Minute%1440)/60;
	return H>=5&&H<11?TEXT("morning"):H>=11&&H<17?TEXT("day"):H>=17&&H<20?TEXT("evening"):TEXT("night");
}

// Twice a second: street.period_change when the part of the day turns, street.arrive when he comes into a place
// (a named place of the map; walking out of every place is not an arrival). The first look only records.
void AOKStreetSocialScene::ModsTick()
{
	if(!State||!OKStreetModsOn(*State))return;
	auto& S=*State;const double Now=FPlatformTime::Seconds();
	if(Now<S.ModsTickAt)return;
	const bool bFirst=S.ModsTickAt<=0;
	S.ModsTickAt=Now+.5;
	const int32 Minute=int32(OKStreetMindNow(S)%1440);
	const FString Period=OKStreetModPeriod(Minute);
	// The first look records the period and his place; arrivals count from there. (It used to wait for street.load,
	// which only another hook sends: with no talk or day change first, no arrival was ever told.)
	if(bFirst){S.ModsPeriod=Period;S.ModsPlace=PlaceHere(S.Male);ModsListenKeys();ModsMergeStreetData();return;}
	// The rules learn the mods' goods once they are up (catalog_extend: priced per region, found by the gift rules).
	if(!S.ModsRulesExtended&&S.Rules&&S.ModsStreetData.IsValid())
	{
		S.ModsRulesExtended=true;
		if(S.ModsRuleItems.Num())
		{
			auto R=OKRulesRequest(TEXT("catalog_extend"));R->SetArrayField(TEXT("items"),S.ModsRuleItems);
			const TSharedPtr<FJsonObject> A=OKRulesEval(S,R);
			UE_LOG(LogOKMod,Display,TEXT("street data: the rules know %d of %d mod item(s)"),A.IsValid()?int32(A->GetNumberField(TEXT("known"))):0,S.ModsRuleItems.Num());
		}
	}
	if(Period!=S.ModsPeriod)
	{
		auto P=ModsPayload();P->SetStringField(TEXT("period"),Period);P->SetStringField(TEXT("previous"),S.ModsPeriod);
		S.ModsPeriod=Period;ModsHook(TEXT("street.period_change"),P);
	}

	const FString Here=PlaceHere(S.Male);
	if(Here==S.ModsPlace)return;
	const FString Was=S.ModsPlace;S.ModsPlace=Here;
	if(Here.IsEmpty())return;	// ModsHook sends street.load first when it was not yet
	auto P=ModsPayload();P->SetStringField(TEXT("who"),TEXT("him"));P->SetStringField(TEXT("place"),Here);P->SetStringField(TEXT("from"),Was);
	if(const FOKStreetPlace* Place=OKStreetFindPlace(Here))P->SetStringField(TEXT("place_name"),Place->Name);
	// Who is with him (the girl on an outing or in a talk): the heroine a place event is about, when there is one.
	const int32 With=S.OutingGirl!=INDEX_NONE?S.OutingGirl:S.Target;
	if(S.Manifest.Characters.IsValidIndex(With)&&With>0)P->SetObjectField(TEXT("heroine"),ModsHeroine(With));
	ModsHook(TEXT("street.arrive"),P);
}

// One event with one heroine (talk, invitation, call, gift, voice line).
void AOKStreetSocialScene::ModsHeroineEvent(const TCHAR* Name,int32 Character,const TFunction<void(FJsonObject&)>& More)
{
	if(!State||!OKStreetModsOn(*State)||!State->Manifest.Characters.IsValidIndex(Character))return;
	auto P=ModsPayload();P->SetObjectField(TEXT("heroine"),ModsHeroine(Character));
	if(More)More(*P);
	ModsHook(Name,P);
}

// The day began (NextDay): street.day_change with every heroine.
void AOKStreetSocialScene::ModsDayChanged()
{
	if(!State||!OKStreetModsOn(*State))return;
	auto& S=*State;auto P=ModsPayload();
	TArray<TSharedPtr<FJsonValue>> Heroines;for(int32 I=1;I<S.Manifest.Characters.Num();++I)Heroines.Add(MakeShared<FJsonValueObject>(ModsHeroine(I)));
	P->SetArrayField(TEXT("heroines"),Heroines);
	ModsHook(TEXT("street.day_change"),P);
}

// What the mods want her to know on her turn (street.talk_facts, answers {"facts": [..]}): lines for the 【今天】 part of
// her prompt, which changes turn to turn anyway (the cached prefix stays as it was).
TArray<FString> AOKStreetSocialScene::ModsTalkFacts(int32 Character) const
{
	TArray<FString> Out;
	if(!State||!OKStreetModsOn(*State)||!State->Manifest.Characters.IsValidIndex(Character))return Out;
	auto* Self=const_cast<AOKStreetSocialScene*>(this);
	auto P=ModsPayload();P->SetObjectField(TEXT("heroine"),ModsHeroine(Character));
	const TSharedPtr<FJsonObject> Answer=Self->ModsHook(TEXT("street.talk_facts"),P);
	const TArray<TSharedPtr<FJsonValue>>* Replies=nullptr;
	if(!Answer.IsValid()||!Answer->TryGetArrayField(TEXT("replies"),Replies))return Out;
	for(const auto& R:*Replies)
	{
		const TSharedPtr<FJsonObject> O=R->AsObject();const TSharedPtr<FJsonObject>* Json=nullptr;const TArray<TSharedPtr<FJsonValue>>* Facts=nullptr;
		if(O.IsValid()&&O->TryGetObjectField(TEXT("json"),Json)&&(*Json)->TryGetArrayField(TEXT("facts"),Facts))
			for(const auto& F:*Facts){FString Text=F->AsString().TrimStartAndEnd();if(!Text.IsEmpty()&&Out.Num()<8)Out.Add(Text.Left(200));}
	}
	return Out;
}
