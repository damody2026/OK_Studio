// OK Studio in-game: picking in the view, framing the selection, view presets and bookmarks, camera objects from the
// view, auto backups and the open report.
#include "OKStudioGame.h"
#include "OKStudioGameInternal.h"
#include "OKStudioSettings.h"
#include "OKSceneActor.h"
#include "KKAffineProceduralMeshComponent.h"
#include "KKPreviewActor.h"
#include "Blueprint/WidgetLayoutLibrary.h"
#include "Camera/CameraComponent.h"
#include "Components/MeshComponent.h"
#include "Components/PoseableMeshComponent.h"
#include "AnimationRuntime.h"
#include "Components/PrimitiveComponent.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "HAL/FileManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

namespace
{
	const FVector InitialFocus(0.f, 0.f, 90.f);
	constexpr float InitialYaw = -90.f, InitialPitch = -8.f, InitialDistance = 380.f;

	/** The bones of a shown character with their parents (world positions), for picking and framing. */
	bool SkeletonSegments(const AKKPreviewActor* Actor, TArray<TPair<FVector, FVector>>& Out)
	{
		UPoseableMeshComponent* Mesh = Actor ? (Actor->BodySkel ? Actor->BodySkel.Get() : (Actor->SkelFollowers.Num() ? Actor->SkelFollowers[0].Get() : nullptr)) : nullptr;
		if (!Mesh) return false;
		const int32 Bones = Mesh->GetNumBones();
		for (int32 B = 0; B < Bones; ++B)
		{
			const FName Name = Mesh->GetBoneName(B);
			const FName Parent = Mesh->GetParentBone(Name);
			if (Parent.IsNone()) continue;
			const FVector A = Mesh->GetBoneTransformByName(Name, EBoneSpaces::WorldSpace).GetLocation();
			const FVector P = Mesh->GetBoneTransformByName(Parent, EBoneSpaces::WorldSpace).GetLocation();
			// Long jumps (the root to the hips) and zero-length bones say nothing about where the body is.
			const double L = FVector::Distance(A, P);
			if (L > 0.5 && L < 60.) Out.Add({ P, A });
		}
		return Out.Num() > 0;
	}

	double PointSegment(const FVector2D& P, const FVector2D& A, const FVector2D& B)
	{
		const FVector2D AB = B - A;
		const double T = AB.SizeSquared() > 1e-6 ? FMath::Clamp(FVector2D::DotProduct(P - A, AB) / AB.SizeSquared(), 0., 1.) : 0.;
		return FVector2D::Distance(P, A + AB * T);
	}
}

bool UOKStudioGame::WorldBounds(int32 Id, FBox& Out) const
{
	Out = FBox(ForceInit);
	const FOKSceneObject* O = Document ? Document->Find(Id) : nullptr;
	if (!O || !SceneActor) return false;
	if (O->Kind == EOKSceneObjectKind::Character)
	{
		const AKKPreviewActor* Preview = SceneActor->PreviewOf(Id);
		if (Preview)
		{
			TInlineComponentArray<UMeshComponent*> Meshes(Preview);
			for (const UMeshComponent* M : Meshes)
				if (M && M->IsRegistered() && M->IsVisible() && M->bRenderInMainPass && !M->ComponentHasTag(TEXT("KKPreviewOutline")) && M->Bounds.SphereRadius > KINDA_SMALL_NUMBER)
				{
					const UKKAffineProceduralMeshComponent* Affine = Cast<UKKAffineProceduralMeshComponent>(M);
					Out += Affine ? Affine->CurrentWorldBounds() : M->Bounds.GetBox();
				}
		}
		// Nothing drawn (still loading, an invisible body): its bones.
		TArray<TPair<FVector, FVector>> Segments;
		if (!Out.IsValid && SkeletonSegments(Preview, Segments)) for (const TPair<FVector, FVector>& S : Segments) { Out += S.Key; Out += S.Value; }
	}
	else if (const AKKPreviewActor* Preview = SceneActor->PreviewOf(Id))
	{
		// Items are shown by a preview actor of their own (like characters): its drawn meshes.
		TInlineComponentArray<UPrimitiveComponent*> Parts(Preview);
		for (const UPrimitiveComponent* P : Parts) if (P->IsVisible() && P->IsRegistered()) Out += P->Bounds.GetBox();
	}
	else if (USceneComponent* C = SceneActor->ComponentOf(Id))
	{
		TArray<USceneComponent*> Children;
		C->GetChildrenComponents(true, Children);
		Children.Add(C);
		for (USceneComponent* Child : Children)
			if (const UPrimitiveComponent* P = Cast<UPrimitiveComponent>(Child); P && P->IsVisible() && P->IsRegistered()) Out += P->Bounds.GetBox();
	}
	if (!Out.IsValid)
	{
		// A light, a camera, a folder or an object not built: a small box where it is.
		const FVector At = (Document->WorldTransform(Id) * SceneActor->GetActorTransform()).GetLocation();
		Out = FBox(At - FVector(15.), At + FVector(15.));
	}
	return true;
}

