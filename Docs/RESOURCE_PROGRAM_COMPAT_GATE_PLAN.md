# 程式包／資源包版本相容性閘（方案，2026-11-24）

**適用範圍**：只更新程式、不重發資源包時，確保「舊資源配新程式」不會變成**靜默少件**。
這份只寫方案，**審過才實作**；本輪沒有動任何程式碼。

> 2026-11-24 晚：Rust 那頭的判準已由 e-cardload（`[E組] 開卡片優化`）拍板，§2、§3、§8 已按它的答覆改寫；
> 原稿與它的差異記在 §7，那裡也留著唯一還沒定的一條（開發樹沒有 `RESOURCES.json` 怎麼算）。
> 分工：Rust（`resources.rs` 的常數、`resources_check`、CLI、C ABI）由 e-cardload 寫；UE 畫面與打包腳本是我們這邊。

- 這份負責的是**相容性閘**（版本放哪、誰寫誰讀、比哪些檔、不符怎麼擋、怎麼講、怎麼驗）。
- 分組規則、`--program-only` 打包流程、玩家安裝說明，在 E 樹 `E:\OpenKoikatsu\Docs\PROGRAM_ONLY_UPDATE_PLAN.md`（MOD 框架 session 寫的），這份不重寫那部分，只補它缺的四塊與必要的修正。
- 相關程式碼：`Tools/ok-extract/src/oklib.rs`、`okstrict.rs`、`modsindex.rs`、`ffi.rs`；`Tools/package_studio_release.lua`、`Tools/package_street_social.lua`、`Tools/original_data_manifest.json`；`Tools/run_card_reader_development.lua`、`Tools/street_stage.lua`；`Source/OpenKoikatsu/OKGalleryWidget.cpp`（`CheckAbsentMods` 是現成的畫面通知樣板）。

## 0. 為什麼非做不可：靜默少件的實際路徑

不是假想。`modsindex.rs` 現在是這樣：庫的 `mods_index.db` schema 不是這版程式要的，`Db::open` 只寫一行 `OKMODS ... is schema N, this build needs M` 到 profile log，然後**回 `None`**。於是 `available()` 是 false，開卡的 GUID 查詢問不到答案，而打包版沒有遊戲 `mods/` 可走——卡片指名的那件衣服就是沒穿上，畫面上只會說「已加载3D」。

同一類的還有：`oklib.json` 的 `version`（現在 2）、封卡資源包 `okLc` 的 `CARD_PACK_VERSION`（現在 2）、`shared_mods.txt` 決定庫能服務哪些 archive（E 樹 `7e7e4b7aa` 改過共用／非共用劃分，直接影響封卡帶什麼 bundle）。這些都是**程式產生、程式讀回**的格式，而程式包只有 1.41 GiB、資源包 34.7 GiB，一旦允許分開更新，兩邊版本就會錯開。

**標準（使用者定的）**：寧可擋下來講清楚，也不要靜默少件。所以閘的設計原則是三條：

1. **閘在開庫處，不在 UI**。擋點放 Rust `oklib::activate()`，讀卡器、OK Studio、MCP、CLI、mod 走的是同一條，沒有繞路。
2. **先擋再講**。不符時沒有「先開了再提示」這種中間狀態。
3. **寧可誤擋**。不認識的子版本一律算不符，不猜「大概可以」。

## 1. 版本放哪、誰寫、誰讀

### 1.1 程式宣告的是「區間」，不是下限

`ok-extract` 裡兩個常數（`src/resources.rs`，新檔，常數與檢查都在裡面，diff 一眼看得到；由 e-cardload 維護：改到會讓舊資源配新程式開不了卡或靜默少件的格式，就順手 +1 並在那個檔裡寫一行為什麼）：

```rust
/// 這版程式懂的最舊資源包格式。
pub const RESOURCES_MIN: u32 = 3;
/// 這版程式懂的最新資源包格式。比這個新的資源包，是程式太舊。
pub const RESOURCES_MAX: u32 = 3;
```

**這一條是對 MOD 那份方案的修正**：它寫「資源比程式新是正常狀態，只有程式比資源新才算不符」，這是錯的。資源包換到新格式（庫帶了 schema 3 的 `mods_index.db`、`oklib.json` version 3）時，舊程式一樣讀不懂，而且壞法就是靜默少件。所以：

