// OK Studio <-> the mod host (Docs/OK_MOD_S8_STUDIO_API.md, work item 8 of Docs/OK_MOD_FRAMEWORK_PLAN.md §15.4).
//
// The studio's registration point (Plugins/OKStudio OKStudioMod.h) is filled from what each loaded mod answers to the
// hook "studio.panel_ui", and scene events, commands, keys, timers and timeline marks reach the mod through the hooks
// studio.* / key.<id> / timer.<id> (Event::Hook of ok-mod-api, sent as {"op":"hook"} to the host, one mod at a time).
// Every payload is a JSON context (the mod's scene data, the selection, the playhead…); the mod answers with an effect
// (new scene data, status line, selection, studio commands, playhead, nudge, scene copy) as Reply::Json.
//
// A mod never touches the document: the bridge reads and writes the mod's own entry of the scene's "mods" (as JSON
// text) and applies what the mod asks for. Rows and timeline values are bound to paths in that JSON, so painting a row
// or playing the timeline never calls the mod, and undo / redo bring everything back with the document.
#include "OKModHost.h"
#include "OKSceneDocument.h"
#include "OKStreetSocialText.h"
#include "OKStudioGame.h"
#include "OKStudioMod.h"
#include "Containers/Ticker.h"
#include "Dom/JsonObject.h"
#include "Framework/Application/IInputProcessor.h"
#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "Misc/App.h"
#include "Misc/Base64.h"
#include "Misc/DelayedAutoRegister.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

DEFINE_LOG_CATEGORY_STATIC(LogOKStudioMods, Log, All);

