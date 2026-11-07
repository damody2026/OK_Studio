#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "Subsystems/WorldSubsystem.h"
#include "CityLanguage.generated.h"

UENUM(BlueprintType)
enum class ECityLanguage : uint8
{
    TraditionalChinese = 0 UMETA(DisplayName="Traditional Chinese (zh-Hant)"),
    SimplifiedChinese = 1 UMETA(DisplayName="Simplified Chinese (zh-Hans)"),
    English = 2 UMETA(DisplayName="English (en)")
};
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FCityLanguageChanged, ECityLanguage, Language);

/** One authoritative language per game instance, retained during level travel. */
UCLASS()
class CITYLOCALIZATION_API UCityLanguageSubsystem : public UGameInstanceSubsystem
{
    GENERATED_BODY()
public:
    virtual void Initialize(FSubsystemCollectionBase& Collection) override;
    UFUNCTION(BlueprintCallable, Category="City|Localization")
    bool SetLanguage(ECityLanguage Language, bool bSavePreference = true);
    bool ApplyToWorld(UWorld* World, ECityLanguage Language, bool bSavePreference);
    UFUNCTION(BlueprintPure, Category="City|Localization")
    ECityLanguage GetLanguage() const { return CurrentLanguage; }
    UPROPERTY(BlueprintAssignable, Category="City|Localization")
    FCityLanguageChanged OnLanguageChanged;
private:
    UPROPERTY(Transient)
    ECityLanguage CurrentLanguage = ECityLanguage::TraditionalChinese;
};

/** Re-applies the current language to each new game/PIE world's MPC instance. */
UCLASS()
class CITYLOCALIZATION_API UCityLanguageWorldSubsystem : public UWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual void OnWorldBeginPlay(UWorld& InWorld) override;
protected:
    virtual bool DoesSupportWorldType(EWorldType::Type WorldType) const override;
};

UCLASS()
class CITYLOCALIZATION_API UCityLanguageLibrary : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="City|Localization", meta=(WorldContext="WorldContextObject"))
    static bool SetCityLanguage(const UObject* WorldContextObject, ECityLanguage Language, bool bSavePreference = true);
    UFUNCTION(BlueprintCallable, Category="City|Localization", meta=(WorldContext="WorldContextObject"))
    static bool SetCityLanguageByCode(const UObject* WorldContextObject, const FString& LanguageCode, bool bSavePreference = true);
    UFUNCTION(BlueprintPure, Category="City|Localization", meta=(WorldContext="WorldContextObject"))
    static ECityLanguage GetCityLanguage(const UObject* WorldContextObject);
    UFUNCTION(BlueprintPure, Category="City|Localization")
    static FString GetCityLanguageCode(ECityLanguage Language);
};
