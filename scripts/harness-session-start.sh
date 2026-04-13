#!/bin/bash
# harness-session-start.sh — SessionStart 훅 (compact)
# statusline이 상시 상태를 표시하므로, 여기서는 핵심 안내만 출력.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/harness-render-progress.sh"

if [ ! -f "$LIB" ]; then exit 0; fi
source "$LIB"
command -v jq &>/dev/null || exit 0

PROJECT_ROOT="$(resolve_harness_root "." 2>/dev/null)" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
[ -f "$PROGRESS" ] || exit 0

sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null)
current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)

# init 상태: 간단 안내
if [ "$sprint_status" = "init" ]; then
  echo "# Harness ready — say \"하네스 엔지니어링 시작\" or /harness-dispatcher"
  exit 0
fi

# 활성 세션: 다음 액션만 안내 (상세 프로그래스는 statusline에서 상시 표시)
if [ "$agent_status" = "blocked" ]; then
  echo "# Harness BLOCKED — user intervention required. Run: bash scripts/harness-next.sh"
elif [ "$next_agent" != "none" ] && [ "$next_agent" != "null" ]; then
  echo "# Harness: next → /harness-${next_agent}"
elif [ "$current_agent" != "none" ] && [ "$current_agent" != "null" ]; then
  echo "# Harness: ${current_agent} [${agent_status}]"
fi
