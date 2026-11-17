// OpenKoikatsu patch (2026-11-18), not upstream DreamGUI. See DreamUIShaderGate.h.
#include "DreamUIRender/DreamUIShaderGate.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"

bool DreamGUIGlobalShadersWanted()
{
#if WITH_EDITOR
	return true;
#else
	static const bool bWanted = FParse::Param(FCommandLine::Get(), TEXT("OKDreamReader")) || FParse::Param(FCommandLine::Get(), TEXT("DreamGUI"));
	return bWanted;
#endif
}
