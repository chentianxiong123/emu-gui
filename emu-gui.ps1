# ============================================================
# 鸿蒙模拟器控制台 v7  (HarmonyOS Emulator CLI GUI, WinForms)
# 等比缩放布局: 主区域全部 Percent 比例, 控件条固定高, 最小尺寸兜底
# 运行: emu-gui  或  桌面快捷方式
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$emuPath = 'C:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe'
$imgDir  = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'harmony-emulator'
$script:seq = 0

# ---------- 配色 ----------
$cAccent   = [System.Drawing.Color]::FromArgb(0, 102, 204)
$cAccentDk = [System.Drawing.Color]::FromArgb(0, 82, 170)
$cBg       = [System.Drawing.Color]::FromArgb(246, 248, 251)
$cCard     = [System.Drawing.Color]::White
$cLine     = [System.Drawing.Color]::FromArgb(221, 226, 233)
$cMuted    = [System.Drawing.Color]::FromArgb(110, 120, 135)
$cOk       = [System.Drawing.Color]::FromArgb(33, 150, 83)
$cErr      = [System.Drawing.Color]::FromArgb(211, 47, 47)
$fBody     = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$fMono     = New-Object System.Drawing.Font('Cascadia Mono', 9)

# ---------- CLI ----------
# C# 帮助类: 流式读取进程输出。PS scriptblock 作事件回调会在无 Runspace 线程崩溃,
# 且有 += 解析问题, 故用原生 .NET 委托 (经 Add-Type 编译, 线程无关)
Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
public class EmuStream {
    public ConcurrentQueue<string> Queue = new ConcurrentQueue<string>();
    public Process Start(string exe, string args, string stdin) {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = exe;
        psi.Arguments = args;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        if (stdin != null) psi.RedirectStandardInput = true;
        Process p = Process.Start(psi);
        if (stdin != null) { p.StandardInput.Write(stdin); p.StandardInput.Flush(); }
        p.OutputDataReceived += (s, e) => { if (e.Data != null) Queue.Enqueue(e.Data); };
        p.ErrorDataReceived  += (s, e) => { if (e.Data != null) Queue.Enqueue(e.Data); };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        return p;
    }
}
"@
$script:emuStream = New-Object EmuStream
$script:dlBusy = $false
# 坑记录（实测）:
#  - -install 首次会提示协议 "confirm whether agree...? (y/N)"，必须经 stdin 喂 y，否则立即退出不下
#    同意后写入 %LOCALAPPDATA%\Huawei\Emulator26.0\.emu_config: HarmonyOS_SDK_Agreement:agree
#  - 下载进度极多行(每~400KB一行, 1.95GB≈2000 行), 全量进日志会卡界面 => 走流式队列只更新进度条
function Test-SdkAgreement {
    $f = Join-Path $env:LOCALAPPDATA 'Huawei\Emulator26.0\.emu_config'
    if (Test-Path $f) { (Get-Content $f -Raw) -match 'HarmonyOS_SDK_Agreement:\s*agree' } else { $false }
}
function Run-Emu-Stream([string[]]$Args, [string]$Stdin = '') {
    $aa = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $Args) { $aa.Add('"' + ($a -replace '"','\"') + '"') }
    $stdinArg = if ($Stdin) { $Stdin } else { $null }
    return $script:emuStream.Start($emuPath, [string]::Join(' ', $aa), $stdinArg)
}
function Run-Emu([string[]]$Args, [switch]$Async, [string]$Stdin = '', [switch]$Quiet) {
    $script:seq++
    $tag = "{0:HHmmss}-{1}" -f (Get-Date), $script:seq
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $emuPath
    $aa = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $Args) { $aa.Add('"' + ($a -replace '"','\"') + '"') }
    $psi.Arguments = [string]::Join(' ', $aa)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($Stdin) { $psi.RedirectStandardInput = $true }
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    catch { Log "[错误] 无法启动 Emulator.exe: $($_.Exception.Message)" -Color $cErr; return }
    if ($Stdin) { $p.StandardInput.Write($Stdin); $p.StandardInput.Flush() }
    if ($Async) { Log "▶ $($Args -join ' ')   (PID $($p.Id)，不等待)" -Color $cOk; return }
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $txt = ($so.Result) + ($se.Result)
    Log "▶ $($Args -join ' ')"
    if ($txt.Trim()) {
        if ($Quiet -and ($txt -split "`r?`n").Count -gt 40) {
            $last = $txt -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 6
            Log ('  ' + (($last -join "`n") -replace "`n", "`n  "))
        } else { Log $txt.TrimEnd() }
    }
    Log "  exit = $($p.ExitCode)" -Color $(if ($p.ExitCode -eq 0) { $cOk } else { $cErr })
}

