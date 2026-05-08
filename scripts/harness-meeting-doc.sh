#!/bin/bash
# harness-meeting-doc.sh — create/read meeting decision documents
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 1
MODE="${2:-prepare}"
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
MEETINGS_ROOT="$PROJECT_ROOT/.harness/actions/meetings"

command -v jq >/dev/null 2>&1 || exit 1
mkdir -p "$MEETINGS_ROOT"

requested_type=$(jq -r '.meetings.requested_type // "spec-review"' "$PROGRESS")
requested_reason=$(jq -r '.meetings.requested_reason // "unspecified"' "$PROGRESS")
drift=$(jq -r '.service_ops.drift_classification // .meetings.decision.drift_classification // "unknown"' "$PROGRESS")
goal_adherence=$(jq -r '.goals.current_adherence // "unknown"' "$PROGRESS")
ops_report=$(jq -r '.service_ops.auto_retro.last_report // empty' "$PROGRESS")
cqo_audit=$(jq -r '.cqo.audit_path // empty' "$PROGRESS")
cto_review=$(jq -r '.cto.review_path // empty' "$PROGRESS")
current_path=$(jq -r '.meetings.current_record_path // empty' "$PROGRESS")

default_decision_json() {
  local owner="planner"
  local action_type="triage"
  case "$1" in
    implementation_drift) owner="cto"; action_type="implement" ;;
    planning_drift) owner="planner"; action_type="replan" ;;
    ops_drift) owner="service-ops"; action_type="monitor" ;;
    goal_drift) owner="dispatcher"; action_type="escalate-owner" ;;
  esac
  if [ "$requested_reason" = "goal-intake" ]; then
    owner="planner"
    action_type="goal-alignment"
  fi
  jq -n \
    --arg owner "$owner" \
    --arg action_type "$action_type" \
    --arg rationale "initial skeleton created by meeting-manager; replace with evidence-backed conclusion" \
    --arg drift_classification "$1" \
    --arg ops_report "$ops_report" \
    --arg cqo_audit "$cqo_audit" \
    --arg cto_review "$cto_review" '
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
      drift_classification: $drift_classification
    }'
}

if [ "$MODE" = "prepare" ]; then
  meeting_id="M-$(date -u +%Y%m%dT%H%M%SZ)"
  meeting_dir="$MEETINGS_ROOT/$meeting_id"
  mkdir -p "$meeting_dir"
  record="$meeting_dir/meeting-$meeting_id.md"

  cat > "$meeting_dir/notice.md" <<EOF
# Notice — $meeting_id

- type: $requested_type
- reason: $requested_reason
- goal_adherence: $goal_adherence

## Request
"$requested_reason" 요청이 접수되었습니다. 참석자들은 각자의 전문 시각에서 사실·증거를 제출하고,
다음 owner와 action_type을 evidence 중심으로 결정하십시오.
EOF

  cat > "$meeting_dir/prep-dispatcher.md" <<'EOF'
# Prep — Dispatcher/CEO
- Goal 자체가 흔들렸는가?
- Owner escalation 이 필요한가?
- 사업 우선순위 또는 KPI 정의를 바꿔야 하는가?
EOF
  cat > "$meeting_dir/prep-planner.md" <<'EOF'
# Prep — Planner/COO
- 기획/가설/웹리서치/레퍼런스 보강이 필요한가?
- planning_drift 또는 goal_drift 근거는 무엇인가?
- 수정해야 할 plan/feature/api 는 무엇인가?
EOF
  cat > "$meeting_dir/prep-cto.md" <<'EOF'
# Prep — CTO
- 구현/아키텍처/기술선택이 원인인가?
- implementation_drift 근거는 무엇인가?
- 어떤 generator/evaluator를 다시 태워야 하는가?
EOF
  cat > "$meeting_dir/prep-cqo.md" <<'EOF'
# Prep — CQO
- 품질/회귀/검증 부족이 원인인가?
- 어떤 evidence가 이 결론을 지지하는가?
- evidence 없는 추정은 금지한다.
EOF
  cat > "$meeting_dir/prep-service-ops.md" <<'EOF'
# Prep — Service-Ops
- 어떤 KPI/로그/incident가 Goal에서 벗어났는가?
- ops_drift 여부를 먼저 판단하라.
- 운영 측 evidence를 문서 경로와 함께 적어라.
EOF

  decision_json="$(default_decision_json "$drift")"
  cat > "$record" <<EOF
# Meeting Record — $meeting_id

## Context
- type: $requested_type
- reason: $requested_reason
- goal_adherence: $goal_adherence

## Decision JSON
\`\`\`json
$(jq -n \
  --arg meeting_id "$meeting_id" \
  --arg type "$requested_type" \
  --arg reason "$requested_reason" \
  --arg source_path "${record#$PROJECT_ROOT/}" \
  --argjson decision "$decision_json" \
  '{meeting_id:$meeting_id,type:$type,reason:$reason,decision:($decision + {source_path:$source_path})}')
\`\`\`
EOF

  bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
    ".meetings.current_id = \"$meeting_id\" |
     .meetings.current_record_path = \"${record#$PROJECT_ROOT/}\" |
     .meetings.decision = ($(jq -c '.decision' <<<"$(
       jq -n --arg meeting_id "$meeting_id" --arg type "$requested_type" --arg reason "$requested_reason" --arg source_path "${record#$PROJECT_ROOT/}" --argjson decision "$decision_json" '{meeting_id:$meeting_id,type:$type,reason:$reason,decision:($decision + {source_path:$source_path})}'
     )"))" >/dev/null

  echo "${record#$PROJECT_ROOT/}"
  exit 0
fi

if [ "$MODE" = "read-decision" ]; then
  [ -n "$current_path" ] || exit 0
  [ -f "$PROJECT_ROOT/$current_path" ] || exit 0
  awk '
    /```json/ {capture=1; next}
    /```/ && capture {capture=0; exit}
    capture {print}
  ' "$PROJECT_ROOT/$current_path" | jq -c '.decision'
  exit 0
fi

exit 2
