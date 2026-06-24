# Changelog

## v3.2.3 - 2026-06-24

- Added Windows x64, disk space, install directory, and log directory preflight checks.
- Enforced `assets/manifest.json` SHA256 verification before install.
- Split installer progress into 7 phases, with a dedicated Claude launch and DeepSeek conversation verification phase.
- Added hidden DeepSeek API Key input and log redaction for `sk-...` tokens.
- Always configures Git Bash / PortableGit for Claude Code on Windows, even when PowerShell 7 exists.
- Preserves existing non-managed Claude Code environment variables in `%USERPROFILE%\.claude\settings.json`.
- Added `tests/verify-windows-package.ps1` package self-check.
- Hardened process argument quoting, PortableGit extraction paths, strict `OK` smoke-test handling, and npm offline install flags after independent review.

## v3.2.2 - 2026-06-24

- Added PortableGit runtime setup for clean Windows machines.
- Automatically configures `CLAUDE_CODE_GIT_BASH_PATH` for Claude Code.
- Expanded installer progress from 5 phases to 6 phases.
- Verified on a clean Windows 11 Home VirtualBox VM.
- Fixed final CcSwitch instruction text quoting.

## v3.2.1 - 2026-06-18

- Stable DeepSeek direct connection flow.
- Offline Node.js and Claude Code installation.
- Optional CcSwitch installation.
- Writes Claude Code settings to `%USERPROFILE%\.claude\settings.json`.
