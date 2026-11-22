using System.IO;
using UnrealBuildTool;

// The OK mod host. ok_mod_host.dll (Tools/ok-mod, cargo) is loaded at run time with LoadLibrary like ok_rules.dll: no
// import library, so a checkout that never built the Rust host still compiles and runs, with mods off.
public class OKModding : ModuleRules
{
	public OKModding(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Json" });
		PrivateDependencyModuleNames.AddRange(new string[] { "Engine", "ApplicationCore" });
		// The C ABI header lives with the Rust host.
		PrivateIncludePaths.Add(Path.GetFullPath(Path.Combine(ModuleDirectory, "..", "..", "..", "..", "Tools", "ok-mod", "host", "include")));
	}
}
