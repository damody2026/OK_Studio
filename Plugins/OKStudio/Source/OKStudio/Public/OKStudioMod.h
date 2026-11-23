// OK Studio's registration point for mods (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.5): commands, toolbar buttons, context menu
// items, rows of the character state and scene settings pages, and timeline interpolables. The UE mod host (OKModding)
// fills it from what each mod declares at register(); until then C++ tests register through it the same way.
// Everything here runs on the game thread. A mod never touches the document directly: it reads and writes through the
// callbacks, the host turns those into calls to the mod, and the document change is one undo step like any other.
#pragma once

#include "CoreMinimal.h"
#include "Containers/ArrayView.h"

class UOKSceneDocument;
struct FOKSceneTimelineTrack;
struct FOKSceneTimelineKeyframe;

/** Which page a mod row is drawn on: 狀態 of the selected character (KKAPI CurrentStateCategory) or 畫面設定 (SceneEffectsCategory). */
enum class EOKStudioModPanel : uint8 { CurrentState, SceneEffects,
	/** The Mod page (系統 → Mod): the mods' own page, rows for the selected object of any kind (ObjectId -1: none). */
	Mods };

/** The control a mod row shows. Values travel as text: Toggle "0"/"1", Slider a number, Dropdown the option index,
 *  Color FLinearColor::ToString(), Text the text; Button has no value and runs its Command. */
enum class EOKStudioModControlKind : uint8 { Toggle, Slider, Dropdown, Color, Text, Button };

/** A command in the studio's command table, run as "mod.<Owner>.<Name>" by buttons, menus, OKStudio.Cmd and the control
 *  channel's cmd; each run is one undo step. Run changes the scene through the document (UOKStudioGame::Get()->Document)
 *  and calls its NotifyChanged, as every studio edit does; a run that changes nothing leaves no step. */
struct FOKStudioModCommand
{
	FString Owner;
	FString Name;
	FString Label;
	TFunction<bool(const FString& Arg)> Run;
	FString Id() const { return TEXT("mod.") + Owner + TEXT(".") + Name; }
};

/** A button on the top tool row; runs a command (usually one of the mod's own). */
struct FOKStudioModToolbarButton
{
	FString Owner;
	FString Id;
	/** A few characters: the button is as small as the other top tools. */
	FString Label;
	FString Tooltip;
	FString Command;
	FString Arg;
	/** One of the studio's own icons (SIcon names: "light", "eye", "camera", …) in place of the label; none: the label. */
	FName Icon;
	/** Drawn pressed while this says so (a toggle's state; none: never). */
	TFunction<bool()> IsOn;
};

/** An entry of the object tree's context menu (KKAPI StudioContextMenus). */
struct FOKStudioModMenuItem
{
	FString Owner;
	FString Id;
	FString Label;
	FString Command;
	FString Arg;
	/** Shown only when this says so (none: always). Selection is never empty when the menu opens. */
	TFunction<bool(const UOKSceneDocument&, const TArray<int32>& Selection)> Visible;
};

/** A row of the 狀態 page (ObjectId: the selected character) or of 畫面設定 (ObjectId -1). */
struct FOKStudioModControl
{
	FString Owner;
	FString Id;
	FString Label;
	EOKStudioModPanel Panel = EOKStudioModPanel::CurrentState;
	EOKStudioModControlKind Kind = EOKStudioModControlKind::Toggle;
	float Min = 0.f, Max = 1.f, Step = 0.01f;
	TArray<FString> Options;
	TFunction<FString(const UOKSceneDocument&, int32 ObjectId)> Get;
	/** True when it changed the document (the studio then records the change). */
	TFunction<bool(UOKSceneDocument&, int32 ObjectId, const FString& Value)> Set;
	/** Button: the command it runs. */
	FString Command;
	FString Arg;
};

/** A value the timeline can key (KKAPI TimelineCompatibility): tracks of it have Owner "mod.<Owner>" and InterpolableId Id.
 *  The studio interpolates the numbers between keys and hands them to Apply. */
struct FOKStudioModInterpolable
{
	FString Owner;
	FString Id;
	FString Label;
	/** True: keyed per object (the menu offers it for the selected one); false: a scene track (ObjectId -1). */
	bool bPerObject = false;
	/** Per object: offered only for these object kinds (EOKSceneObjectKind as int; empty: every kind). */
	TArray<int32> Kinds;
	/** The value now, for a new key. */
	TFunction<bool(const UOKSceneDocument&, int32 ObjectId, TArray<float>& OutValues)> Sample;
	/** Playback: the interpolated value at the playhead. */
	TFunction<void(UOKSceneDocument&, int32 ObjectId, TConstArrayView<float> Values)> Apply;
};

class OKSTUDIO_API FOKStudioModRegistry
{
public:
	static FOKStudioModRegistry& Get();

	/** A mod id: reverse domain, letters, digits, '.', '_', '-' (mod.toml id; OK_MOD_FRAMEWORK_PLAN §5). */
	static bool IsValidOwner(const FString& Owner);
	/** A command or entry name inside a mod: letters, digits, '_', '-' (no '.', so "mod.<owner>.<name>" splits). */
	static bool IsValidName(const FString& Name);
	/** "mod.<owner>" of timeline tracks. */
	static FString TimelineOwner(const FString& Owner) { return TEXT("mod.") + Owner; }

