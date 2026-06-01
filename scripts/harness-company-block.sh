#!/bin/bash
# harness-company-block.sh — mark the current v7 company mission BLOCKED on
# external authority (the second legitimate stop condition; the first is
# harness-company-complete.sh).
#
# Usage:
#   bash scripts/harness-company-block.sh <project-root> "<missing authority>"
#
# This is the explicit running -> blocked transition. The CEO runs it when the
# next action genuinely requires external authority the harness cannot infer or
# obtain (new credentials/secrets, payment approval, legal/business acceptance,
# unavailable production access, destructive data action, or a direct conflict
# with the Owner's stated direction). It records the named blocker, flips the
# runtime out of "running" so the Stop hook releases the turn, and marks the
# active mission-state lifecycle "blocked". It does NOT archive documents.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${1:-.}"
REASON="${2:-awaiting external authority}"

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
TODOS="$PROJECT_ROOT/.harness/todos/state.json"
[ -f "$PROGRESS" ] || {
  echo "[company-block] not found: $PROGRESS" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "[company-block] jq is required" >&2
  exit 1
}

if ! bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
  '.company_state.state = "idle" |
   .conductor.state = "blocked" |
   .conductor.current_action = ("blocked:" + $reason) |
   .conductor.blocked_at = (now | todate) |
   .conductor.tracks = [] |
   .conductor.rendezvous = null |
   .conductor.fork_meeting_id = null |
   .current_agent = null |
   .next_agent = "none" |
   .agent_status = "blocked" |
   .owner_prompt.status = "awaiting-authority" |
   .owner_prompt.blocked_reason = $reason |
   .owner_prompt.blocked_at = (now | todate) |
   del(.conductor.completed_at) |
   del(.owner_prompt.completed_at) |
   del(.company_state.completed_at)' \
  --arg reason "$REASON"; then
  echo "[company-block] FAILED: progress.json transition did not apply (reason=$REASON). Runtime is NOT marked blocked." >&2
  exit 1
fi

if [ -f "$TODOS" ]; then
  tmp="$(mktemp)"
  if jq --arg reason "$REASON" '
    .owners |= with_entries(
      .value |= map(
        if (.status == "active" or .status == "pending")
        then .status = "blocked" | .blocked_reason = $reason | .updated_at = (now | todate)
        else .
        end
      )
    )
  ' "$TODOS" > "$tmp" 2>/dev/null; then mv "$tmp" "$TODOS"; else rm -f "$tmp"; fi
fi

DOCS="$PROJECT_ROOT/.harness/documents"
if [ -d "$DOCS" ]; then
  find "$DOCS" -name mission-state.json -type f -print0 | while IFS= read -r -d '' state; do
    active="$(jq -r '.active // false' "$state" 2>/dev/null || echo false)"
    lifecycle="$(jq -r '.lifecycle // .status // "unknown"' "$state" 2>/dev/null || echo unknown)"
    case "$lifecycle" in
      closed|cancelled|superseded|complete|completed|blocked) continue ;;
    esac
    if [ "$active" = "true" ]; then
      tmp="$(mktemp)"
      jq --arg r "$REASON" '.lifecycle = "blocked" | .active = false | .blocked_reason = $r | .blocked_at = (now | todate)' "$state" > "$tmp" && mv "$tmp" "$state"
    fi
  done
fi

if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/harness-activity-record.js" ]; then
  node "$SCRIPT_DIR/harness-activity-record.js" "$PROJECT_ROOT" >/dev/null 2>&1 || true
fi

echo "[company-block] marked blocked: $REASON"
