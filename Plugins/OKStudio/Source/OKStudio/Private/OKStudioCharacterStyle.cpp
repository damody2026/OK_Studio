#include "OKStudioCharacterStyle.h"

namespace
{
	/** How far a style's end pulls a slider from the card's value to the style's. */
	constexpr float Pull = 0.75f;

	struct FStyleSlider
	{
		int32 Index;
		float Chibi;
		float Real;
	};

	// Indices: KKShapeRows.cpp. Every slider goes the opposite way for the two styles; tuned on 13 cards, mature and childlike.
	const TArray<FStyleSlider> BodyStyle = {
		{ 0, -2.f, 1.8f },		// height
		{ 1, 3.f, -0.2f },		// head size
		{ 4, 0.15f, 0.7f },		// breast size
		{ 37, 0.3f, 0.7f },		// shoulder width
	};
	const TArray<FStyleSlider> FaceStyle = {
		{ 0, 0.8f, 0.1f },		// face width
		{ 5, 0.55f, 0.f },		// lower face width
		{ 8, 0.9f, -0.2f },		// chin up/down
		{ 9, 0.95f, 0.1f },		// chin width
		{ 13, 1.f, 0.15f },		// chin tip width
		{ 16, 0.7f, 0.f },		// cheek width
		{ 17, 0.8f, 0.f },		// cheek forward
		{ 30, 0.2f, 0.9f },		// eye height
		{ 33, 0.45f, 0.55f },	// eye angle
		{ 34, 1.3f, -0.6f },	// eye width
		{ 35, 0.9f, -0.2f },	// eye length
		{ 38, 0.2f, 0.9f },		// nose tip
		{ 40, 0.2f, 1.f },		// nose bridge
		{ 42, 0.3f, 0.8f },		// mouth width
	};

	void Pulled(float Style, const TArray<FStyleSlider>& Sliders, TArray<float>& Values)
	{
		for (const FStyleSlider& S : Sliders)
		{
			const float Target = Style > 0.f ? S.Chibi : S.Real;
			if (Values.IsValidIndex(S.Index)) Values[S.Index] += FMath::Abs(Style) * Pull * (Target - Values[S.Index]);
		}
	}
}

void OKStudioStyleSliders(float Style, TArray<float>& Body, TArray<float>& Face)
{
	Style = FMath::Clamp(Style, -1.f, 1.f);
	if (Style == 0.f) return;
	Pulled(Style, BodyStyle, Body);
	Pulled(Style, FaceStyle, Face);
}
