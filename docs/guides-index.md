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
| Swift / Objective-C | [MD](../macos/README.md) · [HTML](../macos/README.html) | [MD](../macos/README.zh-CN.md) · [HTML](../macos/README.zh-CN.html) | Experimental; native Mac build/AX testing pending |
| Go | [MD](../go/README.md) · [HTML](../go/README.html) | [MD](../go/README.zh-CN.md) · [HTML](../go/README.zh-CN.html) | Windows; experimental Darwin cgo/AX backend |
| Rust | [MD](../rust/README.md) · [HTML](../rust/README.html) | [MD](../rust/README.zh-CN.md) · [HTML](../rust/README.zh-CN.html) | Windows; experimental macOS AX backend |

## Coverage and remaining acceptance

Guides cover requirements, build or interpreter invocation, run/stop/restore, 45 icon use and the current three-layer policy. Per-branch timer/worker limitations are stated in its guide. Foreground default: 2 seconds fresh source; native background repair: 1 second; background source default: 5 seconds per window. A one-second schedule is not a one-second cold UIA deadline.

The [support matrix](../support-matrix.md) records actual verification scope. See [local validation and remaining release work](release-readiness.md#local-validation). Current source tests and packaged smoke checks are distinct. Swift/Objective-C/Go/Rust macOS code remains Experimental until target-SDK build and real AX testing succeed. Local results do not assert remote CI or release completion; check the confirmed repository for actual records.

Normal restoration protects external custom captions. Windows caption labels do not change taskbar application grouping; macOS titles do not rename the Dock application. Private evidence and source-title caches stay outside the source package.