function Log([string]$m, [System.Drawing.Color]$Color = $cAccentDk) {
    try {
        $script:txtLog.AppendText(("[{0:HH:mm:ss}] " -f (Get-Date)))
        $script:txtLog.SelectionColor = $Color
        $script:txtLog.AppendText($m)
        $script:txtLog.SelectionColor = $script:txtLog.ForeColor
        $script:txtLog.AppendText([Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.TextLength
        $script:txtLog.ScrollToCaret()
    } catch { }
}

# ---------- 控件工厂 ----------
function New-Grp([string]$t) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $t
    $g.Font = $fBody
    $g.ForeColor = $cAccentDk
    $g.BackColor = $cCard
    $g.Dock = 'Fill'
    $g.Padding = New-Object System.Windows.Forms.Padding(10)
    return $g
}
function New-Btn([string]$t, [scriptblock]$cb, [switch]$Primary, [int]$w = 0) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $t
    if ($w -gt 0) {
        # flow 面板里 AutoSize 会算错(缩成 32x14 裁掉文字), 用固定尺寸
        $b.AutoSize = $false
        $b.Width = $w
        $b.Height = 30
        $b.Margin = New-Object System.Windows.Forms.Padding(2, 2, 2, 2)
    } else {
        $b.AutoSize = $true
        $b.AutoSizeMode = 'GrowAndShrink'
    }
    $b.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $cLine
    $b.Font = $fBody
    if ($Primary) {
        $b.BackColor = $cAccent; $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderColor = $cAccent
        $b.FlatAppearance.MouseOverBackColor = $cAccentDk
    } else {
        $b.BackColor = [System.Drawing.Color]::White
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(235, 242, 250)
    }
    $b.Add_Click($cb)
    return $b
}
function New-Lbl([string]$t) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $t
    $l.AutoSize = $true
    $l.Height = 26
    $l.TextAlign = 'MiddleLeft'
    $l.Font = $fBody
    return $l
}
function New-Cbo([string[]]$Items, [int]$w = 90) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'
    $c.Width = $w
    $c.Height = 28
    $c.FlatStyle = 'Flat'
    $c.Items.AddRange($Items)
    if ($c.Items.Count -gt 0) { $c.SelectedIndex = 0 }
    return $c
}
function New-Txt([string]$def, [int]$w = 90) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = $def
    $t.Width = $w
    $t.Height = 28
    $t.BorderStyle = 'FixedSingle'
    return $t
}
function New-Flow([int]$h = 36) {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Dock = 'Fill'
    $f.AutoSize = $false
    $f.Height = $h
    $f.WrapContents = $false
    $f.FlowDirection = 'LeftToRight'
    $f.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
    return $f
}
# 流式行内垂直居中 (固定行高 36, 控件高 ~28)
function Align-Flow($f) {
    for ($i = 0; $i -lt $f.Controls.Count; $i++) {
        $c = $f.Controls[$i]
        $need = 34 - $c.Height
        if ($need -gt 0) {
            $tp = [int]($need / 2)
            $c.Margin = New-Object System.Windows.Forms.Padding -ArgumentList @(2, $tp, 2, ($need - $tp))
        }
    }
}

# ============================================================
# 窗体: 可缩放, 主区域等比
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = '鸿蒙模拟器控制台'
$form.Size = New-Object System.Drawing.Size(1000, 1000)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 900)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cBg
$form.Font = $fBody
try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($emuPath) } catch { }

$body = New-Object System.Windows.Forms.TableLayoutPanel
$body.Dock = 'Fill'
$body.ColumnCount = 2
$body.RowCount = 4
$body.Padding = New-Object System.Windows.Forms.Padding(12)
$body.BackColor = $cBg
$body.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 56))) | Out-Null
$body.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 44))) | Out-Null
$body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 42))) | Out-Null
$body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 34))) | Out-Null
$body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 24))) | Out-Null
$body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 26))) | Out-Null
$form.Controls.Add($body)

$tip = New-Object System.Windows.Forms.ToolTip
function Add-Tip($ctrl, [string]$text) { $script:tip.SetToolTip($ctrl, $text) }

# ============================================================
# 左卡: 实例管理
# ============================================================
$gInst = New-Grp ' 实例管理 '
$ilay = New-Object System.Windows.Forms.TableLayoutPanel
$ilay.Dock = 'Fill'
$ilay.ColumnCount = 1
$ilay.RowCount = 6
$ilay.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
$ilay.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100))) | Out-Null
$ilay.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 36))) | Out-Null
$ilay.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 36))) | Out-Null
$ilay.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 36))) | Out-Null
$ilay.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 36))) | Out-Null
$ilay.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 24))) | Out-Null
$gInst.Controls.Add($ilay)

$list = New-Object System.Windows.Forms.ListBox
$list.Dock = 'Fill'
$list.BorderStyle = 'FixedSingle'
$list.Font = $fBody
$list.ItemHeight = 22
$ilay.Controls.Add($list, 0, 0)

