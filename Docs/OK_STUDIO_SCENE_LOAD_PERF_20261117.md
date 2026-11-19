# OK Studio 开场景的速度（2026-11-17，F 组）

**一句话**：场景里本来就会做的事没变，只是把该在 worker 上做的搬到 worker、把切得太碎的每帧预算放大。21 角色 634 道具的场景冷载入 44.7 s → 24.7 s（−45%），0 角色 48 道具的轻场景 6.2 s → 3.2 s（−49%），物件内容一模一样。

**做了五件事**（都在 `AOKSceneActor`，`Tools/ok-extract` 一行没动）：

| 改动 | cvar | 旧值 |
|---|---|---|
| 道具 session 预先在 worker 上并行开启 | `ok.Studio.ItemOpensAhead` = 8 | 0（在建它的那一帧里开） |
| 道具的 `PrepareRuntimeMaterials` 也搬到那个 worker | 同上 | 在 game thread 上（最大的一块，7.8 s） |
| 角色 session 最多 3 个并行开启 | `ok.Studio.CharacterOpensAhead` = 3 | 1 |
| 开场景时每帧的 session 切片放大 | `ok.Studio.OpenSliceMs` = 120 | 30 |
| 每帧建的物件放大，另加时间上限 | `ok.Studio.BuildsPerFrame` = 96 / `BuildSliceMs` = 250 | 24 / 无 |

**试过之后回退的两件**（都在「还剩下什么」与下面各节里留了数字）：同型号道具共用 mesh／material（既有的 `OKFindEqualMaterial` 早就在去重，634 个道具只建了 49 个材质、23 张贴图）、共用角色显示 ramp 贴图（实测 `ramp_ms = 0`，Studio 道具走不到那条路）。KStudio PNG 导入时并行转原作卡也试过，没有变快，同样回退。

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
   **worker 上同时也做 `PrepareRuntimeMaterials`**，和角色的开启一样。这是道具最大的一块：见下面「道具在 UE 端花在哪」。
2. **角色 session 同时开好几个**（`ok.Studio.CharacterOpensAhead`，预设 3）。以前是「一次只开一个 worker」。
3. **开场景时每帧的 session 切片 30 ms → 120 ms**（`ok.Studio.OpenSliceMs`）。一帧本身就要 20 ms 以上（算绘与引擎 tick），切成 30 ms 等于大半时间花在帧开销上；250 ms 再长就没有好处了。
4. **每帧建的物件 24 → 96，另加 250 ms 上限**（`ok.Studio.BuildsPerFrame`／`ok.Studio.BuildSliceMs`）。道具的 session 已经先开好了，一个道具只剩几毫秒，24 个一帧让几千道具的场景卡在帧数上。`Sync()` 每帧会走过全部物件，帧数少一半，这个 O(物件 × 帧) 的成本也少一半。

把四个旋钮设回旧值（`ItemOpensAhead 0`、`CharacterOpensAhead 1`、`OpenSliceMs 30`、`BuildsPerFrame 24`）就是改之前的行为，上面的比较都是这样做的。

## 结果

**冷载入**（毫秒，`OK_NOCACHE=1`，每个场景每个设定各一个全新行程，场景是该行程的第一个）。下表量在 **`14616cb41`**（收了 E 组开卡改动：原作卡 mods 树、材质 parent 预载、基础 bundle 预热）之上，四个旋钮全旧对全新，同一段时间背靠背：

| 场景 | 旧 → 新 | |
|---|---:|---|
| 0 角色 / 48 道具 | 6 157 → **3 161** | −49% |
| 1 角色 / 地图 73 | 9 808 → **7 531** | −23% |
| 5 角色 / 地图 70 | 12 221 → **9 378** | −23% |
| 21 角色 / 634 道具 / 地图 20 | 44 701 → **24 728** | −45% |
| 原作 KStudio PNG（5 角色） | 24 377 → **22 654** | −7% |

原作 KStudio PNG 那一列只有 −7%，因为它的时间有 62% 不在场景建构里：`load_call_ms` 是 13 981 ms（旧设定）／14 320 ms（新设定），那是 `FOKStudioImport::Import` 把五张原作卡转成 OK 卡的一次阻塞呼叫，本轮的改动完全碰不到它。

**E 组的 `ac498d042`（每张新卡少重扫一次整棵 mods 树）对这条路没有效果**：合并前同一个样本的 `load_call_ms` 是 14 182／14 595 ms，合并后 13 981／14 320 ms，落在趟与趟之间的波动里。所以这 14 秒不是 mods 树重扫，要另外量（并行转卡也没有变快，见「还剩下什么」第 1 点）。这个样本证明的是**原作卡那条路在场景载入里还没被改善**，不是相反。

峰值记忆体（21 角色场景，这个行程的 working set）：全旧 16.1 GB、全新 16.5 GB。

> `14616cb41` 之前量的同一组是 4 247 → 3 636、7 553 → 6 939、12 286 → 9 409、42 352 → 28 534、24 882 → 23 105。换基点之后两边都变了（E 组的预载改变了第一个场景的成本分布），所以不要拿两组数字交叉比较。

### `ItemOpensAhead` 调小值不值得（16 GB 机器）

同一个 21 角色 634 道具场景，冷载入，只改这一个旋钮：

| `ok.Studio.ItemOpensAhead` | ready | 峰值记忆体 |
|---|---:|---:|
| 8（预设） | 27 403 ms | 16.5 GB |
| 4 | 40 726 ms | 16.4 GB |
| 0（旧行为，道具在帧里自己开） | — | 16.1 GB |

