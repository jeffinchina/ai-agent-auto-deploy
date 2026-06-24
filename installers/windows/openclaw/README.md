# OpenClaw Windows Installer

Status: online wrapper, not a fully offline release package.

This installer wraps the official OpenClaw Windows installer, writes local logs, and verifies `openclaw --version` where available.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Optional onboarding:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -RunOnboarding
```

## Verification

Open a fresh PowerShell after installation:

```powershell
openclaw --version
openclaw onboard
```

Clean Windows VM real install validation is still pending.
