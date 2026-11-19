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
	// DIAGNOSTIC, not a fix. How many render frames each kind waits is a cvar, so a scale can be changed without a
	// build and the four kinds can be told apart:
	//   DreamGUI.DeferredRelease.Frames.Texture  -- Hold(FTextureRHIRef)
	//   DreamGUI.DeferredRelease.Frames.Buffer   -- Hold(FBufferRHIRef)
	//   DreamGUI.DeferredRelease.Frames.Pooled   -- Hold(TRefCountPtr<IPooledRenderTarget>), a GRenderTargetPool element
	//                                               handed back for reuse, which is not the same as destroyed
	//   DreamGUI.DeferredRelease.Frames.Func     -- Later(TUniqueFunction), a raw delete
	// Each defaults to 3, which is what the whole queue used before they were split.
	//
	// A frame count is NOT a correctness criterion and no value here is a fix: 240 frames is 1.45 s at the card
	// reader's measured 165 FPS, which no command list the GPU has yet to run can span, and it still faulted on one
	// of two trips. What the counts are for is telling the kinds apart -- whichever kind's scale moves the crash
	// carries the resource that is read after it is let go.

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