| 關係 | 判定 | 訊息方向 |
|---|---|---|
| `version < RESOURCES_MIN` | 不符 | 請更新資源包（或本機重建那一項） |
| `RESOURCES_MIN ≤ version ≤ RESOURCES_MAX` | 相容 | — |
| `version > RESOURCES_MAX` | 不符 | **請更新程式** |

平常兩個常數相等；只有在刻意保留一版相容（例如新程式能同時吃 version 3 與 4 的庫）時 `MAX` 才比 `MIN` 大，而且要在那一版的 commit 裡寫明「為什麼能同時吃」。

第一版的區間要把**今天這兩筆格式改動算進去**：`ae89b2073`（兩張文字表 → `mods_index.db`）與 `717297c3b`（schema 2，加 migration 表）。也就是說今天以前打的完整包，一律是「資源太舊」。

### 1.2 完整包寫什麼

完整包打包時，`package_street_social.lua` 在資源那一側寫 `Content/IndependentResources/RESOURCES.json`：

```json
{
  "format": "ok-resources",
  "version": 3,
  "made": "2026-11-24T11:49:57Z",
  "commit": "b8d394043",
  "package": "Studio-20261124-release-e",
  "groups": ["base-index", "base-models", "runtime-animations", "kkpreview", "cards", "hairdeck"],
  "parts": {
    "oklib_version": 2,
    "mods_index_schema": 2,
    "has_shared_mods": true,
    "has_models_ignore": true,
    "has_sources": true
  }
}
```

`version` 是人工整數（§2.1），`parts` 是**從實際檔案讀出來的**，不是手打的，而且整串由 `ok-extract --oklib resources-stamp <base_v1>` 印出來給打包腳本轉抄——**打包腳本不自己解析任何庫格式**（它不該知道 `oklib.json` 長什麼樣，也不該自己開 SQLite）。

### 1.3 程式包寫什麼

`PACKAGE.json` 加三個欄位：

```json
{ "kind": "program", "requires_resources_min": 3, "requires_resources_max": 3 }
```

完整包是 `"kind": "full"`，同樣寫這兩個數（它自己的資源當然落在區間內，自檢會驗）。數字一律由 `ok-extract --oklib resources-stamp --program` 印出來轉抄，**不准在 lua 裡寫死**——寫死就是第二個會忘記更新的地方。

**程式包裡不准有 `RESOURCES.json`**（自檢項）。否則覆蓋安裝時它會把玩家那份正確的資源版本蓋成錯的，閘就瞎了。

### 1.4 誰讀

| 讀的人 | 怎麼讀 | 失敗怎麼辦 |
|---|---|---|
| Rust `oklib::activate()` | 開庫時查一次，結果快取在 `Store` | **回 `Err`**，整條開卡路徑同一個錯誤訊息 |
| 讀卡器 / OK Studio（C++） | 啟動時 C ABI 查一次 | 常駐通知（§4） |
| 啟動器（`run_card_reader_development.lua`、OKStudio 那支、`StreetSocial.cmd` 走的 lua） | 啟動前跑 CLI | 主控台印訊息並 `pause`，不啟動遊戲 |
| 打包自檢 | `--program-only` 時對最近一個完整包跑一次 | 打包失敗 |

## 2. 比哪些檔：機器讀得到的子版本為主，人工整數為輔

### 2.1 人工整數只是快捷

`RESOURCES_MIN/MAX` 與 `RESOURCES.json` 的 `version` 的用途是「我知道這版不相容」的**宣告**，忘記 +1 就是靜默少件回來。所以閘**同時**比下面每一項，任一項不是這版程式認識的值就算不符，**不管 `version` 看起來多漂亮**。

下表是 e-cardload 拍板後的版本（2026-11-24）：

