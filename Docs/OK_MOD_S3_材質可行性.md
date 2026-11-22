# OK mod 工作項 3：材質可行性實測（2026-11-23，F 組）

對應計畫 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §6.11（B 層 cook 材質 pak）與 §15.4 第 3 列。結論先講：

| 問題 | 結論 | 證據 |
|---|---|---|
| mod 的材質 pak 能不能放在 `Mods/<id>/content/`（不在 `Content/Paks`）由宿主掛載、開自己的 shader 庫、畫出來 | **能**。打包後的遊戲（Development，無 shader 編譯器）兩個材質都用 mod 自己的 shader 畫出 | `Saved/ModKit/Probe-S3a/probe.png`、`game.log` |
| Custom 節點 `#include` 外部 `.usf`，cook 後能不能不靠原始碼載入 | **能**。`.usf` 只在 cook 時讀，編好的 bytecode 在 mod 的 shader 庫裡；打包遊戲裡沒有那個 `.usf`、也沒有對應的虛擬 shader 路徑，材質照樣畫出 | 同上；另見下方「#include 的證據」 |
| 不開 shader 庫就載材質會怎樣 | 材質載得到但沒有 shader map，退回預設材質（暗場景裡整片黑），和 2026-11-17 的教訓一致 | `Saved/ModKit/Probe-S3b-NoLibrary/` |
| pak 白名單檢查能不能擋 Blueprint、擋越界路徑 | **能**。含 Blueprint 的 pak 被拒；檔案寫到 `/Game`、`/Engine` 對應路徑的 pak 被拒 | `Saved/ModKit/OKModBadSample/Cook1/verify.json`、`Saved/ModKit/OKModSampleMaterial/EscapeSample/verify/verify.json` |

## 做了什麼

### 1. 樣本內容外掛 `Plugins/OKModSampleMaterial`

- content-only（沒有 Modules），`EnabledByDefault: false`：遊戲與主編輯器都不啟用它，不會被 cook 進遊戲，也不影響任何建置；
- `Shaders/OKModSample.usf`：函式 `OKModSampleStripes(UV, Count)`，洋紅／青色斜紋加黃框，和引擎的灰色預設材質一眼可分；
- `Content/M_OKModSample.uasset`：Unlit 材質，一個 Custom 節點 `return OKModSampleStripes(UV, Count);`，`IncludeFilePaths = /Project/OKMod/OKModSampleMaterial/OKModSample.usf`，輸入接 TexCoord 與純量參數 `OKStripeCount`（預設 6）；
- `Content/MI_OKModSample.uasset`：上面的 MaterialInstanceConstant，`OKStripeCount = 12`（驗證 mod 內部的套件互相引用在重新掛載後仍解得開）。

這兩個 uasset 是在 cook 主機（下一節）裡用編輯器 Python 一次做出來的（`modkit_cook.lua --python <腳本>`；腳本是一次性的，沒有進版控）。mod 作者平常是在 ModKit 編輯器裡手動做。

**掛載根**：UE 外掛的套件根只能是 `/<外掛名>/`，不能是 `/OKMod/<id>/`（名稱不能有斜線）。所以目前的實際對應是：

- mod id ＝ 外掛名（`OKModSampleMaterial`），套件根 `/OKModSampleMaterial/`；
- pak 內的實體路徑（mount point）是 `../../../OpenKoikatsu/Mods/<id>/Content/`；
- 宿主掛載後 `FPackageName::RegisterMountPoint("/<id>/", "<專案>/Mods/<id>/Content/")`。

計畫裡寫的 `/OKMod/<id>/` 建議改成「`/<id>/`，且 id 必須是外掛名、宿主保留以 `OKMod` 開頭」或由 `ok-mod-pack` 檢查 id 不撞核心外掛名（`/KKRuntimePose/`、`/Game/` 等）。要真的變成 `/OKMod/<id>/` 得在 cook 時改寫套件名（UE 沒有現成的做法），不建議。

