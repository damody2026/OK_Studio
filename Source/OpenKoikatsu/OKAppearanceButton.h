#pragma once
#include "CoreMinimal.h"
#include "Components/Button.h"
#include "OKAppearanceButton.generated.h"
UCLASS()
class UOKAppearanceButton:public UButton {
 GENERATED_BODY()
public:
 UPROPERTY() TObjectPtr<class UOKCharacterController> Owner;
 UPROPERTY() TObjectPtr<class UImage> Thumbnail;
 UPROPERTY() TObjectPtr<class UTextBlock> ThumbnailStatus;
 UPROPERTY() TObjectPtr<class UTextBlock> Caption;	// "類型 N · 原始遊戲" (the DreamGUI reader's tile shows it)
 bool bChosen=false;	// the item the card has now
 FString ItemKey;
 UFUNCTION() void SelectItem();
};