**调小不划算**：4 比 8 慢了三分之一（worker 上的开启吞吐减半：每个道具的 session 约 98 ms，4 个并行是 41 个／秒、8 个是 82 个／秒），记忆体只省 0.1 GB。`ok.Studio.CharacterOpensAhead` 从 3 调到 1 也一样（30 274 ms、16.4 GB）。真正占住 16 GB 的是场景本身（全旧设定也要 16.1 GB），不是这两个管线。所以这两个旋钮是「机器真的爆了才动」的出口，不是 16 GB 机器该预设调低的值。

参考用的热开数字（同一行程第二、三趟，档案快取与 sqlite 都暖）：

| 场景 | 冷开（暖快取、行程第一趟） | 热开（同行程再开） |
|---|---|---|
| 0 角色 / 48 道具 | 4 245 → 3 306 | 1 489 → 926 |
| 1 角色 / 地图 73 | 7 421 → 6 880 | 3 869 → 3 114 |
| 5 角色 / 地图 70 | 11 660 → 8 520 | 8 045 → 5 939 |
| 21 角色 / 634 道具 / 地图 20 | 42 194 → 28 179 | 38 594 → 25 624 |
| 1 角色 / 5867 道具 | 209 601 → 86 315 | 180 387 → 84 956 |
| 原作 KStudio PNG（5 角色） | 25 184 → 22 689 | 18 304 → 16 640 |

### 道具在 UE 端花在哪（21 角色场景，634 个道具，`OK_LOAD_PROFILE=1`）

一开始以为重复的是 mesh 与材质（634 个道具只有 67 种型号），量完发现不是：整场只建了 23 张贴图、49 个材质，`OKFindEqualMaterial` 的去重早就在做了。实际分布是：

| 分段 | 改之前 | 改之后 |
|---|---:|---:|
| UE 端合计 | 10 136 ms | 4 594 ms |
| 其中 `OKPrepareCookedRole` | 7 770 ms | 840 ms |
| ├ 它的贴图 | 116 ms | 172 ms |
| ├ 它载入的 shared parent | 26 ms | 41 ms |
| └ 它建的 part 实例（MID） | 339 ms | 372 ms |
| 建 parts | 2 222 ms | 2 133 ms |
| 显示 ramp 贴图 | 0 ms | 0 ms |

`OKPrepareCookedRole` 的 7.8 s 里，它自己的三个子计时只占 0.5 s；剩下的全在它 `Setup()` 的第一行 `To.Source.PrepareRuntimeMaterials(Error)` ——**角色的开启早就把这一步放到 worker 上了**（`StartCharacterOpen` 的注解：「on the game thread this was the 1 to 6 s frame left」），道具没有。把它搬进 `PrepareItem` 的 worker 之后，道具在 game thread 上从 22.4 s（全旧）降到 4.6 s。

> 回退的一项：原本怀疑每个 preview 各建一张显示 ramp 贴图（`OKCharacterDisplayRampPath` → `TextureFromPngBytes`），做了全行程共用。实测 `ramp_ms` 是 0——Studio 的道具根本没走到那条路（`ToonRampTex` 已由场景的 RampG 给定），整场只建一次。共用 ramp 的行为已拿掉，只留下把 ramp 与 `cooked_role` 纳入 `OK_LOAD_PROFILE` 的计时，`KKUnityBundle` 因此没有行为变更。

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
   - E 组的 `ac498d042`（每张新卡少重扫一次整棵 mods 树）合进来之后这一段**没有变**：`load_call_ms` 在 `14616cb41` 上是 13 981 ms（旧设定）／14 320 ms（新设定），跟合并前的 14 182／14 595 一样。所以这 14 秒不是 mods 树扫描，得另外量。
   - 另一条路是快取：OK 卡已经存在、而且比原作卡与 ok-extract 的建置都新的时候就不重转。要先想好版本戳记，否则 2026-10-28 以前那种缺 okLt 的旧卡会被重复使用。
2. **道具的 Unreal spawn**：搬走 `PrepareRuntimeMaterials` 之后剩 4.6 s，其中 2.1 s 是建 parts、0.84 s 是 `OKPrepareCookedRole` 剩下的部分（建每个实例自己的 MID，不能共用：颜色与 Material Editor 覆写是逐实例写进去的）。要再往下砍得共用同型号的 static mesh，那要动 `Plugins/KKUnityBundle`（三组共用）。
3. **`Sync()` 每帧走过全部物件**：5867 道具场景里，`Sync` 总共 62 s，其中只有 23 s 是 `Build()`；其余约 39 s 是 8806 个物件 × 291 次 Sync 的回圈本身（世界变换、可见性、材质覆写比对）。只对「这一帧真的会变」的物件做事，是最后一块。
4. `ready_ms` 是「物件都建完」，不是「材质都编译完」。拍照比对一定要等 shader 编译结束，否则比到的是编译进度（见 `Docs/ERROR_LOG.md` 的记录）。

## 2026-11-18：`Sync()` 开 id 索引——Sync 自己快了 16 s，**整体反而慢 24.7%**

`AOKSceneActor::Tick` 在 2437 行先调 `Sync()`，才在下一行建 `FFindScope`，所以 `Sync` 整段跑在 scope 之外，
里头每个 `WorldTransform`／`IsShown` 沿父链的查找都是 `Objects` 的线性扫描（物件上千就是平方级）。
改成在 `Sync()` 顶端自己开 scope，开关 `ok.Studio.SyncFindIndex`（预设 1，0 回到扫描）。

**A/B**（`koikatu_cs0003420_2.okscene`：1 角色、5867 道具、2938 其他，共 8806 物件；冷开＝全新行程第一个场景、
`OK_NOCACHE=1`、`RAYON_NUM_THREADS=8`、编辑器 `-game`、`OKStudio.ProfileSceneLoad 1 exit`、F 树 `7e003b86f` ＋
未提交的计数器，**各一趟**）：

