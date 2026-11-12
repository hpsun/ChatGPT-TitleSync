# ChatGPT-TitleSync — C# standalone application

[简体中文](README.zh-CN.md) · [HTML](README.html) · [Project home](../../README.md)

Windows tray application for **ChatGPT-TitleSync / ChatGPT 标题同步助手**, written in C# 5 / .NET Framework 4.x.


## Name replacement — empty rules by default

The tray **Name replacement… / 名称替换…** entry and the matching button in Settings open the shared Unicode editor. It starts with **no rules**: it does not remove vendor prefixes or extract brackets automatically. Enable individual rows and arrange their order. **Plain text / 普通文字** performs ordinal, case-sensitive global replacement and treats the replacement literally; **Regex / 正则** uses the Windows .NET engine and supports `$0`–`$99`, `${0}`–`${99}` and `$$`. Unsupported or nonexistent capture references are rejected.

The current-conversation list reads the monitor's private **CTS1 source snapshot**, shows its timestamp and can refresh that file. It does not issue another ChatGPT/UIA read. A manual example remains available when the snapshot is missing or invalid. **Suggest rules** derives escaped candidates from the example or selected text, including prefix removal, separator content and paired delimiters. Suggestions are drafts: select **Use rule**, then **Save** to apply them. **Cancel** never saves. Preview runs against the local example only, in a bounded child process.

Windows frontends share `%LOCALAPPDATA%\ChatGPT-TitleSync\title-rules.json`, independent of interval, startup and icon settings. Rules run on the verified raw conversation name before the display suffix. An invalid configuration, replacement, match timeout, blank/control/generic result, overlong output or unpaired UTF-16 surrogate restores the **entire original raw name**, not a partially transformed value. The helper limits matching to 100 ms per regex and 500 ms per pipeline; callers enforce a 1,500 ms rule-worker deadline. Queueing and scheduling can add latency. Unchanged raw names and rule signatures reuse success/fallback caches instead of spawning workers every second.

Saving rules re-derives known displays from raw caches without resetting source-read deadlines. A repaint still requires the same window identity and an owned caption equal to its last write; externally chosen titles remain protected. Runtime `title-rule-sources.bin` snapshots contain private conversation names and must not be published.

After a client has been constructed, the display signature includes rule bytes plus worker existence, size and last-write time. Restoring that worker at the same path can reformat the same cached raw name without another source read. The C# application references the shared rules assembly as a startup dependency; restore the complete companion set before launching if it is missing. Copying only the main EXE is insufficient.

See [name-replacement help](../../docs/name-replacement.md) and the packaged [local HTML help](../../docs/name-replacement.html).

### Optional ChatGPT suffix

**Append — ChatGPT / 标题末尾显示ChatGPT** is checked by default. Clear it to show only the derived conversation name. It is independent of the rule master switch; empty or disabled rules can still omit the suffix. Save applies it; Cancel preserves saved bytes. Schema-1 files may omit append_chatgpt_suffix (default true); a present value must be a JSON Boolean.

The raw-name cache, original caption and source schedule remain unchanged. Saving re-renders owned captions at maintenance without another source read; external manual captions remain protected. Valid body/caption limits are 512/522 UTF-16 units. Decodable invalid sources (overlong or containing control characters) return the entire raw name without a suffix or truncation. The CLI keeps --format body-only; --format --caption returns the complete caption. Read failures default to adding the suffix, while valid false remains effective when rule matching falls back. Normal C#/PowerShell consumers do not append another suffix.

Workers retain the 1,500 ms deadline. Success and fallback results are cached for unchanged raw name plus rule/helper signature, until that signature changes, another raw name is observed or the resident restarts. Saving creates a new rule revision. Private parallel runs recorded WorkerTimeout; one sequential low-load retry per PowerShell host then returned ok and actually applied false. This does not prove a universal response-time guarantee. The original failure evidence remains.

### New-feature verification boundary

The new companion has pure Unicode/CLI tests, including whole-pipeline fallback and malformed surrogate output. Injected display-only checks prove cached repaint does not add a source read. PowerShell 5.1/7 client checks use private files and fake window backends. Editor renders use fictional examples and never-shown owned controls at 100%, 125% and 150% simulated font/geometry scales; header glyph bounds fit. A separate offscreen NOACTIVATE/Hidden check verifies the candidate's explicit native reveal without changing the foreground. These checks do **not** claim a new normal-desktop, sign-in, physical tray-menu or all-live-UIA acceptance run. Earlier real-window results below retain their original dates and scope.

### Build dependency

