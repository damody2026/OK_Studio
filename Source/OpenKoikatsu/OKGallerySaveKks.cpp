#include "OKCharacterController.h"
#include "OKStudioCharacterStyle.h"
#include "KKCardWriter.h"
#include "KKCardWorkspace.h"
#include "KKRustExtract.h"
#include "Components/EditableTextBox.h"
#include "Components/TextBlock.h"
#include "Dom/JsonObject.h"
#include "Engine/Engine.h"
#include "HAL/FileManager.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

// 存成 KKS 卡: the shown character back as a plain KKS card, the way the game reads it.
namespace
{
	/** The card image without what only OK reads: the APNG frames (acTL/fcTL/fdAT, the game shows the default image) and
	 *  the OK chunks (ok*: snapshots, the card's own resources). */
	TArray<uint8> PlainCardPng(const TArray<uint8>& Png)
	{
		if (Png.Num() < 8) return Png;
		TArray<uint8> Out(Png.GetData(), 8);
		for (int64 Pos = 8; Pos + 12 <= Png.Num();)
		{
			const uint8* At = Png.GetData() + Pos;
			const int64 Size = 12 + ((int64(At[0]) << 24) | (int64(At[1]) << 16) | (int64(At[2]) << 8) | int64(At[3]));
			if (Pos + Size > Png.Num()) return Png;
			const bool bOkOnly = FMemory::Memcmp(At + 4, "acTL", 4) == 0 || FMemory::Memcmp(At + 4, "fcTL", 4) == 0
				|| FMemory::Memcmp(At + 4, "fdAT", 4) == 0 || (At[4] == 'o' && At[5] == 'k');
			if (!bOkOnly) Out.Append(At, int32(Size));
			Pos += Size;
			if (FMemory::Memcmp(At + 4, "IEND", 4) == 0) break;
		}
		return Out;
	}

	TArray<TSharedPtr<FJsonValue>> Numbers(const FVector& V)
	{
		return { MakeShared<FJsonValueNumber>(V.X), MakeShared<FJsonValueNumber>(V.Y), MakeShared<FJsonValueNumber>(V.Z) };
	}

	FVector Vector(const TSharedPtr<FJsonObject>& Data, const TCHAR* Field, float Default)
	{
		const TArray<TSharedPtr<FJsonValue>>* A = nullptr;
		if (!Data->TryGetArrayField(Field, A) || A->Num() != 3) return FVector(Default);
		return FVector((*A)[0]->AsNumber(), (*A)[1]->AsNumber(), (*A)[2]->AsNumber());
	}

	/** The style's bone modifiers on the card's (as the session shows them, `set_style_bones`): scales and lengths
	 *  multiply, offsets and turns add, a bone the card leaves alone is added. */
	void MergeStyleBones(TArray<TSharedPtr<FJsonValue>>& Card, const TArray<TSharedPtr<FJsonValue>>& Style)
	{
		for (const TSharedPtr<FJsonValue>& StyleValue : Style)
		{
			const TSharedPtr<FJsonObject> Bone = StyleValue->AsObject();
			const TArray<TSharedPtr<FJsonValue>>& StyleCoords = Bone->GetArrayField(TEXT("coord"));
			if (StyleCoords.IsEmpty()) continue;
			const TSharedPtr<FJsonObject> S = StyleCoords[0]->AsObject();
			const FVector Scale = Vector(S, TEXT("scale"), 1.f), Pos = Vector(S, TEXT("pos"), 0.f), Rot = Vector(S, TEXT("rot"), 0.f);
			const double Length = S->GetNumberField(TEXT("length"));
			TSharedPtr<FJsonObject> Found;
			for (const TSharedPtr<FJsonValue>& Value : Card)
			{
				const TSharedPtr<FJsonObject> Existing = Value->AsObject();
				if (Existing.IsValid() && Existing->GetStringField(TEXT("name")) == Bone->GetStringField(TEXT("name")) && Existing->GetIntegerField(TEXT("location")) < 10) { Found = Existing; break; }
			}
			if (!Found) { Card.Add(StyleValue); continue; }
			for (const TSharedPtr<FJsonValue>& Value : Found->GetArrayField(TEXT("coord")))
			{
				const TSharedPtr<FJsonObject> D = Value->AsObject();
				D->SetArrayField(TEXT("scale"), Numbers(Vector(D, TEXT("scale"), 1.f) * Scale));
				D->SetArrayField(TEXT("pos"), Numbers(Vector(D, TEXT("pos"), 0.f) + Pos));
				D->SetArrayField(TEXT("rot"), Numbers(Vector(D, TEXT("rot"), 0.f) + Rot));
				D->SetNumberField(TEXT("length"), D->GetNumberField(TEXT("length")) * Length);
			}
		}
	}
}

