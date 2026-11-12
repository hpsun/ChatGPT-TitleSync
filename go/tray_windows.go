//go:build windows && amd64

package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"unsafe"
)

type trayPoint struct{ X, Y int32 }
type trayMsg struct {
	H       uintptr
	Message uint32
	W, L    uintptr
	Time    uint32
	Point   trayPoint
	Private uint32
}
type trayClass struct {
	Size, Style                                               uint32
	Proc                                                      uintptr
	ClassExtra, WindowExtra                                   int32
	Instance, Icon, Cursor, Background, Menu, Name, SmallIcon uintptr
}
type trayIcon struct {
	Size                uint32
	H                   uintptr
	ID, Flags, Callback uint32
	Icon                uintptr
	Tip                 [128]uint16
	State, StateMask    uint32
	Info                [256]uint16
	Timeout             uint32
	InfoTitle           [64]uint16
	InfoFlags           uint32
	GUID                [16]byte
	Balloon             uintptr
}
type winTray struct {
	settings                                     *liveSettings
	cancel                                       context.CancelFunc
	hwnd, panel, fgEdit, bgEdit, autoCheck, icon uintptr
	modeCombo, fixedCombo, periodCombo           uintptr
	theme                                        *iconThemeController
	iconOwned                                    bool
	iconID                                       int
	nid                                          trayIcon
	done                                         chan struct{}
	test                                         bool
	taskbar                                      uint32
	assetLoader                                  func(int) (uintptr, error)
}

var trayInstances sync.Map
var trayU = syscall.NewLazyDLL("user32.dll")
var trayK = syscall.NewLazyDLL("kernel32.dll")
var trayS = syscall.NewLazyDLL("shell32.dll")
var trayG = syscall.NewLazyDLL("gdi32.dll")
var trayCallback = syscall.NewCallback(trayWndProc)

// UTF-16 text is retained for the UI lifetime. uintptr itself is not a GC root.
var trayText sync.Map

func tu(s string) uintptr {
	if p, ok := trayText.Load(s); ok {
		return uintptr(unsafe.Pointer(p.(*uint16)))
	}
	p := ptr(s)
	actual, _ := trayText.LoadOrStore(s, p)
	return uintptr(unsafe.Pointer(actual.(*uint16)))
}

