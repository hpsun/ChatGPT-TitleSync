# ChatGPT 标题同步助手：Swift、Objective-C与AppleScript实验性Mac前端

[English](README.md) · [项目主页](../README.zh-CN.md)

**Experimental：Swift、Objective-C及AppleScript伴随程序均未在Mac进行原生编译或运行。** 源码复核和Windows侧模型不能证明Mac兼容性、AX行为、界面像素或实际时延。

## 环境与构建
需要Mac、Xcode命令行工具及macOS SDK。预期目标bundle标识为com.openai.chat，须在目标Mac核对，也可用--bundle-id覆盖。

### Swift
```sh
swiftc ChatGPTWindowTitles.swift -framework AppKit -framework ApplicationServices -o chatgpt-titlesync-swift
./chatgpt-titlesync-swift --interval 2 --background-interval 5 --bundle-id com.openai.chat
```

### Objective-C
```sh
clang -fobjc-arc -fblocks -framework Cocoa -framework ApplicationServices ChatGPTWindowTitles.m -o chatgpt-titlesync-objc
./chatgpt-titlesync-objc --interval 2 --background-interval 5 --bundle-id com.openai.chat
```
这些是构建指引，不代表已完成原生编译。

## 三层维护
窗口元数据维护每1秒调度。--interval控制前台来源读取，默认2秒，范围1..3600秒。--background-interval控制各后台窗口来源刷新，默认5秒，范围5..3600秒；设为15即15秒。

1. 前台ChatGPT窗口直接读取当前对话名，不用记住的标题代替本次新读取。
2. 已识别后台窗口重置为通用ChatGPT标题时，立即用记住的标题恢复，不为这次恢复触发来源读取。
3. 独立串行后台来源队列低频刷新后台对话名，也为未知后台窗口建立缓存；不阻塞前台来源队列，也不会因下一次前台1秒检查到期而取消。

只枚举目标bundle的AXWindows窗口元数据。前台焦点AX读取前先核对NSWorkspace，不读取其它应用内容。来源读取仅在有界原生外壳中寻找唯一AXWebArea并读取标题，不遍历网页子节点或聊天正文。

缓存身份包括PID、应用启动时刻和AX窗口身份。身份、前后台角色或暂停／设置修订号变化时丢弃结果；后台窗口转为前台后，旧后台结果不能覆盖前台新结果。非通用自定义标题持续保护，通用重置后恢复正常维护。写入必须确认AXTitle可写，且成功结果要求回读一致。

两份草稿使用内存缓存，重启后重新建立。2秒和5秒是来源调度间隔，不是读取完成保证。多个窗口同时到期时，串行后台读取和AX调用时延会使完成时刻顺延。

## 扫描间隔菜单与设置保存

点击菜单栏项目，选择 **扫描间隔设置…**。非模态面板提供前台来源间隔、后台来源间隔两个输入框，以及保存和取消；编辑期间普通调度继续运行。

菜单仅接受整数秒：前台 **1..3600**，后台 **5..3600**，缺省分别为 **2秒**和 **5秒**。非法或小数输入在面板内显示错误，不改变当前配置；取消也不改变配置。后台原生标题回改维护仍采用独立的1秒元数据调度；这两个字段修改实际来源读取调度间隔。

保存时由同一把计时锁成对更新两个间隔，递增主线程代次，再向状态队列排入各窗口来源修订号递增和到期时间重置。待提交结果会先核对新的代次与逐窗口修订号；下一次可执行扫描采用新间隔，不需要重启。已经进入的AX调用或提交不会被强制打断，保存前已通过最后检查的提交仍可能在状态重置排队期间完成；繁忙读者或状态队列仍可能延后下一次观察，热生效不代表严格的响应时间保证。

各实现使用独立的 `UserDefaults` 设置域保存 `ScanIntervals`：

| 实现 | 设置域 | 字段 |
| --- | --- | --- |
| Swift | `org.chatgpt-title.swift` | `ForegroundSeconds`、`BackgroundSeconds` |
| Objective-C | `org.chatgpt-title.objc` | `ForegroundSeconds`、`BackgroundSeconds` |

