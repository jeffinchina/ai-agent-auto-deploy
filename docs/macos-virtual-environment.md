# macOS Test Environment Plan

The macOS release gate needs a real macOS environment. A Windows-hosted macOS VM is not a reliable or supported baseline for this project.

## Recommended Layers

| Layer | Use | Notes |
| --- | --- | --- |
| GitHub Actions `macos-15` / `macos-26` runner | Repeatable CI smoke | Best for install scripts, command verification, and sanitized artifacts. Not enough for GUI prompts or first-launch acceptance. |
| Real Mac with local VM | Human acceptance | Best user-flow match. Use UTM, Parallels, VirtualBuddy, or Apple Virtualization Framework on Apple hardware. Apple Silicon macOS guests can have snapshot/restore limitations, so keep a clean VM clone or clean user reset recipe. |
| Cloud Mac | Remote human/agent acceptance | Use when no physical Mac is available. Prefer MacStadium/Orka-style VM images if snapshot/reset matters; AWS EC2 Mac is useful for bare-metal access but has a 24-hour minimum host allocation. |

## Practical Recommendation

Use this order:

1. Keep GitHub Actions as the fast repeatable layer. Run normal hosted smoke for every agent; run DeepSeek smoke only through a repository secret and only when needed.
2. For release acceptance, rent or use an Apple-hardware Mac environment rather than a Windows-hosted macOS VM.
3. If you own or can borrow an Apple Silicon Mac, use VirtualBuddy or UTM for simple clean macOS guest testing. Because snapshot support can be limited for macOS guests, create a clean base VM, shut it down, and duplicate the VM bundle before each agent test.
4. If you need a cloud path, prefer a provider that gives resettable macOS VM images. MacStadium/Orka is the best fit for repeated installer QA. AWS EC2 Mac is acceptable for one-off bare-metal testing, but budget for the 24-hour minimum.

Useful references:

- GitHub-hosted macOS runner docs: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- GitHub `macos-26` runner availability: https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/
- AWS EC2 Mac 24-hour minimum allocation: https://aws.amazon.com/ec2/instance-types/mac/
- AWS EC2 Mac user guide: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-mac-instances.html
- MacStadium macOS virtualization overview: https://support.macstadium.com/hc/en-us/articles/39227685958043-MacStadium-Overview

## Why Not a Windows-Hosted macOS VM

For release evidence, do not treat a macOS VM running on a Windows PC as equivalent to a user Mac. It is difficult to keep legally and technically reliable, and it can hide issues around Apple Silicon, Gatekeeper, shell profiles, Keychain, and desktop first-launch prompts.

Apple's current macOS software license is for Apple-branded systems and permits additional virtualized copies on Apple-branded computers you own or control for development/testing-style uses. It also says the grant does not permit running the Apple software on non-Apple-branded computers. See Apple's macOS Software License Agreement: https://www.apple.com/legal/sla/

GitHub-hosted runners are useful CI evidence because GitHub documents each standard hosted runner as a new VM, and provides macOS runner labels such as `macos-15`. They are still not a substitute for real first-launch user acceptance. See GitHub runner docs: https://docs.github.com/en/actions/reference/runners/github-hosted-runners

## Manual Mac Acceptance Flow

For each package:

1. Start from a clean macOS user or restored clean VM snapshot.
2. Copy the package zip from `dist/macos` or the shared release folder.
3. Unzip it and open Terminal in the package folder.
4. Run `DRY_RUN=1 bash install.sh`.
5. Run `bash install.sh`.
6. Open a fresh Terminal.
7. Run the package-specific command:

| Package | Basic verification | Provider/conversation verification |
| --- | --- | --- |
| Claude Code | `claude --version` | Enter DeepSeek key when prompted; installer already runs `claude -p 'Reply with exactly OK'`. |
| Codex | `codex --version`, `codex doctor` | Use `PREPARE_DEEPSEEK_LITELLM=1 INSTALL_LITELLM_PROXY=1 bash install.sh`, then `RUN_DEEPSEEK_SMOKE=1 bash install.sh` with a runtime key. |
| OpenClaw | `openclaw --version` | Use `CONFIGURE_DEEPSEEK=1 bash install.sh`, then `RUN_DEEPSEEK_SMOKE=1 bash install.sh` with a runtime key. |
| Cursor | `cursor-agent --version` or `cursor` detection | Pending provider setup and minimal prompt verification. |

## Evidence To Save

- Sanitized installer log folder.
- Terminal output showing version/doctor result.
- For GUI tools, a sanitized screenshot after the minimal prompt succeeds.
- macOS version, CPU architecture, package zip hash, and date.

Do not save API keys in screenshots, logs, shell history, or issue comments.
