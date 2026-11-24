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

## 還沒處理的（`Tools/`，不出貨）

按根目錄分群，前幾大的是：

| 路徑群 | 處數 | 檔數 | 是什麼 |
|---|---:|---:|---|
| `C:/portable/OpenKoikatsu` | 256 | 196 | 街區城市製作腳本、probe 工具、各種一次性腳本 |
| `E:/StreetSocialCityProduction` | 59 | 40 | 街區城市的環境包（使用者的 StreetSocialCity 專案，不進版控） |
| `E:/PhysX` | 58 | 48 | 引擎路徑——**但這些多半是註解或預設值**，實際取得方式是 `Tools/ok_engine.lua`（`OK_ENGINE_ROOT` → `Tools/engine.local.json` → 預設） |
| `C:/Users/Damody` | 42 | 15 | Rust 測試用的暫存路徑、幾支腳本的輸出位置 |
| `E:/TTS`、`E:/OkSong`、`E:/HeartMuLa`、`F:/HairDeckData` | 24 | 11 | 模型與資料的本機位置，各自有環境變數可覆寫 |

`Tools/lua/ok/init.lua` 的 `ok.game_root()` 會依序試 `OK_GAME_ROOT` → `C:/portable/KoikatuSunshine` → `D:/KoikatuSunshine` → `E:/KoikatuSunshine` → `E:/Koikatu` → `D:/Koikatu`，**每一個都用 `is_game_root()` 驗過才採用**，所以不會指到不存在的地方；但 `game_root(true)` 在全部都找不到時會回 `C:/portable/KoikatuSunshine` 這個不存在的值。這是三台開發機共用的腳本庫，不出貨。

## 怎麼重新盤點

```powershell
.\Tools\lua\lua.exe Tools\check_absolute_paths.lua
```

它只看**會出貨的那些**（`Source/`、`Plugins/`，排除 `*.spec.cpp`、`Tests/`、`Intermediate/`），找到不在允許清單裡的 `磁碟機:/` 就非零結束碼。新加的寫死路徑會被它擋下來。
