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
- 其他卡（千佳、惠惠、刻晴）還沒在修好的主機上重看。

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
