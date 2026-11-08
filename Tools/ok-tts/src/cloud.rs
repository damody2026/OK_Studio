//! Cloud backend: the lines are made by Alibaba Cloud Model Studio (百煉, DashScope) instead of the local GPU model.
//!
//! Each voice of voices.json (personality x age) becomes one cloud voice, designed once from its description
//! (voice-enrollment, `create_voice`) and remembered in a local file, so a heroine keeps the same voice. Lines are
//! synthesized with that voice (`SpeechSynthesizer`; SSE for /synthesize_stream). The server's HTTP contract, cache
//! files and OGG output stay the same, so the game does not know which backend made a line.
//!
//! Key: DASHSCOPE_API_KEY, else "aliyun"."api_key" of the user's key file %LOCALAPPDATA%\OpenKoikatsu\api-keys.json
//! (OK_API_KEYS names another file). With a key the cloud is the default; without one there is no cloud. The key
//! never goes into the repository.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use base64::Engine as _;
use serde_json::{json, Value};
use sha1_smol::Sha1;

use crate::engine::SAMPLE_RATE;
use crate::text::VoiceChoice;

pub const DEFAULT_MODEL: &str = "qwen-audio-3.1-tts-flash";
const CACHE_VERSION: &str = "ok-tts-cloud-1";
/// voice-enrollment's preview line (15..200 characters).
const PREVIEW_TEXT: &str = "你好，今天天气真好，我们一起去散步吧。";
const MAX_PROMPT_CHARS: usize = 500;

/// The user's API key file (Docs/API_KEYS.md): OK_API_KEYS, else %LOCALAPPDATA%\OpenKoikatsu\api-keys.json.
/// {"deepseek": {...}, "aliyun": {"api_key", "base_url", "tts_model", "asr_model"}}; a service without a key is off.
pub fn config_path() -> PathBuf {
    if let Some(p) = std::env::var_os("OK_API_KEYS").filter(|p| !p.is_empty()) {
        return PathBuf::from(p);
    }
    let base = std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
    base.join("OpenKoikatsu").join("api-keys.json")
}

/// The "aliyun" section of the key file.
fn config() -> Value {
    std::fs::read_to_string(config_path()).ok()
        .and_then(|s| serde_json::from_str::<Value>(s.trim_start_matches('\u{feff}')).ok())
        .and_then(|v| v.get("aliyun").cloned())
        .unwrap_or_else(|| json!({}))
}

