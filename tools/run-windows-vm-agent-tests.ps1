#Requires -Version 5.1
param(
    [string]$Root = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$VmName = "CCDeploy-Win11-Test",
    [string]$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe",
    [string]$SharedDir = "D:\VMs\CCDeployTest\Shared",
    [ValidateSet("all", "codex", "openclaw", "cursor")]
    [string]$Agent = "all",
    [string]$GuestUser,
    [string]$GuestPasswordFile,
    [string]$SnapshotName = "clean-base",
    [switch]$RestoreSnapshot,
    [switch]$RunRealInstall,
    [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"

$agents = @("codex", "openclaw", "cursor")
if ($Agent -ne "all") { $agents = @($Agent) }

function Write-TextFile([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Invoke-VBox([string[]]$Args, [string]$OutFile) {
    if (-not (Test-Path $VBoxManage)) {
        throw "VBoxManage not found: $VBoxManage"
    }
    $output = & $VBoxManage @Args 2>&1
    $code = $LASTEXITCODE
    if ($OutFile) {
        Write-TextFile $OutFile (($output | ForEach-Object { [string]$_ }) -join "`r`n")
    }
    return @{ ExitCode = $code; Output = $output }
}

function Invoke-GuestPowerShell([string]$Command, [string]$OutFile) {
    if (-not $GuestUser) {
        throw "GuestUser is required for guestcontrol execution."
    }
    if (-not $GuestPasswordFile -or -not (Test-Path $GuestPasswordFile)) {
        throw "GuestPasswordFile is required for guestcontrol execution. Store it outside the repository."
    }

    $args = @(
        "guestcontrol", $VmName, "run",
        "--exe", "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
        "--username", $GuestUser,
        "--passwordfile", $GuestPasswordFile,
        "--wait-stdout",
        "--wait-stderr",
        "--",
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", $Command
    )
    Invoke-VBox -Args $args -OutFile $OutFile
}

function Get-InstallArgs([string]$AgentId) {
    switch ($AgentId) {
        "cursor" { return "-InstallCliWithBash" }
        default { return "" }
    }
}

function Get-VerifyCommand([string]$AgentId) {
    switch ($AgentId) {
        "codex" { return "codex --version; codex doctor" }
        "openclaw" { return "openclaw --version" }
        "cursor" { return "cursor-agent --version" }
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultsDir = Join-Path $SharedDir "vm-results\$timestamp"
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

$planLines = New-Object System.Collections.Generic.List[string]
$planLines.Add("# Windows VM Agent Test Run $timestamp")
$planLines.Add("")
$planLines.Add("- VM: " + $VmName)
$planLines.Add("- Snapshot: " + $SnapshotName)
$planLines.Add("- Shared folder: " + $SharedDir)
$planLines.Add("- Agents: $($agents -join ', ')")
$planLines.Add("- Mode: $(if ($RunRealInstall) { 'dry-run + real install' } else { 'dry-run only' })")
$planLines.Add("")
$planLines.Add("## Manual fallback")
$planLines.Add("")
$planLines.Add("If guestcontrol credentials are not available, copy each package folder from \\VBOXSVR\CCDeployPackage to the VM desktop and run:")
$planLines.Add("")
foreach ($agentId in $agents) {
    $package = "$agentId-windows-v0.1.0"
    $installArgs = Get-InstallArgs $agentId
    $planLines.Add("### $agentId")
    $planLines.Add("")
    $planLines.Add('```powershell')
    $planLines.Add(('cd "{0}"' -f $package))
    $planLines.Add("powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun")
    if ($RunRealInstall) {
        $planLines.Add(("powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 {0}" -f $installArgs).Trim())
        $verifyCommand = Get-VerifyCommand $agentId
        $planLines.Add($verifyCommand)
    }
    $planLines.Add('```')
    $planLines.Add("")
}
Write-TextFile (Join-Path $resultsDir "PLAN.md") ($planLines -join "`r`n")

$buildOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "tools\build-windows-agent-packages.ps1") -Root $Root -SharedDir $SharedDir 2>&1
$buildExit = $LASTEXITCODE
$buildOutput | Out-Host
if ($buildExit -ne 0) {
    Write-TextFile (Join-Path $resultsDir "build-windows-agent-packages-failed.txt") (($buildOutput | ForEach-Object { [string]$_ }) -join "`r`n")
    throw "Windows package build failed before VM checks. See $resultsDir"
}

if ($PlanOnly) {
    Write-Host "Plan written to: $resultsDir" -ForegroundColor Green
    exit 0
}

if (-not $GuestUser -or -not $GuestPasswordFile) {
    Write-Host "Guest credentials not provided; wrote manual plan only: $resultsDir" -ForegroundColor Yellow
    exit 0
}

if ($RestoreSnapshot) {
    Write-Host "Restoring snapshot $SnapshotName on $VmName..." -ForegroundColor Yellow
    Invoke-VBox -Args @("controlvm", $VmName, "poweroff") -OutFile (Join-Path $resultsDir "00-poweroff.txt") | Out-Null
    Start-Sleep -Seconds 3
    $restore = Invoke-VBox -Args @("snapshot", $VmName, "restore", $SnapshotName) -OutFile (Join-Path $resultsDir "01-restore-snapshot.txt")
    if ($restore.ExitCode -ne 0) { throw "Snapshot restore failed. See $resultsDir" }
    $start = Invoke-VBox -Args @("startvm", $VmName, "--type", "gui") -OutFile (Join-Path $resultsDir "02-startvm.txt")
    if ($start.ExitCode -ne 0) { throw "VM start failed. See $resultsDir" }
    Start-Sleep -Seconds 20
}

foreach ($agentId in $agents) {
    $package = "\\VBOXSVR\CCDeployPackage\$agentId-windows-v0.1.0"
    $dryRunCommand = "& '$package\install.ps1' -DryRun"
    $dryRun = Invoke-GuestPowerShell $dryRunCommand (Join-Path $resultsDir "$agentId-dry-run.txt")
    if ($dryRun.ExitCode -ne 0) { throw "$agentId dry-run failed. See $resultsDir" }

    if ($RunRealInstall) {
        $installArgs = Get-InstallArgs $agentId
        $installCommand = ("& '$package\install.ps1' {0}" -f $installArgs).Trim()
        $install = Invoke-GuestPowerShell $installCommand (Join-Path $resultsDir "$agentId-install.txt")
        if ($install.ExitCode -ne 0) { throw "$agentId install failed. See $resultsDir" }

        $verify = Invoke-GuestPowerShell (Get-VerifyCommand $agentId) (Join-Path $resultsDir "$agentId-verify.txt")
        if ($verify.ExitCode -ne 0) { throw "$agentId verify failed. See $resultsDir" }
    }
}

Write-Host "Windows VM agent checks complete. Results: $resultsDir" -ForegroundColor Green
