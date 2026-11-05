#include "OKStudioImport.h"
#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "KKCardReader.h"
#include "KKRustExtract.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "OKSceneDocument.h"
#include "OKStudioCatalog.h"
#include "OKSceneActor.h"
#include "OKStudioGame.h"
#include "OKStudioPose.h"
#include "OKStudioImportSettings.h"
#include "OKStudioPost.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "ok_extract.h"

namespace
{
	/** Studio cameras look along Unity Z, ours along X. */
	FQuat MmddCamTurn() { return FQuat(FVector::UpVector, UE_HALF_PI); }

	FVector Vec3(const TSharedPtr<FJsonObject>& O, const TCHAR* Key, const FVector& Default = FVector::ZeroVector)
	{
		const TArray<TSharedPtr<FJsonValue>>* A = nullptr;
		if (!O->TryGetArrayField(Key, A) || A->Num() != 3) return Default;
		return FVector((*A)[0]->AsNumber(), (*A)[1]->AsNumber(), (*A)[2]->AsNumber());
	}
	FLinearColor Color(const TSharedPtr<FJsonObject>& O)
	{
		return O ? FLinearColor(O->GetNumberField(TEXT("r")), O->GetNumberField(TEXT("g")), O->GetNumberField(TEXT("b")), O->GetNumberField(TEXT("a"))) : FLinearColor::White;
	}

	/** Matches jim60105's StudioCharaLightLinkedToCamera.ComputeAngle for Directional Chara localEuler = (40, 180) (sign = -1). */
	FVector ComputeLinkedCharaLightEuler(const FVector2D& PreLig, const FVector2D& PreCam, const FVector2D& CamEuler)
	{
		auto Wrap180 = [](double Deg) -> double
		{
			if (Deg < -180.0 || Deg > 180.0)
				Deg = Deg <= 0.0 ? FMath::Fmod(Deg - 180.0, 360.0) + 180.0 : FMath::Fmod(Deg + 180.0, 360.0) - 180.0;
			return Deg;
		};
		auto Wrap90 = [](double Deg) -> double
		{
			if (Deg < -90.0 || Deg > 90.0)
				Deg = Deg <= 0.0 ? FMath::Fmod(Deg - 90.0, 180.0) + 90.0 : FMath::Fmod(Deg + 90.0, 180.0) - 90.0;
			return Deg;
		};
		auto Fix360 = [](double Deg) -> double
		{
			Deg = FMath::Fmod(Deg, 360.0);
			return Deg < 0.0 ? Deg + 360.0 : Deg;
		};

		const double Dx = CamEuler.X - PreCam.X;
		const double Dy = CamEuler.Y - PreCam.Y;
		if (FMath::IsNearlyZero(Dx, 1e-6) && FMath::IsNearlyZero(Dy, 1e-6))
			return FVector(PreLig.X, PreLig.Y, 0.0);

		const double Alpha = Wrap180(PreLig.Y + 180.0 - PreCam.Y);
		const double Beta = Wrap90(40.0 - PreLig.X);
		int32 Situ = 0;
		if (FMath::IsNearlyZero(Alpha, 1e-4)) Situ = 1;
		else if (FMath::IsNearlyEqual(FMath::Abs(Alpha), 180.0, 1e-4)) Situ = 2;
		else if (FMath::IsNearlyEqual(FMath::Abs(Beta), 90.0, 1e-4)) Situ = 3;

		if (Situ != 0)
		{
			double OffX = Dx, OffY = Dy;
			if (Situ == 2)
			{
				OffX = -Dx;
			}
			else if (Situ == 3)
			{
				if (Alpha > 90.0) { OffX = -Dx; OffY = Dy + 180.0 - Alpha; }
				else if (Alpha < -90.0) { OffX = -Dx; OffY = Dy - 180.0 - Alpha; }
				else { OffX = Dx; OffY = Dy - Alpha; }
			}
			return FVector(Fix360(PreLig.X - OffX), Fix360(PreLig.Y + OffY), 0.0);
		}

		const double AlphaR = FMath::DegreesToRadians(Alpha);
		const double BetaR = FMath::DegreesToRadians(Beta);
		const double SinAlphaCosBeta = FMath::Sin(AlphaR) * FMath::Cos(BetaR);
		double CosR = FMath::Sqrt(FMath::Max(0.0, 1.0 - SinAlphaCosBeta * SinAlphaCosBeta));
		if (Alpha < -90.0 || Alpha > 90.0) CosR = -CosR;
		const double SinAgls = FMath::IsNearlyZero(CosR, 1e-12) ? 0.0 : FMath::Clamp(FMath::Sin(BetaR) / CosR, -1.0, 1.0);
		const double NextAgls = FMath::Asin(SinAgls) + FMath::DegreesToRadians(Dx);
		const double NewBetaR = FMath::Asin(FMath::Clamp(FMath::Sin(NextAgls) * CosR, -1.0, 1.0));
		const double CosNewBeta = FMath::Cos(NewBetaR);
		const double CosNewAlpha = FMath::IsNearlyZero(CosNewBeta, 1e-12)
			? 1.0 : FMath::Clamp(FMath::Cos(NextAgls) * CosR / CosNewBeta, -1.0, 1.0);
		double NewAlphaR = FMath::Acos(CosNewAlpha);
		if (Alpha < 0.0) NewAlphaR = -NewAlphaR;
		const double DeltaBeta = FMath::RadiansToDegrees(NewBetaR) - Beta;
		const double DeltaYaw = Dy + FMath::RadiansToDegrees(NewAlphaR) - Alpha;
		return FVector(Fix360(PreLig.X - DeltaBeta), Fix360(PreLig.Y + DeltaYaw), 0.0);
	}

	struct FImporter
	{
		UOKSceneDocument* Doc = nullptr;
		FString CardDirectory;
		FOKStudioImport::FReport* Report = nullptr;
		TMap<FString, int32> Notes;
		/** Material Editor's scene data: material edits by object key. */
		TMap<int32, TArray<FOKSceneMaterialEdit>> MaterialEdits;
		/** Maps Studio dicKey ("key") to UOKSceneDocument ObjectId. */
		TMap<int32, int32> KeyToId;

		void Note(const FString& What) { ++Notes.FindOrAdd(What); }

		FTransform Transform(const TSharedPtr<FJsonObject>& O)
		{
			const TSharedPtr<FJsonObject>* Change = nullptr;
			if (!O->TryGetObjectField(TEXT("change"), Change)) return FTransform::Identity;
			return FOKStudioImport::UnityToUe(Vec3(*Change, TEXT("pos")), Vec3(*Change, TEXT("rot")), Vec3(*Change, TEXT("scale"), FVector::OneVector));
		}

		/** Accessory point bone the next added object hangs on (characters' slot children). */
		FString PendingAttach;

		int32 Add(EOKSceneObjectKind Kind, const FString& Name, int32 Parent, const TSharedPtr<FJsonObject>& O)
		{
			const int32 Id = Doc->AddObject(Kind, Name, Parent);
			FOKSceneObject* X = Doc->Find(Id);
			X->Transform = Transform(O);
			X->AttachBone = MoveTemp(PendingAttach);
			PendingAttach.Reset();
			bool bVisible = true;
			if (O->TryGetBoolField(TEXT("visible"), bVisible)) X->bVisible = bVisible;
			int32 ObjKey = -1;
			if (O->TryGetNumberField(TEXT("key"), ObjKey) && ObjKey >= 0) KeyToId.Add(ObjKey, Id);
			return Id;
		}

		/** StudioTween.EaseType as the nearest timeline curve. */
		static EOKSceneEase Ease(int32 Type)
		{
			if (Type == 21) return EOKSceneEase::Linear;
			if (Type == 22) return EOKSceneEase::EaseOut; // spring
			const int32 Kind = Type < 21 ? Type % 3 : (Type - 23) % 3;
			return Kind == 0 ? EOKSceneEase::EaseIn : Kind == 1 ? EOKSceneEase::EaseOut : EOKSceneEase::EaseInOut;
		}

		/** A route's start point folder and its timeline track (OCIRoute.Play): the path runs through the points (and a
		 *  curve's aid point) at each point's speed, back to the start when the route loops, turned along the path
		 *  with Orient. Returns the folder (-1: no points). */
		int32 Route(const TSharedPtr<FJsonObject>& O, int32 RouteId)
		{
			const TArray<TSharedPtr<FJsonValue>>* Points = nullptr;
			if (!O->TryGetArrayField(TEXT("points"), Points) || Points->IsEmpty()) return -1;
			struct FPoint { FTransform Transform; float Speed = 2.f; int32 Ease = 21; bool bCurve = false; bool bAid = false; FVector Aid = FVector::ZeroVector; };
			TArray<FPoint> P;
			for (const TSharedPtr<FJsonValue>& V : *Points)
			{
				const TSharedPtr<FJsonObject> J = V->AsObject();
				if (!J) continue;
				FPoint Point;
				Point.Transform = Transform(J);
				Point.Transform.SetScale3D(FVector::OneVector);
				Point.Speed = FMath::Max(float(J->GetNumberField(TEXT("speed"))), 0.01f);
				Point.Ease = int32(J->GetNumberField(TEXT("ease")));
				Point.bCurve = J->GetBoolField(TEXT("curve"));
				const TSharedPtr<FJsonObject>* Aid = nullptr;
				if (J->TryGetObjectField(TEXT("aid"), Aid))
				{
					Point.bAid = true;
					Point.Aid = Point.Transform.TransformPosition(FOKStudioImport::UnityToUe(Vec3(*Aid, TEXT("pos")), FVector::ZeroVector, FVector::OneVector).GetLocation());
				}
				P.Add(Point);
			}
			if (P.IsEmpty()) return -1;
			const int32 Rider = Doc->AddObject(EOKSceneObjectKind::Folder, Doc->Find(RouteId)->Name + TEXT(" (start)"), RouteId);
			Doc->Find(Rider)->Transform = P[0].Transform;
			if (P.Num() < 2) return Rider;
			bool bLoop = true;
			O->TryGetBoolField(TEXT("looped"), bLoop);
			int32 Orient = 0;
			O->TryGetNumberField(TEXT("orient"), Orient);
			// Path points with the speed and curve of the segment they start.
			struct FStop { FVector Position; float Speed; EOKSceneEase Ease; };
			TArray<FStop> Stops;
			bool bSmooth = false;
			const int32 Segments = bLoop ? P.Num() : P.Num() - 1;
			for (int32 I = 0; I < Segments; ++I)
			{
				const FPoint& A = P[I];
				const FVector Next = P[(I + 1) % P.Num()].Transform.GetLocation();
				Stops.Add({ A.Transform.GetLocation(), A.Speed, Ease(A.Ease) });
				if (A.bCurve)
				{
					bSmooth = true;
					Stops.Add({ A.bAid ? A.Aid : (A.Transform.GetLocation() + Next) * 0.5, A.Speed, Ease(A.Ease) });
				}
			}
			Stops.Add({ bLoop ? P[0].Transform.GetLocation() : P.Last().Transform.GetLocation(), 0.f, EOKSceneEase::Linear });
			FOKSceneTrack Track;
			Track.ObjectId = Rider;
			Track.bSmoothPath = bSmooth;
			float Time = 0.f;
			for (int32 I = 0; I < Stops.Num(); ++I)
			{
				FOKSceneKey Key;
				Key.Time = Time;
				Key.Ease = Stops[I].Ease;
				FQuat Rotation = P[0].Transform.GetRotation();
				if (Orient != 0)
				{
					// Turned along the path: towards the next stop (the last one keeps the previous heading).
					FVector Dir = I + 1 < Stops.Num() ? Stops[I + 1].Position - Stops[I].Position : Stops[I].Position - Stops[FMath::Max(I - 1, 0)].Position;
					if (Orient == 2) Dir.Z = 0.f;
					// Unity's LookRotation: forward (+Z, Unreal +Y) along the path, up (+Y, Unreal +Z) kept up.
					if (!Dir.IsNearlyZero()) Rotation = FRotationMatrix::MakeFromYZ(Dir, FVector::UpVector).ToQuat();
				}
				Key.Transform = FTransform(Rotation, Stops[I].Position);
				Track.Keys.Add(Key);
				// iTween speed: Unity units (m) per second.
				if (I + 1 < Stops.Num()) Time += float(FVector::Dist(Stops[I].Position, Stops[I + 1].Position) / 100.0) / Stops[I].Speed;
			}
			if (Time > 0.f)
			{
				Doc->Tracks.Add(MoveTemp(Track));
				Doc->Duration = FMath::Max(Doc->Duration, Time);
				Note(TEXT("routes move their children along the timeline"));
			}
			return Rider;
		}

		void Children(const TSharedPtr<FJsonObject>& O, int32 Parent)
		{
			const TArray<TSharedPtr<FJsonValue>>* Kids = nullptr;
			if (O->TryGetArrayField(TEXT("children"), Kids)) for (const TSharedPtr<FJsonValue>& K : *Kids) Object(K->AsObject(), Parent);
		}

