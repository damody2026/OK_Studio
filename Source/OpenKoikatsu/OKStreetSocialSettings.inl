// ---- Settings menu (the button at the top left, above the minimap): voices, voice input and the API keys.
// Everything is kept in the player's settings file, player.json (OKStreetReadPlayerFile, Docs/API_KEYS.md):
//   voice.voice_mode  builtin (recorded clips) | tts (the local TTS) | cloud (Alibaba Cloud, needs its key) | off
//   asr.mode          local | cloud (needs the Alibaba Cloud key)
//   deepseek.api_key  free talk and the heroines' mind; without it the conversations keep to the built-in choices
//   aliyun.api_key    the cloud voices and voice input
// No key is needed to play: without them the game has its built-in choices and the local voices (or none).
// The voice servers learn a change at once (POST /cloud on ok-tts and ok-asr); a server started without its local
// model (the cloud was chosen at launch) has it again only after the next start, and says so.
// The key boxes are UMG text boxes (UEditableTextBox, ok-game-mcp ui_set can fill them); the choices are buttons.

FString AOKStreetSocialScene::VoiceModeLabel(const FString& Mode) const{
 return OKT(*(TEXT("ui.settings.voice_")+Mode));
}

// The keys and modes from player.json (after LoadVoiceSettings, which reads the voice section).
void AOKStreetSocialScene::LoadPlayerSettings(){
 auto& S=*State;if(S.SelfTest||S.RetargetSelfTest||S.Manifest.SavePath.IsEmpty())return;
 const TSharedRef<FJsonObject> Player=OKStreetReadPlayerFile(PlayerSettingsPath());
 const TSharedRef<FJsonObject> Deep=OKStreetPlayerSection(Player,TEXT("deepseek")),Ali=OKStreetPlayerSection(Player,TEXT("aliyun")),Asr=OKStreetPlayerSection(Player,TEXT("asr"));
 Deep->TryGetStringField(TEXT("api_key"),S.DeepSeekKey);Ali->TryGetStringField(TEXT("api_key"),S.AliyunKey);
 S.DeepSeekKey.TrimStartAndEndInline();S.AliyunKey.TrimStartAndEndInline();
 Ali->TryGetStringField(TEXT("base_url"),S.AliyunBaseUrl);Ali->TryGetStringField(TEXT("tts_model"),S.AliyunTtsModel);Ali->TryGetStringField(TEXT("asr_model"),S.AliyunAsrModel);
 FString Mode;if(Asr->TryGetStringField(TEXT("mode"),Mode)&&(Mode==TEXT("local")||Mode==TEXT("cloud")))S.AsrMode=Mode;
 // A cloud choice with no key left: the local voices / recognizer (the server was started that way too).
 if(S.AliyunKey.IsEmpty()&&S.VoiceMode==TEXT("cloud")){S.VoiceMode=TEXT("tts");S.TtsEnabled=true;S.CloudVoiceWanted=true;}
 if(S.AliyunKey.IsEmpty()&&S.AsrMode==TEXT("cloud")){S.AsrMode=TEXT("local");S.CloudAsrWanted=true;}
}

// The Alibaba Cloud section as the voice servers take it on POST /cloud ({"api_key": ""}: back to the local model).
static FString OKStreetCloudBody(const FOKStreetSceneState& S,bool On,const TCHAR* ModelField,const FString& Model){
 TSharedRef<FJsonObject> B=MakeShared<FJsonObject>();
 B->SetStringField(TEXT("api_key"),On?S.AliyunKey:FString());
 if(On){if(!S.AliyunBaseUrl.IsEmpty())B->SetStringField(TEXT("base_url"),S.AliyunBaseUrl);if(!Model.IsEmpty())B->SetStringField(ModelField,Model);}
 FString Out;FJsonSerializer::Serialize(B,TJsonWriterFactory<>::Create(&Out));return Out;
}

