# 街景可調色與自然變體

本次只建立 `output/street-social-city-production/streetscape-variations-v1/` 可攜衍生版本；遵守目前 AGENTS.md，未修改 `StreetSocialCity/`，也未宣稱原生場景已套用。

## 重建與預覽

使用專案 Lua：`Tools\lua\lua.exe Tools\street_variations.lua build`。已建置時執行 `Tools\lua\lua.exe Tools\street_variations.lua serve`，開啟 http://127.0.0.1:47982/index.html 。伺服器只綁定127.0.0.1，提供此成果資料夾讀取。按「準備目前預覽 PNG」可將實際WebGL畫面存到本成果的renders資料夾；此唯一寫入介面限制同源Origin、自訂標頭、固定PNG檔名、格式／尺寸與12MB上限，不修改模型或原生專案。

Rust工具位於 `Tools/street-variation`。Three.js 0.179.1 使用本機 npm 快取中的官方套件及原始MIT LICENSE，發布後不依賴CDN。沒有新增Python或PowerShell檔案。

## 顏色

檢查實際GLB貼圖：機車為青綠車漆，自行車為灰綠車架。以原色範圍建立平滑灰階遮罩，提供青綠、酒紅、奶油白、海軍藍、芥末黃與石墨灰六色。保留原貼圖明暗細節；以linear RGB計算，遮罩外像素逐一驗證完全相同。法線、粗糙度、金屬度、UV與原始BIN位元組不變。

車色不需GPT重新猜測UV分區；本次未新增GPT／Tripo生成。可調目標色為RGB參數，對應 `StreetVariation.ush`。12份2K以內的預設車色PNG供可攜GLB變體使用，正式可調材質只需原底色、同一張遮罩及每實例三個色彩浮點值；不必為每個停車物件建立一份獨立材質。

樟樹及櫻花樹各四種輕微葉色差，以葉材質的RGB係數控制；不改樹皮，MASK、0.33裁切值、雙面與原Alpha貼圖保留。

## 擺放與LOD

固定種子20261020，以實例ID與參數通道的SHA256取值，不依賴列表順序或每幀隨機。樹原有角度加減12度、水平94–100%、高度96–104%。不新增位置偏移、不傾斜根部，保持接地。保守水平圓包絡不大於原配置，原有以對角半徑保護的走道／建築排除區仍有效；碰撞樹幹使用同一縮放與角度。車輛只變色，尺寸與停車方向不變。

10份模型涵蓋機車LOD0、自行車LOD0–2、兩種樹各LOD0–2。每階使用相同顏色與實例參數，切換距離和剔除策略沿用來源；面數不增加。幾何未改，沿用各原件已通過的Rust remesh收據，不為換材質重複remesh而破壞細節。

驗收範圍是本次換色、變換與幾何保持。自行車中／遠景沿用原有簡化網格，近距離放大仍可見原來源細部缺損；近景使用LOD0。本次沒有重新處理既有簡化品質，也沒有宣稱效能或原生Unreal更新。

## 原生整合契約（尚未執行）

`variation-manifest.json`逐筆提供before/after、顏色線性RGB、原群組及樹幹碰撞差異。正式HISM可保留原分區與共用StaticMesh，為各實例設定3個custom-data floats，材質以VertexInterpolator將PerInstanceCustomData帶至pixel shader，再呼叫共用函式。不要依色彩拆成數千個Actor或每物件動態材質。模型大小、LOD門檻及剔除距離均不變。

在獲准修改的目標專案整合時，仍須做原生編譯、保存後重新開圖、材質Alpha連線、碰撞與實際渲染驗收；本次的可攜驗收不能代替未執行的原生驗收。
