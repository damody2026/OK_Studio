# 开卡性能优化（2026-11-17，E 树）

目标：让「开卡」（读卡器打开原作 KKS 卡与 OK 卡到可显示）实际变快。**前提：开卡的磁碟快取永久关闭**
（`70d8a21c7`，2026-10-28，多程序正确性；使用者 2026-11-17 再次确认「永远不要开开卡快取，想办法优化冷读取」），
所以**唯一的基准是「全新程序、无快取」的冷开**。

这份是独立的最终版，接手不必读任何对话。按时间顺序的过程记录（含被后续推翻的中间结论、各阶段的原始
分解数字）在 `Saved/Reports/card-open-perf-20261117/README.md`，**那是本机产物、不进版控**，可能被清掉；
需要长期保存的结论都在这份文件与 [ERROR_LOG.md](ERROR_LOG.md) 的 2026-11-17 各条里。

## 一、做了什么，各省多少

| # | 改动 | 提交 | 量到的收益 |
|---|---|---|---|
| 1 | 原作卡不再每张新卡重扫整棵 mods 树（`library_zip_memo` 的键按 archive、`fallback_candidates` 跳过不可能的候选、虚拟 mods 树遍历按 generation memo） | `ac498d042` `22f5ce43a` | `open_zip` 每张新卡 11739 → 146 次；**第二张新卡 −45.3%、第三张 −29.9%、三张合计 −28.2%** |
| 2 | 颜色遮罩烘焙按同值区段查表（256 项通道表取代逐 texel 的遮罩取样、tint 级联与 6 次 `powf`） | `9acc7e0e8` | **OK 卡第一张 1523.5 → 1267.3 ms（−16.8%）**；`mask bake: math` 1508.7 → 537.0 ms（−64%） |
| 3 | UE 侧启动时背景预载共用材质 parent（194 个 package，含 `_Outline`／`_Flat` 变体） | `ef829dc3a` | 第一张卡 `parent_load_ms` **151.7 → 60.0 ms（−92 ms）** |
| 4 | 基础 bundle 的解码搬进启动预热（`oo_base`／`bo_head_00`／`mm_base`） | `42716c068` | `load_base_bundles` 288.8 → 232.2 ms（−20%）；第一张卡 `extract_card_outfit TOTAL` −4.5% |
| 5 | 身体贴图合成链单次解码／编码，不再每步 PNG 往返 | `ac498d042` | `compose_body_texture` C001 214.4 → 181.5 ms（−15%）、klara 91.3 → 69.3 ms（−24%） |

**端到端**（同一执行档、全部开关开 vs 全部关、交错 3 轮取中位数，`OK_BENCH_PREWARM=1`）

原作 KKS 卡（一个进程依次开三张，`OK_GAME_ROOT=D:/KoikatuSunshine`）：

| | 改前 s | 改后 s | 变化 |
|---|---:|---:|---:|
| 第一张 Tohru（含进程初始化＋第一次全树遍历） | 5.01 | 4.40 | −12.2% |
| 第二张新卡 KK_091207 | 4.24 | 2.32 | **−45.3%** |
| 第三张新卡 Komazoku Megumin (2) | 4.81 | 3.37 | **−29.9%** |
| **合计** | **14.06** | **10.09** | **−28.2%** |

OK 卡四张合计 5.03 → 4.77（−5.2%；当时机器上有别组的 UnrealEditor，先前在干净机器上量到的 −2.2% 更可信）。
OK 卡另外单独拿到改动 2 的 −16.8%（第一张）。

**第一张卡 vs 第二张之后要分开看**：第一张的成本是进程初始化＋第一次全树遍历＋第一次解码基础 bundle，
能搬的已经搬进背景预热（改动 3、4）；**第二张之后才是读卡器里翻卡的实际体验，原作卡 −30~45%**。
OK 卡不读 mods 树，所以改动 1 对它几乎无效，它的收益来自改动 2。

## 二、做了之后回退或放弃的（和收益一样重要，省掉重走一遍）

