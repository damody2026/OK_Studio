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
- 重拍：`shop-survey-v1/captures-20261102-131804`（20/20）。A04 斜路末端已經有迴車圓環；G084 地平線現在是一道低山脊（仍偏平緩）；A13、A17 已經有樹叢，但 A13 中央大部分還是空的，因為樹叢多半落在城市邊緣。
- `Landmark_stage_92` 擺在 S18 第 10 號車庫的進出路線上，開了碰撞之後 route review 會失敗，所以它維持 NoCollision，記成擺錯位置（見下方）。

## 還沒處理

| 項目 | 現象 | 說明 |
|---|---|---|
| 海灘內緣方格階梯（A01、A02、A04、G024） | 草地與白沙的交界仍是方格階梯（`captures-20261102-131804/A04.png`、`A01.png`） | 1 m 探測顯示沙條 `WorldEdge_CoastStrip` 的內緣其實平滑，而且就在草地開始的地方。我以為是沙條只比草高 3 cm 被草透出來，所以把平頂墊高到 12 cm（`--top 1212`），重拍後**沒有變化**，這個推論是錯的。G04 地面本身帶海灘沙的 MI（`MI_Detail_c6f565f3d91f57f03b7a`），比較可能是地面網格自己的沙地材質區塊按 2.5 m 格子畫出來。trace 拿不到 section 材質（`get_material_from_collision_face_index` 回傳的不是那四個 MI），下一步要直接讀 G04 網格的 section 和三角形，畫出沙地區塊 |
| A13 中央空地 | 只有一叢樹落在中央 | 樹叢種子依「離物件的距離」排序，而城界外沒有物件，所以多數種子落在邊緣。要改成城界也算有東西，或依區塊平均分配 |
| 地面接縫 | G085 高度落差帶、G086／G104／G148 材質色差、G150 平鋪接縫 | 需要先在相鄰地面網格的邊界記錄高差與 MI，再決定是併入 `world_grass_unify` 的 MI 清單，還是沿邊界鋪 skirt |
| G113 白色沙坡 | 內陸河段護岸前一大片看起來沒貼圖的白色沙坡 | 這段在 shore grid（x 300 m 以內）外，是內陸水岸的 heightfield；要另外查它用的材質 |
| A17 轉角 | 環狀道路在東北角是 L 形轉角，往北沒有延伸 | 判斷為轉角而不是斷頭；北側空地已由樹叢補上 |
| `Landmark_playground_a_98` | 底部在 z 34 m，可能浮在空中或位在屋頂上 | 待確認 |
