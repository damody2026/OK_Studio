# PhysX 布料（裙子／袖子）交接 2026-11-21

讀卡器裡用 PhysX 5.11 GPU 布料（`PxDeformableSurface`）做裙子與袖子，和原作物理（DynamicBone，下稱 DB）對照。設計與歷次排查見 [CLOTH_PHYSX_SKIRT_SLEEVE.md](CLOTH_PHYSX_SKIRT_SLEEVE.md)，錯誤紀錄在 [ERROR_LOG.md](ERROR_LOG.md) 2026-11-21 各條。

## 目前狀態

- 上午的改動提交到 `23300e60d`；下午的修正見下方「使用者 11-21 回報的處理」。都沒有推送。`OKExtractBuildStamp.h` 和 `grok-media/` 不屬於這項工作，不要提交。
- 遊戲沒在跑，Unreal slot 已釋放（slot1、slot2 都空）。
- 主要程式碼：
  - Rust 端：`Tools/ok-extract/src/cloth_px.rs`。
  - Unreal 端：`Plugins/OKPhysXSecondary/.../OKPhysXCloth.cpp`（CVar `OKPhysXCloth.*`；11-21 下午改了上傳方式，見下）。
  - 另有小改動：`dbone.rs` 的 `DBoneSet::root_names`，`session.rs` 的 `AccessoryRuntime::implanted_bones`。

### 已修好且錄影確認

| 問題 | 做法（commit） |
|---|---|
| 雷電將軍紫色和服破面 | 骨頭移植到身體骨架的衣服（`implanted_bones` 非空）不做布料（`72dd437b9`） |
| 自帶手臂 DB 鏈的衣服 | 留給 DB；鏈布料只在 `OK_CLOTH_PX_CHAINS=1` 時實驗 |
| 襯衫袖與外套袖互穿 | `LAYERS` 分層：同一區只讓外層當布料，裡層照骨架走（`5f50686a4`） |
| 千佳褶裙上浮、前擺翻起 | 裙子不放 GPU 身體膠囊（`ae19a7ad6`）；所有裙子改成跟著 DB 擺：布料最多離 DB 5 cm（`OK_CLOTH_PX_LONG_MAX`），不能高於姿勢 5 mm（`OK_CLOTH_PX_UP`）（`99eeab16d`） |
| 女僕長裙變短、被腿刺穿；惠惠裙擺露出內褲 | 同上 DB 跟隨 |

**上浮的原因（上午的判斷，當時主機上傳失效、布料根本沒在跟身體模擬，見下方根本原因，需重新驗證）**：`PxDeformableSurface` 的靜止形狀在建立那一刻就定死了，走路中途建的布料會一直保留那一刻的外擴。為此調過彎曲、摩擦、楊氏模數、厚度、迭代次數、PULL、CPU 膠囊，全都沒用，不要再走一遍。

## 使用者 11-21 回報的處理（下午）

使用者說的原話：

> 服裝 2，手上的袖子沒有物理要修正
> 服裝 3，女僕長裙的面數不夠，需要自己加面
> 服裝 5，面數不夠且小腿穿模和服長裙
> 我看起來有兩個問題：1. 衣服面數不夠時需要自己加面 2. 物理碰撞參數沒有調到位

讀卡器的「服裝 N」是 outfit 索引 N−1（`OKGalleryWidget.cpp` 的 `服裝 %d` 用 `i + 1`）。

