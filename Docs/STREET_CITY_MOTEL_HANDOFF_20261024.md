# 大學城／情趣汽車旅館交接檔

> **後續Tripo飾品工作已有更新：[2026-10-25最新交接](STREET_CITY_TRIPO_DECOR_HANDOFF_20261025.md)。先讀新檔，再將本檔作為原旅館建築／鏡面／打包驗收背景。**
>
> **2026-10-25 12:40 更新**：地圖已因飾品變成 SHA `e5b446c6…`；本檔 A、B、D 節已對新地圖完成（audit／routes／physics_plan、完整 cook `20261025-115752`、quick physics、79 路線實走全過，細節見新檔「新地圖 e5b4 的驗收」）。下方 1ddd／211933 的敘述已過時。**13:25 更新：C、E、F 節也已完成**（full 347 張、59 頁逐頁目視、`publish_street_city_motel.lua`、`delivery-motel.html`、`Play-Motel.cmd` 與 61 個進房捷徑），細節同見新檔。

更新：2026-10-24 21:22（Asia/Taipei）。本檔為本輪接手入口，優先於較舊的 `motel-v1/WORK_STATE.md`。使用者要求因對話過長先保存交接；**本輪汽車旅館尚未完成最終打包與全路線遊戲驗收，不得宣稱全部完成。**

**最後核對的即時狀態（21:22）：新完整 cook 已啟動，ID `20261024-211933`，map SHA為下列新SHA。Lua PID47220、dotnet PID62108、UnrealEditor-Cmd PID38784仍在執行。`package-running.json` 已更新為此新ID；`package.json` 尚為舊202123，須等新結果寫回。日誌 `output/street-social-city-production/motel-v1/package-20261024-211933.log`。保留此背景建置，接手先查，不要重複啟動。**

## 接手先讀

工作目錄 `C:/portable/OpenKoikatsu`，PowerShell。回覆用繁體中文。

1. 先讀本檔，再讀 `Docs/STREET_CITY_MOTEL_REVISION_20261024.md`。
2. 檢查 `output/street-social-city-production/motel-v1/package-running.json`、`package.json` 的地圖 SHA；它們可能是仍在執行的建置或舊候選包，不能只看檔名。
3. 新地圖 SHA 是 `1ddd0b6445db86c88ac831ab58970e113fa3b204be67d08b355da8e84a111d2e`。目前 source audit、routes、physics plan 均對應此 SHA。
4. 正在執行一次新封裝；**先確認現有程序及結果，不能直接再開第二次 cook。** 詳見下節。
5. 繼續剩餘驗收並交付；不能將舊候選包、來源預覽或定鏡拍照當成最新封裝的實際行走證據。

## 使用者授權與本輪目標

- 全地圖廁所都要有大片鏡子，合理室內位置也放鏡子。
- 所有旅館改成情趣汽車旅館，參考兩站全部房型建模：
  - <https://www.imore-motel.com.tw/?page_id=258>
  - <https://linsen.we-go.com.tw/room/>
- 最新明確授權：**「旅館空間不夠就加大」**；本輪因此擴大 H1、處理 S18 前庭，不需重問。
- 沿用全城度假大學城、戀愛氛圍、可讀暗底發光大字招牌、合理屋頂、低重複 PBR、真實花樹、24h 日月光、柔和夜影、不過暗夜景、地面紋理有可辨尺度、平地、影輝大學圍牆多校門、交通設施、避免 z-fighting 等前期成果。
- 既有街道石板地面不要亂改。其餘學校 17 棟 89 層與功能等既有成果保留。
- 使用者曾要求無人值守 12 小時；該舊 goal 已 complete、heartbeat 12 已 PAUSED。**不要新開 goal 或復活 automation。**
- 使用者明確不准傳訊息另一聊天。不要發其他聊天訊息。本輪沒有要求新子代理，不 spawn。

## 工具及安全邊界

