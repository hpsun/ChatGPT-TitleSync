# Rust：ChatGPT-TitleSync / ChatGPT 标题同步助手

[English](README.md) · [项目主页](../README.zh-CN.md)

Windows x64 Release构建及隔离测试已验证。Mac为**Experimental实验源码，未在Mac编译或实测**。实现独立使用Rust及原生接口，不依赖外部crate或C#监听程序。

## 环境与构建
Windows需要Rust的x86_64-pc-windows-msvc工具链、MSVC链接器及Windows SDK。本机使用Rust 1.82、已有MSVC 2019 Build Tools及Windows SDK 10.0.19041，未新增系统安装。
```powershell
.\build.ps1
# 已配置MSVC开发环境时：
cargo test --offline
cargo build --release --offline
```

实验性Mac版本需要Rust、Xcode命令行工具及macOS SDK，原生FFI链接System、AppKit、ApplicationServices、CoreFoundation和Objective-C运行库。
```sh
cargo build --release
```
此Mac命令是未来本机构建说明，不是已经成功构建的结论。

## 运行、间隔及控制
```powershell
.\target\release\chatgpt-titlesync-rust.exe --interval 2 --background-interval 5
.\target\release\chatgpt-titlesync-rust.exe --pause
.\target\release\chatgpt-titlesync-rust.exe --resume
.\target\release\chatgpt-titlesync-rust.exe --stop
.\target\release\chatgpt-titlesync-rust.exe --once --read-only
```
Mac使用./target/release/chatgpt-titlesync-rust及相同参数。--interval范围1..3600秒，缺省**2秒**。--state-dir PATH指定本实现私有控制目录。--once只检查一次前台，然后退出并还原；终端在前台时可能没有目标。

协议分三层：前台来源缺省每2秒fresh读取，不以记住的名称代替；已知后台窗口的generic原生标题每秒用缓存修复，不重新读来源；独立串行后台worker缺省每窗5秒刷新来源，并低频发现未知后台窗口。前台不等待后台来源队列。自定义原生标题保留；提交前复核身份、前后台角色及缓存版本。

Windows共用互斥体Local\TdxChatGptTitleStandalone及停止事件Local\TdxChatGptTitleStandalone.Stop。Mac控制仅针对本Rust实例，不是跨语言协调。暂停／正常退出仅还原仍匹配的自有标题；强制结束不能保证还原。

## 配色45与固定／随机图标

缺省为**固定配色45**，使用统一的45–52透明资源。通过「扫描间隔设置…」打开三个不可编辑下拉框：图标模式「固定／随机」、固定配色「45–52」、随机周期「每日／每小时／每5分钟」。固定配色框仅在固定模式可用，周期框仅在随机模式可用。保存先验证所需资源并提交草稿，取消保持原已提交选择。运行中同步托盘和本程序已打开的设置窗图标，不改写可执行文件或已固定快捷方式。

Windows 请保留随项目分发的 `assets/themes/45.ico` 至 `52.ico`；保存随机模式前要求八个资源均可加载。基准别名为 [ICO](../assets/chatgpt-titlesync.ico)、[PNG](../assets/chatgpt-titlesync-icon.png)、[ICNS](../assets/chatgpt-titlesync.icns)。查找支持可执行文件旁的 `themes/`，以及原目录结构中的相对 `assets/themes/`。正式Windows构建已将基准45的七个分辨率嵌入EXE资源。共用的[资源生成器](../tools/Make-IconResource.ps1)使用PowerShell／.NET BCL生成Win32 RES，再由Windows .NET Framework 4.x的`cvtres.exe`转换并规范化COFF；不另装资源编译器或外部库。所需Windows PowerShell与`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\cvtres.exe`缺失时明确失败，不默默产出通用文件图标。

Windows 各实现共用 `HKCU\Software\ChatGPT-TitleSync` 中的下列值；图标设置不混入本语言的前台／后台时间设置文件。

| 值名 | 类型 | 含义／缺项默认值 |
| --- | --- | --- |
| `IconMode` | REG_SZ | `fixed`（默认）或 `random` |
| `FixedIcon` | DWORD | 45–52，默认45 |
| `IconPeriod` | REG_SZ | `day`（默认）、`hour`、`5min` |
| `RandomIcon` | DWORD | 上一次随机配色，45–52 |
| `IconSlot` | REG_SZ | 上一次已提交的本地时间槽 |

