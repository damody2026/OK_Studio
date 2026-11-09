# 協調者交接（2026-10-27）

這份文件給接手「協調者」工作的人或 session：負責同步 C／E 兩份 checkout 與兩個引擎、整合時重新編譯與 cook、管理四個工作 agent、每十分鐘巡檢。

## 1. 目前狀態（2026-10-27 上午）

| 項目 | C | E |
|---|---|---|
| 路徑 | `C:\portable\OpenKoikatsu` | `E:\OpenKoikatsu` |
| 分支 | master | duo2（master、duo 指向同一個 commit） |
| HEAD | `fa0bd827`（R3-239） | `fa0bd8276`（同一個 commit） |
| 引擎 | `D:\PhysX\UE5.8` | `E:\PhysX\UE5.8` |
| 引擎 HEAD | `11576da86`（分支 `UE5.8-physX-5.11-ok`） | 同左 |
| StreetSocial base | `Saved/StreetSocial/Base1026c` | `Saved/StreetSocial/Base1026c` |
| 最新 stage | `Gest127.stage`（攻略 session 打的 exe-only） | `Fix1027M.stage`（galgame 打的 exe-only） |
| `local-instance.json` | 預設 | `port_base 47960`、`voice: true` |

- origin 的 master 與 duo2 都在 `fa0bd827`；引擎和遠端 `ok` 一致。
- 四個 repo 都沒有 worktree，也沒有 stash。
- C 和 E 的 10 張街區女主卡（`Content/CharacterCards/StreetHeroines/`）sha 一致。
- **上次完整重新編譯與 cook 是 2026-10-26 的 `Int1026cC`／`Int1026cE`。** 這次 10-27 的整合，使用者中途說「同步完後停下」，所以只做了同步，沒有重新編譯和 cook。
- 巡檢排程已停（cron 只存在協調者 session 內，關掉就沒了）。
- 暫停中：galgame、TTS、街區攻略。街道城市照使用者指示沒有暫停，仍在工作。

### 工作目錄裡未提交的改動（都不是協調者的，整合時不要提交）

**C：**
- `Source/OpenKoikatsu/OKGalleryWidget.cpp`：讀卡器水槍載入修正（E-250），來源不明，一直保留。
- `Source/OpenKoikatsu/OKCharacterMCP.cpp`：來源不明。
- `Docs/ERROR_LOG.md`：以 HEAD 為底，檔尾接了別的 session 未提交的條目，相對 HEAD 只新增、不刪。
- `Docs/STREET_ERRORS.md`、`Docs/OK_BASE_LIBRARY_PLAN.md`：各 session 未提交的紀錄。
- `Docs/StreetSocialCity/*`、`Tools/street_city_*.lua`、`Tools/remesh_street_city_asset.py`：街道城市 session 的檔案。使用者指示不提交。
- `OKExtractBuildStamp.h`：建置自動產生，照規矩不提交。

**E：**
- `Tools/ok-extract/{Cargo.lock,Cargo.toml,src/appearance.rs,src/appearance/properties.rs,src/lib.rs,src/session.rs}`，以及未追蹤的 `src/bin/ok-chara.rs`、`src/okchara.rs`：已封存的「新版 OK 卡」session 留下的工作，從 10-25 起一直保留。
- `Docs/ERROR_LOG.md`：同 C 的處理方式。
- `OKExtractBuildStamp.h`。

## 2. 四個 agent

