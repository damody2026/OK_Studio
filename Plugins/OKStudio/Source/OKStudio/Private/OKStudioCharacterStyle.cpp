#include "OKStudioCharacterStyle.h"

namespace
{
	/** How far a style's end pulls a slider from the card's value to the style's. */
	constexpr float Pull = 0.75f;
	/** The whole character's size at the chibi end. */
	constexpr float ChibiScale = 0.78f;
	/** Half the distance between the thighs and between the arms, on the unscaled skeleton (m). */
	constexpr float ThighX = 0.0806f, ArmX = 0.094f;
	/** The head size and breast size sliders the chibi end pulls to. */
	constexpr float ChibiHead = 3.f, ChibiBreast = 0.15f;

	struct FStyleSlider
	{
		int32 Index;
		float Chibi;
		float Real;
	};

	struct FStyleBone
	{
		const TCHAR* Name;
		float ChibiThickness, ChibiLength;
		float RealThickness, RealLength;
		bool bBothSides;
	};

	/** A skin bone the realistic end narrows back to the card's width after scaling the character. */
	struct FStyleWidth
	{
		const TCHAR* Name;
		bool bBothSides;
		int32 Along;		// the axis that keeps the growth, -1 for none
		float FOKStudioStyleTuning::* Width = nullptr;	// against the card's
		bool bArm = false;	// its length follows ArmGrowth
		bool bLeg = false;	// its length follows LegLength
	};

	// Indices: KKShapeRows.cpp. Every slider goes the opposite way for the two styles; the inventory and why these values:
	// Docs/OK_STUDIO_CHARACTER_STYLE_PARAMS.md. The height slider is not one of them (OKStudioStyleScale).
	const TArray<FStyleSlider> BodyStyle = {
		{ 2, 0.7f, 0.25f },		// neck width
		{ 3, 0.7f, 0.25f },		// neck thickness
		{ 16, 0.6f, 0.35f },	// upper torso width
		{ 17, 0.6f, 0.35f },	// upper torso thickness
		{ 18, 0.6f, 0.35f },	// lower torso width
		{ 19, 0.6f, 0.35f },	// lower torso thickness
		{ 22, 0.6f, 0.25f },	// upper waist width
		{ 23, 0.6f, 0.3f },		// upper waist thickness
		{ 24, 0.4f, 0.5f },		// lower waist width
		{ 26, 0.4f, 0.5f },		// hips
		{ 28, 0.5f, 0.3f },		// upper thigh width
		{ 29, 0.5f, 0.3f },		// upper thigh thickness
		{ 30, 0.5f, 0.3f },		// lower thigh width
		{ 31, 0.5f, 0.3f },		// lower thigh thickness
		{ 32, 0.5f, 0.3f },		// knee width
		{ 33, 0.5f, 0.3f },		// knee thickness
		{ 34, 0.5f, 0.3f },		// calf
		{ 35, 0.5f, 0.3f },		// ankle width
		{ 36, 0.5f, 0.3f },		// ankle thickness
		{ 37, 0.3f, 0.6f },		// shoulder width
		{ 39, 0.5f, 0.3f },		// upper arm width
		{ 40, 0.5f, 0.3f },		// upper arm thickness
		{ 41, 0.5f, 0.3f },		// elbow width
		{ 42, 0.5f, 0.3f },		// elbow thickness
		{ 43, 0.5f, 0.3f },		// forearm
	};
	const TArray<FStyleSlider> FaceStyle = {
		{ 0, 0.72f, 0.1f },		// face width
		{ 5, 0.45f, 0.f },		// lower face width
		{ 6, 0.95f, 0.5f },		// lower chin up/down
		{ 8, 0.7f, -0.2f },		// chin up/down
		{ 9, 0.7f, 0.25f },		// chin width
		{ 16, 0.5f, 0.f },		// cheek width
		{ 17, 1.05f, 0.f },		// cheek forward
		{ 18, 0.2f, 0.8f },		// cheek up/down
		{ 30, 0.2f, 0.9f },		// eye height
		{ 33, 0.45f, 0.55f },	// eye angle
		{ 34, 1.3f, -0.6f },	// eye width
		{ 35, 0.9f, -0.2f },	// eye length
		{ 38, 0.2f, 0.9f },		// nose tip
		{ 40, 0.2f, 1.f },		// nose bridge
		{ 42, 0.3f, 0.8f },		// mouth width
	};
	// What no slider reaches: the neck's length (the head on its bone) and the fingers.
	const FStyleBone BoneStyle[] = {
		{ TEXT("cf_j_head"), 1.f, 0.75f, 1.f, 1.f, false },
		{ TEXT("cf_j_index01"), 1.1f, 1.f, 0.9f, 1.f, true }, { TEXT("cf_j_index02"), 1.f, 0.85f, 1.f, 1.12f, true }, { TEXT("cf_j_index03"), 1.f, 0.85f, 1.f, 1.12f, true },
		{ TEXT("cf_j_middle01"), 1.1f, 1.f, 0.9f, 1.f, true }, { TEXT("cf_j_middle02"), 1.f, 0.85f, 1.f, 1.12f, true }, { TEXT("cf_j_middle03"), 1.f, 0.85f, 1.f, 1.12f, true },
		{ TEXT("cf_j_ring01"), 1.1f, 1.f, 0.9f, 1.f, true }, { TEXT("cf_j_ring02"), 1.f, 0.85f, 1.f, 1.12f, true }, { TEXT("cf_j_ring03"), 1.f, 0.85f, 1.f, 1.12f, true },
		{ TEXT("cf_j_little01"), 1.1f, 1.f, 0.9f, 1.f, true }, { TEXT("cf_j_little02"), 1.f, 0.85f, 1.f, 1.12f, true }, { TEXT("cf_j_little03"), 1.f, 0.85f, 1.f, 1.12f, true },
		{ TEXT("cf_j_thumb02"), 1.f, 0.85f, 1.f, 1.1f, true }, { TEXT("cf_j_thumb03"), 1.f, 0.85f, 1.f, 1.1f, true },
	};

