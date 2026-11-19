# 把「材質貼圖」那批移植到 E 树（2026-11-19）

F 树这批做的是：MaterialEditor 的贴图读写（`textures`／`textures_apply`）＋读卡器的「材質貼圖」页
（指派／清除／偏移／缩放）。这份是给套的人照着跑的清单。

> **状态：现在不要套，这份只保持最新。**（协调 2026-11-19 拍板）
> 第二层（读卡器界面）在 E 树缺的整条上下文，正是 **e-fork-2 这轮窗口要带进 E 的东西**
> （12 笔 cherry-pick ＋ `step2-items.patch`）；等它落地，上下文自然就有了，
> **交给常规整合带过去比现在硬挑干净**。第一层（资料端）虽然能单独做，但 E 现在没有人要用它，
> 提早搬进去只会多一份要维护的分叉。所以：**待 e-fork-2 窗口落地后，由协调决定是否照这份做第二层。**
>
> **套之前一定要先做这一步**（E 的 HEAD 会一直漂）：
> ```powershell
> git -C E:\OpenKoikatsu rev-parse --abbrev-ref HEAD   # 确认还是 master，不是 duo2
> git merge-base --is-ancestor d6b60bc24 <E 当下 HEAD>  # 确认基准没被改写
> ```
> 两项都过，再照第 3 节重新预演一次；**不要拿这份里的衝突表当当下的事实**。

## 0. 预演的基准（会漂移，照实写）

| | 值 |
|---|---|
| 预演时 **E 的 HEAD** | `9ae0439c5`（**分支 `master`**，2026-11-19 14:48:03，`NoBackdrop 加模式 2`） |
| F 的 HEAD | `b6fc31af7`（2026-11-19） |
| 两边的共同祖先 | `d6b60bc24`（`整合 #19`，2026-11-19 00:18:33） |

**E 正在被 e-cardload 推进，所以它的 HEAD 一定会变。** 下面每一笔的衝突是对着
`9ae0439c5` 预演的；套的时候先 `git merge-base --is-ancestor d6b60bc24 <E 当下 HEAD>` 确认基准没被改写，
再照同样的方式重新预演一次。**不要假装 HEAD 不会变。**

### 先纠正一个会害人的说法

**E 的 `duo2` 分支不是 E 在用的东西。** `duo2` 停在 `0fc3c8989`（2026-11-07），
E 的工作分支是 **`master`**。我第一次预演就是对着 `duo2` 做的，整份结果都没用。

还有一个更隐蔽的：**`git cat-file -e <commit>` 在 E 树成功，不代表 E 的 HEAD 有那笔。**
物件在不在物件库，和它在不在历史里，是两个问题——E 之前从 F 取过东西，物件就都在。
要问「E 的 HEAD 有没有这笔」只有一个答案算数：

```powershell
git -C E:\OpenKoikatsu merge-base --is-ancestor <commit> HEAD
```

我用 `cat-file -e` 得到的「E 有」**全部是错的**：用 `--is-ancestor` 重问，
今天 F 在这一块的提交 **E 一笔都没有**（共同祖先停在今天 00:18 的整合 #19）。
这正是 `Docs/ERROR_LOG.md` 那条通则的第一问与第三问：**先确认那个来源答不答得了这个问题。**

## 1. 这不是「挑四笔」的事

协调给的四笔（`7ecd947ff`、`dca71c93e`、`3af999058`、`fe5d80d11`）里，
**只有 `7ecd947ff` 与 `dca71c93e` 是自足的**。`3af999058` 与 `fe5d80d11` 改的是读卡器界面，
而它们的上下文（头发四页、`ops` 按钮、`MakeOwnToggle`、身分式外挂键）全部是今天 F 的新东西，
E 一笔都没有。硬挑会得到一堆「找不到上下文」的衝突，还会把半个功能留在 E 树。

所以分两层，**可以只做第一层**：

### 第一层：资料端（只要 Rust，和界面无关）

| 顺序 | 提交 | 带什么 | 为什么不能漏 |
|---:|---|---|---|
| 1 | `97e2be23a` | `Tools/ok-extract/src/appearance/ops.rs`（新）＋`appearance.rs` 的 `mod ops;` | `7ecd947ff` 的 `mod textures;` 就贴在 `mod ops;` 旁边；没有它，那一行没有上下文 |
| 2 | `7ecd947ff` | `appearance/textures.rs`（新）、`appearance.rs` 的 dispatch 分支、两份文件 | 贴图读写本体 |
| 3 | `3af999058` 的 **`textures.rs` 部分** | 只取 `Tools/ok-extract/src/appearance/textures.rs` | `Vector2` 的形状（两个 float32 的定长阵列）与那支实卡测试 |
| 4 | `dca71c93e`、`2eca4ce2a` | 纯文件 | 外挂键的走法与两处更正；可最后带，也可不带 |

只取某一笔里的某些档：

```powershell
git show 3af999058 -- Tools/ok-extract/src/appearance/textures.rs | git apply --3way --index
```

### 第二层：读卡器界面（要整条链，或者不做）

`3af999058` 的其余部分与 `fe5d80d11` 需要这条链先在 E 树里（旧→新）：

