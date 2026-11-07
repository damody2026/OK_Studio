#include "Modules/ModuleManager.h"
#include "CityEnvironmentLog.h"
#include "CityEnvironmentRuntimeAudit.h"
#include "CityEnvironmentImmersionAudit.h"

DEFINE_LOG_CATEGORY(LogCityEnvironment);
class FCityEnvironmentModule final : public IModuleInterface
{
public:
 void StartupModule() override { StartCityEnvironmentRuntimeAudit(); StartCityEnvironmentImmersionAudit(); }
 void ShutdownModule() override { StopCityEnvironmentImmersionAudit(); StopCityEnvironmentRuntimeAudit(); }
};
IMPLEMENT_MODULE(FCityEnvironmentModule, CityEnvironment);
