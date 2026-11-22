#include "OKModDreamPanel.h"

#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/PackageName.h"
#include "Misc/SecureHash.h"
#include "Modules/ModuleManager.h"
#include "UObject/Package.h"
#include "UObject/UObjectHash.h"
#include "UObject/UObjectIterator.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "Engine/BlueprintCore.h"
#if WITH_EDITOR
#include "EdGraph/EdGraph.h"
#include "EdGraph/EdGraphNode.h"
#endif

IMPLEMENT_MODULE(FDefaultModuleImpl, OKModDream)

DEFINE_LOG_CATEGORY_STATIC(LogOKModDream, Log, All);

// ---------------------------------------------------------------------------------------------------------- bridge

bool UOKModDreamBridge::IsEventName(const FString& Event)
{
	if (Event.IsEmpty() || Event.Len() > 64) return false;
	for (const TCHAR C : Event)
		if (!FChar::IsAlnum(C) && C != TEXT('_')) return false;
	return true;
}

void UOKModDreamBridge::Emit(const FString& Event) { EmitValue(Event, FString()); }

void UOKModDreamBridge::EmitValue(const FString& Event, const FString& Value)
{
	if (!IsEventName(Event))
	{
		UE_LOG(LogOKModDream, Warning, TEXT("[%s] panel event \"%s\" is not a name (A-Z a-z 0-9 _): not sent"), *ModId, *Event);
		return;
	}
	if (OnEmit) OnEmit(Event, Value);
}

FString UOKModDreamBridge::Raw(const FString& Key) const { return OnRead ? OnRead(Key) : FString(); }
FText UOKModDreamBridge::Text(const FString& Key) const { return FText::FromString(Raw(Key)); }

float UOKModDreamBridge::Number(const FString& Key) const
{
	const FString V = Raw(Key);
	return V.IsNumeric() ? FCString::Atof(*V) : (V == TEXT("true") ? 1.f : 0.f);
}

bool UOKModDreamBridge::Flag(const FString& Key) const
{
	const FString V = Raw(Key);
	return V == TEXT("true") || (V.IsNumeric() && FCString::Atof(*V) != 0.f);
}

// ---------------------------------------------------------------------------------------------------------- check

