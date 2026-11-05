# OK Studio：素體重製與去原作素材計畫（2026-11-04）

目標：做出一個**不含任何原作與第三方 mod 素材**、可以公開散布的版本，產品名稱 **OK Studio**（取代 `OpenKoikatsu`）。同時保留「使用者自己有原作時，在本機還原相容資料」的路線（下稱 **Compat**，即 [原作資料移出版控計畫](ORIGINAL_DATA_OUT_OF_GIT_PLAN_20261104.md) 的 `restore_original_data.lua`）。

盤點依據：[基礎庫共用資源盤點](BASE_LIBRARY_SHARED_INVENTORY_20261104.md)、[原作資料移出版控計畫](ORIGINAL_DATA_OUT_OF_GIT_PLAN_20261104.md)、[新版 OK 卡](OK_CHARA_CARD.md)。

> 本文是工程規劃，不是法律意見。公開散布或商業化前，請找熟悉日本／台灣著作權與商標的律師確認。下表的授權是撰寫時的認知，引入前要到各專案的 LICENSE 再確認一次。

## 一、可行性結論

**可行，但「換掉素體」只是其中一塊。** OK Studio 散布的每一個檔案（素材、資料、程式碼）都要能說出自製或合法授權的來源。原作與第三方的成分分在五層：

| 層 | 現況 | 本計畫章節 |
|---|---|---|
| 1. 素體網格與貼圖 | `oo_base`、`bo_head`、`oo_hand`、`mm_base`、`mt_body`／`mt_face`／`mt_eye` 等都來自原作 | 四、P2 |
| 2. 素體資料 | 身形滑桿曲線 `cf_anmShapeBody`／`cf_anmShapeHead_00`／`cf_anmShapeHand`、rest pose、臉型預設、`shapecorrect` 清單 | 四、P3 |
| 3. 其他素材 | 衣服、頭髮、配件、Studio 動畫（5,806）、paired 動作、語音、BGM、台詞翻譯、ramp、146 個由遊戲／mod shader 轉出的 `.inl` | 四、P4～P6 |
| 4. 第三方 mod | UncensorSelector、BetterPenetration、KKS_Fixes、ME shader 等 134 個模型，多數授權不允許再散布 | 全部排除，P2 自製取代 |
| 5. 程式碼 | `dbone/`（DynamicBone_Ver02 移植）、`finalik.rs`（RootMotion FinalIK 移植）、多處依 `ChaControl` 行為對照實作；`src/` 有 49 個檔案、263 處提到這些來源 | 三、P7 |

另外兩個非素材問題：

- **git 歷史**：`origin` 從 2026-10-20 起的 commit 與 LFS 已含原作資料；OK Studio 用新倉庫。
- **名稱**：產品、執行檔、`.uproject`、UI 文字改為 OK Studio；「Koikatsu」只出現在陳述相容性的句子（例如「可讀取 Koikatsu Sunshine 人物卡，需自備原作」）。目前 F 組的場景編輯器也叫 OK Studio（[OK_STUDIO_PLAN](OK_STUDIO_PLAN.md)），之後文件裡改稱「場景編輯器」，OK Studio 指整個產品。

截圖裡的 OpenTTD 比喻要修正：OpenTTD 能上 Steam，除了換成 OpenGFX／OpenSFX／OpenMSX 素材，還取得了原作者 Chris Sawyer 的同意。本專案沒有權利人同意，只能靠「完全不散布原作內容」。

## 二、總體架構：以 VRM 為素體規格，原作相容做成可選外掛

**素體採用 VRM 1.0 的 humanoid 規格**（開放規格，參考實作 UniVRM、three-vrm 為 MIT）：

- 骨架：VRM humanoid 骨（hips、spine、chest、upperChest、neck、head、四肢、手指）是必要骨，OK 另加自己的形變骨（相當於原作的 `cf_s_*`）。
- 表情：VRM 的標準表情（`aa`／`ih`／`ou`／`ee`／`oh`、`blink`、`happy`、`angry`、`sad`、`relaxed`、`surprised`、`lookUp/Down/Left/Right`）作為最低集合，OK 自己的眼型／口型／眉型編號再往上加。
- 物理：VRM SpringBone 規格（`VRMC_springBone`）作為動態骨的資料格式。
- Shader：MToon 規格（`VRMC_materials_mtoon`）作為卡通材質的參數集合。

好處：規格與參考實作都是開源；使用者可以把 VRoid Studio 或其他 VRM 工具做的角色、衣服、頭髮帶進 OK Studio，素材缺口可以由社群補。

**原作相容拆成 `OKCompat` 外掛，不在 OK Studio 公開倉庫：**