		void Object(const TSharedPtr<FJsonObject>& O, int32 Parent)
		{
			if (!O) return;
			const FString Kind = O->GetStringField(TEXT("kind"));
			if (Kind == TEXT("Folder"))
			{
				++Report->Folders;
				const int32 Id = Add(EOKSceneObjectKind::Folder, O->GetStringField(TEXT("name")), Parent, O);
				Children(O, Id);
			}
			else if (Kind == TEXT("Route"))
			{
				// A route is a folder; its children ride a second folder that rests on the start point (OCIRoute's child
				// root) and travels through the points along the timeline.
				++Report->Routes;
				const int32 Id = Add(EOKSceneObjectKind::Folder, TEXT("[route] ") + O->GetStringField(TEXT("name")), Parent, O);
				const int32 Rider = Route(O, Id);
				Children(O, Rider >= 0 ? Rider : Id);
			}
			else if (Kind == TEXT("Text"))
			{
				++Report->Texts;
				Note(TEXT("text objects are skipped"));
			}
			else if (Kind == TEXT("Camera"))
			{
				++Report->Cameras;
				const int32 Id = Add(EOKSceneObjectKind::Camera, O->GetStringField(TEXT("name")), Parent, O);
				// Unity's camera looks along its +Z, an Unreal camera along +X.
				FTransform& T = Doc->Find(Id)->Transform;
				T.SetRotation(T.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI));
				if (O->GetBoolField(TEXT("active"))) Doc->ActiveCamera = Id;
			}
			else if (Kind == TEXT("Light"))
			{
				++Report->Lights;
				const int32 Id = Add(EOKSceneObjectKind::Light, TEXT("Light"), Parent, O);
				// Unity's directional and spot lights shine along +Z, Unreal's along +X.
				FTransform& T = Doc->Find(Id)->Transform;
				T.SetRotation(T.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI));
				FOKSceneLight& L = Doc->Find(Id)->Light;
				const int32 No = int32(O->GetNumberField(TEXT("no")));
				const float SpotAngleFull = float(O->GetNumberField(TEXT("spot_angle")));
				FString LightType;
				if (O->TryGetStringField(TEXT("light_type"), LightType))
				{
					L.Type = LightType == TEXT("directional") ? EOKSceneLightType::Directional
						: LightType == TEXT("spot") ? EOKSceneLightType::Spot : EOKSceneLightType::Point;
				}
				else
				{
					L.Type = No == 0 ? EOKSceneLightType::Directional
						: (No == 2 || (No > 2 && !FMath::IsNearlyEqual(SpotAngleFull, 30.f, 1e-2f))) ? EOKSceneLightType::Spot
						: EOKSceneLightType::Point;
				}
				const TSharedPtr<FJsonObject>* C = nullptr;
				if (O->TryGetObjectField(TEXT("color"), C)) L.Color = Color(*C);
				// Unity intensity (about 0..2) to UE units; ranges are metres.
				const float Intensity = float(O->GetNumberField(TEXT("intensity")));
				L.Intensity = L.Type == EOKSceneLightType::Directional ? Intensity * 4.f : Intensity * 800.f;
				L.Range = float(O->GetNumberField(TEXT("range"))) * 100.f;
				L.SpotAngle = SpotAngleFull * 0.5f;
				L.bShadows = O->GetBoolField(TEXT("shadow"));
				if (!O->GetBoolField(TEXT("enable"))) Doc->Find(Id)->bVisible = false;
				Note(TEXT("light intensities are converted approximately"));
			}
			else if (Kind == TEXT("Item"))
			{
				++Report->Items;
				int32 Group = int32(O->GetNumberField(TEXT("group"))), Category = int32(O->GetNumberField(TEXT("category"))), No = int32(O->GetNumberField(TEXT("no")));
				const FOKStudioCatalogItem* Entry = FOKStudioCatalog::Get().FindItem(Group, Category, No);
				// A sideloader mod item: the scene saved the session's local slot; the mod's GUID and own slot name it
				// (studio_mod_items.json, ok-extract --oklib studio-mods). The item keeps the mod's numbers from now on.
				FString ModGuid;
				const FOKStudioEffect* ModEffect = nullptr;
				float ModEffectScale = 1.f;
				FString ModParticleText;
				if (O->TryGetStringField(TEXT("mod_guid"), ModGuid) && !ModGuid.IsEmpty())
				{
					// A particle pack's item (its ParticleSystems are not converted): the OK effect its name stands for.
					if (const FOKStudioCatalogItem* Particle = FOKStudioCatalog::Get().FindModParticle(ModGuid, int32(O->GetNumberField(TEXT("mod_slot")))))
					{
						ModEffect = FOKStudioCatalog::Get().EffectForParticleMod(*Particle, &ModEffectScale);
						ModParticleText = FOKStudioCatalog::ParticleText(*Particle);
						if (!ModEffect && Particle->Model.IsEmpty()) Note(FString::Printf(TEXT("mod particle items without a matching OK effect (add a word to effects.json): %s"), *Particle->Name));
					}
					Entry = FOKStudioCatalog::Get().FindModItem(ModGuid, int32(O->GetNumberField(TEXT("mod_slot"))));
					if (Entry) { Group = Entry->Group; Category = Entry->Category; No = Entry->No; Note(TEXT("mod items come from the library's converted mods")); }
					else if (!ModEffect) Note(FString::Printf(TEXT("mod items not in the library (ok-extract <game> --oklib studio-mods <library> <scene folder>): %s"), *ModGuid));
				}
				// Particle items become OK Niagara effects (the game's ParticleSystems are not converted).
				if (const FOKStudioEffect* Effect = ModEffect ? ModEffect : FOKStudioCatalog::Get().EffectForKks(Group, Category, No))
				{
					const int32 FxId = Add(EOKSceneObjectKind::Effect, Effect->Name, Parent, O);
					Doc->Find(FxId)->Effect.Effect = Effect->Id;
					if (Effect == ModEffect)
					{
						Doc->Find(FxId)->Transform.MultiplyScale3D(FVector(ModEffectScale));
						Doc->Find(FxId)->Effect.Source = ModParticleText;
					}
					Note(TEXT("particle items become OK Niagara effects"));
					Children(O, FxId);
					return;
				}
				const int32 Id = Add(Entry ? EOKSceneObjectKind::Item : EOKSceneObjectKind::Folder, Entry ? Entry->Name : FString::Printf(TEXT("[mod item %d/%d/%d]"), Group, Category, No), Parent, O);
				if (Entry)
				{
					++Report->CatalogItems;
					FOKSceneItem& I = Doc->Find(Id)->Item;
					I.Group = Group; I.Category = Category; I.No = No;
					if (const TArray<FOKSceneMaterialEdit>* Edits = MaterialEdits.Find(int32(O->GetNumberField(TEXT("key")))))
					{
						I.MaterialEdits = *Edits;
						Note(TEXT("items carry Material Editor edits"));
					}
                    double ItemTime=0., ItemSpeed=1.; int32 ItemPattern=0;
                    O->TryGetNumberField(TEXT("anime_time"), ItemTime); O->TryGetNumberField(TEXT("anime_speed"), ItemSpeed); O->TryGetNumberField(TEXT("anime_pattern"), ItemPattern);
                    I.AnimeTime=float(ItemTime);
                    I.AnimeSpeed=float(ItemSpeed);
                    I.AnimePattern=ItemPattern;
                    if (Entry->bAnime && (ItemPattern != 0 || !FOKStudioCatalog::Get().ChildAnimations.Contains(FIntVector(Group, Category, No))))
                        Note(TEXT("animated item attachment has no converted track for its selected pattern"));
					// Item FK of an enabled item: its bones' local rotations.
					const TArray<TSharedPtr<FJsonValue>>* Bones = nullptr;
					if (O->GetBoolField(TEXT("enable_fk")) && O->TryGetArrayField(TEXT("fk"), Bones))
						for (const TSharedPtr<FJsonValue>& B : *Bones)
						{
							const TArray<TSharedPtr<FJsonValue>>& Pair = B->AsArray();
							if (Pair.Num() == 2) I.Fk.Add({ Pair[0]->AsString(), Vec3(Pair[1]->AsObject(), TEXT("rot")) });
						}
					const TArray<TSharedPtr<FJsonValue>>* Colors = nullptr;
					if (O->TryGetArrayField(TEXT("colors"), Colors))
						for (int32 K = 0; K < 3 && K < Colors->Num(); ++K)
						{
							FLinearColor C = Color((*Colors)[K]->AsObject());
							I.Colors.Add(Entry->Colors[K] ? FLinearColor(C.R, C.G, C.B, 1.f) : FLinearColor(1.f, 1.f, 1.f, -1.f));
						}
					// colors[6]: the item's shadow colour (OIItemInfo; the game writes it to every material's _shadowcolor).
					if (Colors && Colors->IsValidIndex(6))
					{
						const FLinearColor C = Color((*Colors)[6]->AsObject());
						I.ShadowColor = FLinearColor(C.R, C.G, C.B, 1.f);
					}
					double Alpha = 1., LineWidth = 1.;
					if (O->TryGetNumberField(TEXT("alpha"), Alpha)) I.Alpha = FMath::Clamp(float(Alpha), 0.f, 1.f);
					if (O->TryGetNumberField(TEXT("line_width"), LineWidth)) I.LineWidth = FMath::Max(0.f, float(LineWidth));
					// Light cancel, emission and outline colour (OIItemInfo, scene version 0.0.7 on).
					double LightCancel = -1., EmissionPower = -1.;
					if (O->TryGetNumberField(TEXT("light_cancel"), LightCancel) && LightCancel >= 0.) I.LightCancel = float(LightCancel);
					if (O->TryGetNumberField(TEXT("emission_power"), EmissionPower) && EmissionPower >= 0.) I.EmissionPower = float(EmissionPower);
					const TSharedPtr<FJsonObject>* ItemColor = nullptr;
					if (O->TryGetObjectField(TEXT("emission_color"), ItemColor)) I.EmissionColor = Color(*ItemColor);
					if (O->TryGetObjectField(TEXT("line_color"), ItemColor)) I.LineColor = Color(*ItemColor);
					// Pattern slots the item offers (ItemList 柄 flags): mask, colour (colors[3..5]), UV, rotation, clamp.
					const TArray<TSharedPtr<FJsonValue>>* Patterns = nullptr;
					if (O->TryGetArrayField(TEXT("patterns"), Patterns))
					{
						bool bAny = false;
						TArray<FOKSceneItemPattern> Slots;
						for (int32 K = 0; K < 3 && K < Patterns->Num(); ++K)
						{
							const TSharedPtr<FJsonObject> P = (*Patterns)[K]->AsObject();
							FOKSceneItemPattern S;
							if (P && Entry->Patterns[K])
							{
								S.Pattern = FMath::Max(0, int32(P->GetNumberField(TEXT("key"))));
								S.bClamp = P->GetBoolField(TEXT("clamp"));
								S.Rotation = float(P->GetNumberField(TEXT("rot")));
								const TArray<TSharedPtr<FJsonValue>>* Uv = nullptr;
								if (P->TryGetArrayField(TEXT("uv"), Uv) && Uv->Num() == 4) S.Uv = FVector4((*Uv)[0]->AsNumber(), (*Uv)[1]->AsNumber(), (*Uv)[2]->AsNumber(), (*Uv)[3]->AsNumber());
								if (Colors && Colors->IsValidIndex(3 + K)) S.Color = Color((*Colors)[3 + K]->AsObject());
								FString UserFile;
								if (P->TryGetStringField(TEXT("file"), UserFile) && !UserFile.IsEmpty()) Note(TEXT("item patterns from user pattern files are not carried over"));
							}
							bAny |= S.Pattern > 0;
							Slots.Add(S);
						}
						if (bAny) I.Patterns = Slots;
					}
				}
				else Note(TEXT("mod items not in the base library become empty folders"));
				Children(O, Id);
			}
			else if (Kind == TEXT("Character"))
			{
				++Report->Characters;
				FString KksCard;
				O->TryGetStringField(TEXT("card"), KksCard);
				const int32 Key = int32(O->GetNumberField(TEXT("key")));
				const FString OkCard = CardDirectory / FString::Printf(TEXT("char_%d.png"), Key);
				FString Summary;
				// A Studio scene names a coordinate explicitly. Keep its numbering and record that outfit's resources;
				// the Gallery's automatic display outfit selection would exchange the saved outfit with another one.
				const TSharedPtr<FJsonObject>* SavedStatus = nullptr;
				int32 SavedOutfit = 0;
				if (O->TryGetObjectField(TEXT("status"), SavedStatus)) (*SavedStatus)->TryGetNumberField(TEXT("coordinate"), SavedOutfit);
				SavedOutfit = FMath::Max(0, SavedOutfit);
				bool bCard = !KksCard.IsEmpty() && FOkSession::MakeOkCardForOutfit(KksCard, OkCard, SavedOutfit, Summary);
				if (!bCard && !KksCard.IsEmpty() && !Report->Source.IsEmpty())
				{
					FString Dir = FPaths::ConvertRelativePathToFull(FPaths::GetPath(Report->Source));
					for (int32 Depth = 0; Depth < 8 && !Dir.IsEmpty(); ++Depth)
					{
						const FString ModsDir = Dir / TEXT("mods");
						if (IFileManager::Get().DirectoryExists(*ModsDir))
						{
							FString RetrySummary;
							if (FOkSession::MakeOkCardForOutfit(KksCard, OkCard, SavedOutfit, RetrySummary, ModsDir)
								|| FOkSession::MakeOkCardForOutfit(KksCard, OkCard, SavedOutfit, RetrySummary, Dir))
							{
								bCard = true;
								Summary = MoveTemp(RetrySummary);
							}
							break;
						}
						const FString ParentDir = FPaths::GetPath(Dir);
						if (ParentDir.IsEmpty() || ParentDir == Dir) break;
						Dir = ParentDir;
					}
				}
				if (bCard) ++Report->CharacterCards; else Report->Notes.Add(FString::Printf(TEXT("character %d: no OK card (%s)"), Key, *Summary));
				// U194: the name in the tree is the card's; "Character 171" said nothing.
				FString CharacterName = FString::Printf(TEXT("Character %d"), Key);
				FKKCharacterFile CardFile;
				FString CardError;
				if (!KksCard.IsEmpty() && UKKCardReader::LoadFromFile(KksCard, CardFile, CardError))
				{
					const FString Full = (CardFile.LastName + TEXT(" ") + CardFile.FirstName).TrimStartAndEnd();
					if (!Full.IsEmpty()) CharacterName = Full;
				}
				// A card that did not convert stays beside the scene's cards (char_<key>.kks.png) to reproduce the failure.
				if (bCard) IFileManager::Get().Delete(*KksCard);
				FString OkAnimPath;
				O->TryGetStringField(TEXT("okanim"), OkAnimPath);
				const bool bHasOkAnim = !OkAnimPath.IsEmpty() && FPaths::FileExists(OkAnimPath);
				// KKVMDPlay drove this character with an MMD motion when the scene was saved (its thumbnail shows that
				// moment). The file is a path on the saving machine; it is looked up by name beside the scene too.
				const TSharedPtr<FJsonObject>* Vmd = nullptr;
				if (O->TryGetObjectField(TEXT("vmd"), Vmd) && (*Vmd)->GetStringField(TEXT("VMDAnimEnabled")).Equals(TEXT("True"), ESearchCase::IgnoreCase))
				{
					const FString Motion = (*Vmd)->GetStringField(TEXT("lastLoadedVMD"));
					const FString Name = FPaths::GetCleanFilename(Motion.Replace(TEXT("\\"), TEXT("/")));
					if (bHasOkAnim)
					{
						Report->Notes.Add(FString::Printf(TEXT("character %d: KKVMDPlay motion %s solved to .okanim and attached"), Key, *Name));
					}
					else
					{
						const bool bHere = FPaths::FileExists(Motion) || FPaths::FileExists(FPaths::GetPath(Report->Source) / Name);
						Report->Notes.Add(FString::Printf(TEXT("character %d: KKVMDPlay motion %s (%s; VMD file not resolved, the character keeps its saved pose)"),
							Key, *Name, bHere ? TEXT("found") : TEXT("not on this machine")));
					}
				}
				const int32 Id = Add(EOKSceneObjectKind::Character, CharacterName, Parent, O);
				FOKSceneCharacter& C = Doc->Find(Id)->Character;
				C.EyesLook = EOKSceneLook::Animation;
				C.Card = bCard ? OkCard : KksCard;
				double Mouth = -1.;
				if (O->TryGetNumberField(TEXT("mouth_open"), Mouth)) C.MouthOpen = float(Mouth);
				// Character state: Studio's nipple and fluids, the card's tears and accessory slots (blush and gloss the card
				// already carries).
				double Nipple = -1.;
				if (O->TryGetNumberField(TEXT("nipple"), Nipple)) C.NipStand = FMath::Clamp(float(Nipple), 0.f, 1.f);
				const TArray<TSharedPtr<FJsonValue>>* Siru = nullptr;
				if (O->TryGetArrayField(TEXT("siru"), Siru) && Siru->Num() == 5)
				{
					TArray<uint8> Fluids;
					for (const TSharedPtr<FJsonValue>& V : *Siru) Fluids.Add(uint8(FMath::Clamp(int32(V->AsNumber()), 0, 2)));
					if (Fluids.ContainsByPredicate([](uint8 L) { return L != 0; })) C.Fluids = Fluids;
				}
				const TSharedPtr<FJsonObject>* Status = nullptr;
				if (O->TryGetObjectField(TEXT("status"), Status))
				{
					int32 Tears = 0;
					if ((*Status)->TryGetNumberField(TEXT("tears_lv"), Tears) && Tears > 0) C.TearsLevel = FMath::Min(Tears, 3);
					// The outfit and clothes state the scene was saved with (ChaFileStatus.coordinateType / clothesState).
					int32 Coordinate = -1;
					if ((*Status)->TryGetNumberField(TEXT("coordinate"), Coordinate) && Coordinate >= 0) C.Outfit = Coordinate;
					const TArray<TSharedPtr<FJsonValue>>* Clothes = nullptr;
					if ((*Status)->TryGetArrayField(TEXT("clothes_state"), Clothes) && Clothes->Num() > 0)
					{
						for (int32 Part = 0; Part < FMath::Min(Clothes->Num(), C.ClothesStates.Num()); ++Part) C.ClothesStates[Part] = uint8(FMath::Clamp(int32((*Clothes)[Part]->AsNumber()), 0, 3));
						// ChaFileStatus.clothesState in KK/KKS has 8 entries ([7] = Shoes), whereas C.ClothesStates has 9 ([7] = inner, [8] = outer).
						if (Clothes->Num() == 8 && C.ClothesStates.Num() >= 9) C.ClothesStates[8] = C.ClothesStates[7];
					}
					// The face the scene was saved with (ChaFileStatus eyebrowPtn / eyesPtn / mouthPtn), and where the eyes and neck look:
					// eyes 1 at the camera (0 straight ahead), neck 0 at the camera (3, the default, as the animation).
					int32 Face = -1;
					if ((*Status)->TryGetNumberField(TEXT("eyebrow_ptn"), Face) && Face >= 0) C.EyebrowPattern = Face;
					if ((*Status)->TryGetNumberField(TEXT("eyes_ptn"), Face) && Face >= 0) C.EyesPattern = Face;
					if ((*Status)->TryGetNumberField(TEXT("mouth_ptn"), Face) && Face >= 0) C.MouthPattern = Face;
					if ((*Status)->TryGetNumberField(TEXT("eyes_look_ptn"), Face) && Face >= 0) C.EyesLook = Face == 1 ? EOKSceneLook::Camera : EOKSceneLook::Animation;
					if ((*Status)->TryGetNumberField(TEXT("neck_look_ptn"), Face) && Face >= 0) C.NeckLook = Face == 0 ? EOKSceneLook::Camera : EOKSceneLook::Animation;
					const TArray<TSharedPtr<FJsonValue>>* Shown = nullptr;
					if ((*Status)->TryGetArrayField(TEXT("show_accessory"), Shown) && Shown->ContainsByPredicate([](const TSharedPtr<FJsonValue>& V) { return !V->AsBool(); }))
					{
						C.AccessoriesShown.Init(1, 21);
						for (int32 Slot = 0; Slot < FMath::Min(Shown->Num(), 20); ++Slot) C.AccessoriesShown[Slot] = (*Shown)[Slot]->AsBool() ? 1 : 0;
					}
				}
                const TSharedPtr<FJsonObject>* Neck = nullptr;
                int32 SavedNeckPattern = -1;
                if (Status) (*Status)->TryGetNumberField(TEXT("neck_look_ptn"), SavedNeckPattern);
                if (SavedNeckPattern == 4 && O->TryGetObjectField(TEXT("neck"), Neck) && (*Neck)->GetIntegerField(TEXT("pattern")) == 4)
                {
                    const TArray<TSharedPtr<FJsonValue>>* Rotations = nullptr;
                    if ((*Neck)->TryGetArrayField(TEXT("rotations"), Rotations) && Rotations->Num() == 2)
                        for (const auto& Value : *Rotations)
                        {
                            const auto& Q = Value->AsArray();
                            if (Q.Num() == 4) C.FixedNeck.Add(FQuat(Q[0]->AsNumber(), Q[1]->AsNumber(), Q[2]->AsNumber(), Q[3]->AsNumber()).GetNormalized());
                        }
                    if (C.FixedNeck.Num() == 2) C.NeckLook = EOKSceneLook::Fixed;
                    else Note(TEXT("saved FIX neck requires the native neck/head bone pair"));
                }
				int32 SavedEyesPattern = -1;
				if (Status) (*Status)->TryGetNumberField(TEXT("eyes_look_ptn"), SavedEyesPattern);
				const TArray<TSharedPtr<FJsonValue>>* SavedEyes = nullptr;
				// The source FIX row is NO_LOOK: retain its saved angles instead of aiming at a target.
				if (SavedEyesPattern == 3 && O->TryGetArrayField(TEXT("eyes"), SavedEyes) && SavedEyes->Num() == 12)
				{
					for (const auto& Value : *SavedEyes) C.FixedEyes.Add(float(Value->AsNumber()));
					C.FixedEyesPattern = SavedEyesPattern;
					C.EyesLook = EOKSceneLook::Fixed;
				}
				// FK of the enabled parts.
				const TArray<TSharedPtr<FJsonValue>>* Active = nullptr;
				const TArray<TSharedPtr<FJsonValue>>* Bones = nullptr;
				if (O->GetBoolField(TEXT("enable_fk")) && O->TryGetArrayField(TEXT("active_fk"), Active) && O->TryGetArrayField(TEXT("fk"), Bones))
				{
					for (const TSharedPtr<FJsonValue>& B : *Bones)
					{
						const TArray<TSharedPtr<FJsonValue>>& Pair = B->AsArray();
						if (Pair.Num() != 2) continue;
						const int32 BoneNo = int32(Pair[0]->AsNumber());
						const FOKStudioFkBone* Info = FOKStudioCatalog::Get().FkBones.FindByPredicate([BoneNo](const FOKStudioFkBone& F) { return F.No == BoneNo; });
						if (!Info) continue;
						const int32 Part = FOKStudioPose::FkPart(Info->Group);
						if (!Active->IsValidIndex(Part) || !(*Active)[Part]->AsBool()) continue;
						C.Fk.Add({ Info->Bone, Vec3(Pair[1]->AsObject(), TEXT("rot")) });
					}
				}
				// IK targets of the enabled parts: the scene keeps their positions in the character's space. KK numbers them
				// 0 hips, 1-3 left arm (shoulder, elbow, hand), 4-6 right arm, 7-9 left leg (thigh, knee, foot), 10-12 right leg;
				// the parts switch as body, right leg, left leg, right arm, left arm. Elbows and knees are the limbs' bend goals (9..12).
				const TArray<TSharedPtr<FJsonValue>>* ActiveIk = nullptr;
				const TArray<TSharedPtr<FJsonValue>>* Targets = nullptr;
				if (O->GetBoolField(TEXT("enable_ik")) && O->TryGetArrayField(TEXT("active_ik"), ActiveIk) && O->TryGetArrayField(TEXT("ik"), Targets))
				{
					struct FMap { int32 Effector; int32 Part; };
					static const FMap Map[13] = { {0, 0}, {1, 4}, {9, 4}, {5, 4}, {2, 3}, {10, 3}, {6, 3}, {3, 2}, {11, 2}, {7, 2}, {4, 1}, {12, 1}, {8, 1} };
					for (const TSharedPtr<FJsonValue>& T : *Targets)
					{
						const TArray<TSharedPtr<FJsonValue>>& Pair = T->AsArray();
						if (Pair.Num() != 2) continue;
						const int32 No = int32(Pair[0]->AsNumber());
						if (No < 0 || No >= 13 || !ActiveIk->IsValidIndex(Map[No].Part) || !(*ActiveIk)[Map[No].Part]->AsBool()) continue;
						const FVector P = Vec3(Pair[1]->AsObject(), TEXT("pos"));
						FOKSceneIkTarget Target;
                        Target.Effector = Map[No].Effector;
                        Target.Position = FVector(-P.X, P.Z, P.Y) * 100.0;
                        Target.bUseRotation = No == 3 || No == 6 || No == 9 || No == 12;
                        Target.Euler = Vec3(Pair[1]->AsObject(), TEXT("rot"));
                        C.Ik.Add(Target);
					}
				}
				// Hand shapes: 0 follows the animation, n is the game's shape n (OCIChar.ChangeHandAnime: SetShapeHandValue(side, n, 0, 0)).
				const TArray<TSharedPtr<FJsonValue>>* Hands = nullptr;
				if (O->TryGetArrayField(TEXT("hand"), Hands) && Hands->Num() == 2)
				{
					auto Shape = [](double V) { const int32 N = int32(V); return N <= 0 ? -1 : FMath::Min(N, 23); };
					C.HandLeft = Shape((*Hands)[0]->AsNumber());
					C.HandRight = Shape((*Hands)[1]->AsNumber());
				}
				// The voice list (VoiceCtrl: group, category, no each, and its repeat); Studio says it once the scene is open.
				const TArray<TSharedPtr<FJsonValue>>* Voices = nullptr;
				if (O->TryGetArrayField(TEXT("voices"), Voices))
					for (const TSharedPtr<FJsonValue>& V : *Voices)
					{
						const TArray<TSharedPtr<FJsonValue>>& E = V->AsArray();
						if (E.Num() == 3) C.Voices.Add({ int32(E[0]->AsNumber()), int32(E[1]->AsNumber()), int32(E[2]->AsNumber()) });
					}
				double VoiceRepeat = 1.;
				O->TryGetNumberField(TEXT("voice_repeat"), VoiceRepeat);
				C.VoiceRepeat = FMath::Clamp(int32(VoiceRepeat), 0, 2);
				C.bVoicePlay = !C.Voices.IsEmpty();
				// Joint correction (OICharInfo.expression, one flag per ExpressionBone category; 4 in old scenes).
				const TArray<TSharedPtr<FJsonValue>>* Expression = nullptr;
				C.JointCorrection = 0;
				if (O->TryGetArrayField(TEXT("expression"), Expression))
					for (int32 I = 0; I < FMath::Min(Expression->Num(), 8); ++I)
						if ((*Expression)[I]->AsBool()) C.JointCorrection |= 1 << I;
				const TArray<TSharedPtr<FJsonValue>>* Anime = nullptr;
				if (O->TryGetArrayField(TEXT("anime"), Anime) && Anime->Num() == 3 && (*Anime)[0]->AsNumber() >= 0)
				{
					const int32 G = int32((*Anime)[0]->AsNumber()), Cat = int32((*Anime)[1]->AsNumber()), N = int32((*Anime)[2]->AsNumber());
					if (const FOKStudioAnim* A = FOKStudioCatalog::Get().FindAnimAnyKind(G, Cat, N); A && !A->File.IsEmpty())
					{
						C.StudioAnimeKind = A->Kind; C.StudioAnimeGroup = G; C.StudioAnimeCategory = Cat; C.StudioAnimeNo = N;
						double Speed = 1.;
						if (O->TryGetNumberField(TEXT("anime_speed"), Speed)) C.Speed = float(Speed);
						double Time = 0.;
						if (O->TryGetNumberField(TEXT("anime_time"), Time)) C.Time = float(Time) * FMath::Max(A->Duration, 0.01f);
						O->TryGetBoolField(TEXT("anime_force_loop"), C.bForceLoop);
						// The H controls the motion blends along: KStudio's animeOptionParam1/2 and animePattern.
						const TArray<TSharedPtr<FJsonValue>>* Options = nullptr;
						O->TryGetArrayField(TEXT("anime_options"), Options);
						double Pattern = 0.;
						const bool bPattern = O->TryGetNumberField(TEXT("anime_pattern"), Pattern);
						for (const FString& Control : A->Controls)
						{
							const int32 Option = Control == TEXT("option1") ? 0 : Control == TEXT("option2") ? 1 : -1;
							if (Option >= 0 ? !(Options && Options->IsValidIndex(Option)) : !bPattern) continue;
							FOKSceneAnimFloat& F = C.AnimFloats.AddDefaulted_GetRef();
							F.Name = Control;
							F.Value = FMath::Clamp(float(Option >= 0 ? (*Options)[Option]->AsNumber() : Pattern), 0.f, 1.f);
						}
					}
					else Note(FString::Printf(TEXT("Studio animation %d/%d/%d is not in the OK animation library (a mod motion this installation lacks; anim-convert adds it once the mod is installed)"), G, Cat, N));
				}
				if (bHasOkAnim)
				{
					C.AnimFile = OkAnimPath;
					C.StudioAnimeKind = 0;
					C.StudioAnimeGroup = -1;
					C.StudioAnimeCategory = -1;
					C.StudioAnimeNo = -1;
					C.Time = 0.f;
					C.Speed = 1.f;
					C.Fk.Reset();
					C.Ik.Reset();
					C.HandLeft = -1;
					C.HandRight = -1;
					C.NeckLook = EOKSceneLook::Animation;
					C.EyesLook = EOKSceneLook::Animation;
					C.FixedNeck.Reset();
					C.FixedEyes.Reset();
					Note(TEXT("MMDD / KKVMDPlay VMD motion solved to .okanim"));
				}
				// Children on accessory slots: kept under the character.
				const TArray<TSharedPtr<FJsonValue>>* Slots = nullptr;
				if (O->TryGetArrayField(TEXT("children"), Slots))
					for (const TSharedPtr<FJsonValue>& S : *Slots)
					{
						const TArray<TSharedPtr<FJsonValue>>& Pair = S->AsArray();
						if (Pair.Num() != 2) continue;
						const FOKStudioAccessoryPoint* Point = FOKStudioCatalog::Get().FindAccessoryPoint(int32(Pair[0]->AsNumber()));
						if (!Point) Note(TEXT("objects on accessory slots the base library does not list sit at the character root (re-run the conversion for the accessory points)"));
						for (const TSharedPtr<FJsonValue>& K : Pair[1]->AsArray()) { PendingAttach = Point ? Point->Bone : FString(); Object(K->AsObject(), Id); PendingAttach.Reset(); }
					}
			}
		}
	};
}