namespace
{
// Script packages a mod widget may reach (classes, structs, enums, functions' owners).
bool IsAllowedScriptPackage(const FString& Name)
{
	static const TCHAR* Exact[] = { TEXT("/Script/CoreUObject"), TEXT("/Script/Engine"), TEXT("/Script/UMG"), TEXT("/Script/SlateCore"),
		TEXT("/Script/Slate"), TEXT("/Script/FieldNotification"), TEXT("/Script/OKModDream"), TEXT("/Script/DreamTween") };
	for (const TCHAR* E : Exact) if (Name == E) return true;
	return Name.StartsWith(TEXT("/Script/DreamGUI"));
}

// Function libraries the compiler's generated code calls (DreamUIExpressionThunks: math and string operators, IsValid,
// field-notify broadcasts). Any other library function is out: a library is where "do anything" lives.
bool IsAllowedLibraryCall(const UFunction* F)
{
	const FString Owner = F->GetOwnerClass() ? F->GetOwnerClass()->GetPathName() : FString();
	if (Owner == TEXT("/Script/Engine.KismetMathLibrary") || Owner == TEXT("/Script/Engine.KismetStringLibrary")) return true;
	if (Owner == TEXT("/Script/Engine.KismetSystemLibrary")) return F->GetName() == TEXT("IsValid");
	if (Owner == TEXT("/Script/FieldNotification.FieldNotificationLibrary")) return true;
	return false;
}

bool IsGeneratedFunctionName(const FString& Name)
{
	return Name.StartsWith(TEXT("__DreamBinding_")) || Name.StartsWith(TEXT("__DreamEmit_")) || Name.StartsWith(TEXT("__DreamRoute_"))
		|| Name.EndsWith(TEXT("__DelegateSignature"));
}

// Something the widget's code or data refers to: allowed or a problem.
void CheckReference(const UObject* Ref, const UClass* Self, const FString& ModRoot, const FString& Where, TArray<FString>& Problems)
{
	if (!Ref) return;
	const UPackage* Package = Ref->GetOutermost();
	const FString PackageName = Package ? Package->GetName() : FString();
	if (const UFunction* F = Cast<UFunction>(Ref))
	{
		const UClass* Owner = F->GetOwnerClass();
		if (Owner == Self) return;
		if (Owner && Owner->IsChildOf(UOKModDreamBridge::StaticClass())) return;
		if (Owner && Owner->IsChildOf(UBlueprintFunctionLibrary::StaticClass()))
		{
			if (!IsAllowedLibraryCall(F)) Problems.Add(FString::Printf(TEXT("%s calls %s (a library function not on the list)"), *Where, *F->GetPathName()));
			return;
		}
		// A widget's own setters and events: DreamGUI and UMG classes, never a library (handled above).
		if (Owner && (PackageName.StartsWith(TEXT("/Script/DreamGUI")) || PackageName == TEXT("/Script/UMG") || PackageName == TEXT("/Script/DreamTween"))) return;
		if (Owner && Owner->IsChildOf(UOKModDreamPanel::StaticClass()) && PackageName == TEXT("/Script/OKModDream")) return;
		Problems.Add(FString::Printf(TEXT("%s calls %s"), *Where, *F->GetPathName()));
		return;
	}
	if (PackageName.StartsWith(TEXT("/Script/")))
	{
		if (!IsAllowedScriptPackage(PackageName)) Problems.Add(FString::Printf(TEXT("%s refers to %s (module not allowed)"), *Where, *Ref->GetPathName()));
		return;
	}
	// Content: this mod's own, DreamGUI's (fonts, presets) or the engine's.
	if (PackageName.StartsWith(TEXT("/") + ModRoot + TEXT("/")) || PackageName.StartsWith(TEXT("/DreamGUI/")) || PackageName.StartsWith(TEXT("/Engine/"))) return;
	Problems.Add(FString::Printf(TEXT("%s refers to %s (outside the mod)"), *Where, *Ref->GetPathName()));
}

void CheckReferencesOf(UObject* Obj, const UClass* Self, const FString& ModRoot, TArray<FString>& Problems)
{
	TArray<UObject*> Refs;
	if (UStruct* Struct = Cast<UStruct>(Obj)) Struct->CollectBytecodeReferencedObjects(Refs);
	{
		FReferenceFinder Finder(Refs, nullptr, false, true, false, false);
		Finder.FindReferences(Obj);
	}
	const FString Where = Obj->GetName();
	for (UObject* Ref : Refs)
	{
		if (!Ref || Ref == Obj || Ref->IsIn(Obj->GetOutermost())) continue;	// inside the same package: checked on its own
		CheckReference(Ref, Self, ModRoot, Where, Problems);
	}
}

bool IsEditorOnlyLeftover(const UObject* Obj)
{
#if WITH_EDITOR
	// The uncooked asset also holds the Blueprint and its graphs (editor only); cooking drops them.
	// The Blueprint keeps its own widget tree too: anything under an editor-only object goes with it.
	if (FPlatformProperties::RequiresCookedData()) return false;
	for (const UObject* O = Obj; O && !O->IsA<UPackage>(); O = O->GetOuter())
	{
		if (IsEditorOnlyObject(O) || O->IsA<UBlueprintCore>() || O->IsA<UEdGraph>() || O->IsA<UEdGraphNode>()) return true;
		// The Blueprint's skeleton and reinstancing classes (the compiler's working copies).
		if (O->IsA<UClass>() && (O->GetName().StartsWith(TEXT("SKEL_")) || O->GetName().StartsWith(TEXT("REINST_")))) return true;
		if (O->GetClass()->GetName().StartsWith(TEXT("SKEL_")) || O->GetClass()->GetName().StartsWith(TEXT("REINST_"))) return true;
	}
	return false;
#else
	return false;
#endif
}
}

FString OKModDream::PanelClassPath() { return UOKModDreamPanel::StaticClass()->GetPathName(); }

bool OKModDream::IsWidgetClass(const UClass* Class)
{
	if (!Class) return false;
	for (const UClass* Meta = Class->GetClass(); Meta; Meta = Meta->GetSuperClass())
		if (Meta->GetName() == TEXT("WidgetBlueprintGeneratedClass") || Meta->GetName() == TEXT("DreamWidgetGeneratedClass")) return true;
	return false;
}

