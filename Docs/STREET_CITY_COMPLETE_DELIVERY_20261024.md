# 影輝大學城完整成果紀錄

紀錄日期：2026-10-24（Asia/Taipei）。本文件記錄本聊天截至 12 小時無人值守修整結束時的整合成果，包含此前累積的建築、材質、夜景、地面、校園與交通工作，以及最後一輪沉浸感修整、大片鏡牆、打包與實際遊戲驗收。

**目前交付版本為 `20261024-150235`，使用 `E:/PhysX/UE5.8` 完整 cook 與打包。** 最終整合驗收狀態為 `passed_reviewed_scope`。此狀態表示下文列明的檢查範圍通過，不代表完整遊戲系統、所有 NPC 行為或全地圖數學意義的零 z-fighting 證明。

## 1. 開啟成果

| 用途 | 入口 |
|---|---|
| 成果頁、校門日夜切換、室內鏡牆及全區照片 | [delivery-immersion.html](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/delivery-immersion.html) |
| 啟動目前打包遊戲 | [Play-Yinghui-University.cmd](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/Play-Yinghui-University.cmd) |
| 使用 E 槽引擎開啟編輯器 | [Open-Yinghui-Editor-E.cmd](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/Open-Yinghui-Editor-E.cmd) |
| 最終整合驗收收據 | [acceptance.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/acceptance.json) |
| 最終工作狀態 | [progress.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/progress.json) |

遊玩操作：WASD／方向鍵步行、滑鼠轉向、Shift 快走、Space 跳躍；F7 切換保留碰撞的自由巡覽，E／Q 升降；F8 開關時間介面。正常啟動從校門內的受支撐位置開始，時間面板預設關閉。

瀏覽器自動化因安全政策禁止 `file:` 協定，未能完成成果 HTML 的瀏覽器排版驗收，也沒有繞過限制。已另外通過靜態 HTML、18 個本機／頁內連結、573 張圖檔、25 個日夜時刻及 JavaScript 語法檢查；場景本身另有實際 Game 像素驗收。

## 2. 版本與檔案身分

| 項目 | 值 |
|---|---|
| 最終封裝 | `20261024-150235` |
| 引擎 | `E:/PhysX/UE5.8` |
| 遊戲地圖 | `/Game/UniversityCity/Maps/UniversityCity` |
| 地圖來源 | `C:/portable/OpenKoikatsu/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap` |
| 渲染驗收 | 實際 D3D12 Development Game |
| 地圖 SHA-256 | `793c958eb03191f025c480dd660dc6c7ec9aef620768648b1fa5d8ebeb9e22bb` |
| Game EXE SHA-256 | `6e1211b6748d5ab2c996f801a66a025ebb07809e902a73b44e02ad1e3b59745a` |
| 最終 Pak SHA-256 | `00f63ec21ed44f176eb34f7a1359a80688c44ff9149d9e55dc6e716728275583` |

實際執行檔：

```text
C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/packages/20261024-150235/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe
```

目前成果以獨立新 stage 保存，舊封裝、備份與失敗紀錄均保留。沒有刪除舊 stage／junction，沒有推送或對外發布，也沒有傳訊其他聊天。

## 3. 累積完成的場景方向

### 建築、校園與商店街

- 整體延續適合戀愛與休閒的大學城、渡假村風格；沿用此前已導入的建築外觀、屋頂、材質及商店街成果。
- 保留 17 棟校舍、89 層室內及原有功能配置；沒有將外觀整修改成刪除室內的空殼。
- 校園使用「影輝大學」校名，保留圍界及五座校門。
- 校園與主要步行範圍以平整、連續、可通行為目標，修整浮空平台、步道與入口高差；水岸及必要設施保留合理構造，不宣稱所有物件使用同一高度。
- 沿用辦公樓退縮、景點露出與銜接調整；另修正櫻花步道穿過辦公樓牆面的問題，保留辦公樓室內。
- 保留商店街大字招牌、暗底亮字、自發光及既有橫式／直式配置；文字具有立體／深度表現，不以形象 logo 取代店名。
- 保留此前加入的道路號誌、行人穿越線與交通設施。本次是場景與步行空間驗收，沒有把交通擺設視為完整車流 AI 已驗證。

