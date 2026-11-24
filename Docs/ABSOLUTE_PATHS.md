# 絕對路徑盤點（2026-11-24，F）

**規則（使用者 2026-11-24）：不能假設所有絕對路徑都一樣。** 每台電腦放的位置都不一樣，這是要給上萬人用的程式；**程式裡不准寫死任何一台機器的路徑**。要找東西就相對於「已經知道的東西」去找：程式自己的資料夾、使用者指定的資料夾、或**卡片自己所在的位置**。

也不要去「猜」：不掃磁碟、不翻登錄檔、不列一串 `C:/`、`D:/`、`E:/` 候選。找不到就講清楚找不到，讓使用者指定。

## 這次掃到什麼

掃 `Source/`、`Plugins/`、`Tools/`、`Config/`、根目錄的 `*.cmd`（排除 `Intermediate/`、`Binaries/`、`target/`）裡所有 `磁碟機:/…` 形式的字串，共 825 處。分四類：

| 類別 | 處數 | 檔數 | 會不會影響使用者 |
|---|---:|---:|---|
| 出貨程式（`Source/`、`Plugins/`，非測試） | 29 | 11 | **會**——已全部處理，見下表 |
| 開發工具（`Tools/`） | 620 | 293 | 不出貨；多數是街區城市製作腳本與 Rust 測試 |
| 測試與 fixture | 69 | — | 不出貨 |
| 假路徑（`C:/a`、`X:/NoGame`、`C:/card.png`…） | 73 | — | 本來就不是真路徑 |
| 系統路徑（`C:/Windows`、`C:/Program Files`） | 34 | — | 作業系統自己的位置 |

## 出貨程式：原本寫死什麼，改成什麼

| 位置 | 原本 | 現在 |
|---|---|---|
| [`KKGameRoot.cpp`](../Plugins/KKSideloader/Source/KKSideloader/Private/KKGameRoot.cpp) 建構子 | `Root = "C:/portable/KoikatuSunshine"` | 空的。沒有內建遊戲目錄。 |
| [`Config/DefaultGame.ini`](../Config/DefaultGame.ini) | `Root=D:/KoikatuSunshine` | `Root=`（留空，旁邊寫明為什麼） |
| [`OKGallerySpeech.cpp`](../Source/OpenKoikatsu/OKGallerySpeech.cpp) `DefaultVoiceRoot` | 候選清單最後塞 `C:/portable/…`、`D:/…`、`E:/KoikatuSunshine/voice_extract`，找不到就回 `C:/portable/…` | 只有：`OK_VOICE_ROOT`、基礎庫的 `h/voice`、使用者指定的遊戲目錄、`Saved/voice_extract`。都沒有就是空的。 |
| [`KKPreviewActor.cpp`](../Plugins/KKUnityBundle/Source/KKUnityBundle/Private/KKPreviewActor.cpp) `ok.ShotPreview` 兩處 | `C:/portable/KoikatuSunshine` 與它底下的測試卡 | `OKShotGameRoot()`＝使用者指定的那個；卡片路徑相對於它 |
| [`OKCrowdScene.cpp`](../Source/OpenKoikatsu/OKCrowdScene.cpp) 百人房間建置指令 | `Root="C:/portable/KoikatuSunshine"` | 使用者指定的那個，`-GameRoot=` 仍可覆寫 |
| [`OKStudioVnge.cpp`](../Plugins/OKStudio/Source/OKStudio/Private/OKStudioVnge.cpp) 兩處 | 候選清單塞 `E:/Koikatu`、`D:/Koikatu/BepInEx/…`、`E:/Koikatu/UserData` | 只用使用者指定的遊戲目錄 |
| [`SOKStudioWindows.cpp`](../Plugins/OKStudio/Source/OKStudio/Private/SOKStudioWindows.cpp) Timeline 掃描 | `E:/Koikatu/BepInEx/plugins/Timeline/Single Files` | 相對於使用者指定的遊戲目錄 |
| [`SceneEditor.cmd`](../SceneEditor.cmd) | `if "%OK_GAME_ROOT%"=="" set "OK_GAME_ROOT=E:/Koikatu"` | 不設預設值；要用遊戲就自己設 `OK_GAME_ROOT` |