// Tells a voice server which way to go; a reply without its local model (started cloud-only) asks for a restart.
void AOKStreetSocialScene::PushCloudSetting(bool Voice){
 auto& S=*State;
 const bool On=!S.AliyunKey.IsEmpty()&&(Voice?S.VoiceMode==TEXT("cloud"):S.AsrMode==TEXT("cloud"));
 const FString Url=(Voice?S.TtsEndpoint:OKStreetFreeTalkAsrEndpoint())/TEXT("cloud");
 auto Request=FHttpModule::Get().CreateRequest();
 Request->SetURL(Url);Request->SetVerb(TEXT("POST"));Request->SetHeader(TEXT("Content-Type"),TEXT("application/json"));Request->SetTimeout(5);
 Request->SetContentAsString(OKStreetCloudBody(S,On,Voice?TEXT("tts_model"):TEXT("asr_model"),Voice?S.AliyunTtsModel:S.AliyunAsrModel));
 Request->OnProcessRequestComplete().BindWeakLambda(this,[this,Voice,On](FHttpRequestPtr,FHttpResponsePtr Response,bool Connected){
  if(!State)return;auto& S=*State;TSharedPtr<FJsonObject> J;bool Ok=false,LocalReady=true;FString Error;
  if(Connected&&Response.IsValid()&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Response->GetContentAsString()),J)&&J.IsValid()){
   J->TryGetBoolField(TEXT("ok"),Ok);J->TryGetBoolField(TEXT("local_ready"),LocalReady);J->TryGetStringField(TEXT("error"),Error);}
  const bool Wanted=Voice?S.VoiceMode!=TEXT("off"):true;
  if(!Connected||!Response.IsValid())S.SettingsNotice=Wanted?OKT(Voice?TEXT("ui.settings.tts_server_missing"):TEXT("ui.settings.asr_server_missing")):FString();
  else if(!Ok)S.SettingsNotice=OKT(TEXT("ui.settings.cloud_failed"))+Error;
  else if(!On&&!LocalReady&&Wanted)S.SettingsNotice=OKT(Voice?TEXT("ui.settings.local_voice_restart"):TEXT("ui.settings.local_asr_restart"));
  if(Voice&&On&&Connected&&Ok){S.CloudVoicesPrepared=false;PrepareCloudVoices();} // a new key or model: its own voices
  UE_LOG(LogTemp,Display,TEXT("Street settings: %s cloud %s -> %s"),Voice?TEXT("voice"):TEXT("asr"),On?TEXT("on"):TEXT("off"),Connected&&Ok?TEXT("ok"):*S.SettingsNotice);
  RebuildSettingsPanel();
 });
 Request->ProcessRequest();
}

void AOKStreetSocialScene::SetVoiceMode(const FString& Mode){
 if(!State)return;auto& S=*State;
 if(Mode!=TEXT("builtin")&&Mode!=TEXT("tts")&&Mode!=TEXT("cloud")&&Mode!=TEXT("off"))return;
 if(Mode==TEXT("cloud")&&S.AliyunKey.IsEmpty()){S.SettingsNotice=OKT(TEXT("ui.settings.cloud_needs_key"));RebuildSettingsPanel();return;}
 S.CloudVoiceWanted=false; // the player's own choice from now on
 const bool WasOff=S.VoiceMode==TEXT("off");
 S.VoiceMode=Mode;S.TtsEnabled=Mode==TEXT("tts")||Mode==TEXT("cloud");OKSetCrowdRuntimeSpeechMuted(Mode==TEXT("off"));
 S.SettingsNotice.Reset();
 S.TtsNotice=OKMsg(TEXT("ui.settings.voice_mode_set"),{{TEXT("name"),VoiceModeLabel(Mode)}});
 SaveVoiceSettings();
 // Voices were off at launch: no TTS server was started for them.
 if(WasOff&&Mode!=TEXT("off")&&Mode!=TEXT("builtin"))S.SettingsNotice=OKT(TEXT("ui.settings.voice_server_next_start"));
 if(Mode!=TEXT("off"))PushCloudSetting(true);
 if(S.TtsEnabled)ProbeTtsServer();
 ProbeVoiceInfo();RefreshUI();RebuildSettingsPanel();
}

