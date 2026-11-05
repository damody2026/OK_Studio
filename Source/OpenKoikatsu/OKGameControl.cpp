#include "OKGameControl.h"
#include "OKCharacterController.h"
#include "OKCharacterMCPRegistry.h"
#include "OKControl.h"
#include "Camera/PlayerCameraManager.h"
#include "Components/Button.h"
#include "Components/CheckBox.h"
#include "Components/ComboBoxString.h"
#include "Components/EditableTextBox.h"
#include "Components/Slider.h"
#include "Components/SpinBox.h"
#include "Containers/Ticker.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/PlayerController.h"
#include "HttpServerResponse.h"
#include "InputKeyEventArgs.h"
#include "Misc/App.h"
#include "Misc/CoreDelegates.h"
#include "Misc/Paths.h"
#include "Misc/StringOutputDevice.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UnrealClient.h"
#include "UObject/UObjectIterator.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

extern ENGINE_API float GAverageFPS;

namespace
{
using FObject=TSharedRef<FJsonObject>;
using FRows=TArray<TSharedPtr<FJsonValue>>;
FString GMode;
TFunction<void(FJsonObject&)> GModeState;
TFunction<bool(const FVector&,const FRotator&)> GModeCamera;
int32 GShots=0;

void Reply(const FHttpResultCallback& Done,const FObject& Body)
{
 FString Text;FJsonSerializer::Serialize(Body,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text));
 Done(FHttpServerResponse::Create(Text,TEXT("application/json; charset=utf-8")));
}
FObject Result(bool Ok,const FString& Error=FString())
{
 FObject O=MakeShared<FJsonObject>();O->SetBoolField(TEXT("ok"),Ok);if(!Error.IsEmpty())O->SetStringField(TEXT("error"),Error);return O;
}
FObject Body(const FHttpServerRequest& Req)
{
 const FUTF8ToTCHAR Utf8(reinterpret_cast<const ANSICHAR*>(Req.Body.GetData()),Req.Body.Num());const FString Text(Utf8.Length(),Utf8.Get());
 TSharedPtr<FJsonObject> Root;if(Text.IsEmpty()||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Root)||!Root)Root=MakeShared<FJsonObject>();return Root.ToSharedRef();
}
UWorld* World(){return GEngine&&GEngine->GameViewport?GEngine->GameViewport->GetWorld():nullptr;}
APlayerController* Player(){UWorld* W=World();return W?W->GetFirstPlayerController():nullptr;}

