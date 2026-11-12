#include "OKReaderTalk.h"

#include "OKInteractionMode.h"
#include "OKStreetMind.h"
#include "OKStreetSocialFreeTalk.h"
#include "OKStreetSocialPlaces.h"
#include "OKStreetSocialRules.h"
#include "OKStreetSocialText.h"
#include "OKStreetSpokenText.h"
#include "Dom/JsonObject.h"
#include "HttpModule.h"
#include "Interfaces/IHttpRequest.h"
#include "Interfaces/IHttpResponse.h"
#include "Misc/FileHelper.h"
#include "Misc/SecureHash.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace {
FString OKReaderJson(const TSharedRef<FJsonObject>& Object){FString Json;FJsonSerializer::Serialize(Object,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json));return Json;}
// The card's identity as the street knows her ("apng-" + its okId chunk, Tools/prepare_street_social_selection.lua):
// her memory and relation there are kept under it. A card without one (not made by ok-extract): her own identity here.
FString OKReaderCardId(const FString& Card){
 TArray<uint8> Bytes;if(!FFileHelper::LoadFileToArray(Bytes,*Card)||Bytes.Num()<8)return FString();
 for(int64 At=8;At+12<=Bytes.Num();){
  const uint32 Len=(uint32(Bytes[At])<<24)|(uint32(Bytes[At+1])<<16)|(uint32(Bytes[At+2])<<8)|uint32(Bytes[At+3]);
  if(At+12+int64(Len)>Bytes.Num())break;
  const bool bId=Bytes[At+4]=='o'&&Bytes[At+5]=='k'&&Bytes[At+6]=='I'&&Bytes[At+7]=='d';
  if(bId&&Len==64){FString Hex;for(uint32 I=0;I<Len;++I)Hex.AppendChar(FChar::ToLower(TCHAR(Bytes[At+8+I])));return TEXT("apng-")+Hex;}
  if(Bytes[At+4]=='I'&&Bytes[At+5]=='E'&&Bytes[At+6]=='N'&&Bytes[At+7]=='D')break;
  At+=12+int64(Len);}
 return TEXT("reader:")+FMD5::HashBytes(Bytes.GetData(),Bytes.Num());
}
// ok-tts and its voice settings as the street has them: the launcher's endpoint, else player.json's voice section.
FString OKReaderTtsEndpoint(int32& Age){
 FString Endpoint=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_TTS_ENDPOINT"));
 FString Text;TSharedPtr<FJsonObject> Root;const TSharedPtr<FJsonObject>* Voice=nullptr;
 if(FFileHelper::LoadFileToString(Text,*OKStreetFreeTalkSettingsPath())&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Root)&&Root.IsValid()&&Root->TryGetObjectField(TEXT("voice"),Voice)){
  double A=0;if((*Voice)->TryGetNumberField(TEXT("tts_age"),A))Age=FMath::Clamp(int32(A),12,45);
  FString Saved;if(Endpoint.IsEmpty()&&(*Voice)->TryGetStringField(TEXT("tts_endpoint"),Saved)&&(Saved.StartsWith(TEXT("http://127.0.0.1:"))||Saved.StartsWith(TEXT("http://localhost:"))))Endpoint=Saved;}
 return Endpoint.IsEmpty()?FString(TEXT("http://127.0.0.1:47860")):Endpoint;
}
}