	using T = FOKStudioStyleTuning;
	const FStyleWidth Widths[] = {
		{ TEXT("cf_s_neck"), false, 1 }, { TEXT("cf_s_spine03"), false, 1, &T::Upper }, { TEXT("cf_s_spine02"), false, 1, &T::Upper }, { TEXT("cf_s_spine01"), false, 1, &T::Upper },
		{ TEXT("cf_s_waist01"), false, 1, &T::Waist }, { TEXT("cf_s_waist02"), false, 1, &T::Hips }, { TEXT("cf_s_siri"), true, -1, &T::Hips }, { TEXT("cf_d_sk_top"), false, 1, &T::Hem },
		{ TEXT("cf_s_bust00"), true, -1, &T::Bust },
		{ TEXT("cf_s_thigh01"), true, 1, &T::Thigh, false, true }, { TEXT("cf_s_thigh02"), true, 1, &T::Thigh, false, true }, { TEXT("cf_s_thigh03"), true, 1, &T::Thigh, false, true },
		{ TEXT("cf_s_leg01"), true, 1, &T::Calf, false, true }, { TEXT("cf_s_leg02"), true, 1, &T::Calf, false, true }, { TEXT("cf_s_leg03"), true, 1, &T::Calf, false, true },
		{ TEXT("cf_s_shoulder02"), true, 0, &T::Shoulders }, { TEXT("cf_s_arm01"), true, 0, &T::UpperArm, true }, { TEXT("cf_s_arm02"), true, 0, &T::UpperArm, true }, { TEXT("cf_s_arm03"), true, 0, &T::UpperArm, true },
		{ TEXT("cf_s_forearm01"), true, 0, &T::Forearm, true }, { TEXT("cf_s_forearm02"), true, 0, &T::Forearm, true }, { TEXT("cf_s_wrist"), true, 0, &T::Forearm, true },
	};

	void Pulled(float Style, const TArray<FStyleSlider>& Sliders, TArray<float>& Values)
	{
		for (const FStyleSlider& S : Sliders)
		{
			const float Target = Style > 0.f ? S.Chibi : S.Real;
			if (Values.IsValidIndex(S.Index)) Values[S.Index] += FMath::Abs(Style) * Pull * (Target - Values[S.Index]);
		}
	}

	/** The head's height in cm on an unscaled character. */
	float HeadSize(float Height, float Head)
	{
		return 20.27f - 1.5f * Height + 3.2f * Head;
	}

	/** The head size slider at which a character of this height slider is Tuning.Heads tall (measured: total height 146.6 + 18.06 h
	 *  cm, head 20.27 - 1.5 h + 3.2 v cm). */
	float RealHead(float Height)
	{
		return ((146.6f + 18.06f * Height) / OKStudioStyleTuning().Heads - HeadSize(Height, 0.f)) / 3.2f;
	}
}

FOKStudioStyleTuning& OKStudioStyleTuning()
{
	static FOKStudioStyleTuning Tuning;
	return Tuning;
}

