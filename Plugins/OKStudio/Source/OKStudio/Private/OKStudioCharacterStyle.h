#pragma once

#include "CoreMinimal.h"

/**
 * A character's sliders at style `Style` (-1 realistic, 0 the card's, 1 chibi): the listed sliders pulled from the card's
 * value towards the style's, so the card still shows through. `Body` and `Face` are the card's sliders and are changed in
 * place. Out of 0..1 the values are what SliderUnlocker's cards use (shape.rs get_info extrapolates them).
 */
void OKStudioStyleSliders(float Style, TArray<float>& Body, TArray<float>& Face);
