# Support and verification matrix

[简体中文](support-matrix.zh-CN.md) · [Machine-readable status](support-matrix.json) · [Project home](README.md)

Snapshot:2026-11-12, Beijing time. The development tree remains **0.1.0**, with **0.2.0** as the next target. This work has no release candidate or new Release; the existing public v0.1.0 preview does not deliver these unreleased changes. Sign-in startup defaults on; icon baseline remains45; no project ZIP is uploaded.

## Current source status

The shared editor's **Append — ChatGPT / 标题末尾显示ChatGPT** checkbox is checked by default and applies on **Save**. It is independent of **Enable name replacement** and row switches: empty or disabled replacement rules can still omit the program-added suffix. The optional shared JSON boolean `append_chatgpt_suffix` defaults to `true` when absent; it is not part of scan, icon or startup preferences.

Empty-by-default plain/regex replacement uses the shared OS companion. Raw/original leases, manual-title guards and2/1/5-second source/native/background defaults remain separate. See [caption protocol and bounds](docs/name-replacement.md#caption-protocol).

## Current candidate verification

The table covers controlled feature checks, not current normal-resident/ChatGPT desktop acceptance. Counts from overlapping sets and subcases are not summed.

| Component | Current evidence | Scope |
| --- | --- | --- |
| Windows common CLI |46/46:31 body + 15 caption |One shared suite, not multiplied by language. |
| Windows helper-specific suite |37 cases:22 retained body + 15 caption |Overlaps the common46; never add both totals. |
| C# / shared editor |10 display checks;13 never-shown editor checks |Owned fictional state/controls, no normal ChatGPT GUI. |
| PowerShell5.1 /7 |Same suffix-off case succeeded individually under lower load |Earlier WorkerTimeout/default-suffix-cache attempts remain; no unconditional pass. |
| Python |23 unit tests +14 private actual-helper checks |Owned files/processes and simulated ownership. |
| AHK Basic /1.1 /2 |17 caption checks per branch; old body fixtures23/19/19 |Basic remains source-only; fake native state, no normal desktop. |
| Go / Rust |20 top-level /21 test functions; a nine-case CLI matrix is inside one test |Windows controlled tests/builds; new suffix-native Mac CI pending. |
| Mac pre-suffix checkpoint1b7c33b |Four native builds;31 common CLI,5 I/O,3 recovery |No AX/GUI/login acceptance; newer suffix 46/client 7 needs its own CI. |

**Windows load boundary:** the owned formatting worker keeps its **1.5-second** deadline. Under load or slow startup it can time out and return the entire raw name plus the **default suffix**, so a saved `false` may not yet take effect. This failure is cached by raw name plus rules/helper identity; unchanged ticks do not retry it. Save the rules again, replace/change the helper identity, restart the monitor, or observe a different raw name to refresh that cache. The same isolated case succeeded in both PowerShell 5.1 and 7 when retested individually under lower load; earlier WorkerTimeout attempts remain evidence. This is not an unconditional pass or a promise of complete UI response within 1.5 seconds.

### Verified remote checkpoint —1b7c33b

At [Mac CI checkpoint `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229), all **four native language builds** (Swift, Objective-C, Go and Rust), the **31 common formatter cases**, **five file-I/O cases** and **three client-recovery cases** passed. Shared AppleScript compilation still failed at reported location `:64` around variable `application` with error **-10003**; a minimal variable correction is prepared and awaits actual CI verification. The newer suffix revision's **46 common cases and seven client cases** require another native integration CI run and are **not covered by this checkpoint**. Real ChatGPT AX/title writes, editor/menu GUI and login behavior remain unverified; all Mac routes remain Experimental.

### Historical earlier remote checkpoint

The following retained paragraphs describe the earlier checkpoint's then-current/pending state; current evidence is above.

[CI run 43124672990](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43124672990), commit `19cec8080908a15f0d0a8ccefa66209cb207bf71`, actually compiled the shared Foundation helper and the new Swift/Objective-C RulesClient integrations, and passed the **same 30 shared format-CLI cases**. Those 30 are one shared suite, not 30 additional tests per language. AppleScript compilation failed in that run. Go/Rust still used their older baseline adapters there, so that CI result does not validate their new name-replacement adapters.

The current helper adds paired-surrogate output validation and bounded I/O error classification; the current AppleScript fixes the subsequently reported `launch` selector token. Those revisions, the 31st common case and the updated client recovery logic need fresh CI evidence. Native Mac AX reads, menu interactions, the AppKit editor, login startup, long-running behavior and real title restoration remain unaccepted. All Mac routes remain **Experimental**, even where compilation and CLI tests have passed.

## Historical theme/startup candidate checks

These counts describe the earlier branding/startup/eight-theme candidate, not the current name-replacement feature. At an earlier retest checkpoint C# named all three existing windows, while one independent four-second cold probe timed out; that strict case was not counted as passed, and the candidate exited normally with state restored. That observation is preserved as historical evidence rather than a current status claim.

| Implementation | Earlier controlled evidence |
| --- | --- |
| C# | 37 theme + 22 startup; modeless Cancel verified |
| AHK Basic | 30 theme + 14 startup + 6 settings; source-only |
| AHK v1.1 / v2 | Each: 30 theme + 14 startup + 11 settings; seven embedded frames |
| PowerShell 5.1 / 7 | Each: 37 theme callback/transaction checks |
| Python | 35 theme + 14 startup + 17 settings; 18 public pure theme tests |
| Go / Rust | 51 / 43 controlled checks; owned binary self-tests; seven embedded frames |
| Mac implementations at that source freeze | Static/source review only; later actual compilation evidence is the separate checkpoint above |

## Earlier revision record

The measurements below are retained for the earlier source revision; previous hashes and checks are recorded under previous_revision in JSON. They are not acceptance of all current changes.

| Implementation | Target | Earlier evidence and limits |
| --- | --- | --- |
| [C#](windows/csharp/README.md) | Windows | 41 policy + 13 helper/Job + 8 interval protocol + 12 settings and hidden-startup checks; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1384ms, BG 781ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [AutoHotkey v1.0 Basic](windows/ahk-v1.0/README.md) | Windows | Basic 1.0.48.05 ANSI x86 source-only; no accepted Basic EXE. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1098ms, BG 632ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [AutoHotkey v1.1](windows/ahk-v1.1/README.md) | Windows | The x64 package at that revision; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 2247ms, BG 667ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [AutoHotkey v2](windows/ahk-v2/README.md) | Windows | The x64 package at that revision; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1056ms, BG 409ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [PowerShell](windows/powershell/README.md) | Windows | PowerShell 5.1/7 targeted cases passed: 2/5 settings, save/reopen/restore, source/header/native agreement, FG reset 881/342ms, BG reset 794/282ms, three generic captions after each normal exit. Controlled 32+9 checks per host and hidden-startup regression remain separate. |
| [Python](windows/python/README.md) | Windows | Final executable passed source/header and later native-title agreement, FG reset 161ms, BG reset 379ms and three generic captions after exit. Two earlier guards skipped injection, not product failures. Settings recheck independently proved persisted/reopened 7/17 and restored 2/5 in one process; the earlier 33/10 ambiguity is preserved without a product-defect conclusion. No Mac validation. |
| [Swift](macos/README.md) | macOS | Native three-layer/menu-settings source draft with independent UserDefaults suite and live generation reset. At that earlier freeze: static review only, without Mac SDK build, preferences-runtime, real AX or GUI acceptance. Later CI compilation is recorded separately above. |
| [Objective-C](macos/README.md) | macOS | Native three-layer/menu-settings source draft with independent UserDefaults suite and live generation reset. At that earlier freeze: static review only, without Mac SDK build, preferences-runtime, real AX or GUI acceptance. Later CI compilation is recorded separately above. |
| [Rust](rust/README.md) | Windows / macOS | 30 controlled checks; Windows x64 native tray. Mac companion was Experimental/uncompiled at that earlier freeze; later CI scope is recorded above. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1018ms, BG 624ms; three original generic captions after normal exit. Single observations, not a benchmark. |
| [Go](go/README.md) | Windows / macOS | 38 controlled checks; Windows x64 native tray. Mac companion was Experimental/uncompiled at that earlier freeze; later CI scope is recorded above. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1784ms, BG 448ms; three original generic captions after normal exit. Single observations, not a benchmark. |

## Protocol and interpretation

Native identity/caption checks: every second. Foreground fresh source default: 2 seconds. Background source default: 5 seconds per window, one serial worker. The foreground never substitutes cached source; a background generic reset can use a same-identity verified cache immediately. Protect non-generic external captions. Scheduling is not a cold-reader completion guarantee.

Historical checks are retained separately in JSON with their revision scope. They do not prove the current source's real window-switch, long-running, installation or taskbar effects. Shared Mac models are not counted as native tests or multiplied per language. Every Mac backend remains Experimental. Remote CI has run, with the exact compilation/CLI checkpoint and remaining runtime gaps recorded above; compilation is not AX or GUI acceptance.

C#, AHK, PowerShell, Python, Go and Rust now have Windows tray/settings source. Actual menu acceptance is recorded separately per branch. Go/Rust retain an optional CLI and use the public osascript companion for their Experimental Mac menu. Swift/Objective-C native clients have the recorded CI compilation evidence, while native menus and all Mac AX/runtime paths remain unverified. Basic retains ASCII launch/runtime/IPC and ANSI-x86 restrictions despite binary UTF-16 title handling.

See [guide requirements](docs/guides-index.md) and [local validation](docs/release-readiness.md#local-validation). Raw reports, caches, actual titles and identities are private and excluded from source delivery. [source-sha256.txt](source-sha256.txt) records the reviewed source/build/workflow/test snapshot hashes; the feature candidate needs a refreshed frozen index before merge. Caption labels do not alter Windows app grouping or the macOS Dock application name.

A separate controlled case fixed restoration after a window becomes hidden. The integrated timings above preceded that guard; foreground and native-caption maintenance paths were unchanged.

With a 15-second background setting, worker-attempt gaps across three windows were about 15.16s, 15.17s and 22.20s. Serial reading and foreground priority can delay attempts; strict per-window completion every 15 seconds is not promised. Normal --stop left no standalone process or owned foreground/background helper; original configuration bytes and conversation were restored. Timing samples preceded the hidden-lease guard; their timing paths were unchanged, and the final EXE includes that controlled fix. These are limited observations, not latency guarantees.
