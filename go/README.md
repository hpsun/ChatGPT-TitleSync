# Go: ChatGPT-TitleSync

[简体中文](README.zh-CN.md) · [Project home](../README.md)

Windows x64 build and isolated fixtures are validated. The macOS backend is **Experimental: CI compilation does not establish native runtime/menu validation**. This is independent Go/native code; it never calls a C# monitor.

## Requirements and build
Windows: Go 1.22 or newer, Windows x64. Native Win32/COM bindings use the standard library; cgo and MSVC are not required. The local verification used a portable official Go SDK with a matched SHA256, not a system installation.
```powershell
.\build.ps1
# If Go is not on PATH:
.\build.ps1 -GoExe C:\path\to\go.exe
```
Use `build.ps1` for the official Windows build. It generates a temporary `*_windows_amd64.syso`, runs tests, builds with `-trimpath`, then removes the resource object. A bare `go build` bypasses baseline-icon embedding. The Go runtime bindings still require neither cgo nor MSVC; official icon packaging additionally requires the Windows PowerShell/.NET components described below.

Experimental macOS: Go plus Xcode Command Line Tools/macOS SDK, cgo enabled. The source links AppKit, ApplicationServices, CoreFoundation, Objective-C runtime and libproc.
```sh
CGO_ENABLED=1 go build -trimpath -o chatgpt-titlesync-go .
```
The Mac command is provided for a future native build; it has not been validated here.


Release builds use `-trimpath` to remove local source/build directory prefixes from compiled metadata. Before the later startup/theme additions, the earlier trimmed Windows candidate used the same 14 product source/module files as its full targeted run and passed 38 controlled checks. That historical evidence does not by itself validate the current theme-enabled UI. This flag does not change the product source or create a ZIP delivery.

## Run, interval and controls
```powershell
.\chatgpt-titlesync-go.exe --interval 2 --background-interval 5
.\chatgpt-titlesync-go.exe --pause
.\chatgpt-titlesync-go.exe --resume
.\chatgpt-titlesync-go.exe --stop
.\chatgpt-titlesync-go.exe --once --read-only
```
On macOS use ./chatgpt-titlesync-go with the same flags. --interval accepts 1..3600 seconds, default **2**. --state-dir PATH selects the private control directory; use the same directory for pause/resume/stop. --once samples the foreground at that instant, then exits and restores owned changes; a foreground terminal may yield no sample.

The source/caption protocol has three independent layers: foreground source sampling is fresh (default 2 seconds); known inactive generic captions are repaired from memory every second without a source read; a separate serial background worker refreshes each background source at the configurable default 5 seconds and discovers unknown background windows. Foreground sampling never substitutes the remembered title and does not wait on the background source queue. Custom native captions remain protected. Identity, role, cache version and foreground state are checked before committing a result.

Windows variants share mutex Local\TdxChatGptTitleStandalone and stop event Local\TdxChatGptTitleStandalone.Stop. Mac controls are private files for this Go instance; no cross-language Mac coordination is claimed. Pause and normal stop restore only unchanged captions owned by this instance. Force termination cannot promise restoration.

## Palette 45 and fixed/random icons

The default is **fixed palette 45**, using the shared transparent 45–52 resources. Open **扫描间隔设置…** to choose three noneditable dropdowns: icon mode **fixed/random**, fixed palette **45–52**, and random period **day/hour/5 minutes**. The fixed-palette field is enabled only in fixed mode; the period field is enabled only in random mode. Save validates the required resources and applies the draft; Cancel preserves the committed choices. Runtime changes update the tray and this application's own open settings-window icons. They do not rewrite executable files or pinned shortcuts.

Keep the distributed `assets/themes/45.ico` through `52.ico` available for Windows (all eight are required before saving random mode). The baseline aliases are [ICO](../assets/chatgpt-titlesync.ico), [PNG](../assets/chatgpt-titlesync-icon.png) and [ICNS](../assets/chatgpt-titlesync.icns). Resource lookup accepts an adjacent `themes/` or the normal relative `assets/themes/` layout. The official Windows build embeds all seven baseline-45 resolutions in the EXE. The shared [resource generator](../tools/Make-IconResource.ps1) uses PowerShell/.NET BCL to create Win32 RES, then the Windows .NET Framework 4.x `cvtres.exe` to convert and normalize COFF, without another resource compiler or external library. Missing Windows PowerShell or `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\cvtres.exe` causes a clear failure rather than silently shipping a generic file icon.

Windows preferences are shared across implementations in `HKCU\Software\ChatGPT-TitleSync`; icon settings are not mixed into the language's foreground/background settings file.

