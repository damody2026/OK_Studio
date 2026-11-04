# 取得共用資源

OK Studio 的倉庫不含任何版權物。程式需要的原作資料（以下叫「共用資源」）要在你自己的電腦上產生，或從 QQ 群 **1127259437** 下載開發資源。這份說明寫給人看，也可以整份交給 AI（Claude Code、Codex 等）照著執行。

## 給 AI 的執行步驟

> 你在 OK Studio 的 checkout（`OpenKoikatsu.uproject` 所在的資料夾）裡工作，系統是 Windows。請照下面的步驟產生共用資源，每一步確認成功再做下一步。不要把產生的檔案提交到 git（`.gitignore` 與 pre-commit hook 已經擋住）。

1. **問使用者 Koikatsu Sunshine 的安裝位置**：資料夾裡要有 `abdata/`（例如 `D:/KoikatuSunshine`，注意拼字是 Koikatu）。沒有遊戲、改用 QQ 群的開發資源 zip 時，跳到步驟 5。
2. **確認工具**：
   - `cargo --version` 能執行（Rust stable、MSVC 工具鏈；沒有就到 <https://rustup.rs> 安裝）。
   - Lua 已附在倉庫：`Tools\lua\lua.exe`，不必另外安裝。
   - 磁碟空間：至少 20 GB。
3. **執行轉換**（在專案根目錄的 PowerShell）：

   ```powershell
   .\Tools\lua\lua.exe Tools\original_data.lua restore --game D:/KoikatuSunshine
   ```

   腳本會先建置 `ok-extract` 與 `ok-paired-library`（`cargo build --release -j 8`，第一次約 10～20 分鐘），再依序轉換：

   | 步驟 | 產生 | 來源 |
   |---|---|---|
   | `models` | `Content/IndependentResources/base_v1/models/`、`sources.okidx` 等索引 | 遊戲 `abdata/chara`，以及遊戲 `mods/` 裡 [`Tools/base_library_shared_mods.txt`](../Tools/base_library_shared_mods.txt) 列的共用 mod |
   | `studio` | Studio 目錄、道具名稱、圖片、天空、反射、shader 狀態 | `abdata/studio` |
   | `sounds` | Studio 語音與 BGM、H 音效 | `abdata/studio/sound`、`abdata/sound` |
   | `anims` | Studio 動畫與 H 動作 | `abdata/studio/anime`、`abdata/h` |
   | `paired` | 雙人配對動作、姿勢與 IK | `abdata/h` |
   | `runtime-clips` | 街區用的動作片段 `Content/IndependentResources/RuntimeAnimations/` | `abdata` |

   轉換時 CPU 最多用 8 個執行緒，整個過程視電腦約 1～3 小時。過程記錄在 `Saved/OriginalData/restore.log`。

4. **看結果**：最後一段會印出 `verify ...: N same, N differ, N missing`。
   - `differ`（內容和開發者那份不完全相同）是正常的：轉換時的時間戳、你的 `mods/` 清單、音訊重新編碼都會讓 bytes 不同，功能一樣。
   - 某一步印出 `FAILED` 時，把 `restore.log` 最後幾十行貼給使用者，再單獨重跑那一步，例如 `restore --game D:/KoikatuSunshine --only studio`。
   - 列在 `missing` 的檔案，見下方「目前還不能從遊戲轉換的部分」。
5. **用 QQ 群的開發資源 zip**（沒有遊戲，或要補齊 `missing`）：

   ```powershell
   .\Tools\lua\lua.exe Tools\original_data.lua restore --archive D:/Downloads/OKOriginalData.zip
   # 有遊戲也有 zip：能轉換的從遊戲轉，其餘從 zip 解
   .\Tools\lua\lua.exe Tools\original_data.lua restore --game D:/KoikatuSunshine --archive D:/Downloads/OKOriginalData.zip
   ```

   zip 內每個檔案都有 sha256，解出後會逐一核對。
6. **之後隨時檢查**：`.\Tools\lua\lua.exe Tools\original_data.lua verify`。

## 不需要的東西

- **街區 demo 的原作台詞、語音與翻譯**：女角的對話由 AI 產生，語音由 TTS 產生，不用原作台詞與語音。
- **Studio 樣本場景與截圖**（`UserData/Studio/scene/` 等）：只是開發時的測試資料。
- **角色卡**：倉庫沒有任何卡片，請用你自己的卡（原作卡、OK 卡）。

## 目前還不能從遊戲轉換的部分

以下幾項還沒有轉換工具（正在補），目前要從開發資源 zip 取得：

| 檔案 | 用途 |
|---|---|
| `Content/KKPreview/`（陰影 ramp、色彩 LUT） | 角色上色風格 |
| `Content/Koikatsu/Data/*.uasset` | 讀卡器的動畫目錄 |
| `Content/IndependentResources/BodyInteractions/`、`MotionCatalogue/` | 觸碰反應、雙人互動的動作名稱 |
| `Content/Scenes/CrowdRoom/*/Shared_*.uasset` | 百人房間的共用走路曲線 |

## 給維護者

- 哪些檔案算共用資源：[`Tools/original_data_manifest.json`](../Tools/original_data_manifest.json)（路徑、大小、sha256、類別）。
- 打包開發資源 zip：`Tools\lua\lua.exe Tools\original_data.lua pack --out <zip>`；測試：`test-archive <zip> <空資料夾>`。
- 設計與驗證紀錄：[原作資料移出版控](ORIGINAL_DATA_OUT_OF_GIT_PLAN_20261104.md)。
