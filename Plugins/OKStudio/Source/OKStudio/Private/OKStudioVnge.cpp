#include "OKStudioVnge.h"
#include "OKSceneDocument.h"
#include "OKSceneActor.h"
#include "OKStudioGame.h"
#include "OKStudioImport.h"
#include "OKStudioCatalog.h"
#include "OKStudioPose.h"
#include "KKPreviewActor.h"
#include "KKSpeech.h"
#include "AudioDevice.h"
#include "Components/AudioComponent.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"
#include "Engine/Texture2D.h"
#include "Engine/World.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "JsonObjectConverter.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "ok_extract.h"

namespace
{
	FString SerializeJsonValue(const TSharedPtr<FJsonValue>& Val)
	{
		if (!Val.IsValid() || Val->IsNull()) return FString();
		FString Out;
		if (Val->Type == EJson::Object)
		{
			FJsonSerializer::Serialize(Val->AsObject().ToSharedRef(), TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out));
		}
		else if (Val->Type == EJson::Array)
		{
			FJsonSerializer::Serialize(Val->AsArray(), TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out));
		}
		else if (Val->Type == EJson::String)
		{
			Out = Val->AsString();
		}
		return Out;
	}

	bool ReadVec3(const TSharedPtr<FJsonObject>& Obj, const TCHAR* Key, FVector& Out)
	{
		const TArray<TSharedPtr<FJsonValue>>* Arr = nullptr;
		if (Obj && Obj->TryGetArrayField(Key, Arr) && Arr->Num() >= 3)
		{
			Out = FVector(float((*Arr)[0]->AsNumber()), float((*Arr)[1]->AsNumber()), float((*Arr)[2]->AsNumber()));
			return true;
		}
		const TSharedPtr<FJsonObject>* Sub = nullptr;
		if (Obj && Obj->TryGetObjectField(Key, Sub) && Sub && Sub->IsValid())
		{
			Out = FVector(float((*Sub)->GetNumberField(TEXT("x"))), float((*Sub)->GetNumberField(TEXT("y"))), float((*Sub)->GetNumberField(TEXT("z"))));
			return true;
		}
		return false;
	}

	bool ReadVec4Color(const TSharedPtr<FJsonObject>& Obj, const TCHAR* Key, FLinearColor& Out)
	{
		const TArray<TSharedPtr<FJsonValue>>* Arr = nullptr;
		if (Obj && Obj->TryGetArrayField(Key, Arr) && Arr->Num() >= 3)
		{
			const float A = Arr->Num() >= 4 ? float((*Arr)[3]->AsNumber()) : 1.f;
			Out = FLinearColor(float((*Arr)[0]->AsNumber()), float((*Arr)[1]->AsNumber()), float((*Arr)[2]->AsNumber()), A);
			return true;
		}
		return false;
	}

	FVector UnityQuatToEulerDeg(const FQuat& QIn)
	{
		// Unity rotation order ZXY: R = Ry(y) * Rx(x) * Rz(z)
		const FQuat Q = QIn.GetNormalized();
		const double X = Q.X, Y = Q.Y, Z = Q.Z, W = Q.W;
		const double SinX = FMath::Clamp(2.0 * (W * X - Y * Z), -1.0, 1.0);
		const double Rx = FMath::Asin(SinX);
		double Ry = 0.0, Rz = 0.0;
		if (FMath::Abs(SinX) < 0.999999)
		{
			Ry = FMath::Atan2(2.0 * (X * Z + W * Y), 1.0 - 2.0 * (X * X + Y * Y));
			Rz = FMath::Atan2(2.0 * (X * Y + W * Z), 1.0 - 2.0 * (X * X + Z * Z));
		}
		else
		{
			Ry = FMath::Atan2(-2.0 * (X * Z - W * Y), 1.0 - 2.0 * (Y * Y + Z * Z));
			Rz = 0.0;
		}
		auto Wrap360 = [](double Rad) -> float
		{
			double Deg = FMath::Fmod(FMath::RadiansToDegrees(Rad), 360.0);
			if (Deg < 0.0) Deg += 360.0;
			return float(Deg);
		};
		return FVector(Wrap360(Rx), Wrap360(Ry), Wrap360(Rz));
	}

	FQuat UnityEulerDegToQuat(const FVector& EulerDegrees)
	{
		const FQuat Qx(FVector(1, 0, 0), FMath::DegreesToRadians(EulerDegrees.X));
		const FQuat Qy(FVector(0, 1, 0), FMath::DegreesToRadians(EulerDegrees.Y));
		const FQuat Qz(FVector(0, 0, 1), FMath::DegreesToRadians(EulerDegrees.Z));
		return (Qy * Qx * Qz).GetNormalized();
	}

	FVector UeTransformToUnityPosM(const FTransform& T)
	{
		const FVector P = T.GetLocation() * 0.01f;
		return FVector(-P.X, P.Z, P.Y);
	}

	FVector UeQuatToUnityEulerDeg(const FQuat& QIn)
	{
		const FQuat Q = QIn.GetNormalized();
		const FQuat U(-Q.X, Q.Z, Q.Y, Q.W);
		return UnityQuatToEulerDeg(U);
	}

	bool ReadUnityEulerOrQuatVal(const TSharedPtr<FJsonValue>& Val, FVector& OutEuler)
	{
		if (!Val.IsValid()) return false;
		if (Val->Type == EJson::Array)
		{
			const TArray<TSharedPtr<FJsonValue>>& Arr = Val->AsArray();
			if (Arr.Num() == 4)
			{
				const FQuat U(float(Arr[0]->AsNumber()), float(Arr[1]->AsNumber()), float(Arr[2]->AsNumber()), float(Arr[3]->AsNumber()));
				OutEuler = UnityQuatToEulerDeg(U);
				return true;
			}
			if (Arr.Num() >= 3)
			{
				OutEuler = FVector(float(Arr[0]->AsNumber()), float(Arr[1]->AsNumber()), float(Arr[2]->AsNumber()));
				return true;
			}
		}
		else if (Val->Type == EJson::Object)
		{
			const TSharedPtr<FJsonObject> Obj = Val->AsObject();
			double W = 0.;
			if (Obj->TryGetNumberField(TEXT("w"), W))
			{
				const FQuat U(float(Obj->GetNumberField(TEXT("x"))), float(Obj->GetNumberField(TEXT("y"))), float(Obj->GetNumberField(TEXT("z"))), float(W));
				OutEuler = UnityQuatToEulerDeg(U);
				return true;
			}
			OutEuler = FVector(float(Obj->GetNumberField(TEXT("x"))), float(Obj->GetNumberField(TEXT("y"))), float(Obj->GetNumberField(TEXT("z"))));
			return true;
		}
		return false;
	}

	FString ResolveFkBoneName(int32 BoneNo, const FString& ExplicitBone)
	{
		if (!ExplicitBone.IsEmpty()) return ExplicitBone;
		if (BoneNo >= 0)
		{
			if (const FOKStudioFkBone* Info = FOKStudioCatalog::Get().FkBones.FindByPredicate([BoneNo](const FOKStudioFkBone& F) { return F.No == BoneNo; }))
			{
				return Info->Bone;
			}
		}
		return FString();
	}

	bool MapVngeIkKeyToEffector(const FString& Key, int32& OutEffector, bool& OutUseRot)
	{
		struct FEntry { int32 Effector; bool bUseRot; };
		static const FEntry ByNo[13] = {
			{0, false}, {1, false}, {9, false}, {5, true},
			{2, false}, {10, false}, {6, true},
			{3, false}, {11, false}, {7, true},
			{4, false}, {12, false}, {8, true}
		};
		const FString K = Key.TrimStartAndEnd();
		if (K.IsNumeric())
		{
			const int32 No = FCString::Atoi(*K);
			if (No >= 0 && No < 13)
			{
				OutEffector = ByNo[No].Effector;
				OutUseRot = ByNo[No].bUseRot;
				return true;
			}
		}
		static const TMap<FString, int32> NamedNo = {
			{TEXT("body"), 0}, {TEXT("hips"), 0},
			{TEXT("arm_l"), 1}, {TEXT("forearm_l"), 2}, {TEXT("hand_l"), 3},
			{TEXT("arm_r"), 4}, {TEXT("forearm_r"), 5}, {TEXT("hand_r"), 6},
			{TEXT("thigh_l"), 7}, {TEXT("leg_l"), 8}, {TEXT("foot_l"), 9},
			{TEXT("thigh_r"), 10}, {TEXT("leg_r"), 11}, {TEXT("foot_r"), 12},
		};
		if (const int32* FoundNo = NamedNo.Find(K.ToLower()))
		{
			OutEffector = ByNo[*FoundNo].Effector;
			OutUseRot = ByNo[*FoundNo].bUseRot;
			return true;
		}
		return false;
	}

	void ParseFkArrayFromRust(const TArray<TSharedPtr<FJsonValue>>& FkArr, TArray<FOKVngeFkEntry>& OutFk)
	{
		for (const TSharedPtr<FJsonValue>& FV : FkArr)
		{
			const TSharedPtr<FJsonObject> FO = FV->AsObject();
			if (!FO) continue;
			int32 No = -1;
			FO->TryGetNumberField(TEXT("no"), No);
			FString Bone;
			FO->TryGetStringField(TEXT("bone"), Bone);
			Bone = ResolveFkBoneName(No, Bone);
			FVector Euler;
			if (!Bone.IsEmpty() && ReadVec3(FO, TEXT("rot"), Euler))
			{
				OutFk.Add({ Bone, Euler });
			}
		}
	}

	void ParseIkArrayFromRust(const TArray<TSharedPtr<FJsonValue>>& IkArr, TArray<FOKVngeIkEntry>& OutIk)
	{
		for (const TSharedPtr<FJsonValue>& IV : IkArr)
		{
			const TSharedPtr<FJsonObject> IO = IV->AsObject();
			if (!IO) continue;
			FOKVngeIkEntry Entry;
			Entry.Effector = int32(IO->GetNumberField(TEXT("effector")));
			ReadVec3(IO, TEXT("pos"), Entry.Pos);
			ReadVec3(IO, TEXT("rot"), Entry.Euler);
			IO->TryGetBoolField(TEXT("use_rot"), Entry.bUseRotation);
			OutIk.Add(Entry);
		}
	}

	FOKVngeObjectPatch ParseObjectStatusFromRust(const TSharedPtr<FJsonObject>& Obj, bool bIsProp, const TMap<int32, int32>& KeyToId, const FOKVngeRegistry& Reg)
	{
		FOKVngeObjectPatch P;
		P.bIsProp = bIsProp;
		if (!Obj) return P;
		Obj->TryGetStringField(TEXT("alias"), P.Alias);
		int32 DicKey = -1;
		if (Obj->TryGetNumberField(TEXT("key"), DicKey) && DicKey >= 0)
		{
			if (const int32* Mapped = KeyToId.Find(DicKey)) P.ObjectId = *Mapped;
		}
		if (P.ObjectId < 0 && !P.Alias.IsEmpty())
		{
			P.ObjectId = Reg.ResolveObjectId(P.Alias, nullptr);
		}
		bool bVis = true;
		if (Obj->TryGetBoolField(TEXT("visible"), bVis)) P.Visible = bVis ? 1 : 0;
		P.bHasPos = ReadVec3(Obj, TEXT("pos"), P.Pos);
		P.bHasRot = ReadVec3(Obj, TEXT("rot"), P.Rot);
		P.bHasScale = ReadVec3(Obj, TEXT("scale"), P.Scale);
		const TArray<TSharedPtr<FJsonValue>>* Anime = nullptr;
		if (Obj->TryGetArrayField(TEXT("anime"), Anime) && Anime->Num() >= 3)
		{
			P.AnimGroup = int32((*Anime)[0]->AsNumber());
			P.AnimCategory = int32((*Anime)[1]->AsNumber());
			P.AnimNo = int32((*Anime)[2]->AsNumber());
		}
		double Num = 0.;
		if (Obj->TryGetNumberField(TEXT("anime_speed"), Num)) P.AnimSpeed = float(Num);
		if (Obj->TryGetNumberField(TEXT("anime_time"), Num)) P.AnimTime = float(Num);
		const TArray<TSharedPtr<FJsonValue>>* FkArr = nullptr;
		if (Obj->TryGetArrayField(TEXT("fk"), FkArr)) ParseFkArrayFromRust(*FkArr, P.Fk);
		const TArray<TSharedPtr<FJsonValue>>* IkArr = nullptr;
		if (Obj->TryGetArrayField(TEXT("ik"), IkArr)) ParseIkArrayFromRust(*IkArr, P.Ik);
		Obj->TryGetNumberField(TEXT("eyebrow_ptn"), P.EyebrowPtn);
		Obj->TryGetNumberField(TEXT("eyes_ptn"), P.EyesPtn);
		if (Obj->TryGetNumberField(TEXT("eyes_open"), Num)) P.EyesOpen = float(Num);
		Obj->TryGetNumberField(TEXT("mouth_ptn"), P.MouthPtn);
		if (Obj->TryGetNumberField(TEXT("mouth_open"), Num)) P.MouthOpen = float(Num);
		Obj->TryGetNumberField(TEXT("hand_left"), P.HandLeft);
		Obj->TryGetNumberField(TEXT("hand_right"), P.HandRight);
		Obj->TryGetNumberField(TEXT("eyes_look"), P.EyesLook);
		Obj->TryGetNumberField(TEXT("neck_look"), P.NeckLook);
		Obj->TryGetNumberField(TEXT("outfit"), P.Outfit);
		const TArray<TSharedPtr<FJsonValue>>* U8Arr = nullptr;
		if (Obj->TryGetArrayField(TEXT("clothes_state"), U8Arr))
			for (const auto& V : *U8Arr) P.ClothesStates.Add(uint8(FMath::Clamp(int32(V->AsNumber()), 0, 3)));
		if (Obj->TryGetArrayField(TEXT("show_accessory"), U8Arr))
			for (const auto& V : *U8Arr) P.AccessoriesShown.Add(uint8(int32(V->AsNumber()) != 0 ? 1 : 0));
		Obj->TryGetNumberField(TEXT("tears_lv"), P.TearsLv);
		if (Obj->TryGetNumberField(TEXT("nip_stand"), Num)) P.NipStand = float(Num);
		if (Obj->TryGetArrayField(TEXT("fluids"), U8Arr))
			for (const auto& V : *U8Arr) P.Fluids.Add(uint8(FMath::Clamp(int32(V->AsNumber()), 0, 2)));
		if (Obj->TryGetNumberField(TEXT("light_intensity"), Num)) P.LightIntensity = float(Num);
		bool bLightEn = true;
		if (Obj->TryGetBoolField(TEXT("light_enable"), bLightEn)) P.LightEnable = bLightEn ? 1 : 0;
		return P;
	}

	/** Parses a raw VNGE Python/JSON pose dictionary (from PoseSaveState `.png`/`.txt` or `-ministates`) into FOKVngeObjectPatch. */
	void ParseRawPoseDictToPatch(const TSharedPtr<FJsonObject>& Map, FOKVngeObjectPatch& P)
	{
		if (!Map) return;
		bool bVis = true;
		if (Map->TryGetBoolField(TEXT("visible"), bVis)) P.Visible = bVis ? 1 : 0;
		P.bHasPos = ReadVec3(Map, TEXT("move_to"), P.Pos);
		if (const TSharedPtr<FJsonValue> RotVal = Map->TryGetField(TEXT("rotate_to"))) P.bHasRot = ReadUnityEulerOrQuatVal(RotVal, P.Rot);
		P.bHasScale = ReadVec3(Map, TEXT("scale_to"), P.Scale);

		const TArray<TSharedPtr<FJsonValue>>* AnimArr = nullptr;
		if (Map->TryGetArrayField(TEXT("anim"), AnimArr))
		{
			if (AnimArr->Num() == 3)
			{
				P.AnimGroup = int32((*AnimArr)[0]->AsNumber());
				P.AnimCategory = int32((*AnimArr)[1]->AsNumber());
				P.AnimNo = int32((*AnimArr)[2]->AsNumber());
			}
			else if (AnimArr->Num() >= 4)
			{
				P.AnimGroup = int32((*AnimArr)[1]->AsNumber());
				P.AnimCategory = int32((*AnimArr)[2]->AsNumber());
				P.AnimNo = int32((*AnimArr)[3]->AsNumber());
			}
		}
		double Num = 0.;
		if (Map->TryGetNumberField(TEXT("anim_spd"), Num)) P.AnimSpeed = float(Num);
		if (Map->TryGetNumberField(TEXT("anim_ntime"), Num)) P.AnimTime = float(Num);

		auto ExtractFkDict = [&](const TSharedPtr<FJsonValue>& FkVal, auto&& Self) -> void
		{
			if (!FkVal.IsValid()) return;
			if (FkVal->Type == EJson::Object)
			{
				for (const TPair<FString, TSharedPtr<FJsonValue>>& KV : FkVal->AsObject()->Values)
				{
					FVector Euler;
					if (!ReadUnityEulerOrQuatVal(KV.Value, Euler)) continue;
					const FString KeyTrim = KV.Key.TrimStartAndEnd();
					const FString Bone = KeyTrim.IsNumeric() ? ResolveFkBoneName(FCString::Atoi(*KeyTrim), FString()) : KeyTrim;
					if (!Bone.IsEmpty()) P.Fk.Add({ Bone, Euler });
				}
			}
			else if (FkVal->Type == EJson::Array)
			{
				const TArray<TSharedPtr<FJsonValue>>& Arr = FkVal->AsArray();
				if (Arr.Num() == 2 && Arr[1]->Type == EJson::Object)
				{
					Self(Arr[1], Self);
				}
				else
				{
					for (const TSharedPtr<FJsonValue>& Elem : Arr)
					{
						if (Elem->Type == EJson::Array && Elem->AsArray().Num() == 2)
							Self(Elem->AsArray()[1], Self);
					}
				}
			}
		};
		for (const TCHAR* FkKey : { TEXT("fk_set2"), TEXT("fk_set_quat"), TEXT("fk_set") })
		{
			if (const TSharedPtr<FJsonValue> FkVal = Map->TryGetField(FkKey))
			{
				ExtractFkDict(FkVal, ExtractFkDict);
				if (!P.Fk.IsEmpty()) break;
			}
		}

		auto ExtractIkDict = [&](const TSharedPtr<FJsonValue>& IkVal, auto&& Self) -> void
		{
			if (!IkVal.IsValid()) return;
			if (IkVal->Type == EJson::Object)
			{
				for (const TPair<FString, TSharedPtr<FJsonValue>>& KV : IkVal->AsObject()->Values)
				{
					int32 Eff = -1;
					bool bUseRot = false;
					if (!MapVngeIkKeyToEffector(KV.Key, Eff, bUseRot) || KV.Value->Type != EJson::Array) continue;
					const TArray<TSharedPtr<FJsonValue>>& Arr = KV.Value->AsArray();
					if (Arr.IsEmpty()) continue;
					FOKVngeIkEntry Entry;
					Entry.Effector = Eff;
					Entry.bUseRotation = bUseRot;
					if (Arr[0]->Type == EJson::Array && Arr[0]->AsArray().Num() >= 3)
					{
						const auto& PA = Arr[0]->AsArray();
						Entry.Pos = FVector(float(PA[0]->AsNumber()), float(PA[1]->AsNumber()), float(PA[2]->AsNumber()));
						if (Arr.Num() >= 2) ReadUnityEulerOrQuatVal(Arr[1], Entry.Euler);
						P.Ik.Add(Entry);
					}
					else if (Arr.Num() >= 3 && Arr[0]->Type == EJson::Number)
					{
						Entry.Pos = FVector(float(Arr[0]->AsNumber()), float(Arr[1]->AsNumber()), float(Arr[2]->AsNumber()));
						if (Arr.Num() >= 6) Entry.Euler = FVector(float(Arr[3]->AsNumber()), float(Arr[4]->AsNumber()), float(Arr[5]->AsNumber()));
						P.Ik.Add(Entry);
					}
				}
			}
			else if (IkVal->Type == EJson::Array && IkVal->AsArray().Num() == 2 && IkVal->AsArray()[1]->Type == EJson::Object)
			{
				Self(IkVal->AsArray()[1], Self);
			}
		};
		for (const TCHAR* IkKey : { TEXT("ik_set2"), TEXT("ik_set_quat"), TEXT("ik_set") })
		{
			if (const TSharedPtr<FJsonValue> IkVal = Map->TryGetField(IkKey))
			{
				ExtractIkDict(IkVal, ExtractIkDict);
				if (!P.Ik.IsEmpty()) break;
			}
		}

		Map->TryGetNumberField(TEXT("eyebrow"), P.EyebrowPtn);
		Map->TryGetNumberField(TEXT("eyes"), P.EyesPtn);
		if (Map->TryGetNumberField(TEXT("eyes_open"), Num)) P.EyesOpen = float(Num);
		Map->TryGetNumberField(TEXT("mouth"), P.MouthPtn);
		if (Map->TryGetNumberField(TEXT("mouth_open"), Num)) P.MouthOpen = float(Num);
		const TArray<TSharedPtr<FJsonValue>>* Hands = nullptr;
		if (Map->TryGetArrayField(TEXT("hands"), Hands) && Hands->Num() >= 2)
		{
			P.HandLeft = int32((*Hands)[0]->AsNumber());
			P.HandRight = int32((*Hands)[1]->AsNumber());
		}
		Map->TryGetNumberField(TEXT("look_at"), P.EyesLook);
		Map->TryGetNumberField(TEXT("face_to"), P.NeckLook);
		Map->TryGetNumberField(TEXT("cloth_type"), P.Outfit);
		const TArray<TSharedPtr<FJsonValue>>* ArrVal = nullptr;
		if (Map->TryGetArrayField(TEXT("cloth_all"), ArrVal))
			for (const auto& V : *ArrVal) P.ClothesStates.Add(uint8(FMath::Clamp(int32(V->AsNumber()), 0, 3)));
		if (Map->TryGetArrayField(TEXT("acc_all"), ArrVal))
			for (const auto& V : *ArrVal) P.AccessoriesShown.Add(uint8((V->Type == EJson::Boolean ? V->AsBool() : (int32(V->AsNumber()) != 0)) ? 1 : 0));
		Map->TryGetNumberField(TEXT("tear"), P.TearsLv);
		if (Map->TryGetNumberField(TEXT("nip_stand"), Num)) P.NipStand = float(Num);
		if (Map->TryGetArrayField(TEXT("juice"), ArrVal))
			for (const auto& V : *ArrVal) P.Fluids.Add(uint8(FMath::Clamp(int32(V->AsNumber()), 0, 2)));
	}

	bool LoadWavOrOggFile(const FString& Path, TSharedPtr<const FKKSpeechPcm, ESPMode::ThreadSafe>& Out, FString& Error)
	{
		if (Path.EndsWith(TEXT(".ogg"), ESearchCase::IgnoreCase)) return KKSpeech::DecodeOgg(Path, Out, Error);
		TArray<uint8> Bytes;
		if (!FFileHelper::LoadFileToArray(Bytes, *Path)) { Error = TEXT("无法读取音频文件: ") + Path; return false; }
		if (Bytes.Num() >= 4 && FMemory::Memcmp(Bytes.GetData(), "OggS", 4) == 0) return KKSpeech::DecodeOgg(Path, Out, Error);
		if (Bytes.Num() < 12 || FMemory::Memcmp(Bytes.GetData(), "RIFF", 4) || FMemory::Memcmp(Bytes.GetData() + 8, "WAVE", 4))
		{
			Error = TEXT("仅支持 WAV / OGG 音频格式: ") + Path;
			return false;
		}
		auto U16 = [&](int32 At) { return int32(Bytes[At]) | (int32(Bytes[At + 1]) << 8); };
		auto U32 = [&](int32 At) { return int32(U16(At)) | (int32(U16(At + 2)) << 16); };
		int32 Channels = 0, Rate = 0, Bits = 0, Format = 0;
		for (int32 At = 12; At + 8 <= Bytes.Num();)
		{
			const int32 Size = U32(At + 4), Body = At + 8;
			if (Size < 0 || Body > Bytes.Num()) break;
			if (!FMemory::Memcmp(Bytes.GetData() + At, "fmt ", 4) && Body + 16 <= Bytes.Num())
			{
				Format = U16(Body); Channels = U16(Body + 2); Rate = U32(Body + 4); Bits = U16(Body + 14);
				if (Format == 0xFFFE && Body + 40 <= Bytes.Num()) Format = U16(Body + 24);
			}
			else if (!FMemory::Memcmp(Bytes.GetData() + At, "data", 4))
			{
				if (Channels < 1 || Channels > 2 || Rate <= 0) { Error = TEXT("不支持的 WAV 声道/采样率: ") + Path; return false; }
				const int32 DataBytes = FMath::Min(Size, Bytes.Num() - Body);
				auto Pcm = MakeShared<FKKSpeechPcm, ESPMode::ThreadSafe>();
				Pcm->Channels = Channels;
				Pcm->SampleRate = Rate;
				if (Format == 1 && Bits == 8)
				{
					Pcm->Samples.SetNumUninitialized(DataBytes);
					for (int32 I = 0; I < DataBytes; ++I) Pcm->Samples[I] = int16((int32(Bytes[Body + I]) - 128) << 8);
					Out = Pcm;
					return true;
				}
				if (Format == 1 && Bits == 16)
				{
					const int32 Count = DataBytes / 2;
					Pcm->Samples.SetNumUninitialized(Count);
					FMemory::Memcpy(Pcm->Samples.GetData(), Bytes.GetData() + Body, Count * 2);
					Out = Pcm;
					return true;
				}
				if (Format == 3 && Bits == 32)
				{
					const int32 Count = DataBytes / 4;
					Pcm->Samples.SetNumUninitialized(Count);
					const float* Src = reinterpret_cast<const float*>(Bytes.GetData() + Body);
					for (int32 I = 0; I < Count; ++I) Pcm->Samples[I] = int16(FMath::Clamp(Src[I], -1.f, 1.f) * 32767.f);
					Out = Pcm;
					return true;
				}
				Error = FString::Printf(TEXT("不支持的 WAV 编码 format=%d bits=%d"), Format, Bits);
				return false;
			}
			At = Body + ((Size + 1) & ~1);
		}
		Error = TEXT("WAV 缺少 data 块: ") + Path;
		return false;
	}

	int32 PngPrefixLength(const TArray<uint8>& Bytes)
	{
		static const uint8 Sig[8] = { 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
		if (Bytes.Num() < 8 || FMemory::Memcmp(Bytes.GetData(), Sig, 8) != 0) return 0;
		int32 Pos = 8;
		while (Pos + 12 <= Bytes.Num())
		{
			const uint32 Len = (uint32(Bytes[Pos]) << 24) | (uint32(Bytes[Pos + 1]) << 16) | (uint32(Bytes[Pos + 2]) << 8) | uint32(Bytes[Pos + 3]);
			const bool bIend = FMemory::Memcmp(Bytes.GetData() + Pos + 4, "IEND", 4) == 0;
			const int64 Next = int64(Pos) + 12 + int64(Len);
			if (Next > Bytes.Num()) return 0;
			Pos = int32(Next);
			if (bIend) return Pos;
		}
		return 0;
	}
}

