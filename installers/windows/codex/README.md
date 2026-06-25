# Codex Windows Installer

Status: online wrapper, not a fully offline release package.

This installer wraps the official OpenAI Codex CLI installer, writes local logs, and verifies `codex --version` plus `codex doctor` where available.

DeepSeek is not configured by direct endpoint because current Codex custom providers expect the OpenAI Responses API. DeepSeek's public API is OpenAI Chat Completions/Anthropic-compatible, so this package prepares a LiteLLM Responses bridge instead.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Optional desktop app attempt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDesktopApp
```

Optional DeepSeek LiteLLM bridge preparation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -PrepareDeepSeekLiteLLM
```

This writes:

- `%USERPROFILE%\.codex\config.toml`
- `%LOCALAPPDATA%\CodexDeepSeekLiteLLM\litellm-config.yaml`
- `%LOCALAPPDATA%\CodexDeepSeekLiteLLM\start-litellm-deepseek.ps1`

To install LiteLLM proxy as well, Python 3.10+ must already be available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -PrepareDeepSeekLiteLLM -InstallLiteLLMProxy
```

The generated files reference `DEEPSEEK_API_KEY` by environment variable and do not store the real key.

## Verification

Open a fresh PowerShell after installation:

```powershell
codex --version
codex doctor
```

First use normally requires:

```powershell
codex login
```

Test harnesses can run verification without installing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -VerifyOnly
```

Clean Windows VM real install validation is still pending.
