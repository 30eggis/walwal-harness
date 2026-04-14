#!/bin/bash
# harness-studio-setup.sh — Claude 세션 내부에서 실행하여 3-column 레이아웃 자동 구축
#
# Claude가 이미 실행 중인 tmux pane에서 호출됨.
# 현재 pane(Claude가 있는 곳)을 Left로 유지하고,
# Center(Dashboard + History)와 Right(Monitor)를 split으로 생성.
#
# ┌──────────────┬──────────────┬──────────────┐
# │              │  Dashboard   │              │
# │  여기서      │  (v4 queue)  │  Team Monitor│
# │  Claude 실행중├──────────────┤  (lifecycle) │
# │              │  Command     │              │
# │              │  History     │              │
# └──────────────┴──────────────┴──────────────┘
#
# Usage (Claude가 bash 도구로 호출):
#   bash scripts/harness-studio-setup.sh [project-root]
#
# 이미 구축됐으면 skip (멱등성 보장)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# ── tmux 내부인지 확인 ──
if [ -z "${TMUX:-}" ]; then
  echo "[studio] Not inside tmux. Layout requires tmux."
  echo "[studio] Start with: tmux new-session -s harness"
  exit 1
fi

# ── 멱등성: 이미 pane이 3개 이상이면 skip ──
PANE_COUNT=$(tmux list-panes | wc -l | tr -d ' ')
if [ "$PANE_COUNT" -ge 3 ]; then
  echo "[studio] Layout already set up ($PANE_COUNT panes). Skipping."
  exit 0
fi

# ── 현재 pane = Claude (Left) ──
PANE_CLAUDE=$(tmux display-message -p '#{pane_id}')

echo "[studio] Setting up 3-column layout..."

# ── Split: Left 35% | Right 65% ──
PANE_MID=$(tmux split-window -h -p 65 -t "$PANE_CLAUDE" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-dashboard-v4.sh\" \"${PROJECT_ROOT}\"'")

# ── Split right: Middle 45% | Right 55% ──
PANE_RIGHT=$(tmux split-window -h -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\"'")

# ── Split middle vertically: Dashboard (top 45%) | History (bottom 55%) ──
PANE_HISTORY=$(tmux split-window -v -p 55 -t "$PANE_MID" -c "$PROJECT_ROOT" \
  -P -F '#{pane_id}' \
  "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"'")

# ── Pane titles ──
tmux select-pane -t "$PANE_CLAUDE"  -T "Lead (Claude)"
tmux select-pane -t "$PANE_MID"     -T "Dashboard"
tmux select-pane -t "$PANE_HISTORY" -T "Command History"
tmux select-pane -t "$PANE_RIGHT"   -T "Team Monitor"

tmux set-option pane-border-status top 2>/dev/null || true
tmux set-option pane-border-format " #{pane_title} " 2>/dev/null || true

# ── 포커스를 Claude pane으로 돌림 ──
tmux select-pane -t "$PANE_CLAUDE"

echo "[studio] Layout ready."
echo "[studio]   Left   : Lead (Claude) — you are here"
echo "[studio]   Center : Dashboard + Command History"
echo "[studio]   Right  : Team Monitor"
