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
