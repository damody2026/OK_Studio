// ok.VerifyEyeCamera: every outfit of every card of the reader's list, eyes following the camera (2026-11-03, the user:
// all heroines must look at the camera in the reader before the street gets it; 2026-11-04: every outfit, and how far off
// the look really is; the user: only the far left and far right). For each outfit: load it, turn on 眼睛看鏡頭, put the camera
// at her eyes from 35 degrees left and right; at each, a shot with the eyes following and one with them
// held straight ahead.
//   The look, from the pixels and not from the rates asked for: for two frames the iris texture is swapped for a white one,
// then for the same with a black dot at its middle; what differs between the two is the dot on screen (matching the iris
// itself fails, its rings repeat and its shading stays behind). Its shift is taken as a turn of a ball whose radius is OK_EYE_AUDIT_RADIUS times half the width of
// her eye as this view sees it (the iris layer's visible area, white against black; the far eye is narrower): an iris looking at the camera sits at the
// middle of the ball as the camera sees it. "err" is the angle left across between
// that look and the camera, per eye and view; the raw shifts are in result.json to judge again.
// Accessories and hair are hidden for those shots, or a strand over the dot would pull it aside. An eye nothing moves in as
// worn is covered: the outfit is "occluded" (cannot be judged as worn, not a pass) if her eyes are good under it, else
// "fail". A card that does not open: "load_failed".
//   Saved/Tests/EyeCamera/<run>/: result.json (written after each outfit), per outfit a strip (following above, straight
// below), per card a sheet (a row per outfit, red fail, yellow occluded).
//   -ExecCmds="ok.VerifyEyeCamera"   OK_EYE_AUDIT_FIRST / OK_EYE_AUDIT_COUNT: a range of cards; OK_EYE_AUDIT_OUTFITS: at most
// that many outfits; OK_EYE_AUDIT_MAX: the degrees allowed (12); OK_EYE_AUDIT_MODES=1: also try the eye button once;
// OK_EYE_AUDIT_EXIT=1 quits after.
#include "OKCharacterController.h"
#include "KKPreviewActor.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Components/PoseableMeshComponent.h"
#include "Components/TextBlock.h"
#include "Engine/Texture2D.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "UObject/StrongObjectPtr.h"
#include "ProceduralMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "GameFramework/PlayerController.h"
#include "ImageUtils.h"
#include "ShaderCompiler.h"
#include "UObject/UObjectIterator.h"
#include "Containers/Ticker.h"
#include "HAL/IConsoleManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

namespace OKEyeCameraAudit
{
static UOKCharacterController* Gallery()
{
    for(TObjectIterator<UOKCharacterController> It;It;++It)if(IsValid(*It)&&It->GetWorld())return *It;
    return nullptr;
}
constexpr int32 Views=2,TileW=230,TileH=128;
static const float Yaws[Views]={-35.f,35.f},Pitches[Views]={0.f,0.f};
struct FShot{TArray<FColor> Pixels;FIntPoint Size=FIntPoint::ZeroValue;FIntRect Eyes;float Rates[3]={};};
// One eye at one view: where it is, her facing as the camera sees it (x right, y up), the pixels to a centimetre.
struct FEye{FVector2D Screen=FVector2D::ZeroVector,Facing=FVector2D::ZeroVector,Shift=FVector2D::ZeroVector;float Scale=0;int32 Seen=0;int32 Dot=0;float Err=-1,Turned=0,OpenW=0,OpenH=0;};
struct FViewGeometry{FEye Eyes[2];float Span=0,SpanPixels=0,CamYaw=0,CamPitch=0;};
struct FState
{
    int32 Card=-1,Last=-1,Outfit=0,OutfitCount=1,MaxOutfits=MAX_int32,Step=0,View=0;double At=0,Wait=0;FString Dir,Modes;
    FShot Shots[Views][7];FViewGeometry Geo[Views];bool bShotPending=false,bModes=false,bCovered=false;FDelegateHandle Handle;float MaxErr=12,Radius=.84f;
    TArray<TSharedPtr<FJsonValue>> Results;int32 Passed=0,Failed=0,Occluded=0,LoadFailed=0;FString Mechanism;
    TArray<FColor> Sheet;int32 SheetRows=0;TArray<TWeakObjectPtr<UPrimitiveComponent>> Hidden;float ModeRates[2]={};
    TMap<TWeakObjectPtr<UMaterialInstanceDynamic>,TWeakObjectPtr<UTexture>> Marked;int32 Marks=0;
};
static TSharedPtr<FState> GState;
static FTSTicker::FDelegateHandle GTicker;
static TStrongObjectPtr<UTexture2D> GDot[3];
// Shots of a view: following, straight, and each with the white iris and with the dot.
enum{Following,Straight,FollowingDot,StraightDot,FollowingWhite,StraightWhite,StraightBlack};

static UTexture2D* DotTexture(int32 Kind)
{
    if(GDot[Kind])return GDot[Kind].Get();
    const int32 N=256;UTexture2D* T=UTexture2D::CreateTransient(N,N,PF_B8G8R8A8);T->SRGB=false;T->Filter=TF_Bilinear;T->AddressX=T->AddressY=TA_Clamp;
    FColor* Out=static_cast<FColor*>(T->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE));
    for(int32 Y=0;Y<N;++Y)for(int32 X=0;X<N;++X)Out[Y*N+X]=FVector2D(X-N/2+.5f,Y-N/2+.5f).Size()<N*.07f&&Kind==1||Kind==2?FColor(0,0,0,255):FColor(255,255,255,255);
    T->GetPlatformData()->Mips[0].BulkData.Unlock();T->UpdateResource();GDot[Kind].Reset(T);return T;
}
// The white iris (0), the dot (1), a black iris (2), or their own textures back (-1).
static void Mark(FState& S,AKKPreviewActor* A,int32 Kind)
{
    if(Kind<0){for(const auto& It:S.Marked)if(It.Key.IsValid())It.Key->SetTextureParameterValue(TEXT("_MainTex"),It.Value.Get());S.Marked.Reset();return;}
    UTexture2D* Dot=DotTexture(Kind);TInlineComponentArray<UMeshComponent*> Meshes(A);
    auto Swap=[&](UMaterialInstanceDynamic* M){UTexture* Was=nullptr;if(!M||!M->GetTextureParameterValue(FHashedMaterialParameterInfo(TEXT("_MainTex")),Was))return;if(!S.Marked.Contains(M))S.Marked.Add(M,Was);M->SetTextureParameterValue(TEXT("_MainTex"),Dot);};
    for(const auto& Part:A->Parts){if(A->Session.EyeMaterialSetting(Part.SessionIndex,-1)==0.f)continue;Swap(Part.GpuEyeMaterial);
        const FName Tags[]={*FString::Printf(TEXT("KKSessionPart_%d"),Part.SessionIndex),*FString::Printf(TEXT("KKMorphPart_%d"),Part.SessionIndex)};
        for(UMeshComponent* Drawn:Meshes)if(Drawn&&(Drawn->ComponentHasTag(Tags[0])||Drawn->ComponentHasTag(Tags[1])||Drawn==Part.Comp))for(int32 Slot=0;Slot<Drawn->GetNumMaterials();++Slot)Swap(Cast<UMaterialInstanceDynamic>(Drawn->GetMaterial(Slot)));}
    S.Marks=S.Marked.Num();
}

