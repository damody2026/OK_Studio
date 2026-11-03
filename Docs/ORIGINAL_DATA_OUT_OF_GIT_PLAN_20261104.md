# 原作資料移出版控計畫（2026-11-04）

目標：版控只留專案自己的程式與內容。原作（KKS `abdata`、遊戲 `UserData`、語音）與第三方 mod 衍生的資料全部移出 git，另外打包成 zip 保存。新增 `Tools/restore_original_data.lua`：只要指定原作路徑，就能把整套 OK 共用資料還原到可以建置、遊玩的狀態。

盤點依據：[基礎庫共用資源盤點](BASE_LIBRARY_SHARED_INVENTORY_20261104.md)，以及本次對 `git ls-files` 的全倉掃描（40,590 個追蹤檔，其中 LFS 9,944 個、約 12.2 GB）。

## 一、要移出的內容

### A. 能從原作路徑重新產生（還原腳本自動做）

| 路徑 | 數量／大小 | 產生方式 |
|---|---|---|
| `base_v1/models/**/*.okmodel`（原作 ~470 個＋共用 mod ~134 個＋來源不明 18 個） | 626／6.4 GB | `ok-extract <遊戲> --oklib convert <lib> 8 @<來源清單>`；清單由目前 `converted.tsv` 對應追蹤中的模型 ID 產生，存成 `Tools/base_library_sources.txt`（只含路徑名稱）。共用 mod 那 134 個需要遊戲 `mods/` 裡有 `Tools/base_library_shared_mods.txt` 列的 zipmod |
| `base_v1/sources.okidx`、`converted.tsv`、`missing.txt`、`oklib.json`、`edits.stamp`、`shared_mods.txt` | 1.1 GB＋小檔 | `convert` 時一併寫出 |
| `base_v1/anims/studio/*.okanim`、`studio_anims.json` | 5,805＋1／~225 MB | `--oklib anim-convert <lib> - "" 8`（`-` 用預設角色，輸出可重現） |
| `base_v1/anims/studio_variants.okpack` | 351 MB | `--oklib anim-pack <lib>` |
| `base_v1/paired/` | 4／1.5 GB | 從 `<遊戲>/abdata` 複製 24 個 bundle（清單與 sha256 在 `paired/manifest.json`，改放 `Tools/paired_sources.json` 進版控）→ `ok-paired-library convert` |
| `base_v1/studio/voice`、`studio_voices.json`、`studio/bgm`、`h/se`、`h/se.json` | 8,346／~2.3 GB | `studio-voices`、`studio-sounds`、`h-sounds`（ok-extract 需 `--features studio-sounds`） |
| `base_v1/studio/{bg,frame,sky,reflections}`、`sky.json`、`map_*.json`、`studio_items.json`、`studio_child_animations.json`、`shader_states.json` | ~110 MB | `studio-images`、`studio-sky`、`studio-reflections`、`studio-environments`、`studio-catalog`（＋`studio-names`、`studio-nodes`、`studio-standard-textures`）、`studio-child-anims`、`shader-states` |
| `base_v1/studio/samples/` 原作 3 張 | 13 MB | `studio-images` 目前挑樣本的規則和現有檔不同；改成讀固定清單 |
| `RuntimeAnimations/library/*.okanim` | 873／339 MB | `Tools/export_street_animation_library.lua --game` |
| `RuntimeAnimations/*.okanim`＋manifest | 84／30 MB | `ok-extract <遊戲> --export-runtime-clips`，來源 key 取自現有 manifest，整理成 `Tools/runtime_clip_sources.txt` |
| `Content/Scenes/CrowdRoom/SharedWalk`、`BehaviorR1Curves` 的 3 個 uasset | 1.6 MB | `Tools/CrowdBehaviorBake -ExportRuntimeCurve`（UE commandlet，需要編輯器） |
| `UserData/Studio/scene/` 官方場景 106 個 | 28.5 MB | 遊戲 `UserData/Studio/scene/Official` → `OKStudio.ImportKStudio`（UE，需要編輯器） |

### B. 不能只靠原作路徑重新產生（放進 zip，還原腳本從 zip 解出）

