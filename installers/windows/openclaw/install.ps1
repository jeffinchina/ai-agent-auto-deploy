#Requires -Version 5.1
param(
    [string]$Tag = "latest",
    [switch]$RunOnboarding,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$VERSION = "0.1.0"
$LOGDIR = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $LOGDIR -Force | Out-Null
$LOGFILE = Join-Path $LOGDIR "openclaw-windows-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Log($m) { Add-Content $LOGFILE "[$(Get-Date -Format 'HH:mm:ss')] $m" -Encoding UTF8 }
function Say($c,$m) { Write-Host $m -ForegroundColor $c; Log $m }
function Ok($m) { Say Green "[OK] $m" }
function Info($m) { Say Gray "[INFO] $m" }
function Warn($m) { Say Yellow "[WARN] $m" }
function Fail($m,$hint) { Say Red "[ERR] $m"; if($hint){ Info "建议: $hint" }; Info "日志: $LOGFILE"; exit 1 }

function Preflight {
    Say Cyan "OpenClaw Windows Installer v$VERSION"
    if ([Environment]::OSVersion.Platform -ne "Win32NT") { Fail "当前脚本仅支持 Windows" "请使用 Windows 10/11。" }
    Ok "Windows 检测通过"
}

function Install-OpenClaw {
    if ($DryRun) {
        Info "DryRun: 跳过 OpenClaw 官方安装脚本下载与执行"
        return
    }
    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Ok "OpenClaw 已存在"
        return
    }
    Info "下载 OpenClaw 官方 Windows 安装脚本..."
    $script = Invoke-WebRequest -UseBasicParsing -Uri "https://openclaw.ai/install.ps1" -TimeoutSec 120
    $block = [scriptblock]::Create([Text.Encoding]::UTF8.GetString([byte[]]$script.Content))
    if ($RunOnboarding) {
        & $block -Tag $Tag 2>&1 | ForEach-Object { Log $_; Write-Host $_ }
    } else {
        & $block -Tag $Tag -NoOnboard 2>&1 | ForEach-Object { Log $_; Write-Host $_ }
    }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Fail "OpenClaw 安装失败" "请检查日志和网络。" }
    Ok "OpenClaw 安装命令完成"
}

function Verify {
    if ($DryRun) {
        Info "DryRun: 跳过 openclaw --version"
        Ok "OpenClaw Windows dry-run 通过"
        return
    }
    $cmd = Get-Command openclaw -ErrorAction SilentlyContinue
    if (-not $cmd) { Fail "未找到 openclaw 命令" "请重新打开终端或检查安装日志。" }
    $v = & $cmd.Source --version 2>&1
    Log $v
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Warn "openclaw --version 返回非 0" }
    else { Ok "openclaw 可用: $v" }
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


