#pragma once
#include "RenderGraphBuilder.h"

// Her garment pushed out over her skin and moved with her thighs' jiggle on the GPU (ok.ClothGpu 2; ClothCover.usf):
// the same steps as the CPU route (Rust belly_bulge/cover.rs, thigh_jiggle.rs follow_own). Field: this pose's skin of
// her (Rust cloth_gpu.rs build_field), Garment: the garment's still data (cloth_gpu.rs garment). Both are 32-bit words.
struct FOKClothCoverJob {
 TSharedPtr<const TArray<uint32>,ESPMode::ThreadSafe> Field,Garment;
 uint32 VertexCount=0,TriangleCount=0;
 bool bCover=false,bFollow=false,bLift=false; // read off the field / garment headers (OKMakeClothCoverJob)
 bool IsValid() const {return Field.IsValid()&&Garment.IsValid()&&VertexCount>0;}
};
// Fills the flags from the blobs; false when they do not fit together.
KKCROWDGPUPACKING_API bool OKMakeClothCoverJob(FOKClothCoverJob& Job);
KKCROWDGPUPACKING_API bool OKClothCoverAvailable();
// The passes: each source vertex's move (float4, native metres after the post correction), or nullptr when rejected.
// Source / Palette / Post as the resident deform has them.
KKCROWDGPUPACKING_API FRDGBufferRef OKAddClothCoverPasses(FRDGBuilder& G,FRDGBufferRef Source,FRDGBufferRef Palette,
 uint32 PaletteCount,uint32 FallbackSlot,const FMatrix44f* PostSkinCorrection,const FOKClothCoverJob& Job);
