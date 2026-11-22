#pragma once

#include "CoreMinimal.h"

// A card's identity as the street, the reader and ok-extract know her: its okId chunk, else the sha256 of the card
// without okVo (voice), okMx and okMr (mods). Same rule as Tools/ok-extract/src/oklib.rs `card_identity` and
// Tools/prepare_street_social_selection.lua `card_identity`. Empty: not a PNG card.
FString OKCardIdentity(const TArray<uint8>& Bytes);