int32 UOKStudioGame::PickObject(const FVector2D& Position) const
{
	APlayerController* PC = SceneActor && SceneActor->GetWorld() ? SceneActor->GetWorld()->GetFirstPlayerController() : nullptr;
	if (!PC || !PC->PlayerCameraManager || !Document) return -1;
	const FVector Eye = PC->PlayerCameraManager->GetCameraLocation();
	auto Project = [PC](const FVector& W, FVector2D& S) { return UWidgetLayoutLibrary::ProjectWorldLocationToWidgetPosition(PC, W, S, true); };
	int32 Best = -1;
	double BestDepth = TNumericLimits<double>::Max();
	for (const FOKSceneObject& O : Document->Objects)
	{
		if (!Document->IsShown(O.Id) || O.Kind == EOKSceneObjectKind::Folder || O.bLocked) continue;
		double Depth = -1.;
		if (O.Kind == EOKSceneObjectKind::Character)
		{
			// The stick figure of the skeleton, 14 px thick.
			TArray<TPair<FVector, FVector>> Segments;
			if (!SkeletonSegments(SceneActor->PreviewOf(O.Id), Segments)) continue;
			for (const TPair<FVector, FVector>& S : Segments)
			{
				FVector2D A, B;
				if (!Project(S.Key, A) || !Project(S.Value, B)) continue;
				if (PointSegment(Position, A, B) < 14.) { const double D = FVector::Distance(Eye, (S.Key + S.Value) * 0.5); Depth = Depth < 0. ? D : FMath::Min(Depth, D); }
			}
		}
		else if (O.Kind == EOKSceneObjectKind::Light || O.Kind == EOKSceneObjectKind::Camera)
		{
			const FVector At = (Document->WorldTransform(O.Id) * SceneActor->GetActorTransform()).GetLocation();
			FVector2D S;
			if (Project(At, S) && FVector2D::Distance(S, Position) < 12.) Depth = FVector::Distance(Eye, At);
		}
		else
		{
			FBox Box;
			if (!WorldBounds(O.Id, Box)) continue;
			FBox2D Screen(ForceInit);
			int32 Seen = 0;
			for (int32 C = 0; C < 8; ++C)
			{
				const FVector Corner((C & 1) ? Box.Max.X : Box.Min.X, (C & 2) ? Box.Max.Y : Box.Min.Y, (C & 4) ? Box.Max.Z : Box.Min.Z);
				FVector2D S;
				if (Project(Corner, S)) { Screen += S; ++Seen; }
			}
			if (Seen && Screen.IsInside(Position)) Depth = FVector::Distance(Eye, Box.GetCenter());
		}
		if (Depth >= 0. && Depth < BestDepth) { BestDepth = Depth; Best = O.Id; }
	}
	return Best;
}

