#Requires -Version 5.1
param(
    [string]$ResultsRoot = "D:\VMs\CCDeployTest\Shared\vm-results",
    [string]$OutputPath,
    [switch]$FailOnMissingGuestRuns,
    [switch]$FailOnPendingManualGates
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) { throw "[FAIL] $Message" }
function Sanitize([string]$Text) {
    if ($null -eq $Text) { return "" }
    return $Text -replace 'sk-[A-Za-z0-9_\-]+', 'sk-***' -replace '(?i)Bearer\s+[A-Za-z0-9_\-\.=]+', 'Bearer ***'
}
function Test-SecretLeak([string]$Text) {
    return ($Text -match 'sk-[A-Za-z0-9_\-]{12,}' -or $Text -match '(?i)Bearer\s+sk-[A-Za-z0-9_\-]+')
}

if (-not (Test-Path $ResultsRoot)) {
    if ($FailOnMissingGuestRuns) { Fail "VM results root does not exist: $ResultsRoot" }
    Write-Host "[WARN] VM results root does not exist: $ResultsRoot" -ForegroundColor Yellow
    exit 0
}

$guestRuns = Get-ChildItem -LiteralPath $ResultsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "guest-*" } |
    Sort-Object LastWriteTime

if (-not $guestRuns -or $guestRuns.Count -eq 0) {
    if ($FailOnMissingGuestRuns) { Fail "No guest-* VM acceptance result directories found under $ResultsRoot" }
    Write-Host "[WARN] No guest-* VM acceptance result directories found under $ResultsRoot" -ForegroundColor Yellow
}

$report = [ordered]@{
    schemaVersion = 1
    scannedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    resultsRoot = $ResultsRoot
    guestRunCount = @($guestRuns).Count
    runs = @()
    secretLeaks = @()
    pendingManualGates = @()
}

foreach ($run in $guestRuns) {
    $summaryPath = Join-Path $run.FullName "SUMMARY.md"
    $transcriptPath = Join-Path $run.FullName "transcript.txt"
    $files = Get-ChildItem -LiteralPath $run.FullName -File -Recurse -ErrorAction SilentlyContinue

    $leaks = @()
    foreach ($file in $files) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (Test-SecretLeak $text) {
            $leaks += $file.FullName
            $report.secretLeaks += $file.FullName
        }
    }

    $summary = ""
    if (Test-Path $summaryPath) {
        $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
    }

    $passCount = ([regex]::Matches($summary, '(?m)^- PASS:')).Count
    $failCount = ([regex]::Matches($summary, '(?m)^- FAIL:')).Count
    $pendingCount = ([regex]::Matches($summary, '(?m)^- PENDING:')).Count
    if ($pendingCount -gt 0) { $report.pendingManualGates += $run.FullName }

    $agents = @()
    foreach ($agent in @("Codex", "OpenClaw", "Cursor")) {
        if ($summary -match "##\s+$agent" -or $summary -match "##\s+$($agent.ToLowerInvariant())") {
            $agents += $agent.ToLowerInvariant()
        }
    }

    $report.runs += [ordered]@{
        name = $run.Name
        path = $run.FullName
        lastWriteTime = $run.LastWriteTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        hasSummary = (Test-Path $summaryPath)
        hasTranscript = (Test-Path $transcriptPath)
        agents = $agents
        passCount = $passCount
        failCount = $failCount
        pendingManualGateCount = $pendingCount
        secretLeakCount = @($leaks).Count
        status = if ($leaks.Count -gt 0) {
            "secret_leak"
        } elseif ($failCount -gt 0) {
            "failed"
        } elseif ($pendingCount -gt 0) {
            "partial_manual_pending"
        } elseif ($passCount -gt 0) {
            "pass"
        } else {
            "unknown"
        }
    }
}

if ($report.secretLeaks.Count -gt 0) {
    $message = "Potential secret leaks found in VM result files:`n" + (($report.secretLeaks | ForEach-Object { "- $_" }) -join "`n")
    Fail $message
}
if ($FailOnPendingManualGates -and $report.pendingManualGates.Count -gt 0) {
    $message = "Pending manual gates remain in VM result directories:`n" + (($report.pendingManualGates | ForEach-Object { "- $_" }) -join "`n")
    Fail $message
}

$json = $report | ConvertTo-Json -Depth 8
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
}

Write-Host $json
