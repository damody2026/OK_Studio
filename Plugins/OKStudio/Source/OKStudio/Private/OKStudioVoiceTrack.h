#pragma once

#include "CoreMinimal.h"

struct FKKSpeechPcm;

/** The sums behind voices on the timeline (U233～U235), apart from the scene so the self tests can run them. */
namespace OKStudioVoiceTrack
{
	using FPcm = TSharedPtr<const FKKSpeechPcm, ESPMode::ThreadSafe>;

	/** The mouth curve's step: the frame rate KKSpeech::MouthRate's smoothing is made for. */
	constexpr float MouthStep = 1.f / 60.f;

	/** How open a mouth saying Pcm is, one value per MouthStep: what the live meter gives (1024 samples of the first
	 *  channel into KKSpeech::MouthRate), but the same however fast the frames come. */
	TArray<float> MouthCurve(const FKKSpeechPcm& Pcm);
	float MouthAt(const TArray<float>& Curve, float Seconds);

	struct FMixClip
	{
		FPcm Pcm;
		float Start = 0.f;
		float Volume = 1.f;
	};
	/** Interleaved stereo of the clips over [From, From + Seconds); empty when none of them sounds there. */
	TArray<float> Mix(const TArray<FMixClip>& Clips, float From, float Seconds, int32 Rate);
	bool WriteWav(const FString& File, const TArray<float>& Stereo, int32 Rate);
}
