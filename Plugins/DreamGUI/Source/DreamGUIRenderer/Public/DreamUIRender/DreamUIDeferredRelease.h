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
	// DIAGNOSTIC VALUE, not a fix. 12 is here to answer one question: is three frames too short?
	// What this queue must outlive is "the GPU has not run that command list yet", and a frame counter does not
	// measure that -- a hitch, the RHI thread running ahead, or a blocked present all advance frames while the GPU
	// stands still. So no constant here is correctness, only "enough on this machine today"; the real fix is to
	// hold until the RHI frame fence of the frame that handed the resource over has completed, and to put
	// UDreamCanvas::DrawTextureHolds (which keeps 8 frames) on that same criterion rather than on another number.
	// Picked as 12 because the canvas already keeps 8: whatever the right answer is, 3 and 8 cannot both be it.
	static constexpr uint32 DelayFrames = 12;

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
