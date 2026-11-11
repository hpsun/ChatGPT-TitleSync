# Icon themes

[简体中文](icon-themes.zh-CN.md) · [Project home](../README.md) · [Startup settings](startup.md)

**Palette 45 is the baseline.** Its enlarged ChatGPT motif carries a blue-violet Title pill at the upper right, with bold monospace text and no outer blue frame. All implementations use the same resource family; their native build/runtime coverage is listed separately in the [support matrix](../support-matrix.md).

<p><img src="../assets/themes/45.png" alt="Baseline 45" width="144"> <img src="../assets/themes/47.png" alt="Amber 47" width="144"> <img src="../assets/themes/48.png" alt="Mint 48" width="144"></p>

## Controls

Open the existing tray/menu **Scan intervals…** settings. Alongside the source intervals and start-at-sign-in checkbox, choose:

| Setting | Choices | Default |
| --- | --- | --- |
| Icon mode | Fixed / Random | Fixed |
| Fixed palette | 45 blue-violet, 46 cyan, 47 amber, 48 mint, 49 rose, 50 sky blue, 51 lavender, 52 coral | 45 |
| Random interval | Daily / Hourly / Every 5 minutes | Daily |

The palette selector is enabled only in Fixed mode. The interval selector is enabled only in Random mode. Save commits changes; Cancel discards the draft. A changed random mode/period selects immediately; the next selection excludes the current palette. Time slots use local wall-clock boundaries, rather than elapsed time since launch. Restarting within a persisted slot keeps its selection.

## Persistence and failure behavior

Windows alternatives share the current-user preference key `HKCU\Software\ChatGPT-TitleSync`: `IconMode` and `IconPeriod` are strings; `FixedIcon` and `RandomIcon` are DWORD palette IDs; `IconSlot` is the last applied time-slot string. macOS experimental sources use the same field names in the shared UserDefaults suite `io.github.hpsun.ChatGPTTitleSync`. The separate `AutoStartEnabled` preference is preserved.

Resources are validated before settings are saved. Missing resources retain a usable existing icon and report a bounded error. Rotation uses the existing lightweight timer and is independent of paused title monitoring; it performs no accessibility reads. Runtime rotation updates this utility's own tray/menu-bar and settings-window artwork. It does not edit a running EXE, pinned shortcut or ChatGPT's own icon.

Keep the repository's `assets/themes` directory with source runs, or the full packaged resource directory with a frozen build. Modern Windows ICO files contain seven sizes (16, 24, 32, 48, 64, 128 and 256 pixels); the legacy variants contain uncompressed DIB frames for AutoHotkey Basic. Baseline aliases and their hashes are in [selection metadata](../assets/icon-selected.json).

## Verification boundary

Current theme changes are undergoing controlled and targeted Windows retesting; earlier nine-runtime caption results belong to earlier revisions. Native Mac compilation, menu appearance, login behavior and accessibility effects have not been verified on a Mac. A workflow definition or Windows-side model is not a Mac test result. See [release readiness](release-readiness.md) for current completion status.