- **只用 `E:/PhysX/UE5.8` 引擎**；不要切回 D 引擎，不動 `E:/OpenKoikatsu`。
- 新專案腳本只用 Lua（`Tools/lua/lua.exe`）；可 Lua 內嵌 Python 或 Blender `--python-expr`，不要新增 `.py`、`.ps1`。
- 不刪舊 stage、archive、junction、備份，不 push／publish 外部。
- AGENTS 原有 StreetSocialCity 不動規則，已由使用者連續明確針對這個專案的實作授權覆蓋；修改範圍仍須限於本任務。
- 其他 session 可能改同一工作樹，提交只取自己的 hunk。這輪未要求 commit，不要擅自提交。
- **瀏覽器對本機 file:// 頁面自動開啟曾被 policy 明確拒絕；不可透過 localhost、換表面等方式繞過。** 驗收用原生 Game PNG + `view_image`。最終可給本機 MD／HTML 檔案連結，不要為自動開 HTML 重試繞過。
- 不打印整份大型／壓縮 JSON，改選欄位、計數與少量樣本。`rg` Windows glob 要用 `rg -g 'foo*.lua' ... Tools`。
- 不停其他聊天程序；只可在核對 PID、command line、task UserDir／log 後停自己的程序。
- 不絕對宣稱「數學上零 z-fighting」；說清楚已檢查範圍和證據。

## 目前正在執行的程序

2026-10-24 21:19 初次查到，21:22 已確認進入新 cook：

- 新打包命令 `Tools/lua/lua.exe Tools/repackage_street_city_motel.lua`。
- Lua PID **47220**，父 PowerShell PID **51956**，本聊天 unified exec session **32559**。
- 21:19 尚在前置資產雜湊；21:22 `package-running.json` 已是新 `20261024-211933`、`running_full_cook`。目前 `package.json` 仍是舊候選，須區分兩個receipt。
- 接手可以查 `Get-CimInstance Win32_Process` 的上述命令、最新 package 日誌／receipt。若同聊天仍可用 session，`write_stdin` 輪詢 32559。
- Native Editor worker 已透過 `quit` 正常釋放，job `20261024-211854-quit` 通過。先前 worker PID 91380／session 6042 **已不是可用 worker**；`serve-ready.json` 是殘留 receipt，不可當存活證據。
- 新 cook 正常應約數分鐘，但前置大量資產 SHA 也需時間。以實際程序／日誌判定。

## 工作路徑與舊交付

| 用途 | 路徑／識別 |
|---|---|
| 本輪輸出 O | `C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1` |
| Source map | `C:/portable/OpenKoikatsu/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap` |
| UE map | `/Game/UniversityCity/Maps/UniversityCity` |
| 私有 host | `E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject` |
| 新資產 namespace | `/Game/UniversityCity/MotelV1/...` |
| 新包根目錄 | `E:/StreetSocialCityProduction/motel-packages/<新時間戳>/Stage` |
| full cook 根目錄 | `D:/StreetSocialCityProduction/motel-full-cook-<新時間戳>/Windows`（只是輸出在 D，不是 D 引擎） |
| 舊完整成果文件 | `C:/portable/OpenKoikatsu/Docs/STREET_CITY_COMPLETE_DELIVERY_20261024.md` |
| 舊完整交付 | `output/street-social-city-production/immersion-v1` |
| 舊已驗收包 | `20261024-150235` |
| 舊包 baseline receipt | `output/street-social-city-production/day-night-v1/package.json`，不是 immersion-v1/package.json |

舊已驗收 map SHA `793c958eb03191f025c480dd660dc6c7ec9aef620768648b1fa5d8ebeb9e22bb`；共用 prebuilt Game SHA `6e1211b6748d5ab2c996f801a66a025ebb07809e902a73b44e02ad1e3b59745a`。舊一小時 77 路線、573 圖及整城驗收屬舊成果，保留，不可挪作新旅館通過證據。

## 已完成的研究與建模

