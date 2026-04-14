#!/bin/bash
# harness-tmux.sh — tmux 4-pane 레이아웃 자동 구성
#
# ┌──────────────────────┬──────────────────────┐
# │                      │ Panel 1: Dashboard   │
# │  Main Terminal       ├──────────────────────┤
# │  (claude 대화형)      │ Panel 2: Monitor     │
# │                      ├──────────────────────┤
# │                      │ Panel 3: Eval Review │
# └──────────────────────┴──────────────────────┘
#
# Usage:
#   bash scripts/harness-tmux.sh [project-root]
#   bash scripts/harness-tmux.sh /path/to/project --ai   (AI eval summary 활성화)
#
# Options:
#   --ai        Panel 3에서 claude -p 로 AI 요약 생성 (API 비용 발생)
#   --detach    세션 생성 후 attach 하지 않음
#   --kill      기존 harness-studio 세션 종료

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-studio"

PROJECT_ROOT=""
USE_AI=""
DETACH=false
KILL=false

for arg in "$@"; do
  case "$arg" in
    --ai)     USE_AI="--ai" ;;
    --detach) DETACH=true ;;
    --kill)
      tmux kill-session -t "$SESSION_NAME" 2>/dev/null && echo "Session '$SESSION_NAME' killed." || echo "No session to kill."
      exit 0
      ;;
    *)
      if [ -d "$arg" ]; then PROJECT_ROOT="$arg"; fi
      ;;
  esac
done

# Auto-detect project root
if [ -z "$PROJECT_ROOT" ]; then
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then PROJECT_ROOT="$dir"; break; fi
    dir="$(dirname "$dir")"
  done
fi

if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT/.harness" ]; then
  echo "Error: .harness/ directory not found."
  echo "Usage: bash scripts/harness-tmux.sh [project-root]"
  exit 1
fi

echo "Project: $PROJECT_ROOT"
echo "Session: $SESSION_NAME"

# Kill existing session if any
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# ── Create tmux session ──
# Pane 0 (left, Main): interactive shell at project root
tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 200 -y 50

# Split right column (40% width)
tmux split-window -h -l 80 -t "$SESSION_NAME" -c "$PROJECT_ROOT"

# Pane 1 (top-right): Dashboard
tmux send-keys -t "${SESSION_NAME}.1" "bash ${SCRIPT_DIR}/harness-dashboard.sh '${PROJECT_ROOT}'" Enter

# Split pane 1 vertically for Monitor
tmux split-window -v -t "${SESSION_NAME}.1" -c "$PROJECT_ROOT"

# Pane 2 (mid-right): Monitor
tmux send-keys -t "${SESSION_NAME}.2" "bash ${SCRIPT_DIR}/harness-monitor.sh '${PROJECT_ROOT}'" Enter

# Split pane 2 vertically for Eval
tmux split-window -v -t "${SESSION_NAME}.2" -c "$PROJECT_ROOT"

# Pane 3 (bottom-right): Eval Watcher
tmux send-keys -t "${SESSION_NAME}.3" "bash ${SCRIPT_DIR}/harness-eval-watcher.sh '${PROJECT_ROOT}' ${USE_AI}" Enter

# ── Launch Claude in Main pane ──
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"
CLAUDE_CMD="claude --dangerously-skip-permissions"

# If handoff.json exists, pick up model from it
if [ -f "$HANDOFF" ]; then
  _model=$(jq -r '.model // empty' "$HANDOFF" 2>/dev/null)
  if [ -n "$_model" ] && [ "$_model" != "null" ]; then
    CLAUDE_CMD="$CLAUDE_CMD --model $_model"
  fi
fi

tmux send-keys -t "${SESSION_NAME}.0" "$CLAUDE_CMD" Enter

# ── Layout adjustments ──
# Select left pane (Main) — this is where the user works
tmux select-pane -t "${SESSION_NAME}.0"

# Set pane titles (requires tmux >= 3.2 with pane-border-format)
tmux select-pane -t "${SESSION_NAME}.0" -T "Main"
tmux select-pane -t "${SESSION_NAME}.1" -T "Dashboard"
tmux select-pane -t "${SESSION_NAME}.2" -T "Monitor"
tmux select-pane -t "${SESSION_NAME}.3" -T "Eval Review"

# Enable pane border titles
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# ── Attach or print info ──
if [ "$DETACH" = true ]; then
  echo ""
  echo "Session created. Attach with:"
  echo "  tmux attach -t $SESSION_NAME"
else
  # If already in tmux, switch; otherwise attach
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION_NAME"
  else
    echo ""
    echo "Launching harness-studio..."
    echo "  Main (left)        : Interactive terminal — run 'claude' here"
    echo "  Dashboard (right↑) : Real-time progress"
    echo "  Monitor (right↔)   : Agent lifecycle events"
    echo "  Eval (right↓)      : Evaluation summaries"
    echo ""
    tmux attach -t "$SESSION_NAME"
  fi
fi
