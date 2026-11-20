// Skirts and sleeves as PhysX 5.11 cloth (PxDeformableSurface, GPU FEM) for ok_extract's cloth_px.
// Rust finds the cloth region, builds the welded mesh and pins; this file only simulates it: one GPU scene per garment,
// the pinned vertices (inverse mass 0) put on their skinned targets every substep, the body capsules as kinematic
// colliders. Without CUDA or PhysXGpu.dll Create fails and Rust keeps the garment's DynamicBones.
#include "OKPhysXSecondary.h"
#include "OKPhysXSecondaryAbi.h"

#if !(defined(OK_PHYSX_SECONDARY_STUB) && OK_PHYSX_SECONDARY_STUB)
#include "HAL/IConsoleManager.h"
#include "Misc/ScopeLock.h"
#include "HAL/PlatformTime.h"
#include "HAL/PlatformProcess.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/Paths.h"
#include "Tasks/Task.h"
#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include <windows.h>
#include "Windows/HideWindowsPlatformTypes.h"
#endif
#include "ProfilingDebugging/CpuProfilerTrace.h"

#pragma push_macro("check")
#pragma push_macro("verify")
#undef check
#undef verify
THIRD_PARTY_INCLUDES_START
#include "PxPhysicsAPI.h"
#include "gpu/PxGpu.h"
#include "extensions/PxDeformableSurfaceExt.h"
#include "extensions/PxCudaHelpersExt.h"
THIRD_PARTY_INCLUDES_END
#pragma pop_macro("verify")
#pragma pop_macro("check")

DEFINE_LOG_CATEGORY_STATIC(LogOKPhysXCloth, Log, All);

using namespace physx;

namespace OKPhysXSecondary
{
	// OKPhysXSecondary.cpp: the module's foundation, physics and CPU dispatcher (loaded on demand).
	bool ClothRuntime(PxPhysics*& Physics, PxFoundation*& Foundation, PxCpuDispatcher*& Dispatcher);
}

static TAutoConsoleVariable<float> CVarYoungs(TEXT("OKPhysXCloth.Youngs"), 2.0e5f, TEXT("Cloth stretch stiffness (Young's modulus, Pa). Takes effect for new cloths."));
static TAutoConsoleVariable<float> CVarPoisson(TEXT("OKPhysXCloth.Poisson"), 0.3f, TEXT("Cloth Poisson ratio. New cloths."));
static TAutoConsoleVariable<float> CVarFriction(TEXT("OKPhysXCloth.Friction"), 0.3f, TEXT("Cloth friction on the body capsules. New cloths."));
static TAutoConsoleVariable<float> CVarThickness(TEXT("OKPhysXCloth.Thickness"), 0.0005f, TEXT("Cloth thickness (m). New cloths. 3 mm drew the skirt 5 cm up and in (2026-11-20)."));
static TAutoConsoleVariable<float> CVarBending(TEXT("OKPhysXCloth.Bending"), 0.02f, TEXT("Bending stiffness of sleeves-only cloths (without it a bell sleeve slumped onto its cuff). New cloths."));
static TAutoConsoleVariable<float> CVarBendingSkirt(TEXT("OKPhysXCloth.BendingSkirt"), 0.f, TEXT("Bending stiffness of cloths with a skirt. Any bending let a walk flip the pleats into a mirrored rest angle that held the skirt 5 cm up (2026-11-20). New cloths."));
static TAutoConsoleVariable<float> CVarElasticDamping(TEXT("OKPhysXCloth.ElasticDamping"), 0.005f, TEXT("Stretch damping. New cloths."));
static TAutoConsoleVariable<float> CVarBendDamping(TEXT("OKPhysXCloth.BendDamping"), 0.01f, TEXT("Bending damping. New cloths."));
static TAutoConsoleVariable<float> CVarLinearDamping(TEXT("OKPhysXCloth.Damping"), 0.6f, TEXT("Linear damping of the cloth vertices (air)."));
static TAutoConsoleVariable<float> CVarMass(TEXT("OKPhysXCloth.Mass"), 0.25f, TEXT("Mass (kg) of one garment's cloth. New cloths."));
static TAutoConsoleVariable<int32> CVarIterations(TEXT("OKPhysXCloth.Iterations"), 12, TEXT("Solver position iterations."));
static TAutoConsoleVariable<float> CVarSubstepHz(TEXT("OKPhysXCloth.SubstepHz"), 120.f, TEXT("Substeps per second (at most MaxSubsteps per frame)."));
static TAutoConsoleVariable<int32> CVarMaxSubsteps(TEXT("OKPhysXCloth.MaxSubsteps"), 2, TEXT("Most substeps in one frame."));
static TAutoConsoleVariable<int32> CVarRestFollow(TEXT("OKPhysXCloth.RestFollow"), 0, TEXT("1: upload the skinned pose as the rest positions every step. PhysX keeps the rest state of the pose a cloth was made in, so this changed nothing measurable (2026-11-20); Rust makes the cloth on a moving pose instead."));
static TAutoConsoleVariable<int32> CVarFeedPrev(TEXT("OKPhysXCloth.FeedPrev"), 1, TEXT("1: the free vertices start each step where Rust showed them (carried with the body); 0: the GPU keeps its own state, only the pins move."));
static TAutoConsoleVariable<int32> CVarCollide(TEXT("OKPhysXCloth.Collide"), 1, TEXT("1: the body capsules are kinematic colliders on the GPU too (Rust always pushes out of them after)."));
static TAutoConsoleVariable<int32> CVarCudaWait(TEXT("OKPhysXCloth.CudaWait"), 0, TEXT("CUDA context scheduling when it is created: 0 auto (spin while cores are free), 1 spin, 2 yield, 4 blocking."));
static TAutoConsoleVariable<int32> CVarInterpolatePins(TEXT("OKPhysXCloth.InterpolatePins"), 0, TEXT("1: the pinned vertices move along their path every substep (an upload and a readback per substep)."));
static TAutoConsoleVariable<int32> CVarAsync(TEXT("OKPhysXCloth.Async"), 1, TEXT("1: the GPU step runs while the frame renders and is shown one frame later (as offsets on the new pose). 0: wait for it."));
static TAutoConsoleVariable<int32> CVarLog(TEXT("OKPhysXCloth.Log"), 0, TEXT("1: log every cloth step's time."));

