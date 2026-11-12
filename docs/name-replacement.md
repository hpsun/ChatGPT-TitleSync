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

Opening the editor, choosing an example, previewing, or requesting suggestions does not save rules or change a window. Saved rules apply to the displayed conversation-name body; the independent suffix checkbox decides whether the usual ` — ChatGPT` is appended.

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

The overall **Enable name replacement** switch bypasses only the replacement list while preserving it; it does not change the suffix preference. Each row also has an enable switch. Enabled rules run from top to bottom, with each result becoming the next rule's input.

For example, first remove `Work / ` from `Work / draft plan`, then change `draft` to `final`. Reversing rules can produce a different result. Disabled rows remain available for later editing.

<a id="chatgpt-suffix"></a>
## ChatGPT suffix and complete captions

The shared editor's **Append — ChatGPT / 标题末尾显示ChatGPT** checkbox is checked by default and applies on **Save**. It is independent of **Enable name replacement** and row switches: empty or disabled replacement rules can still omit the program-added suffix. The optional shared JSON boolean `append_chatgpt_suffix` defaults to `true` when absent; it is not part of scan, icon or startup preferences.

Turning this checkbox off removes only the suffix added by this program, not matching text already contained in the original chat name. Choosing examples, requesting suggestions, previewing or cancelling does not commit this choice. Raw source names, source cadence, original-caption restoration and manually changed caption protection remain unchanged.

For example, this fictional configuration disables replacement and the added suffix independently:

```json
{
  "schema_version": 1,
  "enabled": false,
  "append_chatgpt_suffix": false,
  "revision": "00000000-0000-4000-8000-000000000001",
  "rules": []
}
```

<a id="caption-protocol"></a>
### Formatter protocol and bounds

`--format` retains its body-only behavior. Adding `--caption` returns the complete caption, which a caption-mode frontend uses directly instead of adding another suffix. A legal raw source and formatted body are limited to **512 UTF-16 units**; a normal full caption is at most **522 units**, including the optional ten-unit ` — ChatGPT` suffix. An existing configuration reaches the caption formatter even when replacement rules are empty or disabled.

A decodable invalid source (over512 units or containing control characters) is returned as the **entire original raw input without an added suffix**, never truncated. This diagnostic fallback can exceed the normal valid-caption limit. Malformed UTF-16 remains a protocol/I/O failure. Normal source readers enforce their own bounds before display processing.

**Windows load boundary:** the owned formatting worker keeps its **1.5-second** deadline. Under load or slow startup it can time out and return the entire raw name plus the **default suffix**, so a saved `false` may not yet take effect. This failure is cached by raw name plus rules/helper identity; unchanged ticks do not retry it. Save the rules again, replace/change the helper identity, restart the monitor, or observe a different raw name to refresh that cache. The same isolated case succeeded in both PowerShell 5.1 and 7 when retested individually under lower load; earlier WorkerTimeout attempts remain evidence. This is not an unconditional pass or a promise of complete UI response within 1.5 seconds.

### One-shot mode limitation in four Windows frontends

In the current Python, AHK Basic1.0, AHK1.1 and AHK2 products, `--once` skips the rules client entirely. It therefore ignores saved replacement rules **and** `append_chatgpt_suffix=false` and uses the raw name plus the default suffix. This is a current product limitation, separate from compatibility of the legacy body-only formatter API. Resident-mode behavior does not establish that one-shot mode honors the setting.

## Errors and safe fallback

An enabled rule needs a nonempty Find field. Invalid patterns or capture references prevent saving. A blank Replace field is allowed.

A handled rule failure uses the whole raw name rather than a partial transformation and respects the saved suffix choice when the companion completes successfully. If the worker cannot run or reaches the caller deadline, the local safe-default/cached-failure limitation above applies.

Rules are limited to 32 rows; Find and Replace each allow 512 UTF-16 code units, and the resulting name body may not exceed 512 units. Most common characters use one unit; an emoji often uses two. The editor reports invalid limits rather than silently truncating.

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

## Development and verification status

The development tree remains **0.1.0**, with **0.2.0** as the next target. This work has no release candidate or new Release; the existing public v0.1.0 preview does not deliver these unreleased changes.

Windows passed **46/46 common CLI cases** (31 body + 15 caption). The separate helper-specific **37-case** suite (22 retained body + 15 caption) overlaps those cases and is not added to46. C# display checks 10 and never-shown editor checks 13 passed; these are controlled component results, not normal-desktop acceptance.

At [Mac CI checkpoint `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229), all **four native language builds** (Swift, Objective-C, Go and Rust), the **31 common formatter cases**, **five file-I/O cases** and **three client-recovery cases** passed. Shared AppleScript compilation still failed at reported location `:64` around variable `application` with error **-10003**; a minimal variable correction is prepared and awaits actual CI verification. The newer suffix revision's **46 common cases and seven client cases** require another native integration CI run and are **not covered by this checkpoint**. Real ChatGPT AX/title writes, editor/menu GUI and login behavior remain unverified; all Mac routes remain Experimental.
