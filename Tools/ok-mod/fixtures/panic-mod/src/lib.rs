//! Test fixture: panics on purpose so the host must disable it and keep running.
//! Where it panics comes from the `OK_MOD_TEST_PANIC_AT` environment variable:
//! `create`, `register`, `enabled`, `mode_enter` or `command` (default `command`, i.e. the
//! console command `mod.org.openkoikatsu.test.panic.boom`).

use ok_mod_sdk::prelude::*;

struct PanicMod {
    at: String,
}

fn maybe_panic(at: &str, here: &str) {
    if at == here {
        panic!("deliberate panic in {here}");
    }
}

impl Mod for PanicMod {
    fn create(_host: Host) -> ModResult<Self> {
        let at = std::env::var("OK_MOD_TEST_PANIC_AT").unwrap_or_else(|_| "command".into());
        maybe_panic(&at, "create");
        Ok(PanicMod { at })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        maybe_panic(&self.at, "register");
        reg.command("boom", "mod.org.openkoikatsu.test.panic.cmd.boom").subscribe("mode_enter");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        maybe_panic(&self.at, event.name());
        Ok(Reply::None)
    }
}

ok_mod!(PanicMod);
