#!/bin/bash
# harness-hourly-review.sh — deterministic hourly executive meeting record
#
# Every hourly batch must leave evidence. This writes executive meeting minutes
# and, for production services, runs Service-Ops monitoring first.

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
drift="$(jq -r '.service_ops.drift_classification // .meetings.decision.drift_classification // "unknown"' "$PROGRESS" 2>/dev/null || echo unknown)"
last_decision="$(jq -r '.meetings.last_decision // "none"' "$PROGRESS" 2>/dev/null || echo none)"
last_meeting="$(jq -r '.meetings.last_review_path // .meetings.current_record_path // "none"' "$PROGRESS" 2>/dev/null || echo none)"
cqo_audit="$(jq -r '.cqo.audit_path // empty' "$PROGRESS" 2>/dev/null || true)"
cto_review="$(jq -r '.cto.review_path // empty' "$PROGRESS" 2>/dev/null || true)"
open_incidents="$(jq -r '(.service_ops.incident.open // []) | length' "$PROGRESS" 2>/dev/null || echo 0)"
owner_escalation="false"

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

meeting_type="standup"
decision_owner="planner"
decision_action="execution-plan"
decision_rationale="정기 회의에서 active GOAL 대비 현재 작업과 운영 신호를 재정렬하고 다음 work package를 명확히 한다."
case "$next_agent" in
  planner|cto|cqo|service-ops|dispatcher)
    decision_owner="$next_agent"
    decision_action="continue-current-handoff"
    decision_rationale="정기 회의에서 현재 handoff가 GOAL과 충돌하지 않음을 확인했으므로 예정된 내부 owner가 계속 진행한다."
    ;;
esac
if [ "$verdict" = "incident" ]; then
  meeting_type="incident-war-room"
  decision_owner="cto"
  decision_action="runtime-recovery"
  decision_rationale="Service-Ops가 down/degraded 신호를 발견했으므로 CTO가 복구 경로를 정하고 CQO가 복구 evidence를 검증한다."
elif [ "$verdict" = "idle" ] || [ "$verdict" = "autonomous_review" ]; then
  meeting_type="followup-review"
  decision_owner="planner"
  decision_action="goal-alignment"
  decision_rationale="Owner 대기 없이 CEO/COO/CTO/CQO/Service-Ops가 GOAL 대비 다음 work package를 재정렬한다."
elif [ "$verdict" = "owner_needed" ]; then
  meeting_type="all-hands"
  decision_owner="dispatcher"
  decision_action="escalate-owner"
  decision_rationale="conductor가 escalated 상태이므로 CEO가 Owner escalation 필요성을 판정한다."
  owner_escalation="true"
fi

decision_json="$(jq -n \
  --arg owner "$decision_owner" \
  --arg action_type "$decision_action" \
  --arg rationale "$decision_rationale" \
  --arg drift "$drift" \
  --arg source "$meeting_rel" \
  --arg ops_report "$ops_report" \
  --arg cqo_audit "$cqo_audit" \
  --arg cto_review "$cto_review" \
  --argjson owner_escalation "$owner_escalation" '
  {
    owner: $owner,
    action_type: $action_type,
    rationale: $rationale,
    evidence: (
      [
        (if $ops_report != "" then {source:$ops_report, kind:"ops-report"} else empty end),
        (if $cqo_audit != "" then {source:$cqo_audit, kind:"cqo-audit"} else empty end),
        (if $cto_review != "" then {source:$cto_review, kind:"cto-review"} else empty end)
      ]
    ),
    drift_classification: $drift,
    source_path: $source,
    owner_escalation: $owner_escalation,
    tracks: [],
    rendezvous: null
  }')"
meeting_json="$(jq -n \
  --arg meeting_id "$id" \
  --arg type "$meeting_type" \
  --arg reason "$verdict" \
  --arg source_path "$meeting_rel" \
  --argjson decision "$decision_json" \
  '{meeting_id:$meeting_id,type:$type,reason:$reason,decision:($decision + {source_path:$source_path})}')"