| id | 比什麼 | 等級 | 現在的值 |
|---|---|---|---|
| `resources_too_old` / `resources_too_new` | `RESOURCES.json` 的 `version` 落在 `[MIN, MAX]` | block | 3 |
| `no_resources_json` | `RESOURCES.json` 在不在 | block（開發樹例外，§7） | — |
| `oklib_version` | `base_v1/oklib.json` 的 `version` ∈ 程式的已知集合 | block | 2 |
| `mods_index_schema` | `mods_index.db` 的 `meta.schema` == `modsindex::SCHEMA` | block | C 樹 1 / E 樹 2 |
| `mods_index_missing` | `mods_index.db` 在不在 | block | — |
| `mods_index_foreign` | 玩家設了遊戲目錄，而索引裡**一個 archive 都對不上他的 `mods/`** | **warn** | — |
| `shared_mods_missing` | `shared_mods.txt` **存在**（不比內容） | block | — |
| `models_ignore_missing` | `models/.gitignore` **存在** | block | — |
| `sources_missing` | `sources.okidx` 與 `models/` 目錄**存在** | block | — |
| `selftest_failed` | 開庫、對一顆已知模型問一個已知查詢，答得出來 | block | — |

幾個「不進閘」與「改做法」的決定，理由記下來免得之後又想加回去：

- **`sources.okidx` 沒有版本欄位可讀**（只有 `.okmodel` 記錄有 `MODEL_MAGIC`，索引本身是整個重寫的二進位）。所以不假裝比版本，改成 `selftest_failed`：**實際開庫問一個已知查詢**，答得出來才算過。等它的格式真的動了、加上版本欄位，那時才進閘比版本。
- **`CARD_PACK_VERSION` 不進資源閘**。它是卡片（`okLc`）跟程式的事，不是資源包的事，而且開卡時本來就會直接報「card pack version N (expected M)」。要上畫面是走**開卡錯誤訊息**那條路，不要混進資源包檢查。（它還是會被釘在 §2.2 的常數指紋表裡。）
- **`shared_mods.txt` 不比內容指紋**。它的內容跟著「這台機器裝了哪些 mod」變，拿它當指紋會為了錯的理由變紅。只檢查**存在**：不存在的話 `okstrict` 不啟用，窄視圖整個失效（開卡 8.9 s → 1.9 s 那筆全賠回去）。
- **`models/.gitignore` 同理只檢查存在**：不存在會讓庫去替第三方 mod 的模型答題，那是**錯的答案**，比缺件更難查。
- **`meta.mods_dir` 和本機 mods 路徑不同，不算失敗**，但分兩種：玩家沒設遊戲目錄（打包版只開 OK 卡）＝完全正常，不要報；設了遊戲目錄而索引一個 archive 都對不上＝報 `mods_index_foreign`，**warn**。理由是現在的行為：`serves()` 比 `meta.mods_dir` 不中就退回「列一次樹，看索引認不認得其中任何一個 archive」，都不認得時 `tree_scan_forbidden` 放行，開卡回頭走整棵樹——慢，而且缺件的判斷會變得不準。它不該擋住只開 OK 卡的人，所以是 warn。

### 2.2 怎麼讓「改了格式卻忘了 +1」被擋下來

三道，都在 `cargo test`，不靠人記得：

1. **格式指紋表（Rust 測試釘死，只釘常數）**：`resources.rs` 的測試裡寫一張期望值表——`modsindex::SCHEMA`、`CARD_PACK_VERSION`、`oklib.json` 寫入時的 `version`、`RESOURCES_MIN/MAX` 自己。任何人改到其中一項，測試就紅，紅的訊息直說：

   ```
   資源包格式變了（mods_index_schema 2 -> 3）。
     若新程式配舊資源會開不了卡或靜默少件，請把 RESOURCES_MIN/MAX 一起 +1，
     再把這張表的期望值更新。若確定相容（舊庫照樣能用），只更新期望值，並在 commit 裡寫明為什麼相容。
   ```

   這道不自動判斷相容性——那沒辦法自動判斷——它只保證**沒有人能默默改掉格式**。
   **不要把 `shared_mods.txt` 樣板的 hash 釘進這張表**（理由同 §2.1：它跟著本機裝了哪些 mod 變，會為了錯的理由變紅）。

2. **`resources-check --selftest`**：對**現在這個庫**實際跑一次 §2.1 的全部檢查（含那個「開庫、問一個已知查詢」的 selftest），CI 與打包腳本直接用。抓的是另一種忘記：改了寫入端沒改讀取端（或反之），常數對了但庫實際上答不出東西。

3. **打包自檢（§6.2）**：`--program-only` 必須對最近一個完整包跑過 `resources-check` 才算打包成功。這是最後一道，抓的是「測試都綠、但現場那包資源就是配不上」。

### 2.3 一個未決但要記下的選項

