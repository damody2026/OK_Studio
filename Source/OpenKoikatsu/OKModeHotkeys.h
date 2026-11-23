#pragma once
// Mod hotkeys (FOKModKeys, Plugins/OKModding) in OK Studio and the one-on-one (Docs/OK_MOD_E_WAVE5.md): each mode
// listens while it is up and stops when it ends; a hotkey's reply is handled as that mode handles any mod reply.
#include "CoreMinimal.h"

class UOKCharacterController;

namespace OKModeHotkeys
{
	/** OK Studio's mods joined (OKStudioModBridge::Build): hotkeys of mode "studio" go to the bridge. */
	void StudioStart();
	/** The studio's mods left (Teardown). */
	void StudioStop();
	/** A one-on-one began (pair.enter): hotkeys of mode "pair", shown in its H panel or as a screen note. */
	void PairStart(UOKCharacterController* Controller);
	/** It ended (pair.exit). */
	void PairStop();
}
