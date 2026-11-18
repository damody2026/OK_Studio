# 遊戲控制通道（所有模式常開）

所有模式啟動就開著控制通道，不需要任何參數，也沒有關閉開關。AI 操作遊戲一律走 `Tools/ok-game-mcp`（`.mcp.json` 的 `ok-game`）；MCP 沒載入的 session 用 `Tools/ok-game-mcp/target/release/ok-game-mcp.exe call <工具> '<JSON>'`。

## 架構

- **獨立執行緒**：`OKControl`（`Plugins/OKStudio/Source/OKStudio/Public/OKControl.h`）有一條自己的執行緒，負責所有 socket、信箱掃描與寫檔。遊戲主執行緒只在有請求時才執行 handler（每 tick 一次讀空佇列，時機和以前 Unreal HTTP 伺服器一樣在 tick 之間）。不用引擎的 `FHttpServerModule`，因為它在主執行緒上 tick socket。
- **只接本機程式**：只綁 127.0.0.1。通道都能跑主控台指令，所以帶 `Origin`、`Sec-Fetch-Site` 不是 `none`、`Host` 不是 127.0.0.1／localhost 的請求一律 403，瀏覽器裡的網頁打不進來。
- **實例登記**：每個程序寫 `Saved/OKControl/<pid>.json`（`port_ui`、`port_street`、`port_studio`、`port_pair`、`mailbox`、`map`、`mode`），結束時刪除；當掉留下的檔案由下一個程序或 MCP 依 pid 判斷略過。staged 版也寫到 checkout 的 `Saved/`（往上找 `Tools/ok_instance.lua`）。

## 通道與連接埠

| 通道 | 開在哪 | 預設埠 | 內容 |
|---|---|---|---|
| UI（`ui`） | 所有模式 | `port_base`+12 | `/state` `/widgets` `/widget` `/exec` `/screenshot` `/key` `/type` `/mouse` `/focus` `/camera`，MCP 工具 `ui_*` |
| 街區（`street`） | StreetSocial | `port_base`+10 | [STREET_SOCIAL_GAME_MCP.md](STREET_SOCIAL_GAME_MCP.md)，`game_*` |
| Studio（`studio`） | SceneEditor、讀卡內開的 Studio | `port_base`+30 | [OK_STUDIO_MCP.md](OK_STUDIO_MCP.md)，`studio_*` |
| 1 對 1（`pair`） | `AOKInteractionPairGameMode` | `port_base`+11 | `/exec` `/reset` `/stats` `/pose`，`pair_call`、`ok-pair-mcp` |
| 讀卡信箱 | 讀卡（Studio 開著時照常；從讀卡進 1 對 1 時只回 `state`，場景面板用 `ui_*`） | `Saved/CharacterMCP`，第二個實例起 `Saved/CharacterMCP/instances/<pid>` | `reader_call`、`ok-character-mcp`（[使用說明](CHARACTER_EDITOR_MCP_USAGE.md)） |

`port_base` 在 `local-instance.json`，沒有時 47860（Studio 仍是 47890）。埠被占用就往上跳 100，所以同時開幾個都不會互撞，實際的埠看 `game_instances`。`-StreetSocialControlPort=`、`-StudioControlPort=`、`-PairControl=` 指定時只用那個埠。

## MCP 工具

MCP 沒載入的 session 用 `Tools/ok-game-mcp/target/release/ok-game-mcp.exe call <工具> '<JSON>'`。**從 Windows PowerShell 5.1 呼叫時，JSON 裡的雙引號要寫成 `\"`**：`ok-game-mcp.exe call ui_mouse '{\"x\":1400,\"y\":123}'`。PowerShell 5.1 傳參數給原生程式時會把 `"` 吃掉，沒跳脫時送出去的是壞 JSON（`key must be a string`）。Git Bash 和 Lua 的 `os.execute` 沒有這個問題。

**兩條輸入路徑要分清楚**：`ui_key` 直接送進 `PlayerController`，不經過任何 UI；`ui_type`／`ui_mouse` 走 Slate，和真鍵盤、真滑鼠一樣先給 UI（DreamGUI、UMG）再給遊戲。測 UI 收不收某個鍵、點不點得到某個控制項，只能用後者；用前者或系統按鍵模擬（SendKeys、SetCursorPos）測出來的現象不算數（2026-11-18 的誤判，見 `Docs/ERROR_LOG.md`）。

