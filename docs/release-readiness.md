# Release readiness: ChatGPT-TitleSync

[简体中文](release-readiness.zh-CN.md) · [Project home](../README.md)

**Status: the user explicitly approved public publication on 2026-11-11; publication is in progress. Remote CI success is not claimed. Earlier pending-approval snapshots are historical.** The Chinese product name is **ChatGPT 标题同步助手**. MIT was selected by the user; the repository LICENSE is required in the source package.

## Current sign-in startup addition

Start at sign-in is part of this revision and **defaults on**, with a direct tray/menu check and a Save/Cancel settings checkbox. It is not deferred language work. Windows shares one current-user Run value and DWORD preference across implementations; overlong enable commands are rejected, and Exit does not cancel next-login registration. See the [startup guide](startup.md). Current real Windows retesting is **in progress**; the earlier nine-runtime table is historical, not acceptance of these new startup sources. macOS LaunchAgent/preferences source is Experimental and has not been compiled or run on a Mac.

## Target protocol and acceptance boundary
The agreed target is three layers:

1. Read the foreground ChatGPT window's source freshly on the configurable foreground interval, default 2 seconds. Do not substitute a remembered source value for that foreground read.
2. Check known background windows' native identity/caption every second. If the app resets a caption to generic, restore the remembered title without reading its source again. Preserve a custom caption, discard changed identities, and do not invent a cache for an unknown window.
3. Refresh background sources at a configurable low frequency, default 5 seconds per window, using one serial background worker. This may establish a cache for previously unknown background windows. Foreground work has priority and must not wait on that background source queue. Commit only for the same identity and a generic or previously written native caption; protect custom names.

The Windows branches have controlled three-layer source/cache checks and local build/parse evidence. That is a local source-candidate review boundary, not a claim of full real-app acceptance for every language. Swift/Objective-C and the Go/Rust macOS backends remain **Experimental**: no native Mac SDK build or AX run has been performed. Earlier foreground-only fixtures are explicitly separated from the new protocol checks.

## Offline audit and repository file selection
Python 3.10+ and its standard library are sufficient:
```powershell
python -m unittest discover -s tools/tests -p "test_release_audit.py" -v
python tools/release_audit.py --allowlist --no-zip --output-dir "$env:TEMP/ChatGPT-TitleSync-file-review"
```

Before this directory is its own Git repository, --allowlist explicitly selects only reviewed source, documents and 45 assets. After local Git initialization/staging, omit --allowlist to check the tracked snapshot. Forbidden/unreviewed tracked files are rejected in either mode. Git-index mode also rejects a selected working file that differs from its staged content.

The audit checks required files, relative document links and anchors against the **package file set**, 2-second foreground / 5-second background default source markers, 45 asset hashes, the MIT file and an existing source checksum index. It rejects private runtime evidence, validation directories, logs, backups, SDKs, binaries, personal absolute paths and common credential-shaped strings. Pattern checks cannot recognize every real conversation name or secret; the selected snapshot still needs human review.

The accepted selection is committed as individual normal repository files: source directories, guides, shared 45 assets and required companion source. This publication does **not** upload a project ZIP. Use `git clone` or retrieve the files from the relevant language directory while keeping its documented dependencies. GitHub may generate source archives automatically; those are not project-uploaded ZIP assets. Local review archives from earlier preparation remain historical evidence and are not the delivery method.

The audit's `--no-zip` mode produces a machine-readable report and selected-file list without an archive. The publisher verifies selected bytes and creates the corresponding blobs/tree. The root `.gitattributes` uses `* -text` to preserve reviewed bytes across checkouts. Private runtime data and downloaded SDKs are excluded.

User approval on **2026-11-11** authorizes this public repository-file publication. It does not turn local tests into remote CI results or native Mac acceptance. The root publisher supplies the confirmed repository URL and records actual push/CI results separately.

<a id="local-validation"></a>
## Local validation
Current local evidence is scoped as follows:

| Check | Local result | Scope |
|---|---:|---|
| Release-audit synthetic boundaries | 12 passed | Allowlist, private links, token/path detection, staged private files, stale hashes, anchors, pending gate, raw-byte Git checkouts and ZIP bytes |
| C# controlled settings candidate | 41 policy + 13 helper/Job + 8 interval protocol + 12 settings passed | Synthetic/self-owned scope; the public 41 policy checks duplicate that policy set. Targeted real-window/settings results are recorded below. |
| PowerShell controlled settings candidate | 32 policy + 9 settings callbacks in each of 5.1 and 7 | Parser/native bridge and repeated atomic save passed in controlled scope. Targeted real-window/settings results are recorded below. |
| Go | 38 controlled checks passed | Policy/regression plus owned native settings controls and live rescheduling; targeted real ChatGPT/settings results are recorded below. |
| Rust | 30 controlled checks passed | Policy/regression plus owned native settings controls and live rescheduling; targeted real ChatGPT/settings results are recorded below. |
| Hidden-startup visibility | 2 owned reveal paths, in both PowerShell hosts | Actual STARTUPINFO Hidden; first native Show hidden, explicit reveal visible; offscreen, no activation or ChatGPT access. |
| Swift/Objective-C and Mac backends | Static review only | Experimental, not native compilation or AX verification |

