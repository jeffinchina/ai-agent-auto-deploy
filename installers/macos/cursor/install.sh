#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
INSTALL_DESKTOP="${INSTALL_DESKTOP:-0}"
DRY_RUN="${DRY_RUN:-0}"
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/cursor-macos-$(date +%Y%m%d-%H%M%S).log"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOGFILE"; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; log "[OK] $*"; }
info() { printf '\033[90m[INFO]\033[0m %s\n' "$*"; log "[INFO] $*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; log "[WARN] $*"; }
fail() { printf '\033[31m[ERR]\033[0m %s\n' "$*"; log "[ERR] $*"; printf '[INFO] Log: %s\n' "$LOGFILE"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "This installer only supports macOS."
command -v curl >/dev/null 2>&1 || fail "curl is required."

if [ "$DRY_RUN" = "1" ]; then
  ok "Cursor macOS dry-run passed"
  exit 0
fi

info "Installing Cursor CLI from official installer..."
curl https://cursor.com/install -fsS | bash >> "$LOGFILE" 2>&1 || fail "Cursor CLI install failed."

if command -v cursor-agent >/dev/null 2>&1; then
  ok "cursor-agent available: $(cursor-agent --version 2>/dev/null | head -n 1 || true)"
elif command -v cursor >/dev/null 2>&1; then
  ok "cursor command available: $(command -v cursor)"
else
  warn "Cursor CLI command not found in PATH; open a new terminal and retry."
fi

if [ "$INSTALL_DESKTOP" = "1" ]; then
  warn "Desktop app automated DMG install is not implemented yet; use https://cursor.com/download for now."
fi
