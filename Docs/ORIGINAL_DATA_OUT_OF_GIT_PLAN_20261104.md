# 原作資料移出版控計畫（2026-11-04）

目標：版控只留專案自己的程式與內容。原作（KKS `abdata`、遊戲 `UserData`、語音）與第三方 mod 衍生的資料全部移出 git，另外打包成 zip 保存。新增 `Tools/original_data.lua`：只要指定原作路徑，就能把整套 OK 共用資料還原到可以建置、遊玩的狀態。

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

## 二、實作（2026-11-04，C）

使用者決定：台詞翻譯一起移出；146 個 shader `.inl` 保留；共用 mod 衍生的模型移出；改寫歷史並 force push 到 `damody2026/OpenKoikatsu`；zip 放 `F:\backup` 並要測試過。先只處理 C，E、F 不動。

| 項目 | 內容 |
|---|---|
| 清單 | `Tools/original_data_manifest.json`：32,229 檔、13.30 GB（路徑、bytes、sha256、群組）；目前所有 LFS 檔（9,944 個）都在其中，sha256 與 LFS oid 全部吻合 |
| 轉換用名稱清單 | `Tools/original_data/model_sources.txt`（610 個來源標籤對應 626 個模型）、`paired/manifest.json`＋`editor-demos.json`、`runtime_clips.tsv`（81 個） |
| 腳本 | `Tools/original_data.lua`：`manifest`、`pack --out <zip>`、`verify [--root]`、`test-archive <zip> <空資料夾>`、`restore [--game <原作>] [--archive <zip>] [--only/--skip <步驟>]` |
| zip | `F:\backup\OKOriginalData_20261104.zip`（9.83 GB）。由 `ok-luakit zip-create` 寫出（Windows 的 tar 讀不了含日文檔名的清單），Zip64、UTF-8 檔名 |
| 程式修改 | `hit_reaction.rs` 測試改在執行期讀 BodyInteractions（檔案不在就略過）；`export_street_animation_library.lua` 改用 `ok.root` 並加 `--exe`；`ok-luakit` 加 `zip-create`／`zip-extract`，順手修 `shader.rs` 一個原本就編不過的借用 |
| 版控 | `.gitignore` 加入整段路徑；commit hook（`Tools/check_no_cards.lua`）擋下這些路徑 |

restore 的步驟：`tools`（建 ok-extract `--features studio-sounds` 與 ok-paired-library，`-j 8`）→ `models` → `studio` → `sounds` → `anims` → `paired` → `runtime-clips` → `archive`。某一步失敗只記下來，它負責的檔案改由 zip 覆蓋；最後對照 manifest 報告相同／不同／缺少。

## 三、驗證結果

| 測試 | 結果 |
|---|---|
| zip 解到空資料夾 | 32,229 檔 sha256 全部吻合 |
| 乾淨 clone（`C:\portable\OKZipTest`）＋只用 zip 還原 | 2.8 分鐘，32,229 檔全部吻合 |
| 同一個 clone 建置編輯器（D: 引擎） | 成功。需要另外放本機商用外掛 `Plugins/BpGeneratorUltimate`（含 Binaries，本來就不進版控） |
| 同一個 clone 的 OK Studio | SceneEditor 開 Addiction 場景，VMD 動作、音訊、MMDD 鏡頭都匯入，播放正常 |
| 同一個 clone 的街區遊戲 | 完整打包（cook 0 錯 0 警告），沙盒啟動 11/11 角色就緒、0 個缺模型，走到雷電將軍旁按 E 交談正常。需要先 `cargo build --release` 建 `Tools/ok-rules`；TTS、ASR、唱歌伺服器沒建，改用內建人聲 |
| 乾淨 clone（`C:\portable\OKRestoreTest`）＋`--game D:/KoikatuSunshine`＋zip | 跑完 0 缺檔。`studio` 一步失敗（這台遊戲缺 `abdata/studio/map/minsyukulobby_studio.unity3d` 的 `t_ks_r08_outview` 貼圖），改從 zip 補。重新產生的檔案有 14,706 個 bytes 和 manifest 不同：模型 551、Studio 語音 8,346（重新編碼）、Studio 動畫 5,805、paired 2、索引 2；街區動畫片段全部相同。這份重新產生的資料庫沒有實際開遊戲驗證 |
| C 遊戲與編輯器建置（D: 引擎） | 成功；`cargo check` 預設與 `--no-default-features` 通過，`hit_reaction` 測試 7 個通過 |

