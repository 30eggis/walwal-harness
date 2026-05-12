#!/bin/bash
# release.sh — Start walwal harness release operation mode.

set -uo pipefail

mode="${1:-release}"
if [ "$mode" = "release" ]; then
  shift || true
fi

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
PID_FILE="$RUNTIME_DIR/release.pid"
LOG_FILE="$LOG_DIR/release-harness.log"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

active_mode=""
[ -f "$MODE_FILE" ] && active_mode="$(cat "$MODE_FILE" 2>/dev/null || true)"
if [ -n "$active_mode" ] && [ "$active_mode" != "release" ]; then
  echo "ERROR: $active_mode mode is active. Run /stop-harness before /release-harness." >&2
  exit 2
fi

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "ERROR: release mode is already active with pid $old_pid" >&2
    exit 2
  fi
fi

cmd="$(jq -r '.runtime.release.command // empty' "$CONFIG" 2>/dev/null || true)"
[ -n "$cmd" ] && [ "$cmd" != "null" ] || { echo "ERROR: runtime.release.command must be configured" >&2; exit 1; }

cwd="$(jq -r '.runtime.release.cwd // "."' "$CONFIG" 2>/dev/null || echo ".")"
run_dir="$PROJECT_ROOT/$cwd"
[ -d "$run_dir" ] || { echo "ERROR: release cwd does not exist: $cwd" >&2; exit 1; }

(
  cd "$run_dir" || exit 1
  nohup bash -lc "$cmd $*" >> "$LOG_FILE" 2>&1 &
  echo "$!"
) > "$RUNTIME_DIR/release.pid.tmp"
pid="$(cat "$RUNTIME_DIR/release.pid.tmp" 2>/dev/null || true)"
rm -f "$RUNTIME_DIR/release.pid.tmp"
[ -n "$pid" ] || { echo "ERROR: failed to start release command" >&2; exit 1; }

printf '%s\n' "release" > "$MODE_FILE"
printf '%s\n' "$pid" > "$PID_FILE"

tmp_config="$(mktemp)"
jq '
  .runtime.build.live = false |
  .runtime.production.live = true
' "$CONFIG" > "$tmp_config" && mv "$tmp_config" "$CONFIG" || rm -f "$tmp_config"

tmp="$(mktemp)"
jq --arg ts "$ts" --arg pid "$pid" --arg log "$LOG_FILE" --arg cmd "$cmd" '
  .runtime_state.mode = "release" |
  .runtime_state.started_at = $ts |
  .runtime_state.pid = ($pid|tonumber) |
  .runtime_state.log_path = $log |
  .runtime_state.command = $cmd |
  .service_ops.requested_mode = "monitor" |
  .service_ops.monitor.stream_active = true |
  .runtime.build.live = false |
  .runtime.production.live = true
' "$PROGRESS" > "$tmp" && mv "$tmp" "$PROGRESS" || rm -f "$tmp"

ops_report="$(bash "$SCRIPT_DIR/harness-service-ops-monitor.sh" "$PROJECT_ROOT" 2>/dev/null || true)"
echo "release pid: $pid"
echo "release log: $LOG_FILE"
[ -n "$ops_report" ] && echo "ops report: $ops_report"