fn setting(cfg: &Value, env: &str, field: &str) -> Option<String> {
    std::env::var(env).ok().filter(|v| !v.trim().is_empty())
        .or_else(|| cfg.get(field).and_then(Value::as_str).map(str::to_string))
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// An Alibaba Cloud key is set (DASHSCOPE_API_KEY or the key file): the cloud is used unless OK_TTS_BACKEND or
/// --backend asks for a local model.
pub fn wanted() -> bool {
    setting(&config(), "DASHSCOPE_API_KEY", "api_key").is_some()
}

pub struct Cloud {
    key: String,
    base_url: String,
    pub model: String,
    agent: ureq::Agent,
    voices_path: PathBuf,
    /// voice key (see `voice_key`) -> cloud voice id
    voices: Mutex<HashMap<String, String>>,
    /// One voice is designed at a time, so two requests for a new voice do not make it twice.
    creating: Mutex<()>,
}

impl Cloud {
    pub fn new(model: Option<&str>) -> Result<Self> {
        let cfg = config();
        let key = setting(&cfg, "DASHSCOPE_API_KEY", "api_key")
            .ok_or_else(|| anyhow!("no Alibaba Cloud API key: set DASHSCOPE_API_KEY or \"aliyun\".\"api_key\" in {}", config_path().display()))?;
        let base_url = setting(&cfg, "DASHSCOPE_BASE_URL", "base_url").unwrap_or_else(|| "https://dashscope.aliyuncs.com".into());
        let model = model.map(str::to_string).or_else(|| setting(&cfg, "OK_TTS_CLOUD_MODEL", "tts_model")).unwrap_or_else(|| DEFAULT_MODEL.into());
        let voices_path = config_path().with_file_name(format!("ok-tts-cloud-voices-{}.json", model));
        let voices: HashMap<String, String> = std::fs::read_to_string(&voices_path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
        let agent = ureq::AgentBuilder::new().try_proxy_from_env(true).timeout_connect(Duration::from_secs(15)).timeout_read(Duration::from_secs(60)).build();
        crate::log!("ok-tts: backend cloud ({model} at {base_url}), {} voices designed earlier ({})", voices.len(), voices_path.display());
        Ok(Self { key, base_url: base_url.trim_end_matches('/').to_string(), model, agent, voices_path, voices: Mutex::new(voices), creating: Mutex::new(()) })
    }

    /// Where a line in this voice is cached: keyed on the cloud model and the voice's description, apart from the
    /// local backends' files.
    pub fn cache_path(&self, out_dir: &Path, voice: &VoiceChoice, text: &str) -> PathBuf {
        let mut digest = Sha1::new();
        digest.update(format!("{CACHE_VERSION}|{}|{}|{text}", self.model, voice.instruct).as_bytes());
        out_dir.join(format!("{}.ogg", digest.digest()))
    }

    fn post(&self, path: &str, body: &Value, sse: bool) -> Result<ureq::Response> {
        let mut req = self.agent.post(&format!("{}{path}", self.base_url))
            .set("Authorization", &format!("Bearer {}", self.key))
            .set("Content-Type", "application/json");
        if sse {
            req = req.set("X-DashScope-SSE", "enable");
        }
        match req.send_string(&body.to_string()) {
            Ok(r) => Ok(r),
            Err(ureq::Error::Status(code, r)) => {
                let text = r.into_string().unwrap_or_default();
                bail!("DashScope {path} HTTP {code}: {}", api_error(&text).unwrap_or(text))
            }
            Err(e) => Err(anyhow!("DashScope {path}: {e}")),
        }
    }

    /// The cloud voice of a voice design, designed on first use and remembered.
    pub fn voice_id(&self, voice: &VoiceChoice) -> Result<String> {
        let key = voice_key(voice);
        if let Some(id) = self.voices.lock().unwrap().get(&key) {
            return Ok(id.clone());
        }
        let _one = self.creating.lock().unwrap();
        if let Some(id) = self.voices.lock().unwrap().get(&key) {
            return Ok(id.clone());
        }
        let t = std::time::Instant::now();
        let prompt: String = voice.instruct.chars().take(MAX_PROMPT_CHARS).collect();
        let body = json!({
            "model": "voice-enrollment",
            "input": {"action": "create_voice", "target_model": self.model, "voice_prompt": prompt, "preview_text": PREVIEW_TEXT,
                      "prefix": prefix(voice), "language_hints": ["zh"]},
            "parameters": {"sample_rate": SAMPLE_RATE, "response_format": "wav"},
        });
        let reply: Value = serde_json::from_str(&self.post("/api/v1/services/audio/tts/customization", &body, false)?.into_string()?)?;
        let id = reply.pointer("/output/voice_id").and_then(Value::as_str)
            .ok_or_else(|| anyhow!("voice design gave no voice_id: {}", api_error(&reply.to_string()).unwrap_or_default()))?
            .to_string();
        crate::log!("ok-tts: cloud voice {key} -> {id} ({:.1}s)", t.elapsed().as_secs_f64());
        let mut all = self.voices.lock().unwrap();
        all.insert(key, id.clone());
        let body = serde_json::to_vec_pretty(&*all)?;
        if let Some(dir) = self.voices_path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        crate::audio::write_atomic(&self.voices_path, &body).with_context(|| format!("write {}", self.voices_path.display()))?;
        Ok(id)
    }

    fn synth_body(&self, text: &str, voice: &VoiceChoice) -> Result<Value> {
        Ok(json!({"model": self.model, "input": {"text": text, "voice": self.voice_id(voice)?},
                  "parameters": {"sample_rate": SAMPLE_RATE, "format": "wav"}}))
    }

    /// One line, whole (24 kHz mono).
    pub fn speak(&self, text: &str, voice: &VoiceChoice) -> Result<Vec<f32>> {
        let body = self.synth_body(text, voice)?;
        let reply: Value = serde_json::from_str(&self.post("/api/v1/services/audio/tts/SpeechSynthesizer", &body, false)?.into_string()?)?;
        let url = reply.pointer("/output/audio/url").and_then(Value::as_str)
            .ok_or_else(|| anyhow!("synthesis gave no audio: {}", api_error(&reply.to_string()).unwrap_or_default()))?;
        let mut wav = Vec::new();
        self.agent.get(url).call().map_err(|e| anyhow!("audio download: {e}"))?.into_reader().read_to_end(&mut wav)?;
        let mut pcm = Pcm::default();
        pcm.push(&wav)?;
        Ok(pcm.take())
    }

    /// One line as it arrives (SSE): `sink` gets each piece; returns the whole line.
    pub fn speak_stream(&self, text: &str, voice: &VoiceChoice, sink: &mut dyn FnMut(&[f32]) -> Result<()>) -> Result<Vec<f32>> {
        let body = self.synth_body(text, voice)?;
        let reader = BufReader::new(self.post("/api/v1/services/audio/tts/SpeechSynthesizer", &body, true)?.into_reader());
        let mut pcm = Pcm::default();
        let mut all = Vec::new();
        for line in reader.lines() {
            let line = line?;
            let Some(data) = line.strip_prefix("data:") else { continue };
            let event: Value = serde_json::from_str(data.trim()).with_context(|| format!("SSE event: {data}"))?;
            if let Some(e) = api_error(&event.to_string()) {
                bail!("DashScope synthesis: {e}");
            }
            let Some(b64) = event.pointer("/output/audio/data").and_then(Value::as_str).filter(|s| !s.is_empty()) else { continue };
            pcm.push(&base64::engine::general_purpose::STANDARD.decode(b64).context("audio piece")?)?;
            let piece = pcm.take();
            if !piece.is_empty() {
                sink(&piece)?;
                all.extend_from_slice(&piece);
            }
        }
        Ok(all)
    }
}

/// The error text of a DashScope reply ({"code", "message"}), if it is one.
fn api_error(body: &str) -> Option<String> {
    let v: Value = serde_json::from_str(body).ok()?;
    let code = v.get("code").and_then(Value::as_str).filter(|c| !c.is_empty())?;
    Some(format!("{code}: {}", v.get("message").and_then(Value::as_str).unwrap_or("")))
}

/// Which design a cloud voice was made from: personality, age and the description itself (a changed description
/// makes a new voice).
fn voice_key(voice: &VoiceChoice) -> String {
    let mut d = Sha1::new();
    d.update(voice.instruct.as_bytes());
    format!("{}@{}#{}", voice.key, voice.age, &d.digest().to_string()[..10])
}

/// voice-enrollment's prefix: letters and digits, at most 10 ("m" for a minus sign).
fn prefix(voice: &VoiceChoice) -> String {
    let mut p = String::from("ok");
    for c in format!("{}a{}", voice.key, voice.age).chars() {
        match c {
            '-' => p.push('m'),
            c if c.is_ascii_alphanumeric() => p.push(c),
            _ => {}
        }
    }
    p.chars().take(10).collect()
}

/// 16-bit PCM from a WAV (whole, or the first piece of a stream) and the raw pieces after it.
#[derive(Default)]
struct Pcm {
    header_done: bool,
    head: Vec<u8>,
    carry: Option<u8>,
    out: Vec<f32>,
}

impl Pcm {
    fn push(&mut self, bytes: &[u8]) -> Result<()> {
        let body: Vec<u8>;
        let mut data: &[u8] = bytes;
        if !self.header_done {
            self.head.extend_from_slice(bytes);
            if !self.head.starts_with(b"RIFF") {
                if self.head.len() < 4 {
                    return Ok(());
                }
                // Raw PCM from the start.
                self.header_done = true;
                body = std::mem::take(&mut self.head);
                data = &body;
            } else {
                let Some((rate, at)) = wav_data_start(&self.head)? else { return Ok(()) };
                if rate != SAMPLE_RATE {
                    bail!("cloud audio is {rate} Hz, not {SAMPLE_RATE}");
                }
                self.header_done = true;
                body = self.head.split_off(at);
                self.head.clear();
                data = &body;
            }
        }
        let mut i = 0;
        if let Some(lo) = self.carry.take() {
            if let Some(&hi) = data.first() {
                self.out.push(i16::from_le_bytes([lo, hi]) as f32 / 32768.0);
                i = 1;
            } else {
                self.carry = Some(lo);
            }
        }
        while i + 1 < data.len() {
            self.out.push(i16::from_le_bytes([data[i], data[i + 1]]) as f32 / 32768.0);
            i += 2;
        }
        if i < data.len() {
            self.carry = Some(data[i]);
        }
        Ok(())
    }

    fn take(&mut self) -> Vec<f32> {
        std::mem::take(&mut self.out)
    }
}

/// (sample rate, offset of the samples) once the header up to the "data" chunk is there; mono 16-bit only.
fn wav_data_start(b: &[u8]) -> Result<Option<(u32, usize)>> {
    let mut at = 12;
    let mut rate = None;
    while at + 8 <= b.len() {
        let id = &b[at..at + 4];
        let size = u32::from_le_bytes([b[at + 4], b[at + 5], b[at + 6], b[at + 7]]) as usize;
        if id == b"data" {
            return Ok(rate.map(|r| (r, at + 8)));
        }
        if at + 8 + size > b.len() {
            return Ok(None);
        }
        if id == b"fmt " {
            let f = &b[at + 8..at + 8 + size];
            let channels = u16::from_le_bytes([f[2], f[3]]);
            let bits = u16::from_le_bytes([f[14], f[15]]);
            if channels != 1 || bits != 16 {
                bail!("cloud audio is {channels} channels / {bits} bits, not mono 16-bit");
            }
            rate = Some(u32::from_le_bytes([f[4], f[5], f[6], f[7]]));
        }
        at += 8 + size + (size & 1);
    }
    Ok(None)
}
