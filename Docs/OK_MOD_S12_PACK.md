# OK Mod 第二波（F 組）：讀卡器 ui_widgets 修正、Shift 跳過、工作項 12 打包與發布（2026-11-23）

協調者在同步點 A（F 快轉到 `2640da679`）之後交辦三件事。對應 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §9、§10 M5、§15.4 第 12 列，以及 [OK_MOD_S4_READER_PREREQ.md](OK_MOD_S4_READER_PREREQ.md) 回報的問題。

同步後先用 F:\UE5.8 建 `OpenKoikatsu` Development 與 `OpenKoikatsuEditor`，兩個都 `Result: Succeeded`（`Saved/ModKit/S6/sync-*.log`）。

## 1. 讀卡器 `ui_widgets`／`ui_set` 是空的（`OKGameControl.cpp`）

**原因**（比 C 的推測多一層）：DreamGUI 讀卡器把舊的 UMG 畫面留作「模型」。`OKGalleryWidget.cpp:1077` 設了三件事：

- 整個 widget `RenderOpacity 0`；
- `HitTestInvisible`；
- 內容根節點 `Collapsed`。

`OnScreen()` 沿父鏈遇到 Collapsed 就濾掉，而且這些控制項從沒建出 Slate，沒有幾何，所以全部被濾掉。

**修正**：

- 辨認「模型層」：使用者 widget 滿足 opacity 0、HitTestInvisible、根節點 Collapsed 三個條件。
- 模型層裡的控制項，判斷標準改成「畫面上有一個正在顯示的 DreamGUI 鏡像（`UOKDreamControl::Source`）指向它」。顯示要整條 DreamGUI 父鏈都 `GetShown()`。這和使用者此刻看得到、按得到的完全一致：換分頁、開抽屜，清單跟著變。
- 第一版只看 UMG 自己的可見旗標，結果只列出 7 個，漏掉 DreamGUI 照樣鏡像出來的收起面板，已放棄。
- 同時修掉一個**崩潰**：`/widgets` 對沒有 Slate 的 UMG 按鈕呼叫 `GetCachedWidget().ToSharedRef()`，觸發 SharedPointer `IsValid()` 斷言，整個讀卡器當掉。改成從 UMG 子樹取按鈕文字（`UmgText`）。

**實測**（讀卡器，`run_card_reader_development.lua <C050.png> -NoBuild -- -ModDev`）：

- 人物卡頁：`/widgets` 列出 14 個按鈕和 4 個控制項，與截圖逐一對得上。
  - 控制項：卡片來源、目錄、服裝、物理；
  - 按鈕：另存新檔、存成 KKS 卡、載入 3D、進入 1 對 1……；
  - 截圖：`F:\OpenKoikatsu\Saved\OKControl\shots\33628-0001.png`。
- 設定／介面頁：列出 C 新加的 pages.json 下拉 `OKGalleryWidget/PageItem_reader_lang_1`（繁中／简中／English）與「顯示字級」數字欄。
  - `ui_set` 設成 English：畫面標題變 `Language`，`Saved/CardReader/language.txt` 變 `en`（截圖 `33628-0004.png`）；
  - 再設回繁體中文：檔案回 `zh-TW`；
  - 「顯示字級」設 8 再設回 7，都成功。
- 按鈕：`/widget {"label":"＋  選擇動畫"}` 打開了「選擇動畫」抽屜（截圖 `33628-0006.png`）。之後清單多出抽屜裡的 5 個 bool、13 個 choice、5 個 number、2 個 text。
- 先前會崩潰的讀卡器 log：`F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-015726-21f03136.log`。

**沒驗**：

- C 測試頁上的 color 控制項沒逐一以 `ui_set` 寫入，只確認新種類會隨頁面出現；
- 卡片（Demo 的 C050）在 F 開不了（OK 卡缺資料），所以載卡後的身形滑桿頁沒實測。

## 2. 按住 Shift 跳過 mod

用 PowerShell 臨時注入按住 Shift（`keybd_event`，結束一定放開），再啟動讀卡器：

- log 只有 `LogOKMod: Display: Mods are off for this run (Shift held at start)`；
- 沒有 `Mod host`／`loaded Hello` 行；
- 控制檔沒有 `mods_dir`（`OKModStart` 直接返回）。

log：`F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-020452-12b457c0.log`。

## 3. 工作項 12：`ok-mod-pack`、profile、obsolete、熱重載

新 crate `Tools/ok-mod/pack`（lib＋CLI `ok-mod-pack`，相依 `ok-mod-host` 的 rlib 共用 manifest／resolve／DLL 檢查）：