| | 索引关 | 索引开 | |
|---|---:|---:|---|
| `ready_ms` | 111 924 | 139 555 | **+24.7%** |
| `sync_world_ms`（`WorldTransform`＋`IsShown`） | 24 518 | **1 197** | −95.1% |
| `sync_ms`（Sync 全部） | 79 160 | 63 008 | −20.4% |
| `build_frames`／`syncs` | 418／419 | 919／920 | **+120%** |
| `starved_syncs` | 99 | 238 | |
| `sync_same_ms` | 788 | 1 460 | |
| `sync_place_ms` | 3 008 | 5 047 | |
| `item_open_worker_ms`（8 条 worker 合计） | 419 325 | 453 042 | +8% |
| `find_index_builds` | 449 | 1 870 | 每次 Sync 1.07 vs 2.03 次 |

**索引本身做到了它该做的事**：那 23–24 s 的父链查找是真的，也真的消掉了（−95.1%），Sync 自己少了 16.2 s；
`find_index_builds / syncs` 关是 1.07、开是 2.03（Sync 自己一次 ＋ Tick 原本那次），没有「成本从扫描搬去重建」。

**但整体变慢，机制是帧数**：每帧 Sync 以外的固定成本两边都约 80 ms（关 75.3、开 81.8，主要是把半成品场景画一遍），
而 `Sync` 变便宜之后每帧只建 6.4 个道具（关是 14.0 个），帧数就从 418 翻到 919；919 × 80 ms 把省下的 16 s
吃掉还倒赔 27.5 s。为什么每帧建得更少：`OKSceneActor.cpp:1474` 的 `bItemWaiting = ... && !PrepareItem(Object)`
——**道具是在它的 worker session 准备好的那一帧才建**，所以每帧建几个只取决于「这一帧有多长」× worker 的产出速率。
帧变短 → 每帧等到的更少 → 帧更多 → 画得更多次 → 还跟 worker 抢 CPU（worker 合计时间 +8%，产出速率从 53/s 掉到 42/s）。

也就是说**这段载入是 worker 产出在计价，游戏执行绪是在陪跑**，而陪跑的单位成本是「画一次半成品场景」。
每次 Sync 只花 68 ms（关是 189 ms），离 `ok.Studio.BuildSliceMs` 的 250 ms 与 `BuildsPerFrame` 的 96 都很远，
所以瓶颈不在这两个旋钮。

**没有结论的一趟**：同一张场景加大预算（`BuildsPerFrame 512`、`BuildSliceMs 2000`）跑了 16 分钟还没开完
（基线 139 s），因 slot 到期被我中止，没有数字。日志只到场景开始建，没有 `scene load:` 那行。原因未查，
不要拿它当「预算开大会更慢」的证据。

**下一步**：既然贵的是「画半成品场景的次数」，就在建构期间限帧（例如 `bBuildsPending` 期间压到 10 FPS），
让两边都少画几次，索引省下的 16 s 才会显示在 `ready_ms` 上。在那之前 `ok.Studio.SyncFindIndex` 的预设值
还不能当成已验证的改善——它让 `Sync` 变快是实测，让整体变快还没有。

## 2026-11-18（下午）：载入期间不画世界——开卡 **−29.7%**，而索引对整体依然是零

上一节的结论是「贵的是把半成品场景画一遍的次数」。于是加了 `ok.Studio.LoadSkipDraw`：`bBuildsPending` 期间把
`GEngine->GameViewport->bDisableWorldRendering` 打开，建完还原（存的是打开前的值，所以中途改 cvar、或场景在建构中
消失走 `EndPlay`，viewport 都会回到会画的状态）。比限帧（`ok.Studio.LoadMaxFps`，同时保留）更直接：限帧只是少画
几次，还顺便把「建下一批道具」的 Tick 一起压慢；不画世界只省掉画，游戏执行绪照原速建。

同一个建置、同一个小时，8806 物件那张（`koikatu_cs0003420_2.okscene`），冷开，每格一趟
（`Saved/Reports/scene-load-f/cfg.lua`，`OK_NOCACHE=1`，一趟一个新行程，三格轮转顺序）：

| `ready_ms` | 画（`LoadSkipDraw 0`） | 不画（`LoadSkipDraw 1`） |
|---|---:|---:|
| 索引关（`SyncFindIndex 0`） | 122 829 | **86 336（−29.7%）** |
| 索引开（`SyncFindIndex 1`） | 125 886（+2.5%） | 86 855（−29.3%） |

四个数字一起看（左起：基线、只开索引、只不画、两个都开）：

| | idx0 draw | idx1 draw | idx0 skip | idx1 skip |
|---|---:|---:|---:|---:|
| `ready_ms` | 122 829 | 125 886 | 86 336 | 86 855 |
| `sync_world_ms` | 27 543 | 1 046 | 25 141 | 1 167 |
| `build_frames` | 459 | 810 | 407 | 951 |
| 每帧 Sync 以外 `frame_other_ms` | 75.5 | 85.1 | **22.7** | **26.4** |
| `sync_ms` | 86 560 | 55 672 | 75 562 | 60 078 |
| 每次 Sync 建成几个 | 19.1 | 10.9 | 21.6 | 9.2 |
| `item_open_worker_ms`（8 条合计） | 446 671 | 395 940 | 380 533 | 444 429 |

两件事都站得住，而且结论和上一节的机制完全一致：

- **不画世界省的就是那 36 s**：每帧 Sync 以外的成本从 75.5 ms 掉到 22.7 ms（−70%），这正是上一节推断出来的
  「一帧约 80 ms 在画半成品场景」。省下的量级（36 s）远超任何单趟噪声。