```
0876b2fe9  ops 接进读卡器与 MCP
a1377c52b  读卡器：头发切成四页＋共通页，眼睛切成目／瞳
ec04221d3  ops 与 edits 可以一起送
d5d3a8fa3  第三批：拉主色，套用时跑原作那个动作
2e3bdff29  四个髮色旗标上画面（MakeOwnToggle／OnToggled）
cb5459b1d  外挂栏位的键改成身分式
3af999058  材質貼圖页（其余部分）
fe5d80d11  材質貼圖页的偏移／缩放控件
```

这条链里 `ef1f80920`（软限制）、`562d60281`、`7dbeff78a`、`0f9c961e0`、`7f461218d`、`0bf68df3a`
是 **f-yvonne 的**，和这批交错但不是这批的依赖；**不要顺手带**，它们有自己的交接。

## 2. 不要带的

- **`d14ee8a85`、`d951217a5`、`b6fc31af7`、`fe5d80d11` 里 `Docs/READER_SHOT_PLAN_20261119.md` 的部分**：
  那是 F 的拍照窗口清单，E 用不到（`fe5d80d11` 要带的只有 `OKReaderScreen.cpp`）。
- **`Tools/unreal_slot.lua`（`9cf1bd7c7`）**：协调已经把它排进 e-fork-2 的窗口，e-cardload 明说不自己改，
  **别在这里重复带**，两边各带一次会在整合时打架。
- **`Tools/make_uv_check_texture.lua`／`Tools/testdata/uv_check_512.png`**：拍照素材，E 不需要。

## 3. 逐笔预演的结果（对着 `9ae0439c5`）

每一笔都是**单独**对着 E 的 HEAD 预演的，**不是累积的**；照顺序套时，后面那笔会看到前面那笔的结果，
所以实际衝突只会更少。预演方式：

```powershell
git merge-tree --write-tree --merge-base=<commit>^ 9ae0439c5 <commit>
```

| 提交 | 衝突档 | 哪一类 | 解法 |
|---|---|---|---|
| `7ecd947ff` | `Docs/CHARACTER_EDITOR_PARITY_HAIR_EYES.md` | modify/delete | **E 根本没有这个档** —— 整份取 F 的 |
| | `Docs/READER_UI_APPEARANCE_API.md` | content | 两边都加在档尾；**两边都留**，F 这段放在 E 那段后面 |
| | `Tools/ok-extract/src/appearance.rs` | content | `mod` 那一行与 dispatch：**两边都留**，顺序不影响 |
| `3af999058` | `Docs/CHARACTER_EDITOR_PARITY_HAIR_EYES.md` | modify/delete | 同上，整份取 F 的 |
| | `Docs/READER_UI_APPEARANCE_API.md` | content | 两边都留 |
| | `Source/OpenKoikatsu/OKCharacterController.h` | content | 两边都留（F 加的是贴图那组成员与两个方法） |
| | `Source/OpenKoikatsu/OKCharacterMCP.cpp` | content | 两边都留；注意 `Mutations` 那一行要**合并成一个集合**，不是两行各自保留 |
| | `Tools/ok-extract/src/appearance/textures.rs` | modify/delete | E 还没有这个档（第一层先带就没这个衝突） |
| `fe5d80d11` | `Docs/READER_SHOT_PLAN_20261119.md` | modify/delete | **不要带这个档**（见第 2 节） |
| | `Source/OpenKoikatsu/OKReaderScreen.cpp` | content | 要第二层整条链先在；只带这一笔会找不到上下文 |

`Docs/ERROR_LOG.md`（`bc2358774`）如果也要带：那是**典型的「两边都留」**——
AGENTS.md 写明两边合并时两边的列都保留，不要挑一边。

## 4. 套完的验收

```powershell
# Rust：贴图那支要过（卡片不进版控，所以是 ignored，要自己给卡）
cargo test --release --manifest-path .\Tools\ok-extract\Cargo.toml --lib textures -j 8
$env:OK_TEX_CARD="D:/XKoikatuSunshine/UserData/chara/female/Tohru.png"
cargo test --release --manifest-path .\Tools\ok-extract\Cargo.toml --lib textures::tests -j 8 -- --ignored --nocapture
# 全 lib：F 树上是 515 passed / 0 failed
cargo test --release --manifest-path .\Tools\ok-extract\Cargo.toml --lib -j 8
```

**该看到什么**：`Tohru.png` 第 0 套印出 **6 列**（脸 `DetailMask`、舌 `MainTex`、身体 `DetailMask`、
两层眼线 `MainTex`、饰品栏 30 的 `DetailMask`），来回测试（读 → 清除 → 指派 → 同 bytes 重用 id）全过。
做了第二层的话，再建置 `OpenKoikatsuEditor` 与 `OpenKoikatsu` 两个 Development 目标（共用程式的规矩），
并在读卡器看到「材質貼圖」分类。

**F 树这边还欠一笔验证**：`fe5d80d11`（偏移／缩放控件）**没有编译过**——`may-build` 一直是 `wait`。
套的人要知道：**那一笔在 F 树也还没编译验证过**，不要以为它在 F 上是绿的。
