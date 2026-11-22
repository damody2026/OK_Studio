#include "OKReaderMods.h"

#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "OKCharacterController.h"
#include "OKCharacterMCPRegistry.h"
#include "OKModContent.h"
#include "OKModHost.h"
#include "OKReaderText.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "ok_extract.h"
#include "Containers/Ticker.h"
#include "Framework/Application/SlateApplication.h"
#include "Engine/GameViewportClient.h"
#include "GameFramework/PlayerController.h"
#include "Widgets/SViewport.h"
#include "KKPreviewActor.h"

namespace
{
using FRows=TArray<TSharedPtr<FJsonValue>>;

TSharedPtr<FJsonObject> GUi;			// reader_ui, once the host answered it
TSharedPtr<FJsonObject> GValues;		// reader_values: key -> value
TSharedPtr<FJsonObject> GApply;			// Saved/CardReader/mod_apply.json
FString GCard;int32 GOutfit=-1;
TMap<int32,FString> GOutfitNames;	// of GCard

TSharedPtr<FJsonObject> Ask(const TSharedRef<FJsonObject>& Request)
{
	if(!OKReaderMods::Active())return nullptr;
	FString Error;
	TSharedPtr<FJsonObject> Answer=FOKModHost::Get().DispatchJson(Request,Error);
	if(!Answer.IsValid())UE_LOG(LogOKMod,Warning,TEXT("reader: %s"),*Error);
	return Answer;
}
TSharedRef<FJsonObject> Op(const TCHAR* Name){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("op"),Name);return O;}

FString ApplyFile(){return FPaths::ProjectSavedDir()/TEXT("CardReader/mod_apply.json");}
FJsonObject& ApplySettings()
{
	if(!GApply.IsValid())
	{
		FString Text;
		if(!FFileHelper::LoadFileToString(Text,*ApplyFile())||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),GApply)||!GApply.IsValid())GApply=MakeShared<FJsonObject>();
	}
	return *GApply;
}

void RefreshValues()
{
	GValues=Ask(Op(TEXT("reader.values")));
	if(!GValues.IsValid())GValues=MakeShared<FJsonObject>();	// asked again on the next card, not every frame
}

