# OK Studio 开场景的速度（2026-11-17，F 组）

从选档到场景在 OK Studio 里建完、可以操作为止。量的是 `UOKStudioGame::Load`（解析场景档＋释放上一个场景，一次阻塞呼叫）加上之后每一帧的渐进建构，直到没有物件或地图还在等下一帧（`AOKSceneActor::HasPendingBuilds()` 为假且 `PreparingMap() < 0`）。

## 怎么量

新增主控台命令 `OKStudio.ProfileSceneLoad [repeats] [exit]`（[`Plugins/OKStudio/Source/OKStudio/Private/OKStudioLoadProfile.cpp`](../Plugins/OKStudio/Source/OKStudio/Private/OKStudioLoadProfile.cpp)）：

| 环境变数 | 作用 |
|---|---|
| `OK_SCENE_PROFILE_LIST` | 场景清单档（一行一个路径，`#` 开头是注解）。`.okscene`、OK 场景卡、原作 KStudio 场景 PNG 都可以 |
| `OK_SCENE_PROFILE_TAG` | 输出名，结果写到 `Saved/Reports/scene-load/<tag>.json` |
| `OK_SCENE_PROFILE_DUMP=1` | 每趟另外写一份场景内容：物件清单、世界座标、每个 preview 的 parts 与元件数、错误。两次跑的结果拿来逐物件比对 |
| `OK_SCENE_PROFILE_SHOT=1` | 场景建完、**而且 shader 编译完**之后拍一张（`OK_SCENE_PROFILE_SHOT_FRAMES`，预设等 240 帧） |

每一列记 `ready_ms`（总时间）、`load_call_ms`、`build_ms`、`build_frames`、`peak_used_gb`，以及 `AOKSceneActor::LoadStats` 的分段：角色 session 在 worker 上开了多久、在 game thread 上 `ContinueSessionLoad` 多久、道具 `Build()` 里各段（型号查表／Rust 开启／Unreal spawn／prefab 根节点／render camera）、地图在 game thread 上的切片、`Sync()` 总时间、空转的 Sync 次数。

跑法（引擎 `F:\UE5.8`，只开自己的实例）：

```bash
OK_SCENE_PROFILE_LIST=F:/OpenKoikatsu/Saved/Reports/scene-load-f/list-b.txt OK_SCENE_PROFILE_TAG=base OK_STUDIO_PORT=48180 "F:/UE5.8/Engine/Binaries/Win64/UnrealEditor.exe" F:/OpenKoikatsu/OpenKoikatsu.uproject "/Engine/Maps/Entry?game=/Script/OKStudio.OKStudioGameMode" -game -windowed -NoSplash -nop4 -NoCloud -abslog=F:/OpenKoikatsu/Saved/Logs/SceneLoadProfile/base.log "-ExecCmds=OKStudio.ProfileSceneLoad 3 exit"
```

样本（都从原作 KStudio 场景重新汇入，所以卡片是现在的 ok-extract 转出来的；清单在 `Saved/Reports/scene-load-f/`）：

| 样本 | 内容 |
|---|---|
| `2021_1022_2145_32_381_2.okscene` | 0 角色、48 道具、无地图 |
| `ill_ss_sample_02_2.okscene` | 1 角色、3 道具、地图 73 |
| `ill_ss_sample_03_2.okscene` | 5 角色、4 道具、地图 70 |
| `koikatu_cs0001521_2.okscene` | 21 角色、634 道具、地图 20（856 个物件） |
| `koikatu_cs0003420_2.okscene` | 1 角色、5867 道具（8806 个物件），压力用 |
| `ill_ss_sample_03.png` | 原作 KStudio 场景 PNG，同一个 5 角色场景，走汇入路径 |

**只看冷载入**（2026-11-17 使用者的决定：开卡快取永远不开，一律优化冷读取）。冷 = 全新行程、`OK_NOCACHE=1`、不设 `OK_LIBRARY_CACHE`，而且**这个场景是该行程开的第一个场景**（所以每个场景、每个设定各起一个行程，一趟）。下面的「冷开」那一栏就是这个。

同一个行程里再开一次的时间（热开）也记在表里，但只当参考：`ok-extract` 的行程内 memo 与 Unreal 的资产快取会让第二趟快不少，那不是使用者实际的情况。

两个设定一律在同一段时间内背靠背跑，因为这台机器同时有别的 session 在跑 Unreal，跨时段的数字会差到 15%。

