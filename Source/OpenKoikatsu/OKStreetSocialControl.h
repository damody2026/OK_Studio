#pragma once
// Development control channel (OKStreetSocialControl.inl): virtual keyboard state. Every key the street scene reads goes
// through OKKeyDown / OKKeyPressed, so a key pressed through the channel is read exactly like a real one (walking is
// real walking). Driven: an AI or test driver plays (-StreetSocialControl, or the first key sent through the channel): the mouse
// stays free and the game keeps reading input with its window behind others. A person playing never gets that.
#include "CoreMinimal.h"
#include "InputCoreTypes.h"
#include "GameFramework/PlayerController.h"

struct FOKVirtualInput {
 bool Active = false, Driven = false;
 TMap<FKey, double> DownUntil;
 TSet<FKey> Pending, Pressed; // Pending: asked since the last tick; Pressed: seen as "just pressed" during this tick
};
inline FOKVirtualInput& OKVirtualInput() { static FOKVirtualInput Input; return Input; }
inline bool OKControlActive() { return OKVirtualInput().Driven; }
inline bool OKKeyDown(APlayerController* PC, const FKey& Key) {
 if (PC && PC->IsInputKeyDown(Key)) return true;
 const double* Until = OKVirtualInput().DownUntil.Find(Key);
 return Until && FPlatformTime::Seconds() < *Until;
}
inline bool OKKeyPressed(APlayerController* PC, const FKey& Key) {
 if (PC && PC->WasInputKeyJustPressed(Key)) return true;
 return OKVirtualInput().Pressed.Contains(Key);
}
