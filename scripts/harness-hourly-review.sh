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
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
meeting_dir="$PROJECT_ROOT/.harness/actions/meetings/$id"
meeting_rel=".harness/actions/meetings/$id/meeting-$id.md"
meeting_path="$PROJECT_ROOT/$meeting_rel"
log_path="$PROJECT_ROOT/.harness/progress.log"

# meeting_dir is created lazily, only when this tick actually has a signal worth a
# meeting doc (see the write-on-signal gate below). No-signal ticks must not even
# leave an empty M-*-hourly directory behind.

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
conductor_action="$(jq -r '.conductor.current_action // "none"' "$PROGRESS" 2>/dev/null || echo none)"
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
incident_repeat_count="$(jq -r '.service_ops.incident.repeat_count // 0' "$PROGRESS" 2>/dev/null || echo 0)"
incident_recovery_required="$(jq -r '.service_ops.incident.recovery_required // false' "$PROGRESS" 2>/dev/null || echo false)"
prev_required_json="$(jq -c '.meetings.decision.required_execution // .meetings.required_execution // null' "$PROGRESS" 2>/dev/null || echo null)"
prev_required_action="$(jq -r '(.meetings.decision.required_execution // .meetings.required_execution // {}).action // "none"' "$PROGRESS" 2>/dev/null || echo none)"
prev_required_owner="$(jq -r '(.meetings.decision.required_execution // .meetings.required_execution // {}).owner // "none"' "$PROGRESS" 2>/dev/null || echo none)"
prev_required_deliverable="$(jq -r '(.meetings.decision.required_execution // .meetings.required_execution // {}).deliverable_path // ""' "$PROGRESS" 2>/dev/null || true)"
prev_execution_result="none"
prev_execution_detail="no prior required_execution"
if [ "$prev_required_json" != "null" ]; then
  if [ -n "$prev_required_deliverable" ] && [ -f "$PROJECT_ROOT/$prev_required_deliverable" ]; then
    prev_execution_result="executed_unverified"
    prev_execution_detail="deliverable exists: $prev_required_deliverable"
    if [ "$prev_required_action" = "runtime-recovery-runbook" ] && [ "${open_incidents:-0}" -eq 0 ] && [ "$alert_count" -eq 0 ]; then
      prev_execution_result="executed_and_verified"
      prev_execution_detail="deliverable exists and Service-Ops has no open incident"
    fi
  elif [ "$prev_required_action" = "runtime-recovery-runbook" ] && [ "$(jq -r '.cto.step_b_status // .cto.step_a_status // ""' "$PROGRESS" 2>/dev/null || true)" != "" ]; then
    prev_execution_result="attempted_blocked"
    prev_execution_detail="CTO recovery state advanced but required deliverable missing: ${prev_required_deliverable:-unset}"
  else
    prev_execution_result="paperwork_only_failure"
    prev_execution_detail="required deliverable missing: ${prev_required_deliverable:-unset}"
  fi
fi
owner_escalation="false"
strategy_total_signals=0
strategy_previous_signals="$(jq -r '.goals.strategy_cadence.total_signals // 0' "$PROGRESS" 2>/dev/null || echo 0)"
strategy_delta=0
strategy_status="not_applicable"
strategy_target_per_hour=0
strategy_target_per_day=0
strategy_last_signal="none"
strategy_required=false