float OKStudioGameInternal::ComputeFocusSelectionDistance(const FBox& Bounds, const FRotator& ViewRotation, float HorizontalFovDegrees, float AspectRatio)
{
	if (!Bounds.IsValid) return 380.f;
	const float Aspect = (FMath::IsFinite(AspectRatio) && AspectRatio > 0.f)
		? FMath::Clamp(AspectRatio, 0.1f, 10.f)
		: (16.f / 9.f);
	const float HFov = (FMath::IsFinite(HorizontalFovDegrees) && HorizontalFovDegrees > 0.f)
		? FMath::Clamp(HorizontalFovDegrees, 5.f, 170.f)
		: 40.f;
	const float TanHalfH = FMath::Max(FMath::Tan(FMath::DegreesToRadians(HFov * 0.5f)), 0.05f);
	const float TanHalfV = FMath::Max(TanHalfH / Aspect, 0.05f);
	const FRotationMatrix Basis(FRotator(ViewRotation.Pitch, ViewRotation.Yaw, 0.f));
	const FVector Forward = Basis.GetUnitAxis(EAxis::X);
	const FVector Right = Basis.GetUnitAxis(EAxis::Y);
	const FVector Up = Basis.GetUnitAxis(EAxis::Z);
	const FVector Center = Bounds.GetCenter();
	FVector Corners[8];
	Bounds.GetVertices(Corners);
	constexpr double Margin = 1.08;
	double Needed = 20.0;
	for (const FVector& Corner : Corners)
	{
		const FVector Delta = Corner - Center;
		const double DepthOffset = FVector::DotProduct(Delta, Forward);
		const double HalfSpanH = (FMath::Abs(FVector::DotProduct(Delta, Right)) * Margin) / double(TanHalfH);
		const double HalfSpanV = (FMath::Abs(FVector::DotProduct(Delta, Up)) * Margin) / double(TanHalfV);
		Needed = FMath::Max(Needed, FMath::Max3(HalfSpanH, HalfSpanV, 1.0) - DepthOffset);
	}
	return FMath::Clamp(float(Needed), 20.f, 5000.f);
}

void UOKStudioGame::FocusSelection(bool bFace)
{
	// Frames Target in the part of the view the panels leave open (U123: the left windows, the right panels and the
	// timeline hid half of what was framed at the middle). The distance fits the box of half size Extent around Target
	// there, by its width and height as the view sees them (a bounding sphere left a T-posed figure small in a narrow gap).
	auto Frame = [this](const FVector& Target, const FVector& Extent)
	{
		FVector2D Size(16.0, 9.0);
		if (GEngine && GEngine->GameViewport) GEngine->GameViewport->GetViewportSize(Size);
		const float Aspect = Size.Y > 1.0 ? float(Size.X / Size.Y) : 16.f / 9.f;
		FBox2D Clear = ClearView;
		if (!Clear.bIsValid || Clear.GetSize().X < 0.2 || Clear.GetSize().Y < 0.2) Clear = FBox2D(FVector2D(0.f, 0.f), FVector2D(1.f, 1.f));
		const float TanX = FMath::Tan(FMath::DegreesToRadians(FMath::Clamp(Document->FreeView.Fov, 5.f, 170.f) * 0.5f)), TanY = TanX / Aspect;
		const FRotationMatrix M(FRotator(Pitch, Yaw, 0.f));
		auto Across = [&Extent](const FVector& Axis) { return float(FMath::Abs(Axis.X) * Extent.X + FMath::Abs(Axis.Y) * Extent.Y + FMath::Abs(Axis.Z) * Extent.Z); };
		const float HalfW = Across(M.GetScaledAxis(EAxis::Y)) * 1.1f, HalfH = Across(M.GetScaledAxis(EAxis::Z)) * 1.1f, Deep = Across(M.GetScaledAxis(EAxis::X));
		const float W = float(Clear.GetSize().X), H = float(Clear.GetSize().Y);
		Distance = FMath::Clamp(FMath::Max(HalfW / (TanX * W), HalfH / (TanY * H)) + Deep, 20.f, 5000.f);
		if (Document->FreeView.bOrtho) Document->FreeView.OrthoWidth = FMath::Max(HalfW / W, HalfH * Aspect / H) * 2.f;
		// Move the orbit centre so the target shows at the open area's centre.
		const FVector2D Off((Clear.GetCenter().X - 0.5) * 2.0, (0.5 - Clear.GetCenter().Y) * 2.0);
		const float HalfX = Document->FreeView.bOrtho ? Document->FreeView.OrthoWidth * 0.5f : Distance * TanX;
		const float HalfY = Document->FreeView.bOrtho ? HalfX / Aspect : Distance * TanY;
		Focus = Target - M.GetScaledAxis(EAxis::Y) * float(Off.X) * HalfX - M.GetScaledAxis(EAxis::Z) * float(Off.Y) * HalfY;
		FramedFocus = Focus; FramedDistance = Distance; FramedYaw = Yaw; FramedPitch = Pitch;
	};
	bFramedFace = bFace;
	const FOKSceneObject* One = Selection.Num() == 1 ? Document->Find(Selection[0]) : nullptr;
	FTransform Head;
	const AKKPreviewActor* Shown = One && SceneActor ? SceneActor->PreviewOf(One->Id) : nullptr;
	if (bFace && One && One->Kind == EOKSceneObjectKind::Character && OKStudioGameInternal::BoneWorld(Shown, TEXT("cf_j_head"), Head))
	{
		// Where the face looks now (U119: a kneeling or turned character was framed at the neck, from behind her partner):
		// the head's turn from its rest pose applied to the character's front (+Y at yaw 0) and up. The view comes from 40°
		// to the side of the face, so a partner right in front of it does not fill the view.
		const float Yaw0 = float(Document->WorldTransform(One->Id).Rotator().Yaw);
		FVector Front = FRotator(0.f, Yaw0 + 90.f, 0.f).Vector(), Up = FVector::UpVector;
		UPoseableMeshComponent* Mesh = Shown->BodySkel ? Shown->BodySkel.Get() : (Shown->SkelFollowers.Num() ? Shown->SkelFollowers[0].Get() : nullptr);
		const int32 Bone = Mesh && Mesh->GetSkinnedAsset() ? Mesh->GetBoneIndex(TEXT("cf_j_head")) : INDEX_NONE;
		if (Bone != INDEX_NONE)
		{
			const FQuat Rest = Mesh->GetComponentQuat() * FAnimationRuntime::GetComponentSpaceTransformRefPose(Mesh->GetSkinnedAsset()->GetRefSkeleton(), Bone).GetRotation();
			const FQuat Turn = Head.GetRotation() * Rest.Inverse();
			Front = Turn.RotateVector(Front);
			Up = Turn.RotateVector(Up);
		}
		// The head bone sits at the top of the neck: the face is a hand above it and a little forward.
		const FRotator Look = (-Front).Rotation();
		Yaw = float(Look.Yaw) + 40.f;
		Pitch = FMath::Clamp(float(Look.Pitch), -45.f, 30.f);
		Frame(Head.GetLocation() + Up * 8.f + Front * 3.f, FVector(12.f));
		Document->ActiveCamera = -1;
		return;
	}
	FBox All(ForceInit);
	for (int32 Id : Selection) { FBox B; if (WorldBounds(Id, B)) All += B; }
	if (!All.IsValid || !SceneActor) return;
	// Back into the scene's own frame (the orbit focus is in world space, the scene actor sits at the origin).
	Frame(All.GetCenter(), All.GetExtent().ComponentMax(FVector(5.f)));
	Document->ActiveCamera = -1;
}

