//! macOS native AX implementation. Source only: not compiled or run on this Windows host.
//! No Dock per-window labels. The optional public osascript companion supplies menu settings.
use crate::{lease::Window, QUIT};
use std::{
    collections::{HashMap, VecDeque},
    ffi::{c_void, CString},
    process::Command,
    ptr,
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex, OnceLock,
    },
    time::{Duration, Instant},
};
type Ref = *const c_void;
type Ax = *const c_void;
#[repr(C)]
#[derive(Default)]
struct BsdInfo {
    flags: u32,
    status: u32,
    xstatus: u32,
    pid: u32,
    ppid: u32,
    uid: u32,
    gid: u32,
    ruid: u32,
    rgid: u32,
    svuid: u32,
    svgid: u32,
    rfu: u32,
    comm: [u8; 16],
    name: [u8; 32],
    nfiles: u32,
    pgid: u32,
    jobc: u32,
    dev: u32,
    tpgid: u32,
    nice: i32,
    startsec: u64,
    startusec: u64,
}
#[link(name = "System")]
extern "C" {
    fn proc_listpids(t: u32, i: u32, b: *mut c_void, n: i32) -> i32;
    fn proc_pidpath(p: i32, b: *mut c_void, n: u32) -> i32;
    fn proc_pidinfo(p: i32, f: i32, a: u64, b: *mut c_void, n: i32) -> i32;
    fn signal(n: i32, h: extern "C" fn(i32)) -> usize;
}
#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> bool;
    fn AXUIElementCreateSystemWide() -> Ax;
    fn AXUIElementGetPid(e: Ax, p: *mut i32) -> i32;
    fn AXUIElementGetTypeID() -> usize;
    fn AXUIElementCreateApplication(p: i32) -> Ax;
    fn AXUIElementCopyAttributeValue(e: Ax, a: Ref, v: *mut Ref) -> i32;
    fn AXUIElementIsAttributeSettable(e: Ax, a: Ref, s: *mut u8) -> i32;
    fn AXUIElementSetAttributeValue(e: Ax, a: Ref, v: Ref) -> i32;
    fn AXUIElementSetMessagingTimeout(e: Ax, t: f32) -> i32;
}
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFRetain(v: Ref) -> Ref;
    fn CFRelease(v: Ref);
    fn CFEqual(a: Ref, b: Ref) -> u8;
    fn CFGetTypeID(v: Ref) -> usize;
    fn CFStringGetTypeID() -> usize;
    fn CFArrayGetTypeID() -> usize;
    fn CFStringCreateWithCString(a: Ref, s: *const i8, e: u32) -> Ref;
    fn CFStringGetCString(s: Ref, b: *mut i8, n: isize, e: u32) -> u8;
    fn CFArrayGetCount(a: Ref) -> isize;
    fn CFArrayGetValueAtIndex(a: Ref, i: isize) -> Ref;
}
struct Owned(Ref);
impl Drop for Owned {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { CFRelease(self.0) }
        }
    }
}
fn cf(s: &str) -> Result<Owned, String> {
    let c = CString::new(s).map_err(|_| "string")?;
    let p = unsafe { CFStringCreateWithCString(ptr::null(), c.as_ptr(), 0x08000100) };
    if p.is_null() {
        Err("string".into())
    } else {
        Ok(Owned(p))
    }
}
fn attr(e: Ax, a: &str) -> Result<Owned, String> {
    let k = cf(a)?;
    let mut p = ptr::null();
    if unsafe { AXUIElementCopyAttributeValue(e, k.0, &mut p) } != 0 || p.is_null() {
        return Err("ax-attribute-unavailable".into());
    }
    Ok(Owned(p))
}
fn text(v: Ref) -> Result<String, String> {
    unsafe {
        if CFGetTypeID(v) != CFStringGetTypeID() {
            return Err("ax-string-type".into());
        }
        let mut b = vec![0u8; 16385];
        if CFStringGetCString(v, b.as_mut_ptr() as *mut i8, b.len() as isize, 0x08000100) == 0 {
            return Err("ax-string-length".into());
        }
        let n = b.iter().position(|x| *x == 0).unwrap_or(b.len());
        String::from_utf8(b[..n].to_vec()).map_err(|_| "ax-string-encoding".into())
    }
}
fn string_attr(e: Ax, a: &str) -> Result<String, String> {
    text(attr(e, a)?.0)
}
pub fn process_identity(pid: u32) -> Result<(u64, String), String> {
    unsafe {
        let mut b = vec![0u8; 4096];
        let n = proc_pidpath(pid as i32, b.as_mut_ptr() as *mut c_void, b.len() as u32);
        if n <= 0 {
            return Err("process-path".into());
        }
        let end = b.iter().position(|x| *x == 0).unwrap_or(n as usize);
        let exe = String::from_utf8(b[..end].to_vec()).map_err(|_| "process-path")?;
        let mut info = BsdInfo::default();
        if proc_pidinfo(
            pid as i32,
            3,
            0,
            &mut info as *mut _ as *mut c_void,
            std::mem::size_of::<BsdInfo>() as i32,
        ) != std::mem::size_of::<BsdInfo>() as i32
        {
            return Err("process-start".into());
        }
        Ok((info.startsec * 1_000_000 + info.startusec, exe))
    }
}
#[derive(Clone)]
struct Entry {
    ax: usize,
    w: Window,
}
static REG: OnceLock<Mutex<HashMap<u64, Entry>>> = OnceLock::new();
static TOKEN: AtomicU64 = AtomicU64::new(1);
fn registry() -> &'static Mutex<HashMap<u64, Entry>> {
    REG.get_or_init(|| Mutex::new(HashMap::new()))
}
fn ax(w: &Window) -> Option<Ax> {
    registry()
        .lock()
        .ok()?
        .get(&w.handle)
        .filter(|e| e.w == *w)
        .map(|e| e.ax as Ax)
}
#[link(name = "AppKit", kind = "framework")]
extern "C" {}
#[link(name = "objc")]
extern "C" {
    fn objc_getClass(n: *const i8) -> Ref;
    fn sel_registerName(n: *const i8) -> Ref;
    fn objc_msgSend();
}
unsafe fn selector(s: &str) -> Ref {
    let c = CString::new(s).unwrap();
    sel_registerName(c.as_ptr())
}
unsafe fn class(s: &str) -> Ref {
    let c = CString::new(s).unwrap();
    objc_getClass(c.as_ptr())
}
fn front_pid() -> u32 {
    unsafe {
        let msg: unsafe extern "C" fn(Ref, Ref) -> Ref =
            std::mem::transmute(objc_msgSend as *const ());
        let pidmsg: unsafe extern "C" fn(Ref, Ref) -> i32 =
            std::mem::transmute(objc_msgSend as *const ());
        let pool = msg(class("NSAutoreleasePool"), selector("new"));
        let ws = msg(class("NSWorkspace"), selector("sharedWorkspace"));
        let app = msg(ws, selector("frontmostApplication"));
        let pid = if app.is_null() {
            0
        } else {
            pidmsg(app, selector("processIdentifier"))
        };
        let drain: unsafe extern "C" fn(Ref, Ref) = std::mem::transmute(objc_msgSend as *const ());
        drain(pool, selector("drain"));
        pid as u32
    }
}
fn focused(pid: u32) -> Result<Owned, String> {
    if front_pid() != pid {
        return Err("not-focused".into());
    }
    let sys = Owned(unsafe { AXUIElementCreateSystemWide() });
    unsafe { AXUIElementSetMessagingTimeout(sys.0, 0.5) };
    let app = attr(sys.0, "AXFocusedApplication")?;
    let mut actual = 0;
    if unsafe { AXUIElementGetPid(app.0, &mut actual) } != 0 || actual as u32 != pid {
        return Err("focus-changed".into());
    }
    unsafe { AXUIElementSetMessagingTimeout(app.0, 0.5) };
    let win = attr(app.0, "AXFocusedWindow")?;
    if unsafe { CFGetTypeID(win.0) != AXUIElementGetTypeID() } || front_pid() != pid {
        return Err("focus-changed".into());
    }
    unsafe { AXUIElementSetMessagingTimeout(win.0, 0.5) };
    Ok(win)
}
pub fn list() -> Result<Vec<Window>, String> {
    let pid = front_pid();
    if pid == 0 {
        return Ok(vec![]);
    }
    let (start, exe) = match process_identity(pid) {
        Ok(v) => v,
        Err(_) => return Ok(vec![]),
    };
    if std::path::Path::new(&exe)
        .file_name()
        .and_then(|s| s.to_str())
        != Some("ChatGPT")
    {
        return Ok(vec![]);
    }
    if !unsafe { AXIsProcessTrusted() } {
        return Err("ax-permission-required".into());
    }
    let win = focused(pid)?;
    let mut reg = registry().lock().map_err(|_| "registry")?;
    if let Some(e) = reg.values().find(|e| {
        e.w.pid == pid && e.w.start == start && unsafe { CFEqual(e.ax as Ax, win.0) } != 0
    }) {
        return Ok(vec![e.w.clone()]);
    }
    let handle = TOKEN.fetch_add(1, Ordering::Relaxed);
    let w = Window {
        handle,
        pid,
        start,
        class: "AXWindow".into(),
        exe,
    };
    unsafe { CFRetain(win.0) };
    reg.insert(
        handle,
        Entry {
            ax: win.0 as usize,
            w: w.clone(),
        },
    );
    Ok(vec![w])
}
pub fn same(w: &Window) -> bool {
    process_identity(w.pid).is_ok_and(|p| p.0 == w.start && p.1 == w.exe)
        && ax(w).is_some_and(|e| string_attr(e, "AXRole").ok().as_deref() == Some("AXWindow"))
}
pub fn active(w: &Window) -> bool {
    if front_pid() != w.pid || !same(w) {
        return false;
    }
    let win = match focused(w.pid) {
        Ok(v) => v,
        Err(_) => return false,
    };
    ax(w).is_some_and(|e| unsafe { CFEqual(e, win.0) } != 0)
}
pub fn set_active(w: &Window, old: &str, new: &str) -> Result<(), String> {
    if !active(w) || !same(w) {
        return Err("focus-changed".into());
    }
    if caption(w)? != old {
        return Err("caption-changed".into());
    }
    let e = ax(w).ok_or("identity")?;
    let key = cf("AXTitle")?;
    let value = cf(new)?;
    let mut writable = 0;
    if !active(w) {
        return Err("focus-changed".into());
    }
    if unsafe { AXUIElementIsAttributeSettable(e, key.0, &mut writable) } != 0 || writable == 0 {
        return Err("ax-title-read-only".into());
    }
    if !active(w) || !same(w) {
        return Err("focus-changed".into());
    }
    let result = unsafe { AXUIElementSetAttributeValue(e, key.0, value.0) };
    if !active(w) {
        if result == 0 {
            let _ = set(w, new, old);
        }
        return Err("focus-changed-after-write".into());
    }
    if result != 0 || caption(w)? != new || !active(w) {
        return Err("write-unconfirmed".into());
    }
    Ok(())
}
pub fn caption(w: &Window) -> Result<String, String> {
    if !same(w) {
        return Err("identity-changed".into());
    }
    let title = string_attr(ax(w).ok_or("identity")?, "AXTitle")?;
    if !same(w) {
        return Err("identity-changed".into());
    }
    Ok(title)
}
pub fn set(w: &Window, old: &str, new: &str) -> Result<(), String> {
    if !same(w) || caption(w)? != old {
        return Err("caption-or-identity-changed".into());
    }
    let e = ax(w).ok_or("identity")?;
    let k = cf("AXTitle")?;
    let mut writable = 0;
    if unsafe { AXUIElementIsAttributeSettable(e, k.0, &mut writable) } != 0 || writable == 0 {
        return Err("ax-title-read-only".into());
    }
    let value = cf(new)?;
    if unsafe { AXUIElementSetAttributeValue(e, k.0, value.0) } != 0 || caption(w)? != new {
        return Err("write-not-confirmed".into());
    }
    Ok(())
}
pub fn read_name(w: &Window) -> Result<String, String> {
    read_name_mode(w, true)
}
pub fn read_name_mode(w: &Window, foreground: bool) -> Result<String, String> {
    if active(w) != foreground || !same(w) {
        return Err("identity-changed".into());
    }
    let root = ax(w).ok_or("identity")?;
    unsafe { CFRetain(root) };
    let mut queue = VecDeque::from([(Owned(root), 0usize)]);
    let start = Instant::now();
    let mut nodes = 0;
    while let Some((node, depth)) = queue.pop_front() {
        if QUIT.load(Ordering::Relaxed) || start.elapsed() > Duration::from_secs(3) || nodes >= 256
        {
            return Err("ax-bounded-read-timeout".into());
        }
        nodes += 1;
        if string_attr(node.0, "AXRole").ok().as_deref() == Some("AXWebArea") {
            let name = string_attr(node.0, "AXTitle")?;
            if active(w) != foreground || !same(w) {
                return Err("identity-changed".into());
            }
            return Ok(name);
        }
        if depth >= 12 {
            continue;
        }
        if let Ok(children) = attr(node.0, "AXChildren") {
            unsafe {
                if CFGetTypeID(children.0) == CFArrayGetTypeID() {
                    for i in 0..CFArrayGetCount(children.0)
                        .min(256usize.saturating_sub(nodes + queue.len()) as isize)
                    {
                        let child = CFArrayGetValueAtIndex(children.0, i);
                        if !child.is_null() {
                            AXUIElementSetMessagingTimeout(child, 0.5);
                            CFRetain(child);
                            queue.push_back((Owned(child), depth + 1));
                        }
                    }
                }
            }
        }
    }
    Err("root-web-area-unavailable".into())
}
pub fn hide_child(_: &mut Command) {}
extern "C" fn stopped(_: i32) {
    QUIT.store(true, Ordering::Relaxed);
}
pub fn install_stop_handler() {
    unsafe {
        signal(2, stopped);
        signal(15, stopped);
    }
}
pub fn acquire() -> Result<(), String> {
    Ok(())
}
pub fn request_stop() -> Result<(), String> {
    Err("use-state-dir-control".into())
}
pub fn stop_requested() -> bool {
    false
}
pub fn cleanup() {
    if let Ok(mut r) = registry().lock() {
        for e in r.values() {
            unsafe { CFRelease(e.ax as Ax) }
        }
        r.clear();
    }
}
pub fn self_test() -> Result<(), String> {
    Err("macOS-own-native-fixture-not-implemented; run cargo test for pure lease tests".into())
}

