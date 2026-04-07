#!/bin/bash
# harness-session-start.sh — SessionStart 훅
# Claude Code 세션 시작 시 자동 실행되어 현재 하네스 상태를 출력한다.
# .claude/settings.json의 SessionStart 훅으로 등록된다.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/harness-render-progress.sh"

# lib이 없으면 silent exit (훅이므로 에러 출력하지 않음)
if [ ! -f "$LIB" ]; then exit 0; fi
source "$LIB"

# jq 없으면 silent exit
command -v jq &>/dev/null || exit 0

# .harness/ 찾기
PROJECT_ROOT="$(resolve_harness_root "." 2>/dev/null)" || exit 0

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
[ -f "$PROGRESS" ] || exit 0

# init 상태면 간단 안내만
sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null)
if [ "$sprint_status" = "init" ]; then
  echo "# Harness ready — say \"하네스 엔지니어링 시작\" or /harness-dispatcher"
  exit 0
fi

# Feature-level 프로그래스 출력
render_progress "$PROJECT_ROOT"
render_agent_bar "$PROJECT_ROOT"
