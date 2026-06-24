#Requires -Version 5.1
# =============================================================================
#  Claude Code + DeepSeek V4 Pro 一键部署  V3.2
#  核心: settings.json 直连 DeepSeek（ANTHROPIC_AUTH_TOKEN）
#  CcSwitch: 可选安装，不阻塞主流程
# =============================================================================

param()

$VERSION    = "3.2.3"
$INSTALL_DIR = "$env:LOCALAPPDATA\ClaudeCodeAgent"
$CC_DIR     = "$env:LOCALAPPDATA\cc-switch"
$GIT_DIR    = "$INSTALL_DIR\PortableGit"
$ASSET_DIR  = "$PSScriptRoot\assets"
$CLAUDE_OFFLINE_DIR = "$ASSET_DIR\claude-code-offline"
$DEEPSEEK   = "https://api.deepseek.com/anthropic"
$MODEL      = "deepseek-v4-pro"
$MODEL_F    = "deepseek-v4-flash"
$NPM_MIRROR = "https://registry.npmmirror.com"
$GIT_URL    = "https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/PortableGit-2.54.0-64-bit.7z.exe"
$TOTAL      = 7

# ---- log ----
$LOGDIR = "$PSScriptRoot\logs"
try {
    if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Path $LOGDIR -Force -ErrorAction Stop | Out-Null }
    $logProbe = Join-Path $LOGDIR ".write-test"
    Set-Content -Path $logProbe -Value "ok" -Encoding ASCII -ErrorAction Stop
    Remove-Item -Path $logProbe -Force -ErrorAction SilentlyContinue
} catch {
    $LOGDIR = Join-Path $env:TEMP "CCDeploy-logs"
    if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Path $LOGDIR -Force | Out-Null }
}
$LOGFILE = "$LOGDIR\deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Sanitize($s) {
    if ($null -eq $s) { return "" }
    $text = [string]$s
    $text = $text -replace 'sk-[A-Za-z0-9_\-]+', 'sk-***'
    $text = $text -replace '(?i)Bearer\s+[A-Za-z0-9_\-\.=]+', 'Bearer ***'
    $text = $text -replace '(?i)(ANTHROPIC_AUTH_TOKEN\s*["'':=]+\s*)[^,"'';\s}]+', '${1}***'
    $text = $text -replace '(?i)(Authorization\s*["'':=]+\s*)[^,"'';\s}]+', '${1}***'
    return $text
}

function L($m) {
    $l = "[$(Get-Date -Format 'HH:mm:ss')] $(Sanitize $m)"
    Add-Content $LOGFILE $l -Encoding UTF8
}

# ---- output ----
function PC($c,$s) { Write-Host $s -ForegroundColor $c }
function OK($s)    { PC Green    "  [OK]   $s"; L "[OK] $s" }
function ERR($s)   { PC Red      "  [ERR]  $s"; L "[ERR] $s" }
function WARN($s)  { PC Yellow   "  [WARN] $s"; L "[WARN] $s" }
function INFO($s)  { PC Gray     "  [INFO] $s"; L "[INFO] $s" }
function ACT($s)   { PC DarkCyan "  [=>]   $s"; L "[ACT] $s" }

function Fail($message, $hint) {
    ERR $message
    if ($hint) { INFO "建议: $hint" }
    INFO "日志: $LOGFILE"
    Read-Host "回车退出"
    exit 1
}

function Phase($t) {
    $script:n++
    $p = [math]::Min(100, [math]::Round($script:n / $TOTAL * 100))
    $d = [math]::Min(20, [math]::Max(0, [math]::Round($script:n / $TOTAL * 20)))
    $b = ("#" * $d) + ("-" * [math]::Max(0, (20 - $d)))
    PC Cyan ""
    PC Cyan "  ========================================="
    PC Cyan "   [$($script:n)/$TOTAL] $t"
    PC Cyan "   [$b] $p%"
    PC Cyan "  ========================================="
    L "=== Phase $($script:n)/${TOTAL}: $t ==="
}

function Banner {
    Clear-Host
    PC Cyan ""
    PC Cyan "  ========================================="
    PC Cyan "    Claude Code + DeepSeek V4 Pro"
    PC Cyan "    一键部署 | 无需翻墙 | 全自动"
    PC Cyan "    v$VERSION"
    PC Cyan "  ========================================="
    PC Cyan ""
}

