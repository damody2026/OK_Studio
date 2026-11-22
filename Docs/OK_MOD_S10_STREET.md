# OK Mod 工作項 10：街區（C 組，2026-11-23）

計畫：F 的 `Docs/OK_MOD_FRAMEWORK_PLAN.md` §6.6、§14.3（`birthday`、`subtitles`）、§15.4 第 10 列；盤點 `Docs/OK_MOD_HOOK_INVENTORY.md` §3.6。給 mod 作者的說明在 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md) §8。沒有改 `ok-mod-api`（街區全部走既有的 `Event::Hook`）。

## 做了什麼

### 1. 街區掛點（新檔 `Source/OpenKoikatsu/OKStreetSocialMods.inl`）

- 事件：`street.load`（讀好存檔後、每個 mod 帶自己的狀態）、`street.day_change`（`NextDay`，存檔前）、`street.talk_begin`／`talk_end`、`street.invite`（答應／拒絕）、`street.phone`（他打給她，接了沒）、`street.gift`（送禮結果）、`street.speech_start`（她的回話開始唸）。
- 給 AI 的事實：`street.talk_facts`，回覆的 `facts` 接在她這一回合【今天】那行的後面（`TodayText`），那一段本來就每回合變，不影響前綴快取。mod 只能給事實，說什麼由 AI 決定。
- **`ext.mods.<id>`**：mod 回 `{"state": …}` 就寫進存檔的 `ext.mods.<id>`；規則鏈原本就會把 `ext` 原樣帶過，所以跟著下一次存檔寫出；讀檔（場景重開）後由 `street.load` 交回。
- **命名空間規則**：`OKRulesEval` 遇到 `"<mod id>.<rule>"`（前綴是訂閱了 `street.rule` 的已啟用 mod）就交給那個 mod；控制通道 `/rules eval` 也一樣，MCP 叫得到。
- 回覆的 `notice`、`subtitle` 顯示在街區的提示行。

### 2. 模式切換時重送啟用清單（`OKModModes.cpp`）

每 0.5 秒看一次宿主的目前模式，變了就重送 ok-extract 的啟用清單。街區程式自己 `EnterMode("pair")`（E 線的 1 對 1）也會跟上，不必每個呼叫點各自記得。C 的程式碼裡目前沒有呼叫 `EnterMode("pair")` 的地方，這是給同步後的 E 程式碼用的。

### 3. 開卡快取鍵只算會影響開卡的 mod（ok-extract `okmods::changes_opens`，工作項 2 行為修正）

實測時發現：只要裝了任何 mod，街區女角就載不出來。原因：

1. 工作項 2 讓開卡快取鍵包含「所有啟用的 mod 與版本」，裝了 birthday 之後鍵就變了，所有快取都沒命中；
2. 街區那幾張卡在遊戲內**重新開**本來就會失敗（`unanswered question(s)`，問的是 `mods/sideloader modpack - animations/*.zipmod`）。用 `-NoMods` 加 `OK_NOCACHE=1` 也一樣失敗，所以這不是 mod 造成的，平常只是被快取擋住；`ok_cards.lua verify`（不在遊戲內）開同一張卡是好的。

修正：快取鍵只算訂閱了「開卡時會跑的 `extract.*` 掛點」的 mod（`extract.kkex`／`extract.kkex_keys` 只影響轉卡，不算）。現在街區、讀卡器的 mod 都不會讓快取失效；之後真的會改開卡結果的 mod（貼圖後處理之類）仍然會換鍵。宿主清單裡已經有 `subscriptions`，不用改 api。**這改變了工作項 2 驗收過的行為，請協調者確認。**

第 2 點（遊戲內重新開卡失敗）是既有問題，沒有修，見下方「發現的問題」。

### 4. 範例

- **`birthday`**（新，`targets = ["street"]`）：核心已經會在她生日那天說「今天是你的生日」、送禮有加成，這個 mod 不重做這些，只補核心沒有的：**每年生日他有沒有來、她有沒有收下禮物**，存在 `ext.mods.org.openkoikatsu.birthday`，之後的回合當事實交給她（「2026 年你生日那天，他來見了你，你也收下了他的禮物」），生日早上給玩家一則提示。沒來的那年什麼都不說、不倒數、不加任何壓力。另提供命名空間規則 `org.openkoikatsu.birthday.upcoming`（接下來的生日）。三種語言依 `lang`。
- **`subtitles`**：多訂閱 `street.speech_start`（以及給工作項 13 用的 `pair.speech_start`），回覆相同。

