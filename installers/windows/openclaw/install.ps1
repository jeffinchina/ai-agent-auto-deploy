#Requires -Version 5.1
param(
    [string]$Tag = "latest",
    [switch]$RunOnboarding,
    [switch]$VerifyOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$VERSION = "0.1.0"
$LOGDIR = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $LOGDIR -Force | Out-Null
$LOGFILE = Join-Path $LOGDIR "openclaw-windows-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$PID.log"

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
        "$env:APPDATA\npm",
        "$env:LOCALAPPDATA\OpenClaw\deps\portable-node",
        "$env:LOCALAPPDATA\OpenClaw\deps\portable-git\cmd",
        "$env:LOCALAPPDATA\OpenClaw\deps\portable-git\bin",
        "$env:LOCALAPPDATA\OpenClaw\deps\portable-git\mingw64\bin",
        "$env:LOCALAPPDATA\OpenClaw\deps\portable-git\usr\bin"
    )
    foreach ($part in $common) {
        if ((Test-Path $part) -and -not $parts.Contains($part)) { $parts.Add($part) }
    }
    $env:Path = ($parts -join ';')
}

function Invoke-PowerShellCommandCaptured([string]$commandName, [string[]]$arguments, [int]$timeoutSec = 120) {
    $quotedArgs = ($arguments | ForEach-Object {
        "'" + ([string]$_ -replace "'", "''") + "'"
    }) -join " "
    $script = "& '$commandName' $quotedArgs; if (`$null -ne `$LASTEXITCODE) { exit `$LASTEXITCODE }"
    return Invoke-Captured "powershell.exe" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $script) $timeoutSec
}

function Preflight {
    Say Cyan "OpenClaw Windows Installer v$VERSION"
    if ([Environment]::OSVersion.Platform -ne "Win32NT") { Fail "当前脚本仅支持 Windows" "请使用 Windows 10/11。" }
    if (-not [Environment]::Is64BitOperatingSystem) { Fail "不支持 32 位 Windows" "请换用 64 位 Windows。" }
    Ok "Windows 64 位"
    if ($DryRun) {
        Info "DryRun: 跳过网络连通性验证"
    }
    Ok "安装前检测完成"
}

function Install-OpenClaw {
    if ($VerifyOnly) {
        Info "VerifyOnly: 跳过 OpenClaw 安装"
        return
    }
    if ($DryRun) {
        Info "DryRun: 跳过 OpenClaw 官方安装脚本下载与执行"
        return
    }
    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Ok "OpenClaw 已存在"
        return
    }
    Info "下载 OpenClaw 官方 Windows 安装脚本..."
    $scriptPath = Join-Path $env:TEMP "openclaw-install.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "https://openclaw.ai/install.ps1" -OutFile $scriptPath -TimeoutSec 120
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-Tag", $Tag)
    if ($RunOnboarding) {
        Info "将运行官方 onboarding"
    } else {
        $args += "-NoOnboard"
    }
    $r = Invoke-Captured "powershell.exe" $args 600
    Log $r.StdOut
    Log $r.StdErr
    Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) { Fail "OpenClaw 安装失败" "请检查日志和网络，或手动运行官方安装命令。" }
    Ok "OpenClaw 安装命令完成"
}

function Verify {
    if ($DryRun) {
        Info "DryRun: 跳过 openclaw --version"
        Ok "OpenClaw Windows dry-run 通过"
        return
    }
    Refresh-ProcessPath
    $cmd = Get-Command openclaw -ErrorAction SilentlyContinue
    if (-not $cmd) { Fail "未找到 openclaw 命令" "请重新打开终端或检查安装日志。" }
    Info "检测到 openclaw: $($cmd.Source)"
    $v = Invoke-PowerShellCommandCaptured "openclaw" @("--version") 60
    Log $v.StdOut
    Log $v.StdErr
    if ($v.ExitCode -ne 0) { Fail "openclaw --version 返回非 0" "请重新打开终端后重试；如果仍失败，请检查安装日志。" }
    else { Ok "openclaw 可用: $($v.StdOut.Trim())" }
    Info "首次使用可运行: openclaw onboard"
}

try {
    Preflight
    Install-OpenClaw
    Verify
    Ok "OpenClaw Windows 安装流程完成"
} catch {
    Fail "未预期错误: $($_.Exception.Message)" "请查看日志并重新运行。"
}


