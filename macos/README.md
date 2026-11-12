# Swift, Objective-C and AppleScript: Experimental macOS frontends

[简体中文](README.zh-CN.md) · [Project home](../README.md)

**Experimental runtime; native compilation and CLI checks are separate evidence.** At [the verified SDK checkpoint](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43124672990) for feature commit `19cec8080908a15f0d0a8ccefa66209cb207bf71`, the new Swift and Objective-C native programs compiled and the shared Unicode rule formatter passed **30/30** CLI cases. The same Swift job later failed the separate AppleScript compilation step. This does not establish editor/menu GUI behavior, ChatGPT AX compatibility, pixels, startup or timing; the latest source changes require their own subsequent CI result.

## Requirements and build
A Mac with Xcode Command Line Tools and the macOS SDK is required. The expected target bundle identifier is com.openai.chat; verify it on the target Mac or override --bundle-id.

### Build both native programs and their companion

Run from this directory on the target Mac:

    bash build.sh

[build.sh](build.sh) first calls [shared/macos/build.sh](../shared/macos/build.sh), compiles the Foundation-only [RulesClient.m](../shared/macos/RulesClient.m), imports [RulesClient.h](../shared/macos/RulesClient.h) for Swift, and links the shared client into both native programs. It produces these three executables together, without launching them:

    chatgpt-titlesync-swift
    chatgpt-titlesync-objc
    chatgpt-titlesync-rules

A custom output directory is supported: `bash build.sh /absolute/output-directory`. Keep all three outputs and the resources/help layout described below. The earlier one-source `swiftc`/`clang` recipes omit the new client dependency and are no longer a complete build command. These scripts do not create signed `.app` bundles.

Only when intentionally starting the selected frontend:

    ./chatgpt-titlesync-swift --interval 2 --background-interval 5 --bundle-id com.openai.chat
    ./chatgpt-titlesync-objc --interval 2 --background-interval 5 --bundle-id com.openai.chat

### Name replacement

The menu-bar **Name replacement… / 名称替换…** item and the settings button open the same shared editor. Ordered plain-text/regex rules, manual preview, current-name selection, generic suggestions and help are supported by [TitleRules.m](../shared/macos/TitleRules.m). A suggestion requires explicit **Use rule** and Save. Rules start empty; there are no personal or machine-specific presets, including no imported rules from other software.

Rules are stored at `~/Library/Application Support/ChatGPT-TitleSync/title-rules.json`. Reading/opening/previewing does not create the configuration; only a successful editor Save writes it. Missing rules mean identity. Existing rules with an unavailable companion produce whole-raw fallback and a diagnostic.

The monitor retains the verified raw name and original native-title lease separately. Formatting is applied before the standard ` — ChatGPT` suffix through an asynchronous owned companion, with a 1500 ms caller deadline. Signature/revision caching prevents repeated format launches for unchanged success or fallback. Rule changes refresh only captions still owned and matching the last write, without extra AX source reads or source-timer resets.

`title-rule-sources.bin` is a private CTS1 raw-name snapshot in the implementation's runtime/state directory. Native Swift/Objective-C use subdirectories of `~/Library/Application Support/ChatGPT-TitleSync/runtime`; the Go/Rust settings bridge uses the interval/config directory. Never commit or publish real snapshots. They supply current-name choices from names already read by the normal monitor, without traversing chat history.

Keep executable `chatgpt-titlesync-rules` beside a relocated native program. Repository-native layout may also find it in the known `../shared/macos` or `../../shared/macos` directories. Keep both local help HTML files in a sibling `docs` directory, or retain the repository `../docs` layout. Companion discovery never uses PATH or a command stored in preferences.

See [English rule help](../docs/name-replacement.md) and [中文帮助](../docs/name-replacement.zh-CN.md) for strict capture references, complete-raw fallback, limits and the difference between Foundation and Windows .NET regex behavior. Native SDK/CLI evidence does not establish that the editor, menu or actual ChatGPT AX title writes work on a user Mac.

