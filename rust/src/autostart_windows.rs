//! Windows autostart contract shared by all language variants. No external crate.
use crate::settings::{Startup, UndoStartup};
use std::{ptr, sync::Arc};
const CURRENT_USER: isize = -2147483647;
const RUN: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const PREF: &str = r"Software\ChatGPT-TitleSync";
const RUN_NAME: &str = "ChatGPT-TitleSync";
const PREF_NAME: &str = "AutoStartEnabled";
#[link(name = "advapi32")]
extern "system" {
    fn RegOpenKeyExW(
        root: isize,
        path: *const u16,
        options: u32,
        access: u32,
        out: *mut isize,
    ) -> i32;
    fn RegCreateKeyExW(
        root: isize,
        path: *const u16,
        reserved: u32,
        class: *mut u16,
        options: u32,
        access: u32,
        security: *const u8,
        out: *mut isize,
        disposition: *mut u32,
    ) -> i32;
    fn RegQueryValueExW(
        key: isize,
        name: *const u16,
        reserved: *mut u32,
        kind: *mut u32,
        data: *mut u8,
        size: *mut u32,
    ) -> i32;
    fn RegSetValueExW(
        key: isize,
        name: *const u16,
        reserved: u32,
        kind: u32,
        data: *const u8,
        size: u32,
    ) -> i32;
    fn RegDeleteValueW(key: isize, name: *const u16) -> i32;
    fn RegCloseKey(key: isize) -> i32;
    #[cfg(test)]
    fn RegDeleteTreeW(root: isize, path: *const u16) -> i32;
}
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(Some(0)).collect()
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Value {
    pub(crate) exists: bool,
    pub(crate) kind: u32,
    pub(crate) data: Vec<u8>,
}
impl Value {
    pub(crate) fn missing() -> Self {
        Self {
            exists: false,
            kind: 0,
            data: vec![],
        }
    }
}
pub(crate) trait Registry: Send + Sync {
    fn read(&self, path: &str, name: &str) -> Result<Value, String>;
    fn write(&self, path: &str, name: &str, value: &Value) -> Result<(), String>;
}
pub(crate) struct Native;
impl Registry for Native {
    fn read(&self, path: &str, name: &str) -> Result<Value, String> {
        unsafe {
            let mut h = 0;
            let r = RegOpenKeyExW(CURRENT_USER, wide(path).as_ptr(), 0, 1, &mut h);
            if r == 2 {
                return Ok(Value::missing());
            }
            if r != 0 {
                return Err(format!("registry-open:{r}"));
            }
            let result = (|| {
                let (mut kind, mut size) = (0, 0);
                let r = RegQueryValueExW(
                    h,
                    wide(name).as_ptr(),
                    ptr::null_mut(),
                    &mut kind,
                    ptr::null_mut(),
                    &mut size,
                );
                if r == 2 {
                    return Ok(Value::missing());
                }
                if r != 0 {
                    return Err(format!("registry-query:{r}"));
                }
                if size > 65536 {
                    return Err("autostart-registry-value-too-large".into());
                }
                let mut data = vec![0; size as usize];
                let r = RegQueryValueExW(
                    h,
                    wide(name).as_ptr(),
                    ptr::null_mut(),
                    &mut kind,
                    data.as_mut_ptr(),
                    &mut size,
                );
                if r != 0 {
                    return Err(format!("registry-read:{r}"));
                }
                data.truncate(size as usize);
                Ok(Value {
                    exists: true,
                    kind,
                    data,
                })
            })();
            RegCloseKey(h);
            result
        }
    }
    fn write(&self, path: &str, name: &str, value: &Value) -> Result<(), String> {
        unsafe {
            let mut h = 0;
            let r = RegCreateKeyExW(
                CURRENT_USER,
                wide(path).as_ptr(),
                0,
                ptr::null_mut(),
                0,
                3,
                ptr::null(),
                &mut h,
                ptr::null_mut(),
            );
            if r != 0 {
                return Err(format!("registry-create:{r}"));
            }
            let r = if value.exists {
                RegSetValueExW(
                    h,
                    wide(name).as_ptr(),
                    0,
                    value.kind,
                    value.data.as_ptr(),
                    value.data.len() as u32,
                )
            } else {
                RegDeleteValueW(h, wide(name).as_ptr())
            };
            RegCloseKey(h);
            if r == 0 || (!value.exists && r == 2) {
                Ok(())
            } else {
                Err(format!("registry-write:{r}"))
            }
        }
    }
}
pub struct WindowsStartup {
    registry: Arc<dyn Registry>,
    run: String,
    pref: String,
    exe: String,
}
impl WindowsStartup {
    pub fn production() -> Result<Self, String> {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        if !exe.is_absolute() {
            return Err("autostart-executable-must-be-absolute".into());
        }
        Ok(Self {
            registry: Arc::new(Native),
            run: RUN.into(),
            pref: PREF.into(),
            exe: exe.to_string_lossy().into(),
        })
    }
    pub fn load(&self) -> Result<bool, String> {
        let v = self.registry.read(&self.pref, PREF_NAME)?;
        if !v.exists {
            return Ok(true);
        }
        if v.kind != 4 || v.data.len() != 4 {
            return Err("autostart-preference-must-be-DWORD".into());
        }
        Ok(u32::from_le_bytes(v.data.try_into().unwrap()) != 0)
    }
}
impl Startup for WindowsStartup {
    fn apply(&self, on: bool) -> Result<UndoStartup, String> {
        let command = format!("\"{}\"", self.exe);
        if on && command.encode_utf16().count() > 260 {
            return Err("开机自启动命令超过 Windows Run 的 260 字符限制".into());
        }

        let run_old = self.registry.read(&self.run, RUN_NAME)?;
        let pref_old = self.registry.read(&self.pref, PREF_NAME)?;
        let old_run_undo = run_old.clone();
        let old_pref_undo = pref_old.clone();
        let reg = self.registry.clone();
        let run = self.run.clone();
        let pref = self.pref.clone();
        let undo: UndoStartup = Box::new(move || {
            let a = reg.write(&pref, PREF_NAME, &old_pref_undo);
            let b = reg.write(&run, RUN_NAME, &old_run_undo);
            match (a, b) {
                (Ok(_), Ok(_)) => Ok(()),
                (Err(a), Ok(_)) => Err(a),
                (Ok(_), Err(b)) => Err(b),
                (Err(a), Err(b)) => Err(format!("{a}; {b}")),
            }
        });
        let run = if on {
            Value {
                exists: true,
                kind: 1,
                data: wide(&command)
                    .into_iter()
                    .flat_map(u16::to_le_bytes)
                    .collect(),
            }
        } else {
            Value::missing()
        };
        let pref = Value {
            exists: true,
            kind: 4,
            data: (if on { 1u32 } else { 0 }).to_le_bytes().to_vec(),
        };
        if run == run_old && pref == pref_old {
            return Ok(Box::new(|| Ok(())));
        }
        if let Err(e) = self
            .registry
            .write(&self.run, RUN_NAME, &run)
            .and_then(|_| self.registry.write(&self.pref, PREF_NAME, &pref))
        {
            if let Err(r) = undo() {
                return Err(format!("{e}; autostart rollback failed: {r}"));
            }
            return Err(e);
        }
        Ok(undo)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        sync::atomic::{AtomicUsize, Ordering},
        time::{SystemTime, UNIX_EPOCH},
    };
    struct Owned {
        base: String,
        controller: WindowsStartup,
    }
    impl Owned {
        fn new() -> Self {
            let base = format!(
                r"Software\ChatGPT-TitleSync-Tests\rust-{}-{}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            );
            let controller = WindowsStartup {
                registry: Arc::new(Native),
                run: format!(r"{}\Run", base),
                pref: format!(r"{}\Preference", base),
                exe: std::env::current_exe().unwrap().to_string_lossy().into(),
            };
            Self { base, controller }
        }
    }
    impl Drop for Owned {
        fn drop(&mut self) {
            assert!(self.base.starts_with(r"Software\ChatGPT-TitleSync-Tests\"));
            unsafe {
                RegDeleteTreeW(CURRENT_USER, wide(&self.base).as_ptr());
            }
        }
    }
    struct FailOnce {
        base: Arc<dyn Registry>,
        n: AtomicUsize,
        fail: usize,
    }
    impl Registry for FailOnce {
        fn read(&self, p: &str, n: &str) -> Result<Value, String> {
            self.base.read(p, n)
        }
        fn write(&self, p: &str, n: &str, v: &Value) -> Result<(), String> {
            if self.n.fetch_add(1, Ordering::SeqCst) + 1 == self.fail {
                return Err("injected registry failure".into());
            }
            self.base.write(p, n, v)
        }
    }
    #[test]
    fn owned_registry_defaults_off_and_rollback() {
        let owned = Owned::new();
        let c = &owned.controller;
        assert!(c.load().unwrap());
        let undo = c.apply(true).unwrap();
        let run = c.registry.read(&c.run, RUN_NAME).unwrap();
        assert_eq!(run.kind, 1);
        let u: Vec<u16> = run
            .data
            .chunks_exact(2)
            .map(|b| u16::from_le_bytes([b[0], b[1]]))
            .collect();
        assert_eq!(
            String::from_utf16_lossy(&u[..u.len() - 1]),
            format!("\"{}\"", c.exe)
        );
        let counter = Arc::new(FailOnce {
            base: c.registry.clone(),
            n: AtomicUsize::new(0),
            fail: 1,
        });
        let same = WindowsStartup {
            registry: counter.clone(),
            run: c.run.clone(),
            pref: c.pref.clone(),
            exe: c.exe.clone(),
        };
        let same_undo = same.apply(true).unwrap();
        same_undo().unwrap();
        assert_eq!(counter.n.load(Ordering::SeqCst), 0);
        undo().unwrap();
        assert!(!c.registry.read(&c.run, RUN_NAME).unwrap().exists);
        let _committed = c.apply(false).unwrap();
        assert!(!c.load().unwrap());
        let other = WindowsStartup {
            registry: c.registry.clone(),
            run: c.run.clone(),
            pref: c.pref.clone(),
            exe: c.exe.clone(),
        };
        assert!(!other.load().unwrap());
    }
    #[test]
    fn registry_and_disk_failure_keep_committed_state() {
        let owned = Owned::new();
        let c = &owned.controller;
        let _committed = c.apply(true).unwrap();
        let a = c.registry.read(&c.run, RUN_NAME).unwrap();
        let b = c.registry.read(&c.pref, PREF_NAME).unwrap();
        let broken = WindowsStartup {
            registry: Arc::new(FailOnce {
                base: c.registry.clone(),
                n: AtomicUsize::new(0),
                fail: 2,
            }),
            run: c.run.clone(),
            pref: c.pref.clone(),
            exe: c.exe.clone(),
        };
        assert!(broken.apply(false).is_err());
        assert_eq!(c.registry.read(&c.run, RUN_NAME).unwrap(), a);
        assert_eq!(c.registry.read(&c.pref, PREF_NAME).unwrap(), b);
        let path =
            std::env::temp_dir().join(format!("titlesync-registry-disk-{}", std::process::id()));
        std::fs::write(&path, "file").unwrap();
        let v = crate::settings::Values {
            foreground: 2,
            background: 5,
            enabled: true,
            autostart: true,
            revision: 0,
        };
        let live = crate::settings::Live::with_startup(
            path.join("settings.conf"),
            v,
            Some(Arc::new(WindowsStartup {
                registry: c.registry.clone(),
                run: c.run.clone(),
                pref: c.pref.clone(),
                exe: c.exe.clone(),
            })),
        );
        let mut off = v;
        off.autostart = false;
        assert!(live.save(off).is_err());
        assert_eq!(live.get(), v);
        assert_eq!(c.registry.read(&c.run, RUN_NAME).unwrap(), a);
        assert_eq!(c.registry.read(&c.pref, PREF_NAME).unwrap(), b);
        let _ = std::fs::remove_file(path);
    }
    #[test]
    fn long_command_rejected_but_off_still_works() {
        let owned = Owned::new();
        let c = &owned.controller;
        let long = WindowsStartup {
            registry: c.registry.clone(),
            run: c.run.clone(),
            pref: c.pref.clone(),
            exe: format!("C:\\{}.exe", "a".repeat(260)),
        };
        assert!(long.apply(true).is_err());
        assert!(!c.registry.read(&c.run, RUN_NAME).unwrap().exists);
        assert!(!c.registry.read(&c.pref, PREF_NAME).unwrap().exists);
        let boundary = WindowsStartup {
            registry: c.registry.clone(),
            run: c.run.clone(),
            pref: c.pref.clone(),
            exe: format!(r"C:\{}", "a".repeat(255)),
        };
        let _boundary_commit = boundary
            .apply(true)
            .expect("exactly 260 UTF-16 command characters");
        let old_run = c.registry.read(&c.run, RUN_NAME).unwrap();
        let old_pref = c.registry.read(&c.pref, PREF_NAME).unwrap();
        assert!(long.apply(true).is_err());
        assert_eq!(c.registry.read(&c.run, RUN_NAME).unwrap(), old_run);
        assert_eq!(c.registry.read(&c.pref, PREF_NAME).unwrap(), old_pref);
        let _committed = long.apply(false).unwrap();
        assert!(!long.load().unwrap());
    }
}
