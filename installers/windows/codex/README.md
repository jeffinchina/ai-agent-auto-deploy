# Codex Windows Installer

Status: online wrapper, not a fully offline release package.

This installer wraps the official OpenAI Codex CLI installer, writes local logs, and verifies `codex --version` plus `codex doctor` where available.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Optional desktop app attempt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDesktopApp
```

## Verification

Open a fresh PowerShell after installation:

```powershell
codex --version
codex doctor
```

First use normally requires:

```powershell
codex login
```

Clean Windows VM real install validation is still pending.
