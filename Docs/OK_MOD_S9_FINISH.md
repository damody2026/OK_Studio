# OK Mod 工作項 9 收尾（F 組）：卡內資源 okMr、skin-decal、材質覆蓋存卡與退回材質、toon-post（2026-11-23）

第三波第 1 項。前半（B 層 pak、A 層、shader 家族、逐部件覆蓋、glass-shader）見 [OK_MOD_S9_MATERIALS.md](OK_MOD_S9_MATERIALS.md)；計畫 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §6.2、§6.11、§14.2。

## 提交

| 提交 | 內容 |
|---|---|
| `47447bebb` | `ok-extract`：`material.post_texture` 帶卡片路徑、先問再解碼，並計入開卡快取鍵 |
| `bd50db204` | `ok-mod`：卡內資源 okMr（每 mod 每卡 100 MiB 上限、存檔時清掉沒人引用的資源）與核心區段 `card_core` |
| `90e8615cd` | `ok-mod-host`：feature `frame` 預設開啟（同步點 B 已採納） |
| `62938899f` | 範例 mod `skin-decal`；測試 mod `material-hooks` 回應 `post_texture` 的 query |
| `d2f98ad4b`、`d1fef0e0a` | `ok-extract`：身體與臉的主貼圖也走 `post_texture`；卡片路徑帶到池執行緒（`CardScope::named`） |
| `f328b8c21` | `ok-mod`：缺 mod 清單不列核心區段 `ok.*`；skin-decal 畫上貼紙時記 log |
| `beda21c66` | `OKModding`：讀卡器的 mod 材質覆蓋存進卡片（`ok.materials`），沒裝 mod 時用卡內的 A 層退回材質 |
| `a49e4b4bf` | toon-post 的 B 層內容外掛 `Plugins/org_openkoikatsu_toon_post`（`M_OKToonPost`） |
| `c2384734b` | `ok-mod-studio`：`Ui::post_process`；範例 mod `toon-post` |
| （本回報同批） | `OKModding`：`-ModDevContent` 掛未 cook 的內容外掛；`OKStudioModBridge`：`post_process` 每幀驅動後處理材質 |

## 做了什麼

### 1. 卡內資源 okMr（宿主，`Tools/ok-mod/host/src/card.rs`）

- mod 的 `character_save` 回覆可以多帶 `resources_b64: {名稱: base64}`。宿主以內容 sha256（小寫十六進位）為鍵存進 okMr，和 C 的 `okmods.rs` `Resources` 同格式（zstd msgpack）。
- **引用方式**：區段資料（`data`）裡出現某個資源的雜湊字串，就算引用它。存檔時把所有區段都沒引用的資源清掉（GC），換貼紙之後舊圖不會留在卡裡。
- **上限**：每個 mod 每張卡 100 MiB（`resource_limit()`，環境變數 `OK_MOD_RESOURCE_LIMIT` 可覆寫，測試用）。超過時整筆存檔拒絕，回報錯誤，卡片不動。
- `card_load` 把該 mod 區段引用到的資源以 `section.resources {雜湊: base64}` 傳給 mod。
- SDK：`hooks::resource_hash`、`save_with_resources`、`ExtSection::resource`；feature `card-file` 提供 `hooks::CardMod::read(path, id)`，在 `post_texture` 這類只拿到卡片路徑的 hook 裡直接讀卡。
- **核心區段** `card_core {card, id, data_b64?}`：只接受 `ok.*`，給遊戲本身（不是 mod）讀寫 okMx；目前用在 `ok.materials`。缺 mod 清單略過 `ok.*`。

### 2. `material.post_texture` 的調整（`Tools/ok-extract`）

- **先問再解碼**：原本每張貼圖都解碼給訂閱者，有一個訂閱者時屬性工作要約 8 分鐘。改成先送不含像素的 payload（`"query": true`），只有回 `{"want": true}` 的 mod 才拿到像素。
- **卡片路徑**：payload 帶 `card`。路徑放在執行緒區域變數 `mod_forward::CardScope`，在 `ffi::session_open` 與 `extract_session` 設定，`session::native_parallel_work` 帶進池執行緒。
- **身體與臉**：`o_body_a` 與 `cf_O_face` 不經 `push.rs` 的 emit，改在 `extract.rs` 另外呼叫。
- 開卡快取鍵把 `material.post_texture` 算進「會改變開卡結果」的 hook。

### 3. 範例 mod skin-decal（`Tools/ok-mod/examples/skin-decal`）

- 讀卡器頁「貼紙／紋身」：目標（身體／臉）、內建圖（愛心、星星）、U、V、大小、旋轉、不透明度、色調。
- 存卡時圖片放進 okMr，區段資料記雜湊與擺放參數；開卡時在 `post_texture` 的 query 只對有貼紙的目標回 want，再把圖畫進主貼圖（依路徑、長度、mtime 快取卡片內容）。
- 目標模式：讀卡器、Studio、1 對 1、街區（都是開卡時合成，不需要各模式另外接）。

### 4. 讀卡器的材質覆蓋存卡與退回材質（`OKModContent.cpp`、`OKReaderMods.cpp`）

- `mod.material.apply` 記下覆蓋；讀卡器存卡時（`OKModContent::CardSaved`）寫成核心區段 `ok.materials`：`{"overrides":[{part, material, fallback:{id, parent, copy_source_values, scalars, vectors}}]}`。
- 開卡時（`CardLoaded`）套回覆蓋。mod 材質不存在（mod 沒裝或停用）時，用 `fallback` 建 A 層材質（`BuildMaterial("card", false, ...)`），log 寫「from the card's fallback」。