| Value | Type | Meaning / missing default |
| --- | --- | --- |
| `IconMode` | REG_SZ | `fixed` (default) or `random` |
| `FixedIcon` | DWORD | 45–52; default 45 |
| `IconPeriod` | REG_SZ | `day` (default), `hour`, or `5min` |
| `RandomIcon` | DWORD | Last random palette, 45–52 |
| `IconSlot` | REG_SZ | Last committed local-time slot |

Random mode uses every palette and excludes the preceding displayed palette. Enabling random mode or changing its period chooses immediately. Restarting in the same valid persisted slot keeps the saved color. Slots use local time: `YYYYMMDD` for day, `YYYYMMDDHH±HHMM` for hour, and `YYYYMMDDHHbb±HHMM` for five minutes (`bb` is minute divided by five, two digits 00–11). Including the UTC offset distinguishes repeated daylight-saving hours. A cheap one-second UI timer compares only this slot; it does not read ChatGPT or start readers. Pausing title synchronization does not stop icon rotation.

Theme registry writes, startup changes and interval-file persistence share a rollback boundary. Failed icon application retains the old icon and committed settings. Missing rotation assets retain the last usable icon and produce one bounded diagnostic for that slot, without repeated popups. Owned old icon handles are released after the tray and product windows have switched. Invalid stored theme fields produce a diagnostic and display fallback 45 without silently rewriting the preferences. Worker, probe, once, read-only and control invocations do not initialize the theme controller.

The macOS companion uses the same shared preference names in the `io.github.hpsun.ChatGPTTitleSync` UserDefaults suite and `assets/themes/45.png` through `52.png`. It owns the menu-bar/settings icon changes; the Go/Rust controller still passes the existing 11 arguments and does not put theme fields into its timing file. This remains experimental source, without native Mac compilation or runtime acceptance on this Windows host.

The added controlled checks use injected time/random selection, fake persistence or private registry keys, and owned hidden native windows. They cover all eight palettes, slot and daylight-saving boundaries, same-slot restarts, no adjacent repeat, field enablement, native Save/Cancel, combined rollback and icon-handle liveness/disposal. They do not substitute for the final real resident acceptance.

## Timing, privacy and validation
The monotonic deadline skips missed ticks instead of sleeping a full interval after each completed read. The separate Windows reader uses this same executable, a four-second bound and its retained child handle. Startup/provider latency can exceed a second: a one-second interval does not guarantee a one-second result.

macOS foreground sampling uses the native front app and AXFocusedApplication / AXFocusedWindow. Low-frequency discovery may query target-app AXWindows; source reads remain bounded and confined to the selected window. Writability and readback are mandatory, and read-only never reports a successful change. Operational output contains status/window/PID metadata, not conversation bodies or names; internal reader IPC contains the required root name.

