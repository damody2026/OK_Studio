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

## 结果

（量完填：两侧中位数表、判定、以及峰值记忆体有没有变差。在那之前这一节是空的——**不要**先写预期值。）
