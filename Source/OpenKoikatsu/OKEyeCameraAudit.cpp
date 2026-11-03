// ok.VerifyEyeCamera: every card of the reader's list, eyes following the camera (2026-11-03, the user: all heroines
// must look at the camera in the reader before the street gets it). For each card: load it, turn on 眼睛看鏡頭, put the
// camera at her eyes from 35 degrees left, the front and 35 degrees right; at each, a shot with the eyes following and one
// with them held straight ahead. Her eyes pass when, from both sides, the following shot differs from the straight one
// around the eyes (the iris moved on screen) and both eyes turned to that side (the rates agree in sign, and the two
// sides are opposite). Shots per card in Saved/Tests/EyeCamera/<run>/ (a strip: left, front, right; following above,
// straight below), results in result.json and the log ("Eye camera audit").
//   -ExecCmds="ok.VerifyEyeCamera"   OK_EYE_AUDIT_FIRST / OK_EYE_AUDIT_COUNT: a range of the list; OK_EYE_AUDIT_EXIT=1 quits after.
#include "OKCharacterController.h"
#include "KKPreviewActor.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Components/PoseableMeshComponent.h"
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
struct FShot{TArray<FColor> Pixels;FIntPoint Size=FIntPoint::ZeroValue;FIntRect Eyes;float Rates[3]={};};
struct FState
{
    int32 Card=-1,Last=-1,Step=0,View=0;double At=0,Wait=0;FString Dir;
    FShot Shots[3][2];bool bShotPending=false;FDelegateHandle Handle;float FrontYaw=0;
    TArray<TSharedPtr<FJsonValue>> Results;int32 Passed=0,Failed=0;FString Mechanism;
};
static TSharedPtr<FState> GState;
static FTSTicker::FDelegateHandle GTicker;
static const float Yaws[3]={-35.f,0.f,35.f};

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
static void Place(AKKPreviewActor* A,float Yaw)
{
    FVector L,R;if(!EyePoints(A,L,R)||!A->StudioCam)return;
    const FVector F=A->GetActorTransform().TransformVectorNoScale(FVector(0,1,0));
    A->OrbitFocus=(L+R)*.5f;A->OrbitYaw=FMath::RadiansToDegrees(FMath::Atan2(F.X,F.Y))+Yaw;A->OrbitPitch=0;A->OrbitDistance=90;
    if(UCameraComponent* C=A->StudioCam->GetCameraComponent())C->SetFieldOfView(22);
    A->ApplyOrbitCamera();
}
static FIntRect EyeRect(AKKPreviewActor* A,FIntPoint Size)
{
    APlayerController* PC=A->GetWorld()?A->GetWorld()->GetFirstPlayerController():nullptr;FVector L,R;FVector2D SL,SR;
    if(!PC||!EyePoints(A,L,R)||!PC->ProjectWorldLocationToScreen(L,SL,true)||!PC->ProjectWorldLocationToScreen(R,SR,true))
        return FIntRect(Size.X*3/8,Size.Y*2/5,Size.X*5/8,Size.Y*3/5);
    const float Span=FMath::Max(FVector2D::Distance(SL,SR),20.f);const FVector2D C=(SL+SR)*.5f;
    // The eye bones sit at the top of the eyes: the area reaches below them.
    FIntRect Rect(int32(C.X-Span*1.1f),int32(C.Y-Span*.2f),int32(C.X+Span*1.1f),int32(C.Y+Span*1.f));Rect.Clip(FIntRect(0,0,Size.X,Size.Y));return Rect;
}
static float Diff(const FShot& F,const FShot& N)
{
    if(F.Size!=N.Size||F.Pixels.Num()!=F.Size.X*F.Size.Y||N.Pixels.Num()!=F.Pixels.Num())return -1;
    const FIntRect R=F.Eyes;double Sum=0;int64 Count=0;
    for(int32 Y=R.Min.Y;Y<R.Max.Y;++Y)for(int32 X=R.Min.X;X<R.Max.X;++X){const FColor& P=F.Pixels[Y*F.Size.X+X];const FColor& Q=N.Pixels[Y*F.Size.X+X];
        Sum+=FMath::Abs(int32(P.R)-Q.R)+FMath::Abs(int32(P.G)-Q.G)+FMath::Abs(int32(P.B)-Q.B);Count+=3;}
    return Count?float(Sum/Count):-1;
}
// One strip per card: the eye area of each shot, 3 views across, following above and straight below.
static void SaveStrip(const FState& S,const FString& Path)
{
    const int32 W=360,H=200;TArray<FColor> Out;Out.Init(FColor::Black,W*3*H*2);
    for(int32 V=0;V<3;++V)for(int32 K=0;K<2;++K){const FShot& Shot=S.Shots[V][K];if(Shot.Pixels.IsEmpty())continue;const FIntRect R=S.Shots[V][0].Eyes;
        for(int32 Y=0;Y<H;++Y)for(int32 X=0;X<W;++X){const int32 SX=R.Min.X+X*R.Width()/W,SY=R.Min.Y+Y*R.Height()/H;
            if(SX>=0&&SY>=0&&SX<Shot.Size.X&&SY<Shot.Size.Y)Out[(K*H+Y)*W*3+V*W+X]=Shot.Pixels[SY*Shot.Size.X+SX];}}
    TArray64<uint8> PNG;FImageUtils::PNGCompressImageArray(W*3,H*2,Out,PNG);FFileHelper::SaveArrayToFile(PNG,*Path);
}
static void Finish(FState& S)
{
    auto Root=MakeShared<FJsonObject>();Root->SetNumberField(TEXT("passed"),S.Passed);Root->SetNumberField(TEXT("failed"),S.Failed);Root->SetArrayField(TEXT("cards"),S.Results);
    FString Text;auto W=TJsonWriterFactory<>::Create(&Text);FJsonSerializer::Serialize(Root,W);FFileHelper::SaveStringToFile(Text,*(S.Dir/TEXT("result.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
    UE_LOG(LogTemp,Display,TEXT("Eye camera audit done: passed=%d failed=%d dir=%s"),S.Passed,S.Failed,*S.Dir);
    if(FPlatformMisc::GetEnvironmentVariable(TEXT("OK_EYE_AUDIT_EXIT"))==TEXT("1"))FPlatformMisc::RequestExit(false);
}
static void Judge(FState& S,UOKCharacterController* G,AKKPreviewActor* A)
{
    const FString Name=FPaths::GetBaseFilename(G->Entries[S.Card].Path);
    const float DL=Diff(S.Shots[0][0],S.Shots[0][1]),DR=Diff(S.Shots[2][0],S.Shots[2][1]);
    const float* RL=S.Shots[0][0].Rates;const float* RR=S.Shots[2][0].Rates;
    // Both eyes to the same side at each view, the two views opposite, and the iris seen to move from both sides.
    const bool Together=RL[0]*RL[1]>0&&RR[0]*RR[1]>0,Opposite=RL[0]*RR[0]<0&&FMath::Abs(RL[0])>.15f&&FMath::Abs(RR[0])>.15f;
    const bool Moved=DL>1.5f&&DR>1.5f;// An iris mesh hidden is an eye drawn white whatever moved.
    const bool Shown=!S.Mechanism.Contains(TEXT("hidden=")) || S.Mechanism.EndsWith(TEXT("hidden=0"));const bool Pass=Together&&Opposite&&Moved&&Shown;
    (Pass?S.Passed:S.Failed)++;
    auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),S.Card);O->SetStringField(TEXT("card"),Name);O->SetBoolField(TEXT("pass"),Pass);
    O->SetNumberField(TEXT("diff_left"),DL);O->SetNumberField(TEXT("diff_right"),DR);O->SetBoolField(TEXT("together"),Together);O->SetBoolField(TEXT("opposite"),Opposite);
    O->SetStringField(TEXT("rates_left"),FString::Printf(TEXT("%.3f,%.3f,%.3f"),RL[0],RL[1],RL[2]));O->SetStringField(TEXT("rates_right"),FString::Printf(TEXT("%.3f,%.3f,%.3f"),RR[0],RR[1],RR[2]));
    O->SetStringField(TEXT("mechanism"),S.Mechanism);S.Results.Add(MakeShared<FJsonValueObject>(O));
    SaveStrip(S,S.Dir/FString::Printf(TEXT("%03d_%s.png"),S.Card,*Name));
    UE_LOG(LogTemp,Display,TEXT("Eye camera audit card=%d %s %s diff=(%.2f,%.2f) rates_left=(%.2f,%.2f) rates_right=(%.2f,%.2f) together=%d opposite=%d via=%s"),
        S.Card,*Name,Pass?TEXT("PASS"):TEXT("FAIL"),DL,DR,RL[0],RL[1],RR[0],RR[1],Together,Opposite,*S.Mechanism);
}
// How her eyes are drawn: procedural parts (mesh UVs), GPU eyes with gaze rows, or the iris tiling only.
static FString Mechanism(AKKPreviewActor* A)
{
    int32 Proc=0,Rows=0,Tiling=0,Hidden=0;
    for(const auto& Part:A->Parts){if(A->Session.EyeMaterialSetting(Part.SessionIndex,-1)==0.f)continue;if(Part.Comp)++Proc;if(Part.GpuEyeMaterial)++(Part.GpuEyeUV[0].IsEmpty()?Tiling:Rows);
        // Each iris drawn as a CPU mesh: where it is, its UV range and whether it shows (an iris gone white).
        if(Part.Comp&&Part.Comp->GetNumSections()&&!Part.Comp->IsVisible())++Hidden;
        if(Part.Comp){FVector2D Lo(1e9,1e9),Hi(-1e9,-1e9);for(const auto& UV:Part.UVs){Lo=FVector2D::Min(Lo,UV);Hi=FVector2D::Max(Hi,UV);}
            UE_LOG(LogTemp,Display,TEXT("Eye camera audit iris part=%d comp=%s parent=%s hidden=%d visible=%d sections=%d bounds=%s uv=(%.3f,%.3f)-(%.3f,%.3f) sort=%d material=%s"),Part.SessionIndex,*Part.Comp->GetName(),Part.Comp->GetAttachParent()?*Part.Comp->GetAttachParent()->GetName():TEXT("-"),Part.Comp->bHiddenInGame,Part.Comp->IsVisible(),Part.Comp->GetNumSections(),
                *Part.Comp->Bounds.Origin.ToString(),Lo.X,Lo.Y,Hi.X,Hi.Y,Part.Comp->TranslucencySortPriority,Part.Comp->GetMaterial(0)?*Part.Comp->GetMaterial(0)->GetName():TEXT("-"));}}
    return FString::Printf(TEXT("proc=%d rows=%d other=%d hidden=%d"),Proc,Rows,Tiling,Hidden);
}
static bool Tick(float)
{
    if(!GState)return false;FState& S=*GState;UOKCharacterController* G=Gallery();const double Now=FPlatformTime::Seconds();
    if(!G||G->Entries.IsEmpty()){if(Now-S.At>120){UE_LOG(LogTemp,Error,TEXT("Eye camera audit: no reader cards"));GState.Reset();return false;}return true;}
    if(S.bShotPending||Now<S.Wait)return true;
    AKKPreviewActor* A=G->PreviewActor.Get();
    switch(S.Step)
    {
    case 0:{ // next card
        ++S.Card;if(S.Card>S.Last||!G->Entries.IsValidIndex(S.Card)){Finish(S);GState.Reset();return false;}
        if(G->bLoadInFlight||G->bAppearanceBusy){--S.Card;S.Wait=Now+.5;return true;}
        G->SelectIndex(S.Card);G->OnLoad3D();S.At=Now;S.Step=1;S.Wait=Now+1;return true;}
    case 1:{ // loaded and compiled
        const bool Ready=A&&A->Session.IsOpen()&&!G->bLoadInFlight&&G->PreviewCardPath==G->Entries[S.Card].Path&&!(GShaderCompilingManager&&GShaderCompilingManager->IsCompiling());
        if(!Ready){if(Now-S.At>240){UE_LOG(LogTemp,Error,TEXT("Eye camera audit card=%d %s LOAD TIMEOUT"),S.Card,*G->Entries[S.Card].FileName);++S.Failed;
            auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),S.Card);O->SetStringField(TEXT("card"),G->Entries[S.Card].FileName);O->SetBoolField(TEXT("pass"),false);O->SetStringField(TEXT("error"),TEXT("load timeout"));S.Results.Add(MakeShared<FJsonValueObject>(O));S.Step=0;}
            S.Wait=Now+.5;return true;}
        if(A->Session.EyeLookPatternCount()<=0){UE_LOG(LogTemp,Error,TEXT("Eye camera audit card=%d %s FAIL no eye look pattern"),S.Card,*G->Entries[S.Card].FileName);++S.Failed;
            auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),S.Card);O->SetStringField(TEXT("card"),G->Entries[S.Card].FileName);O->SetBoolField(TEXT("pass"),false);O->SetStringField(TEXT("error"),TEXT("no eye look pattern"));S.Results.Add(MakeShared<FJsonValueObject>(O));S.Step=0;return true;}
        // Eyes open and still apart from the look: no blinking.
        A->FaceBlink.FixedFlags=1;A->BlinkEyeRate=1.f;A->BlinkBrowRate=1.f;A->ApplyMouth();
        // OK_EYE_AUDIT_HIDE=<role prefix>,...: parts of those roles hidden (a mask over her face, C011).
        {TArray<FString> Hide;FPlatformMisc::GetEnvironmentVariable(TEXT("OK_EYE_AUDIT_HIDE")).ParseIntoArray(Hide,TEXT(","));
         if(Hide.Num())for(const auto& Part:A->Parts)if(Hide.ContainsByPredicate([&](const FString& H){return Part.Role.StartsWith(H);})){
             TInlineComponentArray<UPrimitiveComponent*> Prims(A);const FName Tag(*FString::Printf(TEXT("KKSessionPart_%d"),Part.SessionIndex));
             for(UPrimitiveComponent* P:Prims)if(P->ComponentHasTag(Tag))P->SetVisibility(false,true);if(Part.Comp)Part.Comp->SetVisibility(false,true);}}
        G->OnEyeLookCamera(true);S.Mechanism=Mechanism(A);S.View=0;S.Step=2;S.Wait=Now+1.5;
        for(auto& V:S.Shots)for(auto& K:V)K=FShot();return true;}
    case 2: // camera to this view, following
        A->FaceBlink.FixedFlags=1;A->BlinkEyeRate=1.f;
        Place(A,S.FrontYaw+Yaws[S.View]);G->OnEyeLookCamera(true);S.Step=3;S.Wait=Now+1.6;return true;
    case 3: case 5:{ // shot
        const int32 K=S.Step==3?0:1;FShot& Shot=S.Shots[S.View][K];
        Shot.Rates[0]=A->EyeGaze[0];Shot.Rates[1]=A->EyeGaze[1];Shot.Rates[2]=A->EyeGaze[2];
        if(FScreenshotRequest::IsScreenshotRequested()){S.Wait=Now+.2;return true;}
        TWeakPtr<FState> Weak=GState;const int32 View=S.View;AKKPreviewActor* Actor=A;
        S.Handle=UGameViewportClient::OnScreenshotCaptured().AddLambda([Weak,View,K,Actor](int32 W,int32 H,const TArray<FColor>& Data){
            if(auto P=Weak.Pin()){FShot& Out=P->Shots[View][K];Out.Size=FIntPoint(W,H);Out.Pixels=Data;Out.Eyes=K==0?EyeRect(Actor,Out.Size):P->Shots[View][0].Eyes;
                UGameViewportClient::OnScreenshotCaptured().Remove(P->Handle);P->bShotPending=false;}});
        S.bShotPending=true;FScreenshotRequest::RequestScreenshot(S.Dir/TEXT("capture.png"),false,false,false);
        if(S.Step==3){S.Step=4;}else{S.Step=6;}return true;}
    case 4: // the same view, eyes held straight
        A->StopEyeLookTracking();A->SetEyeGaze(0,0,0);S.Step=5;S.Wait=Now+.8;return true;
    case 6:
        if(++S.View<3){S.Step=2;return true;}
        Judge(S,G,A);S.Step=0;return true;
    }
    return true;
}
static void Start(const TArray<FString>& Args)
{
    if(GState){UE_LOG(LogTemp,Warning,TEXT("Eye camera audit already running"));return;}
    GState=MakeShared<FState>();FState& S=*GState;S.At=FPlatformTime::Seconds();
    const FString First=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_EYE_AUDIT_FIRST")),Count=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_EYE_AUDIT_COUNT"));
    S.Card=(First.IsEmpty()?0:FCString::Atoi(*First))-1;S.Last=Count.IsEmpty()?MAX_int32:S.Card+FCString::Atoi(*Count);
    if(Args.Num()>=1)S.Card=FCString::Atoi(*Args[0])-1;if(Args.Num()>=2)S.Last=S.Card+FCString::Atoi(*Args[1]);
    // Yaw 0 is her front (Place turns it to her facing, the actor's +Y).
    S.FrontYaw=0;
    S.Dir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("Tests/EyeCamera")/FDateTime::Now().ToString(TEXT("%Y%m%d-%H%M%S")));
    IFileManager::Get().MakeDirectory(*S.Dir,true);
    UE_LOG(LogTemp,Display,TEXT("Eye camera audit start first=%d dir=%s"),S.Card+1,*S.Dir);
    GTicker=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&Tick),.1f);
}
static FAutoConsoleCommand Command(TEXT("ok.VerifyEyeCamera"),TEXT("Each reader card: eyes follow the camera from left, front and right (args: first count)"),FConsoleCommandWithArgsDelegate::CreateStatic(&Start));
}