This branch’s `Build.ps1` first calls `shared/windows/Build.ps1` to build `ChatGPT-TitleSync.Rules.exe`, then references that assembly when compiling the main application. Keep the main app, reader and rules companion together, with packaged docs/help and assets. Rule CLI/editor entries do not acquire the monitor singleton or register startup.


## Branding and compatibility

The public program name is **ChatGPT-TitleSync / ChatGPT 标题同步助手**. This rename keeps `Local\TdxChatGptTitleStandalone` and its `.Stop`/`.Settings` events unchanged, preventing an older standalone version from writing concurrently. Existing `%LOCALAPPDATA%\ChatGPT-title` storage and settings keys remain unchanged. C# also retains `chatgpt-title-cache.json`, the `chatgpt-title-readers` private work directory and diagnostic schema `chatgpt-title-probe-v1` for saved-data compatibility. The historical real-window observations below predate the branding and auto-start changes; newer owned/offline checks are scoped separately.

## Icon themes — fixed or timed random

Default: **Fixed, theme45**, with the random period retained as **Daily**. The selected design uses the large ChatGPT emblem on a cream tile, an upper-right rounded Title capsule and bold monospaced text. The eight files preserve that layout:

| ID | Capsule / text | ID | Capsule / text |
| --- | --- | --- | --- |
| 45 | Blue-violet / white | 49 | Rose / white |
| 46 | Lake blue / black | 50 | Sky blue / black |
| 47 | Amber / black | 51 | Lavender / black |
| 48 | Mint / black | 52 | Coral / black |

<img src="../../assets/themes/45.png" alt="Default45" width="72"> <img src="../../assets/themes/47.png" alt="Amber47" width="72"> <img src="../../assets/themes/48.png" alt="Mint48" width="72">

Settings adds three **noneditable dropdowns**, keeping the two numeric text fields and startup checkbox. **Fixed/Random** enables either the fixed-color field or the random-period field; the other is disabled. Random periods are local calendar day, local hour, or five-minute wall-clock bucket. Changing to Random or changing its period chooses once immediately; later changes avoid the preceding color. A restart in the same slot reuses the saved random choice. A cheap one-second UI check detects slot changes even while title monitoring is disabled; it does not read ChatGPT or launch a helper for color changes.

Windows variants share only five theme values under `HKCU\Software\ChatGPT-TitleSync`: `IconMode` and `IconPeriod` (`REG_SZ`), `FixedIcon` and `RandomIcon` (`DWORD`, 45..52), and `IconSlot` (`REG_SZ`). Day slots use `YYYYMMDD`; hour slots use `YYYYMMDDHH±HHMM`; five-minute slots use `YYYYMMDDHHbb±HHMM`, where `bb` is minute//5, 00..11. These values do not replace `AutoStartEnabled` or monitoring settings.

**Save** validates assets and commits the theme with startup/interval changes. **Cancel** closes and discards the draft. Registry, startup and settings-file failures restore the preceding committed choice rather than applying a partial new icon. A missing rotation asset keeps the last usable icon and limits diagnostics to that slot; invalid saved data falls back to 45 with a bounded diagnostic instead of silently rewriting the preference. Only a normal resident can persist theme choices; diagnostic/control entries do not.

Runtime themes change this product's tray and own settings-window icons, not EXE bytes, pinned shortcuts or the ChatGPT app's icon. Preserve `assets/themes/45..52.ico` with the install tree; root icon aliases and the base executable resource remain 45. Each previous owned icon is released after replacement. Control names are `IconMode`, `FixedIcon`, `IconPeriod`; their native window IDs are determined at runtime.

The current change passed 37 C# injected clock/random/registry/asset/transaction checks and37 actual PowerShell callback checks in each host, using owned keys and never-shown controls. Earlier A1-era targeted runs documented on 2026-11-11 remain historical; they are not relabelled as current eight-theme/live-change acceptance. Current real-window retesting is recorded separately by the project publisher.

## Start at sign-in — default on

The normal resident enables **开机自启动 / Start at sign-in** by default. It runs when the current Windows user signs in, rather than before login. The tray check item applies immediately. The settings checkbox uses the same state: **Save** applies it; **Cancel** leaves it unchanged. A successful change from either entry updates the other, including an already-open settings form. Failures display an error and retain the preceding successful UI state; registry-write failures attempt to restore prior values.

