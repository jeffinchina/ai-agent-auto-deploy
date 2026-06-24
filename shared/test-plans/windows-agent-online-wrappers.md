# Windows Agent Online Wrapper Test Plan

This plan covers the Windows Codex, OpenClaw, and Cursor online wrapper packages.

These packages are not yet equivalent to the Claude Code Windows v3.2.3 offline package. Claude v3.2.3 bundles offline assets and has passed a real VM install. These wrappers call official upstream online installers and must pass clean-VM smoke tests before release.

## Static Gate

Run on the host before touching a VM:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-all-installers.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-windows-agent-packages.ps1
```

Expected:

- PowerShell scripts parse.
- Every Windows installer passes `-DryRun`.
- Package folders contain `install.ps1`, `run.cmd`, `README.md`, and upstream notes.
- `windows-agent-packages.json` contains each package and SHA256 for each zip.
- Secret scan finds no obvious API keys.

## Clean VM Gate

Use `CCDeploy-Win11-Test` restored to `clean-base`.

Copy or use the packages from:

```text
\\VBOXSVR\CCDeployPackage
```

For each package:

1. Copy the package folder to the VM desktop.
2. Open PowerShell in that folder.
3. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun`.
4. Run the real install command.
5. Close PowerShell and open a fresh PowerShell.
6. Run the package-specific verification command below.
7. Save the installer `logs` folder before restoring the snapshot.

When VirtualBox guest credentials are available, the host-side coordinator can generate a plan and run guestcontrol checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-windows-vm-agent-tests.ps1 -PlanOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-windows-vm-agent-tests.ps1 -GuestUser codex -GuestPasswordFile C:\path\outside\repo\guest-password.txt
```

## Package Verification

Codex:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
codex --version
codex doctor
```

OpenClaw:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
openclaw --version
```

Cursor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallCliWithBash
cursor-agent --version
```

Cursor CLI requires Git Bash or WSL. If the clean VM does not have either, that is a product dependency finding, not a test pass.

## Pass Criteria

- Installer exits with code 0, or gives a clear dependency/error message that a normal user can act on.
- A fresh terminal can find the installed command.
- Version command returns a recognizable version string.
- Logs exist and do not expose secrets.
- The README tells the user what to do next for login or first use.

## Current Status

- Host static checks: automated.
- GitHub Actions dry-run checks: automated.
- Package zip, manifest, SHA256, and extracted file checks: automated.
- Clean Windows VM real installs: pending for Codex/OpenClaw/Cursor.