// {"ops":[...]}: the original editor's composite actions (hair_base_color, ...; Docs/READER_UI_APPEARANCE_API.md §10),
// applied the way the detailed editor applies them (UOKCharacterController::ApplyPropertyOps: one write of the card, then
// it opens again). The detailed editor need not have been opened: ops work on the card file, not on its rows, so the
// source is taken to be the card shown now (rows read for another card are dropped and read again when it opens).
// While the reader is busy (a load, the slider edits of the same reply) they wait for it, up to 30 seconds.
void ApplyOps(UOKCharacterController* G,const FString& Mod,const TArray<TSharedPtr<FJsonValue>>& Ops)
{
	if(!G)return;
	const double Until=FPlatformTime::Seconds()+30;
	FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak=TWeakObjectPtr<UOKCharacterController>(G),Mod,Ops,Until](float)
	{
		UOKCharacterController* C=Weak.Get();if(!C)return false;
		const bool bBusy=C->bPropertyBusy||C->bAppearanceBusy||C->bLoadInFlight||C->bAnimationPreparing;
		if(bBusy&&FPlatformTime::Seconds()<Until)return true;
		FString Refused=bBusy?FString(TEXT("the reader stayed busy for 30 seconds")):FString();
		if(Refused.IsEmpty()&&C->Entries.IsValidIndex(C->SelectedIndex)&&(C->PropertySource!=C->Entries[C->SelectedIndex].Path||C->PropertyOutfit!=C->OutfitIndex))
		{
			if(!C->PendingProperties.IsEmpty())Refused=TEXT("the detailed editor has edits not applied yet");
			else{C->EditorProperties.Reset();C->PropertySource=C->Entries[C->SelectedIndex].Path;C->PropertyOutfit=C->OutfitIndex;}
		}
		if(Refused.IsEmpty())Refused=C->ApplyPropertyOps(Ops);
		if(!Refused.IsEmpty())
		{
			UE_LOG(LogOKMod,Warning,TEXT("[%s] ops not applied: %s"),*Mod,*Refused);
			C->ScreenNote(43,8.f,FColor::Yellow,FString::Printf(TEXT("[%s] %s"),*Mod,*Refused));
		}
		else UE_LOG(LogOKMod,Display,TEXT("[%s] %d op(s) applied"),*Mod,Ops.Num());
		return false;
	}));
}
// What a mod's reply asks of the reader: {"set":[{key,value}]} registry edits, {"ops":[...]}, {"notice": text},
// {"subtitle":{"text","seconds"}}.
void Follow(UOKCharacterController* G,const FString& Mod,const TSharedPtr<FJsonObject>& Json)
{
	if(!G||!Json.IsValid())return;
	const TArray<TSharedPtr<FJsonValue>>* Edits=nullptr;
	if(Json->TryGetArrayField(TEXT("set"),Edits)&&Edits->Num())
	{
		FString Error;
		if(!OKCharacterMCPRegistry::SetParameters(G,*Edits,Error))UE_LOG(LogOKMod,Warning,TEXT("[%s] edits not applied: %s"),*Mod,*Error);
	}
	const TArray<TSharedPtr<FJsonValue>>* Ops=nullptr;
	if(Json->TryGetArrayField(TEXT("ops"),Ops)&&Ops->Num())ApplyOps(G,Mod,*Ops);
	FString Notice;
	if(Json->TryGetStringField(TEXT("notice"),Notice)&&!Notice.IsEmpty())G->ScreenNote(40,6.f,FColor::Cyan,FString::Printf(TEXT("[%s] %s"),*Mod,*Notice));
	const TSharedPtr<FJsonObject>* Names=nullptr;
	if(Json->TryGetObjectField(TEXT("outfit_names"),Names))
	{
		for(const auto& N:(*Names)->Values)
		{
			const int32 Index=FCString::Atoi(*N.Key);FString Name;
			if(!N.Value.IsValid()||!N.Value->TryGetString(Name)||Name.TrimStartAndEnd().IsEmpty())GOutfitNames.Remove(Index);
			else GOutfitNames.Add(Index,Name.TrimStartAndEnd().Left(40));
		}
		G->RefreshOutfitList();
	}
	const TSharedPtr<FJsonObject>* Subtitle=nullptr;
	if(Json->TryGetObjectField(TEXT("subtitle"),Subtitle))
	{
		FString Text;double Seconds=4;(*Subtitle)->TryGetNumberField(TEXT("seconds"),Seconds);
		if((*Subtitle)->TryGetStringField(TEXT("text"),Text)&&!Text.IsEmpty())G->ScreenNote(41,float(FMath::Clamp(Seconds,.5,30.)),FColor::White,Text);
	}
}
void FollowReplies(UOKCharacterController* G,const TSharedPtr<FJsonObject>& Answer)
{
	const TArray<TSharedPtr<FJsonValue>>* Replies=nullptr;
	if(!Answer.IsValid()||!Answer->TryGetArrayField(TEXT("replies"),Replies))return;
	for(const TSharedPtr<FJsonValue>& R:*Replies)
	{
		const TSharedPtr<FJsonObject> O=R->AsObject();if(!O.IsValid())continue;
		const FString Mod=O->GetStringField(TEXT("mod"));bool bOk=false;O->TryGetBoolField(TEXT("ok"),bOk);
		if(!bOk){UE_LOG(LogOKMod,Warning,TEXT("[%s] %s"),*Mod,*O->GetStringField(TEXT("error")));continue;}
		const TSharedPtr<FJsonObject>* Json=nullptr;if(O->TryGetObjectField(TEXT("json"),Json))Follow(G,Mod,*Json);
	}
}

const TSharedPtr<FJsonObject>& Ui()
{
	if(!GUi.IsValid()&&OKReaderMods::Active())GUi=Ask(Op(TEXT("reader.ui")));
	return GUi;
}

