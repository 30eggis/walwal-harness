#!/bin/bash
# harness-stop.sh — Stop hook (v6.2)
#
# Claude 가 한 turn 을 끝내려 할 때 발화.
# conductor.state == "running" 이고 다음 작업이 남아 있으면
# stdout 으로 {"decision":"block", "reason":"..."} JSON 을 출력해
# Claude 가 멈추지 않고 다음 tick 으로 자동 연쇄하게 한다.
#
# 멈춰야 할 경우 (회사 루프 정지·task_stop 등) 는 그냥 exit 0
# → Claude 가 정상적으로 turn 을 종료.

set -uo pipefail

INPUT=$(cat 2>/dev/null || echo "{}")
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

# 하네스 초기화 안 된 곳: no-op
[ -f "$CWD/.harness/progress.json" ] || exit 0
[ -f "$CWD/.harness/config.json" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PROGRESS="$CWD/.harness/progress.json"
CONFIG="$CWD/.harness/config.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Opt-out
AUTO_CHAIN=$(jq -r '.behavior.auto_chain_on_stop // true' "$CONFIG" 2>/dev/null || echo "true")
if [ "$AUTO_CHAIN" != "true" ]; then exit 0; fi

# 무한루프 방지: 한 sprint 안에서 stop_chain_count 가 상한을 넘으면 중단
STOP_CHAIN_MAX=$(jq -r '.behavior.auto_chain_max_per_sprint // 200' "$CONFIG" 2>/dev/null || echo 200)
STOP_CHAIN_COUNT=$(jq -r '.conductor.stop_chain_count // 0' "$PROGRESS" 2>/dev/null || echo 0)
if [ "${STOP_CHAIN_COUNT:-0}" -ge "${STOP_CHAIN_MAX:-200}" ]; then exit 0; fi

# 회사 루프 상태 확인
CONDUCTOR_STATE=$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null || echo "idle")
COMPANY_STATE=$(jq -r '.company_state.state // "idle"' "$PROGRESS" 2>/dev/null || echo "idle")
CURRENT_AGENT=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null || echo "none")
NEXT_AGENT=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null || echo "none")
AGENT_STATUS=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null || echo "pending")
OWNER_PROMPT_STATUS=$(jq -r '.owner_prompt.status // "none"' "$PROGRESS" 2>/dev/null || echo "none")
TASK_STOP_ACTIVE=$(jq -r '.task_stop.active // false' "$PROGRESS" 2>/dev/null || echo "false")
ESCALATION=$(jq -r '.conductor.escalation // "null"' "$PROGRESS" 2>/dev/null || echo "null")
SPRINT_STATUS=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null || echo "init")

# stop hook 이 자기 자신에 의해 재진입되지 않도록 hook event 필터링
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
if [ "$HOOK_EVENT" = "Stop" ]; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
  if [ "$STOP_HOOK_ACTIVE" = "true" ]; then exit 0; fi
fi

# 자동 연쇄 조건:
#   conductor/company loop 가 running
#   AND task_stop 비활성
#   AND (next_agent 가 명시되어 있거나, agent_status=completed 라서 다음 tick 결정 필요)
# v7 CEO 루프는 conductor-tick 없이 CEO/CXX 상태로 시작될 수 있다.
# current_agent=ceo running + owner_prompt.routing 은 기존 설치본이 conductor/company
# state를 아직 쓰지 않은 stuck 상태에서도 turn 종료 차단 대상으로 본다.
should_chain="false"
if { [ "$CONDUCTOR_STATE" = "running" ] || [ "$COMPANY_STATE" = "running" ]; } \
  && [ "$TASK_STOP_ACTIVE" != "true" ]; then
  if [ "$NEXT_AGENT" != "none" ] && [ "$NEXT_AGENT" != "null" ]; then
    should_chain="true"
  elif [ "$AGENT_STATUS" = "completed" ]; then
    should_chain="true"
  elif [ "$CURRENT_AGENT" = "ceo" ] && [ "$AGENT_STATUS" = "running" ] && [ "$OWNER_PROMPT_STATUS" = "routing" ]; then
    should_chain="true"
  fi