| Session | ID | 範圍與目前狀態 |
|---|---|---|
| [E組] galgame 對話演出（ok-story） | `local_e1ab64e1-1121-47b8-9dfd-826b83310c4c` | E 線：1 對 1、galgame 對話演出、120 FPS、嘴型。最後 commit `b029dd755`。暫停中，沒有未提交的程式。 |
| [E組] TTS 優化計畫文件+女主唱歌 | `local_d15c5307-f14a-4241-939e-29e27a94fdc2` | ok-tts／ok-song／ok-asr。**使用者決定優化清單暫停，只修遊戲裡實際出現的 bug**，閒置是正常的。最後 commit `4303e3c5f`。暫停中。 |
| [C組] 街區攻略：十位女主循環測試與修正 | `local_f3c6ce71-1f4f-4190-8085-72f919946e0d` | C 線：街區規則與遊玩（R3 編號）。最後 commit `fa0bd827`（R3-239）。存檔在 slot3。暫停中。 |
| [C組] 街道城市三腳架裝飾交接 | `local_b47b0eca-c21c-4df5-955a-0a2e3e923feb` | 街道城市（StreetSocialCity）的商店街、旅館、宿舍、教室擺設。**使用者指示一律不 commit**。目前在工作：教室掛件驗收、50 件 Tripo 旅館家具（已送出，每件 30 點，共 1500 點；使用者上限 50 件）。 |

其他 session（不要管）：`剪貼簿貼上失敗`、`專案轉換為 Unreal C++`（使用者自己的 MyProject，Epic 版 UE5.8，用的是 `C:\Program Files\Epic Games\UE_5.8`）、`StreetSocial.cmd 遊戲流程文檔`。

## 3. 給 agent 的固定規則（轉達時沿用）

- 24 小時無人值守、遇到問題自己判斷、不找使用者確認、要通用解、錯誤寫進 md。
- 卡住時每十分鐘檢查一次（背景指令或約 600 秒的喚醒），不要空等，也不要前景 sleep。
- 只提交自己的 hunk；角色卡和 OK 卡不進版控（pre-commit hook 會擋）。
- 錯誤紀錄要在**最新版本**上追加，不要從舊副本覆寫（10-26、10-27 都發生過，`ERROR_LOG.md`／`STREET_ERRORS.md` 被舊版蓋掉）。
- 不要關使用者可能在玩的遊戲，只關自己開的 PID。
- 同一個引擎不要兩個 session 同時打包；E 引擎上，街道城市要 cook 前先確認沒人在打包。
- 平常打包沿用 base（`--base-dir Saved/StreetSocial/Base1026c`，`--skip-cook --skip-base`，新 tag）。完整 cook 只在整合時做。
- 量 TTS 順暢度時，只能有一個 Unreal 遊戲在跑（兩個遊戲搶 GPU，ok-tts 會斷流）。

## 4. 十分鐘巡檢

用 `CronCreate` 建排程（分鐘 `3,13,23,33,43,53`），prompt 內容如下：

> 【協調者十分鐘巡檢】用 mcp__ccd_session_mgmt__list_sessions 檢查四個 agent（ID 見上表）。對每個 isRunning=false 且 lastActivityAt 超過 10 分鐘的 session，用 list_events（limit 3～8）看它最後說什麼：在等排程喚醒、建置或遊戲且說明合理的，就不打擾（超過 30 分鐘沒進展才叫它檢查一次）；停下來問問題、等確認、說「我繼續」卻結束回合、或沒交代就停的，用 send_message 叫它照規則自己判斷後繼續。例外：使用者本人要它暫停的工作（TTS 的優化清單）不要叫它重啟。真正只有使用者能決定的事，記下來告訴使用者。不要動 StreetSocialCity，不要讓兩個 session 同時打包同一個引擎。最後用一兩句繁體中文回報。

- 整合期間先 `CronDelete` 停掉巡檢，否則它會叫醒暫停中的 agent；整合完、恢復 agent 時再重建。
- 使用者只留部分 agent 時，把 prompt 改成只看那幾個。
- 常見情況：agent 回報「接下來我繼續…」卻結束回合。這時就叫它直接開始做。

## 5. 整合流程（使用者說「現在整合 C <=> E、D 引擎 <=> E 引擎…」）

