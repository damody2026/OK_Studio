#pragma once
#include "CoreMinimal.h"
#include "Modules/ModuleManager.h"

/**
 * PhysX 5.11 back end for the Rust DynamicBone solver (ok_extract.lib).
 * Every module that statically links ok_extract.lib calls OKPhysXSecondary::Register() once;
 * the Rust side then delegates particle integration to Solve().
 */
namespace OKPhysXSecondary
{
	/** Clipping audit of hair/cloth particles against the body capsules they must stay out of. */
	struct FStats
	{
		float MaxPenetration = 0.f; // metres, worst hair/cloth particle-or-bone depth inside a body since ResetStats
		float MinBodyGap = 0.f;     // metres, closest approach between two characters' body capsules (negative = overlapping bodies)
		int64 Violations = 0;       // chain steps with a particle more than 1 cm inside
		int64 Steps = 0;
		float MaxProjection = 0.f; // metres, largest single correction of the exact pass (popping indicator)
		int64 Resets = 0;          // particles put back on their goal after blowing up
		float BodyPenetration = 0.f; // breasts/hips (soft tissue squeezed by limbs), reported apart from hair/cloth
		int64 BodyViolations = 0;
		FString ViolationsByBody;
		double SolveSeconds = 0.;
		double PhaseSeconds[4] = {0., 0., 0., 0.}; // prepare, simulate, substep collisions, finish
		float MeanSwing = 0.f;     // metres, mean distance of the simulated particles from their animated pose (how much they swing)
		FString HardSplit;         // "length/point/midpoint" corrections of the exact pass (first pass)
		int64 HardFixes = 0;       // particle corrections the final exact pass still made (soft constraints did not hold)
		float MeanDrop = 0.f;      // metres, mean height of the animated pose above the simulated particles (sag)
		float MaxSwing = 0.f;       // metres, largest particle offset from its animated pose
		uint64 MaxSwingWhere = 0;  // (chain key << 16) | particle index of that offset
		float MaxStretch = 0.f;     // largest bone length / rest length (a stretched skirt panel)
		float TrueDepth = 0.f;      // metres, deepest particle/bone inside a full (unshrunk) body proxy it does not hang from
		int64 TrueViolations = 0;  // particle steps more than 3 cm inside such a proxy (visible clipping)
		int64 Pops = 0;            // chain steps whose particles accelerated >3 cm/frame^2 beyond the animation (jitter)
		FString BySolver;          // "solver:steps/pops/jitter" per solver, "b" = body chains (breasts, hips)
		int64 Jitter = 0;          // chain steps whose unexplained acceleration flipped direction (>1 cm both frames): shaking
		float MaxJerk = 0.f;       // metres per frame^2, worst such unexplained acceleration  // CPU seconds spent in the PhysX solver (all threads)  // "index:count" per body capsule, "p" = partner's body
	};
	/**
	 * Where a character's skeleton space (the native session's metres) sits in the world, also in metres, as a row-vector
	 * matrix (UE convention). Set every frame by the owner of the session: actor movement then swings hair/cloth, and the
	 * characters' bodies collide with each other's chains even when their actors are placed differently.
	 */
	OKPHYSXSECONDARY_API void SetGroupFrame(uint64 Group, const FMatrix44f& SkeletonToWorld);
	/** OKPhysXSecondary.DebugHeadTilt: extra backward head tilt (degrees) for the clipping audit. */
	OKPHYSXSECONDARY_API float HeadTilt();
	OKPHYSXSECONDARY_API int32 AuditEnabled();
	OKPHYSXSECONDARY_API void ResetStats();
	OKPHYSXSECONDARY_API FStats GetStats();
	/** Loads the module and installs the solver into the calling module's ok_extract copy. */
	OKPHYSXSECONDARY_API void Register(void (*SetSolver)(int32 (*)(const void*), void (*)(uint64), void (*)(uint64, const void*, uint32), int32 (*)(uint64, void*, uint32, float), float (*)(), int32 (*)(uint64, void*, uint32), int32 (*)()));
	/** Gives the calling module's ok_extract copy the weight/hardness settings, so its built-in Verlet follows them too. */
	OKPHYSXSECONDARY_API void RegisterTuning(void (*SetSource)(void (*)(float*, float*)));
	/** Softness scales of OKPhysXSecondary.Hardness for one chain (identity for breast/hip soft tissue), shared by every solver. */
	struct FSoftness { float Pull = 1.f, Range = 1.f, Damp = 1.f, Zeta = 1.f; };
	OKPHYSXSECONDARY_API FSoftness Softness(uint32 RootFlags);
	/** OKPhysXSecondary.Enabled false makes Solve decline, which restores the built-in solver. */
	OKPHYSXSECONDARY_API bool IsEnabled();
	/** After a pose switch: solve with OKPhysXSecondary.SettleBackend (Chaos) for Seconds (<0: SettleSeconds), then the chosen solver. */
	OKPHYSXSECONDARY_API void Settle(float Seconds = -1.f);
	OKPHYSXSECONDARY_API int32 Solve(const void* Step);
	/** Every chain of one DynamicBone set (FOKPxChainStep[Count]) in one PhysX scene keyed by Batch; all or nothing. */
	OKPHYSXSECONDARY_API int32 SolveBatch(uint64 Batch, void* Steps, uint32 Count);
	OKPHYSXSECONDARY_API void Release(uint64 Key);
	/** Replaces the body capsules (FOKPxCapsule[Count]) that every chain of Group collides with. */
	/** Full-body ragdoll (FOKPxBone[Count], in/out). Count 0 only reports whether it is enabled. */
	OKPHYSXSECONDARY_API int32 Ragdoll(uint64 Group, void* Bones, uint32 Count, float Dt);
	OKPHYSXSECONDARY_API void PublishBody(uint64 Group, const void* Capsules, uint32 Count);
	/**
	 * Skirts and sleeves as PhysX cloth (PxDeformableSurface on the GPU) for ok_extract's cloth_px: installs the host into
	 * the calling module's ok_extract copy (pass &ok_set_physx_cloth). See OKPhysXCloth.cpp.
	 */
	/** Flags bit 0: the garment has a skirt (made without bending). */
	using FClothCreateFn = int32 (*)(uint64 Key, uint32 N, const float* Pos, const float* InvMass, uint32 TriN, const uint32* Tris, uint32 Flags);
	using FClothStepFn = int32 (*)(uint64 Key, uint32 N, const float* Targets, const float* Prev, const void* Capsules, uint32 CapN, float Dt, float* Out);
	using FClothReleaseFn = void (*)(uint64 Key);
	using FSetClothFn = void (*)(FClothCreateFn, FClothStepFn, FClothReleaseFn);
	OKPHYSXSECONDARY_API void RegisterCloth(FSetClothFn SetCloth);
	void ShutdownCloth();
	/**
	 * The same cloth on NVIDIA FleX (OKFlexCloth.cpp): one particle solver per character holding all her cloth, so the
	 * layers collide with each other and with her posed body mesh. Bind tells which character a cloth belongs to (before
	 * its Create); Body gives her body this frame (vertices xyz, triangles). Pass &ok_set_flex_cloth.
	 */
	using FClothBindFn = void (*)(uint64 Key, uint64 Session);
	using FClothBodyFn = void (*)(uint64 Session, uint32 NV, const float* Pos, uint32 NT, const uint32* Tris);
	using FSetFlexClothFn = void (*)(FClothCreateFn, FClothStepFn, FClothReleaseFn, FClothBindFn, FClothBodyFn);
	OKPHYSXSECONDARY_API void RegisterFlexCloth(FSetFlexClothFn SetCloth);
	void ShutdownFlexCloth();
}
