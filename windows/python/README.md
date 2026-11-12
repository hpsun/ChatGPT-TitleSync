# ChatGPT-TitleSync — Python

## Compatibility after the rename

The UI labels are fixed rather than selected from the Windows UI language. Python uses Chinese/English labels.

The product is now **ChatGPT-TitleSync / ChatGPT 标题同步助手**. Legacy IPC names (`Local\TdxChatGptTitleStandalone` and `.Stop`), the existing `%LOCALAPPDATA%\ChatGPT-title\...` settings locations, and `TdxChatGptTitles` log locations are intentionally retained. This preserves user preferences and prevents the old and renamed controllers from writing concurrently. Internal class identifiers and the descriptive source filenames are also retained. The rename was checked with syntax/build and isolated owned fixtures; earlier real-window results remain evidence for the unchanged title policy, rather than a new live test of the renamed UI.

**Default-interval candidate update (2026-11-10).** Fresh installations now use foreground **2 seconds** and background **5 seconds**. Existing valid user settings are preserved; explicit CLI arguments still override their corresponding saved values. Python and modern AHK candidates were rebuilt; Basic remains source-only. Branch-local fixture tests do not establish real ChatGPT or shell-menu acceptance, which is recorded separately.

[简体中文](README.zh-CN.md) · [HTML](README.html)

Source execution and the console/onedir candidate are described below. This remains an unpublished pre-release candidate.

## Dependencies

- Windows and a Python 3 interpreter. The script uses only the standard library: ctypes, subprocess, pathlib, and related modules.
- Windows UI Automation and Win32 APIs supplied by the OS.
- No pythonnet, external COM package or model/API connection. Optional name replacement uses the separately built shared C# companion below.

Keep a python.exe next to pythonw.exe when using the latter: the source-mode worker chooses the console interpreter to capture its JSON output.

## Run from source

From this directory:

    python chatgpt_window_titles.py
    python chatgpt_window_titles.py --interval 2
    python chatgpt_window_titles.py --read-only --once
    python chatgpt_window_titles.py --read-only --once --hwnd 123456

The optional HWND filter limits both foreground and background handling to that current native window. `--once` performs one foreground read and exits; it does not start the background refresh loop.

For a quiet source-mode process, pythonw may be used instead of python. The standard-library Win32 tray now provides scan settings and normal exit; --no-tray keeps a console-only deployment. Normal resident launch enables per-user sign-in startup by default; isolated modes do not register it.

## Stop

    python chatgpt_window_titles.py --stop

Ctrl+C is the console exit path. Stop/cancellation also cleans up the owned reader process.

## Syntax check, build, and packaging

Source execution needs no compilation. Bytecode checking is not a standalone EXE:

    python -m py_compile chatgpt_window_titles.py
    python chatgpt_window_titles.py --self-test

The worker now distinguishes source mode from a frozen executable: source mode launches interpreter + source file; frozen mode launches the same EXE directly with internal worker arguments. The self-test verifies an owned child dispatch and Unicode reply without reading ChatGPT.

### Tested Windows x64 build

Tested tools: CPython 3.12.14 x64, PyInstaller 6.22.3, hooks 2026.10. Build dependencies were installed only in a validation-local directory. The tested package is **console + onedir**, not windowed or one-file.

Equivalent PowerShell steps, from this directory, with a Python interpreter you have chosen:

    $tools = Join-Path $PWD ".build-tools"
    python -m pip install --target "$tools" pyinstaller==6.22.3
    $env:PYTHONPATH = $tools
    $themeRoot = (Resolve-Path "..\..\assets\themes").Path
    $themeData = @(); foreach ($id in 45..52) { $themeData += @("--add-data", ((Join-Path $themeRoot "$id.ico") + ";assets\themes")) }
    python -m PyInstaller --noconfirm --onedir --console --noupx --name ChatGPTTitleSyncPython --icon "..\..\assets\chatgpt-titlesync.ico" --distpath ".\build\dist" --workpath ".\build\work" --specpath ".\build" @themeData ".\chatgpt_window_titles.py"
    .\build\dist\ChatGPTTitleSyncPython\ChatGPTTitleSyncPython.exe --self-test

Keep the **entire** ChatGPTTitleSyncPython directory, including _internal; the EXE alone is not a portable package. Use --console for this verified recipe: the worker uses redirected standard output. A --windowed/--noconsole or one-file variant needs its own acceptance and is not claimed here.

