# Cursor Windows Installer

Status: conservative online wrapper, not a fully offline release package.

Cursor desktop is the native Windows path and is installed through `winget`.

Cursor Agent CLI's official bash installer currently supports Linux/macOS, not Windows Git Bash. For CLI usage on Windows, use WSL2 and run the official installer inside the Linux environment.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDesktop -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDesktop
```

WSL2/Linux CLI note:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallCliWithBash
```

The CLI flag fails early on Windows Git Bash with a clear message instead of pretending that Cursor Agent CLI is supported there.

## Verification

Open a fresh PowerShell after installation:

```powershell
Test-Path "$env:LOCALAPPDATA\Programs\Cursor\Cursor.exe"
```

For WSL2/Linux CLI installs, verify inside WSL:

```bash
cursor-agent --version
```

Test harnesses can run verification without installing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -VerifyOnly
```

Clean Windows VM real install validation is still pending.
