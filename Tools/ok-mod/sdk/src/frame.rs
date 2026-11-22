//! Per-frame calls (feature `frame`, proposed in Docs/OK_MOD_S11_FRAME.md): once per character per frame, after the
//! card's own bone modifiers, on the game's worker threads, several characters at the same time.
//!
//! ```ignore
//! fn frame(f: &mut ok_mod_sdk::frame::Frame) -> bool {
//!     let Some(neck) = f.find("cf_j_neck") else { return false };
//!     f.bones_mut()[neck].rot = tilt(f.bones()[neck].rot);
//!     true // bones changed
//! }
//! ok_mod_sdk::ok_mod_frame!(frame);
//! ```
//!
//! The function is not a method of the mod: it may run on any thread at any time, so whatever it shares with the mod
//! (settings, input) goes through `static` atomics or locks. Keep it short: each call is timed against the host's
//! budget (0.5 ms by default) and a mod over it 30 frames in a row is not called again this session; a panic stops it
//! at once.

use std::ffi::{c_char, CStr};

/// One bone's local transform (Unity space, the parent's frame).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Bone {
    pub pos: [f32; 3],
    pub rot: [f32; 4],
    pub scale: [f32; 3],
}

/// A push for this frame's physics: dynamic-bone chains whose root is within `radius` of `center` (world, Unity space)
/// get `force` added to their `m_Force`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Force {
    pub center: [f32; 3],
    pub radius: f32,
    pub force: [f32; 3],
    pub reserved: f32,
}

/// The frame as the host lays it out (Tools/ok-extract/src/mod_frame.rs `OkModFrame`).
#[repr(C)]
pub struct RawFrame {
    pub size: u32,
    pub kind: u32,
    pub character: u64,
    pub sex: i32,
    pub dt: f32,
    pub time: f32,
    pub bone_count: u32,
    pub names: *const *const c_char,
    pub bones: *mut Bone,
    pub worlds: *const [f32; 16],
    pub forces: *mut Force,
    pub force_cap: u32,
    pub force_count: u32,
}

/// One character's frame.
pub struct Frame<'a> {
    raw: &'a mut RawFrame,
}

impl<'a> Frame<'a> {
    /// # Safety
    /// `raw` is the host's frame, valid for `'a`.
    pub unsafe fn from_raw(raw: &'a mut RawFrame) -> Option<Self> {
        (raw.size as usize >= std::mem::size_of::<RawFrame>()).then_some(Frame { raw })
    }
    /// 0 = a character on its own (card reader, Studio), 1 = in a pair frame (1-on-1).
    pub fn kind(&self) -> u32 { self.raw.kind }
    /// Stable for the character's lifetime: key per-character state with it.
    pub fn character(&self) -> u64 { self.raw.character }
    pub fn is_female(&self) -> bool { self.raw.sex == 1 }
    /// Seconds since the last frame (0 in pair frames: keep your own clock there).
    pub fn dt(&self) -> f32 { self.raw.dt }
    pub fn time(&self) -> f32 { self.raw.time }
    pub fn len(&self) -> usize { self.raw.bone_count as usize }
    pub fn is_empty(&self) -> bool { self.len() == 0 }
    pub fn name(&self, i: usize) -> &str {
        if i >= self.len() { return ""; }
        // SAFETY: bone_count names, NUL-terminated, valid for the call.
        unsafe { CStr::from_ptr(*self.raw.names.add(i)).to_str().unwrap_or("") }
    }
    /// The index of a bone by name (a linear search: cache it per character).
    pub fn find(&self, name: &str) -> Option<usize> { (0..self.len()).find(|&i| self.name(i) == name) }
    pub fn bones(&self) -> &[Bone] {
        // SAFETY: bone_count bones, valid for the call.
        unsafe { std::slice::from_raw_parts(self.raw.bones, self.len()) }
    }
    /// Change locals here and return true from the frame function.
    pub fn bones_mut(&mut self) -> &mut [Bone] {
        // SAFETY: as bones(); the frame is borrowed mutably.
        unsafe { std::slice::from_raw_parts_mut(self.raw.bones, self.len()) }
    }
    /// A bone's world matrix before this frame's changes (row-major 4x4, Unity space).
    pub fn world(&self, i: usize) -> [f32; 16] {
        if i >= self.len() { return [0.0; 16]; }
        // SAFETY: bone_count matrices, valid for the call.
        unsafe { *self.raw.worlds.add(i) }
    }
    /// A bone's world position.
    pub fn world_pos(&self, i: usize) -> [f32; 3] {
        let m = self.world(i);
        [m[3], m[7], m[11]]
    }
    /// Adds a push for this frame's physics; false when the frame has no room left.
    pub fn push(&mut self, force: Force) -> bool {
        if self.raw.force_count >= self.raw.force_cap { return false; }
        // SAFETY: force_cap slots, valid for the call.
        unsafe { *self.raw.forces.add(self.raw.force_count as usize) = force };
        self.raw.force_count += 1;
        true
    }
}

/// Bit the exported function returns when the mod's function panicked (the host stops calling it).
pub const PANICKED: u32 = 0x8000_0000;

/// Exports `fn(&mut Frame) -> bool` (true = bones changed) as the mod's `ok_mod_frame`, with panic isolation.
#[macro_export]
macro_rules! ok_mod_frame {
    ($f:path) => {
        #[doc(hidden)]
        #[no_mangle]
        pub unsafe extern "C" fn ok_mod_frame(raw: *mut ::std::ffi::c_void) -> u32 {
            if raw.is_null() {
                return 0;
            }
            let raw = &mut *(raw as *mut $crate::frame::RawFrame);
            let Some(mut frame) = $crate::frame::Frame::from_raw(raw) else { return 0 };
            match ::std::panic::catch_unwind(::std::panic::AssertUnwindSafe(|| $f(&mut frame))) {
                Ok(true) => 1,
                Ok(false) => 0,
                Err(_) => $crate::frame::PANICKED,
            }
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lift(f: &mut Frame) -> bool {
        let Some(i) = f.find("b") else { return false };
        f.bones_mut()[i].pos[1] = 2.0;
        f.push(Force { center: [0.0; 3], radius: 1.0, force: [1.0, 0.0, 0.0], reserved: 0.0 })
    }
    fn boom(_: &mut Frame) -> bool { panic!("boom") }
    mod lift_export { crate::ok_mod_frame!(super::lift); }

    #[test]
    fn frame_view_and_export() {
        let names = [c"a".as_ptr(), c"b".as_ptr()];
        let mut bones = [Bone::default(); 2];
        let worlds = [[0.0f32; 16]; 2];
        let mut forces = [Force::default(); 1];
        let mut raw = RawFrame { size: std::mem::size_of::<RawFrame>() as u32, kind: 0, character: 1, sex: 1, dt: 0.0, time: 0.0,
            bone_count: 2, names: names.as_ptr(), bones: bones.as_mut_ptr(), worlds: worlds.as_ptr(), forces: forces.as_mut_ptr(),
            force_cap: 1, force_count: 0 };
        let r = unsafe { lift_export::ok_mod_frame(&mut raw as *mut RawFrame as *mut _) };
        assert_eq!(r, 1);
        assert_eq!(bones[1].pos[1], 2.0);
        assert_eq!(raw.force_count, 1);
        let mut frame = unsafe { Frame::from_raw(&mut raw) }.unwrap();
        assert!(!frame.push(Force::default()), "no room");
        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| boom(&mut frame)));
        assert!(caught.is_err());
    }
}