namespace OKStudioModBridge
{
	FString Condensed(const TSharedRef<FJsonObject>& Object)
	{
		FString Out;
		FJsonSerializer::Serialize(Object, TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out));
		return Out;
	}

	FString CondensedValue(const TSharedPtr<FJsonValue>& Value)
	{
		if (!Value.IsValid() || Value->IsNull()) return FString();
		FString Out;
		switch (Value->Type)
		{
		case EJson::Object: return Condensed(Value->AsObject().ToSharedRef());
		case EJson::Array: FJsonSerializer::Serialize(Value->AsArray(), TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out)); return Out;
		case EJson::String: return Value->AsString();
		case EJson::Boolean: return Value->AsBool() ? TEXT("true") : TEXT("false");
		default: return FString::SanitizeFloat(Value->AsNumber());
		}
	}

	/** JSON text as a value; anything else as a string value. */
	TSharedPtr<FJsonValue> ParseValue(const FString& Text)
	{
		if (Text.IsEmpty()) return MakeShared<FJsonValueNull>();
		TSharedPtr<FJsonValue> Value;
		if (FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Value) && Value.IsValid()) return Value;
		return MakeShared<FJsonValueString>(Text);
	}

	const TCHAR* KindName(EOKSceneObjectKind Kind)
	{
		switch (Kind)
		{
		case EOKSceneObjectKind::Folder: return TEXT("folder");
		case EOKSceneObjectKind::Character: return TEXT("character");
		case EOKSceneObjectKind::Item: return TEXT("item");
		case EOKSceneObjectKind::Light: return TEXT("light");
		case EOKSceneObjectKind::Camera: return TEXT("camera");
		case EOKSceneObjectKind::Effect: return TEXT("effect");
		case EOKSceneObjectKind::Model: return TEXT("model");
		}
		return TEXT("object");
	}

	// --- The mod's scene data ---

	FString DataText(const UOKSceneDocument& Doc, const FString& Mod)
	{
		TArray<uint8> Bytes;
		if (!Doc.GetModData(Mod, Bytes) || Bytes.IsEmpty()) return FString();
		const FUTF8ToTCHAR Text(reinterpret_cast<const ANSICHAR*>(Bytes.GetData()), Bytes.Num());
		return FString(Text.Length(), Text.Get());
	}

	void SetDataText(UOKSceneDocument& Doc, const FString& Mod, const FString& Text, int32 Version)
	{
		const FTCHARToUTF8 Utf8(*Text);
		Doc.SetModData(Mod, Version, TConstArrayView<uint8>(reinterpret_cast<const uint8*>(Utf8.Get()), Utf8.Length()));
	}

	int32 DataVersion(const UOKSceneDocument& Doc, const FString& Mod)
	{
		const FOKSceneModData* Entry = Doc.Mods.Find(Mod);
		return Entry ? Entry->Version : 0;
	}

	/** The data as a JSON object (empty when the scene has none or it is not an object). */
	TSharedRef<FJsonObject> DataObject(const UOKSceneDocument& Doc, const FString& Mod)
	{
		const TSharedPtr<FJsonValue> V = ParseValue(DataText(Doc, Mod));
		return V.IsValid() && V->Type == EJson::Object ? V->AsObject().ToSharedRef() : MakeShared<FJsonObject>();
	}

	TArray<FString> PathKeys(const FString& Path, int32 ObjectId)
	{
		TArray<FString> Keys;
		Path.Replace(TEXT("{object}"), *FString::FromInt(ObjectId)).ParseIntoArray(Keys, TEXT("."));
		return Keys;
	}

	TSharedPtr<FJsonValue> ReadPath(const TSharedRef<FJsonObject>& Root, const FString& Path, int32 ObjectId)
	{
		const TArray<FString> Keys = PathKeys(Path, ObjectId);
		TSharedPtr<FJsonObject> At = Root;
		for (int32 I = 0; I < Keys.Num(); ++I)
		{
			const TSharedPtr<FJsonValue> V = At.IsValid() ? At->TryGetField(Keys[I]) : nullptr;
			if (!V.IsValid()) return nullptr;
			if (I == Keys.Num() - 1) return V;
			At = V->Type == EJson::Object ? V->AsObject() : nullptr;
		}
		return nullptr;
	}

	/** Sets (or with a null value removes) the value at Path, making the objects on the way. */
	void WritePath(const TSharedRef<FJsonObject>& Root, const FString& Path, int32 ObjectId, const TSharedPtr<FJsonValue>& Value)
	{
		const TArray<FString> Keys = PathKeys(Path, ObjectId);
		if (Keys.IsEmpty()) return;
		TSharedRef<FJsonObject> At = Root;
		for (int32 I = 0; I < Keys.Num() - 1; ++I)
		{
			const TSharedPtr<FJsonObject>* Next = nullptr;
			if (!At->TryGetObjectField(Keys[I], Next) || !Next || !Next->IsValid())
			{
				if (!Value.IsValid()) return;
				TSharedRef<FJsonObject> Made = MakeShared<FJsonObject>();
				At->SetObjectField(Keys[I], Made);
				At = Made;
				continue;
			}
			At = Next->ToSharedRef();
		}
		if (Value.IsValid()) At->SetField(Keys.Last(), Value); else At->RemoveField(Keys.Last());
	}

	FString ValueText(const TSharedPtr<FJsonValue>& V)
	{
		if (!V.IsValid() || V->IsNull()) return FString();
		if (V->Type == EJson::Boolean) return V->AsBool() ? TEXT("1") : TEXT("0");
		if (V->Type == EJson::Number) return FString::SanitizeFloat(V->AsNumber());
		return V->Type == EJson::String ? V->AsString() : CondensedValue(V);
	}

	// --- One studio mod ---

	struct FKeyChord
	{
		FString Id;
		FKey Key;
		bool bCtrl = false, bShift = false, bAlt = false, bDrag = false;
		bool bHeld = false;
	};

	struct FTimer
	{
		FString Id;
		double Every = 1.0;
		double Next = 0.0;
	};

	struct FMod
	{
		FString Id;
		FString Dir;
		TArray<FKeyChord> Keys;
		TArray<FTimer> Timers;
		FString MarksPath;
		bool bObjects = false;
		TMap<FString, FString> Text;
		FVector2D Drag = FVector2D::ZeroVector;
		FString DragId;
		bool bDragShift = false;
		/** Failed for good: no more calls; removed from the studio on the next tick (not inside the call that failed). */
		bool bDropped = false;
	};

	struct FState
	{
		TArray<FMod> Mods;
		TWeakObjectPtr<UOKStudioGame> Game;
		bool bBuilt = false;
		bool bReload = false;
		float LastTime = 0.f;
		bool bWasPlaying = false;
		TSharedPtr<class FInput> Input;
		/** Effects of scene events, applied after the change they answered (only their data was applied at once). */
		TArray<TPair<FString, TSharedPtr<FJsonObject>>> Deferred;
		/** The last calls and answers, for OKStudio.ModTrace and the tests. */
		TArray<FString> Trace;
		TArray<FString> DropQueue;
	};

	FState& State()
	{
		static FState S;
		return S;
	}

	/** A stand-in for the mod host (OKStudio.ModBridgeSelfTest): its listing and its answers to dispatch requests. */
	struct FFakeHost
	{
		TSharedPtr<FJsonObject> List;
		TFunction<TSharedPtr<FJsonObject>(const FJsonObject& Request)> Dispatch;
	};

	TOptional<FFakeHost>& Fake()
	{
		static TOptional<FFakeHost> F;
		return F;
	}

	bool HostOpen() { return Fake().IsSet() || FOKModHost::Get().IsOpen(); }
	TSharedPtr<FJsonObject> HostList() { return Fake().IsSet() ? Fake()->List : FOKModHost::Get().List(); }
	TSharedPtr<FJsonObject> HostDispatch(const TSharedRef<FJsonObject>& Request, FString& Error)
	{
		if (Fake().IsSet()) return Fake()->Dispatch(*Request);
		return FOKModHost::Get().DispatchJson(Request, Error);
	}

	FMod* FindMod(const FString& Id) { return State().Mods.FindByPredicate([&](const FMod& M) { return M.Id == Id; }); }

	void Note(const FString& Line)
	{
		TArray<FString>& T = State().Trace;
		T.Add(Line);
		if (T.Num() > 200) T.RemoveAt(0, T.Num() - 200);
	}

	/** A label: a text id of the mod (mod.<id>.…) from its locale files, or the text itself. */
	FString Label(const FMod& Mod, const FString& Text)
	{
		if (const FString* Found = Mod.Text.Find(Text)) return *Found;
		return Text;
	}

	void LoadLocale(FMod& Mod)
	{
		TArray<FString> Langs = { OKStreetCppText().Lang, TEXT("zh-TW"), TEXT("zh-CN"), TEXT("en") };
		for (const FString& Lang : Langs)
		{
			TArray<FString> Files;
			const FString Dir = Mod.Dir / TEXT("locale") / Lang;
			IFileManager::Get().FindFiles(Files, *(Dir / TEXT("*.toml")), true, false);
			for (const FString& File : Files)
			{
				TArray<FString> Lines;
				FFileHelper::LoadFileToStringArray(Lines, *(Dir / File));
				for (const FString& Line : Lines)
				{
					// "key" = "text" (the form the mods' locale files use; TOML escapes \" and \\ only).
					FString Key, Value;
					if (!Line.Split(TEXT("="), &Key, &Value)) continue;
					Key = Key.TrimStartAndEnd().TrimQuotes();
					Value = Value.TrimStartAndEnd();
					if (Value.Len() < 2 || !Value.StartsWith(TEXT("\"")) || !Value.EndsWith(TEXT("\""))) continue;
					Value = Value.Mid(1, Value.Len() - 2).Replace(TEXT("\\\""), TEXT("\"")).Replace(TEXT("\\\\"), TEXT("\\"));
					if (!Mod.Text.Contains(Key)) Mod.Text.Add(Key, Value);
				}
			}
		}
	}

	bool ParseChord(const FString& Text, FKeyChord& Out)
	{
		TArray<FString> Parts;
		Text.ParseIntoArray(Parts, TEXT("+"));
		if (Parts.IsEmpty()) return false;
		for (int32 I = 0; I < Parts.Num() - 1; ++I)
		{
			const FString P = Parts[I].TrimStartAndEnd();
			if (P.Contains(TEXT("Ctrl")) || P.Contains(TEXT("Control"))) Out.bCtrl = true;
			else if (P.Contains(TEXT("Shift"))) Out.bShift = true;
			else if (P.Contains(TEXT("Alt"))) Out.bAlt = true;
			else return false;
		}
		Out.Key = FKey(*Parts.Last().TrimStartAndEnd());
		return Out.Key.IsValid();
	}

	// --- Calls into a mod ---

	TSharedRef<FJsonObject> Context(const FMod& Mod)
	{
		TSharedRef<FJsonObject> C = MakeShared<FJsonObject>();
		C->SetNumberField(TEXT("studio"), 1);
		UOKStudioGame* Game = State().Game.Get();
		UOKSceneDocument* Doc = Game ? Game->Document.Get() : nullptr;
		if (!Doc) return C;
		C->SetField(TEXT("data"), ParseValue(DataText(*Doc, Mod.Id)));
		C->SetNumberField(TEXT("data_version"), DataVersion(*Doc, Mod.Id));
		TArray<TSharedPtr<FJsonValue>> Selection;
		for (int32 Id : Game->Selection) Selection.Add(MakeShared<FJsonValueNumber>(Id));
		C->SetArrayField(TEXT("selection"), Selection);
		C->SetNumberField(TEXT("primary"), Game->SelectedId);
		C->SetNumberField(TEXT("time"), Game->TimelineTime);
		C->SetNumberField(TEXT("duration"), Doc->Duration);
		C->SetBoolField(TEXT("playing"), Game->bTimelinePlaying);
		C->SetBoolField(TEXT("dirty"), Game->bDirty);
		C->SetStringField(TEXT("scene_file"), Game->File);
		if (Mod.bObjects)
		{
			TArray<TSharedPtr<FJsonValue>> Objects;
			for (const FOKSceneObject& O : Doc->Objects)
			{
				TSharedRef<FJsonObject> J = MakeShared<FJsonObject>();
				J->SetNumberField(TEXT("id"), O.Id);
				J->SetStringField(TEXT("kind"), KindName(O.Kind));
				J->SetStringField(TEXT("name"), O.Name);
				J->SetNumberField(TEXT("parent"), O.Parent);
				J->SetBoolField(TEXT("visible"), O.bVisible);
				Objects.Add(MakeShared<FJsonValueObject>(J));
			}
			C->SetArrayField(TEXT("objects"), Objects);
		}
		return C;
	}

	void Drop(const FString& Id, const FString& Why);

	/** The hook a studio event goes to (Event::Hook of ok-mod-api; the mod subscribes to the name). */
	FString HookName(const FString& Event, const TSharedRef<FJsonObject>& Args)
	{
		FString Id;
		Args->TryGetStringField(TEXT("id"), Id);
		if (Event == TEXT("key") || Event == TEXT("drag")) return TEXT("key.") + Id;
		if (Event == TEXT("timer")) return TEXT("timer.") + Id;
		if (Event == TEXT("objects_deleted")) return TEXT("studio.object_deleted");
		if (Event == TEXT("timeline_pass")) return TEXT("studio.timeline_event");
		if (Event == TEXT("control")) return TEXT("studio.panel_control");
		return TEXT("studio.") + Event;
	}

	/** Runs the mod's hook with the context as payload ({"op":"hook"} of the host); its JSON answer (null when it did
	 *  not answer — not subscribed — or failed; an object with "status" for a text answer). */
	TSharedPtr<FJsonObject> Call(const FString& Id, const FString& Hook, const TSharedRef<FJsonObject>& Ctx)
	{
		TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
		Request->SetStringField(TEXT("op"), TEXT("hook"));
		Request->SetStringField(TEXT("hook"), Hook);
		Request->SetStringField(TEXT("payload"), Condensed(Ctx));
		Request->SetArrayField(TEXT("mods"), { MakeShared<FJsonValueString>(Id) });
		FString Error;
		if (const FMod* Known = FindMod(Id); Known && Known->bDropped) return nullptr;
		const TSharedPtr<FJsonObject> Answer = HostDispatch(Request, Error);
		if (!Answer.IsValid()) { UE_LOG(LogOKStudioMods, Warning, TEXT("%s %s: %s"), *Id, *Hook, *Error); return nullptr; }
		Note(FString::Printf(TEXT("%s %s -> %s"), *Id, *Hook, *Condensed(Answer.ToSharedRef()).Left(300)));
		// The mod's reply: an entry of "replies" ({mod, json|text|error}); a host answering one mod flat is read the same.
		TSharedPtr<FJsonObject> Reply;
		const TArray<TSharedPtr<FJsonValue>>* Replies = nullptr;
		if (Answer->TryGetArrayField(TEXT("replies"), Replies))
		{
			for (const TSharedPtr<FJsonValue>& V : *Replies)
			{
				const TSharedPtr<FJsonObject> R = V->AsObject();
				FString Mod;
				if (R && R->TryGetStringField(TEXT("mod"), Mod) && Mod == Id) Reply = R;
			}
		}
		else Reply = Answer;
		bool bOk = true;
		Answer->TryGetBoolField(TEXT("ok"), bOk);
		FString Why;
		if (!bOk || (Reply.IsValid() && Reply->TryGetStringField(TEXT("error"), Why)))
		{
			if (Why.IsEmpty()) Answer->TryGetStringField(TEXT("error"), Why);
			UE_LOG(LogOKStudioMods, Warning, TEXT("%s %s failed: %s"), *Id, *Hook, *Why);
			// A mod that panicked (or was turned off) is gone from the studio; its data stays in the scene.
			if (Why.Contains(TEXT("not enabled")) || Why.Contains(TEXT("panicked"))) Drop(Id, Why);
			else if (FOKStudioModRegistry::Get().ShowStatus) FOKStudioModRegistry::Get().ShowStatus(FString::Printf(TEXT("%s：%s"), *Id, *Why));
			return nullptr;
		}
		if (!Reply.IsValid()) return nullptr;
		const TSharedPtr<FJsonObject>* Json = nullptr;
		if (Reply->TryGetObjectField(TEXT("json"), Json) && Json && Json->IsValid()) return *Json;
		FString Text;
		if (!Reply->TryGetStringField(TEXT("text"), Text)) return nullptr;
		TSharedRef<FJsonObject> Status = MakeShared<FJsonObject>();
		Status->SetStringField(TEXT("status"), Text);
		return Status;
	}

	// --- Effects ---

	void Nudge(UOKStudioGame& Game, const FJsonObject& N)
	{
		UOKSceneDocument& Doc = *Game.Document;
		const FRotator View(Game.Pitch, Game.Yaw, 0.f);
		const TArray<TSharedPtr<FJsonValue>>* Move = nullptr;
		const TArray<TSharedPtr<FJsonValue>>* Turn = nullptr;
		double Scale = 1.0;
		N.TryGetArrayField(TEXT("move_view"), Move);
		N.TryGetArrayField(TEXT("rotate"), Turn);
		N.TryGetNumberField(TEXT("scale"), Scale);
		auto At = [](const TArray<TSharedPtr<FJsonValue>>* A, int32 I) { return A && A->IsValidIndex(I) ? (*A)[I]->AsNumber() : 0.0; };
		const FVector Delta = Move ? View.RotateVector(FVector(At(Move, 2), At(Move, 0), At(Move, 1))) : FVector::ZeroVector;
		const FQuat Spin = Turn ? FQuat(FRotator(At(Turn, 0), At(Turn, 1), At(Turn, 2))) : FQuat::Identity;
		for (int32 Id : Game.SelectionRoots())
		{
			FOKSceneObject* O = Doc.Find(Id);
			if (!O) continue;
			const FTransform World = Doc.WorldTransform(Id);
			const FTransform Parent = Doc.ParentFrame(Id);
			if (!Delta.IsNearlyZero()) O->Transform.SetLocation(Parent.InverseTransformPosition(World.GetLocation() + Delta));
			if (!Spin.Equals(FQuat::Identity)) O->Transform.SetRotation(Parent.GetRotation().Inverse() * (Spin * World.GetRotation()));
			if (!FMath::IsNearlyEqual(Scale, 1.0)) O->Transform.SetScale3D(O->Transform.GetScale3D() * Scale);
		}
		Doc.NotifyChanged();
	}

	void Export(UOKStudioGame& Game, const FString& Mod, const FJsonObject& E)
	{
		FString Name;
		int32 Keep = 5;
		E.TryGetStringField(TEXT("name"), Name);
		E.TryGetNumberField(TEXT("keep"), Keep);
		// The mod names the file only: letters, digits, '-', '_' in the mod's own folder.
		FString Safe;
		for (TCHAR C : Name) if (FChar::IsAlnum(C) || C == TEXT('-') || C == TEXT('_')) Safe.AppendChar(C);
		if (Safe.IsEmpty()) return;
		const FString Dir = FPaths::ProjectSavedDir() / TEXT("OKStudio/ModExports") / Mod;
		IFileManager::Get().MakeDirectory(*Dir, true);
		FString Error;
		if (!Game.Document->SaveToFile(Dir / Safe + TEXT(".okscene"), Error)) { UE_LOG(LogOKStudioMods, Warning, TEXT("%s: export %s: %s"), *Mod, *Safe, *Error); return; }
		TArray<FString> Files;
		IFileManager::Get().FindFiles(Files, *(Dir / TEXT("*.okscene")), true, false);
		Files.Sort();
		for (int32 I = 0; I < Files.Num() - FMath::Clamp(Keep, 1, 100); ++I) IFileManager::Get().Delete(*(Dir / Files[I]));
		UE_LOG(LogOKStudioMods, Display, TEXT("%s: scene copy %s"), *Mod, *FPaths::ConvertRelativePathToFull(Dir / Safe + TEXT(".okscene")));
	}

	/** The data part of an effect (applied at once, inside the change the mod answered). */
	void ApplyData(UOKStudioGame& Game, const FString& Mod, const FJsonObject& Effect)
	{
		UOKSceneDocument& Doc = *Game.Document;
		bool bClear = false;
		if (Effect.TryGetBoolField(TEXT("clear_data"), bClear) && bClear) { if (Doc.RemoveModData(Mod)) Doc.NotifyChanged(); return; }
		const TSharedPtr<FJsonValue> Data = Effect.TryGetField(TEXT("data"));
		if (!Data.IsValid()) return;
		int32 Version = DataVersion(Doc, Mod);
		Effect.TryGetNumberField(TEXT("data_version"), Version);
		if (Data->IsNull()) { if (Doc.RemoveModData(Mod)) Doc.NotifyChanged(); return; }
		const FString Text = CondensedValue(Data);
		if (DataText(Doc, Mod) == Text && DataVersion(Doc, Mod) == Version) return;
		SetDataText(Doc, Mod, Text, Version);
		Doc.NotifyChanged();
	}

	/** Everything else: status, selection, commands, playhead, nudge, scene copy. */
	void ApplyRest(UOKStudioGame& Game, const FString& Mod, const FJsonObject& Effect)
	{
		FString Status;
		if (Effect.TryGetStringField(TEXT("status"), Status) && FOKStudioModRegistry::Get().ShowStatus) FOKStudioModRegistry::Get().ShowStatus(Status);
		const TArray<TSharedPtr<FJsonValue>>* Select = nullptr;
		if (Effect.TryGetArrayField(TEXT("select"), Select))
		{
			TArray<int32> Ids;
			for (const TSharedPtr<FJsonValue>& V : *Select) Ids.Add(int32(V->AsNumber()));
			Game.SelectMany(Ids, Ids.Num() ? Ids.Last() : -1);
		}
		const TSharedPtr<FJsonObject>* Nudge_ = nullptr;
		if (Effect.TryGetObjectField(TEXT("nudge"), Nudge_) && Nudge_ && Nudge_->IsValid()) Nudge(Game, **Nudge_);
		const TSharedPtr<FJsonObject>* Timeline = nullptr;
		if (Effect.TryGetObjectField(TEXT("timeline"), Timeline) && Timeline && Timeline->IsValid())
		{
			double Time = 0.0;
			bool bPlaying = false;
			if ((*Timeline)->TryGetNumberField(TEXT("time"), Time)) { Game.SetTimelineTime(float(Time)); State().LastTime = float(Time); }
			if ((*Timeline)->TryGetBoolField(TEXT("playing"), bPlaying)) Game.bTimelinePlaying = bPlaying;
		}
		const TSharedPtr<FJsonObject>* ExportJson = nullptr;
		if (Effect.TryGetObjectField(TEXT("export"), ExportJson) && ExportJson && ExportJson->IsValid()) Export(Game, Mod, **ExportJson);
		const TArray<TSharedPtr<FJsonValue>>* Run = nullptr;
		if (Effect.TryGetArrayField(TEXT("run"), Run))
			for (const TSharedPtr<FJsonValue>& V : *Run)
			{
				const TSharedPtr<FJsonObject> R = V->AsObject();
				FString Command, Arg;
				if (!R || !R->TryGetStringField(TEXT("command"), Command)) continue;
				R->TryGetStringField(TEXT("arg"), Arg);
				if (!Game.RunUiCommand(Command, Arg)) UE_LOG(LogOKStudioMods, Warning, TEXT("%s: studio command %s failed"), *Mod, *Command);
			}
	}

	void Apply(const FString& Mod, const TSharedPtr<FJsonObject>& Effect, bool bDeferRest)
	{
		UOKStudioGame* Game = State().Game.Get();
		if (!Game || !Game->Document || !Effect.IsValid()) return;
		ApplyData(*Game, Mod, *Effect);
		if (bDeferRest) State().Deferred.Add({ Mod, Effect }); else ApplyRest(*Game, Mod, *Effect);
	}

	/** A scene event to one mod: its answer's data now, the rest after the change. */
	void SendEvent(FMod& Mod, const FString& Event, const TSharedRef<FJsonObject>& Args, bool bDeferRest)
	{
		TSharedRef<FJsonObject> Ctx = Context(Mod);
		for (const TPair<FString, TSharedPtr<FJsonValue>>& P : Args->Values) Ctx->SetField(P.Key, P.Value);
		Ctx->SetStringField(TEXT("event"), Event);
		// An imported scene's data of this mod, as the mod wrote it.
		const TSharedPtr<FJsonObject>* Imported = nullptr;
		if (Args->TryGetObjectField(TEXT("imported_mods"), Imported) && Imported && Imported->IsValid())
		{
			Ctx->RemoveField(TEXT("imported_mods"));
			const TSharedPtr<FJsonObject>* Entry = nullptr;
			FString Base64;
			TArray<uint8> Bytes;
			if ((*Imported)->TryGetObjectField(Mod.Id, Entry) && Entry && (*Entry)->TryGetStringField(TEXT("data"), Base64) && FBase64::Decode(Base64, Bytes))
			{
				const FUTF8ToTCHAR Text(reinterpret_cast<const ANSICHAR*>(Bytes.GetData()), Bytes.Num());
				Ctx->SetField(TEXT("imported_data"), ParseValue(FString(Text.Length(), Text.Get())));
			}
		}
		const FString Id = Mod.Id;
		Apply(Id, Call(Id, HookName(Event, Args), Ctx), bDeferRest);
	}

	void Broadcast(const FString& Event, const TSharedRef<FJsonObject>& Args, bool bDeferRest)
	{
		TArray<FString> Ids;
		for (const FMod& M : State().Mods) Ids.Add(M.Id);
		for (const FString& Id : Ids) if (FMod* M = FindMod(Id)) SendEvent(*M, Event, Args, bDeferRest);
	}

	/** A key, timer or drag event outside any command: one undo step of its own (a drag joins the drag before it). */
	void SendInputEvent(FMod& Mod, const FString& Event, const TSharedRef<FJsonObject>& Args, bool bStep)
	{
		UOKStudioGame* Game = State().Game.Get();
		if (!Game) return;
		if (bStep) Game->BeginStep();
		SendEvent(Mod, Event, Args, false);
		if (bStep && State().Game.IsValid()) Game->EndStep();
	}

	// --- Registration ---

	bool RunModCommand(const FString& Id, const FString& Name, const FString& Arg)
	{
		FMod* Mod = FindMod(Id);
		if (!Mod) return false;
		TSharedRef<FJsonObject> Ctx = Context(*Mod);
		Ctx->SetStringField(TEXT("event"), TEXT("command"));
		Ctx->SetStringField(TEXT("name"), Name);
		Ctx->SetStringField(TEXT("arg"), Arg);
		const TSharedPtr<FJsonObject> Effect = Call(Id, TEXT("studio.command"), Ctx);
		if (!Effect.IsValid()) return false;
		Apply(Id, Effect, false);
		return true;
	}

	EOKStudioModControlKind ControlKind(const FString& Kind)
	{
		if (Kind == TEXT("slider")) return EOKStudioModControlKind::Slider;
		if (Kind == TEXT("dropdown")) return EOKStudioModControlKind::Dropdown;
		if (Kind == TEXT("color")) return EOKStudioModControlKind::Color;
		if (Kind == TEXT("text")) return EOKStudioModControlKind::Text;
		if (Kind == TEXT("button")) return EOKStudioModControlKind::Button;
		return EOKStudioModControlKind::Toggle;
	}

	/** A row's value written into the data as its kind keeps it: toggle a bool, slider / dropdown a number, else text. */
	TSharedPtr<FJsonValue> RowValue(EOKStudioModControlKind Kind, const FString& Value)
	{
		switch (Kind)
		{
		case EOKStudioModControlKind::Toggle: return MakeShared<FJsonValueBoolean>(Value == TEXT("1") || Value.ToBool());
		case EOKStudioModControlKind::Slider: case EOKStudioModControlKind::Dropdown: return MakeShared<FJsonValueNumber>(FCString::Atod(*Value));
		default: if (Value.IsEmpty()) return nullptr; return MakeShared<FJsonValueString>(Value);
		}
	}

	void Register(FMod& Mod, const FJsonObject& Ui)
	{
		FOKStudioModRegistry& R = FOKStudioModRegistry::Get();
		const FString Id = Mod.Id;
		auto Each = [&Ui](const TCHAR* Field, TFunctionRef<void(const FJsonObject&)> Do)
		{
			const TArray<TSharedPtr<FJsonValue>>* List = nullptr;
			if (Ui.TryGetArrayField(Field, List)) for (const TSharedPtr<FJsonValue>& V : *List) if (const TSharedPtr<FJsonObject> O = V->AsObject()) Do(*O);
		};
		auto Str = [](const FJsonObject& O, const TCHAR* F) { FString S; O.TryGetStringField(F, S); return S; };
		Each(TEXT("commands"), [&](const FJsonObject& C)
		{
			const FString Name = Str(C, TEXT("name"));
			R.AddCommand({ Id, Name, Label(Mod, Str(C, TEXT("label"))), [Id, Name](const FString& Arg) { return RunModCommand(Id, Name, Arg); } });
		});
		Each(TEXT("toolbar"), [&](const FJsonObject& B)
		{
			R.AddToolbarButton({ Id, Str(B, TEXT("id")), Label(Mod, Str(B, TEXT("label"))), Label(Mod, Str(B, TEXT("tooltip"))), Str(B, TEXT("command")), Str(B, TEXT("arg")) });
		});
		Each(TEXT("menu"), [&](const FJsonObject& M)
		{
			TArray<FString> Kinds;
			M.TryGetStringArrayField(TEXT("kinds"), Kinds);
			FOKStudioModMenuItem Item{ Id, Str(M, TEXT("id")), Label(Mod, Str(M, TEXT("label"))), Str(M, TEXT("command")), Str(M, TEXT("arg")), nullptr };
			if (!Kinds.IsEmpty())
				Item.Visible = [Kinds](const UOKSceneDocument& Doc, const TArray<int32>& Selection)
				{
					const FOKSceneObject* O = Selection.Num() ? Doc.Find(Selection.Last()) : nullptr;
					return O && Kinds.Contains(KindName(O->Kind));
				};
			R.AddMenuItem(MoveTemp(Item));
		});
		Each(TEXT("controls"), [&](const FJsonObject& C)
		{
			FOKStudioModControl Control;
			Control.Owner = Id;
			Control.Id = Str(C, TEXT("id"));
			Control.Label = Label(Mod, Str(C, TEXT("label")));
			Control.Panel = Str(C, TEXT("panel")) == TEXT("scene") ? EOKStudioModPanel::SceneEffects : EOKStudioModPanel::CurrentState;
			Control.Kind = ControlKind(Str(C, TEXT("kind")));
			double Min = 0, Max = 1, Step = 0.01;
			C.TryGetNumberField(TEXT("min"), Min); C.TryGetNumberField(TEXT("max"), Max); C.TryGetNumberField(TEXT("step"), Step);
			Control.Min = float(Min); Control.Max = float(Max); Control.Step = float(Step);
			TArray<FString> Options;
			C.TryGetStringArrayField(TEXT("options"), Options);
			for (const FString& O : Options) Control.Options.Add(Label(Mod, O));
			Control.Command = Str(C, TEXT("command"));
			Control.Arg = Str(C, TEXT("arg"));
			const FString Bind = Str(C, TEXT("bind"));
			const FString ControlId = Control.Id;
			const EOKStudioModControlKind Kind = Control.Kind;
			if (!Bind.IsEmpty())
			{
				Control.Get = [Id, Bind](const UOKSceneDocument& Doc, int32 Object) { return ValueText(ReadPath(DataObject(Doc, Id), Bind, Object)); };
				Control.Set = [Id, Bind, Kind, ControlId](UOKSceneDocument& Doc, int32 Object, const FString& Value)
				{
					TSharedRef<FJsonObject> Data = DataObject(Doc, Id);
					WritePath(Data, Bind, Object, RowValue(Kind, Value));
					if (Data->Values.IsEmpty()) Doc.RemoveModData(Id); else SetDataText(Doc, Id, Condensed(Data), FMath::Max(1, DataVersion(Doc, Id)));
					// The mod hears of it when it asked to (it may change more of its data in the same step).
					if (FMod* M = FindMod(Id))
					{
						TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
						Args->SetStringField(TEXT("id"), ControlId);
						Args->SetNumberField(TEXT("object"), Object);
						Args->SetStringField(TEXT("value"), Value);
						SendEvent(*M, TEXT("control"), Args, true);
					}
					return true;
				};
			}
			R.AddControl(MoveTemp(Control));
		});
		Each(TEXT("interpolables"), [&](const FJsonObject& I)
		{
			FOKStudioModInterpolable Interp;
			Interp.Owner = Id;
			Interp.Id = Str(I, TEXT("id"));
			Interp.Label = Label(Mod, Str(I, TEXT("label")));
			I.TryGetBoolField(TEXT("per_object"), Interp.bPerObject);
			TArray<FString> Kinds;
			I.TryGetStringArrayField(TEXT("kinds"), Kinds);
			for (int32 K = 0; K <= int32(EOKSceneObjectKind::Model); ++K) if (Kinds.Contains(KindName(EOKSceneObjectKind(K)))) Interp.Kinds.Add(K);
			const FString Bind = Str(I, TEXT("bind"));
			Interp.Sample = [Id, Bind](const UOKSceneDocument& Doc, int32 Object, TArray<float>& Out)
			{
				const TSharedPtr<FJsonValue> V = ReadPath(DataObject(Doc, Id), Bind, Object);
				if (!V.IsValid()) return false;
				if (V->Type == EJson::Number) { Out = { float(V->AsNumber()) }; return true; }
				if (V->Type == EJson::Array) { for (const TSharedPtr<FJsonValue>& E : V->AsArray()) Out.Add(float(E->AsNumber())); return !Out.IsEmpty(); }
				return false;
			};
			// Playback writes the value into the data (no undo step: the timeline is not recorded while it plays).
			Interp.Apply = [Id, Bind](UOKSceneDocument& Doc, int32 Object, TConstArrayView<float> Values)
			{
				TSharedRef<FJsonObject> Data = DataObject(Doc, Id);
				if (Values.Num() == 1) WritePath(Data, Bind, Object, MakeShared<FJsonValueNumber>(Values[0]));
				else { TArray<TSharedPtr<FJsonValue>> A; for (float V : Values) A.Add(MakeShared<FJsonValueNumber>(V)); WritePath(Data, Bind, Object, MakeShared<FJsonValueArray>(A)); }
				SetDataText(Doc, Id, Condensed(Data), FMath::Max(1, DataVersion(Doc, Id)));
			};
			R.AddInterpolable(MoveTemp(Interp));
		});
		Each(TEXT("keys"), [&](const FJsonObject& K)
		{
			FKeyChord Chord;
			Chord.Id = Str(K, TEXT("id"));
			K.TryGetBoolField(TEXT("drag"), Chord.bDrag);
			if (ParseChord(Str(K, TEXT("key")), Chord)) Mod.Keys.Add(Chord);
			else UE_LOG(LogOKStudioMods, Warning, TEXT("%s: key \"%s\" not understood"), *Id, *Str(K, TEXT("key")));
		});
		Each(TEXT("timers"), [&](const FJsonObject& T)
		{
			double Ms = 1000;
			T.TryGetNumberField(TEXT("ms"), Ms);
			const double Every = FMath::Max(Ms, 50.0) / 1000.0;
			Mod.Timers.Add({ Str(T, TEXT("id")), Every, FPlatformTime::Seconds() + Every });
		});
		Ui.TryGetStringField(TEXT("timeline_marks"), Mod.MarksPath);
		Ui.TryGetBoolField(TEXT("objects"), Mod.bObjects);
	}

	void Teardown()
	{
		FState& S = State();
		for (const FMod& M : S.Mods) FOKStudioModRegistry::Get().RemoveOwner(M.Id);
		S.Mods.Reset();
		S.Deferred.Reset();
		S.DropQueue.Reset();
		FOKStudioModRegistry::Get().SceneEventSink = nullptr;
		S.bBuilt = false;
	}

	void Drop(const FString& Id, const FString& Why)
	{
		UE_LOG(LogOKStudioMods, Warning, TEXT("%s left the studio: %s"), *Id, *Why);
		// Its command may be the one running now: the registry entry and FMod go on the next tick.
		if (FMod* M = FindMod(Id)) M->bDropped = true;
		State().DropQueue.AddUnique(Id);
		if (FOKStudioModRegistry::Get().ShowStatus) FOKStudioModRegistry::Get().ShowStatus(FString::Printf(TEXT("mod %s 已停用：%s"), *Id, *Why));
	}

	void RemoveDropped()
	{
		FState& S = State();
		for (const FString& Id : S.DropQueue)
		{
			FOKStudioModRegistry::Get().RemoveOwner(Id);
			S.Mods.RemoveAll([&](const FMod& M) { return M.Id == Id; });
		}
		S.DropQueue.Reset();
	}

	void Build()
	{
		Teardown();
		FState& S = State();
		S.bBuilt = true;
		const TSharedPtr<FJsonObject> List = HostList();
		const TArray<TSharedPtr<FJsonValue>>* Mods = nullptr;
		if (!List.IsValid() || !List->TryGetArrayField(TEXT("mods"), Mods)) return;
		for (const TSharedPtr<FJsonValue>& V : *Mods)
		{
			const TSharedPtr<FJsonObject> M = V->AsObject();
			FString Id, StateName, Dir;
			if (!M || !M->TryGetStringField(TEXT("id"), Id)) continue;
			M->TryGetStringField(TEXT("state"), StateName);
			M->TryGetStringField(TEXT("dir"), Dir);
			if (StateName != TEXT("enabled")) continue;
			FMod Mod;
			Mod.Id = Id;
			Mod.Dir = Dir;
			LoadLocale(Mod);
			TSharedRef<FJsonObject> Ctx = Context(Mod);
			Ctx->SetNumberField(TEXT("protocol"), 1);
			const TSharedPtr<FJsonObject> Ui = Call(Id, TEXT("studio.panel_ui"), Ctx);
			if (!Ui.IsValid()) continue;
			S.Mods.Add(MoveTemp(Mod));
			Register(S.Mods.Last(), *Ui);
			UE_LOG(LogOKStudioMods, Display, TEXT("%s joined the studio (%d keys, %d timers)"), *Id, S.Mods.Last().Keys.Num(), S.Mods.Last().Timers.Num());
		}
		FOKStudioModRegistry::Get().SceneEventSink = [](const FString& Event, const TSharedRef<FJsonObject>& Args) { Broadcast(Event, Args, true); };
		S.LastTime = S.Game.IsValid() ? S.Game->TimelineTime : 0.f;
	}

	// --- Keys and mouse ---

	bool Typing()
	{
		const TSharedPtr<SWidget> Focus = FSlateApplication::Get().GetKeyboardFocusedWidget();
		return Focus.IsValid() && Focus->GetType().ToString().Contains(TEXT("EditableText"));
	}

	class FInput : public IInputProcessor
	{
	public:
		virtual void Tick(const float, FSlateApplication&, TSharedRef<ICursor>) override {}
		virtual bool HandleKeyDownEvent(FSlateApplication&, const FKeyEvent& E) override
		{
			if (!State().Game.IsValid() || Typing()) return false;
			for (FMod& Mod : State().Mods)
				for (FKeyChord& K : Mod.Keys)
				{
					// A drag key may be held with Shift (another direction); the other modifiers must match.
					if (E.GetKey() != K.Key || E.IsControlDown() != K.bCtrl || E.IsAltDown() != K.bAlt || (!K.bDrag && E.IsShiftDown() != K.bShift)) continue;
					if (K.bHeld || E.IsRepeat()) return true;
					K.bHeld = true;
					TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
					Args->SetStringField(TEXT("id"), K.Id);
					Args->SetBoolField(TEXT("down"), true);
					Args->SetBoolField(TEXT("shift"), E.IsShiftDown());
					SendInputEvent(Mod, TEXT("key"), Args, true);
					return true;
				}
			return false;
		}
		virtual bool HandleKeyUpEvent(FSlateApplication&, const FKeyEvent& E) override
		{
			for (FMod& Mod : State().Mods)
				for (FKeyChord& K : Mod.Keys)
				{
					if (!K.bHeld || E.GetKey() != K.Key) continue;
					K.bHeld = false;
					TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
					Args->SetStringField(TEXT("id"), K.Id);
					Args->SetBoolField(TEXT("down"), false);
					SendInputEvent(Mod, TEXT("key"), Args, true);
					return true;
				}
			return false;
		}
		virtual bool HandleMouseMoveEvent(FSlateApplication&, const FPointerEvent& E) override
		{
			for (FMod& Mod : State().Mods)
				for (const FKeyChord& K : Mod.Keys)
					if (K.bHeld && K.bDrag) { Mod.Drag += E.GetCursorDelta(); Mod.DragId = K.Id; Mod.bDragShift = E.IsShiftDown(); }
			return false;
		}
		virtual const TCHAR* GetDebugName() const override { return TEXT("OKStudioMods"); }
	};

	// --- Per frame: the studio coming and going, deferred effects, timers, drags, timeline marks ---

	TArray<float> MarkTimes(const UOKSceneDocument& Doc, const FMod& Mod)
	{
		TArray<float> Out;
		const TSharedPtr<FJsonValue> V = ReadPath(DataObject(Doc, Mod.Id), Mod.MarksPath, -1);
		if (!V.IsValid() || V->Type != EJson::Array) return Out;
		for (const TSharedPtr<FJsonValue>& M : V->AsArray())
		{
			double T = -1.0;
			if (M->Type == EJson::Number) T = M->AsNumber();
			else if (const TSharedPtr<FJsonObject> O = M->AsObject()) O->TryGetNumberField(TEXT("time"), T);
			Out.Add(float(T));
		}
		return Out;
	}

	void TickMarks(UOKStudioGame& Game)
	{
		FState& S = State();
		const float Now = Game.TimelineTime;
		const float Before = S.LastTime;
		const bool bPlaying = Game.bTimelinePlaying;
		S.LastTime = Now;
		if (!bPlaying || !S.bWasPlaying) { S.bWasPlaying = bPlaying; return; }
		S.bWasPlaying = bPlaying;
		if (FMath::IsNearlyEqual(Now, Before)) return;
		// Passed: in (Before, Now], or across the loop's wrap to the start.
		const bool bWrapped = Now < Before;
		auto Passed = [&](float T) { return T >= 0.f && (bWrapped ? (T > Before || T <= Now) : (T > Before && T <= Now)); };
		TArray<FString> Ids;
		for (const FMod& M : S.Mods) if (!M.MarksPath.IsEmpty()) Ids.Add(M.Id);
		for (const FString& Id : Ids)
		{
			FMod* Mod = FindMod(Id);
			if (!Mod || !Game.Document) continue;
			const TArray<float> Times = MarkTimes(*Game.Document, *Mod);
			TArray<int32> Order;
			for (int32 I = 0; I < Times.Num(); ++I) if (Passed(Times[I])) Order.Add(I);
			if (Order.IsEmpty()) continue;
			// Earliest first (after a wrap, the ones before the end first).
			Order.Sort([&](int32 A, int32 B) { const float TA = bWrapped && Times[A] <= Now ? Times[A] + 1e6f : Times[A], TB = bWrapped && Times[B] <= Now ? Times[B] + 1e6f : Times[B]; return TA < TB; });
			TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
			TArray<TSharedPtr<FJsonValue>> Marks;
			for (int32 I : Order) Marks.Add(MakeShared<FJsonValueNumber>(I));
			Args->SetArrayField(TEXT("marks"), Marks);
			Args->SetNumberField(TEXT("from"), Before);
			SendEvent(*Mod, TEXT("timeline_pass"), Args, false);
		}
	}

	bool Tick(float)
	{
		FState& S = State();
		UOKStudioGame* Game = UOKStudioGame::Get();
		if (Game != S.Game.Get() || S.bReload)
		{
			S.bReload = false;
			if (S.bBuilt) Teardown();
			S.Game = Game;
			if (Game && HostOpen()) Build();
			if (Game && !S.Input.IsValid() && FSlateApplication::IsInitialized())
			{
				S.Input = MakeShared<FInput>();
				FSlateApplication::Get().RegisterInputPreProcessor(S.Input);
			}
		}
		RemoveDropped();
		if (!Game) return true;
		// The host opens when the studio mode starts, which may be after the studio itself.
		if (!S.bBuilt && HostOpen()) Build();
		if (!Game->Document) return true;
		if (S.Deferred.Num())
		{
			TArray<TPair<FString, TSharedPtr<FJsonObject>>> Now = MoveTemp(S.Deferred);
			for (const TPair<FString, TSharedPtr<FJsonObject>>& D : Now) ApplyRest(*Game, D.Key, *D.Value);
		}
		const double Seconds = FPlatformTime::Seconds();
		TArray<TPair<FString, FString>> Due;
		for (FMod& Mod : S.Mods)
			for (FTimer& T : Mod.Timers)
				if (Seconds >= T.Next) { T.Next = Seconds + T.Every; Due.Add({ Mod.Id, T.Id }); }
		for (const TPair<FString, FString>& D : Due)
			if (FMod* Mod = FindMod(D.Key))
			{
				TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
				Args->SetStringField(TEXT("id"), D.Value);
				SendInputEvent(*Mod, TEXT("timer"), Args, true);
			}
		TArray<FString> Dragging;
		for (const FMod& Mod : S.Mods) if (!Mod.Drag.IsNearlyZero()) Dragging.Add(Mod.Id);
		for (const FString& Id : Dragging)
			if (FMod* Mod = FindMod(Id))
			{
				TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
				Args->SetStringField(TEXT("id"), Mod->DragId);
				Args->SetNumberField(TEXT("dx"), Mod->Drag.X);
				Args->SetNumberField(TEXT("dy"), Mod->Drag.Y);
				Args->SetBoolField(TEXT("shift"), Mod->bDragShift);
				Mod->Drag = FVector2D::ZeroVector;
				SendInputEvent(*Mod, TEXT("drag"), Args, false);
			}
		TickMarks(*Game);
		return true;
	}

	FDelayedAutoRegisterHelper Start(EDelayedRegisterRunPhase::EndOfEngineInit, []
	{
		if (!FApp::IsGame() || IsRunningCommandlet()) return;
		FTSTicker::GetCoreTicker().AddTicker(TEXT("OKStudioMods"), 0.f, [](float Delta) { return Tick(Delta); });
	});

	FAutoConsoleCommand ReloadCommand(TEXT("OKStudio.ModReload"), TEXT("Asks the studio mods again what they add (studio.panel_ui)."),
		FConsoleCommandDelegate::CreateLambda([] { State().bReload = true; }));

	FAutoConsoleCommand TraceCommand(TEXT("OKStudio.ModTrace"), TEXT("Logs the studio mods' last calls and answers."),
		FConsoleCommandDelegate::CreateLambda([]
		{
			for (const FMod& M : State().Mods) UE_LOG(LogOKStudioMods, Display, TEXT("mod %s: %d keys, %d timers, marks \"%s\""), *M.Id, M.Keys.Num(), M.Timers.Num(), *M.MarksPath);
			for (const FString& Line : State().Trace) UE_LOG(LogOKStudioMods, Display, TEXT("%s"), *Line);
		}));
}

