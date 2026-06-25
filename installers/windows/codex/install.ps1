#Requires -Version 5.1
param(
    [string]$Release = "latest",
    [string]$DeepSeekModel = "deepseek-v4-pro",
    [string]$LiteLLMBackendModel = "deepseek/deepseek-chat",
    [int]$LiteLLMPort = 4000,
    [switch]$InstallDesktopApp,
    [switch]$PrepareDeepSeekLiteLLM,
    [switch]$InstallLiteLLMProxy,
    [switch]$SkipLoginHint,
    [switch]$VerifyOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$VERSION = "0.1.0"
$LOGDIR = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $LOGDIR -Force | Out-Null
$LOGFILE = Join-Path $LOGDIR "codex-windows-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$PID.log"

function Sanitize($s) {
    if ($null -eq $s) { return "" }
    return ([string]$s) -replace 'sk-[A-Za-z0-9_\-]+', 'sk-***' -replace '(?i)Bearer\s+[A-Za-z0-9_\-\.=]+', 'Bearer ***'
}
function Log($m) { Add-Content $LOGFILE "[$(Get-Date -Format 'HH:mm:ss')] $(Sanitize $m)" -Encoding UTF8 }
function Say($c,$m) { Write-Host $m -ForegroundColor $c; Log $m }
function Ok($m) { Say Green "[OK] $m" }
function Info($m) { Say Gray "[INFO] $m" }
function Warn($m) { Say Yellow "[WARN] $m" }
function Fail($m,$hint) { Say Red "[ERR] $m"; if($hint){ Info "建议: $hint" }; Info "日志: $LOGFILE"; exit 1 }

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
    $common = @(
        "$env:LOCALAPPDATA\Programs\codex\bin",
        "$env:LOCALAPPDATA\Codex\bin",
        "$env:USERPROFILE\.codex\bin",
        "$env:USERPROFILE\.local\bin"
    )
    if ($env:APPDATA) {
        $pythonRoot = Join-Path $env:APPDATA "Python"
        if (Test-Path $pythonRoot) {
            Get-ChildItem -LiteralPath $pythonRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $scripts = Join-Path $_.FullName "Scripts"
                if (Test-Path $scripts) { $common += $scripts }
            }
        }
    }
    foreach ($part in $common) {
        if ((Test-Path $part) -and -not $parts.Contains($part)) { $parts.Add($part) }
    }
    $env:Path = ($parts -join ';')
}

function Invoke-Captured($file, [string[]]$arguments, [int]$timeoutSec = 120) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = ($arguments | ForEach-Object {
        $a = [string]$_
        if ($a -match '[\s"]') { '"' + ($a -replace '"','\"') + '"' } else { $a }
    }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $done = $p.WaitForExit($timeoutSec * 1000)
    if(-not $done){ try { $p.Kill() } catch {}; return @{ ExitCode = 124; StdOut = ""; StdErr = "timeout" } }
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; StdOut = Sanitize $outTask.Result; StdErr = Sanitize $errTask.Result }
}

function Get-PythonInvoker {
    Refresh-ProcessPath
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $version = Invoke-Captured $python.Source @("--version") 30
        if ($version.ExitCode -eq 0 -and (Test-PythonVersionText $version.StdOut)) {
            return @{ File = $python.Source; PrefixArgs = @() }
        }
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        $version = Invoke-Captured $py.Source @("-3", "--version") 30
        if ($version.ExitCode -eq 0 -and (Test-PythonVersionText $version.StdOut)) {
            return @{ File = $py.Source; PrefixArgs = @("-3") }
        }
    }

    return $null
}

function Test-PythonVersionText([string]$Text) {
    if ($Text -match 'Python\s+(\d+)\.(\d+)\.') {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        return ($major -gt 3 -or ($major -eq 3 -and $minor -ge 10))
    }
    return $false
}

function Ensure-PythonForLiteLLM {
    $invoker = Get-PythonInvoker
    if ($invoker) { return $invoker }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Fail "未找到 Python" "Codex + DeepSeek LiteLLM bridge 需要 Python 3.10+；请先安装 Python，或安装 Windows Package Manager 后重试。"
    }

    Info "未检测到 Python 3，正在通过 winget 安装 Python 3.12..."
    $install = Invoke-Captured $winget.Source @(
        "install",
        "--id", "Python.Python.3.12",
        "--exact",
        "--source", "winget",
        "--scope", "user",
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements"
    ) 900
    Log $install.StdOut
    Log $install.StdErr
    if ($install.ExitCode -ne 0) {
        Fail "Python 3.12 安装失败" "请检查 winget 输出，或手动安装 Python 3.10+ 后重试 -InstallLiteLLMProxy。"
    }

    Refresh-ProcessPath
    $invoker = Get-PythonInvoker
    if (-not $invoker) {
        Fail "Python 安装后仍不可用" "请打开新 PowerShell 后重试，或检查 Python 是否加入 PATH。"
    }
    Ok "Python 可用"
    return $invoker
}

