#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$OutputDir = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path "dist\macos"),
    [string]$SharedDir,
    [string]$Version = "0.1.0",
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"

$agents = @(
    @{ Id = "claude-code"; Name = "Claude Code" },
    @{ Id = "codex"; Name = "Codex" },
    @{ Id = "openclaw"; Name = "OpenClaw" },
    @{ Id = "cursor"; Name = "Cursor" }
)

function Write-TextFile([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function New-PackageReadme($agent, [string]$Path, [string]$Version) {
    $extra = ""
    if ($agent.Id -eq "codex") {
        $extra = @"

## DeepSeek Release Gate

For release validation, set a runtime DeepSeek key and use the LiteLLM bridge:

~~~bash
export DEEPSEEK_API_KEY="sk-..."
PREPARE_DEEPSEEK_LITELLM=1 INSTALL_LITELLM_PROXY=1 bash install.sh
RUN_DEEPSEEK_SMOKE=1 bash install.sh
unset DEEPSEEK_API_KEY
~~~

Do not paste API keys into logs, screenshots, Git history, or chat.
"@
    }
    if ($agent.Id -eq "openclaw") {
        $extra = @"

## DeepSeek Release Gate

For release validation, set a runtime DeepSeek key or use the hidden prompt:

~~~bash
export DEEPSEEK_API_KEY="sk-..."
CONFIGURE_DEEPSEEK=1 bash install.sh
RUN_DEEPSEEK_SMOKE=1 bash install.sh
unset DEEPSEEK_API_KEY
~~~

Do not paste API keys into logs, screenshots, Git history, or chat.
"@
    }
    $content = @"
# $($agent.Name) macOS Installer v$Version

This package is an online macOS installer wrapper. It does not bundle the upstream agent binary.

## How to run

Open Terminal in this folder:

~~~bash
DRY_RUN=1 bash install.sh
bash install.sh
~~~

## Verification

After installation, close the old terminal, open a new Terminal window, and run the version or doctor command shown by the installer.

See TEST-PLAN.md for the current macOS verification boundary. Windows packaging and CI dry-runs are not a substitute for a real Mac smoke test.
$extra
"@
    Write-TextFile $Path $content
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$testPlan = Join-Path $Root "shared\test-plans\macos-agent-online-wrappers.md"
$manifest = [ordered]@{
    version = $Version
    builtAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    packages = @()
}

foreach ($agent in $agents) {
    $sourceDir = Join-Path $Root "installers\macos\$($agent.Id)"
    $sourceScript = Join-Path $sourceDir "install.sh"
    if (-not (Test-Path $sourceScript)) {
        throw "Missing installer script: $sourceScript"
    }

    $packageName = "$($agent.Id)-macos-v$Version"
    $packageDir = Join-Path $OutputDir $packageName
    if (Test-Path $packageDir) {
        Remove-Item -LiteralPath $packageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

    Copy-Item -LiteralPath $sourceScript -Destination (Join-Path $packageDir "install.sh") -Force
    $sourceReadme = Join-Path $sourceDir "README.md"
    if (Test-Path $sourceReadme) {
        Copy-Item -LiteralPath $sourceReadme -Destination (Join-Path $packageDir "UPSTREAM-NOTES.md") -Force
    }
    if (Test-Path $testPlan) {
        Copy-Item -LiteralPath $testPlan -Destination (Join-Path $packageDir "TEST-PLAN.md") -Force
    }
    New-PackageReadme $agent (Join-Path $packageDir "README.md") $Version

    $entry = [ordered]@{
        id = $agent.Id
        name = $agent.Name
        version = $Version
        folder = $packageName
        status = "online-wrapper"
        dryRunCommand = "DRY_RUN=1 bash install.sh"
        installCommand = "bash install.sh"
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

$manifestPath = Join-Path $OutputDir "macos-agent-packages.json"
Write-TextFile $manifestPath ($manifest | ConvertTo-Json -Depth 6)
if ($SharedDir) {
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $SharedDir "macos-agent-packages.json") -Force
}

Write-Host "Built macOS agent packages in: $OutputDir" -ForegroundColor Green
if ($SharedDir) {
    Write-Host "Synced macOS packages to: $SharedDir" -ForegroundColor Green
}
