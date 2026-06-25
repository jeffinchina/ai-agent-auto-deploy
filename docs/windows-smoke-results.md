# Windows Smoke Results

GitHub Actions `workflow_dispatch` can run real online smoke checks on `windows-2025`.

These checks are stronger than host static/dry-run checks, but they are still ephemeral runner checks. Final release acceptance for user-facing packages should also include the local `CCDeploy-Win11-Test` clean VM flow.

## Results

| Agent | Run | Result | Notes |
| --- | --- | --- | --- |
| Codex | `28138248652` | Fail | Official installer completed, but current PowerShell process could not find `codex`; added process PATH refresh before verification. |
| Codex | `28138374078` | Pass | `codex --version` and `codex doctor` verification passed after process PATH refresh. |
| OpenClaw | `28138408131` | Fail | Official installer completed, but wrapper tried to execute the generated command shim as a native executable. |
| OpenClaw | `28143299443` | Pass | Verification now refreshes PATH and invokes `openclaw --version` through PowerShell command semantics. |
| Cursor | `28138408411` | Fail | Cursor Agent official bash installer reported `Unsupported operating system: MINGW64_NT-10.0-26100`. |
| Cursor | `28143299476` | Pass | Windows smoke now validates the native Cursor desktop path via `winget install --id Anysphere.Cursor`; Cursor Agent CLI remains a WSL2/macOS/Linux path. |

## Artifacts

Manual Windows smoke runs upload an artifact named `windows-smoke-<agent>-<run_id>`. It contains:

- `SUMMARY.md` with agent, commit, runner, and timestamp.
- installer log files copied from `installers/windows/*/logs`.

Do not paste artifacts publicly without checking them first. Installer logs are intended to be sanitized by the wrapper scripts, but they may still reveal runner paths, package versions, or upstream installer output.

## Current Boundary

Windows runner smoke is useful for proving online installer behavior on a real Windows runner. It does not replace the VirtualBox `clean-base` test, because the GitHub runner already has developer tooling and is not a typical fresh user machine.

Cursor has an additional boundary: the official Cursor Agent bash installer currently supports Linux and macOS, not Windows Git Bash. The Windows package therefore treats Cursor desktop installation as the native Windows route, and WSL2 as the CLI route.