### 2. `Tools/modkit_cook.lua`（雛形，之後歸工作項 9）

```powershell
.\Tools\lua\lua.exe Tools\modkit_cook.lua --mod OKModSampleMaterial            # cook → pak → 檢查，最後一行是 pak
.\Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> --verify <pak>             # 只檢查，被拒時 exit 1
.\Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> --python <腳本.py>         # 在 cook 主機裡跑編輯器 Python（無介面製作）
.\Tools\lua\lua.exe Tools\modkit_cook.lua --mod <id> --prepare-only             # 只建 cook 主機，印出 .uproject
```

- **cook 主機** `Saved/ModKit/<id>/Host/OKModCook_<id>.uproject`：content-only 專案，用引擎現成的 `UnrealEditor-Cmd.exe`，**不用編 C++**（十幾秒 cook 完）。內容：
  - `Plugins/<id>` → junction 到 mod 外掛；
  - `Shaders/OKMod/<id>` → junction 到外掛的 `Shaders/`。引擎啟動時自動把 `<專案>/Shaders` 對應成 `/Project`，所以 Custom 節點用 `/Project/OKMod/<id>/<檔>.usf`。content-only 外掛沒有模組，無法自己呼叫 `AddShaderSourceDirectoryMapping` 對應 `/Plugin/<id>`；
  - `Config/DefaultEngine.ini` 直接複製遊戲的（同樣的 renderer 設定才會編出同樣的 permutation），再補兩行把遊戲模組的類別（DreamGUI viewport client、GameMode）指回引擎類別；加上 `CrowdCookSM6`（只編 DX12 SM6）與傳統 pak 的 `DefaultGame.ini`。
- **shader 庫名稱** ＝ cook 主機的專案名 `OKModCook_<id>`，檔名 `ShaderArchive-OKModCook_<id>-PCD3D_SM6-PCD3D_SM6.ushaderbytecode`，不會和遊戲或別的 mod 的庫撞名（和街區補丁用 `RuntimeMaterialBake` 專案名的做法相同）。
- **pak**：`UnrealPak -Create`，傳統 pak；mount point `../../../OpenKoikatsu/Mods/<id>/Content/`，內含 mod 的 `.uasset/.uexp` 與 shader 庫。
- **cook 結果檢查**：材質編不過時 cook 仍回 `Success - 0 error(s)`、照樣產生 pak（見下方 #include 證據），所以腳本掃 cook log，遇到 `Failed to compile Material`、`valid ShaderMap`、`Expression include file path ... invalid` 就失敗。

### 3. 白名單檢查（`--verify`，之後移到 Rust 的 `ok-mod-pack`，工作項 12）

1. `UnrealPak -List` 取 mount point 與檔案清單；每個檔案的完整路徑必須在 `../../../OpenKoikatsu/Mods/<id>/Content/` 底下，不准 `./`、`../` 跳出；
2. 檔案種類只准 `.uasset/.uexp/.ubulk/.uptnl` 與根目錄的 `ShaderArchive-OKModCook_<id>-*.ushaderbytecode`；`.umap`、`.ini`、`.dll` 等一律拒；
3. `UnrealPak -Extract` 後逐一讀 `.uasset` 的 header（Lua 直接解析 `FPackageFileSummary`、import 表、export 表，格式依 `PackageFileSummary.cpp`、`ObjectResource.cpp`）：
   - 必須是 cooked 套件（`PKG_Cooked`＋`PKG_FilterEditorOnly`），套件名必須是 `/<id>/<相對路徑>`；
   - **每個 export** 的類別都必須是 `/Script/Engine` 的原生類別且在 §6.11 白名單（`Material`、`MaterialInstanceConstant`、`MaterialFunction`、`MaterialParameterCollection`、`Texture2D`、`TextureCube`、`Texture2DArray`、`VolumeTexture`、`SubsurfaceProfile`）；類別定義在包內（`ClassIndex > 0`，例如 Blueprint 產生的 `_C` 類別）直接拒；
   - 必須有一個與檔名同名的頂層資產。