### 5. 範例 mod toon-post（`Tools/ok-mod/examples/toon-post`）

- B 層材質 `M_OKToonPost`：後處理（`BL_SCENE_COLOR_AFTER_TONEMAPPING`），Custom 節點內寫 HLSL——場景深度做 Sobel 描線、依亮度畫網點。參數 `LineWidth`、`LineStrength`、`DotSize`、`DotStrength`、`LineColor`。材質由編輯器 Python 產生（腳本只在 scratchpad，不進版控），`modkit_cook.lua --mod org_openkoikatsu_toon_post` cook 成 pak，`content_build = "1@5.8.4-0"`。pak 不進版控。
- Studio「畫面設定」頁：開關、線寬、線強度、網點大小、網點強度、線色；四個數值可做時間軸插值。設定是場景資料，存在 `.okscene` 的 `mods`。第一次打開開關時其他欄位補預設值（同一個復原步驟）；`reset` 指令設回預設。
- **Studio 端**（`OKStudioModBridge.cpp`）：面板回覆的 `post_process {material, enabled, scalars, colors}` 只接受 mod 自己的材質（`<mod id>/...`）。每幀從場景資料讀設定，建 MID 放進一個無邊界的 `APostProcessVolume`（Priority 1000），沒有開啟的就清空。每幀不呼叫 mod，所以復原、重做、時間軸播放都直接跟著資料走。
- **編輯器測試 B 層**（`-ModDevContent`）：編輯器載不了 cooked pak。加這個參數時，若專案 `Plugins/<content_root>/` 有該 mod 的內容外掛（`EnabledByDefault false`），以 `AddToPluginsList` 登記、`MountNewlyCreatedPlugin` 掛載，材質在編輯器現場編譯（`FinishCompilation`，只在 `WITH_EDITOR`）。打包遊戲照舊只走 pak。

## 驗證

自動測試：`cargo test`（`Tools/ok-mod`）全過，其中 `host/tests/resources.rs` 以真的 skin-decal 驗證：存愛心後 okMr 1 筆、卡片身分不變、重開把圖傳回 mod、換星星後愛心被清掉、超過上限被拒、清除貼紙後 okMr 移除、`card_core` 的設定／讀取／拒絕非 `ok.*`／移除。toon-post 單元測試 1 項。`ok-extract` 的 `changes_opens` 測試含 `material.post_texture`。

實機（F 引擎、編輯器 `-ModDev`）：

| 項目 | 結果 | 證據 |
|---|---|---|
| 讀卡器貼紙存卡（okMr 寫入） | 存卡後卡內 1 筆覆蓋＋1 個區段＋okMr，身分不變 | `F:\OpenKoikatsu\Saved\CharacterMCP\cards\貼紙測試_AF1DAAAB406A55E70623FC82DF583CE2.png` |
| 貼紙畫在臉上（重開卡） | 有 | `F:\OpenKoikatsu\Saved\OKControl\shots\58332-0001.png`；卡 `F:\OpenKoikatsu\Saved\CharacterMCP\cards\貼紙臉2_69AA64BC45CA1F024B68BD9E7C7300BD.png` |
| 材質覆蓋從卡片還原 | 有 | log「applied from the card」 |
| 移除 glass-shader 後開同一張卡 | 用卡內退回的 A 層材質 | `F:\OpenKoikatsu\Saved\OKControl\shots\71588-0001.png`，log「from the card's fallback」 |
| 不裝 skin-decal 另存 | skin-decal 區段、`ok.materials`、okMr 原樣保留，身分不變 | `F:\OpenKoikatsu\Saved\CharacterMCP\cards\貼紙無mod另存_1CDDB2784E04618D2E81768F88AFF309.png` |
| toon-post 在 Studio | `-ModDevContent` 掛上內容外掛、材質 ready；`reset` 後畫面出現描線與網點 | 前 `F:\OpenKoikatsu\Saved\OKControl\shots\toon-before.png`、後 `F:\OpenKoikatsu\Saved\OKControl\shots\toon-after.png` |
| toon-post 存場景再開 | 效果還在（設定在 `.okscene` 的 `mods`） | `F:\OpenKoikatsu\Saved\OKControl\shots\toon-reloaded.png`，場景 `F:\OpenKoikatsu\UserData\Studio\scene\toon_post_test.png`（本機） |
| 換回沒有 toon-post 資料的場景 | 效果關掉 | `F:\OpenKoikatsu\Saved\OKControl\shots\toon-off-again.png` |

建置：F 引擎 `OpenKoikatsu` Development 與 `OpenKoikatsuEditor` 都通過。toon-post 的 pak 在**打包遊戲**裡的實測沒做（需要 stage；由最後整合的 cook 一併確認）。

## 限制與待辦

- 讀卡器透過 MCP 的 `reader_call set` 改不了 mod 的控制項，測試改用 `ui_exec "mod.call {op:reader.control,...}"`。
- 貼紙要存卡並重開才看得到（合成在開卡時）；拖滑桿沒有即時預覽。
- 材質覆蓋清單在換服裝時清空；覆蓋只在讀卡器套用，Studio／街區／1 對 1 開卡還沒讀 `ok.materials`。
- 退回材質只有參數，沒有貼圖（mod 的 PNG 不放進卡）。
- 缺 mod 提示沒有列出「材質覆蓋用到的 mod」。
- toon-post 開啟時場景原本的景深、光暈看起來消失了（後處理材質讀 tonemap 後的畫面，再疊在高優先權 volume 上），還沒查原因；描線以深度差判斷，遠景樹葉會很密。
- 編輯器裡 `-ModDevContent` 掛上的外掛在程序結束前不卸載。