{
  echo "# Hourly Executive Meeting Minutes"
  echo ""
  echo "- id: $id"
  echo "- ts: $ts"
  echo "- project: $project_name"
  echo "- goal: $goal_id"
  echo "- type: $meeting_type"
  echo "- verdict: $verdict"
  echo "- chair: Meeting-Manager"
  echo "- attendees: Dispatcher/CEO, Planner/COO, CTO, CQO, Service-Ops"
  echo ""
  echo "## Evidence Read Before Discussion"
  echo ""
  echo "- conductor: $conductor_state"
  echo "- tick_count: $tick_count"
  echo "- current_agent: $current_agent ($agent_status)"
  echo "- next_agent: $next_agent"
  echo "- queue: $queue_summary"
  echo "- drift_classification: $drift"
  echo "- previous_decision: $last_decision"
  echo "- previous_meeting: $last_meeting"
  if [ -n "$ops_report" ]; then
    echo "- service_ops_report: $ops_report"
  fi
  if [ -n "$cto_review" ]; then
    echo "- cto_review: $cto_review"
  fi
  if [ -n "$cqo_audit" ]; then
    echo "- cqo_audit: $cqo_audit"
  fi
  echo ""
  echo "## Role Briefs"
  echo ""
  echo "### Dispatcher/CEO"
  case "$verdict" in
    owner_needed)
      echo "- 판단: escalation 상태이므로 Owner에게 외부 결정이 필요한지 확인한다."
      ;;
    *)
      echo "- 판단: 최초 GOAL 이후 Owner 입력은 interrupt다. 회사는 Owner를 기다리지 않고 GOAL 달성 루프를 계속한다."
      ;;
  esac
  echo "- 관심사: active GOAL, KPI, Owner-facing escalation 필요성."
  echo ""
  echo "### Planner/COO"
  if [ "$verdict" = "idle" ] || [ "$verdict" = "autonomous_review" ]; then
    echo "- 판단: work package가 멈췄거나 Owner 대기처럼 보이는 상태다. 다음 operating cycle을 재정렬해야 한다."
  else
    echo "- 판단: 현재 queue와 next_agent가 GOAL에 맞는지 유지 점검한다."
  fi
  echo "- 관심사: planning drift, hypothesis 필요성, 다음 work package 정의."
  echo ""
  echo "### CTO"
  if [ "$alert_count" -gt 0 ]; then
    echo "- 판단: 운영 장애가 구현/런타임 복구 대상인지 우선 판정하고 복구 owner를 지정해야 한다."
  else
    echo "- 판단: 현재 구현/아키텍처 흐름이 다음 handoff를 받을 수 있는지 확인한다."
  fi
  echo "- 관심사: implementation drift, runtime recovery, generator/evaluator 재배정."
  echo ""
  echo "### CQO"
  echo "- 판단: 회의 결론은 evidence가 있는 항목만 통과시킨다. 복구/변경 후 회귀 검증 기준을 요구한다."
  echo "- 관심사: quality drift, missing tests, PASS/FAIL 근거."
  echo ""
  echo "### Service-Ops"
  echo ""
  echo "- monitored_services: $health_count"
  echo "- warnings: $warn_count"
  echo "- alerts: $alert_count"
  echo "- open_incidents: $open_incidents"
  echo "- 판단: 운영 신호를 회의에 제출하고, 장애 시 incident-war-room을 요구한다."
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
  echo "## Discussion"
  echo ""
  case "$verdict" in
    incident)
      echo "- Service-Ops: down/degraded 서비스가 있으므로 feature work보다 장애 triage가 우선이다."
      echo "- CTO: 복구 절차, 재시작, 설정 누락, 포트 충돌 중 원인을 좁히고 runtime-recovery work item을 받는다."
      echo "- CQO: 복구 완료 주장은 health check와 재현 가능한 evidence 없이는 PASS로 보지 않는다."
      echo "- COO: 장애 복구가 GOAL 진행을 막는 범위를 queue에 반영한다."
      echo "- CEO: Owner에게 묻지 않고 내부 복구 루프를 진행한다. 단 GOAL 변경이 필요하면 별도 escalation한다."
      ;;
    owner_needed)
      echo "- CEO: conductor escalation의 원인이 내부 해결 가능한지 우선 판정한다."
      echo "- COO/CTO/CQO/Service-Ops: 각자 해결 가능한 내부 action을 제시하고, 불가능할 때만 Owner escalation을 유지한다."
      ;;
    autonomous_review)
      echo "- CEO: Owner 입력은 interrupt이므로 대기하지 않는다."
      echo "- COO: 다음 work package를 재정렬한다."
      echo "- CTO/CQO/Service-Ops: 구현, 검증, 운영 관점에서 다음 handoff를 준비한다."
      ;;
    idle)
      echo "- Meeting-Manager: idle은 Owner 대기가 아니라 operating cycle 재개 신호다."
      echo "- COO: GOAL 대비 다음 후보 작업을 선정한다."
      echo "- CTO/CQO/Service-Ops: 각자 실행/검증/운영 준비 상태를 점검한다."
      ;;
    *)
      echo "- 회의 결론: 현재 GOAL을 유지하고 다음 autonomous tick에서 conductor가 다음 부서를 배정한다."
      ;;
  esac
  echo ""
  echo "## Decision JSON"
  echo ""
  echo '```json'
  jq '.' <<<"$meeting_json"
  echo '```'
  echo ""
  echo "## Action Items"
  echo ""
  case "$verdict" in
    incident)
      echo "- CTO: runtime recovery work item을 열고 down/degraded 서비스 복구 경로를 실행한다."
      echo "- Service-Ops: 복구 후 monitor를 다시 돌려 last_check와 health evidence를 갱신한다."
      echo "- CQO: 복구 evidence를 검증하고 regression risk를 기록한다."
      ;;
    idle|autonomous_review)
      echo "- Planner/COO: Owner 대기 없이 active GOAL 기준 다음 work package를 정의한다."
      echo "- Conductor: meeting decision을 읽고 다음 부서를 자동 배정한다."
      ;;
    *)
      echo "- Conductor: 다음 autonomous tick에서 decision.owner/action_type 기준으로 handoff한다."
      ;;
  esac
} > "$meeting_path"

jq --arg ts "$ts" --arg id "$id" --arg rel "$meeting_rel" --arg verdict "$verdict" --arg type "$meeting_type" --argjson decision "$decision_json" '
	  .meetings.last_type = "hourly-review" |
	  .meetings.last_reason = $verdict |
	  .meetings.last_review_at = $ts |
	  .meetings.last_review_path = $rel |
	  .meetings.current_id = $id |
	  .meetings.current_record_path = $rel |
	  .meetings.last_attendees = ["dispatcher","planner","cto","cqo","service-ops","meeting-manager"] |
	  .meetings.decision = $decision |
	  if $verdict == "incident" or $verdict == "autonomous_review" or $verdict == "idle"
	  then .meetings.active = ((.meetings.active // []) + ["meeting-manager","dispatcher","planner","cto","cqo","service-ops"] | unique) |
	       .meetings.requested_type = (.meetings.requested_type // $type) |
	       .meetings.requested_reason = (.meetings.requested_reason // $verdict)
	  else . end |
	  .service_ops.monitor.last_hourly_review = $ts
	' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

echo "$ts | meeting-manager | hourly-review | $verdict | $id | $meeting_rel" >> "$log_path"
echo "$meeting_rel"
