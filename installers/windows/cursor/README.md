# Cursor Windows Installer

Status: conservative online wrapper, not a fully offline release package.

Cursor CLI's official installer is a bash script. On Windows this means Git Bash or WSL is required for CLI installation. The desktop app is documented but not silently installed yet.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallCliWithBash
```

Desktop note:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDesktop
```

The desktop flag currently fails with a clear message instead of pretending to install the app.

## Verification

Open a fresh PowerShell after installation:

```powershell
cursor-agent --version
```

If the command is missing, confirm Git Bash or WSL was installed before running the CLI installer.

Clean Windows VM real install validation is still pending.
