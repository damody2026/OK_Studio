# 大学城：低配机器只载入附近区块（2026-11-14）

目标（使用者 2026-11-14）：**10 个女角加场景，游戏进程最多用 16 GB 内存就能玩**。远处建筑缺失、pop-in、低 LOD 都可以接受；低配机器载不起来不行。

测试者机器：Lenovo Legion R9000K 2021H，Ryzen 9 5900HX，RTX 3080 Laptop 16 GB，64 GB RAM。

## 1. 测试者为什么载不起来

测试者执行的是 `E:\OKPackage\StreetSocial-20261114-hvoice\StreetSocial.cmd`（E 组打的包）。

- 旧启动器（`Tools/run_street_social_development.lua`）只在**项目** `Content/UniversityCity/Maps/UniversityCityWP.umap` 存在时才开串流版地图。
- `Content/UniversityCity/` 在 `.gitignore` 里，`Tools/package_street_social.lua` 也不复制它，所以任何包、任何新 clone 都落到整城源地图 `UniversityCity`。
- 包里的 stage（`Pack1114.stage`）其实两张都 cook 了（`Manifest_UFSFiles_Win64.txt` 有 `UniversityCity.umap` 和 `UniversityCityWP.umap`）。
- 源地图一次载入全部 28,600 个 actor：16,063 个 StaticMeshActor、5,565 个点光源、1,202 个聚光灯、1,162 个平面反射、4,343 个蓝图 actor（数字来自 cook 的 `StreamingGeneration` 日志，`Saved/Logs/WorldPartition/StreamingGeneration-Cook_UniversityCityWP-*.log`）。
- 串流版：128 m 一格，Level 0 共 84 格，载入半径 256 m（约 20 格），常驻只有 44 个 actor（天光、方向光、36 个合并 HLOD）。

修正（6c2fcfd8d）：启动器改看 **stage 自己的 cook 清单**；`-Editor` 才看项目 Content。没有串流版时印警告。`-CitySource` 仍可强制源地图（路网烘焙要用）。

其他崩溃来源（与地图无关，记录在此）：
- C 树共享 patch `StreetDisplay39Puddle.patch` 缺全局 shader `FOKClothCoverCS`，conq1114d 起的 C stage 正常启动会在着色器初始化时致命错误（`conq1114d.stage/.../Crashes/UECC-Windows-EE0DD5A9…`）。测试者的包用 `StreetDisplay40Cloth.patch`，没有这个问题。
- 19:37 那次崩溃是 `-Editor` 开 WP（进程 66 GB、系统剩 19 GB commit），不是打包版。

## 2. 游戏逻辑在只载入附近时是否仍成立

已检查，不需要改：
- 路网：串流地图时 `OKStreetCityCheckRoads` 读烘焙好的 `city_roads.json`，不在地图上做射线检查。
- 每块地图载入时才处理灯光、镜子、剔除距离（`OKStreetSocialScene.cpp`，按 level 处理）。
- 远处女角：落地高度 `OKStreetGroundZ` 在没有几何体时已有后备（2026-11-14 修正）。

## 3. 量测（`Tools/street_city_memory_probe.lua`）

工具：照 `StreetSocial.cmd` 的方式启动（`-Sandbox MemProbe -PortBase 48160 -NoCloud -Control -Window 1280x720`），每 2 秒记录游戏进程的 private commit、工作集、峰值、GPU 专用显存、系统可用 commit；载入后待机 60 秒，再依序瞬移到 department、boys_dorm、skating、gym、church、department，各停 25 秒；最后只结束自己启动的 PID。Unreal slot 名称 `c-lowspec`。输出 `Saved/StreetSocial/MemProbe/<tag>.csv` 与 `.json`。

测试者的 stage 不能被改动（启动器会在 stage 的 Content 建 junction），所以在 `Saved/StreetSocial/MemProbe/Pack1114.stage` 用 junction 镜像包的 Engine、Binaries、Plugins、Paks。这个目录有 junction，**不要递归删除**。

一次跑完的清单（全部 10 个女角、`-NoCloud`，启动器 6c2fcfd8d 以后）：

| tag | 参数 | 看什么 |
|---|---|---|
| pack-wp-10 | `-Executable <镜像 stage exe> -PatchDir <包的 StreetDisplay40Cloth.patch>` | 修正后测试者会得到的：串流 256 m |
| pack-source-10 | 同上加 `-CitySource`，`--no-tour --seconds 90` | 修正前测试者得到的：整城一次载入 |
| pack-wp-10-r128 | pack-wp-10 加 `--exec "wp.Runtime.OverrideRuntimeSpatialHashLoadingRange -grid=0 -range=12800"` | 半径减半后的 commit |
| pack-wp-10-r64 | 同上 `-range=6400` | 最小可玩半径 |

判定：
- **通过**：游戏进程峰值 private commit ≤ 16 GB（含载入与瞬移换区），GPU 专用显存 ≤ 8 GB（低配目标），全程没有崩溃。
- 半径要选最大的、仍满足 16 GB 的那档；若 256 m 已经满足，不改半径。

## 4. 结果

（量测排在 c-street-city 的 WP 重建之后，结果补在这里。）

## 5. 后续（依量测结果）

- 若串流版 256 m 超过 16 GB：在 C++ 于 `UWorldPartitionSubsystem::OnWorldPartitionSubsystemInitialized` 套用载入半径（`-StreetCityLoadingRange=N`，或依实体内存自动选），每次开图（含读档重开地图）都生效；控制台指令在地图重开时会被引擎清掉，不能只靠 `-ExecCmds`。
- E 组的包要用新启动器重新打包，测试者才会开串流版。
