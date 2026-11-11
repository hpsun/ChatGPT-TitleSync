//go:build windows && amd64

package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

var k32 = syscall.NewLazyDLL("kernel32.dll")
var u32 = syscall.NewLazyDLL("user32.dll")
var ole = syscall.NewLazyDLL("ole32.dll")
var oa = syscall.NewLazyDLL("oleaut32.dll")
var openProcess = k32.NewProc("OpenProcess")
var closeHandle = k32.NewProc("CloseHandle")
var processTimes = k32.NewProc("GetProcessTimes")
var processPath = k32.NewProc("QueryFullProcessImageNameW")
var getWindowPID = u32.NewProc("GetWindowThreadProcessId")
var getClass = u32.NewProc("GetClassNameW")
var getText = u32.NewProc("GetWindowTextW")
var isWindow = u32.NewProc("IsWindow")
var ancestor = u32.NewProc("GetAncestor")
var sendText = u32.NewProc("SendMessageTimeoutW")

func ptr(s string) *uint16 { p, _ := syscall.UTF16PtrFromString(s); return p }
func processIdentity(pid uint32) (uint64, string, error) {
	h, _, _ := openProcess.Call(0x1000, 0, uintptr(pid))
	if h == 0 {
		return 0, "", errors.New("process-access")
	}
	defer closeHandle.Call(h)
	var times [4]uint64
	r, _, _ := processTimes.Call(h, uintptr(unsafe.Pointer(&times[0])), uintptr(unsafe.Pointer(&times[1])), uintptr(unsafe.Pointer(&times[2])), uintptr(unsafe.Pointer(&times[3])))
	if r == 0 {
		return 0, "", errors.New("process-time")
	}
	buf := make([]uint16, 32768)
	size := uint32(len(buf))
	r, _, _ = processPath.Call(h, 0, uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)))
	if r == 0 {
		return 0, "", errors.New("process-path")
	}
	return times[0], syscall.UTF16ToString(buf[:size]), nil
}
func capture(h uint64) (Window, error) {
	r, _, _ := isWindow.Call(uintptr(h))
	if r == 0 {
		return Window{}, errors.New("window-gone")
	}
	a, _, _ := ancestor.Call(uintptr(h), 2)
	if a != uintptr(h) {
		return Window{}, errors.New("not-top-level")
	}
	var pid uint32
	getWindowPID.Call(uintptr(h), uintptr(unsafe.Pointer(&pid)))
	start, exe, e := processIdentity(pid)
	if e != nil {
		return Window{}, e
	}
	buf := make([]uint16, 256)
	n, _, _ := getClass.Call(uintptr(h), uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if n == 0 {
		return Window{}, errors.New("window-class")
	}
	return Window{h, pid, start, syscall.UTF16ToString(buf), exe}, nil
}
func nativeSame(w Window) bool {
	current, e := capture(w.Handle)
	return e == nil && current.Key() == w.Key()
}

func nativeList() ([]Window, error) {
	h, _, _ := u32.NewProc("GetForegroundWindow").Call()
	if h == 0 {
		return nil, nil
	}
	w, e := capture(uint64(h))
	if e != nil || w.Class != "Chrome_WidgetWin_1" || !strings.EqualFold(filepath.Base(w.Exe), "ChatGPT.exe") {
		return nil, nil
	}
	return []Window{w}, nil
}
func nativeActive(w Window) bool {
	h, _, _ := u32.NewProc("GetForegroundWindow").Call()
	return uint64(h) == w.Handle && nativeSame(w)
}
func nativeSetActive(w Window, a, b string) error {
	if !nativeActive(w) {
		return errors.New("focus-changed")
	}
	if e := nativeSet(w, a, b); e != nil {
		return e
	}
	if !nativeActive(w) {
		_ = nativeSet(w, b, a)
		return errors.New("focus-changed-after-write")
	}
	return nil
}
func nativeCaption(w Window) (string, error) {
	if !nativeSame(w) {
		return "", errors.New("identity-changed")
	}
	buf := make([]uint16, 2048)
	getText.Call(uintptr(w.Handle), uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if !nativeSame(w) {
		return "", errors.New("identity-changed")
	}
	return syscall.UTF16ToString(buf), nil
}
func nativeSet(w Window, expected, new string) error {
	if !nativeSame(w) {
		return errors.New("identity-changed")
	}
	old, e := nativeCaption(w)
	if e != nil || old != expected {
		return errors.New("caption-changed")
	}
	var result uintptr
	sendText.Call(uintptr(w.Handle), 0xC, 0, uintptr(unsafe.Pointer(ptr(new))), 0x23, 300, uintptr(unsafe.Pointer(&result)))
	current, e := nativeCaption(w)
	if e != nil || current != new {
		return errors.New("write-not-confirmed")
	}
	return nil
}
func hideChild(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
}
func isolatedName(ctx context.Context, w Window) (string, error) { return childName(ctx, w) }

type guid struct {
	A    uint32
	B, C uint16
	D    [8]byte
}
type variant struct {
	VT, R1, R2, R3 uint16
	Data           [2]uintptr
}

func vcall(obj uintptr, index int, args ...uintptr) (uintptr, uintptr, syscall.Errno) {
	vt := *(*uintptr)(unsafe.Pointer(obj))
	fn := *(*uintptr)(unsafe.Pointer(vt + uintptr(index)*unsafe.Sizeof(uintptr(0))))
	return syscall.SyscallN(fn, append([]uintptr{obj}, args...)...)
}
func release(obj uintptr) {
	if obj != 0 {
		vcall(obj, 2)
	}
}
func failed(hr uintptr) bool                  { return int32(uint32(hr)) < 0 }
func nativeReadName(w Window) (string, error) { return nativeReadNameMode(w, true) }
func nativeReadNameMode(w Window, foreground bool) (string, error) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if !nativeSame(w) {
		return "", errors.New("identity-changed")
	}
	hr, _, _ := ole.NewProc("CoInitializeEx").Call(0, 0)
	if failed(hr) {
		return "", errors.New("com-init")
	}
	defer ole.NewProc("CoUninitialize").Call()
	cls := guid{0xFF48DBA4, 0x60EF, 0x4201, [8]byte{0xAA, 0x87, 0x54, 0x10, 0x3E, 0xEF, 0x59, 0x4E}}
	iid := guid{0x30CBE57D, 0xD9D0, 0x452A, [8]byte{0xAB, 0x13, 0x7A, 0xC5, 0xAC, 0x48, 0x25, 0xEE}}
	var automation, root, docCondition, visibleCondition, condition, document uintptr
	hr, _, _ = ole.NewProc("CoCreateInstance").Call(uintptr(unsafe.Pointer(&cls)), 0, 1, uintptr(unsafe.Pointer(&iid)), uintptr(unsafe.Pointer(&automation)))
	if failed(hr) || automation == 0 {
		return "", errors.New("uia-create")
	}
	defer release(automation)
	if nativeActive(w) != foreground {
		return "", errors.New("focus-changed")
	}
	hr, _, _ = vcall(automation, 6, uintptr(w.Handle), uintptr(unsafe.Pointer(&root)))
	if failed(hr) || root == 0 {
		return "", errors.New("uia-window")
	}
	defer release(root)
	value := variant{VT: 3}
	value.Data[0] = 50030
	hr, _, _ = vcall(automation, 23, 30003, uintptr(unsafe.Pointer(&value)), uintptr(unsafe.Pointer(&docCondition)))
	if failed(hr) || docCondition == 0 {
		return "", errors.New("uia-condition")
	}
	defer release(docCondition)
	visible := variant{VT: 11}
	hr, _, _ = vcall(automation, 23, 30022, uintptr(unsafe.Pointer(&visible)), uintptr(unsafe.Pointer(&visibleCondition)))
	if failed(hr) || visibleCondition == 0 {
		return "", errors.New("uia-visible-condition")
	}
	defer release(visibleCondition)
	hr, _, _ = vcall(automation, 25, docCondition, visibleCondition, uintptr(unsafe.Pointer(&condition)))
	if failed(hr) || condition == 0 {
		return "", errors.New("uia-and-condition")
	}
	defer release(condition)
	// FindFirst is scoped to THIS HWND subtree, never the desktop or another window.
	if nativeActive(w) != foreground {
		return "", errors.New("focus-changed")
	}
	searchCondition := condition
	if !foreground {
		searchCondition = docCondition
	}
	hr, _, _ = vcall(root, 5, 4, searchCondition, uintptr(unsafe.Pointer(&document)))
	if failed(hr) || document == 0 {
		return "", errors.New("root-web-area-unavailable")
	}
	defer release(document)
	identityValue := variant{}
	hr, _, _ = vcall(document, 10, 30011, uintptr(unsafe.Pointer(&identityValue)))
	defer oa.NewProc("VariantClear").Call(uintptr(unsafe.Pointer(&identityValue)))
	if failed(hr) || identityValue.VT != 8 || identityValue.Data[0] == 0 {
		return "", errors.New("root-document-role")
	}
	identityLength, _, _ := oa.NewProc("SysStringLen").Call(identityValue.Data[0])
	if identityLength > 256 || string(utf16Decode(unsafe.Slice((*uint16)(unsafe.Pointer(identityValue.Data[0])), int(identityLength)))) != "RootWebArea" {
		return "", errors.New("root-document-role")
	}
	name := variant{}
	if nativeActive(w) != foreground {
		return "", errors.New("focus-changed")
	}
	hr, _, _ = vcall(document, 10, 30005, uintptr(unsafe.Pointer(&name)))
	defer oa.NewProc("VariantClear").Call(uintptr(unsafe.Pointer(&name)))
	if failed(hr) || name.VT != 8 || name.Data[0] == 0 {
		return "", errors.New("root-name-unavailable")
	}
	length, _, _ := oa.NewProc("SysStringLen").Call(name.Data[0])
	if length > 4096 {
		return "", errors.New("root-name-too-long")
	}
	title := string(utf16Decode(unsafe.Slice((*uint16)(unsafe.Pointer(name.Data[0])), int(length))))
	if !nativeSame(w) {
		return "", errors.New("identity-changed")
	}
	return title, nil
}
func utf16Decode(v []uint16) []rune {
	out := []rune{}
	for i := 0; i < len(v); i++ {
		r := rune(v[i])
		if r >= 0xD800 && r <= 0xDBFF && i+1 < len(v) && v[i+1] >= 0xDC00 && v[i+1] <= 0xDFFF {
			r = 0x10000 + (r-0xD800)*0x400 + rune(v[i+1]) - 0xDC00
			i++
		}
		out = append(out, r)
	}
	return out
}
func nativeSelfTest() error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	h, _, _ := u32.NewProc("CreateWindowExW").Call(0, uintptr(unsafe.Pointer(ptr("STATIC"))), uintptr(unsafe.Pointer(ptr("OWN_GO_ORIGINAL"))), 0x00CF0000, ^uintptr(29999), ^uintptr(29999), 120, 80, 0, 0, 0, 0)
	if h == 0 {
		return errors.New("own-window-create")
	}
	defer u32.NewProc("DestroyWindow").Call(h)
	w, e := capture(uint64(h))
	if e != nil || w.PID != uint32(os.Getpid()) {
		return errors.New("own-identity")
	}
	if e = nativeSet(w, "OWN_GO_ORIGINAL", "OWN_GO_MANAGED"); e != nil {
		return e
	}
	bad := w
	bad.Start--
	if nativeSame(bad) || nativeSet(bad, "OWN_GO_MANAGED", "FORBIDDEN") == nil {
		return errors.New("stale-lease-accepted")
	}
	if e = nativeSet(w, "OWN_GO_MANAGED", "OWN_GO_ORIGINAL"); e != nil {
		return e
	}
	fmt.Println("owned HWND identity, guarded native write and restore passed")
	return nil
}

