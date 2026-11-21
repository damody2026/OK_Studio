// Skirts, sleeves and drapes as NVIDIA FleX 1.2 cloth for ok_extract's cloth_px (the "FleX" choice beside PhysX).
// FleX simulates particles: each character gets one solver holding every garment of hers that is cloth, so the layers
// collide with each other (a lining and its outer cloth, a robe over a skirt) and with her posed body mesh (a triangle
// mesh shape updated every frame), not only with capsules. The DLLs are loaded at run time from this plugin's
// Binaries/ThirdParty/Win64 (copied there from the engine's GameWorks Flex plugin): the CUDA build first, the D3D11
// compute build when CUDA does not start. Same ABI as OKPhysXCloth.cpp (Create/Step/Release), plus Bind (cloth ->
// character) and Body (her body this frame).
#include "OKPhysXSecondary.h"

#if !(defined(OK_PHYSX_SECONDARY_STUB) && OK_PHYSX_SECONDARY_STUB) && defined(OK_FLEX_CLOTH) && OK_FLEX_CLOTH
#include "HAL/IConsoleManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/Paths.h"
#include "Misc/ScopeLock.h"
#include "Tasks/Task.h"
#include "ProfilingDebugging/CpuProfilerTrace.h"

THIRD_PARTY_INCLUDES_START
#include "NvFlex.h"
THIRD_PARTY_INCLUDES_END

DEFINE_LOG_CATEGORY_STATIC(LogOKFlexCloth, Log, All);

static TAutoConsoleVariable<int32> CVarFlexIterations(TEXT("OKFlexCloth.Iterations"), 20, TEXT("FleX solver iterations per substep. 8 left Raiden's kimono panels wrinkled and piling at the hem, 24 hung them smooth (2026-11-21; 17 ms a solve for her 42k particles, 9 ms at 8)."));
static TAutoConsoleVariable<float> CVarFlexSubstepHz(TEXT("OKFlexCloth.SubstepHz"), 240.f, TEXT("FleX substeps per second (at most MaxSubsteps per solve)."));
static TAutoConsoleVariable<int32> CVarFlexMaxSubsteps(TEXT("OKFlexCloth.MaxSubsteps"), 8, TEXT("Most FleX substeps in one solve."));
static TAutoConsoleVariable<float> CVarFlexMaxDt(TEXT("OKFlexCloth.MaxDt"), 0.04f, TEXT("Most time (s) one solve simulates; the time past it is dropped."));
static TAutoConsoleVariable<float> CVarFlexRadius(TEXT("OKFlexCloth.Radius"), 0.006f, TEXT("FleX particle interaction radius (m). New solvers."));
static TAutoConsoleVariable<float> CVarFlexRest(TEXT("OKFlexCloth.SolidRest"), 0.004f, TEXT("Distance cloth particles keep from each other (other layers, self-collision), m."));
static TAutoConsoleVariable<float> CVarFlexBodyDistance(TEXT("OKFlexCloth.BodyDistance"), 0.004f, TEXT("Distance cloth particles keep from her body mesh (m)."));
static TAutoConsoleVariable<float> CVarFlexStretch(TEXT("OKFlexCloth.Stretch"), 1.0f, TEXT("Stretch spring stiffness (0..1). New cloths."));
static TAutoConsoleVariable<float> CVarFlexBend(TEXT("OKFlexCloth.Bend"), 0.3f, TEXT("Bending spring stiffness (0..1). New cloths."));
static TAutoConsoleVariable<float> CVarFlexFriction(TEXT("OKFlexCloth.Friction"), 0.4f, TEXT("Friction on her body."));
static TAutoConsoleVariable<float> CVarFlexParticleFriction(TEXT("OKFlexCloth.ParticleFriction"), 0.2f, TEXT("Friction between cloth particles (layers)."));
static TAutoConsoleVariable<float> CVarFlexDamping(TEXT("OKFlexCloth.Damping"), 0.5f, TEXT("Viscous damping (1/s)."));
static TAutoConsoleVariable<float> CVarFlexDrag(TEXT("OKFlexCloth.Drag"), 0.05f, TEXT("Air drag on the cloth triangles."));
static TAutoConsoleVariable<float> CVarFlexLift(TEXT("OKFlexCloth.Lift"), 0.02f, TEXT("Air lift on the cloth triangles."));
static TAutoConsoleVariable<int32> CVarFlexSelf(TEXT("OKFlexCloth.SelfCollide"), 1, TEXT("1: a cloth collides with itself (its folds), not only with other layers."));
static TAutoConsoleVariable<int32> CVarFlexBody(TEXT("OKFlexCloth.BodyMesh"), 1, TEXT("1: her posed body mesh is a collision shape (0: capsules only)."));
static TAutoConsoleVariable<int32> CVarFlexCapsules(TEXT("OKFlexCloth.Capsules"), 1, TEXT("1: her body capsules are collision shapes too."));
static TAutoConsoleVariable<int32> CVarFlexAsync(TEXT("OKFlexCloth.Async"), 1, TEXT("1: the solve runs while the frame renders, collected next frame. 0: wait for it."));
static TAutoConsoleVariable<int32> CVarFlexLog(TEXT("OKFlexCloth.Log"), 0, TEXT("1: log each solve."));
static TAutoConsoleVariable<int32> CVarFlexBackend(TEXT("OKFlexCloth.Backend"), 0, TEXT("0: CUDA, then D3D11 if CUDA fails; 1: CUDA only; 2: D3D11 only. Read once."));

namespace
{
	struct FCapsule { float A[3]; float B[3]; float Radius; };

