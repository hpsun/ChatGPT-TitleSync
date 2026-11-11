# Support and verification matrix

[简体中文](support-matrix.zh-CN.md) · [Machine-readable status](support-matrix.json) · [Project home](README.md)

Snapshot: 2026-11-11, Beijing time. User explicitly approved publication on 2026-11-11; normal repository-file publication is in progress. Earlier unpublished/approval-pending snapshots are historical. No project ZIP is uploaded and startup defaults on at current-user sign-in. Selected icon: 45. Eight languages, with three AHK runtimes listed separately.


Current default-on startup sources are under fresh real Windows retesting; do not treat earlier nine-runtime timing/settings results as acceptance of this new revision. See the [startup contract](docs/startup.md). Mac startup is source-only Experimental.
## Current source status

## Current candidate verification

The current branding, startup and eight-theme sources passed the controlled checks below. Final targeted real-window retesting across nine Windows runtime cases remains in progress. C# named all three existing windows, but one independent four-second cold probe timed out; that strict case is not counted as passed. The candidate exited normally and original state was restored. Earlier live results do not substitute for this run.

| Implementation | Current controlled evidence |
| --- | --- |
| C# | 37 theme + 22 startup; modeless Cancel verified |
| AHK Basic | 30 theme + 14 startup + 6 settings; source-only |
| AHK v1.1 / v2 | Each: 30 theme + 14 startup + 11 settings; seven embedded frames |
| PowerShell 5.1 / 7 | Each: 37 theme callback/transaction checks |
| Python | 35 theme + 14 startup + 17 settings; 18 public pure theme tests |
| Go / Rust | 51 / 43 controlled checks; owned binary self-tests; seven embedded frames |
| Swift / Objective-C / Go macOS / Rust macOS | Experimental source; no native Mac build or runtime result |

## Earlier revision record

The measurements below are retained for the earlier source revision; previous hashes and checks are recorded under previous_revision in JSON. They are not acceptance of all current changes.

| Implementation | Target | Current evidence and limits |
| --- | --- | --- |
| [C#](windows/csharp/README.md) | Windows | 41 policy + 13 helper/Job + 8 interval protocol + 12 settings and hidden-startup checks; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1384ms, BG 781ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [AutoHotkey v1.0 Basic](windows/ahk-v1.0/README.md) | Windows | Basic 1.0.48.05 ANSI x86 source-only; no accepted Basic EXE. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1098ms, BG 632ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [AutoHotkey v1.1](windows/ahk-v1.1/README.md) | Windows | Current x64 package; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 2247ms, BG 667ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [AutoHotkey v2](windows/ahk-v2/README.md) | Windows | Current x64 package; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1056ms, BG 409ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [PowerShell](windows/powershell/README.md) | Windows | PowerShell 5.1/7 targeted cases passed: 2/5 settings, save/reopen/restore, source/header/native agreement, FG reset 881/342ms, BG reset 794/282ms, three generic captions after each normal exit. Controlled 32+9 checks per host and hidden-startup regression remain separate. |
| [Python](windows/python/README.md) | Windows | Final executable passed source/header and later native-title agreement, FG reset 161ms, BG reset 379ms and three generic captions after exit. Two earlier guards skipped injection, not product failures. Settings recheck independently proved persisted/reopened 7/17 and restored 2/5 in one process; the earlier 33/10 ambiguity is preserved without a product-defect conclusion. No Mac validation. |
| [Swift](macos/README.md) | macOS | Native three-layer/menu-settings source draft with independent UserDefaults suite and live generation reset. Static review only; no Mac SDK build, preferences-runtime, real AX or GUI acceptance. |
| [Objective-C](macos/README.md) | macOS | Native three-layer/menu-settings source draft with independent UserDefaults suite and live generation reset. Static review only; no Mac SDK build, preferences-runtime, real AX or GUI acceptance. |
| [Rust](rust/README.md) | Windows / macOS | 30 controlled checks; Windows x64 native tray. Mac companion Experimental/uncompiled. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1018ms, BG 624ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [Go](go/README.md) | Windows / macOS | 38 controlled checks; Windows x64 native tray. Mac companion Experimental/uncompiled. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1784ms, BG 448ms; three original generic captions after normal exit. Single observations, not a benchmark. |

## Protocol and interpretation

Native identity/caption checks: every second. Foreground fresh source default: 2 seconds. Background source default: 5 seconds per window, one serial worker. The foreground never substitutes cached source; a background generic reset can use a same-identity verified cache immediately. Protect non-generic external captions. Scheduling is not a cold-reader completion guarantee.

Historical checks are retained separately in JSON with their revision scope. They do not prove the current source's real window-switch, long-running, installation or taskbar effects. Shared Mac models are not counted as native tests or multiplied per language. Every Mac backend remains Experimental: no Mac compilation/AX acceptance. Remote CI has not run.

C#, AHK, PowerShell, Python, Go and Rust now have Windows tray/settings source. Actual menu acceptance is recorded separately per branch. Go/Rust retain an optional CLI and use the public osascript companion for their Experimental Mac menu. Swift/Objective-C native menus and all Mac backends remain uncompiled/AX-unverified. Basic retains ASCII launch/runtime/IPC and ANSI-x86 restrictions despite binary UTF-16 title handling.

See [guide requirements](docs/guides-index.md) and [local validation](docs/release-readiness.md#local-validation). Raw reports, caches, actual titles and identities are private and excluded from source delivery. [source-sha256.txt](source-sha256.txt) records the final frozen source/build/workflow/test hashes. Caption labels do not alter Windows app grouping or the macOS Dock application name.

A separate controlled case fixed restoration after a window becomes hidden. The integrated timings above preceded that guard; foreground and native-caption maintenance paths were unchanged.

With a 15-second background setting, worker-attempt gaps across three windows were about 15.16s, 15.17s and 22.20s. Serial reading and foreground priority can delay attempts; strict per-window completion every 15 seconds is not promised. Normal --stop left no standalone process or owned foreground/background helper; original configuration bytes and conversation were restored. Timing samples preceded the hidden-lease guard; their timing paths were unchanged, and the final EXE includes that controlled fix. These are limited observations, not latency guarantees.
