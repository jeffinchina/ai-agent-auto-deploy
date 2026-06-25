# Windows Smoke Results

GitHub Actions `workflow_dispatch` can run real online smoke checks on `windows-2025`.

These checks are stronger than host static/dry-run checks, but they are still ephemeral runner checks. Final release acceptance for user-facing packages should also include the local `CCDeploy-Win11-Test` clean VM flow.

## Results

| Agent | Run | Result | Notes |
| --- | --- | --- | --- |
| Codex | `28138248652` | Fail | Official installer completed, but current PowerShell process could not find `codex`; added process PATH refresh before verification. |
| OpenClaw | Not run | Pending | Manual Windows runner smoke entry added. |
| Cursor | Not run | Pending | Manual Windows runner smoke entry added; requires Git Bash on runner. |

## Artifacts

Manual Windows smoke runs upload an artifact named `windows-smoke-<agent>-<run_id>`. It contains:

- `SUMMARY.md` with agent, commit, runner, and timestamp.
- installer log files copied from `installers/windows/*/logs`.

Do not paste artifacts publicly without checking them first. Installer logs are intended to be sanitized by the wrapper scripts, but they may still reveal runner paths, package versions, or upstream installer output.

## Current Boundary

Windows runner smoke is useful for proving online installer behavior on a real Windows runner. It does not replace the VirtualBox `clean-base` test, because the GitHub runner already has developer tooling and is not a typical fresh user machine.
