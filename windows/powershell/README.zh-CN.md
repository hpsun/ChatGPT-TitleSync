# ChatGPT 标题同步助手 — PowerShell

[English](README.md) · [项目主页](../../README.zh-CN.md)

Windows x64源代码草稿。已在Windows PowerShell 5.1和PowerShell 7中验证脚本解析、内嵌C#编译及模拟前台状态；本分支未操作真实ChatGPT验证。

## 名称替换——缺省规则为空

托盘 **Name replacement… / 名称替换…** 和设置窗中的同名按钮打开共用Unicode编辑器。初始**没有任何规则**，不会自动去掉厂商前缀或提取括号。可逐条启用并调整顺序。**Plain text / 普通文字**按区分大小写的原文全局替换，替换内容按普通文字处理；**Regex / 正则**采用Windows .NET引擎，支持 `$0`～`$99`、`${0}`～`${99}` 和 `$$`，拒绝未知或不存在的捕获引用。

当前对话下拉读取监控器的私有 **CTS1来源快照**，显示时间并可刷新文件，不为此额外读取ChatGPT或UIA。快照缺失或无效时仍可手工输入示例。**建议规则**根据当前示例或所选文字派生转义后的候选，包含去前缀、保留分隔符后内容、成对符号内部等；建议只是草稿，必须先点**使用规则**，再点**保存**才生效。**取消**不保存。预览只处理本地示例，并使用有界子进程。

Windows前端共享 `%LOCALAPPDATA%\ChatGPT-TitleSync\title-rules.json`，与间隔、自启动和图标设置分开。规则只作用于可信原始对话名，之后才拼显示后缀。配置、替换引用、匹配超时、空白／控制字符／通用名结果、超长输出或孤立UTF-16代理项，均回退**完整原始来源名**，不使用中途结果。共用工具每条正则限制100毫秒、整条链500毫秒；调用方对规则worker设置1500毫秒期限，排队和调度仍可能增加耗时。相同原名及规则签名复用成功／回退缓存，不每秒重启worker。

保存规则从raw缓存重新派生已知显示，不重置来源读取截止时间。重绘仍核验同一窗口身份及“当前标题等于本实例最后写入值”，保留外部手工标题。运行期 `title-rule-sources.bin` 包含私人对话名，不应发布。

已建立客户端后，显示签名同时包含规则内容及worker文件的存在性、大小和修改时间；补回同路径worker可让相同raw重新格式化，不为此多读来源。PowerShell启动时若未找到共用工具，该功能保持不可用；补齐后须重启脚本。这里不提供缺包启动后的程序集热加载。

参见[名称替换帮助](../../docs/name-replacement.zh-CN.md)及打包的[本地HTML帮助](../../docs/name-replacement.zh-CN.html)。

### 可关闭的 ChatGPT 后缀

**Append — ChatGPT / 标题末尾显示ChatGPT** 缺省勾选；取消后只显示派生对话名。该项独立于规则总开关，空规则或停用规则时也能关闭后缀。保存才生效，取消不修改保存字节。旧schema-1配置可缺少 append_chatgpt_suffix（按true处理）；存在时必须是JSON布尔值。

原始名缓存、原窗口标题和读取时序保持不变。保存后在维护节拍热更新已由程序管理的窗口，不增加来源读取；外部手工标题仍受保护。合法正文/完整标题上限为512/522个UTF-16单元。可解码但超长或含控制符的非法来源，完整回退原文，不附后缀也不截断。CLI的 --format 保留正文协议，--format --caption 返回完整标题；读取失败默认加后缀，配置合法且为false时规则匹配回退仍不附加。正常C#/PowerShell直接消费完整标题，不再重复拼接。

子进程仍限1,500毫秒。同一原始名与规则/helper签名的成功或回退结果会缓存，直到签名变化、观察到别的原始名或驻留程序重启才重试；保存会生成新规则修订号。私有并行验证曾记录WorkerTimeout，随后两个PowerShell宿主各一次低载顺序复测均返回ok，false实际生效；不能据此承诺统一响应时延。失败原始证据保留。

### 新功能验证边界