pub fn set_inactive(w: &Window, a: &str, b: &str) -> Result<(), String> {
    if active(w) {
        return Err("foreground".into());
    }
    set(w, a, b)?;
    if active(w) {
        let _ = set(w, b, a);
        return Err("focus-changed".into());
    }
    Ok(())
}
static DISCOVERY_OFFSET: AtomicU64 = AtomicU64::new(0);
pub fn list_all() -> Result<Vec<Window>, String> {
    if !unsafe { AXIsProcessTrusted() } {
        return Err("AX-permission".into());
    }
    let start = Instant::now();
    let mut ids = vec![0i32; 4096];
    let bytes = unsafe {
        proc_listpids(
            1,
            0,
            ids.as_mut_ptr() as *mut c_void,
            (ids.len() * 4) as i32,
        )
    };
    if bytes <= 0 {
        return Err("process-list".into());
    }
    let count = (bytes as usize / 4).min(ids.len());
    if count == 0 {
        return Ok(vec![]);
    }
    let offset = DISCOVERY_OFFSET.fetch_add(1, Ordering::Relaxed) as usize % count;
    let mut out = Vec::new();
    for k in 0..count {
        if QUIT.load(Ordering::Relaxed) || start.elapsed() > Duration::from_secs(4) {
            break;
        }
        let pid = ids[(offset + k) % count];
        if pid <= 0 {
            continue;
        }
        let (stamp, exe) = match process_identity(pid as u32) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if std::path::Path::new(&exe)
            .file_name()
            .and_then(|s| s.to_str())
            != Some("ChatGPT")
        {
            continue;
        }
        let app = Owned(unsafe { AXUIElementCreateApplication(pid) });
        unsafe { AXUIElementSetMessagingTimeout(app.0, 0.5) };
        let windows = match attr(app.0, "AXWindows") {
            Ok(a) => a,
            Err(_) => continue,
        };
        if unsafe { CFGetTypeID(windows.0) != CFArrayGetTypeID() } {
            continue;
        }
        for i in 0..unsafe { CFArrayGetCount(windows.0) }.min(256) {
            if start.elapsed() > Duration::from_secs(4) {
                break;
            }
            let win = unsafe { CFArrayGetValueAtIndex(windows.0, i) };
            if unsafe { CFGetTypeID(win) != AXUIElementGetTypeID() } {
                continue;
            }
            unsafe { AXUIElementSetMessagingTimeout(win, 0.5) };
            if string_attr(win, "AXRole").ok().as_deref() != Some("AXWindow") {
                continue;
            }
            let mut reg = registry().lock().map_err(|_| "registry")?;
            if let Some(old) = reg.values().find(|e| {
                e.w.pid == pid as u32
                    && e.w.start == stamp
                    && unsafe { CFEqual(e.ax as Ax, win) } != 0
            }) {
                out.push(old.w.clone());
                continue;
            }
            let handle = TOKEN.fetch_add(1, Ordering::Relaxed);
            let w = Window {
                handle,
                pid: pid as u32,
                start: stamp,
                class: "AXWindow".into(),
                exe: exe.clone(),
            };
            unsafe { CFRetain(win) };
            reg.insert(
                handle,
                Entry {
                    ax: win as usize,
                    w: w.clone(),
                },
            );
            out.push(w);
        }
    }
    Ok(out)
}

pub fn background_child(_: &mut Command) {}
