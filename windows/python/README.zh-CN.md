# ChatGPT 标题同步助手 — Python

## 改名后的兼容性

界面文字目前固定，不会按 Windows 系统界面语言自动切换。Python 使用中英混合文字。

软件现名为 **ChatGPT-TitleSync / ChatGPT 标题同步助手**。为继承用户设置并避免旧程序与新程序同时改写标题，继续保留原有 `Local\TdxChatGptTitleStandalone` 及 `.Stop` 通信名称、`%LOCALAPPDATA%\ChatGPT-title\...` 设置位置和 `TdxChatGptTitles` 日志目录；内部类标识和描述性源文件名也保留。此次改名只进行语法、构建及隔离自有夹具检查，既有真实窗口结果说明未改动的标题策略，不冒充改名界面的新一轮实机验证。

[English](README.md) · [HTML](README.zh-CN.html)

**缺省间隔候选更新（2026-11-10）。** 首次运行缺省采用前台 **2秒**、后台 **5秒**。已有合法用户设置保留；显式命令行参数继续优先于对应已保存值。Python和现代AHK候选已重建，Basic仍只交付源码。分支隔离测试不等于真实ChatGPT或系统托盘菜单已经验收，真实验收另行记录。

## 依赖与源码运行

Windows、Python 3；监控端只用标准库 ctypes/subprocess，不依赖 pythonnet；名称替换使用下述单独构建的共享 C# 辅助程序。

源码脚本可直接运行，无需编译：

    python chatgpt_window_titles.py
    python chatgpt_window_titles.py --interval 2 --background-interval 5
    python chatgpt_window_titles.py --read-only --once
    python chatgpt_window_titles.py --self-test
    python chatgpt_window_titles.py --stop

`--once` 仅执行一次前台读取后退出，不启动后台循环。Python 可用 Ctrl+C 或托盘退出；AHK 托盘也提供退出入口。正常退出仅还原仍由本次运行拥有、身份与最后写入值一致的标题；强制结束无法执行还原。

## 最新调度规则

- 前台缺省每 2 秒重新读取当前会话名，`--interval` 可设不小于 1 秒。失败时不用旧缓存冒充新名称。读取前后与写入前均核对前台、HWND、PID、创建时刻及类名／路径。
- 已知后台窗口每 1 秒仅检查原生身份和 caption。被应用改回通用 `ChatGPT` 时立即使用最近核实的缓存会话名恢复，不为此再读 UIA；仍为最后写入值时不动。外部 custom 改名保留，身份失效清除缓存。
- 后台真实来源缺省每窗 5 秒低频刷新，可用 `--background-interval 15` 或 `30`，范围 5–3600 秒。未知后台窗口也可据此建立首份缓存。只沿固定直系 RawView 路径读取 Document[RootWebArea].Name，不展开正文。
- 最多一个前台和一个串行后台自有读取子进程，句柄和输出按角色区分。后台目标成为前台时丢弃／取消旧后台结果，前台重新读取。后台读取超过 1 秒不因普通前台 tick 而被反复取消。后台刷新结果仅在 caption 仍为通用值或自己最后写入值时改名，custom 不覆盖。
- **2 秒是前台检查／调度间隔，不承诺完整读取在 2 秒内结束；5 秒是每窗到期间隔，不是所有窗口硬完成时限。** 单次读取 watchdog 目标 4 秒，排队与 UIA 启动耗时可能延后完成。AHK 定时器为协作线程，后台完成处理或超时清理可能等待前台回调返回。只结束自己创建并持有身份的读取器，不结束 ChatGPT。

不读私库、正文、Explorer／任务栏全树，不启调试端口，不改任务栏分组设置。所有独立 Windows 版本共享 `Local\TdxChatGptTitleStandalone` 互斥与 `.Stop` 事件，同一时间只运行一份；也不要与驻留助理内置标题功能并行争用。

## 构建、图标与交付边界

