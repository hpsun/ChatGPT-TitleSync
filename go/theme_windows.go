//go:build windows && amd64

package main

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"math/big"
	"strconv"
	"sync"
	"syscall"
	"time"
)

// Themes live only in the shared preference key, never in the timing settings file.
type iconPreference struct {
	Mode   string
	Fixed  int
	Period string
}
type iconThemeState struct {
	iconPreference
	Random int
	Slot   string
}

func defaultIconTheme() iconThemeState {
	return iconThemeState{iconPreference{"fixed", 45, "day"}, 45, ""}
}
func validIconPreference(p iconPreference) error {
	if p.Mode != "fixed" && p.Mode != "random" {
		return errors.New("图标模式必须为固定或随机")
	}
	if p.Fixed < 45 || p.Fixed > 52 {
		return errors.New("图标配色必须为45–52")
	}
	if p.Period != "day" && p.Period != "hour" && p.Period != "5min" {
		return errors.New("随机周期必须为每日、每小时或每5分钟")
	}
	return nil
}
func iconSlot(period string, now time.Time) string {
	switch period {
	case "day":
		return now.Format("20060102")
	case "hour":
		return now.Format("2006010215-0700")
	case "5min":
		return now.Format("2006010215") + fmt.Sprintf("%02d", now.Minute()/5) + now.Format("-0700")
	}
	return ""
}
func (s iconThemeState) id() int {
	if s.Mode == "random" {
		return s.Random
	}
	return s.Fixed
}

type iconThemeStore interface {
	Load() (iconThemeState, error)
	Save(iconThemeState) (func() error, error)
}
type iconThemeController struct {
	mu         sync.Mutex
	state      iconThemeState
	store      iconThemeStore
	clock      func() time.Time
	pick       func(int) (int, error)
	validate   func(int) error
	install    func(int) error
	failedSlot string
}

func newIconThemeController(store iconThemeStore, validate, install func(int) error) (*iconThemeController, error) {
	s, e := store.Load()
	if e != nil {
		s = defaultIconTheme()
	}
	return &iconThemeController{state: s, store: store, clock: time.Now, pick: func(n int) (int, error) {
		v, e := rand.Int(rand.Reader, big.NewInt(int64(n)))
		if e != nil {
			return 0, e
		}
		return int(v.Int64()), nil
	}, validate: validate, install: install}, e
}
func (c *iconThemeController) snapshot() iconThemeState {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.state
}
func (c *iconThemeController) draft(p iconPreference, allAssets bool) (iconThemeState, error) {
	if e := validIconPreference(p); e != nil {
		return iconThemeState{}, e
	}
	old := c.snapshot()
	s := old
	s.iconPreference = p
	// Validate every possible random asset before committing the selected mode.
	if allAssets && p.Mode == "random" {
		for i := 45; i <= 52; i++ {
			if e := c.validate(i); e != nil {
				return s, e
			}
		}
	} else if allAssets {
		if e := c.validate(p.Fixed); e != nil {
			return s, e
		}
	}
	if p.Mode == "random" {
		slot := iconSlot(p.Period, c.clock())
		if old.Mode != "random" || old.Period != p.Period || old.Slot != slot || old.Random < 45 || old.Random > 52 {
			previous := old.id()
			n, e := c.pick(7)
			if e != nil {
				return s, e
			}
			if n < 0 || n >= 7 {
				return s, errors.New("icon random picker out of range")
			}
			next := 45 + n
			if next >= previous {
				next++
			}
			s.Random = next
			s.Slot = slot
		}
	}
	if e := c.validate(s.id()); e != nil {
		return s, e
	}
	return s, nil
}

type iconThemeTransaction struct {
	c     *iconThemeController
	value iconThemeState
	undo  func() error
}

func (c *iconThemeController) transaction(p iconPreference) (*iconThemeTransaction, error) {
	v, e := c.draft(p, true)
	if e != nil {
		return nil, e
	}
	return &iconThemeTransaction{c: c, value: v}, nil
}
func (t *iconThemeTransaction) Prepare() error { u, e := t.c.store.Save(t.value); t.undo = u; return e }
func (t *iconThemeTransaction) Finish() error {
	if e := t.c.install(t.value.id()); e != nil {
		return e
	}
	t.c.mu.Lock()
	t.c.state = t.value
	t.c.failedSlot = ""
	t.c.mu.Unlock()
	return nil
}
func (t *iconThemeTransaction) Rollback() error {
	if t.undo != nil {
		u := t.undo
		t.undo = nil
		return u()
	}
	return nil
}