出貨程式剩下的 `磁碟機:/` 字串都不是真的要去開的路徑：

- `OKStreetSocialRules.h`（18 處 `C:/v/*.ogg`）：規則測試用的 JSON 字串。
- `OKGalleryWidget.cpp`、`OKGallerySpeech.cpp`、`KKGameRoot.cpp`、`OKHScene.cpp/.h`、`OKInteractionPairGameMode.h`、`OKBatchConvertCommandlet.h`：**註解**裡提到的路徑（講這次的事故、或舉例）。
- `OKReaderScreen.cpp`：設定頁輸入框的提示文字「例如 D:/KoikatuSunshine」——是給人看的例子，不是程式會去開的路徑。
- `OKCrowdQuality.cpp`：Blender 的預設安裝位置 `C:/Program Files/Blender Foundation/…`，是**第三方程式自己的安裝位置**，而且 `-CrowdBlender=` 可覆寫、檔案不在就直接回 false。
- `DreamGUI` 的 `D:/Work/…`、`I:/P/…`、`C:/Proj/…`：都在註解與測試 fixture 裡。

## 遊戲目錄現在是怎麼決定的

沒有內建值，也不去猜。[`KKChooseGameRoot`](../Plugins/KKSideloader/Source/KKSideloader/Public/KKGameRoot.h)：

1. **卡片自己所在的那個遊戲安裝**——從卡片的位置往上走，看到同時有 `abdata/`、`UserData/` 與 `KoikatsuSunshine.exe`／`Koikatu.exe` 就是它（`FKKLocalModIndex::BuildForCard`）。這不是猜：卡片在哪裡是事實。它底下要有 `mods/` 才算數。
2. 否則用**使用者在「設定 › 遊戲目錄」指定的那個**（存在自己的 `GameUserSettings.ini`，不是版控的 ini）。
3. 設了但那個資料夾現在沒有 `mods/`（改名、搬走、從別台機器帶過來的設定）→ 照開，但**在畫面上講明**，因為這時候卡片會安靜地少掉 zipmod，mod 的衣服就不對了。

每開一張卡都重算一次，所以**中途把遊戲資料夾改名也跟得上**。

## 開發工具（`Tools/`）：第二輪清完（2026-11-24）

第一輪只處理出貨程式。使用者接著說「盤點這個程式的全部絕對路徑，全部改成相對路徑」，所以 `Tools/` 也清了，並把檢查器的範圍擴到 **Rust（`ok-extract`、`ok-mod`、`ok-song`、`ok-game-mcp`、`character_mcp` 的 `src/`）、專案自己的 Lua（`Tools/**/*.lua`）與腳本庫（`Tools/lua/ok/`）**。