### 材質與地面

- 延續此前 Grok 建築 PBR 2K 與地表 PBR 1K 工作；相關階段來源保存在第 10 節的成果資料夾。
- 依使用者回饋保留原有良好街道石板鋪面，沒有以全圖統一新材質覆蓋既有街道；原鋪面保留清單與實際渲染另有 ledger。
- 放大草地、土與其他地表的可讀紋理比例，避免 UV 重複過密而遠看像單色色塊。
- 修正白色步道、平台及 PK-0102 的單色地面；現有地面使用可辨識的鋪面紋理。
- 運動館原有同一材質同時套牆與地板的問題，改用向上表面判斷：地面為 14 × 120 cm 錯縫木板，牆頂為淺色礦物粉刷。
- 木板包含對應 base／normal／ORM 與每板紋理偏移；保留場地標線、器材材質槽、幾何及碰撞。

### 日夜、月光與燈光

- 保留 0～24 小時完整日照、月照與日期時間介面。
- 夜空調為較深的藍色，保留較大且可見表面細節的月亮；建築、道路與景點仍可辨識。
- 延續柔和夜間陰影與月照方向，避免把晚上處理成全黑或只有局部強光。
- 保留渡假村風格路燈、校園步道燈及景點照明，整理重複燈具，降低局部眩光與過強反差。
- 球場新增燈具調整為 3,500 lm、70 cm 光源半徑，降低局部高光與體積光干擾；這是指定球場燈具設定，不是所有路燈的統一參數。

## 4. 最後一輪沉浸感修整

下列為本輪已安裝並納入整合驗收的主要項目；數量代表對應安裝紀錄的範圍，不能直接相加當作獨立物件總數。

| 範圍 | 完成內容 |
|---|---|
| 校園地面與步道 | 修整 1,469 段校園步道、浮空活動公園及景點平台，處理步道端點與出入口銜接 |
| 水岸 | 調整釣魚／活動平台、支柱及通行構造，將指定水岸平台接到目前地面基準；補足支撐與欄杆 |
| 連接步道 | 南北連接區鋪面連續，欄杆為完整高度；保留支撐構造 |
| 植栽 | 325 個樹木元件更新；增加常綠樹變化與景觀 LOD，修整 49 個棕櫚元件／352 個實例的樹冠 |
| 櫻花步道 | 六株櫻花樹冠密度第二版、六個樹幹碰撞與六盞上照燈；重新配置前景綠樹，保留花樹可見度 |
| 樹幹與碰撞 | 修正移動樹木與碰撞代理未同步；最終 1,640 個可見樹幹連結納入檢查 |
| 涼亭 | 八座涼亭屋頂與柱頭支撐補齊，修正可見接縫 |
| 門口 | 清除 11 處櫃檯／淋浴間入口阻擋，保留室內設施功能 |
| 設施 | 11 組原本放在屋頂、其他物件或空中的設施完成重新落地；兩張跑道內側長椅搬離緩衝區 |
| 路燈 | 36 組重複舊燈具停用並保留以便回復；32 盞保留航海風照明重新平衡 |
| 碰撞 | 124 組標準街燈金屬構件補阻擋；254 項實體設施檢查通過 |
| 球場 | 補籃球場弧線、罰球與限制區標線，保留原有籃框；標線與底面分離 |
| 泳池 | 水面與池壁側邊內縮 1 cm，移除錯置泳池道具的可見干擾，原物件保留隱藏 |
| 建築接合 | 對向店面雨棚保留 55 cm 淨空，修正相互重疊 |
| 圍界 | 去除 16 個重複圍欄實例，避免重疊共面 |
| 樓梯 | 補連續斜扶手；17 棟校舍首層與二層之間共 34 條雙向樓梯路線納入實際步行 |
| 玩家 | 使用有碰撞的正常 CharacterMovement 步行角色，從校門內受支撐位置開始；F7 提供保留碰撞的巡覽模式 |

