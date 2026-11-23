using System.IO;
using UnrealBuildTool;

// The OK mod host. ok_mod_host.dll (Tools/ok-mod, cargo) is loaded at run time with LoadLibrary like ok_rules.dll: no
// import library, so a checkout that never built the Rust host still compiles and runs, with mods off.
public class OKModding : ModuleRules
{
	public OKModding(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		// KKUnityBundle: the shader family table (KKModMaterials.h) the card reader's parts consult.
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Json", "KKUnityBundle" });
		// RenderCore: the mods' shader libraries (FShaderCodeLibrary); RHI: GMaxRHIShaderPlatform.
		PrivateDependencyModuleNames.AddRange(new string[] { "Engine", "ApplicationCore", "RenderCore", "RHI" });
		// Projects: -ModDevContent mounts a mod's uncooked content plugin in the editor (IPluginManager).
		PrivateDependencyModuleNames.Add("Projects");
		// OKModDream: the check of a mod's .dui panel packages (plan §6.13 D2) when its pak is mounted.
		PrivateDependencyModuleNames.Add("OKModDream");
		// Slate, InputCore: the mod hotkeys (OKModKeys), one input pre-processor for every mode.
		PrivateDependencyModuleNames.AddRange(new string[] { "Slate", "SlateCore", "InputCore" });
		// The C ABI header lives with the Rust host.
		PrivateIncludePaths.Add(Path.GetFullPath(Path.Combine(ModuleDirectory, "..", "..", "..", "..", "Tools", "ok-mod", "host", "include")));
	}
}