// The items under a page or a container (group, row, tabs, scroll: Docs/OK_MOD_HOOKS.md §4), containers left out.
void LeafItems(const TArray<TSharedPtr<FJsonObject>>& In,TArray<TSharedPtr<FJsonObject>>& Out)
{
	for(const TSharedPtr<FJsonObject>& I:In)
	{
		const TArray<TSharedPtr<FJsonValue>>* Kids=nullptr;
		if(!I->TryGetArrayField(TEXT("items"),Kids)){Out.Add(I);continue;}
		TArray<TSharedPtr<FJsonObject>> Objects;
		for(const TSharedPtr<FJsonValue>& K:*Kids)if(K.IsValid()&&K->Type==EJson::Object)Objects.Add(K->AsObject());
		LeafItems(Objects,Out);
	}
}
// The registry kind of a mod item that holds a value a person sets; empty for one that only shows (label, progress, a
// list with nothing to pick, an image, a button).
FString RowKind(const TSharedPtr<FJsonObject>& I)
{
	FString Kind;I->TryGetStringField(TEXT("kind"),Kind);
	if(Kind==TEXT("toggle")||Kind==TEXT("bool"))return TEXT("bool");
	if(Kind==TEXT("dropdown")||Kind==TEXT("choice")||Kind==TEXT("radio"))return TEXT("choice");
	if(Kind==TEXT("list"))return I->HasField(TEXT("options"))?TEXT("choice"):FString();
	// A mod colour is "#RRGGBB" text (format says so), not the registry's 0..1 colour component.
	if(Kind==TEXT("text")||Kind==TEXT("color"))return TEXT("text");
	if(Kind.IsEmpty()||Kind==TEXT("number")||Kind==TEXT("slider"))return TEXT("number");
	return FString();
}
FString Text(const TSharedPtr<FJsonObject>& O,const TCHAR* Field)
{
	FString Id,Plain;O->TryGetStringField(*(FString(Field)+TEXT("_id")),Id);O->TryGetStringField(Field,Plain);
	if(!Id.IsEmpty()){const FString T=OKReaderT(Id);if(T!=Id||Plain.IsEmpty())return T;}
	return Plain;
}
}

bool OKReaderMods::Active()
{
	return FOKModHost::Get().IsOpen()&&FOKModHost::Get().CurrentMode()==TEXT("reader");
}

void OKReaderMods::Loaded(UOKCharacterController* G,const FString& Card,int32 Outfit)
{
	if(!Active()||Card.IsEmpty())return;
	const FString Full=FPaths::ConvertRelativePathToFull(Card);
	if(Full==GCard&&Outfit==GOutfit)return;
	// The card's mod material overrides (ok.materials), with its own fallback where the mod is not here.
	OKModContent::CardLoaded(Full);
	if(Full==GCard)
	{
		GOutfit=Outfit;
		auto R=Op(TEXT("hook"));R->SetStringField(TEXT("hook"),TEXT("reader.outfit_change"));
		auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("card"),Full);P->SetNumberField(TEXT("outfit"),Outfit);R->SetObjectField(TEXT("payload"),P);
		FollowReplies(G,Ask(R));RefreshValues();return;
	}
	// The card shown before is gone: reader.character_unload, so a mod drops what it kept of it.
	if(!GCard.IsEmpty())
	{
		auto U=Op(TEXT("hook"));U->SetStringField(TEXT("hook"),TEXT("reader.character_unload"));
		auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("card"),GCard);U->SetObjectField(TEXT("payload"),P);
		FollowReplies(G,Ask(U));
	}
	GCard=Full;GOutfit=Outfit;GOutfitNames.Reset();
	auto R=Op(TEXT("card_load"));R->SetStringField(TEXT("card"),Full);R->SetNumberField(TEXT("outfit"),Outfit);
	FRows Skip;for(const auto& M:CardMods())if(!ApplyOnLoad(M.Key))Skip.Add(MakeShared<FJsonValueString>(M.Key));
	R->SetArrayField(TEXT("skip_apply"),Skip);
	// An original card: the sections mods make from its KKEx (extract.kkex), handed over as if the card had them, so
	// what the player sees and what a save writes is what converting the card gives.
	{
		const FTCHARToUTF8 Path(*Full);
		const int32 Need=ok_kkex_mod_sections(Path.Get(),nullptr,0);
		if(Need>1)
		{
			TArray<ANSICHAR> Buffer;Buffer.SetNumZeroed(Need);
			TSharedPtr<FJsonObject> Imported;
			if(ok_kkex_mod_sections(Path.Get(),Buffer.GetData(),Need)==0&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(UTF8_TO_TCHAR(Buffer.GetData())),Imported)&&Imported.IsValid()&&Imported->Values.Num())
				R->SetObjectField(TEXT("imported"),Imported);
		}
	}
	const TSharedPtr<FJsonObject> Answer=Ask(R);
	FollowReplies(G,Answer);
	// The card uses mods that are not here: said, and their data stays in the card untouched (saved back as it was).
	const TArray<TSharedPtr<FJsonValue>>* Missing=nullptr;
	if(Answer.IsValid()&&Answer->TryGetArrayField(TEXT("missing"),Missing)&&Missing->Num())
	{
		TArray<FString> Names;
		for(const auto& M:*Missing){const auto O=M->AsObject();if(!O.IsValid())continue;FString V;O->TryGetStringField(TEXT("version"),V);Names.Add(V.IsEmpty()?O->GetStringField(TEXT("id")):O->GetStringField(TEXT("id"))+TEXT(" ")+V);}
		auto Args=MakeShared<FJsonObject>();Args->SetStringField(TEXT("mods"),FString::Join(Names,TEXT("、")));Args->SetNumberField(TEXT("count"),Names.Num());
		FString Note=OKReaderMsg(TEXT("reader.mods.missing"),Args);
		if(Note==TEXT("reader.mods.missing"))Note=TEXT("這張卡用到未安裝的 mod：")+FString::Join(Names,TEXT("、"));
		G->ScreenNote(42,10.f,FColor::Yellow,Note);
		UE_LOG(LogOKMod,Display,TEXT("reader: %s uses mods that are not here: %s"),*Full,*FString::Join(Names,TEXT(", ")));
	}
	RefreshValues();
}

