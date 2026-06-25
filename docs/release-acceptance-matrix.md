# Release Acceptance Matrix

This matrix tracks the target release standard: install from a clean user environment, configure the intended provider, and prove a minimal conversation path.

## Evidence Levels

| Level | Meaning |
| --- | --- |
| Static | Parser, dry-run, manifest, zip/hash, and secret scan pass. |
| Hosted smoke | GitHub Actions runner performs a real online install and basic command verification. |
| Clean VM install | Local clean-base VM or equivalent fresh machine performs the install from the package. |
| Provider smoke | The package configures DeepSeek or another declared provider path. |
| Conversation smoke | A minimal prompt returns an expected result through the actual agent path. |

## Windows

| Package | Static | Hosted smoke | Clean VM install | Provider smoke | Conversation smoke | Current release status |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Code Windows v3.2.3 | Pass | N/A | Pass by user VM report | Pass, DeepSeek direct | Pass, `claude -p` returned usable response | Closest releasable baseline; still wants structured artifact capture. |
| Codex Windows v0.1.0 | Pass | Pass, run `28138374078` | Pending | LiteLLM bridge and Python bootstrap implemented; VM runner prepared | Pending bridge-backed `codex exec` on clean VM | Not release-level yet. |
| OpenClaw Windows v0.1.0 | Pass | Pass, run `28143299443` | Pending | Implemented in package; VM runner prepared | Implemented in package; pending clean VM run | Not release-level yet. |
| Cursor Windows v0.1.0 | Pass | Pass, run `28143299476` | Pending | Pending GUI/provider setup | Pending GUI prompt; VM runner records manual gate | Not release-level yet. |

## macOS

| Package | Static | Hosted smoke | Clean macOS VM / cloud Mac install | Provider smoke | Conversation smoke | Current release status |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Code macOS v0.1.0 | Pass | Pending; needs runtime DeepSeek key | Pending | Implemented in package, pending runner/real Mac run | Implemented in package, pending runner/real Mac run | Not release-level yet. |
| Codex macOS v0.1.0 | Pass | Pass, runs `28137469599`, `28137905077` | Pending | LiteLLM bridge config implemented, pending runner/real Mac run | Implemented in package, pending runner/real Mac run | Not release-level yet. |
| OpenClaw macOS v0.1.0 | Pass | Pass, run `28137681835` | Pending | Implemented in package, pending runner/real Mac run | Implemented in package, pending runner/real Mac run | Not release-level yet. |
| Cursor macOS v0.1.0 | Pass | Pass, run `28137494682` | Pending | Pending provider setup | Pending | Not release-level yet. |

## Immediate Gates

1. Run Codex/OpenClaw/Cursor Windows packages manually, through the guest-side runner, or through `VBoxManage guestcontrol` on `CCDeploy-Win11-Test` restored to `clean-base`.
2. Run Codex/OpenClaw hosted DeepSeek smoke with a repository `DEEPSEEK_API_KEY` secret where implemented, then repeat on clean VM / real Mac.
3. For macOS, use GitHub macOS runners for hosted smoke and a real Mac/cloud Mac for interactive release acceptance. A Windows-hosted macOS VM is not the release baseline.
4. Never store API keys in the repository, artifacts, screenshots, command history, or chat logs. Use hidden input locally or a short-lived GitHub secret for runner-only tests.

See `docs/provider-deepseek-research.md` before implementing or marking any non-Claude DeepSeek provider gate as complete.