	/** Each returns false (and logs why) for a bad id or one already taken; the same owner and id replaces nothing. */
	bool AddCommand(FOKStudioModCommand Command);
	bool AddToolbarButton(FOKStudioModToolbarButton Button);
	bool AddMenuItem(FOKStudioModMenuItem Item);
	bool AddControl(FOKStudioModControl Control);
	bool AddInterpolable(FOKStudioModInterpolable Interpolable);
	/** Drops everything the mod registered (the host disables or unloads it). */
	void RemoveOwner(const FString& Owner);

	const TArray<FOKStudioModCommand>& Commands() const { return CommandList; }
	const TArray<FOKStudioModToolbarButton>& ToolbarButtons() const { return ToolbarList; }
	const TArray<FOKStudioModMenuItem>& MenuItems() const { return MenuList; }
	const TArray<FOKStudioModControl>& Controls() const { return ControlList; }
	const TArray<FOKStudioModInterpolable>& Interpolables() const { return InterpolableList; }
	const FOKStudioModCommand* FindCommand(const FString& FullId) const;
	const FOKStudioModInterpolable* FindInterpolable(const FOKSceneTimelineTrack& Track) const;

	/** Bumped by every add and remove; the studio's command table, tool row and pages rebuild when it moves. */
	int32 Generation() const { return GenerationCounter; }

	/** Timeline glue for UOKSceneDocument: tracks whose Owner starts with "mod.". Sample: the value now (false: no such
	 *  interpolable, the track keys 0). Evaluate: interpolates the two keys linearly by Factor and applies the result. */
	static bool IsModTrack(const FOKSceneTimelineTrack& Track);
	bool SampleTimeline(const UOKSceneDocument& Document, const FOKSceneTimelineTrack& Track, TArray<float>& OutValues) const;
	bool EvaluateTimeline(UOKSceneDocument& Document, const FOKSceneTimelineTrack& Track, const FOKSceneTimelineKeyframe* K0, const FOKSceneTimelineKeyframe* K1, float Factor) const;

	/** Entries of the timeline's 添加插值轨 menu for the selected object (null: scene tracks only). */
	struct FMenuInterpolable { FString Title; FString Owner; FString Id; int32 ObjectId = -1; };
	TArray<FMenuInterpolable> InterpolableMenu(const UOKSceneDocument& Document, int32 SelectedId) const;

	// --- Scene events (KKAPI SceneCustomFunctionController), for whoever passes them on to the mods (the mod host bridge,
	// Source/OpenKoikatsu/OKStudioModBridge.cpp). The studio calls the Notify functions, one line where it happens; with
	// no sink they do nothing. Args are JSON: ids as numbers, maps as {"<old id>": <new id>}.

	/** event: scene_load {kind: load|import|clear, map?, imported_mods?}, scene_save, objects_copied {map},
	 *  objects_deleted {ids}, objects_selected {ids, primary}. Called inside the change (a mod's answer is part of its
	 *  undo step); the sink must not change objects there, only the scene's mod data. */
	TFunction<void(const FString& Event, const TSharedRef<class FJsonObject>& Args)> SceneEventSink;
	void NotifySceneLoad(const TCHAR* Kind, const TMap<int32, int32>* IdMap = nullptr, const TSharedPtr<class FJsonObject>& ImportedRoot = nullptr);
	void NotifySceneSave();
	void NotifyObjectsCopied(const TMap<int32, int32>& IdMap);
	void NotifyObjectsDeleted(const TArray<int32>& Ids);
	void NotifySelected(const TArray<int32>& Ids, int32 Primary);
	/** The id map of the last objects added with new ids (paste, import), for the Notify right after. */
	TMap<int32, int32> LastRemap;
	/** Shows a line in the studio's status bar (set by the panel while it is open). */
	TFunction<void(const FString&)> ShowStatus;

private:
	bool Check(const FString& Owner, const FString& Name, const TCHAR* What, bool bTaken) const;
	TArray<FOKStudioModCommand> CommandList;
	TArray<FOKStudioModToolbarButton> ToolbarList;
	TArray<FOKStudioModMenuItem> MenuList;
	TArray<FOKStudioModControl> ControlList;
	TArray<FOKStudioModInterpolable> InterpolableList;
	int32 GenerationCounter = 0;
};

/**
 * One edit of the studio's control channel for a mod's answer (Docs/OK_MOD_E_WAVE4.md): spawn, transform, reparent,
 * delete, select, pose, patch, duplicate, the short forms show / rename / dress (patch of bVisible, name, outfit and
 * clothes states), and the reads inspect, bones, bounds and get (studio.get: the scene state, with "id" that object).
 * The same ops and arguments as the control
 * channel's /studio/<op> (studio_spawn, studio_transform, studio_patch, … of ok-game-mcp), so an edit a mod asks for is
 * one undo step (nested in the step it belongs to) and is refused while the studio is busy. Returns {ok, error?, …}.
 */
OKSTUDIO_API TSharedRef<class FJsonObject> OKStudioRunModOp(const FString& Op, const TSharedRef<class FJsonObject>& Args);
