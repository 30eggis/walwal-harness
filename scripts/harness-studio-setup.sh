#!/bin/bash
# harness-studio-setup.sh — Claude 세션에서 3-column 레이아웃 자동 구축
#
# ┌──────────────┬──────────────┬──────────────┐
# │              │  Dashboard   │              │
# │  Claude      │  (v4 queue)  │  Team Monitor│
# │  (Lead)      ├──────────────┤  (lifecycle) │
# │              │  Command     │              │
# │              │  History     │              │
# └──────────────┴──────────────┴──────────────┘
#
# 두 가지 상황을 모두 처리:
#   A) tmux 안에서 실행 → 현재 pane을 split하여 레이아웃 구축
#   B) tmux 밖에서 실행 → 새 tmux 세션 생성, Claude를 좌측 pane에서 재실행
#
# Usage:
#   bash scripts/harness-studio-setup.sh [project-root]
#
# 이미 구축됐으면 skip (멱등성 보장)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-studio"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then PROJECT_ROOT="$dir"; break; fi
    dir="$(dirname "$dir")"
  done
fi

if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT/.harness" ]; then
  echo "[studio] .harness/ not found."
  exit 1
fi

# ── Resolve Claude command ──
CLAUDE_CMD="claude --dangerously-skip-permissions"
if [ -f "$PROJECT_ROOT/.harness/handoff.json" ]; then
  _model=$(jq -r '.model // empty' "$PROJECT_ROOT/.harness/handoff.json" 2>/dev/null)
  if [ -n "$_model" ] && [ "$_model" != "null" ]; then
    CLAUDE_CMD="$CLAUDE_CMD --model $_model"
  fi
fi

# ══════════════════════════════════════════
# Case A: 이미 tmux 안에 있음 → pane split
# ══════════════════════════════════════════
if [ -n "${TMUX:-}" ]; then
  # 멱등성: 이미 pane이 3개 이상이면 skip
  PANE_COUNT=$(tmux list-panes | wc -l | tr -d ' ')
  if [ "$PANE_COUNT" -ge 3 ]; then
    echo "[studio] Layout already set up ($PANE_COUNT panes). Skipping."
    exit 0
  fi

  PANE_CLAUDE=$(tmux display-message -p '#{pane_id}')
  echo "[studio] Setting up 3-column layout (in-place split)..."

  # Left 35% | Right 65%
  PANE_MID=$(tmux split-window -h -p 65 -t "$PANE_CLAUDE" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard-v4.sh\" \"${PROJECT_ROOT}\"'")

  # Middle 45% | Right 55%
  PANE_RIGHT=$(tmux split-window -h -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\"'")

  # Dashboard top 45% | History bottom 55%
  PANE_HISTORY=$(tmux split-window -v -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
    -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"'")

  # Pane titles
  tmux select-pane -t "$PANE_CLAUDE"  -T "Lead (Claude)"
  tmux select-pane -t "$PANE_MID"     -T "Dashboard"
  tmux select-pane -t "$PANE_HISTORY" -T "Command History"
  tmux select-pane -t "$PANE_RIGHT"   -T "Team Monitor"

  tmux set-option pane-border-status top 2>/dev/null || true
  tmux set-option pane-border-format " #{pane_title} " 2>/dev/null || true

  # 포커스를 Claude pane으로 복귀
  tmux select-pane -t "$PANE_CLAUDE"

  echo "[studio] Layout ready (in-place)."
  exit 0
fi

# ══════════════════════════════════════════
# Case B: tmux 밖에 있음 → 새 세션 생성
# ══════════════════════════════════════════

# 이미 세션이 있으면 attach만
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "[studio] Session '$SESSION_NAME' already exists. Attaching..."
  echo "[studio] ATTACH_TMUX=$SESSION_NAME"
  exit 0
fi

echo "[studio] Creating new tmux session with 3-column layout..."

# 1. 새 세션 → Left pane (Claude 실행)
PANE_MAIN=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 \
  -P -F '#{pane_id}')

# 2. Left 35% | Right 65%
PANE_MID=$(tmux split-window -h -p 65 -t "$PANE_MAIN" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard-v4.sh\" \"${PROJECT_ROOT}\"'")

# 3. Middle 45% | Right 55%
PANE_RIGHT=$(tmux split-window -h -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\"'")

# 4. Dashboard top 45% | History bottom 55%
PANE_HISTORY=$(tmux split-window -v -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"'")

# 5. Left pane에서 Claude 자동 실행
tmux send-keys -t "$PANE_MAIN" "unset npm_config_prefix 2>/dev/null" Enter
tmux send-keys -t "$PANE_MAIN" "clear && $CLAUDE_CMD" Enter

# Pane titles
tmux select-pane -t "$PANE_MAIN"    -T "Lead (Claude)"
tmux select-pane -t "$PANE_MID"     -T "Dashboard"
tmux select-pane -t "$PANE_HISTORY" -T "Command History"
tmux select-pane -t "$PANE_RIGHT"   -T "Team Monitor"

tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# Focus on Claude pane
tmux select-pane -t "$PANE_MAIN"

echo "[studio] Session '$SESSION_NAME' created."
echo "[studio] ATTACH_TMUX=$SESSION_NAME"
