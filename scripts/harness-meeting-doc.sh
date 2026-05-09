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
# v6.2 — parallel tracks hints (set by conductor before convene). length >= 2 = fork.
requested_tracks=$(jq -c '.meetings.requested_tracks // []' "$PROGRESS")
requested_rendezvous=$(jq -c '.meetings.requested_rendezvous // null' "$PROGRESS")
fork_context=$(jq -c '.meetings.fork_context // null' "$PROGRESS")
fallback_fork_meeting_id=$(jq -r '.meetings.fork_meeting_id // .conductor.fork_meeting_id // ""' "$PROGRESS")
fallback_conductor_tracks=$(jq -c '.conductor.tracks // []' "$PROGRESS")
fallback_decision_tracks=$(jq -c '.meetings.decision.tracks // []' "$PROGRESS")

default_decision_json() {
  local owner="planner"
  local action_type="triage"
  case "$1" in
    implementation_drift) owner="cto"; action_type="implement" ;;
    planning_drift) owner="planner"; action_type="replan" ;;
    ops_drift) owner="service-ops"; action_type="monitor" ;;
    goal_drift) owner="planner"; action_type="goal-realignment" ;;
  esac
  if [ "$requested_reason" = "goal-intake" ]; then
    owner="planner"
    action_type="goal-alignment"
  fi

  # v6.2 — Tracks 가 단일 진실: length >= 2 → fork-join, length == 1 → single.
  # legacy {owner, action_type} 만 들어와도 1-element tracks[] 로 합성.
  local tracks_json="[]"
  local rendezvous_json="null"
  if [ "$(jq 'length' <<<"$requested_tracks")" -gt 1 ]; then
    tracks_json=$(jq -c '
      [ to_entries[] | (.value + {
          id: ((.value.id // null) // ("track-" + ((.key + 1) | tostring))),
          deliverable: (.value.deliverable // "report"),
          deliverable_path: (.value.deliverable_path // null),
          status: (.value.status // "pending")
        })
      ]
    ' <<<"$requested_tracks")
    rendezvous_json=$(jq -c '. // {type:"followup-review", when:"next_cadence"}' <<<"$requested_rendezvous")
    # primary owner = first track owner (편의 미러)
    owner=$(jq -r '.[0].owner // "planner"' <<<"$tracks_json")
    action_type=$(jq -r '.[0].action_type // "triage"' <<<"$tracks_json")
  else
    # single — derive a 1-element tracks[] (backward compat 도 동시에 처리)
    tracks_json=$(jq -c -n \
      --arg owner "$owner" \
      --arg action_type "$action_type" \
      '[ {id:"track-1", owner:$owner, action_type:$action_type, deliverable:"report", deliverable_path:null, status:"pending"} ]')
  fi

  jq -n \
    --arg owner "$owner" \
    --arg action_type "$action_type" \
    --arg rationale "initial skeleton created by meeting-manager; replace with evidence-backed conclusion" \
    --arg drift_classification "$1" \
    --arg ops_report "$ops_report" \
    --arg cqo_audit "$cqo_audit" \
    --arg cto_review "$cto_review" \
    --argjson tracks "$tracks_json" \
    --argjson rendezvous "$rendezvous_json" '
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
      drift_classification: $drift_classification,
      tracks: $tracks,
      rendezvous: $rendezvous
    }'
}

resolve_followup_fork_context() {
  local resolved="$fork_context"
  if [ "$requested_type" != "followup-review" ]; then
    echo "$resolved"
    return
  fi

  if [ "$resolved" != "null" ] && [ -n "$resolved" ]; then
    echo "$resolved"
    return
  fi

  local fallback_tracks="$fallback_conductor_tracks"
  if [ "$(jq 'length' <<<"$fallback_tracks")" -eq 0 ] && [ "$(jq 'length' <<<"$fallback_decision_tracks")" -gt 0 ]; then
    fallback_tracks="$fallback_decision_tracks"
  fi

  if [ "$(jq 'length' <<<"$fallback_tracks")" -eq 0 ]; then
    echo "null"
    return
  fi

  jq -c -n \
    --arg fork_meeting_id "$fallback_fork_meeting_id" \
    --argjson prior_tracks "$fallback_tracks" \
    '{fork_meeting_id:$fork_meeting_id, prior_tracks:$prior_tracks, sealed_at:(now | todate)}'
}

if [ "$MODE" = "prepare" ]; then
  meeting_id="M-$(date -u +%Y%m%dT%H%M%SZ)"
  meeting_dir="$MEETINGS_ROOT/$meeting_id"
  mkdir -p "$meeting_dir"
  record="$meeting_dir/meeting-$meeting_id.md"

  # v6.2 — Notice surfaces tracks/rendezvous for visibility (length >= 2 = fork)
  tracks_summary="(single owner)"
  rendezvous_summary="-"
  is_fork="false"
  if [ "$(jq 'length' <<<"$requested_tracks")" -gt 1 ]; then
    is_fork="true"
    tracks_summary=$(jq -r '[.[] | "\(.id // "?"):\(.owner)/\(.action_type)→\(.deliverable // "report")"] | join(", ")' <<<"$requested_tracks")
    rendezvous_summary=$(jq -r '"\(.type // "followup-review")@\(.when // "next_cadence")"' <<<"$requested_rendezvous")
  fi
  cat > "$meeting_dir/notice.md" <<EOF
# Notice — $meeting_id

- type: $requested_type
- reason: $requested_reason
- goal_adherence: $goal_adherence
- fork: $is_fork
- tracks: $tracks_summary
- rendezvous: $rendezvous_summary

## Request
"$requested_reason" 요청이 접수되었습니다. 참석자들은 각자의 전문 시각에서 사실·증거를 제출하고,
다음 owner와 action_type을 evidence 중심으로 결정하십시오.

> **Parallel tracks (v6.2)**: \`tracks[]\` 의 길이 ≥ 2 면 fork-join. \`rendezvous\` 시점에 followup-review 로 합쳐집니다. 단일 트랙 회의는 기존과 동일하게 동작합니다.
EOF

  cat > "$meeting_dir/prep-dispatcher.md" <<'EOF'
# Prep — Dispatcher/CEO
- Role: 회사 내부 CEO. Owner와의 유일한 외부 창구이며, Owner 입력은 최초 GOAL 이후 interrupt/additional request로만 취급한다.
- Must answer: Goal 자체가 흔들렸는가, 아니면 내부 실행/품질/운영 문제인가?
- Must decide: Owner escalation 이 정말 필요한가, 아니면 내부 임원진이 처리할 수 있는가?
- Must not: Owner를 기다린다는 결론으로 회의를 끝내지 마라.
- Evidence to cite: active GOAL, KPI, previous decision, escalation trigger.
EOF
  cat > "$meeting_dir/prep-planner.md" <<'EOF'
# Prep — Planner/COO
- Role: COO. GOAL을 실행 가능한 work package, 가설, queue로 바꾸고 조직이 옆길로 새지 않게 한다.
- Must answer: planning_drift 또는 goal_drift 인가, 아니면 구현/품질/운영 문제인가?
- Must decide: 다음 operating cycle에서 어떤 work package를 queue/backlog/track으로 만들 것인가?
- Must not: "다음 sprint에서", "Owner가 정하면" 같은 대기형 결론을 쓰지 마라.
- Evidence to cite: feature-list, sprint-contract, queue, hypothesis/report artifacts.
EOF
  cat > "$meeting_dir/prep-cto.md" <<'EOF'
# Prep — CTO
- Role: CTO. 구현, 아키텍처, 기술선택, runtime recovery의 책임자다.
- Must answer: implementation_drift 인가, 런타임 장애인가, 설계 변경이 필요한가?
- Must decide: 어떤 generator/devops/hotfix worker를 태우고 어떤 deliverable을 요구할 것인가?
- Must not: 운영 장애를 단순 Service-Ops 알림으로만 남기지 마라. 복구 owner를 지정하라.
- Evidence to cite: code path, build/test output, runtime health, cto-review.
EOF
  cat > "$meeting_dir/prep-cqo.md" <<'EOF'
# Prep — CQO
- Role: CQO. 품질, 회귀, 검증 기준의 최종 감시자다.
- Must answer: evidence가 충분한가, PASS/FAIL 판정이 방어 가능한가?
- Must decide: 어떤 evaluator/check가 필요하고, 어떤 주장은 검증 전까지 보류해야 하는가?
- Must not: evidence 없는 낙관론을 회의 결론으로 통과시키지 마라.
- Evidence to cite: evaluator reports, regression results, cqo-audit, reproducible checks.
EOF
  cat > "$meeting_dir/prep-service-ops.md" <<'EOF'
# Prep — Service-Ops
- Role: Service-Ops. 운영 신호, KPI, incident, monitor cadence의 책임자다.
- Must answer: 어떤 KPI/로그/health/incident가 Goal에서 벗어났는가?
- Must decide: ops_drift 인가, incident-war-room 이 필요한가, monitor cadence를 바꿔야 하는가?
- Must not: 서버 down을 혼자 경고만 하고 끝내지 마라. 회의에 올려 CTO/CQO action으로 연결하라.
- Evidence to cite: ops-report path, health table, incident timeline, last_check.
EOF

  decision_json="$(default_decision_json "$drift")"

  # v6.2 — followup-review: surface prior_tracks + fork_meeting_id from fork_context
  resolved_fork_context="$(resolve_followup_fork_context)"

  fork_section=""
  if [ "$requested_type" = "followup-review" ] && [ "$resolved_fork_context" != "null" ] && [ -n "$resolved_fork_context" ]; then
    fork_id=$(jq -r '.fork_meeting_id // ""' <<<"$resolved_fork_context")
    fork_section="

## Fork Context (v6.2)
- fork_meeting_id: $fork_id
- prior_tracks (rendezvous 입력):

\`\`\`json
$(jq '.prior_tracks' <<<"$resolved_fork_context")
\`\`\`

> 결정자(기본 CTO) 는 위 트랙별 deliverable 을 통합 검토 후 \`apply-now / backlog / more-validation\` 중 하나를 선택해 아래 Decision JSON 의 \`tracks\` 를 비우고 \`owner / action_type\` 만 채운다 (followup 에서 또 fork 금지)."
  fi

  cat > "$record" <<EOF
# Meeting Record — $meeting_id

## Context
- type: $requested_type
- reason: $requested_reason
- goal_adherence: $goal_adherence
$fork_section

## Required Role Positions

Meeting-Manager must fill this section before reporting the meeting as complete.

### Dispatcher/CEO
- Position:
- Evidence:
- Escalation needed: yes/no

### Planner/COO
- Position:
- Evidence:
- Proposed work package:

### CTO
- Position:
- Evidence:
- Engineering action:

### CQO
- Position:
- Evidence:
- Quality gate:

### Service-Ops
- Position:
- Evidence:
- Operational action:

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

  if [ "$requested_type" = "followup-review" ] && [ "$resolved_fork_context" != "null" ] && [ -n "$resolved_fork_context" ]; then
    bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" ".meetings.fork_context = $resolved_fork_context" >/dev/null
  fi

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

# v6.2 — read-tracks: emit normalized tracks[] (length>=2 = fork, length==1 = single).
# Legacy decisions without tracks → synthesize 1-element tracks[] from {owner, action_type}.
if [ "$MODE" = "read-tracks" ]; then
  jq -c '
    if ((.meetings.decision.tracks // []) | length) > 0 then
      .meetings.decision.tracks
    elif ((.meetings.fork_context.prior_tracks // []) | length) > 0 then
      .meetings.fork_context.prior_tracks
    elif ((.conductor.tracks // []) | length) > 0 then
      .conductor.tracks
    else
      [ {
          id: "track-1",
          owner: (.meetings.decision.owner // "planner"),
          action_type: (.meetings.decision.action_type // "triage"),
          deliverable: "report",
          deliverable_path: null,
          status: "pending"
        }
      ]
    end
  ' "$PROGRESS"
  exit 0
fi

# v6.2 — read-rendezvous: emit rendezvous{} or null
if [ "$MODE" = "read-rendezvous" ]; then
  jq -c '.meetings.decision.rendezvous // .conductor.rendezvous // null' "$PROGRESS"
  exit 0
fi

# v6.2 — read-fork: "true" if tracks.length >= 2, else "false"
if [ "$MODE" = "read-fork" ]; then
  decision="$(bash "$0" "$PROJECT_ROOT" read-decision 2>/dev/null || true)"
  if [ -z "$decision" ]; then decision='{}'; fi
  jq -r '((.tracks // []) | length) > 1' <<<"$decision"
  exit 0
fi

exit 2
