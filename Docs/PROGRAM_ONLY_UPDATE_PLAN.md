# 只更新程式、不重發資源包（方案，2026-11-24）

使用者問：下次能不能只更新程式？`Studio-20261124-release-e` 裡程式約 1.41 GiB、資源約 34.7 GiB，差 25 倍。這份是方案，協調者審過才動工。

**目前狀態（2026-11-24）**

- 第 1 節分組、第 4 節 `--program-only`、`RESOURCES.json`／`PACKAGE.json` 的寫入、安裝說明（[OK_STUDIO_MOD_PACKAGE.md](OK_STUDIO_MOD_PACKAGE.md)「只更新程式」）已實作。
- 第 2、3 節（資源版本與相容性檢查）**改由 C 組另行規劃**，這裡寫的版本規則不作數。協調者審出的四個問題交給 C 組解：
  1. 「資源比程式新不算不符」是錯的，要改成程式宣告一個可接受的區間；
  2. 不能只靠人工 +1，要同時比機器讀得到的子版本，並擋下「改了格式忘了 +1」；
  3. 舊 stage 的清理要寫明 junction（安裝說明已寫：先拆 junction 再刪）；
  4. 覆蓋安裝時 `Tools/` 的 exe 可能正在跑（安裝說明已列出要先關哪些）。
- 在版本檢查定案前，`--program-only` 的自檢用一個實際的檢查代替：用程式包自己的 `ok-extract`，搭配 `--resources-from` 完整包的基礎庫，嚴格開該包最多 10 張 OK 卡（`--oklib strict-check`，新程序、不用快取）。任何一張開不起來就失敗，並要求先發新的完整包。
- **版本判準**：以下照抄 C 組定稿 `C:\portable\OpenKoikatsu\Docs\RESOURCE_PROGRAM_COMPAT_GATE_PLAN.md`（C 樹 `853c039c6`）§2.4，兩份文件不各講一套。

  > **版本判準是兩層，兩層都要。**
  >
  > 第一層是 `RESOURCES.json` 的人工整數 `version`，對應程式裡的 `[RESOURCES_MIN, RESOURCES_MAX]` 區間。它是**宣告**：「我知道這版不相容」。它存在的理由是有些不相容不落在任何機器讀得到的子版本上——例如模型檔的內部編碼換了，而 `oklib.json` 的 version 沒動；那時整數是唯一的表達方式。資源落在區間外都算不符，**包括比程式新**（訊息方向是「請更新程式」）。
  >
  > 第二層是機器實際讀出來的子版本，比對程式原始碼裡的常數：`mods_index.db` 的 `meta.schema` 對 `modsindex::SCHEMA`、`oklib.json` 的 `version`、再加幾個必要檔案的存在性與一個「開庫問一個已知查詢」的 selftest。它是**兜底**：忘了把整數 +1 也照樣擋得住。2026-11-24 第一份程式包撞的就是這一層（schema 1 的資源配要 schema 2 的程式，索引讀成 0 個 GUID，原作卡照樣開起來卻假報缺 42 個 mod）。
  >
  > **不比 `shared_mods.txt` 與 `mods_index.db` 的 SHA-256**，雖然 `RESOURCES.json` 會記著它們。記是為了出事時對帳；比會天天假警報：`shared_mods.txt` 的內容跟著「這台裝了哪些 mod」變，`mods_index.db` 重建一次雜湊就變而相容性根本沒變。**假警報比沒有閘更糟，因為使用者會學會忽略它**。這兩個檔只檢查**存在**（缺了會讓庫給出錯的答案，那是 block）。

  一句話：整數是宣告，子版本是兜底，雜湊只記不比。缺 `RESOURCES.json`（`no_resources_json`）是唯一依現場而變等級的項目：出貨安裝（`PACKAGE.json` 的 `kind` 是 `program` 或 `full`）block，開發樹 warn，判的是「這份安裝是不是出貨的」。
