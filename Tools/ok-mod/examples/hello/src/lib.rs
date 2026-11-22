//! `hello`: the smallest OK mod (Docs/OK_MOD_FRAMEWORK_PLAN.md §14.1).
//! Logs when enabled and on every mode change, has one config entry and the console command
//! `mod.org.openkoikatsu.hello.ping`.

use ok_mod_sdk::prelude::*;

struct Hello {
    host: Host,
    pings: u64,
}

impl Mod for Hello {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Hello { host, pings: 0 })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.config_text("greeting", "hello", "mod.org.openkoikatsu.hello.config.greeting")
            .command("ping", "mod.org.openkoikatsu.hello.cmd.ping")
            .subscribe("mode_enter")
            .subscribe("mode_exit");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Enabled => {
                let greeting = self.host.config_text("greeting").unwrap_or_default();
                self.host.info(format!("{greeting} from hello (host {})", self.host.host_version()));
            }
            Event::ModeEnter { mode } => self.host.info(format!("entered mode {mode}")),
            Event::ModeExit { mode } => self.host.info(format!("left mode {mode}")),
            Event::Command { name, args } if name == "ping" => {
                self.pings += 1;
                let greeting = self.host.config_text("greeting").unwrap_or_default();
                return Ok(Reply::Text(format!("pong {} ({greeting}) {args}", self.pings).trim_end().into()));
            }
            Event::Command { name, .. } => return Err(format!("unknown command {name}")),
            _ => {}
        }
        Ok(Reply::None)
    }
}

ok_mod!(Hello);