## Three-layer maintenance
The metadata maintenance timer runs once per second. --interval controls foreground source reads (default 2, range 1..3600 seconds). --background-interval controls each inactive window's source refresh (default 5, range 5..3600 seconds); use 15 for a 15-second refresh.

1. The foreground ChatGPT window reads its current conversation name directly. A remembered title never substitutes for a fresh foreground source read.
2. An identified inactive window resetting to generic ChatGPT immediately receives its remembered title, without starting a source read for that repair.
3. An independent serial background source queue periodically refreshes inactive names and establishes caches for unknown inactive windows. It does not block the foreground source queue or cancel just because another one-second foreground tick occurs.

Only the target bundle's AXWindows metadata is enumerated. NSWorkspace is checked before focused AX access; other applications' content is not read. The bounded native envelope finds one AXWebArea and reads its title. Web-area children and chat messages are never traversed.

Cache identity includes PID, app launch date and AX window identity. Results are discarded when identity, foreground/background role or the pause/settings revision changes. A background result cannot overwrite the foreground result after activation. Non-generic custom captions remain protected; a generic reset permits normal maintenance. AXTitle must be writable and successful writes require matching readback.

The two drafts use in-memory caches. Restarting rebuilds them. Two seconds and 5 seconds are source scheduling intervals, not source-completion guarantees. Several due windows can complete later because background reads are serialized and AX calls have nonzero latency.

## Scan interval menu and saved preferences

Open the menu-bar item and choose **扫描间隔设置…** (Scan intervals…). The modeless panel contains foreground and background source interval fields, **保存** (Save), and **取消** (Cancel). It remains a separate settings panel; normal scheduling continues while it is open.

The menu accepts whole seconds: foreground **1..3600**, background **5..3600**. Defaults are **2 seconds** and **5 seconds**. Invalid or fractional input displays an inline error and does not change the current settings. Cancel leaves them unchanged. Background native-caption repair remains on the independent one-second metadata schedule; these fields change actual source-read scheduling, not that maintenance tick.

Save updates both intervals under one timing lock. It advances the main-thread generation, then queues a state-queue revision/deadline reset for every known window. Pending completions are checked against the new generation and per-window revision before applying their result; the next eligible scan uses the new intervals without restarting. An AX call or commit already in progress is not forcibly interrupted. A commit that passed its last guard before Save may finish while the queued state reset is waiting. A busy reader or state queue can delay the next new observation, so hot application is not a strict response-time guarantee.

Each implementation stores `ScanIntervals` in its own `UserDefaults` suite:

| Implementation | Preferences suite | Values |
| --- | --- | --- |
| Swift | `org.chatgpt-title.swift` | `ForegroundSeconds`, `BackgroundSeconds` |
| Objective-C | `org.chatgpt-title.objc` | `ForegroundSeconds`, `BackgroundSeconds` |

Only these source-read interval values remain separate from each other and the Go/Rust AppleScript settings bridge; icon/startup preferences use the shared suite described below. At startup, valid explicit `--interval` / `--background-interval` values override saved values for that launch; an omitted parameter uses its valid saved value or the default. A later menu Save applies and persists the newly entered pair. The startup checkbox and icon controls are committed with Save as described below. Interval settings do not persist conversation-title caches or change Accessibility permissions.

**Historical theme-revision boundary:** the initial panel, input handling, preferences, locking and generation checks received static source review only. The Swift `application.run()` and Objective-C `main` / `[application run]` entry points remain present. These observations are not native compilation, GUI appearance, preferences-runtime or AX timing acceptance; those checks still require a real Mac.

## Experimental sign-in startup — default on

The source now includes a direct **开机自启动 / Start at sign-in** menu check and the same checkbox in settings. Menu changes apply immediately; Save commits the settings choice and Cancel leaves it unchanged. Successful changes synchronize both controls. Exit stops the current process without clearing the next-login choice.

