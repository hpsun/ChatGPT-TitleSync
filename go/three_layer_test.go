package main

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"
)

type protocolFake struct {
	ws     []Window
	fg     uint64
	caps   map[uint64]string
	writes int
}

func protocolFixture() (*titleCache, *protocolFake) {
	a := Window{11, 7, 9, "fixture", "fixture"}
	b := Window{22, 7, 9, "fixture", "fixture"}
	f := &protocolFake{[]Window{a, b}, 11, map[uint64]string{11: "ChatGPT", 22: "ChatGPT"}, 0}
	return newTitleCache(f, false, defaultBackgroundSeconds*time.Second), f
}
func (f *protocolFake) List() ([]Window, error) {
	for _, w := range f.ws {
		if w.Handle == f.fg {
			return []Window{w}, nil
		}
	}
	return nil, nil
}
func (f *protocolFake) Same(w Window) bool {
	for _, x := range f.ws {
		if x.Key() == w.Key() {
			return true
		}
	}
	return false
}
func (f *protocolFake) Active(w Window) bool { return f.fg == w.Handle && f.Same(w) }
func (f *protocolFake) Caption(w Window) (string, error) {
	v, ok := f.caps[w.Handle]
	if !ok {
		return "", errors.New("gone")
	}
	return v, nil
}
func (f *protocolFake) Set(w Window, a, b string) error {
	if !f.Same(w) || f.caps[w.Handle] != a {
		return errors.New("changed")
	}
	f.caps[w.Handle] = b
	f.writes++
	return nil
}
func (f *protocolFake) SetActive(w Window, a, b string) error {
	if !f.Active(w) {
		return errors.New("inactive")
	}
	return f.Set(w, a, b)
}
func (f *protocolFake) Name(context.Context, Window) (string, error) {
	panic("native maintenance must never read a source")
}
func TestThreeLayerForegroundAlwaysFresh(t *testing.T) {
	c, f := protocolFixture()
	a := f.ws[0]
	c.apply(sourceResult{Job: c.job(a, true), Title: "First"})
	f.caps[11] = "ChatGPT"
	c.maintain()
	if f.caps[11] != "ChatGPT" {
		t.Fatal("cache replayed into foreground")
	}
	c.apply(sourceResult{Job: c.job(a, true), Title: "Second"})
	if f.caps[11] != "Second — ChatGPT" {
		t.Fatal(f.caps)
	}
}
func TestThreeLayerBackgroundNativeRepairWithoutRead(t *testing.T) {
	c, f := protocolFixture()
	c.apply(sourceResult{Job: c.job(f.ws[0], true), Title: "First"})
	f.fg = 0
	f.caps[11] = "ChatGPT"
	c.maintain()
	if f.caps[11] != "First — ChatGPT" {
		t.Fatal(f.caps)
	}
}
func TestThreeLayerCustomProtectedCacheCanRefresh(t *testing.T) {
	c, f := protocolFixture()
	a := f.ws[0]
	c.apply(sourceResult{Job: c.job(a, true), Title: "First"})
	f.fg = 0
	f.caps[11] = "Custom"
	c.maintain()
	j := c.job(a, false)
	c.apply(sourceResult{Job: j, Title: "Updated"})
	if f.caps[11] != "Custom" {
		t.Fatal("custom overwritten")
	}
	f.caps[11] = "ChatGPT"
	c.maintain()
	if f.caps[11] != "Updated — ChatGPT" {
		t.Fatal(f.caps)
	}
}
func TestThreeLayerUnknownLowFrequencyCache(t *testing.T) {
	c, f := protocolFixture()
	f.fg = 0
	now := time.Unix(100, 0)
	c.Clock = func() time.Time { return now }
	c.remember(f.ws[1])
	js := c.backgroundJobs()
	if len(js) != 1 {
		t.Fatal(js)
	}
	c.apply(sourceResult{Job: js[0], Title: "Background"})
	if f.caps[22] != "Background — ChatGPT" {
		t.Fatal(f.caps)
	}
	now = now.Add(4 * time.Second)
	if len(c.backgroundJobs()) != 0 {
		t.Fatal("early background sample")
	}
	now = now.Add(time.Second)
	if len(c.backgroundJobs()) != 1 {
		t.Fatal("due sample missing")
	}
}
func TestThreeLayerStaleBackgroundCannotReplaceFresh(t *testing.T) {
	c, f := protocolFixture()
	a := f.ws[0]
	f.fg = 0
	j := c.job(a, false)
	f.fg = 11
	c.apply(sourceResult{Job: c.job(a, true), Title: "Fresh"})
	f.fg = 0
	c.apply(sourceResult{Job: j, Title: "Old"})
	if c.Entries[a.Key()].Title != "Fresh — ChatGPT" {
		t.Fatal("stale cache")
	}
}
func TestThreeLayerIdentityChangeDropsCache(t *testing.T) {
	c, f := protocolFixture()
	a := f.ws[0]
	c.apply(sourceResult{Job: c.job(a, true), Title: "First"})
	f.fg = 0
	f.ws[0].Start++
	before := f.writes
	c.maintain()
	if len(c.Entries) != 0 || f.writes != before {
		t.Fatal("identity reused")
	}
}
func TestThreeLayerPauseGenerationRejectsOldResult(t *testing.T) {
	c, f := protocolFixture()
	j := c.job(f.ws[0], true)
	c.Epoch++
	c.apply(sourceResult{Job: j, Title: "Old"})
	if f.writes != 0 {
		t.Fatal("pre-pause result committed")
	}
}
func TestThreeLayerRestoreOnlyOwnMatchingCaption(t *testing.T) {
	c, f := protocolFixture()
	c.apply(sourceResult{Job: c.job(f.ws[0], true), Title: "First"})
	c.restore()
	if f.caps[11] != "ChatGPT" {
		t.Fatal(f.caps)
	}
}
func TestThreeLayerForegroundNotBlockedBySlowBackground(t *testing.T) {
	c, f := protocolFixture()
	a, b := f.ws[0], f.ws[1]
	started := make(chan struct{})
	fore := make(chan time.Time, 100)
	var bgReads atomic.Int32
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	fn := sourceFunctions{Discover: func() ([]Window, error) { return []Window{a, b}, nil }, Read: func(ctx context.Context, w Window, fg bool) (string, error) {
		if fg {
			select {
			case fore <- time.Now():
			default:
			}
			return "Fresh", nil
		}
		if bgReads.Add(1) == 1 {
			close(started)
		}
		<-ctx.Done()
		return "", ctx.Err()
	}}
	go func() { runThreeLayer(ctx, c, 20*time.Millisecond, fn, func() bool { return false }); close(done) }()
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		cancel()
		<-done
		t.Fatal("background did not start")
	}
	after := time.Now()
	deadline := time.After(500 * time.Millisecond)
	seen := false
	for !seen {
		select {
		case at := <-fore:
			if at.After(after) {
				seen = true
			}
		case <-deadline:
			cancel()
			<-done
			t.Fatal("foreground waited on background")
		}
	}
	cancel()
	<-done
	if bgReads.Load() != 1 {
		t.Fatal("background worker not serial")
	}
}

