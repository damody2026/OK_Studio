// Tests of the studio's mod points (OK_MOD_FRAMEWORK_PLAN §15.4 item 5).
//  - OpenKoikatsu.Studio.ModData (automation, editor): the .okscene "mods" field (FormatVersion 4) reads, writes and keeps
//    other mods' entries; old scenes read as before; the registry's checks; mod timeline tracks sample and play.
//  - OKStudio.ModSelfTest [exit] (in the running studio): a test mod registered from C++ — its command runs from the
//    command table as one undo step, its tool button, tree menu entry, 狀態 and 畫面設定 rows work, and the data survives
//    save / load. Results in Saved/OKStudio/mod_selftest.txt; "MOD SELFTEST n/m" at the end of the log.
#include "SOKStudioPanel.h"
#include "OKStudioGameInternal.h"
#include "OKStudioMod.h"
#include "Misc/AutomationTest.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "Widgets/Input/SCheckBox.h"

namespace
{
	TArray<uint8> ModBytes(const FString& Text) { FTCHARToUTF8 U(*Text); return TArray<uint8>(reinterpret_cast<const uint8*>(U.Get()), U.Length()); }
	FString ModText(const UOKSceneDocument& Doc, const FString& Mod)
	{
		TArray<uint8> B;
		if (!Doc.GetModData(Mod, B)) return TEXT("<none>");
		return FString(FUTF8ToTCHAR(reinterpret_cast<const ANSICHAR*>(B.GetData()), B.Num()));
	}
	void ModSetText(UOKSceneDocument& Doc, const FString& Mod, const FString& Value) { Doc.SetModData(Mod, 1, ModBytes(Value)); }
	TSharedPtr<FJsonObject> ModParseJson(const FString& Json)
	{
		TSharedPtr<FJsonObject> Root;
		FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json), Root);
		return Root;
	}
	FString ModWriteJson(const TSharedRef<FJsonObject>& Root)
	{
		FString Out;
		FJsonSerializer::Serialize(Root, TJsonWriterFactory<>::Create(&Out));
		return Out;
	}
}

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKStudioModDataTest, "OpenKoikatsu.Studio.ModData", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKStudioModDataTest::RunTest(const FString&)
{
	UOKSceneDocument* Doc = NewObject<UOKSceneDocument>();
	Doc->AddObject(EOKSceneObjectKind::Folder, TEXT("a"));

	// A scene without mod data is written as before: no "mods", the old version number.
	const FString Plain = Doc->ToJson();
	TSharedPtr<FJsonObject> PlainRoot = ModParseJson(Plain);
	TestTrue(TEXT("plain scene parses"), PlainRoot.IsValid());
	if (!PlainRoot) return false;
	TestFalse(TEXT("plain scene has no mods field"), PlainRoot->HasField(TEXT("mods")));
	TestEqual(TEXT("plain scene keeps version 1"), int32(PlainRoot->GetNumberField(TEXT("version"))), 1);

	// Mod data: version 4, sorted ids, bytes back as written.
	ModSetText(*Doc, TEXT("com.example.b"), TEXT("bee"));
	Doc->SetModData(TEXT("com.example.a"), 3, TArray<uint8>{ 0, 1, 2, 255 });
	const FString WithMods = Doc->ToJson();
	TSharedPtr<FJsonObject> ModRoot = ModParseJson(WithMods);
	TestEqual(TEXT("a scene with mod data is version 4"), int32(ModRoot->GetNumberField(TEXT("version"))), 4);
	TestTrue(TEXT("mods field written"), ModRoot->HasTypedField<EJson::Object>(TEXT("mods")));
	UOKSceneDocument* Back = NewObject<UOKSceneDocument>();
	FString Error;
	TestTrue(TEXT("version 4 reads"), Back->FromJson(WithMods, Error));
	TArray<uint8> Raw;
	int32 Version = 0;
	TestTrue(TEXT("binary mod data reads back"), Back->GetModData(TEXT("com.example.a"), Raw, &Version) && Raw == TArray<uint8>{ 0, 1, 2, 255 } && Version == 3);
	TestEqual(TEXT("text mod data reads back"), ModText(*Back, TEXT("com.example.b")), FString(TEXT("bee")));
	TestEqual(TEXT("written again the same"), Back->ToJson(), WithMods);
	TestTrue(TEXT("remove"), Back->RemoveModData(TEXT("com.example.b")) && !Back->Mods.Contains(TEXT("com.example.b")));

	// A mod this build does not have: its entry is written back unchanged; a broken entry is dropped, the scene opens.
	{
		TSharedRef<FJsonObject> Root = ModParseJson(Plain).ToSharedRef();
		TSharedRef<FJsonObject> Mods = MakeShared<FJsonObject>();
		TSharedRef<FJsonObject> Unknown = MakeShared<FJsonObject>();
		Unknown->SetNumberField(TEXT("version"), 7);
		Unknown->SetStringField(TEXT("data"), TEXT("AAEC/w=="));
		Mods->SetObjectField(TEXT("com.unknown.mod"), Unknown);
		Mods->SetNumberField(TEXT("com.broken.mod"), 5);
		Root->SetObjectField(TEXT("mods"), Mods);
		Root->SetNumberField(TEXT("version"), 4);
		UOKSceneDocument* Other = NewObject<UOKSceneDocument>();
		TestTrue(TEXT("scene with unknown and broken mod data opens"), Other->FromJson(ModWriteJson(Root), Error));
		TestEqual(TEXT("broken entry dropped"), Other->Mods.Num(), 1);
		TSharedPtr<FJsonObject> Again = ModParseJson(Other->ToJson());
		const TSharedPtr<FJsonObject>* AgainMods = nullptr;
		const TSharedPtr<FJsonObject>* Entry = nullptr;
		const bool bKept = Again && Again->TryGetObjectField(TEXT("mods"), AgainMods) && (*AgainMods)->TryGetObjectField(TEXT("com.unknown.mod"), Entry)
			&& (*Entry)->GetStringField(TEXT("data")) == TEXT("AAEC/w==") && int32((*Entry)->GetNumberField(TEXT("version"))) == 7;
		TestTrue(TEXT("unknown mod's entry written back unchanged"), bKept);
		// A scene without the field clears what the document held (opening another scene, undo to before the mod wrote).
		TestTrue(TEXT("old scene clears mods"), Other->FromJson(Plain, Error) && Other->Mods.IsEmpty());
		Root->SetNumberField(TEXT("version"), 5);
		TestFalse(TEXT("version 5 refused"), Other->FromJson(ModWriteJson(Root), Error));
	}

	// Old scenes on this machine (UserData/Studio/scene, local only) still open, and are written without mods.
	{
		TArray<FString> Files;
		const FString Dir = FPaths::ProjectDir() / TEXT("UserData/Studio/scene");
		IFileManager::Get().FindFiles(Files, *(Dir / TEXT("*.okscene")), true, false);
		int32 Opened = 0;
		for (const FString& Name : Files)
		{
			FString Json;
			UOKSceneDocument* Old = NewObject<UOKSceneDocument>();
			if (!FFileHelper::LoadFileToString(Json, *(Dir / Name)) || !Old->FromJson(Json, Error)) { AddError(FString::Printf(TEXT("old scene %s: %s"), *Name, *Error)); continue; }
			TSharedPtr<FJsonObject> Out = ModParseJson(Old->ToJson());
			if (!Out || Out->HasField(TEXT("mods")) || int32(Out->GetNumberField(TEXT("version"))) > 3) { AddError(FString::Printf(TEXT("old scene %s written with mods or version 4"), *Name)); continue; }
			++Opened;
		}
		AddInfo(FString::Printf(TEXT("old scenes opened: %d of %d"), Opened, Files.Num()));
	}

	// Registry: ids are checked, a name is taken once, removing an owner drops all of it.
	FOKStudioModRegistry& R = FOKStudioModRegistry::Get();
	const FString Owner = TEXT("test.moddata");
	R.RemoveOwner(Owner);
	const int32 Gen = R.Generation();
	TestFalse(TEXT("bad mod id refused"), R.AddCommand({ TEXT("bad id"), TEXT("x"), TEXT("x"), [](const FString&) { return true; } }));
	TestFalse(TEXT("dotted command name refused"), R.AddCommand({ Owner, TEXT("a.b"), TEXT("x"), [](const FString&) { return true; } }));
	TestTrue(TEXT("command added"), R.AddCommand({ Owner, TEXT("ping"), TEXT("ping"), [](const FString&) { return true; } }));
	TestFalse(TEXT("same command twice refused"), R.AddCommand({ Owner, TEXT("ping"), TEXT("ping"), [](const FString&) { return true; } }));
	TestTrue(TEXT("command found by full id"), R.FindCommand(TEXT("mod.test.moddata.ping")) != nullptr);
	TestTrue(TEXT("generation moved"), R.Generation() > Gen);

	// Timeline: a scene value of the mod, keyed at 0 and 1, plays back interpolated by the studio.
	TSharedRef<float> Level = MakeShared<float>(0.f);
	FOKStudioModInterpolable I;
	I.Owner = Owner; I.Id = TEXT("level"); I.Label = TEXT("level");
	I.Sample = [Level](const UOKSceneDocument&, int32, TArray<float>& Out) { Out = { *Level }; return true; };
	I.Apply = [Level](UOKSceneDocument&, int32, TConstArrayView<float> V) { *Level = V[0]; };
	TestTrue(TEXT("interpolable added"), R.AddInterpolable(MoveTemp(I)));
	const int32 Track = Doc->AddTimelineInterpolableTrack(FOKStudioModRegistry::TimelineOwner(Owner), TEXT("level"), -1);
	*Level = 10.f;
	Doc->SetTimelineTrackKey(Track, 1.f);
	*Level = -1.f;
	Doc->EvaluateTimeline(0.5f);
	TestTrue(TEXT("mod track interpolates between keys"), FMath::IsNearlyEqual(*Level, 5.f, 0.05f));
	TestTrue(TEXT("the menu offers the scene value"), R.InterpolableMenu(*Doc, -1).ContainsByPredicate([](const FOKStudioModRegistry::FMenuInterpolable& M) { return M.Id == TEXT("level") && M.ObjectId < 0; }));
	R.RemoveOwner(Owner);
	TestTrue(TEXT("removing the mod drops its registrations"), !R.FindCommand(TEXT("mod.test.moddata.ping")) && R.Interpolables().IsEmpty());
	*Level = -1.f;
	Doc->EvaluateTimeline(0.5f);
	TestTrue(TEXT("a track of a mod not loaded does nothing and stays"), *Level == -1.f && Doc->TimelineTracks.IsValidIndex(Track) && Doc->ToJson().Contains(TEXT("mod.test.moddata")));
	return true;
}
#endif