結論：**source＋zip** 可以還原成能玩遊戲、能用 OK Studio 的專案（已實測）。**只給原作路徑**能產生 A 類的大部分檔案，但不是逐位元相同，B 類一定要 zip；要把它當成正式還原方式，需要另外驗證重新產生的模型與語音。

## 四、版控歷史

- 改寫前先把舊歷史備份到 `https://github.com/damody/OpenKoikatsu` 的 `master2`（`8a57fc422`，含全部 LFS）。
- 用 `git filter-repo --invert-paths` 在另一個 bare clone 刪掉原作資料路徑，另外刪掉歷史裡曾提交過的 `Content/CharacterCards/`（角色卡本來就不能進版控）。1,319 個 commit 裡已找不到這些路徑；最新 commit 的 tree 與改寫前相同。
- force push：`damody2026/OpenKoikatsu` 的 `master`、`duo2` → `8f603d99`，`feat/mmd-vnge-support` → `2fcc1084`。GitHub 上 `refs/pull/1/head`（PR #1）仍指向舊歷史，這個 ref 無法從 git 刪除；舊的 LFS 物件也還在 GitHub 的 LFS 儲存空間，要完全清掉只能刪倉庫重建或請 GitHub 客服處理。
- C 已 `reset --mixed` 到新的 `master`（工作樹不動）。**E、F 還在舊歷史**：之後要 `git fetch` 後 reset 到新的 `origin/duo2`，不能 merge 舊歷史（會把原作資料帶回來）。E、F 的原作資料檔案仍在各自磁碟上，reset 時用 `--mixed` 或 `--soft` 保留。

## 五、新 checkout 的準備

```text
git clone https://github.com/damody2026/OK_Studio.git
Tools\lua\lua.exe Tools\original_data.lua restore --game <原作>
（或）Tools\lua\lua.exe Tools\original_data.lua restore --archive <開發資源 zip> [--h-voices <H 語音 zip>]
```

另外需要本機的：`Plugins/BpGeneratorUltimate`、`Tools/engine.local.json`、街區用的角色卡（`Content/CharacterCards/StreetHeroines/`、`output/StreetSocialAPNG/Male01.png`），以及 `Tools/ok-rules` 的建置。

## 六、C／E／F 同步到新歷史（2026-11-04 下午）

公開倉庫改成 `damody2026/OK_Studio`，E、F 的 `duo2` 已 reset 到新歷史，檔案都留在磁碟上。交接見 [AGENTS_HANDOFF_20261104B.md](AGENTS_HANDOFF_20261104B.md)。

| 測試 | 結果 |
|---|---|
| 乾淨 clone＋只用遊戲（`--game D:/KoikatuSunshine`）＋zip | 還原完成，0 缺檔；修掉 5 類缺檔（Studio 缺貼圖中斷、`.ok_cache.sqlite` 舊路徑、街區片段清單、`shared-ignore`、manifest 裡的孤兒模型） |
| 開發資源 zip、H 語音 zip | `test-archive` 通過（15,906 檔、121,565 檔） |
| 乾淨 clone 的 `kks-verify`、`okcard-verify`（5 張原作卡） | 各 4/5 相同，`okcard-verify` gaps=0 |
| `Relife - 日代千鹤.png` | 乾淨 clone 與完整本機庫都 DIFFERENT：卡片用到沒有指名的 zipmod（`[cbr95810] pubic hair v1.0`），不是這次造成的 |
| C 完整本機庫的 `kks-verify`（同 5 張，對 `D:/KoikatuSunshine`） | 5 張都 DIFFERENT，原因沒查出來。這份庫留著舊的非共用模型（misses 比乾淨 clone 少幾百個），原始來源 `C:\portable\KoikatuSunshine` 已不存在，無法對照。只影響在 C 用本機庫把原作卡轉成新 OK 卡；既有 OK 卡只讀共用資源，不受影響 |
| C `Int1104NC`、E `Int1104NE` 完整打包 | cook 0 錯，修卡後沙盒啟動 11/11、0 個缺件 |
| F `verify_ok_studio --tag Int1104NF` | 全部通過 |

只靠遊戲還原還有兩件事沒做到：16 個只在 zip 裡的檔案沒有轉換器；沒有 H 語音時 H 場景無聲這件事只看過程式，沒有實際跑過。Gallery 的一般語音仍讀 `voice_extract`。