1. **暫停 agent。** `CronDelete` 停巡檢。對 galgame、TTS、攻略各送暫停訊息，請它們：commit＋push 已驗證的工作（只自己的 hunk）、未完成的不要提交並回報清單、關掉自己的遊戲和 ok-tts／asr／song、UAT、cargo、排程喚醒，回報後停下。街道城市通常不暫停，只請它在通知前不要在 E 引擎上 cook／UAT，記憶體壓在 40 GB 內。某個 session 正在跑很長的一輪時，用 `stop_session` 中斷，讓排隊的暫停訊息先執行。
2. **盤點。** 對兩個 repo 執行 `git fetch origin`，看 `HEAD...origin/master`、worktree、stash。兩個引擎執行 `git fetch ok` 後比對 `UE5.8-physX-5.11-ok`。**比對兩邊 `StreetHeroines` 的女主卡 sha**；不同時把新轉的版本複製過去，okId 要對得上 `Profiles/apng-<id>.json`。
3. **同步。** 未提交的檔案先備份到 scratchpad，`git stash push -u -- <檔案>`，`git merge --ff-only origin/master`，再 `git stash pop`。E 另外要 `git branch -f master origin/master`、`git branch -f duo origin/master`、`git push origin duo2`。
   - **要注意：** stash pop 會把工作副本的改動三方合併到新 HEAD 上。**不要再用合併前的備份去覆寫**，那會把剛同步進來的行刪掉（10-27 犯過）。最多用備份來還原 CRLF 被改掉的未追蹤檔。
   - 錯誤紀錄 md 發生衝突時，用「以 HEAD 為底，把工作副本多出來的行接在檔尾」的方式合併。合併後用 `git diff --numstat HEAD` 確認刪除數是 0。
   - 索引裡若有比 HEAD 舊的項目（狀態顯示 `MM`），用 `git reset -- <檔>` 重設，工作檔不會被動到。
4. **重新編譯。** 刪掉兩邊的 `Saved/StreetSocial/Build/StreetDisplay26HG.patch`（先刪 pak 再 rmdir），讓啟動器重建材質 patch。對 `Tools/ok-tts`、`ok-asr`、`ok-song` 跑 `cargo build --release`，和 `Build/<x>/<x>.exe` 比對，不同才複製（C 和 E 都要做，E 現在也有 `Build/ok-tts`、`Build/ok-asr`）。兩邊的建置用 PowerShell `Start-Process` 在背景平行跑：
   - C：`D:\PhysX\UE5.8\Engine\Build\BatchFiles\Build.bat OpenKoikatsuEditor Win64 Development -project=C:\portable\OpenKoikatsu\OpenKoikatsu.uproject -waitmutex -NoHotReloadFromIDE`，接著 `Tools\lua\lua.exe Tools\rebuild_street_social_runtime.lua --tag Int<日期>C --engine D:/PhysX/UE5.8 --base-dir Saved/StreetSocial/Base<日期>`
   - E：同上，但改用 E 的引擎、`E:\OpenKoikatsu\Tools\lua\lua.exe`、tag `Int<日期>E`。
   - 用 `Rebuild-<tag>/cook.log` 裡的 `Packages Cooked: 1240 … Success - 0 error(s)` 確認 cook 成功。
5. **實際啟動驗證（一定要做，要截圖）。**
   - 讀卡器：設 `OK_AUTO_SEQUENCE=C000`，執行 `Tools\run_card_reader_development.lua -NoBuild -- -ExecCmds=ok.FaceFlatten`。log 要出現 `ok.FaceFlatten = "0"` 和 `OK preview render readiness`，再用 PrintWindow 截圖。
   - StreetSocial：`Tools\run_street_social_development.lua -Control -Sandbox Verify<日期> -PortBase 48100 -Exec ok.FaceFlatten`（E 用 `48200`）。用 `Tools/ok-game-mcp/target/release/ok-game-mcp.exe call ...`，`OK_CONTROL_PORT` 設 48110／48210，依序 `game_click 中午` → `game_goto` → `game_key E` → `game_screenshot`。確認畫面有立繪、TTS 伺服器就緒，log 有新 tag 和 `ok.FaceFlatten = "0"`。
   - 驗證完只關自己的 `game.pid`。
