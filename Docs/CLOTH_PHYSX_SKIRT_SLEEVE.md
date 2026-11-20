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
  - 這種衣服**整件留在 DynamicBone**：不再用手臂權重辨識袖子，裡面夾帶的 `cf_j_sk_*` 角落也不做布料。
- **骨頭移植到身體骨架的衣服（coordinated）一律不做布料**：它的鏈在整套衣服骨架裡照跑，旁邊的布料往上浮 10 cm（雷電將軍和服的前片 part 27，原始輸出 dy +100 mm），前片不見、流蘇脫開。開 `OK_CLOTH_PX_CHAINS=1` 才會試。
  - 把袖子鏈做成布料（`OK_CLOTH_PX_CHAINS=1`，實驗）：深度 = 鏈內層數 ÷ 該鏈最深層數，根部固定，最多偏離 DynamicBone 姿勢 `OK_CLOTH_PX_CHAIN_MAX`（預設 6 cm）。走路時長袖垂擺仍會甩開、撕裂，所以預設關閉。

### 模擬網格

- 含區域頂點的三角形全部納入。區域外的頂點自動成為固定的邊界。
- 0.3 mm 內的頂點焊成同一個粒子（UV 接縫、雙面複本）。之前只焊位置完全相同的頂點，結果刻晴的裙子在前面接縫裂開一道縫。
- 重複的三角形去掉。
- 去掉退化三角形：面積 < 0.2 mm²，或面積 < 0.02 × 最長邊²。
- 每個連通塊統一三角形的繞向。
- 沒有任何三角形用到的粒子改成固定。

### 限制（Rust 每幀套用）

- **最大距離**（等同 Unreal 布料的 max distance 遮罩）：自由點離蒙皮位置最多
  - 裙子：0.55 × 到最近固定點的距離 × smoothstep(深度)，上限 0.30 m；
  - 袖子：min(0.35 × 到最近固定點的距離, 0.012 + 0.6 × max(0, r − 0.05))，上限 0.08 m。袖子越寬鬆越能擺。
- **LRA（long-range attachment）**：每個自由點沿網格找測地距離最近的固定點。離它的距離不能超過 1.03 × max(建立時的測地距離, 目前目標到那個固定點的直線距離)。少了這條限制，軟布會被自己的重量拉長，春野的短裙比 DynamicBone 版長了 10 cm。取 max 是因為動作本身的裙骨 key 會把裙子拉得比建立時更長。
- **袖子不內陷**：袖子粒子沿蒙皮法線最多只能往內 2 mm，不然外套底下的襯衫會從袖子穿出來。
- **身體背擋**：粒子離每個身體 capsule 軸的距離，不能小於 min(1.5 × 半徑, 建立時的距離 − 1 mm)。之前用每幀的目標當限制，邁步的大腿會穿過裙子，因為目標裙子不會跟著腿動。
- **回拉**：要交給下一步的偏移，每秒衰減 3 倍（`OK_CLOTH_PX_PULL`）。

環境變數（啟動時讀一次）：`OK_CLOTH_PX_PIN`、`OK_CLOTH_PX_SKIRT_REACH`、`OK_CLOTH_PX_SKIRT_MAX`、`OK_CLOTH_PX_SLEEVE_REACH`、`OK_CLOTH_PX_SLEEVE_MAX`、`OK_CLOTH_PX_SHOULDER`、`OK_CLOTH_PX_CUFF`、`OK_CLOTH_PX_CAPSULE`、`OK_CLOTH_PX_MARGIN`、`OK_CLOTH_PX_STRETCH`、`OK_CLOTH_PX_PULL`、`OK_CLOTH_PX_CARRY`、`OK_CLOTH_PX_REBUILD`。`OK_CLOTH_PX_DEBUG=1` 每秒記一行：原始結果相對目標的平均 dy 和外擴量、飛出去的粒子數。查問題時靠的就是這一行。

### 什麼時候建立布料

PhysX 只會在布料建立的那一刻記下 rest 狀態，之後上傳新的 rest positions 量不出任何差別（`OKPhysXCloth.RestFollow`，預設關）。讀卡器開卡的第一幀是 bind pose，那時剛性裙子比動作裡被裙骨 key 拉下來的高 3–5 cm。如果在那一刻建立，布料會一直把下擺往上收。所以：

- 姿勢持續動了 1.5 秒（讓從 bind pose 淡入動作的過渡結束），或靜止 2 秒，才建立布料。
- 靜止時建立的布料，等姿勢開始動滿 1.5 秒後會重建一次。
- 形狀和建立時相比偏離超過 30%（`OK_CLOTH_PX_REBUILD`，最多每半秒一次）也會重建。走路動作本身的裙骨 key 就會讓形狀變動 6–13%，所以門檻不能設低。
- 姿勢跳動（任一目標一幀移動超過 0.35 m）時，全部放回目標重新開始。
- 等待建立的期間，裙子畫成剛性目標，不會切回 DynamicBone 再切回來。

### 衣服之間不穿模（分層）

- 兩件衣服有同一種布料區（裙子、左袖、右袖）時，只有外層那件是布料，裡層那件照骨架姿勢走，所以兩層不會互穿。
- 外層的判斷：在動作中、布料建立前，量每個區的頂點離身體膠囊的平均距離，以及它垂多遠（裙子取最低點，袖子取離肩膀最遠處，都用第 95 百分位）。另一件比它外 3 mm 以上，而且垂得一樣遠（差 2 cm 內），才算蓋住它。只到臀部的外套不算蓋住底下的裙子。
- 春野千佳：襯衫袖子在外套袖子裡面，改成跟骨架走；外套和褶裙都還是布料。

