# 街區打包（給別人玩的版本）

日期：2026-11-08。

`Tools/package_street_social.lua` 把街區打包成一個資料夾（可再壓成 zip），拿到的人用 `StreetSocial.cmd` 啟動。

```powershell
# 先檢查，不複製
.\Tools\lua\lua.exe Tools\package_street_social.lua --out D:\StreetSocialPackage --check
# 打包，可加 zip；--stage 不給就用 Saved/StreetSocial/Build 最新的 stage
.\Tools\lua\lua.exe Tools\package_street_social.lua --out D:\StreetSocialPackage [--stage <X.stage>] [--zip D:\StreetSocial.zip]
```

## 包裡有什麼

| 內容 | 來源 |
|---|---|
| 遊戲 | stage 的 `Windows/`（引擎執行檔、遊戲執行檔、pak）。stage 指向 Content 的兩個 junction（`IndependentResources`、`KKPreview`）不複製，拿到的人第一次啟動時由啟動器自動建立 |
| 執行期 patch | `Saved/StreetSocial/Build/StreetDisplay30Phys.patch` |
| 啟動器與工具 | `StreetSocial.cmd`、`Tools/lua/`、`Tools/*.lua`、原作資料清單（還原用） |
| 已建置的工具 | `ok_rules.dll`、`ok_mind.dll`、`ok_story.dll`、`ok-extract.exe`（對方沒有 cargo） |
| 語音伺服器 | `Build/ok-tts`、`Build/ok-asr`（不含模型與 log；`--no-voice-servers` 可不放） |
| 街區資料 | `Content/IndependentResources` 裡 **git 有追蹤**的檔案 |
| 設定檔 | 新玩家用的 `Saved/StreetSocial/player.json`：內建錄音配音、本機辨識，**金鑰空白**（[玩家設定檔](API_KEYS.md)） |

**不放：** 原作與 mod 資料（`Tools/original_data_manifest.json` 列的檔案、`base_v1`、`KKPreview` 等）、角色卡、存檔、TTS 快取、本機的金鑰。

拿到的人要做的事：
1. 用自己的遊戲還原原作資料：`Tools\lua\lua.exe Tools\original_data.lua restore --game <遊戲資料夾>`，見 [SHARED_RESOURCES_SETUP](SHARED_RESOURCES_SETUP.md)。
2. 準備自己的角色卡，放在 `Saved/StreetSocial/heroines.json` 指到的位置。
3. 要用 AI 對話或雲端語音的話，在遊戲左上角「設定」填金鑰。

## 打包前的檢查（任一項不過就停止）

1. **pak 的內容**：用 UnrealPak 列出每個 pak。
   - 有原作資料轉出的資產 → 停止。
   - 有 git 沒追蹤的資產 → 停止，除非用 `--allow <資料夾>` 明確說明那是什麼。
   - cook 產生的檔案（AssetRegistry、Config、shader 庫）不算資產。
2. **金鑰**：找出這台機器上的金鑰，搜尋包裡每個文字檔，找到就停止。
   - 來源：各 `player.json`、舊的 `deepseek.json`／`api-keys.json`、環境變數 `DEEPSEEK_API_KEY`／`DASHSCOPE_API_KEY`。

## 目前的狀態（2026-11-08）

拿 C 組的 stage `nav1108n.stage`（大學城，pak 20 GB）跑 `--check`，結果是停止：

- pak 裡 cook 進了 18 個 `Content/Koikatsu/Data/*`（原作資料清單的 `unreal-catalog` 組：`DA_AnimationAndMouth`、`DT_animation_clips`、`DT_studio_catalog` 等）。要先讓 cook 不帶這些資產，才能打包。
- `Content/UniversityCity` 有 124,416 個資產沒進版控，需要確認來源後再決定能不能用 `--allow Content/UniversityCity` 放行。
- 這台機器上找到 2 把金鑰，包裡都沒有。
- 預估 4,645 個檔案、22.16 GB。

還沒實際複製出一份完整的包，也還沒在另一台機器上試玩過。

## 在開發機上試跑包（2026-11-14）

- 一律加 `-Sandbox <名稱> -NoCloud`，不呼叫雲端。
- 啟動器會把這台機器 `%LOCALAPPDATA%\OpenKoikatsu` 的金鑰補進包裡空白的 `Saved/StreetSocial/player.json`。試跑後要：
  1. 用 `street_player_settings.template()` 重寫包的 `player.json`（金鑰空白）；
  2. 刪掉試跑留下的檔案（`PACKAGE.json` 沒列的：`Saved/StreetSocial/Play-*`、`Sandbox`、`TTSCache`、`Saved/OKControl`、`base_v1/work`、語音伺服器 logs、stage 內的 `Saved`），以及 stage 裡指向包內 Content 的兩個 junction（只刪連結）；PowerShell 讀 `PACKAGE.json` 要加 `-Encoding UTF8`；
  3. 再搜一次本機金鑰（逐字搜整包含 pak，加 `sk-` 與 `"api_key"` 格式搜）。