- **索引对 `ready_ms` 依然是零**：不画世界之后它还是 86.3 vs 86.9 s（+0.6%，一趟之内就是噪声）。
  `sync_world_ms` 25.1 s → 1.2 s、`sync_ms` −12.7% 都还是真的，但这段载入由 worker 产出计价，
  把工作从游戏执行绪拿掉不会让它更快。所以 `ok.Studio.SyncFindIndex` **维持预设 0**——
  连「限帧之后就会显形」这个上一节写下的预期也被量掉了，码与测试留着，等哪天开卡真的卡在 Sync 自己。
- 「索引让帧变短 → 每帧建更少 → 帧更多」在不画世界时也成立（407 → 951 帧），只是每帧便宜到不再要紧。

据此 **`ok.Studio.LoadSkipDraw` 预设改成 1**。

代价要说准，我第一次写错了：**不是「停在载入前那一帧」**。`UGameViewportClient::Draw` 在 `bDisableWorldRendering`
时每帧都 `SceneCanvas->Clear(FLinearColor::Transparent)`（`GameViewportClient.cpp:1985`），所以世界那块是**每帧清空**，
只剩在它之后画的东西（UI）。一分半的空白画面跟当掉没两样，所以同一笔改动里加了一行进度
（`AddOnScreenDebugMessage`，画在 `DrawStatsHUD`，不受 `bDisableWorldRendering` 影响）：`Loading scene  n / n`。
刻意用 ASCII——引擎的 small font 没有 CJK 字形，写中文会变成方框；要本地化的载入画面该做在 Studio 的 Slate UI 里，
那是另一笔。想看场景一件件长出来就 `ok.Studio.LoadSkipDraw 0`。

验这件事的办法也加进 harness：`OK_SCENE_PROFILE_SHOT_LOADING=<帧>` 会在建构中的那一帧拍一张
`<tag>_<场景>_loading.png`——载入中的画面只能这样看到，拍完成品的 `OK_SCENE_PROFILE_SHOT` 看不到。

**量到但还没量的**：每格只有一趟（上一节是另一个建置的一趟）；36 s 的差不需要更多趟就成立，0.6% 的那个差需要。
还有一个没被指标盖住的风险：不画世界可能把 shader／材质的首帧成本推到载入之后，`ready_ms` 看起来变好而使用者
还在等——`ready_ms` 数的是「没有物件还在排建构」，数不到这个。要排除它得在 ready 之后再量「画面稳定」的时间
（例如 `GShaderCompilingManager` 连续 N 帧空闲），目前还没有这个字段。

## 2026-11-18（再测）：−29.7% 是单趟的运气，真实幅度约 −23%；而 `settle_ms` 立刻抓到一笔被推后的成本

上一节每格只有一趟，所以补了第二、第三个窗口与 856 物件那张。**结论的方向站得住，幅度要改小，而且小场景上净值
可能是负的。**

8806 物件那张（`koikatu_cs0003420_2.okscene`），索引关，冷开，三个时间窗口共 4 对：

| 窗口 | `LoadSkipDraw 1` | `LoadSkipDraw 0` | 每帧 Sync 以外（1 / 0） |
|---|---:|---:|---|
| 10:32–10:41 | 86 336 | 122 829 | 24.1 / 75.5 |
| 11:13–11:17 | 101 323 | 98 867 | 24.1 / 64.7 |
| 11:17–11:21 | 77 825 | 93 545 | 20.5 / 63.3 |
| 11:21–11:25 | 76 516 | 113 562 | 20.1 / 71.5 |
| **中位数** | **82 081** | **106 215** | — |

- **幅度改成约 −23%**（中位数 82.1 s vs 106.2 s），不是 −29.7%。那一趟赶上基线最慢的一次。
- **4 对里有 1 对没有差**（11:13 那对，101.3 vs 98.9）。机器是共用的，别组的 CPU 工作会同时改变两边；
  基线自己在 93.5–122.8 s 之间跳，这个变异比我想的大，单趟对单趟不够下结论。
- **唯一每趟都稳的是机制**：每帧 Sync 以外的成本 20.1–24.1 ms（不画）对 63.3–75.5 ms（画），四对之间完全不重叠。
  省下来的东西是确定的；它有多少会变成 `ready_ms` 的减少，取决于当下 worker 有多忙。

856 物件那张（`koikatu_cs0001521_2.okscene`，21 个角色、634 道具），一对：

| | `LoadSkipDraw 1` | `LoadSkipDraw 0` |
|---|---:|---:|
| `ready_ms` | 25 984 | 28 334 |
| 每帧 Sync 以外 | 11.9 ms | 32.3 ms |
| **`settle_ms`（ready 之后到 shader 连续 30 帧空闲）** | **4 376** | **1 288** |
| `ready_ms` ＋ `settle_ms` | **30 360** | **29 622** |

**`settle_ms` 抓到的正是我上一节自己列出的那个风险**：不画世界把 shader／材质的首帧成本推到载入之后，小场景上
推掉的（3.1 s）比省下的（2.3 s）还多，**端到端反而慢 0.7 s**。只看 `ready_ms` 会把这当成 −8.3% 的改善。
大场景上这笔小得多（1.4 s vs 0.9 s），端到端仍是 78.5 s vs 104.5 s。

**处置**：`ok.Studio.LoadSkipDraw` 预设维持 1。**站得最稳的是机制，不是端到端的中位数**：每帧 Sync 以外
20.1–24.1 ms（不画）对 63.3–75.5 ms（画），四对之间完全不重叠，每一趟都这样；端到端 82.1 vs 106.2 s（约 −23%）
要连着「同一张卡的基线自己在 93.5–122.8 s 之间跳、4 对里有 1 对完全没差」一起读，别单独引用那个百分比。

