#!/bin/bash
# harness-studio-v4.sh — Harness Studio v4: 3-Column + Dashboard Split
#
# ┌──────────────┬──────────────┬──────────────┐
# │              │  Progress    │  Team 1      │
# │              │  (fixed)     ├──────────────┤
# │  Main        ├──────────────┤  Team 2      │
# │  (claude)    │  Prompts     ├──────────────┤
# │              │  (scroll)    │  Team 3      │
# └──────────────┴──────────────┴──────────────┘

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-v4"

PROJECT_ROOT=""

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
# Layout: 3 columns first, then split middle column
#
# Step 1: [Main]
# Step 2: [Main | Right]          — h split 66%
# Step 3: [Main | Mid | Right]    — h split Mid from Right at 50%
# Step 4: [Main | Progress / Prompts | Right]  — v split Mid
# Step 5: [Main | Progress / Prompts | T1 / T2 / T3]  — v split Right
# ══════════════════════════════════════════

# 1. Main
PANE_MAIN=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 \
  -P -F '#{pane_id}')

# 2. Right column (will become Team area)
PANE_RIGHT=$(tmux split-window -h -p 66 -t "$PANE_MAIN" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')

# 3. Middle column (split from Right, 50% = Mid gets left half, Right keeps right half)
PANE_MID=$(tmux split-window -h -p 50 -t "$PANE_RIGHT" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}')
# Now: PANE_MID is the NEW pane (right side of split), PANE_RIGHT stays left
# Wait — tmux split-window -h on PANE_RIGHT creates new pane to the RIGHT of PANE_RIGHT
# So PANE_MID ends up on the right, and PANE_RIGHT is in the middle
# We need to swap: split PANE_MAIN's right, then the rightmost becomes teams

# Actually let me reconsider. After step 2:
#   [Main 33%] [Right 66%]
# After step 3 (split Right horizontally at 50%):
#   [Main 33%] [Right_left 33%] [Right_right 33%]
# Right_left = PANE_RIGHT (original), Right_right = PANE_MID (new)
# We want: Right_left = Dashboard area, Right_right = Team area
# So PANE_RIGHT becomes Dashboard, PANE_MID becomes Teams. But pane IDs...
# Actually: split-window creates the NEW pane. -h splits horizontally.
# The new pane goes to the right. So:
#   PANE_RIGHT (original) = middle column (Dashboard)
#   PANE_MID (new) = right column (Teams)
# Perfect!

# 4. Split middle column (PANE_RIGHT = Dashboard area) into Progress + Prompts
#    Kill the shell in PANE_RIGHT first, replace with Progress
tmux send-keys -t "$PANE_RIGHT" "exec bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard-v4.sh\" \"${PROJECT_ROOT}\"'" Enter

PANE_PROMPTS=$(tmux split-window -v -p 40 -t "$PANE_RIGHT" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompts-v4.sh\" \"${PROJECT_ROOT}\"'")

# 5. Split right column (PANE_MID = Team area) into Team 1/2/3
tmux send-keys -t "$PANE_MID" "exec bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 1 \"${PROJECT_ROOT}\"'" Enter

PANE_T2=$(tmux split-window -v -p 66 -t "$PANE_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 2 \"${PROJECT_ROOT}\"'")

PANE_T3=$(tmux split-window -v -p 50 -t "$PANE_T2" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 3 \"${PROJECT_ROOT}\"'")

# ── Launch Claude in Main ──
tmux send-keys -t "$PANE_MAIN" "unset npm_config_prefix 2>/dev/null; clear && claude --dangerously-skip-permissions" Enter

# ── Pane titles ──
tmux select-pane -t "$PANE_MAIN"    -T "Main"
tmux select-pane -t "$PANE_RIGHT"   -T "Progress"
tmux select-pane -t "$PANE_PROMPTS" -T "Prompts"
tmux select-pane -t "$PANE_MID"     -T "Team 1"
tmux select-pane -t "$PANE_T2"      -T "Team 2"
tmux select-pane -t "$PANE_T3"      -T "Team 3"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# ── Focus Main ──
tmux select-pane -t "$PANE_MAIN"

# ── Attach ──
if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$SESSION_NAME"
else
  echo ""
  echo "Launching Harness Studio v4..."
  echo "  Main (left)       : Claude interactive"
  echo "  Progress (mid↑)   : Queue + Teams + Features"
  echo "  Prompts (mid↓)    : Manual prompts + activity"
  echo "  Team 1-3 (right)  : Parallel workers"
  echo ""
  tmux attach -t "$SESSION_NAME"
fi
