using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Reflection;
using UnityEngine;

// OK_PROBE_MAP_TOUR=<map:sun,...>: the sky and the sea of a map at a time of day, for the comparison with OK Studio.
// Each stop writes <output>.map<no>_sun<t>_y<yaw>_p<pitch>.png from fixed views (Unity space) and <output>.map<no>_sun<t>.tsv
// with the sky, the lights and every property of the water materials. Nothing is saved in the game.
public sealed partial class GamePoseProbe {
    private static readonly float[][] TourViews = {
        // yaw, pitch (up is positive): the sky all round, then the ground or the sea below it.
        new[] { 0f, 20f }, new[] { 90f, 20f }, new[] { 180f, 20f }, new[] { 270f, 20f }, new[] { 0f, 70f },
        new[] { 0f, -15f }, new[] { 90f, -15f }, new[] { 180f, -15f }, new[] { 270f, -15f } };

    // GetMethod does not return a base class's private method (AmplifyColorBase.OnRenderImage).
    private static bool DrawsImage(Type type) {
        for (; type != null && type != typeof(MonoBehaviour); type = type.BaseType)
            if (type.GetMethod("OnRenderImage", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly) != null) return true;
        return false;
    }

    private static string MaterialValue(Material material, Shader shader, int property) {
        string name = shader.GetPropertyName(property);
        switch (shader.GetPropertyType(property)) {
            case UnityEngine.Rendering.ShaderPropertyType.Color: return material.GetColor(name).ToString("R");
            case UnityEngine.Rendering.ShaderPropertyType.Vector: return material.GetVector(name).ToString("R");
            case UnityEngine.Rendering.ShaderPropertyType.Texture: {
                Texture t = material.GetTexture(name);
                return t == null ? "null" : t.name + ":" + t.width + ":" + t.height + ":" + t.GetType().Name;
            }
            default: return material.GetFloat(name).ToString("R");
        }
    }

    // Everything drawn at this stop: renderers with their lightmaps, each material's properties once, and terrains.
    private static void WriteTourMaterials(string file) {
        var seen = new System.Collections.Generic.HashSet<Material>();
        using (var writer = new StreamWriter(file)) {
            foreach (Terrain terrain in UnityEngine.Object.FindObjectsOfType<Terrain>())
                writer.WriteLine("terrain\t" + PathOf(terrain.transform) + "\t" + terrain.terrainData.size.ToString("R") + "\t" + terrain.lightmapIndex);
            foreach (Renderer renderer in UnityEngine.Object.FindObjectsOfType<Renderer>()) {
                if (!renderer.enabled || !renderer.gameObject.activeInHierarchy) continue;
                MeshFilter filter = renderer.GetComponent<MeshFilter>();
                foreach (Material material in renderer.sharedMaterials) {
                    if (material == null) continue;
                    writer.WriteLine("renderer\t" + PathOf(renderer.transform) + "\t" + (filter == null || filter.sharedMesh == null ? "" : filter.sharedMesh.name) + "\t" + material.name + "\t" + material.shader.name + "\t" + renderer.lightmapIndex + "\t" + renderer.lightmapScaleOffset.ToString("R") + "\t" + renderer.bounds.center.ToString("R") + "\t" + renderer.bounds.size.ToString("R") + "\tlayer=" + renderer.gameObject.layer);
                    if (!seen.Add(material)) continue;
                    writer.WriteLine("material\t" + material.name + "\t" + material.shader.name + "\t" + material.renderQueue + "\t" + String.Join(",", material.shaderKeywords));
                    for (int p = 0; p < material.shader.GetPropertyCount(); ++p)
                        writer.WriteLine("material_prop\t" + material.name + "\t" + material.shader.GetPropertyName(p) + "\t" + MaterialValue(material, material.shader, p));
                }
            }
            writer.WriteLine("lightmaps\t" + LightmapSettings.lightmaps.Length + "\t" + LightmapSettings.lightmapsMode);
        }
    }

