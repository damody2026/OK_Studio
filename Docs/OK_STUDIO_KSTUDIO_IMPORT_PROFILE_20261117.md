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
