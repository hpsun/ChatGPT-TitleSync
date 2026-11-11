//! Shared icon preferences. UI-thread transactions join startup and timing rollback.
use crate::autostart_windows::{Native, Registry, Value};
use crate::settings::SettingsExtra;
use std::sync::Arc;
const PREF: &str = r"Software\ChatGPT-TitleSync";
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Mode {
    Fixed,
    Random,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Period {
    Day,
    Hour,
    FiveMinutes,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Preference {
    pub mode: Mode,
    pub fixed: u32,
    pub period: Period,
}
#[derive(Clone, Debug, PartialEq)]
pub struct State {
    pub pref: Preference,
    pub random: u32,
    pub slot: String,
}
impl Default for State {
    fn default() -> Self {
        Self {
            pref: Preference {
                mode: Mode::Fixed,
                fixed: 45,
                period: Period::Day,
            },
            random: 45,
            slot: String::new(),
        }
    }
}
impl State {
    pub fn id(&self) -> u32 {
        if self.pref.mode == Mode::Random {
            self.random
        } else {
            self.pref.fixed
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub struct Moment {
    pub year: u16,
    pub month: u16,
    pub day: u16,
    pub hour: u16,
    pub minute: u16,
    pub offset_minutes: i32,
}
pub fn slot(p: Period, t: Moment) -> String {
    let date = format!("{:04}{:02}{:02}", t.year, t.month, t.day);
    if p == Period::Day {
        return date;
    }
    let z = t.offset_minutes;
    let sign = if z < 0 { '-' } else { '+' };
    let a = z.abs();
    let offset = format!("{sign}{:02}{:02}", a / 60, a % 60);
    if p == Period::Hour {
        format!("{date}{:02}{offset}", t.hour)
    } else {
        format!("{date}{:02}{:02}{offset}", t.hour, t.minute / 5)
    }
}
#[repr(C)]
#[derive(Default)]
struct SystemTime {
    year: u16,
    month: u16,
    dow: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    millis: u16,
}
#[repr(C)]
struct Zone {
    bias: i32,
    standard_name: [u16; 32],
    standard_date: SystemTime,
    standard_bias: i32,
    daylight_name: [u16; 32],
    daylight_date: SystemTime,
    daylight_bias: i32,
}
#[link(name = "kernel32")]
extern "system" {
    fn GetLocalTime(t: *mut SystemTime);
    fn GetTimeZoneInformation(z: *mut Zone) -> u32;
}
#[link(name = "bcrypt")]
extern "system" {
    fn BCryptGenRandom(algorithm: isize, out: *mut u8, len: u32, flags: u32) -> i32;
}
fn local_moment() -> Moment {
    unsafe {
        let mut t = SystemTime::default();
        let mut z: Zone = std::mem::zeroed();
        GetLocalTime(&mut t);
        let id = GetTimeZoneInformation(&mut z);
        let extra = if id == 1 {
            z.standard_bias
        } else if id == 2 {
            z.daylight_bias
        } else {
            0
        };
        Moment {
            year: t.year,
            month: t.month,
            day: t.day,
            hour: t.hour,
            minute: t.minute,
            offset_minutes: -(z.bias + extra),
        }
    }
}
fn random_index(n: u32) -> Result<u32, String> {
    if n == 0 {
        return Err("random range".into());
    }
    for _ in 0..8 {
        let mut bytes = [0u8; 4];
        if unsafe { BCryptGenRandom(0, bytes.as_mut_ptr(), 4, 2) } != 0 {
            return Err("system icon random source failed".into());
        }
        let v = u32::from_le_bytes(bytes);
        let limit = u32::MAX - (u32::MAX % n);
        if v < limit {
            return Ok(v % n);
        }
    }
    Err("system icon random source rejected samples".into())
}
pub type Undo = Box<dyn FnOnce() -> Result<(), String> + Send>;
pub trait Store {
    fn load(&self) -> Result<State, String>;
    fn save(&self, state: &State) -> Result<Undo, String>;
}
pub struct RegistryStore {
    pub registry: Arc<dyn Registry>,
    pub path: String,
}
fn string(s: &str) -> Value {
    Value {
        exists: true,
        kind: 1,
        data: s
            .encode_utf16()
            .chain(Some(0))
            .flat_map(u16::to_le_bytes)
            .collect(),
    }
}
fn number(n: u32) -> Value {
    Value {
        exists: true,
        kind: 4,
        data: n.to_le_bytes().to_vec(),
    }
}
fn read_string(v: &Value) -> Result<String, String> {
    if v.kind != 1 || v.data.len() < 2 || v.data.len() > 256 || v.data.len() % 2 != 0 {
        return Err("invalid icon string preference".into());
    }
    let u: Vec<u16> = v
        .data
        .chunks_exact(2)
        .map(|x| u16::from_le_bytes([x[0], x[1]]))
        .collect();
    if u.last() != Some(&0) || u[..u.len() - 1].contains(&0) {
        return Err("invalid icon string terminator".into());
    }
    String::from_utf16(&u[..u.len() - 1]).map_err(|_| "invalid icon string UTF16".into())
}
fn read_number(v: &Value) -> Result<u32, String> {
    if v.kind != 4 || v.data.len() != 4 {
        return Err("invalid icon numeric preference".into());
    }
    Ok(u32::from_le_bytes(v.data[..].try_into().unwrap()))
}
impl Store for RegistryStore {
    fn load(&self) -> Result<State, String> {
        let mut s = State::default();
        for name in [
            "IconMode",
            "FixedIcon",
            "IconPeriod",
            "RandomIcon",
            "IconSlot",
        ] {
            let v = self.registry.read(&self.path, name)?;
            if !v.exists {
                continue;
            }
            match name {
                "IconMode" => {
                    s.pref.mode = match read_string(&v)?.as_str() {
                        "fixed" => Mode::Fixed,
                        "random" => Mode::Random,
                        _ => return Err("invalid persisted icon mode".into()),
                    }
                }
                "FixedIcon" => s.pref.fixed = read_number(&v)?,
                "IconPeriod" => {
                    s.pref.period = match read_string(&v)?.as_str() {
                        "day" => Period::Day,
                        "hour" => Period::Hour,
                        "5min" => Period::FiveMinutes,
                        _ => return Err("invalid persisted icon period".into()),
                    }
                }
                "RandomIcon" => s.random = read_number(&v)?,
                "IconSlot" => s.slot = read_string(&v)?,
                _ => {}
            }
        }
        if !(45..=52).contains(&s.pref.fixed) || !(45..=52).contains(&s.random) {
            return Err("invalid persisted icon ID".into());
        }
        Ok(s)
    }
    fn save(&self, s: &State) -> Result<Undo, String> {
        let names = [
            "IconMode",
            "FixedIcon",
            "IconPeriod",
            "RandomIcon",
            "IconSlot",
        ];
        let values = [
            string(if s.pref.mode == Mode::Fixed {
                "fixed"
            } else {
                "random"
            }),
            number(s.pref.fixed),
            string(match s.pref.period {
                Period::Day => "day",
                Period::Hour => "hour",
                Period::FiveMinutes => "5min",
            }),
            number(s.random),
            string(&s.slot),
        ];
        let old: Vec<Value> = names
            .iter()
            .map(|n| self.registry.read(&self.path, n))
            .collect::<Result<_, _>>()?;
        let registry = self.registry.clone();
        let path = self.path.clone();
        let undo: Undo = Box::new(move || {
            let mut errors = vec![];
            for i in (0..names.len()).rev() {
                if let Err(e) = registry.write(&path, names[i], &old[i]) {
                    errors.push(e)
                }
            }
            if errors.is_empty() {
                Ok(())
            } else {
                Err(errors.join("; "))
            }
        });
        for i in 0..names.len() {
            if let Err(e) = self.registry.write(&self.path, names[i], &values[i]) {
                return match undo() {
                    Ok(()) => Err(e),
                    Err(r) => Err(format!("{e}; icon rollback failed: {r}")),
                };
            }
        }
        Ok(undo)
    }
}
pub struct Controller {
    pub state: State,
    store: Arc<dyn Store>,
    clock: Box<dyn Fn() -> Moment>,
    pick: Box<dyn Fn(u32) -> Result<u32, String>>,
    validate: Box<dyn Fn(u32) -> Result<(), String>>,
    failed_slot: String,
}
impl Controller {
    pub fn new(
        store: Arc<dyn Store>,
        clock: Box<dyn Fn() -> Moment>,
        pick: Box<dyn Fn(u32) -> Result<u32, String>>,
        validate: Box<dyn Fn(u32) -> Result<(), String>>,
    ) -> (Self, Option<String>) {
        let (state, error) = match store.load() {
            Ok(s) => (s, None),
            Err(e) => (State::default(), Some(e)),
        };
        (
            Self {
                state,
                store,
                clock,
                pick,
                validate,
                failed_slot: String::new(),
            },
            error,
        )
    }
    pub fn production(validate: fn(u32) -> Result<(), String>) -> (Self, Option<String>) {
        Self::new(
            Arc::new(RegistryStore {
                registry: Arc::new(Native),
                path: PREF.into(),
            }),
            Box::new(local_moment),
            Box::new(random_index),
            Box::new(validate),
        )
    }
    fn draft(&self, p: Preference, all: bool) -> Result<State, String> {
        if !(45..=52).contains(&p.fixed) {
            return Err("图标配色必须为45–52".into());
        }
        let mut s = self.state.clone();
        s.pref = p;
        if all {
            if p.mode == Mode::Random {
                for id in 45..=52 {
                    (self.validate)(id)?
                }
            } else {
                (self.validate)(p.fixed)?
            }
        }
        if p.mode == Mode::Random {
            let current = slot(p.period, (self.clock)());
            if self.state.pref.mode != Mode::Random
                || self.state.pref.period != p.period
                || self.state.slot != current
            {
                let n = (self.pick)(7)?;
                if n >= 7 {
                    return Err("icon random picker out of range".into());
                }
                let previous = self.state.id();
                let mut id = 45 + n;
                if id >= previous {
                    id += 1
                }
                s.random = id;
                s.slot = current
            }
        }
        (self.validate)(s.id())?;
        Ok(s)
    }
    pub fn transaction<'a>(
        &'a mut self,
        p: Preference,
        install: &'a mut dyn FnMut(u32) -> Result<(), String>,
    ) -> Result<Transaction<'a>, String> {
        let value = self.draft(p, true)?;
        Ok(Transaction {
            controller: self,
            value,
            undo: None,
            install,
        })
    }
    pub fn tick(
        &mut self,
        install: &mut dyn FnMut(u32) -> Result<(), String>,
    ) -> Result<(), String> {
        if self.state.pref.mode != Mode::Random {
            return Ok(());
        }
        let current = slot(self.state.pref.period, (self.clock)());
        if self.state.slot == current || self.failed_slot == current {
            return Ok(());
        }
        let result = (|| {
            let value = self.draft(self.state.pref, false)?;
            let mut tx = Transaction {
                controller: self,
                value,
                undo: None,
                install,
            };
            if let Err(e) = tx.prepare() {
                return Err(e);
            }
            if let Err(e) = tx.finish() {
                return match tx.rollback() {
                    Ok(()) => Err(e),
                    Err(r) => Err(format!("{e}; icon rollback failed: {r}")),
                };
            }
            Ok(())
        })();
        if result.is_err() {
            self.failed_slot = current
        }
        result
    }
}
pub struct Transaction<'a> {
    controller: &'a mut Controller,
    value: State,
    undo: Option<Undo>,
    install: &'a mut dyn FnMut(u32) -> Result<(), String>,
}
impl SettingsExtra for Transaction<'_> {
    fn prepare(&mut self) -> Result<(), String> {
        self.undo = Some(self.controller.store.save(&self.value)?);
        Ok(())
    }
    fn finish(&mut self) -> Result<(), String> {
        (self.install)(self.value.id())?;
        self.controller.state = self.value.clone();
        self.controller.failed_slot.clear();
        Ok(())
    }
    fn rollback(&mut self) -> Result<(), String> {
        self.undo.take().map(|u| u()).unwrap_or(Ok(()))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    #[derive(Clone)]
    struct FakeStore {
        state: Arc<Mutex<State>>,
        writes: Arc<Mutex<usize>>,
    }
    impl FakeStore {
        fn new() -> Self {
            Self {
                state: Arc::new(Mutex::new(State::default())),
                writes: Arc::new(Mutex::new(0)),
            }
        }
    }
    impl Store for FakeStore {
        fn load(&self) -> Result<State, String> {
            Ok(self.state.lock().unwrap().clone())
        }
        fn save(&self, s: &State) -> Result<Undo, String> {
            let old = self.state.lock().unwrap().clone();
            *self.state.lock().unwrap() = s.clone();
            *self.writes.lock().unwrap() += 1;
            let state = self.state.clone();
            Ok(Box::new(move || {
                *state.lock().unwrap() = old;
                Ok(())
            }))
        }
    }
    fn moment() -> Moment {
        Moment {
            year: 2026,
            month: 11,
            day: 11,
            hour: 9,
            minute: 4,
            offset_minutes: 480,
        }
    }
    fn fixture() -> (Controller, FakeStore, Arc<Mutex<Moment>>) {
        let store = FakeStore::new();
        let now = Arc::new(Mutex::new(moment()));
        let clock = now.clone();
        let (c, e) = Controller::new(
            Arc::new(store.clone()),
            Box::new(move || *clock.lock().unwrap()),
            Box::new(|_| Ok(0)),
            Box::new(|_| Ok(())),
        );
        assert!(e.is_none());
        (c, store, now)
    }
    fn apply(c: &mut Controller, p: Preference) {
        let mut install = |_| Ok(());
        let mut tx = c.transaction(p, &mut install).unwrap();
        tx.prepare().unwrap();
        tx.finish().unwrap();
    }
    #[test]
    fn system_clock_and_random_abi_without_ui_or_preferences() {
        assert_eq!(std::mem::size_of::<SystemTime>(), 16);
        assert_eq!(std::mem::size_of::<Zone>(), 172);
        let t = local_moment();
        assert!(
            (1..=12).contains(&t.month)
                && (1..=31).contains(&t.day)
                && t.hour < 24
                && t.minute < 60
                && t.offset_minutes.abs() < 1440
        );
        for _ in 0..16 {
            assert!(random_index(7).unwrap() < 7);
        }
    }
    #[test]
    fn exact_shared_slots_and_dst() {
        let mut t = moment();
        assert_eq!(slot(Period::Day, t), "20261111");
        assert_eq!(slot(Period::Hour, t), "2026111109+0800");
        assert_eq!(slot(Period::FiveMinutes, t), "202611110900+0800");
        t.minute = 5;
        assert_eq!(slot(Period::FiveMinutes, t), "202611110901+0800");
        t.offset_minutes = -300;
        assert_eq!(slot(Period::Hour, t), "2026111109-0500");
        let a = slot(Period::Hour, t);
        t.offset_minutes = -240;
        assert_ne!(a, slot(Period::Hour, t));
        t.day = 12;
        t.hour = 0;
        t.minute = 0;
        assert_eq!(slot(Period::Day, t), "20261112");
    }
    #[test]
    fn all_eight_reachable_without_adjacent_repeat() {
        let (mut c, _, _) = fixture();
        let mut seen = std::collections::BTreeSet::new();
        for n in 0..7 {
            c.state = State::default();
            c.pick = Box::new(move |_| Ok(n));
            let s = c
                .draft(
                    Preference {
                        mode: Mode::Random,
                        fixed: 45,
                        period: Period::Day,
                    },
                    true,
                )
                .unwrap();
            assert_ne!(s.random, 45);
            seen.insert(s.random);
        }
        c.state.pref.fixed = 52;
        c.pick = Box::new(|_| Ok(0));
        seen.insert(
            c.draft(
                Preference {
                    mode: Mode::Random,
                    fixed: 52,
                    period: Period::Day,
                },
                true,
            )
            .unwrap()
            .random,
        );
        assert_eq!(seen.len(), 8);
    }
    #[test]
    fn fixed_does_not_rotate_and_same_slot_restart_is_stable() {
        let (mut c, store, now) = fixture();
        let mut install = |_| panic!("fixed mode must not install");
        c.tick(&mut install).unwrap();
        assert_eq!(*store.writes.lock().unwrap(), 0);
        apply(
            &mut c,
            Preference {
                mode: Mode::Random,
                fixed: 45,
                period: Period::Day,
            },
        );
        let before = c.state.clone();
        let writes = *store.writes.lock().unwrap();
        let clock = now.clone();
        let (mut restart, e) = Controller::new(
            Arc::new(store.clone()),
            Box::new(move || *clock.lock().unwrap()),
            Box::new(|_| panic!("same slot repicked")),
            Box::new(|_| panic!("same slot revalidated")),
        );
        assert!(e.is_none());
        let mut install = |_| panic!("same slot reinstalled");
        restart.tick(&mut install).unwrap();
        assert_eq!(restart.state, before);
        assert_eq!(*store.writes.lock().unwrap(), writes);
    }
    #[test]
    fn period_and_boundary_changes_choose_once() {
        let (mut c, store, now) = fixture();
        apply(
            &mut c,
            Preference {
                mode: Mode::Random,
                fixed: 45,
                period: Period::FiveMinutes,
            },
        );
        let old = c.state.random;
        now.lock().unwrap().minute = 5;
        let mut count = 0;
        let mut install = |_| {
            count += 1;
            Ok(())
        };
        c.tick(&mut install).unwrap();
        assert_ne!(c.state.random, old);
        let writes = *store.writes.lock().unwrap();
        c.tick(&mut install).unwrap();
        assert_eq!(count, 1);
        assert_eq!(*store.writes.lock().unwrap(), writes);
        let previous = c.state.random;
        apply(
            &mut c,
            Preference {
                mode: Mode::Random,
                fixed: 45,
                period: Period::Hour,
            },
        );
        assert_ne!(previous, c.state.random);
    }
    #[test]
    fn missing_rotation_asset_keeps_state_and_attempts_once() {
        let (mut c, store, now) = fixture();
        apply(
            &mut c,
            Preference {
                mode: Mode::Random,
                fixed: 45,
                period: Period::Hour,
            },
        );
        let old = c.state.clone();
        let writes = *store.writes.lock().unwrap();
        now.lock().unwrap().hour += 1;
        let calls = Arc::new(Mutex::new(0));
        let called = calls.clone();
        c.validate = Box::new(move |_| {
            *called.lock().unwrap() += 1;
            Err("missing owned fixture asset".into())
        });
        let mut install = |_| panic!("missing asset installed");
        assert!(c.tick(&mut install).is_err());
        assert!(c.tick(&mut install).is_ok());
        assert_eq!(*calls.lock().unwrap(), 1);
        assert_eq!(c.state, old);
        assert_eq!(*store.writes.lock().unwrap(), writes);
    }
    #[test]
    fn random_save_requires_all_assets_and_invalid_fixed_is_rejected() {
        let (mut c, store, _) = fixture();
        c.validate = Box::new(|id| {
            if id == 52 {
                Err("missing fixture asset".into())
            } else {
                Ok(())
            }
        });
        let mut install = |_| Ok(());
        assert!(c
            .transaction(
                Preference {
                    mode: Mode::Random,
                    fixed: 45,
                    period: Period::Day
                },
                &mut install
            )
            .is_err());
        assert!(c
            .transaction(
                Preference {
                    mode: Mode::Fixed,
                    fixed: 44,
                    period: Period::Day
                },
                &mut install
            )
            .is_err());
        assert_eq!(*store.writes.lock().unwrap(), 0);
    }
    struct StartupFixture {
        on: Arc<Mutex<bool>>,
    }
    impl crate::settings::Startup for StartupFixture {
        fn apply(&self, on: bool) -> Result<crate::settings::UndoStartup, String> {
            let old = *self.on.lock().unwrap();
            *self.on.lock().unwrap() = on;
            let state = self.on.clone();
            Ok(Box::new(move || {
                *state.lock().unwrap() = old;
                Ok(())
            }))
        }
    }
    #[test]
    fn failed_icon_install_rolls_back_timing_theme_startup() {
        let (mut c, store, _) = fixture();
        let path = std::env::temp_dir()
            .join(format!(
                "titlesync-theme-transaction-{}",
                std::process::id()
            ))
            .join("settings.conf");
        let old = crate::settings::Values {
            foreground: 2,
            background: 5,
            enabled: true,
            autostart: true,
            revision: 0,
        };
        let startup = Arc::new(StartupFixture {
            on: Arc::new(Mutex::new(true)),
        });
        let live = crate::settings::Live::with_startup(path.clone(), old, Some(startup.clone()));
        live.save(old).unwrap();
        let before = std::fs::read(&path).unwrap();
        let mut draft = live.get();
        let committed = draft;
        draft.foreground = 3;
        draft.background = 10;
        draft.autostart = false;
        let mut install = |_| Err("injected Shell icon failure".into());
        {
            let mut tx = c
                .transaction(
                    Preference {
                        mode: Mode::Random,
                        fixed: 45,
                        period: Period::Day,
                    },
                    &mut install,
                )
                .unwrap();
            assert!(live.save_extra(draft, Some(&mut tx)).is_err());
        }
        assert_eq!(std::fs::read(&path).unwrap(), before);
        assert_eq!(live.get(), committed);
        assert!(*startup.on.lock().unwrap());
        assert_eq!(*store.state.lock().unwrap(), State::default());
        assert_eq!(c.state, State::default());
        let owned = std::fs::canonicalize(path.parent().unwrap()).unwrap();
        let temp = std::fs::canonicalize(std::env::temp_dir()).unwrap();
        assert!(
            owned.starts_with(temp)
                && owned
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with("titlesync-theme-transaction-")
        );
        let _ = std::fs::remove_dir_all(owned);
    }
    struct FailOnce {
        base: Arc<dyn Registry>,
        calls: Mutex<usize>,
    }
    impl Registry for FailOnce {
        fn read(&self, p: &str, n: &str) -> Result<Value, String> {
            self.base.read(p, n)
        }
        fn write(&self, p: &str, n: &str, v: &Value) -> Result<(), String> {
            let mut calls = self.calls.lock().unwrap();
            *calls += 1;
            if *calls == 3 {
                return Err("injected third icon write failure".into());
            }
            self.base.write(p, n, v)
        }
    }
    #[link(name = "advapi32")]
    extern "system" {
        fn RegDeleteTreeW(root: isize, path: *const u16) -> i32;
    }
    #[test]
    fn private_registry_roundtrip_rollback_does_not_touch_startup() {
        let path = format!(
            r"Software\ChatGPT-TitleSync-Tests\rust-theme-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let native: Arc<dyn Registry> = Arc::new(Native);
        native.write(&path, "AutoStartEnabled", &number(1)).unwrap();
        let r = RegistryStore {
            registry: native.clone(),
            path: path.clone(),
        };
        assert_eq!(r.load().unwrap(), State::default());
        let mut state = State::default();
        state.pref.mode = Mode::Random;
        state.random = 52;
        state.slot = "20261111".into();
        let undo = r.save(&state).unwrap();
        assert_eq!(r.load().unwrap(), state);
        undo().unwrap();
        assert_eq!(r.load().unwrap(), State::default());
        assert_eq!(native.read(&path, "AutoStartEnabled").unwrap(), number(1));
        let failed = RegistryStore {
            registry: Arc::new(FailOnce {
                base: native.clone(),
                calls: Mutex::new(0),
            }),
            path: path.clone(),
        };
        assert!(failed.save(&state).is_err());
        assert_eq!(r.load().unwrap(), State::default());
        assert!(path.starts_with(r"Software\ChatGPT-TitleSync-Tests\rust-theme-"));
        native.write(&path, "FixedIcon", &number(44)).unwrap();
        let (fallback, error) = Controller::new(
            Arc::new(RegistryStore {
                registry: native.clone(),
                path: path.clone(),
            }),
            Box::new(moment),
            Box::new(|_| Ok(0)),
            Box::new(|_| Ok(())),
        );
        assert!(error.is_some());
        assert_eq!(fallback.state, State::default());
        assert_eq!(native.read(&path, "FixedIcon").unwrap(), number(44));
        let w: Vec<u16> = path.encode_utf16().chain(Some(0)).collect();
        unsafe {
            RegDeleteTreeW(-2147483647, w.as_ptr());
        }
    }
}
