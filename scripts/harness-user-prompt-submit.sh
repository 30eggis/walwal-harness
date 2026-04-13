#!/bin/bash
# harness-user-prompt-submit.sh — UserPromptSubmit hook (compact v3.2)
# 핵심 상태 + 라우팅 지시만 주입. 장황한 설명 제거.
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

# ── Compact context 주입 ──
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
