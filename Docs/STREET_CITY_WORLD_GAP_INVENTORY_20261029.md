# 街道城市全世界視覺缺口盤點與 Tripo 生成計畫（2026-10-29，c-street-city）

> 這份文件和所有街道城市的檔案一律不 commit，只留在本機。

## 1. 使用者的決定

- 2026-10-28 深夜：「你可以把剩下的tripo點數全部用完，用於增加整個世界的視覺完整性；並且可以用 blender 整理跟remesh比較，我的目標就是盡量低的面數得到最好的視覺效果，哪個面數低就用哪個。」
- 同時說：「你先盤點完整缺口，我明天再幫你接 claude in chrome。」所以這一輪只盤點、不生成。
- 之前的旅館上限 100、商店街上限 100 都由「用完剩下的點數」取代。每件仍是 ≤30 點，用使用者的設定：H3.1、2K、PBR 開、Remove Lighting 開、Triangle、**Ultra Mesh 關**，送出前看按鈕上是 30。
- 上次記錄的點數是 3,255（10-27 晚，旅館家具 v3 之後），約可生成 **108 件**。明天接上 Chrome 後先看實際餘額，再決定生成到第幾件。

## 2. 盤點方式

| 步驟 | 工具／資料 | 結果 |
|---|---|---|
| 室外撒點 | 原生 job `outdoor_scan`（`Tools/street_city_world_gap_payload.lua`，唯讀）：30 m 格點，從天空打射線，穿過小物件落在地面，排除建築範圍 | `output/street-social-city-production/world-gap-v1/outdoor-scan.json`；城內 1,439 個可站立點 |
| 視點規劃 | `Tools/plan_street_city_world_gap_views.lua --bbox 0 120000 0 150000`：每 90 m 一格取一點，人眼高度，四方向輪流；每 300 m 一張空拍 | 地面 174、空拍 19，共 193 個視點（`gap-views.json`） |
| 打包版實拍 | `capture_street_city_shop_survey.lua --views`（package 20261028-233636，地圖 97b11930c01f…） | 193/193 張：`shop-survey-v1/captures-20261029-012810/`；總覽 `world-gap-v1/sheets/gap-01..17.jpg` |
| 室內 | 既有的打包版樓層實拍（10-26 全城普查、10-27／10-28 各類樓層）＋商店改造預覽 | 見第 5 節 |
| 現有街道家具 | `streetscape-v1/active-asset-registry.json` | 28 種資產，全部是方塊板件組裝（長椅 156 面、路燈 48～96 面） |

第一次撒點的範圍被一塊城外的活動平面（1.9 km × 7.5 km）撐大，前 63 分鐘拍到的全是空平面。這批實拍已刪除，原因和修正記在 `Docs/STREET_ERRORS.md`。

## 3. 室外分區與缺口

| 區 | 大約範圍 (x, y m) | 看得到的缺口（視點） |
|---|---|---|
| Z1 海岸與沙灘 | x 0–150，y 0–1050 | 只有棕櫚樹，沒有傘、躺椅、救生塔、步道（A01–A03、G016、G020）；沙灘外緣是階梯狀方塊（A03、A04）；G024 是大片空沙地；海上沒有船 |
| Z2 西側沿海草坪帶 | x 150–300，y 0–1080 | 數百公尺平坦草坪，只有零星的樹和方塊長椅，沒有灌木、花叢、岩石（G028–G037、G047、G048） |
| Z3 商店街與鋪面廣場 | x 280–480，y 150–600 | 大片灰色鋪面是空的（A06、G040、G041、G051）；長椅、花台是方塊；沒有餐車、販賣機、露天座、立牌；路上沒有車 |
| Z4 汽車旅館外 | 約 (260–320, 640–800) | 騎樓下只有回收桶（G045）；前面草坪是空的（G044） |
| Z5 校園核心 | x 450–950，y 0–900 | 建築之間的草坪空洞（G069、G090、G094、G098、G106、G120、G127）；牆腳和欄杆前後沒有綠籬（G043、G064、G068、G077、G081、G121）；花台太方；缺校園地圖、告示板、野餐桌、飲水機、單車棚 |
| Z6 運河與湖濱 | y 約 840–940 | 直線碎石坡加綠色方塊（G099、G113、G161、G173）；沒有蘆葦、睡蓮、碼頭、木棧道、船、臨水欄杆 |
| Z7 北運動場 | x 550–700，y 200–400 | 跑道、足球場沒有球門、看台、記分板、燈塔（G075、G076、G091–G093） |
| Z8 南運動區 | x 450–950，y 1100–1400 | 只有 A19 有一座看台；網球場只有網子；場外深綠草地沒有層次（G087、G103、G117、G132、G149） |
| Z9 東側外圍疏林 | x 950–1100，y 0–1050 | 樹均勻散佈像苗圃，沒有灌木和地被（G136、G152–G165）；斜坡邊緣直接接天空 |
| Z10 南外圍與世界邊緣 | y 1000 以上 | 完全空曠（G084、G101、G115、G131、G146、G147）；看得到地板切邊（G085、G088、G104、G134、G150、A13） |

