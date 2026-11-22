// Wires the OK mod host (Plugins/OKModding) into the game: which mode a game world runs, the /mod control route, and the
// dispatcher ok-extract uses inside this process (Docs/OK_MOD_FRAMEWORK_PLAN.md §8, item 6 of §15.4).
//
// The mode is read off each game world as it starts playing: OK Studio and the 1-on-1 scene by their game modes, the card
// reader by the plain OpenKoikatsuGameMode, the street by its scene actor. The 1-on-1 entered from the street runs in
// the street's world; its code calls FOKModHost::Get().EnterMode(TEXT("pair")) / ExitMode itself (OKModHost.h).
#include "OKModHost.h"
#include "OKControl.h"
#include "OKInteractionPairGameMode.h"
#include "OKStreetSocialScene.h"
#include "OKStudioGameMode.h"
#include "OpenKoikatsuGameMode.h"
#include "ok_extract.h"
#include "KKRustExtract.h"
#include "Containers/Ticker.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "HttpServerResponse.h"
#include "Misc/App.h"
#include "Misc/CoreDelegates.h"

namespace
{
FString GWorldMode;
TWeakObjectPtr<UWorld> GModeWorld;

// ok-extract's enabled-mod list (okmods::set_enabled, the open-cache key) for this module's copy and KKUnityBundle's,
// which runs the opens; set after every mode change, because each mode loads its own mods.
void SyncExtract()
{
	FString Lines;
	if (const TSharedPtr<FJsonObject> L = FOKModHost::Get().List())
	{
		const TArray<TSharedPtr<FJsonValue>>* Mods = nullptr;
		if (L->TryGetArrayField(TEXT("mods"), Mods))
			for (const TSharedPtr<FJsonValue>& M : *Mods)
				if (const TSharedPtr<FJsonObject> O = M->AsObject(); O.IsValid() && O->GetStringField(TEXT("state")) == TEXT("enabled"))
					Lines += O->GetStringField(TEXT("id")) + TEXT("@") + O->GetStringField(TEXT("version")) + TEXT("\n");
	}
	const FTCHARToUTF8 Utf8(*Lines);
	ok_set_enabled_mods(Utf8.Get());
	FOkSession::SetModDispatch(&FOKModHost::RustDispatch, &FOKModHost::RustFree);
	FOkSession::SetEnabledMods(Utf8.Get());
}

void Enter(UWorld* World, const FString& Mode)
{
	GWorldMode = Mode;
	GModeWorld = World;
	FOKModHost::Get().EnterMode(Mode);
	SyncExtract();
}

void BeganPlay(TWeakObjectPtr<UWorld> Weak)
{
	UWorld* World = Weak.Get();
	if (!World || !World->IsGameWorld()) return;
	AGameModeBase* GameMode = World->GetAuthGameMode();
	if (!GameMode) return;
	if (GameMode->IsA<AOKStudioGameMode>()) { Enter(World, TEXT("studio")); return; }
	if (GameMode->IsA<AOKInteractionPairGameMode>()) { Enter(World, TEXT("pair")); return; }
	if (GameMode->GetClass() == AOpenKoikatsuGameMode::StaticClass()) { Enter(World, TEXT("reader")); return; }
	// The street's scene is placed in its map or spawned while the city starts (OKCrowdScene.cpp): look for it a few
	// frames. The crowd room has none and runs no mode.
	FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Weak, Frames = 0](float) mutable
	{
		UWorld* W = Weak.Get();
		if (!W) return false;
		if (TActorIterator<AOKStreetSocialScene>(W)) { Enter(W, TEXT("street")); return false; }
		return ++Frames < 120;
	}));
}

void WorldReady(UWorld* World, const UWorld::InitializationValues)
{
	if (!World || !World->IsGameWorld()) return;
	World->OnWorldBeginPlay.AddLambda([Weak = TWeakObjectPtr<UWorld>(World)] { BeganPlay(Weak); });
}

void WorldGone(UWorld* World, bool, bool)
{
	if (World && GModeWorld.Get() == World && !GWorldMode.IsEmpty())
	{
		FOKModHost::Get().ExitMode(GWorldMode);
		GWorldMode.Empty();
		GModeWorld = nullptr;
		SyncExtract();
	}
}
}

void OKModStart()
{
	if (!FApp::IsGame() || IsRunningCommandlet()) return;
	FOKModHost::Get().Startup();
	if (FOKModHost::Get().IsTurnedOff()) return;
	ok_set_mod_dispatch(&FOKModHost::RustDispatch, &FOKModHost::RustFree);
	FWorldDelegates::OnPostWorldInitialization.AddStatic(&WorldReady);
	FWorldDelegates::OnWorldCleanup.AddStatic(&WorldGone);
	FCoreDelegates::OnEnginePreExit.AddLambda([]
	{
		ok_set_mod_dispatch(nullptr, nullptr);
		FOkSession::SetModDispatch(nullptr, nullptr);
		FOKModHost::Get().Close();
	});
}

// POST /mod on the UI channel: the body is one mod host request ({"op":"list"}, {"op":"command",...}; ok_mod_host.h),
// the answer is the host's. ok-game-mcp's mod_call.
void OKModControlRoutes()
{
	OKControl::Bind(TEXT("ui"), TEXT("/mod"), EHttpServerRequestVerbs::VERB_POST, [](const FHttpServerRequest& Req, const FHttpResultCallback& Done)
	{
		const FUTF8ToTCHAR Utf8(reinterpret_cast<const ANSICHAR*>(Req.Body.GetData()), Req.Body.Num());
		const FString Request(Utf8.Length(), Utf8.Get());
		FString Answer, Error;
		if (!FOKModHost::Get().Dispatch(Request.IsEmpty() ? FString(TEXT("{\"op\":\"list\"}")) : Request, Answer, Error))
		{
			FString Escaped = Error.ReplaceCharWithEscapedChar();
			Answer = FString::Printf(TEXT("{\"ok\":false,\"error\":\"%s\"}"), *Escaped);
		}
		Done(FHttpServerResponse::Create(Answer, TEXT("application/json; charset=utf-8")));
	});
}
