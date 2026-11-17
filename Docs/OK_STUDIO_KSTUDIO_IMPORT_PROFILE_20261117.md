# 原作 KStudio 场景 PNG 导入的 14 s 花在哪（2026-11-17，f-sceneload，只量测不改）

样本：`D:/KoikatuSunshine/UserData/studio/scene/ill_ss_sample_03.png`（5 个角色）。
该场景冷开 22.7 s，其中 `load_call_ms` ≈ 14 s（62%）。本轮**没有改任何程式码**。

## 一句话

那 14 s 几乎全部是**逐角色转卡**，而转卡里每张卡都重新付一次「只跟库＋mods 树有关、跟卡无关」的
暖机（`lists+mods+guids` 约 1.3 s／卡）。`ORIGINAL_OPEN` 这个全域锁确实存在，
但它只是结果：转卡挂的是**行程全域**的 gamefs fallback，本来就不能两张卡同时挂。

## 量到的分布（CLI 重现，`OK_NOCACHE=1`、`RAYON_NUM_THREADS=8`）

| 阶段 | 毫秒 | 说明 |
|---|---:|---|
| `--oklib scene-export`（解析场景 PNG＋拆出 5 张 KKS 卡） | **206** | 可忽略 |
| 5 张卡在同一行程内依序转换（`OK_CARDS_IN_PROCESS=1`，等同 UE 走的路） | **12 255** | UE 内量到 11.0 s，对得上 |
| 其余（UE 侧走 JSON、写卡） | ~1 500 | 14 s − 12.3 s |

### 一张卡的 3.7 s 里面（`OK_PROFILE=1`，单独行程，27 次 open）

转一张卡会开 **27 次 session**：4 套服装＋23 个衣着状态变体（`okstrict.rs` 的 converting 一轮）。

| open | `extract_session TOTAL` |
|---|---:|
| 第 1 次（outfit 0） | **2 144 ms** |
| 第 2–27 次 | 每次 20–100 ms，合计约 1 290 ms |

第 1 次那 2 144 ms 的组成：

| 子阶段 | 第 1 次 | 第 2 次以后 |
|---|---:|---:|
| `lists+mods+guids` | **1 342 ms** | 1.0–1.8 ms |
| ↳ `lists: ramp` | 567 ms | 0.1–0.2 ms |
| ↳ `lists: mods catalog` | 490 ms | 0.0 ms |
| `load_base_bundles` | 194 ms | 1–3 ms |
| `clothes+hair+write` | 588 ms | 10–70 ms |

五张卡形状完全一样（第一次 open 2 024–2 165 ms，`lists+mods+guids` 1 274–1 410 ms，都是 27 次 open）。

**所以：5 × 约 1.5 s（lists＋base bundles）＝ 约 7.7 s，其中 4 张卡的 6.1 s 是重算同一份东西。**
那是 12.3 s 的一半。

## 为什么每张卡都重算：view identity 是个计数器

`oklib.rs:1904` 每转一张卡就铸一个新的 view 名字：

```rust
static CONVERSIONS: AtomicU64 = AtomicU64::new(0);
let view = format!("converting-{}-{}", std::process::id(), CONVERSIONS.fetch_add(1, Ordering::Relaxed));
```

这个名字同时当 `PackScope::identity` 与 `mods_identity`。下游：

- `extract.rs:40-43` 的 epoch 含 `mounted_pack_identity()`，名字一变就 `clear_entry_memo()`
  → `VIEW_MEMO` 整个清掉 → `load_mods_catalog_shared`（key 只有 `mods_dir`，`list.rs:666`）、
  `base_bundles_stage` 等全部 miss。
- `material_editor.rs:305` 的 ramp memo key 含 `mounted_pack_mods_identity()` → 也 miss，于是那 567 ms 的
  zipmod 读取每张卡重来一次（该处注解自己写着「reading its zipmod again on every open cost ~0.5 s」）。
- `entries.rs:97` 的 `pack_memo`（跨执行绪共享那份）key 是 `pack|fallback_generation|...`，`pack` 就是这个
  唯一名字，`fallback_generation` 也因为每次 `set_fallback` 递增 → 同样 miss。

唯一名字是**刻意的修正**，`oklib.rs:1901-1903` 的注解写了原因：卡自己的 zipmod 会加进库的树，
按 view 做 key 的 memo（树的 zip 清单、GUID 索引）不能用上一张卡的树回答下一张卡
（「小绯雪 converted after Denia lost its own zipmod's GUID, and with it its clothes」）。

