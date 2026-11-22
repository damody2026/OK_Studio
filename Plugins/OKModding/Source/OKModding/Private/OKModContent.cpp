#include "OKModContent.h"
#include "OKModHost.h"
#include "KKPreviewActor.h"
#include "Components/MeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/SubsurfaceProfile.h"
#include "Engine/Texture2D.h"
#include "Engine/Texture2DArray.h"
#include "Engine/TextureCube.h"
#include "Engine/VolumeTexture.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerController.h"
#include "HAL/IConsoleManager.h"
#include "ImageUtils.h"
#include "Materials/Material.h"
#include "Materials/MaterialFunctionInterface.h"
#include "Materials/MaterialInstanceConstant.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialParameterCollection.h"
#include "MaterialShared.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/CoreDelegates.h"
#include "Misc/EngineVersion.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "RHIGlobals.h"
#include "ShaderCodeLibrary.h"
#include "UObject/Package.h"
#include "UObject/UObjectHash.h"
#include "Serialization/JsonSerializer.h"
#include "Containers/Ticker.h"
#include "HAL/PlatformTime.h"
#include "UnrealClient.h"

namespace
{
TMap<FString, TSharedPtr<FKKModMaterial>> GMaterials;
// Mods whose content was handled (mounted or refused) in this process: B layer is set up once.
TMap<FString, bool> GContentUsable;

const TCHAR* ParentPath(const FString& Short)
{
	if (Short == TEXT("opaque")) return TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewOpaque.M_PreviewOpaque");
	if (Short == TEXT("masked")) return TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewMasked.M_PreviewMasked");
	if (Short == TEXT("translucent")) return TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewTranslucent.M_PreviewTranslucent");
	if (Short == TEXT("xray")) return TEXT("/Game/IndependentResources/PreviewMaterials/M_PreviewXRay.M_PreviewXRay");
	return nullptr;
}

// Section 6.11's whitelist: the only asset classes a mod pak may hold (no Blueprint, nothing executable).
bool AllowedClass(const UObject* Object)
{
	return Object->IsA<UMaterial>() || Object->IsA<UMaterialInstanceConstant>() || Object->IsA<UMaterialFunctionInterface>()
		|| Object->IsA<UMaterialParameterCollection>() || Object->IsA<UTexture2D>() || Object->IsA<UTextureCube>()
		|| Object->IsA<UTexture2DArray>() || Object->IsA<UVolumeTexture>() || Object->IsA<USubsurfaceProfile>();
}

struct FPakEntries : IPlatformFile::FDirectoryVisitor
{
	TArray<FString> Files;
	virtual bool Visit(const TCHAR* Name, bool bIsDirectory) override
	{
		if (!bIsDirectory) Files.Add(FString(Name).Replace(TEXT("\\"), TEXT("/")));
		return true;
	}
};

// Mounts one mod's paks and opens its shader library; every entry must sit under the mod's own content folder and every
// asset must be of a whitelisted class, else the paks are unmounted and the mod's cooked materials are not used.
bool MountContent(const FString& Id, const TSharedPtr<FJsonObject>& Mod)
{
	const FString Root = Mod->GetStringField(TEXT("content_root"));
	FString ModBuild;
	Mod->TryGetStringField(TEXT("content_build"), ModBuild);
	const FString GameBuild = OKModContent::ContentBuild();
	if (ModBuild != GameBuild)
	{
		UE_LOG(LogOKMod, Warning, TEXT("[%s] content pak not used: content_build \"%s\", this game is \"%s\" (cook it again for this build)"), *Id, *ModBuild, *GameBuild);
		return false;
	}
	if (!FPlatformProperties::RequiresCookedData())
	{
		UE_LOG(LogOKMod, Display, TEXT("[%s] content pak not used in the editor (cooked content only loads in a packaged game); materials use their A-layer fallback"), *Id);
		return false;
	}
	if (!FCoreDelegates::MountPak.IsBound())
	{
		UE_LOG(LogOKMod, Warning, TEXT("[%s] content pak not used: no pak file system"), *Id);
		return false;
	}
	TArray<FString> Paks;
	Mod->TryGetStringArrayField(TEXT("paks"), Paks);
	TArray<FString> Mounted, Packages;
	FString MountDir;
	auto Refuse = [&](const FString& Why)
	{
		UE_LOG(LogOKMod, Error, TEXT("[%s] content pak refused: %s"), *Id, *Why);
		for (const FString& P : Mounted) if (FCoreDelegates::OnUnmountPak.IsBound()) FCoreDelegates::OnUnmountPak.Execute(P);
		return false;
	};
	const FString ExpectedMount = (FPaths::ProjectDir() / TEXT("Mods") / Root / TEXT("Content/")).Replace(TEXT("\\"), TEXT("/"));
	for (const FString& Pak : Paks)
	{
		IPakFile* File = FCoreDelegates::MountPak.Execute(Pak, 0);
		if (!File) return Refuse(TEXT("could not mount ") + Pak);
		Mounted.Add(Pak);
		const FString Mount = File->PakGetMountPoint().Replace(TEXT("\\"), TEXT("/"));
		if (!Mount.Equals(ExpectedMount, ESearchCase::IgnoreCase)) return Refuse(FString::Printf(TEXT("%s mounts at %s, must be %s"), *Pak, *Mount, *ExpectedMount));
		MountDir = Mount;
		FPakEntries Entries;
		File->PakVisitPrunedFilenames(Entries);
		for (const FString& Entry : Entries.Files)
		{
			// Entries come relative to the mount point (or, from other pak readers, with it in front).
			const FString Rel = Entry.StartsWith(Mount, ESearchCase::IgnoreCase) ? Entry.Mid(Mount.Len()) : Entry;
			if (Rel.IsEmpty() || Rel.StartsWith(TEXT("/")) || Rel.StartsWith(TEXT("../")) || Rel.Contains(TEXT(":")) || ("/" + Rel + "/").Contains(TEXT("/../")) || ("/" + Rel + "/").Contains(TEXT("/./")))
				return Refuse(TEXT("entry outside the mod's folder: ") + Entry);
			const FString Ext = FPaths::GetExtension(Rel).ToLower();
			if (Ext == TEXT("uasset")) Packages.Add(TEXT("/") + Root + TEXT("/") + FPaths::GetBaseFilename(Rel, false));
			else if (Ext == TEXT("uexp") || Ext == TEXT("ubulk") || Ext == TEXT("uptnl")) {}
			else if (Ext == TEXT("ushaderbytecode") && !Rel.Contains(TEXT("/")) && Rel.StartsWith(TEXT("ShaderArchive-") + Mod->GetStringField(TEXT("shader_library")))) {}
			else return Refuse(TEXT("file type not allowed: ") + Rel);
		}
	}
	const FString PackageRoot = TEXT("/") + Root + TEXT("/");
	if (!FPackageName::MountPointExists(PackageRoot)) FPackageName::RegisterMountPoint(PackageRoot, MountDir);
	// The library before any material: a material serialized without it has no shaders and falls back to the default
	// (black characters, 2026-11-17).
	if (!FShaderCodeLibrary::OpenLibrary(Mod->GetStringField(TEXT("shader_library")), MountDir)) return Refuse(TEXT("shader library ") + Mod->GetStringField(TEXT("shader_library")) + TEXT(" did not open"));
	for (const FString& Name : Packages)
	{
		UPackage* Package = LoadPackage(nullptr, *Name, LOAD_None);
		if (!Package) return Refuse(TEXT("could not load ") + Name);
		FString Bad;
		ForEachObjectWithPackage(Package, [&](UObject* Object)
		{
			if (Object->IsA<UPackage>() || AllowedClass(Object)) return true;
			// Subobjects of an allowed asset (e.g. a texture's platform data holder) are judged with their asset.
			for (UObject* Outer = Object->GetOuter(); Outer && !Outer->IsA<UPackage>(); Outer = Outer->GetOuter()) if (AllowedClass(Outer)) return true;
			Bad = FString::Printf(TEXT("%s is a %s"), *Object->GetPathName(), *Object->GetClass()->GetPathName());
			return false;
		});
		if (!Bad.IsEmpty()) return Refuse(TEXT("class not on the whitelist: ") + Bad);
	}
	UE_LOG(LogOKMod, Display, TEXT("[%s] content mounted: %d pak(s), %d asset(s) at %s, shader library %s"), *Id, Mounted.Num(), Packages.Num(), *PackageRoot, *Mod->GetStringField(TEXT("shader_library")));
	return true;
}

TSharedPtr<FKKModMaterial> BuildMaterial(const FString& ModId, bool bContent, const TSharedPtr<FJsonObject>& M)
{
	auto Out = MakeShared<FKKModMaterial>();
	Out->Id = M->GetStringField(TEXT("id"));
	FString Asset, Parent, MainTexture;
	M->TryGetStringField(TEXT("asset"), Asset);
	M->TryGetStringField(TEXT("parent"), Parent);
	if (M->TryGetStringField(TEXT("main_texture"), MainTexture)) Out->MainTexture = FName(*MainTexture);
	M->TryGetBoolField(TEXT("copy_source_values"), Out->bCopySourceValues);
	UMaterialInterface* Material = nullptr;
	if (!Asset.IsEmpty() && bContent)
	{
		Material = LoadObject<UMaterialInterface>(nullptr, *Asset);
		const FMaterialResource* Resource = Material ? Material->GetMaterialResource(GMaxRHIShaderPlatform) : nullptr;
		const UMaterial* Base = Material ? Material->GetMaterial() : nullptr;
		if (!Material || !Resource || !Resource->GetGameThreadShaderMap() || (Base && Base->IsDefaultMaterial()))
		{
			UE_LOG(LogOKMod, Warning, TEXT("[%s] %s: %s has no shaders for this game (not cooked with them?); using its fallback"), *ModId, *Out->Id, *Asset);
			Material = nullptr;
		}
	}
	if (!Material && !Parent.IsEmpty())
		if (const TCHAR* Path = ParentPath(Parent))
		{
			Material = LoadObject<UMaterialInterface>(nullptr, Path);
			// The core parents take the part's texture as PreviewTexture and their colour as PreviewTint.
			if (Material) Out->MainTexture = TEXT("PreviewTexture");
		}
	if (!Material)
	{
		UE_LOG(LogOKMod, Warning, TEXT("[%s] %s: no usable material (asset %s, parent %s)"), *ModId, *Out->Id, *Asset, *Parent);
		return nullptr;
	}
	Out->Material.Reset(Material);
	const TSharedPtr<FJsonObject>* Obj = nullptr;
	if (M->TryGetObjectField(TEXT("scalars"), Obj))
		for (const auto& P : (*Obj)->Values) Out->Scalars.Add(FName(*P.Key), float(P.Value->AsNumber()));
	if (M->TryGetObjectField(TEXT("vectors"), Obj))
		for (const auto& P : (*Obj)->Values)
		{
			const TArray<TSharedPtr<FJsonValue>>& V = P.Value->AsArray();
			if (V.Num() == 4) Out->Vectors.Add(FName(*P.Key), FLinearColor(V[0]->AsNumber(), V[1]->AsNumber(), V[2]->AsNumber(), V[3]->AsNumber()));
		}
	if (M->TryGetObjectField(TEXT("textures"), Obj))
		for (const auto& P : (*Obj)->Values)
		{
			UTexture2D* Texture = FImageUtils::ImportFileAsTexture2D(P.Value->AsString());
			if (!Texture) { UE_LOG(LogOKMod, Warning, TEXT("[%s] %s: could not read %s"), *ModId, *Out->Id, *P.Value->AsString()); continue; }
			Out->Textures.Emplace(FName(*P.Key), TStrongObjectPtr<UTexture>(Texture));
		}
	UE_LOG(LogOKMod, Display, TEXT("[%s] material %s ready: %s"), *ModId, *Out->Id, *Material->GetPathName());
	return Out;
}
}