| 项目 | 量到的事实 | 处置 |
|---|---|---|
| ④`read_strip_all_guids` 併集 | 走树与併集都已免费，成本全在 7300 次 `zip_memo`，其中 97% 是 `fallback_serving_id`。**但那 430 ms 是冷的 Windows 目录元数据**：短路掉它之后这一阶段只剩 18 ms，而且开关开与关都是 18 ms。一次开卡要读几百 MB bundle，会把目录元数据挤出快取，所以下一张卡的全树 stat 又回磁碟（暖 18 ms／被挤掉 250–400 ms／第一张 1.3–1.6 s）。三种做法（serving memo 改吃 `fallback_identity` token、`resolve_mod_archive` 线性扫描换查表、whole-tree pass 并行）交错 A/B 都拿不到 | 全部回退 |
| `fallback_serving_id` 能不能省掉 | 不能。`open_zip` 的 replay 分支对「library 记录了但本机没有模型」的档案本来就 `fallback_source` 去 stat，而 `real_zip_matches_recorded` 不符时会 `open_real` 直接读真档 —— manifest 真的可能来自真档，键不含 serving id 就会重现 2026-11-12 花火那个 bug | 保留现状 |
| ②`slot colour` 编解码融合 | math 占 88%（939 ms），PNG 往返只占 12%（decode 91 ms／encode 43 ms），拿不到原估的 80–120 ms | 放弃 |
| ②「以为烘焙把遮罩升采样到 4096²」 | **错的前提，而且是我自己写的注解造成的**。4096 是 mod／原作 Texture2D **自己的尺寸**，程式码没有 4096 常数也没有任何 resize；遮罩一直是逐输出 texel 按需读，没有放大后的缓冲区。那 939 ms 是「产生一张 4096² albedo」本身的逐 texel 成本 | 这条路径无事可改；结论已写进 `clothes_texture.rs` 的注解 |
| `GridSampler` 的 point 快路径 | 以为同尺寸时权重为 0 可以少读三个 texel；`OK_GRID_DIAG` 印出来才知道真实情况是 64²／512² 升采样到 4096²，权重本来就不是 0 | 整个回退，只留诊断 |
| ③`emit` 并行 | 整个 emit 阶段占三张卡总时间 2.2%（`memo_put` 19 ms＋`ctx.emit` 54 ms）。`memo_put` 搬不走（`view_memo` 是 thread-local）；`ctx.emit` 的每项工作是 `emit_part` 往 `session_parts` 后面 append，后面还有四处 `last_mut()` 改刚 append 的那一项 —— **顺序就是这个资料结构本身** | 不做，只留三个子计时 |
| `BUNDLE_CACHE`（`parse_bundle_cached` 的 thread_local）改程序共用 | `ParsedBundle` 有 18 个 `RefCell` 栏位且 `external_files` 装 `Rc<ExternalFile>` → `!Send + !Sync`，**型别上就放不进跨执行绪的 static**；还骑着「OK 卡资源包只记录真的跑过的查询」这条不变式（F 组 11-16 alice 那个 bug 的同一类）；`TEXTURE_CACHE_BYTES` 已经是每 bundle 192 MiB、每执行绪各一份。`native_workers_broadcast` 也救不了，因为 `base: head textures` 是在开卡那条执行绪上同步跑的 | 不做 |

## 三、量测方法与陷阱

**方法（这台机器上唯一可信的做法）**

1. **只量冷开**：全新程序、无快取。磁碟快取永久关闭，所以没有「暖」这个基准。
2. **同一个执行档＋环境变数开关＋交错＋同时段＋取中位数**。不同次执行之间的差异不算 A/B。
3. **正确性用 `--fresh-dump` 逐位元组比对** session bytes（不是整档雜湊，见 ERROR_LOG I-014）：
   OK 卡 28 个 dump（C001／C006／C049／klara／C050／megumin，含 override 与眼睛贴图）＋原作卡 21 个。
4. 一切建置与量测**最多 8 执行绪**（`cargo -j 8`、`-MaxParallelActions=8`、`RAYON_NUM_THREADS=8`）。
5. 会改变输出位元组的改动（例如缩小底图）**不适用**第 3 条，要改成目视＋平均 RGB 绝对差＋贴图记忆体。

**踩过的坑（都已写进 `Docs/ERROR_LOG.md`）**

