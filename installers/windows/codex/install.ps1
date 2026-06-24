#Requires -Version 5.1
param(
    [string]$Release = "latest",
    [switch]$InstallDesktopApp,
    [switch]$SkipLoginHint,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$VERSION = "0.1.0"
$LOGDIR = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $LOGDIR -Force | Out-Null
$LOGFILE = Join-Path $LOGDIR "codex-windows-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

function Invoke-Captured($file, [string[]]$arguments, [int]$timeoutSec = 120) {
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
    if(-not $done){ try { $p.Kill() } catch {}; return @{ ExitCode = 124; StdOut = ""; StdErr = "timeout" } }
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; StdOut = Sanitize $outTask.Result; StdErr = Sanitize $errTask.Result }
}

function Preflight {
    Say Cyan "Codex Windows Installer v$VERSION"
    if ([Environment]::OSVersion.Platform -ne "Win32NT") { Fail "当前脚本仅支持 Windows" "请使用 Windows 10/11。" }
    if (-not [Environment]::Is64BitOperatingSystem) { Fail "不支持 32 位 Windows" "请换用 64 位 Windows。" }
    Ok "Windows 64 位"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($InstallDesktopApp -and -not $DryRun -and -not $winget) { Fail "未找到 winget" "安装 Codex 桌面 App 需要 Windows Package Manager。" }
    Ok "安装前检测完成"
}

function Install-CodexCli {
    if ($DryRun) {
        Info "DryRun: 跳过 Codex CLI 下载与安装"
        return
    }
    $existing = Get-Command codex -ErrorAction SilentlyContinue
    if ($existing) {
        Info "检测到 codex: $($existing.Source)"
        return
    }

    Info "下载 OpenAI 官方 Codex CLI 安装脚本..."
    $installScript = Join-Path $env:TEMP "codex-install.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "https://chatgpt.com/codex/install.ps1" -OutFile $installScript -TimeoutSec 120
    $env:CODEX_NON_INTERACTIVE = "1"
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $installScript)
    if ($Release -and $Release -ne "latest") { $args += @("-Release", $Release) }
    $r = Invoke-Captured "powershell.exe" $args 300
    Log $r.StdOut
    Log $r.StdErr
    Remove-Item $installScript -Force -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) { Fail "Codex CLI 安装失败" "请检查网络，或手动运行官方安装命令。" }
    Ok "Codex CLI 安装完成"
}

function Install-CodexDesktop {
    if (-not $InstallDesktopApp) { return }
    if ($DryRun) {
        Info "DryRun: 跳过 Codex 桌面 App 安装"
        return
    }
    Info "安装 Codex 桌面 App..."
    $r = Invoke-Captured "winget.exe" @("install", "Codex", "-s", "msstore", "--accept-package-agreements", "--accept-source-agreements") 600
    Log $r.StdOut
    Log $r.StdErr
    if ($r.ExitCode -ne 0) { Warn "Codex 桌面 App 安装未确认成功，可稍后手动运行 winget install Codex -s msstore" }
    else { Ok "Codex 桌面 App 安装完成" }
}

function Verify {
    if ($DryRun) {
        Info "DryRun: 跳过 codex --version 和 codex doctor"
        Ok "Codex Windows dry-run 通过"
        return
    }
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $cmd) { Fail "未找到 codex 命令" "请重新打开终端，或检查安装脚本输出。" }
    $ver = Invoke-Captured $cmd.Source @("--version") 60
    Log $ver.StdOut
    Log $ver.StdErr
    if ($ver.ExitCode -ne 0) { Fail "codex --version 验证失败" "请查看日志。" }
    Ok "codex 可用: $($ver.StdOut.Trim())"

    $doctor = Invoke-Captured $cmd.Source @("doctor") 120
    Log $doctor.StdOut
    Log $doctor.StdErr
    if ($doctor.ExitCode -ne 0) { Warn "codex doctor 返回非 0，可能需要登录或修复本机环境" }
    else { Ok "codex doctor 通过" }

    if (-not $SkipLoginHint) {
        Info "首次使用请运行: codex login"
        Info "ChatGPT 登录是默认路径；API key 登录适合 CI/自动化场景。"
    }
}

try {
    Preflight
    Install-CodexCli
    Install-CodexDesktop
    Verify
    Ok "Codex Windows 安装流程完成"
} catch {
    Fail "未预期错误: $($_.Exception.Message)" "请查看日志并重新运行。"
}