FTransform FOKStudioImport::UnityToUe(const FVector& Position, const FVector& EulerDegrees, const FVector& Scale)
{
	// Unity rotation order Z, X, Y (q = qy qx qz); the converter's basis change maps a quaternion (x, y, z, w) to (-x, z, y, w).
	const FQuat Qx(FVector(1, 0, 0), FMath::DegreesToRadians(EulerDegrees.X));
	const FQuat Qy(FVector(0, 1, 0), FMath::DegreesToRadians(EulerDegrees.Y));
	const FQuat Qz(FVector(0, 0, 1), FMath::DegreesToRadians(EulerDegrees.Z));
	const FQuat U = Qy * Qx * Qz;
	return FTransform(FQuat(-U.X, U.Z, U.Y, U.W).GetNormalized(), FVector(-Position.X, Position.Z, Position.Y) * 100.0, FVector(Scale.X, Scale.Z, Scale.Y));
}

FString FOKStudioImport::FReport::ToJson() const
{
	TSharedRef<FJsonObject> J = MakeShared<FJsonObject>();
	J->SetStringField(TEXT("source"), Source);
	J->SetStringField(TEXT("version"), Version);
	J->SetNumberField(TEXT("characters"), Characters);
	J->SetNumberField(TEXT("character_cards"), CharacterCards);
	J->SetNumberField(TEXT("items"), Items);
	J->SetNumberField(TEXT("catalog_items"), CatalogItems);
	J->SetNumberField(TEXT("lights"), Lights);
	J->SetNumberField(TEXT("cameras"), Cameras);
	J->SetNumberField(TEXT("folders"), Folders);
	J->SetNumberField(TEXT("routes"), Routes);
	J->SetNumberField(TEXT("texts"), Texts);
	J->SetNumberField(TEXT("map"), Map);
	TArray<TSharedPtr<FJsonValue>> N;
	for (const FString& S : Notes) N.Add(MakeShared<FJsonValueString>(S));
	J->SetArrayField(TEXT("notes"), N);
	FString Out;
	FJsonSerializer::Serialize(J, TJsonWriterFactory<>::Create(&Out));
	return Out;
}