void AOKStreetSocialScene::SetAsrMode(const FString& Mode){
 if(!State)return;auto& S=*State;
 if(Mode!=TEXT("local")&&Mode!=TEXT("cloud"))return;
 if(Mode==TEXT("cloud")&&S.AliyunKey.IsEmpty()){S.SettingsNotice=OKT(TEXT("ui.settings.cloud_needs_key"));RebuildSettingsPanel();return;}
 S.AsrMode=Mode;S.CloudAsrWanted=false;S.SettingsNotice.Reset();
 if(!S.SelfTest&&!S.Manifest.SavePath.IsEmpty()){
  const FString Path=PlayerSettingsPath();const TSharedRef<FJsonObject> Player=OKStreetReadPlayerFile(Path);
  OKStreetPlayerSection(Player,TEXT("asr"))->SetStringField(TEXT("mode"),Mode);
  FString Error;if(!OKStreetWritePlayerFile(Path,Player,Error))S.SettingsNotice=OKT(TEXT("ui.settings.save_failed"))+Error;
 }
 PushCloudSetting(false);RebuildSettingsPanel();
}

// The two key boxes into player.json. An emptied Alibaba Cloud key takes the cloud choices back to the local ones.
void AOKStreetSocialScene::SaveApiKeys(){
 if(!State)return;auto& S=*State;
 const FString Deep=SettingsDeepSeekBox?SettingsDeepSeekBox->GetText().ToString().TrimStartAndEnd():S.DeepSeekKey;
 const FString Ali=SettingsAliyunBox?SettingsAliyunBox->GetText().ToString().TrimStartAndEnd():S.AliyunKey;
 const bool AliChanged=Ali!=S.AliyunKey;
 S.DeepSeekKey=Deep;S.AliyunKey=Ali;S.SettingsNotice.Reset();
 if(!S.SelfTest&&!S.Manifest.SavePath.IsEmpty()){
  const FString Path=PlayerSettingsPath();const TSharedRef<FJsonObject> Player=OKStreetReadPlayerFile(Path);
  OKStreetPlayerSection(Player,TEXT("deepseek"))->SetStringField(TEXT("api_key"),Deep);
  OKStreetPlayerSection(Player,TEXT("aliyun"))->SetStringField(TEXT("api_key"),Ali);
  FString Error;S.SettingsNotice=OKStreetWritePlayerFile(Path,Player,Error)?OKT(TEXT("ui.settings.keys_saved")):OKT(TEXT("ui.settings.save_failed"))+Error;
 }
 UE_LOG(LogTemp,Display,TEXT("Street settings: keys saved (DeepSeek %s, Alibaba Cloud %s)"),Deep.IsEmpty()?TEXT("none"):TEXT("set"),Ali.IsEmpty()?TEXT("none"):TEXT("set"));
 if(Ali.IsEmpty()){
  if(S.VoiceMode==TEXT("cloud"))SetVoiceMode(TEXT("tts"));
  if(S.AsrMode==TEXT("cloud"))SetAsrMode(TEXT("local"));
 }else if(AliChanged){
  // The first key for cloud choices made without one (player.json of a package): turn them on now, no restart.
  const bool Voice=S.CloudVoiceWanted&&S.VoiceMode!=TEXT("cloud"),Asr=S.CloudAsrWanted&&S.AsrMode!=TEXT("cloud");
  S.CloudVoiceWanted=S.CloudAsrWanted=false;
  if(Voice)SetVoiceMode(TEXT("cloud"));
  else if(S.VoiceMode==TEXT("cloud"))PushCloudSetting(true); // a new key for choices already on the cloud
  if(Asr)SetAsrMode(TEXT("cloud"));
  else if(S.AsrMode==TEXT("cloud"))PushCloudSetting(false);
 }
 RefreshUI();RebuildSettingsPanel();
}