namespace
{
	UWorld* ModTestWorld() { return GEngine && GEngine->GameViewport ? GEngine->GameViewport->GetWorld() : nullptr; }

	TSharedPtr<SWidget> FindTagged(const TSharedRef<SWidget>& Root, const FName Tag)
	{
		if (const TSharedPtr<FTagMetaData> T = Root->GetMetaData<FTagMetaData>(); T && T->Tag == Tag) return Root;
		FChildren* Kids = Root->GetChildren();
		for (int32 I = 0; Kids && I < Kids->Num(); ++I)
			if (TSharedPtr<SWidget> Found = FindTagged(Kids->GetChildAt(I), Tag)) return Found;
		return nullptr;
	}
	TSharedPtr<SWidget> FindType(const TSharedPtr<SWidget>& Root, const FName Type)
	{
		if (!Root) return nullptr;
		if (Root->GetType() == Type) return Root;
		FChildren* Kids = Root->GetChildren();
		for (int32 I = 0; Kids && I < Kids->Num(); ++I)
			if (TSharedPtr<SWidget> Found = FindType(Kids->GetChildAt(I), Type)) return Found;
		return nullptr;
	}
	bool Click(const TSharedPtr<SWidget>& Root)
	{
		const TSharedPtr<SWidget> B = FindType(Root, TEXT("SButton"));
		if (!B) return false;
		StaticCastSharedPtr<SButton>(B)->SimulateClick();
		return true;
	}