void OKReaderMods::Saved(UOKCharacterController* G,const FString& Path)
{
	if(!Active())return;
	auto R=Op(TEXT("card_store"));R->SetStringField(TEXT("card"),FPaths::ConvertRelativePathToFull(Path));R->SetNumberField(TEXT("outfit"),GOutfit<0?0:GOutfit);
	const TSharedPtr<FJsonObject> Answer=Ask(R);
	OKModContent::CardSaved(FPaths::ConvertRelativePathToFull(Path));
	if(!Answer.IsValid())return;
	const TArray<TSharedPtr<FJsonValue>>* Errors=nullptr;
	if(Answer->TryGetArrayField(TEXT("errors"),Errors))for(const auto& E:*Errors)if(const auto O=E->AsObject())UE_LOG(LogOKMod,Warning,TEXT("[%s] not saved into the card: %s"),*O->GetStringField(TEXT("mod")),*O->GetStringField(TEXT("error")));
	const TArray<TSharedPtr<FJsonValue>>* Written=nullptr;
	if(Answer->TryGetArrayField(TEXT("written"),Written))UE_LOG(LogOKMod,Display,TEXT("reader: %d mod section(s) saved into %s"),Written->Num(),*Path);
}

// input.pointer (the boop example, Docs/OK_MOD_S11_FRAME.md): while the mouse sweeps over the character with no button
// down (a drag turns the camera), at most 20 times a second, and only while some mod subscribed (asked every 2 s).
// "Over" is the mouse ray crossing her bounds; the mod decides which bones the ray is near. Origin, direction and
// velocity are in her Unity skeleton space (metres, the space a frame call's world matrices use); the velocity is how
// the ray's point nearest her moved.
void OKReaderMods::Pointer(UOKCharacterController* G,AKKPreviewActor* Actor,float DeltaSeconds)
{
	static double AskedAt=-1e9,SentAt=0;static bool bListened=false;
	static TWeakObjectPtr<AKKPreviewActor> LastActor;static FVector LastPoint=FVector::ZeroVector;static bool bHadPoint=false;
	// Why nothing is sent (log LogOKMod Verbose), once per change.
	static const TCHAR* LastWhy=nullptr;
	auto Why=[](const TCHAR* W){if(W!=LastWhy){LastWhy=W;UE_LOG(LogOKMod,Verbose,TEXT("input.pointer: %s"),W);}};
	if(!Active()||!G||!IsValid(Actor)){bHadPoint=false;return;}
	const double Now=FPlatformTime::Seconds();
	if(Now-AskedAt>2)
	{
		AskedAt=Now;
		auto R=Op(TEXT("subscribers"));R->SetStringField(TEXT("hook"),TEXT("input.pointer"));
		FString Error;const TSharedPtr<FJsonObject> A=FOKModHost::Get().DispatchJson(R,Error);
		const TArray<TSharedPtr<FJsonValue>>* Mods=nullptr;
		bListened=A.IsValid()&&A->TryGetArrayField(TEXT("mods"),Mods)&&Mods->Num()>0;
	}
	if(!bListened){bHadPoint=false;Why(TEXT("no subscriber"));return;}
	APlayerController* PC=G->GetOwningPlayer();
	if(!PC||!FSlateApplication::IsInitialized()){bHadPoint=false;Why(TEXT("no player controller"));return;}
	const TSet<FKey>& Down=FSlateApplication::Get().GetPressedMouseButtons();
	FVector Origin,Dir;
	if(Down.Num()){bHadPoint=false;Why(TEXT("a mouse button is down"));return;}
	// The cursor from Slate, not the viewport's own mouse position: with the reader screen on top the viewport only
	// knows the mouse for the frame it moved.
	UGameViewportClient* VC=G->GetWorld()?G->GetWorld()->GetGameViewport():nullptr;
	const TSharedPtr<SViewport> Widget=VC?VC->GetGameViewportWidget():nullptr;
	FVector2D Pixel=FVector2D::ZeroVector;bool bInside=false;
	if(Widget.IsValid()&&VC->Viewport)
	{
		const FGeometry& Geo=Widget->GetTickSpaceGeometry();
		const FVector2D Local=Geo.AbsoluteToLocal(FSlateApplication::Get().GetCursorPos()),Size=Geo.GetLocalSize();
		const FIntPoint ViewSize=VC->Viewport->GetSizeXY();
		bInside=Size.X>0&&Size.Y>0&&Local.X>=0&&Local.Y>=0&&Local.X<Size.X&&Local.Y<Size.Y;
		if(bInside)Pixel=Local*FVector2D(ViewSize.X/Size.X,ViewSize.Y/Size.Y);
	}
	if(!bInside||!PC->DeprojectScreenPositionToWorld(Pixel.X,Pixel.Y,Origin,Dir)){bHadPoint=false;Why(TEXT("the mouse is not in the viewport"));return;}
	const FBox Box=Actor->GetComponentsBoundingBox(true,true);
	FVector Hit,Normal;float Time=0;
	if(!Box.IsValid||!FMath::LineExtentBoxIntersection(Box,Origin,Origin+Dir*100000.,FVector::ZeroVector,Hit,Normal,Time))
	{
		static double ToldAt=0;
		if(Now-ToldAt>1){ToldAt=Now;UE_LOG(LogOKMod,VeryVerbose,TEXT("input.pointer: ray %s %s pixel %s, her bounds %s"),*Origin.ToString(),*Dir.ToString(),*Pixel.ToString(),*Box.ToString());}
		bHadPoint=false;Why(TEXT("not over her"));return;
	}
	// The ray's point nearest her middle: its movement is the sweep.
	const FVector Point=Origin+Dir*FMath::Max(0.,FVector::DotProduct(Box.GetCenter()-Origin,Dir));
	const bool bSame=bHadPoint&&LastActor.Get()==Actor;
	const FVector Moved=bSame?Point-LastPoint:FVector::ZeroVector;
	if(bSame&&Now-SentAt<.05)return;	// keep LastPoint: the next send measures the whole stretch
	const double Seconds=FMath::Max(Now-SentAt,1e-3);
	LastPoint=Point;LastActor=Actor;bHadPoint=true;SentAt=Now;
	if(!bSame||Moved.IsNearlyZero(.05)){Why(TEXT("over her, not moving"));return;}	// the first point only starts the measure
	Why(TEXT("sending"));
	const FTransform& T=Actor->GetActorTransform();
	const FVector UOrigin=AKKPreviewActor::ActorLocalToUnity(T.InverseTransformPosition(Origin));
	const FVector UDir=(AKKPreviewActor::ActorLocalToUnity(T.InverseTransformVectorNoScale(Dir)*100.)).GetSafeNormal();
	const FVector UVel=AKKPreviewActor::ActorLocalToUnity(T.InverseTransformVector(Moved))/Seconds;
	auto Vec=[](const FVector& V){TArray<TSharedPtr<FJsonValue>> A;for(double C:{V.X,V.Y,V.Z})A.Add(MakeShared<FJsonValueNumber>(C));return A;};
	auto R=Op(TEXT("hook"));R->SetStringField(TEXT("hook"),TEXT("input.pointer"));
	auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("mode"),TEXT("reader"));P->SetStringField(TEXT("card"),GCard);
	P->SetArrayField(TEXT("origin"),Vec(UOrigin));P->SetArrayField(TEXT("dir"),Vec(UDir));P->SetArrayField(TEXT("velocity"),Vec(UVel));
	R->SetObjectField(TEXT("payload"),P);
	FollowReplies(G,Ask(R));
}

