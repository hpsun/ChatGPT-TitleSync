//! Native Win32 tray and modeless settings. No additional runtime or crates.
use crate::settings::Live;
use crate::theme_windows::{Controller, Mode, Period, Preference};
use std::{
    mem, ptr,
    sync::{atomic::Ordering, mpsc, Arc},
    thread,
};
#[repr(C)]
#[derive(Default)]
struct Point {
    x: i32,
    y: i32,
}
#[repr(C)]
#[derive(Default)]
struct Msg {
    hwnd: isize,
    message: u32,
    w: usize,
    l: isize,
    time: u32,
    point: Point,
    private: u32,
}
#[repr(C)]
struct Class {
    size: u32,
    style: u32,
    proc: unsafe extern "system" fn(isize, u32, usize, isize) -> isize,
    ce: i32,
    we: i32,
    instance: isize,
    icon: isize,
    cursor: isize,
    background: isize,
    menu: *const u16,
    name: *const u16,
    small: isize,
}
#[repr(C)]
struct Icon {
    size: u32,
    hwnd: isize,
    id: u32,
    flags: u32,
    callback: u32,
    icon: isize,
    tip: [u16; 128],
    state: u32,
    mask: u32,
    info: [u16; 256],
    timeout: u32,
    title: [u16; 64],
    infoflags: u32,
    guid: [u8; 16],
    balloon: isize,
}
#[link(name = "user32")]
extern "system" {
    fn RegisterClassExW(c: *const Class) -> u16;
    #[cfg(test)]
    fn GetWindow(h: isize, command: u32) -> isize;
    #[cfg(test)]
    fn GetWindowLongPtrW(h: isize, index: i32) -> isize;
    fn CreateWindowExW(
        ex: u32,
        cls: *const u16,
        text: *const u16,
        style: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        parent: isize,
        menu: isize,
        instance: isize,
        param: *const std::ffi::c_void,
    ) -> isize;
    fn DefWindowProcW(h: isize, m: u32, w: usize, l: isize) -> isize;
    fn DestroyWindow(h: isize) -> i32;
    fn DestroyIcon(h: isize) -> i32;
    fn SetTimer(h: isize, id: usize, millis: u32, callback: isize) -> usize;
    fn KillTimer(h: isize, id: usize) -> i32;
    fn EnableWindow(h: isize, enabled: i32) -> i32;
    #[cfg(test)]
    fn IsWindowEnabled(h: isize) -> i32;
    #[cfg(test)]
    fn GetIconInfo(h: isize, out: *mut OwnedIconInfo) -> i32;
    fn SetWindowPos(
        h: isize,
        after: isize,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        flags: u32,
    ) -> i32;
    fn SetForegroundWindow(h: isize) -> i32;
    fn SetFocus(h: isize) -> isize;
    fn LoadIconW(i: isize, n: *const u16) -> isize;
    fn LoadCursorW(i: isize, n: *const u16) -> isize;
    fn LoadImageW(i: isize, n: *const u16, kind: u32, w: i32, h: i32, f: u32) -> isize;
    fn SendMessageW(h: isize, m: u32, w: usize, l: isize) -> isize;
    fn PostMessageW(h: isize, m: u32, w: usize, l: isize) -> i32;
    fn PostQuitMessage(c: i32);
    fn GetMessageW(m: *mut Msg, h: isize, a: u32, b: u32) -> i32;
    fn TranslateMessage(m: *const Msg) -> i32;
    fn DispatchMessageW(m: *const Msg) -> isize;
    fn SetWindowTextW(h: isize, s: *const u16) -> i32;
    fn GetWindowTextW(h: isize, s: *mut u16, n: i32) -> i32;
    fn CreatePopupMenu() -> isize;
    fn DestroyMenu(h: isize) -> i32;
    fn AppendMenuW(h: isize, f: u32, id: usize, s: *const u16) -> i32;
    fn TrackPopupMenu(h: isize, f: u32, x: i32, y: i32, r: i32, owner: isize, p: *const u8) -> u32;
    fn GetCursorPos(p: *mut Point) -> i32;
    fn MessageBoxW(h: isize, s: *const u16, t: *const u16, f: u32) -> i32;
    fn RegisterWindowMessageW(n: *const u16) -> u32;
}
#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleW(s: *const u16) -> isize;
}
#[link(name = "shell32")]
extern "system" {
    fn Shell_NotifyIconW(c: u32, i: *const Icon) -> i32;
}
#[link(name = "gdi32")]
extern "system" {
    fn GetStockObject(n: i32) -> isize;
    #[cfg(test)]
    fn DeleteObject(h: isize) -> i32;
}
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(Some(0)).collect()
}
struct Tray {
    s: Arc<Live>,
    hwnd: isize,
    panel: isize,
    fg: isize,
    bg: isize,
    auto_check: isize,
    mode_combo: isize,
    fixed_combo: isize,
    period_combo: isize,
    theme: Option<Controller>,
    icon_owned: bool,
    icon_id: u32,
    asset_loader: fn(u32) -> Result<isize, String>,
    nid: Icon,
    test: bool,
    taskbar: u32,
}
// Only the dedicated UI thread accesses this pointer, including synchronous callbacks.
thread_local! {static UI:std::cell::Cell<*mut Tray>=const{std::cell::Cell::new(ptr::null_mut())};}
unsafe extern "system" fn proc(h: isize, m: u32, w: usize, l: isize) -> isize {
    let p = UI.with(|v| v.get());
    if !p.is_null() {
        let t = &mut *p;
        if m == t.taskbar && !t.test {
            let _ = t.update(0);
            return 0;
        }
        match m {
            0x113 if h == t.hwnd && w == 90 => {
                t.tick_theme();
                return 0;
            }
            0x8001 => {
                if l == 0x205 || l == 0x7b {
                    t.popup()
                }
                return 0;
            }
            0x111 if h == t.panel => {
                if w & 0xffff == 301 && w >> 16 == 1 {
                    t.enable_theme_fields();
                    return 0;
                }
                match w & 0xffff {
                    101 => t.commit(),
                    102 => {
                        panel_visibility(h, false);
                    }
                    _ => {}
                }
                return 0;
            }
            0x111 if h == t.hwnd && (1..=4).contains(&(w & 0xffff)) => {
                t.command((w & 0xffff) as u32);
                return 0;
            }
            0x10 => {
                if h == t.panel {
                    panel_visibility(h, false);
                    return 0;
                }
                KillTimer(t.hwnd, 90);
                if t.panel != 0 {
                    DestroyWindow(t.panel);
                }
                if !t.test {
                    Shell_NotifyIconW(2, &t.nid);
                }
                DestroyWindow(h);
                if t.icon_owned {
                    DestroyIcon(t.nid.icon);
                    t.icon_owned = false;
                }
                return 0;
            }
            2 if h == t.hwnd => {
                PostQuitMessage(0);
                return 0;
            }
            _ => {}
        }
    }
    DefWindowProcW(h, m, w, l)
}
// Explicit show/hide avoids STARTUPINFO's first-ShowWindow override.
unsafe fn panel_visibility(h: isize, visible: bool) -> bool {
    SetWindowPos(h, 0, 0, 0, 0, 0, if visible { 0x57 } else { 0x97 }) != 0
}
// Compatibility: native automation class ChatGPTTitleRustTray_ remains stable; visible titles are renamed.
impl Tray {
    unsafe fn create(s: Arc<Live>, test: bool) -> Result<Box<Self>, String> {
        let instance = GetModuleHandleW(ptr::null());
        let cls = wide(&format!("ChatGPTTitleRustTray_{}", std::process::id()));
        let c = Class {
            size: mem::size_of::<Class>() as u32,
            style: 0,
            proc,
            ce: 0,
            we: 0,
            instance,
            icon: 0,
            cursor: LoadCursorW(0, 32512 as *const u16),
            background: 6,
            menu: ptr::null(),
            name: cls.as_ptr(),
            small: 0,
        };
        if RegisterClassExW(&c) == 0 {
            return Err("tray-window-class".into());
        }
        let hwnd = CreateWindowExW(
            0,
            cls.as_ptr(),
            wide("ChatGPT-TitleSync Rust tray").as_ptr(),
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            instance,
            ptr::null(),
        );
        if hwnd == 0 {
            return Err("tray-window".into());
        }
        let mut icon = 0;
        let mut icon_owned = false;
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let dir = exe.parent().ok_or("exe-parent")?;
        for p in [
            dir.join("chatgpt-titlesync.ico"),
            dir.join("../assets/chatgpt-titlesync.ico"),
            dir.join("../../assets/chatgpt-titlesync.ico"),
            dir.join("../../../assets/chatgpt-titlesync.ico"),
        ] {
            if p.is_file() {
                icon = LoadImageW(0, wide(&p.to_string_lossy()).as_ptr(), 1, 0, 0, 0x50);
                if icon != 0 {
                    icon_owned = true;
                    break;
                }
            }
        }
        if icon == 0 {
            icon = LoadIconW(instance, 1 as *const u16)
        }
        if icon == 0 {
            icon = LoadIconW(0, 32512 as *const u16)
        }
        let mut nid: Icon = mem::zeroed();
        nid.size = mem::size_of::<Icon>() as u32;
        nid.hwnd = hwnd;
        nid.id = 1;
        nid.icon = icon;
        nid.callback = 0x8001;
        let mut t = Box::new(Self {
            s,
            hwnd,
            panel: 0,
            fg: 0,
            bg: 0,
            auto_check: 0,
            mode_combo: 0,
            fixed_combo: 0,
            period_combo: 0,
            theme: None,
            icon_owned,
            icon_id: 0,
            asset_loader: load_theme_asset,
            nid,
            test,
            taskbar: RegisterWindowMessageW(wide("TaskbarCreated").as_ptr()),
        });
        UI.with(|v| v.set(&mut *t));
        if !test && !t.update(0) {
            DestroyWindow(t.hwnd);
            UI.with(|v| v.set(ptr::null_mut()));
            return Err("tray icon could not be added; use --no-tray for CLI controls".into());
        }
        if !test {
            let (theme, error) = Controller::production(validate_theme_asset);
            if let Some(e) = error {
                eprintln!("icon theme: {e}");
            }
            t.theme = Some(theme);
            t.tick_theme();
            let desired = t.theme.as_ref().unwrap().state.id();
            if let Err(e) = t.install_theme(desired) {
                eprintln!("icon theme: {e}");
            }
            SetTimer(t.hwnd, 90, 1000, 0);
        }
        Ok(t)
    }
    unsafe fn update(&mut self, command: u32) -> bool {
        let v = self.s.get();
        self.nid.flags = 7;
        self.nid.tip.fill(0);
        let text = wide(&format!(
            "ChatGPT 标题同步助手（Rust）\n前台{}秒；后台{}秒",
            v.foreground, v.background
        ));
        self.nid.tip[..text.len()].copy_from_slice(&text);
        Shell_NotifyIconW(command, &self.nid) != 0
    }
    unsafe fn child(
        &self,
        class: &str,
        text: &str,
        style: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        id: isize,
    ) -> isize {
        let win = CreateWindowExW(
            0,
            wide(class).as_ptr(),
            wide(text).as_ptr(),
            style | 0x50000000,
            x,
            y,
            w,
            h,
            self.panel,
            id,
            0,
            ptr::null(),
        );
        SendMessageW(win, 0x30, GetStockObject(17) as usize, 1);
        win
    }
    unsafe fn show(&mut self, show: bool) {
        if self.panel == 0 {
            let cls = wide(&format!("ChatGPTTitleRustTray_{}", std::process::id()));
            self.panel = CreateWindowExW(
                0x00040000,
                cls.as_ptr(),
                wide("ChatGPT 标题同步助手 · Rust — 设置").as_ptr(),
                0x00c80000,
                i32::MIN,
                i32::MIN,
                450,
                410,
                0,
                0,
                0,
                ptr::null(),
            );
            if self.panel == 0 {
                return;
            }
            self.child(
                "STATIC",
                "前台扫描间隔（秒，1–3600）",
                0,
                18,
                20,
                260,
                23,
                0,
            );
            self.fg = self.child("EDIT", "", 0x00810080, 295, 18, 105, 25, 201);
            self.child(
                "STATIC",
                "后台刷新间隔（秒，5–3600）",
                0,
                18,
                62,
                260,
                23,
                0,
            );
            self.bg = self.child("EDIT", "", 0x00810080, 295, 60, 105, 25, 202);
            self.auto_check = self.child("BUTTON", "开机自启动", 0x00010003, 18, 103, 260, 27, 203);
            self.child("STATIC", "图标模式", 0, 18, 143, 220, 23, 0);
            self.mode_combo = self.combo(&["固定配色", "随机配色"], 295, 138, 301);
            self.child("STATIC", "固定配色（45–52）", 0, 18, 185, 260, 23, 0);
            self.fixed_combo = self.combo(
                &[
                    "45 蓝紫 / 白",
                    "46 青 / 黑",
                    "47 琥珀 / 黑",
                    "48 薄荷 / 黑",
                    "49 玫红 / 白",
                    "50 天蓝 / 黑",
                    "51 淡紫 / 黑",
                    "52 珊瑚 / 黑",
                ],
                265,
                180,
                302,
            );
            self.child("STATIC", "随机周期", 0, 18, 227, 220, 23, 0);
            self.period_combo = self.combo(&["每日", "每小时", "每5分钟"], 295, 222, 303);
            self.child(
                "STATIC",
                "后台标题回改仍每秒检查一次。",
                0,
                18,
                267,
                390,
                25,
                0,
            );
            self.child("BUTTON", "保存", 0x00010001, 220, 317, 85, 30, 101);
            self.child("BUTTON", "取消", 0x00010000, 315, 317, 85, 30, 102);
        }
        let v = self.s.get();
        SetWindowTextW(self.fg, wide(&v.foreground.to_string()).as_ptr());
        SetWindowTextW(self.bg, wide(&v.background.to_string()).as_ptr());
        self.sync_auto();
        self.sync_theme_fields();
        SendMessageW(self.panel, 0x80, 0, self.nid.icon);
        SendMessageW(self.panel, 0x80, 1, self.nid.icon);
        if show {
            panel_visibility(self.panel, true);
            SetForegroundWindow(self.panel);
            SetFocus(self.fg);
        }
    }
    unsafe fn combo(&self, items: &[&str], x: i32, y: i32, id: isize) -> isize {
        let h = self.child("COMBOBOX", "", 0x00210003, x, y, 140, 190, id);
        for text in items {
            SendMessageW(h, 0x143, 0, wide(text).as_ptr() as isize);
        }
        h
    }
    unsafe fn sync_theme_fields(&self) {
        let s = self
            .theme
            .as_ref()
            .map(|t| t.state.clone())
            .unwrap_or_default();
        SendMessageW(
            self.mode_combo,
            0x14e,
            if s.pref.mode == Mode::Random { 1 } else { 0 },
            0,
        );
        SendMessageW(self.fixed_combo, 0x14e, (s.pref.fixed - 45) as usize, 0);
        SendMessageW(
            self.period_combo,
            0x14e,
            match s.pref.period {
                Period::Day => 0,
                Period::Hour => 1,
                Period::FiveMinutes => 2,
            },
            0,
        );
        self.enable_theme_fields();
    }
    unsafe fn enable_theme_fields(&self) {
        let random = SendMessageW(self.mode_combo, 0x147, 0, 0) == 1;
        EnableWindow(self.fixed_combo, if random { 0 } else { 1 });
        EnableWindow(self.period_combo, if random { 1 } else { 0 });
    }
    unsafe fn install_theme(&mut self, id: u32) -> Result<(), String> {
        if self.icon_id == id {
            return Ok(());
        }
        let h = (self.asset_loader)(id)?;
        let old = self.nid.icon;
        self.nid.icon = h;
        if !self.test && !self.update(1) {
            self.nid.icon = old;
            DestroyIcon(h);
            return Err("托盘图标更新失败".into());
        }
        for w in [self.hwnd, self.panel] {
            if w != 0 {
                SendMessageW(w, 0x80, 0, h);
                SendMessageW(w, 0x80, 1, h);
            }
        }
        if self.icon_owned && old != 0 {
            DestroyIcon(old);
        }
        self.icon_owned = true;
        self.icon_id = id;
        Ok(())
    }
    unsafe fn tick_theme(&mut self) {
        if let Some(mut theme) = self.theme.take() {
            let mut install = |id| self.install_theme(id);
            if let Err(e) = theme.tick(&mut install) {
                eprintln!("icon theme: {e}");
            }
            self.theme = Some(theme);
        }
    }
    unsafe fn sync_auto(&self) {
        if self.auto_check != 0 {
            SendMessageW(
                self.auto_check,
                0xf1,
                if self.s.get().autostart { 1 } else { 0 },
                0,
            );
        }
    }
    unsafe fn error(&self, e: &str) {
        if !self.test {
            MessageBoxW(
                self.panel,
                wide(e).as_ptr(),
                wide("扫描间隔设置").as_ptr(),
                0x10,
            );
        }
    }
    unsafe fn commit(&mut self) {
        let parse = |h| {
            let mut b = [0u16; 64];
            let n = GetWindowTextW(h, b.as_mut_ptr(), 64);
            String::from_utf16_lossy(&b[..n as usize])
                .trim()
                .parse::<u64>()
        };
        let (a, b) = match (parse(self.fg), parse(self.bg)) {
            (Ok(a), Ok(b)) => (a, b),
            _ => {
                self.error("请输入整数秒数");
                return;
            }
        };
        let mut v = self.s.get();
        v.foreground = a;
        v.background = b;
        v.autostart = SendMessageW(self.auto_check, 0xf0, 0, 0) == 1;
        if !v.valid() {
            self.error("前台间隔需为1–3600秒，后台间隔需为5–3600秒");
            return;
        }
        if self.theme.is_some()
            && (!(0..=1).contains(&SendMessageW(self.mode_combo, 0x147, 0, 0))
                || !(0..=2).contains(&SendMessageW(self.period_combo, 0x147, 0, 0)))
        {
            self.error("请选择有效图标模式和周期");
            return;
        }
        let result = if let Some(mut theme) = self.theme.take() {
            let p = Preference {
                mode: if SendMessageW(self.mode_combo, 0x147, 0, 0) == 1 {
                    Mode::Random
                } else {
                    Mode::Fixed
                },
                fixed: (SendMessageW(self.fixed_combo, 0x147, 0, 0) + 45) as u32,
                period: match SendMessageW(self.period_combo, 0x147, 0, 0) {
                    1 => Period::Hour,
                    2 => Period::FiveMinutes,
                    _ => Period::Day,
                },
            };
            let live = self.s.clone();
            let mut install = |id| self.install_theme(id);
            let r = match theme.transaction(p, &mut install) {
                Ok(mut tx) => live.save_extra(v, Some(&mut tx)),
                Err(e) => Err(e),
            };
            self.theme = Some(theme);
            r
        } else {
            self.s.save(v)
        };
        if let Err(e) = result {
            self.sync_auto();
            self.error(&e);
            return;
        }
        if !self.test {
            let _ = self.update(1);
        }
        panel_visibility(self.panel, false);
    }
    unsafe fn command(&mut self, c: u32) {
        match c {
            1 => {
                let mut v = self.s.get();
                v.enabled = !v.enabled;
                if let Err(e) = self.s.save(v) {
                    self.error(&e)
                } else if !self.test {
                    let _ = self.update(1);
                }
            }
            4 => {
                let mut v = self.s.get();
                v.autostart = !v.autostart;
                if let Err(e) = self.s.save(v) {
                    self.sync_auto();
                    self.error(&e)
                } else {
                    self.sync_auto();
                    if !self.test {
                        let _ = self.update(1);
                    }
                }
            }
            2 => self.show(!self.test),
            3 => crate::QUIT.store(true, Ordering::Relaxed),
            _ => {}
        }
    }
    unsafe fn popup(&mut self) {
        let menu = CreatePopupMenu();
        if menu == 0 {
            return;
        }
        let v = self.s.get();
        AppendMenuW(
            menu,
            if v.enabled { 8 } else { 0 },
            1,
            wide("启用窗口标题").as_ptr(),
        );
        AppendMenuW(
            menu,
            if v.autostart { 8 } else { 0 },
            4,
            wide("开机自启动").as_ptr(),
        );
        AppendMenuW(menu, 0, 2, wide("扫描间隔设置…").as_ptr());
        AppendMenuW(menu, 0x800, 0, ptr::null());
        AppendMenuW(menu, 0, 3, wide("退出并还原标题").as_ptr());
        let mut p = Point::default();
        GetCursorPos(&mut p);
        SetForegroundWindow(self.hwnd);
        let c = TrackPopupMenu(menu, 0x182, p.x, p.y, 0, self.hwnd, ptr::null());
        DestroyMenu(menu);
        self.command(c);
        PostMessageW(self.hwnd, 0, 0, 0);
    }
}
fn theme_asset(id: u32) -> Result<std::path::PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let dir = exe.parent().ok_or("exe-parent")?;
    for base in [
        "themes",
        "assets/themes",
        "../assets/themes",
        "../../assets/themes",
        "../../../assets/themes",
    ] {
        let p = dir.join(base).join(format!("{id}.ico"));
        if p.is_file() {
            return Ok(p);
        }
    }
    Err(format!("图标资源不可用：{id}"))
}
fn load_theme_asset(id: u32) -> Result<isize, String> {
    let p = theme_asset(id)?;
    let h = unsafe { LoadImageW(0, wide(&p.to_string_lossy()).as_ptr(), 1, 0, 0, 0x50) };
    if h == 0 {
        Err(format!("图标资源无法加载：{id}"))
    } else {
        Ok(h)
    }
}
fn validate_theme_asset(id: u32) -> Result<(), String> {
    let h = load_theme_asset(id)?;
    unsafe {
        DestroyIcon(h);
    }
    Ok(())
}

