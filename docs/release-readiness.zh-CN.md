# 发布准备：ChatGPT 标题同步助手

[English](release-readiness.md) · [项目主页](../README.zh-CN.md)

**截至2026-11-12：**[仓库](https://github.com/hpsun/ChatGPT-TitleSync)与[v0.1.0公开预览](https://github.com/hpsun/ChatGPT-TitleSync/releases/tag/v0.1.0)已存在。开发树版本仍为 **0.1.0**，下一目标为 **0.2.0**；本次未建立发布候选（RC）或新 Release，已有公开 v0.1.0 预览不代表这些尚未发布的改动已经交付。产品名保持ChatGPT-TitleSync／ChatGPT标题同步助手；用户选定的MIT及仓库LICENSE仍须保留，此前未发布/待批准条目作为历史。

## 既有登录自启动契约

登录自启动已经**缺省已开**；托盘／菜单可直接勾选，设置中同项按保存提交、取消不改。Windows各实现共用当前用户Run值和DWORD偏好；启用超长命令会被拒绝，退出不取消下次登录登记。见[启动说明](startup.zh-CN.md)。名称替换不改变此契约。下方旧九路线设置／重置观测属于旧源码修订，不能证明新规则处理已经验收。Mac登录／LaunchAgent行为仍为Experimental，未完成真实Mac验收。

## 名称替换候选

共享编辑器的 **Append — ChatGPT / 标题末尾显示ChatGPT** 复选框缺省勾选，按**保存**生效，与 **Enable name replacement** 及逐行开关独立：替换规则为空或停用时仍可关闭程序追加的后缀。共享 JSON 可选布尔项 `append_chatgpt_suffix` 缺项按 `true`，不属于扫描、图标或启动项偏好。

显示链缺省无私人规则或自动迁移；当前样例来自私有已核实原名快照，建议须使用规则再保存。`--format`保留主体，`--format --caption`返回完整标题；合法原名/主体限512个UTF-16码元，正常完整标题最多522；可解码非法来源完整无修饰回退，不截断。原名/恢复/手工标题守卫与来源节拍不改，四种Python／AHK一次检查模式限制见[帮助](name-replacement.zh-CN.md#caption-protocol)。

**Windows 负载边界：**自有格式化 worker 的截止仍为 **1.5 秒**。负载竞争或启动缓慢可导致超时，回退为完整原名加**缺省后缀**，因此保存的 `false` 可能尚未生效。失败按原名及规则/辅助程序身份缓存，条件不变的轮询不会重试；重新保存规则、替换/改变辅助程序身份、重启监听，或观测到不同原名，才会刷新该缓存。降低负载后，两种 PowerShell host（5.1、7）分别单独复测同项成功，之前 WorkerTimeout 现场仍保留；不能据此宣称无条件通过，也不承诺完整界面响应必在1.5秒内完成。

## 目标协议与验收边界
最终目标分三层：

1. 前台ChatGPT窗口按可配置间隔直接fresh读取来源，缺省2秒，不能用记住的来源代替前台读取。
2. 每秒检查已知后台窗口的原生身份／标题。应用把标题改回generic时，直接用记住的标题恢复，不重新读来源；保留自定义标题，身份改变清缓存，未知窗口不凭空造缓存。
3. 后台来源低频刷新，每窗缺省5秒、可配置，单独一个串行worker；未知后台也可低频建缓存。前台优先，不能等待后台来源队列。完成时仅在身份一致且原生标题仍generic或本程序上次写入值时更新，保护自定义名。

Windows分支已有三层来源／缓存的受控检查和本机构建／解析证据。这是本地源码候选的审核边界，不是所有语言的真实应用完整验收。全部Mac后端仍为**Experimental**。下列实际SDK编译／CLI检查点与当前待验证修订、真实AX／菜单／编辑器／登录验收必须分开；旧foreground-only测试与新协议检查明确分开。

## 离线审计与仓库文件选择
只需Python 3.10及以上及标准库：
```powershell
python -m unittest discover -s tools/tests -p "test_release_audit.py" -v
python tools/release_audit.py --allowlist --no-zip --output-dir "$env:TEMP/ChatGPT-TitleSync-file-review"
```

目录尚无独立Git仓库时，--allowlist明确只取已审阅的源码、文档和45资源。初始化并暂存后，省略--allowlist检查tracked快照。两种模式都拒绝越界或未审阅的tracked文件；Git-index模式还拒绝工作文件与暂存内容不一致。

审计按**实际包内文件集**核对必需文件、文档相对链接／锚点、前台2秒/后台5秒缺省源码标记、45资源哈希、MIT及已有源码哈希索引。拒绝私有运行证据、validation、日志、备份、SDK、二进制、个人绝对路径和常见凭据形态。模式不能识别所有真实对话名或秘密，仍须人工审阅候选快照。

核准后按正常目录逐文件提交源码、指南、共享45资源与必要伴随源码，**本次不上传项目ZIP**。可Git clone获取目录树，或在对应语言目录取得单文件并保留其文档要求的依赖。GitHub若自动提供源码归档，是平台生成内容，不是本项目上传的ZIP；先前本地审核压缩包仅作历史留证，不作为交付方式。

审计使用`--no-zip`输出机读报告和选中文件清单，不生成压缩包。发布方核对每个文件字节，再建立对应blob/tree。根`.gitattributes`使用`* -text`保持已审核字节；私有运行数据、下载SDK等不进入仓库。

用户于**2026-11-11**明确批准的仓库文件及首个v0.1.0预览版现已公开。这不等于远端CI结果或Mac原生验收；名称替换功能分支单独验证，未建立其它Release。

<a id="local-validation"></a>
## 本地验证

<a id="current-suffix-verification"></a>
当前逐组件证据与历史分开；46／37重叠测试不相加，共同用例不按前端重复计数，嵌套子例不升级为顶层数量。

| 组件 | 当前证据 | 范围 |
| --- | --- | --- |
| Windows共同CLI |46／46：31 body＋15 caption |一套共同测试，不按语言重复累计。 |
| Windows helper专项 |37项：22保留body＋15 caption |与共同46有重叠，不得把两总数相加。 |
| C#／共享编辑器 |显示10项；始终隐藏编辑器13项 |自有虚构状态/控件，无正常ChatGPT GUI。 |
| PowerShell5.1／7 |低载下分别单独复测同项关闭尾巴成功 |保留此前WorkerTimeout／缺省尾巴缓存，不称无条件通过。 |
| Python |23项单元＋14项真实helper私有检查 |自有文件/进程与模拟所有权。 |
| AHK Basic／1.1／2 |每分支17项caption；旧body分别23／19／19 |Basic仍仅源码，虚构原生状态，无正常桌面。 |
| Go／Rust |20顶层／21测试函数，单函数包含9项CLI矩阵 |Windows受控测试/构建，新suffix Mac原生CI待验。 |
| Mac pre-suffix检查点1b7c33b |四原生构建、31共同CLI、5 I/O、3恢复 |未AX／GUI／登录验收，更新的suffix46／client7须独立CI。 |

**Windows 负载边界：**自有格式化 worker 的截止仍为 **1.5 秒**。负载竞争或启动缓慢可导致超时，回退为完整原名加**缺省后缀**，因此保存的 `false` 可能尚未生效。失败按原名及规则/辅助程序身份缓存，条件不变的轮询不会重试；重新保存规则、替换/改变辅助程序身份、重启监听，或观测到不同原名，才会刷新该缓存。降低负载后，两种 PowerShell host（5.1、7）分别单独复测同项成功，之前 WorkerTimeout 现场仍保留；不能据此宣称无条件通过，也不承诺完整界面响应必在1.5秒内完成。

上述Go／Rust选测使用私有文件、内存状态和仅属自身的无界面协议进程。此前两次未筛选Go测试还执行了自行清理的GUID临时注册表夹具，不称纯文件测试，未使用真实产品Run／偏好键。

### 历史本地源码检查

以下计数保留自此前源码／设置修订，不计作名称替换验证：

| 检查 | 本地结果 | 范围 |
|---|---:|---|
| 发布审计合成边界 | 12项通过 | 允许清单、私有链接、凭据／路径、误暂存、旧哈希、锚点、pending门槛、Git行尾字节保持与ZIP字节 |
| C#受控设置候选 | 41策略＋13 helper/Job＋8间隔协议＋12设置通过 | 合成/自有对象范围；公开41项复现策略集。真实窗口/设置专项结果见下表。 |
| PowerShell受控设置候选 | 5.1与7各32策略＋9设置回调通过 | 受控解析/原生桥及重复原子保存通过；真实窗口/设置专项结果见下表。 |
| Go | 38项受控检查通过 | 策略/回归、自有原生设置控件与热重排；真实ChatGPT/设置专项结果见下表。 |
| Rust | 30项受控检查通过 | 策略/回归、自有原生设置控件与热重排；真实ChatGPT/设置专项结果见下表。 |
| 隐藏启动首显 | 两种自有显示路径，在两种PowerShell主机运行 | 实际STARTUPINFO Hidden；首次原生Show隐藏，显式显示后可见；离屏、不激活、不访问ChatGPT。 |
| 当时源码冻结的Mac后端 | 当时仅静态复核 | 后续编译范围由下列有日期的远端检查点补证；真实AX／运行证据仍缺失 |

原始执行证据、真实进程标识和对话名称留在本地，公共包不链接、不包含。源码／构建／模拟检查与真实应用时延、Mac原生验收严格区分。

## 实际CI检查点与后续门槛

在 [Mac CI 检查点 `1b7c33b`](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43141369229)，**四种原生语言构建**（Swift、Objective-C、Go、Rust）、**31项共同格式化**、**5项文件I/O**及**3项客户端恢复**均通过；共享 AppleScript 编译仍在报告位置 `:64` 的 `application` 变量附近报 **-10003**，最小修正待验证。更新后缀修订的 **46项共同用例及7项客户端**仍须另一轮原生整合CI，**不在此检查点覆盖范围内**。真实ChatGPT AX/标题写入、编辑器/菜单GUI和登录行为未验证，Mac路线继续为Experimental。

### 1b7c33b之前的历史检查点

以下保留当时“当前/待验证”范围；已核实最新结果及更新后缀待验范围以上方为准。

[macOS CI run43124672990](https://github.com/hpsun/ChatGPT-TitleSync/actions/runs/43124672990)，提交`19cec8080908a15f0d0a8ccefa66209cb207bf71`，实际编译共享Foundation helper及新增Swift／Objective-C RulesClient集成，并通过同一套**30项共同格式CLI用例**。该次AppleScript编译失败；Go／Rust当时仍为旧baseline适配，不能以此证明新名称替换适配通过。共享用例只计一套，不按语言重复累计。

当前helper修订`4B614FB1…D2C67DE`、AppleScript修订`9127B78F…7855E99`、新增第31个Unicode回退用例、客户端负缓存恢复与新Go／Rust适配，仍等待下一完整CI结果。编译及CLI通过不等于真实Mac AX、菜单、AppKit编辑器、登录自启动、长期运行或真实标题还原验收；Mac继续标Experimental。

验证workflow检查源码／审计／构建和受控用例，不启动正常AX监听。其只读检查及checkout不保留凭据的要求，与独立`release-preview.yml`任务分开：后者只在`main`的Windows检查成功后，按守卫建立已授权首版v0.1.0 Release；已有v0.1.0时保持不变。它不为功能分支发布，也不构成其它Release的批准。失败步骤仍按失败记录，不能由个别job成功推导整套成功。



已核对官方[checkout v7](https://github.com/actions/checkout)和[setup-go v7](https://github.com/actions/setup-go)。CI有意固定到本机使用的Go 1.27.3和Rust 1.82.0，不宣称它们是最新语言版本。Rust使用官方[rustup工具链机制](https://rust-lang.github.io/rustup/concepts/toolchains.html)；Windows链接器要求见[Rust安装说明](https://rust-lang.org/tools/install/)。

## 图标与交付
45号为共享基准：[PNG](../assets/chatgpt-titlesync-icon.png)、[Windows ICO](../assets/chatgpt-titlesync.ico)、[macOS ICNS](../assets/chatgpt-titlesync.icns)。运行时固定／随机配色用于程序自身托盘及设置窗口；EXE内嵌资源及固定快捷方式保持固定。各实现构建及原生验证范围分别说明，见[图标设置](icon-themes.zh-CN.md)。Mac .app封装、签名、公证仍未验证。

审计/文件选择工具不写网络或更改启动项；实际仓库创建和逐文件发布由获授权的根发布方单独执行，不上传审核ZIP。

## 发布边界

- [仓库](https://github.com/hpsun/ChatGPT-TitleSync)及[v0.1.0预览版](https://github.com/hpsun/ChatGPT-TitleSync/releases/tag/v0.1.0)已公开；名称替换功能分支未建立新Release。
- 合并前重新核对本功能选中文件／目录树、逐文件哈希、配套程序包装和当前CI；旧冻结及旧真实专项不能替代变更文件的验证。
- 不上传本地项目审核ZIP；仓库按普通源码／文档／资源文件组织。私有证据、实际规则、来源快照、标题、身份及日志继续排除。
- Windows受控／CLI与Mac SDK／CLI证据分开记录；本功能当前正常Windows GUI及真实Mac AX／菜单／编辑器／登录验收仍未完成。



<!-- BEGIN TARGETED_WINDOWS_REAL -->
## 历史Windows真实窗口专项验收 — 2026-11-11

以下测量属于此前冻结修订，不属于名称替换候选。9个Windows运行时案例复用同3个现存ChatGPT窗口，各案例比对1个来源/页头目标、有效注入1次前台通用标题重置及1次后台重置，并检查正常退出后3窗为原通用标题。设置经绑定原生指令/同一菜单处理器调用，不冒称系统托盘物理右键已实测。下列为单次重置到首次匹配观测，不是基准、冷读取时限或长期/安装/任务栏保证；这组历史Windows案例本身没有Mac原生编译或运行，后续Mac CI另见上方。

| 运行时 | 设置 | 前台复原 | 后台复原 | 退出 |
| --- | --- | ---: | ---: | --- |
| C# | 2/5 → 3/10重开 → 2/5 | 1384ms | 781ms | 3窗原通用标题 |
| AHK Basic 1.0 | 2/5 → 3/10重开 → 2/5 | 1098ms | 632ms | 3窗原通用标题 |
| AHK v1.1 | 2/5 → 3/10重开 → 2/5 | 2247ms | 667ms | 3窗原通用标题 |
| AHK v2 | 2/5 → 3/10重开 → 2/5 | 1056ms | 409ms | 3窗原通用标题 |
| PowerShell 5.1 | 2/5 → 3/10重开 → 2/5 | 881ms | 794ms | 3窗原通用标题 |
| PowerShell 7 | 2/5 → 3/10重开 → 2/5 | 342ms | 282ms | 3窗原通用标题 |
| Python | 2/5 → 7/17重开 → 2/5 | 161ms | 379ms | 3窗原通用标题 |
| Rust | 2/5 → 3/10重开 → 2/5 | 1018ms | 624ms | 3窗原通用标题 |
| Go | 2/5 → 3/10重开 → 2/5 | 1784ms | 448ms | 3窗原通用标题 |

Python冷启动来源样本的原生标题仍通用；稍后有效前台重置的原标题指纹与独立来源完全一致，按跨时点证据记录。前两次前台守卫未注入重置，保留原档，不计产品失败。Python各项使用同一冻结EXE的不同启动批次；最终设置补证在同一进程中核验磁盘及重开控件精确7/17，再还原2/5。原先无法解释的33/10观察保留，不改写为已证产品缺陷。此前C#首显隐藏缺陷保留历史记录，表中使用修复后的最终EXE。
<!-- END TARGETED_WINDOWS_REAL -->
