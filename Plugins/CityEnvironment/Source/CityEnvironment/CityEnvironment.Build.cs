using UnrealBuildTool;
using System.IO;

public class CityEnvironment : ModuleRules
{
    public CityEnvironment(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        // The Astronomy translation unit undefines engine macros. Keep it out of unity blobs.
        bUseUnity = false;
        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core",
            "CoreUObject",
            "Engine",
            "InputCore",
            "UMG",
            "Slate",
            "SlateCore",
            "CityLocalization"
        });
        PrivateDependencyModuleNames.AddRange(new string[] { "Json", "RHI", "RenderCore", "PhysicsCore" });
        PrivateIncludePaths.Add(Path.Combine(ModuleDirectory, "..", "ThirdParty", "Astronomy"));
    }
}