function Remove-TomlSection([string[]]$Lines, [string]$SectionName) {
    $result = New-Object System.Collections.Generic.List[string]
    $sectionHeader = "[$SectionName]"
    $skip = $false
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -ieq $sectionHeader) {
            $skip = $true
            continue
        }
        if ($skip -and $trimmed.StartsWith("[") -and $trimmed.EndsWith("]")) {
            $skip = $false
        }
        if (-not $skip) { $result.Add($line) }
    }
    return $result.ToArray()
}

function Set-CodexTopLevelConfig([string[]]$Lines, [string]$Model, [string]$Provider) {
    $result = New-Object System.Collections.Generic.List[string]
    $inserted = $false
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        $isTopLevelModel = (-not $inserted) -and ($trimmed -match '^(model|model_provider)\s*=')
        if ($isTopLevelModel) { continue }
        if (-not $inserted -and $trimmed.StartsWith("[") -and $trimmed.EndsWith("]")) {
            $result.Add(('model = "{0}"' -f $Model))
            $result.Add(('model_provider = "{0}"' -f $Provider))
            $result.Add("")
            $inserted = $true
        }
        $result.Add($line)
    }
    if (-not $inserted) {
        $result.Insert(0, "")
        $result.Insert(0, ('model_provider = "{0}"' -f $Provider))
        $result.Insert(0, ('model = "{0}"' -f $Model))
    }
    return $result.ToArray()
}

function Preflight {
    Say Cyan "Codex Windows Installer v$VERSION"
    if ([Environment]::OSVersion.Platform -ne "Win32NT") { Fail "当前脚本仅支持 Windows" "请使用 Windows 10/11。" }
    if (-not [Environment]::Is64BitOperatingSystem) { Fail "不支持 32 位 Windows" "请换用 64 位 Windows。" }
    Ok "Windows 64 位"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($InstallDesktopApp -and -not $DryRun -and -not $winget) { Fail "未找到 winget" "安装 Codex 桌面 App 需要 Windows Package Manager。" }
    Ok "安装前检测完成"
}

function Install-CodexCli {
    if ($VerifyOnly) {
        Info "VerifyOnly: 跳过 Codex CLI 安装"
        return
    }
    if ($DryRun) {
        Info "DryRun: 跳过 Codex CLI 下载与安装"
        return
    }
    $existing = Get-Command codex -ErrorAction SilentlyContinue
    if ($existing) {
        Info "检测到 codex: $($existing.Source)"
        return
    }

    Info "下载 OpenAI 官方 Codex CLI 安装脚本..."
    $installScript = Join-Path $env:TEMP "codex-install.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "https://chatgpt.com/codex/install.ps1" -OutFile $installScript -TimeoutSec 120
    $env:CODEX_NON_INTERACTIVE = "1"
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $installScript)
    if ($Release -and $Release -ne "latest") { $args += @("-Release", $Release) }
    $r = Invoke-Captured "powershell.exe" $args 300
    Log $r.StdOut
    Log $r.StdErr
    Remove-Item $installScript -Force -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) { Fail "Codex CLI 安装失败" "请检查网络，或手动运行官方安装命令。" }
    Ok "Codex CLI 安装完成"
}

function Install-CodexDesktop {
    if (-not $InstallDesktopApp) { return }
    if ($VerifyOnly) {
        Info "VerifyOnly: 跳过 Codex 桌面 App 安装"
        return
    }
    if ($DryRun) {
        Info "DryRun: 跳过 Codex 桌面 App 安装"
        return
    }
    Info "安装 Codex 桌面 App..."
    $r = Invoke-Captured "winget.exe" @("install", "Codex", "-s", "msstore", "--accept-package-agreements", "--accept-source-agreements") 600
    Log $r.StdOut
    Log $r.StdErr
    if ($r.ExitCode -ne 0) { Warn "Codex 桌面 App 安装未确认成功，可稍后手动运行 winget install Codex -s msstore" }
    else { Ok "Codex 桌面 App 安装完成" }
}

function Verify {
    if ($DryRun) {
        Info "DryRun: 跳过 codex --version 和 codex doctor"
        Ok "Codex Windows dry-run 通过"
        return
    }
    Refresh-ProcessPath
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $cmd) { Fail "未找到 codex 命令" "请重新打开终端，或检查安装脚本输出。" }
    $ver = Invoke-Captured $cmd.Source @("--version") 60
    Log $ver.StdOut
    Log $ver.StdErr
    if ($ver.ExitCode -ne 0) { Fail "codex --version 验证失败" "请查看日志。" }
    Ok "codex 可用: $($ver.StdOut.Trim())"

    $doctor = Invoke-Captured $cmd.Source @("doctor") 120
    Log $doctor.StdOut
    Log $doctor.StdErr
    if ($doctor.ExitCode -ne 0) { Warn "codex doctor 返回非 0，可能需要登录或修复本机环境" }
    else { Ok "codex doctor 通过" }

    if (-not $SkipLoginHint) {
        Info "首次使用请运行: codex login"
        Info "ChatGPT 登录是默认路径；API key 登录适合 CI/自动化场景。"
    }
}

