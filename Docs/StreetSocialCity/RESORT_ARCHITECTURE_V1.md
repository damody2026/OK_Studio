# 渡假大學城建築外觀重製

## 使用者範圍

2026-10-22 使用者指定：全城建築外觀造型重做，保留樓層與室內功能；大部分建築要有大招牌、美化設計與合理的非平頂屋頂。沿用 Romance PBR v1 的 Grok 生圖材質，避免明顯貼圖重複。使用者不允許跨聊天傳訊協調，寫圖前等待其他 Editor 釋放。

共 122 棟、427 層；PK 是戶外空間，不計入建築。實際建築資料來自 assembly-manifest 與 campus／remaining 尺寸契約；擺放依照現有地圖 Actor 的真實 transform，不沿用已過期的早期 city-plan 座標。

## 實作分工與資源

- Grok Build job `run-mvj1add4-l4flgk`，thread `b0a71144-e387-4468-a7dd-ec304139b23a`：完整 122 棟設計名冊，各棟屋頂形式、坡度、脊向、色調與細節；122 組參數皆不同。最初查閱大型契約過久的工作 `run-mvj0pv7y-zo9rsu` 已取消，沒有當作成功交付。
- 主代理：契約盤點、Rust 尺寸化外觀幾何工具、Unreal 匯入、材質接入、大招牌文字、保存、重開圖驗收與實景檢查。
- 工具：`Tools/resort-props/src/bin/resort-architecture.rs`、`Tools/street_city_resort_architecture.lua`、`Tools/street_city_resort_architecture_payload.lua`。
- 產物：`output/street-social-city-production/resort-architecture-v1/`。
- 新 UE 資源：`/Game/UniversityCity/ResortArchitectureV1`。

這個階段以外觀模型包覆和新屋頂改變輪廓，保留原有室內樓板、隔間、樓梯、電梯與設備模型。新增外觀不作可進入的新樓層；不宣稱棚架或裝飾空間可供角色行走。新增幾何不改原有行走碰撞，避免改造阻塞既有功能路徑。

## 重現與還原

從專案根目錄執行；每次真正保存前確認沒有其他 session 持有相同地圖。

```text
cargo run --release --manifest-path Tools/resort-props/Cargo.toml --bin resort-architecture -- build
Tools\lua\lua.exe Tools/street_city_resort_architecture.lua inventory
Tools\lua\lua.exe Tools/street_city_resort_architecture.lua shader
Tools\lua\lua.exe Tools/street_city_resort_architecture.lua install
Tools\lua\lua.exe Tools/street_city_resort_architecture.lua render
```

`inventory` 會建立原地圖的 Actor／元件／材質／碰撞／HISM signature 與幾何尺寸基線。`shader` 僅在 Entry 地圖建立外觀資源；`install` 先核對基線 SHA，再備份並保存一次。`render` 必須重開地圖並完成 `audit` 才拍攝實景。

還原以 `restore` 移除本次帶有 `ResortArchitecture-v1` tag 的外觀和招牌 Actor。備份僅供診斷，不能直接覆蓋含有其他 session 新工作之地圖。

## 驗收來源

以產物目錄內最新的 `geometry-manifest.json`、`shader.json`、`install.json`、`audit.json`、`render.json`、各階段 `*-exit.json` 與 `acceptance.json` 為準。已完成：保存後重新開圖驗收 8,369 checks、0 issues；13 張原生拍攝，成果頁精選 8 張取景清楚的照片。各階段原生程序退出碼皆為 0。

## 設計與幾何結果

八類屋頂：gable、shed、butterfly、cross_gable、paired_pavilion、lantern、stepped、hip。屋頂分割 743 個單元，新增外觀共 168,860 個三角面。大體量屋頂保留設備露台，亭式覆頂不是新增可進入樓層；窗眉、木托架、樓層簷帶與轉角構件留在原牆面外，所有地面入口與原有碰撞保留。

