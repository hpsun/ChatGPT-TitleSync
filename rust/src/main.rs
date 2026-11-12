#![cfg_attr(all(windows, not(test)), windows_subsystem = "windows")]
#[cfg(windows)]
mod autostart_windows;
mod lease;
mod name_rules;
mod settings;
#[cfg(windows)]
mod theme_windows;
mod three_layer;
#[cfg(target_os = "macos")]
mod tray_macos;
#[cfg(windows)]
mod tray_windows;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as native;
#[cfg(target_os = "macos")]
mod macos;
use lease::{Backend, Window};
#[cfg(target_os = "macos")]
use macos as native;
use std::{
    env, fs,
    io::{Read, Write},
    path::PathBuf,
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
static QUIT: AtomicBool = AtomicBool::new(false);
pub fn hex(s: &str) -> String {
    s.as_bytes().iter().map(|b| format!("{:02x}", b)).collect()
}
pub fn unhex(s: &str) -> Result<String, String> {
    if s.len() % 2 != 0 {
        return Err("hex".into());
    }
    let bytes: Result<Vec<_>, _> = (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16))
        .collect();
    String::from_utf8(bytes.map_err(|_| "hex")?).map_err(|_| "utf8".into())
}
pub fn encode(w: &Window) -> String {
    format!(
        "{}|{}|{}|{}|{}",
        w.handle,
        w.pid,
        w.start,
        hex(&w.class),
        hex(&w.exe)
    )
}
pub fn decode(s: &str) -> Result<Window, String> {
    let a: Vec<_> = s.split('|').collect();
    if a.len() != 5 {
        return Err("identity".into());
    }
    Ok(Window {
        handle: a[0].parse().map_err(|_| "handle")?,
        pid: a[1].parse().map_err(|_| "pid")?,
        start: a[2].parse().map_err(|_| "start")?,
        class: unhex(a[3])?,
        exe: unhex(a[4])?,
    })
}
fn name_child(w: &Window) -> Result<String, String> {
    name_child_mode(w, true, &QUIT)
}
fn name_child_mode(w: &Window, foreground: bool, cancel: &AtomicBool) -> Result<String, String> {
    let mut c = Command::new(env::current_exe().map_err(|_| "executable")?);
    c.args([
        if foreground {
            "--probe"
        } else {
            "--probe-background"
        },
        &encode(w),
    ])
    .stdout(Stdio::piped())
    .stderr(Stdio::null());
    native::hide_child(&mut c);
    if !foreground {
        native::background_child(&mut c);
    }
    let mut child = c.spawn().map_err(|_| "helper-start")?;
    let start = Instant::now();
    let revision = settings::LIVE.get().map(|s| s.get().revision);
    loop {
        if cancel.load(Ordering::Relaxed)
            || QUIT.load(Ordering::Relaxed)
            || settings::LIVE
                .get()
                .map(|s| {
                    let v = s.get();
                    !v.enabled || Some(v.revision) != revision
                })
                .unwrap_or(false)
            || !native::same(w)
            || native::active(w) != foreground
            || native::stop_requested()
            || start.elapsed() > Duration::from_secs(4)
        {
            let _ = child.kill();
            let _ = child.wait();
            return Err("helper-canceled-or-timeout".into());
        }
        match child.try_wait() {
            Ok(Some(s)) => {
                if !s.success() {
                    return Err("helper-failed".into());
                }
                let mut data = String::new();
                if let Some(out) = child.stdout.take() {
                    out.take(32769)
                        .read_to_string(&mut data)
                        .map_err(|_| "helper-output")?;
                }
                if data.len() > 32768 {
                    return Err("helper-output".into());
                }
                return unhex(data.trim());
            }
            Ok(None) => thread::sleep(Duration::from_millis(30)),
            Err(_) => return Err("helper-wait".into()),
        }
    }
}
struct Native;
impl Backend for Native {
    fn list(&mut self) -> Result<Vec<Window>, String> {
        native::list()
    }
    fn active(&self, w: &Window) -> bool {
        native::active(w)
    }
    fn set_active(&mut self, w: &Window, a: &str, b: &str) -> Result<(), String> {
        native::set_active(w, a, b)
    }
    fn set_inactive(&mut self, w: &Window, a: &str, b: &str) -> Result<(), String> {
        native::set_inactive(w, a, b)
    }
    fn same(&self, w: &Window) -> bool {
        native::same(w)
    }
    fn caption(&self, w: &Window) -> Result<String, String> {
        native::caption(w)
    }
    fn set(&mut self, w: &Window, a: &str, b: &str) -> Result<(), String> {
        native::set(w, a, b)
    }
    fn name(&mut self, w: &Window) -> Result<String, String> {
        #[cfg(windows)]
        {
            name_child(w)
        }
        #[cfg(target_os = "macos")]
        {
            native::read_name(w)
        }
    }
}
struct Lock {
    path: PathBuf,
    token: String,
}
impl Drop for Lock {
    fn drop(&mut self) {
        if fs::read_to_string(&self.path).ok().as_deref() == Some(&self.token) {
            let _ = fs::remove_file(&self.path);
        }
    }
}
fn lock(dir: &std::path::Path) -> Result<Lock, String> {
    let path = dir.join("owner");
    let (start, exe) = native::process_identity(std::process::id())?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let token = format!("{}|{}|{}|{}", std::process::id(), start, hex(&exe), nonce);
    for _ in 0..2 {
        match fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&path)
        {
            Ok(mut f) => {
                f.write_all(token.as_bytes()).map_err(|_| "lock-write")?;
                return Ok(Lock { path, token });
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                if let Ok(old) = fs::read_to_string(&path) {
                    let a: Vec<_> = old.split('|').collect();
                    if a.len() == 4 {
                        if let (Ok(pid), Ok(stamp), Ok(oldexe)) =
                            (a[0].parse(), a[1].parse::<u64>(), unhex(a[2]))
                        {
                            if native::process_identity(pid)
                                .is_ok_and(|p| p.0 == stamp && p.1 == oldexe)
                            {
                                return Err("already-running".into());
                            }
                        }
                    }
                }
                fs::remove_file(&path).map_err(|_| "stale-lock")?;
            }
            Err(_) => return Err("lock-access".into()),
        }
    }
    Err("lock-race".into())
}
fn run() -> Result<(), String> {
    let a: Vec<_> = env::args().skip(1).collect();
    let has = |s: &str| a.iter().any(|x| x == s);
    let mut i = 0;
    while i < a.len() {
        match a[i].as_str() {
            "--state-dir"
            | "--probe"
            | "--probe-background"
            | "--interval"
            | "--background-interval" => {
                i += 1;
                if i >= a.len() {
                    return Err("missing-option-value".into());
                }
            }
            "--once" | "--read-only" | "--stop" | "--pause" | "--resume" | "--self-test"
            | "--help" | "--no-tray" => {}
            _ => return Err("unknown-option".into()),
        }
        i += 1;
    }
    let interval = if let Some(i) = a.iter().position(|x| x == "--interval") {
        a.get(i + 1)
            .ok_or("interval")?
            .parse::<u64>()
            .map_err(|_| "interval")?
    } else {
        settings::DEFAULT_FOREGROUND
    };
    if !(1..=3600).contains(&interval) {
        return Err("interval-range".into());
    }
    let background = if let Some(i) = a.iter().position(|x| x == "--background-interval") {
        a.get(i + 1)
            .ok_or("background-interval")?
            .parse::<u64>()
            .map_err(|_| "background-interval")?
    } else {
        settings::DEFAULT_BACKGROUND
    };
    if !(5..=3600).contains(&background) {
        return Err("background-interval-range".into());
    }
    if has("--help") {
        println!("--once --read-only --stop --pause --resume --state-dir PATH --interval SECONDS --background-interval SECONDS --self-test --no-tray (defaults: foreground 2 seconds, background 5 seconds)");
        return Ok(());
    }
    if let Some(i) = a
        .iter()
        .position(|s| s == "--probe" || s == "--probe-background")
    {
        let w = decode(a.get(i + 1).ok_or("identity")?)?;
        let foreground = a[i] == "--probe";
        if native::active(&w) != foreground || !native::same(&w) {
            return Err("identity".into());
        }
        let title = native::read_name_mode(&w, foreground)?;
        if native::active(&w) != foreground || !native::same(&w) {
            return Err("identity".into());
        }
        if title.chars().count() > 240 {
            return Err("root-name-too-long".into());
        }
        println!("{}", hex(&title));
        return Ok(());
    }
    if has("--self-test") {
        native::self_test()?;
        println!("owned-native-fixture-passed");
        return Ok(());
    }
    #[cfg(windows)]
    if has("--stop") {
        return native::request_stop();
    }
    let base = env::var_os("APPDATA")
        .or_else(|| env::var_os("HOME"))
        .map(PathBuf::from)
        .ok_or("state-directory")?;
    let dir = if let Some(i) = a.iter().position(|s| s == "--state-dir") {
        PathBuf::from(a.get(i + 1).ok_or("state-directory")?)
    } else {
        // Compatibility: preserve the historical state directory and ownership/control files across the visible product rename.
        base.join("ChatGPT-title-rust")
    };
    fs::create_dir_all(&dir).map_err(|_| "state-directory")?;
    for (flag, file) in [("--stop", "stop"), ("--pause", "pause")] {
        if has(flag) {
            fs::write(dir.join(file), b"requested").map_err(|_| "control-write")?;
            return Ok(());
        }
    }
    if has("--resume") {
        let _ = fs::remove_file(dir.join("pause"));
        return Ok(());
    }
    native::acquire()?;
    let _lock = lock(&dir)?;
    let _ = fs::remove_file(dir.join("stop"));
    native::install_stop_handler();
    if has("--once") {
        let mut cache =
            three_layer::Cache::new(Native, has("--read-only"), Duration::from_secs(background));
        if let Some(job) = cache.foreground_job(Instant::now()) {
            #[cfg(windows)]
            let result = name_child_mode(&job.w, true, &QUIT);
            #[cfg(target_os = "macos")]
            let result = native::read_name_mode(&job.w, true);
            cache.apply(job, result, Instant::now());
        }
        cache.restore();
        native::cleanup();
        return Ok(());
    }

    let path = dir.join("settings.conf");
    let mut initial = settings::load(
        &path,
        settings::Values {
            foreground: interval,
            background,
            enabled: true,
            autostart: true,
            revision: 0,
        },
    );
    if has("--interval") {
        initial.foreground = interval
    }
    if has("--background-interval") {
        initial.background = background
    }
    // Only the normal singleton-owning resident may consult shared autostart preferences.
    #[cfg(windows)]
    let startup: Option<std::sync::Arc<dyn settings::Startup>> = if !has("--read-only") {
        let control = std::sync::Arc::new(autostart_windows::WindowsStartup::production()?);
        initial.autostart = control.load()?;
        let _undo = settings::Startup::apply(control.as_ref(), initial.autostart)?;
        Some(control)
    } else {
        None
    };
    #[cfg(target_os = "macos")]
    let startup: Option<std::sync::Arc<dyn settings::Startup>> = None;
    let live = std::sync::Arc::new(settings::Live::with_startup(path, initial, startup));
    let _ = settings::LIVE.set(live.clone());
    let work = || {
        let mut cache = three_layer::Cache::new(
            Native,
            has("--read-only"),
            Duration::from_secs(initial.background),
        );
        if !has("--read-only") {
            cache.rules = Some(name_rules::Client::new(dir.clone()));
        }
        let read: three_layer::Read = std::sync::Arc::new(|w, fg, cancel| {
            #[cfg(windows)]
            {
                name_child_mode(w, fg, cancel)
            }
            #[cfg(target_os = "macos")]
            {
                if cancel.load(Ordering::Relaxed) {
                    Err("stopped".into())
                } else {
                    native::read_name_mode(w, fg)
                }
            }
        });
        let discover: three_layer::Discover = std::sync::Arc::new(|| native::list_all());
        three_layer::run_live(
            cache,
            Duration::from_secs(initial.foreground),
            read,
            discover,
            || {
                let stop = QUIT.load(Ordering::Relaxed)
                    || native::stop_requested()
                    || dir.join("stop").exists();
                if stop {
                    QUIT.store(true, Ordering::Relaxed);
                }
                (stop, dir.join("pause").exists() || !live.get().enabled)
            },
            || {
                let v = live.get();
                (
                    Duration::from_secs(v.foreground),
                    Duration::from_secs(v.background),
                )
            },
        );
    };
    let result = if has("--no-tray") || has("--read-only") {
        work();
        Ok(())
    } else {
        #[cfg(windows)]
        {
            tray_windows::run(live.clone(), work)
        }
        #[cfg(target_os = "macos")]
        {
            tray_macos::run(live.clone(), work)
        }
    };
    native::cleanup();
    result?;
    Ok(())
}
fn main() {
    if let Err(e) = run() {
        eprintln!("error={}", e);
        std::process::exit(1)
    }
}

fn advance_deadline(previous: Instant, now: Instant, interval: Duration) -> Instant {
    let mut next = previous + interval;
    while next < now {
        next += interval;
    }
    next
}
#[cfg(test)]
mod schedule_tests {
    use super::*;
    #[test]
    fn no_completion_drift() {
        let b = Instant::now();
        assert_eq!(
            advance_deadline(b, b + Duration::from_millis(200), Duration::from_secs(1)),
            b + Duration::from_secs(1)
        );
    }
    #[test]
    fn skip_missed() {
        let b = Instant::now();
        assert_eq!(
            advance_deadline(b, b + Duration::from_millis(3200), Duration::from_secs(1)),
            b + Duration::from_secs(4)
        );
    }
}

#[cfg(test)]
mod exact_schedule_test {
    use super::*;
    #[test]
    fn due_now_no_extra_sleep() {
        let b = Instant::now();
        assert_eq!(
            advance_deadline(b, b + Duration::from_secs(1), Duration::from_secs(1)),
            b + Duration::from_secs(1)
        );
    }
}