// For the tests (OKStudioModBridgeTest.cpp): drive the bridge without real input.
namespace OKStudioModBridgeTest
{
	/** Puts a fake host in place of the real one (and rebuilds on the next tick); an unset Dispatch puts the real one back. */
	void SetFakeHost(TSharedPtr<FJsonObject> List, TFunction<TSharedPtr<FJsonObject>(const FJsonObject&)> Dispatch)
	{
		if (Dispatch) OKStudioModBridge::Fake() = OKStudioModBridge::FFakeHost{ List, MoveTemp(Dispatch) };
		else OKStudioModBridge::Fake().Reset();
		OKStudioModBridge::State().bReload = true;
	}
	void Tick() { OKStudioModBridge::Tick(0.f); }
	/** The value a mod's control shows for an object, as the panel row reads it. */
	FString ControlValue(const FString& Mod, const FString& Control, int32 Object)
	{
		UOKStudioGame* Game = OKStudioModBridge::State().Game.Get();
		const FOKStudioModControl* C = FOKStudioModRegistry::Get().Controls().FindByPredicate([&](const FOKStudioModControl& X) { return X.Owner == Mod && X.Id == Control; });
		return C && C->Get && Game && Game->Document ? C->Get(*Game->Document, Object) : FString(TEXT("<none>"));
	}
	bool SetControl(const FString& Mod, const FString& Control, int32 Object, const FString& Value)
	{
		UOKStudioGame* Game = OKStudioModBridge::State().Game.Get();
		const FOKStudioModControl* C = FOKStudioModRegistry::Get().Controls().FindByPredicate([&](const FOKStudioModControl& X) { return X.Owner == Mod && X.Id == Control; });
		// As the panel row does: the change is noted for undo (SOKStudioPanel::Changed).
		if (!C || !C->Set || !Game || !Game->Document || !C->Set(*Game->Document, Object, Value)) return false;
		Game->Document->NotifyChanged();
		return true;
	}
	FString DataText(const FString& Mod)
	{
		UOKStudioGame* Game = OKStudioModBridge::State().Game.Get();
		return Game && Game->Document ? OKStudioModBridge::DataText(*Game->Document, Mod) : FString();
	}
	bool Built() { return OKStudioModBridge::State().bBuilt; }
	int32 ModCount() { return OKStudioModBridge::State().Mods.Num(); }
	bool HasMod(const FString& Id) { return OKStudioModBridge::FindMod(Id) != nullptr; }
	void Reload() { OKStudioModBridge::State().bReload = true; }
	/** A key event of a mod's key id as if pressed / released. */
	bool Key(const FString& Mod, const FString& KeyId, bool bDown)
	{
		using namespace OKStudioModBridge;
		FMod* M = FindMod(Mod);
		FKeyChord* K = M ? M->Keys.FindByPredicate([&](const FKeyChord& C) { return C.Id == KeyId; }) : nullptr;
		if (!K) return false;
		K->bHeld = bDown;
		TSharedRef<FJsonObject> Args = MakeShared<FJsonObject>();
		Args->SetStringField(TEXT("id"), KeyId);
		Args->SetBoolField(TEXT("down"), bDown);
		SendInputEvent(*M, TEXT("key"), Args, true);
		return true;
	}
	/** Mouse movement while a drag key is held (sent on the next tick). */
	bool Drag(const FString& Mod, const FString& KeyId, FVector2D Delta)
	{
		using namespace OKStudioModBridge;
		FMod* M = FindMod(Mod);
		if (!M) return false;
		M->Drag += Delta;
		M->DragId = KeyId;
		return true;
	}
	/** Fires a mod's timers now. */
	bool FireTimers(const FString& Mod)
	{
		using namespace OKStudioModBridge;
		FMod* M = FindMod(Mod);
		if (!M) return false;
		for (FTimer& T : M->Timers) T.Next = 0.0;
		return true;
	}
	FString LastTrace() { const TArray<FString>& T = OKStudioModBridge::State().Trace; return T.Num() ? T.Last() : FString(); }
}
