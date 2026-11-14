#pragma once
#include "CoreMinimal.h"
#include "Sound/SoundWaveProcedural.h"
#include "Sound/SoundGenerator.h"
#include <atomic>
#include "KKSpeech.generated.h"

USTRUCT(BlueprintType)
struct FKKSpeechLine {
    GENERATED_BODY()
    UPROPERTY(BlueprintReadOnly) FString Id;
    UPROPERTY(BlueprintReadOnly) FString Text;
    UPROPERTY(BlueprintReadOnly) FString AudioPath;
    UPROPERTY(BlueprintReadOnly) int32 Personality=0;
};

struct FKKSpeechPcm {
    TArray<int16> Samples;
    int32 SampleRate=0,Channels=0;
};
struct FKKSpeechMeter {
    TAtomic<float> Rms{0.f};
    TAtomic<int32> RenderedFrames{0};
    std::atomic<uint32> ClockSeq{0};
    std::atomic<double> BlockAudioSeconds{0.0};
    std::atomic<double> BlockWallSeconds{0.0};
    std::atomic<bool> bFinished{false};

    void WriteClockAnchor(double InAudioSeconds, double InWallSeconds, bool bInFinished) {
        const uint32 Seq = ClockSeq.load(std::memory_order_relaxed);
        ClockSeq.store(Seq + 1u, std::memory_order_release);
        BlockAudioSeconds.store(InAudioSeconds, std::memory_order_relaxed);
        BlockWallSeconds.store(InWallSeconds, std::memory_order_relaxed);
        bFinished.store(bInFinished, std::memory_order_relaxed);
        ClockSeq.store(Seq + 2u, std::memory_order_release);
    }

    bool ReadClockAnchor(uint32& InOutSeq, double& OutAudioSeconds, double& OutWallSeconds, bool& OutFinished) const {
        for (int32 Attempt = 0; Attempt < 4; ++Attempt) {
            const uint32 Seq1 = ClockSeq.load(std::memory_order_acquire);
            if (Seq1 == 0u || (Seq1 & 1u) != 0u) continue;
            const double AudioSec = BlockAudioSeconds.load(std::memory_order_relaxed);
            const double WallSec = BlockWallSeconds.load(std::memory_order_relaxed);
            const bool bFin = bFinished.load(std::memory_order_relaxed);
            std::atomic_thread_fence(std::memory_order_acquire);
            const uint32 Seq2 = ClockSeq.load(std::memory_order_relaxed);
            if (Seq1 == Seq2) {
                const bool bChanged = (Seq1 != InOutSeq);
                InOutSeq = Seq1;
                OutAudioSeconds = AudioSec;
                OutWallSeconds = WallSec;
                OutFinished = bFin;
                return bChanged;
            }
        }
        return false;
    }
};
// One face of the original's H face list (HFaceList_cNN_KK_AA, FaceListCtrl.SetFace): Eye -1 in an index exported before
// the whole face was (only the mouth then).
struct FKKHFace {
    int32 Eye=-1,Brow=-1,Mouth=0,Tears=0;
    float EyeOpen=1.f,MouthOpen=0.f,Cheek=0.f;
    bool bHighlight=true,bBlink=true;
};
struct FKKHBreathCue {
    FString Path;
    FString Name;
    TArray<int32> Mouths;
    TArray<float> OpenMins;
    TArray<FKKHFace> Faces; // as Mouths, the whole face
};
// What HVoiceCtrl.IsBreathPtnConditions and GetStateSelect read when they pick her breathing: her pleasure gauge (0..100;
// conditions 0 / 1 split at 50), his fast motion (voice.speedMotion, conditions 4 / 5), whether they move (12 / 13), and
// her HExperience (0 初めて .. 3 淫乱; the bank of files) with whether she has had him in her / in her behind before
// (state 8 / 9 use bank 0 until then). No hands, kiss, items or gentleness in the scenes that ask.
struct FKKHBreathContext {
    float Gauge=0.f;
    bool bFast=false;
    bool bMoving=false;
    int32 Experience=0;
    bool bHadVaginal=false;
    bool bHadAnal=false;
    // The intercourse voice table's conditions (HVoiceCtrl.IsPtnConditionsSonyu): in her anus, his condom, and her first
    // time there this scene while still a virgin (isVirgin && !count.isInsertKokan; the anal one likewise).
    bool bAnal=false;
    bool bCondom=false;
    bool bVirginFirst=false;
    bool bAnalVirginFirst=false;
};
namespace KKSpeech {
    // A voice's general lines, parsed once per index file (comm_lines.json) and voice; waits for a running prefetch.
    KKUNITYBUNDLE_API bool LoadLines(const FString& Root,int32 Personality,TArray<FKKSpeechLine>& Lines,FString& Error);
    // LoadLines started on the thread pool (a card load names the voice before its speech panel asks for it).
    KKUNITYBUNDLE_API void PrefetchLines(const FString& Root,int32 Personality);
    KKUNITYBUNDLE_API bool DecodeOgg(const FString& Path,TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe>& Out,FString& Error);
    // DecodeOgg without its cache of decoded clips (a file read once, e.g. one of her spoken lines).
    KKUNITYBUNDLE_API bool DecodeOggUncached(const FString& Path,TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe>& Out,FString& Error);
    KKUNITYBUNDLE_API float MouthRate(float Rms,float& Previous);
    KKUNITYBUNDLE_API ISoundGeneratorPtr MakeGenerator(TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe> Pcm,TSharedPtr<FKKSpeechMeter,ESPMode::ThreadSafe> Meter,float StartSeconds=0.f,int32 OutputRate=0);
    // First-time H breath (experience bucket 0) for one animator state.
    KKUNITYBUNDLE_API bool CollectHBreath(const FString& Root,int32 Personality,int32 Mode,const FString& State,int32 AnimId,bool bMoving,TArray<FKKHBreathCue>& Out,FString& Error);
    // Her breathing for one animator state as the original picks it now (gauge, speed, her experience bank).
    KKUNITYBUNDLE_API bool CollectHBreath(const FString& Root,int32 Personality,int32 Mode,const FString& State,int32 AnimId,const FKKHBreathContext& Context,TArray<FKKHBreathCue>& Out,FString& Error);
    KKUNITYBUNDLE_API bool PrepareHBreathIndex(const FString& Root,FString& Error);
    // Her cries for one row of the intercourse voice table (HSonyu plays 300 + row: 25 her climax in the slow loop, 26 in
    // the fast one) for this animation, from her experience bank (h_breath_index version 2 "voices").
    // The same sound played Tempo times as fast at its own pitch (WSOLA: overlapped windows taken further apart, each
    // matched to the last by its waveform). Tempo 1 or less returns In.
    KKUNITYBUNDLE_API TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe> TimeStretch(const TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe>& In,float Tempo);
    KKUNITYBUNDLE_API bool CollectHVoice(const FString& Root,int32 Personality,int32 Row,int32 AnimId,const FKKHBreathContext& Context,TArray<FKKHBreathCue>& Out,FString& Error);
}

UCLASS()
class KKUNITYBUNDLE_API UKKSpeechWave : public USoundWaveProcedural {
    GENERATED_BODY()
public:
    void Init(TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe> InPcm,int32 PlaybackSampleRate);
    virtual ISoundGeneratorPtr CreateSoundGenerator(const FSoundGeneratorInitParams& Params) override;
    TSharedPtr<const FKKSpeechPcm,ESPMode::ThreadSafe> Pcm;
    TSharedPtr<FKKSpeechMeter,ESPMode::ThreadSafe> Meter;
};