**而且不加「场景多大才开」的阈值。** 856 物件那张端到端赔 0.7 s（30.4 vs 29.6 s）我知道，但那 0.7 s 就落在上面
那个趟间噪声里；拿一个数据点去定一个物件数阈值，等于把噪声写成常数，之后没人敢动也没人能验。等哪天小场景的
净损失大到能稳定重现（多个窗口、多趟、方向一致），再回来谈阈值。

**还没验到的**：载入中的画面还是没拍到。第一版的 `OK_SCENE_PROFILE_SHOT_LOADING` 用了
`RequestScreenshot(path, bShowUI=false, false)`，把 UI 与进度行排除在截图外，拍回来两边都是全黑，什么也证明不了
（已改成 `bShowUI=true`，还没跑）。所以「使用者在载入期间看到什么」目前只有引擎码的推论（世界每帧清空＋
`DrawStatsHUD` 画的进度行），没有照片。

### 载入中的画面：拍到了，而且撑住底线的不是我加的那行

2026-11-18 11:48–11:50，8806 物件那张，`LoadSkipDraw 1`，在建构中的第 250 帧拍：

- `Saved/Reports/scene-load/shotA-draw1-r1_koikatu_cs0003420_2_loading.png`（1920×1080）
- `Saved/Reports/scene-load/shotB-draw1-r1_koikatu_cs0003420_2_loading.png`（1280×720）

两张都看得到 **`SOKStudioLoadOverlay`**（f-studio-ui 的 Slate 覆盖层，ZOrder 30）：「載入場景 / koikatu_cs0003420_2 /
67%（720p 那张 68%）/ 已建 5,932 共 8,806 個物件」加进度条，左下角另有「建置場景物件 5932 / 8806」。
世界那块如预期是空白的，Studio 的面板照常画。**所以「载入期间任何时候都看得到进度」这条底线成立，两种窗口都成立。**

**但我原本以为撑住它的那行不会显示。**我在 `SetLoadThrottle` 里加的 `AddOnScreenDebugMessage` 从来没出现过：
`AOKStudioGameMode::StartPlay` 就把引擎萤幕讯息整个关掉了（`OKStudioGameMode.cpp:27`），而且是刻意的。
那行已经移除，注解改成写明 **这个预设值依赖 `SOKStudioLoadOverlay` 显示进度；那个 overlay 不在就把预设改回 0**。

## 2026-11-18：`ok.Studio.ItemOpensAhead` 8／16／24——**不是闸门**，而且我先前「worker 没吃满」的推论是算错的

假设是：`item_open_worker_ms` 约 380 s ÷ 8 条 ≈ 48 s，而开卡要 77–86 s，中间 20–30 s 没人做事，闸门
（`PrepareItem` 的 `Opening >= Ahead`，预设 8）卡住了 worker。**两轮下来这个假设站不住，而且推论本身就错。**

8806 物件那张，索引关、`LoadSkipDraw 1`，冷开，两轮交错（第二轮换顺序）：

| | a8 | a16 | a24 |
|---|---:|---:|---:|
| `ready_ms` 第一轮（顺序 8→16→24） | 79 580 | 71 313 | 100 034 |
| `ready_ms` 第二轮（顺序 16→8→24） | 84 388 | 95 094 | 73 123 |
| **中位数** | **81 984** | **83 204** | **86 579** |
| `item_open_worker_ms` 第一／第二轮 | 378 362／383 108 | 704 012／744 807 | 1 042 028／1 031 837 |
| `peak_used_gb`（行程内） | 8.1／8.2 | 8.1／8.2 | 8.2／8.2 |

**时间上：两轮互相矛盾，没有可测到的效果。** a24 第一轮 100.0 s、第二轮 73.1 s；a16 第一轮 71.3 s、第二轮 95.1 s。
三个值的中位数 82.0／83.2／86.6 全部落在彼此的散布里。按先讲好的判别法：**开到 24 时间没变好 → 瓶颈不是队列深度**，
不再往上加。

**但有一个每轮都稳的数字，它正好说明为什么：**`item_open_worker_ms` 随 Ahead 几乎线性涨（378→704→1042，
两轮差 ±2%），而墙上时间不动。这是「同一批工作挤同样的 CPU」的特征：开的件数变多，每件就按比例变慢，
吞吐不变。**worker 早就吃满了，不是闲着。**

**我先前的推论错在哪**：`item_open_worker_ms` 是把每个 open 的**经过时间**加总，重叠执行的工作会被重复计入，
它不是 CPU 时间，所以「÷ 8 得到 48 s」没有意义。用一个不是 CPU 时间的和去推 CPU 有没有吃满，是把指标的
定义想当然了。

**处置**：`ok.Studio.ItemOpensAhead` 维持 8（记忆体峰值三个值都没有差别，所以也没有「开大换时间」可谈）。
那 20–30 s 的来源要改用别的方法找：量主执行绪提交与材质建立这类真正的串行段（`item_spawn_ms`、`item_model_ms`），
或直接用 Unreal Insights 看一帧里谁在等谁。

**记忆体（这轮才补齐的三个数字）**：行程内 `peak_used_gb` 8.1–8.2 GB；外部取样的行程峰值是工作集 8.37–9.83 GB、
commit 9.49–10.87 GB，三个 Ahead 值之间没有差别。以 16 GB RAM 的低配目标来看，这张 8806 物件的场景光是
commit 就要 10 GB 上下，余裕不大，但那跟 Ahead 无关。**VRAM 这轮没量到**：量它的程式（`RHIGetMemoryStats`）
写好了但还没建置——别组的编辑器开着时 Live Coding 会挡住建置，下一段补。