int32 FOKVngeRegistry::ResolveObjectId(const FString& Alias, const UOKSceneDocument* Doc) const
{
	const FString Trimmed = Alias.TrimStartAndEnd();
	if (Trimmed.IsEmpty()) return -1;
	for (const FOKVngeActorTag& T : Actors)
		if (T.Alias.Equals(Trimmed, ESearchCase::IgnoreCase) && T.ObjectId >= 0) return T.ObjectId;
	for (const FOKVngeActorTag& T : Props)
		if (T.Alias.Equals(Trimmed, ESearchCase::IgnoreCase) && T.ObjectId >= 0) return T.ObjectId;
	if (Doc)
	{
		if (Trimmed.IsNumeric())
		{
			const int32 DirectId = FCString::Atoi(*Trimmed);
			if (Doc->Find(DirectId)) return DirectId;
		}
		auto MatchNthCharacter = [&](int32 ZeroBasedIdx) -> int32
		{
			int32 Seen = 0;
			for (const FOKSceneObject& O : Doc->Objects)
			{
				if (O.Kind == EOKSceneObjectKind::Character)
				{
					if (Seen == ZeroBasedIdx) return O.Id;
					++Seen;
				}
			}
			return -1;
		};
		if (Trimmed.StartsWith(TEXT("act"), ESearchCase::IgnoreCase) && Trimmed.Mid(3).IsNumeric())
		{
			return MatchNthCharacter(FCString::Atoi(*Trimmed.Mid(3)));
		}
		if ((Trimmed.StartsWith(TEXT("f"), ESearchCase::IgnoreCase) || Trimmed.StartsWith(TEXT("m"), ESearchCase::IgnoreCase)) && Trimmed.Mid(1).IsNumeric())
		{
			const int32 OneBased = FCString::Atoi(*Trimmed.Mid(1));
			if (OneBased >= 1) return MatchNthCharacter(OneBased - 1);
		}
	}
	return -1;
}

void FOKSceneVngeData::RemapObjectIds(const TMap<int32, int32>& IdMap)
{
	auto MapId = [&IdMap](int32& Id)
	{
		if (Id >= 0)
		{
			if (const int32* NewId = IdMap.Find(Id)) Id = *NewId;
			else Id = -1;
		}
	};
	for (FOKVngeActorTag& T : Registry.Actors) MapId(T.ObjectId);
	for (FOKVngeActorTag& T : Registry.Props) MapId(T.ObjectId);
	for (FOKVngeSceneState& St : Sss.States)
	{
		for (FOKVngeObjectPatch& P : St.Actors) MapId(P.ObjectId);
		for (FOKVngeObjectPatch& P : St.Props) MapId(P.ObjectId);
	}
	for (FOKVngeClip& C : Clips)
		for (FOKVngeTrack& Tr : C.Tracks) MapId(Tr.ObjectId);
	for (FOKVngeTextEntry& Tx : Texts) MapId(Tx.ObjectId);
	for (FOKVngeSoundSource& S : Sounds) MapId(S.BindObjectId);
	for (FOKVngePhysicsRule& R : Physics.Rules)
	{
		if (R.SourceObjectId >= 0) MapId(R.SourceObjectId);
		MapId(R.TargetObjectId);
	}
}

FOKStudioVngeRuntime::FOKStudioVngeRuntime(UOKStudioGame* InGame)
	: Game(InGame)
{
}

FOKStudioVngeRuntime::~FOKStudioVngeRuntime()
{
	StopAllSounds();
	StopAllClips();
}

