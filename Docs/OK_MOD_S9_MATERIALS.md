# OK Mod 工作項 9（F 組）：mod 材質——B 層 pak、A 層參數材質、shader 家族、逐部件覆蓋、glass-shader（2026-11-23）

同步點 B 之前，協調者交辦工作項 9 中不依賴 E 與 C 的部分。對應 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §6.11，以及工作項 3 的結論（[OK_MOD_S3_材質可行性.md](OK_MOD_S3_材質可行性.md)）。

## 提交

| 提交 | 內容 |
|---|---|
| `9590728f4` | `ok-mod-host`：`{"op":"content"}`，讀 mod 的 `materials/*.toml` 與 `content/*.pak`（`Tools/ok-mod/host/src/content.rs`） |
| `fcb19c528` | `KKUnityBundle`：shader 家族表 `KKModMaterials`；`KKPreviewActor` 的材質分派段在一般部件與 GPU 蒙皮 follower 上查表 |
| `d15c17874` | `OKModding`：內容載入器 `OKModContent`（B 層掛載、白名單、OpenLibrary、預熱、A 層、家族登記、主控台指令）；`DefaultGame.ini [OKModding] ContentBuild=1`；`modkit_cook.lua` 印出 content_build |
| `1147165a3` | 範例 mod `Tools/ok-mod/examples/glass-shader` |
| `ea59f5d4a` | full profile 加入 glass-shader |

B 層材質本身（外掛 `Plugins/org_openkoikatsu_glass_shader`、`M_OKGlass`、`MI_OKGlass_Smoky`）由子代理提交在 `fc121c3cf`，錯誤紀錄在 `979e6aeff`。

## 做了什麼

### mod 的材質宣告（宿主，Rust）

mod 資料夾裡的 `materials/*.toml`：

```toml
[[material]]
name = "glass"                                              # 完整 id "<mod id>/glass"
asset = "/org_openkoikatsu_glass_shader/M_OKGlass.M_OKGlass"   # B 層：mod 自己 pak 裡的材質
parent = "translucent"                                      # A 層：opaque／masked／translucent／xray；有 asset 時是備用
families = ["Koikano/main_clothes_item_glasses"]            # 由這個材質畫的 Unity shader
main_texture = "_MainTex"                                   # 部件自己的貼圖放進哪個參數
copy_source_values = false                                  # 卡片材質值是否寫進同名參數（預設 true）
[material.scalars]
GlassOpacity = 0.35
[material.vectors]
GlassTint = [0.75, 0.9, 1.0, 1.0]
[material.textures]
_DetailTex = "textures/detail.png"                          # mod 資料夾內的 PNG
```

宿主逐項檢查，不合格的宣告丟掉並列在 `problems`（遊戲 log 會印出）：

- `asset` 必須在 mod 自己的套件根 `/<content_root>/` 下；`content_root` 是 id 把 `.`、`-` 換成 `_`，即 ModKit 外掛名。
- `parent` 只能是四個開放的父材質。
- 貼圖必須是 mod 資料夾內的 PNG。
- 有 `content/*.pak` 卻沒有 `content_build` 時，不用那個 pak。

### 遊戲端（`Plugins/OKModding/.../OKModContent.cpp`）

進入模式與熱重載之後呼叫 `OKModContent::Refresh()`。每個 mod 的 pak 在一個程序裡只處理一次。

**B 層（只在打包遊戲）**，照工作項 3 驗證過的順序：

