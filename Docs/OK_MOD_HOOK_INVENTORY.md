# OK Mod 盤點：mod 能改什麼、不能改什麼（2026-11-22）

配合 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md)。兩邊一起盤：

- **原作生態實際改了什麼**：KK_Plugins 51 個插件、KKAPI（IllusionModdingAPI）、ExtendedSave／Sideloader（BepisPlugins）、HF_Patch 的元件結構（2026-11-22 淺層 clone 後唯讀 grep）；
- **OK 現有程式在哪裡掛得上**：以 C（`C:\portable\OpenKoikatsu`，master）為準。E（`E:\OpenKoikatsu`）目前在 master 677437d20，是 C 的祖先，`duo2` 已全部併入；**Studio、1 對 1 的程式 C、E 相同**，只有 `KKPreviewActor.cpp`、`OKGalleryWidget.cpp`、`OKReaderScreen.cpp`、`session.rs`、`ffi.rs`、`push.rs`、`KKRustExtract.cpp` 的行號在 E 不同。下文位置都是 C 的行號。

三欄的意思：

- **可改**：現有程式已經有單一入口，宿主包一層就能開放；
- **有條件**：能做，但要先改核心（加欄位、加快取鍵、加執行緒約束）或有適用範圍限制；
- **不可改**：設計上不開放，或技術上做不到，附理由。

## 1. 原作插件到底改了什麼（需求面）

KK_Plugins 51 個插件（不含 TestPlugin）按改動類別計數：

| 類別 | 插件數 | 代表 |
|---|---:|---|
| 讀卡／捏人 UI 與事件 | 21 | MaterialEditor、Pushup、UncensorSelector、EyeControl、Profile |
| 設定／熱鍵／便利，不存資料 | ~21 | Autosave、ItemBlacklist、StudioWindowResize |
| 角色卡擴充資料 | 14 | MaterialEditor、Pushup、InvisibleBody、Colliders、MoreOutfits、Profile |
| 材質／貼圖／shader | 10 | MaterialEditor、HairAccessoryCustomizer、MaleJuice、TwoLut |
| 網格／蒙皮／可見性 | 7 | AccessoryClothes、ClothesToAccessories、UncensorSelector |
| Studio 場景資料 | 7 | StudioSceneSettings、StudioImageEmbed、TwoLut |
| 服裝（coordinate）資料 | 5 | MaterialEditor、Pushup、DynamicBoneEditor |
| 內容清單注入 | 5 | ListOverride、AccessoriesToStudioItems、MoreOutfits |
| 每幀骨骼／姿勢後處理 | 4 | AnimationController、HCharaAdjustment |
| 物理（DynamicBone） | 4 | Colliders、DynamicBoneEditor、Boop |
| 相機／後處理／淡入淡出 | 4 | StudioSceneSettings、FadeAdjuster |
| 表情／視線 | 3 | EyeControl、EyeShaking |
| 音頻 | 3 | Subtitles、兩個載入音效 |
| 主遊戲／H | 11 | MoreOutfits、SpawnLocker、HCharaAdjustment、Subtitles |

另外幾點：

- **39／51 用 Harmony 修補遊戲方法**，最常被修補的是 `ChaControl`（13 個）。也就是說，原作大部分插件是靠"任意修補"活下來的。OK 不開放任意修補，這些需求得換成宣告好的掛點（§3），或者乾脆做進核心。
- 很多每幀邏輯其實是 Unity 設計逼出來的。例如每幀改 collider 清單、每幀把 `hideMoz` 設成 true、每幀把可見性寫回去，都是因為遊戲自己每幀會覆寫。到了 OK，這些變成"設一次、由宿主保持"的狀態（§4）。
- 真正吃重的每幀骨骼插件不在 KK_Plugins 裡，而是 KKABMX、KKPE、NodesConstraints、Timeline、A12、PregnancyPlus、BetterPenetration。其中 ABMX、PregnancyPlus、BetterPenetration 的資料**已經是 OK 核心**在處理。

