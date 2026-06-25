# DeepSeek Provider Research

This note records the current upstream evidence for DeepSeek/provider integration. It is not a pass/fail result by itself.

## DeepSeek API

- DeepSeek documents OpenAI/Anthropic-compatible access.
- OpenAI-compatible chat example uses `https://api.deepseek.com/chat/completions` with `Authorization: Bearer ${DEEPSEEK_API_KEY}` and model names such as `deepseek-v4-pro`.
- Source: https://api-docs.deepseek.com/

## Claude Code

- Current Windows v3.2.3 and macOS v0.1.0 wrappers use DeepSeek's Anthropic-compatible endpoint.
- Release gate is install, config write, and `claude -p 'Reply with exactly OK'`.
- Windows v3.2.3 has passed a clean VM user test. macOS Claude Code hosted/real-Mac smoke is still pending.

## Codex

- Codex supports custom model providers with `model_provider`, provider `base_url`, and `env_key`.
- Current Codex documentation emphasizes provider wire/API shape, including custom providers and Responses API behavior.
- DeepSeek's public examples are OpenAI/Anthropic-compatible, but the exact Codex + DeepSeek direct path must be tested before being marked release-level.
- Sources:
  - https://developers.openai.com/codex/config-advanced
  - https://developers.openai.com/codex/config-reference

## OpenClaw

- OpenClaw has first-class DeepSeek provider documentation.
- Official DeepSeek provider docs list provider `deepseek`, auth `DEEPSEEK_API_KEY`, API style `OpenAI-compatible`, and base URL `https://api.deepseek.com`.
- OpenClaw documents both interactive onboarding and non-interactive setup:
  - `openclaw onboard --auth-choice deepseek-api-key`
  - `openclaw onboard --non-interactive --mode local --auth-choice deepseek-api-key --deepseek-api-key "$DEEPSEEK_API_KEY" --skip-health --accept-risk`
- Model availability can be checked with `openclaw models list --provider deepseek`.
- Source: https://docs.openclaw.ai/providers/deepseek

## Cursor

- Current Windows package installs Cursor desktop as the native Windows route.
- Cursor Agent CLI official installer supports macOS/Linux, not Windows Git Bash, based on observed runner failure.
- DeepSeek API-key support in Cursor desktop is not currently proven for our package. Cursor community guidance says DeepSeek custom models may be added manually, while direct DeepSeek API keys may not be officially supported in Cursor Settings > Models > API Keys.
- Treat Cursor DeepSeek conversation validation as a GUI/manual gate until a supported CLI or configuration file path is confirmed.
- Source for current community guidance: https://forum.cursor.com/t/deepseek-models-in-cursor-through-api-key-or-add-model/147930

## Implementation Priority

1. OpenClaw DeepSeek configuration is the most concrete next automation target.
2. Codex DeepSeek configuration needs a small proof-of-compatibility test before writing installer behavior.
3. Cursor DeepSeek configuration should remain manual/GUI until a stable supported automation path is confirmed.
