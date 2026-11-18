#include "OKSlateInput.h"
#include "Containers/Ticker.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Framework/Application/SlateApplication.h"
#include "Interaction/UITextInput.h"
#include "Core/Components/DreamWidget.h"
#include "UnrealClient.h"
#include "UObject/UObjectIterator.h"
#include "Widgets/SViewport.h"

namespace
{
FModifierKeysState StateOf(const OKSlateInput::FModifiers& M)
{
	return FModifierKeysState(M.bShift,false,M.bCtrl,false,M.bAlt,false,M.bCmd,false,false);
}
// The modifier keys that are down, in the order a hand presses them.
TArray<FKey> ModifierKeys(const OKSlateInput::FModifiers& M)
{
	TArray<FKey> Out;
	if(M.bCtrl)Out.Add(EKeys::LeftControl);
	if(M.bAlt)Out.Add(EKeys::LeftAlt);
	if(M.bShift)Out.Add(EKeys::LeftShift);
	if(M.bCmd)Out.Add(EKeys::LeftCommand);
	return Out;
}
bool SendKey(const FKey& Key,const FModifierKeysState& State,bool bDown)
{
	if(!FSlateApplication::IsInitialized()||!Key.IsValid())return false;
	const uint32* KeyCode=nullptr;const uint32* CharCode=nullptr;
	FInputKeyManager::Get().GetCodesFromKey(Key,KeyCode,CharCode);
	const FKeyEvent Event(Key,State,FSlateApplication::Get().GetUserIndexForKeyboard(),false,CharCode?*CharCode:0,KeyCode?*KeyCode:0);
	return bDown?FSlateApplication::Get().ProcessKeyDownEvent(Event):FSlateApplication::Get().ProcessKeyUpEvent(Event);
}
void SendChar(TCHAR C,const FModifierKeysState& State)
{
	if(FSlateApplication::IsInitialized())FSlateApplication::Get().ProcessKeyCharEvent(FCharacterEvent(C,State,FSlateApplication::Get().GetUserIndexForKeyboard(),false));
}
// The character a key types on its own (the platform sends it after the key down).
TCHAR CharOfKey(const FKey& Key)
{
	if(Key==EKeys::Enter)return TEXT('\r');
	if(Key==EKeys::Tab)return TEXT('\t');
	if(Key==EKeys::BackSpace)return TEXT('\b');
	return 0;
}
// The key a character is typed with, when the keyboard has one.
FKey KeyOfChar(TCHAR C)
{
	if(C==TEXT(' '))return EKeys::SpaceBar;
	if(C==TEXT('\r')||C==TEXT('\n'))return EKeys::Enter;
	if(C==TEXT('\t'))return EKeys::Tab;
	if(C>=128)return EKeys::Invalid;
	const uint32 Upper=uint32(FChar::ToUpper(C));
	const bool bAlnum=FChar::IsAlnum(C);
	return FInputKeyManager::Get().GetKeyFromCodes(bAlnum?Upper:0,Upper);
}

bool ToAbsolute(const FVector2D& Pixel,FVector2D& Out)
{
	if(!GEngine||!GEngine->GameViewport||!GEngine->GameViewport->Viewport)return false;
	TSharedPtr<SViewport> Widget=GEngine->GameViewport->GetGameViewportWidget();
	const FIntPoint Size=GEngine->GameViewport->Viewport->GetSizeXY();
	if(!Widget.IsValid()||Size.X<=0||Size.Y<=0)return false;
	const FGeometry& G=Widget->GetCachedGeometry();
	const FVector2D Position(G.GetAbsolutePosition()),Extent(G.GetAbsoluteSize());
	Out=Position+Pixel*Extent/FVector2D(Size);
	return true;
}
// Mouse buttons this input holds down (a real mouse's would be in the platform's state; ours only in the events).
TSet<FKey> GPressed;
FVector2D GLastAbsolute=FVector2D::ZeroVector;

FPointerEvent Pointer(const FVector2D& Absolute,const FKey& Effecting,float Wheel=0.f)
{
	FSlateApplication& App=FSlateApplication::Get();
	return FPointerEvent(App.GetUserIndexForMouse(),FSlateApplicationBase::CursorPointerIndex,Absolute,GLastAbsolute,GPressed,Effecting,Wheel,App.GetModifierKeys());
}
bool Move(const FVector2D& Pixel)
{
	FVector2D Absolute;if(!FSlateApplication::IsInitialized()||!ToAbsolute(Pixel,Absolute))return false;
	FSlateApplication& App=FSlateApplication::Get();
	App.SetCursorPos(Absolute);
	const FPointerEvent Event=Pointer(Absolute,EKeys::Invalid);
	App.ProcessMouseMoveEvent(Event);GLastAbsolute=Absolute;
	return true;
}
bool Button(const FVector2D& Pixel,const FKey& Key,bool bDown,bool bDouble=false)
{
	FVector2D Absolute;if(!FSlateApplication::IsInitialized()||!ToAbsolute(Pixel,Absolute))return false;
	FSlateApplication& App=FSlateApplication::Get();
	if(bDown)GPressed.Add(Key);else GPressed.Remove(Key);
	const FPointerEvent Event=Pointer(Absolute,Key);
	if(!bDown)return App.ProcessMouseButtonUpEvent(Event);
	return bDouble?App.ProcessMouseButtonDoubleClickEvent(nullptr,Event):App.ProcessMouseButtonDownEvent(nullptr,Event);
}
// Steps run one per tick, so the UI sees the pointer arrive, the press and the release in separate frames (DreamGUI reads
// its pointer once a frame: a press and release in the same frame clicked nothing).
void RunSteps(TArray<TFunction<void()>> Steps)
{
	if(Steps.IsEmpty())return;
	struct FRun{TArray<TFunction<void()>> Steps;int32 Next=0;};
	TSharedRef<FRun> Run=MakeShared<FRun>();Run->Steps=MoveTemp(Steps);
	Run->Steps[Run->Next++]();
	if(Run->Next>=Run->Steps.Num())return;
	FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Run](float){Run->Steps[Run->Next++]();return Run->Next<Run->Steps.Num();}),0.03f);
}
}

