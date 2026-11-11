# ChatGPT-TitleSync v0.1.0 — 首次公开预览

[English](release-notes-v0.1.0.md) · [HTML](release-notes-v0.1.0.zh-CN.html) · [项目说明](../README.zh-CN.md) · [已知问题](../KNOWN_ISSUES.zh-CN.md) · [修改记录](../CHANGELOG.zh-CN.md)

仓库 `VERSION` 文件登记 **0.1.0**，作为 **ChatGPT-TitleSync / ChatGPT 标题同步助手**首次公开预览。本说明记录该版本的内容，不代表远端 Release、标签或 CI 已经完成。已确认仓库为 [hpsun/ChatGPT-TitleSync](https://github.com/hpsun/ChatGPT-TitleSync)。

## 本次加入登录自启动

登录自启动已纳入本次修订，**缺省已开**；托盘／菜单可直接勾选，设置中同项按保存提交、取消不改。这不是延后版的语言功能。Windows各实现共用当前用户Run值和DWORD偏好；启用超长命令会被拒绝，退出不取消下次登录登记。见[启动说明](startup.zh-CN.md)。当前真实Windows复测**正在进行**，此前九路线表是历史记录，不能替代新启动源码的验收。Mac LaunchAgent及偏好仅为Experimental源码，未在Mac编译或运行。

## 目录

- [本版行为](#included)
- [改名与兼容](#compatibility)
- [验证范围](#verification)
- [文件、Releases 与 Packages](#distribution)
- [后续工作与参考](#next)

<a id="included"></a>
## 本版行为

项目包含 Windows 上独立实现的 C#、AutoHotkey Basic／v1.1／v2、PowerShell、Python、Go、Rust，并提供英文主指南及中文版。Swift、Objective-C 和 Go／Rust 的 macOS 后端仍为实验源码。

首次缺省前台每 **2秒**检查新鲜来源，后台来源每窗口 **5秒**刷新；轻量级原生元数据／缓存标题恢复仍独立每 **1秒**检查。已有合法设置继续生效，显式启动参数覆盖对应已保存值。调度间隔不保证冷启动读取在同样时限内完成。

前台直接读取当前对话名。后台原生标题被改回通用名时，可根据绑定同一窗口身份的已核实缓存恢复。窗口身份核对、外部自定义标题保护、前后台独立有界读取器及正常退出恢复继续保留；不重命名 Windows 任务栏应用分组或 macOS Dock 应用名。

<a id="compatibility"></a>
## 改名与兼容

可见产品名、文档、构建产物名及 45 资产文件名统一为 **ChatGPT-TitleSync / ChatGPT 标题同步助手**；描述性源文件名可以保留。

原有状态／设置位置、共用 IPC 及租约身份有意保留。Windows 示例包括 `Local\TdxChatGptTitleStandalone` 及 `.Stop`、`%LOCALAPPDATA%\ChatGPT-title\...` 设置和既有 `TdxChatGptTitles` 日志目录。这样继承原设置，并避免旧控制器与改名后控制器同时拥有、改写同一窗口标题。各实现指南分别说明保留位置。当前所选图标为45号；旧A1观测保留为历史。

<a id="verification"></a>
## 验证范围

最终改名之前，已真实运行九条 Windows 路线：C#、AHK Basic、AHK v1.1、AHK v2、PowerShell 5.1、PowerShell 7、Python、Go、Rust。它们复用了相同三个既有 ChatGPT 窗口，核对来源／头部／原生标题，完成有效前台重置、后台重置、设置持久化／重开／恢复以及正常退出后的标题恢复。这是针对性观察，不是性能排名、长期可靠性、安装验收或所有 ChatGPT 版本保证。绑定原生命令调用菜单／设置处理器，不代表每个分支均完成任务栏物理右键实测。

最终品牌改名另行通过本地重编译、语法／源码检查及隔离自有夹具验证；这些证据核对改名和构建路径，不冒充改名界面又完成一轮真实 ChatGPT 验收。此前异常和修正继续保留在[修改记录](../CHANGELOG.zh-CN.md)及[已知问题](../KNOWN_ISSUES.zh-CN.md)，未删除或改写性质。

macOS 分支**尚未完成真实 Mac SDK 构建或 Mac AX／窗口标题验收**。Windows 上的模型及本地夹具不能证明 Mac 支持；工作流文件也不等于远程 CI 已通过。具体边界见[支持矩阵](../support-matrix.zh-CN.md)与[验证记录](release-readiness.zh-CN.md#local-validation)。

<a id="distribution"></a>
## 文件、Releases 与 Packages

v0.1.0 按正常仓库目录逐文件提供源码、文档和图标，**不上传或提供项目制作的 ZIP 下载**。按所选[实现指南](guides-index.zh-CN.md)保留依赖文件及相对路径。以后若提供 Python 冻结程序，须同时提供完整依赖目录，不能把单独 EXE 当作可运行交付。Basic 只提供源码，没有已验收的编译 EXE。

发布者建立真实 GitHub Releases 记录时，可采用本版说明；本文件不证明远端已经有该记录。**首版不使用 GitHub Packages。**运行缓存、私有验收日志、下载的 SDK 和个人诊断不进入公开源码树。

<a id="next"></a>
## 后续工作与参考

按系统语言自动选择界面语言，以及用户手工覆盖，安排到后续版；v0.1.0 尚未实现。已选定45号为基准，八色配色及轮换设置见[图标设置](icon-themes.zh-CN.md)；真实 Mac 验证也待做。参见[路线图](roadmap.zh-CN.md)、[已知问题](../KNOWN_ISSUES.zh-CN.md)、[修改记录](../CHANGELOG.zh-CN.md)和[项目说明](../README.zh-CN.md)。
