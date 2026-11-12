# ChatGPT 标题同步助手 — C# 独立应用

[English](README.md) · [HTML](README.zh-CN.html) · [项目说明](../../README.zh-CN.md)

**ChatGPT 标题同步助手／ChatGPT-TitleSync** 的 Windows 托盘应用，C# 5／.NET Framework 4.x。


## 名称替换——缺省规则为空

托盘 **Name replacement… / 名称替换…** 和设置窗中的同名按钮打开共用Unicode编辑器。初始**没有任何规则**，不会自动去掉厂商前缀或提取括号。可逐条启用并调整顺序。**Plain text / 普通文字**按区分大小写的原文全局替换，替换内容按普通文字处理；**Regex / 正则**采用Windows .NET引擎，支持 `$0`～`$99`、`${0}`～`${99}` 和 `$$`，拒绝未知或不存在的捕获引用。

当前对话下拉读取监控器的私有 **CTS1来源快照**，显示时间并可刷新文件，不为此额外读取ChatGPT或UIA。快照缺失或无效时仍可手工输入示例。**建议规则**根据当前示例或所选文字派生转义后的候选，包含去前缀、保留分隔符后内容、成对符号内部等；建议只是草稿，必须先点**使用规则**，再点**保存**才生效。**取消**不保存。预览只处理本地示例，并使用有界子进程。

Windows前端共享 `%LOCALAPPDATA%\ChatGPT-TitleSync\title-rules.json`，与间隔、自启动和图标设置分开。规则只作用于可信原始对话名，之后才拼显示后缀。配置、替换引用、匹配超时、空白／控制字符／通用名结果、超长输出或孤立UTF-16代理项，均回退**完整原始来源名**，不使用中途结果。共用工具每条正则限制100毫秒、整条链500毫秒；调用方对规则worker设置1500毫秒期限，排队和调度仍可能增加耗时。相同原名及规则签名复用成功／回退缓存，不每秒重启worker。

保存规则从raw缓存重新派生已知显示，不重置来源读取截止时间。重绘仍核验同一窗口身份及“当前标题等于本实例最后写入值”，保留外部手工标题。运行期 `title-rule-sources.bin` 包含私人对话名，不应发布。

已建立客户端后，显示签名同时包含规则内容及worker文件的存在性、大小和修改时间；补回同路径worker可让相同raw重新格式化，不为此多读来源。C#主程序把共用规则程序集作为启动依赖；缺失时须先补齐配套文件再启动，不能只复制主EXE。

参见[名称替换帮助](../../docs/name-replacement.zh-CN.md)及打包的[本地HTML帮助](../../docs/name-replacement.zh-CN.html)。

### 可关闭的 ChatGPT 后缀

**Append — ChatGPT / 标题末尾显示ChatGPT** 缺省勾选；取消后只显示派生对话名。该项独立于规则总开关，空规则或停用规则时也能关闭后缀。保存才生效，取消不修改保存字节。旧schema-1配置可缺少 append_chatgpt_suffix（按true处理）；存在时必须是JSON布尔值。

原始名缓存、原窗口标题和读取时序保持不变。保存后在维护节拍热更新已由程序管理的窗口，不增加来源读取；外部手工标题仍受保护。合法正文/完整标题上限为512/522个UTF-16单元。可解码但超长或含控制符的非法来源，完整回退原文，不附后缀也不截断。CLI的 --format 保留正文协议，--format --caption 返回完整标题；读取失败默认加后缀，配置合法且为false时规则匹配回退仍不附加。正常C#/PowerShell直接消费完整标题，不再重复拼接。

子进程仍限1,500毫秒。同一原始名与规则/helper签名的成功或回退结果会缓存，直到签名变化、观察到别的原始名或驻留程序重启才重试；保存会生成新规则修订号。私有并行验证曾记录WorkerTimeout，随后两个PowerShell宿主各一次低载顺序复测均返回ok，false实际生效；不能据此承诺统一响应时延。失败原始证据保留。

### 新功能验证边界

共用工具已有Unicode／CLI纯测试，覆盖整链回退和孤立代理项；注入后端证明缓存重绘不增加来源读取。PowerShell5.1／7客户端检查使用私有文件与模拟窗口后端。编辑器效果图仅用虚构示例、从未显示的自有控件，模拟100%、125%、150%字体与几何，表头字形内容区完整；另以自有离屏NOACTIVATE／Hidden夹具核验候选的显式原生显示且前台不变。这些检查**不代表**新增正常桌面、登录启动、物理托盘菜单或全部实时UIA验收；下方早期真实窗口结果保留原日期和范围。

### 构建依赖