1. mod.toml 的 `content_build` 必須等於遊戲的值：`<DefaultGame.ini [OKModding] ContentBuild>@<引擎 major.minor.patch-changelist>`，目前是 `1@5.8.4-0`。`Tools\lua\lua.exe Tools\modkit_cook.lua --mod <外掛> --content-build` 印出這個值；cook 完成時也會印出並寫進 `content_build.txt`。
2. `FCoreDelegates::MountPak(pak, 0)`。
3. 掛載點必須是 `../../../OpenKoikatsu/Mods/<content_root>/Content/`。逐一列出 pak 的檔案：只接受 `.uasset`／`.uexp`／`.ubulk`／`.uptnl`，以及這個 mod 自己的 `ShaderArchive-OKModCook_<root>-*.ushaderbytecode`；擋下 `..`、絕對路徑與磁碟代號。
4. `RegisterMountPoint("/<root>/", 掛載點)`。
5. `FShaderCodeLibrary::OpenLibrary("OKModCook_<root>", 掛載點)`，打不開就拒絕。一定要在載入任何材質之前做，否則材質沒有 shader。
6. 載入每個套件，套件裡每個物件的類別都要在 §6.11 白名單上（Material、MaterialInstanceConstant、MaterialFunction、MaterialParameterCollection、Texture2D／Cube／2DArray、VolumeTexture、SubsurfaceProfile）；白名單資產的子物件跟著它的資產判斷。

任何一步不合格：卸下已掛的 pak，這個 mod 的材質改用 `parent`。

- **預熱**：材質在 `Refresh` 時載入並以 `TStrongObjectPtr` 常駐，同時檢查 `GetGameThreadShaderMap()` 不為空、不是預設材質，沒有 shader 也退回 `parent`。沒有做 PSO 預編譯（`PrecachePSOs`）。
- **編輯器**（`!FPlatformProperties::RequiresCookedData()`）不掛 pak（cooked 內容在編輯器載不進來），直接用 A 層。

**A 層**：

- 載入 `/Game/IndependentResources/PreviewMaterials/M_Preview*`。
- 部件貼圖放進父材質的 `PreviewTexture`；mod 給的 `PreviewTint` 等參數照樣套用。
- PNG 用 `FImageUtils::ImportFileAsTexture2D` 讀。

**shader 家族**：`KKModMaterials::SetFamilies`，鍵是小寫的 Unity shader 名。同一個 shader 兩個 mod 都宣告時，先載入的贏，log 會警告。`KKPreviewActor` 在兩個地方查表：

- 一般部件（程序網格）套完材質後；
- GPU 蒙皮 follower 套完材質後。讀卡器預設畫的是 follower，程序網格是隱藏的。

查到就以 mod 材質建 MID，順序是：

1. 宣告的參數；
2. （`copy_source_values` 時）卡片材質的同名值，顏色 sRGB→linear；
3. 部件貼圖放進 `main_texture`。

**主控台指令**：

| 指令 | 做什麼 |
|---|---|
| `mod.material.list` | 每個 mod 材質實際用的資產，以及遊戲的 content build |
| `mod.material.apply <mod id>/<名> <部件>` | 逐角色覆蓋：顯示中角色的部件名（例如 `clothes_top`、`clothes_socks`）或元件名，連同畫它的 follower，所有材質槽換成該 mod 材質；部件貼圖與原值照上面規則帶入。找不到時列出目前有哪些部件 |
| `mod.material.preview <id>... [Shot=<png>] [Quit=1]` | 鏡頭前放平面畫這些材質（給 probe stage 用），3 秒截圖、6 秒退出 |
| `mod.enter <模式>` | 手動進入模式（probe stage 的 Entry 地圖辨認不出模式時用） |

### 範例 glass-shader

位置：`Tools/ok-mod/examples/glass-shader`。

- 內容：DLL（只有 `about` 指令與啟用訊息）、`mod.toml`（`category = "content"`、`content_build = "1@5.8.4-0"`）、`materials/glass.toml`、`locale`。
- 兩個材質：
  - `glass`：B 層 `M_OKGlass`，A 層備用 `translucent`；家族是 `Koikano/main_clothes_item_glasses`、`Shader Forge/toon_glasses_lod0`（眼鏡鏡片，以及用這兩個 shader 的透明飾品）。
  - `smoky`：B 層 `MI_OKGlass_Smoky`，沒有家族，給 `mod.material.apply` 用。