缺口在于：它用的是**单调计数器**，而不是**树的内容**。场景导入正好是树完全相同的情形——5 张卡在同一个
目录、`OKTIME card_zipmods 0.00s (0 zips)`，没有任何卡自带 zipmod。`gamefs::fallback_identity()` 已经把
每个 archive 的路径／大小／时间和卡目录的列表都算进去了，拿它（而不是计数器）当 identity，树相同的卡
就能共用 memo，树不同的卡仍然各自重算，原本的正确性不受影响。

**这解释了为什么 E 组的 `ac498d042` 对这条路径没有可量到的差别**：那笔优化的 memo 也挂在
`mounted_pack_mods_identity()` 上，而转卡每张卡都换一个新的。

## 「疑似全域锁」查实

是 `oklib.rs:1708` 的 `static ORIGINAL_OPEN: Mutex<()>`，在 `with_zipmods_and`（`oklib.rs:1792`）
一进来就 lock，整张卡转完才放。它锁住的是**行程全域的来源视图**，不是某份资料：

| 全域状态 | 在哪 |
|---|---|
| `gamefs::FALLBACK`（`RwLock<Vec<Fallback>>`，决定哪些 zipmod 看得到） | `gamefs.rs:300 set_fallback` |
| `MOUNTED_PACK` / `MOUNTED_PACK_MODS` | `oklib.rs:1155/1163` |
| `gamefs::process_overlay()` 的录制 overlay | `gamefs.rs:267` |
| `tree_answers::begin(lib)`、`okstrict::set_read_only` | 行程全域 |

函式自己的注解就写着：*"Fallback directories are process-wide: one original card at a time."*
所以并行转卡不是「锁没调好」，是**两张卡需要两份互斥的行程全域 fallback**。
这也解释了之前 `ParallelFor` 4 并行 11.7 s 比依序 11.0 s 还慢——全部卡在同一把锁上，只多了竞争成本。

专案里已经有正解：`--oklib cards` 批次转卡**用子行程**做并行（`oklib.rs:2620-2650`，
`OK_CARDS_WORKERS` 默认硬体执行绪一半），注解写得很明白「Worker processes … each set up the library once」。
实测同一批 5 张卡：

| 方式 | 毫秒 |
|---|---:|
| 同一行程依序（UE 现在的做法） | 12 255 |
| 5 workers 子行程并行 | **7 849**（−36%，CPU 共 18.2 s） |

子行程只快 36% 而不是 5 倍，因为每个 worker 自己付一次 1.3 s 暖机，又互相抢磁碟。

## 两条可走的路（都还没动，等协调 session 决定）

| 路 | 预估 | 风险／地盘 |
|---|---|---|
| A. view identity 改成由树的内容（`fallback_identity`）决定，而不是计数器 | 上限约 −6 s／12.3 s（整场景 22.7 → 约 17 s），而且同行程、不必并行 | 改 `oklib.rs` 铸 view 的地方与 `extract.rs` 的 epoch，**是 e-cardload 的地盘**，而且踩到的正是那笔小绯雪正确性修正，必须有「树不同就不共用」的证明与对照 |
| B. UE 导入场景时改用子行程转卡（`--oklib cards` 已经有） | −36% | 不碰共用 Rust 路径，但要在 UE 侧 spawn 子行程、处理失败与进度，而且 A 做了以后 B 的收益会缩小 |

A 和 B 部分重叠，A 更根本。两条都不该在不通报的情况下动。

## 重现

```bash
# 1. 场景解析＋拆卡（206 ms）
ok-extract.exe D:/KoikatuSunshine --oklib scene-export ./Content/IndependentResources/base_v1 \
  'D:/KoikatuSunshine/UserData/studio/scene/ill_ss_sample_03.png' <卡目录>
# 2. 单卡阶段分布（stderr 才有 OK_PROFILE）
OK_NOCACHE=1 OK_PROFILE=1 OK_TIMING=1 ok-extract.exe D:/KoikatuSunshine --oklib card \
  ./Content/IndependentResources/base_v1 <卡目录>/char_1.kks.png <输出.png> 2> prof.err
# 3. 同行程依序 vs 子行程并行
OK_NOCACHE=1 OK_CARDS_IN_PROCESS=1 ok-extract.exe D:/KoikatuSunshine --oklib cards <库> <清单> <输出目录>
OK_NOCACHE=1 OK_CARDS_WORKERS=5  ok-extract.exe D:/KoikatuSunshine --oklib cards <库> <清单> <输出目录>
```

---

## 2026-11-17 下午：B 路落地的数字

`ok.Studio.ImportCardWorkers`（预设 -1＝硬体执行绪一半、上限 8；0＝原本的同行程依序）。
同一支 `UnrealEditor-Cmd` 启动器、`OK_NOCACHE=1`、同一张场景 PNG（`ill_ss_sample_03.png`，5 角色）：