| 工具 | 用途 |
|---|---|
| `game_instances` | 列出這個 checkout 所有執行中的遊戲（任何模式，手動開的也在內） |
| `game_select {pid}` | 同時開多個時指定操作哪一個，0 回到最新的 |
| `ui_state` | pid、地圖、GameMode、FPS、視窗、相機，以及模式補充的資料（百人房間：女角清單與位置） |
| `ui_widgets` | 畫面上能操作的一切：按鈕（`label`、`index`；純 Slate 按鈕也算）與控制項（`key`、`label`、`kind`、`value`、範圍、選項） |
| `ui_press {label, index}` | 按按鈕 |
| `ui_set {key 或 label, index, value}` | 改控制項，和人操作時觸發一樣的事件 |
| `ui_key {key, seconds}` | 直接送進遊戲輸入（`APlayerController::InputKey`），**繞過所有 UI**：Slate、UMG、DreamGUI 都看不到，文字框有焦點時一樣會讓角色走動。測遊戲輸入用；要測 UI 收不收某個鍵，用 `ui_type` |
| `ui_type {text, keys, key, action, modifiers, enter}` | 像真鍵盤一樣走 Slate（`FSlateApplication` 的 key down／字元／key up）：先經過輸入前處理器（DreamGUI 的文字框），再到有焦點的控制項，最後才到遊戲。`text` 打字（帶按鍵事件，`keys=false` 只送字元）；`key` 按一個具名鍵（Enter、Tab、Escape、Left、BackSpace…），`action` 為 tap／down／up，`modifiers` 為 shift／ctrl／alt／cmd。回覆含 `handled` 與焦點（同 `ui_focus`）。實作在 `Source/OpenKoikatsu/OKSlateInput.*`，街區的 `/type` 也用它 |
| `ui_mouse {x, y, action, button, to_x, to_y, notches}` | 像真滑鼠一樣走 Slate（也會移動系統游標），座標是 `ui_screenshot` 圖上的像素：點得到 DreamGUI 控制項與 3D 視窗，不只 UMG 按鈕（`ui_press`）。`action`：click（預設）、double、down、up、move、drag、wheel |
| `ui_focus` | 鍵盤現在會送到哪裡：Slate 的焦點控制項與它往上的路徑、遊戲視窗有沒有焦點、按住的滑鼠鍵，以及正在編輯的 DreamGUI 文字框（它們比 Slate 焦點先拿到鍵） |
| `ui_camera {location, rotation}` | 放相機（百人房間；其他模式移動 view target） |
| `ui_exec {command}`、`ui_screenshot {ui}` | 主控台指令、截圖 |
| `reader_call {action, ...}` | 讀卡信箱：`state`、`cards`（卡片牆）、`select`、`load`、`parameters`、`get`、`set`、`reset`、`apply`、`controls`、`control_set`、`action`…；`session`／`revision` 自動帶 |
| `pair_call {path}` | 1 對 1 場景的文字通道 |

讀卡的 `parameters` 含 `shape.*`、`bone.*`、`physics.*`、`pregnancy.*`、`style.*`（角色風格的 `style` 與各比例參數）與卡片屬性。

## 卡住就強制關：逾時與強制結束（2026-11-19）

GPU 卡死（`DXGI_ERROR_DEVICE_HUNG`，2026-11-19 在讀卡器抓到一次）之後，行程還活著、通道還在聽，但永遠不會再回應——等它的工具會一直等下去，自動化跑一輪會看起來「還在跑」。所以每個等待都有期限，到了就**強制結束那一個行程**（`Tools/ok-game-mcp/src/watchdog.rs`）。

| 等什麼 | 預設 | 環境變數 | 逾時會做什麼 |
|---|---:|---|---|
| 單次呼叫（`ui_*`、`game_*` 的 HTTP 通道） | 60 s | `OK_MCP_TIMEOUT_CALL`，或 `OK_MCP_TIMEOUT` | 判定後強制結束 |
| 讀卡器信箱（`reader_call`） | 120 s（`state` 10 s） | `OK_MCP_TIMEOUT_READER`，或呼叫參數 `timeout_s` | 判定後強制結束 |
| 啟動等待（`reader_launch`、`game_launch`） | 300 s／街區照呼叫參數 | `OK_MCP_TIMEOUT_LAUNCH`，或 `timeout_s` | 結束剛啟動的那個 pid |
| 健康探測（判斷是「卡死」還是「只是慢」） | 3 s | `OK_MCP_TIMEOUT_HEALTH` | — |
| `studio_launch` | 120 s | `OK_MCP_TIMEOUT_LAUNCH` | 先解析出**真正的 OK Studio 行程**（先看誰佔著控制埠，再往啟動器的子孫裡找 `UnrealEditor*`／`OpenKoikatsu*`），結束它；真的找不到就在錯誤訊息裡明講「Studio 無逾時保護、沒有結束任何行程、請自己看」，不靜默略過 |
| 街區控制通道（`game_*` 的每一次呼叫） | 60 s | `OK_MCP_TIMEOUT_CALL` | 判定後強制結束 |
| OK Studio 的每一次呼叫（載入、存檔、截圖都走這裡） | 180 s | `OK_MCP_TIMEOUT_STUDIO` | 結束**佔著那個埠**的行程（`Get-NetTCPConnection`），一樣只關自己的 |

逾時之後的判斷順序：

