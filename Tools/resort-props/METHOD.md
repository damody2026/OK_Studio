# 度假街景產製方法

## 範圍

新增 R001–R100 共 100 種不同幾何／用途的物件，六色不算種類。每種三段 GLB LOD；簡單幾何不為減面破壞輪廓，可能維持相同面數。LOD0 上限 12,000 三角面，當前多數為數百面。產生 300 個世界座標配置、花草掛載資料與現有樹木變體參照。

依當前 AGENTS.md 不修改 StreetSocialCity/。此交付是可攜模型與配置層，沒有宣稱 Unreal 原生地圖已更新、遊戲幀率或導航已驗收。全圖 WebGL 模式的平面只是檢視背景，不是最終地形。

## 幾何與 remesh

簡單物件使用既有 unit-panel／unit-cylinder 已 remesh 網格，驗證來源 SHA256 與 remesh-report.json，先將 GLB Y-up 轉成 Z-up，再正規化尺寸、組裝。圓柱匯入有上下端面軸向斷言。傘面另產生連續錐形 source.obj，實際執行目前 E:/Paper/instant-meshes-rs/target/release/instant-meshes.exe，讀取 remeshed.obj 的拓撲；來源、輸出與工具雜湊及日誌保存於 components/canopy/。共三個 remesh 元件來源。這是複用已 remesh 元件，不是對整個組裝模型再次 remesh，也不把新建未 remesh 網格混入。花草與樹木複用已有的 remesh／LOD 資產；本批沒有新增 Tripo 任務。需要新的有機造型時才使用 Tripo Model（非 Texture），下載落地後等待 10–30 秒確認，再執行 instant-meshes-rs 與 LOD 驗收。

## 材質與變體

三組自製 1024² 木紋、亞麻與石材貼圖，幾何具 UV 和硬面法線。配色只改裝飾、布面與烤漆，不改木材、石材或金屬。GLB 使用 KHR_materials_variants 保存六色。請連 textures/ 一起搬移，單獨搬 GLB 會缺貼圖。

花朵沿用原始貼圖，shader 按原圖色相分離綠葉與花瓣，四種花色、葉色係數變化；±12°、水平 94–100%、高度 96–104%。plantings.json 保存每次確定性變化。樹木保留先前變體的根部位置與 LOD；樹木是既有環境脈絡，不重複計入新增 100 種。

## 配置

世界座標 east,north,up，公尺；GLB 為標準 Y-up，匯入 UE 時依專案既有軸轉換轉成公分，不可重複旋轉。NPZ 地形 mapY=1100-worldY。依主題目標選擇道路附近的平坦空地，排除建築加緩衝、所有道路完整寬度、既有戶外設施、既有物件、入口 4m、物件間距與水域。九點地形取樣最大高差 3.5cm。

placement.json 是組裝的主資料；建議以單件 GLB + HISM 和 per-instance 配色匯入，不把整層 GLB 當一個常駐 mesh。resort-layer.glb 是世界座標整層檢視／交換檔，花草另依 plantings.json 組裝。大型遮棚建議 220m 剔除，小物 100m；LOD 距離可依實機畫面調整，不能把總三角面數當作 FPS 保證。

## 重建與驗收

```
Tools/lua/lua.exe Tools/resort_props.lua build
Tools/lua/lua.exe Tools/resort_props.lua verify
Tools/lua/lua.exe Tools/resort_props.lua serve
```

預覽 http://127.0.0.1:47983/index.html 。重建前關閉本工具自己的 serve 程序，避免 Windows 鎖住 exe。離線 Cargo 依賴已鎖版。Rust 驗證 GLB 長度、buffer/accessor、有限數值、LOD 單調減面、貼圖解析度、來源雜湊、100 組不同 BIN 幾何、全部配置及花草變體範圍。實際瀏覽器再檢視主題、LOD、配色、花草與整圖；PNG 經 localhost 固定路由存檔。

參考官方度假設施：
- https://taroko.lakeshore.com.tw/facility/tranquil/pool/
- https://www.farglory-hotel.com.tw/fac-detail/outdoor-pool/

未使用官網照片作貼圖。錯誤與修正附加至 Docs/STREET_ERRORS.md。
