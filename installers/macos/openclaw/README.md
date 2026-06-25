# OpenClaw macOS Installer

Status: online wrapper, not a fully offline release package.

This installer wraps the official OpenClaw macOS installer, verifies `openclaw --version`, and can optionally run the DeepSeek provider/conversation gate.

## Run

```bash
DRY_RUN=1 bash install.sh
bash install.sh
```

Optional DeepSeek provider and conversation smoke:

```bash
export DEEPSEEK_API_KEY="sk-..."
CONFIGURE_DEEPSEEK=1 bash install.sh
RUN_DEEPSEEK_SMOKE=1 bash install.sh
unset DEEPSEEK_API_KEY
```

If `DEEPSEEK_API_KEY` is not set, the installer prompts for the key with hidden input. Do not paste keys into logs, screenshots, Git history, or chat.
