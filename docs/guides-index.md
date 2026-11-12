# Implementation guides

[简体中文](guides-index.zh-CN.md) · [Project home](../README.md) · [v0.1.0 notes](release-notes-v0.1.0.md) · [Roadmap](roadmap.md)

Each implementation has an English primary guide and an independent Chinese guide. Markdown and HTML are generated from the same body.

| Implementation | English | Chinese | Runtime / interface |
| --- | --- | --- | --- |
| C# | [MD](../windows/csharp/README.md) · [HTML](../windows/csharp/README.html) | [MD](../windows/csharp/README.zh-CN.md) · [HTML](../windows/csharp/README.zh-CN.html) | Windows tray; .NET Framework |
| AHK Basic | [MD](../windows/ahk-v1.0/README.md) · [HTML](../windows/ahk-v1.0/README.html) | [MD](../windows/ahk-v1.0/README.zh-CN.md) · [HTML](../windows/ahk-v1.0/README.zh-CN.html) | Basic 1.0.48.05 ANSI x86; ASCII launch/runtime/IPC paths |
| AHK v1.1 | [MD](../windows/ahk-v1.1/README.md) · [HTML](../windows/ahk-v1.1/README.html) | [MD](../windows/ahk-v1.1/README.zh-CN.md) · [HTML](../windows/ahk-v1.1/README.zh-CN.html) | Unicode v1.1.33+; x86/x64 |
| AHK v2 | [MD](../windows/ahk-v2/README.md) · [HTML](../windows/ahk-v2/README.html) | [MD](../windows/ahk-v2/README.zh-CN.md) · [HTML](../windows/ahk-v2/README.zh-CN.html) | v2.0+; x86/x64 |
| PowerShell | [MD](../windows/powershell/README.md) · [HTML](../windows/powershell/README.html) | [MD](../windows/powershell/README.zh-CN.md) · [HTML](../windows/powershell/README.zh-CN.html) | Windows PowerShell 5.1 / PowerShell 7 on Windows |
| Python | [MD](../windows/python/README.md) · [HTML](../windows/python/README.html) | [MD](../windows/python/README.zh-CN.md) · [HTML](../windows/python/README.zh-CN.html) | Windows Python 3; standard library |
| Swift / Objective-C | [MD](../macos/README.md) · [HTML](../macos/README.html) | [MD](../macos/README.zh-CN.md) · [HTML](../macos/README.zh-CN.html) | Experimental; native-client CI compilation recorded; real AX/GUI testing pending |
| Go | [MD](../go/README.md) · [HTML](../go/README.html) | [MD](../go/README.zh-CN.md) · [HTML](../go/README.zh-CN.html) | Windows; experimental Darwin cgo/AX backend |
| Rust | [MD](../rust/README.md) · [HTML](../rust/README.html) | [MD](../rust/README.zh-CN.md) · [HTML](../rust/README.zh-CN.html) | Windows; experimental macOS AX backend |

## Name replacement help

[English guide](name-replacement.md) · [English HTML](name-replacement.html) · [中文帮助](name-replacement.zh-CN.md) · [中文HTML](name-replacement.zh-CN.html)

The guide covers plain-text and regex modes, numeric captures, example selection, suggestions, ordering, preview, Save/Cancel, limits and complete-original fallback. Both modes default to an empty list; language-specific companion build/packaging instructions are in each implementation guide.

## Coverage and remaining acceptance

Guides cover requirements, build or interpreter invocation, run/stop/restore, 45 icon use and the current three-layer policy. Per-branch timer/worker limitations are stated in its guide. Foreground default: 2 seconds fresh source; native background repair: 1 second; background source default: 5 seconds per window. A one-second schedule is not a one-second cold UIA deadline.

The [support matrix](../support-matrix.md) records actual verification scope. See [local validation and remaining release work](release-readiness.md#local-validation). Current source tests and packaged smoke checks are distinct. The v0.1.0 preview is already public, while name replacement remains a feature branch without a new Release. The current Windows shared Unicode companion passed 31/31 format-CLI cases; full new desktop retesting of the eight independent Windows frontend implementations is pending. At [CI `19cec808`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43124672990) and [CI `97858710`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43126332444), the Foundation helper and new Swift/Objective-C clients compiled and the same 30 shared CLI cases passed; Go/Rust were still older baseline adapters. Latest AppleScript/helper boundaries, client recovery and new Go/Rust integration await the next complete CI. All Mac routes remain Experimental for real AX, menu, editor and login acceptance. Earlier static-only freezes and real-window samples are historical, not current acceptance.

Normal restoration protects external custom captions. Windows caption labels do not change taskbar application grouping; macOS titles do not rename the Dock application. Private evidence and source-title caches stay outside the source package.
