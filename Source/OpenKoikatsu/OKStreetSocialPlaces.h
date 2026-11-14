#pragma once
#include "OKStreetSocialRules.h"
#include "OKStreetSocialProperty.h"
#include "Algo/Reverse.h"
#include "Dom/JsonObject.h"
#include "Engine/World.h"
#include "HAL/PlatformMisc.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/WeakObjectPtrTemplates.h"

// Street places the player and a girl can go to together, and the built-in activities free talk can start.
//
// Places are modelled at runtime from the cooked StreetCube/StreetCylinder meshes and the 12 StreetMaterial
// colours (no re-cook). Solid parts get collision, so the player sweep, the companion follow and route
// planning avoid them; NPC route walking never goes near them. School, library and playground stand on an
// extension east of the cooked ground (x 3200..6400) that is spawned with them.
//
// Units are cm; +X is north (up on the minimap), +Y is east.

struct FOKStreetPlacePart {
 EOKStreetMesh Mesh = EOKStreetMesh::Cube;
 EOKStreetMaterial Material = EOKStreetMaterial::Cream;
 FVector Center = FVector::ZeroVector;
 FVector Size = FVector(100);
 bool Solid = false;
 bool Hidden = false; // collision only (the place has a model)
};

// A place model built by Tools/street_models/build_street_models.py (Blender) as .okmesh: coloured
// sections in local cm with the front toward +X, collision boxes and the door spot.
struct FOKStreetModelSection {
 FLinearColor Color = FLinearColor::White; // sRGB from the file, converted
 uint8 StreetMaterial = 3;
 bool UseStreetMaterial = false;
 bool Roof = false; // hidden while the player is inside
 uint8 Level = 0; // floor of a multi-storey building (1 = ground); 0 = always shown
 TArray<FVector> Positions, Normals;
 TArray<FVector2D> UV;
 TArray<int32> Indices;
};
struct FOKStreetModelAnchor {
 FString Name;
 FVector Position = FVector::ZeroVector;
 float Yaw = 0.f;
};
struct FOKStreetPlaceModel {
 TArray<FOKStreetModelSection> Sections;
 TArray<FBox> Boxes;
 FVector Door = FVector::ZeroVector;
 TArray<FBox> Rooms; // walkable interiors (v2)
 TArray<FOKStreetModelAnchor> Anchors; // activity spots (v2)
};

inline FString OKStreetPlaceModelDir() {
 const FString Content = FPaths::ProjectContentDir() / TEXT("IndependentResources/StreetSocialData/Models");
 if (FPaths::DirectoryExists(Content)) return Content;
 const FString Builtin = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_BUILTIN_RESOURCES"));
 if (!Builtin.IsEmpty() && FPaths::DirectoryExists(FPaths::GetPath(Builtin) / TEXT("StreetSocialData/Models"))) return FPaths::GetPath(Builtin) / TEXT("StreetSocialData/Models");
 return FPaths::ProjectDir() / TEXT("Content/IndependentResources/StreetSocialData/Models");
}

inline TSharedPtr<const FOKStreetPlaceModel> OKStreetLoadPlaceModel(const FString& Path, FString& Error) {
 TArray<uint8> Bytes;
 if (!FFileHelper::LoadFileToArray(Bytes, *Path)) { Error = TEXT("missing ") + Path; return nullptr; }
 int64 At = 0;
 auto Need = [&](int64 N) { return At + N <= Bytes.Num(); };
 auto U32 = [&]() { uint32 V = 0; if (Need(4)) FMemory::Memcpy(&V, Bytes.GetData() + At, 4); At += 4; return V; };
 auto F32 = [&]() { float V = 0; if (Need(4)) FMemory::Memcpy(&V, Bytes.GetData() + At, 4); At += 4; return V; };
 if (Bytes.Num() < 12 || FMemory::Memcmp(Bytes.GetData(), "OKPM", 4)) { Error = TEXT("not an okmesh: ") + Path; return nullptr; }
 At = 4;
 const uint32 Version = U32();
 if (Version != 1 && Version != 2) { Error = TEXT("unsupported okmesh version: ") + Path; return nullptr; }
 auto Model = MakeShared<FOKStreetPlaceModel>();
 const uint32 Count = U32();
 if (Count > 256) { Error = TEXT("too many sections: ") + Path; return nullptr; }
 for (uint32 S = 0; S < Count; ++S) {
  FOKStreetModelSection& Sec = Model->Sections.AddDefaulted_GetRef();
  const float R = F32(), G = F32(), B = F32();
  Sec.Color = FLinearColor::FromSRGBColor(FColor(uint8(FMath::Clamp(R, 0.f, 1.f) * 255), uint8(FMath::Clamp(G, 0.f, 1.f) * 255), uint8(FMath::Clamp(B, 0.f, 1.f) * 255)));
  Sec.StreetMaterial = uint8(FMath::Min<uint32>(U32(), 11));
  const uint32 Flags = U32();
  Sec.UseStreetMaterial = (Flags & 1) != 0;
  Sec.Roof = (Flags & 2) != 0;
  Sec.Level = uint8((Flags >> 8) & 0xFF);
  const uint32 Vertices = U32(), Indices = U32();
  if (Vertices > 4000000 || Indices > 12000000 || !Need(int64(Vertices) * 32 + int64(Indices) * 4)) { Error = TEXT("truncated okmesh: ") + Path; return nullptr; }
  Sec.Positions.SetNumUninitialized(Vertices);Sec.Normals.SetNumUninitialized(Vertices);Sec.UV.SetNumUninitialized(Vertices);Sec.Indices.SetNumUninitialized(Indices);
  for (uint32 V = 0; V < Vertices; ++V) { const float X = F32(), Y = F32(), Z = F32(); Sec.Positions[V] = FVector(X, Y, Z); }
  for (uint32 V = 0; V < Vertices; ++V) { const float X = F32(), Y = F32(), Z = F32(); Sec.Normals[V] = FVector(X, Y, Z); }
  for (uint32 V = 0; V < Vertices; ++V) { const float X = F32(), Y = F32(); Sec.UV[V] = FVector2D(X, Y); }
  for (uint32 I = 0; I < Indices; ++I) { const uint32 Index = U32(); if (Index >= Vertices) { Error = TEXT("bad okmesh index: ") + Path; return nullptr; } Sec.Indices[I] = int32(Index); }
 }
 const uint32 Boxes = U32();
 if (Boxes > 1024 || !Need(int64(Boxes) * 24 + 12)) { Error = TEXT("truncated okmesh boxes: ") + Path; return nullptr; }
 for (uint32 Box = 0; Box < Boxes; ++Box) {
  // One read per statement: the order of arguments in a call is unspecified (MSVC reads right to left).
  const float CX = F32(), CY = F32(), CZ = F32(), SX = F32(), SY = F32(), SZ = F32();
  const FVector C(CX, CY, CZ), S(SX, SY, SZ);
  Model->Boxes.Add(FBox(C - S * .5f, C + S * .5f));
 }
 const float DX = F32(), DY = F32(), DZ = F32();
 Model->Door = FVector(DX, DY, DZ);
 if (Version >= 2) {
  const uint32 Rooms = U32();
  if (Rooms > 64 || !Need(int64(Rooms) * 24 + 4)) { Error = TEXT("truncated okmesh rooms: ") + Path; return nullptr; }
  for (uint32 R = 0; R < Rooms; ++R) {
   const float CX = F32(), CY = F32(), CZ = F32(), SX = F32(), SY = F32(), SZ = F32();
   const FVector C(CX, CY, CZ), S(SX, SY, SZ);
   Model->Rooms.Add(FBox(C - S * .5f, C + S * .5f));
  }
  const uint32 Anchors = U32();
  if (Anchors > 64) { Error = TEXT("too many okmesh anchors: ") + Path; return nullptr; }
  for (uint32 A = 0; A < Anchors; ++A) {
   const uint32 Length = U32();
   if (Length > 64 || !Need(int64(Length) + 16)) { Error = TEXT("truncated okmesh anchor: ") + Path; return nullptr; }
   const FUTF8ToTCHAR Name(reinterpret_cast<const ANSICHAR*>(Bytes.GetData() + At), Length);
   FOKStreetModelAnchor& Anchor = Model->Anchors.AddDefaulted_GetRef();
   Anchor.Name = FString(Name.Length(), Name.Get());
   At += Length;
   const float AX = F32(), AY = F32(), AZ = F32(), Yaw = F32();
   Anchor.Position = FVector(AX, AY, AZ);Anchor.Yaw = Yaw;
  }
 }
 return Model;
}

// Fill light for the place models: a share of the sun intensity, with a floor so they stay readable at night.
inline constexpr float OKStreetPlaceFillShare = .45f, OKStreetPlaceFillNight = .3f;
// Soine (sleeping side by side) root offset in the bed's frame, and how far her onsen sitting pose is lifted
// so she sits on the pool's step instead of its floor (dev overrides: -StreetSocialSoineShiftX/Y=, -StreetSocialOnsenLift=).
inline constexpr float OKStreetSoineShiftX = 0.f, OKStreetSoineShiftY = -50.f, OKStreetOnsenLift = 30.f;

struct FOKStreetPlace {
 const TCHAR* Id = TEXT("");
 const TCHAR* Name = TEXT("");
 const TCHAR* About = TEXT(""); // what the place is, for the model
 const TCHAR* ZhName = nullptr; const TCHAR* ZhAbout = nullptr; // the data's own (Traditional Chinese), kept when the language swaps Name/About
 FVector Door = FVector::ZeroVector; // street-side spot where the pair arrives and activities happen
 TArray<FOKStreetPlacePart> Parts;
 // With a model: where it stands and its yaw (the model's front +X turns to face the street).
 FVector Origin = FVector::ZeroVector;
 float Yaw = 0.f;
 TSharedPtr<const FOKStreetPlaceModel> Model;
 TArray<FBox> Rooms; // world, from the model
 TArray<int32> RoomLevels; // floor of each room (1 = ground), from the rooms' heights
 TArray<FOKStreetModelAnchor> Anchors; // world positions and yaw
 bool Outdoor = false; // the city's data: open ground (a park, a beach) rather than a building entered by its door
};

