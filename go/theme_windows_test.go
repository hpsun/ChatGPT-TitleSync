//go:build windows && amd64

package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

type fakeIconStore struct {
	state  iconThemeState
	writes int
	fail   bool
}

func (f *fakeIconStore) Load() (iconThemeState, error) { return f.state, nil }
func (f *fakeIconStore) Save(s iconThemeState) (func() error, error) {
	if f.fail {
		return nil, errors.New("injected icon save failure")
	}
	old := f.state
	f.state = s
	f.writes++
	return func() error { f.state = old; return nil }, nil
}
func themeFixture(t *testing.T) (*iconThemeController, *fakeIconStore, *time.Time, *int) {
	t.Helper()
	now := time.Date(2026, 11, 11, 9, 4, 0, 0, time.FixedZone("own", 8*3600))
	installs := 0
	store := &fakeIconStore{state: defaultIconTheme()}
	c, e := newIconThemeController(store, func(int) error { return nil }, func(int) error { installs++; return nil })
	if e != nil {
		t.Fatal(e)
	}
	c.clock = func() time.Time { return now }
	c.pick = func(int) (int, error) { return 0, nil }
	return c, store, &now, &installs
}
func applyTheme(t *testing.T, c *iconThemeController, p iconPreference) {
	t.Helper()
	tx, e := c.transaction(p)
	if e != nil {
		t.Fatal(e)
	}
	if e = tx.Prepare(); e != nil {
		t.Fatal(e)
	}
	if e = tx.Finish(); e != nil {
		t.Fatal(e)
	}
}
func TestIconSlotsExactLocalBoundaries(t *testing.T) {
	n := time.Date(2026, 11, 11, 9, 59, 0, 0, time.FixedZone("own", 8*3600))
	if iconSlot("day", n) != "20261111" || iconSlot("hour", n) != "2026111109+0800" || iconSlot("5min", n) != "202611110911+0800" {
		t.Fatal("exact shared slot format")
	}
	if iconSlot("5min", n.Add(time.Minute)) != "202611111000+0800" {
		t.Fatal("5min boundary")
	}
	if iconSlot("day", time.Date(2026, 11, 11, 23, 59, 0, 0, n.Location()).Add(time.Minute)) != "20261112" {
		t.Fatal("day boundary")
	}
	a := time.Date(2026, 11, 1, 1, 0, 0, 0, time.FixedZone("before", -4*3600))
	b := time.Date(2026, 11, 1, 1, 0, 0, 0, time.FixedZone("after", -5*3600))
	if iconSlot("hour", a) == iconSlot("hour", b) {
		t.Fatal("DST repeated hour must differ")
	}
}
func TestIconRandomAllEightAndNoAdjacentRepeat(t *testing.T) {
	c, _, _, _ := themeFixture(t)
	seen := map[int]bool{}
	for n := 0; n < 7; n++ {
		c.state = defaultIconTheme()
		c.pick = func(int) (int, error) { return n, nil }
		s, e := c.draft(iconPreference{"random", 45, "day"}, true)
		if e != nil || s.Random == 45 {
			t.Fatal("adjacent repeat", s, e)
		}
		seen[s.Random] = true
	}
	c.state.Fixed = 52
	c.pick = func(int) (int, error) { return 0, nil }
	s, e := c.draft(iconPreference{"random", 52, "day"}, true)
	if e != nil {
		t.Fatal(e)
	}
	seen[s.Random] = true
	if len(seen) != 8 {
		t.Fatal("all palettes not reachable", seen)
	}
}
func TestIconSameSlotRestartDoesNotPickOrWrite(t *testing.T) {
	c, store, now, _ := themeFixture(t)
	applyTheme(t, c, iconPreference{"random", 45, "day"})
	writes := store.writes
	second, e := newIconThemeController(store, func(int) error { return nil }, func(int) error { t.Fatal("same slot reinstalled"); return nil })
	if e != nil {
		t.Fatal(e)
	}
	second.clock = func() time.Time { return *now }
	second.pick = func(int) (int, error) { t.Fatal("same slot repicked"); return 0, nil }
	if e = second.tick(); e != nil || store.writes != writes || second.snapshot().Random != c.snapshot().Random {
		t.Fatal("same slot changed", e)
	}
}
func TestIconRotationPeriodChangesAndFixedNoOp(t *testing.T) {
	c, store, now, installs := themeFixture(t)
	if e := c.tick(); e != nil || store.writes != 0 {
		t.Fatal("fixed mode rotation")
	}
	applyTheme(t, c, iconPreference{"random", 45, "5min"})
	first := c.snapshot().Random
	*now = now.Add(time.Minute)
	if e := c.tick(); e != nil {
		t.Fatal(e)
	}
	if c.snapshot().Random == first || *installs != 2 {
		t.Fatal("5min boundary did not choose exactly once")
	}
	before := c.snapshot().Random
	applyTheme(t, c, iconPreference{"random", 45, "hour"})
	if c.snapshot().Random == before {
		t.Fatal("period change did not choose immediately")
	}
	count := store.writes
	if e := c.tick(); e != nil || store.writes != count {
		t.Fatal("repeated slot wrote")
	}
}
func TestIconMissingAssetRetainsStateAndLogsOncePerSlot(t *testing.T) {
	c, store, now, installs := themeFixture(t)
	applyTheme(t, c, iconPreference{"random", 45, "hour"})
	old := c.snapshot()
	writes := store.writes
	count := *installs
	*now = now.Add(time.Hour)
	calls := 0
	c.validate = func(int) error { calls++; return errors.New("missing owned fixture asset") }
	if c.tick() == nil || c.tick() != nil || calls != 1 || c.snapshot() != old || store.writes != writes || *installs != count {
		t.Fatal("missing asset changed state or repeated attempt")
	}
}