**不是缺模型的問題**（另外處理，不花 Tripo 點數）：

1. 世界邊緣外露：要延伸地面，加遠景地形或霧。
2. 草地只有單一材質，有方塊狀色差（G086、G148、A17），地形幾乎沒有起伏。
3. 岸線：海岸是階梯鋸齒，湖岸是直線碎石坡。要先改岸線網格，再放植栽。
4. 建築立面：有整面無窗的牆（G079、G140），窗玻璃是不透光的白色（G026、G110），大樓重複同一款貼圖。
5. 光照：遠景霧化偏白，平光，AO 很少。

## 4. 室內缺口（摘要）

- **還沒布置的整棟**：
  - City_CV F01–F05：只有木架、電腦桌、散椅。
  - City_TR F01–F02：方塊儲物櫃加等候椅，用途待確認。
  - Mall_M1 F02–F10：鏡頭卡在樓梯間，要重拍。
- **缺用途關鍵物件**：
  - Campus_IN：機器手臂和 3D 印表機都是方塊。
  - Campus_SC：沒有實驗桌、水槽、通風櫃。
  - Campus_LI：F04、F05 空著，沒有借還書櫃台。
  - Campus_AD：一樓沒有接待台。
  - City_O01–O03：只有工作站。
  - 宿舍 r5、r6 沒有書桌和衣櫃。
  - Campus_SP：沒有跑步機和重訓機。
  - Campus_T4 的販賣部只是一個方塊。
- **最顯眼的程序方塊**：
  - 盆栽（綠十字片）、學生桌椅、電腦螢幕、辦公椅；
  - 住宅的沙發、床、流理台、電視；
  - 書架、金屬雙層床、啞鈴架、商店收銀機。

## 5. Tripo 生成清單（第一批 108 件）

排序原則：一個模型能替換的實例越多、能填的面積越大，越先做。「實例」是預計放置的數量。

### 5.1 街道家具替換（20 件，替換約 1,700 個方塊實例）

| # | Tripo prompt | 實例 | 面數上限 |
|---|---|---|---|
| W01–W03 | wooden slat park bench with cast iron armrests（3 款） | 337 | 1.5k |
| W04 | campus post lamp with lantern head | 308 | 1.5k |
| W05 | double-arm road street light, modern | 193 | 1.5k |
| W06 | low bollard path light | 120 | 0.6k |
| W07–W09 | concrete rectangular planter with shrubs／round tree planter／wooden planter box | 403 | 2k |
| W10–W11 | japanese style triple recycling bin station（2 款） | 219 | 1.2k |
| W12 | steel bicycle rack, five bays | 44 | 1.5k |
| W13–W14 | city bicycle with front basket（2 款） | 24 | 3k |
| W15 | small motor scooter | 10 | 3k |
| W16 | modern glass bus shelter with bench and route map | 2→10 | 4k |
| W17–W18 | green electrical utility cabinet／telecom box | 66 | 0.6k |
| W19 | red fire hydrant | 150 | 0.6k |
| W20 | concrete traffic bollard | 120 | 0.3k |

### 5.2 景觀層（25 件，填大片草坪與硬邊）

| # | Tripo prompt | 實例 | 面數上限 |
|---|---|---|---|
| L01–L02 | round clipped boxwood shrub（2 款） | 600 | 1k |
| L03–L04 | pink flowering azalea bush（2 款） | 400 | 1.5k |
| L05 | blue hydrangea shrub | 150 | 1.5k |
| L06–L07 | mixed shrub cluster, natural group（2 款） | 500 | 2k |
| L08–L09 | ornamental grass clump（2 款） | 400 | 1k |
| L10–L11 | trimmed hedge segment 2 m, low／tall | 800 | 0.8k |
| L12 | trimmed hedge corner piece | 120 | 0.8k |
| L13 | circular flower bed with mixed blooms | 60 | 3k |
| L14 | long flower border strip | 150 | 2k |
| L15–L16 | wildflower meadow ground cover patch（2 款） | 600 | 1.5k |
| L17–L19 | natural granite boulder（3 款） | 300 | 0.8k |
| L20 | stone stepping path set | 80 | 1k |
| L21–L22 | lake reeds and cattails clump（2 款） | 400 | 1.5k |
| L23 | water lily pad cluster | 150 | 0.8k |
| L24 | beach dune grass tuft | 300 | 0.8k |
| L25 | coastal rock cluster | 120 | 2k |

### 5.3 室內高重複件（15 件）