| 位置 | 原本 | 現在 |
|---|---|---|
| [`Tools/lua/ok/init.lua`](../Tools/lua/ok/init.lua) `ok.game_root()` | 一串寫死的候選：`C:/portable/KoikatuSunshine`、`D:/KoikatuSunshine`、`E:/KoikatuSunshine`、`E:/Koikatu`、`D:/Koikatu`；全找不到時 `game_root(true)` 回第一個（不存在的）值 | `OK_GAME_ROOT` → 讀卡器「設定 › 遊戲目錄」寫的 `GameUserSettings.ini` → `Config/DefaultGame.ini` → **這個 checkout 旁邊與同磁碟根目錄下名字帶 `koikat` 的資料夾**（每一個都要過 `is_game_root()`）。全找不到時 `game_root(true)` 回空字串，`game_root()` 報錯叫人指定。 |
| 同檔 `ok.game_path()` | 只把 `C:/portable/KoikatuSunshine/…` 這個前綴換掉 | 看路徑裡的 `abdata/`、`UserData/`、`mods/`、`BepInEx/`：前綴不是現在的安裝位置就換成現在的 |
| 同檔 `ok.engine_root()` | 最後退回 `E:/PhysX/UE5.8` | `OK_ENGINE_ROOT` → `Tools/engine.local.json` → **同磁碟探測**（`<磁碟>/UE5.8`、`<磁碟>/PhysX/UE5.8`、checkout 旁邊），都沒有就報錯 |
| [`ok-extract`](../Tools/ok-extract/src) 的 `mmdd.rs`、`lib.rs` | dump 寫到 `C:/portable/…`、場景 fixture 寫死 `E:/Koikatu`、`action` 資料夾重定位只認一台機器 | `OK_DUMP_DIR`／系統暫存、`repo_root()`（`CARGO_MANIFEST_DIR`）、`OK_MMDD_SEARCH_DIR` 與 `OK_GAME_ROOT` 底下搜；測試讀 `OK_MMDD_SCENE`／`OK_KKVMD_SCENE` |
| [`ok-song`](../Tools/ok-song/src/main.rs) | 7 個 `E:/…` 模型預設值 | `OK_SONG_MODELS`，否則 checkout 旁邊的 `Build/ok-song` |
| [`Tools/RuntimeLightProbe/Probe.cs`](../Tools/RuntimeLightProbe/Probe.cs) | 10 處 `C:/portable/OpenKoikatsu/…` | `OK_PROBE_OUT`，否則遊戲底下的 `OKProbe/`；測試卡路徑預設空的 |
| `Tools/EnginePatches/VsmQueueReuse/`、`apply_vsm_queue_reuse.lua`、`recover_paint_imports.lua` | 17 個 `D:/UE5.8/…` shader 路徑、`E:/PhysX/UE5.8` 預設 | 都接 `ok.engine_root()` |
| `anim_export/*`、`build_street_social_catalogue.lua`、街區活動產線那一批（`build_`／`prepare_`／`publish_`／`smooth_`／`verify_`／`write_street_activity_*.lua`，含內嵌的 PowerShell／Python 區塊）、`build_us_data.lua` | `C:/portable/OpenKoikatsu/…` 輸出與輸入位置 | `ok.root` 底下（內嵌區塊用 `@OKROOT@`／`@OKOUT@` 佔位符，執行前換掉） |
| `card_open_baseline.lua`、`package_studio_release.lua`、`run_crowd_*.lua`、`test_crowd_bone_packing.lua`、`prepare_street_activity_models.lua`、`make_ok_chara_card.lua`、`scan_kks_editor_shape.lua`、`export_street_animation_library.lua`、`ok_cards.lua` | `E:/OKPackage/TestCards-…`、`F:/HairDeckData`、`D:/OpenKoikatsuCrowd/DevelopmentStage`、`C:/Users/Damody/Downloads/…`、`E:/cargo-target/…`、`D:/XKoikatuSunshine/kks_decomp`、`D:/KoikatuSunshine` | 各自一個環境變數（`OK_TEST_CARDS`、`OK_HAIRDECK_DATA`、`OK_CROWD_STAGE`、`OK_TRIPO_DOWNLOADS`、`CARGO_TARGET_DIR`）或 `ok.root`／`ok.game_root()`；使用者自己的下載資料夾走 `USERPROFILE` |

檢查器的允許清單另外收了幾條，都寫了理由：**C／E／F 三個工作樹共用的 Unreal 名額檔**（`Tools/unreal_slot.lua` 與用它的兩支腳本——放各自的 `Saved/` 底下就互相看不到，三個樹會同時開 Unreal 把機器壓死）、第三方程式自己的安裝位置（Blender、MSVC）、作業系統位置，以及測試與 fixture 的假路徑。`Tools/tests/`、`test_*.lua`、`tests.rs`／`*_tests.rs`、`fixtures/`、`examples/` 整個跳過。

另一個專案（`StreetSocialCity`）的產線腳本（檔名帶 `street_city`，46 支約 145 處）照 AGENTS.md 不動。

## 怎麼重新盤點

```powershell
.\Tools\lua\lua.exe Tools\check_absolute_paths.lua
```

它看 `Source/`、`Plugins/`、`Config/*.ini`、根目錄的 `*.cmd`、Rust crate 的 `src/`、專案自己的 Lua（含 `Tools/lua/ok/`），排除 `*.spec.cpp`、`Tests/`、`Intermediate/`、`target/` 與測試／fixture。找到不在允許清單裡的 `磁碟機:/` 就非零結束碼。新加的寫死路徑會被它擋下來。
