#Requires -Version 5.1
param(
    [ValidateSet("windows", "macos")]
    [string]$Platform,
    [ValidateSet("claude-code", "codex", "openclaw", "cursor")]
    [string]$Agent,
    [string]$Repo = "jeffinchina/ai-agent-auto-deploy",
    [string]$Workflow = "Installer static checks",
    [switch]$Watch,
    [switch]$SkipSecretCheck
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) { throw "[FAIL] $Message" }

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Fail "GitHub CLI (gh) is required. Install gh and run 'gh auth login' first."
}

if ($Agent -eq "cursor") {
    Fail "Cursor DeepSeek smoke is a GUI/manual gate and is not implemented as hosted CLI smoke."
}
if ($Platform -eq "windows" -and $Agent -eq "claude-code") {
    Fail "Claude Code Windows v3.2.3 is validated through the local clean-base VM/offline package path, not this hosted wrapper workflow."
}

if (-not $SkipSecretCheck) {
    $secretList = & $gh.Source secret list --repo $Repo 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "Could not list GitHub secrets. Run 'gh auth login' or retry. Output: $($secretList -join ' ')"
    }
    $hasSecret = $secretList | Where-Object { $_ -match '^DEEPSEEK_API_KEY\s' }
    if (-not $hasSecret) {
        Fail "Repository secret DEEPSEEK_API_KEY is missing. Run tools\set-github-deepseek-secret.ps1 first."
    }
}

$windowsAgent = "none"
$macosAgent = "none"
if ($Platform -eq "windows") { $windowsAgent = $Agent }
if ($Platform -eq "macos") { $macosAgent = $Agent }

$runOutput = & $gh.Source workflow run $Workflow `
    --repo $Repo `
    -f "windows_smoke_agent=$windowsAgent" `
    -f "macos_smoke_agent=$macosAgent" `
    -f "deepseek_smoke=true" 2>&1
if ($LASTEXITCODE -ne 0) {
    Fail "Could not dispatch workflow. Output: $($runOutput -join ' ')"
}

Write-Host "[OK] Dispatched hosted DeepSeek smoke: $Platform / $Agent" -ForegroundColor Green
if ($runOutput) { $runOutput | ForEach-Object { Write-Host $_ } }

if ($Watch) {
    Start-Sleep -Seconds 5
    $runs = & $gh.Source run list --repo $Repo --workflow $Workflow --limit 1 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "Could not find dispatched run. Output: $($runs -join ' ')" }
    $first = ($runs | Select-Object -First 1)
    $parts = $first -split '\t'
    $runId = $parts | Where-Object { $_ -match '^\d{8,}$' } | Select-Object -First 1
    if (-not $runId) {
        Write-Host "[WARN] Could not parse run id from gh output. Latest run line:" -ForegroundColor Yellow
        Write-Host $first
        exit 0
    }
    & $gh.Source run watch $runId --repo $Repo --exit-status
}
