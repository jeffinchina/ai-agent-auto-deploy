#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$SharedDir = "D:\VMs\CCDeployTest\Shared"
)

$ErrorActionPreference = "Stop"

$source = Join-Path $Root "shared\vm\Run-Windows-Agent-Acceptance.ps1"
if (-not (Test-Path $source)) {
    throw "Missing VM guest runner: $source"
}

if (-not (Test-Path $SharedDir)) {
    New-Item -ItemType Directory -Path $SharedDir -Force | Out-Null
}

$target = Join-Path $SharedDir "Run-Windows-Agent-Acceptance.ps1"
Copy-Item -LiteralPath $source -Destination $target -Force

$cmd = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Windows-Agent-Acceptance.ps1" -RunProviderGate -InstallLiteLLMProxy
echo.
pause
"@
Set-Content -LiteralPath (Join-Path $SharedDir "Run-Windows-Agent-Acceptance.cmd") -Value $cmd -Encoding ASCII

foreach ($agent in @("codex", "openclaw", "cursor")) {
    $agentCmd = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Windows-Agent-Acceptance.ps1" -Agent $agent -RunProviderGate -InstallLiteLLMProxy
echo.
pause
"@
    Set-Content -LiteralPath (Join-Path $SharedDir "Run-Windows-Agent-Acceptance-$agent.cmd") -Value $agentCmd -Encoding ASCII
}

Write-Host "Synced VM guest runner to: $target" -ForegroundColor Green
Write-Host "VM command: \\VBOXSVR\CCDeployPackage\Run-Windows-Agent-Acceptance.cmd" -ForegroundColor Green
Write-Host "Release gate: restore clean-base and run one per-agent .cmd at a time." -ForegroundColor Yellow
