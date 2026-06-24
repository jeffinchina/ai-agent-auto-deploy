# Shared Installer Framework

This folder contains cross-package contracts shared by Windows and macOS installers.

Keep shared files small and declarative. Platform-specific scripts should live under `installers/<os>/<agent>/` after the current root Claude Windows installer is stable.

## Contracts

- Asset manifests define required files and hashes.
- Provider profiles define API endpoints, model names, and auth environment variable names.
- Test plans define what must pass before a package can be released.

The current root `deploy.ps1` remains the active Claude Windows installer until the v3.2.x line is fully validated in VM tests.