完整构建命令见[英文主指南](README.md)。Python 冻结后、AHK 编译后均直接用自身 EXE 启动 worker，源码模式用匹配解释器＋脚本。基准45图标为 [chatgpt-titlesync.ico](../../assets/chatgpt-titlesync.ico)，可给源码快捷方式指定该图标。

历史构建基线曾通过 Python x64 console/onedir、AHK v1.1 x64、AHK v2 x64 的自有 Unicode 窗口／还原、打包后自身 worker、测试自建 Stop 事件与 A1 七帧资源检查；图标主题加入前的三份候选曾重建，其打包后的隐藏自有窗／自身 worker smoke 已通过。Python 必须交付整个 onedir 目录及 `_internal`，windowed／one-file 未验收。Basic 旧编译器发生访问冲突，另一次现代编译器配原 ANSI base 超时；失败残留不得交付，Basic 提供已通过当前 11 项策略测试的源码，不交付失败编译残留。

源码级私有测试 IPC 还验证了正常退出会回收前台和后台两个自有读取器，未向正在运行的控制器发送共享 Stop。此前打包基线已验证共享 --stop 入口；本轮不把它冒充新包再次试发的结果。

原创代码许可见根 LICENSE；第三方运行库、编译器和打包依赖各自许可仍适用。各分支的支持边界见根[支持矩阵](../../support-matrix.md)。Windows 结果不外推为 macOS 编译或 AX 实机通过。

## 运行时图标主题（基准45）

缺省使用**固定45**。EXE基础资源及根[ICO](../../assets/chatgpt-titlesync.ico)保持45。设置窗口新增三个**不可编辑的下拉框**：固定／随机、固定配色45–52、每日／每小时／每5分钟。固定时只启用配色，随机时只启用周期。保存与检查间隔、自启动一起应用；取消不变更已提交设置。校验或持久化失败会回滚已更改的图标／自启动状态，保留可用图标；数值Edit仍只有两个。

45–52依次为：蓝紫／白、青／黑、琥珀／黑、薄荷／黑、玫红／白、天蓝／黑、淡紫／黑、珊瑚／黑。各Windows语言版本共用HKCU\Software\ChatGPT-TitleSync中的5项：IconMode（REG_SZ fixed/random）、FixedIcon（REG_DWORD 45..52）、IconPeriod（REG_SZ day/hour/5min）、RandomIcon（REG_DWORD 45..52）及IconSlot（REG_SZ）。缺项读取为fixed/45/day，不因此写入；自启动偏好为独立命名值。只读、worker、一次检查、停止／控制和自检不写真实图标偏好。已有偏好不合法时只报告有界元信息并回退45，不悄悄覆盖原数据。

启用随机或改变周期立即选一次，相邻随机选择不重复；同一时段重启沿用已保存选择。跨语言精确slot：每日YYYYMMDD；每小时YYYYMMDDHH±HHMM；每5分钟YYYYMMDDHHbb±HHMM，bb为minute//5的两位00..11。仅在已有元数据定时器廉价检查，不增读GPT或新增读取器。缺资源／轮换失败保留旧图标，每个失败slot最多记录一次。暂停标题处理不影响图标轮换。运行时只修改本程序托盘及自有窗口图标，不改EXE或固定快捷方式。

源码由[chatgpt_window_titles.py](chatgpt_window_titles.py)与同目录**[icon_preferences.py](icon_preferences.py)**共同组成，源码运行须保留辅助文件。PyInstaller自动收集导入模块；构建命令需额外纳入8个正常ICO到_internal/assets/themes，并完整交付onedir目录。

```powershell
python -B tests/test_icon_preferences.py
python chatgpt_window_titles.py --icon-self-test
```

18项公开纯策略单测使用假持久化／资源／时间，不访问注册表；另有35项受控检查通过，包括隐藏原生设置保存／取消、五值及间隔／自启动回滚、旧图标句柄存活。 本轮不将这些结果称为真实GPT、托盘鼠标菜单或登录启动验收；版本仍为0.1.0。

