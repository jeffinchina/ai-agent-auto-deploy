#Requires -Version 5.1
param(
    [ValidateSet("all", "codex", "openclaw", "cursor")]
    [string]$Agent = "all",
    [string]$PackageRoot = "\\VBOXSVR\CCDeployPackage",
    [string]$ResultsRoot = "\\VBOXSVR\CCDeployPackage\vm-results",
    [switch]$RunProviderGate,
    [switch]$InstallLiteLLMProxy,
    [switch]$SkipInstall,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

$agents = @("codex", "openclaw", "cursor")
if ($Agent -ne "all") { $agents = @($Agent) }

$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$resultDir = Join-Path $ResultsRoot "guest-$runId"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$transcriptPath = Join-Path $resultDir "transcript.txt"
$summaryPath = Join-Path $resultDir "SUMMARY.md"
$manualGates = New-Object System.Collections.Generic.List[string]

function Sanitize([string]$Text) {
    if ($null -eq $Text) { return "" }
    return $Text -replace 'sk-[A-Za-z0-9_\-]+', 'sk-***' -replace '(?i)Bearer\s+[A-Za-z0-9_\-\.=]+', 'Bearer ***'
}

function Write-Summary([string]$Line) {
    Add-Content -LiteralPath $summaryPath -Value (Sanitize $Line) -Encoding UTF8
}

function Refresh-ProcessPath {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($scope in @("Machine", "User")) {
        $value = [Environment]::GetEnvironmentVariable("Path", $scope)
        if ($value) {
            foreach ($part in ($value -split ';')) {
                if ($part -and -not $parts.Contains($part)) { $parts.Add($part) }
            }
        }
    }
    foreach ($part in ($env:Path -split ';')) {
        if ($part -and -not $parts.Contains($part)) { $parts.Add($part) }
    }
    foreach ($part in @(
        "$env:LOCALAPPDATA\Programs\codex\bin",
        "$env:LOCALAPPDATA\Codex\bin",
        "$env:USERPROFILE\.codex\bin",
        "$env:USERPROFILE\.local\bin",
        "$env:APPDATA\npm",
        "$env:LOCALAPPDATA\Programs\Cursor",
        "$env:LOCALAPPDATA\Programs\cursor"
    )) {
        if ((Test-Path $part) -and -not $parts.Contains($part)) { $parts.Add($part) }
    }
    if ($env:APPDATA) {
        $pythonRoot = Join-Path $env:APPDATA "Python"
        if (Test-Path $pythonRoot) {
            Get-ChildItem -LiteralPath $pythonRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $scripts = Join-Path $_.FullName "Scripts"
                if ((Test-Path $scripts) -and -not $parts.Contains($scripts)) { $parts.Add($scripts) }
            }
        }
    }
    $env:Path = ($parts -join ';')
}

function Invoke-Step([string]$Name, [scriptblock]$Block) {
    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    Write-Summary "- START: $Name"
    try {
        & $Block
        Write-Summary "- PASS: $Name"
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } catch {
        Write-Summary "- FAIL: $Name"
        Write-Summary "  - Error: $($_.Exception.Message)"
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        throw
    }
}

function Invoke-PackageCommand([string]$PackageDir, [string[]]$Arguments) {
    $script = Join-Path $PackageDir "install.ps1"
    if (-not (Test-Path $script)) { throw "Missing installer: $script" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Installer failed with exit code ${LASTEXITCODE}: $script $($Arguments -join ' ')" }
}

function Require-DeepSeekKey {
    if ($env:DEEPSEEK_API_KEY) {
        if ($env:DEEPSEEK_API_KEY -notlike "sk-*") { throw "DEEPSEEK_API_KEY must start with sk-." }
        return
    }

    Write-Host ""
    Write-Host "DeepSeek API Key input is hidden and only stored in this PowerShell process." -ForegroundColor Yellow
    $secure = Read-Host "DeepSeek API Key" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    if (-not $plain -or $plain -notlike "sk-*") { throw "DeepSeek API Key must start with sk-." }
    $env:DEEPSEEK_API_KEY = $plain
}

function Test-CodexDeepSeek([string]$PackageDir) {
    Require-DeepSeekKey
    $args = @("-VerifyOnly", "-SkipLoginHint", "-PrepareDeepSeekLiteLLM")
    if ($InstallLiteLLMProxy) { $args += "-InstallLiteLLMProxy" }
    Invoke-PackageCommand $PackageDir $args
    Refresh-ProcessPath
    $env:CODEX_LITELLM_API_KEY = "sk-local-codex"

    $startScript = Join-Path $env:LOCALAPPDATA "CodexDeepSeekLiteLLM\start-litellm-deepseek.ps1"
    if (-not (Test-Path $startScript)) { throw "Missing LiteLLM start script: $startScript" }

    $proxyLog = Join-Path $resultDir "codex-litellm-proxy.out.log"
    $proxyErr = Join-Path $resultDir "codex-litellm-proxy.err.log"
    $proxy = Start-Process powershell -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $startScript
    ) -WindowStyle Hidden -RedirectStandardOutput $proxyLog -RedirectStandardError $proxyErr -PassThru

    try {
        $healthy = $false
        foreach ($i in 1..20) {
            Start-Sleep -Seconds 2
            try {
                Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:4000/health" -TimeoutSec 5 | Out-Null
                $healthy = $true
                break
            } catch {
                if ($proxy.HasExited) { break }
            }
        }
        if (-not $healthy) { throw "LiteLLM proxy did not become healthy. See $proxyLog and $proxyErr" }

        Refresh-ProcessPath
        $codex = Get-Command codex -ErrorAction SilentlyContinue
        if (-not $codex) { throw "codex command not found after install." }
        $output = & $codex.Source exec --ephemeral "Reply with exactly OK" 2>&1
        $safeOutput = Sanitize (($output | Out-String).Trim())
        Set-Content -LiteralPath (Join-Path $resultDir "codex-deepseek-output.txt") -Value $safeOutput -Encoding UTF8
        if ($LASTEXITCODE -ne 0) { throw "codex exec failed with exit code $LASTEXITCODE" }
        if ($safeOutput -notmatch "\bOK\b") { throw "codex DeepSeek smoke did not return OK." }
    } finally {
        if ($proxy -and -not $proxy.HasExited) { Stop-Process -Id $proxy.Id -Force -ErrorAction SilentlyContinue }
        foreach ($logPath in @($proxyLog, $proxyErr)) {
            if (Test-Path $logPath) {
                $text = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
                Set-Content -LiteralPath $logPath -Value (Sanitize $text) -Encoding UTF8
            }
        }
    }
}