| 设定 | 导入毫秒 |
|---|---:|
| `ImportCardWorkers 0`（旧路径） | 16 542；16 024 |
| 预设（8 个子行程） | **8 023**（worker 段 7.39 s；另一趟 7.05 s） |

**−51%**，五张卡全部成功。比 CLI 量到的 −36% 更多，因为父行程完全不必自己付一次转卡暖机。

**正确性**：`ImportCardWorkers 0` 与预设各导一次、各用 `OKStudio.ProfileSceneLoad` 傾印，
两份 `imp-w0_ill_ss_sample_03_2_pass0.json` 与 `imp-wN_..._pass0.json` **逐位元相同**
（16 个物件、`map`、`map_parts`、`map_error` 全等）。另外同一批 5 张卡「同行程依序」与
「每张卡一个行程」的 digest 与 parts 也完全相同（但 digest 不区分 outfit，所以那条证据不够，
傾印才是）。

**打包版没有这个加速**：`ok-extract.exe` 只在开发 checkout 的 `Tools/ok-extract/target/release/`
（或 `Tools/ok-extract/`）下；找不到就整个不启用，自动回到同行程依序。使用者给测试者的是打包版，
所以那边的导入时间仍然是 16 s 那一档。

## `Sync()` 的 39 s 在哪（量完了，和原先的推断不一样）

`koikatu_cs0003420_2.okscene`（8806 个物件，1 角色），冷开：

| | 毫秒 | 占 `Sync` |
|---|---:|---:|
| `ready_ms` 整趟 | 88 003 | |
| `Sync` 合计 | 63 406 | 100% |
| ↳ `Build()`（道具） | 22 564 | 36% |
| ↳ **`WorldTransform(Id)` ＋ `IsShown(Id)`** | **23 526** | **37%** |
| ↳ 写 transform／visibility | 1 979 | 3% |
| ↳ `SameContent` 深比较 | 516 | 0.8% |
| ↳ `WireRenderTextures` | 77 | 0.1% |
| ↳ 其余（`SyncMap`、各 kind 的 morph／材质比较、`Present` 集合、迴圈本身） | ~14 700 | 23% |

所以下一步该动的是 `WorldTransform`／`IsShown` —— 两者都为每个物件走一遍父链，每帧都走；
一个由上而下算一次全部世界变换的走法（或按 `PlaceGeneration` 记住）可以把那 23.5 s 大部分拿掉。
**深比较换 revision 的上限只有 0.5 s，不值得做**；我自己试的「不重写未变的 transform」也已回退
（见 `Docs/ERROR_LOG.md` 同日那笔：开 88 003 ms、关 87 573 ms，跳过只命中 1.6%）。

## 共用路径没被弄坏（在 `02888030e` ＋ 回退 `7ed584bd1` 上）

| | 结果 |
|---|---|
| 街区 `run_street_social_development.lua -Editor -SelfTest` | 10 位女角全部载入，`RequestExitWithStatus(0)`，只有既有那条 CommonUI routing error |
| 百人房间 `run_crowd_room100.lua --editor --count 20 --benchmark 5` | frame 2.48 ms、p95 3.10、p99 3.77、`frames_over_8_33_ms: 0`、`target_120_met: true` |
| `Tools/ok_convert_order_check.lua`（e-cardload 的次序关卡） | PASS：两张卡在同程序正序与反序下，开起来都和各自单独转的基准逐位元组相同 |

## `ImportCardWorkers` 的预设还没定，而且上限要压到 4

量 worker 数要等 e-cardload 的 `1a3a55dc2`（全域池吃 `OK_THREADS`／`RAYON_NUM_THREADS`）合进 F 树：
在那之前 `lib.rs` 的 `limit_threads()` 写死 `MAX_THREADS`，每个 worker 的裸 `par_iter` 都是 8 条
（8 个 worker ≈ 80 条），量到的 wall 是用「把机器吃光」换的。

另外**现在传的 `[threads] = max(2, 8/workers)` 本身守不住规矩**：8 个 worker 时 `8/8 = 1` 被抬成 2，
总共 16 条；而且抬不掉——`oklib.rs` 那三个具名池都是 `cpu_threads().clamp(2, 8)`，每个行程至少 2 条。
所以守住「最多 8 执行绪」的唯一办法是**把 worker 上限压到 4**（`4 × max(2, 8/4) = 8`，刚好）。
这和 e-cardload 的 CPU 论点（2–3 个 worker、每人依序转几张，两项收益才叠加）方向一致，但理由更硬：
不是比较省，是超过 4 个 worker 在现在的池结构下不可能守住。