| 問題 | 原因 | 做法 |
|---|---|---|
| **布料從來沒跟著身體動（根本原因）** | 主機每步寫進 GPU 的位置被解算器當成位移換成速度；第一個卡頓幀後整塊布連固定點一起飛走，畫面只剩 Rust 的夾限結果 | 固定點用速度帶到目標、自由點保留 GPU 狀態，只把被夾住的點用速度引導回去（`OKPhysXCloth.PinByVelocity`），單次工作時間有上限。詳見 [ERROR_LOG.md](ERROR_LOG.md)「PhysX 布料從來沒跟著身體動」 |
| 服裝 2 紗袖沒有物理 | 紗袍是 `clothes_gloves`，移植 24 根骨、有自己的袖鏈；detect 只看 `clothes_top`，移植骨衣服又整件排除 | 手套看自己的鏈；移植骨與自帶鏈的衣服預設做布料，跟著 DynamicBone 擺，偏移和鄰點平均 |
| 服裝 3、5 面數不夠 | — | `cloth_refine.rs` 自動加面（邊 ≤ 25 mm）：女僕長裙 776 → 3600 頂點、和服裙片 953 → 3434、紗袍 2731 → 5144 |
| 服裝 5 小腿穿出和服長裙 | 和服整件因移植骨被排除，是 DynamicBone；另外分層把和服的子網格互判成「被蓋住」 | 和服成為布料；長裙垂下部分避開小腿膠囊整個半徑；裙子也放 GPU 身體膠囊；分層只比同種區、只量自己畫的頂點、同 mesh 子網格不互比 |

### 重錄（五套全部，修完之後）

- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all2\raiden_outfit1_compare_20s.mp4` … `raiden_outfit5_compare_20s.mp4`（左 PhysX 布料、右原始物理，20 秒，每 5 秒轉 90°）。
- 單邊：`C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all2\outfit{N}_cloth.mp4`、`outfit{N}_dynamicbone.mp4`。
- 錄影腳本（暫存區，可能被清掉）：用 ok-game-mcp CLI 切服裝、`ok.ClothPx 1/0`、相機 yaw，ffmpeg `gfxcapture` 抓遊戲視窗，`hstack` 加 `drawtext` 標字。

### 還沒處理／已知

- 服裝 3 側面錄影中有一段前片被大腿頂到往前翻起約 20 cm，之後落回。`ok.ClothPxStats` 量到顯示位置最多離 DynamicBone 姿勢 90 mm，超出 5 cm 的部分來自 Rust 的身體膠囊推出（含新的小腿規則）。要再壓可以限制推出後的總偏移。
- 布料真的會動之後，以前在壞掉狀態下定的參數（`BendingSkirt` 0、`Thickness`、`OK_CLOTH_PX_PULL`、重建門檻、「跟著 DynamicBone」本身）都值得重新量一次。
- 其他卡（千佳、惠惠、刻晴）已在修好的主機上重看（2026-11-21 晚，見第三次回報）。

## 使用者 11-21 第二次回報（傍晚）

> 服裝二 一樣穿模 / 服裝三 一直抖動 / 服裝五 穿模加抖動

| 問題 | 原因 | 做法 |
|---|---|---|
| 抖動（服裝 3、5） | ① 非同步時主機用絕對位置轉向，而 Rust 給的位置落後 GPU 一個結果，每次都把布料拉回上一個結果，60 fps 每幀抖 19 mm；② 200 fps 下約 6 幀才一個結果，中間幀顯示衰減中的舊結果，新結果一到又跳出去 | 每幀先收結果、對這個結果算修正、再發下一個工作，修正以「修正量」交給主機（建立旗標 bit 1），逆著修正的速度歸零、修正不留成動量；兩次結果之間平滑過去（`OK_CLOTH_PX_BLEND`）；單次工作上限改為 `OKPhysXCloth.MaxDt` 34 ms |
| 穿模（服裝 2 紗袖垂進腰臀胯下；服裝 5） | Rust 推出身體用建立時的距離，走路後不對 | 每幀依姿勢：離膠囊軸不比姿勢近，上限 1.5 × 半徑 + 4 cm（`OK_CLOTH_PX_KEEP_OUT`、`OK_CLOTH_PX_LIVE_PUSH`） |

量測（`OK_CLOTH_PX_DEBUG=1` 的 `jitter` 行，shown 是畫面上布料、raw 是姿勢本身，見 CLOTH_PHYSX_SKIRT_SLEEVE.md）：

| 服裝 3 | 修之前 | 修之後 |
|---|---|---|
| 200 fps（非同步） | 偏移量測 3.3 mm／幀，畫面上裙片側邊一寬一窄地翻 | shown 6.10 ≈ raw 6.05 mm（布料不再多加抖動） |
| 60 fps（非同步） | 19 mm（位置轉向時） | shown 4.4、raw 2.8 mm |
| 同步（`Async 0`） | — | shown 4.29、raw 4.45 mm |

服裝 2、4、5 修之後 shown 與 raw 也相同（1.51／1.24、2.62／2.58、8.5／8.4 mm）。讀卡器的姿勢本身在 200 fps 下每幀二階差分就有 5–6 mm（動畫取樣不均勻），那是身體和布料一起的，不是布料。

錄影（修之後）：

- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all4\raiden_outfit2_compare_20s.mp4`
- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all4\raiden_outfit3_compare_20s.mp4`
- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all4\raiden_outfit5_compare_20s.mp4`
- 單邊：同資料夾的 `outfit{N}_cloth.mp4`、`outfit{N}_dynamicbone.mp4`。