**OK 核心已經認識的 KKEx 區段**（`Tools/ok-extract/src/card.rs:2509-2635`）：Pushup、UncensorSelector、ABMData、KSOX／KCOX、KK_PregnancyPlus、KK_InvisibleBody（2567）、DynamicBoneEditor、EyeControl、editfangs、ClothingBlendShape、madevil.kk.ass、Accessory_States、Colliders、MaterialEditor、HairAccessoryCustomizer、MoreAccessories、UniversalAutoResolver。Studio 場景另認識 timeline、nodesConstraints、kkpe、studioscenesettings、studioimageembed 等（`studio_scene_plugins.rs`）。**這些區段歸核心，mod 只能讀，不能接手。**

## 2. 總表：可改／有條件／不可改

| 範圍 | 可改 | 有條件 | 不可改 |
|---|---|---|---|
| 卡片資料 | 自己 id 下的 `okMx` 資料；讀核心不認識的 KKEx 區段（`unknown_plugin_sections`） | 寫 `okMx` 要先讓三處身份計算排除它（§5.3） | 核心 chunk（`okLc okId okCh okPh okVo` 等）、別的 mod 的 `okMx`、核心認識的 KKEx 區段 |
| 開卡流程 | 開卡後對 session 下指令（身形、FK、骨骼位置／縮放、表情遮罩、臉紅） | 貼圖合成後處理：mod 集合要進開卡快取鍵；網格後處理（第二版） | 卡片解析、清單／GUID 解析、bundle 載入、zipmod 解析、uncensor 選擇規則 |
| 外觀屬性 | 經 appearance `patch` 寫 `plugins.<自己 id>.*`；用 apply／ops 換部件、改顏色和材質參數 | — | 繞過 `verify`；寫別的 id 的 `plugins.*` |
| 讀卡 UI | 宣告式頁面與控制項（`pages.json` 同格式、`PluginHost` 區），自動出現在 MCP `ui_*` | `pages.json` 目前只支援 `number`，要先補 toggle／dropdown／color／text／button | 自帶 Slate／UMG |
| 姿勢／骨骼 | — | 後姿勢骨骼修正（Rust、背景執行緒、可能多角色並行），只對有 Rust session 的角色（讀卡、Studio、1 對 1） | 街區／人群角色（GPU rig／pose bank，沒有每幀 session）；替換 animator 或 IK |
| 物理 | 透過既有參數（`okPh`、動態骨參數）調 | 每幀施力（Boop 類）：要在 Rust dynamics 加輸入 | 替換 PhysX／FleX 布料或剛體解算 |
| 表情／視線 | 表情遮罩、臉紅、視線目標（既有 setter） | 每幀驅動臉部：臉部在 C++ game thread，代價較高 | 改眨眼／表情時鐘本身 |
| 材質／貼圖／shader | 改既有材質參數（MaterialEditor 那一套 ops）；以 PNG 換貼圖；A 層參數材質（核心母材質＋參數＋PNG） | B 層：ModKit cook 的全新材質（含 Custom HLSL）、材質函式、後處理材質，pak 掛載、白名單驗證、綁整合版本（計畫 §6.11）；合成後處理（同開卡流程那格） | 新 global shader／render pass／shading model／vertex factory（要 C++ 模組）；執行期編譯 HLSL（遊戲內沒有編譯器）；覆蓋核心材質資產 |
| 模型／服裝內容 | 轉卡時經 gamefs 讀遊戲／zipmod 檔案，自動錄進卡內 `okLc` | — | `.okmod` 帶模型給別人的卡用（外觀資源一律在卡裡，計畫 §6.12）；DLL 裡塞 uasset |
| 相機／燈光／後處理 | Studio 指令能做到的（場景設定） | 讀卡與街區相機：要另開掛點 | 渲染管線、後處理材質 |
| 音頻 | 播放 mod 自帶的 ogg（宿主解碼） | 字幕類：要在語音播放處加事件 | 改語音解碼、嘴型算法 |
| OK Studio | 註冊指令（進現有指令表，自動有 undo 步驟）；時間軸可插值屬性（`Owner = "mod.<id>"`）；場景資料 | `.okscene` 要先加保留欄位，否則未知欄位會被丟掉 | 改檔案格式本體、改求解流程 |
| 1 對 1／H | 訂閱 `Note()` 事件；每幀 game thread 掛點 `OnSessionsIdle` | 配對骨骼修正（同姿勢那格） | 改 H 流程狀態機與判定 |
| 街區 | 命名空間規則 `<mod>.<rule>`；事件訂閱；資料表 toml；存檔 `ext.mods.<id>` | 給 LLM 對話加事實：要放在 prompt 會變動的那一段，不能破壞前綴快取 | 關鍵字判斷玩家的話；needs 變成生存壓力；直接改存檔其他欄位 |
| 控制通道／指令 | `mod_call` 路由；執行期註冊的主控台指令 | — | 綁新連接埠、對外網路 |
| 文字 | `locale/` 下 `mod.<id>.*` 語義 id | 宿主要自帶 ICU 格式化（讀卡器目前沒有在地化管線） | 覆蓋核心文字 id |
| 設定 | 宿主代存的型別化設定項、自動設定頁 | — | 自己寫檔 |
| 全域 | — | — | UObject／引擎、任意函式修補、行程／檔案系統（`assets/` 與設定以外）、網路、別的 mod 的資料 |

