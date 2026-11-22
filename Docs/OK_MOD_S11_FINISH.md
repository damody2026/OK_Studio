# OK Mod 工作項 11 收尾（F 組）：idle-breath（Studio 多角色後姿勢）、1 對 1 的 boop／每幀呼叫（2026-11-23）

第三波第 3 項。前半見 [OK_MOD_S11_FRAME.md](OK_MOD_S11_FRAME.md)（每幀掛點、預算、boop 的 Rust 部分）；計畫 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §6.8、§14.2。

## 提交

| 提交 | 內容 |
|---|---|
| （本回報同批） | `KKUnityBundle`：`FOkSession::ModFrameId()`（mod 每幀呼叫的 `character`，即 Session 位址） |
| （同上） | OK Studio 橋接：mod 拿到的物件清單裡，顯示中的角色帶 `frame`（字串，u64 放不進 JSON 數字）；主控台 `OKStudio.ModSet <mod> <控制項> <物件|-1> [值]`（MCP 用 `ui_exec` 讀寫 mod 的面板列，和面板列一樣一個復原步驟） |
| （同上） | `ok-mod-studio`：`Object::frame` |
| （同上） | 範例 `Tools/ok-mod/examples/idle-breath`；full／starter profile |

## idle-breath

- **每幀**（`ok_mod_frame!`）：姿勢之後，`cf_j_spine02`、`cf_j_spine03` 繞局部 X、兩肩繞局部 Z 加一點旋轉，正弦（吸氣慢、吐氣快一點）。每個角色依 frame id 錯開相位，一群人不會同步呼吸。配對幀（`kind = 1`）不動。
- **逐角色設定**：場景資料 `{"enabled", "speed"（每分鐘次數）, "chars": {"<物件 id>": {"strength": 0..3}}}`。
  - 狀態頁一列「呼吸強度」（`bind: chars.{object}.strength`），也是逐物件的時間軸值；畫面設定頁有開關與速度。
  - 複製物件時設定跟到新 id（`objects_copied`）、刪除時移除、匯入場景時依新舊 id 對照搬過來。
- **物件 → 每幀呼叫的對照**：每幀函式只知道 `Frame::character`（Session 位址），Studio 的設定是以物件 id 存。橋接在物件清單帶上 `frame`，mod 每次被呼叫（含每 0.5 秒的 `sync` 計時器）就把「frame id → 強度」寫進 `static`。角色重建（換服裝、換卡）frame id 會變，最多半秒後跟上。

## 驗證

Studio（編輯器版，`-ModDev`），場景 `ill_ss_sample_00.okscene`（兩個角色，物件 1、4）。用 `studio_bones` 讀 `cf_j_neck`、`cf_j_shoulder_L` 的世界座標，每秒一次：

| 情況 | 結果 |
|---|---|
| 預設（強度 1） | 兩個角色的頸部同時在動，x 約 ±0.4～0.9 cm、z 約 ±0.1 cm，相位不同 |
| 角色 4 強度 0（`OKStudio.ModSet ... strength 4 0`） | 角色 4 完全不動（6 次讀數相同），角色 1 照常起伏 |
| 角色 4 強度 3 | 角色 4 的頸部 x 擺幅約 3 cm |
| 復原（`studio_undo`） | 強度回到 0 |
| 複製角色 4（強度 2.5） | 新物件 20 也是 2.5，且在動；先前複製的 19（當時 0）不動。三個角色並行 |

數據：`F:\OpenKoikatsu\Saved\OKControl\shots\idle-breath\probe-copies.txt`；畫面 `F:\OpenKoikatsu\Saved\OKControl\shots\idle-breath\studio-3chars.png`（靜態截圖看不出呼吸，主要證據是骨骼讀數）。

預算：整段只有一次超過 500 µs（1356 µs，log `frame took 1356 us`，是開場景後不久的一次，可能是剛載入的競爭），沒有連續 30 次，沒被停用。

**1 對 1**（讀卡器 → 進入 1 對 1 互動場景，站立愛撫播放中）：

- `mod.call {"op":"frame_stats"}`：boop 的呼叫數 374 → 717、0 次超時、最慢 228 µs；
- `mod.org.openkoikatsu.boop.poke all` 之後九尾整個甩開：`F:\OpenKoikatsu\Saved\OKControl\shots\65304-0001.png`（前）、`F:\OpenKoikatsu\Saved\OKControl\shots\65304-0002.png`（後）。

建置：F 引擎 `OpenKoikatsu` Development、`OpenKoikatsuEditor` 通過；`cargo test --workspace`（`Tools/ok-mod`）通過。

## 限制

- 後姿勢改骨骼的實機示範只有 Studio；讀卡器、街區沒裝 idle-breath（`targets = ["studio"]`）。
- frame id 對照靠 mod 被呼叫與 0.5 秒計時器，角色重建後最多半秒用預設強度。
- 時間軸播放逐物件強度時，mod 不會每幀被呼叫，靠計時器每 0.5 秒同步，所以強度變化是一段一段跟上的。
- 1 對 1 裡沒有確認 `kind = 1` 的配對幀與 `dt`（只看到呼叫數增加與外力生效）。