[Validation report](../docs/release-readiness.md#local-validation): production lease/deadline logic with fake foreground transitions, native COM condition ABI, and an owned offscreen STATIC window. No real ChatGPT integration or Mac behavior was verified.

## Background interval and test scope
Use --background-interval N, range 5..3600, default 5. The native background check stays at 1 second independently of the source intervals. Unknown windows are discovered at the low-frequency cadence. The foreground and background readers are independently controlled; only one background source job runs at a time. A slow reader or a long serial queue can extend actual observation latency. No one-second completion guarantee is claimed.

The current three-layer fixtures cover background generic repair without a source read, custom-caption protection with refreshed memory, unknown-window cache creation, per-window due time, stale-result/version and identity guards, and a pending/slow background job that does not block foreground work. Windows tests are isolated; real ChatGPT integration is not claimed here. macOS remains Experimental, with no native build or AX verification on this Windows host.

## Tray settings and persistence
Normal Windows residency now has a native Win32 tray icon. Right-click it for **Enable window titles**, **开机自启动 / Start at login**, **Scan interval settings…**, and **Exit and restore titles**. The settings window has separate foreground (1–3600 seconds) and background-source (5–3600 seconds) inputs. Defaults are 2 and 5. Save validates and persists both values, then updates the existing controller; it does not start another writer. Disabled/paused monitoring restores owned unchanged captions. A setting change invalidates queued old results and reschedules both lanes; in-flight Windows readers are canceled using their own retained child handles.

The lightweight native check for a known inactive caption being reset remains **fixed at 1 second**. It uses the cached name, does not read the conversation source, and is separate from the two configurable source intervals. Settings are stored in this implementation's private state directory. Saved settings are loaded on the next normal start; explicitly supplied --interval or --background-interval overrides the corresponding saved value for that run. The menu's next Save persists the current choice. --once uses its CLI values without starting a tray. --no-tray explicitly runs the resident with CLI/file controls and no menu.

The Windows settings checks include an owned hidden native settings window, valid/invalid input, persisted enable state, reload, disk-save failure preserving live settings, hot worker rescheduling, and normal owned shutdown. These controlled tests do not replace a real ChatGPT resident integration test.

### Experimental Mac menu companion
macOS uses the public [TraySettings.applescript](../macos/TraySettings.applescript) front end through the operating system's /usr/bin/osascript and AppleScriptObjC/AppKit. This is an explicit system-runtime dependency, not a native self-contained executable. The front end has enable and start-at-login options, a modeless settings panel and Quit. It only writes this language's private settings/stop files; the language controller performs all title reads/writes/restoration. The controller observes validated settings every 100 ms; title maintenance remains at 1 second. Unexpected front-end exit stops the monitor and restores owned captions; missing/startup-failed source reports an error, with --no-tray as the explicit CLI fallback.

Preserve the repository's macos/ and assets/ directories when running from source. Alternatively put TraySettings.applescript beside the executable and preserve ../assets/chatgpt-titlesync-icon.png. No Mac SDK is present on the verification host: this companion and both native Mac backends remain **Experimental, source-reviewed only, not natively compiled or run**.

Private settings file: **settings.json** under APPDATA/ChatGPT-title-go (Windows) or HOME/Library/Application Support/ChatGPT-title-go (macOS). --state-dir selects a different private directory.

<!-- BEGIN TARGETED_WINDOWS_REAL -->
The targeted observations below were recorded before the product rename. Renamed Windows builds receive offline/self-owned checks; a new real ChatGPT run is not implied by the name change.

## Targeted real Windows acceptance — 2026-11-11

38 controlled checks; Windows x64 native tray. Mac companion Experimental/uncompiled. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1784ms, BG 448ms; three original generic captions after normal exit. Single observations, not a benchmark.

One accepted FG and one BG reset; the same three existing windows were reused and matched their original generic captions after exit. Native settings/menu-handler checks do not establish physical shell right-click, long-term use or installation acceptance. See the project support matrix for the precise scope.
<!-- END TARGETED_WINDOWS_REAL -->

## Compatibility after the rename

The visible product name is **ChatGPT-TitleSync / ChatGPT 标题同步助手**. The historical Windows mutex/stop-event names `Local\TdxChatGptTitleStandalone` and `.Stop`, existing state directories, native automation class names and lease/control-file formats are intentionally retained. This preserves saved settings and prevents the old and renamed Windows residents from writing titles simultaneously. A historical name in these compatibility identities is not the current product label. Defaults remain foreground 2 seconds and background 5 seconds; valid existing saved values are preserved.

## Start at login (default on)

The tray's checked **开机自启动 / Start at login** item applies immediately. The settings window has the same checkbox: Save commits it, while Cancel leaves the saved choice unchanged. A successful menu change also updates an already open settings checkbox without overwriting draft interval inputs. Failed registration or persistence reports an error and retains the committed UI/state; registry writes are rolled back if the settings-file commit fails.

Windows language variants share `HKCU\Software\ChatGPT-TitleSync` DWORD `AutoStartEnabled`: absent means on, explicit 0 remains off across language changes and restarts. A normal resident first acquires the existing cross-version singleton, then registers only its quoted absolute EXE path (no test/state-directory arguments) in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value `ChatGPT-TitleSync`. Enabling another language's normal resident replaces that one value rather than adding more startup entries. Normal Exit does not disable the saved startup preference.

Workers, probes, --self-test, --once, --read-only and control requests do not register startup. Read-only residency uses CLI/file controls without the tray, preventing interactive settings from adding startup in a read-only context. --settings is not a supported CLI action in this implementation and is rejected before singleton/registration; use its tray settings action.

The private settings file mirrors `autostart_enabled` (old files missing it default to true); the shared Windows registry preference is authoritative on normal startup. The added offline checks use isolated self-owned registry subkeys, never the real Run key or shared preference, and test default on/off inheritance, transactional/file-failure rollback, menu-checkbox synchronization and Save/Cancel semantics. The current builds still require root-controlled real startup acceptance.

On experimental macOS, the public companion receives `autostart_enabled` as argument 10 and the current absolute EXE path as argument 11. It owns the user LaunchAgent `~/Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist`; Go/Rust only send committed values and observe settings changes. --no-tray skips that optional frontend and its startup management. No Mac LaunchAgent, native compilation or real Mac run was performed on this Windows host.

On Windows the full quoted Run command is limited to 260 UTF-16 characters. Enabling a longer command reports an error before changing Run/preferences; disabling remains available regardless of path length. An already identical command/preference is not rewritten. See [Microsoft Run/RunOnce documentation](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).

## Name replacement and the shared OS companion

Name replacement starts with an **empty rule list**. No personal prefixes, local rules or migration from another application are bundled. Each language monitor calls the same audited OS companion: Windows uses `ChatGPT-TitleSync.Rules.exe` (.NET Framework Unicode/Regex), and macOS uses `chatgpt-titlesync-rules` (Foundation/AppKit). This feature therefore includes that packaged companion; Rust still adds no crates and Go still adds no external Go module.

Build the companion before using the feature:

```powershell
# From this language directory on Windows:
powershell -NoProfile -File ..\shared\windows\Build.ps1
```

```sh
# From this language directory on macOS:
sh ../shared/macos/build.sh
# An optional output directory is supported:
sh ../shared/macos/build.sh /tmp/titlesync-rules-build
```

When using a separate output directory, package the resulting companion beside the monitor executable. Repository layouts also locate it in the known `shared/windows` or `shared/macos` directory. No executable or shell command is loaded from rule preferences or searched on PATH. Packaged local help must accompany the executable/repository layout.

Open **Name replacement…** from the tray menu or the settings button. Rules run in order and can be enabled, removed or reordered. `literal` performs ordinal, case-sensitive, non-overlapping global replacement; `regex` uses the OS engine. Numeric replacement captures support `$0`–`$99`, `${0}`–`${99}` and `$$`; advanced regex features differ between Windows and macOS. An empty replacement is permitted. A failed/invalid/blank/control/overlong result falls back to the complete verified original name.

The editor offers verified current names from a private `title-rule-sources.bin` CTS1 snapshot in this monitor's runtime/settings directory. It does not query ChatGPT again. The timestamp and manual sample remain available if the snapshot is absent or invalid. **Suggest regex** derives escaped candidates from the chosen example/selection, displays the explanation, pattern, replacement and result, and requires **Use rule** followed by **Save**. Opening, previewing or cancelling never creates the persistent rules file. See [name-replacement help](../docs/name-replacement.html).

The shared rules file is `%LOCALAPPDATA%/ChatGPT-TitleSync/title-rules.json` on Windows or `~/Library/Application Support/ChatGPT-TitleSync/title-rules.json` on macOS. Timing/startup/icon settings stay separate and cannot erase rules. Do not publish actual rules, source snapshots, worker packets or runtime logs.

The monitor retains unmodified verified raw names separately from display titles and original-title restore leases. Rule changes advance a display-only generation, discard stale asynchronous results and reformat only still-owned captions that match the last write. Source deadlines and cancellation are unchanged: the existing foreground/background defaults remain 2/5 seconds and native background repair stays on its existing 1-second schedule. Formatting uses an owned disposable worker with a 1500 ms deadline and memoizes success/fallback by raw name, rule bytes and companion existence/mtime/size; a missing companion installed later is retried through a display-only generation change; unchanged repair does not respawn a formatter. Manual titles, window creation identity and exit restoration keep their existing guards.

For rules-only verification, use the new rule and three-layer fake-backend tests. Those tests use private files/in-memory native state; the optional owned-worker fixture launches and terminates only its own no-UI process. The pre-existing unfiltered Windows test suite additionally exercises GUID-scoped temporary registry keys and owned native controls, so an unfiltered `go test`/`cargo test` result is not described as a private-file-only test. Native macOS GUI/runtime behavior still needs actual Mac validation even when CI compilation and pure formatting cases pass.

## Optional ChatGPT suffix

The shared **Name replacement** editor also controls whether to append the fixed ` — ChatGPT` suffix. It defaults on; the optional boolean `append_chatgpt_suffix` in the shared rules JSON defaults to `true` when absent. Turning it off uses the formatted body alone. This preference is separate from this implementation's foreground/background, startup and icon settings.

The product client requests a complete caption with `--format --caption`; its parent cache does not append again. The original `--format` API and body-only fixtures remain unchanged. With no rules file, the verified raw name plus the default suffix is immediately available without creating a rules file or launching a formatter. An existing empty or disabled rule set still goes through the companion so an explicit `false` works. A rule error with a valid false preference retains the complete original body without a suffix; unreadable rules, a missing companion or an invalid worker response use the local default caption. A handled fallback packet is accepted only when it is exactly the original body or that body plus the fixed suffix.

The rule body remains limited to 512 UTF-16 code units; a complete caption is limited to 522. Saving a suffix change refreshes only still-owned display captions through the display generation. Verified raw names, source intervals, source cancellation, manual-caption protection and original-title restoration remain unchanged. Current suffix checks use private files, in-memory native state and format-only companion processes; they do not establish real desktop or Mac GUI acceptance.