void FOKStudioVngeRuntime::ImportFromSceneJson(const TSharedPtr<FJsonObject>& VngeJson, const TMap<int32, int32>& KeyToId, UOKSceneDocument& Doc, TArray<FString>& OutNotes)
{
	if (!VngeJson.IsValid()) return;
	FOKSceneVngeData& Out = Doc.Vnge;
	Out = FOKSceneVngeData();

	// 1. Registry + Actor Settings
	const TSharedPtr<FJsonObject>* RegObj = nullptr;
	if (VngeJson->TryGetObjectField(TEXT("registry"), RegObj) && RegObj && RegObj->IsValid())
	{
		const TArray<TSharedPtr<FJsonValue>>* ActorTags = nullptr;
		if ((*RegObj)->TryGetArrayField(TEXT("actor_tags"), ActorTags))
		{
			for (const TSharedPtr<FJsonValue>& V : *ActorTags)
			{
				const TSharedPtr<FJsonObject> O = V->AsObject();
				if (!O) continue;
				const int32 DicKey = int32(O->GetNumberField(TEXT("key")));
				const int32* ObjId = KeyToId.Find(DicKey);
				if (!ObjId) continue;
				FOKVngeActorTag Tag;
				O->TryGetStringField(TEXT("alias"), Tag.Alias);
				Tag.ObjectId = *ObjId;
				O->TryGetNumberField(TEXT("sex"), Tag.Sex);
				O->TryGetStringField(TEXT("color"), Tag.ColorHex);
				O->TryGetStringField(TEXT("title"), Tag.Title);
				if (!Tag.Alias.IsEmpty()) Out.Registry.Actors.Add(MoveTemp(Tag));
			}
		}
		const TSharedPtr<FJsonObject>* ActorsMap = nullptr;
		if ((*RegObj)->TryGetObjectField(TEXT("actors"), ActorsMap) && ActorsMap && ActorsMap->IsValid())
		{
			for (const TPair<FString, TSharedPtr<FJsonValue>>& KV : (*ActorsMap)->Values)
			{
				if (Out.Registry.Actors.ContainsByPredicate([&](const FOKVngeActorTag& T) { return T.Alias == KV.Key; })) continue;
				if (const int32* ObjId = KeyToId.Find(int32(KV.Value->AsNumber())))
				{
					FOKVngeActorTag Tag;
					Tag.Alias = KV.Key;
					Tag.ObjectId = *ObjId;
					Out.Registry.Actors.Add(MoveTemp(Tag));
				}
			}
		}
		const TSharedPtr<FJsonObject>* PropsMap = nullptr;
		if ((*RegObj)->TryGetObjectField(TEXT("props"), PropsMap) && PropsMap && PropsMap->IsValid())
		{
			for (const TPair<FString, TSharedPtr<FJsonValue>>& KV : (*PropsMap)->Values)
			{
				if (const int32* ObjId = KeyToId.Find(int32(KV.Value->AsNumber())))
				{
					FOKVngeActorTag Tag;
					Tag.Alias = KV.Key;
					Tag.ObjectId = *ObjId;
					Tag.Sex = -1;
					Out.Registry.Props.Add(MoveTemp(Tag));
				}
			}
		}
	}
	if (const TSharedPtr<FJsonValue> ActorSetVal = VngeJson->TryGetField(TEXT("actor_settings")))
	{
		Out.Registry.ActorSettingsJson = SerializeJsonValue(ActorSetVal);
	}

	// 2. SSS + SSSAdv + Ministates + SSSB
	const TSharedPtr<FJsonObject>* SssObj = nullptr;
	if (VngeJson->TryGetObjectField(TEXT("sss"), SssObj) && SssObj && SssObj->IsValid())
	{
		(*SssObj)->TryGetStringField(TEXT("version"), Out.Sss.Version);
		const TArray<TSharedPtr<FJsonValue>>* CamsArr = nullptr;
		if ((*SssObj)->TryGetArrayField(TEXT("cameras"), CamsArr))
		{
			for (const TSharedPtr<FJsonValue>& CV : *CamsArr)
			{
				const TSharedPtr<FJsonObject> CO = CV->AsObject();
				if (!CO) continue;
				FOKVngeCameraSlot Slot;
				Slot.Slot = int32(CO->GetNumberField(TEXT("slot")));
				ReadVec3(CO, TEXT("pos"), Slot.Pos);
				ReadVec3(CO, TEXT("distance"), Slot.Distance);
				ReadVec3(CO, TEXT("rotate"), Slot.Rotate);
				Slot.Fov = float(CO->GetNumberField(TEXT("fov")));
				CO->TryGetStringField(TEXT("who_say"), Slot.WhoSay);
				CO->TryGetStringField(TEXT("what_say"), Slot.WhatSay);
				CO->TryGetStringField(TEXT("add_param"), Slot.AddParam);
				Out.Sss.Cameras.Add(MoveTemp(Slot));
			}
		}
		const TArray<TSharedPtr<FJsonValue>>* StatesArr = nullptr;
		if ((*SssObj)->TryGetArrayField(TEXT("states"), StatesArr))
		{
			for (int32 Idx = 0; Idx < StatesArr->Num(); ++Idx)
			{
				const TSharedPtr<FJsonObject> SO = (*StatesArr)[Idx]->AsObject();
				if (!SO) continue;
				FOKVngeSceneState St;
				SO->TryGetStringField(TEXT("id"), St.Id);
				SO->TryGetStringField(TEXT("who_say"), St.WhoSay);
				SO->TryGetStringField(TEXT("what_say"), St.WhatSay);
				SO->TryGetStringField(TEXT("add_param"), St.AddParam);
				if (Out.Sss.Cameras.IsValidIndex(Idx)) St.LinkedCameraSlot = Idx;
				const TArray<TSharedPtr<FJsonValue>>* SubArr = nullptr;
				if (SO->TryGetArrayField(TEXT("actors"), SubArr))
					for (const auto& AV : *SubArr) St.Actors.Add(ParseObjectStatusFromRust(AV->AsObject(), false, KeyToId, Out.Registry));
				if (SO->TryGetArrayField(TEXT("props"), SubArr))
					for (const auto& PV : *SubArr) St.Props.Add(ParseObjectStatusFromRust(PV->AsObject(), true, KeyToId, Out.Registry));
				Out.Sss.States.Add(MoveTemp(St));
			}
		}
	}
	if (const TSharedPtr<FJsonValue> SssAdvVal = VngeJson->TryGetField(TEXT("sss_adv")))
	{
		Out.Sss.SssAdvJson = SerializeJsonValue(SssAdvVal);
	}
	if (const TSharedPtr<FJsonValue> SssbVal = VngeJson->TryGetField(TEXT("sssb")))
	{
		Out.Sss.SssbJson = SerializeJsonValue(SssbVal);
	}
	const TArray<TSharedPtr<FJsonValue>>* MiniArr = nullptr;
	if (VngeJson->TryGetArrayField(TEXT("ministates"), MiniArr))
	{
		for (const TSharedPtr<FJsonValue>& MV : *MiniArr)
		{
			const TSharedPtr<FJsonObject> MO = MV->AsObject();
			if (!MO) continue;
			FOKVngeMinistate Ms;
			MO->TryGetStringField(TEXT("name"), Ms.Name);
			MO->TryGetStringField(TEXT("group"), Ms.Group);
			Ms.PayloadJson = SerializeJsonValue(MO->TryGetField(TEXT("payload")));
			Out.Sss.Ministates.Add(MoveTemp(Ms));
		}
	}
	if (!Out.Sss.IsEmpty())
	{
		OutNotes.Add(FString::Printf(TEXT("VNGE SSS imported (%d states, %d cameras, %d ministates)"), Out.Sss.States.Num(), Out.Sss.Cameras.Num(), Out.Sss.Ministates.Num()));
	}

	// 3. VNAnime KFA Clips (`vnge_kfa` / `vnge_kfa2` / `-keyframeclips:`)
	const TArray<TSharedPtr<FJsonValue>>* ClipsArr = nullptr;
	if (VngeJson->TryGetArrayField(TEXT("clips"), ClipsArr))
	{
		for (const TSharedPtr<FJsonValue>& CV : *ClipsArr)
		{
			const TSharedPtr<FJsonObject> CO = CV->AsObject();
			if (!CO) continue;
			FOKVngeClip Clip;
			CO->TryGetStringField(TEXT("name"), Clip.Name);
			CO->TryGetNumberField(TEXT("version"), Clip.Version);
			Clip.FrameLength = FMath::Max(1.f, float(CO->GetNumberField(TEXT("frame_length"))));
			Clip.FrameRate = FMath::Max(1.f, float(CO->GetNumberField(TEXT("frame_rate"))));
			Clip.Duration = FMath::Max(0.05f, float(CO->GetNumberField(TEXT("duration"))));
			CO->TryGetNumberField(TEXT("loop_mode"), Clip.LoopMode);
			Clip.Speed = FMath::Max(0.01f, float(CO->GetNumberField(TEXT("speed"))));
			CO->TryGetBoolField(TEXT("autorun"), Clip.bAutorun);
			CO->TryGetNumberField(TEXT("priority"), Clip.Priority);
			const TArray<TSharedPtr<FJsonValue>>* TracksArr = nullptr;
			if (CO->TryGetArrayField(TEXT("tracks"), TracksArr))
			{
				for (const TSharedPtr<FJsonValue>& TV : *TracksArr)
				{
					const TSharedPtr<FJsonObject> TO = TV->AsObject();
					if (!TO) continue;
					FOKVngeTrack Tr;
					TO->TryGetStringField(TEXT("target_id"), Tr.TargetAlias);
					TO->TryGetStringField(TEXT("target_type"), Tr.TargetType);
					int32 DicKey = -1;
					if (TO->TryGetNumberField(TEXT("key"), DicKey) && DicKey >= 0)
					{
						if (const int32* FoundId = KeyToId.Find(DicKey)) Tr.ObjectId = *FoundId;
					}
					if (Tr.ObjectId < 0 && Tr.TargetType != TEXT("cam"))
					{
						Tr.ObjectId = Out.Registry.ResolveObjectId(Tr.TargetAlias, &Doc);
					}
					const TArray<TSharedPtr<FJsonValue>>* KeysArr = nullptr;
					if (!TO->TryGetArrayField(TEXT("keys"), KeysArr) || KeysArr->IsEmpty()) continue;
					Tr.Keys.Reserve(KeysArr->Num());
					for (const TSharedPtr<FJsonValue>& KV : *KeysArr)
					{
						const TSharedPtr<FJsonObject> KO = KV->AsObject();
						if (!KO) continue;
						FOKVngeTrackKey Key;
						Key.Time = float(KO->GetNumberField(TEXT("time")));
						KO->TryGetStringField(TEXT("ease"), Key.Ease);
						bool bVis = true;
						if (KO->TryGetBoolField(TEXT("visible"), bVis)) Key.Visible = bVis ? 1 : 0;
						Key.bHasPos = ReadVec3(KO, TEXT("pos"), Key.Pos);
						Key.bHasRot = ReadVec3(KO, TEXT("rot"), Key.Rot);
						Key.bHasScale = ReadVec3(KO, TEXT("scale"), Key.Scale);
						const bool bCP = ReadVec3(KO, TEXT("cam_pos"), Key.CamPos);
						const bool bCD = ReadVec3(KO, TEXT("cam_dst"), Key.CamDst);
						const bool bCR = ReadVec3(KO, TEXT("cam_rot"), Key.CamRot);
						Key.bHasCam = bCP || bCD || bCR;
						double ValNum = 0.;
						if (KO->TryGetNumberField(TEXT("value"), ValNum)) { Key.bHasValue = true; Key.Value = float(ValNum); }
						const TArray<TSharedPtr<FJsonValue>>* SubArr = nullptr;
						if (KO->TryGetArrayField(TEXT("fk"), SubArr)) ParseFkArrayFromRust(*SubArr, Key.Fk);
						if (KO->TryGetArrayField(TEXT("ik"), SubArr)) ParseIkArrayFromRust(*SubArr, Key.Ik);
						KO->TryGetNumberField(TEXT("eyebrow_ptn"), Key.EyebrowPtn);
						KO->TryGetNumberField(TEXT("eyes_ptn"), Key.EyesPtn);
						KO->TryGetNumberField(TEXT("mouth_ptn"), Key.MouthPtn);
						if (KO->TryGetNumberField(TEXT("eyes_open"), ValNum)) Key.EyesOpen = float(ValNum);
						if (KO->TryGetNumberField(TEXT("mouth_open"), ValNum)) Key.MouthOpen = float(ValNum);
						KO->TryGetNumberField(TEXT("hand_left"), Key.HandLeft);
						KO->TryGetNumberField(TEXT("hand_right"), Key.HandRight);
						if (KO->TryGetArrayField(TEXT("anime"), SubArr) && SubArr->Num() >= 3)
						{
							Key.AnimGroup = int32((*SubArr)[0]->AsNumber());
							Key.AnimCategory = int32((*SubArr)[1]->AsNumber());
							Key.AnimNo = int32((*SubArr)[2]->AsNumber());
						}
						if (KO->TryGetNumberField(TEXT("anime_speed"), ValNum)) Key.AnimSpeed = float(ValNum);
						Tr.Keys.Add(MoveTemp(Key));
					}
					if (!Tr.Keys.IsEmpty()) Clip.Tracks.Add(MoveTemp(Tr));
				}
			}
			if (!Clip.Tracks.IsEmpty()) Out.Clips.Add(MoveTemp(Clip));
		}
	}
	if (!Out.Clips.IsEmpty())
	{
		OutNotes.Add(FString::Printf(TEXT("VNGE KFA animation clips imported (%d clips)"), Out.Clips.Num()));
		// When the scene has no native Timeline.dll tracks, expose the primary autorun/first KFA clip on the main Timeline too.
		if (Doc.Tracks.IsEmpty() && Doc.TimelineTracks.IsEmpty())
		{
			int32 Chosen = Out.Clips.IndexOfByPredicate([](const FOKVngeClip& C) { return C.bAutorun; });
			if (Chosen == INDEX_NONE) Chosen = 0;
			BakeClipToDocumentTimeline(Out.Clips[Chosen], Doc, false);
		}
	}

	// 4. VNText & Studio Text entries
	const TArray<TSharedPtr<FJsonValue>>* TextsArr = nullptr;
	if (VngeJson->TryGetArrayField(TEXT("texts"), TextsArr))
	{
		for (const TSharedPtr<FJsonValue>& TV : *TextsArr)
		{
			const TSharedPtr<FJsonObject> TO = TV->AsObject();
			if (!TO) continue;
			FOKVngeTextEntry Entry;
			TO->TryGetStringField(TEXT("id"), Entry.Id);
			const int32 DicKey = int32(TO->GetNumberField(TEXT("dic_key")));
			if (const int32* FoundId = KeyToId.Find(DicKey)) Entry.ObjectId = *FoundId;
			TO->TryGetStringField(TEXT("text"), Entry.Text);
			ReadVec4Color(TO, TEXT("color"), Entry.Color);
			ReadVec4Color(TO, TEXT("outline_color"), Entry.OutlineColor);
			Entry.OutlineSpread = float(TO->GetNumberField(TEXT("outline_spread")));
			TO->TryGetBoolField(TEXT("visible"), Entry.bVisible);
			TO->TryGetBoolField(TEXT("in_front"), Entry.bInFront);
			TO->TryGetStringField(TEXT("font"), Entry.Font);
			Entry.Size = FMath::Max(8.f, float(TO->GetNumberField(TEXT("size"))));
			TO->TryGetNumberField(TEXT("anchor"), Entry.Anchor);
			TO->TryGetNumberField(TEXT("alignment"), Entry.Alignment);
			ReadVec3(TO, TEXT("position"), Entry.Position);
			ReadVec3(TO, TEXT("rotation"), Entry.Rotation);
			ReadVec3(TO, TEXT("scale"), Entry.Scale);
			TO->TryGetBoolField(TEXT("is_3d"), Entry.bIs3D);
			TO->TryGetBoolField(TEXT("bind_cam"), Entry.bBindCam);
			TO->TryGetBoolField(TEXT("parent_hide"), Entry.bParentHide);
			TO->TryGetBoolField(TEXT("word_wrap"), Entry.bWordWrap);
			TO->TryGetNumberField(TEXT("word_wrap_len"), Entry.WordWrapLen);
			Out.Texts.Add(MoveTemp(Entry));
		}
		if (!Out.Texts.IsEmpty())
		{
			OutNotes.Add(FString::Printf(TEXT("VNGE / Studio text overlays imported (%d entries)"), Out.Texts.Num()));
		}
	}

	// 5. VNSound (`vnge_sound` + `vnge_sound_extdata`)
	const TSharedPtr<FJsonObject>* SoundObj = nullptr;
	if (VngeJson->TryGetObjectField(TEXT("sound"), SoundObj) && SoundObj && SoundObj->IsValid())
	{
		const TArray<TSharedPtr<FJsonValue>>* SrcArr = nullptr;
		if ((*SoundObj)->TryGetArrayField(TEXT("sources"), SrcArr))
		{
			for (const TSharedPtr<FJsonValue>& SV : *SrcArr)
			{
				const TSharedPtr<FJsonObject> SO = SV->AsObject();
				if (!SO) continue;
				FOKVngeSoundSource Src;
				SO->TryGetStringField(TEXT("id"), Src.Id);
				SO->TryGetStringField(TEXT("group"), Src.Group);
				SO->TryGetStringField(TEXT("path"), Src.Path);
				SO->TryGetStringField(TEXT("extracted_path"), Src.ExtractedPath);
				Src.Volume = FMath::Clamp(float(SO->GetNumberField(TEXT("volume"))), 0.f, 2.f);
				Src.Pitch = FMath::Clamp(float(SO->GetNumberField(TEXT("pitch"))), 0.1f, 4.f);
				SO->TryGetBoolField(TEXT("loop_play"), Src.bLoop);
				SO->TryGetBoolField(TEXT("auto_play"), Src.bAutoPlay);
				SO->TryGetBoolField(TEXT("is_3d"), Src.bIs3D);
				const int32 BindKey = int32(SO->GetNumberField(TEXT("bind_key")));
				if (const int32* FoundId = KeyToId.Find(BindKey)) Src.BindObjectId = *FoundId;
				SO->TryGetStringField(TEXT("bind_actor"), Src.BindActorAlias);
				if (Src.BindObjectId < 0 && !Src.BindActorAlias.IsEmpty())
				{
					Src.BindObjectId = Out.Registry.ResolveObjectId(Src.BindActorAlias, &Doc);
				}
				Src.MinDist = FMath::Max(0.1f, float(SO->GetNumberField(TEXT("min_dist"))));
				Src.MaxDist = FMath::Max(Src.MinDist, float(SO->GetNumberField(TEXT("max_dist"))));
				Src.bLipSync = Src.BindObjectId >= 0 && Src.Group.Contains(TEXT("voice"), ESearchCase::IgnoreCase);
				Src.RawJson = SerializeJsonValue(SO->TryGetField(TEXT("raw")));
				Out.Sounds.Add(MoveTemp(Src));
			}
		}
		if (!Out.Sounds.IsEmpty())
		{
			OutNotes.Add(FString::Printf(TEXT("VNGE sound sources imported (%d sources)"), Out.Sounds.Num()));
		}
	}

	// 6. VNPhysics (`vnge_physics`)
	const TSharedPtr<FJsonObject>* PhysObj = nullptr;
	if (VngeJson->TryGetObjectField(TEXT("physics"), PhysObj) && PhysObj && PhysObj->IsValid())
	{
		(*PhysObj)->TryGetStringField(TEXT("version"), Out.Physics.Version);
		Out.Physics.CollidersJson = SerializeJsonValue((*PhysObj)->TryGetField(TEXT("colliders")));
		Out.Physics.RigidBodiesJson = SerializeJsonValue((*PhysObj)->TryGetField(TEXT("rigid_bodies")));
		Out.Physics.TriggersJson = SerializeJsonValue((*PhysObj)->TryGetField(TEXT("triggers")));
		Out.Physics.ActionsJson = SerializeJsonValue((*PhysObj)->TryGetField(TEXT("actions")));
		const TArray<TSharedPtr<FJsonValue>>* TrigArr = nullptr;
		if ((*PhysObj)->TryGetArrayField(TEXT("triggers"), TrigArr))
		{
			for (int32 I = 0; I < TrigArr->Num(); ++I)
			{
				const TSharedPtr<FJsonObject> TO = (*TrigArr)[I]->AsObject();
				if (!TO) continue;
				FOKVngePhysicsRule Rule;
				if (!TO->TryGetStringField(TEXT("name"), Rule.Name) || Rule.Name.IsEmpty())
					Rule.Name = FString::Printf(TEXT("触发器 %d"), I + 1);
				TO->TryGetStringField(TEXT("source"), Rule.SourceAlias);
				TO->TryGetStringField(TEXT("target"), Rule.TargetAlias);
				if (!Rule.SourceAlias.IsEmpty() && !Rule.SourceAlias.Equals(TEXT("cam"), ESearchCase::IgnoreCase))
					Rule.SourceObjectId = Out.Registry.ResolveObjectId(Rule.SourceAlias, &Doc);
				if (!Rule.TargetAlias.IsEmpty())
					Rule.TargetObjectId = Out.Registry.ResolveObjectId(Rule.TargetAlias, &Doc);
				double Dist = 0.35;
				if (TO->TryGetNumberField(TEXT("distance"), Dist) || TO->TryGetNumberField(TEXT("radius"), Dist))
					Rule.TriggerDistance = FMath::Max(0.02f, float(Dist));
				if (!TO->TryGetStringField(TEXT("action"), Rule.ActionKind) || Rule.ActionKind.IsEmpty())
					Rule.ActionKind = TEXT("play_clip");
				TO->TryGetStringField(TEXT("param"), Rule.ActionParam);
				Out.Physics.Rules.Add(MoveTemp(Rule));
			}
		}
		if (!Out.Physics.IsEmpty())
		{
			OutNotes.Add(TEXT("VNGE physics colliders & triggers imported"));
		}
	}

	// 7. VNSS (`vnge_vnss` / `:vnscenescript:`)
	const TSharedPtr<FJsonObject>* ScriptObj = nullptr;
	if (VngeJson->TryGetObjectField(TEXT("script"), ScriptObj) && ScriptObj && ScriptObj->IsValid())
	{
		(*ScriptObj)->TryGetStringField(TEXT("version"), Out.Script.Version);
		const TSharedPtr<FJsonValue> RawVal = (*ScriptObj)->TryGetField(TEXT("raw"));
		Out.Script.RawJson = SerializeJsonValue(RawVal);
		if (RawVal.IsValid() && RawVal->Type == EJson::Object)
		{
			for (const TPair<FString, TSharedPtr<FJsonValue>>& KV : RawVal->AsObject()->Values)
			{
				FOKVngeScriptBlock Block;
				Block.Name = KV.Key;
				if (KV.Value->Type == EJson::Array)
				{
					for (const TSharedPtr<FJsonValue>& LV : KV.Value->AsArray())
					{
						Block.Lines.Add(LV->Type == EJson::String ? LV->AsString() : SerializeJsonValue(LV));
					}
				}
				else
				{
					Block.Lines.Add(SerializeJsonValue(KV.Value));
				}
				Out.Script.Blocks.Add(MoveTemp(Block));
			}
		}
		else if (RawVal.IsValid() && RawVal->Type == EJson::Array)
		{
			FOKVngeScriptBlock Block;
			Block.Name = TEXT("main");
			for (const TSharedPtr<FJsonValue>& LV : RawVal->AsArray())
			{
				Block.Lines.Add(LV->Type == EJson::String ? LV->AsString() : SerializeJsonValue(LV));
			}
			Out.Script.Blocks.Add(MoveTemp(Block));
		}
		if (!Out.Script.IsEmpty())
		{
			OutNotes.Add(FString::Printf(TEXT("VNGE scene script imported (%d blocks)"), Out.Script.Blocks.Num()));
		}
	}
}

void FOKStudioVngeRuntime::OnSceneOpened()
{
	StopAllSounds();
	StopAllClips();
	bCamTransitionActive = false;
	InsideTriggerRules.Reset();
	ResetScript();
	if (!Game || !Game->Document) return;
	UOKSceneDocument& Doc = *Game->Document;
	for (int32 I = 0; I < Doc.Vnge.Clips.Num(); ++I)
	{
		if (Doc.Vnge.Clips[I].bAutorun)
		{
			PlayClip(I, true);
		}
	}
	for (int32 I = 0; I < Doc.Vnge.Sounds.Num(); ++I)
	{
		if (Doc.Vnge.Sounds[I].bAutoPlay)
		{
			FString Err;
			PlaySoundSource(I, Err);
		}
	}
	const int32 InitIdx = Doc.Vnge.Script.Blocks.IndexOfByPredicate([](const FOKVngeScriptBlock& B)
	{
		return B.Name.Equals(TEXT(":init"), ESearchCase::IgnoreCase) || B.Name.Equals(TEXT("init"), ESearchCase::IgnoreCase);
	});
	if (InitIdx != INDEX_NONE)
	{
		for (const FString& Line : Doc.Vnge.Script.Blocks[InitIdx].Lines)
		{
			ExecuteScriptLine(Line);
		}
	}
}

