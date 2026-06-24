#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
RELEASE="${CODEX_RELEASE:-latest}"
DRY_RUN="${DRY_RUN:-0}"
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/codex-macos-$(date +%Y%m%d-%H%M%S).log"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOGFILE"; }
info() { printf '\033[90m[INFO]\033[0m %s\n' "$*"; log "[INFO] $*"; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; log "[OK] $*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; log "[WARN] $*"; }
fail() { printf '\033[31m[ERR]\033[0m %s\n' "$*"; log "[ERR] $*"; printf '[INFO] Log: %s\n' "$LOGFILE"; exit 1; }

preflight() {
  printf 'Codex macOS Installer v%s\n' "$VERSION"
  [ "$(uname -s)" = "Darwin" ] || fail "This installer only supports macOS."
  case "$(uname -m)" in
    arm64|x86_64) ok "Architecture: $(uname -m)" ;;
    *) fail "Unsupported architecture: $(uname -m)" ;;
  esac
  command -v curl >/dev/null 2>&1 || fail "curl is required."
}

install_codex() {
  if command -v codex >/dev/null 2>&1; then
    info "Existing codex: $(command -v codex)"
    return
  fi

  info "Running OpenAI official Codex CLI installer..."
  export CODEX_NON_INTERACTIVE=1
  export CODEX_RELEASE="$RELEASE"
  curl -fsSL https://chatgpt.com/codex/install.sh | sh >> "$LOGFILE" 2>&1 || fail "Codex CLI install failed."
  ok "Codex CLI installed"
}

verify_codex() {
  command -v codex >/dev/null 2>&1 || fail "codex command not found after install."
  codex --version >> "$LOGFILE" 2>&1 || fail "codex --version failed."
  ok "codex available: $(codex --version 2>/dev/null | head -n 1)"
  if codex doctor >> "$LOGFILE" 2>&1; then
    ok "codex doctor passed"
  else
    warn "codex doctor returned non-zero; login or local environment may still need setup"
  fi
  info "First use: run codex login"
}

preflight
if [ "$DRY_RUN" = "1" ]; then
  ok "Codex macOS dry-run passed"
  exit 0
fi
install_codex
verify_codex
ok "Codex macOS install flow complete"
