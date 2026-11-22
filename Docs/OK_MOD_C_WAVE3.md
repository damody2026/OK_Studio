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