void OKReaderMods::Speech(UOKCharacterController* G,const FString& Line)
{
	if(!Active())return;
	auto R=Op(TEXT("hook"));R->SetStringField(TEXT("hook"),TEXT("reader.speech_start"));
	auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("mode"),TEXT("reader"));P->SetStringField(TEXT("text"),Line);P->SetStringField(TEXT("card"),GCard);
	R->SetObjectField(TEXT("payload"),P);
	FollowReplies(G,Ask(R));
}

TArray<OKReaderMods::FPage> OKReaderMods::Pages()
{
	TArray<FPage> Out;
	const TSharedPtr<FJsonObject>& U=Ui();
	const TArray<TSharedPtr<FJsonValue>>* Mods=nullptr;
	if(!U.IsValid()||!U->TryGetArrayField(TEXT("mods"),Mods))return Out;
	for(const auto& M:*Mods)
	{
		const auto MO=M->AsObject();const TArray<TSharedPtr<FJsonValue>>* PageList=nullptr;
		if(!MO.IsValid()||!MO->TryGetArrayField(TEXT("pages"),PageList))continue;
		for(const auto& P:*PageList)
		{
			const auto PO=P->AsObject();if(!PO.IsValid())continue;
			FPage Page;Page.Mod=MO->GetStringField(TEXT("mod"));Page.Name=Text(PO,TEXT("name"));Page.Spec=PO;
			if(Page.Name.IsEmpty())MO->TryGetStringField(TEXT("name"),Page.Name);
			const TArray<TSharedPtr<FJsonValue>>* Items=nullptr;
			if(PO->TryGetArrayField(TEXT("items"),Items))for(const auto& I:*Items)if(I->AsObject().IsValid())Page.Items.Add(I->AsObject());
			Out.Add(MoveTemp(Page));
		}
	}
	return Out;
}

