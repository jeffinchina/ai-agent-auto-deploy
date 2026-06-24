# Installer Framework Draft

This project should grow as a set of small installers that share one framework, not as one giant script.

## Shape

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
shared/
  manifests/
  providers/
  test-plans/
```

Keep the current root `deploy.ps1` until the Claude Windows package is fully stable. Move only after v3.2.x has a repeatable VM test story.

## Common Lifecycle

Every agent installer should implement the same lifecycle:

1. `detect`: OS, CPU architecture, existing installation, network, permissions.
2. `verify-assets`: manifest presence, SHA256, archive readability, required asset set.
3. `install-runtime`: Node, Git Bash, PowerShell 7, shell tools, package manager, or app runtime.
4. `install-agent`: agent CLI/app install.
5. `configure-provider`: API endpoint, model, auth token, provider profile.
6. `verify-agent`: version check and real minimal conversation or launch smoke test.
7. `finish`: PATH/shell profile, shortcuts, user guide, log summary.
8. `reset`: uninstall project-owned files and restore config backups.

## Package Matrix

Build and test in this order:

| Package | Windows | macOS | Notes |
| --- | --- | --- | --- |
| Claude Code | first | second | Keep DeepSeek direct as stable default; CcSwitch remains optional. |
| Codex | after Claude | after Claude | Use official install path and provider model once requirements are clear. |
| OpenClaw | after Codex | after Codex | Confirm actual upstream packaging before designing automation. |
| Cursor | after OpenClaw | after OpenClaw | More app-like than CLI-like; verification should include launch/config smoke test. |

## Release Forms

Support both:

- Single package: one installer for one agent and one OS, easiest for users and support.
- Unified entry: a menu that lets users choose OS-compatible agents and providers, useful after single packages are proven.

Do not make the unified entry the source of truth. It should call the same tested package modules.

## Verification Rules

- Never hardcode real API keys in tests.
- VM tests should start from a named clean snapshot.
- A package is not releasable until parser checks, manifest hashes, install smoke test, provider smoke test, and fresh-terminal launch all pass.
- Logs must redact `sk-...` tokens.
- If a provider supports multiple API styles, verify the exact style used by the target agent, not only a nearby endpoint.

## Online vs Offline Installers

Use online installers for first integration and discovery. Promote a package to offline distribution only after the online path has passed real VM or hosted runner tests and its required assets can be pinned with hashes.
