# OK Mod 第三波追加項：post_texture／mod 材質覆蓋與各個快取（F 組，2026-11-23）

協調者在第三波追加：查清開卡結果受 mod 影響時，GPU 磁碟快取、KKRuntimePose 的街區／人群角色快取、Studio 角色快取、okBk 烘焙會不會出錯。原則（計畫 §7.6）：
- 開卡結果受 mod 影響的地方，快取鍵要含「訂閱 `extract.*`／`material.*` 的 mod 與版本」；
- 裝了 mod 不能拿到沒套 mod 的舊快取；
- 沒裝 mod 時快取不能失效。

## mod 怎麼影響開卡結果

- **Rust（開卡裡）**：`material.post_texture` 在貼圖放進 session 前的最後一步呼叫，共三處：
  - `extract.rs`，身體；
  - `extract.rs`，頭；
  - `push.rs` 的 `emit`，其他部件。

  mod 畫在網格自己的那份貼圖上。程式裡的 `extract.*` 只有 `extract.kkex`／`extract.kkex_keys`，只在轉卡時用。
- **Unreal（開卡之後）**：讀卡器的逐部件材質覆蓋（`ok.materials`），以及 shader 家族換材質。兩者都在每次建部件時重新決定，沒有以部件為鍵的材質快取。

## 盤點結果

| 快取 | 鍵 | 內容 | 結論 |
|---|---|---|---|
| 開卡快取 `<key>.okpreview`（`oklib.rs` `session_cache_key`；要 `OK_LIBRARY_CACHE`） | 整張卡（只去掉 `okBk`／`okMm`／`okLt`，**含 `okMx`／`okMr`**）、服裝、模型、版本、`okmods::cache_key_bytes()` | 掛點之後的整個開卡結果 | 規則正確，但**遊戲端給的 mod 清單漏了 `material.post_texture`**（見下方修正 1） |
| okBk 烘焙（`cardbake.rs`） | 同一把開卡鍵，完全相符才用 | 整個開卡結果 | 一致。`ok-card-bake` 沒有 mod 宿主，存的是無 mod 鍵＋無 mod 結果；開著改開卡結果的 mod 時鍵不同，不會被拿到 |
| okMm 記錄（`memosnap.rs`） | 同一把開卡鍵 | 掛點之前的解碼與查詢 | 和 mod 無關 |
| ok-extract 程序內快取（`png_transform_cache`、`unity/textures.rs`、`MASK_BAKES`、身體合成的 `view_memo`、entries 的 memo、`sqlcache`、動畫磁碟快取） | 依內容或來源 | 都是掛點之前的資料；掛點每次開卡都會再跑 | 一致 |
| KKRuntimePose GPU 姿勢磁碟快取（`KKRuntimeGpuDiskCache.cpp`） | 整個卡檔的 SHA-1＋服裝、曲線、第一幀、共用資源 | 只有骨骼軌道，沒有貼圖與材質 | 一致（不受貼圖 mod 影響；卡檔一改鍵就變） |
| 人群的角色快照（`KKRuntimePoseModule.cpp`） | 沒有自己的快取，走開卡快取 | — | 一致。說明見下方「不修的部分」 |
| KKRuntimePose／`KKTextureRuntime` 的貼圖快取 | 像素或 PNG 內容雜湊，命中時再逐位元組比對 | 貼圖 | 一致 |
| OK Studio（縮圖、圖樣、Material Editor 貼圖、LUT、天空、FBX） | 路徑＋大小，或內容雜湊 | 沒有開卡後的資料 | 無關 |
| 街區診所改造卡 `Saved/StreetSocial/Appearance/<id>-<key>.png`（`OKStreetSocialClinic.inl`） | 原卡與換臉來源卡的**路徑**、髮色、服裝、穿著 | 改造後的卡檔 | **卡在原地改過（例如加了貼紙，okMx／okMr 變了）仍沿用舊的改造卡**（見修正 2） |

## 修正

1. **`Source/OpenKoikatsu/OKModModes.cpp` `SyncExtract`**：
   - **問題**：遊戲在每次進模式時，把「會改開卡結果的 mod」清單推給兩份 ok-extract（`ok_set_enabled_mods`）。C++ 的篩選只認 `extract.*`，漏了 `material.post_texture`；Rust 的 `okmods::changes_opens` 有算。
   - **後果**：skin-decal、glass-shader（以及測試用 material-hooks）的掛點照樣在開卡裡跑，快取鍵卻不含它們。帶貼紙的結果存在無 mod 的鍵下，關掉 mod 後還拿得到；也可能先存了無 mod 的結果，裝上 mod 後拿到沒貼紙的舊結果。
   - **修正**：篩選條件改成和 `changes_opens` 相同。沒裝這類 mod 時清單照舊是空的，鍵不變。
   - 實機：讀卡器（`-ModDev`，沒有 `OK_NOCACHE`）開 `F:\OpenKoikatsu\Saved\CharacterMCP\cards\貼紙臉2_69AA64BC45CA1F024B68BD9E7C7300BD.png`，換卡再換回來，貼紙都在：`F:\OpenKoikatsu\Saved\OKControl\shots\80204-0001.png`。log 每次開卡都有 `decal drawn on head`。
2. **`Source/OpenKoikatsu/OKStreetSocialClinic.inl` `RestyledCard`**：
   - **修正**：改造卡的鍵多加原卡與換臉來源卡的大小與修改時間。卡在原地改過（mod 區段、貼紙）就是另一個樣子，不再沿用舊檔。
   - **代價**：這次改動後，既有的改造卡會各重做一次（之後照常命中）。這和 mod 裝不裝無關，沒裝 mod 時鍵也穩定。

建置：F 引擎 `OpenKoikatsu` Development 與編輯器（見提交）。

## 不修的部分（記下來）

- **mod 的設定不在鍵裡**：鍵只有 `id@version`。若某個 mod 的開卡結果取決於它的全域設定，改設定而不升版本會拿到舊結果。目前的範例沒有這種情況（skin-decal 的設定在卡裡，已在鍵中；glass-shader 不畫貼圖）。之後有這種 mod 時，要嘛把設定放進卡、要嘛改設定時升版本，或者再把設定雜湊放進 `cache_key_bytes`。
- **人群（KKRuntimePose）那份 ok-extract 不跑 mod**：KKRuntimePose 自己靜態連結一份 `ok_extract.lib`，沒有設定 mod 轉送與清單。結果是一致的（無 mod 鍵＋無 mod 結果）。人群房間本來就不進任何 mod 模式（`OKModModes.cpp`：「The crowd room has none and runs no mode」），所以沒有錯配；若之後人群也要套 mod，要像 KKUnityBundle 一樣從 `SyncExtract` 設定它那份。
- **okBk 的 `load_kind` 沒檢查 `open_config_identity`**（磁碟快取有檢查）：和 mod 無關，留給開卡快取的負責人。
- **開卡快取預設沒開**（`OK_LIBRARY_CACHE` 沒設時不存不讀），所以修正 1 實際影響的是有開這個快取的環境。暖機程式 `ok-card-warm` 沒有 mod 宿主，存的是無 mod 鍵，一致。