FString TextIn(const TSharedRef<SWidget>& W)
{
 if(W->GetType()==FName(TEXT("STextBlock")))return StaticCastSharedRef<STextBlock>(W)->GetText().ToString();
 if(FChildren* C=W->GetChildren())for(int32 I=0;I<C->Num();++I){FString T=TextIn(C->GetChildAt(I));if(!T.IsEmpty())return T;}
 return FString();
}
struct FScreen {TSet<const SWidget*> Shown;TArray<TPair<FString,TSharedRef<SWidget>>> Buttons;};
void Walk(const TSharedRef<SWidget>& W,FScreen& S)
{
 if(!W->GetVisibility().IsVisible())return;S.Shown.Add(&W.Get());
 if(W->GetType()==FName(TEXT("SButton")))S.Buttons.Add({TextIn(W),W});
 if(FChildren* C=W->GetChildren())for(int32 I=0;I<C->Num();++I)Walk(C->GetChildAt(I),S);
}
FScreen Screen()
{
 FScreen S;TFunction<void(const TSharedRef<SWindow>&)> Add=[&](const TSharedRef<SWindow>& W){Walk(W,S);for(const TSharedRef<SWindow>& C:W->GetChildWindows())Add(C);};
 if(FSlateApplication::IsInitialized())for(const TSharedRef<SWindow>& W:FSlateApplication::Get().GetInteractiveTopLevelWindows())Add(W);return S;
}
template<class T> bool IsA(UWidget* W){return Cast<T>(W)!=nullptr;}
// The Slate tree does not lead into what a player's layer holds, so UMG is found by its objects and judged by its own parents.
bool OnScreen(UWidget* W)
{
 if(!W->GetCachedWidget().IsValid()||W->GetCachedGeometry().GetLocalSize().IsNearlyZero())return false;
 for(UWidget* At=W;At;){
  const ESlateVisibility V=At->GetVisibility();if(V==ESlateVisibility::Collapsed||V==ESlateVisibility::Hidden)return false;
  if(UWidget* Parent=At->GetParent())At=Parent;else{auto* Tree=At->GetTypedOuter<UWidgetTree>();At=Tree?Cast<UWidget>(Tree->GetOuter()):nullptr;}
 }
 return true;
}
TArray<UWidget*> Operable()
{
 TArray<UWidget*> Out;UWorld* Now=World();
 for(TObjectIterator<UWidget> It;It;++It){UWidget* W=*It;
  if(!IsValid(W)||!(IsA<UButton>(W)||IsA<USlider>(W)||IsA<UComboBoxString>(W)||IsA<UCheckBox>(W)||IsA<UEditableTextBox>(W)||IsA<USpinBox>(W))||W->GetWorld()!=Now||!OnScreen(W))continue;Out.Add(W);}
 Out.Sort([](const UWidget& A,const UWidget& B){return A.GetName()<B.GetName();});return Out;
}
struct FButton {FString Label;TSharedPtr<SWidget> Slate;UButton* Umg=nullptr;bool Enabled=true;};
TArray<FButton> Buttons(const FScreen& S,const TArray<UWidget*>& Widgets)
{
 TArray<FButton> Out;TSet<const SWidget*> Seen;
 for(UWidget* W:Widgets)if(auto* B=Cast<UButton>(W)){const TSharedPtr<SWidget> Slate=B->GetCachedWidget();Seen.Add(Slate.Get());Out.Add({TextIn(Slate.ToSharedRef()),nullptr,B,B->GetIsEnabled()});}
 for(const auto& P:S.Buttons)if(!Seen.Contains(&P.Value.Get())&&!P.Value->GetCachedGeometry().GetLocalSize().IsNearlyZero())Out.Add({P.Key,P.Value,nullptr,P.Value->IsEnabled()});
 return Out;
}
FString KeyOf(UWidget* W)
{
 auto* Owner=W->GetTypedOuter<UUserWidget>();return (Owner?Owner->GetClass()->GetName()+TEXT("/"):FString())+W->GetName();
}
FObject Describe(UWidget* W)
{
 FObject O=MakeShared<FJsonObject>();O->SetStringField(TEXT("key"),KeyOf(W));O->SetStringField(TEXT("label"),OKCharacterMCPRegistry::Label(W));O->SetBoolField(TEXT("enabled"),W->GetIsEnabled());
 if(auto* S=Cast<USlider>(W)){O->SetStringField(TEXT("kind"),TEXT("number"));O->SetNumberField(TEXT("value"),S->GetValue());O->SetNumberField(TEXT("min"),S->GetMinValue());O->SetNumberField(TEXT("max"),S->GetMaxValue());}
 else if(auto* N=Cast<USpinBox>(W)){O->SetStringField(TEXT("kind"),TEXT("number"));O->SetNumberField(TEXT("value"),N->GetValue());O->SetNumberField(TEXT("min"),N->GetMinValue());O->SetNumberField(TEXT("max"),N->GetMaxValue());}
 else if(auto* C=Cast<UComboBoxString>(W)){O->SetStringField(TEXT("kind"),TEXT("choice"));O->SetStringField(TEXT("value"),C->GetSelectedOption());FRows Choices;for(int32 I=0;I<C->GetOptionCount();++I)Choices.Add(MakeShared<FJsonValueString>(C->GetOptionAtIndex(I)));O->SetArrayField(TEXT("choices"),Choices);}
 else if(auto* B=Cast<UCheckBox>(W)){O->SetStringField(TEXT("kind"),TEXT("bool"));O->SetBoolField(TEXT("value"),B->IsChecked());}
 else if(auto* T=Cast<UEditableTextBox>(W)){O->SetStringField(TEXT("kind"),TEXT("text"));O->SetStringField(TEXT("value"),T->GetText().ToString());}
 return O;
}
// The same steps as OKCharacterMCPRegistry::SetControl: what a person's change would fire.
bool SetValue(UWidget* W,const TSharedPtr<FJsonValue>& V,FString& Error)
{
 if(!W->GetIsEnabled()){Error=TEXT("disabled");return false;}if(!V.IsValid()){Error=TEXT("value is required");return false;}
 double N=0;bool B=false;FString T;
 if(auto* S=Cast<USlider>(W)){if(!V->TryGetNumber(N)||N<S->GetMinValue()||N>S->GetMaxValue()){Error=TEXT("number in range required");return false;}S->SetValue(N);S->OnValueChanged.Broadcast(N);}
 else if(auto* Spin=Cast<USpinBox>(W)){if(!V->TryGetNumber(N)){Error=TEXT("number required");return false;}Spin->SetValue(N);Spin->OnValueChanged.Broadcast(N);Spin->OnValueCommitted.Broadcast(N,ETextCommit::OnEnter);}
 else if(auto* C=Cast<UComboBoxString>(W)){if(!V->TryGetString(T)||C->FindOptionIndex(T)==INDEX_NONE){Error=TEXT("not one of the choices");return false;}auto Changed=C->OnSelectionChanged;C->OnSelectionChanged.Clear();C->SetSelectedOption(T);C->OnSelectionChanged=Changed;C->OnSelectionChanged.Broadcast(T,ESelectInfo::OnMouseClick);}
 else if(auto* Check=Cast<UCheckBox>(W)){if(!V->TryGetBool(B)){Error=TEXT("true or false required");return false;}Check->SetIsChecked(B);Check->OnCheckStateChanged.Broadcast(B);}
 else if(auto* Box=Cast<UEditableTextBox>(W)){if(!V->TryGetString(T)){Error=TEXT("text required");return false;}auto Changed=Box->OnTextChanged;Box->OnTextChanged.Clear();Box->SetText(FText::FromString(T));Box->OnTextChanged=Changed;Box->OnTextChanged.Broadcast(Box->GetText());Box->OnTextCommitted.Broadcast(Box->GetText(),ETextCommit::OnEnter);}
 if(auto* G=W->GetTypedOuter<UOKCharacterController>())G->ApplyPendingEditorMods();
 return true;
}
TArray<TSharedPtr<FJsonValue>> Vec(double X,double Y,double Z){return {MakeShared<FJsonValueNumber>(X),MakeShared<FJsonValueNumber>(Y),MakeShared<FJsonValueNumber>(Z)};}