float OKStudioStyleScale(float Style, const TArray<float>& CardBody, const TArray<float>& Body)
{
	Style = FMath::Clamp(Style, -1.f, 1.f);
	if (Style >= 0.f || !CardBody.IsValidIndex(1) || !Body.IsValidIndex(1)) return FMath::Lerp(1.f, ChibiScale, FMath::Max(Style, 0.f));
	return HeadSize(CardBody[0], CardBody[1]) / HeadSize(Body[0], Body[1]);
}

float OKStudioStyleLift(float Style, float Scale, float CardHeight)
{
	// The legs are about half the unscaled height; the feet stay on the ground when they change.
	return Style < 0.f ? (FMath::Lerp(1.f, OKStudioStyleTuning().LegLength, -Style) - 1.f) * 0.5f * (146.6f + 18.06f * CardHeight) * Scale : 0.f;
}

FString OKStudioStyleBones(float Style, float Scale)
{
	Style = FMath::Clamp(Style, -1.f, 1.f);
	FString Json;
	if (Style < 0.f)
	{
		const FOKStudioStyleTuning& Tuning = OKStudioStyleTuning();
		const float Thin = 1.f / Scale;
		const float Arm = (1.f + (Scale - 1.f) * Tuning.ArmGrowth) / Scale;
		const float Leg = FMath::Lerp(1.f, Tuning.LegLength, -Style);
		const auto Add = [&Json](const FString& Name, const FVector& Size, float Length, float X)
		{
			Json += FString::Printf(TEXT("%s{\"name\":\"%s\",\"location\":0,\"coord\":[{\"scale\":[%f,%f,%f],\"length\":%f,\"pos\":[%f,0,0],\"rot\":[0,0,0]}]}"),
				Json.IsEmpty() ? TEXT("") : TEXT(","), *Name, Size.X, Size.Y, Size.Z, Length, X);
		};
		for (const FStyleWidth& W : Widths)
			for (const TCHAR* Side : { TEXT("_L"), TEXT("_R") })
			{
				FVector Size(Thin * FMath::Lerp(1.f, W.Width ? Tuning.*W.Width : 1.f, -Style));
				if (W.Along >= 0) Size[W.Along] = 1.f;
				Add(FString(W.Name) + (W.bBothSides ? Side : TEXT("")), Size, W.bArm ? Arm : W.bLeg ? Leg : 1.f, 0.f);
				if (!W.bBothSides) break;
			}
		// The cf_d_ branches hang off the same joints: left at their length, the skin and a wrist accessory stay behind the hand.
		for (const TCHAR* Bone : { TEXT("cf_j_forearm01_L"), TEXT("cf_j_forearm01_R"), TEXT("cf_j_hand_L"), TEXT("cf_j_hand_R"), TEXT("cf_d_arm01_L"), TEXT("cf_d_arm01_R"), TEXT("cf_d_arm02_L"), TEXT("cf_d_arm02_R"), TEXT("cf_d_arm03_L"), TEXT("cf_d_arm03_R"), TEXT("cf_d_forearm02_L"), TEXT("cf_d_forearm02_R"), TEXT("cf_d_wrist_L"), TEXT("cf_d_wrist_R") }) Add(Bone, FVector::OneVector, Arm, 0.f);
		for (const TCHAR* Bone : { TEXT("cf_j_leg01_L"), TEXT("cf_j_leg01_R"), TEXT("cf_j_leg03_L"), TEXT("cf_j_leg03_R") }) Add(Bone, FVector::OneVector, Leg, 0.f);
		Add(TEXT("cf_s_head"), FVector(FMath::Lerp(1.f, Tuning.HeadSize, -Style)), 1.f, 0.f);
		// The thighs and arms come in with the width, or they would stand off the body.
		Add(TEXT("cf_j_thigh00_L"), FVector::OneVector, 1.f, ThighX * (1.f - Thin * Tuning.Hips));
		Add(TEXT("cf_j_thigh00_R"), FVector::OneVector, 1.f, -ThighX * (1.f - Thin * Tuning.Hips));
		Add(TEXT("cf_j_arm00_L"), FVector::OneVector, 1.f, ArmX * (1.f - Thin * Tuning.Shoulders));
		Add(TEXT("cf_j_arm00_R"), FVector::OneVector, 1.f, -ArmX * (1.f - Thin * Tuning.Shoulders));
	}
	if (Style > 0.f)
	{
		const float Head = FMath::Lerp(1.f, OKStudioStyleTuning().ChibiHead, Style);
		Json += FString::Printf(TEXT("%s{\"name\":\"cf_s_head\",\"location\":0,\"coord\":[{\"scale\":[%f,%f,%f],\"length\":1,\"pos\":[0,0,0],\"rot\":[0,0,0]}]}"), Json.IsEmpty() ? TEXT("") : TEXT(","), Head, Head, Head);
	}
	if (Style != 0.f)
		for (const FStyleBone& B : BoneStyle)
		{
			const float Rate = FMath::Abs(Style);
			const float Thickness = FMath::Lerp(1.f, Style > 0.f ? B.ChibiThickness : B.RealThickness, Rate);
			const float Length = FMath::Lerp(1.f, Style > 0.f ? B.ChibiLength : B.RealLength, Rate);
			for (const TCHAR* Side : { TEXT("_L"), TEXT("_R") })
			{
				Json += FString::Printf(TEXT("%s{\"name\":\"%s%s\",\"location\":0,\"coord\":[{\"scale\":[1,%f,%f],\"length\":%f,\"pos\":[0,0,0],\"rot\":[0,0,0]}]}"),
					Json.IsEmpty() ? TEXT("") : TEXT(","), B.Name, B.bBothSides ? Side : TEXT(""), Thickness, Thickness, Length);
				if (!B.bBothSides) break;
			}
		}
	return TEXT("[") + Json + TEXT("]");
}