## 2026-11-18（傍晚）：索引翻盘——和不画世界一起开才有用，**预设改成 1**

上一节写「不画世界之后索引对 `ready_ms` 还是零（86.3 vs 86.9 s）」，那是**一趟**。同一天补了三对交错，结论相反，
而且三对完全不重叠：

| | 索引开 | 索引关 |
|---|---:|---:|
| `ready_ms` 三趟 | 78 281 / 76 105 / 72 942 | 93 019 / 87 742 / 86 518 |
| **中位数** | **76 105** | **87 742（−13.2%）** |
| `sync_ms` | 54 886 | 78 593（−30.2%） |
| `sync_world_ms` | 1 064 | 27 005（−96.1%） |
| `build_frames` | 866 | 408 |
| 每帧 Sync 以外 | 24.2 ms | 23.9 ms |

#### 交互效应的完整机制（为什么单独量索引会得到 0 甚至负值）

这段写清楚，因为「单独量到 0 就以为没用」正是这轮最大的坑。因果链有四环，每一环都有量到的数字：

1. **索引让 Sync 自己变便宜**：`sync_world_ms` 27.0 s → 1.1 s，`sync_ms` 78.6 s → 54.9 s，省下约 24 s。
2. **Sync 变便宜 → 每帧变短**。而载入的节奏不是由游戏执行绪决定的：道具是在**它的 worker session 准备好的那一帧**
   才建（`OKSceneActor.cpp` 的 `bItemWaiting = … && !PrepareItem(Object)`）。帧短了，每帧等到的道具就少
   （每次 Sync 建成 21.5 → 10.2 个）。
3. **每帧建得少 → 帧数翻倍**：408 → 866 帧。总共要建的物件数不变，所以帧数几乎正好反比。
4. **每多一帧，就多付一次「这一帧 Sync 以外的成本」**。这一项由另一个开关决定：
   - 画世界时约 **80 ms**／帧 → 多出的 458 帧 × 80 ms ≈ **+37 s**，吃掉第 1 环省下的 24 s 还倒赔，
     所以单独开索引是 **+24.7%**（11-18 上午量到的）。
   - 不画世界时约 **24 ms**／帧 → 多出的 458 帧 × 24 ms ≈ **+11 s**，小于省下的 24 s，净赚约 13 s，
     就是这里量到的 **−13.2%**。

所以这两个开关不是「各自有效、加起来更好」，而是**索引的收益被帧数放大后的重画成本抵消**，只有先把重画拿掉，
索引的收益才留得住。要判断类似的开关，光看它自己的那一项（`sync_ms`）会得到「省了 24 s」，看 `ready_ms` 会得到
「亏了 27 s」，两个都对，差别在中间那两环有没有被数到。

**两个开关只有一起开才划算**：索引让 Sync 变便宜 → 帧变短 → 帧数翻倍（408 → 866）；画世界时每帧 80 ms，
翻倍的代价大于省下的，所以单独开索引是亏的（那也是 11-18 上午量到的 +24.7%）。不画世界之后每帧只剩约 24 ms，
省下的 24 s 才留得住。**`ok.Studio.SyncFindIndex` 预设改成 1**，协调者定的 11-21 期限提前有了答案：不是死码，是
要搭配才生效的码。

一趟与三对的差别值得记住：上一节那句「索引没用」是一趟得出的，而这台机器同一张卡的基线会在 86.5–93.0 s 之间
跳——**一趟的差只要小于这个跨度就没有信息**，当时我写得太确定了。

### `sync_live_ms`：假设错了，那 20–30 s 不在这里

上一节找到「`sync_ms` 减去所有计时器还剩 18.5／19.5 s」，我猜是 Sync 里对每个物件比对已套用状态（morph override、
`LiveMaterialEdits`、灯光特效）那段，于是加了 `sync_live_ms` 把它圈起来。**量出来只有 1.1–2.2 s。**

而且 `unaccounted` 在索引开（23.7 s）与关（22.3 s）几乎一样——**它跟查找成本无关**，所以也不是父链走访的残留。
剩下的嫌疑在：`SyncMap()`、每帧对 8806 个物件的回圈本身（`Shown` 查找、`SwapKeyedMotion`）、以及 `PrepareItem`
的闸门检查（每个未建的道具每帧都问一次）。下一步是再加两个计时器（`SyncMap` 与闸门检查）把它夹出来，
别再用猜的。

### 记忆体（三个数字补齐，给低配目标参考）

8806 物件那张，`LoadSkipDraw 1`，索引开／关都一样：行程内工作集峰值 **8.1–8.2 GB**、commit **9.0–9.1 GB**、
**VRAM 1.9–2.0 GB**，`vram_over_budget` 全程 **0**。也就是说这张场景的压力在系统记忆体，不在显存；
8 GB VRAM 的机器没有风险，16 GB RAM 的机器则要注意 commit 已经到 9 GB 上下（见下一节）。

## 低配目标（16 GB RAM／8 GB VRAM）：大场景的压力在系统记忆体，不在显存

单独记一条，免得埋在别的结论里。8806 物件的 `koikatu_cs0003420_2.okscene`，冷开，2026-11-18 多趟量到的峰值：

| | 峰值 | 对 16 GB／8 GB 的意思 |
|---|---:|---|
| 行程工作集 | 8.1–9.8 GB | 16 GB 机器上作业系统与其他程式只剩一半多 |
| commit charge | 9.0–10.9 GB | 分页档小的机器先爆的是这个 |
| GPU local memory | 1.9–2.0 GB | 8 GB VRAM 余裕很大，`vram_over_budget` 全程 0 |