	const TCHAR* ModOwner = TEXT("test.studiomod");

	/** The test mod: everything it keeps is in the scene's mod data, as a real mod's would be. */
	void RegisterTestMod()
	{
		FOKStudioModRegistry& R = FOKStudioModRegistry::Get();
		R.RemoveOwner(ModOwner);
		auto Doc = [] { UOKStudioGame* G = UOKStudioGame::Get(); return G ? G->Document.Get() : nullptr; };
		R.AddCommand({ ModOwner, TEXT("mark"), TEXT("測試標記"), [Doc](const FString& Arg)
		{
			UOKSceneDocument* D = Doc();
			if (!D) return false;
			ModSetText(*D, ModOwner, Arg);
			D->NotifyChanged();
			return true;
		} });
		R.AddToolbarButton({ ModOwner, TEXT("mark"), TEXT("標"), TEXT("測試 mod：標記"), TEXT("mod.test.studiomod.mark"), TEXT("tool") });
		R.AddMenuItem({ ModOwner, TEXT("mark"), TEXT("測試 mod：標記"), TEXT("mod.test.studiomod.mark"), TEXT("menu"), nullptr });
		FOKStudioModControl Flag;
		Flag.Owner = ModOwner; Flag.Id = TEXT("flag"); Flag.Label = TEXT("測試旗標"); Flag.Panel = EOKStudioModPanel::CurrentState; Flag.Kind = EOKStudioModControlKind::Toggle;
		Flag.Get = [](const UOKSceneDocument& D, int32 Id) { return D.Mods.Contains(FString::Printf(TEXT("test.studiomod.flag%d"), Id)) ? FString(TEXT("1")) : FString(TEXT("0")); };
		Flag.Set = [](UOKSceneDocument& D, int32 Id, const FString& V)
		{
			const FString Key = FString::Printf(TEXT("test.studiomod.flag%d"), Id);
			if (V == TEXT("1")) ModSetText(D, Key, TEXT("on")); else D.RemoveModData(Key);
			return true;
		};
		R.AddControl(MoveTemp(Flag));
		FOKStudioModControl Level;
		Level.Owner = ModOwner; Level.Id = TEXT("level"); Level.Label = TEXT("測試強度"); Level.Panel = EOKStudioModPanel::SceneEffects; Level.Kind = EOKStudioModControlKind::Slider;
		Level.Min = 0.f; Level.Max = 10.f; Level.Step = 0.1f;
		Level.Get = [](const UOKSceneDocument& D, int32) { return D.Mods.Contains(TEXT("test.studiomod.level")) ? ModText(D, TEXT("test.studiomod.level")) : FString(TEXT("0")); };
		Level.Set = [](UOKSceneDocument& D, int32, const FString& V) { ModSetText(D, TEXT("test.studiomod.level"), V); return true; };
		R.AddControl(MoveTemp(Level));
	}

