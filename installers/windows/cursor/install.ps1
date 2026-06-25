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

function Refresh-ProcessPath {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($part in ($env:Path -split ';')) {
        if ($part -and -not $parts.Contains($part)) { $parts.Add($part) }
    }
    foreach ($scope in @("Machine", "User")) {
        $value = [Environment]::GetEnvironmentVariable("Path", $scope)
        if ($value) {
            foreach ($part in ($value -split ';')) {
                if ($part -and -not $parts.Contains($part)) { $parts.Add($part) }
            }
        }
    }
    $common = @(
        "$env:USERPROFILE\.local\bin",
        "$env:LOCALAPPDATA\Programs\Cursor",
        "$env:LOCALAPPDATA\Programs\cursor"
    )
    foreach ($part in $common) {
        if ((Test-Path $part) -and -not $parts.Contains($part)) { $parts.Add($part) }
    }
    $env:Path = ($parts -join ';')
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

function Get-BashKernelName([string]$bashPath) {
    if (-not $bashPath) { return $null }
    $r = Invoke-Captured $bashPath @("-lc", "uname -s") 30
    if ($r.ExitCode -ne 0) { return $null }
    return $r.StdOut.Trim()
}

function Find-CursorDesktop {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Cursor\Cursor.exe",
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:ProgramFiles\Cursor\Cursor.exe",
        "${env:ProgramFiles(x86)}\Cursor\Cursor.exe"
    )
    foreach($p in $candidates){ if(Test-Path $p){ return $p } }
    $cmd = Get-Command cursor -ErrorAction SilentlyContinue
    if($cmd){ return $cmd.Source }
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
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) { Fail "未找到 winget" "Cursor 桌面版自动安装需要 Windows Package Manager；也可访问 https://cursor.com/download 手动安装。" }
    }
    if ($InstallCliWithBash) {
        $bash = Find-Bash
        if ($bash) {
            Info "检测到 bash: $bash"
            $kernel = Get-BashKernelName $bash
            if ($kernel) { Info "bash uname: $kernel" }
            if (-not $DryRun -and -not $VerifyOnly -and $kernel -notmatch '^(Linux|Darwin)') {
                Fail "Cursor Agent CLI 官方安装器不支持当前 bash 环境: $kernel" "Windows 原生请使用 -InstallDesktop；需要 CLI 时请在 WSL2 Linux 或 macOS 中运行 Cursor 官方安装器。"
            }
        }
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
        $existing = Find-CursorDesktop
        if ($existing) {
            Ok "Cursor 桌面版已存在: $existing"
            return
        }
        Info "使用 winget 安装 Cursor 桌面版..."
        $r = Invoke-Captured "winget.exe" @(
            "install",
            "--id", "Anysphere.Cursor",
            "--exact",
            "--source", "winget",
            "--scope", "user",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements"
        ) 900
        Log $r.StdOut
        Log $r.StdErr
        if ($r.ExitCode -ne 0) { Fail "Cursor 桌面版安装失败" "请查看日志，或手动访问 https://cursor.com/download。" }
        Ok "Cursor 桌面版安装命令完成"
    }
}

function Verify {
    if ($DryRun) {
        Ok "Cursor Windows dry-run 通过"
        return
    }
    Refresh-ProcessPath
    if ($InstallDesktop) {
        $desktop = Find-CursorDesktop
        if ($desktop) {
            Ok "Cursor 桌面版可用: $desktop"
        } else {
            Fail "未检测到 Cursor 桌面版" "请打开新终端后重试；如果仍失败，请查看 winget 安装日志或访问 https://cursor.com/download。"
        }
    }
    if ($InstallCliWithBash -or (-not $InstallDesktop)) {
        $cursorAgent = Get-Command cursor-agent -ErrorAction SilentlyContinue
        if ($cursorAgent) {
            Ok "cursor-agent 可用: $($cursorAgent.Source)"
        } else {
            Fail "未检测到 cursor-agent" "Cursor Agent CLI 官方安装器当前不支持 Windows Git Bash；请在 WSL2 Linux/macOS 中安装，或仅使用 -InstallDesktop。"
        }
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