if grep -Eiq 'strategy|algo|backtest|신규.?전략|시간당.?1|일.?6|daily.?6|hourly.?1' "$log_path" "$PROJECT_ROOT/.harness/actions/goals.md" 2>/dev/null; then
  strategy_required=true
  strategy_target_per_hour=1
  strategy_target_per_day=6
  strategy_total_signals="$(grep -Eic '(^|[|[:space:]])(new-strategy|strategy-generated|algos?_candidate|backtest-jobs?|backtest_enqueue|신규.?전략|전략.?생성)([|[:space:]]|$)' "$log_path" 2>/dev/null || echo 0)"
  strategy_last_signal="$(grep -Ei '(^|[|[:space:]])(new-strategy|strategy-generated|algos?_candidate|backtest-jobs?|backtest_enqueue|신규.?전략|전략.?생성)([|[:space:]]|$)' "$log_path" 2>/dev/null | tail -1 || true)"
  [ -n "$strategy_last_signal" ] || strategy_last_signal="none"
  if [ "$strategy_total_signals" -lt "$strategy_previous_signals" ]; then
    strategy_previous_signals="$strategy_total_signals"
  fi
  strategy_delta=$((strategy_total_signals - strategy_previous_signals))
  if [ "$strategy_delta" -ge "$strategy_target_per_hour" ]; then
    strategy_status="on_track"
  else
    strategy_status="behind_goal"
  fi
fi

verdict="working"
if [ "$alert_count" -gt 0 ]; then
  verdict="incident"
elif [ "$strategy_required" = "true" ] && [ "$strategy_status" = "behind_goal" ]; then
  verdict="goal_drift"
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
progress_meaningful_json='[]'
required_execution_json='null'
handoff_requires_execution=false
handoff_feature="$(printf "%s" "$conductor_action" | awk -F: '{print $NF}')"
case "$handoff_feature" in
  ""|none|null|pass-through|monitor|completed|running|ready|execution-plan|continue-current-handoff|goal-alignment)
    handoff_feature="$stamp"
    ;;
esac
safe_handoff_feature="$(printf "%s" "$handoff_feature" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-//; s/-$//')"
[ -n "$safe_handoff_feature" ] || safe_handoff_feature="$stamp"

case "$next_agent" in
  planner|cto|cqo|generator-*|evaluator-*|documentationer|coo-developer)
    if [ "$next_agent" != "$current_agent" ] || [[ "$conductor_action" == *handoff* ]] || [[ "$conductor_action" == advance:* ]] || [[ "$conductor_action" == spawn:* ]] || [[ "$conductor_action" == dispatch:* ]]; then
      handoff_requires_execution=true
    fi
    ;;
esac
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
  if [ "$incident_recovery_required" = "true" ] || [ "${incident_repeat_count:-0}" -ge 2 ]; then
    decision_action="runtime-recovery-runbook"
    decision_rationale="동일 운영 장애가 ${incident_repeat_count}회 연속 감지됐다. 반복 회의가 아니라 CTO가 복구 runbook을 실행하고 CQO가 evidence를 검증한다."
    progress_meaningful_json='["runtime-recovery-runbook required"]'
    required_execution_json="$(jq -n --arg id "RE-$stamp-runtime-recovery" --arg source "$meeting_rel" '{
      id:$id,
      owner:"cto",
      action:"runtime-recovery-runbook",
      deliverable_path:".harness/actions/cto-runbook-runtime-recovery-current.md",
      verifier:"cqo+service-ops",
      due:"next_tick",
      source_path:$source,
      success_condition:"Service-Ops verifies every configured production service as ok; partial recovery remains incident."
    }')"
  else
    decision_action="runtime-recovery"
    decision_rationale="Service-Ops가 down/degraded 신호를 발견했으므로 CTO가 복구 경로를 정하고 CQO가 복구 evidence를 검증한다."
    progress_meaningful_json='["runtime-recovery decision"]'
    required_execution_json="$(jq -n --arg id "RE-$stamp-runtime-recovery" --arg source "$meeting_rel" '{
      id:$id,
      owner:"cto",
      action:"runtime-recovery",
      deliverable_path:".harness/actions/cto-action-runtime-recovery-current.md",
      verifier:"service-ops",
      due:"next_tick",
      source_path:$source,
      success_condition:"Service-Ops health improves or records a concrete blocker."
    }')"
  fi
