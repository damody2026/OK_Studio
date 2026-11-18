#include "OKSceneDocument.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS
// Sync() looks every object and every one of its parents up by id. Without a FFindScope open each lookup scans
// Objects, which is quadratic in a scene of thousands (ok.Studio.SyncFindIndex). The index may only make that
// faster: this test asserts the two paths answer identically, including the cases the index guards against
// (an object added or removed while a scope is open, and an id that does not exist).
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOKSceneFindIndexTest, "OpenKoikatsu.Studio.SceneFindIndex",
								 EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FOKSceneFindIndexTest::RunTest(const FString& Parameters)
{
	UOKSceneDocument* Doc = NewObject<UOKSceneDocument>();
	// A chain deep enough to exercise the parent walk, each link moved, rotated and scaled, plus siblings so the
	// index has more than one entry per level.
	TArray<int32> Chain;
	int32 Parent = -1;
	for (int32 Level = 0; Level < 6; ++Level)
	{
		const int32 Id = Doc->AddObject(EOKSceneObjectKind::Item, FString::Printf(TEXT("link%d"), Level), Parent);
		FOKSceneObject* O = Doc->Find(Id);
		if (!TestNotNull(TEXT("added object is found"), O)) return false;
		O->Transform = FTransform(FRotator(Level * 7.f, Level * 11.f, Level * 3.f), FVector(Level * 10.f, Level * -4.f, Level * 2.f), FVector(1.f + Level * .25f));
		// One hidden link in the middle: IsShown must answer false for everything below it.
		O->bVisible = Level != 3;
		Chain.Add(Id);
		Parent = Id;
		for (int32 Sibling = 0; Sibling < 3; ++Sibling) Doc->AddObject(EOKSceneObjectKind::Item, FString::Printf(TEXT("side%d_%d"), Level, Sibling), Parent);
	}

	// Scanned answers (no scope open) against indexed answers, for every object and for an id that is not there.
	TArray<int32> Ids;
	for (const FOKSceneObject& O : Doc->Objects) Ids.Add(O.Id);
	Ids.Add(123456);
	TArray<FTransform> Scanned;
	TArray<bool> ScannedShown;
	for (const int32 Id : Ids) { Scanned.Add(Doc->WorldTransform(Id)); ScannedShown.Add(Doc->IsShown(Id)); }
	{
		const UOKSceneDocument::FFindScope Scope(Doc);
		for (int32 I = 0; I < Ids.Num(); ++I)
		{
			TestTrue(FString::Printf(TEXT("indexed world transform matches the scan for id %d"), Ids[I]), Doc->WorldTransform(Ids[I]).Equals(Scanned[I], .0001f));
			TestEqual(FString::Printf(TEXT("indexed visibility matches the scan for id %d"), Ids[I]), Doc->IsShown(Ids[I]), ScannedShown[I]);
		}
	}
	// The hidden link really does hide what is under it, so the comparison above is not comparing all-true.
	TestFalse(TEXT("an object under the hidden link is hidden"), Doc->IsShown(Chain[5]));
	TestTrue(TEXT("an object above the hidden link shows"), Doc->IsShown(Chain[2]));
	// A nested scope is the same index, and leaving the inner one keeps the outer one working.
	{
		const UOKSceneDocument::FFindScope Outer(Doc);
		const FTransform Before = Doc->WorldTransform(Chain[5]);
		{ const UOKSceneDocument::FFindScope Inner(Doc); TestTrue(TEXT("nested scope answers the same"), Doc->WorldTransform(Chain[5]).Equals(Before, .0001f)); }
		TestTrue(TEXT("outer scope still answers after the inner one ends"), Doc->WorldTransform(Chain[5]).Equals(Before, .0001f));
	}
	// Objects added and removed while a scope is open: the index is built again rather than answering with a stale
	// position. This is what makes the scope safe to hold across a whole Sync.
	{
		const UOKSceneDocument::FFindScope Scope(Doc);
		const FTransform Deep = Doc->WorldTransform(Chain[5]);
		const int32 Added = Doc->AddObject(EOKSceneObjectKind::Item, TEXT("added inside the scope"), Chain[1]);
		if (FOKSceneObject* O = Doc->Find(Added)) O->Transform = FTransform(FVector(5.f, 6.f, 7.f));
		TestTrue(TEXT("an object added inside the scope is found"), Doc->Find(Added) != nullptr);
		TestTrue(TEXT("the objects already there keep their transform"), Doc->WorldTransform(Chain[5]).Equals(Deep, .0001f));
		TestTrue(TEXT("the object added inside the scope is removed"), Doc->RemoveObject(Added));
		TestNull(TEXT("an object removed inside the scope is gone"), Doc->Find(Added));
		TestTrue(TEXT("removal leaves the rest where they were"), Doc->WorldTransform(Chain[5]).Equals(Deep, .0001f));
	}
	// One object removed and another added between two scopes, so the array's length and storage can both come back
	// unchanged while the contents moved. An index kept from the first scope would answer "no such object" for the new
	// id; the scope's entry throws its index away for exactly this, and this case is what forbids reusing it.
	{
		{ const UOKSceneDocument::FFindScope Scope(Doc); Doc->WorldTransform(Chain[5]); }
		const int32 Doomed = Doc->Objects.Last().Id;
		const int32 Was = Doc->Objects.Num();
		TestTrue(TEXT("the last object is removed between the scopes"), Doc->RemoveObject(Doomed));
		const int32 Added = Doc->AddObject(EOKSceneObjectKind::Item, TEXT("added between the scopes"), Chain[1]);
		TestEqual(TEXT("the array is the length it was"), Doc->Objects.Num(), Was);
		const UOKSceneDocument::FFindScope Scope(Doc);
		TestNotNull(TEXT("the object added between the scopes is found"), Doc->Find(Added));
		TestNull(TEXT("the object removed between the scopes is gone"), Doc->Find(Doomed));
	}
	return true;
}
#endif
