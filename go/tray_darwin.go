//go:build darwin && cgo

package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"
)

// The transparent public companion uses the system osascript runtime, not a private binary.
func runWithTray(ctx context.Context, s *liveSettings, cancel context.CancelFunc, work func()) error {
	exe, e := os.Executable()
	if e != nil {
		return e
	}
	exe, e = filepath.Abs(exe)
	if e != nil {
		return e
	}
	dir := filepath.Dir(exe)
	script := ""
	for _, p := range []string{filepath.Join(dir, "TraySettings.applescript"), filepath.Join(dir, "../macos/TraySettings.applescript"), filepath.Join(dir, "macos/TraySettings.applescript")} {
		if exists(p) {
			script = p
			break
		}
	}
	if script == "" {
		return fmt.Errorf("missing public TraySettings.applescript; use --no-tray for CLI controls")
	}
	v := s.snapshot()
	ready := filepath.Join(filepath.Dir(s.path), fmt.Sprintf("tray-ready-%d", os.Getpid()))
	defer os.Remove(ready)
	icon := filepath.Join(filepath.Dir(script), "../assets/chatgpt-titlesync-icon.png")
	cmd := exec.Command("/usr/bin/osascript", script, s.path, filepath.Join(filepath.Dir(s.path), "stop"), "json", strconv.Itoa(v.ForegroundSeconds), strconv.Itoa(v.BackgroundSeconds), strconv.FormatBool(v.Enabled), ready, icon, "Go", strconv.FormatBool(v.AutoStartEnabled), exe)
	cmd.Stderr = os.Stderr
	if e := cmd.Start(); e != nil {
		return fmt.Errorf("menu companion: %w; use --no-tray for CLI controls", e)
	}
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()
	for deadline := time.Now().Add(8 * time.Second); !exists(ready); {
		select {
		case e := <-exited:
			return fmt.Errorf("menu companion exited before ready: %v; use --no-tray for CLI controls", e)
		case <-ctx.Done():
			cmd.Process.Kill()
			<-exited
			return ctx.Err()
		case <-time.After(50 * time.Millisecond):
		}
		if time.Now().After(deadline) {
			cmd.Process.Kill()
			<-exited
			return fmt.Errorf("menu companion startup timeout; use --no-tray for CLI controls")
		}
	}
	stopped := make(chan struct{})
	watchDone := make(chan error, 1)
	go func() {
		tick := time.NewTicker(100 * time.Millisecond)
		defer tick.Stop()
		for {
			select {
			case e := <-exited:
				cancel()
				watchDone <- fmt.Errorf("menu companion exited: %v", e)
				return
			case <-stopped:
				cmd.Process.Kill()
				<-exited
				watchDone <- nil
				return
			case <-tick.C:
				old := s.snapshot()
				next := loadSettings(s.path, old)
				if next.ForegroundSeconds != old.ForegroundSeconds || next.BackgroundSeconds != old.BackgroundSeconds || next.Enabled != old.Enabled || next.AutoStartEnabled != old.AutoStartEnabled {
					s.mu.Lock()
					next.Revision = s.value.Revision + 1
					s.value = next
					s.mu.Unlock()
				}
			}
		}
	}()
	work()
	close(stopped)
	e = <-watchDone
	if exists(filepath.Join(filepath.Dir(s.path), "stop")) {
		return nil
	}
	return e
}