## 使用者 11-21 第三次回報（晚上，附截圖）

> 服裝二 一樣穿模 / 服裝三 一直抖動且邊緣鋸齒 / 服裝五 穿模加抖動且邊緣鋸齒

| 問題 | 原因 | 做法 |
|---|---|---|
| 服裝 2 紗袖穿過大腿、淺藍碎片露在腰前 | ① 身體膠囊比她的大腿細，粒子在膠囊外卻在皮膚裡；② 紗袖的 DynamicBone 姿勢有一段本來就垂進腰臀（原版藏在身體裡），被推出來擠成一團；③ 淺藍內襯是另一片網格，兩片各自模擬互穿 | 皮膚碰撞場（`cloth_skin.rs`）；姿勢在皮膚裡的地方布料留在姿勢上；同一件衣服 6 mm 內的較小網格片當內襯跟著外層 |
| 服裝 3、5 皺成紙巾狀、下擺鋸齒 | 彎曲剛度 0（上傳失效時定的），布料真的動了以後沒有東西撐住形狀；偏移平滑只用在跟著 DynamicBone 的布料 | `Bending`／`BendingSkirt` 0.5；偏移平滑 6 次、所有布料都做 |
| 服裝 5 穿模 | 同服裝 2 ①（小腿） | 皮膚碰撞場 |

量測（`jitter` 行，shown／raw，mm／幀）：服裝 2 6.10／4.92，服裝 5 第 5 塊 9.74／7.88；比上一輪多了一些（推出皮膚帶進來的），其他布料 shown ≈ raw。

錄影：

- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all6\raiden_outfit1_compare_20s.mp4` … `raiden_outfit5_compare_20s.mp4`
- 單邊：同資料夾的 `outfit{N}_cloth.mp4`、`outfit{N}_dynamicbone.mp4`。

其他卡（同一版）：千佳歩く1、惠惠與刻晴走る1，各錄 20 秒對比，沒有退步：

- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\others7\chika_outfit1_compare_20s.mp4`
- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\others7\megumin_outfit1_compare_20s.mp4`
- `C:\portable\OpenKoikatsu\Saved\OKControl\videos\others7\keqing_outfit1_compare_20s.mp4`

### 無人值守巡檢（11-21 16:10–16:45）

- 開皮膚碰撞後幀率掉到約 70（皮膚查詢每粒子每幀 5 次、每次掃兩遍）。改成一次掃描加 rayon 平行，回到約 110。
- 60 fps 下關掉皮膚碰撞，服裝 5 的布料也比姿勢多抖 1.5–2 倍：兩次結果之間的平滑每次結果到達都折方向。改成臨界阻尼彈簧（`OK_CLOTH_PX_DAMP_T` 2）。
- 皮膚碰撞再多加約 1 mm／幀（服裝 2 紗袖、服裝 5 和服後擺）。逐項關掉量過：不交給 GPU（`OK_CLOTH_PX_SKIN_HOST=0`）、不留在姿勢（`OK_CLOTH_PX_HOLD=0`）、高斯加寬到 2 cm，都沒有差別。判斷是布料貼著大腿、跟著腿動（腿本身每幀二階差分就比袖子大），不是讀數雜訊。
- 60 fps、阻尼 2 倍時（shown／raw mm）：服裝 2 紗袖 3.2／1.7，服裝 5 和服 3.6／2.2、6.8／4.8；關掉皮膚碰撞是 2.6／1.7、3.4／2.3、5.2／4.4。不鎖幀（100–165 fps）時 shown 和 raw 相差 0.05–1 mm。
- 錄影：`C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all7\raiden_outfit2_compare_20s.mp4`、`raiden_outfit3_compare_20s.mp4`、`raiden_outfit5_compare_20s.mp4`。服裝 5 和服長擺在轉身時會往側面水平甩出，原始物理同一時刻也一樣。

還沒處理：

- 服裝 2、5 貼著大腿的布料跟著腿動，比姿勢多抖約 1 mm／幀（見上）。
- 服裝 5 白色袖口有時比原版張得開。
- 服裝 3 女僕長裙側面走路時前後片往外張開，是它跟著的 DynamicBone 姿勢本身就張開（布料最多偏 5 cm），修之前的錄影也一樣。
- 讀卡器姿勢在高幀率下取樣不均勻（身體也一起抖），不在布料範圍。

## 測試與錄影流程

1. 先佔 slot，再確認可以建置：
   ```powershell
   Tools\lua\lua.exe Tools\unreal_slot.lua claim c-cloth-px "<做什麼>" --lane clothpx
   ```
   ```powershell
   Tools\lua\lua.exe Tools\unreal_slot.lua may-build
   ```
   `may-build` 回傳 exit 3 就等。
2. 改了共用程式碼：
   - 跑 `cargo check`，加跑 `--no-default-features`；
   - 建 `OpenKoikatsu` Development 與 `OpenKoikatsuEditor`，兩個都要連結成功。
3. 用 ok-game MCP 的 `reader_launch` 開卡。
   - 卡：`E:/OKPackage/ext60/20_heroine_raiden_shogun.png`，lane `clothpx`。
   - 切服裝 1–5，動作「Demo：女 歩く1」。
4. 布料開關與除錯：
   - `ok.PhysXCloth.*` CVar，以及環境變數 `OK_CLOTH_PX_*`；
   - `OK_CLOTH_PX_DEBUG=1` 會印 detect、每塊布料的 dy 與外擴；
   - 量 dy 的 scratch 腳本 `dy2.lua` 在 session 暫存區，可能已被清掉，需要就重寫：取最後一次建立那塊布料的 log 行，跳過前 3 行再平均。
5. 錄影。
   - 錄製：ffmpeg `gfxcapture=hwnd=<視窗 hwnd>`，編碼 `h264_nvenc`；用 ok-game-mcp CLI 每 5 秒把相機轉到 yaw 0／90／180／270。
   - 左右並排：`hstack`，標字用 `drawtext`，字型 `msjh.ttc`。
   - 目前一輪（修這次回報之前）的成品：
     - `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all\raiden_outfit1_compare_20s.mp4` … `raiden_outfit5_compare_20s.mp4`
     - 單邊：`C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_all\outfit{N}_cloth.mp4`、`outfit{N}_dynamicbone.mp4`
6. 用完 `reader_stop`，然後 `Tools\lua\lua.exe Tools\unreal_slot.lua release`。

## 注意

- 不推送；只提交自己的 hunk；不要在共用工作樹上 checkout、reset、stash。
- 角色卡、原作資料、`grok-media/`、`OKExtractBuildStamp.h` 不提交。
- 腳本只用 Lua（`Tools\lua\lua.exe`），不新增 `.py`／`.ps1`。

## 使用者 11-21 第四次回報（晚上）

> 我沒有要你對齊原始的物理，用 physx 的意義就是要比原本的好……服裝二沒有上物理、穿模了，你要幫他上物理；UI 要可以切換不同的物理；除了 apex 還要新增 flex 的布料模擬。nvflex 一定能做到更好，穿模、布料之間的穿透都能解決，把所有布料的問題都修正。

做了（見 CLOTH_PHYSX_SKIRT_SLEEVE.md「真的模擬與 NVIDIA FleX」）：

- 真布料成為預設，FleX 主機，讀卡器「布料物理」選單。提交 `78434cadb`、`762d51e94`。
- FleX 錄影：
  - `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_flex4\raiden_outfit2_compare_20s.mp4`（服裝 2）
  - `C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_flex3\raiden_outfit3_compare_20s.mp4`、`raiden_outfit5_compare_20s.mp4`

還沒做好：

- 服裝 2：原姿勢藏在骨盆裡的那段紗袍，現在垂在胯前成一團布（不穿模，但皺）；內襯邊緣偶爾從外層上緣露出。
- 服裝 5：側片邊緣有破碎感；要看是布料區和非布料區交界處被拉開，還是三角形翻面。
- FleX 還不是預設；其他角色卡（千佳、惠惠、刻晴、三月七）還沒用 FleX 看過。

### 巡檢（11-21 18:55–19:20，FleX）

- 服裝 5 在 FleX 下碎成一團的原因：形狀偏離就重建（20 秒重設 3 次）、Rust 每幀把往裡垂的布推回 DynamicBone 姿勢的距離、內襯自己模擬時和外層互穿（建立形狀的過濾放過 1 cm 內的粒子對）。已修（`4a713aaec`）：真布料不重建、只推出膠囊本身、FleX 時 Rust 不推膠囊；內襯跟著外層並隨外層表面轉動、不進解算器；過濾半徑 6 mm。
- 試過「FleX 時 Rust 只夾最大距離」（`OK_CLOTH_FLEX_PURE=1`）：幾秒內變尖刺，預設關。關掉自碰撞或身體網格碰撞，畫面差不多。
- 服裝 2 在 FleX 下乾淨：紗袍掛在手臂，背後垂過臀部，不穿身體（`C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_flex5\raiden_outfit2_compare_20s.mp4`）。
- 服裝 5 還有細皺與下擺堆疊；下擺的鋸齒有一部分是和服本身的 alpha 鏤空與深色紋樣（原始物理也有）。

### 巡檢（11-21 19:20–19:30）：FleX 設為預設

- 千佳（歩く1）、惠惠、刻晴（走る1）、三月七（歩く1）在 FleX 下：裙子、袖子垂擺正常，沒有穿模；畫面抖動比姿勢多 0.1–0.4 mm。
- `ok.ClothSolver` 預設 1、Rust 端也預設 FleX（第一次載入就用 FleX 的細網格）；FleX 主機沒註冊時（CLI）用 PhysX。讀卡器選單預設顯示「FleX 布料」。

### 巡檢（11-21 19:30–19:45）：FleX 迭代次數

- 服裝 5 和服下擺起皺、堆疊：迭代 8 → 16 → 24 逐步平順；彎曲 0.7、阻尼 3 反而皺。預設改為迭代 20、子步最多 8（她 42k 粒子一次求解約 15 ms，非同步）。
- 預設設定的錄影：`C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_flex7\raiden_outfit2_compare_20s.mp4`、`raiden_outfit3_compare_20s.mp4`、`raiden_outfit5_compare_20s.mp4`。
- 還沒好：服裝 5 右腰側的垂片有時翻出深色碎片。

### 巡檢（11-21 19:40–23:00）：使用者回報「服裝 2 袖子沒物理、服裝 3／5 碎片化抖動與穿模」

逐項量測（`folds`：折超過直角的三角形比例，減去姿勢本身的）後的處置，提交 `e6462670e`、`a938a30fc`、`3ffab2161`：

| 問題 | 原因 | 處置 | 量測 |
|---|---|---|---|
| 服裝 3／5 皺成碎片 | FleX 切到 1 cm，像紙巾；身體網格碰撞每幀跳動把布擠皺；彎曲記住姿勢的捲曲 | 邊長 2.5 cm、`OKFlexCloth.BodyMesh` 0、`OKFlexCloth.FlatBend` 1 | 和服三塊多餘翻折 11／13／17% → 3.7／2.3／1.7%；女僕裙 4.1% → 1.5% |
| 服裝 2 袖子沒物理 | 三個鏈根附近全部釘住，最低釘點在胯部（1042／2804 粒子） | 手套紗幔只釘臂環（233 個） | 自由粒子 1718 → 2571 |
| 服裝 3 吊襪帶蕾絲穿出裙片 | 皮膚碰撞場只有身體 | 加長襪、褲襪、鞋靴 | — |
| 和服黑色碎片 | 描邊外殼從摺起的前層穿出（原始物理也有） | 物件描邊沿視線後退 1 cm（`ok.OutlinePushBack`） | `ok.Debug.Outline 0` 對照確認 |
| 內襯深色閃爍 | 跟隨的內襯只離外層 1 mm | 至少 4 mm | — |

其他卡（千佳、惠惠、刻晴、三月七）同一版翻折都比上一版少，畫面乾淨。

錄影：`C:\portable\OpenKoikatsu\Saved\OKControl\videos\raiden_flex9\raiden_outfit2_compare_20s.mp4`、`raiden_outfit3_compare_20s.mp4`、`raiden_outfit5_compare_20s.mp4`（左 FleX，右原始物理；左上標籤仍寫「PhysX 布料」）。

還沒好：和服下擺在腳邊偶爾堆疊；描邊後退只做了 MainItemPlus 家族（和服、紗袖），其他描邊家族沒動。

### 巡檢（11-21 22:15–23:10）：和服下擺的黑色旗狀物

- 下擺兩側流蘇旁的黑色旗狀物只在描邊開時出現；原始物理同一位置也有、而且更大（逐幀對照），是這件和服的描邊本身，不是布料造成的。
- 和服的描邊是預先烘好的共用母材質（`M_ForgeOpaque_Outline`、`M_ForgeAlphaMasked_Outline`），執行時加不了往後退的節點；上一輪的 `ok.OutlinePushBack` 只對 MainItemPlus 家族有效。要改得重新產生 `Content/IndependentResources/RuntimeMaterials` 的母材質（影響所有組），先不動。
- 試過、沒用（已撤回）：FleX 自碰撞半徑加大（12 mm／9 mm，像厚布）、布料區法線直接用模擬後的平滑法線。

### 巡檢（11-21 22:30–23:20）

- 和服參數掃過（`OKFlexCloth.Friction` 0.1、`Damping` 2、`Drag` 0.2、`Bend` 0.6）：多餘翻折都在 1–3%，和預設差不多，不改。
- 服裝 2 紗幔在胯前疊成一團、淺藍內面外露：拉回姿勢設 0（`OK_CLOTH_PX_FREE_PULL=0`）一樣。原因是這片紗幔的內側在作者的姿勢裡本來就擺在骨盆裡（原始物理靠穿進身體藏起來），真布料不能進身體，只能停在胯前。下一步：布料建立時先把落在身體裡的粒子移到皮膚外再當靜止形狀（現在是以穿進身體的形狀建立，推出來時擠皺）。
- 試過、撤回：布料建立前先把落在身體裡的粒子推到皮膚外（推的量再和鄰居平均）再當靜止形狀。整片紗幔被推成一面圍在胯前的「圍裙」，2571 個粒子全被帶動、最多 10.7 cm，翻折 12.5%（原本 2.6%）。紗幔內側到底該在前還是在後，幾何上分不出來；下次試「只動在皮膚裡的粒子、往姿勢裡它離得近的那一側皮膚推、不做平均」。
- 再試、撤回：只推在皮膚裡的粒子、不平均。服裝 2 紗幔有 1435／2804 個粒子在姿勢裡就藏在身體內（最深 6.8 cm），推出來仍在胯前成一塊，翻折 6.8%（原本 2.7%）。下一步：把姿勢裡藏在身體內的那部分切掉，不模擬也不顯示（原版那部分本來就看不到），剩下的從手臂自由垂下。
- 再試、撤回：把姿勢裡深於 1.5 cm 藏在身體內的 804 個粒子切掉（不模擬、畫在最近的留下粒子上）。剩下的紗幔仍橫在胯前，切口邊緣成鋸齒碎片，翻折 6.8%。胯前那片不是藏在身體裡的部分造成的：兩片紗袖從上臂垂下本來就在身前交疊（原始物理是讓下緣穿進骨盆）。三種「處理藏在身體裡的布」的做法都比現狀差，服裝 2 先維持現狀（翻折 2.6%）。