elif [ "$verdict" = "idle" ] || [ "$verdict" = "autonomous_review" ]; then
  meeting_type="followup-review"
  decision_owner="planner"
  decision_action="goal-alignment"
  decision_rationale="Owner 대기 없이 CEO/COO/CTO/CQO/Service-Ops가 GOAL 대비 다음 work package를 재정렬한다."
elif [ "$verdict" = "goal_drift" ]; then
  meeting_type="spec-review"
  decision_owner="planner"
  decision_action="strategy-cadence-recovery"
  decision_rationale="전략 생성 cadence가 목표보다 뒤처졌다. COO가 다음 시간의 전략 후보 생성/백테스트 work package를 즉시 재배정한다."
  progress_meaningful_json='["strategy cadence recovery decision"]'
  required_execution_json="$(jq -n --arg id "RE-$stamp-strategy-cadence" --arg source "$meeting_rel" --arg deliverable ".harness/actions/strategy-work-package-${stamp}.md" '{
    id:$id,
    owner:"planner",
    action:"create-strategy-work-package",
    deliverable_path:$deliverable,
    verifier:"cqo",
    due:"next_tick",
    source_path:$source,
    success_condition:"A strategy work package exists with candidate idea, data source, backtest command, and CQO acceptance criteria."
  }')"
elif [ "$verdict" = "owner_needed" ]; then
  meeting_type="all-hands"
  decision_owner="dispatcher"
  decision_action="escalate-owner"
  decision_rationale="conductor가 escalated 상태이므로 CEO가 Owner escalation 필요성을 판정한다."
  owner_escalation="true"
fi

if [ "$verdict" = "working" ] && [ "$handoff_requires_execution" = "true" ]; then
  decision_owner="$next_agent"
  case "$next_agent" in
    planner)
      decision_action="execution-plan"
      deliverable_path=".harness/actions/planner-execution-plan-${safe_handoff_feature}.md"
      verifier="cto+cqo"
      success_condition="Planner creates a concrete execution plan that reconciles the current handoff with GOAL, queue priority, non-goals, owner, and verifier."
      ;;
    cto)
      decision_action="technical-handoff"
      deliverable_path=".harness/actions/cto-action-${safe_handoff_feature}.md"
      verifier="cqo"
      success_condition="CTO records implementation scope, affected files, validation commands, blocker status, and the next execution owner."
      ;;
    cqo)
      decision_action="quality-verification"
      deliverable_path=".harness/actions/cqo-audit-${safe_handoff_feature}.md"
      verifier="meeting-manager"
      success_condition="CQO records PASS/FAIL with evidence, regressions, and the next routing decision."
      ;;
    generator-*)
      decision_action="implement-${safe_handoff_feature}"
      deliverable_path=".harness/actions/gen-report-${safe_handoff_feature}.md"
      verifier="cqo+evaluator-code-quality"
      success_condition="Generator produces the named implementation report, changed-file list, validation output, and handoff to CQO/evaluator."
      ;;
    evaluator-*)
      decision_action="verify-${safe_handoff_feature}"
      deliverable_path=".harness/actions/evaluation-${safe_handoff_feature}.md"
      verifier="cqo"
      success_condition="Evaluator writes an evidence-backed PASS/FAIL report and does not rubber-stamp missing evidence."
      ;;
    documentationer)
      decision_action="document-${safe_handoff_feature}"
      deliverable_path=".harness/actions/documentation-${safe_handoff_feature}.md"
      verifier="planner"
      success_condition="Documentationer writes the requested brief/report with source paths and decision impact."
      ;;
    coo-developer)
      decision_action="spike-${safe_handoff_feature}"
      deliverable_path=".harness/actions/hypothesis/${safe_handoff_feature}/spike/report.md"
      verifier="planner+cqo"
      success_condition="COO developer records spike result, repro/evidence, and verdict input for Planner."
      ;;
    *)
      decision_action="execute-${safe_handoff_feature}"
      deliverable_path=".harness/actions/execution-${safe_handoff_feature}.md"
      verifier="meeting-manager"
      success_condition="The owner writes a concrete deliverable and next-step evidence before the following hourly review."
      ;;
  esac
  decision_rationale="working 상태라도 현재 handoff는 산출물 없는 '계속 진행'으로 통과할 수 없다. 다음 tick까지 owner가 deliverable을 남기고 verifier가 검증한다."
  progress_meaningful_json="$(jq -n --arg item "execution contract required: $next_agent/$decision_action" '[$item]')"
  required_execution_json="$(jq -n \
    --arg id "RE-$stamp-handoff" \
    --arg owner "$decision_owner" \
    --arg action "$decision_action" \
    --arg deliverable "$deliverable_path" \
    --arg verifier "$verifier" \
    --arg source "$meeting_rel" \
    --arg success "$success_condition" \
    --arg conductor_action "$conductor_action" \
    '{
      id:$id,
      owner:$owner,
      action:$action,
      deliverable_path:$deliverable,
      verifier:$verifier,
      due:"next_tick",
      source_path:$source,
      source_conductor_action:$conductor_action,
      success_condition:$success
    }')"