6. **清理。** 用不跟隨 junction 的 `Kill-Path`（遇到 reparse point 只解除連結）刪掉舊的 `*.stage`、舊的 `Base*`、舊的 `Rebuild-*`。只保留新的 stage 和 base。
7. **還原與恢復。** 確認未提交檔都還在。更新記憶 `conquest-builds-on-d-engine.md` 和 `MEMORY.md` 裡的 base 名稱。對各 agent 送「整合完成，請恢復」，附上新的 stage 和 base。重建巡檢 cron。使用者說「做完先不要恢復」或「同步完後停下」時，就停在那一步。

## 6. 需要使用者處理或決定的事

- 街道城市的工作（商店街、旅館、宿舍、教室、泳池斜坡等）全部還沒 commit，是否提交、何時提交由使用者決定。
- 旅館家具 Tripo：使用者 10-27 定的上限是 50 件，已經送出 50 件，不能再多生成。商店街另有 100 件的上限。
- E 的 `local-instance.json` 已改成 `voice: true`，E 遊戲會自己開 ok-tts（47960）和 ok-asr（47961）。即時語音辨識用的是實體麥克風，房間裡的說話聲會被當成台詞送出，可以在右側面板換麥克風。
- 這次整合沒有重新編譯和 cook。下次整合要跑完整流程，產生新的 `Int<日期>C／E` 和新的 base。

## 7. 各 agent 的交接

協調者自己的 session 是「[已完成] C/E 專案與引擎同步、工作分配」（`local_017c550a-c101-4c2d-9793-ff18dd2feeda`），其他 session 傳來的訊息會標成這個名字。

### 7.1 [E組] galgame 對話演出（ok-story）— `local_e1ab64e1-1121-47b8-9dfd-826b83310c4c`

- **範圍**：E 線，包括 1 對 1 場景、街區 galgame 對話演出（立繪、鏡頭、群聊）、嘴型、120 FPS、E 的 TTS／ASR 接線。在 E（`E:\OpenKoikatsu`，E 引擎）工作，要用 E 的 `Tools\lua\lua.exe`。
- **狀態**：暫停中，沒有未提交的程式。最後 commit 是 `b029dd755`。E 目前最新的 stage 是 `Fix1027M`（Base1026c）。
- **10-26～27 完成並推送**：
  - 1 對 1 張嘴時臉變黑，原因是工作執行緒退回到沒擺姿勢時的包圍盒，臉被剔除。已改在 `KKRuntimeSkinBounds`（`064080221`）。C 已確認有效。
  - 廣場黑球改成金色發光球。
  - 群聊時遊戲給女主的提醒加上「給{名字}的提醒」前綴（`4666326a0`）。
  - 走過來的女主不會打斷 1 對 1（`c84f87ea3`）。
  - E 的 ASR 誤連到 C 的埠，啟動器改成優先用自己的埠（`41e6eeb06`）。
  - 話題改成排在她的回覆之後（`1d6ac29dd`）。
  - 餐廳菜單改成畫面中央的卡片（`c0794b4bb`／`41f568c2e`）。
  - 送禮改成她自己回應收或不收，不再 15 秒自動收下（`78572fa91`）。
  - 對話鏡頭改成能把她從頭到腰放進畫面，先拉寬視角，不夠才退到他右肩後（`1159f49af`／`b029dd755`）。
  - 「餵～」自動改成「喂～」（`5c8c6c1e0`）。
  - 打電話時她的語音改成聽筒模式（不做空間化，`167adccb1`）。
  - E 的 `local-instance.json` 改成 `voice: true`，並建好 `Build/ok-tts`、`Build/ok-asr`（本機設定，不進版控）。
- **交接文件**：`E:\OpenKoikatsu\Docs\ONEONE_BLACK_FACE_HANDOFF_20261026.md`（未追蹤，已完成）、`Docs/GALGAME_STREET.md`、`Docs/STREET_120FPS_20261025.md`。
- **下一步**：繼續換女主實玩 1 對 1 和 galgame（換還沒測過的女主、用新存檔，避免記憶污染），找到實際問題就修。使用者看過菜單卡和對話鏡頭的截圖後，可能會直接在這個 session 提意見。
- **注意**：它曾經關掉使用者正在玩的遊戲，只能關自己 `game.pid` 裡的 PID。量 TTS 時只能開一個遊戲。它很常回報完就停下，巡檢時要叫它繼續。

