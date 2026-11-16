using UnrealBuildTool;
using System.IO;

public class OKStudio : ModuleRules
{
	public OKStudio(ReadOnlyTargetRules Target) : base(Target)
	{
        string ChildAnimationFile = Path.Combine(Path.GetDirectoryName(Target.ProjectFile.FullName), "Content", "IndependentResources", "base_v1", "studio_child_animations.json");
        if (File.Exists(ChildAnimationFile)) RuntimeDependencies.Add(ChildAnimationFile, StagedFileType.NonUFS);
        string MapEnvironmentFile = Path.Combine(Path.GetDirectoryName(Target.ProjectFile.FullName), "Content", "IndependentResources", "base_v1", "studio", "map_environments.json");
        if (File.Exists(MapEnvironmentFile)) RuntimeDependencies.Add(MapEnvironmentFile, StagedFileType.NonUFS);
        string ReflectionRoot = Path.GetDirectoryName(MapEnvironmentFile);
        string ReflectionIndex = Path.Combine(ReflectionRoot, "map_reflections.json");
        if (File.Exists(ReflectionIndex)) RuntimeDependencies.Add(ReflectionIndex, StagedFileType.NonUFS);
        string ReflectionCubes = Path.Combine(ReflectionRoot, "reflections");
        if (Directory.Exists(ReflectionCubes)) foreach (string FileName in Directory.GetFiles(ReflectionCubes, "*.okcube")) RuntimeDependencies.Add(FileName, StagedFileType.NonUFS);
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		// Files keep file-scope helpers with short names (OKStudioPost.cpp's Base / Instance): no unity blobs.
		bUseUnity = false;
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "Json", "JsonUtilities", "Slate", "SlateCore", "InputCore", "HTTPServer" });
		PrivateDependencyModuleNames.AddRange(new string[] { "KKUnityBundle", "KKCard", "OKAnimation", "OKHGShading", "KKRuntimePose", "RHI", "UMG", "RenderCore", "ImageCore", "Niagara", "XmlParser", "HTTP", "HTTPServer", "Sockets", "Networking", "ImageWrapper", "ApplicationCore", "ProceduralMeshComponent" });
		// U277 outside models: ufbx (MIT, single file), the engine's copy that its Interchange FBX parser compiles; it is
		// built into OKStudioFbx.cpp. _UCRT_LEGACY_INFINITY as Interchange sets it (newer Windows SDKs' INFINITY overflows).
		PrivateIncludePaths.Add(Path.Combine(EngineDirectory, "Plugins", "Interchange", "Runtime", "Source", "Parsers", "ThirdParty", "uFBX", "0.21.2"));
		PrivateDefinitions.Add("_UCRT_LEGACY_INFINITY");
	}
}