这些数字跟 `ok.Studio.ItemOpensAhead`（8／16／24）无关，也跟索引、是否画世界无关——是场景本身的量。
要降的话得从「同时握着的道具 session」与贴图常驻下手，不是调这几个旗标。
（量法：行程内 `FPlatformMemoryStats` 的 `UsedPhysical`／`UsedVirtual`，GPU 用 `RHIGetMemoryStats` 的
`UsedLocal`／`BudgetLocal`／`IsOverBudget`；外部另用 `Win32_Process` 取样核对——注意 `PeakWorkingSetSize` 是 KB。）

## 2026-11-19：照量测标准自查，以下数字就地降级（原数字不删）

E 组今天付了四次代价定出来的量测标准（见 `Docs/ERROR_LOG.md` 与协调的清单）套到这份与
[大场景那份](OK_STUDIO_BIG_SCENE_LOAD_20261118.md)之后，**这份里有几个结论要降级**。
原数字一律保留——它们是当时真的量到的，只是**不足以支撑原本写的那个结论**。

**先说还能用的**，免得整批被当成废的：大场景那份的导入 A/B（同一执行档、交错两轮、而且**有开关生效迹象**：
每趟日志的 JSON 大小 3.6／2.6 MB 对 347.7／297.3 MB）的**同轮差值**仍然成立；
本份 2026-11-18「再测」那节（多窗口、已自我更正过单趟运气，`−23%`）也仍然成立。

| # | 原本的结论 | 为什么降级 | 降级成 |
|---|---|---|---|
| 1 | `ac498d042`「对这条路没有效果」 | **跨建置**比较（合并前 14 182／14 595 ms vs 合并后 13 981／14 320 ms），只有同一执行档上的趟可以互比 | **不可判**。不能写成「没有效果」，只能说「这两个建置上各量到的数字落在同一区间」 |
| 2 | `SyncFindIndex`「+24.7%，瓶颈不在这两个旋钮」 | 各一趟；执行档是「`7e003b86f` ＋**未提交的计数器**」；而且**没有申报旋钮生效的正面迹象**（只有「时间没变／变差」） | **不可判**，且见下面「不可复原」 |
| 3 | `ItemOpensAhead`／`BuildsPerFrame` 一类「没效果」 | 同样缺生效迹象：没有差异可能是旋钮没生效 | **降级**为「这次没量到差异」，不是「这个旋钮没用」 |
| 4 | 全部绝对 ms 数字 | 没有执行档身分（只有 commit hash），也没有量具自测 | **只能当同轮内的相对量**，不可跨窗口比 |
| 5 | 大场景那份 A/B 表的「中位数」 | `n=2` | 改印**原始两个值与 n**；见下面的 n<3 规则 |

### 不可复原：`7e003b86f` ＋未提交的计数器 那一组

上面第 2 项那个执行档**现在既重建不出来、也认不回来**（计数器从未提交，没有 patch 存档，
表头机制当时还不存在）。所以它**不是「暂时不能用、补个身分就好」，而是永久失去身分**：

> **不可复原。不要在未来任何比较中复活这组数字**——包括拿它当基线、当「之前量过」的引用、
> 或和新数字并排。要那个结论就重量一次。

### 由此加上的两条规矩

- **第 8 条（量测用到的未提交改动必须先固定下来）**：量测前**提交**，或至少
  `git diff > <存档的 patch 档>` 并把 patch 的杂凑记进表头。否则执行档在量测结束的瞬间就永久失去身分，
  **数据当场变成不可复原**——上面那一组就是实例。
- **n < 3 不报任何集中趋势量**（中位数、平均、幅度百分比），直接印**原始值与 n**。
  两个点没有中位数；两个点算出来的百分比，读的人会当成有代表性。

### 还要补的（等机器窗口）

1. 量测脚本接 `Tools/shot_batch_header.lua write --purpose load --editor F:/OpenKoikatsu`（**`load` 不是 `shots`**：音档要算进去，`base_v1` 是 136 935 档而不是 15 370），**每趟**写 `batch_header.json`，
   比完再 `check`（结束码 0 SAME／1 DIFFERENT／2 MISSING／3 OLD 或 RULES，**只有 0 可比**，别接管线）。
   `RULES` 是「用途或指纹规则不同」——例如拿 `shots` 的表头去跟 `load` 的比，它会拒绝而不是回 `SAME`。
   它第三版连 `base_v1` 等**不进版控的原作衍生资料**也记——场景卡载入耗时直接吃基础库内容，
   这条对这边比读卡器更要紧。
2. **量具自测**：已知为正＝在被量的区段里人为塞一段 sleep，看对应的 `*_ms` 有没有跟着涨
   （这测的是**量具本身**，不是被量的东西）；已知为负＝不塞，确认不涨。两次都留纪录，
   **没有自测纪录的量具，输出不进纪录**。
3. 「同一执行档、交错两轮」这个做法继续用；有了表头之后，它才从**断言**变成**证据**。

## 2026-11-19 窗口：`ok.Studio.SyncFindIndex` 量完了（Q1）

**结论（措辞到此为止，不要外推）**：在**这个 8 806 物件的场景**（`koikatu_cs0003420_2.okscene`）、
**这个执行档**上，`ok.Studio.SyncFindIndex=1` 比 `=0` 的 `sync_world_ms` **快约 45 倍**、
`ready_ms` **少 41.1 秒**。**预设 1 正确，不改预设，不动共用程式码**，
因此也不需要走共用验证与通知 OK Studio 那条线。

