#pragma once
#include "CoreMinimal.h"
class AKKPreviewActor;

// Fixed-size render targets keep card previews independent of window resolution.
namespace OKCardPreviewCapture
{
    using FComplete = TFunction<void(TArray<TArray<uint8>>, FString)>;
    // Four views: face close-up, front, side, back (in the actor's current pose).
    void Begin(AKKPreviewActor* Actor, FComplete Complete);
    // OK card views: front, side and back in T-pose (the actor is put in T-pose; the caller restores its animation).
    void BeginTPoseViews(AKKPreviewActor* Actor, FComplete Complete);
    // One view for HairDeck (a bred child's hair is drawn from her parents' faces): front, centred on the face mesh, 1.5
    // face widths across (head and shoulders); 768x1024, the face centre at the middle.
    void BeginHairReference(AKKPreviewActor* Actor, FComplete Complete);
}
