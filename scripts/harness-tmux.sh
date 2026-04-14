#!/bin/bash
# harness-tmux.sh — Harness Studio tmux 5-pane 레이아웃
#
# ┌─────────────────────────┬────────────────────────┐
# │  Dashboard (auto-refresh)│ Monitor (compact)      │
# │                          ├────────────────────────┤
# │                          │ Agent Session (claude)  │
# ├─────────────────────────┤                         │
# │  Control (harness> _)    ├────────────────────────┤
# │                          │ Eval Review             │
# └─────────────────────────┴────────────────────────┘
#
# Usage:
#   bash scripts/harness-tmux.sh [project-root]
#   bash scripts/harness-tmux.sh /path/to/project --ai
#
# Options:
#   --ai        Eval Review에서 claude -p AI 요약
#   --detach    세션 생성 후 attach 하지 않음
#   --kill      기존 harness-studio 세션 종료

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-studio"

PROJECT_ROOT=""
USE_AI=""
DETACH=false

for arg in "$@"; do
  case "$arg" in
    --ai)     USE_AI="--ai" ;;
    --detach) DETACH=true ;;
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
# Build layout using explicit pane IDs
# ══════════════════════════════════════════

# 1. Create session → capture Dashboard pane ID
PANE_DASHBOARD=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 200 -y 50 \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard.sh\" \"${PROJECT_ROOT}\"'")

# 2. Split Dashboard horizontally (55% left / 45% right) → Monitor pane
PANE_MONITOR=$(tmux split-window -h -p 45 -t "$PANE_DASHBOARD" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\"'")

# 3. Split Dashboard vertically (75% top / 25% bottom) → Control pane
PANE_CONTROL=$(tmux split-window -v -p 25 -t "$PANE_DASHBOARD" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-control.sh\" \"${PROJECT_ROOT}\"'")

# 4. Split Monitor vertically (15% top / 85% bottom) → Agent Session pane
PANE_AGENT=$(tmux split-window -v -p 85 -t "$PANE_MONITOR" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')

# 5. Split Agent Session vertically (55% top / 45% bottom) → Eval Review pane
PANE_EVAL=$(tmux split-window -v -p 45 -t "$PANE_AGENT" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-eval-watcher.sh\" \"${PROJECT_ROOT}\" ${USE_AI}'")

# 6. Agent Session — leave as empty shell, ready for Control to launch claude
#    Pre-unset nvm conflict variable
tmux send-keys -t "$PANE_AGENT" "unset npm_config_prefix 2>/dev/null" Enter
tmux send-keys -t "$PANE_AGENT" "clear" Enter

# ── Pane titles ──
tmux select-pane -t "$PANE_DASHBOARD" -T "Dashboard"
tmux select-pane -t "$PANE_MONITOR"   -T "Monitor"
tmux select-pane -t "$PANE_CONTROL"   -T "Control"
tmux select-pane -t "$PANE_AGENT"     -T "Agent Session"
tmux select-pane -t "$PANE_EVAL"      -T "Eval Review"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# ── Focus on Control pane (where user types) ──
tmux select-pane -t "$PANE_CONTROL"

# ── Attach ──
if [ "$DETACH" = true ]; then
  echo ""
  echo "Session created. Attach: tmux attach -t $SESSION_NAME"
else
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION_NAME"
  else
    echo ""
    echo "Launching harness-studio..."
    echo "  Dashboard (left↑)   : Auto-refresh progress"
    echo "  Control (left↓)     : Manual commands (next/retry/stop/log)"
    echo "  Monitor (right↑)    : Agent lifecycle (compact)"
    echo "  Agent Session (right↔): claude --dangerously-skip-permissions"
    echo "  Eval Review (right↓): Evaluation summaries"
    echo ""
    tmux attach -t "$SESSION_NAME"
  fi
fi
