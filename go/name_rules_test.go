package main

import (
	"context"
	"encoding/binary"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func waitDisplay(t *testing.T, c *titleCache, predicate func() bool) {
	t.Helper()
	until := time.Now().Add(2 * time.Second)
	for !predicate() {
		c.pollNameRules(true)
		if time.Now().After(until) {
			t.Fatal("display worker did not settle")
		}
		time.Sleep(5 * time.Millisecond)
	}
}
func TestRulePacketsUnicodeAndBounds(t *testing.T) {
	raw := "Example 示例 😀"
	b, e := encodeRulePacket(raw)
	if e != nil {
		t.Fatal(e)
	}
	v, e := decodeRulePacket(b)
	if e != nil || v != raw {
		t.Fatal(v, e)
	}
	if _, e = decodeRulePacket([]byte{0, 0xd8}); e == nil {
		t.Fatal("unpaired surrogate accepted")
	}
	if _, e = encodeRulePacket(strings.Repeat("a", 513)); e == nil {
		t.Fatal("oversize accepted")
	}
	if validRuleDisplay("ChatGPT") || validRuleDisplay("a\nb") {
		t.Fatal("invalid display accepted")
	}
}
func TestRuleMissingFileDoesNotCreateConfiguration(t *testing.T) {
	state := t.TempDir()
	rules := filepath.Join(state, "missing", "title-rules.json")
	var calls atomic.Int32
	client := newNameRuleClientAt(context.Background(), state, rules, "fake", "fake", func(context.Context, string, string, []byte, bool, string) ruleMemo { calls.Add(1); return ruleMemo{} })
	defer client.Close()
	client.Poll([]string{"Example"})
	v, ready := client.Display("Example")
	if !ready || v != "Example" || calls.Load() != 0 {
		t.Fatal(v, ready, calls.Load())
	}
	if _, e := os.Stat(rules); !os.IsNotExist(e) {
		t.Fatal("rules config created")
	}
	b, e := os.ReadFile(filepath.Join(state, "title-rule-sources.bin"))
	if e != nil || string(b[:4]) != "CTS1" || binary.LittleEndian.Uint32(b[4:]) != 1 {
		t.Fatal("snapshot", e)
	}
	if strings.Contains(string(b), "ChatGPT") {
		t.Fatal("display suffix in raw snapshot")
	}
}
func TestRuleCacheRawRevisionLeaseAndCadence(t *testing.T) {
	state := t.TempDir()
	rules := filepath.Join(state, "rules.json")
	_ = os.WriteFile(rules, []byte("first"), 0600)
	var calls atomic.Int32
	runner := func(_ context.Context, _ string, _ string, b []byte, _ bool, raw string) ruleMemo {
		calls.Add(1)
		return ruleMemo{raw + " " + string(b), "ok"}
	}
	client := newNameRuleClientAt(context.Background(), state, rules, "fake", "fake", runner)
	defer client.Close()
	c, f := protocolFixture()
	c.Rules = client
	a := f.ws[0]
	c.apply(sourceResult{Job: c.job(a, true), Title: "Example"})
	waitDisplay(t, c, func() bool { return f.caps[11] == "Example first — ChatGPT" })
	entry := c.Entries[a.Key()]
	deadline, version, sourceEpoch := entry.NextBackground, entry.Version, c.Epoch
	if entry.RawName != "Example" || entry.Original != "ChatGPT" {
		t.Fatal("raw or lease polluted")
	}
	_ = os.WriteFile(rules, []byte("second"), 0600)
	client.nextPoll = time.Time{}
	waitDisplay(t, c, func() bool { return f.caps[11] == "Example second — ChatGPT" })
	if entry.RawName != "Example" || entry.Original != "ChatGPT" || !deadline.Equal(entry.NextBackground) || entry.Version != version || c.Epoch != sourceEpoch {
		t.Fatal("display changed source/cadence/lease")
	}
	before := calls.Load()
	for i := 0; i < 10; i++ {
		c.pollNameRules(true)
		c.maintain()
	}
	if calls.Load() != before {
		t.Fatal("unchanged repair respawned formatter")
	}
	f.caps[11] = "Manual title"
	_ = os.WriteFile(rules, []byte("third"), 0600)
	client.nextPoll = time.Time{}
	waitDisplay(t, c, func() bool { return entry.RuleEpoch == client.Epoch && strings.Contains(entry.Title, "third") })
	if f.caps[11] != "Manual title" {
		t.Fatal("manual caption overwritten")
	}
	c.restore()
	if f.caps[11] != "Manual title" {
		t.Fatal("manual caption restored over")
	}
}
func TestRuleStaleAsyncAndFallbackMemo(t *testing.T) {
	state := t.TempDir()
	rules := filepath.Join(state, "rules.json")
	_ = os.WriteFile(rules, []byte("old"), 0600)
	var calls atomic.Int32
	runner := func(ctx context.Context, _ string, _ string, b []byte, _ bool, raw string) ruleMemo {
		calls.Add(1)
		if string(b) == "old" {
			<-ctx.Done()
			return ruleMemo{"STALE", "ok"}
		}
		return ruleMemo{raw, "fallback:Fixture"}
	}
	client := newNameRuleClientAt(context.Background(), state, rules, "fake", "fake", runner)
	defer client.Close()
	c, f := protocolFixture()
	c.Rules = client
	c.apply(sourceResult{Job: c.job(f.ws[0], true), Title: "Current"})
	c.pollNameRules(true)
	_ = os.WriteFile(rules, []byte("new"), 0600)
	client.nextPoll = time.Time{}
	waitDisplay(t, c, func() bool { return f.caps[11] == "Current — ChatGPT" })
	if strings.Contains(f.caps[11], "STALE") {
		t.Fatal("stale formatter applied")
	}
	before := calls.Load()
	for i := 0; i < 20; i++ {
		c.pollNameRules(true)
	}
	if calls.Load() != before {
		t.Fatal("fallback not cached")
	}
}

func TestRuleOwnedWorkerProtocolAndDeadline(t *testing.T) {
	helper := os.Getenv("CTS_RULE_TEST_HELPER")
	if helper == "" {
		t.Skip("private owned fixture not supplied")
	}
	state := t.TempDir()
	raw := "Example 示例 😀"
	for _, mode := range []string{"pass", "fallback", "invalid"} {
		got := formatRuleWorker(context.Background(), state, helper, []byte(mode), false, raw)
		if got.Value != raw {
			t.Fatal("raw Unicode packet changed", mode)
		}
		if mode == "pass" && got.Status != "ok" {
			t.Fatal(got.Status)
		}
		if mode != "pass" && !strings.HasPrefix(got.Status, "fallback:") {
			t.Fatal(got.Status)
		}
	}
	receipt := filepath.Join(state, "owned-child-pid.txt")
	start := time.Now()
	got := formatRuleWorker(context.Background(), state, helper, []byte("DELAY|"+receipt), false, raw)
	if got.Value != raw || got.Status != "fallback:WorkerTimeout" || time.Since(start) > 2500*time.Millisecond {
		t.Fatal("owned deadline", got, time.Since(start))
	}
	if _, e := os.Stat(receipt); e != nil {
		t.Fatal("owned fixture did not execute", e)
	}
	entries, _ := os.ReadDir(state)
	for _, entry := range entries {
		if entry.IsDir() && strings.HasPrefix(entry.Name(), "title-rule-worker-") {
			t.Fatal("owned temp cleanup failed")
		}
	}
}

func TestRuleCompanionRecoveryInvalidatesOnlyDisplay(t *testing.T) {
	state := t.TempDir()
	rules := filepath.Join(state, "rules.json")
	helper := filepath.Join(state, "own-helper-fixture")
	_ = os.WriteFile(rules, []byte("unchanged"), 0600)
	runner := func(_ context.Context, _ string, h string, _ []byte, _ bool, raw string) ruleMemo {
		if _, e := os.Stat(h); e != nil {
			return ruleMemo{raw, "fallback:MissingHelper"}
		}
		return ruleMemo{raw + " formatted", "ok"}
	}
	client := newNameRuleClientAt(context.Background(), state, rules, helper, "", runner)
	defer client.Close()
	c, f := protocolFixture()
	c.Rules = client
	w := f.ws[0]
	c.apply(sourceResult{Job: c.job(w, true), Title: "Example"})
	waitDisplay(t, c, func() bool { return f.caps[11] == "Example — ChatGPT" })
	e := c.Entries[w.Key()]
	deadline, version, sourceEpoch, displayEpoch := e.NextBackground, e.Version, c.Epoch, client.Epoch
	_ = os.WriteFile(helper, []byte("owned fake helper"), 0600)
	client.nextPoll = time.Time{}
	waitDisplay(t, c, func() bool { return f.caps[11] == "Example formatted — ChatGPT" })
	if client.Epoch <= displayEpoch || c.Epoch != sourceEpoch || e.Version != version || !e.NextBackground.Equal(deadline) || e.RawName != "Example" || e.Original != "ChatGPT" {
		t.Fatal("companion recovery altered source scheduling/raw/lease")
	}
}