All four Mac implementations share `NSUserDefaults` suite `io.github.hpsun.ChatGPTTitleSync`, key `AutoStartEnabled` (missing defaults on), and `~/Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist`. The draft uses an absolute executable argument, `RunAtLoad=true`, `KeepAlive=false`; it prepares the next login rather than bootstrapping a second resident immediately. Swift/Objective-C retain their separate `ScanIntervals` suites above. The Go/Rust menu companion also persists `autostart_enabled`; its internal launch contract now has **11 arguments**, adding the autostart boolean and executable path. Use the current branch launcher, not an older nine-argument companion invocation.

**Historical theme-revision boundary:** this addition was then source-only Experimental and had not been compiled or run on a Mac. The later native compilation checkpoint above does not establish login, preferences-runtime, permission or AX acceptance. See the [startup guide](../docs/startup.md).

## Pause, quit and permissions
Use the menu-bar Pause and restore, Resume, Quit and restore, and Check/request Accessibility permission controls. The drafts do not implement a --stop CLI flag. Normal exit restores only still-matching titles owned by that instance. Forced termination can prevent restoration. Accessibility permission is decided by the user; no privacy setting is changed automatically.

## Icon themes: baseline 45 and eight palettes

The current baseline is **45**. The settings panel adds three **noneditable pop-up lists**: Fixed/Random mode, fixed palette **45–52**, and Daily/Hourly/Every 5 minutes. Fixed enables the palette list and disables the period list; Random does the reverse. Cancel preserves committed settings. Save validates the selected resources before attempting startup, theme and interval writes. On failure, the code attempts to restore the prior five icon values, startup preference/LaunchAgent and interval configuration; a rollback failure is reported rather than presented as success.

| ID | Palette | Runtime PNG |
| --- | --- | --- |
| 45 | Blue-violet / white | [45.png](../assets/themes/45.png) |
| 46 | Cyan / black | [46.png](../assets/themes/46.png) |
| 47 | Amber / black | [47.png](../assets/themes/47.png) |
| 48 | Mint / black | [48.png](../assets/themes/48.png) |
| 49 | Rose / white | [49.png](../assets/themes/49.png) |
| 50 | Sky blue / black | [50.png](../assets/themes/50.png) |
| 51 | Lavender / black | [51.png](../assets/themes/51.png) |
| 52 | Coral / black | [52.png](../assets/themes/52.png) |

All four Mac implementations share the icon values below in `NSUserDefaults` suite **`io.github.hpsun.ChatGPTTitleSync`**. Their separate source-read interval stores remain unchanged.

| Key | Values / meaning |
| --- | --- |
| `IconMode` | String `fixed` or `random`; default `fixed` |
| `FixedIcon` | Integer 45..52; default 45 |
| `IconPeriod` | String `day`, `hour` or `5min`; default `day` |
| `RandomIcon` | Last chosen integer 45..52 |
| `IconSlot` | Persisted local-time slot of that random choice |

Missing icon preferences are read as fixed/45/day without writing defaults. Invalid stored preferences retain their saved data, report bounded metadata and use baseline 45 where its resource is available. Random mode selects once immediately when enabled or its period changes, avoids adjacent random repeats, and reuses the persisted choice on a same-slot restart. Exact shared slots are `YYYYMMDD`, `YYYYMMDDHH±HHMM`, and `YYYYMMDDHHbb±HHMM`; for five minutes, `bb=minute//5`, padded to 00..11. Hour/five-minute offsets distinguish repeated local hours.

Swift/Objective-C check the slot on their existing one-second metadata timer. The AppleScript companion previously had no UI timer, so it now has one one-second AppKit timer dedicated to this slot check. It performs no ChatGPT/AX/source read and starts no additional helper. Pausing title work leaves icon rotation active. Scheduling is not a strict display-time guarantee. Missing assets or a failed rotation keep the last usable image and report at most once per failed slot; an initial missing image can leave a textual `GPT` fallback. Runtime changes affect this product's menu-bar/application image, without rewriting executable files or pinned shortcuts.