void OKStudioStyleSliders(float Style, float FaceLook, TArray<float>& Body, TArray<float>& Face)
{
	Style = FMath::Clamp(Style, -1.f, 1.f);
	FaceLook = FMath::Clamp(FaceLook, -1.f, 1.f);
	const FOKStudioStyleTuning& Tuning = OKStudioStyleTuning();
	if (FaceLook != 0.f)
	{
		const TArray<float> CardFace = Face;
		Pulled(FaceLook, FaceStyle, Face);
		// The jaw keeps the card's shape: the realistic end only goes part of the way, the chibi end widens a narrow jaw and leaves a wide one.
		if (FaceLook < 0.f)
		{
			// A narrow jaw is already sharp and takes little of it, a wide one takes more (chin width and cheek width, the card's).
			const float Jaw = Face.IsValidIndex(16) ? (CardFace[9] + CardFace[16]) * 0.5f : 0.f;
			const float Strength = FMath::Clamp(Tuning.RealJaw + 0.74f * (Jaw - 0.04f), 0.1f, 0.7f);
			for (int32 Index : { 0, 5, 6, 8, 9, 16, 17, 18 })
				if (Face.IsValidIndex(Index)) Face[Index] = FMath::Lerp(CardFace[Index], Face[Index], Strength);
			// Eyes going up and shrinking leave a longer face under them, which reads as a sharper chin.
			for (int32 Index : { 30, 33, 34, 35, 38, 40, 42 })
				if (Face.IsValidIndex(Index)) Face[Index] = FMath::Lerp(CardFace[Index], Face[Index], Tuning.RealFace);
		}
		else
		{
			for (int32 Index : { 0, 5, 9, 16 })
				if (Face.IsValidIndex(Index)) Face[Index] = FMath::Min(Face[Index], FMath::Max(CardFace[Index], CardFace[Index] + FaceLook * Tuning.ChibiJaw));
		}
		// The bottom of the chin rounds off at both ends, from the card's own: lowering the tip blunts it far more than widening it does.
		if (Face.IsValidIndex(13))
		{
			const float Round = FMath::Abs(FaceLook) * (FaceLook < 0.f ? Tuning.RealChin : Tuning.ChibiChin);
			Face[11] = CardFace[11] - Round;
			Face[13] = CardFace[13] + Round * 2.f;
		}
	}
	if (Style == 0.f) return;
	Pulled(Style, BodyStyle, Body);
	// The chibi end takes at most half of the card's breasts away.
	if (Body.IsValidIndex(4)) Body[4] = Style > 0.f ? FMath::Lerp(Body[4], FMath::Max(Body[4] * 0.5f, FMath::Min(Body[4], ChibiBreast)), Style) : Body[4] - Style * Pull * (OKStudioStyleTuning().Breast - Body[4]);
	if (Body.IsValidIndex(1)) Body[1] = Style > 0.f ? FMath::Lerp(Body[1], ChibiHead, Style * Pull) : FMath::Lerp(Body[1], FMath::Min(Body[1], RealHead(Body[0])), -Style);
}