### 7.2 [E組] TTS 優化計畫文件+女主唱歌 — `local_d15c5307-f14a-4241-939e-29e27a94fdc2`

- **範圍**：`Tools/ok-tts`、`ok-song`、`ok-asr`，以及女主唱歌的遊戲端。**使用者 10-25 決定暫停優化清單，只修遊戲裡實際出現的 bug**，所以閒置是正常的，不要叫它重啟優化清單。
- **狀態**：暫停中，沒有未提交的檔案。最後 commit 是 `4303e3c5f`（唱歌時鏡頭被牆擋住會換角度）。
- **已完成**：
  - 0.6B 評估的結論是維持 1.7B。`OK_TTS_BASE_MODEL` 可以切換，試聽頁在 `E:\OpenKoikatsu\Saved\TTS\VoiceCheck-20261025-0.6B\index.html`。
  - 唱歌：歌做好後她會自己走過來唱；男主退到她前方約 2.3 m、兩人面對面；字幕依她實際唱的內容對時（要用 ok-asr 的 `/transcribe_spans`）；唱完有「♪ 再聽一次」；撤回了「日常對話不出聲」。
- **還沒在遊戲裡驗證**：歌詞依實際演唱細切對時，目前只有離線驗證過。使用者下次在 C 遊戲裡聽歌時若字幕對不上，交給它修。
- **部署注意**：改了 ok-tts／ok-asr／ok-song 之後，整合時要重新 cargo build，換進兩邊的 `Build/<x>/`。

### 7.3 [C組] 街區攻略：十位女主循環測試與修正 — `local_f3c6ce71-1f4f-4190-8085-72f919946e0d`

- **範圍**：C 線街區（大世界）的規則與遊玩。自己玩十位女主，發現問題就修，問題用 R3 編號記在 `Docs/STREET_PLAYTEST_FINDINGS.md`。規則寫在 Rust（`Tools/ok-rules`），C++ 只負責呈現。用 D 引擎打 exe-only stage（`Gest*`，Base1026c）。
- **狀態**：暫停中，存檔在 slot3。最後 commit 是 `fa0bd827`（R3-239），之前是 `ffb1877b`（R3-235～238）。沒有自己未提交的檔案。C 目前最新的 stage 是 `Gest127`。
- **10-27 這輪**：
  - **R3-235**：菜單沒有的品項，她要直說，並問他要不要相近的。改了三種語言的提示詞，還沒確定遊戲裡讀到的是新文案。
  - **R3-236**：活動中才約好的「之後見」，不再被當成提早完成而消失。Gest127 已重測過。
  - **R3-237**：「他近來在讀的書」改成「書不在手上」，避免她誤以為他正在看書。三種語言的文案都改了，**還沒在遊戲裡重測**。
  - **R3-239**：下雨時，空閒的女主改去同時段最空的室內地點，不再全擠進書局。cargo 排程測試 13 項都通過，**還沒在遊戲裡重測**。
  - **R3-238（未修）**：在咖啡廳和惠惠一起時存檔、讀檔，她會被放回宿舍。原因是存檔只記他的位置，要另外做。
- **更早**：R3-226～233，包括請客記錄、1 對 1 的「離開」按鈕和 `/private` 端點、她主動想親密時先問他、傳訊息約他後在原地等 40 分鐘、檢視模式（`StreetSocial.cmd -Inspect N`、MCP `game_inspect`）等，詳見 FINDINGS。
- **下一步**：在遊戲裡重測 R3-237 和 R3-239，修 R3-238，之後繼續十女主循環。
- **注意**：它的遊戲會帶起 ok-tts／asr／song。打包 D 引擎前，協調者要先跟它說。它的回報有時是簡體中文。

### 7.4 [C組] 街道城市三腳架裝飾交接 — `local_b47b0eca-c21c-4df5-955a-0a2e3e923feb`

