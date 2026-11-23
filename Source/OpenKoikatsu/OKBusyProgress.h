#pragma once
#include "CoreMinimal.h"

// Every action a person starts in the card reader that can run long goes through here, so one progress bar can show
// all of them. The action's own code calls Begin before the work and End after it, on whatever thread each happens
// on. Nothing is drawn for the first half second, so the actions that finish at once never flash a bar -- which is
// the whole rule: anything the person set off that lasts longer than that says what it is doing and how far along.
namespace OKBusy
{
	/// An action is only drawn once it has run this long.
	constexpr double ShowAfterSeconds = 0.5;

	/// One action running now.
	struct FJob
	{
		int64 Id = 0;
		/// What the person asked for: 「載入3D」、「套用服裝卡」.
		FString Label;
		/// The step inside it, when the work reports one; empty while it does not.
		FString Stage;
		double Began = 0.;
		/// 0..1, or negative while the work cannot say (the bar sweeps instead of filling).
		float Done = -1.f;
		/// Its fraction comes from ok-extract's own progress slot (FOkSession::JobProgress), polled by the controller.
		bool bFollowsExtract = false;
		double Elapsed() const { return FPlatformTime::Seconds() - Began; }
	};

	/// Begins an action; the returned id ends it. Any thread.
	int64 Begin(const FString& Label, bool bFollowsExtract = false);
	/// How far along (0..1, or negative for unknown) and, when it has one, the step's name. Any thread.
	void Progress(int64 Id, float Done, const FString& Stage = FString());
	/// Ends it. Any thread; an id already ended, or never begun, does nothing.
	void End(int64 Id);
	/// The action to show: the newest still running. False when nothing runs.
	bool Current(FJob& Out);
	/// Everything running now, oldest first (what the game MCP reports as the reader's busy state).
	TArray<FJob> Running();

	/// Begins on construction, ends on destruction: for work that begins and ends on one thread, including the error
	/// paths, which is where a hand-written End is forgotten.
	struct FScope
	{
		explicit FScope(const FString& Label, bool bFollowsExtract = false) : Id(Begin(Label, bFollowsExtract)) {}
		~FScope() { End(Id); }
		FScope(const FScope&) = delete;
		FScope& operator=(const FScope&) = delete;
		void Report(float Done, const FString& Stage = FString()) const { OKBusy::Progress(Id, Done, Stage); }
		int64 Id = 0;
	};
}
