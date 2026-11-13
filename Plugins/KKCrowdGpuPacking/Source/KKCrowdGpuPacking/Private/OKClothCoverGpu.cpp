#include "OKClothCoverGpu.h"
#include "OKRuntimeGpuDeform.h"
#include "GlobalShader.h"
#include "ShaderParameterStruct.h"
#include "RenderGraphUtils.h"
#include "RenderingThread.h"

// One shader type: ClothCover.usf MainCS runs the step it is given (EStep, its switch).
enum class EOKClothStep:uint32 {Skin=0,Follow,Rise,ClearCandidates,Clear,RiseHeld,Grow,RiseRing,PushAt,PushRing,FlipSet,FlipCheck,FlipApply,Result,ClearHits};
class FOKClothCoverCS:public FGlobalShader {
 DECLARE_GLOBAL_SHADER(FOKClothCoverCS);
 SHADER_USE_PARAMETER_STRUCT(FOKClothCoverCS,FGlobalShader);
 BEGIN_SHADER_PARAMETER_STRUCT(FParameters,)
  SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<FSource>,Sources)
  SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<float4>,PaletteRows)
  SHADER_PARAMETER(uint32,PaletteCount)
  SHADER_PARAMETER(uint32,FallbackSlot)
  SHADER_PARAMETER(uint32,HasPostSkinCorrection)
  SHADER_PARAMETER(FVector4f,PostSkinRow0)
  SHADER_PARAMETER(FVector4f,PostSkinRow1)
  SHADER_PARAMETER(FVector4f,PostSkinRow2)
  SHADER_PARAMETER_RDG_BUFFER_SRV(ByteAddressBuffer,Field)
  SHADER_PARAMETER_RDG_BUFFER_SRV(ByteAddressBuffer,Garment)
  SHADER_PARAMETER(uint32,VertexCount)
  SHADER_PARAMETER(uint32,TriangleCount)
  SHADER_PARAMETER(uint32,Round)
  SHADER_PARAMETER(uint32,Step)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float4>,Pos)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float4>,Follow)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float>,Rise)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float>,RiseWas)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float4>,Push)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float4>,PushWas)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<uint>,Taken)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<uint>,Counts)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<uint>,Changed)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<uint>,TriFlag)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<uint>,Flags)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float4>,Moves)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<uint>,TriHits)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<uint>,TriStart)
  SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<float4>,Hits)
  SHADER_PARAMETER(uint32,HitCapacity)
 END_SHADER_PARAMETER_STRUCT()
 static bool ShouldCompilePermutation(const FGlobalShaderPermutationParameters& P){return IsFeatureLevelSupported(P.Platform,ERHIFeatureLevel::SM5);}
};
IMPLEMENT_GLOBAL_SHADER(FOKClothCoverCS,"/Plugin/KKCrowdGpuPacking/ClothCover.usf","MainCS",SF_Compute);

bool OKClothCoverAvailable(){auto* Map=GetGlobalShaderMap(GMaxRHIFeatureLevel);return Map&&Map->HasShader(&FOKClothCoverCS::GetStaticType(),0);}

bool OKMakeClothCoverJob(FOKClothCoverJob& Job){
 Job.bCover=Job.bFollow=Job.bLift=false;Job.VertexCount=Job.TriangleCount=0;
 if(!Job.Field.IsValid()||!Job.Garment.IsValid())return false;
 const TArray<uint32>& F=*Job.Field;const TArray<uint32>& G=*Job.Garment;
 if(F.Num()<16||G.Num()<16)return false;
 Job.VertexCount=G[0];Job.TriangleCount=G[4];
 if(F[0]!=0xFFFFFFFFu){
  if(uint64(F[0])+40>uint64(F.Num()))return false;
  const uint32 Flags=F[F[0]+1];Job.bCover=true;Job.bLift=(Flags&4)!=0;Job.bFollow=(Flags&2)!=0&&G[6]!=0;
 }
 return Job.VertexCount>0;
}