//go:uintptrescapes
func uiCall(name string, a ...uintptr) uintptr { r, _, _ := trayU.NewProc(name).Call(a...); return r }
func iconCall(cmd uintptr, n *trayIcon) bool {
	r, _, _ := trayS.NewProc("Shell_NotifyIconW").Call(cmd, uintptr(unsafe.Pointer(n)))
	return r != 0
}
func trayWndProc(h uintptr, m uint32, w, l uintptr) uintptr {
	if v, ok := trayInstances.Load(h); ok {
		t := v.(*winTray)
		if m == t.taskbar && !t.test {
			t.updateIcon(0)
			return 0
		}
		switch m {
		case 0x113:
			if h == t.hwnd && w == 90 && t.theme != nil {
				if e := t.theme.tick(); e != nil {
					fmt.Fprintln(os.Stderr, "icon theme:", e)
				}
			}
			return 0
		case 0x8001:
			if l == 0x205 || l == 0x7b {
				t.popup()
			}
			return 0
		case 0x111:
			id := w & 0xffff
			if h == t.panel {
				if id == 401 && !t.test {
					if e := openNameRuleEditor(filepath.Dir(t.settings.path)); e != nil {
						t.error(e)
					}
				}
				if id == 301 && (w>>16) == 1 {
					t.enableThemeFields()
				}
				if id == 101 {
					t.commitDialog()
				}
				if id == 102 {
					setPanelVisibility(h, false)
				}
				return 0
			}
			if h == t.hwnd && id >= 1 && id <= 5 {
				t.command(id)
				return 0
			}
		case 0x10:
			if h == t.panel {
				setPanelVisibility(h, false)
				return 0
			}
			uiCall("KillTimer", t.hwnd, 90)
			if t.panel != 0 {
				uiCall("DestroyWindow", t.panel)
			}
			if !t.test {
				iconCall(2, &t.nid)
			}
			uiCall("DestroyWindow", h)
			if t.iconOwned {
				uiCall("DestroyIcon", t.icon)
				t.iconOwned = false
			}
			return 0
		case 0x2:
			trayInstances.Delete(h)
			if h == t.hwnd {
				uiCall("PostQuitMessage", 0)
			}
			return 0
		}
	}
	return uiCall("DefWindowProcW", h, uintptr(m), w, l)
}
func (t *winTray) updateIcon(command uintptr) bool {
	s := t.settings.snapshot()
	t.nid.Flags = 7
	tip := fmt.Sprintf("ChatGPT 标题同步助手（Go）\n前台%d秒；后台%d秒", s.ForegroundSeconds, s.BackgroundSeconds)
	copy(t.nid.Tip[:], syscall.StringToUTF16(tip))
	return iconCall(command, &t.nid)
}
func (t *winTray) popup() {
	menu := uiCall("CreatePopupMenu")
	if menu == 0 {
		return
	}
	defer uiCall("DestroyMenu", menu)
	checked := uintptr(0)
	if t.settings.snapshot().Enabled {
		checked = 8
	}
	uiCall("AppendMenuW", menu, checked, 1, tu("启用窗口标题"))
	autoChecked := uintptr(0)
	if t.settings.snapshot().AutoStartEnabled {
		autoChecked = 8
	}
	uiCall("AppendMenuW", menu, autoChecked, 4, tu("开机自启动"))
	uiCall("AppendMenuW", menu, 0, 2, tu("扫描间隔设置…"))
	uiCall("AppendMenuW", menu, 0, 5, tu("Name replacement… / 名称替换…"))
	uiCall("AppendMenuW", menu, 0x800, 0, 0)
	uiCall("AppendMenuW", menu, 0, 3, tu("退出并还原标题"))
	var point trayPoint
	uiCall("GetCursorPos", uintptr(unsafe.Pointer(&point)))
	uiCall("SetForegroundWindow", t.hwnd)
	command := uiCall("TrackPopupMenu", menu, 0x182, uintptr(point.X), uintptr(point.Y), 0, t.hwnd, 0)
	t.command(command)
	uiCall("PostMessageW", t.hwnd, 0, 0, 0)
}
func (t *winTray) command(command uintptr) {
	switch command {
	case 5:
		if !t.test {
			if e := openNameRuleEditor(filepath.Dir(t.settings.path)); e != nil {
				t.error(e)
			}
		}

	case 1:
		s := t.settings.snapshot()
		s.Enabled = !s.Enabled
		if e := t.settings.save(s); e != nil {
			t.error(e)
		} else if !t.test {
			t.updateIcon(1)
		}
	case 4:
		s := t.settings.snapshot()
		s.AutoStartEnabled = !s.AutoStartEnabled
		if e := t.settings.save(s); e != nil {
			t.syncAutoCheck()
			t.error(e)
		} else {
			t.syncAutoCheck()
			if !t.test {
				t.updateIcon(1)
			}
		}
	case 2:
		t.showSettings(!t.test)
	case 3:
		t.cancel()
	}
}

