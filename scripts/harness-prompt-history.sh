#!/bin/bash
# harness-prompt-history.sh — Prompt History pane for v4 tmux layout
# progress.log + audit.log에서 유저 프롬프트/에이전트 활동 히스토리를 표시
# Usage: bash scripts/harness-prompt-history.sh [project-root]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_harness_root ".")" || { echo "[history] .harness/ not found."; exit 1; }
fi

PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"
AUDIT_LOG="$PROJECT_ROOT/.harness/actions/audit.log"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"

render_header() {
  echo -e "${BOLD}PROMPT HISTORY${RESET}  ${DIM}$(date +%H:%M:%S)${RESET}"
  echo ""
}

render_progress_log() {
  if [ ! -f "$PROGRESS_LOG" ]; then
    echo -e "  ${DIM}(no progress.log yet)${RESET}"
    return
  fi

  grep -v '^#' "$PROGRESS_LOG" 2>/dev/null | grep -v '^$' | tail -20 | while IFS= read -r line; do
    local ts agent action detail
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

    local short_ts icon color
    short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "$ts")

    case "$agent" in
      dispatcher*)  icon="▸" ; color="$MAGENTA" ;;
      brainstormer) icon="◇" ; color="$CYAN" ;;
      planner*)     icon="□" ; color="$YELLOW" ;;
      generator*)   icon="▶" ; color="$GREEN" ;;
      eval*)        icon="✦" ; color="$RED" ;;
      user|manual)  icon="★" ; color="$BOLD" ;;
      team*)        icon="⊕" ; color="$CYAN" ;;
      *)            icon="·" ; color="$DIM" ;;
    esac

    if [ ${#detail} -gt 40 ]; then detail="${detail:0:38}.."; fi

    printf "  %b%b%b %b%-8s%b %b%s%b %b%s%b\n" \
      "$color" "$icon" "$RESET" \
      "$DIM" "$short_ts" "$RESET" \
      "$RESET" "$agent" "$RESET" \
      "$DIM" "$action" "$RESET"
    if [ -n "$detail" ] && [ "$detail" != " " ]; then
      echo -e "    ${DIM}${detail}${RESET}"
    fi
  done
}

render_audit_tail() {
  if [ ! -f "$AUDIT_LOG" ]; then return; fi

  echo ""
  echo -e "${BOLD}AUDIT${RESET}"

  grep -v '^#' "$AUDIT_LOG" 2>/dev/null | grep -v '^$' | tail -10 | while IFS= read -r line; do
    local ts agent action status target
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    status=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')
    target=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')

    local color="$RESET" icon="·"
    case "$status" in
      start)    color="$CYAN";  icon="▶" ;;
      complete) color="$GREEN"; icon="✓" ;;
      fail)     color="$RED";   icon="✗" ;;
      pass)     color="$GREEN"; icon="✓" ;;
      skip)     color="$DIM";   icon="–" ;;
    esac

    local short_ts
    short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "$ts")

    if [ ${#target} -gt 25 ]; then target="${target:0:23}.."; fi

    printf "  %b%b%b %b%s%b %-10s %b%s%b\n" \
      "$color" "$icon" "$RESET" \
      "$DIM" "$short_ts" "$RESET" \
      "$agent" \
      "$DIM" "$target" "$RESET"
  done
}

render_all() {
  render_header
  render_progress_log
  render_audit_tail
}

# ── Main loop ──
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit 0' EXIT INT TERM
clear

while true; do
  buf=$(render_all 2>&1)
  tput cup 0 0 2>/dev/null
  echo "$buf"
  tput ed 2>/dev/null
  sleep 3
done
