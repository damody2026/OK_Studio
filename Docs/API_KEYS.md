# API 金鑰設定檔

日期：2026-11-08。

外部服務的金鑰統一放在一個設定檔：**`%LOCALAPPDATA%\OpenKoikatsu\api-keys.json`**（例如 `C:\Users\<使用者>\AppData\Local\OpenKoikatsu\api-keys.json`）。環境變數 `OK_API_KEYS` 可以指定別的檔案。這個檔案不在專案裡，不會進版控。範本是 [`Config/api-keys.example.json`](../Config/api-keys.example.json)：複製過去，再填入要用的金鑰。

```json
{
  "deepseek": {
    "api_key": "",
    "endpoint": "https://api.deepseek.com/chat/completions",
    "model": "deepseek-v4-flash"
  },
  "aliyun": {
    "api_key": "",
    "base_url": "https://dashscope.aliyuncs.com",
    "tts_model": "qwen-audio-3.1-tts-flash",
    "asr_model": "qwen3-asr-flash"
  }
}
```

**有填金鑰就啟用，沒填就沒有。** `api_key` 以外的欄位都可以省略，省略時用上面的預設值。

| 段落 | 有金鑰 | 沒金鑰 |
|---|---|---|
| `deepseek` | 街區的自由對話、女主角的 AI（`ok-mind`）可以使用 | 沒有 AI 對話；面板會提示金鑰尚未設定 |
| `aliyun` | `ok-tts`、`ok-asr` 改用阿里雲百煉的雲端語音合成與辨識，不載入本機模型（見 [TTS／ASR 雲端版](CLOUD_VOICE_DASHSCOPE.md)） | 照舊使用本機 GPU 模型 |

- 金鑰從[阿里雲百煉主控台](https://bailian.console.aliyun.com/)與 [DeepSeek 平台](https://platform.deepseek.com/)取得。阿里雲的金鑰只能用在建立它的區域；預設端點是北京區，其他區域要改 `base_url`。
- 環境變數優先於設定檔：`DEEPSEEK_API_KEY`、`DASHSCOPE_API_KEY`（`DASHSCOPE_BASE_URL` 可覆寫端點）。
- 有阿里雲金鑰但想用本機模型：`ok-tts --backend base|design`、`ok-asr --backend local`，或設環境變數 `OK_TTS_BACKEND`／`OK_ASR_BACKEND`。
- 改了金鑰以後：DeepSeek 在遊戲中約 2 秒內生效；`ok-tts`／`ok-asr` 只在啟動時讀取，要重新啟動伺服器（關掉遊戲再開即可）。
- 這是使用者層級的檔案，同一台機器上的所有 checkout（C／E／F）都會讀到同一份。

## 舊的設定檔

`deepseek.json`（`OK_FREE_TALK_SETTINGS`、專案的 `Saved/StreetSocial/deepseek.json`、`%LOCALAPPDATA%\OpenKoikatsu\deepseek.json`）仍然讀得到：`api-keys.json` 的 `deepseek` 段落沒有金鑰時，才會改讀這些舊檔。
