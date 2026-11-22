# OK Mod 工作項 11（F 組）：每幀掛點（後姿勢骨骼、物理外力、預算與停用），範例 boop 的 Rust 部分（2026-11-23）

對應 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §6.8、§14 的 `boop`，以及 [OK_MOD_HOOK_INVENTORY.md](OK_MOD_HOOK_INVENTORY.md) §3.3、§4。

這輪只動 F 擁有的檔案。`idle-breath`（Studio）照指示等同步點 B 之後。

## 提交

| 提交 | 內容 |
|---|---|
| `e277d001d` | ok-extract：`mod_frame.rs`（`ok_set_mod_frame`、後姿勢掛點、依角色存外力）；`session.rs` 掛點；`dbone.rs`／`dbone/ver02.rs` 的外力；`OKAnim.Profile` 加 `finish.mod` |
| `49ee3c5dc` | ok-mod：宿主 `frame.rs`（`okm_frame`、預算、停用、`frame_stats`／`frame_budget`）；SDK `frame.rs`（`Frame`、`ok_mod_frame!`）。兩者都是**預設關閉的 feature `frame`** |
| `f770f5b1b` | 範例 `Tools/ok-mod/examples/boop`（Rust 部分） |
| `789b0721e` | OKModding：宿主有 `okm_frame` 時交給開卡那份 ok-extract（`KKModMaterials::SetExtractFrame`） |

## 設計（**api 追加，請協調者決定**）

每幀不走 JSON Hook，也**不改 `ok-mod-api` 的型別**：

```text
ok-extract worker（每角色每幀）
  └─ okm_frame(OkModFrame*)          ← 遊戲以 ok_set_mod_frame 交給「開卡的那份」ok-extract
       └─ 每個啟用 mod 的 ok_mod_frame(OkModFrame*)   ← mod DLL 另外匯出的 C 函式
```

- **mod 端**：SDK 的 `ok_mod_frame!(fn)` 把 `fn(&mut Frame) -> bool`（true = 改了骨骼）匯出成 `#[no_mangle] extern "C" fn ok_mod_frame`，裡面 `catch_unwind`，panic 時回 `0x8000_0000`。
  - `Frame` 是 `#[repr(C)]` 結構的安全包裝，提供：
    - `kind`（0 單人、1 配對）、`character`（角色存活期間不變的 id）、`is_female`、`dt`、`time`；
    - 骨骼：`bones()`／`bones_mut()`（local TRS，Unity 空間）、`name(i)`／`find(name)`、`world(i)`／`world_pos(i)`（改之前的 world 矩陣）；
    - 物理外力：`push(Force { center, radius, force })`，每幀最多 32 個。
- **為什麼不用 abi_stable**：每幀要直接傳指標，不要 JSON。前一段已經實測到，在 `Event` 追加變體會讓舊 mod 被新宿主拒載（`too many variants`）；這個做法完全不碰 `OkMod`／`ModInstance` 的版面，舊 mod 照常載入，沒匯出 `ok_mod_frame` 就是不要幀。
- **宿主端**：
  - 載入 mod 時以 `RawLibrary::get(b"ok_mod_frame\0")` 找這個函式；
  - 啟用的 mod 依載入順序發布給 `okm_frame`，在 `enter_mode`、`reload`、`disable`、panic、`close` 時更新。
  - 用 null 呼叫 `okm_frame` 時回傳「幾個 mod 要幀」。ok-extract 先問；答 0 就不建 frame。
- **預算與停用**：
  - 每個 mod 每次呼叫都計時，預算預設 500 µs（§6.8）；
  - 超過時 log 警告，第一次與每第 100 次各一行；
  - 連續 30 次超過、或 panic，這個 mod 的幀函式本次執行不再呼叫，它的其他 hook 照常；
  - `{"op":"frame_stats"}` 回報呼叫數、超時數、最慢一次與是否停用；`{"op":"frame_budget","us"}` 可改預算。
- **執行緒**：幀函式在 ok-extract 的 worker 上呼叫，可能多個角色同時。所以它不是 `ModInstance` 的方法，要和 mod 共用的狀態只能放 `static`（atomics 或鎖）；boop 就是這個寫法。
- **ok-extract 端**（`Tools/ok-extract/src/mod_frame.rs`）：
  - 後姿勢掛點在 `finish_animator_transforms` 裡，ABM 之後、Studio IK 之前（盤點 §3.3 的位置）。
  - 單人與配對（`sample_paired_frame`，`kind = 1`）都經過這裡。配對時 `dt` 傳 0，因為配對的取樣沒有幀時間；mod 要自己計時。
  - 配對的位置在接觸求解之前。協調者提到「配對 `ffi.rs` 1598 之後」要不要再加一個點，留給你決定。
  - **外力**：frame 回的球形外力依角色存著（key 是 `px::current_group()`，也就是動態骨求解時的那個角色），在這幾處加到 `m_Force`：
    - `dbone.rs` 的 ordinary 動態骨（三處）與 standalone 路徑；
    - `dbone/ver02.rs` 的身體 Ver02（胸、臀）。
    - PhysX 路徑共用同一個 gravity 值，所以也吃得到。
    - 下一幀的回答會取代這一幀的；沒外力時每處只多一次 atomic load。

**要你決定的**：

1. 這個 C 函式的契約（`ok_mod_frame` 名稱、`OkModFrame` 版面、只追加欄位、`size` 欄位做版本）要不要當正式 API 0.1 的一部分；
2. host／SDK 的 `frame` feature 何時改成預設開；
3. 配對要不要另外在接觸求解之後再開一個點。

