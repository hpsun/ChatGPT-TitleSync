pub const DEFAULT_FOREGROUND: u64 = 2;
pub const DEFAULT_BACKGROUND: u64 = 5;
use std::{
    fs,
    io::Write,
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock},
};
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Values {
    pub foreground: u64,
    pub background: u64,
    pub enabled: bool,
    pub autostart: bool,
    pub revision: u64,
}
impl Values {
    pub fn valid(&self) -> bool {
        (1..=3600).contains(&self.foreground) && (5..=3600).contains(&self.background)
    }
}
pub struct Live {
    pub path: PathBuf,
    value: Mutex<Values>,
    commit: Mutex<()>,
    startup: Option<Arc<dyn Startup>>,
}
pub type UndoStartup = Box<dyn FnOnce() -> Result<(), String> + Send>;
pub trait Startup: Send + Sync {
    fn apply(&self, enabled: bool) -> Result<UndoStartup, String>;
}
// Optional UI additions join startup and timing persistence, without changing the file format.
pub trait SettingsExtra {
    fn prepare(&mut self) -> Result<(), String>;
    fn finish(&mut self) -> Result<(), String>;
    fn rollback(&mut self) -> Result<(), String>;
}
fn rollback_settings(
    extra: &mut Option<&mut dyn SettingsExtra>,
    startup: Option<UndoStartup>,
    file: Option<&Option<Vec<u8>>>,
    path: &std::path::Path,
    cause: String,
) -> String {
    let mut errors = vec![cause];
    if let Some(tx) = extra.as_mut() {
        if let Err(e) = tx.rollback() {
            errors.push(e)
        }
    }
    if let Some(saved) = file {
        let result = match saved {
            Some(bytes) => (|| {
                let temp = path.with_extension("rollback.tmp");
                let result = (|| {
                    let mut f = fs::File::create(&temp).map_err(|e| e.to_string())?;
                    f.write_all(bytes).map_err(|e| e.to_string())?;
                    f.sync_all().map_err(|e| e.to_string())?;
                    drop(f);
                    replace(&temp, path)
                })();
                let _ = fs::remove_file(temp);
                result
            })(),
            None => match fs::remove_file(path) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.to_string()),
                _ => Ok(()),
            },
        };
        if let Err(e) = result {
            errors.push(format!("settings rollback failed: {e}"))
        }
    }
    if let Some(undo) = startup {
        if let Err(e) = undo() {
            errors.push(format!("autostart rollback failed: {e}"))
        }
    }
    errors.join("; ")
}
pub static LIVE: OnceLock<Arc<Live>> = OnceLock::new();
impl Live {
    pub fn new(path: PathBuf, value: Values) -> Self {
        Self {
            path,
            value: Mutex::new(value),
            commit: Mutex::new(()),
            startup: None,
        }
    }
    pub fn with_startup(path: PathBuf, value: Values, startup: Option<Arc<dyn Startup>>) -> Self {
        Self {
            path,
            value: Mutex::new(value),
            commit: Mutex::new(()),
            startup,
        }
    }
    pub fn get(&self) -> Values {
        *self.value.lock().unwrap()
    }
    pub fn save(&self, value: Values) -> Result<(), String> {
        self.save_extra(value, None)
    }
    pub fn save_extra(
        &self,
        mut value: Values,
        mut extra: Option<&mut dyn SettingsExtra>,
    ) -> Result<(), String> {
        if !value.valid() {
            return Err("前台间隔需为1–3600秒，后台间隔需为5–3600秒".into());
        }
        let _commit = self.commit.lock().unwrap();
        let old = self.get();
        let undo = if old.autostart != value.autostart {
            self.startup
                .as_ref()
                .map(|s| s.apply(value.autostart))
                .transpose()?
        } else {
            None
        };
        let previous = if extra.is_some() {
            match fs::read(&self.path) {
                Ok(b) => Some(b),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => {
                    return Err(rollback_settings(
                        &mut extra,
                        undo,
                        None,
                        &self.path,
                        e.to_string(),
                    ))
                }
            }
        } else {
            None
        };
        if let Some(tx) = extra.as_mut() {
            if let Err(e) = tx.prepare() {
                return Err(rollback_settings(&mut extra, undo, None, &self.path, e));
            }
        }
        let result = (|| {
            let parent = self.path.parent().ok_or("settings-parent")?;
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            let temp = parent.join(format!("settings-{}.tmp", std::process::id()));
            let result = (|| {
                let mut f = fs::File::create(&temp).map_err(|e| e.to_string())?;
                write!(f,"foreground_seconds={}\nbackground_seconds={}\nenabled={}\nautostart_enabled={}\n",value.foreground,value.background,value.enabled,value.autostart).map_err(|e|e.to_string())?;
                f.sync_all().map_err(|e| e.to_string())?;
                drop(f);
                replace(&temp, &self.path)
            })();
            let _ = fs::remove_file(temp);
            result
        })();
        if let Err(e) = result {
            return Err(rollback_settings(&mut extra, undo, None, &self.path, e));
        }
        if let Some(tx) = extra.as_mut() {
            if let Err(e) = tx.finish() {
                return Err(rollback_settings(
                    &mut extra,
                    undo,
                    Some(&previous),
                    &self.path,
                    e,
                ));
            }
        }
        let mut committed = self.value.lock().unwrap();
        value.revision = committed.revision + 1;
        *committed = value;
        Ok(())
    }
    #[cfg(target_os = "macos")]
    pub fn reload(&self) {
        let old = self.get();
        let mut v = load(&self.path, old);
        if v.foreground != old.foreground
            || v.background != old.background
            || v.enabled != old.enabled
            || v.autostart != old.autostart
        {
            v.revision = old.revision + 1;
            *self.value.lock().unwrap() = v
        }
    }
}
pub fn load(path: &std::path::Path, fallback: Values) -> Values {
    let text = match fs::read_to_string(path) {
        Ok(s) if s.len() <= 4096 => s,
        _ => return fallback,
    };
    let mut fg = None;
    let mut bg = None;
    let mut on = None;
    let mut autostart = None;
    for line in text.lines() {
        let (key, v) = match line.split_once('=') {
            Some(x) => x,
            None => return fallback,
        };
        match key {
            "foreground_seconds" => fg = v.parse().ok(),
            "background_seconds" => bg = v.parse().ok(),
            "enabled" => on = v.parse().ok(),
            "autostart_enabled" => {
                autostart = v.parse().ok();
                if autostart.is_none() {
                    return fallback;
                }
            }
            _ => return fallback,
        }
    }
    match (fg, bg, on) {
        (Some(foreground), Some(background), Some(enabled)) => {
            let s = Values {
                foreground,
                background,
                enabled,
                autostart: autostart.unwrap_or(true),
                revision: 0,
            };
            if s.valid() {
                s
            } else {
                fallback
            }
        }
        _ => fallback,
    }
}
#[cfg(windows)]
fn replace(a: &std::path::Path, b: &std::path::Path) -> Result<(), String> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(a: *const u16, b: *const u16, flags: u32) -> i32;
    }
    let aa: Vec<u16> = a.as_os_str().encode_wide().chain(Some(0)).collect();
    let bb: Vec<u16> = b.as_os_str().encode_wide().chain(Some(0)).collect();
    if unsafe { MoveFileExW(aa.as_ptr(), bb.as_ptr(), 1 | 8) } == 0 {
        Err(std::io::Error::last_os_error().to_string())
    } else {
        Ok(())
    }
}
#[cfg(not(windows))]
fn replace(a: &std::path::Path, b: &std::path::Path) -> Result<(), String> {
    fs::rename(a, b).map_err(|e| e.to_string())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persist_validation_and_toggle() {
        let dir = std::env::temp_dir().join(format!(
            "chatgpt-titlesync-rust-settings-{}",
            std::process::id()
        ));
        let _ = fs::create_dir(&dir);
        let s = Live::new(
            dir.join("settings.conf"),
            Values {
                foreground: DEFAULT_FOREGROUND,
                background: DEFAULT_BACKGROUND,
                enabled: true,
                autostart: true,
                revision: 0,
            },
        );
        let mut v = s.get();
        v.foreground = 2;
        v.background = 5;
        s.save(v).unwrap();
        v.foreground = 3;
        s.save(v).unwrap();
        assert_eq!(load(&s.path, v).foreground, 3);
        let before = s.get();
        v.background = 4;
        assert!(s.save(v).is_err());
        assert_eq!(s.get(), before);
        v = before;
        v.enabled = false;
        s.save(v).unwrap();
        assert!(!load(&s.path, before).enabled);
        fs::write(&s.path, "broken").unwrap();
        assert_eq!(load(&s.path, before), before);
        let _ = fs::remove_dir_all(dir);
    }
    #[test]
    fn failed_save_keeps_live() {
        let path = std::env::temp_dir().join(format!("title-settings-file-{}", std::process::id()));
        fs::write(&path, "file").unwrap();
        let v = Values {
            foreground: DEFAULT_FOREGROUND,
            background: DEFAULT_BACKGROUND,
            enabled: true,
            autostart: true,
            revision: 0,
        };
        let s = Live::new(path.join("settings.conf"), v);
        let mut changed = v;
        changed.foreground = 2;
        assert!(s.save(changed).is_err());
        assert_eq!(s.get(), v);
        let _ = fs::remove_file(path);
    }
    #[test]
    fn fresh_defaults_preserve_existing_settings() {
        let dir = std::env::temp_dir().join(format!("title-defaults-{}", std::process::id()));
        let path = dir.join("settings.conf");
        let _ = fs::remove_file(&path);
        let defaults = Values {
            foreground: DEFAULT_FOREGROUND,
            background: DEFAULT_BACKGROUND,
            enabled: true,
            autostart: true,
            revision: 0,
        };
        assert_eq!((defaults.foreground, defaults.background), (2, 5));
        assert_eq!(load(&path, defaults), defaults);
        let s = Live::new(path, defaults);
        let mut custom = defaults;
        custom.foreground = 7;
        custom.background = 17;
        s.save(custom).unwrap();
        let got = load(&s.path, defaults);
        assert_eq!((got.foreground, got.background), (7, 17));
        let _ = fs::remove_dir_all(dir);
    }
    #[test]
    fn legacy_autostart_default_and_explicit_off_round_trip() {
        let dir =
            std::env::temp_dir().join(format!("titlesync-autostart-fields-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.conf");
        fs::write(
            &path,
            "foreground_seconds=7\nbackground_seconds=17\nenabled=true\n",
        )
        .unwrap();
        let defaults = Values {
            foreground: 2,
            background: 5,
            enabled: true,
            autostart: true,
            revision: 0,
        };
        let old = load(&path, defaults);
        assert_eq!(
            (old.foreground, old.background, old.autostart),
            (7, 17, true)
        );
        let live = Live::new(path.clone(), old);
        let mut off = old;
        off.autostart = false;
        live.save(off).unwrap();
        let text = fs::read_to_string(&path).unwrap();
        assert_eq!(text.lines().count(), 4);
        assert!(text.ends_with("autostart_enabled=false\n"));
        let loaded = load(&path, defaults);
        assert_eq!(
            (loaded.foreground, loaded.background, loaded.autostart),
            (7, 17, false)
        );
        let _ = fs::remove_dir_all(dir);
    }
}
