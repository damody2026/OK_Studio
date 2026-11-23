//! What a long job is doing right now, for a UI to show while it waits.
//!
//! One slot for the whole process: the jobs that use it (wearing an outfit card) are the ones the reader runs one at
//! a time and blocks its own UI on. The worker thread writes, the game thread reads through `ok_progress_text`
//! (ffi.rs); neither blocks the other for more than a string copy.
//!
//! The weights are measured shares of the job, not guesses, so a bar drawn from `done` moves at roughly a constant
//! speed instead of sitting at one step. Re-measure them when the stages change
//! (`Docs/OK_CLOTHES_CARD.md`: 封裝 and 嚴格檢查 are about 80% of a wear between them).

use std::sync::Mutex;

#[derive(Clone, Default)]
pub struct Progress {
    /// What is happening, for a person to read.
    pub label: String,
    /// How much of the job is behind this step, 0..=1. 1 means finished.
    pub done: f32,
    /// Raised every time the slot changes, so a reader can tell "same text again" from "nothing is running".
    pub generation: u64,
    pub running: bool,
}

static SLOT: Mutex<Option<Progress>> = Mutex::new(None);

fn put(f: impl FnOnce(&mut Progress)) {
    let mut slot = SLOT.lock().unwrap_or_else(|e| e.into_inner());
    let mut p = slot.take().unwrap_or_default();
    let generation = p.generation + 1;
    f(&mut p);
    p.generation = generation;
    *slot = Some(p);
}

/// A job starts; `label` is its first step.
pub fn begin(label: &str) {
    put(|p| { p.label = label.to_owned(); p.done = 0.0; p.running = true; });
}
/// The job moved on. `done` is the share of the whole job that is behind this point.
pub fn step(label: &str, done: f32) {
    put(|p| { if p.running { p.label = label.to_owned(); p.done = done.clamp(0.0, 1.0); } });
}
/// The job ended (well or badly). The last label is kept so a UI can show how it ended.
pub fn end(label: &str) {
    put(|p| { p.label = label.to_owned(); p.done = 1.0; p.running = false; });
}
/// What the slot says now, or None when nothing ever ran.
pub fn current() -> Option<Progress> {
    SLOT.lock().unwrap_or_else(|e| e.into_inner()).clone()
}

/// Ends the job even when the work returns early or fails: every path out of `wear_into` has to leave the slot
/// saying "not running", or the reader's label would hang on the last step for ever.
pub struct Guard(&'static str);
impl Guard {
    pub fn begin(first: &str, ended: &'static str) -> Self { begin(first); Guard(ended) }
}
impl Drop for Guard {
    fn drop(&mut self) { end(self.0); }
}