FOKReaderTalk::FOKReaderTalk(const FString& InCard,const FString& InHer,const FString& InHim,int32 InPersonality)
 :Card(InCard),Her(InHer),Him(InHim),Personality(InPersonality),Alive(MakeShared<bool,ESPMode::ThreadSafe>(true)){
 Id=OKReaderCardId(Card);TtsEndpoint=OKReaderTtsEndpoint(TtsAge);
 // Her name and his as the street has them: its name table over her card's (jeanne.png is 贞德 there, and her persona is
 // found under that name), and the player's own name from the settings over the male card's.
 {FString Text;TSharedPtr<FJsonObject> Root;const TSharedPtr<FJsonObject>* Names=nullptr;FString Name;
  if(FFileHelper::LoadFileToString(Text,*(FPaths::ProjectContentDir()/TEXT("IndependentResources/StreetSocialData/name_overrides.json")))&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Root)&&Root.IsValid()
   &&Root->TryGetObjectField(TEXT("names"),Names)&&(*Names)->TryGetStringField(Id,Name)&&!Name.IsEmpty())Her=Name;}
 {FString Text;TSharedPtr<FJsonObject> Root;const TSharedPtr<FJsonObject>* Voice=nullptr;FString Name;
  if(FFileHelper::LoadFileToString(Text,*OKStreetFreeTalkSettingsPath())&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Root)&&Root.IsValid()
   &&Root->TryGetObjectField(TEXT("voice"),Voice)&&(*Voice)->TryGetStringField(TEXT("player_name"),Name)&&!Name.TrimStartAndEnd().IsEmpty())Him=Name.TrimStartAndEnd().Left(24);}
 TtsDir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("CardReader/voice"));IFileManager::Get().MakeDirectory(*TtsDir,true);
 // Her place in the street's main save, when she has one there.
 FOKStreetStore Store;FString Error;
 if(OKStreetLoadSaveFile(FPaths::ProjectSavedDir()/TEXT("StreetSocial/relationships.json"),Store,Error)==EOKStreetLoad::Ok){
  MindNow=int64(Store.CalendarDay)*1440+FMath::Max(0,Store.CalendarMinute);
  for(const FOKStreetRelation& R:Store.Relations)if(R.Id==Id){Stage=R.Stage;Favor=R.Favor;Lewdness=R.Lewdness;SexDesire=R.SexDesire;break;}}
 UE_LOG(LogTemp,Display,TEXT("Card reader talk: %s id=%s stage=%s tts=%s"),*Her,*Id,*Stage,*TtsEndpoint);
}
FOKReaderTalk::~FOKReaderTalk(){*Alive=false;End();}
void FOKReaderTalk::End(){
 if(Mind){FString Error;if(!Mind->Save(Error))UE_LOG(LogTemp,Warning,TEXT("Card reader talk: her memory not saved: %s"),*Error);Mind.Reset();}
}

// What she remembers that bears on his line (ok-mind recall), as the street asks it.
FString FOKReaderTalk::RecallText(const FString& Text) const{
 if(!Mind)return FString();
 TSharedRef<FJsonObject> Q=MakeShared<FJsonObject>();Q->SetStringField(TEXT("kind"),TEXT("recall"));Q->SetStringField(TEXT("heroine"),Id);Q->SetNumberField(TEXT("now"),double(MindNow));Q->SetNumberField(TEXT("k"),5);
 Q->SetArrayField(TEXT("entities"),{MakeShared<FJsonValueString>(TEXT("player"))});
 TArray<TSharedPtr<FJsonValue>> Words;FString Chunk;auto Flush=[&](){if(Chunk.Len()>=2)Words.Add(MakeShared<FJsonValueString>(Chunk.Left(8)));Chunk.Reset();};
 for(const TCHAR C:Text){if(FChar::IsWhitespace(C)||FChar::IsPunct(C)||C==TEXT('，')||C==TEXT('。')||C==TEXT('？')||C==TEXT('！')||C==TEXT('、'))Flush();else Chunk.AppendChar(C);}Flush();
 Q->SetArrayField(TEXT("keywords"),Words);
 FString Out,Error;TSharedPtr<FJsonObject> Root;const TArray<TSharedPtr<FJsonValue>>* Rows=nullptr;
 if(!Mind->Query(OKReaderJson(Q),Out,Error)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Out),Root)||!Root.IsValid()||!Root->TryGetArrayField(TEXT("memories"),Rows))return FString();
 FString Memories;for(const auto& Row:*Rows){FString Summary;if(Row->AsObject().IsValid()&&Row->AsObject()->TryGetStringField(TEXT("summary"),Summary)&&!Summary.IsEmpty())Memories+=(Memories.IsEmpty()?FString():FString(OKT(TEXT("ui.economy.semicolon_mark"))))+Summary;}
 return Memories;
}

