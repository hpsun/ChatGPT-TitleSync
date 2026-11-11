package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

type Window struct {
	Handle uint64 `json:"handle"`
	PID    uint32 `json:"pid"`
	Start  uint64 `json:"start"`
	Class  string `json:"class"`
	Exe    string `json:"exe"`
}

func (w Window) Key() string {
	return fmt.Sprintf("%d|%d|%d|%s|%s", w.Handle, w.PID, w.Start, w.Class, strings.ToLower(w.Exe))
}

type Backend interface {
	List() ([]Window, error)
	Same(Window) bool
	Active(Window) bool
	SetActive(Window, string, string) error
	Caption(Window) (string, error)
	Set(Window, string, string) error
	Name(context.Context, Window) (string, error)
}
type lease struct {
	W                 Window
	Original, Written string
	Retry             time.Time
}
type Manager struct {
	CanAct   func() bool
	B        Backend
	Leases   map[string]*lease
	Retry    map[string]time.Time
	Clock    func() time.Time
	ReadOnly bool
	Emit     func(string, Window)
}

func NewManager(b Backend, ro bool) *Manager {
	return &Manager{B: b, Leases: map[string]*lease{}, Retry: map[string]time.Time{}, Clock: time.Now, ReadOnly: ro, Emit: emit}
}
func cleanName(s string) (string, error) {
	s = strings.TrimSpace(strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, s))
	if utf8.RuneCountInString(s) > 240 {
		return "", errors.New("root-name-too-long")
	}
	return s, nil
}
func (m *Manager) restore(key string) {
	l := m.Leases[key]
	if l == nil {
		return
	}
	if !m.B.Same(l.W) {
		delete(m.Leases, key)
		return
	}
	current, e := m.B.Caption(l.W)
	if e != nil {
		return
	}
	if current != l.Written {
		delete(m.Leases, key)
		m.Emit("restore-skipped-external-change", l.W)
		return
	}
	if m.ReadOnly {
		return
	}
	if m.B.Set(l.W, current, l.Original) == nil {
		delete(m.Leases, key)
		m.Emit("restored", l.W)
	}
}
func (m *Manager) Restore() {
	for k := range m.Leases {
		m.restore(k)
	}
}
func (m *Manager) Tick(ctx context.Context) {
	windows, e := m.B.List()
	if e != nil {
		m.Emit("windows-unavailable", Window{})
		return
	}
	for _, w := range windows {
		if ctx.Err() != nil || (m.CanAct != nil && !m.CanAct()) {
			return
		}
		key := w.Key()
		if m.Clock().Before(m.Retry[key]) {
			continue
		}
		if !m.B.Active(w) || !m.B.Same(w) {
			continue
		}
		before, e := m.B.Caption(w)
		if e != nil {
			continue
		}
		if old := m.Leases[key]; old != nil && before != old.Written && !genericCaption(before) {
			delete(m.Leases, key)
			m.Retry[key] = m.Clock().Add(30 * time.Second)
			m.Emit("external-change-backoff", w)
			continue
		}
		title, e := m.B.Name(ctx, w)
		if e != nil {
			if !m.B.Active(w) {
				continue
			}
			m.Retry[key] = m.Clock().Add(time.Second)
			m.Emit("root-name-unavailable", w)
			continue
		}
		if ctx.Err() != nil || (m.CanAct != nil && !m.CanAct()) || !m.B.Active(w) || !m.B.Same(w) {
			continue
		}
		latest, e := m.B.Caption(w)
		if e != nil || latest != before {
			delete(m.Leases, key)
			m.Retry[key] = m.Clock().Add(30 * time.Second)
			continue
		}
		title, e = cleanName(title)
		if e != nil {
			m.Emit("root-name-invalid", w)
			continue
		}
		if title == "" || strings.EqualFold(title, "ChatGPT") {
			m.restore(key)
			continue
		}
		if m.ReadOnly {
			m.Emit("read-only-name-available", w)
			continue
		}
		desired := title
		if !strings.HasSuffix(desired, " — ChatGPT") {
			desired += " — ChatGPT"
		}
		if latest == desired {
			continue
		}
		if !m.B.Active(w) {
			continue
		}
		if e = m.B.SetActive(w, latest, desired); e != nil {
			m.Retry[key] = m.Clock().Add(30 * time.Second)
			m.Emit("title-not-writable-or-unconfirmed", w)
			continue
		}
		original := latest
		if old := m.Leases[key]; old != nil {
			original = old.Original
		}
		m.Leases[key] = &lease{W: w, Original: original, Written: desired}
		m.Emit("updated", w)
	}
}

func genericCaption(s string) bool {
	return strings.TrimSpace(s) == "" || strings.EqualFold(strings.TrimSpace(s), "ChatGPT")
}