function Test-WriteAccess($path) {
    try {
        New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
        $tmp = Join-Path $path ".ccdeploy-write-test"
        Set-Content -Path $tmp -Value "ok" -Encoding ASCII -ErrorAction Stop
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        L "Write test failed for ${path}: $($_.Exception.Message)"
        return $false
    }
}

function Get-AssetPath($name) {
    $rootPath = Join-Path $ASSET_DIR $name
    if (Test-Path $rootPath) { return (Resolve-Path $rootPath).Path }
    $offlinePath = Join-Path $CLAUDE_OFFLINE_DIR $name
    if (Test-Path $offlinePath) { return (Resolve-Path $offlinePath).Path }
    return $null
}

function Test-AssetManifest([string[]]$RequiredNames, [string[]]$OptionalNames = @()) {
    $manifestFile = Join-Path $ASSET_DIR "manifest.json"
    if (-not (Test-Path $manifestFile)) {
        if ($RequiredNames.Count -gt 0) {
            Fail "未找到资源清单: assets\manifest.json" "请重新复制完整安装包，或重新下载发布包。"
        }
        WARN "未找到 assets\manifest.json，在线安装时跳过资源哈希校验"
        return
    }

    try {
        $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Fail "资源清单格式错误" "请重新复制完整安装包，或重新下载发布包。"
    }

    if (-not $manifest.assets -or @($manifest.assets).Count -eq 0) {
        Fail "资源清单为空" "请重新复制完整安装包，或重新下载发布包。"
    }

    if ($manifest.version -and $manifest.version -ne $VERSION) {
        Fail "资源清单版本 $($manifest.version) 与脚本版本 $VERSION 不一致" "请不要混用不同版本的 deploy.ps1 和 assets 文件夹。"
    }

    $namesToCheck = @()
    $namesToCheck += @($RequiredNames)
    foreach ($name in @($OptionalNames)) {
        if ($name -and (Get-AssetPath $name)) { $namesToCheck += $name }
    }

    foreach ($name in ($namesToCheck | Where-Object { $_ } | Select-Object -Unique)) {
        $asset = @($manifest.assets | Where-Object { $_.name -eq $name }) | Select-Object -First 1
        if (-not $asset) {
            Fail "资源清单缺少条目: $name" "请重新复制完整安装包，或重新下载发布包。"
        }
        $path = Get-AssetPath $asset.name
        if (-not $path) {
            Fail "缺少离线资源: $($asset.name)" "请确认 assets 文件夹完整，或重新下载发布包。"
        }

        if ($asset.sha256) {
            ACT "校验资源: $($asset.name)"
            $actual = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToUpperInvariant()
            $expected = ([string]$asset.sha256).ToUpperInvariant()
            if ($actual -ne $expected) {
                Fail "资源校验失败: $($asset.name)" "文件可能损坏或被替换。请删除当前安装包后重新复制。"
            }
        }
    }
    OK "资源清单校验通过"
}