void FOKStudioVngeRuntime::Tick(float DeltaTime)
{
	if (!Game || !Game->Document || DeltaTime <= 0.f) return;
	UOKSceneDocument& Doc = *Game->Document;

	// 1. Smooth SSS camera transition
	if (bCamTransitionActive)
	{
		CamTransElapsed += DeltaTime;
		const float RawAlpha = CamTransDuration > 1e-4f ? FMath::Clamp(CamTransElapsed / CamTransDuration, 0.f, 1.f) : 1.f;
		const float Alpha = RawAlpha * RawAlpha * (3.f - 2.f * RawAlpha);
		const FVector CurTarget = FMath::Lerp(CamStartTarget, CamEndTarget, Alpha);
		const FVector CurDist = FMath::Lerp(CamStartDist, CamEndDist, Alpha);
		const FQuat QA = UnityEulerDegToQuat(CamStartRot);
		const FQuat QB = UnityEulerDegToQuat(CamEndRot);
		const FVector CurRot = UnityQuatToEulerDeg(FQuat::Slerp(QA, QB, Alpha));
		const float CurFov = FMath::Lerp(CamStartFov, CamEndFov, Alpha);
		ApplyOrbitCameraUnity(CurTarget, CurDist, CurRot, CurFov);
		if (RawAlpha >= 1.f) bCamTransitionActive = false;
	}

	// 2. Concurrent VNAnime KFA clips
	if (!ClipStates.IsEmpty())
	{
		TArray<int32> RunningIds;
		ClipStates.GetKeys(RunningIds);
		for (int32 ClipIdx : RunningIds)
		{
			if (!Doc.Vnge.Clips.IsValidIndex(ClipIdx))
			{
				ClipStates.Remove(ClipIdx);
				continue;
			}
			FClipPlayState* St = ClipStates.Find(ClipIdx);
			if (!St || !St->bPlaying) continue;
			const FOKVngeClip& Clip = Doc.Vnge.Clips[ClipIdx];
			const float Len = FMath::Max(0.05f, Clip.Duration);
			const float Step = DeltaTime * FMath::Max(0.01f, Clip.Speed) * float(St->PingPongDir);
			St->Time += Step;
			if (Clip.LoopMode == 0)
			{
				if (St->Time >= Len) { St->Time = Len; St->bPlaying = false; }
			}
			else if (Clip.LoopMode == 2)
			{
				if (St->Time >= Len) { St->Time = Len; St->PingPongDir = -1; }
				else if (St->Time <= 0.f) { St->Time = 0.f; St->PingPongDir = 1; }
			}
			else
			{
				if (St->Time > Len) St->Time = FMath::Fmod(St->Time, Len);
				else if (St->Time < 0.f) St->Time = Len + FMath::Fmod(St->Time, Len);
			}
			EvaluateClipAt(Clip, St->Time);
		}
	}

	// 3. Active VNSound 3D follow + lifecycle cleanup
	if (!ActiveSounds.IsEmpty())
	{
		TArray<int32> SndIndices;
		ActiveSounds.GetKeys(SndIndices);
		for (int32 SIdx : SndIndices)
		{
			FActiveSound* AS = ActiveSounds.Find(SIdx);
			if (!AS) continue;
			UAudioComponent* Comp = AS->AudioComp.Get();
			if (!Comp || !Comp->IsPlaying())
			{
				if (AS->bLoop && Doc.Vnge.Sounds.IsValidIndex(SIdx) && !Game->bMuteSound)
				{
					FString Err;
					PlaySoundSource(SIdx, Err);
				}
				else
				{
					ActiveSounds.Remove(SIdx);
				}
				continue;
			}
			if (Doc.Vnge.Sounds.IsValidIndex(SIdx))
			{
				const FOKVngeSoundSource& Src = Doc.Vnge.Sounds[SIdx];
				Comp->SetVolumeMultiplier(Game->bMuteSound ? 0.f : FMath::Clamp(Src.Volume * Game->SoundVolume, 0.f, 2.f));
				if (Src.bIs3D && Src.BindObjectId >= 0 && Doc.Find(Src.BindObjectId))
				{
					FVector HeadPos = Doc.WorldTransform(Src.BindObjectId).GetLocation() + FVector(0.f, 0.f, 140.f);
					Game->BoneAt(Src.BindObjectId, TEXT("cf_j_head"), HeadPos);
					Comp->SetWorldLocation(HeadPos);
				}
			}
		}
	}

	// 4. VNPhysics distance/contact trigger evaluation
	if (Doc.Vnge.Physics.bEnabled && !Doc.Vnge.Physics.Rules.IsEmpty())
	{
		for (int32 RIdx = 0; RIdx < Doc.Vnge.Physics.Rules.Num(); ++RIdx)
		{
			const FOKVngePhysicsRule& Rule = Doc.Vnge.Physics.Rules[RIdx];
			if (!Rule.bEnabled || Rule.TargetObjectId < 0 || !Doc.Find(Rule.TargetObjectId)) continue;
			FVector SrcPos = FVector::ZeroVector;
			if (Rule.SourceObjectId == -2)
			{
				if (!Game->Viewer) continue;
				SrcPos = Game->Viewer->GetActorLocation();
			}
			else if (Rule.SourceObjectId >= 0 && Doc.Find(Rule.SourceObjectId))
			{
				SrcPos = Doc.WorldTransform(Rule.SourceObjectId).GetLocation();
			}
			else continue;
			const FVector DstPos = Doc.WorldTransform(Rule.TargetObjectId).GetLocation();
			const float DistM = float(FVector::Dist(SrcPos, DstPos) * 0.01);
			const bool bInside = DistM <= FMath::Max(0.02f, Rule.TriggerDistance);
			if (bInside && !InsideTriggerRules.Contains(RIdx))
			{
				InsideTriggerRules.Add(RIdx);
				TriggerPhysicsRuleNow(RIdx);
			}
			else if (!bInside && DistM > Rule.TriggerDistance * 1.15f)
			{
				InsideTriggerRules.Remove(RIdx);
			}
		}
	}
}

int32 FOKStudioVngeRuntime::AutoRegisterSceneTags()
{
	if (!Game || !Game->Document) return 0;
	UOKSceneDocument& Doc = *Game->Document;
	int32 Added = 0;
	int32 FCount = 0, PropCount = 0;
	for (const FOKSceneObject& O : Doc.Objects)
	{
		if (O.Kind == EOKSceneObjectKind::Character)
		{
			++FCount;
			if (!Doc.Vnge.Registry.Actors.ContainsByPredicate([&](const FOKVngeActorTag& T) { return T.ObjectId == O.Id; }))
			{
				FOKVngeActorTag Tag;
				Tag.Alias = FString::Printf(TEXT("f%d"), FCount);
				Tag.ObjectId = O.Id;
				Tag.Title = O.Name;
				Doc.Vnge.Registry.Actors.Add(MoveTemp(Tag));
				++Added;
			}
		}
		else if (O.Kind == EOKSceneObjectKind::Item)
		{
			++PropCount;
			if (!Doc.Vnge.Registry.Props.ContainsByPredicate([&](const FOKVngeActorTag& T) { return T.ObjectId == O.Id; }))
			{
				FOKVngeActorTag Tag;
				Tag.Alias = FString::Printf(TEXT("p%d"), PropCount);
				Tag.ObjectId = O.Id;
				Tag.Sex = -1;
				Tag.Title = O.Name;
				Doc.Vnge.Registry.Props.Add(MoveTemp(Tag));
				++Added;
			}
		}
	}
	if (Added > 0) Doc.NotifyChanged();
	return Added;
}

bool FOKStudioVngeRuntime::SetObjectTag(int32 ObjectId, const FString& Alias, bool bIsProp)
{
	if (!Game || !Game->Document || Alias.TrimStartAndEnd().IsEmpty()) return false;
	UOKSceneDocument& Doc = *Game->Document;
	const FOKSceneObject* Obj = Doc.Find(ObjectId);
	if (!Obj) return false;
	const FString Clean = Alias.TrimStartAndEnd();
	TArray<FOKVngeActorTag>& List = bIsProp ? Doc.Vnge.Registry.Props : Doc.Vnge.Registry.Actors;
	if (FOKVngeActorTag* Existing = List.FindByPredicate([&](const FOKVngeActorTag& T) { return T.Alias.Equals(Clean, ESearchCase::IgnoreCase) || T.ObjectId == ObjectId; }))
	{
		Existing->Alias = Clean;
		Existing->ObjectId = ObjectId;
		Existing->Title = Obj->Name;
	}
	else
	{
		FOKVngeActorTag Tag;
		Tag.Alias = Clean;
		Tag.ObjectId = ObjectId;
		Tag.Sex = bIsProp ? -1 : 1;
		Tag.Title = Obj->Name;
		List.Add(MoveTemp(Tag));
	}
	Doc.NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::RemoveObjectTag(const FString& Alias, bool bIsProp)
{
	if (!Game || !Game->Document) return false;
	TArray<FOKVngeActorTag>& List = bIsProp ? Game->Document->Vnge.Registry.Props : Game->Document->Vnge.Registry.Actors;
	const int32 Removed = List.RemoveAll([&](const FOKVngeActorTag& T) { return T.Alias.Equals(Alias, ESearchCase::IgnoreCase); });
	if (Removed > 0) Game->Document->NotifyChanged();
	return Removed > 0;
}

void FOKStudioVngeRuntime::ApplyOrbitCameraUnity(const FVector& TargetM, const FVector& DistM, const FVector& RotDeg, float VertFovDeg)
{
	if (!Game || !Game->Document) return;
	const FVector TargetUe = FVector(-TargetM.X, TargetM.Z, TargetM.Y) * 100.0;
	const FQuat CamRotU = UnityEulerDegToQuat(RotDeg);
	const FVector CamWorldM = TargetM + CamRotU.RotateVector(DistM);
	FTransform CamUe = FOKStudioImport::UnityToUe(CamWorldM, RotDeg, FVector::OneVector);
	CamUe.SetRotation(CamUe.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI));
	const FRotator R = CamUe.GetRotation().Rotator();
	Game->Focus = TargetUe;
	Game->Distance = FMath::Max(5.f, float(FVector::Dist(TargetUe, CamUe.GetLocation())));
	Game->Pitch = R.Pitch;
	Game->Yaw = R.Yaw;
	const double VFovRad = FMath::DegreesToRadians(FMath::Clamp(double(VertFovDeg), 2.0, 165.0));
	const float HorizFov = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(VFovRad * 0.5) * (16.0 / 9.0))));
	Game->Document->FreeView.Fov = HorizFov;
	Game->Document->ActiveCamera = -1;
}

void FOKStudioVngeRuntime::ApplyObjectPatch(const FOKVngeObjectPatch& Patch, bool bAllowMotionChange)
{
	if (!Game || !Game->Document) return;
	UOKSceneDocument& Doc = *Game->Document;
	int32 TargetId = Patch.ObjectId;
	if (TargetId < 0 && !Patch.Alias.IsEmpty())
	{
		TargetId = Doc.Vnge.Registry.ResolveObjectId(Patch.Alias, &Doc);
	}
	FOKSceneObject* Obj = Doc.Find(TargetId);
	if (!Obj) return;

	if (Patch.Visible >= 0) Obj->bVisible = Patch.Visible != 0;
	if (Patch.bHasPos || Patch.bHasRot || Patch.bHasScale)
	{
		const FVector CurPosM = UeTransformToUnityPosM(Obj->Transform);
		FQuat CurRotUe = Obj->Transform.GetRotation();
		if (Obj->Kind == EOKSceneObjectKind::Camera || Obj->Kind == EOKSceneObjectKind::Light)
			CurRotUe = CurRotUe * FQuat(FVector::UpVector, -UE_HALF_PI);
		const FVector CurEuler = UeQuatToUnityEulerDeg(CurRotUe);
		const FVector CurScale(Obj->Transform.GetScale3D().X, Obj->Transform.GetScale3D().Z, Obj->Transform.GetScale3D().Y);
		FTransform NewT = FOKStudioImport::UnityToUe(
			Patch.bHasPos ? Patch.Pos : CurPosM,
			Patch.bHasRot ? Patch.Rot : CurEuler,
			Patch.bHasScale ? Patch.Scale : CurScale);
		if (Obj->Kind == EOKSceneObjectKind::Camera || Obj->Kind == EOKSceneObjectKind::Light)
			NewT.SetRotation(NewT.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI));
		Obj->Transform = NewT;
	}

	if (Obj->Kind == EOKSceneObjectKind::Character)
	{
		FOKSceneCharacter& C = Obj->Character;
		if (bAllowMotionChange && Patch.AnimGroup >= 0 && Patch.AnimCategory >= 0 && Patch.AnimNo >= 0)
		{
			if (const FOKStudioAnim* A = FOKStudioCatalog::Get().FindAnimAnyKind(Patch.AnimGroup, Patch.AnimCategory, Patch.AnimNo))
			{
				C.StudioAnimeKind = A->Kind;
				C.StudioAnimeGroup = Patch.AnimGroup;
				C.StudioAnimeCategory = Patch.AnimCategory;
				C.StudioAnimeNo = Patch.AnimNo;
				C.AnimFile.Reset();
			}
		}
		if (Patch.AnimSpeed >= 0.f) C.Speed = Patch.AnimSpeed;
		if (Patch.AnimTime >= 0.f) C.Time = Patch.AnimTime;
		if (!Patch.Fk.IsEmpty())
		{
			for (const FOKVngeFkEntry& FE : Patch.Fk)
			{
				if (FOKSceneFkBone* Existing = C.Fk.FindByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == FE.Bone; }))
					Existing->Euler = FE.Euler;
				else
					C.Fk.Add({ FE.Bone, FE.Euler });
			}
		}
		if (!Patch.Ik.IsEmpty())
		{
			for (const FOKVngeIkEntry& IE : Patch.Ik)
			{
				const FVector PosCm = FVector(-IE.Pos.X, IE.Pos.Z, IE.Pos.Y) * 100.0;
				if (FOKSceneIkTarget* Existing = C.Ik.FindByPredicate([&](const FOKSceneIkTarget& X) { return X.Effector == IE.Effector; }))
				{
					Existing->Position = PosCm;
					Existing->Euler = IE.Euler;
					Existing->bUseRotation = IE.bUseRotation;
				}
				else
				{
					FOKSceneIkTarget T;
					T.Effector = IE.Effector;
					T.Position = PosCm;
					T.Euler = IE.Euler;
					T.bUseRotation = IE.bUseRotation;
					C.Ik.Add(T);
				}
			}
		}
		if (Patch.EyebrowPtn >= 0) C.EyebrowPattern = Patch.EyebrowPtn;
		if (Patch.EyesPtn >= 0) C.EyesPattern = Patch.EyesPtn;
		if (Patch.EyesOpen >= 0.f) C.EyesOpen = FMath::Clamp(Patch.EyesOpen, 0.f, 1.f);
		if (Patch.MouthPtn >= 0) C.MouthPattern = Patch.MouthPtn;
		if (Patch.MouthOpen >= 0.f) C.MouthOpen = FMath::Clamp(Patch.MouthOpen, 0.f, 1.f);
		if (Patch.HandLeft >= -1) C.HandLeft = Patch.HandLeft <= 0 ? -1 : FMath::Min(Patch.HandLeft, 23);
		if (Patch.HandRight >= -1) C.HandRight = Patch.HandRight <= 0 ? -1 : FMath::Min(Patch.HandRight, 23);
		if (Patch.EyesLook >= 0) C.EyesLook = Patch.EyesLook == 1 ? EOKSceneLook::Camera : EOKSceneLook::Animation;
		if (Patch.NeckLook >= 0) C.NeckLook = Patch.NeckLook == 0 ? EOKSceneLook::Camera : EOKSceneLook::Animation;
		if (Patch.Outfit >= 0) C.Outfit = Patch.Outfit;
		if (!Patch.ClothesStates.IsEmpty())
		{
			for (int32 I = 0; I < FMath::Min(Patch.ClothesStates.Num(), C.ClothesStates.Num()); ++I)
				C.ClothesStates[I] = Patch.ClothesStates[I];
			if (Patch.ClothesStates.Num() == 8 && C.ClothesStates.Num() >= 9)
				C.ClothesStates[8] = C.ClothesStates[7];
		}
		if (!Patch.AccessoriesShown.IsEmpty())
		{
			if (C.AccessoriesShown.Num() < 21) C.AccessoriesShown.Init(1, 21);
			for (int32 I = 0; I < FMath::Min(Patch.AccessoriesShown.Num(), C.AccessoriesShown.Num()); ++I)
				C.AccessoriesShown[I] = Patch.AccessoriesShown[I];
		}
		if (Patch.TearsLv >= 0) C.TearsLevel = FMath::Clamp(Patch.TearsLv, 0, 3);
		if (Patch.Blush >= 0.f) C.Blush = FMath::Clamp(Patch.Blush, 0.f, 1.f);
		if (Patch.NipStand >= 0.f) C.NipStand = FMath::Clamp(Patch.NipStand, 0.f, 1.f);
		if (Patch.Fluids.Num() == 5) C.Fluids = Patch.Fluids;
	}
	else if (Obj->Kind == EOKSceneObjectKind::Item)
	{
		for (const FOKVngeFkEntry& FE : Patch.Fk)
		{
			if (FOKSceneFkBone* Existing = Obj->Item.Fk.FindByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == FE.Bone; }))
				Existing->Euler = FE.Euler;
			else
				Obj->Item.Fk.Add({ FE.Bone, FE.Euler });
		}
	}
	else if (Obj->Kind == EOKSceneObjectKind::Light)
	{
		if (Patch.LightIntensity >= 0.f) Obj->Light.Intensity = Patch.LightIntensity;
		if (Patch.LightEnable >= 0) Obj->bVisible = Patch.LightEnable != 0;
	}
}

bool FOKStudioVngeRuntime::ApplySssState(int32 StateIndex, bool bSmoothCamera)
{
	if (!Game || !Game->Document) return false;
	UOKSceneDocument& Doc = *Game->Document;
	if (!Doc.Vnge.Sss.States.IsValidIndex(StateIndex)) return false;
	const FOKVngeSceneState& St = Doc.Vnge.Sss.States[StateIndex];
	Doc.Vnge.Sss.ActiveStateIndex = StateIndex;
	for (const FOKVngeObjectPatch& P : St.Actors) ApplyObjectPatch(P, true);
	for (const FOKVngeObjectPatch& P : St.Props) ApplyObjectPatch(P, true);
	if (!St.WhoSay.IsEmpty() || !St.WhatSay.IsEmpty())
	{
		ActiveWhoSay = St.WhoSay;
		ActiveWhatSay = St.WhatSay;
	}
	const int32 CamIdx = St.LinkedCameraSlot >= 0 ? St.LinkedCameraSlot : StateIndex;
	if (Doc.Vnge.Sss.Cameras.IsValidIndex(CamIdx))
	{
		ApplySssCamera(CamIdx, bSmoothCamera ? Doc.Vnge.Sss.CameraTransitionSeconds : 0.f);
	}
	Doc.NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::ApplySssCamera(int32 CameraSlotIndex, float TransitionSeconds)
{
	if (!Game || !Game->Document) return false;
	UOKSceneDocument& Doc = *Game->Document;
	if (!Doc.Vnge.Sss.Cameras.IsValidIndex(CameraSlotIndex)) return false;
	const FOKVngeCameraSlot& Slot = Doc.Vnge.Sss.Cameras[CameraSlotIndex];
	Doc.Vnge.Sss.ActiveCameraSlot = CameraSlotIndex;
	if (!Slot.WhoSay.IsEmpty() || !Slot.WhatSay.IsEmpty())
	{
		ActiveWhoSay = Slot.WhoSay;
		ActiveWhatSay = Slot.WhatSay;
	}
	const float Dur = TransitionSeconds < 0.f ? Doc.Vnge.Sss.CameraTransitionSeconds : TransitionSeconds;
	if (Dur <= 0.001f)
	{
		bCamTransitionActive = false;
		ApplyOrbitCameraUnity(Slot.Pos, Slot.Distance, Slot.Rotate, Slot.Fov);
		return true;
	}
	CamStartTarget = FVector(-Game->Focus.X, Game->Focus.Z, Game->Focus.Y) * 0.01f;
	CamStartDist = FVector(0.f, 0.f, -Game->Distance * 0.01f);
	const FQuat CurUeQ = FRotator(Game->Pitch, Game->Yaw, 0.f).Quaternion() * FQuat(FVector::UpVector, -UE_HALF_PI);
	CamStartRot = UeQuatToUnityEulerDeg(CurUeQ);
	const double HFovRad = FMath::DegreesToRadians(FMath::Clamp(double(Doc.FreeView.Fov), 5.0, 170.0));
	CamStartFov = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(HFovRad * 0.5) * (9.0 / 16.0))));
	CamEndTarget = Slot.Pos;
	CamEndDist = Slot.Distance;
	CamEndRot = Slot.Rotate;
	CamEndFov = Slot.Fov;
	CamTransElapsed = 0.f;
	CamTransDuration = Dur;
	bCamTransitionActive = true;
	return true;
}

