#!/bin/bash
# harness-user-prompt-submit.sh — UserPromptSubmit hook (v5 unified)
# 핵심 상태 + 라우팅 지시만 주입. 회사 루프는 항상 병렬/자율 진행.
set -e

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then CWD="$PWD"; fi

# 조건 1: 하네스 초기화 확인
if [ ! -f "$CWD/.harness/config.json" ]; then exit 0; fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 조건 2: opt-out 플래그 확인
AUTO_ROUTE="true"
if command -v jq >/dev/null 2>&1; then
  AUTO_ROUTE=$(jq -r '.behavior.auto_route_dispatcher // true' "$CWD/.harness/config.json" 2>/dev/null || echo "true")
fi
if [ "$AUTO_ROUTE" != "true" ]; then exit 0; fi

# 사용자 skip 감지
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
if echo "$PROMPT" | grep -qiE "harness\s*(skip|off|bypass|없이)|without\s*harness|just\s*(answer|chat|reply)"; then
  exit 0
fi

# 현재 세션 상태 읽기
PIPELINE="none"; CURRENT_AGENT="none"; NEXT_AGENT="none"
SPRINT_NUM="0"; SPRINT_STATUS="init"; AGENT_STATUS="pending"

if [ -f "$CWD/.harness/progress.json" ] && command -v jq >/dev/null 2>&1; then
  conductor_state=$(jq -r '.conductor.state // "idle"' "$CWD/.harness/progress.json" 2>/dev/null || echo "idle")
  pending_next=$(jq -r '.next_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  if [ -x "$SCRIPT_DIR/conductor-tick.sh" ] && { [ "$conductor_state" = "running" ] || [ "$pending_next" = "conductor" ]; }; then
    bash "$SCRIPT_DIR/conductor-tick.sh" "$CWD" >/dev/null 2>&1 || true
  fi
  PIPELINE=$(jq -r '.pipeline // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  CURRENT_AGENT=$(jq -r '.current_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  NEXT_AGENT=$(jq -r '.next_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  SPRINT_NUM=$(jq -r '.sprint.number // 0' "$CWD/.harness/progress.json" 2>/dev/null || echo "0")
  SPRINT_STATUS=$(jq -r '.sprint.status // "init"' "$CWD/.harness/progress.json" 2>/dev/null || echo "init")
  AGENT_STATUS=$(jq -r '.agent_status // "pending"' "$CWD/.harness/progress.json" 2>/dev/null || echo "pending")
fi

TASK_STOP_ACTIVE="false"
TASK_STOP_REASON="null"
TASK_STOP_RESUME_AFTER="null"
TASK_STOP_WAKE_TARGET="none"
if [ -f "$CWD/.harness/progress.json" ] && command -v jq >/dev/null 2>&1; then
  TASK_STOP_ACTIVE=$(jq -r '.task_stop.active // false' "$CWD/.harness/progress.json" 2>/dev/null || echo "false")
  TASK_STOP_REASON=$(jq -r '.task_stop.reason // "null"' "$CWD/.harness/progress.json" 2>/dev/null || echo "null")
  TASK_STOP_RESUME_AFTER=$(jq -r '.task_stop.resume_after // "null"' "$CWD/.harness/progress.json" 2>/dev/null || echo "null")
  TASK_STOP_WAKE_TARGET=$(jq -r '.task_stop.wake_target // .next_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
fi

# ── 명령 히스토리 기록 (모든 모드 공통) ──
PROGRESS_LOG="$CWD/.harness/progress.log"
if [ -n "$PROMPT" ] && [ -d "$CWD/.harness" ]; then
  # progress.log가 없으면 생성
  if [ ! -f "$PROGRESS_LOG" ]; then
    echo "# Harness Command History — $(date +%Y-%m-%d)" > "$PROGRESS_LOG"
  fi
  PROMPT_SHORT=$(echo "$PROMPT" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-80)
  if [ ${#PROMPT_SHORT} -gt 2 ]; then
    echo "$(date +"%Y-%m-%d %H:%M") | user-prompt | input | ${PROMPT_SHORT}" >> "$PROGRESS_LOG"
  fi
fi

# ── 컨텍스트 분리 가드레일 ──
# 현재 에이전트가 활성인데 다른 에이전트 스킬을 호출하려는 경우 경고
CONTEXT_WARNING=""
CONTEXT_BLOCK=""
if [ "$CURRENT_AGENT" != "none" ] && [ "$CURRENT_AGENT" != "null" ] && [ "$AGENT_STATUS" = "running" ]; then
  # 프롬프트에서 /harness-* 패턴 추출
  REQUESTED_SKILL=$(echo "$PROMPT" | grep -oE '/harness-[a-z-]+' | head -1 | sed 's|/harness-||')
  if [ -n "$REQUESTED_SKILL" ] && [ "$REQUESTED_SKILL" != "$CURRENT_AGENT" ]; then
    CONTEXT_BLOCK="
## Context Isolation Block
current_agent=${CURRENT_AGENT} (running) 인데 /harness-${REQUESTED_SKILL} 호출 감지.
문서 기반 task session 분리를 강제하기 위해 이 호출은 차단됩니다.
현재 에이전트를 먼저 완료(completed)하거나, 새 세션을 시작하세요."
  fi
fi

if [ -n "$CONTEXT_BLOCK" ]; then
  cat <<EOF
[harness] blocked | current=${CURRENT_AGENT} | requested=${REQUESTED_SKILL}
${CONTEXT_BLOCK}
EOF
  exit 0
fi

if [ "$TASK_STOP_ACTIVE" = "true" ] && [ "$TASK_STOP_REASON" = "TokenLimit" ]; then
  cat <<EOF
[harness] token-limit hold | wake_target=${TASK_STOP_WAKE_TARGET}
## TokenLimit Hold
- 모든 작업은 일시중지 상태입니다.
- 재개 대상: /harness-${TASK_STOP_WAKE_TARGET}
- retry_after: ${TASK_STOP_RESUME_AFTER}
- 이 상태는 문서 기반으로만 복구되며, 별도 모델 probe는 수행하지 않습니다.
EOF
  exit 0
fi

FEATURE_QUEUE="$CWD/.harness/actions/feature-queue.json"
T_PASSED=0; T_TOTAL=0; T_FAILED=0
if [ -f "$FEATURE_QUEUE" ]; then
  T_PASSED=$(jq '.queue.passed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
  T_TOTAL=$(jq '[.queue.ready, (.queue.blocked | keys), (.queue.in_progress | keys), .queue.passed, .queue.failed] | flatten | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
  T_FAILED=$(jq '.queue.failed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
fi

cat <<EOF
[harness] company | S${SPRINT_NUM} | ${PIPELINE} | agent=${CURRENT_AGENT} (${AGENT_STATUS}) | next=${NEXT_AGENT} | queue=${T_PASSED}/${T_TOTAL} passed | failed=${T_FAILED}
${CONTEXT_WARNING}
## Route
- pipeline=none/dispatcher 미실행 → harness-dispatcher 스킬 호출
- 기본 경로는 conductor 중심 회사 루프다: dispatch -> CEO meeting -> planner(COO) -> cto -> gen/eval -> cqo -> service-ops -> batch meeting
- worker pool(기본 3)이 자율적으로 Gen→Eval 루프 실행 중이며 control-plane은 이 상한에 포함되지 않는다
- Owner에게 "계속 진행", "진행할까요?", "다음 명령을 입력하세요"를 요구하지 않는다. GOAL이 있고 escalation이 아니면 즉시 next_agent/current_agent 업무를 수행한다
- Owner 입력은 목표 변경·사고·결과 확인용이지 회사 진행을 펌프하는 신호가 아니다
- conductor 는 Planner 직행 대신 meeting-manager / cto / cqo / service-ops 로 next_agent를 재작성할 수 있다
- 기능 요청 → pipeline flow | 실수 지적 → gotcha flow | 메타 질문 → 짧게 응답 (skip)
- 활성 pipeline → next_agent/current_agent 컨텍스트로 계속
- skip: "harness skip", "just answer" 등 명시 시 단일 메시지 건너뜀
EOF

exit 0
