#pragma once
#include "CoreMinimal.h"
class ACityImmersionWalker;
class ACityEnvironmentController;
class FJsonObject;
enum class ECityImmersionInputAudit : uint8 { Pending, Passed, Failed };
ECityImmersionInputAudit PollCityImmersionInputAudit(ACityImmersionWalker* Pawn, ACityEnvironmentController* Clock, const TSharedPtr<FJsonObject>& Report, double Now);
