# 街道城市：11-02 重拍後的地圖剩餘項目（2026-11-02）

使用者 2026-11-01 決定 `StreetSocialCity/` 整個資料夾不要動，所以這些項目原本只在 `C:\portable\OpenKoikatsu` 版控內準備。**2026-11-02 使用者直接允許用編輯器 job 改地圖**（只改場景、不動 C++，`StreetSocialCity/` 仍不進版控），以下各項已寫進 `StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap`。每個安裝前都把地圖備份到 `output/street-social-city-production/world-edge-v1/UniversityCity-before-<項目>-<sha>.umap`，並在同一個資料夾寫收據。

Native job 一律用 `Tools\lua\lua.exe Tools\street_city_motel_job.lua <job> <payload>`，必須先拿到 Unreal slot 並啟動 motel 編輯器 worker（`motel-v1/serve-ready.json` 為 passed）。

## 已安裝

| 項目 | 原因 | 做法 | job／工具 |
|---|---|---|---|
| 世界邊緣山丘（G084、G088、G134、G150 的地平線一片平地） | skirt 原本只有一段 35–80 m 的起伏，要到 2.5 km 外才升滿，從街上看仰角不到 2° | 150–900 m 升起 25–80 m 的近丘，1.2 km 外再疊 70–190 m 的遠山脊，最高約 236 m；仍是 NoCollision，只是視覺 | `Tools/build_street_city_world_edge.lua` → `world_edge_install`（`street_city_world_edge_payload.lua`） |
| 道路斷頭（A04 斜路等） | 道路片 `DepthStableStreet_*` 沒有碰撞，路面是 G?? 地面抬到 1205（草地 1198），所以用地面高度找路 | `world_road_raster_probe` 量 2 m 一格的地面 → `Tools/find_street_city_road_ends.lua` 找出寬度至少 8 m 的直路末端（排除 L 形轉角、路口、步道、通到水邊或城外的路）。兩個互相面對、距離 100 m 內的末端用路面接起來，前方 100 m 內有路的也接上，其餘放迴車圓環（半徑 max(12 m, 0.75 × 路寬)）。路面用地面本身的柏油 MI（`MI_Detail_932bc009ac742438e2bf`），4 cm 厚、有碰撞、可走 | `world_road_ends_install`（`street_city_world_gaps_payload.lua`） |
| 地標碰撞 | 32 個 `Landmark_*` 全都是 NoCollision，玩家會穿過去 | 每個模型都已經帶一個凸包；元件改成 BlockAll、只用簡化碰撞，角色不能踩上去 | `world_landmark_collision` |
| 大片空草地（A13、A17 北側） | 250 m × 200 m 的空草地看起來像沒做完 | 全城 5 m 一格，樹叢只種在距離任何東西 25 m 以上的空草地（判斷方式：往下打到的是 G?? 地面且高度在街面，格子裡也沒有 actor 或 instance）。樹叢之間至少隔 70 m，每叢最多 16 棵，用城裡原有的樟樹 a/b/c 與白花、金花樹，離道路與物件至少 12 m。每棵樹另放一根隱藏的樹幹碰撞（和街樹同尺寸）。共 31 叢，多數落在城市邊緣，剛好蓋住地面在城界上的切邊 | `world_groves_install` |

## 驗收（11-02）

- cook：`motel-v1` 套件 `20261102-120404`（地圖 `d21219de3c65`），audit、routes、physics_plan、mirror migration 全部通過。
- 實走：4 段（`slice 0..3 4`）都通過，0 次協助；收據為 `motel-v1/physics-20261102-121315.json`、`-123259.json`、`-130111.json`、`-132047.json`（slice 0 開場 14 fps，仍一次通過）。
- slice 0 開場 14 fps 的原因：開場 fps 一律在同一個 player start 量，同一個套件、同一張地圖下，四段依時間先後是 49、46、32、14 fps，一路往下掉；整段超過 100 ms 的幀數，slice 0 是 159，今早安裝前的第 3 段是 216，看不出新增的物件讓它變差。比較可能是同一時間機器上還有其他 Unreal 遊戲在搶 GPU，或 shader 還在暖機。之後量效能要照 `Docs` 的單一遊戲規則，不要拿這個數字當效能證據。
- 重拍：`shop-survey-v1/captures-20261102-131804`（20/20）。A04 斜路末端已經有迴車圓環；G084 地平線現在是一道低山脊（仍偏平緩）；A13、A17 已經有樹叢，但 A13 中央大部分還是空的，因為樹叢多半落在城市邊緣。
- `Landmark_stage_92` 擺在 S18 第 10 號車庫的進出路線上，開了碰撞之後 route review 會失敗，所以它維持 NoCollision，記成擺錯位置（見下方）。