fi

# ── Write-on-signal gate ────────────────────────────────────────────────────
# Agreement: 문서 ≠ 텔레메트리. A no-delta hourly tick must not emit yet another
# identical meeting doc — it bumps a heartbeat counter instead. A "signal" is an
# incident, goal drift, owner escalation, a required-execution contract, a handoff
# that needs execution, or a change in verdict since the last recorded review.
# Control flow (conductor-tick.sh) routes off progress.json state, not this file,
# so suppressing the markdown on quiet ticks is safe.
write_on_signal="$(jq -r '.company_mode.write_on_signal // true' "$CONFIG" 2>/dev/null || echo true)"
last_verdict="$(jq -r '.meetings.last_reason // ""' "$PROGRESS" 2>/dev/null || echo "")"
has_signal=true
if [ "$write_on_signal" = "true" ]; then
  has_signal=false
  case "$verdict" in
    incident|goal_drift|owner_needed) has_signal=true ;;
  esac
  [ "$required_execution_json" != "null" ] && has_signal=true
  [ "$handoff_requires_execution" = "true" ] && has_signal=true
  # A change in verdict since the last recorded review is a state transition worth a
  # minute (this also makes the first-ever review a signal, since last_verdict is "").
  [ "$verdict" != "$last_verdict" ] && has_signal=true
fi