- `RESOURCES.json` 的整數 `version` 只有一個來源：`Tools/ok-extract/src/resources.rs` 的 `RESOURCES_VERSION`，打包腳本從那裡讀。該檔進樹前暫用 1（涵蓋到 `717297c3b` 為止的格式），`version_from` 會註明。
- `RESOURCES.json` 另外只記事實，供之後的檢查比對：
  - 帶了哪些資源組、各幾個檔、多大；
  - `oklib.json` 的 version；
  - `shared_mods.txt` 與 `mods_index.db` 的大小和 sha256，放在 `record_only` 底下並附註「只記不比」，避免以後被誤拿來當判準。

  「需要哪一版」的欄位等 C 組定。

## 1. 什麼算程式、什麼算資源

判準只有一條，看檔案從哪來，不看放在哪個資料夾：

| 組 | 判準 | 現在有哪些 | 容量（release-e） |
|---|---|---|---:|
| **資源** | `Tools/original_data_manifest.json` 有列的檔（原作與 mod 衍生，不進版控） | `base_v1`（含 `mods_index.db`）、`RuntimeAnimations/*.okanim` 960 個、`BodyInteractions`、`MotionCatalogue`、`Content/KKPreview`、`Content/Koikatsu`、`Content/Scenes` | 約 30.6 GiB |
| **資源** | 打包時另外帶進去、不在版控的大檔 | `Content/CharacterCards`（`--cards` 的 OK 卡）、`HairDeckData/`（權重） | 約 4.1 GiB |
| **程式** | 其餘全部：建置產物，加上版控裡的自製內容 | `Saved/StreetSocial/Build/<tag>.stage`（exe、paks、Patch、Mods）、`Tools/`、啟動檔 `*.cmd`、`Config/`、`Docs/`、`ModPackages/`、`Plugins/`、`Licenses/`、`PACKAGE.json`、`OK_STUDIO_MOD_PACKAGE.md`，以及 `Content/IndependentResources` 裡不在 manifest 的自製小檔（`StreetSocialData`、`Story`、`PreviewMaterials`、`OKStudio`、`Studio`、`VideoMotionDemos`、`StreetSocialCity`、`RuntimeAnimations` 裡 18 個自製檔） | 約 1.41 GiB |

之後加新東西照這條歸組：

- 從原作或 mod 轉出來的，一律進 manifest，所以屬於資源。
- 自己寫的、進版控的，屬於程式。
- 不進版控、也不是原作資料的大檔（權重之類），在 `package_studio_release.lua` 的資源清單明列。

`Licenses/` 兩邊都放：`DINOv3-LICENSE.md` 要跟 `HairDeckData` 走。

## 2. 資源包版本

- **資源包版本號**：`ok-extract` 裡一個整數常數 `RESOURCES_VERSION`，由開卡格式的維護者（目前是 e-cardload）負責。
  - **何時 +1**：只要「新程式配舊資源會開不了卡或靜默少件」就 +1。今天的 `ae89b2073`（txt 換成 `mods_index.db`）和 `7e7e4b7aa`（共用劃分）都算。
- **完整包寫版本**：完整包打包時，在 `Content/IndependentResources/RESOURCES.json` 寫入：
  ```json
  {"format": "ok-resources", "version": 3, "made": "2026-11-24T11:49:57Z", "commit": "b8d394043",
   "package": "Studio-20261124-release-e", "groups": ["base-index", "base-models", "..."],
   "parts": {"oklib": 2, "mods_index_schema": 2}}
  ```
- **程式包寫需求**：程式包的 `PACKAGE.json` 加 `"kind": "program"` 與 `"requires_resources": 3`。完整包是 `"kind": "full"`，同時寫兩個欄位。
- **檢查做在 Rust**：格式是 Rust 那邊的，檢查也放在那裡。
  - CLI：`ok-extract --oklib resources-check <base_v1>`。
  - C ABI：回 JSON，`{"ok": false, "problems": [{"what": ..., "fix": ...}]}`。
- **逐項比對**：
  1. `RESOURCES.json` 是否存在，`version` 是否不小於程式需要的版本；
  2. `oklib.json` 的 `version`；
  3. `mods_index.db` 的 schema；
  4. 其他由 e-cardload 指定的檔案。

  第 2、3 項各自可能有本機能補的修法。哪些檔要比、`mods_dir` 不同算不算問題，已經去問 e-cardload，還在等回覆。