namespace
{
	/** A Unity camera key as ours: where it stands and looks, and MMD's vertical angle of view as a 16:9 horizontal one. */
	void MmddCameraKey(const TSharedPtr<FJsonObject>& Kf, FTransform& OutTransform, float& OutFov)
	{
		OutTransform = FOKStudioImport::UnityToUe(Vec3(Kf, TEXT("world_pos")), Vec3(Kf, TEXT("rot")), FVector::OneVector);
		OutTransform.SetRotation(OutTransform.GetRotation() * MmddCamTurn());
		const double VertFov = FMath::DegreesToRadians(FMath::Clamp(Kf->GetNumberField(TEXT("fov")), 1.0, 170.0));
		OutFov = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(VertFov * 0.5) * 16.0 / 9.0)));
	}
}

int32 FOKStudioImport::AddVmdCamera(UOKSceneDocument* Document, const FString& KeysJson, const FString& Name)
{
	TArray<TSharedPtr<FJsonValue>> Keys;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(KeysJson), Keys) || Keys.IsEmpty()) return -1;
	const FOKSceneObject* Old = Document->Objects.FindByPredicate([&Name](const FOKSceneObject& O) { return O.Kind == EOKSceneObjectKind::Camera && O.Name == Name; });
	const int32 Id = Old ? Old->Id : Document->AddObject(EOKSceneObjectKind::Camera, Name, -1);
	FOKSceneObject* Camera = Document->Find(Id);
	Document->Tracks.RemoveAll([Id](const FOKSceneTrack& T) { return T.ObjectId == Id; });
	FOKSceneTrack Track;
	Track.ObjectId = Id;
	for (const TSharedPtr<FJsonValue>& V : Keys)
	{
		const TSharedPtr<FJsonObject> Kf = V->AsObject();
		if (!Kf) continue;
		FOKSceneKey Key;
		float Fov;
		MmddCameraKey(Kf, Key.Transform, Fov);
		Key.Time = float(Kf->GetNumberField(TEXT("time")));
		Key.Ease = EOKSceneEase::Linear;
		Key.Value = Fov;
		if (Track.Keys.IsEmpty()) { Camera->Transform = Key.Transform; Camera->Camera.Fov = Fov; }
		Document->Duration = FMath::Max(Document->Duration, Key.Time);
		Track.Keys.Add(MoveTemp(Key));
	}
	Document->Tracks.Add(MoveTemp(Track));
	Document->ActiveCamera = Id;
	Document->Post.bDepthOfField = false;
	Document->NotifyChanged();
	return Id;
}