// The blobs uploaded once each (the same shared array: the same buffer), render thread.
struct FOKClothBlob {TSharedPtr<const TArray<uint32>,ESPMode::ThreadSafe> Data;TRefCountPtr<FRDGPooledBuffer> Buffer;};
static TArray<FOKClothBlob> GOKClothBlobs;
static FRDGBufferRef OKClothBlob(FRDGBuilder& G,const TSharedPtr<const TArray<uint32>,ESPMode::ThreadSafe>& Data,const TCHAR* Name){
 for(int32 I=0;I<GOKClothBlobs.Num();++I)if(GOKClothBlobs[I].Data==Data){FOKClothBlob Hit=GOKClothBlobs[I];GOKClothBlobs.RemoveAt(I);GOKClothBlobs.Add(Hit);return G.RegisterExternalBuffer(Hit.Buffer);}
 const uint32 Bytes=FMath::Max<uint32>(16,uint32(Data->Num())*4);
 auto* Buffer=G.CreateBuffer(FRDGBufferDesc::CreateByteAddressDesc(Bytes),Name);
 G.QueueBufferUpload(Buffer,Data->GetData(),uint64(Data->Num())*4);
 FOKClothBlob Entry{Data,G.ConvertToExternalBuffer(Buffer)};GOKClothBlobs.Add(Entry);
 // A field a frame per heroine and each garment's still data: the oldest go.
 while(GOKClothBlobs.Num()>96)GOKClothBlobs.RemoveAt(0);
 return Buffer;
}

// A garment drawn in several sections installs its whole source in each one, all with this frame's same field, palette and
// garment: worked out once (the first section), the others take that result. The field is a new array every frame, so its
// pointer (with the garment's) names the frame's result.
// Held by the arrays themselves (not their addresses): a freed field's address may come back as the next frame's.
// Diagnosis only (the moves come out wrong): steps left out, a bit each (1<<EOKClothStep), to find what costs the GPU.
static TAutoConsoleVariable<int32> CVarOkClothGpuSkip(TEXT("ok.ClothGpuSkip"),0,TEXT("Diagnosis: ok.ClothGpu 2 steps not run, bit per step (Skin 0 .. Result 13; e.g. 16 leaves out the lift's sequential clear). 0 (default) all"),ECVF_RenderThreadSafe);
static TAutoConsoleVariable<int32> CVarOkClothGpuOnePass(TEXT("ok.ClothGpuOnePass"),1,TEXT("ok.ClothGpu 2: 1 (default) a garment's steps in one RDG pass with UAV barriers between them; 0 one RDG pass a step (the same work)"),ECVF_RenderThreadSafe);
struct FOKClothResult {TSharedPtr<const TArray<uint32>,ESPMode::ThreadSafe> Field,Garment;TRefCountPtr<FRDGPooledBuffer> Moves;};
static TArray<FOKClothResult> GOKClothResults;