	struct FModTest
	{
		TWeakObjectPtr<UOKStudioGame> Game;
		TArray<FString> Lines;
		int32 Passed = 0, Failed = 0, Step = 0, Wait = 0, Character = -1;
		bool bExit = false;
		FString SceneFile;

		void Check(bool bOk, const FString& What)
		{
			Lines.Add(FString::Printf(TEXT("%s %s"), bOk ? TEXT("PASS") : TEXT("FAIL"), *What));
			(bOk ? Passed : Failed) += 1;
			UE_LOG(LogTemp, Display, TEXT("OK studio mod self test: %s %s"), bOk ? TEXT("PASS") : TEXT("FAIL"), *What);
		}
		SOKStudioPanel* Panel() const { return Game.IsValid() ? Game->GetPanel() : nullptr; }
		UOKSceneDocument* Doc() const { return Game.IsValid() ? Game->Document.Get() : nullptr; }
		bool Cmd(const FString& Id, const FString& Arg = FString()) const { return Panel() && Panel()->RunCommand(Id, Arg); }
		FString Mark() const { return Doc() ? ModText(*Doc(), ModOwner) : FString(); }
		void Settle(int32 Frames = 10) { Wait = Frames; if (Game.IsValid()) Game->SyncDocumentNow(); }

		void Finish()
		{
			FOKStudioModRegistry::Get().RemoveOwner(ModOwner);
			Lines.Insert(FString::Printf(TEXT("MOD SELFTEST %d/%d"), Passed, Passed + Failed), 0);
			FFileHelper::SaveStringArrayToFile(Lines, *(FPaths::ProjectSavedDir() / TEXT("OKStudio/mod_selftest.txt")));
			UE_LOG(LogTemp, Display, TEXT("MOD SELFTEST %d/%d"), Passed, Passed + Failed);
			if (!SceneFile.IsEmpty())
			{
				IFileManager::Get().Delete(*SceneFile, false, true, true);
				IFileManager::Get().DeleteDirectory(*(FPaths::GetPath(SceneFile) / FPaths::GetBaseFilename(SceneFile) + TEXT("_cards")), false, true);
			}
			if (bExit) FPlatformMisc::RequestExit(false);
		}

