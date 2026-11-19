# OK Studio：Sync 的摆位改成一次由上而下（2026-11-20，F 树）

`ok.Studio.SyncPlaceIndex`。**这份是先写定跑法与读法的预先登记，数字那一节在量完才填**——边跑边决定读法会读出自己想看的结果。

## 为什么动这里

8806 物件场景冷开 88 003 ms，其中 `Sync` 63 406 ms，而 `WorldTransform(Id)` ＋ `IsShown(Id)` 占 **23 526 ms**
（`Sync` 的 37%、整趟的 27%，见 [OK_STUDIO_SCENE_LOAD_PERF_20261117.md](OK_STUDIO_SCENE_LOAD_PERF_20261117.md)）。
两者都为**每个物件、每帧**各走一遍父链；而 item 父的 child point（`AnimatedItemChildPoint`，要查目录与动画）
在旧写法里是**每个後代各算一次**。

**两个量过之後不要再试的方向**（同一份报告）：写 transform／visibility 只占 1 979 ms，
`ok.Studio.SkipUnchangedPlacement` 的 A/B 是开 88 003 ms、关 87 573 ms（关的还快 0.5%），已回退；
`SameContent` 深比较只占 516 ms，上限就是那 0.5 s，不值得做。

## 改了什么

`UOKSceneDocument::FPlaceScope`：scope 活着时，`WorldTransform` 与 `IsShown` 从**一次由上而下的 pass** 回答。

- pass 由每个根往下走，父一定排在子之前，所以每个物件只跟**一个**变换合成，而不是一条链。
- item 父的 child frame 在**第一个子来问时算一次**存起来，之後该父的每个子共用。
- 可见性由上往下与：`shown = 父的 shown && O.bVisible`，与旧写法逐层问 `bVisible` 等价。
- **pass 走不到的照旧走父链**：父链成环（没有根到得了）、或深过 `MaxDepth`（4096）的那一截；
  所以那些 id 的答案还是它本来的答案，不是「identity」。
- scope 的寿命就是一次 pass：它读 `ItemAnimationSeconds` 与 `BoneFrame`（当下的骨架姿势），所以**不能跨帧留**。
  `Sync()` 里开在 `BoneFrame` 指派**之後**（在那之前建会把每个挂点物件摆在角色根上，然後整个 Sync 都用那张错表），
  也在 `SyncMap()` 之後。
- 开关：`ok.Studio.SyncPlaceIndex`（预设 1，`0` 回到逐条走父链）；诊断用环境变数 `OK_STUDIO_PLACE_INDEX=0` 同效。
- profile JSON 多一个 `place_builds`：一个 Sync 一次；关掉时是 0。

正确性：`OpenKoikatsu.Studio.ScenePlaceIndex`（新增）把两条路径**逐物件**对照——item 链（含父的缩放只移动不放大子）、
角色骨架上的两个挂点、没骨头的挂点、隐藏层、父不存在的孤儿、父链成环、scope 内增删物件、
以及骨架在两个 pass 之间移动（证明 pass 不会把旧骨架留到下一帧）。与既有的 `OpenKoikatsu.Studio.SceneFindIndex` 一起跑。

## 跑法（预先登记；拿到槽直接照跑，不要改）

```powershell
.\Tools\lua\lua.exe Saved\Reports\scene-load-f\ab-place.lua Saved\Reports\scene-load-f\cold-heavy-only.txt heavy-place 2
```

- 脚本与清单在 `Saved/` 底下，**不进版控**（`.gitignore` 第 5 行）：新 checkout 要照这一节重建。
  清单一律给**绝对路径**——编辑器的工作目录不是那个 shell 的。
- 场景：`F:/OpenKoikatsu/UserData/Studio/scene/koikatu_cs0003420_2.okscene`（8806 物件）。
- **每侧 2 轮，共 4 趟**；每轮两侧对调（第 1 轮先开後关、第 2 轮先关後开），所以机器状态的漂移不会只落在一侧。
- 每趟**一个新行程、冷开**（`OK_NOCACHE=1`）、载入清单第一个场景、`OKStudio.ProfileSceneLoad 1 exit`。
- 跑之前确认机器上只有这一个 Unreal（`unreal_slot.lua status` 的 `unreal processes`），并且槽是自己的（`may-build` 回 `go`）。
- 超过 20 分钟就 yield；有人排独占量测一律先让，**中途被停的那趟整趟作废、不取它的数字**。

## 读法（预先登记）

| 字段 | 看它做什么 |
|---|---|
| `place_builds` | **闸门**：开的那侧必须 > 0、关的那侧必须 = 0。不满足就是开关没翻到，**整趟作废**，不读其他字段 |
| `sync_world_ms` | 这次改动针对的那一段（`WorldTransform` ＋ `IsShown`）。预期大幅下降 |
| `sync_ms` | `Sync` 总计；`sync_world_ms` 省下来的要在这里看得到，否则是省到别处又花回去 |
| `ready_ms` | 整趟开场景。**判定看这个** |
| `sync_same_ms`、`sync_place_ms` | 不该动；其中一个明显变化就是改动漏到别处 |
| `syncs`、`build_frames` | 帧数会随 Sync 变快而变多（上一轮踩过：帧变短、帧数翻倍，重绘半成品的成本会吃掉省下的）。**只看这两个不能下结论**，但它们解释 `ready_ms` 为何不等比例下降 |
| `objects`、`find_index_builds` | 两侧必须一样（同一个场景、同一条索引路径）；不一样表示比的不是同一件事 |

判定门槛：**`ready_ms` 的两侧中位数相差超过约 3% 才算真变化**（照专案惯例；3% 以内按噪声处理，并把两侧数字都写下来）。
`sync_world_ms` 另外单独报，因为它是这次改动的直接目标，幅度会比 `ready_ms` 大。