// Where her eyes are: the eye bones when the body has them, else in front of and above the head bone.
static bool EyePoints(AKKPreviewActor* A,FVector& L,FVector& R)
{
    UPoseableMeshComponent* Skel=A->BodySkel;if(!Skel)return false;
    const FName EL(TEXT("cf_J_Eye_t_L")),ER(TEXT("cf_J_Eye_t_R"));
    if(Skel->GetBoneIndex(EL)!=INDEX_NONE&&Skel->GetBoneIndex(ER)!=INDEX_NONE){L=Skel->GetSocketLocation(EL);R=Skel->GetSocketLocation(ER);return true;}
    const FName Head=Skel->GetBoneIndex(TEXT("cf_j_head"))!=INDEX_NONE?FName(TEXT("cf_j_head")):FName(TEXT("cf_s_head"));
    if(Skel->GetBoneIndex(Head)==INDEX_NONE)return false;
    const FVector H=Skel->GetSocketLocation(Head),Fwd=A->GetActorTransform().TransformVectorNoScale(FVector(0,1,0)),Side=A->GetActorTransform().TransformVectorNoScale(FVector(1,0,0));
    const FVector C=H+FVector(0,0,8)+Fwd*7;L=C+Side*3.2f;R=C-Side*3.2f;return true;
}
static void Place(AKKPreviewActor* A,float Yaw,float Pitch)
{
    FVector L,R;if(!EyePoints(A,L,R)||!A->StudioCam)return;
    const FVector F=A->GetActorTransform().TransformVectorNoScale(FVector(0,1,0));
    A->OrbitFocus=(L+R)*.5f;A->OrbitYaw=FMath::RadiansToDegrees(FMath::Atan2(F.X,F.Y))+Yaw;A->OrbitPitch=Pitch;A->OrbitDistance=90;
    if(UCameraComponent* C=A->StudioCam->GetCameraComponent())C->SetFieldOfView(22);
    A->ApplyOrbitCamera();
}
// Her eyes as this view's camera sees them.
static void Measure(AKKPreviewActor* A,FViewGeometry& G)
{
    APlayerController* PC=A->GetWorld()?A->GetWorld()->GetFirstPlayerController():nullptr;FVector P[2];
    if(!PC||!A->StudioCam||!EyePoints(A,P[0],P[1]))return;
    UCameraComponent* Camera=A->StudioCam->GetCameraComponent();
    const FRotator Rot=Camera->GetComponentRotation();const FVector Right=Rot.RotateVector(FVector::RightVector),Up=Rot.RotateVector(FVector::UpVector);
    const FVector Side=(P[1]-P[0]).GetSafeNormal(),Ahead=A->GetActorTransform().TransformVectorNoScale(FVector(0,1,0));
    const FVector Facing=(Ahead-Side*FVector::DotProduct(Ahead,Side)).GetSafeNormal();G.Span=FVector::Dist(P[0],P[1]);
    for(int32 I=0;I<2;++I){FEye& E=G.Eyes[I];FVector2D Beside;
        if(!PC->ProjectWorldLocationToScreen(P[I],E.Screen,true)||!PC->ProjectWorldLocationToScreen(P[I]+Right,Beside,true))continue;
        E.Scale=FVector2D::Distance(E.Screen,Beside);E.Facing=FVector2D(FVector::DotProduct(Facing,Right),FVector::DotProduct(Facing,Up));}
    G.SpanPixels=FVector2D::Distance(G.Eyes[0].Screen,G.Eyes[1].Screen);
    const FVector ToCam=(Camera->GetComponentLocation()-(P[0]+P[1])*.5f).GetSafeNormal();
    G.CamYaw=FMath::RadiansToDegrees(FMath::Atan2(FVector::DotProduct(ToCam,Side),FVector::DotProduct(ToCam,Facing)));G.CamPitch=FMath::RadiansToDegrees(FMath::Asin(FMath::Clamp(ToCam.Z,-1.,1.)));
}
static FIntRect EyeRect(const FViewGeometry& G,FIntPoint Size)
{
    const float Span=FMath::Max(G.SpanPixels,20.f);const FVector2D C=(G.Eyes[0].Screen+G.Eyes[1].Screen)*.5f;
    // The eye bones sit at the top of the eyes: the area reaches below them.
    FIntRect Rect(int32(C.X-Span*1.1f),int32(C.Y-Span*.2f),int32(C.X+Span*1.1f),int32(C.Y+Span*1.f));Rect.Clip(FIntRect(0,0,Size.X,Size.Y));return Rect;
}
static int32 Delta(const FColor& P,const FColor& Q){return FMath::Abs(int32(P.R)-Q.R)+FMath::Abs(int32(P.G)-Q.G)+FMath::Abs(int32(P.B)-Q.B);}
static float Diff(const FShot& F,const FShot& N)
{
    if(F.Size!=N.Size||F.Pixels.Num()!=F.Size.X*F.Size.Y||N.Pixels.Num()!=F.Pixels.Num())return -1;
    const FIntRect R=F.Eyes;double Sum=0;int64 Count=0;
    for(int32 Y=R.Min.Y;Y<R.Max.Y;++Y)for(int32 X=R.Min.X;X<R.Max.X;++X){Sum+=Delta(F.Pixels[Y*F.Size.X+X],N.Pixels[Y*F.Size.X+X]);Count+=3;}
    return Count?float(Sum/Count):-1;
}
// Around one eye (its half of the face, so the dot found is its own).
static FIntRect EyeArea(const FViewGeometry& G,const FEye& E,FIntPoint Size)
{
    const float Span=FMath::Max(G.SpanPixels,20.f),Middle=(G.Eyes[0].Screen.X+G.Eyes[1].Screen.X)*.5f;const bool Left=E.Screen.X<Middle;
    FIntRect R(int32(Left?E.Screen.X-Span*.75f:Middle),int32(E.Screen.Y-Span*.25f),int32(Left?Middle:E.Screen.X+Span*.75f),int32(E.Screen.Y+Span*.95f));R.Clip(FIntRect(0,0,Size.X,Size.Y));return R;
}
// How many pixels changed between the shots around this eye.
static int32 Changed(const FShot& F,const FShot& N,const FViewGeometry& G,const FEye& E)
{
    if(F.Size!=N.Size||F.Pixels.IsEmpty()||N.Pixels.Num()!=F.Pixels.Num())return 0;
    const FIntRect R=EyeArea(G,E,F.Size);int32 Count=0;
    for(int32 Y=R.Min.Y;Y<R.Max.Y;++Y)for(int32 X=R.Min.X;X<R.Max.X;++X)Count+=Delta(F.Pixels[Y*F.Size.X+X],N.Pixels[Y*F.Size.X+X])>36;
    return Count;
}
// The dot of one eye: what the dot changed on the white iris, nothing else differs between the shots.
static bool FindDot(const FShot& Dot,const FShot& White,const FViewGeometry& G,const FEye& E,FVector2D& Out,int32& Count)
{
    Count=0;if(Dot.Size!=White.Size||Dot.Pixels.IsEmpty()||White.Pixels.Num()!=Dot.Pixels.Num())return false;
    const FIntRect R=EyeArea(G,E,Dot.Size);FVector2D Sum=FVector2D::ZeroVector;
    for(int32 Y=R.Min.Y;Y<R.Max.Y;++Y)for(int32 X=R.Min.X;X<R.Max.X;++X)if(Delta(Dot.Pixels[Y*Dot.Size.X+X],White.Pixels[Y*Dot.Size.X+X])>90){Sum+=FVector2D(X,Y);++Count;}
    if(Count<6)return false;
    Out=Sum/Count;return true;
}
// How wide and high her eye is: where the iris layer shows at all.
static void FindOpening(const FShot& Black,const FShot& White,const FViewGeometry& G,FEye& E)
{
    if(Black.Size!=White.Size||Black.Pixels.IsEmpty()||White.Pixels.Num()!=Black.Pixels.Num())return;
    const FIntRect R=EyeArea(G,E,Black.Size);FIntPoint Lo(MAX_int32,MAX_int32),Hi(MIN_int32,MIN_int32);TArray<int32> Xs,Ys;
    for(int32 Y=R.Min.Y;Y<R.Max.Y;++Y)for(int32 X=R.Min.X;X<R.Max.X;++X)if(Delta(Black.Pixels[Y*Black.Size.X+X],White.Pixels[Y*Black.Size.X+X])>90){Xs.Add(X);Ys.Add(Y);}
    if(Xs.Num()<30)return;
    Xs.Sort();Ys.Sort();E.OpenW=Xs[Xs.Num()*98/100]-Xs[Xs.Num()*2/100];E.OpenH=Ys[Ys.Num()*98/100]-Ys[Ys.Num()*2/100];
}
// What is left across between the look and the camera, up and down not counted: her lid and highlights cut the dot and
// pull its middle down (2026-11-04, 11 cards failed so with their eyes on the camera). Straight ahead the iris sits Radius*Facing from the middle of the ball as
// the camera sees it; looking at the camera, at the middle.
static void Solve(const FState& S,float Open,FEye& E)
{
    const float Radius=S.Radius*Open*.5f;if(Radius<=0)return;
    const FVector2D Left=E.Facing+FVector2D(E.Shift.X,-E.Shift.Y)/Radius;
    E.Err=FMath::RadiansToDegrees(FMath::Asin(FMath::Min(FMath::Abs(Left.X),1.)));
    const FVector Look(Left.X,Left.Y,FMath::Sqrt(FMath::Max(0.,1.-Left.SizeSquared()))),Facing(E.Facing.X,E.Facing.Y,FMath::Sqrt(FMath::Max(0.,1.-E.Facing.SizeSquared())));
    E.Turned=FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(Look,Facing),-1.,1.)));
}
static void Copy(const FShot& Shot,const FIntRect& R,TArray<FColor>& Out,int32 OutW,int32 X0,int32 Y0,int32 W,int32 H)
{
    if(Shot.Pixels.IsEmpty()||R.Width()<=0||R.Height()<=0)return;
    for(int32 Y=0;Y<H;++Y)for(int32 X=0;X<W;++X){const int32 SX=R.Min.X+X*R.Width()/W,SY=R.Min.Y+Y*R.Height()/H;
        if(SX>=0&&SY>=0&&SX<Shot.Size.X&&SY<Shot.Size.Y)Out[(Y0+Y)*OutW+X0+X]=Shot.Pixels[SY*Shot.Size.X+SX];}
}
static void Save(const TArray<FColor>& Pixels,int32 W,int32 H,const FString& Path){TArray64<uint8> PNG;FImageUtils::PNGCompressImageArray(W,H,Pixels,PNG);FFileHelper::SaveArrayToFile(PNG,*Path);}
// One strip per outfit: the eye area of each shot, the views across; following, straight, then both with the dot.
static void SaveStrip(const FState& S,const FString& Path)
{
    const int32 W=300,H=167;TArray<FColor> Out;Out.Init(FColor::Black,W*Views*H*4);
    for(int32 V=0;V<Views;++V)for(int32 K=0;K<4;++K)Copy(S.Shots[V][K],S.Shots[V][0].Eyes,Out,W*Views,V*W,K*H,W,H);
    Save(Out,W*Views,H*4,Path);
}
// One sheet per card, to look through by eye: a row per outfit, following only.
static void AddSheetRow(FState& S,FColor Mark)
{
    const int32 W=TileW*Views+8;S.Sheet.AddDefaulted(W*(TileH+2));const int32 Y0=S.SheetRows++*(TileH+2);
    for(int32 Y=0;Y<TileH+2;++Y)for(int32 X=0;X<W;++X)S.Sheet[(Y0+Y)*W+X]=X<8?Mark:FColor::Black;
    for(int32 V=0;V<Views;++V)Copy(S.Shots[V][0],S.Shots[V][0].Eyes,S.Sheet,W,8+V*TileW,Y0,TileW-2,TileH);
}
static void FlushSheet(FState& S,const FString& Name)
{
    if(!S.SheetRows)return;Save(S.Sheet,TileW*Views+8,S.SheetRows*(TileH+2),S.Dir/FString::Printf(TEXT("sheet_%03d_%s.png"),S.Card,*Name));S.Sheet.Reset();S.SheetRows=0;
}
static void WriteResult(const FState& S)
{
    auto Root=MakeShared<FJsonObject>();Root->SetNumberField(TEXT("passed"),S.Passed);Root->SetNumberField(TEXT("failed"),S.Failed);Root->SetNumberField(TEXT("occluded"),S.Occluded);Root->SetNumberField(TEXT("load_failed"),S.LoadFailed);
    Root->SetNumberField(TEXT("max_err"),S.MaxErr);Root->SetNumberField(TEXT("radius"),S.Radius);if(!S.Modes.IsEmpty())Root->SetStringField(TEXT("eye_button"),S.Modes);Root->SetArrayField(TEXT("outfits"),S.Results);
    FString Text;auto W=TJsonWriterFactory<>::Create(&Text);FJsonSerializer::Serialize(Root,W);FFileHelper::SaveStringToFile(Text,*(S.Dir/TEXT("result.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}
static void Finish(FState& S)
{
    WriteResult(S);UE_LOG(LogTemp,Display,TEXT("Eye camera audit done: passed=%d failed=%d occluded=%d load_failed=%d dir=%s"),S.Passed,S.Failed,S.Occluded,S.LoadFailed,*S.Dir);
    if(FPlatformMisc::GetEnvironmentVariable(TEXT("OK_EYE_AUDIT_EXIT"))==TEXT("1"))FPlatformMisc::RequestExit(false);
}
static void Record(FState& S,UOKCharacterController* G,const TCHAR* Status,const TCHAR* Error)
{
    const FString Text=Status;++(Text==TEXT("load_failed")?S.LoadFailed:S.Failed);
    auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),S.Card);O->SetStringField(TEXT("card"),G->Entries.IsValidIndex(S.Card)?FPaths::GetBaseFilename(G->Entries[S.Card].Path):FString(TEXT("?")));O->SetNumberField(TEXT("outfit"),S.Outfit);
    O->SetStringField(TEXT("status"),Text);O->SetStringField(TEXT("error"),Error);S.Results.Add(MakeShared<FJsonValueObject>(O));WriteResult(S);
    UE_LOG(LogTemp,Error,TEXT("Eye camera audit card=%d outfit=%d %s: %s"),S.Card,S.Outfit,*Text,Error);
}
// Accessories and hair out of the way of her eyes for a shot with the dot.
static void HideOver(FState& S,AKKPreviewActor* A)
{
    TInlineComponentArray<UPrimitiveComponent*> Prims(A);
    auto Hide=[&](UPrimitiveComponent* P){if(P->IsVisible()){P->SetVisibility(false,true);S.Hidden.Add(P);}};
    for(const auto& Part:A->Parts)if(Part.Role.StartsWith(TEXT("acc"))||Part.Role.Contains(TEXT("hair"))){
        const FName Tag(*FString::Printf(TEXT("KKSessionPart_%d"),Part.SessionIndex));
        for(UPrimitiveComponent* P:Prims)if(P->ComponentHasTag(Tag))Hide(P);
        if(Part.Comp)Hide(Part.Comp);}
}
static void ShowOver(FState& S){for(const auto& P:S.Hidden)if(P.IsValid())P->SetVisibility(true,true);S.Hidden.Reset();}
static void Judge(FState& S,UOKCharacterController* G,AKKPreviewActor* A)
{
    const FString Name=FPaths::GetBaseFilename(G->Entries[S.Card].Path);float Worst=0;bool Unseen=false;
    for(int32 V=0;V<Views;++V)for(FEye& E:S.Geo[V].Eyes){FindOpening(S.Shots[V][StraightBlack],S.Shots[V][StraightWhite],S.Geo[V],E);const auto& Shots=S.Shots[V];E.Seen=Changed(Shots[Following],Shots[Straight],S.Geo[V],E);
        FVector2D To,From;int32 DotTo=0,DotFrom=0;const bool Found=FindDot(Shots[FollowingDot],Shots[FollowingWhite],S.Geo[V],E,To,DotTo)&&FindDot(Shots[StraightDot],Shots[StraightWhite],S.Geo[V],E,From,DotFrom);
        E.Dot=FMath::Min(DotTo,DotFrom);E.Err=-1;E.Shift=FVector2D::ZeroVector;if(Found){E.Shift=To-From;Solve(S,E.OpenW,E);}
        Unseen|=!Found;Worst=FMath::Max(Worst,E.Err);S.bCovered|=E.Seen<30;}
    const float* RL=S.Shots[0][0].Rates;const float* RR=S.Shots[1][0].Rates;
    // Both eyes to the same side at each view, the two views opposite.
    const bool Together=RL[0]*RL[1]>0&&RR[0]*RR[1]>0,Opposite=RL[0]*RR[0]<0&&FMath::Abs(RL[0])>.15f&&FMath::Abs(RR[0])>.15f;
    const float DL=Diff(S.Shots[0][0],S.Shots[0][1]),DR=Diff(S.Shots[1][0],S.Shots[1][1]);
    // An iris mesh hidden is an eye drawn white whatever moved.
    const bool Shown=S.Mechanism.EndsWith(TEXT("hidden=0")),Good=!Unseen&&Together&&Opposite&&Shown&&Worst<=S.MaxErr;
    const TCHAR* Status=Good?(S.bCovered?TEXT("occluded"):TEXT("pass")):TEXT("fail");
    ++(Good?(S.bCovered?S.Occluded:S.Passed):S.Failed);
    auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),S.Card);O->SetStringField(TEXT("card"),Name);O->SetNumberField(TEXT("outfit"),S.Outfit);O->SetStringField(TEXT("status"),Status);
    O->SetNumberField(TEXT("worst_err"),Worst);O->SetBoolField(TEXT("covered"),S.bCovered);O->SetNumberField(TEXT("marks"),S.Marks);O->SetBoolField(TEXT("unseen"),Unseen);O->SetBoolField(TEXT("together"),Together);O->SetBoolField(TEXT("opposite"),Opposite);
    O->SetNumberField(TEXT("diff_left"),DL);O->SetNumberField(TEXT("diff_right"),DR);O->SetStringField(TEXT("mechanism"),S.Mechanism);
    TArray<TSharedPtr<FJsonValue>> List;
    for(int32 V=0;V<Views;++V){const FViewGeometry& Geo=S.Geo[V];const float* R=S.Shots[V][0].Rates;auto J=MakeShared<FJsonObject>();
        J->SetNumberField(TEXT("cam_yaw"),Geo.CamYaw);J->SetNumberField(TEXT("cam_pitch"),Geo.CamPitch);J->SetNumberField(TEXT("span"),Geo.Span);J->SetStringField(TEXT("rates"),FString::Printf(TEXT("%.3f,%.3f,%.3f"),R[0],R[1],R[2]));
        TArray<TSharedPtr<FJsonValue>> Eyes;for(const FEye& E:Geo.Eyes){auto Q=MakeShared<FJsonObject>();Q->SetNumberField(TEXT("err"),E.Err);Q->SetNumberField(TEXT("turned"),E.Turned);Q->SetNumberField(TEXT("seen"),E.Seen);Q->SetNumberField(TEXT("dot"),E.Dot);Q->SetNumberField(TEXT("open_w"),E.OpenW);Q->SetNumberField(TEXT("open_h"),E.OpenH);
            Q->SetNumberField(TEXT("dx"),E.Shift.X);Q->SetNumberField(TEXT("dy"),E.Shift.Y);Q->SetNumberField(TEXT("scale"),E.Scale);Q->SetNumberField(TEXT("fx"),E.Facing.X);Q->SetNumberField(TEXT("fy"),E.Facing.Y);Eyes.Add(MakeShared<FJsonValueObject>(Q));}
        J->SetArrayField(TEXT("eyes"),Eyes);List.Add(MakeShared<FJsonValueObject>(J));}
    {FString Iris;for(const auto& Part:A->Parts){if(A->Session.EyeMaterialSetting(Part.SessionIndex,-1)==0.f)continue;Iris+=TEXT("[");for(int32 I=0;I<14;++I)Iris+=FString::Printf(TEXT("%.4f "),A->Session.EyeMaterialSetting(Part.SessionIndex,I));
        FVector2D Lo(1e9,1e9),Hi(-1e9,-1e9);for(const auto& UV:Part.UVs){Lo=FVector2D::Min(Lo,UV);Hi=FVector2D::Max(Hi,UV);}Iris+=FString::Printf(TEXT("uv %.3f %.3f %.3f %.3f]"),Lo.X,Lo.Y,Hi.X,Hi.Y);}
     O->SetStringField(TEXT("iris"),Iris);}
    O->SetArrayField(TEXT("views"),List);S.Results.Add(MakeShared<FJsonValueObject>(O));
    SaveStrip(S,S.Dir/FString::Printf(TEXT("%03d_%s_o%d.png"),S.Card,*Name,S.Outfit));
    AddSheetRow(S,Good?(S.bCovered?FColor::Yellow:FColor(0,160,0)):FColor::Red);WriteResult(S);
    UE_LOG(LogTemp,Display,TEXT("Eye camera audit card=%d %s outfit=%d %s worst=%.1f covered=%d unseen=%d together=%d opposite=%d cam=(%.0f,%.0f) via=%s"),
        S.Card,*Name,S.Outfit,Status,Worst,S.bCovered,Unseen,Together,Opposite,S.Geo[0].CamYaw,S.Geo[1].CamYaw,*S.Mechanism);
}
// How her eyes are drawn: procedural parts (mesh UVs), GPU eyes with gaze rows, or the iris tiling only.
static FString Mechanism(AKKPreviewActor* A)
{
    int32 Proc=0,Rows=0,Tiling=0,Hidden=0;
    for(const auto& Part:A->Parts){if(A->Session.EyeMaterialSetting(Part.SessionIndex,-1)==0.f)continue;if(Part.Comp)++Proc;if(Part.GpuEyeMaterial)++(Part.GpuEyeUV[0].IsEmpty()?Tiling:Rows);
        if(Part.Comp&&Part.Comp->GetNumSections()&&!Part.Comp->IsVisible())++Hidden;}
    return FString::Printf(TEXT("proc=%d rows=%d other=%d hidden=%d"),Proc,Rows,Tiling,Hidden);
}
static FVector2D ViewportSize(){FVector2D Size(1280,720);if(GEngine->GameViewport)GEngine->GameViewport->GetViewportSize(Size);return Size;}
static bool Tick(float)
{
    if(!GState)return false;FState& S=*GState;UOKCharacterController* G=Gallery();const double Now=FPlatformTime::Seconds();
    if(!G||G->Entries.IsEmpty()){if(Now-S.At>120){UE_LOG(LogTemp,Error,TEXT("Eye camera audit: no reader cards"));GState.Reset();return false;}return true;}
    if(S.bShotPending||Now<S.Wait)return true;
    AKKPreviewActor* A=G->PreviewActor.Get();
    switch(S.Step)
    {
    case 0:{ // next outfit, or next card
        if(G->bLoadInFlight||G->bAppearanceBusy){S.Wait=Now+.5;return true;}
        S.bCovered=false;S.At=Now;S.Step=1;S.Wait=Now+1;
        if(S.Card>=0&&S.Outfit+1<S.OutfitCount){++S.Outfit;G->OnOutfitNext();return true;}
        if(G->Entries.IsValidIndex(S.Card))FlushSheet(S,FPaths::GetBaseFilename(G->Entries[S.Card].Path));
        ++S.Card;S.Outfit=0;if(S.Card>S.Last||!G->Entries.IsValidIndex(S.Card)){Finish(S);GState.Reset();return false;}
        G->SelectIndex(S.Card);if(G->SelectedIndex!=S.Card){S.OutfitCount=1;Record(S,G,TEXT("load_failed"),TEXT("the card does not read"));S.Step=0;return true;}
        S.OutfitCount=FMath::Min(FMath::Max(G->Selected.Outfits.Num(),1),S.MaxOutfits);G->OutfitIndex=0;G->RefreshOutfitList();G->OnLoad3D();return true;}
    case 1:{ // loaded and compiled
        const bool Same=A&&A->Session.IsOpen()&&!G->bLoadInFlight&&G->PreviewCardPath==G->Entries[S.Card].Path&&G->PreviewOutfitIndex==S.Outfit;
        const bool Ready=Same&&!(GShaderCompilingManager&&GShaderCompilingManager->IsCompiling());
        if(!Ready){
            // Nothing loading and not hers: it did not open.
            if(!Same&&!G->bLoadInFlight&&Now-S.At>8){Record(S,G,TEXT("load_failed"),TEXT("the load ended without her"));S.Step=0;return true;}
            if(Now-S.At>240){Record(S,G,TEXT("load_failed"),TEXT("load timeout"));S.Step=0;return true;}
            S.Wait=Now+.5;return true;}
        if(A->Session.EyeLookPatternCount()<=0){Record(S,G,TEXT("fail"),TEXT("no eye look pattern"));S.Step=0;return true;}
        // Eyes open and still apart from the look: no blinking.
        A->FaceBlink.FixedFlags=1;A->BlinkEyeRate=1.f;A->BlinkBrowRate=1.f;A->ApplyMouth();
        G->OnEyeLookCamera(true);S.Mechanism=Mechanism(A);S.View=0;S.Step=2;S.Wait=Now+1.5;
        for(auto& V:S.Shots)for(auto& K:V)K=FShot();return true;}
    case 2: // camera to this view, following
        A->FaceBlink.FixedFlags=1;A->BlinkEyeRate=1.f;
        Place(A,Yaws[S.View],Pitches[S.View]);G->OnEyeLookCamera(true);S.Step=3;S.Wait=Now+1.4;return true;
    case 3: case 5: case 31: case 34: case 36: case 38: case 41:{ // shot
        const int32 K=S.Step==3?Following:S.Step==5?Straight:S.Step==31?FollowingDot:S.Step==34?StraightDot:S.Step==36?FollowingWhite:S.Step==38?StraightWhite:StraightBlack;FShot& Shot=S.Shots[S.View][K];
        Shot.Rates[0]=A->EyeGaze[0];Shot.Rates[1]=A->EyeGaze[1];Shot.Rates[2]=A->EyeGaze[2];
        if(FScreenshotRequest::IsScreenshotRequested()){S.Wait=Now+.2;return true;}
        if(K==Following)Measure(A,S.Geo[S.View]);
        TWeakPtr<FState> Weak=GState;const int32 View=S.View;
        S.Handle=UGameViewportClient::OnScreenshotCaptured().AddLambda([Weak,View,K](int32 W,int32 H,const TArray<FColor>& Data){
            if(auto P=Weak.Pin()){FShot& Out=P->Shots[View][K];Out.Size=FIntPoint(W,H);Out.Pixels=Data;Out.Eyes=K==Following?EyeRect(P->Geo[View],Out.Size):P->Shots[View][Following].Eyes;
                UGameViewportClient::OnScreenshotCaptured().Remove(P->Handle);P->bShotPending=false;}});
        S.bShotPending=true;FScreenshotRequest::RequestScreenshot(S.Dir/TEXT("capture.png"),false,false,false);
        S.Step=S.Step==3?30:S.Step==36?37:S.Step==31?4:S.Step==5?33:S.Step==38?39:S.Step==34?40:35;return true;}
    case 30: case 33: // the white iris, nothing over it
        Mark(S,A,0);HideOver(S,A);S.Step=S.Step==30?36:38;S.Wait=Now+.15;return true;
    case 40: // black, for where it shows
        Mark(S,A,2);S.Step=41;S.Wait=Now+.1;return true;
    case 37: case 39: // the dot on it
        Mark(S,A,1);S.Step=S.Step==37?31:34;S.Wait=Now+.1;return true;
    case 4: // the same view, eyes held straight
        Mark(S,A,-1);ShowOver(S);A->StopEyeLookTracking();A->SetEyeGaze(0,0,0);S.Step=5;S.Wait=Now+.5;return true;
    case 35:
        Mark(S,A,-1);ShowOver(S);S.Step=6;S.Wait=Now+.1;return true;
    case 6:
        if(++S.View<Views){S.Step=2;return true;}
        Judge(S,G,A);S.Step=S.bModes?10:0;return true;
    // The eye button, once: ahead -> the mouse (held at each side of the screen) -> the camera -> ahead.
    case 10:{S.bModes=false;Place(A,0,0);const FVector2D Size=ViewportSize();G->SetEyeMode(0);G->EyeMousePixel=FVector2D(Size.X*.05f,Size.Y*.45f);G->OnEyeModeNext();S.Step=11;S.Wait=Now+2;return true;}
    case 11:{const FVector2D Size=ViewportSize();S.ModeRates[0]=A->EyeGaze[0];G->EyeMousePixel=FVector2D(Size.X*.95f,Size.Y*.45f);S.Step=12;S.Wait=Now+2;return true;}
    case 12:S.ModeRates[1]=A->EyeGaze[0];G->EyeMousePixel=FVector2D(-1,-1);G->OnEyeModeNext();S.Step=13;S.Wait=Now+1;return true;
    case 13:{const bool Camera=A->bEyeLookFollowCamera&&G->EyeMode==2;G->OnEyeModeNext();
        S.Modes=FString::Printf(TEXT("mouse left=%.3f right=%.3f camera=%d"),S.ModeRates[0],S.ModeRates[1],Camera);S.Step=14;S.Wait=Now+1;return true;}
    case 14:{const bool Ahead=!A->bEyeLookTracking&&A->EyeGaze[0]==0.f&&A->EyeGaze[2]==0.f&&G->EyeMode==0;S.Modes+=FString::Printf(TEXT(" ahead=%d label=%s"),Ahead,G->EyeModeLabel?*G->EyeModeLabel->GetText().ToString():TEXT("-"));
        UE_LOG(LogTemp,Display,TEXT("Eye button test: %s"),*S.Modes);FScreenshotRequest::RequestScreenshot(S.Dir/TEXT("eye_button_ui.png"),true,false,false);S.Step=0;S.Wait=Now+1;return true;}
    }
    return true;
}
static void Start(const TArray<FString>& Args)
{
    if(GState){UE_LOG(LogTemp,Warning,TEXT("Eye camera audit already running"));return;}
    GState=MakeShared<FState>();FState& S=*GState;S.At=FPlatformTime::Seconds();
    auto Env=[](const TCHAR* Name){return FPlatformMisc::GetEnvironmentVariable(Name);};
    const FString First=Env(TEXT("OK_EYE_AUDIT_FIRST")),Count=Env(TEXT("OK_EYE_AUDIT_COUNT")),Outfits=Env(TEXT("OK_EYE_AUDIT_OUTFITS")),Max=Env(TEXT("OK_EYE_AUDIT_MAX")),Radius=Env(TEXT("OK_EYE_AUDIT_RADIUS"));
    S.Card=(First.IsEmpty()?0:FCString::Atoi(*First))-1;S.Last=Count.IsEmpty()?MAX_int32:S.Card+FCString::Atoi(*Count);
    if(Args.Num()>=1)S.Card=FCString::Atoi(*Args[0])-1;
    if(Args.Num()>=2)S.Last=S.Card+FCString::Atoi(*Args[1]);
    if(!Outfits.IsEmpty())S.MaxOutfits=FMath::Max(1,FCString::Atoi(*Outfits));
    if(!Max.IsEmpty())S.MaxErr=FCString::Atof(*Max);
    if(!Radius.IsEmpty())S.Radius=FCString::Atof(*Radius);
    S.bModes=Env(TEXT("OK_EYE_AUDIT_MODES"))==TEXT("1");
    S.Dir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("Tests/EyeCamera")/FDateTime::Now().ToString(TEXT("%Y%m%d-%H%M%S")));
    IFileManager::Get().MakeDirectory(*S.Dir,true);
    UE_LOG(LogTemp,Display,TEXT("Eye camera audit start first=%d dir=%s"),S.Card+1,*S.Dir);
    GTicker=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&Tick),.1f);
}
static FAutoConsoleCommand Command(TEXT("ok.VerifyEyeCamera"),TEXT("Each outfit of each reader card: eyes follow the camera from left, front, right, above and below (args: first count)"),FConsoleCommandWithArgsDelegate::CreateStatic(&Start));
}