// The floor (1-based) of the place's room the point stands in, or 0 when outside. 3D: an upper floor's room
// only counts at its height.
inline int32 OKStreetPlaceFloor(const FOKStreetPlace& Place, const FVector& Point) {
 for (int32 I = 0; I < Place.Rooms.Num(); ++I) {
  const FBox& Room = Place.Rooms[I];
  if (Point.X >= Room.Min.X && Point.X <= Room.Max.X && Point.Y >= Room.Min.Y && Point.Y <= Room.Max.Y && Point.Z >= Room.Min.Z - 60.f && Point.Z < Room.Max.Z - 60.f)
   return Place.RoomLevels.IsValidIndex(I) ? Place.RoomLevels[I] : 1;
 }
 return 0;
}

// The nearest bed (anchors named "bed...") within Range of a point, skipping one; with its place.
inline const FOKStreetModelAnchor* OKStreetNearestBed(const FVector& At, float Range, const FOKStreetModelAnchor* Except, const FOKStreetPlace** Where = nullptr);

// Elevator stops of a multi-storey place: anchors named "liftK:label", ordered by floor.
inline TArray<const FOKStreetModelAnchor*> OKStreetPlaceLifts(const FOKStreetPlace& Place) {
 TArray<const FOKStreetModelAnchor*> Out;
 for (const auto& A : Place.Anchors) if (A.Name.StartsWith(TEXT("lift"))) Out.Add(&A);
 Out.Sort([](const FOKStreetModelAnchor& A, const FOKStreetModelAnchor& B) { return A.Position.Z < B.Position.Z; });
 return Out;
}
// A stop's label in the game's language (the models keep the data's own Chinese; filled when the language changes).
inline TMap<FString, FString>& OKStreetLiftLabelTexts() { static TMap<FString, FString> Texts; return Texts; }
inline FString OKStreetLiftLabel(const FOKStreetModelAnchor& Lift) {
 FString Left, Right;
 const FString Own = Lift.Name.Split(TEXT(":"), &Left, &Right) ? Right : Lift.Name;
 const FString* Text = OKStreetLiftLabelTexts().Find(Own);
 return Text ? *Text : Own;
}

inline const FOKStreetModelAnchor* OKStreetPlaceAnchor(const FOKStreetPlace& Place, const TCHAR* Name) {
 if (!Name || !*Name) return nullptr;
 // "pond|fountain": the first the model has (an activity names the spot a new scene will add, and an older one till then).
 TArray<FString> Names; FString(Name).ParseIntoArray(Names, TEXT("|"));
 for (const FString& N : Names) if (const FOKStreetModelAnchor* A = Place.Anchors.FindByPredicate([&N](const FOKStreetModelAnchor& X) { return X.Name == N; })) return A;
 return nullptr;
}

// Whether a world point stands in one of the place's rooms (2D).
inline bool OKStreetInsidePlace(const FOKStreetPlace& Place, const FVector& Point) {
 for (const FBox& Room : Place.Rooms) if (Point.X >= Room.Min.X && Point.X <= Room.Max.X && Point.Y >= Room.Min.Y && Point.Y <= Room.Max.Y && Point.Z >= Room.Min.Z - 60.f && Point.Z < Room.Max.Z - 60.f) return true;
 return false;
}

// A roof reached by its own stairs from the street (the campus rooftop: no lift goes above 5F, only the stairs at each
// building's wall, anchors "stair_bottom..." on the ground). The place At is on, if it is one, and the room (roof) it is on.
inline const TArray<FOKStreetPlace>& OKStreetPlaces();
inline const FOKStreetPlace* OKStreetStairRoof(const FVector& At, const FBox** Roof = nullptr) {
 for (const auto& P : OKStreetPlaces()) {
  if (P.Anchors.ContainsByPredicate([](const FOKStreetModelAnchor& A) { return A.Name.StartsWith(TEXT("lift")); })) continue;
  if (!P.Anchors.ContainsByPredicate([](const FOKStreetModelAnchor& A) { return A.Name.StartsWith(TEXT("stair_bottom")); })) continue;
  for (const FBox& Room : P.Rooms) if (At.X >= Room.Min.X && At.X <= Room.Max.X && At.Y >= Room.Min.Y && At.Y <= Room.Max.Y && At.Z >= Room.Min.Z - 60.f && At.Z < Room.Max.Z - 60.f) {
   if (Roof) *Roof = &Room;
   return &P;
  }
 }
 return nullptr;
}
// The foot of the stairs up to that roof: the stair_bottom closest to the roof (each roof has its own at its wall).
inline FVector OKStreetRoofStairFoot(const FOKStreetPlace& Place, const FBox& Roof) {
 FVector Best = Place.Door; double BestSq = TNumericLimits<double>::Max();
 for (const auto& A : Place.Anchors) {
  if (!A.Name.StartsWith(TEXT("stair_bottom"))) continue;
  const double Dx = FMath::Max3(Roof.Min.X - A.Position.X, 0.0, A.Position.X - Roof.Max.X), Dy = FMath::Max3(Roof.Min.Y - A.Position.Y, 0.0, A.Position.Y - Roof.Max.Y);
  if (Dx * Dx + Dy * Dy < BestSq) { BestSq = Dx * Dx + Dy * Dy; Best = A.Position; }
 }
 return Best;
}

enum class EOKStreetActivityKind : uint8 { Pair, Photo, Facility, Walk, Restroom, Sleep, Solo };

struct FOKStreetActivity {
 const TCHAR* Id;
 const TCHAR* Name;
 const TCHAR* Place; // place id, or empty: done where the pair is standing
 EOKStreetActivityKind Kind;
 int32 Code; // BeginPair kind (1 seated, 2 drink, 3/4 splash, 5 meal, 6/7 watermelon, 8 phone, 9 bath, 10 read, 11 seated on the place's own benches) or BeginFacility kind
 const TCHAR* Anchor = nullptr; // spot inside the place model where it happens (the pair walks in and faces its way)
 // Original-game curves for this place (venue.manifest.json): her clip (seated variants keep the seated benches;
 // Solo plays it standing beside him) and, for Solo, his own (else he just stands with her).
 const TCHAR* FemaleClip = nullptr;
 const TCHAR* MaleClip = nullptr;
 const TCHAR* ZhName = nullptr; // the data's own name, kept when the language swaps Name
 const TCHAR* Effect = nullptr; // shown while it runs (activities.toml effect: "explosion")
 float Turn = 0.f; // degrees added to the anchor's facing (activities.toml turn)
};

// The activities come from the rules (rules/activities.toml, activities.rs `activities_table`), read with the other
// tables (OKRulesReadTables) and again when the language changes. The rows' text lives in OKStreetActivityTexts so the
// TCHAR pointers stay valid; a reload keeps the old text alive (a pointer taken before it still reads).
struct FOKStreetActivityText { FString Id, Name, ZhName, Place, Anchor, FemaleClip, MaleClip, Effect; };
inline TArray<TUniquePtr<FOKStreetActivityText>>& OKStreetActivityTexts() { static TArray<TUniquePtr<FOKStreetActivityText>> Texts; return Texts; }
inline TArray<FOKStreetActivity>& OKStreetActivitiesMutable() { static TArray<FOKStreetActivity> All; return All; }
inline const TArray<FOKStreetActivity>& OKStreetActivities() { return OKStreetActivitiesMutable(); }
// What the activities use (activities.toml needs: the fish food, a sketchbook): one at hand is enough for the two of them.
inline TSet<FString>& OKStreetActivitySupplies() { static TSet<FString> All; return All; }

inline const FOKStreetActivity* OKStreetFindActivity(const FString& Id) {
 for (const auto& A : OKStreetActivities()) if (Id == A.Id) return &A;
 return nullptr;
}
// What an activity id is called in a sentence ("他和她一起去%s", her memory): the menu name without its note in
// brackets or a leading 一起 ("一起散步（你帶路）" -> "散步"); an unknown id stays as it is.
inline const FOKStreetPlace* OKStreetFindPlace(const FString& Id); // below
inline FString OKStreetActivityName(const FString& Id) {
 // "stroll" (walking around nearby) is no menu activity: said as the walk ("went to stroll" in the rumours).
 if (Id == TEXT("stroll")) return OKStreetActivityName(TEXT("walk"));
 const FOKStreetActivity* A = OKStreetFindActivity(Id);
 // Going somewhere ("go:playground", or a bare place id): the place's name, never the id (a rumour said "went to
 // go:playground" and the listener made it a watermelon game there).
 if (!A) { const FOKStreetPlace* P = OKStreetFindPlace(Id.StartsWith(TEXT("go:")) ? Id.Mid(3) : Id); return P ? FString(P->Name) : Id; }
 FString Name = A->Name; int32 Bracket = INDEX_NONE; if (Name.FindChar(TCHAR(0xFF08), Bracket)) Name.LeftInline(Bracket);
 Name.RemoveFromStart(TEXT("就地")); Name.RemoveFromStart(TEXT("一起")); // "就地坐下聊天" -> "坐下聊天"
 // "在学生餐厅一起吃饭" -> "学生餐厅吃饭": after "一起去" the place comes first ("一起去在学生餐厅一起吃饭" in the rumours).
 if (Name.RemoveFromStart(TEXT("在"))) { const int32 Together = Name.Find(TEXT("一起")); if (Together != INDEX_NONE) Name.RemoveAt(Together, 2); }
 Name.TrimStartAndEndInline(); return Name.IsEmpty() ? FString(A->Name) : Name;
}
// The facility activity (restaurant room, hotel room, spa) of a facility index: its Code.
inline const FOKStreetActivity* OKStreetFacilityActivity(int32 Facility) {
 for (const auto& A : OKStreetActivities()) if (A.Kind == EOKStreetActivityKind::Facility && A.Code == Facility) return &A;
 return nullptr;
}

