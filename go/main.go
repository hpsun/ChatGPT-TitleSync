package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

type nativeBackend struct{}

func (nativeBackend) SetInactive(w Window, a, b string) error { return nativeSetInactive(w, a, b) }

func (nativeBackend) List() ([]Window, error)               { return nativeList() }
func (nativeBackend) Active(w Window) bool                  { return nativeActive(w) }
func (nativeBackend) SetActive(w Window, a, b string) error { return nativeSetActive(w, a, b) }
func (nativeBackend) Same(w Window) bool                    { return nativeSame(w) }
func (nativeBackend) Caption(w Window) (string, error)      { return nativeCaption(w) }
func (nativeBackend) Set(w Window, old, new string) error   { return nativeSet(w, old, new) }
func (nativeBackend) Name(ctx context.Context, w Window) (string, error) {
	if runtime.GOOS == "darwin" {
		return isolatedName(ctx, w)
	}
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
				if !nativeActive(w) {
					cancel()
					return
				}
			}
		}
	}()
	return isolatedName(bounded, w)
}
func emit(code string, w Window) {
	_ = json.NewEncoder(os.Stdout).Encode(map[string]interface{}{"utc": time.Now().UTC().Format(time.RFC3339), "event": code, "window": w.Handle, "pid": w.PID})
}

type probeResult struct {
	Window Window `json:"window"`
	Title  string `json:"title,omitempty"`
	Error  string `json:"error,omitempty"`
}
type limitedOutput struct {
	b        []byte
	overflow bool
}

func (o *limitedOutput) Write(p []byte) (int, error) {
	n := len(p)
	if len(o.b)+n > 32768 {
		o.overflow = true
	}
	space := 32768 - len(o.b)
	if space > 0 {
		if len(p) > space {
			p = p[:space]
		}
		o.b = append(o.b, p...)
	}
	return n, nil
}
func childName(ctx context.Context, w Window) (string, error) { return childNameMode(ctx, w, true) }
func childNameMode(ctx context.Context, w Window, foreground bool) (string, error) {
	exe, e := os.Executable()
	if e != nil {
		return "", e
	}
	raw, _ := json.Marshal(w)
	query := base64.RawURLEncoding.EncodeToString(raw)
	bounded, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	mode := "--probe"
	if !foreground {
		mode = "--probe-background"
	}
	cmd := exec.CommandContext(bounded, exe, mode, query)
	hideChild(cmd)
	if !foreground {
		backgroundChild(cmd)
	}
	out := &limitedOutput{}
	cmd.Stdout = out
	cmd.Stderr = io.Discard
	if e = cmd.Run(); e != nil {
		return "", errors.New("reader-failed-or-timeout")
	}
	if out.overflow {
		return "", errors.New("reader-output-too-large")
	}
	var r probeResult
	if json.Unmarshal(out.b, &r) != nil || r.Window.Key() != w.Key() || r.Error != "" {
		return "", errors.New("reader-identity-or-name-unavailable")
	}
	return r.Title, nil
}

type owner struct {
	PID        uint32
	Start      uint64
	Exe, Nonce string
}