int32 FOKStudioVngeRuntime::CaptureCurrentSssCamera(const FString& WhoSay, const FString& WhatSay)
{
	if (!Game || !Game->Document) return -1;
	UOKSceneDocument& Doc = *Game->Document;
	FOKVngeCameraSlot Slot;
	Slot.Slot = Doc.Vnge.Sss.Cameras.Num();
	Slot.Pos = FVector(-Game->Focus.X, Game->Focus.Z, Game->Focus.Y) * 0.01f;
	Slot.Distance = FVector(0.f, 0.f, -Game->Distance * 0.01f);
	const FQuat CurUeQ = FRotator(Game->Pitch, Game->Yaw, 0.f).Quaternion() * FQuat(FVector::UpVector, -UE_HALF_PI);
	Slot.Rotate = UeQuatToUnityEulerDeg(CurUeQ);
	const double HFovRad = FMath::DegreesToRadians(FMath::Clamp(double(Doc.FreeView.Fov), 5.0, 170.0));
	Slot.Fov = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(HFovRad * 0.5) * (9.0 / 16.0))));
	Slot.WhoSay = WhoSay;
	Slot.WhatSay = WhatSay;
	const int32 Idx = Doc.Vnge.Sss.Cameras.Add(MoveTemp(Slot));
	Doc.Vnge.Sss.ActiveCameraSlot = Idx;
	Doc.NotifyChanged();
	return Idx;
}

int32 FOKStudioVngeRuntime::CaptureCurrentSssState(const FString& CustomId, const FString& WhoSay, const FString& WhatSay)
{
	if (!Game || !Game->Document) return -1;
	UOKSceneDocument& Doc = *Game->Document;
	AutoRegisterSceneTags();
	const int32 CamSlot = CaptureCurrentSssCamera(WhoSay, WhatSay);

	FOKVngeSceneState St;
	St.Id = CustomId.IsEmpty() ? FString::Printf(TEXT("%d"), Doc.Vnge.Sss.States.Num()) : CustomId;
	St.WhoSay = WhoSay;
	St.WhatSay = WhatSay;
	St.LinkedCameraSlot = CamSlot;

	for (const FOKVngeActorTag& Tag : Doc.Vnge.Registry.Actors)
	{
		const FOKSceneObject* Obj = Doc.Find(Tag.ObjectId);
		if (!Obj || Obj->Kind != EOKSceneObjectKind::Character) continue;
		const FOKSceneCharacter& C = Obj->Character;
		FOKVngeObjectPatch P;
		P.Alias = Tag.Alias;
		P.ObjectId = Obj->Id;
		P.Visible = Obj->bVisible ? 1 : 0;
		P.bHasPos = true; P.Pos = UeTransformToUnityPosM(Obj->Transform);
		P.bHasRot = true; P.Rot = UeQuatToUnityEulerDeg(Obj->Transform.GetRotation());
		P.bHasScale = true; P.Scale = FVector(Obj->Transform.GetScale3D().X, Obj->Transform.GetScale3D().Z, Obj->Transform.GetScale3D().Y);
		P.AnimGroup = C.StudioAnimeGroup;
		P.AnimCategory = C.StudioAnimeCategory;
		P.AnimNo = C.StudioAnimeNo;
		P.AnimSpeed = C.Speed;
		P.AnimTime = C.Time;
		for (const FOKSceneFkBone& B : C.Fk) P.Fk.Add({ B.Bone, B.Euler });
		for (const FOKSceneIkTarget& T : C.Ik)
		{
			FOKVngeIkEntry IE;
			IE.Effector = T.Effector;
			IE.Pos = FVector(-T.Position.X, T.Position.Z, T.Position.Y) * 0.01f;
			IE.Euler = T.Euler;
			IE.bUseRotation = T.bUseRotation;
			P.Ik.Add(IE);
		}
		P.EyebrowPtn = C.EyebrowPattern;
		P.EyesPtn = C.EyesPattern;
		P.EyesOpen = C.EyesOpen;
		P.MouthPtn = C.MouthPattern;
		P.MouthOpen = C.MouthOpen;
		P.HandLeft = C.HandLeft;
		P.HandRight = C.HandRight;
		P.Outfit = C.Outfit;
		P.ClothesStates = C.ClothesStates;
		P.AccessoriesShown = C.AccessoriesShown;
		P.TearsLv = C.TearsLevel;
		P.Blush = C.Blush;
		P.NipStand = C.NipStand;
		P.Fluids = C.Fluids;
		St.Actors.Add(MoveTemp(P));
	}

	for (const FOKVngeActorTag& Tag : Doc.Vnge.Registry.Props)
	{
		const FOKSceneObject* Obj = Doc.Find(Tag.ObjectId);
		if (!Obj) continue;
		FOKVngeObjectPatch P;
		P.Alias = Tag.Alias;
		P.ObjectId = Obj->Id;
		P.bIsProp = true;
		P.Visible = Obj->bVisible ? 1 : 0;
		P.bHasPos = true; P.Pos = UeTransformToUnityPosM(Obj->Transform);
		FQuat Q = Obj->Transform.GetRotation();
		if (Obj->Kind == EOKSceneObjectKind::Camera || Obj->Kind == EOKSceneObjectKind::Light) Q = Q * FQuat(FVector::UpVector, -UE_HALF_PI);
		P.bHasRot = true; P.Rot = UeQuatToUnityEulerDeg(Q);
		P.bHasScale = true; P.Scale = FVector(Obj->Transform.GetScale3D().X, Obj->Transform.GetScale3D().Z, Obj->Transform.GetScale3D().Y);
		if (Obj->Kind == EOKSceneObjectKind::Item)
		{
			for (const FOKSceneFkBone& B : Obj->Item.Fk) P.Fk.Add({ B.Bone, B.Euler });
		}
		else if (Obj->Kind == EOKSceneObjectKind::Light)
		{
			P.LightIntensity = Obj->Light.Intensity;
		}
		St.Props.Add(MoveTemp(P));
	}

	const int32 Idx = Doc.Vnge.Sss.States.Add(MoveTemp(St));
	Doc.Vnge.Sss.ActiveStateIndex = Idx;
	Doc.NotifyChanged();
	return Idx;
}

bool FOKStudioVngeRuntime::DeleteSssState(int32 StateIndex)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Sss.States.IsValidIndex(StateIndex)) return false;
	Game->Document->Vnge.Sss.States.RemoveAt(StateIndex);
	Game->Document->NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::DeleteSssCamera(int32 CameraSlotIndex)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Sss.Cameras.IsValidIndex(CameraSlotIndex)) return false;
	Game->Document->Vnge.Sss.Cameras.RemoveAt(CameraSlotIndex);
	Game->Document->NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::ApplyMinistate(int32 MinistateIndex, int32 OverrideTargetId)
{
	if (!Game || !Game->Document) return false;
	UOKSceneDocument& Doc = *Game->Document;
	if (!Doc.Vnge.Sss.Ministates.IsValidIndex(MinistateIndex)) return false;
	const FOKVngeMinistate& Ms = Doc.Vnge.Sss.Ministates[MinistateIndex];
	TSharedPtr<FJsonObject> Payload;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Ms.PayloadJson), Payload) || !Payload.IsValid()) return false;

	const int32 TargetId = OverrideTargetId >= 0 ? OverrideTargetId : Game->SelectedId;
	// Ministate payload can be either a direct pose dict or `{ "actors": { "f1": {...} }, "props": {...} }`
	const TSharedPtr<FJsonObject>* ActorsDict = nullptr;
	if (Payload->TryGetObjectField(TEXT("actors"), ActorsDict) && ActorsDict && ActorsDict->IsValid())
	{
		for (const TPair<FString, TSharedPtr<FJsonValue>>& KV : (*ActorsDict)->Values)
		{
			FOKVngeObjectPatch P;
			P.Alias = KV.Key;
			P.ObjectId = Doc.Vnge.Registry.ResolveObjectId(KV.Key, &Doc);
			if (P.ObjectId < 0) P.ObjectId = TargetId;
			ParseRawPoseDictToPatch(KV.Value->AsObject(), P);
			ApplyObjectPatch(P, true);
		}
	}
	else if (TargetId >= 0)
	{
		FOKVngeObjectPatch P;
		P.ObjectId = TargetId;
		ParseRawPoseDictToPatch(Payload, P);
		ApplyObjectPatch(P, true);
	}
	else return false;
	Doc.NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::PlayClip(int32 ClipIndex, bool bResetTime)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Clips.IsValidIndex(ClipIndex)) return false;
	FClipPlayState& St = ClipStates.FindOrAdd(ClipIndex);
	if (bResetTime) { St.Time = 0.f; St.PingPongDir = 1; }
	St.bPlaying = true;
	EvaluateClipAt(Game->Document->Vnge.Clips[ClipIndex], St.Time);
	return true;
}

void FOKStudioVngeRuntime::PauseClip(int32 ClipIndex)
{
	if (FClipPlayState* St = ClipStates.Find(ClipIndex)) St->bPlaying = false;
}

void FOKStudioVngeRuntime::StopClip(int32 ClipIndex)
{
	if (FClipPlayState* St = ClipStates.Find(ClipIndex))
	{
		St->bPlaying = false;
		St->Time = 0.f;
		St->PingPongDir = 1;
	}
}

void FOKStudioVngeRuntime::StopAllClips()
{
	ClipStates.Reset();
}

bool FOKStudioVngeRuntime::ScrubClip(int32 ClipIndex, float TimeSeconds)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Clips.IsValidIndex(ClipIndex)) return false;
	const FOKVngeClip& Clip = Game->Document->Vnge.Clips[ClipIndex];
	FClipPlayState& St = ClipStates.FindOrAdd(ClipIndex);
	St.Time = FMath::Clamp(TimeSeconds, 0.f, FMath::Max(0.05f, Clip.Duration));
	EvaluateClipAt(Clip, St.Time);
	return true;
}

const FOKStudioVngeRuntime::FClipPlayState* FOKStudioVngeRuntime::GetClipPlayState(int32 ClipIndex) const
{
	return ClipStates.Find(ClipIndex);
}

void FOKStudioVngeRuntime::EvaluateClipAt(const FOKVngeClip& Clip, float TimeSec)
{
	if (!Game || !Game->Document) return;
	UOKSceneDocument& Doc = *Game->Document;
	for (const FOKVngeTrack& Tr : Clip.Tracks)
	{
		if (Tr.Keys.IsEmpty()) continue;
		int32 IdxA = 0, IdxB = 0;
		float Alpha = 0.f;
		if (TimeSec <= Tr.Keys[0].Time)
		{
			IdxA = IdxB = 0;
		}
		else if (TimeSec >= Tr.Keys.Last().Time)
		{
			IdxA = IdxB = Tr.Keys.Num() - 1;
		}
		else
		{
			for (int32 I = 0; I + 1 < Tr.Keys.Num(); ++I)
			{
				if (TimeSec >= Tr.Keys[I].Time && TimeSec <= Tr.Keys[I + 1].Time)
				{
					IdxA = I;
					IdxB = I + 1;
					const float Span = Tr.Keys[I + 1].Time - Tr.Keys[I].Time;
					Alpha = Span > 1e-5f ? FMath::Clamp((TimeSec - Tr.Keys[I].Time) / Span, 0.f, 1.f) : 0.f;
					break;
				}
			}
		}
		const FOKVngeTrackKey& KA = Tr.Keys[IdxA];
		const FOKVngeTrackKey& KB = Tr.Keys[IdxB];
		if (Tr.TargetType == TEXT("cam"))
		{
			if (KA.bHasCam || KB.bHasCam)
			{
				const FVector Pos = FMath::Lerp(KA.CamPos, KB.CamPos, Alpha);
				const FVector Dst = FMath::Lerp(KA.CamDst, KB.CamDst, Alpha);
				const FVector Rot = UnityQuatToEulerDeg(FQuat::Slerp(UnityEulerDegToQuat(KA.CamRot), UnityEulerDegToQuat(KB.CamRot), Alpha));
				const float Fov = KA.bHasValue ? FMath::Lerp(KA.Value, KB.bHasValue ? KB.Value : KA.Value, Alpha) : 23.f;
				ApplyOrbitCameraUnity(Pos, Dst, Rot, Fov);
			}
			continue;
		}
		FOKVngeObjectPatch Patch;
		Patch.Alias = Tr.TargetAlias;
		Patch.ObjectId = Tr.ObjectId >= 0 ? Tr.ObjectId : Doc.Vnge.Registry.ResolveObjectId(Tr.TargetAlias, &Doc);
		Patch.Visible = KA.Visible;
		if (KA.bHasPos || KB.bHasPos) { Patch.bHasPos = true; Patch.Pos = FMath::Lerp(KA.Pos, KB.bHasPos ? KB.Pos : KA.Pos, Alpha); }
		if (KA.bHasRot || KB.bHasRot)
		{
			Patch.bHasRot = true;
			Patch.Rot = UnityQuatToEulerDeg(FQuat::Slerp(UnityEulerDegToQuat(KA.Rot), UnityEulerDegToQuat(KB.bHasRot ? KB.Rot : KA.Rot), Alpha));
		}
		if (KA.bHasScale || KB.bHasScale) { Patch.bHasScale = true; Patch.Scale = FMath::Lerp(KA.Scale, KB.bHasScale ? KB.Scale : KA.Scale, Alpha); }
		if (KA.bHasValue) Patch.LightIntensity = FMath::Lerp(KA.Value, KB.bHasValue ? KB.Value : KA.Value, Alpha);
		Patch.EyebrowPtn = KA.EyebrowPtn;
		Patch.EyesPtn = KA.EyesPtn;
		Patch.MouthPtn = KA.MouthPtn;
		if (KA.EyesOpen >= 0.f) Patch.EyesOpen = FMath::Lerp(KA.EyesOpen, KB.EyesOpen >= 0.f ? KB.EyesOpen : KA.EyesOpen, Alpha);
		if (KA.MouthOpen >= 0.f) Patch.MouthOpen = FMath::Lerp(KA.MouthOpen, KB.MouthOpen >= 0.f ? KB.MouthOpen : KA.MouthOpen, Alpha);
		Patch.HandLeft = KA.HandLeft;
		Patch.HandRight = KA.HandRight;
		Patch.AnimGroup = KA.AnimGroup;
		Patch.AnimCategory = KA.AnimCategory;
		Patch.AnimNo = KA.AnimNo;
		if (KA.AnimSpeed >= 0.f) Patch.AnimSpeed = FMath::Lerp(KA.AnimSpeed, KB.AnimSpeed >= 0.f ? KB.AnimSpeed : KA.AnimSpeed, Alpha);
		for (const FOKVngeFkEntry& FA : KA.Fk)
		{
			FVector Euler = FA.Euler;
			if (IdxB != IdxA)
			{
				if (const FOKVngeFkEntry* FB = KB.Fk.FindByPredicate([&](const FOKVngeFkEntry& X) { return X.Bone == FA.Bone; }))
					Euler = UnityQuatToEulerDeg(FQuat::Slerp(UnityEulerDegToQuat(FA.Euler), UnityEulerDegToQuat(FB->Euler), Alpha));
			}
			Patch.Fk.Add({ FA.Bone, Euler });
		}
		for (const FOKVngeIkEntry& IA : KA.Ik)
		{
			FOKVngeIkEntry IE = IA;
			if (IdxB != IdxA)
			{
				if (const FOKVngeIkEntry* IB = KB.Ik.FindByPredicate([&](const FOKVngeIkEntry& X) { return X.Effector == IA.Effector; }))
				{
					IE.Pos = FMath::Lerp(IA.Pos, IB->Pos, Alpha);
					IE.Euler = UnityQuatToEulerDeg(FQuat::Slerp(UnityEulerDegToQuat(IA.Euler), UnityEulerDegToQuat(IB->Euler), Alpha));
				}
			}
			Patch.Ik.Add(IE);
		}
		ApplyObjectPatch(Patch, true);
	}
	if (Game->SceneActor) Game->SyncDocumentNow();
}

int32 FOKStudioVngeRuntime::CreateClip(const FString& Name, float Duration, float FrameRate)
{
	if (!Game || !Game->Document) return -1;
	FOKVngeClip Clip;
	Clip.Name = Name.IsEmpty() ? FString::Printf(TEXT("Clip_%d"), Game->Document->Vnge.Clips.Num() + 1) : Name;
	Clip.Duration = FMath::Max(0.2f, Duration);
	Clip.FrameRate = FMath::Clamp(FrameRate, 1.f, 120.f);
	Clip.FrameLength = Clip.Duration * Clip.FrameRate;
	const int32 Idx = Game->Document->Vnge.Clips.Add(MoveTemp(Clip));
	Game->Document->NotifyChanged();
	return Idx;
}

