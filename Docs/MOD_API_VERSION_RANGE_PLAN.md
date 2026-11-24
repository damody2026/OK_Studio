# mod API 版本區間與程式包更新（方案，2026-11-24）

**範圍**：只更新程式之後，玩家裝的 mod 還能不能載入，載不進去時誰講、怎麼講，以及 mod 留在卡與存檔裡的資料怎麼辦。不含 mod 框架本身（[OK mod 框架](OK_MOD_FRAMEWORK_PLAN.md)）、資源包的閘與格式紀律（[相容性閘](RESOURCE_PROGRAM_COMPAT_GATE_PLAN.md)、[資源包格式凍結](RESOURCE_PACK_FREEZE_PLAN.md)）。

標準同前兩份：**寧可擋下來講清楚，也不要靜默少件**。mod 版的靜默少件是：玩家更新程式，mod 安靜不見，他以為是遊戲壞了。

## 0. 現況比預期完整，缺的是三條

已經有的（`Tools/ok-mod`）：

- `ok-mod-api` 的 `API_VERSION`（crate 版本，`mod.toml` 的 `api = "0.1"` 比對它的 major.minor）與 `ABI_VERSION = "0.1.0"`（abi_stable 載入時比的那個，故意分開）。
- 區間語意**已經寫好了**：`api_compatible`（`host/src/manifest.rs:83`）——1.0 之後同 major、host 可以較新；**0.x 期間每個 minor 都是破壞性**。
- prefix struct 只准往後長、會長變體的 enum 用 `NonExhaustive`，所以「加東西」本來就不必抬版本（`api/src/lib.rs` 的 compatibility rules）。
- 拒絕的理由留著：`Verdict::Reject("needs ok-mod-api 0.2, this host has 0.1")` → `State::Rejected(why)`（`host/src/lib.rs:238`）。
- `obsolete.toml`：核心知道該退場的 mod，`ok-mod-pack install` 拒裝、`verify` 搬到 `Mods/.old/` 並附理由。

缺的是三條，都在「程式包更新」這個情境上。

## 1. 什麼時候准抬 `ok-mod-api`

0.x 的每個 minor 都把玩家裝的 mod **全部**踢掉，而程式包更新正好就是會動 `ok-mod-api` 的時機。所以要有政策，而且和資源包那條同一條紀律：

1. **加 prefix 欄位、加 NonExhaustive 變體不抬 minor**，這兩種本來就相容——這是日常該走的路。
2. **要抬 minor，等於宣布「現有 mod 全部要重編」**。抬的人在這份文件裡留下日期、理由，以及使用者同意的紀錄。沒有紀錄不准抬。
3. **`ABI_VERSION` 同理，而且更嚴**：它一變，連重編都救不了舊 DLL（abi_stable 直接拒載）。
4. **到 1.0 之前就先照 1.0 的紀律走**：host 接受 `wanted.1 <= host.1`。`api_compatible` 現在在 major 為 0 時要求完全相等，這是保守的正確做法，但代價是每次 minor 都清場。建議的折衷：保留這個行為，靠第 1 條讓 minor 幾乎不必動，而不是放寬比對——放寬比對會讓真的破壞性改動靜默載入，那比清場糟。
5. **`PACKAGE.json` 記下這個程式包帶的 `ok_mod_api` 與 `ok_mod_abi`**（由 host 印出來轉抄，不在 lua 裡寫死，理由同閘 §1.3）。mod 作者和自動化查得到，玩家也看得到自己手上這版吃哪個。

## 2. 玩家看到什麼

`needs ok-mod-api 0.2, this host has 0.1` 是給開發者看的。程式包更新後第一次啟動要發生的事：

- **主詞是 mod 的名字，不是版本號**：「〈mod 名稱〉是給舊版遊戲做的，這一版載不進來，要等作者出新版。」
- **列在畫面上，不可省略**。沿用閘 §4 那套常駐通知：**warn 級**，黃字、可關掉。少一個 mod 不是資料錯誤，不該 block 整個遊戲——但也不准只寫在 log 裡。
- **一次講完**：被拒的 mod 一起列，不是一個一條。
- 讀卡器的 mod 頁（`OKReaderMods.cpp` / `OKReaderModPage.cpp`）要能看到每個 mod 的狀態與理由（`State::Rejected(why)` 已經有這個資料，要接到畫面）。
- `obsolete.toml` 搬走的那些，理由也走同一個地方顯示，別讓玩家只在 `Mods/.old/` 裡發現自己的 mod 不見了。

