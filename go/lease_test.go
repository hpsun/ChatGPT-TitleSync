package main

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

type fake struct {
	inactive              bool
	reads                 int
	w                     Window
	cap, title            string
	alive, writable, fail bool
	writes                int
	during                func()
}

func (f *fake) List() ([]Window, error) {
	if f.inactive {
		return nil, nil
	}
	return []Window{f.w}, nil
}
func (f *fake) Same(w Window) bool               { return f.alive && w.Key() == f.w.Key() }
func (f *fake) Caption(w Window) (string, error) { return f.cap, nil }
func (f *fake) Set(w Window, a, b string) error {
	if !f.Same(w) || f.cap != a || !f.writable {
		return errors.New("write-rejected")
	}
	f.cap = b
	f.writes++
	return nil
}
func (f *fake) Name(ctx context.Context, w Window) (string, error) {
	f.reads++
	if f.during != nil {
		f.during()
	}
	if f.fail {
		return "", errors.New("private-body-never-log")
	}
	return f.title, nil
}
func fixture() (*Manager, *fake) {
	f := &fake{w: Window{1, 2, 3, "own", "fixture"}, cap: "Original", title: "项目计划", alive: true, writable: true}
	m := NewManager(f, false)
	m.Emit = func(string, Window) {}
	return m, f
}
func TestRestore(t *testing.T) {
	m, f := fixture()
	m.Tick(context.Background())
	m.Restore()
	if f.cap != "Original" || f.writes != 2 {
		t.Fatal(f)
	}
}
func TestExternalChange(t *testing.T) {
	m, f := fixture()
	m.Tick(context.Background())
	f.cap = "External"
	m.Restore()
	if f.cap != "External" {
		t.Fatal(f)
	}
}
func TestIdentityReuse(t *testing.T) {
	m, f := fixture()
	m.Tick(context.Background())
	f.w.Start++
	m.Restore()
	if f.writes != 1 {
		t.Fatal(f)
	}
}
func TestReadOnly(t *testing.T) {
	m, f := fixture()
	m.ReadOnly = true
	m.Tick(context.Background())
	m.Restore()
	if f.writes != 0 {
		t.Fatal(f)
	}
}
func TestNoFakeWriteSuccess(t *testing.T) {
	m, f := fixture()
	f.writable = false
	m.Tick(context.Background())
	if len(m.Leases) != 0 || f.writes != 0 {
		t.Fatal(f)
	}
}
func TestReaderFailureNoPrivateLog(t *testing.T) {
	m, f := fixture()
	f.fail = true
	var log string
	m.Emit = func(c string, w Window) { log += c }
	m.Tick(context.Background())
	if strings.Contains(log, "private") || f.writes != 0 {
		t.Fatal(log)
	}
}
func TestReaderIdentityRace(t *testing.T) {
	m, f := fixture()
	f.during = func() { f.w.Start++ }
	m.Tick(context.Background())
	if f.writes != 0 {
		t.Fatal(f)
	}
}
func TestReaderCaptionRace(t *testing.T) {
	m, f := fixture()
	f.during = func() { f.cap = "External" }
	m.Tick(context.Background())
	if f.writes != 0 || f.cap != "External" {
		t.Fatal(f)
	}
}
func TestPauseDuringRead(t *testing.T) {
	m, f := fixture()
	ok := true
	m.CanAct = func() bool { return ok }
	f.during = func() { ok = false }
	m.Tick(context.Background())
	if f.writes != 0 {
		t.Fatal(f)
	}
}
func TestCanceled(t *testing.T) {
	m, f := fixture()
	ctx, c := context.WithCancel(context.Background())
	c()
	m.Tick(ctx)
	if f.writes != 0 {
		t.Fatal(f)
	}
}
func TestGenericRestores(t *testing.T) {
	m, f := fixture()
	m.Tick(context.Background())
	f.title = "ChatGPT"
	m.Tick(context.Background())
	if f.cap != "Original" {
		t.Fatal(f)
	}
}
func TestFightBackoff(t *testing.T) {
	m, f := fixture()
	now := time.Now()
	m.Clock = func() time.Time { return now }
	m.Tick(context.Background())
	f.cap = "External"
	m.Tick(context.Background())
	m.Tick(context.Background())
	if f.cap != "External" || f.writes != 1 {
		t.Fatal(f)
	}
	now = now.Add(31 * time.Second)
	m.Tick(context.Background())
	m.Restore()
	if f.cap != "External" {
		t.Fatal(f)
	}
}
func TestOriginalKeptAcrossNames(t *testing.T) {
	m, f := fixture()
	m.Tick(context.Background())
	f.title = "资料整理"
	m.Tick(context.Background())
	m.Restore()
	if f.cap != "Original" {
		t.Fatal(f)
	}
}
func TestAlreadyDesiredNoOwnership(t *testing.T) {
	m, f := fixture()
	f.cap = "项目计划 — ChatGPT"
	m.Tick(context.Background())
	m.Restore()
	if f.writes != 0 || len(m.Leases) != 0 {
		t.Fatal(f)
	}
}
func TestNameLimit(t *testing.T) {
	m, f := fixture()
	f.title = strings.Repeat("x", 241)
	m.Tick(context.Background())
	if f.writes != 0 {
		t.Fatal(f)
	}
}

func TestNonTargetForegroundNoRead(t *testing.T) {
	m, f := fixture()
	f.inactive = true
	m.Tick(context.Background())
	if f.reads != 0 || f.writes != 0 {
		t.Fatal(f)
	}
}
func TestFocusChangesDuringReadNoWrite(t *testing.T) {
	m, f := fixture()
	f.during = func() { f.inactive = true }
	m.Tick(context.Background())
	if f.writes != 0 {
		t.Fatal(f)
	}
}
func TestInactiveKeepsCaptionAndLease(t *testing.T) {
	m, f := fixture()
	m.Tick(context.Background())
	f.inactive = true
	m.Tick(context.Background())
	if f.cap != "项目计划 — ChatGPT" || len(m.Leases) != 1 {
		t.Fatal(f)
	}
	m.Restore()
	if f.cap != "Original" {
		t.Fatal(f)
	}
}
func TestGenericCaptionNoManualBackoff(t *testing.T) {
	m, f := fixture()
	m.Tick(context.Background())
	f.cap = "ChatGPT"
	f.title = "资料整理"
	m.Tick(context.Background())
	if f.cap != "资料整理 — ChatGPT" {
		t.Fatal(f)
	}
}
func (f *fake) Active(w Window) bool { return !f.inactive && f.Same(w) }
func (f *fake) SetActive(w Window, a, b string) error {
	if !f.Active(w) {
		return errors.New("focus-changed")
	}
	return f.Set(w, a, b)
}

func TestDeadlineDoesNotDriftAfterRead(t *testing.T) {
	base := time.Unix(100, 0)
	if advanceDeadline(base, base.Add(200*time.Millisecond), time.Second) != base.Add(time.Second) {
		t.Fatal("completion-based drift")
	}
}
func TestDeadlineSkipsMissedTicks(t *testing.T) {
	base := time.Unix(100, 0)
	if advanceDeadline(base, base.Add(3200*time.Millisecond), time.Second) != base.Add(4*time.Second) {
		t.Fatal("missed deadline backlog")
	}
}

func TestDeadlineExactlyDueRunsWithoutExtraSleep(t *testing.T) {
	b := time.Unix(100, 0)
	if advanceDeadline(b, b.Add(time.Second), time.Second) != b.Add(time.Second) {
		t.Fatal("extra one-second wait at exact deadline")
	}
}