安裝收據可能保留當時的 `requires_reopen`／`requires_render_review` 狀態，這些是階段紀錄。最後是否完成整合驗收，以本文件第 6～8 節及 `acceptance.json` 為準，不改寫舊收據冒充當時已通過。

## 5. 十二間大片室內鏡牆

鏡牆設於適合動作練習、體態確認與訓練的室內。寬約 6～8 m、高約 2.1～2.2 m，下緣約離地 30 cm；薄框、背板貼實牆，避開門口通道。

| 房間 | 空間 |
|---|---|
| SC-0303 | 舞蹈社 |
| SP-0403 | 重量訓練 |
| SP-0404 | 有氧 |
| SP-0405 | 拳擊 |
| SP-0406 | 功能訓練 |
| SP-0407 | 復健 |
| SP-0408 | 體適能 |
| SP-0501 | 瑜伽 |
| SP-0502 | 皮拉提斯 |
| SP-0503 | 舞蹈 |
| SP-0504 | 武術 |
| SP-0506 | 飛輪 |

使用原生 PlanarReflection；啟用 clip plane，`r.ReflectionMethod=2`。元件保存設定與實際執行時設定分開：Game 在玩家附近以 75% capture、prefilter roughness 0 運作，約每 0.2 秒挑選同樓層、正面、22 m 範圍內最近至多兩面鏡牆，其餘停止反射更新。反射 bounds 已按實際鏡牆尺寸縮放。

最終完整 cook 版的 **48 張鏡牆照片**涵蓋每間正面／斜角及白天／夜晚，全部人工檢視，確認能看見室內實際反射。部分日間地板反射仍有細顆粒取樣感，列為現存畫質限制。這份驗收沒有聲稱所有室內房間都新增鏡子，也沒有聲稱最終街景效能測試涵蓋所有鏡牆同時啟用的極端情況。

## 6. 實際遊戲驗收

### 最終封裝物理與普通操作

執行 `physics-20261024-151526`，封裝 `20261024-150235`，結果通過：

| 項目 | 結果 |
|---|---|
| 原生室內／門口／窗面等射線 | 127,750 項 |
| 地面支撐 | 13,884 項 |
| 玩家膠囊淨空 | 6,868 段，包含可用門口檢查 |
| 可見樹幹連結 | 1,640 項 |
| 實體設施 | 254 項 |
| Pawn simple glazing | 60,448 項 |
| 正常起點及普通輸入 | 走路、後退、快走、跳躍測試通過 |
| 封裝完整性 | EXE／Pak／驗收計畫驗收後未變 |

此輪 `soak_seconds=0`，屬完整物理及普通操作回歸，**不是最終封裝重新巡走一小時**。

### 一小時連續巡走：保留原封裝身分

`physics-20261024-140946` 在前一封裝 `20261024-135124` 上連續巡走 3,600 秒，完成 81 次路線，涵蓋全部 **77 條不同路線**：43 條戶外路線與 17 棟校舍各兩條方向的樓梯路線。`walking_step_assists=0`。120 張原始巡走照片已全部檢視。

這兩個封裝的地圖、Game EXE 與 Config SHA-256 一致，且 1,251 個地圖／引用 runtime StaticMesh packages 共 **2,502 個序列化 chunks 完全一致**。僅編輯器隱藏預覽 `PlanarReflectionPlane` 在兩邊都被 cook 排除。鏡面與材質 shader 重新完整 cook 後另行實拍、另行做最終物理回歸。

因此可將舊封裝的長時間幾何／步行結果作為同一地圖與相同執行檔的分階段證據，但不能說它是在最終新 Pak 上巡走一小時。34 條樓梯路線涵蓋各校舍首層到二層雙向，也不等於所有 89 層樓梯均逐層走過。

### 時間介面、日夜與效能

最終封裝執行 `runtime-package-20261024-151653`，實際 D3D12 Game 通過：