TArray<TPair<FString,FString>> OKReaderMods::CardMods()
{
	TArray<TPair<FString,FString>> Out;
	const TSharedPtr<FJsonObject> L=FOKModHost::Get().IsOpen()?FOKModHost::Get().List():nullptr;
	const TArray<TSharedPtr<FJsonValue>>* Mods=nullptr;
	if(!L.IsValid()||!L->TryGetArrayField(TEXT("mods"),Mods))return Out;
	for(const auto& M:*Mods)
	{
		const auto O=M->AsObject();if(!O.IsValid()||O->GetStringField(TEXT("state"))!=TEXT("enabled"))continue;
		TArray<FString> Subs;O->TryGetStringArrayField(TEXT("subscriptions"),Subs);
		if(Subs.Contains(TEXT("reader.character_load")))Out.Emplace(O->GetStringField(TEXT("id")),O->GetStringField(TEXT("name")));
	}
	return Out;
}

bool OKReaderMods::IsModKey(const FString& Key){return Key.StartsWith(TEXT("mod."));}
TSharedPtr<FJsonValue> OKReaderMods::Value(const FString& Key)
{
	if(!Active())return nullptr;
	if(!GValues.IsValid())RefreshValues();
	return GValues.IsValid()?GValues->TryGetField(Key):nullptr;
}
FString OKReaderMods::ItemText(const TSharedPtr<FJsonObject>& Item,const TCHAR* Field){return Item.IsValid()?Text(Item,Field):FString();}

