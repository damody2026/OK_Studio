#pragma once
#include "CoreMinimal.h"
class UTexture2D;
inline constexpr int32 OKRuntimeTextureMaxDimension=1024;
struct FKKRuntimeTextureSettings {
 int32 Filter=1,WrapU=0,WrapV=0;bool SRGB=true,EncodedMips=false;
 bool operator==(const FKKRuntimeTextureSettings& B)const{return Filter==B.Filter&&WrapU==B.WrapU&&WrapV==B.WrapV&&SRGB==B.SRGB&&EncodedMips==B.EncodedMips;}
};
struct FKKRuntimeTextureMip {int32 Width=0,Height=0;TArray<uint8> BGRA;};
struct FKKRuntimePreparedTexture {
 FString SourceHash;FKKRuntimeTextureSettings Settings;TArray<FKKRuntimeTextureMip> Mips;
 // Hash of the settings and every mip's pixels (the GPU texture cache key), computed where the mips are built: hashing
 // them again on the game thread cost 20-40 ms per large texture, for every character the reader built.
 FString PixelIdentity;
 int32 SourceWidth=0,SourceHeight=0;
};
struct FKKRuntimeMaterialTexture {FString Property;int32 Texture=INDEX_NONE;};
struct FKKRuntimeMaterialPart {
 int32 NativePart=INDEX_NONE,ShaderKind=0,Unlit=0,ItemDraw=0,EyeDraw=0;bool Outline=false;
 FString Name,Role,Blend,SourceMetadataJson;
 TMap<FString,FVector4f> Values;TArray<FKKRuntimeMaterialTexture> Textures;
 // Material properties the host sets over the source material's (Unity names and values, as Material.SetColor /
 // SetFloat would: OK Studio item colours). Empty for card parts.
 TMap<FString,FLinearColor> Overrides;
};
struct FKKRuntimeMaterialData {
 TArray<FKKRuntimeMaterialPart> Parts;TArray<FKKRuntimePreparedTexture> Textures;
 uint64 EncodedBytes=0,PixelBytes=0;double PrepareMs=0;bool WorkerThread=false;
};
struct OkSession;
struct FKKRuntimePalettePart;
KKRUNTIMEPOSE_API bool OKCaptureRuntimeMaterials(OkSession*,TConstArrayView<FKKRuntimePalettePart>,FKKRuntimeMaterialData&,FString& Error);
// The same, every distinct texture decoded and mipped in parallel (what OK_FIRSTLOAD=C5 makes the default): for a load
// the player waits on, off the game thread (the one-on-one scene's high model).
KKRUNTIMEPOSE_API bool OKCaptureRuntimeMaterialsParallel(OkSession*,TConstArrayView<FKKRuntimePalettePart>,FKKRuntimeMaterialData&,FString& Error);
// One part's description (source metadata and card-resolved values) without decoding its textures: what an own-graph
// material needs to run the part's installed programs (OKMakeRuntimeOutlineVertexOffset).
KKRUNTIMEPOSE_API bool OKDescribeRuntimeMaterialPart(OkSession*,int32 NativePart,FKKRuntimeMaterialPart&,FString& Error);
// Game thread, no image decoding or material compilation. Caller retains UObject.
// Returned textures are immutable and may be shared across characters. A caller
// needing editable pixels must create a private texture rather than mutate these.
KKRUNTIMEPOSE_API UTexture2D* OKCreateRuntimePreparedTexture(const FKKRuntimePreparedTexture&,FString& Error);