FString OKModContent::ContentBuild()
{
	FString Build = TEXT("0");
	GConfig->GetString(TEXT("OKModding"), TEXT("ContentBuild"), Build, GGameIni);
	// Engine/Build/Build.version's version and Changelist (0 for a source build; CompatibleWith() is 5.8.0-0 in a
	// packaged source build, so it does not tell engine builds apart).
	const FEngineVersion& V = FEngineVersion::Current();
	return FString::Printf(TEXT("%s@%d.%d.%d-%u"), *Build, V.GetMajor(), V.GetMinor(), V.GetPatch(), V.GetChangelist());
}

void OKModContent::Refresh()
{
	check(IsInGameThread());
	TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
	Request->SetStringField(TEXT("op"), TEXT("content"));
	FString Error;
	const TSharedPtr<FJsonObject> Answer = FOKModHost::Get().DispatchJson(Request, Error);
	const TArray<TSharedPtr<FJsonValue>>* Mods = nullptr;
	if (!Answer.IsValid() || !Answer->TryGetArrayField(TEXT("mods"), Mods)) return;
	TMap<FString, TSharedPtr<FKKModMaterial>> Materials;
	TMap<FString, TSharedPtr<FKKModMaterial>> Families;
	for (const TSharedPtr<FJsonValue>& Value : *Mods)
	{
		const TSharedPtr<FJsonObject> Mod = Value->AsObject();
		const FString Id = Mod->GetStringField(TEXT("id"));
		TArray<FString> Problems;
		Mod->TryGetStringArrayField(TEXT("problems"), Problems);
		for (const FString& P : Problems) UE_LOG(LogOKMod, Warning, TEXT("[%s] %s"), *Id, *P);
		bool bContent = false;
		if (const bool* Done = GContentUsable.Find(Id)) bContent = *Done;
		else
		{
			TArray<FString> Paks;
			Mod->TryGetStringArrayField(TEXT("paks"), Paks);
			bContent = !Paks.IsEmpty() && MountContent(Id, Mod);
			GContentUsable.Add(Id, bContent);
		}
		const TArray<TSharedPtr<FJsonValue>>* Decls = nullptr;
		if (!Mod->TryGetArrayField(TEXT("materials"), Decls)) continue;
		for (const TSharedPtr<FJsonValue>& D : *Decls)
		{
			const TSharedPtr<FJsonObject> M = D->AsObject();
			// Built once per process: a refresh after another mode loaded keeps the existing instances.
			TSharedPtr<FKKModMaterial> Material = GMaterials.FindRef(M->GetStringField(TEXT("id")));
			if (!Material) Material = BuildMaterial(Id, bContent, M);
			if (!Material) continue;
			Materials.Add(Material->Id, Material);
			TArray<FString> Shaders;
			M->TryGetStringArrayField(TEXT("families"), Shaders);
			for (const FString& Shader : Shaders)
			{
				const FString Key = Shader.ToLower();
				if (const TSharedPtr<FKKModMaterial>* Taken = Families.Find(Key))
				{
					UE_LOG(LogOKMod, Warning, TEXT("[%s] shader family \"%s\" is already drawn by %s (loaded earlier); %s is not used for it"), *Id, *Shader, *(*Taken)->Id, *Material->Id);
					continue;
				}
				Families.Add(Key, Material);
			}
		}
	}
	GMaterials = MoveTemp(Materials);
	const int32 FamilyCount = Families.Num();
	KKModMaterials::SetFamilies(MoveTemp(Families));
	if (GMaterials.Num() || FamilyCount) UE_LOG(LogOKMod, Display, TEXT("Mod materials: %d, shader families: %d"), GMaterials.Num(), FamilyCount);

	// material.resolve_shader: a mod picks the material per part ({"shader","part"} -> {"material":"<mod>/<name>"} or
	// nothing). Only installed while someone subscribed, so parts cost nothing otherwise. Asked on every part build (no
	// cache): a mod's answer may follow its settings.
	TSharedRef<FJsonObject> Who = MakeShared<FJsonObject>();
	Who->SetStringField(TEXT("op"), TEXT("subscribers"));
	Who->SetStringField(TEXT("hook"), TEXT("material.resolve_shader"));
	const TSharedPtr<FJsonObject> Subscribers = FOKModHost::Get().DispatchJson(Who, Error);
	const TArray<TSharedPtr<FJsonValue>>* Names = nullptr;
	if (!Subscribers.IsValid() || !Subscribers->TryGetArrayField(TEXT("mods"), Names) || Names->IsEmpty())
	{
		KKModMaterials::SetResolver(nullptr);
		return;
	}
	UE_LOG(LogOKMod, Display, TEXT("material.resolve_shader: %d mod(s) choose materials per part"), Names->Num());
	KKModMaterials::SetResolver([](const FString& Shader, const FString& Part) -> TSharedPtr<FKKModMaterial>
	{
		TSharedRef<FJsonObject> Payload = MakeShared<FJsonObject>();
		Payload->SetStringField(TEXT("shader"), Shader);
		Payload->SetStringField(TEXT("part"), Part);
		TSharedRef<FJsonObject> Hook = MakeShared<FJsonObject>();
		Hook->SetStringField(TEXT("op"), TEXT("hook"));
		Hook->SetStringField(TEXT("hook"), TEXT("material.resolve_shader"));
		Hook->SetObjectField(TEXT("payload"), Payload);
		FString HookError;
		TSharedPtr<FKKModMaterial> Chosen;
		const TSharedPtr<FJsonObject> Answer = FOKModHost::Get().DispatchJson(Hook, HookError);
		const TArray<TSharedPtr<FJsonValue>>* Replies = nullptr;
		if (Answer.IsValid() && Answer->TryGetArrayField(TEXT("replies"), Replies))
			for (const TSharedPtr<FJsonValue>& R : *Replies)
			{
				const TSharedPtr<FJsonObject> Reply = R->AsObject();
				const TSharedPtr<FJsonObject>* Json = nullptr;
				FString Id;
				// The first mod (load order) that names a material wins.
				if (!Reply.IsValid() || !Reply->TryGetObjectField(TEXT("json"), Json) || !(*Json)->TryGetStringField(TEXT("material"), Id)) continue;
				Chosen = OKModContent::Find(Id);
				if (Chosen) break;
				UE_LOG(LogOKMod, Warning, TEXT("material.resolve_shader: %s named %s, which is not a loaded mod material"), *Reply->GetStringField(TEXT("mod")), *Id);
			}
		return Chosen;
	});
}