## 驗了什麼

- **cargo**：`Tools/ok-mod` 整個 workspace `cargo test` 全過，新增 `host/tests/street_mods.rs`（載入 birthday 與 subtitles 的 DLL：新遊戲讀檔、換日提示、對話與送禮記錄、拒收不記、事實、規則、字幕、換一個宿主讀回存檔狀態後事實仍在）與 birthday 的單元測試（日期計算含 2/29、記錄只在生日當天、沒來的那年不說）。ok-extract `cargo check` 與 `--no-default-features` 通過，`okmods` 新測試通過。
- **建置**：`may-build` 後用 D: 引擎建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development，最後一次改動後兩個都 `Result: Succeeded`。
- **街區實測**（`-Editor -Sandbox cmod10 -PortBase 48160 -Heroine 1`，自己的連接埠 48170、自己的沙盒存檔，沒碰別人的 stage；`c-mod-10` 占名額，用完已關閉並釋放）。測試前把沙盒裡貞德·Alter 的生日改成隔天（`Saved/StreetSocial/Sandbox/cmod10/mind/heroines/…json`，只有這個沙盒）：

| 項目 | 結果 |
|---|---|
| 宿主 | 街區模式載入 birthday、subtitles |
| 讀檔 | `street.load` 在第一個街區掛點之前送出 |
| 換日（N） | 日期 2010-10-09 → 10-10；提示行「今天是贞德·Alter的生日。」 |
| 對話 | `street.talk_begin` → birthday 回 `state`；`ok.Street.Inspect` 裡她的【今天】最後一句是「今天是你生日，他來找你了」 |
| 存檔 | 存到欄位 1，`Saves/1/relationships.json` 的 `ext.mods.org.openkoikatsu.birthday.years.<她的 id>.2010 = {met: true, gift: false}` |
| 讀檔 | 讀欄位 1（場景重開）→ `street.load` 交回狀態，她的【今天】仍有那一句 |
| 命名空間規則 | `/rules eval {"rule":"org.openkoikatsu.birthday.upcoming",…}` 回 `{"upcoming":[{"name":"贞德·Alter","in_days":0,…}]}` |
| AI 對話（開雲端） | 說「生日快樂」，她回「你、你怎麼知道？我沒跟誰提過生日啊…」；`street.speech_start` 每句都送到 subtitles |
| 字幕 | 提示行顯示她那句話（截圖 `C:\portable\OpenKoikatsu\Saved\StreetSocial\Play-20261123T034232\control_shots\shot.0001.png`） |
| 開卡快取修正 | 修正前：裝 mod 時貞德·Alter、雷電將軍都載不出（`unanswered question(s)`）；`-NoMods` 正常；`-NoMods`＋`OK_NOCACHE=1` 也失敗。修正後裝 mod 也正常載入 |

## 沒驗什麼、發現的問題

- **遊戲內重新開街區女角卡會失敗（既有問題，未修）**：不用快取時，`jeanne_alter.png`、`raiden_shogun.png` 在街區開卡都報 `the OK card has N unanswered question(s)`，問的是 `mods/sideloader modpack - animations/…zipmod`；`ok_cards.lua verify` 在遊戲外開同一張卡是好的。推測是街區執行時讀動畫 mod 的掃描落進了卡片的嚴格開卡範圍。快取被清掉（或快取鍵改變）的機器上街區女角會載不出來。開卡路徑不在工作項 10 範圍，交給協調者決定由誰處理。
- `street.talk_end`、`street.invite`、`street.phone` 在遊戲裡有送出，但兩個範例都沒訂閱，只有程式路徑與 `talk_end` 的觸發確認，沒有 mod 回覆可看。送禮（`street.gift`）沒在遊戲裡實際送過，只有宿主測試。
- 開卡快取鍵的修正改變了工作項 2 的行為（見第 3 節），請協調者確認。
- 打包的 stage 沒有重建驗證，只用 `-Editor` 跑。
- 讀卡器 mod 頁的數字滑桿與顏色控制項還沒做：協調者已把它併進工作項 7b（DreamGUI 宣告式），在那裡完成。

## 開卡基準（S2 補量）

機器沒有 Unreal 在跑時量的（含本工作項的快取鍵修正）：總計 5.39 秒，對照上一份 7.84 秒 -31.3%，工作量計數 473 → 472，沒有變慢。細節寫在 `Docs/OK_MOD_S2_CARD_CHUNKS.md` 最後一節。