## 3. 各範圍的掛點位置

只列要掛的點，格式：掛點 ｜ 位置 ｜ 執行緒 ｜ 頻率 ｜ 備註。

### 3.1 卡片與開卡（Rust）

| 掛點 | 位置 | 執行緒 | 頻率 | 備註 |
|---|---|---|---|---|
| `on_session_open` | `session.rs:4869-4877`（`session::open`） | 背景 | 每次開卡＋服裝 | **快取命中也會走**；`okPh`／`okCh` 也是在這裡套用的 |
| 未快取開卡結束 | `session.rs:4936-4941` | 背景 | 未命中時 | 這裡的改動會被快取，所以 mod 集合要進 `oklib.rs:1556-1559` 的快取鍵 |
| 貼圖合成後 | `head_body.rs:627`、`face_texture.rs:187`、`catalog_textures.rs:377` | 背景 | 每部件 | KSOX 疊圖已經在這幾處 |
| 網格推送 | `push.rs:652` | 背景 | 每部件 | 第二版 |
| 轉 OK 卡 `on_kkex` | `oklib.rs` `make_ok_card` 約 2097，在 `library_card_with_pack` 之前 | CLI／背景 | 每次轉卡 | — |
| 寫 chunk | `tree_answers::with_chunk`（保留身份、缺 `okId` 時補上） | — | — | `strip_ok_chunks`（`oklib.rs:1621`）只刪 okLb／okLc／okLt／okId／okPv，`okMx` 重製時會留下 |
| C++ 另存 | `KKCardWriter.cpp:148` `SaveWithEdits` | 依呼叫者 | 每次存檔 | 原樣保留 PNG 前段的所有 chunk，`okMx` 不會被洗掉；共 8 個呼叫點 |

`extract.rs` 內部各階段（`lists_stage`、貼圖合成、頭髮、飾品、服裝…）**快取命中時整段跳過**，不當掛點。

### 3.2 讀卡 UI

| 掛點 | 位置 | 備註 |
|---|---|---|
| 宿主開啟（讀卡） | `OKHUD.cpp:24` → `OKGalleryWidget.cpp:1008` | — |
| 選卡 | `SelectIndex` `OKGalleryWidget.cpp:1324` | — |
| 載入：背景段／完成段 | `StartLoad3D` 1883（背景 1993-2014）／`FinishPreparedPreview` 2126（game thread） | — |
| 換裝／另存 | `OnOutfitSelected` 2364、`OnSave` 1494、`FinishOkCardSave` 1594 | — |
| 宣告式頁面 | `OKReaderScreen.cpp`：`pages.json` 解析 816-900、`BuildPluginTools` 1524 | 已有 `PluginHost` 區 |
| MCP 自動暴露 | `OKGameControl.cpp:94-100` `Operable()` | 宿主建的 UMG 控制項自動能被 `ui_widgets`／`ui_set` 讀寫 |
| 屬性面板 | `OKGalleryProperties.cpp` | `plugins.<id>.*` 的列會自動出現；**`group_id`／`title_id` 目前在 C++ 沒翻譯** |

### 3.3 每幀角色

