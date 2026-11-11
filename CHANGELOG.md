# Changelog

[简体中文](CHANGELOG.zh-CN.md) · [HTML](CHANGELOG.html) · [Known issues](KNOWN_ISSUES.md) · [Project home](README.md)

These entries record local development and verification dates in **Beijing time** before the first public source publication. They are not historical Git commit dates, version tags, or invented GitHub issue numbers. Future published fixes should link the real issue, commit or release after it exists.

## 2026-11-11 — AppleScript reserved-selector candidate

The compile-only diagnostic in [run 43035186223, Swift job 130572026758](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43035186223/job/130572026758), for commit `d90f7d3ca16cbd24b7f521b8baa18a0e947984e6`, succeeded and identified the actual offending token as `run` inside `app's run()`. The UTF-16 error range was `{4883, 3}` for the exact CRLF source and `{4787, 3}` for its in-memory LF copy. The repeated CLI `:189` location was not sufficient to identify the failing source statement; the earlier popup edits did not resolve it. All four native compilation steps still passed in that run.

This candidate changes that one call to `app's |run|()`. Apple's [AppleScriptObjC translation guide](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AppendixA-AppleScriptObjCQuickTranslationGuide.html) documents vertical-bar escaping for Cocoa method names that conflict with AppleScript terminology. The selector remains the Cocoa `run` method. A focused static review found no other bare calls from the same command-name set; existing `|error|:` parameter labels remain escaped. No other selector was changed.

The source change is **a candidate pending the next actual Mac CI compile**. The diagnosis compiled source only; it never executed the event loop, a script handler, the AX monitor or the application UI. Native runtime, settings, icons and sign-in startup remain unverified by this work.

## 2026-11-11 — Native SDK compilation and AppleScript diagnostics

In [run 43027160517](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43027160517), commit `f9eb899396fd2885cbad5ee36002be4e8c77554d` passed all four native compilation steps: Swift, Objective-C, Go and Rust. The recorded runner was macOS 15.8.2 (24H232), with Xcode 16.4 (16F6), macOS SDK 15.5, Swift 6.1.2 and Apple Clang 17.0.0. These are SDK compilation results, **not native AX or application-runtime acceptance**.

The independent shared AppleScript compilation still failed with `macos/TraySettings.applescript:189: error: Expected expression but found command name. (-2741)`. The meaning of `:189` has not been established as a source line or character range; earlier popup-expression changes did not resolve the observed error. Its actual location and correction remain pending.

A minimal [compile-only diagnostic tool](tools/diagnose-applescript.swift) now calls `NSAppleScript.compileAndReturnError` for the exact source and an in-memory LF-normalized copy. It prints the compiler error dictionary, UTF-16 `NSRange`, offending token and nearby source text. The workflow invokes it only after the shared AppleScript compile step fails. It never executes the script or a handler, launches the monitor, or performs AX/UI operations. The diagnostic itself still needs its first actual Mac CI result; no AppleScript fix or runtime success is claimed by adding this tool.

## 2026-11-11 — Post-publication macOS CI runner correction

The first public-source [macOS compile-only run (42985821518)](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/42985821518), for commit `4024f41be4792372e574168c938e4a6a3da6766c`, ended as **cancelled**. All four jobs (Swift, Objective-C, Rust and Go) had no assigned runner and no executed steps. Each job annotation reported: `The configuration 'macos-14-arm64-us-default' is not supported`. Checkout and compilation never began; this run provides no source-compilation result or evidence of a billing failure.

GitHub's [official macOS 14 retirement announcement](https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/) confirms retirement on 2026-11-02 and lists supported migration labels. The workflow now targets the fixed `macos-15` label instead of `macos-14`. Verification of this migration is **pending the actual subsequent GitHub Actions run**; a workflow edit alone does not establish compilation success. Even a successful compile-only run would leave native AX behavior, settings, icons and sign-in startup unverified. The earlier candidate entry below retains the verification status at its original documentation freeze.

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

## 2026-11-11 — Experimental macOS compilation repairs

The [first supported-runner build](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43019350487) reached the macOS SDK: Objective-C and Rust compiled successfully. Go failed because an adjacent explanatory comment was included in the Cgo preamble as C text; separating the comments fixes that input. The Swift job stopped at a shared AppleScript parser error before swiftc; the mode-selection branch now computes an integer before making one Objective-C selector call. The next actual CI run must verify both repairs. These are compilation observations, not macOS accessibility or application runtime acceptance.

The [follow-up native run](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43024915028) again built Objective-C and Rust. It exposed three remaining Go compile errors (assignment to an existing error variable and two Core Foundation reference zero values) and another AppleScript selector-argument parsing error. These now have minimal source corrections. Native Swift compilation and AppleScript syntax checking run as separate steps, so either failure remains visible; the workflow also records actual compiler and SDK versions. Verification of this revision is pending the next workflow run.