更強的做法是讓 `RESOURCES.json` 不記人工整數，只記 `parts`，由程式自己判斷每一項認不認識——那樣就完全沒有「忘記 +1」。沒這樣做的原因是：有些不相容**不在上面任何一項裡**（例如模型檔的內部編碼換了，但 `oklib.json` 的 version 沒動），那時人工整數是唯一的表達方式。所以兩者都留，人工整數當逃生門。

## 3. 介面

### 3.1 CLI

```powershell
.\Tools\ok-extract\target\release\ok-extract.exe --oklib resources-check .\Content\IndependentResources\base_v1 [--want-min N --want-max N]
```

- 退出碼：0 相容（只有 warn 也算 0，但 JSON 裡有 `problems`）；2 有 `block`；1 自己壞了（路徑不對、JSON 讀不了）。
- stdout 是 JSON（下面那個形狀），stderr 是人看的繁體中文摘要；`--quiet` 只給 JSON。
- `--want-min/--want-max` 覆寫程式自己的區間，給驗收與測試用。
- 另外：`resources-stamp`（給打包腳本抄的那些值，`--program` 印程式這側的區間）、`resources-check --selftest`（§2.2）。

### 3.2 JSON

```json
{
  "ok": false,
  "resources": { "version": 2, "package": "Studio-20261123-release-b", "made": "2026-11-23T…",
                 "parts": { "oklib_version": 2, "mods_index_schema": 1, "has_shared_mods": true } },
  "program": { "min": 3, "max": 3, "commit": "b8d394043" },
  "problems": [
    { "id": "mods_index_schema", "level": "block",
      "what": "mod 索引是舊格式（schema 1），這版程式要 schema 2。卡片指名的第三方 mod 會查不到，那些部件不會穿上。",
      "fix": "本機有遊戲的話，在安裝資料夾執行下面這行重建索引；沒有遊戲就下載新的完整包。",
      "fixable_locally": true,
      "command": "Tools\\ok-extract\\target\\release\\ok-extract.exe D:/KoikatuSunshine --oklib mods-index Content\\IndependentResources\\base_v1" }
  ]
}
```

`problems[].id` 由 e-cardload 定死這一組，之後只增不改（`library_missing` 併進 `sources_missing`／`no_resources_json`，`card_pack_version` 與 `shared_mods_fingerprint` 依 §2.1 不在資源閘裡）：

`resources_too_old`、`resources_too_new`、`no_resources_json`、`oklib_version`、`mods_index_schema`、`mods_index_missing`、`mods_index_foreign`、`shared_mods_missing`、`models_ignore_missing`、`sources_missing`、`selftest_failed`。

每項帶 `what`／`fix`／`fixable_locally`／`command`，文案繁體中文。

### 3.3 level 兩級

- `block`：擋開卡。上面除 `mods_index_foreign` 以外的全部。
- `warn`：不擋，只在畫面上掛通知。**目前只有 `mods_index_foreign`**（它不該擋住只開 OK 卡的人）。

`warn` 的存在有風險（它也可能讓缺件判斷不準），所以規則寫死：**`warn` 只能用在「程式讀得懂全部格式，而且照常開得了 OK 卡」的情況**；任何「程式讀不懂」或「庫會給出錯的答案」（缺 `shared_mods.txt`、缺 `models/.gitignore`）都是 `block`。新增 `warn` 要在這份文件裡加一行理由。

### 3.4 C ABI

照 `ok_card_absent_mods` 的 capacity 慣例（不是回 `const char*` 讓呼叫端釋放）：

```c
/// 把 §3.2 的 JSON（UTF-8）寫進 out，最多 cap 位元組；回需要的長度。lib 為 NULL 時查目前設定的基礎庫。
int ok_resources_check(const char* lib_utf8, char* out, int cap);
```

C++ 那側 `FOkSession::ResourcesCheck(FString& OutJson)`，再由 `UOKCharacterController` 與 OK Studio 各自呈現。`activate()` 的擋是 Rust 自己做的，C++ 這支只為了「畫面上要講什麼」。

## 4. 擋到什麼程度、畫面上怎麼顯示

### 4.1 擋的範圍

