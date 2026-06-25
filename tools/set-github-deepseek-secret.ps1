#Requires -Version 5.1
param(
    [string]$Repo = "jeffinchina/ai-agent-auto-deploy",
    [string]$SecretName = "DEEPSEEK_API_KEY"
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) { throw "[FAIL] $Message" }

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Fail "GitHub CLI (gh) is required. Install gh and run 'gh auth login' first."
}

Write-Host "This will store $SecretName as a GitHub Actions repository secret for $Repo." -ForegroundColor Cyan
Write-Host "Input is hidden. The value is piped to gh via stdin and is not written to disk." -ForegroundColor Yellow

$secure = Read-Host "DeepSeek API Key" -AsSecureString
$bstr = [IntPtr]::Zero
$plain = $null
try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if (-not $plain -or $plain -notlike "sk-*") {
        Fail "DeepSeek API Key must start with sk-."
    }

    $plain | & $gh.Source secret set $SecretName --repo $Repo
    if ($LASTEXITCODE -ne 0) {
        Fail "gh secret set failed."
    }
    Write-Host "[OK] GitHub secret stored: $SecretName" -ForegroundColor Green
} finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $plain = $null
    Remove-Variable plain -ErrorAction SilentlyContinue
}