void FOKReaderTalk::Send(AOKInteractionMode& Mode,const FString& Text,const FString& Context,bool System){
 if(!bMindTried){bMindTried=true;Mind=MakeUnique<FOKStreetMind>();FString Error;
  // The street's main save: what she remembers there she remembers here, and the other way round.
  const FString SaveDir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("StreetSocial/mind"));
  if(Mind->Open(SaveDir,OKStreetFreeTalkSettingsPath(),false,Error,FPaths::GetPath(FPaths::GetPath(OKStreetPlaceModelDir())))){UE_LOG(LogTemp,Display,TEXT("Card reader talk: mind open (%s) at %s"),*Mind->DllPath(),*SaveDir);}
  else{UE_LOG(LogTemp,Warning,TEXT("Card reader talk: no heroine mind, she answers nothing: %s"),*Error);Mind.Reset();}}
 if(!Mind){Mode.HSceneShowLine(FString(OKT(TEXT("ui.scene.ai_service_off_reply"))));return;}
 FOKFreeTalkPersona Persona;FString Error;
 if(!OKStreetFreeTalkLoadPersona(Her,Persona,Error)){UE_LOG(LogTemp,Warning,TEXT("Card reader talk: no persona for %s: %s"),*Her,*Error);return;}
 FOKFreeTalkStatus Status;
 Status.Relation=Stage==TEXT("lover")?OKT(TEXT("ui.bonds.lover_stage")):Stage==TEXT("friend")?OKT(TEXT("ui.bonds.friend_stage")):OKT(TEXT("ui.scene.stage_new"));
 if(!Him.IsEmpty())Status.Relation+=OKMsg(TEXT("ui.free_talk.his_name_note"),{{TEXT("name"),*Him}});
 Status.Favor=Favor;Status.Lewdness=Lewdness;Status.SexDesire=SexDesire;
 // Alone with him in the private room, as the street's one-on-one tells it.
 Status.Doing=OKT(TEXT("ui.free_talk.private_doing"));Status.Nearby=OKT(TEXT("ui.free_talk.private_nearby"));Status.Scene=OKT(TEXT("ui.free_talk.private_scene"));
 Status.Now=OKStreetFreeTalkDateTime(FDateTime::Now());Status.Memories=RecallText(Text);
 FString UserMessage=OKStreetFreeTalkUserMessage(Status,Text);if(!Context.IsEmpty())UserMessage+=TEXT("\n")+Context;
 TSharedRef<FJsonObject> Request=MakeShared<FJsonObject>();
 Request->SetStringField(TEXT("kind"),TEXT("talk"));Request->SetStringField(TEXT("tag"),TEXT("freetalk"));Request->SetStringField(TEXT("priority"),TEXT("dialogue"));
 Request->SetStringField(TEXT("heroine"),Id);Request->SetStringField(TEXT("system"),OKStreetFreeTalkSystemPrompt(Persona,OKStreetPlaceCatalogue()));Request->SetStringField(TEXT("user"),UserMessage);
 Request->SetNumberField(TEXT("max_tokens"),400);Request->SetNumberField(TEXT("temperature"),1.0);Request->SetBoolField(TEXT("json"),true);Request->SetArrayField(TEXT("legacy_history"),{});
 Job=Mind->Submit(OKReaderJson(Request),Error);
 if(!Job){UE_LOG(LogTemp,Warning,TEXT("Card reader talk: the mind refused the talk: %s"),*Error);return;}
 bBusy=true;bReaction=System;Mode.HSceneShowLine(Her+OKT(TEXT("ui.scene.ellipsis_colon")));
 UE_LOG(LogTemp,Display,TEXT("Card reader talk: sent %s line (%d chars)"),System?TEXT("a happening"):TEXT("his"),Text.Len());
}

void FOKReaderTalk::Finish(AOKInteractionMode& Mode,const TSharedPtr<FJsonObject>& R){
 bBusy=false;Job=0;FString Content,Failure;bool Ok=false,Retry=false;R->TryGetBoolField(TEXT("ok"),Ok);FOKFreeTalkReply Reply;
 if(!Ok){R->TryGetStringField(TEXT("error"),Failure);Failure=OKT(TEXT("ui.mind.deepseek_error_prefix"))+Failure;}
 else if(!R->TryGetStringField(TEXT("content"),Content)||!OKStreetFreeTalkParseContent(Content,Reply,Failure,Retry)){if(Failure.IsEmpty())Failure=OKT(TEXT("ui.mind.deepseek_empty_reply"));}
 if(!Failure.IsEmpty()){UE_LOG(LogTemp,Warning,TEXT("Card reader talk: no reply: %s"),*Failure);Mode.HSceneShowLine(Failure);return;}
 Shown=Her+OKT(TEXT("ui.economy.colon_mark"))+Reply.Reply;Mode.HSceneShowLine(Shown);
 UE_LOG(LogTemp,Display,TEXT("Card reader talk: she answered %d lines"),Reply.Lines.Num());
 ++Generation;Lines=Reply.Lines;Paths.Init(FString(),Lines.Num());Ready.Init(0,Lines.Num());Said=0;RepliedAt=FPlatformTime::Seconds();
 if(Lines.Num())RequestLine(0);
}