| 掛點 | 位置 | 執行緒 |
|---|---|---|
| 後姿勢骨骼修正 | `session.rs:3241-3248`（ABMX 之後、Studio IK 之前），或 `finish_paired_dynamics` 之前（讓物理跟著走） | 背景，多角色並行（async pose、Studio `ParallelFor`、1 對 1 rayon） |
| 配對骨骼修正 | `ffi.rs:1598` 之後、1605（dynamics）之前 | 背景，每角色並行 |
| 臉部／視線 | `KKPreviewActor.cpp:10234`／`10249` | game thread |
| 1 對 1 每幀 | `KKPairedPlayback.cpp:96` `OnSessionsIdle` | game thread |
| 既有指令通道 | `ffi.rs:449` set_fk、466 set_bone_pos_scale、685 set_expression_mask、3428 set_blush | game thread 設定，求解時套用 |

### 3.4 OK Studio

| 掛點 | 位置 | 備註 |
|---|---|---|
| 宿主開啟 | `OKStudioGame.cpp:144` | — |
| 存／讀 | `Save` 775、`Load` 849；`.okscene` `OKSceneDocument.cpp:205/288` | **未知根欄位會被丟掉** |
| Undo | `CommitHistory` 316（整份文件快照） | mod 資料只要放在文件裡，就免費有 undo，**不需要 mod 回傳 do／undo** |
| 指令表 | `SOKStudioPanel.h:532` `AddCommand`、`RunCommand` 535（自動包 undo 步驟） | 控制通道 `cmd` 也走這裡 |
| 時間軸 | `EvaluateTimeline` `OKSceneDocument.cpp:1146`，依 track `Owner` 分派 | mod 用 `Owner = "mod.<id>"` |

### 3.5 1 對 1／H

| 掛點 | 位置 |
|---|---|
| 宿主開啟 | `OKInteractionPairGameMode.cpp:52`、`OKInteractionMode.cpp:50` |
| H 事件單一入口 | `OKHScene.cpp:476` `Note()` |
| 進出 | `OKInteractionMode` `Enter` 50、`Exit` 643；街區交接 `OKStreetSocialContacts.inl:614/743` |

### 3.6 街區

| 掛點 | 位置 | 備註 |
|---|---|---|
| 宿主開啟 | `OKStreetSocialScene.cpp:850` → `OKStreetSocialMind.inl:21`（規則在 24-27 開啟） | — |
| 規則鏈 | `Tools/ok-rules/src/lib.rs:141-217` | `<mod>.<rule>` 插在 bonds fallback 之前 |
| 存檔 | `FOKStreetStore::Ext`（`OKStreetSocialRules.h:374`），寫 1262 | 已經能原樣往返不透明 JSON，mod 狀態放 `ext.mods.<id>` |
| 事件 | 換日 `OKStreetSocialOuting.inl:252`、對話 `BeginTalk`／`EndTalk`、邀約 `Invite.inl:312`、電話 `PhoneInbox.inl:204`、效果 `Heroine.inl:20` | 都在 game thread |

### 3.7 跨模式

- **行程層級開宿主**：`OpenKoikatsu.cpp:18-50`（`StartupModule`，緊挨 `OKGameControl::Start`），一次涵蓋所有模式；各模式的開啟點只負責發"進入模式"事件；
- **主控台指令**：現有寫法都是編譯期的 `static FAutoConsoleCommand`，mod 指令要改用執行期的 `IConsoleManager::RegisterConsoleCommand`；
- **控制通道**：`OKGameControl.cpp:142` 的路由表加 `/mod`，ok-game-mcp 的工具表在 `Tools/ok-game-mcp/src/control.rs:315-341`；
- **文字**：`OKT`／`OKMsg` 經 ok_rules 的 `text` 規則，**只有街區（和 1 對 1）開著**；Studio 有自己的表，讀卡器沒有。所以宿主要自帶 ICU 格式化；
- **啟動參數**：比照 `run_street_social_development.lua:8-26`，加 `-NoMods`／`OK_MODS_DIR`；
- **staging**：`stage_street_social.lua:51-74` 把 `ok_rules`／`ok_mind`／`ok_story` DLL 複製到 exe 旁，`ok_mod_host.dll` 加在這裡；`Mods/` 放 `<tag>.stage/`，必須是普通目錄（stage 裡的 `Windows/Engine`、`Content` 是 junction）。

## 4. 每幀回呼：會用在哪裡

原作的每幀用途（KK_Plugins 全部，加上生態裡的大戶），換到 OK 後的做法：

