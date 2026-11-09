#include "OKStudioVoiceTrack.h"
#include "OKStudioGame.h"
#include "OKStudioGameInternal.h"
#include "OKSceneActor.h"
#include "OKStudioCatalog.h"
#include "KKPreviewActor.h"
#include "KKSpeech.h"
#include "Async/Async.h"
#include "AudioDevice.h"
#include "Components/AudioComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include <atomic>

TArray<float> OKStudioVoiceTrack::MouthCurve(const FKKSpeechPcm& Pcm)
{
	TArray<float> Curve;
	if (Pcm.Channels <= 0 || Pcm.SampleRate <= 0) return Curve;
	const int32 Frames = Pcm.Samples.Num() / Pcm.Channels;
	const int32 Window = FMath::Max(Pcm.SampleRate * 1024 / 48000, 1);
	const int32 Steps = FMath::CeilToInt(float(Frames) / Pcm.SampleRate / MouthStep);
	Curve.Reserve(Steps + 1);
	float Previous = 0.f;
	for (int32 Step = 0; Step <= Steps; ++Step)
	{
		const int32 End = FMath::Min(int32(double(Step) * MouthStep * Pcm.SampleRate), Frames);
		double Sum = 0.;
		for (int32 I = FMath::Max(End - Window, 0); I < End; ++I)
		{
			const double V = Pcm.Samples[I * Pcm.Channels] / 32768.;
			Sum += V * V;
		}
		Curve.Add(KKSpeech::MouthRate(float(FMath::Sqrt(Sum / Window)), Previous));
	}
	return Curve;
}

float OKStudioVoiceTrack::MouthAt(const TArray<float>& Curve, float Seconds)
{
	if (Curve.IsEmpty() || Seconds < 0.f) return 0.f;
	const float At = Seconds / MouthStep;
	const int32 I = FMath::FloorToInt(At);
	if (I + 1 >= Curve.Num()) return 0.f;
	return FMath::Lerp(Curve[I], Curve[I + 1], At - I);
}

TArray<float> OKStudioVoiceTrack::Mix(const TArray<FMixClip>& Clips, float From, float Seconds, int32 Rate)
{
	TArray<float> Out;
	const int32 Frames = FMath::RoundToInt(Seconds * Rate);
	if (Frames <= 0 || Rate <= 0) return Out;
	bool bAny = false;
	for (const FMixClip& Clip : Clips)
	{
		if (!Clip.Pcm || Clip.Pcm->Channels <= 0 || Clip.Pcm->SampleRate <= 0) continue;
		const FKKSpeechPcm& P = *Clip.Pcm;
		const int32 Source = P.Samples.Num() / P.Channels;
		const double Length = double(Source) / P.SampleRate;
		// The output frames the clip covers.
		const int32 First = FMath::Max(FMath::CeilToInt((Clip.Start - From) * Rate), 0);
		const int32 Last = FMath::Min(FMath::CeilToInt((double(Clip.Start) + Length - From) * Rate), Frames);
		if (First >= Last) continue;
		if (!bAny) { Out.SetNumZeroed(Frames * 2); bAny = true; }
		const int32 Second = P.Channels > 1 ? 1 : 0;
		for (int32 F = First; F < Last; ++F)
		{
			const double Position = (double(From) + double(F) / Rate - Clip.Start) * P.SampleRate;
			const int32 I = FMath::Clamp(int32(Position), 0, Source - 1), J = FMath::Min(I + 1, Source - 1);
			const float U = float(Position - I);
			auto Sample = [&](int32 Channel) { return FMath::Lerp(float(P.Samples[I * P.Channels + Channel]), float(P.Samples[J * P.Channels + Channel]), U) / 32768.f * Clip.Volume; };
			Out[F * 2] += Sample(0);
			Out[F * 2 + 1] += Sample(Second);
		}
	}
	return Out;
}

bool OKStudioVoiceTrack::WriteWav(const FString& File, const TArray<float>& Stereo, int32 Rate)
{
	const int32 DataBytes = Stereo.Num() * 2;
	TArray<uint8> Bytes;
	Bytes.Reserve(44 + DataBytes);
	auto Tag = [&Bytes](const char* S) { Bytes.Append(reinterpret_cast<const uint8*>(S), 4); };
	auto U32 = [&Bytes](uint32 V) { for (int32 I = 0; I < 4; ++I) Bytes.Add(uint8(V >> (I * 8))); };
	auto U16 = [&Bytes](uint32 V) { Bytes.Add(uint8(V)); Bytes.Add(uint8(V >> 8)); };
	Tag("RIFF"); U32(36 + DataBytes); Tag("WAVE");
	Tag("fmt "); U32(16); U16(1); U16(2); U32(Rate); U32(Rate * 4); U16(4); U16(16);
	Tag("data"); U32(DataBytes);
	for (const float V : Stereo) U16(uint16(int16(FMath::Clamp(FMath::RoundToInt(V * 32767.f), -32768, 32767))));
	return FFileHelper::SaveArrayToFile(Bytes, *File);
}