// A boxy building facing `Facing` (unit, along X or Y): body, roof slab, door, sign band, awning, windows.
inline void OKStreetBuilding(FOKStreetPlace& P, FVector2D Center, FVector Size, FVector2D Facing, EOKStreetMaterial Body, EOKStreetMaterial Roof, EOKStreetMaterial Sign, bool TwoFloors) {
 auto Add = [&P](EOKStreetMesh Mesh, EOKStreetMaterial M, FVector C, FVector S, bool Solid) {
  FOKStreetPlacePart Part;Part.Mesh = Mesh;Part.Material = M;Part.Center = C;Part.Size = S;Part.Solid = Solid;P.Parts.Add(Part);
 };
 const FVector Base(Center.X, Center.Y, 0);
 Add(EOKStreetMesh::Cube, Body, Base + FVector(0, 0, Size.Z * .5f), Size, true);
 Add(EOKStreetMesh::Cube, Roof, Base + FVector(0, 0, Size.Z + 15), FVector(Size.X + 60, Size.Y + 60, 30), false);
 const bool AlongX = FMath::Abs(Facing.X) > FMath::Abs(Facing.Y);
 const FVector Normal(Facing.X, Facing.Y, 0);
 const FVector Side = AlongX ? FVector(0, 1, 0) : FVector(1, 0, 0);
 const float Half = (AlongX ? Size.X : Size.Y) * .5f, Width = AlongX ? Size.Y : Size.X;
 auto Face = [&](EOKStreetMaterial M, float Along, float Z, float W, float H, float Depth) {
  const FVector C = Base + Normal * (Half + Depth * .5f) + Side * Along + FVector(0, 0, Z);
  Add(EOKStreetMesh::Cube, M, C, AlongX ? FVector(Depth, W, H) : FVector(W, Depth, H), false);
 };
 Face(EOKStreetMaterial::Wood, 0, 115, 170, 230, 10); // door
 Face(Sign, 0, Size.Z - 55, Width * .72f, 56, 16); // sign band
 Face(EOKStreetMaterial::Stripe, 0, 262, 260, 14, 110); // awning over the door
 for (const float Along : {-Width * .32f, Width * .32f}) Face(EOKStreetMaterial::Glass, Along, 150, Width * .2f, 120, 6);
 if (TwoFloors) for (const float Along : {-Width * .32f, 0.f, Width * .32f}) Face(EOKStreetMaterial::Glass, Along, Size.Z - 160, Width * .18f, 90, 6);
 P.Door = Base + Normal * (Half + 260);
}

// A box building he walks into (the clinics and the salon, user 2026-11-03, before the map has them): open inside, one
// room, spots given in the building's own frame (Ahead towards the door, Right to its right, Turn from facing the door).
struct FOKStreetSpot { const TCHAR* Name; float Ahead, Right, Turn; };
inline void OKStreetWalkInBuilding(FOKStreetPlace& P, FVector2D Center, FVector Size, FVector2D Facing, EOKStreetMaterial Body, EOKStreetMaterial Roof, EOKStreetMaterial Sign, std::initializer_list<FOKStreetSpot> Spots) {
 OKStreetBuilding(P, Center, Size, Facing, Body, Roof, Sign, false);
 P.Parts[0].Solid = false;
 const FVector Base(Center.X, Center.Y, 0), Front(Facing.X, Facing.Y, 0), Right(-Facing.Y, Facing.X, 0);
 P.Rooms.Add(FBox(Base - FVector(Size.X * .5f, Size.Y * .5f, 0), Base + FVector(Size.X * .5f, Size.Y * .5f, 450.f))); P.RoomLevels.Add(1);
 const float FrontYaw = Front.Rotation().Yaw;
 // (Anchor yaw is a character rotation: she faces yaw + 90.)
 for (const FOKStreetSpot& S : Spots) { FOKStreetModelAnchor A; A.Name = S.Name; A.Position = Base + Front * S.Ahead + Right * S.Right; A.Yaw = FRotator::NormalizeAxis(FrontYaw + S.Turn - 90.f); P.Anchors.Add(A); }
}

// Vacant lots from property.json become places (navigation, PlaceHere, a heroine's workplace): the lot's ground is
// its one room; what stands on it is spawned at runtime (OKStreetSocialCompanyWorld.inl). Id and name are TCHAR
// pointers in FOKStreetPlace, so their strings are kept for the life of the program.
inline void OKStreetAppendPropertyLots(TArray<FOKStreetPlace>& Out) {
 static TArray<TUniquePtr<FString>> Strings;
 auto Keep = [](const FString& Text) -> const TCHAR* { Strings.Add(MakeUnique<FString>(Text)); return **Strings.Last(); };
 for (const FOKStreetUnitDef& U : OKStreetProperty().Units) {
  if (!U.bLot) continue;
  FOKStreetPlace& P = Out.AddDefaulted_GetRef();
  P.Id = Keep(U.Id); P.Name = Keep(U.Name.IsEmpty() ? U.Id : U.Name); P.About = Keep(TEXT("一塊空地，可以租或買下來蓋房子"));
  const bool AlongX = FMath::IsNearlyEqual(FMath::Abs(FRotator::NormalizeAxis(U.Yaw)), 0.f) || FMath::IsNearlyEqual(FMath::Abs(FRotator::NormalizeAxis(U.Yaw)), 180.f);
  const FVector Half(AlongX ? U.Size.Y * 0.5f : U.Size.X * 0.5f, AlongX ? U.Size.X * 0.5f : U.Size.Y * 0.5f, 0.f);
  const FVector Center(U.Center.X, U.Center.Y, 0.f), Front = FRotator(0, U.Yaw, 0).Vector();
  P.Door = Center + Front * ((AlongX ? Half.X : Half.Y) + 150.f);
  P.Rooms.Add(FBox(Center - FVector(Half.X, Half.Y, 0.f), Center + FVector(Half.X, Half.Y, 450.f))); P.RoomLevels.Add(1);
  // Spots for whoever works there: a counter by the front, desks behind it.
  auto Anchor = [&](const TCHAR* Name, const FVector& Local, float Yaw) { FOKStreetModelAnchor A; A.Name = Name; A.Position = Center + FRotator(0, U.Yaw, 0).RotateVector(Local); A.Yaw = FRotator::NormalizeAxis(U.Yaw + Yaw); P.Anchors.Add(A); };
  // (Anchor yaw is a character rotation: it faces yaw + 90, so -90 faces the street.)
  Anchor(TEXT("counter"), FVector(240, 0, 0), -90.f); Anchor(TEXT("seat"), FVector(-60, -200, 0), -90.f); Anchor(TEXT("seat2"), FVector(-60, 200, 0), -90.f); Anchor(TEXT("table"), FVector(0, 0, 0), -90.f);
 }
}

inline const TArray<FOKStreetPlace>& OKStreetPlaces();

// The city's data (Tools/export_street_city_game_places.lua): its places, and the road graph his long walks follow.
struct FOKStreetCityData {
 TSharedPtr<FJsonObject> Root;
 TArray<FVector> Nodes; // road points
 TArray<TArray<int32>> Links; // each node's neighbours
 TArray<int32> Walk; // the street walks' stops
 TWeakObjectPtr<UWorld> World; // set by OKStreetCityCheckRoads: the routes ask it what stands between
 TArray<int32> Kept; int32 KeptPart = INDEX_NONE; // which connected part each point is in, and the one kept
 TSet<int32> NoStart; // points he tried to walk onto the graph at and could not
};
inline FVector OKStreetJsonVector(const FJsonObject& O, const TCHAR* Field) {
 const TArray<TSharedPtr<FJsonValue>>* V = nullptr;
 if (!O.TryGetArrayField(Field, V) || V->Num() < 3) return FVector::ZeroVector;
 return FVector((*V)[0]->AsNumber(), (*V)[1]->AsNumber(), (*V)[2]->AsNumber());
}
inline FOKStreetCityData& OKStreetCity() {
 static FOKStreetCityData City = [] {
  FOKStreetCityData Out;
  const FString Path = FPaths::GetPath(OKStreetPlaceModelDir()) / TEXT("city_places.json");
  FString Body;
  if (!FFileHelper::LoadFileToString(Body, *Path) || !FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Body), Out.Root) || !Out.Root) { UE_LOG(LogTemp, Error, TEXT("Street city: cannot read %s"), *Path); Out.Root.Reset(); return Out; }
  const TSharedPtr<FJsonObject>* Road = nullptr;
  if (Out.Root->TryGetObjectField(TEXT("road"), Road)) {
   const TArray<TSharedPtr<FJsonValue>>* Rows = nullptr;
   if ((*Road)->TryGetArrayField(TEXT("nodes"), Rows)) for (const auto& V : *Rows) { const auto& P = V->AsArray(); Out.Nodes.Add(FVector(P[0]->AsNumber(), P[1]->AsNumber(), P[2]->AsNumber())); }
   Out.Links.SetNum(Out.Nodes.Num());
   if ((*Road)->TryGetArrayField(TEXT("links"), Rows)) for (const auto& V : *Rows) { const auto& L = V->AsArray(); const int32 A = int32(L[0]->AsNumber()), B = int32(L[1]->AsNumber()); if (Out.Links.IsValidIndex(A) && Out.Links.IsValidIndex(B)) { Out.Links[A].Add(B); Out.Links[B].Add(A); } }
   if ((*Road)->TryGetArrayField(TEXT("walk"), Rows)) for (const auto& V : *Rows) Out.Walk.Add(int32(V->AsNumber()));
  }
  UE_LOG(LogTemp, Display, TEXT("Street city: %d road points, %d walk stops from %s"), Out.Nodes.Num(), Out.Walk.Num(), *Path);
  return Out;
 }();
 return City;
}
// What the maps draw of the road graph: its points stand on a 6 m lattice over every road and square, so the maps fill each
// point's cell (runs of a row merged into one box, ~1,600 in all) instead of drawing its 90,000 links, which buried the big
// map in a grey sheet and took it to 10 FPS (2026-11-14). Only linked points of the kept part; doors off the lattice are left
// out. Built again when the graph changes (the checked roads replace the picture's once the map is up).
inline const TArray<FBox2D>& OKStreetCityRoadAreas() {
 const FOKStreetCityData& City = OKStreetCity();
 static TArray<FBox2D> Areas; static int32 Nodes = -1, Part = -2, Kept = -1;
 if (Nodes == City.Nodes.Num() && Part == City.KeptPart && Kept == City.Kept.Num()) return Areas;
 Nodes = City.Nodes.Num(); Part = City.KeptPart; Kept = City.Kept.Num(); Areas.Reset();
 if (City.Nodes.IsEmpty()) return Areas;
 const double Step = 600, OX = City.Nodes[0].X, OY = City.Nodes[0].Y;
 TMap<int64, TArray<int64>> Rows;
 for (int32 N = 0; N < City.Nodes.Num() && N < City.Links.Num(); ++N) {
  if (City.Links[N].IsEmpty() || (City.KeptPart != INDEX_NONE && (!City.Kept.IsValidIndex(N) || City.Kept[N] != City.KeptPart))) continue;
  const double FX = (City.Nodes[N].X - OX) / Step, FY = (City.Nodes[N].Y - OY) / Step;
  const int64 IX = FMath::RoundToInt64(FX), IY = FMath::RoundToInt64(FY);
  if (FMath::Abs(FX - IX) > .01 || FMath::Abs(FY - IY) > .01) continue;
  Rows.FindOrAdd(IY).Add(IX);
 }
 for (auto& Row : Rows) {
  Row.Value.Sort();
  auto Emit = [&](int64 A, int64 B) { Areas.Add(FBox2D(FVector2D(OX + (A - .5) * Step, OY + (Row.Key - .5) * Step), FVector2D(OX + (B + .5) * Step, OY + (Row.Key + .5) * Step))); };
  int64 Start = Row.Value[0], Prev = Start;
  for (int32 I = 1; I < Row.Value.Num(); ++I) { if (Row.Value[I] > Prev + 1) { Emit(Start, Prev); Start = Row.Value[I]; } Prev = Row.Value[I]; }
  Emit(Start, Prev);
 }
 UE_LOG(LogTemp, Display, TEXT("Street city: the maps draw the road graph as %d boxes"), Areas.Num());
 return Areas;
}