这推翻了 11-18 那组「索引开反而慢 24.7%」的旧数字（那组早已自查降级为**不可判**：各一趟、
执行档含未提交的计数器、没有阳性样本）。

| 趟 | `SyncFindIndex` | `find_index_builds` | `sync_world_ms` | `ready_ms` | `build_frames` |
|---|---:|---:|---:|---:|---:|
| 1 | 1 | 2 436 | 1 155.4 | 62 848.3 | 1 202 |
| 2 | **0** | **894** | **51 855.4** | **103 981.4** | **863** |
| 3 | 1 | 2 420 | 1 171.4 | 62 850.7 | 1 194 |

**依据是效果的量级远大于任何合理散布**（41 秒／45 倍），不是「效果 ≫ 地板」：
段 A 同设定两趟的 `ready_ms` 只差 **2.4 ms**（62 秒上的 0.004%），**那不可能是真的趟间散布**——
一个跑 62 秒、上千帧、吃磁碟与 GPU 的流程不会稳到万分之零点四。照 11d（**噪声会抖，常数是偏移**），
这么紧的一致本身就是异常（两趟背靠背、可能共用了暖起来的状态），
**所以段 A 那两趟不能当地板用**，它量到的是「两趟几乎共用同一状态时的差」。

**`ready_ms` 的散布下限：约 0.6 秒**（同场景同执行档的第三个观测，Q2 的 96/250 arm 是 62 206.6 ms，
比段 A 两趟低 641.7 ms）。真实散布只会更大不会更小，往后拿 `ready_ms` 比较都用这个当下限。

**到达证据**：`find_index_builds`（机制那一点，`OKStudioLoadProfile.cpp:223`）。
`sync_world_ms` 的 45 倍**没有**拿来当到达证据——它是被判的指标，那会循环论证。

**没量的、要补才知道的（砍掉的东西留在这里，别当成量过）**：

- **未量小场景是否同向。** 若日后有人考虑**按场景规模切换 `SyncFindIndex`**（例如小场景设 0），
  **需先补量**：本窗口只量了大场景。
- **未做前后半交错**（段 B 砍掉）：单轮 n=3，冷暖与漂移没有被控制住。
  三趟没有出现单调趋势，但 n=3 本来就不谈分辨率。
- 原始资料与现场笔记：`Saved/Reports/scene-load-q1-20261119/segA/`（三份 json、开工与收工表头、NOTES.md）。
  量测用的执行档**含有量具自测的注入程式码（关着）**，未提交；patch 与杂凑在
  `Saved/Reports/scene-load-selftest-20261119/`。

## 2026-11-19 窗口：`BuildsPerFrame`／`BuildSliceMs` 量完了（Q2）

详细纪录与原始 json 在 `Saved/Reports/scene-load-q2-20261119/`（`RESULT.md` 是定稿）。两句话：

1. **「开不完」没有重现**：`512/2000` 挂钟 **76 秒**跑完，对 `96/250` 的 77 秒。
2. **加大预算什么都没改变**：`build_frames` 1 197 → **1 200**；`ready_ms` 62 206.6 → 61 987.6。

**旋钮确实到达**（log 回显 `LastSetBy: Console`，两个值都没被 `ObjectBuildBudget()` 的 0–4096
与 `BuildSliceSeconds()` 的 10–5000 ms 夹掉），所以这是**「有到达、没效果」**，
是今天少数可以干净写成排除的一格。

**措辞范围**：在**这个 8 806 物件的场景、这个执行档**上，把 `BuildsPerFrame` 96→512、
`BuildSliceMs` 250→2000 **不改变 `build_frames`、不改变载入耗时、也不会开不完**。
不外推到别的场景规模，也不宣称这两个旋钮「没有用」。

**为什么没效果（有证据、未经直接验证的解释）**：`item_open_worker_ms` 约 **267 秒 worker 时间**
对 `item_build_ms` 约 19.8 秒，`starved_syncs` **153/1198**——瓶颈指向**物件在 worker 上开启**，
每帧可建的本来就远少于 96 个。**但 profile 没有「每帧实际建了几个」这一栏**，所以这句没有直接证据（10b）。

**11-18 那趟「`512` 跑了 16 分钟还没开完」记「未重现」**：那趟没有数字、没有表头、执行档身分不明，
**不能判断它当时发生了什么**，也**不能**拿这次的 76 秒去覆盖它。

## 这个窗口没量的（取消或砍掉，别当成量过）

| 没量的 | 原因 |
|---|---|
| **Q3：原作 KStudio PNG 那 ≈14 秒 `load_call_ms` 的分项** | **未量，因「当机最优先」而取消**（2026-11-19 使用者指示） |
| Q1 小场景是否同向 | 砍掉：结论是维持预设，答案不改变做法。日后若想按场景规模切换 `SyncFindIndex`，**需先补量** |
| Q1 段 B（前后半交错） | 砍掉：效果 45 倍、远大于散布，再跑一轮不改变结论。代价是冷暖与漂移未控制，单轮 n=3 |

## 下一轮的起点（这窗口学到、但还没做的）

1. **加一个「每帧实际建了几个」的读数**（直方图或最大值）：没有它，Q2 那个「瓶颈在 worker 开启」
   永远只能写成解释而不是结论。
2. **`ready_ms` 的散布下限约 0.6 秒**：别再拿两趟背靠背的差当地板（那次是 2.4 ms，0.004%，不可能是真的）。
3. **log 行速率两数（最后一分钟／前一分钟）只在趟长超过约 2 分钟时有意义**：
   短趟里「前一分钟」几乎全是启动期，会看到上升而不是衰减。
   量具应该**只印原始数字、不印结论**——这个设计在 Q2 的 76 秒趟上救了一次。
