#!/bin/bash
# harness-runtime-stop.sh — Stop walwal harness play/release runtime mode.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${HARNESS_PROJECT_ROOT:-.}")" || exit 1
HARNESS_DIR="$PROJECT_ROOT/.harness"
PROGRESS="$HARNESS_DIR/progress.json"
CONFIG="$HARNESS_DIR/config.json"
RUNTIME_DIR="$HARNESS_DIR/runtime"

[ -d "$HARNESS_DIR" ] || { echo "ERROR: .harness/ not found" >&2; exit 1; }
[ -f "$PROGRESS" ] || { echo "ERROR: .harness/progress.json not found" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "ERROR: .harness/config.json not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

MODE_FILE="$RUNTIME_DIR/harness-mode"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stopped=0

for pid_file in "$RUNTIME_DIR/play.pid" "$RUNTIME_DIR/release.pid"; do
  [ -f "$pid_file" ] || continue
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    stopped=$((stopped + 1))
  fi
  rm -f "$pid_file"
done

rm -f "$MODE_FILE"

tmp_config="$(mktemp)"
jq '
  .runtime.build.live = false |
  .runtime.production.live = false
' "$CONFIG" > "$tmp_config" && mv "$tmp_config" "$CONFIG" || rm -f "$tmp_config"

tmp="$(mktemp)"
jq --arg ts "$ts" --arg reason "$*" '
  .runtime_state.mode = "stopped" |
  .runtime_state.stopped_at = $ts |
  .runtime_state.stop_reason = $reason |
  .runtime_state.pid = null |
  .service_ops.requested_mode = null |
  .service_ops.monitor.stream_active = false |
  .runtime.build.live = false |
  .runtime.production.live = false
' "$PROGRESS" > "$tmp" && mv "$tmp" "$PROGRESS" || rm -f "$tmp"

echo "stopped runtime processes: $stopped"