Windows implementations share the fixed `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value **ChatGPT-TitleSync** and `HKCU\Software\ChatGPT-TitleSync\AutoStartEnabled` DWORD preference. A missing preference means on; an explicit zero remains off across language variants and restarts. Only a normal resident that acquired the existing shared singleton reads/applies that preference and updates the product's Run command. Read-only, worker, one-pass checks and settings/stop IPC entries do not register startup. Turning it off removes only this product's Run value. No administrator permission, service or scheduled task is used. Enabling a command longer than the Windows Run 260-character limit is rejected before either value is changed; disabling still works. Already-matching startup/preference values are not rewritten. See [Microsoft’s Run documentation](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).

The registered command is the fully quoted absolute path of the running `ChatGPT-TitleSync.exe`, without diagnostic or interval arguments. Keep `ChatGPT-TitleSync.Reader.exe` beside it.

The menu item and settings checkbox have the control name `AutoStartEnabled`; source defaults remain foreground 2 seconds/background 5 seconds. The stored monitoring-settings JSON shape and legacy singleton identities remain compatible. This addition was checked with never-shown owned controls and temporary current-user registry keys, including cross-C#/PowerShell off-preference reads; that is not a new real-Run/login acceptance claim.

## Build and run

Build.ps1 uses the Windows Framework64 compiler and UIAutomation/WPF assemblies, produces AnyCPU executables, and requires no MSVC. Keep the main app, title reader and shared rules EXEs together. Preserve the repository assets directory for the relative tray icon; the main EXE embeds baseline 45.

```powershell
powershell.exe -NoProfile -File .\Build.ps1
.\ChatGPT-TitleSync.exe --interval 2 --background-interval 5
```

`--interval` accepts 1..3600 seconds for foreground source checks. `--background-interval` accepts 5..3600 seconds per background window, default 5; use `--background-interval 15` for 15 seconds. Native metadata/caption maintenance remains every second independently. The foreground interval controls actual helper source observations. The helper publishes an independent one-second heartbeat; the parent consumes newly observed source sequences on the one-second metadata tick. An unchanged source timestamp is never relabelled as a fresh observation.

The tray provides **Enable window titles**, **扫描间隔设置… / Scan intervals…**, and **Exit and restore titles**. The modeless settings dialog accepts foreground (1..3600) and background (5..3600) whole seconds, saves both values and applies them immediately without restarting. Invalid values remain in the dialog with an inline error. Enable state and both intervals persist in `%LOCALAPPDATA%\ChatGPT-title\csharp\settings.json`; explicit CLI intervals override saved intervals for that run. Native background cached-caption repair stays fixed at one second. Start at sign-in is enabled by default; see the startup section below.

`ChatGPT-TitleSync.exe --settings` asks the existing resident instance to open this same menu handler; it does not start another writer. Exit code 4 means no compatible resident instance is available. `Build.ps1 -OutputDirectory PATH` builds isolated acceptance binaries without replacing a running copy.

## Files

| File | Role |
| --- | --- |
| App.cs | Tray, settings, singleton and normal exit |
| TitleMonitor.cs | Three-layer scheduler, identity cache, owned helper lifetime and restoration |
| TitleReader.cs | Isolated source reader; document-root Name only during normal monitoring |
| Build.ps1 | Builds rules companion first, then ChatGPT-TitleSync.exe and ChatGPT-TitleSync.Reader.exe |

## Three-layer monitoring

1. Every second, check native ChatGPT identities/captions. Repair a known background window's generic `ChatGPT` reset from its verified cache without reading its source again.
2. Read the foreground conversation name freshly on its source interval. Do not fall back to a cached foreground source. A foreground change cancels the old watch.
3. Refresh each background source at most once per configured interval using one serial reader. Unknown background windows may acquire their first verified title. Foreground attachment/work has priority and does not synchronously wait on a background read.

Source reads follow a bounded native shell to `Document[RootWebArea].Name`, not conversation descendants. Cache/write identity includes HWND, PID, creation time, class and executable path.

Background results can write only for the same identity and a generic or still-owned caption. Non-generic custom captions are preserved. If a background target becomes foreground, its old background result is discarded; the foreground gets fresh source.

## Read-only check

```powershell
.\ChatGPT-TitleSync.exe --read-only --output .\read-only-results.json
```

This enumerates native ChatGPT windows, makes one bounded non-writing source read per window, saves UTF-8 JSON and exits. It does not start the live watch. The per-window read-only deadline is 4 seconds. Results include titles and process identity; keep them private.

## Stop and restore

```powershell
.\ChatGPT-TitleSync.exe --stop
```

Tray Exit and --stop request normal shutdown. Restore only if identity matches and the current caption equals the last write. Preserve external edits. A custom-caption hold releases on a generic reset or explicit feature disable/re-enable; foreground source reads remain fresh while writes are held.

Standalone Windows variants share `Local\TdxChatGptTitleStandalone` and its `.Stop` event. Run one writer at a time. The settings action changes sampling cadence, not the singleton or stop contract.

## Helpers, timing and private data

The foreground retains one isolated --watch helper bound to its window and parent identity. It caches the RootWebArea element, not Name values, and atomically publishes heartbeat `Seq`/`HeartbeatUtc` and source `SourceSeq`/`ObservedUtc` snapshots. Parent polling does not wait for UIA.

Cold attachment deadline: **10 seconds**. After first-ready, heartbeat deadline: **4 seconds**. An independent 500 ms snapshot check preserves healthy helper heartbeats even with a slower parent interval. New data is observed before a stale-boundary decision; pending, duplicate, stale or mismatched snapshots cannot write titles.

Background snapshots have their own cancellation, output file, retained process handle and kill-on-close Job. They cannot kill the foreground helper or unrelated same-name processes. Target activation cancels the background role. Pause/disable/exit clean up both roles.

A one-second schedule does not guarantee a cold reader finishes in one second. Provider responsiveness, native metadata work and system scheduling add latency.

`%LOCALAPPDATA%\ChatGPT-title\csharp` holds settings, title-operation logs, worker snapshots and `chatgpt-title-cache.json`. The private cache intentionally stores verified names and full identities so upgrades can restore existing background windows. It is runtime data, excluded from source packages. Logs use error codes/title fingerprints rather than conversation bodies.

## Validation boundary

The public fixture now contains 41 three-layer policy/timing checks, including long source gaps and background cancellation on role changes. Twelve settings/persistence checks exercise never-shown owned controls; the PowerShell counterpart exercises nine tray callbacks under both 5.1 and 7. Separate existing helper/Job checks cover cold/steady deadlines:

```powershell
powershell.exe -NoProfile -File ..\..\tools\test-csharp.ps1
powershell.exe -NoProfile -STA -File ..\..\tools\test-tray-settings.ps1
```

These fake/self-owned checks cover cache reload/identity, generic resets, custom captions, fresh foreground sources, cancellation, cold/steady deadlines and restoration. They are not complete tray, installation, long-term or real taskbar visual acceptance. See [local validation](../../docs/release-readiness.md#local-validation) and the [support matrix](../../support-matrix.md). macOS is not a C# target.

## Historical real-window observations

The standalone app passed fresh foreground title switching and background generic-reset repair. Both the source and native-caption samples were verified as foreground. A source timestamp to first native-caption sample measured **516ms**; a background cache repair measured **937ms**.

With --background-interval 15, worker-attempt gaps for three windows were approximately **15.16s, 15.17s and 22.20s**. The background reader is serial and foreground work has priority, so this interval is a scheduling minimum, not a guarantee that each window finishes reading exactly every 15 seconds.

Normal --stop exited the app and left no owned foreground/background helper. The original conversation and configuration bytes were restored. These timing samples preceded the hidden-window lease guard; foreground/caption-maintenance paths were unchanged, and the final EXE includes that separately controlled fix.

These are targeted observations, not latency guarantees or complete installation/tray/long-term/taskbar visual acceptance. macOS remains outside this C# target; no remote CI or public release has run.

## Hidden-startup settings visibility

A process started with Windows `STARTUPINFO` set to Hidden can have its first ordinary Show suppressed. The settings entry now explicitly reveals its owned window with `SetWindowPos` before requesting activation. This is a native window visibility issue, separate from UI Automation source reading.

The public `tools/test-tray-settings.ps1` includes a separate owned WinExe regression: it confirms `STARTF_USESHOWWINDOW` with `SW_HIDE`, observes the first native Show still hidden, then verifies the production reveal helper and a WinForms window become visible. Its windows are offscreen and use `WS_EX_NOACTIVATE`; it asserts that the foreground window stays unchanged. The same public entry runs under PowerShell 5.1 and 7. These are controlled visibility checks, separate from real ChatGPT/menu acceptance.

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Targeted real Windows acceptance — 2026-11-11

41 policy + 13 helper/Job + 8 interval protocol + 12 settings and hidden-startup checks; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1384ms, BG 781ms; three original generic captions after normal exit. Single observations, not a benchmark.

One accepted FG and one BG reset; the same three existing windows were reused and matched their original generic captions after exit. Native settings/menu-handler checks do not establish physical shell right-click, long-term use or installation acceptance. See the project support matrix for the precise scope.
<!-- END TARGETED_WINDOWS_REAL -->
