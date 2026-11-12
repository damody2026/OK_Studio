#pragma once
#include "CoreMinimal.h"

class AOKInteractionMode;
class FOKStreetMind;

// The card reader's one-on-one talks like the street's (user 2026-11-12, coordinator): his line from the H panel goes to
// the heroine mind (ok-mind, DeepSeek) with her persona (free_talk_personas.json by her name), what she remembers of him
// (the street's main save: Saved/StreetSocial/mind, her identity the card's okId as the street knows her) and what she
// is in the middle of; her reply is shown on the panel and spoken line by line through ok-tts with her card's own voice.
// Only the words: the street's actions (meals, outings, money) are not hers to start from here, as in its private room.
class FOKReaderTalk {
public:
 FOKReaderTalk(const FString& Card,const FString& Her,const FString& Him,int32 Personality);
 ~FOKReaderTalk();
 void Tick(AOKInteractionMode& Mode);
 // Her memory written to disk (ok-mind save) when the scene ends.
 void End();
 const FString& HerName() const{return Her;}
 const FString& HisName() const{return Him;}
private:
 void Send(AOKInteractionMode& Mode,const FString& Text,const FString& Context,bool System);
 void Finish(AOKInteractionMode& Mode,const TSharedPtr<class FJsonObject>& Result);
 void RequestLine(int32 Index);
 FString RecallText(const FString& Text) const;
 FString Card,Her,Him,Id,TtsEndpoint,TtsDir;int32 Personality=0,TtsAge=18;
 TUniquePtr<FOKStreetMind> Mind;bool bMindTried=false,bBusy=false,bReaction=false;uint64 Job=0;
 // Her reply's lines: their TTS files (empty: none, text only), which have come back, and how many she has said.
 TArray<FString> Lines,Paths;TArray<uint8> Ready;int32 Said=0,Generation=0;double RepliedAt=0.;
 FString Shown;
 // The street save's view of her (stage, favour) and its clock for the mind's recall; none: his lover, as the reader has her.
 FString Stage=TEXT("lover");float Favor=150.f,Lewdness=0.f,SexDesire=0.f;int64 MindNow=0;
 TSharedPtr<bool,ESPMode::ThreadSafe> Alive;
};