bool UOKStudioGame::ViewStillFramed() const
{
	return Document->ActiveCamera < 0 && !Selection.IsEmpty() && FramedDistance > 0.f && Focus.Equals(FramedFocus, 0.01) && FMath::IsNearlyEqual(Distance, FramedDistance, 0.01f)
		&& FMath::IsNearlyEqual(Yaw, FramedYaw, 0.01f) && FMath::IsNearlyEqual(Pitch, FramedPitch, 0.01f);
}

bool UOKStudioGame::KeepInOpenView(int32 Id, const FBox2D& Covered)
{
	APlayerController* PC = SceneActor && SceneActor->GetWorld() ? SceneActor->GetWorld()->GetFirstPlayerController() : nullptr;
	if (!PC || !PC->PlayerCameraManager || !Document || Document->ActiveCamera >= 0 || !Document->Find(Id)) return false;
	FVector2D Size(16.0, 9.0);
	if (GEngine && GEngine->GameViewport) GEngine->GameViewport->GetViewportSize(Size);
	const FBox2D Clear = ClearView;
	if (!Clear.bIsValid || Clear.GetSize().X < 0.2 || Clear.GetSize().Y < 0.2 || Size.X < 1. || Size.Y < 1.) return false;
	const FVector At = (Document->WorldTransform(Id) * SceneActor->GetActorTransform()).GetLocation();
	FVector2D Pixel;
	if (!PC->ProjectWorldLocationToScreen(At, Pixel)) return false;
	const FVector2D Now(Pixel.X / Size.X, Pixel.Y / Size.Y);
	if (!Covered.IsInside(Now)) return false;
	// As far as it takes: into the open part, a tenth of it from the edge.
	const FVector2D Margin = Clear.GetSize() * 0.1;
	const FVector2D Want(FMath::Clamp(Now.X, Clear.Min.X + Margin.X, Clear.Max.X - Margin.X), FMath::Clamp(Now.Y, Clear.Min.Y + Margin.Y, Clear.Max.Y - Margin.Y));
	const FRotationMatrix M(FRotator(Pitch, Yaw, 0.f));
	const float Depth = float(FVector::DotProduct(At - PC->PlayerCameraManager->GetCameraLocation(), M.GetScaledAxis(EAxis::X)));
	if (Depth <= 1.f) return false;
	const float Aspect = float(Size.X / Size.Y);
	const float TanX = FMath::Tan(FMath::DegreesToRadians(FMath::Clamp(Document->FreeView.Fov, 5.f, 170.f) * 0.5f));
	const float HalfX = Document->FreeView.bOrtho ? Document->FreeView.OrthoWidth * 0.5f : Depth * TanX;
	const float HalfY = HalfX / Aspect;
	Focus += M.GetScaledAxis(EAxis::Y) * float(Now.X - Want.X) * 2.f * HalfX - M.GetScaledAxis(EAxis::Z) * float(Now.Y - Want.Y) * 2.f * HalfY;
	return true;
}

