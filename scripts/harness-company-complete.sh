#!/bin/bash
# harness-company-complete.sh — mark the current v7 company mission complete.
#
# Usage:
#   bash scripts/harness-company-complete.sh <project-root> [reason] [mission-rel]
#
# This is the explicit running -> idle/done transition used by dashboard,
# runner, hooks, and final CEO handoff paths. It intentionally only updates
# runtime state and mission lifecycle; it does not archive mission documents.

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

refuse() {
  echo "[company-complete] REFUSED: $1" >&2
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | company-complete | refused | $1" >> "$PROJECT_ROOT/.harness/progress.log"
  if [ -n "${target_state:-}" ] && jq -e '.lifecycle == "complete" or .lifecycle == "completed"' "$target_state" >/dev/null; then
    echo 'Restore active:true and lifecycle:active, then retry.' >&2
  fi
  exit 1
}

target_state=""
if [ "$#" -ge 3 ]; then
  mission_rel="$3"
  case "$mission_rel" in ""|/*|*..*) refuse invalid-mission-path ;; esac
  target_dir="$(cd "$DOCS/$mission_rel" 2>/dev/null && pwd -P)" || refuse invalid-mission-path
  case "$target_dir/" in "$(cd "$DOCS" && pwd -P)/"*) ;; *) refuse invalid-mission-path ;; esac
  target_state="$target_dir/mission-state.json"
  [ -f "$target_state" ] || refuse missing-mission-state
else
  target_state="$(pick_transition_mission_state)"
fi
ended=false
tiered=false
gate_scope=latest-active
# Explicit targets scope the existing lessons gate even for legacy missions.
if [ "$#" -ge 3 ]; then gate_scope="mission:$3"; fi
if [ -n "$target_state" ]; then
  lifecycle=$(jq -r '.lifecycle // .status // "unknown"' "$target_state") || refuse invalid-mission-state
  case "$lifecycle" in cancelled|superseded|closed) ended=true ;; esac
  if jq -e 'has("tier")' "$target_state" >/dev/null; then
    tiered=true
    mission_rel="${target_state#"$DOCS"/}"
    # Explicit targets were canonicalized; retain the caller's relative path.
    if [ "$#" -ge 3 ]; then mission_rel="$3/mission-state.json"; fi
    mission_rel="${mission_rel%/mission-state.json}"
    gate_scope="mission:$mission_rel"
  fi
fi

if [ "$ended" = false ]; then
  if [ "${HARNESS_SKIP_LESSONS_GATE:-0}" != 1 ] && [ -x "$SCRIPT_DIR/harness-lessons-gate.sh" ]; then
    gate_out=$(bash "$SCRIPT_DIR/harness-lessons-gate.sh" "$PROJECT_ROOT" text "$gate_scope") || refuse "lessons-gate: $gate_out"
  fi
  if [ "$tiered" = true ]; then
    evidence=$(bash "$SCRIPT_DIR/harness-worker-evidence-validate.sh" "$PROJECT_ROOT" text "$gate_scope") || refuse "worker-evidence: $evidence"
    mission_dir="$(dirname "$target_state")"
    [ -f "$mission_dir/cqo.md" ] || refuse missing-verdict
    verdict=$(awk '
      /^[[:space:]]*>?[[:space:]]*##[[:space:]]+CQO Verdict([[:space:]]+\([^)]*\))?[[:space:]]*$/ { inb=1; next }
      /^[[:space:]]*>?[[:space:]]*#{1,2}[[:space:]]/ { inb=0 }
      inb { candidate=$0; sub(/^[[:space:]>*_-]*/, "", candidate)
        if (tolower(candidate) ~ /^verdict[*_[:space:]]*:/) last=$0 }
      END {
        if (last == "") print "missing"
        else if (last ~ /^[[:space:]]*>?[[:space:]]*Verdict:[[:space:]]*(PASS|ACCEPTED|FAIL|REJECTED|BLOCKED)[[:space:]]*$/) {
          sub(/^[[:space:]]*>?[[:space:]]*Verdict:[[:space:]]*/, "", last)
          sub(/[[:space:]]*$/, "", last); print last
        } else print "invalid"
      }
    ' "$mission_dir/cqo.md") || refuse invalid-final-verdict
    case "$verdict" in
      PASS|ACCEPTED) ;;
      missing) refuse missing-verdict ;;
      invalid) refuse invalid-final-verdict ;;
      *) refuse verdict-not-pass ;;
    esac
    tier=$(jq -r 'def r: if . == "S" then 0 elif . == "M" then 1 else 2 end;
      [.tier, (.tier_history[]? | .from, .to)] | map(r) | max' "$target_state") || refuse invalid-tier-state
    if [ -f "$PROJECT_ROOT/.harness/config.json" ]; then
      enabled=$(jq -r 'if .behavior.mission_tiers == null then true else .behavior.mission_tiers end' "$PROJECT_ROOT/.harness/config.json") || refuse invalid-config
      [ "$enabled" != false ] || tier=2
    fi
    if [ "$tier" -eq 0 ]; then
      grep -Eq '^[[:space:]]*>?[[:space:]]*##[[:space:]]+Direct Work[[:space:]]*$' "$mission_dir/cto.md" || refuse missing-direct-work
      grep -Eq '^[[:space:]]*>?[[:space:]]*##[[:space:]]+Verification Commands[[:space:]]*$' "$mission_dir/cqo.md" || refuse missing-verification-commands
      session=$(sed -nE 's/^[[:space:]]*Verification Session: (separate|same-session)[[:space:]]*$/\1/p' "$mission_dir/cqo.md" | tail -1)
      [ -n "$session" ] || refuse missing-verification-session
      if [ "$session" = same-session ]; then
        echo '[company-complete] WARNING: same-session-verification; disclose to Owner.' >&2
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | company-complete | warn | same-session-verification" >> "$PROJECT_ROOT/.harness/progress.log"
      fi
    fi
  fi
fi

# Corpus reachability (Hard Rule 11) and spec pins (Hard Rule 4) are re-checked
# at the same point, for the same reason: both are promises that decay silently
# between when they are made and when the mission claims to be done.
if [ "${HARNESS_SKIP_LESSONS_GATE:-0}" != "1" ] && [ -x "$SCRIPT_DIR/harness-corpus-reachability.sh" ]; then
  if ! reach_out="$(bash "$SCRIPT_DIR/harness-corpus-reachability.sh" "$PROJECT_ROOT" text 2>/dev/null)"; then
    refuse "corpus-reachability: $reach_out"
  fi
fi

# Spec pins are verified against the mission this transition would close. This
# sits BEFORE the runtime transition on purpose: a refusal that runs after
# progress.json is already `completed` has refused nothing.
if [ "$ended" = false ] && [ "${HARNESS_SKIP_LESSONS_GATE:-0}" != "1" ] && [ -x "$SCRIPT_DIR/harness-spec-pin.sh" ] && [ -d "$DOCS" ]; then
  pin_target="$target_state"
  if [ -n "$pin_target" ]; then
    mission_rel="${pin_target#"$DOCS"/}"; mission_rel="${mission_rel%/mission-state.json}"
    if [ "$#" -ge 3 ]; then mission_rel="$3"; fi
    if ! pin_out="$(bash "$SCRIPT_DIR/harness-spec-pin.sh" "$PROJECT_ROOT" "$mission_rel" verify text 2>/dev/null)"; then
      refuse "spec-pin drift: $pin_out"
    fi
  fi
fi

if [ "$ended" = true ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | company-complete | ended-without-acceptance | $lifecycle" >> "$PROJECT_ROOT/.harness/progress.log"
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
  if [ -n "$target_state" ]; then
    lifecycle="$(jq -r '.lifecycle // .status // "unknown"' "$target_state" 2>/dev/null || echo unknown)"
    case "$lifecycle" in
      closed|cancelled|superseded) ;;
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