4. 結果寫 `verify.json`。

| 測試 pak | 結果 | 理由 |
|---|---|---|
| 樣本 `Saved/ModKit/OKModSampleMaterial/Cook2/pak/OKModSampleMaterial.pak` | 接受 | `M_OKModSample`＝Material、`MI_OKModSample`＝MaterialInstanceConstant |
| Blueprint 反例 `Saved/ModKit/OKModBadSample/Cook1/pak/OKModBadSample.pak`（Actor Blueprint＋一個空材質，外掛放在 `Saved/ModKit/BadSample/`，不進版控） | **拒絕** | `BP_OKModBad_C` 的類別 `BlueprintGeneratedClass`、`Default__BP_OKModBad_C` 的類別定義在包內、`SimpleConstructionScript`／`SCS_Node`／`SceneComponent` 不在白名單 |
| 越界反例 `Saved/ModKit/OKModSampleMaterial/EscapeSample/OKModSampleMaterial.pak`（手工把檔案寫到 `../../../OpenKoikatsu/Content/IndependentResources/RuntimeMaterials/M_Hijack.uasset` 與 `../../../Engine/Content/EngineMaterials/WorldGridMaterial.uexp`） | **拒絕** | 兩個路徑都在 mod 根外；也沒有 shader 庫 |

### 4. 打包後遊戲實測

- 探針 `Source/OpenKoikatsu/OKModMaterialProbe.cpp`（新檔，只在非 Shipping）：主控台指令 `ok.ModMaterialProbe Mod=<id> [Pak=] [Library=] [Assets=a+b] [NoLibrary=1] [Shot=] [Quit=1]`，順序照 §6.11：
  1. `FCoreDelegates::MountPak(<專案>/Mods/<id>/content/<id>.pak, 0)`（最低順位）；
  2. `FPackageName::RegisterMountPoint("/<id>/", <專案>/Mods/<id>/Content/)`；
  3. `FShaderCodeLibrary::OpenLibrary("OKModCook_<id>", 同一目錄)`；
  4. `LoadObject` 材質，檢查 `GetMaterialResource(GMaxRHIShaderPlatform)->GetGameThreadShaderMap()`，各放在相機前一塊 Plane 上，3 秒後截圖、6 秒後結束。
  引擎現成的 `Mount` 主控台指令只做得到第 1 步（沒有註冊套件根、開 shader 庫、擺物件的指令），所以還是要 C++。工作項 6／9 會把這段吸收進宿主。
- 探針用的最小打包遊戲 `Tools/modkit_probe.lua stage`：遊戲 Development 執行檔（`Binaries/Win64`）＋只 cook `/Engine/Maps/Entry` 與 `/Engine/BasicShapes/Plane`（`-NoGameAlwaysCook`）＋UAT `-stage -pak -skipiostore` 到 `Saved/ModKit/ProbeStage/Stage`（傳統 pak，約 2.5 分鐘）。`Tools/modkit_probe.lua run` 把 pak 複製到 `<stage>/Windows/OpenKoikatsu/Mods/<id>/content/<id>.pak`，以 `Entry?game=/Script/Engine.GameModeBase` 啟動並執行探針。

| 實測 | 指令 | 結果 |
|---|---|---|
| S3a 正常 | `modkit_probe.lua run --mod OKModSampleMaterial --pak Saved/ModKit/OKModSampleMaterial/Cook1/pak/OKModSampleMaterial.pak --tag S3a` | `open library ... -> 1`；兩個資產 `shadermap=1 default=0`；`drawn_with_mod_shaders=2 of 2`；截圖兩塊斜紋板（左 6 條、右 12 條） |
| S3b 不開庫 | 同上加 `--no-library`，tag `S3b-NoLibrary` | 兩個資產 `shadermap=0`，`drawn_with_mod_shaders=0`；截圖全黑（預設材質在無光的 Entry 地圖裡是黑的） |
| S3c 少 `.usf` cook 的 pak | `--pak Saved/ModKit/OKModSampleMaterial/CookNoInclude/pak/OKModSampleMaterial.pak --tag S3c-NoInclude` | 庫開得起來，但材質 `shadermap=0`，退回預設 |