| 放在 OK Studio（公開） | 放在 OKCompat（私有，或只在本機產生） |
|---|---|
| OK 卡格式、VRM 匯入、自製素體與資料、MToon 系材質、自寫物理與 IK | 原作卡與 zipmod 讀取後的資源轉換、146 個 `.inl`、`dbone` 的 DynamicBone 移植、`finalik.rs`、`ChaControl` 對照實作、原作動畫與 paired 動作 |
| 舊卡參數 → OK 參數的語意對照表（自己寫的） | `restore_original_data.lua` 產生的全部資料 |

讀取原作卡的程式（`card.rs`、PNG／MessagePack 解析）是格式相容用途，留在 OK Studio；讀出來的參數一律經語意對照表轉成 OK 自己的參數再使用。

## 三、程式碼：可用的開源實作（P7）

### 動態骨（取代 DynamicBone_Ver02）

| 候選 | 授權 | 用法 |
|---|---|---|
| VRM SpringBone（規格＋UniVRM／three-vrm 實作） | 規格開放、實作 MIT | **首選**。演算法簡單（Verlet＋長度約束＋球／膠囊碰撞），依規格在 Rust 重寫；MIT 實作可參考，保留著作權聲明即可 |
| NVIDIA PhysX 5 | BSD-3 | 已在引擎裡（`UE5.8-physX-5.11-ok`）；裙子、胸部這類需要穩定碰撞的部位可用 PhysX 的 articulation／rigid body |
| Rapier（Rust） | Apache-2.0 | Rust 端若需要通用剛體／關節求解可用；`okphysics.rs` 已有自有基礎，可評估是否直接併入 |
| UE Chaos Cloth、AnimDynamics、RigidBody AnimNode | UE EULA（UE 專案內可用） | 衣物布料、尾巴、飾品；只能在 UE 端用，不能進 Rust 庫 |
| XPBD 論文（Müller 等，2016） | 論文演算法 | 自寫布料／軟體時的依據 |

建議：**動態骨用 VRM SpringBone 規格在 Rust 重寫**（現有 `dbone` 的碰撞與縮放處理語意可以寫成規格書交給重寫者，但不看舊程式碼），衣物裙擺評估 PhysX／Chaos。

### IK（取代 FinalIK）

| 候選 | 授權 | 用法 |
|---|---|---|
| 解析式 Two-bone IK | 公開演算法 | 手腳四肢，最常用，自己寫半天可完成 |
| FABRIK（Aristidou & Lasenby, 2011）、CCD | 公開演算法 | 脊椎、尾巴、多節鏈 |
| ozz-animation（C++） | MIT | 有 two-bone IK、aim/look-at IK 的成熟實作可參考或直接連結 |
| UE IK Rig／Full Body IK（PBIK） | UE EULA | 全身 IK（相當於 FinalIK 的 FBBIK／VRIK）；在 UE 端求解，Rust 端只給目標點 |
| Godot 的 SkeletonModifier／FABRIK | MIT | 可參考 |
| Blender IK | GPL | **不要**引入程式碼（會讓整個專案受 GPL 約束） |

建議：**Rust 端寫 two-bone＋FABRIK＋look-at 三種**，涵蓋手腳、視線、脊椎；需要全身平衡的配對互動在 UE 端用 PBIK。

### 依 `ChaControl` 對照的身形／姿態求解

這部分沒有開源替代品可以直接換，因為它就是「原作怎麼把參數變成骨架」。做法是**先寫行為規格，再由沒看過舊程式的人重寫**：OK 自己定義參數怎麼影響骨（見 P3），舊卡經語意對照表轉入，不追求和原作數值一致。

### clean-room 流程

1. 熟悉舊實作的人寫「行為規格書」：輸入、輸出、邊界情況、數值測試案例（測試的期望值用 OK 自己的素體產生，不用原作輸出）。
2. 另一個沒讀過舊程式碼的人（或沒載入舊程式碼的 AI session）依規格書實作。
3. 程式碼審查確認沒有複製舊實作的結構與常數。

## 四、素體、身形資料與其他素材的實作方式

### P2 素體網格與貼圖

**建議做法：Blender 自己雕一套動漫比例素體，拓撲可以從 CC0 素材起步。**

1. **拓撲來源**（二選一，都要記錄在 `PROVENANCE.md`）：
   - MakeHuman 的 base mesh 與 targets（資產為 CC0，程式碼是 AGPL，只拿資產不拿程式）：拓撲乾淨、關節環線合理，但比例寫實，要大幅改成動漫比例。
   - 從零 box modeling：最乾淨，工時多 2～3 週。
   - VRoid Studio 匯出的素體：工時最少，但 OK Studio 會變成散布 VRoid 產物，要先確認 VRoid Studio 的使用條款允許在開源專案中再散布並允許修改；確認前不要用。
