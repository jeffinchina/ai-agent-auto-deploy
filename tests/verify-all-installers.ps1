#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = "Stop"

function Pass($message) { Write-Host "[PASS] $message" -ForegroundColor Green }
function Fail($message) { throw "[FAIL] $message" }

$psFiles = Get-ChildItem -Path (Join-Path $Root "installers") -Recurse -Filter "*.ps1"
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

$scanRoots = @("installers", "shared", "docs", "tests")
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


