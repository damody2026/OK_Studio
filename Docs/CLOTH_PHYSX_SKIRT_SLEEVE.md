# 裙子與袖子改用 PhysX 布料（2026-11-20）

角色卡上的裙子與袖子不再靠 DynamicBone 甩骨頭，而是自動轉成 PhysX 5.11 的 GPU 布料（`PxDeformableSurface`，FEM 三角網格布料）來模擬，不需要逐卡調整。`ok.ClothPx 0` 會切回原本的 DynamicBone。

## 引擎能用哪一種布料

| 方案 | 在 `D:\PhysX\UE5.8`（`UE5.8-physX-5.11-ok`）的狀態 |
|---|---|
| APEX Clothing | UE5 已移除。引擎裡只剩 `ApexDestruction` 外掛，那是破壞效果，不是布料。 |
| NvCloth | 引擎沒有，`Source/ThirdParty/PhysX3` 是空目錄。 |
| PhysX 5 粒子布料（`PxParticleClothBuffer`） | PhysX 5.11 的標頭已經沒有這個類別。 |
| **PhysX 5.11 `PxDeformableSurface`** | 可用。GameWorks Flex 外掛會把 PhysX 5.11 連同 `PhysXGpu.dll`、`cudart64_12.dll` 一起 stage，`OKPhysXSecondary` 也已連結同一份 SDK。只能在 GPU（CUDA）上跑。**採用這個。** |
| Chaos Cloth | 有外掛，但需要 `USkeletalMesh` 的 clothing 資料和 cloth vertex buffer。讀卡器的衣服是 Rust 蒙皮後用程序網格畫出來的，接不上。 |

## 原本裙子和袖子怎麼動

- 衣服在 Rust（`Tools/ok-extract`）裡是 `AccessoryRuntime`，自帶 prefab 骨架。`update_render_impl` 每幀解 DynamicBone（`dbone.rs`），再蒙皮出頂點。裙子用的是 `ct_clothesBot` 的 `cf_j_sk_<列>_<層>` 鏈，可以交給 `OKPhysXSecondary` 的 PhysX 剛體鏈去解算。
- Unreal 端（`KKPreviewActor`）把蒙皮結果畫成程序網格，有兩條路線：GPU 路線（private GPU，調色盤在 GPU 上蒙皮）和 CPU 路線（由 Rust 給頂點）。
- 袖子沒有 DynamicBone，只跟著手臂骨蒙皮，不會自己擺動。

## 做法

```
衣服蒙皮（布料部件：裙子的 DynamicBone 關掉，走 rigid 路線）
  → cloth_px::apply：取區域頂點的蒙皮位置當目標
  → OKPhysXCloth（PhysX GPU，背景工作）：固定點放在目標上，自由點自己模擬，身體 capsule 當運動學碰撞體
  → Rust：LRA、最大距離、袖子不內陷、推出身體 capsule、法線跟著布轉
  → 寫回頂點（走 CPU 路線上傳）
```

### 自動辨識（`Tools/ok-extract/src/cloth_px.rs`）

全部從衣服網格自己的骨骼權重算出來，不看卡片內容：

- **裙子**：權重 ≥25% 落在 `cf_j_sk_*` 骨上的頂點。只看角色 `clothes_*` 的部件，但排除鞋、襪、褲襪、手套、胸罩、內褲；連身裙的 `clothes_top` 也算。
  - 深度 = 加權後的骨鏈層數 ÷ 這件衣服用到的最大層數（腰是 0，下擺是 1）。
  - 深度 < 0.12 的頂點（腰帶）固定。
- **袖子**：`clothes_top` 裡權重 ≥50% 落在同一側手臂骨上的頂點。手臂骨指名稱含 arm／elbo／wrist／hand 的骨，不含 shoulder。
  - 沿「肩（`cf_j_arm00`）→ 肘（`cf_j_forearm01`）→ 腕（`cf_j_hand`）」投影，得到位置 u 和離手臂軸的距離 r。
  - u < 0.14 固定（肩口）；u > 這隻袖子的最遠處 − 0.05 也固定（袖口）。
- 一側少於 30 個頂點就不做布料。
- **自帶袖子鏈的衣服**（2026-11-21，雷電將軍紫色和服「服裝 5」）：mod 上衣的寬袖由自己的 DynamicBone 鏈（`+SleeveB_L_A21`、`+SleeveB_R_A31`／`A41`，掛在手臂骨下）帶動，還有從腰垂下的長擺（`+BowknotB_CB_A01`）。
  - 鏈的根：衣服自己的 DynamicBone 設定有就用它；骨頭被移植到身體骨架上的衣服（coordinated），設定已清空，改取「被移植、父骨沒被移植」的骨當根。身體骨在這種衣服的骨架裡叫 `__ok_body_bridge/<骨名>`，比對時要去掉前綴。
  - 只認掛在手臂骨下的鏈（袖子）；從腰垂下的長擺與前片不算。
  - 鏈上的頂點是 `KIND_CHAIN` 布料：深度 = 鏈內層數 ÷ 該鏈最深層數，根部固定，最多偏離 DynamicBone 姿勢 `OK_CLOTH_PX_CHAIN_MAX`（預設 6 cm）。不再用手臂權重辨識這種衣服的袖子。
  - 手套（`clothes_gloves`）也看自己的鏈：雷電服裝 2 掛在手臂上的紗袍是手套部件，24 根骨移植到身體上。沒有鏈的一般手套不做布料。