/** A voice clip's sound, decoded on a worker with its mouth curve. */
struct FOKStudioVoiceSound
{
	OKStudioVoiceTrack::FPcm Pcm;
	TArray<float> Curve;
	float Seconds = 0.f;
	std::atomic<bool> bDone{ false };
};

FString UOKStudioGame::VoiceClipFile(const FOKSceneVoiceClip& Clip) const
{
	// Asked every frame for every clip: the library search and the file checks once.
	const FString Key = Clip.No >= 0 ? FString::Printf(TEXT("%d/%d/%d"), Clip.Group, Clip.Category, Clip.No) : File + TEXT("|") + Clip.File;
	if (const FString* Known = VoiceClipPaths.Find(Key)) return *Known;
	FString Path;
	if (Clip.No >= 0) Path = FOKStudioCatalog::Get().VoiceSound(Clip.Group, Clip.Category, Clip.No);
	else if (!Clip.File.IsEmpty())
	{
		Path = FPaths::IsRelative(Clip.File) && !File.IsEmpty() ? FPaths::GetPath(File) / Clip.File : Clip.File;
		Path = FPaths::FileExists(Path) ? FPaths::ConvertRelativePathToFull(Path) : FString();
	}
	if (!Path.IsEmpty()) VoiceClipPaths.Add(Key, Path);
	return Path;
}

FString UOKStudioGame::VoiceClipName(const FOKSceneVoiceClip& Clip) const
{
	if (Clip.No < 0) return FPaths::GetBaseFilename(Clip.File);
	const FOKStudioVoice* V = FOKStudioCatalog::Get().FindVoice(Clip.Group, Clip.Category, Clip.No);
	return V ? V->Name : FString::Printf(TEXT("%d/%d/%d"), Clip.Group, Clip.Category, Clip.No);
}

const FOKStudioVoiceSound* UOKStudioGame::VoiceClipSound(const FOKSceneVoiceClip& Clip, bool bWait) const
{
	const FString Path = VoiceClipFile(Clip);
	if (Path.IsEmpty()) return nullptr;
	TSharedPtr<FOKStudioVoiceSound, ESPMode::ThreadSafe>& Sound = VoiceSounds.FindOrAdd(Path);
	auto Decode = [Path](FOKStudioVoiceSound& Into)
	{
		FString Error;
		if (OKStudioGameInternal::LoadAudioFile(Path, Into.Pcm, Error) && Into.Pcm && Into.Pcm->Channels > 0 && Into.Pcm->SampleRate > 0)
		{
			Into.Curve = OKStudioVoiceTrack::MouthCurve(*Into.Pcm);
			Into.Seconds = float(Into.Pcm->Samples.Num() / Into.Pcm->Channels) / Into.Pcm->SampleRate;
		}
		else UE_LOG(LogTemp, Warning, TEXT("OK studio: voice %s failed to load: %s"), *Path, *Error);
		Into.bDone = true;
	};
	if (!Sound)
	{
		Sound = MakeShared<FOKStudioVoiceSound, ESPMode::ThreadSafe>();
		if (bWait) Decode(*Sound);
		else Async(EAsyncExecution::ThreadPool, [Sound = Sound, Decode] { Decode(*Sound); });
	}
	while (bWait && !Sound->bDone) FPlatformProcess::Sleep(0.001f);
	return Sound->bDone && Sound->Seconds > 0.f ? Sound.Get() : nullptr;
}

float UOKStudioGame::VoiceClipSeconds(const FOKSceneVoiceClip& Clip) const
{
	const FOKStudioVoiceSound* Sound = VoiceClipSound(Clip, false);
	return Sound ? Sound->Seconds : 1.f;
}

float UOKStudioGame::VoiceMouth(int32 Id, float Time) const
{
	const FOKSceneObject* O = Document ? Document->Find(Id) : nullptr;
	float Open = 0.f;
	if (O)
		for (const FOKSceneVoiceClip& Clip : O->Character.VoiceClips)
			if (Time >= Clip.Start)
				if (const FOKStudioVoiceSound* Sound = VoiceClipSound(Clip, false))
					Open = FMath::Max(Open, OKStudioVoiceTrack::MouthAt(Sound->Curve, Time - Clip.Start));
	return Open;
}

int32 UOKStudioGame::VoiceClipsSounding() const
{
	int32 Count = 0;
	for (const TPair<FString, TWeakObjectPtr<UAudioComponent>>& A : VoiceClipAudio) Count += A.Value.IsValid() && A.Value->IsPlaying();
	return Count;
}

void UOKStudioGame::ApplyVoiceMouth(float Time)
{
	if (!SceneActor || !Document) return;
	for (const FOKSceneObject& O : Document->Objects)
	{
		if (O.Kind != EOKSceneObjectKind::Character || (O.Character.VoiceClips.IsEmpty() && !VoiceMouthIds.Contains(O.Id))) continue;
		const float Open = VoiceMouth(O.Id, Time);
		if (AKKPreviewActor* P = SceneActor->PreviewOf(O.Id)) P->SetMouthOpenFloor(Open);
		if (Open > 0.f) VoiceMouthIds.Add(O.Id); else VoiceMouthIds.Remove(O.Id);
	}
}

