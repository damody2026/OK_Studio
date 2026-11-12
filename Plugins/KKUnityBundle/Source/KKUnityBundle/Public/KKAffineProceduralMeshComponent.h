#pragma once

#include "CoreMinimal.h"
#include "ProceduralMeshComponent.h"
#include "KKGpuStream.h"
#include "KKAffineProceduralMeshComponent.generated.h"

// Borrowed for one blocking game-thread call. Attribute arrays remain immutable
// until packing finishes; each request must target a distinct mesh section.
struct FKKAnimatedStreamRequest {
    UProceduralMeshComponent* Component=nullptr;int32 Section=0;
    const TArray<FVector>* Positions=nullptr;const TArray<FVector>* Normals=nullptr;
    const TArray<FProcMeshTangent>* Tangents=nullptr;
};
struct FKKGeneratedStreamRequest {
    UProceduralMeshComponent* Component=nullptr;int32 Section=0;
};

// Caller jobs own disjoint, complete draw ranges; source preparation for a range
// must finish in the same job before Emit. No captured UObject/FFI calls on workers.
using FKKGeneratedStreamRange = TFunctionRef<void(int32,int32,int32)>;
using FKKGeneratedSectionWriter = TFunctionRef<void(int32,FProcMeshVertex&)>;
using FKKGeneratedSectionEmitter = TFunctionRef<void(int32,FKKGeneratedSectionWriter)>;

// Native bone matrices can contain shear after nonuniform shape scaling.
// Keep immutable mesh vertices and apply that affine remainder in the renderer.
UCLASS()
class KKUNITYBUNDLE_API UKKAffineProceduralMeshComponent : public UProceduralMeshComponent
{
    GENERATED_BODY()
public:
    // Opt-in for owned, collision-free preview meshes. Stock PMCs retain
    // their original proxy and APIs, including third-party components.
    bool bUseAnimatedStreams = false;
    // Collision-free layers may retain a conservative render envelope while
    // CPU section bounds and authored vertices remain exact for current poses.
    bool bUseConservativeAnimatedBounds = false;
    // Reserve a validated local culling envelope without rewriting tight CPU
    // section bounds. Current vertices always remain part of CalcBounds.
    void ExpandAnimatedRenderBounds(const FBox& LocalEnvelope);
    static void UpdateAnimatedStreamsBatch(TArrayView<const FKKAnimatedStreamRequest> Requests);
    // Generator changes only position/normal/tangent of disjoint vertices.
    // All captured source data must stay immutable until this blocking call returns.
    static bool UpdateGeneratedStreamsBatch(TArrayView<const FKKGeneratedStreamRequest> Requests,
        TFunctionRef<void(int32,int32,FProcMeshVertex&)> Generate);
    // Source jobs may write independent canonical arrays; Generate must not read
    // those arrays concurrently. All jobs finish before bounds or render publication.
    static bool UpdateGeneratedStreamsBatchWithSourceJobs(TArrayView<const FKKGeneratedStreamRequest> Requests,
        TFunctionRef<void(int32,int32,FProcMeshVertex&)> Generate, int32 SourceJobCount,
        TFunctionRef<void(int32)> GenerateSource);
    static bool UpdateGeneratedStreamsBySourceRanges(TArrayView<const FKKGeneratedStreamRequest> Requests,
        int32 JobCount,TFunctionRef<void(int32,FKKGeneratedStreamRange)> GenerateJob,
        TFunctionRef<void(int32,int32,FProcMeshVertex&)> GenerateVertex);
    // External blocking scheduler owns one complete section per emit. Missing
    // sections retain their previous streams; publisher only touches emitted data.
    static bool UpdateGeneratedStreamsExternally(TArrayView<const FKKGeneratedStreamRequest> Requests,
        TFunctionRef<void(FKKGeneratedSectionEmitter)> Schedule);
    virtual FPrimitiveSceneProxy* CreateSceneProxy() override;
    // The stock procedural component collects nothing, so each material compiled its shaders in the frame that first
    // drew it; both proxies draw with FLocalVertexFactory.
    virtual void CollectPSOPrecacheData(const FPSOPrecacheParams& Base, FMaterialInterfacePSOPrecacheParamsList& Out) override;
    // Ask for a material's PSOs as one of these components (movable, casting shadows) will draw it, before any does: the
    // high model's parents as they load, so its first frame in the one-on-one does not wait for them (once per material).
    static void PrecacheAhead(UMaterialInterface* Material);
    // Called (game thread) with each material PrecacheAhead takes for the first time: a host asks for the parents it will
    // swap in for that one later (the H scene's _Bias clothes) the same way.
    static TFunction<void(UMaterialInterface*)>& PrecacheAheadVariants();
    static void UpdateStreams(UProceduralMeshComponent* Component, int32 Section,
        const TArray<FVector>& Positions, const TArray<FVector>& Normals,
        const TArray<FVector2D>& UV0, const TArray<FVector2D>& UV1,
        const TArray<FVector2D>& UV2, const TArray<FVector2D>& UV3,
        const TArray<FColor>& Colors, const TArray<FProcMeshTangent>& Tangents);
    static void UpdateStreams(UProceduralMeshComponent* Component, int32 Section,
        const TArray<FVector>& Positions, const TArray<FVector>& Normals,
        const TArray<FVector2D>& UV0, const TArray<FColor>& Colors,
        const TArray<FProcMeshTangent>& Tangents)
    {
        const TArray<FVector2D> Empty;
        UpdateStreams(Component, Section, Positions, Normals, UV0, Empty, Empty, Empty, Colors, Tangents);
    }
    static void SetStreamSectionVisible(UProceduralMeshComponent* Component, int32 Section, bool bVisible);
    bool UsesAnimatedStreams() const;
    uint64 GetGpuStreamProxyEpoch() const {return GpuStreamProxyEpoch;}
    // Game thread; moves an owned packet to RT without waiting. Rejected work
    // retains the previous streams. Requires collision-free animated proxy.
    TSharedRef<FKKGpuStreamReceipt,ESPMode::ThreadSafe> SubmitGpuStreams(int32 Section,FKKGpuStreamRequest Request);
    static void SubmitGpuStreamsBatch(TArray<FKKGpuStreamSectionRequest> Requests);
    TSharedRef<FKKGpuStreamReceipt,ESPMode::ThreadSafe> SubmitGpuCoating(int32 Section,UKKAffineProceduralMeshComponent* Source,int32 SourceSection,FKKGpuCoatingRequest Request);
#if WITH_DEV_AUTOMATION_TESTS
    bool VerifyAnimatedRenderStreams(int32 Section, uint32 UVUploads, uint32 ColorUploads);
    bool VerifyGpuRenderStreams(int32 Section,const TArray<FProcMeshVertex>& Expected,uint64 Generation);
#endif
    void SetRenderResidual(const FMatrix& Matrix);
    virtual FMatrix GetRenderMatrix() const override;
    virtual FBoxSphereBounds CalcBounds(const FTransform& LocalToWorld) const override;
    // Where the sections are now. Bounds only grow while the GPU draws a section, so that a late publication is not culled.
    FBox CurrentWorldBounds() const;
private:
    void PublishAnimatedStreamBounds();
    FBox AnimatedBoundsEnvelope = FBox(ForceInit);
    // The bounds of each section's latest GPU publication; empty while the CPU writes the sections.
    TMap<int32,FBox> GpuSectionBounds;
    FMatrix RenderResidual = FMatrix::Identity;
    uint64 GpuStreamProxyEpoch=0;
};