- **骨頭移植到身體骨架的衣服（coordinated）也做布料（2026-11-21 起）**：它的鏈在整套衣服骨架裡照跑，布料跟著 DynamicBone 姿勢擺（下面「跟著 DynamicBone 擺」），偏移另外和鄰點平均（`OK_CLOTH_PX_SMOOTH`，預設 6 次；2026-11-21 晚起所有布料都做，`OK_CLOTH_PX_SMOOTH_ALL=0` 只做跟著 DynamicBone 的），免得各點各自被夾住而邊緣鋸齒、撕開。
  - 以前這兩類衣服整件留在 DynamicBone，理由是「布料浮起 10 cm、撕裂」。那些現象其實是主機上傳失效造成的（見「PhysX 主機」）。`OK_CLOTH_PX_CHAINS=0` 回到舊做法。

### 模擬網格

- 含區域頂點的三角形全部納入。區域外的頂點自動成為固定的邊界。
- 0.3 mm 內的頂點焊成同一個粒子（UV 接縫、雙面複本）。之前只焊位置完全相同的頂點，結果刻晴的裙子在前面接縫裂開一道縫。
- 重複的三角形去掉。
- 去掉退化三角形：面積 < 0.2 mm²，或面積 < 0.02 × 最長邊²。
- 每個連通塊統一三角形的繞向。
- 沒有任何三角形用到的粒子改成固定。

### 加面（`Tools/ok-extract/src/cloth_refine.rs`，2026-11-21）

面數少的衣服只能在少數幾條邊上折，像紙板：雷電的女僕長裙 776 頂點、和服裙片 953 頂點。

- 衣服的骨架建好後（`push.rs`），用同一套辨識找出布料區；碰到布料區的三角形一直切到每條邊不超過 `OK_CLOTH_PX_EDGE`（預設 25 mm，0 關閉）。每次切三角形最長的那條邊，三角形形狀才不會變爛；最多 8 輪，新增頂點不超過原本 6 倍（4000–40000）。切好後骨架用新網格重建一次。
- 新頂點是邊的中點：位置、法線、切線、UV、頂點色、蒙皮權重、morph 位移都取兩端平均，所以布料不動時看起來和原本一樣。
- 邊用「位置」判斷要不要切，不用頂點編號：UV 接縫和雙面複本在同一位置有各自的頂點，只切一邊會沿接縫裂開。兩邊各有自己的中點（各自的 UV），位置相同，布料再把它們焊成一個粒子。
- 只在有 PhysX 布料主機時做（`OK_CLOTH_PX_REFINE=1` 強制、`0` 關閉），沒有主機的 CLI 與轉卡不受影響。
- 結果（雷電）：女僕長裙 776 → 3600 頂點；和服裙片 953 → 3434；紗袍 2731 → 5144。

### 限制（Rust 每幀套用）

- **最大距離**（等同 Unreal 布料的 max distance 遮罩）：自由點離蒙皮位置最多
  - 裙子：0.55 × 到最近固定點的距離 × smoothstep(深度)，上限 0.30 m；
  - 袖子：min(0.35 × 到最近固定點的距離, 0.012 + 0.6 × max(0, r − 0.05))，上限 0.08 m。袖子越寬鬆越能擺。