- 官網 HTML 61 頁與主要照片已盤點、看過；`reference-catalog.json`、`references/`、`motel-plan.json` 保存對應。
- iMore **26** 個房型頁：中文 22，另英文頁尾四個泳池房 1340／1344／1342／1338。
- WeGo **35** 個不同 URL，含分頁 1–8、同名不同等級／無車庫 variant，已去重。
- 共 **61 個來源房型**：H1 **58 間**，保留 5 層、客房位於 2–5 樓；S18 **3 間**，保留 3 層。
- 52 個房內私人車庫，另外 9 間無房內車庫，其中 S18 三間各有地面指定車庫。
- 品牌：H1「影輝之夜 情趣汽車旅館」、S18「花境 情趣汽車旅館」。
- 是依官網風格與配置製作的原創遊戲改編、推導尺寸，**不是實測一比一復刻**。本輪用 Blender 程序建模、沿用既有 Grok2K／1K 資產，不要聲稱新用 Tripo 或重新 Grok 生成。
- 各房有床、連續布面被褥、沙發、衣櫃、minibar、TV、凹槽浴缸、洗手盆、淋浴、獨立 WC、實背板鏡框、燈具、主題裝飾等。
- 修過家具 weighted smooth normals；被褥原本像 22 根散熱片，已換連續布面。
- 私有地板沿用 Grok teak 紋理，搭 SportsFinish parent，14cm×120cm 木板接縫；車庫石材、104 條停車線高於面層避免共面。
- 水分離 GLB／NoCollision，材質 private `M_SpaWater`，複製既有 translucent 水材質。
- H1 建築約 126×54m，有北側雙跑道 switchback ramps、東側 feeder、獨立樓梯、受支撐屋頂橋／pergola。
- 反向坡道 winding 已修；樓梯由實心堆塊改成獨立踏板和斜梯樑，恢復下方淨高。S18 樓梯孔不被走廊封住。
- 招牌真實立體中文字（msjhbd.ttc），暗底亮字。H1 主入口大字已移外緣避免被上層遮。
- 原 H1／S18 actors 隱藏且 components NoCollision，保留可回復；其他建築未刪除。

## 鏡面成果

- 新 **1033** 個 PlanarReflection：非旅館 **971 組**洗手台鏡面（涵蓋 **1234** 個盆）+ 61 房 + H1 接待 WC 1 面。
- 加舊 12 訓練鏡，共 Game configured **1045**。
- 新 1033 serialized visibility=false；Game 同樓層／正面／22m 內最多啟動 2 面，75%、prefilter=0。
- 非旅館各鏡面有 backing，曾每 25cm 檢查連續牆體，水槽 native wall trace；廚房／實驗室水槽不冒充廁所。
- 目前 fresh reopen audit：61 房、971 banks、1033 captures、1234 basins，全數通過。
- 舊候選包曾實際看到房內及公共廁所反射 towel／art／wardrobe；**新包仍須重新拍照驗收**。

## 本次最新修正（已保存到新 source SHA）

