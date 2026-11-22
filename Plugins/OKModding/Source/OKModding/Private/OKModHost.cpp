#include "OKModHost.h"
#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "HAL/PlatformProcess.h"
#include "Misc/CommandLine.h"
#include "Misc/OutputDevice.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Modules/ModuleManager.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include <Windows.h>
#include "Windows/HideWindowsPlatformTypes.h"
#endif
#include "ok_mod_host.h"

DEFINE_LOG_CATEGORY(LogOKMod);

// Must match OKM_ABI_VERSION in Tools/ok-mod/host/include/ok_mod_host.h.
static_assert(OKM_ABI_VERSION == 1, "ok_mod_host.h changed: check the functions FOKModHost::FApi loads");

struct FOKModHost::FApi
{
	using FAbi = uint32 (*)();
	using FOpen = okm_host* (*)(const char*, okm_log_fn, void*);
	using FDispatch = const char* (*)(okm_host*, const char*);
	using FFree = void (*)(const char*);
	using FLastError = const char* (*)();
	using FClose = void (*)(okm_host*);
	FAbi Abi = nullptr; FOpen Open = nullptr; FDispatch Dispatch = nullptr; FFree Free = nullptr; FLastError LastError = nullptr; FClose Close = nullptr;

	FString Take(const char* Text) const
	{
		if (!Text) return FString();
		FString Out = UTF8_TO_TCHAR(Text);
		Free(Text);
		return Out;
	}
};

static FString OKModJson(const TSharedRef<FJsonObject>& Object)
{
	FString Json;
	FJsonSerializer::Serialize(Object, TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json));
	return Json;
}

static void OKModLog(void*, int32 Level, const char* ModId, const char* Message)
{
	const FString Id = UTF8_TO_TCHAR(ModId ? ModId : "");
	const FString Text = UTF8_TO_TCHAR(Message ? Message : "");
	const FString Line = Id.IsEmpty() ? Text : FString::Printf(TEXT("[%s] %s"), *Id, *Text);
	switch (Level)
	{
	case OKM_LOG_ERROR: UE_LOG(LogOKMod, Error, TEXT("%s"), *Line); break;
	case OKM_LOG_WARN: UE_LOG(LogOKMod, Warning, TEXT("%s"), *Line); break;
	case OKM_LOG_INFO: UE_LOG(LogOKMod, Display, TEXT("%s"), *Line); break;
	default: UE_LOG(LogOKMod, Verbose, TEXT("%s"), *Line); break;
	}
}

FOKModHost& FOKModHost::Get()
{
	static FOKModHost Host;
	return Host;
}

void FOKModHost::Startup()
{
	if (bStarted) return;
	bStarted = true;
	bool bShift = false;
#if PLATFORM_WINDOWS
	bShift = (::GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
#endif
	bTurnedOff = FParse::Param(FCommandLine::Get(), TEXT("NoMods")) || bShift;
	if (bTurnedOff) UE_LOG(LogOKMod, Display, TEXT("Mods are off for this run (%s)"), bShift ? TEXT("Shift held at start") : TEXT("-NoMods"));
}

FString FOKModHost::ModsDir()
{
	FString Dir;
	if (FParse::Value(FCommandLine::Get(), TEXT("ModsDir="), Dir) && !Dir.IsEmpty()) return FPaths::ConvertRelativePathToFull(Dir);
	Dir = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_MODS_DIR"));
	if (!Dir.IsEmpty()) return FPaths::ConvertRelativePathToFull(Dir);
	// A staged game: the stage root holds stage.json (Tools/street_stage.lua); Mods/ sits beside it, a plain folder.
	for (FString At = FPaths::ConvertRelativePathToFull(FPlatformProcess::BaseDir()); !At.IsEmpty();)
	{
		At.RemoveFromEnd(TEXT("/"));
		if (IFileManager::Get().FileExists(*(At / TEXT("stage.json")))) return At / TEXT("Mods");
		const FString Parent = FPaths::GetPath(At);
		if (Parent == At || Parent.Len() < 3) break;
		At = Parent;
	}
	return FPaths::ConvertRelativePathToFull(FPaths::ProjectDir() / TEXT("Mods"));
}

FString FOKModHost::ConfigDir()
{
	const FString Env = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_MODS_CONFIG_DIR"));
	if (!Env.IsEmpty()) return FPaths::ConvertRelativePathToFull(Env);
	return FPaths::GetPath(ModsDir()) / TEXT("UserData/config/mods");
}

TArray<FString> FOKModHost::DllCandidates()
{
	TArray<FString> Out;
	const FString Env = FPlatformMisc::GetEnvironmentVariable(TEXT("OK_MOD_HOST_DLL"));
	if (!Env.IsEmpty()) Out.Add(Env);
	Out.Add(FPaths::ConvertRelativePathToFull(FPaths::Combine(FPlatformProcess::BaseDir(), TEXT("ok_mod_host.dll"))));
	Out.Add(FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("Tools/ok-mod/target/release/ok_mod_host.dll"))));
	return Out;
}

