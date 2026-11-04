#include "OKStudioCharacterStyle.h"

namespace
{
	constexpr float Keep = -100.f;
	/** How far a style's end pulls a slider from the card's value to the style's. */
	constexpr float Pull = 0.75f;

	struct FStyleSlider
	{
		int32 Index;
		float Chibi;
		float Real;
	};

	// Indices: KKShapeRows.cpp.
	const TArray<FStyleSlider> BodyStyle = {
		{ 0, -2.f, 0.8f },	// height
		{ 1, 3.f, 0.3f },		// head size
		{ 4, 0.15f, Keep },		// breast size
	};
	const TArray<FStyleSlider> FaceStyle = {
		{ 0, 0.8f, 0.35f },	// face width
		{ 5, 0.8f, 0.3f },		// lower face width
		{ 8, 0.9f, 0.2f },		// chin up/down
		{ 9, 0.95f, 0.4f },		// chin width
		{ 13, 1.f, 0.4f },	// chin tip width
		{ 16, 0.85f, 0.35f },	// cheek width
		{ 17, 0.8f, 0.35f },	// cheek forward
		{ 30, 0.2f, 0.65f },		// eye height
		{ 33, 0.45f, Keep },	// eye angle
		{ 34, 1.3f, 0.2f },	// eye width
		{ 35, 0.9f, 0.25f },	// eye length
		{ 38, 0.2f, 0.7f },		// nose tip
		{ 40, 0.2f, 0.7f },		// nose bridge
		{ 42, 0.3f, 0.6f },		// mouth width
	};

	void Pulled(float Style, const TArray<FStyleSlider>& Sliders, TArray<float>& Values)
	{
		for (const FStyleSlider& S : Sliders)
		{
			const float Target = Style > 0.f ? S.Chibi : S.Real;
			if (Target != Keep && Values.IsValidIndex(S.Index)) Values[S.Index] += FMath::Abs(Style) * Pull * (Target - Values[S.Index]);
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