- **pak 不進版控**（是 cook 產物）：
  - 用 `Tools\lua\lua.exe Tools\modkit_cook.lua --mod org_openkoikatsu_glass_shader` 重新產生；
  - 把產生的 `org_openkoikatsu_glass_shader.pak` 放進 mod 的 `content\`；
  - 本機現成的一份：`F:\OpenKoikatsu\Saved\ModKit\org_openkoikatsu_glass_shader\Cook3\pak\org_openkoikatsu_glass_shader.pak`。

## 驗證

- **Rust**：`cargo test -j 8`（`Tools/ok-mod` 全 workspace）全部通過，包含 `content::tests::reads_and_checks`：
  - 好的宣告；
  - 不在開放清單的 parent、跳出 mod 資料夾的貼圖、指到 `/Game/` 的 asset 都被丟掉；
  - 沒有 content_build 時 pak 不用。
- **建置**（F:\UE5.8）：`OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 最後一次都 `Result: Succeeded`，log 在 `F:\OpenKoikatsu\Saved\ModKit\S9\editor5.log` 與 `F:\OpenKoikatsu\Saved\ModKit\S9\game3.log`。這次沒改 `Tools/ok-extract`。

**B 層，打包遊戲**（`Saved/ModKit/ProbeStage`，換上新 exe、`ok_mod_host.dll` 與 `Mods/glass-shader`）：

- content_build 不符（stage 的 ini 沒有 `[OKModding]`，值是 `0@5.8.4-0`）：
  - log `content pak not used: content_build "1@5.8.4-0", this game is "0@5.8.4-0"`；
  - 兩個材質退回 `M_PreviewTranslucent`，畫成兩塊淡色平面：`F:\OpenKoikatsu\Saved\ModKit\S9\nomatch2\preview.png`。
- 符合（命令列 `-ini:Game:[OKModding]:ContentBuild=1`）：
  - log 依序是：
    - `content mounted: 1 pak(s), 2 asset(s) at /org_openkoikatsu_glass_shader/, shader library OKModCook_org_openkoikatsu_glass_shader`；
    - `material .../glass ready: /org_openkoikatsu_glass_shader/M_OKGlass.M_OKGlass`；
    - 兩個材質都 `shadermap=1`。
  - 截圖是黑底上的玻璃：中央透明、邊緣有 fresnel 亮邊，不是預設材質：`F:\OpenKoikatsu\Saved\ModKit\S9\match3\preview.png`。
  - log：`F:\OpenKoikatsu\Saved\ModKit\S9\match3\game.log`。
- 拒絕流程：中途一版的檔案路徑檢查有錯，把合法 pak 判成「entry outside the mod's folder」（`F:\OpenKoikatsu\Saved\ModKit\S9\match2\game.log`）。驗到的是：拒絕 → 卸下 → 退回 A 層，遊戲照常。
  - 「白名單外的類別」（例如 Blueprint）這條路徑**沒有在遊戲裡用真的壞 pak 驗**。打包時的同一份白名單檢查（`modkit_cook.lua --verify`）在工作項 3 用 Blueprint 反例驗過。

**讀卡器（編輯器建置 `-game`，`-ModDev`）**：

- log：`content pak not used in the editor ...; materials use their A-layer fallback`；`mod.material.list` 列出 2 個材質、2 個家族、`content build 1@5.8.4-0`。
- **shader 家族**：卡 `F:\OpenKoikatsu\Content\CharacterCards\CrowdAPNG\C011.png`（戴眼鏡）。
  - log 有 `OK mod material follower part=head shader=Koikano/main_clothes_item_glasses material=org.openkoikatsu.glass-shader/glass`；
  - 鏡片變成淡藍玻璃色：`F:\OpenKoikatsu\Saved\ModKit\S9\reader-family-glasses.png`。
- **逐部件覆蓋**：`mod.material.apply org.openkoikatsu.glass-shader/smoky clothes_top` 回 `on 6 material slot(s)`，白外套變成半透明煙灰，保留原本的布料貼圖：`F:\OpenKoikatsu\Saved\ModKit\S9\reader-apply-smoky.png`。
- log：`F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-024050-01b1f4da.log`。

## 第二段：材質 hook（Hook cherry-pick 之後）