// Is a body's way clear between two points of the street (he walks 105 cm over the ground, so a kerb is no wall)?
// Radius: a thinner body from where he stands, since he may stand closer to a fence than the 30 cm of the graph's links.
inline bool OKStreetCityClear(const UWorld* World, const FVector& A, const FVector& B, float Radius = 30.f) {
 FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetCityClear), false);
 FHitResult Hit;
 return !World->SweepSingleByChannel(Hit, A + FVector(0, 0, 105), B + FVector(0, 0, 105), FQuat::Identity, ECC_WorldStatic, FCollisionShape::MakeCapsule(Radius, 60), Query);
}
// The road graph comes from a picture of the roads, which knows no fences: once the map is up, each point takes the height
// of its ground and each link the map blocks is dropped; only the biggest connected part stays.
inline void OKStreetCityCheckRoads(UWorld* World) {
 FOKStreetCityData& City = OKStreetCity();
 City.World = World;
 const double Started = FPlatformTime::Seconds();
 // A streamed map has only his surroundings loaded, so nothing can be checked here: it reads what the whole map said
 // (a run on the source map with -CityBakeRoads writes city_roads.json).
 const FString BakedPath = FPaths::GetPath(OKStreetPlaceModelDir()) / TEXT("city_roads.json");
 const bool Bake = FParse::Param(FCommandLine::Get(), TEXT("CityBakeRoads"));
 bool Baked = false;
 if (World->GetWorldPartition()) {
  FString Body; TSharedPtr<FJsonObject> Root; const TArray<TSharedPtr<FJsonValue>>* Rows = nullptr;
  if (FFileHelper::LoadFileToString(Body, *BakedPath) && FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Body), Root) && Root && Root->TryGetArrayField(TEXT("nodes"), Rows)) {
   City.Nodes.Reset(); for (const auto& V : *Rows) { const auto& P = V->AsArray(); City.Nodes.Add(FVector(P[0]->AsNumber(), P[1]->AsNumber(), P[2]->AsNumber())); }
   City.Links.Reset(); City.Links.SetNum(City.Nodes.Num());
   if (Root->TryGetArrayField(TEXT("links"), Rows)) for (const auto& V : *Rows) { const auto& L = V->AsArray(); const int32 A = int32(L[0]->AsNumber()), B = int32(L[1]->AsNumber()); City.Links[A].Add(B); City.Links[B].Add(A); }
   Baked = true;
  } else UE_LOG(LogTemp, Error, TEXT("Street city: streamed map without %s: the road graph is unchecked"), *BakedPath);
 }
 FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetCityRoads), false);
 int32 Dropped = 0;
 if (!World->GetWorldPartition()) {
 // The ground at the point's own height first (the picture puts every point at 1200): traced from 4 m up, the first thing
 // hit was a wall's or a planter's top beside the road, points stood 1.8 m up on them, and a walk along that road was
 // stepped into the wall at every point, 20 s each (R6-180). From 4 m up only where nothing is under the point's height
 // (a hill).
 for (FVector& Node : City.Nodes) { FHitResult Hit;
  if (World->LineTraceSingleByChannel(Hit, Node + FVector(0, 0, 60), Node - FVector(0, 0, 600), ECC_WorldStatic, Query) || World->LineTraceSingleByChannel(Hit, Node + FVector(0, 0, 400), Node - FVector(0, 0, 600), ECC_WorldStatic, Query)) Node.Z = Hit.ImpactPoint.Z; }
 for (int32 A = 0; A < City.Nodes.Num(); ++A) for (int32 I = City.Links[A].Num() - 1; I >= 0; --I) {
  const int32 B = City.Links[A][I];
  if (B > A && !OKStreetCityClear(World, City.Nodes[A], City.Nodes[B])) { City.Links[A].RemoveAt(I); City.Links[B].Remove(A); ++Dropped; }
 }
 const int32 Lattice = City.Nodes.Num();
 // A door with no floor under it or inside something (the ramen shop's on its 9F counter seat, the Christmas tree's in the
 // campus fence, the north restroom's; places_check 11-09): the data's doors come from the models' anchors and the picture
 // of the roads, which know nothing solid. Such a door moves to the nearest spot round it with a floor at its height and
 // room for a body, one in sight of a road point first (outdoors), so a walk there ends on its feet beside it.
 {
  auto Fine = [&](FVector& At) {
   FHitResult Hit;
   if (!World->LineTraceSingleByChannel(Hit, At + FVector(0, 0, 70), At - FVector(0, 0, 120), ECC_WorldStatic, Query) || Hit.bStartPenetrating || Hit.ImpactPoint.Z > At.Z + 50.f) return false;
   const float Ground = float(Hit.ImpactPoint.Z);
   if (World->OverlapAnyTestByChannel(FVector(At.X, At.Y, Ground + 105.f), FQuat::Identity, ECC_WorldStatic, FCollisionShape::MakeCapsule(25.f, 60.f), Query)) return false;
   At.Z = Ground; return true; };
  auto SeesRoad = [&](const FVector& At) {
   for (int32 N = 0; N < Lattice; ++N) if (FVector::DistSquared2D(City.Nodes[N], At) < FMath::Square(1500.f) && FMath::Abs(City.Nodes[N].Z - At.Z) < 200.f && OKStreetCityClear(World, At, City.Nodes[N])) return true;
   return false; };
  int32 Moved = 0;
  for (FOKStreetPlace& P : const_cast<TArray<FOKStreetPlace>&>(OKStreetPlaces())) {
   FVector Here = P.Door; if (Fine(Here)) continue;
   FVector Best = P.Door; double BestScore = TNumericLimits<double>::Max();
   for (float R = 40.f; R <= 400.f; R += 30.f) {
    for (int32 K = 0; K < 24; ++K) {
     const float T = 2.f * PI * K / 24.f; FVector At = P.Door + FVector(FMath::Cos(T) * R, FMath::Sin(T) * R, 0);
     if (!Fine(At)) continue;
     // Open air, the side the place is on: the Christmas tree's door went over the campus fence, 40 cm nearer than the
     // street side, and every walk to the tree went round by the gate.
     FVector Middle = P.Door; if (P.Outdoor && !P.Rooms.IsEmpty()) Middle = P.Rooms[0].GetCenter();
     const double Score = R + (P.Door.Z < 1450.f && !SeesRoad(At) ? 2000.0 : 0.0) + (P.Outdoor ? FVector::Dist2D(At, Middle) * .5 : 0.0);
     if (Score < BestScore) { BestScore = Score; Best = At; }
    }
   }
   if (BestScore < TNumericLimits<double>::Max()) { UE_LOG(LogTemp, Display, TEXT("Street city: door of %s inside something or over no floor, %s -> %s"), P.Id, *P.Door.ToCompactString(), *Best.ToCompactString()); P.Door = Best; ++Moved; }
   else UE_LOG(LogTemp, Warning, TEXT("Street city: door of %s inside something or over no floor, and no spot round it"), P.Id);
  }
  UE_LOG(LogTemp, Display, TEXT("Street city: %d doors moved onto open floor"), Moved);
 }
 // Every door is on the graph too, tied to the points it can reach: the picture of the roads knows no doors either.
 // So is every gate: a door on either side of a fence is how the two sides meet.
 auto Tie = [&](const FVector& At) {
  const int32 Door = City.Nodes.Add(At); City.Links.AddDefaulted();
  for (int32 N = 0; N < Lattice; ++N) if (FVector::DistSquared2D(City.Nodes[N], At) < FMath::Square(1500.f) && FMath::Abs(City.Nodes[N].Z - At.Z) < 200.f && OKStreetCityClear(World, At, City.Nodes[N])) { City.Links[Door].Add(N); City.Links[N].Add(Door); } };
 for (const auto& P : OKStreetPlaces()) { Tie(P.Door); for (const auto& A : P.Anchors) if (A.Name.StartsWith(TEXT("gate"))) Tie(A.Position); }
 }
 TArray<int32> Part; Part.Init(INDEX_NONE, City.Nodes.Num());
 int32 Biggest = INDEX_NONE, BiggestSize = 0;
 for (int32 Start = 0; Start < City.Nodes.Num(); ++Start) {
  if (Part[Start] != INDEX_NONE) continue;
  TArray<int32> Open = {Start}; Part[Start] = Start; int32 Size = 0;
  while (!Open.IsEmpty()) { const int32 N = Open.Pop(EAllowShrinking::No); ++Size; for (const int32 Next : City.Links[N]) if (Part[Next] == INDEX_NONE) { Part[Next] = Start; Open.Add(Next); } }
  if (Size > 50) UE_LOG(LogTemp, Display, TEXT("Street city: road part from %s: %d points"), *City.Nodes[Start].ToCompactString(), Size);
  if (Size > BiggestSize) { BiggestSize = Size; Biggest = Start; }
 }
 for (int32 N = 0; N < City.Nodes.Num(); ++N) if (Part[N] != Biggest) City.Links[N].Reset();
 City.Kept = MoveTemp(Part); City.KeptPart = Biggest;
 UE_LOG(LogTemp, Display, TEXT("Street city: road check %s, dropped %d links, %d of %d points connected (%.0f ms)"), Baked ? TEXT("read from the bake") : TEXT("on the map"), Dropped, BiggestSize, City.Nodes.Num(), (FPlatformTime::Seconds() - Started) * 1000.0);
 if (Bake && !World->GetWorldPartition()) {
  FString Out = TEXT("{\"nodes\":[");
  for (int32 N = 0; N < City.Nodes.Num(); ++N) Out += FString::Printf(TEXT("%s[%.1f,%.1f,%.1f]"), N ? TEXT(",") : TEXT(""), City.Nodes[N].X, City.Nodes[N].Y, City.Nodes[N].Z);
  Out += TEXT("],\"links\":["); bool First = true;
  for (int32 A = 0; A < City.Nodes.Num(); ++A) for (const int32 B : City.Links[A]) if (B > A) { Out += FString::Printf(TEXT("%s[%d,%d]"), First ? TEXT("") : TEXT(","), A, B); First = false; }
  Out += TEXT("]}\n");
  UE_LOG(LogTemp, Display, TEXT("Street city: road bake %s: %s"), *BakedPath, FFileHelper::SaveStringToFile(Out, *BakedPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM) ? TEXT("written") : TEXT("FAILED"));
 }
}