2. **分件**：身體、頭、手分開；頭部的臉、眼白、虹膜、睫毛、眉毛、口腔、牙齒、舌頭各自一個材質槽，方便表情與換色。
3. **貼圖改用參數驅動**：膚色、腮紅、唇色、眼影、曬痕用 UE 材質參數＋少量灰階遮罩（自己繪製）合成，而不是像原作那樣每種顏色一張貼圖。這樣需要自製的貼圖從幾百張降到幾十張，也直接對應卡片裡的顏色參數。
4. **眼睛**：虹膜、瞳孔、高光分層，各自用參數控制大小、顏色、位置（對應原作卡的眼睛參數語意）。
5. **成人部件**（若 OK Studio 包含）：自製，取代整個第 4 層。
6. **面數**：女約 2～3 萬三角，LOD 用 `Tools/vendor/instant-meshes` 產生。

### P3 身形資料（滑桿、表情、手型、rest pose）

**建議做法：在 Blender 裡把每個滑桿做成「骨變形＋修正 shape key」，匯出 glTF，由 Rust 工具轉成 OK 自己的格式。**

1. **定義滑桿規格**（`Content/IndependentResources/okstudio/shape_spec.json`）：
   - 保留舊卡的參數 ID 與意義（例如「胸部大小」「腿長」「眼睛大小」），每個參數寫明「0、0.5、1 時要長成什麼樣子」，用可量測的目標描述（身高 cm、胸圍比例、眼寬占臉寬比例），這些目標由我們自己決定。
   - 不從原作的 `cf_anmShape*` 取樣任何數值，也不拿原作截圖當比對目標。
2. **在 Blender 製作**：
   - 骨變形：每個滑桿在 0／1 兩端設定形變骨的位移、旋轉、縮放（相當於原作的 AnimationCurve，但用三點或少量關鍵點，自己的數值）。
   - 修正 shape key：骨縮放做不好的部位（胸型、臀型、臉頰輪廓）加 shape key。
   - 臉部 52 項與表情：以 shape key 為主（臉型是 morph 比骨縮放好控制），眼／口／眉表情也是 shape key。
   - 手型：在 Blender 擺好每個手勢的姿勢，存成姿勢庫。
3. **匯出與轉換**：Blender 匯出 glTF（含 shape key 與骨架、自訂屬性），新增 Rust 工具 `ok-shape-pack` 讀 glTF＋`shape_spec.json`，產生 OK 執行期用的滑桿資料。全程不需要寫 Blender Python 腳本，符合專案的「不新增 .py」規則。
4. **rest pose**：用 VRM 規格的 T-pose 作為綁定姿勢，A-pose 作為預設顯示；Compat 端在本機產生「原作 rest → OK rest」的 retarget 表，讓原作動畫在 Compat 模式能套上 OK 素體。
5. **臉型預設**：自己做 6～10 組臉型預設（就是一組滑桿數值），存在 `okstudio/face_presets.json`。
6. **舊卡相容**：舊卡數值（0～1）直接當 OK 滑桿數值使用；因為語意相同，外觀方向會一致，細節比例不同是預期結果。驗收時用人物編輯 MCP 的三視圖，比較 Compat 與 OK Studio 的方向是否一致。

### P4 Shader 與 ramp（優先度最高：決定能不能編譯）

**建議做法：以 MToon 規格寫一套 UE 材質，把依賴 `.inl` 的程式碼移到 OKCompat。**

1. 先做程式拆分：所有 `#include` 那 146 個 `.inl` 的程式碼（`KKRuntimePose`、`KKUnityBundle`、`OKStudio`）移到 `OKCompat` 外掛，OK Studio 的模組用介面呼叫，外掛不存在時改用新材質。這一步做完，**沒有原作也能編譯**，可以先於其他素材完成。
2. 新材質家族：身體／臉、頭髮（含天使環高光）、衣服、配件、透明、外框，共 5～6 種，參數以 MToon 為底（shade color、shade shift、toony、rim、matcap、outline width/color），加上 OK 需要的遮罩通道。
3. ramp：自己畫 4～6 張（柔和、硬邊、雙色階等），現有 `render_style` 的 `ramp:<key>` 機制可以直接沿用。
4. 驗收：OK 素體＋新材質在街區光照下，和現狀並排截圖，由使用者目視確認風格可接受。

### P5 衣服、頭髮、配件

1. **入門集**：衣服 8 類、頭髮前／後／側、常用配件各 3～5 件，用 `ok-chara`（自繪或自生成的人設圖 → Tripo → 擬合到 OK 素體）。人設圖不能以原作截圖或原作角色為輸入；Tripo 生成物的商用與再散布條款要先確認。
2. **VRM 匯入**：實作 VRM 衣服／頭髮匯入，讓使用者用 VRoid 或其他工具自己補素材（OK Studio 只散布匯入功能，不散布別人的 VRM）。
3. **舊卡替代對照表**：原作部件 ID → OK Studio 同類部件（`okstudio/compat_parts.json`）；找不到就用該類別預設件，舊卡不會光頭或裸身。