## 基准落在哪里

21 角色／634 道具那个场景，热开 38.6 s，其中：

| 分段 | 毫秒 | 在哪条线上 |
|---|---:|---|
| 道具 `OpenOkModelFk` | 13 513 | game thread |
| 道具 Unreal spawn | 13 189 | game thread（必须） |
| 角色 session 开启 | 11 970 | 一个 worker，**一次只开一个** |
| 角色 `ContinueSessionLoad` | 4 762 | game thread，每帧 30 ms |
| 地图 | 3 559 | game thread，每帧 30 ms |
| 解析场景档＋释放上一个场景 | 857 | 一次阻塞 |
| `Sync()` 以外（算绘、引擎 tick、GC） | 12 957 | 229 帧 × 约 56 ms |

5867 道具那个场景更极端：热开 180 s，道具 `OpenOkModelFk` 68 s、spawn 20 s，而且要 567 帧（每帧只建 24 个物件）。

## 改了四件事

都在场景层（`AOKSceneActor`），没有动 `Tools/ok-extract` 与单卡开卡的共用路径。

1. **道具 session 在 worker 上并行开启**（`ok.Studio.ItemOpensAhead`，预设 8）。以前每个道具在建它的那一帧里自己呼叫 `OpenOkModelFk`；现在 `PrepareItem` 先在 worker 上开，帧里只做 Unreal 这一段。同时在开的数量与「开好但还没建」的数量都有上限（后者是 `Ahead * 3`），否则几千个道具的场景会一次握着几千个 session。
2. **角色 session 同时开好几个**（`ok.Studio.CharacterOpensAhead`，预设 3）。以前是「一次只开一个 worker」。
3. **开场景时每帧的 session 切片 30 ms → 120 ms**（`ok.Studio.OpenSliceMs`）。一帧本身就要 20 ms 以上（算绘与引擎 tick），切成 30 ms 等于大半时间花在帧开销上；250 ms 再长就没有好处了。
4. **每帧建的物件 24 → 96，另加 250 ms 上限**（`ok.Studio.BuildsPerFrame`／`ok.Studio.BuildSliceMs`）。道具的 session 已经先开好了，一个道具只剩几毫秒，24 个一帧让几千道具的场景卡在帧数上。`Sync()` 每帧会走过全部物件，帧数少一半，这个 O(物件 × 帧) 的成本也少一半。

把四个旋钮设回旧值（`ItemOpensAhead 0`、`CharacterOpensAhead 1`、`OpenSliceMs 30`、`BuildsPerFrame 24`）就是改之前的行为，上面的比较都是这样做的。

## 结果

**冷载入**（毫秒，`OK_NOCACHE=1`，每个场景每个设定各一个全新行程，场景是该行程的第一个）：

| 场景 | 旧 → 新 | |
|---|---:|---|
| 0 角色 / 48 道具 | 4 247 → **3 636** | −14% |
| 1 角色 / 地图 73 | 7 553 → **6 939** | −8% |
| 5 角色 / 地图 70 | 12 286 → **9 409** | −23% |
| 21 角色 / 634 道具 / 地图 20 | 46 709 → **30 736** | −34% |
| 原作 KStudio PNG（5 角色） | 24 882 → **23 105** | −7% |

峰值记忆体没有变差：21 角色场景 16.2 → 16.3 GB。

参考用的热开数字（同一行程第二、三趟，档案快取与 sqlite 都暖）：

| 场景 | 冷开（暖快取、行程第一趟） | 热开（同行程再开） |
|---|---|---|
| 0 角色 / 48 道具 | 4 245 → 3 306 | 1 489 → 926 |
| 1 角色 / 地图 73 | 7 421 → 6 880 | 3 869 → 3 114 |
| 5 角色 / 地图 70 | 11 660 → 8 520 | 8 045 → 5 939 |
| 21 角色 / 634 道具 / 地图 20 | 42 194 → 28 179 | 38 594 → 25 624 |
| 1 角色 / 5867 道具 | 209 601 → 86 315 | 180 387 → 84 956 |
| 原作 KStudio PNG（5 角色） | 25 184 → 22 689 | 18 304 → 16 640 |

### 冷载入时，角色那一段花在哪

5 角色场景，`OK_PROFILE=1 OK_NOCACHE=1`，五个角色加起来（它们是并行开的，所以总和大于墙钟时间）：