bool FOKStudioVngeRuntime::DeleteClip(int32 ClipIndex)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Clips.IsValidIndex(ClipIndex)) return false;
	StopClip(ClipIndex);
	Game->Document->Vnge.Clips.RemoveAt(ClipIndex);
	Game->Document->NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::RecordKeyToClip(int32 ClipIndex, int32 ObjectId, float TimeSeconds)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Clips.IsValidIndex(ClipIndex)) return false;
	UOKSceneDocument& Doc = *Game->Document;
	const FOKSceneObject* Obj = Doc.Find(ObjectId);
	if (!Obj) return false;
	FOKVngeClip& Clip = Doc.Vnge.Clips[ClipIndex];
	const float T = FMath::Max(0.f, TimeSeconds);
	Clip.Duration = FMath::Max(Clip.Duration, T);
	Clip.FrameLength = Clip.Duration * FMath::Max(1.f, Clip.FrameRate);

	FOKVngeTrack* Tr = Clip.Tracks.FindByPredicate([ObjectId](const FOKVngeTrack& X) { return X.ObjectId == ObjectId && X.TargetType != TEXT("cam"); });
	if (!Tr)
	{
		FOKVngeTrack NewTr;
		NewTr.ObjectId = ObjectId;
		NewTr.TargetType = Obj->Kind == EOKSceneObjectKind::Character ? TEXT("actor") : TEXT("prop");
		NewTr.TargetAlias = Obj->Name.IsEmpty() ? FString::Printf(TEXT("%d"), ObjectId) : Obj->Name;
		Tr = &Clip.Tracks.Add_GetRef(MoveTemp(NewTr));
	}

	FOKVngeTrackKey Key;
	Key.Time = T;
	Key.Visible = Obj->bVisible ? 1 : 0;
	Key.bHasPos = true; Key.Pos = UeTransformToUnityPosM(Obj->Transform);
	FQuat Q = Obj->Transform.GetRotation();
	if (Obj->Kind == EOKSceneObjectKind::Camera || Obj->Kind == EOKSceneObjectKind::Light) Q = Q * FQuat(FVector::UpVector, -UE_HALF_PI);
	Key.bHasRot = true; Key.Rot = UeQuatToUnityEulerDeg(Q);
	Key.bHasScale = true; Key.Scale = FVector(Obj->Transform.GetScale3D().X, Obj->Transform.GetScale3D().Z, Obj->Transform.GetScale3D().Y);
	if (Obj->Kind == EOKSceneObjectKind::Character)
	{
		const FOKSceneCharacter& C = Obj->Character;
		for (const FOKSceneFkBone& B : C.Fk) Key.Fk.Add({ B.Bone, B.Euler });
		for (const FOKSceneIkTarget& Ik : C.Ik)
		{
			FOKVngeIkEntry IE;
			IE.Effector = Ik.Effector;
			IE.Pos = FVector(-Ik.Position.X, Ik.Position.Z, Ik.Position.Y) * 0.01f;
			IE.Euler = Ik.Euler;
			IE.bUseRotation = Ik.bUseRotation;
			Key.Ik.Add(IE);
		}
		Key.EyebrowPtn = C.EyebrowPattern;
		Key.EyesPtn = C.EyesPattern;
		Key.MouthPtn = C.MouthPattern;
		Key.EyesOpen = C.EyesOpen;
		Key.MouthOpen = C.MouthOpen;
		Key.HandLeft = C.HandLeft;
		Key.HandRight = C.HandRight;
		Key.AnimGroup = C.StudioAnimeGroup;
		Key.AnimCategory = C.StudioAnimeCategory;
		Key.AnimNo = C.StudioAnimeNo;
		Key.AnimSpeed = C.Speed;
	}

	if (FOKVngeTrackKey* Existing = Tr->Keys.FindByPredicate([T](const FOKVngeTrackKey& K) { return FMath::IsNearlyEqual(K.Time, T, 1e-3f); }))
		*Existing = MoveTemp(Key);
	else
	{
		Tr->Keys.Add(MoveTemp(Key));
		Tr->Keys.Sort([](const FOKVngeTrackKey& A, const FOKVngeTrackKey& B) { return A.Time < B.Time; });
	}
	Doc.NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::RecordCameraKeyToClip(int32 ClipIndex, float TimeSeconds)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Clips.IsValidIndex(ClipIndex)) return false;
	UOKSceneDocument& Doc = *Game->Document;
	FOKVngeClip& Clip = Doc.Vnge.Clips[ClipIndex];
	const float T = FMath::Max(0.f, TimeSeconds);
	Clip.Duration = FMath::Max(Clip.Duration, T);
	Clip.FrameLength = Clip.Duration * FMath::Max(1.f, Clip.FrameRate);

	FOKVngeTrack* Tr = Clip.Tracks.FindByPredicate([](const FOKVngeTrack& X) { return X.TargetType == TEXT("cam"); });
	if (!Tr)
	{
		FOKVngeTrack NewTr;
		NewTr.TargetAlias = TEXT("cam");
		NewTr.TargetType = TEXT("cam");
		Tr = &Clip.Tracks.Add_GetRef(MoveTemp(NewTr));
	}

	FOKVngeTrackKey Key;
	Key.Time = T;
	Key.bHasCam = true;
	Key.CamPos = FVector(-Game->Focus.X, Game->Focus.Z, Game->Focus.Y) * 0.01f;
	Key.CamDst = FVector(0.f, 0.f, -Game->Distance * 0.01f);
	const FQuat CurUeQ = FRotator(Game->Pitch, Game->Yaw, 0.f).Quaternion() * FQuat(FVector::UpVector, -UE_HALF_PI);
	Key.CamRot = UeQuatToUnityEulerDeg(CurUeQ);
	Key.bHasValue = true;
	const double HFovRad = FMath::DegreesToRadians(FMath::Clamp(double(Doc.FreeView.Fov), 5.0, 170.0));
	Key.Value = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(HFovRad * 0.5) * (9.0 / 16.0))));

	if (FOKVngeTrackKey* Existing = Tr->Keys.FindByPredicate([T](const FOKVngeTrackKey& K) { return FMath::IsNearlyEqual(K.Time, T, 1e-3f); }))
		*Existing = MoveTemp(Key);
	else
	{
		Tr->Keys.Add(MoveTemp(Key));
		Tr->Keys.Sort([](const FOKVngeTrackKey& A, const FOKVngeTrackKey& B) { return A.Time < B.Time; });
	}
	Doc.NotifyChanged();
	return true;
}

void FOKStudioVngeRuntime::BakeClipToDocumentTimeline(const FOKVngeClip& Clip, UOKSceneDocument& Doc, bool bReplaceExisting)
{
	if (bReplaceExisting)
	{
		Doc.Tracks.Reset();
		Doc.TimelineTracks.Reset();
	}
	Doc.Duration = FMath::Max(Doc.Duration, Clip.Duration);
	Doc.bLoopTimeline = Clip.LoopMode != 0;

	for (const FOKVngeTrack& Tr : Clip.Tracks)
	{
		if (Tr.Keys.IsEmpty()) continue;
		if (Tr.TargetType == TEXT("cam"))
		{
			const FString CamName = TEXT("VNGE 镜头");
			const FOKSceneObject* OldCam = Doc.Objects.FindByPredicate([&](const FOKSceneObject& O) { return O.Kind == EOKSceneObjectKind::Camera && O.Name == CamName; });
			const int32 CamId = OldCam ? OldCam->Id : Doc.AddObject(EOKSceneObjectKind::Camera, CamName, -1);
			Doc.Tracks.RemoveAll([CamId](const FOKSceneTrack& X) { return X.ObjectId == CamId; });
			FOKSceneTrack OutTr;
			OutTr.ObjectId = CamId;
			for (const FOKVngeTrackKey& K : Tr.Keys)
			{
				if (!K.bHasCam) continue;
				const FQuat CamRotU = UnityEulerDegToQuat(K.CamRot);
				const FVector CamWorldM = K.CamPos + CamRotU.RotateVector(K.CamDst);
				FTransform CamUe = FOKStudioImport::UnityToUe(CamWorldM, K.CamRot, FVector::OneVector);
				CamUe.SetRotation(CamUe.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI));
				FOKSceneKey OutK;
				OutK.Time = K.Time;
				OutK.Transform = CamUe;
				if (K.bHasValue)
				{
					const double VFovRad = FMath::DegreesToRadians(FMath::Clamp(double(K.Value), 2.0, 165.0));
					OutK.Value = float(FMath::RadiansToDegrees(2.0 * FMath::Atan(FMath::Tan(VFovRad * 0.5) * (16.0 / 9.0))));
				}
				else OutK.Value = 40.f;
				OutTr.Keys.Add(OutK);
			}
			if (!OutTr.Keys.IsEmpty())
			{
				if (FOKSceneObject* CamObj = Doc.Find(CamId))
				{
					CamObj->Transform = OutTr.Keys[0].Transform;
					CamObj->Camera.Fov = OutTr.Keys[0].Value;
				}
				Doc.ActiveCamera = CamId;
				Doc.Tracks.Add(MoveTemp(OutTr));
			}
			continue;
		}

		const int32 ObjId = Tr.ObjectId >= 0 ? Tr.ObjectId : Doc.Vnge.Registry.ResolveObjectId(Tr.TargetAlias, &Doc);
		const FOKSceneObject* BaseObj = Doc.Find(ObjId);
		if (!BaseObj) continue;
		Doc.Tracks.RemoveAll([ObjId](const FOKSceneTrack& X) { return X.ObjectId == ObjId; });
		FOKSceneTrack OutTr;
		OutTr.ObjectId = ObjId;
		FOKSceneTimelineTrack VisTl;
		VisTl.Owner = TEXT("Timeline");
		VisTl.InterpolableId = TEXT("objectEnabled");
		VisTl.ObjectId = ObjId;
		VisTl.Alias = BaseObj->Name + TEXT(" 显隐 (VNGE)");
		VisTl.GroupPath = TEXT("VNGE 烘焙");
		FOKSceneTimelineTrack EyesOpenTl;
		EyesOpenTl.Owner = TEXT("Timeline");
		EyesOpenTl.InterpolableId = TEXT("characterEyesOpen");
		EyesOpenTl.ObjectId = ObjId;
		EyesOpenTl.Alias = BaseObj->Name + TEXT(" 睁眼度 (VNGE)");
		EyesOpenTl.GroupPath = TEXT("VNGE 烘焙");
		TMap<int32, FOKSceneTimelineTrack> IkPosTls, IkRotTls;
		FTransform CurT = BaseObj->Transform;
		for (const FOKVngeTrackKey& K : Tr.Keys)
		{
			FOKSceneKey OutK;
			OutK.Time = K.Time;
			if (K.Visible >= 0)
			{
				FOKSceneTimelineKeyframe Vk;
				Vk.Time = K.Time;
				Vk.Values = { K.Visible != 0 ? 1.f : 0.f };
				VisTl.Keyframes.Add(MoveTemp(Vk));
			}
			if (K.bHasPos || K.bHasRot || K.bHasScale)
			{
				const FVector CurPosM = UeTransformToUnityPosM(CurT);
				FQuat CurRotUe = CurT.GetRotation();
				if (BaseObj->Kind == EOKSceneObjectKind::Camera || BaseObj->Kind == EOKSceneObjectKind::Light)
					CurRotUe = CurRotUe * FQuat(FVector::UpVector, -UE_HALF_PI);
				const FVector CurEuler = UeQuatToUnityEulerDeg(CurRotUe);
				const FVector CurScale(CurT.GetScale3D().X, CurT.GetScale3D().Z, CurT.GetScale3D().Y);
				CurT = FOKStudioImport::UnityToUe(K.bHasPos ? K.Pos : CurPosM, K.bHasRot ? K.Rot : CurEuler, K.bHasScale ? K.Scale : CurScale);
				if (BaseObj->Kind == EOKSceneObjectKind::Camera || BaseObj->Kind == EOKSceneObjectKind::Light)
					CurT.SetRotation(CurT.GetRotation() * FQuat(FVector::UpVector, UE_HALF_PI));
			}
			OutK.Transform = CurT;
			if (K.bHasValue) OutK.Value = K.Value;
			if (BaseObj->Kind == EOKSceneObjectKind::Character)
			{
				for (const FOKVngeFkEntry& FE : K.Fk) OutK.Fk.Add({ FE.Bone, FE.Euler });
				for (const FOKVngeIkEntry& IE : K.Ik)
				{
					FOKSceneTimelineTrack& PosTl = IkPosTls.FindOrAdd(IE.Effector);
					if (PosTl.InterpolableId.IsEmpty())
					{
						PosTl.Owner = TEXT("Timeline");
						PosTl.InterpolableId = TEXT("guideObjectPos");
						PosTl.ObjectId = ObjId;
						PosTl.TargetIkEffector = IE.Effector;
						PosTl.GroupPath = TEXT("VNGE 烘焙");
					}
					FOKSceneTimelineKeyframe Pk;
					Pk.Time = K.Time;
					Pk.Values = { float(IE.Pos.X), float(IE.Pos.Y), float(IE.Pos.Z) };
					PosTl.Keyframes.Add(MoveTemp(Pk));
					if (IE.bUseRotation)
					{
						FOKSceneTimelineTrack& RotTl = IkRotTls.FindOrAdd(IE.Effector);
						if (RotTl.InterpolableId.IsEmpty())
						{
							RotTl.Owner = TEXT("Timeline");
							RotTl.InterpolableId = TEXT("guideObjectRot");
							RotTl.ObjectId = ObjId;
							RotTl.TargetIkEffector = IE.Effector;
							RotTl.GroupPath = TEXT("VNGE 烘焙");
						}
						const FQuat Qx(FVector(1, 0, 0), FMath::DegreesToRadians(IE.Euler.X));
						const FQuat Qy(FVector(0, 1, 0), FMath::DegreesToRadians(IE.Euler.Y));
						const FQuat Qz(FVector(0, 0, 1), FMath::DegreesToRadians(IE.Euler.Z));
						const FQuat Uq = (Qy * Qx * Qz).GetNormalized();
						FOKSceneTimelineKeyframe Rk;
						Rk.Time = K.Time;
						Rk.Values = { float(Uq.X), float(Uq.Y), float(Uq.Z), float(Uq.W) };
						RotTl.Keyframes.Add(MoveTemp(Rk));
					}
				}
				if (K.EyesOpen >= 0.f)
				{
					FOKSceneTimelineKeyframe Ek;
					Ek.Time = K.Time;
					Ek.Values = { K.EyesOpen };
					EyesOpenTl.Keyframes.Add(MoveTemp(Ek));
				}
				if (K.EyebrowPtn >= 0 || K.EyesPtn >= 0 || K.MouthPtn >= 0 || K.MouthOpen >= 0.f || K.HandLeft >= -1 || K.HandRight >= -1)
				{
					OutK.bCharacterState = true;
					OutK.EyebrowPattern = K.EyebrowPtn >= 0 ? K.EyebrowPtn : BaseObj->Character.EyebrowPattern;
					OutK.EyesPattern = K.EyesPtn >= 0 ? K.EyesPtn : BaseObj->Character.EyesPattern;
					OutK.MouthPattern = K.MouthPtn >= 0 ? K.MouthPtn : BaseObj->Character.MouthPattern;
					OutK.MouthOpen = K.MouthOpen;
					OutK.HandLeft = K.HandLeft >= -1 ? K.HandLeft : BaseObj->Character.HandLeft;
					OutK.HandRight = K.HandRight >= -1 ? K.HandRight : BaseObj->Character.HandRight;
				}
				if (K.AnimGroup >= 0 && K.AnimCategory >= 0 && K.AnimNo >= 0)
				{
					if (const FOKStudioAnim* A = FOKStudioCatalog::Get().FindAnimAnyKind(K.AnimGroup, K.AnimCategory, K.AnimNo))
					{
						OutK.AnimKind = A->Kind;
						OutK.AnimGroup = K.AnimGroup;
						OutK.AnimCategory = K.AnimCategory;
						OutK.AnimNo = K.AnimNo;
						OutK.AnimSpeed = K.AnimSpeed >= 0.f ? K.AnimSpeed : 1.f;
					}
				}
			}
			OutTr.Keys.Add(MoveTemp(OutK));
		}
		if (!OutTr.Keys.IsEmpty()) Doc.Tracks.Add(MoveTemp(OutTr));
		if (!VisTl.Keyframes.IsEmpty()) Doc.TimelineTracks.Add(MoveTemp(VisTl));
		if (!EyesOpenTl.Keyframes.IsEmpty()) Doc.TimelineTracks.Add(MoveTemp(EyesOpenTl));
		for (auto& Kv : IkPosTls) if (!Kv.Value.Keyframes.IsEmpty()) Doc.TimelineTracks.Add(MoveTemp(Kv.Value));
		for (auto& Kv : IkRotTls) if (!Kv.Value.Keyframes.IsEmpty()) Doc.TimelineTracks.Add(MoveTemp(Kv.Value));
	}
}

bool FOKStudioVngeRuntime::BakeClipToTimeline(int32 ClipIndex, bool bReplaceExisting)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Clips.IsValidIndex(ClipIndex)) return false;
	BakeClipToDocumentTimeline(Game->Document->Vnge.Clips[ClipIndex], *Game->Document, bReplaceExisting);
	Game->SetTimelineTime(0.f);
	Game->Document->NotifyChanged();
	return true;
}

FString FOKStudioVngeRuntime::ResolvePoseLibRoot()
{
	TArray<FString> Candidates;
	FString CfgRoot;
	if (GConfig)
	{
		GConfig->GetString(TEXT("/Script/KKSideloader.KKGameRootSettings"), TEXT("Root"), CfgRoot, GGameIni);
		if (CfgRoot.IsEmpty()) GConfig->GetString(TEXT("KKGameRoot"), TEXT("Root"), CfgRoot, GGameIni);
	}
	if (!CfgRoot.IsEmpty()) Candidates.Add(CfgRoot / TEXT("BepInEx/plugins/Console/Lib/sss"));
	Candidates.Add(TEXT("E:/Koikatu/BepInEx/plugins/Console/Lib/sss"));
	Candidates.Add(TEXT("D:/Koikatu/BepInEx/plugins/Console/Lib/sss"));
	for (const FString& C : Candidates)
	{
		if (IFileManager::Get().DirectoryExists(*C)) return FPaths::ConvertRelativePathToFull(C);
	}
	const FString Fallback = FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir() / TEXT("OKStudio/PoseLib/sss"));
	IFileManager::Get().MakeDirectory(*Fallback, true);
	return Fallback;
}

TArray<FString> FOKStudioVngeRuntime::GetPoseLibCategories(const FString& RootDir)
{
	const FString Root = RootDir.IsEmpty() ? ResolvePoseLibRoot() : RootDir;
	static const TCHAR* Ordered[] = {
		TEXT("ffaces"), TEXT("fposes"), TEXT("fstatus"), TEXT("lhand"), TEXT("rhand"),
		TEXT("mfaces"), TEXT("mposes"), TEXT("mstatus"), TEXT("vnacharpose"), TEXT("vnachar"),
		TEXT("propfk"), TEXT("propvnanime"), TEXT("xxpelib")
	};
	TArray<FString> OnDisk;
	IFileManager::Get().FindFiles(OnDisk, *(Root / TEXT("*")), false, true);
	OnDisk.Sort();
	TArray<FString> Cats;
	for (const TCHAR* K : Ordered)
	{
		if (OnDisk.Contains(K)) Cats.Add(K);
	}
	for (const FString& D : OnDisk) Cats.AddUnique(D);
	if (Cats.IsEmpty())
	{
		for (const TCHAR* K : Ordered) Cats.Add(K);
	}
	return Cats;
}

TArray<FOKVngePosePresetItem> FOKStudioVngeRuntime::ScanPosePresets(const FString& Category, const FString& SearchFilter)
{
	TArray<FOKVngePosePresetItem> Items;
	const FString Dir = ResolvePoseLibRoot() / Category;
	if (!IFileManager::Get().DirectoryExists(*Dir)) return Items;

	TArray<FString> Files;
	IFileManager::Get().FindFilesRecursive(Files, *Dir, TEXT("*.*"), true, false);
	Files.Sort();
	const FString Filter = SearchFilter.TrimStartAndEnd();
	for (const FString& Full : Files)
	{
		const FString Ext = FPaths::GetExtension(Full).ToLower();
		if (Ext != TEXT("png") && Ext != TEXT("txt") && Ext != TEXT("json")) continue;
		FString Rel = Full;
		FPaths::MakePathRelativeTo(Rel, *(Dir + TEXT("/")));
		const FString Display = FPaths::ChangeExtension(Rel, TEXT(""));
		if (!Filter.IsEmpty() && !Display.Contains(Filter, ESearchCase::IgnoreCase)) continue;
		FOKVngePosePresetItem Item;
		Item.Name = Display;
		Item.Category = Category;
		Item.FullPath = Full;
		Item.bIsPng = Ext == TEXT("png");
		Items.Add(MoveTemp(Item));
	}
	return Items;
}

UTexture2D* FOKStudioVngeRuntime::GetPresetThumbnail(const FString& FilePath)
{
	if (const TStrongObjectPtr<UTexture2D>* Cached = PresetThumbnails.Find(FilePath))
	{
		return Cached->Get();
	}
	TArray<uint8> Bytes;
	if (!FFileHelper::LoadFileToArray(Bytes, *FilePath)) return nullptr;
	const int32 PngLen = PngPrefixLength(Bytes);
	if (PngLen <= 0) return nullptr;
	TArrayView64<const uint8> View(Bytes.GetData(), PngLen);
	if (UTexture2D* Tex = FImageUtils::ImportBufferAsTexture2D(View))
	{
		PresetThumbnails.Add(FilePath, TStrongObjectPtr<UTexture2D>(Tex));
		return Tex;
	}
	return nullptr;
}

