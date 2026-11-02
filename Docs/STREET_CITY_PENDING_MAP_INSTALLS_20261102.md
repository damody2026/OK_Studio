# 街道城市：等使用者決定才套用到地圖的項目（2026-11-02）

使用者 2026-11-01 決定 `StreetSocialCity/` 整個資料夾不要動，包括地圖 `StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap` 的場景安裝（協調者 11-02 確認）。以下項目只在 `C:\portable\OpenKoikatsu` 版控內準備工具與步驟，**不寫進地圖**；使用者同意後才照步驟套用。

## 已準備

### 世界邊緣山丘（G084、G088、G134、G150 地平線一片平地）

- 原因：`Tools/build_street_city_world_edge.lua` 原本的 skirt 只有一段 35–80 m 的起伏，而且要到 2.5 km 外才升滿。從街上看仰角不到 2°，結果看起來還是平地（`shop-survey-v1/captures-20261101-114953/G084.png`）。
- 改法（已改工具；這支工具和先前其他 street-city 工具一樣還沒進版控，照規則留在工作樹）：150 m 到 900 m 之間升起 25–80 m 的近丘，1.2 km 以外再疊一道 70–190 m 的遠山脊，最高約 236 m。skirt 仍是 NoCollision，只是視覺。
- 產出（已建）：`output/street-social-city-production/world-edge-v1/skirt/skirt.glb`，2,796 三角面，`build.json` 記錄邊界與探測點。
- 套用步驟（使用者同意後）：
  1. 拿 Unreal slot，啟動 motel 編輯器 worker（`serve-ready.json` 為 passed）。
  2. `Tools\lua\lua.exe Tools\street_city_motel_job.lua world_edge_install Tools\street_city_world_edge_payload.lua`：重新匯入 skirt，找出軸向，替換 `WorldEdge_Skirt`。
  3. `Tools\lua\lua.exe Tools\run_street_city_motel_acceptance.lua --from-cook --no-walk` cook，再分 4 段實走（`run_street_city_motel_physics.lua package 0 slice k 4`）。
  4. 重拍 `world-edge-v1/edge-recheck-views.json`，看 G084／G088／G134／G150。

## 未準備（都要改地圖，等決定）

這幾項缺的是資料，不是工具：現有探測（`world-edge-v1/shore-grid.json`、`point-actors.json`、`view-ground-probe.json`）只有高度與少數點的 actor，沒有逐格地表材質，也沒有道路端點。要補資料只能跑唯讀的編輯器探測，但編輯器開 `StreetSocialCity.uproject` 會寫進 `StreetSocialCity/Saved`、`Intermediate`，也算動到資料夾，所以和安裝一起等決定。打包版（`-pak` stage）實走與重拍不寫進 `StreetSocialCity/`，可以照常跑。

| 項目 | 現象（`captures-20261101-114953`） | 先要的唯讀探測 | 之後的做法 |
|---|---|---|---|
| 海灘內緣階梯 | A01／A02／A04／G024 沙與草的交界是 10–15 m 一階的軸對齊階梯，在 `WorldEdge_CoastStrip` 內側 6 m 以外（沙片內緣本身是平滑的） | 在 `shore-grid` 的 1 m 格上同時記錄命中元件的材質（沙或草） | `build_street_city_shore_strip.lua` 加入沙地遮罩：模糊後取等值線當內緣，沙片從內緣鋪到水線，蓋住原本的沙格階梯；步道（`point-actors` 裡的 paving）往內留 0.5 m |
| 地面接縫 | G085 高度落差帶、G086／G104／G148 材質色差、G150 平鋪接縫 | `world_view_ground_probe` 擴大到所有相鄰地面網格的邊界：記錄高差與 MI | 色差：併入 `world_grass_unify` 的 MI 清單；高差：沿邊界鋪一條 skirt；平鋪：草坪 MI 加世界座標的 macro variation |
| A17 死路 | 北側道路在草地中直接斷頭 | 道路網格端點（road／curb actor 的邊界與端點方向） | 端點加迴車圓環（半徑 12 m，同道路材質，有碰撞），或接到最近的步道 |
| A13 空地 | 道路東側大片空草地（約 250 m × 200 m） | 空地範圍內的 actor 分佈（距最近 actor ≥ 25 m 的草地格） | 依 `street_city_tree_species.lua` 種 3–5 片樹叢、一條環狀步道，配上 `park-props` 的野餐桌與告示牌 |
| 地標碰撞 | 地標模型的碰撞沒驗證 | 各 `Landmark_*` 的碰撞設定 | 安裝時設簡化碰撞，實走路線加一條經過地標的 |
