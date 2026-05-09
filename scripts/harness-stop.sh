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

# Opt-out
AUTO_CHAIN=$(jq -r '.behavior.auto_chain_on_stop // true' "$CONFIG" 2>/dev/null || echo "true")
if [ "$AUTO_CHAIN" != "true" ]; then exit 0; fi

# 무한루프 방지: 한 sprint 안에서 stop_chain_count 가 상한을 넘으면 중단
STOP_CHAIN_MAX=$(jq -r '.behavior.auto_chain_max_per_sprint // 200' "$CONFIG" 2>/dev/null || echo 200)
STOP_CHAIN_COUNT=$(jq -r '.conductor.stop_chain_count // 0' "$PROGRESS" 2>/dev/null || echo 0)
if [ "${STOP_CHAIN_COUNT:-0}" -ge "${STOP_CHAIN_MAX:-200}" ]; then exit 0; fi

# 회사 루프 상태 확인
CONDUCTOR_STATE=$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null || echo "idle")
NEXT_AGENT=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null || echo "none")
AGENT_STATUS=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null || echo "pending")
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
#   conductor 가 running
#   AND task_stop 비활성
#   AND task_stop 비활성
#   AND (next_agent 가 명시되어 있거나, agent_status=completed 라서 다음 tick 결정 필요)
should_chain="false"
if [ "$CONDUCTOR_STATE" = "running" ] \
  && [ "$TASK_STOP_ACTIVE" != "true" ]; then
  if [ "$NEXT_AGENT" != "none" ] && [ "$NEXT_AGENT" != "null" ]; then
    should_chain="true"
  elif [ "$AGENT_STATUS" = "completed" ]; then
    should_chain="true"
  fi
fi

if [ "$should_chain" != "true" ]; then exit 0; fi

# stop_chain_count 증가 (느슨한 카운터 — race 허용)
NEW_COUNT=$((STOP_CHAIN_COUNT + 1))
TMP=$(mktemp)
jq --argjson n "$NEW_COUNT" '.conductor.stop_chain_count = $n |
  .conductor.last_stop_chain_at = (now | todate)' "$PROGRESS" > "$TMP" 2>/dev/null \
  && mv "$TMP" "$PROGRESS" || rm -f "$TMP"

# Claude 에게 다음 행동 지시
if [ "$ESCALATION" != "null" ]; then
  REASON="자율 회사 루프 진행 중. escalation=${ESCALATION} 는 정지 사유가 아니라 meeting-manager/service-ops 공유 대상이다. next_agent=${NEXT_AGENT}, agent_status=${AGENT_STATUS}, conductor=${CONDUCTOR_STATE}. SKILL 에 따라 conductor-tick 을 굴려 meeting-manager 회의로 라우팅하거나 다음 부서를 spawn 하라. progress.log 에는 절대 미래 시각을 쓰지 말 것. 진짜로 끝났을 때만 turn 을 종료하라."
else
  REASON="자율 회사 루프 진행 중. next_agent=${NEXT_AGENT}, agent_status=${AGENT_STATUS}, conductor=${CONDUCTOR_STATE}. SKILL 에 따라 다음 부서를 spawn 하거나 conductor-tick 을 한 번 더 굴려라. progress.log 에는 절대 미래 시각을 쓰지 말 것. 진짜로 끝났을 때만 turn 을 종료하라."
fi

jq -nc \
  --arg reason "$REASON" \
  '{decision: "block", reason: $reason}'

exit 0
