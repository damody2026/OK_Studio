//! `subtitles`: what she says, shown as a subtitle while a voice line plays (Subtitles, plan §14.1).
//!
//! `speech_start` brings the line's text (and the mode); the reply `{"subtitle": {"text", "seconds"}}` is shown by the
//! game. The reader sends `reader.speech_start` (the line chosen), the street `street.speech_start` (her reply, with the
//! heroine), the 1-on-1 scene `pair.speech_start` (work item 13); the same answer works for all.

use ok_mod_sdk::prelude::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct SpeechStart {
    #[serde(default)]
    text: String,
}

struct Subtitles {
    host: Host,
}

impl Mod for Subtitles {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Subtitles { host })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.config_float("seconds_per_char", 0.15, 0.02, 1.0, "mod.org.openkoikatsu.subtitles.config.seconds_per_char")
            .config_float("min_seconds", 2.0, 0.5, 10.0, "mod.org.openkoikatsu.subtitles.config.min_seconds")
            .subscribe("reader.speech_start")
            .subscribe("street.speech_start")
            .subscribe("pair.speech_start");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        if !name.as_str().ends_with(".speech_start") { return Ok(Reply::None); }
        let line: SpeechStart = hooks::parse(payload)?;
        let text = line.text.trim();
        if text.is_empty() { return Ok(Reply::None); }
        let per = self.host.config_float("seconds_per_char").unwrap_or(0.15);
        let min = self.host.config_float("min_seconds").unwrap_or(2.0);
        let seconds = (text.chars().count() as f64 * per).clamp(min, 30.0);
        hooks::json(&serde_json::json!({"subtitle": {"text": text, "seconds": seconds}}))
    }
}

ok_mod!(Subtitles);
