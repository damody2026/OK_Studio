// Copyright 2026-Present TypeDreamMoon. All Rights Reserved.

#include "DreamUIRender/DreamUIMaterialProxy.h"
#include "DreamUIRender/DreamUIDeferredRelease.h"

#include "Engine/Texture.h"
#include "MaterialDomain.h"
#include "Materials/Material.h"
#include "Materials/MaterialInterface.h"
#include "RenderGraphBuilder.h"
#include "RenderingThread.h"
#include "HAL/IConsoleManager.h"
#include "HAL/ThreadSafeCounter.h"
#include "UObject/UObjectGlobals.h"

namespace DreamUIMaterialProxyLocal
{
	template<typename ValueType>
	void SetByName(TArray<TPair<FName, ValueType>>& InOutValues, FName InName, const ValueType& InValue)
	{
		for (TPair<FName, ValueType>& Value : InOutValues)
		{
			if (Value.Key == InName)
			{
				Value.Value = InValue;
				return;
			}
		}
		InOutValues.Emplace(InName, InValue);
	}

	template<typename ValueType>
	const ValueType* FindByName(const TArray<TPair<FName, ValueType>>& InValues, FName InName)
	{
		for (const TPair<FName, ValueType>& Value : InValues)
		{
			if (Value.Key == InName)
			{
				return &Value.Value;
			}
		}
		return nullptr;
	}

	/** Every proxy made and not yet deleted, for the collector's hook. Game thread only. */
	TArray<TWeakPtr<FDreamUIMaterialProxy, ESPMode::ThreadSafe>>& LiveProxies()
	{
		static TArray<TWeakPtr<FDreamUIMaterialProxy, ESPMode::ThreadSafe>> Proxies;
		return Proxies;
	}

	/** The collector found nothing holding InObject, or it is garbage: it is not to be drawn with again. */
	bool IsGone(const UObject* InObject)
	{
		return InObject != nullptr && (InObject->IsUnreachable() || !IsValid(InObject));
	}
}

void FDreamUIMaterialParameters::SetTexture(FName InName, const UTexture* InTexture)
{
	DreamUIMaterialProxyLocal::SetByName(Textures, InName, InTexture);
}

void FDreamUIMaterialParameters::SetVector(FName InName, const FLinearColor& InValue)
{
	DreamUIMaterialProxyLocal::SetByName(Vectors, InName, InValue);
}

void FDreamUIMaterialParameters::SetScalar(FName InName, float InValue)
{
	DreamUIMaterialProxyLocal::SetByName(Scalars, InName, InValue);
}

bool FDreamUIMaterialParameters::operator==(const FDreamUIMaterialParameters& InOther) const
{
	return Textures == InOther.Textures && Vectors == InOther.Vectors && Scalars == InOther.Scalars;
}

namespace DreamUIMaterialProxyExperiment
{
	// EXPERIMENT (default off), and NOT a fix candidate: when on, a proxy that has lost its last reference is never
	// deleted at all -- it is deliberately leaked. The point is to separate two things that FDreamUIDeferredRelease
	// cannot: "the destructor runs" from "the destructor runs 240 frames later". Frames.Func=240 only moved the
	// crash from card 4/7 to 19/15, so a count cannot say whether the destructor is the trigger. Never running it
	// can.
	//
	// Reading registered before the run: if the crash disappears in BOTH reproductions, the trigger is the proxy's
	// destructor itself (which lets go of the texture refcounts its uniform buffer holds for the material, and
	// MainPS binds the same textures). If it still faults, the destructor is not the trigger and the delay seen at
	// Frames.Func=240 is some other timing effect.
	//
	// The leak is bounded and measured, not assumed: 30 card loads is a finite number of proxies, so the counter
	// below is logged and the trip's process RAM is read alongside it. It must never ship: a leak that makes a
	// crash disappear is a diagnostic, not a repair.
	static TAutoConsoleVariable<int32> CVarNeverDeleteProxy(
		TEXT("DreamGUI.Experiment.NeverDeleteProxy"), 0,
		TEXT("Experiment: never delete a material proxy that lost its last reference (deliberate leak, diagnostic only)."),
		ECVF_RenderThreadSafe);

	static FThreadSafeCounter Leaked;