## 第二輪（11-02 下午）

| 項目 | 原因 | 做法 | job／工具 |
|---|---|---|---|
| 海灘內緣方格階梯 | `world_ground_sections_probe` 讀 G01–G16 網格的材質分區（1 m）後發現：G04 地面本身有海灘沙分區，在 y 940–1060 m 一帶往內陸延伸到 x 115–120 m，3 m 一階，超出沙條內緣（x 103–112 m），從空中看到的階梯就是它。早上把沙條墊高 12 cm 沒用，是因為原因根本不在沙條 | 沙條建置讀 `ground-sections.json`：每個線上點沿內側法線找到最遠的沙格，再加 1.5 m，至少 `--inland`；先取 ±15 m 的最大值，再做 ±10 m 平均，所以不會退到沙格裡面，邊緣也沒有階梯。重新安裝後探測 A04 的內緣在 x 117–123 m，平滑、蓋住沙區 | `world_ground_sections_probe` → `Tools/build_street_city_shore_strip.lua` → `world_coast_strip_install` |
| A13 中央空地 | 上一版把城界外當成空地，所以樹叢擠在城市邊緣 | 距離場把城界也當成有東西；重種後 22 叢，南側的樹叢落在離城界 30–40 m 的帶上，也就是 A13 草地所在的位置 | `world_groves_install` |
| `Landmark_stage_92` 在 S18 車庫路線上 | 先開碰撞、重跑 routes，拿到被擋住的點 | 搬到 80 m 內最近的空草地（足跡外擴 3 m 全落在街面草地上，也沒有壓到其他物件），保留朝向，然後開碰撞。實際移了 20 m（到 45373, 53314），routes 重跑通過 | `world_landmark_relocate` |
| `Landmark_playground_a_98` | 它沒有浮空，而是站在 Campus_D3_F06 的屋頂上（z 34.2 m），玩家到不了 | 搬移規則加一條「屋頂」：底下不是 G?? 地面、而且底部高於 13 m，就搬到草地 | `world_landmark_relocate` |
| G086／G104／G148 色差 | 交界的另一邊是 `Outdoor_annex_ground`（城界以南，y 1100–1380 m），它用兩個自己的 MI，貼圖和城市地面相同，只是色調不同 | 這兩個槽改用 G01–G16 的 meadow MI。走路面仍比城市地面低 10 cm（1188 對 1198），這就是 G085 的落差帶；把它抬高會把站在上面的東西埋掉，所以沒動 | `world_annex_ground_unify` |

第二輪驗收：cook `20261102-143741`（audit、routes、physics_plan、mirror migration 通過），4 段實走都一次通過（`motel-v1/physics-20261102-144612.json`、`-145716.json`、`-150831.json`、`-152047.json`），slice 0 這次開場 57.5 fps，證實上一輪的 14 fps 是 GPU 被別的遊戲占用。重拍 `shop-survey-v1/captures-20261102-153142`（20/20）：A04、A01 沙灘內緣變成平滑曲線，A13 中央有樹叢；G086 色差減輕，但前景仍有一條深色線和一塊偏暗的方格（10 cm 落差的邊與另一塊地面），列在下表。

## 第三輪（11-02 傍晚，已驗收）

| 項目 | 原因 | 做法 | 工具／job |
|---|---|---|---|
| G085／G086 落差線與偏暗方格 | 城外的 skirt 蓋在城南已有的地面（`Outdoor_annex_ground` 與體育場，x 569–975、y 1100–1380 m）上方，浮在 1188 的走路面上 10 cm，材質又不同 | skirt 建置讀 `probe.json`，把伸出城界的平坦地面當成開口：開口裡不鋪 skirt；開口的邊線成為格線，離開口比離城界近的點，邊緣高度跟著那塊地面 | `Tools/build_street_city_world_edge.lua` → `world_edge_install` |
| G150 接縫 | skirt 用自己的三向投影草地（`M_GrassWorldTriplanar_v2`），和城市草地不同 | skirt 加上公尺 / 4 的平面 UV（和城市地面同比例），安裝時改用 G12 上的城市 meadow MI；舊版沒有 UV 的 skirt 仍用三向投影草地 | 同上 |
| G113 河床白色沙坡 | 內陸河床和海灘共用沙的材質 | 沙條把內陸河床的面放在第二個材質槽 `S_RiverBed`，安裝時這個槽用城市地面的河礫石 MI | `Tools/build_street_city_shore_strip.lua` → `world_coast_strip_install` |

16:29 已裝進地圖（地圖 `969acee9857e`）。

