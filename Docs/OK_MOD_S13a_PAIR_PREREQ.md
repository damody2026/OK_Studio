# OK mod 工作項 13 前置：1 對 1 事件的外部訂閱（2026-11-23，E 組）

協調者在工作項 5 驗收後指派（同步點 A 之前、不依賴 mod 宿主）。計畫：F 的 `Docs/OK_MOD_FRAMEWORK_PLAN.md` §14.3、§15.4 第 13 項；盤點 `Docs/OK_MOD_HOOK_INVENTORY.md` §3.5。

## 提交

| 提交 | 內容 |
|---|---|
| `d18598efd` | 1 對 1 事件的外部訂閱介面與各處一行呼叫 |
| `43349ff3a` | 自動化測試 `OpenKoikatsu.Interaction.ModEvents`、實機記錄指令 `ok.PairModEvents` |

## 做了什麼

新檔 `Source/OpenKoikatsu/OKInteractionMod.h/.cpp`：`FOKInteractionModEvents::Get()`。

- `Subscribe(owner, callback)` 回傳 id；可以用 `Unsubscribe(id)` 退訂，或用 `RemoveOwner(owner)` 一次移除（宿主停用 mod 時用）。
- 只在 game thread 使用。回呼裡只讀，不改場景。回呼中退訂或新訂閱，下一個事件才生效。
- 沒人訂閱時，每個呼叫點只多一次判斷就返回。

事件（`FOKPairModEvent`，都帶 `Card`：她的卡片路徑）：

| 事件 | 從哪裡發 | 欄位 |
|---|---|---|
| `Enter` | `AOKInteractionMode::Enter` 結尾（讀卡器、街區、`EnterCards` 都經過這裡） | `bFitting`（街區試衣間，不是 1 對 1）；這時卡片可能還不是她的 |
| `Ready` | 兩人都載好、開始播放（evidence 寫 `ready` 的那一處） | — |
| `Exit` | `AOKInteractionMode::Exit` | `bCancelled`（取消或沒啟動）、`Seconds`（Ready 之後經過的秒數） |
| `Note` | `UOKHScenePanel::Note`（H 場景的事件單一入口，約 50 處） | `Text`（顯示的文字）、`bReact` |
| `Finish` | `UOKHScenePanel::Finish` | `Text` 為種類（`org_in`、`same_out`…） |
| `Voice` | 原作 H 語音 `UOKHScenePanel::PlayHVoice`、TTS 台詞 `AOKInteractionMode::HSceneSpeak`，播放成功時 | `Source`（`hvoice`／`tts`）、`Path`、`Text`（檔名或語音名稱）、`Row`（hvoice 的表號 300+） |
| `Line` | `UOKHScenePanel::ShowLine`（她的台詞文字，過期的不發） | `Text` |

既有檔案只加呼叫：`OKHScene.cpp` 四處加 include，`OKInteractionMode.cpp` 四處加 include。

## 驗了什麼

- 建置：`OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 都在 `E:\PhysX\UE5.8` 建置成功。
- `OpenKoikatsu.Interaction.ModEvents`（UnrealEditor-Cmd，NullRHI）：**通過**。驗了：
  - 七種事件依序各收到一次，欄位正確；
  - 空回呼被拒絕；
  - 回呼中退訂時，其他訂閱者照順序收到，退訂者之後收不到；
  - 退訂兩次會失敗；移除 owner 後收不到。

  同一次也重跑了工作項 5 的 `OpenKoikatsu.Studio.ModData`，仍然通過。
- 實機：用 `-LegacyReader` 開讀卡器並載入 `Content/CharacterCards/Demo/C050.png`，開 `ok.PairModEvents on`，按「進入1對1互動場景」，按「摸胸部」，再按「離開（回到讀卡）」。共收到 21 筆事件，依序有：
  - `enter`、`ready`；
  - `note`（她換上了制服、他撫摸她的胸部）；
  - `line`（她的台詞）；
  - `voice source=tts`（六次）；
  - `exit cancelled=0 seconds=32.3`。

  全部帶 `card=C050.png`。記錄在 `E:\OpenKoikatsu\Saved\OKInteraction\pair_mod_events.txt`。
- 既有行為：進出、載入、台詞、語音在實機照常；log 裡沒有新的錯誤（只有這張卡本身缺 3 個 okLt 資料的既有訊息）。各處呼叫在沒人訂閱時不做事，事件發送只讀狀態。

## 沒驗什麼

- `Finish` 與 `Voice source=hvoice` 沒在實機觸發（要玩到高潮、開原作 H 語音），只有自動化測試。
- 街區的 1 對 1（`OKStreetSocialContacts.inl` 交接進出）沒有實機跑；它也經過 `AOKInteractionMode::Enter`／`Exit`，照理收得到。
- 既有的 `ok.AuditSharedInteraction` 這次沒跑成（讀卡器一收到指令就 exit 1，原因沒查，見 `Docs/ERROR_LOG.md`），所以沒有用它的往返檢查比對改動前後。

## 給工作項 13 的備註

- `Note` 的文字是已翻譯好的顯示文字（`OKT`／`OKMsg` 的結果），沒有語義 id。mod 不能拿文字做關鍵字判斷（計畫 §6.6）。要給 `pair-counter` 用，建議工作項 13 把 `Note()` 改成同時傳語義 id（例如 `ui.hscene.event_first_kiss`）。這要改約 50 個呼叫點，不是一行改動，這次沒做。
- `Enter` 時卡片路徑可能還是資料夾裡第一張；`Ready` 之後才可靠。
- 1 對 1 以外的語音（讀卡器、街區的一般對話）不在這個介面內，`subtitles` 的街區部分歸 C 的工作項 10。
