// OpenKoikatsu patch (2026-11-18), not upstream DreamGUI. See DreamUIShaderGate.h.
#include "DreamUIRender/DreamUIShaderGate.h"
#include "GlobalShader.h"
#include "Shader.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"

bool DreamGUIGlobalShadersWanted(EShaderPlatform Platform)
{
#if WITH_EDITOR
	return true;
#else
	// Startup never requires them unless asked for by hand (-DreamGUI): a stage on a base cooked before this plugin
	// existed has none, and the card reader asks for them itself when it opens its screen (DreamGUIGlobalShadersReady).
	static const bool bForced = FParse::Param(FCommandLine::Get(), TEXT("DreamGUI"));
	return bForced;
#endif
}

bool DreamGUIGlobalShadersReady(FString* OutWhy)
{
#if WITH_EDITOR
	return true;
#else
	const EShaderPlatform Platform = GMaxRHIShaderPlatform;
	FShaderType* Probe = FShaderType::GetShaderTypeByName(TEXT("FDreamUIBackdropCompositePS"));
	const bool bReady = Probe && Platform < SP_NumPlatforms && GGlobalShaderMap[Platform] && GGlobalShaderMap[Platform]->HasShader(Probe, 0);
	if (!bReady && OutWhy)
	{
		*OutWhy = TEXT("DreamGUI 的 global shader 不在這個遊戲的 shader 庫裡（讀卡器的新畫面要用到）。")
			TEXT("請先執行 Tools/lua/lua.exe Tools/rebuild_street_social_patch.lua 重建 runtime patch，或改用完整 cook 的新 base。")
			TEXT(" DreamGUI's global shaders are not in this game's shader library: rebuild the runtime patch or use a fully cooked base.");
	}
	return bReady;
#endif
}
