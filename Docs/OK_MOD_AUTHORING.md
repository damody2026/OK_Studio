# 寫一個 OK mod（從 `ok-mod-pack new` 開始）

給 mod 作者的入門。框架設計在 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md)，所有掛點與回覆格式在 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md)，打包與安裝在 [OK_MOD_S12_PACK.md](OK_MOD_S12_PACK.md)。

OK mod 是一個 Rust `cdylib`（Windows 上就是一個 DLL），用 `ok-mod-sdk` 寫，遊戲的宿主 `ok_mod_host.dll` 以 `abi_stable` 載入。mod 作者只碰 SDK，不手寫 C ABI。

## 1. 產生範本

```powershell
cargo build --release -p ok-mod-pack --manifest-path F:\OpenKoikatsu\Tools\ok-mod\Cargo.toml
F:\OpenKoikatsu\Tools\ok-mod\target\release\ok-mod-pack.exe new F:\MyMods\tea-time --id org.example.tea-time --name "Tea time" --author "我"
```

| 參數 | 意思 |
|---|---|
| `<folder>` | 新 mod 的資料夾，不存在或是空的 |
| `--id` | mod id，反向網域、小寫：`org.example.tea-time`（每段 a–z 開頭，只用 a–z、0–9、`-`） |
| `--name` | 顯示名稱；不給就用 id 最後一段 |
| `--author` | 寫進 `mod.toml` 的 `authors` |
| `--sdk` | SDK crate 的位置；預設是建 `ok-mod-pack` 的那份 `Tools/ok-mod/sdk` |
| `--json` | 回答用 JSON |

產生的檔案（以 `org.example.tea-time` 為例）：

```text
tea-time/
  Cargo.toml                 # crate ok-mod-tea-time，lib ok_tea_time（cdylib），依賴 ok-mod-sdk（相對路徑）
  mod.toml                   # id、版本 0.1.0、api 0.1、dll ok_tea_time.dll、targets、category
  src/lib.rs                 # 設定項、主控台指令、熱鍵、熱重載保留狀態
  locale/en/tea-time.toml    # 程式用到的每個文字 id
  locale/zh-CN/tea-time.toml
```

- **放在 `Tools/ok-mod` 工作區外**（一般情況）：`Cargo.toml` 自帶空的 `[workspace]`（不被上層工作區吞掉）與 `panic = "unwind"` 的 profile。
- **放在 `Tools/ok-mod` 裡**（例如 `examples/<名稱>`）：不加 `[workspace]` 與 profile，沿用工作區的；回答會提示要把哪一行加進 `Tools/ok-mod/Cargo.toml` 的 `members`。

`panic = "unwind"` 不能改：SDK 把 panic 變成錯誤、宿主把那個 mod 停掉；`abort` 會讓整個遊戲跟著當掉，`ok-mod-pack pack` 會拒絕這種 DLL。

## 2. 範本裡有什麼

`src/lib.rs` 的四個部分，都可以直接刪掉不要的：

| 部分 | 程式 | 玩家看到 |
|---|---|---|
| 設定項 | `reg.config_text("greeting", "hello", "mod.<id>.config.greeting")` | 讀卡器 Mods 頁一列文字框；值存在 `UserData/config/mods/` |
| 主控台指令 | `reg.command("hello", ...)` → `Event::Command { name: "hello" }` | 主控台 `mod.<id>.hello`；控制通道 `mod_call` 也叫得到 |
| 熱鍵 | `reg.hotkey("hello", "", ...)` → `Event::Hook { name: "key.hello" }`，payload `hooks::KeyPress { mode, chord }` | 讀卡器 Mods › 熱鍵頁可綁；主控台 `OKMod.Bind <id> hello F7`。範本預設沒綁，避免和別的 mod 搶鍵 |
| 熱重載保留狀態 | `reg.keep_state()`；`hooks::SAVE_STATE` 回 `hooks::json(&self.count)`，`hooks::RESTORE_STATE` 讀 `hooks::RestoreState<u64>` | 開發模式 `mod.reload <id>` 後計數不歸零 |

細節見 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md) §9。其他掛點（讀卡器 `reader.*`、轉卡 `extract.*`、Studio `studio.*`、1 對 1 `pair.*`、街區 `street.*`、材質 `material.*`、計時 `timer.*`）都一樣用 `reg.subscribe("<hook 名>")` 訂閱，在 `on_event` 比對 `Event::Hook { name, payload }`，payload 用 `hooks::parse`，回覆用 `hooks::json`。

