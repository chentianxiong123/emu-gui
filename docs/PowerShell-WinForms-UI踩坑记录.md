# PowerShell + WinForms 写 GUI 踩坑记录

> 缘起：鸿蒙模拟器控制台（`emu-gui.ps1`，Windows PowerShell 7 + WinForms，纯脚本不编译）。
> 全程被布局/事件/文字渲染坑到怀疑人生，以下每条都实际踩过、排除过、验证过。
> 语言直白，别介意。

---

## 一、布局坑（最恶心的一组）

### 坑 1：放进 TableLayoutPanel 的控件不设 Dock，就是默认 200px 宽 [必须修]

**现象**：一行里 4 个按钮 + 下拉框，右边一大截死活显示不出来；下拉框文案被从中间截断（"手机 (Phone)" 变成"手机 ("）。

**原因**：WinForms 控件默认尺寸是 200x100（Button 是 75x23，但 Panel 系默认 200x100）。把 FlowLayoutPanel / 普通 Panel 直接 `Controls.Add` 进 TableLayoutPanel 单元格后，**如果不设 Dock 或显式 Width，它就保持 200px 宽**，内容全部溢出单元格，被表格裁剪。超出部分不是滚动、不是换行，就是物理性地切掉，连影子都不留。

**修复**：`$f.Dock = 'Fill'` 一行，面板自动撑满单元格宽度。

```powershell
function New-Flow {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Dock = 'Fill'          # ← 灵魂，没有它默认 200 宽
    $f.AutoSize = $false
    ...
}
```

**预警**：这个坑被另一个坑（按钮 AutoSize 算错变小）完美掩盖——按钮只有 32px 时一行才 300px，200px 容器只溢出 100px，看起来"按钮小"而不是"行被裁"。把按钮改成正常 90px 后立刻爆炸。**排查布局问题时先确认每个容器控件的实测宽度**，别靠肉眼。

### 坑 2：Button 的 AutoSize 在 FlowLayoutPanel 里会把尺寸算成 32x14 [绕开]

**现象**：`Text='🔄 刷新'`（含 Emoji 前缀）的按钮，PreferredSize 算出 76x30，实际 Width/Height 却是 32x14——文字直接消失，按钮看起来是空白的。

**原因**：不深究 WinForms 内部（高低 DPI/字体回退测量打架），实测就是这个组合（Button + FlowLayoutPanel + AutoSize=GrowAndShrink）会算错，且只在部分 Flow 面板里错。

**修复**：**别在 FlowLayoutPanel 里用 AutoSize 按钮**，建按钮时给显式宽高：

```powershell
$b.AutoSize = $false
$b.Width  = 90
$b.Height = 30
```

**教训**：AutoSize 在全屏/网格布局下能用，在 FlowLayoutPanel 里就是个定时炸弹。宁可手动算宽度（中文每字 ≈ 14px @ 9.5pt，加 20px padding）。

### 坑 3：TableLayoutPanel 行/列是"样式"，加控件时要数对格子 [必须修]

**现象**：控件错位、重叠、越界。

**原因**：`Controls.Add($ctrl, col, row)` 的 col/row 一旦超过 ColumnCount/RowCount，WinForms 会**默默扩展**而不是报错，视觉上就是乱摆。

**修复**：把列数、行数、每个 Add 的行列号写成一张表对着数；改行样式时同步数。

---

## 二、事件/线程坑（最隐蔽的一组）

### 坑 4：PowerShell 里绑定 Process 输出事件，回调线程没有 Runspace → 整个进程崩掉 [绕开]

**现象**：`$p.OutputDataReceived += { ... }` 报"属性不存在"；改成 `$p.add_OutputDataReceived($handler)` 后，事件一触发直接抛
`PSInvalidOperationException: There is no Runspace available to run scripts in this thread`，程序当场退出。

**原因**：.NET 事件回调跑在线程池线程上，**那个线程没有 PowerShell Runspace**，ScriptBlock 根本执行不了。PowerShell 的 `+=` 事件语法在 PS7 里对 Process 事件类成员也有解析问题。

**修复**：脚本里不要用 PS 的 ScriptBlock 当 .NET 事件回调。改用 `Add-Type` 编译一个 C# 辅助类，原生 .NET 委托入队，UI 线程用 Timer 消费：

