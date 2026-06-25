#!/usr/bin/env bash
set -euo pipefail

AGENT="all"
PACKAGE_ROOT="${PACKAGE_ROOT:-$(pwd)}"
RESULTS_ROOT="${RESULTS_ROOT:-$(pwd)/macos-results}"
RUN_PROVIDER_GATE="${RUN_PROVIDER_GATE:-0}"
INSTALL_LITELLM_PROXY="${INSTALL_LITELLM_PROXY:-0}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"

usage() {
  cat <<'USAGE'
Usage:
  Run-macOS-Agent-Acceptance.sh [--agent all|claude-code|codex|openclaw|cursor] [--package-root DIR] [--results-root DIR] [--provider-gate] [--install-litellm-proxy] [--skip-install]

Run this on a real Mac, cloud Mac, or Apple-hardware macOS VM.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:?missing agent}"; shift 2 ;;
    --package-root) PACKAGE_ROOT="${2:?missing package root}"; shift 2 ;;
    --results-root) RESULTS_ROOT="${2:?missing results root}"; shift 2 ;;
    --provider-gate) RUN_PROVIDER_GATE=1; shift ;;
    --install-litellm-proxy) INSTALL_LITELLM_PROXY=1; shift ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$AGENT" in
  all|claude-code|codex|openclaw|cursor) ;;
  *) echo "Unsupported agent: $AGENT" >&2; exit 2 ;;
esac

sanitize() {
  sed -E 's/sk-[A-Za-z0-9_-]+/sk-***/g; s/Bearer[[:space:]]+[A-Za-z0-9_.=-]+/Bearer ***/Ig'
}

run_id="$(date -u +%Y%m%d-%H%M%S)"
result_dir="$RESULTS_ROOT/guest-$run_id"
mkdir -p "$result_dir"
summary="$result_dir/SUMMARY.md"
transcript="$result_dir/transcript.txt"
manual_gates_file="$result_dir/manual-gates.txt"

log() {
  printf '%s\n' "$*" | sanitize | tee -a "$transcript"
}

write_summary() {
  printf '%s\n' "$*" | sanitize >> "$summary"
}

run_step() {
  local name="$1"
  shift
  log ""
  log "==> $name"
  write_summary "- START: $name"
  if "$@" 2>&1 | sanitize | tee -a "$transcript"; then
    write_summary "- PASS: $name"
    log "[PASS] $name"
  else
    local status="${PIPESTATUS[0]}"
    write_summary "- FAIL: $name"
    write_summary "  - Exit: $status"
    log "[FAIL] $name"
    exit "$status"
  fi
}

require_deepseek_key() {
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    case "$DEEPSEEK_API_KEY" in
      sk-*) return 0 ;;
      *) echo "DEEPSEEK_API_KEY must start with sk-." >&2; exit 1 ;;
    esac
  fi

  printf '\nDeepSeek API Key input is hidden and only stored in this shell process.\n'
  printf 'DeepSeek API Key: '
  stty -echo
  IFS= read -r DEEPSEEK_API_KEY
  stty echo
  printf '\n'
  export DEEPSEEK_API_KEY
  case "$DEEPSEEK_API_KEY" in
    sk-*) ;;
    *) echo "DeepSeek API Key must start with sk-." >&2; exit 1 ;;
  esac
}

package_dir_for() {
  local id="$1"
  printf '%s/%s-macos-v0.1.0' "$PACKAGE_ROOT" "$id"
}

run_install_sh() {
  local dir="$1"
  shift
  (cd "$dir" && "$@" bash install.sh)
}

mark_manual_gate() {
  local msg="$1"
  printf '%s\n' "$msg" >> "$manual_gates_file"
  write_summary "- MANUAL: $msg"
  log "[MANUAL] $msg"
}

run_claude_code() {
  local dir
  dir="$(package_dir_for claude-code)"
  [ -f "$dir/install.sh" ] || { echo "Missing package: $dir" >&2; exit 1; }
  run_step "Claude Code dry-run" env DRY_RUN=1 bash "$dir/install.sh"
  if [ "$SKIP_INSTALL" != "1" ]; then
    if [ "$RUN_PROVIDER_GATE" = "1" ]; then require_deepseek_key; fi
    run_step "Claude Code install and DeepSeek smoke" bash "$dir/install.sh"
  fi
}

