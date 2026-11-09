// Opt-in input-path smoke test. No OS input injection or normal-play activation.
#include "CityImmersionInputAudit.h"
#include "CityImmersionWalker.h"
#include "CityEnvironmentController.h"
#include "Components/CapsuleComponent.h"
#include "Dom/JsonObject.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "HAL/PlatformTime.h"
#include "InputKeyEventArgs.h"

namespace
{
 int32 InputAuditPhase=-1;
 double InputAuditNext=0;
 FVector InputAuditOrigin,InputAuditMark;
 TArray<TSharedPtr<FJsonValue>> InputAuditSteps;
 void Key(APlayerController* PC,FKey K,bool Down)
 {
  PC->InputKey(FInputKeyEventArgs(nullptr,INPUTDEVICEID_NONE,K,Down?IE_Pressed:IE_Released,FPlatformTime::Cycles64()));
 }
 void Axis(APlayerController* PC,FKey K,float Delta)
 {
  PC->InputKey(FInputKeyEventArgs(nullptr,INPUTDEVICEID_NONE,K,Delta,1.f/60.f,1,FPlatformTime::Cycles64()));
 }
}

ECityImmersionInputAudit PollCityImmersionInputAudit(ACityImmersionWalker* Pawn,ACityEnvironmentController* Clock,const TSharedPtr<FJsonObject>& Report,double Now)
{
 auto PC=Pawn?Cast<APlayerController>(Pawn->GetController()):nullptr;
 if(!PC||!Clock)return ECityImmersionInputAudit::Failed;
 auto Movement=Pawn->GetCharacterMovement();
 auto Fail=[&](const TCHAR* Reason)
 {
  Report->SetStringField(TEXT("normal_input_error"),Reason);Report->SetNumberField(TEXT("normal_input_phase"),InputAuditPhase);
  for(FKey K:{EKeys::W,EKeys::S,EKeys::LeftShift,EKeys::SpaceBar,EKeys::F7,EKeys::F8,EKeys::E})Key(PC,K,false);
  return ECityImmersionInputAudit::Failed;
 };
 auto Record=[&](const TCHAR* Name,double Value=0.)
 {
  auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("control"),Name);Row->SetNumberField(TEXT("measured_value"),Value);InputAuditSteps.Add(MakeShared<FJsonValueObject>(Row));Report->SetArrayField(TEXT("normal_input_steps"),InputAuditSteps);
 };
 auto Wait=[&](int32 NewPhase,double Seconds){InputAuditPhase=NewPhase;InputAuditNext=Now+Seconds;return ECityImmersionInputAudit::Pending;};
 auto Reset=[&](){Movement->StopMovementImmediately();Pawn->SetActorLocation(InputAuditOrigin,false,nullptr,ETeleportType::TeleportPhysics);PC->SetControlRotation(FRotator::ZeroRotator);Movement->SetMovementMode(MOVE_Walking);};
 if(InputAuditPhase<0)
 {
  if(PC->bShowMouseCursor||PC->IsMoveInputIgnored()||Clock->ShouldShowTimeControls())return Fail(TEXT("normal_play_start_does_not_capture_walking_input"));
  InputAuditOrigin=InputAuditMark=Pawn->GetActorLocation();PC->SetControlRotation(FRotator::ZeroRotator);Pawn->SetAuditControlled(false);
  Report->SetStringField(TEXT("normal_input_scope"),TEXT("Controller InputKey events exercise ordinary pawn polling,CharacterMovement and F7/F8 bindings on the verified4m start segment. No OS keyboard/mouse or focus-routing claim. Only isolated test cases reset position."));
  Key(PC,EKeys::W,true);return Wait(1,1.2);
 }
 if(Now<InputAuditNext)return ECityImmersionInputAudit::Pending;
 const FVector Location=Pawn->GetActorLocation();
 switch(InputAuditPhase)
 {
 case 1:
  if(Location.X-InputAuditMark.X<150||Location.X-InputAuditMark.X>280||FMath::Abs(Location.Y-InputAuditMark.Y)>5)return Fail(TEXT("W_did_not_walk_forward"));
  Record(TEXT("W_forward_cm"),Location.X-InputAuditMark.X);Key(PC,EKeys::W,false);return Wait(2,.3);
 case 2:
  if(Pawn->GetVelocity().Size2D()>5)return Fail(TEXT("walk_did_not_brake"));
  InputAuditMark=Location;Key(PC,EKeys::S,true);return Wait(3,1.2);
 case 3:
  if(Location.X-InputAuditMark.X> -150||Location.X-InputAuditMark.X< -280)return Fail(TEXT("S_did_not_walk_backward"));
  Record(TEXT("S_backward_cm"),InputAuditMark.X-Location.X);Key(PC,EKeys::S,false);return Wait(4,.3);
 case 4:
  Reset();InputAuditMark=InputAuditOrigin;Key(PC,EKeys::LeftShift,true);Key(PC,EKeys::W,true);return Wait(5,.75);
 case 5:
  if(Location.X-InputAuditMark.X<200||Location.X-InputAuditMark.X>320)return Fail(TEXT("Shift_did_not_increase_walk_speed"));
  Record(TEXT("Shift_fast_walk_cm"),Location.X-InputAuditMark.X);Key(PC,EKeys::W,false);Key(PC,EKeys::LeftShift,false);return Wait(6,.3);
 case 6:
  if(!Movement->IsMovingOnGround())return Fail(TEXT("not_grounded_before_jump"));
  InputAuditMark=Location;Key(PC,EKeys::SpaceBar,true);return Wait(7,.3);
 case 7:
  if(Location.Z-InputAuditMark.Z<20||Location.Z-InputAuditMark.Z>80)return Fail(TEXT("Space_did_not_jump"));
  Record(TEXT("Space_jump_rise_cm"),Location.Z-InputAuditMark.Z);Key(PC,EKeys::SpaceBar,false);return Wait(8,1.);
 case 8:
  if(!Movement->IsMovingOnGround()||FMath::Abs(Location.Z-InputAuditMark.Z)>3)return Fail(TEXT("jump_did_not_land"));
  Key(PC,EKeys::F7,true);return Wait(9,.15);
 case 9:
  Key(PC,EKeys::F7,false);
  if(!Movement->IsFlying()||Pawn->GetCapsuleComponent()->GetCollisionEnabled()==ECollisionEnabled::NoCollision)return Fail(TEXT("F7_flight_or_collision_contract_failed"));
  Record(TEXT("F7_collision_preserving_flight"));InputAuditMark=Location;Key(PC,EKeys::E,true);return Wait(10,.5);
 case 10:
  if(Location.Z-InputAuditMark.Z<90||Location.Z-InputAuditMark.Z>300)return Fail(TEXT("E_did_not_ascend_in_tour"));
  Record(TEXT("E_tour_ascent_cm"),Location.Z-InputAuditMark.Z);Key(PC,EKeys::E,false);Key(PC,EKeys::F7,true);return Wait(11,.15);
 case 11:
  Key(PC,EKeys::F7,false);
  if(Movement->IsFlying()||Pawn->GetCapsuleComponent()->GetCollisionEnabled()==ECollisionEnabled::NoCollision)return Fail(TEXT("F7_did_not_restore_ground_physics"));
  return Wait(12,1.3);
 case 12:
  if(!Movement->IsMovingOnGround())return Fail(TEXT("tour_exit_did_not_land"));
  Key(PC,EKeys::F8,true);return Wait(13,.15);
 case 13:
  Key(PC,EKeys::F8,false);
  if(!Clock->ShouldShowTimeControls()||!PC->bShowMouseCursor)return Fail(TEXT("F8_did_not_open_time_controls"));
  InputAuditMark=Location;Key(PC,EKeys::W,true);return Wait(14,.4);
 case 14:
  if(FVector::Dist2D(Location,InputAuditMark)>1)return Fail(TEXT("player_moves_while_time_panel_has_mouse"));
  Record(TEXT("F8_UI_blocks_walking_cm"),FVector::Dist2D(Location,InputAuditMark));Key(PC,EKeys::W,false);Key(PC,EKeys::F8,true);return Wait(15,.15);
 case 15:
  Key(PC,EKeys::F8,false);
  if(Clock->ShouldShowTimeControls()||PC->bShowMouseCursor)return Fail(TEXT("F8_did_not_restore_game_input"));
  Record(TEXT("F8_restores_game_input"));PC->SetControlRotation(FRotator::ZeroRotator);Axis(PC,EKeys::MouseX,20);Axis(PC,EKeys::MouseY,10);return Wait(16,.15);
 case 16:
  {
   const FRotator Rotation=PC->GetControlRotation();const double Yaw=FMath::Abs(FMath::UnwindDegrees(Rotation.Yaw)),Pitch=FMath::Abs(FMath::UnwindDegrees(Rotation.Pitch));
   if(Yaw<.1||Yaw>20||Pitch<.1||Pitch>20)return Fail(TEXT("mouse_axes_did_not_control_view"));
   Record(TEXT("MouseX_yaw_degrees"),Yaw);Record(TEXT("MouseY_pitch_degrees"),Pitch);Reset();Pawn->SetAuditControlled(true);Movement->MaxWalkSpeed=140;Report->SetBoolField(TEXT("normal_input_smoke_passed"),true);return ECityImmersionInputAudit::Passed;
  }
 default:return Fail(TEXT("invalid_input_audit_phase"));
 }
}
