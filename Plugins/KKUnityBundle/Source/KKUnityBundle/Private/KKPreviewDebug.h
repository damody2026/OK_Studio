#pragma once
#include "CoreMinimal.h"

class UPrimitiveComponent;

// Debug controls for a character's drawn parts, live from the console (and so from ok-game-mcp's ui_exec):
//   ok.Debug.HideParts <name,name,...>  hides the parts drawn for these source renderers (exact names; empty shows all)
//   ok.Debug.Outline 0|1                 hides / shows every outline shell (component shells and procedural sections)
//   ok.Debug.DumpParts                   lists every tagged part: name, component, visibility, materials and blend
// A part's components carry the tag OKPart=<source renderer name> (OKTagPreviewPart, called where they are made); the
// current settings apply to a part as soon as it is tagged, so a reload keeps them.
void OKTagPreviewPart(UPrimitiveComponent* Component, const FString& Name);
