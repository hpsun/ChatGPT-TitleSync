# 已知问题与验证边界

[English](KNOWN_ISSUES.md) · [HTML](KNOWN_ISSUES.zh-CN.html) · [变更记录](CHANGELOG.zh-CN.md) · [支持矩阵](support-matrix.zh-CN.md)

快照：**2026-11-12，北京时间**。开发树版本仍为 **0.1.0**，下一目标为 **0.2.0**；本次未建立发布候选（RC）或新 Release，已有公开 v0.1.0 预览不代表这些尚未发布的改动已经交付。历史观察保留原修订范围，已修复项见[变更记录](CHANGELOG.zh-CN.md)。

<a id="event-only-monitoring-is-not-implemented"></a>
<a id="format-worker-deadline-under-load"></a>
## 负载下格式化截止与缓存回退

**Windows 负载边界：**自有格式化 worker 的截止仍为 **1.5 秒**。负载竞争或启动缓慢可导致超时，回退为完整原名加**缺省后缀**，因此保存的 `false` 可能尚未生效。失败按原名及规则/辅助程序身份缓存，条件不变的轮询不会重试；重新保存规则、替换/改变辅助程序身份、重启监听，或观测到不同原名，才会刷新该缓存。降低负载后，两种 PowerShell host（5.1、7）分别单独复测同项成功，之前 WorkerTimeout 现场仍保留；不能据此宣称无条件通过，也不承诺完整界面响应必在1.5秒内完成。

共享编辑器的 **Append — ChatGPT / 标题末尾显示ChatGPT** 复选框缺省勾选，按**保存**生效，与 **Enable name replacement** 及逐行开关独立：替换规则为空或停用时仍可关闭程序追加的后缀。共享 JSON 可选布尔项 `append_chatgpt_suffix` 缺项按 `true`，不属于扫描、图标或启动项偏好。

详见[完整标题边界](docs/name-replacement.zh-CN.md#caption-protocol)；原始名/恢复凭据与手工改名保护不变。

## 一次检查模式的设置限制

Python、AHK Basic1.0、AHK1.1和AHK2当前在 `--once` 跳过规则客户端，忽略已保存替换和关闭尾巴设置，采用原名加缺省尾巴。这是产品限制，不能以旧API兼容性含糊称用户选项已生效。

## 尚未实现纯事件监听

一次有界Windows实验仅为一个文档NameProperty订阅TreeScope.Element，两次来源变化另有独立确认，但60秒内未收到属性回调。原生前台/对象名称元数据事件有到达，但也可能来自本程序自身改写窗口标题，尚未证明可可靠表示对话变化。

本次没有订阅页头文本，也未重绑替换后的文档/提供方，**不能证明所有事件路径都不可用**。生产继续采用可配置的前台来源缺省**2秒**、后台每窗**5秒**、原生缓存标题修复**1秒**。事件加速须先单独验证通知可靠性与自写反馈，再考虑替代兜底。

## macOS仍为Experimental，未经原生验证

在 [Mac CI 检查点 `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229)，**四种原生语言构建**（Swift、Objective-C、Go、Rust）、**31项共同格式化**、**5项文件I/O**及**3项客户端恢复**均通过；共享 AppleScript 编译仍在报告位置 `:64` 的 `application` 变量附近报 **-10003**，最小修正待验证。更新后缀修订的 **46项共同用例及7项客户端**仍须另一轮原生整合CI，**不在此检查点覆盖范围内**。真实ChatGPT AX/标题写入、编辑器/菜单GUI和登录行为未验证，Mac路线继续为Experimental。

下段保留首次CI之前的历史冻结说明，不是当前SDK状态：

> **Swift、Objective-C、Go/Darwin、Rust/macOS**四分支均未在真实Mac验收。原生菜单草稿与公开AppleScriptObjC伴随程序只经过源码复核；Windows侧模型不等于Mac SDK编译、AX权限/提供方、标题可写、焦点、封装或时延验证。仍需真实Mac构建与专项运行。见[Mac指南](macos/README.zh-CN.md)。

## AutoHotkey Basic没有已验收编译EXE

已验证路线为源码配**AutoHotkey Basic1.0.48.05 ANSI x86**解释器。旧编译器尝试失败或超时，残留产物不交付。即使原生标题使用UTF-16缓冲，源码/运行时/IPC路径及托盘文字仍有该分支ASCII限制；不能换现代Unicode运行时/base后宣称Basic兼容。见[Basic指南](windows/ahk-v1.0/README.zh-CN.md)。

## 计时与界面覆盖有限

- 较早源码修订的九种Windows运行方式通过设置、来源、重置修复及正常退出专项，复用同3个现存窗口，不等于长期可靠性、比较基准、完整安装或所有版本保证。
- 设置/菜单处理器由绑定原生指令调用；没有逐分支独立验收系统托盘物理右键及全部任务栏布局。
- 来源间隔是调度间隔，不承诺冷UIA读取或串行后台队列全部项目在该周期内完成。
- 辅助层级变化或不可用时，有界来源读取可能失败；应拒绝本次读取，而不是猜侧栏名称或扫描聊天正文。更广泛提供方/版本兼容仍需验证。
- Python原验收中的两次守卫跳过及一次无法解释的设置回读观察均保留，没有改写成产品失败；独立后续补证确认了最终修复路径和精确持久化/重开值，原始诊断留在私有证据中。

准确范围与各次观测见[支持矩阵](support-matrix.zh-CN.md)。

## 发布后查看真实远端CI

在 [Mac CI 检查点 `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229)，**四种原生语言构建**（Swift、Objective-C、Go、Rust）、**31项共同格式化**、**5项文件I/O**及**3项客户端恢复**均通过；共享 AppleScript 编译仍在报告位置 `:64` 的 `application` 变量附近报 **-10003**，最小修正待验证。更新后缀修订的 **46项共同用例及7项客户端**仍须另一轮原生整合CI，**不在此检查点覆盖范围内**。真实ChatGPT AX/标题写入、编辑器/菜单GUI和登录行为未验证，Mac路线继续为Experimental。

保留首次发布时的历史说明（编译状态已由上方实际检查点更新）：

> 本文冻结时Windows及Experimental macOS工作流尚未远端运行。本地通过不等于GitHub Actions通过；首次push后须查看实际运行，并用真实Issue/提交记录失败和修复，不能预先放通过徽章或宣称Mac原生通过。

## 报告新问题

请提供实现/运行时、系统与应用版本、最小复现、预期与实际行为，并区分来源读取、原生标题写入、设置保存或窗口可见性问题。上传前脱敏：缓存、原始日志和截图可能含对话名、机器路径及账户信息，不能原样公开这些私有材料。