仅这些来源读取间隔互不共用，也不与Go/Rust的AppleScript设置桥共用；图标及自启动使用下述共享域。启动时，有效的显式 `--interval`、`--background-interval` 参数优先于保存值；省略参数则采用有效保存值，没有保存值时用缺省值。之后通过菜单保存的新值立即用于后续调度并持久化。自启动复选框和图标控件随保存提交，见下文；间隔设置不持久化对话标题缓存，也不修改辅助功能权限。

新增面板、输入检查、偏好设置、锁和代次校验仅经过静态源码复核。Swift的 `application.run()` 与Objective-C的 `main` / `[application run]` 入口仍完整保留。这些检查不代表Mac原生编译、界面效果、偏好设置运行行为或AX时序验收，仍需真实Mac验证。

## 实验性登录自启动——缺省已开

源码现提供 **开机自启动 / Start at sign-in** 菜单勾选和设置中同项。菜单成功修改后立即生效；设置按保存提交，取消不改；成功后同步两处控件。退出仅停止当前进程，不取消下次登录选择。

四个Mac实现共享 `NSUserDefaults` 域 `io.github.hpsun.ChatGPTTitleSync` 的 `AutoStartEnabled`（缺项开启），以及 `~/Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist`。草稿采用绝对可执行路径、`RunAtLoad=true`、`KeepAlive=false`，为下次登录准备，不立即bootstrap第二个常驻实例。Swift／Objective-C仍保留前述独立 `ScanIntervals` 域。Go／Rust菜单伴随源码还保存 `autostart_enabled`；内部启动契约现为**11个参数**，新增自启动布尔值和可执行路径，应使用当前分支启动器，不沿用旧9参数调用。

本项仍为**Experimental源码**，未在Mac编译或运行，不能证明登录启动、权限或AX行为已通过。见[启动说明](../docs/startup.zh-CN.md)。

## 暂停、退出与权限
通过菜单栏选择暂停并还原、恢复监听、退出并还原，以及检查／请求辅助功能权限。草稿未实现--stop命令行参数。正常退出仅还原仍与本实例写入值匹配的自有标题；强制结束可能无法还原。由用户决定辅助功能权限，程序不自动修改隐私设置。

## 图标主题：基准45与八种配色

当前缺省为**固定45**。设置面板新增三个**不可编辑的下拉列表**：固定／随机、固定配色**45–52**、每日／每小时／每5分钟。固定时启用配色、禁用周期；随机时相反。取消保留已提交设置。保存先验证资源，再尝试写入自启动、主题和间隔；失败时尝试还原原有五项图标偏好、自启动偏好／LaunchAgent及间隔配置，还原失败会明确报错，不显示为成功。

| 编号 | 配色 | 运行时PNG |
| --- | --- | --- |
| 45 | 蓝紫／白 | [45.png](../assets/themes/45.png) |
| 46 | 青／黑 | [46.png](../assets/themes/46.png) |
| 47 | 琥珀／黑 | [47.png](../assets/themes/47.png) |
| 48 | 薄荷／黑 | [48.png](../assets/themes/48.png) |
| 49 | 玫红／白 | [49.png](../assets/themes/49.png) |
| 50 | 天蓝／黑 | [50.png](../assets/themes/50.png) |
| 51 | 淡紫／黑 | [51.png](../assets/themes/51.png) |
| 52 | 珊瑚／黑 | [52.png](../assets/themes/52.png) |

四个Mac实现共用 `NSUserDefaults` 域 **`io.github.hpsun.ChatGPTTitleSync`** 中的下列图标项；来源读取间隔仍按前述各自存储。

| 项 | 值与含义 |
| --- | --- |
| `IconMode` | 字符串fixed／random，缺省fixed |
| `FixedIcon` | 整数45..52，缺省45 |
| `IconPeriod` | 字符串day／hour／5min，缺省day |
| `RandomIcon` | 上次随机选中的45..52整数 |
| `IconSlot` | 该次随机选择对应的本地时间段 |

缺项按fixed／45／day读取，不因此写入默认值。已有偏好不合法时保留原数据，报告有界元信息，并在资源可用时使用45。启用随机或改变周期立即选一次，相邻随机选择不重复，同一slot重启沿用保存结果。跨语言精确slot依次为 `YYYYMMDD`、`YYYYMMDDHH±HHMM`、`YYYYMMDDHHbb±HHMM`；每5分钟的bb为minute//5，两位补零00..11。小时和5分钟槽包含时区偏移，以区分重复的本地小时。

