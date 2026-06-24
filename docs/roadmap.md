# Roadmap

## Phase 1: Windows Stability

- Make install steps idempotent.
- Keep offline asset hash verification mandatory for release packages.
- Improve error messages for missing network, bad API keys, corrupted packages, missing runtime dependencies, and failed smoke tests.
- Require fresh-terminal Claude launch verification and minimal DeepSeek conversation verification before release.
- Add uninstall/reset support.
- Add automated smoke test scripts for Windows VM.

## Phase 2: Multi-provider Configuration

- Add provider profiles for DeepSeek, Qwen, GLM, Kimi, OpenRouter, and custom Anthropic-compatible endpoints.
- Keep direct Claude Code configuration as the stable default.
- Keep CcSwitch as an optional visual provider manager until the full proxy flow is proven reliable in VM tests.

## Phase 3: Multi-agent Adapter Model

Each agent should have a small adapter with the same lifecycle:

- detect
- install
- configure
- verify
- uninstall/reset

Candidate agents:

- Claude Code
- Codex CLI
- OpenClaw
- Cursor

## Phase 4: Multi-system Support

Do not force one giant cross-platform script. Prefer system-specific installers sharing common manifests:

- `windows/deploy.ps1`
- `macos/deploy.sh`
- `linux/deploy.sh`
- shared provider and asset manifests

## Phase 5: Release Experience

- Keep single-agent packages as the support-friendly default.
- Add an optional unified entry after individual packages are proven in VM tests.
- The unified entry should call the same tested modules, not duplicate installer logic.
