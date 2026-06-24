#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = "Stop"

function Pass($message) { Write-Host "[PASS] $message" -ForegroundColor Green }
function Fail($message) { throw "[FAIL] $message" }

$deploy = Join-Path $Root "deploy.ps1"
$manifestFile = Join-Path $Root "assets\manifest.json"

if (-not (Test-Path $deploy)) { Fail "deploy.ps1 not found" }
if (-not (Test-Path $manifestFile)) { Fail "assets\manifest.json not found" }

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($deploy, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) {
    $message = ($errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
    Fail "PowerShell parse errors:`n$message"
}
Pass "deploy.ps1 parses"

$content = Get-Content $deploy -Raw -Encoding UTF8
if ($content -notmatch '\$VERSION\s*=\s*"([^"]+)"') { Fail "VERSION not found" }
$scriptVersion = $Matches[1]
$manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -ne $scriptVersion) {
    Fail "manifest version '$($manifest.version)' does not match script version '$scriptVersion'"
}
Pass "version sync: $scriptVersion"

foreach ($asset in $manifest.assets) {
    $path = Join-Path $Root "assets\$($asset.name)"
    if (-not (Test-Path $path)) {
        $path = Join-Path $Root "assets\claude-code-offline\$($asset.name)"
    }
    if (-not (Test-Path $path)) { Fail "missing asset: $($asset.name)" }
    $actual = (Get-FileHash -Algorithm SHA256 $path).Hash.ToUpperInvariant()
    $expected = ([string]$asset.sha256).ToUpperInvariant()
    if ($actual -ne $expected) { Fail "hash mismatch: $($asset.name)" }
}
Pass "manifest hashes match"

$trackedTextFiles = @(
    "deploy.ps1",
    "README.md",
    "CHANGELOG.md",
    "docs\roadmap.md",
    "docs\vm-test-notes.md",
    "assets\manifest.json"
)
foreach ($relative in $trackedTextFiles) {
    $path = Join-Path $Root $relative
    if ((Test-Path $path) -and (Get-Content $path -Raw -Encoding UTF8) -match 'sk-[A-Za-z0-9_\-]{12,}') {
        Fail "possible API key leaked in $relative"
    }
}
Pass "no obvious API keys in checked text files"

if ($content -notmatch 'Read-Host\s+"  API Key"\s+-AsSecureString') {
    Fail "API key prompt must use -AsSecureString"
}
if ($content -notmatch 'CLAUDE_CODE_GIT_BASH_PATH') {
    Fail "Git Bash path configuration missing"
}
if ($content -notmatch 'function\s+P6Verify' -or $content -notmatch 'Reply with exactly OK') {
    Fail "Claude/DeepSeek smoke verification phase missing"
}
Pass "required Windows hardening checks are present"

Write-Host "All package checks passed." -ForegroundColor Cyan

