# ChatGPT-TitleSync — AutoHotkey v2

## Compatibility after the rename

The UI labels are fixed rather than selected from the Windows UI language. The tray/title labels are Chinese; the settings fields and Save/Cancel labels are English.

The product is now **ChatGPT-TitleSync / ChatGPT 标题同步助手**. Legacy IPC names (`Local\TdxChatGptTitleStandalone` and `.Stop`), the existing `%LOCALAPPDATA%\ChatGPT-title\...` settings locations, and `TdxChatGptTitles` log locations are intentionally retained. This preserves user preferences and prevents the old and renamed controllers from writing concurrently. Internal class identifiers and the descriptive source filenames are also retained. The rename was checked with syntax/build and isolated owned fixtures; earlier real-window results remain evidence for the unchanged title policy, rather than a new live test of the renamed UI.

**Default-interval candidate update (2026-11-10).** Fresh installations now use foreground **2 seconds** and background **5 seconds**. Existing valid user settings are preserved; explicit CLI arguments still override their corresponding saved values. Python and modern AHK candidates were rebuilt; Basic remains source-only. Branch-local fixture tests do not establish real ChatGPT or shell-menu acceptance, which is recorded separately.

[简体中文](README.zh-CN.md) · [HTML](README.html)

Run this source with its matching interpreter. The build recipe and current acceptance boundaries are below.

## Dependencies

- Windows; runtime: **AutoHotkey v2**, **Unicode x86 or x64; v2.0+**.
- OS-provided Windows UI Automation and Win32 APIs.
- No external COM library or model/API connection. Optional name replacement uses the separately built shared C# companion below.

The tested installed runtime is v2.0.15, both AutoHotkey32.exe and AutoHotkey64.exe. This is v2 syntax and must not be launched by v1.1 or Basic. Native title reading uses ComCall, ComObject, Buffer and native pointer-size types. Optional name replacement uses the shared Unicode companion described below.

Both pointer sizes passed the owned GUI/fake-source foreground policy tests. That test also exposed and verified the fix for a previous Key() function-name shadowing error in Poll and LogEvent; earlier limited self-tests are not substituted for the main-loop policy check.

## Run from source

The following commands assume the matching runtime is on PATH. Otherwise use its quoted absolute path:

    AutoHotkey64.exe "chatgpt_window_titles.ahk"
    AutoHotkey64.exe "chatgpt_window_titles.ahk" --interval 2
    AutoHotkey64.exe "chatgpt_window_titles.ahk" --read-only --once
    AutoHotkey64.exe "chatgpt_window_titles.ahk" --self-test

The --once mode scans once and normally exits, restoring any captions it wrote. --read-only never changes captions.

## Stop

    AutoHotkey64.exe "chatgpt_window_titles.ahk" --stop

The tray exit command is also a normal restoration path.

## Compilation / executable packaging

Compilation is optional; source execution remains supported. The compiled-mode branch now launches the same EXE directly. Source mode still launches the interpreter and source file. The owned worker is checked against the OS image path of the parent executable, so a filesystem junction alias does not falsely reject it.

A candidate using **v2.0.15 x64** and A1 was actually compiled and passed --self-test with CompiledMode=1 and OwnedWorkerDispatch=1. The earlier packaging baseline also verified --stop with a test-owned shared event. The current source-level stop fixture used a private test namespace to verify that both foreground and background readers are reclaimed; a shared stop signal was not sent to an already running controller. All seven A1 ICO frame payloads were verified in the PE resources.

Equivalent PowerShell recipe; replace the example tool paths with your matching official installation:

    New-Item -ItemType Directory -Force ".\build" | Out-Null
    & "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" /in ".\chatgpt_window_titles.ahk" /out ".\build\ChatGPTTitleSync-v2-x64.exe" /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /icon "..\..\assets\chatgpt-titlesync.ico" /compress 0
    New-Item -ItemType Directory -Force ".\build\assets\themes" | Out-Null
    foreach ($id in 45..52) { Copy-Item -LiteralPath "..\..\assets\themes\$id.ico" -Destination ".\build\assets\themes\$id.ico" }
    .\build\ChatGPTTitleSync-v2-x64.exe --self-test
    .\build\ChatGPTTitleSync-v2-x64.exe --interval 2
    .\build\ChatGPTTitleSync-v2-x64.exe --stop

Use the correct runtime version and architecture as /base. Ahk2Exe does not translate v1 syntax into v2. The current three-layer candidate acceptance is x64. Earlier foreground-policy source checks also covered x86; a current x86 build needs its own three-layer and compiled smoke checks.