| 路徑 | 數量／大小 | 原因 |
|---|---|---|
| `StreetSocialData/ja_ogg`、`RuntimeV2/ja_ogg` | 15,105／~530 MB | 來源是預先解出的 `<遊戲>/voice_extract`，沒有追蹤中的解出工具 |
| `StreetSocialData/zh_ogg` | 851／21 MB | 來源是中文語音包 WAV，不在遊戲內 |
| `StreetSocialData` 的台詞資料（`catalogue*.json`、`RuntimeV2～V5`、`topics`、`relationships`、`invitations`、`gaps`、`rules.json`、`world.json`、`expressions.json`、`h_poses.json`、`TestFixtures`） | 數十 MB | 含原作台詞與 BepInEx zh-TW 翻譯，之後還有人工／AI 修改，不能重跑 |
| `StreetSocialData/Localization/{en,zh-CN,zh-TW}/dialogue.json` | ~3 MB | 原作台詞的翻譯（衍生著作） |
| `RuntimeVoices/sun_tk_32_000.ogg`、`BodyInteractions/`、`MotionCatalogue/MotionCatalogue.json` | 10 MB | 沒有追蹤中的產生工具 |
| `Content/Koikatsu/Data/*.uasset` | 9／19 MB | 原作與 zipmod 目錄的 DataTable；TSV 匯出工具沒進版控 |
| `Content/KKPreview/` 的原作 ramp、LUT 與 mod ramp | ~50 個 | 沒有產生工具 |
| `UserData/Studio/scene/` 第三方場景 22 個、`UserData/Studio/screenshot/` | 65 MB | 來源是 pixiv 場景，不在遊戲內 |
| `Docs/images/OKStudio/` 中的原作截圖（含官方場景 PNG 原檔） | ≤86 MB | 驗證截圖 |

B 類之後若補上產生工具（例如從 abdata 解語音與台詞、ramp 匯出），就移到 A 類，不必再靠 zip。

### C. 留在版控

- 專案自己的程式、地圖、`RuntimeMaterials`（GpuPoseAudit 產生，貼圖是佔位）、`StreetSocialData` 的規則 toml、Regions、Profiles、`Models/*.okmesh`（Blender 自建）、`Localization/*.toml`、`Launch/*`、`PreviewMaterials`、`Story`、`OKStudio/effects.json`、`StreetSocialCity`、`VideoMotionDemos`。
- 新增、只含名稱與雜湊的清單：`Tools/base_library_sources.txt`、`Tools/paired_sources.json`、`Tools/runtime_clip_sources.txt`、`Tools/original_data_manifest.json`（每個移出檔案的路徑、sha256、大小、類別 A/B、產生步驟）。

## 二、要先改的程式（否則移出後無法建置）

1. `Tools/ok-extract/src/hit_reaction.rs:143,204` 用 `include_bytes!` 嵌入 `BodyInteractions/hit-reaction-v1.json`，檔案不在就連 `ok_extract.lib` 都編不過。改成執行期讀檔，缺檔時停用該功能並寫 log。
2. `Config/DefaultGame.ini` 的 `DirectoriesToAlwaysCook` 含 `/Game/Koikatsu/Data`、`DirectoriesToAlwaysStageAsNonUFS` 含 `base_v1/paired`、`BodyInteractions`、`KKPreview`、`MotionCatalogue`；`RampTexture=KKPreview/MinimalistRamp.png`。目錄不存在時 cook 與 stage 不能失敗（逐項確認，必要時改由還原腳本檢查）。
3. 執行期讀取點缺檔要給明確訊息，例如「原作資料未還原，請執行 `Tools/lua/lua.exe Tools/restore_original_data.lua --game <路徑>`」：`KKCardSource.cpp:43`、`OKStudioCatalog.cpp`、`OKHScene.cpp`、`OKStreetSocialScene.cpp`、`OKBodyInteraction.cpp`、`OKMotionCatalogue.cpp`、`OKCrowdQuality.cpp:112`、`KKAnimationCatalog.cpp:7`。
4. `.gitignore` 加入所有移出路徑；`Tools/check_no_cards.lua`（commit hook）加一條規則：擋下 manifest 裡列的路徑，避免日後又被加回。

## 三、還原腳本 `Tools/restore_original_data.lua`

```text
Tools\lua\lua.exe Tools\restore_original_data.lua --game <原作路徑> [--archive <zip>] [--only <類別>] [--verify] [--threads 8]
```

