# Known issues and verification limits

[简体中文](KNOWN_ISSUES.zh-CN.md) · [HTML](KNOWN_ISSUES.html) · [Changelog](CHANGELOG.md) · [Support matrix](support-matrix.md)

Snapshot: **2026-11-12, Beijing time**. The development tree remains **0.1.0**, with **0.2.0** as the next target. This work has no release candidate or new Release; the existing public v0.1.0 preview does not deliver these unreleased changes. Historical observations retain their original revision scope; fixed problems belong in the [changelog](CHANGELOG.md).

<a id="format-worker-deadline-under-load"></a>
## Formatter deadline and cached fallback under load

**Windows load boundary:** the owned formatting worker keeps its **1.5-second** deadline. Under load or slow startup it can time out and return the entire raw name plus the **default suffix**, so a saved `false` may not yet take effect. This failure is cached by raw name plus rules/helper identity; unchanged ticks do not retry it. Save the rules again, replace/change the helper identity, restart the monitor, or observe a different raw name to refresh that cache. The same isolated case succeeded in both PowerShell 5.1 and 7 when retested individually under lower load; earlier WorkerTimeout attempts remain evidence. This is not an unconditional pass or a promise of complete UI response within 1.5 seconds.

The shared editor's **Append — ChatGPT / 标题末尾显示ChatGPT** checkbox is checked by default and applies on **Save**. It is independent of **Enable name replacement** and row switches: empty or disabled replacement rules can still omit the program-added suffix. The optional shared JSON boolean `append_chatgpt_suffix` defaults to `true` when absent; it is not part of scan, icon or startup preferences.

See [complete-caption bounds](docs/name-replacement.md#caption-protocol). Raw/original restoration and manual-caption protection are unchanged.

## One-shot settings limitation

Python, AHK Basic1.0, AHK1.1 and AHK2 currently skip their rules client in `--once`, ignoring both saved replacements and suffix-off. They use raw plus the default suffix. This is a product limitation, not a claim that legacy API compatibility makes the saved option effective.

<a id="event-only-monitoring-is-not-implemented"></a>
## Event-only monitoring is not implemented

A bounded Windows trial attached once to one document's `NameProperty` with `TreeScope.Element`. Two source changes were independently confirmed, but no property callbacks were received during the 60-second run. Native foreground and object-name metadata events did arrive; those events can also reflect the formatter's own caption writes and were not established as reliable conversation-change notifications.

The trial did not subscribe to header text or rebind a replaced document/provider. It does **not** establish that every event route is unusable. Production keeps foreground source reads at the configurable **2-second default**, background sources at **5 seconds per window**, and native cached-caption repair at **1 second**. Event acceleration needs a separate reliability and self-write-feedback experiment before replacing any fallback.

## macOS is Experimental, not native-verified

At [Mac CI checkpoint `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229), all **four native language builds** (Swift, Objective-C, Go and Rust), the **31 common formatter cases**, **five file-I/O cases** and **three client-recovery cases** passed. Shared AppleScript compilation still failed at reported location `:64` around variable `application` with error **-10003**; a minimal variable correction is prepared and awaits actual CI verification. The newer suffix revision's **46 common cases and seven client cases** require another native integration CI run and are **not covered by this checkpoint**. Real ChatGPT AX/title writes, editor/menu GUI and login behavior remain unverified; all Mac routes remain Experimental.

The following statement is retained from the initial pre-CI freeze, not the current SDK status:

> All four Mac branches remain unverified on an actual Mac: **Swift, Objective-C, Go/Darwin and Rust/macOS**. The native menu drafts and public AppleScriptObjC companion received source review; Windows-side models are not Mac SDK, AX permission/provider, writable-title, focus, packaging or timing acceptance. A real Mac build and targeted runtime tests are required. See the [Mac guide](macos/README.md).

## AutoHotkey Basic has no accepted compiled EXE

The validated route is source with **AutoHotkey Basic 1.0.48.05 ANSI x86**. Legacy compiler attempts failed or timed out; resulting crash/timeout remnants are not delivery artifacts. Source/runtime/IPC paths and tray labels retain the branch's ASCII restrictions, even though native title buffers support UTF-16. Do not substitute a modern Unicode runtime/base and claim Basic compatibility. See the [Basic guide](windows/ahk-v1.0/README.md).

## Timing and UI coverage are limited

- At an earlier source revision, nine Windows runtime routes passed targeted settings/source/reset/normal-exit checks, reusing the same three existing windows. This is not a long-term reliability test, comparative benchmark, complete installer test or all-version guarantee.
- Settings/menu handlers were exercised through bound native commands. A physical Windows shell right-click and every taskbar arrangement were not independently verified for every branch.
- A configured source interval is a scheduling interval, not a promise that a cold UIA read or every item in a serial background queue finishes within that period.
- A changed or unavailable accessibility layout can prevent a bounded source read. The program should decline that read rather than guess from the sidebar or scan the conversation body. Provider/version compatibility still needs wider testing.
- The Python acceptance record retains two guard-skipped reset attempts and an earlier unexplained settings readback. Those were not rewritten as product failures. Independent later checks confirmed the final reset path and exact persisted/reopened settings; the original diagnostic evidence stays private.

See the [support matrix](support-matrix.md) for exact scope and individual observations.

## Remote CI must be observed after publication

At [Mac CI checkpoint `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229), all **four native language builds** (Swift, Objective-C, Go and Rust), the **31 common formatter cases**, **five file-I/O cases** and **three client-recovery cases** passed. Shared AppleScript compilation still failed at reported location `:64` around variable `application` with error **-10003**; a minimal variable correction is prepared and awaits actual CI verification. The newer suffix revision's **46 common cases and seven client cases** require another native integration CI run and are **not covered by this checkpoint**. Real ChatGPT AX/title writes, editor/menu GUI and login behavior remain unverified; all Mac routes remain Experimental.

Retained initial-publication statement (historical, superseded for compilation scope):

> At this documentation freeze, the Windows and Experimental macOS workflows had not run remotely. Local passes are not a passing GitHub Actions result. After the first push, inspect the actual runs and record failures and fixes in the real issues/commits; do not add a passing badge or native-Mac claim in advance.

## Reporting a new problem

Include the implementation/runtime, OS and app version, minimal reproduction, expected behavior and actual behavior. State whether the issue is a title-source failure, a native caption write, a settings save or a window-visibility problem. Sanitize diagnostics before attaching them: runtime caches, raw logs and screenshots can contain conversation names, machine paths or account details. Do not upload those private artifacts unchanged.