void UOKStudioGame::FindChairs(TArray<FBox>& Out, TArray<int32>* OutItems) const
{
	if (!SceneActor || !Document) return;
	TArray<FBox> Boxes;
	SceneActor->MapPartBounds(Boxes);
	TArray<int32> Items;
	Items.Init(-1, Boxes.Num());
	for (const FOKSceneObject& O : Document->Objects)
	{
		FBox B;
		if (O.Kind == EOKSceneObjectKind::Item && Document->IsShown(O.Id) && WorldBounds(O.Id, B)) { Boxes.Add(B); Items.Add(O.Id); }
	}
	for (int32 I = 0; I < Boxes.Num(); ++I)
	{
		const FVector S = Boxes[I].GetSize();
		if (FMath::Min(S.X, S.Y) < 30. || FMath::Max(S.X, S.Y) > 65. || S.Z < 55. || S.Z > 115.) continue;
		Out.Add(Boxes[I]);
		if (OutItems) OutItems->Add(Items[I]);
	}
}

bool UOKStudioGame::ChairAt(const FVector2D& Position, FBox& Out, int32* OutItem) const
{
	APlayerController* PC = SceneActor && SceneActor->GetWorld() ? SceneActor->GetWorld()->GetFirstPlayerController() : nullptr;
	if (!PC || !PC->PlayerCameraManager) return false;
	const FVector Eye = PC->PlayerCameraManager->GetCameraLocation();
	TArray<FBox> Chairs;
	TArray<int32> Items;
	FindChairs(Chairs, &Items);
	double Best = TNumericLimits<double>::Max();
	for (int32 I = 0; I < Chairs.Num(); ++I)
	{
		const FBox& Box = Chairs[I];
		FBox2D Screen(ForceInit);
		for (int32 C = 0; C < 8; ++C)
		{
			const FVector Corner((C & 1) ? Box.Max.X : Box.Min.X, (C & 2) ? Box.Max.Y : Box.Min.Y, (C & 4) ? Box.Max.Z : Box.Min.Z);
			FVector2D S;
			if (UWidgetLayoutLibrary::ProjectWorldLocationToWidgetPosition(PC, Corner, S, true)) Screen += S;
		}
		const double Depth = FVector::Distance(Eye, Box.GetCenter());
		if (Screen.bIsValid && Screen.IsInside(Position) && Depth < Best) { Best = Depth; Out = Box; if (OutItem) *OutItem = Items[I]; }
	}
	return Best < TNumericLimits<double>::Max();
}

