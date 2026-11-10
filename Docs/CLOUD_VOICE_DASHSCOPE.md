# TTS／ASR 雲端版（阿里雲百煉 DashScope）

日期：2026-11-08。

`ok-tts` 和 `ok-asr` 各多了一個雲端後端：合成與辨識改送阿里雲百煉（DashScope），本機不載入模型，也不佔用 GPU。HTTP 介面、快取檔與輸出格式（OGG、24 kHz PCM 串流、辨識 JSON）都不變，遊戲端不用改；`/health` 的 `backend` 會顯示 `cloud`。

## 開啟方式

在街區左上角的「設定」填阿里雲百煉金鑰，再把「配音」或「語音輸入」選成雲端。金鑰存進玩家設定檔 `Saved/StreetSocial/player.json` 的 `aliyun` 段（見 [玩家設定檔與 API 金鑰](API_KEYS.md)）。沒有金鑰就沒有雲端，照舊用本機模型。

- **啟動時**：啟動器把 `player.json` 用 `--settings` 傳給伺服器。
  - `voice.voice_mode` 是 `cloud` 且有金鑰：`ok-tts` 只用雲端，不載入本機模型。
  - `asr.mode` 是 `cloud` 且有金鑰：`ok-asr` 只用雲端。
- **執行中**：遊戲用 `POST /cloud {"api_key", "base_url", "tts_model"|"asr_model"}` 打開或關閉雲端（`api_key` 空白就是關閉）。
  - 用雲端啟動的伺服器沒有本機模型，切回本機要重新啟動。這時回覆裡的 `local_ready` 是 false，遊戲會提示。
- 優先順序：`--backend` > 環境變數 `OK_TTS_BACKEND`／`OK_ASR_BACKEND` > `player.json` 的選擇。
- 金鑰優先讀 `DASHSCOPE_API_KEY`，其次是設定檔；`DASHSCOPE_BASE_URL`、`aliyun.base_url` 可覆寫端點。金鑰只能用在建立它的區域，目前的金鑰屬於北京區（`dashscope.aliyuncs.com`）。
- 模型可用 `--cloud-model`、`OK_TTS_CLOUD_MODEL`／`OK_ASR_CLOUD_MODEL` 或 `aliyun.tts_model`／`aliyun.asr_model` 指定。
- `/health` 多了 `local_ready`（本機模型是否已載入）；`backend` 顯示目前是 `cloud` 還是本機。

## TTS（`Tools/ok-tts/src/cloud.rs`）

- **音色**：`voices.json` 的每個性格 × 年紀，第一次用到時以它的描述（`instruct`）在雲端設計一個音色（`/api/v1/services/audio/tts/customization`，`voice-enrollment` 的 `create_voice`），之後同一個角色固定用這個音色。音色 ID 記在 `%LOCALAPPDATA%\OpenKoikatsu\ok-tts-cloud-voices-<模型>.json`。描述改了就會重新設計一個。
- **合成**：`/synthesize` 呼叫 `/api/v1/services/audio/tts/SpeechSynthesizer`，取回 WAV 後照原本流程裁掉前後靜音、正規化並寫成 OGG。`/synthesize_stream` 走同一個端點的 SSE：第一段是 WAV 標頭加 PCM，之後都是 24 kHz PCM16，邊收邊轉給遊戲。
- **預先設計（2026-11-10）**：設計一個音色要 7～12 秒，第一句會等太久而超過遊戲的 TTS 逾時。遊戲在雲端伺服器就緒（`/health` 的 `backend` 是 `cloud`）或切到雲端時，把這個世界每位女主的性格與他的音色送到 `POST /voice/prepare {"voices":[{"personality","age"}...]}`。伺服器在背景設計還沒有的音色，最多 3 個同時進行，立刻回 `{"designing": N}`。每個音色各有自己的鎖，一句台詞不會排在別人的音色後面等。本機後端收到這個請求不做任何事。
- **快取**：快取鍵包含雲端模型與描述（`ok-tts-cloud-1`），不會和本機模型的檔案混用。
- **不支援**：卡片內的角色聲音（`okVo`，Base 後端的 speaker embedding）與 `/voice/candidates`、`/voice/fix`；雲端模式一律依性格的描述選音色。

## ASR（`Tools/ok-asr/src/cloud.rs`）

- `Engine` 改成本機與雲端兩種。麥克風、免持的語音切段、靜音判斷都留在本機，只有 `transcribe` 送到雲端。
- 端點是 OpenAI 相容的 `/compatible-mode/v1/chat/completions`，模型 `qwen3-asr-flash`，音訊以 16 kHz WAV 的 base64 data URI 送出。雲端回傳的語言代碼（`zh`、`en`…）會換回本機用的名稱（`Chinese`、`English`…），中文照舊轉成繁體（玩家語言是 zh-CN 時轉簡體）。
- 雲端模式不做暖機（暖機請求也要計費）。

## 實測（2026-11-08，北京區）

| 項目 | 結果 |
|---|---|
| 第一次用到某個性格（設計音色＋合成） | 11.8 秒＋約 1.4 秒 |
| 之後的 `/synthesize`（20 字，3.9 秒音訊） | 1.85 秒 |
| `/synthesize_stream`（22 字） | 第一段音訊約 1.3 秒 |
| 快取命中（檔案與串流） | 立即 |
| `/transcribe`（4.1 秒音訊） | 1.6–1.7 秒，文字正確並轉成繁體 |
| `/transcribe_spans`（兩段） | 2.3 秒，兩段都正確 |
| 錯誤的金鑰 | 回 `DashScope ASR HTTP 401: Incorrect API key provided...` |
| 本機 ASR（`--backend local`） | 照常可用 |

## 還沒確認

- 沒有在遊戲裡實際開啟雲端模式跑過；以上都是直接打伺服器 HTTP 測的。
- 免持聽寫（`/listen/*`）因為要開實體麥克風而沒有測，它和 `/transcribe` 共用同一個辨識函式。
- 沒有人工試聽雲端音色是否貼近本機的聲音。

## 已處理（2026-11-10）

- 第一次出聲要先設計音色：改成預先設計（見上方「預先設計」）。直接打伺服器實測：兩個新音色同時設計，分別花 6.8 秒、7.8 秒；設計完後那個性格的第一句 `/synthesize` 只要 1.8 秒。
- 遊戲內實測（沙盒，以雲端啟動）：伺服器一就緒，遊戲就送出 `/voice/prepare`（`designing 6`），6 個音色在 7～16 秒內設計完成。和雷電將軍自由對話時，她的每一句在請求後 0.8～2.4 秒開始播放（串流），沒有一句退回內建錄音。
- 同一台機器上的多個 ok-tts 共用 `ok-tts-cloud-voices-<模型>.json`：以前每個程序寫入時都蓋掉整個檔案，會吃掉別的程序剛設計好的音色，那個音色之後又得重新設計（實測時另一個遊戲的伺服器把 `00` 又設計了一次）。現在寫入前會先讀回檔案、合併後再寫；設計前也會先查檔案裡有沒有別的程序做好的。
- 雲端下載的 WAV 讀不了：`ok-asr` 的 `read_wav` 在 hound 拒絕時，改用自己的解析（走過各個 chunk，只取完整的樣本），有單元測試。
