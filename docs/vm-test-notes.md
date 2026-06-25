# Windows VM Test Notes

## Baseline

- Hypervisor: Oracle VirtualBox 7.2
- VM: `CCDeploy-Win11-Test`
- OS: Windows 11 Home zh-CN
- Snapshot: `clean-base`

`clean-base` means Windows has finished installation and entered the desktop, but the deploy script has not been run. It should not contain:

- Node.js installed by this project
- Claude Code installed by this project
- PortableGit installed by this project
- `%USERPROFILE%\.claude\settings.json`
- CcSwitch installed by this project

## v3.2.2 Result

The v3.2.2 package was validated on the clean VM:

- Node.js offline install succeeded.
- Claude Code offline install succeeded.
- PortableGit runtime setup fixed the Windows launch blocker.
- DeepSeek API key validation succeeded.
- `claude -p "Reply with exactly OK"` returned `OK`.

## v3.2.3 Result

The v3.2.3 package was tested on the clean VM and the user reported success after entering a real DeepSeek API key manually.

- Package copied to host shared folder: `D:\VMs\CCDeployTest\Shared\把这个文件夹拷到待安装的电脑_V3.2.3`
- ZIP SHA256: `9B7D4CD8B69349359928D3EC7356F1E6D2EA391CB4E042B2284AA7F2AEA6CCDF`
- Host-side package self-check passed: parser, version sync, manifest hashes, key leak scan, hardening checks.
- DeepSeek API minimal check passed once with user-provided key; no key was written to files or logs.
- Fresh PowerShell could start Claude Code after the runtime dependency fix.

Remaining improvement: capture a structured test artifact during the next clean VM run, such as sanitized logs and screenshots, so release evidence does not rely only on chat history.

## Windows Agent Online Wrapper Status

Generated host-side packages are available in:

- `C:\Users\65295\ai-agent-auto-deploy\dist\windows`
- `D:\VMs\CCDeployTest\Shared`

These packages currently have static, dry-run, package, manifest, and SHA256 verification only. Clean VM real install validation is still pending for:

- Codex Windows
- OpenClaw Windows
- Cursor Windows

GitHub Actions can also run manual Windows runner smoke checks for these online wrappers. See `docs/windows-smoke-results.md`. This is useful evidence, but it does not replace the clean VM test because GitHub runners already include developer tooling.

To generate a structured test plan and, when guest credentials are available, run guestcontrol-based checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-windows-vm-agent-tests.ps1 -PlanOnly
```

With a guest password file stored outside this repository, dry-run checks can be executed inside the VM:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-windows-vm-agent-tests.ps1 -GuestUser codex -GuestPasswordFile C:\path\outside\repo\guest-password.txt
```

Real install checks mutate the VM and should be run after restoring `clean-base`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-windows-vm-agent-tests.ps1 -GuestUser codex -GuestPasswordFile C:\path\outside\repo\guest-password.txt -RestoreSnapshot -RunRealInstall
```

## Automation Note

VirtualBox Guest Additions are installed and the VM has a logged-in `codex` user, but `VBoxManage guestcontrol` requires a valid guest username/password. Without that credential, clean VM installs must be performed manually or through visible UI automation.

## Known VM Notes

- Guest shutdown can hang in VirtualBox on this host. Use snapshot restore for repeatable tests.
- Keep API keys out of logs, screenshots, GitHub Issues, and chat transcripts.