// He could not walk from A to B: that link is gone, or, from somewhere off the graph, B is not a way onto it from there.
inline void OKStreetCityBlocked(const FVector& A, const FVector& B) {
 FOKStreetCityData& City = OKStreetCity();
 auto Node = [&City](const FVector& At) { for (int32 I = 0; I < City.Nodes.Num(); ++I) if (FVector::DistSquared2D(City.Nodes[I], At) < 1.0) return I; return int32(INDEX_NONE); };
 const int32 From = Node(A), To = Node(B);
 if (To == INDEX_NONE) return;
 if (From != INDEX_NONE && City.Links[From].Remove(To) > 0) { City.Links[To].Remove(From); UE_LOG(LogTemp, Display, TEXT("Street city: link %d-%d blocked"), From, To); return; }
 City.NoStart.Add(To);
}

// The way along the roads: to a road point he can reach from where he is, along the graph, to the one nearest the goal.
inline TArray<FVector> OKStreetCityRoute(const FVector& From, const FVector& To) {
 const FOKStreetCityData& City = OKStreetCity();
 auto Nearest = [&City](const FVector& At) {
  TArray<TPair<double, int32>> Near;
  for (int32 I = 0; I < City.Nodes.Num(); ++I) if ((City.Kept.IsEmpty() || City.Kept[I] == City.KeptPart) && !City.NoStart.Contains(I)) Near.Emplace(FVector::DistSquared2D(City.Nodes[I], At), I);
  Near.Sort([](const TPair<double, int32>& A, const TPair<double, int32>& B) { return A.Key < B.Key; });
  const UWorld* World = City.World.Get();
  for (int32 I = 0; World && I < FMath::Min(Near.Num(), 24); ++I) if (OKStreetCityClear(World, At, City.Nodes[Near[I].Value], 18.f)) return Near[I].Value;
  return Near.IsEmpty() ? INDEX_NONE : Near[0].Value; };
 const int32 Start = Nearest(From), Goal = Nearest(To);
 if (Start == INDEX_NONE || Goal == INDEX_NONE) return {From, To};
 TArray<double> Cost; Cost.Init(TNumericLimits<double>::Max(), City.Nodes.Num());
 TArray<int32> Came; Came.Init(INDEX_NONE, City.Nodes.Num());
 typedef TPair<double, int32> FOpen; TArray<FOpen> Open;
 auto Less = [](const FOpen& A, const FOpen& B) { return A.Key < B.Key; };
 Cost[Start] = 0; Open.HeapPush(FOpen(0, Start), Less);
 while (!Open.IsEmpty()) {
  FOpen Top; Open.HeapPop(Top, Less);
  if (Top.Value == Goal) break;
  for (const int32 Next : City.Links[Top.Value]) {
   const double New = Cost[Top.Value] + FVector::Dist2D(City.Nodes[Top.Value], City.Nodes[Next]);
   if (New < Cost[Next]) { Cost[Next] = New; Came[Next] = Top.Value; Open.HeapPush(FOpen(New + FVector::Dist2D(City.Nodes[Next], City.Nodes[Goal]), Next), Less); }
  }
 }
 if (Start != Goal && Came[Goal] == INDEX_NONE) return {From, To};
 TArray<FVector> Route = {To};
 for (int32 At = Goal; At != INDEX_NONE; At = Came[At]) Route.Add(City.Nodes[At]);
 Route.Add(From);
 Algo::Reverse(Route);
 return Route;
}

// In the city each place comes from the data: an old id keeps its words for the model, a new one starts from its name.
// The smallest place first, so a room in a building is found before the building (PlaceHere takes the first).
inline void OKStreetApplyCityPlaces(TArray<FOKStreetPlace>& Out) {
 static TArray<TUniquePtr<FString>> Strings;
 auto Keep = [](const FString& Text) -> const TCHAR* { Strings.Add(MakeUnique<FString>(Text)); return **Strings.Last(); };
 const TSharedPtr<FJsonObject>& Root = OKStreetCity().Root;
 const TArray<TSharedPtr<FJsonValue>>* Rows = nullptr;
 if (!Root || !Root->TryGetArrayField(TEXT("places"), Rows)) return;
 TArray<FOKStreetPlace> Next;
 for (const auto& V : *Rows) {
  const TSharedPtr<FJsonObject> O = V->AsObject();
  const FString Id = O->GetStringField(TEXT("id")), Name = O->GetStringField(TEXT("name"));
  FOKStreetPlace P;
  if (const FOKStreetPlace* Old = Out.FindByPredicate([&](const FOKStreetPlace& X) { return Id == X.Id; })) P = *Old;
  else { P.Id = Keep(Id); P.Name = Keep(Name); P.About = P.Name; }
  P.Parts.Reset(); P.Model.Reset(); P.Rooms.Reset(); P.RoomLevels.Reset(); P.Anchors.Reset();
  P.Door = OKStreetJsonVector(*O, TEXT("door"));
  { bool Open = false; P.Outdoor = O->TryGetBoolField(TEXT("outdoor"), Open) && Open; }
  for (const auto& R : O->GetArrayField(TEXT("rooms"))) {
   const TSharedPtr<FJsonObject> Room = R->AsObject();
   P.Rooms.Add(FBox(OKStreetJsonVector(*Room, TEXT("min")), OKStreetJsonVector(*Room, TEXT("max"))));
   P.RoomLevels.Add(int32(Room->GetNumberField(TEXT("floor"))));
  }
  for (const auto& A : O->GetArrayField(TEXT("anchors"))) {
   const TSharedPtr<FJsonObject> Row = A->AsObject();
   FOKStreetModelAnchor Anchor; Anchor.Name = Row->GetStringField(TEXT("name")); Anchor.Position = OKStreetJsonVector(*Row, TEXT("pos")); Anchor.Yaw = float(Row->GetNumberField(TEXT("yaw")));
   P.Anchors.Add(Anchor);
  }
  Next.Add(MoveTemp(P));
 }
 // The smaller place first, so a spot in one inside another is the inner one's: by the ground it covers, not its volume
 // (the BBQ area's box is 37 m tall over a corner of the playground, and the playground took every spot of it).
 auto Volume = [](const FOKStreetPlace& P) { double V = 0; for (const FBox& R : P.Rooms) V += (R.Max.X - R.Min.X) * (R.Max.Y - R.Min.Y); return V; };
 Next.StableSort([&](const FOKStreetPlace& A, const FOKStreetPlace& B) {
  const double VA = Volume(A), VB = Volume(B);
  if (!FMath::IsNearlyEqual(VA, VB, 1.0)) return VA < VB;
  return FString(A.Id).StartsWith(TEXT("campus_")) && !FString(B.Id).StartsWith(TEXT("campus_")); }); // T1 is school and campus_t1: the college's id wins
 Out = MoveTemp(Next);
 UE_LOG(LogTemp, Display, TEXT("Street city: %d places"), Out.Num());
}