## 3. 不符時怎麼講

- **檢查時機**：
  - 啟動器（`run_card_reader_development.lua`、OKStudio 那支）啟動前先跑一次 CLI 檢查，不符就在主控台講清楚，並 `pause`；
  - 遊戲起來後，讀卡器和 Studio 也各查一次。
- **遊戲內的呈現**：
  - 不符時畫面上方掛常駐通知（`ScreenNote`／`ShowNotice`，紅色，不會自己消失）；
  - 開卡一律擋下（原作卡與 OK 卡都擋），擋的時候再說一次原因。不會先開了再缺件。
- **訊息範例**：資源太舊、本機補不了：
  ```
  資源包太舊，這版程式開不了卡。
    程式需要資源版本 3，這台裝的是 2（Studio-20261123-release-b，2026-11-23）。
    請下載完整包 Studio-20261124-release-e，或至少它的資源部分，解壓覆蓋到 E:\OKPackage\Studio-xxxx\。
  ```
- **訊息範例**：只是索引要重建、本機有遊戲：
  ```
  mod 索引是舊格式（schema 1），這版需要 2。
    本機有遊戲的話，在安裝資料夾執行：
    Tools\ok-extract\target\release\ok-extract.exe D:/KoikatuSunshine --oklib mods-index Content\IndependentResources\base_v1
    沒有遊戲就下載新的完整包。
  ```
- **版本更新**：資源比程式新是正常狀態。只有程式比資源新、跨過一次 `RESOURCES_VERSION` +1，才算不符。

## 4. `--program-only` 流程

```
Tools\lua\lua.exe Tools\package_studio_release.lua --tag <Name> --out <新資料夾> --program-only [--zip] [--zip-threads N]
```

- **建置**：第 1～6 步照舊（工具、編輯器、stage、modkit、mods）。程式包不帶卡片，所以 `--cards` 可以不給。
- **打包**：第 7 步叫 `package_street_social.lua` 時加一個「不帶資源」的開關，略過 manifest 的所有 group、`--cards` 與 HairDeck。`PACKAGE.json` 照樣列出放進去的檔，並寫 `kind: program` 與 `requires_resources`。
- **自檢**：照舊跑，只是不查資源。
  - 照舊查：沒有 `.pdb`、啟動檔只有 ASCII、每個工具起得來、mods verify、paks 裡沒有遊戲地圖。
  - 拿掉：`base_v1`、HairDeck 權重、HairDeck generate 的檢查（包裡沒有權重）。
  - 新增：
    1. 包裡沒有任何 manifest 或卡片或 HairDeck 檔，防止誤帶資源；
    2. 用最近一個完整包（`--resources-from <完整包資料夾>`，預設找 `E:\OKPackage` 下最新的 full 包）跑一次 `resources-check`，證明這份程式能配現有資源。不通過就失敗，並在訊息裡說要先發新的完整包。
- **壓縮**：`--zip` 壓完照樣 `7z t`。
- **玩家怎麼裝**：把程式包解壓覆蓋到既有安裝資料夾。
  - 新的 `.stage` 名字不同，和舊的並存，啟動器挑最新的那個，第一次啟動時自己把 Content 接到既有資源。
  - `Tools/`、啟動檔、`Config/`、`Docs/` 直接覆蓋。
  - 舊 stage 可以手動刪，或下一版加一個清理指令。
  - 說明寫進 `OK_STUDIO_MOD_PACKAGE.md`。

## 5. 要改的地方