	// ---- the FleX API, loaded from the DLL
	struct FFlexApi
	{
		void* Dll = nullptr;
		decltype(&NvFlexInit) Init = nullptr;
		decltype(&NvFlexShutdown) Shutdown = nullptr;
		decltype(&NvFlexSetSolverDescDefaults) SolverDescDefaults = nullptr;
		decltype(&NvFlexCreateSolver) CreateSolver = nullptr;
		decltype(&NvFlexDestroySolver) DestroySolver = nullptr;
		decltype(&NvFlexUpdateSolver) UpdateSolver = nullptr;
		decltype(&NvFlexSetParams) SetParams = nullptr;
		decltype(&NvFlexSetActive) SetActive = nullptr;
		decltype(&NvFlexSetActiveCount) SetActiveCount = nullptr;
		decltype(&NvFlexSetParticles) SetParticles = nullptr;
		decltype(&NvFlexGetParticles) GetParticles = nullptr;
		decltype(&NvFlexSetRestParticles) SetRestParticles = nullptr;
		decltype(&NvFlexSetVelocities) SetVelocities = nullptr;
		decltype(&NvFlexGetVelocities) GetVelocities = nullptr;
		decltype(&NvFlexSetPhases) SetPhases = nullptr;
		decltype(&NvFlexSetSprings) SetSprings = nullptr;
		decltype(&NvFlexSetDynamicTriangles) SetDynamicTriangles = nullptr;
		decltype(&NvFlexSetShapes) SetShapes = nullptr;
		decltype(&NvFlexCreateTriangleMesh) CreateTriangleMesh = nullptr;
		decltype(&NvFlexDestroyTriangleMesh) DestroyTriangleMesh = nullptr;
		decltype(&NvFlexUpdateTriangleMesh) UpdateTriangleMesh = nullptr;
		decltype(&NvFlexAllocBuffer) AllocBuffer = nullptr;
		decltype(&NvFlexFreeBuffer) FreeBuffer = nullptr;
		decltype(&NvFlexMap) Map = nullptr;
		decltype(&NvFlexUnmap) Unmap = nullptr;
		decltype(&NvFlexAcquireContext) AcquireContext = nullptr;
		decltype(&NvFlexRestoreContext) RestoreContext = nullptr;
		decltype(&NvFlexGetDeviceName) GetDeviceName = nullptr;
	};
	FFlexApi GApi;
	NvFlexLibrary* GLib = nullptr;
	bool GTried = false;
	FCriticalSection GLock;      // the shared state (cloths, solvers); never held while FleX works on the GPU
	FCriticalSection GFlexLock;  // every FleX call (taken after GLock when both are needed, never the other way)
	FString GBackendName;

	void ErrorCallback(NvFlexErrorSeverity Type, const char* Msg, const char* File, int Line)
	{
		UE_LOG(LogOKFlexCloth, Warning, TEXT("FleX %s: %hs (%hs:%d)"), Type == eNvFlexLogError ? TEXT("error") : TEXT("message"), Msg, File, Line);
	}

	bool LoadApi(const FString& Dir, const TCHAR* Name, NvFlexComputeType Compute)
	{
		FPlatformProcess::PushDllDirectory(*Dir);
		void* Dll = FPlatformProcess::GetDllHandle(*FPaths::Combine(Dir, Name));
		FPlatformProcess::PopDllDirectory(*Dir);
		if (!Dll) { UE_LOG(LogOKFlexCloth, Warning, TEXT("FleX: cannot load %s/%s"), *Dir, Name); return false; }
		FFlexApi A;
		A.Dll = Dll;
		bool bAll = true;
#define OK_FLEX_GET(Field, Sym) A.Field = (decltype(A.Field))FPlatformProcess::GetDllExport(Dll, TEXT(#Sym)); bAll &= A.Field != nullptr;
		OK_FLEX_GET(Init, NvFlexInit) OK_FLEX_GET(Shutdown, NvFlexShutdown) OK_FLEX_GET(SolverDescDefaults, NvFlexSetSolverDescDefaults)
		OK_FLEX_GET(CreateSolver, NvFlexCreateSolver) OK_FLEX_GET(DestroySolver, NvFlexDestroySolver) OK_FLEX_GET(UpdateSolver, NvFlexUpdateSolver)
		OK_FLEX_GET(SetParams, NvFlexSetParams) OK_FLEX_GET(SetActive, NvFlexSetActive) OK_FLEX_GET(SetActiveCount, NvFlexSetActiveCount)
		OK_FLEX_GET(SetParticles, NvFlexSetParticles) OK_FLEX_GET(GetParticles, NvFlexGetParticles) OK_FLEX_GET(SetRestParticles, NvFlexSetRestParticles)
		OK_FLEX_GET(SetVelocities, NvFlexSetVelocities) OK_FLEX_GET(GetVelocities, NvFlexGetVelocities) OK_FLEX_GET(SetPhases, NvFlexSetPhases)
		OK_FLEX_GET(SetSprings, NvFlexSetSprings) OK_FLEX_GET(SetDynamicTriangles, NvFlexSetDynamicTriangles) OK_FLEX_GET(SetShapes, NvFlexSetShapes)
		OK_FLEX_GET(CreateTriangleMesh, NvFlexCreateTriangleMesh) OK_FLEX_GET(DestroyTriangleMesh, NvFlexDestroyTriangleMesh)
		OK_FLEX_GET(UpdateTriangleMesh, NvFlexUpdateTriangleMesh) OK_FLEX_GET(AllocBuffer, NvFlexAllocBuffer) OK_FLEX_GET(FreeBuffer, NvFlexFreeBuffer)
		OK_FLEX_GET(Map, NvFlexMap) OK_FLEX_GET(Unmap, NvFlexUnmap) OK_FLEX_GET(AcquireContext, NvFlexAcquireContext)
		OK_FLEX_GET(RestoreContext, NvFlexRestoreContext) OK_FLEX_GET(GetDeviceName, NvFlexGetDeviceName)
#undef OK_FLEX_GET
		if (!bAll) { UE_LOG(LogOKFlexCloth, Warning, TEXT("FleX: %s lacks some exports"), Name); FPlatformProcess::FreeDllHandle(Dll); return false; }
		NvFlexInitDesc Desc = {};
		Desc.deviceIndex = 0;
		Desc.enableExtensions = true;
		Desc.computeType = Compute;
		Desc.runOnRenderContext = false;
		NvFlexLibrary* Lib = A.Init(NV_FLEX_VERSION, &ErrorCallback, &Desc);
		if (!Lib) { UE_LOG(LogOKFlexCloth, Warning, TEXT("FleX: %s did not start"), Name); FPlatformProcess::FreeDllHandle(Dll); return false; }
		GApi = A;
		GLib = Lib;
		GBackendName = FString::Printf(TEXT("%s on %hs"), Name, A.GetDeviceName ? A.GetDeviceName(Lib) : "?");
		UE_LOG(LogOKFlexCloth, Display, TEXT("FleX cloth: %s"), *GBackendName);
		return true;
	}

