# Name replacement

[English](name-replacement.md) · [简体中文](name-replacement.zh-CN.md) · [HTML](name-replacement.html) · [Project home](../README.md)

Change how a conversation name appears in the local ChatGPT window title. The conversation stored in ChatGPT keeps its original name. Rules start empty: the program does not import another program's rules or include personal prefixes.

## Open the editor

Choose **Name replacement…** from the tray menu, or use the button in Settings. The rule editor is a separate companion packaged with the selected implementation. Keep the companion beside the program when distributing a compiled build.

1. Select an observed conversation name from **Current conversations**, or enter a fictional/manual sample.
2. Add a rule and choose **Plain text** or **Regular expression**.
3. Enter **Find** and **Replace**. A blank replacement removes the matched text.
4. Inspect the preview. Use **Move up** and **Move down** to set execution order.
5. Select **Save** to apply. **Cancel** discards the draft.

Opening the editor, choosing an example, previewing, or requesting suggestions does not save rules or change a window. Saved rules apply to the displayed conversation name before the usual ` — ChatGPT` suffix.

## Pick a current conversation name

The dropdown uses raw names already verified by the running monitor. Its timestamp helps identify an older snapshot. It does not scan the chat history or send content to a server.

If no names are available, activate the relevant ChatGPT windows and let the normal monitor observe them, or use a manual example. A background window that has not yet been observed may be absent. Selecting a name copies it into the sample field; it does not rename the chat.

The monitor keeps the original name separately from the display result. Rule changes do not trigger extra ChatGPT source reads or reset the foreground/background scan intervals.

## Plain-text replacement

Choose this mode for exact text. Matching is case-sensitive and replaces every non-overlapping occurrence. Punctuation, dollar signs, and backslashes are ordinary characters.

| Sample name | Find | Replace | Preview |
|---|---|---|---|
| `Work / Example chat A` | `Work / ` | empty | `Example chat A` |
| `draft plan — draft notes` | `draft` | `final` | `final plan — final notes` |
| `Price $1` | `$1` | `$2` | `Price $2` |

`Work` and `work` are different. A dot finds an actual dot in this mode.

## Regular-expression replacement

Choose this mode to match a structure. The following examples are illustrative; none is installed as a default rule.

| Purpose | Sample | Find | Replace | Preview |
|---|---|---|---|---|
| Remove an exact prefix | `Work / Example chat A` | `^Work / ` | empty | `Example chat A` |
| Keep the part after a slash | `Team / Example chat B` | `^[^/]+/\s*(.+)$` | `${1}` | `Example chat B` |
| Extract a whole bracketed name | `[Example chat C]` | `^\[([^\]]+)\]$` | `${1}` | `Example chat C` |
| Exchange two parts | `North / South` | `^(.+) / (.+)$` | `$2 — $1` | `South — North` |
| Match a literal dot | `Example.v2` | `\.` | `-` | `Example-v2` |

### Common pattern symbols

| Symbol | Meaning |
|---|---|
| `^` and `$` | Start and end of the name |
| `.` | A character; escape it as `\.` to find a dot |
| `(...)` | Capture a part for use in the replacement |
| `+`, `*`, `?` | Repeat one or more, zero or more, or make optional |
| `[abc]`, `[^/]` | A character from a set, or a character except slash |
| `\s` | Whitespace |
| `\` | Escape a pattern character such as `\[`, `\(`, or `\.` |

### Capture references in Replace

Use `$1` or `${1}` for the first capture, through `$99`/`${99}`. `$0` or `${0}` inserts the whole match. `$$` inserts a literal dollar sign. A valid optional capture that did not match inserts an empty string. A reference to a group that does not exist is rejected.

These references apply only in regular-expression mode. For example, `${1}` is literal text in plain-text mode. The replacement field does not interpret `\1` as a capture reference.

Windows uses .NET regular expressions; macOS uses Foundation `NSRegularExpression`. Common patterns above are intended for both. Advanced syntax and Unicode matching can differ between these engines; test on the target platform. A rule containing an engine-specific feature is not guaranteed portable merely because the JSON file can be read.

## Suggested rules

Select a sample name, then choose **Suggest**. Available suggestions are derived locally from the sample's structure or selected text, such as removing a prefix, keeping text after a separator, or extracting a paired-delimiter segment.

Each candidate shows its purpose, pattern, replacement, and result. Inspect them and choose **Use rule** to add one to the draft; only **Save** commits it. Suggestions can change meaning when used with another name, so preview at least two representative examples when practical.

Suggestions do not rewrite all chats, edit their stored names, or install machine-specific defaults. If the sample has no suitable structure, write a plain-text rule or enter a pattern yourself.

## Rule order and switches

The overall switch bypasses the list while preserving it. Each row also has an enable switch. Enabled rules run from top to bottom, with each result becoming the next rule's input.

For example, first remove `Work / ` from `Work / draft plan`, then change `draft` to `final`. Reversing rules can produce a different result. Disabled rows remain available for later editing.

## Errors and safe fallback

An enabled rule needs a nonempty Find field. Invalid patterns or capture references prevent saving. A blank Replace field is allowed.

If applying the list fails, takes too long, or produces a blank name, control characters, an oversized name, or only `ChatGPT`, the whole operation falls back to the complete original conversation name. A partly transformed name is not used.

Rules are limited to 32 rows; Find and Replace each allow 512 UTF-16 code units, and the resulting name may not exceed 512 units. Most common characters use one unit; an emoji often uses two. The editor reports invalid limits rather than silently truncating.

Windows matches have a 100 ms per-expression timeout and a 500 ms aggregate budget. A separate formatting process also has a 1.5-second caller deadline. macOS relies on the disposable process deadline for a hard boundary. Preview and monitor formatting do not run unbounded expressions on the UI thread.

While a new result is pending, the last owned caption may remain until the next display update. A title manually changed by another application remains protected by the monitor's existing ownership checks. Normal exit still attempts to restore the original native caption.

## Local files and privacy

Rules are shared by the language implementations on the same operating system:

- Windows: `%LOCALAPPDATA%\ChatGPT-TitleSync\title-rules.json`.
- macOS: `~/Library/Application Support/ChatGPT-TitleSync/title-rules.json`.

An absent file means an empty rule list. Only an explicit successful Save creates or changes this preference. The editor validates and saves atomically; changing intervals, icons, or startup does not overwrite the rules.

Observed names use a separate private runtime snapshot. They are not copied into the rule file unless you deliberately include text in a rule. Do not publish your own rule files, runtime snapshots, or screenshots containing real conversation names. The distributed examples use fictional names.

## Build and verification

All Windows implementations use the packaged Unicode companion for the same rule semantics, including the ANSI-era AHK Basic implementation. macOS implementations use the Foundation companion. See the [guide index](guides-index.md) for language-specific build/run instructions.

Compilation, controlled format tests, source acquisition, and real desktop acceptance are separate checks. Consult the [support matrix](../support-matrix.md) for the current verified scope; an Experimental Mac label remains in effect until native runtime behavior is verified.
