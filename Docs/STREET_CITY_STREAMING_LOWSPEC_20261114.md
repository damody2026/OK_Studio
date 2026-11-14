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

2026-11-14 23:10–23:41，本机（128 GB、RTX 5090 32 GB），测试者的包 `Pack1114.stage` + `StreetDisplay40Cloth.patch`，`-NoCloud`。23:11 起机器上另有使用者自己的读卡程序（CardReaderDevelopment）在跑。原始数据：`Saved/StreetSocial/MemProbe/*.csv|json`，memreport 在 `Saved/StreetSocial/MemProbe/Pack1114.stage/Windows/OpenKoikatsu/Saved/Profiling/MemReports/`。

| tag | 地图 | 女角 | 其他 | 峰值 commit | 峰值显存 | 载入格子 |
|---|---|---|---|---|---|---|
| pack-source-10 | 源地图（修正前测试者打开的） | 10 | | 29.7 GB | 10.7 GB | 整张 |
| pack-wp-10 | WP | 10 | 窗口在载入完被使用者关掉，作废 | (22.6) | (8.8) | |
| pack-wp-10b | WP | 10 | 瞬移 6 处 | **32.1 GB** | **13.3 GB** | 61 |
| pack-wp-10-r128 | WP | 10 | 半径 128 m | 32.4 GB | 13.6 GB | |
| pack-wp-h1b | WP | 1 | | 21.1 GB | 10.4 GB | 65 |
| pack-wp-h1b-r64 | WP | 1 | 半径 64 m | 21.1 GB | 10.4 GB | 45（主网格只剩 4 格） |
| pack-wp-h1-hlod0 | WP | 1 | `wp.Runtime.HLOD 0` | 21.0 GB | 10.4 GB | 64 |

结论：
1. **改开串流地图不会降低内存**（32.1 vs 29.7 GB）。启动器修正仍要保留（之后的 WP 才能发挥作用），但它单独不能让低配机器跑起来。
2. 串流半径确实生效（64 m 时主网格只载 4 格），瞬移时格子也确实载入/卸载，可是内存不动。原因是这版 cook 的 WP：
   - 36 个合并 HLOD 网格（`StaticMesh_UniversityCityWP_HLODLayer_Merged_*`）存在 **地图包本身**（`/Game/UniversityCity/Maps/UniversityCityWP`），开图就整批载入：2.8 GB 网格，最大一个 585 MB（VB 189 MB）。
   - HLOD 远景格子（`HLOD0_256m_767m`，约 40 个）的 Instanced 层用原始网格做实例（3,756 个 `HLODInstancedStaticMeshComponent`），全城约 1,900 个网格资产（EnvironmentV1 1.0 GB、MotelRoomsV2、ShopSamplesV1…）因此常驻。
   - 这些网格都带碰撞：`NavCollision` 2.5 GB + `BodySetup` 2.0 GB（CPU）。
   - `wp.Runtime.HLOD 0` 只隐藏、不卸载（合并网格在地图包里）。
3. 女角：每多 1 位约 +1.2 GB commit、+0.3 GB 显存（10 位 32 GB vs 1 位 21 GB）。
4. 1 位女角时 UE 分配器（FMalloc）只占 7.9 GB，commit 却有 21 GB：其余约 13 GB 在 D3D12 与 Rust（ok_extract 会话、解码缓存）那边，这部分还没拆细。
5. 测试者为什么崩溃：本机量到的 30 GB commit 放得进 64 GB；显存 10.7–13.3 GB（本机贴图池按 32 GB 显卡的 70% 配）在 16 GB 笔电显卡上已接近满载。需要测试者那台机器的 `game.log` 和 `Saved/Crashes` 才能确定是显存、TDR 还是别的。

**16 GB 判定：目前不通过**（10 女角 32 GB；只有 1 位女角也要 21 GB）。不 cook 能调的东西（半径、HLOD 开关）量过都没有效果。

## 5. 给使用者的决定：要不要改远景

16 GB 判定：**不通过**（10 女角 32.1 GB；1 女角 21.1 GB）。分两块做：