S3a 的 game.log 還記錄了引擎這一側：`Mounted Pak file '.../Mods/OKModSampleMaterial/content/OKModSampleMaterial.pak', mount point: '../../../OpenKoikatsu/Mods/OKModSampleMaterial/Content/'`、`Mount point added ... mounted to '/OKModSampleMaterial/'`、`Using .../ShaderArchive-OKModCook_OKModSampleMaterial-PCD3D_SM6-PCD3D_SM6.ushaderbytecode for material shader code. Total 1093 unique shaders.`

## #include 的證據

1. **cook 時一定要有 `.usf`**：把 `OKModSample.usf` 暫時移走再 cook（`Saved/ModKit/OKModSampleMaterial/CookNoInclude/cook.log`），log 依序是 `Expression include file path '/Project/OKMod/OKModSampleMaterial/OKModSample.usf' is invalid, removing from cached data`、`Failed to compile Material /OKModSampleMaterial/M_OKModSample ... Default Material will be used in game`、`Cooking a material resource ... that doesn't have a valid ShaderMap`，而 cook 結尾仍是 `Success - 0 error(s), 3 warning(s)`；`ShaderAssetInfo` 裡沒有這個材質。這個 pak 在遊戲裡退回預設材質（S3c）。也就是說 Custom 節點真的用到了外部 `.usf`，不是被忽略。
2. **執行期不需要 `.usf`**：打包 stage 裡找不到任何 `OKModSample` 的 `.usf`（`Saved/ModKit/ProbeStage/Stage` 只有 mod 的 pak），遊戲裡也沒有 `/Project/OKMod/...` 的虛擬路徑；S3a 照樣畫出來，log 沒有任何 shader 原始碼路徑的錯誤。
3. **原始碼層面的理由**：include 路徑存在材質的 `EditorOnlyData->ExpressionIncludeFilePaths`（cook 時剝除），計算 include 檔雜湊的 `FMaterial::GetExpressionIncludesHash` 只在 `WITH_EDITOR` 編譯；`AddShaderSourceDirectoryMapping` 在 `RequiresCookedData()` 的平台直接 return。打包遊戲只靠 shader 庫裡以 shader map hash 查到的 bytecode。

結論：**ModKit 裡 `#include` 外部 `.usf` 可以用；條件是 cook 時看得到該檔（cook 主機做虛擬路徑對應），發布的 pak 不帶也不需要原始碼。**

## 沒驗的

- 只驗了 Unlit 材質畫在引擎 `FLocalVertexFactory`（StaticMesh）上。**角色用的 GPU skin／KKRuntimePose 的 vertex factory 沒驗**：cook 主機沒有啟用遊戲的外掛（KKRuntimePose、OKHGShading、KKCrowdGpuPacking…），那些外掛自己的 vertex factory 的 permutation 不會編進 mod 的庫。工作項 9 要讓 mod 材質上角色，cook 主機得帶上這些外掛（像 `prepare_runtime_shared_material.lua` 的 bake host 那樣要編 C++），或確認材質只用引擎的 VF。
- 沒驗 Lit 材質、OK 的 ramp／陰影參數契約、材質函式、貼圖、MaterialParameterCollection（白名單裡的這幾類沒有樣本，只有 Material 與 MIC 實際跑過）。
- 沒驗街區／讀卡器的正式 stage（F 沒有街區 stage；用的是只 cook Entry 的最小 stage），沒驗 IoStore 遊戲（計畫本來就用傳統 pak）。
- 沒驗 PSO 預熱、卸載 mod（`Unmount` 與 `CloseLibrary`）、兩個 mod 同時掛載、`content_build` 版本鎖。
- 檢查器只讀 header，不檢查 export 內容；`.ubulk/.uptnl` 只看路徑。

