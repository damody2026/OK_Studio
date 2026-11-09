#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "GameFramework/GameModeBase.h"
#include "CityImmersionWalker.generated.h"

class UPlanarReflectionComponent;

UCLASS()
class CITYENVIRONMENT_API ACityImmersionWalker : public ACharacter
{
    GENERATED_BODY()
public:
    ACityImmersionWalker();
    virtual void Tick(float DeltaSeconds) override;
    virtual void PossessedBy(AController* NewController) override;
    void SetAuditControlled(bool Enabled) { bAuditControlled = Enabled; }
    UFUNCTION(Exec)
    void CityImmersionViewPoint(const FString& ViewId);
    UFUNCTION(Exec)
    void CityImmersionCapturePose(float X, float Y, float Z, float Pitch, float Yaw);
private:
    bool bTourFlight = false;
    bool bAuditControlled = false;
    bool bMirrorsCached = false;
    float MirrorRefreshSeconds = 0.f;
    TArray<TWeakObjectPtr<UPlanarReflectionComponent>> LocalMirrors;
};

UCLASS()
class CITYENVIRONMENT_API ACityImmersionGameMode : public AGameModeBase
{
    GENERATED_BODY()
public:
    ACityImmersionGameMode();
};