| 動作 | 不符（block）時 |
|---|---|
| 遊戲／讀卡器／Studio 啟動 | **可以**。擋在啟動＝玩家只看到一個關掉的窗，問不出原因 |
| 進主畫面、看卡片牆、翻設定頁 | **可以**。卡片牆列檔名不需要開庫 |
| 開卡（原作卡、OK 卡，讀卡器／Studio／MCP／CLI／mod 都算） | 有 `block` 就**擋**。`oklib::activate()` 回 `Err`，錯誤訊息就是 §3.2 的 `what` + `fix`；只有 `warn` 時照開 |
| 開 Studio 場景 | 場景裡有角色就會走開卡，於是被同一條擋下；沒有角色的場景照開 |
| 轉卡、封卡、重建索引（`--oklib mods-index` 之類） | **不擋**。它們就是修法本身 |

不符時沒有「先開了再提示」。要讓這件不可能，擋點在 Rust 開庫處而不在 UI：讀卡器、Studio、MCP、CLI、任何 mod 走的都是 `activate()`。

開發用逃生門：`OK_RESOURCES_CHECK=off`。要求（寫進文件）：每次開卡都在 log 印一行「相容性閘已關閉，這次開卡可能靜默少件」；打包自檢要驗**任何 `.cmd`／啟動 lua 都沒有設這個變數**。

### 4.2 啟動器（主控台）

`run_card_reader_development.lua` 與 OKStudio 那支，在啟動前跑 CLI；不符就印繁體中文訊息並 `pause`，不啟動遊戲。

注意 `.cmd` 必須維持純 ASCII（主控台 code page 65001 下 cmd 會誤讀非 ASCII 行），所以**中文訊息一律由 lua／exe 印**，不要寫進 `.cmd`。

### 4.3 遊戲內

沿用 `CheckAbsentMods`（`OKGalleryWidget.cpp`，2026-11-24）那套，不另做一份：

- 檢查在 worker 上跑，掛 `OKBusy::Begin(TEXT("檢查資源包版本"))`——專案規矩是超過 0.5 秒的 UI 動作都要有進度條，雖然這次通常是毫秒級（讀一個 JSON＋一個 SQLite meta），不要為了快就省掉。
- `block`：`ScreenNote` 用紅色、**不自己消失**（秒數給很大值，key 固定，重查會取代同一則），`InspectorText` 寫完整的 `what` + `fix` + 指令。**不給關閉鈕**：關掉它就等於回到「畫面什麼都沒說」，而使用者的標準正是不要那樣。
- `warn`：黃色、不自己消失，但**可以按一次收起**（它不擋功能，長駐紅字會讓真正的 `block` 失去份量）。
- 按下開卡時再講一次原因（開卡失敗的錯誤訊息就是同一段文字），不要只靠上面那則通知。
- 版面：訊息會有四五行，照 `CheckAbsentMods` 的做法多行塞進 `ScreenNote` 與 Inspector，不另開對話框。

### 4.4 文案

原則：先講玩家會看到什麼後果（哪件事會壞），再講怎麼修，指令可以直接複製。不丟 GUID、不丟 schema 號碼當主詞。

資源太舊、本機補不了：

```
資源包太舊，這版程式開不了卡。
  程式需要資源版本 3，這台裝的是 2（Studio-20261123-release-b，2026-11-23）。
  請下載完整包 Studio-20261124-release-e，或至少它的資源部分，解壓覆蓋到安裝資料夾。
```

程式太舊（§1.1 新增的那個方向）：

```
資源包比程式新，這版程式讀不懂。
  這台的資源是版本 4，程式只懂到 3（程式包 Studio-20261124-release-e）。
  請下載新的程式包覆蓋安裝；資源包不用再下載一次。
```

只是索引要重建、本機有遊戲：

```
mod 索引是舊格式（schema 1），這版程式要 2。卡片指名的第三方 mod 會查不到，那些部件不會穿上。
  本機有遊戲的話，在安裝資料夾執行：
  Tools\ok-extract\target\release\ok-extract.exe D:/KoikatuSunshine --oklib mods-index Content\IndependentResources\base_v1
  沒有遊戲就下載新的完整包。
```

索引不是這台的遊戲建的（`mods_index_foreign`，warn）：

```
mod 索引不是這個遊戲目錄建的，開原作卡會慢，而且「缺哪些 mod」可能列不準。
  OK 卡不受影響，照開。
  要修就重建一次索引：
  Tools\ok-extract\target\release\ok-extract.exe D:/KoikatuSunshine --oklib mods-index Content\IndependentResources\base_v1
```