var sharedMutex uintptr
var sharedStop atomic.Uintptr

func nativeAcquire() (func(), error) {
	// Compatibility: do not rename the shared historical mutex/event; old and new products must remain mutually exclusive.
	h, _, _ := k32.NewProc("CreateMutexW").Call(0, 0, uintptr(unsafe.Pointer(ptr("Local\\TdxChatGptTitleStandalone"))))
	if h == 0 {
		return nil, errors.New("shared-mutex-create")
	}
	wait, _, _ := k32.NewProc("WaitForSingleObject").Call(h, 0)
	if wait != 0 && wait != 0x80 {
		closeHandle.Call(h)
		return nil, errors.New("already-running-shared")
	}
	sharedMutex = h
	// Compatibility: preserve the cross-version stop event alongside the legacy mutex.
	ev, _, _ := k32.NewProc("CreateEventW").Call(0, 1, 0, uintptr(unsafe.Pointer(ptr("Local\\TdxChatGptTitleStandalone.Stop"))))
	if ev == 0 {
		k32.NewProc("ReleaseMutex").Call(h)
		closeHandle.Call(h)
		return nil, errors.New("shared-stop-create")
	}
	sharedStop.Store(ev)
	k32.NewProc("ResetEvent").Call(ev)
	return func() {
		sharedStop.Store(0)
		closeHandle.Call(ev)
		k32.NewProc("ReleaseMutex").Call(h)
		closeHandle.Call(h)
		sharedMutex = 0
	}, nil
}

