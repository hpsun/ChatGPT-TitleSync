//go:build windows && amd64

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"testing"
	"time"
	"unsafe"
)

type failOnceRegistry struct {
	base    startupRegistry
	n, fail int
}

func (f *failOnceRegistry) Read(p, n string) (registryValue, error) { return f.base.Read(p, n) }
func (f *failOnceRegistry) Write(p, n string, v registryValue) error {
	f.n++
	if f.n == f.fail {
		return fmt.Errorf("injected registry write failure")
	}
	return f.base.Write(p, n, v)
}
func ownedStartup(t *testing.T) (*windowsStartup, func()) {
	t.Helper()
	base := fmt.Sprintf(`Software\ChatGPT-TitleSync-Tests\go-%d-%d`, os.Getpid(), time.Now().UnixNano())
	exe, e := os.Executable()
	if e != nil {
		t.Fatal(e)
	}
	w := &windowsStartup{nativeStartupRegistry{}, base + `\Run`, base + `\Preference`, exe}
	cleanup := func() {
		if !strings.HasPrefix(base, `Software\ChatGPT-TitleSync-Tests\`) {
			t.Error("unsafe owned test key")
			return
		}
		startupDLL.NewProc("RegDeleteTreeW").Call(currentUserKey, uintptr(unsafe.Pointer(ptr(base))))
	}
	return w, cleanup
}
func TestAutoStartOwnedRegistryTransaction(t *testing.T) {
	w, cleanup := ownedStartup(t)
	defer cleanup()
	v, e := w.Load()
	if e != nil || !v {
		t.Fatal("missing preference must default on", e)
	}
	undo, e := w.Apply(true)
	if e != nil {
		t.Fatal(e)
	}
	run, e := w.registry.Read(w.run, startupRunName)
	if e != nil || !run.exists || run.kind != 1 {
		t.Fatal("owned Run missing", e)
	}
	want := `"` + w.exe + `"`
	var units []uint16
	for i := 0; i+1 < len(run.data); i += 2 {
		units = append(units, uint16(run.data[i])|uint16(run.data[i+1])<<8)
	}
	if len(units) < 3 || units[0] != 34 || units[len(units)-2] != 34 {
		t.Fatal("Run entry must use actual quote characters")
	}
	if got := stringFromUnits(units); got != want {
		t.Fatal("Run must contain only quoted absolute EXE", got)
	}
	counter := &failOnceRegistry{base: w.registry}
	same := &windowsStartup{counter, w.run, w.pref, w.exe}
	sameUndo, e := same.Apply(true)
	if e != nil {
		t.Fatal(e)
	}
	if e = sameUndo(); e != nil || counter.n != 0 {
		t.Fatal("unchanged startup state wrote registry", e, counter.n)
	}
	if e = undo(); e != nil {
		t.Fatal(e)
	}
	if run, _ = w.registry.Read(w.run, startupRunName); run.exists {
		t.Fatal("undo did not restore missing Run")
	}
	if _, e = w.Apply(false); e != nil {
		t.Fatal(e)
	}
	if on, e := w.Load(); e != nil || on {
		t.Fatal("explicit shared off lost", e)
	}
	// A second controller represents another language using the same preference contract.
	other := &windowsStartup{w.registry, w.run, w.pref, w.exe}
	if on, e := other.Load(); e != nil || on {
		t.Fatal("off not inherited", e)
	}
}
func stringFromUnits(u []uint16) string { return syscall.UTF16ToString(u) }
func TestAutoStartFailureAndDiskFailureRollback(t *testing.T) {
	w, cleanup := ownedStartup(t)
	defer cleanup()
	if _, e := w.Apply(true); e != nil {
		t.Fatal(e)
	}
	beforeRun, _ := w.registry.Read(w.run, startupRunName)
	beforePref, _ := w.registry.Read(w.pref, startupPreferenceName)
	broken := &windowsStartup{&failOnceRegistry{base: w.registry, fail: 2}, w.run, w.pref, w.exe}
	if _, e := broken.Apply(false); e == nil {
		t.Fatal("write failure not reported")
	}
	a, _ := w.registry.Read(w.run, startupRunName)
	b, _ := w.registry.Read(w.pref, startupPreferenceName)
	if !reflect.DeepEqual(a, beforeRun) || !reflect.DeepEqual(b, beforePref) {
		t.Fatal("registry transaction did not roll back")
	}
	dir := t.TempDir()
	block := filepath.Join(dir, "file")
	os.WriteFile(block, []byte("file"), 0600)
	initial := scanSettings{2, 5, true, true, 0}
	s := &liveSettings{value: initial, path: filepath.Join(block, "settings.json"), startup: w}
	off := initial
	off.AutoStartEnabled = false
	if e := s.save(off); e == nil {
		t.Fatal("disk save failure not reported")
	}
	a, _ = w.registry.Read(w.run, startupRunName)
	b, _ = w.registry.Read(w.pref, startupPreferenceName)
	if s.snapshot() != initial || !reflect.DeepEqual(a, beforeRun) || !reflect.DeepEqual(b, beforePref) {
		t.Fatal("file failure published or retained wrong autostart")
	}
}

func TestAutoStartLongCommandRejectedButOffWorks(t *testing.T) {
	w, cleanup := ownedStartup(t)
	defer cleanup()
	w.exe = `C:\` + strings.Repeat("a", 260) + ".exe"
	if _, e := w.Apply(true); e == nil {
		t.Fatal("long startup command accepted")
	}
	a, _ := w.registry.Read(w.run, startupRunName)
	b, _ := w.registry.Read(w.pref, startupPreferenceName)
	if a.exists || b.exists {
		t.Fatal("long command rejection mutated registry")
	}
	w.exe = `C:\` + strings.Repeat("a", 255)
	if _, e := w.Apply(true); e != nil {
		t.Fatal("exactly 260 UTF-16 command characters rejected", e)
	}
	oldRun, _ := w.registry.Read(w.run, startupRunName)
	oldPref, _ := w.registry.Read(w.pref, startupPreferenceName)
	w.exe = `C:\` + strings.Repeat("a", 260) + ".exe"
	if _, e := w.Apply(true); e == nil {
		t.Fatal("long command accepted after existing valid registration")
	}
	a, _ = w.registry.Read(w.run, startupRunName)
	b, _ = w.registry.Read(w.pref, startupPreferenceName)
	if !reflect.DeepEqual(a, oldRun) || !reflect.DeepEqual(b, oldPref) {
		t.Fatal("length rejection overwrote existing registration")
	}
	if _, e := w.Apply(false); e != nil {
		t.Fatal("off incorrectly rejected long EXE", e)
	}
	if on, e := w.Load(); e != nil || on {
		t.Fatal("long-path off not persisted", e)
	}
}