void AOKStreetSocialScene::ToggleSettingsMenu(){
 if(!State)return;auto& S=*State;S.SettingsOpen=!S.SettingsOpen;S.SettingsNotice.Reset();
 if(S.SettingsOpen){
  // The boxes show what is saved (the file may have been edited by hand meanwhile).
  LoadPlayerSettings();
  if(SettingsDeepSeekBox)SettingsDeepSeekBox->SetText(FText::FromString(S.DeepSeekKey));
  if(SettingsAliyunBox)SettingsAliyunBox->SetText(FText::FromString(S.AliyunKey));
 }
 RebuildSettingsPanel();
}

void AOKStreetSocialScene::RebuildSettingsPanel(){
 if(!State||!State->UiSettingsHolder.IsValid())return;auto& S=*State;
 if(!S.SettingsOpen){S.UiSettingsHolder->SetContent(SNullWidget::NullWidget);return;}
 auto MakeKeyBox=[this](TObjectPtr<UEditableTextBox>& Box,const TCHAR* Name,const FString& Tip,const FString& Value){
  if(!Box){Box=NewObject<UEditableTextBox>(this,Name);Box->SetIsPassword(true);Box->SetText(FText::FromString(Value));}
  Box->SetToolTipText(FText::FromString(Tip));Box->SetHintText(FText::FromString(OKT(TEXT("ui.settings.key_hint"))));
  return Box->TakeWidget();
 };
 TWeakObjectPtr<AOKStreetSocialScene> Weak(this);
 auto Label=[](const FString& Text,float Size=12.f,FLinearColor Color=FLinearColor::White){return SNew(STextBlock).AutoWrapText(true).WrapTextAt(420).ColorAndOpacity(Color).Font(FCoreStyle::GetDefaultFontStyle("Regular",Size)).Text(FText::FromString(Text));};
 auto Choice=[&](const FString& Text,bool Current,bool Enabled,TFunction<void()> Act){
  return SNew(SButton).ButtonStyle(OKStreetGlassButton()).IsEnabled(Enabled).Text(FText::FromString((Current?TEXT("▶ "):TEXT(""))+Text)).OnClicked_Lambda([Act](){Act();return FReply::Handled();});
 };
 const bool HasAli=!S.AliyunKey.IsEmpty();
 TSharedRef<SVerticalBox> Box=SNew(SVerticalBox);
 Box->AddSlot().AutoHeight().Padding(0,0,0,8)[SNew(SHorizontalBox)
  +SHorizontalBox::Slot().FillWidth(1).VAlign(VAlign_Center)[Label(OKT(TEXT("ui.settings.title")),16.f)]
  +SHorizontalBox::Slot().AutoWidth()[SNew(SButton).ButtonStyle(OKStreetGlassButton()).Text(FText::FromString(OKT(TEXT("ui.settings.close")))).OnClicked_Lambda([Weak](){if(Weak.IsValid())Weak->ToggleSettingsMenu();return FReply::Handled();})]];
 // Voices.
 Box->AddSlot().AutoHeight().Padding(0,4)[Label(OKT(TEXT("ui.settings.voice_label")),13.f,FLinearColor(1,.83f,.35f))];
 {TSharedRef<SWrapBox> Row=SNew(SWrapBox).UseAllottedSize(true);
  for(const TCHAR* Mode:{TEXT("builtin"),TEXT("tts"),TEXT("cloud"),TEXT("off")}){const FString M=Mode;
   Row->AddSlot().Padding(2)[Choice(VoiceModeLabel(M),S.VoiceMode==M,M!=TEXT("cloud")||HasAli,[Weak,M](){if(Weak.IsValid())Weak->SetVoiceMode(M);})];}
  Box->AddSlot().AutoHeight()[Row];}
 // Voice input.
 Box->AddSlot().AutoHeight().Padding(0,8,0,4)[Label(OKT(TEXT("ui.settings.asr_label")),13.f,FLinearColor(1,.83f,.35f))];
 {TSharedRef<SWrapBox> Row=SNew(SWrapBox).UseAllottedSize(true);
  for(const TCHAR* Mode:{TEXT("local"),TEXT("cloud")}){const FString M=Mode;
   Row->AddSlot().Padding(2)[Choice(OKT(*(TEXT("ui.settings.asr_")+M)),S.AsrMode==M,M!=TEXT("cloud")||HasAli,[Weak,M](){if(Weak.IsValid())Weak->SetAsrMode(M);})];}
  Box->AddSlot().AutoHeight()[Row];}
 // Keys.
 Box->AddSlot().AutoHeight().Padding(0,10,0,2)[Label(OKT(TEXT("ui.settings.deepseek_key")),13.f,FLinearColor(1,.83f,.35f))];
 Box->AddSlot().AutoHeight().Padding(2)[MakeKeyBox(SettingsDeepSeekBox,TEXT("SettingsDeepSeekKey"),OKT(TEXT("ui.settings.deepseek_key")),S.DeepSeekKey)];
 Box->AddSlot().AutoHeight().Padding(0,6,0,2)[Label(OKT(TEXT("ui.settings.aliyun_key")),13.f,FLinearColor(1,.83f,.35f))];
 Box->AddSlot().AutoHeight().Padding(2)[MakeKeyBox(SettingsAliyunBox,TEXT("SettingsAliyunKey"),OKT(TEXT("ui.settings.aliyun_key")),S.AliyunKey)];
 Box->AddSlot().AutoHeight().HAlign(HAlign_Left).Padding(2,6)[SNew(SButton).ButtonStyle(OKStreetGlassButton()).Text(FText::FromString(OKT(TEXT("ui.settings.save_keys")))).OnClicked_Lambda([Weak](){if(Weak.IsValid())Weak->SaveApiKeys();return FReply::Handled();})];
 // What the keys give.
 FOKFreeTalkSettings Ai;FString Why;const bool AiReady=OKStreetFreeTalkLoadSettings(Ai,Why);
 Box->AddSlot().AutoHeight().Padding(0,6,0,0)[Label(OKT(AiReady?TEXT("ui.settings.deepseek_on"):TEXT("ui.settings.deepseek_off")),11.f,AiReady?FLinearColor(.55f,1.f,.7f):FLinearColor(.8f,.8f,.8f))];
 Box->AddSlot().AutoHeight()[Label(OKT(HasAli?TEXT("ui.settings.aliyun_on"):TEXT("ui.settings.aliyun_off")),11.f,HasAli?FLinearColor(.55f,1.f,.7f):FLinearColor(.8f,.8f,.8f))];
 if(!S.SettingsNotice.IsEmpty())Box->AddSlot().AutoHeight().Padding(0,6,0,0)[Label(S.SettingsNotice,11.f,FLinearColor(1,.83f,.35f))];
 Box->AddSlot().AutoHeight().Padding(0,8,0,0)[Label(OKMsg(TEXT("ui.settings.file_path"),{{TEXT("path"),FPaths::ConvertRelativePathToFull(PlayerSettingsPath())}}),10.f,FLinearColor(.7f,.7f,.7f))];
 static const FSlateRoundedBoxBrush SettingsBrush(FLinearColor(.025f,.045f,.075f,.97f),16.f);
 S.UiSettingsHolder->SetContent(SNew(SBox).WidthOverride(460)[SNew(SBorder).BorderImage(&SettingsBrush).Padding(14)[Box]]);
}
