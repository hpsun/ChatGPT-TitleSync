package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestScanSettingsPersistenceAndValidation(t *testing.T) {
	p := filepath.Join(t.TempDir(), "settings.json")
	a := scanSettings{defaultForegroundSeconds, defaultBackgroundSeconds, true, true, 0}
	s := &liveSettings{value: a, path: p}
	a.ForegroundSeconds = 2
	a.BackgroundSeconds = 5
	if e := s.save(a); e != nil {
		t.Fatal(e)
	}
	a.ForegroundSeconds = 3
	if e := s.save(a); e != nil {
		t.Fatal(e)
	}
	v := loadSettings(p, scanSettings{})
	if v.ForegroundSeconds != 3 || v.BackgroundSeconds != 5 || !v.Enabled {
		t.Fatal(v)
	}
	before := s.snapshot()
	a.BackgroundSeconds = 4
	if s.save(a) == nil || s.snapshot() != before {
		t.Fatal("invalid settings published")
	}
	a = before
	a.Enabled = false
	if e := s.save(a); e != nil {
		t.Fatal(e)
	}
	if loadSettings(p, before).Enabled {
		t.Fatal("toggle not persisted")
	}
	os.WriteFile(p, []byte("broken"), 0600)
	if loadSettings(p, before) != before {
		t.Fatal("invalid fallback")
	}
}
func TestScanSettingsFailedSavePreservesLive(t *testing.T) {
	p := filepath.Join(t.TempDir(), "parent")
	os.WriteFile(p, []byte("file"), 0600)
	a := scanSettings{defaultForegroundSeconds, defaultBackgroundSeconds, true, true, 0}
	s := &liveSettings{value: a, path: filepath.Join(p, "settings.json")}
	b := a
	b.ForegroundSeconds = 2
	if s.save(b) == nil || s.snapshot() != a {
		t.Fatal("failed disk save changed live settings")
	}
}

func TestFreshDefaultsAndExistingSettingsPreserved(t *testing.T) {
	p := filepath.Join(t.TempDir(), "settings.json")
	defaults := scanSettings{defaultForegroundSeconds, defaultBackgroundSeconds, true, true, 0}
	if defaults.ForegroundSeconds != 2 || defaults.BackgroundSeconds != 5 {
		t.Fatal("wrong product defaults")
	}
	if loadSettings(p, defaults) != defaults {
		t.Fatal("fresh defaults")
	}
	v := defaults
	v.ForegroundSeconds = 7
	v.BackgroundSeconds = 17
	s := &liveSettings{value: defaults, path: p}
	if e := s.save(v); e != nil {
		t.Fatal(e)
	}
	got := loadSettings(p, defaults)
	if got.ForegroundSeconds != 7 || got.BackgroundSeconds != 17 {
		t.Fatal("custom settings were overwritten by defaults")
	}
}

func TestLegacyAutostartDefaultAndExplicitOffRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	defaults := scanSettings{2, 5, true, true, 0}
	os.WriteFile(path, []byte(`{"foreground_seconds":7,"background_seconds":17,"enabled":true}`), 0600)
	old := loadSettings(path, defaults)
	if old.ForegroundSeconds != 7 || old.BackgroundSeconds != 17 || !old.AutoStartEnabled {
		t.Fatal("legacy file default/autostart or saved intervals lost")
	}
	s := &liveSettings{value: old, path: path}
	off := old
	off.AutoStartEnabled = false
	if e := s.save(off); e != nil {
		t.Fatal(e)
	}
	loaded := loadSettings(path, defaults)
	if loaded.AutoStartEnabled || loaded.ForegroundSeconds != 7 || loaded.BackgroundSeconds != 17 {
		t.Fatal("explicit off or values did not persist")
	}
}