- 2026-11-14 起包裡啟動（根目錄有 `PACKAGE.json`）不再讀寫 `%LOCALAPPDATA%\OpenKoikatsu` 的設定與金鑰，金鑰空白就保持空白。
- 壓縮前一定要先刪掉 stage 裡的兩個 junction（`Pack*.stage/Windows/OpenKoikatsu/Content/IndependentResources`、`KKPreview`，用 `cmd /c rmdir` 只刪連結）：7-Zip 會跟著 junction 把 `Content/IndependentResources` 再壓一次，51 GB 的包變成 80 GB。啟動器下次開遊戲時會再建回來。

## 讓 AI 透過 MCP 操作包（2026-11-17）

街區包與工作室包（`--studio`）都附兩個 MCP server 與 `WriteMcpConfig.cmd`：

| server | 檔案 | 做什麼 |
|---|---|---|
| `ok-game` | `Tools/ok-game-mcp/target/release/ok-game-mcp.exe` | 讀卡器（`reader_call`：開卡、參數、截圖、量測）、OK Studio（`studio_*`）、任何畫面（`ui_*`） |
| `openkoikatsu-character` | `Tools/character_mcp/bin/ok-character-mcp.exe` | 人物編輯器 31 個工具，含參考圖與依 2D 圖自動調身材（`reference_prepare`、`body_fit_start`），見 [人物編輯 MCP 使用說明](CHARACTER_EDITOR_MCP_USAGE.md) |

1. 解壓後執行一次 `WriteMcpConfig.cmd`（`Tools/write_mcp_config.lua`），在包的根目錄產生 `mcp.json`，裡面是這個資料夾的絕對路徑；包搬了位置要再執行一次。
2. 把 `mcp.json` 的 `mcpServers` 加到 AI 客戶端的 MCP 設定（Claude Code：放進專案的 `.mcp.json`）。
3. 執行 `CardReaderDevelopment.cmd` 開一張卡，再請 AI 照圖調整。兩個 server 都只走本機的控制通道與信箱（`Saved/OKControl`、`Saved/CharacterMCP`），不開網路埠。

打包版的身體由 GPU 顯示，跟隨用的 skeletal component 沒有 mesh object；`FOKPaintPose::Prepare` 以前一律要求它，打包版的 `body_masks`、`character_measure` 都失敗（「no readable CPU data」）。現在只有走引擎 CPU 蒙皮的路徑才需要。驗證：工作室包裡用胡桃的 OK 卡，以 `body_masks` 為目標、打亂身高與兩項體型後背景擬合，loss 0.146 → 0.0076，三個值回到原值附近。

## 帶上 mod（`--mods`，2026-11-23）

`--mods <放 .okmod 的資料夾>` 把 OK mod 框架一起打進包，說明見 [OK_STUDIO_MOD_PACKAGE.md](OK_STUDIO_MOD_PACKAGE.md)。打包前先把 mod 裝進 stage 的 `Mods/`（`.old/` 不會打進去）：

```powershell
.\Tools\lua\lua.exe Tools\pack_mod_examples.lua --out Saved/mod-integ/packages --content-from <ModKit 產物的 Mods 資料夾> --build
.\Tools\ok-mod\target\release\ok-mod-pack.exe profile apply Tools/ok-mod/profiles/full.toml --mods Saved/StreetSocial/Build/<stage>/Mods --packages Saved/mod-integ/packages
.\Tools\lua\lua.exe Tools\package_street_social.lua --studio --private --cards <卡片資料夾> --mods Saved/mod-integ/packages --readme Docs/OK_STUDIO_MOD_PACKAGE.md --out <包> --zip <包.zip>
```

包裡多出：
- `<stage>/Mods/`：已安裝的 mod；
- `ModPackages/`：`.okmod` 安裝包；
- `Tools/ok-mod/`：版控內的全部原始碼；
- `Plugins/org_openkoikatsu_*`：ModKit 內容外掛；
- `ok-mod-pack.exe`；
- `Docs/OK_MOD_*.md`。

`PACKAGE.json` 的 `mods` 是已安裝的 mod 數。

## 工作室包放哪些原作資料（2026-11-23）

發佈包沒有容量上限（使用者 2026-11-23）。`--studio --private` 預設只排除 `h-voices`、`studio-scenes`、`street-voices`、`street-dialogue`、`h-poses`：這些是街區或 1 對 1 才用的資料，或是含角色的範例場景。

Studio 音效道具（`base-sounds`，約 2.3 GB）與動作片段（`runtime-clips`，約 362 MB）以前為了壓在 10 GB 內被排除，現在會放進包。2026-11-23 的 `Studio-20261123-mods-full` 是 15.2 GB，zip 是 12.7 GB。
