# OK Mod 第三波（C 組，2026-11-23，同步點 B 之後）

協調者指派的五項，依序做。C 已快轉到 351002ba5（同步點 B）。

## 1. ui_widgets／ui_set 列得出、改得到讀卡器 mod 頁的原生控制項（86c6b53d6）

**問題**：同步點 B 帶進來的 F 的修正（9a63c5401）讓 `ui_widgets` 列得出 DreamGUI 鏡像，但它是從鏡像的 UMG 來源（`UOKDreamControl::Source`）去找控制項。工作項 7b 的 mod 頁控制項沒有 UMG 來源，所以一個都列不出來。

**修正**（`OKGameControl.cpp`，F 不在改這個檔，提交訊息寫清楚了）：

- `/widgets` 在 UMG 控制項之後，加上讀卡器畫面的 `UOKReaderScreen::BoundControls()`：沒有 UMG 來源、值綁在 mod 上的控制項，而且要在畫面上。
  - 值控制項：鍵是 `Dream/<路徑>`（路徑和 `ok.ReaderScreen controls` 一樣）；`kind` 是 `number`、`bool`、`choice`（附 `choices`）或 `text`，附 `value`；數字另附 `min`、`max`。
  - 按鈕：放進 `buttons`，用文字標示。
- `/widget`：依 `key` 或 `label` 設值，值用 `UOKDreamControl::SetValue` 檢查後送到 mod，超出範圍或不是選項之一會回錯誤；沒給 `value` 時依文字按按鈕。
- `UOKDreamControl::IsOnScreen` 多看 TabView 目前開著的是哪一頁：收起的分頁裡的控制項不算在畫面上。工作項 7b 回報的限制「藏在別的分頁裡的控制項 `press`／`set` 照樣做得到」也一併修掉了。

**實測**（讀卡器，`c-mod-w3` 拿到 slot1，用完關閉並釋放；開的卡是 `C000.png`，在 Mods›控制項範例）：

- `ui_widgets`：只列出目前分頁的控制項。「數值」頁列出 3 個（數量 Spin、音量 Slider、顏色）；切到「選擇」頁後列出小／中／大、心情、清單、害羞，「數值」頁那 3 個就不列了。
- `ui_set`，每一筆都用 `reader_call get` 確認 mod 那邊的值：

| 控制項 | 設的值 | mod 那邊的結果 |
|---|---|---|
| Spin | 9 | count 變 9 |
| 顏色 | `#20A060` | tint 變 `#20A060` |
| Slider | 2 | 拒絕，回 `out of range 0..1` |
| 單選「大」 | true | size 變 `l` |
| Choice | 「開心」 | mood 變 `happy` |
| List | 「桃子」 | fruit 變 `peach` |
| 害羞 | true | shy 變 true |
| 多行 Input | 一段文字 | note 寫入 |

- `ui_press {"label":"恢復初始值"}`：mod 指令執行，值回到初始。
- 用 D: 引擎建編輯器與遊戲兩個目標，都成功。

## 2. 街區女角冷開報 unanswered question(s)：已修（ff61e59f5）

**原因**：

- 街區同時開 5 張卡。開卡的頭部細節貼圖那一步（`extract.rs`）是 rayon 平行迭代，沒有包在 `oklib::pack_parallel` 裡，所以跑在全域池。
- 全域池的執行緒只能靠 `pack_scope()` 的退路找到卡，而退路只有剛好一張卡在開時才給。好幾張一起開時，這一步找不到卡，查不到卡內的樹答案（okLt `override`），就去掃整棵 mods 樹。
- 等到只剩最後一張卡還在開，這些讀取又被算成那張卡的缺口：約 4000 個 `GAMEFS zip …`。動畫 mod 按字母排在最前面，所以錯誤訊息看起來像只問動畫 mod。
- 讀卡器、`ok_cards verify`、`strict-check` 一次只開一張；有快取時又不跑這一步。所以只有街區冷開會出事。

**怎麼找到的**：`OK_STRICT_TRACE` 的追蹤原本只寫到 stderr，遊戲裡看不到。改成也寫進遊戲 log 之後，以 `OK_NOCACHE=1` 開街區，從堆疊可以看到執行緒在全域池上，而且「own pack scope: false」。

**修正**：那一步改用 `pack_parallel`，和開卡其他會讀卡片資料的平行步驟一樣。開卡路徑上其他沒包的平行迭代，我逐一看過，都只處理像素或幾何，不讀檔。

**沒採用的做法**：把整個開卡搬進卡自己的池。開卡執行緒上有不少執行緒區域的旗標與快取，搬過去就看不到了。

**驗證**：