1. `OK_MCP_KILL_ON_TIMEOUT=0` 就只回報不結束（要現場看卡死的畫面時用）。
2. **只關自己的**：pid 必須是呼叫端用 `OK_GAME_PID` 指名的，或這個 session 自己啟動的（`Saved/OKControl/launched/<pid>.json`）。別的 session 的遊戲一律不動，只回報。**絕不按視窗標題或執行檔名稱找行程**。
3. 再探一次 `/health`（3 s）：還會回應就代表「只是慢」，不結束，並叫你把期限調大。
4. 確認那個 pid 還是遊戲行程（`UnrealEditor*`／`OpenKoikatsu*`，避免 pid 被別人重用），才
   `Win32_Process.Terminate`——卡死的遊戲不可能禮貌關閉，要關的那條執行緒就是卡住的那條。

結束之後：錯誤訊息與 stderr 都寫明「等了幾秒、結束了哪個 pid、最後的狀況」，而且**不清任何證據**，遊戲的 log 與 Aftermath／D3D12 的 crash dump 原地保留（`Saved/Logs`、`Saved/Crashes`）。逾時一律是失敗：`ok-game-mcp call` 回非零結束碼，MCP 工具回錯誤，所以自動化那一輪會算失敗，不會看起來跑完。

> **改了 `ok-game-mcp` 之後，還在跑的舊 MCP server 行程仍然是舊版。** 它的執行檔被自己鎖住換不掉（`cargo build` 會停在 os error 5），所以那個 session 的呼叫**不會有逾時強制結束，也不會送 `X-OK-From`**——log 裡記成 `from unknown` 就是這個訊號：那是舊版工具送進來的。要生效就得重啟那個 MCP server（整合時統一做）；想先驗證可以用獨立的 target 目錄建置（`CARGO_TARGET_DIR=<暫存>`）再直接跑那支 exe。

### 手開的視窗：只告訴你，不替你關

`CardReaderDevelopment.cmd`／`StreetSocial.cmd` 開的是**使用者的視窗**，卡死了也不自動關——殺掉連畫面都來不及看。取而代之的是講清楚：啟動器印完 PID／Log 之後多一行 `Stuck? ... ok_hang_check.lua`，而 `Tools\lua\lua.exe Tools\ok_hang_check.lua` 會對每個登記中的遊戲（`Saved/OKControl/<pid>.json`）印一行「正常／沒有回應／行程已經不在」；沒有回應的那個另外印出 log 路徑、GPU crash dump 目錄（`Saved/Crashes`），以及要自己關的話該下的那一行 `ok-game-mcp call reader_stop '{"pid": N}'`。它只看不動，有卡住的回結束碼 2。

想讓終端一直盯著，啟動時加 `-Watch`（或自己跑 `ok_hang_check.lua --watch --pid=N [--every=秒]`）：每 10 秒探一次 `/health`，沒回應的那一刻就印上面那幾行、然後以 2 結束，**同樣不碰那個行程**。log 與 dump 請留著，那是查卡死原因的唯一證據。

實測（2026-11-19）：把自己的讀卡器用 `NtSuspendProcess` 凍住（和 GPU 卡死一樣，通道在但不回應），`OK_MCP_TIMEOUT_CALL=8` 下 `ui_exec` 等 8 s → 探 `/health` 失敗 → `ended it (Win32_Process.Terminate)`，行程確實消失、結束碼非零；沒凍住時同樣的短期限不會誤殺（呼叫 1 s 內就回來了）。

## 每一筆指令都記得是誰送的（2026-11-19）

一台機器上常有好幾個 session 各自開著遊戲，忘了設 `OK_GAME_PID` 的工具會打到別人的遊戲上（2026-11-19 就發生過：別的 session 的驗證腳本在量測中途對另一個讀卡器翻頁、開卡）。所以兩條通道都記來源：

- HTTP 通道（`ui_*`、`game_*`、`studio_*`）：呼叫端送 `X-OK-From: pid=<pid> <lane>`（`ok-game-mcp` 的
  `game::from_header`，lane 取自 `OK_MCP_FROM` 或 `OK_LANE`），遊戲在分派前記一行
  `OKControl <path> from <來源>`（`OKControl.cpp` 的 `Drain`）。`/health` 與 `/state` 會被輪詢，不記。
  沒有這個標頭的呼叫端記成 `unknown`。
- 讀卡器信箱（`reader_call`）：請求的 JSON 多一個 `from` 欄位（同樣的字串），讀卡器記在
  `Character MCP operation=… from=…`（`OKCharacterMCP.cpp`）。

查「這個操作是誰送的」就 grep log 的 `OKControl ` 或 `from=`。自己送指令時設 `OK_GAME_PID`
指定自己的遊戲，並且可以設 `OK_LANE`（或 `OK_MCP_FROM`）讓 log 直接看得出是哪個 session。

## 不改變一般使用

- 通道開著本身不改變遊戲行為。街區的「滑鼠不鎖、視窗不在前景也讀輸入、跳過開始選單」只給 `-Control`（`-StreetSocialControl`）；沒帶 `-Control` 時，AI 第一次透過 `/key` 送鍵才進入前兩項（`OKVirtualInput().Driven`）。
- 讀卡不會因此自動載入角色：`-CharacterMCPCard=` 才會。
- pair 的 `/stats` 量測模式只在 `-PairControl` 或第一次 `/pose` 後才生效。
