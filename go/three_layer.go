package main

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"
)

// All cache/native decisions run on the controller. Source workers never hold its state.
type cachedTitle struct {
	W                                                   Window
	Title, LastWritten, Original                        string
	RawName                                             string
	RuleEpoch                                           uint64
	PendingDisplay, PendingForeground, NeedsFreshSource bool
	PendingVersion                                      uint64
	Own                                                 bool
	Version                                             uint64
	NextBackground                                      time.Time
	Pending                                             uint64
}
type sourceJob struct {
	W                  Window
	Foreground         bool
	Version, ID, Epoch uint64
}
type sourceResult struct {
	Job   sourceJob
	Title string
	Err   error
}
type titleCache struct {
	B             Backend
	Entries       map[string]*cachedTitle
	ReadOnly      bool
	Clock         func() time.Time
	Background    time.Duration
	Rules         *nameRuleClient
	nextID, Epoch uint64
}

func newTitleCache(b Backend, ro bool, bg time.Duration) *titleCache {
	return &titleCache{B: b, Entries: map[string]*cachedTitle{}, ReadOnly: ro, Clock: time.Now, Background: bg}
}
func (c *titleCache) remember(w Window) *cachedTitle {
	key := w.Key()
	e := c.Entries[key]
	if e == nil {
		e = &cachedTitle{W: w}
		c.Entries[key] = e
	}
	return e
}
func (c *titleCache) job(w Window, fg bool) sourceJob {
	e := c.remember(w)
	c.nextID++
	return sourceJob{w, fg, e.Version, c.nextID, c.Epoch}
}
func (c *titleCache) maintain() {
	for key, e := range c.Entries {
		if !c.B.Same(e.W) {
			delete(c.Entries, key)
			continue
		}
		if (c.Rules != nil && (e.PendingDisplay || e.NeedsFreshSource || e.RuleEpoch != c.Rules.Epoch)) || e.Title == "" || c.B.Active(e.W) {
			continue
		}
		current, err := c.B.Caption(e.W)
		if err != nil {
			continue
		}
		if current == e.Title {
			e.LastWritten = e.Title
			continue
		}
		if !genericCaption(current) {
			e.Own = false
			e.Original = ""
			e.LastWritten = ""
			continue
		}
		if c.ReadOnly || c.B.Active(e.W) {
			continue
		}
		if setInactive(c.B, e.W, current, e.Title) == nil {
			// A focus change during the native write must not replay a cache into the foreground.
			if c.B.Active(e.W) {
				_ = c.B.Set(e.W, e.Title, current)
				continue
			}
			if !e.Own {
				e.Original = current
			}
			e.Own = true
			e.LastWritten = e.Title
		}
	}
}
func (c *titleCache) foregroundJob() (sourceJob, bool) {
	ws, err := c.B.List()
	if err != nil {
		return sourceJob{}, false
	}
	for _, w := range ws {
		if c.B.Active(w) && c.B.Same(w) {
			return c.job(w, true), true
		}
	}
	return sourceJob{}, false
}
func (c *titleCache) backgroundJobs() []sourceJob {
	keys := make([]string, 0, len(c.Entries))
	for k := range c.Entries {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := []sourceJob{}
	for _, k := range keys {
		e := c.Entries[k]
		if e.Pending != 0 || c.Clock().Before(e.NextBackground) || c.B.Active(e.W) || !c.B.Same(e.W) {
			continue
		}
		j := c.job(e.W, false)
		e.Pending = j.ID
		out = append(out, j)
	}
	return out
}
func (c *titleCache) apply(r sourceResult) {
	if r.Job.Epoch != c.Epoch {
		return
	}
	e := c.Entries[r.Job.W.Key()]
	if e == nil || !c.B.Same(r.Job.W) {
		delete(c.Entries, r.Job.W.Key())
		return
	}
	if !r.Job.Foreground {
		if e.Pending == r.Job.ID {
			e.Pending = 0
		}
		e.NextBackground = c.Clock().Add(c.Background)
	}
	if r.Err != nil {
		return
	}
	if r.Job.Foreground {
		if !c.B.Active(r.Job.W) {
			return
		}
	} else if c.B.Active(r.Job.W) || e.Version != r.Job.Version {
		return
	}
	raw, err := cleanName(r.Title)
	if err != nil {
		return
	}
	current, err := c.B.Caption(e.W)
	if err != nil || !c.B.Same(e.W) || (r.Job.Foreground && !c.B.Active(e.W)) {
		return
	}
	e.Version++
	e.NextBackground = c.Clock().Add(c.Background)
	e.NeedsFreshSource = false
	if genericCaption(raw) {
		e.RawName = ""
		e.PendingDisplay = false
		e.Title = ""
		if e.Own && current == e.LastWritten && !c.ReadOnly {
			_ = c.B.Set(e.W, current, e.Original)
		}
		e.Own = false
		e.LastWritten = ""
		e.Original = ""
		return
	}
	e.RawName = raw
	e.PendingDisplay = true
	e.PendingForeground = r.Job.Foreground
	e.PendingVersion = e.Version
	e.RuleEpoch = 0
	c.resolveSourceDisplay(e)
}
func (c *titleCache) resolveSourceDisplay(e *cachedTitle) {
	if !e.PendingDisplay {
		return
	}
	display, ready := e.RawName, true
	if c.Rules != nil {
		display, ready = c.Rules.Display(e.RawName)
	}
	if !ready {
		return
	}
	e.PendingDisplay = false
	if e.PendingVersion != e.Version || !c.B.Same(e.W) || c.B.Active(e.W) != e.PendingForeground {
		e.NeedsFreshSource = true
		return
	}
	c.writeDisplay(e, display, e.PendingForeground, false)
}
func (c *titleCache) pollNameRules(write bool) {
	if c.Rules == nil {
		return
	}
	names := []string{}
	for _, e := range c.Entries {
		if e.RawName != "" {
			names = append(names, e.RawName)
		}
	}
	keys := []string{}
	for key := range c.Entries {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	c.Rules.SourceSetKey = strings.Join(keys, "\x00")
	c.Rules.Poll(names)
	if !write {
		return
	}
	for _, e := range c.Entries {
		if e.RawName == "" || e.NeedsFreshSource {
			continue
		}
		if e.PendingDisplay {
			c.resolveSourceDisplay(e)
			continue
		}
		if e.RuleEpoch != c.Rules.Epoch {
			value, ready := c.Rules.Display(e.RawName)
			if ready {
				c.writeDisplay(e, value, c.B.Active(e.W), true)
			}
		}
	}
}
func (c *titleCache) writeDisplay(e *cachedTitle, value string, foreground, ownedOnly bool) {
	if !c.B.Same(e.W) || c.B.Active(e.W) != foreground {
		return
	}
	current, err := c.B.Caption(e.W)
	if err != nil || !c.B.Same(e.W) {
		return
	}
	desired := value
	if !strings.HasSuffix(desired, " — ChatGPT") {
		desired += " — ChatGPT"
	}
	previous := e.LastWritten
	e.Title = desired
	if c.Rules != nil {
		e.RuleEpoch = c.Rules.Epoch
	}
	if current == desired {
		e.LastWritten = desired
		return
	}
	if ownedOnly && (!e.Own || current != previous) {
		return
	}
	if !genericCaption(current) && (previous == "" || current != previous) {
		e.Own = false
		e.Original = ""
		e.LastWritten = ""
		return
	}
	if c.ReadOnly {
		return
	}
	if foreground {
		if !c.B.Active(e.W) {
			return
		}
		err = c.B.SetActive(e.W, current, desired)
	} else {
		if c.B.Active(e.W) {
			return
		}
		err = setInactive(c.B, e.W, current, desired)
		if err == nil && c.B.Active(e.W) {
			_ = c.B.Set(e.W, desired, current)
			err = errors.New("focus-changed")
		}
	}
	if err == nil {
		if !e.Own {
			e.Original = current
		}
		e.Own = true
		e.LastWritten = desired
	}
}
func (c *titleCache) restore() {
	for _, e := range c.Entries {
		if e.Own && c.B.Same(e.W) {
			if current, err := c.B.Caption(e.W); err == nil && current == e.LastWritten {
				_ = c.B.Set(e.W, current, e.Original)
			}
		}
		e.Own = false
	}
}

type sourceFunctions struct {
	Read     func(context.Context, Window, bool) (string, error)
	Discover func() ([]Window, error)
	Settings func() (time.Duration, time.Duration)
}
type discoveryResult struct {
	Windows []Window
	Err     error
}

func runThreeLayer(ctx context.Context, c *titleCache, interval time.Duration, fn sourceFunctions, paused func() bool) {
	childCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	fgIn, bgIn := make(chan sourceJob), make(chan sourceJob)
	results := make(chan sourceResult, 4)
	discovered := make(chan discoveryResult, 1)
	done := make(chan struct{}, 2)
	initialBackground := c.Background
	worker := func(input <-chan sourceJob, discovery bool) {
		defer func() { done <- struct{}{} }()
		var discoverTick <-chan time.Time
		var timer *time.Ticker
		nextDiscovery := time.Now()
		lastPeriod := initialBackground
		if discovery {
			var ws []Window
			var e error
			if !paused() {
				ws, e = fn.Discover()
			}
			select {
			case discovered <- discoveryResult{ws, e}:
			case <-childCtx.Done():
				return
			}
			timer = time.NewTicker(100 * time.Millisecond)
			nextDiscovery = time.Now().Add(lastPeriod)
			defer timer.Stop()
			discoverTick = timer.C
		}
		for {
			select {
			case <-childCtx.Done():
				return
			case <-discoverTick:
				period := lastPeriod
				if fn.Settings != nil {
					_, period = fn.Settings()
				}
				if period != lastPeriod {
					lastPeriod = period
					nextDiscovery = time.Now()
				}
				if time.Now().Before(nextDiscovery) {
					continue
				}
				nextDiscovery = time.Now().Add(period)
				if paused() {
					continue
				}
				ws, e := fn.Discover()
				select {
				case discovered <- discoveryResult{ws, e}:
				case <-childCtx.Done():
					return
				}
			case job := <-input:
				var title string
				var err error
				if paused() {
					err = errors.New("paused")
				} else {
					title, err = fn.Read(childCtx, job.W, job.Foreground)
				}
				select {
				case results <- sourceResult{job, title, err}:
				case <-childCtx.Done():
					return
				}
			}
		}
	}
	go worker(fgIn, false)
	go worker(bgIn, true)
	defer func() {
		cancel()
		<-done
		<-done
		if c.Rules != nil {
			c.Rules.Close()
		}
		c.restore()
	}()
	next := time.Now()
	nextNative := next
	poll := time.NewTicker(50 * time.Millisecond)
	defer poll.Stop()
	var foreground *sourceJob
	queue := []sourceJob{}
	wasPaused := false
	for {
		var fch, bch chan sourceJob
		var fj, bj sourceJob
		if foreground != nil {
			fch = fgIn
			fj = *foreground
		}
		if len(queue) > 0 {
			bch = bgIn
			bj = queue[0]
		}
		if foreground != nil {
			select {
			case fgIn <- *foreground:
				foreground = nil
				fch = nil
			default:
			}
		}
		select {
		case <-ctx.Done():
			return
		case fch <- fj:
			foreground = nil
		case bch <- bj:
			queue = queue[1:]
		case d := <-discovered:
			if d.Err == nil {
				for _, w := range d.Windows {
					c.remember(w)
				}
			}
		case r := <-results:
			if !paused() {
				c.apply(r)
			} else {
				if e := c.Entries[r.Job.W.Key()]; e != nil && e.Pending == r.Job.ID {
					e.Pending = 0
				}
			}
		case <-poll.C:
			if fn.Settings != nil {
				fg, bg := fn.Settings()
				if fg != interval || bg != c.Background {
					interval = fg
					c.Background = bg
					c.Epoch++
					foreground = nil
					queue = nil
					next = time.Now()
					nextNative = next
					for _, e := range c.Entries {
						e.Pending = 0
						e.NextBackground = next
					}
				}
			}
			p := paused()
			c.pollNameRules(!p)
			if p {
				if !wasPaused {
					c.Epoch++
					c.restore()
				}
				wasPaused = true
				foreground = nil
				queue = nil
				continue
			}
			if wasPaused {
				next = time.Now()
				nextNative = next
				for _, e := range c.Entries {
					e.Pending = 0
				}
				wasPaused = false
			}
			if !time.Now().Before(nextNative) {
				c.maintain()
				queue = append(queue, c.backgroundJobs()...)
				nextNative = advanceDeadline(nextNative, time.Now(), time.Second)
			}
			if !time.Now().Before(next) {
				if j, ok := c.foregroundJob(); ok {
					foreground = &j
				} else {
					foreground = nil
				}
				next = advanceDeadline(next, time.Now(), interval)
			}
		}
	}
}

func setInactive(b Backend, w Window, a, c string) error {
	if x, ok := b.(interface {
		SetInactive(Window, string, string) error
	}); ok {
		return x.SetInactive(w, a, c)
	}
	if b.Active(w) {
		return errors.New("foreground")
	}
	return b.Set(w, a, c)
}