void UOKStudioGame::StopVoiceClipAudio()
{
	for (TPair<FString, TWeakObjectPtr<UAudioComponent>>& A : VoiceClipAudio)
		if (A.Value.IsValid()) A.Value->Stop();
	VoiceClipAudio.Reset();
}

void UOKStudioGame::UpdateVoiceClips()
{
	if (VoiceClipScene != File) { StopVoiceClipAudio(); VoiceSounds.Reset(); VoiceClipPaths.Reset(); VoiceClipScene = File; }
	// Going back (a loop) says the clips again from there; a seek has stopped them already.
	if (TimelineTime < VoiceClipTime - 1e-3f) StopVoiceClipAudio();
	VoiceClipTime = TimelineTime;
	const bool bSound = bTimelinePlaying && TimelineSpeed > 0.f && !bMuteSound && !IsExporting();
	const float Speed = FOKAudioMasterClock::ClampAudioSpeed(TimelineSpeed);
	UWorld* World = GetTickableGameObjectWorld();
	TSet<FString> Now;
	for (const FOKSceneObject& O : Document->Objects)
	{
		if (O.Kind != EOKSceneObjectKind::Character) continue;
		for (const FOKSceneVoiceClip& Clip : O.Character.VoiceClips)
		{
			const FOKStudioVoiceSound* Sound = VoiceClipSound(Clip, false);
			const float At = TimelineTime - Clip.Start;
			if (!Sound || !bSound || At < 0.f || At >= Sound->Seconds || !World) continue;
			const FString Key = FString::Printf(TEXT("%d|%.4f|%s"), O.Id, Clip.Start, *VoiceClipFile(Clip));
			Now.Add(Key);
			const float Volume = FMath::Clamp(SoundVolume * Clip.Volume, 0.f, 2.f);
			if (const TWeakObjectPtr<UAudioComponent>* Playing = VoiceClipAudio.Find(Key))
			{
				if (Playing->IsValid()) { (*Playing)->SetVolumeMultiplier(Volume); (*Playing)->SetPitchMultiplier(Speed); }
				continue;
			}
			UKKSpeechWave* Wave = NewObject<UKKSpeechWave>(this);
			Wave->Init(Sound->Pcm, World->GetAudioDevice().IsValid() ? World->GetAudioDevice()->GetSampleRate() : Sound->Pcm->SampleRate);
			Wave->VirtualizationMode = EVirtualizationMode::PlayWhenSilent;
			UAudioComponent* Comp = UGameplayStatics::CreateSound2D(World, Wave, Volume, Speed, At, nullptr, false, true);
			if (!Comp) continue;
			Comp->bAlwaysPlay = true;
			Comp->bIsUISound = true;
			Comp->Play(At);
			VoiceClipAudio.Add(Key, Comp);
		}
	}
	for (auto It = VoiceClipAudio.CreateIterator(); It; ++It)
		if (!Now.Contains(It.Key()))
		{
			if (It.Value().IsValid()) It.Value()->Stop();
			It.RemoveCurrent();
		}
	ApplyVoiceMouth(TimelineTime);
}

void UOKStudioGame::AddVoiceClip(int32 Id, const FOKSceneVoiceClip& Clip)
{
	FOKSceneObject* O = Document->Find(Id);
	if (!O || O->Kind != EOKSceneObjectKind::Character) return;
	O->Character.VoiceClips.Add(Clip);
	if (const FOKStudioVoiceSound* Sound = VoiceClipSound(Clip, true)) Document->Duration = FMath::Max(Document->Duration, Clip.Start + Sound->Seconds);
	Document->NotifyChanged();
}

void UOKStudioGame::LoadVoiceClips() const
{
	for (const FOKSceneObject& O : Document->Objects)
		for (const FOKSceneVoiceClip& Clip : O.Character.VoiceClips) VoiceClipSound(Clip, true);
}

bool UOKStudioGame::WriteExportMix(const FString& Wav)
{
	TArray<OKStudioVoiceTrack::FMixClip> Clips;
	for (const FOKSceneObject& O : Document->Objects)
		for (const FOKSceneVoiceClip& Clip : O.Character.VoiceClips)
			if (const FOKStudioVoiceSound* Sound = VoiceClipSound(Clip, true)) Clips.Add({ Sound->Pcm, Clip.Start, Clip.Volume });
	// The scene's own sound runs with the timeline as well.
	if (EnsureSceneAudioPcmLoaded()) Clips.Add({ SceneAudioPcm, Document->SoundDelay, 1.f });
	constexpr int32 Rate = 48000;
	const TArray<float> Mixed = OKStudioVoiceTrack::Mix(Clips, ExportFrom, ExportTotal / ExportFps, Rate);
	return !Mixed.IsEmpty() && OKStudioVoiceTrack::WriteWav(Wav, Mixed, Rate);
}