随机模式使用全部八种配色，排除前一个实际显示的配色。启用随机模式或改变周期时立即选择一次；同一有效时间槽内重启沿用已保存配色。时间槽按本机时间生成：每日 `YYYYMMDD`，每小时 `YYYYMMDDHH±HHMM`，每5分钟 `YYYYMMDDHHbb±HHMM`，其中 `bb` 为分钟整除5后的两位编号00–11。UTC偏移区分夏令时回拨后的重复小时。每秒一次的轻量界面时钟只比较时间槽，不读取ChatGPT、不启动读取器；暂停标题同步也不停止图标轮换。

主题注册表、开机自启动与间隔文件共享回滚边界；应用图标失败时保留旧图标和原已提交设置。轮换所需资源缺失时保留最后可用图标，同一时间槽仅记录一次有限诊断，不反复弹窗。旧自有图标句柄在托盘和程序窗体切换完成后释放。已存主题字段非法时报告诊断并以45显示回退，不偷偷改写偏好。worker、probe、once、read-only和控制入口不初始化主题控制器。

实验性Mac前端在 `io.github.hpsun.ChatGPTTitleSync` UserDefaults分类使用同名共享偏好及 `assets/themes/45.png` 至 `52.png`，由前端处理菜单栏／设置窗图标。Go／Rust仍传原有11个参数，不向时间设置文件新增主题字段。本Windows主机未进行Mac原生编译或实机验收，Mac仍为实验源码。

新增受控检查使用注入时钟／随机选择、假持久化或私有注册表键、自有隐藏原生窗口，覆盖八种配色、时间槽和夏令时边界、同槽重启、相邻不重、条件置灰、实际控件保存／取消、合并回滚及图标句柄存活／释放；不替代最终真实驻留验收。

## 时效、隐私与验证
单调时钟截止时间跳过错过的轮次，不在读取完成后额外等待完整间隔。Windows每次启动本程序自身作为隔离读取器，上限4秒，仅使用保留的Child句柄终止。启动或提供器延迟可能超过1秒，检查设置不是1秒完成保证。

Mac前台使用原生前台应用元数据及AXFocusedApplication／AXFocusedWindow，低频发现可读取目标应用AXWindows，来源读取不持缓存／注册表状态锁。只读／拒写不会当成功；日志只含状态、窗口和PID元数据，不记录会话名／正文，内部读取器通信才包含所需根名称。