bool OKModDream::CheckPackage(UPackage* Package, const FString& ModRoot, TArray<FString>& Problems)
{
	const int32 Before = Problems.Num();
	if (!Package) { Problems.Add(TEXT("no package")); return false; }
	TArray<UObject*> Objects;
	GetObjectsWithPackage(Package, Objects, EGetObjectsFlags::IncludeNestedObjects);
	// The widget class: one, parent UOKModDreamPanel, only the compiler's functions.
	UClass* Widget = nullptr;
	const FString ClassName = FPackageName::GetShortName(Package->GetName()) + TEXT("_C");
	for (UObject* Obj : Objects)
		if (UClass* C = Cast<UClass>(Obj); C && IsWidgetClass(C) && !IsEditorOnlyLeftover(C))
		{
			if (Widget || C->GetName() != ClassName) Problems.Add(FString::Printf(TEXT("%s: widget class %s (one, named %s)"), *Package->GetName(), *C->GetName(), *ClassName));
			else Widget = C;
		}
	if (!Widget) { Problems.Add(FString::Printf(TEXT("%s: no widget class"), *Package->GetName())); return false; }
	if (Widget->GetSuperClass() != UOKModDreamPanel::StaticClass())
		Problems.Add(FString::Printf(TEXT("%s: parent is %s, not %s"), *Widget->GetName(), *GetPathNameSafe(Widget->GetSuperClass()), *PanelClassPath()));
	for (TFieldIterator<UFunction> It(Widget, EFieldIteratorFlags::ExcludeSuper); It; ++It)
		if (!IsGeneratedFunctionName(It->GetName()))
			Problems.Add(FString::Printf(TEXT("%s: function %s is not one the .dui compiler makes (a hand-written graph?)"), *Widget->GetName(), *It->GetName()));
	UObject* Defaults = Widget->GetDefaultObject(false);
	for (UObject* Obj : Objects)
	{
		if (IsEditorOnlyLeftover(Obj)) continue;
		const bool bPart = Obj == Widget || Obj == Defaults || Obj->IsIn(Widget) || (Defaults && Obj->IsIn(Defaults));
		if (!bPart)
		{
			Problems.Add(FString::Printf(TEXT("%s (%s) is not part of the widget"), *Obj->GetPathName(), *Obj->GetClass()->GetName()));
			continue;
		}
		// Every object is of an allowed class: the widget's own (its defaults), or one from an allowed module.
		const UClass* Class = Obj->GetClass();
		const FString ClassPackage = Class->GetOutermost()->GetName();
		if (Class != Widget && !IsAllowedScriptPackage(ClassPackage))
			Problems.Add(FString::Printf(TEXT("%s is a %s (module not allowed)"), *Obj->GetName(), *Class->GetPathName()));
		CheckReferencesOf(Obj, Widget, ModRoot, Problems);
	}
	return Problems.Num() == Before;
}