- 把**两次独立执行**当成 A/B，报出 −17.6%，真实是 −2.2%。此后每个改动都带关闭开关。
- 自己留在背景的 `find` 吃掉 92% CPU，污染所有量测（1.4 s → 31.9 s）。这棵树上 `find` 很慢（45 GB 基础库），
  要用 Glob／grep 指定路径。另外**不要把 `cargo` 程序当成机器在忙** —— 那 18 个 idle 的
  `cargo run ok-game-mcp` 是常驻的 MCP server。
- 凭 SPOT 的次数与总时间推估就报结论（「136 次 `flip_png_v` 是串行的」），其实它们早就在并行的
  `PushCtx::transform` 里。**发现前提错了先把量测补上，再回头讲。**
- `ls -t Saved/Logs/CardReader/*.log | head -1` 拿到的是**上一次执行的日誌**，两种设定印出一样的数字，
  看起来像开关没生效。改成自己指定 `-abslog=`。
- kill 回圈用 `head -1`，留下 3 个 UnrealEditor（各约 9.5 GB），把 `f-sceneload` 卡在排队、那一轮数字全废。
  **一格 slot 只能有一个 Unreal 程序**；按命令列过滤 kill 并确认 `remaining: 0`。
- 把「精确名字查表」放在**关闭开关的前面**，关掉也享受到新路径 —— 假 A/B。
- **`VAR=$v` 搭配空值表示「不设」：`VAR=` 仍然会把变数设起来**，而开关是 `var_os(...).is_some()`，
  空值也算设了，于是**两边都是关的**。A/B 看起来「优化没用」，而且**那 49 个 dump 的「IDENTICAL」
  什么都没证明** —— 正确性闸门整个空转。是数字自相矛盾（单独跑 537 ms vs A/B 1000 ms）才抓到的。
  **每次 A/B 前先印一行确认开关真的在切。**

**留下的诊断**（都是环境变数开关，关掉时零成本）

| 变数 | 作用 |
|---|---|
| `OK_PROFILE=1` | 阶段计时。本轮新增 `batch: slot colour`／`slot finish`／`keys+memo`／`transform`／`emit`，`emit/memo_put`、`emit/regroup`、`emit/ctx.emit`，`base: head textures`、`base: head shape keys+md`、`base: body dynamics+colliders`，`mask bake: decode`／`math`／`encode` |
| `OK_GRID_DIAG=1` | 一次烘焙的贴图与遮罩尺寸、filter |
| `OK_TILE_DIAG=1` | 同值 texel 比例、`has_pat`，以及查表／逐 texel 两条路径各处理多少 texel |

**关闭开关**（做 A/B 用，也是出问题时的退路）：`OK_COARSE_ZIP_MEMO=1`、`OK_NO_ROOT_PROBE=1`、
`OK_NO_TREE_WALK_MEMO=1`、`OK_NO_CHAINED_BODY=1`、`OK_NO_BASE_BUNDLE_PREWARM=1`、`OK_NO_MASK_RUNS=1`、
`OK_NO_MATERIAL_PRELOAD=1`（UE 侧）。

## 四、还没做的

- **把底图缩小换速度与 VRAM**：等使用者决定。一张 4096² RGBA8 解码后 64 MiB，一张卡的重烘焙可以有 4 张
  （256 MiB），在 8 GB VRAM 的目标机上可疑；但**底图的细节不是遮罩给的**，缩的是底图自己那 4096² 的花纹、
  缝线、字样，不是只掉插值。会改变输出位元组，所以验证标准要换成目视（配件上色／头发上色／眼睛贴图／
  有 override 贴图的卡，正面＋近拍）＋改前后平均 RGB 绝对差＋贴图总量。
- **第一张卡 `base: head textures` 还有约 190–200 ms** 没搬走，原因见第二节 `BUNDLE_CACHE` 那一列
  （要搬得先重构 `ParsedBundle` 的内部可变性模型，代价远大于收益）。