$f1 = New-Flow
$bRefresh = New-Btn '🔄 刷新' { Refresh-Instances } -w 88
$bStart   = New-Btn '▶ 启动'  { Start-Inst } -Primary -w 88
$bStop    = New-Btn '⏹ 停止'  { if (Inst) { Run-Emu @('-stop', (Inst)) } } -w 88
$bDel     = New-Btn '🗑 删除'  { if (Inst) { if ($chkForce.Checked) { Run-Emu @('-delete', (Inst), '-force') } else { Run-Emu @('-delete', (Inst)) } } } -w 88
$chkNoWin = New-Object System.Windows.Forms.CheckBox
$chkNoWin.Text = '无窗'; $chkNoWin.AutoSize = $true; $chkNoWin.Font = $fBody
$chkNoWin.Margin = New-Object System.Windows.Forms.Padding(6, 6, 0, 0)
$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Text = '强制删除'; $chkForce.AutoSize = $true; $chkForce.Font = $fBody
$chkForce.Margin = New-Object System.Windows.Forms.Padding(10, 6, 0, 0)
$f1.Controls.Add($bRefresh); $f1.Controls.Add($bStart); $f1.Controls.Add($bStop); $f1.Controls.Add($bDel)
$f1.Controls.Add($chkNoWin); $f1.Controls.Add($chkForce)
$ilay.Controls.Add($f1, 0, 1)
Align-Flow $f1

$f2 = New-Flow
$f2.Controls.Add((New-Lbl '实例名:'))
$txtName = New-Txt '' 150
$f2.Controls.Add($txtName)
$bLic = New-Btn '📜 接受协议' { Run-Emu @('-license', 'accept') }
$f2.Controls.Add($bLic)
$ilay.Controls.Add($f2, 0, 2)
Align-Flow $f2

$f3 = New-Flow
$f3.Controls.Add((New-Lbl '新建:'))
$txtNew = New-Txt 'myPhone' 80
$f3.Controls.Add($txtNew)
$f3.Controls.Add((New-Lbl '设备:'))
$cboDev = New-Cbo ([string[]]@('手机 (Phone)','折叠屏 (Foldable)','阔折叠 (WideFold)','三折叠 (TripleFold)','平板 (Tablet)','二合一 (2in1)','二合一折叠 (2in1 Foldable)','手表 (Wearable)','儿童手表 (WearableKid)','电视 (TV)','汽车 (Car)')) 130
$f3.Controls.Add($cboDev)
$f3.Controls.Add((New-Lbl '版本:'))
$cboVer = New-Object System.Windows.Forms.ComboBox
$cboVer.DropDownStyle = 'DropDown'
$cboVer.Width = 150
$cboVer.Items.AddRange([string[]]@(
  'HarmonyOS 7.0.0(26.0.0)','HarmonyOS 6.1.1(24)','HarmonyOS 6.1.0(23)','HarmonyOS 6.0.2(22)',
  'HarmonyOS 6.0.1(21)','HarmonyOS 6.0.0(20)','HarmonyOS 5.1.1(19)','HarmonyOS 5.1.0(18)',
  'HarmonyOS 5.0.5(17)','HarmonyOS 5.0.4(16)','HarmonyOS 5.0.3(15)','HarmonyOS 5.0.2(14)','HarmonyOS 5.0.1(13)'))
$cboVer.Text = 'HarmonyOS 7.0.0(26.0.0)'
$f3.Controls.Add($cboVer)
$ilay.Controls.Add($f3, 0, 3)
Align-Flow $f3

