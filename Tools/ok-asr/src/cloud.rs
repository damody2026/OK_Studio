//! Cloud backend: speech is recognized by Alibaba Cloud Model Studio (百煉, DashScope; qwen3-asr-flash through the
//! OpenAI-compatible chat completions) instead of the local GPU model. The microphone, voice activity cuts and the
//! HTTP contract stay here; only `transcribe` goes to the cloud.
//!
//! Settings are shared with ok-tts: DASHSCOPE_API_KEY, else the "api_key" of %LOCALAPPDATA%\OpenKoikatsu\dashscope.json
//! (OK_DASHSCOPE_CONFIG names another file). The key never goes into the repository.

use std::path::PathBuf;
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Result};
use base64::Engine as _;
use serde_json::{json, Value};

use crate::engine::Transcript;
use crate::mel::SAMPLE_RATE;
use crate::text::to_display;

pub const DEFAULT_MODEL: &str = "qwen3-asr-flash";

/// The settings file: {"api_key", "base_url", "tts": bool, "asr": bool, "tts_model", "asr_model"} (all optional).
pub fn config_path() -> PathBuf {
    if let Some(p) = std::env::var_os("OK_DASHSCOPE_CONFIG").filter(|p| !p.is_empty()) {
        return PathBuf::from(p);
    }
    let base = std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
    base.join("OpenKoikatsu").join("dashscope.json")
}

fn config() -> Value {
    std::fs::read_to_string(config_path()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_else(|| json!({}))
}

fn setting(cfg: &Value, env: &str, field: &str) -> Option<String> {
    std::env::var(env).ok().filter(|v| !v.trim().is_empty())
        .or_else(|| cfg.get(field).and_then(Value::as_str).map(str::to_string))
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// Whether the settings file asks for the cloud ASR (`"asr": true`); OK_ASR_BACKEND and --backend win over it.
pub fn wanted() -> bool {
    config().get("asr").and_then(Value::as_bool).unwrap_or(false)
}

pub struct Cloud {
    key: String,
    base_url: String,
    pub model: String,
    agent: ureq::Agent,
}

impl Cloud {
    pub fn new(model: Option<&str>) -> Result<Self> {
        let cfg = config();
        let key = setting(&cfg, "DASHSCOPE_API_KEY", "api_key")
            .ok_or_else(|| anyhow!("no DashScope API key: set DASHSCOPE_API_KEY or \"api_key\" in {}", config_path().display()))?;
        let base_url = setting(&cfg, "DASHSCOPE_BASE_URL", "base_url").unwrap_or_else(|| "https://dashscope.aliyuncs.com".into());
        let model = model.map(str::to_string).or_else(|| setting(&cfg, "OK_ASR_CLOUD_MODEL", "asr_model")).unwrap_or_else(|| DEFAULT_MODEL.into());
        let agent = ureq::AgentBuilder::new().try_proxy_from_env(true).timeout_connect(Duration::from_secs(15)).timeout_read(Duration::from_secs(60)).build();
        crate::log!("ok-asr: backend cloud ({model} at {base_url})");
        Ok(Self { key, base_url: base_url.trim_end_matches('/').to_string(), model, agent })
    }

    /// 16 kHz mono samples -> transcript, like the local engine. `language` ("Chinese", "English", ...) is passed on
    /// as a hint.
    pub fn transcribe(&self, samples: &[f32], language: Option<&str>) -> Result<Transcript> {
        let t = Instant::now();
        let audio_seconds = samples.len() as f64 / SAMPLE_RATE as f64;
        let wav = base64::engine::general_purpose::STANDARD.encode(wav16(samples));
        let mut options = json!({"enable_itn": false});
        if let Some(code) = language.and_then(language_code) {
            options["language"] = json!(code);
        }
        let body = json!({
            "model": self.model,
            "messages": [{"role": "user", "content": [{"type": "input_audio", "input_audio": {"data": format!("data:audio/wav;base64,{wav}")}}]}],
            "stream": false,
            "asr_options": options,
        });
        let reply = self.agent.post(&format!("{}/compatible-mode/v1/chat/completions", self.base_url))
            .set("Authorization", &format!("Bearer {}", self.key))
            .set("Content-Type", "application/json")
            .send_string(&body.to_string());
        let reply: Value = match reply {
            Ok(r) => serde_json::from_str(&r.into_string()?)?,
            Err(ureq::Error::Status(code, r)) => {
                let text = r.into_string().unwrap_or_default();
                let msg = serde_json::from_str::<Value>(&text).ok()
                    .and_then(|v| v.pointer("/error/message").and_then(Value::as_str).map(str::to_string))
                    .unwrap_or(text);
                bail!("DashScope ASR HTTP {code}: {msg}")
            }
            Err(e) => bail!("DashScope ASR: {e}"),
        };
        let message = reply.pointer("/choices/0/message").ok_or_else(|| anyhow!("DashScope ASR gave no result: {reply}"))?;
        let raw = message.get("content").and_then(Value::as_str).unwrap_or("").trim().to_string();
        let code = message.get("annotations").and_then(Value::as_array)
            .and_then(|a| a.iter().find_map(|x| x.get("language").and_then(Value::as_str)))
            .unwrap_or("");
        // The local engine's language names, so the rest of the server (and the game) need not tell them apart.
        let lang = match language {
            Some(l) => l.to_string(),
            None if raw.is_empty() => String::new(),
            None => language_name(code).to_string(),
        };
        Ok(Transcript { text: to_display(&lang, &raw), language: lang, raw, audio_seconds, asr_seconds: t.elapsed().as_secs_f64() })
    }
}

fn language_code(name: &str) -> Option<&'static str> {
    Some(match name.to_ascii_lowercase().as_str() {
        "chinese" => "zh",
        "cantonese" => "yue",
        "english" => "en",
        "japanese" => "ja",
        "korean" => "ko",
        _ => return None,
    })
}

fn language_name(code: &str) -> &str {
    match code {
        "zh" => "Chinese",
        "yue" => "Cantonese",
        "en" => "English",
        "ja" => "Japanese",
        "ko" => "Korean",
        other => other,
    }
}

/// 16-bit mono WAV at the model rate.
fn wav16(samples: &[f32]) -> Vec<u8> {
    let data = samples.len() * 2;
    let mut v = Vec::with_capacity(44 + data);
    v.extend_from_slice(b"RIFF");
    v.extend_from_slice(&((36 + data) as u32).to_le_bytes());
    v.extend_from_slice(b"WAVEfmt ");
    v.extend_from_slice(&16u32.to_le_bytes());
    v.extend_from_slice(&1u16.to_le_bytes());
    v.extend_from_slice(&1u16.to_le_bytes());
    v.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
    v.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes());
    v.extend_from_slice(&2u16.to_le_bytes());
    v.extend_from_slice(&16u16.to_le_bytes());
    v.extend_from_slice(b"data");
    v.extend_from_slice(&(data as u32).to_le_bytes());
    for s in samples {
        v.extend_from_slice(&((s.clamp(-1.0, 1.0) * 32767.0).round() as i16).to_le_bytes());
    }
    v
}