| 檔 | 改什麼 | 誰 |
|---|---|---|
| `Tools/ok-extract`（`oklib.rs` 或新檔） | `RESOURCES_VERSION`、`resources-check` CLI 與 C ABI | e-cardload（或我寫、它審，看它回覆） |
| `Tools/package_street_social.lua` | 不帶資源的開關；完整包寫 `RESOURCES.json`；`PACKAGE.json` 的 `kind` 與 `requires_resources` | 我 |
| `Tools/package_studio_release.lua` | `--program-only`、`--resources-from`、對應的預檢與自檢 | 我 |
| `Tools/run_card_reader_development.lua`、OKStudio 啟動器 | 啟動前檢查，不符就講並停下 | 我 |
| `Source/OpenKoikatsu`（讀卡器）、`Plugins/OKStudio` | 啟動時檢查、常駐通知、擋開卡 | 我 |
| `Docs/OK_STUDIO_MOD_PACKAGE.md`、這份文件 | 歸組規則、玩家怎麼裝程式包 | 我 |

## 6. 驗收

1. 用目前的樹打 `--program-only`，覆蓋到 `Studio-20261124-release-e` 的複本上：讀卡器能開原作卡和 OK 卡，Studio 能開。
2. 把複本的 `RESOURCES.json` 改成舊版本：啟動器先講，遊戲畫面上也講，開卡被擋。
3. 把 `mods_index.db` 換成 schema 1：畫面講清楚，並給出重建指令。
4. 程式包裡沒有 `.pdb`，也沒有任何資源檔；zip 通過 `7z t`。

## 7. 實測紀錄（2026-11-24）

- `--program-only` 打出 `E:\OKPackage\Studio-20261124-program-f`：1.5 GB、1618 個檔，zip 782,503,378 bytes，通過 `7z t`。
- 第一版自檢只用新程式嚴格開 release-e 的 10 張 OK 卡，全過。
- 把程式包疊到 release-e 的硬連結複本上之後，問題出在原作卡：
  - 新程式要 `mods_index.db` schema 2，release-e 帶的是 schema 1；
  - 結果索引讀不進來（0 GUID），伊莉雅變成「缺 42 個 mod」、KK_019440 變成「缺 18 個」，卡卻照樣開起來；
  - 缺件畫面有列出來，但那是錯的答案：那些 mod 都有裝。
- 原因：OK 卡不經過 mod 索引，所以第一版自檢抓不到。
- 修正：自檢加一項，把 `--resources-from` 的 `mods_index.db` 的 `meta.schema` 和這份原始碼 `modsindex.rs` 的 `SCHEMA` 比對，不同就失敗。重跑後自檢正確擋下（schema 1 對 2），不產生 zip。
- 第一次產生的 zip 已改名為 `Studio-20261124-program-f.DO-NOT-USE-needs-schema2-resources.zip`，不能疊在 release-e 上。
- 這也證明協調者的第 2 點：只靠人工 +1 的版本號一定會漏，要比機器讀得到的子版本。e-cardload 的 `resources_check` 做好後，這項臨時檢查改成呼叫它。

## 8. 待辦

- **`ok_resources_check` 進樹後要接的地方**（e-cardload 負責寫這個檢查，介面已對好）：
  - 讀卡器與 Studio 的畫面通知：`block` 擋下開卡，`warn` 只提示；
  - 啟動器在主控台的檢查；
  - 把 `--program-only` 自檢裡臨時的 schema 比對，改成呼叫它。由它**取代**這項比對，不讓兩套判準並存（C 組文件 §6.2）。
  - 自檢開卡要 **OK 卡與原作卡各一張**。原作卡要指名第三方 mod：2026-11-24 那次就是只驗 OK 卡，而 OK 卡不經過 mod 索引，所以沒抓到。

  版本規則等 C 組定案。
- **新 stage 沿用舊 stage 的 mod 配置**：
  - 啟動器第一次用到新 stage 時，比對前一個 stage 的 `Mods/.installed.toml`。
  - 舊的有新的沒有的 mod，或啟用狀態不同，就在主控台與畫面上講一句，並附上 `ok-mod-pack profile apply` 的指令。
  - 現在只寫在安裝說明裡，玩家容易漏看。
- **測試夾具 `E:\OKPackage\overlay-test-1124f`**：release-e 的硬連結複本，上面疊了 program-f。
  - 版本檢查做好、用它驗過「擋得住」之後才刪。
  - 裡面有硬連結與 junction，不能遞迴刪除，要照安裝說明「舊 stage 要不要刪」那套先拆 junction 再刪。