/** The desk or table a chair belongs to: the nearest box of that size, up to 90 cm off. */
static bool OKDeskBy(const TArray<FBox>& Boxes, const FBox& Chair, FBox& Out)
{
	double Nearest = 90.;
	for (const FBox& B : Boxes)
	{
		const FVector S = B.GetSize();
		const FVector Off = B.GetCenter() - Chair.GetCenter();
		const double Reach = FVector2D(Off.X, Off.Y).Size();
		if (FMath::Min(S.X, S.Y) >= 40. && FMath::Max(S.X, S.Y) >= 66. && FMath::Max(S.X, S.Y) <= 220. && S.Z >= 50. && S.Z <= 110. && Reach > 3. && Reach < Nearest) { Nearest = Reach; Out = B; }
	}
	return Nearest < 90.;
}

bool UOKStudioGame::SeatAt(int32 Id, const FBox& Chair, int32 Item)
{
	FOKSceneObject* O = Document ? Document->Find(Id) : nullptr;
	if (!O || O->Kind != EOKSceneObjectKind::Character || O->bLocked) return false;
	FTransform World = Document->WorldTransform(Id);
	const FVector Seat(Chair.GetCenter().X, Chair.GetCenter().Y, Chair.Min.Z);
	World.SetLocation(Seat);
	// A chair item looks where it is turned, front +Y as a character's. The bounds of a map's do not say; the desk beside it
	// does (a classroom's chairs stand half under theirs).
	TArray<FBox> Boxes;
	SceneActor->MapPartBounds(Boxes);
	FBox Desk;
	if (Document->Find(Item)) World.SetRotation(FRotator(0., Document->WorldTransform(Item).Rotator().Yaw, 0.).Quaternion());
	else if (OKDeskBy(Boxes, Chair, Desk))
	{
		const FVector Off = Desk.GetCenter() - Chair.GetCenter();
		World.SetRotation(FRotator(0., FMath::RadiansToDegrees(FMath::Atan2(Off.Y, Off.X)) - 90., 0.).Quaternion());
	}
	O->Transform = O->Parent >= 0 ? World.GetRelativeTransform(Document->WorldTransform(O->Parent)) : World;
	return true;
}

bool UOKStudioGame::HipsOver(int32 Id, const FBox& Chair)
{
	FOKSceneObject* O = Document ? Document->Find(Id) : nullptr;
	FTransform Hips;
	if (!O || !SceneActor || !OKStudioGameInternal::BoneWorld(SceneActor->PreviewOf(Id), TEXT("cf_j_hips"), Hips)) return false;
	FTransform World = Document->WorldTransform(Id);
	FVector Seat = Chair.GetCenter();
	// A classroom's chairs stand pushed in, the seat under the desk: on it she sat through the desk top. The map's chair cannot
	// be pulled out, so she sits where it would be, a body's depth behind the desk's edge.
	TArray<FBox> Boxes;
	SceneActor->MapPartBounds(Boxes);
	FBox Desk;
	if (OKDeskBy(Boxes, Chair, Desk) && Desk.Intersect(Chair))
	{
		const FVector Front = FRotator(0., World.Rotator().Yaw + 90., 0.).Vector();
		const FVector Half = Desk.GetExtent();
		const double Edge = FVector::DotProduct(Desk.GetCenter() - Chair.GetCenter(), Front) - FMath::Abs(Front.X) * Half.X - FMath::Abs(Front.Y) * Half.Y;
		if (Edge < 14.) Seat += Front * (Edge - 14.);
	}
	World.AddToTranslation(FVector(Seat.X - Hips.GetLocation().X, Seat.Y - Hips.GetLocation().Y, 0.));
	O->Transform = O->Parent >= 0 ? World.GetRelativeTransform(Document->WorldTransform(O->Parent)) : World;
	return true;
}

