#pragma once

#include "CoreMinimal.h"
#include "Components/Button.h"
#include "Components/CheckBox.h"
#include "Components/ComboBoxString.h"
#include "Components/EditableTextBox.h"
#include "OKReaderPageItems.generated.h"

class UOKCharacterController;
class UVerticalBox;
class UWidget;

// pages.json items of kind bool／choice／color／text／button (Docs/OK_MOD_S4_READER_PREREQ.md). Each is a UMG control
// in the controller's see-through UMG layer, bound to a registry key (OKCharacterMCPRegistry, the same keys reader_call
// get／set and `ok.ReaderScreen set key=` use) or, for a button, to a reader action. The reader screen mirrors it like
// every other source, and ui_widgets／ui_set reach it as a UMG control: nothing new to expose to the MCP.
//
// Keys: any registry key of the item's kind (a card property, later `mod.<id>.*`), plus the reader's own `reader.lang`.
// A key the registry does not have yet (the card's properties are read when a page asks for them) leaves its control
// disabled until it does; an unknown key is never an error at build time for that reason.
namespace OKReaderPageItems
{
	// The kinds built here.
	bool IsItemKind(const FString& Kind);
	// One item's row (caption + control) in this page's box (made in the controller's ShapeBox on the first item,
	// collapsed until the page shows). Null and Error: why it was not built (the page says it in red).
	UWidget* Build(UOKCharacterController* G,UVerticalBox*& Box,const TSharedPtr<FJsonObject>& Spec,FString& Error);
	// Only this page's box shown (null: none). Called on every page switch before the page's own enter.
	void ShowOnly(UVerticalBox* Box);
	// Every shown item's control takes the value its key has now (a few times a second).
	void Refresh(UOKCharacterController* G,float DeltaSeconds);
	// Captions from label_id follow the reader's language.
	void Relabel();
	// A reader action by name: what a button item, the pages' own_buttons and (later) mods run.
	bool IsKnownAction(const FString& Action);
	bool RunAction(UOKCharacterController* G,const FString& Action,FString& Error);
	// Every item made (for the audit and `ok.ReaderScreen pageitems`): kind, key or action, and the control's path.
	void List(FOutputDevice& Out);
	// Forget every item (the pages are about to be built again).
	void Reset();
}

UCLASS()
class OPENKOIKATSU_API UOKPageItemToggle : public UCheckBox
{
	GENERATED_BODY()
public:
	TWeakObjectPtr<UOKCharacterController> Owner;
	FString Key;
	UFUNCTION() void Changed(bool bNewChecked);
};

UCLASS()
class OPENKOIKATSU_API UOKPageItemChoice : public UComboBoxString
{
	GENERATED_BODY()
public:
	TWeakObjectPtr<UOKCharacterController> Owner;
	FString Key;
	// Option label -> the value written (a registry choice's {value, label}).
	TMap<FString,FString> Values;
	bool bQuiet=false;
	UFUNCTION() void Selected(FString Option,ESelectInfo::Type SelectionType);
};

// A text item, or a colour item (#RRGGBB／#RRGGBBAA written to the key's .r/.g/.b/.a or .0-.3 components).
UCLASS()
class OPENKOIKATSU_API UOKPageItemText : public UEditableTextBox
{
	GENERATED_BODY()
public:
	TWeakObjectPtr<UOKCharacterController> Owner;
	FString Key;
	bool bColor=false;
	UFUNCTION() void Committed(const FText& Typed,ETextCommit::Type CommitType);
};

UCLASS()
class OPENKOIKATSU_API UOKPageItemButton : public UButton
{
	GENERATED_BODY()
public:
	TWeakObjectPtr<UOKCharacterController> Owner;
	FString Action;
	UFUNCTION() void Clicked();
};
