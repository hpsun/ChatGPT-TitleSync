//go:build windows && amd64

package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
	"unsafe"
)

type rejectableStartup struct{ fail bool }

func (r *rejectableStartup) Apply(on bool) (func() error, error) {
	if r.fail {
		return nil, fmt.Errorf("injected startup failure")
	}
	return func() error { return nil }, nil
}
func TestOwnedNativeSettingsWindow(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if unsafe.Sizeof(trayClass{}) != 80 || unsafe.Sizeof(trayMsg{}) != 48 || unsafe.Sizeof(trayIcon{}) != 976 {
		t.Fatal("Win32 ABI")
	}
	s := &liveSettings{value: scanSettings{defaultForegroundSeconds, defaultBackgroundSeconds, true, true, 0}, path: filepath.Join(t.TempDir(), "settings.json")}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	tr, e := newWinTray(s, cancel, true)
	if e != nil {
		t.Fatal(e)
	}
	defer uiCall("SendMessageW", tr.hwnd, 0x10, 0, 0)
	tr.showSettings(false)
	if tr.modeCombo == 0 || tr.fixedCombo == 0 || tr.periodCombo == 0 || uiCall("IsWindowEnabled", tr.fixedCombo) == 0 || uiCall("IsWindowEnabled", tr.periodCombo) != 0 {
		t.Fatal("theme fixed-mode field enablement")
	}
	uiCall("SendMessageW", tr.modeCombo, 0x14e, 1, 0)
	uiCall("SendMessageW", tr.panel, 0x111, (1<<16)|301, tr.modeCombo)
	if uiCall("IsWindowEnabled", tr.fixedCombo) != 0 || uiCall("IsWindowEnabled", tr.periodCombo) == 0 {
		t.Fatal("theme random-mode field enablement")
	}
	tr.syncThemeFields()
	fakeIconPath, _ := filepath.Abs(filepath.Join("..", "assets", "chatgpt-titlesync.ico"))
	tr.assetLoader = func(int) (uintptr, error) {
		h := uiCall("LoadImageW", 0, tu(fakeIconPath), 1, 0, 0, 0x50)
		if h == 0 {
			return 0, fmt.Errorf("owned fake icon could not load")
		}
		return h, nil
	}
	firstIcon, _ := tr.assetLoader(45)
	if firstIcon == 0 {
		t.Fatal("fake icon fixture unavailable")
	}
	if tr.iconOwned {
		uiCall("DestroyIcon", tr.icon)
	}
	tr.icon = firstIcon
	tr.nid.Icon = firstIcon
	tr.iconOwned = true
	tr.iconID = 45
	if !ownedIconAlive(firstIcon) {
		t.Fatal("owned icon fixture invalid")
	}
	if e := tr.installThemeAsset(46); e != nil {
		t.Fatal(e)
	}
	if ownedIconAlive(firstIcon) || !ownedIconAlive(tr.icon) {
		t.Fatal("icon replacement did not dispose old owned handle after updating windows")
	}
	if uiCall("SendMessageW", tr.panel, 0x7f, 0, 0) != tr.icon {
		t.Fatal("settings window icon not updated")
	}
	store := &fakeIconStore{state: defaultIconTheme()}
	controller, e := newIconThemeController(store, tr.validateThemeAsset, tr.installThemeAsset)
	if e != nil {
		t.Fatal(e)
	}
	controller.clock = func() time.Time { return time.Date(2026, 11, 11, 9, 4, 0, 0, time.FixedZone("own", 8*3600)) }
	controller.pick = func(int) (int, error) { return 0, nil }
	tr.theme = controller
	if e := tr.installThemeAsset(45); e != nil {
		t.Fatal(e)
	}
	tr.syncThemeFields()
	uiCall("SendMessageW", tr.modeCombo, 0x14e, 1, 0)
	uiCall("SendMessageW", tr.periodCombo, 0x14e, 2, 0)
	uiCall("SendMessageW", tr.panel, 0x111, 102, 0)
	if store.writes != 0 || controller.snapshot() != defaultIconTheme() {
		t.Fatal("Cancel committed theme draft")
	}
	tr.showSettings(false)
	if uiCall("SendMessageW", tr.modeCombo, 0x147, 0, 0) != 0 {
		t.Fatal("Cancel theme draft survived reopen")
	}
	uiCall("SendMessageW", tr.modeCombo, 0x14e, 1, 0)
	uiCall("SendMessageW", tr.periodCombo, 0x14e, 2, 0)
	tr.commitDialog()
	if store.writes != 1 || controller.snapshot().Mode != "random" || controller.snapshot().Period != "5min" {
		t.Fatal("native theme Save did not commit")
	}
	tr.theme = nil
	if tr.autoCheck == 0 || uiCall("SendMessageW", tr.autoCheck, 0xf0, 0, 0) != 1 {
		t.Fatal("autostart must initially be checked")
	}
	uiCall("SendMessageW", tr.autoCheck, 0xf1, 0, 0)
	if !s.snapshot().AutoStartEnabled {
		t.Fatal("checkbox draft committed before Save")
	}
	uiCall("SendMessageW", tr.panel, 0x111, 102, 0)
	if !s.snapshot().AutoStartEnabled {
		t.Fatal("Cancel changed autostart")
	}
	tr.showSettings(false)
	if uiCall("SendMessageW", tr.autoCheck, 0xf0, 0, 0) != 1 {
		t.Fatal("reopen did not restore committed autostart")
	}
	if uiCall("GetWindow", tr.panel, 4) != 0 || uiCall("GetWindowLongPtrW", tr.panel, 0xffffffec)&0x40000 == 0 {
		t.Fatal("settings must be an independently discoverable top-level app window")
	}
	offscreen := int32(-32000)
	uiCall("SetWindowPos", tr.panel, 0, uintptr(offscreen), uintptr(offscreen), 0, 0, 0x15)
	if !setPanelVisibility(tr.panel, true) || uiCall("IsWindowVisible", tr.panel) == 0 {
		t.Fatal("own settings panel did not become visible")
	}
	setPanelVisibility(tr.panel, false)
	if tr.fgEdit == 0 || tr.bgEdit == 0 {
		t.Fatal("native edits absent")
	}
	uiCall("SetWindowTextW", tr.fgEdit, tu("2"))
	uiCall("SetWindowTextW", tr.bgEdit, tu("5"))
	tr.commitDialog()
	if s.snapshot().ForegroundSeconds != 2 || loadSettings(s.path, scanSettings{}).BackgroundSeconds != 5 {
		t.Fatal("input not applied")
	}
	v := s.snapshot()
	uiCall("SetWindowTextW", tr.fgEdit, tu("0"))
	tr.commitDialog()
	if s.snapshot() != v {
		t.Fatal("invalid range applied")
	}
	uiCall("SetWindowTextW", tr.fgEdit, tu("abc"))
	tr.commitDialog()
	if s.snapshot() != v {
		t.Fatal("noninteger applied")
	}
	backend := &rejectableStartup{}
	s.startup = backend
	uiCall("SendMessageW", tr.hwnd, 0x111, 4, 0)
	if s.snapshot().AutoStartEnabled || uiCall("SendMessageW", tr.autoCheck, 0xf0, 0, 0) != 0 || loadSettings(s.path, v).AutoStartEnabled {
		t.Fatal("menu did not persist/synchronize autostart off")
	}
	uiCall("SetWindowTextW", tr.fgEdit, tu("7"))
	uiCall("SendMessageW", tr.hwnd, 0x111, 4, 0)
	if !s.snapshot().AutoStartEnabled || uiCall("SendMessageW", tr.autoCheck, 0xf0, 0, 0) != 1 {
		t.Fatal("menu did not synchronize autostart on")
	}
	if got, _ := editValue(tr.fgEdit); got != 7 {
		t.Fatal("menu synchronization overwrote interval draft")
	}
	uiCall("SendMessageW", tr.autoCheck, 0xf1, 0, 0)
	tr.commitDialog()
	if s.snapshot().AutoStartEnabled || loadSettings(s.path, v).AutoStartEnabled {
		t.Fatal("checkbox Save did not commit autostart")
	}
	beforeFailure := s.snapshot()
	backend.fail = true
	uiCall("SendMessageW", tr.hwnd, 0x111, 4, 0)
	if s.snapshot() != beforeFailure || uiCall("SendMessageW", tr.autoCheck, 0xf0, 0, 0) != 0 {
		t.Fatal("failed menu operation reported false success")
	}
	backend.fail = false
	uiCall("SendMessageW", tr.hwnd, 0x111, 1, 0)
	if s.snapshot().Enabled || loadSettings(s.path, v).Enabled {
		t.Fatal("menu toggle failed")
	}
	uiCall("SendMessageW", tr.hwnd, 0x111, 3, 0)
	select {
	case <-ctx.Done():
	default:
		t.Fatal("menu exit did not cancel owned controller")
	}
}