func TestLiveIntervalChangeReschedulesWithoutRestart(t *testing.T) {
	c, f := protocolFixture()
	var fgMS, bgMS atomic.Int64
	fgMS.Store(2000)
	bgMS.Store(5000)
	var reads, discoveries atomic.Int32
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	fn := sourceFunctions{Settings: func() (time.Duration, time.Duration) {
		return time.Duration(fgMS.Load()) * time.Millisecond, time.Duration(bgMS.Load()) * time.Millisecond
	}, Discover: func() ([]Window, error) { discoveries.Add(1); return nil, nil }, Read: func(_ context.Context, _ Window, fg bool) (string, error) {
		if fg {
			reads.Add(1)
		}
		return "Fresh", nil
	}}
	go func() { runThreeLayer(ctx, c, 2*time.Second, fn, func() bool { return false }); close(done) }()
	deadline := time.Now().Add(time.Second)
	for reads.Load() < 1 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if reads.Load() < 1 {
		cancel()
		<-done
		t.Fatal("initial source read absent")
	}
	fgMS.Store(50)
	bgMS.Store(6000)
	deadline = time.Now().Add(700 * time.Millisecond)
	for (reads.Load() < 3 || discoveries.Load() < 2) && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	cancel()
	<-done
	if reads.Load() < 3 || discoveries.Load() < 2 {
		t.Fatalf("hot settings failed: reads=%d discovery=%d", reads.Load(), discoveries.Load())
	}
	if c.Background != 6*time.Second || f.caps[11] != "ChatGPT" {
		t.Fatal("new cadence or exit restoration failed")
	}
}