No normal monitoring or real ChatGPT UIA access was used during packaging validation. Runtime foreground switching and long-running behavior remain separate acceptance items. See the [official Ahk2Exe tool](https://github.com/AutoHotkey/Ahk2Exe) and [compiler/base documentation](https://github.com/AutoHotkey/AutoHotkeyDocs/blob/v1/docs/Scripts.htm).


## Start at sign-in (default enabled)

Normal resident launch first obtains the existing shared controller mutex, then reads the shared startup preference. A missing preference means **enabled**. The tray's **开机自启动** item shows a check mark and applies a toggle immediately. The settings window has the **same 开机自启动** checkbox; its changes apply only on Save, and Cancel leaves startup unchanged. A menu change also updates an already-open settings checkbox. Save updates the same live menu state. Failures show an error and retain or restore the previous registration rather than reporting success.

All Windows implementations share these per-user registry values:

| Location | Value | Meaning |
| --- | --- | --- |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` | `ChatGPT-TitleSync` (REG_SZ) | The current variant's accurately quoted absolute launch command |
| `HKCU\Software\ChatGPT-TitleSync` | `AutoStartEnabled` (DWORD) | Missing = 1; 1 = enabled; explicit 0 = disabled across implementations and restarts |

Turning the switch off removes only this product's Run value and retains DWORD 0. A later launch or another implementation does not force it back on. When enabled, a normal launch updates the command only when needed; identical commands/preferences are not rewritten. No administrator rights, Windows service or scheduled task is used.

The startup command contains only the compiled executable, or the matching interpreter plus the source script. It never copies test log/settings locations, explicit intervals or other testing arguments. Keep a frozen Python runtime directory complete and keep source/runtime files at stable locations. Enabling rejects a command longer than Windows Run's **260-character** limit without changing Run or the preference. Disabling remains available even if the current command is too long. See the [official Run-key limit](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).

Read-only sessions, worker roles, stop commands, one-shot/check modes and self-tests do not register production startup. The autostart self-test uses injected temporary HKCU subkeys and hidden owned controls only:

    AutoHotkey64.exe /ErrorStdOut "chatgpt_window_titles.ahk" --autostart-self-test --output own-startup.json

The private test covers default-on, cross-launch explicit-off persistence, exact source/frozen quoting, repeated no-op registration, 260/261-character source commands, failure rollback, menu/checkbox synchronization, Save and Cancel. It does not claim that an actual sign-in/reboot was performed.


## Tray scan interval settings

Right-click the tray icon and select **扫描间隔设置…**. The two inputs are foreground source checks (default **2 seconds**, range **1–3600 seconds**) and per-window background source refresh (default **5 seconds**, range **5–3600 seconds**). Decimals are accepted within these ranges. Save applies both values without restarting; Cancel leaves them unchanged. Invalid input or a failed settings write leaves the current configuration unchanged.

Settings are stored as INI at `%LOCALAPPDATA%\ChatGPT-title\ahk-v2\settings.ini`. The parent directory is created on first save; subsequent saves replace the same file. On startup, explicitly supplied `--interval` / `--background-interval` values override the corresponding persisted value. A tray save establishes the new persisted values for subsequent starts. The foreground and background owned readers are cancelled and rescheduled after a change, so a result from the previous settings revision cannot be applied.

The lightweight native window/cached-caption repair still runs every **1 second**, independently of these two settings. These inputs do not change UIA watchdogs, the stop-event check or every internal timer. The right-click **Exit and restore** action remains a normal cleanup path. The per-user startup switch is described above; global environment settings are not changed.

The 2026-11-10 interval tests used only isolated fixtures: Python passed 17 settings/native-window checks; AHK Basic passed 6 settings checks; Unicode AHK v1.1 and v2 each passed 11 settings checks. The modern AHK tests include hidden settings-window values, hot timer rescheduling, nonexistent parent directories, first and replacement saves, invalid input, failed-save rollback and temporary-file cleanup. Expected output failures are captured as diagnostics, not displayed as unhandled error windows. These checks do not establish real ChatGPT source-provider or shell-menu acceptance; that is recorded separately.

## Scheduling policy

Foreground ChatGPT windows use a fresh title read on the default 2-second schedule (`--interval`, minimum 1 second). A foreground failure never falls back to the cached title. Focus and full native identity are checked before reading, after reading and before writing.

Every 1 second, lightweight native metadata/caption checks maintain known background windows. If the application changes an owned/known caption back to the generic `ChatGPT`, the most recently verified conversation name is restored from memory immediately; this repair does not start a new UIA read. An unchanged last-written caption is left alone. Custom external captions are preserved, and HWND/PID/process-creation/class/path mismatch invalidates the cached identity.

Background source refresh uses a separate owned reader role, serially visiting eligible background windows every 5 seconds per window by default. Use `--background-interval 15` or `--background-interval 5` (accepted range 5–3600 seconds). Native enumeration only discovers ChatGPT window metadata; title sources follow the verified direct RawView path to `Document[RootWebArea].Name`, never chat-body descendants. Unknown background windows may establish their first name through this low-frequency refresh. A fresh background result updates the native caption only when it is still generic or still owned; custom captions remain protected.

At most one foreground reader and one serial background reader may coexist, with separate owned handles/output. A background target becoming active cancels/discards that background result, and the foreground uses a new read. A background read taking longer than 1 second is not cancelled merely because a foreground tick is due. Readers target a 4-second watchdog; only owned helper processes are terminated. AHK uses cooperative timer threads: processing a background completion or timeout may wait for a foreground callback to return. Queueing, startup and UIA can delay a complete read: **a 2-second foreground schedule is not a guarantee that source reading finishes within 2 seconds, and 5 seconds is a per-window due interval rather than a hard all-window completion deadline.**

Generic home pages are handled without constructing `ChatGPT — ChatGPT`. Normal exit restores only captions still owned by this run and matching identity plus last-written value. No private database, browser-debugging endpoint, Explorer tree or taskbar tree is read. Startup registration is limited to the per-user contract below; taskbar grouping is not changed.

## Stop and coexistence

Use the normal stop command below or the supplied exit control. Forced termination cannot execute caption restoration. Only the script's own reader process is terminated on a timeout or focus loss; ChatGPT is not terminated.

The standalone Windows versions share the mutex Local\TdxChatGptTitleStandalone and the manual-reset event Local\TdxChatGptTitleStandalone.Stop. Run one title controller at a time; do not run it alongside the resident assistant's built-in title feature.

Normal resident launch manages the per-user sign-in entry below. It does not install a service, scheduled task, file association or taskbar-grouping change.

## Runtime icon themes (baseline 45)

The selected baseline is **45**. The base EXE resource and root [ICO](../../assets/chatgpt-titlesync.ico) stay 45. Settings now include three **noneditable dropdowns**: Fixed/Random, a fixed palette **45–52**, and Daily/Hourly/Every 5 minutes. Fixed enables the palette and disables the period; Random does the reverse. Save applies together with intervals/start-at-sign-in; Cancel preserves committed values. A validation or persistence failure rolls back the changed icon/startup state and retains the old usable icon. There are still only two numeric Edit controls.

| ID | Palette |
| --- | --- |
| 45 | Blue-violet / white |
| 46 | Cyan / black |
| 47 | Amber / black |
| 48 | Mint / black |
| 49 | Rose / white |
| 50 | Sky blue / black |
| 51 | Lavender / black |
| 52 | Coral / black |

Windows variants share only these icon values under **HKCU\Software\ChatGPT-TitleSync**: `IconMode` REG_SZ (`fixed`/`random`), `FixedIcon` REG_DWORD (45..52), `IconPeriod` REG_SZ (`day`/`hour`/`5min`), `RandomIcon` REG_DWORD (45..52), and `IconSlot` REG_SZ. Defaults are fixed/45/day; missing preferences are not written by reading them. The startup preference is a separate named value. Read-only/worker/once/check/control/self-test modes do not register production icon preferences. Invalid saved preferences report bounded metadata and use baseline 45 without silently overwriting the saved data.

Random chooses once on enabling or changing period and avoids adjacent random repeats. Same-slot restart reuses the persisted choice. Exact shared local-time slots are `YYYYMMDD` for day, `YYYYMMDDHH±HHMM` for hour, and `YYYYMMDDHHbb±HHMM` for five minutes, with `bb=minute//5` padded to 00..11. The existing metadata timer checks the slot; it does not read ChatGPT or start another helper. Missing/invalid assets or a failed rotation preserve the last usable icon and report at most once per failed slot. Pausing title work does not stop this timer. Runtime changes apply to the tray and this product's own windows; EXEs and pinned shortcuts are never rewritten.

Runtime sources are [chatgpt_window_titles.ahk](chatgpt_window_titles.ahk) plus **[IconTheme.ahk](IconTheme.ahk)** in this same directory. Keep the helper with source-mode deployments. The source includes the helper with `#Include`; modern Ahk2Exe embeds it when compiling. Source mode uses `../../assets/themes`; a compiled EXE requires its own sibling `assets/themes` directory. Normal Windows variants use `45.ico` through `52.ico`.

Isolated theme checks:

```powershell
AutoHotkey64.exe /ErrorStdOut "chatgpt_window_titles.ahk" --icon-self-test
```

The theme self-test passed 30 controlled checks with a private temporary HKCU key, injected clock/picker, copied owned icon assets and hidden owned controls. It checks all eight IDs, three boundaries, same-slot restart, no repeats, missing-asset throttling, Save/Cancel and combined interval/startup/icon rollback. The preserved IDs are numeric inputs 4/6, startup 7, Save/Cancel 9/10, and new dropdowns 12/14/16. These are isolated results; they do not claim a new real ChatGPT, shell-menu or sign-in acceptance for the theme build. Product version remains 0.1.0.

## Validation boundary

The current policy was checked with owned native windows, fake foreground/title sources and owned child processes, including a background source slower than 1 second while foreground ticks continue. Private-namespace stop fixtures also verified cleanup of both reader roles without touching the normal shared stop event. Python passed 12 checks; each AHK branch passed 11, covering cache repair, custom-caption protection, generic home restore, unknown background discovery, target activation and identity invalidation. Source adapters in the fixtures replace only target/source discovery; they do not claim to validate current ChatGPT UIA-provider behavior.

Before the icon-theme update, the three x64 candidates were rebuilt with the previous A1 icon resources from the then-current Python/AHK v1.1/v2 sources; packaged hidden-window/self-worker smoke passed. Basic is source-only because its tested legacy compiler failed and a modern compiler/base attempt timed out; crash remnants are excluded. Real ChatGPT switching, long-running monitoring and shell presentation remain separate acceptance items. Windows results do not establish macOS compilation or AX compatibility. See the repository [support matrix](../../support-matrix.md).

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Targeted real Windows acceptance — 2026-11-11

Current x64 package; Targeted real 2/5 settings/save/reopen/restore and source agreement passed; FG reset 1056ms, BG 409ms; three original generic captions after normal exit. Single observations, not a benchmark.

One accepted FG and one BG reset; the same three existing windows were reused and matched their original generic captions after exit. Native settings/menu-handler checks do not establish physical shell right-click, long-term use or installation acceptance. See the project support matrix for the precise scope.
<!-- END TARGETED_WINDOWS_REAL -->

## Name replacement — shared Unicode companion

The tray **Name replacement… / 名称替换…** and the settings window's same-named button open the **same** shared editor: ordered literal/regex rows, preview, already-read raw-name dropdown, generic regex suggestions and local help. Suggestions require explicit **Use rule**, then Save. Defaults are empty/identity; no personal or machine-specific presets are built in or migrated.

Build the companion first, from this branch directory:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "..\..\shared\windows\Build.ps1"

This builds [TitleRules.cs](../../shared/windows/TitleRules.cs) with the Windows .NET Framework compiler. Retain `ChatGPT-TitleSync.Rules.exe` beside the main EXE, or at the exact repository location `../../shared/windows`; it is never searched through PATH or a preference-supplied command. Keep [English help](../../docs/name-replacement.md) and [中文帮助](../../docs/name-replacement.zh-CN.md), including their HTML siblings, available locally.

Rules are separate at `%LOCALAPPDATA%\ChatGPT-TitleSync\title-rules.json`. Reading, opening and previewing do not create it; only successful editor Save writes it. Timing/startup/icon saves do not overwrite rules. No file means unchanged raw name. Existing rules plus an unavailable companion mean whole-raw fallback with a diagnostic.

Formatting runs on the **verified raw name before** the standard ` — ChatGPT` suffix. Raw-source cache and original native-caption restoration stay unchanged. A separate display revision refreshes only a caption still owned by this run and equal to its last write, protecting manual and generic captions. Normal source schedules and 1-second cached repair remain separate. A nonblocking, pinned, caller-owned format child has a 1500 ms deadline; unchanged success/fallback is cached and stale results are discarded. Signatures are checked on a bounded 1-second cadence without extra ChatGPT reads.

`title-rule-sources.bin` is a **private** CTS1 snapshot in the monitor runtime/settings directory. It contains verified raw names only, is updated on name/window-set changes and must not be committed or published. It populates the editor dropdown without extra UIA reads.

Keep [NameReplacement.ahk](NameReplacement.ahk) beside the main source; its `#Include` is required. Matching modern Ahk2Exe embeds the include, but **does not embed the shared rules EXE or local help**. A compiled deployment needs `ChatGPT-TitleSync.Rules.exe` beside the main EXE and both help pages in a sibling `docs` directory. The existing icon include and theme assets remain required.

The matching official interpreter passed early `--check` parsing. A separate private fixture passed **18** checks with fictional names, the real shared format companion, a disposable owned timeout child and stubbed identity/caption operations.

These are format/protocol and controlled-ownership checks. They do not open the editor, start a normal resident, read ChatGPT, change production startup/preferences or claim new real-desktop/menu acceptance. The linked help defines limits, strict replacement references, OS regex differences and complete-raw fallback.
