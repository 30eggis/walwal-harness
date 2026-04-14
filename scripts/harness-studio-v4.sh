#!/bin/bash
# harness-studio-v4.sh — Harness Studio v4: Parallel Agent Teams
#
# ┌──────────────────────┬─────────────────────────┐
# │  Dashboard            │ Team 1 (worker log)     │
# │  (Queue + Teams +     ├─────────────────────────┤
# │   Feature status)     │ Team 2 (worker log)     │
# ├──────────────────────┤                          │
# │  Control              ├─────────────────────────┤
# │  harness> _           │ Team 3 (worker log)     │
# └──────────────────────┴─────────────────────────┘
#
# Usage:
#   bash scripts/harness-studio-v4.sh [project-root]
#   bash scripts/harness-studio-v4.sh --kill

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-v4"

PROJECT_ROOT=""
KILL=false

for arg in "$@"; do
  case "$arg" in
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

# ── Initialize queue if not exists ──
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
if [ ! -f "$QUEUE" ]; then
  echo "Initializing feature queue..."
  bash "$SCRIPT_DIR/harness-queue-manager.sh" init "$PROJECT_ROOT"
fi

# ══════════════════════════════════════════
# Build 5-pane layout using explicit pane IDs
# ══════════════════════════════════════════

# 1. Dashboard (top-left)
PANE_DASH=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 200 -y 50 \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard-v4.sh\" \"${PROJECT_ROOT}\"'")

# 2. Team 1 (top-right)
PANE_T1=$(tmux split-window -h -p 50 -t "$PANE_DASH" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 1 \"${PROJECT_ROOT}\"'")

# 3. Control (bottom-left, 25% of left)
PANE_CTRL=$(tmux split-window -v -p 25 -t "$PANE_DASH" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-control-v4.sh\" \"${PROJECT_ROOT}\"'")

# 4. Team 2 (middle-right, split from Team 1)
PANE_T2=$(tmux split-window -v -p 66 -t "$PANE_T1" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 2 \"${PROJECT_ROOT}\"'")

# 5. Team 3 (bottom-right, split from Team 2)
PANE_T3=$(tmux split-window -v -p 50 -t "$PANE_T2" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 3 \"${PROJECT_ROOT}\"'")

# ── Pane titles ──
tmux select-pane -t "$PANE_DASH" -T "Dashboard"
tmux select-pane -t "$PANE_CTRL" -T "Control"
tmux select-pane -t "$PANE_T1"   -T "Team 1"
tmux select-pane -t "$PANE_T2"   -T "Team 2"
tmux select-pane -t "$PANE_T3"   -T "Team 3"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# Focus Control
tmux select-pane -t "$PANE_CTRL"

# Attach
if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$SESSION_NAME"
else
  echo ""
  echo "Launching Harness Studio v4..."
  echo "  Dashboard (left↑)  : Feature Queue + Team status"
  echo "  Control (left↓)    : start/pause/assign/requeue"
  echo "  Team 1-3 (right)   : Parallel worker logs"
  echo ""
  tmux attach -t "$SESSION_NAME"
fi