if [ "$has_signal" != "true" ]; then
  # No delta — heartbeat only. Keep service-ops health fresh, leave the last real
  # meeting pointer intact (read-decision fallback still resolves), and record that
  # this tick was a quiet checkpoint rather than a meeting.
  jq --arg ts "$ts" --arg verdict "$verdict" '
    .meetings.last_reason = $verdict |
    .meetings.last_review_at = $ts |
    .meetings.heartbeat_count = ((.meetings.heartbeat_count // 0) + 1) |
    .meetings.last_heartbeat_at = $ts |
    .meetings.last_heartbeat_verdict = $verdict |
    .service_ops.monitor.last_hourly_review = $ts
  ' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS" || { rm -f "${PROGRESS}.tmp"; exit 1; }
  hb="$(jq -r '.meetings.heartbeat_count // 0' "$PROGRESS" 2>/dev/null || echo '?')"
  echo "$ts | meeting-manager | hourly-heartbeat | $verdict | no-signal (heartbeat #$hb, no meeting doc)" >> "$log_path"
  # stdout: last real meeting path so the wake prompt keeps context (empty if none).
  jq -r '.meetings.last_review_path // empty' "$PROGRESS" 2>/dev/null || true
  exit 0
fi

mkdir -p "$meeting_dir"

decision_json="$(jq -n \
  --arg owner "$decision_owner" \
  --arg action_type "$decision_action" \
  --arg rationale "$decision_rationale" \
  --arg drift "$drift" \
  --arg source "$meeting_rel" \
  --arg ops_report "$ops_report" \
  --arg cqo_audit "$cqo_audit" \
  --arg cto_review "$cto_review" \
  --argjson progress_meaningful "$progress_meaningful_json" \
  --argjson required_execution "$required_execution_json" \
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
    progress_classification: {
      meaningful_actions: $progress_meaningful,
      paperwork_only: ["hourly-review", "service-ops-monitor"]
    },
    required_execution: $required_execution,
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
  echo "- previous_required_execution: $prev_required_owner/$prev_required_action"
  echo "- previous_execution_result: $prev_execution_result"
  echo "- previous_execution_detail: $prev_execution_detail"
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
  echo "## Progress Classification"
  echo ""
  echo "- previous_required_execution_result: $prev_execution_result"
  echo "- previous_required_execution_detail: $prev_execution_detail"
  if [ "$verdict" = "incident" ] && { [ "$incident_recovery_required" = "true" ] || [ "${incident_repeat_count:-0}" -ge 2 ]; }; then
    echo "- meaningful_actions: runtime-recovery-runbook required"
    echo "- paperwork_only: hourly meeting minutes, Service-Ops monitor report"
  elif [ "$verdict" = "goal_drift" ]; then
    echo "- meaningful_actions: strategy cadence recovery decision"
    echo "- paperwork_only: hourly meeting minutes, Service-Ops monitor report"
  else
    echo "- meaningful_actions: none detected in this deterministic batch until conductor/agent tick records execution"
    echo "- paperwork_only: hourly meeting minutes, Service-Ops monitor report"
  fi
  echo ""
  echo "## Role Briefs"
  echo ""
  echo "### Dispatcher/CEO"
  case "$verdict" in
    owner_needed)
      echo "- 판단: escalation 상태다. 먼저 CEO/CXX가 내부 권장안을 확정하고, 외부 권한(credentials/secrets, payment approval, legal/business acceptance, production access, destructive data action)이 필요할 때만 Owner-facing BLOCKED로 보고한다."
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
  echo "- incident_repeat_count: $incident_repeat_count"
  echo "- incident_recovery_required: $incident_recovery_required"
  if [ "$strategy_required" = "true" ]; then
    echo "- strategy_cadence: $strategy_status (delta=$strategy_delta, total_signals=$strategy_total_signals, target_per_hour=$strategy_target_per_hour, target_per_day=$strategy_target_per_day)"
    echo "- last_strategy_signal: $strategy_last_signal"
  fi
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
      if [ "$incident_recovery_required" = "true" ] || [ "${incident_repeat_count:-0}" -ge 2 ]; then
        echo "- CTO: 같은 장애가 반복됐으므로 추가 회의가 아니라 runtime-recovery-runbook 실행으로 전환한다."
      else
        echo "- CTO: 복구 절차, 재시작, 설정 누락, 포트 충돌 중 원인을 좁히고 runtime-recovery work item을 받는다."
      fi
      echo "- CQO: 복구 완료 주장은 health check와 재현 가능한 evidence 없이는 PASS로 보지 않는다."
      echo "- COO: 장애 복구가 GOAL 진행을 막는 범위를 queue에 반영한다."
      echo "- CEO: Owner에게 묻지 않고 내부 복구 루프를 진행한다. 단 GOAL 변경이 필요하면 별도 escalation한다."
      ;;
    goal_drift)
      echo "- CEO: Owner가 없어도 최초 GOAL의 KPI를 기준으로 회사 루프를 평가한다."
      echo "- COO: 전략 생성/백테스트 cadence가 목표보다 낮으므로 다음 work package를 전략 후보 생성으로 고정한다."
      echo "- CTO: 필요한 데이터/실행 경로가 막혔는지 점검한다."
      echo "- CQO: 후보 전략은 backtest evidence 없이는 유의미 진척으로 인정하지 않는다."
      echo "- Service-Ops: 운영 장애가 cadence 저하 원인인지 계속 감시한다."
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
    goal_drift)
      echo "- Planner/COO: 다음 autonomous tick에서 전략 후보 생성/백테스트 work package를 발급한다."
      echo "- CTO: 전략 실행 경로와 데이터 의존성 차단 여부를 점검한다."
      echo "- CQO: backtest 결과가 없는 후보를 유의미 진척으로 집계하지 않는다."
      ;;
    idle|autonomous_review)
      echo "- Planner/COO: Owner 대기 없이 active GOAL 기준 다음 work package를 정의한다."
      echo "- Conductor: meeting decision을 읽고 다음 부서를 자동 배정한다."
      ;;
    *)
      echo "- Conductor: 다음 autonomous tick에서 decision.owner/action_type 기준으로 handoff한다."
      ;;
  esac
  echo ""
  echo "## Required Execution"
  echo ""
  if [ "$required_execution_json" = "null" ]; then
    echo "- none"
  else
    jq -r '"- owner: \(.owner)\n- action: \(.action)\n- deliverable_path: \(.deliverable_path)\n- verifier: \(.verifier)\n- due: \(.due)\n- success_condition: \(.success_condition)"' <<<"$required_execution_json"
  fi
} > "$meeting_path"

