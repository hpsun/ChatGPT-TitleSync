# 实现指南索引

[English](guides-index.md) · [项目说明](../README.zh-CN.md) · [v0.1.0发布说明](release-notes-v0.1.0.zh-CN.md) · [路线图](roadmap.zh-CN.md)

各实现以英文为主指南，另有独立中文版；Markdown 与 HTML 由同一正文生成。

| 实现 | 英文 | 中文 | 运行时／界面 |
| --- | --- | --- | --- |
| C# | [MD](../windows/csharp/README.md) · [HTML](../windows/csharp/README.html) | [MD](../windows/csharp/README.zh-CN.md) · [HTML](../windows/csharp/README.zh-CN.html) | Windows 托盘；.NET Framework |
| AHK Basic | [MD](../windows/ahk-v1.0/README.md) · [HTML](../windows/ahk-v1.0/README.html) | [MD](../windows/ahk-v1.0/README.zh-CN.md) · [HTML](../windows/ahk-v1.0/README.zh-CN.html) | Basic 1.0.48.05 ANSI x86；启动／运行时／IPC 路径需 ASCII |
| AHK v1.1 | [MD](../windows/ahk-v1.1/README.md) · [HTML](../windows/ahk-v1.1/README.html) | [MD](../windows/ahk-v1.1/README.zh-CN.md) · [HTML](../windows/ahk-v1.1/README.zh-CN.html) | Unicode v1.1.33+；x86/x64 |
| AHK v2 | [MD](../windows/ahk-v2/README.md) · [HTML](../windows/ahk-v2/README.html) | [MD](../windows/ahk-v2/README.zh-CN.md) · [HTML](../windows/ahk-v2/README.zh-CN.html) | v2.0+；x86/x64 |
| PowerShell | [MD](../windows/powershell/README.md) · [HTML](../windows/powershell/README.html) | [MD](../windows/powershell/README.zh-CN.md) · [HTML](../windows/powershell/README.zh-CN.html) | Windows PowerShell 5.1／Windows PowerShell 7 |
| Python | [MD](../windows/python/README.md) · [HTML](../windows/python/README.html) | [MD](../windows/python/README.zh-CN.md) · [HTML](../windows/python/README.zh-CN.html) | Windows Python 3；标准库 |
| Swift / Objective-C | [MD](../macos/README.md) · [HTML](../macos/README.html) | [MD](../macos/README.zh-CN.md) · [HTML](../macos/README.zh-CN.html) | Experimental；已记录原生客户端CI编译，真实AX／GUI待验收 |
| Go | [MD](../go/README.md) · [HTML](../go/README.html) | [MD](../go/README.zh-CN.md) · [HTML](../go/README.zh-CN.html) | Windows；Darwin cgo／AX 后端为实验源码 |
| Rust | [MD](../rust/README.md) · [HTML](../rust/README.html) | [MD](../rust/README.zh-CN.md) · [HTML](../rust/README.zh-CN.html) | Windows；macOS AX 后端为实验源码 |

## 名称替换帮助

[中文帮助](name-replacement.zh-CN.md) · [中文HTML](name-replacement.zh-CN.html) · [English guide](name-replacement.md) · [English HTML](name-replacement.html)

包含普通文字、正则、数字捕获组、当前名称选择、建议方案、顺序、预览、保存与取消、长度限制和完整原名回退。两种模式默认均为空规则；各语言指南另列配套组件的构建和打包方法。

## 指南覆盖与待验收项

各指南包含环境、构建或解释器运行、运行／停止／恢复、45 图标及当前三层策略，并说明各分支计时器／工作进程边界。前台缺省每2秒取新鲜来源，后台原生修复每秒一次，后台来源缺省每窗口 5 秒。每秒调度不等于冷 UIA 读取一秒完成。

[支持矩阵](../support-matrix.zh-CN.md) 按实际验证范围记录；见[本地验证与发布待办](release-readiness.zh-CN.md#local-validation)。源码测试和打包后 smoke 不是同一项。v0.1.0预览版已经公开，名称替换仍是功能分支、未建立新Release。当前Windows共享Unicode配套程序通过31／31项格式CLI用例，八种独立Windows前端实现的新完整桌面复测待开展。[CI `19cec808`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43124672990)及[CI `97858710`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43126332444)已编译Foundation helper和新增Swift／Objective-C客户端，同一套30项共享CLI通过；Go／Rust当时仍为旧baseline适配。最新AppleScript／helper边界、客户端恢复和新Go／Rust集成等待下一完整CI。全部Mac路线的真实AX、菜单、编辑器和登录验收仍为Experimental；此前仅静态冻结及真实窗口样本均属历史，不能替代当前验收。

正常恢复保留外部自定义标题。Windows 窗口标签不改变应用分组，macOS 窗口标题不重命名 Dock 应用。私有证据及对话名缓存不进入源码包。
