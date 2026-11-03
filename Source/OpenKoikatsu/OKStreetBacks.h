#pragma once
#include "CoreMinimal.h"

class UWorld;

// The street's walls, buildings and floors are closed boxes (and spheres, cylinders), drawn from outside only. From
// inside one (the camera in a wall) or under a floor, what showed was its far side from within, a block of colour over
// what is being looked at (user, 2026-11-02: walls, buildings and floors not drawn from behind, always). Each frame, the
// street shape the camera is inside, or a floor slab whose top it is below, is not drawn (its collision stays). ok.Street.HideBacks 0
// draws them all.
void OKHideStreetBacks(UWorld* World,const FVector& Eye);
