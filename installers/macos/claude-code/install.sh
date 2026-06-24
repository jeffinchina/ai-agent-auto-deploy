#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
DEEPSEEK_URL="https://api.deepseek.com/anthropic"
MODEL="deepseek-v4-pro"
MODEL_FAST="deepseek-v4-flash"
DRY_RUN="${DRY_RUN:-0}"
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/claude-code-macos-$(date +%Y%m%d-%H%M%S).log"

sanitize() {
  sed -E 's/sk-[A-Za-z0-9_-]+/sk-***/g; s/Bearer[[:space:]]+[A-Za-z0-9_.=-]+/Bearer ***/Ig'
}
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$(printf '%s' "$*" | sanitize)" >> "$LOGFILE"; }
info() { printf '\033[90m[INFO]\033[0m %s\n' "$*"; log "[INFO] $*"; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; log "[OK] $*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; log "[WARN] $*"; }
fail() { printf '\033[31m[ERR]\033[0m %s\n' "$*"; log "[ERR] $*"; printf '[INFO] Log: %s\n' "$LOGFILE"; exit 1; }

preflight() {
  printf 'Claude Code macOS Installer v%s\n' "$VERSION"
  [ "$(uname -s)" = "Darwin" ] || fail "This installer only supports macOS."
  case "$(uname -m)" in
    arm64|x86_64) ok "Architecture: $(uname -m)" ;;
    *) fail "Unsupported architecture: $(uname -m)" ;;
  esac
  command -v curl >/dev/null 2>&1 || fail "curl is required."
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to update settings.json."
}

ensure_node() {
  if command -v node >/dev/null 2>&1; then
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [ "$major" -ge 18 ]; then
      ok "Node.js $(node --version)"
      return
    fi
    warn "Existing Node.js is too old: $(node --version 2>/dev/null || true)"
  fi

  if command -v brew >/dev/null 2>&1; then
    info "Installing Node.js with Homebrew..."
    brew install node@20 >> "$LOGFILE" 2>&1 || brew install node >> "$LOGFILE" 2>&1 || fail "Node.js install failed."
    export PATH="$(brew --prefix)/opt/node@20/bin:$(brew --prefix)/bin:$PATH"
    command -v node >/dev/null 2>&1 || fail "Node.js not found after Homebrew install."
    ok "Node.js $(node --version)"
    return
  fi

  fail "Node.js 18+ is required." "Install Node.js 20+ or Homebrew, then rerun this installer."
}

install_claude() {
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code already exists: $(claude --version 2>/dev/null | head -n 1)"
    return
  fi
  command -v npm >/dev/null 2>&1 || fail "npm is required."
  info "Installing Claude Code with npm..."
  npm install -g @anthropic-ai/claude-code --no-audit --no-fund >> "$LOGFILE" 2>&1 || fail "Claude Code npm install failed."
  command -v claude >/dev/null 2>&1 || fail "claude command not found after install."
  ok "Claude Code $(claude --version 2>/dev/null | head -n 1)"
}

read_key() {
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    case "$DEEPSEEK_API_KEY" in
      sk-*) ;;
      *) fail "DEEPSEEK_API_KEY must start with sk-." ;;
    esac
    validate_key "$DEEPSEEK_API_KEY" && DEEPSEEK_KEY="$DEEPSEEK_API_KEY" && return
    fail "DEEPSEEK_API_KEY did not validate."
  fi

  printf '\nDeepSeek API Key input is hidden. Paste and press Enter.\n'
  for attempt in 1 2 3; do
    printf 'API Key: '
    stty -echo
    IFS= read -r key
    stty echo
    printf '\n'
    case "$key" in
      sk-*) ;;
      *) warn "API Key should start with sk- ($attempt/3)"; continue ;;
    esac
    validate_key "$key" && DEEPSEEK_KEY="$key" && return
  done
  fail "No valid DeepSeek API Key was provided."
}

validate_key() {
  local key="$1"
  info "Validating DeepSeek API Key..."
  local code
  code="$(curl -sS -o /tmp/ccdeploy-deepseek-check.json -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${key}" \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}" \
    https://api.deepseek.com/chat/completions || true)"
  rm -f /tmp/ccdeploy-deepseek-check.json
  case "$code" in
    200) ok "DeepSeek API Key is valid"; return 0 ;;
    401) warn "DeepSeek API Key is invalid (401)"; return 1 ;;
    402) warn "DeepSeek account has no usable balance (402)"; return 1 ;;
    429) warn "DeepSeek rate limit (429)"; return 1 ;;
    *) warn "DeepSeek validation failed with HTTP $code"; return 1 ;;
  esac
}

write_settings() {
  info "Writing Claude Code settings..."
  export DEEPSEEK_KEY DEEPSEEK_URL MODEL MODEL_FAST
  python3 <<'PY'
import json, os, pathlib, time
cfg = pathlib.Path.home() / ".claude" / "settings.json"
cfg.parent.mkdir(parents=True, exist_ok=True)
data = {}
if cfg.exists():
    backup = cfg.with_suffix(cfg.suffix + f".bak-{time.strftime('%Y%m%d-%H%M%S')}")
    backup.write_bytes(cfg.read_bytes())
    try:
        data = json.loads(cfg.read_text(encoding="utf-8"))
    except Exception:
        data = {}
env = dict(data.get("env") or {})
env.update({
    "ANTHROPIC_BASE_URL": os.environ["DEEPSEEK_URL"],
    "ANTHROPIC_AUTH_TOKEN": os.environ["DEEPSEEK_KEY"],
    "ANTHROPIC_MODEL": os.environ["MODEL"],
    "ANTHROPIC_DEFAULT_OPUS_MODEL": os.environ["MODEL"],
    "ANTHROPIC_DEFAULT_SONNET_MODEL": os.environ["MODEL"],
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ["MODEL_FAST"],
    "CLAUDE_CODE_SUBAGENT_MODEL": os.environ["MODEL"],
    "CLAUDE_CODE_EFFORT_LEVEL": "medium",
})
data["env"] = env
cfg.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
PY
  ok "Claude Code settings written"
}

verify_claude() {
  claude --version >> "$LOGFILE" 2>&1 || fail "claude --version failed."
  ok "claude starts"
  local output
  output="$(claude -p 'Reply with exactly OK' 2>> "$LOGFILE" | tr -d '\r' | sed -n '1p' || true)"
  log "Claude smoke output: $output"
  [ "$output" = "OK" ] || fail "DeepSeek smoke test did not return OK."
  ok "DeepSeek smoke test passed"
}

preflight
if [ "$DRY_RUN" = "1" ]; then
  ok "Claude Code macOS dry-run passed"
  exit 0
fi
trap 'stty echo 2>/dev/null || true' EXIT
ensure_node
install_claude
read_key
write_settings
verify_claude
ok "Claude Code macOS install flow complete"
