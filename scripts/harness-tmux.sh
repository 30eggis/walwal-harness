#!/bin/bash
# harness-tmux.sh — Harness Studio tmux 4-pane 레이아웃
#
# ┌───────────────────────────┬─────────────────────────┐
# │                           │ Monitor (compact)       │
# │  Main: Control Center     ├─────────────────────────┤
# │  (Dashboard + Manual      │ Agent Session            │
# │   Prompt + Orchestration) │ (claude --skip-perms)    │
# │                           ├─────────────────────────┤
# │                           │ Eval Review              │
# │                           │ (eval 결과 요약)          │
# └───────────────────────────┴─────────────────────────┘
#
# Usage:
#   bash scripts/harness-tmux.sh [project-root]
#   bash scripts/harness-tmux.sh /path/to/project --ai
#
# Options:
#   --ai        Eval Review에서 claude -p 로 AI 요약 생성
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

# ── Resolve Claude command for Agent Session ──
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"
CLAUDE_CMD="claude --dangerously-skip-permissions"
if [ -f "$HANDOFF" ]; then
  _model=$(jq -r '.model // empty' "$HANDOFF" 2>/dev/null)
  if [ -n "$_model" ] && [ "$_model" != "null" ]; then
    CLAUDE_CMD="$CLAUDE_CMD --model $_model"
  fi
fi

# ══════════════════════════════════════════
# Layout Construction
# ══════════════════════════════════════════
# Step 1: Create session → Pane 0 = Main (Control Center)
tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 200 -y 50

# Step 2: Split right column (45% width) → Pane 1 = Monitor (top-right, compact)
tmux split-window -h -p 45 -t "$SESSION_NAME" -c "$PROJECT_ROOT" \
  "exec bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\"'"

# Step 3: Split Pane 1 vertically → Pane 2 = Agent Session (mid-right)
# Monitor gets ~20% of right column height, remaining 80% split below
tmux split-window -v -p 80 -t "${SESSION_NAME}.1" -c "$PROJECT_ROOT"

# Pane 2 = Agent Session (interactive shell, will run claude)
tmux send-keys -t "${SESSION_NAME}.2" "$CLAUDE_CMD" Enter

# Step 4: Split Pane 2 vertically → Pane 3 = Eval Review (bottom-right)
# Agent Session and Eval Review split 1:1
tmux split-window -v -p 50 -t "${SESSION_NAME}.2" -c "$PROJECT_ROOT" \
  "exec bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-eval-watcher.sh\" \"${PROJECT_ROOT}\" ${USE_AI}'"

# ── Launch Dashboard in Main pane ──
tmux send-keys -t "${SESSION_NAME}.0" "bash ${SCRIPT_DIR}/harness-dashboard.sh '${PROJECT_ROOT}'" Enter

# ── Select Main pane as active ──
tmux select-pane -t "${SESSION_NAME}.0"

# ── Pane titles ──
tmux select-pane -t "${SESSION_NAME}.0" -T "Control Center"
tmux select-pane -t "${SESSION_NAME}.1" -T "Monitor"
tmux select-pane -t "${SESSION_NAME}.2" -T "Agent Session"
tmux select-pane -t "${SESSION_NAME}.3" -T "Eval Review"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# ── Attach ──
if [ "$DETACH" = true ]; then
  echo ""
  echo "Session created. Attach with:"
  echo "  tmux attach -t $SESSION_NAME"
else
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION_NAME"
  else
    echo ""
    echo "Launching harness-studio..."
    echo "  Control Center (left)  : Dashboard + manual prompting"
    echo "  Monitor (right↑)       : Agent lifecycle (compact)"
    echo "  Agent Session (right↔) : claude --dangerously-skip-permissions"
    echo "  Eval Review (right↓)   : Evaluation summaries"
    echo ""
    tmux attach -t "$SESSION_NAME"
  fi
fi