// SetWindowPos avoids STARTUPINFO.wShowWindow overriding a process's first ShowWindow call.
func setPanelVisibility(panel uintptr, visible bool) bool {
	flags := uintptr(0x97)
	if visible {
		flags = 0x57
	}
	return uiCall("SetWindowPos", panel, 0, 0, 0, 0, 0, flags) != 0
}
func (t *winTray) syncAutoCheck() {
	if t.autoCheck != 0 {
		checked := uintptr(0)
		if t.settings.snapshot().AutoStartEnabled {
			checked = 1
		}
		uiCall("SendMessageW", t.autoCheck, 0xf1, checked, 0)
	}
}
func (t *winTray) child(class, text string, style uint32, x, y, w, h int32, id uintptr) uintptr {
	win := uiCall("CreateWindowExW", 0, tu(class), tu(text), uintptr(style|0x50000000), uintptr(x), uintptr(y), uintptr(w), uintptr(h), t.panel, id, 0, 0)
	font, _, _ := trayG.NewProc("GetStockObject").Call(17)
	uiCall("SendMessageW", win, 0x30, font, 1)
	return win
}
func (t *winTray) showSettings(show bool) {
	s := t.settings.snapshot()
	if t.panel == 0 {
		cls := fmt.Sprintf("ChatGPTTitleGoTray_%d", os.Getpid())
		t.panel = uiCall("CreateWindowExW", 0x00040000, tu(cls), tu("ChatGPT 标题同步助手 · Go — 设置"), 0x00c80000, 0x80000000, 0x80000000, 450, 450, 0, 0, 0, 0)
		if t.panel == 0 {
			return
		}
		trayInstances.Store(t.panel, t)
		t.child("STATIC", "前台扫描间隔（秒，1–3600）", 0, 18, 20, 260, 23, 0)
		t.fgEdit = t.child("EDIT", "", 0x00810080, 295, 18, 105, 25, 201)
		t.child("STATIC", "后台刷新间隔（秒，5–3600）", 0, 18, 62, 260, 23, 0)
		t.bgEdit = t.child("EDIT", "", 0x00810080, 295, 60, 105, 25, 202)
		t.autoCheck = t.child("BUTTON", "开机自启动", 0x00010003, 18, 103, 260, 27, 203)
		t.child("STATIC", "图标模式", 0, 18, 143, 220, 23, 0)
		t.modeCombo = t.combo([]string{"固定配色", "随机配色"}, 295, 138, 301)
		t.child("STATIC", "固定配色（45–52）", 0, 18, 185, 260, 23, 0)
		t.fixedCombo = t.combo([]string{"45 蓝紫 / 白", "46 青 / 黑", "47 琥珀 / 黑", "48 薄荷 / 黑", "49 玫红 / 白", "50 天蓝 / 黑", "51 淡紫 / 黑", "52 珊瑚 / 黑"}, 265, 180, 302)
		t.child("STATIC", "随机周期", 0, 18, 227, 220, 23, 0)
		t.periodCombo = t.combo([]string{"每日", "每小时", "每5分钟"}, 295, 222, 303)
		t.child("STATIC", "后台标题回改仍每秒检查一次。", 0, 18, 267, 390, 25, 0)
		t.child("BUTTON", "Name replacement… / 名称替换…", 0x00010000, 18, 307, 300, 30, 401)
		t.child("BUTTON", "保存", 0x00010001, 220, 357, 85, 30, 101)
		t.child("BUTTON", "取消", 0x00010000, 315, 357, 85, 30, 102)
	}
	uiCall("SetWindowTextW", t.fgEdit, tu(strconv.Itoa(s.ForegroundSeconds)))
	uiCall("SetWindowTextW", t.bgEdit, tu(strconv.Itoa(s.BackgroundSeconds)))
	t.syncAutoCheck()
	t.syncThemeFields()
	if t.icon != 0 {
		uiCall("SendMessageW", t.panel, 0x80, 0, t.icon)
		uiCall("SendMessageW", t.panel, 0x80, 1, t.icon)
	}
	if show {
		setPanelVisibility(t.panel, true)
		uiCall("SetForegroundWindow", t.panel)
		uiCall("SetFocus", t.fgEdit)
	}
}
func editValue(h uintptr) (int, error) {
	b := make([]uint16, 64)
	n := uiCall("GetWindowTextW", h, uintptr(unsafe.Pointer(&b[0])), uintptr(len(b)))
	return strconv.Atoi(strings.TrimSpace(syscall.UTF16ToString(b[:n])))
}
func (t *winTray) commitDialog() {
	a, e := editValue(t.fgEdit)
	if e != nil {
		t.error(fmt.Errorf("请输入整数秒数"))
		return
	}
	b, e := editValue(t.bgEdit)
	if e != nil {
		t.error(fmt.Errorf("请输入整数秒数"))
		return
	}
	s := t.settings.snapshot()
	s.ForegroundSeconds = a
	s.BackgroundSeconds = b
	s.AutoStartEnabled = uiCall("SendMessageW", t.autoCheck, 0xf0, 0, 0) == 1
	if e = validSettings(s); e != nil {
		t.error(e)
		return
	}
	var extra settingsExtra
	if t.theme != nil {
		mode := uiCall("SendMessageW", t.modeCombo, 0x147, 0, 0)
		period := uiCall("SendMessageW", t.periodCombo, 0x147, 0, 0)
		if mode > 1 || period > 2 {
			t.error(fmt.Errorf("请选择有效图标模式和周期"))
			return
		}
		p := iconPreference{Mode: "fixed", Fixed: int(uiCall("SendMessageW", t.fixedCombo, 0x147, 0, 0)) + 45, Period: "day"}
		if uiCall("SendMessageW", t.modeCombo, 0x147, 0, 0) == 1 {
			p.Mode = "random"
		}
		switch uiCall("SendMessageW", t.periodCombo, 0x147, 0, 0) {
		case 1:
			p.Period = "hour"
		case 2:
			p.Period = "5min"
		}
		tx, err := t.theme.transaction(p)
		if err != nil {
			t.error(err)
			return
		}
		extra = tx
	}
	if e = t.settings.saveExtra(s, extra); e != nil {
		t.syncAutoCheck()
		t.error(e)
		return
	}
	if !t.test {
		t.updateIcon(1)
	}
	setPanelVisibility(t.panel, false)
}
func (t *winTray) error(e error) {
	if !t.test {
		uiCall("MessageBoxW", t.panel, tu(e.Error()), tu("扫描间隔设置"), 0x10)
	}
}
func loadTrayIcon() (uintptr, bool) {
	exe, _ := os.Executable()
	dir := filepath.Dir(exe)
	for _, p := range []string{filepath.Join(dir, "chatgpt-titlesync.ico"), filepath.Join(dir, "..", "assets", "chatgpt-titlesync.ico"), filepath.Join(dir, "..", "..", "assets", "chatgpt-titlesync.ico")} {
		if _, e := os.Stat(p); e == nil {
			if h := uiCall("LoadImageW", 0, tu(p), 1, 0, 0, 0x50); h != 0 {
				return h, true
			}
		}
	}
	instance, _, _ := trayK.NewProc("GetModuleHandleW").Call(0)
	if h := uiCall("LoadIconW", instance, 1); h != 0 {
		return h, false
	}
	return uiCall("LoadIconW", 0, 32512), false
}

