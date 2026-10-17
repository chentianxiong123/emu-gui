# 鸿蒙模拟器控制台 (emu-gui)

基于 DevEco Studio 自带 `Emulator.exe` CLI 的 Windows 图形控制台，纯 PowerShell + WinForms，无需额外依赖。

## 功能

- 实例管理：刷新 / 启动（可无窗）/ 停止 / 删除
- 创建实例：中文设备类型（手机/折叠屏/平板/手表/电视/汽车…）、真机机型清单联动、名称/内存/存储校验
- 镜像管理：获取镜像列表、下载（实时进度 + 本地占用统计）、强制下载、卸载；SDK 协议自动同意
- 状态栏显示 SDK 协议状态与镜像信息

## 使用

```powershell
# 直接运行
pwsh -File emu-gui.ps1

# 或双击 bin/emu-gui.cmd（自动检测 pwsh，隐藏黑窗）
```

## 依赖

- PowerShell 7+
- DevEco Studio：`C:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe`
- 已下载镜像：`%LOCALAPPDATA%\Huawei\Sdk\system-image\`

## 文档

- `docs/PowerShell-WinForms-UI踩坑记录.md` — 开发过程中的 WinForms 踩坑全部记录（布局 Dock、AutoSize、跨线程队列、PS 语法坑等）

## 下载镜像

```bash
Emulator.exe -install -deviceType phone -osVersion "HarmonyOS 7.0.0(26.0.0)"
# 首次会询问 y/N，同意后写入 .emu_config，之后不再询问
```

## 许可证

MIT