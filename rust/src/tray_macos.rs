//! Experimental public AppleScriptObjC menu companion. Requires system osascript.
use crate::settings::Live;
use std::{
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};
pub fn run(s: Arc<Live>, work: impl FnOnce()) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    if !exe.is_absolute() {
        return Err("autostart-executable-must-be-absolute".into());
    }
    let dir = exe.parent().ok_or("exe-parent")?;
    let script = [
        dir.join("TraySettings.applescript"),
        dir.join("../macos/TraySettings.applescript"),
        dir.join("../../../macos/TraySettings.applescript"),
        dir.join("macos/TraySettings.applescript"),
    ]
    .into_iter()
    .find(|p| p.is_file())
    .ok_or("missing public TraySettings.applescript; use --no-tray for CLI controls")?;
    let v = s.get();
    let parent = s.path.parent().ok_or("settings-parent")?;
    let ready = parent.join(format!("tray-ready-{}", std::process::id()));
    let stop = parent.join("stop");
    let icon = script
        .parent()
        .unwrap()
        .join("../assets/chatgpt-titlesync-icon.png");
    let mut child = Command::new("/usr/bin/osascript")
        .arg(&script)
        .arg(&s.path)
        .arg(&stop)
        .arg("conf")
        .arg(v.foreground.to_string())
        .arg(v.background.to_string())
        .arg(v.enabled.to_string())
        .arg(&ready)
        .arg(icon)
        .arg("Rust")
        .arg(v.autostart.to_string())
        .arg(&exe)
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| format!("menu companion: {e}; use --no-tray for CLI controls"))?;
    let started = Instant::now();
    while !ready.exists() {
        if child.try_wait().map_err(|e| e.to_string())?.is_some() {
            return Err(
                "menu companion exited before ready; use --no-tray for CLI controls".into(),
            );
        }
        if started.elapsed() > Duration::from_secs(8) {
            let _ = child.kill();
            let _ = child.wait();
            return Err("menu companion startup timeout; use --no-tray for CLI controls".into());
        }
        thread::sleep(Duration::from_millis(50));
    }
    let _ = std::fs::remove_file(ready);
    let done = Arc::new(AtomicBool::new(false));
    let finish = done.clone();
    let watch = thread::spawn(move || {
        while !finish.load(Ordering::Relaxed) {
            s.reload();
            match child.try_wait() {
                Ok(Some(_)) => {
                    crate::QUIT.store(true, Ordering::Relaxed);
                    return Err("menu companion exited".to_owned());
                }
                Err(e) => {
                    crate::QUIT.store(true, Ordering::Relaxed);
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(e.to_string());
                }
                _ => {}
            }
            thread::sleep(Duration::from_millis(100));
        }
        let _ = child.kill();
        let _ = child.wait();
        Ok(())
    });
    work();
    done.store(true, Ordering::Relaxed);
    let result = watch
        .join()
        .map_err(|_| "menu companion watcher".to_owned())?;
    if stop.exists() {
        Ok(())
    } else {
        result
    }
}