	/** The library, started on first use (GLock held). */
	bool Library()
	{
		if (GTried) return GLib != nullptr;
		GTried = true;
		const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("OKPhysXSecondary"));
		if (!Plugin) return false;
		const FString Dir = FPaths::ConvertRelativePathToFull(FPaths::Combine(Plugin->GetBaseDir(), TEXT("Binaries/ThirdParty/Win64")));
		const int32 Backend = CVarFlexBackend.GetValueOnAnyThread();
		if (Backend != 2 && LoadApi(Dir, TEXT("NvFlexReleaseCUDA_x64.dll"), eNvFlexCUDA)) return true;
		if (Backend != 1 && LoadApi(Dir, TEXT("NvFlexReleaseD3D_x64.dll"), eNvFlexD3D11)) return true;
		UE_LOG(LogOKFlexCloth, Warning, TEXT("FleX cloth: no backend started; skirts and sleeves keep their DynamicBones"));
		return false;
	}

	/** A host buffer of FleX (pinned on CUDA, staging on D3D), grown as needed. */
	struct FBuf
	{
		NvFlexBuffer* B = nullptr;
		int32 Count = 0, Stride = 0;
		void Ensure(int32 N, int32 InStride)
		{
			N = FMath::Max(N, 1);
			if (B && Count >= N && Stride == InStride) return;
			if (B) GApi.FreeBuffer(B);
			Count = FMath::RoundUpToPowerOfTwo(N); Stride = InStride;
			B = GApi.AllocBuffer(GLib, Count, Stride, eNvFlexBufferHost);
		}
		void Free() { if (B) GApi.FreeBuffer(B); B = nullptr; Count = 0; }
		template <typename T> T* Map() { return static_cast<T*>(GApi.Map(B, eNvFlexMapWait)); }
		void Unmap() { GApi.Unmap(B); }
	};

	struct FCloth
	{
		uint64 Key = 0;
		uint64 Session = 0;
		int32 N = 0;
		int32 Base = 0;                 // first particle in the solver
		TArray<float> InvMass;
		TArray<bool> Inactive;          // left out of the solver (a following layer)
		TArray<int32> Phase;            // per particle (group per connected piece)
		TArray<FIntVector> Tris;
		TArray<FVector3f> Rest;         // the shape it was made in
		TArray<TPair<FIntPoint, float>> Springs; // particle pair, stiffness (rest length from Rest)
		TArray<FVector3f> Pos;          // its state: where the solver has it
		TArray<FVector3f> Vel;
		TArray<FVector3f> Target;       // the pins' targets for the solve being staged / last solved
		TArray<FVector3f> Corr;         // Rust's corrections to apply before the next solve
		bool bCorr = false;
		bool bStaged = false;
		bool bNew = false;              // a result not yet collected
		bool bPrevIsCorrection = false;
		float Dt = 0.f;
		TArray<FCapsule> Caps;
	};

	struct FSolver
	{
		uint64 Session = 0;
		NvFlexSolver* Solver = nullptr;
		int32 Capacity = 0;
		TArray<uint64> Cloths;          // keys, in solver order
		TArray<FCloth*> Ptrs;           // the same cloths (stable while a solve runs: Create/Release wait for it)
		bool bLayout = true;            // particles, springs, triangles, phases to upload
		FBuf Particles, Velocities, Phases, Active, RestParticles, SpringIdx, SpringLen, SpringK, TriIdx, TriNormals;
		FBuf Geometry, ShapePos, ShapeRot, ShapePrevPos, ShapePrevRot, ShapeFlags, BodyVerts, BodyIdx;
		NvFlexTriangleMeshId BodyMesh = 0;
		TArray<FVector3f> Body;         // her body this frame
		TArray<int32> BodyTris;
		bool bBodyNew = false;
		UE::Tasks::FTask Job;
		bool bJob = false;
		double JobSeconds = 0.;
		int32 Total = 0;
		int32 NumActive = 0;

		void Wait() { if (bJob) { Job.Wait(); bJob = false; } }
		void FreeAll()
		{
			for (FBuf* B : {&Particles, &Velocities, &Phases, &Active, &RestParticles, &SpringIdx, &SpringLen, &SpringK, &TriIdx, &TriNormals,
				&Geometry, &ShapePos, &ShapeRot, &ShapePrevPos, &ShapePrevRot, &ShapeFlags, &BodyVerts, &BodyIdx}) B->Free();
			if (BodyMesh) GApi.DestroyTriangleMesh(GLib, BodyMesh);
			BodyMesh = 0;
			if (Solver) GApi.DestroySolver(Solver);
			Solver = nullptr;
			Capacity = 0;
		}
	};

	TMap<uint64, TUniquePtr<FCloth>> GCloths;
	TMap<uint64, TUniquePtr<FSolver>> GSolvers;
	TMap<uint64, uint64> GBound;        // cloth key -> session

	struct FContext { FContext() { GApi.AcquireContext(GLib); } ~FContext() { GApi.RestoreContext(GLib); } };

	FSolver& SolverOf(uint64 Session)
	{
		TUniquePtr<FSolver>& S = GSolvers.FindOrAdd(Session);
		if (!S) { S = MakeUnique<FSolver>(); S->Session = Session; }
		return *S;
	}

	/** Groups: each connected piece of a cloth (by triangles) on its own, so a lining collides with its outer cloth. */
	void MakePhases(FCloth& C, int32& NextGroup)
	{
		TArray<int32> Parent; Parent.SetNum(C.N);
		for (int32 I = 0; I < C.N; ++I) Parent[I] = I;
		auto Find = [&](int32 X) { while (Parent[X] != X) { Parent[X] = Parent[Parent[X]]; X = Parent[X]; } return X; };
		for (const FIntVector& T : C.Tris) { Parent[Find(T.X)] = Find(T.Y); Parent[Find(T.Y)] = Find(T.Z); }
		// All her cloth in one group, colliding with itself, filtered by the rest pose: particles already within the radius
		// of each other where the cloth was made never collide. Her garments' DynamicBone poses cross each other (Raiden's
		// kimono panels, her robe's lining through its outer cloth); a group per piece made FleX pull every crossing apart
		// at once and the kimono knotted into a heap round her legs (2026-11-21). OKFlexCloth.SelfCollide 0: groups per
		// piece without self-collision (pieces still meet each other).
		C.Phase.SetNum(C.N);
		const bool bSelf = CVarFlexSelf.GetValueOnAnyThread() != 0;
		TMap<int32, int32> GroupOf;
		for (int32 I = 0; I < C.N; ++I)
		{
			if (bSelf) { C.Phase[I] = NvFlexMakePhase(1, eNvFlexPhaseSelfCollide | eNvFlexPhaseSelfCollideFilter); continue; }
			int32* G = GroupOf.Find(Find(I));
			if (!G) G = &GroupOf.Add(Find(I), NextGroup++);
			C.Phase[I] = NvFlexMakePhase(*G, 0);
		}
	}

	/** Stretch springs on the edges, bending springs across each pair of triangles (as NvFlexExtCreateClothFromMesh). */
	void MakeSprings(FCloth& C)
	{
		TMap<FIntPoint, int32> EdgeTri;   // edge -> third vertex of the first triangle seen
		TSet<FIntPoint> Seen;
		const float Stretch = FMath::Clamp(CVarFlexStretch.GetValueOnAnyThread(), 0.f, 1.f);
		const float Bend = FMath::Clamp(CVarFlexBend.GetValueOnAnyThread(), 0.f, 1.f);
		auto Key = [](int32 A, int32 B) { return A < B ? FIntPoint(A, B) : FIntPoint(B, A); };
		for (const FIntVector& T : C.Tris)
		{
			const int32 V[3] = {T.X, T.Y, T.Z};
			for (int32 E = 0; E < 3; ++E)
			{
				const int32 A = V[E], B = V[(E + 1) % 3], O = V[(E + 2) % 3];
				const FIntPoint K = Key(A, B);
				if (!Seen.Contains(K)) { Seen.Add(K); C.Springs.Add({K, Stretch}); }
				if (const int32* Other = EdgeTri.Find(K))
				{
					if (Bend > 0.f && *Other != O) C.Springs.Add({Key(*Other, O), Bend});
				}
				else EdgeTri.Add(K, O);
			}
		}
	}

	/** Every cloth of the solver into its buffers (a cloth made or released). GLock and the context held. */
	bool Layout(FSolver& S)
	{
		int32 Total = 0;
		for (FCloth* C : S.Ptrs) { C->Base = Total; Total += C->N; }
		S.Total = Total;
		if (Total == 0) return true;
		if (!S.Solver || S.Capacity < Total)
		{
			if (S.Solver) GApi.DestroySolver(S.Solver);
			NvFlexSolverDesc Desc;
			GApi.SolverDescDefaults(&Desc);
			Desc.featureMode = eNvFlexFeatureModeSimpleSolids;
			Desc.maxParticles = FMath::Max(16384, int32(FMath::RoundUpToPowerOfTwo(Total + 1024)));
			Desc.maxDiffuseParticles = 0;
			Desc.maxNeighborsPerParticle = 64;
			S.Solver = GApi.CreateSolver(GLib, &Desc);
			S.Capacity = S.Solver ? Desc.maxParticles : 0;
			if (!S.Solver) { UE_LOG(LogOKFlexCloth, Warning, TEXT("FleX: no solver for %d particles"), Total); return false; }
		}
		S.Particles.Ensure(Total, sizeof(float) * 4);
		S.RestParticles.Ensure(Total, sizeof(float) * 4);
		S.Velocities.Ensure(Total, sizeof(float) * 3);
		S.Phases.Ensure(Total, sizeof(int32));
		S.Active.Ensure(Total, sizeof(int32));
		int32 NumSprings = 0, NumTris = 0;
		for (FCloth* C : S.Ptrs) { NumSprings += C->Springs.Num(); NumTris += C->Tris.Num(); }
		S.SpringIdx.Ensure(NumSprings * 2, sizeof(int32));
		S.SpringLen.Ensure(NumSprings, sizeof(float));
		S.SpringK.Ensure(NumSprings, sizeof(float));
		S.TriIdx.Ensure(NumTris * 3, sizeof(int32));
		S.TriNormals.Ensure(NumTris, sizeof(float) * 4);
		{
			float* Rest = S.RestParticles.Map<float>();
			int32* Phase = S.Phases.Map<int32>();
			int32* Active = S.Active.Map<int32>();
			int32* SI = S.SpringIdx.Map<int32>();
			float* SL = S.SpringLen.Map<float>();
			float* SK = S.SpringK.Map<float>();
			int32* TI = S.TriIdx.Map<int32>();
			int32 Sp = 0, Tr = 0, NumActive = 0;
			for (FCloth* CPtr : S.Ptrs)
			{
				FCloth& C = *CPtr;
				for (int32 I = 0; I < C.N; ++I)
				{
					const int32 P = C.Base + I;
					Rest[P * 4 + 0] = C.Rest[I].X; Rest[P * 4 + 1] = C.Rest[I].Y; Rest[P * 4 + 2] = C.Rest[I].Z; Rest[P * 4 + 3] = C.InvMass[I];
					Phase[P] = C.Phase[I];
					if (!C.Inactive[I]) Active[NumActive++] = P;
				}
				for (const TPair<FIntPoint, float>& Spring : C.Springs)
				{
					SI[Sp * 2] = C.Base + Spring.Key.X; SI[Sp * 2 + 1] = C.Base + Spring.Key.Y;
					SL[Sp] = (C.Rest[Spring.Key.X] - C.Rest[Spring.Key.Y]).Length();
					SK[Sp] = Spring.Value;
					++Sp;
				}
				for (const FIntVector& T : C.Tris) { TI[Tr * 3] = C.Base + T.X; TI[Tr * 3 + 1] = C.Base + T.Y; TI[Tr * 3 + 2] = C.Base + T.Z; ++Tr; }
			}
			S.NumActive = NumActive;
			S.RestParticles.Unmap(); S.Phases.Unmap(); S.Active.Unmap(); S.SpringIdx.Unmap(); S.SpringLen.Unmap(); S.SpringK.Unmap(); S.TriIdx.Unmap();
		}
		GApi.SetRestParticles(S.Solver, S.RestParticles.B, nullptr);
		GApi.SetPhases(S.Solver, S.Phases.B, nullptr);
		GApi.SetActive(S.Solver, S.Active.B, nullptr);
		GApi.SetActiveCount(S.Solver, S.NumActive);
		GApi.SetSprings(S.Solver, S.SpringIdx.B, S.SpringLen.B, S.SpringK.B, NumSprings);
		GApi.SetDynamicTriangles(S.Solver, S.TriIdx.B, S.TriNormals.B, NumTris);
		S.bLayout = false;
		UE_LOG(LogOKFlexCloth, Display, TEXT("FleX solver %llu: %d cloths, %d particles, %d springs, %d triangles"), S.Session, S.Cloths.Num(), Total, NumSprings, NumTris);
		return true;
	}

	FQuat4f FromX(const FVector3f& Dir)
	{
		const float L = Dir.Length();
		if (L < 1e-6f) return FQuat4f::Identity;
		return FQuat4f::FindBetweenNormals(FVector3f(1.f, 0.f, 0.f), Dir / L);
	}

	/** Her body mesh and capsules as the solver's shapes. */
	void Shapes(FSolver& S, const TArray<FCapsule>& Caps, const TArray<FVector3f>& Body, const TArray<int32>& BodyTris, bool bBodyNew)
	{
		const bool bBody = CVarFlexBody.GetValueOnAnyThread() != 0 && (S.BodyMesh != 0 || (BodyTris.Num() >= 3 && Body.Num() > 0));
		if (bBody && bBodyNew && BodyTris.Num() >= 3 && Body.Num() > 0)
		{
			if (!S.BodyMesh) S.BodyMesh = GApi.CreateTriangleMesh(GLib);
			S.BodyVerts.Ensure(Body.Num(), sizeof(float) * 4);
			S.BodyIdx.Ensure(BodyTris.Num(), sizeof(int32));
			FVector3f Lo(FLT_MAX), Hi(-FLT_MAX);
			float* V = S.BodyVerts.Map<float>();
			for (int32 I = 0; I < Body.Num(); ++I)
			{
				V[I * 4] = Body[I].X; V[I * 4 + 1] = Body[I].Y; V[I * 4 + 2] = Body[I].Z; V[I * 4 + 3] = 0.f;
				Lo = FVector3f::Min(Lo, Body[I]); Hi = FVector3f::Max(Hi, Body[I]);
			}
			S.BodyVerts.Unmap();
			FMemory::Memcpy(S.BodyIdx.Map<int32>(), BodyTris.GetData(), BodyTris.Num() * sizeof(int32));
			S.BodyIdx.Unmap();
			GApi.UpdateTriangleMesh(GLib, S.BodyMesh, S.BodyVerts.B, S.BodyIdx.B, Body.Num(), BodyTris.Num() / 3, &Lo.X, &Hi.X);
		}
		const int32 NumCaps = CVarFlexCapsules.GetValueOnAnyThread() ? Caps.Num() : 0;
		const int32 Num = (bBody ? 1 : 0) + NumCaps;
		S.Geometry.Ensure(Num, sizeof(NvFlexCollisionGeometry));
		S.ShapePos.Ensure(Num, sizeof(float) * 4); S.ShapeRot.Ensure(Num, sizeof(float) * 4);
		S.ShapePrevPos.Ensure(Num, sizeof(float) * 4); S.ShapePrevRot.Ensure(Num, sizeof(float) * 4);
		S.ShapeFlags.Ensure(Num, sizeof(int32));
		NvFlexCollisionGeometry* G = S.Geometry.Map<NvFlexCollisionGeometry>();
		float* P = S.ShapePos.Map<float>(); float* R = S.ShapeRot.Map<float>();
		float* PP = S.ShapePrevPos.Map<float>(); float* PR = S.ShapePrevRot.Map<float>();
		int32* F = S.ShapeFlags.Map<int32>();
		int32 I = 0;
		auto Put = [&](const FVector3f& At, const FQuat4f& Q)
		{
			P[I * 4] = PP[I * 4] = At.X; P[I * 4 + 1] = PP[I * 4 + 1] = At.Y; P[I * 4 + 2] = PP[I * 4 + 2] = At.Z; P[I * 4 + 3] = PP[I * 4 + 3] = 0.f;
			R[I * 4] = PR[I * 4] = Q.X; R[I * 4 + 1] = PR[I * 4 + 1] = Q.Y; R[I * 4 + 2] = PR[I * 4 + 2] = Q.Z; R[I * 4 + 3] = PR[I * 4 + 3] = Q.W;
		};
		if (bBody)
		{
			G[I].triMesh.mesh = S.BodyMesh;
			G[I].triMesh.scale[0] = G[I].triMesh.scale[1] = G[I].triMesh.scale[2] = 1.f;
			Put(FVector3f::ZeroVector, FQuat4f::Identity);
			F[I] = NvFlexMakeShapeFlags(eNvFlexShapeTriangleMesh, true);
			++I;
		}
		for (int32 C = 0; C < NumCaps; ++C)
		{
			const FVector3f A(Caps[C].A[0], Caps[C].A[1], Caps[C].A[2]), B(Caps[C].B[0], Caps[C].B[1], Caps[C].B[2]);
			G[I].capsule.radius = FMath::Max(Caps[C].Radius, 0.002f);
			G[I].capsule.halfHeight = FMath::Max((B - A).Length() * 0.5f, 0.0005f);
			Put((A + B) * 0.5f, FromX(B - A));
			F[I] = NvFlexMakeShapeFlags(eNvFlexShapeCapsule, true);
			++I;
		}
		S.Geometry.Unmap(); S.ShapePos.Unmap(); S.ShapeRot.Unmap(); S.ShapePrevPos.Unmap(); S.ShapePrevRot.Unmap(); S.ShapeFlags.Unmap();
		GApi.SetShapes(S.Solver, S.Geometry.B, S.ShapePos.B, S.ShapeRot.B, S.ShapePrevPos.B, S.ShapePrevRot.B, S.ShapeFlags.B, Num);
	}

	void Params(FSolver& S)
	{
		NvFlexParams P = {};
		P.numIterations = FMath::Clamp(CVarFlexIterations.GetValueOnAnyThread(), 1, 64);
		P.gravity[0] = 0.f; P.gravity[1] = -9.81f; P.gravity[2] = 0.f;
		P.radius = FMath::Max(0.002f, CVarFlexRadius.GetValueOnAnyThread());
		P.solidRestDistance = FMath::Clamp(CVarFlexRest.GetValueOnAnyThread(), 0.001f, P.radius);
		P.fluidRestDistance = P.solidRestDistance;
		P.dynamicFriction = CVarFlexFriction.GetValueOnAnyThread();
		P.staticFriction = CVarFlexFriction.GetValueOnAnyThread();
		P.particleFriction = CVarFlexParticleFriction.GetValueOnAnyThread();
		P.restitution = 0.f;
		P.adhesion = 0.f;
		P.sleepThreshold = 0.f;
		P.maxSpeed = 20.f;
		P.maxAcceleration = 200.f;
		P.shockPropagation = 0.f;
		P.dissipation = 0.f;
		P.damping = FMath::Max(0.f, CVarFlexDamping.GetValueOnAnyThread());
		P.drag = CVarFlexDrag.GetValueOnAnyThread();
		P.lift = CVarFlexLift.GetValueOnAnyThread();
		P.collisionDistance = FMath::Max(0.001f, CVarFlexBodyDistance.GetValueOnAnyThread());
		P.particleCollisionMargin = P.radius * 0.5f;
		P.shapeCollisionMargin = P.collisionDistance * 2.f;
		P.numPlanes = 0;
		P.relaxationMode = eNvFlexRelaxationLocal;
		P.relaxationFactor = 1.f;
		GApi.SetParams(S.Solver, &P);
	}

	/**
	 * One solve of a character's solver (a worker task, or inline). Its inputs are taken under GLock, the FleX work runs
	 * under GFlexLock only (the game thread's Step must not wait on the GPU), the results go back under GLock.
	 */
	void Solve(FSolver* SPtr, float Dt)
	{
		TRACE_CPUPROFILER_EVENT_SCOPE(OKFlexCloth_Solve);
		FSolver& S = *SPtr;
		const double Start = FPlatformTime::Seconds();
		TArray<float> PosIn, VelIn, PosOut, VelOut;
		TArray<FCapsule> Caps;
		TArray<FVector3f> Body;
		TArray<int32> BodyTris;
		bool bBodyNew = false;
		int32 Total = 0;
		{
			FScopeLock Guard(&GLock);
			for (FCloth* C : S.Ptrs) Total += C->N;
			PosIn.SetNumUninitialized(Total * 4);
			VelIn.SetNumUninitialized(Total * 3);
			int32 P = 0;
			// The pins on their targets, the free particles where the solver left them plus Rust's corrections (a correction
			// moves the particle, the part of its motion against it stops).
			for (FCloth* CPtr : S.Ptrs)
			{
				FCloth& C = *CPtr;
				if (Caps.Num() == 0) Caps = C.Caps;
				for (int32 I = 0; I < C.N; ++I, ++P)
				{
					FVector3f At = C.Pos[I], V = C.Vel[I];
					if (C.InvMass[I] <= 0.f) { At = C.Target[I]; V = FVector3f::ZeroVector; }
					else if (C.bCorr)
					{
						const FVector3f D = C.Corr[I];
						if (C.bPrevIsCorrection)
						{
							const float L = D.Length();
							if (L > 1e-6f) { At += D; const FVector3f Dir = D / L; const float Against = FVector3f::DotProduct(V, Dir); if (Against < 0.f) V -= Dir * Against; }
						}
						else At = D;
					}
					PosIn[P * 4] = At.X; PosIn[P * 4 + 1] = At.Y; PosIn[P * 4 + 2] = At.Z; PosIn[P * 4 + 3] = C.InvMass[I];
					VelIn[P * 3] = V.X; VelIn[P * 3 + 1] = V.Y; VelIn[P * 3 + 2] = V.Z;
				}
				C.bCorr = false;
			}
			if (S.bBodyNew) { Body = S.Body; BodyTris = S.BodyTris; bBodyNew = true; S.bBodyNew = false; }
		}
		if (Total == 0) return;
		const float H = FMath::Clamp(Dt, 0.f, FMath::Clamp(CVarFlexMaxDt.GetValueOnAnyThread(), 0.005f, 0.1f));
		const int32 Steps = FMath::Clamp(FMath::CeilToInt(H * FMath::Max(30.f, CVarFlexSubstepHz.GetValueOnAnyThread())), 1, FMath::Max(1, CVarFlexMaxSubsteps.GetValueOnAnyThread()));
		{
			FScopeLock Flex(&GFlexLock);
			FContext Context;
			if (S.bLayout && !Layout(S)) return;
			if (!S.Solver || S.Total != Total) return;
			FMemory::Memcpy(S.Particles.Map<float>(), PosIn.GetData(), PosIn.Num() * sizeof(float)); S.Particles.Unmap();
			FMemory::Memcpy(S.Velocities.Map<float>(), VelIn.GetData(), VelIn.Num() * sizeof(float)); S.Velocities.Unmap();
			GApi.SetParticles(S.Solver, S.Particles.B, nullptr);
			GApi.SetVelocities(S.Solver, S.Velocities.B, nullptr);
			Params(S);
			Shapes(S, Caps, Body, BodyTris, bBodyNew);
			if (H > 0.f) GApi.UpdateSolver(S.Solver, H, Steps, false);
			GApi.GetParticles(S.Solver, S.Particles.B, nullptr);
			GApi.GetVelocities(S.Solver, S.Velocities.B, nullptr);
			PosOut.SetNumUninitialized(Total * 4); VelOut.SetNumUninitialized(Total * 3);
			FMemory::Memcpy(PosOut.GetData(), S.Particles.Map<float>(), PosOut.Num() * sizeof(float)); S.Particles.Unmap();
			FMemory::Memcpy(VelOut.GetData(), S.Velocities.Map<float>(), VelOut.Num() * sizeof(float)); S.Velocities.Unmap();
		}
		{
			FScopeLock Guard(&GLock);
			int32 P = 0;
			for (FCloth* CPtr : S.Ptrs)
			{
				FCloth& C = *CPtr;
				for (int32 I = 0; I < C.N; ++I, ++P)
				{
					const FVector3f At(PosOut[P * 4], PosOut[P * 4 + 1], PosOut[P * 4 + 2]);
					const FVector3f V(VelOut[P * 3], VelOut[P * 3 + 1], VelOut[P * 3 + 2]);
					const bool bOk = FMath::IsFinite(At.X) && FMath::IsFinite(At.Y) && FMath::IsFinite(At.Z) && FMath::IsFinite(V.X) && FMath::IsFinite(V.Y) && FMath::IsFinite(V.Z);
					C.Pos[I] = bOk ? At : C.Target[I];
					C.Vel[I] = bOk ? V : FVector3f::ZeroVector;
				}
				C.bNew = true;
				C.bStaged = false;
			}
		}
		S.JobSeconds = FPlatformTime::Seconds() - Start;
		if (CVarFlexLog.GetValueOnAnyThread())
			UE_LOG(LogOKFlexCloth, Display, TEXT("FleX solver %llu: %d particles, %d substeps of %.2f ms, %d capsules%s, %.2f ms"), S.Session, Total, Steps, H / Steps * 1000.f, Caps.Num(), bBodyNew ? TEXT(", body updated") : TEXT(""), S.JobSeconds * 1000.0);
	}

	void Launch(FSolver& S)
	{
		float Dt = 0.f;
		for (FCloth* C : S.Ptrs) Dt = FMath::Max(Dt, C->Dt);
		for (FCloth* C : S.Ptrs) C->Dt = 0.f;
		if (CVarFlexAsync.GetValueOnAnyThread() != 0)
		{
			FSolver* SPtr = &S;
			S.Job = UE::Tasks::Launch(UE_SOURCE_LOCATION, [SPtr, Dt] { Solve(SPtr, Dt); });
			S.bJob = true;
		}
		else
		{
			GLock.Unlock();
			Solve(&S, Dt);
			GLock.Lock();
		}
	}

	void Bind(uint64 Key, uint64 Session)
	{
		FScopeLock Guard(&GLock);
		GBound.Add(Key, Session);
	}

	int32 Create(uint64 Key, uint32 N, const float* Pos, const float* InvMass, uint32 TriN, const uint32* Tris, uint32 Flags)
	{
		TRACE_CPUPROFILER_EVENT_SCOPE(OKFlexCloth_Create);
		if (!N || !TriN) return 0;
		FScopeLock Guard(&GLock);
		{ FScopeLock Flex(&GFlexLock); if (!Library()) return 0; }
		const uint64 Session = GBound.FindRef(Key);
		FSolver& S = SolverOf(Session);
		if (S.bJob) { GLock.Unlock(); S.Job.Wait(); GLock.Lock(); S.bJob = false; }
		if (TUniquePtr<FCloth>* Old = GCloths.Find(Key)) { S.Cloths.Remove(Key); S.Ptrs.Remove(Old->Get()); GCloths.Remove(Key); }
		TUniquePtr<FCloth> C = MakeUnique<FCloth>();
		C->Key = Key; C->Session = Session; C->N = int32(N);
		C->bPrevIsCorrection = (Flags & 2u) != 0;
		C->InvMass = TArray<float>(InvMass, int32(N));
		// Below 0: a layer Rust moves with another (left out of the solver: not active, never collides).
		C->Inactive.SetNum(N);
		for (uint32 I = 0; I < N; ++I) { C->Inactive[I] = C->InvMass[I] < 0.f; if (C->Inactive[I]) C->InvMass[I] = 0.f; }
		C->Rest.SetNum(N); C->Pos.SetNum(N); C->Vel.SetNumZeroed(N); C->Target.SetNum(N); C->Corr.SetNumZeroed(N);
		for (uint32 I = 0; I < N; ++I) { C->Rest[I] = C->Pos[I] = C->Target[I] = FVector3f(Pos[I * 3], Pos[I * 3 + 1], Pos[I * 3 + 2]); }
		C->Tris.SetNum(TriN);
		for (uint32 T = 0; T < TriN; ++T) C->Tris[T] = FIntVector(int32(Tris[T * 3]), int32(Tris[T * 3 + 1]), int32(Tris[T * 3 + 2]));
		// No springs or air triangles on the layers left out of the solver.
		C->Tris.RemoveAll([&C](const FIntVector& T) { return C->Inactive[T.X] || C->Inactive[T.Y] || C->Inactive[T.Z]; });
		int32 NextGroup = 1;
		for (FCloth* Other : S.Ptrs) for (int32 Ph : Other->Phase) NextGroup = FMath::Max(NextGroup, (Ph & eNvFlexPhaseGroupMask) + 1);
		MakePhases(*C, NextGroup);
		MakeSprings(*C);
		S.Cloths.Add(Key);
		S.Ptrs.Add(C.Get());
		S.bLayout = true;
		UE_LOG(LogOKFlexCloth, Display, TEXT("FleX cloth %llu (character %llu): %u particles, %u triangles, %d springs (%s)"), Key, Session, N, TriN, C->Springs.Num(), *GBackendName);
		GCloths.Add(Key, MoveTemp(C));
		return 1;
	}

	/**
	 * One frame of a cloth, as OKPhysXCloth's Step. Dt 0: collect (2 with Out for the targets of the last launch, 3 while
	 * the solve runs, 0 with nothing new). Dt > 0: stage this cloth's targets, corrections and capsules; when every cloth
	 * of her solver is staged (or one is staged twice) the solve of all of them starts. Dt < 0: on the targets at rest.
	 */
	int32 Step(uint64 Key, uint32 N, const float* Targets, const float* Prev, const void* CapsRaw, uint32 CapN, float Dt, float* Out)
	{
		TRACE_CPUPROFILER_EVENT_SCOPE(OKFlexCloth_Step);
		FScopeLock Guard(&GLock);
		TUniquePtr<FCloth>* Found = GCloths.Find(Key);
		if (!Found || (*Found)->N != int32(N)) return 0;
		FCloth& C = **Found;
		TUniquePtr<FSolver>* SFound = GSolvers.Find(C.Session);
		if (!SFound) return 0;
		FSolver& S = **SFound;
		const bool bRunning = S.bJob && !S.Job.IsCompleted();
		if (Dt == 0.f)
		{
			if (bRunning) return 3;
			if (S.bJob) { S.Job.Wait(); S.bJob = false; }
			if (!C.bNew) return 0;
			C.bNew = false;
			for (int32 I = 0; I < C.N; ++I)
			{
				const FVector3f P = C.InvMass[I] <= 0.f ? C.Target[I] : C.Pos[I];
				Out[I * 3] = P.X; Out[I * 3 + 1] = P.Y; Out[I * 3 + 2] = P.Z;
			}
			return 2;
		}
		if (bRunning) { C.Dt += FMath::Max(Dt, 0.f); return 3; }
		if (S.bJob) { S.Job.Wait(); S.bJob = false; }
		if (Dt < 0.f)
		{
			for (int32 I = 0; I < C.N; ++I) { C.Pos[I] = C.Target[I] = FVector3f(Targets[I * 3], Targets[I * 3 + 1], Targets[I * 3 + 2]); C.Vel[I] = FVector3f::ZeroVector; }
			C.bCorr = false;
			FMemory::Memcpy(Out, Targets, sizeof(float) * 3 * N);
			return 1;
		}
		// A cloth staged twice: a frame went by without the others (hidden, made later); solve with what there is.
		if (C.bStaged) Launch(S);
		if (S.bJob) { GLock.Unlock(); S.Job.Wait(); GLock.Lock(); S.bJob = false; }
		for (int32 I = 0; I < C.N; ++I) C.Target[I] = FVector3f(Targets[I * 3], Targets[I * 3 + 1], Targets[I * 3 + 2]);
		C.bCorr = Prev != nullptr;
		if (Prev) for (int32 I = 0; I < C.N; ++I) C.Corr[I] = FVector3f(Prev[I * 3], Prev[I * 3 + 1], Prev[I * 3 + 2]);
		C.Caps.SetNum(CapsRaw ? int32(CapN) : 0);
		if (CapsRaw && CapN) FMemory::Memcpy(C.Caps.GetData(), CapsRaw, sizeof(FCapsule) * CapN);
		C.Dt += Dt;
		C.bStaged = true;
		bool bAll = true;
		for (FCloth* Other : S.Ptrs) bAll &= Other->bStaged;
		if (bAll)
		{
			Launch(S);
			if (!S.bJob && C.bNew)
			{
				// Synchronous (OKFlexCloth.Async 0): the result for these targets now.
				C.bNew = false;
				for (int32 I = 0; I < C.N; ++I)
				{
					const FVector3f P = C.InvMass[I] <= 0.f ? C.Target[I] : C.Pos[I];
					Out[I * 3] = P.X; Out[I * 3 + 1] = P.Y; Out[I * 3 + 2] = P.Z;
				}
				return 1;
			}
		}
		return 0;
	}

	void Release(uint64 Key)
	{
		FScopeLock Guard(&GLock);
		TUniquePtr<FCloth>* Found = GCloths.Find(Key);
		GBound.Remove(Key);
		if (!Found) return;
		const uint64 Session = (*Found)->Session;
		if (TUniquePtr<FSolver>* S = GSolvers.Find(Session))
		{
			if ((*S)->bJob) { GLock.Unlock(); (*S)->Job.Wait(); GLock.Lock(); (*S)->bJob = false; }
			(*S)->Cloths.Remove(Key);
			(*S)->Ptrs.Remove(Found->Get());
			(*S)->bLayout = true;
			if ((*S)->Cloths.Num() == 0) { FScopeLock Flex(&GFlexLock); FContext Context; (*S)->FreeAll(); GSolvers.Remove(Session); }
		}
		GCloths.Remove(Key);
	}

	void Body(uint64 Session, uint32 NV, const float* Pos, uint32 NT, const uint32* Tris)
	{
		FScopeLock Guard(&GLock);
		TUniquePtr<FSolver>* Found = GSolvers.Find(Session);
		if (!Found || !NV || !NT) return;
		FSolver& S = **Found;
		// The solve may be reading the last body: the next one takes this (it is copied under GLock in Shapes).
		S.Body.SetNum(NV);
		FMemory::Memcpy(S.Body.GetData(), Pos, sizeof(float) * 3 * NV);
		if (S.BodyTris.Num() != int32(NT * 3)) { S.BodyTris.SetNum(NT * 3); FMemory::Memcpy(S.BodyTris.GetData(), Tris, sizeof(uint32) * 3 * NT); }
		S.bBodyNew = true;
	}

	int32 CreateAbi(uint64 Key, uint32 N, const float* Pos, const float* InvMass, uint32 TriN, const uint32* Tris, uint32 Flags) { return Create(Key, N, Pos, InvMass, TriN, Tris, Flags); }
	int32 StepAbi(uint64 Key, uint32 N, const float* Targets, const float* Prev, const void* Caps, uint32 CapN, float Dt, float* Out) { return Step(Key, N, Targets, Prev, Caps, CapN, Dt, Out); }
	void ReleaseAbi(uint64 Key) { Release(Key); }
	void BindAbi(uint64 Key, uint64 Session) { Bind(Key, Session); }
	void BodyAbi(uint64 Session, uint32 NV, const float* Pos, uint32 NT, const uint32* Tris) { Body(Session, NV, Pos, NT, Tris); }
}

namespace OKPhysXSecondary
{
	void RegisterFlexCloth(FSetFlexClothFn SetCloth)
	{
		FModuleManager::Get().LoadModuleChecked<IModuleInterface>(TEXT("OKPhysXSecondary"));
		if (SetCloth) SetCloth(&CreateAbi, &StepAbi, &ReleaseAbi, &BindAbi, &BodyAbi);
	}
	void ShutdownFlexCloth()
	{
		FScopeLock Guard(&GLock);
		for (auto& S : GSolvers) if (S.Value->bJob) S.Value->Job.Wait();
		FScopeLock Flex(&GFlexLock);
		if (GLib)
		{
			FContext Context;
			for (auto& S : GSolvers) S.Value->FreeAll();
		}
		GSolvers.Empty();
		GCloths.Empty();
		if (GLib) { GApi.Shutdown(GLib); GLib = nullptr; }
	}
}
#else
namespace OKPhysXSecondary
{
	void RegisterFlexCloth(FSetFlexClothFn) {}
	void ShutdownFlexCloth() {}
}
#endif
