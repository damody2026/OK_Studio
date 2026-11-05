# 遊戲控制通道（所有模式常開）

所有模式啟動就開著控制通道，不需要任何參數，也沒有關閉開關。AI 操作遊戲一律走 `Tools/ok-game-mcp`（`.mcp.json` 的 `ok-game`）；MCP 沒載入的 session 用 `Tools/ok-game-mcp/target/release/ok-game-mcp.exe call <工具> '<JSON>'`。

## 架構

- **獨立執行緒**：`OKControl`（`Plugins/OKStudio/Source/OKStudio/Public/OKControl.h`）有一條自己的執行緒，負責所有 socket、信箱掃描與寫檔。遊戲主執行緒只在有請求時才執行 handler（每 tick 一次讀空佇列，時機和以前 Unreal HTTP 伺服器一樣在 tick 之間）。不用引擎的 `FHttpServerModule`，因為它在主執行緒上 tick socket。
- **只接本機程式**：只綁 127.0.0.1。通道都能跑主控台指令，所以帶 `Origin`、`Sec-Fetch-Site` 不是 `none`、`Host` 不是 127.0.0.1／localhost 的請求一律 403，瀏覽器裡的網頁打不進來。
- **實例登記**：每個程序寫 `Saved/OKControl/<pid>.json`（`port_ui`、`port_street`、`port_studio`、`port_pair`、`mailbox`、`map`、`mode`），結束時刪除；當掉留下的檔案由下一個程序或 MCP 依 pid 判斷略過。staged 版也寫到 checkout 的 `Saved/`（往上找 `Tools/ok_instance.lua`）。

## 通道與連接埠

| 通道 | 開在哪 | 預設埠 | 內容 |
|---|---|---|---|
| UI（`ui`） | 所有模式 | `port_base`+12 | `/state` `/widgets` `/widget` `/exec` `/screenshot` `/key` `/camera`，MCP 工具 `ui_*` |
| 街區（`street`） | StreetSocial | `port_base`+10 | [STREET_SOCIAL_GAME_MCP.md](STREET_SOCIAL_GAME_MCP.md)，`game_*` |
| Studio（`studio`） | SceneEditor、讀卡內開的 Studio | `port_base`+30 | [OK_STUDIO_MCP.md](OK_STUDIO_MCP.md)，`studio_*` |
| 1 對 1（`pair`） | `AOKInteractionPairGameMode` | `port_base`+11 | `/exec` `/reset` `/stats` `/pose`，`pair_call`、`ok-pair-mcp` |
| 讀卡信箱 | 讀卡（Studio 開著時照常；從讀卡進 1 對 1 時只回 `state`，場景面板用 `ui_*`） | `Saved/CharacterMCP`，第二個實例起 `Saved/CharacterMCP/instances/<pid>` | `reader_call`、`ok-character-mcp`（[使用說明](CHARACTER_EDITOR_MCP_USAGE.md)） |

`port_base` 在 `local-instance.json`，沒有時 47860（Studio 仍是 47890）。埠被占用就往上跳 100，所以同時開幾個都不會互撞，實際的埠看 `game_instances`。`-StreetSocialControlPort=`、`-StudioControlPort=`、`-PairControl=` 指定時只用那個埠。

## MCP 工具

| 工具 | 用途 |
|---|---|
| `game_instances` | 列出這個 checkout 所有執行中的遊戲（任何模式，手動開的也在內） |
| `game_select {pid}` | 同時開多個時指定操作哪一個，0 回到最新的 |
| `ui_state` | pid、地圖、GameMode、FPS、視窗、相機，以及模式補充的資料（百人房間：女角清單與位置） |
| `ui_widgets` | 畫面上能操作的一切：按鈕（`label`、`index`；純 Slate 按鈕也算）與控制項（`key`、`label`、`kind`、`value`、範圍、選項） |
| `ui_press {label, index}` | 按按鈕 |
| `ui_set {key 或 label, index, value}` | 改控制項，和人操作時觸發一樣的事件 |
| `ui_key {key, seconds}` | 當成玩家鍵盤按鍵 |
| `ui_camera {location, rotation}` | 放相機（百人房間；其他模式移動 view target） |
| `ui_exec {command}`、`ui_screenshot {ui}` | 主控台指令、截圖 |
| `reader_call {action, ...}` | 讀卡信箱：`state`、`cards`（卡片牆）、`select`、`load`、`parameters`、`get`、`set`、`reset`、`apply`、`controls`、`control_set`、`action`…；`session`／`revision` 自動帶 |
| `pair_call {path}` | 1 對 1 場景的文字通道 |

讀卡的 `parameters` 含 `shape.*`、`bone.*`、`physics.*`、`pregnancy.*`、`style.*`（角色風格的 `style` 與各比例參數）與卡片屬性。

## 不改變一般使用

- 通道開著本身不改變遊戲行為。街區的「滑鼠不鎖、視窗不在前景也讀輸入、跳過開始選單」只給 `-Control`（`-StreetSocialControl`）；沒帶 `-Control` 時，AI 第一次透過 `/key` 送鍵才進入前兩項（`OKVirtualInput().Driven`）。
- 讀卡不會因此自動載入角色：`-CharacterMCPCard=` 才會。
- pair 的 `/stats` 量測模式只在 `-PairControl` 或第一次 `/pose` 後才生效。
