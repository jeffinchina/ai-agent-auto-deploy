#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
RELEASE="${CODEX_RELEASE:-latest}"
PREPARE_DEEPSEEK_LITELLM="${PREPARE_DEEPSEEK_LITELLM:-0}"
INSTALL_LITELLM_PROXY="${INSTALL_LITELLM_PROXY:-0}"
RUN_DEEPSEEK_SMOKE="${RUN_DEEPSEEK_SMOKE:-0}"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-v4-pro}"
LITELLM_BACKEND_MODEL="${LITELLM_BACKEND_MODEL:-deepseek/deepseek-chat}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
DRY_RUN="${DRY_RUN:-0}"
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/codex-macos-$(date +%Y%m%d-%H%M%S).log"

sanitize() {
  sed -E 's/sk-[A-Za-z0-9_-]+/sk-***/g; s/Bearer[[:space:]]+[A-Za-z0-9_.=-]+/Bearer ***/Ig'
}
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$(printf '%s' "$*" | sanitize)" >> "$LOGFILE"; }
info() { printf '\033[90m[INFO]\033[0m %s\n' "$*"; log "[INFO] $*"; }
ok() { printf '\033[32m[OK]\033[0m %s\n' "$*"; log "[OK] $*"; }
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

write_litellm_bridge() {
  if [ "$PREPARE_DEEPSEEK_LITELLM" != "1" ] && [ "$INSTALL_LITELLM_PROXY" != "1" ] && [ "$RUN_DEEPSEEK_SMOKE" != "1" ]; then
    return
  fi

  command -v python3 >/dev/null 2>&1 || fail "python3 is required for Codex + LiteLLM DeepSeek bridge setup."

  bridge_dir="$HOME/.local/share/codex-deepseek-litellm"
  mkdir -p "$bridge_dir"
  lite_config="$bridge_dir/litellm-config.yaml"
  start_script="$bridge_dir/start-litellm-deepseek.sh"
  smoke_script="$bridge_dir/run-codex-deepseek-smoke.sh"

  cat > "$lite_config" <<YAML
model_list:
  - model_name: $DEEPSEEK_MODEL
    litellm_params:
      model: $LITELLM_BACKEND_MODEL
      api_key: os.environ/DEEPSEEK_API_KEY
YAML

  cat > "$start_script" <<SH
#!/usr/bin/env bash
set -euo pipefail
if [ -z "\${DEEPSEEK_API_KEY:-}" ] || [[ "\${DEEPSEEK_API_KEY}" != sk-* ]]; then
  echo "Set DEEPSEEK_API_KEY in this terminal before starting LiteLLM." >&2
  exit 1
fi
export CODEX_LITELLM_API_KEY="\${CODEX_LITELLM_API_KEY:-sk-local-codex}"
exec litellm --config "$lite_config" --host 127.0.0.1 --port "$LITELLM_PORT"
SH
  chmod +x "$start_script"

  cat > "$smoke_script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export CODEX_LITELLM_API_KEY="${CODEX_LITELLM_API_KEY:-sk-local-codex}"
codex exec --ephemeral "Reply with exactly OK"
SH
  chmod +x "$smoke_script"

  codex_dir="$HOME/.codex"
  codex_config="$codex_dir/config.toml"
  mkdir -p "$codex_dir"
  temp_config="$(mktemp)"
  if [ -f "$codex_config" ]; then
    backup="$codex_config.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$codex_config" "$backup"
    info "Backed up Codex config: $backup"
    awk '
      BEGIN { skip = 0 }
      $0 == "[model_providers.litellm-deepseek]" { skip = 1; next }
      skip && /^\[/ { skip = 0 }
      !skip && $0 !~ /^[[:space:]]*(model|model_provider)[[:space:]]*=/ { print }
    ' "$codex_config" > "$temp_config"
  else
    : > "$temp_config"
  fi

  {
    printf 'model = "%s"\n' "$DEEPSEEK_MODEL"
    printf 'model_provider = "litellm-deepseek"\n\n'
    cat "$temp_config"
    printf '\n[model_providers.litellm-deepseek]\n'
    printf 'name = "LiteLLM DeepSeek bridge"\n'
    printf 'base_url = "http://127.0.0.1:%s/v1"\n' "$LITELLM_PORT"
    printf 'env_key = "CODEX_LITELLM_API_KEY"\n'
    printf 'wire_api = "responses"\n'
  } > "$codex_config"
  rm -f "$temp_config"

  ok "Codex LiteLLM DeepSeek bridge config written"
  info "LiteLLM config: $lite_config"
  info "Start script: $start_script"
  info "Smoke helper: $smoke_script"

  if [ "$INSTALL_LITELLM_PROXY" = "1" ] || [ "$RUN_DEEPSEEK_SMOKE" = "1" ]; then
    info "Installing LiteLLM proxy with python3 -m pip..."
    run_capture python3 -m pip install --user 'litellm[proxy]' || fail "LiteLLM proxy install failed."
    export PATH="$HOME/.local/bin:$PATH"
    command -v litellm >/dev/null 2>&1 || fail "litellm command not found after install."
    ok "LiteLLM proxy installed"
  fi
}

run_deepseek_smoke() {
  if [ "$RUN_DEEPSEEK_SMOKE" != "1" ]; then
    return
  fi
  [ -n "${DEEPSEEK_API_KEY:-}" ] || fail "DEEPSEEK_API_KEY is required for Codex DeepSeek smoke."
  case "$DEEPSEEK_API_KEY" in
    sk-*) ;;
    *) fail "DEEPSEEK_API_KEY must start with sk-." ;;
  esac
  command -v litellm >/dev/null 2>&1 || fail "litellm command not found."

  bridge_dir="$HOME/.local/share/codex-deepseek-litellm"
  start_script="$bridge_dir/start-litellm-deepseek.sh"
  export CODEX_LITELLM_API_KEY="${CODEX_LITELLM_API_KEY:-sk-local-codex}"
  "$start_script" >> "$LOGFILE" 2>&1 &
  proxy_pid=$!
  trap 'kill "$proxy_pid" 2>/dev/null || true' EXIT

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS "http://127.0.0.1:$LITELLM_PORT/health" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  curl -fsS "http://127.0.0.1:$LITELLM_PORT/health" >/dev/null 2>&1 || fail "LiteLLM proxy did not become healthy."

  info "Running Codex DeepSeek minimal conversation smoke..."
  run_capture codex exec --ephemeral "Reply with exactly OK" || fail "Codex DeepSeek conversation smoke failed."
  printf '%s' "$CAPTURED_OUTPUT" | grep -q '\bOK\b' || fail "Codex DeepSeek conversation did not return OK."
  ok "Codex DeepSeek conversation smoke passed"
}

preflight
if [ "$DRY_RUN" = "1" ]; then
  ok "Codex macOS dry-run passed"
  exit 0
fi
install_codex
verify_codex
write_litellm_bridge
run_deepseek_smoke
ok "Codex macOS install flow complete"
