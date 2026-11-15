# build_street_city_places.lua 重跑會漂移（2026-11-15 c-street-city 記錄）

`Tools/build_street_city_places.lua` 現在重跑，輸出和已提交的表對不上，所以 `city_anchors.json` 和 `places-v1/places.json` 目前只能手改、不能重生。照正常流程重跑一次，整座城的錨點會無聲變動。這是欠帳，之後要回頭對帳，這次不修。

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

## 推測的原因（未證實）

- **最可能的一項**：建置工具只讀 `output/street-social-city-production/world-edge-v1/` 裡**檔名最新**的 `lover-spots-install-*.json`（第 273–283 行），現在最新的是 `20261107-161611`。但現有的 places.json（11-12 15:49）裡有 11-07 以後才裝的店，例如 izakaya、sushi、fastfood、yakiniku 的 R2 道具。所以當時用的應該是更新的 install 檔，而那份檔現在不在本機 `output/`，它不進版控，可能被清掉或改名了。消失的 55 個地點和大部分錨點都對得上這一點。
- **其他輸入**：`places-v1/actors.json`（11-09）、`motel-v1/motel-install.json`（11-07）、`round6-*`、`anchor-fit`、`seats-fit` 等在 places.json 產生之後是否又變過，沒有逐一比對。位置變動（public 長椅、campus、civic）可能來自這些量測檔。
- **11-12 以後手改的部分**：重跑時一定會被覆蓋，例如 9c49ed12b 的 off_ 標記（建置工具已接上共用規則）、導出器的 SPOTS 與 PASSAGES。導出器那些改的是 city_places.json，不受建置工具影響。

## 之後對帳要做的事

1. 找回或重建 11-07 以後各輪的 lover-spots install 結果。來源地圖裡的 LoverSpot actor 還在，可以從地圖重新匯出一份 install 檔。
2. 輸入補齊後重跑，和已提交的表逐列對帳，只接受能解釋的差異。
3. 把建置工具依賴的 `output/` 輸入列成清單，缺檔時直接失敗，不要默默輸出縮水的表。