TArray<TSharedPtr<FJsonValue>> OKReaderMods::Rows(UOKCharacterController* G)
{
	FRows Out;
	if(!Active())return Out;
	if(!GValues.IsValid())RefreshValues();
	for(const FPage& Page:Pages())
	{
	TArray<TSharedPtr<FJsonObject>> Leaves;LeafItems(Page.Items,Leaves);
	for(const TSharedPtr<FJsonObject>& I:Leaves)
	{
		FString Key;
		if(!I->TryGetStringField(TEXT("key"),Key)||Key.IsEmpty())continue;
		const FString Kind=RowKind(I);if(Kind.IsEmpty())continue;
		auto Row=MakeShared<FJsonObject>();
		Row->SetStringField(TEXT("key"),Key);Row->SetStringField(TEXT("kind"),Kind);Row->SetStringField(TEXT("label"),Page.Name+TEXT("／")+Text(I,TEXT("label")));
		Row->SetStringField(TEXT("category"),TEXT("mods"));Row->SetStringField(TEXT("mod"),Page.Mod);
		{FString ItemKind;I->TryGetStringField(TEXT("kind"),ItemKind);if(ItemKind==TEXT("color"))Row->SetStringField(TEXT("format"),TEXT("#RRGGBB"));}
		Row->SetBoolField(TEXT("supported"),true);Row->SetBoolField(TEXT("requires_apply"),false);
		TSharedPtr<FJsonValue> Value=GValues.IsValid()?GValues->TryGetField(Key):nullptr;
		if(!Value.IsValid()||Value->Type==EJson::Null)
			Value=Kind==TEXT("bool")?StaticCastSharedRef<FJsonValue>(MakeShared<FJsonValueBoolean>(false)):Kind==TEXT("number")?StaticCastSharedRef<FJsonValue>(MakeShared<FJsonValueNumber>(0)):StaticCastSharedRef<FJsonValue>(MakeShared<FJsonValueString>(FString()));
		Row->SetField(TEXT("value"),Value);
		double N;if(I->TryGetNumberField(TEXT("min"),N))Row->SetNumberField(TEXT("min"),N);if(I->TryGetNumberField(TEXT("max"),N))Row->SetNumberField(TEXT("max"),N);
		const TArray<TSharedPtr<FJsonValue>>* Options=nullptr;
		if(I->TryGetArrayField(TEXT("options"),Options))
		{
			FRows Made;
			for(const auto& O:*Options){const auto OO=O->AsObject();if(!OO.IsValid())continue;auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("value"),OO->GetStringField(TEXT("value")));R->SetStringField(TEXT("label"),Text(OO,TEXT("label")));Made.Add(MakeShared<FJsonValueObject>(R));}
			Row->SetArrayField(TEXT("options"),Made);
		}
		Out.Add(MakeShared<FJsonValueObject>(Row));
	}
	}
	for(const auto& M:CardMods())
	{
		auto Row=MakeShared<FJsonObject>();
		Row->SetStringField(TEXT("key"),TEXT("reader.mod_apply.")+M.Key);Row->SetStringField(TEXT("kind"),TEXT("bool"));
		Row->SetStringField(TEXT("label"),M.Value.IsEmpty()?M.Key:M.Value);Row->SetStringField(TEXT("category"),TEXT("mods"));Row->SetStringField(TEXT("mod"),M.Key);
		Row->SetBoolField(TEXT("supported"),true);Row->SetBoolField(TEXT("requires_apply"),false);Row->SetBoolField(TEXT("value"),ApplyOnLoad(M.Key));
		Out.Add(MakeShared<FJsonValueObject>(Row));
	}
	return Out;
}