- 暫停時鐘、時間面板滑鼠游標與原生 UI delegates。
- 三種語言切換、存檔與讀檔。
- 真正 ticker 推進的整日循環；24 倍速下約 149.964 秒完成一天。
- 既有街道鋪面及觸覺鋪面實際渲染 ledger 查核。
- 三組同鏡位照明啟用／停用效能比較，達既定門檻；GPU 中位差約 0.304 ms，frame increase median 約 -5.41%。這是該測試環境的比較，不能推論所有機器必然加速或固定 FPS。
- 白天、黃昏、夜晚三段移動街景共 67 張取樣，全部檢視，所看取樣中未觀察到交替共面閃爍。

測試機為 Ryzen 9 9950X3D、RTX 5090，Development build，texture pool 2,048 MB；效能結果不能視為一般玩家硬體的保證。

## 7. 深度衝突與視覺檢查的實際範圍

已處理跑道標線與底面、草地／地形重疊、重複圍欄、雨棚接合、泳池邊緣及步道接合等發現的問題。最終地圖的三個獨立掃描範圍為：

| 幾何範圍 | 候選數 | 完全共面候選 |
|---|---:|---:|
| outdoor-ground | 85,926 | 0 |
| campus-buildings | 372 | 0 |
| environment-fixtures | 0 | 0 |

候選數包含近距離三角形、內部接觸及合法構造接合，不能把所有候選直接視為可見 z-fighting。摘要仍標示需要人工分類，沒有將其改成全域零衝突證書。幾何掃描、玩家視角照片與移動取樣互補；未涵蓋的物件、視角、連續影格及極遠距離仍有邊界。

## 8. 照片來源與驗收證據

成果頁共 573 張原生 Game 畫面：**67 張來自最終 `150235`，506 張來自 `135124`**，各張保留實際 `package_id` 與原始圖檔 SHA-256。最終 67 張包括全部 48 張鏡牆、4 張南北連接步道、10 張運動館樓層、3 張月亮及2張南主校門照片。舊封裝失敗的鏡面照片已排除，沒有重新標成通過或新版本。

| 證據 | 檔案 |
|---|---|
| 整合交付收據 | [acceptance.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/acceptance.json) |
| 573 張完整來源清單 | [captures-final-reviewed.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/captures-final-reviewed.json) |
| 最終人工畫面檢視 | [visual-review-final.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/visual-review-final.json) |
| 最終 67 張原生實拍收據 | [render-repair-captures.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/render-repair-captures.json) |
| 新舊地圖／模型資料等同性 | [render-recook-equivalence.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/render-recook-equivalence.json) |
| 最終物理與操作 | [physics-20261024-151526.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/physics-20261024-151526.json) |
| 一小時巡走原始結果 | [physics-20261024-140946.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/physics-20261024-140946.json) |
| 一小時巡走原封裝收據 | [physics-20261024-140946-launch.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/physics-20261024-140946-launch.json) |
| 120 張巡走照片檢視 | [physics-20261024-140946-review.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/physics-20261024-140946-review.json) |
| 最終日夜／UI／效能 | [runtime-package-20261024-151653.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/runtime-package-20261024-151653.json) |
| 最終移動畫面檢視 | [visual-review.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/runtime-package-20261024-151653-review/visual-review.json) |
| 深度候選與分類限制 | [depth-candidate-summary.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/depth-candidate-summary.json) |
| 保存後重新開啟查核 | [audit.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/audit.json) |
| 運動館地／牆材質 | [sports-finish-install.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/sports-finish-install.json) |
| 成果 HTML 靜態查核 | [delivery-page-check.json](C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/delivery-page-check.json) |

## 9. 打包過程的問題與修復

1. 增量 cook 版的鏡面元件與 CVar 雖正確，封裝實拍仍為灰白／黑面，未列為通過。相同地圖與 EXE 的來源 Game 能反射，最後改完整 cook，最終新封裝實拍恢復反射。
2. 首次完整 cook 遇 E 槽空間不足；失敗資料保留移到 D 槽。清除舊 cook cache 的操作被自動審核拒絕後，採新的獨立目錄，沒有刪除舊 stage 或 junction。
3. `CookOutputDir` 缺少 `Windows` 層級導致 staging 只收到設定檔，以 Pak 清單與真啟動攔下；保留搬移已完成 cook 到正確目錄後另建新 stage。
4. `physics-20261024-150656` 在並行工作及啟動期間的 W 前進距離不足而失敗。失敗收據保留，沒有調寬門檻；停止其他驗收 Game 後，以最終包獨立執行 `151526`，普通輸入與完整物理檢查通過。