## 开机自启动（缺省已开）

正常驻留先取得原有共享控制器互斥，再读取共用自启动偏好；偏好缺项视为**已开**。托盘右键的 **开机自启动 / Start at sign-in** 项直接显示√并即时应用切换。设置窗口有**同名 开机自启动 / Start at sign-in**复选框，只有保存才生效，取消不改自启动；菜单切换会同步已经打开的设置框，保存后菜单也显示同一状态。失败会提示错误并保留或恢复此前登记，不假报成功。

所有 Windows 实现共用当前用户注册表约定：

| 位置 | 值 | 含义 |
| --- | --- | --- |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` | `ChatGPT-TitleSync`（REG_SZ） | 当前实现带正确引号的绝对启动命令 |
| `HKCU\Software\ChatGPT-TitleSync` | `AutoStartEnabled`（DWORD） | 缺项为1；1已开；显式0关闭，跨实现及重启保留 |

关闭只删除本产品的 Run 值，并保留 DWORD 0；下次启动或更换实现不会强制重新开启。开启时仅在需要时更新当前实现命令，相同命令和偏好不反复写入。不使用管理员权限、服务或计划任务。

登记命令只包含编译 EXE，或匹配解释器加源脚本，不携带测试日志／设置位置、显式检查间隔或其他测试参数。Python 冻结目录须完整保留，源脚本和解释器位置应稳定。开启时若命令超过 Windows Run 的**260字符**限制，明确报错，Run和偏好保持原样；即使命令过长仍可关闭。依据见[微软 Run 键说明](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)。

只读、worker、停止、一次检查／check及自检模式不登记真实自启动。以下自检仅使用可注入临时 HKCU 自有子键及隐藏自有控件：

    python chatgpt_window_titles.py --autostart-self-test

该测试覆盖默认已开、跨启动保留显式关闭、源码／冻结命令引号、相同值不写入、源码命令260／261字符、失败回滚、菜单与复选框同步、保存和取消；不声称已经真实登录或重启系统验证。


## 托盘扫描间隔设置

右键点击 A1 托盘图标，选择 **扫描间隔设置…**。两个输入项分别是前台来源检查间隔（默认 **2 秒**，范围 **1–3600 秒**）和每个后台窗口的来源刷新间隔（默认 **5 秒**，范围 **5–3600 秒**），范围内可输入小数。保存后无需重启即可生效；取消不改变设置。输入非法或保存失败时保留当前有效配置。

设置以 JSON 保存在 `%LOCALAPPDATA%\ChatGPT-title\python\settings.json`。首次保存自动建立父目录，后续保存替换同一文件。启动时显式给出的 `--interval` / `--background-interval` 分别优先于对应已保存值；托盘保存的新值将供后续启动使用。修改后会取消自身持有的前台、后台读取器并重新安排检查，避免应用旧设置轮次产生的结果。

轻量级原生窗口检查及缓存标题恢复仍独立地每 **1 秒**运行。两个参数不改变 UIA 读取超时、停止信号检查或所有内部定时器。右键菜单的退出并恢复标题仍执行正常清理。本次加入上述当前用户自启动开关，不改变全局环境设置。

2026-11-10 间隔设置测试仅使用隔离夹具：Python 通过 17 项设置与原生窗口检查；AHK Basic 通过 6 项设置检查；Unicode AHK v1.1 和 v2 各通过 11 项。现代 AHK 覆盖隐藏设置窗内容、热更新调度、父目录不存在、首次和重复保存、非法输入、保存失败保持原值及临时文件清理。预期的输出失败捕获为诊断，不弹出未处理错误窗。这些结果不代表真实 ChatGPT 来源提供器或系统托盘菜单已经验收，真实验收另行记录。

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Windows真实窗口专项验收 — 2026-11-11

最终EXE来源/页头及稍后原生标题一致，FG复原161毫秒、BG379毫秒，退出后3窗为原通用标题。此前两次守卫未注入，不当产品失败；独立设置补证同进程精确持久化/重开7/17并还原2/5；原33/10歧义保留，不下产品缺陷结论，未Mac验证。

有效前台/后台重置各1次，复用同3个现存窗口并在退出后匹配原通用标题；原生设置/菜单处理器验证不等于系统托盘物理右键、长期驻留或安装验收。具体范围见项目支持矩阵。
<!-- END TARGETED_WINDOWS_REAL -->

## 名称替换：共享 Unicode 辅助程序

托盘 **名称替换… / Name replacement…** 与设置窗口中的同名按钮打开**同一个**共享编辑器：有序字面/正则规则、预览、已读原名下拉列表、通用正则建议及本地帮助。建议必须明确点击“使用规则”，再保存才生效。缺省为空规则/原样显示，不内置本机或个人规则，也不从无关软件迁移。

先从本分支目录构建辅助程序：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "..\..\shared\windows\Build.ps1"

该命令用 Windows .NET Framework 编译器编译 [TitleRules.cs](../../shared/windows/TitleRules.cs)。运行时保留 `ChatGPT-TitleSync.Rules.exe`：放在主 EXE 旁，或保持仓库 `../../shared/windows` 布局；不会从 PATH 或偏好指定的命令寻找程序。须保留[中文帮助](../../docs/name-replacement.zh-CN.md)与 [English help](../../docs/name-replacement.md)，包括同名 HTML。

规则独立保存在 `%LOCALAPPDATA%\ChatGPT-TitleSync\title-rules.json`；打开、读取、预览不创建配置，只有编辑器成功保存才写入。间隔、启动项和图标保存不覆盖规则。文件缺失时原样显示；已有规则但辅助程序不可用时完整回退原名并记诊断，不假报成功。

先对**已核实原名**格式化，再拼接标准 ` — ChatGPT` 后缀。原始来源缓存、原生原标题恢复凭据不改；独立显示修订只更新仍由本次运行拥有且等于上次写值的标题，保护手工及通用原生标题。来源计划与每秒缓存修复仍独立；格式化是异步、自有句柄绑定的子进程，1500 毫秒截止，只终止该自有进程；成功和回退均缓存，旧代丢弃。规则签名按有界每秒节拍核对，不新增 ChatGPT 来源读取。

运行/设置目录中的 `title-rule-sources.bin` 是**私有** CTS1 快照，仅含已核实原名，仅在名称/窗口集合变化后更新，不得提交或公开。编辑器下拉框读取它，不另读辅助树。

源码部署将 [name_replacement.py](name_replacement.py) 与主脚本放在同一目录。PyInstaller 会识别其静态导入；自定义 spec 须保留它，也可加 `--hidden-import name_replacement`。共享规则 EXE 仍须外部保留。上文 onedir 构建之后：

    $bundle = ".\build\dist\ChatGPTTitleSyncPython"
    Copy-Item "..\..\shared\windows\ChatGPT-TitleSync.Rules.exe" $bundle
    New-Item -ItemType Directory -Force "$bundle\docs" | Out-Null
    Copy-Item "..\..\docs\name-replacement.html","..\..\docs\name-replacement.zh-CN.html" "$bundle\docs"
    python -B tests/test_name_replacement.py -v

适配器已通过 14 项自有文件/进程检查，另通过 8 项调用真实共享格式化程序的私有检查；覆盖 Unicode CTS1、完整回退、缓存失效、超时、旧代丢弃和模拟所有权保护。

以上是格式化、协议和受控所有权检查，不启动编辑器或正常驻留，不读 ChatGPT，不改生产启动项/偏好，不表示本轮真实桌面/菜单已经复测。限制、严格替换引用、操作系统正则差异与完整原名回退规则见所链接帮助。