## 5. 覆蓋安裝的兩個現場問題

### 5.1 舊 `.stage` 的清理

兩種現場差很多，文件要分開寫：

- **玩家的安裝資料夾裡沒有 junction**。`package_street_social.lua` 的註解寫得很清楚：「The stage keeps its game files; its junctions into Content are not copied」。所以玩家那邊刪舊 stage 資料夾是安全的普通刪除。
- **開發樹的 `Saved/StreetSocial/Build/*.stage` 裡有 junction**（`stage_interaction_runtime.lua` 建的，指向 base 與 `Content/IndependentResources`）。那邊**永不遞迴刪除**，這是本專案踩過的坑。

程式包帶新的 `.stage`，和舊的並存，啟動器挑 `staged_at` 最新的；舊 stage 不會自己消失，所以：

1. `OK_STUDIO_MOD_PACKAGE.md` 要寫明「舊 stage 不刪也能用，只是磁碟會長（每份約 1 GiB）」，給出可以手動刪哪個資料夾。
2. 提供 `Tools\lua\lua.exe Tools\prune_stages.lua --keep 1`（新腳本，實作時寫），規則寫死：
   - 只動 `Saved/StreetSocial/Build/` 底下的 `*.stage`；
   - 刪之前**先掃 reparse point**（`fsutil reparsepoint query`，或 lfs 的屬性），遇到就先 `cmd /c rmdir <link>` 解掉連結（`street_stage.lua` 已經是這個做法），**解完才遞迴刪**；掃到任何一個解不掉就整個放棄並印出是哪個；
   - 預設 `--dry-run`，要刪得明講；
   - 保留目前最新那份與正在跑的那份（exe 被鎖就跳過並講）。
3. 開發樹上預設**不跑**這支：C／E／F 共用，別人的 stage 可能架在同一個 base 上。文件寫「開發樹要清就自己確認過再跑」。

### 5.2 `Tools/` 的 exe 正在跑

`ok-game-mcp`、`ok-character-mcp` 這些 MCP server 可能正在跑，覆蓋會失敗（Windows 不准覆寫正在執行的 exe）。現成的解法在 `package_studio_release.lua` 第 163–169 行就有：**正在跑的 exe 不能覆寫，但可以改名**；改名讓它繼續從新名字跑，原位置就空出來可以寫。

所以程式包不要用「解壓縮覆蓋」當唯一說法，附一支安裝腳本 `Tools\install_program_update.lua`（由程式包裡的 `InstallProgramUpdate.cmd` 呼叫，`.cmd` 保持 ASCII）：

1. 先列出會被換掉的檔；
2. 每個檔先試直接覆寫；失敗就把目標改名成 `<名字>.old-<時間戳>` 再寫新的，接著試刪舊的——刪不掉就留著，並記一行「這支還在跑，舊檔留著下次開機再清」；
3. 一個都寫不進去（整個資料夾被鎖、權限不對）就停下來，講人話：

   ```
   有程式還在執行，更新沒有完成。
     還在跑：ok-game-mcp.exe、ok-character-mcp.exe
     請關掉遊戲、OK Studio 與讀卡器，以及連著它們的 AI 工具，再執行一次 InstallProgramUpdate.cmd。
   ```

4. 收尾再跑一次 `resources-check`，印結果；不符就照 §4.4 講。

安裝腳本**不自己殺行程**。這台機器上三棵樹、多個 session 共用那些 exe，殺別人的東西是另一類災難。

## 6. 落地的改動清單與自檢

### 6.1 要改哪裡