失败样本的处理：

- 某一趟没写出 JSON（行程被杀、崩溃）：**那一趟作废，补跑一轮完整的对调**，不用别轮的数字补位。
- 两侧的 `objects` 或 `find_index_builds` 不同：整趟作废。
- `place_builds` 在关的那侧非零：开关没翻到，整趟作废。
- 若 4 趟里有 2 趟以上作废：整个量测重跑，不混用。

**跨时段的绝对值不可比**：只比同一轮之内交错取的中位数（上一轮同一件事量到 6.5–7.4 s 与 5.0 s 两组，差别只是别组在不在吃机器）。
**单次量测会给出错的幅度**，所以每侧至少 2 趟。

## 结果：**前提是过期的，改动已撤回**

量了 4 趟（交错两轮，`heavy-place-place{0,1}-r{1,2}`，报告在 `F:\OpenKoikatsu\Saved\Reports\scene-load\`）：

| 字段 | pass off | pass on | |
|---|---:|---:|---|
| `ready_ms` | 66 049 | 65 390 | −1.0%（门槛 3% 以内，噪声） |
| `sync_ms` | 45 171 | 44 772 | −0.9% |
| **`sync_world_ms`** | **1 182** | **1 927** | **+63%（目标那一段变慢了）** |
| `sync_same_ms` | 1 285 | 1 217 | −5.3% |
| `sync_place_ms` | 2 619 | 2 589 | −1.2% |
| `syncs` | 1 164 | 1 169 | +0.5% |
| `objects` | 8 806 | 8 806 | 一样 |
| `find_index_builds` | 2 356 | 1 199 | **两侧不同（见下）** |
| `place_builds` | **1** | 1 170 | **关的那侧不是 0（见下）** |

### 按登记的读法，这一趟不算有效量测

两条闸门都没过：`place_builds` 关的那侧是 **1**（不是 0），`find_index_builds` 两侧不同。
两者都查清楚了，但**读法是跑之前写定的，不能看到数字再放宽**，所以这 4 趟不作为 A/B 结论：

- 关的那侧 `place_builds=1`：`-ExecCmds` 的 cvar 在**第一个 Sync 之後**才生效，所以空场景那一次 Sync 仍走了 pass。
  要让这条闸门可用，得改成「关的那侧 ≤ 1，且那一次必须落在载入开始之前」——**下次跑之前**改，不是现在。
- `find_index_builds` 两侧不同：pass 自己建 id 表、不经过 `Find()`，所以 `FFindScope` 的索引重建次数跟着变
  （关 2 356 ≈ 每个 Sync 两次、开 1 199 ≈ 每个 Sync 一次）。那条「两侧必须一样」的要求对**这个**开关是错的，
  它只适用于不动查找路径的改动。

### 不依赖那条 A/B 也成立的两件事

1. **`sync_world_ms` 现在是 1.1–1.2 s，不是 23.5 s。** 两侧、四趟都在 1.1–1.9 s。
   11-17 报告里那 23.5 s 是**那条 id 索引（`ok.Studio.SyncFindIndex`，11-18）之前**的数字：
   当时每走一层父链都要线性扫 `Objects`，索引把它拿掉了，剩下的链走本身很便宜。
   **所以这一轮针对的成本早就不在了**，上限只剩约 1.2 s（63 s 的 1.9%），连 3% 的门槛都到不了。
2. **pass 让它变慢是有道理的，不是实作没调好。** 场景是一帧建一批、分 1 170 个 Sync 建完的，
   每个 Sync 的回圈只碰**目前已经存在**的物件；而 pass 每次都从根走完**全部 8 806 个**并建一张表。
   省掉的链走比建表便宜，所以越早的 Sync 越亏。

### 处置

**撤回**（`FPlaceScope`、`ok.Studio.SyncPlaceIndex`、`place_builds`、`OpenKoikatsu.Studio.ScenePlaceIndex` 全部移除，
工作树回到 `afcf919cc`）。改动本身是对的形状——逐物件对照测试全 PASS、两条路径的数字一致——但它解决的是一个
**已经被别的改动解决掉的成本**，而且在「边建边同步」这个形态下净亏。不留 default-off 的死码。

**如果日後有人要再试这个想法**，先确认两件事：场景已经建完（不要在 1 170 个 Sync 里各建一次表），
以及那时 `sync_world_ms` 真的还是大头。

## 下一个人该动哪里（这 4 趟顺手量到的）

同一趟 `sync_loop_ms` 42 499 ms 的组成：

| 字段 | ms | 是什么 |
|---|---:|---|
| `item_build_ms` | 20 185 | 回圈里建道具（含 `item_spawn_ms` 17 401，UE spawn，必须在 game thread） |
| `sync_gate_ms` | 11 938 | 每个 Sync 问每个道具「它的 session 好了没」那道闸 |
| `sync_place_ms` | 2 501 | 写 transform／visibility（11-17 量过，跳过不划算） |
| `sync_live_ms` | 2 463 | 回圈里的 live 更新 |
| `sync_world_ms` | 1 146 | 这一轮针对的那一段 |
| `sync_same_ms` | 1 205 | `SameContent` 比较（11-17 量过，上限 0.5 s） |

⇒ **`sync_gate_ms` 的 11.9 s 是现在最大的、还没有人碰过的一块**：它是一道每帧对每个物件都问一次的闸，
而答案在物件的 session 好了之後就不会再变。`item_spawn_ms` 的 17.4 s 是已知的下一块（要动
`Plugins/KKUnityBundle` 的同型号共用 mesh／material，三组共用，动之前要先讲）。