int32 UOKStudioGame::DropOnSurface()
{
	if (!SceneActor || !Document) return 0;
	TArray<FBox> Surfaces;
	SceneActor->MapPartBounds(Surfaces);
	for (const FOKSceneObject& O : Document->Objects)
	{
		FBox B;
		if (O.Kind == EOKSceneObjectKind::Item && !Selection.Contains(O.Id) && Document->IsShown(O.Id) && WorldBounds(O.Id, B)) Surfaces.Add(B);
	}
	APlayerController* PC = SceneActor->GetWorld() ? SceneActor->GetWorld()->GetFirstPlayerController() : nullptr;
	const FVector Eye = PC && PC->PlayerCameraManager ? PC->PlayerCameraManager->GetCameraLocation() : FVector::ZeroVector;
	int32 Moved = 0;
	for (const int32 Id : Selection)
	{
		FOKSceneObject* O = Document->Find(Id);
		FBox Box;
		if (!O || O->bLocked || !O->AttachBone.IsEmpty() || (O->Kind != EOKSceneObjectKind::Item && O->Kind != EOKSceneObjectKind::Character) || !WorldBounds(Id, Box)) continue;
		// The first top the line of sight through its foot meets: where it looks to be. Straight below it was not: at 82 cm over
		// the aisle a book looked to lie on the desk behind and fell to the floor (U262). A view from level or below looks down nowhere.
		const FVector Foot(Box.GetCenter().X, Box.GetCenter().Y, Box.Min.Z);
		const FVector Sight = (Foot - Eye).GetSafeNormal();
		const FVector Down = Sight.Z < -0.05 ? Sight : FVector(0., 0., -1.);
		const FVector From = Sight.Z < -0.05 ? Eye : Foot + FVector(0., 0., 30.);
		double Nearest = UE_BIG_NUMBER;
		for (const FBox& S : Surfaces)
		{
			const double T = (S.Max.Z - From.Z) / Down.Z;
			const FVector Hit = From + Down * T;
			if (T > 0. && T < Nearest && Hit.X >= S.Min.X && Hit.X <= S.Max.X && Hit.Y >= S.Min.Y && Hit.Y <= S.Max.Y) Nearest = T;
		}
		if (Nearest >= UE_BIG_NUMBER) continue;
		const FVector Move = From + Down * Nearest - Foot;
		if (Move.IsNearlyZero(0.01)) continue;
		FTransform World = Document->WorldTransform(Id);
		World.AddToTranslation(Move);
		O->Transform = O->Parent >= 0 ? World.GetRelativeTransform(Document->WorldTransform(O->Parent)) : World;
		++Moved;
	}
	return Moved;
}

void UOKStudioGame::FrameFirstCharacter(int32 Id)
{
	// The initial view shows 156 cm at the character's distance: head and feet were cut. Its bounds come only once the
	// card has built, so this is a standing person's size, not FocusSelection.
	const bool bStartView = (Distance == InitialDistance && Focus.Equals(InitialFocus)) || (Distance == StartDistance && Focus.Equals(StartFocus));
	if (Document->ActiveCamera >= 0 || !bStartView) return;
	Focus = Document->WorldTransform(Id).GetLocation() + FVector(0.f, 0.f, 82.f);
	Distance = 480.f;
}

void UOKStudioGame::ViewPreset(int32 Preset)
{
	Document->ActiveCamera = -1;
	switch (Preset)
	{
	case 0: Yaw = -90.f; Pitch = 0.f; break;
	case 1: Yaw = 180.f; Pitch = 0.f; break;
	case 2: Pitch = -89.f; break;
	case 3: Yaw = 90.f; Pitch = 0.f; break;
	case 4: Yaw = 0.f; Pitch = 0.f; break;
	default: Focus = InitialFocus; Yaw = InitialYaw; Pitch = InitialPitch; Distance = InitialDistance; break;
	}
}

void UOKStudioGame::SaveBookmark(int32 Slot)
{
	if (Slot < 0 || Slot > 9) return;
	while (Document->Bookmarks.Num() <= Slot) Document->Bookmarks.AddDefaulted();
	FOKSceneBookmark& B = Document->Bookmarks[Slot];
	B.bSet = true; B.Focus = Focus; B.Yaw = Yaw; B.Pitch = Pitch; B.Distance = Distance; B.Camera = Document->ActiveCamera;
	Document->NotifyChanged();
}

bool UOKStudioGame::LoadBookmark(int32 Slot)
{
	if (!Document->Bookmarks.IsValidIndex(Slot) || !Document->Bookmarks[Slot].bSet) return false;
	const FOKSceneBookmark& B = Document->Bookmarks[Slot];
	Focus = B.Focus; Yaw = B.Yaw; Pitch = B.Pitch; Distance = B.Distance;
	Document->ActiveCamera = Document->Find(B.Camera) ? B.Camera : -1;
	return true;
}

int32 UOKStudioGame::CameraFromView()
{
	const int32 Id = Add(EOKSceneObjectKind::Camera);
	StoreViewInCamera(Id);
	return Id;
}

