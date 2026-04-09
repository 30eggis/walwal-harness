#!/bin/bash
# harness-user-prompt-submit.sh
# ─────────────────────────────────────────
# Claude Code UserPromptSubmit hook
# 모든 사용자 프롬프트를 harness-dispatcher 로 라우팅하도록 Claude 에게
# 지시하는 컨텍스트를 stdout 에 주입한다.
#
# 활성 조건:
#   1) 현재 cwd 에 .harness/config.json 존재
#   2) .harness/config.json 의 behavior.auto_route_dispatcher != false
#
# 비활성 상황에서는 아무것도 출력하지 않고 exit 0 (pass-through).
# ─────────────────────────────────────────
set -e

# stdin 의 JSON payload 읽기 (Claude Code 가 {prompt, cwd, session_id, ...} 전달)
INPUT=$(cat)

# cwd 추출 (payload 에 없으면 PWD fallback)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then
  CWD="$PWD"
fi

# 조건 1: 하네스 초기화 확인
if [ ! -f "$CWD/.harness/config.json" ]; then
  exit 0
fi

# 조건 2: opt-out 플래그 확인 (기본값 true)
AUTO_ROUTE="true"
if command -v jq >/dev/null 2>&1; then
  AUTO_ROUTE=$(jq -r '.behavior.auto_route_dispatcher // true' "$CWD/.harness/config.json" 2>/dev/null || echo "true")
fi
if [ "$AUTO_ROUTE" != "true" ]; then
  exit 0
fi

# 프롬프트 내용 추출 (opt-out 문구 감지용)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
# 사용자가 명시적으로 건너뛰기 요청하면 pass-through
if echo "$PROMPT" | grep -qiE "harness\s*(skip|off|bypass|없이)|without\s*harness|just\s*(answer|chat|reply)"; then
  exit 0
fi

# 현재 세션 상태 읽기
PIPELINE="none"
CURRENT_AGENT="none"
NEXT_AGENT="none"
SPRINT_NUM="0"
SPRINT_STATUS="init"
FE_STACK="react"

if [ -f "$CWD/.harness/progress.json" ] && command -v jq >/dev/null 2>&1; then
  PIPELINE=$(jq -r '.pipeline // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  CURRENT_AGENT=$(jq -r '.current_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  NEXT_AGENT=$(jq -r '.next_agent // "none"' "$CWD/.harness/progress.json" 2>/dev/null || echo "none")
  SPRINT_NUM=$(jq -r '.sprint.number // 0' "$CWD/.harness/progress.json" 2>/dev/null || echo "0")
  SPRINT_STATUS=$(jq -r '.sprint.status // "init"' "$CWD/.harness/progress.json" 2>/dev/null || echo "init")
fi

if [ -f "$CWD/.harness/actions/pipeline.json" ] && command -v jq >/dev/null 2>&1; then
  FE_STACK=$(jq -r '.fe_stack // "react"' "$CWD/.harness/actions/pipeline.json" 2>/dev/null || echo "react")
fi

# ─────────────────────────────────────────
# Context 주입 (stdout → Claude 컨텍스트)
# ─────────────────────────────────────────
cat <<EOF
[walwal-harness] Auto-routing is ACTIVE for this project.

이 프로젝트는 walwal-harness 가 초기화되어 있으며, auto_route_dispatcher 플래그가
켜져 있습니다. 사용자의 모든 프롬프트는 **harness-dispatcher** 스킬을 통해
분류/라우팅된 뒤 처리되어야 합니다.

## 분류 규칙 (Dispatcher Request Classification)
- **기능 요청** (만들어줘, 추가, 고쳐줘, PRD, OpenAPI) → Pipeline Flow
- **실수 지적** (아니, 잘못됐어, 그렇게 하면 안 돼, X로 해야지) → Gotcha Flow
- **혼합** → Gotcha 먼저 기록 → Pipeline 이어서
- **메타/인사/Claude 자체 질문** → 짧게 일반 응답 (dispatcher skip 허용)

## 현재 harness 세션 상태
- pipeline: $PIPELINE
- current_agent: $CURRENT_AGENT
- next_agent: $NEXT_AGENT
- sprint: $SPRINT_NUM ($SPRINT_STATUS)
- fe_stack: $FE_STACK

## 지시
1. 먼저 위 상태를 읽고, 사용자 메시지가 어떤 분류에 해당하는지 판단
2. **pipeline 이 'none' 또는 dispatcher 미실행 상태**면 harness-dispatcher 스킬 호출
3. **pipeline 이 이미 활성**이면:
   - 실수 지적이면 → dispatcher 로 gotcha 기록
   - 기능 연속 작업이면 → next_agent 또는 current_agent 의 컨텍스트로 계속
4. 응답 전 반드시 \`.harness/progress.json\` 을 읽고 세션 경계 프로토콜 준수

## 이 라우팅을 건너뛰려면
- **단일 메시지**: 사용자가 "harness skip", "without harness", "harness 없이", "just answer" 등을 명시
- **전역 비활성**: \`.harness/config.json\` 에서 \`behavior.auto_route_dispatcher = false\` 설정

## 참고
이 안내는 \`scripts/harness-user-prompt-submit.sh\` UserPromptSubmit 훅에 의해
매 프롬프트마다 자동 주입됩니다. 중복 안내처럼 보여도 무시하지 말고 위 규칙을 따르세요.
EOF

exit 0