共用工具已有Unicode／CLI纯测试，覆盖整链回退和孤立代理项；注入后端证明缓存重绘不增加来源读取。PowerShell5.1／7客户端检查使用私有文件与模拟窗口后端。编辑器效果图仅用虚构示例、从未显示的自有控件，模拟100%、125%、150%字体与几何，表头字形内容区完整；另以自有离屏NOACTIVATE／Hidden夹具核验候选的显式原生显示且前台不变。这些检查**不代表**新增正常桌面、登录启动、物理托盘菜单或全部实时UIA验收；下方早期真实窗口结果保留原日期和范围。

### 共用工具与PowerShell加载

先从本目录执行 `powershell.exe -NoProfile -File ..\..\shared\windows\Build.ps1`。名称替换需要生成的 `ChatGPT-TitleSync.Rules.exe`，可放脚本旁或保留仓库 `shared/windows` 位置。脚本自动使用 `[Reflection.Assembly]::LoadFrom(...)` 加载纯BCL客户端；PS7不能用 `Add-Type -Path` 加载EXE，框架JSON／正则匹配留在隔离规则进程内，主机使用原生JSON检查空规则。没有共用工具时，该功能入口不可用；原有监控不由它接管。该工具不是PS脚本的EXE封装。


## 环境与构建
使用64位Windows PowerShell 5.1；父脚本也可使用PowerShell 7。隔离读取器固定使用Windows自带的Windows PowerShell 5.1及UIAutomation程序集，无需MSVC或额外SDK；名称替换另用打包的共用C#规则工具，原生绑定仍由Add-Type在内存中编译。


## 品牌与兼容性

正式名称为 **ChatGPT 标题同步助手／ChatGPT-TitleSync**。保留 `Local\TdxChatGptTitleStandalone` 及 `.Stop`／`.Settings` 事件，确保旧独立版不能同时写标题。现有 `%LOCALAPPDATA%\ChatGPT-title` 数据位置与设置字段保持兼容。脚本入口现为 `ChatGPT-TitleSync.ps1`，仍可用 `-LogDirectory` 指定私有数据位置。下方历史真实窗口观察早于品牌与自启动修改；本次自有／离线检查另行注明范围。

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

注册命令为实际父PowerShell主机和绝对脚本路径，均加双引号：`"<实际主机.exe>" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "<绝对脚本路径>"`，不保留测试日志路径或间隔参数。脚本与所需图标资源应保留在该位置。只读常驻模式禁用自启动控件。

菜单项与设置复选框的控件名均为 `AutoStartEnabled`。前台2秒／后台5秒缺省值、监测设置JSON字段及旧互斥身份保持兼容。本项已用从不显示的自有控件、临时当前用户注册表键验证，包含C#/PowerShell互读关闭偏好；这不等于新增真实Run／登录启动验收。

## 运行与间隔
在当前目录运行：
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-TitleSync.ps1 -IntervalSeconds 2 -BackgroundIntervalSeconds 5
# 只读单次检查：
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-TitleSync.ps1 -ReadOnly -Once
```

缺省**2秒**；-IntervalSeconds范围1..3600，别名-interval。前台直接采样当前ChatGPT来源，后台走独立低频来源worker，终端处于前台时，单次检查可能没有结果。调度使用单调时钟的截止时间，跳过错过的轮次，不在每次读取完成后额外等待一个完整间隔。

## 停止与还原
在另一个终端运行：
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-TitleSync.ps1 -Stop
```

Windows各语言版本共用互斥体Local\TdxChatGptTitleStandalone与停止事件Local\TdxChatGptTitleStandalone.Stop，只运行一个独立版本。正常停止或退出时，仅还原仍与本实例写入值一致的自有标题；强制结束进程不能保证还原。

后台窗口保留可信标题缓存，原生通用回改无需重读来源即可修复，后台来源由独立低频任务刷新。读写前后复核前台、HWND、PID、创建时间、类名和程序路径；失焦取消自有读取器并丢弃旧结果。应用原生标题重置成ChatGPT不会触发人工改名退避；真正的自定义标题释放写入所有权并保留。

## 已选图标与封装
.ps1由PowerShell解释器承载，脚本本身不会嵌入EXE图标。快捷方式可选用共享[baseline45 ICO](../../assets/chatgpt-titlesync.ico)。如另行封装EXE，须单独嵌入该资源；本脚本未生成此类封装。快捷方式图标与宿主EXE图标是不同层次。

