// OpenKoikatsu patch (2026-11-18, lazy since 2026-11-19), not upstream DreamGUI.
#pragma once
#include "CoreMinimal.h"
#include "RHIShaderPlatform.h"

// Whether DreamGUI's global shaders belong to the set a cooked game requires at startup.
//
// The engine requires every registered global shader that ShouldCompilePermutation accepts to be in the cooked
// global shader map (FGlobalShaderMap verification, ShaderCompiler.cpp "Missing global shader ... Fatal"). A
// stage built on a base cooked before this plugin existed has none of them, so merely linking the module made
// every such stage fatal at startup even when nothing drew DreamGUI. The editor and every cook (WITH_EDITOR)
// always compile them, so new bases carry them; a cooked game never requires them at startup (only -DreamGUI forces
// it). Whatever is going to draw DreamGUI asks DreamGUIGlobalShadersReady first, when it is about to: the card reader
// does that as it opens its DreamGUI screen, so the street, Studio and one-on-one modes start on any base.
DREAMGUIRENDERER_API bool DreamGUIGlobalShadersWanted(EShaderPlatform Platform);

// Whether this game's global shader map has DreamGUI's shaders (always true in the editor). When not, OutWhy says what
// to rebuild.
DREAMGUIRENDERER_API bool DreamGUIGlobalShadersReady(FString* OutWhy = nullptr);
