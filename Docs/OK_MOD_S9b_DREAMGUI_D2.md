# OK Mod 工作項 9b（F 組）：DreamGUI D2——mod 自帶 `.dui` 面板（2026-11-23）

第三波第 2 項。計畫 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §6.13；事前評估在 [OK_MOD_S9_MATERIALS.md](OK_MOD_S9_MATERIALS.md) 最後一節；格式說明在 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md) §4.1。

## 提交

| 提交 | 內容 |
|---|---|
| `ef826d58a` | 新外掛 `Plugins/OKModDream`：父類別 `UOKModDreamPanel`、`UOKModDreamBridge`（`Mod`）、`OKModDream::CheckPackage`／`Fingerprint`、commandlet `OKModDreamCheck`；`.uproject` 啟用 |
| `7cfef39cf` | `OKModding`：掛 pak 時檢查面板包（不合格整包拒絕）；`OKModContent::Widget`；只有面板的 pak 不要求 shader library |
| `8911de3c6` | 讀卡器：mod 頁的 `dui` 項；`OKReaderMods::Emit`（`ui.<id>.<事件>` 只送該 mod） |
| `19c206560` | `ok-mod-host`：`reader.ui` 的 `dui` 項一律標上頁面所屬的 mod |
| `4022481f8` | ModKit `modkit_cook.lua`：`DUI/*.dui` → 面板（lint、編兩次比對指紋、`OKModDreamCheck`） |
| `70d7b2884` | 範例 `dream-panel`（外掛 `Plugins/org_openkoikatsu_dream_panel` 的 `DUI/Panel.dui`＋Rust mod） |

## 設計

**為什麼另開 `OKModDream` 外掛**：ModKit 的 cook 主機是純內容專案，沒有遊戲模組。面板的父類別與檢查若放在遊戲模組或 `OKModding`（依賴 `KKUnityBundle`），主機載不到。`OKModDream` 只依賴 DreamGUI，主機把 `Plugins/DreamGUI`、`Plugins/OKModDream` junction 進去即可（用遊戲編輯器建好的 DLL）。

**`.dui` 只碰得到 `Mod`**（`UOKModDreamBridge`，面板的 `Transient` 屬性，讀卡器建面板後設定）：

- `Mod.Text(key)`（`FText`，給 `Text` 屬性）、`Mod.Number`、`Mod.Flag`：讀 `mod.<本 mod id>.<key>`；
- `Mod.Emit(event)`、`Mod.EmitValue(event, value)`：發 `ui.<本 mod id>.<event>`。
- mod id 由宿主標在頁面項目上，`.dui` 與 mod 都無法指定別的 mod。

**三層檢查**（§6.13「只有編譯器產物」）：

1. ModKit lint（Lua，逐行）：`class` 行、`use` 白名單、禁 `new`／`viewmodels`／`props`／`global`／`<->`。
2. `OKModDream::CheckPackage`（C++，ModKit 與遊戲共用）：
   - 只有一個 widget 類別 `WBP_<Name>_C`，父類別 `UOKModDreamPanel`；
   - 函式名只有編譯器的三種前綴與 dispatcher 簽章；
   - 每個物件與函式的位元組碼參照（`CollectBytecodeReferencedObjects`＋`FReferenceFinder`）：呼叫對象限自己、`Mod`、DreamGUI／UMG 控制項（非函式庫）、Math／String／`IsValid`／FieldNotification；參照的類別限允許的 `/Script/` 模組；內容限 mod 自己、`/DreamGUI/`、`/Engine/`。
   - 編輯器裡同一個包還有藍圖、EdGraph 節點、`SKEL_`／`REINST_` 類別，這些 cook 會去掉，檢查時略過（只在 `!RequiresCookedData()`）。
3. 重編一致：ModKit 刪掉舊資產、編譯、取指紋；再刪、再編、再取，兩次要相同。指紋含屬性、函式（名稱、參數、位元組碼長度與呼叫對象）、widget 樹的物件名與類別。不比位元組碼的原始位元組（記憶體裡含指標）。

遊戲掛 pak 時，有 widget 類別的包走第 2 層＋「mod 資料夾有 `ui/<Name>.dui`」，不合格整個 pak 拒絕；其他包照舊走材質白名單。

## 驗證

| 項目 | 結果 | 證據 |
|---|---|---|
| ModKit 編 dream-panel | lint、兩次編譯、檢查、指紋一致（`8898675b…`）、cook、pak verify 都過 | `F:\OpenKoikatsu\Saved\ModKit\org_openkoikatsu_dream_panel\Cook-20261123061336\` |
| cook 產物沒有本機路徑 | `WBP_Panel.uasset/.uexp` 找不到 `F:`、`Saved`、`.dui` 字串 | 同上 `verify.extract\` |
| 讀卡器顯示面板 | Mods › DreamGUI 面板：面板出現，綁定文字「還沒打招呼」「按了 0 次」 | `F:\OpenKoikatsu\Saved\OKControl\shots\97940-0003.png` |
| 按鈕回到 Rust | 按「打招呼」兩次 → 「你好！（第 2 次）」，頁面上的一般 label 也同步 | `F:\OpenKoikatsu\Saved\OKControl\shots\97940-0004.png` |
| 回覆照 §5 處理 | 按「歸零」→ 提示「打招呼次數歸零」、回到 0 | `F:\OpenKoikatsu\Saved\OKControl\shots\97940-0005.png` |
| 缺 `ui/Panel.dui` | 面板被拒（log `panel refused: ... no ui/Panel.dui`），頁面其他項目照常 | `F:\OpenKoikatsu\Saved\OKControl\shots\83992-0002.png` |

建置：F 引擎 `OpenKoikatsu` Development、`OpenKoikatsuEditor` 都通過；`cargo test --workspace`（`Tools/ok-mod`）全過。

讀卡器實測是編輯器版（`-ModDev -ModDevContent`，用 ModKit 編在外掛裡的未 cook 資產，走同一份檢查）。**打包遊戲掛 pak 的路徑沒有實測**，留給最後整合的 cook／stage。

## 限制與待辦

- 打包遊戲的 pak 路徑（掛載時的面板檢查、cooked 類別的 `CollectBytecodeReferencedObjects`）未實測。
- 面板只在讀卡器；Studio（Slate）、街區不在範圍。
- `Mod.Text` 等帶參數的綁定每幀讀（DreamGUI 對帶參數的呼叫一律每幀）；值本身是讀卡器快取的 `reader.values`，不會每幀問 mod。
- lint 是逐行字串比對，不是 `.dui` 的 AST；真正的保證是第 2 層的編譯後檢查。
- 面板高度用 `.dui` 根節點的 `SizeDelta` 或項目的 `height`；寬度跟欄寬。
- 檢查允許 DreamGUI／UMG 控制項類別上的任何非函式庫函式（setter、事件）；之後若 DreamGUI 加了能做事的控制項方法，要重看這份清單。
- 編輯器裡 `-ModDevContent` 要先跑過一次 ModKit（資產才會在外掛裡）；外掛的 `.gitignore` 不收這個資產。
