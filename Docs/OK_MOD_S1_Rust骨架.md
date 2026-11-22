# OK Mod 工作項 1：Rust 骨架（2026-11-23，F 組）

對應 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §15.4 第 1 列（M0 的 Rust 部分）。只動了新目錄 `Tools/ok-mod/` 與 `.gitignore`，沒有碰 `Tools/ok-extract`、`Plugins/`、`Source/`，所以這一項不需要建 Unreal。

## 做了什麼

`Tools/ok-mod/` 是一個 Cargo workspace：

| crate | 位置 | 內容 |
|---|---|---|
| `ok-mod-api` 0.1.0 | `api/` | 跨 DLL 的型別，只有型別：`OkMod`／`OkModRef`（RootModule）、`HostApi`／`HostApiRef`（宿主給 mod 的函式表，prefix 結構）、`ModInstance`（`sabi_trait`：`register`、`on_event`、`shutdown`）、`Event`／`Reply`／`Declaration`／`ConfigValue`（都是 `NonExhaustive`）、`ModError`、`BuildInfo`、`LogLevel`、`ModHandle` |
| `ok-mod-sdk` 0.1.0 | `sdk/` | mod 作者用：`Mod` trait、`Host`（log、讀寫自己的設定項）、`Registrar`（宣告設定項、指令、訂閱事件）、`ok_mod!` 巨集 |
| `ok-mod-host` 0.1.0 | `host/` | `cdylib`（`ok_mod_host.dll`，給 UE）＋ `rlib`（給 ok-extract CLI）：發現 `Mods/*/mod.toml`、解析、依賴排序、abi_stable 載入、分派、panic 停用、設定存檔、`okm_*` C ABI |
| `hello` | `examples/hello/` | 範例：啟用時寫 log、一個設定項 `greeting`、主控台指令 `mod.org.openkoikatsu.hello.ping`、訂閱 `mode_enter`／`mode_exit`；附 `locale/zh-CN`、`locale/en` |
| panic 測試 mod | `fixtures/panic-mod/` | 依環境變數 `OK_MOD_TEST_PANIC_AT` 在 `create`／`register`／`enabled`／`mode_enter`／`command` 故意 panic |
| 版面不符測試 mod | `fixtures/bad-layout/` | 自稱 `ok_mod` ABI 0.1.0，但 `OkMod.create` 簽名不同 |

C ABI 標頭：`Tools/ok-mod/host/include/ok_mod_host.h`，照 `ok_rules.h` 的寫法：

- `okm_abi_version`（= 1）、`okm_open(config_json, log_fn, user)`、`okm_dispatch(host, request_json)`、`okm_free`、`okm_last_error`、`okm_close`；
- `okm_dispatch` 的請求：`list`、`event`（`mode_enter`／`mode_exit`）、`command`（`mod.<id>.<name>` 或 mod＋name）、`config`、`config_set`、`disable`，格式寫在標頭註解；
- 每個函式都包 `catch_unwind`，不會把 panic 傳回 C++。

### 設計上的決定（給協調者定 0.1 時參考）

1. **abi_stable 版本字串與 crate 版本分開**。abi_stable 在 0.x 的相容規則是「minor 相同、而且宿主的 patch ≤ mod 的 patch」（`VersionNumber::is_compatible`）。若直接用 crate 版本（`package_version_strings!`），宿主升到 0.1.1 就會拒載所有用 0.1.0 編的舊 mod，方向和我們要的（新宿主載舊 mod）相反。所以 `OkModRef::VERSION_STRINGS` 固定用 `ok_mod_api::ABI_VERSION = "0.1.0"`，只在破壞性改動時改 minor；附加欄位、附加事件靠 abi_stable 的版面檢查（prefix 結構可加尾欄位、NonExhaustive 可加 variant）。`mod.toml` 的 `api = "0.1"` 另外做一次人看得懂的檢查（0.x 要 major.minor 相同；1.x 起同 major、mod 的 minor ≤ 宿主）。
2. **mod 不必直接相依 abi_stable**。abi_stable 的 `#[export_root_module]` 產生的程式碼寫死 `::abi_stable::` 路徑，mod crate 不直接相依就編不過。`ok_mod!` 改成自己展開同樣的 `LibHeader` 靜態，匯出名用 `#[export_name = "_1as_0lib_1header_0root_bmodule_bloader"]`（abi_stable 的 `ROOT_MODULE_LOADER_NAME`），SDK 有測試比對這個名字。
3. **panic 隔離在 SDK**：abi_stable 自己的 `sabi_trait` 跨界 panic 會 abort，所以 SDK 的 `Adapter` 把 `create`／`register`／`on_event`／`shutdown` 都包 `catch_unwind`，panic 變成 `ModError{kind: PANIC}`，而且 adapter 會記住「已中毒」，之後一律回 `POISONED`。SDK 在 mod 的 DLL 內裝自己的 panic hook（每個 cdylib 有自己的 std），把訊息與位置記下來而不是寫 stderr，所以宿主的停用原因有檔名行號。宿主收到 PANIC／POISONED 就把 mod 標成 `faulted`、從登記表移除、`mem::forget` 掉 instance（壞掉的 mod 連解構子都不叫）。
4. **`panic = "abort"` 編的 mod 拒載**：`BuildInfo.panic_unwind` 由 SDK 用 `cfg!(panic = "unwind")` 填。
5. **DLL 與 `mod.toml` 對照**：`ok_mod!` 把 crate 旁的 `mod.toml` 編進 DLL，宿主比對 id 與版本，不符就拒載。
6. **錯誤種類用 `ModErrorKind(u8)` 加常數**，不用列舉，加新種類不改版面。
7. **設定項**：型別 bool／int／float／text／hotkey，int／float 有範圍；宿主存在 `config_dir/<id>.toml`（UE 端會給 `UserData/config/mods`），寫入用暫存檔＋rename；讀到型別或範圍不符的舊值就用預設並寫警告。mod 在 `create` 時還沒宣告設定項，讀不到值；`Enabled` 事件起才讀得到。
8. **解析規則**：同 id 只留最新版；`targets` 不含目前模式→略過；`api` 不符、`incompatible` 命中（宣告的那個不載）、缺依賴或版本不符（連鎖）、載入順序循環（循環內的拒載，依賴它們的也拒載）→拒載並寫原因；`dependencies`、存在的 `optional_dependencies`、`load_order.after` 排前面，`load_order.before` 排後面，同層依 id 排序。
9. **文字 id 前綴**：設定項與指令的 `description_id` 不是 `mod.<id>.` 開頭時，宿主寫警告但不拒載（i18n 併表在工作項 6 之後才有）。
10. 每個 mod 每次呼叫都在宿主選的執行緒（`ModInstance: Send`，不要求 `Sync`）；mod 呼叫宿主的回呼（log、config）不會碰宿主主鎖，不會死鎖。

