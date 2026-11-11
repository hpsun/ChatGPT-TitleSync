use crate::{lease::Window, QUIT};
use std::{
    ffi::c_void, mem, os::windows::process::CommandExt, process::Command, ptr,
    sync::atomic::Ordering,
};
type H = isize;
type Hr = i32;
#[repr(C)]
struct Guid {
    a: u32,
    b: u16,
    c: u16,
    d: [u8; 8],
}
#[repr(C)]
#[derive(Default)]
struct Variant {
    vt: u16,
    r1: u16,
    r2: u16,
    r3: u16,
    data: [usize; 2],
}
#[link(name = "kernel32")]
extern "system" {
    fn OpenProcess(a: u32, b: i32, p: u32) -> H;
    fn CloseHandle(h: H) -> i32;
    fn GetProcessTimes(h: H, c: *mut u64, e: *mut u64, k: *mut u64, u: *mut u64) -> i32;
    fn QueryFullProcessImageNameW(h: H, f: u32, b: *mut u16, n: *mut u32) -> i32;
    fn SetConsoleCtrlHandler(h: Option<unsafe extern "system" fn(u32) -> i32>, add: i32) -> i32;
}
#[link(name = "user32")]
extern "system" {
    fn IsWindow(h: H) -> i32;
    fn GetForegroundWindow() -> H;
    fn IsWindowVisible(h: H) -> i32;
    fn EnumWindows(cb: unsafe extern "system" fn(H, isize) -> i32, data: isize) -> i32;
    fn GetAncestor(h: H, f: u32) -> H;
    fn GetWindowThreadProcessId(h: H, p: *mut u32) -> u32;
    fn GetClassNameW(h: H, b: *mut u16, n: i32) -> i32;
    fn GetWindowTextW(h: H, b: *mut u16, n: i32) -> i32;
    fn SendMessageTimeoutW(
        h: H,
        m: u32,
        w: usize,
        l: isize,
        f: u32,
        t: u32,
        r: *mut usize,
    ) -> isize;
    fn CreateWindowExW(
        e: u32,
        c: *const u16,
        t: *const u16,
        s: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        p: H,
        m: H,
        i: H,
        l: *const c_void,
    ) -> H;
    fn DestroyWindow(h: H) -> i32;
}
#[link(name = "ole32")]
extern "system" {
    fn CoInitializeEx(p: *const c_void, f: u32) -> Hr;
    fn CoUninitialize();
    fn CoCreateInstance(
        c: *const Guid,
        o: *const c_void,
        k: u32,
        i: *const Guid,
        p: *mut *mut c_void,
    ) -> Hr;
}
#[link(name = "oleaut32")]
extern "system" {
    fn VariantClear(v: *mut Variant) -> Hr;
    fn SysStringLen(s: *const u16) -> u32;
}
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(Some(0)).collect()
}
unsafe fn method(p: *mut c_void, n: usize) -> *const c_void {
    *(*(p as *const *const *const c_void)).add(n)
}
struct Com(*mut c_void);
impl Drop for Com {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                let f: unsafe extern "system" fn(*mut c_void) -> u32 =
                    mem::transmute(method(self.0, 2));
                f(self.0);
            }
        }
    }
}
struct Apartment;
impl Drop for Apartment {
    fn drop(&mut self) {
        unsafe { CoUninitialize() }
    }
}
pub fn process_identity(pid: u32) -> Result<(u64, String), String> {
    unsafe {
        let h = OpenProcess(0x1000, 0, pid);
        if h == 0 {
            return Err("process-access".into());
        }
        let mut times = [0u64; 4];
        let ok = GetProcessTimes(
            h,
            &mut times[0],
            &mut times[1],
            &mut times[2],
            &mut times[3],
        );
        let mut b = vec![0u16; 32768];
        let mut n = b.len() as u32;
        let pathok = QueryFullProcessImageNameW(h, 0, b.as_mut_ptr(), &mut n);
        CloseHandle(h);
        if ok == 0 || pathok == 0 {
            return Err("process-identity".into());
        }
        Ok((times[0], String::from_utf16_lossy(&b[..n as usize])))
    }
}
fn capture(h: u64) -> Result<Window, String> {
    unsafe {
        if IsWindow(h as H) == 0 || GetAncestor(h as H, 2) != h as H {
            return Err("window-identity".into());
        }
        let mut pid = 0;
        GetWindowThreadProcessId(h as H, &mut pid);
        let (start, exe) = process_identity(pid)?;
        let mut b = [0u16; 256];
        let n = GetClassNameW(h as H, b.as_mut_ptr(), 256);
        if n == 0 {
            return Err("class".into());
        }
        Ok(Window {
            handle: h,
            pid,
            start,
            class: String::from_utf16_lossy(&b[..n as usize]),
            exe,
        })
    }
}
pub fn same(w: &Window) -> bool {
    capture(w.handle).is_ok_and(|a| a == *w)
}
pub fn list() -> Result<Vec<Window>, String> {
    let h = unsafe { GetForegroundWindow() };
    if h == 0 {
        return Ok(vec![]);
    }
    let w = match capture(h as u64) {
        Ok(w) => w,
        Err(_) => return Ok(vec![]),
    };
    if w.class == "Chrome_WidgetWin_1"
        && std::path::Path::new(&w.exe)
            .file_name()
            .is_some_and(|s| s.to_string_lossy().eq_ignore_ascii_case("ChatGPT.exe"))
    {
        Ok(vec![w])
    } else {
        Ok(vec![])
    }
}
pub fn active(w: &Window) -> bool {
    (unsafe { GetForegroundWindow() as u64 == w.handle }) && same(w)
}
pub fn set_active(w: &Window, a: &str, b: &str) -> Result<(), String> {
    if !active(w) {
        return Err("focus-changed".into());
    }
    set(w, a, b)?;
    if !active(w) {
        let _ = set(w, b, a);
        return Err("focus-changed-after-write".into());
    }
    Ok(())
}
pub fn caption(w: &Window) -> Result<String, String> {
    if !same(w) {
        return Err("identity-changed".into());
    }
    let mut b = [0u16; 2048];
    let n = unsafe { GetWindowTextW(w.handle as H, b.as_mut_ptr(), 2048) };
    if !same(w) {
        return Err("identity-changed".into());
    }
    Ok(String::from_utf16_lossy(&b[..n.max(0) as usize]))
}
pub fn set(w: &Window, old: &str, new: &str) -> Result<(), String> {
    if !same(w) || caption(w)? != old {
        return Err("caption-or-identity-changed".into());
    }
    let text = wide(new);
    let mut r = 0;
    unsafe {
        SendMessageTimeoutW(
            w.handle as H,
            0xC,
            0,
            text.as_ptr() as isize,
            0x23,
            300,
            &mut r,
        );
    }
    if !same(w) || caption(w)? != new {
        return Err("write-not-confirmed".into());
    }
    Ok(())
}
pub fn read_name(w: &Window) -> Result<String, String> {
    read_name_mode(w, true)
}
pub fn read_name_mode(w: &Window, foreground: bool) -> Result<String, String> {
    if !same(w) {
        return Err("identity-changed".into());
    }
    unsafe {
        if CoInitializeEx(ptr::null(), 0) < 0 {
            return Err("com-init".into());
        }
        let _apt = Apartment;
        let cls = Guid {
            a: 0xFF48DBA4,
            b: 0x60EF,
            c: 0x4201,
            d: [0xAA, 0x87, 0x54, 0x10, 0x3E, 0xEF, 0x59, 0x4E],
        };
        let iid = Guid {
            a: 0x30CBE57D,
            b: 0xD9D0,
            c: 0x452A,
            d: [0xAB, 0x13, 0x7A, 0xC5, 0xAC, 0x48, 0x25, 0xEE],
        };
        let mut p = ptr::null_mut();
        if CoCreateInstance(&cls, ptr::null(), 1, &iid, &mut p) < 0 || p.is_null() {
            return Err("uia-create".into());
        }
        let a = Com(p);
        let from: unsafe extern "system" fn(*mut c_void, H, *mut *mut c_void) -> Hr =
            mem::transmute(method(a.0, 6));
        let mut r = ptr::null_mut();
        if active(w) != foreground {
            return Err("focus-changed".into());
        }
        if from(a.0, w.handle as H, &mut r) < 0 || r.is_null() {
            return Err("uia-window".into());
        }
        let root = Com(r);
        let prop: unsafe extern "system" fn(*mut c_void, i32, Variant, *mut *mut c_void) -> Hr =
            mem::transmute(method(a.0, 23));
        let mut v = Variant::default();
        v.vt = 3;
        v.data[0] = 50030;
        let mut c = ptr::null_mut();
        if prop(a.0, 30003, v, &mut c) < 0 || c.is_null() {
            return Err("uia-document-condition".into());
        }
        let doc = Com(c);
        let mut visible = Variant::default();
        visible.vt = 11;
        let mut c = ptr::null_mut();
        if prop(a.0, 30022, visible, &mut c) < 0 || c.is_null() {
            return Err("uia-visible-condition".into());
        }
        let vis = Com(c);
        let and: unsafe extern "system" fn(
            *mut c_void,
            *mut c_void,
            *mut c_void,
            *mut *mut c_void,
        ) -> Hr = mem::transmute(method(a.0, 25));
        let mut c = ptr::null_mut();
        if and(a.0, doc.0, vis.0, &mut c) < 0 || c.is_null() {
            return Err("uia-and".into());
        }
        let condition = Com(c);
        let find: unsafe extern "system" fn(*mut c_void, i32, *mut c_void, *mut *mut c_void) -> Hr =
            mem::transmute(method(root.0, 5));
        let mut d = ptr::null_mut();
        if active(w) != foreground {
            return Err("focus-changed".into());
        }
        if find(
            root.0,
            4,
            if foreground { condition.0 } else { doc.0 },
            &mut d,
        ) < 0
            || d.is_null()
        {
            return Err("root-web-area-unavailable".into());
        }
        let document = Com(d);
        let get: unsafe extern "system" fn(*mut c_void, i32, *mut Variant) -> Hr =
            mem::transmute(method(document.0, 10));
        let mut identity_value = Variant::default();
        let identity_hr = get(document.0, 30011, &mut identity_value);
        let identity_ok =
            if identity_hr >= 0 && identity_value.vt == 8 && identity_value.data[0] != 0 {
                let n = SysStringLen(identity_value.data[0] as *const u16) as usize;
                n <= 256
                    && String::from_utf16_lossy(std::slice::from_raw_parts(
                        identity_value.data[0] as *const u16,
                        n,
                    )) == "RootWebArea"
            } else {
                false
            };
        VariantClear(&mut identity_value);
        if !identity_ok {
            return Err("root-document-role".into());
        }
        let mut value = Variant::default();
        if active(w) != foreground {
            return Err("focus-changed".into());
        }
        let hr = get(document.0, 30005, &mut value);
        let result = if hr >= 0 && value.vt == 8 && value.data[0] != 0 {
            let n = SysStringLen(value.data[0] as *const u16) as usize;
            if n <= 4096 {
                Ok(String::from_utf16_lossy(std::slice::from_raw_parts(
                    value.data[0] as *const u16,
                    n,
                )))
            } else {
                Err("root-name-too-long".into())
            }
        } else {
            Err("root-name-unavailable".into())
        };
        VariantClear(&mut value);
        if !same(w) {
            return Err("identity-changed".into());
        }
        result
    }
}
pub fn hide_child(c: &mut Command) {
    c.creation_flags(0x08000000);
}
unsafe extern "system" fn stopped(_: u32) -> i32 {
    QUIT.store(true, Ordering::Relaxed);
    1
}
pub fn install_stop_handler() {
    unsafe {
        SetConsoleCtrlHandler(Some(stopped), 1);
    }
}
pub fn cleanup() {
    unsafe {
        if STOP != 0 {
            CloseHandle(STOP);
            STOP = 0;
        }
        if MUTEX != 0 {
            ReleaseMutex(MUTEX);
            CloseHandle(MUTEX);
            MUTEX = 0;
        }
    }
}
pub fn self_test() -> Result<(), String> {
    unsafe {
        let h = CreateWindowExW(
            0,
            wide("STATIC").as_ptr(),
            wide("Rust owned original").as_ptr(),
            0,
            -30000,
            -30000,
            200,
            100,
            0,
            0,
            0,
            ptr::null(),
        );
        if h == 0 {
            return Err("fixture-create".into());
        }
        let result = (|| {
            let w = capture(h as u64)?;
            set(&w, "Rust owned original", "Rust owned changed")?;
            if caption(&w)? != "Rust owned changed" {
                return Err("fixture-readback".into());
            }
            let mut wrong = w.clone();
            wrong.start += 1;
            if set(&wrong, "Rust owned changed", "wrong").is_ok() {
                return Err("fixture-identity-guard".into());
            }
            set(&w, "Rust owned changed", "Rust owned original")?;
            Ok(())
        })();
        DestroyWindow(h);
        result
    }
}