inline const TArray<FOKStreetPlace>& OKStreetPlaces() {
 static TArray<FOKStreetPlace> All = [] { // not const: OKStreetCityCheckRoads moves a door the map shows to be inside something
  using M = EOKStreetMaterial;
  TArray<FOKStreetPlace> Out;
  auto Make = [&Out](const TCHAR* Id, const TCHAR* Name, const TCHAR* About) -> FOKStreetPlace& {
   FOKStreetPlace& P = Out.AddDefaulted_GetRef();P.Id = Id;P.Name = Name;P.About = About;return P;
  };
  OKStreetBuilding(Make(TEXT("restaurant"), TEXT("餐廳"), TEXT("家庭式餐廳，門口有座位，也有安靜的包廂")), FVector2D(2500, -2300), FVector(900, 800, 420), FVector2D(-1, 0), M::Cream, M::Terracotta, M::Leaf, false);
  OKStreetBuilding(Make(TEXT("snack"), TEXT("點心店"), TEXT("賣飲料和甜點的小店，可以外帶")), FVector2D(2500, 2300), FVector(900, 800, 380), FVector2D(-1, 0), M::Stripe, M::Cream, M::Lamp, false);
  OKStreetBuilding(Make(TEXT("bookstore"), TEXT("書局"), TEXT("文具和書的小書局，有漫畫和雜誌")), FVector2D(-2500, -2200), FVector(900, 900, 400), FVector2D(1, 0), M::Wood, M::Stone, M::Glass, false);
  OKStreetBuilding(Make(TEXT("lodge"), TEXT("會館"), TEXT("休閒會館，有休息房間和精油護理室")), FVector2D(-2500, 1900), FVector(900, 1100, 460), FVector2D(1, 0), M::Terracotta, M::Stone, M::Hedge, true);
  OKStreetBuilding(Make(TEXT("school"), TEXT("舊校舍（社團大樓）"), TEXT("大學搬到北邊新校園後留下的舊校舍，現在是社團活動和自習用的大樓：一樓教室、二樓自習教室、三樓音樂教室")), FVector2D(5400, -1700), FVector(1400, 1600, 600), FVector2D(-1, 0), M::Cream, M::Terracotta, M::Stripe, true);
  OKStreetBuilding(Make(TEXT("library"), TEXT("圖書館"), TEXT("安靜的市立圖書館，裡面要小聲說話")), FVector2D(5400, 300), FVector(1200, 1000, 500), FVector2D(-1, 0), M::Stone, M::Bark, M::Wood, true);
  {
   // Open field: grass, a running-track border and two goals (none of it blocks walking).
   FOKStreetPlace& P = Make(TEXT("playground"), TEXT("操場"), TEXT("學校旁的操場，有草地和跑道，適合玩水和打西瓜"));
   auto Add = [&P](EOKStreetMesh Mesh, EOKStreetMaterial Mat, FVector C, FVector S) {
    FOKStreetPlacePart Part;Part.Mesh = Mesh;Part.Material = Mat;Part.Center = C;Part.Size = S;P.Parts.Add(Part);
   };
   Add(EOKStreetMesh::Cube, M::Leaf, FVector(4950, 1900, 1), FVector(1700, 1300, 2));
   for (const float Y : {1220.f, 2580.f}) Add(EOKStreetMesh::Cube, M::Terracotta, FVector(4950, Y, 1.5f), FVector(1800, 70, 3));
   for (const float X : {4070.f, 5830.f}) Add(EOKStreetMesh::Cube, M::Terracotta, FVector(X, 1900, 1.5f), FVector(70, 1430, 3));
   for (const float X : {4250.f, 5650.f}) {
    for (const float Y : {1780.f, 2020.f}) Add(EOKStreetMesh::Cylinder, M::Stone, FVector(X, Y, 100), FVector(10, 10, 200));
    Add(EOKStreetMesh::Cube, M::Stone, FVector(X, 1900, 200), FVector(10, 250, 10));
   }
   P.Door = FVector(4600, 1900, 0);
  }
  // South extension (x -6400..-3200), shop fronts facing north toward the street.
  OKStreetBuilding(Make(TEXT("drinkshop"), TEXT("飲料店"), TEXT("手搖飲料店，有珍珠奶茶、水果茶和冰沙")), FVector2D(-4300, -1800), FVector(800, 900, 380), FVector2D(1, 0), M::Leaf, M::Cream, M::Lamp, false);
  OKStreetBuilding(Make(TEXT("fruitshop"), TEXT("水果店"), TEXT("賣當季水果的水果行，門口擺著一箱箱水果，也有切好的水果盒")), FVector2D(-4300, 0), FVector(800, 900, 360), FVector2D(1, 0), M::Cream, M::Leaf, M::Terracotta, false);
  OKStreetBuilding(Make(TEXT("petshop"), TEXT("寵物店"), TEXT("寵物店，櫥窗裡有小狗小貓，可以隔著玻璃看牠們玩")), FVector2D(-4300, 1800), FVector(800, 900, 400), FVector2D(1, 0), M::Stripe, M::Terracotta, M::Glass, false);
  // Behind the shops: the dormitories, with a walkway between.
  OKStreetBuilding(Make(TEXT("girls_dorm"), TEXT("校外女生宿舍"), TEXT("星街科技大學在街區裡的校外女生宿舍，走到校門約五分鐘；四層樓有陽台，一樓是交誼廳（訪客可以進），樓上房間男生不能上去")), FVector2D(-5750, -1700), FVector(900, 1500, 1260), FVector2D(1, 0), M::Cream, M::Terracotta, M::Stripe, true);
  OKStreetBuilding(Make(TEXT("boys_dorm"), TEXT("校外男生宿舍"), TEXT("星街科技大學在街區裡的校外男生宿舍，走到校門約五分鐘；門口有腳踏車停車架")), FVector2D(-5750, 1700), FVector(900, 1500, 1260), FVector2D(1, 0), M::Cream, M::Stone, M::Stripe, true);
  // West resort extension (y -6400..-2800), fronts facing the street (+Y).
  OKStreetBuilding(Make(TEXT("hotel"), TEXT("溫泉SPA飯店"), TEXT("高級溫泉SPA飯店，門口有泳池和椰子樹，裡面有SPA護理室和客房")), FVector2D(1600, -5200), FVector(1300, 1000, 1900), FVector2D(0, 1), M::Cream, M::Stone, M::Glass, true);
  OKStreetBuilding(Make(TEXT("minshuku"), TEXT("民宿"), TEXT("日式木造民宿，有緣側和小庭院，可以在房間休息")), FVector2D(-500, -4800), FVector(1000, 900, 320), FVector2D(0, 1), M::Cream, M::Wood, M::Wood, false);
  OKStreetBuilding(Make(TEXT("onsen"), TEXT("露天溫泉"), TEXT("露天溫泉，竹籬笆圍著冒熱氣的岩石浴池，旁邊有更衣小屋和石燈籠")), FVector2D(-2300, -5100), FVector(1400, 1500, 300), FVector2D(0, 1), M::Wood, M::Stone, M::Wood, false);
  // East university-town extension (y 2800..7800), fronts facing the street (-Y).
  OKStreetBuilding(Make(TEXT("conveni"), TEXT("便利商店"), TEXT("24小時便利商店，有冰箱飲料、零食和熱食")), FVector2D(-2300, 4100), FVector(1000, 800, 340), FVector2D(0, -1), M::Cream, M::Stone, M::Leaf, false);
  // Campus (Docs/STREET_SOCIAL_CAMPUS_PLAN.md): one five-storey building per college, north of the school side, fronts
  // facing south toward the street. Rows at x 8800 / 12000 / 15200.
  {struct FCampus{const TCHAR* Id;const TCHAR* Name;const TCHAR* About;FVector2D At;};
   const FCampus Campus[]={
    {TEXT("campus_t1"),TEXT("第一教學大樓 T1（共同教育委員會）"),TEXT("通識課的教室大樓，五層樓，1 樓有通識教育中心辦公室"),FVector2D(8800,-4000)},
    {TEXT("campus_rb"),TEXT("綜合研究大樓 RB（產學創新學院）"),TEXT("產學創新學院的大樓，五層樓，1 樓是各所辦公室"),FVector2D(8800,-500)},
    {TEXT("campus_ib"),TEXT("國際大樓 IB（應用科技學院）"),TEXT("應用科技學院的大樓，五層樓，1 樓是各所辦公室"),FVector2D(8800,3000)},
    {TEXT("campus_t4"),TEXT("第四教學大樓 T4（設計學院）"),TEXT("設計學院的大樓，五層樓，1 樓是設計系和建築系的系辦"),FVector2D(12000,-4000)},
    {TEXT("campus_e1"),TEXT("工程一館 E1（工程學院）"),TEXT("工程學院的大樓，五層樓，1 樓是機械、材料、營建、化工系辦"),FVector2D(12000,-500)},
    {TEXT("campus_ma"),TEXT("管理大樓 MA（管理學院）"),TEXT("管理學院的大樓，五層樓，1 樓是工管、企管、資管系辦與財金所辦"),FVector2D(12000,3000)},
    {TEXT("campus_t2"),TEXT("第二教學大樓 T2（人文社會學院）"),TEXT("人文社會學院的大樓，五層樓，1 樓是應外系和數位學習所辦"),FVector2D(15200,-2250)},
    {TEXT("campus_ee"),TEXT("電資館 EE（電資學院）"),TEXT("電資學院的大樓，五層樓，1 樓是電子、電機、資工系辦與光電所辦"),FVector2D(15200,1250)},
    {TEXT("campus_ad"),TEXT("行政大樓 AD"),TEXT("校門旁的行政大樓，五層樓，1 樓是註冊組（入學考）、教務處（轉系）、學務處（休學、復學）"),FVector2D(8800,-7600)}};
   for(const auto& C:Campus)OKStreetBuilding(Make(C.Id,C.Name,C.About),C.At,FVector(1400,2800,1700),FVector2D(-1,0),M::Cream,M::Stone,M::Glass,true);}
  OKStreetBuilding(Make(TEXT("campus_gate"), TEXT("星街科技大學 校門"), TEXT("大學的正門，石柱上掛著校名，旁邊有警衛亭和校園地圖")), FVector2D(6600, -3200), FVector(1200, 2200, 600), FVector2D(-1, 0), M::Stone, M::Stone, M::Stone, false);
  OKStreetBuilding(Make(TEXT("campus_sports"), TEXT("大學運動場"), TEXT("校園西側的運動場：跑道圍著足球場，旁邊有籃球場和看台")), FVector2D(12500, -9800), FVector(3400, 5600, 100), FVector2D(-1, 0), M::Leaf, M::Leaf, M::Leaf, false);
  // Plan §15.1: 星運彩券行, west of the convenience store (the one new place).
  OKStreetBuilding(Make(TEXT("lottery"), TEXT("星運彩券行"), TEXT("便利商店旁的彩券行，可以買星光 6/49、雙星彩、幸運刮刮卡，也能投注競技彩；牆上有開獎和賠率螢幕，門口有紅榜")), FVector2D(-3500, 4050), FVector(700, 700, 340), FVector2D(0, -1), M::Terracotta, M::Stone, M::Lamp, false);
  OKStreetBuilding(Make(TEXT("cafe"), TEXT("咖啡廳"), TEXT("紅磚咖啡廳，有吧台、沙發和小圓桌，適合坐下來慢慢聊")), FVector2D(2300, 4100), FVector(1000, 900, 380), FVector2D(0, -1), M::Terracotta, M::Stone, M::Wood, false);
  OKStreetBuilding(Make(TEXT("lecture"), TEXT("大學講堂"), TEXT("大學的紅磚講堂，門口有鐘塔，裡面是一排排課桌和黑板")), FVector2D(-5000, 4700), FVector(1600, 1400, 600), FVector2D(0, -1), M::Terracotta, M::Stone, M::Cream, true);
  OKStreetBuilding(Make(TEXT("cafeteria"), TEXT("學生餐廳"), TEXT("大學的學生餐廳，有取餐檯和長桌，便宜又大碗")), FVector2D(5000, 4600), FVector(1400, 1200, 420), FVector2D(0, -1), M::Cream, M::Leaf, M::Stripe, false);
  OKStreetBuilding(Make(TEXT("park"), TEXT("中央公園"), TEXT("大學城的中央公園，有噴水池、花圃、長椅和大樹")), FVector2D(0, 4700), FVector(200, 200, 100), FVector2D(0, -1), M::Leaf, M::Leaf, M::Leaf, false);
  OKStreetBuilding(Make(TEXT("shrine"), TEXT("神社"), TEXT("公園後面的小神社，有紅色鳥居和石燈籠，可以參拜許願")), FVector2D(0, 6800), FVector(500, 700, 300), FVector2D(0, -1), M::Wood, M::Leaf, M::Wood, false);
  OKStreetBuilding(Make(TEXT("department"), TEXT("大學城百貨"), TEXT("十層樓的百貨公司，搭電梯上下樓：1F化妝品・服務台、2F女裝、3F男裝、4F鞋包配件、5F家居生活、6F書店文具、7F電器、8F玩具、9F美食街、10F景觀餐廳")), FVector2D(-5300, 7200), FVector(1800, 2000, 4000), FVector2D(0, -1), M::Glass, M::Stone, M::Lamp, true);
  OKStreetBuilding(Make(TEXT("aquarium"), TEXT("海洋水族館"), TEXT("大學城的海洋水族館，有整面牆的大水槽、水母柱和小水槽，大水槽前有長椅")), FVector2D(4800, 6600), FVector(1400, 2000, 600), FVector2D(0, -1), M::Glass, M::Stone, M::Glass, false);
  // Public restrooms by the big public places: separate men's and women's rooms, each with its own door.
  const TCHAR* RestroomAbout = TEXT("公共廁所，男廁和女廁分開，各有自己的入口");
  OKStreetBuilding(Make(TEXT("restroom_park"), TEXT("公廁（中央公園旁）"), RestroomAbout), FVector2D(2300, 5600), FVector(500, 700, 300), FVector2D(-1, 0), M::Cream, M::Leaf, M::Cream, false);
  OKStreetBuilding(Make(TEXT("restroom_campus"), TEXT("公廁（大學講堂旁）"), RestroomAbout), FVector2D(-3500, 5600), FVector(700, 500, 300), FVector2D(0, -1), M::Cream, M::Leaf, M::Cream, false);
  OKStreetBuilding(Make(TEXT("restroom_north"), TEXT("公廁（學校操場旁）"), RestroomAbout), FVector2D(3500, -2300), FVector(500, 700, 300), FVector2D(1, 0), M::Cream, M::Leaf, M::Cream, false);
  OKStreetBuilding(Make(TEXT("restroom_resort"), TEXT("公廁（度假區）"), RestroomAbout), FVector2D(500, -5400), FVector(700, 500, 300), FVector2D(0, 1), M::Cream, M::Leaf, M::Cream, false);
  // The clinics and the salon (user 2026-11-03; ok-rules clinic.rs): rebuilding her hymen, giving her someone else's face,
  // dyeing her hair. In the resort's gap by the restroom, east of the hotel, and between the cafe and the cafeteria.
  OKStreetWalkInBuilding(Make(TEXT("clinic_gyn"), TEXT("婦科診所"), TEXT("小小的婦科診所，有櫃台、候診區、診間和手術室，可以做處女膜重建手術")), FVector2D(500, -4300), FVector(600, 700, 340), FVector2D(0, 1), M::Cream, M::Stone, M::Glass,
   {{TEXT("counter"), 200, 0, 180}, {TEXT("seat"), 150, -220, 90}, {TEXT("seat2"), 150, 220, -90}, {TEXT("doctor"), -150, -150, 0}, {TEXT("bed_op"), -200, 150, 0}, {TEXT("rest"), -50, 230, -90}, {TEXT("wait"), 250, -150, 180}});
  OKStreetWalkInBuilding(Make(TEXT("clinic_beauty"), TEXT("醫美診所"), TEXT("醫美診所，諮詢室裡有臉型參考，可以把臉整成別人的臉型，也能還原")), FVector2D(2800, -5300), FVector(700, 800, 360), FVector2D(0, 1), M::Glass, M::Stone, M::Lamp,
   {{TEXT("counter"), 230, 0, 180}, {TEXT("consult"), 0, -200, 90}, {TEXT("seat"), 150, 250, -90}, {TEXT("bed_op"), -250, 0, 0}, {TEXT("rest"), -250, 250, 0}, {TEXT("mirror"), -100, -300, 90}, {TEXT("wait"), 250, -200, 180}});
  OKStreetWalkInBuilding(Make(TEXT("salon"), TEXT("美髮店"), TEXT("美髮店，有理髮椅、洗頭台和髮色樣本牆，可以染頭髮")), FVector2D(3550, 4100), FVector(800, 800, 340), FVector2D(0, -1), M::Stripe, M::Stone, M::Lamp,
   {{TEXT("counter"), 250, -250, 180}, {TEXT("chair"), 0, -200, 90}, {TEXT("chair2"), 0, 200, -90}, {TEXT("wash"), -250, 0, 0}, {TEXT("seat"), 250, 250, 180}, {TEXT("swatch"), -100, -300, 90}});
  if (OKStreetCityMode()) { OKStreetApplyCityPlaces(Out); return Out; } // TODO his company's lots: the city's `lots` are not read yet
  // Models replace the box buildings: same spot, the model's front (+X) turned to the street.
  struct FPlacement { const TCHAR* Id; FVector Origin; float Yaw; };
  const FPlacement Placements[] = {
   {TEXT("restaurant"), FVector(2500, -2300, 0), 180}, {TEXT("snack"), FVector(2500, 2300, 0), 180},
   {TEXT("bookstore"), FVector(-2500, -2200, 0), 0}, {TEXT("lodge"), FVector(-2500, 1900, 0), 0},
   {TEXT("school"), FVector(5400, -1700, 0), 180}, {TEXT("library"), FVector(5400, 300, 0), 180},
   {TEXT("playground"), FVector(4950, 1900, 0), 0},
   {TEXT("drinkshop"), FVector(-4300, -1800, 0), 0}, {TEXT("fruitshop"), FVector(-4300, 0, 0), 0}, {TEXT("petshop"), FVector(-4300, 1800, 0), 0},
   {TEXT("girls_dorm"), FVector(-5750, -1700, 0), 0}, {TEXT("boys_dorm"), FVector(-5750, 1700, 0), 0},
   {TEXT("hotel"), FVector(1600, -5200, 0), 90}, {TEXT("minshuku"), FVector(-500, -4800, 0), 90}, {TEXT("onsen"), FVector(-2300, -5100, 0), 90},
   {TEXT("conveni"), FVector(-2300, 4100, 0), 270}, {TEXT("lottery"), FVector(-3500, 4050, 0), 270},
   {TEXT("campus_t1"), FVector(8800, -4000, 0), 180}, {TEXT("campus_rb"), FVector(8800, -500, 0), 180}, {TEXT("campus_ib"), FVector(8800, 3000, 0), 180},
   {TEXT("campus_t4"), FVector(12000, -4000, 0), 180}, {TEXT("campus_e1"), FVector(12000, -500, 0), 180}, {TEXT("campus_ma"), FVector(12000, 3000, 0), 180},
   {TEXT("campus_t2"), FVector(15200, -2250, 0), 180}, {TEXT("campus_ee"), FVector(15200, 1250, 0), 180}, {TEXT("campus_ad"), FVector(8800, -7600, 0), 180}, {TEXT("campus_gate"), FVector(6600, -3200, 0), 180}, {TEXT("campus_sports"), FVector(12500, -9800, 0), 180}, {TEXT("cafe"), FVector(2300, 4100, 0), 270}, {TEXT("lecture"), FVector(-5000, 4700, 0), 270},
   {TEXT("cafeteria"), FVector(5000, 4600, 0), 270}, {TEXT("park"), FVector(0, 4700, 0), 270}, {TEXT("shrine"), FVector(0, 6800, 0), 270},
   {TEXT("aquarium"), FVector(4800, 6600, 0), 270}, {TEXT("department"), FVector(-5300, 7200, 0), 270}, {TEXT("restroom_park"), FVector(2300, 5600, 0), 180}, {TEXT("restroom_campus"), FVector(-3500, 5600, 0), 270},
   {TEXT("restroom_north"), FVector(3500, -2300, 0), 0}, {TEXT("restroom_resort"), FVector(500, -5400, 0), 90},
  };
  const FString Dir = OKStreetPlaceModelDir();
  for (const FPlacement& At : Placements) {
   FOKStreetPlace* P = Out.FindByPredicate([&](const FOKStreetPlace& X) { return FCString::Strcmp(X.Id, At.Id) == 0; });
   if (!P) continue;
   FString Error;
   const auto Model = OKStreetLoadPlaceModel(Dir / FString(At.Id) + TEXT(".okmesh"), Error);
   if (!Model) { UE_LOG(LogTemp, Warning, TEXT("Street place model: %s (keeping the box building)"), *Error); continue; }
   const FTransform T(FRotator(0, At.Yaw, 0), At.Origin);
   P->Model = Model;P->Origin = At.Origin;P->Yaw = At.Yaw;P->Door = T.TransformPosition(Model->Door);P->Parts.Reset();
   for (const FBox& Room : Model->Rooms) P->Rooms.Add(Room.TransformBy(T));
   // An open-air place (park, shrine, playground) has no rooms in its model: its ground is the model's footprint, so
   // standing at the park's bench is "in the park" (PlaceHere was empty there, and so was every rule that asks).
   if (Model->Rooms.IsEmpty()) {
    FBox Ground(ForceInit);
    for (const FOKStreetModelSection& Sec : Model->Sections) for (const FVector& V : Sec.Positions) Ground += V;
    if (Ground.IsValid) P->Rooms.Add(FBox(FVector(Ground.Min.X, Ground.Min.Y, 0.f), FVector(Ground.Max.X, Ground.Max.Y, 450.f)).TransformBy(T));
   }
   // Floors from the rooms' heights: the lowest is 1.
   TArray<float> Heights;for (const FBox& Room : P->Rooms) Heights.AddUnique(FMath::RoundToFloat(Room.Min.Z));Heights.Sort();
   for (const FBox& Room : P->Rooms) P->RoomLevels.Add(Heights.IndexOfByKey(FMath::RoundToFloat(Room.Min.Z)) + 1);
   for (const auto& Anchor : Model->Anchors) { FOKStreetModelAnchor World = Anchor;World.Position = T.TransformPosition(Anchor.Position);World.Yaw = FRotator::NormalizeAxis(Anchor.Yaw + At.Yaw);P->Anchors.Add(World); }
   // Collision footprints (axis aligned after a quarter-turn yaw).
   for (const FBox& Box : Model->Boxes) {
    const FBox World = Box.TransformBy(T);
    FOKStreetPlacePart Part;Part.Center = World.GetCenter();Part.Size = World.GetSize();Part.Solid = true;Part.Hidden = true;P->Parts.Add(Part);
   }
  }
  OKStreetAppendPropertyLots(Out); // his company's vacant lots are places too (OKStreetSocialProperty.h data)
  return Out;
 }();
 return All;
}