bool FOKStudioImport::Import(const FString& ScenePng, UOKSceneDocument* Document, const FString& CardDirectory, FReport& Report, FString& OutError)
{
	if (!Document) { OutError = TEXT("no document"); return false; }
	IFileManager::Get().MakeDirectory(*CardDirectory, true);
	TArray<ANSICHAR> Buffer;
	Buffer.SetNumZeroed(64 << 20);
	int32 ExportRc = ok_studio_scene_export(TCHAR_TO_UTF8(*ScenePng), TCHAR_TO_UTF8(*CardDirectory), Buffer.GetData(), Buffer.Num());
	if (ExportRc != 0 && FCStringAnsi::Strncmp(Buffer.GetData(), "needs ", 6) == 0)
	{
		const int64 Needed = FCStringAnsi::Atoi64(Buffer.GetData() + 6);
		if (Needed > Buffer.Num() && Needed <= (1536LL << 20))
		{
			Buffer.SetNumZeroed(int32(Needed + 4096));
			ExportRc = ok_studio_scene_export(TCHAR_TO_UTF8(*ScenePng), TCHAR_TO_UTF8(*CardDirectory), Buffer.GetData(), Buffer.Num());
		}
	}
	if (ExportRc != 0) { OutError = UTF8_TO_TCHAR(Buffer.GetData()); return false; }
	TSharedPtr<FJsonObject> Scene;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(UTF8_TO_TCHAR(Buffer.GetData())), Scene) || !Scene) { OutError = TEXT("bad scene JSON"); return false; }
	Report = FReport();
	Report.Source = ScenePng;
	Report.Version = Scene->GetStringField(TEXT("version"));
	Report.Map = int32(Scene->GetNumberField(TEXT("map")));
	Document->Objects.Reset();
    // Import replaces the scene. Optional/neutral settings must not inherit
    // the previous scene (e.g. aperture 0 left the previous DOF enabled).
    Document->Post = FOKScenePost();
    Document->MapTransform = FTransform::Identity;
    Document->Tracks.Reset();
    Document->Duration = 10.f;
    Document->SoundFile.Reset();
    Document->SoundDelay = 0.f;
    Document->Sound = FOKSceneSound();
    Document->ItemAnimationSeconds=0.f;
	Document->NextId = 1;
	Document->Constraints.Reset();
	Document->TimelineTracks.Reset();
	Document->bLoopTimeline = false;
	Document->StudioCameraId = -1;
	Document->StudioCameraOrbitTarget = FVector::ZeroVector;
	Document->StudioCameraOrbitRot = FVector::ZeroVector;
	Document->StudioCameraOrbitDist = FVector::ZeroVector;
	Document->CharaLightId = -1;
	Document->bLinkCharaLightToCamera = false;
	Document->LinkedLightBase = FVector2D::ZeroVector;
	Document->LinkedCameraBase = FVector2D::ZeroVector;
	Document->ActiveCamera = -1;
	Document->Map = FOKStudioCatalog::Get().FindMap(Report.Map) ? Report.Map : -1;
	if (Report.Map >= 0 && Document->Map < 0) Report.Notes.Add(FString::Printf(TEXT("map %d is not in the base library"), Report.Map));
	FImporter Importer;
	Importer.Doc = Document;
	Importer.CardDirectory = CardDirectory;
	Importer.Report = &Report;
	const TArray<TSharedPtr<FJsonValue>>* MaterialEdits = nullptr;
	if (Scene->TryGetArrayField(TEXT("material_edits"), MaterialEdits))
		for (const TSharedPtr<FJsonValue>& V : *MaterialEdits)
		{
			const TSharedPtr<FJsonObject> E = V->AsObject();
			const TArray<TSharedPtr<FJsonValue>>* Value = nullptr;
			if (!E || !E->TryGetArrayField(TEXT("value"), Value) || Value->Num() < 4) continue;
			FOKSceneMaterialEdit Edit;
			Edit.Material = E->GetStringField(TEXT("material"));
			Edit.Property = E->GetStringField(TEXT("property"));
			static const TMap<FString, EOKSceneMaterialEditKind> Kinds = { { TEXT("float"), EOKSceneMaterialEditKind::Float }, { TEXT("color"), EOKSceneMaterialEditKind::Color },
				{ TEXT("texture"), EOKSceneMaterialEditKind::Texture }, { TEXT("texture_st"), EOKSceneMaterialEditKind::TextureST },
				{ TEXT("shader"), EOKSceneMaterialEditKind::Shader }, { TEXT("renderer"), EOKSceneMaterialEditKind::Renderer } };
			const EOKSceneMaterialEditKind* Kind = Kinds.Find(E->GetStringField(TEXT("kind")));
			if (!Kind) continue;
			Edit.Kind = *Kind;
			E->TryGetStringField(TEXT("text"), Edit.Text);
			Edit.Value = FLinearColor(float((*Value)[0]->AsNumber()), float((*Value)[1]->AsNumber()), float((*Value)[2]->AsNumber()), float((*Value)[3]->AsNumber()));
			Importer.MaterialEdits.FindOrAdd(int32(E->GetNumberField(TEXT("id")))).Add(Edit);
		}
	const TArray<TSharedPtr<FJsonValue>>* Objects = nullptr;
	if (Scene->TryGetArrayField(TEXT("objects"), Objects)) for (const TSharedPtr<FJsonValue>& O : *Objects) Importer.Object(O->AsObject(), -1);
	const TArray<TSharedPtr<FJsonValue>>* CardErrors = nullptr;
	if (Scene->TryGetArrayField(TEXT("card_errors"), CardErrors)) for (const TSharedPtr<FJsonValue>& E : *CardErrors) Report.Notes.Add(E->AsString());
	// Screen settings (System menu): the Amplify Color filter (the grading LUT is lerp(filter, Lut_Amount, aceBlend):
	// Studio's camera blends towards its serialized Lut_Amount), bloom and vignette.
	const TSharedPtr<FJsonObject>* Effects = nullptr;
	if (Scene->TryGetObjectField(TEXT("effects"), Effects))
	{
		const FJsonObject& E = **Effects;
		int32 Ace = -1;
		double Blend = 0.;
		if (E.TryGetNumberField(TEXT("ace_no"), Ace) && FOKStudioCatalog::Get().FindFilter(Ace))
		{
			E.TryGetNumberField(TEXT("ace_blend"), Blend);
			Document->Post.ColorFilter = Ace;
			Document->Post.ColorFilterIntensity = float(FMath::Clamp(1. - Blend, 0., 1.));
		}
		else if (Ace >= 0) Report.Notes.Add(FString::Printf(TEXT("screen filter %d is not in the base library's Studio filter list"), Ace));
		bool bOn = false;
		double Value = 0.;
		if (E.TryGetBoolField(TEXT("bloom"), bOn))
		{
			Document->Post.bBloom = bOn;
			if (E.TryGetNumberField(TEXT("bloom_intensity"), Value)) Document->Post.BloomIntensity = float(Value);
			if (E.TryGetNumberField(TEXT("bloom_threshold"), Value)) Document->Post.BloomThreshold = float(Value);
			if (E.TryGetNumberField(TEXT("bloom_blur"), Value)) Document->Post.BloomSize = float(FMath::Clamp(Value / 4., 0.1, 8.));
		}
		if (E.TryGetBoolField(TEXT("vignette"), bOn)) Document->Post.bVignette = bOn;
		if (E.TryGetBoolField(TEXT("shadow"), bOn)) Document->Post.bShadow = bOn;
		// The shading globals (ambient shadow colour and strength, outline darkness and width): Studio writes them to
		// _ambientshadowG, _LineColorG, _linewidthG for everything it draws.
		const TSharedPtr<FJsonObject>* Ambient = nullptr;
		if (E.TryGetObjectField(TEXT("ambient_shadow"), Ambient)) Document->Post.AmbientShadow = Color(*Ambient);
		if (E.TryGetNumberField(TEXT("ambient_shadow_g"), Value)) Document->Post.AmbientShadowG = float(Value);
		if (E.TryGetNumberField(TEXT("line_color_g"), Value)) Document->Post.LineColorG = float(Value);
		if (E.TryGetNumberField(TEXT("line_width_g"), Value)) Document->Post.LineWidthG = float(Value);
		// SceneInfo.rampG: the mt_ramp the scene's characters and items shade with (SystemButtonCtrl sets _RampG).
		if (E.TryGetNumberField(TEXT("ramp_g"), Value)) Document->Post.RampG = int32(Value);
		// Studio restores its saved shader mode after loading characters; system.xml is only the card default.
		if (E.TryGetNumberField(TEXT("shader_type"), Value)) Document->Post.ShaderType = int32(Value);
		// SceneInfo.sunLightType: the map's time of day (its own sky, when it has one, follows it).
		if (E.TryGetNumberField(TEXT("sun_light_type"), Value)) Document->Post.SunType = int32(Value);
		// SceneInfo.caMap: Studio's map position / rotation (MapCtrl.Reflect sets the map root's local transform).
		Document->MapTransform = UnityToUe(Vec3(*Effects, TEXT("map_pos")), Vec3(*Effects, TEXT("map_rot")), FVector::OneVector);
		// Fog, ambient occlusion and sun shafts (SystemButtonCtrl FogInfo, AmplifyOcculusionEffectInfo, SunShaftsInfo).
		const TSharedPtr<FJsonObject>* Field = nullptr;
		if (E.TryGetBoolField(TEXT("fog"), bOn)) Document->Post.bFog = bOn;
		if (E.TryGetObjectField(TEXT("fog_color"), Field)) Document->Post.FogColor = Color(*Field);
		if (E.TryGetBoolField(TEXT("aoe"), bOn)) Document->Post.bAmbientOcclusion = bOn;
		if (E.TryGetObjectField(TEXT("aoe_color"), Field)) Document->Post.AmbientOcclusionTint = Color(*Field);
		if (E.TryGetNumberField(TEXT("aoe_radius"), Value)) Document->Post.AmbientOcclusionRadius = float(Value);
		if (E.TryGetBoolField(TEXT("sun_shafts"), bOn)) Document->Post.bSunShafts = bOn;
		if (E.TryGetObjectField(TEXT("sun_color"), Field)) Document->Post.SunShaftColor = Color(*Field);
		if (E.TryGetObjectField(TEXT("sun_threshold_color"), Field)) Document->Post.SunShaftThreshold = Color(*Field);
		// Depth of field (Unity Standard Assets DepthOfField, focused on the Studio camera's target; the focal distance is
		// set with the camera below). Its blur grows with 1 / (1 - aperture) - 1 (aperture 0: no blur at all) and shrinks
		// with the in-focus width focalSize; as an f-stop: 3.7 focalSize / strength, calibrated on official scene 1901
		// (focalSize 0.89, aperture 0.62: the stage behind the singers blurred, the singers sharp).
		double FocalSize = 0.95, Aperture = 0.6;
		E.TryGetNumberField(TEXT("depth_focal_size"), FocalSize);
		E.TryGetNumberField(TEXT("depth_aperture"), Aperture);
		const double Strength = 1. / (1. - FMath::Clamp(Aperture, 0., 0.95)) - 1.;
		if (E.TryGetBoolField(TEXT("depth"), bOn) && bOn && Strength > 0.01)
		{
			Document->Post.bDepthOfField = true;
			Document->Post.Aperture = float(FMath::Clamp(3.7 * FMath::Max(FocalSize, 0.05) / Strength, 0.3, 22.));
		}
		// Background and frame pictures (the scene names a file of UserData/bg, UserData/frame): the game's own ones are in
		// the OK base library (studio/bg, studio/frame, kept as library-relative paths); a user's own picture is copied
		// beside the cards from the scene's game folder or from beside the scene card.
		auto Picture = [&](const TCHAR* Field, const TCHAR* Kind) -> FString
		{
			FString Name;
			if (!E.TryGetStringField(Field, Name) || Name.IsEmpty()) return FString();
			const FString File = FPaths::GetCleanFilename(Name);
			const FString Library = FString::Printf(TEXT("studio/%s/%s"), Kind, *File);
			if (FPaths::FileExists(AOKSceneActor::LibraryDirectory() / Library)) return Library;
			if (FPaths::FileExists(CardDirectory / File)) return CardDirectory / File;
			const FString Normal = FPaths::ConvertRelativePathToFull(ScenePng).Replace(TEXT("\\"), TEXT("/"));
			const int32 UserData = Normal.Find(TEXT("/UserData/"), ESearchCase::IgnoreCase);
			TArray<FString> Candidates;
			if (UserData >= 0) Candidates.Add(Normal.Left(UserData) / TEXT("UserData") / Kind / File);
			Candidates.Add(FPaths::GetPath(Normal) / File);
			const FString* Source = Candidates.FindByPredicate([](const FString& C) { return FPaths::FileExists(C); });
			const FString Copy = CardDirectory / File;
			if (Source && (IFileManager::Get().Copy(*Copy, **Source) == COPY_OK || FPaths::FileExists(Copy))) return Copy;
			Report.Notes.Add(FString::Printf(TEXT("%s picture %s is neither in the base library nor beside the scene"), Kind, *Name));
			return FString();
		};
		Document->Post.Background = Picture(TEXT("background"), TEXT("bg"));
		Document->Post.Frame = Picture(TEXT("frame"), TEXT("frame"));
		// The sound menu (BGMCtrl, OutsideSoundCtrl): the BGM by its list no; the outside sound is a file of the game's
		// UserData/audio, copied beside the cards like a user's picture.
		{
			FOKSceneSound& S = Document->Sound;
			S.Bgm = E.HasField(TEXT("bgm_no")) ? int32(E.GetNumberField(TEXT("bgm_no"))) : 0;
			S.bBgmRepeat = !E.HasField(TEXT("bgm_repeat")) || int32(E.GetNumberField(TEXT("bgm_repeat"))) != 0;
			E.TryGetBoolField(TEXT("bgm_play"), S.bBgmPlay);
			S.bOutsideRepeat = !E.HasField(TEXT("outside_repeat")) || int32(E.GetNumberField(TEXT("outside_repeat"))) != 0;
			E.TryGetBoolField(TEXT("outside_play"), S.bOutsidePlay);
			if (S.bBgmPlay && FOKStudioCatalog::Get().BgmSound(S.Bgm).IsEmpty())
				Report.Notes.Add(FString::Printf(TEXT("BGM %d is not in the base library (ok-extract --oklib studio-sounds)"), S.Bgm));
			FString Name;
			if (E.TryGetStringField(TEXT("outside_file"), Name) && !Name.IsEmpty())
			{
				const FString FileName = FPaths::GetCleanFilename(Name);
				const FString Normal = FPaths::ConvertRelativePathToFull(ScenePng).Replace(TEXT("\\"), TEXT("/"));
				const int32 UserData = Normal.Find(TEXT("/UserData/"), ESearchCase::IgnoreCase);
				TArray<FString> Candidates;
				if (UserData >= 0) Candidates.Add(Normal.Left(UserData) / TEXT("UserData/audio") / FileName);
				Candidates.Add(FPaths::GetPath(Normal) / FileName);
				const FString* Source = Candidates.FindByPredicate([](const FString& C) { return FPaths::FileExists(C); });
				const FString Copy = CardDirectory / FileName;
				if (Source && (IFileManager::Get().Copy(*Copy, **Source) == COPY_OK || FPaths::FileExists(Copy))) S.Outside = Copy;
				else Report.Notes.Add(FString::Printf(TEXT("outside sound %s is neither in the game's UserData/audio nor beside the scene"), *FileName));
			}
		}
		// StudioScene initializes the colour-clearing main camera from EstData.BackColor.
		// Its depth-only child camera's blue colour never clears the scene.
		bool bSky = false;
		E.TryGetBoolField(TEXT("sky"), bSky);
		// SceneInfo.skyInfo: Studio's sky dome and its StudioSky pattern.
		Document->Post.bSky = bSky;
		Document->Post.SkyPattern = int32(E.GetNumberField(TEXT("sky_pattern")));
		// The author's clear colour shows in the scene's own picture when nothing covers its corners (2534's blue);
		// otherwise this installation's.
		// The picture went through the scene's grade (and vignette, at its corners: squared distance 1.86 from the
		// centre for the 8-pixel patches of a 320x180 picture): the colour behind is what grades to it.
		FLinearColor Shown;
		if (int32(Scene->GetNumberField(TEXT("map"))) < 0 && Document->Post.Background.IsEmpty() && !bSky)
			Document->Post.BackgroundColor = OKStudioClearColorFromPicture(ScenePng, Shown)
				? OKStudioUngradeSourceColor(Document->Post, Shown, 1.86f) : OKStudioConfiguredClearColor();
	}
	// The Studio view the scene was saved with: a camera object, the active view unless a camera object is.
	int32 CharaLightId = -1;
	const TSharedPtr<FJsonObject>* Camera = nullptr;
	if (Scene->TryGetObjectField(TEXT("camera"), Camera))
	{
		const int32 Id = Document->AddObject(EOKSceneObjectKind::Camera, TEXT("Studio camera"), -1);
		FOKSceneObject* Cam = Document->Find(Id);
		const FTransform Base = UnityToUe(Vec3(*Camera, TEXT("pos")), Vec3(*Camera, TEXT("rotate")), FVector::OneVector);
		const FVector Distance = Vec3(*Camera, TEXT("distance"));
		// Camera at rotation * distance + pos; Unity's camera looks along +Z, an Unreal camera along +X.
		Cam->Transform = FTransform(Base.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI), Base.GetLocation() + Base.GetRotation().RotateVector(FVector(-Distance.X, Distance.Z, Distance.Y) * 100.0));
		// Studio's depth of field focuses on the camera target.
		if (Document->Post.bDepthOfField) Document->Post.FocalDistance = float(FMath::Max(Distance.Size() * 100.0, 10.0));
		// Unity's field of view is vertical; Studio pictures are 16:9.
		const double VerticalFov = FMath::DegreesToRadians(FMath::Clamp((*Camera)->GetNumberField(TEXT("fov")), 1.0, 170.0));
		// Unity's depth of field blurs the far background by an amount on screen that does not depend on the lens; UE's
		// cinematic one by the focal length squared over f-stop times focus distance (focal length from the horizontal
		// field of view on its 24.89 mm sensor). The f-stop above was calibrated on 1901 (vertical 23 degrees, focus
		// 1.42 m); other views scale from there, else a wide view (4432: 31.5 degrees, 2.88 m) kept its background sharp.
		if (Document->Post.bDepthOfField)
		{
			auto FocalMm = [](double Vertical) { return 24.89 / (2.0 * FMath::Tan(Vertical * 0.5) * 16.0 / 9.0); };
			const double Focal = FocalMm(VerticalFov), FocalRef = FocalMm(FMath::DegreesToRadians(23.0));
			const double Focus = FMath::Max(double(Document->Post.FocalDistance) * 10.0, Focal + 1.0), FocusRef = 1420.0;
			const double Scale = FMath::Square(Focal / FocalRef) * (FocusRef - FocalRef) / (Focus - Focal);
			Document->Post.Aperture = float(FMath::Clamp(Document->Post.Aperture * Scale, 0.3, 22.0));
		}
		Cam->Camera.Fov = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(VerticalFov * 0.5) * 16.0 / 9.0)));
		Document->StudioCameraId = Id;
		Document->StudioCameraOrbitTarget = Vec3(*Camera, TEXT("pos"));
		Document->StudioCameraOrbitRot = Vec3(*Camera, TEXT("rotate"));
		Document->StudioCameraOrbitDist = Distance;
		if (Document->ActiveCamera < 0) Document->ActiveCamera = Id;
		++Report.Cameras;
		// CameraLightCtrl.LightCalc rotates the scene-root "Light Chara", not
		// the camera. Its Directional Chara child retains its authored (40,180,0)
		// rotation (CharaStudio_Data/level2). The scene file also keeps mapLight, but Studio only saves and loads
		// it: CameraLightCtrl has no map light, nothing in the game lights the map with it (the map shows its baked
		// lightmaps). Made a light, it washed lightmapped maps out (the 1F toilet's partitions drew white).
		const TArray<TSharedPtr<FJsonValue>>* StudioLights = nullptr;
		if ((*Camera)->TryGetArrayField(TEXT("lights"), StudioLights))
			for (const TSharedPtr<FJsonValue>& V : *StudioLights)
			{
				const TSharedPtr<FJsonObject> L = V->AsObject();
				if (!L || !L->GetBoolField(TEXT("camera"))) continue;
				const TArray<TSharedPtr<FJsonValue>>* Rot = nullptr;
				FVector Euler(0.);
				if (L->TryGetArrayField(TEXT("rot"), Rot) && Rot->Num() == 2) Euler = FVector((*Rot)[0]->AsNumber(), (*Rot)[1]->AsNumber(), 0.);
				// Unity's light shines along +Z, an Unreal light along +X.
				const FQuat Turn(FVector::UpVector, UE_HALF_PI);
				const FQuat Child = UnityToUe(FVector::ZeroVector, FVector(40.f, 180.f, 0.f), FVector::OneVector).GetRotation();
				const FQuat Shine = UnityToUe(FVector::ZeroVector, Euler, FVector::OneVector).GetRotation() * Child * Turn;
				const int32 LightId = Document->AddObject(EOKSceneObjectKind::Light, TEXT("Studio character light"), -1);
				FOKSceneObject* Obj = Document->Find(LightId);
				Obj->Transform = FTransform(Shine);
				FOKSceneLight& Light = Obj->Light;
				Light.Type = int32(L->GetNumberField(TEXT("kind"))) == 1 ? EOKSceneLightType::Directional : EOKSceneLightType::Point;
				const TSharedPtr<FJsonObject>* C = nullptr;
				if (L->TryGetObjectField(TEXT("color"), C)) Light.Color = Color(*C);
				Light.Intensity = float(L->GetNumberField(TEXT("intensity"))) * (Light.Type == EOKSceneLightType::Directional ? 4.f : 800.f);
				Light.bShadows = L->GetBoolField(TEXT("shadow"));
				// Studio's character light lights the characters and items, not the map.
				Light.bCharactersOnly = true;
				if (Light.Type == EOKSceneLightType::Directional && CharaLightId < 0) CharaLightId = LightId;
				++Report.Lights;
			}
	}
	bool bLinkCharaLight = false;
	FVector2D LinkedLightBase(0., 0.), LinkedCamBase(0., 0.);
	const TSharedPtr<FJsonObject>* LinkedLightObj = nullptr;
	if (CharaLightId >= 0 && Scene->TryGetObjectField(TEXT("chara_light_linked_to_camera"), LinkedLightObj) && LinkedLightObj && (*LinkedLightObj).IsValid())
	{
		bool bLocked = false;
		(*LinkedLightObj)->TryGetBoolField(TEXT("locked"), bLocked);
		const TArray<TSharedPtr<FJsonValue>>* LA = nullptr;
		const TArray<TSharedPtr<FJsonValue>>* CA = nullptr;
		if (bLocked
			&& (*LinkedLightObj)->TryGetArrayField(TEXT("light_angle"), LA) && LA->Num() == 2
			&& (*LinkedLightObj)->TryGetArrayField(TEXT("camera_angle"), CA) && CA->Num() == 2)
		{
			LinkedLightBase = FVector2D((*LA)[0]->AsNumber(), (*LA)[1]->AsNumber());
			LinkedCamBase = FVector2D((*CA)[0]->AsNumber(), (*CA)[1]->AsNumber());
			bLinkCharaLight = true;
		}
	}
	Document->CharaLightId = CharaLightId;
	Document->bLinkCharaLightToCamera = bLinkCharaLight;
	Document->LinkedLightBase = LinkedLightBase;
	Document->LinkedCameraBase = LinkedCamBase;
	const TSharedPtr<FJsonObject>* LightSettingsObj = nullptr;
	if (Scene->TryGetObjectField(TEXT("light_settings"), LightSettingsObj) && LightSettingsObj && (*LightSettingsObj).IsValid())
	{
		double GlobalStrength = -1.;
		if ((*LightSettingsObj)->TryGetNumberField(TEXT("shadow_strength"), GlobalStrength) && FMath::IsFinite(GlobalStrength))
		{
			const float Clamped = float(FMath::Clamp(GlobalStrength, 0., 1.));
			for (FOKSceneObject& Obj : Document->Objects)
				if (Obj.Kind == EOKSceneObjectKind::Light) Obj.Light.ShadowStrength = Clamped;
		}
		const TArray<TSharedPtr<FJsonValue>>* LightEntries = nullptr;
		if ((*LightSettingsObj)->TryGetArrayField(TEXT("lights"), LightEntries))
		{
			for (const TSharedPtr<FJsonValue>& EntryVal : *LightEntries)
			{
				const TSharedPtr<FJsonObject> Entry = EntryVal->AsObject();
				if (!Entry) continue;
				int32 ObjKey = 0;
				if (!Entry->TryGetNumberField(TEXT("object_id"), ObjKey)) continue;
				const int32 TargetId = (ObjKey == -10) ? CharaLightId : (Importer.KeyToId.Find(ObjKey) ? *Importer.KeyToId.Find(ObjKey) : -1);
				FOKSceneObject* TargetObj = Document->Find(TargetId);
				if (!TargetObj || TargetObj->Kind != EOKSceneObjectKind::Light) continue;
				bool bLightEnable = TargetObj->bVisible; if (Entry->TryGetBoolField(TEXT("enable"), bLightEnable)) TargetObj->bVisible = bLightEnable;
				bool bLightShadows = TargetObj->Light.bShadows;
				if (Entry->TryGetBoolField(TEXT("shadows"), bLightShadows)) TargetObj->Light.bShadows = bLightShadows;
				double EntryStrength = 0.;
				if (Entry->TryGetNumberField(TEXT("shadow_strength"), EntryStrength) && FMath::IsFinite(EntryStrength))
					TargetObj->Light.ShadowStrength = float(FMath::Clamp(EntryStrength, 0., 1.));
			}
		}
	}
	// MMDD (MMD Director / KKVMDPlay) motion speeds, durations, and evaluated VMD camera timeline track.
	const TSharedPtr<FJsonObject>* Mmdd = nullptr;
	if (Scene->TryGetObjectField(TEXT("mmdd"), Mmdd) && Mmdd && (*Mmdd).IsValid())
	{
		double TotalFrameLen = 0.;
		if ((*Mmdd)->TryGetNumberField(TEXT("total_frame_len"), TotalFrameLen) && TotalFrameLen > 0.)
		{
			double Fps = 30.;
			(*Mmdd)->TryGetNumberField(TEXT("fps"), Fps);
			Document->Duration = FMath::Max(Document->Duration, float(TotalFrameLen / FMath::Max(Fps, 1.)));
		}
		const TArray<TSharedPtr<FJsonValue>>* Motions = nullptr;
		if ((*Mmdd)->TryGetArrayField(TEXT("motions"), Motions))
		{
			for (const TSharedPtr<FJsonValue>& MVal : *Motions)
			{
				const TSharedPtr<FJsonObject> M = MVal->AsObject();
				if (!M) continue;
				const int32 CharKey = int32(M->GetNumberField(TEXT("char_key")));
				const int32* ObjId = Importer.KeyToId.Find(CharKey);
				if (!ObjId) continue;
				if (FOKSceneObject* CharObj = Document->Find(*ObjId))
				{
					FString SolvedAnim;
					if (M->TryGetStringField(TEXT("okanim"), SolvedAnim) && !SolvedAnim.IsEmpty() && FPaths::FileExists(SolvedAnim))
					{
						CharObj->Character.AnimFile = SolvedAnim;
						CharObj->Character.StudioAnimeKind = 0;
						CharObj->Character.StudioAnimeGroup = -1;
						CharObj->Character.StudioAnimeCategory = -1;
						CharObj->Character.StudioAnimeNo = -1;
						CharObj->Character.Fk.Reset();
						CharObj->Character.Ik.Reset();
						CharObj->Character.HandLeft = -1;
						CharObj->Character.HandRight = -1;
						CharObj->Character.NeckLook = EOKSceneLook::Animation;
						CharObj->Character.EyesLook = EOKSceneLook::Animation;
						CharObj->Character.FixedNeck.Reset();
						CharObj->Character.FixedEyes.Reset();
						CharObj->Character.EyebrowPattern = -1;
						CharObj->Character.EyesPattern = -1;
						CharObj->Character.MouthPattern = -1;
						CharObj->Character.MouthOpen = -1.f;
						CharObj->Character.Blink = 0;
					}
					double Speed = 1., Duration = 0.;
					if (SolvedAnim.IsEmpty() && M->TryGetNumberField(TEXT("playback_speed"), Speed) && Speed > 0.) CharObj->Character.Speed = float(Speed);
					if (M->TryGetNumberField(TEXT("duration"), Duration) && Duration > 0.) Document->Duration = FMath::Max(Document->Duration, float(Duration));
				}
			}
		}
		const TArray<TSharedPtr<FJsonValue>>* Sounds = nullptr;
		if ((*Mmdd)->TryGetArrayField(TEXT("sounds"), Sounds))
		{
			for (const TSharedPtr<FJsonValue>& SVal : *Sounds)
			{
				const TSharedPtr<FJsonObject> S = SVal->AsObject();
				if (!S) continue;
				bool bEn = true;
				S->TryGetBoolField(TEXT("enable"), bEn);
				if (!bEn) continue;
				FString ResolvedSound;
				if (!S->TryGetStringField(TEXT("resolved_sound"), ResolvedSound) || ResolvedSound.IsEmpty())
					S->TryGetStringField(TEXT("sound_file"), ResolvedSound);
				if (!ResolvedSound.IsEmpty() && FPaths::FileExists(ResolvedSound))
				{
					Document->SoundFile = ResolvedSound;
					double Delay = 0.0;
					if (S->TryGetNumberField(TEXT("delay"), Delay)) Document->SoundDelay = float(Delay);
					Importer.Note(TEXT("MMDD audio track imported"));
					break;
				}
			}
		}
		const TArray<TSharedPtr<FJsonValue>>* Cameras = nullptr;
		if ((*Mmdd)->TryGetArrayField(TEXT("cameras"), Cameras))
		{
			for (const TSharedPtr<FJsonValue>& CVal : *Cameras)
			{
				const TSharedPtr<FJsonObject> C = CVal->AsObject();
				if (!C || !C->GetBoolField(TEXT("enable"))) continue;
				const TArray<TSharedPtr<FJsonValue>>* Keyframes = nullptr;
				if (!C->TryGetArrayField(TEXT("keyframes"), Keyframes) || Keyframes->IsEmpty()) continue;
				const int32 MmddCamId = Document->AddObject(EOKSceneObjectKind::Camera, TEXT("MMDD camera"), -1);
				FOKSceneObject* MmddCam = Document->Find(MmddCamId);
				FOKSceneObject* LightObj = bLinkCharaLight ? Document->Find(CharaLightId) : nullptr;
				const float LightIntensity = LightObj ? LightObj->Light.Intensity : 0.f;
				FOKSceneTrack CamTrack;
				CamTrack.ObjectId = MmddCamId;
				CamTrack.bSmoothPath = false;
				FOKSceneTrack LightTrack;
				LightTrack.ObjectId = CharaLightId;
				LightTrack.bSmoothPath = false;
				const FQuat CamTurn = MmddCamTurn();
				const FQuat LightChild = UnityToUe(FVector::ZeroVector, FVector(40.f, 180.f, 0.f), FVector::OneVector).GetRotation();
				for (int32 K = 0; K < Keyframes->Num(); ++K)
				{
					const TSharedPtr<FJsonObject> Kf = (*Keyframes)[K]->AsObject();
					if (!Kf) continue;
					const FVector Rot = Vec3(Kf, TEXT("rot"));
					FTransform T;
					float HorizFov;
					MmddCameraKey(Kf, T, HorizFov);
					if (K == 0)
					{
						MmddCam->Transform = T;
						MmddCam->Camera.Fov = HorizFov;
					}
					FOKSceneKey Key;
					Key.Time = float(Kf->GetNumberField(TEXT("time")));
					Key.Ease = EOKSceneEase::Linear;
					Key.Transform = T;
					Key.Value = HorizFov;
					Document->Duration = FMath::Max(Document->Duration, Key.Time);
					if (LightObj)
					{
						const FVector LightEuler = ComputeLinkedCharaLightEuler(LinkedLightBase, LinkedCamBase, FVector2D(Rot.X, Rot.Y));
						const FQuat LightShine = UnityToUe(FVector::ZeroVector, LightEuler, FVector::OneVector).GetRotation() * LightChild * CamTurn;
						if (K == 0) LightObj->Transform = FTransform(LightShine);
						FOKSceneKey LightKey;
						LightKey.Time = Key.Time;
						LightKey.Ease = EOKSceneEase::Linear;
						LightKey.Transform = FTransform(LightShine);
						LightKey.Value = LightIntensity;
						LightTrack.Keys.Add(MoveTemp(LightKey));
					}
					CamTrack.Keys.Add(MoveTemp(Key));
				}
				if (!CamTrack.Keys.IsEmpty())
				{
					Document->Tracks.Add(MoveTemp(CamTrack));
					Document->ActiveCamera = MmddCamId;
					++Report.Cameras;
					Document->Post.bDepthOfField = false;
					Importer.Note(TEXT("MMDD VMD camera track imported"));
					if (!LightTrack.Keys.IsEmpty())
					{
						Document->Tracks.Add(MoveTemp(LightTrack));
						Importer.Note(TEXT("StudioCharaLightLinkedToCamera track attached to character light"));
					}
				}
				break;
			}
		}
	}
	// VNGE (Visual Novel Game Engine) KFA keyframe clips and SceneSaveState (SSS) tracks.
	const TSharedPtr<FJsonObject>* Vnge = nullptr;
	if (Scene->TryGetObjectField(TEXT("vnge"), Vnge) && Vnge && (*Vnge).IsValid())
	{
		const TArray<TSharedPtr<FJsonValue>>* Clips = nullptr;
		if ((*Vnge)->TryGetArrayField(TEXT("clips"), Clips) && !Clips->IsEmpty())
		{
			// Build alias -> ObjectId lookup from vnge.registry (actors, props, lights).
			TMap<FString, int32> AliasToId;
			const TSharedPtr<FJsonObject>* Registry = nullptr;
			if ((*Vnge)->TryGetObjectField(TEXT("registry"), Registry) && Registry && (*Registry).IsValid())
			{
				auto MapSection = [&](const TCHAR* Section)
				{
					const TSharedPtr<FJsonObject>* SecObj = nullptr;
					if ((*Registry)->TryGetObjectField(Section, SecObj) && SecObj && (*SecObj).IsValid())
					{
						for (const TPair<FString, TSharedPtr<FJsonValue>>& Pair : (*SecObj)->Values)
						{
							const int32 DicKey = int32(Pair.Value->AsNumber());
							if (const int32* Id = Importer.KeyToId.Find(DicKey)) AliasToId.Add(Pair.Key, *Id);
						}
					}
				};
				MapSection(TEXT("actors"));
				MapSection(TEXT("props"));
				MapSection(TEXT("lights"));
			}
			for (const TPair<int32, int32>& Pair : Importer.KeyToId)
			{
				AliasToId.FindOrAdd(FString::Printf(TEXT("%d"), Pair.Key), Pair.Value);
			}

			// Import the first non-empty KFA clip's per-object keyframes onto Document->Tracks.
			for (const TSharedPtr<FJsonValue>& ClipVal : *Clips)
			{
				const TSharedPtr<FJsonObject> Clip = ClipVal->AsObject();
				if (!Clip) continue;
				const TArray<TSharedPtr<FJsonValue>>* Kfs = nullptr;
				if (!Clip->TryGetArrayField(TEXT("keyframes"), Kfs) || Kfs->IsEmpty()) continue;
				TMap<int32, FOKSceneTrack> ObjTracks;
				for (const TSharedPtr<FJsonValue>& KfVal : *Kfs)
				{
					const TSharedPtr<FJsonObject> Kf = KfVal->AsObject();
					if (!Kf) continue;
					const float Time = float(Kf->GetNumberField(TEXT("time")));
					const TSharedPtr<FJsonObject>* Props = nullptr;
					if (!Kf->TryGetObjectField(TEXT("props"), Props) || !Props || !(*Props).IsValid()) continue;
					for (const TPair<FString, TSharedPtr<FJsonValue>>& Entry : (*Props)->Values)
					{
						FString Alias, PropName;
						if (!Entry.Key.Split(TEXT("."), &Alias, &PropName)) continue;
						const int32* ObjId = AliasToId.Find(Alias);
						if (!ObjId) continue;
						const FOKSceneObject* BaseObj = Document->Find(*ObjId);
						if (!BaseObj) continue;
						FOKSceneTrack& Track = ObjTracks.FindOrAdd(*ObjId);
						Track.ObjectId = *ObjId;
						FOKSceneKey* Key = Track.Keys.FindByPredicate([Time](const FOKSceneKey& Existing) { return FMath::IsNearlyEqual(Existing.Time, Time, 1e-3f); });
						if (!Key)
						{
							FOKSceneKey NewKey;
							NewKey.Time = Time;
							NewKey.Transform = BaseObj->Transform;
							Key = &Track.Keys.Add_GetRef(MoveTemp(NewKey));
						}
						if (PropName == TEXT("pos") && Entry.Value->Type == EJson::Array && Entry.Value->AsArray().Num() == 3)
						{
							const auto& A = Entry.Value->AsArray();
							const FVector P(A[0]->AsNumber(), A[1]->AsNumber(), A[2]->AsNumber());
							Key->Transform.SetLocation(FVector(-P.X, P.Z, P.Y) * 100.0);
						}
						else if ((PropName == TEXT("rot") || PropName == TEXT("angle")) && Entry.Value->Type == EJson::Array && Entry.Value->AsArray().Num() == 3)
						{
							const auto& A = Entry.Value->AsArray();
							const FVector R(A[0]->AsNumber(), A[1]->AsNumber(), A[2]->AsNumber());
							FQuat Q = UnityToUe(FVector::ZeroVector, R, FVector::OneVector).GetRotation();
							if (BaseObj->Kind == EOKSceneObjectKind::Camera || BaseObj->Kind == EOKSceneObjectKind::Light)
								Q = Q * FQuat(FVector::UpVector, UE_HALF_PI);
							Key->Transform.SetRotation(Q);
						}
						else if (PropName == TEXT("eyebrow_ptn")) { Key->bCharacterState = true; Key->EyebrowPattern = int32(Entry.Value->AsNumber()); }
						else if (PropName == TEXT("eyes_ptn")) { Key->bCharacterState = true; Key->EyesPattern = int32(Entry.Value->AsNumber()); }
						else if (PropName == TEXT("mouth_ptn")) { Key->bCharacterState = true; Key->MouthPattern = int32(Entry.Value->AsNumber()); }
						else if (PropName == TEXT("mouth_open")) { Key->bCharacterState = true; Key->MouthOpen = float(Entry.Value->AsNumber()); }
					}
					Document->Duration = FMath::Max(Document->Duration, Time);
				}
				int32 AddedTracks = 0;
				for (TPair<int32, FOKSceneTrack>& Pair : ObjTracks)
				{
					if (!Pair.Value.Keys.IsEmpty())
					{
						Document->Tracks.Add(MoveTemp(Pair.Value));
						++AddedTracks;
					}
				}
				if (AddedTracks > 0)
				{
					Importer.Note(TEXT("VNGE KFA animation tracks imported"));
					break;
				}
			}
		}
	}
	// Studio scene plugins: TreeNodeNaming, SaveCameraObjectFOV, StudioSceneSettings, MoarCamz, KKPE, NodesConstraints, Timeline.
	{
		auto JsonFloats = [](const TSharedPtr<FJsonObject>& Obj, const TCHAR* Key, TArray<float>& Out) -> bool
		{
			Out.Reset();
			const TArray<TSharedPtr<FJsonValue>>* Arr = nullptr;
			if (!Obj || !Obj->TryGetArrayField(Key, Arr)) return false;
			Out.Reserve(Arr->Num());
			for (const TSharedPtr<FJsonValue>& V : *Arr) Out.Add(float(V->AsNumber()));
			return true;
		};
		auto JsonBools3 = [](const TSharedPtr<FJsonObject>& Obj, const TCHAR* Key, bool& X, bool& Y, bool& Z)
		{
			const TArray<TSharedPtr<FJsonValue>>* Arr = nullptr;
			if (Obj && Obj->TryGetArrayField(Key, Arr) && Arr->Num() >= 3)
			{
				X = (*Arr)[0]->AsBool();
				Y = (*Arr)[1]->AsBool();
				Z = (*Arr)[2]->AsBool();
			}
		};
		auto VertFovToHoriz = [](double VertDeg) -> float
		{
			const double VertRad = FMath::DegreesToRadians(FMath::Clamp(VertDeg, 1.0, 170.0));
			return float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(VertRad * 0.5) * 16.0 / 9.0)));
		};

		// 1. TreeNodeNaming (`object_names`)
		const TSharedPtr<FJsonObject>* ObjectNamesObj = nullptr;
		if (Scene->TryGetObjectField(TEXT("object_names"), ObjectNamesObj) && ObjectNamesObj && (*ObjectNamesObj).IsValid())
		{
			int32 NamedCount = 0;
			for (const TPair<FString, TSharedPtr<FJsonValue>>& Pair : (*ObjectNamesObj)->Values)
			{
				const int32 DicKey = FCString::Atoi(*Pair.Key);
				const FString CustomName = Pair.Value.IsValid() ? Pair.Value->AsString() : FString();
				if (CustomName.IsEmpty()) continue;
				if (const int32* ObjId = Importer.KeyToId.Find(DicKey))
					if (FOKSceneObject* Obj = Document->Find(*ObjId)) { Obj->Name = CustomName; ++NamedCount; }
			}
			if (NamedCount > 0) Importer.Note(TEXT("TreeNodeNaming custom names imported"));
		}

		// 2. SaveCameraObjectFOV (`camera_fovs`)
		const TSharedPtr<FJsonObject>* CameraFovsObj = nullptr;
		if (Scene->TryGetObjectField(TEXT("camera_fovs"), CameraFovsObj) && CameraFovsObj && (*CameraFovsObj).IsValid())
		{
			const TSharedPtr<FJsonObject>* CamMap = nullptr;
			if ((*CameraFovsObj)->TryGetObjectField(TEXT("cameras"), CamMap) && CamMap && (*CamMap).IsValid())
			{
				for (const TPair<FString, TSharedPtr<FJsonValue>>& Pair : (*CamMap)->Values)
				{
					const int32 DicKey = FCString::Atoi(*Pair.Key);
					if (const int32* ObjId = Importer.KeyToId.Find(DicKey))
						if (FOKSceneObject* CamObj = Document->Find(*ObjId); CamObj && CamObj->Kind == EOKSceneObjectKind::Camera && Pair.Value.IsValid())
							CamObj->Camera.Fov = VertFovToHoriz(Pair.Value->AsNumber());
				}
			}
			double MainVertFov = 0.;
			if ((*CameraFovsObj)->TryGetNumberField(TEXT("main_fov"), MainVertFov) && Document->StudioCameraId >= 0)
				if (FOKSceneObject* StudioCam = Document->Find(Document->StudioCameraId))
					StudioCam->Camera.Fov = VertFovToHoriz(MainVertFov);
			Importer.Note(TEXT("SaveCameraObjectFOV settings imported"));
		}

		// 3. MoarCamz (`moar_camz`)
		const TSharedPtr<FJsonObject>* MoarCamzObj = nullptr;
		if (Scene->TryGetObjectField(TEXT("moar_camz"), MoarCamzObj) && MoarCamzObj && (*MoarCamzObj).IsValid())
		{
			const TArray<TSharedPtr<FJsonValue>>* Slots = nullptr;
			if ((*MoarCamzObj)->TryGetArrayField(TEXT("slots"), Slots) && !Slots->IsEmpty())
			{
				int32 AddedMoar = 0;
				for (const TSharedPtr<FJsonValue>& SVal : *Slots)
				{
					const TSharedPtr<FJsonObject> S = SVal->AsObject();
					if (!S) continue;
					const int32 SlotNum = int32(S->GetNumberField(TEXT("slot")));
					FVector TargetPos = Vec3(S, TEXT("pos"));
					const FVector OffsetPos = Vec3(S, TEXT("offset_pos"));
					bool bEngaged = false;
					S->TryGetBoolField(TEXT("center_target_engaged"), bEngaged);
					if (bEngaged && TargetPos.IsNearlyZero(1e-4f))
					{
						int32 TargetKey = -1;
						if (S->TryGetNumberField(TEXT("center_target"), TargetKey))
							if (const int32* TargetId = Importer.KeyToId.Find(TargetKey))
							{
								const FVector UeLoc = Document->WorldTransform(*TargetId).GetLocation() * 0.01;
								TargetPos = FVector(-UeLoc.X, UeLoc.Z, UeLoc.Y);
							}
					}
					TargetPos += OffsetPos;
					const FVector Rot = Vec3(S, TEXT("rot"));
					const FVector Dist = Vec3(S, TEXT("distance"));
					double Fov = 23.;
					S->TryGetNumberField(TEXT("fov"), Fov);
					const int32 CamId = Document->AddObject(EOKSceneObjectKind::Camera, FString::Printf(TEXT("MoarCamz %d"), SlotNum), -1);
					if (FOKSceneObject* CamObj = Document->Find(CamId))
					{
						const FTransform Base = UnityToUe(TargetPos, Rot, FVector::OneVector);
						CamObj->Transform = FTransform(Base.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI),
							Base.GetLocation() + Base.GetRotation().RotateVector(FVector(-Dist.X, Dist.Z, Dist.Y) * 100.0));
						CamObj->Camera.Fov = VertFovToHoriz(Fov);
						++Report.Cameras;
						++AddedMoar;
						if (AddedMoar <= 10)
						{
							const int32 MarkIdx = AddedMoar - 1;
							while (Document->Bookmarks.Num() <= MarkIdx) Document->Bookmarks.AddDefaulted();
							if (!Document->Bookmarks[MarkIdx].bSet)
							{
								Document->Bookmarks[MarkIdx].bSet = true;
								Document->Bookmarks[MarkIdx].Focus = Base.GetLocation();
								Document->Bookmarks[MarkIdx].Distance = float(FMath::Max(Dist.Size() * 100.0, 10.0));
								Document->Bookmarks[MarkIdx].Camera = CamId;
							}
						}
					}
				}
				if (AddedMoar > 0) Importer.Note(TEXT("MoarCamz camera slots imported"));
			}
		}

		// 4. StudioSceneSettings (`scene_settings`)
		const TSharedPtr<FJsonObject>* SceneSettingsObj = nullptr;
		if (Scene->TryGetObjectField(TEXT("scene_settings"), SceneSettingsObj) && SceneSettingsObj && (*SceneSettingsObj).IsValid())
		{
			double NearM = 0., FarM = 0.;
			const bool bHasNear = (*SceneSettingsObj)->TryGetNumberField(TEXT("near_clip"), NearM) && NearM > 0.;
			const bool bHasFar = (*SceneSettingsObj)->TryGetNumberField(TEXT("far_clip"), FarM) && FarM > 0.;
			if (bHasNear || bHasFar)
			{
				for (FOKSceneObject& Obj : Document->Objects)
				{
					if (Obj.Kind != EOKSceneObjectKind::Camera) continue;
					if (bHasNear) Obj.Camera.Near = float(NearM * 100.0);
					if (bHasFar) Obj.Camera.Far = float(FarM * 100.0);
				}
				Importer.Note(TEXT("StudioSceneSettings clip planes imported"));
			}
		}

		// 5. KKPE (`kkpe` character & item bone TRS + blendshapes)
		const TSharedPtr<FJsonObject>* KkpeObj = nullptr;
		if (Scene->TryGetObjectField(TEXT("kkpe"), KkpeObj) && KkpeObj && (*KkpeObj).IsValid())
		{
			auto ParseKkpeBonesAndMorphs = [&](const TSharedPtr<FJsonObject>& Elem, TArray<FOKSceneBoneTrs>& OutBones, TArray<FOKSceneMorphOverride>& OutMorphs)
			{
				const TArray<TSharedPtr<FJsonValue>>* BonesArr = nullptr;
				if (Elem->TryGetArrayField(TEXT("bones"), BonesArr))
				{
					for (const TSharedPtr<FJsonValue>& BVal : *BonesArr)
					{
						const TSharedPtr<FJsonObject> B = BVal->AsObject();
						if (!B) continue;
						FOKSceneBoneTrs Trs;
						if (!B->TryGetStringField(TEXT("bone"), Trs.Bone) || Trs.Bone.IsEmpty()) continue;
						TArray<float> V;
						if (JsonFloats(B, TEXT("pos"), V) && V.Num() >= 3) { Trs.bHasPos = true; Trs.Pos = FVector(V[0], V[1], V[2]); }
						if (JsonFloats(B, TEXT("euler"), V) && V.Num() >= 3) { Trs.bHasRot = true; Trs.Euler = FVector(V[0], V[1], V[2]); }
						if (JsonFloats(B, TEXT("scale"), V) && V.Num() >= 3) { Trs.bHasScale = true; Trs.Scale = FVector(V[0], V[1], V[2]); }
						if (Trs.bHasPos || Trs.bHasRot || Trs.bHasScale) OutBones.Add(MoveTemp(Trs));
					}
				}
				const TArray<TSharedPtr<FJsonValue>>* MorphsArr = nullptr;
				if (Elem->TryGetArrayField(TEXT("morphs"), MorphsArr))
				{
					for (const TSharedPtr<FJsonValue>& MVal : *MorphsArr)
					{
						const TSharedPtr<FJsonObject> M = MVal->AsObject();
						if (!M) continue;
						FOKSceneMorphOverride Morph;
						if (!M->TryGetStringField(TEXT("renderer"), Morph.Renderer) || Morph.Renderer.IsEmpty()) continue;
						Morph.Index = int32(M->GetNumberField(TEXT("index")));
						Morph.Weight = float(FMath::Clamp(M->GetNumberField(TEXT("weight")), 0.0, 100.0));
						if (Morph.Index >= 0) OutMorphs.Add(MoveTemp(Morph));
					}
				}
			};
			int32 KkpeApplied = 0;
			const TArray<TSharedPtr<FJsonValue>>* KkpeChars = nullptr;
			if ((*KkpeObj)->TryGetArrayField(TEXT("characters"), KkpeChars))
			{
				for (const TSharedPtr<FJsonValue>& CVal : *KkpeChars)
				{
					const TSharedPtr<FJsonObject> Elem = CVal->AsObject();
					if (!Elem) continue;
					const int32* ObjId = Importer.KeyToId.Find(int32(Elem->GetNumberField(TEXT("dic_key"))));
					FOKSceneObject* Obj = ObjId ? Document->Find(*ObjId) : nullptr;
					if (!Obj || Obj->Kind != EOKSceneObjectKind::Character) continue;
					int32 Ptn = -1;
					double Open = -1.;
					if (Elem->TryGetNumberField(TEXT("eyes_ptn"), Ptn) && Ptn >= 0) Obj->Character.EyesPattern = Ptn;
					if (Elem->TryGetNumberField(TEXT("eyes_open"), Open) && Open >= 0.) Obj->Character.EyesOpen = float(FMath::Clamp(Open, 0., 1.));
					if (Elem->TryGetNumberField(TEXT("mouth_ptn"), Ptn) && Ptn >= 0) Obj->Character.MouthPattern = Ptn;
					if (Elem->TryGetNumberField(TEXT("mouth_open"), Open) && Open >= 0.) Obj->Character.MouthOpen = float(FMath::Clamp(Open, 0., 1.));
					if (Elem->TryGetNumberField(TEXT("eyebrows_ptn"), Ptn) && Ptn >= 0) Obj->Character.EyebrowPattern = Ptn;
					ParseKkpeBonesAndMorphs(Elem, Obj->Character.BoneOverrides, Obj->Character.MorphOverrides);
					++KkpeApplied;
				}
			}
			const TArray<TSharedPtr<FJsonValue>>* KkpeItems = nullptr;
			if ((*KkpeObj)->TryGetArrayField(TEXT("items"), KkpeItems))
			{
				for (const TSharedPtr<FJsonValue>& IVal : *KkpeItems)
				{
					const TSharedPtr<FJsonObject> Elem = IVal->AsObject();
					if (!Elem) continue;
					const int32* ObjId = Importer.KeyToId.Find(int32(Elem->GetNumberField(TEXT("dic_key"))));
					FOKSceneObject* Obj = ObjId ? Document->Find(*ObjId) : nullptr;
					if (!Obj || Obj->Kind != EOKSceneObjectKind::Item) continue;
					ParseKkpeBonesAndMorphs(Elem, Obj->Item.BoneOverrides, Obj->Item.MorphOverrides);
					++KkpeApplied;
				}
			}
			if (KkpeApplied > 0) Importer.Note(TEXT("KKPE bone TRS & blendshape overrides imported"));
		}

		// 6. NodesConstraints & KK_AnimationController (`constraints`)
		const TArray<TSharedPtr<FJsonValue>>* ConstraintsArr = nullptr;
		if (Scene->TryGetArrayField(TEXT("constraints"), ConstraintsArr) && !ConstraintsArr->IsEmpty())
		{
			for (const TSharedPtr<FJsonValue>& CVal : *ConstraintsArr)
			{
				const TSharedPtr<FJsonObject> C = CVal->AsObject();
				if (!C) continue;
				const int32 ParentKey = int32(C->GetNumberField(TEXT("parent_key")));
				const int32 ChildKey = int32(C->GetNumberField(TEXT("child_key")));
				int32 ParentId = -1;
				if (ParentKey == -2) ParentId = -2;
				else if (const int32* FoundP = Importer.KeyToId.Find(ParentKey)) ParentId = *FoundP;
				else continue;
				const int32* FoundC = Importer.KeyToId.Find(ChildKey);
				if (!FoundC) continue;

				FOKSceneConstraint Con;
				Con.LoadId = int32(C->GetNumberField(TEXT("load_id")));
				C->TryGetBoolField(TEXT("enabled"), Con.bEnabled);
				Con.ParentId = ParentId;
				C->TryGetStringField(TEXT("parent_bone"), Con.ParentBone);
				Con.ChildId = *FoundC;
				C->TryGetStringField(TEXT("child_bone"), Con.ChildBone);
				C->TryGetNumberField(TEXT("child_ik_effector"), Con.ChildIkEffector);
				C->TryGetBoolField(TEXT("position"), Con.bPosition);
				C->TryGetBoolField(TEXT("mirror_position"), Con.bMirrorPosition);
				C->TryGetBoolField(TEXT("rotation"), Con.bRotation);
				C->TryGetBoolField(TEXT("mirror_rotation"), Con.bMirrorRotation);
				C->TryGetBoolField(TEXT("look_at"), Con.bLookAt);
				C->TryGetBoolField(TEXT("scale"), Con.bScale);
				C->TryGetBoolField(TEXT("mirror_scale"), Con.bMirrorScale);
				TArray<float> V;
				if (JsonFloats(C, TEXT("pos_offset"), V) && V.Num() >= 3) Con.PositionOffset = FVector(V[0], V[1], V[2]);
				if (JsonFloats(C, TEXT("rot_offset"), V) && V.Num() >= 4) Con.RotationOffset = FQuat(V[0], V[1], V[2], V[3]).GetNormalized();
				if (JsonFloats(C, TEXT("scale_offset"), V) && V.Num() >= 3) Con.ScaleOffset = FVector(V[0], V[1], V[2]);
				if (JsonFloats(C, TEXT("orig_parent_pos"), V) && V.Num() >= 3) Con.OrigParentPos = FVector(V[0], V[1], V[2]);
				if (JsonFloats(C, TEXT("orig_parent_rot"), V) && V.Num() >= 4) Con.OrigParentRot = FQuat(V[0], V[1], V[2], V[3]).GetNormalized();
				if (JsonFloats(C, TEXT("orig_parent_scale"), V) && V.Num() >= 3) Con.OrigParentScale = FVector(V[0], V[1], V[2]);
				double Factor = 1.;
				if (C->TryGetNumberField(TEXT("pos_factor"), Factor)) Con.PosFactor = float(Factor);
				if (C->TryGetNumberField(TEXT("rot_factor"), Factor)) Con.RotFactor = float(Factor);
				if (C->TryGetNumberField(TEXT("scale_factor"), Factor)) Con.ScaleFactor = float(Factor);
				JsonBools3(C, TEXT("pos_locks"), Con.bLockPosX, Con.bLockPosY, Con.bLockPosZ);
				JsonBools3(C, TEXT("rot_locks"), Con.bLockRotX, Con.bLockRotY, Con.bLockRotZ);
				JsonBools3(C, TEXT("scale_locks"), Con.bLockScaleX, Con.bLockScaleY, Con.bLockScaleZ);
				Document->Constraints.Add(MoveTemp(Con));
			}
			if (!Document->Constraints.IsEmpty()) Importer.Note(TEXT("NodesConstraints parent-child constraints imported"));
		}

		// 7. Timeline (`timeline`)
		const TSharedPtr<FJsonObject>* TimelineObj = nullptr;
		if (Scene->TryGetObjectField(TEXT("timeline"), TimelineObj) && TimelineObj && (*TimelineObj).IsValid())
		{
			double TlDuration = 0.;
			if ((*TimelineObj)->TryGetNumberField(TEXT("duration"), TlDuration) && TlDuration > 0.)
				Document->Duration = FMath::Max(Document->Duration, float(TlDuration));
			const TArray<TSharedPtr<FJsonValue>>* TlTracks = nullptr;
			if ((*TimelineObj)->TryGetArrayField(TEXT("tracks"), TlTracks) && !TlTracks->IsEmpty())
			{
				for (const TSharedPtr<FJsonValue>& TVal : *TlTracks)
				{
					const TSharedPtr<FJsonObject> T = TVal->AsObject();
					if (!T) continue;
					FOKSceneTimelineTrack Track;
					T->TryGetStringField(TEXT("owner"), Track.Owner);
					T->TryGetStringField(TEXT("id"), Track.InterpolableId);
					const int32 DicKey = int32(T->GetNumberField(TEXT("dic_key")));
					if (DicKey < 0) Track.ObjectId = -1;
					else if (const int32* FoundId = Importer.KeyToId.Find(DicKey)) Track.ObjectId = *FoundId;
					else if (Track.Owner == TEXT("NodesConstraints")) Track.ObjectId = -1;
					else continue;
					T->TryGetStringField(TEXT("target_path"), Track.TargetPath);
					T->TryGetStringField(TEXT("target_bone"), Track.TargetBone);
					T->TryGetNumberField(TEXT("target_ik_effector"), Track.TargetIkEffector);
					T->TryGetNumberField(TEXT("param_int"), Track.ParamInt);
					const TArray<TSharedPtr<FJsonValue>>* Kfs = nullptr;
					if (!T->TryGetArrayField(TEXT("keyframes"), Kfs) || Kfs->IsEmpty()) continue;
					Track.Keyframes.Reserve(Kfs->Num());
					for (const TSharedPtr<FJsonValue>& KfVal : *Kfs)
					{
						const TSharedPtr<FJsonObject> KfObj = KfVal->AsObject();
						if (!KfObj) continue;
						FOKSceneTimelineKeyframe Kf;
						Kf.Time = float(KfObj->GetNumberField(TEXT("time")));
						JsonFloats(KfObj, TEXT("values"), Kf.Values);
						const TArray<TSharedPtr<FJsonValue>>* NamesArr = nullptr;
						if (KfObj->TryGetArrayField(TEXT("names"), NamesArr))
							for (const TSharedPtr<FJsonValue>& NVal : *NamesArr) Kf.Names.Add(NVal->AsString());
						const TArray<TSharedPtr<FJsonValue>>* CurveArr = nullptr;
						if (KfObj->TryGetArrayField(TEXT("curve"), CurveArr))
						{
							Kf.Curve.Reserve(CurveArr->Num());
							for (const TSharedPtr<FJsonValue>& PtVal : *CurveArr)
							{
								const TSharedPtr<FJsonObject> PtObj = PtVal->AsObject();
								if (!PtObj) continue;
								FOKSceneTimelineCurvePt Pt;
								Pt.Time = float(PtObj->GetNumberField(TEXT("t")));
								Pt.Value = float(PtObj->GetNumberField(TEXT("v")));
								Pt.InTangent = float(PtObj->GetNumberField(TEXT("in_t")));
								Pt.OutTangent = float(PtObj->GetNumberField(TEXT("out_t")));
								Kf.Curve.Add(Pt);
							}
						}
						Track.Keyframes.Add(MoveTemp(Kf));
					}
					if (!Track.Keyframes.IsEmpty()) Document->TimelineTracks.Add(MoveTemp(Track));
				}
				if (!Document->TimelineTracks.IsEmpty())
				{
					Document->bLoopTimeline = true;
					Document->EvaluateTimeline(0.f);
					Importer.Note(TEXT("Timeline tracks imported"));
				}
			}
		}
	}
	for (const TPair<FString, int32>& N : Importer.Notes) Report.Notes.Add(FString::Printf(TEXT("%s (%d)"), *N.Key, N.Value));
	Document->NotifyChanged();
	return true;
}

bool FOKStudioImport::ImportToFile(const FString& ScenePng, FString& OutScene, FReport& Report, FString& OutError)
{
	const FString Name = FPaths::GetBaseFilename(ScenePng);
	const FString Dir = UOKStudioGame::SceneDirectory();
	UOKSceneDocument* Document = NewObject<UOKSceneDocument>();
	if (!Import(ScenePng, Document, Dir / (Name + TEXT("_cards")), Report, OutError)) return false;
	// The file of an earlier import may hold what was saved over it: opening the card again took those changes away
	// without a word (U220). It stays, and this import goes to the next free name; an unchanged one is used again.
	const FString Json = Document->ToJson();
	FString Base = Name, Old;
	for (int32 N = 2; FFileHelper::LoadFileToString(Old, *(Dir / (Base + TEXT(".okscene")))) && Old != Json; ++N) Base = FString::Printf(TEXT("%s_%d"), *Name, N);
	OutScene = Dir / (Base + TEXT(".okscene"));
	if (!Document->SaveToFile(OutScene, OutError)) return false;
	FFileHelper::SaveStringToFile(Report.ToJson(), *(Dir / (Base + TEXT(".import.json"))), FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
	return true;
}
