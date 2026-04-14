#!/bin/bash
# harness-prompts-v4.sh — v4 Dashboard 하단: Manual Prompts + Activity
# progress.log에서 user-prompt와 team 활동을 newest-first로 표시.
# 스크롤 가능 영역 — 프롬프트가 많아져도 상단 Progress를 가리지 않음.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  source "$SCRIPT_DIR/lib/harness-render-progress.sh"
  PROJECT_ROOT="$(resolve_harness_root ".")" || { echo "[prompts] .harness/ not found."; exit 1; }
fi

LOG_FILE="$PROJECT_ROOT/.harness/progress.log"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"

LAST_LINE_COUNT=0

render_prompts() {
  if [ ! -f "$LOG_FILE" ]; then
    echo -e "  ${DIM}(progress.log not found)${RESET}"
    return
  fi

  local term_h
  term_h=$(tput lines 2>/dev/null || echo 20)
  local max_lines=$((term_h - 3))  # Leave room for header
  if [ "$max_lines" -lt 5 ]; then max_lines=5; fi

  echo -e "${BOLD}Prompts & Activity${RESET} ${DIM}(newest first)${RESET}"
  echo ""

  # Read all entries, reverse, limit to terminal height
  grep -v '^#' "$LOG_FILE" 2>/dev/null | grep -v '^$' | \
  tail -r 2>/dev/null | head -"$max_lines" | \
  while IFS= read -r line; do
    local ts agent action detail
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

    local short_ts icon color
    short_ts=$(echo "$ts" | sed 's/^[0-9]*-//')

    case "$agent" in
      user-prompt)
        icon="★"; color="$BOLD"
        # User prompts get full width, highlighted
        if [ ${#detail} -gt 60 ]; then detail="${detail:0:58}.."; fi
        echo -e "  ${color}${icon} ${short_ts}${RESET} ${detail}"
        ;;
      dispatcher*)
        icon="▸"; color="$MAGENTA"
        if [ ${#detail} -gt 50 ]; then detail="${detail:0:48}.."; fi
        echo -e "  ${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${agent} ${DIM}${action}${RESET} ${detail}"
        ;;
      team-*)
        icon="⚡"; color="$CYAN"
        if [ ${#detail} -gt 50 ]; then detail="${detail:0:48}.."; fi
        # Color by action type
        case "$action" in
          *pass*)  color="$GREEN"; icon="✓" ;;
          *fail*)  color="$RED";   icon="✗" ;;
          *eval*)  color="$MAGENTA"; icon="✦" ;;
          *gen*)   color="$CYAN";  icon="▶" ;;
          *merge*) color="$GREEN"; icon="⊕" ;;
        esac
        echo -e "  ${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${agent} ${DIM}${action}${RESET} ${detail}"
        ;;
      manual)
        icon="★"; color="$YELLOW"
        if [ ${#detail} -gt 50 ]; then detail="${detail:0:48}.."; fi
        echo -e "  ${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${detail}"
        ;;
      *)
        icon="·"; color="$DIM"
        if [ ${#detail} -gt 50 ]; then detail="${detail:0:48}.."; fi
        echo -e "  ${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${agent} ${DIM}${action}${RESET} ${detail}"
        ;;
    esac
  done
}

# ── Main loop ──
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit 0' EXIT INT TERM
clear

while true; do
  buf=$(render_prompts 2>&1)
  tput cup 0 0 2>/dev/null
  echo "$buf"
  tput ed 2>/dev/null
  sleep 3
done