### 與身體的碰撞

- 有裙子的布料，GPU 上不放身體膠囊：走路時大腿甩進裙子，把千佳的褶裙平均頂高 3–4 cm，前擺翻起（`OKPhysXCloth.Collide 0` 時 −0.2 cm；把膠囊縮到布料裡、摩擦設 0 都沒用）。每步之後 Rust 仍把每個粒子推出身體（不超過建立時的距離）。
- 只有袖子的布料照常放 GPU 膠囊，半徑縮到不超過自由粒子在建立形狀時離它的距離。

### 與 DynamicBone 互斥

- 裙子成為布料的那件衣服，蒙皮時不解它的 DynamicBone（`AccessoryFramePolicy::cloth_rigid`）。骨頭移植到身體骨架上的衣服例外：它的鏈和整套衣服骨架共用，關掉會讓其他垂片變僵，所以照跑，布料只覆蓋自己的頂點。這和 `OK_NO_CLOTH_DYNAMICS` 的 rigid 路線相同：prefab 骨架維持在動作姿勢，跟著掛點走。
- 袖子的頂點綁在身體的手臂骨上，沒有鏈會動到它們，上衣的其他鏈（領巾、衣襬）照常運作。
- 布料建不出來時（沒有 CUDA、區域太小、cooking 失敗），那件衣服標為失敗，自動回到 DynamicBone。

### PhysX 主機（`Plugins/OKPhysXSecondary/Source/OKPhysXSecondary/Private/OKPhysXCloth.cpp`）

- 一件衣服一個 GPU scene（TGS、GPU broadphase）。GPU heap 縮小到每個 scene 數十 MB。
- 從外掛目錄先載入 `cudart64_12.dll` 和 `PhysXGpu.dll`（`Build.cs` 把它們列為 RuntimeDependencies）。少了這一步會出現「Failed to load PhysXGpu.dll」。
- 三角網格不清理、不焊接，直接 cook，cook 完再依位置對回 Rust 的粒子順序。建立時若 `OKPhysXCloth.Log 1`，會先自測一步：網格一致的話，自由點只會因重力移動不到 1 mm。
- **非同步，從不等待**：每幀交出一個背景工作（一次上傳、N 個子步、一次讀回）。工作還在跑時，這幀沿用上一個結果（回傳 3）；跑完的結果屬於它當初拿到的目標，Rust 再把位移從那時每個粒子的局部座標系（法線＋一條鄰邊）搬到這一幀的姿勢上。之所以這樣做，是因為在這台機器上，渲染器也在用同一張 GPU，PhysX 每個子步光同步就要等 7–11 ms，同步做一幀要 40 ms。
- 自由點從 Rust 上一幀顯示的位置開始（已經套過上面的限制）；速度也一起上傳，用前兩次起點的差推算。如果只覆寫位置、留著 GPU 原本的速度，兩者不一致，裙子走路時每一步都會被抬高。
- 固定點的逆質量為 0，放在目標上。
- 身體 capsule（`dbone::body_proxy_capsules`：上臂、前臂、大腿、小腿、骨盆、軀幹、肩）是 kinematic 剛體。
- 材質：`Thickness` 0.5 mm。原本設 3 mm 時，GPU 布料自己會往上往內縮，裙子平均高 5 cm。含裙子的布料 `BendingSkirt` 為 0；只有袖子的布料 `Bending` 為 0.02。原因是任何彎曲剛度，走一段路後都可能把褶子翻到鏡像的 rest 角，把裙子撐高 5 cm；但沒有彎曲的話，惠惠的喇叭袖會塌到袖口。
- CVar：`OKPhysXCloth.Youngs`（2e5）、`Poisson`、`Friction`、`Thickness`、`Bending`、`BendingSkirt`、`ElasticDamping`、`BendDamping`、`Damping`、`Mass`、`Iterations`（12）、`SubstepHz`（120）、`MaxSubsteps`（2）、`Async`（1）、`FeedPrev`（1）、`RestFollow`（0）、`InterpolatePins`、`Collide`、`CudaWait`、`Log`。

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

- 雷電將軍紫色和服整套是 DynamicBone（見上），`ok.ClothPx 1` 和 `0` 看起來一樣。
- 刻晴、三月七沒有在分層與 GPU 膠囊的改動後重拍。

- 三月七（`18_heroine_march_7th`）的 mod 裙子用自己的 `K*`／`joint*` 骨，不在 `cf_j_sk_*` 鏈上，辨識不到，所以只有袖子會變成布料。
- 讀卡器沒有原地轉身的動作，轉身只用鏡頭繞看過；跑步和走路驗證過。
- 布料是在「動了 1.5 秒」的姿勢上建立的。換成一個裙骨 key 差很多的動作時，要等形狀偏離超過 30% 才會重建，在那之前下擺可能比目標高或低幾公分。
- 外套底下的襯衫和外套袖子之間沒有碰撞，只靠「袖子不內陷 2 mm」擋住。
- 只有 `KKUnityBundle` 開啟；街區（`KKRuntimePose`）、群眾仍用 DynamicBone。
