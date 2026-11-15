# 大学城：低配机器只载入附近区块（2026-11-14）

目标（使用者 2026-11-14）：**10 个女角加场景，游戏进程最多用 16 GB 内存就能玩**。远处建筑缺失、pop-in、低 LOD 都可以接受；低配机器载不起来不行。

测试者机器：Lenovo Legion R9000K 2021H，Ryzen 9 5900HX，RTX 3080 Laptop 16 GB，64 GB RAM。

## 0. 最终结论（2026-11-15 05:00，stage lowmem1115c = master ce8b94e17）

低配目标（使用者 2026-11-15）是显存 ≤ 8 GB、内存 ≤ 12 GB，低配只载入 5 名女角。

结果（本机 128 GB／RTX 5090，`-LowMemory` 强制低配，5 名女角）：

| 情况 | commit | 工作集（实际占用的实体内存） | 显存 |
|---|---|---|---|
| 修改前（测试者的包，10 名女角，一次载入整座城） | 29.7–32.1 GB | | 10.7–13.3 GB |
| 待机 | 约 10 GB | 约 7 GB | 3.5–4.5 GB |
| 39 分钟长测（31 轮：瞬移到远处，再自动走向女角 45 秒） | 每轮最低 8.2–12.5 GB，峰值 **14.4 GB** | 峰值 **10.0 GB** | 峰值 **5.2 GB** |
| 10 名女角（参考） | 待机 13.5 GB，峰值 14.3 GB | 10.8 GB | 4.5 GB |

- **不会当机，内存也不会一路往上爬**：长测每圈 8 个地点，各圈每轮最低 commit 的平均依序是 10.16、10.53、10.64、10.08 GB，没有累积。第 32 轮时游戏被另一个 session 误杀（它用命令列比对 `nh1115` 找自己的进程，命中了这边的 `NH1115.patch`）。game.log 没有错误，`Crashes` 是空的。
- **显存 ≤ 8 GB：通过**，峰值 5.2 GB。
- **内存 ≤ 12 GB**：实际占用的实体内存（工作集）峰值 10.0 GB，**通过**。commit 待机约 10 GB，**通过**；但瞬移后会有短暂峰值 13–14.4 GB，**超过 12 GB**。commit 里约 4 GB 是驱动把显存映射进进程的部分（4.1），12 GB 的机器靠分页档可以容纳。正常走路是渐进载入，不会像瞬移那样整片格子同时载入。

第二次长测（nh1115h，含 R9-1、R9-2 与多入口，2026-11-15 04:41–05:25）完整跑完 35 分钟、32 轮，过程中没有当机。各圈每轮最低 commit 的平均依序是 10.38、10.31、10.59、10.70 GB。和第一次（10.16、10.53、10.64、10.08）放在一起看，是跑与跑之间的起伏，没有累积。峰值 commit 15.7 GB（载入与巡游时；长测中的峰值是 14.3 GB），工作集峰值 10.9 GB，显存峰值 5.4 GB。每 2 秒的取样在 `Saved/StreetSocial/MemProbe/soak2-5-low.csv`，这个档案是逐行写入的，就算游戏中途被关掉，已经取样的部分也会留下来。

整合后复测（stage lowmem1115e，master b8b92340a；内含整合进来的 E 组泪痕／一对一改动与 F 组 HairDeck；2026-11-15 12:50–13:05）：低配 5 女角，跑一次巡游再加 2 分钟 soak。
- 结果：峰值 commit 12.9 GB，工作集 9.1 GB，显存 4.7 GB；待机 commit 11.5 GB；每轮最低 commit 10.0 / 8.8 GB；没有当机。
- 对照整合前同一套流程：nh1115w 的峰值 commit 13.4 GB、显存 4.5 GB；第二次长测峰值 15.7 GB。
- 判断：整合没有让数字变差。commit 峰值仍超过 12 GB，原因还是上面说的瞬移后短暂峰值，这一点整合前就是这样。
- 结果档：`Saved/StreetSocial/MemProbe/int-5-low.json`、`int-5-low.csv`。

走路复测（玩家不会瞬移，走路才是无缝串流的真实情况；lowmem1115e，低配 5 女角，`street_city_memory_probe.lua --walk`，2026-11-15 13:20–13:50）。用自动导航走路，路线与巡游的 6 个点相同：百货 → 男生宿舍 → 溜冰场 → 体育馆 → 教堂 → 百货，5 段共约 2.4 km，全程不瞬移。
- 分两次跑：自动导航会把他带进体育馆里，进入设施后不能再用地图导航，所以第二次从体育馆门口出发（`--route gym,church,department`）。每次一段，都在 20 分钟内跑完。

