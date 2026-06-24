# Windows Claude Code Test Plan

## Static Checks

- `deploy.ps1` parses in Windows PowerShell 5.1.
- `assets/manifest.json` version matches `$VERSION`.
- Required assets exist and SHA256 values match.
- Repository text files do not contain real API keys.

## Clean VM Checks

- Restore `CCDeploy-Win11-Test` to `clean-base`.
- Copy the target package from `\\VBOXSVR\CCDeployPackage`.
- Run `一键部署.cmd`.
- Enter a real DeepSeek API Key manually.
- Confirm all installer phases complete.
- Confirm Phase 6 passes `claude --version`.
- Confirm Phase 6 passes `claude -p "Reply with exactly OK"`.
- Open a fresh PowerShell and run `claude`.

## Release Gate

Do not publish a GitHub Release tag until static checks and clean VM checks both pass.