	/** True when this proxy is to be leaked on purpose; logs how many have been, so the leak can be seen to be bounded. */
	static bool LeakInsteadOfDeleting()
	{
		if (CVarNeverDeleteProxy.GetValueOnAnyThread() == 0)
		{
			return false;
		}
		const int32 Count = Leaked.Increment();
		if (Count <= 10 || (Count % 50) == 0)
		{
			UE_LOG(LogTemp, Warning, TEXT("DreamGUI EXPERIMENT: material proxy leaked on purpose, total=%d"), Count);
		}
		return true;
	}
}

TSharedRef<FDreamUIMaterialProxy, ESPMode::ThreadSafe> FDreamUIMaterialProxy::Create(UMaterialInterface* InSource)
{
	check(IsInGameThread());
	// After reachability analysis, before anything unreachable is destroyed, let alone freed.
	static const FDelegateHandle Unreachable = FCoreUObjectDelegates::PostReachabilityAnalysis.AddStatic(&FDreamUIMaterialProxy::LetGoOfUnreachable);
	// Deleted on the render thread, as a material instance's render proxy is: the last reference may go on either
	// thread, and a frame the render thread has yet to record may still draw with it.
	TSharedRef<FDreamUIMaterialProxy, ESPMode::ThreadSafe> Proxy = MakeShareable(new FDreamUIMaterialProxy(InSource), [](FDreamUIMaterialProxy* InProxy)
	{
		if (DreamUIMaterialProxyExperiment::LeakInsteadOfDeleting())
		{
			return;
		}
		// Deleted a few frames later still (FDreamUIDeferredRelease): a graph already recorded may read its uniform buffer.
		if (IsInRenderingThread())
		{
			FDreamUIDeferredRelease::Later([InProxy]() { delete InProxy; });
			return;
		}
		ENQUEUE_RENDER_COMMAND(FDreamUIMaterialProxyDelete)(
			[InProxy](FRHICommandListImmediate& RHICmdList)
			{
				FDreamUIDeferredRelease::Later([InProxy]() { delete InProxy; });
			});
	});
	DreamUIMaterialProxyLocal::LiveProxies().Add(Proxy);
	return Proxy;
}

FDreamUIMaterialProxy::FDreamUIMaterialProxy(UMaterialInterface* InSource)
	: FMaterialRenderProxy(InSource != nullptr ? InSource->GetName() : FString(TEXT("FDreamUIMaterialProxy")))
	, GameThreadSource(InSource)
	, RenderThreadSource(InSource)
{
}

void FDreamUIMaterialProxy::SetParameters_GameThread(const FDreamUIMaterialParameters& InParameters)
{
	GameThreadParameters = InParameters;
	// Held by the command: whoever lets go of the proxy meanwhile has it deleted after the command, not before.
	ENQUEUE_RENDER_COMMAND(FDreamUIMaterialProxySetParameters)(
		[Proxy = AsShared(), Parameters = InParameters](FRHICommandListImmediate& RHICmdList) mutable
		{
			Proxy->RenderThreadParameters = MoveTemp(Parameters);
			// What the material shaders read: made again from the new values, the proxy made a render resource on the way.
			Proxy->CacheUniformExpressions(RHICmdList, false);
		});
}

void FDreamUIMaterialProxy::FollowSource_RenderThread(FRHICommandListBase& RHICmdList, ERHIFeatureLevel::Type InFeatureLevel)
{
	const FMaterialRenderProxy* Parent = GetParent();
	// The serial moves whenever the source's own cache is let go of or made again, which is what a parameter set on a
	// material instance does to it.
	const int32 Serial = Parent->GetExpressionCacheSerialNumber();
	if (Parent == FollowedParent && Serial == FollowedSerial)
	{
		return;
	}
	FollowedParent = Parent;
	FollowedSerial = Serial;
	// What UpdateUniformExpressionCacheIfNeeded reads as out of date, and makes again at once from GetParameterValue --
	// the source's current values. Not InvalidateUniformExpressionCache, which also waits on the uniform expression
	// updater's task and broadcasts editor invalidations, from a gathering of dynamic meshes that may run on a task. The
	// passes a graph still executes asynchronously read this cache, so they are waited for first, as the update does.
	FRDGBuilder::WaitForAsyncExecuteTask();
	UniformExpressionCache[InFeatureLevel].CachedUniformExpressionShaderMap = nullptr;
	UpdateUniformExpressionCacheIfNeeded(RHICmdList, InFeatureLevel);
}