function Test-NetworkQuick {
    try {
        $null = Invoke-WebRequest "https://api.deepseek.com" -TimeoutSec 5 -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

function Find-GitBash {
    $candidates = @()
    if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $candidates += $env:CLAUDE_CODE_GIT_BASH_PATH.Trim() }
    $candidates += @(
        "$GIT_DIR\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    $gitCmd = Get-Command git -EA 0
    if ($gitCmd) {
        $root = Split-Path (Split-Path $gitCmd.Source)
        $candidates += (Join-Path $root "bin\bash.exe")
    }
    foreach ($p in $candidates | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    return $null
}

function Find-ClaudeCmd {
    $cl = Get-Command claude -EA 0
    if ($cl) { return $cl.Source }
    if ($script:nd) {
        $p = Join-Path $script:nd "claude.cmd"
        if (Test-Path $p) { return $p }
    }
    try {
        $np = & npm config get prefix 2>$null
        if ($np) {
            $p = Join-Path $np.Trim() "claude.cmd"
            if (Test-Path $p) { return $p }
        }
    } catch {}
    return $null
}

function Quote-Arg($arg) {
    $value = [string]$arg
    if ($value -notmatch '[\s"]') { return $value }
    return '"' + ($value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Join-CommandLineArgs([string[]]$items) {
    return (@($items) | ForEach-Object { Quote-Arg $_ }) -join ' '
}

function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory=$true)][string]$file,
        [Parameter(Mandatory=$true)][string[]]$arguments,
        [Parameter(Mandatory=$true)][int]$timeoutSec
    )

    $result = @{ ExitCode = $null; StdOut = ""; StdErr = ""; TimedOut = $false }

    try {
        $argLine = Join-CommandLineArgs $arguments
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $file
        $psi.Arguments = $argLine
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
        if (-not $done) {
            $result.TimedOut = $true
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        } else {
            $result.ExitCode = $p.ExitCode
            $p.WaitForExit()
        }
        $result.StdOut = Sanitize $outTask.Result
        $result.StdErr = Sanitize $errTask.Result
    } catch {
        $result.StdErr = Sanitize $_.Exception.Message
        $result.ExitCode = 1
    } finally {}
    return $result
}

function Get-PlainTextFromSecureString($secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Get-HttpStatus($err) {
    try {
        if ($err.Exception.Response -and $err.Exception.Response.StatusCode) {
            return [int]$err.Exception.Response.StatusCode
        }
    } catch {}
    return 0
}

function Write-CommandLog($prefix, $lines) {
    foreach ($line in @($lines)) {
        if ($null -ne $line -and ([string]$line).Trim()) {
            L "[$prefix] $line"
        }
    }
}

function Get-ManifestAssetNamesByRole($rolePattern) {
    $manifestFile = Join-Path $ASSET_DIR "manifest.json"
    if (-not (Test-Path $manifestFile)) { return @() }
    try {
        $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($manifest.assets | Where-Object { $_.role -match $rolePattern } | Select-Object -ExpandProperty name)
    } catch {
        return @()
    }
}

# ============ Phase 1: 环境检测 + 资源校验 ============
function P1 {
    Phase "环境检测 + 资源校验"

    if ([Environment]::OSVersion.Platform -ne "Win32NT") {
        Fail "当前脚本仅支持 Windows" "请使用 Windows 10/11 64 位系统运行。"
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        Fail "不支持 32 位 Windows" "请换用 64 位 Windows。"
    }
    OK "系统: Windows 64 位"
    INFO "PowerShell: $($PSVersionTable.PSVersion)"

    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $g = [math]::Round($d.FreeSpace / 1GB, 1)
    INFO "C盘可用: ${g}GB"
    if ($g -lt 2) { Fail "C盘空间不足" "至少保留 2GB 可用空间，建议 5GB 以上。" }
    if ($g -lt 5) { WARN "C盘空间偏低，建议清理到 5GB 以上" }

    if (-not (Test-WriteAccess $INSTALL_DIR)) {
        Fail "无法写入安装目录" "请确认当前用户有权限写入 %LOCALAPPDATA%。"
    }
    if (-not (Test-WriteAccess $LOGDIR)) {
        Fail "无法写入日志目录" "请把安装包复制到本机桌面或用户目录后重试。"
    }
    OK "写入权限正常"

    $script:hasNodeZip = Test-Path "$ASSET_DIR\node-v20.18.0-win-x64.zip"
    $script:hasCcZip   = Test-Path "$ASSET_DIR\cc-switch-portable.zip"
    $script:gitSfx     = Get-ChildItem "$ASSET_DIR\PortableGit-*-64-bit.7z.exe" -EA 0 | Select-Object -First 1
    $script:hasTgz     = $false
    if (Test-Path $CLAUDE_OFFLINE_DIR) {
        $script:hasTgz = (@(Get-ChildItem "$CLAUDE_OFFLINE_DIR\*.tgz" -EA 0).Count -ge 2)
    }
    INFO "资源: Node=$($script:hasNodeZip) CcSwitch=$($script:hasCcZip) Claude=$($script:hasTgz) Git=$([bool]$script:gitSfx)"

    $script:net = Test-NetworkQuick
    if ($script:net) { OK "网络: DeepSeek 入口可达" }
    else { WARN "网络: 暂未确认可达，稍后会用 API Key 再验证" }

    if ($script:hasNodeZip -and $script:hasTgz) {
        $script:mode = "offline"
        $required = @(
            "node-v20.18.0-win-x64.zip",
            "anthropic-ai-claude-code-2.1.170.tgz",
            "anthropic-ai-claude-code-win32-x64-2.1.170.tgz"
        )
        if (-not (Find-GitBash)) {
            $required += "PortableGit-2.54.0-64-bit.7z.exe"
        }
        Test-AssetManifest -RequiredNames $required -OptionalNames @("cc-switch-portable.zip")
        OK "策略: 离线资源优先"
    } elseif ($script:net) {
        $script:mode = "online"
        Test-AssetManifest -RequiredNames @() -OptionalNames @(
            "node-v20.18.0-win-x64.zip",
            "anthropic-ai-claude-code-2.1.170.tgz",
            "anthropic-ai-claude-code-win32-x64-2.1.170.tgz",
            "PortableGit-2.54.0-64-bit.7z.exe",
            "cc-switch-portable.zip"
        )
        OK "策略: 在线下载"
    } else {
        Fail "缺少离线资源且网络不可用" "请复制完整 assets 文件夹，或连接网络后重试。"
    }
}

# ============ Phase 2: Node.js ============
function P2 {
    Phase "安装 Node.js"

    $e = Get-Command node -EA 0
    if ($e) {
        $v = & node --version 2>$null
        if ($v -and ([Version]$v.TrimStart('v') -ge [Version]"18.0.0")) {
            INFO "系统已有 Node.js $v"
            $script:nd = Split-Path $e.Source
            $script:ownNode = $false
            OK "使用系统 Node.js"
            return
        }
        WARN "系统 Node.js 版本过低，将使用内置 Node.js"
    }

    $script:ownNode = $true
    if ($script:hasNodeZip) {
        ACT "解压 Node.js..."
        Expand-Archive "$ASSET_DIR\node-v20.18.0-win-x64.zip" $INSTALL_DIR -Force
    } elseif ($script:net) {
        ACT "下载 Node.js..."
        $u = "https://npmmirror.com/mirrors/node/v20.18.0/node-v20.18.0-win-x64.zip"
        $t = "$env:TEMP\node-v20.18.0-win-x64.zip"
        Invoke-WebRequest $u -OutFile $t -UseBasicParsing -TimeoutSec 300
        Expand-Archive $t $INSTALL_DIR -Force
        Remove-Item $t -Force -EA 0
    } else {
        Fail "无法获取 Node.js" "请确认 assets 中存在 node-v20.18.0-win-x64.zip。"
    }

    $f = Get-ChildItem $INSTALL_DIR -Directory -Filter "node-v20.*" | Select-Object -First 1
    if (-not $f) { Fail "Node.js 解压失败" "请重新复制安装包后重试。" }
    $script:nd = $f.FullName
    $v = & "$($script:nd)\node.exe" --version
    OK "Node.js $v"
}

# ============ Phase 3: Claude Code ============
function P3 {
    Phase "安装 Claude Code"

    $env:Path = "$($script:nd);$env:Path"
    if ($script:ownNode) {
        ACT "配置 npm prefix"
        & npm config set prefix "$($script:nd)" 2>$null
    }
    & npm config set registry $NPM_MIRROR 2>$null
    INFO "npm prefix: $(npm config get prefix)"

    if ($script:hasTgz) {
        ACT "离线安装 Claude Code..."
        $manifestTgz = Get-ManifestAssetNamesByRole "Claude Code"
        if (@($manifestTgz).Count -gt 0) {
            $ts = @($manifestTgz | ForEach-Object {
                $p = Join-Path $CLAUDE_OFFLINE_DIR $_
                if (-not (Test-Path $p)) { Fail "缺少 Claude Code 离线包: $_" "请重新复制完整安装包。" }
                Get-Item $p
            })
        } else {
            $ts = @(Get-ChildItem "$CLAUDE_OFFLINE_DIR\*.tgz")
        }
        if (@($ts).Count -lt 2) { Fail "Claude Code 离线包不完整" "请确认 claude-code-offline 中包含 wrapper 和 win32-x64 两个 tgz。" }
        $npmOutput = & npm install -g --offline --no-audit --no-fund @($ts.FullName) 2>&1
    } elseif ($script:net) {
        ACT "在线安装 Claude Code..."
        $npmOutput = & npm install -g @anthropic-ai/claude-code 2>&1
    } else {
        Fail "无法安装 Claude Code" "请确认离线 tgz 资源完整，或连接网络后重试。"
    }
    $npmExit = $LASTEXITCODE
    Write-CommandLog "npm" $npmOutput

    if ($npmExit -ne 0) {
        $tail = @($npmOutput | Select-Object -Last 8) -join " | "
        if ($tail) { INFO "npm 摘要: $(Sanitize $tail)" }
        Fail "Claude Code 安装失败" "请查看日志中的 npm 错误，并重新运行安装脚本。"
    }

    $cl = Find-ClaudeCmd
    if (-not $cl) { Fail "claude 命令不可用" "请重新运行安装脚本，或检查 Node.js npm prefix。" }

    $ver = & $cl --version 2>$null
    if (-not $ver) { Fail "claude 已安装但无法读取版本" "请打开新终端输入 claude --version 查看具体错误。" }
    $script:claudeCmd = $cl
    OK "Claude Code $ver"
}

# ============ Phase 4: Git Bash / PowerShell 7 Runtime ============
function P4Runtime {
    Phase "安装 Claude Code 运行环境"

    $pwsh = Get-Command pwsh -EA 0
    if ($pwsh) {
        $script:pwshPath = $pwsh.Source
        OK "PowerShell 7 已存在"
        INFO "pwsh: $($pwsh.Source)"
    } else {
        INFO "未检测到 PowerShell 7，将使用 Git Bash 运行环境"
    }

    $bash = Find-GitBash
    if (-not $bash) {
        if ($script:gitSfx) {
            ACT "解压 PortableGit..."
            if (Test-Path $GIT_DIR) { Remove-Item -Recurse -Force $GIT_DIR -EA 0 }
            New-Item -ItemType Directory -Path $GIT_DIR -Force | Out-Null
            $gitArgs = Join-CommandLineArgs @("-y", "-o$GIT_DIR")
            $p = Start-Process -FilePath $script:gitSfx.FullName -ArgumentList $gitArgs -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) { Fail "PortableGit 解压失败" "错误码: $($p.ExitCode)。请重新复制 PortableGit 离线包。" }
        } elseif ($script:net) {
            ACT "下载 PortableGit..."
            $tmp = "$env:TEMP\PortableGit.7z.exe"
            Invoke-WebRequest $GIT_URL -OutFile $tmp -UseBasicParsing -TimeoutSec 300
            if (Test-Path $GIT_DIR) { Remove-Item -Recurse -Force $GIT_DIR -EA 0 }
            New-Item -ItemType Directory -Path $GIT_DIR -Force | Out-Null
            $gitArgs = Join-CommandLineArgs @("-y", "-o$GIT_DIR")
            $p = Start-Process -FilePath $tmp -ArgumentList $gitArgs -Wait -PassThru -WindowStyle Hidden
            Remove-Item $tmp -Force -EA 0
            if ($p.ExitCode -ne 0) { Fail "PortableGit 解压失败" "错误码: $($p.ExitCode)。请重新运行安装脚本。" }
        } else {
            Fail "缺少 Git Bash 或 PowerShell 7" "Claude Code on Windows 需要 Git Bash 或 PowerShell 7；请复制完整安装包。"
        }
        $bash = Find-GitBash
    }

    if (-not $bash) { Fail "未找到 Git Bash bash.exe" "请安装 Git for Windows，或重新运行本安装包。" }
    $script:gitBash = $bash.Trim()
    $env:CLAUDE_CODE_GIT_BASH_PATH = $script:gitBash
    [Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $script:gitBash, "User")
    OK "Git Bash 就绪"
    INFO "bash: $script:gitBash"
}

# ============ Phase 5: API Key + 配置 ============
function P5Config {
    Phase "配置 DeepSeek API Key"

    PC White ""
    PC White "  +-------------------------------------------+"
    PC White "  |  请输入 DeepSeek API Key                  |"
    PC White "  |  输入时不会显示，粘贴后直接回车即可       |"
    PC White "  |  获取: platform.deepseek.com -> API Keys  |"
    PC White "  +-------------------------------------------+"
    PC White ""

    for ($i = 1; $i -le 3; $i++) {
        $secure = Read-Host "  API Key" -AsSecureString
        $k = Get-PlainTextFromSecureString $secure
        if ([string]::IsNullOrWhiteSpace($k)) { WARN "不能为空 ($i/3)"; continue }
        if (-not $k.StartsWith("sk-")) { WARN "格式应以 sk- 开头 ($i/3)"; continue }

        ACT "验证 Key..."
        try {
            $b = @{ model=$MODEL; messages=@(@{role="user";content="hi"}); max_tokens=1 } | ConvertTo-Json -Compress
            $h = @{ "Content-Type"="application/json"; Authorization="Bearer $k" }
            $null = Invoke-RestMethod -Uri "https://api.deepseek.com/chat/completions" -Method Post -Body $b -Headers $h -TimeoutSec 20
            OK "Key 有效"
            $script:key = $k
            break
        } catch {
            $c = Get-HttpStatus $_
            if ($c -eq 401) {
                ERR "Key 无效 (401)"
            } elseif ($c -eq 402) {
                ERR "DeepSeek 账户余额不足或无可用额度 (402)"
            } elseif ($c -eq 429) {
                WARN "DeepSeek 暂时限流 (429)，请稍后重试 ($i/3)"
            } elseif ($c -ge 500) {
                WARN "DeepSeek 服务暂时异常 ($c)，请稍后重试 ($i/3)"
            } else {
                WARN "Key 验证失败，网络或端点异常 ($i/3)"
                L $_.Exception.Message
            }
        }
    }
    if (-not $script:key) { Fail "未获取到可验证的 DeepSeek API Key" "请确认 Key、账户余额、网络连接后重新运行。" }

    ACT "写入 Claude Code 配置..."
    $cfgDir = "$env:USERPROFILE\.claude"
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    $cfgFile = "$cfgDir\settings.json"
    $cfg = @{ env = @{} }
    $existingEnv = @{}

    if (Test-Path $cfgFile) {
        Copy-Item $cfgFile "$cfgFile.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force -EA 0
        try {
            $old = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $old.PSObject.Properties | ForEach-Object {
                if ($_.Name -ne "env") { $cfg[$_.Name] = $_.Value }
            }
            if ($old.env) {
                $old.env.PSObject.Properties | ForEach-Object {
                    $existingEnv[$_.Name] = $_.Value
                }
            }
        } catch {
            WARN "现有 Claude 配置格式异常，将保留备份后覆盖"
        }
    }

    $cfgEnv = @{}
    foreach ($name in $existingEnv.Keys) {
        $cfgEnv[$name] = $existingEnv[$name]
    }
    $managedEnv = @{
        ANTHROPIC_BASE_URL   = $DEEPSEEK
        ANTHROPIC_AUTH_TOKEN = $script:key
        ANTHROPIC_MODEL      = $MODEL
        ANTHROPIC_DEFAULT_OPUS_MODEL   = $MODEL
        ANTHROPIC_DEFAULT_SONNET_MODEL = $MODEL
        ANTHROPIC_DEFAULT_HAIKU_MODEL  = $MODEL_F
        CLAUDE_CODE_SUBAGENT_MODEL     = $MODEL
        CLAUDE_CODE_EFFORT_LEVEL       = "medium"
    }
    if ($script:gitBash) { $managedEnv.CLAUDE_CODE_GIT_BASH_PATH = $script:gitBash }
    foreach ($name in $managedEnv.Keys) {
        $cfgEnv[$name] = $managedEnv[$name]
    }
    $cfg.env = $cfgEnv

    $cfg | ConvertTo-Json -Depth 20 | Set-Content $cfgFile -Encoding UTF8
    $script:configFile = $cfgFile
    OK "Claude Code 配置完成"
    INFO "端点: $DEEPSEEK"
    INFO "模型: $MODEL"
    INFO "认证: ANTHROPIC_AUTH_TOKEN"
}

# ============ Phase 6: Claude 启动 + DeepSeek 对话验证 ============
function P6Verify {
    Phase "Claude 启动 + DeepSeek 对话验证"

    $env:Path = "$($script:nd);$env:Path"
    if ($script:gitBash) { $env:CLAUDE_CODE_GIT_BASH_PATH = $script:gitBash }

    $cl = Find-ClaudeCmd
    if (-not $cl) { Fail "找不到 claude 命令" "请重新运行安装脚本，或打开新终端输入 claude --version。" }
    $script:claudeCmd = $cl

    ACT "验证 claude --version..."
    $versionCheck = Invoke-ProcessCapture -file $cl -arguments @("--version") -timeoutSec 40
    if ($versionCheck.TimedOut) {
        Fail "claude --version 超时" "请重启终端后手动运行 claude --version，并把日志发给技术支持。"
    }
    if ($versionCheck.ExitCode -ne 0 -or -not $versionCheck.StdOut.Trim()) {
        L $versionCheck.StdErr
        Fail "claude 启动验证失败" "请确认 Git Bash / PowerShell 7 依赖已安装，并查看日志。"
    }
    OK "claude 可启动: $($versionCheck.StdOut.Trim())"

    ACT "验证 DeepSeek 对话..."
    $prompt = "Reply with exactly OK"
    $chatCheck = Invoke-ProcessCapture -file $cl -arguments @("-p", $prompt) -timeoutSec 90
    if ($chatCheck.TimedOut) {
        Fail "DeepSeek 对话验证超时" "请检查网络是否能访问 api.deepseek.com，然后重新运行安装脚本。"
    }
    $combined = (($chatCheck.StdOut + "`n" + $chatCheck.StdErr).Trim())
    L "Claude verify output: $combined"
    if ($chatCheck.ExitCode -ne 0) {
        Fail "DeepSeek 对话验证失败" "请检查 API Key 是否有效、账户是否有余额、网络是否可访问 DeepSeek。"
    }
    if ($combined.Trim() -ne "OK") {
        INFO "返回内容: $combined"
        Fail "DeepSeek 对话验证未返回预期结果" "请检查模型配置是否可用，或稍后重新运行安装脚本。"
    }
    OK "DeepSeek 对话验证通过"
}

# ============ Phase 7: PATH + CcSwitch(可选) + 桌面说明 ============
function P7Finish {
    Phase "PATH 持久化 + CcSwitch 安装"

    try {
        $up = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not $up) { $up = "" }
        if ($up -notlike "*$($script:nd)*") {
            [Environment]::SetEnvironmentVariable("Path", "$($script:nd);$up", "User")
            OK "PATH 已持久化"
        } else {
            OK "PATH 已存在"
        }
    } catch {
        WARN "PATH 持久化失败，新终端可能识别不到 claude"
        L $_.Exception.Message
    }

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop | Out-Null
        OK "PowerShell 执行策略已设置"
    } catch {
        WARN "执行策略设置失败，不影响 claude 使用"
        INFO "需要时可手动运行: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    }

    $script:ccReady = $false
    if (Test-Path $CC_DIR) {
        ACT "删除旧版 CcSwitch..."
        Remove-Item -Recurse -Force $CC_DIR -EA 0
    }
    New-Item -ItemType Directory -Path $CC_DIR -Force | Out-Null

    $ccDownloaded = $false
    if ($script:net) {
        ACT "在线检查 CcSwitch 最新版..."
        try {
            $api = Invoke-WebRequest "https://api.github.com/repos/farion1231/cc-switch/releases/latest" -UseBasicParsing -TimeoutSec 10 | ConvertFrom-Json
            $latestTag = $api.tag_name
            INFO "最新版: $latestTag"
            $dlUrl = $api.assets | Where-Object { $_.browser_download_url -like "*Windows-Portable*" } | Select-Object -ExpandProperty browser_download_url -First 1
            if ($dlUrl) {
                ACT "下载 CcSwitch $latestTag..."
                $tmp = "$env:TEMP\cc-switch-latest.zip"
                Invoke-WebRequest $dlUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120
                Expand-Archive $tmp $CC_DIR -Force
                Remove-Item $tmp -Force -EA 0
                $ccDownloaded = $true
                OK "CcSwitch $latestTag 已安装"
            }
        } catch {
            WARN "在线检查失败，使用离线版"
            L $_.Exception.Message
        }
    }

    if (-not $ccDownloaded -and $script:hasCcZip) {
        ACT "解压 CcSwitch 离线版..."
        Expand-Archive "$ASSET_DIR\cc-switch-portable.zip" $CC_DIR -Force
        OK "CcSwitch 离线版已安装"
    }

    if (Test-Path "$CC_DIR\cc-switch.exe") {
        $script:ccReady = $true
        OK "CcSwitch 就绪"
        try {
            ACT "启动 CcSwitch..."
            Start-Process "$CC_DIR\cc-switch.exe" -WindowStyle Normal
            Start-Sleep 2
        } catch {
            WARN "CcSwitch 自动启动失败，可稍后用桌面快捷方式打开"
        }

        try {
            $desktop = [Environment]::GetFolderPath("Desktop")
            $shortcut = Join-Path $desktop "CcSwitch.lnk"
            $WScript = New-Object -ComObject WScript.Shell
            $link = $WScript.CreateShortcut($shortcut)
            $link.TargetPath = "$CC_DIR\cc-switch.exe"
            $link.WorkingDirectory = $CC_DIR
            $link.Description = "CcSwitch - Claude Code 提供商管理器"
            $link.Save()
            OK "桌面快捷方式已创建"
            INFO "快捷方式: $shortcut"
        } catch {
            WARN "快捷方式创建失败"
        }
    } else {
        WARN "CcSwitch 未安装（不影响 Claude Code 使用）"
    }

    try {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $readmeFile = Join-Path $desktop "Claude Code 使用说明.txt"
        $today = Get-Date -Format 'yyyy-MM-dd'
        $readmeContent = @"
===============================================
   Claude Code + DeepSeek V4 Pro 使用说明
===============================================

【启动 Claude Code】
  1. 打开新的 PowerShell 或 CMD 终端
  2. 输入 claude 并按回车
  3. 等待启动完成后即可对话

【常用命令】
  claude                     启动交互模式
  claude --version           查看版本
  claude -p "你好"           直接提问
  /help                      查看帮助
  /clear                     清空对话

【已自动配置】
  模型: DeepSeek V4 Pro
  端点: $DEEPSEEK
  配置: %USERPROFILE%\.claude\settings.json
  运行依赖: Git Bash / PowerShell 7

【CcSwitch】
  桌面已创建 CcSwitch 快捷方式
  可用于后续手动添加或切换更多模型提供商
  当前 Claude Code 默认走 DeepSeek 直连配置，不依赖 CcSwitch 才能使用

【常见问题】
  Q: 输入 claude 回车后提示"无法识别"？
  A: 关闭终端，重新打开 PowerShell 或 CMD 后再试。

  Q: 提示需要 Git for Windows 或 PowerShell 7？
  A: 重新运行安装脚本；本安装包会自动配置 PortableGit。

  Q: DeepSeek 对话失败？
  A: 检查 API Key、账户余额、网络连接，并把日志发给技术支持。

===============================================
  技术支持：请联系提供此安装包的团队
  部署日期：$today
===============================================
"@
        Set-Content -Path $readmeFile -Value $readmeContent -Encoding UTF8
        OK "桌面使用说明已生成"
        INFO "使用说明: $readmeFile"
    } catch {
        WARN "使用说明生成失败"
    }
}

