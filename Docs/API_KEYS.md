# 玩家設定檔與 API 金鑰

日期：2026-11-08。

街區（StreetSocial）屬於玩家的設定都放在**同一個檔案**：`Saved/StreetSocial/player.json`。`-Sandbox` 用的是沙盒資料夾裡自己的 `player.json`。它不進版控，啟動器另外會備份一份到 `%LOCALAPPDATA%\OpenKoikatsu\player.json`：`Saved/` 被清掉時，就從這份還原。

**金鑰可以不填。** 沒有金鑰也能玩：對話只用內建選項，配音用內建錄音、本機語音合成，或者不配音。填了金鑰才多出 AI 自由對話和雲端語音。

## 在遊戲裡設定

街區畫面左上角的「設定」（小地圖上面）：

| 項目 | 選項 | 說明 |
|---|---|---|
| 配音 | 內建錄音／本機語音合成／雲端語音合成（阿里雲）／無配音 | 下一句開始生效。雲端要先填阿里雲金鑰。「無配音」時台詞照常播放但沒有聲音，所以說完一句、存好感這些時機都不變。對話面板的 V 鍵也會依序切換這幾種 |
| 語音輸入 | 本機辨識／雲端辨識（阿里雲） | 自由對話用的麥克風辨識 |
| DeepSeek 金鑰 | 文字框 | AI 自由對話和女主角的 AI 都用它。沒有金鑰時，對話面板不顯示「自由對話」按鈕，改成一行提示 |
| 阿里雲百煉金鑰 | 文字框 | 雲端語音合成與辨識，見 [TTS／ASR 雲端版](CLOUD_VOICE_DASHSCOPE.md) |

按「儲存金鑰」寫進 `player.json`。面板下方會顯示目前哪些功能可以用，以及設定檔的完整路徑。

- 換配音或語音輸入時，遊戲立刻通知語音伺服器（`POST /cloud`），不用重開。
- 例外：這次是用雲端啟動的伺服器沒有載入本機模型，改回本機要重新啟動遊戲，面板會提示。
- 例外：啟動時選「無配音」就不會開語音合成伺服器，之後改成語音合成也要重新啟動。
- DeepSeek 金鑰約 2 秒內生效。女主角的 AI（ok-mind）在開圖時讀一次設定。
- 金鑰欄是 UMG 文字框，`ok-game-mcp` 的 `ui_set` 能填：key 是 `SettingsDeepSeekKey`／`SettingsAliyunKey`，填完再用 `ui_press` 按「儲存金鑰」。選項都是按鈕，`ui_press` 按得到。

## 檔案內容

```json
{
  "locale": "zh-TW",
  "render_style": "koikatsu",
  "voice": { "voice_mode": "builtin", "tts_age": 18, "male_tone": "off", "tts_base_size": "1.7B", "player_name": "..." },
  "asr": { "mode": "local", "device": "麥克風名稱的一部分" },
  "deepseek": { "api_key": "", "endpoint": "https://api.deepseek.com/chat/completions", "model": "deepseek-v4-flash" },
  "aliyun": { "api_key": "", "base_url": "https://dashscope.aliyuncs.com", "tts_model": "qwen-audio-3.1-tts-flash", "asr_model": "qwen3-asr-flash" }
}
```

- `voice.voice_mode`：`builtin`、`tts`、`cloud`、`off`。
- `asr.mode`：`local`、`cloud`。
- 環境變數優先於檔案裡的金鑰：`DEEPSEEK_API_KEY`、`DASHSCOPE_API_KEY`（`DASHSCOPE_BASE_URL` 可以換端點）。阿里雲金鑰只能用在建立它的區域，預設端點是北京區。
- 啟動器把這個檔案傳給遊戲（`OK_FREE_TALK_SETTINGS`、`OK_ASR_SETTINGS`）和語音伺服器（`--settings`）。
  - `voice_mode` 是 `cloud` 且有金鑰：`ok-tts` 只用雲端，不載入本機模型。
  - `voice_mode` 是 `off`：不啟動 `ok-tts`。
  - `asr.mode` 是 `cloud` 且有金鑰：`ok-asr` 只用雲端。
- 寫入的程式只改自己那一段，其他欄位原封不動。

## 舊的設定檔

以前分開存在 `voice-settings.json`（配音）、`asr-settings.json`（麥克風）、`deepseek.json`（DeepSeek）。啟動器在啟動時會把它們讀進 `player.json`（`Tools/street_player_settings.lua`），讀過的檔案改名成 `*.migrated`。

- `%LOCALAPPDATA%\OpenKoikatsu\deepseek.json` 也會讀進來，但檔案保留不動（其他 checkout 還在用）。
- 前一版暫時用過的 `%LOCALAPPDATA%\OpenKoikatsu\api-keys.json`，讀進來後就刪除。

## 打包

給別人的版本用 `Tools/package_street_social.lua` 打包，裡面附的是空金鑰的新設定檔，見 [街區打包](STREET_SOCIAL_PACKAGE.md)。
