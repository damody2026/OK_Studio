#include "CityLanguage.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"
#include "Kismet/KismetInternationalizationLibrary.h"
#include "Materials/MaterialParameterCollection.h"
#include "Materials/MaterialParameterCollectionInstance.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Modules/ModuleManager.h"

DEFINE_LOG_CATEGORY_STATIC(LogCityLanguage, Log, All);
namespace CityLanguage
{
    constexpr const TCHAR* Section = TEXT("CityLocalization");
    const FName Parameter(TEXT("LanguageIndex"));
    bool IsValid(ECityLanguage Value) { return static_cast<uint8>(Value) <= 2; }
    bool Parse(const FString& Code, ECityLanguage& Out)
    {
        const FString Value = Code.TrimStartAndEnd().ToLower().Replace(TEXT("_"), TEXT("-"));
        if (Value == TEXT("zh-hant") || Value == TEXT("zh-tw") || Value == TEXT("0")) Out = ECityLanguage::TraditionalChinese;
        else if (Value == TEXT("zh-hans") || Value == TEXT("zh-cn") || Value == TEXT("1")) Out = ECityLanguage::SimplifiedChinese;
        else if (Value == TEXT("en") || Value == TEXT("2")) Out = ECityLanguage::English;
        else return false;
        return true;
    }
    ECityLanguage LoadPreference()
    {
        ECityLanguage Result = ECityLanguage::TraditionalChinese;
        FString Code;
        if (GConfig->GetString(Section, TEXT("Language"), Code, GGameUserSettingsIni)) Parse(Code, Result);
        if (FParse::Value(FCommandLine::Get(), TEXT("CityLanguage="), Code))
        {
            ECityLanguage Override;
            if (Parse(Code, Override)) Result = Override;
            else UE_LOG(LogCityLanguage, Warning, TEXT("Unsupported -CityLanguage=%s"), *Code);
        }
        return Result;
    }
    void SavePreference(ECityLanguage Language)
    {
        GConfig->SetString(Section, TEXT("Language"), *UCityLanguageLibrary::GetCityLanguageCode(Language), GGameUserSettingsIni);
        GConfig->Flush(false, GGameUserSettingsIni);
    }
    UMaterialParameterCollectionInstance* Instance(UWorld* World)
    {
        if (!World) return nullptr;
        auto* Collection = LoadObject<UMaterialParameterCollection>(nullptr, TEXT("/Game/UniversityCity/Localization/MPC_CityLanguage.MPC_CityLanguage"));
        return Collection ? World->GetParameterCollectionInstance(Collection) : nullptr;
    }
    bool Apply(UWorld* World, ECityLanguage Language)
    {
        if (!World || !IsValid(Language)) return false;
        auto* MPC = Instance(World);
        float PreviousIndex;
        if (!MPC || !MPC->GetScalarParameterValue(Parameter, PreviousIndex))
        {
            UE_LOG(LogCityLanguage, Error, TEXT("City language collection or LanguageIndex is missing"));
            return false;
        }
        const FString PreviousCulture = UKismetInternationalizationLibrary::GetCurrentCulture();
        if (!UKismetInternationalizationLibrary::SetCurrentCulture(UCityLanguageLibrary::GetCityLanguageCode(Language), false)) return false;
        if (!MPC->SetScalarParameterValue(Parameter, static_cast<float>(Language)))
        {
            UKismetInternationalizationLibrary::SetCurrentCulture(PreviousCulture, false);
            return false;
        }
        UE_LOG(LogCityLanguage, Log, TEXT("%s: %s (LanguageIndex=%d, collection=%s)"), *World->GetPathName(), *UCityLanguageLibrary::GetCityLanguageCode(Language), static_cast<int32>(Language), *MPC->GetCollection()->GetPathName());
        return true;
    }
    UWorld* World(const UObject* Context)
    {
        return GEngine ? GEngine->GetWorldFromContextObject(Context, EGetWorldErrorMode::ReturnNull) : nullptr;
    }
}

void UCityLanguageSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
    Super::Initialize(Collection);
    CurrentLanguage = CityLanguage::LoadPreference();
}
bool UCityLanguageSubsystem::SetLanguage(ECityLanguage Language, bool bSavePreference)
{
    return ApplyToWorld(GetGameInstance()->GetWorld(), Language, bSavePreference);
}
bool UCityLanguageSubsystem::ApplyToWorld(UWorld* World, ECityLanguage Language, bool bSavePreference)
{
    if (!World || World->GetGameInstance() != GetGameInstance() || !CityLanguage::Apply(World, Language)) return false;
    const bool bChanged = CurrentLanguage != Language;
    CurrentLanguage = Language;
    if (bSavePreference) CityLanguage::SavePreference(Language);
    if (bChanged) OnLanguageChanged.Broadcast(Language);
    return true;
}
bool UCityLanguageWorldSubsystem::DoesSupportWorldType(EWorldType::Type WorldType) const
{
    return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}
void UCityLanguageWorldSubsystem::OnWorldBeginPlay(UWorld& InWorld)
{
    Super::OnWorldBeginPlay(InWorld);
    if (UGameInstance* GI = InWorld.GetGameInstance())
    {
        if (auto* Language = GI->GetSubsystem<UCityLanguageSubsystem>()) Language->ApplyToWorld(&InWorld, Language->GetLanguage(), false);
    }
}
bool UCityLanguageLibrary::SetCityLanguage(const UObject* Context, ECityLanguage Language, bool bSavePreference)
{
    UWorld* World = CityLanguage::World(Context);
    if (!World || !CityLanguage::IsValid(Language)) return false;
    if (auto* GI = World->GetGameInstance())
        if (auto* State = GI->GetSubsystem<UCityLanguageSubsystem>()) return State->ApplyToWorld(World, Language, bSavePreference);
    // The same callable supports an editor preview, without requiring a PIE world.
    if (!CityLanguage::Apply(World, Language)) return false;
    if (bSavePreference) CityLanguage::SavePreference(Language);
    return true;
}
bool UCityLanguageLibrary::SetCityLanguageByCode(const UObject* Context, const FString& Code, bool bSavePreference)
{
    ECityLanguage Language;
    return CityLanguage::Parse(Code, Language) && SetCityLanguage(Context, Language, bSavePreference);
}
ECityLanguage UCityLanguageLibrary::GetCityLanguage(const UObject* Context)
{
    UWorld* World = CityLanguage::World(Context);
    if (World)
        if (auto* GI = World->GetGameInstance())
            if (auto* State = GI->GetSubsystem<UCityLanguageSubsystem>()) return State->GetLanguage();
    float Index = 0;
    if (auto* MPC = CityLanguage::Instance(World)) MPC->GetScalarParameterValue(CityLanguage::Parameter, Index);
    return static_cast<ECityLanguage>(FMath::Clamp(FMath::RoundToInt(Index), 0, 2));
}
FString UCityLanguageLibrary::GetCityLanguageCode(ECityLanguage Language)
{
    switch (Language)
    {
    case ECityLanguage::TraditionalChinese: return TEXT("zh-Hant");
    case ECityLanguage::SimplifiedChinese: return TEXT("zh-Hans");
    case ECityLanguage::English: return TEXT("en");
    default: return FString();
    }
}
static FAutoConsoleCommandWithWorldAndArgs CityLanguageCommand(
    TEXT("City.Language"), TEXT("Switch city text and culture: City.Language zh-Hant | zh-Hans | en (or 0 | 1 | 2). Saves preference."),
    FConsoleCommandWithWorldAndArgsDelegate::CreateLambda([](const TArray<FString>& Args, UWorld* World)
    {
        if (Args.Num() != 1 || !UCityLanguageLibrary::SetCityLanguageByCode(World, Args[0], true))
            UE_LOG(LogCityLanguage, Warning, TEXT("Usage: City.Language zh-Hant | zh-Hans | en"));
    }));
IMPLEMENT_MODULE(FDefaultModuleImpl, CityLocalization)