// Compatibility: cooperative stop uses the same historical cross-language event.
func nativeRequestStop() error {
	h, _, _ := k32.NewProc("OpenEventW").Call(2, 0, uintptr(unsafe.Pointer(ptr("Local\\TdxChatGptTitleStandalone.Stop"))))
	if h == 0 {
		return errors.New("no-standalone-running")
	}
	defer closeHandle.Call(h)
	r, _, _ := k32.NewProc("SetEvent").Call(h)
	if r == 0 {
		return errors.New("stop-request-failed")
	}
	return nil
}
func nativeStopRequested() bool {
	h := sharedStop.Load()
	if h == 0 {
		return false
	}
	r, _, _ := k32.NewProc("WaitForSingleObject").Call(h, 0)
	return r == 0
}

var allEnumMu sync.Mutex
var allEnumOut *[]Window
var allEnumThunk = syscall.NewCallback(func(h, state uintptr) uintptr {
	if allEnumOut == nil {
		return 0
	}
	visible, _, _ := u32.NewProc("IsWindowVisible").Call(h)
	if visible == 0 {
		return 1
	}
	w, e := capture(uint64(h))
	if e == nil && w.Class == "Chrome_WidgetWin_1" && strings.EqualFold(filepath.Base(w.Exe), "ChatGPT.exe") {
		*allEnumOut = append(*allEnumOut, w)
	}
	return 1
})

