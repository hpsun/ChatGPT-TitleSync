package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
	"unicode/utf16"
)

func captionRuleConfig(appendSuffix bool, enabled bool, rules []map[string]any) []byte {
	b, _ := json.Marshal(map[string]any{"schema_version": 1, "enabled": enabled, "revision": "11111111-1111-4111-8111-111111111111", "append_chatgpt_suffix": appendSuffix, "rules": rules})
	return b
}
func TestRuleCaptionPacketLimitsAndFixtureDefault(t *testing.T) {
	state := t.TempDir()
	c := newNameRuleClientAt(context.Background(), state, filepath.Join(state, "absent.json"), "", "", formatRuleWorker)
	defer c.Close()
	if c.CaptionMode {
		t.Fatal("body fixture default changed")
	}
	full := strings.Repeat("a", 512) + ruleCaptionSuffix
	b := []byte{}
	for _, u := range utf16.Encode([]rune(full)) {
		b = append(b, byte(u), byte(u>>8))
	}
	if _, e := decodeRulePacket(b); e == nil {
		t.Fatal("body decoder accepted a caption packet")
	}
	if got, e := decodeRulePacketLimit(b, 522); e != nil || got != full {
		t.Fatal("522-unit caption", e)
	}
	if !validRuleCaption(full) || validRuleCaption(strings.Repeat("a", 513)+ruleCaptionSuffix) || validRuleCaption("a\nb") {
		t.Fatal("caption body/full/control bound")
	}
	if localRuleRaw(strings.Repeat("a", 513), true) != strings.Repeat("a", 513) || localRuleRaw("a\nb", true) != "a\nb" {
		t.Fatal("invalid raw decorated")
	}
	if !validRuleCaption(strings.Repeat("a", 512)) {
		t.Fatal("512-unit suffix-off body rejected")
	}
}
func TestRuleCaptionMissingReadFailureAndMissingHelper(t *testing.T) {
	state := t.TempDir()
	rules := filepath.Join(state, "absent", "rules.json")
	var calls atomic.Int32
	runner := func(context.Context, string, string, []byte, bool, string) ruleMemo { calls.Add(1); return ruleMemo{} }
	c := newNameRuleClientAt(context.Background(), state, rules, "", "", runner)
	c.CaptionMode = true
	defer c.Close()
	c.Poll([]string{"Example"})
	v, ready := c.Display("Example")
	if !ready || v != "Example"+ruleCaptionSuffix || calls.Load() != 0 {
		t.Fatal("missing default", v, ready, calls.Load())
	}
	if _, e := os.Stat(filepath.Dir(rules)); !os.IsNotExist(e) {
		t.Fatal("missing config parent created")
	}
	_ = os.MkdirAll(filepath.Dir(rules), 0700)
	_ = os.Mkdir(rules, 0700)
	c.nextPoll = time.Time{}
	c.Poll([]string{"Example"})
	v, ready = c.Display("Example")
	if !ready || v != "Example"+ruleCaptionSuffix || calls.Load() != 0 {
		t.Fatal("read failure default")
	}
	got := formatCaptionRuleWorker(context.Background(), state, "", captionRuleConfig(false, true, []map[string]any{}), false, "Example")
	if got.Value != "Example"+ruleCaptionSuffix || got.Status != "fallback:CompanionMissing" {
		t.Fatal(got)
	}
}
func TestRuleCaptionExistingEmptyDisabledUsesWorker(t *testing.T) {
	for _, enabled := range []bool{true, false} {
		state := t.TempDir()
		rules := filepath.Join(state, "rules.json")
		_ = os.WriteFile(rules, captionRuleConfig(false, enabled, []map[string]any{}), 0600)
		var calls atomic.Int32
		c := newNameRuleClientAt(context.Background(), state, rules, "fake", "", func(_ context.Context, _ string, _ string, b []byte, _ bool, raw string) ruleMemo {
			calls.Add(1)
			if !strings.Contains(string(b), "\"append_chatgpt_suffix\":false") {
				t.Error("rules changed")
			}
			return ruleMemo{raw, "ok"}
		})
		c.CaptionMode = true
		c.Poll([]string{"Example"})
		until := time.Now().Add(time.Second)
		for {
			v, ready := c.Display("Example")
			if ready {
				if v != "Example" || calls.Load() != 1 {
					t.Fatal("existing rules bypassed worker", enabled, v, calls.Load())
				}
				break
			}
			if time.Now().After(until) {
				t.Fatal("worker did not settle")
			}
			time.Sleep(time.Millisecond)
			c.Poll([]string{"Example"})
		}
		c.Close()
	}
}
func TestRuleCaptionHotRefreshNoDoubleSuffixAndOwnership(t *testing.T) {
	state := t.TempDir()
	rules := filepath.Join(state, "rules.json")
	_ = os.WriteFile(rules, captionRuleConfig(true, true, []map[string]any{}), 0600)
	runner := func(_ context.Context, _ string, _ string, b []byte, _ bool, raw string) ruleMemo {
		if strings.Contains(string(b), "\"append_chatgpt_suffix\":false") {
			return ruleMemo{raw, "ok"}
		}
		return ruleMemo{raw + ruleCaptionSuffix, "ok"}
	}
	client := newNameRuleClientAt(context.Background(), state, rules, "fake", "", runner)
	client.CaptionMode = true
	defer client.Close()
	c, f := protocolFixture()
	c.Rules = client
	w := f.ws[0]
	c.apply(sourceResult{Job: c.job(w, true), Title: "Example"})
	waitDisplay(t, c, func() bool { return f.caps[11] == "Example"+ruleCaptionSuffix })
	e := c.Entries[w.Key()]
	deadline, version, epoch := e.NextBackground, e.Version, c.Epoch
	_ = os.WriteFile(rules, captionRuleConfig(false, true, []map[string]any{}), 0600)
	client.nextPoll = time.Time{}
	waitDisplay(t, c, func() bool { return f.caps[11] == "Example" })
	if e.RawName != "Example" || e.Original != "ChatGPT" || e.Version != version || c.Epoch != epoch || !e.NextBackground.Equal(deadline) {
		t.Fatal("suffix toggle changed source/raw/lease")
	}
	c.restore()
	if f.caps[11] != "ChatGPT" {
		t.Fatal("suffix-off restore failed")
	}
	// A subsequent source capture can own again; a manual caption survives a later toggle.
	c.apply(sourceResult{Job: c.job(w, true), Title: "Example"})
	waitDisplay(t, c, func() bool { return e.Own })
	f.caps[11] = "Manual caption"
	_ = os.WriteFile(rules, captionRuleConfig(true, true, []map[string]any{}), 0600)
	client.nextPoll = time.Time{}
	waitDisplay(t, c, func() bool { return e.RuleEpoch == client.Epoch })
	if f.caps[11] != "Manual caption" {
		t.Fatal("manual caption changed")
	}
	c.restore()
	if f.caps[11] != "Manual caption" {
		t.Fatal("manual caption restored over")
	}
}
func TestRuleCaptionSharedCompanionCases(t *testing.T) {
	helper := os.Getenv("CTS_CAPTION_TEST_HELPER")
	if helper == "" {
		t.Skip("shared caption companion not supplied")
	}
	state := t.TempDir()
	raw := "Example"
	invalid := []map[string]any{{"enabled": true, "mode": "regex", "pattern": "(", "replacement": ""}}
	tests := []struct {
		name     string
		config   []byte
		want     string
		fallback bool
	}{
		{"missing optional field", []byte(`{"schema_version":1,"enabled":true,"revision":"11111111-1111-4111-8111-111111111111","rules":[]}`), raw + ruleCaptionSuffix, false},
		{"false empty", captionRuleConfig(false, true, []map[string]any{}), raw, false},
		{"false disabled", captionRuleConfig(false, false, []map[string]any{}), raw, false},
		{"false rule error", captionRuleConfig(false, true, invalid), raw, true},
		{"true rule error", captionRuleConfig(true, true, invalid), raw + ruleCaptionSuffix, true},
		{"bad json", []byte("{"), raw + ruleCaptionSuffix, true},
		{"512 body off", captionRuleConfig(false, true, []map[string]any{{"enabled": true, "mode": "literal", "pattern": raw, "replacement": strings.Repeat("a", 512)}}), strings.Repeat("a", 512), false},
		{"512 body on", captionRuleConfig(true, true, []map[string]any{{"enabled": true, "mode": "literal", "pattern": raw, "replacement": strings.Repeat("a", 512)}}), strings.Repeat("a", 512) + ruleCaptionSuffix, false},
		{"513 body fallback", captionRuleConfig(false, true, []map[string]any{{"enabled": true, "mode": "literal", "pattern": "E", "replacement": strings.Repeat("a", 507)}}), raw, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := formatCaptionRuleWorker(context.Background(), state, helper, tc.config, false, raw)
			if got.Value != tc.want {
				t.Fatal("caption mismatch", got.Status)
			}
			if tc.fallback != strings.HasPrefix(got.Status, "fallback:") {
				t.Fatal(got.Status)
			}
		})
	}
}
