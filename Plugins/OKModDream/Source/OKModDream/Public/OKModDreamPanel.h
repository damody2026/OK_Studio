// A mod's .dui panel (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.13 D2, Docs/OK_MOD_HOOKS.md).
//
// A mod ships a .dui; the ModKit (Tools/modkit_cook.lua) compiles it with DreamGUI's DreamUICompileWidgets into a widget
// Blueprint whose parent is UOKModDreamPanel, and cooks it into the mod's content pak. The .dui reaches the game only
// through one object, `Mod` (UOKModDreamBridge):
//
//   Text Greeting { Text <- Mod.Text("greeting") }          // a value of this mod: mod.<id>.greeting
//   Native.Button Hello { OnClicked += Mod.Emit("hello") }  // to the mod's Rust code: hook ui.<id>.hello
//
// Mod.Text / Number / Flag read only this mod's own values (the key is prefixed with mod.<id>.); Emit / EmitValue only
// raise this mod's ui.<id>.* hook. The game side (the card reader) fills in what they do.
//
// OKModDream::CheckPackage is the check that such a package holds only what the DreamGUI compiler makes from a .dui
// (parent class, generated function names, the functions the bytecode calls, the packages it reaches). The game runs it
// when it mounts a mod pak; the ModKit runs it (commandlet OKModDreamCheck) before cooking.
#pragma once

#include "CoreMinimal.h"
#include "Core/DreamTextUserWidget.h"
#include "Commandlets/Commandlet.h"
#include "OKModDreamPanel.generated.h"

/** What a mod's .dui can reach: this mod's values and this mod's ui hooks, nothing else. */
UCLASS(BlueprintType)
class OKMODDREAM_API UOKModDreamBridge : public UObject
{
	GENERATED_BODY()

public:
	/** The mod this panel belongs to. */
	FString ModId;
	/** Raises hook ui.<mod>.<event> with a value (empty when none). Set by the game. */
	TFunction<void(const FString& Event, const FString& Value)> OnEmit;
	/** The mod's value mod.<mod>.<key> as text (numbers in their shortest form, true/false). Set by the game. */
	TFunction<FString(const FString& Key)> OnRead;

	/** Raises this mod's hook ui.<mod id>.<Event> (letters, digits and _ only). */
	UFUNCTION(BlueprintCallable, Category = "OK Mod")
	void Emit(const FString& Event);
	/** Raises this mod's hook ui.<mod id>.<Event> with a value. */
	UFUNCTION(BlueprintCallable, Category = "OK Mod")
	void EmitValue(const FString& Event, const FString& Value);
	/** This mod's value mod.<mod id>.<Key> as text for a Text property ("" when it has none). */
	UFUNCTION(BlueprintPure, Category = "OK Mod")
	FText Text(const FString& Key) const;
	/** The same value as plain text (what Number and Flag read). */
	FString Raw(const FString& Key) const;
	/** The same value as a number (0 when it is not one). */
	UFUNCTION(BlueprintPure, Category = "OK Mod")
	float Number(const FString& Key) const;
	/** The same value as a switch (true, or a number not 0). */
	UFUNCTION(BlueprintPure, Category = "OK Mod")
	bool Flag(const FString& Key) const;

	/** Event names a mod may raise: 1 to 64 of A-Z a-z 0-9 _. */
	static bool IsEventName(const FString& Event);
};

/** The parent class of every mod .dui panel; the ModKit sets it, a mod cannot pick another. */
UCLASS(BlueprintType, Blueprintable)
class OKMODDREAM_API UOKModDreamPanel : public UDreamTextUserWidget
{
	GENERATED_BODY()

public:
	/** The panel's road to its mod (set by the game right after it creates the panel). */
	UPROPERTY(BlueprintReadOnly, Transient, Category = "OK Mod")
	TObjectPtr<UOKModDreamBridge> Mod;
};

namespace OKModDream
{
	/** The class path of UOKModDreamPanel (what a mod widget's parent must be). */
	OKMODDREAM_API FString PanelClassPath();
	/** True when the class is a widget Blueprint class (DreamGUI or UMG), whatever its parent. */
	OKMODDREAM_API bool IsWidgetClass(const UClass* Class);
	/**
	 * A loaded package of a mod (its root `/<ModRoot>/`) that holds a widget class: true when everything in it is what
	 * the DreamGUI compiler makes from a .dui with UOKModDreamPanel as parent. Problems lists why not.
	 */
	OKMODDREAM_API bool CheckPackage(UPackage* Package, const FString& ModRoot, TArray<FString>& Problems);
	/**
	 * What a recompile of the same .dui must give again: the widget class's functions (names, parameters, bytecode),
	 * its properties and its widget tree (names and classes), as one hex hash.
	 */
	OKMODDREAM_API FString Fingerprint(UClass* WidgetClass);
}

/**
 * -run=OKModDreamCheck -Root=<mod content root> [-Out=<file>]
 * Loads every package under /<Root>/, checks those with a widget class (OKModDream::CheckPackage) and writes one line
 * per widget "<package> <fingerprint>" to -Out (or the log). Exit 1 when one fails.
 */
UCLASS()
class OKMODDREAM_API UOKModDreamCheckCommandlet : public UCommandlet
{
	GENERATED_BODY()

public:
	UOKModDreamCheckCommandlet();
	virtual int32 Main(const FString& Params) override;
};