static FOKModHost::FApi* OKModLoadApi(const FString& Path, FString& Error)
{
	void* Dll = FPlatformProcess::GetDllHandle(*Path);
	if (!Dll) { Error = TEXT("could not load ") + Path; return nullptr; }
	auto* Api = new FOKModHost::FApi();
	auto Get = [&](const TCHAR* Name) { return FPlatformProcess::GetDllExport(Dll, Name); };
	Api->Abi = (FOKModHost::FApi::FAbi)Get(TEXT("okm_abi_version"));
	Api->Open = (FOKModHost::FApi::FOpen)Get(TEXT("okm_open"));
	Api->Dispatch = (FOKModHost::FApi::FDispatch)Get(TEXT("okm_dispatch"));
	Api->Free = (FOKModHost::FApi::FFree)Get(TEXT("okm_free"));
	Api->LastError = (FOKModHost::FApi::FLastError)Get(TEXT("okm_last_error"));
	Api->Close = (FOKModHost::FApi::FClose)Get(TEXT("okm_close"));
	if (!Api->Abi || !Api->Open || !Api->Dispatch || !Api->Free || !Api->LastError || !Api->Close)
	{
		Error = TEXT("missing okm_* exports in ") + Path;
		delete Api;
		return nullptr;
	}
	if (Api->Abi() != OKM_ABI_VERSION)
	{
		Error = FString::Printf(TEXT("%s has okm ABI %u, this game needs %d"), *Path, Api->Abi(), OKM_ABI_VERSION);
		delete Api;
		return nullptr;
	}
	return Api;
}

bool FOKModHost::Open(const FString& Mode)
{
	FString Error, Path;
	for (const FString& Candidate : DllCandidates())
	{
		if (!FPaths::FileExists(Candidate)) continue;
		Api = OKModLoadApi(Candidate, Error);
		if (Api) { Path = Candidate; break; }
	}
	if (!Api)
	{
		UE_LOG(LogOKMod, Warning, TEXT("Mods are off: %s"), Error.IsEmpty() ? TEXT("ok_mod_host.dll not found (cargo build --release in Tools/ok-mod)") : *Error);
		return false;
	}
	TSharedRef<FJsonObject> Config = MakeShared<FJsonObject>();
	Config->SetStringField(TEXT("mods_dir"), ModsDir());
	Config->SetStringField(TEXT("config_dir"), ConfigDir());
	Config->SetStringField(TEXT("target"), Mode);
	UE_LOG(LogOKMod, Display, TEXT("Mod host %s, mods in %s, mode %s"), *Path, *ModsDir(), *Mode);
	okm_host* NewHandle = Api->Open(TCHAR_TO_UTF8(*OKModJson(Config)), &OKModLog, nullptr);
	if (!NewHandle)
	{
		UE_LOG(LogOKMod, Warning, TEXT("Mods are off: okm_open failed: %s"), *Api->Take(Api->LastError()));
		return false;
	}
	FWriteScopeLock Locked(Lock);
	Handle = NewHandle;
	return true;
}

void FOKModHost::EnterMode(const FString& Mode)
{
	check(IsInGameThread());
	if (!bStarted) Startup();
	if (bTurnedOff || bOpenFailed) return;
	if (!Handle)
	{
		if (!Open(Mode)) { bOpenFailed = true; return; }
	}
	Current = Mode;
	TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
	Request->SetStringField(TEXT("op"), TEXT("event"));
	Request->SetStringField(TEXT("event"), TEXT("mode_enter"));
	Request->SetStringField(TEXT("mode"), Mode);
	FString Error;
	if (!DispatchJson(Request, Error).IsValid()) UE_LOG(LogOKMod, Warning, TEXT("mode_enter %s: %s"), *Mode, *Error);
	RegisterCommands();
}