Swift／Objective-C使用原有1秒元数据定时器检查slot。AppleScript伴随程序原来没有UI定时器，此次新增唯一一个1秒AppKit图标定时器，仅检查slot，不读取GPT、AX或标题来源，不新增辅助进程。暂停标题处理不停止图标轮换；调度不代表严格的显示时限。资源丢失或轮换失败保留最近可用图像，每个失败slot最多记录一次；初始资源缺失时可能显示文字GPT。运行时只改本程序菜单栏／应用图像，不改写可执行文件或固定快捷方式。

### 资源布局与封装

保留全部8个PNG。可执行文件编译在 `macos/` 中时使用 `../assets/themes`；移动二进制后可在同级保留 `assets/themes`。`.app`使用 `Contents/Resources/themes`，也支持 `Contents/Resources/assets/themes`。原生草稿依次检查这两个bundle位置、二进制同级assets/themes、../assets/themes；避免前面的空目录遮挡后面的完整资源。

```text
ChatGPT-TitleSync/
  assets/
    chatgpt-titlesync-icon.png
    themes/45.png ... 52.png
  macos/
    ChatGPTWindowTitles.swift
    ChatGPTWindowTitles.m
    TraySettings.applescript
    chatgpt-titlesync-swift   # 本机编译示例
```

Go／Rust伴随程序保持**原11参数接口**，从第8项基础PNG路径的父目录找到themes。使用当前Go／Rust启动器并保留上述布局，不增加第12项主题参数，也不向原有间隔配置文件格式添加图标偏好。

上述构建命令只生成可执行文件，不生成签名.app，也不嵌入PNG集合。另行封装时可通过CFBundleIconFile使用当前[基准45 ICNS](../assets/chatgpt-titlesync.icns)，并按上述方式保留运行时PNG。封装、签名、公证和逐窗口Dock命名均未验证。

**历史A1记录。** 图标主题加入前的说明使用文字菜单栏项目，并描述可选A1 bundle图标；当时CLI构建未嵌入A1。这些仍为历史事实。当前根PNG／ICO／ICNS别名已指向45，源码也已实现运行时图像选择；旧A1记录或新资源均不代表Mac图像显示已经实测成功。

## 验证边界

见[发布验证说明](../docs/release-readiness.zh-CN.md#local-validation)。历史**13项标题行为模型**早于三层实现，仅保留为模型证据。新增[23项图标契约模型](test_icon_policy.py)使用假偏好／资源、注入时间／随机选择，覆盖同slot重启、时段边界、无连重、保存／取消及自启动／间隔／主题回滚，全部通过。原13项标题模型也再次通过，执行时未在源码树产生新回执。

```sh
python3 -B test_icon_policy.py
python3 -B -m unittest discover -s . -p test_macos_behavior.py
```

静态比对确认原AX／标题算法正文未变，Swift的application.run()、Objective-C的main／[application run]入口保留，AppleScript仍为11参数。词法括号／handler结构检查和状态模型**不等于原生编译或运行测试**。

本轮没有在Mac验证Swift／Objective-C编译、osacompile、AppleScriptObjC桥接、AppKit控件／图像及ARC／对象寿命、真实UserDefaults持久化与回滚、LaunchAgent／登录启动、辅助功能权限、实际ChatGPT AX层级／标题可写性、像素、焦点／暂停时序或封装。产品版本仍为**0.1.0**，这些Mac前端继续标为**Experimental**；声明原生支持前仍需Mac SDK构建及受控实机验收。

静态复核还保留逐窗口的状态队列来源修订号，在新读取和观测到前后台角色变化时递增；提交必须同时匹配该修订号与暂停／退出代次。外部标题变化会释放旧写入所有权但保留核实名称缓存。仅在同PID与启动身份的AXWindows完整成功且未被数量上限截断的快照中，才退役关闭窗口；失败／截断枚举保守保留原记录。元数据AX调用占用共享状态队列时可能延后提交，独立来源队列不构成硬实时保证。
