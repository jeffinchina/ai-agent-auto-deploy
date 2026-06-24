#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
TAG="${OPENCLAW_TAG:-latest}"
RUN_ONBOARDING="${RUN_ONBOARDING:-0}"
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/openclaw-macos-$(date +%Y%m%d-%H%M%S).log"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOGFILE"; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; log "[OK] $*"; }
info() { printf '\033[90m[INFO]\033[0m %s\n' "$*"; log "[INFO] $*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; log "[WARN] $*"; }
fail() { printf '\033[31m[ERR]\033[0m %s\n' "$*"; log "[ERR] $*"; printf '[INFO] Log: %s\n' "$LOGFILE"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "This installer only supports macOS."
command -v curl >/dev/null 2>&1 || fail "curl is required."

if command -v openclaw >/dev/null 2>&1; then
  ok "OpenClaw already exists: $(command -v openclaw)"
else
  info "Running OpenClaw official installer..."
  if [ "$RUN_ONBOARDING" = "1" ]; then
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --tag "$TAG" >> "$LOGFILE" 2>&1 || fail "OpenClaw install failed."
  else
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --tag "$TAG" --no-onboard >> "$LOGFILE" 2>&1 || fail "OpenClaw install failed."
  fi
  ok "OpenClaw install command complete"
fi

if openclaw --version >> "$LOGFILE" 2>&1; then
  ok "openclaw available: $(openclaw --version 2>/dev/null | head -n 1)"
else
  warn "openclaw --version returned non-zero; onboarding may still be required"
fi
info "First use: openclaw onboard"