function Test-CursorManualGate {
    $script:manualGates.Add("Cursor DeepSeek provider/conversation gate requires GUI/manual verification.")
    Write-Summary "- MANUAL: Cursor DeepSeek provider/conversation gate"
    Write-Summary "  - Cursor Windows package installs/verifies desktop app only."
    Write-Summary "  - Complete provider setup in the Cursor GUI if supported, send one minimal prompt, and save a sanitized screenshot/output."
    Write-Host "Cursor DeepSeek conversation is a GUI/manual gate in this package." -ForegroundColor Yellow
}

Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
try {
    Set-Content -LiteralPath $summaryPath -Value "# Windows Agent VM Acceptance $runId`n" -Encoding UTF8
    Write-Summary "- Computer: $env:COMPUTERNAME"
    Write-Summary "- User: $env:USERNAME"
    Write-Summary "- Package root: $PackageRoot"
    Write-Summary "- Provider gate requested: $RunProviderGate"
    if ($Agent -eq "all") {
        Write-Summary "- Isolation note: this run covers multiple packages in one VM session. Release-level evidence still requires restoring clean-base and running each agent separately."
        Write-Host "Release-level evidence requires restoring clean-base and running each agent separately." -ForegroundColor Yellow
    }
    Write-Summary ""

    foreach ($agentId in $agents) {
        $packageDir = Join-Path $PackageRoot "$agentId-windows-v0.1.0"
        if (-not (Test-Path $packageDir)) { throw "Missing package folder: $packageDir" }
        Write-Summary "## $agentId"

        switch ($agentId) {
            "codex" {
                Invoke-Step "Codex dry-run" { Invoke-PackageCommand $packageDir @("-DryRun") }
                if (-not $SkipInstall) { Invoke-Step "Codex install" { Invoke-PackageCommand $packageDir @("-SkipLoginHint") } }
                Invoke-Step "Codex verify" {
                    Refresh-ProcessPath
                    $cmd = Get-Command codex -ErrorAction Stop
                    & $cmd.Source --version
                    if ($LASTEXITCODE -ne 0) { throw "codex --version failed" }
                    & $cmd.Source doctor
                    if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] codex doctor returned non-zero" -ForegroundColor Yellow }
                }
                if ($RunProviderGate) { Invoke-Step "Codex DeepSeek conversation smoke" { Test-CodexDeepSeek $packageDir } }
            }
            "openclaw" {
                Invoke-Step "OpenClaw dry-run" { Invoke-PackageCommand $packageDir @("-DryRun") }
                if (-not $SkipInstall) { Invoke-Step "OpenClaw install" { Invoke-PackageCommand $packageDir @() } }
                Invoke-Step "OpenClaw verify" {
                    Refresh-ProcessPath
                    $cmd = Get-Command openclaw -ErrorAction Stop
                    & $cmd.Source --version
                    if ($LASTEXITCODE -ne 0) { throw "openclaw --version failed" }
                }
                if ($RunProviderGate) {
                    Invoke-Step "OpenClaw DeepSeek provider and conversation smoke" {
                        Require-DeepSeekKey
                        Invoke-PackageCommand $packageDir @("-VerifyOnly", "-ConfigureDeepSeek", "-RunDeepSeekSmoke")
                    }
                }
            }
            "cursor" {
                Invoke-Step "Cursor dry-run" { Invoke-PackageCommand $packageDir @("-InstallDesktop", "-DryRun") }
                if (-not $SkipInstall) { Invoke-Step "Cursor desktop install" { Invoke-PackageCommand $packageDir @("-InstallDesktop") } }
                Invoke-Step "Cursor desktop verify" { Invoke-PackageCommand $packageDir @("-VerifyOnly", "-InstallDesktop") }
                if ($RunProviderGate) { Test-CursorManualGate }
            }
        }
        Write-Summary ""
    }

    Write-Summary "## Result"
    if ($manualGates.Count -gt 0) {
        Write-Summary "Automated gates passed for commands that ran. Manual gates remain pending:"
        foreach ($gate in $manualGates) { Write-Summary "- PENDING: $gate" }
    } else {
        Write-Summary "PASS for automated gates that ran."
    }
    Write-Host ""
    Write-Host "Acceptance run complete: $resultDir" -ForegroundColor Green
} finally {
    Remove-Item Env:\DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    $text = Get-Content -LiteralPath $transcriptPath -Raw -Encoding UTF8
    Set-Content -LiteralPath $transcriptPath -Value (Sanitize $text) -Encoding UTF8
    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}
