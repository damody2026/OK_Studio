using UnrealBuildTool;

// The parent class of the mods' .dui panels and the check of a mod widget class (plan §6.13 D2). Depends on DreamGUI
// alone, so the ModKit cook host (a content-only project) can enable it to compile and check a mod's .dui.
public class OKModDream : ModuleRules
{
	public OKModDream(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "DreamGUI", "AssetRegistry" });
	}
}
