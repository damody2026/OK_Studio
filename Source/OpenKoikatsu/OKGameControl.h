#pragma once
// The UI channel, open in every mode (Docs/GAME_CONTROL_CHANNELS.md): whatever is on screen, read and changed the way a
// person does, so a control no other channel knows about is still reachable.
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"

namespace OKGameControl
{
 void Start();
 /** What a mode adds to /state, and how it takes /camera (none: the view target moves). Game thread. */
 void SetMode(const FString& Name,TFunction<void(FJsonObject&)> State,TFunction<bool(const FVector&,const FRotator&)> Camera);
 void ClearMode();
}
