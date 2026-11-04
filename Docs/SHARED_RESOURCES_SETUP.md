# 取得共用資源

OK Studio 的倉庫不含任何版權物。程式需要的原作資料（以下叫「共用資源」）要用你自己的遊戲在電腦上產生。這份說明寫給人看，也可以整份交給 AI（Claude Code、Codex 等）照著執行。

## 給 AI 的執行步驟

> 你在 OK Studio 的 checkout（`OpenKoikatsu.uproject` 所在的資料夾）裡工作，系統是 Windows。請照下面的步驟產生共用資源，每一步確認成功再做下一步。不要把產生的檔案提交到 git（`.gitignore` 與 pre-commit hook 已經擋住）。

1. **問使用者 Koikatsu Sunshine 的安裝位置**：資料夾裡要有 `abdata/`（例如 `D:/KoikatuSunshine`，注意拼字是 Koikatu）。
2. **確認工具**：
   - `cargo --version` 能執行（Rust stable、MSVC 工具鏈；沒有就到 <https://rustup.rs> 安裝）。
   - Lua 已附在倉庫：`Tools\lua\lua.exe`，不必另外安裝。
   - 磁碟空間：至少 40 GB（產生的資料約 30 GB）。
3. **執行轉換**（在專案根目錄的 PowerShell）：

   ```powershell
   .\Tools\lua\lua.exe Tools\original_data.lua restore --game D:/KoikatuSunshine
   ```

   腳本會先建置 `ok-extract`、`ok-paired-library` 與 `ok-ramps`（`cargo build --release -j 8`，第一次約 10～20 分鐘），再依序轉換：

   | 步驟 | 產生 | 來源 |
   |---|---|---|
   | `models` | `Content/IndependentResources/base_v1/models/`、`sources.okidx` 等索引 | 遊戲 `abdata/chara`，以及遊戲 `mods/` 裡 [`Tools/base_library_shared_mods.txt`](../Tools/base_library_shared_mods.txt) 列的共用 mod |
   | `studio` | Studio 目錄、道具名稱、圖片、天空、反射、shader 狀態 | `abdata/studio` |
   | `sounds` | Studio 語音與 BGM、H 音效 | `abdata/studio/sound`、`abdata/sound` |
   | `h-voices` | **H 語音**（`base_v1/h/voice/`，約 12 萬段、13 GB）；選用，見下方「H 語音」 | `abdata/sound/data/pcm` |
   | `anims` | Studio 動畫與 H 動作 | `abdata/studio/anime`、`abdata/h` |
   | `paired` | 雙人配對動作、姿勢與 IK、H 場景的姿勢清單 `StreetSocialData/h_poses.json` | `abdata/h` |
   | `runtime-clips` | 街區用的動作片段 `Content/IndependentResources/RuntimeAnimations/` | `abdata` |
   | `preview` | 陰影 ramp（`Content/KKPreview/Ramps/`）、色彩 LUT、Minimalist ramp | `abdata/chara`、遊戲 `mods/`、`BepInEx/plugins/KKS_BetterColorPicker.dll` |

   轉換時 CPU 最多用 8 個執行緒，整個過程視電腦約 1～3 小時。過程記錄在 `Saved/OriginalData/restore.log`。沒有 BetterColorPicker 外掛或 Minimalist Shadows mod 時，那一項會略過（畫面改用原本的顏色、沒有 Minimalist 陰影），不影響其他功能。

4. **看結果**：最後會印出 `verify ...: N same, N differ, N missing`，接著分成三段說明：
   - `restore done: everything converted from the game is in place`：成功。
   - `differ`（內容和開發者那份不完全相同）是正常的：轉換時間、你的 `mods/` 清單、音訊重新編碼都會讓 bytes 不同，功能一樣。
   - `not needed ...`：不需要的資料（見下方），可以忽略。
   - `no converter yet ...`：還沒有轉換工具的資料，列出缺了它們會少哪些功能（見下方），可以忽略。
   - `no H voices ...`：沒有 H 語音（用了 `--skip h-voices`），H 場景沒有聲音，其他照常。
   - `missing from the game conversion ...` 或某一步印出 `FAILED`：把 `restore.log` 最後幾十行貼給使用者，再單獨重跑那一步，例如 `restore --game D:/KoikatuSunshine --only studio`。
5. **之後隨時檢查**：`.\Tools\lua\lua.exe Tools\original_data.lua verify`。

## H 語音（選用）

H 語音約 13 GB，只有 H 場景用得到。不需要的話轉換時加 `--skip h-voices`，磁碟少用 13 GB，H 場景照常進行，只是沒有聲音：

```powershell
.\Tools\lua\lua.exe Tools\original_data.lua restore --game D:/KoikatuSunshine --skip h-voices
# 之後想要時再單獨轉換
.\Tools\lua\lua.exe Tools\original_data.lua restore --game D:/KoikatuSunshine --only h-voices
```

## 不需要的東西

以下資料不轉換：

- **街區 demo 的原作台詞、語音與翻譯**：女角的對話由 AI 產生，聲音一律由 TTS 產生（沒有 TTS 時只顯示字幕），不使用原作台詞與語音檔。H 場景的語音不在此列，見上方「H 語音」。
- **Studio 樣本場景與截圖**（`UserData/Studio/scene/` 等）：只是開發時的測試資料。
- **角色卡**：倉庫沒有任何卡片，請用你自己的卡（原作卡、OK 卡）。

## 還沒有轉換工具的資料

以下幾項還不能從遊戲轉換，對應的功能會關閉，其他功能照常：

| 檔案 | 沒有時少掉的功能 |
|---|---|
| `Content/IndependentResources/BodyInteractions/`、`MotionCatalogue/` | 一對一互動的觸碰反應、雙人動作的名稱 |
| `Content/Koikatsu/Data/*.uasset` | 讀卡器的動畫目錄 |
| `Content/Scenes/CrowdRoom/*/Shared_*.uasset` | 百人房間的共用走路曲線 |

## 給維護者

- 哪些檔案算共用資源：[`Tools/original_data_manifest.json`](../Tools/original_data_manifest.json)（路徑、大小、sha256、類別）；每一類的來源（遊戲、zip、選用、不需要）與打進哪個 zip（`part`）寫在 `Tools/original_data.lua` 的 `GROUPS`。
- 新增轉換產物（不在 git 裡）到 manifest：`Tools\lua\lua.exe Tools\original_data.lua manifest-add <類別> <路徑...>`。
- 打包開發資源 zip：`Tools\lua\lua.exe Tools\original_data.lua pack --out <zip>`（不含 H 語音）；H 語音另外一包：`pack --part h-voices --out <zip>`。測試：`test-archive <zip> <空資料夾> [--part h-voices]`。還原時 `restore --archive <主 zip> [--h-voices <H 語音 zip>]`。
- 設計與驗證紀錄：[原作資料移出版控](ORIGINAL_DATA_OUT_OF_GIT_PLAN_20261104.md)。