    private static void WriteTourStop(Studio.Map map, string file) {
        using (var writer = new StreamWriter(file)) {
            writer.WriteLine("map\t" + map.no + "\tsun\t" + (int)map.sunType + "\tsky_info\t" + map.isSkyInfo);
            Material sky = RenderSettings.skybox;
            writer.WriteLine("skybox\t" + (sky == null ? "null" : sky.name + "\t" + sky.shader.name));
            if (sky != null) {
                writer.WriteLine("sky_keywords\t" + String.Join(",", sky.shaderKeywords));
                for (int p = 0; p < sky.shader.GetPropertyCount(); ++p) {
                    string name = sky.shader.GetPropertyName(p);
                    switch (sky.shader.GetPropertyType(p)) {
                        case UnityEngine.Rendering.ShaderPropertyType.Color: writer.WriteLine("sky_prop\t" + name + "\t" + sky.GetColor(name).ToString("R")); break;
                        case UnityEngine.Rendering.ShaderPropertyType.Vector: writer.WriteLine("sky_prop\t" + name + "\t" + sky.GetVector(name).ToString("R")); break;
                        case UnityEngine.Rendering.ShaderPropertyType.Texture: { Texture t = sky.GetTexture(name); writer.WriteLine("sky_prop\t" + name + "\t" + (t == null ? "null" : t.name)); break; }
                        default: writer.WriteLine("sky_prop\t" + name + "\t" + sky.GetFloat(name).ToString("R")); break;
                    }
                }
            }
            writer.WriteLine("quality\tpixel_lights=" + QualitySettings.pixelLightCount + " shadow_distance=" + QualitySettings.shadowDistance);
            writer.WriteLine("ambient\t" + RenderSettings.ambientMode + "\t" + RenderSettings.ambientIntensity.ToString("R") + "\t" + RenderSettings.ambientLight.ToString("R") + "\t" + RenderSettings.ambientSkyColor.ToString("R"));
            writer.WriteLine("fog\t" + RenderSettings.fog + "\t" + RenderSettings.fogMode + "\t" + RenderSettings.fogColor.ToString("R") + "\t" + RenderSettings.fogDensity.ToString("R"));
            foreach (Light light in UnityEngine.Object.FindObjectsOfType<Light>())
                if (light.enabled && light.gameObject.activeInHierarchy)
                    writer.WriteLine("light\t" + PathOf(light.transform) + "\t" + light.type + "\t" + light.color.ToString("R") + "\t" + light.intensity.ToString("R") + "\t" + light.transform.forward.ToString("R") + "\tenabled=" + light.enabled + " mask=" + light.cullingMask + " render=" + light.renderMode + " baked=" + light.bakingOutput.lightmapBakeType + " shadows=" + light.shadows);
            foreach (Renderer renderer in UnityEngine.Object.FindObjectsOfType<Renderer>()) {
                if (!renderer.enabled || !renderer.gameObject.activeInHierarchy) continue;
                foreach (Material material in renderer.sharedMaterials) {
                    if (material == null) continue;
                    string shaderName = material.shader.name;
                    if (shaderName.IndexOf("water", StringComparison.OrdinalIgnoreCase) < 0 && renderer.name.IndexOf("sea", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    writer.WriteLine("water\t" + PathOf(renderer.transform) + "\t" + material.name + "\t" + shaderName + "\t" + renderer.bounds.center.ToString("R") + "\t" + renderer.bounds.size.ToString("R") + "\t" + String.Join(",", material.shaderKeywords));
                    Shader shader = material.shader;
                    for (int p = 0; p < shader.GetPropertyCount(); ++p) {
                        string name = shader.GetPropertyName(p);
                        string value;
                        switch (shader.GetPropertyType(p)) {
                            case UnityEngine.Rendering.ShaderPropertyType.Color: value = material.GetColor(name).ToString("R"); break;
                            case UnityEngine.Rendering.ShaderPropertyType.Vector: value = material.GetVector(name).ToString("R"); break;
                            case UnityEngine.Rendering.ShaderPropertyType.Texture: {
                                Texture t = material.GetTexture(name);
                                value = t == null ? "null" : t.name + ":" + t.width + ":" + t.height + ":" + t.GetType().Name;
                                break;
                            }
                            default: value = material.GetFloat(name).ToString("R"); break;
                        }
                        writer.WriteLine("water_prop\t" + material.name + "\t" + name + "\t" + value);
                    }
                }
            }
        }
    }

    private IEnumerator MapTour(Studio.Studio studio, string tour) {
        string output = Environment.GetEnvironmentVariable("OK_GAME_POSE_OUTPUT");
        if (String.IsNullOrEmpty(output)) throw new InvalidOperationException("Map tour requires OK_GAME_POSE_OUTPUT");
        string heightText = Environment.GetEnvironmentVariable("OK_PROBE_TOUR_HEIGHT");
        float height = String.IsNullOrEmpty(heightText) ? 30f : float.Parse(heightText, CultureInfo.InvariantCulture);
        studio.InitScene(false);
        for (int frame = 0; frame < 60; ++frame) yield return null;
        Studio.Map map = Singleton<Studio.Map>.Instance;
        foreach (string stop in tour.Split(',')) {
            string[] parts = stop.Split(':');
            int no = int.Parse(parts[0]), sun = int.Parse(parts[1]);
            yield return map.LoadMapCoroutine(no, false);
            for (int frame = 0; frame < 60; ++frame) yield return null;
            if (map.isSunLightInfo && !map.IsTimeZone(sun)) continue;
            map.sunType = (SunLightInfo.Info.Type)sun;
            for (int frame = 0; frame < 60; ++frame) yield return null;
            yield return new WaitForEndOfFrame();
            string name = output + ".map" + no + "_sun" + sun;
            WriteTourStop(map, name + ".tsv");
            WriteTourMaterials(name + ".materials.tsv");
            Camera main = Camera.main;
            Vector3 position = main.transform.position; Quaternion rotation = main.transform.rotation; float fov = main.fieldOfView;
            try {
                main.fieldOfView = 60f;
                main.transform.position = new Vector3(0f, height, 0f);
                foreach (float[] view in TourViews) {
                    main.transform.rotation = Quaternion.Euler(-view[1], view[0], 0f);
                    CaptureMain(main, name + "_y" + (int)view[0] + "_p" + (int)view[1] + ".png");
                }
                // The same views without the camera's image effects: what the sky and the sea draw themselves.
                var effects = new System.Collections.Generic.List<Behaviour>();
                using (var writer = new StreamWriter(name + ".post.tsv"))
                    foreach (Behaviour effect in main.GetComponents<Behaviour>()) {
                        writer.WriteLine("effect\t" + effect.GetType().FullName + "\t" + effect.enabled);
                        if (effect.enabled && DrawsImage(effect.GetType())) effects.Add(effect);
                        var grade = effect as AmplifyColorBase;
                        if (grade != null) writer.WriteLine("grade\t" + (grade.LutTexture == null ? "null" : grade.LutTexture.name) + "\t" + (grade.LutBlendTexture == null ? "null" : grade.LutBlendTexture.name) + "\t" + grade.BlendAmount.ToString("R") + "\t" + grade.Exposure.ToString("R") + "\t" + grade.Tonemapper);
                    }
                foreach (Behaviour effect in effects) effect.enabled = false;
                try {
                    foreach (float[] view in TourViews) {
                        main.transform.rotation = Quaternion.Euler(-view[1], view[0], 0f);
                        CaptureMain(main, name + "_y" + (int)view[0] + "_p" + (int)view[1] + "_nopost.png");
                    }
                } finally { foreach (Behaviour effect in effects) effect.enabled = true; }
            } finally {
                main.transform.position = position; main.transform.rotation = rotation; main.fieldOfView = fov;
            }
        }
        File.WriteAllText(output, "PASS: map tour completed");
        finished = true;
        Application.Quit();
    }
}
