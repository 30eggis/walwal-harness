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
DOCS="$PROJECT_ROOT/.harness/documents"
[ -f "$PROGRESS" ] || {
  echo "[company-complete] not found: $PROGRESS" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "[company-complete] jq is required" >&2
  exit 1
}

# Lessons-before-plan gate (AGENTS.md Hard Rule 20). The Stop hook cannot see
# this path: once this script sets conductor.state=completed, harness-stop.sh
# short-circuits at the top, so a mission could complete having never read the
# corpus simply by firing the transition. Refuse the terminal transition here —
# this is the transition P6 names, and it is the last point at which refusing
# still means anything.
#
# Safe against deadlock: the gate is scoped to the latest ACTIVE mission, so the
# stop-hook backstop (which fires only when no mission is active) always passes.
# Opt out per project with .harness/config.json behavior.lessons_gate=false, or
# override a single call with HARNESS_SKIP_LESSONS_GATE=1.
if [ "${HARNESS_SKIP_LESSONS_GATE:-0}" != "1" ] && [ -x "$SCRIPT_DIR/harness-lessons-gate.sh" ]; then
  if ! gate_out="$(bash "$SCRIPT_DIR/harness-lessons-gate.sh" "$PROJECT_ROOT" text latest-active 2>/dev/null)"; then
    {
      echo "[company-complete] REFUSED: the active mission has not recorded what it read before planning."
      echo "$gate_out"
      echo "  Add the two sections to each role document, then re-run this transition."
      echo "  (override: HARNESS_SKIP_LESSONS_GATE=1, or behavior.lessons_gate=false in .harness/config.json)"
    } >&2
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | company-complete | refused | lessons-gate (Hard Rule 20)" >> "$PROJECT_ROOT/.harness/progress.log" 2>/dev/null || true
    exit 1
  fi
fi

# Corpus reachability (Hard Rule 11) and spec pins (Hard Rule 4) are re-checked
# at the same point, for the same reason: both are promises that decay silently
# between when they are made and when the mission claims to be done.
if [ "${HARNESS_SKIP_LESSONS_GATE:-0}" != "1" ] && [ -x "$SCRIPT_DIR/harness-corpus-reachability.sh" ]; then
  if ! reach_out="$(bash "$SCRIPT_DIR/harness-corpus-reachability.sh" "$PROJECT_ROOT" text 2>/dev/null)"; then
    {
      echo "[company-complete] REFUSED: corpus entries are unreachable by roles they name as an audience."
      echo "$reach_out"
    } >&2
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | company-complete | refused | corpus-reachability (Hard Rule 11)" >> "$PROJECT_ROOT/.harness/progress.log" 2>/dev/null || true
    exit 1
  fi
fi

state_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

pick_transition_mission_state() {
  local best=""
  local best_mtime=0
  local state active lifecycle mtime
  [ -d "$DOCS" ] || return 0
  while IFS= read -r -d '' state; do
    active="$(jq -r '.active // false' "$state" 2>/dev/null || echo false)"
    lifecycle="$(jq -r '.lifecycle // .status // "unknown"' "$state" 2>/dev/null || echo unknown)"
    if [ "$active" = "true" ] || [ "$lifecycle" = "blocked" ]; then
      mtime="$(state_mtime "$state")"
      if [ "${mtime:-0}" -ge "$best_mtime" ]; then
        best="$state"
        best_mtime="${mtime:-0}"
      fi
    fi
  done < <(find "$DOCS" -name mission-state.json -type f -print0)
  [ -n "$best" ] && printf '%s\n' "$best"
}

# Spec pins are verified against the mission this transition would close. This
# sits BEFORE the runtime transition on purpose: a refusal that runs after
# progress.json is already `completed` has refused nothing.
if [ "${HARNESS_SKIP_LESSONS_GATE:-0}" != "1" ] && [ -x "$SCRIPT_DIR/harness-spec-pin.sh" ] && [ -d "$DOCS" ]; then
  pin_target="$(pick_transition_mission_state)"
  if [ -n "$pin_target" ]; then
    mission_rel="${pin_target#"$DOCS"/}"; mission_rel="${mission_rel%/mission-state.json}"
    if ! pin_out="$(bash "$SCRIPT_DIR/harness-spec-pin.sh" "$PROJECT_ROOT" "$mission_rel" verify text 2>/dev/null)"; then
      {
        echo "[company-complete] REFUSED: this mission was built against a spec that has since moved."
        echo "$pin_out"
      } >&2
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | company-complete | refused | spec-pin drift (Hard Rule 4)" >> "$PROJECT_ROOT/.harness/progress.log" 2>/dev/null || true
      exit 1
    fi
  fi
fi

if ! bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
  '.company_state.state = "idle" |
   .company_state.active_workers = 0 |
   .company_state.completed_at = (now | todate) |
   .conductor.state = "completed" |
   .conductor.current_action = ("complete:" + $reason) |
   .conductor.completed_at = (now | todate) |
   .conductor.tracks = [] |
   .conductor.rendezvous = null |
   .conductor.fork_meeting_id = null |
   .current_agent = null |
   .next_agent = "none" |
   .agent_status = "completed" |
   .owner_prompt.status = "completed" |
   .owner_prompt.completed_at = (now | todate) |
   del(.owner_prompt.blocked_reason) |
   del(.owner_prompt.blocked_at) |
   del(.conductor.blocked_at)' \
  --arg reason "$REASON"; then
  echo "[company-complete] FAILED: progress.json transition did not apply (reason=$REASON). Runtime is NOT marked complete." >&2
  exit 1
fi

if [ -f "$TODOS" ]; then
  tmp="$(mktemp)"
  jq '
    .owners |= with_entries(
      .value |= map(
        if (.status == "active" or .status == "pending" or .status == "paused" or .status == "blocked")
        then .status = "done" | del(.blocked_reason) | .updated_at = (now | todate)
        else .
        end
      )
    )
  ' "$TODOS" > "$tmp" && mv "$tmp" "$TODOS"
fi

if [ -d "$DOCS" ]; then
  target_state="$(pick_transition_mission_state)"
  if [ -n "$target_state" ]; then
    lifecycle="$(jq -r '.lifecycle // .status // "unknown"' "$target_state" 2>/dev/null || echo unknown)"
    case "$lifecycle" in
      closed|cancelled|superseded|complete|completed) ;;
      *)
        tmp="$(mktemp)"
        jq '.lifecycle = "complete" | .active = false | .completed_at = (now | todate) | del(.blocked_reason) | del(.blocked_at)' "$target_state" > "$tmp" && mv "$tmp" "$target_state"
        ;;
    esac
  fi
fi

if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/harness-activity-record.js" ]; then
  node "$SCRIPT_DIR/harness-activity-record.js" "$PROJECT_ROOT" >/dev/null 2>&1 || true
fi

echo "[company-complete] marked complete: $REASON"
