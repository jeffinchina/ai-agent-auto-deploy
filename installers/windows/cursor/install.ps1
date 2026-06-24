#Requires -Version 5.1
param(
    [switch]$InstallDesktop,
    [switch]$InstallCliWithBash,
    [switch]$VerifyOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$VERSION = "0.1.0"
$LOGDIR = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $LOGDIR -Force | Out-Null
$LOGFILE = Join-Path $LOGDIR "cursor-windows-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$PID.log"

function Sanitize($s) {
    if ($null -eq $s) { return "" }
    return ([string]$s) -replace 'sk-[A-Za-z0-9_\-]+', 'sk-***' -replace '(?i)Bearer\s+[A-Za-z0-9_\-\.=]+', 'Bearer ***'
}
function Log($m) { Add-Content $LOGFILE "[$(Get-Date -Format 'HH:mm:ss')] $(Sanitize $m)" -Encoding UTF8 }
function Say($c,$m) { Write-Host $m -ForegroundColor $c; Log $m }
function Ok($m) { Say Green "[OK] $m" }
function Info($m) { Say Gray "[INFO] $m" }
function Warn($m) { Say Yellow "[WARN] $m" }
function Fail($m,$hint) { Say Red "[ERR] $m"; if($hint){ Info "建议: $hint" }; Info "日志: $LOGFILE"; exit 1 }

function Invoke-Captured($file, [string[]]$arguments, [int]$timeoutSec = 300) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = ($arguments | ForEach-Object {
        $a = [string]$_
        if ($a -match '[\s"]') { '"' + ($a -replace '"','\"') + '"' } else { $a }
    }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $done = $p.WaitForExit($timeoutSec * 1000)
    if(-not $done){ try { $p.Kill() } catch {}; return @{ ExitCode = 124; StdOut = ""; StdErr = "timeout after $timeoutSec seconds" } }
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; StdOut = Sanitize $outTask.Result; StdErr = Sanitize $errTask.Result }
}

function Find-Bash {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach($p in $candidates){ if(Test-Path $p){ return $p } }
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if($bash){ return $bash.Source }
    return $null
}

function Preflight {
    Say Cyan "Cursor Windows Installer v$VERSION"
    if ([Environment]::OSVersion.Platform -ne "Win32NT") { Fail "当前脚本仅支持 Windows" "请使用 Windows 10/11。" }
    if (-not [Environment]::Is64BitOperatingSystem) { Fail "不支持 32 位 Windows" "请换用 64 位 Windows。" }
    Ok "Windows 64 位"
    if (-not $DryRun -and -not $VerifyOnly -and -not $InstallCliWithBash -and -not $InstallDesktop) {
        Fail "未选择 Cursor 安装模式" "CLI 安装请加 -InstallCliWithBash；桌面 App 当前请从 https://cursor.com/download 手动安装。"
    }
    if (-not $DryRun -and -not $VerifyOnly -and $InstallDesktop -and -not $InstallCliWithBash) {
        Fail "Cursor 桌面 App 自动安装尚未实现" "请使用官方下载页安装桌面 App；CLI 自动安装请加 -InstallCliWithBash。"
    }
    if ($InstallCliWithBash) {
        $bash = Find-Bash
        if ($bash) { Info "检测到 bash: $bash" }
        elseif (-not $DryRun) { Fail "未找到 Git Bash/WSL bash" "Cursor CLI 官方安装器是 bash 脚本；请先安装 Git for Windows 或 WSL2。" }
    }
    Ok "安装前检测完成"
}

function Install-CursorCli {
    if ($VerifyOnly) {
        Info "VerifyOnly: 跳过 Cursor CLI 安装"
        return
    }
    if (-not $InstallCliWithBash) {
        if ($DryRun) { Warn "DryRun: 未选择 Cursor CLI 安装模式" }
        Info "需要 CLI 时可加 -InstallCliWithBash，或在 Git Bash/WSL 中运行: curl https://cursor.com/install -fsS | bash"
        return
    }

    if ($DryRun) {
        Info "DryRun: 跳过 Cursor CLI bash 安装器执行"
        return
    }

    $bash = Find-Bash
    if (-not $bash) { Fail "未找到 Git Bash/WSL bash" "Cursor CLI 官方安装器是 bash 脚本；请先安装 Git for Windows 或 WSL2。" }
    Info "使用官方 Cursor CLI 安装脚本..."
    $r = Invoke-Captured $bash @("-lc", "curl https://cursor.com/install -fsS | bash") 600
    Log $r.StdOut
    Log $r.StdErr
    if ($r.ExitCode -ne 0) { Fail "Cursor CLI 安装失败" "请查看日志或手动访问 https://cursor.com/docs/cli/installation。" }
    Ok "Cursor CLI 安装命令完成"
}

function Install-CursorDesktop {
    if (-not $InstallDesktop) { return }
    if ($VerifyOnly) {
        Info "VerifyOnly: 跳过 Cursor 桌面 App 安装"
        return
    }
    if ($DryRun) {
        Info "DryRun: 跳过 Cursor 桌面 App 安装"
    } else {
        Fail "Cursor 桌面 App 自动下载/静默安装尚未实现" "请使用官方下载页: https://cursor.com/download"
    }
    Info "当前请使用官方下载页: https://cursor.com/download"
}

function Verify {
    if ($DryRun) {
        Ok "Cursor Windows dry-run 通过"
        return
    }
    $cursorAgent = Get-Command cursor-agent -ErrorAction SilentlyContinue
    if ($cursorAgent) {
        Ok "cursor-agent 可用: $($cursorAgent.Source)"
    } else {
        Fail "未检测到 cursor-agent" "请打开新终端后重试；如果仍失败，请确认 Git Bash/WSL 中的官方安装器是否成功。"
    }
}

try {
    Preflight
    Install-CursorCli
    Install-CursorDesktop
    Verify
    Ok "Cursor Windows 安装流程完成"
} catch {
    Fail "未预期错误: $($_.Exception.Message)" "请查看日志并重新运行。"
}


