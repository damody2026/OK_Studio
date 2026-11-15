# build_street_city_places.lua 重跑會漂移（2026-11-15 c-street-city 記錄）

`Tools/build_street_city_places.lua` 現在重跑，輸出和已提交的表對不上，所以 `city_anchors.json` 和 `places-v1/places.json` 目前只能手改、不能重生。照正常流程重跑一次，整座城的錨點會無聲變動。這是欠帳，之後要回頭對帳。11-15 已查明主因並修好（見「原因」），剩下錨點編號不固定的問題。

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

## 之後要做的事（這次不重生表）

1. 讓編號固定：流水號依座標排序後再發，不靠迭代順序。改完連跑兩次要完全相同。
2. 用上面的鍵對帳，已提交的 id 盡量保留（點沒變就沿用舊 id），只對真正新增的點發新 id。
3. 建置工具依賴的 `output/` 目錄缺檔或列不出內容時直接失敗，不要默默輸出縮水的表。