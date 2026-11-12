package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"
)

const ruleMaxBytes = 131072
const ruleMaxUnits = 512
const ruleCaptionSuffix = " — ChatGPT"
const ruleMaxCaptionUnits = 522

type ruleMemo struct{ Value, Status string }
type ruleJob struct {
	Raw     string
	Epoch   uint64
	Rules   []byte
	Missing bool
	Context context.Context
	Helper  string
}
type ruleAnswer struct {
	Raw   string
	Epoch uint64
	Memo  ruleMemo
}

// The controller alone owns memo/epoch. Workers receive immutable raw/rule snapshots.
type nameRuleClient struct {
	RulesPath, StateDirectory, Helper, Help string
	Epoch                                   uint64
	CaptionMode                             bool
	signature                               [32]byte
	initialized, missing                    bool
	readFailure                             string
	rules                                   []byte
	memo                                    map[string]ruleMemo
	pending                                 map[string]bool
	jobs                                    chan ruleJob
	answers                                 chan ruleAnswer
	baseContext                             context.Context
	cancel                                  context.CancelFunc
	epochContext                            context.Context
	epochCancel                             context.CancelFunc
	workers                                 sync.WaitGroup
	nextPoll                                time.Time
	sources                                 []byte
	SourceSetKey, publishedSourceSetKey     string
	resolveHelper                           func() string
	runner                                  func(context.Context, string, string, []byte, bool, string) ruleMemo
}