#[link(name = "kernel32")]
extern "system" {
    fn CreateMutexW(a: *const c_void, b: i32, n: *const u16) -> H;
    fn WaitForSingleObject(h: H, t: u32) -> u32;
    fn ReleaseMutex(h: H) -> i32;
    fn CreateEventW(a: *const c_void, m: i32, i: i32, n: *const u16) -> H;
    fn OpenEventW(a: u32, i: i32, n: *const u16) -> H;
    fn ResetEvent(h: H) -> i32;
    fn SetEvent(h: H) -> i32;
}
static mut MUTEX: H = 0;
static mut STOP: H = 0;
pub fn acquire() -> Result<(), String> {
    unsafe {
        let h = CreateMutexW(
            ptr::null(),
            0,
            // Compatibility: keep the historical shared mutex/event names to exclude old and renamed residents.
            wide("Local\\TdxChatGptTitleStandalone").as_ptr(),
        );
        if h == 0 {
            return Err("shared-mutex".into());
        }
        let r = WaitForSingleObject(h, 0);
        if r != 0 && r != 0x80 {
            CloseHandle(h);
            return Err("already-running-shared".into());
        }
        MUTEX = h;
        // Compatibility: keep this stop-event identity identical to the previous product.
        STOP = CreateEventW(
            ptr::null(),
            1,
            0,
            wide("Local\\TdxChatGptTitleStandalone.Stop").as_ptr(),
        );
        if STOP == 0 {
            ReleaseMutex(h);
            CloseHandle(h);
            MUTEX = 0;
            return Err("stop-event".into());
        }
        ResetEvent(STOP);
    }
    Ok(())
}
pub fn stop_requested() -> bool {
    unsafe { STOP != 0 && WaitForSingleObject(STOP, 0) == 0 }
}
// Compatibility: use the historical cross-language stop event after the visible rename.
pub fn request_stop() -> Result<(), String> {
    unsafe {
        let h = OpenEventW(2, 0, wide("Local\\TdxChatGptTitleStandalone.Stop").as_ptr());
        if h == 0 {
            return Err("no-standalone-running".into());
        }
        let r = SetEvent(h);
        CloseHandle(h);
        if r == 0 {
            return Err("stop-failed".into());
        }
    }
    Ok(())
}
#[cfg(test)]
mod abi_tests {
    use super::*;
    #[test]
    fn native_condition_abi() {
        unsafe {
            assert!(CoInitializeEx(ptr::null(), 0) >= 0);
            let _apt = Apartment;
            let cls = Guid {
                a: 0xFF48DBA4,
                b: 0x60EF,
                c: 0x4201,
                d: [0xAA, 0x87, 0x54, 0x10, 0x3E, 0xEF, 0x59, 0x4E],
            };
            let iid = Guid {
                a: 0x30CBE57D,
                b: 0xD9D0,
                c: 0x452A,
                d: [0xAB, 0x13, 0x7A, 0xC5, 0xAC, 0x48, 0x25, 0xEE],
            };
            let mut p = ptr::null_mut();
            assert!(CoCreateInstance(&cls, ptr::null(), 1, &iid, &mut p) >= 0);
            assert!(!p.is_null());
            let a = Com(p);
            let prop: unsafe extern "system" fn(*mut c_void, i32, Variant, *mut *mut c_void) -> Hr =
                mem::transmute(method(a.0, 23));
            let mut v = Variant::default();
            v.vt = 3;
            v.data[0] = 50030;
            let mut c = ptr::null_mut();
            assert!(prop(a.0, 30003, v, &mut c) >= 0);
            assert!(!c.is_null());
            drop(Com(c));
            let mut v = Variant::default();
            v.vt = 11;
            let mut c = ptr::null_mut();
            assert!(prop(a.0, 30022, v, &mut c) >= 0);
            assert!(!c.is_null());
            drop(Com(c));
            // ABI only: no application accessibility tree is read.
        }
    }
}

unsafe extern "system" fn collect_all(h: H, data: isize) -> i32 {
    if IsWindowVisible(h) == 0 {
        return 1;
    }
    if let Ok(w) = capture(h as u64) {
        if w.class == "Chrome_WidgetWin_1"
            && std::path::Path::new(&w.exe)
                .file_name()
                .is_some_and(|s| s.to_string_lossy().eq_ignore_ascii_case("ChatGPT.exe"))
        {
            (*(data as *mut Vec<Window>)).push(w)
        }
    }
    1
}
pub fn list_all() -> Result<Vec<Window>, String> {
    let mut out = Vec::new();
    if unsafe { EnumWindows(collect_all, &mut out as *mut _ as isize) } == 0 {
        return Err("discovery".into());
    }
    Ok(out)
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

pub fn background_child(c: &mut Command) {
    c.creation_flags(0x08004000);
}