func lockState(dir string) (func(), error) {
	meStart, meExe, e := processIdentity(uint32(os.Getpid()))
	if e != nil {
		return nil, e
	}
	me := owner{uint32(os.Getpid()), meStart, meExe, fmt.Sprintf("%d", time.Now().UnixNano())}
	p := filepath.Join(dir, "owner.json")
	for attempt := 0; attempt < 2; attempt++ {
		f, e := os.OpenFile(p, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if e == nil {
			b, _ := json.Marshal(me)
			_, e = f.Write(b)
			_ = f.Close()
			if e != nil {
				return nil, e
			}
			return func() {
				b, _ := os.ReadFile(p)
				var current owner
				if json.Unmarshal(b, &current) == nil && current.Nonce == me.Nonce {
					_ = os.Remove(p)
				}
			}, nil
		}
		if !os.IsExist(e) {
			return nil, e
		}
		b, _ := os.ReadFile(p)
		var old owner
		if json.Unmarshal(b, &old) == nil {
			s, x, e := processIdentity(old.PID)
			if e == nil && s == old.Start && strings.EqualFold(x, old.Exe) {
				return nil, errors.New("already-running")
			}
		}
		_ = os.Remove(p)
	}
	return nil, errors.New("cannot-acquire-state-lock")
}
func exists(p string) bool { _, e := os.Stat(p); return e == nil }
func run() int {
	f := flag.NewFlagSet("chatgpt-titlesync-go", flag.ContinueOnError)
	background := f.Int("background-interval", defaultBackgroundSeconds, "per-window background source interval seconds (5..3600)")
	noTray := f.Bool("no-tray", false, "run without the native tray interface")
	interval := f.Int("interval", defaultForegroundSeconds, "active-window check deadline in seconds (1..3600)")
	once := f.Bool("once", false, "one poll then guarded restore")
	readonly := f.Bool("read-only", false, "read names only; never write captions")
	stop := f.Bool("stop", false, "request cooperative stop and title restoration")
	pause := f.Bool("pause", false, "pause polling and restore owned captions")
	resume := f.Bool("resume", false, "resume polling")
	test := f.Bool("self-test", false, "only owned native fixture; no real ChatGPT access")
	probeBackground := f.String("probe-background", "", "internal background source reader")
	probe := f.String("probe", "", "internal isolated UIA reader identity")
	base, _ := os.UserConfigDir()
	// Compatibility: retain the historical state directory and lease format so old/new residents share saved settings and ownership.
	state := f.String("state-dir", filepath.Join(base, "ChatGPT-title-go"), "private control directory; distinct from other languages")
	if err := f.Parse(os.Args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if *background < 5 || *background > 3600 {
		return 2
	}
	if *interval < 1 || *interval > 3600 {
		return 2
	}
	if *probeBackground != "" {
		*probe = *probeBackground
	}
	if *probe != "" {
		var w Window
		b, e := base64.RawURLEncoding.DecodeString(*probe)
		if e != nil || json.Unmarshal(b, &w) != nil {
			return 2
		}
		r := probeResult{Window: w}
		fg := *probeBackground == ""
		if !nativeSame(w) || nativeActive(w) != fg {
			r.Error = "identity-mismatch"
		} else {
			r.Title, e = nativeReadNameMode(w, fg)
			if e != nil || nativeActive(w) != fg || !nativeSame(w) {
				r.Title = ""
				r.Error = "name-unavailable"
			}
		}
		_ = json.NewEncoder(os.Stdout).Encode(r)
		return 0
	}
	if *test {
		if e := nativeSelfTest(); e != nil {
			fmt.Fprintln(os.Stderr, e)
			return 1
		}
		emit("owned-self-test-passed", Window{})
		return 0
	}
	if e := os.MkdirAll(*state, 0700); e != nil {
		fmt.Fprintln(os.Stderr, e)
		return 1
	}
	stopFile, pauseFile := filepath.Join(*state, "stop"), filepath.Join(*state, "pause")
	if *stop && runtime.GOOS == "windows" {
		if e := nativeRequestStop(); e != nil {
			fmt.Fprintln(os.Stderr, e)
			return 1
		}
		return 0
	}
	if *stop {
		if e := os.WriteFile(stopFile, []byte("stop"), 0600); e != nil {
			fmt.Fprintln(os.Stderr, e)
			return 1
		}
		return 0
	}
	if *pause {
		if e := os.WriteFile(pauseFile, []byte("pause"), 0600); e != nil {
			fmt.Fprintln(os.Stderr, e)
			return 1
		}
		return 0
	}
	if *resume {
		if e := os.Remove(pauseFile); e != nil && !os.IsNotExist(e) {
			fmt.Fprintln(os.Stderr, e)
			return 1
		}
		return 0
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	sharedRelease, e := nativeAcquire()
	if e != nil {
		fmt.Fprintln(os.Stderr, e)
		return 1
	}
	defer sharedRelease()
	release, e := lockState(*state)
	if e != nil {
		fmt.Fprintln(os.Stderr, e)
		return 1
	}
	defer release()
	_ = os.Remove(stopFile)
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	var paused atomic.Bool
	go func() {
		t := time.NewTicker(100 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				paused.Store(exists(pauseFile))
				if exists(stopFile) || nativeStopRequested() {
					cancel()
					return
				}
			}
		}
	}()
	if *once {
		cache := newTitleCache(nativeBackend{}, *readonly, time.Duration(*background)*time.Second)
		if j, ok := cache.foregroundJob(); ok {
			title, err := nativeReadSource(ctx, j.W, true)
			cache.apply(sourceResult{j, title, err})
		}
		cache.restore()
		return 0
	}

	settingsPath := filepath.Join(*state, "settings.json")
	initial := loadSettings(settingsPath, scanSettings{ForegroundSeconds: *interval, BackgroundSeconds: *background, Enabled: true, AutoStartEnabled: true})
	f.Visit(func(fl *flag.Flag) {
		if fl.Name == "interval" {
			initial.ForegroundSeconds = *interval
		}
		if fl.Name == "background-interval" {
			initial.BackgroundSeconds = *background
		}
	})
	var startup startupPreference
	if !*readonly {
		var e error
		initial, startup, e = prepareNativeStartup(initial)
		if e != nil {
			fmt.Fprintln(os.Stderr, "autostart:", e)
			return 1
		}
	}
	settings := &liveSettings{value: initial, path: settingsPath, startup: startup}
	cache := newTitleCache(nativeBackend{}, *readonly, time.Duration(initial.BackgroundSeconds)*time.Second)
	work := func() {
		runThreeLayer(ctx, cache, time.Duration(initial.ForegroundSeconds)*time.Second, sourceFunctions{
			Read: func(readCtx context.Context, w Window, foreground bool) (string, error) {
				v := settings.snapshot()
				bounded, cancelRead := context.WithCancel(readCtx)
				defer cancelRead()
				var wg sync.WaitGroup
				wg.Add(1)
				go func() {
					defer wg.Done()
					tick := time.NewTicker(40 * time.Millisecond)
					defer tick.Stop()
					for {
						select {
						case <-bounded.Done():
							return
						case <-tick.C:
							now := settings.snapshot()
							if !now.Enabled || now.Revision != v.Revision {
								cancelRead()
								return
							}
						}
					}
				}()
				title, err := nativeReadSource(bounded, w, foreground)
				cancelRead()
				wg.Wait()
				return title, err
			},
			Discover: nativeListAll,
			Settings: func() (time.Duration, time.Duration) {
				v := settings.snapshot()
				return time.Duration(v.ForegroundSeconds) * time.Second, time.Duration(v.BackgroundSeconds) * time.Second
			}}, func() bool { return paused.Load() || exists(pauseFile) || !settings.snapshot().Enabled })
	}
	if *noTray || *readonly {
		work()
	} else if e := runWithTray(ctx, settings, cancel, work); e != nil {
		fmt.Fprintln(os.Stderr, e)
		return 1
	}
	return 0
}
func main() { os.Exit(run()) }

func advanceDeadline(previous, now time.Time, interval time.Duration) time.Time {
	next := previous.Add(interval)
	if next.Before(now) {
		delta := now.Sub(next)
		steps := delta / interval
		if delta%interval != 0 {
			steps++
		}
		next = next.Add(steps * interval)
	}
	return next
}
