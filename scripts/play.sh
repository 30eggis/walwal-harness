#!/bin/bash
# play.sh — Start walwal harness play build mode.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${HARNESS_PROJECT_ROOT:-.}")" || exit 1
HARNESS_DIR="$PROJECT_ROOT/.harness"
CONFIG="$HARNESS_DIR/config.json"
PROGRESS="$HARNESS_DIR/progress.json"
RUNTIME_DIR="$HARNESS_DIR/runtime"
LOG_DIR="$HARNESS_DIR/logs/$(date -u +%Y-%m-%d)"

[ -d "$HARNESS_DIR" ] || { echo "ERROR: .harness/ not found" >&2; exit 1; }
[ -f "$PROGRESS" ] || { echo "ERROR: .harness/progress.json not found" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "ERROR: .harness/config.json not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

mkdir -p "$RUNTIME_DIR" "$LOG_DIR"

MODE_FILE="$RUNTIME_DIR/harness-mode"
PID_FILE="$RUNTIME_DIR/play.pid"
LOG_FILE="$LOG_DIR/play-harness.log"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ENV_FILE="$PROJECT_ROOT/.env"

active_mode=""
[ -f "$MODE_FILE" ] && active_mode="$(cat "$MODE_FILE" 2>/dev/null || true)"
if [ -n "$active_mode" ] && [ "$active_mode" != "play" ]; then
  echo "ERROR: $active_mode mode is active. Run /stop-harness before /play-harness." >&2
  exit 2
fi

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "ERROR: play mode is already active with pid $old_pid" >&2
    exit 2
  fi
fi

cmd="$(jq -r '.runtime.play.command // empty' "$CONFIG" 2>/dev/null || true)"
if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
  cmd="$(jq -r '.runtime.build.commands[0].command // empty' "$CONFIG" 2>/dev/null || true)"
fi
[ -n "$cmd" ] || { echo "ERROR: runtime.play.command or runtime.build.commands[0].command must be configured" >&2; exit 1; }

cwd="$(jq -r '.runtime.play.cwd // .runtime.build.commands[0].cwd // "."' "$CONFIG" 2>/dev/null || echo ".")"
run_dir="$PROJECT_ROOT/$cwd"
[ -d "$run_dir" ] || { echo "ERROR: play cwd does not exist: $cwd" >&2; exit 1; }

env_base_port=""
if [ -f "$ENV_FILE" ]; then
  env_base_port="$(grep -E '^HARNESS_BASE_PORT=[0-9]' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' || true)"
fi
config_base_port="$(jq -r 'if .runtime.ports.base == null then "" else (.runtime.ports.base|tostring) end' "$CONFIG" 2>/dev/null || true)"
base_port="${env_base_port:-$config_base_port}"

(
  cd "$run_dir" || exit 1
  nohup bash -lc "$cmd $*" >> "$LOG_FILE" 2>&1 &
  echo "$!"
) > "$RUNTIME_DIR/play.pid.tmp"
pid="$(cat "$RUNTIME_DIR/play.pid.tmp" 2>/dev/null || true)"
rm -f "$RUNTIME_DIR/play.pid.tmp"
[ -n "$pid" ] || { echo "ERROR: failed to start play command" >&2; exit 1; }

printf '%s\n' "play" > "$MODE_FILE"
printf '%s\n' "$pid" > "$PID_FILE"

tmp_config="$(mktemp)"
jq --arg log "$LOG_FILE" --arg cmd "$cmd" --arg cwd "$cwd" --arg base "$base_port" '
  .runtime.build.live = true |
  .runtime.production.live = false |
  .runtime.build.commands[0].command = ((.runtime.build.commands[0].command // $cmd) | if . == "" then $cmd else . end) |
  .runtime.build.commands[0].cwd = ((.runtime.build.commands[0].cwd // $cwd) | if . == "" then $cwd else . end) |
  .runtime.build.commands[0].log_path = $log |
  if ($base | length) > 0 then
    .runtime.ports.base = (($base|tonumber?) // .runtime.ports.base) |
    .runtime.build.commands[0].expected_port = ((.runtime.build.commands[0].expected_port // (($base|tonumber?) // null)))
  else
    .
  end
' "$CONFIG" > "$tmp_config" && mv "$tmp_config" "$CONFIG" || rm -f "$tmp_config"

tmp="$(mktemp)"
jq --arg ts "$ts" --arg pid "$pid" --arg log "$LOG_FILE" --arg cmd "$cmd" '
  .runtime_state.mode = "play" |
  .runtime_state.started_at = $ts |
  .runtime_state.pid = ($pid|tonumber) |
  .runtime_state.log_path = $log |
  .runtime_state.command = $cmd |
  .service_ops.requested_mode = "monitor" |
  .service_ops.monitor.stream_active = true |
  .runtime.build.live = true |
  .runtime.production.live = false
' "$PROGRESS" > "$tmp" && mv "$tmp" "$PROGRESS" || rm -f "$tmp"

ops_report="$(bash "$SCRIPT_DIR/harness-service-ops-monitor.sh" "$PROJECT_ROOT" 2>/dev/null || true)"
echo "play pid: $pid"
echo "play log: $LOG_FILE"
[ -n "$ops_report" ] && echo "ops report: $ops_report"
