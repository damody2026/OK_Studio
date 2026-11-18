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
	static const bool bWanted = FParse::Param(FCommandLine::Get(), TEXT("OKDreamReader")) || FParse::Param(FCommandLine::Get(), TEXT("DreamGUI"));
	static bool bChecked = false;
	if (bWanted && !bChecked && Platform < SP_NumPlatforms && GGlobalShaderMap[Platform] && !GGlobalShaderMap[Platform]->IsEmpty())
	{
		bChecked = true;
		FShaderType* Probe = FShaderType::GetShaderTypeByName(TEXT("FDreamUIBackdropCompositePS"));
		if (Probe && !GGlobalShaderMap[Platform]->HasShader(Probe, 0))
		{
			UE_LOG(LogInit, Fatal, TEXT("DreamGUI 的 global shader 不在這個遊戲的 shader 庫裡（-OKDreamReader／-DreamGUI 要用到）。")
				TEXT("請先執行 Tools/lua/lua.exe Tools/rebuild_street_social_patch.lua 重建 runtime patch，或改用完整 cook 的新 base。")
				TEXT(" DreamGUI's global shaders are not in this game's shader library: rebuild the runtime patch or use a fully cooked base."));
		}
	}
	return bWanted;
#endif
}