FString OKModDream::Fingerprint(UClass* WidgetClass)
{
	if (!WidgetClass) return FString();
	TArray<FString> Lines;
	Lines.Add(TEXT("parent ") + GetPathNameSafe(WidgetClass->GetSuperClass()));
	for (TFieldIterator<FProperty> It(WidgetClass, EFieldIteratorFlags::ExcludeSuper); It; ++It)
		Lines.Add(FString::Printf(TEXT("property %s %s"), *It->GetName(), *It->GetCPPType()));
	for (TFieldIterator<UFunction> It(WidgetClass, EFieldIteratorFlags::ExcludeSuper); It; ++It)
	{
		UFunction* F = *It;
		FString Line = FString::Printf(TEXT("function %s script %d"), *F->GetName(), F->Script.Num());
		for (TFieldIterator<FProperty> P(F); P; ++P) Line += FString::Printf(TEXT(" %s:%s"), *P->GetName(), *P->GetCPPType());
		TArray<UObject*> Refs;
		F->CollectBytecodeReferencedObjects(Refs);
		for (UObject* R : Refs) Line += TEXT(" ->") + GetPathNameSafe(R);
		Lines.Add(Line);
	}
	// The widget tree and the rest of the class's objects (cooked or not, the same names and classes).
	TArray<UObject*> Inner;
	GetObjectsWithOuter(WidgetClass, Inner, EGetObjectsFlags::IncludeNestedObjects);
	if (UObject* Defaults = WidgetClass->GetDefaultObject(false)) GetObjectsWithOuter(Defaults, Inner, EGetObjectsFlags::IncludeNestedObjects);
	for (UObject* Obj : Inner)
		if (!Obj->IsA<UFunction>() && !IsEditorOnlyLeftover(Obj))
			Lines.Add(FString::Printf(TEXT("object %s %s"), *Obj->GetPathName(WidgetClass->GetOutermost()), *Obj->GetClass()->GetPathName()));
	Lines.Sort();
	FSHA1 Hash;
	for (const FString& L : Lines)
	{
		const FTCHARToUTF8 U(*L);
		Hash.Update(reinterpret_cast<const uint8*>(U.Get()), U.Length());
		Hash.Update(reinterpret_cast<const uint8*>("\n"), 1);
	}
	Hash.Final();
	uint8 Digest[FSHA1::DigestSize];
	Hash.GetHash(Digest);
	return BytesToHex(Digest, FSHA1::DigestSize).ToLower();
}

// ---------------------------------------------------------------------------------------------------------- commandlet

UOKModDreamCheckCommandlet::UOKModDreamCheckCommandlet()
{
	IsClient = false;
	IsEditor = true;
	LogToConsole = true;
}

int32 UOKModDreamCheckCommandlet::Main(const FString& Params)
{
	FString Root, Out;
	if (!FParse::Value(*Params, TEXT("Root="), Root) || Root.IsEmpty())
	{
		UE_LOG(LogOKModDream, Error, TEXT("OKModDreamCheck: -Root=<mod content root> is required"));
		return 2;
	}
	FParse::Value(*Params, TEXT("Out="), Out);
	IAssetRegistry& Registry = FModuleManager::LoadModuleChecked<FAssetRegistryModule>(TEXT("AssetRegistry")).Get();
	Registry.SearchAllAssets(true);
	TArray<FAssetData> Assets;
	Registry.GetAssetsByPath(FName(*(TEXT("/") + Root)), Assets, true);
	TArray<FString> Lines;
	int32 Failed = 0, Widgets = 0;
	for (const FAssetData& A : Assets)
	{
		UPackage* Package = LoadPackage(nullptr, *A.PackageName.ToString(), LOAD_None);
		if (!Package) { UE_LOG(LogOKModDream, Error, TEXT("OKModDreamCheck: cannot load %s"), *A.PackageName.ToString()); ++Failed; continue; }
		TArray<UObject*> Objects;
		GetObjectsWithPackage(Package, Objects, EGetObjectsFlags::None);
		UClass* Widget = nullptr;
		const FString ClassName = FPackageName::GetShortName(Package->GetName()) + TEXT("_C");
		for (UObject* Obj : Objects) if (UClass* C = Cast<UClass>(Obj); C && OKModDream::IsWidgetClass(C) && C->GetName() == ClassName) Widget = C;
		if (!Widget) continue;
		++Widgets;
		TArray<FString> Problems;
		if (!OKModDream::CheckPackage(Package, Root, Problems))
		{
			++Failed;
			for (const FString& P : Problems) UE_LOG(LogOKModDream, Error, TEXT("OKModDreamCheck: %s"), *P);
		}
		const FString Line = Package->GetName() + TEXT(" ") + OKModDream::Fingerprint(Widget);
		UE_LOG(LogOKModDream, Display, TEXT("OKModDreamCheck: %s"), *Line);
		Lines.Add(Line);
	}
	Lines.Sort();
	if (!Out.IsEmpty()) FFileHelper::SaveStringToFile(FString::Join(Lines, TEXT("\n")) + TEXT("\n"), *Out, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
	UE_LOG(LogOKModDream, Display, TEXT("OKModDreamCheck: %d widget(s), %d failed"), Widgets, Failed);
	return Failed ? 1 : 0;
}
