# macOS Smoke Results

GitHub Actions `workflow_dispatch` can run real online smoke checks on `macos-15`.

These checks are stronger than Windows-hosted static/dry-run checks, but they are still ephemeral runner checks. Final release acceptance should also include a real Mac or cloud Mac user-flow pass.

## Results

| Agent | Run | Result | Notes |
| --- | --- | --- | --- |
| Codex | `28137469599` | Pass | Official installer completed and wrapper verification passed on GitHub macOS runner. |
| Cursor | `28137494682` | Pass | Official installer completed and `cursor-agent`/`cursor` detection passed on GitHub macOS runner. |
| OpenClaw | `28137494636` | Fail | Wrapper used unsupported `--tag`; changed to official `--version` plus `--no-prompt`. Needs rerun after fix. |
| Claude Code | Not run | Pending | Requires repository secret `DEEPSEEK_API_KEY` and should be run manually to avoid accidental key/API use. |
