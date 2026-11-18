#pragma once
#include "CoreMinimal.h"
#include "InputCoreTypes.h"

class FJsonObject;

// Input as the player's keyboard and mouse deliver it: through FSlateApplication, so every input pre-processor (DreamGUI's
// Slate input source, the paint keys), the focused Slate/UMG widget and finally the game viewport see it in that order --
// what a real key or click reaches, and what it does not. The control channels' typing and clicking use this one
// implementation (ui_type, ui_mouse and the street's /type).
//
// Not the same path as APlayerController::InputKey (ui_key): that goes straight to the game's input, past every UI.
namespace OKSlateInput
{
	struct FModifiers { bool bShift=false, bCtrl=false, bAlt=false, bCmd=false; };
	// "shift", "ctrl"/"control", "alt", "cmd"/"command"; unknown names are an error.
	bool ParseModifiers(const TArray<FString>& Names,FModifiers& Out,FString& Error);

	// One key pressed and released: the modifier keys go down first and up last, with the state each event carries; a key
	// that types (Enter, Tab, BackSpace) also sends its character between, as the platform does.
	bool TapKey(const FKey& Key,const FModifiers& Modifiers);
	// Only the press, or only the release (to hold a key).
	bool KeyDown(const FKey& Key,const FModifiers& Modifiers);
	bool KeyUp(const FKey& Key,const FModifiers& Modifiers);

	// Each character typed. bKeyEvents: a key down and up around each character whose key is known (letters, digits, space,
	// the punctuation on the keyboard), as a keyboard sends them -- DreamGUI's fields type on the key down, Slate's on the
	// character. Off: the characters only (an IME's text, which has no keys).
	void TypeText(const FString& Text,bool bKeyEvents);

	// Pointer events at a point of the game viewport in its own pixels (a screenshot's pixels), moving the OS cursor there
	// too. Button: EKeys::LeftMouseButton / RightMouseButton / MiddleMouseButton.
	bool MouseMove(const FVector2D& ViewportPixel);
	bool MouseDown(const FVector2D& ViewportPixel,const FKey& Button);
	bool MouseUp(const FVector2D& ViewportPixel,const FKey& Button);
	bool MouseClick(const FVector2D& ViewportPixel,const FKey& Button,bool bDouble=false);
	// Pressed at From, moved there in Steps, released at To.
	bool MouseDrag(const FVector2D& From,const FVector2D& To,const FKey& Button,int32 Steps=12);
	bool MouseWheel(const FVector2D& ViewportPixel,float Notches);

	// Where the keyboard focus is: Slate's focused widget (its type and readable name) and the path above it, and every
	// DreamGUI text field that is being edited (owner, text). For the control channels' ui_focus.
	TSharedRef<FJsonObject> DescribeFocus();
}