## 給工作項 9 的建議

1. **掛載順序照探針**：Mount（最低順位）→ `RegisterMountPoint("/<id>/", <Mods>/<id>/Content/)` → `OpenLibrary("OKModCook_<id>", 同目錄)` → 才載材質。`OpenLibrary` 失敗就整個 mod 的材質不載（不然會靜默變黑）；載入後檢查 `GetGameThreadShaderMap()` 非空，空的就拒用並寫明。
2. **mod id 規則**：id ＝ 外掛名、套件根 `/<id>/`，`ok-mod-pack` 要檢查 id 不撞核心外掛與 `Game`／`Engine`／`Script`；計畫 §6.11 的 `/OKMod/<id>/` 改寫成這個。
3. **虛擬 shader 路徑**：目前 `/Project/OKMod/<id>/`（cook 主機的 `Shaders/` junction）。若 ModKit 想讓作者在主編輯器裡直接開 mod 材質，要嘛在主專案根放一個不進版控的 `Shaders/OKMod/<id>` junction，要嘛由 `Plugins/OKModding` 的編輯器模組在 PostConfigInit 把 `/Project/OKMod/<id>` 以外的寫法也對應好。**路徑一旦寫進材質就固定**，建議定案用 `/Project/OKMod/<id>/`，不要之後再改。
4. **shader 庫偏大**：樣本庫 7 MB、1093 個 shader，大部分是 Entry 地圖帶進來的引擎材質。要瘦身可以試不帶 `-MAP`、或 cook 後用 `ShaderAssetInfo-*.json` 只保留 mod 資產的 shader map（需要另寫工具，沒試）。
5. **cook 成功碼不可信**：沿用 `modkit_cook.lua` 掃 log 的做法，或改查 `ShaderAssetInfo` 是否列出每個 Material。
6. **角色材質**：先決定 mod 材質要不要支援 KKRuntimePose 的 vertex factory（見「沒驗的」第 1 點），這會決定 cook 主機要不要編 C++。

## 產物位置（都在 `Saved/`，不進版控）

- 樣本 pak：`F:\OpenKoikatsu\Saved\ModKit\OKModSampleMaterial\Cook2\pak\OKModSampleMaterial.pak`（Cook1 是實測用的同一份內容）
- cook log：`F:\OpenKoikatsu\Saved\ModKit\OKModSampleMaterial\Cook1\cook.log`、少 `.usf` 的 `F:\OpenKoikatsu\Saved\ModKit\OKModSampleMaterial\CookNoInclude\cook.log`
- 檢查結果：`F:\OpenKoikatsu\Saved\ModKit\OKModSampleMaterial\Verify2\verify.json`、`F:\OpenKoikatsu\Saved\ModKit\OKModBadSample\Cook1\verify.json`、`F:\OpenKoikatsu\Saved\ModKit\OKModSampleMaterial\EscapeSample\verify\verify.json`
- 遊戲實測：`F:\OpenKoikatsu\Saved\ModKit\Probe-S3a\probe.png`、`F:\OpenKoikatsu\Saved\ModKit\Probe-S3a\game.log`；對照組 `F:\OpenKoikatsu\Saved\ModKit\Probe-S3b-NoLibrary\`、`F:\OpenKoikatsu\Saved\ModKit\Probe-S3c-NoInclude\`
- 最小 stage：`F:\OpenKoikatsu\Saved\ModKit\ProbeStage\Stage\Windows\OpenKoikatsu\Binaries\Win64\OpenKoikatsu.exe`（約 5.4 GB，含 `v1` 的 NonUFS 資源，用完可刪）
- 建置 log：`F:\OpenKoikatsu\Saved\ModKit\Build\game.log`、`F:\OpenKoikatsu\Saved\ModKit\Build\editor.log`（F 引擎建 `OpenKoikatsu` Development 與 `OpenKoikatsuEditor` 都 `Result: Succeeded`）
