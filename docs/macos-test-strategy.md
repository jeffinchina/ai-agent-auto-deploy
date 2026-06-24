# macOS Test Strategy

Do not use a Windows-hosted macOS VM as the project test baseline. It is not a stable or compliant way to validate installer releases.

## Recommended Test Layers

1. GitHub Actions macOS runners for repeatable PR and release checks.
2. A real Mac or cloud Mac for final release acceptance.
3. Optional macOS VM only on Apple hardware, using Apple-supported virtualization tooling.

## CI Gate

Use explicit runner labels for release gates instead of `macos-latest`:

- Apple Silicon runner, for arm64 behavior.
- Intel runner, for x64 behavior where required.

Required checks:

- shell syntax validation
- package build
- install smoke test
- CLI `--version` or `doctor` check
- uninstall or cleanup check
- upgrade-from-previous-release check
- no-secret scan

## Manual Release Gate

Before publishing a macOS release artifact, verify on a real Mac or cloud Mac:

- Gatekeeper behavior
- first launch prompts
- shell profile/PATH changes
- service or launchd registration, if any
- network/proxy behavior
- uninstall/reset
- upgrade from the previous public package

## Notes

Apple-supported virtualization belongs on Apple hardware. UTM, Parallels, VMware Fusion, and Apple Virtualization Framework are useful only within their supported host/guest boundaries. Avoid Hackintosh-style workflows and do not document bypass steps in this repository.
