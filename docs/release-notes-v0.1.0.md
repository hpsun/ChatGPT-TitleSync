# ChatGPT-TitleSync v0.1.0 — initial public preview

[简体中文](release-notes-v0.1.0.zh-CN.md) · [HTML](release-notes-v0.1.0.html) · [Project home](../README.md) · [Known issues](../KNOWN_ISSUES.md) · [Changelog](../CHANGELOG.md)

Version **0.1.0**, recorded in the repository's `VERSION` file, is the first public preview of **ChatGPT-TitleSync**, Chinese name **ChatGPT 标题同步助手**. These notes describe the version's content; they do not assert that a remote release, tag or CI run has completed. The confirmed repository is [hpsun/ChatGPT-TitleSync](https://github.com/hpsun/ChatGPT-TitleSync).

## Current sign-in startup addition

Start at sign-in is part of this revision and **defaults on**, with a direct tray/menu check and a Save/Cancel settings checkbox. It is not deferred language work. Windows shares one current-user Run value and DWORD preference across implementations; overlong enable commands are rejected, and Exit does not cancel next-login registration. See the [startup guide](startup.md). Current real Windows retesting is **in progress**; the earlier nine-runtime table is historical, not acceptance of these new startup sources. macOS LaunchAgent/preferences source is Experimental and has not been compiled or run on a Mac.

## Contents

- [Included behavior](#included)
- [Rename and compatibility](#compatibility)
- [Verification scope](#verification)
- [Files, Releases and Packages](#distribution)
- [Deferred work and references](#next)

<a id="included"></a>
## Included behavior

The project offers independent Windows implementations in C#, AutoHotkey Basic/v1.1/v2, PowerShell, Python, Go and Rust, with English-primary and Chinese guides. Swift, Objective-C and the Go/Rust macOS backends are Experimental source.

Fresh settings default to **2-second foreground source checks** and **5-second source refresh per background window**. Lightweight native metadata/cached-caption repair remains independently scheduled every **1 second**. Valid existing settings remain effective, and explicit startup values override the corresponding saved values. A scheduling interval is not a cold-reader completion guarantee.

Foreground handling reads the current conversation name freshly. Background generic-caption resets may be repaired from an identity-bound verified cache. Identity checks, custom-caption protection, independent bounded reader roles and normal-exit restoration remain part of the policy. Windows taskbar grouping and the macOS Dock application name are not renamed.

<a id="compatibility"></a>
## Rename and compatibility

The visible product name, documentation, build artifact names and 45 asset filenames use **ChatGPT-TitleSync / ChatGPT 标题同步助手**. Descriptive source filenames can remain unchanged.

Existing state/configuration locations, shared IPC and lease identities are intentionally retained. Windows examples include `Local\TdxChatGptTitleStandalone` and `.Stop`, `%LOCALAPPDATA%\ChatGPT-title\...` settings, and existing `TdxChatGptTitles` logging locations. Keeping these identifiers preserves preferences and prevents an older controller and a renamed controller from concurrently owning the same window titles. Each implementation guide describes its retained locations. The current selected artwork is palette 45; older A1 observations remain historical.

<a id="verification"></a>
## Verification scope

Before the final product rename, nine Windows runtime routes were exercised: C#, AHK Basic, AHK v1.1, AHK v2, PowerShell 5.1, PowerShell 7, Python, Go and Rust. They reused the same three existing ChatGPT windows and checked source/header/native agreement, a valid foreground reset, a background reset, settings persistence/reopen/restore, and normal-exit caption restoration. These were targeted observations, not benchmarks, long-term reliability tests, installation coverage or guarantees for all ChatGPT versions. Bound native menu/settings-handler checks do not establish physical shell-right-click testing for every branch.

The final branding pass was checked separately with local rebuilding, syntax/source checks and isolated self-owned fixtures. That evidence verifies the rename/build paths without claiming another live ChatGPT acceptance run for the renamed UI. Earlier anomalies and corrections remain in the [changelog](../CHANGELOG.md) and [known issues](../KNOWN_ISSUES.md); they were not erased or relabelled.

The macOS branches have **not** completed a native Mac SDK build or actual Mac AX/window-title acceptance. Windows-side models and local fixtures do not establish Mac support. Workflow definitions are not a passing remote CI result. Exact scope is recorded in the [support matrix](../support-matrix.md) and [validation summary](release-readiness.md#local-validation).

<a id="distribution"></a>
## Files, Releases and Packages

v0.1.0 uses normal repository directories and individual source/document/icon files. **No project-produced ZIP is uploaded or offered as the project download.** Follow the chosen [implementation guide](guides-index.md) and keep its companion files and relative paths. A future frozen Python distribution needs its complete dependency directory; its EXE alone is not a runnable deployment. Basic is source-only and has no accepted compiled EXE.

Release notes can be attached to the actual GitHub Releases record when the publisher creates it; this document is not evidence that such a record already exists. **GitHub Packages is not used for the first release.** Runtime caches, private validation logs, downloaded SDKs and personal diagnostics stay outside the public source tree.

<a id="next"></a>
## Deferred work and references

Automatic system-language selection and a manual language override are planned for a later release, not implemented in v0.1.0. Palette 45 has been selected as the baseline; the eight palette choices and rotation settings are described in [icon settings](icon-themes.md). Native Mac verification is also pending. See the [roadmap](roadmap.md), [known issues](../KNOWN_ISSUES.md), [changelog](../CHANGELOG.md), and [project home](../README.md).
