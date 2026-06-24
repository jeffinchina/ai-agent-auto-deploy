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

## Known VM Notes

- Guest shutdown can hang in VirtualBox on this host. Use snapshot restore for repeatable tests.
- Keep API keys out of logs, screenshots, GitHub Issues, and chat transcripts.