| 路段 | 用时 | 走路中 commit 峰值 | 工作集峰值 | 显存峰值 |
|---|---|---|---|---|
| 百货 → 男生宿舍 | 123 s | 10.7 GB | | |
| 男生宿舍 → 溜冰场 | 161 s | 11.5 GB | | |
| 溜冰场 → 体育馆 | 186 s | 11.3 GB | | |
| （第一次 3 段合计） | | 11.5 GB | 8.0 GB | 4.4 GB |
| 体育馆 → 教堂 | 208 s | 10.0 GB | | |
| 教堂 → 百货 | 117 s | **12.4 GB** | 8.7 GB | 4.6 GB |

- 判断：
  - 显存 ≤ 8 GB、工作集 ≤ 12 GB：全程通过。
  - commit ≤ 12 GB：只有走到百货门口时超出 0.4 GB，其余 4 段都在 12 GB 内。
- 原因：超出的 0.4 GB 不是瞬间峰值。走近百货的最后 60 秒，commit 一路从 9.7 → 10.9 → 11.4 → 12.0 → 12.4 GB 慢慢上升，工作集与显存也跟着上升。这是百货与商店街一带的格子本身较密（巡游时停在百货也是 12.2–12.3 GB），不是新旧两批格子同时留在内存里。所以「切换时先放掉旧的再载新的」对这里帮不上忙；要降下来，得减少这一带常驻的内容。
- 结果档：`Saved/StreetSocial/MemProbe/walk-5-low.json`、`walk2-5-low.json` 与同名 `.csv`。

**低配载入半径 128 m → 96 m（2026-11-15 14:00–14:55）**：只在低配生效，一般模式不变；`-StreetCityLoadingRange=<cm>` 照样可以覆盖（`Source/OpenKoikatsu/OpenKoikatsu.cpp`）。这是低配要付的代价：看得到的范围小一点。没有动地图内容、贴图或减面。

| 教堂 → 百货（走路，停在百货） | stage | 走路中 commit 峰值 | 工作集 | 显存 |
|---|---|---|---|---|
| 128 m | nh1115y | 12.4 / 12.3 GB（两次） | 8.7 GB | 4.6 GB |
| 96 m（参数） | nh1115y | 11.0 / 10.9 GB（两次） | 7.9 GB | 4.1 GB |
| 96 m（新默认，不带参数） | lowmem1115f | **11.1 GB** | 7.8 GB | 4.1 GB |

- 走路量测跑在当时最新的 stage（c-conquest 的 nh1115y，同样是整合后的 master）。128 m 与 96 m 是在同一个 stage 上对比的。新默认值在 lowmem1115f 上确认过，game.log 写着 `Streamed map loading range 9600 cm`。
- 画面：走路途中每 30 秒截一张（镜头在身后朝前看），96 m 与 128 m 对照，加上到百货后环顾四个方向。近处街道、店面、树都完整，百货门口没有破洞，也没看到建筑突然冒出来。远处地平线本来就是空的（城市拿掉了远景，128 m 时也一样），96 m 只是空的边缘近一点。
  - 截图：`Saved/StreetSocial/Play-20261115T142100/control_shots/`（96 m，`walkcmp_*.jpg` 是左 96 m、右 128 m 的对照）、`Play-20261115T141638/control_shots/`（128 m）。
- **结论：低配走路全程达标**。commit ≤ 12 GB（百货一带 11.1 GB）、工作集 ≤ 12 GB、显存 ≤ 8 GB。瞬移后的短暂峰值是测试手段才会出现的，另外记录。
- 量测时注意：启动器默认挑最新的 stage，其他组随时可能建新的；对照组请用 `-Executable` 固定 stage。这次曾挑到别人还没建完的 nh1115z，游戏没写 log 就结束了（不是当机）。