Grok 的名冊是設計意圖，實際幾何以 `geometry-manifest.json` 與實景為準；其中細節類別 `scalloped_cornice` 在此版映射成簷帶與窗眉節奏，並未生成波浪形雕飾。

文字使用既有 119 棟的三語材質，另補 S18、S19、M1 的正式建築名牌，沿用 `MPC_CityLanguage.LanguageIndex`。既有街面招牌與室內文字不改。

新屋頂與木材沿用 Romance PBR v1 的世界座標隨機三向投影；色調依 Grok 各棟指定的赤陶、湖綠與象牙選擇。貼圖 2048×2048；Grok 原始圖 1024×1024 經重採樣，Normal／ORM 為推導貼圖而非掃描資料，方法限制見 ROMANCE_PBR_V1.md。

Grok 第二輪記錄成本 US$0.1885572、262,224 total tokens（含快取）；此數字是 bridge 回報值，不包含被取消的前一輪。


最終地圖 SHA-256：`a71d39ee863af27d71d0ef883b18b835e97d95b09667e529edc44a7ecd727345`。`acceptance.json` 同時核對來源、設計名冊、幾何清單、安裝、重開圖驗收與拍攝檔案雜湊。初次旋轉參數錯誤及被剔除的攝影鏡位已如實留存，不當作驗收成果。


## 一樓招牌修正（2026-10-22）

使用者要求招牌應是一樓橫式，或從一樓延伸到更高樓層的直式。本修正取代前一版屋頂招牌配置：120 棟改為實際街面入口立面的一樓橫式簷帶；R1、R2 一樓上緣剩餘高度不足，改為轉角直式，底部 2.9m、頂部 7.7m，使用正向直排文字而非旋轉原橫式 Logo。直式牌距窗跨至少 1.35m。

橫式牌依第一層樓高、同側門高與窗頂決定高度，不跨入二樓；優先使用 street_main／grand 入口，避免放在服務出口立面。舊屋頂牌的背板、框架和支柱一起從模型移除，不只移動文字面。`signage-review.json` 對照修正前 GLB，122 棟的 roof／trim／facade／wood 表面逐項雜湊一致。

直式文字由 `Tools/street_city_vertical_sign_text.lua` 以字型重新排版，支援繁中、簡中與英文，保留既有語言切換。修正前模型、清單和成果頁已封存於 `backups/before-ground-signs-*.zip`；變更前地圖另作版本備份。最終驗收與照片應以更新後 acceptance.json／delivery.html 為準，前文舊地圖 SHA 屬上一版紀錄。

## 外部招牌大字版（2026-10-22）

本節取代前述沿用 Logo 的做法。全部 122 棟外部新增大招牌，使用 localization-v1/catalogue.json 的正式 building.* 名稱，重新以粗體文字排版；繁中、簡中、英文共 366 張。橫式大字依實際牌體比例排版，R1／R2 使用正向直排。奶油白底、深綠字，保留 MPC_CityLanguage 切換。文字面與材質名稱帶內容雜湊，上一版資產保留。

工具 Tools/street_city_vertical_sign_text.lua 已擴充為全部建築字圖生成器。文字貼圖以最長邊 2048、BGRA8、無 mipmaps、永不串流匯入，避免細長招牌因低解析度 mip 而難以閱讀。新版驗收入口為 delivery-text-signs.html，地圖與證據雜湊以 acceptance.json 為準。

大字版最終地圖 SHA-256：`c5adee2ac741a39c15fcbf1190a38264a4d92e01bdead802376e1373b21b88a4`。重開圖 8,369 checks／0 issues，原有 427 層樓與全部原始 Actor／元件核對通過；匯入、安裝與 14 張實景拍攝的 native exit code 皆為 0。成果頁選用 8 張清楚視角；S19 等遮擋鏡位及 M1 樹木遮住名稱的鏡位不列入展示。

## 真實店面與高度場招牌（2026-10-22）

