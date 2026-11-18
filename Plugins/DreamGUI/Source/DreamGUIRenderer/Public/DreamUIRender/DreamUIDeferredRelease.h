// OpenKoikatsu patch (2026-11-19), not upstream DreamGUI.
#pragma once
#include "CoreMinimal.h"
#include "RHIResources.h"
#include "RendererInterface.h"

/**
 * GPU resources DreamGUI lets go of, kept a few render frames longer before they are really released.
 *
 * Three times a resource DreamGUI had just replaced or freed was still read by a draw the GPU had not run yet -- the
 * font atlas, a thumbnail, a texture the pool moved -- each a GPU page fault in DreamGUI's view extension. This queue
 * closes that whole class at once: what is handed to it lives DelayFrames render frames past the frame it was handed
 * over in, whatever recorded or translated command list still points at it. Any thread (the render thread, its graph setup tasks).
 */
class DREAMGUIRENDERER_API FDreamUIDeferredRelease
{
public:
	static constexpr uint32 DelayFrames = 3;

	static void Hold(FTextureRHIRef InTexture);
	static void Hold(FBufferRHIRef InBuffer);
	static void Hold(TRefCountPtr<IPooledRenderTarget> InPooled);
	/** Runs InRelease DelayFrames render frames from now (a delete, a ReleaseResource). */
	static void Later(TUniqueFunction<void()> InRelease);

	/** Releases what has waited long enough. Called once a frame from the view extension (render thread). */
	static void Tick_RenderThread();
	/** How many are waiting (DreamGUI.LogDeferredRelease). */
	static int32 Num();
};
