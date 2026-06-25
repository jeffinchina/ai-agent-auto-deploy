# Windows Agent Online Wrapper Test Plan

This plan covers the Windows Codex, OpenClaw, and Cursor online wrapper packages.

These packages are not yet equivalent to the Claude Code Windows v3.2.3 offline package. Claude v3.2.3 bundles offline assets and has passed a real VM install. These wrappers call official upstream online installers and must pass clean-VM smoke tests before release.

The final release gate is stricter than command installation: each package must prove the intended provider setup and a minimal conversation through the actual agent path. At the moment, Codex/OpenClaw/Cursor Windows have hosted installation smoke evidence, but not clean VM DeepSeek conversation evidence.

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
3. Run the package-specific dry-run command below.
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

OpenClaw DeepSeek gate:

```powershell
$env:DEEPSEEK_API_KEY = "sk-..."
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -VerifyOnly -ConfigureDeepSeek
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -VerifyOnly -ConfigureDeepSeek -RunDeepSeekSmoke
Remove-Item Env:\DEEPSEEK_API_KEY
```

Cursor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDesktop -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDesktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -VerifyOnly -InstallDesktop
```

Cursor Agent CLI's official bash installer currently supports Linux/macOS, not Windows Git Bash. On Windows, treat WSL2 as the CLI route and native desktop as the Windows route.

## Provider And Conversation Gate

After the basic install succeeds, the package is still not release-level until the provider path is verified:

| Agent | Provider gate | Conversation gate |
| --- | --- | --- |
| Codex | Configure DeepSeek through Codex's supported custom provider model. | Run one minimal non-interactive prompt and save sanitized output. |
| OpenClaw | Run `install.ps1 -VerifyOnly -ConfigureDeepSeek` with a runtime `DEEPSEEK_API_KEY`. | Run `install.ps1 -VerifyOnly -ConfigureDeepSeek -RunDeepSeekSmoke` and save sanitized output. |
| Cursor | Configure DeepSeek through Cursor desktop settings unless a supported CLI path is confirmed. | Send one minimal GUI prompt and save sanitized screenshot/output. |

Do not paste or save API keys. Capture only sanitized logs and the final success/failure evidence.

## Pass Criteria

- Installer exits with code 0, or gives a clear dependency/error message that a normal user can act on.
- CLI agents: a fresh terminal can find the installed command.
- CLI agents: version or doctor command returns a recognizable success result.
- Desktop agents: the application is installed in a supported location and the package `-VerifyOnly` check passes.
- Logs exist and do not expose secrets.
- The README tells the user what to do next for login or first use.

## Current Status

- Host static checks: automated.
- GitHub Actions dry-run checks: automated.
- Package zip, manifest, SHA256, and extracted file checks: automated.
- GitHub Actions Windows runner smoke: passed for Codex, OpenClaw, and Cursor desktop.
- Clean Windows VM real installs: pending for Codex/OpenClaw/Cursor.
