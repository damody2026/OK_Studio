# OK Studio＋讀卡器＋Mod 發佈包（2026-11-23）

這個包有 OK Studio、讀卡器（`CardReaderDevelopment.cmd` 的完整人物編輯）與 OK mod 框架：19 個範例 mod 已裝好，另附全部 mod 原始碼、打包工具與作者文件。

**不含**街區遊戲本體與遊戲地圖：
- 沒有 `StreetSocial.cmd`；
- cook 只有 `/Engine/Maps/Entry` 與 `Template_Default`（`PACKAGE.json` 的 `maps_in_paks`）；
- 沒有語音伺服器。

由 `Tools/package_street_social.lua --studio --mods` 產生，打包方法見 [STREET_SOCIAL_PACKAGE.md](STREET_SOCIAL_PACKAGE.md)。

## 怎麼開

| 入口 | 做什麼 |
|---|---|
| `OKStudio.cmd` | OK Studio 場景編輯器。把場景檔拖到它上面可以直接開 |
| `CardReaderDevelopment.cmd` | 讀卡器：開 OK 卡、人物編輯、衣服卡、動作與表情。mod 頁在左下「Mods」 |
| `WriteMcpConfig.cmd` | 產生 `mcp.json`，讓 AI 客戶端透過 MCP 操作讀卡器與 Studio（[人物編輯 MCP](CHARACTER_EDITOR_MCP_USAGE.md)） |

兩個入口都跑包裡的打包版遊戲（`Saved/StreetSocial/Build/<stage>/`），不需要 Unreal 編輯器。

跳過所有 mod 的方法：
- 參數加 `-NoMods`；
- 或啟動時按住 Shift。

## Mod 在哪裡

| 位置 | 內容 |
|---|---|
| `Saved/StreetSocial/Build/<stage>/Mods/` | 已安裝的 mod，遊戲從這裡載入；`.installed.toml` 記錄裝了哪些版本 |
| `ModPackages/*.okmod` | 19 個範例的安裝包，可用 `ok-mod-pack` 重裝或換一組 |
| `Tools/ok-mod/` | 全部原始碼，見下表 |
| `Plugins/org_openkoikatsu_*` | 三個帶 shader 的範例（glass-shader、toon-post、dream-panel）的 ModKit 內容外掛原始檔 |
| `Tools/ok-mod/target/release/ok-mod-pack.exe` | 打包、安裝、驗證、profile 工具 |
| `Docs/OK_MOD_*.md` | 作者文件與設計紀錄 |

`Tools/ok-mod/` 的內容：
- `api`：跨 DLL 的型別；
- `sdk`：mod 作者用的巨集與包裝；
- `host`：宿主 `ok_mod_host.dll`；
- `pack`：`ok-mod-pack`；
- `studio`：Studio 的 SDK 擴充；
- `examples`、`fixtures`：範例與測試用 mod；
- `profiles`：`starter`、`full` 兩組。

各模式載入的 mod（`full` profile）：

| 模式 | mod |
|---|---|
| 讀卡器 | boop、dream-panel、glass-shader、hello、outfit-names、pair_counter、profile、random-chara、skin-decal、subtitles、ui-sample |
| OK Studio | boop、glass-shader、hello、idle-breath、light_rig、object_hotkeys、scene_notes、skin-decal、studio_autosave、timeline_flow、toon-post |
| 轉卡（ok-extract） | hello、profile |

`birthday`、`pair_counter` 的街區／1 對 1 部分在這個包裡用不到（沒有街區），它們的程式仍在原始碼裡。

### ok-mod-pack 常用指令