fi
if [ "$should_chain" != "true" ] \
  && [ "$TASK_STOP_ACTIVE" != "true" ] \
  && [ "$CURRENT_AGENT" = "ceo" ] \
  && [ "$AGENT_STATUS" = "running" ] \
  && [ "$OWNER_PROMPT_STATUS" = "routing" ]; then
  should_chain="true"
fi

if [ "$should_chain" != "true" ]; then exit 0; fi

# CXX direct-execution guard:
# Only run this while an active company loop is actually chaining. Scope it to
# the newest active mission so legacy/archive documents cannot keep Stop
# blocked forever.
if [ -x "$SCRIPT_DIR/harness-worker-evidence-validate.sh" ]; then
  WORKER_EVIDENCE_JSON=$("$SCRIPT_DIR/harness-worker-evidence-validate.sh" "$CWD" json latest-active 2>/dev/null || true)
  WORKER_EVIDENCE_OK=$(echo "$WORKER_EVIDENCE_JSON" | jq -r 'if has("ok") then .ok else true end' 2>/dev/null || echo true)
  if [ "$WORKER_EVIDENCE_OK" != "true" ]; then
    REASON=$(echo "$WORKER_EVIDENCE_JSON" | jq -r '
      "CXX 직접 실행 차단: " +
      ([.violations[] | "\(.mission) has CXX docs without worker reports: \(.docs | join(","))"] | join("; ")) +
      ". harness-hiring/resource-manager로 전문 worker를 고용 또는 배정하고 .harness/documents/{goal-or-child-mission}/{owning-cxx}/workers/{worker-name}.md 를 남긴 뒤 계속하라."
    ' 2>/dev/null || echo "CXX 직접 실행 차단: worker report가 없는 active mission이 있습니다. hired worker 보고서를 먼저 생성하세요.")
    jq -nc --arg reason "$REASON" '{decision:"block", reason:$reason}'
    exit 0
  fi
fi

# stop_chain_count 증가 (느슨한 카운터 — race 허용)
NEW_COUNT=$((STOP_CHAIN_COUNT + 1))
TMP=$(mktemp)
jq --argjson n "$NEW_COUNT" '.conductor.stop_chain_count = $n |
  .conductor.last_stop_chain_at = (now | todate)' "$PROGRESS" > "$TMP" 2>/dev/null \
  && mv "$TMP" "$PROGRESS" || rm -f "$TMP"

# Claude 에게 다음 행동 지시
if [ "$ESCALATION" != "null" ]; then
  REASON="자율 회사 루프 진행 중. escalation=${ESCALATION} 는 정지 사유가 아니라 meeting-manager/service-ops 공유 대상이다. current_agent=${CURRENT_AGENT}, next_agent=${NEXT_AGENT}, agent_status=${AGENT_STATUS}, conductor=${CONDUCTOR_STATE}, company=${COMPANY_STATE}. SKILL 에 따라 CEO/CXX/worker 흐름을 계속하거나 conductor-tick 을 굴려 meeting-manager 회의로 라우팅하라. progress.log 에는 절대 미래 시각을 쓰지 말 것. 진짜로 끝났을 때만 turn 을 종료하라."
else
  REASON="자율 회사 루프 진행 중. current_agent=${CURRENT_AGENT}, next_agent=${NEXT_AGENT}, agent_status=${AGENT_STATUS}, conductor=${CONDUCTOR_STATE}, company=${COMPANY_STATE}. SKILL 에 따라 CEO/CXX/worker 흐름을 계속하고, 필요한 CXX/worker fresh session 을 실행하라. progress.log 에는 절대 미래 시각을 쓰지 말 것. 진짜로 끝났을 때만 turn 을 종료하라."
fi

jq -nc \
  --arg reason "$REASON" \
  '{decision: "block", reason: $reason}'

exit 0
