# PhysX 布料（裙子／袖子）交接 2026-11-21

讀卡器裡用 PhysX 5.11 GPU 布料（`PxDeformableSurface`）做裙子與袖子，和原作物理（DynamicBone，下稱 DB）對照。設計與歷次排查見 [CLOTH_PHYSX_SKIRT_SLEEVE.md](CLOTH_PHYSX_SKIRT_SLEEVE.md)，錯誤紀錄在 [ERROR_LOG.md](ERROR_LOG.md) 2026-11-21 各條。

## 目前狀態

- 工作樹乾淨：全部改動都已提交到 `master`，最新是 `23300e60d`，沒有推送。`OKExtractBuildStamp.h` 和 `grok-media/` 不屬於這項工作，不要提交。
- 遊戲沒在跑，Unreal slot 已釋放（slot1、slot2 都空）。
- 主要程式碼：
  - Rust 端：`Tools/ok-extract/src/cloth_px.rs`。
  - Unreal 端：`Plugins/OKPhysXSecondary/.../OKPhysXCloth.cpp`（CVar `ok.PhysXCloth.*`，這輪沒改）。
  - 另有小改動：`dbone.rs` 的 `DBoneSet::root_names`，`session.rs` 的 `AccessoryRuntime::implanted_bones`。

### 已修好且錄影確認

| 問題 | 做法（commit） |
|---|---|
| 雷電將軍紫色和服破面 | 骨頭移植到身體骨架的衣服（`implanted_bones` 非空）不做布料（`72dd437b9`） |
| 自帶手臂 DB 鏈的衣服 | 留給 DB；鏈布料只在 `OK_CLOTH_PX_CHAINS=1` 時實驗 |
| 襯衫袖與外套袖互穿 | `LAYERS` 分層：同一區只讓外層當布料，裡層照骨架走（`5f50686a4`） |
| 千佳褶裙上浮、前擺翻起 | 裙子不放 GPU 身體膠囊（`ae19a7ad6`）；所有裙子改成跟著 DB 擺：布料最多離 DB 5 cm（`OK_CLOTH_PX_LONG_MAX`），不能高於姿勢 5 mm（`OK_CLOTH_PX_UP`）（`99eeab16d`） |
| 女僕長裙變短、被腿刺穿；惠惠裙擺露出內褲 | 同上 DB 跟隨 |

**上浮的真正原因**：`PxDeformableSurface` 的靜止形狀在建立那一刻就定死了，走路中途建的布料會一直保留那一刻的外擴。為此調過彎曲、摩擦、楊氏模數、厚度、迭代次數、PULL、CPU 膠囊，全都沒用，不要再走一遍。

## 使用者最新回報（未處理）

使用者說的原話：

> 服裝 2，手上的袖子沒有物理要修正
> 服裝 3，女僕長裙的面數不夠，需要自己加面
> 服裝 5，面數不夠且小腿穿模和服長裙
> 我看起來有兩個問題：1. 衣服面數不夠時需要自己加面 2. 物理碰撞參數沒有調到位

修完後要**把五套服裝全部重錄一遍**（多角度、20 秒、布料和原作物理左右並排）。

### 建議的下一步

1. **服裝 2 手臂上的紗袍沒有物理。**
   - 先查它的 role 與主要權重骨。`cloth_px.rs` 的 `detect()` 只收 `clothes_*` 角色，袖子只認 `clothes_top`；之前服裝 2 的 detect log 只有兩個 `clothes_top`：胸部權重 1868 頂點、腰部權重 719 頂點，沒有裙子或袖子區。
   - 很可能紗袍是配件（`acc`，在 `push.rs:212` 走 `from_assigned_accessory`），或手臂權重太低沒被判成袖子。
   - 做法：在 `detect()` 的角色過濾**之前**加 `OK_CLOTH_PX_DEBUG` log，印出每個 part 的 role 和權重最重的骨頭。確認後，把袖子判定擴到配件，或放寬手臂權重門檻。
2. **自動加面（細分）。**
   - 布料區頂點太稀時，要同時細分模擬網格和渲染網格。
   - 要一起細分的逐頂點欄位都在 `unity.rs:1785` 的 `ExtractedMesh`：
     - 位置：`positions`、`rest_positions`；
     - 法線與切線：`normals`、`rest_normals`、`tangents`；
     - UV 與頂點色：`uvs`、`uv2`–`uv4`、`vertex_colors`；
     - 蒙皮：`weights`、`bone_idx`；
     - morph：`blend_shapes`（中點取兩端 delta 的平均）；
     - 索引與子網格：`indices`、`submesh_ranges`、`submesh_index`。
   - 只細分被判成布料的三角形，避免整件衣服頂點數暴增。要等 detect 之後、建立 `AccessoryRuntime` 之前做，或改成在 runtime 的 source mesh 上做。
3. **服裝 5 和服長裙被小腿穿出。**
   - 現在裙子走 DB 跟隨，穿模主要來自 DB 的碰撞體，加上布料層沒有身體膠囊。
   - 檢查小腿的 DB collider 半徑與長度，以及布料端 `cap_fit` 的 CPU 膠囊（`cap_scale` 1.5、`cap_margin`）有沒有涵蓋小腿。必要時只對長裙（`d.long`）加小腿膠囊。
4. 五套服裝重錄（流程見下），更新文件與 ERROR_LOG，分別提交（一種改動一個 commit）。

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