| 原作每幀用途 | 例子 | 在 OK 怎麼做 | 需要每幀呼叫 mod？ |
|---|---|---|---|
| 每幀覆寫可見性、collider 清單、`hideMoz` | UncensorSelector、Colliders、Demosaic | 設一次狀態，由宿主或核心保持 | 不需要 |
| 動態骨參數重設 | DynamicBoneEditor | 參數改變時下一次指令 | 不需要 |
| 熱鍵輪詢 | ItemBlacklist、CharacterExport、ShaderSwapper | 宿主統一做按鍵綁定，mod 收"按鍵事件" | 不需要 |
| 計時、自動存檔、檔案監看 | Autosave、ReloadCharaListOnChange | 宿主計時器（最短 50 ms）與檔案事件 | 不需要 |
| IMGUI／tooltip 更新 | MaterialEditor、AnimationController | 宣告式 UI，宿主畫 | 不需要 |
| 時間軸流程控制 | TimelineFlowControl | Studio 時間軸事件（越過關鍵幀時通知） | 不需要（播放中按事件） |
| 貼圖動畫 | MaterialEditor 動畫貼圖 | 宿主按 mod 宣告的幀序列播放 | 不需要 |
| **動畫後的骨骼修正** | AnimationController（視線／IK 跟物件）、KKABMX、KKPE、NodesConstraints、PregnancyPlus | Rust 後姿勢掛點（§3.3） | **需要**，背景執行緒、可能並行 |
| **每幀施力給物理** | Boop | Rust dynamics 的外力輸入 | **需要**，同上 |
| **眼睛高光抖動等臉部效果** | EyeShaking | 臉部每幀（C++ game thread） | **需要**，game thread |
| 角色根節點跟操縱器 | HCharaAdjustment、StudioObjectMoveHotkeys | Studio／1 對 1 已有物件操縱，改成指令 | 不需要 |

結論：

- **通用的 game thread 每幀 tick 第一版不開**。原作約 3/4 的每幀用途在 OK 裡都能換成狀態、事件或計時器。
- **真正需要每幀的只有三種**：骨骼修正、物理外力、臉部效果。前兩種都在 Rust 求解裡，在背景執行緒跑，而且多角色並行。
- 開放形式：mod 實作一個純函式 `post_pose(角色, 骨骼 slice) -> 修改`，規則如下：
  - 必須 `Send + Sync`，不能動共用狀態；
  - 宿主量每次耗時，超出預算就警告，持續超出就停用；
  - 只作用在有 Rust session 的角色（讀卡、Studio、1 對 1），**街區與人群角色碰不到**。
- 排期：放 M4 之後。第一版先給計時器、按鍵事件、時間軸事件。

## 5. 盤點推翻或補充計畫的地方

### 5.1 E 線

E 現在在 master，是 C 的祖先，沒有比 C 新的 Studio／1 對 1 程式。"E 線同時開掛點"不需要另做一套，同一份掛點在兩個 checkout 都要編得過。

### 5.2 同一行程裡會有兩個宿主

`ok_extract.lib` 是靜態連結進遊戲執行檔的。如果 ok-extract 連 `ok-mod-host` rlib，UE 又載入 `ok_mod_host.dll`，同一個行程裡就有兩個宿主、兩份 mod 狀態。

- **改為**：遊戲內 ok-extract 經由 `OkUnrealBindings`（`ffi.rs:1308`，目前只有 `log`）加一個回呼，轉給 UE 載入的那個宿主；
- rlib 只給獨立的 `ok-extract.exe`（CLI 轉卡）用。

### 5.3 角色身份有三處實作

| 實作 | 位置 | 怎麼算 |
|---|---|---|
| Rust | `oklib.rs:828-848` | `okId`，否則 sha256 扣 `okVo` |
| Lua | `prepare_street_social_selection.lua:83-115` | 扣 `okVo` |
| C++ 讀卡對話 | `OKReaderTalk.cpp:24-34` | `okId`，否則**整個檔案的 MD5**，連 `okVo` 都沒扣 |

- 三處都要排除 `okMx`；
- C++ 那一處本來就和另外兩處不一致，是既有問題，要在 M1 之前先修。

### 5.4 快取

開卡有 session 快取、`okBk`、memo 三層。