$f4 = New-Flow
$f4.Controls.Add((New-Lbl '机型:'))
$cboProf = New-Cbo ([string[]]@('默认(按设备)')) 150
$f4.Controls.Add($cboProf)
$f4.Controls.Add((New-Lbl '内存:'))
$txtMem = New-Txt '4' 44
$f4.Controls.Add($txtMem)
$f4.Controls.Add((New-Lbl '存储:'))
$txtSto = New-Txt '6' 44
$f4.Controls.Add($txtSto)
$bCreate = New-Btn '＋ 创建实例' {
    # ---- 创建校验(防乱填) ----
    $n = $txtNew.Text.Trim()
    if (-not $n) { Log '先填"新建"名称' -Color $cErr; return }
    if ($n -notmatch '^[A-Za-z][A-Za-z0-9_]{1,29}$') { Log '实例名: 字母开头, 仅字母/数字/下划线, 2~30 位' -Color $cErr; return }
    if ($list.Items.Contains($n)) { Log "同名实例已存在: $n" -Color $cErr; return }
    $mem = $txtMem.Text.Trim()
    if ($mem -notmatch '^\d+$' -or [int]$mem -lt 2 -or [int]$mem -gt 32) { Log '内存: 2~32 的整数' -Color $cErr; return }
    $sto = $txtSto.Text.Trim()
    if ($sto -notmatch '^\d+$' -or [int]$sto -lt 2 -or [int]$sto -gt 1023) { Log '存储: 2~1023 的整数' -Color $cErr; return }
    # ---- 组装参数 ----
    $dev = [string]$cboDev.SelectedItem
    if ($dev -match '\(([^)]+)\)\s*$') { $dev = $matches[1].Trim() }
    $a = @('-create', $n, '-deviceType', $dev, '-osVersion', $cboVer.Text)
    if ($mem) { $a += @('-memory', $mem) }
    if ($sto) { $a += @('-storage', $sto) }
    $prof = [string]$cboProf.SelectedItem
    if ($prof -and $prof -ne '默认(按设备)') { $a += @('-screenProfile', $prof) }
    # ---- 确认框 ----
    $msg = "确认创建实例?`n名称: $n`n设备: $($cboDev.SelectedItem)`n版本: $($cboVer.Text)`n内存: ${mem}GB  存储: ${sto}GB"
    if ($prof -and $prof -ne '默认(按设备)') { $msg += "`n机型: $prof" }
    if ([System.Windows.Forms.MessageBox]::Show($form, $msg, '创建实例', 'YesNo', 'Question') -ne 'Yes') {
        Log '已取消创建' -Color $cMuted; return
    }
    Run-Emu $a
    Refresh-Instances
} -Primary
$f4.Controls.Add($bCreate)
$ilay.Controls.Add($f4, 0, 4)
Align-Flow $f4
# 机型库(设备类型 -> 真机清单, 来自 -screenProfileList 实测)
$script:profMap = @{
    'Phone'       = [string[]]@('Mate 90 Pro','Mate 90','Mate 90 Pro Max','Mate 90 RS','Pura X View','Pura 90 Pro','Pura 90','Pura 90 Pro Max','nova 16 Pro','nova 16','nova 16 Ultra','nova 16z','Mate 80 Pro','Mate 80','Mate 80 Pro Max','Mate 80 RS','Pura 80 Pro','Pura 80','Pura 80 Pro+','Pura 80 Ultra','nova 15 Pro','nova 15','nova 15 Ultra','Enjoy 90 Plus','Enjoy 90','Enjoy 90 Pro Max','nova 14 Pro','nova 14','nova 14 Ultra','Mate 70 Pro','Mate 70','Mate 70 Pro+','Mate 70 RS','Mate 70 Air','Pura 70 Pro','Pura 70','Pura 70 Pro+','Pura 70 Ultra','nova 13 Pro','nova 13','nova flip','nova flip S','Pocket 2','Mate 60 Pro','Mate 60','Mate 60 Pro+','Mate 60 RS','nova 12 Pro','nova 12','nova 12 Ultra')
    'Foldable'    = [string[]]@('Mate X7','Mate X6','Mate X5')
    'WideFold'    = [string[]]@('Pura X Max','Pura X')
    'Tablet'      = [string[]]@('MatePad Pro 13','MatePad Pro 12','MatePad Pro 11','MatePad Air 12','MatePad 11 S')
    '2in1'        = [string[]]@('MateBook Pro')
    'Car'         = [string[]]@('Huawei_Car')
}
function Sync-Profiles {
    $dev = [string]$cboDev.SelectedItem
    if ($dev -match '\(([^)]+)\)\s*$') { $dev = $matches[1].Trim() }
    $cboProf.Items.Clear()
    [void]$cboProf.Items.Add('默认(按设备)')
    if ($script:profMap.ContainsKey($dev)) {
        foreach ($m in $script:profMap[$dev]) { [void]$cboProf.Items.Add($m) }
    }
    $cboProf.SelectedIndex = 0
}
$cboDev.add_SelectedIndexChanged({ Sync-Profiles })
Sync-Profiles

$f5 = New-Flow 24
$lblCnt = New-Lbl '共 0 个实例'
$lblCnt.ForeColor = $cMuted
$f5.Controls.Add($lblCnt)
$ilay.Controls.Add($f5, 0, 5)
$body.Controls.Add($gInst, 0, 0)