// Compatibility: retain ChatGPTTitleGoTray_ as an internal automation class; visible titles use the new brand.
func newWinTray(settings *liveSettings, cancel context.CancelFunc, test bool) (*winTray, error) {
	t := &winTray{settings: settings, cancel: cancel, done: make(chan struct{}), test: test}
	instance, _, _ := trayK.NewProc("GetModuleHandleW").Call(0)
	name := ptr(fmt.Sprintf("ChatGPTTitleGoTray_%d", os.Getpid()))
	c := trayClass{Size: uint32(unsafe.Sizeof(trayClass{})), Proc: trayCallback, Instance: instance, Background: 6, Name: uintptr(unsafe.Pointer(name))}
	c.Cursor = uiCall("LoadCursorW", 0, 32512)
	registered := uiCall("RegisterClassExW", uintptr(unsafe.Pointer(&c)))
	if registered == 0 {
		var existing trayClass
		existing.Size = uint32(unsafe.Sizeof(existing))
		if uiCall("GetClassInfoExW", instance, uintptr(unsafe.Pointer(name)), uintptr(unsafe.Pointer(&existing))) == 0 || existing.Proc != trayCallback {
			return nil, fmt.Errorf("tray-window-class")
		}
	}
	t.hwnd = uiCall("CreateWindowExW", 0, uintptr(unsafe.Pointer(name)), tu("ChatGPT-TitleSync Go tray"), 0, 0, 0, 0, 0, 0, 0, instance, 0)
	if t.hwnd == 0 {
		return nil, fmt.Errorf("tray-window")
	}
	trayInstances.Store(t.hwnd, t)
	t.taskbar = uint32(uiCall("RegisterWindowMessageW", tu("TaskbarCreated")))
	t.icon, t.iconOwned = loadTrayIcon()
	t.nid = trayIcon{Size: uint32(unsafe.Sizeof(trayIcon{})), H: t.hwnd, ID: 1, Icon: t.icon, Callback: 0x8001}
	if !test && !t.updateIcon(0) {
		uiCall("DestroyWindow", t.hwnd)
		return nil, fmt.Errorf("tray icon could not be added; use --no-tray for CLI controls")
	}
	if !test {
		store := registryIconThemeStore{nativeStartupRegistry{}, startupPreferencePath}
		var err error
		t.theme, err = newIconThemeController(store, t.validateThemeAsset, t.installThemeAsset)
		// Invalid preferences only affect display fallback; no silent registry rewrite.
		if err != nil {
			fmt.Fprintln(os.Stderr, "icon theme:", err)
		}
		if err = t.theme.tick(); err != nil {
			fmt.Fprintln(os.Stderr, "icon theme:", err)
		}
		if err = t.installThemeAsset(t.theme.snapshot().id()); err != nil {
			fmt.Fprintln(os.Stderr, "icon theme:", err)
		}
		uiCall("SetTimer", t.hwnd, 90, 1000, 0)
	}
	return t, nil
}
func runWithTray(ctx context.Context, settings *liveSettings, cancel context.CancelFunc, work func()) error {
	ready := make(chan *winTray, 1)
	failed := make(chan error, 1)
	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		t, e := newWinTray(settings, cancel, false)
		if e != nil {
			failed <- e
			return
		}
		ready <- t
		defer close(t.done)
		defer cancel()
		var msg trayMsg
		for {
			r := uiCall("GetMessageW", uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
			if int32(r) <= 0 {
				break
			}
			uiCall("TranslateMessage", uintptr(unsafe.Pointer(&msg)))
			uiCall("DispatchMessageW", uintptr(unsafe.Pointer(&msg)))
		}
	}()
	var t *winTray
	select {
	case t = <-ready:
	case e := <-failed:
		return e
	}
	work()
	uiCall("PostMessageW", t.hwnd, 0x10, 0, 0)
	<-t.done
	return nil
}