最终预设＝量完 `2／3／4` 的 wall 与**导入期间峰值记忆体**（5 角色与 21 角色两个场景）之后定；
峰值若接近 16 GB 就往下压，即使 wall 慢一点。

## 量了才知道：worker 数的约束是记忆体，不是执行绪

协调 session 提醒「量之前先确认实际起了几条，不要只照公式推」。量完之后，**「最多 8 执行绪」这个框架在这条路径上
根本不是约束**：

| `[threads]` | 峰值 OS 执行绪 | wall | CPU | 峰值 working set |
|---|---:|---:|---:|---:|
| 不给（`OK_THREADS` 未设） | 130 | 7.04 s | 11.22 s | 2 370 MB |
| `2` | 119 | 7.63 s | 11.02 s | 2 352 MB |
| `1` | 119 | — | — | — |

**单一个转卡行程本来就跑 119–130 条 OS 执行绪**（GPU 烘焙的 D3D11／DXGI、各种池、zip 读取、Windows 自己的
worker），所以专案那条规矩讲的显然是 rayon 这类**运算**执行绪，不是 OS 执行绪；拿「8 个 worker × 8 条 = 64」
去推是用错了单位。而且 `OK_THREADS` 现在对 CPU 几乎没有影响（11.02 vs 11.22 s）——正是 e-cardload 查出的
`limit_threads()` 写死 `MAX_THREADS` 那个洞，`1a3a55dc2` 修了。

**真正的约束是记忆体。** `--oklib cards` 转同一批 5 张卡（`procs_seen` ＝ worker 数 ＋ 父行程）：

| worker 数 | wall | 峰值私有记忆体合计 | 峰值 working set 合计 |
|---:|---:|---:|---:|
| 1 | 18.86 s | 2.23 GB | 2.92 GB |
| 2 | 14.85 s | 3.74 GB | 5.20 GB |
| 4 | 12.47 s | 5.65 GB | **8.95 GB** |

每多一个 worker 约 ＋1.5 GB 私有／＋2 GB working set（次线性，因为同一批 bundle 的档案页是共用的）。
照这个斜率 8 个 worker 约 11 GB 私有／**约 17 GB working set** —— **使用者的目标机是 16 GB，而 UE 自己
还要好几 GB，所以 8 个 worker 不可行**，这和执行绪无关。

换来的时间：1 → 2 个 worker 买 4 s，2 → 4 个只再买 2.4 s，代价是多 3.75 GB working set。
所以**预设往 2 走、上限 4**；4 只适合大机器。最终值等 `1a3a55dc2` 合进来、在 UE 导入这条路上量
`= 2／3／4` 的 wall 与导入期间峰值记忆体（5 角色与 21 角色两个场景）之后定，量到的峰值直接写进 cvar 说明。

（系统层的 `\Memory\Committed Bytes` 在这台机器量不出来：基线 94 GB 还在随别组的工作变动，8 worker 那趟
甚至量到负的 delta。要量就量自己那些行程的私有／working set 合计。）

### 更正：`[threads]` 不是 no-op，但也不是单次量到的 0.8 s

上一节那张表是**单次**量测，e-cardload 指出它读起来有两个矛盾：「不给」比 4／2／1 快 0.8 s（12%），
而 4／2／1 之间**非单调**（4 条比 1 条还慢）—— 后者证明这个量测有噪声，所以前者的幅度不可信。
交错三轮重量（同一张卡，取中位数）：

| `[threads]` | wall 中位数 | 三趟 | CPU 中位数 |
|---|---:|---|---:|
| 不给（＝8） | **5.01 s** | 4.87, 5.01, 5.15 | 8.92 s |
| 4 | **5.15 s** | 5.06, 5.15, 5.21 | 8.27 s |
| 2 | **5.30 s** | 5.25, 5.30, 5.40 | 7.92 s |

这次**单调**，而且区间几乎不重叠（不给 4.87–5.15 vs 2 条 5.25–5.40）。所以：
- 把一个 worker 从 8 条收到 2 条，wall 多约 **6%**、CPU 省约 **11%**；
- 预设 2 个 worker 时每个拿 4 条，代价约 **3%**（5.15 vs 5.01）；
- 记忆体完全不随它变（2.34–2.38 GB），所以它不影响 worker 数的选择。

两个错都要记：我写「`[threads]` 是 no-op」是**低估**（有 0.29 s 的真实差），而单次量到的 0.8 s 是
**高估**（噪声）。另外这一轮的绝对值整体比上一节快（5.0 s vs 6.5–7.4 s），因为上一节量的时候
f-yvonne 的全跑正在吃机器 —— **跨时段的绝对值不能比，只能比同一轮之内交错取的中位数**。