- **LRA（long-range attachment）**：每個自由點沿網格找測地距離最近的固定點。離它的距離不能超過 1.03 × max(建立時的測地距離, 目前目標到那個固定點的直線距離)。少了這條限制，軟布會被自己的重量拉長，春野的短裙比 DynamicBone 版長了 10 cm。取 max 是因為動作本身的裙骨 key 會把裙子拉得比建立時更長。
- **袖子不內陷**：袖子粒子沿蒙皮法線最多只能往內 2 mm，不然外套底下的襯衫會從袖子穿出來。
- **身體背擋（2026-11-21 下午起每幀算）**：粒子離每個身體 capsule 軸的距離，不能比**這一幀**姿勢離它近，上限 1.5 × 半徑 + 4 cm（`OK_CLOTH_PX_KEEP_OUT`）。兩輪（臀和大腿的膠囊重疊）。以前用建立時的距離：走路後姿勢變了，太小的讓雷電服裝 2 的紗袖垂進腰臀與胯下，太大的每幀把布料推出姿勢之外。`OK_CLOTH_PX_LIVE_PUSH=0` 回到建立時的距離。更早（11-20）用每幀目標時大腿會穿過裙子，那是主機上傳失效、布料根本沒在模擬時的結論（見「PhysX 主機」）。
- **回拉**：交給主機的修正裡，加上把結果往姿勢拉回的量，每秒 3 倍（`OK_CLOTH_PX_PULL`），依這次工作涵蓋的時間計算。
- **身體皮膚（2026-11-21 晚，`Tools/ok-extract/src/cloth_skin.rs`）**：膠囊比風格化的身體細，雷電服裝 2 的紗袖穿過大腿、服裝 5 的裙片穿過小腿時，每個粒子都還在膠囊外。所以有布料的角色每幀把身體網格（每 1 cm 方塊取一點，`THIN_M`）用骨架 palette 擺好，放進 4 cm 的格子。粒子讀周圍 27 格的皮膚點，以高斯（σ 1 cm）加權算出離皮膚的距離和往外的方向，比皮膚外 4 mm（`OK_CLOTH_PX_SKIN_MARGIN`）近就推出去，但不比姿勢本身更外。
  - 讀數的可信度 0–1：兩邊皮膚方向相反處（兩腿之間，沒有往外的方向）和最近皮膚接近 4 cm 時逐漸降到 0。用最近四點反距離加權時，點一換讀數就跳，被推的布料抖（1.7 → 3.6 mm／幀）。
  - 成本：每個粒子每幀查 5 次（need／hold 一次、兩次限制各兩次）。查詢一次掃描 27 格（找到更近的皮膚點時把已累加的權重縮小），並用 rayon 平行；最早兩次掃描、單執行緒時雷電從約 110 fps 掉到 70。
  - **姿勢本身在身體裡的地方，布料留在姿勢上**：雷電紗袖的 DynamicBone 姿勢有一段垂進腰臀裡（原版就藏在身體裡看不到），把它推出皮膚會擠成一團皺在肚子前。姿勢在皮膚下 5 mm（`OK_CLOTH_PX_SKIN_DEEP`）以內完全留住，往外到皮膚外 3 cm（`OK_CLOTH_PX_HOLD_OUT`）逐漸放開；推出量也乘上同樣的比例。`OK_CLOTH_PX_SKIN=0` 關掉整個皮膚碰撞。
- **膠囊下限**：`OK_CLOTH_PX_CAP_FLOOR`（預設 0）讓粒子不論姿勢都至少離膠囊軸這麼多倍半徑。設 1 會把垂進骨盆的紗袖往外推皺，皮膚碰撞已經處理穿模，所以預設不用。
- **長裙避開小腿**：長裙垂下的部分離小腿膠囊軸至少 1.5 × 半徑，不管姿勢離多近（`OK_CLOTH_PX_SHIN`，預設開）。走路中途建立時小腿已經在和服裙片裡，舊規則（不超過建立時的距離）就讓它一直穿過去。
- 這些限制寫成一個函式（`constrain`），每幀用兩次：一次用在 GPU 剛做完的結果上，算出要交給主機的修正（見「PhysX 主機」的收／發）；一次用在畫面顯示的位置上。

環境變數（啟動時讀一次）：`OK_CLOTH_PX_PIN`、`OK_CLOTH_PX_SKIRT_REACH`、`OK_CLOTH_PX_SKIRT_MAX`、`OK_CLOTH_PX_SLEEVE_REACH`、`OK_CLOTH_PX_SLEEVE_MAX`、`OK_CLOTH_PX_SHOULDER`、`OK_CLOTH_PX_CUFF`、`OK_CLOTH_PX_CAPSULE`、`OK_CLOTH_PX_MARGIN`、`OK_CLOTH_PX_STRETCH`、`OK_CLOTH_PX_PULL`、`OK_CLOTH_PX_CARRY`、`OK_CLOTH_PX_REBUILD`、`OK_CLOTH_PX_EDGE`、`OK_CLOTH_PX_REFINE`、`OK_CLOTH_PX_CHAINS`、`OK_CLOTH_PX_SMOOTH`、`OK_CLOTH_PX_SHIN`、`OK_CLOTH_PX_SKIRT_CAPS`、`OK_CLOTH_PX_KEEP_OUT`、`OK_CLOTH_PX_LIVE_PUSH`、`OK_CLOTH_PX_BLEND`、`OK_CLOTH_PX_SMOOTH_ALL`、`OK_CLOTH_PX_SKIN`、`OK_CLOTH_PX_SKIN_MARGIN`、`OK_CLOTH_PX_SKIN_DEEP`、`OK_CLOTH_PX_HOLD_OUT`、`OK_CLOTH_PX_CAP_FLOOR`、`OK_CLOTH_PX_LAYER_GAP`、`OK_CLOTH_PX_DAMP`、`OK_CLOTH_PX_DAMP_T`；診斷用 `OK_CLOTH_PX_SKIN_HOST=0`（皮膚推出只用在畫面，不交給 GPU）、`OK_CLOTH_PX_HOLD=0`（不把姿勢在身體裡的布料留在姿勢上）、`OK_CLOTH_PX_SKIN_SIGMA`（皮膚讀數的高斯寬度，預設 0.01 m）。`OK_CLOTH_PX_DEBUG=1` 每秒記兩行：
- `jitter`：姿勢（raw）和畫面上的布料（shown）在她的骨架空間裡每幀位置的二階差分，取自由粒子的平均，加上這一秒的幀數和新結果數。平滑的走路在 200 fps 下應不到 0.1 mm；讀卡器的姿勢本身就有 5–6 mm（動畫取樣不均勻，身體一樣），所以看的是 shown 有沒有比 raw 大。不要量「布料相對姿勢的偏移」：姿勢在跳時，那個量會把姿勢的抖動算成布料的。
- `debug`：顯示的布料相對目標的平均 dy 和外擴量、飛出去的粒子數，以及那一幀主機的回傳碼（2 是新結果、3 是工作還在跑）和姿勢跳動。