# ---- 实例逻辑 ----
function Inst() { return $txtName.Text.Trim() }
function Start-Inst {
    $n = Inst
    if (-not $n) { Log '先填实例名（或从列表选择）' -Color $cErr; return }
    $a = @('-start', $n)
    if ($chkNoWin.Checked) { $a += '-noWindow' }
    Run-Emu $a -Async
}
function Refresh-Instances {
    $script:seq++
    $tag = "{0:HHmmss}-{1}" -f (Get-Date), $script:seq
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $emuPath
    $psi.Arguments = '"-list" "-details"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { Log "列表失败: $($_.Exception.Message)" -Color $cErr; return }
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $txt = ($so.Result) + ($se.Result)
    Log "▶ -list -details"
    if ($txt.Trim()) { Log $txt.TrimEnd() }
    $list.Items.Clear()
    $parsed = $false
    try {
        $j = $txt | ConvertFrom-Json
        if ($j -is [System.Array] -and $j.Count -gt 0) {
            foreach ($x in $j) {
                $n = if ($x.name) { $x.name } elseif ($x.instanceName) { $x.instanceName } else { "$x" }
                [void]$list.Items.Add($n); $parsed = $true
            }
        }
    } catch { }
    if (-not $parsed) {
        foreach ($ln in ($txt -split "`r?`n")) {
            $t = $ln.Trim()
            if ($t -and $t -ne '[Empty]') { [void]$list.Items.Add(($t -split '\s+')[0]) }
        }
    }
    $lblCnt.Text = "共 $($list.Items.Count) 个实例"
}
$list.Add_SelectedIndexChanged({ if ($list.SelectedItem) { $txtName.Text = [string]$list.SelectedItem } })
$list.Add_DoubleClick({ if ($list.SelectedItem) { $txtName.Text = [string]$list.SelectedItem; Start-Inst } })

Add-Tip $bStart   '启动选中实例；勾选"无窗"则后台运行不弹窗口'
Add-Tip $bLic     '首次使用需接受 HarmonyOS 软件服务协议'
Add-Tip $chkForce '删除时跳过确认（实例在运行时也可强删）'
Add-Tip $chkNoWin '后台模式：不显示模拟器窗口，仅由本面板控制'

# ============================================================
# 右卡: 镜像管理
# ============================================================
$gImg = New-Grp ' 镜像管理 '
$mg = New-Object System.Windows.Forms.TableLayoutPanel
$mg.Dock = 'Fill'
$mg.ColumnCount = 1
$mg.RowCount = 3
$mg.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
$mg.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100))) | Out-Null
$mg.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 36))) | Out-Null
$mg.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 24))) | Out-Null
$gImg.Controls.Add($mg)

$lvImg = New-Object System.Windows.Forms.ListView
$lvImg.Dock = 'Fill'
$lvImg.View = 'Details'
$lvImg.FullRowSelect = $true
$lvImg.GridLines = $true
$lvImg.BorderStyle = 'FixedSingle'
$lvImg.Font = $fBody
[void]$lvImg.Columns.Add('HarmonyOS 版本', 210)
[void]$lvImg.Columns.Add('设备', 95)
[void]$lvImg.Columns.Add('状态', 80)
$mg.Controls.Add($lvImg, 0, 0)

$fImg = New-Flow
$bImgList = New-Btn '🔎 获取列表' { Refresh-Images } -Primary -w 115
$bInstall = New-Btn '↓ 下载' { Install-Image $false } -w 80
$bInstF   = New-Btn '↓ 强下' { Install-Image $true } -w 80
$bUninst  = New-Btn '✖ 卸载' { Uninstall-Image } -w 80
$fImg.Controls.Add($bImgList); $fImg.Controls.Add($bInstall); $fImg.Controls.Add($bInstF); $fImg.Controls.Add($bUninst)
$mg.Controls.Add($fImg, 0, 1)
Align-Flow $fImg

$fImg2 = New-Flow 24
$lblImgStat = New-Lbl '尚未获取镜像列表'
$lblImgStat.ForeColor = $cMuted
$fImg2.Controls.Add($lblImgStat)
$pbDl = New-Object System.Windows.Forms.ProgressBar
$pbDl.Width = 220; $pbDl.Height = 16; $pbDl.Visible = $false
$pbDl.Margin = New-Object System.Windows.Forms.Padding(10, 4, 2, 0)
$fImg2.Controls.Add($pbDl)
$mg.Controls.Add($fImg2, 0, 2)
$body.Controls.Add($gImg, 1, 0)

Add-Tip $bImgList '从华为镜像服务器拉取全部可下载镜像（联网）'
Add-Tip $bInstall  '下载镜像列表中选中的那一行（版本+设备取自该行）'
Add-Tip $bInstF    '同名镜像已存在时跳过校验强制重新下载'
Add-Tip $bUninst   '删除镜像列表中选中行的本地镜像文件'

