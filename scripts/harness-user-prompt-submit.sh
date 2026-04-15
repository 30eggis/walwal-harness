#!/bin/bash
# harness-user-prompt-submit.sh — UserPromptSubmit hook (v5 unified)
# 핵심 상태 + 라우팅 지시만 주입. Solo/Team 통합.
set -e

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then CWD="$PWD"; fi

# 조건 1: 하네스 초기화 확인
if [ ! -f "$CWD/.harness/config.json" ]; then exit 0; fi

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
  PIPELINE=$(jq -r '.pipeline // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  CURRENT_AGENT=$(jq -r '.current_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  NEXT_AGENT=$(jq -r '.next_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  SPRINT_NUM=$(jq -r '.sprint.number // 0' "$CWD/.harness/progress.json" 2>/dev/null || echo "0")
  SPRINT_STATUS=$(jq -r '.sprint.status // "init"' "$CWD/.harness/progress.json" 2>/dev/null || echo "init")
  AGENT_STATUS=$(jq -r '.agent_status // "pending"' "$CWD/.harness/progress.json" 2>/dev/null || echo "pending")
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
if [ "$CURRENT_AGENT" != "none" ] && [ "$CURRENT_AGENT" != "null" ] && [ "$AGENT_STATUS" = "running" ]; then
  # 프롬프트에서 /harness-* 패턴 추출
  REQUESTED_SKILL=$(echo "$PROMPT" | grep -oE '/harness-[a-z-]+' | head -1 | sed 's|/harness-||')
  if [ -n "$REQUESTED_SKILL" ] && [ "$REQUESTED_SKILL" != "$CURRENT_AGENT" ]; then
    CONTEXT_WARNING="
## !! Context Isolation Warning !!
current_agent=${CURRENT_AGENT} (running) 인데 /harness-${REQUESTED_SKILL} 호출 감지.
한 세션에서 다른 에이전트를 실행하면 컨텍스트가 오염됩니다.
현재 에이전트를 먼저 완료(completed)하거나, 새 세션을 시작하세요."
  fi
fi

# ── Mode 기반 분기 ──
MODE="solo"
if [ -f "$CWD/.harness/progress.json" ] && command -v jq >/dev/null 2>&1; then
  MODE=$(jq -r '.mode // "solo"' "$CWD/.harness/progress.json" 2>/dev/null || echo "solo")
fi

if [ "$MODE" = "team" ]; then
  FEATURE_QUEUE="$CWD/.harness/actions/feature-queue.json"
  T_PASSED=0; T_TOTAL=0; T_FAILED=0
  if [ -f "$FEATURE_QUEUE" ]; then
    T_PASSED=$(jq '.queue.passed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    T_TOTAL=$(jq '[.queue.ready, (.queue.blocked | keys), (.queue.in_progress | keys), .queue.passed, .queue.failed] | flatten | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    T_FAILED=$(jq '.queue.failed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
  fi

  cat <<EOF
[harness] team | ${T_PASSED}/${T_TOTAL} passed | ${T_FAILED} failed

## Team Mode Active
- 3 Agent Teams이 자율적으로 Gen→Eval 루프 실행 중 (max 5 retries)
- 역할: 모니터링, 실패 대응, 수동 개입
- /harness-stop → 중단 | /harness-solo → Solo 전환
- skip: "harness skip" 시 일반 대화
EOF
  exit 0
fi

# ── Compact context 주입 (solo/paused mode) ──
cat <<EOF
[harness] S${SPRINT_NUM} | ${PIPELINE} | agent=${CURRENT_AGENT} (${AGENT_STATUS}) | next=${NEXT_AGENT}
${CONTEXT_WARNING}
## Route
- pipeline=none/dispatcher 미실행 → harness-dispatcher 스킬 호출
- 기능 요청 → pipeline flow | 실수 지적 → gotcha flow | 메타 질문 → 짧게 응답 (skip)
- 활성 pipeline → next_agent/current_agent 컨텍스트로 계속
- skip: "harness skip", "just answer" 등 명시 시 단일 메시지 건너뜀
EOF

exit 0
