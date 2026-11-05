#include "OKStudioVoiceTrack.h"
#include "OKSceneDocument.h"
#include "KKSpeech.h"
#include "Dom/JsonObject.h"
#include "Misc/AutomationTest.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace
{
	/** Seconds of a mono tone at this level. */
	OKStudioVoiceTrack::FPcm Tone(float Seconds, int32 Rate, float Level)
	{
		auto Pcm = MakeShared<FKKSpeechPcm, ESPMode::ThreadSafe>();
		Pcm->Channels = 1;
		Pcm->SampleRate = Rate;
		Pcm->Samples.SetNumUninitialized(FMath::RoundToInt(Seconds * Rate));
		for (int32 I = 0; I < Pcm->Samples.Num(); ++I) Pcm->Samples[I] = int16(FMath::Sin(I * 0.05f) * Level * 32767.f);
		return Pcm;
	}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioVoiceTrackTest, "OKStudio.VoiceTrack", EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FOKStudioVoiceTrackTest::RunTest(const FString&)
{
	using namespace OKStudioVoiceTrack;
	// The mouth: shut in silence, open with the sound, shut past the end; the same curve at any frame rate.
	const FPcm Loud = Tone(1.f, 48000, 0.5f);
	const TArray<float> Curve = MouthCurve(*Loud);
	TestTrue(TEXT("one value per step"), FMath::Abs(Curve.Num() - 61) <= 1);
	TestEqual(TEXT("shut before it starts"), MouthAt(Curve, -0.1f), 0.f);
	TestTrue(TEXT("open while it sounds"), MouthAt(Curve, 0.5f) > 0.5f);
	TestEqual(TEXT("shut after the end"), MouthAt(Curve, 1.5f), 0.f);
	TestEqual(TEXT("a curve is the same each time"), MouthCurve(*Loud), Curve);
	const TArray<float> Quiet = MouthCurve(*Tone(1.f, 48000, 0.f));
	TestEqual(TEXT("silence keeps it shut"), MouthAt(Quiet, 0.5f), 0.f);
	// The mix: a clip lands at its time, from the range's start, and the 44.1 kHz one still lasts its length.
	const TArray<float> None = Mix({ { Loud, 5.f, 1.f } }, 0.f, 2.f, 48000);
	TestTrue(TEXT("a clip outside the range gives no sound"), None.IsEmpty());
	const TArray<float> Mixed = Mix({ { Tone(0.5f, 44100, 0.5f), 1.f, 1.f } }, 0.5f, 1.5f, 48000);
	TestEqual(TEXT("stereo for the whole range"), Mixed.Num(), 1.5f * 48000 * 2 > 0 ? 144000 : 0);
	auto Peak = [&Mixed](float From, float To)
	{
		float Max = 0.f;
		for (int32 F = int32(From * 48000); F < int32(To * 48000); ++F) Max = FMath::Max(Max, FMath::Abs(Mixed[F * 2]));
		return Max;
	};
	TestEqual(TEXT("silent before the clip"), Peak(0.f, 0.49f), 0.f);
	TestTrue(TEXT("sounds at its time"), Peak(0.51f, 0.99f) > 0.4f);
	TestEqual(TEXT("silent after it"), Peak(1.01f, 1.5f), 0.f);
	const TArray<float> Cut = Mix({ { Loud, 0.f, 0.5f } }, 0.5f, 1.f, 48000);
	TestTrue(TEXT("volume counts"), Cut.Num() == 96000 && FMath::Abs(Cut[1000 * 2]) < 0.26f);

	// The fade: only over its time, from where the old motion stood at the key; a cut has none.
	UOKSceneDocument* Doc = NewObject<UOKSceneDocument>();
	FOKSceneObject& Who = Doc->Objects.AddDefaulted_GetRef();
	Who.Id = 7;
	Who.Kind = EOKSceneObjectKind::Character;
	FOKSceneTrack& T = Doc->Tracks.AddDefaulted_GetRef();
	T.ObjectId = 7;
	FOKSceneKey A, B;
	A.Time = 1.f; A.AnimNo = 3; A.AnimSpeed = 2.f; A.AnimStart = 0.25f;
	B.Time = 3.f; B.AnimNo = 4; B.AnimSpeed = 1.f; B.AnimBlend = 0.5f;
	T.Keys = { A, B };
	FOKSceneMotionFade Fade;
	TestFalse(TEXT("no fade before the key"), Doc->MotionFadeAt(7, 2.9f, Fade));
	TestTrue(TEXT("a fade at the key"), Doc->MotionFadeAt(7, 3.f, Fade));
	TestEqual(TEXT("from the old motion"), Fade.No, 3);
	TestEqual(TEXT("where it stood"), Fade.FromTime, 0.25f + 3.f * 2.f);
	TestEqual(TEXT("fade length"), Fade.Duration, 0.5f);
	TestTrue(TEXT("still in the fade"), Doc->MotionFadeAt(7, 3.4f, Fade));
	TestFalse(TEXT("over after its time"), Doc->MotionFadeAt(7, 3.5f, Fade));
	// The format: a fade or a clip asks for version 3, and only they do; both survive a reload.
	auto Version = [Doc] { TSharedPtr<FJsonObject> Root; FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Doc->ToJson()), Root); return Root.IsValid() ? int32(Root->GetNumberField(TEXT("version"))) : 0; };
	TestEqual(TEXT("a fade is version 3"), Version(), 3);
	UOKSceneDocument* Back = NewObject<UOKSceneDocument>();
	FString Error;
	TestTrue(TEXT("reads back"), Back->FromJson(Doc->ToJson(), Error));
	TestEqual(TEXT("the fade stays"), Back->Tracks.Num() == 1 && Back->Tracks[0].Keys.Num() == 2 ? Back->Tracks[0].Keys[1].AnimBlend : -1.f, 0.5f);
	T.Keys[1].AnimBlend = 0.f;
	TestFalse(TEXT("a cut has none"), Doc->MotionFadeAt(7, 3.f, Fade));
	TestEqual(TEXT("motion keys alone stay version 2"), Version(), 2);
	T.Keys[0].AnimNo = T.Keys[1].AnimNo = -2;
	TestEqual(TEXT("old scenes stay version 1"), Version(), 1);
	FOKSceneVoiceClip Said;
	Said.Start = 1.5f; Said.File = TEXT("line.wav");
	Who.Character.VoiceClips.Add(Said);
	TestEqual(TEXT("a clip is version 3"), Version(), 3);
	TestTrue(TEXT("reads back with a clip"), Back->FromJson(Doc->ToJson(), Error));
	const FOKSceneObject* Read = Back->Find(7);
	TestTrue(TEXT("the clip stays"), Read && Read->Character.VoiceClips.Num() == 1 && Read->Character.VoiceClips[0] == Said);
	return true;
}

#endif
