#!/bin/bash
# harness-session-start.sh — SessionStart 훅
# 새 세션 시작 시 자동으로:
#   1) 이전 에이전트가 completed이면 harness-next.sh를 실행하여 게이트 체크 + handoff 생성
#   2) handoff.json이 있으면 다음 에이전트 안내
#   3) statusline이 상시 상태를 표시하므로 여기서는 핵심 안내만 출력
#
# 사용자가 수동으로 harness-next.sh를 실행할 필요가 없도록 자동화.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/harness-render-progress.sh"

if [ ! -f "$LIB" ]; then exit 0; fi
source "$LIB"
command -v jq &>/dev/null || exit 0

PROJECT_ROOT="$(resolve_harness_root "." 2>/dev/null)" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"
[ -f "$PROGRESS" ] || exit 0

sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null)
current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)

# ─────────────────────────────────────────
# init 상태: 첫 안내
# ─────────────────────────────────────────
if [ "$sprint_status" = "init" ]; then
  echo "# Harness ready — say \"하네스 엔지니어링 시작\" or /harness-dispatcher"
  exit 0
fi

# ─────────────────────────────────────────
# 이전 에이전트가 completed → 자동으로 harness-next 실행
# (게이트 체크, 아티팩트 검증, handoff.json 생성)
# ─────────────────────────────────────────
if [ "$agent_status" = "completed" ] || [ "$agent_status" = "failed" ]; then
  # harness-next.sh를 백그라운드로 실행하면 안 됨 — 결과가 필요
  bash "$SCRIPT_DIR/harness-next.sh" "$PROJECT_ROOT" 2>/dev/null

  # harness-next.sh가 progress.json과 handoff.json을 업데이트했으므로 다시 읽기
  next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
  agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
fi

# ─────────────────────────────────────────
# 상태별 안내 출력
# ─────────────────────────────────────────
if [ "$agent_status" = "blocked" ]; then
  echo "# Harness BLOCKED — retry limit reached, user intervention required"

elif [ -f "$HANDOFF" ] && [ "$next_agent" != "none" ] && [ "$next_agent" != "null" ]; then
  # handoff.json에서 모델/모드 정보 읽기
  handoff_model=$(jq -r '.model // "opus"' "$HANDOFF" 2>/dev/null)
  handoff_thinking=$(jq -r '.thinking_mode // empty' "$HANDOFF" 2>/dev/null)

  mode_str=""
  if [ -n "$handoff_thinking" ] && [ "$handoff_thinking" != "null" ]; then
    mode_str=" /${handoff_thinking}"
  fi

  echo "# Harness: next → /harness-${next_agent}  (${handoff_model}${mode_str})"

elif [ "$current_agent" != "none" ] && [ "$current_agent" != "null" ]; then
  echo "# Harness: ${current_agent} [${agent_status}]"
fi