/** The character textures kept for a switch back; they hold a refcount, so GC cannot take them. */
struct FKKRuntimeTextureKeepStats {int32 Entries=0,StaleEntries=0;int64 Bytes=0,StaleBytes=0;};
KKRUNTIMEPOSE_API FKKRuntimeTextureKeepStats OKRuntimeTextureKeepStats();
/** Marks every kept texture as untouched; the load that follows touches the ones it uses itself. */
KKRUNTIMEPOSE_API void OKMarkKeptRuntimeTexturesStale();
/** Releases the kept textures nothing has touched since the mark (returns how many, and their bytes). */
KKRUNTIMEPOSE_API int32 OKReleaseStaleKeptRuntimeTextures(int64* OutBytes=nullptr);
// Diagnostic (log only, gated by ok.LogKeptTextureLife, default off), for the GPU page fault of 2026-11-19.
// Records who a card texture was handed to, so that at the moment the kept cache lets the texture go we can ask
// of every material that ever received it: is that material still here, and what does that parameter point at now?
// Three answers, three different repairs: still here pointing elsewhere (render-thread copy is stale),
// still here pointing at this one (the material itself is unreachable), or gone (the holder is not a material).
KKRUNTIMEPOSE_API void OKRecordRuntimeTextureHandoff(const UTexture2D* Texture,const class UMaterialInstanceDynamic* Material,FName Parameter);
/** Releases every kept texture. */
KKRUNTIMEPOSE_API void OKReleaseKeptRuntimeTextures();
// Low-memory PC (Docs/STREET_CITY_STREAMING_LOWSPEC_20261114.md): on when the machine has under 48 GB of RAM or under
// 20 GB of VRAM (the city took 12-13 GB of VRAM at full quality, so a 16 GB card counts too), or with -OKLowMemory; -OKNoLowMemory turns it off. Runtime character textures are then capped to
// kk.RuntimeTextureLowMemoryMaxSize (512) and their CPU copy is dropped once uploaded.
KKRUNTIMEPOSE_API bool OKRuntimeLowMemory();
// Low-memory PC: a runtime texture's CPU pixels go at the end of the frame it was uploaded in, not at the upload itself
// (BULKDATA_SingleUse): its maker often changes SRGB / clamp / LOD group and uploads it again right after, and with the
// pixels already gone that second upload was empty, so the card reader's colour-grading LUT turned the whole view black
// (2026-11-18). No-op otherwise.
KKRUNTIMEPOSE_API void OKDropRuntimeTexturePixelsAfterFrame(UTexture2D* Texture);
// Before changing a runtime texture's settings and calling UpdateResource in a later frame (a texture made earlier, from
// a cache): reads its pixels back from the GPU when the low-memory mode dropped them, and drops them again after this
// frame. True when the texture has its pixels.
KKRUNTIMEPOSE_API bool OKRestoreRuntimeTexturePixels(UTexture2D* Texture);
struct FKKRuntimeTextureCacheStats {uint64 Requests=0,Hits=0,Created=0,AvoidedPixelBytes=0,PreparedCacheHits=0,PreparedDecodeJobs=0,PreparedJoinedJobs=0;uint32 Entries=0;};
KKRUNTIMEPOSE_API FKKRuntimeTextureCacheStats OKRuntimeTextureCacheStats();

// Plain-data mip preparation; encoded native render textures keep byte-space averaging.
KKRUNTIMEPOSE_API bool OKBuildRuntimeTextureMips(TArray<uint8> BGRA,int32 Width,int32 Height,
 const FKKRuntimeTextureSettings&,TArray<FKKRuntimeTextureMip>& Out,FString& Error);
struct FKKRuntimeMaterialStats {uint32 Parts=0,Slots=0,Textures=0,Mips=0,SharedInstances=0,UnsupportedParts=0,OpaqueInstances=0,AlphaMaskedInstances=0,AlphaTranslucentInstances=0,ItemInstances=0,HairInstances=0,HairFrontInstances=0,StudioAlphaInstances=0,EyeWhiteInstances=0,EyeInstances=0,KoikanoEyeWhiteInstances=0,KoikanoEyeInstances=0,NoseInstances=0,AdditionalInstances=0;bool SharedParentUsed=false,SourceRasterVerified=false,SourceMeshShadersVerified=false,SourceMeshPixelsVerified=false,SourceMeshRasterPixelsVerified=false;uint64 PixelBytes=0;double PrepareMs=0;};