		bool Tick()
		{
			if (!Game.IsValid() || !Panel()) { Check(false, TEXT("studio running")); Finish(); return false; }
			if (Wait > 0) { --Wait; return true; }
			UOKStudioGame* G = Game.Get();
			SOKStudioPanel* P = Panel();
			G->CommitHistory();
			switch (Step++)
			{
			case 0:
			{
				Cmd(TEXT("scene.new"));
				RegisterTestMod();
				const TArray<FString> Cards = UOKStudioGame::AvailableCards();
				Check(Cards.Num() > 0 && Cmd(TEXT("add.character"), Cards.Num() ? Cards[0] : FString()), TEXT("a character to show the 狀態 rows on"));
				for (const FOKSceneObject& O : Doc()->Objects) if (O.Kind == EOKSceneObjectKind::Character) Character = FMath::Max(Character, O.Id);
				Settle(60);
				return true;
			}
			case 1:
			{
				// The command table: run by id, one undo step, redo brings it back.
				Check(Cmd(TEXT("mod.test.studiomod.mark"), TEXT("cmd")) && Mark() == TEXT("cmd"), TEXT("mod command runs from the command table and writes scene mod data"));
				G->Undo();
				const FString Undone = Mark();
				G->Redo();
				Check(Undone == TEXT("<none>") && Mark() == TEXT("cmd"), FString::Printf(TEXT("the command is one undo step (undone: %s, redone: %s)"), *Undone, *Mark()));
				Check(!Cmd(TEXT("mod.test.studiomod.nosuch")), TEXT("an unregistered mod command fails"));
				// The tool row rebuilt when the mod registered.
				Check(Click(FindTagged(P->AsShared(), TEXT("ModTool_test.studiomod.mark"))) && Mark() == TEXT("tool"), TEXT("toolbar button runs its command"));
				// The tree's context menu.
				Cmd(TEXT("select"), FString::FromInt(Character));
				const TSharedPtr<SWidget> Menu = P->TreeContextMenu();
				Check(Menu && Click(FindTagged(Menu.ToSharedRef(), TEXT("ModMenu_test.studiomod.mark"))) && Mark() == TEXT("menu"), TEXT("context menu entry runs its command"));
				Cmd(TEXT("page.state"));
				Settle(5);
				return true;
			}
			case 2:
			{
				// 狀態 page of the selected character: the toggle row writes the mod's data for that character; undo takes it back.
				Check(P->ModRowsShown == 1, FString::Printf(TEXT("狀態 page shows the mod's row (%d)"), P->ModRowsShown));
				const TSharedPtr<SWidget> Box = FindType(FindTagged(P->AsShared(), TEXT("ModRow_test.studiomod.flag")), TEXT("SCheckBox"));
				if (Box) StaticCastSharedPtr<SCheckBox>(Box)->ToggleCheckedState();
				const FString Key = FString::Printf(TEXT("test.studiomod.flag%d"), Character);
				const bool bOn = Doc()->Mods.Contains(Key);
				G->CommitHistory();
				G->Undo();
				Check(Box && bOn && !Doc()->Mods.Contains(Key), TEXT("狀態 toggle sets the character's mod data, undo clears it"));
				G->Redo();
				Cmd(TEXT("scene.tab"), TEXT("0"));
				Settle(5);
				return true;
			}
			case 3:
			{
				Check(P->ModRowsShown == 1 && FindTagged(P->AsShared(), TEXT("ModRow_test.studiomod.level")).IsValid(), FString::Printf(TEXT("畫面設定 shows the mod's scene row (%d)"), P->ModRowsShown));
				const FOKStudioModControl* Level = FOKStudioModRegistry::Get().Controls().FindByPredicate([](const FOKStudioModControl& C) { return C.Id == TEXT("level"); });
				Check(Level && Level->Set(*Doc(), -1, TEXT("2.5")) && Level->Get(*Doc(), -1) == TEXT("2.5"), TEXT("scene row value set"));
				Doc()->NotifyChanged();
				G->CommitHistory();
				// Saved and opened again (a scene card), the mod data is all there.
				SceneFile = UOKStudioGame::SceneDirectory() / TEXT("_modselftest.png");
				IFileManager::Get().Delete(*SceneFile, false, true, true);
				Check(Cmd(TEXT("scene.save"), TEXT("_modselftest")) && FPaths::FileExists(SceneFile), TEXT("scene saves"));
				Check(Cmd(TEXT("scene.new")) && Doc()->Mods.IsEmpty(), TEXT("a new scene has no mod data"));
				Check(Cmd(TEXT("scene.load"), SceneFile) && Mark() == TEXT("menu") && ModText(*Doc(), TEXT("test.studiomod.level")) == TEXT("2.5")
					&& Doc()->Mods.Contains(FString::Printf(TEXT("test.studiomod.flag%d"), Character)), TEXT("mod data saved and loaded with the scene"));
				Settle(20);
				return true;
			}
			case 4:
			{
				// The mod goes away: its command leaves the table, the rows go, the data stays in the scene.
				FOKStudioModRegistry::Get().RemoveOwner(ModOwner);
				Check(!Cmd(TEXT("mod.test.studiomod.mark"), TEXT("gone")) && Mark() == TEXT("menu"), TEXT("a removed mod's command is gone; its data stays"));
				Finish();
				return false;
			}
			default: Finish(); return false;
			}
		}
	};

	FAutoConsoleCommand ModSelfTestCommand(TEXT("OKStudio.ModSelfTest"),
		TEXT("OKStudio.ModSelfTest [exit]: a C++ test mod registered in the studio: command, tool button, menu entry, page rows, scene data (Saved/OKStudio/mod_selftest.txt)."),
		FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
		{
			TSharedRef<FModTest> Test = MakeShared<FModTest>();
			Test->bExit = Args.Contains(TEXT("exit"));
			TSharedRef<int32> Frames = MakeShared<int32>(0);
			FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Test, Frames](float)
			{
				if (++*Frames < 30) return true;
				if (!Test->Game.IsValid())
				{
					FString Error;
					UOKStudioGame* Game = UOKStudioGame::Get() ? UOKStudioGame::Get() : UOKStudioGame::Start(ModTestWorld(), FString(), Error);
					if (!Game) { UE_LOG(LogTemp, Error, TEXT("OK studio mod self test: %s"), *Error); if (Test->bExit) FPlatformMisc::RequestExit(false); return false; }
					Test->Game = Game;
					Game->bDirty = false;
					return true;
				}
				return Test->Tick();
			}), 0.f);
		}));
}