### 什麼時候建立布料

PhysX 只會在布料建立的那一刻記下 rest 狀態，之後上傳新的 rest positions 量不出任何差別（`OKPhysXCloth.RestFollow`，預設關）。讀卡器開卡的第一幀是 bind pose，那時剛性裙子比動作裡被裙骨 key 拉下來的高 3–5 cm。如果在那一刻建立，布料會一直把下擺往上收。所以：

- 姿勢持續動了 1.5 秒（讓從 bind pose 淡入動作的過渡結束），或靜止 2 秒，才建立布料。
- 靜止時建立的布料，等姿勢開始動滿 1.5 秒後會重建一次。
- 形狀和建立時相比偏離超過 30%（`OK_CLOTH_PX_REBUILD`，最多每半秒一次）也會重建。走路動作本身的裙骨 key 就會讓形狀變動 6–13%，所以門檻不能設低。
- 姿勢跳動（任一目標一幀移動超過 0.35 m）時，全部放回目標重新開始。
- 等待建立的期間，裙子畫成剛性目標，不會切回 DynamicBone 再切回來。

### 裙子跟著 DynamicBone 擺（2026-11-21 起）

- 裙子的 DynamicBone 照跑，布料只在它的姿勢周圍擺動：最多偏離 5 cm（`OK_CLOTH_PX_LONG_MAX`），而且不准比它的姿勢高 5 mm 以上（`OK_CLOTH_PX_UP`）。
- 原因：
  - 布料在走路中途建立，PhysX 就把那一刻的張開形狀當成靜止形狀，之後改不掉。自由的裙子會依建立時機高 1–4 cm 或低 1 cm（惠惠的裙底因此露出）。調軟、變薄、泊松比 0、加迭代、加強拉回都沒有改變。
  - 身體膠囊比穿過膝襪的腿細，長裙前片會被腿頂穿。DynamicBone 有自己的碰撞，形狀和原作一致。
- `OK_CLOTH_PX_LONG_SPAN`（預設 0）：裙長超過這個值才跟著 DynamicBone。設成 0.35 等於回到「只有長裙跟著」。
- 驗證：雷電五套各錄 20 秒多角度對比（女僕長裙、巫女短褶裙與原始物理一致）；惠惠、千佳的裙子蓋住，和原始物理一樣長。

### 衣服之間不穿模（分層）

- 兩件衣服有同一種布料區（裙子、左袖、右袖）時，只有外層那件是布料，裡層那件照骨架姿勢走，所以兩層不會互穿。
- 外層的判斷：在動作中、布料建立前，量每個區的頂點離身體膠囊的平均距離，以及它垂多遠（裙子取最低點，袖子取離肩膀最遠處，都用第 95 百分位）。另一件比它外 3 mm 以上，而且垂得一樣遠（差 2 cm 內），才算蓋住它。只到臀部的外套不算蓋住底下的裙子。
- 春野千佳：襯衫袖子在外套袖子裡面，改成跟骨架走；外套和褶裙都還是布料。
- 只比同一種區（2026-11-21）：以前把「裙」和「鏈」當同一層，鏈現在只指手臂上的袖鏈，它的「垂多遠」是離肩距離，和裙子的最低點不能比；合併時雷電和服的裙片「蓋住」了自己的袖子。
- **同一件衣服的內襯（2026-11-21 晚）**：內襯是外層底下幾 mm 的另一片網格。兩片各自模擬會互穿：雷電紗袖的淺藍內襯一塊塊從紫色外層穿出來。同一件衣服裡，一片網格（三角形連通的一塊）有一半以上的頂點離較大的那片不到 6 mm（`OK_CLOTH_PX_LAYER_GAP`，0 關閉），它就不模擬：固定在姿勢上，畫面上跟著較大那片最近的粒子移動，間距不變。log 會印 `OK cloth px layers`。
- 只量這個部件自己三角形用到的頂點，而且同一個 mesh 的子網格不互相比：一件衣服的子網格共用整個頂點緩衝，量全部頂點時和服的每個子網格都找到「別的部件蓋住它」，結果沒有一塊是布料。

### 與身體的碰撞

