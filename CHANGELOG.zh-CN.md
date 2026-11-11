# 变更记录

[English](CHANGELOG.md) · [HTML](CHANGELOG.zh-CN.html) · [已知问题](KNOWN_ISSUES.zh-CN.md) · [项目主页](README.zh-CN.md)

以下记录首次公开源码发布前的真实本地开发与验证日期，统一为**北京时间**，不冒充历史Git提交日期、版本标签或虚构GitHub Issue编号。后续公开修复应在实际Issue、提交或Release建立后引用真实链接。

## 2026-11-11 — 公开发布后的macOS CI运行环境修正

首次公开源码提交 `4024f41be4792372e574168c938e4a6a3da6766c` 的[macOS仅编译运行（42985821518）](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/42985821518)结果为**已取消**。Swift、Objective-C、Rust、Go四个作业均未分配runner，且没有执行任何步骤。每个作业的注解原文均为：`The configuration 'macos-14-arm64-us-default' is not supported`。源码检出和编译均未开始；该次运行没有产生源码编译结论，也没有提供费用问题的证据。

GitHub的[macOS 14退役官方公告](https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/)确认该环境于2026-11-02退役，并列出可迁移的运行环境标签。本次将工作流从`macos-14`改为固定的`macos-15`。迁移后的验证**仍待后续GitHub Actions真实运行结果**，不能仅凭工作流修改宣称编译成功。即使仅编译运行成功，原生AX行为、设置、图标和登录自启动仍须另行验证。下方较早的发布候选记录保留其原始文档冻结时的验证状态。

## 2026-11-11 — 发布候选与Windows实测

### 新增与调整

- 共享45图标；C#、AHK Basic/v1.1/v2、PowerShell、Python、Go、Rust、Swift、Objective-C各自实现，配英中文构建运行指南。
- 首次运行缺省**前台来源2秒、各后台来源5秒**。已有合法保存值继续有效，显式启动参数覆盖对应保存值；原生缓存标题维护仍独立每1秒调度。
- 托盘/菜单设置保存前后台间隔，并在现有驻留控制器中重排调度，旧设置代次的结果不再提交。前台使用新来源；已知后台通用标题回改可由同身份缓存修复。
- Windows工作流加入PowerShell5.1/7下的[设置与隐藏启动回归](tools/test-tray-settings.ps1)；[源码审计](tools/release_audit.py)将缓存、日志、私有诊断、下载工具链及二进制排除在源码包外。

### 已修复

| 实际问题 | 原因与修正 | 验证及公开依据 |
| --- | --- | --- |
| Hidden启动后，第一次设置窗口可能已有完整控件却仍不可见。 | STARTUPINFO.wShowWindow可覆盖首次普通ShowWindow请求。Go、Rust、C#、PowerShell设置路径使用SetWindowPos显式显示自有窗口，不再仅依赖第一次Show；C#/PS另行请求激活。这是原生可见性问题，不能据此认定UI Automation无法定位控件。 | 自有WinExe确认真实Hidden启动标记、初始原生Show隐藏、显式显示成功且前台不变；最终运行程序设置闭环通过。见[C#](windows/csharp/App.cs)、[PS](windows/powershell/ChatGPT-TitleSync.ps1)、[Go](go/tray_windows.go)、[Rust](rust/src/tray_windows.rs)、[回归夹具](tools/tests/startup_hidden_fixture.cs)。 |
| C#较慢来源间隔可能被误认为读者无响应；父程序只按同一间隔消费时也可能错过新鲜快照。 | 来源观察序列/时间与1秒心跳序列/时间分开。Helper按用户间隔实际读取，父程序按原生维护节拍消费新观察；健康来源间隙不反复取消独立后台角色。 | 冷附着、长间隔、新序列、角色变化及旧观察拒绝的受控检查。见[监听器](windows/csharp/TitleMonitor.cs)、[读取器](windows/csharp/TitleReader.cs)。 |

### 实测及边界

