#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$OutputDir = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path "dist\windows"),
    [string]$SharedDir,
    [string]$Version = "0.1.0",
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"

$agents = @(
    @{
        Id = "codex"
        Name = "Codex"
        Script = "install.ps1"
        Notes = @(
            "Online installer wrapper for the official OpenAI Codex installer.",
            "Run install.ps1 -DryRun first on a clean Windows VM.",
            "Run install.ps1 after dry-run succeeds, then open a new terminal and run codex --version."
        )
    },
    @{
        Id = "openclaw"
        Name = "OpenClaw"
        Script = "install.ps1"
        Notes = @(
            "Online installer wrapper for the official OpenClaw Windows installer.",
            "Run install.ps1 -DryRun first on a clean Windows VM.",
            "Run install.ps1 after dry-run succeeds, then open a new terminal and run openclaw --version."
        )
    },
    @{
        Id = "cursor"
        Name = "Cursor"
        Script = "install.ps1"
        Notes = @(
            "Conservative Windows wrapper for Cursor CLI/Desktop setup.",
            "CLI setup requires Git Bash or WSL because the official Cursor CLI installer is a bash script.",
            "Desktop app install is currently documented rather than silently automated."
        )
    }
)

function Write-TextFile([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function New-RunCmd([string]$Path) {
    $content = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
"@
    Write-TextFile $Path $content
}

function New-PackageReadme($agent, [string]$Path, [string]$Version) {
    $notes = ($agent.Notes | ForEach-Object { "- $_" }) -join "`r`n"
    $content = @"
# $($agent.Name) Windows Installer v$Version

This package is an online Windows installer wrapper. It does not bundle the upstream agent binary.

## What it does

$notes

## How to run

Open PowerShell in this folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

You can also double-click `run.cmd`.

## Verification

After installation, close the old terminal, open a new PowerShell window, and run the version command shown by the installer.

Logs are written to the local `logs` folder. Do not paste logs publicly if they contain account paths or provider output.
"@
    Write-TextFile $Path $content
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$manifest = [ordered]@{
    version = $Version
    builtAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    packages = @()
}
$testPlan = Join-Path $Root "shared\test-plans\windows-agent-online-wrappers.md"

foreach ($agent in $agents) {
    $sourceDir = Join-Path $Root "installers\windows\$($agent.Id)"
    $sourceScript = Join-Path $sourceDir $agent.Script
    if (-not (Test-Path $sourceScript)) {
        throw "Missing installer script: $sourceScript"
    }

    $packageName = "$($agent.Id)-windows-v$Version"
    $packageDir = Join-Path $OutputDir $packageName
    if (Test-Path $packageDir) {
        Remove-Item -LiteralPath $packageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

    Copy-Item -LiteralPath $sourceScript -Destination (Join-Path $packageDir "install.ps1") -Force
    $sourceReadme = Join-Path $sourceDir "README.md"
    if (Test-Path $sourceReadme) {
        Copy-Item -LiteralPath $sourceReadme -Destination (Join-Path $packageDir "UPSTREAM-NOTES.md") -Force
    }
    if (Test-Path $testPlan) {
        Copy-Item -LiteralPath $testPlan -Destination (Join-Path $packageDir "TEST-PLAN.md") -Force
    }
    New-RunCmd (Join-Path $packageDir "run.cmd")
    New-PackageReadme $agent (Join-Path $packageDir "README.md") $Version

    $entry = [ordered]@{
        id = $agent.Id
        name = $agent.Name
        version = $Version
        folder = $packageName
        status = "online-wrapper"
        dryRunCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun"
        installCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1"
    }

    if (-not $NoZip) {
        $zipPath = Join-Path $OutputDir "$packageName.zip"
        if (Test-Path $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force
        }
        Compress-Archive -Path (Join-Path $packageDir "*") -DestinationPath $zipPath -Force
        $hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
        $entry.zip = Split-Path -Leaf $zipPath
        $entry.sha256 = $hash.Hash
    }

    $manifest.packages += $entry

    if ($SharedDir) {
        if (-not (Test-Path $SharedDir)) {
            New-Item -ItemType Directory -Path $SharedDir -Force | Out-Null
        }
        $sharedPackage = Join-Path $SharedDir $packageName
        if (Test-Path $sharedPackage) {
            Remove-Item -LiteralPath $sharedPackage -Recurse -Force
        }
        Copy-Item -LiteralPath $packageDir -Destination $sharedPackage -Recurse -Force
        if (-not $NoZip) {
            Copy-Item -LiteralPath (Join-Path $OutputDir "$packageName.zip") -Destination (Join-Path $SharedDir "$packageName.zip") -Force
        }
    }
}

$manifestPath = Join-Path $OutputDir "windows-agent-packages.json"
Write-TextFile $manifestPath ($manifest | ConvertTo-Json -Depth 6)
if ($SharedDir) {
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $SharedDir "windows-agent-packages.json") -Force
}

Write-Host "Built Windows agent packages in: $OutputDir" -ForegroundColor Green
if ($SharedDir) {
    Write-Host "Synced packages to: $SharedDir" -ForegroundColor Green
}
