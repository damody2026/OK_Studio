#pragma once
#include "CoreMinimal.h"

/** Diagnostic (log only, gated by ok.LogTextureLifetime, default off): one line for a runtime texture at a point
 *  in its life, printing the UObject name -- the same key the D3D12 page-fault report shows for a released
 *  allocation. Added 2026-11-19 to trace a faulting GPU address back to whoever created and released it.
 *  Visible on a clean run too, unlike an instrument that only reports from inside a crash handler. */
KKUNITYBUNDLE_API void OKLogRuntimeTextureLife(const TCHAR* Event, const class UTexture2D* Tex, int64 Bytes);

/** Diagnostic (ok.LogTextureLifetime=2): walks every live UTexture2D and prints identity, including the outer
 *  that names whoever created it. Game thread. */
KKUNITYBUNDLE_API void OKCensusRuntimeTextures(const TCHAR* When);
