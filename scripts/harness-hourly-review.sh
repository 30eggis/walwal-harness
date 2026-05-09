#!/bin/bash
# harness-hourly-review.sh — deterministic hourly company record
#
# Every hourly batch must leave evidence. This writes a meeting record and, for
# production services, runs Service-Ops monitoring first.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"

[ -f "$PROGRESS" ] || exit 0
[ -f "$CONFIG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

if [ "$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null || echo idle)" = "waiting_owner" ]; then
  jq '
    .conductor.state = "waiting_meeting" |
    .conductor.current_action = "autonomous-normalize-waiting-owner" |
    .next_agent = "meeting-manager" |
    .agent_status = "pending" |
    .meetings.active = ((.meetings.active // []) + ["meeting-manager"] | unique) |
    .meetings.requested_type = (.meetings.requested_type // "followup-review") |
    .meetings.requested_reason = (.meetings.requested_reason // "autonomous-normalize-waiting-owner") |
    .workflow.stage = "ops-monitoring" |
    .workflow.last_transition = (now | todate) |
    .workflow.last_reason = "autonomous-normalize-waiting-owner"
  ' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
id="M-$(date -u +%Y%m%dT%H%M%SZ)-hourly"
meeting_dir="$PROJECT_ROOT/.harness/actions/meetings/$id"
meeting_rel=".harness/actions/meetings/$id/meeting-$id.md"
meeting_path="$PROJECT_ROOT/$meeting_rel"
log_path="$PROJECT_ROOT/.harness/progress.log"

mkdir -p "$meeting_dir"

ops_report=""
if [ -x "$SCRIPT_DIR/harness-service-ops-monitor.sh" ]; then
  ops_report="$(bash "$SCRIPT_DIR/harness-service-ops-monitor.sh" "$PROJECT_ROOT" 2>/dev/null || true)"
fi

project_name="$(basename "$PROJECT_ROOT")"
goal_id="$(jq -r '.goals.active_id // "none"' "$PROGRESS" 2>/dev/null || echo none)"
current_agent="$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null || echo none)"
next_agent="$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null || echo none)"
agent_status="$(jq -r '.agent_status // "unknown"' "$PROGRESS" 2>/dev/null || echo unknown)"
conductor_state="$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null || echo idle)"
tick_count="$(jq -r '.conductor.tick_count // 0' "$PROGRESS" 2>/dev/null || echo 0)"
health_count="$(jq -r '(.service_ops.health // []) | length' "$PROGRESS" 2>/dev/null || echo 0)"
alert_count="$(jq -r '[.service_ops.health[]? | select(.status == "down" or .status == "degraded")] | length' "$PROGRESS" 2>/dev/null || echo 0)"
warn_count="$(jq -r '[.service_ops.health[]? | select(.status == "warn" or .status == "log_missing")] | length' "$PROGRESS" 2>/dev/null || echo 0)"
queue_summary="not configured"
if [ -f "$PROJECT_ROOT/.harness/actions/feature-queue.json" ]; then
  queue_summary="$(jq -r '"ready=\(.queue.ready|length), in_progress=\(.queue.in_progress|length), passed=\(.queue.passed|length), failed=\(.queue.failed|length)"' "$PROJECT_ROOT/.harness/actions/feature-queue.json" 2>/dev/null || echo "unreadable")"
fi

verdict="working"
if [ "$alert_count" -gt 0 ]; then
  verdict="incident"
elif [ "$conductor_state" = "escalated" ]; then
  verdict="owner_needed"
elif [ "$conductor_state" = "waiting_owner" ]; then
  verdict="autonomous_review"
elif [ "$current_agent" = "none" ] && [ "$next_agent" = "none" ]; then
  verdict="idle"
fi

{
  echo "# Hourly Company Review"
  echo ""
  echo "- id: $id"
  echo "- ts: $ts"
  echo "- project: $project_name"
  echo "- goal: $goal_id"
  echo "- verdict: $verdict"
  echo ""
  echo "## Company State"
  echo ""
  echo "- conductor: $conductor_state"
  echo "- tick_count: $tick_count"
  echo "- current_agent: $current_agent ($agent_status)"
  echo "- next_agent: $next_agent"
  echo "- queue: $queue_summary"
  echo ""
  echo "## Service-Ops"
  echo ""
  echo "- monitored_services: $health_count"
  echo "- warnings: $warn_count"
  echo "- alerts: $alert_count"
  if [ -n "$ops_report" ]; then
    echo "- ops_report: $ops_report"
  fi
  echo ""
  if [ "$health_count" -gt 0 ]; then
    echo "| Service | Port | Health | Log | Status |"
    echo "|---|---:|---|---|---|"
    jq -r '(.service_ops.health // [])[] |
      "| \(.name) | \(.host):\(.port) \(.port_state) | " +
      (if .health_path == null then "n/a" else ((.health_status // "000")|tostring) + "/" + ((.expected_status // 200)|tostring) end) +
      " | " +
      (if (.log.configured|not) then "not configured" elif (.log.exists|not) then "missing" else ((.log.recent_errors|tostring) + " recent errors") end) +
      " | \(.status) |"' "$PROGRESS"
  else
    echo "No production services are configured for Service-Ops monitoring."
  fi
  echo ""
  echo "## Decision"
  echo ""
  case "$verdict" in
    incident)
      echo "Service-Ops found a production alert. Conductor should route incident handling before normal feature work."
      ;;
    owner_needed)
      echo "Company loop is escalated and requires explicit intervention because conductor is $conductor_state."
      ;;
    autonomous_review)
      echo "Owner input is treated as an interrupt only. Continue the autonomous company loop through Meeting-Manager and Service-Ops toward the active GOAL."
      ;;
    idle)
      echo "No active company work is visible in progress.json."
      ;;
    *)
      echo "Continue autonomous company loop toward the active GOAL."
      ;;
  esac
} > "$meeting_path"

jq --arg ts "$ts" --arg id "$id" --arg rel "$meeting_rel" --arg verdict "$verdict" '
	  .meetings.last_type = "hourly-review" |
	  .meetings.last_reason = $verdict |
	  .meetings.last_review_at = $ts |
	  .meetings.last_review_path = $rel |
	  if $verdict == "incident" or $verdict == "autonomous_review" or $verdict == "idle"
	  then .meetings.active = ((.meetings.active // []) + ["meeting-manager"] | unique) |
	       .meetings.requested_type = (.meetings.requested_type // "followup-review") |
	       .meetings.requested_reason = (.meetings.requested_reason // $verdict)
	  else . end |
	  .service_ops.monitor.last_hourly_review = $ts
	' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

echo "$ts | meeting-manager | hourly-review | $verdict | $id | $meeting_rel" >> "$log_path"
echo "$meeting_rel"
