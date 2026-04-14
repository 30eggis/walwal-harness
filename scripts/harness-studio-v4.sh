#!/bin/bash
# harness-studio-v4.sh — Harness Studio v4
#
# ┌──────────────┬──────────────┬──────────────┐
# │              │  Progress    │  Team 1      │
# │  Main        ├──────────────┤  Team 2      │
# │  (claude)    │  Prompts     │  Team 3      │
# └──────────────┴──────────────┴──────────────┘

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-v4"

PROJECT_ROOT=""
for arg in "$@"; do
  case "$arg" in
    --kill) tmux kill-session -t "$SESSION_NAME" 2>/dev/null && echo "Killed." || echo "No session."; exit 0 ;;
    *) if [ -d "$arg" ]; then PROJECT_ROOT="$arg"; fi ;;
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
  echo "Error: .harness/ not found."; exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
echo "Project: $PROJECT_ROOT"

tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
sleep 1
# Ensure no leftover session
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# ── Queue ──
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
if [ ! -f "$QUEUE" ]; then
  bash "$SCRIPT_DIR/harness-queue-manager.sh" init "$PROJECT_ROOT"
else
  bash "$SCRIPT_DIR/harness-queue-manager.sh" recover "$PROJECT_ROOT"
fi

# ══════════════════════════════════════════
# Layout: use PANE IDs (not indices!) to avoid renumbering issues
#
# 1. MAIN
# 2. split-h MAIN → MAIN | RIGHT           (RIGHT = pane ID captured)
# 3. split-h RIGHT → MID | RIGHT           (use -P to capture MID ID, RIGHT stays)
# 4. split-v RIGHT → T1 | T2_AREA          (RIGHT becomes T1, T2_AREA captured)
# 5. split-v T2_AREA → T2 | T3             (T2_AREA becomes T2, T3 captured)
# 6. split-v MID → PROGRESS | PROMPTS      (MID becomes PROGRESS, PROMPTS captured)
# ══════════════════════════════════════════

# 1. MAIN
P_MAIN=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 \
  -P -F '#{pane_id}')

# 2. RIGHT column (66% of total)
P_RIGHT=$(tmux split-window -h -p 66 -t "$P_MAIN" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')

# 3. MID column — split RIGHT, new pane goes LEFT of RIGHT (using -b flag)
P_MID=$(tmux split-window -hb -p 50 -t "$P_RIGHT" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')
# P_MID = left half (mid column), P_RIGHT = right half (teams column)

# 4. T1/T2 area — split RIGHT vertically (66% goes to new pane below)
P_T2_AREA=$(tmux split-window -v -p 66 -t "$P_RIGHT" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')
P_T1="$P_RIGHT"
# P_T1 = top 34%, P_T2_AREA = bottom 66%

# 5. T2/T3 — split T2_AREA (50/50)
P_T3=$(tmux split-window -v -p 50 -t "$P_T2_AREA" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')
P_T2="$P_T2_AREA"

# 6. Progress/Prompts — split MID vertically
P_PROMPTS=$(tmux split-window -v -p 40 -t "$P_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')
P_PROGRESS="$P_MID"

# ── Commands (using pane IDs — stable regardless of index renumbering) ──
tmux send-keys -t "$P_MAIN"     "unset npm_config_prefix 2>/dev/null; clear && claude --dangerously-skip-permissions" Enter
tmux send-keys -t "$P_PROGRESS" "exec bash '${SCRIPT_DIR}/harness-dashboard-v4.sh' '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_PROMPTS"  "exec bash '${SCRIPT_DIR}/harness-prompts-v4.sh' '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_T1"       "exec bash '${SCRIPT_DIR}/harness-team-worker.sh' 1 '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_T2"       "exec bash '${SCRIPT_DIR}/harness-team-worker.sh' 2 '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_T3"       "exec bash '${SCRIPT_DIR}/harness-team-worker.sh' 3 '${PROJECT_ROOT}'" Enter

# ── Titles ──
tmux select-pane -t "$P_MAIN"     -T "Main"
tmux select-pane -t "$P_PROGRESS" -T "Progress"
tmux select-pane -t "$P_PROMPTS"  -T "Prompts"
tmux select-pane -t "$P_T1"       -T "Team 1"
tmux select-pane -t "$P_T2"       -T "Team 2"
tmux select-pane -t "$P_T3"       -T "Team 3"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true
tmux select-pane -t "$P_MAIN"

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$SESSION_NAME"
else
  tmux attach -t "$SESSION_NAME"
fi