### 這次沒做、留給後面的

- `mod.toml` 的 `sha256` 只解析不驗證（工作項 12 的 `ok-mod-pack` 填與驗）；`Mods/profiles/` 目前被略過不當 mod，profile 也是 12；
- i18n 併表、`okMx`、Character／UI／Studio 掛點都還沒有（照 §15.4 的分工在 6、7、8 之後）；
- `okm_*` 只有 `list`／`event`／`command`／`config`／`config_set`／`disable`，UE 側的主控台指令登記、`-NoMods`、`mod_call` 是工作項 6。

## 驗了什麼

在 `F:\OpenKoikatsu\Tools\ok-mod` 跑（`-j 8`）：

- `cargo test -j 8`：全部通過。宿主單元測試 7 個（manifest、api 規則、依賴／重複／循環／不相容／玩家停用、設定檢查與存讀檔），SDK 1 個（匯出名），整合測試 `host/tests/load.rs` 7 個：
  - `hello_loads_answers_and_keeps_config`：hello 載入、log 有「hello from hello」、`ping` 回 `pong 1 (hello)`、`mode_enter` 只送給訂閱者、型別不符的設定被拒、改設定後重開宿主（換成 studio 模式）值還在；
  - `panic_disables_only_that_mod`：panic 在 `command`／`create`／`register`／`enabled`／`mode_enter` 五處，panic mod 都變 `faulted`（原因含「deliberate panic in …」與 panic 位置），hello 照常回應，faulted 的 mod 之後不再被叫；
  - `incompatible_dlls_are_refused`：版面不符（abi_stable 拒絕，原因「not a compatible ok_mod DLL」）、`api = "0.2"`、DLL 與 `mod.toml` 的 id 不符、DLL 不存在，四種都拒載，hello 不受影響；
  - `panic_abort_build_is_refused`：用 `--config profile.dev.panic="abort"` 編的 hello 被拒；
  - `mods_from_other_rustc_versions_load`：宿主用 rustc 1.97.1（預設）編，hello 與 panic mod 分別用 **rustc 1.92.0** 與 **rustc 1.98.1** 編（`rustup run <版本> cargo build`），都能載入、`ping` 正常、panic 隔離正常；狀態裡的 `rustc` 欄位顯示 `rustc 1.92.0 (ded5c06cf 2025-12-08)`、`rustc 1.98.1 (48a229cea 2026-09-01)`；
  - `no_mods_and_disabled_and_wrong_target`：`no_mods` 時清單為空；玩家停用與 `targets` 不含目前模式都是 `skipped`；
  - `c_abi_round_trip`：經 `okm_open`／`okm_dispatch`／`okm_free`／`okm_last_error`／`okm_close` 走一遍全部請求，log 回呼收到 hello 的訊息與 panic mod 的停用訊息（level 1）。
- `cargo build -j 8 --release`：產出 `target/release/ok_mod_host.dll`（約 1.6 MB）、`ok_hello.dll`；`objdump -p` 確認宿主匯出 6 個 `okm_*`，hello 匯出 `_1as_0lib_1header_0root_bmodule_bloader`。
- `cargo check -j 8 --no-default-features`：通過（這個 workspace 沒有 feature，照規則跑一次）。

整合測試第一次跑約 70 秒（要用三個工具鏈各編一次三個 fixture，放在 `target/fixtures-*`），之後有快取，零點幾秒。沒安裝 1.92.0／1.98.1 的機器會印出「toolchain … is not installed; skipping it」並跳過那個版本。

## 沒驗什麼

- **沒有在 Unreal 裡載入**：`ok_mod_host.dll` 只被 Rust 測試以 rlib 方式呼叫過 C 函式，沒有被 C++ `LoadLibrary`（工作項 6）。
- release 版的宿主與 release 版的 mod 互載沒有跑測試（測試的 fixture 都是 debug）；release 只確認了建置與匯出符號。
- 沒有測「mod 用較新的 `ok-mod-api`（加了尾欄位）在舊宿主上」：目前只有 0.1.0 一版，等 API 第一次加欄位時補測。
- 熱重載、`sha256` 驗證、profile 都不在這一項。
