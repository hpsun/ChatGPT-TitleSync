# ChatGPT-TitleSync — PowerShell

[简体中文](README.zh-CN.md) · [Project home](../../README.md)

**ChatGPT-TitleSync / ChatGPT 标题同步助手** for Windows x64. Source parsing, embedded C# compilation, fake-foreground checks and tray/settings callbacks are validated under Windows PowerShell 5.1 and PowerShell 7. Real ChatGPT integration was not exercised in this branch's fixtures.

## Name replacement — empty rules by default

The tray **Name replacement… / 名称替换…** entry and the matching button in Settings open the shared Unicode editor. It starts with **no rules**: it does not remove vendor prefixes or extract brackets automatically. Enable individual rows and arrange their order. **Plain text / 普通文字** performs ordinal, case-sensitive global replacement and treats the replacement literally; **Regex / 正则** uses the Windows .NET engine and supports `$0`–`$99`, `${0}`–`${99}` and `$$`. Unsupported or nonexistent capture references are rejected.

The current-conversation list reads the monitor's private **CTS1 source snapshot**, shows its timestamp and can refresh that file. It does not issue another ChatGPT/UIA read. A manual example remains available when the snapshot is missing or invalid. **Suggest rules** derives escaped candidates from the example or selected text, including prefix removal, separator content and paired delimiters. Suggestions are drafts: select **Use rule**, then **Save** to apply them. **Cancel** never saves. Preview runs against the local example only, in a bounded child process.

Windows frontends share `%LOCALAPPDATA%\ChatGPT-TitleSync\title-rules.json`, independent of interval, startup and icon settings. Rules run on the verified raw conversation name before the display suffix. An invalid configuration, replacement, match timeout, blank/control/generic result, overlong output or unpaired UTF-16 surrogate restores the **entire original raw name**, not a partially transformed value. The helper limits matching to 100 ms per regex and 500 ms per pipeline; callers enforce a 1,500 ms rule-worker deadline. Queueing and scheduling can add latency. Unchanged raw names and rule signatures reuse success/fallback caches instead of spawning workers every second.

Saving rules re-derives known displays from raw caches without resetting source-read deadlines. A repaint still requires the same window identity and an owned caption equal to its last write; externally chosen titles remain protected. Runtime `title-rule-sources.bin` snapshots contain private conversation names and must not be published.

After a client has been constructed, the display signature includes rule bytes plus worker existence, size and last-write time. Restoring that worker at the same path can reformat the same cached raw name without another source read. If the companion was absent during PowerShell startup, the feature stays unavailable until the files are restored and the script is restarted. This does not add hot-loading of a missing startup assembly.

See [name-replacement help](../../docs/name-replacement.md) and the packaged [local HTML help](../../docs/name-replacement.html).

### Optional ChatGPT suffix

**Append — ChatGPT / 标题末尾显示ChatGPT** is checked by default. Clear it to show only the derived conversation name. It is independent of the rule master switch; empty or disabled rules can still omit the suffix. Save applies it; Cancel preserves saved bytes. Schema-1 files may omit append_chatgpt_suffix (default true); a present value must be a JSON Boolean.

The raw-name cache, original caption and source schedule remain unchanged. Saving re-renders owned captions at maintenance without another source read; external manual captions remain protected. Valid body/caption limits are 512/522 UTF-16 units. Decodable invalid sources (overlong or containing control characters) return the entire raw name without a suffix or truncation. The CLI keeps --format body-only; --format --caption returns the complete caption. Read failures default to adding the suffix, while valid false remains effective when rule matching falls back. Normal C#/PowerShell consumers do not append another suffix.

Workers retain the 1,500 ms deadline. Success and fallback results are cached for unchanged raw name plus rule/helper signature, until that signature changes, another raw name is observed or the resident restarts. Saving creates a new rule revision. Private parallel runs recorded WorkerTimeout; one sequential low-load retry per PowerShell host then returned ok and actually applied false. This does not prove a universal response-time guarantee. The original failure evidence remains.

### New-feature verification boundary

