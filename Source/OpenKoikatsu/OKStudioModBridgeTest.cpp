// OKStudio.ModBridgeSelfTest: the studio mod bridge (OKStudioModBridge.cpp) against a fake mod written here, in a running
// studio, without the mod host. Checks registration, commands, effects (data, status, selection, playhead, run, nudge,
// scene copy), bound rows with undo / redo, keys, drags, timers, copy / delete events, timeline marks, interpolables,
// and a mod that fails leaving the studio. Writes Saved/OKStudio/mod_bridge_selftest.txt and logs PASS / FAIL lines.
#include "OKSceneDocument.h"
#include "OKStudioGame.h"
#include "OKStudioMod.h"
#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace OKStudioModBridgeTest
{
	void SetFakeHost(TSharedPtr<FJsonObject> List, TFunction<TSharedPtr<FJsonObject>(const FJsonObject&)> Dispatch);
	void Tick();
	bool HasMod(const FString& Id);
	bool Key(const FString& Mod, const FString& KeyId, bool bDown);
	bool Drag(const FString& Mod, const FString& KeyId, FVector2D Delta);
	bool FireTimers(const FString& Mod);
	FString ControlValue(const FString& Mod, const FString& Control, int32 Object);
	bool SetControl(const FString& Mod, const FString& Control, int32 Object, const FString& Value);
	FString DataText(const FString& Mod);
}

namespace
{
	const TCHAR* FakeId = TEXT("org.test.studio_bridge");

