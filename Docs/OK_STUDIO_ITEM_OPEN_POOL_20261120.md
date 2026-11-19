# OK Studio：道具开启改用常驻执行绪池（2026-11-20，F-sceneload）

## 题目是量出来的，不是猜的

`sync_loop_ms` 42.3 s 里 `sync_gate_ms` 是 11.6 s。先在闸门里加了五个字段
（`sync_gate_model_ms`、`sync_gate_key_ms`、`sync_gate_open_ms`、`sync_gate_spawn_ms`，
以及 `gate_calls`／`gate_capped`／`gate_keys`／`gate_opens`，提交 `dfcba22e0`），
一趟冷开（8806 物件／5867 道具／约 1200 个 Sync）的结果：

| 字段 | ms | 次数 | 每次 |
|---|---:|---:|---:|
| `sync_gate_ms` | 11 590 | — | — |
| └ `sync_gate_spawn_ms` | **11 036** | **5 867** | **1.88 ms** |
| └ `sync_gate_open_ms` 其余 | 102 | 5 867 | 17 µs |
| └ `sync_gate_key_ms` | 208 | 15 618 | 13 µs |
| └ `sync_gate_model_ms` | 15 | 15 618 | 1 µs |
| 其余（map 查找＋时钟） | ~230 | 4 323 726（其中 4 308 108 被上限挡掉） | ~50 ns |

**所以成本不在「每帧问每个道具一次」**——那 432 万次呼叫合计约 0.2 s。11 s 全在 5867 次
开启，每次 1.88 ms：`AsyncThread` 每次都 `FRunnableThread::Create` 一条 4 MB OS 执行绪，
而且会**等它真的开始跑**才返回（引擎 `Async.h:443`）；机器上同时有八个解码 worker，这一等
就是毫秒级。（11-18 量过的「读表本身」只占报数约 13%：两侧 `sync_ms` 差 3.56 s 对报了 27 s
的五个计时器，所以这 11 s 不是计时器自己。）

## 改法

`ok.Studio.ItemOpenPool`（默认 1）：第一个道具开启时建一个 `FQueuedThreadPool`，
`ItemOpensAhead()` 条执行绪、栈大小仍是 4 MB，之后每次开启用 `AsyncPool` 丢进去。
0 走回每个道具一条执行绪（只为了再量一次差）。开启的工作本身一字未改。

同时补一件之前漏的：`EndPlay` 原本只等角色的开启，不等道具的，道具开启可以活过它被开启的
那个 world。池必须在它上面的工作结束后才能销毁，所以现在先等 `PreparedItems` 再销毁池。

## 跑法与读法（跑之前写定）

四趟交错：`heavy-pool1-r1`、`heavy-pool0-r1`、`heavy-pool1-r2`、`heavy-pool0-r2`，
每趟一个新行程、`OK_NOCACHE=1`、同一张场景清单（`cold-heavy-only.txt`）：

```powershell
.\Tools\lua\lua.exe Saved\Reports\scene-load-f\profile-one.lua F:/OpenKoikatsu/Saved/Reports/scene-load-f/cold-heavy-only.txt heavy-pool1-r1
.\Tools\lua\lua.exe Saved\Reports\scene-load-f\profile-one.lua F:/OpenKoikatsu/Saved/Reports/scene-load-f/cold-heavy-only.txt heavy-pool0-r1 "ok.Studio.ItemOpenPool 0"
```

**有效性闸门**（任一条不过就是无效量测，不看数字决定放宽）：

1. 四趟都 `objects` 8806、`items` 5867。
2. 两侧 `gate_opens` 相差 2% 以内（做的是同一批开启）。
3. 关的那侧 `sync_gate_spawn_ms` ≥ 9 000；开的那侧 ≤ 1 500。
   （`-ExecCmds` 的 cvar 在第一个 Sync 之后才生效，所以关的那侧容许前几个开启走了池——
   这是量级判定，不是相等判定。）

**读法**：每侧两趟取中位数（两趟即平均），看 `ready_ms`、`sync_ms`、`sync_gate_ms`、
`sync_gate_spawn_ms`、`item_build_ms`、`item_open_worker_ms`。