在包的根目錄（PowerShell）執行。下面的 `<stage>` 換成 `Saved\StreetSocial\Build\` 底下實際的 stage 資料夾名稱。

```powershell
# 看各模式會載入哪些 mod（不開遊戲）
.\Tools\ok-mod\target\release\ok-mod-pack.exe verify .\Saved\StreetSocial\Build\<stage>\Mods
# 換成入門組（6 個 mod）
.\Tools\ok-mod\target\release\ok-mod-pack.exe profile apply .\Tools\ok-mod\profiles\starter.toml --mods .\Saved\StreetSocial\Build\<stage>\Mods --packages .\ModPackages
# 裝回全部
.\Tools\ok-mod\target\release\ok-mod-pack.exe profile apply .\Tools\ok-mod\profiles\full.toml --mods .\Saved\StreetSocial\Build\<stage>\Mods --packages .\ModPackages
```

遊戲開著時 `install` 會拒絕，先關掉遊戲。

## 寫自己的 mod

1. 讀 [OK_MOD_AUTHORING.md](OK_MOD_AUTHORING.md)，內容依序是：
   - 產生範本；
   - 範本內容；
   - 建置、打包、安裝；
   - 開發迴圈與熱重載；
   - 範例對照。
2. 要的環境：
   - Rust（MSVC 工具鏈）；
   - mod 的 `Cargo.toml` 必須是 `panic = "unwind"`，範本已設好。
3. 每個模式能接的掛點與 payload 見 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md)。
4. 整體設計與規則見 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md)：
   - §2 硬性原則；
   - §6 API 面；
   - §7 ABI 與版本規則；
   - §7.6 實作後定下的規則：新功能一律走 `Event::Hook`，每幀呼叫走 `ok_mod_frame`。
5. 範例程式就是最好的參考：
   - `Tools/ok-mod/examples/hello`：最小骨架、設定、指令、熱鍵；
   - `profile`：卡片資料、轉卡、讀卡 UI 一條龍；
   - Studio 範例：`scene-notes`、`timeline-flow`、`light-rig`。

### 限制

- **程式只能是 Rust DLL**：不能改寫遊戲，只能用宣告好的掛點。
- **帶 shader 的 mod**：
  - 要用 ModKit（同一個引擎與 OpenKoikatsu 原始碼）cook pak，指令是 `Tools/modkit_cook.lua`；
  - pak 綁定遊戲建置（`mod.toml` 的 `content_build`），換了版本的遊戲要重新 cook。
- **安全**：裝 mod 等於信任作者，DLL 是原生碼，沒有沙箱。

## 生成頭髮與影片匯入

- **參考圖生成頭髮（HairDeck）**：裝好即用。
  - 權重放在包根目錄的 `HairDeckData/`，`Tools/ok-hairdeck` 是不需要 CUDA 的 CPU 版，生成一次約 40 秒。
  - 讀卡器、OK Studio 與配種的頭髮混合都用它。
  - 權重的授權：HairDeck 是 Apache-2.0；其中的 DINOv3 依 Meta 的 DINOv3 License 再散布。全文與清單在 `Licenses/`（`THIRD_PARTY.md`）。
- **影片匯入**：要**自備權重**，包裡沒有。
  - SMPL-X 不允許再散布，GVHMR 只限非商業用途。
  - 怎麼取得、放在哪裡（`GVHMR\checkpoints\`，或用環境變數 `OK_GVHMR_MODELS` 指定），見 [VIDEO_WEIGHTS.md](VIDEO_WEIGHTS.md)。
  - 沒放好時，面板會直接說明要自備權重。

## 只更新程式（程式包）

完整包約 36 GB，其中程式只有約 1.4 GB，其餘是資源（從原作轉出的基礎庫、動作、角色卡、頭髮權重）。資源沒有變時，只要下載**程式包**（`Studio-<日期>-program-<x>.zip`，`PACKAGE.json` 的 `kind` 是 `program`），疊在已經裝好的完整包上。哪些算程式、哪些算資源，見 [PROGRAM_ONLY_UPDATE_PLAN.md](PROGRAM_ONLY_UPDATE_PLAN.md) 第 1 節。

### 安裝步驟

1. **先關掉包裡在跑的程式**，否則覆蓋會失敗（檔案被占用）：
   - 讀卡器與 OK Studio 的遊戲視窗，以及開著它們的主控台視窗；
   - AI 客戶端（Claude Desktop、Claude Code 等）裡用 `WriteMcpConfig.cmd` 設定的 MCP server：`ok-game-mcp.exe`、`ok-character-mcp.exe`。關掉客戶端，或在它的 MCP 設定裡停用；
   - 工作管理員裡若還有 `ok-extract.exe`、`ok-hairdeck.exe`、`ok-video.exe`，等它們跑完或結束它們。
2. 把程式包的 zip **解壓到原本的安裝資料夾**（例如 `E:\OKPackage\Studio-20261124-release-e\`），遇到同名檔一律覆蓋。
   - 這只會換掉 `Tools\`、啟動檔、`Config\`、`Docs\`、`ModPackages\` 等程式部分，並多出一個新的 `Saved\StreetSocial\Build\<新 stage>.stage\`；
   - `Content\IndependentResources\base_v1\`、`Content\CharacterCards\`、`HairDeckData\` 不會被動到。
3. 照常用 `CardReaderDevelopment.cmd`、`OKStudio.cmd` 開。啟動器挑最新的 stage，第一次啟動時會自己把它接到既有的資源。

**自己裝過或換過 mod 的話**：mod 裝在各個 stage 自己的 `Mods\` 裡，新 stage 帶的是程式包預設的那一組。要沿用原本的配置，就用上面「ok-mod-pack 常用指令」對新 stage 再 `profile apply` 一次。

### 舊 stage 要不要刪

不刪也能用，只是每次更新多占約 1.3 GB。要刪的話**不能整個資料夾遞迴刪除**：stage 的 `Windows\OpenKoikatsu\Content\` 底下是指向安裝資料夾 `Content\` 的 junction，遞迴刪除會一路刪進共用的資源。安全的做法：

```powershell
# <old> 換成要刪的舊 stage 資料夾名稱；先拆 junction（只拆連結，不碰它指向的資料），再刪資料夾
$old = '.\Saved\StreetSocial\Build\<old>.stage'
Get-ChildItem "$old\Windows\OpenKoikatsu\Content" -Force | Where-Object { $_.LinkType } | ForEach-Object { $_.Delete() }
Remove-Item $old -Recurse -Force
```

刪之前先確認 `Get-ChildItem "$old\Windows\OpenKoikatsu\Content" -Force` 列出的那幾個（`CharacterCards`、`IndependentResources`、`KKPreview`）都已經拆掉。

### 程式和資源對不上時

程式包打包時，已經用它自己的 `ok-extract` 搭配對應完整包的資源，嚴格開過那包裡的 OK 卡（打包自檢）。所以照上面的步驟疊在同一版或更新的完整包上就能用。萬一資源太舊，開卡會失敗，畫面會講缺什麼；這時請下載新的完整包。啟動時自動檢查資源版本的機制還在規劃（[PROGRAM_ONLY_UPDATE_PLAN.md](PROGRAM_ONLY_UPDATE_PLAN.md) 第 2、3 節）。