## 3. mod 留在卡與存檔裡的資料

`host/src/card.rs:122` 的 section 帶 `requires: {id, version}`：mod 被拒之後，它寫進卡／存檔的那段資料還在。

規則：

1. **原樣保留，不解讀、不丟棄**。卡和存檔的寫回路徑要照抄（這條要有測試：載入→不載 mod→存回，那段 bytes 不變）。
2. **講一句**：「這張卡有一段資料來自沒有載入的 mod，已經保留。」玩家把 mod 裝回來就該原狀恢復。
3. 這和存檔那份的「靜默丟棄」是同一個病（[卡與存檔版本](CARD_AND_SAVE_VERSION_PLAN.md) §2.2），所以 `deny_unknown_fields` 若要加，**不能加在會吃到 mod section 的那一層**，否則裝了 mod 的存檔在沒裝 mod 的機器上就開不了。這條要和那份一起看。

## 4. 要改哪裡

| 檔 | 改什麼 | 誰 |
|---|---|---|
| `Tools/ok-mod/api/src/lib.rs` 的文件註解、這份文件 | 抬 minor 的政策與紀錄欄 | mod 框架那組 |
| `Tools/ok-mod/host/src/ffi.rs` | 把每個 mod 的狀態與理由（含 `Rejected`）吐成給畫面用的清單 | mod 框架那組 |
| `Source/OpenKoikatsu/OKReaderMods.cpp`、`OKReaderModPage.cpp`、OK Studio 對應處 | 啟動時的常駐通知（warn 級）與 mod 頁的狀態欄，文案照 §2 | 讀卡器／F 組 |
| `Tools/ok-mod/host/src/card.rs`、存檔寫回路徑 | 未載入 mod 的 section 原樣保留，加測試 | mod 框架那組 |
| `Tools/package_*.lua` | `PACKAGE.json` 寫 `ok_mod_api`、`ok_mod_abi`（轉抄 host 印的） | MOD 框架那組 |

## 5. 驗收

1. 把一個 mod 的 `mod.toml` 改成 `api = "0.2"`（host 是 0.1）：遊戲照常啟動，畫面上列出這個 mod 的名字與理由，mod 頁看得到狀態，log 不是唯一的出口。
2. 同一個 mod 先裝好、存一次檔（讓它寫下自己的 section），再把它改成不相容：載入→存回，那段 bytes 原封不動；畫面講了「有一段資料來自沒載入的 mod」。
3. 把 mod 裝回相容版本：那段資料恢復作用（和第 2 步存檔前逐欄比）。
4. `obsolete.toml` 命中的 mod：搬到 `Mods/.old/`，畫面上講了理由，不是只有資料夾裡少一個檔。
5. 程式包的 `PACKAGE.json` 有 `ok_mod_api` 與 `ok_mod_abi`，和 host 自己印的相同（打包自檢比一次）。
6. 五個被拒的 mod：畫面上一次列完，不是五條通知。

## 6. 風險

- **放寬 `api_compatible` 的誘惑**。看起來能少清幾次場，實際上是讓破壞性改動靜默載入，然後在某個 mod 的某個呼叫上崩掉或給錯答案。寧可清場，清場是看得見的。
- **warn 疲勞**。mod 的通知和資源閘的通知是同一塊畫面；兩邊都愛講就都沒人看。mod 這邊只在**狀態變了**的那次啟動講（記在本機，不在資源包裡），之後只留在 mod 頁。
- **`ABI_VERSION` 一動連重編都救不了舊 DLL**，而玩家分不出 API 和 ABI。文案不要提這兩個詞，只講「要等作者出新版」。
- **共用程式碼**：`Tools/ok-mod` 與 `Source/` 是 C／E／F 三組共用，改完要 `cargo check --release`（Rust 另跑 `--no-default-features`）並實際連結 `OpenKoikatsu` Win64 Development 與 `OpenKoikatsuEditor`。
