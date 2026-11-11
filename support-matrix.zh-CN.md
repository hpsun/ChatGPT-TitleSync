# 支持与验证矩阵

[English](support-matrix.md) · [机器可读状态](support-matrix.json) · [项目说明](README.zh-CN.md)

快照：2026-11-11，北京时间。用户已于2026-11-11明确批准，正常仓库文件公开发布进行中；此前未发布/待批准状态为历史快照。本次不上传项目ZIP，缺省启用当前用户登录自启动；图标仍为当前已选资源。八种语言，AHK 三个运行时分别列出。


当前默认开启自启动源码正在开展新一轮Windows真实复测；此前九路线时延／设置结果不能替代本轮新版验收。见[启动契约](docs/startup.zh-CN.md)。Mac自启动仅有Experimental源码。
## 当前源码状态

## 当前候选的验证

当前品牌、自启动及八色主题源码已完成下表受控检查；九种Windows运行方式的最终真实窗口复测仍在进行。C#已给三个现存窗口改名，但独立4秒冷探针有一窗超时，因此该案例尚未全部通过；程序已正常退出并恢复原状态。旧实测不替代本次验收。

| 实现 | 当前受控证据 |
| --- | --- |
| C# | 37项主题＋22项自启；取消确实关闭 |
| AHK Basic | 30项主题＋14项自启＋6项设置；仅源码 |
| AHK v1.1 / v2 | 各30项主题＋14项自启＋11项设置；七帧内嵌 |
| PowerShell 5.1 / 7 | 各37项主题回调／事务检查 |
| Python | 35项主题＋14项自启＋17项设置；18项公开纯主题测试 |
| Go / Rust | 51／43项受控检查；自有程序自测；七帧内嵌 |
| Swift / Objective-C / Go macOS / Rust macOS | 实验源码；无Mac原生构建或运行结果 |

## 旧修订的验证记录

以下保留此前测量，其源码哈希及旧检查另列于JSON的previous_revision；不作为当前候选已完成全部实测的证据。

| 实现 | 目标 | 当前证据与边界 |
| --- | --- | --- |
| [C#](windows/csharp/README.zh-CN.md) | Windows | 41策略＋13 helper/Job＋8间隔协议＋12设置及Hidden首显受控检查；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原1384毫秒、BG781毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。 |
| [AutoHotkey v1.0 Basic](windows/ahk-v1.0/README.zh-CN.md) | Windows | Basic1.0.48.05 ANSI x86，仅源码路线，没有已验收Basic EXE；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原1098毫秒、BG632毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。 |
| [AutoHotkey v1.1](windows/ahk-v1.1/README.zh-CN.md) | Windows | 当前x64包；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原2247毫秒、BG667毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。 |
| [AutoHotkey v2](windows/ahk-v2/README.zh-CN.md) | Windows | 当前x64包；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原1056毫秒、BG409毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。 |
| [PowerShell](windows/powershell/README.zh-CN.md) | Windows | PowerShell5.1/7专项实测通过：2/5设置、保存重开还原、来源/页头/原生标题一致；FG复原881/342毫秒、BG794/282毫秒，各次正常退出后3窗为原通用标题。每主机32+9项受控及Hidden首显回归单列。 |
| [Python](windows/python/README.zh-CN.md) | Windows | 最终EXE来源/页头及稍后原生标题一致，FG复原161毫秒、BG379毫秒，退出后3窗为原通用标题。此前两次守卫未注入，不当产品失败；独立设置补证同进程精确持久化/重开7/17并还原2/5；原33/10歧义保留，不下产品缺陷结论，未Mac验证。 |
| [Swift](macos/README.zh-CN.md) | macOS | 原生三层/菜单设置源码草稿，使用独立UserDefaults域及热更新代次重置；仅静态复核，未Mac SDK编译、偏好运行、真实AX或界面验收。 |
| [Objective-C](macos/README.zh-CN.md) | macOS | 原生三层/菜单设置源码草稿，使用独立UserDefaults域及热更新代次重置；仅静态复核，未Mac SDK编译、偏好运行、真实AX或界面验收。 |
| [Rust](rust/README.zh-CN.md) | Windows／macOS | 30项受控通过，Windows x64原生托盘；Mac伴随源码仍Experimental/未编译；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原1018毫秒、BG624毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。 |
| [Go](go/README.zh-CN.md) | Windows／macOS | 38项受控通过，Windows x64原生托盘；Mac伴随源码仍Experimental/未编译；真实2/5设置/保存/重开/还原与来源一致性专项通过；FG复原1784毫秒、BG448毫秒，正常退出后3窗为原通用标题。单次观测，不是基准。 |

## 协议与判读

原生身份／标题每秒核对，前台新鲜来源缺省每2秒，后台来源缺省每窗口 5 秒且单串行角色。前台不用缓存代替新来源；后台通用标题回改可立即用同身份可信缓存修复。非通用外部标题保留。调度间隔不等于冷读取完成期限。

JSON 单列历史检查及所属版本；它们不证明当前源码的真实切换、长期驻留、安装或任务栏效果。Mac 共享模型不算原生验证，也不按语言重复累计。所有 Mac 后端均为 Experimental：未 Mac 编译／AX 验收。远程 CI 尚未运行。

C#、AHK、PowerShell、Python、Go、Rust均已有Windows托盘设置源码；各分支的真实菜单验收状态另列。Go/Rust仍可选择CLI；其Mac菜单由公开osascript伴随源码实现。Swift/Objective-C原生菜单与全部Mac后端保持实验性，未原生编译或AX验收。Basic 即使二进制保留 UTF-16 标题，仍要求 ASCII 启动／运行时／IPC 路径及 ANSI x86。

见[指南环境要求](docs/guides-index.zh-CN.md)及[本地验证摘要](docs/release-readiness.zh-CN.md#local-validation)。原报告、缓存、真实标题和身份均私有留存，不进入源码交付；[source-sha256.txt](source-sha256.txt) 记录最终冻结的源码／构建／工作流／测试校验值。窗口标签不改变 Windows 应用分组或 macOS Dock 应用名称。

隐藏后退出还原缺陷已由独立受控案例修复；以上集成计时采于该保护修复前，相关前台／原生标题维护路径未改变。

独立版真实专项中，设置后台 15 秒后，三个窗口工作进程尝试间隔分别观测约 15.16、15.17 和 22.20 秒。串行读取和前台优先可造成延后，不能承诺每窗口严格每 15 秒读完。正常 --stop 后独立程序及其前后台 helper 均无残留，配置原字节和原对话已恢复。计时样本采于隐藏 lease 保护修复前，相关计时路径未变；最终 EXE 包含该受控修复。以上为有限样本，不是延迟保证。