TSharedPtr<FKKModMaterial> OKModContent::Find(const FString& Id) { return GMaterials.FindRef(Id); }

TArray<FString> OKModContent::MaterialIds()
{
	TArray<FString> Out;
	GMaterials.GetKeys(Out);
	Out.Sort();
	return Out;
}

// ---------------------------------------------------------------------------------------------------- console

static UWorld* OKModGameWorld()
{
	if (GEngine) for (const FWorldContext& C : GEngine->GetWorldContexts()) if (C.World() && C.World()->IsGameWorld()) return C.World();
	return nullptr;
}

// The part's current texture and values, from the material it draws with now (the card's own were applied to it).
static UTexture* OKModPartTexture(UMaterialInterface* Current)
{
	UTexture* Texture = nullptr;
	if (Current) for (const TCHAR* Name : { TEXT("_MainTex"), TEXT("MainTex"), TEXT("BaseTexture"), TEXT("Texture"), TEXT("PreviewTexture") })
		if (Current->GetTextureParameterValue(FHashedMaterialParameterInfo(Name), Texture) && Texture) return Texture;
	return nullptr;
}

static void OKModMaterialList(const TArray<FString>&, FOutputDevice& Out)
{
	for (const FString& Id : OKModContent::MaterialIds())
	{
		const TSharedPtr<FKKModMaterial> M = OKModContent::Find(Id);
		Out.Log(FString::Printf(TEXT("%s -> %s"), *Id, M && M->Material.IsValid() ? *M->Material->GetPathName() : TEXT("-")));
	}
	Out.Log(FString::Printf(TEXT("%d material(s), %d shader famil(ies); content build %s"), OKModContent::MaterialIds().Num(), KKModMaterials::FamilyCount(), *OKModContent::ContentBuild()));
}

