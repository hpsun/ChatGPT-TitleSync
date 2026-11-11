# Known issues and verification limits

[简体中文](KNOWN_ISSUES.zh-CN.md) · [HTML](KNOWN_ISSUES.html) · [Changelog](CHANGELOG.md) · [Support matrix](support-matrix.md)

Snapshot: **2026-11-11, Beijing time**, at initial publication preparation. Fixed problems belong in the [changelog](CHANGELOG.md); the entries below remain limitations or unverified targets. They are not fabricated GitHub issues. Actual issue/commit links should be added after those records exist.

<a id="event-only-monitoring-is-not-implemented"></a>
## Event-only monitoring is not implemented

A bounded Windows trial attached once to one document's `NameProperty` with `TreeScope.Element`. Two source changes were independently confirmed, but no property callbacks were received during the 60-second run. Native foreground and object-name metadata events did arrive; those events can also reflect the formatter's own caption writes and were not established as reliable conversation-change notifications.

The trial did not subscribe to header text or rebind a replaced document/provider. It does **not** establish that every event route is unusable. Production keeps foreground source reads at the configurable **2-second default**, background sources at **5 seconds per window**, and native cached-caption repair at **1 second**. Event acceleration needs a separate reliability and self-write-feedback experiment before replacing any fallback.

## macOS is Experimental, not native-verified

All four Mac branches remain unverified on an actual Mac: **Swift, Objective-C, Go/Darwin and Rust/macOS**. The native menu drafts and public AppleScriptObjC companion received source review; Windows-side models are not Mac SDK, AX permission/provider, writable-title, focus, packaging or timing acceptance. A real Mac build and targeted runtime tests are required. See the [Mac guide](macos/README.md).

## AutoHotkey Basic has no accepted compiled EXE

The validated route is source with **AutoHotkey Basic 1.0.48.05 ANSI x86**. Legacy compiler attempts failed or timed out; resulting crash/timeout remnants are not delivery artifacts. Source/runtime/IPC paths and tray labels retain the branch's ASCII restrictions, even though native title buffers support UTF-16. Do not substitute a modern Unicode runtime/base and claim Basic compatibility. See the [Basic guide](windows/ahk-v1.0/README.md).

## Timing and UI coverage are limited

- Nine Windows runtime routes passed targeted settings/source/reset/normal-exit checks, reusing the same three existing windows. This is not a long-term reliability test, comparative benchmark, complete installer test or all-version guarantee.
- Settings/menu handlers were exercised through bound native commands. A physical Windows shell right-click and every taskbar arrangement were not independently verified for every branch.
- A configured source interval is a scheduling interval, not a promise that a cold UIA read or every item in a serial background queue finishes within that period.
- A changed or unavailable accessibility layout can prevent a bounded source read. The program should decline that read rather than guess from the sidebar or scan the conversation body. Provider/version compatibility still needs wider testing.
- The Python acceptance record retains two guard-skipped reset attempts and an earlier unexplained settings readback. Those were not rewritten as product failures. Independent later checks confirmed the final reset path and exact persisted/reopened settings; the original diagnostic evidence stays private.

See the [support matrix](support-matrix.md) for exact scope and individual observations.

## Remote CI must be observed after publication

At this documentation freeze, the Windows and Experimental macOS workflows had not run remotely. Local passes are not a passing GitHub Actions result. After the first push, inspect the actual runs and record failures and fixes in the real issues/commits; do not add a passing badge or native-Mac claim in advance.

## Reporting a new problem

Include the implementation/runtime, OS and app version, minimal reproduction, expected behavior and actual behavior. State whether the issue is a title-source failure, a native caption write, a settings save or a window-visibility problem. Sanitize diagnostics before attaching them: runtime caches, raw logs and screenshots can contain conversation names, machine paths or account details. Do not upload those private artifacts unchanged.
