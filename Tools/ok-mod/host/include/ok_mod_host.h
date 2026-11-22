// ok_mod_host.dll: the OK mod host, loaded in-process by Unreal (LoadLibrary / GetProcAddress, the same
// way as ok_rules.dll). It finds the mods in Mods/, decides which load, loads their Rust DLLs through
// abi_stable, dispatches events and disables a mod that panics (Docs/OK_MOD_FRAMEWORK_PLAN.md).
//
// All strings are UTF-8; requests and answers are JSON. Every returned string must be released with
// okm_free. No call ever unwinds into the caller: errors come back as NULL plus okm_last_error.
// One okm_host is used from one thread at a time (the game thread); the log callback may be called
// from that thread during any okm_* call.
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct okm_host okm_host;

// ABI version; Unreal refuses a DLL whose version differs from the one it was built against.
#define OKM_ABI_VERSION 1
uint32_t okm_abi_version(void);

// Log levels passed to okm_log_fn.
#define OKM_LOG_ERROR 1
#define OKM_LOG_WARN 2
#define OKM_LOG_INFO 3
#define OKM_LOG_VERBOSE 4

// mod_id is "" for the host's own messages. Both strings are valid only during the call.
typedef void (*okm_log_fn)(void* user, int32_t level, const char* mod_id, const char* message);

// config_json:
//   {"mods_dir": "<stage root>/Mods", "config_dir": "<...>/UserData/config/mods" (optional),
//    "target": "reader" | "studio" | "pair" | "street" | "extract",
//    "no_mods": false (-NoMods: load nothing), "disabled": ["mod.id", ...] (optional)}
// Discovers, resolves and loads the mods and sends them "enabled". A broken mod never makes this
// fail; it shows up as rejected/faulted in "list". Returns NULL only for a bad config_json.
okm_host* okm_open(const char* config_json, okm_log_fn log, void* user);

// request_json, by "op":
//   {"op":"list"}
//       -> {"host_version","api_version","abi_version","target","modes":[modes this process ran],"no_mods",
//           "mods":[{"id","name","version","dir","state":"enabled|skipped|rejected|faulted|disabled",
//                    "reason"?,"order"?,"rustc"?,"commands":["mod.<id>.<name>",...],"subscriptions":[...]}]}
//   {"op":"event","event":"mode_enter"|"mode_exit","mode":"reader"}
//       -> {"replies":[{"mod","ok",("text"|"json"|"error")?}]}   (only mods that subscribed)
//       mode_enter for a mode this process has not run yet first loads the mods that target it (the street hands
//       over to the 1-on-1 scene in the same process); mode_exit leaves every mod loaded.
//   {"op":"command","command":"mod.<id>.<name>","args":"..."}  or  {"op":"command","mod","name","args"}
//       -> {"ok":true,"text"?|"json"?} | {"ok":false,"error"}
//   {"op":"config","mod":"<id>"}
//       -> [{"key","type":"bool|int|float|text|hotkey","value","default","min","max","description_id"}]
//   {"op":"config_set","mod","key","value"} -> {"ok":true} | {"ok":false,"error"}  (saved; mod gets config_changed)
//   {"op":"disable","mod"} -> {"ok":true} | {"ok":false,"error"}   (this session only)
// Returns NULL for a malformed request (see okm_last_error).
const char* okm_dispatch(okm_host* host, const char* request_json);

void okm_free(const char* text);

// Last error on the calling thread, or NULL. Release with okm_free.
const char* okm_last_error(void);

// Sends shutdown to every enabled mod (last loaded first). The mod DLLs stay loaded until the
// process ends (abi_stable never unloads).
void okm_close(okm_host* host);

#ifdef __cplusplus
}
#endif