本分支 `Build.ps1` 先调用 `shared/windows/Build.ps1` 构建 `ChatGPT-TitleSync.Rules.exe`，再引用该程序集构建主程序。主程序、读取器和规则工具三个EXE须相邻，保留docs帮助及assets资源。规则CLI／编辑器不取得监控器互斥体，不注册自启动。


## 品牌与兼容性

正式名称为 **ChatGPT 标题同步助手／ChatGPT-TitleSync**。保留 `Local\TdxChatGptTitleStandalone` 及 `.Stop`／`.Settings` 事件，确保旧独立版不能同时写标题。现有 `%LOCALAPPDATA%\ChatGPT-title` 数据位置与设置字段保持兼容。C# 的 `chatgpt-title-cache.json`、私有工作目录 `chatgpt-title-readers` 和诊断结构标识 `chatgpt-title-probe-v1` 也保留，用于兼容既有数据。下方历史真实窗口观察早于品牌与自启动修改；本次自有／离线检查另行注明范围。

## 图标主题——固定或定时随机

缺省为**固定45号**，随机周期保留为**每日**。已选设计采用奶油色圆角tile、大ChatGPT主体、右上覆盖的Title胶囊及粗等宽字形；八色保持同一布局。

| 编号 | 胶囊／文字 | 编号 | 胶囊／文字 |
| --- | --- | --- | --- |
| 45 | 蓝紫／白字 | 49 | 玫红／白字 |
| 46 | 湖蓝／黑字 | 50 | 天蓝／黑字 |
| 47 | 琥珀／黑字 | 51 | 浅紫／黑字 |
| 48 | 薄荷／黑字 | 52 | 珊瑚／黑字 |

<img src="../../assets/themes/45.png" alt="缺省45号" width="72"> <img src="../../assets/themes/47.png" alt="琥珀47号" width="72"> <img src="../../assets/themes/48.png" alt="薄荷48号" width="72">

设置增加三个**不可编辑下拉框**，保留原两个数值输入和自启动复选框。固定／随机切换后，仅启用固定配色或随机周期中的对应一项，另一项变灰。随机周期为本地日历日、本地整点小时或五分钟时段；启用随机或更改周期时立即选一次，之后不连续重复前一色。同一时段内重启复用已保存的随机色。独立每秒做轻量时段检查，关闭标题监听后仍能换色，不为换图读取ChatGPT或启动读取器。

Windows各实现仅共享 `HKCU\Software\ChatGPT-TitleSync` 下五项：`IconMode`、`IconPeriod`（`REG_SZ`），`FixedIcon`、`RandomIcon`（`DWORD`，45..52），`IconSlot`（`REG_SZ`）。每日slot为 `YYYYMMDD`，小时为 `YYYYMMDDHH±HHMM`，五分钟为 `YYYYMMDDHHbb±HHMM`，其中bb是分钟整除5，范围00..11；不替代 `AutoStartEnabled` 或原监测设置。

**保存**校验资源并与自启动／间隔一起提交；**取消**关闭并丢弃草稿。注册表、自启动或设置文件失败会恢复之前的已提交选择，不把部分修改当成功。轮换时缺少资源保留最后可用图标，同一slot限量记录诊断；非法旧偏好回退45并报告一次，不偷偷改写。只有正常常驻入口持久化主题，诊断／控制入口不写入。

运行时主题只改变本产品托盘与自己的设置窗图标，不改EXE字节、固定快捷方式或ChatGPT应用图标。安装目录保留 `assets/themes/45..52.ico`；根图标别名与EXE资源仍是45。新图标替换后才释放旧自有句柄。控件名为 `IconMode`、`FixedIcon`、`IconPeriod`，原生窗口ID以当次运行实际值为准。

本次通过37项C#注入时间／随机数／注册表／资源／事务检查及每个PowerShell主机37项实际回调检查，范围为自有键与从不显示的控件。2026-11-11记录的早期A1阶段专项仍按历史保留，不改称当前八色／实时换图验收；当前真实窗口复测由项目发布方另行记录。

## 开机自启动——缺省已开

正常常驻模式缺省勾选 **开机自启动 / Start at sign-in**，在当前Windows用户登录时启动，并非登录前运行。托盘右键勾选立即生效；设置窗中的同项在**保存**后生效，**取消**不更改。任一入口成功更改后同步另一处，包含已经打开的设置窗。失败会显示错误，不把失败状态当成功；注册表写入失败时尝试恢复原值。

Windows各实现共享 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 下固定值名 **ChatGPT-TitleSync**，及 `HKCU\Software\ChatGPT-TitleSync\AutoStartEnabled` DWORD偏好。缺项按开启处理；显式0会跨语言版本与重启保持关闭。只有取得原共享互斥体的正常常驻入口才读取偏好并注册自身；只读、工作进程、单次检查、设置／停止IPC入口不注册。关闭时只移除本产品的Run值，不使用管理员权限、服务或任务计划。启用命令超过Windows Run的260字符限制时会明确拒绝，不改启动项或共享偏好；仍可关闭。启动项与偏好已经一致时不重复写入。参见[Microsoft Run文档](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)。