inline const FOKStreetPlace* OKStreetFindPlace(const FString& Id) {
 for (const auto& P : OKStreetPlaces()) if (Id == P.Id) return &P;
 return nullptr;
}

// Extra route points for walking to places (never added to NPC routes): the gap east of the plaza, the
// east extension's walkway, and every door.
inline TArray<FVector> OKStreetPlaceRoutePoints() {
 TArray<FVector> Points = {FVector(3150, 50, 0), FVector(3150, -1550, 0), FVector(3150, 1650, 0), FVector(3800, -1700, 0), FVector(3800, 300, 0), FVector(3800, 1900, 0),
                           FVector(1750, -1700, 0), FVector(1750, 1750, 0), FVector(-1750, -1650, 0), FVector(-1750, 1300, 0),
                           // South extension: through the gaps beside the south block, then along the shop fronts.
                           FVector(-1750, -1340, 0), FVector(-2500, -1340, 0), FVector(-3400, -1340, 0), FVector(-1750, 990, 0), FVector(-2500, 990, 0), FVector(-3400, 990, 0),
                           FVector(-3450, -1800, 0), FVector(-3450, 0, 0), FVector(-3450, 1800, 0),
                           // Dorm walkway behind the shops, reached through the alleys between them.
                           FVector(-3450, -900, 0), FVector(-5040, -900, 0), FVector(-3450, 900, 0), FVector(-5040, 900, 0), FVector(-5040, -1700, 0), FVector(-5040, 1700, 0),
                           // West resort: past the restaurant terrace or the bookstore, then along y = -3300.
                           FVector(1650, -2400, 0), FVector(1650, -3300, 0), FVector(-1100, -1600, 0), FVector(-1100, -2400, 0), FVector(-1100, -3300, 0),
                           FVector(-2300, -3300, 0), FVector(-500, -3300, 0), FVector(1800, -3300, 0),
                           // East university town: past the snack shop or the lodge, then along y = 3300; the shrine
                           // is reached along the park's east edge (the fountain is in the middle).
                           FVector(1750, 3200, 0), FVector(-1750, 3200, 0), FVector(-5000, 3300, 0), FVector(-2300, 3300, 0), FVector(0, 3300, 0),
                           FVector(1550, 3300, 0), FVector(2300, 3300, 0), FVector(5000, 3300, 0), FVector(1550, 6000, 0),
                           // Aquarium behind the cafeteria (past its east side), the restrooms' approaches.
                           FVector(6100, 3300, 0), FVector(6100, 5600, 0), FVector(1550, 5600, 0), FVector(-3500, 3300, 0), FVector(500, -3300, 0),
                           // Department store behind the lecture hall: up the gap between the hall and the campus restroom.
                           FVector(-4000, 3300, 0), FVector(-4000, 5900, 0),
                           // Campus: in from the school side along y = -3200 or from the east along y = 3300, then the lanes
                           // south of each row of buildings and the gaps between them.
                           FVector(3800, -3200, 0), FVector(7400, -3200, 0), FVector(7400, 3300, 0),
                           FVector(7400, -5800, 0), FVector(7400, -2250, 0), FVector(7400, 1250, 0), FVector(7400, 4800, 0),
                           FVector(10300, -5800, 0), FVector(10300, -2250, 0), FVector(10300, 1250, 0), FVector(10300, 4800, 0),
                           FVector(13500, -5800, 0), FVector(13500, -2250, 0), FVector(13500, 1250, 0), FVector(13500, 4800, 0),
                           FVector(16200, -5800, 0), FVector(16200, -2250, 0), FVector(16200, 1250, 0), FVector(16200, 4800, 0),
                           // Administration building and the sports ground south-west of the classrooms.
                           FVector(7400, -7600, 0), FVector(7400, -9800, 0), FVector(10300, -9800, 0)};
 for (const auto& P : OKStreetPlaces()) Points.Add(P.Door);
 return Points;
}