### Resource layout and packaging

Keep all eight PNGs. A source build placed in `macos/` finds `../assets/themes`. A relocated binary can keep `assets/themes` beside itself. For an `.app` bundle, use `Contents/Resources/themes` (or `Contents/Resources/assets/themes`). The native drafts check those bundle resource locations, then binary-sibling `assets/themes`, then `../assets/themes`; avoid an empty earlier directory shadowing a complete later one.

```text
ChatGPT-TitleSync/
  assets/
    chatgpt-titlesync-icon.png
    themes/45.png ... 52.png
  macos/
    ChatGPTWindowTitles.swift
    ChatGPTWindowTitles.m
    TraySettings.applescript
    build.sh
    chatgpt-titlesync-rules   # shared runtime companion
    chatgpt-titlesync-objc
    chatgpt-titlesync-swift   # locally compiled example
```

The Go/Rust companion keeps its **11-argument interface unchanged**. It derives `themes` from the containing directory of argument 8, the base PNG path. Use the current Go/Rust launcher and retain that asset layout; no twelfth theme argument is introduced. Icon preferences are not added to the existing Go/Rust interval-file schema.

The build commands above produce executables, not signed `.app` bundles, and do not embed the PNG set. A separately prepared bundle may use the current [baseline-45 ICNS](../assets/chatgpt-titlesync.icns) through `CFBundleIconFile`, with the runtime PNGs retained as described above. Packaging, signing, notarization and per-window Dock naming remain unverified.

**Historical A1 record.** Earlier pre-theme instructions described a textual menu-bar item and optional A1 bundle-icon packaging; the CLI build did not embed A1. That remains historical evidence. The current root PNG/ICO/ICNS aliases now represent 45, and the source now implements runtime image selection. No successful native Mac rendering is inferred from either the old A1 record or the new resources.

## Validation

The current native/30-case CLI checkpoint and its separate AppleScript failure are recorded at the top of this guide. The following model/static records are **historical theme-revision evidence**, not the current compilation status.

See the [release validation summary](../docs/release-readiness.md#local-validation). The historical **13-case title behavior model** predates the three-layer implementation and remains model evidence only. The new [23-case icon contract model](test_icon_policy.py) passed with fake preferences/assets, injected time/random selection, same-slot restart, period boundaries, no repeats, Save/Cancel and startup/interval/theme rollback. The retained 13-case title model also passed when imported without generating source-tree receipts.

```sh
python3 -B test_icon_policy.py
python3 -B -m unittest discover -s . -p test_macos_behavior.py
```

Static comparison found the existing AX/title algorithm bodies unchanged. The Swift `application.run()` and Objective-C `main` / `[application run]` entry points remain present, and the AppleScript 11-argument boundary remains intact. Lexical delimiter/handler checks and the state models are **not native compiler or runtime tests**.

At that historical theme-revision freeze, native Swift/Objective-C compilation, `osacompile`, the AppleScriptObjC bridge, AppKit controls/images and ARC/lifetime behavior, real `UserDefaults` persistence and rollback, LaunchAgent/login behavior, Accessibility permission, the actual ChatGPT AX hierarchy/writable title, pixels, focus/pause timing and packaging were not verified on a Mac. Product version remains **0.1.0**, with these Mac frontends marked **Experimental**. Subsequent changed-source SDK builds and controlled native AX/GUI acceptance remain required before claiming runtime support.

Static review also retains each window's state-queue-only source revision, advanced for new reads and observed foreground/background transitions. A completion must match that revision and the pause/exit generation. External caption changes release the old write lease while retaining the verified title cache. A closed window is retired only after a successful, uncapped AXWindows snapshot for the same PID and launch identity; failed/capped enumeration preserves prior records conservatively. The shared state queue may delay commits during metadata AX calls; separate source queues do not provide a hard timing guarantee.