	TSharedPtr<FJsonObject> Parse(const FString& Text)
	{
		TSharedPtr<FJsonObject> O;
		FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), O);
		return O;
	}

	/** The fake mod: what it was sent and its answers. */
	struct FFakeMod
	{
		TMap<FString, int32> Count;
		TArray<int32> PassedMarks;
		FString LastCommandName;

		static TSharedRef<FJsonObject> Data(const FJsonObject& Payload)
		{
			const TSharedPtr<FJsonObject>* D = nullptr;
			TSharedRef<FJsonObject> Out = MakeShared<FJsonObject>();
			if (Payload.TryGetObjectField(TEXT("data"), D) && D && D->IsValid()) Out->Values = (*D)->Values;
			return Out;
		}

		static TSharedRef<FJsonObject> Notes(const TSharedRef<FJsonObject>& Data)
		{
			const TSharedPtr<FJsonObject>* N = nullptr;
			if (Data->TryGetObjectField(TEXT("notes"), N) && N && N->IsValid()) return N->ToSharedRef();
			TSharedRef<FJsonObject> Made = MakeShared<FJsonObject>();
			Data->SetObjectField(TEXT("notes"), Made);
			return Made;
		}

		static TSharedRef<FJsonObject> Ui()
		{
			const FString Json = TEXT(R"({
				"commands": [{"name": "mark", "label": "Mark"}, {"name": "seek", "label": "Seek"}, {"name": "run", "label": "Run"},
				             {"name": "marks", "label": "Marks"}, {"name": "export", "label": "Export"}, {"name": "select_none", "label": "None"},
				             {"name": "boom", "label": "Boom"}],
				"toolbar": [{"id": "t", "label": "T", "tooltip": "fake", "command": "mod.org.test.studio_bridge.mark"}],
				"menu": [{"id": "m", "label": "M", "command": "mod.org.test.studio_bridge.mark", "kinds": ["folder"]}],
				"controls": [{"id": "note", "label": "Note", "panel": "state", "kind": "text", "bind": "notes.{object}"},
				             {"id": "speed", "label": "Speed", "panel": "scene", "kind": "slider", "min": 0, "max": 2, "bind": "speed"}],
				"interpolables": [{"id": "w", "label": "W", "bind": "w.{object}", "per_object": true, "kinds": ["folder"]}],
				"keys": [{"id": "k", "key": "Ctrl+Alt+F9"}, {"id": "d", "key": "Ctrl+Alt+F10", "drag": true}],
				"timers": [{"id": "t1", "ms": 60000}],
				"timeline_marks": "marks",
				"objects": true
			})");
			return Parse(Json).ToSharedRef();
		}

		/** Answers one hook; null when the fake mod does not subscribe to it. */
		TSharedPtr<FJsonObject> Answer(const FString& Hook, const FJsonObject& Payload)
		{
			Count.FindOrAdd(Hook)++;
			TSharedRef<FJsonObject> R = MakeShared<FJsonObject>();
			if (Hook == TEXT("studio.panel_ui")) return Ui();
			if (Hook == TEXT("studio.command"))
			{
				Payload.TryGetStringField(TEXT("name"), LastCommandName);
				if (LastCommandName == TEXT("mark"))
				{
					TSharedRef<FJsonObject> D = Data(Payload);
					const TArray<TSharedPtr<FJsonValue>>* Sel = nullptr;
					if (Payload.TryGetArrayField(TEXT("selection"), Sel)) D->SetArrayField(TEXT("marked"), *Sel);
					R->SetObjectField(TEXT("data"), D);
					R->SetNumberField(TEXT("data_version"), 2);
					R->SetStringField(TEXT("status"), TEXT("fake: marked"));
				}
				else if (LastCommandName == TEXT("seek")) R->SetObjectField(TEXT("timeline"), Parse(TEXT(R"({"time": 1.5})")));
				else if (LastCommandName == TEXT("run")) R = Parse(TEXT(R"({"run": [{"command": "mod.org.test.studio_bridge.seek", "arg": ""}]})")).ToSharedRef();
				else if (LastCommandName == TEXT("marks")) { TSharedRef<FJsonObject> D = Data(Payload); D->SetArrayField(TEXT("marks"), { MakeShared<FJsonValueObject>(Parse(TEXT(R"({"time": 0.5})"))) }); R->SetObjectField(TEXT("data"), D); }
				else if (LastCommandName == TEXT("export")) R->SetObjectField(TEXT("export"), Parse(TEXT(R"({"name": "selftest", "keep": 1})")));
				else if (LastCommandName == TEXT("select_none")) R->SetArrayField(TEXT("select"), {});
				else if (LastCommandName == TEXT("boom")) return nullptr;
				return R;
			}
			if (Hook == TEXT("key.k"))
			{
				bool bDown = false;
				if (Payload.TryGetBoolField(TEXT("down"), bDown) && bDown) R->SetObjectField(TEXT("nudge"), Parse(TEXT(R"({"move_view": [10, 0, 0]})")));
				return R;
			}
			if (Hook == TEXT("key.d"))
			{
				FString Event;
				Payload.TryGetStringField(TEXT("event"), Event);
				if (Event == TEXT("drag")) R->SetObjectField(TEXT("nudge"), Parse(TEXT(R"({"scale": 2})")));
				return R;
			}
			if (Hook == TEXT("studio.objects_copied"))
			{
				TSharedRef<FJsonObject> D = Data(Payload);
				const TSharedRef<FJsonObject> N = Notes(D);
				const TSharedPtr<FJsonObject>* Map = nullptr;
				if (Payload.TryGetObjectField(TEXT("map"), Map) && Map && Map->IsValid())
					for (const TPair<FString, TSharedPtr<FJsonValue>>& P : (*Map)->Values)
						if (const TSharedPtr<FJsonValue> Old = N->TryGetField(P.Key)) N->SetField(FString::FromInt(int32(P.Value->AsNumber())), Old);
				R->SetObjectField(TEXT("data"), D);
				return R;
			}
			if (Hook == TEXT("studio.object_deleted"))
			{
				TSharedRef<FJsonObject> D = Data(Payload);
				const TSharedRef<FJsonObject> N = Notes(D);
				const TArray<TSharedPtr<FJsonValue>>* Ids = nullptr;
				if (Payload.TryGetArrayField(TEXT("ids"), Ids)) for (const TSharedPtr<FJsonValue>& V : *Ids) N->RemoveField(FString::FromInt(int32(V->AsNumber())));
				R->SetObjectField(TEXT("data"), D);
				return R;
			}
			if (Hook == TEXT("studio.timeline_event"))
			{
				const TArray<TSharedPtr<FJsonValue>>* Marks = nullptr;
				if (Payload.TryGetArrayField(TEXT("marks"), Marks)) for (const TSharedPtr<FJsonValue>& V : *Marks) PassedMarks.Add(int32(V->AsNumber()));
				R->SetObjectField(TEXT("timeline"), Parse(TEXT(R"({"playing": false})")));
				return R;
			}
			if (Hook.StartsWith(TEXT("timer.")) || Hook.StartsWith(TEXT("studio."))) return R;
			return nullptr;
		}

		/** The host's answer to a dispatch request ({"op":"hook"} only). */
		TSharedPtr<FJsonObject> Dispatch(const FJsonObject& Request)
		{
			FString Op, Hook, PayloadText;
			Request.TryGetStringField(TEXT("op"), Op);
			Request.TryGetStringField(TEXT("hook"), Hook);
			Request.TryGetStringField(TEXT("payload"), PayloadText);
			TSharedRef<FJsonObject> Out = MakeShared<FJsonObject>();
			Out->SetBoolField(TEXT("ok"), true);
			TArray<TSharedPtr<FJsonValue>> Replies;
			const TSharedPtr<FJsonObject> Payload = Parse(PayloadText);
			if (Op != TEXT("hook") || !Payload.IsValid()) { Out->SetBoolField(TEXT("ok"), false); Out->SetStringField(TEXT("error"), TEXT("fake host: bad request")); return Out; }
			FString Name;
			Payload->TryGetStringField(TEXT("name"), Name);
			TSharedRef<FJsonObject> Reply = MakeShared<FJsonObject>();
			Reply->SetStringField(TEXT("mod"), FakeId);
			if (Hook == TEXT("studio.command") && Name == TEXT("boom"))
			{
				Count.FindOrAdd(Hook)++;
				Reply->SetStringField(TEXT("error"), TEXT("mod panicked: fake"));
				Replies.Add(MakeShared<FJsonValueObject>(Reply));
			}
			else if (const TSharedPtr<FJsonObject> Json = Answer(Hook, *Payload))
			{
				Reply->SetObjectField(TEXT("json"), Json);
				Replies.Add(MakeShared<FJsonValueObject>(Reply));
			}
			Out->SetArrayField(TEXT("replies"), Replies);
			return Out;
		}
	};

	struct FReport
	{
		TArray<FString> Lines;
		int32 Failed = 0;
		void Check(bool bOk, const FString& What)
		{
			Lines.Add(FString::Printf(TEXT("%s %s"), bOk ? TEXT("PASS") : TEXT("FAIL"), *What));
			if (!bOk) ++Failed;
		}
	};

	void Run()
	{
		using namespace OKStudioModBridgeTest;
		UOKStudioGame* Game = UOKStudioGame::Get();
		FReport R;
		if (!Game || !Game->Document) { UE_LOG(LogTemp, Error, TEXT("ModBridgeSelfTest: the studio is not running")); return; }
		UOKSceneDocument& Doc = *Game->Document;
		FOKStudioModRegistry& Registry = FOKStudioModRegistry::Get();
		TSharedPtr<FFakeMod> Mod = MakeShared<FFakeMod>();
		FString StatusSeen;
		const TFunction<void(const FString&)> OldStatus = Registry.ShowStatus;
		Registry.ShowStatus = [&StatusSeen, OldStatus](const FString& Text) { StatusSeen = Text; if (OldStatus) OldStatus(Text); };

		// Registration.
		TSharedRef<FJsonObject> List = Parse(FString::Printf(TEXT(R"({"mods": [{"id": "%s", "state": "enabled", "dir": "", "commands": []}]})"), FakeId)).ToSharedRef();
		SetFakeHost(List, [Mod](const FJsonObject& Request) { return Mod->Dispatch(Request); });
		Tick();
		auto Owned = [](const auto& Items) { int32 N = 0; for (const auto& I : Items) N += I.Owner == FakeId; return N; };
		R.Check(HasMod(FakeId), TEXT("fake mod joined through studio.panel_ui"));
		R.Check(Owned(Registry.Commands()) == 7, FString::Printf(TEXT("7 commands registered (%d)"), Owned(Registry.Commands())));
		R.Check(Owned(Registry.ToolbarButtons()) == 1 && Owned(Registry.MenuItems()) == 1, TEXT("toolbar button and menu item registered"));
		R.Check(Owned(Registry.Controls()) == 2 && Owned(Registry.Interpolables()) == 1, TEXT("2 controls and 1 interpolable registered"));

		// An object to work on (its own undo step), selected.
		Game->BeginStep();
		const int32 A = Doc.AddObject(EOKSceneObjectKind::Folder, TEXT("ModBridgeSelfTest"));
		Game->EndStep();
		Game->SelectMany({ A }, A);
		R.Check(Mod->Count.FindRef(TEXT("studio.objects_selected")) > 0, TEXT("studio.objects_selected sent"));
		const FOKStudioModMenuItem* Menu = Registry.MenuItems().FindByPredicate([](const FOKStudioModMenuItem& M) { return M.Owner == FakeId; });
		R.Check(Menu && Menu->Visible && Menu->Visible(Doc, Game->Selection), TEXT("menu item visible on a folder"));

		// A bound row, undo and redo.
		Game->BeginStep();
		SetControl(FakeId, TEXT("note"), A, TEXT("hello"));
		Game->EndStep();
		R.Check(ControlValue(FakeId, TEXT("note"), A) == TEXT("hello"), TEXT("text row writes notes.<id>"));
		R.Check(Mod->Count.FindRef(TEXT("studio.panel_control")) > 0, TEXT("studio.panel_control sent"));
		Game->Undo();
		R.Check(ControlValue(FakeId, TEXT("note"), A).IsEmpty(), FString::Printf(TEXT("undo clears the row (\"%s\")"), *ControlValue(FakeId, TEXT("note"), A)));
		Game->Redo();
		R.Check(ControlValue(FakeId, TEXT("note"), A) == TEXT("hello"), TEXT("redo brings the row back"));
		Game->BeginStep();
		SetControl(FakeId, TEXT("speed"), -1, TEXT("1.25"));
		Game->EndStep();
		R.Check(ControlValue(FakeId, TEXT("speed"), -1) == TEXT("1.25"), FString::Printf(TEXT("slider row writes a number (%s)"), *DataText(FakeId)));

		// Commands and their effects.
		Game->SelectMany({ A }, A);
		R.Check(Game->RunUiCommand(TEXT("mod.org.test.studio_bridge.mark"), TEXT("")), TEXT("mod command runs from the command table"));
		R.Check(DataText(FakeId).Contains(FString::Printf(TEXT("\"marked\":[%d]"), A)), FString::Printf(TEXT("data effect applied (%s)"), *DataText(FakeId)));
		R.Check(StatusSeen == TEXT("fake: marked"), FString::Printf(TEXT("status effect (\"%s\")"), *StatusSeen));
		R.Check(Doc.Mods.Contains(FakeId) && Doc.Mods[FakeId].Version == 2, TEXT("data_version kept"));
		Game->RunUiCommand(TEXT("mod.org.test.studio_bridge.seek"), TEXT(""));
		R.Check(FMath::IsNearlyEqual(Game->TimelineTime, 1.5f), FString::Printf(TEXT("timeline effect moves the playhead (%.2f)"), Game->TimelineTime));
		Game->SetTimelineTime(0.f);
		Game->RunUiCommand(TEXT("mod.org.test.studio_bridge.run"), TEXT(""));
		R.Check(FMath::IsNearlyEqual(Game->TimelineTime, 1.5f), TEXT("run effect runs a studio command"));
		Game->RunUiCommand(TEXT("mod.org.test.studio_bridge.select_none"), TEXT(""));
		R.Check(Game->Selection.IsEmpty(), TEXT("select effect"));
		Game->SelectMany({ A }, A);

		// Keys and drags: nudge the selection.
		const FVector Before = Doc.WorldTransform(A).GetLocation();
		Key(FakeId, TEXT("k"), true);
		Key(FakeId, TEXT("k"), false);
		const float Moved = FVector::Dist(Before, Doc.WorldTransform(A).GetLocation());
		R.Check(FMath::IsNearlyEqual(Moved, 10.f, 0.01f), FString::Printf(TEXT("key.k nudges 10 along the view (%.3f)"), Moved));
		Drag(FakeId, TEXT("d"), FVector2D(5.f, 0.f));
		Tick();
		R.Check(FMath::IsNearlyEqual(Doc.Find(A)->Transform.GetScale3D().X, 2.f, 0.001f), TEXT("drag on key.d scales"));

		// Timers.
		FireTimers(FakeId);
		Tick();
		R.Check(Mod->Count.FindRef(TEXT("timer.t1")) == 1, TEXT("timer.t1 fires"));

		// Copy and delete events keep the per-object data in step.
		Game->BeginStep();
		const int32 B = Doc.Duplicate(A);
		Game->EndStep();
		R.Check(B >= 0 && ControlValue(FakeId, TEXT("note"), B) == TEXT("hello"), FString::Printf(TEXT("studio.objects_copied copies the note to %d"), B));
		Game->BeginStep();
		Doc.RemoveObject(B);
		Game->EndStep();
		R.Check(!DataText(FakeId).Contains(FString::Printf(TEXT("\"%d\":"), B)), TEXT("studio.object_deleted removes the note"));
		Tick(); // the deferred rest of the scene events

		// Timeline marks: playing across 0.5 sends studio.timeline_event, which stops playback.
		Game->RunUiCommand(TEXT("mod.org.test.studio_bridge.marks"), TEXT(""));
		Game->SetTimelineTime(0.f);
		Game->bTimelinePlaying = true;
		Tick();
		Game->SetTimelineTime(0.75f);
		Tick();
		R.Check(Mod->PassedMarks.Contains(0), TEXT("studio.timeline_event for the passed mark"));
		R.Check(!Game->bTimelinePlaying, TEXT("its timeline effect stops playback"));
		Game->bTimelinePlaying = false;

		// Interpolable bound to the data.
		const FOKStudioModInterpolable* W = Registry.Interpolables().FindByPredicate([](const FOKStudioModInterpolable& I) { return I.Owner == FakeId; });
		TArray<float> Sampled;
		if (W) { W->Apply(Doc, A, TArray<float>{ 0.25f }); W->Sample(Doc, A, Sampled); }
		R.Check(Sampled.Num() == 1 && FMath::IsNearlyEqual(Sampled[0], 0.25f), TEXT("interpolable applies and samples w.<id>"));

		// Scene copy.
		const FString Copy = FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir()) / TEXT("OKStudio/ModExports") / FakeId / TEXT("selftest.okscene");
		IFileManager::Get().Delete(*Copy);
		Game->RunUiCommand(TEXT("mod.org.test.studio_bridge.export"), TEXT(""));
		R.Check(IFileManager::Get().FileExists(*Copy), FString::Printf(TEXT("export writes %s"), *Copy));

		// A mod that panics leaves the studio; its data stays.
		Game->RunUiCommand(TEXT("mod.org.test.studio_bridge.boom"), TEXT(""));
		Tick(); // a failed mod goes on the next tick
		R.Check(!HasMod(FakeId) && Owned(Registry.Commands()) == 0 && Owned(Registry.Controls()) == 0, TEXT("a panicked mod is removed from the studio"));
		R.Check(Doc.Mods.Contains(FakeId), TEXT("its scene data stays"));

		// Clean up: the object, the data, the real host back.
		Game->BeginStep();
		Doc.RemoveObject(A);
		Doc.RemoveModData(FakeId);
		Doc.NotifyChanged();
		Game->EndStep();
		Registry.ShowStatus = OldStatus;
		SetFakeHost(nullptr, nullptr);
		Tick();

		R.Lines.Insert(FString::Printf(TEXT("OKStudio.ModBridgeSelfTest: %d failed of %d"), R.Failed, R.Lines.Num()), 0);
		const FString Out = FPaths::ProjectSavedDir() / TEXT("OKStudio/mod_bridge_selftest.txt");
		FFileHelper::SaveStringToFile(FString::Join(R.Lines, TEXT("\n")) + TEXT("\n"), *Out, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
		for (const FString& L : R.Lines) UE_LOG(LogTemp, Display, TEXT("ModBridgeSelfTest %s"), *L);
	}

	FAutoConsoleCommand SelfTest(TEXT("OKStudio.ModBridgeSelfTest"),
		TEXT("Runs the studio mod bridge against a fake mod (writes Saved/OKStudio/mod_bridge_selftest.txt)."),
		FConsoleCommandDelegate::CreateStatic(&Run));
}