// Ground for the north (school side) and south (shops) extensions, top at z=0 like the cooked ground.
inline TArray<FOKStreetPlacePart> OKStreetPlaceGround() {
 TArray<FOKStreetPlacePart> Out;
 if (OKStreetCityMode()) return Out; // the city's ground is in its map
 for (const float X : {4800.f, -4800.f}) {
  FOKStreetPlacePart G;G.Material = EOKStreetMaterial::Checker;G.Center = FVector(X, 0, -20);G.Size = FVector(3200, 5600, 40);Out.Add(G);
 }
 FOKStreetPlacePart West;West.Material = EOKStreetMaterial::Checker;West.Center = FVector(0, -4600, -20);West.Size = FVector(6400, 3600, 40);Out.Add(West);
 FOKStreetPlacePart East;East.Material = EOKStreetMaterial::Checker;East.Center = FVector(0, 5600, -20);East.Size = FVector(12800, 5600, 40);Out.Add(East);
 // The campus north of everything, with lawns between the rows of buildings (visual only).
 FOKStreetPlacePart Campus;Campus.Material = EOKStreetMaterial::Plaza;Campus.Center = FVector(11600, -500, -20);Campus.Size = FVector(10400, 12200, 40);Out.Add(Campus);
 FOKStreetPlacePart South;South.Material = EOKStreetMaterial::Plaza;South.Center = FVector(11300, -9900, -20);South.Size = FVector(9800, 6600, 40);Out.Add(South);
 for (const float X : {10300.f, 13500.f}) for (const float Y : {-4000.f, -500.f, 3000.f}) { FOKStreetPlacePart L;L.Material = EOKStreetMaterial::Leaf;L.Center = FVector(X, Y, 1);L.Size = FVector(900, 2000, 2);Out.Add(L); }
 return Out;
}

// Compass words for the model: +X north, +Y east.
inline FString OKStreetCompass(const FVector& From, const FVector& To) {
 const FVector D = To - From;
 if (D.Size2D() < 300) return OKT(TEXT("ui.compass.here"));
 const float Angle = FMath::RadiansToDegrees(FMath::Atan2(D.Y, D.X)); // 0 = north, 90 = east
 static const TCHAR* Keys[] = {TEXT("ui.compass.n"), TEXT("ui.compass.ne"), TEXT("ui.compass.e"), TEXT("ui.compass.se"), TEXT("ui.compass.s"), TEXT("ui.compass.sw"), TEXT("ui.compass.w"), TEXT("ui.compass.nw")};
 const int32 Index = FMath::RoundToInt(FMath::Fmod(Angle + 360.f, 360.f) / 45.f) % 8;
 return OKT(Keys[Index]);
}

// Stable catalogue for the system prompt (cacheable): places and what can be done there.
inline const FOKStreetModelAnchor* OKStreetNearestBed(const FVector& At, float Range, const FOKStreetModelAnchor* Except, const FOKStreetPlace** Where) {
 const FOKStreetModelAnchor* Best = nullptr;float BestDistance = Range;
 for (const auto& P : OKStreetPlaces()) for (const auto& A : P.Anchors) {
  if (&A == Except || !A.Name.StartsWith(TEXT("bed")) || FMath::Abs(A.Position.Z - At.Z) > 150.f) continue;
  const float Distance = FVector::Dist2D(A.Position, At);
  if (Distance < BestDistance) { BestDistance = Distance;Best = &A;if (Where) *Where = &P; }
 }
 return Best;
}

// The floor height under a point: the bottom of the place room it stands in, else the street (0).
inline float OKStreetFloorZ(const FVector& At) {
 for (const auto& P : OKStreetPlaces()) for (const FBox& Room : P.Rooms)
  if (At.X >= Room.Min.X && At.X <= Room.Max.X && At.Y >= Room.Min.Y && At.Y <= Room.Max.Y && At.Z >= Room.Min.Z - 60.f && At.Z < Room.Max.Z - 60.f) return OKStreetCityMode() ? Room.Min.Z + 30.f : Room.Min.Z; // the city's room boxes start 30 cm under the floor
 return OKStreetCityMode() ? float(At.Z) : 0.f; // the city's street is not flat: he stays where the ground has him
}

// The ground under a point, within a step up and a slope down. False: no ground there.
inline bool OKStreetGroundZ(const UWorld* World, const FVector& At, float& Z, const AActor* Ignore = nullptr) {
 FCollisionQueryParams Query(SCENE_QUERY_STAT(StreetGround), false, Ignore);
 FHitResult Hit;
 if (!World->LineTraceSingleByChannel(Hit, At + FVector(0, 0, 70), At - FVector(0, 0, 120), ECC_WorldStatic, Query)) return false;
 Z = float(Hit.ImpactPoint.Z);
 return true;
}
// His body in the sweeps: on the built street 7 cm over flat ground; in the city high enough to walk up a kerb or a stair.
inline float OKStreetBodyLift() { return OKStreetCityMode() ? 105.f : 85.f; }
inline float OKStreetBodyHalf() { return OKStreetCityMode() ? 60.f : 78.f; }
// Too far for the street grid (it searches at most 60000 cells): the city's road graph.
inline bool OKStreetCityFar(const FVector& From, const FVector& To) { return OKStreetCityMode() && FVector::Dist2D(From, To) > 4000.f; }

// Up a floor: a floor above the street. On the built street that is any height; the city's street itself is 12 m up.
inline bool OKStreetUpstairs(const FVector& At) {
 if (!OKStreetCityMode()) return At.Z > 100.f;
 for (const auto& P : OKStreetPlaces()) if (OKStreetPlaceFloor(P, At) > 1) return true;
 return false;
}

inline FString OKStreetPlaceCatalogueBuild();
// Made once per place set (city or street): every free-talk turn asked for it again, places times activities (2026-11-12).
inline FString OKStreetPlaceCatalogue() {
 static FString Cached; static int32 CachedKey = -1;
 const int32 Key = (OKStreetCityMode() ? 1 : 0) + 2 * OKStreetPlaces().Num();
 if (Key != CachedKey) { Cached = OKStreetPlaceCatalogueBuild(); CachedKey = Key; }
 return Cached;
}
inline FString OKStreetPlaceCatalogueBuild() {
 FString Out = TEXT("【街區地點】\n");
 for (const auto& P : OKStreetPlaces()) {
  Out += FString::Printf(TEXT("- %s（id: %s）：%s"), P.Name, P.Id, P.About);
  TArray<FString> Here;
  for (const auto& A : OKStreetActivities()) if (FCString::Strcmp(A.Place, P.Id) == 0) Here.Add(A.Name);
  if (!Here.IsEmpty()) Out += TEXT("。可以：") + FString::Join(Here, TEXT("、"));
  Out += TEXT("\n");
 }
 Out += TEXT("【可以一起做的活動】（id：名稱，地點）\n");
 for (const auto& A : OKStreetActivities()) {
  const FOKStreetPlace* P = OKStreetFindPlace(A.Place);
  Out += FString::Printf(TEXT("- %s：%s，%s\n"), A.Id, A.Name, P ? *FString::Printf(TEXT("在%s"), P->Name) : TEXT("就地進行"));
 }
 return Out;
}