// A cheap UI timer checks only local time. Failed slots are attempted/logged once.
func (c *iconThemeController) tick() error {
	old := c.snapshot()
	if old.Mode != "random" {
		return nil
	}
	slot := iconSlot(old.Period, c.clock())
	c.mu.Lock()
	skip := old.Slot == slot || c.failedSlot == slot
	c.mu.Unlock()
	if skip {
		return nil
	}
	value, e := c.draft(old.iconPreference, false)
	if e == nil {
		tx := &iconThemeTransaction{c: c, value: value}
		e = tx.Prepare()
		if e == nil {
			e = tx.Finish()
			if e != nil {
				e = errors.Join(e, tx.Rollback())
			}
		}
	}
	if e != nil {
		c.mu.Lock()
		c.failedSlot = slot
		c.mu.Unlock()
	}
	return e
}

type registryIconThemeStore struct {
	registry startupRegistry
	path     string
}

func iconString(s string) registryValue {
	u := syscall.StringToUTF16(s)
	b := make([]byte, len(u)*2)
	for i, n := range u {
		binary.LittleEndian.PutUint16(b[i*2:], n)
	}
	return registryValue{true, 1, b}
}
func iconNumber(n int) registryValue {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, uint32(n))
	return registryValue{true, 4, b}
}
func decodeIconString(v registryValue) (string, error) {
	if v.kind != 1 || len(v.data)%2 != 0 || len(v.data) < 2 || len(v.data) > 256 {
		return "", errors.New("invalid icon string preference")
	}
	u := make([]uint16, len(v.data)/2)
	for i := range u {
		u[i] = binary.LittleEndian.Uint16(v.data[i*2:])
	}
	if u[len(u)-1] != 0 {
		return "", errors.New("unterminated icon preference")
	}
	for _, n := range u[:len(u)-1] {
		if n == 0 {
			return "", errors.New("embedded icon preference terminator")
		}
	}
	return syscall.UTF16ToString(u), nil
}
func decodeIconNumber(v registryValue) (int, error) {
	if v.kind != 4 || len(v.data) != 4 {
		return 0, errors.New("invalid icon numeric preference")
	}
	return int(binary.LittleEndian.Uint32(v.data)), nil
}
func (r registryIconThemeStore) Load() (iconThemeState, error) {
	s := defaultIconTheme()
	for _, name := range []string{"IconMode", "FixedIcon", "IconPeriod", "RandomIcon", "IconSlot"} {
		v, e := r.registry.Read(r.path, name)
		if e != nil {
			return s, e
		}
		if !v.exists {
			continue
		}
		switch name {
		case "IconMode":
			s.Mode, e = decodeIconString(v)
		case "FixedIcon":
			s.Fixed, e = decodeIconNumber(v)
		case "IconPeriod":
			s.Period, e = decodeIconString(v)
		case "RandomIcon":
			s.Random, e = decodeIconNumber(v)
		case "IconSlot":
			s.Slot, e = decodeIconString(v)
		}
		if e != nil {
			return s, e
		}
	}
	if e := validIconPreference(s.iconPreference); e != nil {
		return s, e
	}
	if s.Random < 45 || s.Random > 52 {
		return s, errors.New("invalid persisted random icon")
	}
	return s, nil
}
func (r registryIconThemeStore) Save(s iconThemeState) (func() error, error) {
	names := []string{"IconMode", "FixedIcon", "IconPeriod", "RandomIcon", "IconSlot"}
	values := []registryValue{iconString(s.Mode), iconNumber(s.Fixed), iconString(s.Period), iconNumber(s.Random), iconString(s.Slot)}
	old := make([]registryValue, len(names))
	for i, n := range names {
		v, e := r.registry.Read(r.path, n)
		if e != nil {
			return nil, e
		}
		old[i] = v
	}
	undo := func() error {
		var all error
		for i := len(names) - 1; i >= 0; i-- {
			all = errors.Join(all, r.registry.Write(r.path, names[i], old[i]))
		}
		return all
	}
	for i, n := range names {
		if e := r.registry.Write(r.path, n, values[i]); e != nil {
			return nil, errors.Join(e, undo())
		}
	}
	return undo, nil
}
func iconThemeDescription(s iconThemeState) string {
	return s.Mode + "/" + strconv.Itoa(s.id()) + "/" + s.Period
}
