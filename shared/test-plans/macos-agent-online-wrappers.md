# macOS Agent Online Wrapper Test Plan

This plan covers the macOS Claude Code, Codex, OpenClaw, and Cursor online wrapper scripts.

Windows-hosted macOS VMs are not a supported release baseline. Use GitHub Actions macOS runners for repeatable CI and a real Mac or cloud Mac for release acceptance.

See `docs/macos-virtual-environment.md` for the human-test environment recommendation.

## Windows Host Gate

Windows can verify repository structure and packaging only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-all-installers.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-macos-agent-packages.ps1
```

This proves package folders can be generated. It does not prove the installers work on macOS.

## GitHub Actions macOS Gate

Run on explicit macOS runners:

- `macos-15` or newer for current Apple Silicon coverage.
- An Intel runner if x64 behavior matters for a release.

Required checks:

- `bash -n` for every `install.sh`.
- `DRY_RUN=1 bash install.sh` for every package.
- no-secret scan over scripts and docs.
- package build artifact generation.

The repository workflow also has a manual `workflow_dispatch` smoke entry. Select one agent with `macos_smoke_agent`. This intentionally does not run on every push because it performs real online installs on an ephemeral GitHub macOS runner. Claude Code smoke requires a repository secret named `DEEPSEEK_API_KEY`.

## Real Mac Release Gate

Before publishing a macOS package, verify on a real Mac or cloud Mac:

- Gatekeeper and first-launch prompts.
- shell profile/PATH changes in a fresh terminal.
- CLI `--version` or `doctor`.
- login/onboarding flow.
- uninstall/reset notes.
- upgrade from previous package, once previous packages exist.

OpenClaw DeepSeek release gate:

```bash
export DEEPSEEK_API_KEY="sk-..."
CONFIGURE_DEEPSEEK=1 bash install.sh
RUN_DEEPSEEK_SMOKE=1 bash install.sh
unset DEEPSEEK_API_KEY
```

Claude Code also performs a DeepSeek conversation smoke when run with a key. Codex and Cursor still need separate provider-path implementation before they can be marked release-level.

## Current Status

- Shell syntax checks: automated in CI.
- Dry-run checks: automated in CI.
- Package zip, manifest, SHA256, and extracted file checks: automated on Windows.
- GitHub macOS hosted smoke: passed for Codex, OpenClaw, and Cursor; pending for Claude Code because the full smoke needs a runtime DeepSeek key.
- Real macOS install smoke tests: pending.
- Real Mac first-use tests: pending.
