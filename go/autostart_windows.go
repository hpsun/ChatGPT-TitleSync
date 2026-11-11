//go:build windows && amd64

package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"
)

const startupRunPath = `Software\Microsoft\Windows\CurrentVersion\Run`
const startupPreferencePath = `Software\ChatGPT-TitleSync`
const startupRunName = "ChatGPT-TitleSync"
const startupPreferenceName = "AutoStartEnabled"

var startupDLL = syscall.NewLazyDLL("advapi32.dll")
var currentUserKey = ^uintptr(0x7ffffffe)

type registryValue struct {
	exists bool
	kind   uint32
	data   []byte
}
type startupRegistry interface {
	Read(string, string) (registryValue, error)
	Write(string, string, registryValue) error
}
type nativeStartupRegistry struct{}

func (nativeStartupRegistry) Read(path, name string) (registryValue, error) {
	var h uintptr
	r, _, _ := startupDLL.NewProc("RegOpenKeyExW").Call(currentUserKey, uintptr(unsafe.Pointer(ptr(path))), 0, 1, uintptr(unsafe.Pointer(&h)))
	if r == 2 {
		return registryValue{}, nil
	}
	if r != 0 {
		return registryValue{}, syscall.Errno(r)
	}
	defer startupDLL.NewProc("RegCloseKey").Call(h)
	var kind, size uint32
	r, _, _ = startupDLL.NewProc("RegQueryValueExW").Call(h, uintptr(unsafe.Pointer(ptr(name))), 0, uintptr(unsafe.Pointer(&kind)), 0, uintptr(unsafe.Pointer(&size)))
	if r == 2 {
		return registryValue{}, nil
	}
	if r != 0 {
		return registryValue{}, syscall.Errno(r)
	}
	if size > 65536 {
		return registryValue{}, errors.New("autostart-registry-value-too-large")
	}
	data := make([]byte, size)
	var p uintptr
	if size > 0 {
		p = uintptr(unsafe.Pointer(&data[0]))
	}
	r, _, _ = startupDLL.NewProc("RegQueryValueExW").Call(h, uintptr(unsafe.Pointer(ptr(name))), 0, uintptr(unsafe.Pointer(&kind)), p, uintptr(unsafe.Pointer(&size)))
	if r != 0 {
		return registryValue{}, syscall.Errno(r)
	}
	return registryValue{true, kind, data[:size]}, nil
}
func (nativeStartupRegistry) Write(path, name string, value registryValue) error {
	var h uintptr
	r, _, _ := startupDLL.NewProc("RegCreateKeyExW").Call(currentUserKey, uintptr(unsafe.Pointer(ptr(path))), 0, 0, 0, 3, 0, uintptr(unsafe.Pointer(&h)), 0)
	if r != 0 {
		return syscall.Errno(r)
	}
	defer startupDLL.NewProc("RegCloseKey").Call(h)
	if !value.exists {
		r, _, _ = startupDLL.NewProc("RegDeleteValueW").Call(h, uintptr(unsafe.Pointer(ptr(name))))
		if r == 2 {
			return nil
		}
	} else {
		var p uintptr
		if len(value.data) > 0 {
			p = uintptr(unsafe.Pointer(&value.data[0]))
		}
		r, _, _ = startupDLL.NewProc("RegSetValueExW").Call(h, uintptr(unsafe.Pointer(ptr(name))), 0, uintptr(value.kind), p, uintptr(len(value.data)))
	}
	runtime.KeepAlive(value.data)
	if r != 0 {
		return syscall.Errno(r)
	}
	return nil
}

type windowsStartup struct {
	registry       startupRegistry
	run, pref, exe string
}

func (w *windowsStartup) Load() (bool, error) {
	v, e := w.registry.Read(w.pref, startupPreferenceName)
	if e != nil {
		return false, e
	}
	if !v.exists {
		return true, nil
	}
	if v.kind != 4 || len(v.data) != 4 {
		return false, errors.New("autostart-preference-must-be-DWORD")
	}
	return binary.LittleEndian.Uint32(v.data) != 0, nil
}
func (w *windowsStartup) Apply(on bool) (func() error, error) {
	command := `"` + w.exe + `"`
	if on && len(syscall.StringToUTF16(command))-1 > 260 {
		return nil, errors.New("开机自启动命令超过 Windows Run 的 260 字符限制")
	}

	oldRun, e := w.registry.Read(w.run, startupRunName)
	if e != nil {
		return nil, e
	}
	oldPref, e := w.registry.Read(w.pref, startupPreferenceName)
	if e != nil {
		return nil, e
	}
	undo := func() error {
		a := w.registry.Write(w.pref, startupPreferenceName, oldPref)
		b := w.registry.Write(w.run, startupRunName, oldRun)
		return errors.Join(a, b)
	}
	pref := make([]byte, 4)
	if on {
		binary.LittleEndian.PutUint32(pref, 1)
	}
	run := registryValue{}
	if on {
		u := syscall.StringToUTF16(command)
		data := make([]byte, len(u)*2)
		for i, c := range u {
			binary.LittleEndian.PutUint16(data[i*2:], c)
		}
		run = registryValue{true, 1, data}
	}
	newPref := registryValue{true, 4, pref}
	same := func(a, b registryValue) bool {
		return a.exists == b.exists && a.kind == b.kind && bytes.Equal(a.data, b.data)
	}
	if same(oldRun, run) && same(oldPref, newPref) {
		return func() error { return nil }, nil
	}
	if e = w.registry.Write(w.run, startupRunName, run); e == nil {
		e = w.registry.Write(w.pref, startupPreferenceName, newPref)
	}
	if e != nil {
		if r := undo(); r != nil {
			return nil, fmt.Errorf("%v; autostart rollback failed: %v", e, r)
		}
		return nil, e
	}
	return undo, nil
}

// Called only after the normal resident acquired its legacy singleton, never by workers or read-only/once/control modes.
func prepareNativeStartup(v scanSettings) (scanSettings, startupPreference, error) {
	exe, e := os.Executable()
	if e != nil {
		return v, nil, e
	}
	exe, e = filepath.Abs(exe)
	if e != nil || !filepath.IsAbs(exe) {
		return v, nil, errors.New("autostart-executable-must-be-absolute")
	}
	w := &windowsStartup{nativeStartupRegistry{}, startupRunPath, startupPreferencePath, exe}
	v.AutoStartEnabled, e = w.Load()
	if e != nil {
		return v, nil, e
	}
	if _, e = w.Apply(v.AutoStartEnabled); e != nil {
		return v, nil, e
	}
	return v, w, nil
}
