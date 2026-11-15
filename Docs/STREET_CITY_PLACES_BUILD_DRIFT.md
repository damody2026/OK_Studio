# build_street_city_places.lua 重跑會漂移（2026-11-15 c-street-city 記錄，11-16 全部解決）

**狀態：已解決。** 表可以從輸入重建，連跑兩次逐位元組相同，重建的 city_anchors.json 與已提交的逐列逐欄位相同。

- 11-15（7a3d4bf30）：漏讀輸入的原因是 `io.popen('ls')` 從 PowerShell 跑時回傳空白。改用 lfs，輸入目錄缺少或是空的就直接失敗（20a01f236）。
- 11-16：編號不固定的原因是 Lua 的 `pairs` 每次跑的順序不同，生成器有 40 處遍歷跟著它走（例如第 325 行依店名遍歷 cafe、書店等 5 家店，誰的錨點排前面；同一點落在幾個重疊區域時，公共座位歸哪一區；city_anchors 的流水號）。改法：生成器開頭用依鍵排序的 `pairs` 遮蔽原本的（`Tools/street_city_new_anchors.lua` 的兩處本來就排好序）。改完同一份輸入連跑兩次，city_anchors.json、places.json、props.json 都逐位元組相同。
- 11-16：名字沿用。寫出 city_anchors.json 前讀現有的表，同一點（地點、位置到 1 cm、kinds；off 的列用 `off_kinds`）沿用原名；新點用生成的名字，名字被占用時改用同前綴的下一個空號。生成器也照導出器的做法加上商店樓梯（`Tools/street_city_shop_stairs.lua`，89 列），標 off 時保存 `off_kinds`。
- 驗證（11-16）：從輸入重建，25459 列中沿用原名 25459 列，另有 4 個新點（KTV_2 的錨點，接著照 `street_city_removed_anchors.lua` 拿掉）。與已提交的表逐列逐欄位比對，差異 0 列（JSON 排版不同，內容相同），所以已提交的表不用動。
- 本機的 `places-v1/places.json`（不進版控，是導出器的輸入）重建後名字全部相同，只有順序不同：5 家店的錨點先後、46 個公共座位的區域、1 間房。下次用重建的 places.json 導出時，city_places.json 裡這幾家店的錨點順序會跟著變，名字不變。

以下是 11-15 修正前的紀錄。
## 試跑結果（11-15，跑完已全部還原）

試跑在 9c49ed12b 之後，比較對象是當時已提交或本機現有的檔案：

| 表 | 現有 | 重跑後 | 新增 | 消失 | 位置變動（>1 cm） | kinds 變動 |
|---|---:|---:|---:|---:|---:|---:|
| city_anchors.json 列 | 25374 | 14873 | 892 | 11393 | 5192 | 1330 |
| places.json `game_places` | 113 | 58 | 0 | 55 | — | — |
| places.json 遊戲地點錨點 | 6869 | 5611 | 225 | 1483 | 936 | — |
| places.json `places`（房間） | 1103 | 796 | 0 | 307 | — | — |

### 消失的是哪些

- **game_places 55 個**：zoo、manga_cafe、fishing、realty、clinic_beauty、bike_shop、craft、livehouse、salon、boat、fastfood、clothing_s10 等，大多是 11-07 以後各輪（R2–R8）新增的店。
- **places 307 間房**：`d*` 212 間、`r*` 82 間，是宿舍與房間類。
- **city_anchors 消失最多的前綴**：d 4160、r 1506、building 1195、girls 620、boys 606、campus 477、s 460。

### 位置變動最多的地點

- **city_anchors**：public 3630、campus 555、building 259、civic 119。
- **places.json 遊戲地點錨點**：campus_sports 327、campus_t1 228、civic 119。

### 新增的

city_anchors 有 892 列：public 467、park 99、s 93、minshuku 64、civic 42。

## 原因（11-15 查明，取代先前的推測）

- **真正的原因**：建置工具用 `io.popen('ls ...')` 列目錄（共 3 處：`world-edge-v1/` 的鏡子與 lover-spots install 檔、`campus-v1/buildings` 與 `world-completion-v1/buildings` 的建築報告）。從 PowerShell 啟動 `Tools\lua\lua.exe` 時，`io.popen` 經過 cmd，cmd 沒有 `ls`，回傳空白，也不報錯。所以這些目錄全被當成空的，對應的輸入整批略過，表就縮水了。從 Git bash 跑時有 `ls`，所以看起來「有時正常」。
- **先前的推測是錯的**：install 檔沒有遺失，不需要從地圖重新匯出。
- **已修**：改用 lfs 列目錄（`ls(dir)`，排序後回傳；目錄不存在時回傳空表）。修正後從 PowerShell 重跑，`places-v1/places.json` 與已提交的版本**逐位元組相同**。

## 修正後還剩的差異：city_anchors 的編號不固定

修正後重跑，`city_anchors.json` 列數一樣（25374），但 id 會換：

| 比較 | 新增／消失 | 位置變動（>1 cm） | kinds 變動 |
|---|---:|---:|---:|
| 已提交 vs 修正後重跑 | 64 對 id 互換 | 2847 | 0 |
| 修正後重跑 A vs 重跑 B（同輸入） | 46 / 46 | 1955 | 0 |

同一份輸入跑兩次結果就不同，代表錨點名稱的流水號取決於迭代順序（推測是 `pairs()` 的順序），不是輸入的問題。錨點本身的集合（位置與 kinds）沒有變，變的只是哪個 id 配到哪個點。但 `activities.toml`、導出器的 SPOTS 等用 id 指名錨點（例如 `seat3`），所以重生一次，這些指名就可能指到別的座位。

## 對帳要比的欄位

以 `(place, pos 四捨五入到 1 cm, kinds)` 當鍵配對，不用 id 配對，再比：

| 欄位 | 用途 |
|---|---|
| `id` | 同一個點換了 id 的列，要列出被規則或 SPOTS 指名的那些 |
| `pos` | 配對鍵；配不到的列就是真正新增或消失的點 |
| `kinds` | 配對鍵的一部分；同點 kinds 不同另外列出 |
| `seat_pos` | 座位類錨點的坐下位置，同點不同就是量測輸入變了 |

## 之後要做的事（11-16 已全部完成，見頂端）

1. 讓編號固定：流水號依座標排序後再發，不靠迭代順序。改完連跑兩次要完全相同。
2. 用上面的鍵對帳，已提交的 id 盡量保留（點沒變就沿用舊 id），只對真正新增的點發新 id。
3. 建置工具依賴的 `output/` 目錄缺檔或列不出內容時直接失敗，不要默默輸出縮水的表。