注册命令仅包含当前 `ChatGPT-TitleSync.exe` 的带双引号绝对路径，不携带诊断或间隔参数；`ChatGPT-TitleSync.Reader.exe` 应与主程序相邻。

菜单项与设置复选框的控件名均为 `AutoStartEnabled`。前台2秒／后台5秒缺省值、监测设置JSON字段及旧互斥身份保持兼容。本项已用从不显示的自有控件、临时当前用户注册表键验证，包含C#/PowerShell互读关闭偏好；这不等于新增真实Run／登录启动验收。

## 构建与运行

Build.ps1 使用 Windows Framework64 编译器及 UIAutomation／WPF 引用，输出 AnyCPU EXE，不需要 MSVC。主程序、读取器及规则工具三个EXE放在一起。保留仓库 assets 目录用于相对托盘图标；主 EXE 也会嵌入基准45。

```powershell
powershell.exe -NoProfile -File .\Build.ps1
.\ChatGPT-TitleSync.exe --interval 2 --background-interval 5
```

`--interval` 为前台来源间隔，有效 1～3600 秒。`--background-interval` 为每窗口后台来源间隔，有效 5～3600 秒，缺省 5；如需 15 秒可用 `--background-interval 15`。原生身份／标题维护独立地每秒执行。 watch读取器按设定间隔实际读取来源，心跳独立每秒发布；父程序每秒消费新来源序列，未变化的来源不作为新观察。

托盘提供 **Enable window titles**、**扫描间隔设置… / Scan intervals…** 和 **Exit and restore titles**。启用选择与两个间隔保存在 `%LOCALAPPDATA%\ChatGPT-title\csharp\settings.json`，缺省启用当前用户登录自启动，见下文。

## 文件

| 文件 | 用途 |
| --- | --- |
| App.cs | 托盘、设置、单实例及正常退出 |
| TitleMonitor.cs | 三层调度、身份缓存、自有读取器生命周期及恢复 |
| TitleReader.cs | 隔离来源读取；正常监听只取文档根 Name |
| Build.ps1 | 先构建共用规则工具，再构建ChatGPT-TitleSync.exe和ChatGPT-TitleSync.Reader.exe |

## 三层监听

1. 每秒核对原生 ChatGPT 窗口身份／标题。已知后台窗口被改回通用 `ChatGPT` 时，直接用可信缓存修复，不为此重读来源。
2. 按前台来源间隔新鲜读取当前对话名，不用缓存兜底。前台改变会取消旧 watch。
3. 每后台窗口至多按设定间隔刷新一次，只有一个串行后台读取角色。未知后台窗口可由此取得首个可信名称。前台附着／处理优先，不同步等待后台读完。

来源读取只沿有界原生壳路径到 `Document[RootWebArea].Name`，不读对话后代。缓存／写入绑定 HWND、PID、创建时刻、窗口类和程序路径。

后台结果只有在身份相同、且当前为通用标题或仍由本实例持有时才能写入。非通用自定义标题保留。后台目标变前台时，旧后台结果被丢弃，由前台取得新鲜来源。

## 只读检查

```powershell
.\ChatGPT-TitleSync.exe --read-only --output .\read-only-results.json
```

枚举原生 ChatGPT 窗口，每窗口做一次有期限且不写标题的来源读取，保存 UTF-8 JSON 后退出，不启动长期 watch。只读每窗口期限为 4 秒；结果含标题及进程身份，应私有保存。

## 停止与还原

```powershell
.\ChatGPT-TitleSync.exe --stop
```

托盘退出和 --stop 均请求正常关闭。只有身份相同且当前标题等于最后写入值时还原，外部修改不覆盖。通用标题重置或明确关闭再启用功能可解除自定义标题保护；保护期间前台仍新鲜读取，只阻止写入。

Windows 独立实现共用 `Local\TdxChatGptTitleStandalone` 及 `.Stop` 事件，应只运行一个写入者。设置菜单修改采样节拍，不改变单实例与停止机制。

## 工作进程、计时及私有数据

前台保持一个绑定窗口及父进程身份的 --watch。它缓存 RootWebArea 元素而不是 Name 值，并原子发布心跳Seq／HeartbeatUtc和来源SourceSeq／ObservedUtc；父程序轮询不等待 UIA。

冷附着期限为 **10 秒**，首个 ready 后心跳期限为 **4 秒**。独立每 500ms 检查快照，即使父程序设置慢间隔也不误杀正常发布中的读取器。先观察新数据再判断过期；pending、重复、过期或身份不符的结果不能写标题。