協調者授權 cherry-pick C 的 `be18a313c`（通用 Hook）。F 上是 `3797e3e40`；`ffi.rs`、`ok_mod_host.h` 的衝突兩邊都保留。

| 提交 | 內容 |
|---|---|
| `1e5771a2b` | 宿主 `{"op":"subscribers","hook"}`：回傳訂閱者，給呼叫端在準備 payload 前先問 |
| `c3d51b03f` | ok-extract：`material.post_texture` |
| `418960c57` | `material.resolve_shader`；ok-extract 分派器改設到開卡的那份（見下方「發現的問題」） |
| `5a322fe86` | 測試 fixture `Tools/ok-mod/fixtures/material-hooks`，列入 `obsolete.toml` |

**`material.post_texture`**（`Tools/ok-extract/src/mod_forward.rs`）：

- 位置：`push.rs` 的 `emit`。這是原作卡、OK 卡、portable 卡共同的出口，在核心所有處理（合成、KSOX／KCOX、徽章、Material Editor）之後。
  - 一開始照計畫接在 `head_body.rs`／`face_texture.rs`／`catalog_textures.rs` 的合成點，但 OK 卡的貼圖來自卡內資源包，不經過那些合成，所以改到這裡。
- payload：`{"slot":"<部件 role：body、head、hair、clothes_top、accessory…>","part":"<網格名>","outfit","width","height","rgba":<位址>,"len"}`。
  - `rgba` 是 8 位元 RGBA（列由上到下）的位址，mod 只能在這次呼叫期間原地改寫。
  - 回 `{"changed":true}` 時，以開卡路徑的編碼（PNG 或 `OK_RAW_TEXTURES` 的 raw）寫回。
- 沒人訂閱時只多一次 `subscribers` 詢問，不解碼；沒有宿主時（CLI、測試）直接略過。

**`material.resolve_shader`**：

- payload `{"shader","part"}`，回 `{"material":"<mod>/<名>"}`；依載入順序，第一個指名已載入材質的 mod 勝出。
- 只有在有人訂閱時，`OKModContent::Refresh` 才裝上解析器（`KKModMaterials::SetResolver`）。
- 部件建立時先問解析器，沒答才查 shader 家族表。不快取，所以 mod 改了設定後，下次開卡就生效。

**實測**（讀卡器，`F:\OpenKoikatsu\Content\CharacterCards\CrowdAPNG\C011.png`，Mods 裡有 glass-shader、hello、material-hooks）：

- resolve_shader：fixture 設定 `glass_part = mimi` 後，log 有：
  - `OK mod material part=o_mimi_fox shader=Koikano/main_clothes_item material=org.openkoikatsu.glass-shader/smoky`；
  - `o_mimi_fox_r` 同樣一行。
  - log：`F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-030209-7bb411dd.log`。
- post_texture：log 有 `[org.openkoikatsu.test.material-hooks] tinted clothes_top (4194304 bytes)`，白襯衫與外套變成綠色：`F:\OpenKoikatsu\Saved\ModKit\S9\reader-post-texture.png`。
  - log：`F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-033429-6541f096.log`。
- `cargo test`：`Tools/ok-mod` 全部通過；`ok-extract` 的 `mod_forward` 測試通過，涵蓋兩種情況：沒人訂閱時只問 subscribers、不送 hook；有人訂閱時原地改寫並重新編碼。
- `cargo check`（含 `--no-default-features`）通過；F:\UE5.8 的 `OpenKoikatsuEditor`（`F:\OpenKoikatsu\Saved\ModKit\S9\editor9.log`）與 `OpenKoikatsu`（`F:\OpenKoikatsu\Saved\ModKit\S9\game5.log`）都 `Result: Succeeded`。

**發現的問題**：