規則：

- **文字一律走 locale**：程式只寫文字 id，id 必須以 `mod.<id>.` 開頭（`pack` 會檢查）。至少給 `en`；`zh-CN`、`zh-TW` 有就加。
- **每幀做事**（改骨骼、推動態骨外力）不走 hook：SDK 開 feature `frame`，用 `ok_mod_frame!`，每個 mod 每次呼叫預算 500 µs（計畫 §7.6，範例 `examples/boop`、`examples/idle-breath`）。
- **mod 自己的卡片資料**（`okMx`）：`hooks::ExtSection::data(version, upgrade)` 讀、`hooks::save(version, &data)` 寫（範例 `examples/profile`、`examples/outfit-names`）。
- `targets` 決定在哪些模式載入：`reader`（讀卡器）、`studio`（OK Studio）、`pair`（1 對 1）、`street`（街區）、`extract`（開卡／轉卡的 worker）。用不到的模式不要列，少載一份。

## 3. 建置、打包、安裝

```powershell
cd F:\MyMods\tea-time
cargo build --release -j 8
F:\OpenKoikatsu\Tools\ok-mod\target\release\ok-mod-pack.exe pack F:\MyMods\tea-time --dll F:\MyMods\tea-time\target\release\ok_tea_time.dll
F:\OpenKoikatsu\Tools\ok-mod\target\release\ok-mod-pack.exe install F:\MyMods\tea-time\org.example.tea-time-0.1.0.okmod --to F:\OpenKoikatsu\Mods
```

- `pack` 檢查 `mod.toml`、DLL 的 ABI 版面與 `panic = unwind`、locale id、內容 pak，寫出 `<id>-<版本>.okmod`（`mod.toml` 帶 DLL 的 sha256）。
- `install` 在遊戲用著那個 `Mods/` 時會拒絕；同 id 只留最新版，舊的搬到 `Mods/.old/`。
- `verify <Mods>` 離線列出每個模式會載入哪些 mod、為什麼沒載入。
- 遊戲找 `Mods/` 的順序：`-ModsDir=`、`OK_MODS_DIR`、stage 根的 `Mods/`、checkout 根的 `Mods/`（[OK_MOD_S6_UE_HOST.md](OK_MOD_S6_UE_HOST.md)）。

## 4. 開發時的迴圈

1. 遊戲加 `-ModDev` 啟動（開發模式才允許熱重載）。
2. 改程式，`cargo build --release`，把新 DLL 放進 `Mods/<id>/`。遊戲開著時第一次載入的原檔被 Windows 鎖住，不能覆蓋但可以改名：先把舊檔改名（例如 `ok_tea_time.dll.old`），再複製新的進去。`abi_stable` 不卸載 DLL，載入過的檔案整個行程都鎖著，所以每次都這樣做；重載實際載入的是宿主複製到 `Mods/<id>/.reload/` 的新檔名副本。
3. 主控台 `mod.reload <id>`：舊副本 `shutdown`，新副本載入；訂了 `keep_state` 的 mod 狀態接著用。
4. `mod.list` 看狀態；panic 過的 mod 顯示 `faulted` 與原因，要修好再重載。

正式遊戲（沒有 `-ModDev`）不做熱重載，`dev.*` 掛點不會發生。

## 5. 範例對照

| 想做 | 看 |
|---|---|
| 最小的 mod、熱鍵、熱重載狀態 | `Tools/ok-mod/examples/hello` |
| 讀卡器面板與控制項 | `examples/ui-sample`、`examples/dream-panel`、`examples/random-chara` |
| 卡片資料（okMx） | `examples/profile`、`examples/outfit-names` |
| 每幀（外力、改骨骼） | `examples/boop`、`examples/idle-breath` |
| OK Studio | `examples/object-hotkeys`、`examples/studio-autosave`、`examples/scene-notes`、`examples/timeline-flow` |
| 1 對 1、街區 | `examples/pair-counter`、`examples/birthday`、`examples/subtitles` |
| 材質、shader（內容 mod） | `examples/glass-shader`、`examples/skin-decal`、`examples/toon-post` |
