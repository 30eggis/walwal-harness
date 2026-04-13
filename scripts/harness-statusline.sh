#!/bin/bash
# harness-statusline.sh — Claude Code statusline hook
# 터미널 하단에 항상 고정되는 1줄 compact 상태 표시.
# stdin: Claude Code JSON payload (model, context_window, cost 등)
# stdout: 상태 문자열 (Claude Code가 터미널 하단에 렌더링)

# Read Claude Code session data from stdin
input=$(cat)

# Extract Claude Code built-in data
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)

# Resolve project root (walk up from cwd)
CWD=$(echo "$input" | jq -r '.workspace.current_dir // empty' 2>/dev/null)
if [ -z "$CWD" ]; then CWD="$PWD"; fi

PROJECT_ROOT="$CWD"
while [ "$PROJECT_ROOT" != "/" ]; do
  if [ -d "$PROJECT_ROOT/.harness" ]; then break; fi
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
FEATURE_LIST="$PROJECT_ROOT/.harness/actions/feature-list.json"
PIPELINE_JSON="$PROJECT_ROOT/.harness/actions/pipeline.json"

# No harness → minimal status
if [ ! -f "$PROGRESS" ]; then
  echo "harness: not initialized | ctx ${context_pct}%"
  exit 0
fi

# Read harness state
sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)
sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null)
pipeline=$(jq -r '.pipeline // "?"' "$PROGRESS" 2>/dev/null)
current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
retry_count=$(jq -r '.sprint.retry_count // 0' "$PROGRESS" 2>/dev/null)

# Pipeline short name
case "$pipeline" in
  FULLSTACK) pl="FULL" ;;
  FE-ONLY)   pl="FE" ;;
  BE-ONLY)   pl="BE" ;;
  null|"?")  pl="?" ;;
  *)         pl="$pipeline" ;;
esac

# Agent short name (strip harness prefix)
agent_short="${current_agent#generator-}"
agent_short="${agent_short#evaluator-}"
if [ "$current_agent" = "none" ] || [ "$current_agent" = "null" ]; then
  agent_short="$next_agent"
  if [ "$agent_short" = "none" ] || [ "$agent_short" = "null" ]; then
    agent_short="idle"
  fi
fi

# Feature progress
total_features=0
completed_features=0
if [ -f "$FEATURE_LIST" ]; then
  total_features=$(jq '.features | length' "$FEATURE_LIST" 2>/dev/null || echo 0)
  completed_features=$(jq '[.features[]? | select(
    (.passes // []) | (
      (map(select(. == "evaluator-functional")) | length > 0) and
      (map(select(. == "evaluator-visual")) | length > 0)
    )
  )] | length' "$FEATURE_LIST" 2>/dev/null || echo 0)
fi

# Status indicator
status_icon=""
case "$agent_status" in
  running)   status_icon=">" ;;
  completed) status_icon="v" ;;
  failed)    status_icon="x" ;;
  blocked)   status_icon="!" ;;
  *)         status_icon="-" ;;
esac

# Retry indicator
retry_str=""
if [ "$retry_count" -gt 0 ]; then
  retry_str=" R${retry_count}"
fi

# Build compact status line
# Format: [S1] FULL | >backend | 2/5 feat | R0 | ctx 45% | $1.23
echo "[S${sprint_num}] ${pl} | ${status_icon}${agent_short}${retry_str} | ${completed_features}/${total_features} feat | ctx ${context_pct}% | \$${cost}"