Windows九种运行方式均已真实运行：C#、AHK Basic、AHK v1.1、AHK v2、PowerShell5.1、PowerShell7、Python、Go、Rust。各次复用同3个现存窗口，完成有效前台/后台通用标题重置、设置保存重开还原、来源/页头对照及正常退出观察。Python最终设置补证使用7/17秒，其余使用3/10，最后均还原2/5。

复原毫秒数只是单次观测，**不是基准或性能排名**。实测调用绑定原生设置/同一菜单处理器，不冒称逐版完成了系统托盘物理右键、长期驻留、安装流程或所有ChatGPT版本验收。详见[支持矩阵](support-matrix.zh-CN.md)与[验证说明](docs/release-readiness.zh-CN.md#local-validation)。

Mac四分支——Swift、Objective-C、Go/Darwin、Rust/macOS——仍为**Experimental，未Mac SDK原生编译或真实AX运行**。本文冻结时远端CI未运行；发布后须查看GitHub Actions实际状态，不能从本地检查推定。

## 2026-11-10 — 保存与失败路径修复

| 实际问题 | 原因与修正 | 验证及公开依据 |
| --- | --- | --- |
| PowerShell初次保存后，覆盖已有设置文件可能报“The path is empty”。 | File.Replace第三参数的$null可能被PowerShell转为空字符串；现用[NullString]::Value传入真正null备份路径。 | PS5.1与7均通过首次/重复保存、持久化和启用开关保留间隔检查。见[源码](windows/powershell/ChatGPT-TitleSync.ps1)、[夹具](tools/test-tray-settings.ps1)。 |
| PowerShell菜单经GetNewClosure后可能找不到辅助函数。 | 动态闭包作用域未保留预期函数查找；现显式捕获可调用scriptblock，并将保存动作传给设置窗。 | 两主机设置打开、保存、重开及退出回调通过。见[源码](windows/powershell/ChatGPT-TitleSync.ps1)。 |
| AHK首次保存时父目录不存在会失败；输出写入失败还需保证清理，避免未处理错误窗。 | 写入前建立设置/输出父目录；现代AHK emit/save捕获预期失败、输出诊断并在finally清除临时输出，提交失败不替换当前生效设置。 | 分支自有测试覆盖首次/替换保存、缺目录、非法输入、失败回滚及临时清理。见[Basic指南](windows/ahk-v1.0/README.zh-CN.md)、[v1.1源码](windows/ahk-v1.1/chatgpt_window_titles.ahk)、[v2源码](windows/ahk-v2/chatgpt_window_titles.ahk)。 |

## 作为限制保留的事件实验

一次Windows60秒实验中，两次导航已由来源/页头确认，而单次Document.NameProperty、TreeScope.Element订阅收到**0条回调**；原生前台/名称变化元数据事件有到达。本次未订阅页头文本，也不重绑文档，不能据此断言所有ChatGPT事件路径不可用。未采用纯事件监听，保留2/5秒来源兜底。见[已知问题](KNOWN_ISSUES.zh-CN.md#event-only-monitoring-is-not-implemented)。

## 2026-11-11 — 实验性Mac编译修正

[首次有效运行环境检查](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43019350487)已进入真实macOS SDK：Objective-C与Rust编译成功。Go因相邻说明注释被Cgo收入前言并当成C文本而失败，现用空行分离；Swift作业在swiftc之前被共享AppleScript语法错误中止，现先计算模式索引，再统一调用一次Objective-C选择器。两处修正仍须下一轮真实CI核验；这些是编译结果，不等于Mac辅助功能或应用运行验收。

[后续真实检查](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43024915028)再次完成Objective-C与Rust编译，同时发现Go另外三处编译错误（既有错误变量赋值及两处Core Foundation引用零值）和另一处AppleScript选择器参数语法问题，现作最小修正。Swift原生编译与AppleScript语法检查拆为独立步骤，两者的失败都保留；工作流另记录实际编译器与SDK版本。本修订仍待下一轮真实工作流核验。
