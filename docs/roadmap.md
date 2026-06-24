# Roadmap

## Phase 1: Windows Stability

- Make install steps idempotent.
- Add offline asset hash verification.
- Improve error messages for missing network, bad API keys, and corrupted packages.
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
- Gemini CLI
- Aider
- Cline/Roo Code helper setup

## Phase 4: Multi-system Support

Do not force one giant cross-platform script. Prefer system-specific installers sharing common manifests:

- `windows/deploy.ps1`
- `macos/deploy.sh`
- `linux/deploy.sh`
- shared provider and asset manifests
