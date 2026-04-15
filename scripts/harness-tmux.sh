#!/bin/bash
# harness-tmux.sh — Unified Harness Studio tmux layout
#
# Team Mode (--team):
# ┌──────────────┬──────────────┬──────────────┐
# │  Prompt      │  Dashboard   │   TEAM 1     │
# │  History     │  (queue +    │  Gen | Eval   │
# │              │   status)    ├──────────────┤
# ├──────────────┤              │   TEAM 2     │
# │  Controller  │              │  Gen | Eval   │
# │  (Claude /   │              ├──────────────┤
# │   Codex)     │              │   TEAM 3     │
# └──────────────┴──────────────┴──────────────┘
#
# Solo Mode (--solo):
# ┌──────────────┬──────────────┬──────────────┐
# │  Dashboard   │  Monitor     │  Agent       │
# │              │  (compact)   │  Session     │
# ├──────────────┤              │              │
# │  Prompt      │              │              │
# │  History     │              │              │
# └──────────────┴──────────────┴──────────────┘
#
# Usage:
#   bash scripts/harness-tmux.sh [project-root] --team
#   bash scripts/harness-tmux.sh [project-root] --solo
#   bash scripts/harness-tmux.sh --kill

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-studio"

PROJECT_ROOT=""
MODE=""
DETACH=false

for arg in "$@"; do
  case "$arg" in
    --team)   MODE="team" ;;
    --solo)   MODE="solo" ;;
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

# Auto-detect mode from progress.json if not specified
if [ -z "$MODE" ]; then
  if command -v jq &>/dev/null && [ -f "$PROJECT_ROOT/.harness/progress.json" ]; then
    MODE=$(jq -r '.mode // "solo"' "$PROJECT_ROOT/.harness/progress.json" 2>/dev/null)
  fi
  MODE="${MODE:-solo}"
fi

echo "Project: $PROJECT_ROOT"
echo "Session: $SESSION_NAME"
echo "Mode: $MODE"

tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# ══════════════════════════════════════════
# Team Mode: 3-column layout (6 panes)
# ══════════════════════════════════════════
if [ "$MODE" = "team" ]; then

  # 1. Create session → Left pane (will become Prompt History)
  PANE_LEFT=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 \
    -P -F '#{pane_id}')

  # 2. Split horizontally: Left 30% | Right 70%
  PANE_MID=$(tmux split-window -h -p 70 -t "$PANE_LEFT" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}')

  # 3. Split right section: Middle 40% | Right 60% (Teams)
  PANE_T1=$(tmux split-window -h -p 60 -t "$PANE_MID" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 1'")

  # 4. Split Team 1 vertically → Team 2 (bottom 66%)
  PANE_T2=$(tmux split-window -v -p 66 -t "$PANE_T1" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 2'")

  # 5. Split Team 2 vertically → Team 3 (bottom 50%)
  PANE_T3=$(tmux split-window -v -p 50 -t "$PANE_T2" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 3'")

  # 6. Split left pane vertically: Prompt History (top 45%) | Controller (bottom 55%)
  PANE_CTRL=$(tmux split-window -v -p 55 -t "$PANE_LEFT" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}')

  # 7. Start Prompt History in left-top
  tmux send-keys -t "$PANE_LEFT" "bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"" Enter

  # 8. Start Dashboard in middle pane
  tmux send-keys -t "$PANE_MID" "bash \"${SCRIPT_DIR}/harness-dashboard.sh\" \"${PROJECT_ROOT}\"" Enter

  # 9. Controller pane — ready for Claude/Codex
  tmux send-keys -t "$PANE_CTRL" "unset npm_config_prefix 2>/dev/null" Enter
  tmux send-keys -t "$PANE_CTRL" "clear" Enter

  # Pane titles
  tmux select-pane -t "$PANE_LEFT"  -T "Prompt History"
  tmux select-pane -t "$PANE_CTRL"  -T "Controller"
  tmux select-pane -t "$PANE_MID"   -T "Dashboard"
  tmux select-pane -t "$PANE_T1"    -T "TEAM 1"
  tmux select-pane -t "$PANE_T2"    -T "TEAM 2"
  tmux select-pane -t "$PANE_T3"    -T "TEAM 3"

  # Focus on Controller
  tmux select-pane -t "$PANE_CTRL"

# ══════════════════════════════════════════
# Solo Mode: 3-column layout (5 panes)
# ══════════════════════════════════════════
else

  # 1. Create session → Dashboard pane
  PANE_DASHBOARD=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 200 -y 50 \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard.sh\" \"${PROJECT_ROOT}\"'")

  # 2. Split horizontally: Left 40% | Right 60%
  PANE_MONITOR=$(tmux split-window -h -p 60 -t "$PANE_DASHBOARD" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\"'")

  # 3. Split Dashboard vertically: Dashboard (top 70%) | Prompt History (bottom 30%)
  PANE_HISTORY=$(tmux split-window -v -p 30 -t "$PANE_DASHBOARD" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"'")

  # 4. Split Monitor: Monitor (top 15%) | Agent Session (bottom 85%)
  PANE_AGENT=$(tmux split-window -v -p 85 -t "$PANE_MONITOR" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}')

  # 5. Agent Session — empty shell ready for claude
  tmux send-keys -t "$PANE_AGENT" "unset npm_config_prefix 2>/dev/null" Enter
  tmux send-keys -t "$PANE_AGENT" "clear" Enter

  # Pane titles
  tmux select-pane -t "$PANE_DASHBOARD" -T "Dashboard"
  tmux select-pane -t "$PANE_MONITOR"   -T "Monitor"
  tmux select-pane -t "$PANE_HISTORY"   -T "Prompt History"
  tmux select-pane -t "$PANE_AGENT"     -T "Agent Session"

  # Focus on Agent Session
  tmux select-pane -t "$PANE_AGENT"
fi

# ── Common settings ──
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# ── Attach ──
if [ "$DETACH" = true ]; then
  echo ""
  echo "Session created. Attach: tmux attach -t $SESSION_NAME"
  echo "Layout ready"
elif ! tty -s 2>/dev/null; then
  # Non-terminal environment (e.g., Claude Code agent session)
  # Try opening Terminal.app on macOS, otherwise detach silently
  if [ "$(uname)" = "Darwin" ]; then
    osascript -e "tell application \"Terminal\" to do script \"tmux attach -t $SESSION_NAME\"" 2>/dev/null && \
      echo "OPENED_TERMINAL=true" || echo "Layout ready"
  else
    echo "Session created (non-terminal). Attach: tmux attach -t $SESSION_NAME"
    echo "Layout ready"
  fi
else
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION_NAME"
  else
    echo ""
    echo "Launching Harness Studio ($MODE mode)..."
    echo "  Stop: bash scripts/harness-tmux.sh --kill"
    echo ""
    tmux attach -t "$SESSION_NAME"
  fi
fi