- **转卡的 view 身分已改由树的内容决定**（`baf5cec10`，场景导入 5 张卡 wall 15 → 12 s）。要再往下拿，
  还有两处挡着，都查过了：
  1. `entries.rs` 的 `pack_memo` 键里有 `gamefs::fallback_generation()`，而它每次 `set_fallback` 都递增，
     所以光改 view 身分不会让它跨卡命中。要共用得先想清楚「同一棵树、不同卡包」在那层安不安全。
  2. `unity/references.rs` 的 `inventory_signature` 在严格开卡时直接回传 `"ok card:<identity>"` 当来源
     epoch，注解写着「the card's own pack has its identity」—— 它**预设身分是每张卡一个**。身分改成按树
     之后这个前提就不再成立；目前靠次序关卡与 5 张场景卡的实测确认没有问题，但再动这一带的人要先看它。
- **这项的收益和「子行程并行转卡」互相抵销**，定 worker 数之前要知道（实测 5 张场景卡）：

  | | wall | CPU 合计 |
  |---|---:|---:|
  | `OK_CARDS_WORKERS=5`（被 clamp 成 4），计数器 | 7.6 s | 17.8 s |
  | 同上，按树 | 7.2 s | 18.3 s |
  | `OK_CARDS_WORKERS=2`，计数器 | 8.6 s | 13.1 s |
  | `OK_CARDS_WORKERS=2`，**按树** | **7.8 s** | **11.8 s** |

  一张卡一个 worker 时每个 worker 都是新程序、各自重付一次暖机，这项的收益归零（开关两边差 0.4 s，在噪声内）；
  每个 worker 依序转 2–3 张时才有 −0.8 s wall／−1.3 s CPU。注意最后两列：**worker=2 加这项的 wall 和
  4 个 worker 差不多，CPU 却少三分之一** —— 使用者的目标机是 16 GB，每个 worker 自己扛一份库与快取，
  所以 worker 数不是愈多愈好。要两项的收益叠加，就让 worker 数小于卡数、每人依序转好几张。
- 转卡的次序迴归关卡：`Tools\ok_convert_order_check.lua`（小绯雪／Denia，2026-10-28 那个 bug）。动到
  `remake_ok_card` 的 view 身分、`with_zipmods_and`，或 `--oklib cards` 的 worker 配置，都要先跑它。
- `library_zip_memo` 里 `|| crate::okstrict::active().is_some()` 这道闸门：整合保住 F 组的 gap guard
  （`0dbce369f`）、两边验证都过之后，由我单独一步拿掉并重验（F 组的 repro
  `failed_remake_leaves_the_card_openable` 把关，我的 dump 不涵盖「开卡 → `ok_okcard_make` → 再开卡」）。

## 五、这一轮的提交（E 树 master，等整合时一起推）

| 提交 | 内容 |
|---|---|
| `ac498d042` | 原作卡每张新卡少重扫一次整棵 mods 树；身体贴图链不再每步 PNG 往返 |
| `22f5ce43a` | `library_zip_memo` 的新键只在非严格开卡用，严格开卡维持原键 |
| `ef829dc3a` | 读卡器启动时背景预载共用材质 parent（第一张卡 −92 ms）；batch 阶段计时 |
| `42716c068` | 基础 bundle 的解码搬进启动预热（第一张卡 −57 ms）；烘焙与基础阶段的子计时 |
| `4799bc55f` | 记下 `read_strip_all_guids` 的 430 ms 是冷的目录元数据，三种优化全部回退 |
| `0219ae37d` | `emit` 阶段的三个子计时；并行化拆开之后不值得，不做 |
| `6596702ef` | 写明 4096 是来源贴图自己的尺寸，这条烘焙路径没有升采样可以拿掉 |
| `9acc7e0e8` | 颜色遮罩烘焙按同值区段查表，第一张 OK 卡少约 250 ms |
| `dcc22a0c3` | 记录 `VAR=$v` 空值会让 A/B 与逐位元组比对一起失效 |

另外 `ec2953393` 是协调者合进 F 组 `18aee76f8`／`0dbce369f` 的合并提交。

每笔改程式码的提交都带「验证：」行：`cargo test --release -j 8 --lib`（507 passed／既有 3 failed，
`StreetHeroines` 目录权限，见 ERROR_LOG 2026-11-17）、`cargo check --release -j 8 --no-default-features`、
`OpenKoikatsu` 与 `OpenKoikatsuEditor` Win64 Development 连结成功。

