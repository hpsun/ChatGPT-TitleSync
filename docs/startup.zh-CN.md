# 用户登录自启动

[English](startup.md) · [HTML](startup.zh-CN.html) · [项目说明](../README.zh-CN.md) · [支持矩阵](../support-matrix.zh-CN.md)

**开机自启动缺省已开。** 正常常驻程序首次成功运行时为当前用户登记所选实现，在该用户登录后启动，不是登录前运行的系统服务。本次Windows自启动修改正在重新实测；此前九条路线通过不代表本轮新版全部实测已完成。Mac自启动仍为Experimental源码，未在Mac编译或运行。

## 目录

- [切换方式](#controls)
- [Windows：当前用户Run项](#windows)
- [macOS：实验性逐用户LaunchAgent](#macos)
- [验证边界](#verification)

<a id="controls"></a>
## 切换方式

| 入口 | 生效时点 |
| --- | --- |
| 托盘／菜单 **开机自启动 / Start at sign-in** | 成功修改后立即生效 |
| 设置复选框并点**保存** | 提交选择，并同步托盘／菜单 |
| 设置**取消** | 不更改已保存选择 |
| **退出并恢复标题** | 只退出本次运行，不取消下次登录启动 |

两处控件对应同一偏好，成功修改后互相同步，包含已经打开的设置窗；失败显示错误，不显示成已成功。偏好缺项按开启处理，明确保存的关闭选择跨重启及支持的语言版本保留。一次只运行一个正常常驻实现。只读探针、工作进程、单次检查及设置／停止控制命令不会注册；只有取得单实例归属的正常常驻入口才能注册。各实现提供的诊断／控制参数不完全相同。

<a id="windows"></a>
## Windows：当前用户Run项

Windows各实现使用相同固定值：

| 项目 | 位置／值 |
| --- | --- |
| 登录命令 | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → `ChatGPT-TitleSync`（`REG_SZ`） |
| 共用偏好 | `HKCU\Software\ChatGPT-TitleSync` → `AutoStartEnabled`（`DWORD`：1开启，0关闭） |

所选正常常驻程序按自身可运行方式登记绝对命令，正确引用可执行文件、解释器与脚本路径，不携带测试日志位置或间隔覆盖参数。C#读取器应与主程序相邻；解释脚本和冻结目录版本保留各指南要求的伴随文件。具体启动格式见相应实现指南。

Run完整命令含引号与参数最多**260字符**。启用超长命令会在修改Run值及偏好前被拒绝，应将程序／脚本放到较短且稳定的位置；关闭仍然允许。命令和偏好已经一致时无需重复写入。失败会报告，并尝试保留／恢复原值，不能当作注册成功。无需管理员权限，不建立服务或任务计划；关闭只删除本产品的Run值。Windows可能延迟登录启动，不保证登录瞬间执行。参见[Microsoft Run／RunOnce文档](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)。

<a id="macos"></a>
## macOS：实验性逐用户LaunchAgent

Swift、Objective-C和Go／Rust菜单伴随源码共享 `NSUserDefaults` 域 `io.github.hpsun.ChatGPTTitleSync` 的 `AutoStartEnabled`，缺项按开启处理。草稿登记到 `~/Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist`，使用同名Label、`ProgramArguments`中的绝对可执行路径、`RunAtLoad=true`、`KeepAlive=false`。

开启为下次登录准备所选程序，不立即bootstrap第二个常驻实例；关闭删除本产品plist。退出本次运行不取消登录选择。Go／Rust设置／菜单契约还保存 `autostart_enabled`。这些仅是源码设计，Mac SDK构建、登录行为、权限与AX／标题操作仍未实机验证。见[Mac指南](../macos/README.zh-CN.md)、[Go指南](../go/README.zh-CN.md)和[Rust指南](../rust/README.zh-CN.md)。

<a id="verification"></a>
## 验证边界

Windows自有测试使用GUID临时注册表键和从不显示的控件，不写真实Run，检查默认开启、共享关闭偏好、取消、两处控件同步、超长拒绝及写入失败处理。本轮真实Windows复测仍在进行。重启登录后的行为、长期可靠性及Mac原生验收须单独记录，旧时延和源码夹具均不能代替这些结果。
