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
#include "Misc/ScopeExit.h"
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

int32 GSlot=0;						// the accessory slot the per-slot controls are on (reader.mod_accessory_slot)
const TCHAR* const AccessorySlotKey=TEXT("reader.mod_accessory_slot");
TSet<FString> GChanged;				// registry keys changed since the last reader.property_change
bool bPropertyTimer=false;
int32 GFollowDepth=0;				// replies being followed: a reply's own edits are not sent back as changes

// {"outfit","slot"}: which slot a per-slot control means (reader.values / reader.control).
TSharedRef<FJsonObject> AccessoryRef(){auto A=MakeShared<FJsonObject>();A->SetNumberField(TEXT("outfit"),GOutfit<0?0:GOutfit);A->SetNumberField(TEXT("slot"),GSlot);return A;}
TSharedRef<FJsonObject> Hook(const TCHAR* Name,const TSharedRef<FJsonObject>& Payload)
{
	auto R=Op(TEXT("hook"));R->SetStringField(TEXT("hook"),Name);
	if(!Payload->HasField(TEXT("card")))Payload->SetStringField(TEXT("card"),GCard);
	R->SetObjectField(TEXT("payload"),Payload);return R;
}

void RefreshValues()
{
	auto Request=Op(TEXT("reader.values"));Request->SetObjectField(TEXT("accessory"),AccessoryRef());
	GValues=Ask(Request);
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
void Follow(UOKCharacterController* G,const FString& Mod,const TSharedPtr<FJsonObject>& Json);

// The registry values a mod asked for ({"get": ["body.height", "shape.face.*", ...]}: keys, or a prefix ending in "*"),
// as {key: value}. Mod controls (mod.*) are the mods' own and not handed out.
TSharedRef<FJsonObject> RegistryValues(UOKCharacterController* G,const TArray<FString>& Wanted,bool bAll=false)
{
	auto Out=MakeShared<FJsonObject>();
	if(!G||(Wanted.IsEmpty()&&!bAll))return Out;
	for(const TSharedPtr<FJsonValue>& P:OKCharacterMCPRegistry::Parameters(G))
	{
		const TSharedPtr<FJsonObject> O=P.IsValid()?P->AsObject():nullptr;if(!O.IsValid())continue;
		const FString Key=O->GetStringField(TEXT("key"));
		if(Key.StartsWith(TEXT("mod.")))continue;
		const bool bWanted=bAll||Wanted.ContainsByPredicate([&](const FString& W){return W.EndsWith(TEXT("*"))?Key.StartsWith(W.LeftChop(1)):W==Key;});
		if(!bWanted)continue;
		if(const TSharedPtr<FJsonValue> V=O->TryGetField(TEXT("value")))Out->SetField(Key,V);
	}
	return Out;
}
// A reply's "get": the values go back to that mod alone as reader.get_result {"values", "card", "outfit"}; its answer
// is followed like any reply, except that it cannot ask again (one round per reply).
void AnswerGet(UOKCharacterController* G,const FString& Mod,const TSharedPtr<FJsonObject>& Json)
{
	const TArray<TSharedPtr<FJsonValue>>* Get=nullptr;
	if(!G||!Json->TryGetArrayField(TEXT("get"),Get)||Get->IsEmpty()||Mod.StartsWith(TEXT("mod."))||GFollowDepth>1)return;
	TArray<FString> Wanted;for(const auto& K:*Get){FString S;if(K.IsValid()&&K->TryGetString(S)&&!S.IsEmpty())Wanted.Add(S);}
	if(Wanted.Num()>256)Wanted.SetNum(256);
	auto P=MakeShared<FJsonObject>();P->SetObjectField(TEXT("values"),RegistryValues(G,Wanted));P->SetNumberField(TEXT("outfit"),GOutfit<0?0:GOutfit);
	auto R=Hook(TEXT("reader.get_result"),P);R->SetArrayField(TEXT("mods"),{MakeShared<FJsonValueString>(Mod)});
	const TSharedPtr<FJsonObject> Answer=Ask(R);
	const TArray<TSharedPtr<FJsonValue>>* Replies=nullptr;
	if(!Answer.IsValid()||!Answer->TryGetArrayField(TEXT("replies"),Replies))return;
	for(const auto& Reply:*Replies)
	{
		const TSharedPtr<FJsonObject> O=Reply->AsObject();bool bOk=false;if(O.IsValid())O->TryGetBoolField(TEXT("ok"),bOk);
		const TSharedPtr<FJsonObject>* J=nullptr;
		if(bOk&&O->TryGetObjectField(TEXT("json"),J)){auto Copy=MakeShared<FJsonObject>(**J);Copy->RemoveField(TEXT("get"));Follow(G,Mod,Copy);}
	}
}

// What a mod's reply asks of the reader: {"set":[{key,value}]} registry edits, {"ops":[...]}, {"notice": text},
// {"subtitle":{"text","seconds"}}, {"get":[keys]} (answered with reader.get_result).
void Follow(UOKCharacterController* G,const FString& Mod,const TSharedPtr<FJsonObject>& Json)
{
	if(!G||!Json.IsValid())return;
	++GFollowDepth;ON_SCOPE_EXIT{--GFollowDepth;};
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
	AnswerGet(G,Mod,Json);
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
	// Pages with per-slot controls ({"accessory": true}, AccessoryControlWrapper's counterpart): which slot they are on.
	if(Pages().ContainsByPredicate([](const FPage& P){bool b=false;return P.Spec.IsValid()&&P.Spec->TryGetBoolField(TEXT("accessory"),b)&&b;}))
	{
		auto Row=MakeShared<FJsonObject>();
		Row->SetStringField(TEXT("key"),AccessorySlotKey);Row->SetStringField(TEXT("kind"),TEXT("number"));
		Row->SetStringField(TEXT("label"),TEXT("Mods／飾品欄（0 起算）"));Row->SetStringField(TEXT("category"),TEXT("mods"));
		Row->SetNumberField(TEXT("min"),0);Row->SetNumberField(TEXT("max"),19);Row->SetNumberField(TEXT("decimals"),0);
		Row->SetBoolField(TEXT("supported"),true);Row->SetBoolField(TEXT("requires_apply"),false);Row->SetNumberField(TEXT("value"),GSlot);
		Out.Add(MakeShared<FJsonValueObject>(Row));
	}
	return Out;
}

int32 OKReaderMods::AccessorySlot(){return GSlot;}
bool OKReaderMods::IsAccessorySlotKey(const FString& Key){return Key==AccessorySlotKey;}
void OKReaderMods::SetAccessorySlot(UOKCharacterController*,int32 Slot)
{
	Slot=FMath::Clamp(Slot,0,19);
	if(Slot==GSlot)return;
	GSlot=Slot;
	if(Active())RefreshValues();	// the per-slot controls show this slot's values
}

void OKReaderMods::WorkingCard(const FString& From,const FString& To)
{
	if(!Active()||From.IsEmpty()||To.IsEmpty())return;
	if(FPaths::ConvertRelativePathToFull(From)!=GCard)return;
	GCard=FPaths::ConvertRelativePathToFull(To);
	UE_LOG(LogOKMod,Verbose,TEXT("reader: work card %s, the same character for the mods"),*GCard);
}

void OKReaderMods::AccessoryChanged(UOKCharacterController* G,int32 Slot,const FString& Item,bool bAdded)
{
	if(!Active())return;
	auto P=MakeShared<FJsonObject>();P->SetNumberField(TEXT("outfit"),GOutfit<0?0:GOutfit);
	if(Slot>=0)P->SetNumberField(TEXT("slot"),Slot);
	P->SetStringField(TEXT("item"),Item);P->SetBoolField(TEXT("added"),bAdded);
	FollowReplies(G,Ask(Hook(TEXT("reader.accessory_change"),P)));RefreshValues();
}

void OKReaderMods::AccessoriesMoved(UOKCharacterController* G,const TArray<TSharedPtr<FJsonValue>>& Ops)
{
	if(!Active())return;
	const int32 Outfit=GOutfit<0?0:GOutfit;
	for(const TSharedPtr<FJsonValue>& V:Ops)
	{
		const TSharedPtr<FJsonObject> O=V.IsValid()?V->AsObject():nullptr;if(!O.IsValid())continue;
		const FString Name=O->GetStringField(TEXT("op"));
		auto P=MakeShared<FJsonObject>();
		if(Name==TEXT("accessory_transfer"))
		{
			P->SetNumberField(TEXT("outfit"),Outfit);P->SetNumberField(TEXT("from"),O->GetNumberField(TEXT("from")));P->SetNumberField(TEXT("to"),O->GetNumberField(TEXT("to")));
			FollowReplies(G,Ask(Hook(TEXT("reader.accessory_transfer"),P)));
		}
		else if(Name==TEXT("accessory_copy"))
		{
			const TArray<TSharedPtr<FJsonValue>>* Slots=nullptr;if(!O->TryGetArrayField(TEXT("slots"),Slots))continue;
			P->SetNumberField(TEXT("from_outfit"),O->GetNumberField(TEXT("from_outfit")));P->SetNumberField(TEXT("to_outfit"),Outfit);P->SetArrayField(TEXT("slots"),*Slots);
			FollowReplies(G,Ask(Hook(TEXT("reader.accessory_copy"),P)));
		}
	}
	RefreshValues();
}

void OKReaderMods::ClothesSaved(UOKCharacterController* G,const FString& Clothes,const FString& Card,int32 Outfit)
{
	if(!Active())return;
	auto R=Op(TEXT("clothes_store"));R->SetStringField(TEXT("clothes"),FPaths::ConvertRelativePathToFull(Clothes));
	R->SetStringField(TEXT("card"),FPaths::ConvertRelativePathToFull(Card));R->SetNumberField(TEXT("outfit"),Outfit);
	const TSharedPtr<FJsonObject> Answer=Ask(R);if(!Answer.IsValid())return;
	const TArray<TSharedPtr<FJsonValue>>* Errors=nullptr;
	if(Answer->TryGetArrayField(TEXT("errors"),Errors))for(const auto& E:*Errors)if(const auto O=E->AsObject())UE_LOG(LogOKMod,Warning,TEXT("[%s] not saved into the outfit card: %s"),*O->GetStringField(TEXT("mod")),*O->GetStringField(TEXT("error")));
	const TArray<TSharedPtr<FJsonValue>>* Written=nullptr;
	if(Answer->TryGetArrayField(TEXT("written"),Written)&&Written->Num())UE_LOG(LogOKMod,Display,TEXT("reader: %d mod section(s) saved into %s"),Written->Num(),*Clothes);
}

void OKReaderMods::ClothesWorn(UOKCharacterController* G,const FString& Clothes,const FString& Card,int32 Outfit)
{
	if(!Active())return;
	auto R=Op(TEXT("clothes_load"));R->SetStringField(TEXT("clothes"),FPaths::ConvertRelativePathToFull(Clothes));
	R->SetStringField(TEXT("card"),FPaths::ConvertRelativePathToFull(Card));R->SetNumberField(TEXT("outfit"),Outfit);
	FollowReplies(G,Ask(R));RefreshValues();
}

void OKReaderMods::ClothesState(UOKCharacterController* G,const uint8 (&States)[9],int32 Kind)
{
	if(!Active())return;
	auto P=MakeShared<FJsonObject>();P->SetNumberField(TEXT("outfit"),GOutfit<0?0:GOutfit);P->SetNumberField(TEXT("kind"),Kind);
	FRows S;for(int32 I=0;I<9;++I)S.Add(MakeShared<FJsonValueNumber>(States[I]));P->SetArrayField(TEXT("states"),S);
	FollowReplies(G,Ask(Hook(TEXT("reader.clothes_state"),P)));
}

// Changes from one drag of a slider or one batch of edits come as one reader.property_change, a quarter second after
// the last: {"keys": [...], "values": {key: value now}}. Edits a mod's own reply makes are not sent back to the mods.
void OKReaderMods::PropertyChanged(UOKCharacterController* G,const FString& Key)
{
	if(!Active()||!G||GFollowDepth>0||Key.IsEmpty()||IsModKey(Key)||IsApplyKey(Key)||Key==AccessorySlotKey)return;
	GChanged.Add(Key);
	static double LastAt=0;LastAt=FPlatformTime::Seconds();
	if(bPropertyTimer)return;
	bPropertyTimer=true;
	FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak=TWeakObjectPtr<UOKCharacterController>(G)](float)
	{
		if(FPlatformTime::Seconds()-LastAt<.25)return true;
		bPropertyTimer=false;
		UOKCharacterController* C=Weak.Get();
		TArray<FString> Keys=GChanged.Array();GChanged.Reset();
		if(!C||!Active()||Keys.IsEmpty())return false;
		Keys.Sort();
		auto P=MakeShared<FJsonObject>();P->SetNumberField(TEXT("outfit"),GOutfit<0?0:GOutfit);
		FRows K;for(const FString& S:Keys)K.Add(MakeShared<FJsonValueString>(S));P->SetArrayField(TEXT("keys"),K);
		P->SetObjectField(TEXT("values"),RegistryValues(C,Keys));
		FollowReplies(C,Ask(Hook(TEXT("reader.property_change"),P)));
		return false;
	}),.1f);
}

bool OKReaderMods::Set(UOKCharacterController* G,const FString& Key,const TSharedPtr<FJsonValue>& Value,FString& Error)
{
	if(!Active()){Error=TEXT("mods are off");return false;}
	auto R=Op(TEXT("reader.control"));R->SetStringField(TEXT("key"),Key);R->SetObjectField(TEXT("accessory"),AccessoryRef());R->SetField(TEXT("value"),Value.IsValid()?Value:MakeShared<FJsonValueNull>());
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
