#Requires -Version 5.1
# =============================================================================
#  Claude Code + DeepSeek V4 Pro 一键部署  V3.2
#  核心: settings.json 直连 DeepSeek（ANTHROPIC_AUTH_TOKEN）
#  CcSwitch: 可选安装，不阻塞主流程
# =============================================================================

param()

$VERSION   = "3.2.2"
$INSTALL_DIR = "$env:LOCALAPPDATA\ClaudeCodeAgent"
$CC_DIR    = "$env:LOCALAPPDATA\cc-switch"
$GIT_DIR   = "$INSTALL_DIR\PortableGit"
$DEEPSEEK  = "https://api.deepseek.com/anthropic"
$MODEL     = "deepseek-v4-pro"
$MODEL_F   = "deepseek-v4-flash"
$NPM_MIRROR = "https://registry.npmmirror.com"
$GIT_URL   = "https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/PortableGit-2.54.0-64-bit.7z.exe"
$TOTAL     = 6

# ---- log ----
$LOGDIR = "$PSScriptRoot\logs"
if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Path $LOGDIR -Force | Out-Null }
$LOGFILE = "$LOGDIR\deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function L($m) { $l = "[$(Get-Date -Format 'HH:mm:ss')] $m"; Add-Content $LOGFILE $l -Encoding UTF8 }

# ---- output ----
function PC($c,$s) { Write-Host $s -ForegroundColor $c }
function OK($s)    { PC Green    "  [OK]   $s"; L "[OK] $s" }
function ERR($s)   { PC Red      "  [ERR]  $s"; L "[ERR] $s" }
function WARN($s)  { PC Yellow   "  [WARN] $s"; L "[WARN] $s" }
function INFO($s)  { PC Gray     "  [INFO] $s"; L "[INFO] $s" }
function ACT($s)   { PC DarkCyan "  [=>]   $s"; L "[ACT] $s" }

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

