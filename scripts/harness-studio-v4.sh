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

echo "Project: $PROJECT_ROOT"
echo "Session: $SESSION_NAME"

tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
sleep 0.5

# ── Init/recover queue ──
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
if [ ! -f "$QUEUE" ]; then
  echo "Initializing feature queue..."
  bash "$SCRIPT_DIR/harness-queue-manager.sh" init "$PROJECT_ROOT"
else
  echo "Recovering stale queue state..."
  bash "$SCRIPT_DIR/harness-queue-manager.sh" recover "$PROJECT_ROOT"
fi

# ══════════════════════════════════════════
# Build layout — all panes use direct command execution
# Panes that exit will show "Pane is dead" instead of closing
# ══════════════════════════════════════════

tmux set-option -g remain-on-exit on 2>/dev/null || true

# 1. Main (left, 34%)
PANE_MAIN=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 \
  -P -F '#{pane_id}')

# 2. Right area (66%) — will become Teams
PANE_RIGHT=$(tmux split-window -h -p 66 -t "$PANE_MAIN" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash '${SCRIPT_DIR}/harness-team-worker.sh' 1 '${PROJECT_ROOT}'")

# 3. Middle column — split from Right (50/50)
PANE_MID=$(tmux split-window -h -p 50 -t "$PANE_RIGHT" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash '${SCRIPT_DIR}/harness-team-worker.sh' 2 '${PROJECT_ROOT}'")

# Now layout: [Main 34%] [Right 33%] [Mid 33%]
# Right = Team 1, Mid = Team 2
# But we need: [Main] [Dashboard area] [Teams area]
# Swap: Right should be dashboard, Mid should stay as teams
# Actually after split: PANE_RIGHT stays left (=Team1), PANE_MID is new right (=Team2)
# We need to rethink...

# Let me use a cleaner approach: create all columns first with placeholder shells

tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
sleep 0.3

# === Clean rebuild ===

# Pane 0: Main
tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55

# Split: [Main 34% | Rest 66%]
tmux split-window -h -p 66 -t "${SESSION_NAME}:0.0" -c "$PROJECT_ROOT"

# Split Rest: [Main 34% | Mid 50% | Right 50%]  (of the 66%)
tmux split-window -h -p 50 -t "${SESSION_NAME}:0.1" -c "$PROJECT_ROOT"

# Now: pane 0 = Main (left), pane 1 = Mid, pane 2 = Right
# Split Mid vertically: Progress (60%) / Prompts (40%)
tmux split-window -v -p 40 -t "${SESSION_NAME}:0.1" -c "$PROJECT_ROOT"

# Now: pane 0=Main, pane 1=Mid-top(Progress), pane 2=Right, pane 3=Mid-bottom(Prompts)
# Split Right into 3 Teams
tmux split-window -v -p 66 -t "${SESSION_NAME}:0.2" -c "$PROJECT_ROOT"
tmux split-window -v -p 50 -t "${SESSION_NAME}:0.3" -c "$PROJECT_ROOT"

# Now 6 panes. Let's identify them by listing:
# pane 0 = Main (left)
# pane 1 = Progress (mid-top)
# pane 2 = Team area top
# pane 3 = Prompts (mid-bottom)
# pane 4 = Team area mid (split from pane 2's bottom sibling? — tmux numbering is tricky)

# Instead of guessing pane numbers, send commands to each pane by index after creation
# First set remain-on-exit for this session
tmux set-option -t "$SESSION_NAME" remain-on-exit on 2>/dev/null || true

# Get all pane IDs in order
PANES=($(tmux list-panes -t "$SESSION_NAME" -F '#{pane_id}'))

# Should be 6 panes. Assign by position:
# Visual order (left-to-right, top-to-bottom):
# [0] Main  [1] Progress  [2] Team-top
#           [3] Prompts   [4] Team-mid
#                         [5] Team-bottom

if [ ${#PANES[@]} -ne 6 ]; then
  echo "ERROR: Expected 6 panes, got ${#PANES[@]}"
  echo "Panes: ${PANES[*]}"
  tmux attach -t "$SESSION_NAME"
  exit 1
fi

P_MAIN="${PANES[0]}"
P_PROGRESS="${PANES[1]}"
P_TEAM1="${PANES[2]}"
P_PROMPTS="${PANES[3]}"
P_TEAM2="${PANES[4]}"
P_TEAM3="${PANES[5]}"

# Send commands to each pane
tmux send-keys -t "$P_MAIN" "unset npm_config_prefix 2>/dev/null; clear && claude --dangerously-skip-permissions" Enter
tmux send-keys -t "$P_PROGRESS" "bash '${SCRIPT_DIR}/harness-dashboard-v4.sh' '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_PROMPTS" "bash '${SCRIPT_DIR}/harness-prompts-v4.sh' '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_TEAM1" "bash '${SCRIPT_DIR}/harness-team-worker.sh' 1 '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_TEAM2" "bash '${SCRIPT_DIR}/harness-team-worker.sh' 2 '${PROJECT_ROOT}'" Enter
tmux send-keys -t "$P_TEAM3" "bash '${SCRIPT_DIR}/harness-team-worker.sh' 3 '${PROJECT_ROOT}'" Enter

# Titles
tmux select-pane -t "$P_MAIN"     -T "Main"
tmux select-pane -t "$P_PROGRESS" -T "Progress"
tmux select-pane -t "$P_PROMPTS"  -T "Prompts"
tmux select-pane -t "$P_TEAM1"    -T "Team 1"
tmux select-pane -t "$P_TEAM2"    -T "Team 2"
tmux select-pane -t "$P_TEAM3"    -T "Team 3"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# Focus Main
tmux select-pane -t "$P_MAIN"

# Attach
if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$SESSION_NAME"
else
  echo ""
  echo "Launching Harness Studio v4..."
  tmux attach -t "$SESSION_NAME"
fi
