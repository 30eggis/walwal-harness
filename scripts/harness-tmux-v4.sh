#!/bin/bash
# harness-tmux-v4.sh — v4 Agent Teams: 원커맨드 실행
#
# ┌──────────────┬──────────────┬──────────────┐
# │              │  Dashboard   │   TEAM 1     │
# │  Main Claude │  (v4 queue)  ├──────────────┤
# │  (Lead)      ├──────────────┤   TEAM 2     │
# │              │  Prompt      ├──────────────┤
# │              │  History     │   TEAM 3     │
# └──────────────┴──────────────┴──────────────┘
#
# Usage:
#   bash scripts/harness-tmux-v4.sh              # 레이아웃 + Claude 자동 실행 + team-action 자동 시작
#   bash scripts/harness-tmux-v4.sh --no-auto    # 레이아웃만 (Claude 수동 실행)
#   bash scripts/harness-tmux-v4.sh --kill       # 세션 종료
#
# 이것만 기억하세요:
#   bash scripts/harness-tmux-v4.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-v4"

PROJECT_ROOT=""
DETACH=false
AUTO_START=true

for arg in "$@"; do
  case "$arg" in
    --detach)   DETACH=true ;;
    --no-auto)  AUTO_START=false ;;
    --kill)
      tmux kill-session -t "$SESSION_NAME" 2>/dev/null && echo "Killed." || echo "No session."
      exit 0
      ;;
    *)
      if [ -d "$arg" ]; then PROJECT_ROOT="$arg"; fi
      ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then PROJECT_ROOT="$dir"; break; fi
    dir="$(dirname "$dir")"
  done
fi

if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT/.harness" ]; then
  echo "Error: .harness/ not found."
  exit 1
fi

echo "Project: $PROJECT_ROOT"
echo "Session: $SESSION_NAME"

tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# ── Resolve Claude command ──
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"
CLAUDE_CMD="claude --dangerously-skip-permissions"
if [ -f "$HANDOFF" ]; then
  _model=$(jq -r '.model // empty' "$HANDOFF" 2>/dev/null)
  if [ -n "$_model" ] && [ "$_model" != "null" ]; then
    CLAUDE_CMD="$CLAUDE_CMD --model $_model"
  fi
fi

# ══════════════════════════════════════════
# Build 3-column layout
# ══════════════════════════════════════════

# 1. Create session → Left pane (Main Claude Lead)
PANE_MAIN=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 \
  -P -F '#{pane_id}')

# 2. Split horizontally: Left 35% | Right 65%
PANE_MID=$(tmux split-window -h -p 65 -t "$PANE_MAIN" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')

# 3. Split right section: Middle 45% | Right 55% — Right는 TEAM 1 으로 시작
PANE_T1=$(tmux split-window -h -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 1'")

# 3b. Split TEAM 1 세로로 → TEAM 2 (하단 66%)
PANE_T2=$(tmux split-window -v -p 66 -t "$PANE_T1" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 2'")

# 3c. Split TEAM 2 세로로 → TEAM 3 (하단 50%)
PANE_T3=$(tmux split-window -v -p 50 -t "$PANE_T2" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 3'")

# 4. Split middle pane vertically: Dashboard (top 45%) | Prompt History (bottom 55%)
PANE_HISTORY=$(tmux split-window -v -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"'")

# 5. Start dashboard in the middle-top pane
tmux send-keys -t "$PANE_MID" "bash \"${SCRIPT_DIR}/harness-dashboard-v4.sh\" \"${PROJECT_ROOT}\"" Enter

# 6. Main pane — Claude 자동 실행
tmux send-keys -t "$PANE_MAIN" "unset npm_config_prefix 2>/dev/null" Enter
tmux send-keys -t "$PANE_MAIN" "clear" Enter

if [ "$AUTO_START" = true ]; then
  # Claude 실행 → 시작 후 자동으로 /harness-team-action 전송
  tmux send-keys -t "$PANE_MAIN" "$CLAUDE_CMD" Enter
  # Claude가 초기화될 시간을 준 뒤 team-action 명령 전송
  sleep 3
  tmux send-keys -t "$PANE_MAIN" "/harness-team-action" Enter
fi

# ── Pane titles ──
tmux select-pane -t "$PANE_MAIN"    -T "Lead (Main Claude)"
tmux select-pane -t "$PANE_MID"     -T "Dashboard"
tmux select-pane -t "$PANE_HISTORY" -T "Prompt History"
tmux select-pane -t "$PANE_T1"      -T "TEAM 1"
tmux select-pane -t "$PANE_T2"      -T "TEAM 2"
tmux select-pane -t "$PANE_T3"      -T "TEAM 3"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# ── Focus on Main pane ──
tmux select-pane -t "$PANE_MAIN"

# ── Attach ──
if [ "$DETACH" = true ]; then
  echo ""
  echo "Session created. Attach: tmux attach -t $SESSION_NAME"
else
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION_NAME"
  else
    echo ""
    echo "harness-v4 starting..."
    echo ""
    echo "  All automatic. Just watch."
    echo "  Stop: bash scripts/harness-tmux-v4.sh --kill"
    echo ""
    tmux attach -t "$SESSION_NAME"
  fi
fi
