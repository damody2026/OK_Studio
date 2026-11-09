# 商店街量產規格（2026-10-25）

S01 咖啡書屋、S26 便利店、S09 花藝店、S17 洗衣店四間樣板店已經使用者確認，其餘 92 間依這份規格量產。盤點與樣板經過見 [商店街盤點與修正計畫](STREET_CITY_SHOP_STREET_FIX_PLAN_20261025.md)。

| 項目 | 位置 |
|---|---|
| 量產建模器 | `Tools/build_street_city_shop_refits.lua [--all \| S02 S03 ...]`（不給參數就做全部未核可的一般店） |
| 店型元件庫（Blender） | `Tools/street_city_shop_refits_blender.lua` |
| 預覽 | `Tools/preview_street_city_shop_samples.lua --refits <id ...>` → `shop-refits-v1/previews/<id>-sheet.jpg` |
| UE 安裝 | `Tools/street_city_shop_samples_payload.lua`（`shop_refits_install`；樣板用 `shop_samples_install`） |
| UE 實拍 | `Tools/capture_street_city_shop_survey.lua --samples <id ...>`，總覽 `Tools/sheet_street_city_shop_survey.lua <資料夾> samples` |
| 店家規格 | `output/.../shop-refits-v1/shop-specs.json`（自動產生）、`shop-spec-overrides.json`（手動覆寫，優先） |
| 產物 | `output/.../shop-refits-v1/<id>/<id>-refit.glb`、`build.json`；總表 `refits-build.json`；貼圖 `textures/` |

## 1. 建物契約（不改）

- 一般店屋共用同一套範本，正面一律在來源 GLB 的 −Y，由 actor 的 yaw 轉向步行街。
  - 店寬 W（半寬）：5、6 或 7 m；深 H（半深）：8～12 m。
  - 正門在左半，門中心 `dx` = −1.6、−2.6 或 −3.6 m，淨寬 2.4 m。
  - 樓梯、電梯、廁所核心從 `core_y` 往後。
- 樓梯、電梯、廁所、二三樓室內、量體與入口位置都不動。
- 地圖上的一樓模型是 DepthRepairs 修過的版本：安裝時複製一份再挖除，原模型不改，路徑記在新模型 metadata 的 `ShopSampleOriginal`。
- 必須淨空：
  - 門前 2.4 m、門內 1.45 m，以及從門口到核心的通道（寬 2.6 m，高 2 m 以下）；
  - 核心前 1.5 m 的橫向走道。
- 建模器在每間建完時檢查，`build.log` 的 `blockers` 必須是空的。

## 2. 每間店的組成

| 部分 | 內容 |
|---|---|
| 挖除 | 正面牆、窗、舊門扇、舊招牌與色帶（只刪整個三角形都在範圍內的，保留轉角柱）；`rebuild` 型另刪整個賣場的舊道具（任一頂點在範圍內就刪） |
| 店面 | 依店寬做的玻璃店面：柱、楣板、橫樑、腰板、直框、開啟的玻璃門扇、門檻；楣板可用店型色帶（便利商店、藥妝店） |
| 主招牌 | 沿用已通過的 RomanceName 大字招牌（暗底亮字、立體字）；不在正面另做橫招牌。裝在背面的會搬回正面 |
| 直式招牌 | 二、三樓之間，三語貼圖（`<id>-V-<語言>.png`），材質 `MI_ShopSign_<id>_V` 接 `MPC_CityLanguage`，夜間發光 |
| 遮雨棚 | 依店型與配色變體；洗衣店用短棚 |
| 二、三樓 | 冷氣室外機（依變體 1～2 台、1～2 層）；花店改成窗台花箱 |
| 店頭 | 依店型：咖啡座、黑板立牌、水果箱、花桶階梯、回收桶、寵物碗、書車、暖簾燈籠、理髮旋轉燈、單車 |
| 室內 | 依店型（第 3 節）；主題牆換成店型材質 |
| 燈 | 店內兩到四盞（依店寬）加一盞門口燈，色溫依店型 |

## 3. 店型

店名決定店型（`RULES`，依序比對關鍵字）；同店型的第幾間決定配色變體。

- `keep`：保留原本已合理的設備，再補上缺的東西。新物件只放在空位，用占位檢查避開舊設備。
- `rebuild`：清空賣場重排。