function Write-CodexLiteLLMBridge {
    if (-not $PrepareDeepSeekLiteLLM -and -not $InstallLiteLLMProxy) {
        return
    }
    if ($DryRun) {
        Info "DryRun: 跳过 Codex LiteLLM DeepSeek bridge 配置"
        return
    }

    $bridgeDir = Join-Path $env:LOCALAPPDATA "CodexDeepSeekLiteLLM"
    New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null

    $liteLlmConfig = Join-Path $bridgeDir "litellm-config.yaml"
    $yaml = @"
model_list:
  - model_name: $DeepSeekModel
    litellm_params:
      model: $LiteLLMBackendModel
      api_key: os.environ/DEEPSEEK_API_KEY
"@
    Set-Content -LiteralPath $liteLlmConfig -Value $yaml -Encoding UTF8

    $startScript = Join-Path $bridgeDir "start-litellm-deepseek.ps1"
$startContent = @"
`$ErrorActionPreference = "Stop"
if (-not `$env:DEEPSEEK_API_KEY -or `$env:DEEPSEEK_API_KEY -notlike "sk-*") {
    throw "Set DEEPSEEK_API_KEY in this terminal before starting LiteLLM."
}
if (-not `$env:CODEX_LITELLM_API_KEY) {
    `$env:CODEX_LITELLM_API_KEY = "sk-local-codex"
}
`$litellm = Get-Command litellm -ErrorAction SilentlyContinue
if (`$litellm) {
    & `$litellm.Source --config "$liteLlmConfig" --host 127.0.0.1 --port $LiteLLMPort
    exit `$LASTEXITCODE
}
`$python = Get-Command python -ErrorAction SilentlyContinue
if (`$python) {
    & `$python.Source -m litellm --config "$liteLlmConfig" --host 127.0.0.1 --port $LiteLLMPort
    exit `$LASTEXITCODE
}
`$py = Get-Command py -ErrorAction SilentlyContinue
if (`$py) {
    & `$py.Source -3 -m litellm --config "$liteLlmConfig" --host 127.0.0.1 --port $LiteLLMPort
    exit `$LASTEXITCODE
}
throw "litellm command not found. Install LiteLLM proxy first."
"@
    Set-Content -LiteralPath $startScript -Value $startContent -Encoding UTF8

    $codexDir = Join-Path $env:USERPROFILE ".codex"
    $codexConfig = Join-Path $codexDir "config.toml"
    New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
    $lines = @()
    if (Test-Path $codexConfig) {
        $backup = "$codexConfig.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $codexConfig -Destination $backup -Force
        Info "已备份 Codex 配置: $backup"
        $lines = Get-Content -LiteralPath $codexConfig -Encoding UTF8
    }
    $providerName = "litellm-deepseek"
    $lines = Remove-TomlSection $lines "model_providers.$providerName"
    $lines = Set-CodexTopLevelConfig $lines $DeepSeekModel $providerName
    $providerBlock = @(
        "",
        "[model_providers.$providerName]",
        'name = "LiteLLM DeepSeek bridge"',
        ('base_url = "http://127.0.0.1:{0}/v1"' -f $LiteLLMPort),
        'env_key = "CODEX_LITELLM_API_KEY"',
        'wire_api = "responses"'
    )
    Set-Content -LiteralPath $codexConfig -Value ($lines + $providerBlock) -Encoding UTF8

    [Environment]::SetEnvironmentVariable("CODEX_LITELLM_API_KEY", "sk-local-codex", "User")
    $env:CODEX_LITELLM_API_KEY = "sk-local-codex"
    Ok "Codex LiteLLM DeepSeek bridge 配置已写入"
    Info "LiteLLM 配置: $liteLlmConfig"
    Info "启动脚本: $startScript"
    Info "使用前请在单独 PowerShell 中设置 DEEPSEEK_API_KEY 后运行启动脚本。"

    if ($InstallLiteLLMProxy) {
        $python = Ensure-PythonForLiteLLM
        Info "安装 LiteLLM proxy..."
        $pipArgs = @($python.PrefixArgs) + @("-m", "pip", "install", "--user", "litellm[proxy]")
        $pip = Invoke-Captured $python.File $pipArgs 900
        Log $pip.StdOut
        Log $pip.StdErr
        if ($pip.ExitCode -ne 0) { Fail "LiteLLM proxy 安装失败" "请检查 Python/pip 和网络。" }
        Refresh-ProcessPath
        Ok "LiteLLM proxy 安装完成"
    }
}

try {
    Preflight
    Install-CodexCli
    Install-CodexDesktop
    Verify
    Write-CodexLiteLLMBridge
    Ok "Codex Windows 安装流程完成"
} catch {
    Fail "未预期错误: $($_.Exception.Message)" "请查看日志并重新运行。"
}