- 2026-11-21 起，裙子也在 GPU 上放身體膠囊（`OK_CLOTH_PX_SKIRT_CAPS=0` 關掉）。之前不放，理由是「大腿把千佳的褶裙頂高 3–4 cm」，但那是主機上傳失效時的量測（見「PhysX 主機」）；布料真的在模擬後，腿要靠 GPU 膠囊推開裙片。每步之後 Rust 仍把每個粒子推出身體。
- GPU 膠囊的半徑縮到不超過自由粒子在建立形狀時離它的距離。Rust 端的推出改成每幀依姿勢算（見「限制」的身體背擋）。

### 與 DynamicBone 互斥

- 只有袖子當布料（沒有裙子）的衣服，蒙皮時不解它的 DynamicBone（`AccessoryFramePolicy::cloth_rigid`）；裙子見上一節，DynamicBone 照跑。骨頭移植到身體骨架上的衣服例外：它的鏈和整套衣服骨架共用，關掉會讓其他垂片變僵，所以照跑，布料只覆蓋自己的頂點。這和 `OK_NO_CLOTH_DYNAMICS` 的 rigid 路線相同：prefab 骨架維持在動作姿勢，跟著掛點走。
- 袖子的頂點綁在身體的手臂骨上，沒有鏈會動到它們，上衣的其他鏈（領巾、衣襬）照常運作。
- 布料建不出來時（沒有 CUDA、區域太小、cooking 失敗），那件衣服標為失敗，自動回到 DynamicBone。

### PhysX 主機（`Plugins/OKPhysXSecondary/Source/OKPhysXSecondary/Private/OKPhysXCloth.cpp`）

- 一件衣服一個 GPU scene（TGS、GPU broadphase）。GPU heap 縮小到每個 scene 數十 MB。
- 從外掛目錄先載入 `cudart64_12.dll` 和 `PhysXGpu.dll`（`Build.cs` 把它們列為 RuntimeDependencies）。少了這一步會出現「Failed to load PhysXGpu.dll」。
- 三角網格不清理、不焊接，直接 cook，cook 完再依位置對回 Rust 的粒子順序。建立時若 `OKPhysXCloth.Log 1`，會先自測一步：網格一致的話，自由點只會因重力移動不到 1 mm。
- **非同步，從不等待**：每幀交出一個背景工作（一次上傳、N 個子步、一次讀回）。工作還在跑時，這幀沿用上一個結果（回傳 3）；跑完的結果屬於它當初拿到的目標，Rust 再把位移從那時每個粒子的局部座標系（法線＋一條鄰邊）搬到這一幀的姿勢上。之所以這樣做，是因為在這台機器上，渲染器也在用同一張 GPU，PhysX 每個子步光同步就要等 7–11 ms，同步做一幀要 40 ms。
- **不寫位置，只給速度（2026-11-21，`OKPhysXCloth.PinByVelocity` 1）**：解算器把主機寫進去的位置當成這一步內的位移，換成速度。以前每步把固定點放到新目標、自由點放到 Rust 顯示的位置，速度就被灌到上限 8 m/s；第一個卡頓幀之後整塊布（固定點也一起）飛走，再也回不來，畫面上只剩 Rust 的夾限結果。11-20／21 上午所有「裙子上浮」的量測與調參都是在這個狀態下做的。現在：
  - 固定點（逆質量 0）給（目標 − GPU 上的位置）÷ Dt 的速度，子步跑完剛好到目標；
  - 自由點保留 GPU 自己的位置和速度（每次讀回位置時也讀回速度）；Rust 對結果做的修正（夾限、推出身體、回拉）用速度交給它（`OKPhysXCloth.SteerGain`，預設 1，最大 6 m/s）：逆著修正方向的那部分速度歸零（像碰撞），修正本身只移動它、步完就從速度裡扣掉，不留成動量。跟著 DynamicBone 的長裙就是靠這個不會飄走。
  - `PinByVelocity 0` 是舊做法（`FeedPrev`：位置與推算速度一起寫），只留作對照。