使用者要求商店街招牌更像真實世界，且文字凸起、其他部分內縮。本版由正式文字排版產生七種材質搭配：深木黃銅、奶油烤漆銅字、鼠尾草綠陶白字、酒紅琺瑯香檳字、藏藍槽字、炭灰黃銅與象牙深綠。店家業種決定材質及次標；非商店設施保持簡潔館名。

每棟三語各有 color_height RGBA、normal_roughness RGBA 與獨立灰階 height，共1,098張來源圖。匯入前以獨立檢查核對高度通道逐像素一致、字面高於底板、單位法線、粗糙度與尺寸，並記錄每張SHA256。RGB保留物理材質色，alpha存高度；細微木紋／金屬刷紋與螺絲、凸邊不以大面積髒污掩飾。

Unreal 材質以32步POM、5次二分細化、物理2.8cm高度比例、切線空間視向、倒角法線及PixelDepthOffset呈現牌面凹凸。PDO由MakeMaterialAttributes接入，以避開Python隱藏enum；並非只有印上陰影的顏色圖。字面仍是高度場，矩形牌邊界外不產生獨立擠出字網格或真實字體投影輪廓。既有牌體、邊框、牆面支架及門窗淨空保留。

原生拍攝另增加S01／S03／S09斜角近照，以檢查字邊、倒角光照及內縮底板。最終地圖SHA與程序退出碼仍須以本版acceptance.json／delivery-relief-signs.html為準。

深度母材質最終採共用M_ReliefShared_01與122個材質實例，逐店綁定六張三語packed貼圖，並以實例參數傳入深度／寬、高比例、金屬度與發光量。不同建築不再各自編譯整份POM圖表；實際材質狀態由原生重開圖驗收確認。

高度場版最終地圖SHA-256：`25338b86f8896cce4f9362529052d1b679206670c354c91ce7e8b5999503eab1`。最終重開圖9,467 checks／0 issues，保留427層樓與全部原始Actor／元件；122塊牌的母材質、三語color/height與normal/roughness、非串流解析度及實際深度比全部通過。最終shader／install／render退出碼皆0，共17張原生拍攝，成果頁展示11個清楚視角，含3張斜角近照。

比例修正版取代前述高度場初版SHA。最終地圖SHA-256：`f22762b2c21c1c8f4b4562e03002d42983d9155669bdf5b5af7c3d4f2586f756`。三語排字先在符合實體比例的畫布上生成，再壓入至少256垂直texel的atlas，壓入後重算法線；因此字形與固定件不被長型牌拉寬。所有366組排字比例、1,098張貼圖核對通過，重開圖9,467 checks／0 issues；最新shader／install／render退出碼皆0，17張拍攝全部完成。最新成果與11張選圖見delivery-relief-signs.html，acceptance.json收錄最終來源與產物SHA。

## 夜間自發光（2026-10-22）

新增M_ReliefShared_Night_01與122個版本化MI_Night材質實例，重用既有三語color/height、normal/roughness與正確字形比例，不重製或拉伸字圖。依材質使用31面亮背景、44面亮字、47面暖色背光暈；亮底由內縮背板遮罩發光，亮字由凸字遮罩發光，背光使用字邊附近高度取樣。原有POM、倒角法線、PixelDepthOffset與金屬／粗糙度保留。

自發光預設啟用，SignNightStrength可在材質實例調暗或關閉，SignGlowStrength控制各店亮度；本版提供發光能力，未新增遊戲時鐘或日落排程器。

原生27張拍攝包含17張一般／斜角圖、7張夜景、3張關閉自發光的夜景對照。夜景固定曝光，僅在暫存世界降低日光與天空光，對照透過暫存MID把目標牌SignNightStrength設0；沒有覆存夜間燈光到地圖。拍攝後還原燈光與材質，再次audit並核對地圖SHA不變。night-visual-review.json記錄相同鏡位／曝光下的像素差異，三組全部通過。