void FDreamUIMaterialProxy::LetGoOfUnreachable()
{
	using namespace DreamUIMaterialProxyLocal;
	TArray<TWeakPtr<FDreamUIMaterialProxy, ESPMode::ThreadSafe>>& Proxies = LiveProxies();
	for (int32 Index = Proxies.Num() - 1; Index >= 0; --Index)
	{
		const TSharedPtr<FDreamUIMaterialProxy, ESPMode::ThreadSafe> Proxy = Proxies[Index].Pin();
		if (!Proxy.IsValid())
		{
			Proxies.RemoveAtSwap(Index);
			continue;
		}
		const bool bSourceGone = IsGone(Proxy->GameThreadSource);
		const bool bTextureGone = Proxy->GameThreadParameters.Textures.ContainsByPredicate(
			[](const TPair<FName, const UTexture*>& InTexture) { return IsGone(InTexture.Value); });
		if (!bSourceGone && !bTextureGone)
		{
			continue;
		}
		if (bSourceGone)
		{
			Proxy->GameThreadSource = nullptr;
		}
		Proxy->GameThreadParameters.Textures.RemoveAll(
			[](const TPair<FName, const UTexture*>& InTexture) { return IsGone(InTexture.Value); });
		// Carried out before the objects are freed: freeing them waits for the render thread to pass their release.
		ENQUEUE_RENDER_COMMAND(FDreamUIMaterialProxyLetGo)(
			[Proxy, Source = Proxy->GameThreadSource, Parameters = Proxy->GameThreadParameters](FRHICommandListImmediate& RHICmdList) mutable
			{
				Proxy->RenderThreadSource = Source;
				Proxy->RenderThreadParameters = MoveTemp(Parameters);
				Proxy->CacheUniformExpressions(RHICmdList, false);
			});
	}
}

const FMaterialRenderProxy* FDreamUIMaterialProxy::GetParent() const
{
	if (RenderThreadSource != nullptr)
	{
		if (const FMaterialRenderProxy* Parent = RenderThreadSource->GetRenderProxy())
		{
			return Parent;
		}
	}
	return UMaterial::GetDefaultMaterial(MD_Surface)->GetRenderProxy();
}

const FMaterial* FDreamUIMaterialProxy::GetMaterialNoFallback(ERHIFeatureLevel::Type InFeatureLevel) const
{
	return GetParent()->GetMaterialNoFallback(InFeatureLevel);
}

const FMaterialRenderProxy* FDreamUIMaterialProxy::GetFallback(ERHIFeatureLevel::Type InFeatureLevel) const
{
	return GetParent()->GetFallback(InFeatureLevel);
}

UMaterialInterface* FDreamUIMaterialProxy::GetMaterialInterface() const
{
	return RenderThreadSource;
}

bool FDreamUIMaterialProxy::GetParameterValue(EMaterialParameterType Type, const FHashedMaterialParameterInfo& ParameterInfo, FMaterialParameterValue& OutValue, const FMaterialRenderContext& Context) const
{
	// DreamGUI's parameters are global ones: a parameter of the same name inside a material layer is the layer's.
	if (ParameterInfo.Association == EMaterialParameterAssociation::GlobalParameter)
	{
		using namespace DreamUIMaterialProxyLocal;
		const FName Name = ParameterInfo.GetName();
		switch (Type)
		{
		case EMaterialParameterType::Texture:
			// No texture is no answer, as a material instance ignores one set to none: the material's own default stands.
			if (const UTexture* const* Texture = FindByName(RenderThreadParameters.Textures, Name); Texture != nullptr && *Texture != nullptr)
			{
				OutValue = *Texture;
				return true;
			}
			break;
		case EMaterialParameterType::Vector:
			if (const FLinearColor* Vector = FindByName(RenderThreadParameters.Vectors, Name))
			{
				OutValue = *Vector;
				return true;
			}
			break;
		case EMaterialParameterType::Scalar:
			if (const float* Scalar = FindByName(RenderThreadParameters.Scalars, Name))
			{
				OutValue = *Scalar;
				return true;
			}
			break;
		default:
			break;
		}
	}
	return GetParent()->GetParameterValue(Type, ParameterInfo, OutValue, Context);
}