- mod 掛點放 `session::open`（快取命中也會走）；
- 會影響快取內容的掛點（貼圖合成後處理），要把"啟用的 mod 與版本"放進快取鍵。

### 5.5 `.okscene`

未知根欄位會被丟掉，要先加一個保留的 `mods` 欄位（FormatVersion 4）。

### 5.6 Studio undo

既有 undo 是整份文件快照。計畫 §6.5 寫的"mod 回傳 do／undo 兩筆指令"不需要，改成"mod 資料放在文件裡，undo 自動涵蓋"。

### 5.7 M3 參考 mod 要換

KK_InvisibleBody 已經是核心（`card.rs:2567`），和"核心認識的區段歸核心"衝突。

- 改用 **Profile**（KK_Profile 的角色簡介）：核心不認識、資料簡單，又能走完 KKEx 匯入、`okMx`、讀卡文字框、MCP 讀寫整條路；
- 視覺效果類的第二個參考，等 §4 的後姿勢掛點再選（例如視線跟隨物件）。

### 5.8 讀卡器文字與控制項

- 沒有在地化管線，plugin 群組標題也沒翻譯；
- `pages.json` 只支援 `number` 控制項。

這兩項是讀卡器開放 UI 前的前置工作。

### 5.9 已有、可以直接沿用的機制

- `ok_rules` 的 DLL 載入與熱重載（`OKStreetRules.cpp`）；
- `OkUnrealBindings` 函式表；
- `PLUGIN_SECTIONS`／`plugins.<id>` 的精確比對規則；
- `with_chunk`；
- `pages.json`＋`PluginHost`；
- UMG 控制項自動暴露給 MCP；
- Studio 指令表與快照 undo；
- 街區 `Store.Ext`；
- `OKControl::Bind`；
- 卡內資源包 `okLc` 的錄製與回放（轉卡時 mod 經 gamefs 讀的檔案也照樣錄進卡）。

宿主不重做這些，只包一層。

## 6. M0 先做哪個模式（盤點後的建議，待使用者決定）

**建議：讀卡器。** 理由如下：

- **需求最多**：原作插件裡，捏人 UI 21 個、角色卡資料 14 個，是最大的兩類；
- **現成基礎最多**：卡片 chunk 寫入會保留未知 chunk；`pages.json`＋`PluginHost`；控制項自動進 MCP；appearance `patch` 單一寫入點；
- **前置工作明確**：身份三處統一（§5.3）、`pages.json` 補控制項種類、宿主 ICU 格式化（§5.8）。

次選是**街區**：`Store.Ext` 和規則鏈都現成，前置工作最少，但能做的 mod 種類比較窄（規則與資料表）。

## 7. 補充：新 shader 與新 UE 材質（2026-11-22 使用者要求開放）

原本列為"不可改"，現在改成兩層開放，細節在計畫 §6.11：

- **A 層（不需要 UE）**：核心母材質加參數與 PNG，宿主在執行期建 MID；
- **B 層（需要 ModKit）**：同引擎、同專案 cook 的材質 pak，自帶 shader 庫，宿主掛載後 `OpenLibrary` 再載入。

**沿用的先例**：

- 街區補丁的 `RuntimeMaterialPatch-*_P.pak`（`Tools/rebuild_street_social_patch.lua`）；
- `KKRuntimeSharedMaterial.cpp:499` 執行期開補充 shader 庫；
- stage 用傳統 pak（`rebuild_street_social_runtime.lua:126`）。

**掛點**：

- `KKPreviewActor.cpp` 約 5831-7088 依 Unity shader 名稱分派材質的地方，加"mod shader 家族登記"；
- `OKHGShading` 的母材質替換（`KKPreviewActor.cpp` 約 10805-10942）可以讓 mod 登記新的渲染風格。

**還是做不到的**：

- 要 C++ 的 shader 工作（global shader、新 pass、新 shading model、vertex factory）；
- 執行期編譯 HLSL。

**待實測**：Custom 節點 `#include` 外部 `.usf` 在 cook 後能不能不靠原始碼載入。

**街區與人群角色**：用 `KKRuntimePose` 的共用母材質配方（`EKKRuntimeMaterialRecipe`），mod 材質要另外登記配方才會套到他們身上，列在 M3.5 之後。
