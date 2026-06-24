#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = "Stop"

function Pass($message) { Write-Host "[PASS] $message" -ForegroundColor Green }
function Fail($message) { throw "[FAIL] $message" }

$psFiles = @()
foreach ($relative in @("installers", "tools")) {
    $path = Join-Path $Root $relative
    if (Test-Path $path) {
        $psFiles += Get-ChildItem -Path $path -Recurse -Filter "*.ps1"
    }
}
foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors) {
        $message = ($errors | ForEach-Object { "$($file.FullName):$($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
        Fail "PowerShell parse errors:`n$message"
    }
}
Pass "PowerShell installers parse"

$installerPsFiles = Get-ChildItem -Path (Join-Path $Root "installers") -Recurse -Filter "*.ps1"
foreach ($file in $installerPsFiles) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $file.FullName -DryRun 2>&1
    if ($LASTEXITCODE -ne 0) {
        $tail = ($output | Select-Object -Last 20) -join "`n"
        Fail "PowerShell dry-run failed: $($file.FullName)`n$tail"
    }
}
Pass "PowerShell installer dry-runs passed"

$buildScript = Join-Path $Root "tools\build-windows-agent-packages.ps1"
if (Test-Path $buildScript) {
    $tempDist = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-agent-auto-deploy-dist-" + [guid]::NewGuid().ToString("N"))
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Root $Root -OutputDir $tempDist -NoZip 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tail = ($output | Select-Object -Last 20) -join "`n"
            Fail "Windows package build dry-run failed:`n$tail"
        }
        foreach ($agent in @("codex", "openclaw", "cursor")) {
            $folder = Join-Path $tempDist "$agent-windows-v0.1.0"
            if (-not (Test-Path (Join-Path $folder "install.ps1"))) {
                Fail "Windows package build missing install.ps1 for $agent"
            }
            if (-not (Test-Path (Join-Path $folder "run.cmd"))) {
                Fail "Windows package build missing run.cmd for $agent"
            }
        }
        Pass "Windows package build dry-run passed"
    } finally {
        if (Test-Path $tempDist) {
            Remove-Item -LiteralPath $tempDist -Recurse -Force
        }
    }
}

$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "D:\Program Files\Git\bin\bash.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { $bash = @{ Source = $candidate }; break }
    }
}

$shFiles = Get-ChildItem -Path (Join-Path $Root "installers") -Recurse -Filter "*.sh"
if ($bash) {
    foreach ($file in $shFiles) {
        & $bash.Source -n $file.FullName
        if ($LASTEXITCODE -ne 0) { Fail "bash -n failed: $($file.FullName)" }
    }
    Pass "shell installers parse"
} else {
    Write-Host "[WARN] bash not found; skipped shell syntax checks" -ForegroundColor Yellow
}

$scanRoots = @("installers", "shared", "docs", "tests", "tools")
foreach ($relative in $scanRoots) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path $path)) { continue }
    $files = Get-ChildItem -Path $path -Recurse -File | Where-Object { $_.Extension -in ".ps1",".sh",".md",".json" }
    foreach ($file in $files) {
        $text = Get-Content $file.FullName -Raw -Encoding UTF8
        if ($text -match 'sk-[A-Za-z0-9_\-]{12,}' -or $text -match '(?i)Bearer\s+sk-') {
            Fail "possible API key leaked in $($file.FullName)"
        }
    }
}
Pass "no obvious API keys in installer text"

Write-Host "All installer checks passed." -ForegroundColor Cyan

