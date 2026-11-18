// OpenKoikatsu patch (2026-11-18), not upstream DreamGUI.
#pragma once
#include "CoreMinimal.h"
#include "RHIShaderPlatform.h"

// Whether DreamGUI's global shaders belong to the set a cooked game requires at startup.
//
// The engine requires every registered global shader that ShouldCompilePermutation accepts to be in the cooked
// global shader map (FGlobalShaderMap verification, ShaderCompiler.cpp "Missing global shader ... Fatal"). A
// stage built on a base cooked before this plugin existed has none of them, so merely linking the module made
// every such stage fatal at startup even when nothing drew DreamGUI. The editor and every cook (WITH_EDITOR)
// always compile them, so new bases carry them; a cooked game asks for them only when it will draw DreamGUI:
// -OKDreamReader (the card reader's DreamGUI screen) or -DreamGUI. When it asks and the cooked map has none of
// them, it stops with a message that says what to rebuild instead of the engine's bare "Missing global shader".
DREAMGUIRENDERER_API bool DreamGUIGlobalShadersWanted(EShaderPlatform Platform);