func nativeListAll() ([]Window, error) {
	allEnumMu.Lock()
	defer allEnumMu.Unlock()
	out := []Window{}
	allEnumOut = &out
	defer func() { allEnumOut = nil }()
	if r, _, _ := u32.NewProc("EnumWindows").Call(allEnumThunk, 0); r == 0 {
		return nil, errors.New("native-discovery-failed")
	}
	return out, nil
}
func nativeReadSource(ctx context.Context, w Window, foreground bool) (string, error) {
	bounded, cancel := context.WithCancel(ctx)
	defer cancel()
	go func() {
		t := time.NewTicker(40 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-bounded.Done():
				return
			case <-t.C:
				if !nativeSame(w) || nativeActive(w) != foreground {
					cancel()
					return
				}
			}
		}
	}()
	return childNameMode(bounded, w, foreground)
}

func nativeSetInactive(w Window, a, b string) error {
	if nativeActive(w) {
		return errors.New("foreground")
	}
	if e := nativeSet(w, a, b); e != nil {
		return e
	}
	if nativeActive(w) {
		_ = nativeSet(w, b, a)
		return errors.New("focus-changed")
	}
	return nil
}

func backgroundChild(c *exec.Cmd) {
	if c.SysProcAttr != nil {
		c.SysProcAttr.CreationFlags |= 0x00004000
	}
}