1. 四間泳池房：原 WC 門與隔間伸入左側泳池，已將 WC／shower 移右側（sx=w/2−3.65，WC tx=13.7），四個 GLB 已重建、匯入、refine。
2. 每池新 6 級池內 16cm 階梯，共 **24 native 內階**，外部仍有 7×18cm stairs；`MotelV1_PoolInteriorSteps` 不可丟。
3. Private `M_PoolMosaic`：5cm 藍色磁磚／接縫／微色差，保留 Grok ceramic normal／ORM，已跑 compile_errors 守門成功。
4. H1 feeder 到街道補 29×4.8m 路口連接，centre [35550,77100,1200]、top1206；private asphalt_v2 1K world period300cm。Y76700 撞樹，改 Y77100；未搬無關樹。
5. 新路口立體牌「影輝之夜／汽車入口／→」，`MotelV1_RoadsideEntranceSign` [36400,77750,...] yaw270，面向 road+X，箭頭指 world−Y 入車道。`sign-build.json` 3 assets，imports 總數66。
6. 舊 bus shelter 被 ramp 壓住：**只**移 `Street_bus_shelter_05_02` instance0，[32700,64600,1200.2]→[36720,64600,1206.2]，加實體石材 footway，其餘 instances unchanged；`bus-stop-relocation.json`。
7. **S18 空間擴大（最新）**：整組 35 owned actors 往 world+X **1000cm**，base [48000,50740,1200]→[49000,50740,1200]；保留三層三房。
   - 新前庭 bounds X46000..47000、Y49140..52340，**10×32m**，top1206／bottom1164，有支撐不浮空。
   - 新 footprint 下方補受支撐 foundation，top1181.8 接原 foundation bottom1182，無共面。
   - 原 S19 溫泉會館 maxX45800；它不是旅館，未改／未搬。原 S18 外景鏡位 X45200 其實在 S19 內，已改為 [46100,50740,1371] 看向 [48400,50740,1750]，仍待新包實際像素確認。
   - 原花樹根 [50840,50650,...] 位於擴建後緣，精確平移 +X1500：`Street_cherry_04_04` instance7、`Resort_cherry_0_5_5` instance0、`LandscapeV3_SoilPlanters` instance6、`LandscapeV3_TrunkCollision` instance268；`Street_lamp_lantern_03_04` instance7 同樣+X1500。其餘 instances 全比對 unchanged。
   - 所有 room position／eye／target／bath_eye／mirror_face／entry 和 site base 已更新。
   - 證據 `branch-space-probe.json`、`branch-objects.json`、**`branch-expansion.json`**，含 backup／完整 actor transforms／精確景觀 instance delta。

## 最新 source 驗收（不是最終遊戲驗收）

對應 SHA `1ddd0b6445db86c88ac831ab58970e113fa3b204be67d08b355da8e84a111d2e`：

- `audit.json`：passed，244 rays、61 capsule sweeps、61 房、971 banks、1033新反射。
- `route-review.json`：passed，**2032 ground samples、1560 capsule/car sweeps、0 issues**。
- `game-physics-plan.json`：**79 actual walk routes**（6樓梯、4pool進出、4poolWC、H1街道1、S18前庭3、61客房）、127750 rays、16099 floors、7349 sweeps、254 fixtures、1640 visible stem links。
- `physics_plan` 已按 branch-expansion 精確更新 trunk proxy268 target center +X1500，及其可見樹 stem_render_link expected_root；其他 counts／1cm tolerance 不放寬。此改動仍須 cooked replay 獨立檢查。
- 最近 jobs：`211731-branch_expand`、`211754-audit`、`211814-routes`、`211845-physics_plan`、`211854-quit`，皆成功。

## 舊候選包不可當最終

- 候選 `20261024-202123`，Stage `E:/StreetSocialCityProduction/motel-packages/20261024-202123/Stage`。
- map SHA `4c2cd1076d1632aa3f069f3c38be522ab67d3e5bed33fbc57afa043d5cd69a4b`。
- pak 18,168,335,373 bytes，SHA `bb9e41c692f6fc4cd554caac4e71d4f5a0183d5d1afb3a042bc809b188cd391a`。
- `physics-20261024-204013.json` quick passed：127750 rays、15968 floors、7278 capsules，normal input true，**0 walk routes**。
- `runtime-views-20261024-204244/` 33 原生照片，曾發現泳池 WC 門進水與 S18 錯鏡位；此後 source 已修。不得交付成最新。
- 舊 `captures.json` 仍可能是這33張；新版 focus script 寫 `focus-captures.json`，full 才寫 `captures.json`。驗收務必核對 map SHA／package ID。

## 接手執行清單（順序）

### A. 等新打包結束

不要重複開 cook，先檢查現有 Lua／dotnet／UnrealEditor-Cmd 程序、`package-running.json` 和 `package.json`。新 package 必須 engine=E:/PhysX/UE5.8、exit_code=0、map SHA等於新 source、source unchanged=true。

