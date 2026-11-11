# Rust: ChatGPT-TitleSync

[简体中文](README.zh-CN.md) · [Project home](../README.md)

Windows x64 release build and isolated fixtures are validated. macOS is **Experimental: source only, not compiled or tested on a Mac**. This is independent Rust/native code with no external crate or C# monitor dependency.

## Requirements and build
Windows: Rust's x86_64-pc-windows-msvc toolchain, an MSVC linker and Windows SDK. The local build used Rust 1.82, installed MSVC 2019 Build Tools and Windows SDK 10.0.19041; no new system installation was performed.
```powershell
.\build.ps1
# In a configured MSVC developer environment:
cargo test --offline
cargo build --release --offline
```

Experimental macOS requires Rust and Xcode Command Line Tools/macOS SDK. The native FFI source links System, AppKit, ApplicationServices, CoreFoundation and Objective-C runtime.
```sh
cargo build --release
```
The Mac command is a future native-build instruction, not a verified build result.

Windows `cargo test` and `cargo build` invoke the shared generator through `build.rs` and link its temporary COFF object. Non-Windows targets skip this step. No external crate is added; Windows still needs its existing MSVC linker/SDK plus the PowerShell/.NET components described below.

## Run, interval and controls
```powershell
.\target\release\chatgpt-titlesync-rust.exe --interval 2 --background-interval 5
.\target\release\chatgpt-titlesync-rust.exe --pause
.\target\release\chatgpt-titlesync-rust.exe --resume
.\target\release\chatgpt-titlesync-rust.exe --stop
.\target\release\chatgpt-titlesync-rust.exe --once --read-only
```
On macOS use ./target/release/chatgpt-titlesync-rust with the same flags. --interval is 1..3600 seconds, default **2**. --state-dir PATH selects this implementation's private controls. --once exits after one foreground sample and guarded restoration; it may find no target while the shell is foreground.

The source/caption protocol has three independent layers: foreground source sampling is fresh (default 2 seconds); known inactive generic captions are repaired from memory every second without a source read; a separate serial background worker refreshes each background source at the configurable default 5 seconds and discovers unknown background windows. Foreground sampling never substitutes the remembered title and does not wait on the background source queue. Custom native captions remain protected. Identity, role, cache version and foreground state are checked before committing a result.

Windows variants share mutex Local\TdxChatGptTitleStandalone and stop event Local\TdxChatGptTitleStandalone.Stop. Mac controls are private to this Rust instance, not cross-language. Pause/normal exit restore only still-matching captions this process owns. A forced kill cannot guarantee restoration.

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
Monotonic deadlines skip missed ticks without adding a full completion-based sleep. Each Windows sample starts a reader from this same executable, bounded to four seconds and terminated only using its retained Child handle. Startup/provider latency can exceed a second; the polling setting is not a one-second completion guarantee.

The Mac source uses native foreground-app metadata plus AXFocusedApplication / AXFocusedWindow for foreground work; low-frequency target-window discovery may use AXWindows. Source reads do not hold the cache/registry state lock. Read-only/writability errors are never success reports. Logs contain status/window/PID metadata, not the conversation name/body; only internal reader IPC carries the required root name.

[Validation report](../docs/release-readiness.md#local-validation) covers actual lease/deadline code with fake foreground changes, native COM condition ABI, and an owned offscreen window. These are not real ChatGPT integration or native-Mac tests.

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

Private settings file: **settings.conf** under APPDATA/ChatGPT-title-rust (Windows) or HOME/ChatGPT-title-rust (macOS). --state-dir selects a different private directory.

<!-- BEGIN TARGETED_WINDOWS_REAL -->
The targeted observations below were recorded before the product rename. Renamed Windows builds receive offline/self-owned checks; a new real ChatGPT run is not implied by the name change.

## Targeted real Windows acceptance — 2026-11-11

30 controlled checks; Windows x64 native tray. Mac companion Experimental/uncompiled. Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1018ms, BG 624ms; three original generic captions after normal exit. Single observations, not a benchmark.

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