function Refresh-Images {
    $script:seq++
    $tag = "{0:HHmmss}-{1}" -f (Get-Date), $script:seq
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $emuPath
    $psi.Arguments = '"-imageList"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { Log "镜像列表失败: $($_.Exception.Message)" -Color $cErr; return }
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $txt = ($so.Result) + ($se.Result)
    Log "▶ -imageList   (exit=$($p.ExitCode))"
    $lvImg.Items.Clear()
    $rows = 0
    try {
        $j = $txt | ConvertFrom-Json
        if ($j -is [System.Array]) {
            foreach ($x in $j) {
                $it = New-Object System.Windows.Forms.ListViewItem($x.osVersion)
                $it.SubItems.Add($x.deviceType)
                $st = if ($x.downloaded -eq 'true') { '✅ 已下载' } else { '未下载' }
                $it.SubItems.Add($st)
                $it.Tag = $x
                [void]$lvImg.Items.Add($it)
                $rows++
            }
        }
    } catch { Log '镜像列表解析失败，原文见下' -Color $cErr; if ($txt.Trim()) { Log $txt.TrimEnd() } }
    $imgRoot = Join-Path $env:LOCALAPPDATA 'Huawei\Sdk\system-image'
    $mb = 0
    if (Test-Path $imgRoot) {
        $mb = [math]::Round(((Get-ChildItem $imgRoot -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB)
    }
    $lblImgStat.Text = "共 $rows 个镜像 · 本地已占 $mb MB · 选择行同步到创建区"
}
function Selected-Image { return $script:lvImg.SelectedItems | Select-Object -First 1 }
function Install-Image([bool]$force) {
    $item = Selected-Image
    if (-not $item) { Log '先在镜像列表选一行' -Color $cErr; return }
    if ($script:dlBusy) { Log '已有下载进行中，请等待完成' -Color $cErr; return }
    $x = $item.Tag
    $a = @('-install', '-deviceType', $x.deviceType, '-osVersion', $x.osVersion)
    if ($force) { $a += '-force' }
    $script:dlBusy = $true
    $st = ''
    if (-not (Test-SdkAgreement)) {
        Log '首次下载需接受协议（自动应答 y）' -Color $cAccent
        $st = 'y'
    }
    Log "▶ $($a -join ' ')  (异步下载，进度见镜像卡片底部)" -Color $cOk
    $pbDl.Value = 0; $pbDl.Visible = $true
    $lblImgStat.Text = '连接镜像服务器...'
    try { $script:dlProc = Run-Emu-Stream $a $st }
    catch {
        Log "下载启动失败: $($_.Exception.Message)" -Color $cErr
        $script:dlBusy = $false; $pbDl.Visible = $false
        return
    }
    $script:dlTimer = New-Object System.Windows.Forms.Timer
    $script:dlTimer.Interval = 120
    $script:dlTimer.add_Tick({
        $line = $null
        while ($script:emuStream.Queue.TryDequeue([ref]$line)) {
            if ($line -match '([0-9.]+)%\s*\(\d+/(\d+)\s*bytes\)') {
                $pct = [double]$matches[1]
                $tot = [double]$matches[2]
                $script:pbDl.Value = [int][Math]::Min(100, $pct)
                $script:lblImgStat.Text = "下载中 {0:N1}%  ({1:N0} MB / {2:N1} GB)" -f $pct, ($tot * $pct / 100 / 1MB), ($tot / 1GB)
            } elseif ($line -match 'image will be download to\s+([^\s]+)') {
                $script:lblImgStat.Text = "保存到: $($matches[1])"
            } elseif ($line -match 'successfully|fail|error|Error') {
                Log $line -Color $(if ($line -match 'successfully') { $cOk } else { $cErr })
            }
        }
        if ($script:dlProc.HasExited) {
            $script:dlTimer.Stop()
            $script:dlProc.Refresh()
            $rc = $script:dlProc.ExitCode
            $script:pbDl.Visible = $false
            Log "  exit = $rc" -Color $(if ($rc -eq 0) { $cOk } else { $cErr })
            $script:dlBusy = $false
            # 进程退出后残余行再清一次
            while ($script:emuStream.Queue.TryDequeue([ref]$line)) {
                if ($line -match 'successfully|fail|error|Error') {
                    Log "  $line" -Color $(if ($line -match 'successfully') { $cOk } else { $cErr })
                }
            }
            Refresh-Images
        }
    })
    $script:dlTimer.Start()
}
function Uninstall-Image {
    $item = Selected-Image
    if (-not $item) { Log '先在镜像列表选一行' -Color $cErr; return }
    $x = $item.Tag
    Run-Emu @('-uninstall', '-deviceType', $x.deviceType, '-osVersion', $x.osVersion)
    Refresh-Images
}
$lvImg.Add_SelectedIndexChanged({
    if ($lvImg.SelectedItems.Count -gt 0) {
        $x = $lvImg.SelectedItems[0].Tag
        if ($x) {
            $cboVer.Text = $x.osVersion
            $dev = [string]$x.deviceType
            # 设备下拉是 "中文 (English)" 形式, 按英文段匹配
            $hit = @($cboDev.Items | Where-Object { ([string]$_ -match '\((.*?)\)\s*$') -and $matches[1].Trim() -ieq $dev })
            if ($hit.Count -gt 0) { $cboDev.SelectedItem = $hit[0] }
            # 同步机型: 优先该设备第一个真机; 无则默认
            if ($script:profMap.ContainsKey($dev) -and $script:profMap[$dev].Count -gt 0) {
                $pf = '默认(按设备)'; $profs = $script:profMap[$dev]
                for ($i = 0; $i -lt $cboProf.Items.Count; $i++) {
                    if ([string]$cboProf.Items[$i] -ieq [string]$profs[0]) { $pf = [string]$cboProf.Items[$i]; break }
                }
                $cboProf.SelectedItem = $pf
            }
        }
    }
})

# ============================================================
# 实例操作（常驻网格，作用于上方"实例名"）
# ============================================================
function ACtl([string[]]$rest) {
    $n = Inst
    if (-not $n) { Log '先填实例名' -Color $cErr; return }
    Run-Emu (@('-instance', $n) + $rest)
}
$gOps = New-Grp ' 实例操作 · 作用于上方"实例名" '
$ot = New-Object System.Windows.Forms.TableLayoutPanel
$ot.Dock = 'Fill'
$ot.ColumnCount = 7
$ot.RowCount = 8
$ot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 8)))  | Out-Null
$ot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 12))) | Out-Null
$ot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 9)))  | Out-Null
$ot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 8)))  | Out-Null
$ot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 12))) | Out-Null
$ot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 9)))  | Out-Null
$ot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 42))) | Out-Null
foreach ($r in 0..7) { $ot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 32))) | Out-Null }
$gOps.Controls.Add($ot)

