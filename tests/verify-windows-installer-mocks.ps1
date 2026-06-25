#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = "Stop"

function Pass($message) { Write-Host "[PASS] $message" -ForegroundColor Green }
function Fail($message) { throw "[FAIL] $message" }

function Write-Cmd([string]$Dir, [string]$Name, [string]$Body) {
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    $path = Join-Path $Dir "$Name.cmd"
    Set-Content -LiteralPath $path -Value $Body -Encoding ASCII
    return $path
}

function Invoke-Installer([string]$Installer, [string[]]$InstallerArgs, [string]$MockBin) {
    $oldPath = $env:Path
    try {
        $env:Path = "$MockBin;$oldPath"
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Installer @InstallerArgs 2>&1
        return @{ ExitCode = $LASTEXITCODE; Output = $output }
    } finally {
        $env:Path = $oldPath
    }
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-agent-auto-deploy-mocks-" + [guid]::NewGuid().ToString("N"))
try {
    $mockBin = Join-Path $temp "bin"

    Write-Cmd $mockBin "codex" @"
@echo off
if "%1"=="--version" (
  echo codex 0.0.0-test
  exit /b 0
)
if "%1"=="doctor" (
  echo doctor ok
  exit /b 0
)
echo codex mock
exit /b 0
"@ | Out-Null

    Write-Cmd $mockBin "openclaw" @"
@echo off
if "%1"=="--version" (
  echo openclaw 0.0.0-test
  exit /b 0
)
if "%1"=="onboard" (
  echo onboard ok
  exit /b 0
)
if "%1"=="models" (
  if "%2"=="list" (
    echo deepseek/deepseek-v4-pro
    exit /b 0
  )
  if "%2"=="set" (
    echo model set
    exit /b 0
  )
)
if "%1"=="infer" (
  echo OK
  exit /b 0
)
echo openclaw mock
exit /b 0
"@ | Out-Null

    Write-Cmd $mockBin "cursor-agent" @"
@echo off
if "%1"=="--version" (
  echo cursor-agent 0.0.0-test
  exit /b 0
)
echo cursor-agent mock
exit /b 0
"@ | Out-Null

    $codex = Invoke-Installer (Join-Path $Root "installers\windows\codex\install.ps1") @("-VerifyOnly", "-SkipLoginHint") $mockBin
    if ($codex.ExitCode -ne 0) { Fail "Codex VerifyOnly failed with mock command:`n$($codex.Output -join "`n")" }

    $oldLocalAppData = $env:LOCALAPPDATA
    $oldUserProfile = $env:USERPROFILE
    try {
        $env:LOCALAPPDATA = Join-Path $temp "localappdata"
        $env:USERPROFILE = Join-Path $temp "userprofile"
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA,$env:USERPROFILE -Force | Out-Null
        $codexBridge = Invoke-Installer (Join-Path $Root "installers\windows\codex\install.ps1") @("-VerifyOnly", "-SkipLoginHint", "-PrepareDeepSeekLiteLLM") $mockBin
        if ($codexBridge.ExitCode -ne 0) { Fail "Codex LiteLLM bridge config failed:`n$($codexBridge.Output -join "`n")" }
        $codexToml = Join-Path $env:USERPROFILE ".codex\config.toml"
        $liteLlmYaml = Join-Path $env:LOCALAPPDATA "CodexDeepSeekLiteLLM\litellm-config.yaml"
        if (-not (Test-Path $codexToml)) { Fail "Codex LiteLLM bridge did not write config.toml" }
        if (-not (Test-Path $liteLlmYaml)) { Fail "Codex LiteLLM bridge did not write litellm-config.yaml" }
        $codexText = Get-Content -LiteralPath $codexToml -Raw -Encoding UTF8
        $liteText = Get-Content -LiteralPath $liteLlmYaml -Raw -Encoding UTF8
        if ($codexText -notmatch 'wire_api = "responses"') { Fail "Codex config missing responses wire_api" }
        if ($codexText -notmatch 'env_key = "CODEX_LITELLM_API_KEY"') { Fail "Codex config missing proxy env key" }
        if ($liteText -notmatch 'api_key: os.environ/DEEPSEEK_API_KEY') { Fail "LiteLLM config should reference DEEPSEEK_API_KEY env var" }
        if ($codexText -match 'sk-[A-Za-z0-9_\-]{12,}' -or $liteText -match 'sk-[A-Za-z0-9_\-]{12,}') { Fail "Codex LiteLLM bridge wrote a real-looking API key" }
    } finally {
        $env:LOCALAPPDATA = $oldLocalAppData
        $env:USERPROFILE = $oldUserProfile
    }

    $openclaw = Invoke-Installer (Join-Path $Root "installers\windows\openclaw\install.ps1") @("-VerifyOnly") $mockBin
    if ($openclaw.ExitCode -ne 0) { Fail "OpenClaw VerifyOnly failed with mock command:`n$($openclaw.Output -join "`n")" }

    $oldDeepSeekKey = $env:DEEPSEEK_API_KEY
    try {
        $env:DEEPSEEK_API_KEY = "sk-test"
        $openclawDeepSeek = Invoke-Installer (Join-Path $Root "installers\windows\openclaw\install.ps1") @("-VerifyOnly", "-ConfigureDeepSeek", "-RunDeepSeekSmoke") $mockBin
        if ($openclawDeepSeek.ExitCode -ne 0) { Fail "OpenClaw DeepSeek mock smoke failed:`n$($openclawDeepSeek.Output -join "`n")" }
    } finally {
        $env:DEEPSEEK_API_KEY = $oldDeepSeekKey
    }

    $cursor = Invoke-Installer (Join-Path $Root "installers\windows\cursor\install.ps1") @("-VerifyOnly") $mockBin
    if ($cursor.ExitCode -ne 0) { Fail "Cursor VerifyOnly failed with mock command:`n$($cursor.Output -join "`n")" }

    Pass "Windows installer VerifyOnly success paths passed"

    Remove-Item -LiteralPath (Join-Path $mockBin "cursor-agent.cmd") -Force
    $cursorMissing = Invoke-Installer (Join-Path $Root "installers\windows\cursor\install.ps1") @("-VerifyOnly") $mockBin
    if ($cursorMissing.ExitCode -eq 0) { Fail "Cursor VerifyOnly should fail when cursor-agent is missing" }

    Write-Cmd $mockBin "openclaw" @"
@echo off
if "%1"=="--version" (
  echo openclaw version failed
  exit /b 7
)
exit /b 7
"@ | Out-Null
    $openclawBad = Invoke-Installer (Join-Path $Root "installers\windows\openclaw\install.ps1") @("-VerifyOnly") $mockBin
    if ($openclawBad.ExitCode -eq 0) { Fail "OpenClaw VerifyOnly should fail when --version fails" }

    Pass "Windows installer VerifyOnly failure paths passed"
} finally {
    if (Test-Path $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
