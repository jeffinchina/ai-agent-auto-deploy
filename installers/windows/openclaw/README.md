# OpenClaw Windows Installer

Status: online wrapper, not a fully offline release package.

This installer wraps the official OpenClaw Windows installer, writes local logs, and verifies `openclaw --version` where available.

It can also run an explicit DeepSeek release gate when requested:

- configure OpenClaw with a DeepSeek API key
- verify the DeepSeek model catalog
- optionally run one minimal DeepSeek model call

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Optional onboarding:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -RunOnboarding
```

Optional DeepSeek provider and conversation smoke:

```powershell
$env:DEEPSEEK_API_KEY = "sk-..."
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ConfigureDeepSeek
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ConfigureDeepSeek -RunDeepSeekSmoke
Remove-Item Env:\DEEPSEEK_API_KEY
```

If `DEEPSEEK_API_KEY` is not set, the installer prompts for the key with hidden input. Do not paste keys into logs, screenshots, Git history, or chat.

## Verification

Open a fresh PowerShell after installation:

```powershell
openclaw --version
openclaw onboard
openclaw models list --provider deepseek --plain
```

Test harnesses can run verification without installing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -VerifyOnly
```

Clean Windows VM real install validation is still pending.