如確定該次未啟動或失敗，先分析日誌再重跑（每次新 target，保留舊包）：

```powershell
.\Tools\lua\lua.exe Tools/repackage_street_city_motel.lua
```

### B. 更新鏡面攔截的舊測試期望，再做 quick cooked physics

**僅新包 map SHA與source相同時**：

```powershell
.\Tools\lua\lua.exe Tools/migrate_street_city_motel_mirror_rays.lua
.\Tools\lua\lua.exe Tools/run_street_city_motel_physics.lua package 0
```

遷移工具解析已 audit 的971 bank Engine Cube 幾何，用 analytic ray/box intersection；只改7條原正向 school-glazing 被新鏡片提前攔住的 expected face（3.25cm）。原 ray start 距窗1.5cm，會在新backing內，受影響 start 移到 glass外2cm，避免 inside-shape ray semantics；hit=true、Pawn-simple和**1cm誤差上限不變**。不改 source asset。

工具會按 map SHA 保存 before-migration plan，不能手動用舊 map 的 backup覆蓋新 plan。若 quick 失敗，分析 native issues；不要把碰撞容差放大。尤其要確認新搬花樹 proxy／render links 正常。

### C. staged focus照片 → 像素查核 → full照片

```powershell
.\Tools\lua\lua.exe Tools/capture_street_city_motel.lua package focus
# 實際看 focus 圖，確認修正有進包且無新問題，再跑：
.\Tools\lua\lua.exe Tools/capture_street_city_motel.lua package
```

重點：四池 WC 門不能進水、pool mosaic可見、池階可辨、S18在正確前庭且看得到外觀、車庫前庭不穿S19、H1路口指示與連接、夜景與暗底亮字、房內與公共WC真反射。新focus預期約34張，以manifest動態為準；full涵蓋61房 day/night/bath與所有池、外觀、每棟抽樣非旅館WC。

此拍攝用 `-CityImmersionCapture`，角色定鏡 flying／NoCollision，**不能叫角色實走驗收**。

### D. 全79路線實際 CharacterMovement巡走

```powershell
.\Tools\lua\lua.exe Tools/run_street_city_motel_physics.lua package 0 all
```

會依總長／140+650自動給約半小時；應一次D3D重任務，不同時跑另一Game。必須 full coverage：每條 route id 在 completed_route_records，normal input smoke true、player start true、Game world、zero walking_step_assists、Stage/pak/exe/plan/source hashes不變。不要只比較 completed_count 而漏獨特 route。

**runner待補強**：目前只數量 coverage，尚未加 unique completed route id集合核對、zero step assists、soak PNG header1920×1080/hash manifest。可以參考 `Tools/run_street_city_immersion_source_physics.lua` 的 native_images_manifest實作。先補再跑更好；不要鏡像測試或放寬原生失敗。

### E. 所有圖片真實目視記錄

```powershell
.\Tools\lua\lua.exe Tools/build_street_city_motel_contact_sheets.lua
# 用 view_image 實際看指定sheet後才可記錄：
.\Tools\lua\lua.exe Tools/record_street_city_motel_visual_review.lua rooms-01,rooms-02
```

- sheets每頁3房×日床／夜床／浴室，共21房型頁+details；fullsoak完成後重跑可加入walking sheets。
- 每次看完再記，不能讓程式自動把未看圖標成通過。
- 可先full capture看21頁；soak後補walking頁（原sheet hash未變可保留review）。
- 原始圖都保留，contact sheet只是縮圖索引。

### F. 最終交付（尚未寫）

