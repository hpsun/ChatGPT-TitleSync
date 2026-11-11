# Changelog

[简体中文](CHANGELOG.zh-CN.md) · [HTML](CHANGELOG.html) · [Known issues](KNOWN_ISSUES.md) · [Project home](README.md)

These entries record local development and verification dates in **Beijing time** before the first public source publication. They are not historical Git commit dates, version tags, or invented GitHub issue numbers. Future published fixes should link the real issue, commit or release after it exists.

## 2026-11-11 — Publication candidate and Windows acceptance

### Added and changed

- Shared 45 artwork and independent implementations in C#, AutoHotkey Basic/v1.1/v2, PowerShell, Python, Go, Rust, Swift and Objective-C. Each branch has English and Chinese build/run guides.
- Fresh-install defaults are **2 seconds for foreground source reads** and **5 seconds per background source**. Existing valid saved settings remain effective; explicit startup arguments override the corresponding saved values. Native cached-caption maintenance remains independently scheduled at one second.
- Tray/menu settings save the foreground/background pair and reschedule the existing controller. Source results from an earlier settings generation are rejected. Foreground reads use fresh source data; known inactive generic-caption resets can be repaired from the same-identity cache.
- Windows source checks now include the public [settings callback and hidden-startup fixtures](tools/test-tray-settings.ps1) in PowerShell 5.1 and 7. The [source audit](tools/release_audit.py) excludes runtime caches, logs, private diagnostics, downloaded toolchains and binaries from the source package.

### Fixed

| Observed problem | Cause and correction | Verification / public source |
| --- | --- | --- |
| The first settings window could contain complete controls but remain invisible after launching the process Hidden. | `STARTUPINFO.wShowWindow` can override the first ordinary `ShowWindow` request. Go, Rust, C# and PowerShell display paths now explicitly reveal their owned settings windows with `SetWindowPos` rather than relying on that first Show. C#/PowerShell request activation separately. This was a native visibility issue, not evidence that UI Automation could not locate the controls. | A separate owned WinExe confirms actual Hidden startup flags, an initially hidden native Show, explicit reveal, and unchanged foreground focus. Final running-app settings checks passed. See [C#](windows/csharp/App.cs), [PowerShell](windows/powershell/ChatGPT-TitleSync.ps1), [Go](go/tray_windows.go), [Rust](rust/src/tray_windows.rs), and [fixture](tools/tests/startup_hidden_fixture.cs). |
| A slow foreground source interval could be confused with an unresponsive C# reader, and consuming only on that interval could miss a fresh source snapshot. | Source observation sequence/time and one-second heartbeat sequence/time are separate. The helper reads on the configured source interval; the parent consumes new observations on the native maintenance tick. A healthy source gap does not repeatedly cancel the independent background role. | Controlled cold-attach, long-interval, new-sequence, role-change and old-observation rejection checks; [monitor](windows/csharp/TitleMonitor.cs) and [reader](windows/csharp/TitleReader.cs). |

### Verified, with explicit limits

Nine Windows runtime routes were actually run: C#, AHK Basic, AHK v1.1, AHK v2, Windows PowerShell 5.1, PowerShell 7, Python, Go and Rust. The same three existing windows were reused. Each route completed a valid foreground generic-caption reset, a background reset, settings save/reopen/restore, source/header comparison and normal exit observations. Python's final settings recheck used 7/17 seconds; the other routes used 3/10 before restoring 2/5.

The recorded reset times are single observations, **not benchmarks or a performance ranking**. A bound native settings/menu handler was exercised; this does not claim a physical shell right-click test for every implementation, long-term monitoring, installation acceptance, or all ChatGPT versions. See the [support matrix](support-matrix.md) and [validation details](docs/release-readiness.md#local-validation).

The macOS Swift, Objective-C, Go/Darwin and Rust/macOS branches remain **Experimental: no native Mac SDK build or real AX run**. Remote CI had not run at this documentation freeze. Its actual status must be observed in GitHub Actions after publication, not inferred from local checks.

## 2026-11-10 — Settings save and failure-path fixes

| Observed problem | Cause and correction | Verification / public source |
| --- | --- | --- |
| PowerShell replacement saves could fail with “The path is empty” after an initial settings file already existed. | PowerShell could coerce the third `File.Replace` argument from `$null` to an empty string. The backup argument now uses `[NullString]::Value` to pass a true null. | First and repeated saves, persistence and enable-toggle preservation passed in Windows PowerShell 5.1 and PowerShell 7; [source](windows/powershell/ChatGPT-TitleSync.ps1), [fixture](tools/test-tray-settings.ps1). |
| PowerShell menu callbacks could fail to find a helper function after `GetNewClosure()`. | The closure's dynamic scope did not retain the expected function lookup. Callbacks now capture callable scriptblocks explicitly and pass the save action into the settings form. | Settings open/save/reopen/exit callbacks passed in both hosts; [source](windows/powershell/ChatGPT-TitleSync.ps1). |
| AHK first saves could fail when the destination parent directory did not exist. Output-write failures also needed bounded cleanup rather than an unhandled error window. | Create the settings/output parent before writing. Modern AHK emit/save paths catch expected write failures, report diagnostics, and remove temporary output in `finally`; failed settings commits do not replace the current live values. | Branch-owned first/replacement save, missing-directory, invalid-input, failed-save rollback and temporary cleanup fixtures. See [Basic guide](windows/ahk-v1.0/README.md), [v1.1 source](windows/ahk-v1.1/chatgpt_window_titles.ahk), [v2 source](windows/ahk-v2/chatgpt_window_titles.ahk). |

## Event experiment retained as a limitation

In one 60-second Windows experiment with two confirmed conversation navigations, a single `Document.NameProperty` / `TreeScope.Element` subscription received **zero callbacks**, although source/header observations showed the changes and native foreground/name-change metadata events arrived. Header-text events were not subscribed and the document locator was not rebound. This does not prove every possible ChatGPT event route is unavailable. Event-only monitoring was not adopted; the 2/5-second source fallback remains. See [known issues](KNOWN_ISSUES.md#event-only-monitoring-is-not-implemented).