bool FOKStudioVngeRuntime::ApplyPosePreset(const FString& FilePath, int32 TargetCharaId, FString& OutError)
{
	if (!Game || !Game->Document) { OutError = TEXT("工作室未运行"); return false; }
	const FTCHARToUTF8 PathUtf8(*FilePath);
	const int32 Needed = ok_studio_vnge_pose_read(PathUtf8.Get(), nullptr, 0);
	if (Needed <= 0) { OutError = TEXT("无法解析预设文件: ") + FilePath; return false; }
	TArray<char> Buf;
	Buf.SetNumZeroed(Needed + 1);
	if (ok_studio_vnge_pose_read(PathUtf8.Get(), Buf.GetData(), Buf.Num()) < 0)
	{
		OutError = TEXT("读取预设失败: ") + FilePath;
		return false;
	}
	const FString JsonStr = UTF8_TO_TCHAR(Buf.GetData());
	TSharedPtr<FJsonObject> Root;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(JsonStr), Root) || !Root.IsValid())
	{
		OutError = TEXT("预设 JSON 解析失败");
		return false;
	}
	const TSharedPtr<FJsonObject>* PoseObj = nullptr;
	const TSharedPtr<FJsonObject> ActivePose = (Root->TryGetObjectField(TEXT("pose"), PoseObj) && PoseObj && PoseObj->IsValid()) ? *PoseObj : Root;

	// Camera preset (`cams` category)
	FVector CamPos, CamDst, CamRot;
	if (ReadVec3(ActivePose, TEXT("cam_pos"), CamPos) || ReadVec3(ActivePose, TEXT("pos"), CamPos))
	{
		if (ReadVec3(ActivePose, TEXT("cam_dst"), CamDst) || ReadVec3(ActivePose, TEXT("distance"), CamDst))
		{
			ReadVec3(ActivePose, TEXT("cam_rot"), CamRot);
			ReadVec3(ActivePose, TEXT("rotate"), CamRot);
			const float Fov = ActivePose->HasField(TEXT("fov")) ? float(ActivePose->GetNumberField(TEXT("fov"))) : 23.f;
			ApplyOrbitCameraUnity(CamPos, CamDst, CamRot, Fov);
			return true;
		}
	}

	const int32 TargetId = TargetCharaId >= 0 ? TargetCharaId : Game->SelectedId;
	if (!Game->Document->Find(TargetId))
	{
		OutError = TEXT("请先选中要应用预设的角色或对象");
		return false;
	}
	FOKVngeObjectPatch Patch;
	Patch.ObjectId = TargetId;
	ParseRawPoseDictToPatch(ActivePose, Patch);
	ApplyObjectPatch(Patch, true);
	Game->Document->NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::SavePosePreset(const FString& Category, const FString& PresetName, int32 SourceCharaId, bool bSaveAsPng, FString& OutSavedPath, FString& OutError)
{
	if (!Game || !Game->Document) { OutError = TEXT("工作室未运行"); return false; }
	const int32 CharaId = SourceCharaId >= 0 ? SourceCharaId : Game->SelectedId;
	const FOKSceneObject* Obj = Game->Document->Find(CharaId);
	if (!Obj || Obj->Kind != EOKSceneObjectKind::Character)
	{
		OutError = TEXT("请先选中一个角色以保存预设");
		return false;
	}
	const FOKSceneCharacter& C = Obj->Character;
	const FString Cat = Category.IsEmpty() ? TEXT("fposes") : Category;
	const FString CleanName = FPaths::MakeValidFileName(PresetName.IsEmpty() ? TEXT("Preset") : PresetName);
	const FString Dir = ResolvePoseLibRoot() / Cat;
	IFileManager::Get().MakeDirectory(*Dir, true);
	OutSavedPath = Dir / (CleanName + (bSaveAsPng ? TEXT(".png") : TEXT(".txt")));

	TSharedRef<FJsonObject> Pose = MakeShared<FJsonObject>();
	Pose->SetNumberField(TEXT("eyebrow"), C.EyebrowPattern);
	Pose->SetNumberField(TEXT("eyes"), C.EyesPattern);
	if (C.EyesOpen >= 0.f) Pose->SetNumberField(TEXT("eyes_open"), C.EyesOpen);
	Pose->SetNumberField(TEXT("mouth"), C.MouthPattern);
	if (C.MouthOpen >= 0.f) Pose->SetNumberField(TEXT("mouth_open"), C.MouthOpen);
	Pose->SetArrayField(TEXT("hands"), { MakeShared<FJsonValueNumber>(FMath::Max(0, C.HandLeft)), MakeShared<FJsonValueNumber>(FMath::Max(0, C.HandRight)) });
	if (C.StudioAnimeGroup >= 0)
	{
		Pose->SetArrayField(TEXT("anim"), { MakeShared<FJsonValueNumber>(C.StudioAnimeGroup), MakeShared<FJsonValueNumber>(C.StudioAnimeCategory), MakeShared<FJsonValueNumber>(C.StudioAnimeNo) });
		Pose->SetNumberField(TEXT("anim_spd"), C.Speed);
	}
	if (!C.Fk.IsEmpty())
	{
		TSharedRef<FJsonObject> FkObj = MakeShared<FJsonObject>();
		for (const FOKSceneFkBone& B : C.Fk)
		{
			FkObj->SetArrayField(B.Bone, { MakeShared<FJsonValueNumber>(B.Euler.X), MakeShared<FJsonValueNumber>(B.Euler.Y), MakeShared<FJsonValueNumber>(B.Euler.Z) });
		}
		Pose->SetObjectField(TEXT("fk_set"), FkObj);
	}
	if (!C.Ik.IsEmpty())
	{
		static const int32 EffToNo[13] = { 0, 1, 4, 7, 10, 3, 6, 9, 12, 2, 5, 8, 11 };
		TSharedRef<FJsonObject> IkObj = MakeShared<FJsonObject>();
		for (const FOKSceneIkTarget& T : C.Ik)
		{
			if (T.Effector < 0 || T.Effector >= 13) continue;
			const FVector PM = FVector(-T.Position.X, T.Position.Z, T.Position.Y) * 0.01f;
			TArray<TSharedPtr<FJsonValue>> PosArr = { MakeShared<FJsonValueNumber>(PM.X), MakeShared<FJsonValueNumber>(PM.Y), MakeShared<FJsonValueNumber>(PM.Z) };
			TArray<TSharedPtr<FJsonValue>> RotArr = { MakeShared<FJsonValueNumber>(T.Euler.X), MakeShared<FJsonValueNumber>(T.Euler.Y), MakeShared<FJsonValueNumber>(T.Euler.Z) };
			IkObj->SetArrayField(FString::Printf(TEXT("%d"), EffToNo[T.Effector]), { MakeShared<FJsonValueArray>(PosArr), MakeShared<FJsonValueArray>(RotArr) });
		}
		Pose->SetObjectField(TEXT("ik_set"), IkObj);
	}
	TArray<TSharedPtr<FJsonValue>> ClothArr;
	for (uint8 St : C.ClothesStates) ClothArr.Add(MakeShared<FJsonValueNumber>(St));
	Pose->SetArrayField(TEXT("cloth_all"), ClothArr);

	TSharedRef<FJsonObject> Wrapper = MakeShared<FJsonObject>();
	Wrapper->SetObjectField(TEXT("pose"), Pose);
	FString PayloadJson;
	FJsonSerializer::Serialize(Wrapper, TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&PayloadJson));

	if (!bSaveAsPng)
	{
		if (!FFileHelper::SaveStringToFile(PayloadJson, *OutSavedPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))
		{
			OutError = TEXT("无法写入预设文件: ") + OutSavedPath;
			return false;
		}
		return true;
	}

	TArray<uint8> ThumbBytes;
	const FString TempShot = FPaths::ProjectSavedDir() / TEXT("OKStudio/poselib_thumb_tmp.png");
	FString CapErr;
	if (Game->CaptureToPng(TempShot, 256, 256, CapErr, false))
	{
		FFileHelper::LoadFileToArray(ThumbBytes, *TempShot);
		IFileManager::Get().Delete(*TempShot, false, true, true);
	}
	const FTCHARToUTF8 PathUtf8(*OutSavedPath);
	const FTCHARToUTF8 CatUtf8(*(TEXT("sss/") + Cat + TEXT("/")));
	const FTCHARToUTF8 JsonUtf8(*PayloadJson);
	char ErrBuf[512] = {};
	if (ok_studio_vnge_pose_write(PathUtf8.Get(), CatUtf8.Get(), JsonUtf8.Get(), ThumbBytes.IsEmpty() ? nullptr : ThumbBytes.GetData(), ThumbBytes.Num(), ErrBuf, sizeof(ErrBuf)) != 0)
	{
		OutError = UTF8_TO_TCHAR(ErrBuf);
		return false;
	}
	PresetThumbnails.Remove(OutSavedPath);
	return true;
}

int32 FOKStudioVngeRuntime::AddTextEntry(const FString& InitialText, bool bIs3D)
{
	if (!Game || !Game->Document) return -1;
	FOKVngeTextEntry Entry;
	Entry.Id = FString::Printf(TEXT("text_%d"), Game->Document->Vnge.Texts.Num() + 1);
	Entry.Text = InitialText.IsEmpty() ? TEXT("新建字幕文本") : InitialText;
	Entry.bIs3D = bIs3D;
	Entry.bBindCam = !bIs3D;
	Entry.Size = bIs3D ? 28.f : 26.f;
	Entry.Position = bIs3D ? UeTransformToUnityPosM(FTransform(Game->Focus + FVector(0.f, 0.f, 60.f))) : FVector(0.5f, 0.85f, 0.f);
	const int32 Idx = Game->Document->Vnge.Texts.Add(MoveTemp(Entry));
	Game->Document->NotifyChanged();
	return Idx;
}

bool FOKStudioVngeRuntime::RemoveTextEntry(int32 Index)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Texts.IsValidIndex(Index)) return false;
	Game->Document->Vnge.Texts.RemoveAt(Index);
	Game->Document->NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::PlaySoundSource(int32 SourceIndex, FString& OutError)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Sounds.IsValidIndex(SourceIndex))
	{
		OutError = TEXT("无效的音源索引");
		return false;
	}
	StopSoundSource(SourceIndex);
	const FOKVngeSoundSource& Src = Game->Document->Vnge.Sounds[SourceIndex];

	TArray<FString> Candidates;
	if (!Src.ExtractedPath.IsEmpty()) Candidates.Add(Src.ExtractedPath);
	if (!Src.Path.IsEmpty())
	{
		Candidates.Add(Src.Path);
		if (!Game->File.IsEmpty()) Candidates.Add(FPaths::GetPath(Game->File) / FPaths::GetCleanFilename(Src.Path));
		Candidates.Add(FPaths::ProjectDir() / Src.Path);
		Candidates.Add(FString(TEXT("E:/Koikatu")) / Src.Path);
		Candidates.Add(FString(TEXT("E:/Koikatu/UserData")) / Src.Path);
	}
	FString Resolved;
	for (const FString& C : Candidates)
	{
		if (!C.IsEmpty() && FPaths::FileExists(C)) { Resolved = C; break; }
	}
	if (Resolved.IsEmpty())
	{
		OutError = TEXT("找不到音频文件: ") + (Src.ExtractedPath.IsEmpty() ? Src.Path : Src.ExtractedPath);
		return false;
	}

	// Character LipSync direct path when bound to a character and non-looping
	if (Src.bLipSync && !Src.bLoop && Src.BindObjectId >= 0 && Game->SceneActor)
	{
		if (AKKPreviewActor* Preview = Game->SceneActor->PreviewOf(Src.BindObjectId))
		{
			Preview->bSpeechDrivesMouth = true;
			if (Preview->PlaySpeechFile(Resolved, Src.Pitch, OutError))
			{
				if (Preview->SpeechAudio)
				{
					Preview->SpeechAudio->SetVolumeMultiplier(Game->bMuteSound ? 0.f : FMath::Clamp(Src.Volume * Game->SoundVolume, 0.f, 2.f));
					FActiveSound AS;
					AS.AudioComp = Preview->SpeechAudio;
					AS.LipSyncObjectId = Src.BindObjectId;
					AS.StartRealTime = FPlatformTime::Seconds();
					AS.bLoop = false;
					ActiveSounds.Add(SourceIndex, MoveTemp(AS));
				}
				return true;
			}
		}
	}

	TSharedPtr<const FKKSpeechPcm, ESPMode::ThreadSafe> Pcm;
	if (!LoadWavOrOggFile(Resolved, Pcm, OutError) || !Pcm.IsValid() || Pcm->Samples.IsEmpty()) return false;
	UWorld* World = Game->GetTickableGameObjectWorld();
	if (!World) { OutError = TEXT("场景世界未就绪"); return false; }

	UKKSpeechWave* Wave = NewObject<UKKSpeechWave>(Game);
	Wave->Init(Pcm, World->GetAudioDevice().IsValid() ? World->GetAudioDevice()->GetSampleRate() : Pcm->SampleRate);
	Wave->VirtualizationMode = EVirtualizationMode::PlayWhenSilent;

	const float Vol = Game->bMuteSound ? 0.f : FMath::Clamp(Src.Volume * Game->SoundVolume, 0.f, 2.f);
	const float Pitch = FMath::Clamp(Src.Pitch, 0.1f, 4.f);
	UAudioComponent* Comp = nullptr;
	if (Src.bIs3D && Src.BindObjectId >= 0 && Game->Document->Find(Src.BindObjectId))
	{
		const FVector Pos = Game->Document->WorldTransform(Src.BindObjectId).GetLocation() + FVector(0.f, 0.f, 140.f);
		Comp = UGameplayStatics::SpawnSoundAtLocation(World, Wave, Pos, FRotator::ZeroRotator, Vol, Pitch, 0.f, nullptr, nullptr, false);
	}
	else
	{
		Comp = UGameplayStatics::CreateSound2D(World, Wave, Vol, Pitch, 0.f, nullptr, false, false);
	}
	if (!Comp) { OutError = TEXT("无法创建音频播放组件"); return false; }
	Comp->bAlwaysPlay = true;
	Comp->Play(0.f);

	FActiveSound AS;
	AS.AudioComp = Comp;
	AS.SoundWave = TStrongObjectPtr<UObject>(Wave);
	AS.LipSyncObjectId = Src.bLipSync ? Src.BindObjectId : -1;
	AS.StartRealTime = FPlatformTime::Seconds();
	AS.DurationSec = float(Pcm->Samples.Num() / FMath::Max(1, Pcm->Channels)) / float(FMath::Max(1, Pcm->SampleRate));
	AS.bLoop = Src.bLoop;
	ActiveSounds.Add(SourceIndex, MoveTemp(AS));
	return true;
}

void FOKStudioVngeRuntime::StopSoundSource(int32 SourceIndex)
{
	if (FActiveSound* AS = ActiveSounds.Find(SourceIndex))
	{
		AS->bLoop = false;
		if (UAudioComponent* Comp = AS->AudioComp.Get()) Comp->Stop();
		if (AS->LipSyncObjectId >= 0 && Game && Game->SceneActor)
		{
			if (AKKPreviewActor* Preview = Game->SceneActor->PreviewOf(AS->LipSyncObjectId)) Preview->StopSpeech();
		}
		ActiveSounds.Remove(SourceIndex);
	}
}

void FOKStudioVngeRuntime::StopAllSounds()
{
	TArray<int32> Keys;
	ActiveSounds.GetKeys(Keys);
	for (int32 K : Keys) StopSoundSource(K);
	ActiveSounds.Reset();
}

bool FOKStudioVngeRuntime::IsSoundPlaying(int32 SourceIndex) const
{
	const FActiveSound* AS = ActiveSounds.Find(SourceIndex);
	return AS && AS->AudioComp.IsValid() && AS->AudioComp->IsPlaying();
}

int32 FOKStudioVngeRuntime::AddSoundSource(const FString& FilePath, int32 BindCharaId)
{
	if (!Game || !Game->Document) return -1;
	FOKVngeSoundSource Src;
	Src.Id = FPaths::GetBaseFilename(FilePath);
	Src.Path = FilePath;
	Src.BindObjectId = BindCharaId;
	Src.bIs3D = BindCharaId >= 0;
	Src.bLipSync = BindCharaId >= 0;
	const int32 Idx = Game->Document->Vnge.Sounds.Add(MoveTemp(Src));
	Game->Document->NotifyChanged();
	return Idx;
}

bool FOKStudioVngeRuntime::RemoveSoundSource(int32 SourceIndex)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Sounds.IsValidIndex(SourceIndex)) return false;
	StopSoundSource(SourceIndex);
	Game->Document->Vnge.Sounds.RemoveAt(SourceIndex);
	Game->Document->NotifyChanged();
	return true;
}

bool FOKStudioVngeRuntime::TriggerPhysicsRuleNow(int32 RuleIndex)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Physics.Rules.IsValidIndex(RuleIndex)) return false;
	const FOKVngePhysicsRule& Rule = Game->Document->Vnge.Physics.Rules[RuleIndex];
	UOKSceneDocument& Doc = *Game->Document;
	if (Rule.ActionKind.Equals(TEXT("play_clip"), ESearchCase::IgnoreCase))
	{
		int32 ClipIdx = Rule.ActionParam.IsNumeric() ? FCString::Atoi(*Rule.ActionParam) : INDEX_NONE;
		if (!Doc.Vnge.Clips.IsValidIndex(ClipIdx))
			ClipIdx = Doc.Vnge.Clips.IndexOfByPredicate([&](const FOKVngeClip& C) { return C.Name.Equals(Rule.ActionParam, ESearchCase::IgnoreCase); });
		if (ClipIdx == INDEX_NONE && !Doc.Vnge.Clips.IsEmpty()) ClipIdx = 0;
		return PlayClip(ClipIdx, true);
	}
	if (Rule.ActionKind.Equals(TEXT("apply_state"), ESearchCase::IgnoreCase))
	{
		int32 StIdx = Rule.ActionParam.IsNumeric() ? FCString::Atoi(*Rule.ActionParam) : INDEX_NONE;
		if (!Doc.Vnge.Sss.States.IsValidIndex(StIdx))
			StIdx = Doc.Vnge.Sss.States.IndexOfByPredicate([&](const FOKVngeSceneState& S) { return S.Id.Equals(Rule.ActionParam, ESearchCase::IgnoreCase); });
		return ApplySssState(StIdx, true);
	}
	if (Rule.ActionKind.Equals(TEXT("play_sound"), ESearchCase::IgnoreCase))
	{
		int32 SndIdx = Rule.ActionParam.IsNumeric() ? FCString::Atoi(*Rule.ActionParam) : INDEX_NONE;
		if (!Doc.Vnge.Sounds.IsValidIndex(SndIdx))
			SndIdx = Doc.Vnge.Sounds.IndexOfByPredicate([&](const FOKVngeSoundSource& S) { return S.Id.Equals(Rule.ActionParam, ESearchCase::IgnoreCase); });
		if (SndIdx == INDEX_NONE && !Doc.Vnge.Sounds.IsEmpty()) SndIdx = 0;
		FString Err;
		return PlaySoundSource(SndIdx, Err);
	}
	if (Rule.ActionKind.Equals(TEXT("toggle_visible"), ESearchCase::IgnoreCase))
	{
		const int32 TargetId = Rule.ActionParam.IsNumeric() ? FCString::Atoi(*Rule.ActionParam) : Rule.TargetObjectId;
		if (FOKSceneObject* Obj = Doc.Find(TargetId))
		{
			Obj->bVisible = !Obj->bVisible;
			Doc.NotifyChanged();
			return true;
		}
	}
	return false;
}