void FOKModHost::ExitMode(const FString& Mode)
{
	if (!Handle) return;
	if (Current == Mode) Current.Empty();
	TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
	Request->SetStringField(TEXT("op"), TEXT("event"));
	Request->SetStringField(TEXT("event"), TEXT("mode_exit"));
	Request->SetStringField(TEXT("mode"), Mode);
	FString Error;
	DispatchJson(Request, Error);
}

bool FOKModHost::Dispatch(const FString& Request, FString& Answer, FString& Error)
{
	FReadScopeLock Locked(Lock);
	if (!Handle || !Api) { Error = bTurnedOff ? TEXT("mods are off (-NoMods)") : TEXT("the mod host is not open"); return false; }
	const char* Text = Api->Dispatch(static_cast<okm_host*>(Handle), TCHAR_TO_UTF8(*Request));
	if (!Text) { Error = Api->Take(Api->LastError()); return false; }
	Answer = Api->Take(Text);
	return true;
}

TSharedPtr<FJsonObject> FOKModHost::DispatchJson(const TSharedRef<FJsonObject>& Request, FString& Error)
{
	FString Answer;
	if (!Dispatch(OKModJson(Request), Answer, Error)) return nullptr;
	TSharedPtr<FJsonObject> Out;
	// Some answers are arrays ("config"): wrap them so callers always get an object.
	if (Answer.StartsWith(TEXT("[")))
	{
		TArray<TSharedPtr<FJsonValue>> Rows;
		if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Answer), Rows)) { Error = TEXT("invalid JSON from the mod host"); return nullptr; }
		Out = MakeShared<FJsonObject>();
		Out->SetArrayField(TEXT("items"), Rows);
		return Out;
	}
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Answer), Out) || !Out.IsValid()) { Error = TEXT("invalid JSON from the mod host: ") + Answer.Left(200); return nullptr; }
	return Out;
}

TSharedPtr<FJsonObject> FOKModHost::List()
{
	TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
	Request->SetStringField(TEXT("op"), TEXT("list"));
	FString Error;
	return DispatchJson(Request, Error);
}

// Every mod command becomes the console command mod.<id>.<name>, registered at run time (the core's own commands are
// compile-time FAutoConsoleCommand; a mod's are only known once it registered).
void FOKModHost::RegisterCommands()
{
	const TSharedPtr<FJsonObject> Listing = List();
	const TArray<TSharedPtr<FJsonValue>>* Mods = nullptr;
	if (!Listing.IsValid() || !Listing->TryGetArrayField(TEXT("mods"), Mods)) return;
	for (const TSharedPtr<FJsonValue>& Mod : *Mods)
	{
		const TArray<TSharedPtr<FJsonValue>>* Commands = nullptr;
		if (!Mod->AsObject()->TryGetArrayField(TEXT("commands"), Commands)) continue;
		for (const TSharedPtr<FJsonValue>& Command : *Commands)
		{
			const FString Name = Command->AsString();
			if (Registered.Contains(Name)) continue;
			Registered.Add(Name);
			IConsoleManager::Get().RegisterConsoleCommand(*Name, *FString::Printf(TEXT("Mod command (%s)"), *Name),
				FConsoleCommandWithArgsAndOutputDeviceDelegate::CreateLambda([Name](const TArray<FString>& Args, FOutputDevice& Out)
				{
					TSharedRef<FJsonObject> Request = MakeShared<FJsonObject>();
					Request->SetStringField(TEXT("op"), TEXT("command"));
					Request->SetStringField(TEXT("command"), Name);
					Request->SetStringField(TEXT("args"), FString::Join(Args, TEXT(" ")));
					FString Error;
					const TSharedPtr<FJsonObject> Reply = FOKModHost::Get().DispatchJson(Request, Error);
					FString Text;
					if (!Reply.IsValid()) Text = Error;
					else if (!Reply->GetBoolField(TEXT("ok"))) Text = TEXT("error: ") + Reply->GetStringField(TEXT("error"));
					else if (!Reply->TryGetStringField(TEXT("text"), Text)) Text = Reply->HasField(TEXT("json")) ? OKModJson(Reply.ToSharedRef()) : TEXT("ok");
					Out.Log(Text);
					UE_LOG(LogOKMod, Display, TEXT("%s -> %s"), *Name, *Text);
				}),
				ECVF_Default);
		}
	}
}