void UOKCharacterController::OnSaveKks()
{
	if (bAppearanceBusy || bPropertyBusy || bLoadInFlight) return;
	if (MaterializeAppearance([](UOKCharacterController* G) { G->OnSaveKks(); })) return;
	if (bApngCaptureInFlight || bPortableSaveInFlight) return;
	if (Selected.OriginalBytes.Num() == 0 || !Entries.IsValidIndex(SelectedIndex)) return;
	const auto Report = [this](const FString& Text)
	{
		if (InspectorText) InspectorText->SetText(FText::FromString(Text));
		if (GEngine) GEngine->AddOnScreenDebugMessage(1, 10.f, FColor::Green, Text);
	};
	if (NicknameBox) Selected.Nickname = NicknameBox->GetText().ToString();
	const FString Directory = OutputDirectoryInput ? OutputDirectoryInput->GetText().ToString().TrimStartAndEnd() : FString();
	if (Directory.IsEmpty()) { Report(TEXT("請先在卡片列表填寫另存資料夾。")); return; }

	FKKCharacterFile Card = Selected;
	FString Note;
	// The style is the shown character's only (the card keeps its values): here it goes into the card. The sliders take the
	// styled values; what sliders do not reach (widths, head, fingers, the whole size and the lift that keeps her feet on
	// the ground) goes into the ABMX bone modifiers, on top of the card's own.
	if (CharacterStyle != 0.f || CharacterFaceStyle != 0.f)
	{
		TArray<float> Body = Card.Body.ShapeValueBody, Face = Card.Face.ShapeValueFace;
		OKStudioStyleSliders(CharacterStyle, CharacterFaceStyle, Body, Face);
		const float Scale = OKStudioStyleScale(CharacterStyle, Card.Body.ShapeValueBody, Body);
		const float Height = Card.Body.ShapeValueBody.IsValidIndex(0) ? Card.Body.ShapeValueBody[0] : 0.5f;
		const float Lift = OKStudioStyleLift(CharacterStyle, Scale, Height);
		Card.Body.ShapeValueBody = MoveTemp(Body);
		Card.Face.ShapeValueFace = MoveTemp(Face);
		if (CharacterStyle != 0.f)
		{
			TSharedPtr<FJsonObject> Mods;
			TArray<TSharedPtr<FJsonValue>> Style;
			if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(EditorModsJson()), Mods) || !Mods.IsValid()
				|| !FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(OKStudioStyleBones(CharacterStyle, Scale)), Style))
			{ Report(TEXT("讀不出卡片的骨骼資料，未存檔。")); return; }
			// The whole character's size: the reader scales the actor, the card scales its height bone (feet at the root),
			// and lifts it (Unity metres) by what the longer legs sink.
			auto HeightBone = MakeShared<FJsonObject>();
			HeightBone->SetStringField(TEXT("name"), TEXT("cf_n_height"));
			HeightBone->SetNumberField(TEXT("location"), 0);
			auto Data = MakeShared<FJsonObject>();
			Data->SetArrayField(TEXT("scale"), Numbers(FVector(Scale)));
			Data->SetNumberField(TEXT("length"), 1.);
			Data->SetArrayField(TEXT("pos"), Numbers(FVector(0., Lift / 100.f, 0.)));
			Data->SetArrayField(TEXT("rot"), Numbers(FVector::ZeroVector));
			HeightBone->SetArrayField(TEXT("coord"), { MakeShared<FJsonValueObject>(Data) });
			Style.Add(MakeShared<FJsonValueObject>(HeightBone));
			TArray<TSharedPtr<FJsonValue>> Bones = Mods->GetArrayField(TEXT("abm"));
			MergeStyleBones(Bones, Style);
			Mods->SetArrayField(TEXT("abm"), Bones);
			FString Json;
			FJsonSerializer::Serialize(Mods.ToSharedRef(), TJsonWriterFactory<>::Create(&Json));
			TArray<uint8> Extended;
			if (!FOkSession::EncodeEditorMods(Card.RawBlocks.FindRef(TEXT("KKEx")), Json, Extended))
			{ Report(TEXT("卡片的模組資料版本或格式不支援，未存檔。")); return; }
			Card.RawBlocks.Add(TEXT("KKEx"), MoveTemp(Extended));
			if (!Card.Blocks.ContainsByPredicate([](const FKKBlockInfo& B) { return B.Name == TEXT("KKEx"); })) { FKKBlockInfo B; B.Name = TEXT("KKEx"); Card.Blocks.Add(B); }
			Note = FString::Printf(TEXT("\n角色風格 %.2f（臉 %.2f）已寫進滑桿與 ABMX 骨骼，整體大小 ×%.2f；KKS 要裝 ABMX 才看得到骨骼部分。"), CharacterStyle, CharacterFaceStyle, Scale);
		}
		else Note = FString::Printf(TEXT("\n臉風格 %.2f 已寫進臉部滑桿。"), CharacterFaceStyle);
	}
	Card.Header.PreviewPng = PlainCardPng(Card.Header.PreviewPng);
	Card.Header.PngEndOffset = Card.Header.PreviewPng.Num();

	const FString Source = Entries[SelectedIndex].Path;
	FString OutPath = UKKCardWorkspace::NewCardPath(FPaths::ConvertRelativePathToFull(Directory), Source);
	OutPath = FPaths::GetPath(OutPath) / FPaths::GetBaseFilename(OutPath).Replace(TEXT("_edited"), TEXT("_kks")) + TEXT(".png");
	for (int32 Suffix = 2; IFileManager::Get().FileExists(*OutPath); ++Suffix)
		OutPath = FPaths::GetPath(OutPath) / FString::Printf(TEXT("%s_kks_%d.png"), *FPaths::GetBaseFilename(Source), Suffix);
	IFileManager::Get().MakeDirectory(*FPaths::GetPath(OutPath), true);
	FString Error;
	if (!UKKCardWriter::SaveWithEdits(Card, OutPath, Error)) { Report(TEXT("存成 KKS 卡失敗：") + Error); return; }
	UE_LOG(LogTemp, Display, TEXT("KKS card saved: %s style=%.2f face_style=%.2f"), *OutPath, CharacterStyle, CharacterFaceStyle);
	Report(FString::Printf(TEXT("已存成 KKS 卡：%s\n身材、臉部與骨骼調整已寫入。"), *OutPath) + Note);
}