**测试者的当机多半不是内存造成的**：测试者的机器是 64 GB 内存、16 GB 显存；照这里量到的数字，修改前整城一次载入也只有 30–32 GB commit、10.7–13.3 GB 显存，都放得下。所以内存不是已知的瓶颈，原因要看测试者的 `game.log` 与 `Saved/Crashes` 才能判断（§6）。为了让下一次当机看得出原因，做了以下几件事（646c07267）：
- game.log 一开始写一行 `OKMachine`：CPU、RAM、commit 上限、GPU 与驱动版本、显存与驱动给的预算、是否低配、stage、patch。
- 之后每 30 秒写一行 `OKMem`：本进程的 commit 与工作集、系统剩余 commit、本进程显存与驱动预算（DXGI `QueryVideoMemoryInfo`）、已载入的串流 level 数、已装好的女角数。`-OKMemLogSeconds=N` 可以改间隔，0 为关闭。
- 显存超过驱动预算，或系统剩余 commit 低于 2 GB 时，写一行 Warning。引擎配置内存失败时（out-of-memory 委派），会在死掉之前写一行 `Out of memory. OKMem: …`。每写一行就 flush，所以进程被系统或驱动直接杀掉时，已经写的内容不会丢。
- 启动器的黑色视窗一定会印出 `Memory: RAM … VRAM … -> …（判定来源）` 与 `Patch: …`；挑选最新 stage 时还会印 `Stage: …`。
- 打包版当机会不会留下 dump：用 nh1115h 执行 `debug crash` 实测过。`<stage>\Windows\OpenKoikatsu\Saved\Crashes\UECC-Windows-…\` 里有 `UEMinidump.dmp`（2.2 MB）、`game.log` 与 `CrashContext.runtime-xml`。stage 里没有 `CrashReportClient`，所以当机后视窗会卡住约 60 秒才自己关掉；dump 在当机的那一刻就已经写好了。

本机的样例：`OKMachine: CPU AMD Ryzen 9 9950X3D … RAM 125.6 GB, commit limit 185.6 GB, GPU NVIDIA GeForce RTX 5090 (driver 610.88, D3D12), VRAM 31.4 GB (budget 30.7 GB), low-memory on, stage lowmem1115d.stage, patch …NH1115.patch`；`OKMem: commit 12.75 GB (peak 12.83), working set 8.87 GB, system free commit 86.2 of 185.6 GB, VRAM 4.62 GB of budget 30.68 GB, streaming levels loaded 16, characters 6`（characters 含主角）。

做了哪些事：

| 项目 | commit／stage | 效果 |
|---|---|---|
| 启动器看 stage 自己的 cook 清单，改开串流地图 | 6c2fcfd8d | 不再一次载入整座城的源地图 |
| 城市不建远景（HLOD）、城市贴图压缩并串流、关 Nanite（c-street-city 的地图 + cook） | base BaseCity1115NH，f06a91068 | 10 名女角：32.1 → 18.9 GB，显存 13.3 → 5.5 GB |
| 低配模式：串流半径 128 m、角色贴图上限 512、上传后释放 CPU 副本、PNG 缓存 512 MB | f06a91068、6c45152b1 | 运行时贴图 1.87 → 0.63 GB |
| 夜间天光下限（环境光不能太暗） | 776611d3e | 夜里也看得到 |
| 低配只载入前 5 名女角（`-MaxHeroines N`） | 4bf6a91d4 | 5 名：11.3 GB／3.8 GB（不巡游） |
| 低配默认开 GPU rig（CrowdRoom100 的做法） | 006b7d92b | 10 名：峰值 18.9 → 15.2 GB |
| 女角装好后释放 Rust 解码缓存与 PNG 缓存 | 006b7d92b | 10 名：待机 14.2 → 13.5 GB |
| 启动器按 stage.json 挑最新 stage，并印出选中的 stage | fbbea3d69 | 避免玩到旧版 |

自动判断低配的条件：实体内存 < 48 GB 或显存 < 20 GB。测试者是 64 GB／16 GB 显卡，所以会自动进入低配。

还没做的两个选项（协调者 2026-11-15 决定先不做，等使用者觉得不够再说）：

| 选项 | 预估效益 | 风险 |
|---|---|---|
| 远处女角的贴图上限再降（512 → 256） | 每名约 30–50 MB 贴图，再加上同量的显存映射，5 名合计约 0.3–0.5 GB | 远处女角变糊；靠近时要重新上传 |
| 远处女角的减面预算再压低（现在身体 15k、衣服 15k、其他 30k，脸与头发不减） | 网格每名只有约 4 MB，5 名合计 < 50 MB | 省得很少，外观风险大，不建议 |

另外，Instant Meshes 低模（`-RuntimeLowPoly`）不做：街区女角本来就已经和百人房间一样执行时减面（4.5）。

§5、§7 是 11-14 当时的规划，(a)、(b) 都已照上表完成，保留作为记录。

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

### 4.1 第二轮拆分（2026-11-14 23:43 起，`-llm -llmcsv` 与 cdb `!address -summary`）

显存目标（使用者 23:5x）：**≤ 8 GB，要能在 RTX 4060 上跑**。

LLM（commit，最后一笔）：

| 类别 | 1 女角 | 10 女角 |
|---|---|---|
| 总计 | 21.4 GB | 31.6 GB |
| UE 未追踪 | 10.3 | 15.1 |
| Textures | 3.1 | 5.9 |
| NavigationCollision + Physics/ChaosTrimesh | 4.8 | 4.8 |
| Untagged | 0.4 | 2.2 |

- cdb（1 女角，23 GB commit）：Windows 堆只有 1.1 GB（Rust 的分配在这里），堆栈 1 GB，**PAGE_WRITECOMBINE 的已提交区段 10.7 GB**，约等于当时使用的显存（10.4 GB）。所谓「未追踪」主要是驱动把显存资源映射进进程的部分，不是 Rust。所以降低显存也会同等降低 commit。
- D3D12：`UAVBuffer StandAlone` 10.3 GB 里有 9.7 GB 是 Nanite 的保留地址（`Reserved Buffer Memory (Uncommitted)`），不占实际内存；实际 Buffers 5 GB（HLOD 合并网格约 3 GB）、Textures 2.6 GB。
- 贴图：`/Game/UniversityCity/ResortArchitectureV1` 有 **1,221 张未压缩、不串流的贴图，共 2.5 GB**，开图就全部常驻（素材设定：不压缩、NeverStream、没有 mip）。`Localization` 的 UI 贴图 180 MB 不串流，可以保留。
- 每多 1 位女角：commit +1.1 GB（其中约 0.3 GB 是显存的映射）、显存 +0.3 GB。

估算（做完 (a)：不建 HLOD + Resort 贴图改压缩与串流）：
- 显存：约 5 GB + 每位女角 0.3 GB，10 位时约 7.6 GB，刚好在 8 GB 内。
- commit：约 11 GB + 每位女角 1.1 GB，10 位时约 21 GB。所以 (b) 还要把每位女角的成本减半，才进得了 16 GB。

### 4.2 低配模式（f06a91068、6c45152b1），同一 base（BaseCity1113b，旧 WP），10 女角

`OKRuntimeLowMemory()`：实体内存 < 48 GB 或显存 < 20 GB 自动开（`-OKLowMemory`／`-OKNoLowMemory`）。开启时：
- 角色运行时贴图从 512 以内的 mip 开始，上传后释放 CPU 端数据（KKRuntimeMaterial 与 KKTextureRuntime 两条路径）；
- PNG 解码缓存 512 MB（否则是实体内存的 1/8，开发机 8 GB）；
- 串流地图载入半径 128 m，每个分区世界初始化时套用（读档重开地图也有效，game.log 有 `Streamed map loading range 12800 cm`）。

另外关闭 Nanite：`r.Nanite.ProjectEnabled=False`（下次 cook 生效），启动器对旧包加 `r.Nanite 0`。

| tag | stage | 低配 | 待机末 commit | 待机末显存 | 峰值 commit | 峰值显存 |
|---|---|---|---|---|---|---|
| lowmem-10-off | lowmem1114 | 关 | 29.5 GB | 12.1 GB | 30.3 GB | 12.1 GB |
| lowmem-10-on | lowmem1114 | 开（只有第一条贴图路径） | 27.4 GB | 11.1 GB | 28.7 GB | 11.8 GB |
| lowmem1115-10-on | lowmem1115 | 开（两条路径） | 27.2 GB | 10.9 GB | 29.0 GB | 11.8 GB |

运行时贴图（memreport）：1.87 GB（10 女角 + 男主，1024² 为主）→ 0.63 GB（512²）。剩下的大头是城市本身（旧 WP 的 HLOD、碰撞、未压缩贴图），要等 c-street-city 的新 cook（`City1115NoHLOD`：不建远景 + 贴图压缩 + 关 Nanite）。

### 4.3 新 stage：City1115NoHLOD（不建远景 + 城市贴图压缩 + 关 Nanite），patch NH1115（2026-11-15 00:49 起）

| tag | 女角 | 低配 | 峰值 commit | 稳定 commit | 巡游中 commit | 峰值工作集 | 峰值显存 | 载入格子 |
|---|---|---|---|---|---|---|---|---|
| nh-10-on | 10 | 开 | 18.9 GB（含 memreport 约 1 GB） | 15.4 GB | 16.1–18.0 GB | 12.5 GB | **5.5 GB** | 17 |
| nh-10-off | 10 | 关 | 25.6 GB | 23.2 GB | | | 8.3 GB | |
| nh-1-on | 1 | 开 | 8.5 GB | 8.3 GB | | | 3.1 GB | |

- 对照修改前（测试者包、旧 WP、10 女角）：峰值 commit 32.1 → 18.9 GB，显存 13.3 → 5.5 GB。
- 城市部分（memreport）：StaticMesh 1,946 → 589 个，碰撞（NavCollision + BodySetup）4.5 → 1.2 GB，贴图 2.7 → 1.2 GB。
- **显存 ≤ 8 GB：通过**（5.5 GB；本机 5090 上的数字，8 GB 显卡上引擎的贴图池会再缩）。
- **内存 16 GB**：实际占用的实体内存（工作集）峰值 12.5 GB，通过；commit 稳定 15.4 GB，瞬移巡游时 16–18 GB。commit 里约 4–5 GB 是驱动映射的显存（见 4.1），16 GB 内存的机器靠分页档可以容纳。若要连 commit 都压在 16 GB 内，下一步是女角数量少于 10 时的上限，或按距离卸载远处女角的贴图。
- **启动修正**：新 base 配旧共享 patch 一启动就当（`Missing global shader FVolumetricFogLightScatteringCS`）。已用当前树重建 `NH1115.patch`，`runtime.json` 改指它（015860b0f）。
- **画面**：远景拿掉、关 Nanite 后，近处建筑与地面正常。原本夜里天光只有白天的 10–20%，百货 1F 21:50 几乎全黑。依使用者要求（「环境光要维持在大家都看得到」）天光下限改为：夜里 35–45%、白天不低于 45%。00:32 的百货 1F 与 01:14 的户外截图都清楚可见。截图在 `Saved/StreetSocial/Play-20261115T004905/control_shots/`（改前）与 `Saved/StreetSocial/Play-20261115T010100/control_shots/`（改后）。

#### 关闭 Nanite 后的城市外观验收（2026-11-15 11:20–12:05，stage nh1115w = a88b81fbb +本机改动）

**结论：已目视验收，没有异常。** 没有看到破面、缺面、LOD 跳动或接缝，所以没有要列出的 actor 或 mesh。`r.Nanite.ProjectEnabled=False` 这个设置可以随版本发给玩家。

- **游戏里的实际设置**：用 `/exec` 读出的值是 `r.Nanite.ProjectEnabled = 0`（ProjectSetting）、`r.Nanite = 0`，确认是在 Nanite 关闭的状态下检查的。
- **第一轮（地面视角）**：18 处，每处 3 个朝向，白天 13:00、夜晚 22:00 各一次（时钟暂停）。
  - 18 处是：车站、公园、溜冰场、祭典、校门、校舍、屋顶、图书馆、百货 1F 室内、展望台室内、游乐园、船屋、钓鱼池、海滩、教堂、山丘、动物园、圣诞树。
  - 截图在 `Saved/StreetSocial/Play-20261115T112044/control_shots/`，`sheets/` 里是每处 2×2 的拼图。
  - 这一轮的第 4 张远景机位钻到地面以下（`/camera` 的 pitch 为负时机位在角色下方），不能用。
- **第二轮（俯瞰）**：12 处，每处 4 个方向，距离 25 m、俯角 30°，另加一张 60 m、俯角 60°；白天、夜晚各一次。截图不带 UI（`/screenshot {scale:1.5}`）。
  - 12 处是：车站、公园、祭典、校门、校舍、屋顶、游乐园、船屋、钓鱼池、海滩、教堂、动物园。
  - 截图在 `Saved/StreetSocial/Play-20261115T113954/control_shots/`，`sheets/` 里每处一张拼图。
- **看到的情况**：
  - 建筑外墙与屋顶、栏杆、路灯、树、摩天轮与云霄飞车轨道、教堂、海滩设施，近看和俯瞰都是完整的几何。
  - 远处建筑没有缺块，相邻网格之间没有缝。
  - 夜里路灯和店内灯光正常，环境光够亮。
- **和 Nanite 无关的现象**（不算异常）：
  - 车站和校舍的平屋顶是一整片亮白色，那是材质本身的颜色，几何是完整的。
  - 少数截图是相机贴近墙面或穿进男主身体，属于机位问题。
- **为什么风险本来就低**：城市模型的汇入脚本都设了 `build_nanite=False`（`Tools/street_city_unreal_import.py`、`street_city_resort_native.lua`、`street_city_activity_native_payload.lua`、`street_city_resort_architecture_payload.lua`）。也就是说，大部分模型本来就是一般网格，只有少数模型是靠 fallback 网格显示的。

### 4.4 低配目标：显存 ≤ 8 GB、内存 ≤ 12 GB，低配只载入 5 名女角（使用者 2026-11-15）

LLM（nh1115b，10 女角，低配）：commit 15.8 GB，组成如下。
- 未追踪 9.2 GB：约 4.5 GB 是驱动映射的显存，其余是 Rust、驱动与执行档。
- Untagged 2.0 GB（女角）。
- 贴图 1.2 GB。
- 碰撞 1.5 GB。

所以 10 位女角进不了 12 GB；使用者同意低配只载入 5 名。

启动器（`Tools/run_street_social_development.lua`）：
- 实体内存 < 48 GB 或显存 < 20 GB 时进入低配，或用 `-LowMemory` 强制、`-NoLowMemory` 关闭。显存从显卡驱动的登录项 `HardwareInformation.qwMemorySize` 读取。
- 低配时只取选卡清单前 5 名（`-MaxHeroines N` 可改），并传 `-OKLowMemory` 给游戏。
- 没载入的女角，关系资料仍留在存档里：存档按 id 保存，量测时 1 女角的 run 之后再开 10 女角，好感度都还在。

| tag | 女角 | 峰值 commit | 巡游中 commit | 峰值工作集 | 峰值显存 | 判定 |
|---|---|---|---|---|---|---|
| nh-5-low | 5 | **11.3 GB** | 10.4 GB | 8.5 GB | **3.8 GB** | 内存 ≤ 12 GB 通过、显存 ≤ 8 GB 通过 |
| nh-10-on（参考） | 10 | 18.9 GB | 16–18 GB | 12.5 GB | 5.5 GB | 内存不通过 |

### 4.5 每名女角为什么占这么多内存，以及 CrowdRoom100 的做法（2026-11-15 01:40 起）

使用者的问题：一名女角为什么占这么多内存，能不能减半；路上没有太多互动的人，不应该吃那么多内存。

拆分（nh1115b，低配）：
- 10 名比 5 名多 4.1 GB，每名约 0.82 GB；1 名到 5 名，每名约 0.44 GB。后几张卡的渲染骨多得多（selection-006、009 各约 4,400–4,700 根，selection-000 只有 1,187 根），所以每名的开销不一样。
- LLM：每多一名女角，约 0.65 GB 落在 Untracked（不经过 UE 的分配器），贴图约 64 MB，EngineMisc 约 58 MB，Graphics 约 155 MB。
- cdb `!heap -s`：1 名到 5 名时，进程预设堆（Rust 使用）从 880 MB 增加到 1,464 MB，每名约 146 MB。女角的 Rust 会话在准备完成后已经 `session_free`，但 bundle 解码缓存、基础库模型和运行时 PNG 缓存（低配上限 512 MB）一直没有释放。

照 CrowdRoom100 的做法改（006b7d92b，stage lowmem1115b）：
- 启动器在低配时默认 `-GpuRig`：姿势由 GPU rig 依共享 clip 计算，不再给每名女角各存一份解算好的姿势库。`-NoGpuRig` 可关回去；patch 里没有 rig shader 时，会退回原本的姿势库。
- `OKCrowdRuntimeScene`：低配模式下，全部女角装好、且没有准备工作在跑时，呼叫 `AKKPreviewActor::ReleaseSceneCaches`。之后要开卡（互动）时会重新解码，只是第一次比较慢。日志会印出 `Low-memory mode: source caches released after N heroines`（N 含主角）。

| tag | 女角 | 设定 | 闲置 commit | 峰值 commit（含巡游） | 峰值工作集 | 峰值显存 |
|---|---|---|---|---|---|---|
| rig-10-low（nh1115b，不巡游） | 10 | rig | 14.2 GB | 15.2 GB | 11.4 GB | 4.7 GB |
| rel-10-low | 10 | rig＋释放 | **13.5 GB** | 14.3 GB | 10.8 GB | 4.5 GB |
| rel-5-norig | 5 | 只有释放 | 10.8 GB | 13.7 GB | 9.7 GB | 4.8 GB |
| rel-5-low | 5 | rig＋释放 | 10.1 GB | 13.1 GB | 9.1 GB | 4.8 GB |
| rel-5-rig2（同上再跑一次） | 5 | rig＋释放 | 10.3 GB | **11.9 GB** | 8.4 GB | 4.3 GB |

- 10 名女角的峰值从 18.9 GB 降到 14.3 GB，闲置时从 15.4 GB 降到 13.5 GB。
- 5 名女角闲置约 10 GB。峰值出现在瞬移到体育馆、溜冰场之后，刚好在 12 GB 上下，两次分别是 13.1 和 11.9 GB。瞬移会让整片格子同时载入；实际走路是慢慢串流，不会这样。
- 显存在每种设定下都低于 5 GB。
- 结论：每名女角约减少 0.15–0.3 GB，**还没有减半**。剩下的大头，一是每名女角各自的网格和材质（不同卡的渲染骨与面数差很多），二是驱动映射的显存。

低模的情况（2026-11-15 核对）：
- 现在的 `CrowdRoom100.cmd` 已经不用 Instant Meshes 低模（`-RuntimeLowPoly`）。`Content/CharacterCards/CrowdAPNG` 一个 `.lowpoly.okmap` 都没有，`Docs/APNG_LOWPOLY.md` 写的是 10-10 当时的做法。
- 百人房间每一名都是在执行时由 `OKReduceRuntimeMeshesAsync` 减面（QEM）：身体合计 15,000 面，衣服 15,000 面，其他 30,000 面；脸和头发不减。
- 街区女角走的是同一个 `OKCrowdRuntimeScene`，`preserve_source_geometry` 没人打开，所以已经和百人房间一样减面了。
- 因此，CrowdRoom100 的做法里街区还没用上的只有 GPU rig，这次已经打开。要再省，就要再压减面预算，或是只给远处的女角更低的预算。

## 5. 给使用者的决定：要不要改远景

16 GB 判定：**不通过**（10 女角 32.1 GB；1 女角 21.1 GB）。分两块做：

| | 内容 | 谁做 | 需要 | 预期省下（依本次量测估算） |
|---|---|---|---|---|
| (a) 城市远景与贴图 | HLOD 去碰撞、去 Instanced 层、合并层简化或完全不要远景；`ResortArchitectureV1` 的 1,221 张贴图改为 BC 压缩、开串流、产生 mip；再 cook。使用者 23:4x 同意重建与 cook，先做「不建远景」 | c-street-city（地图）+ cook | 使用者同意改远景外观与 cook；约 90 GB、整台机器的 HLOD 重建（来源地图的 HLOD 现在是做到一半的版本） | 远景常驻网格 2.8 GB + 全城常驻原始网格约 2 GB（显存为主）+ 碰撞 4.5 GB（内存），合计约 7–9 GB |
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
> 2. `<包>\Saved\StreetSocial\Build\<名称>.stage\Windows\OpenKoikatsu\Saved\Crashes\` 整个资料夹（如果有的话；里面每次当机一个子资料夹，有 `.dmp`、`.runtime-xml` 和 log）。`<名称>` 是启动时黑色视窗里 `Stage:` 那一行写的名称；包里通常只有一个 `.stage`。
> 3. 黑色视窗（启动器）最上面几行的截图或复制文字：里面有 `Memory: RAM … VRAM … -> low-memory mode`（是否进入低配）与 `Stage:`。
> 4. `%LOCALAPPDATA%\CrashDumps\` 里名称含 `OpenKoikatsu` 的 `.dmp`（如果有）。
> 5. 显卡资讯：按 `Win + R` 输入 `dxdiag`，等它跑完按「储存所有资讯」，存成 `dxdiag.txt`。
>
> 当机时视窗可能会先卡住大约 1 分钟才关掉，这是正常的（当机记录已经写好了），请等它自己关掉，或用工作管理员结束。
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
