# macOS Smoke Results

GitHub Actions `workflow_dispatch` can run real online smoke checks on `macos-15`.

These checks are stronger than Windows-hosted static/dry-run checks, but they are still ephemeral runner checks. Final release acceptance should also include a real Mac or cloud Mac user-flow pass.

## Results

| Agent | Run | Result | Notes |
| --- | --- | --- | --- |
| Codex | `28137469599` | Pass | Official installer completed and wrapper verification passed on GitHub macOS runner. |
| Cursor | `28137494682` | Pass | Official installer completed and `cursor-agent`/`cursor` detection passed on GitHub macOS runner. |
| OpenClaw | `28137494636` | Fail | Wrapper used unsupported `--tag`; changed to official `--version` plus `--no-prompt`. |
| OpenClaw | `28137681835` | Pass | Fixed wrapper completed official installer and verification on GitHub macOS runner. |
| Claude Code | Not run | Pending | Requires repository secret `DEEPSEEK_API_KEY` and should be run manually to avoid accidental key/API use. |

## Current Boundary

Codex, Cursor, and OpenClaw have passed real online smoke checks on GitHub's macOS runner. Claude Code macOS is still pending because the smoke test needs a DeepSeek API key and should not persist user-provided keys into repository secrets without an explicit release-testing decision.

These runner checks do not replace final real-Mac acceptance for Gatekeeper prompts, fresh Terminal behavior, or desktop-app first launch.

## Artifacts

New manual macOS smoke runs upload an artifact named `macos-smoke-<agent>-<run_id>`. It contains:

- `SUMMARY.md` with agent, commit, runner, and timestamp.
- installer log files copied from `installers/macos/*/logs`.

Do not paste artifacts publicly without checking them first. Installer logs are intended to be sanitized by the wrapper scripts, but they may still reveal runner paths, package versions, or provider output.