- **先收、再算、再發（2026-11-21 下午）**：每幀 Rust 先用 Dt 0 呼叫一次 `Step`，只收已做完的工作結果（回傳 2；還在跑回傳 3；沒有工作回傳 0）；對**這個結果**套用限制，算出修正，轉回那個結果建立時的姿勢座標，再呼叫一次 `Step` 發出下一個工作，修正放在 `Prev`（建立旗標 bit 1：`Prev` 是修正量而不是位置）。以前修正和發工作是同一次呼叫，算的是前一個結果：非同步模式下主機把每個點拉回上一個結果，雷電的女僕長裙在兩個結果之間來回翻（60 fps 每幀 19 mm）。
- **兩次結果之間平滑過去（`OK_CLOTH_PX_BLEND`，預設開）**：GPU 工作在渲染器同時使用 GPU 時要 20 ms，200 fps 下約 6 幀才回一次結果。中間的幀以前顯示「往姿勢衰減中的舊結果」，新結果一到又跳出去，形成鋸齒。後來改成畫面上的偏移每幀往最新結果移動 dt ÷（平均結果間隔），但 60 fps 下每 3 幀才一個結果，運動方向每次結果到達就折一下，和服比姿勢多抖 1.5–2 倍。2026-11-21 晚起改用臨界阻尼彈簧追最新結果（`OK_CLOTH_PX_DAMP`，時間 = 平均結果間隔 × `OK_CLOTH_PX_DAMP_T`，預設 2），速度連續。量過 1、2、3 倍：2 倍明顯比 1 倍好，3 倍沒有再好。
- 一次工作最多模擬 `OKPhysXCloth.MaxDt`（預設 34 ms）秒，多的丟掉：切動作時的 0.1 s 卡頓原本變成兩個 50 ms 子步。以前上限是 MaxSubsteps ÷ SubstepHz（16.7 ms），工作要 20 ms 時布料只跑到 2/3 速度。
- 上傳改用同步的 `copyHToD` 再 `markDirty`（`PxDeformableSurfaceExt::copyToDevice` 在 stream 0 上非同步拷貝）。
- `OKPhysXCloth.Log 2`：每次工作記一行，自由點與固定點這次移動了多少、GPU 上最快的速度。固定點本來不該動，它若「移動」就是上傳出了問題。
- 身體 capsule（`dbone::body_proxy_capsules`：上臂、前臂、大腿、小腿、骨盆、軀幹、肩）是 kinematic 剛體。
- 材質：`Thickness` 0.5 mm。原本設 3 mm 時，GPU 布料自己會往上往內縮，裙子平均高 5 cm。彎曲剛度 `Bending`（只有袖子）與 `BendingSkirt`（含裙子）都是 0.5（2026-11-21 晚起）。以前裙子 0、袖子 0.02，理由是「彎曲剛度會把褶子翻到鏡像的 rest 角、撐高裙子 5 cm」，但那是主機上傳失效時的判斷；布料真的在模擬後，0 讓雷電的女僕長裙皺得像紙巾、下擺鋸齒，0.5 平整垂下，服裝 4 紅褶裙的褶子仍在（dy ±4 mm）；千佳（歩く1）、惠惠、刻晴（走る1）也重錄過（2026-11-21 晚），裙長與原始物理一致、惠惠喇叭袖張開、刻晴跑步沒有穿腿，畫面布料抖動和姿勢相同（shown − raw ≤ 0.25 mm）。
- CVar：`OKPhysXCloth.Youngs`（2e5）、`Poisson`、`Friction`、`Thickness`、`Bending`、`BendingSkirt`、`ElasticDamping`、`BendDamping`、`Damping`、`Mass`、`Iterations`（12）、`SubstepHz`（120）、`MaxSubsteps`（2）、`MaxDt`（0.034）、`Async`（1）、`PinByVelocity`（1）、`SteerGain`（1）、`SteerKeep`（1，只用在位置模式；修正模式固定為 0）、`FeedPrev`（1）、`RestFollow`（0）、`InterpolatePins`、`Collide`、`CudaWait`、`Log`（1 或 2）。

### Unreal 端

- `ok.ClothPx`：1（預設）裙子和袖子；2 只有裙子；3 只有袖子；0 關閉，回到原本的 DynamicBone。改值時所有布料重建。
- 布料部件一律走 CPU 路線（private GPU 閘門多檢查 `Session.ClothPxPart`）；`ok.PrivateGpuParts` 會列出 `physx cloth`。
- `ok.ClothPxStats`：列出上次呼叫以來的布料數、粒子數、步數、每步毫秒、最大偏移、夾住與推出次數。
- 只有 `KKUnityBundle`（讀卡器、Studio、1 對 1）把模式設為開。街區的 `KKRuntimePose` 有自己的一份 ok_extract，模式預設 0，不受影響；群眾也不受影響。

## 量測（讀卡器，編輯器 Development 版，RTX 5090，2026-11-20）

先切到該動作，等布料建好，再用 `ok.ClothPx 1/0` 切換，各等 3 秒讀 `ui_state` 的 FPS。

| 卡 | 動作 | 布料 | ClothPx 1 FPS | ClothPx 0（DynamicBone）FPS | 外觀 |
|---|---|---|---:|---:|---|
| 春野千佳（`26_kks_haruno_chika`） | 歩く1 | 短褶裙 559 粒子＋外套袖 962＋上衣 1237 | 140–145 | 150 | 褶裙自然下垂，走路時前後擺，長度和 DynamicBone 一致 |
| 刻晴（`16_heroine_keqing`） | 走る1 | 格子褶裙＋外套袖 | 187 | 204 | 跑步時裙擺外甩，沒有破洞或穿腿 |
| 惠惠（`19_heroine_megumin`） | 走る1 | 裙 618＋喇叭袖 688 | 162–165 | 181–190 | 寬袖跟著手臂擺，袖口張開 |

