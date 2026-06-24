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

## v3.2.3 Status

Prepared for clean VM validation:

- Package copied to host shared folder: `D:\VMs\CCDeployTest\Shared\把这个文件夹拷到待安装的电脑_V3.2.3`
- ZIP SHA256: `9B7D4CD8B69349359928D3EC7356F1E6D2EA391CB4E042B2284AA7F2AEA6CCDF`
- VM restored to `clean-base` and booted to desktop.
- Host-side package self-check passed: parser, version sync, manifest hashes, key leak scan, hardening checks.
- DeepSeek API minimal check passed once with user-provided key; no key was written to files or logs.

Manual validation still required:

- Run `一键部署.cmd` inside the VM from the V3.2.3 package.
- Enter a real DeepSeek API Key manually.
- Confirm Phase 6 reports both `claude --version` and DeepSeek conversation verification as passed.
- Open a fresh PowerShell and run `claude`, then send a short prompt.

## Known VM Notes

- Guest shutdown can hang in VirtualBox on this host. Use snapshot restore for repeatable tests.
- Keep API keys out of logs, screenshots, GitHub Issues, and chat transcripts.
