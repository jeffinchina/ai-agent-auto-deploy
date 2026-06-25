#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
TAG="${OPENCLAW_TAG:-latest}"
RUN_ONBOARDING="${RUN_ONBOARDING:-0}"
CONFIGURE_DEEPSEEK="${CONFIGURE_DEEPSEEK:-0}"
RUN_DEEPSEEK_SMOKE="${RUN_DEEPSEEK_SMOKE:-0}"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek/deepseek-v4-pro}"
DRY_RUN="${DRY_RUN:-0}"
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/openclaw-macos-$(date +%Y%m%d-%H%M%S).log"

sanitize() {
  sed -E 's/sk-[A-Za-z0-9_-]+/sk-***/g; s/Bearer[[:space:]]+[A-Za-z0-9_.=-]+/Bearer ***/Ig'
}
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$(printf '%s' "$*" | sanitize)" >> "$LOGFILE"; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; log "[OK] $*"; }
info() { printf '\033[90m[INFO]\033[0m %s\n' "$*"; log "[INFO] $*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; log "[WARN] $*"; }
fail() { printf '\033[31m[ERR]\033[0m %s\n' "$*"; log "[ERR] $*"; printf '[INFO] Log: %s\n' "$LOGFILE"; exit 1; }

run_capture() {
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output" | sanitize >> "$LOGFILE"
  CAPTURED_OUTPUT="$output"
  return "$status"
}

read_deepseek_key() {
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    case "$DEEPSEEK_API_KEY" in
      sk-*) printf '%s' "$DEEPSEEK_API_KEY"; return 0 ;;
      *) fail "DEEPSEEK_API_KEY must start with sk-." ;;
    esac
  fi
  printf '\nDeepSeek API Key input is hidden. Paste and press Enter.\n'
  printf 'API Key: '
  stty -echo
  IFS= read -r key
  stty echo
  printf '\n'
  case "$key" in
    sk-*) printf '%s' "$key" ;;
    *) fail "DeepSeek API Key must start with sk-." ;;
  esac
}

[ "$(uname -s)" = "Darwin" ] || fail "This installer only supports macOS."
command -v curl >/dev/null 2>&1 || fail "curl is required."

if [ "$DRY_RUN" = "1" ]; then
  ok "OpenClaw macOS dry-run passed"
  exit 0
fi
trap 'stty echo 2>/dev/null || true' EXIT

if command -v openclaw >/dev/null 2>&1; then
  ok "OpenClaw already exists: $(command -v openclaw)"
else
  info "Running OpenClaw official installer..."
  args=(--version "$TAG" --no-prompt)
  if [ "$RUN_ONBOARDING" = "1" ]; then
    :
  else
    args+=(--no-onboard)
  fi
  if ! curl -fsSL https://openclaw.ai/install.sh | bash -s -- "${args[@]}" >> "$LOGFILE" 2>&1; then
    warn "OpenClaw installer log tail:"
    tail -n 40 "$LOGFILE" || true
    fail "OpenClaw install failed."
  fi
  ok "OpenClaw install command complete"
fi

if openclaw --version >> "$LOGFILE" 2>&1; then
  ok "openclaw available: $(openclaw --version 2>/dev/null | head -n 1)"
else
  fail "openclaw --version returned non-zero."
fi
info "First use: openclaw onboard"

if [ "$CONFIGURE_DEEPSEEK" = "1" ] || [ "$RUN_DEEPSEEK_SMOKE" = "1" ]; then
  key="$(read_deepseek_key)"
  info "Configuring OpenClaw DeepSeek provider..."
  run_capture openclaw onboard \
    --non-interactive \
    --mode local \
    --auth-choice deepseek-api-key \
    --deepseek-api-key "$key" \
    --skip-health \
    --skip-ui \
    --skip-channels \
    --skip-daemon \
    --skip-search \
    --accept-risk || fail "DeepSeek provider configuration failed."
  ok "DeepSeek provider configured"

  info "Verifying DeepSeek model catalog..."
  run_capture openclaw models list --provider deepseek --plain || fail "DeepSeek model catalog verification failed."
  printf '%s' "$CAPTURED_OUTPUT" | grep -qi 'deepseek' || fail "DeepSeek model catalog did not include DeepSeek models."
  ok "DeepSeek model catalog available"

  info "Setting default model: $DEEPSEEK_MODEL"
  if run_capture openclaw models set "$DEEPSEEK_MODEL"; then
    ok "Default model set"
  else
    warn "Default model setup was not confirmed; smoke uses explicit model override."
  fi
fi

if [ "$RUN_DEEPSEEK_SMOKE" = "1" ]; then
  info "Running OpenClaw DeepSeek minimal conversation smoke..."
  run_capture openclaw infer model run --local --model "$DEEPSEEK_MODEL" --prompt "Reply with exactly OK" || fail "DeepSeek conversation smoke failed."
  printf '%s' "$CAPTURED_OUTPUT" | grep -q '\bOK\b' || fail "DeepSeek conversation did not return OK."
  ok "DeepSeek conversation smoke passed"
fi