- 布料在主執行緒上的成本只有交出／收回工作：每步 0.01–0.05 ms（`ok.ClothPxStats`）。
- GPU 背景工作每次約 30–60 ms，和渲染搶 GPU。FPS 掉 5–15% 主要來自這裡，以及布料部件改走 CPU 路線、每幀上傳頂點。
- 布料的結果比姿勢晚一個背景工作（約 2–4 幀）。用局部座標系搬運位移之後，看不出延遲。

## 限制

- 雷電將軍紫色和服（服裝 5）以前整套是 DynamicBone；2026-11-21 起袖鏈與移植骨的衣服也做布料（見「自動辨識」）。
- 刻晴、三月七在 2026-11-21 晚的預設（皮膚碰撞、彎曲 0.5、阻尼平滑）下重錄過，沒有退步：`C:\portable\OpenKoikatsu\Saved\OKControl\videos\others7\keqing_outfit1_compare_20s.mp4`、`march7_outfit1_compare_20s.mp4`（三月七裙下的深色是她的短褲，原始物理同一時刻也看得到）。

- 三月七（`18_heroine_march_7th`）的 mod 裙子用自己的 `K*`／`joint*` 骨，不在 `cf_j_sk_*` 鏈上，辨識不到，所以只有袖子會變成布料。
- 讀卡器沒有原地轉身的動作，轉身只用鏡頭繞看過；跑步和走路驗證過。
- 布料是在「動了 1.5 秒」的姿勢上建立的。換成一個裙骨 key 差很多的動作時，要等形狀偏離超過 30% 才會重建，在那之前下擺可能比目標高或低幾公分。
- 外套底下的襯衫和外套袖子之間沒有碰撞，只靠「袖子不內陷 2 mm」擋住。
- 只有 `KKUnityBundle` 開啟；街區（`KKRuntimePose`）、群眾仍用 DynamicBone。

## 真的模擬與 NVIDIA FleX（2026-11-21 晚）

使用者要的是比原始物理好（不穿模、各層不互穿），不是和原始物理一樣。上面「跟著 DynamicBone 擺」那一套把布料限制在姿勢 5–6 cm 內並拉回姿勢，畫面幾乎就是原始物理，雷電服裝 2 紗袍等於沒上物理、仍從胯下穿出（見 `Docs/ERROR_LOG.md` 同日）。

### 真布料（`OK_CLOTH_PX_FREE`，預設 1）

- 布料只從固定列垂下：最多離姿勢 `OK_CLOTH_PX_FREE_MAX`（30 cm），拉回姿勢只剩每秒 `OK_CLOTH_PX_FREE_PULL`（0.3）。
- 不在姿勢落在身體裡時留在姿勢上；皮膚推出要求在皮膚外 `OK_CLOTH_PX_SKIN_MARGIN`；Rust 端身體膠囊推出用整個半徑；GPU 膠囊不再縮小；裙子可以被腿踢高。
- 長裙也關掉 DynamicBone（移植骨的衣服除外，它的鏈和整套衣服共用）。
- `OK_CLOTH_PX_FREE=0` 回到跟著 DynamicBone 擺。

### FleX 主機（`Plugins/OKPhysXSecondary/Source/OKPhysXSecondary/Private/OKFlexCloth.cpp`）