// One line of hers through ok-tts (the street's request: her personality's voice, her card's own when it has one); the
// next is asked for when this one is back, so they come in order.
void FOKReaderTalk::RequestLine(int32 Index){
 if(!Lines.IsValidIndex(Index))return;
 const FString Spoken=OKStreetSpokenText(Lines[Index]);bool Speakable=false;for(const TCHAR C:Spoken)if(FChar::IsAlnum(C)||(C>=0x3040&&C<0xFF00)){Speakable=true;break;}
 if(!Speakable){Ready[Index]=2;RequestLine(Index+1);return;}
 TSharedRef<FJsonObject> Body=MakeShared<FJsonObject>();Body->SetStringField(TEXT("text"),Spoken.Left(400));Body->SetStringField(TEXT("personality"),FString::FromInt(Personality));
 Body->SetNumberField(TEXT("age"),TtsAge);Body->SetStringField(TEXT("out_dir"),TtsDir);Body->SetStringField(TEXT("card"),Card);
 auto Http=FHttpModule::Get().CreateRequest();Http->SetURL(TtsEndpoint/TEXT("synthesize"));Http->SetVerb(TEXT("POST"));
 Http->SetHeader(TEXT("Content-Type"),TEXT("application/json; charset=utf-8"));Http->SetContentAsString(OKReaderJson(Body));Http->SetTimeout(30.f);
 const int32 Gen=Generation;TWeakPtr<bool,ESPMode::ThreadSafe> WeakAlive=Alive;
 Http->OnProcessRequestComplete().BindLambda([this,WeakAlive,Gen,Index](FHttpRequestPtr,FHttpResponsePtr Response,bool Connected){
  if(!WeakAlive.IsValid()||Gen!=Generation||!Ready.IsValidIndex(Index))return;
  TSharedPtr<FJsonObject> J;bool Ok=false;FString Path;
  if(Connected&&Response.IsValid()&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Response->GetContentAsString()),J)&&J.IsValid())Ok=J->TryGetBoolField(TEXT("ok"),Ok)&&Ok&&J->TryGetStringField(TEXT("path"),Path);
  Paths[Index]=Ok?Path:FString();Ready[Index]=Ok?1:2;
  if(!Ok)UE_LOG(LogTemp,Warning,TEXT("Card reader talk: no voice for line %d (%s), shown as text"),Index,Connected?TEXT("TTS error"):TEXT("no TTS server"));
  RequestLine(Index+1);});
 Http->ProcessRequest();
}

void FOKReaderTalk::Tick(AOKInteractionMode& Mode){
 if(Mind){TArray<TSharedPtr<FJsonObject>> Done;Mind->Poll(Done);for(const auto& R:Done)if(R.IsValid()&&uint64(R->GetNumberField(TEXT("id")))==Job)Finish(Mode,R);}
 // Her lines, each once the one before is said (a line with no voice is shown only).
 while(Said<Lines.Num()&&Ready[Said]==2)++Said;
 if(Said<Lines.Num()&&Ready[Said]==1&&!Mode.HSceneSpeaking()){Mode.HSceneSpeak(Paths[Said]);++Said;}
 const bool Unsaid=Said<Lines.Num()&&FPlatformTime::Seconds()-RepliedAt<40.;
 // Her reaction to a touch is out of date once he does something new: what is left of it is dropped (the street's rule).
 if(bReaction&&Unsaid&&!bBusy&&Mode.HSceneHasReaction()){Said=Lines.Num();++Generation;}
 Mode.HSceneReplyPending(bBusy||(Said<Lines.Num()&&FPlatformTime::Seconds()-RepliedAt<40.));
 FString Line,Context;bool System=false;
 if(!bBusy&&!(Said<Lines.Num()&&FPlatformTime::Seconds()-RepliedAt<40.)&&Mode.HSceneTakeLine(Line,Context,System))Send(Mode,Line,Context,System);
}