Run and stop the built candidate:

    .\build\dist\ChatGPTTitleSyncPython\ChatGPTTitleSyncPython.exe --interval 2 --log "$env:LOCALAPPDATA\ChatGPTTitle\python.jsonl"
    .\build\dist\ChatGPTTitleSyncPython\ChatGPTTitleSyncPython.exe --stop

The explicit per-user --log path avoids treating a bundle-internal path as durable logging. The environment variable above affects only that PowerShell session; no global Python environment is installed by this guide.

The actual validation candidate passed frozen=true, owned Unicode write/restore, external-caption protection, self-worker dispatch. The earlier packaging baseline verified --stop using a test-owned shared event; the current source-level private-namespace stop fixture verified that both reader roles are reclaimed without signalling an existing controller. That earlier A1 resource contained all seven input frames; the theme candidate uses baseline 45. These are build/smoke results, not a real ChatGPT switching or long-running acceptance test. See the [official PyInstaller runtime guide](https://pyinstaller.org/en/stable/runtime-information.html).


## Start at sign-in (default enabled)

Normal resident launch first obtains the existing shared controller mutex, then reads the shared startup preference. A missing preference means **enabled**. The tray's **开机自启动 / Start at sign-in** item shows a check mark and applies a toggle immediately. The settings window has the **same 开机自启动 / Start at sign-in** checkbox; its changes apply only on Save, and Cancel leaves startup unchanged. A menu change also updates an already-open settings checkbox. Save updates the same live menu state. Failures show an error and retain or restore the previous registration rather than reporting success.

All Windows implementations share these per-user registry values:

| Location | Value | Meaning |
| --- | --- | --- |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` | `ChatGPT-TitleSync` (REG_SZ) | The current variant's accurately quoted absolute launch command |
| `HKCU\Software\ChatGPT-TitleSync` | `AutoStartEnabled` (DWORD) | Missing = 1; 1 = enabled; explicit 0 = disabled across implementations and restarts |

Turning the switch off removes only this product's Run value and retains DWORD 0. A later launch or another implementation does not force it back on. When enabled, a normal launch updates the command only when needed; identical commands/preferences are not rewritten. No administrator rights, Windows service or scheduled task is used.

The startup command contains only the compiled executable, or the matching interpreter plus the source script. It never copies test log/settings locations, explicit intervals or other testing arguments. Keep a frozen Python runtime directory complete and keep source/runtime files at stable locations. Enabling rejects a command longer than Windows Run's **260-character** limit without changing Run or the preference. Disabling remains available even if the current command is too long. See the [official Run-key limit](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).

Read-only sessions, worker roles, stop commands, one-shot/check modes and self-tests do not register production startup. The autostart self-test uses injected temporary HKCU subkeys and hidden owned controls only:

    python chatgpt_window_titles.py --autostart-self-test

The private test covers default-on, cross-launch explicit-off persistence, exact source/frozen quoting, repeated no-op registration, 260/261-character source commands, failure rollback, menu/checkbox synchronization, Save and Cancel. It does not claim that an actual sign-in/reboot was performed.


## Tray scan interval settings

Right-click the tray icon and select **扫描间隔设置…**. The two inputs are foreground source checks (default **2 seconds**, range **1–3600 seconds**) and per-window background source refresh (default **5 seconds**, range **5–3600 seconds**). Decimals are accepted within these ranges. Save applies both values without restarting; Cancel leaves them unchanged. Invalid input or a failed settings write leaves the current configuration unchanged.

Settings are stored as JSON at `%LOCALAPPDATA%\ChatGPT-title\python\settings.json`. The parent directory is created on first save; subsequent saves replace the same file. On startup, explicitly supplied `--interval` / `--background-interval` values override the corresponding persisted value. A tray save establishes the new persisted values for subsequent starts. The foreground and background owned readers are cancelled and rescheduled after a change, so a result from the previous settings revision cannot be applied.

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

Runtime sources are [chatgpt_window_titles.py](chatgpt_window_titles.py) plus **[icon_preferences.py](icon_preferences.py)** in this same directory. Keep the helper with source-mode deployments. PyInstaller includes the imported helper automatically. The frozen package recipe above includes the eight normal ICOs in `_internal/assets/themes`; keep the complete onedir directory. Normal Windows variants use `45.ico` through `52.ico`.

Isolated theme checks:

```powershell
python -B tests/test_icon_preferences.py
python chatgpt_window_titles.py --icon-self-test
```

The public 18 policy unit tests use fake persistence/assets and an injected clock; an additional controlled fixture passed 35 checks including hidden native Save/Cancel, full five-value rollback, interval/startup rollback and icon-handle liveness. These are isolated results; they do not claim a new real ChatGPT, shell-menu or sign-in acceptance for the theme build. Product version remains 0.1.0.

## Validation boundary

The current policy was checked with owned native windows, fake foreground/title sources and owned child processes, including a background source slower than 1 second while foreground ticks continue. Private-namespace stop fixtures also verified cleanup of both reader roles without touching the normal shared stop event. Python passed 12 checks; each AHK branch passed 11, covering cache repair, custom-caption protection, generic home restore, unknown background discovery, target activation and identity invalidation. Source adapters in the fixtures replace only target/source discovery; they do not claim to validate current ChatGPT UIA-provider behavior.

Before the icon-theme update, the three x64 candidates were rebuilt with the previous A1 icon resources from the then-current Python/AHK v1.1/v2 sources; packaged hidden-window/self-worker smoke passed. Basic is source-only because its tested legacy compiler failed and a modern compiler/base attempt timed out; crash remnants are excluded. Real ChatGPT switching, long-running monitoring and shell presentation remain separate acceptance items. Windows results do not establish macOS compilation or AX compatibility. See the repository [support matrix](../../support-matrix.md).

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Targeted real Windows acceptance — 2026-11-11

Final executable passed source/header and later native-title agreement, FG reset 161ms, BG reset 379ms and three generic captions after exit. Two earlier guards skipped injection, not product failures. Settings recheck independently proved persisted/reopened 7/17 and restored 2/5 in one process; the earlier 33/10 ambiguity is preserved without a product-defect conclusion. No Mac validation.

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

Keep [name_replacement.py](name_replacement.py) beside the main source. PyInstaller follows its static import; a custom spec must retain it, or add `--hidden-import name_replacement`. The shared rules EXE remains external. After the onedir build above:

    $bundle = ".\build\dist\ChatGPTTitleSyncPython"
    Copy-Item "..\..\shared\windows\ChatGPT-TitleSync.Rules.exe" $bundle
    New-Item -ItemType Directory -Force "$bundle\docs" | Out-Null
    Copy-Item "..\..\docs\name-replacement.html","..\..\docs\name-replacement.zh-CN.html" "$bundle\docs"
    python -B tests/test_name_replacement.py -v

The adapter passed 14 owned-file/process tests plus 8 private checks with the real shared format companion. The checks include Unicode CTS1, exact fallback, cache invalidation, timeout, stale generations and simulated ownership guards.

These are format/protocol and controlled-ownership checks. They do not open the editor, start a normal resident, read ChatGPT, change production startup/preferences or claim new real-desktop/menu acceptance. The linked help defines limits, strict replacement references, OS regex differences and complete-raw fallback.

### Optional ChatGPT suffix — default enabled

The shared name-replacement editor has an independent **Append — ChatGPT / 标题末尾显示ChatGPT** checkbox, checked by default. Uncheck it and **Save** to stop adding the program's ` — ChatGPT` suffix. It remains effective when replacement rules are empty or **Enable name replacement** is off. This switch does not remove matching text that is part of the original conversation name.

The optional JSON field `append_chatgpt_suffix` is a boolean in the shared `title-rules.json`; an omitted field defaults to `true`. It is not stored in scan-interval, icon or startup preferences. The frontend asks the shared formatter for the **complete caption** with `--format --caption`, then uses that output directly, avoiding a second suffix. Existing body-only `--format` clients keep their previous semantics. The verified raw source remains limited to 512 UTF-16 units; a complete caption is limited to 522 units including the optional 10-unit suffix.

Saving this choice changes display generation only. It can refresh an owned caption still matching the last write, without extra source reads, source-timer resets or changes to raw/original restoration data. An existing configuration is always sent to the companion in caption mode, even with empty/disabled rules, so the unchecked suffix remains effective. A handled formatter fallback accepts only the entire raw name or that raw name plus the fixed suffix. If the companion cannot run or misses its deadline, the safe local fallback uses the default suffix and records a diagnostic; unchanged fallback stays cached until the rules/helper signature changes, a different raw name is observed or the monitor restarts.

Caption revision checks: **23** owned Python unit tests and **14** private checks against the actual copied Windows companion passed. These are file/process and simulated ownership checks, not a fresh normal-desktop/editor acceptance.
