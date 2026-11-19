// Copyright 2026-Present TypeDreamMoon. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Materials/MaterialRenderProxy.h"
#include "Templates/SharedPointer.h"
#include "UObject/WeakObjectPtrTemplates.h"

class UMaterialInterface;
class UTexture;

/** The parameters DreamGUI gives a material of its own, by name: what a material instance per draw call used to carry. */
struct DREAMGUIRENDERER_API FDreamUIMaterialParameters
{
	TArray<TPair<FName, TWeakObjectPtr<const UTexture>>> Textures;
	TArray<TPair<FName, FLinearColor>> Vectors;
	TArray<TPair<FName, float>> Scalars;

	void SetTexture(FName InName, const UTexture* InTexture);
	void SetVector(FName InName, const FLinearColor& InValue);
	void SetScalar(FName InName, float InValue);

	bool operator==(const FDreamUIMaterialParameters& InOther) const;
	bool operator!=(const FDreamUIMaterialParameters& InOther) const { return !(*this == InOther); }
};

/**
 * A draw call's material as DreamGUI draws it: the source material's own render proxy, with DreamGUI's parameters
 * answered in its place -- the way the engine's FColoredTexturedMaterialRenderProxy answers a colour and a texture. It
 * stands where a material instance per draw call used to, without a UObject: nothing to pool as an object, to keep
 * from the collector, or to be copied along with a component into a saved level.
 *
 * Persistent, because the material shaders read the uniform expressions it caches. Made on the game thread and held by
 * shared pointer from both threads; whichever lets go last has it deleted on the render thread. Its parameters change
 * by render command (SetParameters_GameThread), which caches its uniform expressions again.
 *
 * The source material and the textures in its parameters are the giver's to keep alive: the proxy names them weakly,
 * and the render thread resolves them as it reads them -- what has been collected comes back as nothing, which is the
 * same answer the proxy gives for a parameter never set. The collector's hook below still runs, so a source or texture
 * on its way out is let go of while it is still there to name: a source gone leaves the default material, a texture
 * gone the material's own default.
 */
class DREAMGUIRENDERER_API FDreamUIMaterialProxy : public FMaterialRenderProxy, public TSharedFromThis<FDreamUIMaterialProxy, ESPMode::ThreadSafe>
{
public:
	/** Game thread. */
	static TSharedRef<FDreamUIMaterialProxy, ESPMode::ThreadSafe> Create(UMaterialInterface* InSource);

	/** Game thread: the material the proxy answers for. */
	UMaterialInterface* GetSource() const { return GameThreadSource.Get(); }
	/** Game thread: the parameters the proxy answers with from the next frame on. The last ones given are kept here too. */
	void SetParameters_GameThread(const FDreamUIMaterialParameters& InParameters);
	const FDreamUIMaterialParameters& GetParameters_GameThread() const { return GameThreadParameters; }
	/**
	 * Render thread, as a draw through the proxy is collected: when the source's own render proxy has made its uniform
	 * expressions again since this one last looked -- the material instance it answers for had a parameter set by its
	 * owner -- this one's are made again too, from the source's new values. They are otherwise made only when DreamGUI's
	 * parameters change, which froze a material instance's own animation at the frame it was first drawn.
	 */
	void FollowSource_RenderThread(FRHICommandListBase& RHICmdList, ERHIFeatureLevel::Type InFeatureLevel);

	//~ Begin FMaterialRenderProxy Interface
	virtual const FMaterial* GetMaterialNoFallback(ERHIFeatureLevel::Type InFeatureLevel) const override;
	virtual const FMaterialRenderProxy* GetFallback(ERHIFeatureLevel::Type InFeatureLevel) const override;
	virtual UMaterialInterface* GetMaterialInterface() const override;
	virtual bool GetParameterValue(EMaterialParameterType Type, const FHashedMaterialParameterInfo& ParameterInfo, FMaterialParameterValue& OutValue, const FMaterialRenderContext& Context) const override;
	//~ End FMaterialRenderProxy Interface

private:
	explicit FDreamUIMaterialProxy(UMaterialInterface* InSource);
	/** The source's own render proxy, asked for each time as the engine's scene proxies ask for theirs. */
	const FMaterialRenderProxy* GetParent() const;
	/** After the collector's reachability analysis: every proxy lets go of what is about to be freed. */
	static void LetGoOfUnreachable();

	TWeakObjectPtr<UMaterialInterface> GameThreadSource;
	TWeakObjectPtr<UMaterialInterface> RenderThreadSource;
	FDreamUIMaterialParameters GameThreadParameters;
	FDreamUIMaterialParameters RenderThreadParameters;
	/**
	 * The source material the parent proxy was asked of, and its cache's serial number, as FollowSource_RenderThread
	 * last saw them. The material, not the parent proxy's address: an address that is freed and handed out again names
	 * something else with the same identity, and a weak pointer cannot. Render thread.
	 */
	TWeakObjectPtr<UMaterialInterface> FollowedSource;
	int32 FollowedSerial = -1;
};