1. 檢查：原作路徑有 `abdata/`；列出 `mods/` 缺少哪些共用 mod（缺的話只略過那些模型並列出，不中斷）；確認沒有 Unreal 正在使用 `base_v1`。
2. 建置 ok-extract（release，`--features studio-sounds`，`-j 8`）與 `ok-paired-library`，所有呼叫帶 `RAYON_NUM_THREADS=8`。
3. 依序產生 A 類：模型（convert @清單）→ Studio 目錄、圖片、天空、反射、環境、shader 狀態 → Studio 動畫與 variants → 語音、BGM、H 音效 → paired → RuntimeAnimations。每一步寫到暫存目錄，成功後才換進正式位置；步驟可單獨重跑（`--only`）。
4. 有 `--archive` 就解出 B 類到原位置，先核對 zip 裡的 manifest。
5. 需要編輯器的步驟（CrowdBehaviorBake 曲線、官方 Studio 場景匯入）放最後，透過 `Tools/unreal_slot.lua` 拿 slot，用完就關。
6. 對照 `Tools/original_data_manifest.json` 輸出報告：相同、內容不同但可接受（例如 `converted.tsv` 的時間欄、ffmpeg 版本差異）、缺少。`--verify` 時只比對不寫入。

## 四、zip 封存

- 工具：`Tools/pack_original_data.lua --out <zip>`，依 manifest 打包 A＋B 兩類（A 類也放進去，讓沒有原作的機器也能還原；也可以只打包 B 類），zip 內附同一份 manifest。
- 預計大小：A 類約 11.5 GB（okmodel、ogg 大多已壓縮，zip 幫助有限）、B 類約 0.8 GB。
- 存放位置不在倉庫內，建議放在 `D:\OKArchive\OKOriginalData_20261104.zip`，再另外備份到雲端或外接碟。

## 五、版控歷史

- 從 HEAD 移除只影響之後的 commit；`origin`（damody2026/OpenKoikatsu）2026-10-20 起的每個 commit 和 LFS 仍含這些檔案，`damody/OpenKoikatsu` 的 `master2` 備份（正在上傳）也一樣。
- 要真的移除，需要改寫歷史（`git filter-repo` 依 manifest 路徑刪除），強制推送後再處理 GitHub 上的 LFS 物件。GitHub 刪除 LFS 物件只能刪掉整個倉庫或請客服處理，所以實際做法是建一個新的乾淨倉庫，或刪掉舊倉庫重推。
- C／E／F 三個 checkout 都要重新 clone 或 reset 到改寫後的歷史；改寫前先完成一次整合，並暫停所有 agent。

## 六、執行順序

1. **準備**（不動版控）：產生 `original_data_manifest.json` 與三份來源清單；寫 `pack_original_data.lua`，打出第一份 zip 並核對 sha256。
2. **程式修正**：第二節 1～3，三邊建置（`cargo check` 預設與 `--no-default-features`、遊戲與編輯器連結）。
3. **還原腳本**：寫 `restore_original_data.lua`，在乾淨 clone（例如 `E:\OpenKoikatsuClean`）只給原作路徑還原，比對 manifest。
4. **驗收**（乾淨 clone）：`kks-verify`、`okcard-check ... live`、`ok_cards.lua verify` 現有 OK 卡零缺件；`verify_ok_studio.lua`；街區完整重建並啟動沙盒 11/11；`CardReaderDevelopment` 啟動。
5. **移出版控**：`git rm --cached` manifest 列的路徑、更新 `.gitignore` 與 hook，提交並在三個 checkout 同步。
6. **歷史清理**（第五節，另外決定時間）。

## 七、待使用者決定

1. `Localization/*/dialogue.json` 等原作台詞的翻譯，以及 StreetSocial 台詞 JSON，是否一起移出（本計畫預設移出，放 zip）。
2. 從遊戲／mod shader 轉出來的 146 個 `.inl`（`KKRuntimePose`、`KKUnityBundle`、`OKStudio`，編譯必需），以及骨架名稱、rest pose 這類小型資料，要留在版控，還是改成還原時產生（後者會讓沒有原作的人無法編譯）。本計畫預設先保留。
3. 共用 mod 衍生的模型（uncensor、KKS_Fixes、ME shader、ramp 等 134 個）是否也算「原作資料」移出（本計畫預設移出，還原時從遊戲 `mods/` 產生）。
4. 是否做第五節的歷史改寫與新倉庫，以及 `master2` 備份是否保留。
5. zip 的存放位置。