| 店型 | 模式 | 店 | 室內 | 店頭 |
|---|---|---|---|---|
| coffee | keep | S01* S21 S38 S49 S67 S85 | 原吧台與座位＋書牆、吊燈、黑板菜單、窗邊植栽；紅磚主題牆 | 咖啡座、黑板立牌 |
| tea | keep | S02 S22 S39 S50 S68 S86 | 原茶飲設備＋兩側燈箱菜單、等候長椅；薄荷磚 | 燈箱立牌 |
| bakery | rebuild | S03 S23 S40 S51 S69 S87 | 麵包展示櫃、牆面麵包架、櫃台、黑板菜單；白色地鐵磚 | 小圓桌、立牌 |
| restaurant | keep | S04 S24 S41 S52 S70 S88 | 原桌椅與廚房＋紙燈吊燈、牆面菜單；木條牆 | 暖簾、燈籠、植栽 |
| fruit | rebuild | S05 S25 S42 S53 S71 S89 | 兩側三層水果箱架、中島箱架、櫃台 | 兩側水果箱 |
| convenience | rebuild | S26* S06 S43 S54 S72 S90 | 整面冷藏櫃、貨架島、收銀台加背櫃、雜誌架 | 回收桶 |
| book | rebuild | S07 S27 S44 S55 S73 S91 | 兩側書牆、平台書桌、櫃台 | 書車 |
| pet | rebuild | S08 S28 S56 S74 S92 | 飼料牆、水族箱、貓跳台、櫃台；粉色牆 | 寵物碗 |
| florist | rebuild | S09* S29 S45 S57 S75 S93 | 三層花桶架、中央花藝桌、櫃台 | 階梯花桶、窗台花箱 |
| clothing | keep | S10 S30 S46 S58 S76 S94 | 原人台與試衣間＋牆面吊衣桿、中島衣架、摺疊桌 | — |
| barber | keep | S11 S31 S47 S59 S77 S95 | 原理髮椅與洗頭椅＋等候沙發、商品架；白磚 | 理髮旋轉燈 |
| music | keep | S12 S32 S48 S60 S78 S96 | 原吉他架＋唱片箱、吉他牆、櫃台、唱片牆；深色木牆 | — |
| game | keep | S13 S33 S61 S79 | 原遊戲桌＋兩側桌遊牆、櫃台 | — |
| camera | keep | S14 S34 S62 S80 | 原相機櫃＋兩側相片牆、櫃台 | — |
| bike | keep | S15 S35 S63 S81 | 原單車＋輪胎牆、工作台與工具板 | 門口單車（沿用原 Tripo 單車） |
| drug | rebuild | S16 S36 S64 S82 | 兩側明亮貨架、貨架島、藥局櫃台與十字燈；淺藍牆 | — |
| laundry | rebuild | S17* S37 S65 S83 | 一側洗衣機、一側洗衣機加烘衣機疊放、摺衣桌、長椅；洗衣磚 | — |
| lottery | rebuild | S20 S66 S84 | 投注櫃台與機台、號碼看板牆、填單桌 | 看板立牌 |

\* 為已核可樣板，保留樣板安裝結果，不重建。

S18 日式民宿、S19 溫泉會館是特殊建築：入口與量體不同，另外處理，不套店型。

## 4. 配色變體

每個店型有 3～6 組變體：店面框色、楣板或色帶、遮雨棚兩色、直式招牌底色、字色、圖示與字體（楷體或黑體）。同型店依出現順序輪用，相鄰兩間不會同色。配色表在 `build_street_city_shop_refits.lua` 的 `P`。

## 5. 素材

- 程序貼圖（Python／PIL）：
  - 三語直式招牌；
  - 商品貨架（一般、藥妝、寵物、桌遊、唱片、茶飲）；
  - 冷藏櫃、書背、黑板菜單、燈箱菜單、號碼看板、相片；
  - 各遮雨棚條紋；
  - 磚、木條、磁磚等主題牆。
- 沿用原有 Tripo 模型：洗衣機、烘衣機、單車；以及 keep 型保留的原設備（理髮椅、人台、吉他、相機等）。
- 這一輪量產沒有生成新的 Tripo 模型。之後若要用 Tripo 換掉程序道具，上限 100 個，每個不超過 30 點，並先經 instant-meshes-rs remesh。
- 需要壁畫或海報時用 Grok 生成，轉成二的冪次貼圖再用。

## 6. 流程與驗收

1. 執行 `lua Tools/build_street_city_shop_refits.lua`，`blockers` 必須全部是空的。
2. 預覽抽查：每種店型至少看一間。
3. UE 安裝：分批安裝，每批存檔前先備份地圖。
4. 實拍抽查：每批每種店型拍一間，包含白天、夜晚店面與店內。
5. 全部完成後，重跑地圖的稽核、路線、物理、cook 與實際走路驗收。

## 7. 樣板學到的規則

- 入口座標表的南／北和模型實際朝向相反。判斷正面一律看模型的 −Y，鏡位挑面向步行街的那一側。
- 挖除正面時只刪整個三角形，不然會連轉角柱一起刪掉；挖除賣場要用任一頂點，不然會殘留側板和桌腳。
- 不要在正面另做橫招牌：RomanceName 已是主招牌，兩塊會重疊。
- Tripo 花束縮小到花桶尺寸後看起來是灰的，花桶改用程序彩色花球。
- 預覽裡的挖除只刪整個物件，可能殘留舊道具；以 UE 實拍為準。

