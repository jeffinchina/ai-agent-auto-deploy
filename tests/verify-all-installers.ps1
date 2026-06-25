#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = "Stop"

function Pass($message) { Write-Host "[PASS] $message" -ForegroundColor Green }
function Fail($message) { throw "[FAIL] $message" }

$psFiles = @()
foreach ($relative in @("installers", "tools", "shared\vm")) {
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

$cursorInstaller = Join-Path $Root "installers\windows\cursor\install.ps1"
if (Test-Path $cursorInstaller) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cursorInstaller 2>&1
    if ($LASTEXITCODE -eq 0) {
        Fail "Cursor installer without an explicit mode should fail instead of reporting success"
    }
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $cursorInstaller -InstallDesktop -DryRun 2>&1
    if ($LASTEXITCODE -ne 0) {
        $tail = ($output | Select-Object -Last 20) -join "`n"
        Fail "Cursor installer -InstallDesktop dry-run should pass:`n$tail"
    }
    Pass "Cursor explicit-mode checks passed"
}

$mockVerifier = Join-Path $Root "tests\verify-windows-installer-mocks.ps1"
if (Test-Path $mockVerifier) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $mockVerifier -Root $Root 2>&1
    if ($LASTEXITCODE -ne 0) {
        $tail = ($output | Select-Object -Last 30) -join "`n"
        Fail "Windows installer mock verification failed:`n$tail"
    }
    Pass "Windows installer mock verification passed"
}

$ledgerPath = Join-Path $Root "docs\release-acceptance-ledger.json"
if (Test-Path $ledgerPath) {
    try {
        $ledger = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Fail "Release acceptance ledger is not valid JSON: $($_.Exception.Message)"
    }
    foreach ($key in @("claude-code-v3.2.3", "codex-v0.1.0", "openclaw-v0.1.0", "cursor-v0.1.0")) {
        if (-not $ledger.windows.$key) { Fail "Release acceptance ledger missing windows.$key" }
    }
    foreach ($key in @("claude-code-v0.1.0", "codex-v0.1.0", "openclaw-v0.1.0", "cursor-v0.1.0")) {
        if (-not $ledger.macos.$key) { Fail "Release acceptance ledger missing macos.$key" }
    }
    if ($ledger.windows."cursor-v0.1.0".conversation_smoke -notmatch "manual_gui_pending") {
        Fail "Cursor Windows conversation smoke must not be marked automated/pass until a real provider path is verified"
    }
    Pass "release acceptance ledger parses"
}

$buildScript = Join-Path $Root "tools\build-windows-agent-packages.ps1"
if (Test-Path $buildScript) {
    $tempDist = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-agent-auto-deploy-dist-" + [guid]::NewGuid().ToString("N"))
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Root $Root -OutputDir $tempDist 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tail = ($output | Select-Object -Last 20) -join "`n"
            Fail "Windows package build dry-run failed:`n$tail"
        }
        $manifestPath = Join-Path $tempDist "windows-agent-packages.json"
        if (-not (Test-Path $manifestPath)) { Fail "Windows package build missing manifest" }
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($agent in @("codex", "openclaw", "cursor")) {
            $folder = Join-Path $tempDist "$agent-windows-v0.1.0"
            if (-not (Test-Path (Join-Path $folder "install.ps1"))) {
                Fail "Windows package build missing install.ps1 for $agent"
            }
            if (-not (Test-Path (Join-Path $folder "README.md"))) {
                Fail "Windows package build missing README.md for $agent"
            }
            if (-not (Test-Path (Join-Path $folder "UPSTREAM-NOTES.md"))) {
                Fail "Windows package build missing UPSTREAM-NOTES.md for $agent"
            }
            if (-not (Test-Path (Join-Path $folder "run.cmd"))) {
                Fail "Windows package build missing run.cmd for $agent"
            }
            if (-not (Test-Path (Join-Path $folder "TEST-PLAN.md"))) {
                Fail "Windows package build missing TEST-PLAN.md for $agent"
            }
            $entry = $manifest.packages | Where-Object { $_.id -eq $agent } | Select-Object -First 1
            if (-not $entry) { Fail "Windows manifest missing $agent" }
            $zipPath = Join-Path $tempDist $entry.zip
            if (-not (Test-Path $zipPath)) { Fail "Windows package zip missing for $agent" }
            $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            if ($actualHash -ne $entry.sha256) { Fail "Windows package hash mismatch for $agent" }
            $extractDir = Join-Path $tempDist "extract-$agent"
            Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
            foreach ($required in @("install.ps1", "README.md", "UPSTREAM-NOTES.md", "run.cmd", "TEST-PLAN.md")) {
                if (-not (Test-Path (Join-Path $extractDir $required))) {
                    Fail "Windows zip for $agent missing $required"
                }
            }
        }
        Pass "Windows package build and zip verification passed"
    } finally {
        if (Test-Path $tempDist) {
            Remove-Item -LiteralPath $tempDist -Recurse -Force
        }
    }
}

