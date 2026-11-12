# 变更记录

[English](CHANGELOG.md) · [HTML](CHANGELOG.zh-CN.html) · [已知问题](KNOWN_ISSUES.zh-CN.md) · [项目主页](README.zh-CN.md)

记录采用真实开发与验证日期，统一为**北京时间**，不冒充历史 Git 提交日期、版本标签或虚构 Issue 编号。旧条目中的**候选**、**待验证**和**仅源码**保留当时检查点的状态；当前范围与已核实 CI 证据以上方**尚未发布**条目为准，不据旧文字认定所有 Mac 源码至今均未编译。

## 尚未发布 — 2026-11-12

### 名称替换

- 新增有序的**普通文字与正则表达式**规则，先处理显示对话名，再加通常的 ` — ChatGPT` 后缀。缺省规则为空，不内置、导入或迁移私人/本机规则；配置缺失时原样显示。
- 可从私有 CTS1 快照选择已观测的当前名称，也可输入手工样例。预览及通用建议不保存、不应用规则，必须明确**使用规则（Use rule）→保存（Save）**；取消保留已保存规则，读取/打开/预览不创建配置。选择器不新增 ChatGPT 来源读取。
- 各前端复用操作系统共用的 Unicode 辅助程序：Windows 使用 .NET，macOS 使用 Foundation；运行时须保留相应辅助程序与本地帮助。异步格式化采用调用方自有进程的 **1500 毫秒**截止，失败时返回**完整原始名称**，不提交局部结果。原始来源缓存、原标题恢复及手工标题保护与显示修订分开，规则变化不重置来源节拍。见[名称替换帮助](docs/name-replacement.zh-CN.md)。

### 可选程序后缀

共享编辑器的 **Append — ChatGPT / 标题末尾显示ChatGPT** 复选框缺省勾选，按**保存**生效，与 **Enable name replacement** 及逐行开关独立：替换规则为空或停用时仍可关闭程序追加的后缀。共享 JSON 可选布尔项 `append_chatgpt_suffix` 缺项按 `true`，不属于扫描、图标或启动项偏好。

`--format`保留名称主体，`--format --caption`返回完整标题；合法原名/主体限512个UTF-16码元，正常完整标题限522。可解码非法来源完整返回且不加尾巴，不截断。原始来源、原标题恢复、手工标题保护与来源间隔不改。

**Windows 负载边界：**自有格式化 worker 的截止仍为 **1.5 秒**。负载竞争或启动缓慢可导致超时，回退为完整原名加**缺省后缀**，因此保存的 `false` 可能尚未生效。失败按原名及规则/辅助程序身份缓存，条件不变的轮询不会重试；重新保存规则、替换/改变辅助程序身份、重启监听，或观测到不同原名，才会刷新该缓存。降低负载后，两种 PowerShell host（5.1、7）分别单独复测同项成功，之前 WorkerTimeout 现场仍保留；不能据此宣称无条件通过，也不承诺完整界面响应必在1.5秒内完成。

Python及三AHK的`--once`当前跳过已保存替换和关闭尾巴选项；该产品限制与body API兼容性分开说明。

### 验证状态

Windows通过 **46／46项共同CLI**（31 body＋15 caption）；另有helper专项 **37项**（22保留body＋15 caption），两套有重叠，不能相加为83。C#显示10项、始终隐藏编辑器13项通过；均为受控组件结果，不是正常桌面验收。

Go20个顶层测试、Rust21个函数通过，单函数内9项CLI子例不另算顶层；Python23项单元＋14项真实helper私有检查，各AHK17项caption检查通过，均为受控范围，不是正常桌面验收。

在 [Mac CI 检查点 `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229)，**四种原生语言构建**（Swift、Objective-C、Go、Rust）、**31项共同格式化**、**5项文件I/O**及**3项客户端恢复**均通过；共享 AppleScript 编译仍在报告位置 `:64` 的 `application` 变量附近报 **-10003**，最小修正待验证。更新后缀修订的 **46项共同用例及7项客户端**仍须另一轮原生整合CI，**不在此检查点覆盖范围内**。真实ChatGPT AX/标题写入、编辑器/菜单GUI和登录行为未验证，Mac路线继续为Experimental。

### README 示意与版本

任务栏示意改为前后相同的灰色平直 **Windows 10 风格**，整段标题使用统一正常字重/样式，窄按钮的长标题显示省略号。系统强调线宽为按钮的 **228/234 像素，即 97.4%**，前后颜色和几何一致。保留真实 ChatGPT 应用图标，所有名称均为虚构的 **Example chat A/B/C**；明确标为效果示意，并说明按钮宽度、字体、合并和主题取决于 Windows。

开发树版本仍为 **0.1.0**，下一目标为 **0.2.0**；本次未建立发布候选（RC）或新 Release，已有公开 v0.1.0 预览不代表这些尚未发布的改动已经交付。

## 2026-11-11 — AppleScript保留字选择器修复候选

提交`d90f7d3ca16cbd24b7f521b8baa18a0e947984e6`的[运行43035186223、Swift作业130572026758](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43035186223/job/130572026758)中，仅编译诊断成功，确认真正报错的是`app's run()`中的`run`。UTF-16错误范围分别为原始CRLF源码`{4883, 3}`、内存LF副本`{4787, 3}`。反复出现的命令行`:189`不足以确定报错语句，此前修改下拉选择表达式没有解决它。该次运行的四项原生编译仍全部通过。

本候选仅将该调用改为`app's |run|()`。Apple的[AppleScriptObjC转换指南](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AppendixA-AppleScriptObjCQuickTranslationGuide.html)说明，Cocoa方法名与AppleScript术语冲突时，应以竖线包围标识符；目标选择器仍是Cocoa的`run`方法。对同类命令名称作静态检查，未发现其他未转义调用，已有`|error|:`参数标签保留原样；没有修改其他选择器。

本次修改仍是**待下一轮Mac CI真实编译确认的候选**。诊断只编译源码，没有执行事件循环、脚本处理器、AX监听或应用界面。本项工作仍未验证原生运行、设置、图标和登录自启动行为。

## 2026-11-11 — 原生SDK编译与AppleScript定位诊断

提交`f9eb899396fd2885cbad5ee36002be4e8c77554d`的[运行43027160517](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43027160517)中，Swift、Objective-C、Go、Rust四项原生编译步骤均已通过。日志实际记录的环境为macOS 15.8.2（24H232）、Xcode 16.4（16F6）、macOS SDK 15.5、Swift 6.1.2、Apple Clang 17.0.0。这些是SDK编译结果，**不等于原生AX或应用运行验收**。

独立的共享AppleScript编译仍报`macos/TraySettings.applescript:189: error: Expected expression but found command name. (-2741)`。`:189`究竟表示源码行号还是字符范围尚未核实；此前对下拉选择表达式的调整没有解决该错误，实际定位与修正仍待确认。

新增最小的[仅编译诊断工具](tools/diagnose-applescript.swift)，分别对原文和内存中仅规范化为LF的副本调用`NSAppleScript.compileAndReturnError`，输出编译错误字典、UTF-16的`NSRange`、报错片段及邻近源码。工作流仅在共享AppleScript编译步骤失败后调用它。该工具不执行脚本或处理器，不启动监听器，也不操作AX或界面。诊断工具本身仍待首次Mac CI真实结果；添加工具不代表已经修复AppleScript或验证运行成功。

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