詳細錯誤紀錄見 [STREET_ERRORS.md](C:/portable/OpenKoikatsu/Docs/STREET_ERRORS.md)。

## 10. 前期成果與後續維護入口

以下是此前階段的成果頁，供追溯設計決策及使用者修正；**不是目前應啟動的最新封裝**：

- [建築與文字招牌](C:/portable/OpenKoikatsu/output/street-social-city-production/resort-architecture-v1/delivery-text-signs.html)
- [夜間發光招牌](C:/portable/OpenKoikatsu/output/street-social-city-production/resort-architecture-v1/delivery-night-signs.html)
- [月照夜景](C:/portable/OpenKoikatsu/output/street-social-city-production/resort-architecture-v1/delivery-moonlight.html)
- [E 引擎實際執行階段](C:/portable/OpenKoikatsu/output/street-social-city-production/day-night-v1/delivery-E-runtime.html)
- [地表 PBR 紋理比例修正](C:/portable/OpenKoikatsu/output/street-social-city-production/ground-pbr-v2/delivery-ground-revision.html)
- [白色地面鋪面修正](C:/portable/OpenKoikatsu/output/street-social-city-production/white-paths-v1/delivery-white-paths.html)
- [PK-0102 地板修正](C:/portable/OpenKoikatsu/output/street-social-city-production/pk0102-floor-v1/delivery-PK0102-floor.html)
- [交通與校園階段](C:/portable/OpenKoikatsu/output/street-social-city-production/traffic-v1/delivery-traffic.html)

重建／驗收工具保存在 `C:/portable/OpenKoikatsu/Tools/`。主要入口為 `repackage_street_city_immersion.lua`、`run_street_city_immersion_physics.lua`、`run_street_city_immersion_runtime.lua`、`capture_street_city_immersion_current.lua`、`verify_street_city_render_recook_equivalence.lua` 及 `publish_street_city_immersion.lua`。重跑前應閱讀各工具的參數與封裝身分守門；不要把其他 demo 的重建命令直接套用到這份 UniversityCity 封裝。

## 11. 目前限制與交接狀態

- 日間部分鏡面地板有細顆粒反射取樣感，尚未完全消除。
- 573 張靜態照片與三段移動取樣不是全地圖連續錄影；不保證所有未知視角、道具與遠距離不存在深度衝突。
- 最終新封裝已做完整物理與普通輸入回歸、日夜／UI／效能及鏡面實拍；一小時巡走來自幾何及 EXE 相同的前一封裝，來源清楚分列。
- 89 層室內有代表鏡位與原生檢查；樓梯長時間巡走範圍為 17 棟首層至二層雙向，不是所有樓層逐層完整遊玩。
- 沒有把場景整修當作 NPC 生活模擬、全功能互動、車流 AI 或完整戀愛遊戲完成證明。
- 這份文件只記錄當前結果；沒有因此重新開啟 12 小時工作、修改場景或啟用排程。

無人值守工作於 2026-10-24 15:29 左右結束，自動喚醒 `12` 已設為 `PAUSED`；本輪驗收遊戲與私有編輯器程序已退出。後續接手以最終交付版與其收據為基準，保留原始照片、版本來源及可回復備份，不覆寫舊證據。


## 後續：情趣汽車旅館與房間飾品（2026-10-25）

新封裝 `20261025-115752`（地圖 SHA `e5b446c6…`）另行交付，不改動上方舊包證據：61 房型、全城廁所鏡面、122 件 Tripo 房間飾品，79 條路線實走與 347 張定鏡畫面。交付頁 `output/street-social-city-production/motel-v1/delivery-motel.html`，啟動器 `motel-v1/Play-Motel.cmd`；說明見 [Tripo 飾品交接](STREET_CITY_TRIPO_DECOR_HANDOFF_20261025.md)。