| # | Tripo prompt | 用在哪裡 | 實例 | 面數上限 |
|---|---|---|---|---|
| I01 | school student desk with attached chair, metal frame, wooden top | 7 棟教學樓教室 | ~1500 | 1k |
| I02 | potted monstera plant in white ceramic pot | 全部室內 | ~300 | 1.5k |
| I03 | computer monitor with keyboard and mouse set | 辦公室、IN、SC、LI、AD | ~800 | 0.8k |
| I04 | office mesh swivel chair, black | O01–O03、AD、CV、IN | ~500 | 1.5k |
| I05 | office workstation desk with fabric partition panel | O01–O03 | ~400 | 1.2k |
| I06 | three-seat fabric sofa, modern grey | R1/R2、宿舍交誼廳、AD 大廳 | ~70 | 3k |
| I07 | double bed with headboard, duvet and pillows | R1/R2 | ~60 | 3k |
| I08 | metal bunk bed with mattresses and ladder | D1–D4 | ~200 | 2k |
| I09 | wooden bookcase full of books | LI、AD、CV、SC | ~300 | 2k |
| I10 | kitchen counter with sink, stove and cabinets | R1/R2 | ~55 | 4k |
| I11 | two door white refrigerator | R1/R2、宿舍、茶水間 | ~80 | 1k |
| I12 | wooden wardrobe, two doors | R1/R2、D1–D4 | ~150 | 1k |
| I13 | dorm study desk with bookshelf hutch and lamp | D1–D4 | ~200 | 2k |
| I14 | retail cash register on counter | 96 間商店 | ~96 | 1.5k |
| I15 | wooden teacher lectern podium | 教室、IB | ~200 | 1k |

### 5.4 區域設施（36 件）

| # | Tripo prompt | 區 | 實例 | 面數上限 |
|---|---|---|---|---|
| F01 | soccer goal with net | Z7、Z8 | 4 | 3k |
| F02–F03 | aluminum bleacher stand, five rows（2 款） | Z7、Z8 | 8 | 6k |
| F04 | team dugout bench shelter | Z7、Z8 | 6 | 4k |
| F05 | sports scoreboard on posts | Z7、Z8 | 2 | 3k |
| F06 | stadium floodlight mast | Z7、Z8 | 12 | 2k |
| F07 | tennis umpire chair | Z8 | 6 | 2k |
| F08–F09 | outdoor fitness equipment station（2 款） | Z2、Z9 | 12 | 4k |
| F10 | wooden lake pier with posts | Z6 | 6 | 6k |
| F11 | wooden boardwalk segment with railing | Z6 | 60 | 2k |
| F12 | small wooden rowing boat | Z6 | 8 | 3k |
| F13 | metal waterfront safety railing segment | Z6 | 120 | 0.6k |
| F14 | wooden lifeguard tower | Z1 | 4 | 4k |
| F15–F16 | beach umbrella with two loungers（2 款） | Z1 | 40 | 3k |
| F17 | beach volleyball net | Z1 | 3 | 1.5k |
| F18 | beach rental hut kiosk | Z1 | 3 | 5k |
| F19 | wooden beach walkway mat | Z1 | 30 | 0.8k |
| F20–F21 | japanese food cart with awning（2 款） | Z3、Z1 | 10 | 5k |
| F22–F23 | japanese drink vending machine（2 款） | Z3、Z4、Z5 | 40 | 1.5k |
| F24 | newsstand kiosk | Z3 | 4 | 4k |
| F25–F26 | outdoor cafe table set with umbrella（2 款） | Z3 | 30 | 3k |
| F27 | campus map signboard | Z5 | 10 | 1k |
| F28 | directional wayfinding signpost | Z5 | 25 | 0.8k |
| F29 | wooden picnic table with benches | Z2、Z5、Z9 | 40 | 1.5k |
| F30 | covered bicycle parking shelter | Z5 | 6 | 4k |
| F31–F33 | compact sedan car／kei car／small hatchback | 道路、Z4 | 60 | 5k |
| F34 | rock revetment seawall segment | Z1 | 60 | 2k |
| F35–F36 | low rolling forested hill silhouette（2 款） | Z9、Z10 邊界 | 20 | 8k |

### 5.5 室內設施（12 件）