```csharp
// C# 类（Add-Type -TypeDefinition 编译）
public class EmuStream {
    public ConcurrentQueue<string> Queue = new ConcurrentQueue<string>();
    public Process Start(string exe, string args, string stdin) {
        ProcessStartInfo psi = new ProcessStartInfo();
        ...
        psi.RedirectStandardOutput = true;
        Process p = Process.Start(psi);
        p.OutputDataReceived += (s, e) => { if (e.Data != null) Queue.Enqueue(e.Data); };
        p.BeginOutputReadLine();
        return p;
    }
}
```

```powershell
# PS 侧：Timer 周期 100ms 从 Queue 取行，更新进度条/标签
```

**铁律**：**跨线程更新控件一律不碰**——后台线程只往线程安全队列写，UI 线程（Timer）读。别想用 Invoke 糊弄，PS 里 ScriptBlock 到别的线程直接没 Runspace。

### 坑 5：进程启动后要立即写 stdin（协议 y/N 确认） [必须]

**现象**：`Emulator.exe -install ...` 运行 1 秒就退出，exit=0，什么都没下载——因为它在等 `(y/N):` 输入，没人理就退了。

**修复**：`RedirectStandardInput = $true`，启动后 `WriteLine('y')`。协议同意一次后写进
`%LOCALAPPDATA%\Huawei\Emulator26.0\.emu_config`，后续不需要再喂。

---

## 三、构造/语法坑（全是 PS 特性咬人）

### 坑 6：`New-Object Foo(a, b-c)` 里带减号 → `op_Subtraction on Object[]` [必须修]

**现象**：`New-Object System.Windows.Forms.Padding(6, $x-3, 0, 0)` 直接报
`Method invocation failed because [System.Object[]] does not contain a method named 'op_Subtraction'`。

**原因**：PS7 里 `Foo(a, b, c)` 这种"括号构造"把参数当**数组**求值，表达式里的 `-` 被当成数组减法。

**修复**：一律 `New-Object Foo -ArgumentList @(a, b, c)`，或先把减法算到变量里再传。

### 坑 7：字符串插值 `"$name: ..."` 解析炸 [必须修]

**现象**：`"$name: xxx"` 报 `Variable reference is not valid. ':' was not followed by a valid variable name character`。

**原因**：`$name:` 里冒号被当成变量名的一部分（作用域限定符）。

**修复**：`"${name}: xxx"` 花括号包变量名。同理 `"$i.txt"` → `"${i}.txt"`。

### 坑 8：bash 里跑 `powershell -Command "$x"` → `$x` 被吞 [必须修]

**现象**：从 bash 触发 PowerShell 单行命令，里面所有 `$`/`$_` 被外层 shell 展开成空。

**修复**：**永远写 .ps1 文件再执行**，别 inline：

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File script.ps1
```

### 坑 9：系统中文编码 → 控制台输出乱码（GBK） [容忍]

**现象**：脚本打印中文在终端乱码。

**原因**：Windows 中文系统控制台代码页 GBK，pwsh 输出 UTF-8。

**处理**：GUI 不依赖控制台；需要回显的写文件用 `[System.Text.Encoding]::UTF8`。

---

## 四、验证方法论（省了无数冤枉路）

1. **不要靠肉眼猜布局**。控件建好后 dump 实测：`$panel.Width`, `$ctrl.Bounds`, `$tlp.GetRowHeights()`。一行代码胜过半小时截图。
2. **复现要最小化**：单独脚本只建出问题的那一截控件树（TableLayoutPanel + 几个按钮），比对着整个 700 行 GUI 猜快 10 倍。
3. **截屏可靠性**：`CopyFromScreen` 会被窗口遮挡/前台状态坑；进程内 `$form.DrawToBitmap()` 直接画控件树，不依赖屏幕，最真。
4. **冒烟测试**：`Start-Process pwsh -File gui.ps1 -RedirectStandardOutput -RedirectStandardError`，sleep 8s，查 `HasExited`，stdout/stderr 都空 = 启动通过。但冒烟只能证明"没崩"，证明"显示对"需要上面的 dump/截图。

---

## 五、一句话总结

WinForms + PowerShell 写 GUI 的核心痛点是三件事：
1. **布局不是自动的**——所有放进容器的控件都要显式 Dock/Width，永远别信默认值；
2. **PS 的 ScriptBlock 不是万能的委托**——跨线程/事件回调必须走 C# 或队列；
3. **PS 自己的语法坑（括号构造、插值冒号、inline $ 被吞）会假装成 WinForms 的 bug**——出问题先怀疑自己那行语法。

坑 1（Dock）和坑 2（AutoSize）是这次"UI 框架难用"的 90% 来源，记住这两条，下次能少哭一半。

2026-10-17 · 鸿蒙模拟器控制台 · PowerShell 7.6.6 / Windows 11