- **保留池的条件**：`ready_ms` 改善 > 3%（低于门槛就是噪声，池不留）。
- 另看 `item_open_worker_ms` 有没有明显变大：池只有 8 条执行绪，若 worker 总时数暴增，
  表示池把原本并行的开启排成了队，那是倒退，即使 `ready_ms` 好看也要讲。

## 结果：闸门全过，池保留；但墙上时间只快 2.1%，因为瓶颈不在 game thread

四趟交错（`heavy-pool{1,0}-r{1,2}`，报告在 `F:\OpenKoikatsu\Saved\Reports\scene-load\`），
每侧两趟取平均：

| 字段 | pool 1 | pool 0 | |
|---|---:|---:|---|
| `ready_ms` | 61 786 | 63 093 | **−2.07%** |
| `sync_ms` | 35 036 | 42 642 | −17.8% |
| **`sync_gate_ms`** | **682** | **11 860** | **−94.3%** |
| └ `sync_gate_spawn_ms` | 45 | 11 308 | 目标那一段 |
| `item_build_ms` | 20 450 | 20 229 | +1.1% |
| `item_open_worker_ms` | 348 498 | 266 537 | **+30.8%**（见下） |
| `syncs` | 1 570 | 1 186 | +32%（game thread 空出来，帧跑得多） |
| 峰值 used GB | 7.27 | 7.21 | +0.06 GB；commit 9.12／9.13 一样 |

三条有效性闸门都过：四趟都 8806 物件／5867 道具；`gate_opens` 两侧都是 **5867**（完全相同）；
关的那侧 `sync_gate_spawn_ms` 11 142／11 473（≥ 9 000），开的那侧 42／48（≤ 1 500）。

### 判定：留。但我登记的那条「> 3% 才留」的理由是错的

登记时写的是「改善 < 3% 就当噪声，池不留」。这一轮的数字自己否掉了那个前提：
两侧**完全不重叠**——pool 1 是 61 838／61 733，pool 0 是 63 114／63 071，
同侧差 105 ms 与 43 ms，两侧差 1 276 ms 与 1 338 ms，是同侧散布的 12–30 倍，4/4 同向。
2.1% 在这台机器上是可复现的真差，不是噪声。门槛本来就该写成「两侧要分离」而不是一个百分比；
**这是读法写错，不是看到数字才放宽**，所以记在这里，下次别再用百分比当噪声判据。

### 为什么 game thread 省了 11.2 s，墙上只快 1.3 s

因为这个场景的载入**不是 game thread 绑住的**：`item_open_worker_ms` 266–348 s 分在 8 条
执行绪上，约等于每条 33–44 s 的墙上时间，而整趟 `ready_ms` 才 62 s。闸门原本每开一个道具就
让 game thread 等 1.88 ms，省掉之后 game thread 只是**问得更勤**（`syncs` +32%），开启本身
还是得等 worker。`item_open_worker_ms` 涨 30.8% 是同一件事的另一面：开启更早、重叠更多，
每个开启在争 CPU 的情况下自己变慢；上限没动（同时开启 8 个、已开未建 24 个），峰值记忆体也
没动（+0.06 GB），所以这不是把并行排成队，是重叠变密。

### 顺手修掉的一个寿命问题

`EndPlay` 原本只等角色的开启，不等道具的——道具开启可以活过它被开启的那个 world。
池不能在它上面的工作还在写 session 时销毁，所以现在先等 `PreparedItems` 全部结束再销毁池。

## 下一个人该动哪里

`ready_ms` 62 s 现在的瓶颈在 worker 侧的开启吞吐，不在 game thread：

- `item_spawn_ms` 17.4 s（UE spawn，必须在 game thread）仍是 `item_build_ms` 20.4 s 的大头，
  要动的是 `Plugins/KKUnityBundle` 的同型号共用 mesh／material——**三组共用，动之前要先讲**。
- `ok.Studio.ItemOpensAhead` 现在有了新的意义：game thread 不再是瓶颈，调高同时开启数**可能**
  有效（池是建池时按 `ItemOpensAhead()` 定大小的，调高 cvar 不会让已建的池长大，要重开）。
  但 11-17 量过记忆体：8 个同时开启峰值 16.5 GB，调高要先量峰值，不要只看 `ready_ms`。
