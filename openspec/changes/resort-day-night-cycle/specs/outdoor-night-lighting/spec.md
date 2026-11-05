## Purpose

為全部已登記戶外景點和連接路線提供風格一致但有場所特色的渡假村夜燈，讓景物、交談站位與步道自然可讀，同時限制光池、眩光與周遭環境之間的過強對比。

## ADDED Requirements

### Requirement: No visible depth conflicts
系統 MUST 盤點並修正造成z-buffer爭用／z-fighting的共面重複幾何、過近疊面、文字底板、水面、地面裝飾、線光和重疊天空／月面。修正 SHALL 優先刪除本流程重複面、建立合理幾何間距或停用已被取代的原表面；不得靠全域深度偏移或改曝光掩蓋。任何必要原幾何變更必須有逐物件修正記錄及可回復資料，保留樓層與室內用途。

#### Scenario: Moving camera depth stability
- **WHEN** 在白天、黃昏、夜晚，以角色高度及斜角，從近景到遠景和LOD切換距離移動相機
- **THEN** 招牌、地面、水面、景物與月面沒有可見交替閃面、摩爾紋或互相穿插的共面輪廓；候選幾何掃描及移動實拍均須通過，未確認項目不能宣稱零z-fighting

### Requirement: Complete destination coverage
系統 SHALL 逐一登記並照明PK-0101至PK-0120、D001至D030，以及海灣、飯店、商店街、住宅、交通與各景點的連接步道。每個ID必須有環境基底光、路徑光、景物重點光或明確的共用光源映射、夜間角色鏡位與驗收狀態；不能以每棟入口有燈取代景點覆蓋。

#### Scenario: No unreviewed landmark
- **WHEN** 產生夜景覆蓋報告
- **THEN** 20個PK與30個D識別碼全部有對應記錄，源資料新增景點時產生未覆蓋錯誤，既有共用分區不重複計算燈具

### Requirement: Resort character and safe visual placement
燈具 SHALL 以2700–3000K暖白、遮光燈罩、低位步道燈和隱藏線光為主；水景可少量用3000–4000K中性光，彩光限於特定景物，不作全城底光。燈具不得遮擋正式店名、觀月／日落視線或雙人合照；主要通道、入口和既有活動淨空保持至少2m。

#### Scenario: Cherry walk and waterfront
- **WHEN** 從入口走到櫻花步道、湖畔或海灣觀景位
- **THEN** 路徑連續可讀，樹花有柔和層次，座椅與護欄有低位引導；視線不直視裸露光源，水面和遠方景觀不被洗成大片白光

### Requirement: Soft local to ambient contrast
系統 SHALL 以降低局部光池強度、擴散／遮光和適量補足環境光共同校正反差。針對固定夜間曝光與相同灰材質測試面，路燈照亮步道區與鄰接未直接照亮區的中位線性亮度比 MUST ≤3:1，景物焦點對其周圍 MUST ≤4:1；燈芯、月亮、招牌文字、火焰及鏡面反射不屬比值取樣區。主要動線地面HDR取樣P10/P50 MUST ≥0.20，避免平均亮度掩蓋黑洞。

#### Scenario: Adjacent bright and dark path
- **WHEN** 用同鏡位、固定曝光、相同灰度探針比較路燈光池與相鄰步道
- **THEN** 探針亮度比不超過3:1，並且原生畫面可辨識人物與路面；增加光池半徑時不得讓光漏入室內或照亮鄰區

### Requirement: Scheduled dimming without dark routes
景觀燈 SHALL 根據太陽高度平滑開關，營業／活動燈另受時段控制；23:00後可減弱裝飾燈與運動場照明，但主要路線、安全入口、階梯與無障礙通道必須維持導引。跳時後必須直接取得正確狀態，不能等待上一個開燈事件。

#### Scenario: Midnight after market closure
- **WHEN** 時間由夜市營業時段跨到收攤後及00:00
- **THEN** 攤位裝飾與營業招牌逐漸調暗，公共通路仍亮且與周圍環境反差柔和，不影響活動系統對營業狀態的獨立判斷

### Requirement: Broad soft night shadows
夜間月光 SHALL 產生隨遮擋距離展開的柔和半影；樹下、花廊與建築旁的陰影不得有明顯硬邊。系統 SHALL 同時降低直射與漫射環境光的反差，保留接地感；不得只提高曝光而洗白燈芯、招牌或月亮。白天日照維持獨立設定。

#### Scenario: Moonlit garden penumbra
- **WHEN** 在21:00及02:00觀察樹冠、廊架與建築投在步道上的陰影
- **THEN** 陰影邊緣隨距離逐漸擴散，暗部仍可讀；以同鏡位原生實拍核對，不只檢查光源角度數值

### Requirement: Native evidence and scene preservation
驗收 SHALL 保留427個既有樓層、122棟外觀及文字、既有活動與通路用途；每個戶外ID有至少一個入夜／深夜的有效角色鏡位，鏡頭在鄰棟內或景物被擋住不得通過。原生HDR及LDR圖片、逐時刻狀態、來源SHA與實際退出碼必須記錄；非零退出不得宣稱程序成功。效能報告必須列出測試機、設定及新增燈光成本。

#### Scenario: Reopen and coverage audit
- **WHEN** 保存後以新程序重開，逐一檢查80個景點記錄及連接路線
- **THEN** 原始樓層、網格、文字與非本變更控制的資料保持，燈具與時鐘資料可恢復，每個有效鏡位可追溯到同一地圖版本；被遮擋或過曝鏡位列為失敗