function Ops-Lbl([string]$t) {
    $l = New-Lbl $t
    $l.Dock = 'Fill'
    $l.AutoSize = $false
    $l.TextAlign = 'MiddleRight'
    return $l
}
function Ops-Btn([string]$t, [scriptblock]$cb) {
    $b = New-Btn $t $cb
    $b.Dock = 'Fill'
    $b.AutoSize = $false
    return $b
}
function Ops-Txt([string]$def) {
    $t = New-Txt $def
    $t.Dock = 'Fill'
    return $t
}
function Ops-Cbo([string[]]$items) {
    $c = New-Cbo $items
    $c.Dock = 'Fill'
    return $c
}

$ot.Controls.Add((Ops-Lbl '旋转'), 0, 0)
$ot.Controls.Add((Ops-Btn '⟲ 左转' { ACtl @('-rotation','left') }), 1, 0)
$ot.Controls.Add((Ops-Btn '⟳ 右转' { ACtl @('-rotation','right') }), 2, 0)
$ot.Controls.Add((Ops-Lbl '音量'), 3, 0)
$ot.Controls.Add((Ops-Btn '音量 +' { ACtl @('-volume','up') }), 4, 0)
$ot.Controls.Add((Ops-Btn '音量 -' { ACtl @('-volume','down') }), 5, 0)

$ot.Controls.Add((Ops-Lbl '电源'), 0, 1)
$ot.Controls.Add((Ops-Btn '⏻ 电源' { ACtl @('-power') }), 1, 1)
$ot.Controls.Add((Ops-Lbl '晃动'), 3, 1)
$ot.Controls.Add((Ops-Btn '📳 晃动' { ACtl @('-shake') }), 4, 1)

$ot.Controls.Add((Ops-Lbl '折叠态'), 0, 2)
$txtFold = Ops-Txt 'folded'
$ot.Controls.Add($txtFold, 1, 2)
$ot.Controls.Add((Ops-Btn '应用' { ACtl @('-foldedState', $txtFold.Text) }), 2, 2)
$ot.Controls.Add((Ops-Lbl '电池 %'), 3, 2)
$txtBat = Ops-Txt '80'
$ot.Controls.Add($txtBat, 4, 2)
$ot.Controls.Add((Ops-Btn '设置' { ACtl @('-battery', $txtBat.Text) }), 5, 2)

$ot.Controls.Add((Ops-Lbl '城市'), 0, 3)
$txtCity = Ops-Txt 'Beijing'
$ot.Controls.Add($txtCity, 1, 3)
$ot.Controls.Add((Ops-Btn '📍 定位' { ACtl @('-gps', '-city', $txtCity.Text) }), 2, 3)
$ot.Controls.Add((Ops-Lbl '坐标'), 3, 3)
$txtLL = Ops-Txt '39.9,116.4'
$ot.Controls.Add($txtLL, 4, 3)
$ot.Controls.Add((Ops-Btn '定位' {
    if ($txtLL.Text -match '^\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*$') {
        $ll = $txtLL.Text -split ','
        ACtl @('-gps','-latitude',$ll[0].Trim(),'-longitude',$ll[1].Trim())
    } else { Log '坐标格式: 纬度,经度' -Color $cErr }
}), 5, 3)