| # | Tripo prompt | 用在哪裡 | 實例 | 面數上限 |
|---|---|---|---|---|
| J01 | flat TV on low media cabinet | R1/R2 | ~55 | 1.5k |
| J02 | wooden dining table with four chairs | R1/R2 | ~55 | 3k |
| J03 | white ceramic toilet | R1/R2、宿舍、SP | ~120 | 1k |
| J04 | pedestal washbasin with mirror | R1/R2、SP、宿舍 | ~150 | 1k |
| J05 | grey metal locker bank, six doors | SP、TR | ~80 | 0.8k |
| J06 | dumbbell rack with dumbbells | SP | ~25 | 3k |
| J07 | gym treadmill | SP | ~20 | 3k |
| J08 | science lab bench with sink and reagent shelf | SC | ~40 | 3k |
| J09 | office conference table with chairs | O01–O03、CV、AD | ~30 | 4k |
| J10 | four drawer metal filing cabinet | AD、O01–O03 | ~80 | 0.6k |
| J11 | modern reception front desk, wood and white | 各棟一樓大廳 | ~8 | 3k |
| J12 | office water dispenser with bottle | 辦公室、宿舍、SP | ~60 | 0.8k |

### 5.6 點數有剩才做（29 件，依序）

- **室外**（第 5.4 節沒排進的 10 件，加 P3 地標 7 件）：
  - 依序：track hurdle、swan pedal boat、lifebuoy ring on post、beach shower post、A-frame sidewalk sign、vertical banner flag pole、outdoor bulletin notice board、stainless drinking fountain、small delivery van、small sailboat；
  - P3 地標：tiered stone plaza fountain、campus clock tower、children playground set ×2、outdoor performance stage、octagonal wooden gazebo、coastal lighthouse。
- **室內**：
  - lecture hall tiered row desk、adjustable weight bench、laboratory fume hood、industrial robot arm、desktop 3D printer、office photocopier、library reading table with green lamps、metal waiting bench row；
  - 商店用：wooden fruit crate display、glass beverage cooler、commercial espresso machine、snack kiosk counter。

## 6. 處理流程（每件都做）

1. **收集**：Claude 控制的 Chrome 分頁發出的下載不會落地，要請使用者在自己的分頁做 Batch Export（每次最多 10 件，GLB、2k）。依專案名稱從 Downloads 收集（沿用 `collect_street_city_motel_furniture_tripo.lua` 的對應規則，`OK_TRIPO_SET=world-tripo-v1`）。
2. **兩個候選，取面數低的**：
   - **Blender 整理**：依尺寸縮放 → 合併重疊頂點、刪鬆散面 → limited dissolve → 依上表的面數上限 decimate → 貼圖縮到 1K（大件 2K）。
   - **remesh**：`E:/Paper/instant-meshes-rs`，目標面數同上限，參數沿用 `remesh_street_city_motel_tripo_decor.lua` 的階梯。
   - 兩者都出正面渲染圖，比較三角形數，**用面數低的那個**；只有低面數的那個破圖（破洞、細件斷掉）時才改用另一個，並記錄原因。
3. **LOD**：實例超過 100 的件，再出一級約 30% 的遠景 LOD。
4. **安裝**：
   - 街道家具：直接換掉 streetscape 既有 instanced mesh 的網格。實例位置、數量不變，碰撞沿用原本的簡易碰撞。
   - 景觀層：依 `outdoor-scan.json` 的可站立點，以及各區規則撒放（牆腳、欄杆旁、岸線、草坪群落），避開路線與門口。
   - 室內：取代程序方塊，位置沿用 `office_fit` 與 `office_decor` 的擺設結果。
5. **驗收**：完整驗收（cook、79 條實走、0 輔助跨步）之後，用 `gap-views.json` 重拍 193 個視點，和這次的 `gap-01..17.jpg` 對照。

## 7. 明天接上 Chrome 後的順序

1. 看 Tripo 餘額，確認設定和按鈕上的點數（30）。
2. 依第 5 節的順序送出：5.1 → 5.2 → 5.3 → 5.4 → 5.5，有剩再做 5.6。每 10 件請使用者做一次 Batch Export。
3. 邊下載邊處理，先完成街道家具替換並驗收一輪，再做景觀層。

## 8. 已備妥的工具（2026-10-29 凌晨，沒有送出任何生成）

- `Tools/plan_street_city_world_tripo.lua` 會產生 `output/street-social-city-production/world-tripo-v1/plan.json`：
  - 共 137 件，第一批 108 件（`batch=1`），點數有剩才做的 29 件是 `batch=2`。
  - 每件記錄 `key`、`prompt`、`size_m`、`tris`（面數上限）、`group`、`zone`、`instances`、`priority`。
  - `per_model_credits=30`，`approved` 欄位寫的是使用者本人的原話。
- `prepare_street_city_motel_furniture_tripo.lua` 改成讀每件的 `tris` 上限；沒有 `tris` 的舊計畫仍是 35k。
- 收集、remesh、比較面數沿用旅館家具那一套，用 `OK_TRIPO_SET=world-tripo-v1` 切換。
- 主 session 一度以為只有 10-27 的 100 件授權。已回覆它：這次是使用者本人在 c-street-city 對話裡同意的。實際生成仍要等使用者接上 Chrome，先看餘額再開始。