bool OKReaderMods::Set(UOKCharacterController* G,const FString& Key,const TSharedPtr<FJsonValue>& Value,FString& Error)
{
	if(!Active()){Error=TEXT("mods are off");return false;}
	auto R=Op(TEXT("reader.control"));R->SetStringField(TEXT("key"),Key);R->SetField(TEXT("value"),Value.IsValid()?Value:MakeShared<FJsonValueNull>());
	const TSharedPtr<FJsonObject> Answer=Ask(R);
	bool bOk=false;if(Answer.IsValid())Answer->TryGetBoolField(TEXT("ok"),bOk);
	if(!bOk){Error=Answer.IsValid()?Answer->GetStringField(TEXT("error")):TEXT("no answer from the mod host");return false;}
	if(GValues.IsValid())GValues->SetField(Key,Value);
	const TSharedPtr<FJsonObject>* Json=nullptr;
	if(Answer->TryGetObjectField(TEXT("json"),Json))Follow(G,Answer->GetStringField(TEXT("mod")),*Json);
	RefreshValues();
	return true;
}

bool OKReaderMods::Emit(UOKCharacterController* G,const FString& Mod,const FString& Event,const FString& Value,FString& Error)
{
	if(!Active()){Error=TEXT("mods are off");return false;}
	auto R=Op(TEXT("hook"));R->SetStringField(TEXT("hook"),TEXT("ui.")+Mod+TEXT(".")+Event);
	R->SetArrayField(TEXT("mods"),{MakeShared<FJsonValueString>(Mod)});
	auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("event"),Event);P->SetStringField(TEXT("value"),Value);R->SetObjectField(TEXT("payload"),P);
	const TSharedPtr<FJsonObject> Answer=Ask(R);
	const TArray<TSharedPtr<FJsonValue>>* Replies=nullptr;
	if(!Answer.IsValid()||!Answer->TryGetArrayField(TEXT("replies"),Replies)||Replies->IsEmpty()){Error=TEXT("no answer from the mod host");return false;}
	const TSharedPtr<FJsonObject> O=(*Replies)[0]->AsObject();bool bOk=false;if(O.IsValid())O->TryGetBoolField(TEXT("ok"),bOk);
	if(!bOk){Error=O.IsValid()?O->GetStringField(TEXT("error")):TEXT("bad reply");return false;}
	FollowReplies(G,Answer);RefreshValues();
	return true;
}

FString OKReaderMods::OutfitName(const FString& Card,int32 Outfit)
{
	if(Card.IsEmpty()||FPaths::ConvertRelativePathToFull(Card)!=GCard)return FString();
	const FString* Name=GOutfitNames.Find(Outfit);return Name?*Name:FString();
}

bool OKReaderMods::IsApplyKey(const FString& Key){return Key.StartsWith(TEXT("reader.mod_apply."));}
bool OKReaderMods::ApplyOnLoad(const FString& Mod){bool bOn=true;ApplySettings().TryGetBoolField(Mod,bOn);return bOn;}
void OKReaderMods::SetApplyOnLoad(const FString& Mod,bool bOn)
{
	ApplySettings().SetBoolField(Mod,bOn);
	FString Text;FJsonSerializer::Serialize(GApply.ToSharedRef(),TJsonWriterFactory<>::Create(&Text));
	FFileHelper::SaveStringToFile(Text,*ApplyFile(),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}

bool OKReaderMods::RunCommand(UOKCharacterController* G,const FString& Command,FString& Error)
{
	if(!Active()){Error=TEXT("mods are off");return false;}
	auto R=Op(TEXT("command"));R->SetStringField(TEXT("command"),Command);
	const TSharedPtr<FJsonObject> Answer=Ask(R);
	bool bOk=false;if(Answer.IsValid())Answer->TryGetBoolField(TEXT("ok"),bOk);
	if(!bOk){Error=Answer.IsValid()?Answer->GetStringField(TEXT("error")):TEXT("no answer from the mod host");return false;}
	FString Text;if(Answer->TryGetStringField(TEXT("text"),Text)&&!Text.IsEmpty()&&G)G->ScreenNote(40,6.f,FColor::Cyan,Text);
	// A command's JSON answer is followed like a hook's ({"set":[...]}, {"notice": ...}).
	const TSharedPtr<FJsonObject>* Json=nullptr;
	if(Answer->TryGetObjectField(TEXT("json"),Json))Follow(G,Command,*Json);
	RefreshValues();
	return true;
}