namespace
{
	class FGpuLoadHook : public PxGpuLoadHook
	{
	public:
		const char* getPhysXGpuDllName() const override { return "PhysXGpu.dll"; }
	} GGpuLoadHook;

	FCriticalSection GLock;
	PxCudaContextManager* GCuda = nullptr;
	bool GCudaTried = false;

	PxCudaContextManager* Cuda(PxFoundation& Foundation)
	{
		if (GCudaTried) return GCuda;
		GCudaTried = true;
		PxSetPhysXGpuLoadHook(&GGpuLoadHook);
		// PhysX loads "PhysXGpu.dll" by name: load it (and its cudart) from this plugin's folder first, beside the PhysX.dll
		// it was built with, or the search path finds nothing (2026-11-20: "Failed to load PhysXGpu.dll").
		if (const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("OKPhysXSecondary")))
		{
			const FString Dir = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Binaries/ThirdParty/Win64"));
			FPlatformProcess::PushDllDirectory(*Dir);
			FPlatformProcess::GetDllHandle(*FPaths::Combine(Dir, TEXT("cudart64_12.dll")));
			if (!FPlatformProcess::GetDllHandle(*FPaths::Combine(Dir, TEXT("PhysXGpu.dll"))))
				{ UE_LOG(LogOKPhysXCloth, Warning, TEXT("PhysX cloth: cannot load %s/PhysXGpu.dll"), *Dir); }
			FPlatformProcess::PopDllDirectory(*Dir);
		}
		PxCudaContextManagerDesc Desc;
		GCuda = PxCreateCudaContextManager(Foundation, Desc, PxGetProfilerCallback());
		if (GCuda && !GCuda->contextIsValid()) { GCuda->release(); GCuda = nullptr; }
#if PLATFORM_WINDOWS
		// Each substep waits on the GPU several times; the SDK's blocking sync sleeps the thread and pays an OS wakeup per
		// wait: 10 ms per substep for one skirt (2026-11-20). CU_CTX_SCHED_AUTO (spin while cores are free) as the Flex
		// plugin does (PHYSX58_CUDA_WAIT); OKPhysXCloth.CudaWait 1 spin, 2 yield, 4 blocking.
		if (GCuda)
		{
			const HMODULE Driver = GetModuleHandleW(L"nvcuda.dll");
			using FGetFlags = int (WINAPI*)(unsigned*);
			using FSetFlags = int (WINAPI*)(unsigned);
			const auto GetFlags = Driver ? reinterpret_cast<FGetFlags>(GetProcAddress(Driver, "cuCtxGetFlags")) : nullptr;
			const auto SetFlags = Driver ? reinterpret_cast<FSetFlags>(GetProcAddress(Driver, "cuCtxSetFlags")) : nullptr;
			PxScopedCudaLock ContextLock(*GCuda);
			unsigned Flags = 0;
			const unsigned Scheduling = unsigned(FMath::Clamp(CVarCudaWait.GetValueOnAnyThread(), 0, 4));
			if (GetFlags && SetFlags && !GetFlags(&Flags) && !SetFlags((Flags & ~7u) | Scheduling))
				{ UE_LOG(LogOKPhysXCloth, Display, TEXT("PhysX cloth: CUDA wait policy %u"), Scheduling); }
			else
				{ UE_LOG(LogOKPhysXCloth, Warning, TEXT("PhysX cloth: CUDA wait policy could not be set")); }
		}
#endif
		if (GCuda) { UE_LOG(LogOKPhysXCloth, Display, TEXT("PhysX cloth: CUDA ready (%hs)"), GCuda->getDeviceName()); }
		else { UE_LOG(LogOKPhysXCloth, Warning, TEXT("PhysX cloth: no CUDA context (PhysXGpu.dll / driver); skirts and sleeves keep their DynamicBones")); }
		return GCuda;
	}

	struct FCloth
	{
		PxScene* Scene = nullptr;
		PxDeformableSurface* Surface = nullptr;
		PxShape* Shape = nullptr;
		PxTriangleMesh* Mesh = nullptr;
		PxDeformableSurfaceMaterial* Material = nullptr;
		PxMaterial* RigidMaterial = nullptr;
		PxVec4* PosInvMass = nullptr;
		PxVec4* Vel = nullptr;
		PxVec4* Rest = nullptr;
		TArray<int32> InputOf;   // cooked vertex -> input vertex
		TArray<float> InvMass;   // cooked order
		TArray<PxVec3> LastPrev;   // cooked order: where the free vertices started the last step (Prev)
		bool bHavePrev = false;
		TArray<PxVec3> LastPinned; // cooked order: last frame's targets (pinned vertices move along them per substep)
		TArray<PxRigidDynamic*> Capsules;
		TArray<FVector4f> CapsuleShape; // radius, half height
		int32 N = 0;
		UE::Tasks::FTask Job;     // this frame's GPU work (OKPhysXCloth.Async)
		bool bJob = false;
		double JobSeconds = 0.;
		float PendingDt = 0.f;
		bool bRestDirty = false;
		bool bVelDirty = false;   // Vel set from the shown motion: the next job uploads it  // Rest changed: the next job uploads it    // frames that passed while the job ran

		~FCloth()
		{
			if (bJob) Job.Wait();
			if (GCuda)
			{
				if (PosInvMass) Ext::PxCudaHelpersExt::freePinnedHostBuffer(*GCuda, PosInvMass);
				if (Vel) Ext::PxCudaHelpersExt::freePinnedHostBuffer(*GCuda, Vel);
				if (Rest) Ext::PxCudaHelpersExt::freePinnedHostBuffer(*GCuda, Rest);
			}
			for (PxRigidDynamic* C : Capsules) if (C) C->release();
			if (Surface) Surface->release();
			if (Shape) Shape->release();
			if (Mesh) Mesh->release();
			if (Material) Material->release();
			if (RigidMaterial) RigidMaterial->release();
			if (Scene) Scene->release();
		}
	};
	TMap<uint64, TUniquePtr<FCloth>> GCloths;

	PxQuat FromX(const PxVec3& Dir)
	{
		const PxVec3 X(1.f, 0.f, 0.f);
		const float L = Dir.magnitude();
		if (L < 1e-6f) return PxQuat(PxIdentity);
		const PxVec3 D = Dir / L;
		const float C = X.dot(D);
		if (C > 0.99999f) return PxQuat(PxIdentity);
		if (C < -0.99999f) return PxQuat(PxPi, PxVec3(0.f, 1.f, 0.f));
		const PxVec3 Axis = X.cross(D).getNormalized();
		return PxQuat(PxAcos(C), Axis);
	}

	/** Puts the capsule actors where the body is now (created/resized as the list changes). */
	void UpdateCapsules(FCloth& Cloth, PxPhysics& Physics, const FOKPxCapsule* Caps, uint32 Count)
	{
		const bool bCollide = CVarCollide.GetValueOnAnyThread() != 0;
		if (!bCollide) Count = 0;
		while (Cloth.Capsules.Num() > int32(Count)) { Cloth.Capsules.Pop()->release(); Cloth.CapsuleShape.Pop(); }
		for (uint32 I = 0; I < Count; ++I)
		{
			const PxVec3 A(Caps[I].A[0], Caps[I].A[1], Caps[I].A[2]), B(Caps[I].B[0], Caps[I].B[1], Caps[I].B[2]);
			const float Radius = FMath::Max(Caps[I].Radius, 0.002f);
			const float Half = FMath::Max((B - A).magnitude() * 0.5f, 0.0005f);
			const PxTransform Pose((A + B) * 0.5f, FromX(B - A));
			if (int32(I) >= Cloth.Capsules.Num())
			{
				PxRigidDynamic* Actor = Physics.createRigidDynamic(Pose);
				Actor->setRigidBodyFlag(PxRigidBodyFlag::eKINEMATIC, true);
				PxShape* Shape = PxRigidActorExt::createExclusiveShape(*Actor, PxCapsuleGeometry(Radius, Half), *Cloth.RigidMaterial);
				Shape->setContactOffset(0.004f);
				Shape->setRestOffset(0.f);
				Cloth.Scene->addActor(*Actor);
				Cloth.Capsules.Add(Actor);
				Cloth.CapsuleShape.Add(FVector4f(Radius, Half, 0.f, 0.f));
				continue;
			}
			PxRigidDynamic* Actor = Cloth.Capsules[I];
			FVector4f& Known = Cloth.CapsuleShape[I];
			if (FMath::Abs(Known.X - Radius) > 0.001f || FMath::Abs(Known.Y - Half) > 0.001f)
			{
				PxShape* Shape = nullptr;
				Actor->getShapes(&Shape, 1);
				if (Shape) Shape->setGeometry(PxCapsuleGeometry(Radius, Half));
				Known = FVector4f(Radius, Half, 0.f, 0.f);
			}
			Actor->setKinematicTarget(Pose);
		}
	}

	int32 Create(uint64 Key, uint32 N, const float* Pos, const float* InvMass, uint32 TriN, const uint32* Tris, uint32 Flags)
	{
		TRACE_CPUPROFILER_EVENT_SCOPE(OKPxCloth_Create);
		PxPhysics* Physics = nullptr; PxFoundation* Foundation = nullptr; PxCpuDispatcher* Dispatcher = nullptr;
		if (!N || !TriN || !OKPhysXSecondary::ClothRuntime(Physics, Foundation, Dispatcher)) return 0;
		FScopeLock Guard(&GLock);
		PxCudaContextManager* CudaManager = Cuda(*Foundation);
		if (!CudaManager) return 0;
		GCloths.Remove(Key);
		TUniquePtr<FCloth> Cloth = MakeUnique<FCloth>();

		PxSceneDesc Desc(Physics->getTolerancesScale());
		Desc.gravity = PxVec3(0.f, -9.81f, 0.f);
		Desc.cpuDispatcher = Dispatcher;
		Desc.filterShader = PxDefaultSimulationFilterShader;
		Desc.cudaContextManager = CudaManager;
		Desc.flags |= PxSceneFlag::eENABLE_GPU_DYNAMICS | PxSceneFlag::eENABLE_PCM;
		Desc.broadPhaseType = PxBroadPhaseType::eGPU;
		Desc.solverType = PxSolverType::eTGS;
		// One garment and a few capsules: the default GPU heaps (hundreds of MB per scene) are far more than it needs.
		Desc.gpuDynamicsConfig.tempBufferCapacity = 8u << 20;
		Desc.gpuDynamicsConfig.maxRigidContactCount = 1u << 14;
		Desc.gpuDynamicsConfig.maxRigidPatchCount = 1u << 12;
		Desc.gpuDynamicsConfig.heapCapacity = 16u << 20;
		Desc.gpuDynamicsConfig.foundLostPairsCapacity = 1u << 12;
		Desc.gpuDynamicsConfig.foundLostAggregatePairsCapacity = 1u << 10;
		Desc.gpuDynamicsConfig.totalAggregatePairsCapacity = 1u << 10;
		Desc.gpuDynamicsConfig.maxDeformableSurfaceContacts = 1u << 16;
		Desc.gpuDynamicsConfig.maxDeformableVolumeContacts = 1u << 10;
		Desc.gpuDynamicsConfig.maxParticleContacts = 1u << 10;
		Cloth->Scene = Physics->createScene(Desc);
		if (!Cloth->Scene) { UE_LOG(LogOKPhysXCloth, Warning, TEXT("cloth %llu: no GPU scene"), Key); return 0; }
		Cloth->RigidMaterial = Physics->createMaterial(CVarFriction.GetValueOnAnyThread(), CVarFriction.GetValueOnAnyThread(), 0.f);

		// The welded mesh as given: no cleaning or welding, so the cooked vertices are Rust's particles.
		PxTriangleMeshDesc MeshDesc;
		MeshDesc.points.count = N;
		MeshDesc.points.stride = sizeof(float) * 3;
		MeshDesc.points.data = Pos;
		MeshDesc.triangles.count = TriN;
		MeshDesc.triangles.stride = sizeof(uint32) * 3;
		MeshDesc.triangles.data = Tris;
		PxCookingParams Params(Physics->getTolerancesScale());
		Params.meshPreprocessParams = PxMeshPreprocessingFlags(PxMeshPreprocessingFlag::eDISABLE_CLEAN_MESH);
		Params.buildTriangleAdjacencies = false;
		Params.buildGPUData = true;
		Cloth->Mesh = PxCreateTriangleMesh(Params, MeshDesc, Physics->getPhysicsInsertionCallback());
		if (!Cloth->Mesh || Cloth->Mesh->getNbVertices() != N) { UE_LOG(LogOKPhysXCloth, Warning, TEXT("cloth %llu: cooking failed (%u vertices)"), Key, N); return 0; }
		// Cooking may still reorder the vertices: map them back by position (the particles are welded, so unique).
		{
			TMap<FIntVector, int32> ByPos;
			auto Quant = [](const float* P) { return FIntVector(FMath::RoundToInt(P[0] * 1e5f), FMath::RoundToInt(P[1] * 1e5f), FMath::RoundToInt(P[2] * 1e5f)); };
			for (uint32 I = 0; I < N; ++I) ByPos.Add(Quant(Pos + I * 3), int32(I));
			const PxVec3* Cooked = Cloth->Mesh->getVertices();
			Cloth->InputOf.SetNumUninitialized(N);
			TBitArray<> Seen(false, N);
			for (uint32 I = 0; I < N; ++I)
			{
				const float P[3] = {Cooked[I].x, Cooked[I].y, Cooked[I].z};
				const int32* In = ByPos.Find(Quant(P));
				if (!In || Seen[*In]) { UE_LOG(LogOKPhysXCloth, Warning, TEXT("cloth %llu: cooked vertices do not map back"), Key); return 0; }
				Seen[*In] = true;
				Cloth->InputOf[I] = *In;
			}
		}
		Cloth->Surface = Physics->createDeformableSurface(*CudaManager);
		if (!Cloth->Surface) { UE_LOG(LogOKPhysXCloth, Warning, TEXT("cloth %llu: no deformable surface"), Key); return 0; }
		Cloth->Material = Physics->createDeformableSurfaceMaterial(CVarYoungs.GetValueOnAnyThread(), CVarPoisson.GetValueOnAnyThread(),
			CVarFriction.GetValueOnAnyThread(), CVarThickness.GetValueOnAnyThread(), ((Flags & 1u) ? CVarBendingSkirt : CVarBending).GetValueOnAnyThread(),
			CVarElasticDamping.GetValueOnAnyThread(), CVarBendDamping.GetValueOnAnyThread());
		PxDeformableSurfaceMaterial* Materials[1] = {Cloth->Material};
		Cloth->Shape = Physics->createShape(PxTriangleMeshGeometry(Cloth->Mesh), Materials, 1, true,
			PxShapeFlag::eSIMULATION_SHAPE);
		if (!Cloth->Shape) return 0;
		Cloth->Shape->setContactOffset(0.004f);
		Cloth->Shape->setRestOffset(0.001f);
		Cloth->Surface->attachShape(*Cloth->Shape);
		Cloth->Surface->setDeformableBodyFlag(PxDeformableBodyFlag::eDISABLE_SELF_COLLISION, true);
		Cloth->Surface->setSolverIterationCounts(FMath::Clamp(CVarIterations.GetValueOnAnyThread(), 1, 64));
		Cloth->Surface->setLinearDamping(FMath::Max(0.f, CVarLinearDamping.GetValueOnAnyThread()));
		Cloth->Surface->setMaxLinearVelocity(8.f);
		Cloth->Scene->addActor(*Cloth->Surface);

		TArray<PxVec3> Cooked;
		Cooked.SetNumUninitialized(N);
		const PxVec3* CookedPos = Cloth->Mesh->getVertices();
		for (uint32 I = 0; I < N; ++I) Cooked[I] = CookedPos[I];
		PxDeformableSurfaceExt::allocateAndInitializeHostMirror(*Cloth->Surface, Cooked.GetData(), nullptr, Cooked.GetData(),
			FMath::Max(0.01f, CVarMass.GetValueOnAnyThread()), PxTransform(PxIdentity), CudaManager, Cloth->PosInvMass, Cloth->Vel, Cloth->Rest);
		if (!Cloth->PosInvMass) return 0;
		Cloth->InvMass.SetNumUninitialized(N);
		Cloth->LastPinned.SetNumUninitialized(N);
		Cloth->LastPrev.SetNumZeroed(N);
		for (uint32 I = 0; I < N; ++I)
		{
			const float In = InvMass[Cloth->InputOf[I]];
			if (In <= 0.f) Cloth->PosInvMass[I].w = 0.f;
			Cloth->InvMass[I] = Cloth->PosInvMass[I].w;
			Cloth->LastPinned[I] = Cooked[I];
		}
		PxDeformableSurfaceExt::copyToDevice(*Cloth->Surface, PxDeformableSurfaceDataFlag::eALL, N, Cloth->PosInvMass, Cloth->Vel, Cloth->Rest);
		if (CVarLog.GetValueOnAnyThread())
		{
			// One step from rest: a consistent mesh barely moves (gravity alone, under a millimetre).
			Cloth->Scene->simulate(1.f / 120.f);
			Cloth->Scene->fetchResults(true);
			TArray<PxVec4> After; After.SetNumUninitialized(N);
			Ext::PxCudaHelpersExt::copyDToH(*CudaManager, After.GetData(), Cloth->Surface->getPositionInvMassBufferD(), N);
			double Sum = 0.0, SumY = 0.0; float Most = 0.f; int32 Free = 0;
			for (uint32 I = 0; I < N; ++I)
			{
				if (Cloth->InvMass[I] <= 0.f) continue;
				const PxVec3 D = After[I].getXYZ() - Cooked[I];
				Most = FMath::Max(Most, D.magnitude()); Sum += D.magnitude(); SumY += D.y; ++Free;
			}
			UE_LOG(LogOKPhysXCloth, Display, TEXT("cloth %llu: first step from rest moved free vertices mean %.3f mm (y %.3f), most %.3f mm, %d free"),
				Key, Free ? Sum / Free * 1000.0 : 0.0, Free ? SumY / Free * 1000.0 : 0.0, Most * 1000.f, Free);
			for (uint32 I = 0; I < N; ++I) Cloth->Vel[I] = PxVec4(0.f);
			PxDeformableSurfaceExt::copyToDevice(*Cloth->Surface, PxDeformableSurfaceDataFlag::eALL, N, Cloth->PosInvMass, Cloth->Vel, Cloth->Rest);
		}
		Cloth->N = int32(N);
		GCloths.Add(Key, MoveTemp(Cloth));
		return 1;
	}

	/** The substeps of one frame on the GPU (a worker task, or inline): one upload, the substeps, one readback. */
	void Simulate(FCloth& Cloth, int32 Steps, float H)
	{
		TRACE_CPUPROFILER_EVENT_SCOPE(OKPxCloth_Simulate);
		const double Start = FPlatformTime::Seconds();
		PxVec4* Device = Cloth.Surface->getPositionInvMassBufferD();
		PxDeformableSurfaceDataFlags Up(PxDeformableSurfaceDataFlag::ePOSITION_INVMASS);
		if (Cloth.bRestDirty) { Up |= PxDeformableSurfaceDataFlag::eREST_POSITION; Cloth.bRestDirty = false; }
		if (Cloth.bVelDirty) { Up |= PxDeformableSurfaceDataFlag::eVELOCITY; Cloth.bVelDirty = false; }
		PxDeformableSurfaceExt::copyToDevice(*Cloth.Surface, Up, uint32(Cloth.N), Cloth.PosInvMass, Cloth.Vel, Cloth.Rest);
		for (int32 S = 0; S < Steps; ++S)
		{
			Cloth.Scene->simulate(H);
			Cloth.Scene->fetchResults(true);
		}
		Ext::PxCudaHelpersExt::copyDToH(*GCuda, Cloth.PosInvMass, Device, uint32(Cloth.N));
		Cloth.JobSeconds = FPlatformTime::Seconds() - Start;
	}

	/**
	 * One frame of a cloth. OKPhysXCloth.Async 1 (default): the GPU work runs on a worker task while the frame renders and
	 * is collected at the next call; `Out` then holds the result for the previous call's targets (returns 2; Rust carries
	 * it over as offsets onto this frame's pose). The GPU waits of a synchronous step were 10 ms a substep with the
	 * renderer busy on the same GPU (2026-11-20). Returns 1 when `Out` is for these targets, 3 when the job still runs
	 * (keep the last result), 0 when there is nothing yet.
	 */
	int32 Step(uint64 Key, uint32 N, const float* Targets, const float* Prev, const void* CapsulesRaw, uint32 CapN, float Dt, float* Out)
	{
		TRACE_CPUPROFILER_EVENT_SCOPE(OKPxCloth_Step);
		PxPhysics* Physics = nullptr; PxFoundation* Foundation = nullptr; PxCpuDispatcher* Dispatcher = nullptr;
		if (!OKPhysXSecondary::ClothRuntime(Physics, Foundation, Dispatcher)) return 0;
		FCloth* ClothPtr = nullptr;
		{
			FScopeLock Guard(&GLock);
			TUniquePtr<FCloth>* Found = GCloths.Find(Key);
			if (!Found || !GCuda || (*Found)->N != int32(N)) return 0;
			ClothPtr = Found->Get();
		}
		FCloth& Cloth = *ClothPtr;
		// One caller per cloth at a time (Rust locks its entry); Release takes GLock and waits for the job.
		bool bHave = false;
		const bool bAsync = CVarAsync.GetValueOnAnyThread() != 0;
		// Still on the GPU (each substep waits 7-11 ms for the GPU the renderer also uses; the Flex plugin measured the
		// same): this frame keeps the last result, its time added to the next job. Never blocks the frame.
		if (Cloth.bJob && bAsync && Dt >= 0.f && !Cloth.Job.IsCompleted()) { Cloth.PendingDt += Dt; return 3; }
		if (Cloth.bJob) { TRACE_CPUPROFILER_EVENT_SCOPE(OKPxCloth_Wait); Cloth.Job.Wait(); Cloth.bJob = false; bHave = true; }
		if (Dt >= 0.f) { Dt += Cloth.PendingDt; }
		Cloth.PendingDt = 0.f;
		auto Target = [&](int32 Cooked) { const float* P = Targets + Cloth.InputOf[Cooked] * 3; return PxVec3(P[0], P[1], P[2]); };
		if (Dt < 0.f)
		{
			// Start again on the targets, at rest.
			Cloth.bHavePrev = false;
			for (int32 I = 0; I < Cloth.N; ++I)
			{
				const PxVec3 P = Target(I);
				Cloth.PosInvMass[I] = PxVec4(P, Cloth.InvMass[I]);
				Cloth.Vel[I] = PxVec4(0.f);
				Cloth.LastPinned[I] = P;
			}
			PxDeformableSurfaceExt::copyToDevice(*Cloth.Surface, PxDeformableSurfaceDataFlags(PxDeformableSurfaceDataFlag::ePOSITION_INVMASS) | PxDeformableSurfaceDataFlag::eVELOCITY, N, Cloth.PosInvMass, Cloth.Vel, Cloth.Rest);
			FMemory::Memcpy(Out, Targets, sizeof(float) * 3 * N);
			return 1;
		}
		auto Write = [&](auto&& TargetOf)
		{
			for (int32 I = 0; I < Cloth.N; ++I)
			{
				const PxVec4& P = Cloth.PosInvMass[I];
				float* O = Out + Cloth.InputOf[I] * 3;
				if (Cloth.InvMass[I] <= 0.f || !P.isFinite()) { const PxVec3 T = TargetOf(I); O[0] = T.x; O[1] = T.y; O[2] = T.z; }
				else { O[0] = P.x; O[1] = P.y; O[2] = P.z; }
			}
		};
		// The previous job's result, for the targets it was given (LastPinned holds them).
		if (bHave && bAsync) Write([&](int32 I) { return Cloth.LastPinned[I]; });
		Dt = FMath::Min(Dt, 0.1f);
		// What Rust showed last frame (its max distance and capsule push applied) is where the free vertices start.
		// Their velocities with them: the motion shown between the last two starts. The GPU's own velocity belongs to
		// positions this replaced, and kept it lifted the skirt 4 cm a step while walking (2026-11-20).
		if (Prev && CVarFeedPrev.GetValueOnAnyThread() != 0)
		{
			const float InvDt = Dt > 1e-4f ? 1.f / Dt : 0.f;
			for (int32 I = 0; I < Cloth.N; ++I)
			{
				if (Cloth.InvMass[I] <= 0.f) continue;
				const float* P = Prev + Cloth.InputOf[I] * 3;
				const PxVec3 Now(P[0], P[1], P[2]);
				Cloth.PosInvMass[I] = PxVec4(Now, Cloth.InvMass[I]);
				PxVec3 V = Cloth.bHavePrev ? (Now - Cloth.LastPrev[I]) * InvDt : PxVec3(0.f);
				const float Speed = V.magnitude();
				if (Speed > 4.f) V *= 4.f / Speed;
				Cloth.Vel[I] = PxVec4(V, 0.f);
				Cloth.LastPrev[I] = Now;
			}
			Cloth.bHavePrev = true;
			Cloth.bVelDirty = true;
		}
		for (int32 I = 0; I < Cloth.N; ++I)
			if (Cloth.InvMass[I] <= 0.f) Cloth.PosInvMass[I] = PxVec4(Target(I), 0.f);
		for (int32 I = 0; I < Cloth.N; ++I) Cloth.LastPinned[I] = Target(I);
		if (CVarRestFollow.GetValueOnAnyThread() != 0)
		{
			for (int32 I = 0; I < Cloth.N; ++I) Cloth.Rest[I] = PxVec4(Target(I), 0.f);
			Cloth.bRestDirty = true;
		}
		UpdateCapsules(Cloth, *Physics, static_cast<const FOKPxCapsule*>(CapsulesRaw), CapsulesRaw ? CapN : 0);
		Cloth.Surface->setLinearDamping(FMath::Max(0.f, CVarLinearDamping.GetValueOnAnyThread()));
		const int32 Steps = FMath::Clamp(FMath::CeilToInt(Dt * FMath::Max(10.f, CVarSubstepHz.GetValueOnAnyThread())), 1, FMath::Max(1, CVarMaxSubsteps.GetValueOnAnyThread()));
		const float H = Dt / float(Steps);
		if (CVarLog.GetValueOnAnyThread())
			UE_LOG(LogOKPhysXCloth, Display, TEXT("cloth %llu: %u vertices, %d substeps, %d capsules, last GPU job %.3f ms"), Key, N, Steps, Cloth.Capsules.Num(), Cloth.JobSeconds * 1000.0);
		if (bAsync)
		{
			Cloth.Job = UE::Tasks::Launch(UE_SOURCE_LOCATION, [ClothPtr, Steps, H] { Simulate(*ClothPtr, Steps, H); });
			Cloth.bJob = true;
			return bHave ? 2 : 0;
		}
		Simulate(Cloth, Steps, H);
		Write([&](int32 I) { return Target(I); });
		return 1;
	}

	void Release(uint64 Key)
	{
		FScopeLock Guard(&GLock);
		GCloths.Remove(Key);
	}

	int32 CreateAbi(uint64 Key, uint32 N, const float* Pos, const float* InvMass, uint32 TriN, const uint32* Tris, uint32 Flags) { return Create(Key, N, Pos, InvMass, TriN, Tris, Flags); }
	int32 StepAbi(uint64 Key, uint32 N, const float* Targets, const float* Prev, const void* Caps, uint32 CapN, float Dt, float* Out) { return Step(Key, N, Targets, Prev, Caps, CapN, Dt, Out); }
	void ReleaseAbi(uint64 Key) { Release(Key); }
}

namespace OKPhysXSecondary
{
	void RegisterCloth(FSetClothFn SetCloth)
	{
		FModuleManager::Get().LoadModuleChecked<IModuleInterface>(TEXT("OKPhysXSecondary"));
		if (SetCloth) SetCloth(&CreateAbi, &StepAbi, &ReleaseAbi);
	}
	void ShutdownCloth()
	{
		FScopeLock Guard(&GLock);
		GCloths.Empty();
		if (GCuda) { GCuda->release(); GCuda = nullptr; }
	}
}
#endif
