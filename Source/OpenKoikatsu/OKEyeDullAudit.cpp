// ok.VerifyEyeDull: the reader's cards with their pupils larger and their eye highlights off (2026-11-04, the user: a yandere's
// pupils 1.1 times as large, 1.3 times when worn out, no highlight; eye features pass on every reader card before the street
// gets them). For each card, hair and accessories out of the way and her eyes held ahead:
//   The size, from the pixels: the iris texture is swapped for a white one, then one with a black dot at its middle, at each
// scale; the dot is what differs. Its width against the one at scale 1 is to be the scale, its middle is to stay across (a
// narrow eye's lids cut off its top, so not its area or height).
//   The highlight: shots of her own iris with it on and off must differ, and on again must match the first.
//   A yandere card must come out of the load already at 1.1 with no highlight.
//   Saved/Tests/EyeDull/<run>/: result.json (after each card), sheet_NN.png (a row per card: as on the card, 1.1, 1.3).
//   -ExecCmds="ok.VerifyEyeDull [first count]"   OK_EYE_AUDIT_EXIT=1 quits after.
#include "OKCharacterController.h"
#include "KKPreviewActor.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Components/PoseableMeshComponent.h"
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

namespace OKEyeDullAudit
{
static UOKCharacterController* Gallery()
{
    for(TObjectIterator<UOKCharacterController> It;It;++It)if(IsValid(*It)&&It->GetWorld())return *It;
    return nullptr;
}
enum EIris{Own,White,Dot};
struct FPhase{EIris Iris;float Scale;bool bHide;};
// As on the card, highlight off, the two scales; then the size; then back.
static const FPhase Phases[]={{Own,1.f,false},{Own,1.f,true},{Own,1.1f,true},{Own,1.3f,true},{White,1.f,true},{Dot,1.f,true},{Dot,1.1f,true},{Dot,1.3f,true},{Own,1.f,false}};
constexpr int32 PhaseCount=UE_ARRAY_COUNT(Phases),PlainShot=0,DarkShot=1,Own11=2,Own13=3,WhiteShot=4,Dot1=5,Dot11=6,Dot13=7,BackShot=8;
constexpr int32 TileW=300,TileH=120,SheetCards=12;
struct FShot{TArray<FColor> Pixels;FIntPoint Size=FIntPoint::ZeroValue;};
struct FState
{
    int32 Card=-1,Last=-1,Step=0,Phase=0;double At=0,Wait=0;FString Dir;bool bShotPending=false,bYandere=false,bYandereOk=true;FDelegateHandle Handle;
    FShot Shots[PhaseCount];FVector2D Eyes[2];float Span=0;TArray<TSharedPtr<FJsonValue>> Results;int32 Passed=0,Failed=0,LoadFailed=0,Sheets=0,SheetRows=0;
    TArray<FColor> Sheet;TArray<TWeakObjectPtr<UPrimitiveComponent>> Hidden;TMap<TWeakObjectPtr<UMaterialInstanceDynamic>,TWeakObjectPtr<UTexture>> Marked;
};
static TSharedPtr<FState> GState;
static TStrongObjectPtr<UTexture2D> GTex[2];

static UTexture2D* Texture(int32 Index)
{
    if(GTex[Index])return GTex[Index].Get();
    const int32 N=256;UTexture2D* T=UTexture2D::CreateTransient(N,N,PF_B8G8R8A8);T->SRGB=false;T->Filter=TF_Bilinear;T->AddressX=T->AddressY=TA_Clamp;
    FColor* Out=static_cast<FColor*>(T->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE));
    for(int32 Y=0;Y<N;++Y)for(int32 X=0;X<N;++X)Out[Y*N+X]=Index&&FVector2D(X-N/2+.5f,Y-N/2+.5f).Size()<N*.12f?FColor(0,0,0,255):FColor(255,255,255,255);
    T->GetPlatformData()->Mips[0].BulkData.Unlock();T->UpdateResource();GTex[Index].Reset(T);return T;
}
// The test iris on her eyes, or their own textures back.
static void SetIris(FState& S,AKKPreviewActor* A,EIris Iris)
{
    if(Iris==Own){for(const auto& It:S.Marked)if(It.Key.IsValid())It.Key->SetTextureParameterValue(TEXT("_MainTex"),It.Value.Get());S.Marked.Reset();return;}
    UTexture2D* T=Texture(Iris==Dot);TInlineComponentArray<UMeshComponent*> Meshes(A);
    auto Swap=[&](UMaterialInstanceDynamic* M){UTexture* Was=nullptr;if(!M||!M->GetTextureParameterValue(FHashedMaterialParameterInfo(TEXT("_MainTex")),Was))return;if(!S.Marked.Contains(M))S.Marked.Add(M,Was);M->SetTextureParameterValue(TEXT("_MainTex"),T);};
    for(const auto& Part:A->Parts){if(A->Session.EyeMaterialSetting(Part.SessionIndex,-1)==0.f)continue;Swap(Part.GpuEyeMaterial);
        const FName Tags[]={*FString::Printf(TEXT("KKSessionPart_%d"),Part.SessionIndex),*FString::Printf(TEXT("KKMorphPart_%d"),Part.SessionIndex)};
        for(UMeshComponent* Drawn:Meshes)if(Drawn&&(Drawn==Part.Comp||Drawn->ComponentHasTag(Tags[0])||Drawn->ComponentHasTag(Tags[1])))for(int32 Slot=0;Slot<Drawn->GetNumMaterials();++Slot)Swap(Cast<UMaterialInstanceDynamic>(Drawn->GetMaterial(Slot)));}
}
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
// The camera close in front of her eyes; where they are on screen.
static bool Place(FState& S,AKKPreviewActor* A)
{
    FVector P[2];APlayerController* PC=A->GetWorld()?A->GetWorld()->GetFirstPlayerController():nullptr;if(!PC||!A->StudioCam||!EyePoints(A,P[0],P[1]))return false;
    const FVector F=A->GetActorTransform().TransformVectorNoScale(FVector(0,1,0));
    A->OrbitFocus=(P[0]+P[1])*.5f;A->OrbitYaw=FMath::RadiansToDegrees(FMath::Atan2(F.X,F.Y));A->OrbitPitch=0;A->OrbitDistance=60;
    if(UCameraComponent* C=A->StudioCam->GetCameraComponent())C->SetFieldOfView(22);
    A->ApplyOrbitCamera();return true;
}
static void Measure(FState& S,AKKPreviewActor* A)
{
    FVector P[2];APlayerController* PC=A->GetWorld()?A->GetWorld()->GetFirstPlayerController():nullptr;if(!PC||!EyePoints(A,P[0],P[1]))return;
    for(int32 I=0;I<2;++I)PC->ProjectWorldLocationToScreen(P[I],S.Eyes[I],true);
    S.Span=FMath::Max<float>(FVector2D::Distance(S.Eyes[0],S.Eyes[1]),20.f);
}
static FIntRect EyeArea(const FState& S,int32 Eye,FIntPoint Size)
{
    const float Middle=(S.Eyes[0].X+S.Eyes[1].X)*.5f;const bool Left=S.Eyes[Eye].X<Middle;
    FIntRect R(int32(Left?S.Eyes[Eye].X-S.Span*.75f:Middle),int32(S.Eyes[Eye].Y-S.Span*.25f),int32(Left?Middle:S.Eyes[Eye].X+S.Span*.75f),int32(S.Eyes[Eye].Y+S.Span*.95f));R.Clip(FIntRect(0,0,Size.X,Size.Y));return R;
}
static int32 Delta(const FColor& P,const FColor& Q){return FMath::Abs(int32(P.R)-Q.R)+FMath::Abs(int32(P.G)-Q.G)+FMath::Abs(int32(P.B)-Q.B);}
// The pixels of this eye that differ by more than Limit, and how wide they are and the middle of that.
static int32 Differ(const FState& S,const FShot& F,const FShot& N,int32 Eye,int32 Limit,float* Width=nullptr,float* Middle=nullptr)
{
    if(F.Size!=N.Size||F.Pixels.IsEmpty()||N.Pixels.Num()!=F.Pixels.Num())return 0;
    const FIntRect R=EyeArea(S,Eye,F.Size);int32 Count=0,Least=MAX_int32,Most=MIN_int32;
    for(int32 Y=R.Min.Y;Y<R.Max.Y;++Y)for(int32 X=R.Min.X;X<R.Max.X;++X)if(Delta(F.Pixels[Y*F.Size.X+X],N.Pixels[Y*F.Size.X+X])>Limit){++Count;Least=FMath::Min(Least,X);Most=FMath::Max(Most,X);}
    if(Width&&Count){*Width=Most-Least+1;*Middle=(Most+Least)*.5f;}
    return Count;
}
static void Save(const TArray<FColor>& Pixels,int32 W,int32 H,const FString& Path){TArray64<uint8> PNG;FImageUtils::PNGCompressImageArray(W,H,Pixels,PNG);FFileHelper::SaveArrayToFile(PNG,*Path);}
static void AddRow(FState& S,FColor Mark)
{
    const int32 W=TileW*3+8;S.Sheet.AddDefaulted(W*(TileH+2));const int32 Y0=S.SheetRows++*(TileH+2);
    for(int32 Y=0;Y<TileH+2;++Y)for(int32 X=0;X<W;++X)S.Sheet[(Y0+Y)*W+X]=X<8?Mark:FColor::Black;
    const FVector2D C=(S.Eyes[0]+S.Eyes[1])*.5f;const int32 Shots[]={PlainShot,Own11,Own13};
    const FIntRect R(int32(C.X-S.Span*1.1f),int32(C.Y-S.Span*.15f),int32(C.X+S.Span*1.1f),int32(C.Y+S.Span*.75f));
    for(int32 T=0;T<3;++T){const FShot& Shot=S.Shots[Shots[T]];if(Shot.Pixels.IsEmpty())continue;
        for(int32 Y=0;Y<TileH;++Y)for(int32 X=0;X<TileW-2;++X){const int32 SX=R.Min.X+X*R.Width()/TileW,SY=R.Min.Y+Y*R.Height()/TileH;
            if(SX>=0&&SY>=0&&SX<Shot.Size.X&&SY<Shot.Size.Y)S.Sheet[(Y0+Y)*W+8+T*TileW+X]=Shot.Pixels[SY*Shot.Size.X+SX];}}
}
static void FlushSheet(FState& S){if(!S.SheetRows)return;Save(S.Sheet,TileW*3+8,S.SheetRows*(TileH+2),S.Dir/FString::Printf(TEXT("sheet_%02d.png"),S.Sheets++));S.Sheet.Reset();S.SheetRows=0;}
static void WriteResult(const FState& S)
{
    auto Root=MakeShared<FJsonObject>();Root->SetNumberField(TEXT("passed"),S.Passed);Root->SetNumberField(TEXT("failed"),S.Failed);Root->SetNumberField(TEXT("load_failed"),S.LoadFailed);Root->SetArrayField(TEXT("cards"),S.Results);
    FString Text;auto W=TJsonWriterFactory<>::Create(&Text);FJsonSerializer::Serialize(Root,W);FFileHelper::SaveStringToFile(Text,*(S.Dir/TEXT("result.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}
static void Fail(FState& S,UOKCharacterController* G,const TCHAR* Status,const TCHAR* Error)
{
    ++(FCString::Strcmp(Status,TEXT("load_failed"))==0?S.LoadFailed:S.Failed);
    auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),S.Card);O->SetStringField(TEXT("card"),G->Entries.IsValidIndex(S.Card)?FPaths::GetBaseFilename(G->Entries[S.Card].Path):FString(TEXT("?")));O->SetStringField(TEXT("status"),Status);O->SetStringField(TEXT("error"),Error);
    S.Results.Add(MakeShared<FJsonValueObject>(O));WriteResult(S);UE_LOG(LogTemp,Error,TEXT("Eye dull audit card=%d %s: %s"),S.Card,Status,Error);
}
static void Judge(FState& S,UOKCharacterController* G,AKKPreviewActor* A)
{
    const FString Name=FPaths::GetBaseFilename(G->Entries[S.Card].Path);bool Good=S.bYandereOk;float CardHighlight=0;for(const auto& It:A->EyeHighlightBase)CardHighlight=FMath::Max(CardHighlight,It.Value.X);
    auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),S.Card);O->SetStringField(TEXT("card"),Name);O->SetBoolField(TEXT("yandere"),S.bYandere);O->SetNumberField(TEXT("card_highlight"),CardHighlight);
    TArray<TSharedPtr<FJsonValue>> Eyes;FString Said;
    for(int32 Eye=0;Eye<2;++Eye){float W1=0,W11=0,W13=0,M1=0,M11=0,M13=0;const FShot& W=S.Shots[WhiteShot];
        const int32 A1=Differ(S,S.Shots[Dot1],W,Eye,200,&W1,&M1);Differ(S,S.Shots[Dot11],W,Eye,200,&W11,&M11);Differ(S,S.Shots[Dot13],W,Eye,200,&W13,&M13);
        const float R11=W1?W11/W1:0,R13=W1?W13/W1:0,Moved=FMath::Max(FMath::Abs(M1-M11),FMath::Abs(M1-M13)),Allowed=FMath::Max(1.5f,.1f*W1);
        const int32 Off=Differ(S,S.Shots[PlainShot],S.Shots[DarkShot],Eye,36),Back=Differ(S,S.Shots[PlainShot],S.Shots[BackShot],Eye,36);
        const bool Size=A1>=40&&FMath::Abs(R11-1.1f)<=.06f&&FMath::Abs(R13-1.3f)<=.08f&&Moved<=Allowed,Light=(Off>=4||CardHighlight<=0.f)&&Back<=FMath::Max(6,Off/10);Good&=Size&&Light;
        auto Q=MakeShared<FJsonObject>();Q->SetNumberField(TEXT("dot"),A1);Q->SetNumberField(TEXT("r11"),R11);Q->SetNumberField(TEXT("r13"),R13);Q->SetNumberField(TEXT("moved"),Moved);Q->SetNumberField(TEXT("highlight_px"),Off);Q->SetNumberField(TEXT("back_px"),Back);Q->SetBoolField(TEXT("size_ok"),Size);Q->SetBoolField(TEXT("light_ok"),Light);Eyes.Add(MakeShared<FJsonValueObject>(Q));
        Said+=FString::Printf(TEXT(" eye%d dot=%d r=%.3f/%.3f moved=%.1f hi=%d back=%d"),Eye,A1,R11,R13,Moved,Off,Back);}
    O->SetArrayField(TEXT("eyes"),Eyes);O->SetStringField(TEXT("status"),Good?TEXT("pass"):TEXT("fail"));S.Results.Add(MakeShared<FJsonValueObject>(O));++(Good?S.Passed:S.Failed);
    AddRow(S,Good?FColor(0,160,0):FColor::Red);if(S.SheetRows>=SheetCards)FlushSheet(S);WriteResult(S);
    UE_LOG(LogTemp,Display,TEXT("Eye dull audit card=%d %s %s yandere=%d%s"),S.Card,*Name,Good?TEXT("pass"):TEXT("fail"),S.bYandere,*Said);
}
static void HideOver(FState& S,AKKPreviewActor* A)
{
    TInlineComponentArray<UPrimitiveComponent*> Prims(A);auto Hide=[&](UPrimitiveComponent* P){if(P->IsVisible()){P->SetVisibility(false,true);S.Hidden.Add(P);}};
    for(const auto& Part:A->Parts)if(Part.Role.StartsWith(TEXT("acc"))||Part.Role.Contains(TEXT("hair"))){const FName Tag(*FString::Printf(TEXT("KKSessionPart_%d"),Part.SessionIndex));
        for(UPrimitiveComponent* P:Prims)if(P->ComponentHasTag(Tag))Hide(P);if(Part.Comp)Hide(Part.Comp);}
}
static bool Tick(float)
{
    if(!GState)return false;FState& S=*GState;UOKCharacterController* G=Gallery();const double Now=FPlatformTime::Seconds();
    if(!G||G->Entries.IsEmpty()){if(Now-S.At>120){UE_LOG(LogTemp,Error,TEXT("Eye dull audit: no reader cards"));GState.Reset();return false;}return true;}
    if(S.bShotPending||Now<S.Wait)return true;
    AKKPreviewActor* A=G->PreviewActor.Get();
    switch(S.Step)
    {
    case 0:{ // next card
        if(G->bLoadInFlight||G->bAppearanceBusy){S.Wait=Now+.5;return true;}
        for(const auto& P:S.Hidden)if(P.IsValid())P->SetVisibility(true,true);S.Hidden.Reset();
        ++S.Card;S.At=Now;S.Step=1;S.Wait=Now+1;
        if(S.Card>S.Last||!G->Entries.IsValidIndex(S.Card)){FlushSheet(S);WriteResult(S);UE_LOG(LogTemp,Display,TEXT("Eye dull audit done: passed=%d failed=%d load_failed=%d dir=%s"),S.Passed,S.Failed,S.LoadFailed,*S.Dir);
            if(FPlatformMisc::GetEnvironmentVariable(TEXT("OK_EYE_AUDIT_EXIT"))==TEXT("1"))FPlatformMisc::RequestExit(false);GState.Reset();return false;}
        G->SelectIndex(S.Card);if(G->SelectedIndex!=S.Card){Fail(S,G,TEXT("load_failed"),TEXT("the card does not read"));S.Step=0;return true;}
        G->OutfitIndex=0;G->RefreshOutfitList();G->OnLoad3D();return true;}
    case 1:{ // loaded and compiled
        const bool Same=A&&A->Session.IsOpen()&&!G->bLoadInFlight&&G->PreviewCardPath==G->Entries[S.Card].Path&&G->PreviewOutfitIndex==0;
        if(!Same||(GShaderCompilingManager&&GShaderCompilingManager->IsCompiling())){
            if(!Same&&!G->bLoadInFlight&&Now-S.At>25){Fail(S,G,TEXT("load_failed"),TEXT("the load ended without her"));S.Step=0;return true;}
            if(Now-S.At>240){Fail(S,G,TEXT("load_failed"),TEXT("load timeout"));S.Step=0;return true;}
            S.Wait=Now+.5;return true;}
        S.bYandere=G->Selected.Personality==KKPersonalityYandere;S.bYandereOk=!S.bYandere||(FMath::IsNearlyEqual(A->EyePupilScale,1.1f)&&A->bEyeHighlightHidden);
        A->FaceBlink.FixedFlags=1;A->BlinkEyeRate=1.f;A->BlinkBrowRate=1.f;A->ApplyMouth();A->StopEyeLookTracking();A->SetEyeGaze(0,0,0);HideOver(S,A);
        if(!Place(S,A)){if(Now-S.At<25){S.Wait=Now+.5;return true;}Fail(S,G,TEXT("fail"),TEXT("no eye bones"));S.Step=0;return true;}
        for(auto& Shot:S.Shots)Shot=FShot();S.Phase=0;S.Step=2;S.Wait=Now+1;return true;}
    case 2:{ // this phase
        const FPhase& P=Phases[S.Phase];A->FaceBlink.FixedFlags=1;A->BlinkEyeRate=1.f;// SetEyeDull puts an iris of its own back: the test iris goes on after it.
        if(P.Iris==Own)SetIris(S,A,Own);A->SetEyeDull(P.Scale,P.bHide);if(P.Iris!=Own)SetIris(S,A,P.Iris);if(S.Phase==0)Measure(S,A);S.Step=3;S.Wait=Now+.35;return true;}
    case 3:{
        if(FScreenshotRequest::IsScreenshotRequested()){S.Wait=Now+.2;return true;}
        TWeakPtr<FState> Weak=GState;const int32 Phase=S.Phase;
        S.Handle=UGameViewportClient::OnScreenshotCaptured().AddLambda([Weak,Phase](int32 W,int32 H,const TArray<FColor>& Data){
            if(auto P=Weak.Pin()){P->Shots[Phase].Size=FIntPoint(W,H);P->Shots[Phase].Pixels=Data;UGameViewportClient::OnScreenshotCaptured().Remove(P->Handle);P->bShotPending=false;}});
        S.bShotPending=true;FScreenshotRequest::RequestScreenshot(S.Dir/TEXT("capture.png"),false,false,false);
        S.Step=++S.Phase<PhaseCount?2:4;return true;}
    case 4:
        Judge(S,G,A);S.Step=0;return true;
    }
    return true;
}
static void Start(const TArray<FString>& Args)
{
    if(GState){UE_LOG(LogTemp,Warning,TEXT("Eye dull audit already running"));return;}
    GState=MakeShared<FState>();FState& S=*GState;S.At=FPlatformTime::Seconds();S.Last=MAX_int32;
    if(Args.Num()>=1)S.Card=FCString::Atoi(*Args[0])-1;
    if(Args.Num()>=2)S.Last=S.Card+FCString::Atoi(*Args[1]);
    S.Dir=FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()/TEXT("Tests/EyeDull")/FDateTime::Now().ToString(TEXT("%Y%m%d-%H%M%S")));
    IFileManager::Get().MakeDirectory(*S.Dir,true);
    UE_LOG(LogTemp,Display,TEXT("Eye dull audit start first=%d dir=%s"),S.Card+1,*S.Dir);
    FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&Tick),.1f);
}
static FAutoConsoleCommand Command(TEXT("ok.VerifyEyeDull"),TEXT("Each reader card: pupils 1.1 and 1.3 times as large, eye highlights off and back (args: first count)"),FConsoleCommandWithArgsDelegate::CreateStatic(&Start));
}