| 指令 | 做什麼 |
|---|---|
| `pack <mod 資料夾> [--dll] [--out] [--skip-pak-check]` | 檢查 mod.toml；載入 DLL 做 ABI 版面、`panic = "unwind"`、內嵌 mod.toml 比對；檢查 `locale/*/*.toml` 的鍵都以 `mod.<id>.` 開頭；有 `content/*.pak` 時要求 `content_build`，並呼叫 `Tools/modkit_cook.lua --verify` 做白名單檢查。把 DLL 的 sha256 寫進 mod.toml，打成 `<id>-<version>.okmod`（zip：mod.toml、DLL、locale／assets／materials／content） |
| `install <.okmod>... --to <Mods> [--force]` | 遊戲在用這個 Mods 資料夾時拒絕；解壓時拒絕指到資料夾外的項目；驗證 sha256；在 obsolete 清單上就拒絕；同 id 只留最新，舊版移到 `Mods/.old/<資料夾>-<版本>-<時間>/` 並附 `RETIRED.txt` 說明原因；寫 `Mods/.installed.toml` |
| `verify <Mods> [--dry-run]` | obsolete 與較舊的重複 mod 移到 `.old`；每個 DLL 驗 sha256 與 ABI 版面；對五個模式各跑一次宿主的依賴解析，列出會載入的順序與不載入的原因；有問題時 exit 1 |
| `profile save <名> --mods <Mods>` | 把已裝的 mod 與版本寫成 `Mods/profiles/<名>.toml` |
| `profile apply <profile.toml> --mods <Mods> --packages <資料夾>` | 讓 Mods 剛好等於 profile：缺的或版本不同的從 `<id>-<version>.okmod` 安裝，不在 profile 的移到 `.old`；`.installed.toml` 記錄 profile 名 |

- **遊戲在用的判斷**：遊戲啟動時把 `mods_dir` 發布到 `Saved/OKControl/<pid>.json`（`OKModModes.cpp`），`install` 從 Mods 往上找控制檔，`mods_dir` 相同而且 UI 埠連得上，才算在用。
- **obsolete**：`Tools/ok-mod/obsolete.toml` 編進執行檔（目前列兩個測試 fixture），`Mods/obsolete.toml` 可再追加。
- **profile**：`Tools/ok-mod/profiles/starter.toml`、`full.toml`，目前都只有 `hello`，其餘範例出現時再加。
- **開發模式熱重載**：
  - 遊戲以 `-ModDev` 啟動時，宿主開 `dev`；`mod.reload <id>`（或 `okm_dispatch {"op":"reload"}`）把重建好的 DLL 複製成 `Mods/<id>/.reload/<名>-<時間>.dll` 再載入；
  - 舊版 `shutdown` 後留在記憶體（abi_stable 不卸載），新版重新 `create`／`register`／`Enabled`，新的主控台指令也會登記；
  - 沒有 `-ModDev` 時拒絕。

**熱重載沒有接續狀態**：計畫 §7.5 的 `save_state`／`restore_state` 要在 `ok-mod-api` 的 `ModInstance` 加方法，是 API 改動，照規則**沒做，等協調者決定**。

- 加法：在 `shutdown` 之後追加兩個 sabi_trait 方法，屬於 prefix 尾端擴充，舊 mod 不受影響；
- 宿主側：舊版給 `RVec<u8>`，新版接收；
- 目前重載後 mod 從頭開始（測試裡 `ping` 的計數歸 1）。

**實測**：

- `cargo test -j 8`（`Tools/ok-mod` 全 workspace）全部通過。
  - 宿主多了 `dev_mode_reload_swaps_in_a_fresh_copy`；
  - `ok-mod-pack` 的 5 個整合測試：
    - 打包內容含 sha256；
    - 安裝、重複安裝、舊版不覆蓋新版、`--force`、再升級；
    - obsolete 拒裝；
    - 篡改 DLL 被 sha256 擋下；
    - verify 的 dry-run 與實際移走、版面不符與缺依賴的報告；
    - starter profile 套用時把不在 profile 的 mod 移走，save 後再 apply 不變；
    - 假的遊戲控制檔＋監聽中的埠：install 被拒，`--force` 可裝，埠關閉後放行；
    - locale 鍵缺前綴、有 pak 沒 `content_build` 都拒絕打包。
- 實際遊戲（讀卡器 `-ModDev`）：
  - `mod.reload org.openkoikatsu.hello` 後 `ping` 從 `pong 1` 重新開始，log 有 `reloaded … from …\.reload\ok_hello-<時間>.dll`；
  - 同時在終端機用 release 版 `ok-mod-pack install … --to F:/OpenKoikatsu/Mods`，回 `a game (pid 33628) is using F:/OpenKoikatsu/Mods; close it first`，exit 2。
- F:\UE5.8：最後一次改完 `OKGameControl.cpp` 後重建 `OpenKoikatsuEditor`（`Saved/ModKit/S6/w4-editor.log`）與 `OpenKoikatsu`（`Saved/ModKit/S6/w5-game.log`），都 `Result: Succeeded`。

**沒驗**：

- **乾淨 stage 上用 `install` 裝 starter 與 full**（§10 M5 的驗收）：F 沒有街區 stage，只在暫存資料夾與 checkout 的 `Mods/` 做過。
- **帶 content pak 的 mod 走 `pack`**：要 ModKit 與 UnrealPak，這次只測了「缺 `content_build` 被拒」。
- **白名單檢查仍在 Lua**：`modkit_cook.lua --verify` 還沒移到 Rust，`ok-mod-pack` 是呼叫它，所以 mod 作者要有本倉庫的 checkout。
- **profile 的停用**：宿主還沒有讀 `Mods/profiles/`。profile 目前靠「Mods 裡只放 profile 裡的 mod」來生效，沒有「裝著但停用」的狀態。
