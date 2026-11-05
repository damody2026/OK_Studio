#pragma once
// The game's control channels, always open in every mode (Docs/GAME_CONTROL_CHANNELS.md). One thread of their own does the
// sockets and the file work (Every); the game thread only runs a handler when a request has come, between ticks, so an
// idle channel costs it one empty queue read per frame. The engine's HTTP server is not used: it ticks its sockets on the
// game thread.
#include "CoreMinimal.h"
#include "HttpResultCallback.h"
#include "HttpServerRequest.h"

namespace OKControl
{
	/** Runs on the game thread. Done may be called later, from any thread. */
	using FHandler = TFunction<void(const FHttpServerRequest&, const FHttpResultCallback&)>;

	/**
	 * Opens the channel's port on 127.0.0.1 and returns it (0: none). Explicit > 0 is that port or nothing; otherwise this
	 * checkout's port_base + Offset (local-instance.json), then the same 100, 200, ... higher while another game has it.
	 * Asking again returns the same port. Game thread.
	 */
	OKSTUDIO_API int32 Listen(const FString& Channel, int32 Offset, int32 Explicit = 0);
	/** Game thread. */
	OKSTUDIO_API void Bind(const FString& Channel, const FString& Path, EHttpServerRequestVerbs Verbs, FHandler Handler);
	/** The channel's routes go; the port stays this process's for the next Bind. Game thread. */
	OKSTUDIO_API void Unbind(const FString& Channel);

	/** A value in this process's Saved/OKControl/<pid>.json, how ok-game-mcp and ok-character-mcp find this game. */
	OKSTUDIO_API void Publish(const FString& Key, const FString& Value);
	/** The checkout this game belongs to (a staged build runs from a folder inside it). */
	OKSTUDIO_API FString Checkout();
	/** Whether another running game of this checkout published this value. */
	OKSTUDIO_API bool TakenByOther(const FString& Key, const FString& Value);

	/** Work on the control thread every Seconds; the id is for Cancel. */
	OKSTUDIO_API int32 Every(double Seconds, TFunction<void()> Work);
	/** Returns once the work cannot run any more. */
	OKSTUDIO_API void Cancel(int32 Id);
}