### P6 動畫、語音、台詞

| 項目 | 建議來源 | 授權注意 |
|---|---|---|
| 走、跑、站、坐、待機 | CMU Graphics Lab Motion Capture Database；100STYLE 資料集 | CMU 允許用在產品中但不可單獨轉售原始資料；100STYLE 為 CC BY 4.0，要標示出處 |
| 對話手勢、互動動作 | 自己動捕（手機／影片動捕，現有 `VideoMotionDemos` 流程）＋手 K | 自製最乾淨 |
| Mixamo | 可以用在遊戲中，但不能把原始動畫檔放進公開倉庫再散布 | 只適合烘焙進打包後的遊戲，不適合開源倉庫 |
| Bandai Namco Research 動作資料集、AMASS | 非商業授權 | 若 OK Studio 有任何商業用途就不要用 |
| Studio 原作動畫 5,806 個、paired 動作 | 只在 OKCompat 提供 | — |
| 語音 | ok-tts | TTS 模型權重與訓練用的聲優資料各自有授權，要逐一確認；最好用明確允許商用的聲音或自錄 |
| 台詞 | 重寫（人工＋AI），不從原作台詞或其翻譯改寫 | 原作台詞與 `dialogue.json` 等翻譯只在 OKCompat |
| BGM、音效 | 自製或 CC0 | — |

街區 demo 需要的動作量不大（數十個），先用自製＋CMU／100STYLE 補齊街區，Studio 的大型動作庫後面再擴充。

## 五、驗收

1. 在沒有 KKS、沒有任何 zipmod 的乾淨機器上，OK Studio 從 clone 到建置、啟動街區與人物編輯器全部成功。
2. manifest 掃描：OK Studio 倉庫零個 `original`／`third_party_mod`／`commercial_port` 檔案。
3. 隨機 20 張網路舊卡在 OK Studio 開啟：全部有身體、頭髮、衣服（替代件），身形與表情方向正確；缺件清單輸出到 log。
4. 同 20 張卡在 Compat（本機還原原作＋OKCompat）與現狀一致（沿用 `okcard-check ... live`）。
5. 一個 VRoid Studio 匯出的 VRM 角色能在 OK Studio 載入、套用 OK 表情與物理。
6. `PROVENANCE.md` 涵蓋每個素材；`THIRD_PARTY_NOTICES.md` 列出所有 MIT／Apache／CC BY 來源與聲明。

## 六、工作順序與規模

| 順序 | 階段 | 內容 | 主要人力 | 估計 |
|---:|---|---|---|---|
| 1 | P0 | 來源標籤：擴充 `original_data_manifest.json` 類別（`original`、`third_party_mod`、`commercial_port`、`own`、`licensed:<授權>`），新增 `PROVENANCE.md`，commit hook 擋未標記檔案 | 程式 | 1 週 |
| 2 | P4-1 | `.inl` 相依程式碼移到 OKCompat，讓沒有原作也能編譯 | 程式 | 2～3 週 |
| 3 | P7 | 動態骨（VRM SpringBone）、IK（two-bone／FABRIK／look-at）clean-room 重寫；身形求解改讀 OK 格式 | 程式（與舊實作隔離） | 1～2 個月 |
| 4 | P1＋P2 | VRM humanoid＋OK 形變骨規格、素體網格與貼圖 | 3D 美術 | 2～3 個月（最大風險） |
| 5 | P3 | 滑桿規格、Blender 製作、`ok-shape-pack` | 美術＋程式 | 1～2 個月，可與 P2 後半重疊 |
| 6 | P4-2 | MToon 系材質與 ramp | 技術美術 | 1～2 個月 |
| 7 | P5、P6 | 入門部件、VRM 匯入、街區動作、語音、台詞 | 美術、動畫、企劃 | 起步 1～2 個月，之後持續 |
| 8 | P8 | 新倉庫、改名 OK Studio、舊倉庫轉私有 | 程式 | 1 週 |

P4-1 排在前面，是因為它不需要美術，而且做完就能在乾淨機器上驗證「沒有原作能不能建置」，後面每一步都能持續驗收。

## 七、待使用者決定

1. OK Studio 是否包含成人內容；影響 P2 部件、P6 動作範圍與散布平台。
2. 骨名：保留 `cf_*` 當內部名稱，還是全面改用 VRM 骨名＋OK 形變骨名、`cf_*` 只出現在 Compat 對照表（建議後者）。
3. P7 重寫範圍：只換 DynamicBone／FinalIK，還是連 `ChaControl` 對照的身形／姿態求解也重寫（採用 P3 的新身形格式後，後者自然會被取代）。
4. 素體拓撲來源：MakeHuman CC0、從零製作，或確認條款後用 VRoid。