# ============ Phase 1: 环境检测 ============
function P1 {
    Phase "环境检测"

    # 磁盘
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $g = [math]::Round($d.FreeSpace / 1GB, 1)
    INFO "C盘可用: ${g}GB"
    if ($g -lt 1) { ERR "磁盘不足"; Read-Host "回车退出"; exit 1 }

    # 资源包
    $script:hasNodeZip = Test-Path "$PSScriptRoot\assets\node-v20.18.0-win-x64.zip"
    $script:hasCcZip   = Test-Path "$PSScriptRoot\assets\cc-switch-portable.zip"
    $script:gitSfx     = Get-ChildItem "$PSScriptRoot\assets\PortableGit-*-64-bit.7z.exe" -EA 0 | Select-Object -First 1
    $script:hasTgz     = $false
    if (Test-Path "$PSScriptRoot\assets\claude-code-offline") {
        $script:hasTgz = (@(Get-ChildItem "$PSScriptRoot\assets\claude-code-offline\*.tgz" -EA 0).Count -ge 2)
    }
    INFO "资源: Node=$($script:hasNodeZip) CcSwitch=$($script:hasCcZip) Claude=$($script:hasTgz) Git=$([bool]$script:gitSfx)"

    # 网络
    try { $null = iwr "https://api.deepseek.com" -TimeoutSec 5 -UseBasicParsing; $script:net = $true; OK "网络: DeepSeek 可达" }
    catch { $script:net = $false; WARN "网络: 未连接" }

    if ($script:hasNodeZip) { $script:mode = "offline"; OK "策略: U盘离线" }
    elseif ($script:net)    { $script:mode = "online";  OK "策略: 在线下载" }
    else { ERR "无资源包且无网络"; Read-Host "回车退出"; exit 1 }
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
    }

    $script:ownNode = $true
    if ($script:hasNodeZip) {
        ACT "解压 Node.js..."
        Expand-Archive "$PSScriptRoot\assets\node-v20.18.0-win-x64.zip" $INSTALL_DIR -Force
    } elseif ($script:net) {
        ACT "下载 Node.js..."
        $u = "https://npmmirror.com/mirrors/node/v20.18.0/node-v20.18.0-win-x64.zip"
        $t = "$env:TEMP\node.zip"
        iwr $u -OutFile $t -UseBasicParsing -TimeoutSec 300
        Expand-Archive $t $INSTALL_DIR -Force
        ri $t -Force -EA 0
    } else { ERR "无法获取 Node.js"; Read-Host "回车退出"; exit 1 }

    $f = Get-ChildItem $INSTALL_DIR -Directory -Filter "node-v20.*" | Select-Object -First 1
    if (-not $f) { ERR "解压失败"; Read-Host "回车退出"; exit 1 }
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

    # 安装
    if ($script:hasTgz) {
        ACT "离线安装 Claude Code..."
        $ts = Get-ChildItem "$PSScriptRoot\assets\claude-code-offline\*.tgz"
        $a = ($ts | %{ "`"$($_.FullName)`"" }) -join ' '
        Invoke-Expression "npm install -g $a" 2>&1 | Out-Null
    } elseif ($script:net) {
        ACT "在线安装 Claude Code..."
        & npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
    } else { ERR "无法安装 Claude Code"; Read-Host "回车退出"; exit 1 }

    if ($LASTEXITCODE -ne 0) { ERR "安装失败"; Read-Host "回车退出"; exit 1 }

    # 定位 claude
    $cl = Get-Command claude -EA 0
    if (-not $cl) { $p = Join-Path $script:nd "claude.cmd"; if (Test-Path $p) { $cl = @{Source=$p} } }
    if (-not $cl) { $np = & npm config get prefix 2>$null; $p = Join-Path $np "claude.cmd"; if (Test-Path $p) { $cl = @{Source=$p} } }
    if (-not $cl) { ERR "claude 命令不可用"; Read-Host "回车退出"; exit 1 }

    $ver = & $cl.Source --version 2>$null
    OK "Claude Code $ver"
}

# ============ Phase 4: Git Bash / PowerShell 7 Runtime ============
function P4Runtime {
    Phase "安装 Claude Code 运行环境"

    $pwsh = Get-Command pwsh -EA 0
    if ($pwsh) {
        OK "PowerShell 7 已存在"
        return
    }

    $bash = Find-GitBash
    if (-not $bash) {
        if ($script:gitSfx) {
            ACT "解压 PortableGit..."
            if (Test-Path $GIT_DIR) { Remove-Item -Recurse -Force $GIT_DIR -EA 0 }
            New-Item -ItemType Directory -Path $GIT_DIR -Force | Out-Null
            $p = Start-Process -FilePath $script:gitSfx.FullName -ArgumentList @("-y", "-o$GIT_DIR") -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) { throw "PortableGit 解压失败: $($p.ExitCode)" }
        } elseif ($script:net) {
            ACT "下载 PortableGit..."
            $tmp = "$env:TEMP\PortableGit.7z.exe"
            iwr $GIT_URL -OutFile $tmp -UseBasicParsing -TimeoutSec 300
            if (Test-Path $GIT_DIR) { Remove-Item -Recurse -Force $GIT_DIR -EA 0 }
            New-Item -ItemType Directory -Path $GIT_DIR -Force | Out-Null
            $p = Start-Process -FilePath $tmp -ArgumentList @("-y", "-o$GIT_DIR") -Wait -PassThru -WindowStyle Hidden
            ri $tmp -Force -EA 0
            if ($p.ExitCode -ne 0) { throw "PortableGit 解压失败: $($p.ExitCode)" }
        } else {
            ERR "缺少 Git Bash 或 PowerShell 7"
            Read-Host "回车退出"
            exit 1
        }
        $bash = Find-GitBash
    }

    if (-not $bash) { throw "未找到 Git Bash bash.exe" }
    $script:gitBash = $bash.Trim()
    $env:CLAUDE_CODE_GIT_BASH_PATH = $script:gitBash
    [Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $script:gitBash, "User")
    OK "Git Bash 就绪"
    INFO "bash: $script:gitBash"
}

# ============ Phase 5: API Key + 配置 ============
function P4 {
    Phase "配置 DeepSeek API Key"

    # 获取 Key
    PC White ""
    PC White "  +-------------------------------------------+"
    PC White "  |  请输入 DeepSeek API Key                  |"
    PC White "  |  格式: sk-xxxxxxxxxxxxxxxx                |"
    PC White "  |  获取: platform.deepseek.com -> API Keys  |"
    PC White "  +-------------------------------------------+"
    PC White ""
    for ($i = 1; $i -le 3; $i++) {
        $k = Read-Host "  API Key"
        if ([string]::IsNullOrWhiteSpace($k)) { WARN "不能为空 ($i/3)"; continue }
        if (-not $k.StartsWith("sk-")) { WARN "格式应以 sk- 开头 ($i/3)"; continue }
        ACT "验证 Key..."
        try {
            $b = @{ model="deepseek-v4-pro"; messages=@(@{role="user";content="hi"}); max_tokens=1 } | ConvertTo-Json -Compress
            $h = @{ "Content-Type"="application/json"; Authorization="Bearer $k" }
            $r = Invoke-RestMethod -Uri "https://api.deepseek.com/chat/completions" -Method Post -Body $b -Headers $h -TimeoutSec 10
            OK "Key 有效"
            $script:key = $k
            break
        } catch {
            $c = [int]$_.Exception.Response.StatusCode
            if ($c -eq 401) { ERR "Key 无效 (401)" }
            elseif ($c -eq 0) { WARN "网络不通，跳过验证"; $script:key = $k; break }
            else { WARN "异常($c)，跳过"; $script:key = $k; break }
        }
    }
    if (-not $script:key) { ERR "未获取到有效 Key"; Read-Host "回车退出"; exit 1 }

    # ---- 写入 Claude Code settings.json（核心配置） ----
    ACT "写入 Claude Code 配置..."
    $cfgDir = "$env:USERPROFILE\.claude"
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    $cfgFile = "$cfgDir\settings.json"
    $cfg = @{ env = @{} }

    # 保留已有非 env 字段
    if (Test-Path $cfgFile) {
        try { $old = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
              $old.PSObject.Properties | %{ if ($_.Name -ne "env") { $cfg[$_.Name] = $_.Value } }
        } catch { WARN "现有配置格式异常，将覆盖" }
    }

    # 关键：使用 ANTHROPIC_AUTH_TOKEN（不是 ANTHROPIC_API_KEY）
    # 第三方 Anthropic 兼容端点通过 AUTH_TOKEN 传 Key
    $cfgEnv = @{
        ANTHROPIC_BASE_URL   = $DEEPSEEK
        ANTHROPIC_AUTH_TOKEN = $script:key
        ANTHROPIC_MODEL      = $MODEL
        ANTHROPIC_DEFAULT_OPUS_MODEL  = $MODEL
        ANTHROPIC_DEFAULT_SONNET_MODEL = $MODEL
        ANTHROPIC_DEFAULT_HAIKU_MODEL = $MODEL_F
    }
    if ($script:gitBash) { $cfgEnv.CLAUDE_CODE_GIT_BASH_PATH = $script:gitBash }
    $cfg.env = $cfgEnv

    $cfg | ConvertTo-Json -Depth 5 | Set-Content $cfgFile -Encoding UTF8
    OK "Claude Code 配置完成"
    INFO "端点: $DEEPSEEK"
    INFO "模型: $MODEL"
    INFO "认证: ANTHROPIC_AUTH_TOKEN"
}

# ============ Phase 6: PATH + CcSwitch(可选) + 验证 ============
function P5 {
    Phase "PATH 持久化 + CcSwitch 安装"

    # ---- 1. PATH 持久化 ----
    try {
        $up = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($up -notlike "*$($script:nd)*") {
            [Environment]::SetEnvironmentVariable("Path", "$($script:nd);$up", "User")
            OK "PATH 已持久化"
        }
    } catch { WARN "PATH 持久化失败" }

    # PowerShell 执行策略
    try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force >$null 2>&1
          OK "PowerShell 执行策略已设置"
    } catch { WARN "执行策略设置失败，请手动运行: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" }

    # ---- 2. CcSwitch（强制重新安装） ----
    $script:ccReady = $false

    # 删除旧版本
    if (Test-Path $CC_DIR) {
        ACT "删除旧版 CcSwitch..."
        Remove-Item -Recurse -Force $CC_DIR -EA 0
    }
    New-Item -ItemType Directory -Path $CC_DIR -Force | Out-Null

    # 优先在线下载最新版
    $ccDownloaded = $false
    if ($script:net) {
        ACT "在线检查 CcSwitch 最新版..."
        try {
            $api = iwr "https://api.github.com/repos/farion1231/cc-switch/releases/latest" -UseBasicParsing -TimeoutSec 10 | ConvertFrom-Json
            $latestTag = $api.tag_name
            INFO "最新版: $latestTag"
            $dlUrl = $api.assets | Where-Object { $_.browser_download_url -like "*Windows-Portable*" } | Select-Object -ExpandProperty browser_download_url -First 1
            if ($dlUrl) {
                ACT "下载 CcSwitch $latestTag..."
                $tmp = "$env:TEMP\cc-switch-latest.zip"
                iwr $dlUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120
                Expand-Archive $tmp $CC_DIR -Force
                ri $tmp -Force -EA 0
                $ccDownloaded = $true
                OK "CcSwitch $latestTag 已安装"
            }
        } catch {
            WARN "在线检查失败，使用离线版"
        }
    }

    if (-not $ccDownloaded -and $script:hasCcZip) {
        ACT "解压 CcSwitch 离线版..."
        Expand-Archive "$PSScriptRoot\assets\cc-switch-portable.zip" $CC_DIR -Force
        OK "CcSwitch 离线版已安装"
    }

    if (Test-Path "$CC_DIR\cc-switch.exe") {
        $script:ccReady = $true
        OK "CcSwitch 就绪"

        # 启动 CcSwitch 主界面
        ACT "启动 CcSwitch..."
        Start-Process "$CC_DIR\cc-switch.exe" -WindowStyle Normal
        Start-Sleep 3

        # 桌面快捷方式
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
        } catch { WARN "快捷方式创建失败" }
    } else {
        WARN "CcSwitch 未安装（不影响 Claude Code 使用）"
    }

    # ---- 3. 验证 claude ----
    ACT "验证 claude..."
    $cl = Get-Command claude -EA 0
    if (-not $cl) { $p = Join-Path $script:nd "claude.cmd"; if (Test-Path $p) { $cl = @{Source=$p} } }
    if ($cl) {
        $v = & $cl.Source --version 2>$null
        if ($v) { OK "claude 可用: $v" }
    } else {
        WARN "新开终端后生效"
    }

    # ---- 4. 桌面使用说明 ----
    try {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $readmeFile = Join-Path $desktop "Claude Code 使用说明.txt"
        $today = Get-Date -Format 'yyyy-MM-dd'
        $readmeContent = @"
===============================================
   Claude Code + DeepSeek V4 Pro 使用说明
===============================================

【启动 Claude Code】
  1. 打开 PowerShell 或 CMD 终端
  2. 输入 claude 并按回车
  3. 等待启动完成后即可对话

【常用命令】
  claude                     启动交互模式
  claude --version           查看版本
  claude "你的问题"          直接提问（不进入交互模式）
  /help                      查看帮助
  /clear                     清空对话

【运行依赖】
  已自动配置 Git Bash / PowerShell 7 运行环境
  如遇启动异常，请重新打开终端后再输入 claude

【桌面快捷方式】
  CcSwitch 提供商管理器快捷方式已在桌面，双击即可打开
  用于切换 AI 模型提供商（DeepSeek、Kimi 等）
  管理 API Key、查看使用量

【常见问题】
  Q: 输入 claude 回车后提示"无法识别"？
  A: 重启电脑后再试，或打开新的终端窗口

  Q: Claude Code 提示 /login？
  A: 输入 /login 按提示操作，或在 CcSwitch 中重新配置 API Key

  Q: 如何切换模型？
  A: 打开桌面 CcSwitch 快捷方式 → 添加提供商 → 配置 API Key → 启用

===============================================
  技术支持：请联系提供此安装包的团队
  部署日期：$today
===============================================
"@
        Set-Content -Path $readmeFile -Value $readmeContent -Encoding UTF8
        OK "桌面使用说明已生成"
    } catch { WARN "使用说明生成失败" }
}

# ============ 完成 ============
function Done {
    PC Cyan ""
    PC Cyan "  +============================================+"
    PC Cyan "  |           部署完成！                       |"
    PC Cyan "  +============================================+"
    PC White ""
    PC White "  新开终端输入: claude"
    PC Cyan ""
    INFO "模型: DeepSeek V4 Pro"
    INFO "端点: $DEEPSEEK"
    INFO "配置: %USERPROFILE%\.claude\settings.json"
    if ($script:gitBash) { INFO "Git Bash: $script:gitBash" }
    INFO "日志: $LOGFILE"
    if ($script:ccReady) {
        INFO "CcSwitch 已安装: %LOCALAPPDATA%\cc-switch\cc-switch.exe"
        INFO "如何打开: 双击运行 → 系统托盘找 CcSwitch 图标 → 右键 → 打开主面板"
        INFO "如何配置: 主面板点击'添加提供商' → 选择 DeepSeek → 输入 API Key → 启用代理"
    }
    INFO "桌面快捷方式: 桌面上有 CcSwitch 快捷方式"
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
    P4
    P5
    Done
} catch {
    ERR "未预期错误: $($_.Exception.Message)"
    INFO "位置: $($_.InvocationInfo.ScriptLineNumber) 行"
    INFO "日志: $LOGFILE"
    Read-Host "回车退出"
    exit 1
}
