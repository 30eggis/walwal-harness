#!/bin/bash
# harness-studio-v4.sh — Harness Studio v4: 3-Column Layout
#
# ┌──────────────┬──────────────┬──────────────┐
# │              │              │  Team 1      │
# │              │              ├──────────────┤
# │  Main        │  Dashboard   │  Team 2      │
# │  (Claude)    │  (read-only) ├──────────────┤
# │              │              │  Team 3      │
# └──────────────┴──────────────┴──────────────┘
#
# Main: 사용자가 직접 Claude Code를 실행하는 대화형 세션
# Dashboard: feature-queue + team status 자동 갱신 (입력 불가)
# Team 1~3: claude -p headless worker (입력 불가, 로그만 표시)
#
# Usage:
#   bash scripts/harness-studio-v4.sh [project-root]
#   bash scripts/harness-studio-v4.sh --kill

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

# ── Initialize queue if not exists ──
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
if [ ! -f "$QUEUE" ]; then
  echo "Initializing feature queue..."
  bash "$SCRIPT_DIR/harness-queue-manager.sh" init "$PROJECT_ROOT"
fi

# ══════════════════════════════════════════
# 3-Column Layout (Main | Dashboard | Teams)
# ══════════════════════════════════════════

# Column 1: Main (interactive shell — user runs claude here)
PANE_MAIN=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 \
  -P -F '#{pane_id}')

# Column 2: Dashboard (split right from Main, 66% remaining → 33% each of 3 cols)
PANE_DASH=$(tmux split-window -h -p 66 -t "$PANE_MAIN" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard-v4.sh\" \"${PROJECT_ROOT}\"'")

# Column 3: Team 1 (split right from Dashboard, 50% of remaining = 33% total)
PANE_T1=$(tmux split-window -h -p 50 -t "$PANE_DASH" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 1 \"${PROJECT_ROOT}\"'")

# Team 2 (split below Team 1)
PANE_T2=$(tmux split-window -v -p 66 -t "$PANE_T1" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 2 \"${PROJECT_ROOT}\"'")

# Team 3 (split below Team 2)
PANE_T3=$(tmux split-window -v -p 50 -t "$PANE_T2" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-team-worker.sh\" 3 \"${PROJECT_ROOT}\"'")

# ── Prepare Main pane (unset nvm noise, clear) ──
tmux send-keys -t "$PANE_MAIN" "unset npm_config_prefix 2>/dev/null; clear" Enter

# ── Pane titles ──
tmux select-pane -t "$PANE_MAIN" -T "Main"
tmux select-pane -t "$PANE_DASH" -T "Dashboard"
tmux select-pane -t "$PANE_T1"   -T "Team 1"
tmux select-pane -t "$PANE_T2"   -T "Team 2"
tmux select-pane -t "$PANE_T3"   -T "Team 3"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# ── Focus Main pane ──
tmux select-pane -t "$PANE_MAIN"

# ── Attach ──
if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$SESSION_NAME"
else
  echo ""
  echo "Launching Harness Studio v4..."
  echo "  Main (left)      : Interactive — run 'claude' here"
  echo "  Dashboard (mid)  : Feature Queue + Team status (auto-refresh)"
  echo "  Team 1-3 (right) : Parallel workers (headless, log only)"
  echo ""
  tmux attach -t "$SESSION_NAME"
fi