void FOKModHost::Close()
{
	FWriteScopeLock Locked(Lock);
	if (Handle && Api) Api->Close(static_cast<okm_host*>(Handle));
	Handle = nullptr;
	for (const FString& Name : Registered)
		if (IConsoleObject* Object = IConsoleManager::Get().FindConsoleObject(*Name)) IConsoleManager::Get().UnregisterConsoleObject(Object);
	Registered.Empty();
}

const char* FOKModHost::RustDispatch(const char* RequestUtf8)
{
	if (!RequestUtf8) return nullptr;
	FString Answer, Error;
	if (!Get().Dispatch(UTF8_TO_TCHAR(RequestUtf8), Answer, Error)) return nullptr;
	const FTCHARToUTF8 Utf8(*Answer);
	char* Out = static_cast<char*>(FMemory::Malloc(Utf8.Length() + 1));
	FMemory::Memcpy(Out, Utf8.Get(), Utf8.Length());
	Out[Utf8.Length()] = 0;
	return Out;
}

void FOKModHost::RustFree(const char* Text)
{
	if (Text) FMemory::Free(const_cast<char*>(Text));
}

static void OKModConsoleList(const TArray<FString>&, FOutputDevice& Out)
{
	FOKModHost& Host = FOKModHost::Get();
	if (Host.IsTurnedOff()) { Out.Log(TEXT("Mods are off for this run (-NoMods or Shift at start).")); return; }
	const TSharedPtr<FJsonObject> Listing = Host.List();
	if (!Listing.IsValid()) { Out.Log(FString::Printf(TEXT("The mod host is not open (mods dir %s)."), *FOKModHost::ModsDir())); return; }
	const TArray<TSharedPtr<FJsonValue>>* Mods = nullptr;
	Listing->TryGetArrayField(TEXT("mods"), Mods);
	TArray<FString> Modes;
	Listing->TryGetStringArrayField(TEXT("modes"), Modes);
	Out.Log(FString::Printf(TEXT("Mod host %s (ok-mod-api %s), modes %s, %d mod(s) in %s"), *Listing->GetStringField(TEXT("host_version")),
		*Listing->GetStringField(TEXT("api_version")), *FString::Join(Modes, TEXT("/")), Mods ? Mods->Num() : 0, *FOKModHost::ModsDir()));
	if (Mods)
		for (const TSharedPtr<FJsonValue>& Value : *Mods)
		{
			const TSharedPtr<FJsonObject> Mod = Value->AsObject();
			FString Reason;
			Mod->TryGetStringField(TEXT("reason"), Reason);
			Out.Log(FString::Printf(TEXT("  %s %s: %s%s"), *Mod->GetStringField(TEXT("id")), *Mod->GetStringField(TEXT("version")),
				*Mod->GetStringField(TEXT("state")), Reason.IsEmpty() ? TEXT("") : *(TEXT(" (") + Reason + TEXT(")"))));
		}
}

static void OKModConsoleCall(const TArray<FString>& Args, FOutputDevice& Out)
{
	FString Answer, Error;
	if (FOKModHost::Get().Dispatch(FString::Join(Args, TEXT(" ")), Answer, Error)) Out.Log(Answer);
	else Out.Log(TEXT("error: ") + Error);
}

static FAutoConsoleCommandWithArgsAndOutputDevice GOKModList(TEXT("mod.list"), TEXT("Mods: each one's version and state (enabled, skipped, rejected, faulted) with the reason."),
	FConsoleCommandWithArgsAndOutputDeviceDelegate::CreateStatic(&OKModConsoleList));
static FAutoConsoleCommandWithArgsAndOutputDevice GOKModCall(TEXT("mod.call"), TEXT("Mods: one raw mod host request, e.g. mod.call {\"op\":\"config\",\"mod\":\"org.openkoikatsu.hello\"}"),
	FConsoleCommandWithArgsAndOutputDeviceDelegate::CreateStatic(&OKModConsoleCall));

class FOKModdingModule final : public IModuleInterface
{
public:
	virtual void StartupModule() override { FOKModHost::Get().Startup(); }
	virtual void ShutdownModule() override { FOKModHost::Get().Close(); }
};
IMPLEMENT_MODULE(FOKModdingModule, OKModding)