| 檔 | 改什麼 | 誰 |
|---|---|---|
| `Tools/ok-extract/src/resources.rs`（新） | `RESOURCES_MIN/MAX`、`resources_check(lib, min, max) -> JSON`、格式指紋表測試 | **e-cardload**（已接；它手上的開卡優化做完就寫） |
| `Tools/ok-extract/src/oklib.rs` | `activate()` 擋；`resources-check` / `resources-stamp` / `--selftest` 子命令 | 同上 |
| `Tools/ok-extract/src/ffi.rs` | `ok_resources_check(lib, out, cap)` | 同上 |
| `Tools/package_street_social.lua` | 完整包寫 `RESOURCES.json`；`PACKAGE.json` 的 `kind` 與 `requires_resources_min/max`（值從 `resources-stamp` 抄） | MOD 框架 session |
| `Tools/package_studio_release.lua` | `--program-only` 的新自檢（§6.2） | 同上 |
| `Tools/prune_stages.lua`（新） | §5.1 的安全清理 | 同上 |
| `Tools/install_program_update.lua`（新）＋`InstallProgramUpdate.cmd` | §5.2 | 同上 |
| `Tools/run_card_reader_development.lua`、OKStudio 啟動器 | 啟動前檢查、不符就印訊息並 `pause` | 同上 |
| `Source/OpenKoikatsu/OKGalleryWidget.cpp`／`OKCharacterController.h`、OK Studio | 啟動時查、`OKBusy`、`ScreenNote`、開卡時再講 | 同上 |
| `Docs/OK_STUDIO_MOD_PACKAGE.md` | 玩家怎麼裝程式包、舊 stage、exe 正在跑 | 同上 |

### 6.2 打包自檢新增

- 程式包裡**沒有** `RESOURCES.json`、沒有 manifest 列的任何檔、沒有卡片、沒有 HairDeck 權重。
- 程式包裡任何 `.cmd` 與啟動 lua **沒有** `OK_RESOURCES_CHECK`。
- `PACKAGE.json` 的 `requires_resources_min/max` 等於 `ok-extract --oklib resources-stamp --program` 印的值（不是 lua 寫死的）。
- 對 `--resources-from <完整包資料夾>`（預設找最新的 full 包）跑一次 `resources-check`，退出碼必須 0；不通過就打包失敗，訊息說「要先發新的完整包」。
- 完整包：`RESOURCES.json` 的 `parts` 等於包裡實際檔案讀出來的值（防打包腳本抄錯）。

## 7. e-cardload 的拍板（2026-11-24）與還沒定的那一條

已拍板，§1～§3、§6、§8 都照它改過。和原稿的差別，列出來免得之後有人照舊稿實作：

| 原稿 | 拍板後 |
|---|---|
| 常數放 `resources_version.rs` | 放 `resources.rs`，常數與檢查同一個檔，由 e-cardload 維護 |
| 比 `sources.okidx` 的版本欄位 | **它沒有版本欄位**；改成 `selftest_failed`（開庫問一個已知查詢） |
| `CARD_PACK_VERSION` 進閘 | **不進**資源閘（那是卡片跟程式的事，開卡已經會報錯）；只釘在常數指紋表裡 |
| `shared_mods.txt` 比內容指紋 | **只比存在**（內容跟著本機裝了哪些 mod 變，比指紋會為了錯的理由變紅） |
| `models/.gitignore` 存在性 | 不變，另加 `sources.okidx` 與 `models/` 的存在性 |
| `meta.mods_dir` 不同一律不報 | 玩家**設了**遊戲目錄而索引一個 archive 都對不上 → 報 `mods_index_foreign`（warn） |
| 欄位叫 `severity` | 叫 `level` |
| C ABI 回 `const char*` | 照 `ok_card_absent_mods` 的 **capacity 慣例** |
| 指紋表含 `shared_mods.txt` 樣板 hash | **只釘常數** |

**還沒定的一條（我在送出問題之後才看出來，要再問它）**：三組的開發樹庫是本機從遊戲轉的，旁邊**沒有 `RESOURCES.json`**，照字面規則 `no_resources_json` 是 `block`，那就是三組都開不了卡。我提的規則是「庫旁邊沒有 `RESOURCES.json` 時只比子版本、不比人工整數，且 `no_resources_json` 在開發樹不算 block；用庫的上面有沒有 `.git` 與 `Tools/base_library_shared_mods.txt` 分辨開發樹」。這條定錯的代價最大（§9 第一項），所以**實作前要它點頭**。

## 8. 怎麼驗這個閘真的有效

全部在一個**完整包的複本**上做（不要動本機開發樹的 `base_v1`），每項都要看三件事：擋不擋、訊息對不對、`resources-check` 的退出碼對不對。