第三輪驗收（11-02 晚上，整合後續跑）：
- cook `20261102-165344` 其實已完成（`package.json` 為 `built_requires_actual_game_acceptance`，地圖相同），所以沒有重新 cook，只補跑 mirror migration（7 處鏡前檢查值）。17:41 那次 cook 是整合時被中止的，不用管。
- 實走：slice 1–3 一次通過（`motel-v1/physics-20261102-225546.json`、`-230655.json`、`-231827.json`）。slice 0 第一次在 `imore-281de587d726-pool-entry-and-exit`（x 313.6、y 655.9 m）判卡住，離這輪改的地方很遠；單獨重跑一次通過（`physics-20261102-233432.json`，開場 58.3 fps），算偶發。
- 重拍 `shop-survey-v1/captures-20261102-232927`（20/20）：
  - G150：skirt 和城市草地接起來，看不出接縫。
  - G113：河床已是河礫石。
  - G085、G086：色差沒了，但城市地面邊緣 1198 對城南地面 1188 的 10 cm 側面仍是一道深色線（見下表）。

## 第四輪：汽車旅館床邊鏡子（11-03，已驗收）

使用者要求「這個世界要多放一點鏡子，方便 H 時可以看鏡子」、「但要放在合理的地方」。

| 項目 | 做法 | job |
|---|---|---|
| 床邊牆鏡 | 從床上 1.3 m 往左、右、床尾打射線。牆要是客房外殼、距離 1.3–6.5 m、20 cm 一格都平（誤差 1.5 cm 內），從床上 0.5 m 看過去不能被擋。鏡子高 0.4–2.2 m，寬 1.4／1.1／0.8 m，金框 | `world_bed_mirrors_install`（`Tools/street_city_bed_mirrors_payload.lua`） |
| 床上天花板鏡 | 床正上方 1.8 × 1.4 m。條件是天花板平，床和鏡子之間沒有東西 | 同上 |
| 效能 | 反射帶 `ImmersionLargeMirror` tag，交給遊戲的「最近兩面」機制開關，存檔時一律關閉；名稱不用 `MotelV1_`，汽車旅館稽核的固定數量不受影響 | |

結果：
- 88 面（牆鏡 47、天花板鏡 41），涵蓋 56 間。
- 沒裝的 5 間：
  - 209 樣板房：床不在預設位置。
  - `imore-6f5e5a7cdf7b`、`imore-345b250913f7`、`imore-cda5d5e2dcb9`、`wego-linsen-3480fecda6b2`：沒有平的牆和天花板。
- 驗收：cook `20261103-025xxx`，4 段實走都一次通過（`motel-v1/physics-20261103-030338.json` … `-042328.json`）。重拍 `shop-survey-v1/captures-20261103-045200`（88 張），牆鏡和天花板鏡都照得到整張床。

過程中的錯誤（都記在 `Docs/STREET_ERRORS.md`）：
- 重裝時探測射線打到上一版的鏡子，牆面被判成不能用。修正：探測時忽略 `BedMirror_*`。
- `unreal.Rotator(0,yaw,0)` 把 yaw 當成 pitch，牆鏡裝成平躺。修正：改用具名參數。
- 舊套件塞滿 E 槽，cook 失敗。修正：刪舊套件，只留三份。

## 第五輪：場景修正（11-03）

| 項目 | 做法 | 狀態 |
|---|---|---|
| 4 組平躺的化妝鏡（`MotelV1_WC_0101`、`0113`、`0909`、`0910`） | 照收據的法線扶正 | 已驗收（cook 後 4 段實走通過） |
| G085／G086 台階線 | 第一版只在城南地面範圍（x 56900–97500）鋪 1 m 斜坡，城界更西邊的落差還在。第二版沿整條南側城界每 2 m 實測兩側高度，有 3–30 cm 落差的地方才鋪 | 第二版安裝中 |
| G086 近處那條線、右下暗色方格 | 線在城南地面內部約 5 m 前（不在城界上），暗色方格是體育場的地面。這輪先量高度剖面再決定怎麼改 | 探測中 |
| G113 白色斜坡 | 河口岸壁 `WorldEdge_Seawall` 沿用 glb 的淺色混凝土，看起來一片白。改用河礫石 MI，岸壁安裝程式也一起改 | 安裝中 |

## 還沒處理

| 項目 | 現象 | 說明 |
|---|---|---|
| G085／G086 台階線 | 城市地面邊緣（1198）比城南地面（1188）高 10 cm，側面在畫面上是一道深色線 | 沿城界、城南地面那一側補一條 1 m 寬、從 1198 降到 1188 的草地斜坡 |
| G113 白色斜牆 | 河岸左邊一大面沒有貼圖的白色斜面 | 第二輪就有，不是這次改出來的；要查是哪個 actor |
| A17 轉角 | 環狀道路在東北角是 L 形轉角，往北沒有延伸 | 判斷為轉角而不是斷頭；北側空地已由樹叢補上 |
