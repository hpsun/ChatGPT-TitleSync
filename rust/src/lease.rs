use std::collections::HashMap;
use std::time::{Duration, Instant};
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Window {
    pub handle: u64,
    pub pid: u32,
    pub start: u64,
    pub class: String,
    pub exe: String,
}
pub trait Backend {
    fn list(&mut self) -> Result<Vec<Window>, String>;
    fn same(&self, w: &Window) -> bool;
    fn set_inactive(&mut self, w: &Window, a: &str, b: &str) -> Result<(), String> {
        if self.active(w) {
            return Err("foreground".into());
        }
        self.set(w, a, b)?;
        if self.active(w) {
            let _ = self.set(w, b, a);
            return Err("focus-changed".into());
        }
        Ok(())
    }
    fn active(&self, w: &Window) -> bool;
    fn set_active(&mut self, w: &Window, a: &str, b: &str) -> Result<(), String> {
        if !self.active(w) {
            return Err("focus-changed".into());
        }
        self.set(w, a, b)?;
        if !self.active(w) {
            return Err("focus-changed-after-write".into());
        }
        Ok(())
    }
    fn caption(&self, w: &Window) -> Result<String, String>;
    fn set(&mut self, w: &Window, old: &str, new: &str) -> Result<(), String>;
    fn name(&mut self, w: &Window) -> Result<String, String>;
}
struct Lease {
    w: Window,
    original: String,
    written: String,
}
pub struct Manager<B: Backend> {
    pub b: B,
    leases: HashMap<Window, Lease>,
    retry: HashMap<Window, Instant>,
    pub readonly: bool,
}
pub fn event(code: &str, w: &Window) {
    println!("event={} pid={} window={}", code, w.pid, w.handle);
}
impl<B: Backend> Manager<B> {
    pub fn new(b: B, readonly: bool) -> Self {
        Self {
            b,
            leases: HashMap::new(),
            retry: HashMap::new(),
            readonly,
        }
    }
    fn restore_one(&mut self, w: &Window) {
        if let Some(l) = self.leases.get(w) {
            if !self.b.same(&l.w) {
                self.leases.remove(w);
                return;
            }
            let current = match self.b.caption(w) {
                Ok(s) => s,
                Err(_) => return,
            };
            if current != l.written {
                self.leases.remove(w);
                event("restore-external-change", w);
                return;
            }
            let original = l.original.clone();
            if !self.readonly && self.b.set(w, &current, &original).is_ok() {
                self.leases.remove(w);
                event("restored", w);
            }
        }
    }
    pub fn restore(&mut self) {
        let keys: Vec<_> = self.leases.keys().cloned().collect();
        for w in keys {
            self.restore_one(&w)
        }
    }
    pub fn tick(&mut self, can_act: impl Fn() -> bool) {
        let windows = match self.b.list() {
            Ok(v) => v,
            Err(_) => return,
        };
        for w in windows {
            if !can_act() {
                return;
            }
            if self.retry.get(&w).is_some_and(|t| Instant::now() < *t)
                || !self.b.active(&w)
                || !self.b.same(&w)
            {
                continue;
            }
            let before = match self.b.caption(&w) {
                Ok(s) => s,
                Err(_) => continue,
            };
            if self
                .leases
                .get(&w)
                .is_some_and(|l| l.written != before && !generic_caption(&before))
            {
                self.leases.remove(&w);
                self.retry
                    .insert(w.clone(), Instant::now() + Duration::from_secs(30));
                event("external-change-backoff", &w);
                continue;
            }
            let title = match self.b.name(&w) {
                Ok(s) => s,
                Err(_) => {
                    if !self.b.active(&w) {
                        continue;
                    }
                    self.retry
                        .insert(w.clone(), Instant::now() + Duration::from_secs(1));
                    event("root-name-unavailable", &w);
                    continue;
                }
            };
            if !can_act() || !self.b.active(&w) || !self.b.same(&w) {
                continue;
            }
            if self.b.caption(&w).ok().as_deref() != Some(&before) {
                self.leases.remove(&w);
                continue;
            }
            let title: String = title.chars().filter(|c| !c.is_control()).collect();
            let title = title.trim();
            if title.chars().count() > 240 {
                continue;
            }
            if title.is_empty() || title.eq_ignore_ascii_case("ChatGPT") {
                self.restore_one(&w);
                continue;
            }
            if self.readonly {
                event("read-only-name-available", &w);
                continue;
            }
            let desired = if title.ends_with(" — ChatGPT") {
                title.to_owned()
            } else {
                format!("{} — ChatGPT", title)
            };
            if desired == before {
                continue;
            }
            if self.b.active(&w) && self.b.set_active(&w, &before, &desired).is_ok() {
                let original = self
                    .leases
                    .get(&w)
                    .map(|l| l.original.clone())
                    .unwrap_or(before);
                self.leases.insert(
                    w.clone(),
                    Lease {
                        w: w.clone(),
                        original,
                        written: desired,
                    },
                );
                event("updated", &w);
            } else {
                self.retry
                    .insert(w.clone(), Instant::now() + Duration::from_secs(30));
                event("write-not-confirmed", &w);
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Fake {
        inactive: bool,
        reads: usize,
        switch_on_name: bool,
        w: Window,
        cap: String,
        title: String,
        alive: bool,
        writable: bool,
        writes: usize,
    }
    impl Backend for Fake {
        fn list(&mut self) -> Result<Vec<Window>, String> {
            if self.inactive {
                Ok(vec![])
            } else {
                Ok(vec![self.w.clone()])
            }
        }
        fn active(&self, w: &Window) -> bool {
            !self.inactive && self.same(w)
        }
        fn same(&self, w: &Window) -> bool {
            self.alive && *w == self.w
        }
        fn caption(&self, _: &Window) -> Result<String, String> {
            Ok(self.cap.clone())
        }
        fn set(&mut self, w: &Window, old: &str, new: &str) -> Result<(), String> {
            if !self.same(w) || self.cap != old || !self.writable {
                return Err("readonly".into());
            }
            self.cap = new.into();
            self.writes += 1;
            Ok(())
        }
        fn name(&mut self, _: &Window) -> Result<String, String> {
            self.reads += 1;
            if self.switch_on_name {
                self.inactive = true;
            }
            Ok(self.title.clone())
        }
    }
    fn fixture() -> Manager<Fake> {
        Manager::new(
            Fake {
                inactive: false,
                reads: 0,
                switch_on_name: false,
                w: Window {
                    handle: 1,
                    pid: 2,
                    start: 3,
                    class: "own".into(),
                    exe: "fixture".into(),
                },
                cap: "Original".into(),
                title: "项目计划".into(),
                alive: true,
                writable: true,
                writes: 0,
            },
            false,
        )
    }
    #[test]
    fn nontarget_no_read() {
        let mut m = fixture();
        m.b.inactive = true;
        m.tick(|| true);
        assert_eq!(m.b.reads, 0);
        assert_eq!(m.b.writes, 0);
    }
    #[test]
    fn focus_switch_read_no_write() {
        let mut m = fixture();
        m.b.switch_on_name = true;
        m.tick(|| true);
        assert_eq!(m.b.writes, 0);
    }
    #[test]
    fn inactive_lease_retained() {
        let mut m = fixture();
        m.tick(|| true);
        m.b.inactive = true;
        m.tick(|| true);
        assert_eq!(m.b.cap, "项目计划 — ChatGPT");
        assert_eq!(m.leases.len(), 1);
        m.restore();
        assert_eq!(m.b.cap, "Original");
    }
    #[test]
    fn generic_native_caption_no_backoff() {
        let mut m = fixture();
        m.tick(|| true);
        m.b.cap = "ChatGPT".into();
        m.b.title = "资料整理".into();
        m.tick(|| true);
        assert_eq!(m.b.cap, "资料整理 — ChatGPT");
    }
    #[test]
    fn restore() {
        let mut m = fixture();
        m.tick(|| true);
        assert_eq!(m.b.cap, "项目计划 — ChatGPT");
        m.restore();
        assert_eq!(m.b.cap, "Original");
        assert_eq!(m.b.writes, 2)
    }
    #[test]
    fn external_preserved() {
        let mut m = fixture();
        m.tick(|| true);
        m.b.cap = "External".into();
        m.restore();
        assert_eq!(m.b.cap, "External")
    }
    #[test]
    fn identity_rejected() {
        let mut m = fixture();
        m.tick(|| true);
        m.b.w.start = 4;
        m.restore();
        assert_eq!(m.b.writes, 1)
    }
    #[test]
    fn readonly_no_success() {
        let mut m = fixture();
        m.readonly = true;
        m.tick(|| true);
        m.restore();
        assert_eq!(m.b.writes, 0)
    }
    #[test]
    fn canceled_no_write() {
        let mut m = fixture();
        m.tick(|| false);
        assert_eq!(m.b.writes, 0)
    }
    #[test]
    fn unwritable_no_lease() {
        let mut m = fixture();
        m.b.writable = false;
        m.tick(|| true);
        assert!(m.leases.is_empty());
        assert_eq!(m.b.writes, 0)
    }
    #[test]
    fn generic_restores() {
        let mut m = fixture();
        m.tick(|| true);
        m.b.title = "ChatGPT".into();
        m.tick(|| true);
        assert_eq!(m.b.cap, "Original")
    }
    #[test]
    fn title_fight_backoff() {
        let mut m = fixture();
        m.tick(|| true);
        m.b.cap = "External".into();
        m.tick(|| true);
        m.tick(|| true);
        assert_eq!(m.b.cap, "External");
        assert_eq!(m.b.writes, 1)
    }
}

impl<B: Backend> Drop for Manager<B> {
    fn drop(&mut self) {
        self.restore();
    }
}

fn generic_caption(s: &str) -> bool {
    s.trim().is_empty() || s.trim().eq_ignore_ascii_case("ChatGPT")
}
