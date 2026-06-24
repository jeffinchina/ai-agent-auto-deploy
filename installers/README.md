# Installers

Future OS and agent-specific installers will live here.

Planned layout:

```text
installers/
  windows/
    claude-code/
    codex/
    openclaw/
    cursor/
  macos/
    claude-code/
    codex/
    openclaw/
    cursor/
```

The current production Windows Claude installer is still the root `deploy.ps1`. Move it here only after v3.2.x has passed repeatable VM validation.

## Current State

The first cross-agent installers are online installers:

- `windows/codex/install.ps1`
- `macos/codex/install.sh`
- `windows/openclaw/install.ps1`
- `macos/openclaw/install.sh`
- `windows/cursor/install.ps1`
- `macos/cursor/install.sh`
- `macos/claude-code/install.sh`

They are intentionally conservative. They verify platform, call official upstream installers, run basic version/doctor checks where available, and write logs locally. They are not yet offline release packages.

## Release Rule

Do not publish any new agent/OS package until it has:

- static parser checks
- no-secret scan
- clean VM or hosted runner smoke test
- real first-run verification
- documented rollback/uninstall behavior