$macosBuildScript = Join-Path $Root "tools\build-macos-agent-packages.ps1"
if (Test-Path $macosBuildScript) {
    $tempDist = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-agent-auto-deploy-macos-dist-" + [guid]::NewGuid().ToString("N"))
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $macosBuildScript -Root $Root -OutputDir $tempDist 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tail = ($output | Select-Object -Last 20) -join "`n"
            Fail "macOS package build dry-run failed:`n$tail"
        }
        $manifestPath = Join-Path $tempDist "macos-agent-packages.json"
        if (-not (Test-Path $manifestPath)) { Fail "macOS package build missing manifest" }
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($agent in @("claude-code", "codex", "openclaw", "cursor")) {
            $folder = Join-Path $tempDist "$agent-macos-v0.1.0"
            if (-not (Test-Path (Join-Path $folder "install.sh"))) {
                Fail "macOS package build missing install.sh for $agent"
            }
            if (-not (Test-Path (Join-Path $folder "TEST-PLAN.md"))) {
                Fail "macOS package build missing TEST-PLAN.md for $agent"
            }
            if (-not (Test-Path (Join-Path $folder "README.md"))) {
                Fail "macOS package build missing README.md for $agent"
            }
            $entry = $manifest.packages | Where-Object { $_.id -eq $agent } | Select-Object -First 1
            if (-not $entry) { Fail "macOS manifest missing $agent" }
            $zipPath = Join-Path $tempDist $entry.zip
            if (-not (Test-Path $zipPath)) { Fail "macOS package zip missing for $agent" }
            $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            if ($actualHash -ne $entry.sha256) { Fail "macOS package hash mismatch for $agent" }
            $extractDir = Join-Path $tempDist "extract-$agent"
            Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
            foreach ($required in @("install.sh", "README.md", "TEST-PLAN.md")) {
                if (-not (Test-Path (Join-Path $extractDir $required))) {
                    Fail "macOS zip for $agent missing $required"
                }
            }
        }
        Pass "macOS package build and zip verification passed"
    } finally {
        if (Test-Path $tempDist) {
            Remove-Item -LiteralPath $tempDist -Recurse -Force
        }
    }
}

$vmTestScript = Join-Path $Root "tools\run-windows-vm-agent-tests.ps1"
if (Test-Path $vmTestScript) {
    $tempShared = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-agent-auto-deploy-vm-shared-" + [guid]::NewGuid().ToString("N"))
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $vmTestScript -Root $Root -SharedDir $tempShared -PlanOnly 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tail = ($output | Select-Object -Last 20) -join "`n"
            Fail "Windows VM test plan generation failed:`n$tail"
        }
        $plans = Get-ChildItem -Path (Join-Path $tempShared "vm-results") -Recurse -Filter "PLAN.md" -ErrorAction SilentlyContinue
        if (-not $plans) { Fail "Windows VM test plan was not generated" }
        Pass "Windows VM test plan generation passed"
    } finally {
        if (Test-Path $tempShared) {
            Remove-Item -LiteralPath $tempShared -Recurse -Force
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

$scanRoots = @("installers", "shared", "docs", "tests", "tools", "config", ".github")
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
$rootFiles = Get-ChildItem -Path $Root -File | Where-Object { $_.Extension -in ".ps1",".cmd",".md",".json" }
foreach ($file in $rootFiles) {
    $text = Get-Content $file.FullName -Raw -Encoding UTF8
    if ($text -match 'sk-[A-Za-z0-9_\-]{12,}' -or $text -match '(?i)Bearer\s+sk-') {
        Fail "possible API key leaked in $($file.FullName)"
    }
}
Pass "no obvious API keys in installer text"

Write-Host "All installer checks passed." -ForegroundColor Cyan