## 限制与验证
每次采样都启动隔离PowerShell读取器，编译绑定并初始化UIA，可能超过1秒。1秒调度不等于1秒内完成读取。-ReaderTimeoutMilliseconds缺省6000，可另行设置。

运行日志仅记状态元数据；-ReadOnly诊断输出按用途包含根网页区域名称，不遍历会话正文或凭据字段。终止读取器仅使用本次保留的自有进程句柄。

[本次受控验证](../../docs/release-readiness.zh-CN.md#local-validation)使用实际处理函数和模拟前台／读取／写入后端，不是对真实ChatGPT或Mac的验证。

## 后台间隔及验证范围
使用-BackgroundIntervalSeconds N（别名-background-interval），范围5..3600，缺省5秒。后台原生标题检查独立保持1秒；未知窗口按低频节奏发现，只有有效来源结果才能建立缓存。前台与后台来源独立受控，后台一次只处理一个来源任务，不阻塞前台队列；慢读取或排队会延长实际观察时延，不能宣称1秒内完成。

本次三层fixture覆盖后台generic不读来源修复、保留custom并刷新记忆、未知窗口建缓存、每窗到期时间、版本／身份／旧结果防护，以及后台任务挂起或很慢时前台仍可处理。Windows为隔离测试，不代表真实ChatGPT整体验收。正常控制器用两个保留自有句柄的子任务和零时等待轮询，未通过真实ChatGPT检验。

## 托盘与扫描设置（补充）

常驻模式缺省提供45号托盘图标和右键菜单：启用标题、扫描间隔设置、退出并恢复标题。设置窗是非模态窗口，支持输入前台1至3600秒、后台5至3600秒，缺省2秒和5秒；非法输入就地显示错误。保存后立即生效，将启用状态和两个间隔保存到LogDirectory下的powershell-settings.json。显式命令行间隔优先于已保存值。原生后台标题回改检测保持每1秒。

修改设置会取消自有读者并使旧任务代次失效，旧结果不能覆盖新设置下的状态。关闭启用选项会取消读者并恢复仍由本实例拥有的标题；重新启用启动新的来源读取。`-Settings` 通知已运行实例调用同一设置菜单处理器，不启动第二个实例。Worker、ReadOnly配合Once、Stop均不启动托盘。

托盘缺省使用共享45号ICO，并支持下述八色主题。脚本宿主EXE自身的图标仍由宿主决定，名称替换另依赖共用规则EXE；登录自启动仍使用上述共享Run项。

公开验证入口：`tools/test-tray-settings.ps1`，分别在Windows PowerShell 5.1与PowerShell 7下运行。两者各通过9项菜单回调、输入校验、即时状态更新、再次覆盖保存、重新打开及退出请求测试；另有32项调度回归。夹具控件不会显示、激活或读取真实ChatGPT，不发送共享Stop。File.Replace的备份参数使用[NullString]::Value，避免PowerShell把空值转换为空路径。

## 隐藏启动后的设置首显

Windows以STARTUPINFO的Hidden启动进程时，第一次普通Show可能被启动提示压制。设置入口现先使用SetWindowPos明确显示自有窗口，再请求激活；这是原生窗口可见性问题，与UI Automation来源读取分开。

公开入口tools/test-tray-settings.ps1已加入独立自有WinExe回归：确认STARTF_USESHOWWINDOW和SW_HIDE，观察首次原生Show仍隐藏，再验证生产显示辅助方法与WinForms窗体确实可见。夹具位于屏幕外并使用WS_EX_NOACTIVATE，核验前台窗口不变；已分别在PowerShell5.1和7执行。它是受控首显验证，不冒充真实ChatGPT或系统托盘菜单整体验收。

<!-- BEGIN TARGETED_WINDOWS_REAL -->
## Windows真实窗口专项验收 — 2026-11-11

PowerShell5.1/7专项实测通过：2/5设置、保存重开还原、来源/页头/原生标题一致；FG复原881/342毫秒、BG794/282毫秒，各次正常退出后3窗为原通用标题。每主机32+9项受控及Hidden首显回归单列。

有效前台/后台重置各1次，复用同3个现存窗口并在退出后匹配原通用标题；原生设置/菜单处理器验证不等于系统托盘物理右键、长期驻留或安装验收。具体范围见项目支持矩阵。
<!-- END TARGETED_WINDOWS_REAL -->