FRDGBufferRef OKAddClothCoverPasses(FRDGBuilder& G,FRDGBufferRef Source,FRDGBufferRef Palette,uint32 PaletteCount,uint32 FallbackSlot,const FMatrix44f* Post,const FOKClothCoverJob& Job){
 check(IsInRenderingThread());
 if(!OKClothCoverAvailable()||!Job.IsValid()||!Source||!Palette||Source->Desc.NumElements<Job.VertexCount||FallbackSlot>=PaletteCount)return nullptr;
 const uint32 N=Job.VertexCount,T=FMath::Max<uint32>(Job.TriangleCount,1);
 if(FMath::DivideAndRoundUp(FMath::Max(N,T),64u)>65535)return nullptr;
 for(const FOKClothResult& Done:GOKClothResults)if(Done.Field==Job.Field&&Done.Garment==Job.Garment)return G.RegisterExternalBuffer(Done.Moves);
 auto* Field=OKClothBlob(G,Job.Field,TEXT("ClothCover.Field"));auto* Garment=OKClothBlob(G,Job.Garment,TEXT("ClothCover.Garment"));
 auto F4=[&](const TCHAR* Name,uint32 Count){return G.CreateBuffer(FRDGBufferDesc::CreateStructuredDesc(sizeof(FVector4f),Count),Name);};
 auto F1=[&](const TCHAR* Name,uint32 Count){return G.CreateBuffer(FRDGBufferDesc::CreateStructuredDesc(sizeof(float),Count),Name);};
 auto U1=[&](const TCHAR* Name,uint32 Count){return G.CreateBuffer(FRDGBufferDesc::CreateStructuredDesc(sizeof(uint32),Count),Name);};
 auto* Pos=F4(TEXT("ClothCover.Pos"),N);auto* Follow=F4(TEXT("ClothCover.Follow"),N);auto* Rise=F1(TEXT("ClothCover.Rise"),N);auto* RiseWas=F1(TEXT("ClothCover.RiseWas"),N);
 auto* Push=F4(TEXT("ClothCover.Push"),N);auto* PushWas=F4(TEXT("ClothCover.PushWas"),N);auto* Taken=U1(TEXT("ClothCover.Taken"),N*2);
 auto* Counts=U1(TEXT("ClothCover.Counts"),N);auto* Changed=U1(TEXT("ClothCover.Changed"),N);auto* TriFlag=U1(TEXT("ClothCover.TriFlag"),T);
 auto* Flags=U1(TEXT("ClothCover.Flags"),8);auto* Moves=F4(TEXT("ClothCover.Moves"),N);
 TArray<FVector4f> Correction;FString Error;const FMatrix44f& Placement=Post?*Post:FMatrix44f::Identity;
 if(!OKPrepareGpuDeformPalette(MakeArrayView(&Placement,1),Correction,Error))return nullptr;
 TShaderMapRef<FOKClothCoverCS> Shader(GetGlobalShaderMap(GMaxRHIFeatureLevel));
 // The views made once, every pass a copy of these parameters with its own step (a view per buffer per pass cost the render
 // thread ~30 ms a frame over her garments).
 FOKClothCoverCS::FParameters Base;
 Base.Sources=G.CreateSRV(Source);Base.PaletteRows=G.CreateSRV(Palette);Base.PaletteCount=PaletteCount;Base.FallbackSlot=FallbackSlot;
 Base.HasPostSkinCorrection=Post?1:0;Base.PostSkinRow0=Correction[0];Base.PostSkinRow1=Correction[1];Base.PostSkinRow2=Correction[2];
 Base.Field=G.CreateSRV(Field);Base.Garment=G.CreateSRV(Garment);Base.VertexCount=N;Base.TriangleCount=Job.TriangleCount;Base.Round=0;Base.Step=0;
 Base.Pos=G.CreateUAV(Pos);Base.Follow=G.CreateUAV(Follow);Base.Rise=G.CreateUAV(Rise);Base.RiseWas=G.CreateUAV(RiseWas);Base.Push=G.CreateUAV(Push);Base.PushWas=G.CreateUAV(PushWas);
 Base.Taken=G.CreateUAV(Taken);Base.Counts=G.CreateUAV(Counts);Base.Changed=G.CreateUAV(Changed);Base.TriFlag=G.CreateUAV(TriFlag);Base.Flags=G.CreateUAV(Flags);Base.Moves=G.CreateUAV(Moves);
 // The lift's clear: each candidate triangle's samples, found in parallel (more than this: the shader's long way, still exact).
 const uint32 HitCapacity=FMath::Max<uint32>(T*4,16384);
 Base.TriHits=G.CreateUAV(U1(TEXT("ClothCover.TriHits"),T));Base.TriStart=G.CreateUAV(U1(TEXT("ClothCover.TriStart"),T));
 Base.Hits=G.CreateUAV(F4(TEXT("ClothCover.Hits"),HitCapacity));Base.HitCapacity=HitCapacity;
 const int32 Skip=CVarOkClothGpuSkip.GetValueOnRenderThread();
 struct FStep {uint32 Step,Groups,Round;};TArray<FStep> Steps;
 auto Pass=[&](EOKClothStep Step,uint32 Count,uint32 Round=0){
  if(Skip&(1<<uint32(Step)))return;
  Steps.Add({uint32(Step),FMath::DivideAndRoundUp(FMath::Max(Count,1u),64u),Round});
 };
 Pass(EOKClothStep::Skin,N);
 if(Job.bFollow)Pass(EOKClothStep::Follow,N);
 if(Job.bLift&&Job.TriangleCount){
  Pass(EOKClothStep::Rise,N);Pass(EOKClothStep::ClearCandidates,Job.TriangleCount);Pass(EOKClothStep::ClearHits,Job.TriangleCount);Pass(EOKClothStep::Clear,64);Pass(EOKClothStep::RiseHeld,N);
  for(uint32 R=0;R<6;++R)Pass(EOKClothStep::RiseRing,N,R); // grows and averages in one pass (ClothCover.usf)
 }
 if(Job.bCover){
  Pass(EOKClothStep::PushAt,N);
  for(uint32 R=0;R<6;++R)Pass(EOKClothStep::PushRing,N,R);
  if(Job.TriangleCount){Pass(EOKClothStep::FlipSet,Job.TriangleCount);for(uint32 R=0;R<6;++R){Pass(EOKClothStep::FlipCheck,Job.TriangleCount,R);Pass(EOKClothStep::FlipApply,N,R);}}
 }
 Pass(EOKClothStep::Result,N);
 if(CVarOkClothGpuOnePass.GetValueOnRenderThread()==0){
  for(const FStep& S:Steps){auto* P=G.AllocParameters<FOKClothCoverCS::FParameters>();*P=Base;P->Round=S.Round;P->Step=S.Step;
   FComputeShaderUtils::AddPass(G,RDG_EVENT_NAME("ClothCover.Step%u",S.Step),Shader,P,FIntVector(S.Groups,1,1));}
 }else{
  // One RDG pass for the garment: the steps dispatched in order inside it, a UAV barrier on every buffer between them (the
  // same work on the GPU; RDG's per-pass bookkeeping over ~30 steps x her garments cost the render thread ~4 ms a frame).
  auto* P=G.AllocParameters<FOKClothCoverCS::FParameters>();*P=Base;
  G.AddPass(RDG_EVENT_NAME("ClothCover"),P,ERDGPassFlags::Compute,[P,Shader,Steps=MoveTemp(Steps)](FRHIComputeCommandList& RHICmdList){
   const FRDGBufferUAVRef Uavs[]={P->Pos,P->Follow,P->Rise,P->RiseWas,P->Push,P->PushWas,P->Taken,P->Counts,P->Changed,P->TriFlag,P->Flags,P->Moves,P->TriHits,P->TriStart,P->Hits};
   TArray<FRHITransitionInfo,TInlineAllocator<16>> Barrier;
   for(FRDGBufferUAVRef U:Uavs)Barrier.Add(FRHITransitionInfo(U->GetRHI(),ERHIAccess::UAVCompute,ERHIAccess::UAVCompute));
   for(int32 I=0;I<Steps.Num();++I){
    FOKClothCoverCS::FParameters Each=*P;Each.Round=Steps[I].Round;Each.Step=Steps[I].Step;
    FComputeShaderUtils::Dispatch(RHICmdList,Shader,Each,FIntVector(Steps[I].Groups,1,1));
    if(I+1<Steps.Num())RHICmdList.Transition(MakeArrayView(Barrier));
   }
  });
 }
 GOKClothResults.Add({Job.Field,Job.Garment,G.ConvertToExternalBuffer(Moves)});
 // A frame's garments of every heroine: the oldest go.
 while(GOKClothResults.Num()>32)GOKClothResults.RemoveAt(0);
 return Moves;
}
