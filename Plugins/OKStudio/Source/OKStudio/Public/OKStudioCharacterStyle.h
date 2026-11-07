#pragma once

#include "CoreMinimal.h"

/** The realistic end's numbers (widths against the card's), changed live by the control op style_tuning. */
struct FOKStudioStyleTuning
{
	float Heads = 11.f;			// how many heads tall
	float HeadSize = 1.4f;		// the head against the card's
	float Hips = 1.4f, Shoulders = 1.4f, Upper = 1.45f, Waist = 1.f, UpperArm = 1.55f, Forearm = 1.6f, Thigh = 1.3f, Calf = 1.3f, Bust = 1.2f, Hem = 1.f;
	float LegLength = 1.f;		// the legs against what the character's growth gives them
	float Breast = 0.85f;		// the breast size slider it pulls to
	float RealJaw = 0.33f;		// how far the jaw sliders go towards the realistic end's, on a middling jaw
	float RealFace = 0.6f;		// how far the eye shape, nose and mouth go towards the realistic end's
	float RealEye = 0.2f;		// and how far the eyes go up: further than this they go under the fringe
	float RealChin = 0.15f;		// how far the realistic end rounds the tip of the chin
	float ChibiChin = 0.15f;	// and the chibi end
	float ChibiHead = 0.8f;		// the chibi end's head against what its head slider gives
	float ChibiJaw = 0.1f;		// the most the chibi end widens the jaw sliders
	float ArmGrowth = 0.7f;		// how much of the character's growth the arms keep
	int32 Revision = 0;			// bumped on a change: shown characters take the numbers again
};
OKSTUDIO_API FOKStudioStyleTuning& OKStudioStyleTuning();

/**
 * A character's sliders at style `Style` (-1 realistic, 0 the card's, 1 chibi): the listed sliders pulled from the card's
 * value towards the style's, so the card still shows through. `Body` and `Face` are the card's sliders and are changed in
 * place. Out of 0..1 the values are what SliderUnlocker's cards use (shape.rs get_info extrapolates them).
 */
OKSTUDIO_API void OKStudioStyleSliders(float Style, float FaceLook, TArray<float>& Body, TArray<float>& Face);

/** The whole character's size at style `Style`, from the card's sliders and the styled ones. The height slider itself keeps head,
 * hands and torso at their size while the rest grows (cf_a_height_aid), so a style scales the character instead. The realistic
 * end grows it by as much as its head shrank: the head stays the card's size and the body below it gets longer. */
OKSTUDIO_API float OKStudioStyleScale(float Style, const TArray<float>& CardBody, const TArray<float>& Body);

/** How far up (cm) the character goes at style `Style` so its feet stay on the ground: the legs' length changes under it. */
OKSTUDIO_API float OKStudioStyleLift(float Style, float Scale, float CardHeight);

/** What sliders do not reach at style `Style` and whole-character scale `Scale` (widths, fingers, neck): bone modifiers for
 * FOkSession::SetStyleBones. */
OKSTUDIO_API FString OKStudioStyleBones(float Style, float Scale);