1. **追加 `Event::Hook` 不是 ABI 相容的**。Hook 之前編出來的 mod DLL（F 的 hello、glass-shader），新宿主全部以 `not a compatible ok_mod DLL` 拒載。
   - abi_stable 比對 `Event` 時，宿主有 6 個變體、mod 只有 5 個，報 `too many variants`；完整比對：`F:\OpenKoikatsu\Saved\ModKit\S9\abi-old-glass-vs-hook-host.txt`。
   - 用新 SDK 重編後就能載入。
   - 影響：Hook 進來之前發出去的 mod 都要重編。之後再加變體也一樣，除非照 abi_stable 的規則調整（例如宿主傳給 mod 的列舉不能比 mod 編譯時的多）。這要協調者決定，我沒動 api。
2. **模組化（編輯器）建置裡 ok-extract 有兩份**：KKUnityBundle 與 OpenKoikatsu 各自靜態連結 `ok_extract.lib`。
   - `OKModModes` 原本呼叫 `ok_set_mod_dispatch`，設的是 OpenKoikatsu 那份，所以開卡時的 hook 永遠不會觸發。
   - 改成由 KKUnityBundle 匯出 `KKModMaterials::SetExtractDispatch`。
   - 單一執行檔（打包遊戲）只有一份，舊寫法在那裡本來就能動；打包遊戲裡的 post_texture 沒實測。

## 沒做／沒驗

- **post_texture 對開卡速度的影響**沒跑 `card_open_baseline.lua`。
  - 沒人訂閱時，每個部件多一次本機 JSON 往返（`subscribers`），估計很小，但沒量；
  - 有人訂閱時，每個部件要解碼再編碼一次主貼圖，C011 的 2048² 上衣是數十毫秒等級。
- **post_texture 改過的貼圖與快取**：開卡路徑的 view_memo 與合成快取都在 hook 之前，所以每次開卡都會重新呼叫 mod。但讀卡器之外的快取有沒有把 hook 後的貼圖存下來（例如 GPU 磁碟快取、Studio／街區的角色快取），沒查。換了 mod 或設定後，那些地方可能還是舊圖。
- **只處理主貼圖**（`texture_png`），沒有法線、遮罩等其他貼圖。
- 照指示這輪不做：toon-post、okMr 寫入與 skin-decal 的卡片寫入、`oklib.rs`。
- **覆蓋不會存進卡片**：`mod.material.apply` 只在這次執行有效，換卡、換服裝就沒了。寫進卡片要等 okMr（同步點 B 之後）。
- **B 層材質畫在角色身上沒驗**：
  - 打包遊戲裡只畫在平面上；讀卡器（編輯器建置）只能用 A 層。
  - 角色部件在 GPU 路徑是 `UKKRuntimePoseableMeshComponent`。cook 主機沒啟用 KKRuntimePose 等遊戲外掛，如果它們用的 vertex factory 不是一般的 GPU skin，庫裡就沒有對應的 permutation，材質會退回預設材質。
  - 要在打包的街區或讀卡器 stage 上試，F 目前沒有那種 stage。
- **A 層退回的觀感**：`M_PreviewTranslucent` 只有 `PreviewTexture`／`PreviewTint` 兩個參數，B 層的 `GlassOpacity`、`FresnelPower` 對它無效。鏡片在 A 層是淡色半透明，不是玻璃。
- **PSO 預編譯**沒做，只有預載常駐。第一次畫 mod 材質可能有 PSO 編譯卡頓，沒量。
- **卸載**：pak 掛上後整個程序都不卸，熱重載也不重掛。改了 pak 要重開遊戲。
- **`content_build` 的引擎部分**是 `FEngineVersion::Current()`。原始碼建置的 changelist 是 0，所以 C、E、F 三份 5.8.4 引擎的值相同。真正擋住不相容 shader 的是 shader 庫自己的格式檢查，加上 ini 的 `ContentBuild`：遊戲改到會破壞舊 mod 內容時要手動加 1。
- **`copy_source_values` 的顏色換算**：一律把卡片顏色當 sRGB 轉 linear。對本來就是線性值的參數（例如被當顏色存的數值）會算錯；glass 範例關掉了這個選項。
- **白名單的 Rust 版本**仍在 Lua（`modkit_cook.lua --verify`），與遊戲端 C++ 是兩份實作。