后台快照有独立取消信号、输出文件、自有进程句柄及退出回收 Job，不会结束前台读取器或无关同名进程；目标转前台会取消后台角色。暂停／关闭功能／退出时会清理二者。

每秒调度不代表冷读取一定在一秒内完成；提供方响应、原生元数据工作和系统调度都可能增加延迟。

`%LOCALAPPDATA%\ChatGPT-title\csharp` 保存设置、标题操作日志、工作快照及 `chatgpt-title-cache.json`。私有缓存为升级后维护现存后台窗口而明确保存可信名称及完整身份，是运行数据，不进入源码包。日志用错误短码／标题指纹，不记录对话正文。

## 验证边界

当前组件证据：41 项三层策略／计时、13 项 watch／工作进程／Job 生命周期及 32 项既有修订回归。公开夹具复现同一组 41 项：

```powershell
powershell.exe -NoProfile -File ..\..\tools\test-csharp.ps1
```

fake／自有对象检查覆盖缓存重载与身份、通用回改、自定义标题、前台新鲜来源、取消、冷／稳态期限和恢复，不等于完整托盘、安装、长期驻留或任务栏视觉验收。见[本地验证摘要](../../docs/release-readiness.zh-CN.md#local-validation)及[支持矩阵](../../support-matrix.zh-CN.md)。C# 不面向 macOS。

## 历史版本真实窗口观测

独立版已通过前台新鲜标题切换及后台通用回改修复；来源样本和原生标题样本均核对为前台。来源时间戳到首个原生标题样本观测 **516ms**，后台缓存修复观测 **937ms**。

设置 --background-interval 15 后，三个窗口工作进程的尝试间隔约 **15.16、15.17、22.20 秒**。后台读取串行、前台优先，因此该间隔是调度下限，不保证每窗口严格每 15 秒读完。

正常 --stop 已退出程序且其前后台 helper 均无残留；原对话和配置原字节已恢复。计时样本采于隐藏窗口 lease 保护修复前，前台／标题维护路径未变；最终 EXE 包含另外受控验证的隐藏保护修复。

这些是有限专项观测，不是延迟保证，也不等于完整安装／托盘／长期／任务栏视觉验收。C# 不面向 macOS；尚未远程运行 CI 或公开发布。

## 扫描间隔设置（补充）

托盘右键现在提供“扫描间隔设置…”。同一个非模态设置窗口支持输入前台来源扫描1至3600秒、后台来源刷新5至3600秒，缺省2秒和5秒；保存后立即生效，同时保存启用状态与两个间隔。下次启动自动读取设置，显式命令行参数优先。非法输入在窗口中显示错误，不会写入配置。后台已记忆标题的原生回改检测仍固定每1秒。

前台间隔控制 helper 的实际来源读取；helper 的心跳仍每1秒发布，父程序每1秒消费新的来源序列。心跳 Seq/HeartbeatUtc 与来源 SourceSeq/ObservedUtc 分开，不能用未变化的来源冒充新读取。长间隔期间保留健康后台来源任务；目标变为前台时取消旧后台角色。

`ChatGPT-TitleSync.exe --settings` 通知已运行单实例打开同一个菜单设置处理器，不会启动第二个写入者；无兼容实例时退出码为4。`Build.ps1 -OutputDirectory PATH` 支持隔离构建。

`tools/test-csharp.ps1` 当前验证41项三层调度策略；`tools/test-tray-settings.ps1` 验证12项C#设置与持久化行为，以及两种PowerShell主机下的9项菜单回调。控件不显示、不激活，测试不触碰真实ChatGPT或共享停止事件。

## 隐藏启动后的设置首显

Windows以STARTUPINFO的Hidden启动进程时，第一次普通Show可能被启动提示压制。设置入口现先使用SetWindowPos明确显示自有窗口，再请求激活；这是原生窗口可见性问题，与UI Automation来源读取分开。

公开入口tools/test-tray-settings.ps1已加入独立自有WinExe回归：确认STARTF_USESHOWWINDOW和SW_HIDE，观察首次原生Show仍隐藏，再验证生产显示辅助方法与WinForms窗体确实可见。夹具位于屏幕外并使用WS_EX_NOACTIVATE，核验前台窗口不变；已分别在PowerShell5.1和7执行。它是受控首显验证，不冒充真实ChatGPT或系统托盘菜单整体验收。

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Windows真实窗口专项验收 — 2026-11-11

41策略＋13 helper/Job＋8间隔协议＋12设置及Hidden首显受控检查；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原1384毫秒、BG781毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。

有效前台/后台重置各1次，复用同3个现存窗口并在退出后匹配原通用标题；原生设置/菜单处理器验证不等于系统托盘物理右键、长期驻留或安装验收。具体范围见项目支持矩阵。
<!-- END TARGETED_WINDOWS_REAL -->