## 量測（獨占：`claim --need-gb 60`，機器上只有這一個 Unreal）

讀卡器（編輯器建置 `-game`）：

- 卡 `F:\OpenKoikatsu\Content\CharacterCards\CrowdAPNG\C011.png`，播「Demo：蹦跳」，約 80 FPS；
- Mods：glass-shader、hello、material-hooks；
- 數字是 `OKAnim.Profile` 每 20 秒窗口的**累計毫秒**。讀卡器沒有 `apply_total` 的幀數，所以比合計；20 秒約 1600 幀。

| 階段（20 秒合計 ms） | A：改動前（editor9） | B：改動後，沒有要幀的 mod | C：改動後，裝 boop（沒戳） |
|---|---|---|---|
| finish.abm | 20.08／20.18／20.30 | 19.66／19.61／19.54 | 20.22 |
| finish.shape | 150.7／146.8／141.6 | 147.5／144.8／145.3 | 150.7 |
| finish.body_dyn | 360.0／361.2／362.2 | 366.1／363.1／365.6 | 360.0 |
| finish.clothes | 1335／1346／1344 | 1382／1376／1371 | 1385 |
| finish.accessories | 14351／14426／14372 | 14383／14375／14362 | 14197 |
| **finish.mod** | — | **1.46／1.42／1.41** | **144.1** |

數據檔：`F:\OpenKoikatsu\Saved\ModKit\S9\frame-baseline-A.txt`、`F:\OpenKoikatsu\Saved\ModKit\S9\frame-B.txt`。

- **沒有要幀的 mod（B）**：掛點本身 20 秒 1.4 ms，約每幀 0.9 µs（一次 atomic load 加一次 null 詢問）。
  - 其他階段多在 A 的波動範圍內；`finish.clothes` 高了約 2.7%（1335～1346 → 1371～1382）。
  - 衣服鏈的外力檢查只是一次 atomic load；同一窗口裡、程式沒改到的 `clothes.colliders`（134～137 → 145～147）也高了，所以我判斷是兩次啟動之間的波動。
  - 但只有 A、B 各一次啟動，**不能排除**。要確認就把 A 再跑一次（要把 `e277d001d` 之前的二進位重編回來）。
  - 沒有宿主（`-NoMods` 或宿主沒有 `okm_frame`）時，連 null 詢問都沒有，只剩 atomic load。
- **裝了 boop（C）**：
  - 建 frame（全身約數百根骨骼的 local 與 world 矩陣）每幀約 75 µs，這是 ok-extract 的成本，不算進 mod 預算；
  - boop 自己沒戳時最慢 12 µs，戳的時候最慢 60 µs（`frame_stats`），預算 500 µs，0 次超時。
  - 75 µs 可以再降：world 矩陣改用骨架已算好的，或只給 mod 宣告要的骨骼。這輪沒做。

## 實測

- **外力**：`mod.org.openkoikatsu.boop.poke all`（力道調到 0.3）後，九尾、頭髮、外套整個甩向一側，約一秒後回復。
  - 截圖：`F:\OpenKoikatsu\Saved\OKControl\shots\77640-0001.png`（甩開）、`F:\OpenKoikatsu\Saved\OKControl\shots\77640-0002.png`（回復）。
  - 預設力道 0.02 的效果沒有截圖確認合不合適。
- **預算停用**：`{"op":"frame_budget","us":1}` 後戳一下。log 依序：
  - `frame took 45 us, budget 1 us (1 time(s) over)`；
  - `frame over budget 30 times in a row: not called again this session`。
  - `frame_stats` 顯示 `over_budget 30, stopped true`。
  - log：`F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-040537-77faf201.log`。
- **`input.pointer` hook**：boop 收得到（回 ok），但我手填的射線沒打中角色，畫面沒動。
- **測試**：
  - `cargo test`：`Tools/ok-mod` 全 workspace 通過；`-p ok-mod-host --features frame --test frame` 通過（實際載入 boop，戳一下後 `okm_frame` 推出胸部的外力，停用後不再推）；SDK 的 frame 測試通過。
  - `ok-extract` 的 `mod_frame` 測試通過：沒宿主不動、改骨骼寫回、外力範圍、角色區分。
- **建置**：`cargo check`（含 `--no-default-features`）通過；F:\UE5.8 的 `OpenKoikatsuEditor`（`F:\OpenKoikatsu\Saved\ModKit\S9\editor10.log`）與 `OpenKoikatsu`（`F:\OpenKoikatsu\Saved\ModKit\S9\game6.log`）都 `Result: Succeeded`。

## 沒做／沒驗

- **boop 的 UE 部分**：滑鼠掃過角色時送 `input.pointer`（射線與速度，Unity 世界座標）。這要 C++ 讀卡器端，不在「Rust 部分」裡，沒做。目前只能用 `poke` 指令或手送 hook。
- **後姿勢改骨骼沒有實機示範**：boop 只推外力。改骨骼的路徑只有 ok-extract 單元測試驗過寫回；實機要等 idle-breath。
- **Studio、1 對 1 沒實測**，只量了讀卡器。配對多角色並行（rayon）時，幀函式的並行安全只靠設計與單元測試。
- **GPU 動態骨路徑**（`GpuChainView` 把 `db.force` 交給 GPU）沒有加外力。
- **配對 `dt` 是 0**，見上。
- **用 Hook 之前 SDK 編的 mod**：照前一段的發現，要用新 SDK 重編才載得進新宿主（與這項無關，提醒一次）。
- `Mods/boop` 只裝在本機 `F:\OpenKoikatsu\Mods`（不進版控）；full profile 還沒加 boop，因為 frame feature 還沒定案。