[验证报告](../docs/release-readiness.zh-CN.md#local-validation)覆盖实际租约／调度逻辑的模拟前台切换、原生COM条件ABI及自有离屏窗口，不是对真实ChatGPT或Mac的验证。

## 后台间隔及验证范围
使用--background-interval N，范围5..3600，缺省5秒。后台原生标题检查独立保持1秒；未知窗口按低频节奏发现，只有有效来源结果才能建立缓存。前台与后台来源独立受控，后台一次只处理一个来源任务，不阻塞前台队列；慢读取或排队会延长实际观察时延，不能宣称1秒内完成。

本次三层fixture覆盖后台generic不读来源修复、保留custom并刷新记忆、未知窗口建缓存、每窗到期时间、版本／身份／旧结果防护，以及后台任务挂起或很慢时前台仍可处理。Windows为隔离测试，不代表真实ChatGPT整体验收。Mac仍标Experimental，本机未做Mac原生编译或AX验证。

## 托盘菜单与扫描间隔设置
Windows 常驻运行现在提供原生托盘图标。右键菜单含「启用窗口标题」「开机自启动」「扫描间隔设置…」「退出并还原标题」。设置窗分别输入前台扫描间隔（1–3600 秒，默认 2 秒）与后台源刷新间隔（5–3600 秒，默认 5 秒）。保存校验、写入本语言私有设置文件，并在当前驻留进程中生效；不会启动第二个标题写入者。禁用或暂停时仅还原本进程仍持有且未被外部改动的标题。修改间隔会废弃旧队列结果并重新安排调度，Windows 在途读取器由其自身保留的子进程句柄取消。

已知非活动窗口标题被软件改回的轻量检查仍固定每 1 秒一次，只使用缓存标题，不重新读取对话源；它不受上述两个源读取间隔控制。下次正常启动加载已保存设置；显式 --interval 或 --background-interval 分别覆盖该次运行的对应值，之后通过菜单保存才持久化。--once 仅使用命令行值且不建托盘；--no-tray 明确选择无菜单的驻留命令行模式。

本次受控测试包含自有隐藏的原生设置窗、合法/非法输入、启用状态保存与重读、保存失败不改变运行设置、热更新调度和正常退出还原。这些不替代真实 ChatGPT 常驻联动验收。

### Mac 菜单仍为实验性源码
Mac 菜单使用公开的 [TraySettings.applescript](../macos/TraySettings.applescript)，由系统 /usr/bin/osascript 与 AppleScriptObjC/AppKit 运行，明确依赖系统运行时，不是独立自包含可执行文件。菜单含启用开关、双字段非模态设置窗与退出。前端只写本语言私有设置/停止文件，标题处理与还原仍由本语言控制器完成。设置文件每 100 毫秒检查一次，标题轻量维护仍为每秒一次。前端异常退出会停止监控并还原已持有标题；缺失源码或启动失败明确报错，可使用 --no-tray 命令行模式。

源码运行时保留 macos/、assets/ 目录；也可将 TraySettings.applescript 放在可执行文件旁并保留 ../assets/chatgpt-titlesync-icon.png。本机无 Mac SDK，Mac 后端与该菜单仅经源码检查，**尚未本机编译或实机验证**。

私有设置文件：settings.conf，位于 APPDATA/ChatGPT-title-rust（Windows）或 HOME/ChatGPT-title-rust（Mac）；--state-dir 可另选本语言私有目录。

<!-- BEGIN TARGETED_WINDOWS_REAL -->
以下针对性观察来自改名前版本。改名后的 Windows 构建另做离线/自有夹具检查，改名本身不表示已新增真实 ChatGPT 实测。

## Windows真实窗口专项验收 — 2026-11-11

30项受控通过，Windows x64原生托盘；Mac伴随源码仍Experimental/未编译；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原1018毫秒、BG624毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。

有效前台/后台重置各1次，复用同3个现存窗口并在退出后匹配原通用标题；原生设置/菜单处理器验证不等于系统托盘物理右键、长期驻留或安装验收。具体范围见项目支持矩阵。
<!-- END TARGETED_WINDOWS_REAL -->

## 改名后的兼容身份

当前软件名称为 **ChatGPT-TitleSync / ChatGPT 标题同步助手**。Windows 旧互斥体/停止事件 `Local\TdxChatGptTitleStandalone` 及 `.Stop`、已有状态目录、原生自动化类名、租约及控制文件格式刻意保留，用于承接已有设置，并阻止旧版和改名版 Windows 驻留程序同时写入标题。兼容身份中的历史名称不是当前品牌。默认前台 2 秒、后台 5 秒，已有合法保存值继续优先。

## 开机自启动（缺省开启）

托盘右键「开机自启动」以勾选状态表示并立即保存/应用。设置窗口也提供同名复选框，保存才提交，取消不改变已保存选择；菜单成功变更后会同步已打开的设置框，同时保留尚未提交的间隔输入。系统注册或文件保存失败会报告错误并保留原已提交状态；文件提交失败时回滚本次注册表变更。

Windows 各语言共享 `HKCU\Software\ChatGPT-TitleSync` 中的 DWORD `AutoStartEnabled`：缺项默认开启，显式 0 在换语言、重启后继续沿用。正常驻留取得原跨版本互斥锁后，才在 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 的值 `ChatGPT-TitleSync` 写入当前带引号的绝对 EXE 路径，不附带测试或 state-dir 参数。换语言时替换同一项，不新增多条开机项。正常退出不会取消已保存的开机启动选择。

worker、probe、自测、once、read-only 和控制请求均不注册。read-only 驻留使用命令行/控制文件而不建托盘，避免只读上下文通过界面新增启动项。本实现不支持 --settings CLI 参数，会在取得互斥锁/注册之前拒绝；请通过托盘打开设置。

私有设置文件同步保存 `autostart_enabled`，旧文件缺项默认 true；正常 Windows 启动以共享注册表偏好为准。新增离线验证仅用自有临时注册表子键，不碰真实 Run 项或共享偏好，覆盖默认开启、关闭继承、系统/文件失败回滚、菜单/复选框同步及保存/取消。本次构建仍待根控制器进行真实启动验收。

实验性 Mac 前端第 10 参数为 autostart_enabled，第 11 参数为当前绝对 EXE 路径。用户 LaunchAgent `~/Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist` 由共享前端管理，Go/Rust 只传已提交状态并观察文件变更；--no-tray 跳过该可选前端及其自启动管理。本 Windows 主机未建立 Mac LaunchAgent，也未做 Mac 原生编译或实机运行。

Windows 开启时，带引号的完整 Run 命令长度最多 260 个 UTF-16 字符；超限会明确报错并保持 Run/偏好原状，关闭不受此长度限制。相同命令与偏好已经一致时不重复写入。[Microsoft Run/RunOnce 文档](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)。