The new companion has pure Unicode/CLI tests, including whole-pipeline fallback and malformed surrogate output. Injected display-only checks prove cached repaint does not add a source read. PowerShell 5.1/7 client checks use private files and fake window backends. Editor renders use fictional examples and never-shown owned controls at 100%, 125% and 150% simulated font/geometry scales; header glyph bounds fit. A separate offscreen NOACTIVATE/Hidden check verifies the candidate's explicit native reveal without changing the foreground. These checks do **not** claim a new normal-desktop, sign-in, physical tray-menu or all-live-UIA acceptance run. Earlier real-window results below retain their original dates and scope.

### Shared companion and PowerShell loading

From this directory, build it first with `powershell.exe -NoProfile -File ..\..\shared\windows\Build.ps1`. Name replacement requires the resulting `ChatGPT-TitleSync.Rules.exe`, beside the script or in the known repository `shared/windows` location. The script automatically loads the pure-BCL client through `[Reflection.Assembly]::LoadFrom(...)`; PowerShell 7 cannot use `Add-Type -Path` for an EXE. Framework JSON/regex execution stays in the isolated rules process, while the host uses native JSON inspection for empty rules. Without the packaged companion the feature entry is unavailable; it does not take over ordinary source monitoring. This companion is not an EXE wrapper around the PowerShell script.


## Requirements and build
Use 64-bit Windows PowerShell 5.1; PowerShell 7 may run the parent script. The isolated reader always uses the Windows-supplied Windows PowerShell 5.1 executable and UIAutomation assemblies. No MSVC or additional SDK is required; name replacement uses the packaged shared C# rules companion. Add-Type compiles the native bindings in memory.


## Branding and compatibility

The public program name is **ChatGPT-TitleSync / ChatGPT 标题同步助手**. This rename keeps `Local\TdxChatGptTitleStandalone` and its `.Stop`/`.Settings` events unchanged, preventing an older standalone version from writing concurrently. Existing `%LOCALAPPDATA%\ChatGPT-title` storage and settings keys remain unchanged. The script entry is now `ChatGPT-TitleSync.ps1`; `-LogDirectory` still overrides its private storage location. The historical real-window observations below predate the branding and auto-start changes; newer owned/offline checks are scoped separately.

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

The registered command quotes the actual parent PowerShell host and absolute script path: `"<actual-host.exe>" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "<absolute-script-path>"`. It does not retain test log paths or interval overrides. Keep the script and its documented assets at that location. Read-only resident mode disables its startup controls.

The menu item and settings checkbox have the control name `AutoStartEnabled`; source defaults remain foreground 2 seconds/background 5 seconds. The stored monitoring-settings JSON shape and legacy singleton identities remain compatible. This addition was checked with never-shown owned controls and temporary current-user registry keys, including cross-C#/PowerShell off-preference reads; that is not a new real-Run/login acceptance claim.

## Run and interval
From this directory:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-TitleSync.ps1 -IntervalSeconds 2 -BackgroundIntervalSeconds 5
# Non-writing single sample:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-TitleSync.ps1 -ReadOnly -Once
```

The resident script defaults to the selected theme45 tray icon. Right-click for **Enable window titles**, **扫描间隔设置… / Scan intervals…**, and **Exit and restore titles**. The modeless settings dialog accepts whole seconds, validates before saving, applies immediately and persists enable state and both intervals in `powershell-settings.json` under `-LogDirectory`. Explicit command-line intervals override saved values for that run. Disabling cancels owned readers and restores owned matching captions; enabling starts fresh source work. Settings changes invalidate prior reader generations, so an old result cannot commit after a change. Native cached-caption repair remains fixed at one second.

`-Settings` sends a request to the existing resident instance and invokes the same settings menu handler. It does not create another writer. `-Worker`, `-ReadOnly -Once`, and `-Stop` remain non-tray modes. Start at sign-in is enabled by default; diagnostic/IPC modes do not register it.

Foreground source interval defaults to **2 seconds**; -IntervalSeconds accepts 1..3600 (alias -interval). Foreground samples read the active ChatGPT source directly; background sources use the separate low-frequency worker. A shell in the foreground can therefore produce an empty single-sample result. The monotonic scheduler skips missed deadlines and does not add a full interval after every read.

## Stop and restoration
In another terminal:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-TitleSync.ps1 -Stop
```