- NvFlex 1.2：用引擎 `Engine/Plugins/GameWorks/Flex` 留下的原版標頭與 DLL（那個外掛的執行期已改用 PhysX 5.8，不再載入它們）。建置時把 `NvFlexReleaseCUDA_x64.dll`、`NvFlexReleaseD3D_x64.dll` 等複製到本外掛 `Binaries/ThirdParty/Win64`，執行時載入：先 CUDA（RTX 5090 上可用，DLL 內有 PTX），不行用 D3D11 compute（`OKFlexCloth.Backend`）。
- 和 PhysX 主機同一組 Create／Step／Release 介面，另加 Bind（布料屬於哪個角色）與 Body（她這一幀的身體網格）。Rust 端 `ok_set_flex_cloth`、`ok_cloth_px_solver`，Unreal 端 `ok.ClothSolver`（0 PhysX、1 FleX）。
- 每個角色一個 FleX 解算器，她所有布料都在裡面，粒子之間互相碰撞（內襯與外層、袍子與裙子）。碰撞形狀是身體膠囊（`OKFlexCloth.Capsules`）；她的身體網格（`OKFlexCloth.BodyMesh`）預設關：FleX 的三角網格沒有速度，每次求解整幀跳一次，走路的大腿落在布上把布擠皺（和服側垂片翻折的三角形多一倍）。不讓布進皮膚交給 Rust 的皮膚碰撞場。
- 全部布料同一個 group、自碰撞、依建立時的形狀過濾（`eNvFlexPhaseSelfCollideFilter`）：建立時就在半徑內的粒子對永遠不碰。原姿勢裡各層本來就互穿（和服裙片、紗袍內襯），每片一個 group 時 FleX 一開始就同時把它們拉開，和服纏成一團堆在腳邊。
- 各件衣服的層次（2026-11-22，`keep_layers`，`OK_CLOTH_PX_LAYER_ORDER`，預設開）：FleX 的粒子半徑 6 mm、間距約 25 mm，布對布只靠粒子碰撞擋不住，惠惠跑步時粉紅百褶裙從大衣背面整條穿出來。每件衣服記下裙襬類粒子在建立時離骨盆垂直軸的水平距離；顯示前，若某粒子附近（現在 4 cm、建立時 5 cm 內）有別件衣服的粒子建立時在它內側 5 mm 以上，現在卻在外面，就把它沿水平方向推到最外那個之外 6 mm（`OK_CLOTH_PX_LAYER_KEEP`）。別件用上一幀顯示的位置，只在沒被鎖住時讀（不互等）。惠惠背面粉紅比例 6.50% → 0.32%（十張平均）；雷電、千佳、刻晴、三月七畫面不變。
- 每次求解：先收結果（Step 的 Dt 0），Rust 算修正，再交出這一幀的目標；她的布料全部交齊（或同一塊交第二次）才開始求解，非同步跑在 worker 上；FleX 呼叫在 `GFlexLock` 內，共用狀態在 `GLock` 內，求解時不握 `GLock`，遊戲執行緒不會等 GPU。
- 彈簧：每條邊一條拉伸彈簧（`OKFlexCloth.Stretch` 1.0），共邊兩三角形的對角一條彎曲彈簧（`OKFlexCloth.Bend` 0.3；0.05 時女僕長裙下擺會皺）。彎曲彈簧的靜止長度是兩個三角形攤平時的對角距離（`OKFlexCloth.FlatBend` 1）：用建立當下的姿勢當靜止形狀時，布記住 DynamicBone 的捲曲，像硬紙一樣（服裝 2 紗袖一直捲在胯前）。
- FleX 時 Rust 端：布料邊長最多 2.5 cm（`OK_CLOTH_FLEX_EDGE`）、不判斷誰蓋住誰、偏移平滑 1 次（`OK_CLOTH_FLEX_SMOOTH`）。1 cm 時布像紙巾一樣皺：14–20% 的三角形折超過直角（姿勢本身 1–3%），和服出現碎片；2–2.5 cm 只剩三分之一，粒子數約五分之一，幀率也高很多。
- 內襯（同一件衣服 6 mm 內的較小網格片）跟著外層、不進解算器；顯示時至少離外層 4 mm（`OK_CLOTH_PX_LINING_GAP`）。原本只差 1 mm，兩層三角化不同，彎處互相穿插閃出深色。
- 手套上的自帶鏈紗幔（雷電服裝 2）：只釘縫在手臂上的粒子，不在鏈根附近釘住（原本 2804 個粒子釘了 1042 個，最低釘點在胯部，袖子沒有物理可言）。上衣的袖鏈根就是袖口接縫，照舊釘住（放開和服袖子會皺成團）；`OK_CLOTH_PX_CHAIN_ROOT_PIN=1` 回到全部釘住。
- 皮膚碰撞場除了身體，還包含長襪、褲襪、鞋靴（有自己骨架的用上一幀蒙皮結果）：布不再停在皮膚與襪面之間（女僕裙被吊襪帶蕾絲穿出）。
- 診斷（`OK_CLOTH_PX_DEBUG=1`）：`folds`（折超過直角的三角形比例，和姿勢比）、`build`（建不起來的原因）、`pins`（釘點數量與最低高度）、`skin`（皮膚碰撞場用了哪些部件）、`layers`（內襯離領頭粒子多遠）；`OK_CLOTH_PX_ONLY=23,27` 只讓指定部件當布料。
- 和服的黑色碎片是描邊：布摺起來時後層離前層比描邊外殼還近，黑色外殼從前層穿出（`ok.Debug.Outline 0` 時全部消失；原始物理也有）。物件描邊（MainItemPlus）外殼沿視線往後退 `ok.OutlinePushBack`（1 cm）。
- 其他 CVar：`OKFlexCloth.Iterations`（20；8 時和服下擺起皺堆疊）、`SubstepHz`（240）、`MaxSubsteps`（8）、`MaxDt`、`Radius`（1 cm）、`SolidRest`（5 mm）、`BodyDistance`（4 mm）、`Friction`、`ParticleFriction`、`Damping`、`Drag`、`Lift`、`SelfCollide`、`Async`、`Log`。

### 讀卡器選單

「衣服 › 布料物理」（`control.PhysicsCombo`）：原始物理（DynamicBone）／PhysX 布料／FleX 布料。換 PhysX／FleX 會重新載入模型（兩者切網格的大小不同）。2026-11-21 晚起預設 FleX（`ok.ClothSolver` 1；FleX 主機沒註冊時自動用 PhysX）：雷電服裝 2／3／5 與千佳、惠惠、刻晴、三月七在 FleX 下都沒有穿模，畫面抖動比姿勢多 0.1–0.4 mm。
