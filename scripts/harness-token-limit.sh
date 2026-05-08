#!/bin/bash
# harness-token-limit.sh — mark/resume token-limit interruptions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 1
CMD="${2:-mark}"

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"

[ -f "$PROGRESS" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

parse_iso_epoch() {
  local iso="${1:-}"
  [ -n "$iso" ] && [ "$iso" != "null" ] || return 1
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null \
    || date -u -d "$iso" "+%s" 2>/dev/null
}

mark_token_limit() {
  local retry_secs current next task_path target stop_reason
  retry_secs="${3:-$(jq -r '.token_limit.retry_after_seconds // 3600' "$CONFIG" 2>/dev/null || echo 3600)}"
  stop_reason=$(jq -r '.token_limit.stop_reason_flag // "TokenLimit"' "$CONFIG" 2>/dev/null || echo "TokenLimit")
  current=$(jq -r '.current_agent // "null"' "$PROGRESS")
  next=$(jq -r '.next_agent // "null"' "$PROGRESS")
  task_path=$(jq -r '.task_sessions.current.path // "null"' "$PROGRESS")
  target="$current"
  if [ "$target" = "null" ] || [ -z "$target" ]; then
    target="$next"
  fi
  [ "$target" != "null" ] || target="dispatcher"

  local stopped_at resume_after
  stopped_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  resume_after="$(date -u -v+"${retry_secs}"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "+${retry_secs} seconds" +%Y-%m-%dT%H:%M:%SZ)"

  bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" "
    .agent_status = \"paused\" |
    .next_agent = \"$target\" |
    .task_stop.active = true |
    .task_stop.reason = \"$stop_reason\" |
    .task_stop.stopped_at = \"$stopped_at\" |
    .task_stop.resume_after = \"$resume_after\" |
    .task_stop.resume_ready = false |
    .task_stop.resume_notified_at = null |
    .task_stop.wake_target = \"$target\" |
    .task_stop.stopped_agent = $(jq -Rn --arg v "$current" '$v') |
    .task_stop.stopped_next_agent = $(jq -Rn --arg v "$next" '$v') |
    .task_stop.task_session_path = $(jq -Rn --arg v "$task_path" '$v') |
    .task_stop.hold_count = ((.task_stop.hold_count // 0) + 1)
  " >/dev/null

  echo "[token-limit] marked: target=$target resume_after=$resume_after"
}

resume_probe() {
  local active reason resume_after wake_target
  active=$(jq -r '.task_stop.active // false' "$PROGRESS")
  reason=$(jq -r '.task_stop.reason // "null"' "$PROGRESS")
  resume_after=$(jq -r '.task_stop.resume_after // "null"' "$PROGRESS")
  wake_target=$(jq -r '.task_stop.wake_target // .next_agent // "null"' "$PROGRESS")

  if [ "$active" != "true" ] || [ "$reason" != "TokenLimit" ]; then
    echo "[token-limit] no active TokenLimit hold"
    exit 0
  fi

  local resume_epoch now_ts
  resume_epoch=$(parse_iso_epoch "$resume_after" || echo 0)
  now_ts=$(date -u "+%s")
  if [ "$now_ts" -lt "$resume_epoch" ]; then
    echo "[token-limit] still held until $resume_after"
    exit 1
  fi

  bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" "
    .agent_status = \"pending\" |
    .current_agent = null |
    .next_agent = \"$wake_target\" |
    .task_stop.active = false |
    .task_stop.resume_ready = true |
    .task_stop.resume_notified_at = (now | todate)
  " >/dev/null
  echo "[token-limit] resume ready: wake_target=$wake_target"
}

case "$CMD" in
  mark) mark_token_limit "$@" ;;
  resume-probe) resume_probe ;;
  *)
    echo "usage: $0 <project-root> <mark|resume-probe> [retry_seconds]" >&2
    exit 2
    ;;
esac