| | 内容 | 谁做 | 需要 | 预期省下（依本次量测估算） |
|---|---|---|---|---|
| (a) 城市远景 | HLOD 去碰撞、去 Instanced 层、合并层简化或完全不要远景，再 cook | c-street-city（地图）+ cook | 使用者同意改远景外观与 cook；约 90 GB、整台机器的 HLOD 重建（来源地图的 HLOD 现在是做到一半的版本） | 远景常驻网格 2.8 GB + 全城常驻原始网格约 2 GB（显存为主）+ 碰撞 4.5 GB（内存），合计约 7–9 GB |
| (b) 女角与引擎 | 拆清 UE 分配器外的 13 GB；依实体内存限制姿势缓冲、贴图缓存、串流池；固定载入半径 | c-lowspec（我） | Source 改动、skip-cook 建置，不用 cook | 目标每位女角从 1.2 GB 降到 0.5 GB 以下（约 6 GB），外加缓存上限 |

要点：
- 只做 (b) 到不了 16 GB：城市本身（1 位女角时）就超过 16 GB。
- 只做 (a) 也到不了：10 位女角 32 GB 扣 7–9 GB 仍有 23 GB 以上。
- 两者都做，预估 10 女角落在 16–18 GB，还要看 (b) 实际拆出来的结果。
- (a) 的外观取舍：
  - 「不要远景」：大约 250 m 外的建筑完全消失，画面只剩附近的街区，走动时远处建筑会冒出来。
  - 「简化远景」：远处只剩方块状的低模建筑轮廓。
  - 两种都没有碰撞，远景本来就走不到，不影响游戏。

## 6. 请测试者回传的文件（可直接转给测试者）

> 请把下面这些文件压成一个 zip 传回来（`<包>` 是你解压 StreetSocial 的资料夹，也就是 `StreetSocial.cmd` 所在的资料夹）：
>
> 1. `<包>\Saved\StreetSocial\` 里**最新**的 `Play-日期时间` 资料夹中的 `game.log`（每次启动会新建一个，依资料夹名称的时间挑当机那一次）。
> 2. `<包>\Saved\StreetSocial\Build\Pack1114.stage\Windows\OpenKoikatsu\Saved\Crashes\` 整个资料夹（如果有的话；里面每次当机一个子资料夹，有 `.dmp`、`.runtime-xml` 和 log）。
> 3. `%LOCALAPPDATA%\CrashDumps\` 里名称含 `OpenKoikatsu` 的 `.dmp`（如果有）。
> 4. 显卡资讯：按 `Win + R` 输入 `dxdiag`，等它跑完按「储存所有资讯」，存成 `dxdiag.txt`。
>
> 打包方式：把上面的文件放进同一个资料夹，按右键 →「压缩成 ZIP 档」。不要放 `Saved\StreetSocial\player.json` 或 `Sandbox`（里面可能有你的金钥），也不要放角色卡。

## 7. 要达到 16 GB 必须做的事

城市（需要 WP 重建 HLOD + cook，c-street-city 的地图）：
1. HLOD 层不要碰撞、不要 NavCollision：合并层与实例层都设 `bNoCollision`／HLOD 网格关碰撞（省约 4.5 GB CPU 的大部分）。
2. 去掉 Instanced HLOD 层，或只用于小物件；远景只保留合并层（Instanced 层让全城原始网格常驻）。
3. 合并层简化：开 mesh simplification（`MeshSimplify`／`ApproximateMesh`）并降低合并贴图尺寸，目标总量 < 300 MB；或直接不建远景（使用者已接受远景缺失），WP 只留主网格。
4. 项目没有用导航网格：关掉静态网格的 NavCollision 生成（cook 设置），全城一起省。
5. 改完后先 HLOD 分批重建（约 90 GB，需整台机器）再 cook（使用者许可后）。

女角与引擎（不需要 cook，Source 改动）：
6. 拆清楚 1 位女角时 D3D12 + Rust 的 13 GB（下一轮量测：Rust 侧用 ok_extract 的内存统计，D3D12 侧看 `D3D12 Memory` 统计组）。
7. 依实体内存设预算：贴图缓存（`KKTextureRuntime` 的 PNG 缓存已是 RAM/8）、姿势缓冲 `StagedPose.Keys`（10 位 872 MB 显存）、Nanite 串流池（528 MB）、贴图串流池。
8. 半径：在 C++ 于 `UWorldPartitionSubsystem::OnWorldPartitionSubsystemInitialized` 套用（`-StreetCityLoadingRange=N`），每次开图都生效；控制台指令在地图重开时会被引擎清掉。等第 1–3 项做完才看得出效果。

分发：E 组的包要用新启动器（6c2fcfd8d）重新打包。
