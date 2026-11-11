# ChatGPT-TitleSync roadmap

[简体中文](roadmap.zh-CN.md) · [HTML](roadmap.html) · [Project home](../README.md) · [Known issues](../KNOWN_ISSUES.md) · [Changelog](../CHANGELOG.md)

This roadmap describes work **after v0.1.0**, the initial public preview of **ChatGPT-TitleSync / ChatGPT 标题同步助手**. Planned items below are not implemented features and do not have a committed release date or version.

## Current sign-in startup addition

Start at sign-in is part of this revision and **defaults on**, with a direct tray/menu check and a Save/Cancel settings checkbox. It is not deferred language work. Windows shares one current-user Run value and DWORD preference across implementations; overlong enable commands are rejected, and Exit does not cancel next-login registration. See the [startup guide](startup.md). Current real Windows retesting is **in progress**; the earlier nine-runtime table is historical, not acceptance of these new startup sources. macOS LaunchAgent/preferences source is Experimental and has not been compiled or run on a Mac.

## Contents

- [Current v0.1.0 boundary](#current)
- [Planned work](#planned)
- [Checks before a future release](#acceptance)
- [Related records](#references)

<a id="current"></a>
## Current v0.1.0 boundary

Runtime UI labels are fixed by implementation. The program does not currently choose its UI language from the system language, and it has no implemented manual language selector. English and Chinese documentation are separate static guides, not evidence of automatic runtime localization. Basic retains an English/ASCII UI for compatibility.

**Palette 45** is the selected baseline, with seven alternative palettes and fixed/random controls in the current candidate. The default policy remains fresh foreground sources every **2 seconds**, background sources every **5 seconds per window**, and lightweight background cached-caption repair every **1 second**. Valid saved settings and shared legacy IPC/state identities are preserved.

<a id="planned"></a>
## Planned work

| Item | Status | Intended scope |
| --- | --- | --- |
| Select the runtime UI language automatically | Later release; not implemented in v0.1.0 | Read the system's preferred UI language, select an available translation, and define a consistent fallback. This applies to program UI text, not ChatGPT conversation contents. |
| Manual language override | Later release; not implemented in v0.1.0 | Let the user explicitly choose a supported UI language and retain that choice across restarts; an explicit choice should take priority over automatic selection. The exact settings interface remains to be designed. |
| Icon customization | Included in the current candidate | Baseline 45 plus palettes 46–52; fixed or random rotation daily, hourly or every five minutes. See [icon settings](icon-themes.md) for the validation boundary. |
| Native macOS validation | Pending | Build Swift, Objective-C, Go/Darwin and Rust/macOS on an actual Mac. Check native menus, AX permission/provider behavior, title writeability, foreground ownership, restoration and timing before expanding support claims. |

<a id="acceptance"></a>
## Checks before a future release

Language work needs checks under supported system-language settings and with a persisted manual override. Labels, tooltips and settings should remain consistent without changing monitoring cadence, state compatibility or title ownership rules. Basic's ASCII/source constraints require an explicit compatibility decision before changing its UI representation.

The selected artwork has PNG/ICO/ICNS exports and a Basic-compatible uncompressed ICO representation. Mac source review, Windows-side models and local Windows checks cannot replace native Mac builds and targeted AX tests. Remote CI results must be observed from actual runs rather than inferred from workflow files.

<a id="references"></a>
## Related records

- [v0.1.0 release notes](release-notes-v0.1.0.md): current content and distribution choices.
- [Known issues](../KNOWN_ISSUES.md): present limits, including Experimental macOS and event-only monitoring.
- [Changelog](../CHANGELOG.md): verified fixes and development history.
- [Implementation guides](guides-index.md): current build/run instructions and per-branch boundaries.
