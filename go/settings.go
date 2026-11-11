package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

const defaultForegroundSeconds = 2
const defaultBackgroundSeconds = 5

// Disk commit precedes publication to the live controller.
type scanSettings struct {
	ForegroundSeconds int    `json:"foreground_seconds"`
	BackgroundSeconds int    `json:"background_seconds"`
	Enabled           bool   `json:"enabled"`
	AutoStartEnabled  bool   `json:"autostart_enabled"`
	Revision          uint64 `json:"-"`
}
type liveSettings struct {
	mu       sync.RWMutex
	commitMu sync.Mutex
	value    scanSettings
	path     string
	startup  startupPreference
}

func validSettings(s scanSettings) error {
	if s.ForegroundSeconds < 1 || s.ForegroundSeconds > 3600 || s.BackgroundSeconds < 5 || s.BackgroundSeconds > 3600 {
		return errors.New("前台间隔需为1–3600秒，后台间隔需为5–3600秒")
	}
	return nil
}
func loadSettings(path string, fallback scanSettings) scanSettings {
	b, e := os.ReadFile(path)
	if e != nil || len(b) > 4096 {
		return fallback
	}
	s := fallback
	s.AutoStartEnabled = true // An old settings file without this field defaults to autostart on.
	if json.Unmarshal(b, &s) != nil || validSettings(s) != nil {
		return fallback
	}
	return s
}
func (s *liveSettings) snapshot() scanSettings { s.mu.RLock(); defer s.mu.RUnlock(); return s.value }

// A system-registration transaction is published only after the file commit succeeds.
type startupPreference interface {
	Apply(bool) (func() error, error)
}

// Optional settings additions join the same rollback boundary as autostart and timing.
type settingsExtra interface {
	Prepare() error
	Finish() error
	Rollback() error
}

func (s *liveSettings) save(v scanSettings) error { return s.saveExtra(v, nil) }
func (s *liveSettings) saveExtra(v scanSettings, extra settingsExtra) error {
	if e := validSettings(v); e != nil {
		return e
	}
	s.commitMu.Lock()
	defer s.commitMu.Unlock()
	old := s.snapshot()
	var undo func() error
	if s.startup != nil && v.AutoStartEnabled != old.AutoStartEnabled {
		var e error
		undo, e = s.startup.Apply(v.AutoStartEnabled)
		if e != nil {
			return e
		}
	}
	var previous []byte
	existed := false
	if extra != nil {
		var e error
		previous, e = os.ReadFile(s.path)
		existed = e == nil
		if e != nil && !os.IsNotExist(e) {
			if undo != nil {
				return errors.Join(e, undo())
			}
			return e
		}
	}
	rollback := func(cause error, restoreFile bool) error {
		if extra != nil {
			cause = errors.Join(cause, extra.Rollback())
		}
		if restoreFile {
			if existed {
				cause = errors.Join(cause, writeSettingsData(s.path, previous))
			} else {
				if e := os.Remove(s.path); e != nil && !os.IsNotExist(e) {
					cause = errors.Join(cause, e)
				}
			}
		}
		if undo != nil {
			cause = errors.Join(cause, undo())
		}
		return cause
	}
	if extra != nil {
		if e := extra.Prepare(); e != nil {
			return rollback(e, false)
		}
	}
	if e := writeSettings(s.path, v); e != nil {
		return rollback(e, false)
	}
	if extra != nil {
		if e := extra.Finish(); e != nil {
			return rollback(e, true)
		}
	}

	s.mu.Lock()
	v.Revision = s.value.Revision + 1
	s.value = v
	s.mu.Unlock()
	return nil
}
func writeSettings(path string, v scanSettings) error {
	b, e := json.MarshalIndent(v, "", "  ")
	if e != nil {
		return e
	}
	return writeSettingsData(path, b)
}
func writeSettingsData(path string, b []byte) error {
	var e error
	if e = os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(path), "settings-*.tmp")
	if e != nil {
		return e
	}
	p := f.Name()
	defer os.Remove(p)
	if _, e = f.Write(b); e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e == nil {
		e = ce
	}
	if e != nil {
		return e
	}
	return os.Rename(p, path)
}