// mod.material.apply <material id> <part name substring>: that material on every matching part of the characters shown
// (MaterialEditor's shader swap, for this session; kept on the card once card data is open to mods).
static void OKModMaterialApply(const TArray<FString>& Args, FOutputDevice& Out)
{
	if (Args.Num() < 2) { Out.Log(TEXT("mod.material.apply <mod id>/<name> <part name substring>")); return; }
	const TSharedPtr<FKKModMaterial> M = OKModContent::Find(Args[0]);
	if (!M) { Out.Log(TEXT("no mod material ") + Args[0] + TEXT(" (mod.material.list)")); return; }
	UWorld* World = OKModGameWorld();
	int32 Applied = 0;
	if (World)
		for (TActorIterator<AKKPreviewActor> It(World); It; ++It)
		{
			// A part by its role (the card's part name, e.g. "socks", "glasses") or its component name (Part_<n>). What
			// draws it may be another component (the GPU-skinned follower), tagged KKSessionPart_<session index>.
			TSet<UMeshComponent*> Targets;
			TSet<int32> Sessions;
			TMap<UMeshComponent*, FString> RoleOf;
			for (const FKKLoadedPart& Part : It->Parts)
			{
				if (!Part.Comp || !(Part.Role.Contains(Args[1]) || Part.Comp->GetName().Contains(Args[1]))) continue;
				Targets.Add(Part.Comp);
				RoleOf.Add(Part.Comp, Part.Role);
				if (Part.SessionIndex != INDEX_NONE) Sessions.Add(Part.SessionIndex);
			}
			TArray<UMeshComponent*> All;
			It->GetComponents(All);
			for (UMeshComponent* C : All)
				for (const FName& Tag : C->ComponentTags)
				{
					const FString T = Tag.ToString();
					if (T.StartsWith(TEXT("KKSessionPart_")) && Sessions.Contains(FCString::Atoi(*T.Mid(14)))) { Targets.Add(C); RoleOf.Add(C, T); }
				}
			for (UMeshComponent* Mesh : Targets)
			for (int32 Slot = 0; Slot < FMath::Max(1, Mesh->GetNumMaterials()); ++Slot)
			{
				UMaterialInterface* Current = Mesh->GetMaterial(Slot);
				UMaterialInstanceDynamic* Dynamic = KKModMaterials::MakeInstance(*M, Mesh, OKModPartTexture(Current), [Current](const FString& P, FLinearColor& V)
				{
					if (!Current) return false;
					float S = 0;
					if (Current->GetVectorParameterValue(FHashedMaterialParameterInfo(*P), V)) return true;
					if (Current->GetScalarParameterValue(FHashedMaterialParameterInfo(*P), S)) { V = FLinearColor(S, S, S, S); return true; }
					return false;
				});
				if (!Dynamic) continue;
				Mesh->SetMaterial(Slot, Dynamic);
				++Applied;
				UE_LOG(LogOKMod, Display, TEXT("mod.material.apply %s on %s.%s slot %d (%s)"), *M->Id, *It->GetName(), *Mesh->GetName(), Slot, *RoleOf.FindRef(Mesh));
			}
		}
	Out.Log(FString::Printf(TEXT("%s on %d material slot(s)"), *M->Id, Applied));
	if (!Applied && World)
	{
		TArray<FString> Roles;
		for (TActorIterator<AKKPreviewActor> It(World); It; ++It) for (const FKKLoadedPart& Part : It->Parts) Roles.AddUnique(Part.Role);
		Out.Log(TEXT("parts shown: ") + FString::Join(Roles, TEXT(", ")));
	}
}