Windows variants share mutex Local\TdxChatGptTitleStandalone and stop event Local\TdxChatGptTitleStandalone.Stop. Run one standalone variant at a time. Stop and normal script exit restore only a still-matching caption owned by this instance. Forced process termination cannot guarantee restoration.

Known inactive windows retain the latest validated source title; generic app resets are repaired from that cache without a new source read. Unknown background windows acquire a cache only after a valid low-frequency source observation. Foreground, HWND, PID, process creation time, class and executable are rechecked around reads and writes. Loss of focus cancels the owned reader and discards its result. A generic native ChatGPT caption reset is accepted; a genuine custom caption releases write ownership and remains protected.

## Selected icon and packaging
The resident NotifyIcon loads the shared baseline45 ICO directly. A .ps1 file also runs under its PowerShell host and does not embed a custom host EXE icon. A shortcut can use the shared [baseline45 ICO](../../assets/chatgpt-titlesync.ico). A packaged EXE wrapper would need to embed that resource separately; no such wrapper is built by this script. Changing a shortcut icon does not change the host EXE icon.

## Limits and evidence
Each sample starts an isolated PowerShell reader, compiles bindings and initializes UIA. This can take longer than one second. Scheduling every second is not a promise that a read finishes in one second. -ReaderTimeoutMilliseconds remains configurable, default 6000.

Operational logs contain status metadata. -ReadOnly diagnostic output intentionally includes the root web area's name. Conversation bodies and credential fields are not traversed. The worker may only be terminated through its retained owned process handle.

[Current controlled validation](../../docs/release-readiness.md#local-validation) covers the actual pass function with injected foreground/reader/writer fixtures; it does not constitute real ChatGPT or macOS verification.

## Background interval and test scope
Use -BackgroundIntervalSeconds N (alias -background-interval), range 5..3600, default 5. The native background check stays at 1 second independently. Two retained owned child tasks provide foreground and serial background source work; polling uses a zero-time wait and never waits for the background reader before foreground work. Worker startup and UIA latency may exceed one second. Current fake-controller tests cover cache repair without source reads, custom protection, unknown windows, per-window due time, version/identity guards and foreground commits while a background job remains pending. Real ChatGPT integration is not claimed by those fixtures.

## Settings regression checks

```powershell
powershell.exe -NoProfile -STA -File ..\..\tools\test-tray-settings.ps1
pwsh.exe -NoProfile -STA -File ..\..\tools\test-tray-settings.ps1
```

These create never-shown owned controls and exercise the menu/save callbacks, invalid input, repeated atomic save, live state updates, reopen and normal-exit request. They do not activate or read ChatGPT windows and do not send the shared stop event. The atomic backup argument uses `[NullString]::Value` so both PowerShell hosts pass a true null to File.Replace.

## Hidden-startup settings visibility

A process started with Windows `STARTUPINFO` set to Hidden can have its first ordinary Show suppressed. The settings entry now explicitly reveals its owned window with `SetWindowPos` before requesting activation. This is a native window visibility issue, separate from UI Automation source reading.

The public `tools/test-tray-settings.ps1` includes a separate owned WinExe regression: it confirms `STARTF_USESHOWWINDOW` with `SW_HIDE`, observes the first native Show still hidden, then verifies the production reveal helper and a WinForms window become visible. Its windows are offscreen and use `WS_EX_NOACTIVATE`; it asserts that the foreground window stays unchanged. The same public entry runs under PowerShell 5.1 and 7. These are controlled visibility checks, separate from real ChatGPT/menu acceptance.

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Targeted real Windows acceptance — 2026-11-11

PowerShell 5.1/7 targeted cases passed: 2/5 settings, save/reopen/restore, source/header/native agreement, FG reset 881/342ms, BG reset 794/282ms, three generic captions after each normal exit. Controlled 32+9 checks per host and hidden-startup regression remain separate.

One accepted FG and one BG reset; the same three existing windows were reused and matched their original generic captions after exit. Native settings/menu-handler checks do not establish physical shell right-click, long-term use or installation acceptance. See the project support matrix for the precise scope.
<!-- END TARGETED_WINDOWS_REAL -->