最終地圖SHA-256：`bfcb51d5f16e80e100fa436842c0a05173e7ae879291a467f46efda1eb3cca04`。重開圖9,833 checks／0 issues，保留427樓層及原有Actor／元件。最終shader／install／render退出碼皆0。最新成果見delivery-night-signs.html及acceptance.json。

## 渡假村路燈與月光夜景（2026-10-22）

主地圖目前以夜間照明保存。新增122座青銅庭園路燈、122座低位步道燈，包含石材基座、細柱、乳白燈芯、遮光燈罩與框架；照明為2800K／2700K、2300／220流明，局部半徑12.5m／4.5m。新燈具網格全部NoCollision，與原有建築、室內功能和原始碰撞資料分開。局部燈不投動態陰影控制光源成本，主要陰影由月光提供；未進行遊戲效能基準測試。

夜空為原生雙面Unlit漸層球，另有可見月亮。美術調整的主月光6lux、冷色柔和補光2.2lux、SkyLight1.5，保留暖燈光池與可辨識的冷色建築輪廓。這是固定夜景設定，沒有新增遊戲時鐘或自動日夜控制器；拍攝暫切白天不會再保存地圖。

保存與獨立重開圖SHA-256：`d9161accbe694d9a5b9637115c680fb3feafdf68d4b0c8e232116354be0d736b`，取代前述自發光招牌版本。獨立NullRHI重開驗收exit0：原場景與招牌9833 checks、新夜景3544 checks，共13377 checks／0內容問題。427原樓層及全部原始Actor變換、網格、材質槽、碰撞與實例簽章保留；新夜景標籤共1956 Actor，包含1708個無碰撞燈具部件、244個局部光源、兩個月光方向光、夜空與月亮。

最新37張原生圖片，成果頁選9個視角。7張戶外廣角亮度檢查通過，可見像素48.24–83.59%，高亮裁切比例最高約0.049%；3組招牌同鏡位固定曝光on/off仍有明顯差異。LI鏡位落在鄰棟室內，已明確剔除戶外展示，保留原圖於拍攝記錄，不把數值亮度通過當作戶外鏡位通過。

交付限制：離屏拍攝已完成所有圖片、寫出收據並正常記錄Exiting後，程序仍以-1073741819退出；-norhithread重試未排除此問題，原因尚未定位。此項沒有記作native exit0。地圖另以新程序重開，全部內容檢查通過且exit0。acceptance.json為passed_with_renderer_shutdown_error，moonlight-native-run.json保存真實退出碼，成果頁亦列出限制。

成果：output/street-social-city-production/resort-architecture-v1/delivery-moonlight.html。驗收：moonlight-install.json、moonlight-audit.json、moonlight-visual-review.json、moonlight-native-run.json、audit.json、render.json。工具：Tools/street_city_resort_night.lua與兩個payload/finalize Lua檔；未新增py或ps1、未傳訊息給其他聊天、未停止其他程序、未提交或推送。

## 月面放大與細節（2026-10-22）

月亮直徑由3200cm增至19200cm，放大6倍；原位置與街道照明強度保留。以M_MoonSurface_02原生Unlit程序材質呈現深淺月海、環形坑凹面／坑緣、細顆粒月壤及柔和邊緣明暗，色調偏象牙白；另加一個1.6倍外徑的Additive柔和光暈，不依賴新增bitmap。新夜景標籤共1957 Actor。

最終SHA-256為af0f0e0553c3e5618ecbf78280401a5fe16d6364eafa2b7a916be04286f5fb36。獨立重開圖檢查9833+3547=13380項通過；本輪保存／36張原生拍攝及獨立重開程序退出碼皆0。前輪偶發的離屏退出異常仍保留歷史記錄，未證實根因，不把本輪正常退出宣稱為已修復引擎。

同鏡位S03-skyline月亮主體從13×13像素增至80×80像素，直徑比例6.154，月面紋理可辨識；moon-disc-visual-review.json記錄原生圖片對照與地圖SHA。成果頁delivery-moonlight.html改用moon-v2快取版本，保留暖色路燈與冷色月光。