| 阶段 | 五个角色合计 | 每个角色 |
|---|---:|---:|
| `extract_session TOTAL` | 8 123 ms | 1 625 ms |
| `clothes+hair+write` | 4 315 ms | 863 ms |
| `lists+mods+guids` | 2 651 ms | 530 ms |
| `okmodel parts`（道具／地图共用） | 2 242 ms | — |
| `load_base_bundles` | 959 ms | 192 ms |

`lists+mods+guids` 占角色开启的三分之一。这些场景的角色是 OK 卡（资源来自卡内资源包与基础库），所以没有 E 组在原作卡上量到的 1.5–3.4 s 那么夸张，但在多角色场景里一样会乘上角色数——这一段在 `Tools/ok-extract` 的共用路径上，由 `e-cardload` 处理。

单项的贡献（21 角色场景，热开）：道具改并行开启 42.3 → 36.3 s；角色 3 个一起开 39.4 → 37.5 s；切片 120 ms 在地图重的 5 角色场景是 7.2 → 5.9 s；每帧 96 个物件在 5867 道具场景是 110 → 85 s。

## 正确性

- `cargo test --release -j 8 --manifest-path Tools/ok-extract/Cargo.toml --lib`：507 过、3 失败。三个失败都是 `appearance` 里写死 `C:/portable/OpenKoikatsu/Content/CharacterCards/StreetHeroines` 的测试，该目录现在多了一个 `KKS/` 子目录，`gamefs::read` 读到目录回传 `PermissionDenied`。与这次改动无关（这次一行 Rust 都没动），但 C 组值得修一下那三个测试的档案过滤。
- 物件比对（`OK_SCENE_PROFILE_DUMP`）：六个样本、每个 2–3 趟，新旧设定的物件数、kind、名称、世界座标、preview 的 parts 与可见／隐藏元件数、地图 parts 数、错误全部相同。唯一的差异是 21 角色场景里 5 个挂在角色骨头上的道具的座标，而**同一组设定的不同 trip 之间也是这 5 个会差**（`[3, 276, 280, 292, 577]`，动画相位决定），不是回退。
- 目视（`OK_SCENE_PROFILE_SHOT`）：新旧设定的画面逐像素平均差，0 角色场景 0.146/255（同设定重跑的杂讯是 0.14），两个有角色的场景分别是 16.3 与 2.3，而同设定重跑本来就是 16.4 与 2.6 —— 都落在动画造成的杂讯里。

## 还剩下什么

1. **原作 KStudio PNG 的汇入**：5 角色的场景里，`load_call_ms` 是 11.3 s（总共 16.6 s）。那是 `FOKStudioImport::Import` 对每个角色依序呼叫 `FOkSession::MakeOkCardForOutfit` 把原作卡转成 OK 卡，而且**每次开同一个场景 PNG 都重转一次**。
   - 试过先走一遍 JSON 收集角色、用 `ParallelFor` 一次转 4 张再建文件：**没有变快**（5 张卡依序 11.0 s，4 个并行 11.7 s），所以回退了，没有留在版控里。`MakeOkCardForOutfit` 在 Rust 那边看来被某个全域锁序列化了，这段要从单卡转换那边查起。
   - 另一条路是快取：OK 卡已经存在、而且比原作卡与 ok-extract 的建置都新的时候就不重转。要先想好版本戳记，否则 2026-10-28 以前那种缺 okLt 的旧卡会被重复使用。
2. **道具的 Unreal spawn**：21 角色场景里 10.5 s，必须在 game thread。但那 634 个道具只有 67 种型号 —— 同型号共用 mesh／material 是下一个大块，不过那要动 `Plugins/KKUnityBundle` 的共用程式码（C／E／F 三组共用），动之前要先讲好。
3. **`Sync()` 每帧走过全部物件**：5867 道具场景里，`Sync` 总共 62 s，其中只有 23 s 是 `Build()`；其余约 39 s 是 8806 个物件 × 291 次 Sync 的回圈本身（世界变换、可见性、材质覆写比对）。只对「这一帧真的会变」的物件做事，是最后一块。
4. `ready_ms` 是「物件都建完」，不是「材质都编译完」。拍照比对一定要等 shader 编译结束，否则比到的是编译进度（见 `Docs/ERROR_LOG.md` 的记录）。
