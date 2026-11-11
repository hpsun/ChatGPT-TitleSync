use crate::lease::{Backend, Window};
use std::{
    collections::{HashMap, VecDeque},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc, Arc,
    },
    thread,
    time::{Duration, Instant},
};
#[derive(Clone)]
pub struct Job {
    pub w: Window,
    pub foreground: bool,
    pub version: u64,
    pub id: u64,
    pub epoch: u64,
}
pub struct Entry {
    pub w: Window,
    pub title: String,
    pub last: String,
    pub original: String,
    pub own: bool,
    pub version: u64,
    pub next_bg: Instant,
    pub pending: u64,
}
pub struct Cache<B: Backend> {
    pub b: B,
    pub entries: HashMap<Window, Entry>,
    pub readonly: bool,
    pub background: Duration,
    pub epoch: u64,
    next_id: u64,
}
impl<B: Backend> Cache<B> {
    pub fn new(b: B, readonly: bool, background: Duration) -> Self {
        Self {
            b,
            entries: HashMap::new(),
            readonly,
            background,
            epoch: 0,
            next_id: 0,
        }
    }
    pub fn remember(&mut self, w: Window, now: Instant) {
        self.entries.entry(w.clone()).or_insert(Entry {
            w,
            title: String::new(),
            last: String::new(),
            original: String::new(),
            own: false,
            version: 0,
            next_bg: now,
            pending: 0,
        });
    }
    pub fn job(&mut self, w: Window, foreground: bool, now: Instant) -> Job {
        self.remember(w.clone(), now);
        self.next_id += 1;
        Job {
            version: self.entries[&w].version,
            w,
            foreground,
            id: self.next_id,
            epoch: self.epoch,
        }
    }
    pub fn maintain(&mut self) {
        let keys: Vec<_> = self.entries.keys().cloned().collect();
        for w in keys {
            if !self.b.same(&w) {
                self.entries.remove(&w);
                continue;
            }
            let e = self.entries.get_mut(&w).unwrap();
            if e.title.is_empty() || self.b.active(&w) {
                continue;
            }
            let current = match self.b.caption(&w) {
                Ok(s) => s,
                Err(_) => continue,
            };
            if current == e.title {
                e.last = e.title.clone();
                continue;
            }
            if !generic(&current) {
                e.own = false;
                e.original.clear();
                e.last.clear();
                continue;
            }
            if self.readonly || self.b.active(&w) {
                continue;
            }
            if self.b.set_inactive(&w, &current, &e.title).is_ok() {
                if !e.own {
                    e.original = current;
                }
                e.own = true;
                e.last = e.title.clone();
            }
        }
    }
    pub fn foreground_job(&mut self, now: Instant) -> Option<Job> {
        if let Ok(ws) = self.b.list() {
            for w in ws {
                if self.b.active(&w) && self.b.same(&w) {
                    return Some(self.job(w, true, now));
                }
            }
        }
        None
    }
    pub fn background_jobs(&mut self, now: Instant) -> Vec<Job> {
        let keys: Vec<_> = self.entries.keys().cloned().collect();
        let mut out = Vec::new();
        for w in keys {
            let e = &self.entries[&w];
            if e.pending != 0 || now < e.next_bg || self.b.active(&w) || !self.b.same(&w) {
                continue;
            }
            let j = self.job(w.clone(), false, now);
            self.entries.get_mut(&w).unwrap().pending = j.id;
            out.push(j)
        }
        out.sort_by_key(|j| j.id);
        out
    }
    pub fn apply(&mut self, j: Job, result: Result<String, String>, now: Instant) {
        if j.epoch != self.epoch {
            return;
        }
        if !self.b.same(&j.w) {
            self.entries.remove(&j.w);
            return;
        }
        let e = match self.entries.get_mut(&j.w) {
            Some(e) => e,
            None => return,
        };
        if !j.foreground {
            if e.pending == j.id {
                e.pending = 0;
            }
            e.next_bg = now + self.background;
        }
        let title = match result {
            Ok(s) => s,
            Err(_) => return,
        };
        if j.foreground {
            if !self.b.active(&j.w) {
                return;
            }
        } else if self.b.active(&j.w) || e.version != j.version {
            return;
        }
        let title: String = title.chars().filter(|c| !c.is_control()).collect();
        let title = title.trim();
        if title.chars().count() > 240 {
            return;
        }
        let current = match self.b.caption(&j.w) {
            Ok(s) => s,
            Err(_) => return,
        };
        if !self.b.same(&j.w) || (j.foreground && !self.b.active(&j.w)) {
            return;
        }
        let previous = e.last.clone();
        e.version += 1;
        e.next_bg = now + self.background;
        if generic(title) {
            e.title.clear();
            if e.own && current == e.last && !self.readonly {
                let _ = self.b.set(&j.w, &current, &e.original);
            }
            e.own = false;
            e.original.clear();
            e.last.clear();
            return;
        }
        let desired = if title.ends_with(" — ChatGPT") {
            title.to_string()
        } else {
            format!("{} — ChatGPT", title)
        };
        e.title = desired.clone();
        if current == desired {
            e.last = desired;
            return;
        }
        if !generic(&current) && (previous.is_empty() || current != previous) {
            e.own = false;
            e.original.clear();
            e.last.clear();
            return;
        }
        if self.readonly {
            return;
        }
        let written = if j.foreground {
            self.b.set_active(&j.w, &current, &desired)
        } else {
            self.b.set_inactive(&j.w, &current, &desired)
        };
        if written.is_ok() {
            if !e.own {
                e.original = current
            }
            e.own = true;
            e.last = desired;
        }
    }
    pub fn restore(&mut self) {
        for e in self.entries.values_mut() {
            if e.own && self.b.same(&e.w) {
                if let Ok(current) = self.b.caption(&e.w) {
                    if current == e.last {
                        let _ = self.b.set(&e.w, &current, &e.original);
                    }
                }
            }
            e.own = false;
        }
    }
}
fn generic(s: &str) -> bool {
    s.trim().is_empty() || s.trim().eq_ignore_ascii_case("ChatGPT")
}
pub type Read = Arc<dyn Fn(&Window, bool, &AtomicBool) -> Result<String, String> + Send + Sync>;
pub type Discover = Arc<dyn Fn() -> Result<Vec<Window>, String> + Send + Sync>;
enum Event {
    Source(Job, Result<String, String>),
    Discovery(Result<Vec<Window>, String>),
}
#[cfg(test)]
pub fn run<B: Backend>(
    cache: Cache<B>,
    interval: Duration,
    read: Read,
    discover: Discover,
    control: impl FnMut() -> (bool, bool),
) {
    let bg = cache.background;
    run_live(cache, interval, read, discover, control, move || {
        (interval, bg)
    })
}
pub fn run_live<B: Backend>(
    mut cache: Cache<B>,
    mut interval: Duration,
    read: Read,
    discover: Discover,
    mut control: impl FnMut() -> (bool, bool),
    timing: impl Fn() -> (Duration, Duration),
) {
    let live_period = Arc::new(AtomicU64::new(cache.background.as_millis() as u64));
    let stop = Arc::new(AtomicBool::new(false));
    let paused = Arc::new(AtomicBool::new(false));
    let (fgtx, fgrx) = mpsc::sync_channel::<Job>(1);
    let (bgtx, bgrx) = mpsc::sync_channel::<Job>(0);
    let (events, eventrx) = mpsc::channel::<Event>();
    let spawn_worker = |rx: mpsc::Receiver<Job>, background: bool| {
        let stop = stop.clone();
        let paused = paused.clone();
        let read = read.clone();
        let discover = discover.clone();
        let events = events.clone();
        let live_period = live_period.clone();
        thread::spawn(move || {
            let mut next_discovery = Instant::now();
            let mut period = Duration::from_millis(live_period.load(Ordering::Relaxed));
            while !stop.load(Ordering::Relaxed) {
                let current = Duration::from_millis(live_period.load(Ordering::Relaxed));
                if current != period {
                    period = current;
                    next_discovery = Instant::now();
                }
                if background && Instant::now() >= next_discovery && !paused.load(Ordering::Relaxed)
                {
                    let _ = events.send(Event::Discovery(discover()));
                    next_discovery = Instant::now() + period;
                }
                match rx.recv_timeout(Duration::from_millis(30)) {
                    Ok(j) => {
                        let result = if paused.load(Ordering::Relaxed) {
                            Err("paused".into())
                        } else {
                            read(&j.w, j.foreground, &stop)
                        };
                        if events.send(Event::Source(j, result)).is_err() {
                            break;
                        }
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => {}
                    Err(_) => break,
                }
            }
        })
    };
    let fg = spawn_worker(fgrx, false);
    let bg = spawn_worker(bgrx, true);
    let mut next = Instant::now();
    let mut next_native = next;
    let mut latest = None;
    let mut queue = VecDeque::new();
    let mut was_paused = false;
    loop {
        let (fg, bg) = timing();
        if fg != interval || bg != cache.background {
            interval = fg;
            cache.background = bg;
            live_period.store(bg.as_millis() as u64, Ordering::Relaxed);
            cache.epoch += 1;
            latest = None;
            queue.clear();
            next = Instant::now();
            next_native = next;
            for e in cache.entries.values_mut() {
                e.pending = 0;
                e.next_bg = next;
            }
        }
        let (quit, pause) = control();
        if quit {
            break;
        }
        paused.store(pause, Ordering::Relaxed);
        if pause {
            if !was_paused {
                cache.epoch += 1;
                cache.restore();
                latest = None;
                queue.clear();
            }
            was_paused = true;
        } else {
            if was_paused {
                next = Instant::now();
                next_native = next;
                for e in cache.entries.values_mut() {
                    e.pending = 0;
                }
                was_paused = false;
            }
            while let Ok(event) = eventrx.try_recv() {
                match event {
                    Event::Discovery(Ok(ws)) => {
                        for w in ws {
                            cache.remember(w, Instant::now());
                        }
                    }
                    Event::Discovery(Err(_)) => {}
                    Event::Source(j, result) => cache.apply(j, result, Instant::now()),
                }
            }
            let now = Instant::now();
            if now >= next_native {
                cache.maintain();
                queue.extend(cache.background_jobs(now));
                next_native =
                    crate::advance_deadline(next_native, Instant::now(), Duration::from_secs(1));
            }
            if now >= next {
                latest = cache.foreground_job(now);
                next = crate::advance_deadline(next, Instant::now(), interval);
            }
            // Foreground dispatch is attempted first. Background work has its own serial thread.
            if let Some(j) = latest.take() {
                match fgtx.try_send(j) {
                    Ok(()) => {}
                    Err(mpsc::TrySendError::Full(j)) => latest = Some(j),
                    Err(_) => {}
                }
            }
            if let Some(j) = queue.pop_front() {
                match bgtx.try_send(j) {
                    Ok(()) => {}
                    Err(mpsc::TrySendError::Full(j)) => queue.push_front(j),
                    Err(_) => {}
                }
            }
        }
        thread::sleep(Duration::from_millis(30));
    }
    stop.store(true, Ordering::Relaxed);
    drop(fgtx);
    drop(bgtx);
    let _ = fg.join();
    let _ = bg.join();
    cache.restore();
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    struct Fake {
        ws: Vec<Window>,
        fg: u64,
        caps: HashMap<u64, String>,
        writes: usize,
    }
    impl Backend for Fake {
        fn list(&mut self) -> Result<Vec<Window>, String> {
            Ok(self
                .ws
                .iter()
                .filter(|w| w.handle == self.fg)
                .cloned()
                .collect())
        }
        fn same(&self, w: &Window) -> bool {
            self.ws.contains(w)
        }
        fn active(&self, w: &Window) -> bool {
            w.handle == self.fg && self.same(w)
        }
        fn caption(&self, w: &Window) -> Result<String, String> {
            self.caps.get(&w.handle).cloned().ok_or("gone".into())
        }
        fn set(&mut self, w: &Window, a: &str, b: &str) -> Result<(), String> {
            if !self.same(w) || self.caps[&w.handle] != a {
                return Err("changed".into());
            }
            self.caps.insert(w.handle, b.into());
            self.writes += 1;
            Ok(())
        }
        fn name(&mut self, _: &Window) -> Result<String, String> {
            panic!("native cache maintenance must not read source")
        }
    }
    fn fixture() -> Cache<Fake> {
        let a = Window {
            handle: 11,
            pid: 7,
            start: 9,
            class: "fixture".into(),
            exe: "fixture".into(),
        };
        let mut b = a.clone();
        b.handle = 22;
        Cache::new(
            Fake {
                ws: vec![a, b],
                fg: 11,
                caps: HashMap::from([(11, "ChatGPT".into()), (22, "ChatGPT".into())]),
                writes: 0,
            },
            false,
            Duration::from_secs(crate::settings::DEFAULT_BACKGROUND),
        )
    }
    fn observe(c: &mut Cache<Fake>, w: Window, fg: bool, title: &str, now: Instant) {
        let j = c.job(w, fg, now);
        c.apply(j, Ok(title.into()), now)
    }
    #[test]
    fn foreground_fresh_not_cache() {
        let mut c = fixture();
        let a = c.b.ws[0].clone();
        let now = Instant::now();
        observe(&mut c, a.clone(), true, "First", now);
        c.b.caps.insert(11, "ChatGPT".into());
        c.maintain();
        assert_eq!(c.b.caps[&11], "ChatGPT");
        observe(&mut c, a, true, "Second", now);
        assert_eq!(c.b.caps[&11], "Second — ChatGPT");
    }
    #[test]
    fn inactive_generic_restored_without_source() {
        let mut c = fixture();
        let a = c.b.ws[0].clone();
        observe(&mut c, a, true, "First", Instant::now());
        c.b.fg = 0;
        c.b.caps.insert(11, "ChatGPT".into());
        c.maintain();
        assert_eq!(c.b.caps[&11], "First — ChatGPT");
    }
    #[test]
    fn custom_kept_but_source_cache_refreshes() {
        let mut c = fixture();
        let a = c.b.ws[0].clone();
        let now = Instant::now();
        observe(&mut c, a.clone(), true, "First", now);
        c.b.fg = 0;
        c.b.caps.insert(11, "Custom".into());
        c.maintain();
        observe(&mut c, a, false, "Updated", now);
        assert_eq!(c.b.caps[&11], "Custom");
        c.b.caps.insert(11, "ChatGPT".into());
        c.maintain();
        assert_eq!(c.b.caps[&11], "Updated — ChatGPT");
    }
    #[test]
    fn unknown_background_due_per_window() {
        let mut c = fixture();
        c.b.fg = 0;
        let a = c.b.ws[1].clone();
        let now = Instant::now();
        c.remember(a, now);
        let jobs = c.background_jobs(now);
        assert_eq!(jobs.len(), 1);
        c.apply(jobs[0].clone(), Ok("Background".into()), now);
        assert_eq!(c.b.caps[&22], "Background — ChatGPT");
        assert!(c.background_jobs(now + Duration::from_secs(4)).is_empty());
        assert_eq!(c.background_jobs(now + Duration::from_secs(5)).len(), 1);
    }
    #[test]
    fn old_background_loses_to_fresh_foreground() {
        let mut c = fixture();
        let a = c.b.ws[0].clone();
        let now = Instant::now();
        c.b.fg = 0;
        let old = c.job(a.clone(), false, now);
        c.b.fg = 11;
        observe(&mut c, a.clone(), true, "Fresh", now);
        c.b.fg = 0;
        c.apply(old, Ok("Old".into()), now);
        assert_eq!(c.entries[&a].title, "Fresh — ChatGPT");
    }
    #[test]
    fn identity_change_discards_cache() {
        let mut c = fixture();
        let a = c.b.ws[0].clone();
        observe(&mut c, a, true, "First", Instant::now());
        c.b.fg = 0;
        c.b.ws[0].start += 1;
        let writes = c.b.writes;
        c.maintain();
        assert!(c.entries.is_empty());
        assert_eq!(c.b.writes, writes);
    }
    #[test]
    fn pause_generation_rejects_result() {
        let mut c = fixture();
        let a = c.b.ws[0].clone();
        let j = c.job(a, true, Instant::now());
        c.epoch += 1;
        c.apply(j, Ok("Old".into()), Instant::now());
        assert_eq!(c.b.writes, 0);
    }
    #[test]
    fn restore_only_owned_matching() {
        let mut c = fixture();
        let a = c.b.ws[0].clone();
        observe(&mut c, a, true, "First", Instant::now());
        c.restore();
        assert_eq!(c.b.caps[&11], "ChatGPT");
    }
    #[test]
    fn slow_background_does_not_block_foreground() {
        let c = fixture();
        let ws = c.b.ws.clone();
        let bg_started = Arc::new(AtomicBool::new(false));
        let fg_after = Arc::new(AtomicBool::new(false));
        let bg_count = Arc::new(AtomicUsize::new(0));
        let started = bg_started.clone();
        let after = fg_after.clone();
        let count = bg_count.clone();
        let read: Read = Arc::new(move |_, foreground, stop| {
            if foreground {
                if started.load(Ordering::Relaxed) {
                    after.store(true, Ordering::Relaxed);
                }
                Ok("Fresh".into())
            } else {
                count.fetch_add(1, Ordering::Relaxed);
                started.store(true, Ordering::Relaxed);
                while !stop.load(Ordering::Relaxed) {
                    thread::sleep(Duration::from_millis(2));
                }
                Err("stopped".into())
            }
        });
        let discover: Discover = Arc::new(move || Ok(ws.clone()));
        let start = Instant::now();
        run(c, Duration::from_millis(20), read, discover, || {
            (
                fg_after.load(Ordering::Relaxed) || start.elapsed() > Duration::from_secs(3),
                false,
            )
        });
        assert!(bg_started.load(Ordering::Relaxed));
        assert!(fg_after.load(Ordering::Relaxed));
        assert_eq!(bg_count.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn live_interval_change_reschedules_without_restart() {
        let cache = fixture();
        let fg_ms = Arc::new(AtomicU64::new(2000));
        let bg_ms = Arc::new(AtomicU64::new(5000));
        let reads = Arc::new(AtomicUsize::new(0));
        let discoveries = Arc::new(AtomicUsize::new(0));
        let r = reads.clone();
        let read: Read = Arc::new(move |_, fg, _| {
            if fg {
                r.fetch_add(1, Ordering::Relaxed);
            }
            Ok("Fresh".into())
        });
        let d = discoveries.clone();
        let discover: Discover = Arc::new(move || {
            d.fetch_add(1, Ordering::Relaxed);
            Ok(vec![])
        });
        let start = Instant::now();
        run_live(
            cache,
            Duration::from_secs(2),
            read,
            discover,
            || {
                if reads.load(Ordering::Relaxed) > 0 {
                    fg_ms.store(50, Ordering::Relaxed);
                    bg_ms.store(6000, Ordering::Relaxed);
                }
                (
                    (reads.load(Ordering::Relaxed) >= 3
                        && discoveries.load(Ordering::Relaxed) >= 2)
                        || start.elapsed() > Duration::from_secs(2),
                    false,
                )
            },
            || {
                (
                    Duration::from_millis(fg_ms.load(Ordering::Relaxed)),
                    Duration::from_millis(bg_ms.load(Ordering::Relaxed)),
                )
            },
        );
        assert!(reads.load(Ordering::Relaxed) >= 3);
        assert!(discoveries.load(Ordering::Relaxed) >= 2);
    }
}
