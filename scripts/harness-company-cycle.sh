#!/bin/bash
# harness-company-cycle.sh — record an OPERATING heartbeat for a perpetual goal.
#
# This is the steady-state transition for a never-completing (Mode 1) goal: the
# CEO runs it at the end of an operating tick AFTER a status-briefing round
# surfaced no new agenda. It flips the runtime to "operating" (a non-terminal
# state the Stop hook treats as a clean yield to the next hourly wake), bumps the
# cycle counter, and records activity — it does NOT terminate the mission or the
# company loop. Finite goals use harness-company-complete.sh instead.
#
# Usage:
#   bash scripts/harness-company-cycle.sh <project-root> <goal-rel> [reason]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${1:-.}"
GOAL_REL="${2:-}"
REASON="${3:-operating-heartbeat}"

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
[ -f "$PROGRESS" ] || { echo "[company-cycle] not found: $PROGRESS" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[company-cycle] jq required" >&2; exit 1; }

if ! bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
  '.company_state.state = "operating" |
   .conductor.state = "operating" |
   .conductor.current_action = ("operating:" + $reason) |
   .conductor.tracks = [] |
   .current_agent = null |
   .next_agent = "none" |
   .agent_status = "operating" |
   .owner_prompt.status = "operating" |
   .conductor.stop_chain_count = 0 |
   .operating.cycles = ((.operating.cycles // 0) + 1) |
   .operating.last_cycle_at = (now | todate) |
   .operating.goal = $goal' \
  --arg reason "$REASON" --arg goal "$GOAL_REL"; then
  echo "[company-cycle] FAILED: progress.json operating heartbeat did not apply (goal=$GOAL_REL). Runtime is NOT marked operating." >&2
  exit 1
fi

# bump the per-goal agenda cycle counter too (best-effort)
AGENDA="$PROJECT_ROOT/.harness/documents/$GOAL_REL/agenda.json"
if [ -n "$GOAL_REL" ] && [ -f "$AGENDA" ]; then
  tmp="$AGENDA.tmp.$$"
  jq '.cycles = ((.cycles // 0) + 1) | .last_cycle_at = (now | todate)' "$AGENDA" > "$tmp" && mv "$tmp" "$AGENDA" || rm -f "$tmp"
fi

if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/harness-activity-record.js" ]; then
  node "$SCRIPT_DIR/harness-activity-record.js" "$PROJECT_ROOT" >/dev/null 2>&1 || true
fi

echo "[company-cycle] operating heartbeat recorded: $REASON"