bool UOKStudioGame::StoreViewInCamera(int32 Id)
{
	FOKSceneObject* O = Document->Find(Id);
	if (!O || O->Kind != EOKSceneObjectKind::Camera || !Viewer) return false;
	UpdateViewer();
	const FTransform World = Viewer->GetActorTransform();
	const FTransform Parent = Document->ParentFrame(Id) * (SceneActor ? SceneActor->GetActorTransform() : FTransform::Identity);
	O->Transform = World.GetRelativeTransform(Parent);
	O->Transform.SetScale3D(FVector::OneVector);
	// From the free view the camera takes its whole lens (near / far / orthographic too).
	if (Document->ActiveCamera < 0) O->Camera = Document->FreeView;
	O->Camera.Fov = Viewer->GetCameraComponent()->FieldOfView;
	Document->NotifyChanged();
	return true;
}

void UOKStudioGame::NextCamera()
{
	TArray<int32> Cameras;
	for (const FOKSceneObject& O : Document->Objects) if (O.Kind == EOKSceneObjectKind::Camera) Cameras.Add(O.Id);
	const int32 At = Cameras.IndexOfByKey(Document->ActiveCamera);
	Document->ActiveCamera = Cameras.IsValidIndex(At + 1) ? Cameras[At + 1] : -1;
}

FString UOKStudioGame::BusyReason() const
{
	if (IsExporting()) return TEXT("exporting");
	if (bTimelinePlaying) return TEXT("playing");
	if (DragAxis >= 0 || bUserDragging) return TEXT("dragging");
	if (SceneActor && (SceneActor->HasPendingBuilds() || SceneActor->PreparingMap() >= 0)) return TEXT("loading");
	if (bStoryMode) return TEXT("story");
	return FString();
}

FString UOKStudioGame::BackupDirectory()
{
	return FOKStudioSettings::Directory() / TEXT("Backup");
}

TArray<FString> UOKStudioGame::BackupFiles()
{
	TArray<FString> Names;
	IFileManager::Get().FindFiles(Names, *(BackupDirectory() / TEXT("*.okscene")), true, false);
	TArray<FString> Files;
	for (const FString& N : Names) Files.Add(BackupDirectory() / N);
	Files.Sort([](const FString& A, const FString& B) { return A > B; });
	return Files;
}

FString UOKStudioGame::BackupNow(bool bForce)
{
	LastBackupSeconds = FPlatformTime::Seconds();
	if (!Document) return FString();
	const FString Json = Document->ToJson();
	const uint32 Hash = GetTypeHash(Json);
	if (!bForce && Hash == LastBackupHash) return FString();
	LastBackupHash = Hash;
	const FString Base = BackupDirectory() / FDateTime::Now().ToString(TEXT("backup_%Y%m%d_%H%M%S"));
	IFileManager::Get().MakeDirectory(*BackupDirectory(), true);
	FString Error;
	if (!Document->SaveToFile(Base + TEXT(".okscene"), Error)) { UE_LOG(LogTemp, Warning, TEXT("OK studio backup: %s"), *Error); return FString(); }
	// A small picture of the view for the restore window.
	CaptureToPng(Base + TEXT(".png"), 256, 144, Error);
	TArray<FString> Files = BackupFiles();
	const int32 Keep = FMath::Max(1, FOKStudioSettings::Get().BackupKeep);
	for (int32 I = Keep; I < Files.Num(); ++I)
	{
		IFileManager::Get().Delete(*Files[I], false, true, true);
		IFileManager::Get().Delete(*FPaths::ChangeExtension(Files[I], TEXT("png")), false, true, true);
	}
	UE_LOG(LogTemp, Display, TEXT("OK studio: backup %s.okscene"), *Base);
	return Base + TEXT(".okscene");
}

TArray<FString> UOKStudioGame::LoadReport() const
{
	TArray<FString> Lines;
	if (!SceneActor || !Document) return Lines;
	for (const TPair<int32, FString>& E : SceneActor->Errors)
	{
		const FOKSceneObject* O = Document->Find(E.Key);
		Lines.Add(FString::Printf(TEXT("#%d %s：%s"), E.Key, O ? *O->Name : TEXT("?"), *E.Value));
	}
	if (!SceneActor->MapError.IsEmpty()) Lines.Add(TEXT("地圖：") + SceneActor->MapError);
	return Lines;
}