// mod.material.preview <material id>... [Shot=<png>] [Quit=1]: each on a plane in front of the camera (checking a
// cooked material draws, e.g. in the ModKit probe stage); Shot after 3 s, Quit after 6 s.
static void OKModMaterialPreview(const TArray<FString>& AllArgs, FOutputDevice& Out)
{
	TArray<FString> Args;
	FString Shot;
	bool bQuit = false;
	for (const FString& A : AllArgs)
	{
		if (A.StartsWith(TEXT("Shot="))) Shot = A.Mid(5);
		else if (A == TEXT("Quit=1")) bQuit = true;
		else Args.Add(A);
	}
	if (!Shot.IsEmpty() || bQuit)
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Shot, bQuit, Start = FPlatformTime::Seconds(), bShot = false](float) mutable
		{
			const double Age = FPlatformTime::Seconds() - Start;
			if (!bShot && Age > 3.0) { bShot = true; if (!Shot.IsEmpty()) FScreenshotRequest::RequestScreenshot(Shot, false, false); }
			if (bQuit && Age > 6.0) { FPlatformMisc::RequestExit(false, TEXT("mod.material.preview")); return false; }
			return !bQuit || Age <= 6.0;
		}));
	UWorld* World = OKModGameWorld();
	UStaticMesh* Plane = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Plane.Plane"));
	if (!World || !Plane) { Out.Log(TEXT("no game world or plane mesh")); return; }
	FVector Eye = FVector::ZeroVector; FRotator View = FRotator::ZeroRotator;
	if (APlayerController* PC = World->GetFirstPlayerController()) PC->GetPlayerViewPoint(Eye, View);
	const FVector Forward = View.Vector(), Right = FRotationMatrix(View).GetUnitAxis(EAxis::Y);
	for (int32 I = 0; I < Args.Num(); ++I)
	{
		const TSharedPtr<FKKModMaterial> M = OKModContent::Find(Args[I]);
		if (!M) { Out.Log(TEXT("no mod material ") + Args[I]); continue; }
		FActorSpawnParameters Params; Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		const FVector At = Eye + Forward * 300.f + Right * ((I - (Args.Num() - 1) * .5f) * 220.f);
		AStaticMeshActor* Actor = World->SpawnActor<AStaticMeshActor>(At, FRotationMatrix::MakeFromZ(-Forward).Rotator(), Params);
		if (!Actor) continue;
		Actor->GetStaticMeshComponent()->SetMobility(EComponentMobility::Movable);
		Actor->GetStaticMeshComponent()->SetStaticMesh(Plane);
		Actor->GetStaticMeshComponent()->SetMaterial(0, KKModMaterials::MakeInstance(*M, Actor, nullptr, [](const FString&, FLinearColor&) { return false; }));
		Actor->SetActorScale3D(FVector(2.f));
		const FMaterialResource* Resource = M->Material->GetMaterialResource(GMaxRHIShaderPlatform);
		Out.Log(FString::Printf(TEXT("%s: %s shadermap=%d"), *M->Id, *M->Material->GetPathName(), Resource && Resource->GetGameThreadShaderMap() != nullptr));
	}
}

static FAutoConsoleCommandWithArgsAndOutputDevice GOKModMaterialList(TEXT("mod.material.list"), TEXT("Mods: their materials and the content build"),
	FConsoleCommandWithArgsAndOutputDeviceDelegate::CreateStatic(&OKModMaterialList));
static FAutoConsoleCommandWithArgsAndOutputDevice GOKModMaterialApply(TEXT("mod.material.apply"), TEXT("Mods: mod.material.apply <mod id>/<name> <part name substring> -- that material on the matching parts of the characters shown"),
	FConsoleCommandWithArgsAndOutputDeviceDelegate::CreateStatic(&OKModMaterialApply));
static FAutoConsoleCommandWithArgsAndOutputDevice GOKModMaterialPreview(TEXT("mod.material.preview"), TEXT("Mods: mod.material.preview <mod id>/<name>... -- each on a plane in front of the camera"),
	FConsoleCommandWithArgsAndOutputDeviceDelegate::CreateStatic(&OKModMaterialPreview));