- 街區 `-Editor -Sandbox cmod10 -PortBase 48160`、`OK_NOCACHE=1`：
  - 修正前：貞德·Alter、雷電將軍載不出，3981 個缺口；
  - 修正後：log 沒有任何 unanswered，全部女角都載入（胡桃、貞德、貞德·Alter、雷電將軍、克拉拉、嵐、邱無忌、刻晴、洛天依、三月七）。
- ok-extract `cargo check`，含 `--no-default-features`。
- pack_scope 與 okstrict 的單元測試。
- 用 D: 引擎建編輯器與遊戲兩個目標，都成功。
- ERROR_LOG 已補一條「已修」。

**沒驗**：`-NoMods` 冷開沒有另外跑；同一條程式路徑，只是不載 mod。打包的 stage 沒有重建。

## 3. pair-counter 的統計在讀卡器顯示（017790714）

E 的 `examples/pair-counter` 在 1 對 1 結束時，把次數、時間、雙方高潮次數寫進她卡片的 okMx。這次加讀卡器端：

- `mod.toml` 的 `targets` 加 `reader`。
- 訂閱 `reader.character_load`：讀這張卡的區段；照「載入卡片時套用」開關也照樣讀，因為只是顯示。另訂閱 `reader.character_unload`、`reader.ui`、`reader.values`。
- 新增「1 對 1 統計」頁，全部唯讀：次數、總時長與平均、她／他各幾次、最後一次的日期（UTC）。沒有紀錄的卡顯示「這張卡還沒有 1 對 1 的紀錄。」
- **不訂閱 `reader.character_save`**：讀卡器另存卡片時，這個區段原樣保留，不會被讀卡器改動。

**驗證**：

- pair-counter 的單元測試（新增日期與頁面文字的測試）。
- 新的宿主測試 `host/tests/pair_counter_reader.rs`：
  - 先用 pair 模式的宿主跑一次 1 對 1（enter、finish ×2、exit 90 秒），得到 mod 要寫進卡的區段；
  - 再用讀卡器模式開卡、把這個區段交給 mod：頁面顯示「1 次」「共 1.5 分鐘，平均每次 1.5 分鐘」「她 2 次，他 1 次」；
  - 換一張沒有資料的卡，會說沒有紀錄。
- 讀卡器實測：Mods 分類出現「1 對 1 統計」頁，`C000.png` 沒有紀錄，照實顯示。

**沒驗**：拿一張真的經過 1 對 1、卡裡已寫入統計的卡，到讀卡器打開看。E 線的 1 對 1 不在 C 的範圍，我沒有實際跑一次 1 對 1。

## 4. random-chara 換髮色，走套用流程（8a251342a）

髮色不是登錄裡的單一數值，而是原作編輯器的組合動作（設定一個底色，同時設好每個頭髮部件的漸層、外框與光澤）。因此在讀卡器 mod 回覆加一個新欄位 `ops`：

- 讀卡器收到 `ops` 後交給 `UOKCharacterController::ApplyPropertyOps`，和詳細編輯套用時同一條流程（`Docs/READER_UI_APPEARANCE_API.md` §10）。
- 讀卡器忙（載入中、套用中）時，用 ticker 等它空下來，最多等 30 秒。
- 還沒有待套用的屬性來源時，先接手目前這張卡與服裝作為來源，再套。
- 被拒時寫 log，並在畫面提示原因。
- `Docs/OK_MOD_HOOKS.md` §5 補了 `ops` 一列。

random-chara 加一個「髮色」開關，鍵是 `hair`，預設關。勾選後，「隨機」除了原本的滑桿，還會回 `{"op": "hair_base_color", "rgba": [...]}`：

- 色相任意；
- 飽和度、明度限制在頭髮會有的範圍內，「幅度」越大範圍越寬。

**驗證**：

- random-chara 單元測試（新增 `hair_is_an_op`）。
- 用 D: 引擎建遊戲與編輯器兩個目標，都成功。
- 讀卡器實測（`C000.png`）：勾髮色、連按 4 次「隨機」，`hair.parts.0.baseColor` 每次都變成 mod 給的顏色。

**發現的問題（不是這次的改動造成的）**：

- `C000.png` 的頭髮是 mod 頭髮，顏色畫在貼圖上，不吃 `baseColor`。所以數值變了，畫面上頭髮仍是粉紅色。換一張原作頭髮的卡才看得到效果，我沒有另外找卡驗。
- 第一次套 ops 之後，身形看起來不同（裙子變窄、腿變長）。這是既有的 `properties_apply` 套用流程重組角色造成的，和讀卡器詳細編輯按「套用」時一樣；新程式只是呼叫它。沒有往下追。