int32 FOKStudioVngeRuntime::AddPhysicsRule(int32 SourceId, int32 TargetId, float DistanceM, const FString& ActionKind, const FString& ActionParam)
{
	if (!Game || !Game->Document) return -1;
	FOKVngePhysicsRule Rule;
	Rule.Name = FString::Printf(TEXT("碰撞触发 %d"), Game->Document->Vnge.Physics.Rules.Num() + 1);
	Rule.SourceObjectId = SourceId;
	Rule.TargetObjectId = TargetId;
	Rule.TriggerDistance = FMath::Max(0.02f, DistanceM);
	Rule.ActionKind = ActionKind.IsEmpty() ? TEXT("play_clip") : ActionKind;
	Rule.ActionParam = ActionParam;
	const int32 Idx = Game->Document->Vnge.Physics.Rules.Add(MoveTemp(Rule));
	Game->Document->NotifyChanged();
	return Idx;
}

bool FOKStudioVngeRuntime::RemovePhysicsRule(int32 RuleIndex)
{
	if (!Game || !Game->Document || !Game->Document->Vnge.Physics.Rules.IsValidIndex(RuleIndex)) return false;
	InsideTriggerRules.Remove(RuleIndex);
	Game->Document->Vnge.Physics.Rules.RemoveAt(RuleIndex);
	Game->Document->NotifyChanged();
	return true;
}

int32 FOKStudioVngeRuntime::StepMoveSelected(const FVector& DeltaCm, bool bLocalSpace)
{
	if (!Game || !Game->Document) return 0;
	const TArray<int32> Roots = Game->SelectionRoots();
	int32 Count = 0;
	for (int32 Id : Roots)
	{
		if (FOKSceneObject* O = Game->Document->Find(Id))
		{
			const FVector Step = bLocalSpace ? O->Transform.GetRotation().RotateVector(DeltaCm) : DeltaCm;
			O->Transform.AddToTranslation(Step);
			++Count;
		}
	}
	if (Count > 0) Game->Document->NotifyChanged();
	return Count;
}

int32 FOKStudioVngeRuntime::StepRotateSelected(const FRotator& DeltaDeg, bool bLocalSpace)
{
	if (!Game || !Game->Document) return 0;
	const TArray<int32> Roots = Game->SelectionRoots();
	const FQuat DQ = DeltaDeg.Quaternion();
	int32 Count = 0;
	for (int32 Id : Roots)
	{
		if (FOKSceneObject* O = Game->Document->Find(Id))
		{
			O->Transform.SetRotation((bLocalSpace ? (O->Transform.GetRotation() * DQ) : (DQ * O->Transform.GetRotation())).GetNormalized());
			++Count;
		}
	}
	if (Count > 0) Game->Document->NotifyChanged();
	return Count;
}

int32 FOKStudioVngeRuntime::StepScaleSelected(const FVector& ScaleMultiplier)
{
	if (!Game || !Game->Document) return 0;
	const TArray<int32> Roots = Game->SelectionRoots();
	int32 Count = 0;
	for (int32 Id : Roots)
	{
		if (FOKSceneObject* O = Game->Document->Find(Id))
		{
			O->Transform.SetScale3D((O->Transform.GetScale3D() * ScaleMultiplier).ComponentMax(FVector(0.01f)));
			++Count;
		}
	}
	if (Count > 0) Game->Document->NotifyChanged();
	return Count;
}

int32 FOKStudioVngeRuntime::BatchReplaceCharacterCards(const FString& NewCardPath, bool bSelectedOnly, bool bKeepOutfitAndClothes)
{
	if (!Game || !Game->Document || NewCardPath.IsEmpty() || !FPaths::FileExists(NewCardPath)) return 0;
	int32 Replaced = 0;
	for (FOKSceneObject& O : Game->Document->Objects)
	{
		if (O.Kind != EOKSceneObjectKind::Character) continue;
		if (bSelectedOnly && !Game->IsSelected(O.Id)) continue;
		const int32 KeptOutfit = O.Character.Outfit;
		const TArray<uint8> KeptClothes = O.Character.ClothesStates;
		const TArray<uint8> KeptAcc = O.Character.AccessoriesShown;
		O.Character.Card = NewCardPath;
		if (bKeepOutfitAndClothes)
		{
			O.Character.Outfit = KeptOutfit;
			O.Character.ClothesStates = KeptClothes;
			O.Character.AccessoriesShown = KeptAcc;
		}
		++Replaced;
	}
	if (Replaced > 0) Game->Document->NotifyChanged();
	return Replaced;
}

int32 FOKStudioVngeRuntime::SetAllCharactersBlink(int32 BlinkMode)
{
	if (!Game || !Game->Document) return 0;
	int32 Changed = 0;
	for (FOKSceneObject& O : Game->Document->Objects)
	{
		if (O.Kind != EOKSceneObjectKind::Character) continue;
		// 0 = normal auto blink (-1), 1 = keep open (1.0), 2 = closed (0.0)
		O.Character.EyesOpen = BlinkMode == 0 ? -1.f : (BlinkMode == 1 ? 1.f : 0.f);
		++Changed;
	}
	if (Changed > 0) Game->Document->NotifyChanged();
	return Changed;
}

int32 FOKStudioVngeRuntime::SyncHCharacters(int32 ReferenceCharaId, bool bSyncTransform, bool bSyncMotionAndTime)
{
	if (!Game || !Game->Document) return 0;
	const int32 RefId = ReferenceCharaId >= 0 ? ReferenceCharaId : Game->SelectedId;
	const FOKSceneObject* Ref = Game->Document->Find(RefId);
	if (!Ref || Ref->Kind != EOKSceneObjectKind::Character) return 0;
	const FTransform RefWorld = Game->Document->WorldTransform(RefId);
	int32 Synced = 0;
	for (FOKSceneObject& O : Game->Document->Objects)
	{
		if (O.Id == RefId || O.Kind != EOKSceneObjectKind::Character) continue;
		if (Game->Selection.Num() > 1 && !Game->IsSelected(O.Id)) continue;
		if (bSyncTransform)
		{
			O.Transform = O.Parent >= 0 ? (RefWorld * Game->Document->WorldTransform(O.Parent).Inverse()) : RefWorld;
		}
		if (bSyncMotionAndTime)
		{
			O.Character.Speed = Ref->Character.Speed;
			O.Character.Time = Ref->Character.Time;
			O.Character.AnimFloats = Ref->Character.AnimFloats;
			if (Game->SceneActor) Game->SceneActor->SetAnimationTime(O.Id, Ref->Character.Time);
		}
		++Synced;
	}
	if (Synced > 0) Game->Document->NotifyChanged();
	return Synced;
}

int32 FOKStudioVngeRuntime::BatchItemFk(bool bSelectedOnly, bool bResetToZero)
{
	if (!Game || !Game->Document) return 0;
	const FString Lib = AOKSceneActor::LibraryDirectory();
	const FTCHARToUTF8 LibUtf8(*Lib);
	int32 Updated = 0;
	for (FOKSceneObject& O : Game->Document->Objects)
	{
		if (O.Kind != EOKSceneObjectKind::Item) continue;
		if (bSelectedOnly && !Game->IsSelected(O.Id)) continue;
		if (bResetToZero)
		{
			if (!O.Item.Fk.IsEmpty()) { O.Item.Fk.Reset(); ++Updated; }
			continue;
		}
		const FOKStudioCatalogItem* Entry = FOKStudioCatalog::Get().FindItem(O.Item.Group, O.Item.Category, O.Item.No);
		if (!Entry || Entry->Model.IsEmpty()) continue;
		const FTCHARToUTF8 IdUtf8(*Entry->Model);
		const FTCHARToUTF8 PrefabUtf8(*Entry->Prefab);
		const int32 Len = ok_okmodel_fk_bones(LibUtf8.Get(), IdUtf8.Get(), PrefabUtf8.Get(), nullptr, 0);
		if (Len <= 2) continue;
		TArray<uint8> Buf;
		Buf.SetNumZeroed(Len + 1);
		if (ok_okmodel_fk_bones(LibUtf8.Get(), IdUtf8.Get(), PrefabUtf8.Get(), Buf.GetData(), Len) <= 0) continue;
		TArray<TSharedPtr<FJsonValue>> BoneNames;
		if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(UTF8_TO_TCHAR(reinterpret_cast<const char*>(Buf.GetData()))), BoneNames)) continue;
		for (const TSharedPtr<FJsonValue>& BV : BoneNames)
		{
			const FString Bone = BV->AsString();
			if (!Bone.IsEmpty() && !O.Item.Fk.ContainsByPredicate([&](const FOKSceneFkBone& X) { return X.Bone == Bone; }))
			{
				O.Item.Fk.Add({ Bone, FVector::ZeroVector });
			}
		}
		++Updated;
	}
	if (Updated > 0) Game->Document->NotifyChanged();
	return Updated;
}

bool FOKStudioVngeRuntime::CopyCharacterStatus(int32 SourceCharaId)
{
	if (!Game || !Game->Document) return false;
	const int32 SrcId = SourceCharaId >= 0 ? SourceCharaId : Game->SelectedId;
	const FOKSceneObject* Obj = Game->Document->Find(SrcId);
	if (!Obj || Obj->Kind != EOKSceneObjectKind::Character) return false;
	TSharedRef<FJsonObject> J = MakeShared<FJsonObject>();
	if (!FJsonObjectConverter::UStructToJsonObject(FOKSceneCharacter::StaticStruct(), &Obj->Character, J)) return false;
	ClipboardCharJson = J;
	ClipboardSourceId = SrcId;
	ClipboardSourceName = Obj->Name;
	ClipboardLocalTransform = Obj->Transform;
	ClipboardWorldTransform = Game->Document->WorldTransform(SrcId);
	bHasClipboardStatus = true;
	return true;
}

int32 FOKStudioVngeRuntime::PasteCharacterStatus(const TArray<int32>& TargetIds, const FOKVngeCopyMask& Mask)
{
	if (!bHasClipboardStatus || !ClipboardCharJson.IsValid() || !Game || !Game->Document) return 0;
	FOKSceneCharacter Src;
	if (!FJsonObjectConverter::JsonObjectToUStruct(ClipboardCharJson.ToSharedRef(), FOKSceneCharacter::StaticStruct(), &Src)) return 0;

	TArray<int32> Targets = TargetIds;
	if (Targets.IsEmpty()) Targets = Game->Selection;
	int32 Pasted = 0;
	for (int32 Id : Targets)
	{
		FOKSceneObject* Obj = Game->Document->Find(Id);
		if (!Obj || Obj->Kind != EOKSceneObjectKind::Character) continue;
		FOKSceneCharacter& Dst = Obj->Character;
		if (Mask.bFace)
		{
			Dst.EyebrowPattern = Src.EyebrowPattern;
			Dst.EyebrowsOpen = Src.EyebrowsOpen;
			Dst.EyesPattern = Src.EyesPattern;
			Dst.EyesOpen = Src.EyesOpen;
			Dst.MouthPattern = Src.MouthPattern;
			Dst.MouthOpen = Src.MouthOpen;
			Dst.MorphOverrides = Src.MorphOverrides;
		}
		if (Mask.bPose)
		{
			Dst.StudioAnimeKind = Src.StudioAnimeKind;
			Dst.StudioAnimeGroup = Src.StudioAnimeGroup;
			Dst.StudioAnimeCategory = Src.StudioAnimeCategory;
			Dst.StudioAnimeNo = Src.StudioAnimeNo;
			Dst.AnimFile = Src.AnimFile;
			Dst.Speed = Src.Speed;
			Dst.Time = Src.Time;
			Dst.bForceLoop = Src.bForceLoop;
			Dst.AnimFloats = Src.AnimFloats;
			Dst.Fk = Src.Fk;
			Dst.Ik = Src.Ik;
			Dst.BoneOverrides = Src.BoneOverrides;
		}
		if (Mask.bHands)
		{
			Dst.HandLeft = Src.HandLeft;
			Dst.HandRight = Src.HandRight;
		}
		if (Mask.bLook)
		{
			Dst.EyesLook = Src.EyesLook;
			Dst.NeckLook = Src.NeckLook;
			Dst.LookPoint = Src.LookPoint;
			Dst.NeckFollow = Src.NeckFollow;
			Dst.Blink = Src.Blink;
			Dst.FixedNeck = Src.FixedNeck;
			Dst.FixedEyes = Src.FixedEyes;
			Dst.FixedEyesPattern = Src.FixedEyesPattern;
		}
		if (Mask.bClothes)
		{
			Dst.Outfit = Src.Outfit;
			Dst.ClothesStates = Src.ClothesStates;
			if (!Mask.bKeepAccessories) Dst.AccessoriesShown = Src.AccessoriesShown;
		}
		if (Mask.bState)
		{
			Dst.TearsLevel = Src.TearsLevel;
			Dst.Blush = Src.Blush;
			Dst.NipStand = Src.NipStand;
			Dst.SkinGloss = Src.SkinGloss;
			Dst.Fluids = Src.Fluids;
			Dst.InvisibleBody = Src.InvisibleBody;
		}
		if (Mask.bStyle)
		{
			Dst.Style = Src.Style;
			Dst.FaceStyle = Src.FaceStyle;
		}
		if (Mask.bWorldTransform)
		{
			Obj->Transform = Obj->Parent >= 0 ? (ClipboardWorldTransform * Game->Document->WorldTransform(Obj->Parent).Inverse()) : ClipboardWorldTransform;
		}
		else if (Mask.bLocalTransform)
		{
			Obj->Transform = ClipboardLocalTransform;
		}
		++Pasted;
	}
	if (Pasted > 0) Game->Document->NotifyChanged();
	return Pasted;
}

bool FOKStudioVngeRuntime::StepScriptNext()
{
	if (!Game || !Game->Document) return false;
	const TArray<FOKVngeScriptBlock>& Blocks = Game->Document->Vnge.Script.Blocks;
	if (!Blocks.IsValidIndex(ActiveScriptBlock))
	{
		if (Blocks.IsEmpty())
		{
			// Fallback: if there is no VNSS script, step through SSS states sequentially!
			const int32 NumStates = Game->Document->Vnge.Sss.States.Num();
			if (NumStates <= 0) return false;
			const int32 NextSt = (Game->Document->Vnge.Sss.ActiveStateIndex + 1) % NumStates;
			return ApplySssState(NextSt, true);
		}
		ActiveScriptBlock = 0;
		ActiveScriptLine = -1;
	}
	const FOKVngeScriptBlock& Block = Blocks[ActiveScriptBlock];
	while (ActiveScriptLine + 1 < Block.Lines.Num())
	{
		++ActiveScriptLine;
		const FString Line = Block.Lines[ActiveScriptLine].TrimStartAndEnd();
		if (Line.IsEmpty() || Line.StartsWith(TEXT("#")) || Line.StartsWith(TEXT("//"))) continue;
		ExecuteScriptLine(Line);
		return true;
	}
	return false;
}

bool FOKStudioVngeRuntime::JumpScriptBlock(const FString& BlockName)
{
	if (!Game || !Game->Document) return false;
	const TArray<FOKVngeScriptBlock>& Blocks = Game->Document->Vnge.Script.Blocks;
	const int32 Idx = Blocks.IndexOfByPredicate([&](const FOKVngeScriptBlock& B)
	{
		return B.Name.Equals(BlockName, ESearchCase::IgnoreCase) || B.Name.Equals(TEXT(":") + BlockName, ESearchCase::IgnoreCase);
	});
	if (Idx == INDEX_NONE) return false;
	ActiveScriptBlock = Idx;
	ActiveScriptLine = -1;
	ActiveChoices.Reset();
	return StepScriptNext();
}

void FOKStudioVngeRuntime::ResetScript()
{
	ActiveScriptBlock = 0;
	ActiveScriptLine = -1;
	ClearDialogue();
}

void FOKStudioVngeRuntime::ClearDialogue()
{
	ActiveWhoSay.Reset();
	ActiveWhatSay.Reset();
	ActiveChoices.Reset();
}

void FOKStudioVngeRuntime::ExecuteScriptLine(const FString& Line)
{
	if (!Game || !Game->Document) return;
	UOKSceneDocument& Doc = *Game->Document;
	ActiveChoices.Reset();

	// Command forms: `sss 0` / `:sss:0` / `cam 1` / `kfa clip1` / `sound bgm1` / `jump s2`
	FString Cmd = Line;
	if (Cmd.StartsWith(TEXT(":"))) Cmd.RemoveAt(0);
	FString Head, Rest;
	if (Cmd.Split(TEXT(" "), &Head, &Rest) || Cmd.Split(TEXT(":"), &Head, &Rest))
	{
		const FString Low = Head.TrimStartAndEnd().ToLower();
		const FString Arg = Rest.TrimStartAndEnd().TrimQuotes();
		if (Low == TEXT("sss") || Low == TEXT("state"))
		{
			int32 Idx = Arg.IsNumeric() ? FCString::Atoi(*Arg) : Doc.Vnge.Sss.States.IndexOfByPredicate([&](const FOKVngeSceneState& S) { return S.Id.Equals(Arg, ESearchCase::IgnoreCase); });
			if (Idx >= 0) ApplySssState(Idx, true);
			return;
		}
		if (Low == TEXT("cam") || Low == TEXT("camera"))
		{
			if (Arg.IsNumeric()) ApplySssCamera(FCString::Atoi(*Arg));
			return;
		}
		if (Low == TEXT("kfa") || Low == TEXT("clip") || Low == TEXT("anim"))
		{
			int32 Idx = Arg.IsNumeric() ? FCString::Atoi(*Arg) : Doc.Vnge.Clips.IndexOfByPredicate([&](const FOKVngeClip& C) { return C.Name.Equals(Arg, ESearchCase::IgnoreCase); });
			if (Idx >= 0) PlayClip(Idx, true);
			return;
		}
		if (Low == TEXT("sound") || Low == TEXT("se") || Low == TEXT("bgm") || Low == TEXT("voice"))
		{
			int32 Idx = Arg.IsNumeric() ? FCString::Atoi(*Arg) : Doc.Vnge.Sounds.IndexOfByPredicate([&](const FOKVngeSoundSource& S) { return S.Id.Equals(Arg, ESearchCase::IgnoreCase); });
			FString Err;
			if (Idx >= 0) PlaySoundSource(Idx, Err);
			return;
		}
		if (Low == TEXT("jump") || Low == TEXT("goto"))
		{
			JumpScriptBlock(Arg);
			return;
		}
		if (Low == TEXT("choice") || Low == TEXT("menu"))
		{
			TArray<FString> Pairs;
			Arg.ParseIntoArray(Pairs, TEXT("|"), true);
			for (const FString& Pair : Pairs)
			{
				FString Lbl, Tgt;
				if (Pair.Split(TEXT("->"), &Lbl, &Tgt)) ActiveChoices.Emplace(Lbl.TrimStartAndEnd(), Tgt.TrimStartAndEnd());
			}
			return;
		}
		// Speaker: Dialogue
		ActiveWhoSay = Head.TrimStartAndEnd();
		if (const FOKVngeActorTag* Tag = Doc.Vnge.Registry.Actors.FindByPredicate([&](const FOKVngeActorTag& T) { return T.Alias.Equals(ActiveWhoSay, ESearchCase::IgnoreCase); }))
		{
			if (!Tag->Title.IsEmpty()) ActiveWhoSay = Tag->Title;
			else if (const FOKSceneObject* Obj = Doc.Find(Tag->ObjectId)) ActiveWhoSay = Obj->Name;
		}
		ActiveWhatSay = Rest.TrimStartAndEnd();
		return;
	}
	ActiveWhoSay.Reset();
	ActiveWhatSay = Line;
}