func sharedRulesPath() string {
	if runtime.GOOS == "windows" {
		return filepath.Join(os.Getenv("LOCALAPPDATA"), "ChatGPT-TitleSync", "title-rules.json")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Application Support", "ChatGPT-TitleSync", "title-rules.json")
}
func ruleCompanionPaths(exe string) (string, string) {
	dir := filepath.Dir(exe)
	binaryName := "chatgpt-titlesync-rules"
	platform := "macos"
	if runtime.GOOS == "windows" {
		binaryName = "ChatGPT-TitleSync.Rules.exe"
		platform = "windows"
	}
	roots := []string{dir, filepath.Join(dir, "..", "shared", platform), filepath.Join(dir, "..", "..", "..", "shared", platform), filepath.Join(dir, "shared", platform)}
	helper := ""
	for _, root := range roots {
		p := filepath.Clean(filepath.Join(root, binaryName))
		if st, e := os.Stat(p); e == nil && !st.IsDir() {
			helper = p
			break
		}
	}
	help := ""
	for _, root := range []string{dir, filepath.Join(dir, ".."), filepath.Join(dir, "..", "..", "..")} {
		p := filepath.Clean(filepath.Join(root, "docs", "name-replacement.html"))
		if st, e := os.Stat(p); e == nil && !st.IsDir() {
			help = p
			break
		}
	}
	return helper, help
}
func newNameRuleClient(parent context.Context, stateDirectory string) *nameRuleClient {
	exe, _ := os.Executable()
	helper, help := ruleCompanionPaths(exe)
	c := newNameRuleClientAt(parent, stateDirectory, sharedRulesPath(), helper, help, formatCaptionRuleWorker)
	c.CaptionMode = true
	c.resolveHelper = func() string { p, _ := ruleCompanionPaths(exe); return p }
	return c
}
func newNameRuleClientAt(parent context.Context, state, rules, helper, help string, runner func(context.Context, string, string, []byte, bool, string) ruleMemo) *nameRuleClient {
	ctx, cancel := context.WithCancel(parent)
	state, _ = filepath.Abs(state)
	rules, _ = filepath.Abs(rules)
	c := &nameRuleClient{RulesPath: rules, StateDirectory: state, Helper: helper, Help: help, memo: map[string]ruleMemo{}, pending: map[string]bool{}, jobs: make(chan ruleJob, 256), answers: make(chan ruleAnswer, 512), baseContext: ctx, cancel: cancel, runner: runner}
	c.epochContext, c.epochCancel = context.WithCancel(ctx)
	for i := 0; i < 4; i++ {
		c.workers.Add(1)
		go func() {
			defer c.workers.Done()
			for {
				select {
				case <-ctx.Done():
					return
				case job := <-c.jobs:
					if job.Context.Err() != nil {
						continue
					}
					memo := runner(job.Context, state, job.Helper, job.Rules, job.Missing, job.Raw)
					select {
					case c.answers <- ruleAnswer{job.Raw, job.Epoch, memo}:
					case <-ctx.Done():
						return
					}
				}
			}
		}()
	}
	return c
}
func (c *nameRuleClient) Close() { c.epochCancel(); c.cancel(); c.workers.Wait() }
func readRuleBytes(path string) ([]byte, bool, string) {
	f, e := os.Open(path)
	if os.IsNotExist(e) {
		return nil, true, ""
	}
	if e != nil {
		return nil, false, "RulesReadError"
	}
	defer f.Close()
	b, e := io.ReadAll(io.LimitReader(f, ruleMaxBytes+1))
	if e != nil {
		return nil, false, "RulesReadError"
	}
	if len(b) > ruleMaxBytes {
		return b, false, "RulesTooLarge"
	}
	return b, false, ""
}

// Companion deployment/replacement invalidates display memo only, never source work.
func ruleHelperSignature(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return path + "|missing"
	}
	if info.IsDir() {
		return path + "|directory"
	}
	return path + "|" + info.ModTime().UTC().Format(time.RFC3339Nano) + "|" + strconv.FormatInt(info.Size(), 10)
}
func (c *nameRuleClient) Poll(rawNames []string) {
	now := time.Now()
	if !c.initialized || !now.Before(c.nextPoll) {
		if c.resolveHelper != nil {
			c.Helper = c.resolveHelper()
		}
		b, missing, failure := readRuleBytes(c.RulesPath)
		key := append([]byte(failure), b...)
		if missing {
			key = append(key, 1)
		} else {
			key = append(key, 0)
		}
		key = append(key, []byte(ruleHelperSignature(c.Helper))...)
		if c.CaptionMode {
			key = append(key, 2)
		} else {
			key = append(key, 3)
		}
		sig := sha256.Sum256(key)
		if !c.initialized || sig != c.signature {
			c.epochCancel()
			c.epochContext, c.epochCancel = context.WithCancel(c.baseContext)
			c.Epoch++
			c.signature = sig
			c.initialized = true
			c.missing = missing
			c.readFailure = failure
			c.rules = b
			c.memo = map[string]ruleMemo{}
			c.pending = map[string]bool{}
		}
		c.nextPoll = now.Add(time.Second)
	}
	for {
		select {
		case result := <-c.answers:
			if result.Epoch == c.Epoch {
				delete(c.pending, result.Raw)
				c.memo[result.Raw] = result.Memo
			}
		default:
			goto drained
		}
	}
drained:
	live := map[string]bool{}
	for _, raw := range rawNames {
		live[raw] = true
	}
	for raw := range c.memo {
		if !live[raw] {
			delete(c.memo, raw)
		}
	}
	c.publishSources(rawNames)
}
func (c *nameRuleClient) Display(raw string) (string, bool) {
	if !c.initialized {
		c.Poll([]string{raw})
	}
	if c.missing || c.readFailure != "" {
		return localRuleRaw(raw, c.CaptionMode), true
	}
	if v, ok := c.memo[raw]; ok {
		return v.Value, true
	}
	if !c.pending[raw] {
		job := ruleJob{raw, c.Epoch, append([]byte(nil), c.rules...), c.missing, c.epochContext, c.Helper}
		select {
		case c.jobs <- job:
			c.pending[raw] = true
		default:
			return localRuleRaw(raw, c.CaptionMode), true
		}
	}
	return "", false
}
func encodeRulePacket(s string) ([]byte, error) {
	if !utf8.ValidString(s) {
		return nil, errors.New("utf8")
	}
	units := utf16.Encode([]rune(s))
	if len(units) > ruleMaxUnits {
		return nil, errors.New("length")
	}
	b := make([]byte, len(units)*2)
	for i, u := range units {
		binary.LittleEndian.PutUint16(b[i*2:], u)
	}
	return b, nil
}
func decodeRulePacket(b []byte) (string, error) { return decodeRulePacketLimit(b, ruleMaxUnits) }
func decodeRulePacketLimit(b []byte, maxUnits int) (string, error) {
	if len(b)%2 != 0 || len(b) > maxUnits*2 {
		return "", errors.New("packet")
	}
	units := make([]uint16, len(b)/2)
	for i := range units {
		units[i] = binary.LittleEndian.Uint16(b[i*2:])
	}
	for i := 0; i < len(units); i++ {
		u := units[i]
		if u >= 0xd800 && u <= 0xdbff {
			if i+1 >= len(units) || units[i+1] < 0xdc00 || units[i+1] > 0xdfff {
				return "", errors.New("surrogate")
			}
			i++
		} else if u >= 0xdc00 && u <= 0xdfff {
			return "", errors.New("surrogate")
		}
	}
	return string(utf16.Decode(units)), nil
}
func validRuleDisplay(s string) bool {
	if strings.TrimSpace(s) == "" || strings.EqualFold(strings.TrimSpace(s), "ChatGPT") {
		return false
	}
	if _, e := encodeRulePacket(s); e != nil {
		return false
	}
	for _, r := range s {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

// The companion is the only suffix owner in caption mode. Body fixtures retain their API.
func localRuleRaw(raw string, caption bool) string {
	if caption && validRuleDisplay(raw) {
		return raw + ruleCaptionSuffix
	}
	return raw
}
func validRuleCaption(value string) bool {
	if len(utf16.Encode([]rune(value))) > ruleMaxCaptionUnits {
		return false
	}
	body := strings.TrimSuffix(value, ruleCaptionSuffix)
	return validRuleDisplay(body)
}
func ownedRuleCleanup(parent, dir string) {
	parent, _ = filepath.Abs(parent)
	dir, _ = filepath.Abs(dir)
	if filepath.Dir(dir) == parent && strings.HasPrefix(filepath.Base(dir), "title-rule-worker-") {
		_ = os.RemoveAll(dir)
	}
}
func boundedRuleFile(path string, limit int) ([]byte, error) {
	f, e := os.Open(path)
	if e != nil {
		return nil, e
	}
	defer f.Close()
	b, e := io.ReadAll(io.LimitReader(f, int64(limit+1)))
	if e != nil {
		return nil, e
	}
	if len(b) > limit {
		return nil, errors.New("bounded-packet")
	}
	return b, nil
}
func formatRuleWorker(parent context.Context, state, helper string, rules []byte, missing bool, raw string) ruleMemo {
	return formatRuleWorkerMode(parent, state, helper, rules, missing, raw, false)
}
func formatCaptionRuleWorker(parent context.Context, state, helper string, rules []byte, missing bool, raw string) ruleMemo {
	return formatRuleWorkerMode(parent, state, helper, rules, missing, raw, true)
}
func formatRuleWorkerMode(parent context.Context, state, helper string, rules []byte, missing bool, raw string, caption bool) ruleMemo {
	fallback := func(code string) ruleMemo { return ruleMemo{localRuleRaw(raw, caption), "fallback:" + code} }
	input, e := encodeRulePacket(raw)
	if e != nil {
		return fallback("InvalidRaw")
	}
	if helper == "" {
		return fallback("CompanionMissing")
	}
	if e = os.MkdirAll(state, 0700); e != nil {
		return fallback("WorkerIO")
	}
	dir, e := os.MkdirTemp(state, "title-rule-worker-")
	if e != nil {
		return fallback("WorkerIO")
	}
	defer ownedRuleCleanup(state, dir)
	rp, ip, op, sp := filepath.Join(dir, "rules.json"), filepath.Join(dir, "input.bin"), filepath.Join(dir, "output.bin"), filepath.Join(dir, "status.txt")
	if !missing {
		if e = os.WriteFile(rp, rules, 0600); e != nil {
			return fallback("WorkerIO")
		}
	}
	if e = os.WriteFile(ip, input, 0600); e != nil {
		return fallback("WorkerIO")
	}
	ctx, cancel := context.WithTimeout(parent, 1500*time.Millisecond)
	defer cancel()
	args := []string{"--format"}
	if caption {
		args = append(args, "--caption")
	}
	args = append(args, "--rules", rp, "--input", ip, "--output", op, "--status", sp)
	cmd := exec.CommandContext(ctx, helper, args...)
	hideChild(cmd)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	e = cmd.Run()
	if ctx.Err() != nil {
		return fallback("WorkerTimeout")
	}
	code := 0
	if e != nil {
		var exit *exec.ExitError
		if !errors.As(e, &exit) {
			return fallback("WorkerFailed")
		}
		code = exit.ExitCode()
	}
	status, e := boundedRuleFile(sp, 128)
	if e != nil || len(status) > 128 {
		return fallback("WorkerProtocol")
	}
	text := string(status)
	for _, v := range status {
		if v > 127 {
			return fallback("WorkerProtocol")
		}
	}
	text = strings.TrimSpace(text)
	limit := ruleMaxUnits
	if caption {
		limit = ruleMaxCaptionUnits
	}
	b, e := boundedRuleFile(op, limit*2)
	if e != nil {
		return fallback("WorkerProtocol")
	}
	value, e := decodeRulePacketLimit(b, limit)
	if e != nil {
		return fallback("WorkerProtocol")
	}
	if code == 2 && strings.HasPrefix(text, "fallback:") {
		if value != raw && (!caption || value != raw+ruleCaptionSuffix) {
			return fallback("WorkerProtocol")
		}
		return ruleMemo{value, text}
	}
	valid := validRuleDisplay(value)
	if caption {
		valid = validRuleCaption(value)
	}
	if code != 0 || text != "ok" || !valid {
		return fallback("WorkerProtocol")
	}
	return ruleMemo{value, "ok"}
}
func (c *nameRuleClient) publishSources(names []string) {
	ordered := []string{}
	for _, name := range names {
		if name != "" {
			if _, e := encodeRulePacket(name); e == nil {
				ordered = append(ordered, name)
			}
		}
	}
	sort.Strings(ordered)
	b := []byte{'C', 'T', 'S', '1', 0, 0, 0, 0}
	count := uint32(0)
	for _, s := range ordered {
		p, _ := encodeRulePacket(s)
		if count >= 128 || len(b)+4+len(p) > ruleMaxBytes {
			break
		}
		var n [4]byte
		binary.LittleEndian.PutUint32(n[:], uint32(len(p)/2))
		b = append(b, n[:]...)
		b = append(b, p...)
		count++
	}
	binary.LittleEndian.PutUint32(b[4:], count)
	if bytes.Equal(c.sources, b) && c.SourceSetKey == c.publishedSourceSetKey {
		return
	}
	if e := os.MkdirAll(c.StateDirectory, 0700); e != nil {
		return
	}
	target := filepath.Join(c.StateDirectory, "title-rule-sources.bin")
	f, e := os.CreateTemp(c.StateDirectory, "title-rule-sources-*.tmp")
	if e != nil {
		return
	}
	temp := f.Name()
	if _, e = f.Write(b); e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e == nil {
		e = ce
	}
	if e == nil {
		e = os.Rename(temp, target)
	}
	_ = os.Remove(temp)
	if e == nil {
		c.sources = append([]byte(nil), b...)
		c.publishedSourceSetKey = c.SourceSetKey
	}
}
func openNameRuleEditor(state string) error {
	state, _ = filepath.Abs(state)
	exe, e := os.Executable()
	if e != nil {
		return e
	}
	helper, help := ruleCompanionPaths(exe)
	if helper == "" || help == "" {
		return errors.New("packaged name-replacement companion/help is unavailable")
	}
	cmd := exec.Command(helper, "--edit", "--rules", sharedRulesPath(), "--sources", filepath.Join(state, "title-rule-sources.bin"), "--help", help)
	if e = cmd.Start(); e != nil {
		return e
	}
	go func() { _ = cmd.Wait() }()
	return nil
}