run_codex() {
  local dir
  dir="$(package_dir_for codex)"
  [ -f "$dir/install.sh" ] || { echo "Missing package: $dir" >&2; exit 1; }
  run_step "Codex dry-run" env DRY_RUN=1 bash "$dir/install.sh"
  if [ "$SKIP_INSTALL" != "1" ]; then
    run_step "Codex install" bash "$dir/install.sh"
  fi
  run_step "Codex verify" bash -lc 'command -v codex && codex --version && { codex doctor || true; }'
  if [ "$RUN_PROVIDER_GATE" = "1" ]; then
    require_deepseek_key
    if [ "$INSTALL_LITELLM_PROXY" = "1" ]; then
      run_step "Codex DeepSeek LiteLLM install and config" env PREPARE_DEEPSEEK_LITELLM=1 INSTALL_LITELLM_PROXY=1 bash "$dir/install.sh"
    else
      run_step "Codex DeepSeek LiteLLM config" env PREPARE_DEEPSEEK_LITELLM=1 bash "$dir/install.sh"
    fi
    run_step "Codex DeepSeek conversation smoke" env RUN_DEEPSEEK_SMOKE=1 bash "$dir/install.sh"
  fi
}

run_openclaw() {
  local dir
  dir="$(package_dir_for openclaw)"
  [ -f "$dir/install.sh" ] || { echo "Missing package: $dir" >&2; exit 1; }
  run_step "OpenClaw dry-run" env DRY_RUN=1 bash "$dir/install.sh"
  if [ "$SKIP_INSTALL" != "1" ]; then
    run_step "OpenClaw install" bash "$dir/install.sh"
  fi
  run_step "OpenClaw verify" bash -lc 'command -v openclaw && openclaw --version'
  if [ "$RUN_PROVIDER_GATE" = "1" ]; then
    require_deepseek_key
    run_step "OpenClaw DeepSeek provider config" env CONFIGURE_DEEPSEEK=1 bash "$dir/install.sh"
    run_step "OpenClaw DeepSeek conversation smoke" env RUN_DEEPSEEK_SMOKE=1 bash "$dir/install.sh"
  fi
}

run_cursor() {
  local dir
  dir="$(package_dir_for cursor)"
  [ -f "$dir/install.sh" ] || { echo "Missing package: $dir" >&2; exit 1; }
  run_step "Cursor dry-run" env DRY_RUN=1 bash "$dir/install.sh"
  if [ "$SKIP_INSTALL" != "1" ]; then
    run_step "Cursor install" bash "$dir/install.sh"
  fi
  if bash -lc 'command -v cursor-agent || command -v cursor' 2>&1 | sanitize | tee -a "$transcript"; then
    write_summary "- PASS: Cursor command detection"
  else
    mark_manual_gate "Cursor command was not detected; verify Cursor desktop first launch manually."
  fi
  if [ "$RUN_PROVIDER_GATE" = "1" ]; then
    mark_manual_gate "Cursor DeepSeek provider/conversation gate requires GUI/manual verification."
  fi
}

{
  echo "# macOS Agent Acceptance $run_id"
  echo
  echo "- Host: $(hostname)"
  echo "- System: $(uname -a)"
  echo "- Package root: $PACKAGE_ROOT"
  echo "- Provider gate requested: $RUN_PROVIDER_GATE"
  if [ "$AGENT" = "all" ]; then
    echo "- Isolation note: release-level evidence should run one agent per clean Mac user/VM restore."
  fi
  echo
} > "$summary"

case "$AGENT" in
  all)
    run_claude_code
    run_codex
    run_openclaw
    run_cursor
    ;;
  claude-code) run_claude_code ;;
  codex) run_codex ;;
  openclaw) run_openclaw ;;
  cursor) run_cursor ;;
esac

write_summary ""
write_summary "## Result"
if [ -s "$manual_gates_file" ]; then
  write_summary "Automated gates passed for commands that ran. Manual gates remain pending:"
  while IFS= read -r gate; do
    write_summary "- PENDING: $gate"
  done < "$manual_gates_file"
else
  write_summary "PASS for automated gates that ran."
fi

if [ -n "${DEEPSEEK_API_KEY:-}" ]; then unset DEEPSEEK_API_KEY; fi

tmp_transcript="$transcript.tmp"
sanitize < "$transcript" > "$tmp_transcript"
mv "$tmp_transcript" "$transcript"

log ""
log "Acceptance run complete: $result_dir"