| # | 人造情境 | 預期 |
|---|---|---|
| 1 | 不動任何東西（對照組） | 退出碼 0；讀卡器開原作卡與 OK 卡都正常；畫面沒有通知 |
| 2 | `RESOURCES.json` 的 `version` 改成 2（比程式舊） | 退出碼 2；啟動器印「資源包太舊」並 `pause`；畫面紅字常駐；開卡被擋 |
| 3 | `version` 改成 9（比程式新） | 退出碼 2；訊息是「請更新**程式**」（不是叫人更新資源） |
| 4 | 刪掉 `RESOURCES.json` | 退出碼 2；`no_resources_json`；訊息講「這份資源包太舊，沒有版本記錄」 |
| 5 | `mods_index.db` 的 `meta.schema` 改回 1 | 退出碼 2；訊息給出重建指令；開卡被擋（**不是**開了然後少件） |
| 6 | 刪掉 `mods_index.db` | 退出碼 2；`mods_index_missing`；指令同上 |
| 7 | `oklib.json` 的 `version` 改成 9 | 退出碼 2；`oklib_version` |
| 8 | 刪掉 `shared_mods.txt` | 退出碼 2；`shared_mods_missing`；開卡被擋（不是變慢後少件） |
| 9 | 刪掉 `models/.gitignore` | 退出碼 2；`models_ignore_missing` |
| 10 | 設一個**別台機器**的遊戲目錄（索引一個 archive 都對不上） | 退出碼 **0**、level `warn`、`mods_index_foreign`；**OK 卡照開**；黃字通知、可收起 |
| 11 | 把 `sources.okidx` 改名（selftest 失敗） | 退出碼 2；`sources_missing` 或 `selftest_failed` |
| 12 | 情境 5 加上 `OK_RESOURCES_CHECK=off` | 卡開得起來；log 每次開卡都印「相容性閘已關閉」 |
| 13 | 情境 2 的複本上跑 `--program-only --resources-from <該複本>` | 打包失敗，訊息說要先發新的完整包 |
| 14 | 把 `modsindex::SCHEMA` 改成 3 但不動 `RESOURCES_MIN/MAX` | `cargo test` 紅，訊息就是 §2.2 那段 |
| 15 | 在**開發樹**（庫旁邊沒有 `RESOURCES.json`）跑一次 | 退出碼 0；讀卡器照常開卡（§7 那條定了才驗） |

情境 5 是整件事的核心：**今天這一條就是靜默少件的實際路徑**，所以它必須從「畫面只說已加载3D」變成「開卡被擋並講清楚」。驗的時候要用一張**指名第三方 mod 的原作卡**（例如伊莉雅那張，它缺 `kiyoubi. illya` 時會少件），不要用只用原作資源的卡——那種卡不問索引，驗不到東西。

另外要驗一次「訊息到得了玩家」：情境 2 下從 `.cmd` 啟動（不是從開發樹啟動），確認主控台的中文沒有因為 code page 變成亂碼（§4.2）。

## 9. 風險

- **共用程式碼**：`Tools/ok-extract`、`Plugins/`、`Source/` 是 C／E／F 三組共用。`activate()` 多一個 `Err` 路徑會影響三組所有開卡的程式。要求：改動進去前，除了 `cargo check --release` 與 `--no-default-features`，實際建置 `OpenKoikatsu` Win64 Development 與 `OpenKoikatsuEditor` 並確認連結成功。另外三組各自的開發樹**沒有** `RESOURCES.json`（庫是本機從遊戲轉的），所以**開發樹必須照常能開卡**——這是最容易做壞的一點：規則定為「庫旁邊沒有 `RESOURCES.json` 時，只比子版本，不比人工整數，且 `no_resources_json` 在**開發樹**不算 `block`」。怎麼分辨開發樹：庫的上面有 `.git` 與 `Tools/base_library_shared_mods.txt`（打包版沒有 `.git`）。**這一條要和 e-cardload 一起定死**，定錯就是三組都開不了卡。
- **誤擋的代價**：閘誤擋等於所有人開不了卡。所以 `block` 的每一項都要能在五秒內用 `resources-check` 的 JSON 看出原因，並且逃生門（`OK_RESOURCES_CHECK=off`）要真的能用。
- **warn 會被習慣性忽略**：長期掛著黃字就沒人看。`warn` 的清單要保持很短（現在兩項），新增要在這份文件裡寫理由。
- **`.cmd` 的編碼**：中文一律由 lua／exe 印，`.cmd` 保持純 ASCII。