- **`Tools/publish_street_city_motel.lua` 目前尚不存在，需實作**：strict latest source/package/audit/routes/physics/fulluniquecoverage/capture/review/hash守門。
- 產生 `motel-v1/delivery-motel.html`，顯示全61房 source URL對應、日夜／浴室／泳池／外觀／非旅館WC／實走照片與證據。不要自動browser繞開local檔限制。
- 產生正常可玩 `Play*.cmd`／每房入口捷徑；用真正 walking pawn＋正常WASD／F8。可以 BugItGo到floor+90，但不能用文檔 capture flying旗標當正常Play。
- 更新 `Docs/STREET_CITY_MOTEL_REVISION_20261024.md` 為實際完成結果、完整驗收MD，並在舊 `STREET_CITY_COMPLETE_DELIVERY_20261024.md` 追加新成果連結，不竄改舊包證據。
- `Docs/STREET_ERRORS.md` 要追加本輪實際錯誤及修正：pool WC進水、S18鏡位落S19／前庭不足、inside-shape鏡片測試遷移、重複巨大JSON輸出；不要聲稱已寫。
- 最後繁中簡短交付，附MD／gallery／正常啟動器，說明原創參考改編和檢查範圍，不宣稱精確復刻或無限範圍零瑕疵。

## Native worker需要重新編修時

只有發現真實新問題才回到source修。修圖後之前package與physics／captures都過期，要重新對新map做audit/routes/plan/cook/replay。

```powershell
.\Tools\lua\lua.exe Tools/street_city_motel_native.lua serve d3d12
# 等本次 serve-payload.run_id == serve-ready.run_id 且程序存活
.\Tools\lua\lua.exe Tools/street_city_motel_job.lua audit Tools/street_city_motel_audit_payload.lua
.\Tools\lua\lua.exe Tools/street_city_motel_job.lua routes Tools/street_city_motel_routes_payload.lua
.\Tools\lua\lua.exe Tools/street_city_motel_job.lua physics_plan Tools/street_city_motel_routes_payload.lua
.\Tools\lua\lua.exe Tools/street_city_motel_job.lua quit
```

冷讀曾約6分鐘，勿見短暫無輸出就誤判deadlock。原本自己停過的worker其實剛完成，不能宣稱UE確實死鎖。不要讓高記憶體Editor和Game同時跑。

## 腳本與不可重跑的操作

| 腳本／mode | 狀態與用途 |
|---|---|
| `build_street_city_motel_suites.lua [pools]` | 建61房或只4池；pool新WC已生成，不需重跑 |
| `build_street_city_motel_architecture.lua` | ramp／樓梯／屋頂已修，不需無故重建 |
| `build_street_city_motel_signs.lua` | H1／S18／road-sign，共3GLB |
| install payload `import` | imports66；會reset Floor／PoolTile parent，後面需refine／pool_mosaic |
| install payload `refine` | 換最新mesh、重套woodplankparent／spa水；S18新的base由install記錄保留 |
| install payload `pool_mosaic` | 已成功，會compile error守門 |
| install payload `place` | **初次放置已完成，不可重跑** |
| `parking_paint`／`pool_steps`／`driveway_install` | **已完成，帶absent守門，不可重複放置** |
| site payload `branch_expand` | **已完成，不可重跑**；receipt／backup在O |
| site payload `branch_objects` | 只讀，舊receipt是搬動前的精確清單 |
| `repackage_street_city_motel.lua` | E新target完整cook，來源資產／config／Gamehash守門 |
| `capture_street_city_motel.lua` | 真實D3D12 staged定鏡；配置1045、active<=2、鏡面75%／0prefilter守門 |
| `run_street_city_motel_physics.lua` | quickNullRHI／fullD3D12實際行走，待上述補強 |

## 給接手代理的簡短啟動指示

> 請讀 `C:/portable/OpenKoikatsu/Docs/STREET_CITY_MOTEL_HANDOFF_20261024.md`，先檢查現有新打包程序，繼續完成本輪汽車旅館與全圖廁所鏡面的E引擎封裝及真正遊戲驗收。使用者已授權旅館空間不足可擴建。不要重做研究，不要把舊202123候選包當最終，不要傳訊息其他聊天。依本檔剩餘清單執行，完成後更新MD並交付正常可玩啟動器。
