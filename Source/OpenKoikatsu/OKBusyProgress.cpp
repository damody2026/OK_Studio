#include "OKBusyProgress.h"
#include "Misc/ScopeLock.h"

namespace OKBusy
{
	namespace
	{
		FCriticalSection& Lock() { static FCriticalSection L; return L; }
		TArray<FJob>& Jobs() { static TArray<FJob> J; return J; }
		int64 NextId = 0;

		// Index of `Id` in Jobs(), or INDEX_NONE. Call under the lock.
		int32 Find(int64 Id) { return Jobs().IndexOfByPredicate([Id](const FJob& J) { return J.Id == Id; }); }
	}

	int64 Begin(const FString& Label, bool bFollowsExtract)
	{
		FScopeLock Guard(&Lock());
		FJob& J = Jobs().AddDefaulted_GetRef();
		J.Id = ++NextId;
		J.Label = Label;
		J.Began = FPlatformTime::Seconds();
		J.bFollowsExtract = bFollowsExtract;
		return J.Id;
	}

	void Progress(int64 Id, float Done, const FString& Stage)
	{
		FScopeLock Guard(&Lock());
		const int32 I = Find(Id);
		if (I == INDEX_NONE) return;
		Jobs()[I].Done = Done;
		// An empty stage leaves the one it had: a caller reporting only a fraction does not wipe the step's name.
		if (!Stage.IsEmpty()) Jobs()[I].Stage = Stage;
	}

	void End(int64 Id)
	{
		FScopeLock Guard(&Lock());
		const int32 I = Find(Id);
		if (I != INDEX_NONE) Jobs().RemoveAt(I);
	}

	bool Current(FJob& Out)
	{
		FScopeLock Guard(&Lock());
		if (Jobs().IsEmpty()) return false;
		// The newest: an action a person started while another ran is the one they are waiting on.
		Out = Jobs().Last();
		return true;
	}

	TArray<FJob> Running()
	{
		FScopeLock Guard(&Lock());
		return Jobs();
	}
}