jq \
  --arg ts "$ts" \
  --arg id "$id" \
  --arg rel "$meeting_rel" \
  --arg verdict "$verdict" \
  --arg type "$meeting_type" \
  --arg strategy_status "$strategy_status" \
  --arg strategy_last_signal "$strategy_last_signal" \
  --arg prev_execution_result "$prev_execution_result" \
  --arg prev_execution_detail "$prev_execution_detail" \
  --argjson strategy_required "$strategy_required" \
  --argjson strategy_target_per_hour "$strategy_target_per_hour" \
  --argjson strategy_target_per_day "$strategy_target_per_day" \
  --argjson strategy_total_signals "$strategy_total_signals" \
  --argjson strategy_previous_signals "$strategy_previous_signals" \
  --argjson strategy_delta "$strategy_delta" \
  --argjson incident_recovery_required "$incident_recovery_required" \
  --argjson decision "$decision_json" '
	  .meetings.last_type = "hourly-review" |
	  .meetings.last_reason = $verdict |
	  .meetings.last_review_at = $ts |
	  .meetings.last_review_path = $rel |
	  .meetings.current_id = $id |
	  .meetings.current_record_path = $rel |
	  .meetings.last_attendees = ["dispatcher","planner","cto","cqo","service-ops","meeting-manager"] |
	  .meetings.decision = $decision |
	  .meetings.previous_required_execution_result = $prev_execution_result |
	  .meetings.previous_required_execution_detail = $prev_execution_detail |
	  .meetings.required_execution = $decision.required_execution |
	  .goals.strategy_cadence = {
	    "required": $strategy_required,
	    "status": $strategy_status,
	    "target_per_hour": $strategy_target_per_hour,
	    "target_per_day": $strategy_target_per_day,
	    "total_signals": $strategy_total_signals,
	    "previous_total_signals": $strategy_previous_signals,
	    "delta_since_last_review": $strategy_delta,
	    "last_signal": $strategy_last_signal,
	    "last_check": $ts
	  } |
	  .service_ops.incident.recovery_required = $incident_recovery_required |
	  if $verdict == "incident" or $verdict == "autonomous_review" or $verdict == "idle" or $verdict == "goal_drift"
	  then .meetings.active = ((.meetings.active // []) + ["meeting-manager","dispatcher","planner","cto","cqo","service-ops"] | unique) |
	       .meetings.requested_type = (.meetings.requested_type // $type) |
	       .meetings.requested_reason = (.meetings.requested_reason // $verdict)
	  else . end |
	  .service_ops.monitor.last_hourly_review = $ts
	' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

echo "$ts | meeting-manager | hourly-review | $verdict | $id | $meeting_rel" >> "$log_path"
echo "$meeting_rel"