pub fn run(s: Arc<Live>, work: impl FnOnce()) -> Result<(), String> {
    let (tx, rx) = mpsc::sync_channel(1);
    let ui = thread::spawn(move || unsafe {
        match Tray::create(s, false) {
            Err(e) => {
                let _ = tx.send(Err(e));
            }
            Ok(t) => {
                let _ = tx.send(Ok(t.hwnd));
                let mut msg = Msg::default();
                while GetMessageW(&mut msg, 0, 0, 0) > 0 {
                    TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                }
                UI.with(|v| v.set(ptr::null_mut()));
                crate::QUIT.store(true, Ordering::Relaxed);
                drop(t);
            }
        }
    });
    let hwnd = rx.recv().map_err(|_| "tray-thread".to_owned())??;
    work();
    unsafe {
        PostMessageW(hwnd, 0x10, 0, 0);
    }
    ui.join().map_err(|_| "tray-thread-panic".to_owned())?;
    Ok(())
}
#[cfg(test)]
#[repr(C)]
struct OwnedIconInfo {
    icon: i32,
    x: u32,
    y: u32,
    mask: isize,
    color: isize,
}
#[cfg(test)]
fn owned_fake_icon(_id: u32) -> Result<isize, String> {
    let p =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/chatgpt-titlesync.ico");
    let h = unsafe { LoadImageW(0, wide(&p.to_string_lossy()).as_ptr(), 1, 0, 0, 0x50) };
    if h == 0 {
        Err("owned original icon fixture failed to load".into())
    } else {
        Ok(h)
    }
}
#[cfg(test)]
unsafe fn owned_icon_alive(h: isize) -> bool {
    let mut info: OwnedIconInfo = mem::zeroed();
    if GetIconInfo(h, &mut info) == 0 {
        return false;
    }
    if info.mask != 0 {
        DeleteObject(info.mask);
    }
    if info.color != 0 {
        DeleteObject(info.color);
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Clone)]
    struct TestThemeStore {
        state: Arc<std::sync::Mutex<crate::theme_windows::State>>,
        writes: Arc<std::sync::atomic::AtomicUsize>,
    }
    impl crate::theme_windows::Store for TestThemeStore {
        fn load(&self) -> Result<crate::theme_windows::State, String> {
            Ok(self.state.lock().unwrap().clone())
        }
        fn save(
            &self,
            s: &crate::theme_windows::State,
        ) -> Result<crate::theme_windows::Undo, String> {
            let old = self.state.lock().unwrap().clone();
            *self.state.lock().unwrap() = s.clone();
            self.writes.fetch_add(1, Ordering::Relaxed);
            let state = self.state.clone();
            Ok(Box::new(move || {
                *state.lock().unwrap() = old;
                Ok(())
            }))
        }
    }
    struct TestStartup {
        fail: std::sync::atomic::AtomicBool,
    }
    impl crate::settings::Startup for TestStartup {
        fn apply(&self, _on: bool) -> Result<crate::settings::UndoStartup, String> {
            if self.fail.load(Ordering::Relaxed) {
                return Err("injected startup failure".into());
            }
            Ok(Box::new(|| Ok(())))
        }
    }
    #[test]
    fn owned_hidden_native_settings() {
        unsafe {
            assert_eq!(mem::size_of::<Class>(), 80);
            assert_eq!(mem::size_of::<Msg>(), 48);
            assert_eq!(mem::size_of::<Icon>(), 976);
            let dir = std::env::temp_dir().join(format!("title-rust-ui-{}", std::process::id()));
            let backend = Arc::new(TestStartup {
                fail: std::sync::atomic::AtomicBool::new(false),
            });
            let s = Arc::new(Live::with_startup(
                dir.join("settings.conf"),
                crate::settings::Values {
                    foreground: crate::settings::DEFAULT_FOREGROUND,
                    background: crate::settings::DEFAULT_BACKGROUND,
                    enabled: true,
                    autostart: true,
                    revision: 0,
                },
                Some(backend.clone()),
            ));
            let mut t = Tray::create(s.clone(), true).unwrap();
            t.show(false);
            assert_ne!(t.mode_combo, 0);
            assert_ne!(t.fixed_combo, 0);
            assert_ne!(t.period_combo, 0);
            assert_ne!(IsWindowEnabled(t.fixed_combo), 0);
            assert_eq!(IsWindowEnabled(t.period_combo), 0);
            assert_eq!(
                GetWindowLongPtrW(t.mode_combo, -16) & 15,
                3,
                "noneditable dropdown"
            );
            SendMessageW(t.mode_combo, 0x14e, 1, 0);
            SendMessageW(t.panel, 0x111, (1 << 16) | 301, t.mode_combo);
            assert_eq!(IsWindowEnabled(t.fixed_combo), 0);
            assert_ne!(IsWindowEnabled(t.period_combo), 0);
            t.sync_theme_fields();
            t.asset_loader = owned_fake_icon;
            let first = (t.asset_loader)(45).unwrap();
            if t.icon_owned {
                DestroyIcon(t.nid.icon);
            }
            t.nid.icon = first;
            t.icon_owned = true;
            t.icon_id = 45;
            assert!(owned_icon_alive(first));
            t.install_theme(46).unwrap();
            assert!(!owned_icon_alive(first));
            assert!(owned_icon_alive(t.nid.icon));
            assert_eq!(SendMessageW(t.panel, 0x7f, 0, 0), t.nid.icon);
            let store = TestThemeStore {
                state: Arc::new(std::sync::Mutex::new(Default::default())),
                writes: Arc::new(std::sync::atomic::AtomicUsize::new(0)),
            };
            let (theme, error) = Controller::new(
                Arc::new(store.clone()),
                Box::new(|| crate::theme_windows::Moment {
                    year: 2026,
                    month: 11,
                    day: 11,
                    hour: 9,
                    minute: 4,
                    offset_minutes: 480,
                }),
                Box::new(|_| Ok(0)),
                Box::new(|id| {
                    let h = owned_fake_icon(id)?;
                    DestroyIcon(h);
                    Ok(())
                }),
            );
            assert!(error.is_none());
            t.theme = Some(theme);
            t.install_theme(45).unwrap();
            t.sync_theme_fields();
            SendMessageW(t.mode_combo, 0x14e, 1, 0);
            SendMessageW(t.period_combo, 0x14e, 2, 0);
            SendMessageW(t.panel, 0x111, 102, 0);
            assert_eq!(store.writes.load(Ordering::Relaxed), 0);
            assert_eq!(t.theme.as_ref().unwrap().state, Default::default());
            t.show(false);
            assert_eq!(SendMessageW(t.mode_combo, 0x147, 0, 0), 0);
            SendMessageW(t.mode_combo, 0x14e, 1, 0);
            SendMessageW(t.period_combo, 0x14e, 2, 0);
            t.commit();
            assert_eq!(store.writes.load(Ordering::Relaxed), 1);
            assert_eq!(t.theme.as_ref().unwrap().state.pref.mode, Mode::Random);
            assert_eq!(
                t.theme.as_ref().unwrap().state.pref.period,
                Period::FiveMinutes
            );
            t.theme = None;
            assert_ne!(t.auto_check, 0);
            assert_eq!(SendMessageW(t.auto_check, 0xf0, 0, 0), 1);
            SendMessageW(t.auto_check, 0xf1, 0, 0);
            assert!(s.get().autostart);
            SendMessageW(t.panel, 0x111, 102, 0);
            assert!(s.get().autostart);
            t.show(false);
            assert_eq!(SendMessageW(t.auto_check, 0xf0, 0, 0), 1);
            SetWindowPos(t.panel, 0, -32000, -32000, 0, 0, 0x15);
            assert!(panel_visibility(t.panel, true));
            assert!(panel_visibility(t.panel, false));
            assert_eq!(
                GetWindow(t.panel, 4),
                0,
                "settings window must have no hidden owner"
            );
            assert_ne!(
                GetWindowLongPtrW(t.panel, -20) & 0x40000,
                0,
                "settings window must have WS_EX_APPWINDOW"
            );
            assert_ne!(t.fg, 0);
            assert_ne!(t.bg, 0);
            SetWindowTextW(t.fg, wide("2").as_ptr());
            SetWindowTextW(t.bg, wide("5").as_ptr());
            t.commit();
            assert_eq!(s.get().foreground, 2);
            assert_eq!(crate::settings::load(&s.path, s.get()).background, 5);
            let before = s.get();
            SetWindowTextW(t.fg, wide("0").as_ptr());
            t.commit();
            assert_eq!(s.get(), before);
            SetWindowTextW(t.fg, wide("abc").as_ptr());
            t.commit();
            assert_eq!(s.get(), before);
            SendMessageW(t.hwnd, 0x111, 4, 0);
            assert!(!s.get().autostart);
            assert_eq!(SendMessageW(t.auto_check, 0xf0, 0, 0), 0);
            assert!(!crate::settings::load(&s.path, s.get()).autostart);
            SetWindowTextW(t.fg, wide("7").as_ptr());
            SendMessageW(t.hwnd, 0x111, 4, 0);
            assert!(s.get().autostart);
            assert_eq!(SendMessageW(t.auto_check, 0xf0, 0, 0), 1);
            let mut draft = [0u16; 8];
            GetWindowTextW(t.fg, draft.as_mut_ptr(), 8);
            assert_eq!(String::from_utf16_lossy(&draft[..1]), "7");
            SendMessageW(t.auto_check, 0xf1, 0, 0);
            t.commit();
            assert!(!s.get().autostart);
            assert!(!crate::settings::load(&s.path, s.get()).autostart);
            let before_failure = s.get();
            backend.fail.store(true, Ordering::Relaxed);
            SendMessageW(t.hwnd, 0x111, 4, 0);
            assert_eq!(s.get(), before_failure);
            assert_eq!(SendMessageW(t.auto_check, 0xf0, 0, 0), 0);
            backend.fail.store(false, Ordering::Relaxed);
            SendMessageW(t.hwnd, 0x111, 1, 0);
            assert!(!s.get().enabled);
            SendMessageW(t.hwnd, 0x10, 0, 0);
            UI.with(|v| v.set(ptr::null_mut()));
            let _ = std::fs::remove_dir_all(dir);
        }
    }
}