namespace OKSlateInput
{
bool ParseModifiers(const TArray<FString>& Names,FModifiers& Out,FString& Error)
{
	for(const FString& Raw:Names)
	{
		const FString N=Raw.ToLower();
		if(N==TEXT("shift"))Out.bShift=true;
		else if(N==TEXT("ctrl")||N==TEXT("control"))Out.bCtrl=true;
		else if(N==TEXT("alt"))Out.bAlt=true;
		else if(N==TEXT("cmd")||N==TEXT("command"))Out.bCmd=true;
		else{Error=FString::Printf(TEXT("unknown modifier %s (shift, ctrl, alt, cmd)"),*Raw);return false;}
	}
	return true;
}

bool KeyDown(const FKey& Key,const FModifiers& Modifiers)
{
	if(!Key.IsValid())return false;
	FModifiers Held;
	for(const FKey& M:ModifierKeys(Modifiers))
	{
		if(M==EKeys::LeftControl)Held.bCtrl=true;else if(M==EKeys::LeftAlt)Held.bAlt=true;else if(M==EKeys::LeftShift)Held.bShift=true;else Held.bCmd=true;
		SendKey(M,StateOf(Held),true);
	}
	const bool bTaken=SendKey(Key,StateOf(Modifiers),true);
	if(const TCHAR C=CharOfKey(Key);C&&!Modifiers.bCtrl&&!Modifiers.bAlt&&!Modifiers.bCmd)SendChar(C,StateOf(Modifiers));
	return bTaken;
}
bool KeyUp(const FKey& Key,const FModifiers& Modifiers)
{
	if(!Key.IsValid())return false;
	const bool bTaken=SendKey(Key,StateOf(Modifiers),false);
	FModifiers Held=Modifiers;TArray<FKey> Mods=ModifierKeys(Modifiers);
	for(int32 I=Mods.Num()-1;I>=0;--I)
	{
		const FKey& M=Mods[I];
		if(M==EKeys::LeftControl)Held.bCtrl=false;else if(M==EKeys::LeftAlt)Held.bAlt=false;else if(M==EKeys::LeftShift)Held.bShift=false;else Held.bCmd=false;
		SendKey(M,StateOf(Held),false);
	}
	return bTaken;
}
bool TapKey(const FKey& Key,const FModifiers& Modifiers)
{
	const bool bTaken=KeyDown(Key,Modifiers);
	KeyUp(Key,Modifiers);
	return bTaken;
}

void TypeText(const FString& Text,bool bKeyEvents)
{
	for(const TCHAR C:Text)
	{
		FModifiers M;M.bShift=FChar::IsUpper(C);
		const FKey Key=bKeyEvents?KeyOfChar(C):EKeys::Invalid;
		if(Key.IsValid())SendKey(Key,StateOf(M),true);
		SendChar(C==TEXT('\n')?TEXT('\r'):C,StateOf(M));
		if(Key.IsValid())SendKey(Key,StateOf(M),false);
	}
}

bool MouseMove(const FVector2D& Pixel){return Move(Pixel);}
bool MouseDown(const FVector2D& Pixel,const FKey& B){return Move(Pixel)&&(Button(Pixel,B,true),true);}
bool MouseUp(const FVector2D& Pixel,const FKey& B){return Move(Pixel)&&(Button(Pixel,B,false),true);}
bool MouseClick(const FVector2D& Pixel,const FKey& B,bool bDouble)
{
	FVector2D Probe;if(!ToAbsolute(Pixel,Probe))return false;
	TArray<TFunction<void()>> Steps;
	Steps.Add([Pixel](){Move(Pixel);});
	Steps.Add([Pixel,B](){Button(Pixel,B,true);});
	Steps.Add([Pixel,B](){Button(Pixel,B,false);});
	// A double click is a press, release, then the platform's double-click event and its release.
	if(bDouble){Steps.Add([Pixel,B](){Button(Pixel,B,true,true);});Steps.Add([Pixel,B](){Button(Pixel,B,false);});}
	RunSteps(MoveTemp(Steps));
	return true;
}
bool MouseDrag(const FVector2D& From,const FVector2D& To,const FKey& B,int32 Count)
{
	FVector2D Probe;if(!ToAbsolute(From,Probe))return false;
	Count=FMath::Clamp(Count,1,240);
	TArray<TFunction<void()>> Steps;
	Steps.Add([From](){Move(From);});
	Steps.Add([From,B](){Button(From,B,true);});
	for(int32 I=1;I<=Count;++I){const FVector2D At=FMath::Lerp(From,To,double(I)/Count);Steps.Add([At](){Move(At);});}
	Steps.Add([To,B](){Button(To,B,false);});
	RunSteps(MoveTemp(Steps));
	return true;
}
bool MouseWheel(const FVector2D& Pixel,float Notches)
{
	FVector2D Absolute;if(!FSlateApplication::IsInitialized()||!Move(Pixel)||!ToAbsolute(Pixel,Absolute))return false;
	FSlateApplication::Get().ProcessMouseWheelOrGestureEvent(Pointer(Absolute,EKeys::Invalid,Notches),nullptr);
	return true;
}

TSharedRef<FJsonObject> DescribeFocus()
{
	TSharedRef<FJsonObject> O=MakeShared<FJsonObject>();
	if(FSlateApplication::IsInitialized())
	{
		FSlateApplication& App=FSlateApplication::Get();
		const TSharedPtr<SWidget> Focus=App.GetKeyboardFocusedWidget();
		O->SetStringField(TEXT("slate_focus"),Focus.IsValid()?Focus->GetTypeAsString():FString());
		O->SetStringField(TEXT("slate_focus_name"),Focus.IsValid()?Focus->ToString():FString());
		// From the focused widget up to the window: tells a UMG control (SObjectWidget above it) from the game viewport.
		TArray<TSharedPtr<FJsonValue>> Path;
		for(TSharedPtr<SWidget> W=Focus;W.IsValid()&&Path.Num()<40;W=W->GetParentWidget())Path.Add(MakeShared<FJsonValueString>(W->GetTypeAsString()));
		O->SetArrayField(TEXT("slate_focus_path"),Path);
		bool bViewport=false;
		if(GEngine&&GEngine->GameViewport){if(TSharedPtr<SViewport> V=GEngine->GameViewport->GetGameViewportWidget())bViewport=Focus==V;}
		O->SetBoolField(TEXT("game_viewport_has_focus"),bViewport);
		TArray<TSharedPtr<FJsonValue>> Mouse;for(const FKey& K:App.GetPressedMouseButtons())Mouse.Add(MakeShared<FJsonValueString>(K.ToString()));
		O->SetArrayField(TEXT("mouse_buttons_down"),Mouse);
	}
	// DreamGUI's fields take keys from its own Slate input source, not from Slate's focus: the ones being edited now.
	TArray<TSharedPtr<FJsonValue>> Editing;
	for(TObjectIterator<UUITextInput> It;It;++It)
	{
		if(!It->IsInputActive())continue;
		TSharedRef<FJsonObject> F=MakeShared<FJsonObject>();
		UDreamWidget* Owner=It->GetWidget();
		F->SetStringField(TEXT("widget"),Owner?Owner->GetPathName():It->GetPathName());
		F->SetStringField(TEXT("text"),It->GetText());
		Editing.Add(MakeShared<FJsonValueObject>(F));
	}
	O->SetArrayField(TEXT("dreamgui_editing"),Editing);
	return O;
}
}