Raw execution evidence, real process identifiers and conversation names remain local and are not linked or included in the public package. Source/build/fake checks are distinct from real application latency and native-Mac acceptance.

## CI definitions, not CI results
Both workflows use permissions: contents: read, checkout without persisted credentials, and no upload/release action.

- Windows checks: source audit, Go/Rust build and fake/owned fixtures, C# application compile plus fake states, and PowerShell syntax/native compile/fake states.
- macOS checks: **Experimental compile only** for Swift, Objective-C, Rust and Go. They never launch the AX monitors. Failures are not hidden as a successful Mac validation.
- The workflow files have **not run remotely**, and the repository must not display a passing CI/native-Mac claim in advance.

Official action documentation was checked for [checkout v7](https://github.com/actions/checkout) and [setup-go v7](https://github.com/actions/setup-go). CI deliberately pins Go 1.27.3 and Rust 1.82.0 to the locally used releases, not to a claimed latest language version. Rust is selected using the official [rustup toolchain mechanism](https://rust-lang.github.io/rustup/concepts/toolchains.html); Windows linker prerequisites are described by the [Rust installation documentation](https://rust-lang.org/tools/install/).

## Icons and delivery
45 is the selected baseline: [PNG](../assets/chatgpt-titlesync-icon.png), [Windows ICO](../assets/chatgpt-titlesync.ico), [macOS ICNS](../assets/chatgpt-titlesync.icns). Runtime fixed/random palettes affect the program's own tray and settings windows; the executable resource and pinned shortcuts remain fixed. Build and native verification differ by implementation; see [icon settings](icon-themes.md). Mac .app packaging, signing and notarization remain unverified.

The audit/selection tools make no network writes or startup changes. Actual repository creation and file publication are performed separately by the authorized publisher; no review ZIP is uploaded.

## Publication boundary
- Inspect the final selected file/tree snapshot and per-file checksums.
- User approval was explicitly given on 2026-11-11; public repository-file publication is in progress.
- Do not upload any local project review ZIP. Add the confirmed URL and actual outcome after publication.
- Remote CI has not run. Native Mac compile/runtime checks remain future work, so Mac stays Experimental.

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Targeted real Windows acceptance — 2026-11-11

Nine Windows runtime cases used the same three existing ChatGPT windows, reused across runs. Each case compared one source/header target, exercised one foreground generic-caption reset and one background reset, and checked three original generic captions after normal exit. Settings were invoked through the bound native command/same menu handler; this is not a physical shell-right-click claim. The numbers below are individual reset-to-first-match observations, not benchmarks, cold-reader deadlines or long-term/install/taskbar guarantees. No Mac source was compiled or run.

| Runtime | Settings | FG reset | BG reset | Exit |
| --- | --- | ---: | ---: | --- |
| C# | 2/5 → 3/10 reopen → 2/5 | 1384ms | 781ms | 3 original generic captions |
| AHK Basic 1.0 | 2/5 → 3/10 reopen → 2/5 | 1098ms | 632ms | 3 original generic captions |
| AHK v1.1 | 2/5 → 3/10 reopen → 2/5 | 2247ms | 667ms | 3 original generic captions |
| AHK v2 | 2/5 → 3/10 reopen → 2/5 | 1056ms | 409ms | 3 original generic captions |
| PowerShell 5.1 | 2/5 → 3/10 reopen → 2/5 | 881ms | 794ms | 3 original generic captions |
| PowerShell 7 | 2/5 → 3/10 reopen → 2/5 | 342ms | 282ms | 3 original generic captions |
| Python | 2/5 → 7/17 reopen → 2/5 | 161ms | 379ms | 3 original generic captions |
| Rust | 2/5 → 3/10 reopen → 2/5 | 1018ms | 624ms | 3 original generic captions |
| Go | 2/5 → 3/10 reopen → 2/5 | 1784ms | 448ms | 3 original generic captions |

Python's cold source sample still had a generic native caption; the later valid foreground-reset original-title fingerprint matched the independently observed source. Two earlier foreground guards did not inject a reset and remain preserved, not counted as product failures. Python combined separate launches of the same frozen executable; its final settings check verified disk values and exact reopened control text at 7/17, then restored 2/5 within one process. The earlier unexplained 33/10 observation is retained; it is not rewritten as a proven product defect. The earlier C# hidden-first-show defect remains historical evidence; the table uses the repaired final executable.
<!-- END TARGETED_WINDOWS_REAL -->