// Exercise a posted command through the actual native message pump, without activation or real targets.
func TestPostedSettingsCommandOwnMessagePump(t *testing.T) {
	s := &liveSettings{value: scanSettings{defaultForegroundSeconds, defaultBackgroundSeconds, true, true, 0}, path: filepath.Join(t.TempDir(), "settings.json")}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ready := make(chan uintptr, 1)
	failed := make(chan error, 1)
	done := make(chan struct{})
	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		defer close(done)
		var msg trayMsg
		for uiCall("PeekMessageW", uintptr(unsafe.Pointer(&msg)), 0, 0x12, 0x12, 1) != 0 {
		}
		tr, e := newWinTray(s, cancel, true)
		if e != nil {
			failed <- e
			return
		}
		ready <- tr.hwnd
		for int32(uiCall("GetMessageW", uintptr(unsafe.Pointer(&msg)), 0, 0, 0)) > 0 {
			uiCall("TranslateMessage", uintptr(unsafe.Pointer(&msg)))
			uiCall("DispatchMessageW", uintptr(unsafe.Pointer(&msg)))
		}
	}()
	var hwnd uintptr
	select {
	case hwnd = <-ready:
	case e := <-failed:
		t.Fatal(e)
	case <-time.After(2 * time.Second):
		t.Fatal("own UI thread startup timeout")
	}
	defer func() {
		uiCall("PostMessageW", hwnd, 0x10, 0, 0)
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Error("own UI thread shutdown timeout")
		}
	}()
	// Force GC before dispatch, reproducing the lifetime conditions of a long-running resident.
	runtime.GC()
	if uiCall("PostMessageW", hwnd, 0x111, 2, 0) == 0 {
		t.Fatal("post settings failed")
	}
	cls := fmt.Sprintf("ChatGPTTitleGoTray_%d", os.Getpid())
	deadline := time.Now().Add(2 * time.Second)
	var panel uintptr
	for time.Now().Before(deadline) {
		panel = uiCall("FindWindowW", tu(cls), tu("ChatGPT 标题同步助手 · Go — 设置"))
		if panel != 0 && uiCall("GetDlgItem", panel, 201) != 0 && uiCall("GetDlgItem", panel, 202) != 0 && uiCall("GetDlgItem", panel, 101) != 0 && uiCall("GetDlgItem", panel, 102) != 0 {
			break
		}
		runtime.GC()
		time.Sleep(10 * time.Millisecond)
	}
	if panel == 0 {
		t.Fatal("posted settings command never created own panel")
	}
	for _, id := range []uintptr{201, 202, 203, 101, 102} {
		if uiCall("GetDlgItem", panel, id) == 0 {
			t.Fatal("settings native control missing", id)
		}
	}
	if uiCall("IsWindowVisible", panel) != 0 {
		t.Fatal("controlled panel must remain hidden")
	}
	uiCall("PostMessageW", hwnd, 0x111, 3, 0)
	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("posted quit did not cancel own controller")
	}
}

type ownedIconInfo struct {
	icon        int32
	x, y        uint32
	mask, color uintptr
}

func ownedIconAlive(h uintptr) bool {
	var i ownedIconInfo
	if uiCall("GetIconInfo", h, uintptr(unsafe.Pointer(&i))) == 0 {
		return false
	}
	if i.mask != 0 {
		trayG.NewProc("DeleteObject").Call(i.mask)
	}
	if i.color != 0 {
		trayG.NewProc("DeleteObject").Call(i.color)
	}
	return true
}