type iconStartupFixture struct{ on bool }

func (s *iconStartupFixture) Apply(on bool) (func() error, error) {
	old := s.on
	s.on = on
	return func() error { s.on = old; return nil }, nil
}
func TestIconSaveFailureRollsBackThemeTimingStartup(t *testing.T) {
	c, store, _, _ := themeFixture(t)
	c.install = func(int) error { return errors.New("injected Shell icon failure") }
	path := filepath.Join(t.TempDir(), "settings.json")
	old := scanSettings{2, 5, true, true, 0}
	if e := writeSettings(path, old); e != nil {
		t.Fatal(e)
	}
	bytes, _ := os.ReadFile(path)
	start := &iconStartupFixture{on: true}
	live := &liveSettings{value: old, path: path, startup: start}
	draft := old
	draft.ForegroundSeconds = 3
	draft.BackgroundSeconds = 10
	draft.AutoStartEnabled = false
	tx, e := c.transaction(iconPreference{"random", 45, "day"})
	if e != nil {
		t.Fatal(e)
	}
	if e = live.saveExtra(draft, tx); e == nil {
		t.Fatal("failed icon application reported success")
	}
	after, _ := os.ReadFile(path)
	if string(after) != string(bytes) || live.snapshot() != old || !start.on || store.state != defaultIconTheme() || c.snapshot() != defaultIconTheme() {
		t.Fatal("combined rollback failed")
	}
}
func TestIconPrivateRegistryFiveValuesRollbackAndAutostartUntouched(t *testing.T) {
	w, cleanup := ownedStartup(t)
	defer cleanup()
	_, e := w.Apply(true)
	if e != nil {
		t.Fatal(e)
	}
	pref, _ := w.registry.Read(w.pref, startupPreferenceName)
	r := registryIconThemeStore{w.registry, w.pref}
	s, e := r.Load()
	if e != nil || s != defaultIconTheme() {
		t.Fatal("missing defaults", e)
	}
	s.Mode = "random"
	s.Random = 52
	s.Slot = "20261111"
	undo, e := r.Save(s)
	if e != nil {
		t.Fatal(e)
	}
	loaded, e := r.Load()
	if e != nil || loaded != s {
		t.Fatal("round trip", e)
	}
	if e = undo(); e != nil {
		t.Fatal(e)
	}
	again, _ := r.Load()
	a, _ := w.registry.Read(w.pref, startupPreferenceName)
	if again != defaultIconTheme() || !reflect.DeepEqual(a, pref) {
		t.Fatal("rollback touched autostart")
	}
	r.registry = &failOnceRegistry{base: w.registry, fail: 3}
	if _, e = r.Save(s); e == nil {
		t.Fatal("injected registry failure accepted")
	}
	r.registry = w.registry
	again, _ = r.Load()
	if again != defaultIconTheme() {
		t.Fatal("partial registry transaction survived")
	}
	if e = w.registry.Write(w.pref, "FixedIcon", iconNumber(44)); e != nil {
		t.Fatal(e)
	}
	fallback, err := newIconThemeController(r, func(int) error { return nil }, func(int) error { return nil })
	if err == nil || fallback.snapshot() != defaultIconTheme() {
		t.Fatal("invalid stored preference did not provide display-only fallback")
	}
	raw, _ := w.registry.Read(w.pref, "FixedIcon")
	if id, _ := decodeIconNumber(raw); id != 44 {
		t.Fatal("invalid stored preference silently rewritten")
	}
}
func TestIconInvalidPreferenceOrUnavailableRandomAssetNeverPersists(t *testing.T) {
	c, store, _, _ := themeFixture(t)
	for _, p := range []iconPreference{{"other", 45, "day"}, {"fixed", 44, "day"}, {"random", 45, "minute"}} {
		if _, e := c.transaction(p); e == nil {
			t.Fatal("invalid theme accepted")
		}
	}
	c.validate = func(id int) error {
		if id == 52 {
			return errors.New("missing random palette")
		}
		return nil
	}
	if _, e := c.transaction(iconPreference{"random", 45, "day"}); e == nil || store.writes != 0 {
		t.Fatal("unavailable random set committed")
	}
}
func TestIconSystemRandomRangeWithoutPreferences(t *testing.T) {
	store := &fakeIconStore{state: defaultIconTheme()}
	c, e := newIconThemeController(store, func(int) error { return nil }, func(int) error { return nil })
	if e != nil {
		t.Fatal(e)
	}
	for i := 0; i < 16; i++ {
		n, e := c.pick(7)
		if e != nil || n < 0 || n >= 7 {
			t.Fatal("system random range", n, e)
		}
	}
	if store.writes != 0 {
		t.Fatal("random source test wrote preference")
	}
}