void Bind(const TCHAR* Path,EHttpServerRequestVerbs Verb,OKControl::FHandler Fn){OKControl::Bind(TEXT("ui"),Path,Verb,MoveTemp(Fn));}

void Routes()
{
 constexpr auto Get=EHttpServerRequestVerbs::VERB_GET;constexpr auto Post=EHttpServerRequestVerbs::VERB_POST;
 Bind(TEXT("/health"),Get,[](const FHttpServerRequest&,const FHttpResultCallback& Done){Reply(Done,Result(true));});
 Bind(TEXT("/state"),Get,[](const FHttpServerRequest&,const FHttpResultCallback& Done){
  FObject O=Result(true);O->SetNumberField(TEXT("pid"),FPlatformProcess::GetCurrentProcessId());O->SetNumberField(TEXT("fps"),GAverageFPS);O->SetStringField(TEXT("mode"),GMode);
  if(UWorld* W=World()){O->SetStringField(TEXT("map"),W->GetMapName());if(AGameModeBase* M=W->GetAuthGameMode())O->SetStringField(TEXT("game_mode"),M->GetClass()->GetName());}
  if(GEngine&&GEngine->GameViewport&&GEngine->GameViewport->Viewport){const FIntPoint Size=GEngine->GameViewport->Viewport->GetSizeXY();O->SetNumberField(TEXT("viewport_width"),Size.X);O->SetNumberField(TEXT("viewport_height"),Size.Y);}
  if(APlayerController* PC=Player())if(PC->PlayerCameraManager){const FVector L=PC->PlayerCameraManager->GetCameraLocation();const FRotator R=PC->PlayerCameraManager->GetCameraRotation();FObject C=MakeShared<FJsonObject>();C->SetArrayField(TEXT("location"),Vec(L.X,L.Y,L.Z));C->SetArrayField(TEXT("rotation"),Vec(R.Pitch,R.Yaw,R.Roll));O->SetObjectField(TEXT("camera"),C);}
  if(GModeState)GModeState(*O);Reply(Done,O);});
 // Everything a person can operate now: buttons (pure Slate ones too) and the UMG value controls.
 Bind(TEXT("/widgets"),Get,[](const FHttpServerRequest&,const FHttpResultCallback& Done){
  const FScreen S=Screen();const auto Widgets=Operable();FRows Pressable,Values;TMap<FString,int32> Seen;
  for(const FButton& B:Buttons(S,Widgets)){FObject O=MakeShared<FJsonObject>();O->SetStringField(TEXT("label"),B.Label);O->SetNumberField(TEXT("index"),Seen.FindOrAdd(B.Label)++);O->SetBoolField(TEXT("enabled"),B.Enabled);Pressable.Add(MakeShared<FJsonValueObject>(O));}
  for(UWidget* W:Widgets)if(!IsA<UButton>(W))Values.Add(MakeShared<FJsonValueObject>(Describe(W)));
  FObject O=Result(true);O->SetArrayField(TEXT("buttons"),Pressable);O->SetArrayField(TEXT("controls"),Values);Reply(Done,O);});
 // {label, index}: press that button. {key | label, index, value}: set that control.
 Bind(TEXT("/widget"),Post,[](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  FObject B=Body(Req);FString Key,Label;B->TryGetStringField(TEXT("key"),Key);B->TryGetStringField(TEXT("label"),Label);double Index=0;B->TryGetNumberField(TEXT("index"),Index);
  const auto Widgets=Operable();
  if(!B->HasField(TEXT("value"))){int32 Nth=0;for(const FButton& Button:Buttons(Screen(),Widgets))if(Button.Label==Label&&Nth++==int32(Index)){if(!Button.Enabled){Reply(Done,Result(false,TEXT("disabled")));return;}if(Button.Umg)Button.Umg->OnClicked.Broadcast();else StaticCastSharedPtr<SButton>(Button.Slate)->SimulateClick();Reply(Done,Result(true));return;}Reply(Done,Result(false,TEXT("no such button on screen")));return;}
  int32 Nth=0;for(UWidget* W:Widgets)if(!IsA<UButton>(W)&&(Key.IsEmpty()?(OKCharacterMCPRegistry::Label(W)==Label&&Nth++==int32(Index)):KeyOf(W)==Key)){FString Error;const bool Ok=SetValue(W,B->TryGetField(TEXT("value")),Error);Reply(Done,Ok?Describe(W):Result(false,Error));return;}
  Reply(Done,Result(false,TEXT("no such control on screen")));});
 Bind(TEXT("/exec"),Post,[](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  FString Command;Body(Req)->TryGetStringField(TEXT("command"),Command);Command.TrimStartAndEndInline();if(Command.IsEmpty()){Reply(Done,Result(false,TEXT("command is required")));return;}
  FStringOutputDevice Out;Out.SetAutoEmitLineTerminator(true);UWorld* W=World();bool Handled=false;
  if(GEngine&&GEngine->GameViewport&&W)Handled=GEngine->GameViewport->Exec(W,*Command,Out);if(!Handled&&GEngine)Handled=GEngine->Exec(W,*Command,Out);
  FObject O=Result(Handled,Handled?FString():TEXT("not a known command"));O->SetStringField(TEXT("output"),Out);Reply(Done,O);});
 Bind(TEXT("/screenshot"),Post,[](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  bool Ui=true;Body(Req)->TryGetBoolField(TEXT("ui"),Ui);
  const FString File=OKControl::Checkout()/FString::Printf(TEXT("Saved/OKControl/shots/%u-%04d.png"),FPlatformProcess::GetCurrentProcessId(),++GShots);
  FScreenshotRequest::RequestScreenshot(File,Ui,false);FObject O=Result(true);O->SetStringField(TEXT("path"),File);Reply(Done,O);});
 // {key, seconds}: as the player's keyboard: pressed, and released after that long.
 Bind(TEXT("/key"),Post,[](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  FObject B=Body(Req);FString Name;B->TryGetStringField(TEXT("key"),Name);double Seconds=.05;B->TryGetNumberField(TEXT("seconds"),Seconds);const FKey Key(*Name);APlayerController* PC=Player();
  if(!Key.IsValid()||!PC){Reply(Done,Result(false,TEXT("unknown key name, or no player")));return;}
  PC->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));
  FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak=TWeakObjectPtr<APlayerController>(PC),Key](float){if(Weak.IsValid())Weak->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Released,0.f));return false;}),float(FMath::Clamp(Seconds,0.,60.)));
  Reply(Done,Result(true));});
 Bind(TEXT("/camera"),Post,[](const FHttpServerRequest& Req,const FHttpResultCallback& Done){
  FObject B=Body(Req);const TArray<TSharedPtr<FJsonValue>>* L=nullptr;const TArray<TSharedPtr<FJsonValue>>* R=nullptr;APlayerController* PC=Player();
  if(!PC||!B->TryGetArrayField(TEXT("location"),L)||!B->TryGetArrayField(TEXT("rotation"),R)||L->Num()!=3||R->Num()!=3){Reply(Done,Result(false,TEXT("location [x,y,z] and rotation [pitch,yaw,roll] are required")));return;}
  const FVector Location((*L)[0]->AsNumber(),(*L)[1]->AsNumber(),(*L)[2]->AsNumber());const FRotator Rotation((*R)[0]->AsNumber(),(*R)[1]->AsNumber(),(*R)[2]->AsNumber());
  bool Ok=false;if(GModeCamera)Ok=GModeCamera(Location,Rotation);else if(AActor* Target=PC->GetViewTarget())Ok=Target->SetActorLocationAndRotation(Location,Rotation);
  Reply(Done,Result(Ok,Ok?FString():TEXT("this mode's camera cannot be placed")));});
}
void WorldReady(UWorld* W,const UWorld::InitializationValues)
{
 if(W&&W->IsGameWorld())OKControl::Publish(TEXT("map"),W->GetMapName());
}
}

namespace OKGameControl
{
void Start()
{
 if(!FApp::IsGame()||IsRunningCommandlet())return;
 FCoreDelegates::OnPostEngineInit.AddLambda([]{
  if(!OKControl::Listen(TEXT("ui"),12))return;Routes();
  FWorldDelegates::OnPostWorldInitialization.AddStatic(&WorldReady);});
}
void SetMode(const FString& Name,TFunction<void(FJsonObject&)> State,TFunction<bool(const FVector&,const FRotator&)> Camera)
{
 GMode=Name;GModeState=MoveTemp(State);GModeCamera=MoveTemp(Camera);OKControl::Publish(TEXT("mode"),Name);
}
void ClearMode(){GMode.Empty();GModeState=nullptr;GModeCamera=nullptr;}
}