$ot.Controls.Add((Ops-Lbl '传感器'), 0, 4)
$cboSen = Ops-Cbo ([string[]]@('亮度','步数','心率'))
$ot.Controls.Add($cboSen, 1, 4)
$txtSen = Ops-Txt '100'
$ot.Controls.Add($txtSen, 2, 4)
$ot.Controls.Add((Ops-Btn '应用' {
    $flag = switch ($cboSen.SelectedIndex) { 0 { '-light' } 1 { '-steps' } 2 { '-heartrate' } }
    ACtl @('-sensor', $flag, $txtSen.Text)
}), 3, 4)

$ot.Controls.Add((Ops-Lbl '点击'), 0, 5)
$txtClick = Ops-Txt ''
$ot.Controls.Add($txtClick, 1, 5)
$ot.Controls.Add((Ops-Btn '点击' { if ($txtClick.Text.Trim()) { ACtl @('-click', $txtClick.Text.Trim()) } }), 2, 5)
$ot.Controls.Add((Ops-Lbl '滑动'), 3, 5)
$txtSlide = Ops-Txt ''
$ot.Controls.Add($txtSlide, 4, 5)
$ot.Controls.Add((Ops-Btn '滑动' { if ($txtSlide.Text.Trim()) { ACtl @('-slide', $txtSlide.Text.Trim()) } }), 5, 5)

$ot.Controls.Add((Ops-Lbl '填字'), 0, 6)
$txtFillW = Ops-Txt ''
$ot.Controls.Add($txtFillW, 1, 6)
$txtFillT = Ops-Txt ''
$ot.Controls.Add($txtFillT, 2, 6)
$ot.SetColumnSpan($txtFillT, 2)
$ot.Controls.Add((Ops-Btn '填充' { if ($txtFillW.Text) { ACtl @('-fill', ('"{0} {1}"' -f $txtFillW.Text, $txtFillT.Text)) } }), 4, 6)
$bShot = Ops-Btn '📷 截图' { Shot }
$ot.Controls.Add($bShot, 5, 6)
Add-Tip $bShot '截取运行中实例的屏幕，保存到 图片\harmony-emulator 并自动打开'

$ot.Controls.Add((Ops-Lbl '操作'), 0, 7)
$ot.Controls.Add((Ops-Btn 'UI布局' { ACtl @('-uiLayout') }), 1, 7)
$ot.Controls.Add((Ops-Lbl '其他'), 3, 7)
$ot.Controls.Add((Ops-Btn '导出日志' { if (Inst) { Run-Emu @('-logZip', (Inst), '-logPath', $imgDir) } }), 4, 7)

$body.Controls.Add($gOps, 0, 1)
$body.SetColumnSpan($gOps, 2)

# ============================================================
# 日志 + 状态
# ============================================================
$gLog = New-Grp ' 日志 '
$logLay = New-Object System.Windows.Forms.TableLayoutPanel
$logLay.Dock = 'Fill'
$logLay.ColumnCount = 2
$logLay.RowCount = 1
$logLay.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
$logLay.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize'))) | Out-Null
$gLog.Controls.Add($logLay)
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock = 'Fill'
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(24, 27, 33)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(230, 233, 240)
$txtLog.BorderStyle = 'FixedSingle'
$txtLog.Font = $fMono
$txtLog.ReadOnly = $true
$logLay.Controls.Add($txtLog, 0, 0)
$bClear = New-Btn '清空' { $script:txtLog.Clear() }
$logLay.Controls.Add($bClear, 1, 0)
$body.Controls.Add($gLog, 0, 2)
$body.SetColumnSpan($gLog, 2)

$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Fill'
$status.TextAlign = 'MiddleLeft'
$status.ForeColor = $cMuted
$status.BackColor = $cBg
$body.Controls.Add($status, 0, 3)
$body.SetColumnSpan($status, 2)

# 截图
function Shot {
    $n = Inst
    if (-not $n) { Log '先填实例名' -Color $cErr; return }
    New-Item -ItemType Directory -Path $imgDir -Force | Out-Null
    $f = Join-Path $imgDir ("{0}-{1:yyyyMMdd-HHmmss}.png" -f $n, (Get-Date))
    Run-Emu @('-instance', $n, '-screenshot', '-screenshotPath', $f)
    if (Test-Path $f) {
        Log "截图已保存: $f" -Color $cOk
        Start-Process $f
    }
}

# 启动
try { $v = (& $emuPath '-version' 2>$null | Select-Object -First 1) } catch { $v = '' }
$agreeTxt = if (Test-SdkAgreement) { '协议已同意' } else { '协议未同意·下载时自动确认' }
$status.Text = if ($v) { "就绪 · $v · $agreeTxt" } else { "就绪 · $agreeTxt" }
Log "就绪 · $($v) · $emuPath"
Log '用法：刷新列表 → 选/填实例名 → 启动；镜像列表选中行 → 下载；实例操作用于上方实例。'
Refresh-Instances
[System.Windows.Forms.Application]::Run($form)