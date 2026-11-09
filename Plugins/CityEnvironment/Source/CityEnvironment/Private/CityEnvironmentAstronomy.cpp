// Compiles the pinned Astronomy Engine C source into this Runtime module.
// License: Source/ThirdParty/Astronomy/LICENSE (MIT, Don Cross / cosinekitty).
// Revision: Source/ThirdParty/Astronomy/REVISION.txt. This file does not modify that source.
//
// MSVC game code is often built with /fp:fast. Astronomy Engine forbids fast math.
// The pragma below requests precise floating point for this translation unit only.

#include "CoreMinimal.h"

#if defined(_MSC_VER)
#pragma warning(push)
#pragma warning(disable: 4100 4101 4189 4244 4267 4305 4456 4457 4459 4701 4702 4706 4996)
#pragma float_control(precise, on, push)
#endif
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wmissing-field-initializers"
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang fp contract(off) reassociate(off) reciprocal(off)
#endif

#ifdef PI
#undef PI
#endif
#ifdef check
#undef check
#endif
#ifdef verify
#undef verify
#endif
#ifdef ensure
#undef ensure
#endif
#ifdef TEXT
#undef TEXT
#endif
#ifdef MAX
#undef MAX
#endif
#ifdef MIN
#undef MIN
#endif
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

// Do not pull windows.h via Astronomy_CurrentTime. The civil clock passes explicit dates.
#define ASTRONOMY_ENGINE_NO_CURRENT_TIME 1

#include "astronomy.c"

#undef ASTRONOMY_ENGINE_NO_CURRENT_TIME
#ifdef PI
#undef PI
#endif

#if defined(__clang__)
#pragma clang diagnostic pop
#endif
#if defined(_MSC_VER)
#pragma float_control(pop)
#pragma warning(pop)
#endif