# ============ 完成 ============
function Done {
    PC Cyan ""
    PC Cyan "  +============================================+"
    PC Cyan "  |           部署完成并通过验证！             |"
    PC Cyan "  +============================================+"
    PC White ""
    PC White "  新开终端输入: claude"
    PC Cyan ""
    INFO "模型: DeepSeek V4 Pro"
    INFO "端点: $DEEPSEEK"
    INFO "配置: %USERPROFILE%\.claude\settings.json"
    if ($script:gitBash) { INFO "Git Bash: $script:gitBash" }
    if ($script:pwshPath) { INFO "PowerShell 7: $script:pwshPath" }
    INFO "日志: $LOGFILE"
    if ($script:ccReady) {
        INFO "CcSwitch 已安装: %LOCALAPPDATA%\cc-switch\cc-switch.exe"
        INFO "如何打开: 双击桌面 CcSwitch 快捷方式，或在系统托盘中打开"
        INFO "如何配置: 主面板点击'添加提供商' → 选择模型服务 → 输入 API Key → 启用"
    }
    INFO "桌面使用说明: 桌面上已生成 Claude Code 使用说明.txt"
    PC Cyan ""
    Read-Host "  按回车退出"
}

# ====== MAIN ======
$script:n = 0
try {
    Banner
    P1
    P2
    P3
    P4Runtime
    P5Config
    P6Verify
    P7Finish
    Done
} catch {
    ERR "未预期错误: $($_.Exception.Message)"
    INFO "位置: $($_.InvocationInfo.ScriptLineNumber) 行"
    INFO "日志: $LOGFILE"
    Read-Host "回车退出"
    exit 1
}

