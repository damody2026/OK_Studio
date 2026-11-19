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
	// DIAGNOSTIC VALUE, not a fix. 240 is here to answer one question: is the window too short at all?
	// What this queue must outlive is "the GPU has not run that command list yet", and a frame counter does not
	// measure that -- a hitch, the RHI thread running ahead, or a blocked present all advance frames while the GPU
	// stands still. So no constant here is correctness, only "enough on this machine today"; a GPU fence on the
	// handover frame is the strict version of this queue, and it closes two real holes (a pooled target handed back
	// for reuse, a raw delete) -- but, per the next paragraph, it is probably not what this crash is.
	// 240 render frames is 1.45 s at the card reader's measured 165 FPS, which no command list the GPU has yet to run
	// can span -- and it still faulted on one of two trips. So what reads a released resource here is not pending GPU
	// work but something that cached it and keeps re-submitting it; a larger constant cannot be the answer either.
	// Left at 240 only while the per-call-site split cell runs, so the source matches the binary being measured.
	static constexpr uint32 DelayFrames = 240;

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
