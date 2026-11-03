# 新版 OK 卡：從一張人設圖做出 OK 卡（okCh）

2026-10-24。參考 [Charakuru](https://github.com/nanocle/Charakuru)（一張立繪 → 部位圖 → Tripo 3D → 綁骨／權重／彈簧 → VRM，單一專案檔、每一步停在檢查點）的流程，終點換成 OK 卡。Charakuru 的公開倉庫只有文件，這裡的程式全部是自己寫的。

## 卡片格式

新版 OK 卡 = 一張一般的 OK 卡（底卡：`okLb`／`okLc` 與原作卡資料）＋ `okCh` 區塊。

- **臉與身體是 KK 原生的**：底卡的卡片參數（臉型 52 項、頭部尺寸、瞳孔／眉毛種類與顏色、膚色）改成接近人設，所以眨眼、表情、嘴型、手指、身體物理都照常運作。
- **衣服與頭髮來自人設的 3D 模型**：`okCh` 存放衣服、頭髮部件與一張身體遮罩：
  - 部件已經擬合到底卡骨架，權重綁 KK 骨名；
  - 衣服分上衣（slot 0）、長襪（slot 6）、室外鞋（slot 8），隨換裝狀態顯示或隱藏；
  - 身體遮罩的 R 通道是被上衣蓋住的皮膚，上衣穿著時取代底卡衣服的遮罩，脫掉時取消。
- 開卡時 `session::open` 呼叫 `okchara::apply`：隱藏底卡的頭髮、配件、衣服，加入 `okCh` 的部件。遊戲、街區、Studio、讀卡器走同一條路，不需要 UE 端改動。
- 重做 OK 卡（`strip_ok_chunks`／`remake_ok_card`）只換 `okLb`／`okLc`，`okCh` 跟著保留。

`okCh` 內容：`OKCH` + 版本（u32，目前 2）+ zstd(bincode(`CharaCard`))。部件位置存在「製作時的骨架空間」，同時記下每根用到的骨在製作時的世界矩陣，執行時 palette = 現在的世界矩陣 × 製作時的反矩陣。版本不符時拒絕載入，要重新產卡。

## 流程與工具

專案資料夾（例：`ref/charakuru/nun_angel/`，本機、不進版控）裡的 `project.okchara` 記錄每一步的輸入、選擇與產出。

| 步驟 | 誰做 | 做法 |
|---|---|---|
| 1. 人設 | 使用者 | 立繪、三視圖放 `source/` |
| 2. 部位圖 8 張 | AI（Grok image_edit）→ 使用者檢查 | 頭（含頭髮）四視角、身體 T-pose 四視角；側面先翻轉姿勢正確的一張再修不對稱處 |
| 3. Tripo 候選 | AI 操作 Tripo（瀏覽器）→ 使用者挑 | Smart Mesh 多視角，一次 4 個候選；`candidates/` |
| 4. 貼圖 | Tripo Texture | 選中的頭、身體各上 4K 貼圖 |
| 5. 頭身接合 | `Tools/make_ok_chara_card.lua assemble` | 依脖子位置與粗細縮放頭部；檢查 `review/assembled.jpg` |
| 6. 綁骨 | Tripo Rig（Humanoid／Mixamo）→ **匯出 FBX** | Tripo 的 GLB 匯出沒有權重；`make_ok_chara_card.lua fbx2glb` 轉成 GLB |
| 7. 貼圖修補 | `ok-chara project` | 把參考圖投影回貼圖（例：頭巾背面花紋） |
| 8. 產卡 | `make_ok_chara_card.lua build` | `ok-chara build`、轉骨測試、檢查圖 `review/fit.jpg`、`review/posed.jpg` |
| 9. 遊戲內檢查 | 使用者 | 街區沙盒（`-Sandbox`）拍正／側／背、走路、換裝 |

```powershell
.\Tools\lua\lua.exe Tools\make_ok_chara_card.lua build ref\charakuru\nun_angel
```

`ok-chara`（`Tools/ok-extract/src/bin/ok-chara.rs`，邏輯在 `src/okchara.rs`）子命令：`skeleton`（底卡骨架與網格）、`fields`（底卡可改的欄位）、`build`、`project`、`pose-test`。

## `ok-chara build` 做的事

1. **底卡參數**：`card_edits`（`[路徑, 值]`，路徑見 `ok-chara fields`）寫進底卡，再用 `remake_ok_card` 重做 OK 卡，讓模型清單跟著新的部件 ID。
2. **擬合**：讀 Mixamo 骨架的 GLB（關節座標系與頂點不一致時，以各骨權重頂點的重心做 2D Procrustes 轉正）。每段骨把網格沿骨軸依長度比伸縮，垂直骨軸用整體比例（軀幹長比），四肢粗細不變；頭部等比、直立。腳踝以下壓到地面（靴底比赤腳高）。
3. **權重**：
   - 靠近皮膚的衣服用底卡身體的權重（含扭轉骨、胸部骨）；
   - 腰部以下離皮膚的裙擺與披風綁 KK 原生裙骨 `cf_j_sk_*`，依角度與高度內插，交界平滑；
   - 其他部分用 Tripo 權重換成 KK 骨名；頭髮只能綁頭、頸、上脊椎（`allowed_joints`）。
4. **分件**：依貼圖顏色去掉畫出來的皮膚；身體網格依位置與顏色拆成上衣、長襪、長靴。頭部網格去掉臉後，移除眼睛、嘴巴等小島，再以「畫出來的雙眼」對齊 KK 的雙眼（縮放以眼距計），頭髮與頭巾就框住 KK 的臉。
5. **身體遮罩**：每個身體頂點沿法線往外 25 cm、往內 2.5 cm 射線，碰到上衣就算被蓋住，畫進 UV 遮罩（1024²，往外擴 2 texel）。
6. 寫卡後立刻用一般開卡流程重開檢查。

## nun_angel 的結果（2026-10-24）

- 底卡 `Content/CharacterCards/StreetHeroines/megumin.png`；改了瞳孔 69（藍）、眉毛 1（金）、頭部尺寸 1.0、眼睛水平位置 0.55、眼睛寬 0.85、長 0.75。
- 卡片 24.8 MB（兩張 4K 貼圖、身體遮罩、底卡）。身體 9,801 → 去皮膚 975 三角形；頭部 9,667 → 留頭髮頭巾；頭髮對齊縮放 0.70。
- 街區（`OKChara2.stage`，沙盒）：原生臉有表情、手指動作；衣服、長襪、長靴、頭巾頭髮跟著待機與走路動作；腳踩在地上；裙骨物理有作用。換裝狀態（`OK_CLOTHES_STATES`）脫上衣／長襪／靴子時對應部件隱藏。

## 限制與後續

- 頭髮是剛性跟頭（沒有髮束動態骨）；長髮只跟到上脊椎。
- 臉型參數是手調的近似，沒有自動比對人設。
- 翅膀、劍、燈籠、緞帶等配件尚未製作。
- 卡片的人物名稱仍是底卡的名字。
- 胸部大小可用 `bust_scale` 調整，方向待使用者決定。