- **範圍**：使用者的另一個 UE 專案 StreetSocialCity，在 `E:\StreetSocialCityProduction`，用 E 引擎。負責商店街、汽車旅館、宿舍、教室等的擺設與驗收。工具在 C 的 `Tools/*street_city*`，產物放在 `C:\portable\OpenKoikatsu\output\street-social-city-production\`。**使用者指示一律不 commit**，協調者也不要動 StreetSocialCity。
- **狀態**：仍在工作，沒有暫停。目前在跑教室掛件（公告欄、時鐘、掛圖）的打包版實走驗收，cook 已經跑完。
- **已完成並驗收**：
  - 商店街 96 間改造、94 間入口掃掠全通過。
  - 汽車旅館 57 間量產房、燈光與燈帶修正、第二批招牌擺設、浴缸、家具密度。
  - 宿舍 D1～D4 和行政樓的擺設。
  - 泳池台階：第一次卡住是卡頓幀造成，加了 8 道隱形斜坡；之後 203 池內斜坡又卡住，改了邊緣算法並抬高斜坡。
  - 歷次完整實走都是 79/79、0 次輔助跨步。
- **Tripo**：旅館家具已送出 50 件，每件 30 點，共 1500 點（帳戶 7095 → 5595），**已達使用者訂的 50 件上限，不能再生成**。接下來要下載、用 instant-meshes-rs remesh、匯入（只用 Editor，不打包）。商店街另有 100 件的上限。
- **進度文件**：
  - `Docs/STREET_CITY_IMMERSIVE_LIFE_PLAN_20261024.md`：第 10 節，含 10.5、10.6。
  - `Docs/STREET_CITY_MOTEL_ROOM_FIDELITY_PLAN_20261025.md`：第七節、七之二。
  - `Docs/STREET_CITY_MOTEL_ROOM_SPEC_20261025.md`：第 10、11 節。
  - `Docs/STREET_CITY_SHOP_STREET_SPEC_20261025.md`：第 9 節。
  - 錯誤紀錄在 `Docs/STREET_ERRORS.md`。
- **注意**：
  - Editor 用 d3d12 開地圖就要約 70 GB 記憶體，所以實拍改用打包版。它有記憶體監看，超過 60 GB 會自動停（整合期間是 40 GB）。
  - 它的 cook 中間檔已改成放在 E 槽、成功後自動刪除。D 槽曾一度只剩 0.5 GB。
  - 驗收開頭的輸入檢查（按 W 前進、Shift 加速）偶爾會失敗，重跑就過；GPU 負載高時比較常發生。
  - 協調者要整合時，只請它不要在 E 引擎上跑 cook／UAT，不用暫停它。

## 8. 相關文件與記憶

- `AGENTS.md`：打包流程，以及「完整流程只在整合時跑」。
- `Docs/DUAL_LINE_DEVELOPMENT.md`：C／E 雙線開發的規則。
- `Docs/ERROR_LOG.md`、`Docs/STREET_ERRORS.md`：錯誤紀錄。
- `E:\OpenKoikatsu\Docs\ONEONE_BLACK_FACE_HANDOFF_20261026.md`：1 對 1 臉黑問題的交接（已修好，修正是 `064080221`）。
- `Docs/STREET_CITY_IMMERSIVE_LIFE_PLAN_20261024.md`（第 10 節）、`Docs/STREET_CITY_MOTEL_ROOM_FIDELITY_PLAN_20261025.md`、`Docs/STREET_CITY_SHOP_STREET_SPEC_20261025.md`、`Docs/STREET_CITY_MOTEL_ROOM_SPEC_20261025.md`：街道城市的進度。
- `Docs/STREET_PLAYTEST_FINDINGS.md`：攻略的 R3 清單。
- 協調者記憶：`full-rebuild-only-at-integration.md`（含女主卡比對）、`stuck-check-every-10-min.md`、`conquest-builds-on-d-engine.md`、`city-tripo-cap-50.md`、`shop-street-tripo-cap-100.md`。