## 8. 目前進度（2026-10-26）

- 96 間全部完成並裝進地圖（SHA 606a3b0… 之後又重裝了 S18、S19）：
  - 樣板 4 間；
  - 量產 90 間；
  - S18 民宿、S19 溫泉會館各做了和風門面。
- 實拍抽查：
  - 每種店型至少一間（shop-survey-v1/samples-20261025-235518、samples-20261026-053408）；
  - S18、S19 另拍（captures-20261026-062007）。
- S18、S19 的正門隔著約 20 cm 的縫隙面對面，從步行街看不到。和風門面因此裝在兩棟南面靠步行街的那一段：S18 為 Blender y −20～−9，S19 為 9～18（UE 本地 y 是 Blender y 的相反數）。那一段沒有門，所以只掛燈籠，不掛暖簾。
- 還沒做：地圖的稽核、路線、物理、cook 與實際走路驗收；二、三樓室內抽查。

## 9. 驗收結果（2026-10-26）

最終地圖 SHA 2f9ca1764f7c…，全部在 E 引擎（E:/PhysX/UE5.8）上執行：

| 項目 | 結果 | 證據 |
|---|---|---|
| 原生稽核 audit | passed，0 個問題 | motel-v1/audit.json |
| 路線檢查 routes | passed，0 個問題 | motel-v1/route-review.json |
| 物理計畫 physics_plan | 已產生 | motel-v1/game-physics-plan.json |
| 完整 cook | exit 0，原始地圖、設定與資產都沒有被改到 | package 20261026-073046，E:/StreetSocialCityProduction/motel-packages/20261026-073046 |
| 打包版快速物理檢查 | passed | motel-v1/physics-20261026-073626.json |
| 打包版實際走路（Game world、ACharacter） | passed：計畫中的 79 條 walk route 全部走完（以 route id 去重後核對），126 筆紀錄，0 次輔助跨步，一般操作輸入與玩家起點都通過，實走約 30 分鐘 | motel-v1/physics-20261026-073745.json |
| 商店入口通行（Editor 膠囊體掃掠） | 94 間一般店全部通過：從門外 2.5 m 走到核心走道，沿途有地板、沒有阻擋 | shop-survey-v1/shop-walk-sweep.json |

注意事項：
- 實際走路的 79 條路線是旅館路線，加上 S18 前庭與樓梯，並不會走進商店。商店的通行改由膠囊體掃掠檢查，這是 Editor 裡的物理查詢，不是打包版的角色實走。
- S18、S19 的正門隔著約 20 cm 的縫隙面對面，這是原本的建物配置，所以不在入口檢查範圍內。
- 沒有 commit。

### 二、三樓抽查（2026-10-26，打包版 20261026-083621）

- 18 間代表店（S01～S16、S20、S37）各拍店面加二、三樓朝街與朝後共 126 張（`capture_street_city_shop_survey.lua --upper`，設 `OK_SHOP_CAPTURE_PACKAGE=1` 用打包版拍），在 shop-survey-v1/captures-20261026-095841/upper-01..05.jpg。
- 二、三樓照規格沒動過，安裝只切 `S##_F01`。看到的狀況都是原設計，不是缺陷：
  - 二樓是依店型擺設的大廳；S07 立在窗前的木板是書櫃背板，S11 的是鏡台背板，對照 `S##-modular-components-v1/assembly-building/S##-F02-cutaway.png` 確認過。
  - 三樓是隔成臥室的住家，朝街鏡位剛好落在臥室隔間牆後，所以畫面只有牆。
- 結論：沒有要修的視覺或碰撞問題。

### 打包版商店入口實走（2026-10-26）

- `Tools/lua/lua.exe Tools/run_street_city_motel_physics.lua package 0 shops`：路線框架與 shop_walk_sweep 相同，從門外 2.5 m 進門、往裡走 3 m，再走到核心前的走道。點距 50 cm，高度取 sweep 的地板射線。94 條路線換掉旅館路線，ACharacter 在打包版 Game world 裡實際走完。
- 結果 passed：94 條全部走完（以 route id 去重核對），共 150 筆紀錄，0 次輔助跨步，地圖、pak、執行檔都沒有被改到。證據在 motel-v1/physics-20261026-101122-launch.json，套件 20261026-083621，地圖 SHA 5c228f62…；遊戲記憶體約 9～11 GB。
- 上一節「商店通行只用 Editor 膠囊體掃掠」的限制，這次已補上打包版角色實走。
