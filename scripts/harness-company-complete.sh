#!/bin/bash
# harness-company-complete.sh — mark the current v7 company mission complete.
#
# Usage:
#   bash scripts/harness-company-complete.sh <project-root> [reason]
#
# This is the explicit running -> idle/done transition used by dashboard,
# runner, hooks, and final CEO handoff paths. It intentionally only updates
# runtime state; it does not archive or rewrite mission documents.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${1:-.}"
REASON="${2:-mission-complete}"

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
TODOS="$PROJECT_ROOT/.harness/todos/state.json"
[ -f "$PROGRESS" ] || {
  echo "[company-complete] not found: $PROGRESS" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "[company-complete] jq is required" >&2
  exit 1
}

bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
  '.company_state.state = "idle" |
   .company_state.active_workers = 0 |
   .company_state.completed_at = (now | todate) |
   .conductor.state = "completed" |
   .conductor.current_action = "complete:'"$REASON"'" |
   .conductor.completed_at = (now | todate) |
   .conductor.tracks = [] |
   .conductor.rendezvous = null |
   .conductor.fork_meeting_id = null |
   .current_agent = null |
   .next_agent = "none" |
   .agent_status = "completed" |
   .owner_prompt.status = "completed" |
   .owner_prompt.completed_at = (now | todate)'

if [ -f "$TODOS" ]; then
  tmp="$(mktemp)"
  jq '
    .owners |= with_entries(
      .value |= map(
        if (.status == "active" or .status == "pending" or .status == "paused")
        then .status = "done" | .updated_at = (now | todate)
        else .
        end
      )
    )
  ' "$TODOS" > "$tmp" && mv "$tmp" "$TODOS"
fi

DOCS="$PROJECT_ROOT/.harness/documents"
if [ -d "$DOCS" ]; then
  find "$DOCS" -name mission-state.json -type f -print0 | while IFS= read -r -d '' state; do
    active="$(jq -r '.active // false' "$state" 2>/dev/null || echo false)"
    lifecycle="$(jq -r '.lifecycle // .status // "unknown"' "$state" 2>/dev/null || echo unknown)"
    case "$lifecycle" in
      closed|cancelled|superseded|complete|blocked) continue ;;
    esac
    if [ "$active" = "true" ]; then
      tmp="$(mktemp)"
      jq '.lifecycle = "complete" | .active = false | .completed_at = (now | todate)' "$state" > "$tmp" && mv "$tmp" "$state"
    fi
  done
fi

echo "[company-complete] marked complete: $REASON"
