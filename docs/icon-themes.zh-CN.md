# 图标配色

[English](icon-themes.md) · [项目说明](../README.zh-CN.md) · [启动设置](startup.zh-CN.md)

**45号为基准。** 放大的ChatGPT主体右上覆盖蓝紫色Title胶囊，使用粗等宽字体，取消蓝色外框。各实现采用同一资源系列；原生构建与运行验证范围分别列于[支持矩阵](../support-matrix.zh-CN.md)。

<p><img src="../assets/themes/45.png" alt="基准45" width="144"> <img src="../assets/themes/47.png" alt="琥珀47" width="144"> <img src="../assets/themes/48.png" alt="薄荷48" width="144"></p>

## 设置项

通过现有托盘／菜单的**扫描间隔设置…**打开设置，在扫描间隔及登录自启动之外选择：

| 设置 | 选项 | 缺省 |
| --- | --- | --- |
| 图标模式 | 固定／随机 | 固定 |
| 固定配色 | 45蓝紫、46青、47琥珀、48薄荷、49玫红、50天蓝、51淡紫、52珊瑚 | 45 |
| 随机周期 | 每日／每小时／每5分钟 | 每日 |

固定模式才启用配色选择；随机模式才启用周期选择。保存提交变更，取消丢弃草稿。启用随机或改变随机周期时立即选色，下次选择排除当前配色。周期按本地时间边界计算，并非从启动时刻起累计；同一已保存时间段内重启保持原配色。

## 保存及失败处理

Windows各替代实现共用当前用户偏好键`HKCU\Software\ChatGPT-TitleSync`：`IconMode`、`IconPeriod`为字符串，`FixedIcon`、`RandomIcon`为DWORD配色编号，`IconSlot`记录最近已应用时间段。Mac实验源码使用同名字段，位于共用UserDefaults域`io.github.hpsun.ChatGPTTitleSync`。独立的`AutoStartEnabled`偏好予以保留。

保存设置前先验证资源。资源缺失时保留可用旧图标并有限报告错误。轮换复用现有轻量计时器，独立于标题监听暂停状态，不额外读取辅助树。运行时更换的是本工具自身的托盘／菜单栏及设置窗图标，不改写运行中的EXE、固定快捷方式或ChatGPT自身图标。

源码运行需保留仓库`assets/themes`目录；冻结构建需保留完整资源依赖目录。现代Windows ICO含16、24、32、48、64、128、256共七种尺寸；旧版ICO为非压缩DIB帧，供AutoHotkey Basic兼容使用。基准别名及哈希见[选择元数据](../assets/icon-selected.json)。

## 验证边界

当前主题改动正在进行受控及Windows真实窗口专项复测；此前九运行时标题结果属于旧修订。尚未在Mac核验原生编译、菜单外观、登录启动及辅助功能效果。工作流定义或Windows模型不等于Mac实测。当前完成状态见[发布准备](release-readiness.zh-CN.md)。
