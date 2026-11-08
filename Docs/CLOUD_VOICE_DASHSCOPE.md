# TTS／ASR 雲端版（阿里雲百煉 DashScope）

日期：2026-11-08。

`ok-tts` 和 `ok-asr` 各多了一個雲端後端：合成與辨識改送阿里雲百煉（DashScope），本機不載入模型，也不佔用 GPU。HTTP 介面、快取檔與輸出格式（OGG、24 kHz PCM 串流、辨識 JSON）都不變，遊戲端不用改；`/health` 的 `backend` 會顯示 `cloud`。

## 開啟方式

在使用者的金鑰設定檔 `%LOCALAPPDATA%\OpenKoikatsu\api-keys.json` 的 `aliyun.api_key` 填入金鑰（見 [API 金鑰設定檔](API_KEYS.md)）。有金鑰，`ok-tts`／`ok-asr` 下次啟動就走雲端；沒金鑰就沒有雲端，照舊用本機模型。

- 優先順序：`--backend` > 環境變數 `OK_TTS_BACKEND`／`OK_ASR_BACKEND` > 有沒有金鑰。有金鑰但要用本機模型時，`ok-tts` 用 `--backend base|design`，`ok-asr` 用 `--backend local`。
- 金鑰優先讀 `DASHSCOPE_API_KEY`，其次是設定檔；`DASHSCOPE_BASE_URL`、`aliyun.base_url` 可覆寫端點。金鑰只能用在建立它的區域，目前的金鑰屬於北京區（`dashscope.aliyuncs.com`）。
- 模型可用 `--cloud-model`、`OK_TTS_CLOUD_MODEL`／`OK_ASR_CLOUD_MODEL` 或 `aliyun.tts_model`／`aliyun.asr_model` 指定。
- 這是使用者層級的檔案，同一台機器上的 C／E／F 三組都會一起切換。

## TTS（`Tools/ok-tts/src/cloud.rs`）

- **音色**：`voices.json` 的每個性格 × 年紀，第一次用到時以它的描述（`instruct`）在雲端設計一個音色（`/api/v1/services/audio/tts/customization`，`voice-enrollment` 的 `create_voice`），之後同一個角色固定用這個音色。音色 ID 記在 `%LOCALAPPDATA%\OpenKoikatsu\ok-tts-cloud-voices-<模型>.json`。描述改了就會重新設計一個。
- **合成**：`/synthesize` 呼叫 `/api/v1/services/audio/tts/SpeechSynthesizer`，取回 WAV 後照原本流程裁掉前後靜音、正規化並寫成 OGG。`/synthesize_stream` 走同一個端點的 SSE：第一段是 WAV 標頭加 PCM，之後都是 24 kHz PCM16，邊收邊轉給遊戲。
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
- 遊戲的 TTS 逾時預設 15 秒，某個性格第一次出聲時要先設計音色（約 12 秒），可能來不及，那一句會退回內建錄音。
- 沒有人工試聽雲端音色是否貼近本機的聲音。
- 直接從雲端下載的 WAV，`ok-asr` 的 `read_wav`（hound）讀不了（data 區塊長度不是樣本大小的整數倍）；`ok-tts` 自己解析標頭，不受影響。
