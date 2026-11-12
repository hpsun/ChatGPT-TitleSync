# Release readiness: ChatGPT-TitleSync

[简体中文](release-readiness.zh-CN.md) · [Project home](../README.md)

**Status as of2026-11-12:** the [repository](https://github.com/hpsun/ChatGPT-TitleSync) and [v0.1.0 preview](https://github.com/hpsun/ChatGPT-TitleSync/releases/tag/v0.1.0) already exist. The development tree remains **0.1.0**, with **0.2.0** as the next target. This work has no release candidate or new Release; the existing public v0.1.0 preview does not deliver these unreleased changes. Product name remains ChatGPT-TitleSync / ChatGPT 标题同步助手. The user-selected MIT license and repository LICENSE remain required; earlier unpublished/approval-pending entries are historical.

## Existing sign-in startup contract

Start at sign-in already **defaults on**, with a direct tray/menu check and a Save/Cancel settings checkbox. Windows shares one current-user Run value and DWORD preference across implementations; overlong enable commands are rejected, and Exit does not cancel next-login registration. See the [startup guide](startup.md). Name replacement does not change that contract. Earlier nine-runtime settings/reset observations below belong to earlier source revisions and cannot establish acceptance of the new rules pipeline. macOS login/LaunchAgent behavior remains Experimental and has no real Mac acceptance.

## Name-replacement candidate

The shared editor's **Append — ChatGPT / 标题末尾显示ChatGPT** checkbox is checked by default and applies on **Save**. It is independent of **Enable name replacement** and row switches: empty or disabled replacement rules can still omit the program-added suffix. The optional shared JSON boolean `append_chatgpt_suffix` defaults to `true` when absent; it is not part of scan, icon or startup preferences.

The display pipeline starts with no private rules or automatic migration. Current-name samples come from private verified-raw snapshots; suggestions require explicit Use rule then Save. `--format` stays body-only; `--format --caption` returns a complete caption. Legal raw/body input is 512 UTF-16 units, normal captions at most 522; decodable invalid sources return whole raw without decoration, never truncation. Raw/restore/manual guards and source cadence stay unchanged. The four Python/AHK one-shot limitations are explicit in [the help](name-replacement.md#caption-protocol).

**Windows load boundary:** the owned formatting worker keeps its **1.5-second** deadline. Under load or slow startup it can time out and return the entire raw name plus the **default suffix**, so a saved `false` may not yet take effect. This failure is cached by raw name plus rules/helper identity; unchanged ticks do not retry it. Save the rules again, replace/change the helper identity, restart the monitor, or observe a different raw name to refresh that cache. The same isolated case succeeded in both PowerShell 5.1 and 7 when retested individually under lower load; earlier WorkerTimeout attempts remain evidence. This is not an unconditional pass or a promise of complete UI response within 1.5 seconds.

## Target protocol and acceptance boundary
The agreed target is three layers:

1. Read the foreground ChatGPT window's source freshly on the configurable foreground interval, default 2 seconds. Do not substitute a remembered source value for that foreground read.
2. Check known background windows' native identity/caption every second. If the app resets a caption to generic, restore the remembered title without reading its source again. Preserve a custom caption, discard changed identities, and do not invent a cache for an unknown window.
3. Refresh background sources at a configurable low frequency, default 5 seconds per window, using one serial background worker. This may establish a cache for previously unknown background windows. Foreground work has priority and must not wait on that background source queue. Commit only for the same identity and a generic or previously written native caption; protect custom names.

The Windows branches have controlled three-layer source/cache checks and local build/parse evidence. That is a local source-candidate review boundary, not a claim of full real-app acceptance for every language. All macOS backends remain **Experimental**. The actual SDK compilation/CLI checkpoint below must be distinguished from the current pending revisions and from real AX/menu/editor/login acceptance. Earlier foreground-only fixtures are explicitly separated from the new protocol checks.

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

User approval on **2026-11-11** covered the now-public repository-file publication and initial v0.1.0 preview. It does not turn local tests into remote CI results or native Mac acceptance. This feature branch is being verified separately and has not created another Release.

<a id="local-validation"></a>
## Local validation

<a id="current-suffix-verification"></a>
Current component evidence is separate from historical checks. Do not sum overlapping46/37 suites, duplicate shared cases per frontend or promote nested subcases to top-level counts.

| Component | Current evidence | Scope |
| --- | --- | --- |
| Windows common CLI |46/46:31 body + 15 caption |One shared suite, not multiplied by language. |
| Windows helper-specific suite |37 cases:22 retained body + 15 caption |Overlaps the common46; never add both totals. |
| C# / shared editor |10 display checks;13 never-shown editor checks |Owned fictional state/controls, no normal ChatGPT GUI. |
| PowerShell5.1 /7 |Same suffix-off case succeeded individually under lower load |Earlier WorkerTimeout/default-suffix-cache attempts remain; no unconditional pass. |
| Python |23 unit tests +14 private actual-helper checks |Owned files/processes and simulated ownership. |
| AHK Basic /1.1 /2 |17 caption checks per branch; old body fixtures23/19/19 |Basic remains source-only; fake native state, no normal desktop. |
| Go / Rust |20 top-level /21 test functions; a nine-case CLI matrix is inside one test |Windows controlled tests/builds; new suffix-native Mac CI pending. |
| Mac pre-suffix checkpoint1b7c33b |Four native builds;31 common CLI,5 I/O,3 recovery |No AX/GUI/login acceptance; newer suffix 46/client 7 needs its own CI. |

**Windows load boundary:** the owned formatting worker keeps its **1.5-second** deadline. Under load or slow startup it can time out and return the entire raw name plus the **default suffix**, so a saved `false` may not yet take effect. This failure is cached by raw name plus rules/helper identity; unchanged ticks do not retry it. Save the rules again, replace/change the helper identity, restart the monitor, or observe a different raw name to refresh that cache. The same isolated case succeeded in both PowerShell 5.1 and 7 when retested individually under lower load; earlier WorkerTimeout attempts remain evidence. This is not an unconditional pass or a promise of complete UI response within 1.5 seconds.

The selected Go/Rust checks above use private files and in-memory state, plus an exclusively owned no-UI protocol process. Two earlier unfiltered Go runs also exercised self-cleaning GUID-scoped temporary registry fixtures; those runs are not described as pure-file tests and did not use the real product Run/preference keys.

### Historical local source checks

The following counts are retained from the earlier source/settings revision. They do not count as verification of name replacement:

| Check | Local result | Scope |
|---|---:|---|
| Release-audit synthetic boundaries | 12 passed | Allowlist, private links, token/path detection, staged private files, stale hashes, anchors, pending gate, raw-byte Git checkouts and ZIP bytes |
| C# controlled settings candidate | 41 policy + 13 helper/Job + 8 interval protocol + 12 settings passed | Synthetic/self-owned scope; the public 41 policy checks duplicate that policy set. Targeted real-window/settings results are recorded below. |
| PowerShell controlled settings candidate | 32 policy + 9 settings callbacks in each of 5.1 and 7 | Parser/native bridge and repeated atomic save passed in controlled scope. Targeted real-window/settings results are recorded below. |
| Go | 38 controlled checks passed | Policy/regression plus owned native settings controls and live rescheduling; targeted real ChatGPT/settings results are recorded below. |
| Rust | 30 controlled checks passed | Policy/regression plus owned native settings controls and live rescheduling; targeted real ChatGPT/settings results are recorded below. |
| Hidden-startup visibility | 2 owned reveal paths, in both PowerShell hosts | Actual STARTUPINFO Hidden; first native Show hidden, explicit reveal visible; offscreen, no activation or ChatGPT access. |
| Mac backends at the earlier source freeze | Static review only at that time | Superseded for compilation scope by the dated remote checkpoint below; real AX/runtime verification is still missing |

Raw execution evidence, real process identifiers and conversation names remain local and are not linked or included in the public package. Source/build/fake checks are distinct from real application latency and native-Mac acceptance.

## Actual CI checkpoint and remaining gates

At [Mac CI checkpoint `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229), all **four native language builds** (Swift, Objective-C, Go and Rust), the **31 common formatter cases**, **five file-I/O cases** and **three client-recovery cases** passed. Shared AppleScript compilation still failed at reported location `:64` around variable `application` with error **-10003**; a minimal variable correction is prepared and awaits actual CI verification. The newer suffix revision's **46 common cases and seven client cases** require another native integration CI run and are **not covered by this checkpoint**. Real ChatGPT AX/title writes, editor/menu GUI and login behavior remain unverified; all Mac routes remain Experimental.

### Historical checkpoint before 1b7c33b

These retained paragraphs describe their then-current/pending revisions; the latest verified result and new pending suffix scope are above.

[macOS CI run 43124672990](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43124672990), commit `19cec8080908a15f0d0a8ccefa66209cb207bf71`, actually compiled the shared Foundation helper and the new Swift/Objective-C RulesClient integrations and passed the same **30 common format-CLI cases**. AppleScript compilation failed in that run. Go/Rust were still their older baseline adapters there; this checkpoint cannot be used for their new name-replacement adapters. A shared suite is counted once rather than multiplied by language.

The current helper revision `4B614FB1…D2C67DE`, AppleScript revision `9127B78F…7855E99`, added 31st Unicode fallback case, updated client negative-cache recovery and new Go/Rust adapters await the next complete CI result. Compilation and CLI success do not validate real Mac AX, menus, the AppKit editor, login startup, long-running operation or real title restoration. Mac remains Experimental.

The validation workflows check source/audit/build and controlled cases without launching normal AX monitors. Their read-only checks and checkout-without-persisted-credentials policy are distinct from the separate `release-preview.yml` job: that guarded job can write only the approved initial v0.1.0 Release after successful Windows checks on `main`, and leaves an existing v0.1.0 Release unchanged. It is not a feature-branch publishing gate or approval for another release. Failed CI steps remain failures; no overall-success claim is inferred from individually successful jobs.



Official action documentation was checked for [checkout v7](https://github.com/actions/checkout) and [setup-go v7](https://github.com/actions/setup-go). CI deliberately pins Go 1.27.3 and Rust 1.82.0 to the locally used releases, not to a claimed latest language version. Rust is selected using the official [rustup toolchain mechanism](https://rust-lang.github.io/rustup/concepts/toolchains.html); Windows linker prerequisites are described by the [Rust installation documentation](https://rust-lang.org/tools/install/).

## Icons and delivery
45 is the selected baseline: [PNG](../assets/chatgpt-titlesync-icon.png), [Windows ICO](../assets/chatgpt-titlesync.ico), [macOS ICNS](../assets/chatgpt-titlesync.icns). Runtime fixed/random palettes affect the program's own tray and settings windows; the executable resource and pinned shortcuts remain fixed. Build and native verification differ by implementation; see [icon settings](icon-themes.md). Mac .app packaging, signing and notarization remain unverified.

The audit/selection tools make no network writes or startup changes. Actual repository creation and file publication are performed separately by the authorized publisher; no review ZIP is uploaded.

## Publication boundary

- The [repository](https://github.com/hpsun/ChatGPT-TitleSync) and [v0.1.0 preview](https://github.com/hpsun/ChatGPT-TitleSync/releases/tag/v0.1.0) are public; the name-replacement feature branch has no new Release.
- Recheck the feature's selected file/tree snapshot, per-file checksums, companion packaging and current CI before merge. Earlier source freezes and targeted live results do not substitute for the changed files.
- Do not upload a local project review ZIP. The repository contains individual normal source/document/resource files; private evidence, actual rules, source snapshots, titles, identities and logs stay excluded.
- Record actual Windows controlled/CLI and Mac SDK/CLI evidence separately. Current normal Windows GUI and native Mac AX/menu/editor/login acceptance remain open for this feature.



<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Historical targeted real Windows acceptance — 2026-11-11

These measurements belong to an earlier frozen revision, not the name-replacement candidate. Nine Windows runtime cases used the same three existing ChatGPT windows, reused across runs. Each case compared one source/header target, exercised one foreground generic-caption reset and one background reset, and checked three original generic captions after normal exit. Settings were invoked through the bound native command/same menu handler; this is not a physical shell-right-click claim. The numbers below are individual reset-to-first-match observations, not benchmarks, cold-reader deadlines or long-term/install/taskbar guarantees. No Mac source was compiled or run as part of those historical Windows cases; later Mac CI is recorded separately above.

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
